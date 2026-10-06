// SecurityHelpersTests.swift
// DICOMStudioTests

import Testing
@testable import DICOMStudio
import Foundation
import DICOMKit

@Suite("Security Helpers Tests")
struct SecurityHelpersTests {

    // MARK: - SecurityTLSHelpers

    @Test("SecurityTLSHelpers riskLabel strict is high security")
    func testTLSHelpersRiskLabelStrict() {
        #expect(SecurityTLSHelpers.riskLabel(for: .strict).lowercased().contains("high"))
    }

    @Test("SecurityTLSHelpers riskLabel development contains 'not for production'")
    func testTLSHelpersRiskLabelDevelopment() {
        let label = SecurityTLSHelpers.riskLabel(for: .development)
        #expect(label.lowercased().contains("not for production") || label.lowercased().contains("development"))
    }

    @Test("SecurityTLSHelpers expiryDescription for future shows days")
    func testTLSHelpersExpiryDescriptionFuture() {
        let entry = SecurityCertificateEntry(
            commonName: "test",
            notAfter: Date().addingTimeInterval(10 * 24 * 3600)
        )
        let desc = SecurityTLSHelpers.expiryDescription(for: entry)
        #expect(desc.contains("day") || desc.contains("tomorrow") || desc.contains("month"))
    }

    @Test("SecurityTLSHelpers expiryDescription for past shows expired")
    func testTLSHelpersExpiryDescriptionExpired() {
        let entry = SecurityCertificateEntry(
            commonName: "old",
            notAfter: Date().addingTimeInterval(-5 * 24 * 3600)
        )
        let desc = SecurityTLSHelpers.expiryDescription(for: entry)
        #expect(desc.lowercased().contains("expired"))
    }

    @Test("SecurityTLSHelpers expiryDescription for today contains 'today'")
    func testTLSHelpersExpiryDescriptionToday() {
        let entry = SecurityCertificateEntry(
            commonName: "today",
            notAfter: Date().addingTimeInterval(3600)
        )
        let desc = SecurityTLSHelpers.expiryDescription(for: entry)
        #expect(desc.lowercased().contains("today") || desc.lowercased().contains("day"))
    }

    @Test("SecurityTLSHelpers shortFingerprint truncates long fingerprints")
    func testTLSHelpersShortFingerprintTruncates() {
        let fp = "a1b2c3d4e5f60001a1b2c3d4e5f60001a1b2c3d4e5f60001a1b2c3d4e5f60001"
        let short = SecurityTLSHelpers.shortFingerprint(fp)
        #expect(short.contains("..."))
        #expect(short.count < fp.count)
    }

    @Test("SecurityTLSHelpers shortFingerprint returns input for short strings")
    func testTLSHelpersShortFingerprintShort() {
        let fp = "abcdef01"
        let short = SecurityTLSHelpers.shortFingerprint(fp)
        #expect(short == fp)
    }

    @Test("SecurityTLSHelpers isValidFingerprint valid 64-char hex is valid")
    func testTLSHelpersValidFingerprint() {
        let fp = "a1b2c3d4e5f60001a1b2c3d4e5f60001a1b2c3d4e5f60001a1b2c3d4e5f60001"
        #expect(SecurityTLSHelpers.isValidFingerprint(fp) == true)
    }

    @Test("SecurityTLSHelpers isValidFingerprint with colons is valid")
    func testTLSHelpersValidFingerprintColons() {
        // 31 * "a1:" (93 chars) + "ab" (2 chars) → 93 - 31 + 2 = 64 hex chars after colon removal
        let colons = String(repeating: "a1:", count: 31) + "ab"
        #expect(SecurityTLSHelpers.isValidFingerprint(colons) == true)
    }

    @Test("SecurityTLSHelpers isValidFingerprint short string is invalid")
    func testTLSHelpersInvalidFingerprintShort() {
        #expect(SecurityTLSHelpers.isValidFingerprint("abcd") == false)
    }

    @Test("SecurityTLSHelpers isValidFingerprint non-hex is invalid")
    func testTLSHelpersInvalidFingerprintNonHex() {
        let fp = String(repeating: "z", count: 64)
        #expect(SecurityTLSHelpers.isValidFingerprint(fp) == false)
    }

