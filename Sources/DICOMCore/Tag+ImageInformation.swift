/// DICOM Tag Extensions - Image Information Module
///
/// Tags from Groups 0008, 0018, 0020, 0028 (Image and related modules)
/// Reference: DICOM PS3.3 - Information Object Definitions
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    // MARK: - Instance Identification
    
    /// Instance Number (0020,0013)
    /// VR: IS, VM: 1
    public static let instanceNumber = Tag(group: 0x0020, element: 0x0013)
    
    /// SOP Instance UID (0008,0018)
    /// VR: UI, VM: 1
    public static let sopInstanceUID = Tag(group: 0x0008, element: 0x0018)
    
    /// SOP Class UID (0008,0016)
    /// VR: UI, VM: 1
    public static let sopClassUID = Tag(group: 0x0008, element: 0x0016)
    
    /// Specific Character Set (0008,0005)
    /// VR: CS, VM: 1-n
    public static let specificCharacterSet = Tag(group: 0x0008, element: 0x0005)
    
    /// Instance Creation Date (0008,0012)
    /// VR: DA, VM: 1
    public static let instanceCreationDate = Tag(group: 0x0008, element: 0x0012)
    
    /// Instance Creation Time (0008,0013)
    /// VR: TM, VM: 1
    public static let instanceCreationTime = Tag(group: 0x0008, element: 0x0013)
    
    /// Instance Creator UID (0008,0014)
    /// VR: UI, VM: 1
    public static let instanceCreatorUID = Tag(group: 0x0008, element: 0x0014)
    
    /// Related General SOP Class UID (0008,001A)
    /// VR: UI, VM: 1-n
    public static let relatedGeneralSOPClassUID = Tag(group: 0x0008, element: 0x001A)
    
    /// Original Specialized SOP Class UID (0008,001B)
    /// VR: UI, VM: 1
    public static let originalSpecializedSOPClassUID = Tag(group: 0x0008, element: 0x001B)
    
    /// Timezone Offset From UTC (0008,0201)
    /// VR: SH, VM: 1
    public static let timezoneOffsetFromUTC = Tag(group: 0x0008, element: 0x0201)
    
    // MARK: - Image Type and Characteristics
    
    /// Image Type (0008,0008)
    /// VR: CS, VM: 2-n
    public static let imageType = Tag(group: 0x0008, element: 0x0008)
    
    /// Acquisition Date (0008,0022)
    /// VR: DA, VM: 1
    public static let acquisitionDate = Tag(group: 0x0008, element: 0x0022)
    
    /// Content Date (0008,0023)
    /// VR: DA, VM: 1
    public static let contentDate = Tag(group: 0x0008, element: 0x0023)
    
    /// Acquisition Time (0008,0032)
    /// VR: TM, VM: 1
    public static let acquisitionTime = Tag(group: 0x0008, element: 0x0032)
    
    /// Content Time (0008,0033)
    /// VR: TM, VM: 1
    public static let contentTime = Tag(group: 0x0008, element: 0x0033)
    
    /// Acquisition DateTime (0008,002A)
    /// VR: DT, VM: 1
    public static let acquisitionDateTime = Tag(group: 0x0008, element: 0x002A)
    
    /// Image Comments (0020,4000)
    /// VR: LT, VM: 1
    public static let imageComments = Tag(group: 0x0020, element: 0x4000)
    
    /// Quality Control Image (0028,0300)
    /// VR: CS, VM: 1
    public static let qualityControlImage = Tag(group: 0x0028, element: 0x0300)
    
    /// Burned In Annotation (0028,0301)
    /// VR: CS, VM: 1
    public static let burnedInAnnotation = Tag(group: 0x0028, element: 0x0301)
    
    /// Recognizable Visual Features (0028,0302)
    /// VR: CS, VM: 1
    public static let recognizableVisualFeatures = Tag(group: 0x0028, element: 0x0302)
    
    /// Lossy Image Compression (0028,2110)
    /// VR: CS, VM: 1
    public static let lossyImageCompression = Tag(group: 0x0028, element: 0x2110)
    
    /// Lossy Image Compression Ratio (0028,2112)
    /// VR: DS, VM: 1-n
    public static let lossyImageCompressionRatio = Tag(group: 0x0028, element: 0x2112)
    
    /// Lossy Image Compression Method (0028,2114)
    /// VR: CS, VM: 1-n
    public static let lossyImageCompressionMethod = Tag(group: 0x0028, element: 0x2114)
    
    /// Icon Image Sequence (0088,0200)
    /// VR: SQ, VM: 1
    public static let iconImageSequence = Tag(group: 0x0088, element: 0x0200)
    
    // MARK: - Image Pixel Description
    
    /// Samples per Pixel (0028,0002)
    /// VR: US, VM: 1
    public static let samplesPerPixel = Tag(group: 0x0028, element: 0x0002)
    
    /// Photometric Interpretation (0028,0004)
    /// VR: CS, VM: 1
    public static let photometricInterpretation = Tag(group: 0x0028, element: 0x0004)
    
    /// Rows (0028,0010)
    /// VR: US, VM: 1
    public static let rows = Tag(group: 0x0028, element: 0x0010)
    
    /// Columns (0028,0011)
    /// VR: US, VM: 1
    public static let columns = Tag(group: 0x0028, element: 0x0011)
    
    /// Bits Allocated (0028,0100)
    /// VR: US, VM: 1
    public static let bitsAllocated = Tag(group: 0x0028, element: 0x0100)
    
    /// Bits Stored (0028,0101)
    /// VR: US, VM: 1
    public static let bitsStored = Tag(group: 0x0028, element: 0x0101)
    
    /// High Bit (0028,0102)
    /// VR: US, VM: 1
    public static let highBit = Tag(group: 0x0028, element: 0x0102)
    
    /// Pixel Representation (0028,0103)
    /// VR: US, VM: 1
    public static let pixelRepresentation = Tag(group: 0x0028, element: 0x0103)
    
    /// Planar Configuration (0028,0006)
    /// VR: US, VM: 1
    public static let planarConfiguration = Tag(group: 0x0028, element: 0x0006)
    
    /// Pixel Aspect Ratio (0028,0034)
    /// VR: IS, VM: 2
    public static let pixelAspectRatio = Tag(group: 0x0028, element: 0x0034)
    
    /// Smallest Image Pixel Value (0028,0106)
    /// VR: US or SS, VM: 1
    public static let smallestImagePixelValue = Tag(group: 0x0028, element: 0x0106)
    
    /// Largest Image Pixel Value (0028,0107)
    /// VR: US or SS, VM: 1
    public static let largestImagePixelValue = Tag(group: 0x0028, element: 0x0107)
    
    /// Smallest Pixel Value in Series (0028,0108)
    /// VR: US or SS, VM: 1
    public static let smallestPixelValueInSeries = Tag(group: 0x0028, element: 0x0108)
    
    /// Largest Pixel Value in Series (0028,0109)
    /// VR: US or SS, VM: 1
    public static let largestPixelValueInSeries = Tag(group: 0x0028, element: 0x0109)
    
    /// Pixel Padding Value (0028,0120)
    /// VR: US or SS, VM: 1
    public static let pixelPaddingValue = Tag(group: 0x0028, element: 0x0120)
    
    /// Pixel Padding Range Limit (0028,0121)
    /// VR: US or SS, VM: 1
    public static let pixelPaddingRangeLimit = Tag(group: 0x0028, element: 0x0121)
    
    /// Float Pixel Padding Value (0028,0122)
    /// VR: FL, VM: 1
    public static let floatPixelPaddingValue = Tag(group: 0x0028, element: 0x0122)
    
    /// Double Float Pixel Padding Value (0028,0123)
    /// VR: FD, VM: 1
    public static let doubleFloatPixelPaddingValue = Tag(group: 0x0028, element: 0x0123)
    
    /// Float Pixel Padding Range Limit (0028,0124)
    /// VR: FL, VM: 1
    public static let floatPixelPaddingRangeLimit = Tag(group: 0x0028, element: 0x0124)
    
    /// Double Float Pixel Padding Range Limit (0028,0125)
    /// VR: FD, VM: 1
    public static let doubleFloatPixelPaddingRangeLimit = Tag(group: 0x0028, element: 0x0125)
    
    // MARK: - Image Plane
    
    /// Image Position (Patient) (0020,0032)
    /// VR: DS, VM: 3
    public static let imagePositionPatient = Tag(group: 0x0020, element: 0x0032)
    
    /// Image Orientation (Patient) (0020,0037)
    /// VR: DS, VM: 6
    public static let imageOrientationPatient = Tag(group: 0x0020, element: 0x0037)
    
    /// Slice Location (0020,1041)
    /// VR: DS, VM: 1
    public static let sliceLocation = Tag(group: 0x0020, element: 0x1041)
    
    /// Slice Thickness (0018,0050)
    /// VR: DS, VM: 1
    public static let sliceThickness = Tag(group: 0x0018, element: 0x0050)
    
    /// Spacing Between Slices (0018,0088)
    /// VR: DS, VM: 1
    public static let spacingBetweenSlices = Tag(group: 0x0018, element: 0x0088)
    
    /// Pixel Spacing (0028,0030)
    /// VR: DS, VM: 2
    public static let pixelSpacing = Tag(group: 0x0028, element: 0x0030)
    
    /// Imager Pixel Spacing (0018,1164)
    /// VR: DS, VM: 2
    public static let imagerPixelSpacing = Tag(group: 0x0018, element: 0x1164)
    
    // MARK: - Multi-frame and Cine
    
    /// Number of Frames (0028,0008)
    /// VR: IS, VM: 1
    public static let numberOfFrames = Tag(group: 0x0028, element: 0x0008)
    
    /// Frame Increment Pointer (0028,0009)
    /// VR: AT, VM: 1-n
    public static let frameIncrementPointer = Tag(group: 0x0028, element: 0x0009)
    
    /// Frame Dimension Pointer (0028,000A)
    /// VR: AT, VM: 1-n
    public static let frameDimensionPointer = Tag(group: 0x0028, element: 0x000A)
    
    /// Ultrasound Color Data Present (0028,0014)
    /// VR: US, VM: 1
    public static let ultrasoundColorDataPresent = Tag(group: 0x0028, element: 0x0014)
    
    /// Frame Time (0018,1063)
    /// VR: DS, VM: 1
    public static let frameTime = Tag(group: 0x0018, element: 0x1063)
    
    /// Frame Time Vector (0018,1065)
    /// VR: DS, VM: 1-n
    public static let frameTimeVector = Tag(group: 0x0018, element: 0x1065)
    
    /// Frame Delay (0018,1066)
    /// VR: DS, VM: 1
    public static let frameDelay = Tag(group: 0x0018, element: 0x1066)
    
    /// Actual Frame Duration (0018,1242)
    /// VR: IS, VM: 1
    public static let actualFrameDuration = Tag(group: 0x0018, element: 0x1242)
    
    /// Cine Rate (0018,0040)
    /// VR: IS, VM: 1
    public static let cineRate = Tag(group: 0x0018, element: 0x0040)
    
    /// Preferred Playback Sequencing (0018,1244)
    /// VR: US, VM: 1
    public static let preferredPlaybackSequencing = Tag(group: 0x0018, element: 0x1244)
    
    /// Frame Label Vector (0018,2002)
    /// VR: SH, VM: 1-n
    public static let frameLabelVector = Tag(group: 0x0018, element: 0x2002)
    
    // MARK: - Contrast/Bolus
    
    /// Contrast/Bolus Agent (0018,0010)
    /// VR: LO, VM: 1
    public static let contrastBolusAgent = Tag(group: 0x0018, element: 0x0010)
    
    /// Contrast/Bolus Agent Sequence (0018,0012)
    /// VR: SQ, VM: 1
    public static let contrastBolusAgentSequence = Tag(group: 0x0018, element: 0x0012)
    
    /// Contrast/Bolus Route (0018,1040)
    /// VR: LO, VM: 1
    public static let contrastBolusRoute = Tag(group: 0x0018, element: 0x1040)
    
    /// Contrast/Bolus Volume (0018,1041)
    /// VR: DS, VM: 1
    public static let contrastBolusVolume = Tag(group: 0x0018, element: 0x1041)
    
    /// Contrast/Bolus Start Time (0018,1042)
    /// VR: TM, VM: 1
    public static let contrastBolusStartTime = Tag(group: 0x0018, element: 0x1042)
    
    /// Contrast/Bolus Stop Time (0018,1043)
    /// VR: TM, VM: 1
    public static let contrastBolusStopTime = Tag(group: 0x0018, element: 0x1043)
    
    /// Contrast/Bolus Total Dose (0018,1044)
    /// VR: DS, VM: 1
    public static let contrastBolusTotalDose = Tag(group: 0x0018, element: 0x1044)
    
    /// Contrast Flow Rate (0018,1046)
    /// VR: DS, VM: 1-n
    public static let contrastFlowRate = Tag(group: 0x0018, element: 0x1046)
    
    /// Contrast Flow Duration (0018,1047)
    /// VR: DS, VM: 1-n
    public static let contrastFlowDuration = Tag(group: 0x0018, element: 0x1047)
    
    /// Contrast/Bolus Ingredient (0018,1048)
    /// VR: CS, VM: 1
    public static let contrastBolusIngredient = Tag(group: 0x0018, element: 0x1048)
    
    /// Contrast/Bolus Ingredient Concentration (0018,1049)
    /// VR: DS, VM: 1
    public static let contrastBolusIngredientConcentration = Tag(group: 0x0018, element: 0x1049)
}
