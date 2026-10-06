// SecurityService.swift
// DICOMStudio
//
// DICOM Studio — Thread-safe service for Security & Privacy Center display state management
// Reference: DICOM PS3.15 (Security and System Management Profiles); HIPAA Security Rule §164.312 (law)
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (locked state store for certificates, server entries, anonymization jobs and rules, audit entries, sessions; defaults .compatible / .basic are app choices)

import Foundation

/// Thread-safe service managing the display state for the Security & Privacy Center.
///
/// Manages TLS certificates, server security entries, anonymization jobs,
/// audit log entries, and access control sessions.
public final class SecurityService: @unchecked Sendable {

    // MARK: - Lock

    private let lock = NSLock()

    // MARK: - 11.1 TLS Configuration State

    private var _globalTLSMode: SecurityTLSMode = .compatible
    private var _certificates: [SecurityCertificateEntry] = []
    private var _serverSecurityEntries: [SecurityServerEntry] = []

    // MARK: - 11.2 Anonymization State

    private var _anonymizationJobs: [AnonymizationJob] = []
    private var _phiDetectionResults: [PHIDetectionResult] = []
    private var _selectedProfile: AnonymizationProfile = .ps315  // PS3.15 Basic Profile (P-STUDIO-ANON-PS315)
    private var _customRules: [AnonymizationTagRule] = []

    // MARK: - 11.3 Audit Log State

    private var _auditEntries: [SecurityAuditEntry] = []
    private var _enabledHandlers: Set<SecurityAuditHandlerType> = [.console]
    private var _retentionPolicy: SecurityAuditRetentionPolicy = .days365

    // MARK: - 11.4 Access Control State

    private var _currentSession: AccessControlSession? = nil
    private var _breakGlassEvents: [BreakGlassEvent] = []

    // MARK: - Init

    public init() {}

    // MARK: - 11.1 TLS Configuration

    /// Returns the global TLS mode.
    public func getGlobalTLSMode() -> SecurityTLSMode {
        lock.withLock { _globalTLSMode }
    }

    /// Sets the global TLS mode.
    public func setGlobalTLSMode(_ mode: SecurityTLSMode) {
        lock.withLock { _globalTLSMode = mode }
    }

    /// Returns all certificates in the certificate store.
    public func getCertificates() -> [SecurityCertificateEntry] {
        lock.withLock { _certificates }
    }

    /// Adds a certificate to the store.
    public func addCertificate(_ certificate: SecurityCertificateEntry) {
        lock.withLock { _certificates.append(certificate) }
    }

    /// Updates an existing certificate by ID.
    public func updateCertificate(_ certificate: SecurityCertificateEntry) {
        lock.withLock {
            guard let idx = _certificates.firstIndex(where: { $0.id == certificate.id }) else { return }
            _certificates[idx] = certificate
        }
    }

    /// Removes a certificate by ID.
    public func removeCertificate(id: UUID) {
        lock.withLock { _certificates.removeAll { $0.id == id } }
    }

    /// Returns all server security entries.
    public func getServerSecurityEntries() -> [SecurityServerEntry] {
        lock.withLock { _serverSecurityEntries }
    }

    /// Adds a server security entry.
    public func addServerSecurityEntry(_ entry: SecurityServerEntry) {
        lock.withLock { _serverSecurityEntries.append(entry) }
    }

    /// Updates an existing server security entry by ID.
    public func updateServerSecurityEntry(_ entry: SecurityServerEntry) {
        lock.withLock {
            guard let idx = _serverSecurityEntries.firstIndex(where: { $0.id == entry.id }) else { return }
            _serverSecurityEntries[idx] = entry
        }
    }

    /// Removes a server security entry by ID.
    public func removeServerSecurityEntry(id: UUID) {
        lock.withLock { _serverSecurityEntries.removeAll { $0.id == id } }
    }

    /// Returns certificates with status `.expiringSoon` or `.expired`.
    public func expiringCertificates() -> [SecurityCertificateEntry] {
        lock.withLock {
            _certificates.filter { $0.status == .expiringSoon || $0.status == .expired }
        }
    }

    // MARK: - 11.2 Anonymization

    /// Returns all anonymization jobs.
    public func getAnonymizationJobs() -> [AnonymizationJob] {
        lock.withLock { _anonymizationJobs }
    }

    /// Enqueues a new anonymization job.
    public func enqueueAnonymizationJob(_ job: AnonymizationJob) {
        lock.withLock { _anonymizationJobs.append(job) }
    }

    /// Updates an existing anonymization job.
    public func updateAnonymizationJob(_ job: AnonymizationJob) {
        lock.withLock {
            guard let idx = _anonymizationJobs.firstIndex(where: { $0.id == job.id }) else { return }
            _anonymizationJobs[idx] = job
        }
    }

    /// Cancels a running or pending job.
    public func cancelAnonymizationJob(id: UUID) {
        lock.withLock {
            guard let idx = _anonymizationJobs.firstIndex(where: { $0.id == id }) else { return }
            _anonymizationJobs[idx].status = .cancelled
        }
    }

