// SecurityViewModelTests.swift
// DICOMStudioTests

import Testing
@testable import DICOMStudio
import Foundation

@Suite("Security ViewModel Tests")
@MainActor
struct SecurityViewModelTests {

    // MARK: - Navigation

    @Test("default activeTab is tlsConfiguration")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDefaultActiveTab() {
        let vm = SecurityViewModel()
        #expect(vm.activeTab == .tlsConfiguration)
    }

    @Test("isLoading starts false")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testIsLoadingStartsFalse() {
        let vm = SecurityViewModel()
        #expect(vm.isLoading == false)
    }

    @Test("errorMessage starts nil")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testErrorMessageStartsNil() {
        let vm = SecurityViewModel()
        #expect(vm.errorMessage == nil)
    }

    // MARK: - 11.1 TLS Configuration

    @Test("default globalTLSMode is compatible")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDefaultGlobalTLSMode() {
        let vm = SecurityViewModel()
        #expect(vm.globalTLSMode == .compatible)
    }

    @Test("setGlobalTLSMode updates mode")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetGlobalTLSMode() {
        let vm = SecurityViewModel()
        vm.setGlobalTLSMode(.strict)
        #expect(vm.globalTLSMode == .strict)
    }

    @Test("addCertificate increases certificates count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testAddCertificateIncreasesCount() {
        let vm = SecurityViewModel()
        vm.addCertificate(SecurityCertificateEntry(commonName: "test.com"))
        #expect(vm.certificates.count == 1)
    }

    @Test("removeCertificate decreases count and clears selection")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRemoveCertificateDecreasesCountAndClearsSelection() {
        let vm = SecurityViewModel()
        let cert = SecurityCertificateEntry(commonName: "test.com")
        vm.addCertificate(cert)
        vm.selectedCertificateID = cert.id
        vm.removeCertificate(id: cert.id)
        #expect(vm.certificates.isEmpty)
        #expect(vm.selectedCertificateID == nil)
    }

    @Test("updateCertificate updates commonName")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testUpdateCertificateUpdatesName() {
        let vm = SecurityViewModel()
        var cert = SecurityCertificateEntry(commonName: "old.com")
        vm.addCertificate(cert)
        cert.commonName = "new.com"
        vm.updateCertificate(cert)
        #expect(vm.certificates.first?.commonName == "new.com")
    }

    @Test("selectedCertificate returns correct certificate")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSelectedCertificateReturnsCorrect() {
        let vm = SecurityViewModel()
        let cert = SecurityCertificateEntry(commonName: "target.com")
        vm.addCertificate(cert)
        vm.selectedCertificateID = cert.id
        #expect(vm.selectedCertificate?.commonName == "target.com")
    }

    @Test("selectedCertificate nil when no selection")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSelectedCertificateNilWhenNoSelection() {
        let vm = SecurityViewModel()
        #expect(vm.selectedCertificate == nil)
    }

    @Test("expiringCertificates returns only expiring entries")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testExpiringCertificatesFiltersCorrectly() {
        let vm = SecurityViewModel()
        vm.addCertificate(SecurityCertificateEntry(commonName: "valid", notAfter: Date().addingTimeInterval(90 * 24 * 3600)))
        vm.addCertificate(SecurityCertificateEntry(commonName: "expiring", notAfter: Date().addingTimeInterval(5 * 24 * 3600)))
        #expect(vm.expiringCertificates.count == 1)
    }

    @Test("addServerSecurityEntry increases count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testAddServerSecurityEntryIncreasesCount() {
        let vm = SecurityViewModel()
        vm.addServerSecurityEntry(SecurityServerEntry(serverName: "PACS"))
        #expect(vm.serverSecurityEntries.count == 1)
    }

    @Test("removeServerSecurityEntry decreases count and clears selection")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRemoveServerSecurityEntryDecreasesCount() {
        let vm = SecurityViewModel()
        let entry = SecurityServerEntry(serverName: "PACS")
        vm.addServerSecurityEntry(entry)
        vm.selectedServerSecurityID = entry.id
        vm.removeServerSecurityEntry(id: entry.id)
        #expect(vm.serverSecurityEntries.isEmpty)
        #expect(vm.selectedServerSecurityID == nil)
    }

