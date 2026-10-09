import Foundation
import DICOMCore
import DICOMKit

// NEMA-verified: 2026a, checked 2026-09-28 — the 3 tags (0020,0010), (0008,0016), (0018,0015) and the DA/TM range syntax read against PS3.6 2026a Table 6-1 and PS3.4 C.2.2.2.5; the delete operations are a DICOMKit extension, PS3.18 defines no Delete Transaction for studies
/// Deletion mode for DICOM instances
///
/// Defines whether instances should be permanently deleted or soft-deleted
/// (marked as deleted but retained in storage).
///
/// Not a PS3.18 transaction: the standard defines no deletion of studies, series or instances
public enum DeletionMode: String, Sendable, Codable {
    /// Permanent deletion - instance is physically removed from storage
    case permanent
    
    /// Soft deletion - instance is marked as deleted but retained in storage
    /// Allows for recovery and audit purposes
    case soft
}

/// Protocol for DICOMweb storage backend abstraction
///
/// This protocol defines the interface for storage providers that back
/// the DICOMweb server. Implementations can use file systems, databases,
/// cloud storage, or in-memory storage.
///
/// Reference: PS3.18 - Web Services
public protocol DICOMwebStorageProvider: Sendable {
    
    // MARK: - Instance Operations
    
    /// Retrieves a DICOM instance by its UIDs
    /// - Parameters:
    ///   - studyUID: Study Instance UID
    ///   - seriesUID: Series Instance UID
    ///   - instanceUID: SOP Instance UID
    /// - Returns: The DICOM instance data, or nil if not found
    func getInstance(
        studyUID: String,
        seriesUID: String,
        instanceUID: String
    ) async throws -> Data?
    
    /// Retrieves all instances in a series
    /// - Parameters:
    ///   - studyUID: Study Instance UID
    ///   - seriesUID: Series Instance UID
    /// - Returns: Array of instance data
    func getSeriesInstances(
        studyUID: String,
        seriesUID: String
    ) async throws -> [InstanceInfo]
    
    /// Retrieves all instances in a study
    /// - Parameter studyUID: Study Instance UID
    /// - Returns: Array of instance data
    func getStudyInstances(studyUID: String) async throws -> [InstanceInfo]
    
    /// Stores a DICOM instance
    /// - Parameters:
    ///   - data: The DICOM file data
    ///   - studyUID: Study Instance UID
    ///   - seriesUID: Series Instance UID
    ///   - instanceUID: SOP Instance UID
    func storeInstance(
        data: Data,
        studyUID: String,
        seriesUID: String,
        instanceUID: String
    ) async throws
    
    /// Deletes a DICOM instance
    /// - Parameters:
    ///   - studyUID: Study Instance UID
    ///   - seriesUID: Series Instance UID
    ///   - instanceUID: SOP Instance UID
    ///   - mode: Deletion mode (permanent or soft delete), defaults to permanent
    /// - Returns: True if deleted, false if not found
    func deleteInstance(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        mode: DeletionMode
    ) async throws -> Bool
    
    /// Deletes all instances in a series
    /// - Parameters:
    ///   - studyUID: Study Instance UID
    ///   - seriesUID: Series Instance UID
    ///   - mode: Deletion mode (permanent or soft delete), defaults to permanent
    /// - Returns: Number of instances deleted
    func deleteSeries(
        studyUID: String,
        seriesUID: String,
        mode: DeletionMode
    ) async throws -> Int
    
    /// Deletes all instances in a study
    /// - Parameters:
    ///   - studyUID: Study Instance UID
    ///   - mode: Deletion mode (permanent or soft delete), defaults to permanent
    /// - Returns: Number of instances deleted
    func deleteStudy(
        studyUID: String,
        mode: DeletionMode
    ) async throws -> Int
    
    // MARK: - Query Operations
    
    /// Searches for studies matching the query
    /// - Parameter query: The query parameters
    /// - Returns: Array of matching study results
    func searchStudies(query: StorageQuery) async throws -> [StudyRecord]
    
    /// Searches for series matching the query
    /// - Parameters:
    ///   - studyUID: Optional study UID to filter by
    ///   - query: The query parameters
    /// - Returns: Array of matching series results
    func searchSeries(studyUID: String?, query: StorageQuery) async throws -> [SeriesRecord]
    
