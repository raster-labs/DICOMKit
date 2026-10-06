// NetworkingModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for the DICOM Networking Hub (Milestone 9)
// Reference: DICOM PS3.4 (Service Class Specifications)
// Reference: DICOM PS3.7 (Message Exchange)
// Reference: DICOM PS3.8 (Network Communication)
// Reference: DICOM PS3.15 (Security and System Management)
// NEMA-verified: 2026a, checked 2026-10-05 — the Studio print enums text-diffed against PS3.3 2026a Table C.13-1
// (Print Priority HIGH/MED/LOW: 3 match; Medium Type: PAPER and CLEAR FILM match, BLU-RAY corrected to BLUE FILM,
// the two MAMMO terms are not offered), Table C.13-3 (Film Size ID: 12 of 12 match; Image Display Format
// STANDARD\C,R: the 8 FilmLayout values match, columns first) and Table C.13-8 (PrintJobStatus is the app's
// job state, re-spelled with the Execution Status terms PENDING/PRINTING/DONE/FAILURE); MPPSStatus against
// PS3.3 C.4.14 (IN PROGRESS/COMPLETED/DISCONTINUED: IN_PROGRESS corrected); NetworkQueryLevel against PS3.4
// Table C.6.1-1 (4 of 4); default port 11112 is the PS3.8 9.1.1 registered port. TLSMode names TLS versions,
// not the PS3.15 Annex B profiles — B.9–B.11 are retired in 2026a, B.12/B.13 are the live BCP 195 profiles
// (P-STUDIO-TLS-PROFILES); TransferPriority orders the app's queue and is not
// the DIMSE Priority (0000,0700). The four print enums duplicate DICOMNetwork's (D22, P-STUDIO-PRINT-ENUMS).

import Foundation

// MARK: - Navigation Tab
import DICOMNetwork

/// Navigation tabs for the DICOM Networking Hub.
public enum NetworkingTab: String, Sendable, Equatable, Hashable, CaseIterable {
    case serverConfig   = "SERVER_CONFIG"
    case cEcho          = "C_ECHO"
    case cFind          = "C_FIND"
    case cMoveGet       = "C_MOVE_GET"
    case cStore         = "C_STORE"
    case mwl            = "MWL"
    case mpps           = "MPPS"
    case printManagement = "PRINT_MANAGEMENT"
    case monitoring     = "MONITORING"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .serverConfig:    return "Server Config"
        case .cEcho:           return "C-ECHO"
        case .cFind:           return "C-FIND"
        case .cMoveGet:        return "C-MOVE/GET"
        case .cStore:          return "C-STORE"
        case .mwl:             return "Worklist"
        case .mpps:            return "MPPS"
        case .printManagement: return "Print"
        case .monitoring:      return "Monitoring"
        }
    }

    /// SF Symbol name for this tab.
    public var sfSymbol: String {
        switch self {
        case .serverConfig:    return "server.rack"
        case .cEcho:           return "network"
        case .cFind:           return "magnifyingglass"
        case .cMoveGet:        return "arrow.down.circle"
        case .cStore:          return "arrow.up.circle"
        case .mwl:             return "list.bullet.clipboard"
        case .mpps:            return "checkmark.circle"
        case .printManagement: return "printer"
        case .monitoring:      return "chart.bar"
        }
    }
}

// MARK: - TLS Mode

/// TLS mode for DICOM (DIMSE) connections: no TLS, one of the live PS3.15 2026a Annex B TLS
/// Secure Transport Connection Profiles, or mutual TLS under B.12.
///
/// Reference: DICOM PS3.15 2026a Annex B — B.12 "BCP 195 RFC 8996, 9325 TLS Secure Transport
/// Connection Profile" and B.13 "Modified BCP 195 RFC 8996, 9325 TLS Secure Transport Connection
/// Profile" (B.1–B.3 and B.9–B.11 are retired). ``tlsConfiguration(certificateValidation:clientIdentity:)``
/// gives the DICOMNetwork `TLSConfiguration` per profile; what that configuration cannot enforce
/// (B.13's CCM / Camellia / DHE suites, key-length and certificate rules) is listed on
/// `TLSConfiguration.bcp195` / `.modifiedBCP195`.
///
/// The former cases `tls12` ("TLS_1_2") and `tls13` ("TLS_1_3") pinned a TLS version, which a
/// profile forbids (B.12 requires TLS 1.2 and attempts 1.3); they are deprecated aliases of
/// ``bcp195`` and ``modifiedBCP195`` (B.13 allows a TLS 1.3-only client), and a stored
/// "TLS_1_2" / "TLS_1_3" decodes to those cases.
public enum TLSMode: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// No TLS (plain DICOM Upper Layer).
    case none           = "NONE"
    /// PS3.15 2026a B.12 BCP 195 RFC 8996, 9325 TLS.
    case bcp195         = "BCP195"
    /// PS3.15 2026a B.13 Modified BCP 195 RFC 8996, 9325 TLS.
    case modifiedBCP195 = "MODIFIED_BCP195"
    /// B.12 with a client certificate (bi-directional mutual authentication, which B.12 servers
    /// shall support and clients are encouraged to use).
    case mtls           = "MTLS"

    /// Pinned TLS 1.2; no PS3.15 profile pins a version.
    @available(*, deprecated, renamed: "bcp195",
               message: "PS3.15 2026a B.12 (BCP 195) requires TLS 1.2 and attempts TLS 1.3; no profile pins TLS 1.2")
    public static var tls12: TLSMode { .bcp195 }

    /// Pinned TLS 1.3; the nearest profile is B.13, which allows a TLS 1.3-only client.
    @available(*, deprecated, renamed: "modifiedBCP195",
               message: "PS3.15 2026a B.13 (Modified BCP 195) is the profile that allows a TLS 1.3-only client")
    public static var tls13: TLSMode { .modifiedBCP195 }

    /// Accepts the current raw values and the retired "TLS_1_2" / "TLS_1_3" (stored profiles
    /// decode to ``bcp195`` / ``modifiedBCP195``).
    public init?(rawValue: String) {
        switch rawValue {
        case "NONE":                       self = .none
        case "BCP195", "TLS_1_2":          self = .bcp195
        case "MODIFIED_BCP195", "TLS_1_3": self = .modifiedBCP195
        case "MTLS":                       self = .mtls
        default:                           return nil
        }
    }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .none:           return "No TLS"
        case .bcp195:         return "BCP 195 TLS (PS3.15 B.12)"
        case .modifiedBCP195: return "Modified BCP 195 TLS (PS3.15 B.13)"
        case .mtls:           return "mTLS (Mutual, B.12)"
        }
    }

    /// Whether TLS is enabled.
    public var isEnabled: Bool { self != .none }

    /// Whether mutual TLS is required.
    public var requiresClientCertificate: Bool { self == .mtls }
}


    /// The PS3.15 2026a Annex B profile this mode applies; nil for ``none``.
    public var profile: SecureTransportConnectionProfile? {
        switch self {
        case .none:           return nil
        case .bcp195, .mtls:  return .bcp195
        case .modifiedBCP195: return .modifiedBCP195
        }
    }

    /// The DICOMNetwork TLS configuration for this mode (`TLSConfiguration.profile(_:…)` of
    /// ``profile``); nil for ``none``. The client identity is used for ``mtls``.
    public func tlsConfiguration(
        certificateValidation: CertificateValidation = .system,
        clientIdentity: ClientIdentity? = nil
    ) -> TLSConfiguration? {
        guard let profile else { return nil }
        return TLSConfiguration.profile(
            profile,
            certificateValidation: certificateValidation,
            clientIdentity: self == .mtls ? clientIdentity : nil
        )
    }
