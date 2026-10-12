// SecurityViewModel.swift
// DICOMStudio
//
// DICOM Studio — ViewModel for the Security & Privacy Center (Milestone 11)
// Reference: DICOM PS3.15 (Security and System Management Profiles); HIPAA Security Rule §164.312 (law)
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: the UI profiles are mapped onto the DICOMKit Anonymizer profiles (basic / clinicalTrial / research / custom, engineProfile) whose attribute lists SecurityHelpers mirrors; the dicom-anon command line comes from AnonHelpers.buildCommand; TLS, audit and access-control state is app state

import Foundation
import Observation
import DICOMKit
import DICOMCore

#if canImport(CryptoKit)
import CryptoKit
#endif

/// ViewModel for the Security & Privacy Center, managing state for all four sections:
/// TLS configuration, anonymization tool, audit log viewer, and access control.
///
/// Requires macOS 14+ / iOS 17+ for the `@Observable` macro.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
@MainActor
public final class SecurityViewModel {

    // MARK: - Dependencies

    private let service: SecurityService

    // MARK: - Navigation

    /// Currently active security tab.
    public var activeTab: SecurityTab = .tlsConfiguration
    /// Whether an operation is in progress.
    public var isLoading: Bool = false
    /// Error message to display, if any.
    public var errorMessage: String? = nil

    // MARK: - 11.1 TLS Configuration

    /// Global TLS mode applied to all new connections.
    public var globalTLSMode: SecurityTLSMode = .compatible
    /// All certificates in the certificate store.
    public var certificates: [SecurityCertificateEntry] = []
    /// Currently selected certificate ID for detail/editing.
    public var selectedCertificateID: UUID? = nil
    /// Whether the add-certificate sheet is showing.
    public var isAddCertificateSheetPresented: Bool = false
    /// All server security entries.
    public var serverSecurityEntries: [SecurityServerEntry] = []
    /// Currently selected server security entry ID.
    public var selectedServerSecurityID: UUID? = nil
    /// Whether the TLS handshake details sheet is showing.
    public var isTLSHandshakeSheetPresented: Bool = false

    // MARK: - 11.2 Anonymization

    /// Files staged for anonymization.
    public var stagedFilePaths: [String] = []
    /// Output directory for anonymized files.
    public var outputDirectory: String = ""
    /// Whether key escrow is enabled for reversibility.
    public var keyEscrowEnabled: Bool = false
    /// All anonymization jobs.
    public var anonymizationJobs: [AnonymizationJob] = []
    /// Currently selected job ID.
    public var selectedJobID: UUID? = nil
    /// Whether the new-job sheet is showing.
    public var isNewJobSheetPresented: Bool = false
    /// PHI detection results.
    public var phiDetectionResults: [PHIDetectionResult] = []
    /// Whether PHI scan is running.
    public var isPHIScanRunning: Bool = false

    // MARK: - 11.2b Anon Builder (dicom-anon CLI parity)

    /// --input path
    public var anonInputPath: String = ""
    /// --output path
    public var anonOutputPath: String = ""
    /// Dates: `keep` = --retain-dates (Full Dates), `shift` = --shift-dates N
    /// (Modified Dates), `remove` = neither (the Basic Profile zeroes them).
    public enum AnonDatePolicy: String, CaseIterable, Sendable { case remove, keep, shift }
    public var anonDatePolicy: AnonDatePolicy = .remove
    public var anonShiftDays: Int = 0
    /// --recursive
    public var anonRecursive: Bool = false
    /// --dry-run
    public var anonDryRun: Bool = false
    /// --backup
    public var anonBackup: Bool = false
    /// --audit-log path
    public var anonAuditLogPath: String = ""
    /// --force
    public var anonForce: Bool = false
    /// --verbose
    public var anonVerbose: Bool = false

