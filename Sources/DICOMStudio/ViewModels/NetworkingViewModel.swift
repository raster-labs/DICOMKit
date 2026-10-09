// NetworkingViewModel.swift
// DICOMStudio
//
// DICOM Studio — ViewModel for the DICOM Networking Hub (Milestone 9)
// Reference: DICOM PS3.4, PS3.7, PS3.8, PS3.15
// NEMA-verified: 2026a, checked 2026-10-06 — carries no DICOM-standard data of its own: the print job's
// Priority, Medium Type and Film Size are DICOMNetwork's enums (raw values the PS3.3 2026a Table C.13-1 / C.13-3
// terms; the Studio duplicates and the case-by-case mapping are gone, P-STUDIO-PRINT-ENUMS) and the Film Layout is handed to DICOMPrintService as a
// PrintLayout (Image Display Format STANDARD\C,R, Table C.13-3), which this panel used to drop; C-ECHO goes
// through DICOMVerificationService. C-FIND, C-MOVE/C-GET, C-STORE, MWL and MPPS here are display state
// loaded by the caller — no DIMSE status is produced or worded in this file.

import Foundation
import Observation
import DICOMKit
import DICOMNetwork

/// Injectable C-ECHO boundary. Production uses DICOMNetwork; deterministic
/// tests can supply a closed local result without opening a socket.
public typealias NetworkingEchoOperation = @Sendable (
    _ host: String,
    _ port: UInt16,
    _ callingAE: String,
    _ calledAE: String,
    _ timeout: TimeInterval
) async throws -> VerificationResult

/// ViewModel for the DICOM Networking Hub, managing state for all nine networking
/// sections: server configuration, C-ECHO, C-FIND, C-MOVE/GET, C-STORE, MWL,
/// MPPS, Print Management, and Network Monitoring.
///
/// Requires macOS 14+ / iOS 17+ for the `@Observable` macro.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@MainActor
@Observable
public final class NetworkingViewModel {

    // MARK: - Dependencies

    private let service: NetworkingService
    private let echoOperation: NetworkingEchoOperation

    // MARK: - Navigation

    /// Currently active networking tab.
    public var activeTab: NetworkingTab = .serverConfig
    /// Whether an operation is in progress.
    public var isLoading: Bool = false
    /// Error message to display, if any.
    public var errorMessage: String? = nil

    // MARK: - 9.1 Server Configuration

    /// All configured server profiles.
    public var serverProfiles: [PACSServerProfile] = []
    /// Currently selected server profile ID (for editing/testing).
    public var selectedServerProfileID: UUID? = nil
    /// Whether the add-server sheet is showing.
    public var isAddServerSheetPresented: Bool = false
    /// Whether the edit-server sheet is showing.
    public var isEditServerSheetPresented: Bool = false

    // MARK: - 9.2 C-ECHO

    /// Echo history (most recent first).
    public var echoHistory: [EchoResult] = []
    /// Whether a batch echo to all servers is in progress.
    public var isBatchEchoInProgress: Bool = false
    /// Number of servers tested so far in a batch echo.
    public var batchEchoProgress: Int = 0

    // MARK: - 9.3 C-FIND

    /// Current query filter.
    public var queryFilter: QueryFilter = QueryFilter()
    /// Query results.
    public var queryResults: [QueryResultItem] = []
    /// Whether a query is running.
    public var isQueryRunning: Bool = false
    /// Saved query templates (name → filter).
    public var savedQueryFilters: [String: QueryFilter] = [:]
    /// Currently selected query result ID for drill-down.
    public var selectedQueryResultID: UUID? = nil

    // MARK: - 9.4 C-MOVE / C-GET

    /// Transfer queue items.
    public var transferQueue: [TransferItem] = []
    /// Bandwidth limit configuration.
    public var bandwidthLimit: BandwidthLimit = BandwidthLimit()
    /// Currently selected transfer item ID.
    public var selectedTransferItemID: UUID? = nil

