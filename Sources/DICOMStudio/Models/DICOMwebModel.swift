// DICOMwebModel.swift
// DICOMStudio
// NEMA-verified: 2026a, checked 2026-10-05 — UPSState.allowedTransitions diffed against PS3.4 2026a Table CC.1.1-2 (Change State rows: SCHEDULED→IN PROGRESS; IN PROGRESS→COMPLETED/CANCELED; SCHEDULED→CANCELED removed, C310H; SCHEDULED is never a target, C303H); UPSState.dicomTerm against PS3.3 2026a C.30.1 (4/4), UPSPriority against C.30.2 (3/3); QIDOQueryLevel resources and WADOProtocol.protocolDescription parameter names against PS3.18 2026a Tables 10.6.1-1 and 9.1.2-1 (3/3, 4/4); the raw values IN_PROGRESS / CANCELLED are Studio-local spellings (P-STUDIO-UPS-STATE-RAW); DICOMwebTLSMode names TLS versions, not PS3.15 Annex B profiles (P-STUDIO-TLS-PROFILES); tabs, auth methods, job statuses, event-channel states and performance statistics carry no DICOM-standard data
//
// DICOM Studio — Data models for the DICOMweb Integration Hub (Milestone 10)
// Reference: DICOM PS3.18 (Web Services)
// Reference: DICOM PS3.19 (Application Hosting)

import Foundation

// MARK: - Navigation Tab

/// Navigation tabs for the DICOMweb Integration Hub.
public enum DICOMwebTab: String, Sendable, Equatable, Hashable, CaseIterable {
    case serverConfig        = "SERVER_CONFIG"
    case qidoRS              = "QIDO_RS"
    case wadoRS              = "WADO_RS"
    case stowRS              = "STOW_RS"
    case upsRS               = "UPS_RS"
    case jpipStreaming        = "JPIP_STREAMING"
    case performanceDashboard = "PERFORMANCE_DASHBOARD"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .serverConfig:         return "Server Config"
        case .qidoRS:               return "QIDO-RS"
        case .wadoRS:               return "WADO-RS"
        case .stowRS:               return "STOW-RS"
        case .upsRS:                return "UPS-RS"
        case .jpipStreaming:         return "JPIP"
        case .performanceDashboard: return "Performance"
        }
    }

    /// SF Symbol name for this tab.
    public var sfSymbol: String {
        switch self {
        case .serverConfig:         return "server.rack"
        case .qidoRS:               return "magnifyingglass"
        case .wadoRS:               return "arrow.down.circle"
        case .stowRS:               return "arrow.up.circle"
        case .upsRS:                return "list.bullet.clipboard"
        case .jpipStreaming:         return "arrow.down.to.line"
        case .performanceDashboard: return "chart.bar"
        }
    }
}

// MARK: - Authentication Method

/// HTTP authentication method for DICOMweb connections.
/// Reference: DICOM PS3.18 8.11 Security and Privacy (names no mechanism; these are HTTP/OAuth2 conventions)
public enum DICOMwebAuthMethod: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case none       = "NONE"
    case bearer     = "BEARER"
    case basic      = "BASIC"
    case oauth2PKCE = "OAUTH2_PKCE"
    case jwt        = "JWT"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .none:       return "None"
        case .bearer:     return "Bearer Token"
        case .basic:      return "Basic Auth"
        case .oauth2PKCE: return "OAuth 2.0 (PKCE)"
        case .jwt:        return "JWT"
        }
    }
}

// MARK: - TLS Mode

/// TLS security mode for DICOMweb HTTPS connections.
/// Reference: DICOM PS3.15 Annex B – Secure Transport Connection Profiles
public enum DICOMwebTLSMode: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case none        = "NONE"
    case compatible  = "COMPATIBLE"
    case strict      = "STRICT"
    case development = "DEVELOPMENT"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .none:        return "No TLS (HTTP)"
        case .compatible:  return "TLS (Compatible)"
        case .strict:      return "TLS (Strict)"
        case .development: return "TLS (Dev / Self-Signed)"
        }
    }

    /// Whether TLS is enabled for this mode.
    public var isEnabled: Bool { self != .none }

    /// Whether self-signed certificates are accepted.
    public var allowsSelfSigned: Bool { self == .development }
}

// MARK: - Connection Status

/// Connection status of a DICOMweb server endpoint.
public enum DICOMwebConnectionStatus: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case unknown = "UNKNOWN"
    case testing = "TESTING"
    case online  = "ONLINE"
    case offline = "OFFLINE"
    case error   = "ERROR"

    /// Human-readable label.
    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .testing: return "Testing…"
        case .online:  return "Online"
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
        case .offline: return "xmark.circle"
        case .error:   return "exclamationmark.triangle.fill"
        }
    }

    /// Whether the server is reachable and responding.
    public var isConnected: Bool { self == .online }
}

