// DataExchangeModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for Data Exchange & Export (Milestone 12)
// Reference: DICOM PS3.10 (Media Storage and File Format)
// Reference: DICOM PS3.18 Annex F (JSON Encoding of DICOM Data Sets)
// Reference: DICOM PS3.19 Annex A (Native DICOM Model XML)
//
// NEMA-verified: 2026a, checked 2026-10-05 — tab, format, status and job enums carry no DICOM-standard values;
// `TransferSyntaxConversionJob.targetDisplayName` takes its name from DICOMCore `SelectableEncoding` (PS3.6 2026a
// Table A-1); `DICOMDIREntry` fields (Patient's Name, Patient ID, Study Date, Study Instance UID, Modality) are
// PS3.3 2026a Table F.5-1/F.5-2/F.5-3 record keys; the PS3.18 Annex F, PS3.3 Annex F and A.45 citations name
// existing clauses (PS3.19 not fetched, its citation not checked).

import Foundation
import DICOMCore

// MARK: - Navigation Tab

/// Navigation tabs for the Data Exchange & Export feature.
public enum DataExchangeTab: String, Sendable, Equatable, Hashable, CaseIterable {
    case jsonConversion    = "JSON_CONVERSION"
    case xmlConversion     = "XML_CONVERSION"
    case imageExport       = "IMAGE_EXPORT"
    case transferSyntax    = "TRANSFER_SYNTAX"
    case compression       = "COMPRESSION"
    case secondaryCapture  = "SECONDARY_CAPTURE"
    case dicomdir          = "DICOMDIR"
    case pdfEncapsulation  = "PDF_ENCAPSULATION"
    case batchOperations   = "BATCH_OPERATIONS"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .jsonConversion:   return "JSON"
        case .xmlConversion:    return "XML"
        case .imageExport:      return "Image Export"
        case .transferSyntax:   return "Transfer Syntax"
        case .compression:      return "Compression"
        case .secondaryCapture: return "Secondary Capture"
        case .dicomdir:         return "DICOMDIR"
        case .pdfEncapsulation: return "PDF"
        case .batchOperations:  return "Batch"
        }
    }

    /// SF Symbol name for this tab.
    public var sfSymbol: String {
        switch self {
        case .jsonConversion:   return "doc.text"
        case .xmlConversion:    return "chevron.left.forwardslash.chevron.right"
        case .imageExport:      return "photo.on.rectangle.angled"
        case .transferSyntax:   return "arrow.triangle.2.circlepath"
        case .compression:      return "square.and.arrow.down.on.square"
        case .secondaryCapture: return "photo.badge.plus"
        case .dicomdir:         return "folder.badge.plus"
        case .pdfEncapsulation: return "doc.richtext"
        case .batchOperations:  return "square.stack.3d.up"
        }
    }
}

// MARK: - JSON Output Format

/// Output format for DICOM-to-JSON conversion.
/// Reference: DICOM PS3.18 §F
public enum JSONOutputFormat: String, Sendable, Equatable, Hashable, CaseIterable {
    case standard = "STANDARD"
    case pretty   = "PRETTY"
    case compact  = "COMPACT"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .standard: return "DICOM JSON (PS3.18 §F)"
        case .pretty:   return "Pretty Printed"
        case .compact:  return "Compact"
        }
    }

    /// Short description.
    public var description: String {
        switch self {
        case .standard: return "Inline base64 for bulk data"
        case .pretty:   return "Human-readable indented JSON"
        case .compact:  return "Minimised single-line JSON"
        }
    }
}

// MARK: - XML Output Format

/// Output format for DICOM-to-XML conversion.
/// Reference: DICOM PS3.19 §A
public enum XMLOutputFormat: String, Sendable, Equatable, Hashable, CaseIterable {
    case standard   = "STANDARD"
    case pretty     = "PRETTY"
    case noKeywords = "NO_KEYWORDS"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .standard:   return "DICOM XML (PS3.19 §A)"
        case .pretty:     return "Pretty Printed"
        case .noKeywords: return "No Keywords"
        }
    }

    /// Short description.
    public var description: String {
        switch self {
        case .standard:   return "Conformant native XML"
        case .pretty:     return "Human-readable indented XML"
        case .noKeywords: return "Tag addresses only, no keyword attributes"
        }
    }
}

// MARK: - Image Export Format

