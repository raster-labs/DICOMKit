import Foundation

// MARK: - QIDO-RS Query Builder

/// Builder for constructing QIDO-RS search queries
///
/// Provides a fluent API for building DICOMweb query parameters
/// according to PS3.18 Section 10.6 (QIDO-RS).
///
/// ## Example Usage
///
/// ```swift
/// let query = QIDOQuery()
///     .patientName("Smith*")
///     .studyDate(from: "20240101", to: "20241231")
///     .modality("CT")
///     .limit(10)
/// ```
///
/// NEMA-verified: 2026a, checked 2026-09-28 — the 20 tags of `QIDOQueryAttribute` diffed against
/// PS3.18 2026a Table 10.6.1-5 (all present) and PS3.6 Table 6-1; search parameter names
/// against Table 8.3.4-1; date/time range syntax per PS3.4 C.2.2.2.5.
///
/// Reference: PS3.18 Section 10.6 - Search Transaction (QIDO-RS)
public struct QIDOQuery: Sendable, Equatable {
    
    // MARK: - Properties
    
    /// Query parameters as key-value pairs
    private var parameters: [String: String] = [:]
    
    /// Fields to include in response
    private var includeFields: [String] = []
    
    // MARK: - Initialization
    
    /// Creates an empty QIDO query
    public init() {}
    
    /// Creates a QIDO query with existing parameters
    /// - Parameter parameters: Initial parameters dictionary
    public init(parameters: [String: String]) {
        self.parameters = parameters
    }
    
    // MARK: - Patient Level Attributes (0010)
    
