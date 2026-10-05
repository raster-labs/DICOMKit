// AIAnalysisView.swift
// DICOMStudio
//
// DICOM Studio — AI/ML Analysis view (dicom-ai)
// Reference: CoreML, Vision framework; DICOM SEG / SR output is produced by dicom-ai (PS3.3 A.51, A.35)
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (UI state and layout only)

#if canImport(SwiftUI)
import SwiftUI

/// AI/ML Analysis view providing classification, segmentation, object detection,
/// image enhancement, batch analysis, and model registry.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct AIAnalysisView: View {
    @Bindable var viewModel: AIAnalysisViewModel

    public init(viewModel: AIAnalysisViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabPicker
            Divider()
            tabContent
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Processing…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let msg = viewModel.errorMessage { Text(msg) }
        }
        .sheet(isPresented: $viewModel.isAddModelSheetPresented) {
            addModelSheet
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(AIAnalysisTab.allCases) { tab in
                    Button { viewModel.activeTab = tab } label: {
                        Label(tab.displayName, systemImage: tab.sfSymbol)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(viewModel.activeTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.displayName)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.activeTab {
        case .imageClassification: classificationContent
        case .segmentation:        segmentationContent
        case .objectDetection:     detectionContent
        case .imageEnhancement:    enhancementContent
        case .batchAnalysis:       batchContent
        case .modelRegistry:       modelRegistryContent
        }
    }

    // MARK: - Classification

    private var classificationContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Image Classification")
                    .font(.title2).bold()

                GroupBox("Input") {
                    TextField("DICOM file path", text: $viewModel.classifyInputPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("DICOM input file path")
                }

                GroupBox("Model") {
                    TextField("Model name or path (.mlmodel)", text: $viewModel.classifyModelName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("CoreML model name")
                }

                GroupBox("Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Output Format", selection: $viewModel.classifyOutputFormat) {
                            ForEach(AIOutputFormat.allCases) { fmt in
                                Text(fmt.displayName).tag(fmt)
                            }
                        }
                        .accessibilityLabel("Output format")

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Confidence Threshold: \(viewModel.classifyConfidence, specifier: "%.2f")")
                                .font(.caption)
                            Slider(value: $viewModel.classifyConfidence, in: 0...1, step: 0.05)
                                .accessibilityLabel("Confidence threshold")
                        }
                    }
                }

                Button("Run Classification") {
                    viewModel.runClassification()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Run image classification")

                if !viewModel.classifyResult.isEmpty {
                    GroupBox("Result") {
                        Text(viewModel.classifyResult)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Segmentation

    private var segmentationContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Image Segmentation")
                    .font(.title2).bold()

                GroupBox("Input") {
                    TextField("DICOM file path", text: $viewModel.segmentInputPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("DICOM input file path")
                }

                GroupBox("Model") {
                    TextField("Segmentation model name (.mlmodel)", text: $viewModel.segmentModelName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Segmentation model")
                }

                GroupBox("Output") {
                    TextField("Output DICOM SEG path (optional)", text: $viewModel.segmentOutputPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Output DICOM SEG path")
                }

                Button("Run Segmentation") {
                    viewModel.runSegmentation()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Run segmentation")

                if !viewModel.segmentResult.isEmpty {
                    GroupBox("Result") {
                        Text(viewModel.segmentResult)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Detection

    private var detectionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Object Detection")
                    .font(.title2).bold()

                GroupBox("Input") {
                    TextField("DICOM file path", text: $viewModel.detectInputPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("DICOM input file path")
                }

                GroupBox("Model") {
                    TextField("Detection model name (.mlmodel)", text: $viewModel.detectModelName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Detection model")
                }

                GroupBox("Settings") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confidence Threshold: \(viewModel.detectConfidence, specifier: "%.2f")")
                            .font(.caption)
                        Slider(value: $viewModel.detectConfidence, in: 0...1, step: 0.05)
                            .accessibilityLabel("Detection confidence threshold")
                    }
                }

                Button("Run Detection") {
                    viewModel.runDetection()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Run object detection")

                if !viewModel.detectResult.isEmpty {
                    GroupBox("Result") {
                        Text(viewModel.detectResult)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Enhancement

    private var enhancementContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Image Enhancement")
                    .font(.title2).bold()

                GroupBox("Input") {
                    TextField("DICOM file path", text: $viewModel.enhanceInputPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("DICOM input file path")
                }

                GroupBox("Model") {
                    TextField("Enhancement model name (.mlmodel)", text: $viewModel.enhanceModelName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Enhancement model")
                }

                GroupBox("Output") {
                    TextField("Output DICOM path (optional)", text: $viewModel.enhanceOutputPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Output DICOM path")
                }

                Button("Run Enhancement") {
                    viewModel.runEnhancement()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Run image enhancement")

                if !viewModel.enhanceResult.isEmpty {
                    GroupBox("Result") {
                        Text(viewModel.enhanceResult)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Batch Analysis

    private var batchContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Batch Analysis")
                    .font(.title2).bold()

                GroupBox("Input") {
                    TextField("Input directory (series/*.dcm)", text: $viewModel.batchInputDirectory)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Input directory")
                }

                GroupBox("Model") {
                    TextField("Model name (.mlmodel)", text: $viewModel.batchModelName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Batch analysis model")
                }

                GroupBox("Output") {
                    TextField("Output file path (optional)", text: $viewModel.batchOutputPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Output results path")
                }

                GroupBox("Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Output Format", selection: $viewModel.batchOutputFormat) {
                            ForEach(AIOutputFormat.allCases) { fmt in
                                Text(fmt.displayName).tag(fmt)
                            }
                        }
                        .accessibilityLabel("Batch output format")

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Confidence Threshold: \(viewModel.batchConfidence, specifier: "%.2f")")
                                .font(.caption)
                            Slider(value: $viewModel.batchConfidence, in: 0...1, step: 0.05)
                                .accessibilityLabel("Batch confidence threshold")
                        }
                    }
                }

                Button("Queue Batch Job") {
                    viewModel.runBatchAnalysis()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Queue batch analysis job")

                if !viewModel.jobs.isEmpty {
                    GroupBox("Jobs (\(viewModel.jobs.count))") {
                        VStack(spacing: 4) {
                            ForEach(viewModel.jobs) { job in
                                HStack {
                                    Image(systemName: job.status.sfSymbol)
                                        .foregroundStyle(job.status == .completed ? .green : job.status == .failed ? .red : .secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(job.modelName).font(.caption).bold()
                                        Text(job.inputPath).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(job.status.displayName).font(.caption2).foregroundStyle(.secondary)
                                    Button {
                                        viewModel.removeJob(id: job.id)
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove job")
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    Button("Clear Completed") {
                        viewModel.clearCompletedJobs()
                    }
                    .font(.caption)
                }
            }
            .padding()
        }
    }

    // MARK: - Model Registry

    private var modelRegistryContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Registered CoreML Models")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.isAddModelSheetPresented = true
                } label: {
                    Label("Add Model", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Add CoreML model")
            }
            .padding()

            Divider()

            if viewModel.registeredModels.isEmpty {
                ContentUnavailableView(
                    "No Models Registered",
                    systemImage: "brain.head.profile",
                    description: Text("Add a CoreML model (.mlmodel or .mlmodelc) to use with DICOM AI analysis.")
                )
            } else {
                List {
                    ForEach(viewModel.registeredModels) { model in
                        HStack {
                            Image(systemName: model.task.sfSymbol)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name).font(.subheadline).bold()
                                Text(model.task.displayName).font(.caption).foregroundStyle(.secondary)
                                Text(model.modelPath).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            Spacer()
                            Text("v\(model.version)").font(.caption2).foregroundStyle(.secondary)
                            Button {
                                viewModel.removeModel(id: model.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove model \(model.name)")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - Add Model Sheet

    private var addModelSheet: some View {
        NavigationStack {
            Form {
                Section("Model Details") {
                    TextField("Model name", text: $viewModel.newModelName)
                        .accessibilityLabel("Model name")
                    TextField("Model file path (.mlmodel or .mlmodelc)", text: $viewModel.newModelPath)
                        .accessibilityLabel("Model file path")
                    Picker("Task", selection: $viewModel.newModelTask) {
                        ForEach(AIModelTask.allCases) { task in
                            Text(task.displayName).tag(task)
                        }
                    }
                    .accessibilityLabel("Model task type")
                }
            }
            .navigationTitle("Add CoreML Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.isAddModelSheetPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.addModel()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 250)
    }
}
#endif