// MARK: - Service Type

/// DICOMweb service types supported by a server.
/// Reference: DICOM PS3.18 Chapters 9 (URI Service), 10 (Studies Service) and 11 (Worklist Service)
public enum DICOMwebServiceType: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case wadoRS = "WADO_RS"
    case qidoRS = "QIDO_RS"
    case stowRS = "STOW_RS"
    case upsRS  = "UPS_RS"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .wadoRS: return "WADO-RS"
        case .qidoRS: return "QIDO-RS"
        case .stowRS: return "STOW-RS"
        case .upsRS:  return "UPS-RS"
        }
    }

    /// Short service abbreviation.
    public var abbreviation: String {
        switch self {
        case .wadoRS: return "WADO"
        case .qidoRS: return "QIDO"
        case .stowRS: return "STOW"
        case .upsRS:  return "UPS"
        }
    }
}

// MARK: - Server Profile

/// A DICOMweb server configuration profile.
/// Reference: DICOM PS3.18 Chapter 8 Common Aspects of DICOM Web Services (8.2 Target Resources: Base URI)
public struct DICOMwebServerProfile: Sendable, Identifiable, Equatable, Hashable, Codable {
    /// Unique profile identifier.
    public let id: UUID
    /// Human-readable profile name.
    public var name: String
    /// Base URL of the DICOMweb server (e.g. https://pacs.example.com/wado).
    public var baseURL: String
    /// HTTP authentication method.
    public var authMethod: DICOMwebAuthMethod
    /// Bearer token (used when authMethod == .bearer or .jwt).
    public var bearerToken: String
    /// Username for basic authentication.
    public var username: String
    /// Password for basic authentication.
    public var password: String
    /// TLS mode for this connection.
    public var tlsMode: DICOMwebTLSMode
    /// Current connection status.
    public var connectionStatus: DICOMwebConnectionStatus
    /// Last connection error message, if any.
    public var lastConnectionError: String?
    /// Whether this is the default active server.
    public var isDefault: Bool
    /// Services advertised or confirmed as supported by this server.
    public var supportedServices: Set<DICOMwebServiceType>
    /// Date this profile was created.
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "",
        baseURL: String = "",
        authMethod: DICOMwebAuthMethod = .none,
        bearerToken: String = "",
        username: String = "",
        password: String = "",
        tlsMode: DICOMwebTLSMode = .none,
        connectionStatus: DICOMwebConnectionStatus = .unknown,
        lastConnectionError: String? = nil,
        isDefault: Bool = false,
        supportedServices: Set<DICOMwebServiceType> = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.authMethod = authMethod
        self.bearerToken = bearerToken
        self.username = username
        self.password = password
        self.tlsMode = tlsMode
        self.connectionStatus = connectionStatus
        self.lastConnectionError = lastConnectionError
        self.isDefault = isDefault
        self.supportedServices = supportedServices
        self.createdAt = createdAt
    }

    /// Whether the profile has a non-empty, well-formed base URL.
    public var isConfigured: Bool { !baseURL.isEmpty && URL(string: baseURL) != nil }
}

// MARK: - QIDO-RS Query Level

/// Information model level for a QIDO-RS search request.
/// Reference: DICOM PS3.18 10.6 Search Transaction, Table 10.6.1-1 (All Studies, All Series, All Instances)
public enum QIDOQueryLevel: String, Sendable, Equatable, Hashable, CaseIterable {
    case study    = "STUDY"
    case series   = "SERIES"
    case instance = "INSTANCE"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .study:    return "Study"
        case .series:   return "Series"
        case .instance: return "Instance"
        }
    }

    /// SF Symbol for this level.
    public var sfSymbol: String {
        switch self {
        case .study:    return "folder.fill"
        case .series:   return "rectangle.stack.fill"
        case .instance: return "doc.fill"
        }
    }
}

// MARK: - QIDO-RS Query Parameters

/// Parameters for a QIDO-RS search request.
/// Reference: DICOM PS3.18 8.3.4 Search Query Parameters (Table 8.3.4-1: fuzzymatching, limit, offset)
/// and Table 10.6.1-5 Required Matching Attributes
public struct QIDOQueryParams: Sendable, Equatable, Hashable {
    /// Unique identifier for this query.
    public let id: UUID
    /// Patient name filter (supports * wildcard).
    public var patientName: String
    /// Patient ID filter.
    public var patientID: String
    /// Study date range start (YYYYMMDD).
    public var studyDateFrom: String
    /// Study date range end (YYYYMMDD).
    public var studyDateTo: String
    /// Modality filter.
    public var modality: String
    /// Accession number filter.
    public var accessionNumber: String
    /// Study description filter.
    public var studyDescription: String
    /// Information model level.
    public var queryLevel: QIDOQueryLevel
    /// Maximum number of results to return.
    public var limit: Int
    /// Number of results to skip (pagination offset).
    public var offset: Int
    /// Whether to enable fuzzy matching for string attributes.
    public var fuzzyMatching: Bool
    /// Whether to request the server to include fuzzy matching details.
    public var includeFuzzyMatching: Bool

