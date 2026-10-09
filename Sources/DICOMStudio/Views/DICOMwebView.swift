// DICOMwebView.swift
// DICOMStudio
// NEMA-verified: 2026a, checked 2026-10-05 — JPIP header lists the 4 JPIP transfer syntaxes of PS3.6 2026a Table A-1 (1.2.840.10008.1.2.4.94 / .95 / .204 / .205) and the uri panel names Pixel Data Provider URL (0028,7FE0) per PS3.6 Table 6-1 and PS3.5 A.6 (was "(0008,1190) RETRIEVE URL"); UPS state strings SCHEDULED / IN PROGRESS / COMPLETED / CANCELED match PS3.3 2026a C.30.1; the dicom-jpip command strings are tool options (ISO/IEC 15444-9), out of scope; everything else is layout
//
// DICOM Studio — DICOMweb Integration Hub view for WADO-RS, QIDO-RS, STOW-RS,
// UPS-RS operations, server configuration, and performance monitoring.
// Reference: DICOM PS3.18 (Web Services)

#if canImport(SwiftUI)
import SwiftUI

/// DICOMweb Integration Hub view providing tabbed access to all DICOMweb services:
/// Server Configuration, QIDO-RS queries, WADO-RS retrieval, STOW-RS uploads,
/// UPS-RS workitem management, and a Performance Dashboard.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct DICOMwebView: View {
    @Bindable var viewModel: DICOMwebViewModel

    public init(viewModel: DICOMwebViewModel) {
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
                ProgressView("Loading…")
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
        .sheet(isPresented: $viewModel.isAddServerSheetPresented) {
            DICOMwebServerFormSheet(mode: .add) { profile in
                viewModel.addServerProfile(profile)
            }
        }
        .sheet(isPresented: $viewModel.isEditServerSheetPresented) {
            if let profile = viewModel.selectedServerProfile {
                DICOMwebServerFormSheet(mode: .edit(profile)) { updated in
                    viewModel.updateServerProfile(updated)
                }
            }
        }
        .sheet(isPresented: $viewModel.isWADOJobSheetPresented) {
            wadoNewJobSheet
        }
        .sheet(isPresented: $viewModel.isSTOWUploadSheetPresented) {
            stowNewUploadSheet
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(DICOMwebTab.allCases, id: \.self) { tab in
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

    // MARK: - Tab Content Router

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.activeTab {
        case .serverConfig:
            serverConfigContent
        case .qidoRS:
            qidoContent
        case .wadoRS:
            wadoContent
        case .stowRS:
            stowContent
        case .upsRS:
            upsContent
        case .jpipStreaming:
            jpipContent
        case .performanceDashboard:
            performanceDashboardContent
        }
    }

    // MARK: - 1. Server Configuration

    private var serverConfigContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DICOMweb Server Profiles")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.isAddServerSheetPresented = true
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
                .accessibilityLabel("Add new DICOMweb server profile")
            }
            .padding()

            if viewModel.serverProfiles.isEmpty {
                ContentUnavailableView(
                    "No Server Profiles",
                    systemImage: "server.rack",
                    description: Text("Add a DICOMweb server to start using QIDO-RS, WADO-RS, and STOW-RS services.")
                )
            } else {
                List(viewModel.serverProfiles, id: \.id, selection: $viewModel.selectedServerProfileID) { profile in
                    serverProfileRow(profile)
                        .contextMenu {
                            serverProfileContextMenu(profile)
                        }
                }
            }
        }
    }

    private func serverProfileRow(_ profile: DICOMwebServerProfile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: profile.connectionStatus.sfSymbol)
                .foregroundStyle(connectionStatusColor(profile.connectionStatus))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(profile.name.isEmpty ? "Unnamed Server" : profile.name)
                        .font(.body)
                        .fontWeight(profile.isDefault ? .semibold : .regular)
                    if profile.isDefault {
                        Text("DEFAULT")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(DICOMwebURLHelpers.displayHost(for: profile.baseURL))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Text(profile.authMethod.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if profile.tlsMode.isEnabled {
                        Image(systemName: DICOMwebTLSHelpers.sfSymbol(for: profile.tlsMode))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel(profile.tlsMode.displayName)
                    }
                    if !profile.supportedServices.isEmpty {
                        Text(profile.supportedServices.map(\.abbreviation).sorted().joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let error = profile.lastConnectionError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Text(profile.connectionStatus.displayName)
                .font(.caption)
                .foregroundStyle(connectionStatusColor(profile.connectionStatus))
        }
        .padding(.vertical, 4)
        .accessibilityLabel("Server \(profile.name)")
        .accessibilityValue("\(profile.connectionStatus.displayName), \(DICOMwebURLHelpers.displayHost(for: profile.baseURL))")
    }

    @ViewBuilder
    private func serverProfileContextMenu(_ profile: DICOMwebServerProfile) -> some View {
        Button {
            viewModel.selectedServerProfileID = profile.id
            viewModel.isEditServerSheetPresented = true
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button {
            Task { await viewModel.testConnection(profileID: profile.id) }
        } label: {
            Label("Test Connection", systemImage: "network")
        }
        if !profile.isDefault {
            Button {
                viewModel.setDefaultProfile(id: profile.id)
            } label: {
                Label("Set as Default", systemImage: "star")
            }
        }
        Divider()
        Button(role: .destructive) {
            viewModel.removeServerProfile(id: profile.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - 2. QIDO-RS

    private var qidoContent: some View {
        VStack(spacing: 0) {
            qidoQueryForm
            Divider()
            qidoResultsList
        }
    }

    private var qidoQueryForm: some View {
        VStack(spacing: 0) {
            HStack {
                Text("QIDO-RS Query")
                    .font(.headline)
                Spacer()
                Picker("Level", selection: $viewModel.qidoQueryLevel) {
                    ForEach(QIDOQueryLevel.allCases, id: \.self) { level in
                        Label(level.displayName, systemImage: level.sfSymbol)
                            .tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .accessibilityLabel("Query level")
            }
            .padding(.horizontal)
            .padding(.top)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Patient Name:")
                        .frame(width: 120, alignment: .trailing)
                    TextField("e.g. DOE^JOHN or DOE*", text: $viewModel.qidoQueryParams.patientName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Patient name filter")
                    Text("Patient ID:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("e.g. 12345", text: $viewModel.qidoQueryParams.patientID)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Patient ID filter")
                }
                GridRow {
                    Text("Study Date From:")
                        .frame(width: 120, alignment: .trailing)
                    TextField("YYYYMMDD", text: $viewModel.qidoQueryParams.studyDateFrom)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Study date range start")
                    Text("To:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("YYYYMMDD", text: $viewModel.qidoQueryParams.studyDateTo)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Study date range end")
                }
                GridRow {
                    Text("Modality:")
                        .frame(width: 120, alignment: .trailing)
                    TextField("e.g. CT, MR, US", text: $viewModel.qidoQueryParams.modality)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Modality filter")
                    Text("Accession:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("Accession number", text: $viewModel.qidoQueryParams.accessionNumber)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Accession number filter")
                }
                GridRow {
                    Text("Description:")
                        .frame(width: 120, alignment: .trailing)
                    TextField("Study description", text: $viewModel.qidoQueryParams.studyDescription)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Study description filter")
                    Text("Limit:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("Max results", value: $viewModel.qidoQueryParams.limit, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 100)
                        .accessibilityLabel("Maximum results")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            HStack {
                Toggle("Fuzzy matching", isOn: $viewModel.qidoQueryParams.fuzzyMatching)
                    .accessibilityLabel("Enable fuzzy matching")
                Spacer()
                Text(viewModel.qidoQuerySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()

                qidoTemplateMenu

                Button("Clear") {
                    viewModel.clearQIDOResults()
                    viewModel.qidoQueryParams = QIDOQueryParams()
                }
                .accessibilityLabel("Clear query and results")

                Button {
                    Task { await viewModel.runQIDOQuery() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isQIDORunning)
                .accessibilityLabel("Run QIDO-RS search")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private var qidoTemplateMenu: some View {
        Menu {
            Section("Save Current Query") {
                Button {
                    let name = "Query \(viewModel.savedQueryTemplates.count + 1)"
                    viewModel.saveQueryTemplate(name: name)
                } label: {
                    Label("Save as Template", systemImage: "square.and.arrow.down")
                }
            }
            if !viewModel.savedQueryTemplates.isEmpty {
                Section("Saved Templates") {
                    ForEach(viewModel.savedQueryTemplates.keys.sorted(), id: \.self) { name in
                        Button(name) {
                            viewModel.loadQueryTemplate(name: name)
                        }
                    }
                }
                Section {
                    ForEach(viewModel.savedQueryTemplates.keys.sorted(), id: \.self) { name in
                        Button(role: .destructive) {
                            viewModel.removeQueryTemplate(name: name)
                        } label: {
                            Label("Delete \"\(name)\"", systemImage: "trash")
                        }
                    }
                }
            }
        } label: {
            Label("Templates", systemImage: "bookmark")
        }
        .accessibilityLabel("Query templates")
    }

    private var qidoResultsList: some View {
        Group {
            if viewModel.isQIDORunning {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.qidoResults.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Enter search criteria and run a QIDO-RS query to find studies, series, or instances.")
                )
            } else {
                VStack(spacing: 0) {
                    if let total = viewModel.qidoTotalResultCount {
                        HStack {
                            Text(DICOMwebQIDOHelpers.paginationDescription(
                                offset: viewModel.qidoQueryParams.offset,
                                limit: viewModel.qidoQueryParams.limit,
                                total: total
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }

                    List(viewModel.qidoResults, id: \.id, selection: $viewModel.qidoSelectedResultID) { result in
                        qidoResultRow(result)
                    }
                }
            }
        }
    }

    private func qidoResultRow(_ result: QIDOResultItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.queryLevel.sfSymbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(DICOMwebQIDOHelpers.formatPatientName(result.patientName))
                    .font(.body)
                HStack(spacing: 8) {
                    if !result.patientID.isEmpty {
                        Text("ID: \(result.patientID)")
                    }
                    if !result.studyDate.isEmpty {
                        Text(result.studyDate)
                    }
                    if !result.modality.isEmpty {
                        Text(result.modality)
                            .fontWeight(.medium)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !result.studyDescription.isEmpty {
                    Text(result.studyDescription)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let series = result.numberOfSeries {
                    Text("\(series) series")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let instances = result.numberOfInstances {
                    Text("\(instances) inst.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel("Result: \(DICOMwebQIDOHelpers.formatPatientName(result.patientName))")
        .accessibilityValue("\(result.modality) \(result.studyDate)")
        .contextMenu {
            if !result.studyInstanceUID.isEmpty {
                Button {
                    viewModel.wadoNewJobStudyUID = result.studyInstanceUID
                    viewModel.wadoNewJobSeriesUID = result.seriesInstanceUID ?? ""
                    viewModel.wadoNewJobInstanceUID = result.sopInstanceUID ?? ""
                    viewModel.wadoNewJobMode = result.seriesInstanceUID != nil ? .series : .study
                    viewModel.activeTab = .wadoRS
                    viewModel.isWADOJobSheetPresented = true
                } label: {
                    Label("Retrieve with WADO-RS", systemImage: "arrow.down.circle")
                }
            }
        }
    }

    // MARK: - 3. WADO-RS

    private var wadoContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("WADO-RS Retrieve Jobs")
                    .font(.headline)
                Spacer()
                if viewModel.activeWADOJobCount > 0 {
                    Text("\(viewModel.activeWADOJobCount) active")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Clear Completed") {
                    viewModel.clearCompletedWADOJobs()
                }
                .disabled(wadoCompletedCount == 0)
                .accessibilityLabel("Clear completed retrieve jobs")

                Button {
                    viewModel.isWADOJobSheetPresented = true
                } label: {
                    Label("New Retrieve", systemImage: "plus")
                }
                .accessibilityLabel("Create new WADO-RS retrieve job")
            }
            .padding()

            if viewModel.wadoJobs.isEmpty {
                ContentUnavailableView(
                    "No Retrieve Jobs",
                    systemImage: "arrow.down.circle",
                    description: Text("Create a WADO-RS retrieve job to download studies, series, or instances from a DICOMweb server.")
                )
            } else {
                List(viewModel.wadoJobs, id: \.id, selection: $viewModel.wadoSelectedJobID) { job in
                    wadoJobRow(job)
                        .contextMenu {
                            if !job.status.isTerminal {
                                Button(role: .destructive) {
                                    viewModel.removeWADOJob(id: job.id)
                                } label: {
                                    Label("Cancel", systemImage: "xmark.circle")
                                }
                            }
                            Button(role: .destructive) {
                                viewModel.removeWADOJob(id: job.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func wadoJobRow(_ job: WADORetrieveJob) -> some View {
        HStack(spacing: 10) {
            Image(systemName: DICOMwebWADOHelpers.sfSymbol(for: job.status))
                .foregroundStyle(wadoStatusColor(job.status))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(job.retrieveMode.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    Image(systemName: job.retrieveMode.sfSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(job.studyInstanceUID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let seriesUID = job.seriesInstanceUID {
                    Text("Series: \(seriesUID)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if job.status == .inProgress {
                    HStack(spacing: 6) {
                        if let progress = job.progressFraction {
                            ProgressView(value: progress)
                                .frame(maxWidth: 120)
                        }
                        Text(DICOMwebWADOHelpers.progressDescription(job: job))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = job.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(job.status.displayName)
                    .font(.caption)
                    .foregroundStyle(wadoStatusColor(job.status))
                Text(DICOMwebWADOHelpers.formattedBytesReceived(job.bytesReceived))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(DICOMwebWADOHelpers.formattedTransferRate(job.transferRateBytesPerSec))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("WADO retrieve: \(job.retrieveMode.displayName)")
        .accessibilityValue("\(job.status.displayName), \(DICOMwebWADOHelpers.formattedBytesReceived(job.bytesReceived))")
    }

    private var wadoNewJobSheet: some View {
        VStack(spacing: 16) {
            Text("New WADO-RS Retrieve Job")
                .font(.headline)

            Form {
                Picker("Retrieve Mode", selection: $viewModel.wadoNewJobMode) {
                    ForEach(WADORetrieveMode.allCases, id: \.self) { mode in
                        Label(mode.displayName, systemImage: mode.sfSymbol)
                            .tag(mode)
                    }
                }
                .accessibilityLabel("Retrieve mode")

                TextField("Study Instance UID *", text: $viewModel.wadoNewJobStudyUID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Study Instance UID, required")

                TextField("Series Instance UID", text: $viewModel.wadoNewJobSeriesUID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Series Instance UID, optional")

                TextField("SOP Instance UID", text: $viewModel.wadoNewJobInstanceUID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("SOP Instance UID, optional")
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    viewModel.isWADOJobSheetPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel retrieve job creation")

                Spacer()

                Button("Retrieve") {
                    Task { await viewModel.enqueueWADOJob() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.wadoNewJobStudyUID.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Start WADO-RS retrieve")
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }

    // MARK: - 4. STOW-RS

    private var stowContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("STOW-RS Upload Jobs")
                    .font(.headline)
                Spacer()
                if viewModel.activeSTOWJobCount > 0 {
                    Text("\(viewModel.activeSTOWJobCount) active")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Clear Completed") {
                    viewModel.clearCompletedSTOWJobs()
                }
                .disabled(stowCompletedCount == 0)
                .accessibilityLabel("Clear completed upload jobs")

                Button {
                    viewModel.isSTOWUploadSheetPresented = true
                } label: {
                    Label("New Upload", systemImage: "plus")
                }
                .accessibilityLabel("Create new STOW-RS upload job")
            }
            .padding()

            if viewModel.stowJobs.isEmpty {
                ContentUnavailableView(
                    "No Upload Jobs",
                    systemImage: "arrow.up.circle",
                    description: Text("Create a STOW-RS upload job to store DICOM instances on a DICOMweb server.")
                )
            } else {
                List(viewModel.stowJobs, id: \.id, selection: $viewModel.stowSelectedJobID) { job in
                    stowJobRow(job)
                        .contextMenu {
                            if !job.status.isTerminal {
                                Button(role: .destructive) {
                                    viewModel.removeSTOWJob(id: job.id)
                                } label: {
                                    Label("Cancel", systemImage: "xmark.circle")
                                }
                            }
                            Button(role: .destructive) {
                                viewModel.removeSTOWJob(id: job.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func stowJobRow(_ job: STOWUploadJob) -> some View {
        HStack(spacing: 10) {
            Image(systemName: DICOMwebSTOWHelpers.sfSymbol(for: job.status))
                .foregroundStyle(stowStatusColor(job.status))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(job.totalFiles) file\(job.totalFiles == 1 ? "" : "s")")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("— \(DICOMwebSTOWHelpers.formattedTotalSize(job.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Text(job.duplicateHandling.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if job.validationEnabled {
                        Image(systemName: "checkmark.shield")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Validation enabled")
                    }
                }

                if job.status == .uploading || job.status == .validating {
                    HStack(spacing: 6) {
                        ProgressView(value: job.progressFraction)
                            .frame(maxWidth: 120)
                        Text(DICOMwebSTOWHelpers.progressDescription(job: job))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if job.failedFiles > 0 {
                    Text("\(job.failedFiles) file\(job.failedFiles == 1 ? "" : "s") failed")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                if let error = job.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(job.status.displayName)
                    .font(.caption)
                    .foregroundStyle(stowStatusColor(job.status))
                Text("\(job.uploadedFiles)/\(job.totalFiles)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("STOW upload: \(job.totalFiles) files")
        .accessibilityValue("\(job.status.displayName), \(job.uploadedFiles) of \(job.totalFiles) uploaded")
    }

    private var stowNewUploadSheet: some View {
        VStack(spacing: 16) {
            Text("New STOW-RS Upload Job")
                .font(.headline)

            Form {
                Section("Files") {
                    if viewModel.stowNewFilePaths.isEmpty {
                        Text("No files selected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.stowNewFilePaths, id: \.self) { path in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.secondary)
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    viewModel.stowNewFilePaths.removeAll { $0 == path }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove file \(URL(fileURLWithPath: path).lastPathComponent)")
                            }
                        }
                    }

                    Button {
                        addFilesViaOpenPanel()
                    } label: {
                        Label("Add Files…", systemImage: "doc.badge.plus")
                    }
                    .accessibilityLabel("Add DICOM files to upload")
                }

                Section("Options") {
                    Picker("Duplicate Handling", selection: $viewModel.stowDuplicateHandling) {
                        ForEach(STOWDuplicateHandling.allCases, id: \.self) { handling in
                            Text(handling.displayName).tag(handling)
                        }
                    }
                    .accessibilityLabel("Duplicate instance handling policy")

                    Toggle("Validate before upload", isOn: $viewModel.stowValidationEnabled)
                        .accessibilityLabel("Enable DICOM validation before uploading")

                    Stepper("Concurrency: \(viewModel.stowPipelineConcurrency)",
                            value: $viewModel.stowPipelineConcurrency, in: 1...20)
                    .accessibilityLabel("Pipeline concurrency, currently \(viewModel.stowPipelineConcurrency)")
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    viewModel.stowNewFilePaths = []
                    viewModel.isSTOWUploadSheetPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel upload job creation")

                Spacer()

                Button("Upload") {
                    Task { await viewModel.enqueueSTOWUpload() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.stowNewFilePaths.isEmpty)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Start STOW-RS upload")
            }
        }
        .padding()
        .frame(minWidth: 450, minHeight: 400)
    }

    // MARK: - 5. UPS-RS

    private var upsContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("UPS-RS Workitems")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await viewModel.loadUPSWorkitems() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isUPSQueryRunning)
                .accessibilityLabel("Refresh UPS workitems")
            }
            .padding()

            if viewModel.upsWorkitems.isEmpty {
                ContentUnavailableView(
                    "No Workitems",
                    systemImage: "list.bullet.clipboard",
                    description: Text("No UPS-RS workitems found. Use Refresh to query the server.")
                )
            } else {
                List(viewModel.upsWorkitems, id: \.id, selection: $viewModel.upsSelectedWorkitemID) { workitem in
                    upsWorkitemRow(workitem)
                }
            }

            Divider()
            upsEventMonitorSection
            Divider()
            upsSubscriptionsSection
        }
        .sheet(isPresented: $viewModel.isUPSSubscriptionSheetPresented) {
            upsSubscriptionSheet
        }
    }

    private func upsWorkitemRow(_ workitem: UPSWorkitem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: DICOMwebUPSHelpers.sfSymbol(for: workitem.state))
                .font(.title3)
                .foregroundStyle(upsStateColor(workitem.state))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(workitem.procedureStepLabel.isEmpty ? "Untitled Workitem" : workitem.procedureStepLabel)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    if !workitem.patientName.isEmpty {
                        Text(DICOMwebQIDOHelpers.formatPatientName(workitem.patientName))
                    }
                    if !workitem.patientID.isEmpty {
                        Text("ID: \(workitem.patientID)")
                    }
                    Image(systemName: workitem.priority.sfSymbol)
                        .foregroundStyle(upsPriorityColor(workitem.priority))
                        .accessibilityLabel("\(workitem.priority.displayName) priority")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if workitem.state == .inProgress && workitem.completionPercentage > 0 {
                    HStack(spacing: 6) {
                        ProgressView(value: Double(workitem.completionPercentage), total: 100)
                            .frame(maxWidth: 140)
                        Text("\(workitem.completionPercentage)%")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !workitem.progressInformation.isEmpty {
                    Text(workitem.progressInformation)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(workitem.state.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(upsStateColor(workitem.state))
                if let scheduledDate = workitem.scheduledDateTime {
                    Text(scheduledDate, style: .date)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("Workitem: \(workitem.procedureStepLabel)")
        .accessibilityValue("\(workitem.state.displayName), \(workitem.priority.displayName) priority")
        .contextMenu {
            ForEach(DICOMwebUPSHelpers.availableTransitions(from: workitem.state), id: \.self) { targetState in
                Button {
                    viewModel.transitionUPSState(targetState, workitemID: workitem.id)
                } label: {
                    Label("Transition to \(targetState.displayName)", systemImage: DICOMwebUPSHelpers.sfSymbol(for: targetState))
                }
            }
        }
    }

    private var upsSubscriptionsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Event Subscriptions")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.isUPSSubscriptionSheetPresented = true
                } label: {
                    Label("Subscribe", systemImage: "bell.badge.fill")
                        .font(.subheadline)
                }
                .accessibilityLabel("Create new UPS event subscription")
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            if viewModel.upsSubscriptions.isEmpty {
                Text("No active subscriptions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.upsSubscriptions, id: \.id) { sub in
                            HStack {
                                Image(systemName: sub.isActive ? "bell.fill" : "bell.slash")
                                    .foregroundStyle(sub.isActive ? .green : .secondary)
                                    .accessibilityHidden(true)
                                Text(sub.isGlobal ? "Global" : "UID: \(sub.workitemUID ?? "")")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Text(sub.eventTypes.map(\.displayName).sorted().joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Button {
                                    viewModel.removeUPSSubscription(id: sub.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove subscription")
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: .infinity)
            }
        }
    }

    // MARK: - 5.1 UPS Event Monitor

    private var upsEventMonitorSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Event Monitor")
                    .font(.headline)

                Spacer()

                // Connection status indicator
                HStack(spacing: 5) {
                    Image(systemName: DICOMwebUPSHelpers.eventChannelSFSymbol(for: viewModel.upsEventChannelState))
                        .foregroundStyle(upsEventChannelColor(viewModel.upsEventChannelState))
                        .accessibilityHidden(true)
                    Text(viewModel.upsEventChannelState.displayName)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(upsEventChannelColor(viewModel.upsEventChannelState))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(upsEventChannelColor(viewModel.upsEventChannelState).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .accessibilityLabel("Event channel status: \(viewModel.upsEventChannelState.displayName)")

                // START / STOP toggle
                Button {
                    if viewModel.isUPSEventMonitoringActive {
                        viewModel.stopEventMonitoring()
                    } else {
                        viewModel.startEventMonitoring()
                    }
                } label: {
                    Label(
                        DICOMwebUPSHelpers.monitorToggleLabel(isActive: viewModel.isUPSEventMonitoringActive),
                        systemImage: DICOMwebUPSHelpers.monitorToggleSFSymbol(isActive: viewModel.isUPSEventMonitoringActive)
                    )
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(viewModel.isUPSEventMonitoringActive ? .red : .green)
                .accessibilityLabel(
                    viewModel.isUPSEventMonitoringActive
                        ? "Stop UPS event monitoring"
                        : "Start UPS event monitoring"
                )
                .accessibilityHint(
                    viewModel.isUPSEventMonitoringActive
                        ? "Stops listening for UPS event notifications from the server"
                        : "Opens a WebSocket channel to receive UPS event notifications"
                )
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            // Received events log
            if viewModel.upsReceivedEvents.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "bell.slash")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(viewModel.isUPSEventMonitoringActive
                             ? "Waiting for events…"
                             : "Press Start to open the event channel")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                HStack {
                    Text("\(viewModel.upsReceivedEvents.count) event(s)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewModel.clearReceivedEvents()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear received events log")
                }
                .padding(.horizontal)
                .padding(.top, 4)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.upsReceivedEvents, id: \.id) { event in
                            upsReceivedEventRow(event)
                        }
                    }
                }
                .frame(minHeight: 320, maxHeight: .infinity)
            }
        }
    }

    private func upsReceivedEventRow(_ event: UPSReceivedEvent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: DICOMwebUPSHelpers.eventTypeSFSymbol(for: event.eventType))
                    .font(.callout)
                    .foregroundStyle(upsEventTypeColor(event.eventType))
                    .frame(width: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(event.eventType.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        // Show short workitem identifier if context is loaded
                        if let shortID = UPSEventDetailHelpers.workitemShortIdentifier(event) {
                            Text(shortID)
                                .font(.footnote)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        Text(event.workitemUID.isEmpty ? "—" : event.workitemUID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if !event.summary.isEmpty {
                        Text(event.summary)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Loading indicator while fetching workitem context
                if !event.isWorkitemContextLoaded && !event.workitemUID.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading workitem details")
                }

                Text(DICOMwebUPSHelpers.relativeTimeString(from: event.receivedAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Received \(DICOMwebUPSHelpers.relativeTimeString(from: event.receivedAt))")
            }

            // Workitem context details row
            if let contextDesc = UPSEventDetailHelpers.workitemContextDescription(event) {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(upsEventTypeColor(event.eventType).opacity(0.3))
                        .frame(width: 2)
                        .padding(.leading, 9)
                        .accessibilityHidden(true)

                    Text(contextDesc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.leading, 15)
                }
                .padding(.top, 3)
                .accessibilityLabel("Workitem details: \(contextDesc)")
            }

            // Event-specific detail chips (state transition, progress bar)
            if event.eventType == .stateChange, let newState = event.newState {
                HStack(spacing: 5) {
                    Spacer().frame(width: 28)
                    if let prev = event.previousState {
                        Text(prev)
                            .font(.caption2.monospaced())
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(newState)
                        .font(.caption2.monospaced())
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(upsStateChipColor(newState).opacity(0.15))
                        .foregroundStyle(upsStateChipColor(newState))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(.top, 3)
                .accessibilityLabel("State transition\(event.previousState.map { " from \($0)" } ?? "") to \(newState)")
            }

            if event.eventType == .progressChange, let pct = event.progressPercentage {
                HStack(spacing: 6) {
                    Spacer().frame(width: 28)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.green)
                                .frame(width: max(0, geo.size.width * CGFloat(pct) / 100.0))
                        }
                    }
                    .frame(height: 6)
                    .frame(maxWidth: 140)
                    Text("\(pct)%")
                        .font(.caption2.monospaced())
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 3)
                .accessibilityLabel("Progress: \(pct) percent")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(upsEventAccessibilityLabel(event))
        .accessibilityValue(event.summary.isEmpty ? "" : event.summary)
    }

    /// Builds a comprehensive accessibility label for a received event row.
    private func upsEventAccessibilityLabel(_ event: UPSReceivedEvent) -> String {
        var parts = ["\(event.eventType.displayName) event"]
        if let shortID = UPSEventDetailHelpers.workitemShortIdentifier(event) {
            parts.append("for \(shortID)")
        }
        parts.append("workitem \(event.workitemUID.isEmpty ? "unknown" : event.workitemUID)")
        if let context = UPSEventDetailHelpers.workitemContextDescription(event) {
            parts.append(context)
        }
        return parts.joined(separator: ", ")
    }

    /// Returns a SwiftUI color for a UPS state string used in chip badges.
    private func upsStateChipColor(_ state: String) -> Color {
        switch state {
        case "SCHEDULED":   return .blue
        case "IN PROGRESS": return .orange
        case "COMPLETED":   return .green
        case "CANCELED":    return .red
        default:            return .secondary
        }
    }

    // MARK: - 5.2 UPS Subscription Sheet

    private var upsSubscriptionSheet: some View {
        VStack(spacing: 16) {
            Text("New UPS Event Subscription")
                .font(.headline)

            Form {
                Section("Scope") {
                    TextField("Workitem UID (empty = global)", text: $viewModel.upsNewSubscriptionWorkitemUID)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Workitem UID for subscription scope")
                        .accessibilityHint("Leave empty to subscribe to all workitems globally")
                    if viewModel.upsNewSubscriptionWorkitemUID.isEmpty {
                        Label("Global subscription — all workitems", systemImage: "globe")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Event Types") {
                    ForEach(UPSEventType.allCases, id: \.self) { eventType in
                        Toggle(isOn: Binding(
                            get: { viewModel.upsSubscribeEventTypes.contains(eventType) },
                            set: { include in
                                if include {
                                    viewModel.upsSubscribeEventTypes.insert(eventType)
                                } else {
                                    viewModel.upsSubscribeEventTypes.remove(eventType)
                                }
                            }
                        )) {
                            Label(eventType.displayName, systemImage: DICOMwebUPSHelpers.eventTypeSFSymbol(for: eventType))
                        }
                        .accessibilityLabel("Subscribe to \(eventType.displayName) events")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    viewModel.isUPSSubscriptionSheetPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel subscription")

                Spacer()

                Button("Subscribe") {
                    viewModel.addUPSSubscription()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.upsSubscribeEventTypes.isEmpty)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Create UPS event subscription")
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 350)
    }

    // MARK: - 6. Performance Dashboard

    // MARK: - JPIP Streaming

    private var jpipContent: some View {
        JPIPContentView()
    }

    // MARK: - Performance Dashboard

    private var performanceDashboardContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Performance Dashboard")
                    .font(.headline)
                Spacer()
                Text(viewModel.performanceHealthDescription)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(performanceHealthColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(performanceHealthColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Button {
                    viewModel.refreshPerformanceStats()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh performance stats")

                Button("Reset") {
                    viewModel.resetPerformanceStats()
                }
                .accessibilityLabel("Reset all performance stats")
            }
            .padding()

            ScrollView {
                LazyVStack(spacing: 16) {
                    performanceHTTPSection
                    performanceLatencySection
                    performanceCacheSection
                    performancePrefetchSection
                    performanceRequestSection
                }
                .padding()
            }
        }
    }

    private var performanceHTTPSection: some View {
        GroupBox("HTTP/2 Streams") {
            HStack(spacing: 20) {
                performanceStatItem(
                    label: "Active Streams",
                    value: DICOMwebPerformanceHelpers.http2StreamsDescription(
                        active: viewModel.performanceStats.http2StreamsActive,
                        max: viewModel.performanceStats.http2MaxStreams
                    ),
                    icon: "arrow.up.arrow.down"
                )
                performanceStatItem(
                    label: "Pipeline Rate",
                    value: String(format: "%.1f req/s", viewModel.performanceStats.pipelinedRequestsPerSec),
                    icon: "chart.line.uptrend.xyaxis"
                )
                performanceStatItem(
                    label: "Pool Utilization",
                    value: DICOMwebPerformanceHelpers.formattedConnectionPoolUtilization(
                        viewModel.performanceStats.connectionPoolUtilization
                    ),
                    icon: "cpu"
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("HTTP/2 streams performance")
    }

    private var performanceLatencySection: some View {
        GroupBox("Latency & Compression") {
            HStack(spacing: 20) {
                performanceStatItem(
                    label: "Average Latency",
                    value: DICOMwebPerformanceHelpers.formattedLatency(viewModel.performanceStats.averageLatencyMs),
                    icon: "clock"
                )
                performanceStatItem(
                    label: "Peak Latency",
                    value: DICOMwebPerformanceHelpers.formattedLatency(viewModel.performanceStats.peakLatencyMs),
                    icon: "clock.badge.exclamationmark"
                )
                performanceStatItem(
                    label: "Compression",
                    value: DICOMwebPerformanceHelpers.formattedCompressionRatio(viewModel.performanceStats.compressionRatio),
                    icon: "arrow.down.right.and.arrow.up.left"
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latency and compression performance")
    }

    private var performanceCacheSection: some View {
        GroupBox("Response Cache") {
            HStack(spacing: 20) {
                performanceStatItem(
                    label: "Hit Rate",
                    value: DICOMwebPerformanceHelpers.formattedHitRate(viewModel.performanceStats.cacheStats.hitRate),
                    icon: "checkmark.circle"
                )
                performanceStatItem(
                    label: "Hits / Misses",
                    value: "\(viewModel.performanceStats.cacheStats.hitCount) / \(viewModel.performanceStats.cacheStats.missCount)",
                    icon: "arrow.left.arrow.right"
                )
                performanceStatItem(
                    label: "Cache Size",
                    value: DICOMwebWADOHelpers.formattedBytesReceived(viewModel.performanceStats.cacheStats.currentSizeBytes),
                    icon: "internaldrive"
                )
                performanceStatItem(
                    label: "Evictions",
                    value: "\(viewModel.performanceStats.cacheStats.evictionCount)",
                    icon: "trash"
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Response cache performance")
    }

    private var performancePrefetchSection: some View {
        GroupBox("Prefetch") {
            HStack(spacing: 20) {
                performanceStatItem(
                    label: "Effectiveness",
                    value: DICOMwebPerformanceHelpers.prefetchEffectivenessDescription(
                        hitCount: viewModel.performanceStats.prefetchHitCount,
                        missCount: viewModel.performanceStats.prefetchMissCount
                    ),
                    icon: "bolt.circle"
                )
                performanceStatItem(
                    label: "Prefetch Hit Rate",
                    value: DICOMwebPerformanceHelpers.formattedHitRate(viewModel.performanceStats.prefetchHitRate),
                    icon: "target"
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prefetch performance")
    }

    private var performanceRequestSection: some View {
        GroupBox("Requests") {
            HStack(spacing: 20) {
                performanceStatItem(
                    label: "Total Requests",
                    value: "\(viewModel.performanceStats.totalRequestCount)",
                    icon: "number"
                )
                performanceStatItem(
                    label: "Errors",
                    value: "\(viewModel.performanceStats.errorCount)",
                    icon: "exclamationmark.triangle"
                )
                performanceStatItem(
                    label: "Error Rate",
                    value: DICOMwebPerformanceHelpers.formattedHitRate(viewModel.performanceStats.errorRate),
                    icon: "chart.bar.xaxis"
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Request statistics")
    }

    private func performanceStatItem(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Color Helpers

    private func connectionStatusColor(_ status: DICOMwebConnectionStatus) -> Color {
        switch status {
        case .unknown: return .secondary
        case .testing: return .blue
        case .online:  return .green
        case .offline: return .orange
        case .error:   return .red
        }
    }

    private func wadoStatusColor(_ status: WADORetrieveStatus) -> Color {
        switch status {
        case .queued:     return .secondary
        case .inProgress: return .blue
        case .completed:  return .green
        case .failed:     return .red
        case .cancelled:  return .orange
        }
    }

    private func stowStatusColor(_ status: STOWUploadStatus) -> Color {
        switch status {
        case .queued:     return .secondary
        case .validating: return .blue
        case .uploading:  return .blue
        case .completed:  return .green
        case .rejected:   return .orange
        case .failed:     return .red
        }
    }

    private func upsStateColor(_ state: WebUPSState) -> Color {
        switch state {
        case .scheduled:  return .blue
        case .inProgress: return .orange
        case .completed:  return .green
        case .canceled:   return .red
        }
    }

    private func upsPriorityColor(_ priority: UPSPriority) -> Color {
        switch priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .secondary
        }
    }

    private func upsEventChannelColor(_ state: UPSEventChannelState) -> Color {
        switch state {
        case .disconnected:  return .secondary
        case .connecting:    return .orange
        case .connected:     return .green
        case .reconnecting:  return .orange
        case .closed:        return .red
        }
    }

    private func upsEventTypeColor(_ type: UPSEventType) -> Color {
        switch type {
        case .stateChange:           return .blue
        case .progressChange:        return .green
        case .stepStateChange:       return .orange
        case .cancellationRequested: return .red
        }
    }

    private var performanceHealthColor: Color {
        switch viewModel.performanceHealthDescription {
        case "Excellent": return .green
        case "Good":      return .blue
        case "Degraded":  return .orange
        default:          return .red
        }
    }

    // MARK: - Computed Counts

    private var wadoCompletedCount: Int {
        viewModel.wadoJobs.filter { $0.status.isTerminal }.count
    }

    private var stowCompletedCount: Int {
        viewModel.stowJobs.filter { $0.status.isTerminal }.count
    }

    // MARK: - File Open Helper

    private func addFilesViaOpenPanel() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Select DICOM Files"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data]
        if panel.runModal() == .OK {
            let paths = panel.urls.map(\.path)
            viewModel.stowNewFilePaths.append(contentsOf: paths)
        }
        #endif
    }
}

// MARK: - Server Profile Form Sheet

/// Sheet for adding or editing a DICOMweb server profile.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct DICOMwebServerFormSheet: View {
    enum Mode {
        case add
        case edit(DICOMwebServerProfile)
    }

    let mode: Mode
    let onSave: (DICOMwebServerProfile) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var authMethod: DICOMwebAuthMethod = .none
    @State private var bearerToken: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var tlsMode: DICOMwebTLSMode = .none
    @State private var supportedServices: Set<DICOMwebServiceType> = Set(DICOMwebServiceType.allCases)
    @State private var validationMessages: [String] = []

    private var existingID: UUID?

    init(mode: Mode, onSave: @escaping (DICOMwebServerProfile) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            existingID = nil
        case .edit(let profile):
            existingID = profile.id
            _name = State(initialValue: profile.name)
            _baseURL = State(initialValue: profile.baseURL)
            _authMethod = State(initialValue: profile.authMethod)
            _bearerToken = State(initialValue: profile.bearerToken)
            _username = State(initialValue: profile.username)
            _password = State(initialValue: profile.password)
            _tlsMode = State(initialValue: profile.tlsMode)
            _supportedServices = State(initialValue: profile.supportedServices)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Server Profile" : "Add Server Profile")
                .font(.headline)

            Form {
                Section("General") {
                    TextField("Server Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Server profile name")
                    TextField("Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("DICOMweb base URL")
                        .accessibilityHint("For example, https://pacs.example.com/dicom-web")
                }

                Section("Authentication") {
                    Picker("Method", selection: $authMethod) {
                        ForEach(DICOMwebAuthMethod.allCases, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .accessibilityLabel("Authentication method")

                    if DICOMwebAuthHelpers.requiresToken(authMethod) {
                        SecureField("Token", text: $bearerToken)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("\(authMethod.displayName) token")
                    }
                    if DICOMwebAuthHelpers.requiresCredentials(authMethod) {
                        TextField("Username", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Username")
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Password")
                    }
                }

                Section("Security") {
                    Picker("TLS Mode", selection: $tlsMode) {
                        ForEach(DICOMwebTLSMode.allCases, id: \.self) { mode in
                            Label(mode.displayName, systemImage: DICOMwebTLSHelpers.sfSymbol(for: mode))
                                .tag(mode)
                        }
                    }
                    .accessibilityLabel("TLS security mode")
                    Text(DICOMwebTLSHelpers.securityDescription(for: tlsMode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Supported Services") {
                    ForEach(DICOMwebServiceType.allCases, id: \.self) { serviceType in
                        Toggle(serviceType.displayName, isOn: Binding(
                            get: { supportedServices.contains(serviceType) },
                            set: { include in
                                if include {
                                    supportedServices.insert(serviceType)
                                } else {
                                    supportedServices.remove(serviceType)
                                }
                            }
                        ))
                        .accessibilityLabel("Support \(serviceType.displayName)")
                    }
                }
            }
            .formStyle(.grouped)

            if !validationMessages.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(validationMessages, id: \.self) { msg in
                        Label(msg, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel server profile form")

                Spacer()

                Button(isEditing ? "Save" : "Add") {
                    saveProfile()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(isEditing ? "Save server profile" : "Add server profile")
            }
        }
        .padding()
        .frame(minWidth: 450, minHeight: 440)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func saveProfile() {
        let profile = DICOMwebServerProfile(
            id: existingID ?? UUID(),
            name: name,
            baseURL: DICOMwebURLHelpers.normalizeURL(baseURL),
            authMethod: authMethod,
            bearerToken: bearerToken,
            username: username,
            password: password,
            tlsMode: tlsMode,
            supportedServices: supportedServices
        )

        var errors: [String] = []
        if profile.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Server name must not be empty.")
        }
        if let urlError = DICOMwebURLHelpers.validationError(for: profile.baseURL) {
            errors.append(urlError)
        }
        if let authError = DICOMwebAuthHelpers.validationError(
            for: profile.authMethod,
            token: profile.bearerToken,
            username: profile.username,
            password: profile.password
        ) {
            errors.append(authError)
        }

        if errors.isEmpty {
            onSave(profile)
            dismiss()
        } else {
            validationMessages = errors
        }
    }
}

// MARK: - JPIP Streaming View

/// Embedded view for JPIP (JPEG 2000 Interactive Protocol) streaming — dicom-jpip.
/// Reference: DICOM PS3.18 §10.4 — JPIP Referenced Transfer Syntax
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
private struct JPIPContentView: View {
    @State private var fetchServerURL: String = ""
    @State private var fetchImageID: String = ""
    @State private var fetchRegion: String = ""
    @State private var fetchLayers: String = ""
    @State private var fetchResult: String = ""
    @State private var uriFilePath: String = ""
    @State private var uriResult: String = ""
    @State private var servePort: String = "8080"
    @State private var serveDirectory: String = ""
    @State private var serveResult: String = ""
    @State private var infoServerURL: String = ""
    @State private var infoResult: String = ""
    @State private var activeOperation: JPIPOperation = .fetch

    enum JPIPOperation: String, CaseIterable, Identifiable {
        case fetch = "Fetch Image"
        case uri   = "Extract URI"
        case serve = "Serve Files"
        case info  = "Server Info"
        var id: String { rawValue }
        var sfSymbol: String {
            switch self {
            case .fetch: return "arrow.down.to.line"
            case .uri:   return "link"
            case .serve: return "server.rack"
            case .info:  return "info.circle"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("JPIP Streaming", systemImage: "arrow.down.to.line")
                    .font(.headline)
                Spacer()
                Text("Transfer Syntaxes: 1.2.840.10008.1.2.4.94 / .95 / .204 / .205")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            Divider()

            // Operation picker
            Picker("Operation", selection: $activeOperation) {
                ForEach(JPIPOperation.allCases) { op in
                    Label(op.rawValue, systemImage: op.sfSymbol).tag(op)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                switch activeOperation {
                case .fetch: fetchPanel
                case .uri:   uriPanel
                case .serve: servePanel
                case .info:  infoPanel
                }
            }
        }
    }

    // MARK: - Fetch

    private var fetchPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fetch image from a JPIP server. Only the requested region and quality layers are transferred, reducing bandwidth for large datasets.")
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox("Server") {
                TextField("JPIP server URL (e.g. http://pacs.example.com:8080)", text: $fetchServerURL)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("JPIP server URL")
                TextField("Image ID / SOP Instance UID", text: $fetchImageID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Image ID")
            }

            GroupBox("Region (optional)") {
                TextField("x,y,width,height (pixels)", text: $fetchRegion)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Region of interest")
                TextField("Quality layers (e.g. 2)", text: $fetchLayers)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Quality layers")
            }

            Button("Build Command") {
                var cmd = "dicom-jpip fetch \(fetchServerURL) --image \"\(fetchImageID)\""
                if !fetchRegion.isEmpty { cmd += " --region \(fetchRegion)" }
                if !fetchLayers.isEmpty { cmd += " --layers \(fetchLayers)" }
                fetchResult = cmd
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Build JPIP fetch command")

            if !fetchResult.isEmpty {
                GroupBox("Command") {
                    Text(fetchResult)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
    }

    // MARK: - Extract URI

    private var uriPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Extract the JPIP request URL of a JPIP-referenced DICOM file: Pixel Data Provider URL (0028,7FE0), which stands in for the Pixel Data (PS3.5 A.6).")
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox("Input") {
                TextField("DICOM file path", text: $uriFilePath)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("DICOM file path")
            }

            Button("Build Command") {
                uriResult = "dicom-jpip uri \"\(uriFilePath)\""
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Build JPIP URI command")

            if !uriResult.isEmpty {
                GroupBox("Command") {
                    Text(uriResult)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
    }

    // MARK: - Serve

    private var servePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start an embedded JPIP server serving local DICOM files.")
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox("Configuration") {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("8080", text: $servePort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .accessibilityLabel("JPIP server port")
                }
                TextField("DICOM files directory", text: $serveDirectory)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("DICOM files directory")
            }

            Button("Build Command") {
                serveResult = "dicom-jpip serve --port \(servePort) --directory \"\(serveDirectory)\""
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Build JPIP serve command")

            if !serveResult.isEmpty {
                GroupBox("Command") {
                    Text(serveResult)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
    }

    // MARK: - Server Info

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Query a JPIP server for its capabilities and statistics.")
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox("Server") {
                TextField("JPIP server URL", text: $infoServerURL)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("JPIP server URL for info")
            }

            Button("Build Command") {
                infoResult = "dicom-jpip info \(infoServerURL)"
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Build JPIP info command")

            if !infoResult.isEmpty {
                GroupBox("Command") {
                    Text(infoResult)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
    }
}
#endif