// MARK: - Server Connection Status

/// Connection status of a DICOM server.
public enum ServerConnectionStatus: String, Sendable, Equatable, Hashable, Codable {
    case unknown   = "UNKNOWN"
    case testing   = "TESTING"
    case online    = "ONLINE"
    /// Reachable and usable, but reporting a non-blocking problem — a printer
    /// with low film, for instance. Distinct from ``error`` so the UI can show
    /// amber rather than red and still let the user submit work.
    case warning   = "WARNING"
    case offline   = "OFFLINE"
    case error     = "ERROR"

    /// Human-readable label.
    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .testing: return "Testing…"
        case .online:  return "Online"
        case .warning: return "Warning"
        case .offline: return "Offline"
        case .error:   return "Error"
        }
    }

    /// SF Symbol name.
    public var sfSymbol: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .testing: return "arrow.triangle.2.circlepath"
        case .online:  return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .offline: return "xmark.circle"
        case .error:   return "xmark.octagon.fill"
        }
    }
}

// MARK: - PACS Server Profile

/// A DICOM server configuration profile.
/// Reference: DICOM PS3.8 Section 9 - AE Title
public struct PACSServerProfile: Sendable, Identifiable, Equatable, Hashable, Codable {
    /// Unique profile identifier.
    public let id: UUID
    /// Human-readable profile name.
    public var name: String
    /// Server hostname or IP address.
    public var host: String
    /// DICOM port (typically 11112, or 2762 for TLS).
    public var port: UInt16
    /// Remote AE title (called AE).
    public var remoteAETitle: String
    /// Local AE title (calling AE).
    public var localAETitle: String
    /// TLS mode for this connection.
    public var tlsMode: TLSMode
    /// Whether to pin the server certificate.
    public var certificatePinningEnabled: Bool
    /// Whether to accept self-signed certificates.
    public var allowSelfSignedCertificates: Bool
    /// Connection timeout in seconds.
    public var timeoutSeconds: Double
    /// Current connection status.
    public var status: ServerConnectionStatus
    /// Date/time of last successful echo.
    public var lastEchoDate: Date?
    /// Whether this is the default/active server.
    public var isDefault: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16 = 11112,
        remoteAETitle: String,
        localAETitle: String = "DICOMSTUDIO",
        tlsMode: TLSMode = .none,
        certificatePinningEnabled: Bool = false,
        allowSelfSignedCertificates: Bool = false,
        timeoutSeconds: Double = 30.0,
        status: ServerConnectionStatus = .unknown,
        lastEchoDate: Date? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.remoteAETitle = remoteAETitle
        self.localAETitle = localAETitle
        self.tlsMode = tlsMode
        self.certificatePinningEnabled = certificatePinningEnabled
        self.allowSelfSignedCertificates = allowSelfSignedCertificates
        self.timeoutSeconds = timeoutSeconds
        self.status = status
        self.lastEchoDate = lastEchoDate
        self.isDefault = isDefault
    }
}

// MARK: - Echo Result

/// Result of a C-ECHO (Verification) operation.
/// Reference: DICOM PS3.7 Section 9.1.5 - Verification
public struct EchoResult: Sendable, Identifiable, Equatable {
    /// Unique result identifier.
    public let id: UUID
    /// ID of the server that was tested.
    public let serverProfileID: UUID
    /// Server name (snapshot for display).
    public let serverName: String
    /// Whether the echo was successful.
    public let success: Bool
    /// Round-trip latency in milliseconds (nil if failed).
    public let latencyMs: Double?
    /// Error message if failed.
    public let errorMessage: String?
    /// When the echo was performed.
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        serverProfileID: UUID,
        serverName: String,
        success: Bool,
        latencyMs: Double? = nil,
        errorMessage: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.serverProfileID = serverProfileID
        self.serverName = serverName
        self.success = success
        self.latencyMs = latencyMs
        self.errorMessage = errorMessage
        self.timestamp = timestamp
    }
}

// MARK: - Query Level

/// DICOM query/retrieve information model levels.
/// Reference: DICOM PS3.4 Annex C - Query/Retrieve Service Class
public enum NetworkQueryLevel: String, Sendable, Equatable, Hashable, CaseIterable {
    case patient  = "PATIENT"
    case study    = "STUDY"
    case series   = "SERIES"
    case instance = "IMAGE"

    /// Human-readable label.
    public var displayName: String {
        switch self {
        case .patient:  return "Patient"
        case .study:    return "Study"
        case .series:   return "Series"
        case .instance: return "Instance"
        }
    }

    /// SF Symbol for this level.
    public var sfSymbol: String {
        switch self {
        case .patient:  return "person.fill"
        case .study:    return "folder.fill"
        case .series:   return "rectangle.stack.fill"
        case .instance: return "doc.fill"
        }
    }
}