    @Test("SecurityTLSHelpers pinnedHostnameValidationError nil for valid hostname")
    func testTLSHelpersPinnedHostnameValid() {
        #expect(SecurityTLSHelpers.pinnedHostnameValidationError(for: "pacs.hospital.com") == nil)
    }

    @Test("SecurityTLSHelpers pinnedHostnameValidationError not nil for empty hostname")
    func testTLSHelpersPinnedHostnameEmpty() {
        #expect(SecurityTLSHelpers.pinnedHostnameValidationError(for: "   ") != nil)
    }

    @Test("SecurityTLSHelpers colorName for valid is green")
    func testTLSHelpersColorNameValid() {
        #expect(SecurityTLSHelpers.colorName(for: .valid) == "green")
    }

    @Test("SecurityTLSHelpers colorName for expired is red")
    func testTLSHelpersColorNameExpired() {
        #expect(SecurityTLSHelpers.colorName(for: .expired) == "red")
    }

    @Test("SecurityTLSHelpers colorName for expiringSoon is orange")
    func testTLSHelpersColorNameExpiringSoon() {
        #expect(SecurityTLSHelpers.colorName(for: .expiringSoon) == "orange")
    }

    @Test("SecurityTLSHelpers securityLabel includes TLS mode")
    func testTLSHelpersSecurityLabel() {
        let server = SecurityServerEntry(serverName: "PACS", tlsMode: .strict)
        let label = SecurityTLSHelpers.securityLabel(for: server)
        #expect(label.contains("Strict") || label.contains("TLS"))
    }

    @Test("SecurityTLSHelpers securityLabel includes mTLS when enabled")
    func testTLSHelpersSecurityLabelMTLS() {
        let server = SecurityServerEntry(serverName: "PACS", tlsMode: .compatible, isMTLSEnabled: true)
        let label = SecurityTLSHelpers.securityLabel(for: server)
        #expect(label.contains("mTLS"))
    }

    @Test("SecurityTLSHelpers strongCipherSuites is not empty")
    func testTLSHelpersStrongCipherSuites() {
        #expect(!SecurityTLSHelpers.strongCipherSuites.isEmpty)
    }

    // MARK: - AnonymizationHelpers

    /// The DICOMKit `Anonymizer` `.basic` profile tags (Sources/DICOMKit/Anonymization/Anonymizer.swift
    /// basicProfileTags), with their PS3.6 2026a Table 6-1 names.
    static let engineBasicTags: [(String, String)] = [
        ("0010,0010", "Patient's Name"), ("0010,0020", "Patient ID"), ("0010,0030", "Patient's Birth Date"),
        ("0010,0032", "Patient's Birth Time"), ("0010,1000", "Other Patient IDs"), ("0010,1001", "Other Patient Names"),
        ("0010,4000", "Patient Comments"), ("0008,0090", "Referring Physician's Name"),
        ("0008,1050", "Performing Physician's Name"), ("0008,1070", "Operators' Name"), ("0008,0080", "Institution Name"),
        ("0008,0081", "Institution Address"), ("0008,1010", "Station Name"), ("0018,1000", "Device Serial Number"),
    ]

    @Test("AnonymizationHelpers basic list is the 14-attribute DICOMKit basic profile with Table 6-1 names")
    func testAnonymizationHelpersBasicListMatchesEngine() {
        let list = AnonymizationHelpers.basicProfileTags   // was hipaaDirectIdentifierTags (P-STUDIO-ANON-TAGLIST-NAME)
        #expect(list.count == 14)
        #expect(list.map { $0.tag } == Self.engineBasicTags.map { $0.0 })
        #expect(list.map { $0.name } == Self.engineBasicTags.map { $0.1 })
        // the tags the former "18 HIPAA identifiers" list named but the engine never removed are gone
        for gone in ["0010,0040", "0010,1010", "0010,1040", "0010,2160", "0010,21B0", "0008,0014", "0008,103E", "0032,1032"] {
            #expect(!list.contains { $0.tag == gone }, "\(gone)")
        }
    }

