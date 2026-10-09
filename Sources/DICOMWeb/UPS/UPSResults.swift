import Foundation

// NEMA-verified: 2026a, checked 2026-10-01 — WorkitemResult keeps the DICOM JSON object (PS3.18 F.2, D213) and takes the requested UID when a Retrieve Workitem response has no SOP Instance UID (PS3.4 2026a Table CC.2.5-3 N-GET "Not allowed"); checked 2026-09-28 — the 19 tags diffed against PS3.6 2026a Table 6-1; the Transaction UID a server returns is read but PS3.18 11.5.2 says it is not returned
// MARK: - UPSQueryResult

/// Result from a UPS-RS workitem search query
///
/// Contains the matching workitems and pagination information.
///
/// Reference: PS3.18 Section 11 - UPS-RS
public struct UPSQueryResult: Sendable, Equatable {
    
    // MARK: - Properties
    
    /// Matching workitems
    public let workitems: [WorkitemResult]
    
    /// Total count of matching workitems (from X-Total-Count header, if available)
    public let totalCount: Int?
    
    /// Pagination information
    public let pagination: PaginationInfo
    
    // MARK: - Computed Properties
    
    /// Number of workitems in this result set
    public var count: Int {
        workitems.count
    }
    
    /// Whether there are more results available
    public var hasMore: Bool {
        pagination.hasMore
    }
    
    /// The offset for the next page of results
    public var nextOffset: Int? {
        pagination.nextOffset
    }
    
    // MARK: - Initialization
    
    /// Creates a UPS query result
    /// - Parameters:
    ///   - workitems: Array of workitem results
    ///   - totalCount: Total count of matching workitems
    ///   - pagination: Pagination information
    public init(
        workitems: [WorkitemResult],
        totalCount: Int? = nil,
        pagination: PaginationInfo = PaginationInfo()
    ) {
        self.workitems = workitems
        self.totalCount = totalCount
        self.pagination = pagination
    }
    
    /// Creates an empty result
    public static var empty: UPSQueryResult {
        UPSQueryResult(workitems: [], totalCount: 0, pagination: PaginationInfo())
    }
}

// MARK: - WorkitemResult

/// Individual workitem result from a query
///
/// Contains the key attributes returned from a UPS-RS query.
/// Not all attributes may be present depending on the query's includefield parameters.
public struct WorkitemResult: Sendable, Equatable {
    
    // MARK: - Identity
    
    /// SOP Instance UID (workitem UID) (0008,0018)
    public let workitemUID: String
    
    // MARK: - UPS State
    
    /// Procedure Step State (0074,1000)
    public let state: UPSState?
    
    /// Scheduled Procedure Step Priority (0074,1200)
    public let priority: UPSPriority?
    
    /// Procedure Step Progress (0074,1004)
    public let progressPercentage: Int?
    
    /// Procedure Step Progress Description (0074,1006)
    public let progressDescription: String?
    
    // MARK: - Scheduling
    
    /// Scheduled Procedure Step Start DateTime (0040,4005)
    public let scheduledStartDateTime: String?
    
    /// Expected Completion DateTime (0040,4011)
    public let expectedCompletionDateTime: String?
    
    /// Scheduled Procedure Step Modification DateTime (0040,4010)
    public let modificationDateTime: String?
    
    // MARK: - Identification
    
    /// Procedure Step Label (0074,1204)
    public let procedureStepLabel: String?
    
    /// Worklist Label (0074,1202)
    public let worklistLabel: String?
    
    /// Scheduled Procedure Step ID (0040,0009)
    public let scheduledProcedureStepID: String?
    
    // MARK: - Patient
    
    /// Patient Name (0010,0010)
    public let patientName: String?
    
    /// Patient ID (0010,0020)
    public let patientID: String?
    
    /// Patient Birth Date (0010,0030)
    public let patientBirthDate: String?
    
    /// Patient Sex (0010,0040)
    public let patientSex: String?
    
    // MARK: - Study Reference
    
    /// Study Instance UID (0020,000D)
    public let studyInstanceUID: String?
    
    /// Accession Number (0008,0050)
    public let accessionNumber: String?
    
    /// Referring Physician's Name (0008,0090)
    public let referringPhysicianName: String?
    
    // MARK: - Transaction
    
    /// Transaction UID (0008,1195)
    public let transactionUID: String?
    
    // MARK: - DICOM JSON
    
    /// The workitem's DICOM JSON Model object (PS3.18 2026a F.2) as the origin server sent
    /// it, serialized; nil for a result built in code. Kept so that a renderer can produce
    /// `dicom-json` from the parsed result (D213).
    public let dicomJSON: Data?
    
