// SecurityModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for the Security & Privacy Center (Milestone 11)
// Reference: DICOM PS3.15 (Security and System Management Profiles)
// Reference: HIPAA Security Rule §164.312

import Foundation

// MARK: - Navigation Tab

/// Navigation tabs for the Security & Privacy Center.
public enum SecurityTab: String, Sendable, Equatable, Hashable, CaseIterable {
    case tlsConfiguration = "TLS_CONFIGURATION"
    case anonymization    = "ANONYMIZATION"
    case auditLog         = "AUDIT_LOG"
    case accessControl    = "ACCESS_CONTROL"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .tlsConfiguration: return "TLS / Certificates"
        case .anonymization:    return "Anonymization"
        case .auditLog:         return "Audit Log"
        case .accessControl:    return "Access Control"
        }
    }

    /// SF Symbol name for this tab.
    public var sfSymbol: String {
        switch self {
        case .tlsConfiguration: return "lock.shield"
        case .anonymization:    return "person.crop.circle.badge.minus"
        case .auditLog:         return "list.clipboard"
        case .accessControl:    return "person.badge.key"
        }
    }
}

// MARK: - TLS Mode

/// TLS security mode for network connections.
/// Reference: DICOM PS3.15 Annex B – Secure Transport Connection Profiles
public enum SecurityTLSMode: String, Sendable, Equatable, Hashable, CaseIterable {
    case strict      = "STRICT"
    case compatible  = "COMPATIBLE"
    case development = "DEVELOPMENT"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .strict:      return "Strict (TLS 1.3 only)"
        case .compatible:  return "Compatible (TLS 1.2+)"
        case .development: return "Development (Allow Self-Signed)"
        }
    }

    /// Short description.
    public var shortDescription: String {
        switch self {
        case .strict:      return "TLS 1.3 only, certificate pinning required"
        case .compatible:  return "TLS 1.2 or higher, standard validation"
        case .development: return "Self-signed and untrusted certificates accepted"
        }
    }

    /// Whether self-signed certificates are accepted.
    public var allowsSelfSigned: Bool { self == .development }

    /// Minimum TLS version string.
    public var minimumTLSVersion: String {
        switch self {
        case .strict:      return "TLS 1.3"
        case .compatible:  return "TLS 1.2"
        case .development: return "TLS 1.0"
        }
    }

    /// Whether this mode is production-safe.
    public var isProductionSafe: Bool { self != .development }
}

// MARK: - Certificate Status

/// Status of a TLS certificate.
public enum SecurityCertificateStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case valid        = "VALID"
    case expiringSoon = "EXPIRING_SOON"
    case expired      = "EXPIRED"
    case missing      = "MISSING"
    case untrusted    = "UNTRUSTED"
    case revoked      = "REVOKED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .valid:        return "Valid"
        case .expiringSoon: return "Expiring Soon"
        case .expired:      return "Expired"
        case .missing:      return "Missing"
        case .untrusted:    return "Untrusted"
        case .revoked:      return "Revoked"
        }
    }

    /// Whether the certificate can be used for secure connections.
    public var isUsable: Bool {
        self == .valid || self == .expiringSoon
    }

    /// SF Symbol name for this status.
    public var sfSymbol: String {
        switch self {
        case .valid:        return "checkmark.seal"
        case .expiringSoon: return "exclamationmark.triangle"
        case .expired:      return "xmark.seal"
        case .missing:      return "questionmark.circle"
        case .untrusted:    return "xmark.shield"
        case .revoked:      return "nosign"
        }
    }
}

// MARK: - Certificate Entry

