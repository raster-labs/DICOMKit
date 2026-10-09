/// DICOM Tag Extensions - Overlay Information
///
/// Tags from Group 6000-60FF (Overlay Plane Module)
/// Reference: DICOM PS3.3 - Information Object Definitions
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    // MARK: - Overlay Plane Group 6000
    // Note: Overlay groups range from 6000 to 60FF (even groups only)
    // Each overlay plane has its own group. Only defining first group (6000) as examples
    
    /// Overlay Rows (6000,0010)
    /// VR: US, VM: 1
    public static let overlayRows = Tag(group: 0x6000, element: 0x0010)
    
    /// Overlay Columns (6000,0011)
    /// VR: US, VM: 1
    public static let overlayColumns = Tag(group: 0x6000, element: 0x0011)
    
    /// Overlay Planes (6000,0012)
    /// VR: US, VM: 1
    /// Retired
    public static let overlayPlanes = Tag(group: 0x6000, element: 0x0012)
    
    /// Number of Frames in Overlay (6000,0015)
    /// VR: IS, VM: 1
    public static let numberOfFramesInOverlay = Tag(group: 0x6000, element: 0x0015)
    
    /// Overlay Description (6000,0022)
    /// VR: LO, VM: 1
    public static let overlayDescription = Tag(group: 0x6000, element: 0x0022)
    
    /// Overlay Type (6000,0040)
    /// VR: CS, VM: 1
    public static let overlayType = Tag(group: 0x6000, element: 0x0040)
    
    /// Overlay Subtype (6000,0045)
    /// VR: LO, VM: 1
    public static let overlaySubtype = Tag(group: 0x6000, element: 0x0045)
    
    /// Overlay Origin (6000,0050)
    /// VR: SS, VM: 2
    public static let overlayOrigin = Tag(group: 0x6000, element: 0x0050)
    
    /// Image Frame Origin (6000,0051)
    /// VR: US, VM: 1
    public static let imageFrameOrigin = Tag(group: 0x6000, element: 0x0051)
    
    /// Overlay Plane Origin (6000,0052)
    /// VR: US, VM: 1
    /// Retired
    public static let overlayPlaneOrigin = Tag(group: 0x6000, element: 0x0052)
    
    /// Overlay Bits Allocated (6000,0100)
    /// VR: US, VM: 1
    public static let overlayBitsAllocated = Tag(group: 0x6000, element: 0x0100)
    
    /// Overlay Bit Position (6000,0102)
    /// VR: US, VM: 1
    public static let overlayBitPosition = Tag(group: 0x6000, element: 0x0102)
    
    /// Overlay Format (6000,0110)
    /// VR: CS, VM: 1
    /// Retired
    public static let overlayFormat = Tag(group: 0x6000, element: 0x0110)
    
    /// Overlay Location (6000,0200)
    /// VR: US, VM: 1
    /// Retired
    public static let overlayLocation = Tag(group: 0x6000, element: 0x0200)
    
    /// Overlay Code Label (6000,0800)
    /// VR: CS, VM: 1-n
    /// Retired
    public static let overlayCodeLabel = Tag(group: 0x6000, element: 0x0800)
    
    /// Overlay Number of Tables (6000,0802)
    /// VR: US, VM: 1
    /// Retired
    public static let overlayNumberOfTables = Tag(group: 0x6000, element: 0x0802)
    
    /// Overlay Code Table Location (6000,0803)
    /// VR: AT, VM: 1-n
    /// Retired
    public static let overlayCodeTableLocation = Tag(group: 0x6000, element: 0x0803)
    
    /// Overlay Bits For Code Word (6000,0804)
    /// VR: US, VM: 1
    /// Retired
    public static let overlayBitsForCodeWord = Tag(group: 0x6000, element: 0x0804)
    
    /// Overlay Activation Layer (6000,1001)
    /// VR: CS, VM: 1
    public static let overlayActivationLayer = Tag(group: 0x6000, element: 0x1001)
    
    /// Overlay Descriptor - Gray (6000,1100)
    /// VR: US, VM: 1
    /// Retired
    public static let overlayDescriptorGray = Tag(group: 0x6000, element: 0x1100)
    
    /// Overlay Descriptor - Red (6000,1101)
    /// VR: US, VM: 1
    /// Retired
    public static let overlayDescriptorRed = Tag(group: 0x6000, element: 0x1101)
    
    /// Overlay Descriptor - Green (6000,1102)
    /// VR: US, VM: 1
    /// Retired
    public static let overlayDescriptorGreen = Tag(group: 0x6000, element: 0x1102)
    
    /// Overlay Descriptor - Blue (6000,1103)
    /// VR: US, VM: 1
    /// Retired
    public static let overlayDescriptorBlue = Tag(group: 0x6000, element: 0x1103)
    
    /// Overlays - Gray (6000,1200)
    /// VR: US, VM: 1-n
    /// Retired
    public static let overlaysGray = Tag(group: 0x6000, element: 0x1200)
    
    /// Overlays - Red (6000,1201)
    /// VR: US, VM: 1-n
    /// Retired
    public static let overlaysRed = Tag(group: 0x6000, element: 0x1201)
    
    /// Overlays - Green (6000,1202)
    /// VR: US, VM: 1-n
    /// Retired
    public static let overlaysGreen = Tag(group: 0x6000, element: 0x1202)
    
    /// Overlays - Blue (6000,1203)
    /// VR: US, VM: 1-n
    /// Retired
    public static let overlaysBlue = Tag(group: 0x6000, element: 0x1203)
    
    /// ROI Area (6000,1301)
    /// VR: IS, VM: 1
    public static let roiArea = Tag(group: 0x6000, element: 0x1301)
    
    /// ROI Mean (6000,1302)
    /// VR: DS, VM: 1
    public static let roiMean = Tag(group: 0x6000, element: 0x1302)
    
    /// ROI Standard Deviation (6000,1303)
    /// VR: DS, VM: 1
    public static let roiStandardDeviation = Tag(group: 0x6000, element: 0x1303)
    
    /// Overlay Label (6000,1500)
    /// VR: LO, VM: 1
    public static let overlayLabel = Tag(group: 0x6000, element: 0x1500)
    
    /// Overlay Data (6000,3000)
    /// VR: OB or OW, VM: 1
    public static let overlayData = Tag(group: 0x6000, element: 0x3000)
    
    /// Overlay Comments (6000,4000)
    /// VR: LT, VM: 1
    /// Retired
    public static let overlayComments = Tag(group: 0x6000, element: 0x4000)
}
