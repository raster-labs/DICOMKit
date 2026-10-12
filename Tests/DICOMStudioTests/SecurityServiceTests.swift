// SecurityServiceTests.swift
// DICOMStudioTests

import Testing
@testable import DICOMStudio
import Foundation

@Suite("Security Service Tests")
struct SecurityServiceTests {

    // MARK: - 11.1 TLS Configuration

    @Test("initial global TLS mode is compatible")
    func testInitialTLSModeCompatible() {
        let service = SecurityService()
        #expect(service.getGlobalTLSMode() == .compatible)
    }

    @Test("setGlobalTLSMode updates mode")
    func testSetGlobalTLSMode() {
        let service = SecurityService()
        service.setGlobalTLSMode(.strict)
        #expect(service.getGlobalTLSMode() == .strict)
    }

    @Test("initial certificates list is empty")
    func testInitialCertificatesEmpty() {
        let service = SecurityService()
        #expect(service.getCertificates().isEmpty)
    }

    @Test("addCertificate increases count")
    func testAddCertificateIncreasesCount() {
        let service = SecurityService()
        service.addCertificate(SecurityCertificateEntry(commonName: "test.com"))
        #expect(service.getCertificates().count == 1)
    }

    @Test("updateCertificate updates commonName")
    func testUpdateCertificateUpdatesName() {
        let service = SecurityService()
        var cert = SecurityCertificateEntry(commonName: "old.com")
        service.addCertificate(cert)
        cert.commonName = "new.com"
        service.updateCertificate(cert)
        #expect(service.getCertificates().first?.commonName == "new.com")
    }

    @Test("removeCertificate decreases count")
    func testRemoveCertificateDecreasesCount() {
        let service = SecurityService()
        let cert = SecurityCertificateEntry(commonName: "test.com")
        service.addCertificate(cert)
        service.removeCertificate(id: cert.id)
        #expect(service.getCertificates().isEmpty)
    }

    @Test("expiringCertificates returns expiringSoon and expired certs")
    func testExpiringCertificatesReturnsExpiring() {
        let service = SecurityService()
        let valid = SecurityCertificateEntry(commonName: "valid", notAfter: Date().addingTimeInterval(90 * 24 * 3600))
        let soon = SecurityCertificateEntry(commonName: "soon", notAfter: Date().addingTimeInterval(10 * 24 * 3600))
        let expired = SecurityCertificateEntry(commonName: "expired", notAfter: Date().addingTimeInterval(-1 * 24 * 3600))
        service.addCertificate(valid)
        service.addCertificate(soon)
        service.addCertificate(expired)
        let expiring = service.expiringCertificates()
        #expect(expiring.count == 2)
    }

    @Test("initial serverSecurityEntries is empty")
    func testInitialServerSecurityEntriesEmpty() {
        let service = SecurityService()
        #expect(service.getServerSecurityEntries().isEmpty)
    }

    @Test("addServerSecurityEntry increases count")
    func testAddServerSecurityEntryIncreasesCount() {
        let service = SecurityService()
        service.addServerSecurityEntry(SecurityServerEntry(serverName: "PACS"))
        #expect(service.getServerSecurityEntries().count == 1)
    }

    @Test("updateServerSecurityEntry updates serverName")
    func testUpdateServerSecurityEntryUpdatesName() {
        let service = SecurityService()
        var entry = SecurityServerEntry(serverName: "Old")
        service.addServerSecurityEntry(entry)
        entry.serverName = "New"
        service.updateServerSecurityEntry(entry)
        #expect(service.getServerSecurityEntries().first?.serverName == "New")
    }

    @Test("removeServerSecurityEntry decreases count")
    func testRemoveServerSecurityEntryDecreasesCount() {
        let service = SecurityService()
        let entry = SecurityServerEntry(serverName: "PACS")
        service.addServerSecurityEntry(entry)
        service.removeServerSecurityEntry(id: entry.id)
        #expect(service.getServerSecurityEntries().isEmpty)
    }

    // MARK: - 11.2 Anonymization

    @Test("initial anonymization jobs is empty")
    func testInitialAnonymizationJobsEmpty() {
        let service = SecurityService()
        #expect(service.getAnonymizationJobs().isEmpty)
    }

