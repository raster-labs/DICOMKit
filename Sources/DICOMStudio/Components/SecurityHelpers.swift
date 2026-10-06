// SecurityHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent helpers for the Security & Privacy Center display
// Reference: DICOM PS3.15 (Security and System Management Profiles), B.12 / B.13 (TLS); HIPAA Security Rule §164.312 (law)
// NEMA-verified: 2026a, checked 2026-10-05 — the anonymization preview lists are diffed by script against the DICOMKit Anonymizer profiles the app runs (basic 14 attributes, clinical trial + 8 date/time attributes, research 3) and their names against PS3.6 2026a Table 6-1 (22/22); the former "18 HIPAA direct identifiers" list named 18 tags of which the engine removed 7 (45 CFR §164.514(b)(2)(i) lists identifier categories, not DICOM attributes, and none of these profiles is PS3.15 Annex E); the 3 cipher suites shown are PS3.15 2026a B.13 TLS 1.3 suites (3/3); the rest is display formatting
// NEMA-verified: 2026a, checked 2026-10-06 — basicProfileTags (renamed from hipaaDirectIdentifierTags, deprecated; P-STUDIO-ANON-TAGLIST-NAME): its 14 tags compared by script with PS3.15 2026a Table E.1-1 (14/14 are rows of the table; the list is not the table, which --profile ps315 applies whole)

import Foundation

// MARK: - TLS Helpers

/// Platform-independent helpers for TLS configuration display and validation.
public enum SecurityTLSHelpers: Sendable {

    /// TLS 1.3 cipher suites for display: three of the five PS3.15 B.13 (Modified BCP 195) suites
    /// every server shall support.
    public static let strongCipherSuites: [String] = [
        "TLS_AES_256_GCM_SHA384",
        "TLS_CHACHA20_POLY1305_SHA256",
        "TLS_AES_128_GCM_SHA256"
    ]

    /// Returns a risk label for a TLS mode.
    public static func riskLabel(for mode: SecurityTLSMode) -> String {
        switch mode {
        case .strict:      return "High Security"
        case .compatible:  return "Standard Security"
        case .development: return "Development Only — Not for Production"
        }
    }

    /// Returns a human-readable description of the certificate expiry.
    public static func expiryDescription(for entry: SecurityCertificateEntry) -> String {
        let days = entry.daysUntilExpiry
        if days < 0 {
            return "Expired \(abs(days)) day(s) ago"
        } else if days == 0 {
            return "Expires today"
        } else if days == 1 {
            return "Expires tomorrow"
        } else if days <= 30 {
            return "Expires in \(days) days"
        } else {
            return "Expires in \(days / 30) month(s)"
        }
    }

    /// Returns a short fingerprint for display (first 16 hex chars + "...").
    public static func shortFingerprint(_ fingerprint: String) -> String {
        let clean = fingerprint.replacingOccurrences(of: ":", with: "")
        guard clean.count >= 16 else { return fingerprint }
        return String(clean.prefix(16)) + "..."
    }

    /// Returns true if the fingerprint string looks like a valid SHA-256 fingerprint.
    public static func isValidFingerprint(_ fingerprint: String) -> Bool {
        let clean = fingerprint.replacingOccurrences(of: ":", with: "")
        return clean.count == 64 && clean.allSatisfy { $0.isHexDigit }
    }

