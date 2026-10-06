// DICOMwebService.swift
// DICOMStudio
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (locked display state for profiles, jobs, workitems and statistics; the UPS state it stores is validated by DICOMwebViewModel against PS3.4 2026a Table CC.1.1-2)
//
// DICOM Studio — Thread-safe service for DICOMweb Integration Hub display state management
// Reference: DICOM PS3.18 (Web Services)

import Foundation

/// Thread-safe service managing the display state for the DICOMweb Integration Hub.
///
/// Manages server profiles, QIDO-RS query state, WADO-RS retrieve jobs,
/// STOW-RS upload jobs, UPS-RS workitems and subscriptions, and performance stats.
public final class DICOMwebService: @unchecked Sendable {

    // MARK: - Lock

    private let lock = NSLock()

    // MARK: - Server Profiles

    private var _serverProfiles: [DICOMwebServerProfile] = []

    // MARK: - QIDO-RS State

    private var _qidoQueryParams: QIDOQueryParams = QIDOQueryParams()
    private var _qidoResults: [QIDOResultItem] = []
    private var _qidoSelectedResultID: UUID? = nil
    private var _savedQueryTemplates: [String: QIDOQueryParams] = [:]

    // MARK: - WADO-RS State

    private var _wadoJobs: [WADORetrieveJob] = []

    // MARK: - STOW-RS State

    private var _stowJobs: [STOWUploadJob] = []

    // MARK: - UPS-RS State

    private var _upsWorkitems: [UPSWorkitem] = []
    private var _upsSubscriptions: [UPSEventSubscription] = []

    // MARK: - Performance Stats

    private var _performanceStats: DICOMwebPerformanceStats = DICOMwebPerformanceStats()
    private var _performanceHistory: [DICOMwebPerformanceStats] = []

    // MARK: - Init

    public init() {}

    // MARK: - Server Profiles

    /// Returns all server profiles.
    public func getServerProfiles() -> [DICOMwebServerProfile] {
        lock.withLock { _serverProfiles }
    }

    /// Adds a server profile. If `isDefault` is true, clears default on all others.
    public func addServerProfile(_ profile: DICOMwebServerProfile) {
        lock.withLock {
            if profile.isDefault {
                _serverProfiles = _serverProfiles.map {
                    var copy = $0; copy.isDefault = false; return copy
                }
            }
            _serverProfiles.append(profile)
        }
    }

    /// Updates an existing server profile by ID.
    public func updateServerProfile(_ profile: DICOMwebServerProfile) {
        lock.withLock {
            guard let idx = _serverProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
            if profile.isDefault {
                _serverProfiles = _serverProfiles.enumerated().map { i, p in
                    var copy = p; copy.isDefault = (i == idx); return copy
                }
            }
            _serverProfiles[idx] = profile
        }
    }

    /// Removes a server profile by ID.
    public func removeServerProfile(id: UUID) {
        lock.withLock {
            _serverProfiles.removeAll { $0.id == id }
        }
    }

    /// Makes the profile with the given ID the default, clearing default on all others.
    public func setDefaultProfile(id: UUID) {
        lock.withLock {
            _serverProfiles = _serverProfiles.map {
                var copy = $0; copy.isDefault = ($0.id == id); return copy
            }
        }
    }

    /// Returns the default server profile, if any.
    public func defaultProfile() -> DICOMwebServerProfile? {
        lock.withLock { _serverProfiles.first { $0.isDefault } }
    }

    /// Returns the server profile with the given ID, if any.
    public func profile(for id: UUID) -> DICOMwebServerProfile? {
        lock.withLock { _serverProfiles.first { $0.id == id } }
    }

    /// Updates the connection status and last error message on the profile with the given ID.
    public func updateConnectionStatus(_ status: DICOMwebConnectionStatus, error: String?, for id: UUID) {
        lock.withLock {
            guard let idx = _serverProfiles.firstIndex(where: { $0.id == id }) else { return }
            _serverProfiles[idx].connectionStatus = status
            _serverProfiles[idx].lastConnectionError = error
        }
    }

    // MARK: - QIDO-RS State

    /// Returns the current QIDO-RS query parameters.
    public func getQIDOQueryParams() -> QIDOQueryParams {
        lock.withLock { _qidoQueryParams }
    }

    /// Sets the QIDO-RS query parameters.
    public func setQIDOQueryParams(_ params: QIDOQueryParams) {
        lock.withLock { _qidoQueryParams = params }
    }

    /// Returns the current QIDO-RS query results.
    public func getQIDOResults() -> [QIDOResultItem] {
        lock.withLock { _qidoResults }
    }

    /// Replaces the QIDO-RS query results.
    public func setQIDOResults(_ results: [QIDOResultItem]) {
        lock.withLock { _qidoResults = results }
    }

    /// Clears all QIDO-RS query results.
    public func clearQIDOResults() {
        lock.withLock { _qidoResults.removeAll() }
    }

    /// Returns the selected QIDO result ID.
    public func getQIDOSelectedResultID() -> UUID? {
        lock.withLock { _qidoSelectedResultID }
    }

    /// Sets the selected QIDO result ID.
    public func setQIDOSelectedResultID(_ id: UUID?) {
        lock.withLock { _qidoSelectedResultID = id }
    }

    /// Returns all saved query templates.
    public func getSavedQueryTemplates() -> [String: QIDOQueryParams] {
        lock.withLock { _savedQueryTemplates }
    }

    /// Saves a named query template.
    public func saveQueryTemplate(name: String, params: QIDOQueryParams) {
        lock.withLock { _savedQueryTemplates[name] = params }
    }

    /// Removes a saved query template by name.
    public func removeQueryTemplate(name: String) {
        lock.withLock { _ = _savedQueryTemplates.removeValue(forKey: name) }
    }