/// A TLS certificate entry in the certificate store.
public struct SecurityCertificateEntry: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    /// Common name from the certificate subject.
    public var commonName: String
    /// Certificate issuer display string.
    public var issuer: String
    /// Certificate subject display string.
    public var subject: String
    /// SHA-256 fingerprint (hex-encoded).
    public var fingerprint: String
    /// Certificate validity start date.
    public var notBefore: Date
    /// Certificate validity end date (expiry).
    public var notAfter: Date
    /// Whether this certificate is pinned for a specific server.
    public var isPinned: Bool
    /// Whether this is a client certificate for mTLS.
    public var isClientCertificate: Bool
    /// Whether this is a CA (root/intermediate) certificate.
    public var isCACertificate: Bool
    /// The server hostname this certificate is pinned to (if any).
    public var pinnedHostname: String

    public init(
        id: UUID = UUID(),
        commonName: String,
        issuer: String = "",
        subject: String = "",
        fingerprint: String = "",
        notBefore: Date = Date(),
        notAfter: Date = Date().addingTimeInterval(365 * 24 * 3600),
        isPinned: Bool = false,
        isClientCertificate: Bool = false,
        isCACertificate: Bool = false,
        pinnedHostname: String = ""
    ) {
        self.id = id
        self.commonName = commonName
        self.issuer = issuer
        self.subject = subject
        self.fingerprint = fingerprint
        self.notBefore = notBefore
        self.notAfter = notAfter
        self.isPinned = isPinned
        self.isClientCertificate = isClientCertificate
        self.isCACertificate = isCACertificate
        self.pinnedHostname = pinnedHostname
    }

    /// Current status derived from expiry date.
    public var status: SecurityCertificateStatus {
        let now = Date()
        if notAfter < now { return .expired }
        let thirtyDays: TimeInterval = 30 * 24 * 3600
        if notAfter < now.addingTimeInterval(thirtyDays) { return .expiringSoon }
        return .valid
    }

    /// Days remaining until expiry (negative if already expired).
    public var daysUntilExpiry: Int {
        Int(notAfter.timeIntervalSince(Date()) / (24 * 3600))
    }
}

// MARK: - Server Security Entry

/// Security status for a single DICOM server connection.
public struct SecurityServerEntry: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    /// Display name for the server.
    public var serverName: String
    /// Hostname or IP address.
    public var hostname: String
    /// TLS mode applied to this server.
    public var tlsMode: SecurityTLSMode
    /// Current certificate status.
    public var certificateStatus: SecurityCertificateStatus
    /// Whether mutual TLS (mTLS) is enabled.
    public var isMTLSEnabled: Bool
    /// Whether certificate pinning is active.
    public var isPinningEnabled: Bool
    /// Negotiated TLS version (e.g. "TLS 1.3").
    public var negotiatedTLSVersion: String
    /// Cipher suite negotiated.
    public var cipherSuite: String

    public init(
        id: UUID = UUID(),
        serverName: String,
        hostname: String = "",
        tlsMode: SecurityTLSMode = .compatible,
        certificateStatus: SecurityCertificateStatus = .unknown,
        isMTLSEnabled: Bool = false,
        isPinningEnabled: Bool = false,
        negotiatedTLSVersion: String = "",
        cipherSuite: String = ""
    ) {
        self.id = id
        self.serverName = serverName
        self.hostname = hostname
        self.tlsMode = tlsMode
        self.certificateStatus = certificateStatus
        self.isMTLSEnabled = isMTLSEnabled
        self.isPinningEnabled = isPinningEnabled
        self.negotiatedTLSVersion = negotiatedTLSVersion
        self.cipherSuite = cipherSuite
    }
}

public extension SecurityCertificateStatus {
    /// Placeholder for unknown state (for server security display before any connection).
    static var unknown: SecurityCertificateStatus { .missing }
}

// MARK: - Anonymization Profile

/// Standard anonymization profile.
/// Reference: DICOM PS3.15 Annex E – Attribute Confidentiality Profiles
public enum AnonymizationProfile: String, Sendable, Equatable, Hashable, CaseIterable {
    case basic            = "BASIC"
    case clinicalTrial    = "CLINICAL_TRIAL"
    case research         = "RESEARCH"
    case hipaaeSafeHarbor = "HIPAA_SAFE_HARBOR"
    case custom           = "CUSTOM"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .basic:            return "Basic (Remove Direct Identifiers)"
        case .clinicalTrial:    return "Clinical Trial (Remove + Dates)"
        case .research:         return "Research (Minimal Removal)"
        case .hipaaeSafeHarbor: return "HIPAA Safe Harbor"
        case .custom:           return "Custom Rules"
        }
    }

    /// The dicom-anon `--profile` value that runs the same attribute list as this
    /// profile. The app's profiles are fixed attribute lists, not PS3.15 Annex E, so
    /// they map to the CLI's deprecated `legacy-*` names: since 2026-10-01
    /// (P-ANON-PROFILE) `--profile basic` is the PS3.15 Basic Application Level
    /// Confidentiality Profile (Table E.1-1, UIDs replaced), which none of these
    /// cases implements. HIPAA Safe Harbor and Custom run the legacy basic list in
    /// the app (`SecurityViewModel.engineProfile`), so they name the same flag.
    public var cliFlag: String {
        switch self {
        case .basic:            return "legacy-basic"
        case .clinicalTrial:    return "legacy-clinical-trial"
        case .research:         return "legacy-research"
        case .hipaaeSafeHarbor: return "legacy-basic"
        case .custom:           return "legacy-basic"
        }
    }

    /// Short description.
    public var shortDescription: String {
        switch self {
        case .basic:            return "Removes 18 HIPAA direct identifiers from DICOM metadata."
        case .clinicalTrial:    return "Removes direct identifiers plus study/acquisition dates."
        case .research:         return "Minimal removal: PatientName, PatientID, PatientBirthDate only."
        case .hipaaeSafeHarbor: return "Applies HIPAA Safe Harbor de-identification (45 CFR §164.514(b)(2))."
        case .custom:           return "Apply user-defined tag-level anonymization rules."
        }
    }
}

