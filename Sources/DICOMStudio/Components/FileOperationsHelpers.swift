// FileOperationsHelpers.swift
// DICOMStudio
//
// DICOM Studio — Helper enums for File Operations & Drag-and-Drop (Milestone 22)
//
// NEMA-verified: 2026a, checked 2026-10-05 — DICM prefix at bytes 128–131 after the 128-byte File Preamble (PS3.10
// 2026a 7.1); the preamble-less fallback accepting a leading group 0002/0008 tag is a heuristic, not standard;
// `isUnusualTransferSyntax`: the 13 UIDs are PS3.6 2026a Table A-1 Transfer Syntax rows — their comment names are
// corrected by the codec pass and not claimed here; `formattedPatientName` reads PN components (PS3.5 2026a
// 6.2.1.1); file extensions are not standard data.

import Foundation
import DICOMCore

// MARK: - DICOMFileDropHelpers

/// Helpers for file drop zone behaviour: DICOM validation, icon names, and list management.
public enum DICOMFileDropHelpers {

    // MARK: Accepted extensions

    /// File extensions accepted by the DICOM drop zone.
    public static let acceptedExtensions: Set<String> = ["dcm", "dicom", "DCM", "DICOM"]

    /// Returns `true` when the file URL has a DICOM-compatible extension or no extension.
    public static func hasAcceptedExtension(_ url: URL) -> Bool {
        let ext = url.pathExtension
        return ext.isEmpty || acceptedExtensions.contains(ext)
    }

    // MARK: DICOM magic-byte detection

    /// Validates that `data` contains the "DICM" magic at byte offset 128.
    ///
    /// The DICOM standard (PS3.10 §7.1) specifies a 128-byte preamble followed by
    /// the four ASCII bytes D, I, C, M.  Files without a preamble (ACR-NEMA) are
    /// still considered DICOM when they begin with a valid group-2 tag.
    ///
    /// - Parameter data: The first 132+ bytes of the file.
    /// - Returns: `.valid` if the magic is present, `.validWithoutPreamble` if the
    ///   file starts with a plausible implicit DICOM tag, otherwise `.notDICOM`.
    public static func validateMagicBytes(_ data: Data) -> FileValidationResult {
        guard data.count >= 132 else {
            return .notDICOM
        }
        let magic = data[128..<132]
        if magic == Data([0x44, 0x49, 0x43, 0x4D]) { // "DICM"
            return .valid
        }
        // Heuristic for ACR-NEMA / implicit preamble-less DICOM:
        // The first two bytes should be a low-numbered group tag (group 0002 or 0008).
        let group = UInt16(data[0]) | (UInt16(data[1]) << 8)
        if group == 0x0002 || group == 0x0008 {
            return .validWithoutPreamble
        }
        return .notDICOM
    }

    // MARK: Modality icon names

    /// Returns the SF Symbol name that best represents the given DICOM modality code.
    ///
    /// Delegates to ``ModalityMapping/systemImage(for:)`` so the app has one
    /// icon map rather than two that disagree. This previously carried its own
    /// switch over nine codes, including the non-DICOM spelling `XR`, which now
    /// resolves as an alias of `DX`.
    public static func symbolName(for modality: String?) -> String {
        guard let modality, !modality.isEmpty,
              ModalityMapping.category(for: modality) != .other
                || Modality.normalized(modality) != nil
        else { return "cross.case" }
        return ModalityMapping.systemImage(for: modality)
    }

    // MARK: File size formatting

    /// Returns a human-readable file size string (e.g. "1.2 MB").
    public static func formattedFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// The threshold in bytes above which a file is considered "very large" (1 GB).
    public static let veryLargeFileThreshold: Int64 = 1_073_741_824

    /// Returns `true` when the file exceeds the very-large threshold.
    public static func isVeryLarge(_ bytes: Int64) -> Bool {
        bytes >= veryLargeFileThreshold
    }

    // MARK: List management helpers

    /// Moves the item at `fromIndex` to `toIndex` in the given array.
    ///
    /// Out-of-range indices are silently ignored.
    public static func move<T>(items: inout [T], fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex,
              items.indices.contains(fromIndex),
              items.indices.contains(toIndex) else { return }
        let item = items.remove(at: fromIndex)
        items.insert(item, at: toIndex)
    }

    /// Removes the item at `index` from the given array, returning the removed item.
    ///
    /// Returns `nil` when the index is out of range.
    @discardableResult
    public static func remove<T>(from items: inout [T], at index: Int) -> T? {
        guard items.indices.contains(index) else { return nil }
        return items.remove(at: index)
    }
}

