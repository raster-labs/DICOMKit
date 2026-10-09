// NetworkingService.swift
// DICOMStudio
//
// DICOM Studio — Thread-safe service for DICOM Networking Hub display state management
// Reference: DICOM PS3.4 (Service Class Specifications)
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (locked display state: profiles, queues,
// MPPS and print job records, audit entries); the only literal is the fallback AE title DICOMSTUDIO, a valid
// PS3.5 Table 6.2-1 AE value (11 characters). Status values are the enums of NetworkingModel.swift.

import Foundation

/// Thread-safe service managing the display state for the DICOM Networking Hub.
///
/// Manages server profiles, echo history, query results, transfer queues,
/// send queues, MWL worklist items, MPPS items, print jobs, monitoring stats,
/// and the HIPAA audit log.
public final class NetworkingService: @unchecked Sendable {

    // MARK: - Lock

    private let lock = NSLock()

    // MARK: - Server Profiles

    private var _serverProfiles: [PACSServerProfile] = []

    // MARK: - Echo History

    private var _echoHistory: [EchoResult] = []

    // MARK: - Query State

    private var _queryFilter: QueryFilter = QueryFilter()
    private var _queryResults: [QueryResultItem] = []
    private var _savedQueryFilters: [String: QueryFilter] = [:]

    // MARK: - Transfer Queue (C-MOVE/C-GET)

    private var _transferQueue: [TransferItem] = []
    private var _bandwidthLimit: BandwidthLimit = BandwidthLimit()

    // MARK: - Send Queue (C-STORE)

    private var _sendQueue: [SendItem] = []
    private var _sendRetryConfig: SendRetryConfig = .default
    private var _validationLevel: ValidationLevel = .standard
    private var _circuitBreakerStates: [UUID: CircuitBreakerDisplayState] = [:]

    // MARK: - MWL State

    private var _mwlItems: [MWLWorklistItem] = []
    private var _mwlFilter: MWLFilter = MWLFilter()

    // MARK: - MPPS State

    private var _mppsItems: [MPPSItem] = []

    // MARK: - Print State

    private var _printJobs: [PrintJob] = []

    // MARK: - Monitoring

    private var _monitoringStats: NetworkMonitoringStats = NetworkMonitoringStats()
    private var _monitoringHistory: [NetworkMonitoringStats] = []
    private var _networkErrors: [NetworkErrorItem] = []

    // MARK: - Audit Log

    private var _auditLog: [AuditLogEntry] = []

    // MARK: - Persistence

    private let profileStorage: ServerProfileStorageService?

    // MARK: - Init

    public init(profileStorage: ServerProfileStorageService? = nil) {
        self.profileStorage = profileStorage
        if let saved = profileStorage?.load(), !saved.isEmpty {
            _serverProfiles = saved
        }
    }

    /// Persists current server profiles to disk.
    private func _persistProfiles() {
        try? profileStorage?.save(_serverProfiles)
    }

    // MARK: - Server Profiles

    /// Returns all server profiles.
    public func getServerProfiles() -> [PACSServerProfile] {
        lock.withLock { _serverProfiles }
    }

    /// Adds a server profile. If `isDefault` is true, clears default on all others.
    public func addServerProfile(_ profile: PACSServerProfile) {
        lock.withLock {
            if profile.isDefault {
                _serverProfiles = _serverProfiles.map {
                    var copy = $0; copy.isDefault = false; return copy
                }
            }
            _serverProfiles.append(profile)
            _persistProfiles()
        }
    }

    /// Updates an existing server profile by ID.
    public func updateServerProfile(_ profile: PACSServerProfile) {
        lock.withLock {
            guard let idx = _serverProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
            if profile.isDefault {
                _serverProfiles = _serverProfiles.enumerated().map { i, p in
                    var copy = p; copy.isDefault = (i == idx); return copy
                }
            }
            _serverProfiles[idx] = profile
            _persistProfiles()
        }
    }

    /// Removes a server profile by ID.
    public func removeServerProfile(id: UUID) {
        lock.withLock {
            _serverProfiles.removeAll { $0.id == id }
            _persistProfiles()
        }
    }

    /// Sets the status of a server profile.
    public func setServerStatus(profileID: UUID, status: ServerConnectionStatus) {
        lock.withLock {
            guard let idx = _serverProfiles.firstIndex(where: { $0.id == profileID }) else { return }
            _serverProfiles[idx].status = status
        }
    }

    /// Returns the default server profile, if any.
    public func defaultServerProfile() -> PACSServerProfile? {
        lock.withLock { _serverProfiles.first { $0.isDefault } }
    }

    // MARK: - Echo History

    /// Returns all echo results, newest first.
    public func getEchoHistory() -> [EchoResult] {
        lock.withLock { _echoHistory.sorted { $0.timestamp > $1.timestamp } }
    }

    /// Appends an echo result and updates the server profile's last echo date and status.
    public func recordEchoResult(_ result: EchoResult) {
        lock.withLock {
            _echoHistory.append(result)
            if let idx = _serverProfiles.firstIndex(where: { $0.id == result.serverProfileID }) {
                _serverProfiles[idx].status = result.success ? .online : .error
                if result.success { _serverProfiles[idx].lastEchoDate = result.timestamp }
            }
            _appendAuditEntry(
                eventType: .echo,
                outcome: result.success ? .success : .failure,
                remoteEntity: result.serverName,
                localAETitle: _serverProfiles.first { $0.id == result.serverProfileID }?.localAETitle ?? "DICOMSTUDIO",
                detail: result.success
                    ? "Latency \(Int(result.latencyMs ?? 0)) ms"
                    : (result.errorMessage ?? "Echo failed")
            )
        }
    }

    /// Clears the echo history.
    public func clearEchoHistory() {
        lock.withLock { _echoHistory.removeAll() }
    }

    // MARK: - Query State

    /// Returns the current query filter.
    public func getQueryFilter() -> QueryFilter {
        lock.withLock { _queryFilter }
    }

    /// Sets the query filter.
    public func setQueryFilter(_ filter: QueryFilter) {
        lock.withLock { _queryFilter = filter }
    }

    /// Returns current query results.
    public func getQueryResults() -> [QueryResultItem] {
        lock.withLock { _queryResults }
    }

    /// Replaces query results.
    public func setQueryResults(_ results: [QueryResultItem]) {
        lock.withLock { _queryResults = results }
    }

    /// Clears all query results.
    public func clearQueryResults() {
        lock.withLock { _queryResults.removeAll() }
    }

    /// Saves a named query filter template.
    public func saveQueryFilter(name: String, filter: QueryFilter) {
        lock.withLock { _savedQueryFilters[name] = filter }
    }

    /// Returns all saved query filter templates.
    public func getSavedQueryFilters() -> [String: QueryFilter] {
        lock.withLock { _savedQueryFilters }
    }

    /// Removes a saved query filter by name.
    public func removeSavedQueryFilter(name: String) {
        lock.withLock { _ = _savedQueryFilters.removeValue(forKey: name) }
    }

    // MARK: - Transfer Queue

    /// Returns the current transfer queue.
    public func getTransferQueue() -> [TransferItem] {
        lock.withLock { _transferQueue }
    }

    /// Enqueues a transfer item.
    public func enqueueTransfer(_ item: TransferItem) {
        lock.withLock { _transferQueue.append(item) }
    }

    /// Updates a transfer item (matched by ID).
    public func updateTransferItem(_ item: TransferItem) {
        lock.withLock {
            guard let idx = _transferQueue.firstIndex(where: { $0.id == item.id }) else { return }
            _transferQueue[idx] = item
        }
    }

    /// Removes a transfer item by ID.
    public func removeTransferItem(id: UUID) {
        lock.withLock { _transferQueue.removeAll { $0.id == id } }
    }

    /// Returns the bandwidth limit configuration.
    public func getBandwidthLimit() -> BandwidthLimit {
        lock.withLock { _bandwidthLimit }
    }

    /// Sets the bandwidth limit configuration.
    public func setBandwidthLimit(_ limit: BandwidthLimit) {
        lock.withLock { _bandwidthLimit = limit }
    }

    // MARK: - Send Queue

    /// Returns the current send queue.
    public func getSendQueue() -> [SendItem] {
        lock.withLock { _sendQueue }
    }

    /// Enqueues a send item.
    public func enqueueSendItem(_ item: SendItem) {
        lock.withLock { _sendQueue.append(item) }
    }

    /// Updates a send item (matched by ID).
    public func updateSendItem(_ item: SendItem) {
        lock.withLock {
            guard let idx = _sendQueue.firstIndex(where: { $0.id == item.id }) else { return }
            _sendQueue[idx] = item
        }
    }

    /// Removes a send item by ID.
    public func removeSendItem(id: UUID) {
        lock.withLock { _sendQueue.removeAll { $0.id == id } }
    }

    /// Returns the send retry configuration.
    public func getSendRetryConfig() -> SendRetryConfig {
        lock.withLock { _sendRetryConfig }
    }

    /// Sets the send retry configuration.
    public func setSendRetryConfig(_ config: SendRetryConfig) {
        lock.withLock { _sendRetryConfig = config }
    }

    /// Returns the pre-send validation level.
    public func getValidationLevel() -> ValidationLevel {
        lock.withLock { _validationLevel }
    }

    /// Sets the pre-send validation level.
    public func setValidationLevel(_ level: ValidationLevel) {
        lock.withLock { _validationLevel = level }
    }

    /// Returns the circuit breaker state for a server profile.
    public func getCircuitBreakerState(profileID: UUID) -> CircuitBreakerDisplayState {
        lock.withLock { _circuitBreakerStates[profileID] ?? .closed }
    }

    /// Sets the circuit breaker state for a server profile.
    public func setCircuitBreakerState(_ state: CircuitBreakerDisplayState, profileID: UUID) {
        lock.withLock { _circuitBreakerStates[profileID] = state }
    }

    // MARK: - MWL

    /// Returns the current MWL worklist items.
    public func getMWLItems() -> [MWLWorklistItem] {
        lock.withLock { _mwlItems }
    }

    /// Replaces the MWL worklist items.
    public func setMWLItems(_ items: [MWLWorklistItem]) {
        lock.withLock { _mwlItems = items }
    }

    /// Returns the MWL filter.
    public func getMWLFilter() -> MWLFilter {
        lock.withLock { _mwlFilter }
    }

    /// Sets the MWL filter.
    public func setMWLFilter(_ filter: MWLFilter) {
        lock.withLock { _mwlFilter = filter }
    }

    // MARK: - MPPS

    /// Returns all MPPS items.
    public func getMPPSItems() -> [MPPSItem] {
        lock.withLock { _mppsItems }
    }

    /// Creates a new MPPS item (N-CREATE).
    public func createMPPS(_ item: MPPSItem) {
        lock.withLock {
            _mppsItems.append(item)
            _appendAuditEntry(
                eventType: .mppsCreate,
                outcome: .success,
                remoteEntity: item.performedStationAETitle,
                localAETitle: item.performedStationAETitle,
                detail: "Created MPPS for \(item.patientName)"
            )
        }
    }

    /// Updates an MPPS item's status (N-SET) by ID.
    public func updateMPPSStatus(id: UUID, status: MPPSStatus, endDateTime: Date? = nil) {
        lock.withLock {
            guard let idx = _mppsItems.firstIndex(where: { $0.id == id }) else { return }
            _mppsItems[idx].status = status
            if let end = endDateTime { _mppsItems[idx].endDateTime = end }
            _appendAuditEntry(
                eventType: .mppsUpdate,
                outcome: .success,
                remoteEntity: _mppsItems[idx].performedStationAETitle,
                localAETitle: _mppsItems[idx].performedStationAETitle,
                detail: "MPPS status set to \(status.displayName)"
            )
        }
    }

    // MARK: - Print

    /// Returns all print jobs.
    public func getPrintJobs() -> [PrintJob] {
        lock.withLock { _printJobs }
    }

    /// Adds a print job.
    public func addPrintJob(_ job: PrintJob) {
        lock.withLock {
            _printJobs.append(job)
            _appendAuditEntry(
                eventType: .printJob,
                outcome: .success,
                remoteEntity: job.label,
                localAETitle: "DICOMSTUDIO",
                detail: "Print job created: \(job.label)"
            )
        }
    }

    /// Updates a print job (matched by ID).
    public func updatePrintJob(_ job: PrintJob) {
        lock.withLock {
            guard let idx = _printJobs.firstIndex(where: { $0.id == job.id }) else { return }
            _printJobs[idx] = job
        }
    }

    /// Removes a print job by ID.
    public func removePrintJob(id: UUID) {
        lock.withLock { _printJobs.removeAll { $0.id == id } }
    }

    // MARK: - Monitoring

    /// Returns the latest monitoring stats.
    public func getMonitoringStats() -> NetworkMonitoringStats {
        lock.withLock { _monitoringStats }
    }

    /// Updates the monitoring stats snapshot and appends to history.
    public func updateMonitoringStats(_ stats: NetworkMonitoringStats) {
        lock.withLock {
            _monitoringStats = stats
            _monitoringHistory.append(stats)
            // Keep last 300 data points.
            if _monitoringHistory.count > 300 {
                _monitoringHistory.removeFirst(_monitoringHistory.count - 300)
            }
        }
    }

    /// Returns the monitoring history (up to 300 snapshots).
    public func getMonitoringHistory() -> [NetworkMonitoringStats] {
        lock.withLock { _monitoringHistory }
    }

    /// Returns all network errors.
    public func getNetworkErrors() -> [NetworkErrorItem] {
        lock.withLock { _networkErrors }
    }

    /// Records a network error.
    public func recordNetworkError(_ error: NetworkErrorItem) {
        lock.withLock { _networkErrors.append(error) }
    }

    /// Clears all recorded network errors.
    public func clearNetworkErrors() {
        lock.withLock { _networkErrors.removeAll() }
    }

    // MARK: - Audit Log

    /// Returns all audit log entries, newest first.
    public func getAuditLog() -> [AuditLogEntry] {
        lock.withLock { _auditLog.sorted { $0.timestamp > $1.timestamp } }
    }

    /// Appends an audit log entry.
    public func appendAuditEntry(_ entry: AuditLogEntry) {
        lock.withLock { _auditLog.append(entry) }
    }

    /// Returns audit log entries matching the given event type.
    public func auditLogEntries(for eventType: AuditNetworkEventType) -> [AuditLogEntry] {
        lock.withLock { _auditLog.filter { $0.eventType == eventType } }
    }

    /// Returns audit log entries matching the given outcome.
    public func auditLogEntries(outcome: AuditEventOutcome) -> [AuditLogEntry] {
        lock.withLock { _auditLog.filter { $0.outcome == outcome } }
    }

    /// Clears the audit log.
    public func clearAuditLog() {
        lock.withLock { _auditLog.removeAll() }
    }

    // MARK: - Private Helpers

    /// Must be called while `lock` is held.
    private func _appendAuditEntry(
        eventType: AuditNetworkEventType,
        outcome: AuditEventOutcome,
        remoteEntity: String,
        localAETitle: String,
        detail: String
    ) {
        _auditLog.append(AuditLogEntry(
            eventType: eventType,
            outcome: outcome,
            remoteEntity: remoteEntity,
            localAETitle: localAETitle,
            detail: detail
        ))
    }
}
