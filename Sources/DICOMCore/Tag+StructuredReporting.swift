/// DICOM Tag Extensions - Structured Reporting
///
/// Tags specific to DICOM Structured Reporting (SR) documents
/// Reference: DICOM PS3.3 - Structured Reporting
/// NEMA-verified: 2026a, checked 2026-09-30 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status); re-run 2026-09-30 after adding Verifying Observer Identification Code Sequence (0040,A088): 75 constants, all match Table 6-1 (keyword, VR, VM, not retired). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    // MARK: - SR Document General Module
    
    /// Preliminary Flag (0040,A496)
    /// VR: CS, VM: 1
    public static let preliminaryFlag = Tag(group: 0x0040, element: 0xA496)
    
    /// Completion Flag (0040,A491)
    /// VR: CS, VM: 1
    public static let completionFlag = Tag(group: 0x0040, element: 0xA491)
    
    /// Completion Flag Description (0040,A492)
    /// VR: LO, VM: 1
    public static let completionFlagDescription = Tag(group: 0x0040, element: 0xA492)
    
    /// Verification Flag (0040,A493)
    /// VR: CS, VM: 1
    public static let verificationFlag = Tag(group: 0x0040, element: 0xA493)
    
    /// Archive Requested (0040,A494)
    /// VR: CS, VM: 1
    public static let archiveRequested = Tag(group: 0x0040, element: 0xA494)
    
    /// Verifying Observer Sequence (0040,A073)
    /// VR: SQ, VM: 1
    public static let verifyingObserverSequence = Tag(group: 0x0040, element: 0xA073)
    
    /// Verifying Observer Name (0040,A075)
    /// VR: PN, VM: 1
    public static let verifyingObserverName = Tag(group: 0x0040, element: 0xA075)

    /// Verifying Observer Identification Code Sequence (0040,A088)
    /// VR: SQ, VM: 1
    /// PS3.6 2026a Table 6-1 (keyword VerifyingObserverIdentificationCodeSequence)
    public static let verifyingObserverIdentificationCodeSequence = Tag(group: 0x0040, element: 0xA088)

    /// Verifying Organization (0040,A027)
    /// VR: LO, VM: 1
    public static let verifyingOrganization = Tag(group: 0x0040, element: 0xA027)
    
    /// Verification DateTime (0040,A030)
    /// VR: DT, VM: 1
    public static let verificationDateTime = Tag(group: 0x0040, element: 0xA030)
    
    /// Author Observer Sequence (0040,A078)
    /// VR: SQ, VM: 1
    public static let authorObserverSequence = Tag(group: 0x0040, element: 0xA078)
    
    /// Participant Sequence (0040,A07A)
    /// VR: SQ, VM: 1
    public static let participantSequence = Tag(group: 0x0040, element: 0xA07A)
    
    /// Custodial Organization Sequence (0040,A07C)
    /// VR: SQ, VM: 1
    public static let custodialOrganizationSequence = Tag(group: 0x0040, element: 0xA07C)
    
    // MARK: - SR Document Content Module
    
    /// Value Type (0040,A040)
    /// VR: CS, VM: 1
    public static let valueType = Tag(group: 0x0040, element: 0xA040)
    
    /// Concept Name Code Sequence (0040,A043)
    /// VR: SQ, VM: 1
    public static let conceptNameCodeSequence = Tag(group: 0x0040, element: 0xA043)
    
    /// Measurement Units Code Sequence (0040,08EA)
    /// VR: SQ, VM: 1
    public static let measurementUnitsCodeSequence = Tag(group: 0x0040, element: 0x08EA)
    
    /// DateTime (0040,A120)
    /// VR: DT, VM: 1
    public static let dateTime = Tag(group: 0x0040, element: 0xA120)
    
    /// Date (0040,A121)
    /// VR: DA, VM: 1
    public static let date = Tag(group: 0x0040, element: 0xA121)
    
    /// Time (0040,A122)
    /// VR: TM, VM: 1
    public static let time = Tag(group: 0x0040, element: 0xA122)
    
    /// Person Name (0040,A123)
    /// VR: PN, VM: 1
    public static let personName = Tag(group: 0x0040, element: 0xA123)
    
    /// UID (0040,A124)
    /// VR: UI, VM: 1
    public static let uid = Tag(group: 0x0040, element: 0xA124)
    
    /// Text Value (0040,A160)
    /// VR: UT, VM: 1
    public static let textValue = Tag(group: 0x0040, element: 0xA160)
    
    /// Concept Code Sequence (0040,A168)
    /// VR: SQ, VM: 1
    public static let conceptCodeSequence = Tag(group: 0x0040, element: 0xA168)

    /// Numeric Value Qualifier Code Sequence (0040,A301)
    /// VR: SQ, VM: 1
    public static let numericValueQualifierCodeSequence = Tag(group: 0x0040, element: 0xA301)
    
    /// Numeric Value (0040,A30A)
    /// VR: DS, VM: 1-n
    public static let numericValue = Tag(group: 0x0040, element: 0xA30A)
    
    /// Floating Point Value (0040,A161)
    /// VR: FD, VM: 1-n
    public static let floatingPointValue = Tag(group: 0x0040, element: 0xA161)
    
    /// Rational Numerator Value (0040,A162)
    /// VR: SL, VM: 1-n
    public static let rationalNumeratorValue = Tag(group: 0x0040, element: 0xA162)
    
    /// Rational Denominator Value (0040,A163)
    /// VR: UL, VM: 1-n
    public static let rationalDenominatorValue = Tag(group: 0x0040, element: 0xA163)
    
    /// Continuity Of Content (0040,A050)
    /// VR: CS, VM: 1
    public static let continuityOfContent = Tag(group: 0x0040, element: 0xA050)
    
    /// Content Sequence (0040,A730)
    /// VR: SQ, VM: 1
    public static let contentSequence = Tag(group: 0x0040, element: 0xA730)
    
    /// Content Template Sequence (0040,A504)
    /// VR: SQ, VM: 1
    public static let contentTemplateSequence = Tag(group: 0x0040, element: 0xA504)
    
    /// Template Identifier (0040,DB00)
    /// VR: CS, VM: 1
    public static let templateIdentifier = Tag(group: 0x0040, element: 0xDB00)
    
    /// Mapping Resource (0008,0105)
    /// VR: CS, VM: 1
    public static let mappingResource = Tag(group: 0x0008, element: 0x0105)
    
    /// Context Group Version (0008,0106)
    /// VR: DT, VM: 1
    public static let contextGroupVersion = Tag(group: 0x0008, element: 0x0106)
    
    /// Context Group Local Version (0008,0107)
    /// VR: DT, VM: 1
    public static let contextGroupLocalVersion = Tag(group: 0x0008, element: 0x0107)
    
    /// Context Group Extension Flag (0008,010B)
    /// VR: CS, VM: 1
    public static let contextGroupExtensionFlag = Tag(group: 0x0008, element: 0x010B)
    
    /// Context Group Extension Creator UID (0008,010D)
    /// VR: UI, VM: 1
    public static let contextGroupExtensionCreatorUID = Tag(group: 0x0008, element: 0x010D)
    
    /// Context Identifier (0008,010F)
    /// VR: CS, VM: 1
    public static let contextIdentifier = Tag(group: 0x0008, element: 0x010F)
    
    /// Coding Scheme Designator (0008,0102)
    /// VR: SH, VM: 1
    public static let codingSchemeDesignator = Tag(group: 0x0008, element: 0x0102)
    
    /// Coding Scheme Version (0008,0103)
    /// VR: SH, VM: 1
    public static let codingSchemeVersion = Tag(group: 0x0008, element: 0x0103)
    
    /// Code Value (0008,0100)
    /// VR: SH, VM: 1
    public static let codeValue = Tag(group: 0x0008, element: 0x0100)
    
    /// Code Meaning (0008,0104)
    /// VR: LO, VM: 1
    public static let codeMeaning = Tag(group: 0x0008, element: 0x0104)
    
    /// Equivalent Code Sequence (0008,0121)
    /// VR: SQ, VM: 1
    public static let equivalentCodeSequence = Tag(group: 0x0008, element: 0x0121)
    
    /// Context UID (0008,0117)
    /// VR: UI, VM: 1
    public static let contextUID = Tag(group: 0x0008, element: 0x0117)
    
    /// Mapping Resource UID (0008,0118)
    /// VR: UI, VM: 1
    public static let mappingResourceUID = Tag(group: 0x0008, element: 0x0118)
    
    /// Mapping Resource Name (0008,0122)
    /// VR: LO, VM: 1
    public static let mappingResourceName = Tag(group: 0x0008, element: 0x0122)
    
    /// Long Code Value (0008,0119)
    /// VR: UC, VM: 1
    public static let longCodeValue = Tag(group: 0x0008, element: 0x0119)
    
    /// URN Code Value (0008,0120)
    /// VR: UR, VM: 1
    public static let urnCodeValue = Tag(group: 0x0008, element: 0x0120)
    
    // MARK: - SR Document Relationship
    
    /// Referenced SOP Sequence (0008,1199)
    /// VR: SQ, VM: 1
    public static let referencedSOPSequence = Tag(group: 0x0008, element: 0x1199)
    
    /// Referenced SOP Class UID (0008,1150)
    /// VR: UI, VM: 1
    public static let referencedSOPClassUID = Tag(group: 0x0008, element: 0x1150)
    
    /// Referenced SOP Instance UID (0008,1155)
    /// VR: UI, VM: 1
    public static let referencedSOPInstanceUID = Tag(group: 0x0008, element: 0x1155)
    
    /// Referenced Frame Number (0008,1160)
    /// VR: IS, VM: 1-n
    public static let referencedFrameNumber = Tag(group: 0x0008, element: 0x1160)
    
    /// Referenced Segment Number (0062,000B)
    /// VR: US, VM: 1-n
    public static let referencedSegmentNumber = Tag(group: 0x0062, element: 0x000B)
    
    /// Purpose of Reference Code Sequence (0040,A170)
    /// VR: SQ, VM: 1
    public static let purposeOfReferenceCodeSequence = Tag(group: 0x0040, element: 0xA170)
    
    /// Observation DateTime (0040,A032)
    /// VR: DT, VM: 1
    public static let observationDateTime = Tag(group: 0x0040, element: 0xA032)
    
    /// Observation Start DateTime (0040,A033)
    /// VR: DT, VM: 1
    public static let observationStartDateTime = Tag(group: 0x0040, element: 0xA033)
    
    /// Referenced Content Item Identifier (0040,DB73)
    /// VR: UL, VM: 1-n
    public static let referencedContentItemIdentifier = Tag(group: 0x0040, element: 0xDB73)

    // MARK: - Table Content Item Macro (PS3.3 C.18.10, added 2026-09-25 for P8)

    /// Tabulated Values Sequence (0040,A801)
    /// VR: SQ, VM: 1
    public static let tabulatedValuesSequence = Tag(group: 0x0040, element: 0xA801)

    /// Number of Table Rows (0040,A802)
    /// VR: UL, VM: 1
    public static let numberOfTableRows = Tag(group: 0x0040, element: 0xA802)

    /// Number of Table Columns (0040,A803)
    /// VR: UL, VM: 1
    public static let numberOfTableColumns = Tag(group: 0x0040, element: 0xA803)

    /// Table Row Number (0040,A804)
    /// VR: UL, VM: 1
    public static let tableRowNumber = Tag(group: 0x0040, element: 0xA804)

    /// Table Column Number (0040,A805)
    /// VR: UL, VM: 1
    public static let tableColumnNumber = Tag(group: 0x0040, element: 0xA805)

    /// Table Row Definition Sequence (0040,A806)
    /// VR: SQ, VM: 1
    public static let tableRowDefinitionSequence = Tag(group: 0x0040, element: 0xA806)

    /// Table Column Definition Sequence (0040,A807)
    /// VR: SQ, VM: 1
    public static let tableColumnDefinitionSequence = Tag(group: 0x0040, element: 0xA807)

    /// Cell Values Sequence (0040,A808)
    /// VR: SQ, VM: 1
    public static let cellValuesSequence = Tag(group: 0x0040, element: 0xA808)
    
    /// Relationship Type (0040,A010)
    /// VR: CS, VM: 1
    public static let relationshipType = Tag(group: 0x0040, element: 0xA010)
    
    // MARK: - Modality Worklist and Performed Procedure Step
    
    /// Performed Procedure Step ID (0040,0253)
    /// VR: SH, VM: 1
    public static let performedProcedureStepID = Tag(group: 0x0040, element: 0x0253)
    
    /// Performed Procedure Step Start Date (0040,0244)
    /// VR: DA, VM: 1
    public static let performedProcedureStepStartDate = Tag(group: 0x0040, element: 0x0244)
    
    /// Performed Procedure Step Start Time (0040,0245)
    /// VR: TM, VM: 1
    public static let performedProcedureStepStartTime = Tag(group: 0x0040, element: 0x0245)
    
    /// Performed Procedure Step End Date (0040,0250)
    /// VR: DA, VM: 1
    public static let performedProcedureStepEndDate = Tag(group: 0x0040, element: 0x0250)
    
    /// Performed Procedure Step End Time (0040,0251)
    /// VR: TM, VM: 1
    public static let performedProcedureStepEndTime = Tag(group: 0x0040, element: 0x0251)
    
    /// Performed Procedure Step Status (0040,0252)
    /// VR: CS, VM: 1
    public static let performedProcedureStepStatus = Tag(group: 0x0040, element: 0x0252)
    
    /// Performed Procedure Step Description (0040,0254)
    /// VR: LO, VM: 1
    public static let performedProcedureStepDescription = Tag(group: 0x0040, element: 0x0254)
    
    /// Performed Procedure Type Description (0040,0255)
    /// VR: LO, VM: 1
    public static let performedProcedureTypeDescription = Tag(group: 0x0040, element: 0x0255)
    
    /// Performed Protocol Code Sequence (0040,0260)
    /// VR: SQ, VM: 1
    public static let performedProtocolCodeSequence = Tag(group: 0x0040, element: 0x0260)
}