    // PS3.15 Annex E retention options
    public var anonRetainCharacteristics: Bool = false
    public var anonRetainDevice: Bool = false
    public var anonRetainInstitution: Bool = false
    public var anonRetainUIDs: Bool = false
    public var anonCleanDescriptors: Bool = false
    public var anonRetainSafePrivate: Bool = false
    public var anonCleanGraphics: Bool = false
    public var anonCleanStructuredContent: Bool = false
    public var anonCleanRecognizableVisualFeatures: Bool = false


    // Pixel pipeline (Clean Pixel Data, OCR, styles, re-encode)
    /// Clean Pixel Data (default on; off = --no-clean-pixel-data)
    public var anonCleanPixelData: Bool = true
    /// --redact-region x,y,w,h (one per entry)
    public var anonRedactRegions: [String] = []
    /// --redact-fill black|white|<value> (nil = black)
    public var anonRedactFill: String? = nil
    /// --redact-style blank|label|replace
    public var anonRedactStyle: String = "blank"
    /// --redact-label (empty = REDACTED)
    public var anonRedactLabel: String = ""
    /// --recompress source|<codec> (empty = Explicit VR LE)
    public var anonRecompress: String = ""
    /// --ocr-mode header|classify
    public var anonOCRMode: String = "classify"
    /// --ocr-all-frames
    public var anonOCRAllFrames: Bool = false
    /// --text-only
    public var anonTextOnly: Bool = false
    /// --allow-burned-in-phi
    public var anonAllowBurnedInPHI: Bool = false
    /// Transient entry state for a new --redact-region.
    public var anonNewRedactRegion: String = ""

    /// Running flag
    public var anonIsRunning: Bool = false
    /// Structured exit code of the last anonymization run (CLI rule: any failed
    /// file → 1). Read by the Workshop executor instead of sniffing the output
    /// text for "error" strings.
    public var anonLastExitCode: Int = 0
    /// Output text (matches dicom-anon printSummary() format)
    public var anonOutput: String = ""

    // MARK: - Security-Scoped Resource Access
    // Set by the view (or CLIWorkshopViewModel) immediately after NSOpenPanel /
    // NSSavePanel so the sandbox can read/write those paths.
    public var anonInputScopedURL: URL?
    public var anonOutputScopedURL: URL?

    // MARK: - 11.3 Audit Log

    /// All audit log entries.
    public var auditEntries: [SecurityAuditEntry] = []
    /// Filter: event type (nil = all types).
    public var auditFilterEventType: SecurityAuditEventType? = nil
    /// Filter: user identity substring.
    public var auditFilterUser: String = ""
    /// Filter: patient/study reference substring.
    public var auditFilterReference: String = ""
    /// Filter: start date for date-range filter (nil = no lower bound).
    public var auditFilterStartDate: Date? = nil
    /// Filter: end date for date-range filter (nil = no upper bound).
    public var auditFilterEndDate: Date? = nil
    /// Selected export format for audit log export.
    public var auditExportFormat: SecurityAuditExportFormat = .csv
    /// Currently enabled log handlers.
    public var enabledHandlers: Set<SecurityAuditHandlerType> = [.console]
    /// Current audit log retention policy.
    public var retentionPolicy: SecurityAuditRetentionPolicy = .days365
    /// Whether the export sheet is showing.
    public var isAuditExportSheetPresented: Bool = false

    // MARK: - 11.4 Access Control

    /// Current user session.
    public var currentSession: AccessControlSession? = nil
    /// Permission matrix entries for display.
    public var permissionMatrix: [PermissionEntry] = []
    /// All break-glass events.
    public var breakGlassEvents: [BreakGlassEvent] = []
    /// Whether the break-glass dialog is showing.
    public var isBreakGlassDialogPresented: Bool = false
    /// Reason text for a pending break-glass request.
    public var breakGlassReason: String = ""

    // MARK: - Init

    public init(service: SecurityService = SecurityService()) {
        self.service = service
        loadAll()
    }

    // MARK: - Private Loader