/// File format for image export operations.
public enum ImageExportFormat: String, Sendable, Equatable, Hashable, CaseIterable {
    case png  = "PNG"
    case jpeg = "JPEG"
    case tiff = "TIFF"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .png:  return "PNG"
        case .jpeg: return "JPEG"
        case .tiff: return "TIFF"
        }
    }

    /// File extension (without leading dot).
    public var fileExtension: String {
        switch self {
        case .png:  return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        }
    }

    /// Whether this format uses lossless compression.
    public var isLossless: Bool {
        switch self {
        case .png:  return true
        case .jpeg: return false
        case .tiff: return true
        }
    }
}

// MARK: - Image Export Resolution

/// Resolution scaling for exported images.
public enum ImageExportResolution: String, Sendable, Equatable, Hashable, CaseIterable {
    case original = "ORIGINAL"
    case half     = "HALF"
    case quarter  = "QUARTER"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .original: return "Original"
        case .half:     return "Half (50%)"
        case .quarter:  return "Quarter (25%)"
        }
    }

    /// Short description.
    public var description: String {
        switch self {
        case .original: return "Full resolution as stored"
        case .half:     return "50% of original resolution"
        case .quarter:  return "25% of original resolution"
        }
    }
}

// MARK: - Transfer Syntax Entry

/// A known DICOM transfer syntax with display metadata.
/// Reference: DICOM PS3.5 §10 and Annex A
public struct TransferSyntaxEntry: Sendable, Identifiable, Equatable, Hashable {
    /// Unique identifier — equals `uid`.
    public let id: String
    /// Transfer syntax UID.
    public let uid: String
    /// Full display name.
    public let displayName: String
    /// Short abbreviation.
    public let shortName: String
    /// Whether pixel data is compressed.
    public let isCompressed: Bool
    /// Whether the compression is lossy.
    public let isLossy: Bool
    /// Description with standard reference.
    public let description: String

    public init(
        uid: String,
        displayName: String,
        shortName: String,
        isCompressed: Bool,
        isLossy: Bool,
        description: String
    ) {
        self.id = uid
        self.uid = uid
        self.displayName = displayName
        self.shortName = shortName
        self.isCompressed = isCompressed
        self.isLossy = isLossy
        self.description = description
    }
}

// MARK: - Conversion Job Status

/// Status of a single transfer syntax conversion job.
public enum ConversionJobStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case pending    = "PENDING"
    case inProgress = "IN_PROGRESS"
    case completed  = "COMPLETED"
    case failed     = "FAILED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .pending:    return "Pending"
        case .inProgress: return "In Progress"
        case .completed:  return "Completed"
        case .failed:     return "Failed"
        }
    }
}

// MARK: - Transfer Syntax Conversion Job

/// A queued conversion job from one transfer syntax to another.
public struct TransferSyntaxConversionJob: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// Absolute path to the source DICOM file.
    public var sourceFilePath: String
    /// Target transfer syntax UID.
    public var targetTransferSyntaxUID: String
    /// Selected encoding intent for the target.
    ///
    /// The `both`-capable general UIDs (`.91`/`.93`/`.203`) carry either a reversible
    /// or an irreversible codestream, so the UID alone does not determine the encoding.
    /// This records which the user picked; it is `.notApplicable` for single-capability
    /// targets (uncompressed, `.90`/`.201`, RLE, …).
    public var intent: EncodingIntent
    /// Current job status.
    public var status: ConversionJobStatus
    /// Size of the original file in bytes.
    public var originalSizeBytes: Int
    /// Size of the converted file in bytes.
    public var convertedSizeBytes: Int
    /// Error message, if the job failed.
    public var errorMessage: String?

    public init(
        sourceFilePath: String,
        targetTransferSyntaxUID: String,
        intent: EncodingIntent = .notApplicable
    ) {
        self.id = UUID()
        self.sourceFilePath = sourceFilePath
        self.targetTransferSyntaxUID = targetTransferSyntaxUID
        self.intent = intent
        self.status = .pending
        self.originalSizeBytes = 0
        self.convertedSizeBytes = 0
        self.errorMessage = nil
    }

    /// The target as a `SelectableEncoding`, pairing the UID with the chosen intent.
    public var targetEncoding: SelectableEncoding? {
        guard let ts = TransferSyntax.from(uid: targetTransferSyntaxUID) else { return nil }
        return SelectableEncoding(transferSyntax: ts, intent: intent)
    }

    /// Intent-aware display name for the target, e.g. "JPEG 2000 Part 2 Multi-component Lossy".
    /// Falls back to the raw UID for unrecognized targets.
    public var targetDisplayName: String {
        targetEncoding?.displayName ?? targetTransferSyntaxUID
    }
}

