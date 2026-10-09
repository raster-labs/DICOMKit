import Foundation

// NEMA-verified: 2026a, checked 2026-10-01 — workitemSearch accepts the 4 Enumerated Values of Procedure Step State (0074,1000), PS3.3 2026a Table C.30.1-1 (= PS3.4 Table CC.1.1-1), as spelled there ("IN PROGRESS" with the space; D107), plus IN_PROGRESS / INPROGRESS; checked 2026-09-28 — the 23 tags of UPSQueryAttribute diffed against PS3.6 2026a Table 6-1; search parameters against PS3.18 Table 8.3.4-1; matching keys against PS3.4 Table CC.2.5-3
// MARK: - UPS Query Builder

/// Builder for constructing UPS-RS search queries
///
/// Provides a fluent API for building UPS workitem query parameters
/// according to PS3.18 Section 11 (UPS-RS).
///
/// ## Example Usage
///
/// ```swift
/// let query = UPSQuery()
///     .state(.scheduled)
///     .scheduledStartDateTimeRange(from: Date(), to: Date().addingTimeInterval(86400))
///     .patientID("12345")
///     .limit(10)
/// ```
///
/// Reference: PS3.18 Section 11 - UPS-RS
public struct UPSQuery: Sendable, Equatable {
    
    // MARK: - Properties
    
    /// Query parameters as key-value pairs
    private var parameters: [String: String] = [:]
    
    /// Fields to include in response
    private var includeFields: [String] = []
    
    // MARK: - Initialization
    
    /// Creates an empty UPS query
    public init() {}
    
    /// Creates a UPS query with existing parameters
    /// - Parameter parameters: Initial parameters dictionary
    public init(parameters: [String: String]) {
        self.parameters = parameters
    }
    
    // MARK: - UPS State Attributes
    