    private func loadAll() {
        globalTLSMode = service.getGlobalTLSMode()
        certificates = service.getCertificates()
        serverSecurityEntries = service.getServerSecurityEntries()
        anonymizationJobs = service.getAnonymizationJobs()
        phiDetectionResults = service.getPHIDetectionResults()
        auditEntries = service.getAuditEntries()
        enabledHandlers = service.getEnabledHandlers()
        retentionPolicy = service.getRetentionPolicy()
        currentSession = service.getCurrentSession()
        breakGlassEvents = service.getBreakGlassEvents()
        permissionMatrix = AccessControlHelpers.standardPermissionMatrix()
    }

    // MARK: - 11.1 TLS Actions

    /// Updates the global TLS mode.
    public func setGlobalTLSMode(_ mode: SecurityTLSMode) {
        globalTLSMode = mode
        service.setGlobalTLSMode(mode)
    }

    /// Adds a certificate to the store.
    public func addCertificate(_ certificate: SecurityCertificateEntry) {
        service.addCertificate(certificate)
        certificates = service.getCertificates()
    }

    /// Updates an existing certificate.
    public func updateCertificate(_ certificate: SecurityCertificateEntry) {
        service.updateCertificate(certificate)
        certificates = service.getCertificates()
    }

    /// Removes a certificate by ID.
    public func removeCertificate(id: UUID) {
        service.removeCertificate(id: id)
        certificates = service.getCertificates()
        if selectedCertificateID == id { selectedCertificateID = nil }
    }

    /// Returns the currently selected certificate, if any.
    public var selectedCertificate: SecurityCertificateEntry? {
        guard let id = selectedCertificateID else { return nil }
        return certificates.first(where: { $0.id == id })
    }

    /// Returns certificates that are expiring or already expired.
    public var expiringCertificates: [SecurityCertificateEntry] {
        service.expiringCertificates()
    }

    /// Adds a server security entry.
    public func addServerSecurityEntry(_ entry: SecurityServerEntry) {
        service.addServerSecurityEntry(entry)
        serverSecurityEntries = service.getServerSecurityEntries()
    }

    /// Updates an existing server security entry.
    public func updateServerSecurityEntry(_ entry: SecurityServerEntry) {
        service.updateServerSecurityEntry(entry)
        serverSecurityEntries = service.getServerSecurityEntries()
    }

    /// Removes a server security entry by ID.
    public func removeServerSecurityEntry(id: UUID) {
        service.removeServerSecurityEntry(id: id)
        serverSecurityEntries = service.getServerSecurityEntries()
        if selectedServerSecurityID == id { selectedServerSecurityID = nil }
    }

    // MARK: - 11.2 Anonymization Actions

    /// Enqueues a new anonymization job with the current settings.
    public func enqueueAnonymizationJob() {
        var job = AnonymizationJob(
            filePaths: stagedFilePaths,
            status: .pending,
            totalFiles: stagedFilePaths.count,
            outputDirectory: outputDirectory,
            keyEscrowEnabled: keyEscrowEnabled
        )
        job.totalFiles = stagedFilePaths.count
        service.enqueueAnonymizationJob(job)
        anonymizationJobs = service.getAnonymizationJobs()
        stagedFilePaths = []
        isNewJobSheetPresented = false
    }

    /// Cancels a running or pending job.
    public func cancelAnonymizationJob(id: UUID) {
        service.cancelAnonymizationJob(id: id)
        anonymizationJobs = service.getAnonymizationJobs()
    }

    /// Removes a terminal job.
    public func removeAnonymizationJob(id: UUID) {
        service.removeAnonymizationJob(id: id)
        anonymizationJobs = service.getAnonymizationJobs()
        if selectedJobID == id { selectedJobID = nil }
    }

    /// Returns the currently selected anonymization job.
    public var selectedJob: AnonymizationJob? {
        guard let id = selectedJobID else { return nil }
        return anonymizationJobs.first(where: { $0.id == id })
    }