// MARK: - Tag Action

/// Action to apply to a DICOM tag during anonymization.
public enum TagAction: String, Sendable, Equatable, Hashable, CaseIterable {
    case remove     = "REMOVE"
    case replace    = "REPLACE"
    case hash       = "HASH"
    case shiftDate  = "SHIFT_DATE"
    case keepDate   = "KEEP_DATE"
    case remapUID   = "REMAP_UID"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .remove:    return "Remove"
        case .replace:   return "Replace with placeholder"
        case .hash:      return "Hash (SHA-256)"
        case .shiftDate: return "Shift date"
        case .keepDate:  return "Keep (do not modify)"
        case .remapUID:  return "Remap UID"
        }
    }

    /// SF Symbol name for this action.
    public var sfSymbol: String {
        switch self {
        case .remove:    return "trash"
        case .replace:   return "pencil"
        case .hash:      return "number"
        case .shiftDate: return "calendar.badge.clock"
        case .keepDate:  return "calendar.badge.checkmark"
        case .remapUID:  return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Anonymization Tag Rule

/// A rule specifying how to handle a specific DICOM tag during anonymization.
public struct AnonymizationTagRule: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    /// DICOM tag in (gggg,eeee) notation (e.g. "0010,0010" for Patient Name).
    public var tag: String
    /// Human-readable tag name.
    public var tagName: String
    /// Action to apply.
    public var action: TagAction
    /// Replacement value (used when action == .replace).
    public var replacementValue: String
    /// Date shift in days (used when action == .shiftDate).
    public var dateShiftDays: Int

    public init(
        id: UUID = UUID(),
        tag: String,
        tagName: String = "",
        action: TagAction = .remove,
        replacementValue: String = "",
        dateShiftDays: Int = 0
    ) {
        self.id = id
        self.tag = tag
        self.tagName = tagName
        self.action = action
        self.replacementValue = replacementValue
        self.dateShiftDays = dateShiftDays
    }
}

// MARK: - Anonymization Status

/// Status of an anonymization job.
public enum AnonymizationStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case pending   = "PENDING"
    case running   = "RUNNING"
    case completed = "COMPLETED"
    case failed    = "FAILED"
    case cancelled = "CANCELLED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .pending:   return "Pending"
        case .running:   return "Running"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    /// Whether this is a terminal state.
    public var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}

// MARK: - Anonymization Job

/// A batch anonymization job.
public struct AnonymizationJob: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    /// File paths staged for anonymization.
    public var filePaths: [String]
    /// Profile applied to this job.
    public var profile: AnonymizationProfile
    /// Custom rules (non-empty only when profile == .custom).
    public var customRules: [AnonymizationTagRule]
    /// Job status.
    public var status: AnonymizationStatus
    /// Total number of files.
    public var totalFiles: Int
    /// Number of files processed so far.
    public var processedFiles: Int
    /// Number of files that failed.
    public var failedFiles: Int
    /// Error message, if any.
    public var errorMessage: String?
    /// Output directory for anonymized files.
    public var outputDirectory: String
    /// Whether a reversibility key escrow file was generated.
    public var keyEscrowEnabled: Bool
    /// When the job was created.
    public var createdAt: Date
    /// When the job finished (nil if still running).
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        filePaths: [String] = [],
        profile: AnonymizationProfile = .basic,
        customRules: [AnonymizationTagRule] = [],
        status: AnonymizationStatus = .pending,
        totalFiles: Int = 0,
        processedFiles: Int = 0,
        failedFiles: Int = 0,
        errorMessage: String? = nil,
        outputDirectory: String = "",
        keyEscrowEnabled: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.filePaths = filePaths
        self.profile = profile
        self.customRules = customRules
        self.status = status
        self.totalFiles = totalFiles
        self.processedFiles = processedFiles
        self.failedFiles = failedFiles
        self.errorMessage = errorMessage
        self.outputDirectory = outputDirectory
        self.keyEscrowEnabled = keyEscrowEnabled
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    /// Progress fraction in [0, 1].
    public var progress: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(processedFiles) / Double(totalFiles)
    }
}

