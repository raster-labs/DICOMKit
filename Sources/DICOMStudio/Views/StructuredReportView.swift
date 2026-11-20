// StructuredReportView.swift
// DICOMStudio
//
// DICOM Studio — Structured Report viewer, builder, and terminology browser
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own (it shows the value type and relationship raw values of the model enums verified in StructuredReportModel.swift); UI state and layout

#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers

/// Structured Report view providing SR viewing, building, DICOM Part 10 `.dcm` import/export,
/// terminology browsing, and CAD findings visualization.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct StructuredReportView: View {
    @Bindable var viewModel: StructuredReportViewModel

    @State private var isImportingDCM = false
    @State private var isExportingDCM = false
    @State private var exportedDocument: DICOMBinaryDocument?
    @State private var exportFilename = "StructuredReport.dcm"

    public init(viewModel: StructuredReportViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            modePicker
            if let status = viewModel.statusMessage, !status.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewModel.statusMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.06))
            }
            Divider()

            if viewModel.isViewerActive {
                viewerContent
            } else if viewModel.isBuilderActive {
                builderContent
            } else if viewModel.isTerminologyBrowserActive {
                terminologyContent
            } else if viewModel.isCADOverlayActive {
                cadContent
            } else {
                welcomeContent
            }
        }
        .fileImporter(
            isPresented: $isImportingDCM,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    _ = try viewModel.importDICOMFile(from: url)
                } catch {
                    viewModel.statusMessage = "Could not read DICOM SR file: \(error.localizedDescription)"
                }
            case .failure(let error):
                viewModel.statusMessage = "Import cancelled or failed: \(error.localizedDescription)"
            }
        }
        .fileExporter(
            isPresented: $isExportingDCM,
            document: exportedDocument,
            contentType: .data,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                viewModel.statusMessage = "Exported Structured Report (.dcm)"
            case .failure(let error):
                viewModel.statusMessage = "Could not export .dcm: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 4) {
            modeButton(title: "Viewer", systemImage: "doc.text.magnifyingglass", isActive: viewModel.isViewerActive) {
                viewModel.isViewerActive = true
                viewModel.isBuilderActive = false
                viewModel.isTerminologyBrowserActive = false
                viewModel.isCADOverlayActive = false
            }
            modeButton(title: "Builder", systemImage: "doc.badge.plus", isActive: viewModel.isBuilderActive) {
                viewModel.isViewerActive = false
                viewModel.isBuilderActive = true
                viewModel.isTerminologyBrowserActive = false
                viewModel.isCADOverlayActive = false
            }
            modeButton(title: "Terminology", systemImage: "character.book.closed", isActive: viewModel.isTerminologyBrowserActive) {
                viewModel.isViewerActive = false
                viewModel.isBuilderActive = false
                viewModel.isTerminologyBrowserActive = true
                viewModel.isCADOverlayActive = false
            }
            modeButton(title: "CAD Findings", systemImage: "target", isActive: viewModel.isCADOverlayActive) {
                viewModel.isViewerActive = false
                viewModel.isBuilderActive = false
                viewModel.isTerminologyBrowserActive = false
                viewModel.isCADOverlayActive = true
            }
            Spacer()

            Button {
                isImportingDCM = true
            } label: {
                Label("Import .dcm…", systemImage: "square.and.arrow.down")
                    .font(.caption)
            }
            .accessibilityLabel("Import DICOM Structured Report")

            if viewModel.selectedDocumentIndex != nil, !viewModel.documents.isEmpty {
                Button {
                    triggerExportSelected()
                } label: {
                    Label("Export .dcm…", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .accessibilityLabel("Export selected Structured Report as DICOM")

                if viewModel.onPublishToStudy != nil {
                    Button {
                        viewModel.publishSelectedDocumentToStudy()
                    } label: {
                        Label("Save to Study (SR)", systemImage: "tray.and.arrow.down")
                            .font(.caption)
                    }
                    .accessibilityLabel("Save selected Structured Report to active study Series 9002")
                }
            }

            if !viewModel.documents.isEmpty {
                Text("\(viewModel.documents.count) document(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func triggerExportSelected() {
        do {
            let data = try viewModel.exportSelectedDocumentData()
            exportedDocument = DICOMBinaryDocument(data: data)
            if let idx = viewModel.selectedDocumentIndex, idx < viewModel.documents.count {
                let rawTitle = viewModel.documents[idx].title.codeMeaning
                    .replacingOccurrences(of: " ", with: "_")
                exportFilename = "SR_\(rawTitle).dcm"
            }
            isExportingDCM = true
        } catch {
            viewModel.statusMessage = error.localizedDescription
        }
    }

    private func modeButton(title: String, systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Welcome

    private var welcomeContent: some View {
        ContentUnavailableView {
            Label("Structured Reports", systemImage: "doc.text")
        } description: {
            Text("View, create, import, and export DICOM Structured Reports (SR) with coded terminology, measurements, and CAD findings.")
        } actions: {
            HStack(spacing: 12) {
                Button("Open Viewer") {
                    viewModel.isViewerActive = true
                }
                Button("New Report") {
                    if viewModel.selectedTemplate == nil {
                        viewModel.selectedTemplate = .radiologyReport
                    }
                    viewModel.isBuilderActive = true
                }
                Button("Import .dcm…") {
                    isImportingDCM = true
                }
            }
        }
    }

    // MARK: - Viewer Content

    private var viewerContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("SR Viewer")
                    .font(.headline)

                if viewModel.documents.count > 1 {
                    Picker(
                        "Document",
                        selection: Binding(
                            get: { viewModel.selectedDocumentIndex ?? 0 },
                            set: { viewModel.selectDocument(at: $0) }
                        )
                    ) {
                        ForEach(Array(viewModel.documents.enumerated()), id: \.element.id) { idx, doc in
                            Text("\(idx + 1). \(doc.title.codeMeaning) (\(doc.documentType.displayName))")
                                .tag(idx)
                        }
                    }
                    .frame(maxWidth: 320)
                }

                Spacer()

                Picker("View", selection: $viewModel.viewerMode) {
                    Text("Tree").tag(SRViewerMode.tree)
                    Text("List").tag(SRViewerMode.list)
                    Text("Narrative").tag(SRViewerMode.narrative)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                .accessibilityLabel("View mode")

                if viewModel.viewerMode == .tree {
                    Button {
                        viewModel.expandAll()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel("Expand all nodes")

                    Button {
                        viewModel.collapseAll()
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                    .accessibilityLabel("Collapse all nodes")
                }
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search content items…", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search structured report content")
                    .onSubmit { viewModel.performSearch() }
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
                if !viewModel.searchResults.isEmpty {
                    Text("\(viewModel.searchResults.count) matches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 6)

            Divider()

            if viewModel.flattenedItems.isEmpty {
                ContentUnavailableView {
                    Label("No Report Loaded", systemImage: "doc.text")
                } description: {
                    Text("Import a DICOM Structured Report (.dcm) or create a clinical report in the Builder.")
                } actions: {
                    HStack(spacing: 12) {
                        Button("Import .dcm…") { isImportingDCM = true }
                        Button("Create Report") {
                            if viewModel.selectedTemplate == nil {
                                viewModel.selectedTemplate = .radiologyReport
                            }
                            viewModel.isViewerActive = false
                            viewModel.isBuilderActive = true
                        }
                    }
                }
            } else {
                switch viewModel.viewerMode {
                case .tree:
                    treeViewerList
                case .list:
                    flatViewerList
                case .narrative:
                    narrativeViewerBody
                }
            }
        }
    }

    private var treeViewerList: some View {
        List(viewModel.flattenedItems, id: \.item.id) { entry in
            HStack(spacing: 6) {
                if entry.depth > 0 {
                    Spacer().frame(width: CGFloat(entry.depth - 1) * 16)
                }
                if entry.item.hasChildren {
                    Button {
                        viewModel.toggleNodeExpansion(entry.item.id)
                    } label: {
                        Image(systemName: entry.item.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 14)
                }

                Image(systemName: SRTreeHelpers.sfSymbolForValueType(entry.item.valueType))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(SRTreeHelpers.itemLabel(entry.item))
                            .font(entry.item.valueType == .container ? .body.weight(.semibold) : .body)
                        Text(entry.item.relationshipType.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                    let formatted = contentItemDisplayValue(entry.item)
                    if !formatted.isEmpty && entry.item.valueType != .container {
                        Text(formatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
            .listRowBackground(
                viewModel.searchResults.contains(entry.item.id)
                    ? Color.yellow.opacity(0.15)
                    : Color.clear
            )
        }
    }

    private var flatViewerList: some View {
        let leafEntries = viewModel.flattenedItems.filter { $0.item.valueType != .container }
        return List(leafEntries, id: \.item.id) { entry in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.item.valueType.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Text(SRTreeHelpers.itemLabel(entry.item))
                    .font(.body.weight(.medium))
                    .frame(minWidth: 140, alignment: .leading)
                Text(contentItemDisplayValue(entry.item))
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.vertical, 2)
            .listRowBackground(
                viewModel.searchResults.contains(entry.item.id)
                    ? Color.yellow.opacity(0.15)
                    : Color.clear
            )
        }
    }

    private var narrativeViewerBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let idx = viewModel.selectedDocumentIndex, idx < viewModel.documents.count {
                    let doc = viewModel.documents[idx]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(doc.title.codeMeaning)
                            .font(.title3.weight(.bold))
                        HStack(spacing: 14) {
                            Text("Type: \(doc.documentType.displayName)")
                            if !doc.patientName.isEmpty { Text("Patient: \(doc.patientName)") }
                            Text(doc.isComplete ? "COMPLETE" : "PARTIAL")
                            Text(doc.isVerified ? "VERIFIED" : "UNVERIFIED")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Divider()
                }

                ForEach(viewModel.flattenedItems, id: \.item.id) { entry in
                    if entry.depth > 0 {
                        if entry.item.valueType == .container {
                            Text(SRTreeHelpers.itemLabel(entry.item))
                                .font(.headline)
                                .padding(.top, 6)
                                .padding(.leading, CGFloat(max(0, entry.depth - 1)) * 14)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                if let concept = entry.item.conceptName {
                                    Text("\(concept.codeMeaning):")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Text(contentItemDisplayValue(entry.item))
                                    .font(.callout)
                                    .textSelection(.enabled)
                            }
                            .padding(.leading, CGFloat(max(0, entry.depth - 1)) * 14)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Builder Content

    private var builderContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SR Builder")
                    .font(.headline)
                Spacer()

                Picker("Mode", selection: $viewModel.builderMode) {
                    Text("Template").tag(SRBuilderMode.template)
                    Text("Free Form").tag(SRBuilderMode.freeForm)
                    Text("Import").tag(SRBuilderMode.importExisting)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .accessibilityLabel("Builder mode")

                Button("Validate") {
                    _ = viewModel.validateBuilder()
                }
                .accessibilityLabel("Validate report")

                Button("Create") {
                    _ = viewModel.createAndLoadDocument()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Create report")
            }
            .padding()

            Divider()

            if !viewModel.validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.validationErrors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.red.opacity(0.05))
            }

            if viewModel.builderMode == .importExisting {
                ContentUnavailableView {
                    Label("Import Existing Structured Report", systemImage: "square.and.arrow.down")
                } description: {
                    Text("Open a DICOM Part 10 Structured Report (.dcm) file to inspect, search, or re-export it.")
                } actions: {
                    Button("Choose DICOM SR File…") {
                        isImportingDCM = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                builderForm
            }
        }
    }

    private var builderForm: some View {
        Form {
            Section("Document Type & Template") {
                Picker("SR Document Type", selection: $viewModel.builderDocumentType) {
                    ForEach(SRBuilderHelpers.supportedDocumentTypes(for: viewModel.builderMode), id: \.self) { docType in
                        Text(docType.displayName).tag(docType)
                    }
                }
                .onChange(of: viewModel.builderDocumentType) { _, newType in
                    let templates = SRBuilderHelpers.availableTemplates(for: newType)
                    if let current = viewModel.selectedTemplate, !templates.contains(current) {
                        viewModel.selectedTemplate = templates.first
                    } else if viewModel.selectedTemplate == nil, viewModel.builderMode == .template {
                        viewModel.selectedTemplate = templates.first
                    }
                }

                let templates = SRBuilderHelpers.availableTemplates(for: viewModel.builderDocumentType)
                if viewModel.builderMode == .template && !templates.isEmpty {
                    Picker("Clinical Template", selection: $viewModel.selectedTemplate) {
                        Text("Select Template…").tag(Optional<SRTemplate>.none)
                        ForEach(templates, id: \.self) { tpl in
                            Text(tpl.displayName).tag(Optional(tpl))
                        }
                    }
                }
            }

            if viewModel.builderDocumentType == .keyObjectSelection {
                Section("Key Object Selection (TID 2010 — Modality KO)") {
                    Picker("Purpose (CID 7010)", selection: $viewModel.keyObjectPurpose) {
                        ForEach(KeyObjectPurpose.allCases, id: \.self) { purpose in
                            Text(purpose.displayName).tag(purpose)
                        }
                    }
                    TextField("Selection Description", text: $viewModel.keyObjectDescription, axis: .vertical)
                        .lineLimit(2...4)
                }
            } else if viewModel.builderDocumentType == .measurementReport {
                Section("Quantitative Measurements (TID 1500)") {
                    ForEach(Array(viewModel.builderMeasurements.enumerated()), id: \.element.id) { idx, item in
                        HStack {
                            Text(item.trackingIdentifier)
                                .font(.body.weight(.medium))
                            Spacer()
                            Text("\(String(format: "%.2f", item.value)) \(item.unit.codeMeaning)")
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                viewModel.builderMeasurements.remove(at: idx)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button {
                        let n = viewModel.builderMeasurements.count + 1
                        viewModel.builderMeasurements.append(
                            TrackedMeasurement(
                                trackingIdentifier: "Lesion \(n)",
                                trackingUID: UUID().uuidString,
                                value: 12.5,
                                unit: SRBuilderHelpers.ucumMillimeter
                            )
                        )
                    } label: {
                        Label("Add Sample Lesion Measurement", systemImage: "plus.circle")
                    }
                }
            } else if let template = viewModel.selectedTemplate, viewModel.builderMode == .template {
                Section("\(template.displayName) Sections (CID 7001)") {
                    ForEach(template.sections, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section)
                                .font(.caption.weight(.medium))
                            TextField(
                                "Enter \(section.lowercased())…",
                                text: Binding(
                                    get: { viewModel.sectionTexts[section] ?? "" },
                                    set: { viewModel.sectionTexts[section] = $0 }
                                ),
                                axis: .vertical
                            )
                            .lineLimit(2...6)
                        }
                    }
                }
            } else {
                Section("Clinical Findings / Diagnosis Narrative") {
                    TextField(
                        "Enter clinical findings, analysis, and diagnostic impression…",
                        text: $viewModel.freeFormText,
                        axis: .vertical
                    )
                    .lineLimit(4...10)
                }
            }

            Section("Patient, Author & Verification") {
                TextField("Patient Name (e.g. DOE^JOHN)", text: $viewModel.patientName)
                TextField("Patient ID", text: $viewModel.patientID)
                if viewModel.builderDocumentType != .keyObjectSelection {
                    TextField("Observer / Author Name (e.g. SMITH^JANE)", text: $viewModel.observerName)
                    Toggle("Mark Report as Complete", isOn: $viewModel.isComplete)
                    Toggle("Mark Report as Verified", isOn: $viewModel.isVerified)
                    if viewModel.isVerified {
                        TextField("Verifying Observer Name (Required)", text: $viewModel.verifyingObserverName)
                        TextField("Verifying Organization (Required)", text: $viewModel.verifyingOrganization)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Terminology Content

    private var terminologyContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Terminology Browser")
                    .font(.headline)
                Spacer()
                Picker("Scope", selection: $viewModel.terminologyScope) {
                    ForEach(TerminologySearchScope.allCases, id: \.self) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Terminology search scope")
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search terminology…", text: $viewModel.terminologyQuery)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search medical terminology")
                    .onSubmit { viewModel.searchTerminology() }
                if !viewModel.terminologyQuery.isEmpty {
                    Button {
                        viewModel.terminologyQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 6)

            Divider()

            if viewModel.terminologyResults.isEmpty && viewModel.favoriteTerms.isEmpty {
                ContentUnavailableView(
                    "Search Terminology",
                    systemImage: "character.book.closed",
                    description: Text("Search for coded medical terms from SNOMED CT, LOINC, and DICOM vocabularies.")
                )
            } else {
                List {
                    if !viewModel.favoriteTerms.isEmpty {
                        Section("Favorites") {
                            ForEach(viewModel.favoriteTerms, id: \.id) { term in
                                terminologyRow(term)
                            }
                        }
                    }
                    if !viewModel.terminologyResults.isEmpty {
                        Section("Results (\(viewModel.terminologyResults.count))") {
                            ForEach(viewModel.terminologyResults, id: \.id) { term in
                                terminologyRow(term)
                            }
                        }
                    }
                }
            }
        }
    }

    private func terminologyRow(_ term: TerminologyEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(term.concept.codeMeaning)
                    .font(.body)
                Text("\(term.concept.codingSchemeDesignator): \(term.concept.codeValue)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.toggleTermFavorite(term)
            } label: {
                Image(systemName: viewModel.isTermFavorite(term.concept) ? "star.fill" : "star")
                    .foregroundStyle(.yellow)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isTermFavorite(term.concept) ? "Remove from favorites" : "Add to favorites")
        }
    }

    // MARK: - CAD Content

    private var cadContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CAD Findings")
                    .font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    Text("Min Confidence:")
                        .font(.caption)
                    Slider(value: $viewModel.cadMinConfidence, in: 0...1)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Minimum confidence threshold")
                    Text(String(format: "%.0f%%", viewModel.cadMinConfidence * 100))
                        .font(.caption.monospaced())
                        .frame(width: 40)
                }
            }
            .padding()

            Divider()

            if viewModel.filteredCADFindings.isEmpty {
                ContentUnavailableView(
                    "No CAD Findings",
                    systemImage: "target",
                    description: Text("Load a CAD SR document to view computer-aided detection findings.")
                )
            } else {
                List(viewModel.filteredCADFindings, id: \.id, selection: $viewModel.selectedCADFindingID) { finding in
                    HStack {
                        Circle()
                            .fill(cadConfidenceColor(finding.confidence))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.locationDescription)
                                .font(.body)
                            HStack(spacing: 8) {
                                Text(finding.findingType.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.quaternary)
                                    .clipShape(Capsule())
                                Text(String(format: "%.0f%% confidence", finding.confidence * 100))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .accessibilityLabel("\(finding.locationDescription), \(Int(finding.confidence * 100)) percent confidence")
                }
            }
        }
    }

    // MARK: - Helpers

    private func cadConfidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 { return .red }
        if confidence >= 0.5 { return .orange }
        return .yellow
    }

    private func contentItemDisplayValue(_ item: SRContentItem) -> String {
        SRTreeHelpers.formatItemValue(item)
    }
}
#endif
