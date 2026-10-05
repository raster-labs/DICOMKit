// SecurityModelTests.swift
// DICOMStudioTests

import Testing
@testable import DICOMStudio
import Foundation

@Suite("Security Model Tests")
struct SecurityModelTests {

    // MARK: - SecurityTab

    @Test("SecurityTab all cases have non-empty display names")
    func testSecurityTabDisplayNames() {
        for tab in SecurityTab.allCases {
            #expect(!tab.displayName.isEmpty)
        }
    }

    @Test("SecurityTab all cases have non-empty SF symbols")
    func testSecurityTabSFSymbols() {
        for tab in SecurityTab.allCases {
            #expect(!tab.sfSymbol.isEmpty)
        }
    }

    @Test("SecurityTab has 4 cases")
    func testSecurityTabCaseCount() {
        #expect(SecurityTab.allCases.count == 4)
    }

    @Test("SecurityTab rawValues are unique")
    func testSecurityTabRawValuesUnique() {
        let rawValues = SecurityTab.allCases.map { $0.rawValue }
        #expect(Set(rawValues).count == SecurityTab.allCases.count)
    }

    // MARK: - SecurityTLSMode

    @Test("SecurityTLSMode all cases have non-empty display names")
    func testTLSModeDisplayNames() {
        for mode in SecurityTLSMode.allCases {
            #expect(!mode.displayName.isEmpty)
        }
    }

    @Test("SecurityTLSMode all cases have non-empty short descriptions")
    func testTLSModeShortDescriptions() {
        for mode in SecurityTLSMode.allCases {
            #expect(!mode.shortDescription.isEmpty)
        }
    }

    @Test("SecurityTLSMode strict does not allow self-signed")
    func testTLSModeStrictNoSelfSigned() {
        #expect(SecurityTLSMode.strict.allowsSelfSigned == false)
    }

    @Test("SecurityTLSMode compatible does not allow self-signed")
    func testTLSModeCompatibleNoSelfSigned() {
        #expect(SecurityTLSMode.compatible.allowsSelfSigned == false)
    }

    @Test("SecurityTLSMode development allows self-signed")
    func testTLSModeDevelopmentAllowsSelfSigned() {
        #expect(SecurityTLSMode.development.allowsSelfSigned == true)
    }

    @Test("SecurityTLSMode strict minimum version is TLS 1.3")
    func testTLSModeStrictMinVersion() {
        #expect(SecurityTLSMode.strict.minimumTLSVersion == "TLS 1.3")
    }

    @Test("SecurityTLSMode compatible minimum version is TLS 1.2")
    func testTLSModeCompatibleMinVersion() {
        #expect(SecurityTLSMode.compatible.minimumTLSVersion == "TLS 1.2")
    }

    @Test("SecurityTLSMode never offers TLS below 1.2 (PS3.15 2026a B.12, RFC 8996)")
    func testTLSModeMinimumVersionsPerB12() {
        for mode in SecurityTLSMode.allCases {
            #expect(["TLS 1.2", "TLS 1.3"].contains(mode.minimumTLSVersion), "\(mode.rawValue)")
        }
        #expect(SecurityTLSMode.development.minimumTLSVersion == "TLS 1.2")
    }

    @Test("AnonymizationProfile descriptions state the engine's attribute counts, not '18 HIPAA identifiers'")
    func testProfileDescriptionsNameEngineCounts() {
        #expect(AnonymizationProfile.basic.shortDescription.contains("14"))
        #expect(AnonymizationProfile.clinicalTrial.shortDescription.contains("22"))
        #expect(!AnonymizationProfile.basic.shortDescription.contains("18 HIPAA"))
        #expect(AnonymizationProfile.hipaaeSafeHarbor.shortDescription.contains("Not a complete"))
    }

    @Test("SecurityTLSMode strict and compatible are production-safe")
    func testTLSModeProductionSafe() {
        #expect(SecurityTLSMode.strict.isProductionSafe == true)
        #expect(SecurityTLSMode.compatible.isProductionSafe == true)
        #expect(SecurityTLSMode.development.isProductionSafe == false)
    }

    @Test("SecurityTLSMode has 3 cases")
    func testTLSModeCaseCount() {
        #expect(SecurityTLSMode.allCases.count == 3)
    }

    // MARK: - SecurityCertificateStatus