    /// P-STUDIO-ANON-TAGLIST-NAME: each legacy basic attribute is a row of PS3.15 2026a Table E.1-1
    /// (the engine's table is generated from the DocBook), yet the list is far short of the table.
    @Test("basicProfileTags: 14 rows of PS3.15 2026a Table E.1-1, not the whole table")
    func testBasicProfileTagsAreTableE11Rows() {
        for (tag, _) in AnonymizationHelpers.basicProfileTags {
            let parsed = Anonymizer.parseFlexibleTag(tag)
            #expect(parsed.map { ConfidentialityProfile.table[$0] != nil } == true, "\(tag)")
        }
        #expect(ConfidentialityProfile.table.count > 600)
    }

    @Test("AnonymizationHelpers defaultRules basic returns the 14 engine rules")
    func testAnonymizationHelpersDefaultRulesBasic() {
        let rules = AnonymizationHelpers.defaultRules(for: .basic)
        #expect(rules.count == 14)
        #expect(rules.allSatisfy { $0.action == .remove })
    }

    @Test("AnonymizationHelpers defaultRules hipaa returns the same 14 rules as basic (same engine profile)")
    func testAnonymizationHelpersDefaultRulesHIPAA() {
        let rules = AnonymizationHelpers.defaultRules(for: .hipaaeSafeHarbor)
        #expect(rules.count == 14)
        #expect(rules.map { $0.tag } == AnonymizationHelpers.defaultRules(for: .basic).map { $0.tag })
    }

    @Test("AnonymizationHelpers defaultRules clinicalTrial adds the 8 engine date/time tags")
    func testAnonymizationHelpersDefaultRulesClinicalTrial() {
        let rules = AnonymizationHelpers.defaultRules(for: .clinicalTrial)
        #expect(rules.count == 22)
        let dates = rules.dropFirst(14).map { $0.tag }
        #expect(dates == ["0008,0020", "0008,0021", "0008,0022", "0008,0023", "0008,0030", "0008,0031", "0008,0032", "0008,0033"])
        #expect(rules.first { $0.tag == "0008,0020" }?.tagName == "Study Date")
    }

    @Test("AnonymizationHelpers defaultRules custom returns empty")
    func testAnonymizationHelpersDefaultRulesCustomEmpty() {
        let rules = AnonymizationHelpers.defaultRules(for: .custom)
        #expect(rules.isEmpty)
    }

    @Test("AnonymizationHelpers tagValidationError nil for valid tag")
    func testAnonymizationHelpersTagValidNull() {
        #expect(AnonymizationHelpers.tagValidationError(for: "00100010") == nil)
    }

    @Test("AnonymizationHelpers tagValidationError nil for tag with comma")
    func testAnonymizationHelpersTagValidWithComma() {
        #expect(AnonymizationHelpers.tagValidationError(for: "0010,0010") == nil)
    }

    @Test("AnonymizationHelpers tagValidationError not nil for empty tag")
    func testAnonymizationHelpersTagValidationEmpty() {
        #expect(AnonymizationHelpers.tagValidationError(for: "") != nil)
    }

    @Test("AnonymizationHelpers tagValidationError not nil for non-hex tag")
    func testAnonymizationHelpersTagValidationNonHex() {
        #expect(AnonymizationHelpers.tagValidationError(for: "ZZZZZZZZ") != nil)
    }

    @Test("AnonymizationHelpers tagValidationError not nil for too short tag")
    func testAnonymizationHelpersTagValidationShort() {
        #expect(AnonymizationHelpers.tagValidationError(for: "0010") != nil)
    }

    @Test("AnonymizationHelpers formatTag produces parenthesized format")
    func testAnonymizationHelpersFormatTag() {
        let formatted = AnonymizationHelpers.formatTag("00100010")
        #expect(formatted == "(0010,0010)")
    }

    @Test("AnonymizationHelpers formatTag accepts comma-separated input")
    func testAnonymizationHelpersFormatTagComma() {
        let formatted = AnonymizationHelpers.formatTag("0010,0010")
        #expect(formatted == "(0010,0010)")
    }

    @Test("AnonymizationHelpers progressText pending shows waiting")
    func testAnonymizationHelpersProgressTextPending() {
        let job = AnonymizationJob(status: .pending)
        let text = AnonymizationHelpers.progressText(for: job)
        #expect(text.lowercased().contains("wait"))
    }

