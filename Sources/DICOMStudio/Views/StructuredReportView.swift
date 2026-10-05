// StructuredReportView.swift
// DICOMStudio
//
// DICOM Studio — Structured Report viewer, builder, and terminology browser
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own (it shows the value type and relationship raw values of the model enums verified in StructuredReportModel.swift); UI state and layout

#if canImport(SwiftUI)
import SwiftUI

/// Structured Report view providing SR viewing, building, terminology browsing,
/// and CAD findings visualization.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct StructuredReportView: View {
    @Bindable var viewModel: StructuredReportViewModel

    public init(viewModel: StructuredReportViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            modePicker
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
            if !viewModel.documents.isEmpty {
                Text("\(viewModel.documents.count) document(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
            Text("View, create, and edit DICOM Structured Reports with coded terminology and CAD findings.")
        } actions: {
            HStack(spacing: 12) {
                Button("Open Viewer") {
                    viewModel.isViewerActive = true
                }
                Button("New Report") {
                    viewModel.isBuilderActive = true
                }
            }
        }
    }

    // MARK: - Viewer Content

    private var viewerContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SR Viewer")
                    .font(.headline)
                Spacer()

                Picker("View", selection: $viewModel.viewerMode) {
                    Text("Tree").tag(SRViewerMode.tree)
                    Text("List").tag(SRViewerMode.list)
                    Text("Narrative").tag(SRViewerMode.narrative)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("View mode")

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
                ContentUnavailableView(
                    "No Report Loaded",
                    systemImage: "doc.text",
                    description: Text("Open a DICOM Structured Report file to view its content tree.")
                )
            } else {
                List(viewModel.flattenedItems, id: \.item.id) { entry in
                    HStack {
                        ForEach(0..<entry.depth, id: \.self) { _ in
                            Rectangle()
                                .fill(.quaternary)
                                .frame(width: 1)
                                .padding(.horizontal, 6)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            if let conceptName = entry.item.conceptName {
                                Text(conceptName.codeMeaning)
                                    .font(.body)
                            } else {
                                Text(entry.item.valueType.rawValue)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            Text(contentItemDisplayValue(entry.item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Builder mode")

                Button("Validate") {
                    _ = viewModel.validateBuilder()
                }
                .accessibilityLabel("Validate report")

                Button("Create") {
                    _ = viewModel.createDocument()
                }
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
                .padding()
                .background(.red.opacity(0.05))
            }

            ContentUnavailableView {
                Label("Report Builder", systemImage: "doc.badge.plus")
            } description: {
                Text("Select a template or start from scratch to create a new Structured Report.")
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
        if let text = item.textValue { return text }
        if let code = item.codeValue { return code.codeMeaning }
        if let num = item.numericValue {
            if let unit = item.measurementUnit {
                return "\(num) \(unit.codeMeaning)"
            }
            return "\(num)"
        }
        if let date = item.dateValue { return date }
        if let time = item.timeValue { return time }
        if let pn = item.personName { return pn }
        if let uid = item.uidValue { return uid }
        return item.valueType.rawValue
    }
}
#endif