    @Test("enqueueAnonymizationJob increases count")
    func testEnqueueAnonymizationJobIncreasesCount() {
        let service = SecurityService()
        service.enqueueAnonymizationJob(AnonymizationJob())
        #expect(service.getAnonymizationJobs().count == 1)
    }

    @Test("updateAnonymizationJob updates status")
    func testUpdateAnonymizationJobUpdatesStatus() {
        let service = SecurityService()
        var job = AnonymizationJob()
        service.enqueueAnonymizationJob(job)
        job.status = .running
        service.updateAnonymizationJob(job)
        #expect(service.getAnonymizationJobs().first?.status == .running)
    }

    @Test("cancelAnonymizationJob sets status to cancelled")
    func testCancelAnonymizationJobCancels() {
        let service = SecurityService()
        let job = AnonymizationJob(status: .running)
        service.enqueueAnonymizationJob(job)
        service.cancelAnonymizationJob(id: job.id)
        #expect(service.getAnonymizationJobs().first?.status == .cancelled)
    }

    @Test("removeAnonymizationJob removes terminal job")
    func testRemoveAnonymizationJobRemovesTerminal() {
        let service = SecurityService()
        let job = AnonymizationJob(status: .completed)
        service.enqueueAnonymizationJob(job)
        service.removeAnonymizationJob(id: job.id)
        #expect(service.getAnonymizationJobs().isEmpty)
    }

    @Test("removeAnonymizationJob does not remove running job")
    func testRemoveAnonymizationJobDoesNotRemoveRunning() {
        let service = SecurityService()
        let job = AnonymizationJob(status: .running)
        service.enqueueAnonymizationJob(job)
        service.removeAnonymizationJob(id: job.id)
        #expect(service.getAnonymizationJobs().count == 1)
    }

    @Test("initial PHI detection results is empty")
    func testInitialPHIDetectionEmpty() {
        let service = SecurityService()
        #expect(service.getPHIDetectionResults().isEmpty)
    }

    @Test("addPHIDetectionResult increases count")
    func testAddPHIDetectionResultIncreasesCount() {
        let service = SecurityService()
        service.addPHIDetectionResult(PHIDetectionResult(filePath: "test.dcm"))
        #expect(service.getPHIDetectionResults().count == 1)
    }

    @Test("clearPHIDetectionResults empties list")
    func testClearPHIDetectionResultsEmptiesList() {
        let service = SecurityService()
        service.addPHIDetectionResult(PHIDetectionResult(filePath: "test.dcm"))
        service.clearPHIDetectionResults()
        #expect(service.getPHIDetectionResults().isEmpty)
    }

    // MARK: - 11.3 Audit Log

    @Test("initial audit entries is empty")
    func testInitialAuditEntriesEmpty() {
        let service = SecurityService()
        #expect(service.getAuditEntries().isEmpty)
    }

    @Test("addAuditEntry increases count")
    func testAddAuditEntryIncreasesCount() {
        let service = SecurityService()
        service.addAuditEntry(SecurityAuditEntry(eventType: .fileAccess))
        #expect(service.getAuditEntries().count == 1)
    }

    @Test("clearAuditEntries empties list")
    func testClearAuditEntriesEmptiesList() {
        let service = SecurityService()
        service.addAuditEntry(SecurityAuditEntry(eventType: .fileAccess))
        service.clearAuditEntries()
        #expect(service.getAuditEntries().isEmpty)
    }

    @Test("initial enabled handlers contains console")
    func testInitialEnabledHandlersContainsConsole() {
        let service = SecurityService()
        #expect(service.getEnabledHandlers().contains(.console))
    }

    @Test("setHandler enabled adds handler")
    func testSetHandlerEnabledAddsHandler() {
        let service = SecurityService()
        service.setHandler(.file, enabled: true)
        #expect(service.getEnabledHandlers().contains(.file))
    }

    @Test("setHandler disabled removes handler")
    func testSetHandlerDisabledRemovesHandler() {
        let service = SecurityService()
        service.setHandler(.console, enabled: false)
        #expect(!service.getEnabledHandlers().contains(.console))
    }

    @Test("initial retention policy is days365")
    func testInitialRetentionPolicyDays365() {
        let service = SecurityService()
        #expect(service.getRetentionPolicy() == .days365)
    }