    /// Removes a terminal job.
    public func removeAnonymizationJob(id: UUID) {
        lock.withLock {
            _anonymizationJobs.removeAll { $0.id == id && $0.status.isTerminal }
        }
    }

    /// Returns the currently selected anonymization profile.
    public func getSelectedProfile() -> AnonymizationProfile {
        lock.withLock { _selectedProfile }
    }

    /// Sets the selected anonymization profile.
    public func setSelectedProfile(_ profile: AnonymizationProfile) {
        lock.withLock { _selectedProfile = profile }
    }

    /// Returns the current custom anonymization rules.
    public func getCustomRules() -> [AnonymizationTagRule] {
        lock.withLock { _customRules }
    }

    /// Replaces the custom anonymization rules.
    public func setCustomRules(_ rules: [AnonymizationTagRule]) {
        lock.withLock { _customRules = rules }
    }

    /// Adds a custom rule.
    public func addCustomRule(_ rule: AnonymizationTagRule) {
        lock.withLock { _customRules.append(rule) }
    }

    /// Removes a custom rule by ID.
    public func removeCustomRule(id: UUID) {
        lock.withLock { _customRules.removeAll { $0.id == id } }
    }

    /// Returns all PHI detection results.
    public func getPHIDetectionResults() -> [PHIDetectionResult] {
        lock.withLock { _phiDetectionResults }
    }

    /// Adds a PHI detection result.
    public func addPHIDetectionResult(_ result: PHIDetectionResult) {
        lock.withLock { _phiDetectionResults.append(result) }
    }

    /// Clears all PHI detection results.
    public func clearPHIDetectionResults() {
        lock.withLock { _phiDetectionResults.removeAll() }
    }

    // MARK: - 11.3 Audit Log

    /// Returns all audit log entries.
    public func getAuditEntries() -> [SecurityAuditEntry] {
        lock.withLock { _auditEntries }
    }

    /// Appends a new audit log entry.
    public func addAuditEntry(_ entry: SecurityAuditEntry) {
        lock.withLock { _auditEntries.append(entry) }
    }

    /// Clears all audit log entries.
    public func clearAuditEntries() {
        lock.withLock { _auditEntries.removeAll() }
    }

    /// Applies the current retention policy to remove stale entries.
    public func applyRetentionPolicy() {
        lock.withLock {
            _auditEntries = SecurityAuditHelpers.applyRetentionPolicy(_auditEntries, policy: _retentionPolicy)
        }
    }

    /// Returns the set of enabled log handlers.
    public func getEnabledHandlers() -> Set<SecurityAuditHandlerType> {
        lock.withLock { _enabledHandlers }
    }

    /// Enables or disables a log handler.
    public func setHandler(_ handler: SecurityAuditHandlerType, enabled: Bool) {
        lock.withLock {
            if enabled {
                _enabledHandlers.insert(handler)
            } else {
                _enabledHandlers.remove(handler)
            }
        }
    }

    /// Returns the current audit retention policy.
    public func getRetentionPolicy() -> SecurityAuditRetentionPolicy {
        lock.withLock { _retentionPolicy }
    }

    /// Sets the audit retention policy.
    public func setRetentionPolicy(_ policy: SecurityAuditRetentionPolicy) {
        lock.withLock { _retentionPolicy = policy }
    }

    // MARK: - 11.4 Access Control

    /// Returns the current session, if any.
    public func getCurrentSession() -> AccessControlSession? {
        lock.withLock { _currentSession }
    }

    /// Sets the current session.
    public func setCurrentSession(_ session: AccessControlSession?) {
        lock.withLock { _currentSession = session }
    }

    /// Updates the last activity timestamp for the current session.
    public func touchSession() {
        lock.withLock {
            _currentSession?.lastActivityAt = Date()
            if _currentSession?.status == .idle {
                _currentSession?.status = .active
            }
        }
    }

    /// Marks the current session as idle.
    public func markSessionIdle() {
        lock.withLock {
            if _currentSession?.status == .active {
                _currentSession?.status = .idle
            }
        }
    }

    /// Locks the current session.
    public func lockSession() {
        lock.withLock { _currentSession?.status = .locked }
    }

    /// Expires the current session.
    public func expireSession() {
        lock.withLock { _currentSession?.status = .expired }
    }

    /// Returns all break-glass events.
    public func getBreakGlassEvents() -> [BreakGlassEvent] {
        lock.withLock { _breakGlassEvents }
    }

    /// Records a new break-glass event and appends a corresponding audit log entry.
    public func recordBreakGlassEvent(_ event: BreakGlassEvent) {
        lock.withLock {
            _breakGlassEvents.append(event)
            let auditEntry = SecurityAuditEntry(
                eventType: .breakGlassAccess,
                userIdentity: event.userName,
                studyReference: event.resourceReference,
                description: "Break-glass access: \(event.reason)",
                success: true
            )
            _auditEntries.append(auditEntry)
        }
    }
}