    // MARK: - 11.2 Anonymization

    @Test("default selectedProfile is basic")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDefaultSelectedProfile() {
        let vm = SecurityViewModel()
        #expect(vm.selectedProfile == .basic)
    }

    @Test("setProfile basic loads the 14 default rules of the engine's basic profile")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetProfileBasicLoads14Rules() {
        let vm = SecurityViewModel()
        vm.setProfile(.basic)
        #expect(vm.customRules.count == 14)
    }

    @Test("setProfile custom does not load default rules")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetProfileCustomDoesNotLoadDefaultRules() {
        let vm = SecurityViewModel()
        vm.setProfile(.custom)
        #expect(vm.customRules.isEmpty)
    }

    @Test("addCustomRule increases customRules count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testAddCustomRuleIncreasesCount() {
        let vm = SecurityViewModel()
        vm.setProfile(.custom)
        vm.addCustomRule(AnonymizationTagRule(tag: "0010,0010"))
        #expect(vm.customRules.count == 1)
    }

    @Test("removeCustomRule decreases customRules count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRemoveCustomRuleDecreasesCount() {
        let vm = SecurityViewModel()
        vm.setProfile(.custom)
        let rule = AnonymizationTagRule(tag: "0010,0010")
        vm.addCustomRule(rule)
        vm.removeCustomRule(id: rule.id)
        #expect(vm.customRules.isEmpty)
    }

    @Test("enqueueAnonymizationJob increases job count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEnqueueAnonymizationJobIncreasesCount() {
        let vm = SecurityViewModel()
        vm.stagedFilePaths = ["/tmp/test.dcm"]
        vm.outputDirectory = "/tmp/output"
        vm.enqueueAnonymizationJob()
        #expect(vm.anonymizationJobs.count == 1)
    }

    @Test("enqueueAnonymizationJob clears staged file paths")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEnqueueAnonymizationJobClearsStagedPaths() {
        let vm = SecurityViewModel()
        vm.stagedFilePaths = ["/tmp/test.dcm"]
        vm.outputDirectory = "/tmp/output"
        vm.enqueueAnonymizationJob()
        #expect(vm.stagedFilePaths.isEmpty)
    }

    @Test("cancelAnonymizationJob sets status to cancelled")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCancelAnonymizationJobSetsStatus() {
        let vm = SecurityViewModel()
        vm.stagedFilePaths = ["/tmp/test.dcm"]
        vm.outputDirectory = "/tmp/output"
        vm.enqueueAnonymizationJob()
        guard let job = vm.anonymizationJobs.first else { return }
        vm.cancelAnonymizationJob(id: job.id)
        #expect(vm.anonymizationJobs.first?.status == .cancelled)
    }

    @Test("selectedJob returns correct job")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSelectedJobReturnsCorrect() {
        let vm = SecurityViewModel()
        vm.stagedFilePaths = ["/tmp/test.dcm"]
        vm.outputDirectory = "/tmp/output"
        vm.enqueueAnonymizationJob()
        guard let job = vm.anonymizationJobs.first else { return }
        vm.selectedJobID = job.id
        #expect(vm.selectedJob?.id == job.id)
    }

    @Test("jobValidationError returns error for empty staged paths")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testJobValidationErrorEmptyFiles() {
        let vm = SecurityViewModel()
        vm.stagedFilePaths = []
        vm.outputDirectory = "/tmp/output"
        #expect(vm.jobValidationError() != nil)
    }

    @Test("jobValidationError returns error for empty output directory")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testJobValidationErrorEmptyOutputDir() {
        let vm = SecurityViewModel()
        vm.stagedFilePaths = ["/tmp/test.dcm"]
        vm.outputDirectory = ""
        #expect(vm.jobValidationError() != nil)
    }