    /// Filter by Procedure Step State (0074,1000)
    ///
    /// - Parameter value: The UPS state to filter by
    /// - Returns: Updated query
    public func state(_ value: UPSState) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.procedureStepState, value: value.rawValue)
    }
    
    /// Filter by multiple Procedure Step States
    ///
    /// - Parameter values: The UPS states to filter by
    /// - Returns: Updated query
    public func states(_ values: [UPSState]) -> UPSQuery {
        let stateValues = values.map { $0.rawValue }.joined(separator: ",")
        return with(parameter: UPSQueryAttribute.procedureStepState, value: stateValues)
    }
    
    // MARK: - Scheduling Attributes
    
    /// Filter by Scheduled Procedure Step Start DateTime (0040,4005)
    ///
    /// - Parameter value: DateTime in DICOM format (YYYYMMDDHHMMSS)
    /// - Returns: Updated query
    public func scheduledStartDateTime(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.scheduledProcedureStepStartDateTime, value: value)
    }
    
    /// Filter by Scheduled Procedure Step Start DateTime range
    ///
    /// - Parameters:
    ///   - from: Start datetime
    ///   - to: End datetime
    /// - Returns: Updated query
    public func scheduledStartDateTimeRange(from: Date, to: Date) -> UPSQuery {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let fromStr = formatter.string(from: from)
        let toStr = formatter.string(from: to)
        return with(parameter: UPSQueryAttribute.scheduledProcedureStepStartDateTime, value: "\(fromStr)-\(toStr)")
    }
    
    /// Filter by Scheduled Procedure Step Start Date
    ///
    /// - Parameter value: Date in YYYYMMDD format
    /// - Returns: Updated query
    public func scheduledStartDate(_ value: String) -> UPSQuery {
        // Expand to full datetime range for the day
        return with(parameter: UPSQueryAttribute.scheduledProcedureStepStartDateTime, value: "\(value)000000-\(value)235959")
    }
    
    /// Filter by Scheduled Procedure Step Start Date range
    ///
    /// - Parameters:
    ///   - from: Start date in YYYYMMDD format
    ///   - to: End date in YYYYMMDD format
    /// - Returns: Updated query
    public func scheduledStartDate(from: String, to: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.scheduledProcedureStepStartDateTime, value: "\(from)000000-\(to)235959")
    }
    
    /// Filter by Expected Completion DateTime (0040,4011)
    ///
    /// - Parameter value: DateTime in DICOM format
    /// - Returns: Updated query
    public func expectedCompletionDateTime(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.expectedCompletionDateTime, value: value)
    }
    
    // MARK: - Priority
    
    /// Filter by Scheduled Procedure Step Priority (0074,1200)
    ///
    /// - Parameter value: Priority level
    /// - Returns: Updated query
    public func priority(_ value: UPSPriority) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.scheduledProcedureStepPriority, value: value.dicomValue)
    }
    
    /// Filter by multiple priorities
    ///
    /// - Parameter values: Priority levels to include
    /// - Returns: Updated query
    public func priorities(_ values: [UPSPriority]) -> UPSQuery {
        let priorityValues = values.map { $0.dicomValue }.joined(separator: ",")
        return with(parameter: UPSQueryAttribute.scheduledProcedureStepPriority, value: priorityValues)
    }
    
    // MARK: - Patient Attributes
    
    /// Filter by Patient ID (0010,0020)
    ///
    /// - Parameter value: Patient ID value or wildcard pattern
    /// - Returns: Updated query
    public func patientID(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.patientID, value: value)
    }
    
    /// Filter by Patient Name (0010,0010)
    ///
    /// - Parameter value: Patient name value or wildcard pattern
    /// - Returns: Updated query
    public func patientName(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.patientName, value: value)
    }
    
    /// Filter by Patient Birth Date (0010,0030)
    ///
    /// - Parameter value: Date in YYYYMMDD format
    /// - Returns: Updated query
    public func patientBirthDate(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.patientBirthDate, value: value)
    }
    
    /// Filter by Patient Sex (0010,0040)
    ///
    /// - Parameter value: Patient sex (M, F, or O)
    /// - Returns: Updated query
    public func patientSex(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.patientSex, value: value)
    }
    
    // MARK: - Study Reference Attributes
    
    /// Filter by Study Instance UID (0020,000D)
    ///
    /// - Parameter value: Study Instance UID
    /// - Returns: Updated query
    public func studyInstanceUID(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.studyInstanceUID, value: value)
    }
    
    /// Filter by Accession Number (0008,0050)
    ///
    /// - Parameter value: Accession number
    /// - Returns: Updated query
    public func accessionNumber(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.accessionNumber, value: value)
    }
    
    /// Filter by Referring Physician's Name (0008,0090)
    ///
    /// - Parameter value: Referring physician's name or wildcard pattern
    /// - Returns: Updated query
    public func referringPhysicianName(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.referringPhysicianName, value: value)
    }
    
    // MARK: - Workitem Attributes
    
    /// Filter by SOP Instance UID (workitem UID) (0008,0018)
    ///
    /// - Parameter value: The workitem's SOP Instance UID
    /// - Returns: Updated query
    public func workitemUID(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.sopInstanceUID, value: value)
    }
    
    /// Filter by Procedure Step Label (0074,1204)
    ///
    /// - Parameter value: Procedure step label or wildcard pattern
    /// - Returns: Updated query
    public func procedureStepLabel(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.procedureStepLabel, value: value)
    }
    
    /// Filter by Worklist Label (0074,1202)
    ///
    /// - Parameter value: Worklist label or wildcard pattern
    /// - Returns: Updated query
    public func worklistLabel(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.worklistLabel, value: value)
    }
    
    /// Filter by Scheduled Procedure Step ID (0040,0009)
    ///
    /// - Parameter value: Scheduled procedure step ID
    /// - Returns: Updated query
    public func scheduledProcedureStepID(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.scheduledProcedureStepID, value: value)
    }
    
    // MARK: - Station Attributes
    
    /// Filter by Scheduled Station Name
    ///
    /// - Parameter value: Station name or wildcard pattern
    /// - Returns: Updated query
    public func scheduledStationName(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.scheduledStationNameCodeSequence, value: value)
    }
    
    /// Filter by Scheduled Station Class
    ///
    /// - Parameter value: Station class or wildcard pattern
    /// - Returns: Updated query
    public func scheduledStationClass(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.scheduledStationClassCodeSequence, value: value)
    }
    
    /// Filter by Scheduled Station Geographic Location
    ///
    /// - Parameter value: Geographic location or wildcard pattern
    /// - Returns: Updated query
    public func scheduledStationGeographicLocation(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.scheduledStationGeographicLocation, value: value)
    }
    
    // MARK: - Performer Attributes
    
    /// Filter by Scheduled Human Performer Name
    ///
    /// - Parameter value: Performer name or wildcard pattern
    /// - Returns: Updated query
    public func scheduledPerformerName(_ value: String) -> UPSQuery {
        return with(parameter: UPSQueryAttribute.scheduledHumanPerformerName, value: value)
    }
    
    // MARK: - Generic Attribute Methods
    
    /// Filter by arbitrary DICOM tag
    ///
    /// - Parameters:
    ///   - tag: DICOM tag in GGGGEEEE format (e.g., "00100020")
    ///   - value: Attribute value
    /// - Returns: Updated query
    public func attribute(_ tag: String, value: String) -> UPSQuery {
        return with(parameter: tag, value: value)
    }
    
    /// Filter by arbitrary DICOM tag with group and element
    ///
    /// - Parameters:
    ///   - group: Tag group (e.g., 0x0010)
    ///   - element: Tag element (e.g., 0x0020)
    ///   - value: Attribute value
    /// - Returns: Updated query
    public func attribute(group: UInt16, element: UInt16, value: String) -> UPSQuery {
        let tag = String(format: "%04X%04X", group, element)
        return with(parameter: tag, value: value)
    }
    
    // MARK: - Pagination
    
    /// Limit the number of results
    ///
    /// - Parameter count: Maximum number of results to return
    /// - Returns: Updated query
    public func limit(_ count: Int) -> UPSQuery {
        return with(parameter: "limit", value: String(count))
    }
    
    /// Set the offset for pagination
    ///
    /// - Parameter offset: Number of results to skip
    /// - Returns: Updated query
    public func offset(_ offset: Int) -> UPSQuery {
        return with(parameter: "offset", value: String(offset))
    }
    
    // MARK: - Include Fields
    
    /// Request specific fields to be included in the response
    ///
    /// - Parameter tag: DICOM tag to include in GGGGEEEE format
    /// - Returns: Updated query
    public func includeField(_ tag: String) -> UPSQuery {
        var query = self
        query.includeFields.append(tag)
        return query
    }
    
    /// Request multiple specific fields to be included in the response
    ///
    /// - Parameter tags: Array of DICOM tags to include
    /// - Returns: Updated query
    public func includeFields(_ tags: [String]) -> UPSQuery {
        var query = self
        query.includeFields.append(contentsOf: tags)
        return query
    }
    
    /// Request all available fields to be included in the response
    ///
    /// - Returns: Updated query
    public func includeAllFields() -> UPSQuery {
        return with(parameter: "includefield", value: "all")
    }
    
    // MARK: - Fuzzy Matching
    
    /// Enable fuzzy matching for string searches
    ///
    /// Fuzzy matching is server-dependent and may not be supported by all servers.
    ///
    /// - Parameter enabled: Whether to enable fuzzy matching
    /// - Returns: Updated query
    public func fuzzyMatching(_ enabled: Bool = true) -> UPSQuery {
        return with(parameter: "fuzzymatching", value: enabled ? "true" : "false")
    }
    
    // MARK: - Parameter Building
    
    /// Converts the query to URL query parameters
    ///
    /// - Returns: Dictionary of query parameters
    public func toParameters() -> [String: String] {
        var params = parameters
        
        // Add include fields
        if !includeFields.isEmpty {
            let existing = params["includefield"]
            if existing == "all" {
                // Keep "all" if set
            } else if let existing = existing {
                // Combine with existing
                params["includefield"] = existing + "," + includeFields.joined(separator: ",")
            } else {
                params["includefield"] = includeFields.joined(separator: ",")
            }
        }
        
        return params
    }
    
    /// Checks if the query has any parameters
    public var isEmpty: Bool {
        return parameters.isEmpty && includeFields.isEmpty
    }
    
    /// Returns the number of query parameters
    public var parameterCount: Int {
        return parameters.count
    }
    
    // MARK: - Private Methods
    
    /// Helper to create a new query with an added parameter
    private func with(parameter key: String, value: String) -> UPSQuery {
        var query = self
        query.parameters[key] = value
        return query
    }
}

