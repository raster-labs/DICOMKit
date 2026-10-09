// NEMA-verified: 2026a, checked 2026-10-01 — create indexes a file in place only when its path is a PS3.10 2026a 8.2/8.5 File ID, or copies it into a new File-set under assigned File IDs DICOM\PTnnnnnn\STnnnnnn\SEnnnnnn\IMnnnnnn (D131); refusals (File ID, PS3.11 2026a profile table, duplicate SOP Instance) are listed per file; the validate report prints the File-set Consistency Flag (0004,1212) per PS3.3 2026a Table F.3-3 (D128); DICOMDIR file name per PS3.10 8.6
//
// DICOMDIRWorkflow.swift
// DICOMKit
//
// Shared orchestration helpers for the `dicom-dcmdir` workflow.
//
// The `dicom-dcmdir` CLI and DICOMStudio's CLI Workshop must produce
// byte-identical output for CLI-parity. The DICOMDIR `dump` output is already
// shared through `DICOMDIRDumpFormatter`; this file does the same for the
// remaining surfaces that both call sites previously hand-mirrored:
//
//   • DICOM-file discovery (the recursive/flat scan that skips an existing
//     DICOMDIR and sorts by path),
//   • the create build-loop (read each file, compute its relative path, add it
//     to the `DICOMDirectory.Builder`), and its summary block,
//   • the `validate` report (statistics + file-set + optional record-type
//     breakdown).
//
// Both surfaces call the helpers below, so this orchestration cannot silently
// drift between them. Output WRITING (sandbox-aware on the app side) and
// argument parsing / exit-code conventions stay with each caller.
//

import Foundation
import DICOMCore

public enum DICOMDIRWorkflow {

    // MARK: - Errors

    public enum WorkflowError: Error, CustomStringConvertible {
        /// No DICOM files were found under the input directory.
        case noDICOMFiles
        public var description: String {
            switch self {
            case .noDICOMFiles: return "No DICOM files found"
            }
        }
    }

    // MARK: - Path resolution (directory ⇄ DICOMDIR file)

