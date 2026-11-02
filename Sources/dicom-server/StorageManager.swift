// NEMA-verified: 2026a, checked 2026-10-01 — received instances retain PS3.10 7.1 File Meta Information and the negotiated data set bytes; filesystem persistence and restart indexing are application behavior.
import Foundation
import DICOMCore
import DICOMKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Durable Part 10 files. An in-memory catalogue prevents conflicting UID
/// publications; it is rebuilt deterministically from the files on startup.
actor StorageManager {
    private let root: URL
    private let fileManager = FileManager.default
    private var pathsByUID: [String: String] = [:]
    private var catalogueReady = false
    private var lockDescriptor: Int32 = -1

    init(dataDirectory: String) throws {
        let requested = URL(fileURLWithPath: dataDirectory)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: true)
        #if canImport(Darwin) || canImport(Glibc)
        var info = stat()
        guard lstat(requested.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
            throw ServerError.storageError("Storage root must be a directory, not a symbolic link: \(requested.path)")
        }
        // Foundation may deliberately retain macOS /var aliases even in
        // resolvingSymlinksInPath(). realpath supplies the actual absolute root.
        guard let resolved = realpath(requested.path, nil) else {
            throw ServerError.storageError("Cannot resolve storage root: \(requested.path)")
        }
        defer { free(resolved) }
        root = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        #else
        throw ServerError.storageError("Durable filesystem storage is unavailable on this platform")
        #endif
    }

    deinit {
        #if canImport(Darwin) || canImport(Glibc)
        if lockDescriptor >= 0 { close(lockDescriptor) }
        #endif
    }

    /// Prevent two server processes from serving divergent indexes of one root.
    func acquireExclusiveAccess() throws {
        guard lockDescriptor < 0 else { return }
        #if canImport(Darwin) || canImport(Glibc)
        let path = root.appendingPathComponent(".dicomkit-server.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw ServerError.storageError("Cannot open storage lock: \(path)") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw ServerError.storageError("Storage directory is already in use by another server: \(root.path)")
        }
        lockDescriptor = descriptor
        #else
        throw ServerError.storageError("Exclusive durable storage is unavailable on this platform")
        #endif
    }

    func releaseExclusiveAccess() {
        #if canImport(Darwin) || canImport(Glibc)
        if lockDescriptor >= 0 { close(lockDescriptor); lockDescriptor = -1 }
        #endif
    }

    /// Scan only regular .dcm files, in lexical path order. Never follow links,
    /// skip an unreadable directory, or expose a partially rebuilt catalogue.
    func scanForIndex() throws -> [DICOMMetadata] {
        catalogueReady = false
        var records: [DICOMMetadata] = []
        var candidate: [String: String] = [:]
        func visit(_ directory: URL) throws {
            try Self.verifyDirectory(directory)
            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey], options: [])
                    .sorted { $0.path < $1.path }
            } catch { throw ServerError.storageError("Reindex could not read directory \(directory.path): \(error)") }
            for url in children {
                let info = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
                guard info.isSymbolicLink != true else { throw ServerError.storageError("Reindex refuses symbolic link: \(url.path)") }
                if info.isDirectory == true { try visit(url); continue }
                guard url.pathExtension.lowercased() == "dcm" else { continue }
                guard info.isRegularFile == true else { throw ServerError.storageError("Reindex requires a regular DICOM file: \(url.path)") }
                let metadata: DICOMMetadata
                do {
                    try Self.verifyIndexedFile(at: url.path)
                    metadata = try Self.metadata(from: Data(contentsOf: url), path: url.path)
                } catch { throw ServerError.storageError("Reindex rejected \(url.path): \(error)") }
                if let prior = candidate[metadata.sopInstanceUID] {
                    throw ServerError.storageError("Reindex found duplicate SOP Instance UID \(metadata.sopInstanceUID): \(prior) and \(url.path)")
                }
                candidate[metadata.sopInstanceUID] = url.path
                records.append(metadata)
            }
        }
        try Self.verifyDirectory(root)
        try visit(root)
        pathsByUID = candidate
        catalogueReady = true
        return records
    }

    static func verifyIndexedFile(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        do {
            try verifyNoSymbolicLinks(url)
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            let permissions = (try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
            guard info.isRegularFile == true, info.isSymbolicLink != true,
                  permissions & 0o444 != 0, FileManager.default.isReadableFile(atPath: path) else {
                throw ServerError.storageError("Stored file is not a readable regular file: \(path)")
            }
        } catch { throw ServerError.storageError("Stored file missing or unreadable at \(path): \(error)") }
    }

    private static func verifyNoSymbolicLinks(_ url: URL) throws {
        #if canImport(Darwin) || canImport(Glibc)
        // Keep the canonical spelling supplied by realpath. Foundation URL
        // standardization/resolution may reintroduce platform alias paths.
        var current = ""
        for component in url.path.split(separator: "/") {
            guard component != ".", component != ".." else {
                throw ServerError.storageError("Stored path is not canonical: \(url.path)")
            }
            current += "/" + component
            var info = stat()
            guard lstat(current, &info) == 0 else {
                throw ServerError.storageError("Stored path missing or unreadable: \(current)")
            }
            guard (info.st_mode & S_IFMT) != S_IFLNK else {
                throw ServerError.storageError("Stored path traverses a symbolic link: \(current)")
            }
        }
        #else
        throw ServerError.storageError("Durable filesystem storage is unavailable on this platform")
        #endif
    }

    private static func verifyDirectory(_ url: URL) throws {
        try verifyNoSymbolicLinks(url)
        let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let permissions = (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard info.isDirectory == true, info.isSymbolicLink != true, permissions & 0o444 != 0, permissions & 0o111 != 0 else {
            throw ServerError.storageError("Storage directory missing or unsafe: \(url.path)")
        }
    }

    private static func metadata(from data: Data, path: String) throws -> DICOMMetadata {
        guard data.count >= 132, data[128..<132] == Data("DICM".utf8) else {
            throw ServerError.storageError("Not a Part 10 DICOM file")
        }
        let file = try DICOMFile.read(from: data)
        let ds = file.dataSet, meta = file.fileMetaInformation
        guard let instance = ds.string(for: .sopInstanceUID), DICOMValueRules.isValidUID(instance),
              let sopClass = ds.string(for: .sopClassUID), DICOMValueRules.isValidUID(sopClass),
              meta.string(for: .mediaStorageSOPInstanceUID) == instance,
              meta.string(for: .mediaStorageSOPClassUID) == sopClass,
              let syntax = meta.string(for: .transferSyntaxUID), DICOMValueRules.isValidUID(syntax) else {
            throw ServerError.storageError("Missing, invalid or conflicting SOP/transfer-syntax identity")
        }
        try StoredFileEnvelope.validate(data, transferSyntaxUID: syntax)
        for tag in [Tag.studyInstanceUID, .seriesInstanceUID] {
            if let uid = ds.string(for: tag), !DICOMValueRules.isValidUID(uid) {
                throw ServerError.storageError("Invalid hierarchy UID \(tag)")
            }
        }
        return DICOMMetadata(dataSet: ds, filePath: path, transferSyntaxUID: syntax)
    }

    func store(file: DICOMFile) async throws -> String {
        let data = try file.write()
        let metadata = try Self.metadata(from: data, path: "")
        return try publish(data, studyUID: metadata.studyInstanceUID ?? "UNKNOWN_STUDY",
            seriesUID: metadata.seriesInstanceUID ?? "UNKNOWN_SERIES", sopInstanceUID: metadata.sopInstanceUID)
    }

    struct StoredInstance: Sendable {
        let filePath: String
        let dataSet: DataSet
        let transferSyntaxUID: String
        let size: Int
    }

    /// Retains the received data set bytes in their negotiated transfer syntax.
    func storeReceived(dataSetData: Data, sopClassUID: String, sopInstanceUID: String,
                       transferSyntaxUID: String, serverAETitle: String, callingAETitle: String?) async throws -> StoredInstance {
        let dataSet = try ServerProtocol.decodeDataSet(dataSetData, transferSyntaxUID: transferSyntaxUID)
        let meta = ServerProtocol.fileMetaInformation(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID,
            transferSyntaxUID: transferSyntaxUID, serverAETitle: serverAETitle, callingAETitle: callingAETitle)
        var fileData = ServerProtocol.partTenHeader(fileMeta: meta)
        guard !fileData.isEmpty else { throw ServerError.storageError("Could not encode File Meta Information for \(sopInstanceUID)") }
        fileData.append(dataSetData)
        let metadata = try Self.metadata(from: fileData, path: "")
        let filePath = try publish(fileData, studyUID: metadata.studyInstanceUID ?? "UNKNOWN_STUDY",
            seriesUID: metadata.seriesInstanceUID ?? "UNKNOWN_SERIES", sopInstanceUID: sopInstanceUID)
        return StoredInstance(filePath: filePath, dataSet: dataSet, transferSyntaxUID: transferSyntaxUID, size: fileData.count)
    }

    /// Write and sync a temporary file, then atomically create its final name
    /// without overwriting an existing instance. Interrupted temporary files are
    /// not .dcm files and cannot enter the startup index.
    private func publish(_ data: Data, studyUID: String, seriesUID: String, sopInstanceUID: String) throws -> String {
        if !catalogueReady { _ = try scanForIndex() }
        let target = try instanceURL(studyUID: studyUID, seriesUID: seriesUID, sopInstanceUID: sopInstanceUID)
        if let prior = pathsByUID[sopInstanceUID] {
            guard prior == target.path else { throw ServerError.storageError("Duplicate SOP Instance UID \(sopInstanceUID) already stored at \(prior)") }
            try Self.verifyIndexedFile(at: prior)
            let existing = try ServerProtocol.readStoredFile(Data(contentsOf: target))
            let incoming = try ServerProtocol.readStoredFile(data)
            guard existing.transferSyntaxUID == incoming.transferSyntaxUID,
                  existing.sopClassUID == incoming.sopClassUID,
                  existing.sopInstanceUID == incoming.sopInstanceUID,
                  existing.dataSetData == incoming.dataSetData else {
                throw ServerError.storageError("Conflicting content for existing SOP Instance UID \(sopInstanceUID); original file preserved")
            }
            return prior // Identical data set/syntax is idempotent, even if source AE File Meta differs.
        }
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".dicomkit-upload-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
        // link() publication is atomic and fails if the destination already exists.
        try fileManager.linkItem(at: temporary, to: target)
        #if canImport(Darwin) || canImport(Glibc)
        let directory = open(target.deletingLastPathComponent().path, O_RDONLY)
        if directory >= 0 { _ = fsync(directory); close(directory) }
        #endif
        pathsByUID[sopInstanceUID] = target.path
        return target.path
    }

    private func instanceURL(studyUID: String, seriesUID: String, sopInstanceUID: String) throws -> URL {
        try Self.verifyDirectory(root)
        var directory = root
        for component in [studyUID, seriesUID] {
            directory.appendPathComponent(Self.pathComponent(component), isDirectory: true)
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
            }
            try Self.verifyDirectory(directory)
        }
        return directory.appendingPathComponent(Self.pathComponent(sopInstanceUID) + ".dcm")
    }

    static func pathComponent(_ value: String) -> String {
        let safe = String(value.map { $0.isASCII && ($0.isNumber || $0.isLetter || $0 == "." || $0 == "_" || $0 == "-") ? $0 : "_" })
        if safe.isEmpty || safe.allSatisfy({ $0 == "." }) { return "_" }
        return safe
    }

    func retrieve(sopInstanceUID: String) async throws -> DICOMFile? {
        if !catalogueReady { _ = try scanForIndex() }
        guard let path = pathsByUID[sopInstanceUID] else { return nil }
        try Self.verifyIndexedFile(at: path)
        return try DICOMFile.read(from: URL(fileURLWithPath: path))
    }

    func statistics() async throws -> StorageStatistics {
        let records = try scanForIndex()
        var size: UInt64 = 0
        for record in records {
            let attributes = try fileManager.attributesOfItem(atPath: record.filePath)
            size += (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        }
        return StorageStatistics(totalFiles: records.count, totalSize: size)
    }
}

struct StorageStatistics: Sendable {
    let totalFiles: Int
    let totalSize: UInt64
    var totalSizeMB: Double { Double(totalSize) / (1024 * 1024) }
}