// MARK: - Query Filter

/// Filter parameters for a C-FIND query.
/// Reference: DICOM PS3.4 Table C.6-1 – Study Root Query/Retrieve Information Model
public struct QueryFilter: Sendable, Equatable {
    /// Query level.
    public var level: NetworkQueryLevel
    /// Patient name (supports wildcards: *, ?).
    public var patientName: String
    /// Patient ID.
    public var patientID: String
    /// Study date start (YYYYMMDD format).
    public var studyDateStart: String
    /// Study date end (YYYYMMDD format).
    public var studyDateEnd: String
    /// Study description.
    public var studyDescription: String
    /// Modality filter.
    public var modality: String
    /// Accession number.
    public var accessionNumber: String
    /// Series description.
    public var seriesDescription: String
    /// Series number.
    public var seriesNumber: String
    /// Maximum number of results (0 = no limit).
    public var maxResults: Int

    public init(
        level: NetworkQueryLevel = .study,
        patientName: String = "",
        patientID: String = "",
        studyDateStart: String = "",
        studyDateEnd: String = "",
        studyDescription: String = "",
        modality: String = "",
        accessionNumber: String = "",
        seriesDescription: String = "",
        seriesNumber: String = "",
        maxResults: Int = 100
    ) {
        self.level = level
        self.patientName = patientName
        self.patientID = patientID
        self.studyDateStart = studyDateStart
        self.studyDateEnd = studyDateEnd
        self.studyDescription = studyDescription
        self.modality = modality
        self.accessionNumber = accessionNumber
        self.seriesDescription = seriesDescription
        self.seriesNumber = seriesNumber
        self.maxResults = maxResults
    }

    /// Returns true if any query field is non-empty.
    public var hasActiveFilter: Bool {
        !patientName.isEmpty || !patientID.isEmpty || !studyDateStart.isEmpty
        || !studyDateEnd.isEmpty || !studyDescription.isEmpty || !modality.isEmpty
        || !accessionNumber.isEmpty || !seriesDescription.isEmpty || !seriesNumber.isEmpty
    }
}

// MARK: - Query Result Item

/// A single result entry from a C-FIND query.
/// Reference: DICOM PS3.4 Annex C.4 – C-FIND Response
public struct QueryResultItem: Sendable, Identifiable, Equatable, Hashable {
    /// Unique result identifier.
    public let id: UUID
    /// Query level of this result.
    public let level: NetworkQueryLevel
    /// Patient name.
    public let patientName: String
    /// Patient ID.
    public let patientID: String
    /// Study Instance UID.
    public let studyInstanceUID: String
    /// Study date.
    public let studyDate: String
    /// Study description.
    public let studyDescription: String
    /// Modality.
    public let modality: String
    /// Accession number.
    public let accessionNumber: String
    /// Series Instance UID (for series/instance level).
    public let seriesInstanceUID: String?
    /// SOP Instance UID (for instance level).
    public let sopInstanceUID: String?
    /// Number of series in study (study level only).
    public let numberOfSeries: Int?
    /// Number of instances in series (series level only).
    public let numberOfInstances: Int?

    public init(
        id: UUID = UUID(),
        level: NetworkQueryLevel,
        patientName: String = "",
        patientID: String = "",
        studyInstanceUID: String = "",
        studyDate: String = "",
        studyDescription: String = "",
        modality: String = "",
        accessionNumber: String = "",
        seriesInstanceUID: String? = nil,
        sopInstanceUID: String? = nil,
        numberOfSeries: Int? = nil,
        numberOfInstances: Int? = nil
    ) {
        self.id = id
        self.level = level
        self.patientName = patientName
        self.patientID = patientID
        self.studyInstanceUID = studyInstanceUID
        self.studyDate = studyDate
        self.studyDescription = studyDescription
        self.modality = modality
        self.accessionNumber = accessionNumber
        self.seriesInstanceUID = seriesInstanceUID
        self.sopInstanceUID = sopInstanceUID
        self.numberOfSeries = numberOfSeries
        self.numberOfInstances = numberOfInstances
    }
}

// MARK: - Transfer Status

/// Status of a C-MOVE or C-GET transfer operation.
public enum TransferStatus: String, Sendable, Equatable, Hashable {
    case pending    = "PENDING"
    case inProgress = "IN_PROGRESS"
    case paused     = "PAUSED"
    case completed  = "COMPLETED"
    case failed     = "FAILED"
    case cancelled  = "CANCELLED"

    /// Human-readable label.
    public var displayName: String {
        switch self {
        case .pending:    return "Pending"
        case .inProgress: return "Transferring"
        case .paused:     return "Paused"
        case .completed:  return "Completed"
        case .failed:     return "Failed"
        case .cancelled:  return "Cancelled"
        }
    }

    /// Whether the transfer can be paused.
    public var canPause: Bool { self == .inProgress }
    /// Whether the transfer can be resumed.
    public var canResume: Bool { self == .paused }
    /// Whether the transfer can be cancelled.
    public var canCancel: Bool { self == .pending || self == .inProgress || self == .paused }
    /// Whether the transfer can be retried.
    public var canRetry: Bool { self == .failed || self == .cancelled }
}

// MARK: - Transfer Priority

/// Priority for transfer queue ordering.
public enum TransferPriority: String, Sendable, Equatable, Hashable, CaseIterable, Comparable {
    case low    = "LOW"
    case normal = "NORMAL"
    case high   = "HIGH"

    public var displayName: String {
        switch self {
        case .low:    return "Low"
        case .normal: return "Normal"
        case .high:   return "High"
        }
    }

    public static func < (lhs: TransferPriority, rhs: TransferPriority) -> Bool {
        let order: [TransferPriority] = [.low, .normal, .high]
        let lhsIdx = order.firstIndex(of: lhs) ?? 0
        let rhsIdx = order.firstIndex(of: rhs) ?? 0
        return lhsIdx < rhsIdx
    }
}

// MARK: - Transfer Item

