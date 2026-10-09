/// DICOM Tag Extensions - Patient Information Module
///
/// Tags from Group 0010 (Patient Module)
/// Reference: DICOM PS3.3 - Information Object Definitions
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    // MARK: - Patient Identification
    
    /// Patient's Name (0010,0010)
    /// VR: PN, VM: 1
    public static let patientName = Tag(group: 0x0010, element: 0x0010)
    
    /// Patient ID (0010,0020)
    /// VR: LO, VM: 1
    public static let patientID = Tag(group: 0x0010, element: 0x0020)
    
    /// Issuer of Patient ID (0010,0021)
    /// VR: LO, VM: 1
    public static let issuerOfPatientID = Tag(group: 0x0010, element: 0x0021)
    
    /// Type of Patient ID (0010,0022)
    /// VR: CS, VM: 1
    public static let typeOfPatientID = Tag(group: 0x0010, element: 0x0022)
    
    /// Issuer of Patient ID Qualifiers Sequence (0010,0024)
    /// VR: SQ, VM: 1
    public static let issuerOfPatientIDQualifiersSequence = Tag(group: 0x0010, element: 0x0024)
    
    // MARK: - Patient Demographics
    
    /// Patient's Birth Date (0010,0030)
    /// VR: DA, VM: 1
    public static let patientBirthDate = Tag(group: 0x0010, element: 0x0030)
    
    /// Patient's Birth Time (0010,0032)
    /// VR: TM, VM: 1
    public static let patientBirthTime = Tag(group: 0x0010, element: 0x0032)
    
    /// Patient's Birth Date in Alternative Calendar (0010,0033)
    /// VR: LO, VM: 1
    public static let patientBirthDateInAlternativeCalendar = Tag(group: 0x0010, element: 0x0033)
    
    /// Patient's Death Date in Alternative Calendar (0010,0034)
    /// VR: LO, VM: 1
    public static let patientDeathDateInAlternativeCalendar = Tag(group: 0x0010, element: 0x0034)
    
    /// Patient's Alternative Calendar (0010,0035)
    /// VR: CS, VM: 1
    public static let patientAlternativeCalendar = Tag(group: 0x0010, element: 0x0035)
    
    /// Patient's Sex (0010,0040)
    /// VR: CS, VM: 1
    /// Enumerated Values: M (Male), F (Female), O (Other), U (Unknown)
    public static let patientSex = Tag(group: 0x0010, element: 0x0040)
    
    /// Patient's Insurance Plan Code Sequence (0010,0050)
    /// VR: SQ, VM: 1
    public static let patientInsurancePlanCodeSequence = Tag(group: 0x0010, element: 0x0050)
    
    /// Patient's Primary Language Code Sequence (0010,0101)
    /// VR: SQ, VM: 1
    public static let patientPrimaryLanguageCodeSequence = Tag(group: 0x0010, element: 0x0101)
    
    /// Patient's Primary Language Modifier Code Sequence (0010,0102)
    /// VR: SQ, VM: 1
    public static let patientPrimaryLanguageModifierCodeSequence = Tag(group: 0x0010, element: 0x0102)
    
    /// Quality Control Subject (0010,0200)
    /// VR: CS, VM: 1
    public static let qualityControlSubject = Tag(group: 0x0010, element: 0x0200)
    
    /// Quality Control Subject Type Code Sequence (0010,0201)
    /// VR: SQ, VM: 1
    public static let qualityControlSubjectTypeCodeSequence = Tag(group: 0x0010, element: 0x0201)
    
    /// Strain Description (0010,0212)
    /// VR: UC, VM: 1
    public static let strainDescription = Tag(group: 0x0010, element: 0x0212)
    
    /// Strain Nomenclature (0010,0213)
    /// VR: LO, VM: 1
    public static let strainNomenclature = Tag(group: 0x0010, element: 0x0213)
    
    /// Strain Stock Number (0010,0214)
    /// VR: LO, VM: 1
    public static let strainStockNumber = Tag(group: 0x0010, element: 0x0214)
    
    /// Strain Source Registry Code Sequence (0010,0215)
    /// VR: SQ, VM: 1
    public static let strainSourceRegistryCodeSequence = Tag(group: 0x0010, element: 0x0215)
    
    /// Strain Stock Sequence (0010,0216)
    /// VR: SQ, VM: 1
    public static let strainStockSequence = Tag(group: 0x0010, element: 0x0216)
    
    /// Strain Source (0010,0217)
    /// VR: LO, VM: 1
    public static let strainSource = Tag(group: 0x0010, element: 0x0217)
    
    /// Strain Additional Information (0010,0218)
    /// VR: UT, VM: 1
    public static let strainAdditionalInformation = Tag(group: 0x0010, element: 0x0218)
    
    /// Strain Code Sequence (0010,0219)
    /// VR: SQ, VM: 1
    public static let strainCodeSequence = Tag(group: 0x0010, element: 0x0219)
    
    // MARK: - Patient Identification & Other Attributes
    
    /// Other Patient IDs (0010,1000)
    /// VR: LO, VM: 1-n
    /// Retired - use Other Patient IDs Sequence (0010,1002) instead
    public static let otherPatientIDs = Tag(group: 0x0010, element: 0x1000)
    
    /// Other Patient Names (0010,1001)
    /// VR: PN, VM: 1-n
    public static let otherPatientNames = Tag(group: 0x0010, element: 0x1001)
    
    /// Other Patient IDs Sequence (0010,1002)
    /// VR: SQ, VM: 1
    public static let otherPatientIDsSequence = Tag(group: 0x0010, element: 0x1002)
    
    /// Patient's Age (0010,1010)
    /// VR: AS, VM: 1
    /// Age of the Patient expressed in nnnD for days, nnnW for weeks, nnnM for months, or nnnY for years
    public static let patientAge = Tag(group: 0x0010, element: 0x1010)
    
    /// Patient's Size (0010,1020)
    /// VR: DS, VM: 1
    /// Patient height in meters
    public static let patientSize = Tag(group: 0x0010, element: 0x1020)
    
    /// Patient's Weight (0010,1030)
    /// VR: DS, VM: 1
    /// Patient weight in kilograms
    public static let patientWeight = Tag(group: 0x0010, element: 0x1030)
    
    /// Referenced Patient Photo Sequence (0010,1100)
    /// VR: SQ, VM: 1
    public static let referencedPatientPhotoSequence = Tag(group: 0x0010, element: 0x1100)
    
    // MARK: - Patient Medical Information
    
    /// Ethnic Group (0010,2160)
    /// VR: SH, VM: 1
    /// Retired in PS3.6 2026a Table 6-1 (RET (2025a)). Kept for reading legacy objects.
    public static let ethnicGroup = Tag(group: 0x0010, element: 0x2160)
    
    /// Occupation (0010,2180)
    /// VR: SH, VM: 1
    public static let occupation = Tag(group: 0x0010, element: 0x2180)
    
    /// Smoking Status (0010,21A0)
    /// VR: CS, VM: 1
    public static let smokingStatus = Tag(group: 0x0010, element: 0x21A0)
    
    /// Additional Patient History (0010,21B0)
    /// VR: LT, VM: 1
    public static let additionalPatientHistory = Tag(group: 0x0010, element: 0x21B0)
    
    /// Pregnancy Status (0010,21C0)
    /// VR: US, VM: 1
    public static let pregnancyStatus = Tag(group: 0x0010, element: 0x21C0)
    
    /// Last Menstrual Date (0010,21D0)
    /// VR: DA, VM: 1
    public static let lastMenstrualDate = Tag(group: 0x0010, element: 0x21D0)
    
    /// Patient's Religious Preference (0010,21F0)
    /// VR: LO, VM: 1
    public static let patientReligiousPreference = Tag(group: 0x0010, element: 0x21F0)
    
    /// Patient Species Description (0010,2201)
    /// VR: LO, VM: 1
    public static let patientSpeciesDescription = Tag(group: 0x0010, element: 0x2201)
    
    /// Patient Species Code Sequence (0010,2202)
    /// VR: SQ, VM: 1
    public static let patientSpeciesCodeSequence = Tag(group: 0x0010, element: 0x2202)
    
    /// Patient's Sex Neutered (0010,2203)
    /// VR: CS, VM: 1
    public static let patientSexNeutered = Tag(group: 0x0010, element: 0x2203)
    
    /// Anatomical Orientation Type (0010,2210)
    /// VR: CS, VM: 1
    public static let anatomicalOrientationType = Tag(group: 0x0010, element: 0x2210)
    
    /// Patient Breed Description (0010,2292)
    /// VR: LO, VM: 1
    public static let patientBreedDescription = Tag(group: 0x0010, element: 0x2292)
    
    /// Patient Breed Code Sequence (0010,2293)
    /// VR: SQ, VM: 1
    public static let patientBreedCodeSequence = Tag(group: 0x0010, element: 0x2293)
    
    /// Breed Registration Sequence (0010,2294)
    /// VR: SQ, VM: 1
    public static let breedRegistrationSequence = Tag(group: 0x0010, element: 0x2294)
    
    /// Breed Registration Number (0010,2295)
    /// VR: LO, VM: 1
    public static let breedRegistrationNumber = Tag(group: 0x0010, element: 0x2295)
    
    /// Breed Registry Code Sequence (0010,2296)
    /// VR: SQ, VM: 1
    public static let breedRegistryCodeSequence = Tag(group: 0x0010, element: 0x2296)
    
    /// Responsible Person (0010,2297)
    /// VR: PN, VM: 1
    public static let responsiblePerson = Tag(group: 0x0010, element: 0x2297)
    
    /// Responsible Person Role (0010,2298)
    /// VR: CS, VM: 1
    public static let responsiblePersonRole = Tag(group: 0x0010, element: 0x2298)
    
    /// Responsible Organization (0010,2299)
    /// VR: LO, VM: 1
    public static let responsibleOrganization = Tag(group: 0x0010, element: 0x2299)
    
    // MARK: - Patient Comments
    
    /// Patient Comments (0010,4000)
    /// VR: LT, VM: 1
    public static let patientComments = Tag(group: 0x0010, element: 0x4000)
    
    // MARK: - Clinical Trial Patient Module
    
    /// Clinical Trial Sponsor Name (0012,0010)
    /// VR: LO, VM: 1
    public static let clinicalTrialSponsorName = Tag(group: 0x0012, element: 0x0010)
    
    /// Clinical Trial Protocol ID (0012,0020)
    /// VR: LO, VM: 1
    public static let clinicalTrialProtocolID = Tag(group: 0x0012, element: 0x0020)
    
    /// Clinical Trial Protocol Name (0012,0021)
    /// VR: LO, VM: 1
    public static let clinicalTrialProtocolName = Tag(group: 0x0012, element: 0x0021)
    
    /// Clinical Trial Site ID (0012,0030)
    /// VR: LO, VM: 1
    public static let clinicalTrialSiteID = Tag(group: 0x0012, element: 0x0030)
    
    /// Clinical Trial Site Name (0012,0031)
    /// VR: LO, VM: 1
    public static let clinicalTrialSiteName = Tag(group: 0x0012, element: 0x0031)
    
    /// Clinical Trial Subject ID (0012,0040)
    /// VR: LO, VM: 1
    public static let clinicalTrialSubjectID = Tag(group: 0x0012, element: 0x0040)
    
    /// Clinical Trial Subject Reading ID (0012,0042)
    /// VR: LO, VM: 1
    public static let clinicalTrialSubjectReadingID = Tag(group: 0x0012, element: 0x0042)
    
    /// Clinical Trial Protocol Ethics Committee Name (0012,0081)
    /// VR: LO, VM: 1
    public static let clinicalTrialProtocolEthicsCommitteeName = Tag(group: 0x0012, element: 0x0081)
    
    /// Clinical Trial Protocol Ethics Committee Approval Number (0012,0082)
    /// VR: LO, VM: 1
    public static let clinicalTrialProtocolEthicsCommitteeApprovalNumber = Tag(group: 0x0012, element: 0x0082)
}
