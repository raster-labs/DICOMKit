/// DICOM Tag Extensions - Study Information Module
///
/// Tags from Groups 0008, 0020, 0032 (Study Module)
/// Reference: DICOM PS3.3 - Information Object Definitions
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    // MARK: - Study Identification
    
    /// Study Instance UID (0020,000D)
    /// VR: UI, VM: 1
    public static let studyInstanceUID = Tag(group: 0x0020, element: 0x000D)
    
    /// Study ID (0020,0010)
    /// VR: SH, VM: 1
    public static let studyID = Tag(group: 0x0020, element: 0x0010)
    
    /// Study Date (0008,0020)
    /// VR: DA, VM: 1
    public static let studyDate = Tag(group: 0x0008, element: 0x0020)
    
    /// Study Time (0008,0030)
    /// VR: TM, VM: 1
    public static let studyTime = Tag(group: 0x0008, element: 0x0030)
    
    /// Accession Number (0008,0050)
    /// VR: SH, VM: 1
    public static let accessionNumber = Tag(group: 0x0008, element: 0x0050)
    
    /// Issuer of Accession Number Sequence (0008,0051)
    /// VR: SQ, VM: 1
    public static let issuerOfAccessionNumberSequence = Tag(group: 0x0008, element: 0x0051)
    
    /// Referring Physician's Name (0008,0090)
    /// VR: PN, VM: 1
    public static let referringPhysicianName = Tag(group: 0x0008, element: 0x0090)
    
    /// Referring Physician Identification Sequence (0008,0096)
    /// VR: SQ, VM: 1
    public static let referringPhysicianIdentificationSequence = Tag(group: 0x0008, element: 0x0096)
    
    /// Consulting Physician's Name (0008,009C)
    /// VR: PN, VM: 1-n
    public static let consultingPhysicianName = Tag(group: 0x0008, element: 0x009C)
    
    /// Consulting Physician Identification Sequence (0008,009D)
    /// VR: SQ, VM: 1
    public static let consultingPhysicianIdentificationSequence = Tag(group: 0x0008, element: 0x009D)
    
    /// Study Description (0008,1030)
    /// VR: LO, VM: 1
    public static let studyDescription = Tag(group: 0x0008, element: 0x1030)
    
    /// Procedure Code Sequence (0008,1032)
    /// VR: SQ, VM: 1
    public static let procedureCodeSequence = Tag(group: 0x0008, element: 0x1032)
    
    /// Referenced Study Sequence (0008,1110)
    /// VR: SQ, VM: 1
    public static let referencedStudySequence = Tag(group: 0x0008, element: 0x1110)
    
    /// Physician(s) of Record (0008,1048)
    /// VR: PN, VM: 1-n
    public static let physiciansOfRecord = Tag(group: 0x0008, element: 0x1048)
    
    /// Physician(s) of Record Identification Sequence (0008,1049)
    /// VR: SQ, VM: 1
    public static let physiciansOfRecordIdentificationSequence = Tag(group: 0x0008, element: 0x1049)
    
    /// Name of Physician(s) Reading Study (0008,1060)
    /// VR: PN, VM: 1-n
    public static let nameOfPhysiciansReadingStudy = Tag(group: 0x0008, element: 0x1060)
    
    /// Physician(s) Reading Study Identification Sequence (0008,1062)
    /// VR: SQ, VM: 1
    public static let physiciansReadingStudyIdentificationSequence = Tag(group: 0x0008, element: 0x1062)
    
    @available(*, deprecated, renamed: "physiciansOfRecord")
    public static let physicianOfRecord = Tag.physiciansOfRecord
    @available(*, deprecated, renamed: "physiciansOfRecordIdentificationSequence")
    public static let physicianOfRecordIdentificationSequence = Tag.physiciansOfRecordIdentificationSequence
    @available(*, deprecated, renamed: "nameOfPhysiciansReadingStudy")
    public static let nameOfPhysicianReadingStudy = Tag.nameOfPhysiciansReadingStudy
    @available(*, deprecated, renamed: "physiciansReadingStudyIdentificationSequence")
    public static let physicianReadingStudyIdentificationSequence = Tag.physiciansReadingStudyIdentificationSequence
    
    /// Requesting Service Code Sequence (0032,1034)
    /// VR: SQ, VM: 1
    public static let requestingServiceCodeSequence = Tag(group: 0x0032, element: 0x1034)
    
    /// Reason for Performed Procedure Code Sequence (0040,1012)
    /// VR: SQ, VM: 1
    public static let reasonForPerformedProcedureCodeSequence = Tag(group: 0x0040, element: 0x1012)
    
    // MARK: - Study Status
    
    /// Study Status ID (0032,000A)
    /// VR: CS, VM: 1
    /// Retired
    public static let studyStatusID = Tag(group: 0x0032, element: 0x000A)
    
    /// Study Priority ID (0032,000C)
    /// VR: CS, VM: 1
    /// Retired
    public static let studyPriorityID = Tag(group: 0x0032, element: 0x000C)
    
    /// Study ID Issuer (0032,0012)
    /// VR: LO, VM: 1
    /// Retired
    public static let studyIDIssuer = Tag(group: 0x0032, element: 0x0012)
    
    /// Study Verified Date (0032,0032)
    /// VR: DA, VM: 1
    /// Retired
    public static let studyVerifiedDate = Tag(group: 0x0032, element: 0x0032)
    
    /// Study Verified Time (0032,0033)
    /// VR: TM, VM: 1
    /// Retired
    public static let studyVerifiedTime = Tag(group: 0x0032, element: 0x0033)
    
    /// Study Read Date (0032,0034)
    /// VR: DA, VM: 1
    /// Retired
    public static let studyReadDate = Tag(group: 0x0032, element: 0x0034)
    
    /// Study Read Time (0032,0035)
    /// VR: TM, VM: 1
    /// Retired
    public static let studyReadTime = Tag(group: 0x0032, element: 0x0035)
    
    /// Scheduled Study Start Date (0032,1000)
    /// VR: DA, VM: 1
    /// Retired
    public static let scheduledStudyStartDate = Tag(group: 0x0032, element: 0x1000)
    
    /// Scheduled Study Start Time (0032,1001)
    /// VR: TM, VM: 1
    /// Retired
    public static let scheduledStudyStartTime = Tag(group: 0x0032, element: 0x1001)
    
    /// Scheduled Study Stop Date (0032,1010)
    /// VR: DA, VM: 1
    /// Retired
    public static let scheduledStudyStopDate = Tag(group: 0x0032, element: 0x1010)
    
    /// Scheduled Study Stop Time (0032,1011)
    /// VR: TM, VM: 1
    /// Retired
    public static let scheduledStudyStopTime = Tag(group: 0x0032, element: 0x1011)
    
    /// Scheduled Study Location (0032,1020)
    /// VR: LO, VM: 1
    /// Retired
    public static let scheduledStudyLocation = Tag(group: 0x0032, element: 0x1020)
    
    /// Scheduled Study Location AE Title (0032,1021)
    /// VR: AE, VM: 1-n
    /// Retired
    public static let scheduledStudyLocationAETitle = Tag(group: 0x0032, element: 0x1021)
    
    /// Reason for Study (0032,1030)
    /// VR: LO, VM: 1
    /// Retired
    public static let reasonForStudy = Tag(group: 0x0032, element: 0x1030)
    
    /// Requesting Physician Identification Sequence (0032,1031)
    /// VR: SQ, VM: 1
    public static let requestingPhysicianIdentificationSequence = Tag(group: 0x0032, element: 0x1031)
    
    /// Requesting Physician (0032,1032)
    /// VR: PN, VM: 1
    public static let requestingPhysician = Tag(group: 0x0032, element: 0x1032)
    
    /// Requesting Service (0032,1033)
    /// VR: LO, VM: 1
    public static let requestingService = Tag(group: 0x0032, element: 0x1033)
    
    /// Study Arrival Date (0032,1040)
    /// VR: DA, VM: 1
    /// Retired
    public static let studyArrivalDate = Tag(group: 0x0032, element: 0x1040)
    
    /// Study Arrival Time (0032,1041)
    /// VR: TM, VM: 1
    /// Retired
    public static let studyArrivalTime = Tag(group: 0x0032, element: 0x1041)
    
    /// Study Completion Date (0032,1050)
    /// VR: DA, VM: 1
    /// Retired
    public static let studyCompletionDate = Tag(group: 0x0032, element: 0x1050)
    
    /// Study Completion Time (0032,1051)
    /// VR: TM, VM: 1
    /// Retired
    public static let studyCompletionTime = Tag(group: 0x0032, element: 0x1051)
    
    /// Study Component Status ID (0032,1055)
    /// VR: CS, VM: 1
    /// Retired
    public static let studyComponentStatusID = Tag(group: 0x0032, element: 0x1055)
    
    /// Requested Procedure Description (0032,1060)
    /// VR: LO, VM: 1
    public static let requestedProcedureDescription = Tag(group: 0x0032, element: 0x1060)
    
    /// Requested Procedure Code Sequence (0032,1064)
    /// VR: SQ, VM: 1
    public static let requestedProcedureCodeSequence = Tag(group: 0x0032, element: 0x1064)
    
    /// Requested Contrast Agent (0032,1070)
    /// VR: LO, VM: 1
    public static let requestedContrastAgent = Tag(group: 0x0032, element: 0x1070)
    
    /// Study Comments (0032,4000)
    /// VR: LT, VM: 1
    /// Retired
    public static let studyComments = Tag(group: 0x0032, element: 0x4000)
    
    // MARK: - Clinical Trial Study Module
    
    /// Clinical Trial Time Point ID (0012,0050)
    /// VR: LO, VM: 1
    public static let clinicalTrialTimePointID = Tag(group: 0x0012, element: 0x0050)
    
    /// Clinical Trial Time Point Description (0012,0051)
    /// VR: ST, VM: 1
    public static let clinicalTrialTimePointDescription = Tag(group: 0x0012, element: 0x0051)
    
    /// Longitudinal Temporal Offset from Event (0012,0052)
    /// VR: FD, VM: 1
    public static let longitudinalTemporalOffsetFromEvent = Tag(group: 0x0012, element: 0x0052)
    
    /// Longitudinal Temporal Event Type (0012,0053)
    /// VR: CS, VM: 1
    public static let longitudinalTemporalEventType = Tag(group: 0x0012, element: 0x0053)
    
    /// Clinical Trial Coordinating Center Name (0012,0060)
    /// VR: LO, VM: 1
    public static let clinicalTrialCoordinatingCenterName = Tag(group: 0x0012, element: 0x0060)
}