    public init(
        id: UUID = UUID(),
        patientName: String = "",
        patientID: String = "",
        studyDateFrom: String = "",
        studyDateTo: String = "",
        modality: String = "",
        accessionNumber: String = "",
        studyDescription: String = "",
        queryLevel: QIDOQueryLevel = .study,
        limit: Int = 100,
        offset: Int = 0,
        fuzzyMatching: Bool = false,
        includeFuzzyMatching: Bool = false
    ) {
        self.id = id
        self.patientName = patientName
        self.patientID = patientID
        self.studyDateFrom = studyDateFrom
        self.studyDateTo = studyDateTo
        self.modality = modality
        self.accessionNumber = accessionNumber
        self.studyDescription = studyDescription
        self.queryLevel = queryLevel
        self.limit = limit
        self.offset = offset
        self.fuzzyMatching = fuzzyMatching
        self.includeFuzzyMatching = includeFuzzyMatching
    }

    /// Whether all text filter fields are empty.
    public var isEmpty: Bool {
        patientName.isEmpty &&
        patientID.isEmpty &&
        studyDateFrom.isEmpty &&
        studyDateTo.isEmpty &&
        modality.isEmpty &&
        accessionNumber.isEmpty &&
        studyDescription.isEmpty
    }
}

// MARK: - QIDO-RS Result Item

/// A single result item returned from a QIDO-RS search.
/// Reference: DICOM PS3.18 10.6.3 Response (Tables 10.6.3-3, 10.6.3-4, 10.6.3-5)
public struct QIDOResultItem: Sendable, Identifiable, Equatable, Hashable {
    /// Unique local identifier.
    public let id: UUID
    /// Study Instance UID.
    public var studyInstanceUID: String
    /// Series Instance UID (nil for study-level results).
    public var seriesInstanceUID: String?
    /// SOP Instance UID (nil for study/series-level results).
    public var sopInstanceUID: String?
    /// Patient name.
    public var patientName: String
    /// Patient ID.
    public var patientID: String
    /// Study date (YYYYMMDD).
    public var studyDate: String
    /// Modality or modalities in series.
    public var modality: String
    /// Study description.
    public var studyDescription: String
    /// Number of series in the study (nil if unknown).
    public var numberOfSeries: Int?
    /// Number of instances in the study or series (nil if unknown).
    public var numberOfInstances: Int?
    /// Query level at which this result was returned.
    public var queryLevel: QIDOQueryLevel

    public init(
        id: UUID = UUID(),
        studyInstanceUID: String = "",
        seriesInstanceUID: String? = nil,
        sopInstanceUID: String? = nil,
        patientName: String = "",
        patientID: String = "",
        studyDate: String = "",
        modality: String = "",
        studyDescription: String = "",
        numberOfSeries: Int? = nil,
        numberOfInstances: Int? = nil,
        queryLevel: QIDOQueryLevel = .study
    ) {
        self.id = id
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.sopInstanceUID = sopInstanceUID
        self.patientName = patientName
        self.patientID = patientID
        self.studyDate = studyDate
        self.modality = modality
        self.studyDescription = studyDescription
        self.numberOfSeries = numberOfSeries
        self.numberOfInstances = numberOfInstances
        self.queryLevel = queryLevel
    }
}

// MARK: - WADO Protocol

/// The WADO protocol variant to use for retrieval.
/// Reference: DICOM PS3.18 Chapter 9 URI Service (Table 9.1.2-1) and 10.4 Retrieve Transaction
public enum WADOProtocol: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// WADO-RS (RESTful) — modern protocol using path-based URLs.
    /// Supported by dcm4chee5, Orthanc, Google Cloud Healthcare, etc.
    case wadoRS = "WADO_RS"
    /// WADO-URI — legacy protocol using query parameters.
    /// Supported by dcm4chee2, older PACS servers.
    case wadoURI = "WADO_URI"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .wadoRS:  return "WADO-RS (RESTful)"
        case .wadoURI: return "WADO-URI (Legacy)"
        }
    }

    /// Short description of the protocol.
    public var protocolDescription: String {
        switch self {
        case .wadoRS:
            return "Modern RESTful API — /studies/{uid}/series/{uid}/instances/{uid}"
        case .wadoURI:
            return "Legacy query-parameter API — ?requestType=WADO&studyUID=...&seriesUID=...&objectUID=..."
        }
    }
}