// MARK: - Audit Event Type

/// Type of auditable event.
/// Reference: DICOM PS3.15 Annex A – Audit Trail Message Format Profile
public enum SecurityAuditEventType: String, Sendable, Equatable, Hashable, CaseIterable {
    case fileAccess        = "FILE_ACCESS"
    case fileModification  = "FILE_MODIFICATION"
    case fileExport        = "FILE_EXPORT"
    case fileImport        = "FILE_IMPORT"
    case networkQuery      = "NETWORK_QUERY"
    case networkRetrieve   = "NETWORK_RETRIEVE"
    case networkSend       = "NETWORK_SEND"
    case anonymization     = "ANONYMIZATION"
    case userLogin         = "USER_LOGIN"
    case userLogout        = "USER_LOGOUT"
    case settingsChange    = "SETTINGS_CHANGE"
    case securityAlert     = "SECURITY_ALERT"
    case breakGlassAccess  = "BREAK_GLASS_ACCESS"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .fileAccess:       return "File Access"
        case .fileModification: return "File Modification"
        case .fileExport:       return "File Export"
        case .fileImport:       return "File Import"
        case .networkQuery:     return "Network Query"
        case .networkRetrieve:  return "Network Retrieve"
        case .networkSend:      return "Network Send"
        case .anonymization:    return "Anonymization"
        case .userLogin:        return "User Login"
        case .userLogout:       return "User Logout"
        case .settingsChange:   return "Settings Change"
        case .securityAlert:    return "Security Alert"
        case .breakGlassAccess: return "Break-Glass Access"
        }
    }

    /// SF Symbol name for this event type.
    public var sfSymbol: String {
        switch self {
        case .fileAccess:       return "doc"
        case .fileModification: return "pencil"
        case .fileExport:       return "square.and.arrow.up"
        case .fileImport:       return "square.and.arrow.down"
        case .networkQuery:     return "magnifyingglass"
        case .networkRetrieve:  return "arrow.down.circle"
        case .networkSend:      return "arrow.up.circle"
        case .anonymization:    return "person.crop.circle.badge.minus"
        case .userLogin:        return "person.fill.checkmark"
        case .userLogout:       return "person.fill.xmark"
        case .settingsChange:   return "gear"
        case .securityAlert:    return "exclamationmark.triangle"
        case .breakGlassAccess: return "flame"
        }
    }
}

// MARK: - Audit Log Entry

/// A single entry in the HIPAA-compliant audit log.
/// Reference: DICOM PS3.15 Annex A.5 – DICOM Audit Messages
public struct SecurityAuditEntry: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    /// Timestamp of the event.
    public var timestamp: Date
    /// Type of event.
    public var eventType: SecurityAuditEventType
    /// User identity (username or display name).
    public var userIdentity: String
    /// Patient reference (PatientID or anonymized ID).
    public var patientReference: String
    /// Study instance UID reference (if applicable).
    public var studyReference: String
    /// Human-readable description of the event.
    public var description: String
    /// Outcome: true = success, false = failure.
    public var success: Bool
    /// Source IP or host for network events.
    public var sourceHost: String
    /// Additional metadata key-value pairs.
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        eventType: SecurityAuditEventType,
        userIdentity: String = "",
        patientReference: String = "",
        studyReference: String = "",
        description: String = "",
        success: Bool = true,
        sourceHost: String = "",
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.userIdentity = userIdentity
        self.patientReference = patientReference
        self.studyReference = studyReference
        self.description = description
        self.success = success
        self.sourceHost = sourceHost
        self.metadata = metadata
    }
}

// MARK: - Audit Log Export Format

/// Supported export formats for audit log data.
public enum SecurityAuditExportFormat: String, Sendable, Equatable, Hashable, CaseIterable {
    case csv  = "CSV"
    case json = "JSON"
    case atna = "ATNA"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .csv:  return "CSV"
        case .json: return "JSON"
        case .atna: return "ATNA (IHE)"
        }
    }

    /// File extension for the export format.
    public var fileExtension: String {
        switch self {
        case .csv:  return "csv"
        case .json: return "json"
        case .atna: return "xml"
        }
    }
}