/// A single item in the C-MOVE / C-GET transfer queue.
/// Reference: DICOM PS3.4 Annex C – Query/Retrieve Service Class
public struct TransferItem: Sendable, Identifiable, Equatable {
    /// Unique item identifier.
    public let id: UUID
    /// Human-readable description (e.g. study description or patient name).
    public var label: String
    /// Study Instance UID to retrieve.
    public let studyInstanceUID: String
    /// Series Instance UID (nil = all series in study).
    public let seriesInstanceUID: String?
    /// SOP Instance UID (nil = all instances in series).
    public let sopInstanceUID: String?
    /// Server to retrieve from.
    public let serverProfileID: UUID
    /// Transfer method (C-MOVE vs C-GET).
    public var method: RetrieveMethod
    /// Transfer priority.
    public var priority: TransferPriority
    /// Current status.
    public var status: TransferStatus
    /// Transfer progress 0.0–1.0.
    public var progress: Double
    /// Number of instances completed.
    public var instancesCompleted: Int
    /// Total number of instances.
    public var instancesTotal: Int
    /// Transfer speed in bytes/sec.
    public var bytesPerSecond: Double
    /// Error message if failed.
    public var errorMessage: String?
    /// When the transfer was queued.
    public let queuedDate: Date
    /// When the transfer started.
    public var startedDate: Date?
    /// When the transfer completed.
    public var completedDate: Date?

    public init(
        id: UUID = UUID(),
        label: String,
        studyInstanceUID: String,
        seriesInstanceUID: String? = nil,
        sopInstanceUID: String? = nil,
        serverProfileID: UUID,
        method: RetrieveMethod = .cMove,
        priority: TransferPriority = .normal,
        status: TransferStatus = .pending,
        progress: Double = 0.0,
        instancesCompleted: Int = 0,
        instancesTotal: Int = 0,
        bytesPerSecond: Double = 0,
        errorMessage: String? = nil,
        queuedDate: Date = Date(),
        startedDate: Date? = nil,
        completedDate: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.sopInstanceUID = sopInstanceUID
        self.serverProfileID = serverProfileID
        self.method = method
        self.priority = priority
        self.status = status
        self.progress = max(0, min(1, progress))
        self.instancesCompleted = instancesCompleted
        self.instancesTotal = instancesTotal
        self.bytesPerSecond = bytesPerSecond
        self.errorMessage = errorMessage
        self.queuedDate = queuedDate
        self.startedDate = startedDate
        self.completedDate = completedDate
    }
}

// MARK: - Retrieve Method

/// C-MOVE vs C-GET retrieval method.
/// Reference: DICOM PS3.4 Section C.4 – C-MOVE, C-GET
public enum RetrieveMethod: String, Sendable, Equatable, Hashable, CaseIterable {
    case cMove = "C_MOVE"
    case cGet  = "C_GET"

    public var displayName: String {
        switch self {
        case .cMove: return "C-MOVE"
        case .cGet:  return "C-GET"
        }
    }
}

// MARK: - Backoff Strategy

/// Backoff strategy for retry operations.
public enum BackoffStrategy: String, Sendable, Equatable, Hashable, CaseIterable {
    case fixed             = "FIXED"
    case exponential       = "EXPONENTIAL"
    case exponentialJitter = "EXPONENTIAL_JITTER"

    public var displayName: String {
        switch self {
        case .fixed:             return "Fixed"
        case .exponential:       return "Exponential"
        case .exponentialJitter: return "Exponential + Jitter"
        }
    }
}

// MARK: - Send Retry Config

/// Retry configuration for C-STORE operations.
public struct SendRetryConfig: Sendable, Equatable, Hashable {
    /// Maximum number of retry attempts (0 = no retries).
    public var maxRetries: Int
    /// Initial delay in seconds before first retry.
    public var initialDelaySeconds: Double
    /// Maximum delay cap in seconds.
    public var maxDelaySeconds: Double
    /// Backoff strategy.
    public var backoffStrategy: BackoffStrategy

    public init(
        maxRetries: Int = 3,
        initialDelaySeconds: Double = 1.0,
        maxDelaySeconds: Double = 60.0,
        backoffStrategy: BackoffStrategy = .exponentialJitter
    ) {
        self.maxRetries = max(0, maxRetries)
        self.initialDelaySeconds = max(0, initialDelaySeconds)
        self.maxDelaySeconds = max(initialDelaySeconds, maxDelaySeconds)
        self.backoffStrategy = backoffStrategy
    }

    /// Default retry configuration.
    public static let `default` = SendRetryConfig()
}

// MARK: - Circuit Breaker State

/// Display state of the circuit breaker for a server connection.
/// Reference: Circuit Breaker pattern for fault-tolerant networking
public enum CircuitBreakerDisplayState: String, Sendable, Equatable, Hashable, CaseIterable {
    case closed   = "CLOSED"
    case open     = "OPEN"
    case halfOpen = "HALF_OPEN"

    public var displayName: String {
        switch self {
        case .closed:   return "Closed (Normal)"
        case .open:     return "Open (Tripped)"
        case .halfOpen: return "Half-Open (Testing)"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .closed:   return "checkmark.circle.fill"
        case .open:     return "exclamationmark.octagon.fill"
        case .halfOpen: return "arrow.triangle.2.circlepath"
        }
    }

    /// Whether sending is blocked.
    public var isBlocked: Bool { self == .open }
}

// MARK: - Send Item

/// A single item in the C-STORE send queue.
/// Reference: DICOM PS3.4 Annex B – Storage Service Class
public struct SendItem: Sendable, Identifiable, Equatable {
    /// Unique item identifier.
    public let id: UUID
    /// Human-readable label.
    public var label: String
    /// Local file path or DICOM SOP Instance UID.
    public var sourceIdentifier: String
    /// Target server profile ID.
    public let serverProfileID: UUID
    /// Current send status.
    public var status: SendStatus
    /// Retry count so far.
    public var retryCount: Int
    /// Progress 0.0–1.0.
    public var progress: Double
    /// Error message if failed.
    public var errorMessage: String?
    /// When the item was queued.
    public let queuedDate: Date
    /// When the send started.
    public var startedDate: Date?
    /// When the send completed.
    public var completedDate: Date?
    /// Circuit breaker state for this destination.
    public var circuitBreakerState: CircuitBreakerDisplayState

