// NEMA-verified: 2026a, checked 2026-10-01 — groups files by Study Instance UID and Series Instance UID (the Q/R unique keys, PS3.4 2026a Tables C.6-2 / C.6-3) and names folders from 6 attributes (Patient's Name, Study Description, Study Instance UID, Series Number, Modality, Series Description; Modality default OT per PS3.3 C.7.3.1.1.1); a file without Study / Series Instance UID (Type 1, PS3.3 Tables C.7-3, C.7-5a) is skipped with a warning; descriptive folder names that collide (Series Number is Type 2, Table C.7-5a) are suffixed with the Instance UID
import Foundation
import DICOMCore
import DICOMDictionary

// Shared study-organize engine for the `dicom-study organize` CLI and DICOMStudio.
// Joins the already-shared StudyScanner / StudyReport so EVERY dicom-study
// subcommand (summary/check/stats/compare AND organize) runs the exact same code
// and produces text-exact output. No ArgumentParser / printing here — verbose
// progress + the summary flow through the injected `log` closure; the adapters
// route it to stdout (CLI) or the console (app). copyItem/moveItem are used
// directly, so re-running over an existing tree raises the same "already exists"
// error in both adapters (parity).

/// Organizes a directory of DICOM files into a Patient/Study/Series tree.
public struct StudyOrganizer {
    public init() {}

    private struct SeriesGroup {
        let seriesNumber: String?
        let seriesDescription: String?
        let modality: String?
        var filePaths: [String] = []
    }
    private struct StudyGroup {
        let studyDescription: String?
        let patientName: String?
        var series: [String: SeriesGroup] = [:]
        var seriesOrder: [String] = []
    }

    /// Organizes `inputPath` into `outputPath`. `pattern` is "descriptive" or "uid".
    /// `copy` copies (else moves). Verbose per-file lines + the final summary are
    /// emitted via `log`. Throws `StudyError` for bad input and propagates the
    /// FileManager error (e.g. "already exists") if a destination already exists.
    @discardableResult
    public func organize(
        inputPath: String,
        outputPath: String,
        pattern: String,
        copy: Bool,
        verbose: Bool,
        log: (String) -> Void
    ) throws -> (copied: Int, studies: Int) {
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw StudyError.directoryNotFound(inputPath)
        }
        guard pattern == "descriptive" || pattern == "uid" else {
            throw StudyError.invalidPattern(pattern)
        }

        if verbose { log("Scanning directory: \(inputPath)") }

        let dicomFiles = collectDICOMFiles(at: inputPath)
        if dicomFiles.isEmpty { throw StudyError.noFilesFound }

        if verbose {
            log("Found \(dicomFiles.count) DICOM files")
            log("Organizing files...")
        }

        // Group by study → series, preserving first-encounter order over the
        // sorted file list (deterministic across CLI and app).
        var studies: [String: StudyGroup] = [:]
        var studyOrder: [String] = []
        for filePath in dicomFiles {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                  let file = try? DICOMFile.read(from: data) else {
                if verbose { log("Warning: Failed to read \(filePath)") }
                continue
            }
            let ds = file.dataSet
            guard let studyUID = ds.string(for: Tag.studyInstanceUID), !studyUID.isEmpty else {
                if verbose { log("Warning: Missing StudyInstanceUID in \(filePath)") }
                continue
            }
            // Series Instance UID is Type 1 (PS3.3 Table C.7-5a): a file without it cannot be
            // placed in a series, so it is reported and left where it is instead of being
            // merged with every other such file into one placeholder series.
            guard let seriesUID = ds.string(for: Tag.seriesInstanceUID), !seriesUID.isEmpty else {
                log("Warning: Missing Series Instance UID (0020,000E) in \(filePath); not organized")
                continue
            }
            if studies[studyUID] == nil {
                studies[studyUID] = StudyGroup(
                    studyDescription: ds.string(for: Tag.studyDescription),
                    patientName: ds.string(for: Tag.patientName))
                studyOrder.append(studyUID)
            }
            if studies[studyUID]!.series[seriesUID] == nil {
                studies[studyUID]!.series[seriesUID] = SeriesGroup(
                    seriesNumber: ds.string(for: Tag.seriesNumber),
                    seriesDescription: ds.string(for: Tag.seriesDescription),
                    modality: ds.string(for: Tag.modality))
                studies[studyUID]!.seriesOrder.append(seriesUID)
            }
            studies[studyUID]!.series[seriesUID]!.filePaths.append(filePath)
        }

        try FileManager.default.createDirectory(atPath: outputPath, withIntermediateDirectories: true)