    /// The DICOM JSON Model object of `dicomJSON`, or nil when there is none.
    public var attributes: [String: Any]? {
        guard let dicomJSON else { return nil }
        return (try? JSONSerialization.jsonObject(with: dicomJSON)) as? [String: Any]
    }
    
    // MARK: - Initialization
    
    /// Creates a workitem result with required and optional attributes
    public init(
        workitemUID: String,
        state: UPSState? = nil,
        priority: UPSPriority? = nil,
        progressPercentage: Int? = nil,
        progressDescription: String? = nil,
        scheduledStartDateTime: String? = nil,
        expectedCompletionDateTime: String? = nil,
        modificationDateTime: String? = nil,
        procedureStepLabel: String? = nil,
        worklistLabel: String? = nil,
        scheduledProcedureStepID: String? = nil,
        patientName: String? = nil,
        patientID: String? = nil,
        patientBirthDate: String? = nil,
        patientSex: String? = nil,
        studyInstanceUID: String? = nil,
        accessionNumber: String? = nil,
        referringPhysicianName: String? = nil,
        transactionUID: String? = nil,
        dicomJSON: Data? = nil
    ) {
        self.workitemUID = workitemUID
        self.state = state
        self.priority = priority
        self.progressPercentage = progressPercentage
        self.progressDescription = progressDescription
        self.scheduledStartDateTime = scheduledStartDateTime
        self.expectedCompletionDateTime = expectedCompletionDateTime
        self.modificationDateTime = modificationDateTime
        self.procedureStepLabel = procedureStepLabel
        self.worklistLabel = worklistLabel
        self.scheduledProcedureStepID = scheduledProcedureStepID
        self.patientName = patientName
        self.patientID = patientID
        self.patientBirthDate = patientBirthDate
        self.patientSex = patientSex
        self.studyInstanceUID = studyInstanceUID
        self.accessionNumber = accessionNumber
        self.referringPhysicianName = referringPhysicianName
        self.transactionUID = transactionUID
        self.dicomJSON = dicomJSON
    }
}

// MARK: - PaginationInfo

/// Pagination information for query results
public struct PaginationInfo: Sendable, Equatable {
    
    /// Current offset
    public let offset: Int
    
    /// Limit used for the query
    public let limit: Int?
    
    /// Whether there are more results available
    public let hasMore: Bool
    
    /// Creates pagination information
    public init(offset: Int = 0, limit: Int? = nil, hasMore: Bool = false) {
        self.offset = offset
        self.limit = limit
        self.hasMore = hasMore
    }
    
    /// The offset for the next page of results
    public var nextOffset: Int? {
        guard hasMore, let limit = limit else { return nil }
        return offset + limit
    }
}

// MARK: - JSON Parsing

extension WorkitemResult {
    
    /// DICOM JSON tags used for parsing workitem results
    private enum Tag {
        static let sopInstanceUID = "00080018"
        static let procedureStepState = "00741000"
        static let procedureStepPriority = "00741200"
        static let procedureStepProgress = "00741004"
        static let procedureStepProgressDescription = "00741006"
        static let scheduledProcedureStepStartDateTime = "00404005"
        static let expectedCompletionDateTime = "00404011"
        static let scheduledProcedureStepModificationDateTime = "00404010"
        static let procedureStepLabel = "00741204"
        static let worklistLabel = "00741202"
        static let scheduledProcedureStepID = "00400009"
        static let patientName = "00100010"
        static let patientID = "00100020"
        static let patientBirthDate = "00100030"
        static let patientSex = "00100040"
        static let studyInstanceUID = "0020000D"
        static let accessionNumber = "00080050"
        static let referringPhysicianName = "00080090"
        static let transactionUID = "00081195"
    }
    
    /// Parses a workitem result from DICOM JSON
    /// - Parameter json: The DICOM JSON object
    /// - Returns: Parsed workitem result, or nil if parsing fails
    public static func parse(json: [String: Any]) -> WorkitemResult? {
        parse(json: json, requestedUID: nil)
    }