    /// Returns validation error for a pinned hostname, or nil if valid.
    public static func pinnedHostnameValidationError(for hostname: String) -> String? {
        if hostname.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Hostname must not be empty."
        }
        let parts = hostname.split(separator: ".").map(String.init)
        if parts.isEmpty {
            return "Hostname must contain at least one label."
        }
        return nil
    }

    /// Returns the security indicator color name for a certificate status.
    public static func colorName(for status: SecurityCertificateStatus) -> String {
        switch status {
        case .valid:        return "green"
        case .expiringSoon: return "orange"
        case .expired:      return "red"
        case .missing:      return "gray"
        case .untrusted:    return "red"
        case .revoked:      return "red"
        }
    }

    /// Returns the overall security level label for a server.
    public static func securityLabel(for server: SecurityServerEntry) -> String {
        var parts: [String] = [server.tlsMode.displayName]
        if server.isMTLSEnabled { parts.append("mTLS") }
        if server.isPinningEnabled { parts.append("Pinned") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Anonymization Helpers

/// Platform-independent helpers for anonymization display and validation.
public enum AnonymizationHelpers: Sendable {

    /// The attributes the Basic profile removes: exactly the DICOMKit `Anonymizer` `.basic` profile
    /// (`--profile legacy-basic`), which the app runs through `SecurityViewModel.engineProfile`.
    /// Names are the PS3.6 Table 6-1 names. This is the app's fixed list, not a PS3.15 Annex E profile
    /// and not the 18 identifier categories of 45 CFR §164.514(b)(2)(i) (which name kinds of
    /// information, not DICOM attributes).
    ///
    /// Public since P-STUDIO-ANON-TAGLIST-NAME (2026-10-06), replacing `hipaaDirectIdentifierTags`.
    /// Each of the 14 attributes is a row of PS3.15 2026a Table E.1-1 (checked by script against
    /// the DocBook, 14/14), but the list is not that table: `--profile ps315` (the
    /// `.ps315` profile) applies every row.
    public static let basicProfileTags: [(tag: String, name: String)] = [
        ("0010,0010", "Patient's Name"),
        ("0010,0020", "Patient ID"),
        ("0010,0030", "Patient's Birth Date"),
        ("0010,0032", "Patient's Birth Time"),
        ("0010,1000", "Other Patient IDs"),
        ("0010,1001", "Other Patient Names"),
        ("0010,4000", "Patient Comments"),
        ("0008,0090", "Referring Physician's Name"),
        ("0008,1050", "Performing Physician's Name"),
        ("0008,1070", "Operators' Name"),
        ("0008,0080", "Institution Name"),
        ("0008,0081", "Institution Address"),
        ("0008,1010", "Station Name"),
        ("0018,1000", "Device Serial Number"),
    ]

    /// The date and time attributes the Clinical Trial profile removes in addition to
    /// `basicProfileTags` (DICOMKit `Anonymizer` `.clinicalTrial`, `--profile legacy-clinical-trial`).
    static let clinicalTrialDateTags: [(tag: String, name: String)] = [
        ("0008,0020", "Study Date"),
        ("0008,0021", "Series Date"),
        ("0008,0022", "Acquisition Date"),
        ("0008,0023", "Content Date"),
        ("0008,0030", "Study Time"),
        ("0008,0031", "Series Time"),
        ("0008,0032", "Acquisition Time"),
        ("0008,0033", "Content Time"),
    ]

    /// The (tag, name) pairs the Basic and HIPAA Safe Harbor profiles remove: `basicProfileTags`.
    ///
    /// The name is historical: the list is the engine's basic profile (14 attributes), not the 18
    /// identifier categories of 45 CFR §164.514(b)(2)(i), which the earlier 18-tag list did not
    /// implement either (the engine removed only 7 of those tags). Deprecated, renamed
    /// `basicProfileTags` (P-STUDIO-ANON-TAGLIST-NAME, 2026-10-06); kept for source compatibility.
    @available(*, deprecated, renamed: "basicProfileTags")
    public static let hipaaDirectIdentifierTags: [(tag: String, name: String)] = basicProfileTags

    /// Returns the default rules for an anonymization profile: the attributes the DICOMKit
    /// `Anonymizer` profile the app runs for it removes (so the preview matches the output).
    ///
    /// `.ps315` returns no rules: the PS3.15 Basic Profile is every row of PS3.15 2026a Table E.1-1
    /// with per-row actions (D, Z, X, U, C) and option columns, which a remove-only tag list cannot
    /// state; the engine's table (DICOMKit `ConfidentialityProfile.table`) is the reference.
    public static func defaultRules(for profile: AnonymizationProfile) -> [AnonymizationTagRule] {
        switch profile {
        case .ps315:
            return []
        case .basic, .hipaaeSafeHarbor:
            return basicProfileTags.map { tagPair in
                AnonymizationTagRule(
                    tag: tagPair.tag,
                    tagName: tagPair.name,
                    action: .remove
                )
            }
        case .clinicalTrial:
            return (basicProfileTags + clinicalTrialDateTags).map { tagPair in
                AnonymizationTagRule(
                    tag: tagPair.tag,
                    tagName: tagPair.name,
                    action: .remove
                )
            }
        case .research:
            return [
                AnonymizationTagRule(tag: "0010,0010", tagName: "Patient Name", action: .remove),
                AnonymizationTagRule(tag: "0010,0020", tagName: "Patient ID", action: .remove),
                AnonymizationTagRule(tag: "0010,0030", tagName: "Patient Birth Date", action: .remove),
            ]
        case .custom:
            return []
        }
    }

    /// Returns a validation error for a tag string, or nil if valid.
    public static func tagValidationError(for tag: String) -> String? {
        let cleaned = tag.replacingOccurrences(of: ",", with: "")
                        .replacingOccurrences(of: "(", with: "")
                        .replacingOccurrences(of: ")", with: "")
                        .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { return "Tag must not be empty." }
        if cleaned.count != 8 { return "Tag must be 8 hex characters (e.g. 00100010)." }
        if !cleaned.allSatisfy({ $0.isHexDigit }) { return "Tag must contain only hex characters." }
        return nil
    }

    /// Returns a formatted tag string in (gggg,eeee) notation.
    public static func formatTag(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
                        .replacingOccurrences(of: "(", with: "")
                        .replacingOccurrences(of: ")", with: "")
                        .uppercased()
        guard cleaned.count == 8 else { return raw.uppercased() }
        let group = String(cleaned.prefix(4))
        let element = String(cleaned.suffix(4))
        return "(\(group),\(element))"
    }

    /// Returns progress text for an anonymization job.
    public static func progressText(for job: AnonymizationJob) -> String {
        switch job.status {
        case .pending:
            return "Waiting to start"
        case .running:
            return "\(job.processedFiles) of \(job.totalFiles) files"
        case .completed:
            if job.failedFiles > 0 {
                return "Completed with \(job.failedFiles) error(s)"
            }
            return "Completed (\(job.totalFiles) files)"
        case .failed:
            return "Failed: \(job.errorMessage ?? "Unknown error")"
        case .cancelled:
            return "Cancelled after \(job.processedFiles) files"
        }
    }

    /// Returns a summary for the before/after preview of a rule set.
    public static func previewSummary(rules: [AnonymizationTagRule]) -> String {
        let counts = rules.reduce(into: [TagAction: Int]()) { acc, rule in
            acc[rule.action, default: 0] += 1
        }
        let parts = counts.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.value) \($0.key.displayName)" }
        if parts.isEmpty { return "No rules defined" }
        return parts.joined(separator: ", ")
    }

    /// Returns true if the date shift value is within a safe range.
    public static func isValidDateShift(_ days: Int) -> Bool {
        days >= -3650 && days <= 3650
    }
}

// MARK: - Audit Log Helpers

/// Platform-independent helpers for audit log display and export.
public enum SecurityAuditHelpers: Sendable {

    /// ISO 8601 date-time formatter for audit log timestamps.
    nonisolated(unsafe) public static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withTimeZone]
        return f
    }()

    /// Returns a formatted timestamp string for display.
    public static func formattedTimestamp(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    /// Returns true if the entry's timestamp falls within the given date range.
    public static func entry(_ entry: SecurityAuditEntry, isInRange range: ClosedRange<Date>) -> Bool {
        range.contains(entry.timestamp)
    }

    /// Filters entries by event type.
    public static func filter(_ entries: [SecurityAuditEntry], byType type: SecurityAuditEventType) -> [SecurityAuditEntry] {
        entries.filter { $0.eventType == type }
    }

    /// Filters entries by user identity (case-insensitive substring match).
    public static func filter(_ entries: [SecurityAuditEntry], byUser user: String) -> [SecurityAuditEntry] {
        guard !user.isEmpty else { return entries }
        return entries.filter { $0.userIdentity.localizedCaseInsensitiveContains(user) }
    }

    /// Filters entries by patient or study reference (case-insensitive substring match).
    public static func filter(_ entries: [SecurityAuditEntry], byReference ref: String) -> [SecurityAuditEntry] {
        guard !ref.isEmpty else { return entries }
        return entries.filter {
            $0.patientReference.localizedCaseInsensitiveContains(ref) ||
            $0.studyReference.localizedCaseInsensitiveContains(ref)
        }
    }

    /// Converts a list of entries to CSV text.
    public static func toCSV(_ entries: [SecurityAuditEntry]) -> String {
        let header = "ID,Timestamp,EventType,User,Patient,Study,Description,Success,SourceHost"
        let rows = entries.map { e in
            [
                e.id.uuidString,
                formattedTimestamp(e.timestamp),
                e.eventType.rawValue,
                csvEscape(e.userIdentity),
                csvEscape(e.patientReference),
                csvEscape(e.studyReference),
                csvEscape(e.description),
                e.success ? "true" : "false",
                csvEscape(e.sourceHost)
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    /// Converts a list of entries to a JSON-serializable array of dictionaries.
    public static func toJSONDictionaries(_ entries: [SecurityAuditEntry]) -> [[String: String]] {
        entries.map { e in
            [
                "id": e.id.uuidString,
                "timestamp": formattedTimestamp(e.timestamp),
                "eventType": e.eventType.rawValue,
                "userIdentity": e.userIdentity,
                "patientReference": e.patientReference,
                "studyReference": e.studyReference,
                "description": e.description,
                "success": e.success ? "true" : "false",
                "sourceHost": e.sourceHost
            ]
        }
    }

    /// Returns statistics about the entries (counts per event type).
    public static func statistics(_ entries: [SecurityAuditEntry]) -> [SecurityAuditEventType: Int] {
        entries.reduce(into: [SecurityAuditEventType: Int]()) { acc, entry in
            acc[entry.eventType, default: 0] += 1
        }
    }

    /// Applies the retention policy by removing entries older than the cutoff.
    public static func applyRetentionPolicy(
        _ entries: [SecurityAuditEntry],
        policy: SecurityAuditRetentionPolicy
    ) -> [SecurityAuditEntry] {
        guard let days = policy.retentionDays else { return entries }
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        return entries.filter { $0.timestamp > cutoff }
    }
}

// MARK: - Access Control Helpers

/// Platform-independent helpers for access control display and session management.
public enum AccessControlHelpers: Sendable {

    /// Returns whether a role has permission to perform the given action.
    public static func hasPermission(_ role: UserRole, for action: String) -> Bool {
        switch action {
        case "view":          return true // all roles can view
        case "import":        return role.privilegeLevel >= UserRole.clinician.privilegeLevel
        case "export":        return role.privilegeLevel >= UserRole.clinician.privilegeLevel
        case "anonymize":     return role.privilegeLevel >= UserRole.clinician.privilegeLevel
        case "delete":        return role.privilegeLevel >= UserRole.admin.privilegeLevel
        case "manageUsers":   return role.privilegeLevel >= UserRole.admin.privilegeLevel
        case "viewAuditLog":  return role.privilegeLevel >= UserRole.admin.privilegeLevel
        case "systemConfig":  return role.privilegeLevel >= UserRole.superAdmin.privilegeLevel
        default:              return false
        }
    }

    /// Returns the standard permission matrix entries.
    public static func standardPermissionMatrix() -> [PermissionEntry] {
        let actions: [(permission: String, description: String)] = [
            ("view",          "View DICOM studies and images"),
            ("import",        "Import DICOM files"),
            ("export",        "Export and download studies"),
            ("anonymize",     "Run anonymization jobs"),
            ("delete",        "Delete studies and series"),
            ("manageUsers",   "Manage user accounts and roles"),
            ("viewAuditLog",  "Access the audit log"),
            ("systemConfig",  "System-wide configuration")
        ]
        return actions.map { action in
            let rolePerms = UserRole.allCases.reduce(into: [UserRole: Bool]()) { acc, role in
                acc[role] = hasPermission(role, for: action.permission)
            }
            return PermissionEntry(
                permission: action.permission,
                description: action.description,
                rolePermissions: rolePerms
            )
        }
    }

    /// Returns the remaining idle time (in seconds) before session timeout, or nil if already expired.
    public static func remainingSessionTime(for session: AccessControlSession) -> TimeInterval? {
        let elapsed = Date().timeIntervalSince(session.lastActivityAt)
        let remaining = session.timeoutInterval - elapsed
        return remaining > 0 ? remaining : nil
    }

    /// Returns a human-readable session duration string.
    public static func sessionDurationText(for session: AccessControlSession) -> String {
        let duration = Date().timeIntervalSince(session.startedAt)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Returns a short JWT scope summary for display.
    public static func scopeSummary(_ scopes: [String]) -> String {
        if scopes.isEmpty { return "No scopes" }
        if scopes.count <= 3 { return scopes.joined(separator: ", ") }
        return "\(scopes.prefix(3).joined(separator: ", ")) +\(scopes.count - 3) more"
    }
}