// MARK: - Audit Log Handler Type

/// Type of audit log output handler.
public enum SecurityAuditHandlerType: String, Sendable, Equatable, Hashable, CaseIterable {
    case file    = "FILE"
    case console = "CONSOLE"
    case osLog   = "OSLOG"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .file:    return "File"
        case .console: return "Console"
        case .osLog:   return "OSLog"
        }
    }

    /// SF Symbol name.
    public var sfSymbol: String {
        switch self {
        case .file:    return "doc.text"
        case .console: return "terminal"
        case .osLog:   return "bubble.left.and.text.bubble.right"
        }
    }
}

// MARK: - Audit Retention Policy

/// How long audit log entries are retained.
public enum SecurityAuditRetentionPolicy: String, Sendable, Equatable, Hashable, CaseIterable {
    case days30      = "30_DAYS"
    case days90      = "90_DAYS"
    case days180     = "180_DAYS"
    case days365     = "365_DAYS"
    case indefinite  = "INDEFINITE"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .days30:     return "30 Days"
        case .days90:     return "90 Days"
        case .days180:    return "180 Days"
        case .days365:    return "1 Year"
        case .indefinite: return "Indefinite"
        }
    }

    /// Number of days to retain, or nil for indefinite.
    public var retentionDays: Int? {
        switch self {
        case .days30:     return 30
        case .days90:     return 90
        case .days180:    return 180
        case .days365:    return 365
        case .indefinite: return nil
        }
    }
}

// MARK: - User Role

/// User role for access control.
public enum UserRole: String, Sendable, Equatable, Hashable, CaseIterable {
    case viewer     = "VIEWER"
    case clinician  = "CLINICIAN"
    case admin      = "ADMIN"
    case superAdmin = "SUPER_ADMIN"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .viewer:     return "Viewer"
        case .clinician:  return "Clinician"
        case .admin:      return "Administrator"
        case .superAdmin: return "Super Administrator"
        }
    }

    /// SF Symbol name.
    public var sfSymbol: String {
        switch self {
        case .viewer:     return "eye"
        case .clinician:  return "stethoscope"
        case .admin:      return "person.badge.key"
        case .superAdmin: return "crown"
        }
    }

    /// Numeric privilege level (higher = more privileged).
    public var privilegeLevel: Int {
        switch self {
        case .viewer:     return 1
        case .clinician:  return 2
        case .admin:      return 3
        case .superAdmin: return 4
        }
    }
}

// MARK: - Session Status

/// Status of a user session.
public enum SessionStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case active  = "ACTIVE"
    case idle    = "IDLE"
    case locked  = "LOCKED"
    case expired = "EXPIRED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .active:  return "Active"
        case .idle:    return "Idle"
        case .locked:  return "Locked"
        case .expired: return "Expired"
        }
    }

    /// Whether the session can be used to perform operations.
    public var isUsable: Bool {
        self == .active || self == .idle
    }
}

// MARK: - Access Control Session

/// Represents an authenticated user session.
public struct AccessControlSession: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    /// Display name of the user.
    public var userName: String
    /// User email or identifier (from OAuth2/JWT).
    public var userEmail: String
    /// Role assigned to the user.
    public var role: UserRole
    /// Current session status.
    public var status: SessionStatus
    /// When the session was started.
    public var startedAt: Date
    /// Last activity timestamp.
    public var lastActivityAt: Date
    /// Session timeout interval (in seconds).
    public var timeoutInterval: TimeInterval
    /// Whether this session was established via OAuth2.
    public var isOAuth2Session: Bool
    /// OAuth2 scopes granted to this session.
    public var grantedScopes: [String]

    public init(
        id: UUID = UUID(),
        userName: String,
        userEmail: String = "",
        role: UserRole = .viewer,
        status: SessionStatus = .active,
        startedAt: Date = Date(),
        lastActivityAt: Date = Date(),
        timeoutInterval: TimeInterval = 3600,
        isOAuth2Session: Bool = false,
        grantedScopes: [String] = []
    ) {
        self.id = id
        self.userName = userName
        self.userEmail = userEmail
        self.role = role
        self.status = status
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.timeoutInterval = timeoutInterval
        self.isOAuth2Session = isOAuth2Session
        self.grantedScopes = grantedScopes
    }

    /// Whether the session has timed out based on the last activity.
    public var isTimedOut: Bool {
        Date().timeIntervalSince(lastActivityAt) > timeoutInterval
    }
}

// MARK: - Break-Glass Event

