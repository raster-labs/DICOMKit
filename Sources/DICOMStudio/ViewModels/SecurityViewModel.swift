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

    /// Currently selected anonymization profile (default: the PS3.15 Basic Profile, P-STUDIO-ANON-PS315).
    public var selectedProfile: AnonymizationProfile = .ps315
    /// Custom rules (active when profile == .custom).
    public var customRules: [AnonymizationTagRule] = []
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
    /// --profile (default ps315, the PS3.15 Basic Application Level Confidentiality Profile, as dicom-anon)
    public var anonProfile: AnonymizationProfile = .ps315
    /// PS3.15 2026a E.3 Option flags (`--retain-*` / `--clean-*`); dicom-anon accepts them only
    /// with `--profile ps315`. Clean Recognizable Visual Features (E.3.2) needs operator regions
    /// and Clean Pixel Data (E.3.1) pixel editing: both are in the CLI Workshop's dicom-anon form.
    public var anonPS315Flags = AnonCLI.PS315Flags()
    /// --allow-burned-in-phi (`--profile ps315`): write a file whose pixels may still carry PHI.
    public var anonAllowBurnedInPHI: Bool = false
    /// --shift-dates N (nil = disabled)
    public var anonShiftDatesEnabled: Bool = false
    public var anonShiftDays: Int = 0
    /// --regenerate-uids
    public var anonRegenerateUIDs: Bool = false
    /// --remove tag (one per entry, format: 0010,0010 or PatientName)
    public var anonRemoveTags: [String] = []
    /// --replace tag=value
    public var anonReplacePairs: [String] = []
    /// --keep tag
    public var anonKeepTags: [String] = []
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

    /// Transient new-tag entry state
    public var anonNewRemoveTag: String = ""
    public var anonNewReplaceTag: String = ""
    public var anonNewReplaceValue: String = ""
    public var anonNewKeepTag: String = ""

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
        selectedProfile = service.getSelectedProfile()
        customRules = service.getCustomRules()
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

    /// Sets the anonymization profile and loads its default rules if not custom.
    public func setProfile(_ profile: AnonymizationProfile) {
        selectedProfile = profile
        service.setSelectedProfile(profile)
        if profile != .custom {
            let rules = AnonymizationHelpers.defaultRules(for: profile)
            customRules = rules
            service.setCustomRules(rules)
        }
    }

    /// Adds a custom rule.
    public func addCustomRule(_ rule: AnonymizationTagRule) {
        service.addCustomRule(rule)
        customRules = service.getCustomRules()
    }

    /// Removes a custom rule by ID.
    public func removeCustomRule(id: UUID) {
        service.removeCustomRule(id: id)
        customRules = service.getCustomRules()
    }

    /// Enqueues a new anonymization job with the current settings.
    public func enqueueAnonymizationJob() {
        let rules = selectedProfile == .custom
            ? customRules
            : AnonymizationHelpers.defaultRules(for: selectedProfile)
        var job = AnonymizationJob(
            filePaths: stagedFilePaths,
            profile: selectedProfile,
            customRules: rules,
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

    /// Returns the exact dicom-anon CLI command for current builder state.
    public var anonCLICommand: String {
        AnonHelpers.buildCommand(
            inputPath: anonInputPath,
            outputPath: anonOutputPath,
            profile: anonProfile,
            shiftDates: anonShiftDatesEnabled ? anonShiftDays : nil,
            regenerateUIDs: anonRegenerateUIDs,
            removeTags: anonRemoveTags,
            replacePairs: anonReplacePairs,
            keepTags: anonKeepTags,
            recursive: anonRecursive,
            dryRun: anonDryRun,
            backup: anonBackup,
            auditLogPath: anonAuditLogPath,
            force: anonForce,
            verbose: anonVerbose,
            ps315OptionFlags: anonProfile.isPS315 ? anonPS315Flags.setFlags : [],
            allowBurnedInPHI: anonProfile.isPS315 && anonAllowBurnedInPHI
        )
    }

    public func addRemoveTag() {
        let tag = anonNewRemoveTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !anonRemoveTags.contains(tag) else { return }
        anonRemoveTags.append(tag)
        anonNewRemoveTag = ""
    }

    public func removeRemoveTag(_ tag: String) {
        anonRemoveTags.removeAll { $0 == tag }
    }

    public func addReplacePair() {
        let tag   = anonNewReplaceTag.trimmingCharacters(in: .whitespaces)
        let value = anonNewReplaceValue.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        let pair = "\(tag)=\(value)"
        if !anonReplacePairs.contains(pair) {
            anonReplacePairs.append(pair)
        }
        anonNewReplaceTag = ""
        anonNewReplaceValue = ""
    }

    public func removeReplacePair(_ pair: String) {
        anonReplacePairs.removeAll { $0 == pair }
    }

    public func addKeepTag() {
        let tag = anonNewKeepTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !anonKeepTags.contains(tag) else { return }
        anonKeepTags.append(tag)
        anonNewKeepTag = ""
    }

    public func removeKeepTag(_ tag: String) {
        anonKeepTags.removeAll { $0 == tag }
    }

    /// Runs anonymization natively using DICOMKit APIs.
    /// Output matches dicom-anon printSummary() exactly.
    public func runAnonymization() {
        guard !anonInputPath.isEmpty else {
            anonOutput = "Error: Input path is required.\n"
            anonLastExitCode = 1
            return
        }
        anonIsRunning = true
        anonOutput = "Running: \(anonCLICommand)\n"

        // Capture all parameters before crossing isolation boundary
        let inputPath   = anonInputPath
        let outputPath  = anonOutputPath
        let profile     = anonProfile
        let shiftDays   = anonShiftDatesEnabled ? anonShiftDays : nil
        let regen       = anonRegenerateUIDs
        let removeTags  = anonRemoveTags
        let replacePairs = anonReplacePairs
        let keepTags    = anonKeepTags
        let recursive   = anonRecursive
        let dryRun      = anonDryRun
        let backup      = anonBackup
        let auditLog    = anonAuditLogPath
        let force       = anonForce
        let verbose     = anonVerbose
        let ps315Flags  = anonProfile.isPS315 ? anonPS315Flags : AnonCLI.PS315Flags()
        let allowPHI    = anonProfile.isPS315 && anonAllowBurnedInPHI

        Task {
            let result = await self.executeAnonymization(
                inputPath: inputPath,
                outputPath: outputPath,
                profile: profile,
                shiftDays: shiftDays,
                regenerateUIDs: regen,
                removeTags: removeTags,
                replacePairs: replacePairs,
                keepTags: keepTags,
                recursive: recursive,
                dryRun: dryRun,
                backup: backup,
                auditLogPath: auditLog,
                force: force,
                verbose: verbose,
                ps315Flags: ps315Flags,
                allowBurnedInPHI: allowPHI
            )
            self.anonOutput = result.output
            self.anonLastExitCode = result.exitCode
            self.anonIsRunning = false
        }
    }

    public func clearAnonOutput() {
        anonOutput = ""
    }

    // MARK: - 11.2b Anon Engine (native DICOMKit, matches dicom-anon output)

    private func executeAnonymization(
        inputPath: String,
        outputPath: String,
        profile: AnonymizationProfile,
        shiftDays: Int?,
        regenerateUIDs: Bool,
        removeTags: [String],
        replacePairs: [String],
        keepTags: [String],
        recursive: Bool,
        dryRun: Bool,
        backup: Bool,
        auditLogPath: String,
        force: Bool,
        verbose: Bool,
        ps315Flags: AnonCLI.PS315Flags = AnonCLI.PS315Flags(),
        allowBurnedInPHI: Bool = false
    ) async -> (output: String, exitCode: Int) {
        // Start security-scoped resource access so the sandbox allows reading
        // the user-selected input and writing to the chosen output directory.
        let inputAccessing  = anonInputScopedURL?.startAccessingSecurityScopedResource()  ?? false
        let outputAccessing = anonOutputScopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if inputAccessing  { anonInputScopedURL?.stopAccessingSecurityScopedResource() }
            if outputAccessing { anonOutputScopedURL?.stopAccessingSecurityScopedResource() }
        }

        // Resolve a guaranteed-writable output path before any file I/O.
        let (effectiveOutputPath, redirectNote) = Self.resolveWritableOutput(
            path: outputPath,
            scopedURL: anonOutputScopedURL
        )

        var totalFiles = 0
        var successful = 0
        var failed = 0
        var warnings: [String] = []
        var modifiedTagNames: [String] = []
        var output = redirectNote ?? ""

        // Resolve file list
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputPath, isDirectory: &isDir) else {
            return ("Error: Input path not found: \(inputPath)\n", 1)
        }

        // CLI parity: dicom-anon requires --output for a single-file run unless
        // --dry-run is set (see main.swift) — without it there is nowhere to write,
        // so anonymizing would silently discard its result while still reporting
        // success. Mirror that guard here instead of falling through to the write
        // step below, which no-ops on an empty output path for a single file.
        if !dryRun && effectiveOutputPath.isEmpty && !isDir.boolValue {
            return (output + "Error: Anonymization requires an output path (or enable Dry Run to preview without writing).\n", 1)
        }

        // Validate every --remove/--replace/--keep spec up front, mirroring the CLI's
        // parseCustomActions/parsePreserveTags: unparseable input must ERROR (the CLI
        // throws ValidationError), never be silently compactMap-dropped while the run
        // still reports success.
        for spec in removeTags where Self.parseTag(spec) == nil {
            return (output + "Error: Invalid tag format: \(spec)\n", 1)
        }
        for pair in replacePairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                return (output + "Error: Invalid replace format: \(pair). Use TAG=VALUE\n", 1)
            }
            if Self.parseTag(String(parts[0])) == nil {
                return (output + "Error: Invalid tag format: \(parts[0])\n", 1)
            }
        }
        for spec in keepTags where Self.parseTag(spec) == nil {
            return (output + "Error: Invalid tag format: \(spec)\n", 1)
        }

        // P-STUDIO-ANON-PS315: the PS3.15 Basic Profile runs dicom-anon's ps315 path — the
        // option rules of DICOMKit AnonCLI.validate (PS3.15 2026a E.3; --keep and an unpaired
        // --shift-dates are refused as the CLI refuses them), then Anonymizer.deidentify.
        let isPS315 = profile.isPS315
        let ps315Options = AnonCLI.options(flags: ps315Flags, shiftDates: shiftDays)
        if isPS315 {
            do {
                try AnonCLI.validate(profile: profile.cliFlag, flags: ps315Flags, shiftDates: shiftDays,
                                     regenerateUids: regenerateUIDs, keep: keepTags)
            } catch {
                return (output + "Error: \(error.localizedDescription)\n", 1)
            }
            if ps315Flags.retainDates {
                output += AnonCLI.retainDatesNotice(shiftDates: shiftDays) + "\n"
            }
        }
        var reports: [(path: String, actions: [AnonCLI.AttributeAction])] = []

        var fileURLs: [URL] = []
        if isDir.boolValue {
            guard recursive else {
                return ("Error: Directory anonymization requires --recursive flag\n", 1)
            }
            guard !outputPath.isEmpty else {
                return ("Error: Directory anonymization requires --output directory\n", 1)
            }
            // Shared, sorted directory walk — the exact gatherer dicom-anon uses,
            // so both surfaces process the same files in the same order.
            guard let gathered = FileGatherer.regularFiles(under: URL(fileURLWithPath: inputPath)) else {
                return ("Error: Failed to enumerate directory: \(inputPath)\n", 1)
            }
            fileURLs = gathered
        } else {
            fileURLs = [URL(fileURLWithPath: inputPath)]
        }

        // Build the shared anonymization engine ONCE for the whole run — the exact
        // same DICOMKit.Anonymizer the `dicom-anon` CLI uses, so the app and CLI
        // cannot drift. Reusing one instance keeps UID remapping consistent across
        // every file in a directory (matching the CLI), and the engine — not the
        // app — now owns profile→tag mapping, per-tag defaults, UID regeneration,
        // date shifting, and PHI scanning.
        let anonymizer = DICOMKit.Anonymizer(
            profile: Self.engineProfile(profile, removeTags: removeTags),
            shiftDates: shiftDays,
            regenerateUIDs: regenerateUIDs,
            preserveTags: Set(keepTags.compactMap { Self.parseTag($0) }),
            customActions: Self.engineCustomActions(removeTags: removeTags, replacePairs: replacePairs)
        )

        for fileURL in fileURLs {
            totalFiles += 1
            // CLI parity: dicom-anon computes the path relative to the input directory
            // for its verbose per-file lines (directory mode only).
            let relativePath = String(
                fileURL.path.replacingOccurrences(of: inputPath, with: "").drop(while: { $0 == "/" })
            )

            do {
                let data = try Data(contentsOf: fileURL)
                let dicomFile = try DICOMFile.read(from: data, force: force)

                // All anonymization processing — profile removals, per-tag defaults
                // (PatientName→ANONYMOUS, PatientID→hash), custom --remove/--replace,
                // --keep, date shifting, UID regeneration, and PHI scanning — is
                // delegated to the shared DICOMKit engine.
                let anonFile: DICOMFile
                let anonResult: AnonymizationResult
                if isPS315 {
                    (anonFile, anonResult) = try StudioAnonPS315.deidentify(
                        dicomFile, anonymizer: anonymizer, options: ps315Options,
                        customActions: Self.engineCustomActions(removeTags: removeTags, replacePairs: replacePairs),
                        allowBurnedInPHI: allowBurnedInPHI, inputURL: fileURL)
                    reports.append((fileURL.path, AnonCLI.attributeActions(
                        before: dicomFile.dataSet, after: anonFile.dataSet, options: ps315Options)))
                } else {
                    (anonFile, anonResult) = try anonymizer.anonymize(file: dicomFile, filePath: fileURL.path)
                }
                let changed = anonResult.changedTags.map { $0.description }
                warnings.append(contentsOf: anonResult.warnings)
                modifiedTagNames.append(contentsOf: changed)

                if !dryRun {
                    // The single-file/no-output/non-dry-run case is rejected up front
                    // (see the guard above) — effectiveOutputPath is only empty here for
                    // a directory run, and destURL never falls back to overwriting the
                    // input file in place.
                    let destURL: URL?
                    if isDir.boolValue {
                        let dirDest = URL(fileURLWithPath: effectiveOutputPath).appendingPathComponent(relativePath)
                        try FileManager.default.createDirectory(at: dirDest.deletingLastPathComponent(), withIntermediateDirectories: true)
                        destURL = dirDest
                    } else {
                        destURL = effectiveOutputPath.isEmpty ? nil : URL(fileURLWithPath: effectiveOutputPath)
                    }
                    if let destURL {
                        // Backup lands next to the OUTPUT file (`<output>.backup`),
                        // matching the CLI — and only when a write actually happens.
                        if backup {
                            let backupURL = destURL.appendingPathExtension("backup")
                            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
                        }
                        // PS3.10 2026a Table 7.1-1: (0002,0003) follows the (0008,0018) that
                        // Table E.1-1 replaces (U) — as dicom-anon writes every output file.
                        let outData = try (isPS315 ? AnonCLI.syncingMediaStorageSOPInstanceUID(anonFile) : anonFile).write()
                        // Sandbox/TCC-resilient write: the earlier resolveWritableOutput uses POSIX
                        // checks that miss TCC, so retry at write time and fall back to ~/Downloads.
                        let wr = try OutputAccess.write(outData, toPath: destURL.path, scopedURL: nil, subfolder: "Anonymized")
                        if let note = wr.note { warnings.append(note) }
                    }
                }

                successful += 1
                // CLI parity: dicom-anon emits per-file verbose lines only in
                // directory mode ("✓ <relative path>"); single files get no per-file line.
                if verbose && isDir.boolValue {
                    output += AnonConsole.fileSuccessLine(relativePath: relativePath) + "\n"
                }

            } catch {
                // CLI parity: a single-file failure propagates out of dicom-anon's run()
                // as a fatal error (no summary); directory mode records the failure with
                // the bare error message as the warning and continues.
                guard isDir.boolValue else {
                    return (output + "Error: \(error.localizedDescription)\n", 1)
                }
                failed += 1
                warnings.append(error.localizedDescription)
                if verbose {
                    output += AnonConsole.fileFailureLine(relativePath: relativePath, message: error.localizedDescription) + "\n"
                }
            }
        }

        // Write audit log via the SHARED Anonymizer (the exact detailed per-tag log the
        // dicom-anon CLI writes), not a generic summary — so the app and CLI audit files
        // are byte-identical (timestamps aside). Like the CLI, the log is written even
        // under --dry-run: dry-run auditing is a primary use case.
        var auditNote = ""
        if !auditLogPath.isEmpty {
            if isPS315 {
                // The PS3.15 engine keeps no change log of its own (dicom-anon's ps315 branch).
                let text = StudioAnonPS315.auditLogText(
                    options: ps315Options, cleanRecognizableVisualFeatures: false, reports: reports)
                try? text.write(to: URL(fileURLWithPath: auditLogPath), atomically: true, encoding: .utf8)
            } else {
                try? anonymizer.writeAuditLog(to: URL(fileURLWithPath: auditLogPath))
            }
            if verbose { auditNote = AnonConsole.auditLogLine(path: auditLogPath) + "\n" }
        }

        let summary = AnonConsole.summary(
            totalFiles: totalFiles,
            successful: successful,
            failed: failed,
            dryRun: dryRun,
            warnings: warnings,
            modifiedTags: Set(modifiedTagNames),
            verbose: verbose
        )
        // CLI exit rule (dicom-anon main.swift): any failed file → exit 1.
        return (output + summary + auditNote, failed > 0 ? 1 : 0)
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
    static func resolveWritableOutput(
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

    private static func parseTag(_ string: String) -> Tag? {
        // Shared parser (hex + keyword map) — same code path as the dicom-anon CLI.
        DICOMKit.Anonymizer.parseFlexibleTag(string)
    }

    // MARK: - Engine mapping (UI profile + flag strings -> shared DICOMKit engine)

    /// Maps the app's UI ``AnonymizationProfile`` onto the shared engine profile.
    /// HIPAA Safe Harbor maps to the legacy basic list (the CLI's `legacy-basic`, matching `cliFlag`);
    /// Custom uses the explicitly listed `--remove` tags as its removal set.
    /// `.ps315` bypasses the legacy engine (`StudioAnonPS315`); like dicom-anon's parseProfile, the
    /// value only builds the shared Anonymizer instance.
    private static func engineProfile(_ profile: AnonymizationProfile, removeTags: [String]) -> DICOMKit.AnonymizationProfile {
        switch profile {
        case .basic, .hipaaeSafeHarbor, .ps315: return .basic
        case .clinicalTrial:            return .clinicalTrial
        case .research:                 return .research
        case .custom:                   return .custom(removeTags.compactMap { parseTag($0) })
        }
    }

    /// Builds the engine's per-tag custom actions from the `--remove` / `--replace`
    /// flag lists (matching the CLI's `parseCustomActions`).
    private static func engineCustomActions(removeTags: [String], replacePairs: [String]) -> [Tag: DICOMKit.AnonymizationAction] {
        var actions: [Tag: DICOMKit.AnonymizationAction] = [:]
        for spec in removeTags {
            if let tag = parseTag(spec) { actions[tag] = .remove }
        }
        for pair in replacePairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, let tag = parseTag(String(parts[0])) {
                actions[tag] = .replaceWithDummy(String(parts[1]))
            }
        }
        return actions
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