    @Test("setRetentionPolicy updates policy")
    func testSetRetentionPolicyUpdates() {
        let service = SecurityService()
        service.setRetentionPolicy(.days90)
        #expect(service.getRetentionPolicy() == .days90)
    }

    @Test("applyRetentionPolicy removes stale entries")
    func testApplyRetentionPolicyRemovesStaleEntries() {
        let service = SecurityService()
        let old = SecurityAuditEntry(
            timestamp: Date().addingTimeInterval(-400 * 24 * 3600),
            eventType: .fileAccess
        )
        let recent = SecurityAuditEntry(
            timestamp: Date().addingTimeInterval(-5 * 24 * 3600),
            eventType: .fileAccess
        )
        service.addAuditEntry(old)
        service.addAuditEntry(recent)
        service.setRetentionPolicy(.days365)
        service.applyRetentionPolicy()
        #expect(service.getAuditEntries().count == 1)
    }

    // MARK: - 11.4 Access Control

    @Test("initial current session is nil")
    func testInitialCurrentSessionNil() {
        let service = SecurityService()
        #expect(service.getCurrentSession() == nil)
    }

    @Test("setCurrentSession stores session")
    func testSetCurrentSessionStores() {
        let service = SecurityService()
        let session = AccessControlSession(userName: "Alice")
        service.setCurrentSession(session)
        #expect(service.getCurrentSession()?.userName == "Alice")
    }

    @Test("setCurrentSession nil clears session")
    func testSetCurrentSessionNilClears() {
        let service = SecurityService()
        service.setCurrentSession(AccessControlSession(userName: "Bob"))
        service.setCurrentSession(nil)
        #expect(service.getCurrentSession() == nil)
    }

    @Test("touchSession updates lastActivityAt")
    func testTouchSessionUpdatesLastActivity() {
        let service = SecurityService()
        let past = Date().addingTimeInterval(-600)
        let session = AccessControlSession(userName: "Carol", lastActivityAt: past)
        service.setCurrentSession(session)
        service.touchSession()
        let updated = service.getCurrentSession()?.lastActivityAt
        #expect(updated != nil)
        #expect(updated! > past)
    }

    @Test("touchSession changes idle to active")
    func testTouchSessionChangesIdleToActive() {
        let service = SecurityService()
        var session = AccessControlSession(userName: "Dave")
        session.status = .idle
        service.setCurrentSession(session)
        service.touchSession()
        #expect(service.getCurrentSession()?.status == .active)
    }

    @Test("markSessionIdle changes active to idle")
    func testMarkSessionIdleChangesActiveToIdle() {
        let service = SecurityService()
        service.setCurrentSession(AccessControlSession(userName: "Eve"))
        service.markSessionIdle()
        #expect(service.getCurrentSession()?.status == .idle)
    }

    @Test("lockSession sets status to locked")
    func testLockSessionSetsLocked() {
        let service = SecurityService()
        service.setCurrentSession(AccessControlSession(userName: "Frank"))
        service.lockSession()
        #expect(service.getCurrentSession()?.status == .locked)
    }

    @Test("expireSession sets status to expired")
    func testExpireSessionSetsExpired() {
        let service = SecurityService()
        service.setCurrentSession(AccessControlSession(userName: "Grace"))
        service.expireSession()
        #expect(service.getCurrentSession()?.status == .expired)
    }

    @Test("initial break glass events is empty")
    func testInitialBreakGlassEventsEmpty() {
        let service = SecurityService()
        #expect(service.getBreakGlassEvents().isEmpty)
    }

    @Test("recordBreakGlassEvent increases count")
    func testRecordBreakGlassEventIncreasesCount() {
        let service = SecurityService()
        let event = BreakGlassEvent(userName: "Admin", reason: "Emergency")
        service.recordBreakGlassEvent(event)
        #expect(service.getBreakGlassEvents().count == 1)
    }

    @Test("recordBreakGlassEvent also adds audit entry")
    func testRecordBreakGlassEventAddsAuditEntry() {
        let service = SecurityService()
        let event = BreakGlassEvent(userName: "Admin", reason: "Emergency")
        service.recordBreakGlassEvent(event)
        let breakGlassAuditEntries = service.getAuditEntries().filter { $0.eventType == .breakGlassAccess }
        #expect(breakGlassAuditEntries.count == 1)
    }
}