// MARK: - WADO-RS Retrieve Mode

/// The scope or mode for a WADO-RS retrieve request.
/// Reference: DICOM PS3.18 10.4 Retrieve Transaction (Tables 10.4.1-1, 10.4.1-3, 10.4.1.5-1, 10.4.1.6-1)
public enum WADORetrieveMode: String, Sendable, Equatable, Hashable, CaseIterable {
    case study    = "STUDY"
    case series   = "SERIES"
    case instance = "INSTANCE"
    case frames   = "FRAMES"
    case rendered = "RENDERED"
    case bulkData = "BULK_DATA"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .study:    return "Study"
        case .series:   return "Series"
        case .instance: return "Instance"
        case .frames:   return "Frames"
        case .rendered: return "Rendered"
        case .bulkData: return "Bulk Data"
        }
    }

    /// SF Symbol for this retrieve mode.
    public var sfSymbol: String {
        switch self {
        case .study:    return "folder.fill"
        case .series:   return "rectangle.stack.fill"
        case .instance: return "doc.fill"
        case .frames:   return "film.stack"
        case .rendered: return "photo.fill"
        case .bulkData: return "cylinder.fill"
        }
    }
}

// MARK: - WADO-RS Retrieve Status

/// Status of a WADO-RS retrieve job.
public enum WADORetrieveStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case queued     = "QUEUED"
    case inProgress = "IN_PROGRESS"
    case completed  = "COMPLETED"
    case failed     = "FAILED"
    case cancelled  = "CANCELLED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .queued:     return "Queued"
        case .inProgress: return "In Progress"
        case .completed:  return "Completed"
        case .failed:     return "Failed"
        case .cancelled:  return "Cancelled"
        }
    }

    /// Whether this status represents a terminal (non-transitioning) state.
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        case .queued, .inProgress:            return false
        }
    }
}

// MARK: - WADO-RS Retrieve Job

/// A WADO-RS retrieve operation.
/// Reference: DICOM PS3.18 Section 10.4 – Retrieve Transaction
public struct WADORetrieveJob: Sendable, Identifiable, Equatable, Hashable {
    /// Unique job identifier.
    public let id: UUID
    /// Study Instance UID to retrieve.
    public var studyInstanceUID: String
    /// Series Instance UID (nil for study-level retrieval).
    public var seriesInstanceUID: String?
    /// SOP Instance UID (nil for study/series-level retrieval).
    public var sopInstanceUID: String?
    /// Frame numbers to retrieve (empty = all frames).
    public var frameNumbers: [Int]
    /// Retrieve mode for this job.
    public var retrieveMode: WADORetrieveMode
    /// Current status.
    public var status: WADORetrieveStatus
    /// Error message when status is .failed.
    public var errorMessage: String?
    /// Bytes received so far.
    public var bytesReceived: Int64
    /// Total bytes expected (nil if unknown).
    public var totalBytes: Int64?
    /// Number of instances received.
    public var instancesReceived: Int
    /// Total number of instances expected (nil if unknown).
    public var totalInstances: Int?
    /// Time the job was started.
    public var startTime: Date?
    /// Time the job finished (terminal state reached).
    public var completionTime: Date?

    public init(
        id: UUID = UUID(),
        studyInstanceUID: String = "",
        seriesInstanceUID: String? = nil,
        sopInstanceUID: String? = nil,
        frameNumbers: [Int] = [],
        retrieveMode: WADORetrieveMode = .study,
        status: WADORetrieveStatus = .queued,
        errorMessage: String? = nil,
        bytesReceived: Int64 = 0,
        totalBytes: Int64? = nil,
        instancesReceived: Int = 0,
        totalInstances: Int? = nil,
        startTime: Date? = nil,
        completionTime: Date? = nil
    ) {
        self.id = id
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.sopInstanceUID = sopInstanceUID
        self.frameNumbers = frameNumbers
        self.retrieveMode = retrieveMode
        self.status = status
        self.errorMessage = errorMessage
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.instancesReceived = instancesReceived
        self.totalInstances = totalInstances
        self.startTime = startTime
        self.completionTime = completionTime
    }

    /// Progress as a fraction in [0, 1], or nil if total is unknown.
    public var progressFraction: Double? {
        guard let total = totalBytes, total > 0 else { return nil }
        return min(1.0, Double(bytesReceived) / Double(total))
    }

    /// Estimated transfer rate in bytes per second, or nil if not started.
    public var transferRateBytesPerSec: Double? {
        guard let start = startTime, bytesReceived > 0 else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return nil }
        return Double(bytesReceived) / elapsed
    }
}

// MARK: - STOW-RS Duplicate Handling