/// Records an emergency ("break-glass") access event for compliance tracking.
public struct BreakGlassEvent: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    /// User who invoked break-glass access.
    public var userName: String
    /// Patient or study reference accessed.
    public var resourceReference: String
    /// Reason provided for break-glass access.
    public var reason: String
    /// Timestamp of the event.
    public var timestamp: Date
    /// Whether a supervisor notification was sent.
    public var supervisorNotified: Bool

    public init(
        id: UUID = UUID(),
        userName: String,
        resourceReference: String = "",
        reason: String = "",
        timestamp: Date = Date(),
        supervisorNotified: Bool = false
    ) {
        self.id = id
        self.userName = userName
        self.resourceReference = resourceReference
        self.reason = reason
        self.timestamp = timestamp
        self.supervisorNotified = supervisorNotified
    }
}

// MARK: - Permission Entry

/// A single entry in the permission matrix.
public struct PermissionEntry: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    /// The permission being described.
    public var permission: String
    /// Human-readable description.
    public var description: String
    /// Whether each role has this permission.
    public var rolePermissions: [UserRole: Bool]

    public init(
        id: UUID = UUID(),
        permission: String,
        description: String = "",
        rolePermissions: [UserRole: Bool] = [:]
    ) {
        self.id = id
        self.permission = permission
        self.description = description
        self.rolePermissions = rolePermissions
    }
}

// MARK: - PHI Detection Result

/// Result of a PHI (Protected Health Information) scan on a DICOM file.
public struct PHIDetectionResult: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    /// File path that was scanned.
    public var filePath: String
    /// Tags found to contain PHI, with (tag, value) pairs.
    public var detectedPHITags: [(tag: String, tagName: String, preview: String)]
    /// Whether the file is considered a PHI risk.
    public var hasPHI: Bool
    /// When the scan was performed.
    public var scannedAt: Date

    public init(
        id: UUID = UUID(),
        filePath: String,
        detectedPHITags: [(tag: String, tagName: String, preview: String)] = [],
        hasPHI: Bool = false,
        scannedAt: Date = Date()
    ) {
        self.id = id
        self.filePath = filePath
        self.detectedPHITags = detectedPHITags
        self.hasPHI = hasPHI
        self.scannedAt = scannedAt
    }

    public static func == (lhs: PHIDetectionResult, rhs: PHIDetectionResult) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}


// MARK: - Anonymization Builder Helpers (matches dicom-anon CLI)

/// Platform-independent helpers for dicom-anon command building.
/// CLI reference: dicom-anon <path> [options]
public enum AnonHelpers: Sendable {

    /// Builds the exact dicom-anon CLI command from SecurityViewModel anon-builder state.
    public static func buildCommand(
        inputPath: String,
        outputPath: String,
        profile: AnonymizationProfile,
        shiftDates: Int?,
        regenerateUIDs: Bool,
        removeTags: [String],
        replacePairs: [String],
        keepTags: [String],
        recursive: Bool,
        dryRun: Bool,
        backup: Bool,
        auditLogPath: String,
        force: Bool,
        verbose: Bool
    ) -> String {
        guard !inputPath.isEmpty else { return "dicom-anon <input>" }
        var cmd = "dicom-anon \"\(inputPath)\""
        if !outputPath.isEmpty { cmd += " --output \"\(outputPath)\"" }
        // Always named: the CLI default is now the PS3.15 Basic Profile (ps315), which
        // is not what any app profile runs, so an omitted flag would change behaviour.
        cmd += " --profile \(profile.cliFlag)"
        if let days = shiftDates { cmd += " --shift-dates \(days)" }
        if regenerateUIDs { cmd += " --regenerate-uids" }
        for tag in removeTags  where !tag.isEmpty { cmd += " --remove \(tag)" }
        for pair in replacePairs where !pair.isEmpty { cmd += " --replace \(pair)" }
        for tag in keepTags    where !tag.isEmpty { cmd += " --keep \(tag)" }
        if recursive   { cmd += " --recursive" }
        if dryRun      { cmd += " --dry-run" }
        if backup      { cmd += " --backup" }
        if !auditLogPath.isEmpty { cmd += " --audit-log \"\(auditLogPath)\"" }
        if force       { cmd += " --force" }
        if verbose     { cmd += " --verbose" }
        return cmd
    }

    // Summary rendering lives in the shared `AnonConsole` (DICOMKit) — the same
    // builder the dicom-anon CLI prints from — so the two surfaces cannot drift.
}