// MARK: - OutputPathHelpers

/// Helpers for resolving output paths and generating filenames.
public enum OutputPathHelpers {

    // MARK: Auto-generated filename

    /// Returns the auto-generated output filename for the given tool and input file URL.
    ///
    /// For example, `dicom-anon` with input `scan.dcm` → `scan_anonymized.dcm`.
    public static func suggestedFilename(for toolName: String, input: URL) -> String {
        let base = input.deletingPathExtension().lastPathComponent
        let ext  = input.pathExtension
        let dotExt = ext.isEmpty ? "" : ".\(ext)"
        switch toolName {
        case "dicom-convert":   return "\(base)_converted\(dotExt)"
        case "dicom-anon":      return "\(base)_anonymized\(dotExt)"
        case "dicom-json":      return "\(base).json"
        case "dicom-xml":       return "\(base).xml"
        case "dicom-compress":  return "\(base)_compressed\(dotExt)"
        case "dicom-split":     return "\(base)_split"
        case "dicom-merge":     return "merged\(dotExt)"
        case "dicom-image":     return "\(base).png"
        case "dicom-pdf":       return "\(base).pdf"
        default:                return "\(base)_output\(dotExt)"
        }
    }

    // MARK: Output directory resolution

    /// Resolves the output directory according to the priority rules from the technical notes.
    ///
    /// Priority:
    /// 1. If `inputURL` is non-nil → input file's parent directory.
    /// 2. If `lastUsedURL` is non-nil → last-used directory.
    /// 3. Fallback → `~/Desktop/`.
    public static func resolveOutputDirectory(
        inputURL: URL?,
        lastUsedURL: URL?,
        desktopFallback: URL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "~/Desktop")
    ) -> (url: URL, mode: OutputPathMode) {
        if let input = inputURL {
            return (input.deletingLastPathComponent(), .sameAsInput)
        }
        if let last = lastUsedURL {
            return (last, .lastUsed)
        }
        return (desktopFallback, .desktop)
    }

    /// Returns `true` when a file already exists at `url`.
    public static func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Quotes a file path if it contains whitespace.
    public static func quotedPath(_ url: URL) -> String {
        let path = url.path
        if path.contains(" ") {
            return "\"\(path)\""
        }
        return path
    }

    // MARK: Multi-file command generation

    /// Builds the file arguments portion of a CLI command string for the given URLs.
    ///
    /// Paths containing spaces are automatically quoted.
    public static func fileArguments(for urls: [URL]) -> String {
        urls.map { quotedPath($0) }.joined(separator: " ")
    }
}

// MARK: - FileValidationHelpers

/// Helpers for quick DICOM header validation and basic metadata extraction.
public enum FileValidationHelpers {

    /// Number of bytes needed for the preamble + magic validation (128 + 4).
    public static let preambleSize = 132

    /// Reads the first `preambleSize` bytes of the file at `url` and validates the DICOM magic.
    ///
    /// - Returns: A `FileValidationResult` describing the outcome.
    public static func quickValidate(url: URL) -> FileValidationResult {
        guard
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
            values.isRegularFile == true
        else {
            return .unreadable(reason: "Not a regular file")
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .unreadable(reason: "Cannot open file")
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: preambleSize),
              !data.isEmpty else {
            return .unreadable(reason: "Cannot read file data")
        }
        return DICOMFileDropHelpers.validateMagicBytes(data)
    }

    /// Determines the set of warnings applicable to a validated file.
    public static func warnings(
        validationResult: FileValidationResult,
        fileSizeBytes: Int64,
        transferSyntaxUID: String?
    ) -> [FileValidationWarning] {
        var warnings: [FileValidationWarning] = []
        switch validationResult {
        case .validWithoutPreamble:
            warnings.append(.missingPreamble)
        case .unreadable:
            warnings.append(.corrupt)
        case .notDICOM:
            warnings.append(.corrupt)
        case .valid:
            break
        }
        if DICOMFileDropHelpers.isVeryLarge(fileSizeBytes) {
            warnings.append(.veryLargeFile)
        }
        if let ts = transferSyntaxUID, isUnusualTransferSyntax(ts) {
            warnings.append(.unusualTransferSyntax)
        }
        return warnings
    }