    public init(
        id: UUID = UUID(),
        label: String,
        sourceIdentifier: String,
        serverProfileID: UUID,
        status: SendStatus = .pending,
        retryCount: Int = 0,
        progress: Double = 0.0,
        errorMessage: String? = nil,
        queuedDate: Date = Date(),
        startedDate: Date? = nil,
        completedDate: Date? = nil,
        circuitBreakerState: CircuitBreakerDisplayState = .closed
    ) {
        self.id = id
        self.label = label
        self.sourceIdentifier = sourceIdentifier
        self.serverProfileID = serverProfileID
        self.status = status
        self.retryCount = max(0, retryCount)
        self.progress = max(0, min(1, progress))
        self.errorMessage = errorMessage
        self.queuedDate = queuedDate
        self.startedDate = startedDate
        self.completedDate = completedDate
        self.circuitBreakerState = circuitBreakerState
    }
}

// MARK: - Send Status

/// Status of a C-STORE send operation.
public enum SendStatus: String, Sendable, Equatable, Hashable {
    case pending   = "PENDING"
    case sending   = "SENDING"
    case completed = "COMPLETED"
    case failed    = "FAILED"

    public var displayName: String {
        switch self {
        case .pending:   return "Pending"
        case .sending:   return "Sending"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        }
    }

    public var canRetry: Bool { self == .failed }
}

// MARK: - Validation Level

/// Pre-send validation level for C-STORE.
public enum ValidationLevel: String, Sendable, Equatable, Hashable, CaseIterable {
    case none     = "NONE"
    case basic    = "BASIC"
    case standard = "STANDARD"
    case strict   = "STRICT"

    public var displayName: String {
        switch self {
        case .none:     return "None"
        case .basic:    return "Basic"
        case .standard: return "Standard"
        case .strict:   return "Strict"
        }
    }

    public var description: String {
        switch self {
        case .none:     return "No validation; send as-is"
        case .basic:    return "Check required tags only"
        case .standard: return "Standard IOD conformance"
        case .strict:   return "Full DICOM conformance"
        }
    }
}

// MARK: - MWL Worklist Item

/// A scheduled procedure step from Modality Worklist.
/// Reference: DICOM PS3.4 Annex K – Modality Worklist Service Class
public struct MWLWorklistItem: Sendable, Identifiable, Equatable, Hashable {
    /// Unique identifier.
    public let id: UUID
    /// Patient name.
    public let patientName: String
    /// Patient ID.
    public let patientID: String
    /// Patient birth date (YYYYMMDD).
    public let patientBirthDate: String
    /// Patient sex.
    public let patientSex: String
    /// Accession number.
    public let accessionNumber: String
    /// Requested procedure ID.
    public let requestedProcedureID: String
    /// Requested procedure description.
    public let requestedProcedureDescription: String
    /// Referring physician name.
    public let referringPhysicianName: String
    /// Scheduled station AE title.
    public let scheduledStationAETitle: String
    /// Scheduled procedure step start date (YYYYMMDD).
    public let scheduledProcedureStepStartDate: String
    /// Scheduled procedure step start time (HHMMSS).
    public let scheduledProcedureStepStartTime: String
    /// Modality.
    public let modality: String
    /// Scheduled performing physician name.
    public let scheduledPerformingPhysicianName: String

    public init(
        id: UUID = UUID(),
        patientName: String,
        patientID: String,
        patientBirthDate: String = "",
        patientSex: String = "",
        accessionNumber: String,
        requestedProcedureID: String,
        requestedProcedureDescription: String,
        referringPhysicianName: String = "",
        scheduledStationAETitle: String,
        scheduledProcedureStepStartDate: String,
        scheduledProcedureStepStartTime: String = "",
        modality: String,
        scheduledPerformingPhysicianName: String = ""
    ) {
        self.id = id
        self.patientName = patientName
        self.patientID = patientID
        self.patientBirthDate = patientBirthDate
        self.patientSex = patientSex
        self.accessionNumber = accessionNumber
        self.requestedProcedureID = requestedProcedureID
        self.requestedProcedureDescription = requestedProcedureDescription
        self.referringPhysicianName = referringPhysicianName
        self.scheduledStationAETitle = scheduledStationAETitle
        self.scheduledProcedureStepStartDate = scheduledProcedureStepStartDate
        self.scheduledProcedureStepStartTime = scheduledProcedureStepStartTime
        self.modality = modality
        self.scheduledPerformingPhysicianName = scheduledPerformingPhysicianName
    }
}

// MARK: - MWL Filter

/// Filter for Modality Worklist queries.
public struct MWLFilter: Sendable, Equatable {
    /// Filter by date (YYYYMMDD, empty = today).
    public var date: String
    /// Filter by modality.
    public var modality: String
    /// Filter by scheduled station AE title.
    public var stationAETitle: String

    public init(date: String = "", modality: String = "", stationAETitle: String = "") {
        self.date = date
        self.modality = modality
        self.stationAETitle = stationAETitle
    }
}

// MARK: - MPPS Status

/// Status of a Modality Performed Procedure Step.
///
/// The raw values are the Performed Procedure Step Status (0040,0252) terms of
/// PS3.3 C.4.14: IN PROGRESS, COMPLETED, DISCONTINUED (the term has a space, not
/// an underscore). `DICOMNetwork.MPPSStatus` carries the same three; the panel
/// shows the raw value.
/// Reference: DICOM PS3.4 Annex F – Modality Performed Procedure Step SOP Class; PS3.3 C.4.14
public enum MPPSStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case inProgress    = "IN PROGRESS"
    case completed     = "COMPLETED"
    case discontinued  = "DISCONTINUED"

    public var displayName: String {
        switch self {
        case .inProgress:   return "In Progress"
        case .completed:    return "Completed"
        case .discontinued: return "Discontinued"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .inProgress:   return "clock.fill"
        case .completed:    return "checkmark.circle.fill"
        case .discontinued: return "minus.circle.fill"
        }
    }

    /// Whether status can transition to completed.
    public var canComplete: Bool { self == .inProgress }
    /// Whether status can transition to discontinued.
    public var canDiscontinue: Bool { self == .inProgress }
}

// MARK: - MPPS Item

