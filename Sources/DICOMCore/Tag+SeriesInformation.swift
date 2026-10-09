/// DICOM Tag Extensions - Series Information Module
///
/// Tags from Groups 0008, 0018, 0020 (Series Module)
/// Reference: DICOM PS3.3 - Information Object Definitions
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    // MARK: - Series Identification
    
    /// Series Instance UID (0020,000E)
    /// VR: UI, VM: 1
    public static let seriesInstanceUID = Tag(group: 0x0020, element: 0x000E)
    
    /// Series Number (0020,0011)
    /// VR: IS, VM: 1
    public static let seriesNumber = Tag(group: 0x0020, element: 0x0011)
    
    /// Series Date (0008,0021)
    /// VR: DA, VM: 1
    public static let seriesDate = Tag(group: 0x0008, element: 0x0021)
    
    /// Series Time (0008,0031)
    /// VR: TM, VM: 1
    public static let seriesTime = Tag(group: 0x0008, element: 0x0031)
    
    /// Series Description (0008,103E)
    /// VR: LO, VM: 1
    public static let seriesDescription = Tag(group: 0x0008, element: 0x103E)
    
    /// Series Description Code Sequence (0008,103F)
    /// VR: SQ, VM: 1
    public static let seriesDescriptionCodeSequence = Tag(group: 0x0008, element: 0x103F)
    
    /// Modality (0008,0060)
    /// VR: CS, VM: 1
    public static let modality = Tag(group: 0x0008, element: 0x0060)
    
    /// Performing Physician's Name (0008,1050)
    /// VR: PN, VM: 1-n
    public static let performingPhysicianName = Tag(group: 0x0008, element: 0x1050)
    
    /// Performing Physician Identification Sequence (0008,1052)
    /// VR: SQ, VM: 1
    public static let performingPhysicianIdentificationSequence = Tag(group: 0x0008, element: 0x1052)
    
    /// Operators' Name (0008,1070)
    /// VR: PN, VM: 1-n
    public static let operatorsName = Tag(group: 0x0008, element: 0x1070)
    
    @available(*, deprecated, renamed: "operatorsName")
    public static let operatorName = Tag.operatorsName
    
    /// Operator Identification Sequence (0008,1072)
    /// VR: SQ, VM: 1
    public static let operatorIdentificationSequence = Tag(group: 0x0008, element: 0x1072)
    
    /// Referenced Performed Procedure Step Sequence (0008,1111)
    /// VR: SQ, VM: 1
    public static let referencedPerformedProcedureStepSequence = Tag(group: 0x0008, element: 0x1111)
    
    /// Related Series Sequence (0008,1250)
    /// VR: SQ, VM: 1
    public static let relatedSeriesSequence = Tag(group: 0x0008, element: 0x1250)
    
    /// Body Part Examined (0018,0015)
    /// VR: CS, VM: 1
    public static let bodyPartExamined = Tag(group: 0x0018, element: 0x0015)
    
    /// Protocol Name (0018,1030)
    /// VR: LO, VM: 1
    public static let protocolName = Tag(group: 0x0018, element: 0x1030)
    
    /// Patient Position (0018,5100)
    /// VR: CS, VM: 1
    public static let patientPosition = Tag(group: 0x0018, element: 0x5100)
    
    /// Laterality (0020,0060)
    /// VR: CS, VM: 1
    public static let laterality = Tag(group: 0x0020, element: 0x0060)
    
    /// Anatomic Region Sequence (0008,2218)
    /// VR: SQ, VM: 1
    public static let anatomicRegionSequence = Tag(group: 0x0008, element: 0x2218)
    
    /// Anatomic Region Modifier Sequence (0008,2220)
    /// VR: SQ, VM: 1
    public static let anatomicRegionModifierSequence = Tag(group: 0x0008, element: 0x2220)
    
    /// Primary Anatomic Structure Sequence (0008,2228)
    /// VR: SQ, VM: 1
    public static let primaryAnatomicStructureSequence = Tag(group: 0x0008, element: 0x2228)
    
    /// Primary Anatomic Structure Modifier Sequence (0008,2230)
    /// VR: SQ, VM: 1
    public static let primaryAnatomicStructureModifierSequence = Tag(group: 0x0008, element: 0x2230)
    
    // MARK: - Frame of Reference
    
    /// Frame of Reference UID (0020,0052)
    /// VR: UI, VM: 1
    public static let frameOfReferenceUID = Tag(group: 0x0020, element: 0x0052)
    
    /// Synchronization Frame of Reference UID (0020,0200)
    /// VR: UI, VM: 1
    public static let synchronizationFrameOfReferenceUID = Tag(group: 0x0020, element: 0x0200)
    
    /// Position Reference Indicator (0020,1040)
    /// VR: LO, VM: 1
    public static let positionReferenceIndicator = Tag(group: 0x0020, element: 0x1040)
    
    // MARK: - Equipment
    
    /// Manufacturer (0008,0070)
    /// VR: LO, VM: 1
    public static let manufacturer = Tag(group: 0x0008, element: 0x0070)
    
    /// Institution Name (0008,0080)
    /// VR: LO, VM: 1
    public static let institutionName = Tag(group: 0x0008, element: 0x0080)
    
    /// Institution Address (0008,0081)
    /// VR: ST, VM: 1
    public static let institutionAddress = Tag(group: 0x0008, element: 0x0081)
    
    /// Institutional Department Name (0008,1040)
    /// VR: LO, VM: 1
    public static let institutionalDepartmentName = Tag(group: 0x0008, element: 0x1040)
    
    /// Manufacturer's Model Name (0008,1090)
    /// VR: LO, VM: 1
    public static let manufacturerModelName = Tag(group: 0x0008, element: 0x1090)
    
    /// Device Serial Number (0018,1000)
    /// VR: LO, VM: 1
    public static let deviceSerialNumber = Tag(group: 0x0018, element: 0x1000)
    
    /// Software Versions (0018,1020)
    /// VR: LO, VM: 1-n
    public static let softwareVersions = Tag(group: 0x0018, element: 0x1020)
    
    /// Station Name (0008,1010)
    /// VR: SH, VM: 1
    public static let stationName = Tag(group: 0x0008, element: 0x1010)
    
    // MARK: - Clinical Trial Series Module
    
    /// Clinical Trial Series ID (0012,0071)
    /// VR: LO, VM: 1
    public static let clinicalTrialSeriesID = Tag(group: 0x0012, element: 0x0071)
    
    /// Clinical Trial Series Description (0012,0072)
    /// VR: LO, VM: 1
    public static let clinicalTrialSeriesDescription = Tag(group: 0x0012, element: 0x0072)
    
    // MARK: - Request Attributes Sequence
    
    /// Request Attributes Sequence (0040,0275)
    /// VR: SQ, VM: 1
    public static let requestAttributesSequence = Tag(group: 0x0040, element: 0x0275)
    
    /// Scheduled Procedure Step ID (0040,0009)
    /// VR: SH, VM: 1
    public static let scheduledProcedureStepID = Tag(group: 0x0040, element: 0x0009)
    
    /// Scheduled Procedure Step Description (0040,0007)
    /// VR: LO, VM: 1
    public static let scheduledProcedureStepDescription = Tag(group: 0x0040, element: 0x0007)
    
    /// Scheduled Protocol Code Sequence (0040,0008)
    /// VR: SQ, VM: 1
    public static let scheduledProtocolCodeSequence = Tag(group: 0x0040, element: 0x0008)
    
    /// Requested Procedure ID (0040,1001)
    /// VR: SH, VM: 1
    public static let requestedProcedureID = Tag(group: 0x0040, element: 0x1001)
    
    /// Requested Procedure Priority (0040,1003)
    /// VR: SH, VM: 1
    public static let requestedProcedurePriority = Tag(group: 0x0040, element: 0x1003)
}
