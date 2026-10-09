// NEMA-verified: 2026a, checked 2026-10-01 — compared with PS3.10 2026a 7.1 / Table 7.1-1: storeReceived writes the 128-byte preamble, "DICM" and the File Meta Information through DICOMFile.create/write (the 6 Type 1 elements (0002,0000)/(0002,0001)/(0002,0002)/(0002,0003)/(0002,0010)/(0002,0012) and 4 Type 3: (0002,0013) and the (0002,0016)/(0002,0017)/(0002,0018) AE Titles) with the negotiated Transfer Syntax UID, then the data set as received (D102 closed); otherwise directory-layout plumbing
import Foundation
import DICOMCore
import DICOMKit

/// Storage manager for DICOM files
actor StorageManager {
    private let dataDirectory: String
    private let fileManager = FileManager.default
    
    init(dataDirectory: String) throws {
        self.dataDirectory = dataDirectory
        
        // Create data directory if it doesn't exist
        try fileManager.createDirectory(
            atPath: dataDirectory,
            withIntermediateDirectories: true
        )
    }
    
    /// Store a DICOM file
    func store(file: DICOMFile) async throws -> String {
        let studyUID = file.dataSet.string(for: .studyInstanceUID) ?? "UNKNOWN_STUDY"
        let seriesUID = file.dataSet.string(for: .seriesInstanceUID) ?? "UNKNOWN_SERIES"
        let instanceUID = file.dataSet.string(for: .sopInstanceUID) ?? UUID().uuidString
        let filePath = try instancePath(studyUID: studyUID, seriesUID: seriesUID, sopInstanceUID: instanceUID)
        let data = try file.write()
        try data.write(to: URL(fileURLWithPath: filePath))
        return filePath
    }

    /// A received instance written as a PS3.10 file
    struct StoredInstance: Sendable {
        let filePath: String
        /// The data set decoded in the negotiated transfer syntax
        let dataSet: DataSet
        let transferSyntaxUID: String
        let size: Int
    }

    /// Stores a data set received by C-STORE as a DICOM Part 10 file.
    ///
    /// PS3.10 7.1: 128-byte preamble, "DICM", File Meta Information (Table 7.1-1) built by
    /// `DICOMFile.create` with the Affected SOP Class / Instance UID of the request as Media
    /// Storage SOP Class / Instance UID and the presentation context's Transfer Syntax UID,
    /// then the data set bytes exactly as received (they are already encoded in that syntax).
    /// The data set is decoded with the same transfer syntax for indexing.
    func storeReceived(
        dataSetData: Data,
        sopClassUID: String,
        sopInstanceUID: String,
        transferSyntaxUID: String,
        serverAETitle: String,
        callingAETitle: String?
    ) async throws -> StoredInstance {
        let dataSet = try ServerProtocol.decodeDataSet(dataSetData, transferSyntaxUID: transferSyntaxUID)
        let meta = ServerProtocol.fileMetaInformation(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            transferSyntaxUID: transferSyntaxUID,
            serverAETitle: serverAETitle,
            callingAETitle: callingAETitle
        )
        var fileData = ServerProtocol.partTenHeader(fileMeta: meta)
        guard !fileData.isEmpty else {
            throw ServerError.storageError("Could not encode File Meta Information for \(sopInstanceUID)")
        }
        fileData.append(dataSetData)

        let filePath = try instancePath(
            studyUID: dataSet.string(for: .studyInstanceUID) ?? "UNKNOWN_STUDY",
            seriesUID: dataSet.string(for: .seriesInstanceUID) ?? "UNKNOWN_SERIES",
            sopInstanceUID: sopInstanceUID
        )
        try fileData.write(to: URL(fileURLWithPath: filePath))
        return StoredInstance(filePath: filePath, dataSet: dataSet,
                              transferSyntaxUID: transferSyntaxUID, size: fileData.count)
    }

    /// `<data dir>/<Study UID>/<Series UID>/<SOP Instance UID>.dcm`, creating the directories.
    ///
    /// UIDs are digits and periods (PS3.5 9.1); any other character is replaced so a
    /// received value cannot name a path outside the data directory.
    private func instancePath(studyUID: String, seriesUID: String, sopInstanceUID: String) throws -> String {
        let seriesPath = "\(dataDirectory)/\(Self.pathComponent(studyUID))/\(Self.pathComponent(seriesUID))"
        try fileManager.createDirectory(atPath: seriesPath, withIntermediateDirectories: true)
        return "\(seriesPath)/\(Self.pathComponent(sopInstanceUID)).dcm"
    }

    static func pathComponent(_ value: String) -> String {
        let safe = String(value.map { $0.isASCII && ($0.isNumber || $0.isLetter || $0 == "." || $0 == "_" || $0 == "-") ? $0 : "_" })
        if safe.isEmpty || safe.allSatisfy({ $0 == "." }) { return "_" }
        return safe
    }
    
    /// Retrieve a DICOM file by SOP Instance UID
    func retrieve(sopInstanceUID: String) async throws -> DICOMFile? {
        // Search for the file
        let filePath = try await findFile(sopInstanceUID: sopInstanceUID)
        guard let path = filePath else {
            return nil
        }
        
        return try DICOMFile.read(from: URL(fileURLWithPath: path))
    }
    
    /// Find a file by SOP Instance UID
    private func findFile(sopInstanceUID: String) async throws -> String? {
        // Scan directories
        guard let enumerator = fileManager.enumerator(atPath: dataDirectory) else {
            return nil
        }
        
        while let file = enumerator.nextObject() as? String {
            if file.hasSuffix(".dcm") {
                let fullPath = "\(dataDirectory)/\(file)"
                
                // Read file and check SOP Instance UID
                do {
                    let dicomFile = try DICOMFile.read(from: URL(fileURLWithPath: fullPath))
                    if dicomFile.dataSet.string(for: .sopInstanceUID) == sopInstanceUID {
                        return fullPath
                    }
                } catch {
                    // Skip files that can't be read
                    continue
                }
            }
        }
        
        return nil
    }
    
    /// Get storage statistics
    func statistics() async throws -> StorageStatistics {
        var totalFiles = 0
        var totalSize: UInt64 = 0
        
        guard let enumerator = fileManager.enumerator(atPath: dataDirectory) else {
            return StorageStatistics(totalFiles: 0, totalSize: 0)
        }
        
        while let file = enumerator.nextObject() as? String {
            if file.hasSuffix(".dcm") {
                totalFiles += 1
                let fullPath = "\(dataDirectory)/\(file)"
                if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                   let size = attrs[.size] as? UInt64 {
                    totalSize += size
                }
            }
        }
        
        return StorageStatistics(totalFiles: totalFiles, totalSize: totalSize)
    }
}

/// Storage statistics
struct StorageStatistics: Sendable {
    let totalFiles: Int
    let totalSize: UInt64
    
    var totalSizeMB: Double {
        Double(totalSize) / (1024 * 1024)
    }
}