// MARK: - UPSQueryAttribute

/// Standard UPS-RS query attribute tags
///
/// Contains commonly used DICOM attribute tags in the GGGGEEEE format
/// required by UPS-RS queries.
public enum UPSQueryAttribute {
    
    // MARK: - UPS State and Progress
    
    /// Procedure Step State (0074,1000)
    public static let procedureStepState = "00741000"
    
    /// Procedure Step Progress (0074,1004)
    public static let procedureStepProgress = "00741004"
    
    /// Procedure Step Progress Description (0074,1006)
    public static let procedureStepProgressDescription = "00741006"
    
    // MARK: - Scheduling
    
    /// Scheduled Procedure Step Start DateTime (0040,4005)
    public static let scheduledProcedureStepStartDateTime = "00404005"
    
    /// Scheduled Procedure Step Modification DateTime (0040,4010)
    public static let scheduledProcedureStepModificationDateTime = "00404010"
    
    /// Expected Completion DateTime (0040,4011)
    public static let expectedCompletionDateTime = "00404011"
    
    /// Scheduled Procedure Step Priority (0074,1200)
    public static let scheduledProcedureStepPriority = "00741200"
    
    /// Scheduled Procedure Step ID (0040,0009)
    public static let scheduledProcedureStepID = "00400009"
    
