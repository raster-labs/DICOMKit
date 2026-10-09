// DataExchangeView.swift
// DICOMStudio
//
// DICOM Studio — Data exchange, conversion, and developer tools view
//
// NEMA-verified: 2026a, checked 2026-10-05 — UI layout; the only standard-derived data is
// `CompressionAlgorithmHelpers.algorithms`/`isLossy` (transfer-syntax labels and lossy flags), which the codec pass
// verifies against PS3.6 2026a Table A-1 / PS3.5 Annex A and which is not claimed here; the Secondary Capture
// modality field is `ModalityPicker` (verified with G2).

#if canImport(SwiftUI)
import SwiftUI
import DICOMCore

/// Data exchange view providing JSON/XML conversion, image export,
/// transfer syntax conversion, DICOMDIR creation, PDF encapsulation,
/// and batch operations.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct DataExchangeView: View {
    @Bindable var viewModel: DataExchangeViewModel

    public init(viewModel: DataExchangeViewModel) {
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
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $viewModel.isJSONExportSheetPresented) {
            FilePathInputSheet(title: "Select DICOM File for JSON", label: "DICOM File Path") { path in
                viewModel.setJSONInputFilePath(path)
            }
        }
        .sheet(isPresented: $viewModel.isXMLExportSheetPresented) {
            FilePathInputSheet(title: "Select DICOM File for XML", label: "DICOM File Path") { path in
                viewModel.setXMLInputFilePath(path)
            }
        }
        .sheet(isPresented: $viewModel.isImageExportSheetPresented) {
            FilePathInputSheet(title: "Select DICOM File for Image Export", label: "DICOM File Path") { path in
                viewModel.setImageInputFilePath(path)
            }
        }
        .sheet(isPresented: $viewModel.isAddConversionJobSheetPresented) {
            AddConversionJobSheet { job in
                viewModel.addConversionJob(job)
            }
        }
        .sheet(isPresented: $viewModel.isAddDICOMDIREntrySheetPresented) {
            AddDICOMDIREntrySheet { entry in
                viewModel.addDICOMDIREntry(entry)
            }
        }
        .sheet(isPresented: $viewModel.isAddBatchJobSheetPresented) {
            AddBatchJobSheet { job in
                viewModel.addBatchJob(job)
            }
        }
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(DataExchangeTab.allCases, id: \.self) { tab in
                    Button {
                        viewModel.activeTab = tab
                    } label: {
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

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.activeTab {
        case .jsonConversion:
            jsonConversionContent
        case .xmlConversion:
            xmlConversionContent
        case .imageExport:
            imageExportContent
        case .transferSyntax:
            transferSyntaxContent
        case .dicomdir:
            dicomdirContent
        case .pdfEncapsulation:
            pdfContent
        case .batchOperations:
            batchContent
        case .compression:
            compressionContent
        case .secondaryCapture:
            secondaryCaptureContent
        }
    }

    // MARK: - JSON Conversion

    private var jsonConversionContent: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("DICOM → JSON")
                    .font(.headline)

                GroupBox("Input") {
                    HStack {
                        TextField("DICOM file path", text: $viewModel.jsonInputFilePath)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("DICOM input file path")
                        Button("Browse…") {
                            viewModel.isJSONExportSheetPresented = true
                        }
                        .accessibilityLabel("Browse for DICOM file")
                    }
                }

                GroupBox("Settings") {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Format", selection: $viewModel.jsonSettings.outputFormat) {
                            Text("Standard").tag(JSONOutputFormat.standard)
                            Text("Pretty").tag(JSONOutputFormat.pretty)
                            Text("Compact").tag(JSONOutputFormat.compact)
                        }
                        .accessibilityLabel("JSON output format")

                        Toggle("Include bulk data URIs", isOn: $viewModel.jsonSettings.includeBulkDataURIs)
                            .accessibilityLabel("Include bulk data URIs in JSON output")
                        Toggle("Metadata only", isOn: $viewModel.jsonSettings.metadataOnly)
                            .accessibilityLabel("Export metadata only")
                    }
                }

                Spacer()
            }
            .padding()
            .frame(minWidth: 250)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Output")
                        .font(.headline)
                    Spacer()
                    Button("Clear") {
                        viewModel.clearJSONOutput()
                    }
                    .disabled(viewModel.jsonOutput.isEmpty)
                    .accessibilityLabel("Clear JSON output")
                }

                if viewModel.jsonOutput.isEmpty {
                    ContentUnavailableView(
                        "No Output",
                        systemImage: "doc.text",
                        description: Text("Select a DICOM file and convert to see JSON output.")
                    )
                } else {
                    ScrollView {
                        Text(viewModel.jsonOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding()
        }
    }

    // MARK: - XML Conversion

    private var xmlConversionContent: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("DICOM → XML")
                    .font(.headline)

                GroupBox("Input") {
                    HStack {
                        TextField("DICOM file path", text: $viewModel.xmlInputFilePath)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("DICOM input file path for XML")
                        Button("Browse…") {
                            viewModel.isXMLExportSheetPresented = true
                        }
                        .accessibilityLabel("Browse for DICOM file")
                    }
                }

                GroupBox("Settings") {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Format", selection: $viewModel.xmlSettings.outputFormat) {
                            Text("Standard").tag(XMLOutputFormat.standard)
                            Text("Pretty").tag(XMLOutputFormat.pretty)
                            Text("No Keywords").tag(XMLOutputFormat.noKeywords)
                        }
                        .accessibilityLabel("XML output format")

                        Toggle("Include bulk data URIs", isOn: $viewModel.xmlSettings.includeBulkDataURIs)
                        Toggle("Metadata only", isOn: $viewModel.xmlSettings.metadataOnly)
                    }
                }

                Spacer()
            }
            .padding()
            .frame(minWidth: 250)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Output")
                        .font(.headline)
                    Spacer()
                    Button("Clear") { viewModel.clearXMLOutput() }
                        .disabled(viewModel.xmlOutput.isEmpty)
                }

                if viewModel.xmlOutput.isEmpty {
                    ContentUnavailableView(
                        "No Output",
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        description: Text("Select a DICOM file to convert to XML.")
                    )
                } else {
                    ScrollView {
                        Text(viewModel.xmlOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding()
        }
    }

    // MARK: - Image Export

    private var imageExportContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Image Export")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Source") {
                        HStack {
                            TextField("DICOM file path", text: $viewModel.imageInputFilePath)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("DICOM image source path")
                            Button("Browse…") {
                                viewModel.isImageExportSheetPresented = true
                            }
                        }
                    }

                    GroupBox("Export Settings") {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("Format", selection: $viewModel.imageExportSettings.format) {
                                Text("PNG").tag(ImageExportFormat.png)
                                Text("JPEG").tag(ImageExportFormat.jpeg)
                                Text("TIFF").tag(ImageExportFormat.tiff)
                            }
                            .accessibilityLabel("Export image format")

                            Picker("Resolution", selection: $viewModel.imageExportSettings.resolution) {
                                Text("Original").tag(ImageExportResolution.original)
                                Text("Half").tag(ImageExportResolution.half)
                                Text("Quarter").tag(ImageExportResolution.quarter)
                            }
                            .accessibilityLabel("Export resolution")

                            Toggle("Burn in window/level", isOn: $viewModel.imageExportSettings.burnInWindowLevel)
                            Toggle("Burn in annotations", isOn: $viewModel.imageExportSettings.burnInAnnotations)
                            Toggle("Export all frames", isOn: $viewModel.imageExportSettings.exportAllFrames)
                        }
                    }

                    Spacer()
                }
                .frame(minWidth: 250, maxWidth: 300)
                .padding()

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Exported Images")
                        .font(.headline)

                    if viewModel.exportedImagePaths.isEmpty {
                        ContentUnavailableView(
                            "No Exports",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("Export images from a DICOM file to view them here.")
                        )
                    } else {
                        List(viewModel.exportedImagePaths, id: \.self) { path in
                            HStack {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                                Text(path)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Transfer Syntax

    private var transferSyntaxContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transfer Syntax Conversion")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.isAddConversionJobSheetPresented = true
                } label: {
                    Label("Add Job", systemImage: "plus")
                }
                .accessibilityLabel("Add conversion job")
            }
            .padding()

            Divider()

            if viewModel.conversionJobs.isEmpty {
                ContentUnavailableView(
                    "No Conversion Jobs",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text("Add transfer syntax conversion jobs to convert between DICOM encoding formats.")
                )
            } else {
                List(viewModel.conversionJobs, id: \.id) { job in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.sourceFilePath)
                                .font(.body)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text("→")
                                    .font(.caption)
                                Text(job.targetDisplayName)
                                    .font(.caption)
                                Text(job.targetTransferSyntaxUID)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(job.status.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - DICOMDIR

    private var dicomdirContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DICOMDIR Creation")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.isAddDICOMDIREntrySheetPresented = true
                } label: {
                    Label("Add Entry", systemImage: "plus")
                }
                .accessibilityLabel("Add DICOMDIR entry")
            }
            .padding()

            GroupBox("Output Path") {
                TextField("DICOMDIR output path", text: $viewModel.dicomdirOutputPath)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("DICOMDIR output directory path")
            }
            .padding(.horizontal)

            Divider()
                .padding(.top, 8)

            if viewModel.dicomdirEntries.isEmpty {
                ContentUnavailableView(
                    "No Entries",
                    systemImage: "folder.badge.plus",
                    description: Text("Add DICOM files to create a DICOMDIR media directory.")
                )
            } else {
                List(viewModel.dicomdirEntries, id: \.id) { entry in
                    HStack {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.patientName)
                                .font(.body)
                            Text("\(entry.modalities.joined(separator: ", ")) • \(entry.seriesCount) series • \(entry.instanceCount) instances")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - PDF Encapsulation

    private var pdfContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PDF Encapsulation")
                    .font(.headline)
                Spacer()

                Picker("Mode", selection: $viewModel.pdfMode) {
                    ForEach(PDFEncapsulationMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("PDF encapsulation mode")
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("PDF File") {
                        HStack {
                            TextField("PDF file path", text: $viewModel.pdfInputPath)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("PDF input file path")
                        }
                    }

                    GroupBox("DICOM Output") {
                        HStack {
                            TextField("Output DICOM path", text: $viewModel.pdfOutputPath)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("DICOM output file path")
                        }
                    }

                    GroupBox("Patient Information") {
                        VStack(spacing: 8) {
                            TextField("Patient Name", text: $viewModel.pdfPatientName)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Patient name for PDF encapsulation")
                            TextField("Patient ID", text: $viewModel.pdfPatientID)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Patient ID for PDF encapsulation")
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Compression

    private var compressionContent: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("DICOM Compression")
                    .font(.headline)

                GroupBox("Input") {
                    HStack {
                        TextField("DICOM file or directory path", text: $viewModel.compressionInputPath)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Compression input path")
                        Button("Browse") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = true
                            if panel.runModal() == .OK {
                                viewModel.compressionInputPath = panel.url?.path ?? ""
                            }
                        }
                    }
                }

                GroupBox("Algorithm") {
                    Picker("Transfer Syntax", selection: $viewModel.compressionAlgorithm) {
                        ForEach(CompressionAlgorithmHelpers.algorithms, id: \.cli) { alg in
                            Text(alg.label).tag(alg.cli)
                        }
                    }
                    .accessibilityLabel("Compression algorithm")

                    if CompressionAlgorithmHelpers.isLossy(viewModel.compressionAlgorithm) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Lossy Quality: \(Int(viewModel.compressionQuality))")
                                .font(.caption)
                            Slider(value: $viewModel.compressionQuality, in: 1...100, step: 1)
                                .accessibilityLabel("Compression quality slider")
                        }
                    }
                }

                GroupBox("Output") {
                    HStack {
                        TextField("Output directory path", text: $viewModel.compressionOutputPath)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Compression output directory")
                        Button("Browse") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            if panel.runModal() == .OK {
                                viewModel.compressionOutputPath = panel.url?.path ?? ""
                            }
                        }
                    }
                }

                Button("Run Compression") {
                    viewModel.runCompression()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.compressionInputPath.isEmpty || viewModel.compressionOutputPath.isEmpty)
                .accessibilityLabel("Run DICOM compression")

                Spacer()
            }
            .padding()
            .frame(minWidth: 280)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Output", systemImage: "terminal")
                        .font(.headline)
                    Spacer()
                    if !viewModel.compressionResult.isEmpty {
                        Button("Clear") { viewModel.compressionResult = "" }
                            .font(.caption)
                    }
                }
                ScrollView {
                    Text(viewModel.compressionResult.isEmpty ? "Results will appear here." : viewModel.compressionResult)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(viewModel.compressionResult.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding()
            .frame(minWidth: 220)
        }
    }

    // MARK: - Secondary Capture

    private var secondaryCaptureContent: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Secondary Capture")
                    .font(.headline)

                GroupBox("Input Image") {
                    HStack {
                        TextField("Image file (PNG, JPEG, TIFF, BMP)", text: $viewModel.secondaryCaptureInputPath)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Input image path for secondary capture")
                        Button("Browse") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp]
                            if panel.runModal() == .OK {
                                viewModel.secondaryCaptureInputPath = panel.url?.path ?? ""
                            }
                        }
                    }
                }

                GroupBox("Patient / Study Metadata") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Patient Name")
                                .gridColumnAlignment(.trailing)
                            TextField("LAST^FIRST^MIDDLE", text: $viewModel.secondaryCapturePatientName)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Patient name")
                        }
                        GridRow {
                            Text("Patient ID")
                                .gridColumnAlignment(.trailing)
                            TextField("Patient identifier", text: $viewModel.secondaryCapturePatientID)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Patient ID")
                        }
                        GridRow {
                            Text("Study Date")
                                .gridColumnAlignment(.trailing)
                            TextField("YYYYMMDD", text: $viewModel.secondaryCaptureStudyDate)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Study date")
                        }
                        GridRow {
                            Text("Modality")
                                .gridColumnAlignment(.trailing)
                            ModalityPicker("Modality",
                                           selection: $viewModel.secondaryCaptureModality)
                        }
                    }
                }

                GroupBox("Output") {
                    HStack {
                        TextField("Output DICOM path (.dcm)", text: $viewModel.secondaryCaptureOutputPath)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Output DICOM file path")
                        Button("Browse") {
                            let panel = NSSavePanel()
                            panel.allowedContentTypes = [.init(filenameExtension: "dcm")!]
                            if panel.runModal() == .OK {
                                viewModel.secondaryCaptureOutputPath = panel.url?.path ?? ""
                            }
                        }
                    }
                }

                Button("Create Secondary Capture") {
                    viewModel.runSecondaryCapture()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.secondaryCaptureInputPath.isEmpty || viewModel.secondaryCaptureOutputPath.isEmpty)
                .accessibilityLabel("Create Secondary Capture DICOM file")

                Spacer()
            }
            .padding()
            .frame(minWidth: 280)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Output", systemImage: "terminal")
                        .font(.headline)
                    Spacer()
                    if !viewModel.secondaryCaptureResult.isEmpty {
                        Button("Clear") { viewModel.secondaryCaptureResult = "" }
                            .font(.caption)
                    }
                }
                ScrollView {
                    Text(viewModel.secondaryCaptureResult.isEmpty ? "Results will appear here." : viewModel.secondaryCaptureResult)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(viewModel.secondaryCaptureResult.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding()
            .frame(minWidth: 220)
        }
    }

    // MARK: - Batch Operations

    private var batchContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Batch Operations")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.isAddBatchJobSheetPresented = true
                } label: {
                    Label("New Batch", systemImage: "plus")
                }
                .accessibilityLabel("Create new batch job")
            }
            .padding()

            Divider()

            if viewModel.batchJobs.isEmpty {
                ContentUnavailableView(
                    "No Batch Jobs",
                    systemImage: "square.stack.3d.up",
                    description: Text("Create batch jobs to process multiple DICOM files simultaneously.")
                )
            } else {
                List(viewModel.batchJobs, id: \.id) { job in
                    HStack {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.operationType.rawValue)
                                .font(.body)
                            Text("\(job.totalCount) files • \(job.operationType.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if job.totalCount > 0 {
                            let progress = Double(job.processedCount) / Double(job.totalCount)
                            if progress > 0 && progress < 1.0 {
                                ProgressView(value: progress)
                                    .frame(width: 80)
                            }
                        }
                        Text(job.status.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - File Path Input Sheet

/// Generic sheet for entering a file path (used for JSON/XML/Image browse buttons).
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct FilePathInputSheet: View {
    let title: String
    let label: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filePath: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(label, text: $filePath)
                        .accessibilityLabel(label)
                }

                Section {
                    Text("Enter the full path to the DICOM file, or drag and drop a file onto this field.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Select") {
                        onSelect(filePath.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(filePath.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 200)
    }
}

// MARK: - Add Conversion Job Sheet

/// Sheet for adding a transfer syntax conversion job.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct AddConversionJobSheet: View {
    let onSave: (TransferSyntaxConversionJob) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var sourceFilePath: String = ""
    @State private var targetID: String = "1.2.840.10008.1.2.1"

    /// One selectable conversion target: an intent-aware label plus the UID and intent
    /// the job should carry. Keyed by `SelectableEncoding.id` so the two rows of a
    /// `both`-capable UID (`.91`/`.93`/`.203`) stay distinct in the picker.
    private struct Target: Identifiable {
        let id: String
        let label: String
        let uid: String
        let intent: EncodingIntent
    }

    // The J2K/HTJ2K targets are driven by the shared transfer-syntax catalog so they
    // stay canonical. The `both`-capable UIDs (.91/.93/.203) present two rows each —
    // Lossless and Lossy — so the user picks (and the job records) exactly which
    // codestream to produce, rather than an ambiguous single row.
    private let targets: [Target] = {
        func plain(_ ts: TransferSyntax, _ label: String) -> Target {
            Target(id: ts.uid, label: label, uid: ts.uid, intent: .notApplicable)
        }
        let j2kTargets: [Target] = TransferSyntax.selectableEncodings
            .filter { $0.transferSyntax.isJPEG2000 }
            .map { Target(id: $0.id, label: $0.displayName, uid: $0.uid, intent: $0.intent) }
        return [
            plain(.explicitVRLittleEndian, "Explicit VR Little Endian"),
            plain(.implicitVRLittleEndian, "Implicit VR Little Endian"),
            plain(.jpegLosslessSV1, "JPEG Lossless"),
        ] + j2kTargets + [
            plain(.rleLossless, "RLE Lossless"),
        ]
    }()

    private var selectedTarget: Target? { targets.first { $0.id == targetID } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    TextField("DICOM File Path", text: $sourceFilePath)
                        .accessibilityLabel("Source DICOM file path")
                }

                Section("Target Transfer Syntax") {
                    Picker("Transfer Syntax", selection: $targetID) {
                        ForEach(targets) { target in
                            Text(target.label).tag(target.id)
                        }
                    }
                    .accessibilityLabel("Target transfer syntax")

                    Text(selectedTarget?.uid ?? "")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Conversion Job")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let target = selectedTarget
                        let job = TransferSyntaxConversionJob(
                            sourceFilePath: sourceFilePath.trimmingCharacters(in: .whitespaces),
                            targetTransferSyntaxUID: target?.uid ?? targetID,
                            intent: target?.intent ?? .notApplicable
                        )
                        onSave(job)
                        dismiss()
                    }
                    .disabled(sourceFilePath.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 300)
    }
}

// MARK: - Add DICOMDIR Entry Sheet

/// Sheet for adding a DICOM study entry to the DICOMDIR.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct AddDICOMDIREntrySheet: View {
    let onSave: (DICOMDIREntry) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var studyInstanceUID: String = ""
    @State private var patientName: String = ""
    @State private var patientID: String = ""
    @State private var studyDate: String = ""
    @State private var modalities: String = "CT"
    @State private var seriesCount: String = "1"
    @State private var instanceCount: String = "1"

    var body: some View {
        NavigationStack {
            Form {
                Section("Patient") {
                    TextField("Patient Name", text: $patientName)
                        .accessibilityLabel("Patient name")
                    TextField("Patient ID", text: $patientID)
                        .accessibilityLabel("Patient ID")
                }

                Section("Study") {
                    TextField("Study Instance UID", text: $studyInstanceUID)
                        .accessibilityLabel("Study instance UID")
                    TextField("Study Date (YYYYMMDD)", text: $studyDate)
                        .accessibilityLabel("Study date")
                }

                Section("Contents") {
                    TextField("Modalities (comma separated)", text: $modalities)
                        .accessibilityLabel("Modalities")
                    TextField("Series Count", text: $seriesCount)
                        .accessibilityLabel("Number of series")
                    TextField("Instance Count", text: $instanceCount)
                        .accessibilityLabel("Number of instances")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add DICOMDIR Entry")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let modalityList = modalities
                            .components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        let entry = DICOMDIREntry(
                            studyInstanceUID: studyInstanceUID.trimmingCharacters(in: .whitespaces),
                            patientName: patientName.trimmingCharacters(in: .whitespaces),
                            patientID: patientID.trimmingCharacters(in: .whitespaces),
                            studyDate: studyDate.trimmingCharacters(in: .whitespaces),
                            modalities: modalityList,
                            seriesCount: Int(seriesCount) ?? 1,
                            instanceCount: Int(instanceCount) ?? 1
                        )
                        onSave(entry)
                        dismiss()
                    }
                    .disabled(patientName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              studyInstanceUID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 400)
    }
}

// MARK: - Add Batch Job Sheet

/// Sheet for creating a new batch operation job.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct AddBatchJobSheet: View {
    let onSave: (BatchJob) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var operationType: BatchOperationType = .tagModification
    @State private var inputPaths: String = ""
    @State private var outputDirectory: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Operation") {
                    Picker("Operation Type", selection: $operationType) {
                        ForEach(BatchOperationType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.sfSymbol).tag(type)
                        }
                    }
                    .accessibilityLabel("Batch operation type")
                }

                Section("Input Files") {
                    TextField("File or directory paths (one per line)", text: $inputPaths, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Input file paths")
                }

                Section("Output") {
                    TextField("Output Directory", text: $outputDirectory)
                        .accessibilityLabel("Output directory")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Batch Job")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let paths = inputPaths
                            .components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        let job = BatchJob(
                            operationType: operationType,
                            inputPaths: paths,
                            outputDirectory: outputDirectory.trimmingCharacters(in: .whitespaces)
                        )
                        onSave(job)
                        dismiss()
                    }
                    .disabled(inputPaths.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              outputDirectory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 380)
    }
}