    // MARK: - WADO-RS State

    /// Returns all WADO-RS retrieve jobs.
    public func getWADOJobs() -> [WADORetrieveJob] {
        lock.withLock { _wadoJobs }
    }

    /// Adds a WADO-RS retrieve job.
    public func addWADOJob(_ job: WADORetrieveJob) {
        lock.withLock { _wadoJobs.append(job) }
    }

    /// Updates a WADO-RS retrieve job (matched by ID).
    public func updateWADOJob(_ job: WADORetrieveJob) {
        lock.withLock {
            guard let idx = _wadoJobs.firstIndex(where: { $0.id == job.id }) else { return }
            _wadoJobs[idx] = job
        }
    }

    /// Removes a WADO-RS retrieve job by ID.
    public func removeWADOJob(id: UUID) {
        lock.withLock { _wadoJobs.removeAll { $0.id == id } }
    }

    /// Removes all WADO-RS jobs with a terminal status.
    public func clearCompletedWADOJobs() {
        lock.withLock { _wadoJobs.removeAll { $0.status.isTerminal } }
    }

    /// Returns the WADO-RS job with the given ID, if any.
    public func wadoJob(for id: UUID) -> WADORetrieveJob? {
        lock.withLock { _wadoJobs.first { $0.id == id } }
    }

    // MARK: - STOW-RS State

    /// Returns all STOW-RS upload jobs.
    public func getSTOWJobs() -> [STOWUploadJob] {
        lock.withLock { _stowJobs }
    }

    /// Adds a STOW-RS upload job.
    public func addSTOWJob(_ job: STOWUploadJob) {
        lock.withLock { _stowJobs.append(job) }
    }

    /// Updates a STOW-RS upload job (matched by ID).
    public func updateSTOWJob(_ job: STOWUploadJob) {
        lock.withLock {
            guard let idx = _stowJobs.firstIndex(where: { $0.id == job.id }) else { return }
            _stowJobs[idx] = job
        }
    }

    /// Removes a STOW-RS upload job by ID.
    public func removeSTOWJob(id: UUID) {
        lock.withLock { _stowJobs.removeAll { $0.id == id } }
    }

    /// Removes all STOW-RS jobs with a terminal status.
    public func clearCompletedSTOWJobs() {
        lock.withLock { _stowJobs.removeAll { $0.status.isTerminal } }
    }

    /// Returns the STOW-RS job with the given ID, if any.
    public func stowJob(for id: UUID) -> STOWUploadJob? {
        lock.withLock { _stowJobs.first { $0.id == id } }
    }

    // MARK: - UPS-RS State

    /// Returns all UPS-RS workitems.
    public func getUPSWorkitems() -> [UPSWorkitem] {
        lock.withLock { _upsWorkitems }
    }

    /// Replaces all UPS-RS workitems.
    public func setUPSWorkitems(_ items: [UPSWorkitem]) {
        lock.withLock { _upsWorkitems = items }
    }

    /// Adds a UPS-RS workitem.
    public func addUPSWorkitem(_ item: UPSWorkitem) {
        lock.withLock { _upsWorkitems.append(item) }
    }

    /// Updates a UPS-RS workitem (matched by ID).
    public func updateUPSWorkitem(_ item: UPSWorkitem) {
        lock.withLock {
            guard let idx = _upsWorkitems.firstIndex(where: { $0.id == item.id }) else { return }
            _upsWorkitems[idx] = item
        }
    }

    /// Updates the state of the UPS-RS workitem with the given ID.
    public func updateUPSWorkitemState(_ state: WebUPSState, for id: UUID) {
        lock.withLock {
            guard let idx = _upsWorkitems.firstIndex(where: { $0.id == id }) else { return }
            _upsWorkitems[idx].state = state
        }
    }

    /// Returns all UPS-RS event subscriptions.
    public func getUPSSubscriptions() -> [UPSEventSubscription] {
        lock.withLock { _upsSubscriptions }
    }

    /// Adds a UPS-RS event subscription.
    public func addUPSSubscription(_ sub: UPSEventSubscription) {
        lock.withLock { _upsSubscriptions.append(sub) }
    }

    /// Removes a UPS-RS event subscription by ID.
    public func removeUPSSubscription(id: UUID) {
        lock.withLock { _upsSubscriptions.removeAll { $0.id == id } }
    }

    /// Marks a UPS-RS event subscription as inactive.
    public func deactivateUPSSubscription(id: UUID) {
        lock.withLock {
            guard let idx = _upsSubscriptions.firstIndex(where: { $0.id == id }) else { return }
            _upsSubscriptions[idx].isActive = false
        }
    }

    // MARK: - Performance Stats

    /// Returns the latest performance stats snapshot.
    public func getPerformanceStats() -> DICOMwebPerformanceStats {
        lock.withLock { _performanceStats }
    }

    /// Updates the current performance stats and appends to history (max 100 entries).
    public func updatePerformanceStats(_ stats: DICOMwebPerformanceStats) {
        lock.withLock {
            _performanceHistory.append(stats)
            if _performanceHistory.count > 100 {
                _performanceHistory.removeFirst(_performanceHistory.count - 100)
            }
            _performanceStats = stats
        }
    }

    /// Returns the performance stats history (up to 100 snapshots).
    public func getPerformanceHistory() -> [DICOMwebPerformanceStats] {
        lock.withLock { _performanceHistory }
    }

    /// Resets the current performance stats to defaults and clears history.
    public func resetPerformanceStats() {
        lock.withLock {
            _performanceStats = DICOMwebPerformanceStats()
            _performanceHistory.removeAll()
        }
    }
}