    @Test("SecurityCertificateStatus valid is usable")
    func testCertificateStatusValidUsable() {
        #expect(SecurityCertificateStatus.valid.isUsable == true)
    }

    @Test("SecurityCertificateStatus expiringSoon is usable")
    func testCertificateStatusExpiringSoonUsable() {
        #expect(SecurityCertificateStatus.expiringSoon.isUsable == true)
    }

    @Test("SecurityCertificateStatus expired is not usable")
    func testCertificateStatusExpiredNotUsable() {
        #expect(SecurityCertificateStatus.expired.isUsable == false)
    }

    @Test("SecurityCertificateStatus revoked is not usable")
    func testCertificateStatusRevokedNotUsable() {
        #expect(SecurityCertificateStatus.revoked.isUsable == false)
    }

    @Test("SecurityCertificateStatus all cases have non-empty display names")
    func testCertificateStatusDisplayNames() {
        for status in SecurityCertificateStatus.allCases {
            #expect(!status.displayName.isEmpty)
        }
    }

    @Test("SecurityCertificateStatus all cases have non-empty SF symbols")
    func testCertificateStatusSFSymbols() {
        for status in SecurityCertificateStatus.allCases {
            #expect(!status.sfSymbol.isEmpty)
        }
    }

    // MARK: - SecurityCertificateEntry

    @Test("SecurityCertificateEntry status valid for future expiry")
    func testCertificateEntryStatusValid() {
        let entry = SecurityCertificateEntry(
            commonName: "example.com",
            notAfter: Date().addingTimeInterval(90 * 24 * 3600)
        )
        #expect(entry.status == .valid)
    }

    @Test("SecurityCertificateEntry status expiringSoon within 30 days")
    func testCertificateEntryStatusExpiringSoon() {
        let entry = SecurityCertificateEntry(
            commonName: "soon.com",
            notAfter: Date().addingTimeInterval(15 * 24 * 3600)
        )
        #expect(entry.status == .expiringSoon)
    }

    @Test("SecurityCertificateEntry status expired for past expiry")
    func testCertificateEntryStatusExpired() {
        let entry = SecurityCertificateEntry(
            commonName: "expired.com",
            notAfter: Date().addingTimeInterval(-1 * 24 * 3600)
        )
        #expect(entry.status == .expired)
    }

    @Test("SecurityCertificateEntry daysUntilExpiry positive for future")
    func testCertificateEntryDaysPositive() {
        let entry = SecurityCertificateEntry(
            commonName: "future.com",
            notAfter: Date().addingTimeInterval(60 * 24 * 3600)
        )
        #expect(entry.daysUntilExpiry > 0)
    }

    @Test("SecurityCertificateEntry daysUntilExpiry negative for past")
    func testCertificateEntryDaysNegative() {
        let entry = SecurityCertificateEntry(
            commonName: "past.com",
            notAfter: Date().addingTimeInterval(-60 * 24 * 3600)
        )
        #expect(entry.daysUntilExpiry < 0)
    }

    @Test("SecurityCertificateEntry default id is unique")
    func testCertificateEntryUniqueID() {
        let a = SecurityCertificateEntry(commonName: "a")
        let b = SecurityCertificateEntry(commonName: "b")
        #expect(a.id != b.id)
    }

    // MARK: - AnonymizationProfile

    @Test("AnonymizationProfile all cases have non-empty display names")
    func testAnonymizationProfileDisplayNames() {
        for profile in AnonymizationProfile.allCases {
            #expect(!profile.displayName.isEmpty)
        }
    }

    @Test("AnonymizationProfile all cases have non-empty short descriptions")
    func testAnonymizationProfileShortDescriptions() {
        for profile in AnonymizationProfile.allCases {
            #expect(!profile.shortDescription.isEmpty)
        }
    }

    @Test("AnonymizationProfile has 5 cases")
    func testAnonymizationProfileCaseCount() {
        #expect(AnonymizationProfile.allCases.count == 5)
    }

    // MARK: - TagAction

    @Test("TagAction all cases have non-empty display names")
    func testTagActionDisplayNames() {
        for action in TagAction.allCases {
            #expect(!action.displayName.isEmpty)
        }
    }

    @Test("TagAction all cases have non-empty SF symbols")
    func testTagActionSFSymbols() {
        for action in TagAction.allCases {
            #expect(!action.sfSymbol.isEmpty)
        }
    }