/// A Modality Performed Procedure Step record.
/// Reference: DICOM PS3.4 Annex F – MPPS
public struct MPPSItem: Sendable, Identifiable, Equatable, Hashable {
    /// Unique item identifier.
    public let id: UUID
    /// MPPS SOP Instance UID.
    public var sopInstanceUID: String
    /// Patient name.
    public let patientName: String
    /// Patient ID.
    public let patientID: String
    /// Performed procedure step ID.
    public var performedProcedureStepID: String
    /// Performed procedure step description.
    public var performedProcedureStepDescription: String
    /// Current MPPS status.
    public var status: MPPSStatus
    /// Performed station AE title.
    public let performedStationAETitle: String
    /// Modality.
    public let modality: String
    /// Procedure start date/time.
    public var startDateTime: Date
    /// Procedure end date/time (nil if in progress).
    public var endDateTime: Date?
    /// Radiation dose (mGy), if applicable.
    public var radiationDosemGy: Double?
    /// Exposure in mAs, if applicable.
    public var exposuremAs: Double?
    /// Number of series created.
    public var numberOfSeries: Int
    /// Number of instances created.
    public var numberOfInstances: Int

    public init(
        id: UUID = UUID(),
        sopInstanceUID: String = UUID().uuidString,
        patientName: String,
        patientID: String,
        performedProcedureStepID: String,
        performedProcedureStepDescription: String,
        status: MPPSStatus = .inProgress,
        performedStationAETitle: String,
        modality: String,
        startDateTime: Date = Date(),
        endDateTime: Date? = nil,
        radiationDosemGy: Double? = nil,
        exposuremAs: Double? = nil,
        numberOfSeries: Int = 0,
        numberOfInstances: Int = 0
    ) {
        self.id = id
        self.sopInstanceUID = sopInstanceUID
        self.patientName = patientName
        self.patientID = patientID
        self.performedProcedureStepID = performedProcedureStepID
        self.performedProcedureStepDescription = performedProcedureStepDescription
        self.status = status
        self.performedStationAETitle = performedStationAETitle
        self.modality = modality
        self.startDateTime = startDateTime
        self.endDateTime = endDateTime
        self.radiationDosemGy = radiationDosemGy
        self.exposuremAs = exposuremAs
        self.numberOfSeries = max(0, numberOfSeries)
        self.numberOfInstances = max(0, numberOfInstances)
    }
}

// MARK: - Print Priority

/// Print priority for DICOM print operations.
/// Reference: DICOM PS3.3 C.13.1 – Film Session Module, Print Priority (2000,0020), Table C.13-1
///
/// Duplicates `DICOMNetwork.PrintPriority` (D22; see P-STUDIO-PRINT-ENUMS); the raw
/// values are the C.13.1 Enumerated Values (HIGH, MED, LOW) so the two stay interchangeable.
public enum PrintPriority: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case high   = "HIGH"
    case med    = "MED"
    case low    = "LOW"

    public var displayName: String {
        switch self {
        case .high: return "High"
        case .med:  return "Medium"
        case .low:  return "Low"
        }
    }
}

// MARK: - Print Medium Type

/// Film/paper medium type for DICOM print.
/// Reference: DICOM PS3.3 C.13.1 – Film Session Module, Medium Type (2000,0030), Table C.13-1
///
/// The raw values are Table C.13-1 Defined Terms (PAPER, CLEAR FILM, BLUE FILM).
/// `bluFilm` used to carry `BLU-RAY`, which is not a Medium Type term (D22); the
/// case name is kept, the value is the term. The two MAMMO terms are not
/// offered here — the Print screen's `DICOMNetwork.MediumType` has all five.
public enum PrintMediumType: String, Sendable, Equatable, Hashable, CaseIterable {
    case paper      = "PAPER"
    case clearFilm  = "CLEAR FILM"
    case bluFilm    = "BLUE FILM"

    public var displayName: String {
        switch self {
        case .paper:     return "Paper"
        case .clearFilm: return "Clear Film"
        case .bluFilm:   return "Blue Film"
        }
    }
}

// MARK: - Film Layout

/// Standard film box image display formats.
/// Reference: DICOM PS3.3 C.13.3 – Film Box Module, Image Display Format (2010,0010), Table C.13-3
///
/// `STANDARD\C,R`: C columns of image boxes, then R rows — columns first. Each
/// raw value is `STANDARD\\\(columns),\(rows)` of its own `columns` / `rows`, and
/// `cellCount` is their product. The Networking print panel hands the layout to
/// `DICOMPrintService.printImages(layout:)` as a `PrintLayout(rows:columns:)`.
public enum FilmLayout: String, Sendable, Equatable, Hashable, CaseIterable {
    case standard1x1 = "STANDARD\\1,1"
    case standard1x2 = "STANDARD\\1,2"
    case standard2x1 = "STANDARD\\2,1"
    case standard2x2 = "STANDARD\\2,2"
    case standard2x3 = "STANDARD\\2,3"
    case standard3x3 = "STANDARD\\3,3"
    case standard4x4 = "STANDARD\\4,4"
    case standard4x5 = "STANDARD\\4,5"

    public var displayName: String {
        switch self {
        case .standard1x1: return "1×1"
        case .standard1x2: return "1×2"
        case .standard2x1: return "2×1"
        case .standard2x2: return "2×2"
        case .standard2x3: return "2×3"
        case .standard3x3: return "3×3"
        case .standard4x4: return "4×4"
        case .standard4x5: return "4×5"
        }
    }

    /// Total number of image cells on the film.
    public var cellCount: Int {
        switch self {
        case .standard1x1: return 1
        case .standard1x2: return 2
        case .standard2x1: return 2
        case .standard2x2: return 4
        case .standard2x3: return 6
        case .standard3x3: return 9
        case .standard4x4: return 16
        case .standard4x5: return 20
        }
    }

    /// Number of columns in the layout grid.
    public var columns: Int {
        switch self {
        case .standard1x1: return 1
        case .standard1x2: return 1
        case .standard2x1: return 2
        case .standard2x2: return 2
        case .standard2x3: return 2
        case .standard3x3: return 3
        case .standard4x4: return 4
        case .standard4x5: return 4
        }
    }