    @Test("AnonymizationHelpers progressText running shows file counts")
    func testAnonymizationHelpersProgressTextRunning() {
        var job = AnonymizationJob(filePaths: ["a", "b", "c"], status: .running, totalFiles: 3, processedFiles: 1)
        job.totalFiles = 3
        let text = AnonymizationHelpers.progressText(for: job)
        #expect(text.contains("1") && text.contains("3"))
    }

    @Test("AnonymizationHelpers progressText completed shows completed")
    func testAnonymizationHelpersProgressTextCompleted() {
        var job = AnonymizationJob(status: .completed, totalFiles: 5, processedFiles: 5)
        job.totalFiles = 5
        let text = AnonymizationHelpers.progressText(for: job)
        #expect(text.lowercased().contains("completed"))
    }

    @Test("AnonymizationHelpers previewSummary empty rules returns no rules message")
    func testAnonymizationHelpersPreviewSummaryEmpty() {
        let summary = AnonymizationHelpers.previewSummary(rules: [])
        #expect(summary.lowercased().contains("no rule"))
    }

    @Test("AnonymizationHelpers previewSummary non-empty returns rule counts")
    func testAnonymizationHelpersPreviewSummaryNonEmpty() {
        let rules = [
            AnonymizationTagRule(tag: "0010,0010", action: .remove),
            AnonymizationTagRule(tag: "0010,0020", action: .hash)
        ]
        let summary = AnonymizationHelpers.previewSummary(rules: rules)
        #expect(!summary.isEmpty)
    }

    @Test("AnonymizationHelpers isValidDateShift 365 is valid")
    func testAnonymizationHelpersDateShiftValid() {
        #expect(AnonymizationHelpers.isValidDateShift(365) == true)
    }

    @Test("AnonymizationHelpers isValidDateShift negative 365 is valid")
    func testAnonymizationHelpersDateShiftNegativeValid() {
        #expect(AnonymizationHelpers.isValidDateShift(-365) == true)
    }

    @Test("AnonymizationHelpers isValidDateShift 99999 is invalid")
    func testAnonymizationHelpersDateShiftInvalid() {
        #expect(AnonymizationHelpers.isValidDateShift(99999) == false)
    }

    // MARK: - SecurityAuditHelpers

    @Test("SecurityAuditHelpers formattedTimestamp produces non-empty string")
    func testAuditLogHelpersFormattedTimestamp() {
        let timestamp = SecurityAuditHelpers.formattedTimestamp(Date())
        #expect(!timestamp.isEmpty)
    }

    @Test("SecurityAuditHelpers entry inRange returns true for matching date")
    func testAuditLogHelpersEntryInRange() {
        let now = Date()
        let entry = SecurityAuditEntry(timestamp: now, eventType: .fileAccess)
        let range = now.addingTimeInterval(-60)...now.addingTimeInterval(60)
        #expect(SecurityAuditHelpers.entry(entry, isInRange: range) == true)
    }

    @Test("SecurityAuditHelpers entry inRange returns false for out-of-range date")
    func testAuditLogHelpersEntryOutOfRange() {
        let now = Date()
        let old = now.addingTimeInterval(-3600)
        let entry = SecurityAuditEntry(timestamp: old, eventType: .fileAccess)
        let range = now.addingTimeInterval(-60)...now.addingTimeInterval(60)
        #expect(SecurityAuditHelpers.entry(entry, isInRange: range) == false)
    }

    @Test("SecurityAuditHelpers filter byType returns only matching entries")
    func testAuditLogHelpersFilterByType() {
        let entries = [
            SecurityAuditEntry(eventType: .fileAccess),
            SecurityAuditEntry(eventType: .networkSend),
            SecurityAuditEntry(eventType: .fileAccess)
        ]
        let filtered = SecurityAuditHelpers.filter(entries, byType: .fileAccess)
        #expect(filtered.count == 2)
    }

    @Test("SecurityAuditHelpers filter byUser returns matching entries")
    func testAuditLogHelpersFilterByUser() {
        let entries = [
            SecurityAuditEntry(eventType: .fileAccess, userIdentity: "alice"),
            SecurityAuditEntry(eventType: .fileAccess, userIdentity: "bob"),
            SecurityAuditEntry(eventType: .fileAccess, userIdentity: "Alice Smith")
        ]
        let filtered = SecurityAuditHelpers.filter(entries, byUser: "alice")
        #expect(filtered.count == 2)
    }

