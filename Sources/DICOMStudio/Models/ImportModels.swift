// ImportModels.swift
// DICOMStudio
//
// DICOM Studio — Models for file import operations
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (import results, validation rule
// identifiers and progress).

import Foundation

/// Result of importing a single DICOM file.
public struct ImportResult: Sendable {
    /// The source URL of the imported file.
    public let sourceURL: URL

    /// The parsed instance, if import succeeded.
    public let instance: InstanceModel?

    /// The extracted study metadata, if available.
    public let study: StudyModel?

    /// The extracted series metadata, if available.
    public let series: SeriesModel?

    /// Any validation issues found during import.
    public let validationIssues: [ValidationIssue]

    /// Whether the import succeeded (file was valid and parsed).
    public var succeeded: Bool { instance != nil }

    /// Whether a duplicate was detected.
    public let isDuplicate: Bool

    /// Creates an import result.
    public init(
        sourceURL: URL,
        instance: InstanceModel? = nil,
        study: StudyModel? = nil,
        series: SeriesModel? = nil,
        validationIssues: [ValidationIssue] = [],
        isDuplicate: Bool = false
    ) {
        self.sourceURL = sourceURL
        self.instance = instance
        self.study = study
        self.series = series
        self.validationIssues = validationIssues
        self.isDuplicate = isDuplicate
    }
}

/// Describes a validation issue found during DICOM file import.
public struct ValidationIssue: Sendable, Equatable {
    /// Severity of the validation issue.
    public let severity: ValidationSeverity

    /// Human-readable description of the issue.
    public let message: String

    /// The validation rule that was violated.
    public let rule: ValidationRule

    /// Creates a validation issue.
    public init(severity: ValidationSeverity, message: String, rule: ValidationRule) {
        self.severity = severity
        self.message = message
        self.rule = rule
    }
}

/// Severity of a validation issue.
public enum ValidationSeverity: String, Sendable, Equatable {
    case error
    case warning
    case info
}

/// Validation rules checked during DICOM file import.
public enum ValidationRule: String, Sendable, Equatable {
    case preamble
    case dicmMagic
    case fileMetaInformation
    case requiredTags
    case transferSyntax
    case sopClassUID
    case fileSize
    case duplicateDetection
}

/// Tracks progress of a batch import operation.
public struct ImportProgress: Sendable {
    /// Total number of files to import.
    public let totalFiles: Int

    /// Number of files processed so far.
    public let processedFiles: Int

    /// Number of files successfully imported.
    public let succeededFiles: Int

    /// Number of files that failed import.
    public let failedFiles: Int

    /// Number of duplicate files skipped.
    public let duplicateFiles: Int

    /// Whether the import is complete.
    public var isComplete: Bool { processedFiles >= totalFiles }

    /// Progress fraction (0.0 to 1.0).
    public var fractionComplete: Double {
        guard totalFiles > 0 else { return 0.0 }
        return Double(processedFiles) / Double(totalFiles)
    }

    /// Current status description.
    public var statusDescription: String {
        if isComplete {
            return "Import complete: \(succeededFiles) imported, \(failedFiles) failed, \(duplicateFiles) duplicates"
        }
        return "Importing \(processedFiles)/\(totalFiles)..."
    }

    /// Creates an import progress.
    public init(
        totalFiles: Int,
        processedFiles: Int = 0,
        succeededFiles: Int = 0,
        failedFiles: Int = 0,
        duplicateFiles: Int = 0
    ) {
        self.totalFiles = totalFiles
        self.processedFiles = processedFiles
        self.succeededFiles = succeededFiles
        self.failedFiles = failedFiles
        self.duplicateFiles = duplicateFiles
    }
}