    /// Number of rows in the layout grid.
    public var rows: Int {
        switch self {
        case .standard1x1: return 1
        case .standard1x2: return 2
        case .standard2x1: return 1
        case .standard2x2: return 2
        case .standard2x3: return 3
        case .standard3x3: return 3
        case .standard4x4: return 4
        case .standard4x5: return 5
        }
    }
}

// MARK: - Print Film Size

/// Standard film size identifiers for DICOM print.
/// Reference: DICOM PS3.3 C.13.3 – Film Box Module, Film Size ID (2010,0050), Table C.13-3
///
/// The 12 Defined Terms of Table C.13-3. Duplicates `DICOMNetwork.FilmSize`
/// (D22; see P-STUDIO-PRINT-ENUMS).
public enum PrintFilmSize: String, Sendable, Equatable, Hashable, CaseIterable {
    case size8x10    = "8INX10IN"
    case size8_5x11  = "8_5INX11IN"
    case size10x12   = "10INX12IN"
    case size10x14   = "10INX14IN"
    case size11x14   = "11INX14IN"
    case size11x17   = "11INX17IN"
    case size14x14   = "14INX14IN"
    case size14x17   = "14INX17IN"
    case size24x24cm = "24CMX24CM"
    case size24x30cm = "24CMX30CM"
    case a4          = "A4"
    case a3          = "A3"

    public var displayName: String {
        switch self {
        case .size8x10:   return "8\" × 10\""
        case .size8_5x11: return "8.5\" × 11\""
        case .size10x12:  return "10\" × 12\""
        case .size10x14:  return "10\" × 14\""
        case .size11x14:  return "11\" × 14\""
        case .size11x17:  return "11\" × 17\""
        case .size14x14:  return "14\" × 14\""
        case .size14x17:  return "14\" × 17\""
        case .size24x24cm: return "24 × 24 cm"
        case .size24x30cm: return "24 × 30 cm"
        case .a4:          return "A4"
        case .a3:          return "A3"
        }
    }
}

// MARK: - Print Job Status

/// Status of a DICOM print job, as the Networking panel tracks it.
///
/// This is the app's own job state — set from the SCU's result, never read off
/// the wire — but it is shown as its raw value, so the values are the Execution
/// Status (2100,0020) terms of PS3.3 C.13.8 Table C.13-8: PENDING, PRINTING,
/// DONE, FAILURE. `completed` carried `COMPLETED` and `failed` carried `FAILED`,
/// which are not Execution Status terms (D22); the case names are kept.
/// Reference: DICOM PS3.3 C.13.8 – Print Job Module
public enum PrintJobStatus: String, Sendable, Equatable, Hashable {
    case pending   = "PENDING"
    case printing  = "PRINTING"
    case completed = "DONE"
    case failed    = "FAILURE"

    public var displayName: String {
        switch self {
        case .pending:   return "Pending"
        case .printing:  return "Printing"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .pending:   return "clock"
        case .printing:  return "printer.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        }
    }
}

// MARK: - Print Job

/// A DICOM print job encompassing a Film Session and Film Boxes.
/// Reference: DICOM PS3.4 Annex H – Print Management Service Class
public struct PrintJob: Sendable, Identifiable, Equatable {
    /// Unique job identifier.
    public let id: UUID
    /// Human-readable job label.
    public var label: String
    /// Target printer server profile ID.
    public let printerServerProfileID: UUID
    /// Number of copies.
    public var numberOfCopies: Int
    /// Print priority.
    public var priority: PrintPriority
    /// Medium type.
    public var mediumType: PrintMediumType
    /// Film layout.
    public var filmLayout: FilmLayout
    /// Film size.
    public var filmSize: PrintFilmSize
    /// SOP Instance UIDs of images placed in the film.
    public var imageSopInstanceUIDs: [String]
    /// File paths of DICOM images selected for printing.
    public var imageFilePaths: [String]
    /// Security-scoped bookmark data for each image file (macOS sandbox).
    public var imageBookmarks: [Data]
    /// Job status.
    public var status: PrintJobStatus
    /// Error message if failed.
    public var errorMessage: String?
    /// When the job was created.
    public let createdDate: Date
    /// When printing completed.
    public var completedDate: Date?

    public init(
        id: UUID = UUID(),
        label: String,
        printerServerProfileID: UUID,
        numberOfCopies: Int = 1,
        priority: PrintPriority = .med,
        mediumType: PrintMediumType = .paper,
        filmLayout: FilmLayout = .standard2x2,
        filmSize: PrintFilmSize = .size14x17,
        imageSopInstanceUIDs: [String] = [],
        imageFilePaths: [String] = [],
        imageBookmarks: [Data] = [],
        status: PrintJobStatus = .pending,
        errorMessage: String? = nil,
        createdDate: Date = Date(),
        completedDate: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.printerServerProfileID = printerServerProfileID
        self.numberOfCopies = max(1, numberOfCopies)
        self.priority = priority
        self.mediumType = mediumType
        self.filmLayout = filmLayout
        self.filmSize = filmSize
        self.imageSopInstanceUIDs = imageSopInstanceUIDs
        self.imageFilePaths = imageFilePaths
        self.imageBookmarks = imageBookmarks
        self.status = status
        self.errorMessage = errorMessage
        self.createdDate = createdDate
        self.completedDate = completedDate
    }
}

// MARK: - Network Monitoring Stats

/// Snapshot of DICOM network monitoring metrics.
public struct NetworkMonitoringStats: Sendable, Equatable {
    /// Number of connections currently in the pool.
    public var pooledConnectionCount: Int
    /// Number of active associations.
    public var activeAssociationCount: Int
    /// Current inbound throughput in bytes/sec.
    public var inboundBytesPerSecond: Double
    /// Current outbound throughput in bytes/sec.
    public var outboundBytesPerSecond: Double
    /// Total bytes received since startup.
    public var totalBytesReceived: Int64
    /// Total bytes sent since startup.
    public var totalBytesSent: Int64
    /// Total number of operations since startup.
    public var totalOperations: Int
    /// Total number of failed operations since startup.
    public var totalFailedOperations: Int
    /// When the stats snapshot was taken.
    public var timestamp: Date

