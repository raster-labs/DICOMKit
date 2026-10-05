// ArchiveManagementView.swift
// DICOMStudio
//
// DICOM Studio — Archive Management view (dicom-archive)
// Reference: DICOM PS3.10 (Media Storage and File Format)
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (layout; the modality field is
// `ModalityPicker`, verified with G2).

#if canImport(SwiftUI)
import SwiftUI

/// Archive Management view providing DICOM archive browse, import, export,
/// search, and statistics.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct ArchiveManagementView: View {
    @Bindable var viewModel: ArchiveManagementViewModel

    public init(viewModel: ArchiveManagementViewModel) {
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
                ProgressView("Working…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let msg = viewModel.errorMessage { Text(msg) }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ArchiveManagementTab.allCases) { tab in
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
        case .browse:    browseContent
        case .importTab: importContent
        case .exportTab: exportContent
        case .search:    searchContent
        case .stats:     statisticsContent
        }
    }

    // MARK: - Browse

    private var browseContent: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Archive directory", text: $viewModel.archivePath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Archive directory path")
                    Button("Load") { viewModel.loadArchive() }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Load archive")
                }
                .padding(8)
                Divider()

                if viewModel.patients.isEmpty {
                    ContentUnavailableView(
                        "No Archive Loaded",
                        systemImage: "archivebox",
                        description: Text("Enter an archive directory path and click Load, or use dicom-archive list.")
                    )
                } else {
                    List(selection: $viewModel.selectedPatientID) {
                        ForEach(viewModel.patients) { patient in
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(patient.patientName).font(.subheadline).bold()
                                    Text("ID: \(patient.patientID)").font(.caption).foregroundStyle(.secondary)
                                    Text("\(patient.studyCount) studies · \(patient.formattedSize)")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .tag(patient.id)
                        }
                    }
                }

                if !viewModel.statusMessage.isEmpty {
                    Divider()
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minWidth: 240, idealWidth: 280)

            if let selected = viewModel.patients.first(where: { $0.id == viewModel.selectedPatientID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(selected.patientName)
                            .font(.title2).bold()

                        GroupBox("Patient") {
                            LabeledContent("Patient ID") { Text(selected.patientID) }
                            LabeledContent("Studies") { Text("\(selected.studyCount)") }
                            LabeledContent("Instances") { Text("\(selected.instanceCount)") }
                            LabeledContent("Total Size") { Text(selected.formattedSize) }
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Select a Patient",
                    systemImage: "person",
                    description: Text("Select a patient to view their studies.")
                )
            }
        }
    }

    // MARK: - Import

    private var importContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Import into Archive")
                    .font(.title2).bold()

                GroupBox("Source") {
                    TextField("Source directory path", text: $viewModel.importOptions.sourceDirectory)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Source directory")
                }

                GroupBox("Archive") {
                    TextField("Archive directory", text: $viewModel.archivePath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Archive directory")
                }

                GroupBox("Options") {
                    Toggle("Recursive import", isOn: $viewModel.importOptions.isRecursive)
                        .accessibilityLabel("Import recursively")
                    Toggle("Overwrite existing files", isOn: $viewModel.importOptions.overwriteExisting)
                        .accessibilityLabel("Overwrite existing")
                    Toggle("Organize by patient/study/series", isOn: $viewModel.importOptions.organizeByPatient)
                        .accessibilityLabel("Organize by patient")
                    Toggle("Create DICOMDIR", isOn: $viewModel.importOptions.createDICOMDIR)
                        .accessibilityLabel("Create DICOMDIR")
                }

                Button("Build Import Command") {
                    viewModel.runImport()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Build import command")

                if !viewModel.importResult.isEmpty {
                    GroupBox("Command") {
                        Text(viewModel.importResult)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Export

    private var exportContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Export from Archive")
                    .font(.title2).bold()

                GroupBox("Source Archive") {
                    TextField("Archive directory", text: $viewModel.archivePath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Archive directory")
                }

                GroupBox("Destination") {
                    TextField("Output directory path", text: $viewModel.exportOptions.outputDirectory)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Output directory")
                }

                GroupBox("Options") {
                    Toggle("Create DICOMDIR in output", isOn: $viewModel.exportOptions.createDICOMDIR)
                        .accessibilityLabel("Create DICOMDIR")
                    Toggle("Flatten directory hierarchy", isOn: $viewModel.exportOptions.flattenHierarchy)
                        .accessibilityLabel("Flatten hierarchy")
                }

                Button("Build Export Command") {
                    viewModel.runExport()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Build export command")

                if !viewModel.exportResult.isEmpty {
                    GroupBox("Command") {
                        Text(viewModel.exportResult)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Search

    private var searchContent: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search Archive")
                        .font(.headline)

                    GroupBox("Query") {
                        TextField("Patient name (wildcards: * ?)", text: $viewModel.searchQuery.patientName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Patient name filter")
                        TextField("Patient ID", text: $viewModel.searchQuery.patientID)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Patient ID filter")
                        TextField("Study date (YYYYMMDD or range)", text: $viewModel.searchQuery.studyDate)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Study date filter")
                        ModalityPicker("Modality",
                                       selection: $viewModel.searchQuery.modality,
                                       includeAnyOption: true,
                                       anyOptionLabel: "Any modality")
                        TextField("Accession number", text: $viewModel.searchQuery.accessionNumber)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Accession number filter")
                    }

                    HStack {
                        Button("Search") { viewModel.runSearch() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("Run search")
                        Button("Clear") { viewModel.clearSearch() }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding()
            }
            .frame(minWidth: 260, idealWidth: 300)

            VStack(spacing: 0) {
                HStack {
                    Text("Results (\(viewModel.searchResults.count))")
                        .font(.headline)
                    Spacer()
                }
                .padding()
                Divider()

                if !viewModel.statusMessage.isEmpty && viewModel.searchResults.isEmpty {
                    ScrollView {
                        Text(viewModel.statusMessage)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if viewModel.searchResults.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("Run a search to find studies in the archive.")
                    )
                } else {
                    List(viewModel.searchResults) { study in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(study.studyDescription.isEmpty ? "(No description)" : study.studyDescription)
                                .font(.subheadline).bold()
                            HStack {
                                Text(study.modality).font(.caption).foregroundStyle(.secondary)
                                Text(study.studyDate).font(.caption).foregroundStyle(.secondary)
                                if !study.accessionNumber.isEmpty {
                                    Text("ACC: \(study.accessionNumber)").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            Text("\(study.seriesCount) series · \(study.instanceCount) instances · \(study.formattedSize)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - Statistics

    private var statisticsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Archive Statistics")
                        .font(.title2).bold()
                    Spacer()
                    Button("Refresh") { viewModel.refreshStatistics() }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Refresh archive statistics")
                }

                GroupBox("Counts") {
                    LabeledContent("Patients")  { Text("\(viewModel.statistics.patientCount)") }
                    LabeledContent("Studies")   { Text("\(viewModel.statistics.studyCount)") }
                    LabeledContent("Series")    { Text("\(viewModel.statistics.seriesCount)") }
                    LabeledContent("Instances") { Text("\(viewModel.statistics.instanceCount)") }
                }

                GroupBox("Storage") {
                    LabeledContent("Total Size") { Text(viewModel.statistics.formattedSize) }
                    LabeledContent("Index Version") { Text(viewModel.statistics.indexVersion) }
                    if let modified = viewModel.statistics.lastModified {
                        LabeledContent("Last Modified") {
                            Text(modified, style: .relative)
                        }
                    }
                }

                if !viewModel.statusMessage.isEmpty {
                    GroupBox("Command") {
                        Text(viewModel.statusMessage)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
    }
}
#endif
