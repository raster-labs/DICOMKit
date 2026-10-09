/// DICOM Tag Extensions - File Meta Information
///
/// Tags from Group 0002 (File Meta Information)
/// Reference: DICOM PS3.10 - Media Storage and File Format
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    // MARK: - File Meta Information Header
    
    /// File Meta Information Group Length (0002,0000)
    /// VR: UL, VM: 1
    public static let fileMetaInformationGroupLength = Tag(group: 0x0002, element: 0x0000)
    
    /// File Meta Information Version (0002,0001)
    /// VR: OB, VM: 1
    public static let fileMetaInformationVersion = Tag(group: 0x0002, element: 0x0001)
    
    /// Media Storage SOP Class UID (0002,0002)
    /// VR: UI, VM: 1
    public static let mediaStorageSOPClassUID = Tag(group: 0x0002, element: 0x0002)
    
    /// Media Storage SOP Instance UID (0002,0003)
    /// VR: UI, VM: 1
    public static let mediaStorageSOPInstanceUID = Tag(group: 0x0002, element: 0x0003)
    
    /// Transfer Syntax UID (0002,0010)
    /// VR: UI, VM: 1
    public static let transferSyntaxUID = Tag(group: 0x0002, element: 0x0010)
    
    /// Implementation Class UID (0002,0012)
    /// VR: UI, VM: 1
    public static let implementationClassUID = Tag(group: 0x0002, element: 0x0012)
    
    /// Implementation Version Name (0002,0013)
    /// VR: SH, VM: 1
    public static let implementationVersionName = Tag(group: 0x0002, element: 0x0013)
    
    /// Source Application Entity Title (0002,0016)
    /// VR: AE, VM: 1
    public static let sourceApplicationEntityTitle = Tag(group: 0x0002, element: 0x0016)
    
    /// Sending Application Entity Title (0002,0017)
    /// VR: AE, VM: 1
    public static let sendingApplicationEntityTitle = Tag(group: 0x0002, element: 0x0017)
    
    /// Receiving Application Entity Title (0002,0018)
    /// VR: AE, VM: 1
    public static let receivingApplicationEntityTitle = Tag(group: 0x0002, element: 0x0018)
    
    // MARK: - Private Information
    
    /// Private Information Creator UID (0002,0100)
    /// VR: UI, VM: 1
    public static let privateInformationCreatorUID = Tag(group: 0x0002, element: 0x0100)
    
    /// Private Information (0002,0102)
    /// VR: OB, VM: 1
    public static let privateInformation = Tag(group: 0x0002, element: 0x0102)
}