    /// `requestedUID`: the workitem UID of a Retrieve Workitem request (PS3.18 11.5). Its
    /// response follows the N-GET column of PS3.4 Table CC.2.5-3, where SOP Instance UID
    /// (0008,0018) is "Not allowed" (conveyed in the request), so the requested UID stands in.
    static func parse(json: [String: Any], requestedUID: String?) -> WorkitemResult? {
        // SOP Instance UID is required (a Search result always carries it, Return Key Type 1)
        guard let workitemUID = extractString(from: json, tag: Tag.sopInstanceUID) ?? requestedUID else {
            return nil
        }
        
        // Parse state
        let stateString = extractString(from: json, tag: Tag.procedureStepState)
        let state = stateString.flatMap { UPSState(rawValue: $0) }
        
        // Parse priority
        let priorityString = extractString(from: json, tag: Tag.procedureStepPriority)
        let priority = priorityString.flatMap { UPSPriority(rawValue: $0) }
        
        // Parse progress
        let progressPercentage = extractInt(from: json, tag: Tag.procedureStepProgress)
        let progressDescription = extractString(from: json, tag: Tag.procedureStepProgressDescription)
        
        return WorkitemResult(
            workitemUID: workitemUID,
            state: state,
            priority: priority,
            progressPercentage: progressPercentage,
            progressDescription: progressDescription,
            scheduledStartDateTime: extractString(from: json, tag: Tag.scheduledProcedureStepStartDateTime),
            expectedCompletionDateTime: extractString(from: json, tag: Tag.expectedCompletionDateTime),
            modificationDateTime: extractString(from: json, tag: Tag.scheduledProcedureStepModificationDateTime),
            procedureStepLabel: extractString(from: json, tag: Tag.procedureStepLabel),
            worklistLabel: extractString(from: json, tag: Tag.worklistLabel),
            scheduledProcedureStepID: extractString(from: json, tag: Tag.scheduledProcedureStepID),
            patientName: extractPersonName(from: json, tag: Tag.patientName),
            patientID: extractString(from: json, tag: Tag.patientID),
            patientBirthDate: extractString(from: json, tag: Tag.patientBirthDate),
            patientSex: extractString(from: json, tag: Tag.patientSex),
            studyInstanceUID: extractString(from: json, tag: Tag.studyInstanceUID),
            accessionNumber: extractString(from: json, tag: Tag.accessionNumber),
            referringPhysicianName: extractPersonName(from: json, tag: Tag.referringPhysicianName),
            transactionUID: extractString(from: json, tag: Tag.transactionUID),
            dicomJSON: try? JSONSerialization.data(withJSONObject: json)
        )
    }
    
    /// Extracts a string value from DICOM JSON
    private static func extractString(from json: [String: Any], tag: String) -> String? {
        guard let element = json[tag] as? [String: Any],
              let values = element["Value"] as? [Any],
              let first = values.first else {
            return nil
        }
        return first as? String
    }
    
    /// Extracts an integer value from DICOM JSON
    private static func extractInt(from json: [String: Any], tag: String) -> Int? {
        guard let element = json[tag] as? [String: Any],
              let values = element["Value"] as? [Any],
              let first = values.first else {
            return nil
        }
        if let intValue = first as? Int {
            return intValue
        }
        if let stringValue = first as? String {
            return Int(stringValue)
        }
        return nil
    }
    
    /// Extracts a person name value from DICOM JSON (handles PN VR format)
    private static func extractPersonName(from json: [String: Any], tag: String) -> String? {
        guard let element = json[tag] as? [String: Any],
              let values = element["Value"] as? [Any],
              let first = values.first else {
            return nil
        }
        
        // PN values can be strings or dictionaries with Alphabetic/Ideographic/Phonetic
        if let stringValue = first as? String {
            return stringValue
        }
        if let dictValue = first as? [String: Any],
           let alphabetic = dictValue["Alphabetic"] as? String {
            return alphabetic
        }
        return nil
    }
}

// MARK: - UPSQueryResult Parsing

extension UPSQueryResult {
    
    /// Parses a UPS query result from DICOM JSON array
    /// - Parameters:
    ///   - jsonArray: The DICOM JSON array
    ///   - totalCount: Total count from X-Total-Count header
    ///   - offset: Current offset
    ///   - limit: Limit used
    /// - Returns: Parsed query result
    public static func parse(
        jsonArray: [[String: Any]],
        totalCount: Int? = nil,
        offset: Int = 0,
        limit: Int? = nil
    ) -> UPSQueryResult {
        let workitems = jsonArray.compactMap { WorkitemResult.parse(json: $0) }
        
        // Determine if there are more results
        let hasMore: Bool
        if let total = totalCount, let lim = limit {
            hasMore = offset + lim < total
        } else if let lim = limit {
            hasMore = workitems.count == lim
        } else {
            hasMore = false
        }
        
        return UPSQueryResult(
            workitems: workitems,
            totalCount: totalCount,
            pagination: PaginationInfo(offset: offset, limit: limit, hasMore: hasMore)
        )
    }
}

