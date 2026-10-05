// ImportService.swift
// DICOMStudio
//
// DICOM Studio — DICOM file import service
//
// NEMA-verified: 2026a, checked 2026-10-05 — DICM prefix at offset 128 after the 128-byte File Preamble (PS3.10
// 2026a 7.1) via `ImportValidation` (G1); file extensions, copy layout and duplicate detection are not standard
// data.

import Foundation
import DICOMKit
import DICOMCore
import os.log

/// Logger for import service diagnostics.
private let logger = Logger(subsystem: "com.dicomstudio", category: "ImportService")

/// Service for importing DICOM files into the local library.
///
/// Handles file validation, metadata extraction, duplicate detection,
/// and batch import with progress tracking.
public final class ImportService: Sendable {

    /// The file service used for parsing DICOM files.
    public let fileService: DICOMFileService

    /// Optional directory to copy imported files into for persistent sandbox access.
    public let copyDirectory: URL?

    /// Creates an import service with the given file service.
    ///
    /// - Parameters:
    ///   - fileService: The DICOM file parsing service.
    ///   - copyDirectory: If set, imported files are copied here so the
    ///     app retains access after the security-scoped resource is released.
    public init(fileService: DICOMFileService = DICOMFileService(), copyDirectory: URL? = nil) {
        self.fileService = fileService
        self.copyDirectory = copyDirectory
    }

    /// Imports a single DICOM file, performing validation and metadata extraction.
    ///
    /// - Parameters:
    ///   - url: The file URL to import.
    ///   - existingInstanceUIDs: Set of already-imported SOP Instance UIDs for duplicate detection.
    /// - Returns: The import result with parsed metadata and any validation issues.
    public func importFile(
        at url: URL,
        existingInstanceUIDs: Set<String> = []
    ) -> ImportResult {
        // Try to gain sandbox access.  For direct file-picker URLs this
        // acquires the security scope; for child URLs enumerated from an
        // already-scoped parent directory it is a harmless no-op.
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        logger.info("importFile: \(url.lastPathComponent) — securityScope=\(accessed)")

        // Read raw data once — reuse it for validation *and* parsing
        // so we stay inside the security scope and avoid redundant I/O.
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.error("importFile: Cannot read \(url.lastPathComponent) — \(error.localizedDescription)")
            return ImportResult(
                sourceURL: url,
                validationIssues: [ValidationIssue(
                    severity: .error,
                    message: "Cannot read file: \(error.localizedDescription)",
                    rule: .fileSize
                )]
            )
        }
        logger.debug("importFile: Read \(data.count) bytes from \(url.lastPathComponent)")

        // Run structural validation
        var allIssues = ImportValidation.validate(data: data)

        // If structural validation found errors, don't try to parse
        if ImportValidation.shouldReject(allIssues) {
            logger.warning("importFile: Validation rejected \(url.lastPathComponent) — \(allIssues.map(\.message).joined(separator: "; "))")
            return ImportResult(sourceURL: url, validationIssues: allIssues)
        }

        // Parse the DICOM data **once** to produce all three models.
        let parsed: DICOMParseResult
        do {
            parsed = try fileService.parseAllMetadata(data: data, url: url)
        } catch {
            logger.error("importFile: Parse failed for \(url.lastPathComponent) — \(error.localizedDescription)")
            allIssues.append(ValidationIssue(
                severity: .error,
                message: "DICOM parse error: \(error.localizedDescription)",
                rule: .fileMetaInformation
            ))
            return ImportResult(sourceURL: url, validationIssues: allIssues)
        }

        let instance = parsed.instance
        let study    = parsed.study
        let series   = parsed.series

        // Copy the file into the app's managed storage so the Viewer
        // can read it later without needing the original security scope.
        var localInstance = instance
        if let copyDir = copyDirectory {
            let studyDir = copyDir.appendingPathComponent(study.studyInstanceUID, isDirectory: true)
            let fm = FileManager.default
            try? fm.createDirectory(at: studyDir, withIntermediateDirectories: true)
            let safeName = instance.sopInstanceUID.isEmpty
                ? url.lastPathComponent
                : instance.sopInstanceUID + ".dcm"
            let dest = studyDir.appendingPathComponent(safeName)
            if !fm.fileExists(atPath: dest.path) {
                do {
                    try data.write(to: dest, options: .atomic)
                    logger.info("importFile: Copied to \(dest.lastPathComponent)")
                } catch {
                    logger.warning("importFile: Copy failed — \(error.localizedDescription)")
                }
            }
            if fm.fileExists(atPath: dest.path) {
                localInstance.filePath = dest.path
            }
        }