    /// Searches for instances matching the query
    /// - Parameters:
    ///   - studyUID: Optional study UID to filter by
    ///   - seriesUID: Optional series UID to filter by
    ///   - query: The query parameters
    /// - Returns: Array of matching instance results
    func searchInstances(
        studyUID: String?,
        seriesUID: String?,
        query: StorageQuery
    ) async throws -> [InstanceRecord]
    
    // MARK: - Metadata Operations
    
    /// Retrieves metadata for an instance (without pixel data)
    /// - Parameters:
    ///   - studyUID: Study Instance UID
    ///   - seriesUID: Series Instance UID
    ///   - instanceUID: SOP Instance UID
    /// - Returns: DataSet without pixel data, or nil if not found
    func getInstanceMetadata(
        studyUID: String,
        seriesUID: String,
        instanceUID: String
    ) async throws -> DataSet?
    
    /// Retrieves metadata for all instances in a series
    /// - Parameters:
    ///   - studyUID: Study Instance UID
    ///   - seriesUID: Series Instance UID
    /// - Returns: Array of DataSets without pixel data
    func getSeriesMetadata(
        studyUID: String,
        seriesUID: String
    ) async throws -> [DataSet]
    
    /// Retrieves metadata for all instances in a study
    /// - Parameter studyUID: Study Instance UID
    /// - Returns: Array of DataSets without pixel data
    func getStudyMetadata(studyUID: String) async throws -> [DataSet]
    
    // MARK: - Statistics
    
    /// Gets the total count for a query (for pagination)
    /// - Parameter query: The query parameters
    /// - Returns: Total number of matching results
    func countStudies(query: StorageQuery) async throws -> Int
    
    /// Gets the count of series in a study
    /// - Parameter studyUID: Study Instance UID
    /// - Returns: Number of series
    func countSeries(studyUID: String) async throws -> Int
    
    /// Gets the count of instances in a series
    /// - Parameters:
    ///   - studyUID: Study Instance UID
    ///   - seriesUID: Series Instance UID
    /// - Returns: Number of instances
    func countInstances(studyUID: String, seriesUID: String) async throws -> Int
}

// MARK: - Supporting Types

/// Information about a stored DICOM instance
public struct InstanceInfo: Sendable {
    /// Study Instance UID
    public let studyUID: String
    
    /// Series Instance UID
    public let seriesUID: String
    
    /// SOP Instance UID
    public let instanceUID: String
    
    /// SOP Class UID
    public let sopClassUID: String?
    
    /// Transfer Syntax UID
    public let transferSyntaxUID: String?
    
    /// Size in bytes
    public let size: Int64
    
    /// The raw DICOM data
    public let data: Data
    
    public init(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        sopClassUID: String? = nil,
        transferSyntaxUID: String? = nil,
        size: Int64,
        data: Data
    ) {
        self.studyUID = studyUID
        self.seriesUID = seriesUID
        self.instanceUID = instanceUID
        self.sopClassUID = sopClassUID
        self.transferSyntaxUID = transferSyntaxUID
        self.size = size
        self.data = data
    }
}

/// Query parameters for storage searches
public struct StorageQuery: Sendable {
    /// Patient name (supports wildcards)
    public var patientName: String?
    
    /// Patient ID (supports wildcards)
    public var patientID: String?
    
    /// Study date (single date or range)
    public var studyDate: DateRange?
    
    /// Study time
    public var studyTime: DateRange?
    
    /// Accession number
    public var accessionNumber: String?
    
    /// Modality (e.g., "CT", "MR")
    public var modality: String?
    
    /// Modalities in study (for study-level queries)
    public var modalitiesInStudy: [String]?
    
    /// Study Instance UID
    public var studyInstanceUID: String?
    
    /// Series Instance UID
    public var seriesInstanceUID: String?
    
    /// SOP Instance UID
    public var sopInstanceUID: String?
    
    /// Study description
    public var studyDescription: String?
    
    /// Series description
    public var seriesDescription: String?
    
    /// Series number
    public var seriesNumber: Int?
    
    /// Instance number
    public var instanceNumber: Int?
    
    /// Referring physician name
    public var referringPhysicianName: String?

    /// Study ID (0020,0010)
    public var studyID: String?

    /// SOP Class UID (0008,0016) — instance-level match
    public var sopClassUID: String?

    /// Body Part Examined (0018,0015) — series-level match
    public var bodyPartExamined: String?
    
    /// Pagination: offset
    public var offset: Int
    
    /// Pagination: limit
    public var limit: Int
    