    /// True when `path` denotes a directory: it ends with a path separator, or it
    /// exists on disk as a directory.
    public static func isDirectoryPath(_ path: String) -> Bool {
        if path.hasSuffix("/") { return true }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Resolves a user-supplied path to the DICOMDIR *file* it refers to. A DICOMDIR
    /// is a single index file conventionally named `DICOMDIR`; when the user points at
    /// a directory (the media folder) the file is `<dir>/DICOMDIR`. Shared by every
    /// `dicom-dcmdir` subcommand so "create into a folder", "validate a folder", and
    /// "dump a folder" all work — and so a write never targets a directory path (which
    /// fails with "the file … couldn't be saved in the folder …").
    public static func resolvedDICOMDIRPath(_ path: String) -> String {
        isDirectoryPath(path) ? (path as NSString).appendingPathComponent("DICOMDIR") : path
    }

    /// URL variant of `resolvedDICOMDIRPath` — appends `DICOMDIR` when `url` is a
    /// directory (so a security-scoped folder grant is preserved), else returns it
    /// unchanged.
    public static func resolvedDICOMDIRURL(_ url: URL) -> URL {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if (exists && isDir.boolValue) || url.hasDirectoryPath {
            return url.appendingPathComponent("DICOMDIR")
        }
        return url
    }

    // MARK: - File discovery

    /// Finds the DICOM files under `directory`, skipping any existing `DICOMDIR`
    /// index file, sorted by path for deterministic ordering. Shared verbatim by
    /// the CLI's `create` and the Studio reimplementation so the file set (and its
    /// order, which fixes the directory-record order) cannot drift between them.
    public static func findDICOMFiles(in directory: URL, recursive: Bool) throws -> [URL] {
        let fm = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        var files: [URL] = []

        if recursive {
            guard let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            ) else {
                throw WorkflowError.noDICOMFiles
            }
            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                if values.isRegularFile == true, fileURL.lastPathComponent != "DICOMDIR" {
                    files.append(fileURL)
                }
            }
        } else {
            let contents = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            )
            for fileURL in contents {
                let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                if values.isRegularFile == true, fileURL.lastPathComponent != "DICOMDIR" {
                    files.append(fileURL)
                }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    // MARK: - Create

    /// A file that was not indexed, and why (a ``DICOMDIRProfileRules/Refusal`` text, or the
    /// read / record-key error).
    public struct FileFailure: Sendable, Equatable {
        /// The file, as the progress lines name it (relative to the input or media folder).
        public let file: String
        /// Why it was not indexed.
        public let reason: String
    }

    /// The outcome of building a DICOMDIR from a directory of DICOM files.
    public struct CreateResult: Sendable {
        public let directory: DICOMDirectory
        /// Files successfully added to the index.
        public let processed: Int
        /// Files that could not be added (unreadable / non-conformant).
        public let failed: Int
        /// Total candidate files discovered.
        public let total: Int
        /// Each file that was not added, with the reason (same order as discovery).
        public let failures: [FileFailure]
    }

    /// The File ID layout a File-set Creator assigns when it copies the files into a new
    /// File-set: `DICOM\PTnnnnnn\STnnnnnn\SEnnnnnn\IMnnnnnn` — five components of at
    /// most eight characters from A-Z, 0-9 (PS3.10 8.2, 8.5), numbered per parent record in
    /// the order the instances are added.
    struct ConformantLayout {
        private var patients: [String: Int] = [:]
        private var studies: [String: Int] = [:]
        private var series: [String: Int] = [:]
        private var images: [String: Int] = [:]
        private var studiesPerPatient: [String: Int] = [:]
        private var seriesPerStudy: [String: Int] = [:]

        private static func component(_ prefix: String, _ n: Int) -> String {
            prefix + String(format: "%06d", n)
        }

        private static func keys(_ ds: DataSet) -> (String, String, String) {
            let patient = ds.string(for: .patientID) ?? ""
            let study = patient + "\u{0}" + (ds.string(for: .studyInstanceUID) ?? "")
            return (patient, study, study + "\u{0}" + (ds.string(for: .seriesInstanceUID) ?? ""))
        }

        /// The File ID the next instance of `dataSet` gets (nothing is reserved yet).
        func fileID(for dataSet: DataSet) -> [String] {
            let (pk, sk, rk) = Self.keys(dataSet)
            let pn = patients[pk] ?? patients.count + 1
            let sn = studies[sk] ?? (studiesPerPatient[pk] ?? 0) + 1
            let rn = series[rk] ?? (seriesPerStudy[sk] ?? 0) + 1
            let inum = (images[rk] ?? 0) + 1
            return ["DICOM", Self.component("PT", pn), Self.component("ST", sn),
                    Self.component("SE", rn), Self.component("IM", inum)]
        }

        /// Reserves the File ID `fileID(for:)` returned, once the instance was indexed.
        mutating func commit(_ dataSet: DataSet) {
            let (pk, sk, rk) = Self.keys(dataSet)
            if patients[pk] == nil { patients[pk] = patients.count + 1 }
            if studies[sk] == nil {
                let n = (studiesPerPatient[pk] ?? 0) + 1
                studiesPerPatient[pk] = n
                studies[sk] = n
            }
            if series[rk] == nil {
                let n = (seriesPerStudy[sk] ?? 0) + 1
                seriesPerStudy[sk] = n
                series[rk] = n
            }
            images[rk, default: 0] += 1
        }
    }

    /// Builds a DICOMDIR from the DICOM files under `inputURL`, using the shared
    /// `DICOMDirectory.Builder`. The relative path stored for each file is computed
    /// the same way on both surfaces (relative to the input directory), so the two
    /// produced DICOMDIRs are byte-identical for the same input.
    ///
    /// Without `fileSetRoot` the files are indexed where they are, so each path relative to
    /// `inputURL` must already be a PS3.10 8.2 / 8.5 File ID (at most 8 components of 1-8
    /// characters A-Z, 0-9, _); a file whose path is not is refused (listed in `failures`),
    /// as is a SOP Class / Transfer Syntax the profile's PS3.11 table does not list. With
    /// `fileSetRoot` the File-set Creator assigns the File IDs instead: each accepted file is
    /// copied, byte for byte, to `<fileSetRoot>/DICOM/PTnnnnnn/STnnnnnn/SEnnnnnn/IMnnnnnn`
    /// and the DICOMDIR references that copy; the caller writes `<fileSetRoot>/DICOMDIR`.
    ///
    /// `progress` receives the human-readable verbose lines ("Found N DICOM files",
    /// the per-file "[i/n] Processing …", and any per-file failure) so the CLI can
    /// `print` them and the app can append them — identical text either way. It is
    /// only invoked when `verbose` is true.
    ///
    /// Throws `WorkflowError.noDICOMFiles` when the directory holds no DICOM files, and the
    /// file-system error when a copy into `fileSetRoot` fails (e.g. the target exists).
    public static func buildDirectory(
        fromFilesIn inputURL: URL,
        recursive: Bool,
        strict: Bool,
        fileSetID: String,
        profile: DICOMDIRProfile,
        copyingInto fileSetRoot: URL? = nil,
        verbose: Bool = false,
        progress: ((String) -> Void)? = nil
    ) throws -> CreateResult {
        let dicomFiles = try findDICOMFiles(in: inputURL, recursive: recursive)
        guard !dicomFiles.isEmpty else { throw WorkflowError.noDICOMFiles }

        if verbose { progress?("Found \(dicomFiles.count) DICOM files\n\n") }

        var builder = DICOMDirectory.Builder(fileSetID: fileSetID, profile: profile)
        var layout = ConformantLayout()
        var processed = 0
        var failures: [FileFailure] = []
        let fm = FileManager.default

        for (index, fileURL) in dicomFiles.enumerated() {
            if verbose { progress?("[\(index + 1)/\(dicomFiles.count)] Processing \(fileURL.lastPathComponent)...\n") }
            // Compute the path via standardized prefix-stripping. The old
            // `replacingOccurrences(of: inputURL.path + "/")` corrupted IDs
            // whenever the enumerator resolved a symlinked input (e.g.
            // /tmp → /private/tmp gave "privateimg0.dcm").
            let basePath = inputURL.standardizedFileURL.path + "/"
            let fullPath = fileURL.standardizedFileURL.path
            let relativePath = fullPath.hasPrefix(basePath)
                ? String(fullPath.dropFirst(basePath.count))
                : fileURL.lastPathComponent
            let fileID: [String]
            let dicomFile: DICOMFile
            do {
                let fileData = try Data(contentsOf: fileURL)
                dicomFile = try DICOMFile.read(from: fileData, force: !strict)
                fileID = fileSetRoot == nil
                    ? relativePath.components(separatedBy: "/")
                    : layout.fileID(for: dicomFile.dataSet)
                try builder.addFile(dicomFile, relativePath: fileID)
            } catch {
                let reason = describe(error)
                failures.append(FileFailure(file: relativePath, reason: reason))
                if verbose { progress?("  Failed: \(reason)\n") }
                continue
            }
            processed += 1
            if let fileSetRoot {
                layout.commit(dicomFile.dataSet)
                let target = fileID.reduce(fileSetRoot) { $0.appendingPathComponent($1) }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: fileURL, to: target)
                if verbose { progress?("  Copied to \(fileID.joined(separator: "\\"))\n") }
            }
        }

        return CreateResult(directory: builder.build(), processed: processed,
                            failed: failures.count, total: dicomFiles.count, failures: failures)
    }