    // MARK: - 9.5 C-STORE

    /// Send queue items.
    public var sendQueue: [SendItem] = []
    /// Retry configuration for sends.
    public var sendRetryConfig: SendRetryConfig = .default
    /// Pre-send validation level.
    public var validationLevel: ValidationLevel = .standard
    /// Circuit breaker states keyed by server profile ID.
    public var circuitBreakerStates: [UUID: CircuitBreakerDisplayState] = [:]
    /// Whether the retry config sheet is showing.
    public var isRetryConfigSheetPresented: Bool = false

    // MARK: - 9.6 MWL

    /// Modality Worklist items.
    public var mwlItems: [MWLWorklistItem] = []
    /// MWL filter.
    public var mwlFilter: MWLFilter = MWLFilter()
    /// Whether a MWL query is running.
    public var isMWLQueryRunning: Bool = false
    /// Selected MWL item for auto-populate.
    public var selectedMWLItemID: UUID? = nil

    // MARK: - 9.7 MPPS

    /// All MPPS items.
    public var mppsItems: [MPPSItem] = []
    /// Currently selected MPPS item ID.
    public var selectedMPPSItemID: UUID? = nil
    /// Whether the new-MPPS sheet is presenting.
    public var isCreateMPPSSheetPresented: Bool = false

    // MARK: - 9.8 Print Management

    /// All print jobs.
    public var printJobs: [PrintJob] = []
    /// Currently selected print job ID.
    public var selectedPrintJobID: UUID? = nil
    /// Whether the new-print-job sheet is presenting.
    public var isNewPrintJobSheetPresented: Bool = false
    /// Detailed log for the last print job execution.
    public var printExecutionLog: String = ""

    // MARK: - 9.9 Monitoring

    /// Latest monitoring statistics snapshot.
    public var monitoringStats: NetworkMonitoringStats = NetworkMonitoringStats()
    /// Audit log entries.
    public var auditLog: [AuditLogEntry] = []
    /// Audit log search query.
    public var auditLogSearchQuery: String = ""
    /// Network error items.
    public var networkErrors: [NetworkErrorItem] = []
    /// Whether monitoring is active.
    public var isMonitoringActive: Bool = false

    // MARK: - Init

    public init(
        service: NetworkingService = NetworkingService(),
        echoOperation: NetworkingEchoOperation? = nil
    ) {
        self.service = service
        // Do not use an escaping async closure as a default argument here. Swift
        // may allocate default-argument closures in the creating task's local
        // allocator, then trap if the stored closure is released by another task.
        self.echoOperation = echoOperation ?? Self.performNetworkEcho
        loadAllState()
    }

    private static func performNetworkEcho(
        host: String,
        port: UInt16,
        callingAE: String,
        calledAE: String,
        timeout: TimeInterval
    ) async throws -> VerificationResult {
        try await DICOMVerificationService.echo(
            host: host,
            port: port,
            callingAE: callingAE,
            calledAE: calledAE,
            timeout: timeout
        )
    }

    // MARK: - Load All State

    private func loadAllState() {
        serverProfiles       = service.getServerProfiles()
        echoHistory          = service.getEchoHistory()
        queryFilter          = service.getQueryFilter()
        queryResults         = service.getQueryResults()
        savedQueryFilters    = service.getSavedQueryFilters()
        transferQueue        = service.getTransferQueue()
        bandwidthLimit       = service.getBandwidthLimit()
        sendQueue            = service.getSendQueue()
        sendRetryConfig      = service.getSendRetryConfig()
        validationLevel      = service.getValidationLevel()
        mwlItems             = service.getMWLItems()
        mwlFilter            = service.getMWLFilter()
        mppsItems            = service.getMPPSItems()
        printJobs            = service.getPrintJobs()
        monitoringStats      = service.getMonitoringStats()
        auditLog             = service.getAuditLog()
        networkErrors        = service.getNetworkErrors()
    }

