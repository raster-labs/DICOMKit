import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-09-28 — the 8 module-defined tags and every key VR checked against PS3.6 2026a Table 6-1; key levels against PS3.4 2026a Tables C.6-1..C.6-5 (Patient's Age is a study-level key)

/// Query/Retrieve Level tag (0008,0052)
///
/// VR: CS, VM: 1
/// Defines the level of the Query/Retrieve hierarchy
extension Tag {
    /// Query/Retrieve Level (0008,0052)
    /// VR: CS, VM: 1
    public static let queryRetrieveLevel = Tag(group: 0x0008, element: 0x0052)
    
    /// Number of Patient Related Studies (0020,1200)
    /// VR: IS, VM: 1
    public static let numberOfPatientRelatedStudies = Tag(group: 0x0020, element: 0x1200)
    
    /// Number of Patient Related Series (0020,1202)
    /// VR: IS, VM: 1
    public static let numberOfPatientRelatedSeries = Tag(group: 0x0020, element: 0x1202)
    
    /// Number of Patient Related Instances (0020,1204)
    /// VR: IS, VM: 1
    public static let numberOfPatientRelatedInstances = Tag(group: 0x0020, element: 0x1204)
    
    /// Number of Study Related Series (0020,1206)
    /// VR: IS, VM: 1
    public static let numberOfStudyRelatedSeries = Tag(group: 0x0020, element: 0x1206)
    
    /// Number of Study Related Instances (0020,1208)
    /// VR: IS, VM: 1
    public static let numberOfStudyRelatedInstances = Tag(group: 0x0020, element: 0x1208)
    
    /// Number of Series Related Instances (0020,1209)
    /// VR: IS, VM: 1
    public static let numberOfSeriesRelatedInstances = Tag(group: 0x0020, element: 0x1209)
    
    /// Modalities in Study (0008,0061)
    /// VR: CS, VM: 1-n
    public static let modalitiesInStudy = Tag(group: 0x0008, element: 0x0061)
}

/// A key-value pair for C-FIND query matching
///
/// Represents a single matching key with optional wildcard support.
public struct QueryKey: Sendable, Hashable {
    /// The DICOM tag to match
    public let tag: Tag
    
    /// The value to match (empty string requests the attribute be returned without matching)
    public let value: String
    
    /// The Value Representation for encoding
    public let vr: VR
    
    /// Creates a query key
    ///
    /// - Parameters:
    ///   - tag: The DICOM tag
    ///   - value: The value to match (use "*" for wildcard, "" to request return)
    ///   - vr: The VR for encoding
    public init(tag: Tag, value: String, vr: VR) {
        self.tag = tag
        self.value = value
        self.vr = vr
    }
}

/// Builder for constructing C-FIND query identifier data sets
///
/// Provides a fluent API for building query keys at different levels.
///
/// Reference: PS3.4 Section C.6 - Query/Retrieve Service Class
public struct QueryKeys: Sendable, Hashable {
    
    /// The query level
    public let level: QueryLevel
    
    /// The query keys
    public private(set) var keys: [QueryKey]
    
    /// Creates a query keys builder
    ///
    /// - Parameter level: The query level
    public init(level: QueryLevel) {
        self.level = level
        self.keys = []
    }
    
    // MARK: - Generic Key Methods
    
    /// Adds a query key with a specific value to match
    ///
    /// - Parameters:
    ///   - tag: The DICOM tag
    ///   - value: The value to match
    ///   - vr: The VR for encoding
    /// - Returns: Updated query keys
    public func matching(_ tag: Tag, value: String, vr: VR) -> QueryKeys {
        var copy = self
        // A data set holds each tag once (PS3.5 7.1): a later key for the same
        // tag replaces the earlier one, so `.requestPatientID().patientID("P1")`
        // yields a single (0010,0020) element carrying "P1".
        copy.keys.removeAll { $0.tag == tag }
        copy.keys.append(QueryKey(tag: tag, value: value, vr: vr))
        return copy
    }
    
    /// Adds a query key requesting an attribute be returned (empty value)
    ///
    /// - Parameters:
    ///   - tag: The DICOM tag to return
    ///   - vr: The VR for encoding
    /// - Returns: Updated query keys
    public func returning(_ tag: Tag, vr: VR) -> QueryKeys {
        var copy = self
        // Never downgrade a matching key already set for this tag to a return key.
        guard !copy.keys.contains(where: { $0.tag == tag }) else { return copy }
        copy.keys.append(QueryKey(tag: tag, value: "", vr: vr))
        return copy
    }
    
    // MARK: - Patient Level Keys
    
    /// Matches Patient Name
    ///
    /// Supports wildcards (* and ?) per PS3.4 Section C.2.2.2
    ///
    /// - Parameter value: The patient name to match (use "*" for wildcard)
    /// - Returns: Updated query keys
    public func patientName(_ value: String) -> QueryKeys {
        matching(.patientName, value: value, vr: .PN)
    }
    
    /// Requests Patient Name be returned
    public func requestPatientName() -> QueryKeys {
        returning(.patientName, vr: .PN)
    }
    
    /// Matches Patient ID
    ///
    /// - Parameter value: The patient ID to match
    /// - Returns: Updated query keys
    public func patientID(_ value: String) -> QueryKeys {
        matching(.patientID, value: value, vr: .LO)
    }
    
    /// Requests Patient ID be returned
    public func requestPatientID() -> QueryKeys {
        returning(.patientID, vr: .LO)
    }
    
    /// Matches Patient Birth Date
    ///
    /// Supports date range queries (e.g., "19800101-19901231")
    ///
    /// - Parameter value: The date or date range to match (YYYYMMDD format)
    /// - Returns: Updated query keys
    public func patientBirthDate(_ value: String) -> QueryKeys {
        matching(.patientBirthDate, value: value, vr: .DA)
    }
    
    /// Requests Patient Birth Date be returned
    public func requestPatientBirthDate() -> QueryKeys {
        returning(.patientBirthDate, vr: .DA)
    }
    
    /// Matches Patient Sex
    ///
    /// - Parameter value: The sex to match (M, F, O)
    /// - Returns: Updated query keys
    public func patientSex(_ value: String) -> QueryKeys {
        matching(.patientSex, value: value, vr: .CS)
    }
    
    /// Requests Patient Sex be returned
    public func requestPatientSex() -> QueryKeys {
        returning(.patientSex, vr: .CS)
    }
    
    // MARK: - Study Level Keys

    /// Requests Patient's Age (0010,1010) be returned
    ///
    /// A study-level Optional Key (PS3.4 Tables C.6-2 / C.6-5); Table C.6-1
    /// (patient level) lists no Patient's Age, so it is not a patient-level key.
    public func requestPatientAge() -> QueryKeys {
        returning(.patientAge, vr: .AS)
    }
    
    /// Matches Study Instance UID
    ///
    /// - Parameter value: The study instance UID to match
    /// - Returns: Updated query keys
    public func studyInstanceUID(_ value: String) -> QueryKeys {
        matching(.studyInstanceUID, value: value, vr: .UI)
    }
    
    /// Requests Study Instance UID be returned
    public func requestStudyInstanceUID() -> QueryKeys {
        returning(.studyInstanceUID, vr: .UI)
    }
    
    /// Matches Study Date
    ///
    /// Supports date range queries (e.g., "20240101-20241231")
    ///
    /// - Parameter value: The date or date range to match (YYYYMMDD format)
    /// - Returns: Updated query keys
    public func studyDate(_ value: String) -> QueryKeys {
        matching(.studyDate, value: value, vr: .DA)
    }
    
    /// Requests Study Date be returned
    public func requestStudyDate() -> QueryKeys {
        returning(.studyDate, vr: .DA)
    }
    
    /// Matches Study Time
    ///
    /// Supports time range queries (e.g., "080000-170000")
    ///
    /// - Parameter value: The time or time range to match (HHMMSS format)
    /// - Returns: Updated query keys
    public func studyTime(_ value: String) -> QueryKeys {
        matching(.studyTime, value: value, vr: .TM)
    }
    
    /// Requests Study Time be returned
    public func requestStudyTime() -> QueryKeys {
        returning(.studyTime, vr: .TM)
    }
    
    /// Matches Accession Number
    ///
    /// - Parameter value: The accession number to match
    /// - Returns: Updated query keys
    public func accessionNumber(_ value: String) -> QueryKeys {
        matching(.accessionNumber, value: value, vr: .SH)
    }
    
    /// Requests Accession Number be returned
    public func requestAccessionNumber() -> QueryKeys {
        returning(.accessionNumber, vr: .SH)
    }
    
    /// Matches Study Description
    ///
    /// Supports wildcards (* and ?)
    ///
    /// - Parameter value: The study description to match
    /// - Returns: Updated query keys
    public func studyDescription(_ value: String) -> QueryKeys {
        matching(.studyDescription, value: value, vr: .LO)
    }
    
    /// Requests Study Description be returned
    public func requestStudyDescription() -> QueryKeys {
        returning(.studyDescription, vr: .LO)
    }
    
    /// Matches Study ID
    ///
    /// - Parameter value: The study ID to match
    /// - Returns: Updated query keys
    public func studyID(_ value: String) -> QueryKeys {
        matching(.studyID, value: value, vr: .SH)
    }
    
    /// Requests Study ID be returned
    public func requestStudyID() -> QueryKeys {
        returning(.studyID, vr: .SH)
    }
    
    /// Matches Referring Physician Name (0008,0090)
    ///
    /// - Parameter value: Physician name pattern (may include wildcards)
    /// - Returns: Updated query keys
    public func referringPhysicianName(_ value: String) -> QueryKeys {
        matching(.referringPhysicianName, value: value, vr: .PN)
    }

    /// Requests Referring Physician Name be returned
    public func requestReferringPhysicianName() -> QueryKeys {
        returning(.referringPhysicianName, vr: .PN)
    }
    
    /// Matches Modalities in Study
    ///
    /// - Parameter value: The modality codes to match (e.g., "CT\\MR")
    /// - Returns: Updated query keys
    public func modalitiesInStudy(_ value: String) -> QueryKeys {
        matching(.modalitiesInStudy, value: value, vr: .CS)
    }
    
    /// Requests Modalities in Study be returned
    public func requestModalitiesInStudy() -> QueryKeys {
        returning(.modalitiesInStudy, vr: .CS)
    }
    
    /// Requests Number of Study Related Series be returned
    public func requestNumberOfStudyRelatedSeries() -> QueryKeys {
        returning(.numberOfStudyRelatedSeries, vr: .IS)
    }
    
    /// Requests Number of Study Related Instances be returned
    public func requestNumberOfStudyRelatedInstances() -> QueryKeys {
        returning(.numberOfStudyRelatedInstances, vr: .IS)
    }
    
    // MARK: - Series Level Keys
    
    /// Matches Series Instance UID
    ///
    /// - Parameter value: The series instance UID to match
    /// - Returns: Updated query keys
    public func seriesInstanceUID(_ value: String) -> QueryKeys {
        matching(.seriesInstanceUID, value: value, vr: .UI)
    }
    
    /// Requests Series Instance UID be returned
    public func requestSeriesInstanceUID() -> QueryKeys {
        returning(.seriesInstanceUID, vr: .UI)
    }
    
    /// Matches Modality
    ///
    /// - Parameter value: The modality code to match (e.g., "CT", "MR", "US")
    /// - Returns: Updated query keys
    public func modality(_ value: String) -> QueryKeys {
        matching(.modality, value: value, vr: .CS)
    }
    
    /// Requests Modality be returned
    public func requestModality() -> QueryKeys {
        returning(.modality, vr: .CS)
    }
    
    /// Matches Series Number
    ///
    /// - Parameter value: The series number to match
    /// - Returns: Updated query keys
    public func seriesNumber(_ value: String) -> QueryKeys {
        matching(.seriesNumber, value: value, vr: .IS)
    }
    
    /// Requests Series Number be returned
    public func requestSeriesNumber() -> QueryKeys {
        returning(.seriesNumber, vr: .IS)
    }
    
    /// Matches Series Description
    ///
    /// Supports wildcards (* and ?)
    ///
    /// - Parameter value: The series description to match
    /// - Returns: Updated query keys
    public func seriesDescription(_ value: String) -> QueryKeys {
        matching(.seriesDescription, value: value, vr: .LO)
    }
    
    /// Requests Series Description be returned
    public func requestSeriesDescription() -> QueryKeys {
        returning(.seriesDescription, vr: .LO)
    }
    
    /// Matches Series Date
    ///
    /// Supports date range queries
    ///
    /// - Parameter value: The date or date range to match
    /// - Returns: Updated query keys
    public func seriesDate(_ value: String) -> QueryKeys {
        matching(.seriesDate, value: value, vr: .DA)
    }
    
    /// Requests Series Date be returned
    public func requestSeriesDate() -> QueryKeys {
        returning(.seriesDate, vr: .DA)
    }
    
    /// Matches Series Time
    ///
    /// - Parameter value: The time or time range to match
    /// - Returns: Updated query keys
    public func seriesTime(_ value: String) -> QueryKeys {
        matching(.seriesTime, value: value, vr: .TM)
    }
    
    /// Requests Series Time be returned
    public func requestSeriesTime() -> QueryKeys {
        returning(.seriesTime, vr: .TM)
    }
    
    /// Matches Body Part Examined
    ///
    /// - Parameter value: The body part code to match
    /// - Returns: Updated query keys
    public func bodyPartExamined(_ value: String) -> QueryKeys {
        matching(.bodyPartExamined, value: value, vr: .CS)
    }
    
    /// Requests Body Part Examined be returned
    public func requestBodyPartExamined() -> QueryKeys {
        returning(.bodyPartExamined, vr: .CS)
    }
    
    /// Requests Number of Series Related Instances be returned
    public func requestNumberOfSeriesRelatedInstances() -> QueryKeys {
        returning(.numberOfSeriesRelatedInstances, vr: .IS)
    }
    
    // MARK: - Instance (Image) Level Keys
    
    /// Matches SOP Instance UID
    ///
    /// - Parameter value: The SOP instance UID to match
    /// - Returns: Updated query keys
    public func sopInstanceUID(_ value: String) -> QueryKeys {
        matching(.sopInstanceUID, value: value, vr: .UI)
    }
    
    /// Requests SOP Instance UID be returned
    public func requestSOPInstanceUID() -> QueryKeys {
        returning(.sopInstanceUID, vr: .UI)
    }
    
    /// Requests SOP Class UID be returned
    public func requestSOPClassUID() -> QueryKeys {
        returning(.sopClassUID, vr: .UI)
    }
    
    /// Matches Instance Number
    ///
    /// - Parameter value: The instance number to match
    /// - Returns: Updated query keys
    public func instanceNumber(_ value: String) -> QueryKeys {
        matching(.instanceNumber, value: value, vr: .IS)
    }
    
    /// Requests Instance Number be returned
    public func requestInstanceNumber() -> QueryKeys {
        returning(.instanceNumber, vr: .IS)
    }
    
    /// Matches Content Date
    ///
    /// - Parameter value: The content date to match
    /// - Returns: Updated query keys
    public func contentDate(_ value: String) -> QueryKeys {
        matching(.contentDate, value: value, vr: .DA)
    }
    
    /// Requests Content Date be returned
    public func requestContentDate() -> QueryKeys {
        returning(.contentDate, vr: .DA)
    }
    
    /// Matches Content Time
    ///
    /// - Parameter value: The content time to match
    /// - Returns: Updated query keys
    public func contentTime(_ value: String) -> QueryKeys {
        matching(.contentTime, value: value, vr: .TM)
    }
    
    /// Requests Content Time be returned
    public func requestContentTime() -> QueryKeys {
        returning(.contentTime, vr: .TM)
    }
    
    /// Requests Rows be returned
    public func requestRows() -> QueryKeys {
        returning(.rows, vr: .US)
    }
    
    /// Requests Columns be returned
    public func requestColumns() -> QueryKeys {
        returning(.columns, vr: .US)
    }
    
    /// Requests Number of Frames be returned
    public func requestNumberOfFrames() -> QueryKeys {
        returning(.numberOfFrames, vr: .IS)
    }
    
    // MARK: - Convenience Methods
    
    /// Creates default query keys for patient-level query
    ///
    /// Returns patient name, patient ID, birth date, sex, and related counts.
    public static func defaultPatientKeys() -> QueryKeys {
        QueryKeys(level: .patient)
            .requestPatientName()
            .requestPatientID()
            .requestPatientBirthDate()
            .requestPatientSex()
            .requestNumberOfPatientRelatedStudies()
            .requestNumberOfPatientRelatedSeries()
            .requestNumberOfPatientRelatedInstances()
    }
    
    /// Requests Number of Patient Related Studies be returned
    public func requestNumberOfPatientRelatedStudies() -> QueryKeys {
        returning(.numberOfPatientRelatedStudies, vr: .IS)
    }
    
    /// Requests Number of Patient Related Series be returned
    public func requestNumberOfPatientRelatedSeries() -> QueryKeys {
        returning(.numberOfPatientRelatedSeries, vr: .IS)
    }
    
    /// Requests Number of Patient Related Instances be returned
    public func requestNumberOfPatientRelatedInstances() -> QueryKeys {
        returning(.numberOfPatientRelatedInstances, vr: .IS)
    }
    
    /// Creates default query keys for study-level query
    ///
    /// Returns study UID, date, time, description, accession number, and related counts.
    public static func defaultStudyKeys() -> QueryKeys {
        QueryKeys(level: .study)
            .requestPatientName()
            .requestPatientID()
            .requestPatientBirthDate()
            .requestStudyInstanceUID()
            .requestStudyDate()
            .requestStudyTime()
            .requestStudyDescription()
            .requestAccessionNumber()
            .requestStudyID()
            .requestReferringPhysicianName()
            .requestModalitiesInStudy()
            .requestNumberOfStudyRelatedSeries()
            .requestNumberOfStudyRelatedInstances()
    }
    
    /// Creates default query keys for series-level query
    ///
    /// Returns series UID, number, description, modality, and instance count.
    public static func defaultSeriesKeys() -> QueryKeys {
        QueryKeys(level: .series)
            .requestSeriesInstanceUID()
            .requestSeriesNumber()
            .requestSeriesDescription()
            .requestModality()
            .requestSeriesDate()
            .requestSeriesTime()
            .requestBodyPartExamined()
            .requestNumberOfSeriesRelatedInstances()
    }
    
    /// Creates default query keys for instance-level query
    ///
    /// Returns instance UID, number, SOP class, and image dimensions.
    public static func defaultInstanceKeys() -> QueryKeys {
        QueryKeys(level: .image)
            .requestSOPInstanceUID()
            .requestSOPClassUID()
            .requestInstanceNumber()
            .requestContentDate()
            .requestContentTime()
            .requestRows()
            .requestColumns()
            .requestNumberOfFrames()
    }
}