    // MARK: - Identification
    
    /// SOP Instance UID (0008,0018) - Workitem UID
    public static let sopInstanceUID = "00080018"
    
    /// Procedure Step Label (0074,1204)
    public static let procedureStepLabel = "00741204"
    
    /// Worklist Label (0074,1202)
    public static let worklistLabel = "00741202"
    
    // MARK: - Patient
    
    /// Patient Name (0010,0010)
    public static let patientName = "00100010"
    
    /// Patient ID (0010,0020)
    public static let patientID = "00100020"
    
    /// Patient Birth Date (0010,0030)
    public static let patientBirthDate = "00100030"
    
    /// Patient Sex (0010,0040)
    public static let patientSex = "00100040"
    
    // MARK: - Study Reference
    
    /// Study Instance UID (0020,000D)
    public static let studyInstanceUID = "0020000D"
    
    /// Accession Number (0008,0050)
    public static let accessionNumber = "00080050"
    
    /// Referring Physician's Name (0008,0090)
    public static let referringPhysicianName = "00080090"
    
    // MARK: - Station (Coded Sequence attributes - for matching on code values)
    
    /// Scheduled Station Name Code Sequence (0040,4025) — matching is on the
    /// code sequence; there is no plain-string station name in UPS.
    public static let scheduledStationNameCodeSequence = "00404025"
    
    /// Scheduled Station Class Code Sequence (0040,4026)
    public static let scheduledStationClassCodeSequence = "00404026"
    
    @available(*, deprecated, renamed: "scheduledStationNameCodeSequence")
    public static let scheduledStationName = scheduledStationNameCodeSequence
    @available(*, deprecated, renamed: "scheduledStationClassCodeSequence")
    public static let scheduledStationClass = scheduledStationClassCodeSequence
    
    /// Scheduled Station Geographic Location
    public static let scheduledStationGeographicLocation = "00404027"
    
    // MARK: - Performer
    
    /// Scheduled Human Performer Name (matches against Human Performer's Name)
    public static let scheduledHumanPerformerName = "00404037"
    
    // MARK: - Admission
    
    /// Admission ID (0038,0010)
    public static let admissionID = "00380010"
}

// MARK: - Convenience Extensions

extension UPSQuery {
    
    /// Creates a query for finding scheduled workitems
    ///
    /// - Parameter limit: Optional result limit
    /// - Returns: Configured query
    public static func scheduled(limit: Int? = nil) -> UPSQuery {
        var query = UPSQuery().state(.scheduled)
        if let limit = limit {
            query = query.limit(limit)
        }
        return query
    }
    
    /// Creates a query for finding in-progress workitems
    ///
    /// - Parameter limit: Optional result limit
    /// - Returns: Configured query
    public static func inProgress(limit: Int? = nil) -> UPSQuery {
        var query = UPSQuery().state(.inProgress)
        if let limit = limit {
            query = query.limit(limit)
        }
        return query
    }
    
