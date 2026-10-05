// AIAnalysisModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for AI/ML Analysis (dicom-ai)
// The DICOM output objects (TID 1500 SR, SEG) are built by dicom-ai / DICOMKit, not here.
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (tabs, output-format and task enums, job and model records); the former PS3.17 Annex U radiomics citation was removed because nothing in the file encodes radiomics; AIOutputFormat's DICOM_SR / DICOM_SEG name dicom-ai's --format dicom-sr / dicom-seg

import Foundation

// MARK: - Navigation Tab

/// Navigation tabs for the AI Analysis feature.
public enum AIAnalysisTab: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case imageClassification = "IMAGE_CLASSIFICATION"
    case segmentation        = "SEGMENTATION"
    case objectDetection     = "OBJECT_DETECTION"
    case imageEnhancement    = "IMAGE_ENHANCEMENT"
    case batchAnalysis       = "BATCH_ANALYSIS"
    case modelRegistry       = "MODEL_REGISTRY"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .imageClassification: return "Classification"
        case .segmentation:        return "Segmentation"
        case .objectDetection:     return "Detection"
        case .imageEnhancement:    return "Enhancement"
        case .batchAnalysis:       return "Batch Analysis"
        case .modelRegistry:       return "Model Registry"
        }
    }

    /// SF Symbol name for this tab.
    public var sfSymbol: String {
        switch self {
        case .imageClassification: return "brain.head.profile"
        case .segmentation:        return "rectangle.3.group"
        case .objectDetection:     return "viewfinder.circle"
        case .imageEnhancement:    return "wand.and.sparkles"
        case .batchAnalysis:       return "square.stack.3d.up"
        case .modelRegistry:       return "list.bullet.rectangle"
        }
    }
}

// MARK: - AI Output Format

/// Output format for AI analysis results.
public enum AIOutputFormat: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case json      = "JSON"
    case dicomSR   = "DICOM_SR"
    case dicomSEG  = "DICOM_SEG"
    case text      = "TEXT"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .json:     return "JSON"
        case .dicomSR:  return "DICOM SR"
        case .dicomSEG: return "DICOM SEG"
        case .text:     return "Plain Text"
        }
    }
}

// MARK: - AI Model Entry

/// Represents a CoreML model registered for use with DICOM images.
public struct AIModelEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var modelPath: String
    public var task: AIModelTask
    public var description: String
    public var version: String
    public var addedDate: Date

    public init(
        id: UUID = UUID(),
        name: String,
        modelPath: String,
        task: AIModelTask,
        description: String = "",
        version: String = "1.0",
        addedDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.modelPath = modelPath
        self.task = task
        self.description = description
        self.version = version
        self.addedDate = addedDate
    }
}

// MARK: - AI Model Task

/// The type of task a CoreML model performs on DICOM images.
public enum AIModelTask: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case classification = "CLASSIFICATION"
    case segmentation   = "SEGMENTATION"
    case detection      = "DETECTION"
    case enhancement    = "ENHANCEMENT"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classification: return "Classification"
        case .segmentation:   return "Segmentation"
        case .detection:      return "Object Detection"
        case .enhancement:    return "Image Enhancement"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .classification: return "tag"
        case .segmentation:   return "rectangle.3.group"
        case .detection:      return "viewfinder"
        case .enhancement:    return "wand.and.sparkles"
        }
    }
}

// MARK: - AI Analysis Job

/// A single AI analysis job (classification, segmentation, detection, or enhancement run).
public struct AIAnalysisJob: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var inputPath: String
    public var modelName: String
    public var task: AIModelTask
    public var outputFormat: AIOutputFormat
    public var confidenceThreshold: Double
    public var status: AIJobStatus
    public var resultSummary: String
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        inputPath: String,
        modelName: String,
        task: AIModelTask,
        outputFormat: AIOutputFormat = .json,
        confidenceThreshold: Double = 0.5,
        status: AIJobStatus = .pending,
        resultSummary: String = "",
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.inputPath = inputPath
        self.modelName = modelName
        self.task = task
        self.outputFormat = outputFormat
        self.confidenceThreshold = confidenceThreshold
        self.status = status
        self.resultSummary = resultSummary
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

// MARK: - AI Job Status

/// Status of an AI analysis job.
public enum AIJobStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case pending    = "PENDING"
    case running    = "RUNNING"
    case completed  = "COMPLETED"
    case failed     = "FAILED"

    public var displayName: String {
        switch self {
        case .pending:   return "Pending"
        case .running:   return "Running"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .pending:   return "clock"
        case .running:   return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        }
    }

    public var color: String {
        switch self {
        case .pending:   return "secondary"
        case .running:   return "blue"
        case .completed: return "green"
        case .failed:    return "red"
        }
    }
}