    @Test("jobValidationError returns nil for valid inputs")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testJobValidationErrorNilForValid() {
        let vm = SecurityViewModel()
        vm.stagedFilePaths = ["/tmp/test.dcm"]
        vm.outputDirectory = "/tmp/output"
        #expect(vm.jobValidationError() == nil)
    }

    // MARK: - 11.3 Audit Log

    @Test("addAuditEntry increases auditEntries count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testAddAuditEntryIncreasesCount() {
        let vm = SecurityViewModel()
        vm.addAuditEntry(SecurityAuditEntry(eventType: .fileAccess))
        #expect(vm.auditEntries.count == 1)
    }

    @Test("clearAuditEntries empties auditEntries")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testClearAuditEntriesEmptiesEntries() {
        let vm = SecurityViewModel()
        vm.addAuditEntry(SecurityAuditEntry(eventType: .fileAccess))
        vm.clearAuditEntries()
        #expect(vm.auditEntries.isEmpty)
    }

    @Test("filteredAuditEntries returns all when no filters set")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testFilteredAuditEntriesAllWhenNoFilter() {
        let vm = SecurityViewModel()
        vm.addAuditEntry(SecurityAuditEntry(eventType: .fileAccess))
        vm.addAuditEntry(SecurityAuditEntry(eventType: .networkSend))
        #expect(vm.filteredAuditEntries.count == 2)
    }

    @Test("filteredAuditEntries filters by event type")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testFilteredAuditEntriesByEventType() {
        let vm = SecurityViewModel()
        vm.addAuditEntry(SecurityAuditEntry(eventType: .fileAccess))
        vm.addAuditEntry(SecurityAuditEntry(eventType: .networkSend))
        vm.auditFilterEventType = .fileAccess
        #expect(vm.filteredAuditEntries.count == 1)
    }

    @Test("filteredAuditEntries filters by user")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testFilteredAuditEntriesByUser() {
        let vm = SecurityViewModel()
        vm.addAuditEntry(SecurityAuditEntry(eventType: .fileAccess, userIdentity: "alice"))
        vm.addAuditEntry(SecurityAuditEntry(eventType: .fileAccess, userIdentity: "bob"))
        vm.auditFilterUser = "alice"
        #expect(vm.filteredAuditEntries.count == 1)
    }

    @Test("clearAuditFilters resets all filters")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testClearAuditFiltersResetsAll() {
        let vm = SecurityViewModel()
        vm.auditFilterEventType = .fileAccess
        vm.auditFilterUser = "alice"
        vm.auditFilterReference = "PAT001"
        vm.clearAuditFilters()
        #expect(vm.auditFilterEventType == nil)
        #expect(vm.auditFilterUser.isEmpty)
        #expect(vm.auditFilterReference.isEmpty)
    }

    @Test("exportAuditLogCSV returns non-empty CSV with entries")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testExportAuditLogCSVNonEmpty() {
        let vm = SecurityViewModel()
        vm.addAuditEntry(SecurityAuditEntry(eventType: .fileAccess, userIdentity: "admin"))
        let csv = vm.exportAuditLogCSV()
        #expect(csv.contains("Timestamp"))
        #expect(csv.contains("admin"))
    }

    @Test("auditStatistics counts event types")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testAuditStatisticsCounts() {
        let vm = SecurityViewModel()
        vm.addAuditEntry(SecurityAuditEntry(eventType: .fileAccess))
        vm.addAuditEntry(SecurityAuditEntry(eventType: .fileAccess))
        vm.addAuditEntry(SecurityAuditEntry(eventType: .networkSend))
        #expect(vm.auditStatistics[.fileAccess] == 2)
        #expect(vm.auditStatistics[.networkSend] == 1)
    }

    @Test("setHandler enabled adds handler")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetHandlerEnabledAddsHandler() {
        let vm = SecurityViewModel()
        vm.setHandler(.file, enabled: true)
        #expect(vm.enabledHandlers.contains(.file))
    }

    @Test("setHandler disabled removes handler")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetHandlerDisabledRemovesHandler() {
        let vm = SecurityViewModel()
        vm.setHandler(.console, enabled: false)
        #expect(!vm.enabledHandlers.contains(.console))
    }