    /// Creates a query for finding workitems by patient
    ///
    /// - Parameters:
    ///   - patientID: Patient identifier
    ///   - state: Optional state filter
    ///   - limit: Optional result limit
    /// - Returns: Configured query
    public static func forPatient(_ patientID: String, state: UPSState? = nil, limit: Int? = nil) -> UPSQuery {
        var query = UPSQuery().patientID(patientID)
        if let state = state {
            query = query.state(state)
        }
        if let limit = limit {
            query = query.limit(limit)
        }
        return query
    }
    
    /// Creates a query for finding workitems scheduled for today
    ///
    /// - Parameter limit: Optional result limit
    /// - Returns: Configured query
    public static func scheduledToday(limit: Int? = nil) -> UPSQuery {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let today = formatter.string(from: Date())
        
        var query = UPSQuery()
            .state(.scheduled)
            .scheduledStartDate(today)
        if let limit = limit {
            query = query.limit(limit)
        }
        return query
    }
    
    /// Creates a query for finding high-priority workitems
    ///
    /// - Parameter limit: Optional result limit
    /// - Returns: Configured query
    public static func highPriority(limit: Int? = nil) -> UPSQuery {
        var query = UPSQuery()
            .state(.scheduled)
            .priorities([.high])
        if let limit = limit {
            query = query.limit(limit)
        }
        return query
    }
    
    /// Creates an empty query (returns all workitems, subject to server limits)
    ///
    /// - Parameter limit: Optional result limit
    /// - Returns: Empty query with optional limit
    public static func all(limit: Int? = nil) -> UPSQuery {
        var query = UPSQuery()
        if let limit = limit {
            query = query.limit(limit)
        }
        return query
    }
}

// MARK: - Worklist Search Builder (shared input mapping)

/// Error thrown by `UPSQuery.workitemSearch` for an unrecognised procedure-step state.
public enum UPSSearchFilterError: Error, CustomStringConvertible, Sendable, Equatable {
    case invalidState(String)

    public var description: String {
        switch self {
        case .invalidState(let value):
            return "Invalid state: \(value). Valid states: SCHEDULED, IN PROGRESS (or IN_PROGRESS), COMPLETED, CANCELED (PS3.3 2026a Table C.30.1-1)"
        }
    }
}

extension UPSQuery {

    /// Builds a `dicom-wado ups --search` worklist query from the tool's two search-filter
    /// flags. This is the SINGLE source of truth for UPS-RS search input: the CLI, the CLI
    /// Workshop's in-app search, and the CLI-parity reference all build their query here, so
    /// the three cannot drift. It maps ONLY the two real CLI search flags
    /// (`--filter-state` / `--scheduled-station`) and adds no extra filters, no `limit`, and
    /// no `includefield` — the CLI sets none, so neither does the app.
    ///
    /// - Parameters:
    ///   - filterState: `--filter-state` value (empty/nil means no state filter). The
    ///     Procedure Step State (0074,1000) Enumerated Values of PS3.3 2026a Table C.30.1-1 are accepted
    ///     case-insensitively as spelled there (SCHEDULED, "IN PROGRESS", COMPLETED,
    ///     CANCELED), and IN_PROGRESS / INPROGRESS as aliases. A non-empty
    ///     unrecognised value throws `UPSSearchFilterError.invalidState`, mirroring the CLI,
    ///     which rejects an invalid `--filter-state` (non-zero exit) rather than silently
    ///     issuing an unfiltered query.
    ///   - scheduledStation: `--scheduled-station` value (empty/nil means no station filter).
    /// - Returns: The configured query.
    public static func workitemSearch(filterState: String?, scheduledStation: String?) throws -> UPSQuery {
        var query = UPSQuery()
        if let filterState = filterState, !filterState.isEmpty {
            let term = filterState.trimmingCharacters(in: .whitespaces).uppercased()
                .replacingOccurrences(of: "_", with: " ")
            switch term {
            case "SCHEDULED":                 query = query.state(.scheduled)
            case "IN PROGRESS", "INPROGRESS": query = query.state(.inProgress)
            case "COMPLETED":                 query = query.state(.completed)
            case "CANCELED":                  query = query.state(.canceled)
            default:                          throw UPSSearchFilterError.invalidState(filterState)
            }
        }
        if let scheduledStation = scheduledStation, !scheduledStation.isEmpty {
            query = query.scheduledStationName(scheduledStation)
        }
        return query
    }
}
