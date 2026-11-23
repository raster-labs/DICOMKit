// StructuredReportView.swift
// DICOMStudio
//
// DICOM Studio — Structured Report viewer, builder, and terminology browser
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own (it shows the value type and relationship raw values of the model enums verified in StructuredReportModel.swift); UI state and layout

#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import DICOMCore

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
            } else if viewModel.isValidationActive {
                validationContent
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
                viewModel.isValidationActive = false
                viewModel.isTerminologyBrowserActive = false
                viewModel.isCADOverlayActive = false
            }
            modeButton(title: "Builder", systemImage: "doc.badge.plus", isActive: viewModel.isBuilderActive) {
                if viewModel.selectedTemplate == nil && viewModel.selectedRegisteredTemplate == nil {
                    viewModel.selectedTemplate = .radiologyReport
                }
                viewModel.isViewerActive = false
                viewModel.isBuilderActive = true
                viewModel.isValidationActive = false
                viewModel.isTerminologyBrowserActive = false
                viewModel.isCADOverlayActive = false
            }
            modeButton(title: "Validation", systemImage: "checkmark.shield", isActive: viewModel.isValidationActive) {
                if viewModel.selectedTemplate == nil && viewModel.selectedRegisteredTemplate == nil && viewModel.documents.isEmpty {
                    viewModel.selectedTemplate = .radiologyReport
                }
                viewModel.isViewerActive = false
                viewModel.isBuilderActive = false
                viewModel.isValidationActive = true
                viewModel.isTerminologyBrowserActive = false
                viewModel.isCADOverlayActive = false
                _ = viewModel.validateCurrentReport()
            }
            modeButton(title: "Terminology", systemImage: "character.book.closed", isActive: viewModel.isTerminologyBrowserActive) {
                viewModel.isViewerActive = false
                viewModel.isBuilderActive = false
                viewModel.isValidationActive = false
                viewModel.isTerminologyBrowserActive = true
                viewModel.isCADOverlayActive = false
            }
            modeButton(title: "CAD Findings", systemImage: "target", isActive: viewModel.isCADOverlayActive) {
                viewModel.isViewerActive = false
                viewModel.isBuilderActive = false
                viewModel.isValidationActive = false
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
        Group {
            if !viewModel.hasActiveViewerImage {
                emptyViewerRestrictionView
            } else {
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
        }
    }

    private var emptyViewerRestrictionView: some View {
        ContentUnavailableView {
            Label("Open an Image in the Viewer to Create a Structured Report", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("The Image Viewer is currently empty. Open an image or study in the Image Viewer first so you can analyze the image alongside the Structured Reports window and inherit the study's Patient ID and DICOM headers.")
        } actions: {
            HStack(spacing: 12) {
                if let goLibrary = viewModel.onNavigateToLibrary {
                    Button {
                        goLibrary()
                    } label: {
                        Label("Open Study Library", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let goViewer = viewModel.onNavigateToViewer {
                    Button {
                        goViewer()
                    } label: {
                        Label("Go to Image Viewer", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    isImportingDCM = true
                } label: {
                    Label("Import Existing SR (.dcm)…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
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
                .disabled(!viewModel.hasActiveViewerImage)
                .accessibilityLabel("Validate report")

                Button("Create") {
                    _ = viewModel.createAndLoadDocument()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasActiveViewerImage)
                .accessibilityLabel("Create report")
            }
            .padding()

            if let ctx = viewModel.activeStudyContext, viewModel.hasActiveViewerImage {
                HStack(spacing: 8) {
                    Image(systemName: "person.text.rectangle.fill")
                        .foregroundStyle(Color.accentColor)
                    let pName = (ctx.patientName?.isEmpty == false) ? ctx.patientName! : "Unnamed Patient"
                    let pID = (ctx.patientID?.isEmpty == false) ? ctx.patientID! : "No Patient ID"
                    let studyDesc = (ctx.studyDescription?.isEmpty == false) ? " • \(ctx.studyDescription!)" : ""
                    Text("Reporting on Active Viewer Study: \(pName) (ID: \(pID))\(studyDesc)")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Button("Re-sync Metadata") {
                        if let name = ctx.patientName, !name.isEmpty { viewModel.patientName = name }
                        if let pid = ctx.patientID, !pid.isEmpty { viewModel.patientID = pid }
                        if let suid = ctx.studyInstanceUID, !suid.isEmpty { viewModel.studyInstanceUID = suid }
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.08))
            }

            Divider()

            if !viewModel.hasActiveViewerImage && viewModel.builderMode != .importExisting {
                emptyViewerRestrictionView
            } else {
                if !viewModel.validationErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Report Validation Failed (\(viewModel.validationErrors.count) issue(s))", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                            Spacer()
                            Button("Open Validation Tab") {
                                viewModel.isBuilderActive = false
                                viewModel.isValidationActive = true
                            }
                            .font(.caption)
                        }
                        ForEach(viewModel.validationErrors, id: \.self) { error in
                            Label(error, systemImage: "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.red.opacity(0.08))
                } else if let validMsg = viewModel.validationSuccessMessage {
                    HStack(spacing: 10) {
                        Label(validMsg, systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                        Spacer()
                        Button("View Conformance Report") {
                            viewModel.isBuilderActive = false
                            viewModel.isValidationActive = true
                        }
                        .font(.caption)
                        Button {
                            viewModel.validationSuccessMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.green.opacity(0.08))
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
    }

    private var builderForm: some View {
        Form {
            Section("Document Type & Template (DICOMCore Registry)") {
                Picker("SR Document Type", selection: $viewModel.builderDocumentType) {
                    let supported = SRBuilderHelpers.supportedDocumentTypes(for: viewModel.builderMode)
                    let clinical = supported.filter(\.isClinicalImagingReportType)
                    let specialized = supported.filter { !$0.isClinicalImagingReportType }

                    Section("Clinical Imaging Report IODs (Prioritized)") {
                        ForEach(clinical, id: \.self) { docType in
                            Text(docType.displayName).tag(docType)
                        }
                    }
                    if !specialized.isEmpty {
                        Section("All Other PS3.6 SR Storage SOP Classes") {
                            ForEach(specialized, id: \.self) { docType in
                                Text(docType.displayName).tag(docType)
                            }
                        }
                    }
                }
                .onChange(of: viewModel.builderDocumentType) { _, newType in
                    let templates = SRBuilderHelpers.availableTemplates(for: newType)
                    if let current = viewModel.selectedTemplate, !templates.contains(current) {
                        viewModel.selectedTemplate = templates.first
                    } else if viewModel.selectedTemplate == nil,
                              viewModel.selectedRegisteredTemplate == nil,
                              viewModel.builderMode == .template {
                        viewModel.selectedTemplate = templates.first
                    }
                    if let defaultTID = newType.coreDocumentType.defaultRootTemplateIdentifier,
                       let descriptor = DICOMCore.TemplateRegistry.shared.descriptor(for: defaultTID) {
                        viewModel.selectedRegisteredTemplate = descriptor
                    }
                }

                LabeledContent("SOP Class UID") {
                    Text(viewModel.builderDocumentType.sopClassUID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Text(viewModel.builderDocumentType.coreDocumentType.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.builderMode == .template {
                    let clinicalTemplates = SRBuilderHelpers.availableTemplates(for: viewModel.builderDocumentType)
                    if !clinicalTemplates.isEmpty {
                        Picker("Clinical Report Preset (CID 7000 / 7001)", selection: $viewModel.selectedTemplate) {
                            Text("None (Use PS3.16 TID Template below)").tag(Optional<SRTemplate>.none)
                            ForEach(clinicalTemplates, id: \.self) { tpl in
                                Text(tpl.displayName).tag(Optional(tpl))
                            }
                        }
                        .onChange(of: viewModel.selectedTemplate) { _, newPreset in
                            if newPreset != nil {
                                viewModel.selectedRegisteredTemplate = nil
                            }
                        }
                    }

                    let registeredTemplates = SRBuilderHelpers.registeredTemplates(for: viewModel.builderDocumentType)
                    let rootTIDs = registeredTemplates.filter(\.isRoot)
                    let subTIDs = registeredTemplates.filter { !$0.isRoot }

                    Picker("PS3.16 Registered Template (All \(registeredTemplates.count) TIDs)", selection: $viewModel.selectedRegisteredTemplate) {
                        Text("None (Use Clinical Preset above)").tag(Optional<DICOMCore.SRRegisteredTemplateDescriptor>.none)
                        Section("Root Document Templates (PS3.16)") {
                            ForEach(rootTIDs) { descriptor in
                                Text(descriptor.formattedDisplayName).tag(Optional(descriptor))
                            }
                        }
                        Section("All Registered Sub-Templates (PS3.16)") {
                            ForEach(subTIDs) { descriptor in
                                Text(descriptor.formattedDisplayName).tag(Optional(descriptor))
                            }
                        }
                    }
                    .onChange(of: viewModel.selectedRegisteredTemplate) { _, newTID in
                        if newTID != nil {
                            viewModel.selectedTemplate = nil
                        }
                    }

                    if let reg = viewModel.selectedRegisteredTemplate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(reg.formattedDisplayName) • Root VT: \(reg.rootValueType.rawValue) • \(reg.isExtensible ? "Extensible" : "Non-Extensible") • \(reg.rows.count) row(s)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            if !reg.templateDescription.isEmpty {
                                Text(reg.templateDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if viewModel.builderDocumentType == .keyObjectSelection {
                Section("Key Object Selection (TID 2010 — Modality KO)") {
                    Picker("Purpose (CID 7010)", selection: $viewModel.keyObjectPurpose) {
                        ForEach(KeyObjectPurpose.allCases, id: \.self) { purpose in
                            Text("\(purpose.displayName) — \(purpose.coreDescriptor.titleConcept.codeMeaning) (\(purpose.coreDescriptor.titleConcept.codeValue))")
                                .tag(purpose)
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
                            Picker(
                                "Unit",
                                selection: Binding(
                                    get: { item.unit.codeValue },
                                    set: { newCode in
                                        if let match = SRBuilderHelpers.availableMeasurementUnits.first(where: { $0.rawValue == newCode }) {
                                            viewModel.builderMeasurements[idx] = TrackedMeasurement(
                                                id: item.id,
                                                trackingIdentifier: item.trackingIdentifier,
                                                trackingUID: item.trackingUID,
                                                value: item.value,
                                                unit: CodedConcept(coreConcept: match.ucumConcept),
                                                timePoint: item.timePoint,
                                                trackingMethod: item.trackingMethod,
                                                findingSite: item.findingSite
                                            )
                                        }
                                    }
                                )
                            ) {
                                ForEach(SRBuilderHelpers.availableMeasurementUnits) { unitDesc in
                                    Text(unitDesc.displayName).tag(unitDesc.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 145)

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
            } else if viewModel.builderMode == .template,
                      let templateName = viewModel.activeTemplateDisplayName,
                      !viewModel.activeTemplateSections.isEmpty {
                Section("\(templateName) Sections (CID 7001 / PS3.16)") {
                    ForEach(viewModel.activeTemplateSections, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            let headingConcept = SRBuilderHelpers.sectionHeading(for: section)
                            Text("\(section) (\(headingConcept.codingSchemeDesignator) \(headingConcept.codeValue))")
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

    // MARK: - Report Validation Content

    private var validationContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("SR Conformance & Template Validation", systemImage: "checkmark.shield")
                    .font(.headline)

                if !viewModel.documents.isEmpty {
                    Picker(
                        "Loaded Report",
                        selection: Binding(
                            get: { viewModel.selectedDocumentIndex ?? 0 },
                            set: {
                                viewModel.selectDocument(at: $0)
                                _ = viewModel.validateCurrentReport()
                            }
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

                let registeredTemplates = SRBuilderHelpers.allRegisteredTemplates
                let rootTIDs = registeredTemplates.filter(\.isRoot)
                let subTIDs = registeredTemplates.filter { !$0.isRoot }
                Picker("PS3.16 TID", selection: $viewModel.validationTargetTemplate) {
                    Text("Auto / Document TID").tag(Optional<DICOMCore.SRRegisteredTemplateDescriptor>.none)
                    Section("Root Document Templates (PS3.16)") {
                        ForEach(rootTIDs) { descriptor in
                            Text(descriptor.formattedDisplayName).tag(Optional(descriptor))
                        }
                    }
                    Section("Sub-Templates (PS3.16)") {
                        ForEach(subTIDs) { descriptor in
                            Text(descriptor.formattedDisplayName).tag(Optional(descriptor))
                        }
                    }
                }
                .frame(maxWidth: 280)
                .onChange(of: viewModel.validationTargetTemplate) { _, _ in
                    _ = viewModel.validateCurrentReport()
                }

                Button("Validate Loaded / Draft") {
                    _ = viewModel.validateCurrentReport()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Run SR validation")

                Button("Validate Builder Draft") {
                    _ = viewModel.validateBuilder()
                }
                .accessibilityLabel("Validate current SR Builder draft")
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let validMsg = viewModel.validationSuccessMessage, viewModel.validationErrors.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("VALID STRUCTURED REPORT")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.green)
                                Text(validMsg)
                                    .font(.callout)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.green.opacity(0.1)))
                    } else if !viewModel.validationErrors.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text("INVALID STRUCTURED REPORT — \(viewModel.validationErrors.count) Error(s)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.red)
                            }
                            ForEach(viewModel.validationErrors, id: \.self) { err in
                                Label(err, systemImage: "xmark.circle")
                                    .font(.callout)
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.red.opacity(0.1)))
                    }

                    if !viewModel.validationChecks.isEmpty {
                        GroupBox("DICOM PS3.3 / PS3.16 Conformance Checklist") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(viewModel.validationChecks) { check in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(check.passed ? .green : .red)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(check.title)
                                                .font(.callout.weight(.semibold))
                                            Text(check.detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    if !viewModel.validationWarnings.isEmpty {
                        GroupBox("PS3.16 Template & Dataset Notices (\(viewModel.validationWarnings.count))") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(viewModel.validationWarnings, id: \.self) { warn in
                                    Label(warn, systemImage: "info.circle")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
            }
        }
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

/// Sidebar destination view for `.reporting` ("Structured Reports").
///
/// - When an image/study is loaded in the Image Viewer (`viewModel.imageViewerViewModel.dicomFile != nil`):
///   synchronizes study/patient metadata, raises the dedicated `StudioWindowID.structuredReports` window,
///   and returns the main window to the Image Viewer so both windows are visible side-by-side.
/// - When the Image Viewer is empty (`viewModel.imageViewerViewModel.dicomFile == nil`):
///   blocks opening the SR window and displays a restriction message instructing the user to open an
///   image in the Viewer first.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct StructuredReportLauncherView: View {
    @Bindable var viewModel: MainViewModel

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    public init(viewModel: MainViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        #if os(macOS)
        Group {
            if viewModel.imageViewerViewModel.dicomFile != nil {
                ContentUnavailableView {
                    Label("Structured Reports", systemImage: "doc.text")
                } description: {
                    Text("Structured Reports opens in its own window alongside the Image Viewer so you can analyze images while writing your report.")
                } actions: {
                    HStack(spacing: 12) {
                        Button {
                            launchSRWindowAlongsideViewer()
                        } label: {
                            Label("Open Structured Reports Window", systemImage: "macwindow")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            viewModel.selectedDestination = .viewer
                        } label: {
                            Label("Return to Image Viewer", systemImage: "eye")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .onAppear {
                    launchSRWindowAlongsideViewer()
                }
            } else {
                ContentUnavailableView {
                    Label("Open an Image in the Viewer to Create a Structured Report", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text("The Image Viewer is currently empty. Open an image or study in the Image Viewer first so you can analyze the image alongside the Structured Reports window and inherit the study's Patient ID and DICOM headers.")
                } actions: {
                    HStack(spacing: 12) {
                        Button {
                            viewModel.selectedDestination = .library
                        } label: {
                            Label("Open Study Library", systemImage: "folder")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            viewModel.selectedDestination = .viewer
                        } label: {
                            Label("Go to Image Viewer", systemImage: "eye")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .onAppear {
                    viewModel.syncStructuredReportWithViewer()
                }
            }
        }
        .navigationTitle("Structured Reports")
        #else
        StructuredReportView(viewModel: viewModel.structuredReportViewModel)
        #endif
    }

    #if os(macOS)
    private func launchSRWindowAlongsideViewer() {
        viewModel.syncStructuredReportWithViewer()
        let srVM = viewModel.structuredReportViewModel
        if !srVM.isViewerActive
            && !srVM.isBuilderActive
            && !srVM.isValidationActive
            && !srVM.isTerminologyBrowserActive
            && !srVM.isCADOverlayActive {
            if srVM.selectedTemplate == nil && srVM.selectedRegisteredTemplate == nil {
                srVM.selectedTemplate = .radiologyReport
            }
            srVM.isBuilderActive = true
        }
        openWindow(id: StudioWindowID.structuredReports)
        Task { @MainActor in
            viewModel.selectedDestination = .viewer
        }
    }
    #endif
}
#endif