/// Policy for handling duplicate DICOM instances during a STOW-RS upload.
/// Reference: DICOM PS3.18 10.5 Store Transaction (Table 10.5.3-1: 409 Conflict)
public enum STOWDuplicateHandling: String, Sendable, Equatable, Hashable, CaseIterable {
    case reject    = "REJECT"
    case overwrite = "OVERWRITE"
    case ignore    = "IGNORE"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .reject:    return "Reject Duplicates"
        case .overwrite: return "Overwrite Duplicates"
        case .ignore:    return "Ignore Duplicates"
        }
    }
}

// MARK: - STOW-RS Upload Status

/// Status of a STOW-RS upload job.
public enum STOWUploadStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case queued     = "QUEUED"
    case validating = "VALIDATING"
    case uploading  = "UPLOADING"
    case completed  = "COMPLETED"
    case rejected   = "REJECTED"
    case failed     = "FAILED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .queued:     return "Queued"
        case .validating: return "Validating"
        case .uploading:  return "Uploading"
        case .completed:  return "Completed"
        case .rejected:   return "Rejected"
        case .failed:     return "Failed"
        }
    }

    /// Whether this status represents a terminal (non-transitioning) state.
    public var isTerminal: Bool {
        switch self {
        case .completed, .rejected, .failed: return true
        case .queued, .validating, .uploading: return false
        }
    }
}

// MARK: - STOW-RS Upload Job

/// A STOW-RS store (upload) operation.
/// Reference: DICOM PS3.18 Section 10.5 – Store Transaction
public struct STOWUploadJob: Sendable, Identifiable, Equatable, Hashable {
    /// Unique job identifier.
    public let id: UUID
    /// File paths of DICOM instances to upload.
    public var filePaths: [String]
    /// Current status.
    public var status: STOWUploadStatus
    /// Total number of files in this job.
    public var totalFiles: Int
    /// Number of files successfully uploaded.
    public var uploadedFiles: Int
    /// Number of files that failed or were rejected.
    public var failedFiles: Int
    /// Bytes uploaded so far.
    public var bytesUploaded: Int64
    /// Total bytes to upload.
    public var totalBytes: Int64
    /// How to handle duplicate instances.
    public var duplicateHandling: STOWDuplicateHandling
    /// Whether DICOM validation is run before upload.
    public var validationEnabled: Bool
    /// Number of concurrent upload streams.
    public var pipelineConcurrency: Int
    /// Error or rejection message, if any.
    public var errorMessage: String?
    /// Time the job was started.
    public var startTime: Date?
    /// Time the job finished (terminal state reached).
    public var completionTime: Date?

    public init(
        id: UUID = UUID(),
        filePaths: [String] = [],
        status: STOWUploadStatus = .queued,
        totalFiles: Int = 0,
        uploadedFiles: Int = 0,
        failedFiles: Int = 0,
        bytesUploaded: Int64 = 0,
        totalBytes: Int64 = 0,
        duplicateHandling: STOWDuplicateHandling = .reject,
        validationEnabled: Bool = true,
        pipelineConcurrency: Int = 5,
        errorMessage: String? = nil,
        startTime: Date? = nil,
        completionTime: Date? = nil
    ) {
        self.id = id
        self.filePaths = filePaths
        self.status = status
        self.totalFiles = totalFiles
        self.uploadedFiles = uploadedFiles
        self.failedFiles = failedFiles
        self.bytesUploaded = bytesUploaded
        self.totalBytes = totalBytes
        self.duplicateHandling = duplicateHandling
        self.validationEnabled = validationEnabled
        self.pipelineConcurrency = pipelineConcurrency
        self.errorMessage = errorMessage
        self.startTime = startTime
        self.completionTime = completionTime
    }

    /// Upload progress as a fraction in [0, 1].
    public var progressFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, Double(bytesUploaded) / Double(totalBytes))
    }
}

// MARK: - UPS-RS State

/// State of a Unified Procedure Step (UPS) workitem.
/// Reference: DICOM PS3.4 Annex CC – Unified Procedure Step Service Class
public enum UPSState: String, Sendable, Equatable, Hashable, CaseIterable {
    case scheduled  = "SCHEDULED"
    case inProgress = "IN_PROGRESS"
    case completed  = "COMPLETED"
    case cancelled  = "CANCELLED"

    /// Human-readable display name (the PS3.3 C.30.1 term in title case; CANCELED is the
    /// standard's spelling).
    public var displayName: String {
        switch self {
        case .scheduled:  return "Scheduled"
        case .inProgress: return "In Progress"
        case .completed:  return "Completed"
        case .cancelled:  return "Canceled"
        }
    }