// MARK: - DICOMDIR Entry

/// A study record to include in a DICOMDIR media file.
/// Reference: DICOM PS3.3 Annex F – DICOMDIR
public struct DICOMDIREntry: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// Study Instance UID.
    public var studyInstanceUID: String
    /// Patient name (DICOM VR PN format).
    public var patientName: String
    /// Patient identifier.
    public var patientID: String
    /// Study date in YYYYMMDD format.
    public var studyDate: String
    /// Modalities present in the study (e.g. ["CT", "PT"]).
    public var modalities: [String]
    /// Number of series in the study.
    public var seriesCount: Int
    /// Total number of SOP instances.
    public var instanceCount: Int

    public init(
        studyInstanceUID: String,
        patientName: String,
        patientID: String,
        studyDate: String,
        modalities: [String],
        seriesCount: Int,
        instanceCount: Int
    ) {
        self.id = UUID()
        self.studyInstanceUID = studyInstanceUID
        self.patientName = patientName
        self.patientID = patientID
        self.studyDate = studyDate
        self.modalities = modalities
        self.seriesCount = seriesCount
        self.instanceCount = instanceCount
    }
}

// MARK: - PDF Encapsulation Mode

/// Mode for the PDF encapsulation / extraction operation.
/// Reference: DICOM PS3.3 §A.45 – Encapsulated PDF IOD
public enum PDFEncapsulationMode: String, Sendable, Equatable, Hashable, CaseIterable {
    case encapsulate = "ENCAPSULATE"
    case extract     = "EXTRACT"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .encapsulate: return "Encapsulate PDF → DICOM"
        case .extract:     return "Extract PDF from DICOM"
        }
    }

    /// Short description.
    public var description: String {
        switch self {
        case .encapsulate: return "Wrap a PDF file as an Encapsulated PDF DICOM instance"
        case .extract:     return "Extract the embedded PDF from an Encapsulated PDF DICOM file"
        }
    }
}

// MARK: - Batch Operation Type

/// Type of operation to perform in a batch job.
public enum BatchOperationType: String, Sendable, Equatable, Hashable, CaseIterable {
    case tagModification          = "TAG_MODIFICATION"
    case transferSyntaxConversion = "TRANSFER_SYNTAX_CONVERSION"
    case anonymization            = "ANONYMIZATION"
    case imageExport              = "IMAGE_EXPORT"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .tagModification:          return "Tag Modification"
        case .transferSyntaxConversion: return "Transfer Syntax Conversion"
        case .anonymization:            return "Anonymization"
        case .imageExport:              return "Image Export"
        }
    }

    /// SF Symbol name.
    public var sfSymbol: String {
        switch self {
        case .tagModification:          return "pencil"
        case .transferSyntaxConversion: return "arrow.triangle.2.circlepath"
        case .anonymization:            return "person.crop.circle.badge.minus"
        case .imageExport:              return "photo.on.rectangle.angled"
        }
    }
}

// MARK: - Tag Modification Operation

/// Operation to apply to a DICOM tag in a batch modification.
public enum TagModificationOperation: String, Sendable, Equatable, Hashable, CaseIterable {
    case add    = "ADD"
    case update = "UPDATE"
    case remove = "REMOVE"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .add:    return "Add"
        case .update: return "Update"
        case .remove: return "Remove"
        }
    }
}

// MARK: - Batch Tag Modification

/// Describes a single tag modification to apply across a batch of files.
public struct BatchTagModification: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// DICOM tag keyword (e.g. "PatientName").
    public var tagKeyword: String
    /// Tag group number.
    public var tagGroup: UInt16
    /// Tag element number.
    public var tagElement: UInt16
    /// Operation to perform.
    public var operation: TagModificationOperation
    /// New value (used for add/update operations).
    public var newValue: String

    public init(
        tagKeyword: String,
        tagGroup: UInt16,
        tagElement: UInt16,
        operation: TagModificationOperation,
        newValue: String
    ) {
        self.id = UUID()
        self.tagKeyword = tagKeyword
        self.tagGroup = tagGroup
        self.tagElement = tagElement
        self.operation = operation
        self.newValue = newValue
    }
}