    @Test("SecurityAuditHelpers filter byUser empty string returns all entries")
    func testAuditLogHelpersFilterByUserEmpty() {
        let entries = [
            SecurityAuditEntry(eventType: .fileAccess, userIdentity: "alice"),
            SecurityAuditEntry(eventType: .fileAccess, userIdentity: "bob")
        ]
        let filtered = SecurityAuditHelpers.filter(entries, byUser: "")
        #expect(filtered.count == 2)
    }

    @Test("SecurityAuditHelpers filter byReference returns matching entries")
    func testAuditLogHelpersFilterByReference() {
        let entries = [
            SecurityAuditEntry(eventType: .fileAccess, patientReference: "PAT001"),
            SecurityAuditEntry(eventType: .fileAccess, patientReference: "PAT002"),
            SecurityAuditEntry(eventType: .fileAccess, studyReference: "1.2.3.PAT001")
        ]
        let filtered = SecurityAuditHelpers.filter(entries, byReference: "PAT001")
        #expect(filtered.count == 2)
    }

    @Test("SecurityAuditHelpers toCSV produces non-empty string with header")
    func testAuditLogHelpersToCSV() {
        let entries = [SecurityAuditEntry(eventType: .fileAccess, userIdentity: "admin")]
        let csv = SecurityAuditHelpers.toCSV(entries)
        #expect(csv.contains("Timestamp"))
        #expect(csv.contains("EventType"))
        #expect(csv.contains("admin"))
    }

    @Test("SecurityAuditHelpers toCSV escapes commas in values")
    func testAuditLogHelpersToCSVEscapesCommas() {
        let entry = SecurityAuditEntry(eventType: .fileAccess, userIdentity: "Smith, John")
        let csv = SecurityAuditHelpers.toCSV([entry])
        #expect(csv.contains("\"Smith, John\""))
    }

    @Test("SecurityAuditHelpers toJSONDictionaries produces correct entries")
    func testAuditLogHelpersToJSONDictionaries() {
        let entries = [SecurityAuditEntry(eventType: .fileAccess, userIdentity: "alice")]
        let dicts = SecurityAuditHelpers.toJSONDictionaries(entries)
        #expect(dicts.count == 1)
        #expect(dicts[0]["eventType"] == "FILE_ACCESS")
        #expect(dicts[0]["userIdentity"] == "alice")
    }

    @Test("SecurityAuditHelpers statistics counts event types correctly")
    func testAuditLogHelpersStatistics() {
        let entries = [
            SecurityAuditEntry(eventType: .fileAccess),
            SecurityAuditEntry(eventType: .fileAccess),
            SecurityAuditEntry(eventType: .networkSend)
        ]
        let stats = SecurityAuditHelpers.statistics(entries)
        #expect(stats[.fileAccess] == 2)
        #expect(stats[.networkSend] == 1)
    }

    @Test("SecurityAuditHelpers applyRetentionPolicy removes old entries")
    func testAuditLogHelpersApplyRetentionPolicyRemovesOld() {
        let old = SecurityAuditEntry(
            timestamp: Date().addingTimeInterval(-60 * 24 * 3600),
            eventType: .fileAccess
        )
        let recent = SecurityAuditEntry(
            timestamp: Date().addingTimeInterval(-1 * 24 * 3600),
            eventType: .fileAccess
        )
        let result = SecurityAuditHelpers.applyRetentionPolicy([old, recent], policy: .days30)
        #expect(result.count == 1)
        #expect(result[0].id == recent.id)
    }

    @Test("SecurityAuditHelpers applyRetentionPolicy indefinite keeps all entries")
    func testAuditLogHelpersApplyRetentionPolicyIndefinite() {
        let old = SecurityAuditEntry(
            timestamp: Date().addingTimeInterval(-3650 * 24 * 3600),
            eventType: .fileAccess
        )
        let result = SecurityAuditHelpers.applyRetentionPolicy([old], policy: .indefinite)
        #expect(result.count == 1)
    }

    // MARK: - AccessControlHelpers

    @Test("AccessControlHelpers viewer can view")
    func testAccessControlHelpersViewerCanView() {
        #expect(AccessControlHelpers.hasPermission(.viewer, for: "view") == true)
    }