    /// Returns `true` when the transfer syntax UID is unusual or rarely supported.
    public static func isUnusualTransferSyntax(_ uid: String) -> Bool {
        // Well-known standard transfer syntaxes that are widely supported, named as
        // PS3.6 2026a Table A-1.
        let commonSyntaxes: Set<String> = [
            "1.2.840.10008.1.2",       // Implicit VR Little Endian: Default Transfer Syntax for DICOM
            "1.2.840.10008.1.2.1",     // Explicit VR Little Endian
            "1.2.840.10008.1.2.2",     // Explicit VR Big Endian (Retired) — still common in old archives
            "1.2.840.10008.1.2.4.50",  // JPEG Baseline (Process 1)
            "1.2.840.10008.1.2.4.51",  // JPEG Extended (Process 2 & 4)
            "1.2.840.10008.1.2.4.57",  // JPEG Lossless, Non-Hierarchical (Process 14)
            "1.2.840.10008.1.2.4.70",  // JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14 [Selection Value 1])
            "1.2.840.10008.1.2.4.90",  // JPEG 2000 Image Compression (Lossless Only)
            "1.2.840.10008.1.2.4.91",  // JPEG 2000 Image Compression
            "1.2.840.10008.1.2.4.201", // High-Throughput JPEG 2000 Image Compression (Lossless Only)
            "1.2.840.10008.1.2.4.202", // High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only)
            "1.2.840.10008.1.2.4.203", // High-Throughput JPEG 2000 Image Compression
            "1.2.840.10008.1.2.5",     // RLE Lossless
        ]
        return !commonSyntaxes.contains(uid)
    }

    /// Extracts a human-readable image dimensions string from raw pixel dimension values.
    ///
    /// Returns `nil` when either dimension is zero.
    public static func imageDimensions(rows: Int, columns: Int) -> String? {
        guard rows > 0, columns > 0 else { return nil }
        return "\(columns)×\(rows)"
    }

    /// Formats a raw DICOM date string (YYYYMMDD) into a locale-friendly display string.
    ///
    /// Returns the original string unchanged if it cannot be parsed.
    public static func formattedStudyDate(_ raw: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        if let date = formatter.date(from: raw) {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return raw
    }

    /// Truncates a DICOM patient name (PN VR, components separated by "^") into a readable form.
    ///
    /// For example, `"DOE^JOHN^MIDDLE"` → `"Doe, John"`.
    public static func formattedPatientName(_ raw: String) -> String {
        let parts = raw.split(separator: "^", maxSplits: 4).map { String($0) }
        guard !parts.isEmpty else { return raw }
        let family = parts[0].capitalized
        let given  = parts.count > 1 ? parts[1].capitalized : nil
        if let given = given, !given.isEmpty {
            return "\(family), \(given)"
        }
        return family
    }
}

// MARK: - DirectoryInputHelpers

/// Helpers for directory input controls.
public enum DirectoryInputHelpers {

    /// DICOM file extensions used when scanning a directory (lowercase).
    public static let dicomExtensions: Set<String> = ["dcm", "dicom"]

    /// Returns `true` when the URL points to a directory.
    public static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// Counts DICOM files in `directoryURL` using the given scan mode.
    ///
    /// Files are identified by their extension (`.dcm`, `.dicom`) or, for
    /// extensionless entries, by the DICOM magic-byte check.  This method is
    /// synchronous and intended for background use.
    ///
    /// - Parameters:
    ///   - directoryURL: Root directory to scan.
    ///   - scanMode: Whether to recurse into subdirectories.
    /// - Returns: The number of DICOM files found.
    public static func countDICOMFiles(
        in directoryURL: URL,
        scanMode: DirectoryScanMode
    ) -> Int {
        let fm = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions =
            scanMode == .shallow ? [.skipsSubdirectoryDescendants, .skipsHiddenFiles] : [.skipsHiddenFiles]

        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: options
        ) else { return 0 }

        var count = 0
        for case let url as URL in enumerator {
            guard
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                values.isRegularFile == true
            else { continue }
            let ext = url.pathExtension.lowercased()
            if dicomExtensions.contains(ext) {
                count += 1
            } else if ext.isEmpty {
                // Quick magic-byte check for extensionless files.
                if FileValidationHelpers.quickValidate(url: url).isDICOM {
                    count += 1
                }
            }
        }
        return count
    }

    /// Returns the `--recursive` flag string when `scanMode` is `.recursive`, otherwise `""`.
    public static func recursiveFlag(for scanMode: DirectoryScanMode) -> String {
        scanMode == .recursive ? "--recursive" : ""
    }

    /// Builds a CLI argument string for the given directory URL and scan mode.
    public static func cliArgument(for directoryURL: URL, scanMode: DirectoryScanMode) -> String {
        let path = OutputPathHelpers.quotedPath(directoryURL)
        let flag = recursiveFlag(for: scanMode)
        return flag.isEmpty ? path : "\(path) \(flag)"
    }
}
