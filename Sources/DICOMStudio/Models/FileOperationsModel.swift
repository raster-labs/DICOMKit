// FileOperationsModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for File Operations & Drag-and-Drop (Milestone 22)
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (drop-zone, output-path and scan state;
// the "DICM" doc comment refers to PS3.10 7.1).

import Foundation

// MARK: - 22.1 File Input Controls

/// Whether the drop zone accepts a single file or multiple files.
public enum FileDropMode: String, Sendable, CaseIterable, Identifiable, Hashable {
    /// Only one file can be held at a time; a new drop replaces the previous file.
    case single
    /// Multiple files are accumulated in an ordered list.
    case multiple

    public var id: String { rawValue }

    /// Human-readable label for this mode.
    public var displayName: String {
        switch self {
        case .single:   return "Single File"
        case .multiple: return "Multiple Files"
        }
    }
}

/// The current drag-over state of a drop zone.
public enum DropZoneHighlight: String, Sendable, Equatable {
    /// No drag in progress.
    case idle
    /// A drag is hovering over the zone.
    case active
    /// The last drop was rejected (e.g. non-DICOM file).
    case rejected
}

/// A single file that has been dropped or selected via the file picker.
public struct DroppedFile: Sendable, Identifiable, Hashable {
    /// Unique identifier within the current session.
    public let id: UUID

    /// Absolute URL of the file on disk.
    public var url: URL

    /// Display name (last path component).
    public var fileName: String

    /// File size in bytes.
    public var fileSizeBytes: Int64

    /// `true` when the DICOM magic bytes ("DICM") were found at offset 128.
    public var isDICOM: Bool

    /// DICOM modality string (e.g. "CT", "MR") extracted from the file header.
    public var modality: String?

    /// Patient name extracted from the file header, if present.
    public var patientName: String?

    /// Study date string (YYYYMMDD) extracted from the file header, if present.
    public var studyDate: String?

    /// Study description extracted from the file header, if present.
    public var studyDescription: String?

    /// Transfer syntax UID string extracted from the file header, if present.
    public var transferSyntaxUID: String?

    /// Image dimensions string (e.g. "512×512") when the file contains pixel data.
    public var imageDimensions: String?

    /// Validation warning for this file, if any.
    public var warning: FileValidationWarning?

    /// Creates a new dropped file entry.
    public init(
        id: UUID = UUID(),
        url: URL,
        fileName: String,
        fileSizeBytes: Int64,
        isDICOM: Bool,
        modality: String? = nil,
        patientName: String? = nil,
        studyDate: String? = nil,
        studyDescription: String? = nil,
        transferSyntaxUID: String? = nil,
        imageDimensions: String? = nil,
        warning: FileValidationWarning? = nil
    ) {
        self.id = id
        self.url = url
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
        self.isDICOM = isDICOM
        self.modality = modality
        self.patientName = patientName
        self.studyDate = studyDate
        self.studyDescription = studyDescription
        self.transferSyntaxUID = transferSyntaxUID
        self.imageDimensions = imageDimensions
        self.warning = warning
    }
}

/// State of the file drop zone component.
public struct FileDropZoneState: Sendable, Equatable {
    /// The current drag-over highlight state.
    public var highlight: DropZoneHighlight

    /// Files held by the zone (zero or one for `.single` mode; any count for `.multiple`).
    public var files: [DroppedFile]

    /// The mode controlling single- vs. multi-file behaviour.
    public var mode: FileDropMode

    /// Human-readable error shown when a drop was rejected.
    public var rejectionMessage: String?

    /// Creates a new drop zone state.
    public init(
        highlight: DropZoneHighlight = .idle,
        files: [DroppedFile] = [],
        mode: FileDropMode = .single,
        rejectionMessage: String? = nil
    ) {
        self.highlight = highlight
        self.files = files
        self.mode = mode
        self.rejectionMessage = rejectionMessage
    }

    /// The single selected file (for `.single` mode), or `nil` when empty.
    public var singleFile: DroppedFile? { files.first }

    /// `true` when at least one file is present.
    public var hasFiles: Bool { !files.isEmpty }
}

// MARK: - 22.2 Output Path Controls

/// How the output path is determined.
public enum OutputPathMode: String, Sendable, CaseIterable, Identifiable, Hashable {
    /// Output goes to the same directory as the input file.
    case sameAsInput
    /// Output goes to the last directory used for this tool.
    case lastUsed
    /// Output goes to `~/Desktop/`.
    case desktop
    /// The user has selected a custom path.
    case custom

    public var id: String { rawValue }

    /// Human-readable label for this mode.
    public var displayName: String {
        switch self {
        case .sameAsInput: return "Same as Input"
        case .lastUsed:    return "Last Used"
        case .desktop:     return "Desktop"
        case .custom:      return "Custom"
        }
    }
}

/// Configuration for the output path panel.
public struct OutputPathConfig: Sendable, Equatable {
    /// How the output path was determined.
    public var mode: OutputPathMode

    /// Resolved absolute output URL (file or directory).
    public var resolvedURL: URL?

    /// The auto-generated filename suggested for this tool and input.
    public var suggestedFilename: String?

    /// `true` when a file already exists at `resolvedURL`.
    public var overwriteWarning: Bool

    /// Creates a new output path configuration.
    public init(
        mode: OutputPathMode = .sameAsInput,
        resolvedURL: URL? = nil,
        suggestedFilename: String? = nil,
        overwriteWarning: Bool = false
    ) {
        self.mode = mode
        self.resolvedURL = resolvedURL
        self.suggestedFilename = suggestedFilename
        self.overwriteWarning = overwriteWarning
    }

    /// Human-readable display path (the last two path components, or the full path for short URLs).
    public var displayPath: String {
        guard let url = resolvedURL else { return "Not set" }
        let components = url.pathComponents
        if components.count > 2 {
            return "…/" + components.suffix(2).joined(separator: "/")
        }
        return url.path
    }
}

/// Configuration for the output directory panel (used by directory-output tools).
public struct OutputDirectoryConfig: Sendable, Equatable {
    /// How the output directory was determined.
    public var mode: OutputPathMode

    /// Resolved absolute directory URL.
    public var resolvedURL: URL?

    /// Available free disk space in bytes, when known.
    public var freeDiskSpaceBytes: Int64?

    /// Creates a new output directory configuration.
    public init(
        mode: OutputPathMode = .desktop,
        resolvedURL: URL? = nil,
        freeDiskSpaceBytes: Int64? = nil
    ) {
        self.mode = mode
        self.resolvedURL = resolvedURL
        self.freeDiskSpaceBytes = freeDiskSpaceBytes
    }

    /// Human-readable display path.
    public var displayPath: String {
        guard let url = resolvedURL else { return "Not set" }
        let components = url.pathComponents
        if components.count > 2 {
            return "…/" + components.suffix(2).joined(separator: "/")
        }
        return url.path
    }
}

// MARK: - 22.3 File Validation & Preview

/// A warning condition associated with a validated file.
public enum FileValidationWarning: String, Sendable, CaseIterable, Identifiable, Hashable {
    /// The DICOM preamble is missing (no "DICM" magic at offset 128).
    case missingPreamble
    /// The file uses a non-standard or unusual transfer syntax.
    case unusualTransferSyntax
    /// The file is very large (> 1 GB).
    case veryLargeFile
    /// The file appears corrupt or unreadable.
    case corrupt

    public var id: String { rawValue }

    /// Human-readable description of the warning.
    public var displayName: String {
        switch self {
        case .missingPreamble:       return "Missing DICOM preamble"
        case .unusualTransferSyntax: return "Unusual transfer syntax"
        case .veryLargeFile:         return "Very large file (>1 GB)"
        case .corrupt:               return "File may be corrupt"
        }
    }

    /// SF Symbol badge icon name for this warning.
    public var symbolName: String {
        switch self {
        case .missingPreamble:       return "exclamationmark.triangle"
        case .unusualTransferSyntax: return "questionmark.circle"
        case .veryLargeFile:         return "externaldrive"
        case .corrupt:               return "xmark.octagon"
        }
    }
}

/// Result of the quick DICOM header validation.
public enum FileValidationResult: Sendable, Equatable {
    /// The file is a valid DICOM file with a standard preamble.
    case valid
    /// The file is DICOM but the preamble is non-standard (ACR-NEMA or implicit preamble).
    case validWithoutPreamble
    /// The file is not a DICOM file.
    case notDICOM
    /// The file could not be read (permissions, I/O error, etc.).
    case unreadable(reason: String)

    /// `true` when the file can be used as DICOM input.
    public var isDICOM: Bool {
        switch self {
        case .valid, .validWithoutPreamble: return true
        case .notDICOM, .unreadable:        return false
        }
    }
}

/// Compact preview metadata for a selected or dropped file.
public struct FilePreviewInfo: Sendable, Equatable {
    /// Display filename.
    public var fileName: String
    /// File size in bytes.
    public var fileSizeBytes: Int64
    /// DICOM modality string (e.g. "CT", "MR"), if available.
    public var modality: String?
    /// Patient name, if present and not anonymized.
    public var patientName: String?
    /// Study date string (YYYYMMDD), if available.
    public var studyDate: String?
    /// Validation warnings to display as badges.
    public var warnings: [FileValidationWarning]

    /// Creates a new file preview info.
    public init(
        fileName: String,
        fileSizeBytes: Int64,
        modality: String? = nil,
        patientName: String? = nil,
        studyDate: String? = nil,
        warnings: [FileValidationWarning] = []
    ) {
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
        self.modality = modality
        self.patientName = patientName
        self.studyDate = studyDate
        self.warnings = warnings
    }
}

// MARK: - 22.4 Directory Input Support

/// Whether directory scanning is recursive.
public enum DirectoryScanMode: String, Sendable, CaseIterable, Identifiable, Hashable {
    /// Only the top-level directory contents are scanned.
    case shallow
    /// All subdirectories are scanned recursively.
    case recursive

    public var id: String { rawValue }

    /// Human-readable label.
    public var displayName: String {
        switch self {
        case .shallow:   return "Top Level Only"
        case .recursive: return "Recursive"
        }
    }
}

/// State of the directory input drop zone.
public struct DirectoryDropState: Sendable, Equatable {
    /// The dropped or selected directory URL, if any.
    public var directoryURL: URL?

    /// The current drag-over highlight state.
    public var highlight: DropZoneHighlight

    /// Number of DICOM files found inside the directory.
    public var dicomFileCount: Int

    /// Whether the count is still being computed.
    public var isScanning: Bool

    /// The current scan mode.
    public var scanMode: DirectoryScanMode

    /// Human-readable rejection message if a non-directory was dropped.
    public var rejectionMessage: String?

    /// Creates a new directory drop state.
    public init(
        directoryURL: URL? = nil,
        highlight: DropZoneHighlight = .idle,
        dicomFileCount: Int = 0,
        isScanning: Bool = false,
        scanMode: DirectoryScanMode = .recursive,
        rejectionMessage: String? = nil
    ) {
        self.directoryURL = directoryURL
        self.highlight = highlight
        self.dicomFileCount = dicomFileCount
        self.isScanning = isScanning
        self.scanMode = scanMode
        self.rejectionMessage = rejectionMessage
    }

    /// Display name for the selected directory.
    public var directoryDisplayName: String {
        directoryURL?.lastPathComponent ?? "No directory selected"
    }

    /// Human-readable DICOM file count.
    public var fileCountDescription: String {
        if isScanning { return "Scanning…" }
        return "\(dicomFileCount) DICOM file\(dicomFileCount == 1 ? "" : "s") found"
    }
}

// MARK: - Top-level File Operations State

/// Top-level tabs for the File Operations feature panel.
public enum FileOperationsTab: String, Sendable, CaseIterable, Identifiable, Hashable {
    /// File input controls: drop zone and file picker.
    case fileInput
    /// Output path configuration.
    case outputPath
    /// File validation and preview details.
    case fileValidation
    /// Directory input controls.
    case directoryInput

    public var id: String { rawValue }

    /// Human-readable tab title.
    public var displayName: String {
        switch self {
        case .fileInput:       return "File Input"
        case .outputPath:      return "Output Path"
        case .fileValidation:  return "Validation & Preview"
        case .directoryInput:  return "Directory Input"
        }
    }

    /// SF Symbol icon for this tab.
    public var symbolName: String {
        switch self {
        case .fileInput:       return "doc.badge.arrow.up"
        case .outputPath:      return "arrow.down.doc"
        case .fileValidation:  return "checkmark.shield"
        case .directoryInput:  return "folder.badge.questionmark"
        }
    }
}

/// Aggregated state for the full File Operations feature.
public struct FileOperationsState: Sendable, Equatable {
    /// The currently visible tab.
    public var selectedTab: FileOperationsTab

    /// State of the file drop zone.
    public var dropZone: FileDropZoneState

    /// Output path configuration.
    public var outputPath: OutputPathConfig

    /// Output directory configuration (for directory-output tools).
    public var outputDirectory: OutputDirectoryConfig

    /// Directory drop state (for directory-input tools).
    public var directoryDrop: DirectoryDropState

    /// Preview information for the currently selected file.
    public var filePreview: FilePreviewInfo?

    /// The CLI tool name currently associated with this panel.
    public var associatedToolName: String

    /// Creates a new file operations state.
    public init(
        selectedTab: FileOperationsTab = .fileInput,
        dropZone: FileDropZoneState = FileDropZoneState(),
        outputPath: OutputPathConfig = OutputPathConfig(),
        outputDirectory: OutputDirectoryConfig = OutputDirectoryConfig(),
        directoryDrop: DirectoryDropState = DirectoryDropState(),
        filePreview: FilePreviewInfo? = nil,
        associatedToolName: String = ""
    ) {
        self.selectedTab = selectedTab
        self.dropZone = dropZone
        self.outputPath = outputPath
        self.outputDirectory = outputDirectory
        self.directoryDrop = directoryDrop
        self.filePreview = filePreview
        self.associatedToolName = associatedToolName
    }
}