// MARK: - CustomStringConvertible

extension WorkitemResult: CustomStringConvertible {
    public var description: String {
        var parts = ["WorkitemResult(\(workitemUID))"]
        if let state = state {
            parts.append("state=\(state.rawValue)")
        }
        if let priority = priority {
            parts.append("priority=\(priority.rawValue)")
        }
        if let label = procedureStepLabel {
            parts.append("label=\(label)")
        }
        if let patientName = patientName {
            parts.append("patient=\(patientName)")
        }
        return parts.joined(separator: ", ")
    }
}

extension UPSQueryResult: CustomStringConvertible {
    public var description: String {
        var parts = ["UPSQueryResult(count=\(count))"]
        if let total = totalCount {
            parts.append("total=\(total)")
        }
        if hasMore {
            parts.append("hasMore=true")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - UPSCreateResponse

/// Response from creating a new workitem
public struct UPSCreateResponse: Sendable, Equatable {
    /// The workitem UID that was created
    public let workitemUID: String
    
    /// The retrieve URL for the created workitem
    public let retrieveURL: String?
    
    /// Warning messages (if any)
    public let warnings: [String]
    
    public init(
        workitemUID: String,
        retrieveURL: String? = nil,
        warnings: [String] = []
    ) {
        self.workitemUID = workitemUID
        self.retrieveURL = retrieveURL
        self.warnings = warnings
    }
}

// MARK: - UPSStateChangeResponse

/// Response from a workitem state change operation
public struct UPSStateChangeResponse: Sendable, Equatable {
    /// The workitem UID that was modified
    public let workitemUID: String
    
    /// The new state
    public let newState: UPSState
    
    /// Transaction UID (returned when transitioning to IN PROGRESS)
    public let transactionUID: String?
    
    /// Warning messages (if any)
    public let warnings: [String]
    
    public init(
        workitemUID: String,
        newState: UPSState,
        transactionUID: String? = nil,
        warnings: [String] = []
    ) {
        self.workitemUID = workitemUID
        self.newState = newState
        self.transactionUID = transactionUID
        self.warnings = warnings
    }
}

// MARK: - UPSCancellationResponse

/// Response from a workitem cancellation request
public struct UPSCancellationResponse: Sendable, Equatable {
    /// The workitem UID that was requested for cancellation
    public let workitemUID: String
    
    /// Whether the cancellation was accepted
    public let accepted: Bool
    
    /// The reason the cancellation was rejected (if not accepted)
    public let rejectionReason: String?
    
    /// Warning messages (if any)
    public let warnings: [String]
    
    public init(
        workitemUID: String,
        accepted: Bool,
        rejectionReason: String? = nil,
        warnings: [String] = []
    ) {
        self.workitemUID = workitemUID
        self.accepted = accepted
        self.rejectionReason = rejectionReason
        self.warnings = warnings
    }
}

// MARK: - UPSError

/// Errors specific to UPS operations
public enum UPSError: Error, Sendable, Equatable {
    /// Workitem not found
    case workitemNotFound(uid: String)
    
    /// Invalid state transition
    case invalidStateTransition(from: UPSState, to: UPSState)
    
    /// Transaction UID required for this operation
    case transactionUIDRequired
    
    /// Transaction UID mismatch
    case transactionUIDMismatch
    
    /// Workitem already exists
    case workitemAlreadyExists(uid: String)
    
    /// Workitem is in a final state and cannot be modified
    case workitemInFinalState(state: UPSState)
    
    /// Missing required attribute
    case missingRequiredAttribute(name: String)
    
    /// Invalid workitem data
    case invalidWorkitemData(reason: String)
    
    /// Cancellation was rejected
    case cancellationRejected(reason: String)
    
    /// Server error
    case serverError(message: String)
}

extension UPSError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .workitemNotFound(let uid):
            return "Workitem not found: \(uid)"
        case .invalidStateTransition(let from, let to):
            return "Invalid state transition from \(from.rawValue) to \(to.rawValue)"
        case .transactionUIDRequired:
            return "Transaction UID required for this operation"
        case .transactionUIDMismatch:
            return "Transaction UID does not match"
        case .workitemAlreadyExists(let uid):
            return "Workitem already exists: \(uid)"
        case .workitemInFinalState(let state):
            return "Workitem is in final state: \(state.rawValue)"
        case .missingRequiredAttribute(let name):
            return "Missing required attribute: \(name)"
        case .invalidWorkitemData(let reason):
            return "Invalid workitem data: \(reason)"
        case .cancellationRejected(let reason):
            return "Cancellation rejected: \(reason)"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