    public init(
        pooledConnectionCount: Int = 0,
        activeAssociationCount: Int = 0,
        inboundBytesPerSecond: Double = 0,
        outboundBytesPerSecond: Double = 0,
        totalBytesReceived: Int64 = 0,
        totalBytesSent: Int64 = 0,
        totalOperations: Int = 0,
        totalFailedOperations: Int = 0,
        timestamp: Date = Date()
    ) {
        self.pooledConnectionCount = pooledConnectionCount
        self.activeAssociationCount = activeAssociationCount
        self.inboundBytesPerSecond = inboundBytesPerSecond
        self.outboundBytesPerSecond = outboundBytesPerSecond
        self.totalBytesReceived = totalBytesReceived
        self.totalBytesSent = totalBytesSent
        self.totalOperations = totalOperations
        self.totalFailedOperations = totalFailedOperations
        self.timestamp = timestamp
    }

    /// Success rate as a fraction 0.0–1.0. Returns 1.0 if no operations.
    public var successRate: Double {
        guard totalOperations > 0 else { return 1.0 }
        let succeeded = totalOperations - totalFailedOperations
        return Double(succeeded) / Double(totalOperations)
    }
}

// MARK: - Audit Event Outcome

/// Outcome of an auditable DICOM event.
/// Reference: DICOM PS3.15 – Security and System Management Profiles
public enum AuditEventOutcome: String, Sendable, Equatable, Hashable, CaseIterable {
    case success = "SUCCESS"
    case failure = "FAILURE"
    case warning = "WARNING"

    public var displayName: String {
        switch self {
        case .success: return "Success"
        case .failure: return "Failure"
        case .warning: return "Warning"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Audit Log Event Type

/// Type of network event recorded in the audit log.
/// Reference: DICOM PS3.15 – Audit Messages
public enum AuditNetworkEventType: String, Sendable, Equatable, Hashable, CaseIterable {
    case echo         = "C_ECHO"
    case find         = "C_FIND"
    case move         = "C_MOVE"
    case get          = "C_GET"
    case store        = "C_STORE"
    case mwlQuery     = "MWL_QUERY"
    case mppsCreate   = "MPPS_CREATE"
    case mppsUpdate   = "MPPS_UPDATE"
    case printJob     = "PRINT_JOB"
    case association  = "ASSOCIATION"

    public var displayName: String {
        switch self {
        case .echo:        return "C-ECHO"
        case .find:        return "C-FIND"
        case .move:        return "C-MOVE"
        case .get:         return "C-GET"
        case .store:       return "C-STORE"
        case .mwlQuery:    return "MWL Query"
        case .mppsCreate:  return "MPPS Create"
        case .mppsUpdate:  return "MPPS Update"
        case .printJob:    return "Print Job"
        case .association: return "Association"
        }
    }
}

// MARK: - Audit Log Entry

/// A single HIPAA-compliant audit log entry.
/// Reference: DICOM PS3.15 A.5 – Audit Messages
public struct AuditLogEntry: Sendable, Identifiable, Equatable {
    /// Unique entry identifier.
    public let id: UUID
    /// Event type.
    public let eventType: AuditNetworkEventType
    /// Event outcome.
    public let outcome: AuditEventOutcome
    /// Remote server name or AE title.
    public let remoteEntity: String
    /// Local AE title.
    public let localAETitle: String
    /// Additional detail message.
    public let detail: String
    /// When the event occurred.
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        eventType: AuditNetworkEventType,
        outcome: AuditEventOutcome,
        remoteEntity: String,
        localAETitle: String,
        detail: String = "",
        timestamp: Date = Date()
    ) {
        self.id = id
        self.eventType = eventType
        self.outcome = outcome
        self.remoteEntity = remoteEntity
        self.localAETitle = localAETitle
        self.detail = detail
        self.timestamp = timestamp
    }
}

// MARK: - Error Category

/// Category of a DICOM network error.
public enum NetworkErrorCategory: String, Sendable, Equatable, Hashable, CaseIterable {
    case transient   = "TRANSIENT"
    case permanent   = "PERMANENT"
    case timeout     = "TIMEOUT"
    case security    = "SECURITY"
    case protocol_   = "PROTOCOL"

    public var displayName: String {
        switch self {
        case .transient:  return "Transient"
        case .permanent:  return "Permanent"
        case .timeout:    return "Timeout"
        case .security:   return "Security"
        case .protocol_:  return "Protocol"
        }
    }

    /// Whether the error is recoverable via retry.
    public var isRetryable: Bool {
        switch self {
        case .transient, .timeout: return true
        case .permanent, .security, .protocol_: return false
        }
    }

    /// Recovery suggestion for the user.
    public var recoverySuggestion: String {
        switch self {
        case .transient:  return "Wait a moment and retry the operation."
        case .permanent:  return "Check server configuration and AE titles."
        case .timeout:    return "Increase timeout or check network connectivity."
        case .security:   return "Verify TLS configuration and certificates."
        case .protocol_:  return "Ensure the server supports the requested SOP class."
        }
    }
}

// MARK: - Network Error Item

/// A categorized network error with recovery information.
public struct NetworkErrorItem: Sendable, Identifiable, Equatable {
    /// Unique error identifier.
    public let id: UUID
    /// Error category.
    public let category: NetworkErrorCategory
    /// Error message.
    public let message: String
    /// Server profile related to the error.
    public let serverProfileID: UUID?
    /// When the error occurred.
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        category: NetworkErrorCategory,
        message: String,
        serverProfileID: UUID? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.message = message
        self.serverProfileID = serverProfileID
        self.timestamp = timestamp
    }
}

// MARK: - Bandwidth Limit

/// Bandwidth limiting configuration for transfers.
public struct BandwidthLimit: Sendable, Equatable, Hashable {
    /// Whether bandwidth limiting is enabled.
    public var isEnabled: Bool
    /// Maximum bytes per second (0 = unlimited).
    public var maxBytesPerSecond: Int64

    public init(isEnabled: Bool = false, maxBytesPerSecond: Int64 = 0) {
        self.isEnabled = isEnabled
        self.maxBytesPerSecond = max(0, maxBytesPerSecond)
    }

    /// Effective limit: nil means unlimited.
    public var effectiveLimit: Int64? {
        isEnabled && maxBytesPerSecond > 0 ? maxBytesPerSecond : nil
    }
}