    // MARK: - 9.1 Server Config Operations

    /// Adds a new server profile.
    public func addServerProfile(_ profile: PACSServerProfile) {
        service.addServerProfile(profile)
        serverProfiles = service.getServerProfiles()
    }

    /// Updates an existing server profile.
    public func updateServerProfile(_ profile: PACSServerProfile) {
        service.updateServerProfile(profile)
        serverProfiles = service.getServerProfiles()
    }

    /// Removes a server profile.
    public func removeServerProfile(id: UUID) {
        service.removeServerProfile(id: id)
        serverProfiles = service.getServerProfiles()
        if selectedServerProfileID == id { selectedServerProfileID = nil }
    }

    /// Returns the currently selected server profile, if any.
    public var selectedServerProfile: PACSServerProfile? {
        guard let id = selectedServerProfileID else { return nil }
        return serverProfiles.first { $0.id == id }
    }

    /// Returns validation errors for a server profile.
    public func validationErrors(for profile: PACSServerProfile) -> [String] {
        ServerProfileValidation.validate(profile)
    }

    // MARK: - 9.2 C-ECHO Operations

    /// Performs a real C-ECHO verification against the given server profile
    /// using DICOMNetwork's VerificationService.
    public func performEcho(profileID: UUID) async {
        guard let profile = serverProfiles.first(where: { $0.id == profileID }) else { return }
        service.setServerStatus(profileID: profileID, status: .testing)
        serverProfiles = service.getServerProfiles()

        let result: EchoResult
        do {
            let verificationResult = try await echoOperation(
                profile.host,
                profile.port,
                profile.localAETitle,
                profile.remoteAETitle,
                profile.timeoutSeconds
            )
            result = EchoResult(
                serverProfileID: profileID,
                serverName: profile.name,
                success: verificationResult.success,
                latencyMs: verificationResult.roundTripTime * 1000
            )
        } catch {
            result = EchoResult(
                serverProfileID: profileID,
                serverName: profile.name,
                success: false,
                errorMessage: error.localizedDescription
            )
        }
        service.recordEchoResult(result)
        echoHistory  = service.getEchoHistory()
        serverProfiles = service.getServerProfiles()
        auditLog     = service.getAuditLog()
    }

    /// Performs a batch echo to all configured servers.
    public func performBatchEcho() async {
        isBatchEchoInProgress = true
        batchEchoProgress = 0
        for profile in serverProfiles {
            await performEcho(profileID: profile.id)
            batchEchoProgress += 1
        }
        isBatchEchoInProgress = false
    }

    /// Clears the echo history.
    public func clearEchoHistory() {
        service.clearEchoHistory()
        echoHistory = service.getEchoHistory()
    }

    // MARK: - 9.3 C-FIND Operations

    /// Updates the query filter.
    public func updateQueryFilter(_ filter: QueryFilter) {
        queryFilter = filter
        service.setQueryFilter(filter)
    }

    /// Loads simulated query results into the view model.
    public func loadQueryResults(_ results: [QueryResultItem]) {
        service.setQueryResults(results)
        queryResults = service.getQueryResults()
        auditLog     = service.getAuditLog()
    }

    /// Clears all query results.
    public func clearQueryResults() {
        service.clearQueryResults()
        queryResults = []
    }

    /// Saves the current query filter under the given name.
    public func saveQueryFilter(name: String) {
        service.saveQueryFilter(name: name, filter: queryFilter)
        savedQueryFilters = service.getSavedQueryFilters()
    }

    /// Loads a saved query filter by name.
    public func loadSavedQueryFilter(name: String) {
        guard let filter = savedQueryFilters[name] else { return }
        updateQueryFilter(filter)
    }

