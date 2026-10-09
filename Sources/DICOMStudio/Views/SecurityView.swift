// SecurityView.swift
// DICOMStudio
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (UI state and layout; the profile picker shows AnonymizationProfile display names and `--profile <cliFlag>`, verified in SecurityModel.swift; no PS3.15 Annex E profile name or CID 7050 code is displayed)
// NEMA-verified: 2026a, checked 2026-10-06 — the profile picker offers AnonymizationProfile.builderProfiles, PS3.15 Basic Application Level Confidentiality Profile first (default; P-STUDIO-ANON-PS315), the legacy lists labelled "not PS3.15"; the E.3 Option toggles show StudioAnonPS315.securityPanelOptions, whose 10 names are compared by script with PS3.15 2026a E.3.3–E.3.11
// DICOM Studio — Security and privacy center view

#if canImport(SwiftUI)
import SwiftUI

/// Security and privacy view providing TLS management, anonymization,
/// audit logging, and access control.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct SecurityView: View {
    @Bindable var viewModel: SecurityViewModel

    public init(viewModel: SecurityViewModel) {
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
        .sheet(isPresented: $viewModel.isAddCertificateSheetPresented) {
            AddCertificateSheet { certificate in
                viewModel.addCertificate(certificate)
            }
        }
        .sheet(isPresented: $viewModel.isNewJobSheetPresented) {
            NewAnonymizationJobSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isAuditExportSheetPresented) {
            AuditExportSheet(viewModel: viewModel)
        }
        .alert("Break-Glass Access", isPresented: $viewModel.isBreakGlassDialogPresented) {
            TextField("Reason for emergency access", text: $viewModel.breakGlassReason)
            Button("Cancel", role: .cancel) {
                viewModel.breakGlassReason = ""
            }
            Button("Confirm", role: .destructive) {
                viewModel.recordBreakGlassEvent(resource: "Emergency Access")
            }
        } message: {
            Text("Enter a reason for break-glass emergency access. This will be logged for compliance.")
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(SecurityTab.allCases, id: \.self) { tab in
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
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.activeTab {
        case .tlsConfiguration:
            tlsContent
        case .anonymization:
            anonymizationContent
        case .auditLog:
            auditLogContent
        case .accessControl:
            accessControlContent
        }
    }

    // MARK: - TLS Configuration

    private var tlsContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TLS Configuration")
                    .font(.headline)
                Spacer()
                Picker("TLS Mode", selection: $viewModel.globalTLSMode) {
                    ForEach(SecurityTLSMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Global TLS mode")
            }
            .padding()

            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("Certificates")
                            .font(.subheadline.bold())
                        Spacer()
                        Button {
                            viewModel.isAddCertificateSheetPresented = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add certificate")
                    }
                    .padding()

                    if viewModel.certificates.isEmpty {
                        ContentUnavailableView(
                            "No Certificates",
                            systemImage: "lock.shield",
                            description: Text("Add TLS certificates for secure DICOM communications.")
                        )
                    } else {
                        List(viewModel.certificates, id: \.id, selection: $viewModel.selectedCertificateID) { cert in
                            HStack {
                                Image(systemName: cert.status == .expired ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                                    .foregroundStyle(cert.status == .expired ? .red : .green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cert.commonName)
                                        .font(.body)
                                    Text("Expires: \(cert.notAfter.formatted(.dateTime.year().month().day()))")
                                        .font(.caption)
                                        .foregroundStyle(cert.status == .expired ? .red : .secondary)
                                }
                                Spacer()
                            }
                            .accessibilityLabel("Certificate \(cert.commonName)")
                            .accessibilityValue(cert.status == .expired ? "Expired" : "Valid")
                        }
                    }

                    if !viewModel.expiringCertificates.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text("\(viewModel.expiringCertificates.count) certificate(s) expiring soon")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(8)
                    }
                }
                .frame(minWidth: 250)

                VStack(spacing: 0) {
                    HStack {
                        Text("Server Security")
                            .font(.subheadline.bold())
                        Spacer()
                    }
                    .padding()

                    if viewModel.serverSecurityEntries.isEmpty {
                        ContentUnavailableView(
                            "No Server Entries",
                            systemImage: "server.rack",
                            description: Text("Configure per-server TLS and security settings.")
                        )
                    } else {
                        List(viewModel.serverSecurityEntries, id: \.id, selection: $viewModel.selectedServerSecurityID) { entry in
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(entry.tlsMode != .development ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.serverName)
                                        .font(.body)
                                    Text("TLS: \(entry.tlsMode.rawValue)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Anonymization

    /// Full dicom-anon UI — mirrors all CLI options.
    private var anonymizationContent: some View {
        HSplitView {
            anonOptionsPanel
                .frame(minWidth: 290, maxWidth: 380)
            anonOutputPanel
                .frame(minWidth: 300)
        }
    }

    // MARK: Options Panel

    private var anonOptionsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                anonInputSection
                anonProfileSection
                if viewModel.anonProfile.isPS315 {
                    anonPS315OptionsSection
                }
                anonOptionsSection
                anonTagsSection
                anonRunSection
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var anonInputSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Input / Output")
                    .font(.subheadline.bold())
                HStack {
                    TextField("DICOM file or directory (required)", text: $viewModel.anonInputPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Anonymization input path")
                    Button("Browse") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true; panel.canChooseDirectories = true
                        if panel.runModal() == .OK {
                            viewModel.anonInputPath = panel.url?.path ?? ""
                            viewModel.anonInputScopedURL = panel.url
                        }
                    }
                }
                HStack {
                    TextField("Output path (--output)", text: $viewModel.anonOutputPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Anonymization output path")
                    Button("Browse") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true   // user can create a new output folder
                        panel.prompt = "Select Output Folder"
                        panel.message = "Choose or create the folder that will receive anonymized files."
                        if panel.runModal() == .OK {
                            viewModel.anonOutputPath = panel.url?.path ?? ""
                            viewModel.anonOutputScopedURL = panel.url
                        }
                    }
                }
            }
        }
    }

    private var anonProfileSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Profile")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("--profile \(viewModel.anonProfile.cliFlag)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Picker("Profile", selection: $viewModel.anonProfile) {
                    ForEach(AnonymizationProfile.builderProfiles, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityLabel("Anonymization profile")
                Text(viewModel.anonProfile.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// PS3.15 2026a E.3 Options for the Basic Profile (dicom-anon's `--retain-*` / `--clean-*`).
    private var anonPS315OptionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("PS3.15 Annex E Options (E.3)")
                    .font(.subheadline.bold())
                ForEach(StudioAnonPS315.securityPanelOptions, id: \.flag) { option in
                    Toggle(isOn: Binding(
                        get: { viewModel.anonPS315Flags[keyPath: option.keyPath] },
                        set: { viewModel.anonPS315Flags[keyPath: option.keyPath] = $0 })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(option.flag)  \(option.name)")
                                .font(.caption)
                            Text("PS3.15 \(option.section)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(option.name)
                }
                Text("Modified Dates needs --shift-dates. Clean Pixel Data (E.3.1) and Clean Recognizable Visual Features (E.3.2) are in the CLI Workshop's dicom-anon form.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle("--allow-burned-in-phi  Write files whose pixels may still carry PHI", isOn: $viewModel.anonAllowBurnedInPHI)
                    .accessibilityLabel("Allow burned-in PHI")
            }
        }
    }

    private var anonOptionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Options")
                    .font(.subheadline.bold())
                Toggle("--recursive  Process directories recursively", isOn: $viewModel.anonRecursive)
                    .accessibilityLabel("Process recursively")
                Toggle("--dry-run  Preview without writing files", isOn: $viewModel.anonDryRun)
                    .accessibilityLabel("Dry run mode")
                Toggle("--backup  Keep backup of originals", isOn: $viewModel.anonBackup)
                    .accessibilityLabel("Create backup files")
                Toggle("--regenerate-uids  Regenerate all UIDs", isOn: $viewModel.anonRegenerateUIDs)
                    .accessibilityLabel("Regenerate UIDs")
                Toggle("--force  Parse without DICM prefix check", isOn: $viewModel.anonForce)
                    .accessibilityLabel("Force parse")
                Toggle("--verbose  Show per-file progress", isOn: $viewModel.anonVerbose)
                    .accessibilityLabel("Verbose output")

                Divider()

                // Date shifting
                HStack {
                    Toggle("--shift-dates", isOn: $viewModel.anonShiftDatesEnabled)
                        .accessibilityLabel("Enable date shifting")
                    if viewModel.anonShiftDatesEnabled {
                        Stepper("\(viewModel.anonShiftDays) days", value: $viewModel.anonShiftDays, in: -36500...36500)
                            .accessibilityLabel("Date shift in days")
                    }
                }

                // Audit log
                HStack {
                    TextField("--audit-log path (optional)", text: $viewModel.anonAuditLogPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Audit log output path")
                    if !viewModel.anonAuditLogPath.isEmpty {
                        Button { viewModel.anonAuditLogPath = "" } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear audit log path")
                    }
                }
            }
        }
    }

    private var anonTagsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Custom Tag Actions")
                    .font(.subheadline.bold())

                // Remove tags
                VStack(alignment: .leading, spacing: 4) {
                    Text("--remove  Tags to remove")
                        .font(.caption.bold())
                    ForEach(viewModel.anonRemoveTags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                                .font(.caption)
                                .monospacedDigit()
                            Spacer()
                            Button { viewModel.removeRemoveTag(tag) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove tag \(tag) from list")
                        }
                    }
                    HStack {
                        TextField("0010,0010 or PatientName", text: $viewModel.anonNewRemoveTag)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .accessibilityLabel("Tag to remove")
                        Button("Add") { viewModel.addRemoveTag() }
                            .accessibilityLabel("Add remove tag")
                    }
                }

                Divider()

                // Replace pairs
                VStack(alignment: .leading, spacing: 4) {
                    Text("--replace  Tag=Value")
                        .font(.caption.bold())
                    ForEach(viewModel.anonReplacePairs, id: \.self) { pair in
                        HStack {
                            Text(pair).font(.caption).monospacedDigit()
                            Spacer()
                            Button { viewModel.removeReplacePair(pair) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove replace pair \(pair)")
                        }
                    }
                    HStack(spacing: 4) {
                        TextField("0010,0010", text: $viewModel.anonNewReplaceTag)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .accessibilityLabel("Tag to replace")
                        Text("=").font(.caption)
                        TextField("ANON", text: $viewModel.anonNewReplaceValue)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .accessibilityLabel("Replacement value")
                        Button("Add") { viewModel.addReplacePair() }
                            .accessibilityLabel("Add replace pair")
                    }
                }

                Divider()

                // Keep tags
                VStack(alignment: .leading, spacing: 4) {
                    Text("--keep  Tags to preserve")
                        .font(.caption.bold())
                    ForEach(viewModel.anonKeepTags, id: \.self) { tag in
                        HStack {
                            Text(tag).font(.caption).monospacedDigit()
                            Spacer()
                            Button { viewModel.removeKeepTag(tag) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove keep tag \(tag)")
                        }
                    }
                    HStack {
                        TextField("0008,0060 or Modality", text: $viewModel.anonNewKeepTag)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .accessibilityLabel("Tag to keep")
                        Button("Add") { viewModel.addKeepTag() }
                            .accessibilityLabel("Add keep tag")
                    }
                }
            }
        }
    }

    private var anonRunSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupBox("CLI Command") {
                Text(viewModel.anonCLICommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel("dicom-anon CLI command preview")
            }

            HStack {
                Button {
                    viewModel.runAnonymization()
                } label: {
                    Label(viewModel.anonIsRunning ? "Anonymizing…" : "Run Anonymization",
                          systemImage: "person.crop.circle.badge.minus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.anonInputPath.isEmpty || viewModel.anonIsRunning)
                .accessibilityLabel("Run DICOM anonymization")

                if viewModel.anonIsRunning {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Clear") { viewModel.clearAnonOutput() }
                    .disabled(viewModel.anonOutput.isEmpty)
                    .accessibilityLabel("Clear anonymization output")
            }
        }
    }

    // MARK: Output Panel

    private var anonOutputPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Output", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                if viewModel.anonDryRun {
                    Text("DRY RUN")
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            .padding()
            Divider()
            ScrollView {
                Text(viewModel.anonOutput.isEmpty
                     ? "Run anonymization to see results.\n\nOutput matches dicom-anon CLI output exactly."
                     : viewModel.anonOutput)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(viewModel.anonOutput.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    // MARK: - Audit Log

    private var auditLogContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Security Audit Log")
                    .font(.headline)
                Spacer()

                Button {
                    viewModel.isAuditExportSheetPresented = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Export audit log")

                Button("Clear") {
                    viewModel.clearAuditEntries()
                }
                .disabled(viewModel.auditEntries.isEmpty)
                .accessibilityLabel("Clear audit log")
            }
            .padding()

            HStack(spacing: 12) {
                TextField("User", text: $viewModel.auditFilterUser)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Filter by user")

                TextField("Reference", text: $viewModel.auditFilterReference)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Filter by reference")

                Button("Clear Filters") {
                    viewModel.clearAuditFilters()
                }
                .font(.caption)

                Spacer()

                Text("\(viewModel.filteredAuditEntries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            if viewModel.filteredAuditEntries.isEmpty {
                ContentUnavailableView(
                    "No Audit Entries",
                    systemImage: "list.clipboard",
                    description: Text("Security audit events will appear here as operations are performed.")
                )
            } else {
                List(viewModel.filteredAuditEntries, id: \.id) { entry in
                    HStack {
                        Image(systemName: auditEventIcon(entry.eventType))
                            .foregroundStyle(auditEventColor(entry.eventType))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.description)
                                .font(.body)
                            HStack(spacing: 8) {
                                Text(entry.userIdentity)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(entry.timestamp.formatted(.dateTime.month().day().hour().minute().second()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Access Control

    private var accessControlContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Access Control")
                    .font(.headline)
                Spacer()
                if let session = viewModel.currentSession {
                    HStack(spacing: 6) {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.green)
                        Text(session.userName)
                            .font(.caption)
                        if let remaining = viewModel.remainingSessionTime {
                            Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Button("Lock") {
                            viewModel.lockSession()
                        }
                        .font(.caption)
                        .accessibilityLabel("Lock session")
                    }
                } else {
                    Text("No active session")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    Text("Permissions")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()

                    if viewModel.permissionMatrix.isEmpty {
                        ContentUnavailableView(
                            "No Permissions Configured",
                            systemImage: "person.badge.key",
                            description: Text("Configure role-based access control permissions.")
                        )
                    } else {
                        List(viewModel.permissionMatrix, id: \.id) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.permission)
                                        .font(.body)
                                    Text(entry.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }

                VStack(spacing: 0) {
                    HStack {
                        Text("Break-Glass Events")
                            .font(.subheadline.bold())
                        Spacer()
                        Button {
                            viewModel.isBreakGlassDialogPresented = true
                        } label: {
                            Label("Break Glass", systemImage: "exclamationmark.shield")
                        }
                        .accessibilityLabel("Initiate break-glass access")
                    }
                    .padding()

                    if viewModel.breakGlassEvents.isEmpty {
                        ContentUnavailableView(
                            "No Break-Glass Events",
                            systemImage: "exclamationmark.shield",
                            description: Text("Emergency access events will be logged here.")
                        )
                    } else {
                        List(viewModel.breakGlassEvents, id: \.id) { event in
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.resourceReference)
                                        .font(.body)
                                    Text("\(event.userName) — \(event.reason)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(event.timestamp.formatted())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func auditEventIcon(_ type: SecurityAuditEventType) -> String {
        switch type {
        case .userLogin: return "person.badge.key"
        case .userLogout: return "person.badge.minus"
        case .fileAccess: return "eye"
        case .fileModification: return "pencil"
        case .fileExport: return "square.and.arrow.up"
        case .fileImport: return "square.and.arrow.down"
        case .networkQuery: return "magnifyingglass"
        case .networkRetrieve: return "arrow.down.circle"
        case .networkSend: return "arrow.up.circle"
        case .anonymization: return "person.crop.circle.badge.minus"
        case .settingsChange: return "gearshape"
        case .securityAlert: return "exclamationmark.shield"
        case .breakGlassAccess: return "exclamationmark.triangle.fill"
        }
    }

    private func auditEventColor(_ type: SecurityAuditEventType) -> Color {
        switch type {
        case .userLogin: return .green
        case .userLogout: return .gray
        case .fileAccess, .networkQuery: return .blue
        case .fileModification, .settingsChange: return .orange
        case .fileExport, .fileImport: return .purple
        case .networkRetrieve, .networkSend: return .blue
        case .anonymization: return .indigo
        case .securityAlert, .breakGlassAccess: return .red
        }
    }
}

// MARK: - Add Certificate Sheet

/// Sheet for adding a TLS certificate to the certificate store.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct AddCertificateSheet: View {
    let onSave: (SecurityCertificateEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var commonName: String = ""
    @State private var issuer: String = ""
    @State private var isPinned: Bool = false
    @State private var pinnedHostname: String = ""
    @State private var isClientCertificate: Bool = false
    @State private var isCACertificate: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Certificate Details") {
                    TextField("Common Name (CN)", text: $commonName)
                        .accessibilityLabel("Certificate common name")
                    TextField("Issuer", text: $issuer)
                        .accessibilityLabel("Certificate issuer")
                }

                Section("Certificate Type") {
                    Toggle("Client Certificate (mTLS)", isOn: $isClientCertificate)
                        .accessibilityLabel("Is client certificate for mutual TLS")
                    Toggle("CA Certificate", isOn: $isCACertificate)
                        .accessibilityLabel("Is certificate authority certificate")
                }

                Section("Pinning") {
                    Toggle("Pin to Server", isOn: $isPinned)
                        .accessibilityLabel("Pin certificate to specific server")
                    if isPinned {
                        TextField("Server Hostname", text: $pinnedHostname)
                            .accessibilityLabel("Hostname to pin certificate to")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Certificate")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let cert = SecurityCertificateEntry(
                            commonName: commonName.trimmingCharacters(in: .whitespaces),
                            issuer: issuer,
                            isPinned: isPinned,
                            isClientCertificate: isClientCertificate,
                            isCACertificate: isCACertificate,
                            pinnedHostname: pinnedHostname
                        )
                        onSave(cert)
                        dismiss()
                    }
                    .disabled(commonName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
    }
}

// MARK: - Anonymization Job Sheet

/// Sheet for creating a new anonymization job.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct NewAnonymizationJobSheet: View {
    @Bindable var viewModel: SecurityViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var filePaths: String = ""
    @State private var outputDirectory: String = ""
    @State private var keyEscrow: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Files") {
                    TextField("File paths (one per line)", text: $filePaths, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("DICOM file paths to anonymize")
                }

                Section("Profile") {
                    Picker("Anonymization Profile", selection: $viewModel.selectedProfile) {
                        ForEach(AnonymizationProfile.allCases, id: \.self) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .accessibilityLabel("Anonymization profile")
                }

                Section("Output") {
                    TextField("Output Directory", text: $outputDirectory)
                        .accessibilityLabel("Output directory for anonymized files")
                    Toggle("Key Escrow (Reversible)", isOn: $keyEscrow)
                        .accessibilityLabel("Enable key escrow for reversible anonymization")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Anonymization Job")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let paths = filePaths
                            .components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        viewModel.stagedFilePaths = paths
                        viewModel.outputDirectory = outputDirectory
                        viewModel.keyEscrowEnabled = keyEscrow
                        viewModel.enqueueAnonymizationJob()
                        dismiss()
                    }
                    .disabled(filePaths.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              outputDirectory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 380)
    }
}

// MARK: - Audit Export Sheet

/// Sheet for configuring and exporting the audit log.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct AuditExportSheet: View {
    @Bindable var viewModel: SecurityViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var exportedText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Form {
                    Section("Export Format") {
                        Picker("Format", selection: $viewModel.auditExportFormat) {
                            ForEach(SecurityAuditExportFormat.allCases, id: \.self) { fmt in
                                Text(fmt.displayName).tag(fmt)
                            }
                        }
                        .accessibilityLabel("Audit log export format")
                    }

                    Section("Preview") {
                        if exportedText.isEmpty {
                            Text("Click Export to generate output.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                Text(exportedText)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 150, maxHeight: .infinity)
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .navigationTitle("Export Audit Log")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        exportedText = viewModel.exportAuditLogCSV()
                    }
                    .disabled(viewModel.filteredAuditEntries.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
#endif