    @Test("TagAction has 6 cases")
    func testTagActionCaseCount() {
        #expect(TagAction.allCases.count == 6)
    }

    // MARK: - AnonymizationTagRule

    @Test("AnonymizationTagRule default action is remove")
    func testTagRuleDefaultAction() {
        let rule = AnonymizationTagRule(tag: "0010,0010")
        #expect(rule.action == .remove)
    }

    @Test("AnonymizationTagRule default id is unique")
    func testTagRuleUniqueID() {
        let a = AnonymizationTagRule(tag: "0010,0010")
        let b = AnonymizationTagRule(tag: "0010,0020")
        #expect(a.id != b.id)
    }

    // MARK: - AnonymizationStatus

    @Test("AnonymizationStatus completed is terminal")
    func testAnonymizationStatusCompletedIsTerminal() {
        #expect(AnonymizationStatus.completed.isTerminal == true)
    }

    @Test("AnonymizationStatus failed is terminal")
    func testAnonymizationStatusFailedIsTerminal() {
        #expect(AnonymizationStatus.failed.isTerminal == true)
    }

    @Test("AnonymizationStatus cancelled is terminal")
    func testAnonymizationStatusCancelledIsTerminal() {
        #expect(AnonymizationStatus.cancelled.isTerminal == true)
    }

    @Test("AnonymizationStatus running is not terminal")
    func testAnonymizationStatusRunningNotTerminal() {
        #expect(AnonymizationStatus.running.isTerminal == false)
    }

    @Test("AnonymizationStatus pending is not terminal")
    func testAnonymizationStatusPendingNotTerminal() {
        #expect(AnonymizationStatus.pending.isTerminal == false)
    }

    @Test("AnonymizationStatus all cases have non-empty display names")
    func testAnonymizationStatusDisplayNames() {
        for status in AnonymizationStatus.allCases {
            #expect(!status.displayName.isEmpty)
        }
    }

    // MARK: - AnonymizationJob

    @Test("AnonymizationJob progress is 0 when totalFiles is 0")
    func testAnonymizationJobProgressZeroFiles() {
        let job = AnonymizationJob()
        #expect(job.progress == 0.0)
    }

    @Test("AnonymizationJob progress is 0.5 when half processed")
    func testAnonymizationJobProgressHalf() {
        var job = AnonymizationJob(filePaths: ["a", "b"], totalFiles: 2, processedFiles: 1)
        job.totalFiles = 2
        #expect(job.progress == 0.5)
    }

    @Test("AnonymizationJob progress is 1.0 when fully processed")
    func testAnonymizationJobProgressFull() {
        var job = AnonymizationJob(totalFiles: 4, processedFiles: 4)
        job.totalFiles = 4
        #expect(job.progress == 1.0)
    }

    // MARK: - SecurityAuditEventType

    @Test("SecurityAuditEventType all cases have non-empty display names")
    func testAuditEventTypeDisplayNames() {
        for type_ in SecurityAuditEventType.allCases {
            #expect(!type_.displayName.isEmpty)
        }
    }

    @Test("SecurityAuditEventType all cases have non-empty SF symbols")
    func testAuditEventTypeSFSymbols() {
        for type_ in SecurityAuditEventType.allCases {
            #expect(!type_.sfSymbol.isEmpty)
        }
    }

    @Test("SecurityAuditEventType has 13 cases")
    func testAuditEventTypeCaseCount() {
        #expect(SecurityAuditEventType.allCases.count == 13)
    }

    // MARK: - SecurityAuditEntry

    @Test("SecurityAuditEntry default id is unique")
    func testAuditLogEntryUniqueID() {
        let a = SecurityAuditEntry(eventType: .fileAccess)
        let b = SecurityAuditEntry(eventType: .fileAccess)
        #expect(a.id != b.id)
    }

    @Test("SecurityAuditEntry default success is true")
    func testAuditLogEntryDefaultSuccess() {
        let entry = SecurityAuditEntry(eventType: .fileAccess)
        #expect(entry.success == true)
    }

    // MARK: - SecurityAuditExportFormat

    @Test("SecurityAuditExportFormat all cases have non-empty display names")
    func testAuditLogExportFormatDisplayNames() {
        for fmt in SecurityAuditExportFormat.allCases {
            #expect(!fmt.displayName.isEmpty)
        }
    }