    /// Whether to use fuzzy matching
    public var fuzzyMatching: Bool
    
    /// Additional custom query parameters
    public var customParameters: [String: String]
    
    public init(
        patientName: String? = nil,
        patientID: String? = nil,
        studyDate: DateRange? = nil,
        studyTime: DateRange? = nil,
        accessionNumber: String? = nil,
        modality: String? = nil,
        modalitiesInStudy: [String]? = nil,
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        sopInstanceUID: String? = nil,
        studyDescription: String? = nil,
        seriesDescription: String? = nil,
        seriesNumber: Int? = nil,
        instanceNumber: Int? = nil,
        referringPhysicianName: String? = nil,
        offset: Int = 0,
        limit: Int = 100,
        fuzzyMatching: Bool = false,
        customParameters: [String: String] = [:],
        studyID: String? = nil,
        sopClassUID: String? = nil,
        bodyPartExamined: String? = nil
    ) {
        self.studyID = studyID
        self.sopClassUID = sopClassUID
        self.bodyPartExamined = bodyPartExamined
        self.patientName = patientName
        self.patientID = patientID
        self.studyDate = studyDate
        self.studyTime = studyTime
        self.accessionNumber = accessionNumber
        self.modality = modality
        self.modalitiesInStudy = modalitiesInStudy
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.sopInstanceUID = sopInstanceUID
        self.studyDescription = studyDescription
        self.seriesDescription = seriesDescription
        self.seriesNumber = seriesNumber
        self.instanceNumber = instanceNumber
        self.referringPhysicianName = referringPhysicianName
        self.offset = offset
        self.limit = limit
        self.fuzzyMatching = fuzzyMatching
        self.customParameters = customParameters
    }
    
    /// Date or date range for queries
    public struct DateRange: Sendable {
        public let start: Date?
        public let end: Date?
        
        /// Single date
        public init(date: Date) {
            self.start = date
            self.end = date
        }
        
        /// Date range
        public init(start: Date?, end: Date?) {
            self.start = start
            self.end = end
        }

        /// Parses a DICOM DA/TM matching value (PS3.4 C.2.2.2.5): `YYYYMMDD`,
        /// `YYYYMMDD-YYYYMMDD`, `YYYYMMDD-`, `-YYYYMMDD` (and the HHMMSS forms
        /// when `format` is "HHmmss"). Returns nil for anything unparsable.
        public init?(dicomValue: String, format: String = "yyyyMMdd") {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            func parse(_ s: Substring) -> Date? {
                let trimmed = s.trimmingCharacters(in: .whitespaces)
                let digits = String(trimmed.prefix(format.count))
                return digits.isEmpty ? nil : formatter.date(from: digits)
            }
            let value = dicomValue.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }
            if let dash = value.firstIndex(of: "-") {
                let lo = value[value.startIndex..<dash]
                let hi = value[value.index(after: dash)...]
                let start = lo.isEmpty ? nil : parse(lo)
                let end = hi.isEmpty ? nil : parse(hi)
                if (!lo.isEmpty && start == nil) || (!hi.isEmpty && end == nil) { return nil }
                if start == nil && end == nil { return nil }
                self.init(start: start, end: end)
            } else {
                guard let date = parse(value[...]) else { return nil }
                self.init(date: date)
            }
        }

        /// True when `dicomValue` (a stored DA/TM string) falls inside the range.
        public func contains(dicomValue: String?, format: String = "yyyyMMdd") -> Bool {
            guard let dicomValue, let point = DateRange(dicomValue: dicomValue, format: format)?.start else {
                return false
            }
            if let start, point < start { return false }
            if let end, point > end { return false }
            return true
        }
    }
}

/// Study-level record from storage
public struct StudyRecord: Sendable {
    /// Study Instance UID
    public let studyInstanceUID: String
    
    /// Patient name
    public let patientName: String?
    
    /// Patient ID
    public let patientID: String?
    
    /// Patient birth date
    public let patientBirthDate: String?
    
    /// Patient sex
    public let patientSex: String?
    
    /// Study date
    public let studyDate: String?
    
    /// Study time
    public let studyTime: String?
    
    /// Accession number
    public let accessionNumber: String?
    
    /// Referring physician name
    public let referringPhysicianName: String?
    
    /// Study description
    public let studyDescription: String?
    
    /// Study ID
    public let studyID: String?
    
    /// Modalities in study
    public let modalitiesInStudy: [String]
    