    /// The Procedure Step State (0074,1000) term of PS3.3 C.30.1 for this case:
    /// SCHEDULED, IN PROGRESS, COMPLETED or CANCELED (the raw values are Studio-local spellings).
    var dicomTerm: String {
        switch self {
        case .scheduled:  return "SCHEDULED"
        case .inProgress: return "IN PROGRESS"
        case .completed:  return "COMPLETED"
        case .cancelled:  return "CANCELED"
        }
    }

    /// SF Symbol for this state.
    public var sfSymbol: String {
        switch self {
        case .scheduled:  return "clock"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .completed:  return "checkmark.circle.fill"
        case .cancelled:  return "xmark.circle"
        }
    }

    /// The target states a Change Workitem State request (PS3.18 11.7, N-ACTION Change UPS State)
    /// may ask for from this state, per PS3.4 Table CC.1.1-2:
    /// SCHEDULED → IN PROGRESS only (Change State to CANCELED from SCHEDULED is refused with C310H;
    /// a SCHEDULED workitem is cancelled by the origin server on Request Cancellation, PS3.18 11.8),
    /// IN PROGRESS → COMPLETED or CANCELED, final states → none. SCHEDULED is never a target (C303H).
    public var allowedTransitions: [UPSState] {
        switch self {
        case .scheduled:  return [.inProgress]
        case .inProgress: return [.completed, .cancelled]
        case .completed:  return []
        case .cancelled:  return []
        }
    }
}

// MARK: - UPS-RS Priority

/// Scheduled procedure step priority for a UPS workitem.
/// Reference: DICOM PS3.3 C.30.2 Scheduled Procedure Step Priority (0074,1200): HIGH, MEDIUM, LOW
public enum UPSPriority: String, Sendable, Equatable, Hashable, CaseIterable {
    case high   = "HIGH"
    case medium = "MEDIUM"
    case low    = "LOW"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .high:   return "High"
        case .medium: return "Medium"
        case .low:    return "Low"
        }
    }

    /// SF Symbol for this priority level.
    public var sfSymbol: String {
        switch self {
        case .high:   return "exclamationmark.circle.fill"
        case .medium: return "circle.fill"
        case .low:    return "arrow.down.circle"
        }
    }
}

// MARK: - UPS-RS Event Type

/// Display categories for UPS event reports. They group the Event Type IDs of PS3.4 Table CC.2.4-1
/// (1 State Report, 2 Cancel Requested, 3 Progress Report, 4 SCP Status Change, 5 Assigned);
/// `stepStateChange` has no counterpart and is never produced by the event channel.
/// Reference: DICOM PS3.18 11.13 Workitem Event Reports; PS3.4 Table CC.2.4-1
public enum UPSEventType: String, Sendable, Equatable, Hashable, CaseIterable {
    case stateChange           = "STATE_CHANGE"
    case progressChange        = "PROGRESS_CHANGE"
    case stepStateChange       = "STEP_STATE_CHANGE"
    case cancellationRequested = "CANCELLATION_REQUESTED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .stateChange:           return "State Change"
        case .progressChange:        return "Progress Change"
        case .stepStateChange:       return "Step State Change"
        case .cancellationRequested: return "Cancellation Requested"
        }
    }
}

// MARK: - UPS-RS Event Subscription

/// A subscription to UPS-RS watch events for one or all workitems.
/// Reference: DICOM PS3.18 11.10 Subscribe Transaction (Table 11.1.1-1 Worklist / Workitem Subscription)
public struct UPSEventSubscription: Sendable, Identifiable, Equatable, Hashable {
    /// Unique subscription identifier.
    public let id: UUID
    /// Workitem UID to watch; nil indicates a global (all workitems) subscription.
    public var workitemUID: String?
    /// Event types included in this subscription.
    public var eventTypes: Set<UPSEventType>
    /// Whether the subscription is currently active.
    public var isActive: Bool
    /// Time the most recent event was received.
    public var lastEventTime: Date?

    public init(
        id: UUID = UUID(),
        workitemUID: String? = nil,
        eventTypes: Set<UPSEventType> = [],
        isActive: Bool = false,
        lastEventTime: Date? = nil
    ) {
        self.id = id
        self.workitemUID = workitemUID
        self.eventTypes = eventTypes
        self.isActive = isActive
        self.lastEventTime = lastEventTime
    }

    /// Whether this is a global subscription (all workitems).
    public var isGlobal: Bool { workitemUID == nil }
}

// MARK: - UPS Workitem