    @Test("setRetentionPolicy updates policy")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetRetentionPolicyUpdates() {
        let vm = SecurityViewModel()
        vm.setRetentionPolicy(.days90)
        #expect(vm.retentionPolicy == .days90)
    }

    // MARK: - 11.4 Access Control

    @Test("default currentSession is nil")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDefaultCurrentSessionNil() {
        let vm = SecurityViewModel()
        #expect(vm.currentSession == nil)
    }

    @Test("setCurrentSession stores session")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetCurrentSessionStores() {
        let vm = SecurityViewModel()
        vm.setCurrentSession(AccessControlSession(userName: "Alice"))
        #expect(vm.currentSession?.userName == "Alice")
    }

    @Test("lockSession sets session to locked")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testLockSessionSetsLocked() {
        let vm = SecurityViewModel()
        vm.setCurrentSession(AccessControlSession(userName: "Bob"))
        vm.lockSession()
        #expect(vm.currentSession?.status == .locked)
    }

    @Test("currentUserHasPermission false when no session")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCurrentUserHasPermissionFalseNoSession() {
        let vm = SecurityViewModel()
        #expect(vm.currentUserHasPermission(for: "view") == false)
    }

    @Test("currentUserHasPermission true for viewer viewing")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCurrentUserHasPermissionTrueViewerView() {
        let vm = SecurityViewModel()
        vm.setCurrentSession(AccessControlSession(userName: "Viewer", role: .viewer))
        #expect(vm.currentUserHasPermission(for: "view") == true)
    }

    @Test("currentUserHasPermission false for viewer deleting")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCurrentUserHasPermissionFalseViewerDelete() {
        let vm = SecurityViewModel()
        vm.setCurrentSession(AccessControlSession(userName: "Viewer", role: .viewer))
        #expect(vm.currentUserHasPermission(for: "delete") == false)
    }

    @Test("remainingSessionTime nil when no session")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRemainingSessionTimeNilNoSession() {
        let vm = SecurityViewModel()
        #expect(vm.remainingSessionTime == nil)
    }

    @Test("remainingSessionTime positive for active session")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRemainingSessionTimePositive() {
        let vm = SecurityViewModel()
        vm.setCurrentSession(AccessControlSession(userName: "Active", lastActivityAt: Date(), timeoutInterval: 3600))
        #expect(vm.remainingSessionTime != nil)
        #expect(vm.remainingSessionTime! > 0)
    }

    @Test("permissionMatrix is populated on init")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testPermissionMatrixPopulatedOnInit() {
        let vm = SecurityViewModel()
        #expect(!vm.permissionMatrix.isEmpty)
    }

    @Test("recordBreakGlassEvent adds break glass event and clears reason")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRecordBreakGlassEventAddsEvent() {
        let vm = SecurityViewModel()
        vm.setCurrentSession(AccessControlSession(userName: "Admin", role: .admin))
        vm.breakGlassReason = "Emergency patient care"
        vm.recordBreakGlassEvent(resource: "PAT001")
        #expect(vm.breakGlassEvents.count == 1)
        #expect(vm.breakGlassReason.isEmpty)
    }

    @Test("recordBreakGlassEvent does nothing for empty reason")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRecordBreakGlassEventEmptyReasonNoOp() {
        let vm = SecurityViewModel()
        vm.setCurrentSession(AccessControlSession(userName: "Admin"))
        vm.breakGlassReason = "   "
        vm.recordBreakGlassEvent(resource: "PAT001")
        #expect(vm.breakGlassEvents.isEmpty)
    }

    @Test("recordBreakGlassEvent adds audit entry")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRecordBreakGlassEventAddsAuditEntry() {
        let vm = SecurityViewModel()
        vm.setCurrentSession(AccessControlSession(userName: "Admin", role: .admin))
        vm.breakGlassReason = "Emergency"
        vm.recordBreakGlassEvent(resource: "PAT001")
        let breakGlassAuditEntries = vm.auditEntries.filter { $0.eventType == .breakGlassAccess }
        #expect(breakGlassAuditEntries.count == 1)
    }
}