        // Validate required tags
        let tagIssues = ImportValidation.validateRequiredTags(
            hasStudyInstanceUID: !study.studyInstanceUID.isEmpty,
            hasSOPInstanceUID: !instance.sopInstanceUID.isEmpty,
            hasSOPClassUID: !instance.sopClassUID.isEmpty
        )
        allIssues.append(contentsOf: tagIssues)

        // Validate transfer syntax
        let tsIssues = ImportValidation.validateTransferSyntax(instance.transferSyntaxUID)
        allIssues.append(contentsOf: tsIssues)

        // Check for duplicates
        let isDuplicate = existingInstanceUIDs.contains(instance.sopInstanceUID)
        if isDuplicate {
            allIssues.append(ValidationIssue(
                severity: .warning,
                message: "Duplicate SOP Instance UID: \(instance.sopInstanceUID)",
                rule: .duplicateDetection
            ))
        }

        logger.info("importFile: OK \(url.lastPathComponent) — patient=\(study.patientName ?? "?"), modality=\(series.modality), duplicate=\(isDuplicate)")
        return ImportResult(
            sourceURL: url,
            instance: localInstance,
            study: study,
            series: series,
            validationIssues: allIssues,
            isDuplicate: isDuplicate
        )
    }

    /// Imports multiple DICOM files, collecting results for each.
    ///
    /// - Parameters:
    ///   - urls: The file URLs to import.
    ///   - existingInstanceUIDs: Set of already-imported SOP Instance UIDs for duplicate detection.
    ///   - progressHandler: Optional callback invoked after each file is processed.
    /// - Returns: Array of import results, one per file.
    public func importFiles(
        at urls: [URL],
        existingInstanceUIDs: Set<String> = [],
        progressHandler: ((ImportProgress) -> Void)? = nil
    ) -> [ImportResult] {
        var results: [ImportResult] = []
        var knownUIDs = existingInstanceUIDs
        var succeeded = 0
        var failed = 0
        var duplicates = 0

        for (index, url) in urls.enumerated() {
            let result = importFile(at: url, existingInstanceUIDs: knownUIDs)
            results.append(result)

            if result.succeeded {
                if result.isDuplicate {
                    duplicates += 1
                } else {
                    succeeded += 1
                    if let uid = result.instance?.sopInstanceUID {
                        knownUIDs.insert(uid)
                    }
                }
            } else {
                failed += 1
            }

            progressHandler?(ImportProgress(
                totalFiles: urls.count,
                processedFiles: index + 1,
                succeededFiles: succeeded,
                failedFiles: failed,
                duplicateFiles: duplicates
            ))
        }

        return results
    }

    /// Scans a directory for DICOM files (non-recursive by default).
    ///
    /// Recognised files:
    /// - `.dcm`, `.dicom`, `.dic` extensions
    /// - Files with **no** extension (common on CD/DVD media)
    /// - Files whose first 132 bytes contain the DICM magic (catches
    ///   numeric-name files like `IM000001` produced by many PACS)
    ///
    /// > **Security note:** The caller is responsible for holding
    /// > security-scoped resource access on `directoryURL` if the
    /// > app is sandboxed.  `handleImportedURLs` keeps the parent
    /// > scope alive for the full duration of the import.
    ///
    /// - Parameters:
    ///   - directoryURL: The directory to scan.
    ///   - recursive: Whether to scan subdirectories.
    /// - Returns: Array of file URLs that may be DICOM files.
    public func scanDirectory(
        at directoryURL: URL,
        recursive: Bool = false
    ) -> [URL] {
        logger.info("scanDirectory: \(directoryURL.path) recursive=\(recursive)")
        let fm = FileManager.default
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        if !recursive {
            options.insert(.skipsSubdirectoryDescendants)
        }

        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: options
        ) else {
            logger.error("scanDirectory: FileManager.enumerator returned nil for \(directoryURL.path)")
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()

            // Fast path: known DICOM extensions or no extension at all.
            if ext == "dcm" || ext == "dicom" || ext == "dic" || ext.isEmpty {
                urls.append(url)
                continue
            }

            // Slow path: files with an unrecognised extension may still be
            // DICOM (e.g. IM000001, CT.1, 0001).  Probe the first 132 bytes
            // for the DICM magic signature.
            if let fileSize = values?.fileSize, fileSize >= ImportValidation.minimumFileSize,
               let handle = try? FileHandle(forReadingFrom: url) {
                defer { try? handle.close() }
                if let header = try? handle.read(upToCount: ImportValidation.minimumFileSize),
                   ImportValidation.hasDICMMagic(header) {
                    urls.append(url)
                }
            }
        }
        logger.info("scanDirectory: Found \(urls.count) candidate files in \(directoryURL.lastPathComponent)")
        return urls
    }
}
