// AIAnalysisViewModel.swift
// DICOMStudio
//
// DICOM Studio — ViewModel for AI Analysis feature (dicom-ai)
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data; the dicom-ai command lines it shows (classify / segment / detect / enhance with --model and --confidence) name real dicom-ai subcommands and options (Sources/dicom-ai/main.swift CommonOptions)

import Foundation
import Observation

/// ViewModel for the AI Analysis feature.
///
/// Manages CoreML model registration, job submission, and results
/// for DICOM image classification, segmentation, detection, and enhancement.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
@MainActor
public final class AIAnalysisViewModel {
    private let service: AIAnalysisService

    // MARK: - Navigation

    public var activeTab: AIAnalysisTab = .imageClassification

    // MARK: - Classification

    public var classifyInputPath: String = ""
    public var classifyModelName: String = ""
    public var classifyConfidence: Double = 0.5
    public var classifyOutputFormat: AIOutputFormat = .json
    public var classifyResult: String = ""

    // MARK: - Segmentation

    public var segmentInputPath: String = ""
    public var segmentModelName: String = ""
    public var segmentOutputPath: String = ""
    public var segmentResult: String = ""

    // MARK: - Detection

    public var detectInputPath: String = ""
    public var detectModelName: String = ""
    public var detectConfidence: Double = 0.5
    public var detectResult: String = ""

    // MARK: - Enhancement

    public var enhanceInputPath: String = ""
    public var enhanceModelName: String = ""
    public var enhanceOutputPath: String = ""
    public var enhanceResult: String = ""

    // MARK: - Batch

    public var batchInputDirectory: String = ""
    public var batchModelName: String = ""
    public var batchOutputPath: String = ""
    public var batchConfidence: Double = 0.5
    public var batchOutputFormat: AIOutputFormat = .json

    // MARK: - Model Registry

    public var registeredModels: [AIModelEntry] = []
    public var newModelPath: String = ""
    public var newModelName: String = ""
    public var newModelTask: AIModelTask = .classification

    // MARK: - Jobs

    public var jobs: [AIAnalysisJob] = []

    // MARK: - UI State

    public var isLoading: Bool = false
    public var errorMessage: String? = nil
    public var isAddModelSheetPresented: Bool = false

    public init(service: AIAnalysisService = AIAnalysisService()) {
        self.service = service
        self.registeredModels = service.models
        self.jobs = service.jobs
    }

    // MARK: - Model Registry Actions

    public func addModel() {
        guard !newModelName.isEmpty, !newModelPath.isEmpty else {
            errorMessage = "Model name and path are required."
            return
        }
        let model = AIModelEntry(
            name: newModelName,
            modelPath: newModelPath,
            task: newModelTask
        )
        service.addModel(model)
        registeredModels = service.models
        newModelName = ""
        newModelPath = ""
        isAddModelSheetPresented = false
    }

    public func removeModel(id: UUID) {
        service.removeModel(id: id)
        registeredModels = service.models
    }

    // MARK: - Run Actions

    public func runClassification() {
        guard !classifyInputPath.isEmpty else {
            errorMessage = "Please provide a DICOM input file path."
            return
        }
        guard !classifyModelName.isEmpty else {
            errorMessage = "Please select or enter a model name."
            return
        }
        let job = AIAnalysisJob(
            inputPath: classifyInputPath,
            modelName: classifyModelName,
            task: .classification,
            outputFormat: classifyOutputFormat,
            confidenceThreshold: classifyConfidence,
            status: .pending
        )
        service.addJob(job)
        jobs = service.jobs
        classifyResult = "Job queued: \(job.id.uuidString.prefix(8))…\nRun dicom-ai classify \"\(classifyInputPath)\" --model \"\(classifyModelName)\" --confidence \(classifyConfidence)"
    }

    public func runSegmentation() {
        guard !segmentInputPath.isEmpty, !segmentModelName.isEmpty else {
            errorMessage = "Input path and model name are required."
            return
        }
        let job = AIAnalysisJob(
            inputPath: segmentInputPath,
            modelName: segmentModelName,
            task: .segmentation,
            status: .pending
        )
        service.addJob(job)
        jobs = service.jobs
        segmentResult = "Job queued: \(job.id.uuidString.prefix(8))…\nRun dicom-ai segment \"\(segmentInputPath)\" --model \"\(segmentModelName)\""
    }

    public func runDetection() {
        guard !detectInputPath.isEmpty, !detectModelName.isEmpty else {
            errorMessage = "Input path and model name are required."
            return
        }
        let job = AIAnalysisJob(
            inputPath: detectInputPath,
            modelName: detectModelName,
            task: .detection,
            confidenceThreshold: detectConfidence,
            status: .pending
        )
        service.addJob(job)
        jobs = service.jobs
        detectResult = "Job queued: \(job.id.uuidString.prefix(8))…\nRun dicom-ai detect \"\(detectInputPath)\" --model \"\(detectModelName)\" --confidence \(detectConfidence)"
    }

    public func runEnhancement() {
        guard !enhanceInputPath.isEmpty, !enhanceModelName.isEmpty else {
            errorMessage = "Input path and model name are required."
            return
        }
        let job = AIAnalysisJob(
            inputPath: enhanceInputPath,
            modelName: enhanceModelName,
            task: .enhancement,
            status: .pending
        )
        service.addJob(job)
        jobs = service.jobs
        enhanceResult = "Job queued: \(job.id.uuidString.prefix(8))…\nRun dicom-ai enhance \"\(enhanceInputPath)\" --model \"\(enhanceModelName)\""
    }

    public func runBatchAnalysis() {
        guard !batchInputDirectory.isEmpty, !batchModelName.isEmpty else {
            errorMessage = "Input directory and model name are required."
            return
        }
        let job = AIAnalysisJob(
            inputPath: batchInputDirectory,
            modelName: batchModelName,
            task: .classification,
            outputFormat: batchOutputFormat,
            confidenceThreshold: batchConfidence,
            status: .pending
        )
        service.addJob(job)
        jobs = service.jobs
    }

    public func removeJob(id: UUID) {
        service.removeJob(id: id)
        jobs = service.jobs
    }

    public func clearCompletedJobs() {
        service.clearCompleted()
        jobs = service.jobs
    }
}