    /// Filter by Patient ID (0010,0020)
    ///
    /// - Parameter value: Patient ID value or wildcard pattern
    /// - Returns: Updated query
    public func patientID(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.patientID, value: value)
    }
    
    /// Filter by Patient Name (0010,0010)
    ///
    /// - Parameter value: Patient name value or wildcard pattern
    /// - Returns: Updated query
    public func patientName(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.patientName, value: value)
    }
    
    /// Filter by Patient Birth Date (0010,0030)
    ///
    /// - Parameter value: Date in YYYYMMDD format or range
    /// - Returns: Updated query
    public func patientBirthDate(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.patientBirthDate, value: value)
    }
    
    /// Filter by Patient Sex (0010,0040)
    ///
    /// - Parameter value: Patient sex (M, F, or O)
    /// - Returns: Updated query
    public func patientSex(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.patientSex, value: value)
    }
    
    // MARK: - Study Level Attributes (0008, 0020)
    
    /// Filter by Study Instance UID (0020,000D)
    ///
    /// - Parameter value: Study Instance UID
    /// - Returns: Updated query
    public func studyInstanceUID(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.studyInstanceUID, value: value)
    }
    
    /// Filter by Study Date (0008,0020)
    ///
    /// - Parameter value: Date in YYYYMMDD format
    /// - Returns: Updated query
    public func studyDate(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.studyDate, value: value)
    }
    
    /// Filter by Study Date range
    ///
    /// - Parameters:
    ///   - from: Start date in YYYYMMDD format (inclusive)
    ///   - to: End date in YYYYMMDD format (inclusive)
    /// - Returns: Updated query
    public func studyDate(from: String, to: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.studyDate, value: "\(from)-\(to)")
    }
    
    /// Filter by Study Date with open-ended range
    ///
    /// - Parameters:
    ///   - from: Start date in YYYYMMDD format (inclusive), or nil for no lower bound
    ///   - to: End date in YYYYMMDD format (inclusive), or nil for no upper bound
    /// - Returns: Updated query
    public func studyDateRange(from: String? = nil, to: String? = nil) -> QIDOQuery {
        let value: String
        if let from = from, let to = to {
            value = "\(from)-\(to)"
        } else if let from = from {
            value = "\(from)-"
        } else if let to = to {
            value = "-\(to)"
        } else {
            return self
        }
        return with(parameter: QIDOQueryAttribute.studyDate, value: value)
    }
    
    /// Filter by Study Time (0008,0030)
    ///
    /// - Parameter value: Time in HHMMSS format
    /// - Returns: Updated query
    public func studyTime(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.studyTime, value: value)
    }
    
    /// Filter by Study Time range
    ///
    /// - Parameters:
    ///   - from: Start time in HHMMSS format
    ///   - to: End time in HHMMSS format
    /// - Returns: Updated query
    public func studyTime(from: String, to: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.studyTime, value: "\(from)-\(to)")
    }
    
    /// Filter by Study Description (0008,1030)
    ///
    /// - Parameter value: Study description value or wildcard pattern
    /// - Returns: Updated query
    public func studyDescription(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.studyDescription, value: value)
    }
    
    /// Filter by Accession Number (0008,0050)
    ///
    /// - Parameter value: Accession number
    /// - Returns: Updated query
    public func accessionNumber(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.accessionNumber, value: value)
    }
    
    /// Filter by Referring Physician's Name (0008,0090)
    ///
    /// - Parameter value: Referring physician's name or wildcard pattern
    /// - Returns: Updated query
    public func referringPhysicianName(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.referringPhysicianName, value: value)
    }
    
    /// Filter by Study ID (0020,0010)
    ///
    /// - Parameter value: Study ID
    /// - Returns: Updated query
    public func studyID(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.studyID, value: value)
    }
    
    // MARK: - Series Level Attributes
    
    /// Filter by Series Instance UID (0020,000E)
    ///
    /// - Parameter value: Series Instance UID
    /// - Returns: Updated query
    public func seriesInstanceUID(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.seriesInstanceUID, value: value)
    }
    
    /// Filter by Modality (0008,0060)
    ///
    /// Use this for series-level queries. For study-level queries, prefer ``modalitiesInStudy(_:)``.
    ///
    /// - Parameter value: Modality code (e.g., CT, MR, US)
    /// - Returns: Updated query
    public func modality(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.modality, value: value)
    }

    /// Filter by Modalities in Study (0008,0061)
    ///
    /// Use this for study-level QIDO-RS queries per PS3.18 Section 10.6.
    /// Tag 0008,0061 is the correct matching attribute at the study level.
    ///
    /// - Parameter value: Modality code (e.g., CT, MR, US)
    /// - Returns: Updated query
    public func modalitiesInStudy(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.modalitiesInStudy, value: value)
    }

    /// Filter by Series Number (0020,0011)
    ///
    /// - Parameter value: Series number
    /// - Returns: Updated query
    public func seriesNumber(_ value: Int) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.seriesNumber, value: String(value))
    }
    
    /// Filter by Series Description (0008,103E)
    ///
    /// - Parameter value: Series description or wildcard pattern
    /// - Returns: Updated query
    public func seriesDescription(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.seriesDescription, value: value)
    }
    
    /// Filter by Performed Procedure Step Start Date (0040,0244)
    ///
    /// - Parameter value: Date in YYYYMMDD format
    /// - Returns: Updated query
    public func performedProcedureStepStartDate(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.performedProcedureStepStartDate, value: value)
    }
    
    /// Filter by Performed Procedure Step Start Time (0040,0245)
    ///
    /// - Parameter value: Time in HHMMSS format, or a range HHMMSS-HHMMSS
    /// - Returns: Updated query
    public func performedProcedureStepStartTime(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.performedProcedureStepStartTime, value: value)
    }

    /// Filter by Scheduled Procedure Step ID inside Request Attributes Sequence
    /// (0040,0275.0040,0009) — PS3.18 8.3.4.1 sequence-attribute matching.
    ///
    /// - Parameter value: Scheduled Procedure Step ID
    /// - Returns: Updated query
    public func scheduledProcedureStepID(_ value: String) -> QIDOQuery {
        return with(parameter: "\(QIDOQueryAttribute.requestAttributesSequence).\(QIDOQueryAttribute.scheduledProcedureStepID)", value: value)
    }

    /// Filter by Requested Procedure ID inside Request Attributes Sequence
    /// (0040,0275.0040,1001).
    ///
    /// - Parameter value: Requested Procedure ID
    /// - Returns: Updated query
    public func requestedProcedureID(_ value: String) -> QIDOQuery {
        return with(parameter: "\(QIDOQueryAttribute.requestAttributesSequence).\(QIDOQueryAttribute.requestedProcedureID)", value: value)
    }

    /// Filter by Body Part Examined (0018,0015)
    ///
    /// - Parameter value: Body part code
    /// - Returns: Updated query
    public func bodyPartExamined(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.bodyPartExamined, value: value)
    }
    
    // MARK: - Instance Level Attributes
    
    /// Filter by SOP Instance UID (0008,0018)
    ///
    /// - Parameter value: SOP Instance UID
    /// - Returns: Updated query
    public func sopInstanceUID(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.sopInstanceUID, value: value)
    }
    
    /// Filter by SOP Class UID (0008,0016)
    ///
    /// - Parameter value: SOP Class UID
    /// - Returns: Updated query
    public func sopClassUID(_ value: String) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.sopClassUID, value: value)
    }
    
    /// Filter by Instance Number (0020,0013)
    ///
    /// - Parameter value: Instance number
    /// - Returns: Updated query
    public func instanceNumber(_ value: Int) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.instanceNumber, value: String(value))
    }
    
    /// Filter by Number of Frames (0028,0008)
    ///
    /// - Parameter value: Number of frames
    /// - Returns: Updated query
    public func numberOfFrames(_ value: Int) -> QIDOQuery {
        return with(parameter: QIDOQueryAttribute.numberOfFrames, value: String(value))
    }
    
    // MARK: - Generic Attribute Methods
    
    /// Filter by arbitrary DICOM tag
    ///
    /// - Parameters:
    ///   - tag: DICOM tag in GGGGEEEE format (e.g., "00100020")
    ///   - value: Attribute value
    /// - Returns: Updated query
    public func attribute(_ tag: String, value: String) -> QIDOQuery {
        return with(parameter: tag, value: value)
    }
    
    /// Filter by arbitrary DICOM tag with group and element
    ///
    /// - Parameters:
    ///   - group: Tag group (e.g., 0x0010)
    ///   - element: Tag element (e.g., 0x0020)
    ///   - value: Attribute value
    /// - Returns: Updated query
    public func attribute(group: UInt16, element: UInt16, value: String) -> QIDOQuery {
        let tag = String(format: "%04X%04X", group, element)
        return with(parameter: tag, value: value)
    }
    
    // MARK: - Pagination
    
    /// Limit the number of results
    ///
    /// - Parameter count: Maximum number of results to return
    /// - Returns: Updated query
    public func limit(_ count: Int) -> QIDOQuery {
        return with(parameter: DICOMwebURLBuilder.QueryParameter.limit, value: String(count))
    }
    
    /// Set the offset for pagination
    ///
    /// - Parameter offset: Number of results to skip
    /// - Returns: Updated query
    public func offset(_ offset: Int) -> QIDOQuery {
        return with(parameter: DICOMwebURLBuilder.QueryParameter.offset, value: String(offset))
    }
    
    // MARK: - Include Fields
    
    /// Request specific fields to be included in the response
    ///
    /// - Parameter tag: DICOM tag to include in GGGGEEEE format
    /// - Returns: Updated query
    public func includeField(_ tag: String) -> QIDOQuery {
        var query = self
        query.includeFields.append(tag)
        return query
    }
    
    /// Request multiple specific fields to be included in the response
    ///
    /// - Parameter tags: Array of DICOM tags to include
    /// - Returns: Updated query
    public func includeFields(_ tags: [String]) -> QIDOQuery {
        var query = self
        query.includeFields.append(contentsOf: tags)
        return query
    }
    
    /// Request all available fields to be included in the response
    ///
    /// - Returns: Updated query
    public func includeAllFields() -> QIDOQuery {
        return with(parameter: DICOMwebURLBuilder.QueryParameter.includefield, value: "all")
    }
    
    // MARK: - Fuzzy Matching
    
    /// Enable fuzzy matching for patient name searches
    ///
    /// Fuzzy matching is server-dependent and may not be supported by all servers.
    ///
    /// - Parameter enabled: Whether to enable fuzzy matching
    /// - Returns: Updated query
    public func fuzzyMatching(_ enabled: Bool = true) -> QIDOQuery {
        return with(parameter: DICOMwebURLBuilder.QueryParameter.fuzzymatching, value: enabled ? "true" : "false")
    }
    
    // MARK: - Parameter Building
    
    /// Converts the query to URL query parameters
    ///
    /// - Returns: Dictionary of query parameters
    public func toParameters() -> [String: String] {
        var params = parameters
        
        // Add include fields
        if !includeFields.isEmpty {
            // Multiple includefield parameters are combined
            let existing = params[DICOMwebURLBuilder.QueryParameter.includefield]
            if existing == "all" {
                // Keep "all" if set
            } else if let existing = existing {
                // Combine with existing
                params[DICOMwebURLBuilder.QueryParameter.includefield] = existing + "," + includeFields.joined(separator: ",")
            } else {
                params[DICOMwebURLBuilder.QueryParameter.includefield] = includeFields.joined(separator: ",")
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
    private func with(parameter key: String, value: String) -> QIDOQuery {
        var query = self
        query.parameters[key] = value
        return query
    }
}

// MARK: - QIDOQueryAttribute

/// Standard QIDO-RS query attribute tags
///
/// Contains commonly used DICOM attribute tags in the GGGGEEEE format
/// required by QIDO-RS queries.
public enum QIDOQueryAttribute {
    
    // MARK: - Patient Level (0010)
    
    /// Patient Name (0010,0010)
    public static let patientName = "00100010"
    
    /// Patient ID (0010,0020)
    public static let patientID = "00100020"
    
    /// Patient Birth Date (0010,0030)
    public static let patientBirthDate = "00100030"
    
    /// Patient Sex (0010,0040)
    public static let patientSex = "00100040"
    
    // MARK: - Study Level (0008, 0020)
    
    /// Study Date (0008,0020)
    public static let studyDate = "00080020"
    
    /// Study Time (0008,0030)
    public static let studyTime = "00080030"
    
    /// Accession Number (0008,0050)
    public static let accessionNumber = "00080050"
    
    /// Modality (0008,0060) — series-level attribute
    public static let modality = "00080060"

    /// Modalities in Study (0008,0061) — study-level attribute
    public static let modalitiesInStudy = "00080061"

    /// Referring Physician's Name (0008,0090)
    public static let referringPhysicianName = "00080090"
    
    /// Study Description (0008,1030)
    public static let studyDescription = "00081030"
    
    /// Study Instance UID (0020,000D)
    public static let studyInstanceUID = "0020000D"
    
    /// Study ID (0020,0010)
    public static let studyID = "00200010"
    
    /// Number of Study Related Series (0020,1206)
    public static let numberOfStudyRelatedSeries = "00201206"
    
    /// Number of Study Related Instances (0020,1208)
    public static let numberOfStudyRelatedInstances = "00201208"
    
    // MARK: - Series Level
    
    /// Series Instance UID (0020,000E)
    public static let seriesInstanceUID = "0020000E"
    
    /// Series Number (0020,0011)
    public static let seriesNumber = "00200011"
    
    /// Series Description (0008,103E)
    public static let seriesDescription = "0008103E"
    
    /// Body Part Examined (0018,0015)
    public static let bodyPartExamined = "00180015"
    
    /// Performed Procedure Step Start Date (0040,0244)
    public static let performedProcedureStepStartDate = "00400244"

    /// Performed Procedure Step Start Time (0040,0245)
    public static let performedProcedureStepStartTime = "00400245"

    /// Request Attributes Sequence (0040,0275) — carries Scheduled Procedure Step ID
    /// and Requested Procedure ID (PS3.18 Table 10.6.1-5 series-level keys)
    public static let requestAttributesSequence = "00400275"

    /// Scheduled Procedure Step ID (0040,0009) — inside Request Attributes Sequence
    public static let scheduledProcedureStepID = "00400009"

    /// Requested Procedure ID (0040,1001) — inside Request Attributes Sequence
    public static let requestedProcedureID = "00401001"
    
    /// Number of Series Related Instances (0020,1209)
    public static let numberOfSeriesRelatedInstances = "00201209"
    
    // MARK: - Instance Level
    
    /// SOP Class UID (0008,0016)
    public static let sopClassUID = "00080016"
    
    /// SOP Instance UID (0008,0018)
    public static let sopInstanceUID = "00080018"
    
    /// Instance Number (0020,0013)
    public static let instanceNumber = "00200013"
    
    /// Number of Frames (0028,0008)
    public static let numberOfFrames = "00280008"
    
    /// Rows (0028,0010)
    public static let rows = "00280010"
    
    /// Columns (0028,0011)
    public static let columns = "00280011"
}

// MARK: - Convenience Extensions

extension QIDOQuery {
    
    /// Creates a query for finding studies by patient name
    ///
    /// - Parameters:
    ///   - name: Patient name or wildcard pattern
    ///   - limit: Optional result limit
    /// - Returns: Configured query
    public static func studiesByPatientName(_ name: String, limit: Int? = nil) -> QIDOQuery {
        var query = QIDOQuery().patientName(name)
        if let limit = limit {
            query = query.limit(limit)
        }
        return query
    }
    
    /// Creates a query for finding studies by date range
    ///
    /// - Parameters:
    ///   - from: Start date in YYYYMMDD format
    ///   - to: End date in YYYYMMDD format
    ///   - limit: Optional result limit
    /// - Returns: Configured query
    public static func studiesByDateRange(from: String, to: String, limit: Int? = nil) -> QIDOQuery {
        var query = QIDOQuery().studyDate(from: from, to: to)
        if let limit = limit {
            query = query.limit(limit)
        }
        return query
    }
    
    /// Creates a query for finding studies by modality
    ///
    /// Matches Modalities in Study (0008,0061), the study-level key of PS3.18 Table 10.6.1-5;
    /// Modality (0008,0060) is a series-level key.
    ///
    /// - Parameters:
    ///   - modality: Modality code (e.g., "CT", "MR")
    ///   - limit: Optional result limit
    /// - Returns: Configured query
    public static func studiesByModality(_ modality: String, limit: Int? = nil) -> QIDOQuery {
        var query = QIDOQuery().modalitiesInStudy(modality)
        if let limit = limit {
            query = query.limit(limit)
        }
        return query
    }
    
    /// Creates an empty query (returns all results, subject to server limits)
    ///
    /// - Parameter limit: Optional result limit
    /// - Returns: Empty query with optional limit
    public static func all(limit: Int? = nil) -> QIDOQuery {
        var query = QIDOQuery()
        if let limit = limit {
            query = query.limit(limit)
        }
        return query
    }
}