    @Test("AccessControlHelpers viewer cannot delete")
    func testAccessControlHelpersViewerCannotDelete() {
        #expect(AccessControlHelpers.hasPermission(.viewer, for: "delete") == false)
    }

    @Test("AccessControlHelpers clinician can import")
    func testAccessControlHelpersClinicianCanImport() {
        #expect(AccessControlHelpers.hasPermission(.clinician, for: "import") == true)
    }

    @Test("AccessControlHelpers clinician cannot manage users")
    func testAccessControlHelpersClinicianCannotManageUsers() {
        #expect(AccessControlHelpers.hasPermission(.clinician, for: "manageUsers") == false)
    }

    @Test("AccessControlHelpers admin can manage users")
    func testAccessControlHelpersAdminCanManageUsers() {
        #expect(AccessControlHelpers.hasPermission(.admin, for: "manageUsers") == true)
    }

    @Test("AccessControlHelpers admin cannot system config")
    func testAccessControlHelpersAdminCannotSystemConfig() {
        #expect(AccessControlHelpers.hasPermission(.admin, for: "systemConfig") == false)
    }

    @Test("AccessControlHelpers superAdmin can do system config")
    func testAccessControlHelpersSuperAdminSystemConfig() {
        #expect(AccessControlHelpers.hasPermission(.superAdmin, for: "systemConfig") == true)
    }

    @Test("AccessControlHelpers unknown action returns false")
    func testAccessControlHelpersUnknownAction() {
        #expect(AccessControlHelpers.hasPermission(.superAdmin, for: "unknownAction") == false)
    }

    @Test("AccessControlHelpers standardPermissionMatrix returns 8 entries")
    func testAccessControlHelpersPermissionMatrixCount() {
        let matrix = AccessControlHelpers.standardPermissionMatrix()
        #expect(matrix.count == 8)
    }

    @Test("AccessControlHelpers standardPermissionMatrix all have non-empty permissions")
    func testAccessControlHelpersPermissionMatrixNonEmpty() {
        let matrix = AccessControlHelpers.standardPermissionMatrix()
        for entry in matrix {
            #expect(!entry.permission.isEmpty)
            #expect(!entry.description.isEmpty)
        }
    }

    @Test("AccessControlHelpers remainingSessionTime nil for timed out session")
    func testAccessControlHelpersRemainingTimeNilForTimedOut() {
        let session = AccessControlSession(
            userName: "Alice",
            lastActivityAt: Date().addingTimeInterval(-7200),
            timeoutInterval: 3600
        )
        #expect(AccessControlHelpers.remainingSessionTime(for: session) == nil)
    }

    @Test("AccessControlHelpers remainingSessionTime positive for active session")
    func testAccessControlHelpersRemainingTimePositive() {
        let session = AccessControlSession(
            userName: "Bob",
            lastActivityAt: Date(),
            timeoutInterval: 3600
        )
        let remaining = AccessControlHelpers.remainingSessionTime(for: session)
        #expect(remaining != nil)
        #expect(remaining! > 0)
    }

    @Test("AccessControlHelpers sessionDurationText returns non-empty string")
    func testAccessControlHelpersSessionDurationText() {
        let session = AccessControlSession(
            userName: "Carol",
            startedAt: Date().addingTimeInterval(-600)
        )
        let text = AccessControlHelpers.sessionDurationText(for: session)
        #expect(!text.isEmpty)
    }

    @Test("AccessControlHelpers scopeSummary empty returns 'No scopes'")
    func testAccessControlHelpersScopeSummaryEmpty() {
        #expect(AccessControlHelpers.scopeSummary([]) == "No scopes")
    }

    @Test("AccessControlHelpers scopeSummary with 2 scopes returns them joined")
    func testAccessControlHelpersScopeSummaryTwo() {
        let summary = AccessControlHelpers.scopeSummary(["openid", "profile"])
        #expect(summary.contains("openid"))
        #expect(summary.contains("profile"))
    }

    @Test("AccessControlHelpers scopeSummary with 5 scopes truncates to 3 + more")
    func testAccessControlHelpersScopeSummaryTruncated() {
        let scopes = ["a", "b", "c", "d", "e"]
        let summary = AccessControlHelpers.scopeSummary(scopes)
        #expect(summary.contains("+2 more"))
    }
}