// MARK: - Compression Algorithms Helpers

/// Platform-independent compression algorithm mapping for DataExchangeView.
public enum CompressionAlgorithmHelpers: Sendable {
    /// The compression targets offered, as (label, dicom-compress `--codec` token).
    ///
    /// Every row resolves its token through the shared catalog
    /// (``TransferSyntax/parseEncoding(_:)``), so the label carries the PS3.6
    /// Table A-1 name and the UID the token really produces, with the lossless /
    /// lossy intent for the `both`-capable UIDs (.91, .203, .112). Nothing here
    /// is spelled by hand: `jpeg-lossless` is .57 (not .70), `j2k-lossless` is a
    /// reversible codestream in the general .91 (not .90), `htj2k-lossless` is a
    /// reversible .203 (not .201) — the catalog says so and the label follows.
    public static let algorithms: [(label: String, cli: String)] = {
        func row(_ cli: String) -> (label: String, cli: String) {
            guard let enc = TransferSyntax.parseEncoding(cli) else { return (cli, cli) }
            return ("\(enc.displayName) (\(enc.uid))", cli)
        }
        return [
            row("rle"),                   // .5    RLE Lossless
            row("jpeg-baseline"),         // .4.50 JPEG Baseline (Process 1)
            row("jpeg-lossless"),         // .4.57 JPEG Lossless, Non-Hierarchical (Process 14)
            row("jpeg-ls-lossless"),      // .4.80 JPEG-LS Lossless Image Compression
            row("jpeg-ls"),               // .4.81 JPEG-LS Lossy (Near-Lossless) Image Compression
            row("j2k-lossless"),          // .4.91 JPEG 2000 Image Compression, reversible codestream
            row("j2k"),                   // .4.91 JPEG 2000 Image Compression, irreversible
            row("htj2k-lossless"),        // .4.203 High-Throughput JPEG 2000 Image Compression, reversible
            row("htj2k-rpcl"),            // .4.202 High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only)
            row("htj2k"),                 // .4.203 High-Throughput JPEG 2000 Image Compression, irreversible
            row("jpeg-xl-lossless-only"), // .4.110 JPEG XL Lossless
            row("jpeg-xl"),               // .4.112 JPEG XL, irreversible
        ]
    }()

    public static func isLossy(_ cliToken: String) -> Bool {
        return cliToken == "jpeg-baseline" || cliToken == "jpeg-ls" || cliToken == "j2k"
            || cliToken == "htj2k" || cliToken == "jpeg-xl"
    }
}
#endif