        // Descriptive folder names are not unique keys: two studies may share Patient's Name,
        // Study Description and the last 8 UID characters, and two series may share Series
        // Number (Type 2, PS3.3 Table C.7-5a; absent → "0"), Modality and Series Description.
        // A name used by more than one study (series) gets the full Study (Series) Instance
        // UID appended, so every Q/R entity (PS3.4 Tables C.6-2 / C.6-3) has its own folder.
        var studyDirNames: [String: String] = [:]
        if pattern == "descriptive" {
            studyDirNames = Self.uniqueNames(studyOrder.map { uid -> (String, String) in
                let study = studies[uid]!
                let desc = study.studyDescription ?? "Unknown"
                let pn = study.patientName ?? "Unknown"
                return (uid, sanitizeFilename("\(pn)_\(desc)_\(uid.suffix(8))"))
            }, sanitize: sanitizeFilename)
        }

        var copiedCount = 0
        for studyUID in studyOrder {
            guard let study = studies[studyUID] else { continue }
            let studyDirName = pattern == "descriptive" ? studyDirNames[studyUID]! : studyUID
            let studyDir = "\(outputPath)/\(studyDirName)"
            try FileManager.default.createDirectory(atPath: studyDir, withIntermediateDirectories: true)

            var seriesDirNames: [String: String] = [:]
            if pattern == "descriptive" {
                seriesDirNames = Self.uniqueNames(study.seriesOrder.map { uid -> (String, String) in
                    let series = study.series[uid]!
                    let num = series.seriesNumber ?? "0"
                    let desc = series.seriesDescription ?? "Unknown"
                    // "XX" is not a DICOM code; OT (Other) is the standard unknown.
                    let mod = series.modality ?? Modality.ot.rawValue
                    return (uid, sanitizeFilename("\(num)_\(mod)_\(desc)"))
                }, sanitize: sanitizeFilename)
            }

            for seriesUID in study.seriesOrder {
                guard let series = study.series[seriesUID] else { continue }
                let seriesDirName = pattern == "descriptive" ? seriesDirNames[seriesUID]! : seriesUID
                let seriesDir = "\(studyDir)/\(seriesDirName)"
                try FileManager.default.createDirectory(atPath: seriesDir, withIntermediateDirectories: true)

                for (index, filePath) in series.filePaths.enumerated() {
                    let destPath = "\(seriesDir)/\(index + 1).dcm"
                    // copyItem/moveItem throw if destPath exists — re-running over an
                    // existing tree errors identically in the CLI and the app.
                    if copy {
                        try FileManager.default.copyItem(atPath: filePath, toPath: destPath)
                    } else {
                        try FileManager.default.moveItem(atPath: filePath, toPath: destPath)
                    }
                    copiedCount += 1
                    if verbose {
                        log("  \(copy ? "Copied" : "Moved"): \(URL(fileURLWithPath: filePath).lastPathComponent) → \(destPath)")
                    }
                }
            }
        }

        log("\(copy ? "Copied" : "Moved") \(copiedCount) files to \(outputPath)")
        log("Organized \(studyOrder.count) studies")
        return (copiedCount, studyOrder.count)
    }

    // MARK: - Helpers

    /// Maps each (uid, name) to its name, or to `name_uid` when another uid has the same name.
    static func uniqueNames(_ entries: [(uid: String, name: String)], sanitize: (String) -> String) -> [String: String] {
        var count: [String: Int] = [:]
        for e in entries { count[e.name, default: 0] += 1 }
        var result: [String: String] = [:]
        for e in entries {
            result[e.uid] = count[e.name]! > 1 ? sanitize("\(e.name)_\(e.uid)") : e.name
        }
        return result
    }

    /// All DICOM files under `path`, sorted by path for deterministic ordering.
    private func collectDICOMFiles(at path: String) -> [String] {
        var dicomFiles: [String] = []
        let fm = FileManager.default
        let enumerator = fm.enumerator(atPath: path)
        while let file = enumerator?.nextObject() as? String {
            let filePath = "\(path)/\(file)"
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: filePath, isDirectory: &isDirectory),
               !isDirectory.boolValue,
               file.hasSuffix(".dcm") || isDICOMFile(filePath) {
                dicomFiles.append(filePath)
            }
        }
        return dicomFiles.sorted()
    }

    private func isDICOMFile(_ path: String) -> Bool {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? fileHandle.close() }
        guard let data = try? fileHandle.read(upToCount: 132), data.count >= 132 else { return false }
        return data.subdata(in: 128..<132) == Data([0x44, 0x49, 0x43, 0x4D]) // "DICM"
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
}