// MARK: - Batch Job Status

/// Status of a batch operation job.
public enum BatchJobStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case pending             = "PENDING"
    case inProgress          = "IN_PROGRESS"
    case completed           = "COMPLETED"
    case completedWithErrors = "COMPLETED_WITH_ERRORS"
    case failed              = "FAILED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .pending:             return "Pending"
        case .inProgress:          return "In Progress"
        case .completed:           return "Completed"
        case .completedWithErrors: return "Completed with Errors"
        case .failed:              return "Failed"
        }
    }

    /// Whether this is a terminal (non-running) state.
    public var isTerminal: Bool {
        self == .completed || self == .completedWithErrors || self == .failed
    }

    /// Whether this status indicates that errors occurred.
    public var hasErrors: Bool {
        self == .completedWithErrors || self == .failed
    }
}

// MARK: - Batch Job

/// A batch operation job tracking multiple input files.
public struct BatchJob: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// Type of operation.
    public var operationType: BatchOperationType
    /// Input file/directory paths.
    public var inputPaths: [String]
    /// Output directory path.
    public var outputDirectory: String
    /// Current job status.
    public var status: BatchJobStatus
    /// Number of items successfully processed.
    public var processedCount: Int
    /// Number of items that failed processing.
    public var failedCount: Int
    /// Total number of items to process.
    public var totalCount: Int
    /// Summary of per-item errors.
    public var errorSummary: [String]

    public init(
        operationType: BatchOperationType,
        inputPaths: [String],
        outputDirectory: String
    ) {
        self.id = UUID()
        self.operationType = operationType
        self.inputPaths = inputPaths
        self.outputDirectory = outputDirectory
        self.status = .pending
        self.processedCount = 0
        self.failedCount = 0
        self.totalCount = 0
        self.errorSummary = []
    }
}

// MARK: - JSON Conversion Settings

/// Settings controlling DICOM-to-JSON conversion behaviour.
public struct JSONConversionSettings: Sendable, Equatable {
    /// Output format to use.
    public var outputFormat: JSONOutputFormat
    /// Whether to use bulk data URI references instead of inline base64.
    public var includeBulkDataURIs: Bool
    /// Byte threshold above which bulk data is referenced instead of inlined.
    public var bulkDataThresholdBytes: Int
    /// When true, pixel data and other bulk data are omitted entirely.
    public var metadataOnly: Bool

    public init() {
        self.outputFormat = .pretty
        self.includeBulkDataURIs = false
        self.bulkDataThresholdBytes = 1024
        self.metadataOnly = false
    }
}

// MARK: - XML Conversion Settings

/// Settings controlling DICOM-to-XML conversion behaviour.
public struct XMLConversionSettings: Sendable, Equatable {
    /// Output format to use.
    public var outputFormat: XMLOutputFormat
    /// Whether to use bulk data URI references instead of inline base64.
    public var includeBulkDataURIs: Bool
    /// Byte threshold above which bulk data is referenced instead of inlined.
    public var bulkDataThresholdBytes: Int
    /// When true, pixel data and other bulk data are omitted entirely.
    public var metadataOnly: Bool

    public init() {
        self.outputFormat = .pretty
        self.includeBulkDataURIs = false
        self.bulkDataThresholdBytes = 1024
        self.metadataOnly = false
    }
}

// MARK: - Image Export Settings

/// Settings controlling how DICOM pixel data is exported as an image file.
public struct ImageExportSettings: Sendable, Equatable {
    /// Target image format.
    public var format: ImageExportFormat
    /// JPEG quality in the range [0.0, 1.0].
    public var jpegQuality: Double
    /// Output resolution scaling.
    public var resolution: ImageExportResolution
    /// Whether to burn patient/study annotations into the output image.
    public var burnInAnnotations: Bool
    /// Whether to apply the current window/level before exporting.
    public var burnInWindowLevel: Bool
    /// When true, all frames of a multi-frame object are exported.
    public var exportAllFrames: Bool

    public init() {
        self.format = .png
        self.jpegQuality = 0.85
        self.resolution = .original
        self.burnInAnnotations = false
        self.burnInWindowLevel = true
        self.exportAllFrames = false
    }
}
