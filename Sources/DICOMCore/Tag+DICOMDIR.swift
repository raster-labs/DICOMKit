/// DICOM Tag Extensions - DICOMDIR (Media Storage Directory)
///
/// Tags for DICOMDIR directory records and file-set information
/// Reference: DICOM PS3.3 F.5 - Media Storage Directory SOP Class
/// Reference: DICOM PS3.10 - Media Storage and File Format
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    // MARK: - File-set Identification and Characteristics
    
    /// File-set ID (0004,1130)
    /// VR: CS, VM: 1
    /// Identifies the file-set on the media
    public static let fileSetID = Tag(group: 0x0004, element: 0x1130)
    
    /// File-set Descriptor File ID (0004,1141)
    /// VR: CS, VM: 1-8
    /// Identifies a file containing the file-set descriptor
    public static let fileSetDescriptorFileID = Tag(group: 0x0004, element: 0x1141)
    
    /// Specific Character Set of File-set Descriptor File (0004,1142)
    /// VR: CS, VM: 1
    /// Character set of the file-set descriptor file
    public static let specificCharacterSetOfFileSetDescriptorFile = Tag(group: 0x0004, element: 0x1142)
    
    // MARK: - Directory Record Sequence
    
    /// Offset of the First Directory Record of the Root Directory Entity (0004,1200)
    /// VR: UL, VM: 1
    /// Byte offset to first root directory record
    public static let offsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity = Tag(group: 0x0004, element: 0x1200)
    
    /// Offset of the Last Directory Record of the Root Directory Entity (0004,1202)
    /// VR: UL, VM: 1
    /// Byte offset to last root directory record
    public static let offsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity = Tag(group: 0x0004, element: 0x1202)
    
    /// File-set Consistency Flag (0004,1212)
    /// VR: US, VM: 1
    /// Indicates if file-set is consistent (0x0000) or inconsistent (0xFFFF)
    public static let fileSetConsistencyFlag = Tag(group: 0x0004, element: 0x1212)
    
    /// Directory Record Sequence (0004,1220)
    /// VR: SQ, VM: 1
    /// Sequence containing all directory records
    public static let directoryRecordSequence = Tag(group: 0x0004, element: 0x1220)
    
    // MARK: - Directory Record Navigation
    
    /// Offset of the Next Directory Record (0004,1400)
    /// VR: UL, VM: 1
    /// Byte offset to next directory record at the same level
    public static let offsetOfTheNextDirectoryRecord = Tag(group: 0x0004, element: 0x1400)
    
    /// Record In-use Flag (0004,1410)
    /// VR: US, VM: 1
    /// Indicates if record is in use (0xFFFF) or inactive (0x0000)
    public static let recordInUseFlag = Tag(group: 0x0004, element: 0x1410)
    
    /// Offset of Referenced Lower-Level Directory Entity (0004,1420)
    /// VR: UL, VM: 1
    /// Byte offset to first child record
    public static let offsetOfReferencedLowerLevelDirectoryEntity = Tag(group: 0x0004, element: 0x1420)
    
    /// Directory Record Type (0004,1430)
    /// VR: CS, VM: 1
    /// Type of directory record (PATIENT, STUDY, SERIES, IMAGE, etc.)
    public static let directoryRecordType = Tag(group: 0x0004, element: 0x1430)
    
    /// Private Record UID (0004,1432)
    /// VR: UI, VM: 1
    /// UID for private record types
    public static let privateRecordUID = Tag(group: 0x0004, element: 0x1432)
    
    // MARK: - Referenced File Information
    
    /// Referenced File ID (0004,1500)
    /// VR: CS, VM: 1-8
    /// Path components to referenced DICOM file
    public static let referencedFileID = Tag(group: 0x0004, element: 0x1500)
    
    /// Referenced SOP Class UID in File (0004,1510)
    /// VR: UI, VM: 1
    /// SOP Class UID of referenced file
    public static let referencedSOPClassUIDInFile = Tag(group: 0x0004, element: 0x1510)
    
    /// Referenced SOP Instance UID in File (0004,1511)
    /// VR: UI, VM: 1
    /// SOP Instance UID of referenced file
    public static let referencedSOPInstanceUIDInFile = Tag(group: 0x0004, element: 0x1511)
    
    /// Referenced Transfer Syntax UID in File (0004,1512)
    /// VR: UI, VM: 1
    /// Transfer Syntax UID of referenced file
    public static let referencedTransferSyntaxUIDInFile = Tag(group: 0x0004, element: 0x1512)
    
    /// Referenced Related General SOP Class UID in File (0004,151A)
    /// VR: UI, VM: 1-n
    /// Related General SOP Class UIDs
    public static let referencedRelatedGeneralSOPClassUIDInFile = Tag(group: 0x0004, element: 0x151A)
    
    // MARK: - MRDR Directory Record Attributes
    
    /// Number of References (0004,1600)
    /// VR: UL, VM: 1
    /// Number of references to this record
    /// Retired in PS3.6 2026a Table 6-1 (RET (2004)). Kept for reading legacy objects.
    public static let numberOfReferences = Tag(group: 0x0004, element: 0x1600)
}