    @Test("SecurityAuditExportFormat csv extension is csv")
    func testAuditLogExportFormatCSVExtension() {
        #expect(SecurityAuditExportFormat.csv.fileExtension == "csv")
    }

    @Test("SecurityAuditExportFormat json extension is json")
    func testAuditLogExportFormatJSONExtension() {
        #expect(SecurityAuditExportFormat.json.fileExtension == "json")
    }

    @Test("SecurityAuditExportFormat atna extension is xml")
    func testAuditLogExportFormatATNAExtension() {
        #expect(SecurityAuditExportFormat.atna.fileExtension == "xml")
    }

    // MARK: - SecurityAuditHandlerType

    @Test("SecurityAuditHandlerType all cases have non-empty display names")
    func testAuditLogHandlerTypeDisplayNames() {
        for handler in SecurityAuditHandlerType.allCases {
            #expect(!handler.displayName.isEmpty)
        }
    }

    @Test("SecurityAuditHandlerType all cases have non-empty SF symbols")
    func testAuditLogHandlerTypeSFSymbols() {
        for handler in SecurityAuditHandlerType.allCases {
            #expect(!handler.sfSymbol.isEmpty)
        }
    }

    // MARK: - SecurityAuditRetentionPolicy

    @Test("SecurityAuditRetentionPolicy indefinite has nil retention days")
    func testRetentionPolicyIndefiniteNil() {
        #expect(SecurityAuditRetentionPolicy.indefinite.retentionDays == nil)
    }

    @Test("SecurityAuditRetentionPolicy days30 has 30 retention days")
    func testRetentionPolicy30Days() {
        #expect(SecurityAuditRetentionPolicy.days30.retentionDays == 30)
    }

    @Test("SecurityAuditRetentionPolicy days365 has 365 retention days")
    func testRetentionPolicy365Days() {
        #expect(SecurityAuditRetentionPolicy.days365.retentionDays == 365)
    }

    @Test("SecurityAuditRetentionPolicy all cases have non-empty display names")
    func testRetentionPolicyDisplayNames() {
        for policy in SecurityAuditRetentionPolicy.allCases {
            #expect(!policy.displayName.isEmpty)
        }
    }

    // MARK: - UserRole

    @Test("UserRole all cases have non-empty display names")
    func testUserRoleDisplayNames() {
        for role in UserRole.allCases {
            #expect(!role.displayName.isEmpty)
        }
    }

    @Test("UserRole all cases have non-empty SF symbols")
    func testUserRoleSFSymbols() {
        for role in UserRole.allCases {
            #expect(!role.sfSymbol.isEmpty)
        }
    }

    @Test("UserRole superAdmin has highest privilege level")
    func testUserRoleSuperAdminHighest() {
        for role in UserRole.allCases where role != .superAdmin {
            #expect(UserRole.superAdmin.privilegeLevel > role.privilegeLevel)
        }
    }

    @Test("UserRole viewer has lowest privilege level")
    func testUserRoleViewerLowest() {
        for role in UserRole.allCases where role != .viewer {
            #expect(UserRole.viewer.privilegeLevel < role.privilegeLevel)
        }
    }

    @Test("UserRole has 4 cases")
    func testUserRoleCaseCount() {
        #expect(UserRole.allCases.count == 4)
    }

    // MARK: - SessionStatus

    @Test("SessionStatus active is usable")
    func testSessionStatusActiveUsable() {
        #expect(SessionStatus.active.isUsable == true)
    }

    @Test("SessionStatus idle is usable")
    func testSessionStatusIdleUsable() {
        #expect(SessionStatus.idle.isUsable == true)
    }

    @Test("SessionStatus locked is not usable")
    func testSessionStatusLockedNotUsable() {
        #expect(SessionStatus.locked.isUsable == false)
    }

    @Test("SessionStatus expired is not usable")
    func testSessionStatusExpiredNotUsable() {
        #expect(SessionStatus.expired.isUsable == false)
    }

    @Test("SessionStatus all cases have non-empty display names")
    func testSessionStatusDisplayNames() {
        for status in SessionStatus.allCases {
            #expect(!status.displayName.isEmpty)
        }
    }

    // MARK: - AccessControlSession

    @Test("AccessControlSession default role is viewer")
    func testAccessControlSessionDefaultRole() {
        let session = AccessControlSession(userName: "Alice")
        #expect(session.role == .viewer)
    }