    /// Returns a validation error message if the staged file list is empty or output dir is missing.
    public func jobValidationError() -> String? {
        if stagedFilePaths.isEmpty { return "No files staged for anonymization." }
        if outputDirectory.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Output directory must not be empty."
        }
        return nil
    }

    // MARK: - 11.2b Anon Builder Actions

    /// The shared workflow request for the current builder state — the same
    /// `AnonymizationWorkflow.Request` the `dicom-anon` CLI builds from argv.
    public var anonRequest: AnonymizationWorkflow.Request {
        var r = AnonymizationWorkflow.Request(inputPath: anonInputPath)
        r.output = anonOutputPath.isEmpty ? nil : anonOutputPath
        r.retainDates = anonDatePolicy == .keep
        r.shiftDates = anonDatePolicy == .shift ? anonShiftDays : nil
        r.retainCharacteristics = anonRetainCharacteristics
        r.retainDevice = anonRetainDevice
        r.retainInstitution = anonRetainInstitution
        r.retainUids = anonRetainUIDs
        r.cleanDescriptors = anonCleanDescriptors
        r.retainSafePrivate = anonRetainSafePrivate
        r.cleanGraphics = anonCleanGraphics
        r.cleanStructuredContent = anonCleanStructuredContent
        r.cleanRecognizableVisualFeatures = anonCleanRecognizableVisualFeatures

        r.cleanPixelData = anonCleanPixelData
        r.redactRegion = anonRedactRegions
        r.redactFill = anonRedactFill
        r.redactStyle = anonRedactStyle
        r.redactLabel = anonRedactLabel.isEmpty ? nil : anonRedactLabel
        r.recompress = anonRecompress.isEmpty ? nil : anonRecompress
        r.ocrMode = anonOCRMode
        r.ocrAllFrames = anonOCRAllFrames
        r.textOnly = anonTextOnly
        r.allowBurnedInPHI = anonAllowBurnedInPHI
        r.recursive = anonRecursive
        r.dryRun = anonDryRun
        r.backup = anonBackup
        r.auditLog = anonAuditLogPath.isEmpty ? nil : anonAuditLogPath
        r.force = anonForce
        r.verbose = anonVerbose
        return r
    }

    /// Returns the exact dicom-anon CLI command for current builder state.
    public var anonCLICommand: String {
        AnonHelpers.buildCommand(anonRequest)
    }

    public func addRedactRegion() {
        let region = anonNewRedactRegion.trimmingCharacters(in: .whitespaces)
        guard !region.isEmpty, !anonRedactRegions.contains(region) else { return }
        anonRedactRegions.append(region)
        anonNewRedactRegion = ""
    }

    /// Runs anonymization natively through the shared workflow (fire-and-forget
    /// for the Security screen's Run button; `performAnonymization()` awaits it).
    public func runAnonymization() {
        Task { await performAnonymization() }
    }

    /// Runs the shared `AnonymizationWorkflow` for the current builder state and
    /// publishes its console text + exit code. Output matches `dicom-anon` exactly.
    @discardableResult
    public func performAnonymization() async -> (output: String, exitCode: Int) {
        guard !anonInputPath.isEmpty else {
            anonOutput = "Error: Input path is required.\n"
            anonLastExitCode = 1
            return (anonOutput, 1)
        }
        anonIsRunning = true
        anonOutput = "Running: \(anonCLICommand)\n"
        let request = anonRequest
        let inputScoped = anonInputScopedURL
        let outputScoped = anonOutputScopedURL
        let result = await Task.detached(priority: .userInitiated) {
            await Self.executeAnonymization(request, inputScopedURL: inputScoped, outputScopedURL: outputScoped)
        }.value
        anonOutput = result.output
        anonLastExitCode = result.exitCode
        anonIsRunning = false
        return result
    }

    public func clearAnonOutput() {
        anonOutput = ""
    }

    // MARK: - 11.2b Anon Engine (shared AnonymizationWorkflow, matches dicom-anon output)

    /// Runs one `dicom-anon` request in-process. Used by the Security screen builder
    /// and by the CLI Workshop executor. The only app-specific work here is sandbox
    /// plumbing: security-scoped access and a guaranteed-writable output location.
    /// Everything else — parsing, validation, the pixel-first run, refusal, every
    /// console line — is `AnonymizationWorkflow`, the code the CLI itself runs.
    nonisolated public static func executeAnonymization(
        _ base: AnonymizationWorkflow.Request,
        inputScopedURL: URL?,
        outputScopedURL: URL?
    ) async -> (output: String, exitCode: Int) {
        let inputAccessing  = inputScopedURL?.startAccessingSecurityScopedResource()  ?? false
        let outputAccessing = outputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if inputAccessing  { inputScopedURL?.stopAccessingSecurityScopedResource() }
            if outputAccessing { outputScopedURL?.stopAccessingSecurityScopedResource() }
        }

        var request = base
        if let inputScopedURL { request.inputPath = inputScopedURL.path }

        // Resolve a guaranteed-writable output path before any file I/O.
        let (effectiveOutputPath, redirectNote) = resolveWritableOutput(
            path: base.output ?? "", scopedURL: outputScopedURL)
        request.output = effectiveOutputPath.isEmpty ? nil : effectiveOutputPath

        var output = redirectNote ?? ""
        // Sandbox/TCC-resilient write: resolveWritableOutput uses POSIX checks that
        // miss TCC, so retry at write time and fall back to ~/Downloads. The note
        // surfaces in the run's warnings, exactly where the CLI would report a
        // write problem.
        let workflow = AnonymizationWorkflow(writeFile: { data, url in
            try OutputAccess.write(data, toPath: url.path, scopedURL: nil, subfolder: "Anonymized").note
        })
        do {
            let outcome = try await workflow.run(request) { output += $0 }
            return (output, Int(outcome.exitCode))
        } catch {
            // The CLI prints `Error: <message>` (ArgumentParser) and exits 1.
            return (output + "Error: \(error.localizedDescription)\n", 1)
        }
    }

    // MARK: - Anon Engine Helpers

    /// Resolves a writable output path within the sandbox.
    ///
    /// Priority:
    ///  1. The security-scoped URL from the file picker (always writable).
    ///  2. Any path already under ~/Downloads (covered by the downloads entitlement).
    ///  3. ~/Downloads/DICOMStudio/Anonymized/ as a safe fallback.
    ///
    /// Returns the resolved path and an optional redirect notice to display in the output.
    nonisolated static func resolveWritableOutput(
        path: String,
        scopedURL: URL?
    ) -> (path: String, redirectNote: String?) {
        // 1. Scoped URL — always writable
        if let url = scopedURL { return (url.path, nil) }
        guard !path.isEmpty else { return (path, nil) }

        let fm = FileManager.default

        // 2. ~/Downloads — directly accessible via entitlement
        let downloadsPath = fm.urls(for: .downloadsDirectory, in: .userDomainMask)
            .first?.path ?? (NSHomeDirectory() + "/Downloads")
        if path.hasPrefix(downloadsPath) { return (path, nil) }

        // 3. Check if an existing ancestor is writable (handles paths the user
        //    has already been granted access to in a previous session)
        var ancestor = (path as NSString).deletingLastPathComponent
        for _ in 0..<5 {
            if fm.isWritableFile(atPath: ancestor) { return (path, nil) }
            let parent = (ancestor as NSString).deletingLastPathComponent
            if parent == ancestor { break }
            ancestor = parent
        }

        // 4. Fall back to ~/Downloads/DICOMStudio/Anonymized/
        let fallback = URL(fileURLWithPath: downloadsPath)
            .appendingPathComponent("DICOMStudio")
            .appendingPathComponent("Anonymized")
        try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        let note = """
            ⚠ Output redirected to: \(fallback.path)
              (Sandbox: use the Browse button to select a writable output location)

            """
        return (fallback.path, note)
    }

    // MARK: - 11.3 Audit Log Actions

    /// Appends an audit log entry (and syncs to service).
    public func addAuditEntry(_ entry: SecurityAuditEntry) {
        service.addAuditEntry(entry)
        auditEntries = service.getAuditEntries()
    }

    /// Clears all audit log entries.
    public func clearAuditEntries() {
        service.clearAuditEntries()
        auditEntries = []
    }

    /// Applies the current retention policy.
    public func applyRetentionPolicy() {
        service.applyRetentionPolicy()
        auditEntries = service.getAuditEntries()
    }

    /// Enables or disables a log handler.
    public func setHandler(_ handler: SecurityAuditHandlerType, enabled: Bool) {
        service.setHandler(handler, enabled: enabled)
        enabledHandlers = service.getEnabledHandlers()
    }

    /// Sets the audit retention policy.
    public func setRetentionPolicy(_ policy: SecurityAuditRetentionPolicy) {
        retentionPolicy = policy
        service.setRetentionPolicy(policy)
    }

    /// Returns audit entries that match the current filter settings.
    public var filteredAuditEntries: [SecurityAuditEntry] {
        var result = auditEntries
        if let type = auditFilterEventType {
            result = SecurityAuditHelpers.filter(result, byType: type)
        }
        if !auditFilterUser.isEmpty {
            result = SecurityAuditHelpers.filter(result, byUser: auditFilterUser)
        }
        if !auditFilterReference.isEmpty {
            result = SecurityAuditHelpers.filter(result, byReference: auditFilterReference)
        }
        if let start = auditFilterStartDate, let end = auditFilterEndDate {
            result = result.filter { SecurityAuditHelpers.entry($0, isInRange: start...end) }
        }
        return result
    }

    /// Clears all audit log filters.
    public func clearAuditFilters() {
        auditFilterEventType = nil
        auditFilterUser = ""
        auditFilterReference = ""
        auditFilterStartDate = nil
        auditFilterEndDate = nil
    }

    /// Returns the audit log as CSV text for export.
    public func exportAuditLogCSV() -> String {
        SecurityAuditHelpers.toCSV(filteredAuditEntries)
    }

    /// Returns audit log statistics (counts per event type).
    public var auditStatistics: [SecurityAuditEventType: Int] {
        SecurityAuditHelpers.statistics(auditEntries)
    }

    // MARK: - 11.4 Access Control Actions

    /// Sets the current user session.
    public func setCurrentSession(_ session: AccessControlSession?) {
        service.setCurrentSession(session)
        currentSession = service.getCurrentSession()
    }

    /// Touches the session to update the last activity timestamp.
    public func touchSession() {
        service.touchSession()
        currentSession = service.getCurrentSession()
    }

    /// Locks the current session.
    public func lockSession() {
        service.lockSession()
        currentSession = service.getCurrentSession()
    }

    /// Records a break-glass emergency access event.
    public func recordBreakGlassEvent(resource: String) {
        guard !breakGlassReason.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let event = BreakGlassEvent(
            userName: currentSession?.userName ?? "Unknown",
            resourceReference: resource,
            reason: breakGlassReason,
            supervisorNotified: true
        )
        service.recordBreakGlassEvent(event)
        breakGlassEvents = service.getBreakGlassEvents()
        auditEntries = service.getAuditEntries()
        breakGlassReason = ""
        isBreakGlassDialogPresented = false
    }

    /// Returns whether the current user has a given permission.
    public func currentUserHasPermission(for action: String) -> Bool {
        guard let session = currentSession else { return false }
        return AccessControlHelpers.hasPermission(session.role, for: action)
    }

    /// Returns remaining session idle time in seconds, or nil if no session.
    public var remainingSessionTime: TimeInterval? {
        guard let session = currentSession else { return nil }
        return AccessControlHelpers.remainingSessionTime(for: session)
    }
}