    /// Number of series
    public let numberOfStudyRelatedSeries: Int
    
    /// Number of instances
    public let numberOfStudyRelatedInstances: Int
    
    /// SOP Classes in study
    public let sopClassesInStudy: [String]
    
    public init(
        studyInstanceUID: String,
        patientName: String? = nil,
        patientID: String? = nil,
        patientBirthDate: String? = nil,
        patientSex: String? = nil,
        studyDate: String? = nil,
        studyTime: String? = nil,
        accessionNumber: String? = nil,
        referringPhysicianName: String? = nil,
        studyDescription: String? = nil,
        studyID: String? = nil,
        modalitiesInStudy: [String] = [],
        numberOfStudyRelatedSeries: Int = 0,
        numberOfStudyRelatedInstances: Int = 0,
        sopClassesInStudy: [String] = []
    ) {
        self.studyInstanceUID = studyInstanceUID
        self.patientName = patientName
        self.patientID = patientID
        self.patientBirthDate = patientBirthDate
        self.patientSex = patientSex
        self.studyDate = studyDate
        self.studyTime = studyTime
        self.accessionNumber = accessionNumber
        self.referringPhysicianName = referringPhysicianName
        self.studyDescription = studyDescription
        self.studyID = studyID
        self.modalitiesInStudy = modalitiesInStudy
        self.numberOfStudyRelatedSeries = numberOfStudyRelatedSeries
        self.numberOfStudyRelatedInstances = numberOfStudyRelatedInstances
        self.sopClassesInStudy = sopClassesInStudy
    }
}

/// Series-level record from storage
public struct SeriesRecord: Sendable {
    /// Study Instance UID
    public let studyInstanceUID: String
    
    /// Series Instance UID
    public let seriesInstanceUID: String
    
    /// Modality
    public let modality: String?
    
    /// Series number
    public let seriesNumber: Int?
    
    /// Series description
    public let seriesDescription: String?
    
    /// Body part examined
    public let bodyPartExamined: String?
    
    /// Series date
    public let seriesDate: String?
    
    /// Series time
    public let seriesTime: String?
    
    /// Performing physician name
    public let performingPhysicianName: String?
    
    /// Number of instances
    public let numberOfSeriesRelatedInstances: Int
    
    public init(
        studyInstanceUID: String,
        seriesInstanceUID: String,
        modality: String? = nil,
        seriesNumber: Int? = nil,
        seriesDescription: String? = nil,
        bodyPartExamined: String? = nil,
        seriesDate: String? = nil,
        seriesTime: String? = nil,
        performingPhysicianName: String? = nil,
        numberOfSeriesRelatedInstances: Int = 0
    ) {
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.modality = modality
        self.seriesNumber = seriesNumber
        self.seriesDescription = seriesDescription
        self.bodyPartExamined = bodyPartExamined
        self.seriesDate = seriesDate
        self.seriesTime = seriesTime
        self.performingPhysicianName = performingPhysicianName
        self.numberOfSeriesRelatedInstances = numberOfSeriesRelatedInstances
    }
}

/// Instance-level record from storage
public struct InstanceRecord: Sendable {
    /// Study Instance UID
    public let studyInstanceUID: String
    
    /// Series Instance UID
    public let seriesInstanceUID: String
    
    /// SOP Instance UID
    public let sopInstanceUID: String
    
    /// SOP Class UID
    public let sopClassUID: String?
    
    /// Instance number
    public let instanceNumber: Int?
    
    /// Number of frames
    public let numberOfFrames: Int?
    
    /// Rows
    public let rows: Int?
    
    /// Columns
    public let columns: Int?
    
    /// Bits allocated
    public let bitsAllocated: Int?
    
    /// Transfer Syntax UID
    public let transferSyntaxUID: String?
    
    public init(
        studyInstanceUID: String,
        seriesInstanceUID: String,
        sopInstanceUID: String,
        sopClassUID: String? = nil,
        instanceNumber: Int? = nil,
        numberOfFrames: Int? = nil,
        rows: Int? = nil,
        columns: Int? = nil,
        bitsAllocated: Int? = nil,
        transferSyntaxUID: String? = nil
    ) {
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.instanceNumber = instanceNumber
        self.numberOfFrames = numberOfFrames
        self.rows = rows
        self.columns = columns
        self.bitsAllocated = bitsAllocated
        self.transferSyntaxUID = transferSyntaxUID
    }
}