/// A Unified Procedure Step workitem retrieved from a UPS-RS server.
/// Reference: DICOM PS3.4 Annex CC
public struct UPSWorkitem: Sendable, Identifiable, Equatable, Hashable {
    /// Unique local identifier.
    public let id: UUID
    /// DICOM Workitem UID (SOP Instance UID of the UPS object).
    public var workitemUID: String
    /// Patient name.
    public var patientName: String
    /// Patient ID.
    public var patientID: String
    /// Procedure step label describing the scheduled work.
    public var procedureStepLabel: String
    /// Scheduled procedure step start date/time.
    public var scheduledDateTime: Date?
    /// Current state.
    public var state: UPSState
    /// Priority of this workitem.
    public var priority: UPSPriority
    /// Free-text progress information.
    public var progressInformation: String
    /// Completion percentage in the range 0–100.
    public var completionPercentage: Int

    public init(
        id: UUID = UUID(),
        workitemUID: String = "",
        patientName: String = "",
        patientID: String = "",
        procedureStepLabel: String = "",
        scheduledDateTime: Date? = nil,
        state: UPSState = .scheduled,
        priority: UPSPriority = .medium,
        progressInformation: String = "",
        completionPercentage: Int = 0
    ) {
        self.id = id
        self.workitemUID = workitemUID
        self.patientName = patientName
        self.patientID = patientID
        self.procedureStepLabel = procedureStepLabel
        self.scheduledDateTime = scheduledDateTime
        self.state = state
        self.priority = priority
        self.progressInformation = progressInformation
        self.completionPercentage = max(0, min(100, completionPercentage))
    }
}

// MARK: - UPS Event Channel State

/// Connection state for the UPS WebSocket event channel.
public enum UPSEventChannelState: String, Sendable, Equatable, Hashable, CaseIterable {
    case disconnected    = "DISCONNECTED"
    case connecting      = "CONNECTING"
    case connected       = "CONNECTED"
    case reconnecting    = "RECONNECTING"
    case closed          = "CLOSED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .disconnected:  return "Disconnected"
        case .connecting:    return "Connecting"
        case .connected:     return "Connected"
        case .reconnecting:  return "Reconnecting"
        case .closed:        return "Closed"
        }
    }
}

// MARK: - UPS Received Event

/// A UPS event notification received over the WebSocket event channel.
public struct UPSReceivedEvent: Sendable, Identifiable, Equatable, Hashable {
    /// Unique local identifier.
    public let id: UUID
    /// The type of event received.
    public var eventType: UPSEventType
    /// The workitem UID this event relates to.
    public var workitemUID: String
    /// Transaction UID (if applicable).
    public var transactionUID: String?
    /// Timestamp when the event was received.
    public var receivedAt: Date
    /// Human-readable summary of the event.
    public var summary: String

    // MARK: - Event-Specific Details (from raw JSON payload)

    /// Previous workitem state (for state change events).
    public var previousState: String?
    /// New workitem state (for state change events).
    public var newState: String?
    /// Reason for state change or cancellation.
    public var reason: String?
    /// Progress percentage (for progress events), 0–100.
    public var progressPercentage: Int?
    /// Progress description text (for progress events).
    public var progressDescription: String?
    /// Contact display name (for progress or cancel events).
    public var contactDisplayName: String?

    // MARK: - Workitem Context (fetched after event receipt)

    /// Patient name associated with the workitem.
    public var patientName: String?
    /// Patient ID associated with the workitem.
    public var patientID: String?
    /// Procedure step label (human-readable workitem description).
    public var procedureStepLabel: String?
    /// Scheduled procedure step start date/time.
    public var scheduledStartDateTime: String?
    /// Current workitem state.
    public var workitemState: String?
    /// Workitem priority.
    public var workitemPriority: String?
    /// Accession number.
    public var accessionNumber: String?
    /// Whether workitem context has been loaded.
    public var isWorkitemContextLoaded: Bool

    public init(
        id: UUID = UUID(),
        eventType: UPSEventType = .stateChange,
        workitemUID: String = "",
        transactionUID: String? = nil,
        receivedAt: Date = Date(),
        summary: String = "",
        previousState: String? = nil,
        newState: String? = nil,
        reason: String? = nil,
        progressPercentage: Int? = nil,
        progressDescription: String? = nil,
        contactDisplayName: String? = nil,
        patientName: String? = nil,
        patientID: String? = nil,
        procedureStepLabel: String? = nil,
        scheduledStartDateTime: String? = nil,
        workitemState: String? = nil,
        workitemPriority: String? = nil,
        accessionNumber: String? = nil,
        isWorkitemContextLoaded: Bool = false
    ) {
        self.id = id
        self.eventType = eventType
        self.workitemUID = workitemUID
        self.transactionUID = transactionUID
        self.receivedAt = receivedAt
        self.summary = summary
        self.previousState = previousState
        self.newState = newState
        self.reason = reason
        self.progressPercentage = progressPercentage
        self.progressDescription = progressDescription
        self.contactDisplayName = contactDisplayName
        self.patientName = patientName
        self.patientID = patientID
        self.procedureStepLabel = procedureStepLabel
        self.scheduledStartDateTime = scheduledStartDateTime
        self.workitemState = workitemState
        self.workitemPriority = workitemPriority
        self.accessionNumber = accessionNumber
        self.isWorkitemContextLoaded = isWorkitemContextLoaded
    }
}