    /// Removes a saved query filter template by name.
    public func removeSavedQueryFilter(name: String) {
        service.removeSavedQueryFilter(name: name)
        savedQueryFilters = service.getSavedQueryFilters()
    }

    /// Returns a summary string for the current query filter.
    public var queryFilterSummary: String {
        QueryFilterHelpers.summary(for: queryFilter)
    }

    // MARK: - 9.4 C-MOVE/GET Operations

    /// Enqueues a transfer item in the download queue.
    public func enqueueTransfer(_ item: TransferItem) {
        service.enqueueTransfer(item)
        transferQueue = service.getTransferQueue()
    }

    /// Updates a transfer item's state.
    public func updateTransferItem(_ item: TransferItem) {
        service.updateTransferItem(item)
        transferQueue = service.getTransferQueue()
    }

    /// Removes a transfer item.
    public func removeTransferItem(id: UUID) {
        service.removeTransferItem(id: id)
        transferQueue = service.getTransferQueue()
        if selectedTransferItemID == id { selectedTransferItemID = nil }
    }

    /// Sets the bandwidth limit.
    public func updateBandwidthLimit(_ limit: BandwidthLimit) {
        bandwidthLimit = limit
        service.setBandwidthLimit(limit)
    }

    /// Items sorted by priority (high first), then queued date.
    public var prioritizedTransferQueue: [TransferItem] {
        transferQueue.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.queuedDate < $1.queuedDate
        }
    }

    // MARK: - 9.5 C-STORE Operations

    /// Enqueues a send item.
    public func enqueueSendItem(_ item: SendItem) {
        service.enqueueSendItem(item)
        sendQueue = service.getSendQueue()
    }

    /// Updates a send item's state.
    public func updateSendItem(_ item: SendItem) {
        service.updateSendItem(item)
        sendQueue = service.getSendQueue()
    }

    /// Removes a send item.
    public func removeSendItem(id: UUID) {
        service.removeSendItem(id: id)
        sendQueue = service.getSendQueue()
    }

    /// Updates the retry configuration.
    public func updateSendRetryConfig(_ config: SendRetryConfig) {
        sendRetryConfig = config
        service.setSendRetryConfig(config)
    }

    /// Updates the pre-send validation level.
    public func updateValidationLevel(_ level: ValidationLevel) {
        validationLevel = level
        service.setValidationLevel(level)
    }

    /// Returns the circuit breaker state for a given server profile.
    public func circuitBreakerState(for profileID: UUID) -> CircuitBreakerDisplayState {
        service.getCircuitBreakerState(profileID: profileID)
    }

    /// Updates the circuit breaker state for a given server profile.
    public func updateCircuitBreakerState(_ state: CircuitBreakerDisplayState, profileID: UUID) {
        service.setCircuitBreakerState(state, profileID: profileID)
        circuitBreakerStates[profileID] = state
    }

    // MARK: - 9.6 MWL Operations

    /// Loads MWL worklist items (simulated query result).
    public func loadMWLItems(_ items: [MWLWorklistItem]) {
        service.setMWLItems(items)
        mwlItems = service.getMWLItems()
        auditLog = service.getAuditLog()
    }

    /// Updates the MWL filter.
    public func updateMWLFilter(_ filter: MWLFilter) {
        mwlFilter = filter
        service.setMWLFilter(filter)
    }

    /// Returns filtered MWL items based on the current filter.
    public var filteredMWLItems: [MWLWorklistItem] {
        mwlItems.filter { item in
            let dateMatch = mwlFilter.date.isEmpty
                || item.scheduledProcedureStepStartDate == mwlFilter.date
            let modMatch  = mwlFilter.modality.isEmpty
                || item.modality.uppercased() == mwlFilter.modality.uppercased()
            let aeMatch   = mwlFilter.stationAETitle.isEmpty
                || item.scheduledStationAETitle.uppercased() == mwlFilter.stationAETitle.uppercased()
            return dateMatch && modMatch && aeMatch
        }
    }

    /// Returns the selected MWL item, if any.
    public var selectedMWLItem: MWLWorklistItem? {
        guard let id = selectedMWLItemID else { return nil }
        return mwlItems.first { $0.id == id }
    }

    // MARK: - 9.7 MPPS Operations

    /// Creates a new MPPS procedure step (N-CREATE).
    public func createMPPS(_ item: MPPSItem) {
        service.createMPPS(item)
        mppsItems = service.getMPPSItems()
        auditLog  = service.getAuditLog()
    }

    /// Completes an MPPS item (N-SET to Completed).
    public func completeMPPS(id: UUID) {
        service.updateMPPSStatus(id: id, status: .completed, endDateTime: Date())
        mppsItems = service.getMPPSItems()
        auditLog  = service.getAuditLog()
    }

    /// Discontinues an MPPS item (N-SET to Discontinued).
    public func discontinueMPPS(id: UUID) {
        service.updateMPPSStatus(id: id, status: .discontinued, endDateTime: Date())
        mppsItems = service.getMPPSItems()
        auditLog  = service.getAuditLog()
    }

    /// Returns the currently selected MPPS item, if any.
    public var selectedMPPSItem: MPPSItem? {
        guard let id = selectedMPPSItemID else { return nil }
        return mppsItems.first { $0.id == id }
    }

    // MARK: - 9.8 Print Operations

    /// Adds a new print job.
    public func addPrintJob(_ job: PrintJob) {
        service.addPrintJob(job)
        printJobs = service.getPrintJobs()
        auditLog  = service.getAuditLog()
    }

    /// Updates an existing print job.
    public func updatePrintJob(_ job: PrintJob) {
        service.updatePrintJob(job)
        printJobs = service.getPrintJobs()
    }

    /// Removes a print job.
    public func removePrintJob(id: UUID) {
        service.removePrintJob(id: id)
        printJobs = service.getPrintJobs()
        if selectedPrintJobID == id { selectedPrintJobID = nil }
    }

    /// Returns the currently selected print job, if any.
    public var selectedPrintJob: PrintJob? {
        guard let id = selectedPrintJobID else { return nil }
        return printJobs.first { $0.id == id }
    }

    /// Executes a pending print job by sending images to the DICOM printer.
    ///
    /// This method:
    /// 1. Looks up the server profile for the print job
    /// 2. Reads and extracts pixel data from each DICOM file
    /// 3. Builds a `PrintConfiguration` and `PrintOptions`
    /// 4. Calls `DICOMPrintService.printImages()` to send to the printer
    /// 5. Updates the job status to `.completed` or `.failed`
    public func executePrintJob(id: UUID) async {
        printExecutionLog = ""
        func log(_ msg: String) {
            let ts = ISO8601DateFormatter().string(from: Date())
            printExecutionLog += "[\(ts)] \(msg)\n"
        }

        guard var job = printJobs.first(where: { $0.id == id }),
              job.status == .pending else {
            log("ERROR: Job not found or not in pending state")
            return
        }
        log("Starting print job: \(job.label) (id: \(job.id))")
        log("Images: \(job.imageFilePaths.count), Bookmarks: \(job.imageBookmarks.count)")

        guard let profile = serverProfiles.first(where: { $0.id == job.printerServerProfileID }) else {
            log("ERROR: Printer server profile not found (id: \(job.printerServerProfileID))")
            job.status = .failed
            job.errorMessage = "Printer server profile not found"
            job.completedDate = Date()
            service.updatePrintJob(job)
            printJobs = service.getPrintJobs()
            return
        }
        guard !job.imageFilePaths.isEmpty else {
            log("ERROR: No images selected for printing")
            job.status = .failed
            job.errorMessage = "No images selected for printing"
            job.completedDate = Date()
            service.updatePrintJob(job)
            printJobs = service.getPrintJobs()
            return
        }

        // Mark as printing
        log("Server: \(profile.name) @ \(profile.host):\(profile.port) (AE: \(profile.remoteAETitle))")
        job.status = .printing
        service.updatePrintJob(job)
        printJobs = service.getPrintJobs()

        // Resolve security-scoped bookmarks to regain sandbox access
        log("Resolving \(job.imageBookmarks.count) security-scoped bookmarks...")
        var resolvedURLs: [URL] = []
        for bookmark in job.imageBookmarks {
            var isStale = false
            #if os(macOS)
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            if url.startAccessingSecurityScopedResource() {
                resolvedURLs.append(url)
            }
            #else
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            resolvedURLs.append(url)
            #endif
        }
        // Fall back to plain paths if no bookmarks (e.g. non-sandboxed context)
        let fileURLs: [URL]
        if resolvedURLs.count == job.imageFilePaths.count {
            fileURLs = resolvedURLs
        } else if !resolvedURLs.isEmpty {
            fileURLs = resolvedURLs
        } else {
            fileURLs = job.imageFilePaths.map { URL(fileURLWithPath: $0) }
        }
        log("Resolved \(resolvedURLs.count) bookmark URLs, total file URLs: \(fileURLs.count)")

        defer {
            for url in resolvedURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Extract pixel data from each DICOM file
        log("Extracting pixel data from \(fileURLs.count) DICOM files...")
        var pixelDataArray: [Data] = []
        var imageDescriptors: [DICOMNetwork.PrintImageData] = []
        for url in fileURLs {
            do {
                let dicomFile = try DICOMFile.read(from: url)
                guard let pd = dicomFile.pixelData() else {
                    log("ERROR: No pixel data in \(url.lastPathComponent)")
                    job.status = .failed
                    job.errorMessage = "Failed to extract pixel data from: \(url.lastPathComponent)"
                    job.completedDate = Date()
                    service.updatePrintJob(job)
                    printJobs = service.getPrintJobs()
                    return
                }
                pixelDataArray.append(pd.data)
                let desc = pd.descriptor
                imageDescriptors.append(DICOMNetwork.PrintImageData(
                    pixelData: pd.data,
                    rows: UInt16(desc.rows),
                    columns: UInt16(desc.columns),
                    bitsAllocated: UInt16(desc.bitsAllocated),
                    bitsStored: UInt16(desc.bitsStored),
                    highBit: UInt16(desc.highBit),
                    samplesPerPixel: UInt16(desc.samplesPerPixel),
                    pixelRepresentation: desc.isSigned ? 1 : 0,
                    photometricInterpretation: desc.photometricInterpretation.rawValue
                ))
                log("  ✓ \(url.lastPathComponent): \(pd.data.count) bytes, \(desc.rows)×\(desc.columns), \(desc.bitsAllocated)-bit, \(desc.photometricInterpretation.rawValue)")
            } catch {
                log("ERROR: Failed to read \(url.lastPathComponent): \(error.localizedDescription)")
                job.status = .failed
                job.errorMessage = "Failed to read DICOM file \(url.lastPathComponent): \(error.localizedDescription)"
                job.completedDate = Date()
                service.updatePrintJob(job)
                printJobs = service.getPrintJobs()
                return
            }
        }

        // Build configuration from server profile
        log("Building print configuration...")
        log("  Host: \(profile.host):\(profile.port)")
        log("  Calling AE: \(profile.localAETitle), Called AE: \(profile.remoteAETitle)")
        log("  Copies: \(job.numberOfCopies), Priority: \(job.priority.rawValue), Medium: \(job.mediumType.rawValue), Film Size: \(job.filmSize.rawValue)")
        let printConfig = PrintConfiguration(
            host: profile.host,
            port: profile.port,
            callingAETitle: profile.localAETitle,
            calledAETitle: profile.remoteAETitle,
            timeout: profile.timeoutSeconds
        )

        // The job carries DICOMNetwork's Print Priority, Medium Type and Film Size
        // (P-STUDIO-PRINT-ENUMS): the PS3.3 Table C.13-1 / C.13-3 terms go to the wire as chosen.
        let printOptions = PrintOptions(
            numberOfCopies: job.numberOfCopies,
            priority: job.priority,
            filmSize: job.filmSize,
            mediumType: job.mediumType
        )

        // The layout the sheet showed is the Image Display Format (2010,0010)
        // the film box is created with — STANDARD\C,R (PS3.3 C.13.3, Table
        // C.13-3). Left out, the SCU chose its own grid and the preview's
        // "2×2, two films" promise was not what reached the printer.
        let networkLayout = PrintLayout(rows: job.filmLayout.rows, columns: job.filmLayout.columns)
        log("  Image Display Format: \(networkLayout.imageDisplayFormat)")

        // Send to printer
        log("Sending \(pixelDataArray.count) images to printer via DICOMPrintService.printImages()...")
        do {
            let result = try await DICOMPrintService.printImages(
                configuration: printConfig,
                images: pixelDataArray,
                options: printOptions,
                imageDescriptors: imageDescriptors,
                layout: networkLayout
            )
            if result.success {
                log("SUCCESS: Print completed")
                log("  Film Session UID: \(result.filmSessionUID ?? "N/A")")
                log("  Film Box UID: \(result.filmBoxUID ?? "N/A")")
                log("  Print Job UID: \(result.printJobUID ?? "N/A")")
                job.status = .completed
                job.completedDate = Date()
            } else {
                log("FAILED: Print service returned failure")
                log("  Status: \(result.status)")
                log("  Error: \(result.errorMessage ?? "none")")
                job.status = .failed
                job.errorMessage = result.errorMessage ?? "Print failed with status: \(result.status)"
                job.completedDate = Date()
            }
        } catch {
            log("EXCEPTION: \(error)")
            log("  Type: \(type(of: error))")
            log("  Description: \(error.localizedDescription)")
            job.status = .failed
            job.errorMessage = error.localizedDescription
            job.completedDate = Date()
        }

        service.updatePrintJob(job)
        printJobs = service.getPrintJobs()
        auditLog  = service.getAuditLog()
    }

    // MARK: - 9.9 Monitoring Operations

    /// Refreshes monitoring statistics from the service.
    public func refreshMonitoringStats(_ stats: NetworkMonitoringStats) {
        service.updateMonitoringStats(stats)
        monitoringStats = service.getMonitoringStats()
    }

    /// Returns audit log entries filtered by the current search query.
    public var filteredAuditLog: [AuditLogEntry] {
        guard !auditLogSearchQuery.isEmpty else { return auditLog }
        let q = auditLogSearchQuery.lowercased()
        return auditLog.filter {
            $0.eventType.displayName.lowercased().contains(q)
            || $0.remoteEntity.lowercased().contains(q)
            || $0.detail.lowercased().contains(q)
            || $0.outcome.displayName.lowercased().contains(q)
        }
    }

    /// Exports the full audit log as a CSV string.
    public func exportAuditLogCSV() -> String {
        AuditLogHelpers.csvExport(entries: auditLog)
    }

    /// Clears the audit log.
    public func clearAuditLog() {
        service.clearAuditLog()
        auditLog = service.getAuditLog()
    }

    /// Records a network error and refreshes the errors list.
    public func recordNetworkError(_ error: NetworkErrorItem) {
        service.recordNetworkError(error)
        networkErrors = service.getNetworkErrors()
    }

    /// Clears all network errors.
    public func clearNetworkErrors() {
        service.clearNetworkErrors()
        networkErrors = service.getNetworkErrors()
    }

    /// Returns a monitoring summary string.
    public var monitoringSummary: String {
        MonitoringHelpers.summary(monitoringStats)
    }
}