    @Test("AccessControlSession default status is active")
    func testAccessControlSessionDefaultStatus() {
        let session = AccessControlSession(userName: "Alice")
        #expect(session.status == .active)
    }

    @Test("AccessControlSession isTimedOut false for fresh session")
    func testAccessControlSessionNotTimedOut() {
        let session = AccessControlSession(userName: "Bob", lastActivityAt: Date(), timeoutInterval: 3600)
        #expect(session.isTimedOut == false)
    }

    @Test("AccessControlSession isTimedOut true for old last activity")
    func testAccessControlSessionTimedOut() {
        let session = AccessControlSession(
            userName: "Charlie",
            lastActivityAt: Date().addingTimeInterval(-7200),
            timeoutInterval: 3600
        )
        #expect(session.isTimedOut == true)
    }

    // MARK: - BreakGlassEvent

    @Test("BreakGlassEvent default supervisorNotified is false")
    func testBreakGlassEventDefaultNotNotified() {
        let event = BreakGlassEvent(userName: "Admin")
        #expect(event.supervisorNotified == false)
    }

    @Test("BreakGlassEvent unique IDs")
    func testBreakGlassEventUniqueIDs() {
        let a = BreakGlassEvent(userName: "A")
        let b = BreakGlassEvent(userName: "B")
        #expect(a.id != b.id)
    }

    // MARK: - PermissionEntry

    @Test("PermissionEntry default rolePermissions is empty")
    func testPermissionEntryDefaultEmpty() {
        let entry = PermissionEntry(permission: "view")
        #expect(entry.rolePermissions.isEmpty)
    }

    // MARK: - PHIDetectionResult

    @Test("PHIDetectionResult equality based on id")
    func testPHIDetectionResultEquality() {
        let id = UUID()
        let a = PHIDetectionResult(id: id, filePath: "a.dcm")
        let b = PHIDetectionResult(id: id, filePath: "b.dcm")
        #expect(a == b)
    }

    @Test("PHIDetectionResult default hasPHI is false")
    func testPHIDetectionResultDefaultNoPHI() {
        let result = PHIDetectionResult(filePath: "test.dcm")
        #expect(result.hasPHI == false)
    }

    // MARK: - AnonymizationProfile ↔ dicom-anon --profile (PS3.15 2026a Annex E)

    /// Since 2026-10-01 (P-ANON-PROFILE) dicom-anon's `--profile basic` is the PS3.15 Basic
    /// Application Level Confidentiality Profile; the app's profiles are fixed attribute
    /// lists, which the CLI names `legacy-basic`, `legacy-clinical-trial`, `legacy-research`.
    @Test("AnonymizationProfile.cliFlag names the CLI's legacy list for every case, never the PS3.15 profile")
    func testAnonymizationProfileCLIFlagsAreLegacyLists() {
        let legacy: Set<String> = ["legacy-basic", "legacy-clinical-trial", "legacy-research"]
        for profile in AnonymizationProfile.allCases {
            #expect(legacy.contains(profile.cliFlag), Comment(rawValue: "\(profile) → \(profile.cliFlag)"))
            #expect(profile.cliFlag != "basic" && profile.cliFlag != "ps315")
        }
        #expect(AnonymizationProfile.basic.cliFlag == "legacy-basic")
        #expect(AnonymizationProfile.clinicalTrial.cliFlag == "legacy-clinical-trial")
        #expect(AnonymizationProfile.research.cliFlag == "legacy-research")
        #expect(AnonymizationProfile.hipaaeSafeHarbor.cliFlag == "legacy-basic")
        #expect(AnonymizationProfile.custom.cliFlag == "legacy-basic")
    }

    @Test("AnonHelpers.buildCommand always names --profile (the CLI default is ps315, not the app's list)")
    func testAnonCommandAlwaysNamesProfile() {
        for profile in AnonymizationProfile.allCases {
            let cmd = AnonHelpers.buildCommand(
                inputPath: "/in/a.dcm", outputPath: "/out/a.dcm", profile: profile,
                shiftDates: nil, regenerateUIDs: false, removeTags: [], replacePairs: [], keepTags: [],
                recursive: false, dryRun: false, backup: false, auditLogPath: "", force: false, verbose: false)
            #expect(cmd.contains(" --profile \(profile.cliFlag)"), Comment(rawValue: cmd))
            #expect(!cmd.contains(" --profile basic"), Comment(rawValue: cmd))
        }
    }
}