// MARK: - Cache Statistics

/// Statistics for the DICOMweb response cache.
public struct DICOMwebCacheStats: Sendable, Equatable, Hashable {
    /// Number of cache hits.
    public var hitCount: Int
    /// Number of cache misses.
    public var missCount: Int
    /// Number of entries evicted from the cache.
    public var evictionCount: Int
    /// Current cache size in bytes.
    public var currentSizeBytes: Int64
    /// Maximum allowed cache size in bytes.
    public var maxSizeBytes: Int64

    public init(
        hitCount: Int = 0,
        missCount: Int = 0,
        evictionCount: Int = 0,
        currentSizeBytes: Int64 = 0,
        maxSizeBytes: Int64 = 100 * 1024 * 1024
    ) {
        self.hitCount = hitCount
        self.missCount = missCount
        self.evictionCount = evictionCount
        self.currentSizeBytes = currentSizeBytes
        self.maxSizeBytes = maxSizeBytes
    }

    /// Cache hit rate as a fraction in [0, 1].
    public var hitRate: Double {
        let total = hitCount + missCount
        guard total > 0 else { return 0 }
        return Double(hitCount) / Double(total)
    }

    /// Cache utilization as a fraction of maxSizeBytes in [0, 1].
    public var utilizationFraction: Double {
        guard maxSizeBytes > 0 else { return 0 }
        return min(1.0, Double(currentSizeBytes) / Double(maxSizeBytes))
    }
}

// MARK: - Performance Statistics

/// Aggregated runtime performance statistics for a DICOMweb session.
public struct DICOMwebPerformanceStats: Sendable, Equatable, Hashable {
    /// Number of active HTTP/2 streams.
    public var http2StreamsActive: Int
    /// Maximum concurrent HTTP/2 streams negotiated with the server.
    public var http2MaxStreams: Int
    /// Pipelined requests per second.
    public var pipelinedRequestsPerSec: Double
    /// Average round-trip latency in milliseconds.
    public var averageLatencyMs: Double
    /// Peak round-trip latency in milliseconds.
    public var peakLatencyMs: Double
    /// Compression ratio (1.0 = no compression; <1.0 = compressed).
    public var compressionRatio: Double
    /// Cache statistics.
    public var cacheStats: DICOMwebCacheStats
    /// Connection pool utilization as a fraction in [0, 1].
    public var connectionPoolUtilization: Double
    /// Number of prefetch cache hits.
    public var prefetchHitCount: Int
    /// Number of prefetch cache misses.
    public var prefetchMissCount: Int
    /// Total number of HTTP requests made.
    public var totalRequestCount: Int
    /// Total number of failed HTTP requests.
    public var errorCount: Int

    public init(
        http2StreamsActive: Int = 0,
        http2MaxStreams: Int = 100,
        pipelinedRequestsPerSec: Double = 0,
        averageLatencyMs: Double = 0,
        peakLatencyMs: Double = 0,
        compressionRatio: Double = 1.0,
        cacheStats: DICOMwebCacheStats = DICOMwebCacheStats(),
        connectionPoolUtilization: Double = 0,
        prefetchHitCount: Int = 0,
        prefetchMissCount: Int = 0,
        totalRequestCount: Int = 0,
        errorCount: Int = 0
    ) {
        self.http2StreamsActive = http2StreamsActive
        self.http2MaxStreams = http2MaxStreams
        self.pipelinedRequestsPerSec = pipelinedRequestsPerSec
        self.averageLatencyMs = averageLatencyMs
        self.peakLatencyMs = peakLatencyMs
        self.compressionRatio = compressionRatio
        self.cacheStats = cacheStats
        self.connectionPoolUtilization = connectionPoolUtilization
        self.prefetchHitCount = prefetchHitCount
        self.prefetchMissCount = prefetchMissCount
        self.totalRequestCount = totalRequestCount
        self.errorCount = errorCount
    }

    /// Prefetch cache hit rate as a fraction in [0, 1].
    public var prefetchHitRate: Double {
        let total = prefetchHitCount + prefetchMissCount
        guard total > 0 else { return 0 }
        return Double(prefetchHitCount) / Double(total)
    }

    /// Error rate as a fraction of total requests in [0, 1].
    public var errorRate: Double {
        guard totalRequestCount > 0 else { return 0 }
        return min(1.0, Double(errorCount) / Double(totalRequestCount))
    }
}