    /// The text of an error: its `errorDescription` when it is a `LocalizedError`, else its
    /// `description` (a Swift error's `localizedDescription` is only "The operation couldn't
    /// be completed").
    static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let text = localized.errorDescription { return text }
        return String(describing: error)
    }

    /// Renders the create summary block, shared verbatim by the CLI and the Studio
    /// reimplementation. The returned string begins and ends with a newline so the
    /// CLI can emit it with `print(summary, terminator: "")` and the app can append
    /// it directly to its console buffer.
    public static func renderCreateSummary(_ result: CreateResult, outputPath: String) -> String {
        let stats = result.directory.statistics()
        var s = ""
        s += "\n"
        s += "✅ DICOMDIR created successfully\n"
        s += "\n"
        s += "Summary:\n"
        s += "  Files processed: \(result.processed)/\(result.total)\n"
        if result.failed > 0 { s += "  Failed: \(result.failed)\n" }
        for failure in result.failures { s += "    \(failure.file): \(failure.reason)\n" }
        s += "  Patients: \(stats.patientCount)\n"
        s += "  Studies: \(stats.studyCount)\n"
        s += "  Series: \(stats.seriesCount)\n"
        s += "  Images: \(stats.imageCount)\n"
        if stats.instanceRecordCount > stats.imageCount {
            s += "  Other instance records: \(stats.instanceRecordCount - stats.imageCount)\n"
        }
        s += "\n"
        s += "Output: \(outputPath)\n"
        return s
    }

    // MARK: - Update

    /// The outcome of updating an existing DICOMDIR with new files.
    public struct UpdateResult: Sendable {
        public let directory: DICOMDirectory
        /// Previously-referenced files re-indexed into the rebuilt directory.
        public let reindexed: Int
        /// New files added to the index.
        public let added: Int
        /// Previously-referenced files that no longer exist on disk (dropped).
        public let missing: Int
        /// Files that could not be read/added (unreadable / non-conformant).
        public let failed: Int
        /// Each file that was not added, with the reason.
        public let failures: [FileFailure]
    }

    public enum UpdateError: Error, CustomStringConvertible {
        /// A `--add` path lies outside the DICOMDIR's media folder, so no
        /// relative File ID can be recorded for it.
        case outsideMediaFolder(String)
        /// The `--add` path does not exist.
        case addPathNotFound(String)
        public var description: String {
            switch self {
            case .outsideMediaFolder(let p):
                return "Cannot add \(p): it is outside the DICOMDIR's media folder"
            case .addPathNotFound(let p):
                return "Add path not found: \(p)"
            }
        }
    }

    /// Updates an existing DICOMDIR: parses it, unions its referenced files with
    /// the DICOM files under `addPath` (a file or a directory inside the media
    /// folder), and rebuilds the index with the same file-set ID and profile.
    /// Rebuilding (rather than patching records in place) keeps the record order
    /// deterministic — identical to what `create` would produce for the same
    /// file set. Previously-referenced files that have disappeared from disk are
    /// dropped (and counted in `missing`). The caller writes the result (the CLI
    /// directly, the app via its sandbox-aware path).
    public static func updateDirectory(
        dicomdirURL: URL,
        addPath: String?,
        verbose: Bool = false,
        progress: ((String) -> Void)? = nil
    ) throws -> UpdateResult {
        let existing = try DICOMDIRReader.read(from: dicomdirURL)
        let mediaFolder = dicomdirURL.deletingLastPathComponent()

        // Existing entries: slash-joined File IDs relative to the media folder.
        var relativePaths: [String] = []
        var seen = Set<String>()
        for rel in existing.allReferencedFiles() where !seen.contains(rel) {
            seen.insert(rel)
            relativePaths.append(rel)
        }

        // New files from --add (file, or directory scanned recursively).
        if let addPath, !addPath.isEmpty {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: addPath, isDirectory: &isDir) else {
                throw UpdateError.addPathNotFound(addPath)
            }
            let addURLs: [URL] = isDir.boolValue
                ? try findDICOMFiles(in: URL(fileURLWithPath: addPath), recursive: true)
                : [URL(fileURLWithPath: addPath)]
            let basePrefix = mediaFolder.standardizedFileURL.path + "/"
            for url in addURLs {
                let full = url.standardizedFileURL.path
                guard full.hasPrefix(basePrefix) else {
                    throw UpdateError.outsideMediaFolder(url.path)
                }
                let rel = String(full.dropFirst(basePrefix.count))
                if !seen.contains(rel) {
                    seen.insert(rel)
                    relativePaths.append(rel)
                }
            }
        }

        // Deterministic record order: same sort as create's file discovery.
        relativePaths.sort()

        var builder = DICOMDirectory.Builder(fileSetID: existing.fileSetID, profile: existing.profile)
        var reindexed = 0, added = 0, missing = 0
        var failures: [FileFailure] = []
        let existingSet = Set(existing.allReferencedFiles())

        for (index, rel) in relativePaths.enumerated() {
            let fileURL = mediaFolder.appendingPathComponent(rel)
            let wasExisting = existingSet.contains(rel)
            if verbose { progress?("[\(index + 1)/\(relativePaths.count)] Processing \(rel)...\n") }
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                missing += 1
                if verbose { progress?("  Missing on disk — dropped from index\n") }
                continue
            }
            do {
                let fileData = try Data(contentsOf: fileURL)
                let dicomFile = try DICOMFile.read(from: fileData, force: true)
                try builder.addFile(dicomFile, relativePath: rel.components(separatedBy: "/"))
                if wasExisting { reindexed += 1 } else { added += 1 }
            } catch {
                let reason = describe(error)
                failures.append(FileFailure(file: rel, reason: reason))
                if verbose { progress?("  Failed: \(reason)\n") }
            }
        }

        return UpdateResult(directory: builder.build(), reindexed: reindexed,
                            added: added, missing: missing, failed: failures.count, failures: failures)
    }

    /// Renders the update summary block, shared verbatim by the CLI and the
    /// Studio reimplementation (same conventions as `renderCreateSummary`).
    public static func renderUpdateSummary(_ result: UpdateResult, outputPath: String) -> String {
        let stats = result.directory.statistics()
        var s = ""
        s += "\n"
        s += "✅ DICOMDIR updated successfully\n"
        s += "\n"
        s += "Summary:\n"
        s += "  Existing files re-indexed: \(result.reindexed)\n"
        s += "  New files added: \(result.added)\n"
        if result.missing > 0 { s += "  Missing (dropped): \(result.missing)\n" }
        if result.failed > 0 { s += "  Failed: \(result.failed)\n" }
        for failure in result.failures { s += "    \(failure.file): \(failure.reason)\n" }
        s += "  Patients: \(stats.patientCount)\n"
        s += "  Studies: \(stats.studyCount)\n"
        s += "  Series: \(stats.seriesCount)\n"
        s += "  Images: \(stats.imageCount)\n"
        if stats.instanceRecordCount > stats.imageCount {
            s += "  Other instance records: \(stats.instanceRecordCount - stats.imageCount)\n"
        }
        s += "\n"
        s += "Output: \(outputPath)\n"
        return s
    }

    // MARK: - Validate

    /// Renders the `validate` success report (everything after the "Validating …"
    /// header line), shared verbatim by the CLI and the Studio reimplementation.
    /// The caller emits the header and handles the read / validation failure paths
    /// (with its own exit-code convention); on success it emits this block.
    ///
    /// The returned string begins with the "valid" confirmation line and ends with
    /// a trailing newline so the CLI can `print(report, terminator: "")` and the
    /// app can append it directly.
    public static func renderValidationReport(_ directory: DICOMDirectory, detailed: Bool) -> String {
        let stats = directory.statistics()
        var s = ""
        s += "✅ DICOMDIR structure is valid\n"
        s += "\n"
        s += "Statistics:\n"
        s += "  Patients: \(stats.patientCount)\n"
        s += "  Studies: \(stats.studyCount)\n"
        s += "  Series: \(stats.seriesCount)\n"
        s += "  Images: \(stats.imageCount)\n"
        if stats.instanceRecordCount > stats.imageCount {
            s += "  Other instance records: \(stats.instanceRecordCount - stats.imageCount)\n"
        }
        s += "  Total records: \(stats.totalRecordCount)\n"
        s += "  Active records: \(stats.activeRecordCount)\n"
        s += "  Inactive records: \(stats.inactiveRecordCount)\n"
        s += "\n"
        s += "File-set:\n"
        s += "  ID: \(directory.fileSetID.isEmpty ? "<none>" : directory.fileSetID)\n"
        s += "  Profile: \(directory.profile.rawValue)\n"
        s += "  File-set Consistency Flag: \(DICOMDIRDumpFormatter.consistencyFlagText(directory.isConsistent))\n"

        if detailed {
            s += "\n"
            s += "Records by type:\n"
            let allRecords = directory.allRecords()
            let recordTypes = Set(allRecords.map { $0.recordType })
            for recordType in recordTypes.sorted(by: { $0.rawValue < $1.rawValue }) {
                let count = allRecords.filter { $0.recordType == recordType }.count
                s += "  \(recordType.rawValue): \(count)\n"
            }
        }

        s += "\n"
        s += "✅ Validation complete\n"
        return s
    }
}
