/// DICOM Tag Extensions - Pixel Data and Related
///
/// Tags from Group 7FE0 and related pixel data elements
/// Reference: DICOM PS3.3 - Information Object Definitions
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    // MARK: - Pixel Data
    
    /// Pixel Data (7FE0,0010)
    /// VR: OB or OW, VM: 1
    public static let pixelData = Tag(group: 0x7FE0, element: 0x0010)
    
    /// Float Pixel Data (7FE0,0008)
    /// VR: OF, VM: 1
    public static let floatPixelData = Tag(group: 0x7FE0, element: 0x0008)
    
    /// Double Float Pixel Data (7FE0,0009)
    /// VR: OD, VM: 1
    public static let doubleFloatPixelData = Tag(group: 0x7FE0, element: 0x0009)
    
    /// Pixel Data Provider URL (0028,7FE0)
    /// VR: UR, VM: 1
    public static let pixelDataProviderURL = Tag(group: 0x0028, element: 0x7FE0)
    
    /// Extended Offset Table (7FE0,0001)
    /// VR: OV, VM: 1
    public static let extendedOffsetTable = Tag(group: 0x7FE0, element: 0x0001)
    
    /// Extended Offset Table Lengths (7FE0,0002)
    /// VR: OV, VM: 1
    public static let extendedOffsetTableLengths = Tag(group: 0x7FE0, element: 0x0002)
    
    // MARK: - LUT (Lookup Table) Data
    
    /// Red Palette Color Lookup Table Data (0028,1201)
    /// VR: OW, VM: 1
    public static let redPaletteColorLookupTableData = Tag(group: 0x0028, element: 0x1201)
    
    /// Green Palette Color Lookup Table Data (0028,1202)
    /// VR: OW, VM: 1
    public static let greenPaletteColorLookupTableData = Tag(group: 0x0028, element: 0x1202)
    
    /// Blue Palette Color Lookup Table Data (0028,1203)
    /// VR: OW, VM: 1
    public static let bluePaletteColorLookupTableData = Tag(group: 0x0028, element: 0x1203)
    
    /// Alpha Palette Color Lookup Table Data (0028,1204)
    /// VR: OW, VM: 1
    public static let alphaPaletteColorLookupTableData = Tag(group: 0x0028, element: 0x1204)
    
    /// Red Palette Color Lookup Table Descriptor (0028,1101)
    /// VR: US or SS, VM: 3
    public static let redPaletteColorLookupTableDescriptor = Tag(group: 0x0028, element: 0x1101)
    
    /// Green Palette Color Lookup Table Descriptor (0028,1102)
    /// VR: US or SS, VM: 3
    public static let greenPaletteColorLookupTableDescriptor = Tag(group: 0x0028, element: 0x1102)
    
    /// Blue Palette Color Lookup Table Descriptor (0028,1103)
    /// VR: US or SS, VM: 3
    public static let bluePaletteColorLookupTableDescriptor = Tag(group: 0x0028, element: 0x1103)
    
    /// Alpha Palette Color Lookup Table Descriptor (0028,1104)
    /// VR: US, VM: 3
    public static let alphaPaletteColorLookupTableDescriptor = Tag(group: 0x0028, element: 0x1104)
    
    /// Segmented Red Palette Color Lookup Table Data (0028,1221)
    /// VR: OW, VM: 1
    public static let segmentedRedPaletteColorLookupTableData = Tag(group: 0x0028, element: 0x1221)
    
    /// Segmented Green Palette Color Lookup Table Data (0028,1222)
    /// VR: OW, VM: 1
    public static let segmentedGreenPaletteColorLookupTableData = Tag(group: 0x0028, element: 0x1222)
    
    /// Segmented Blue Palette Color Lookup Table Data (0028,1223)
    /// VR: OW, VM: 1
    public static let segmentedBluePaletteColorLookupTableData = Tag(group: 0x0028, element: 0x1223)
    
    /// Segmented Alpha Palette Color Lookup Table Data (0028,1224)
    /// VR: OW, VM: 1
    public static let segmentedAlphaPaletteColorLookupTableData = Tag(group: 0x0028, element: 0x1224)
    
    // MARK: - LUT Storage
    
    /// Large Red Palette Color Lookup Table Data (0028,1211)
    /// VR: OW, VM: 1
    /// Retired
    public static let largeRedPaletteColorLookupTableData = Tag(group: 0x0028, element: 0x1211)
    
    /// Large Green Palette Color Lookup Table Data (0028,1212)
    /// VR: OW, VM: 1
    /// Retired
    public static let largeGreenPaletteColorLookupTableData = Tag(group: 0x0028, element: 0x1212)
    
    /// Large Blue Palette Color Lookup Table Data (0028,1213)
    /// VR: OW, VM: 1
    /// Retired
    public static let largeBluePaletteColorLookupTableData = Tag(group: 0x0028, element: 0x1213)
    
    /// Large Palette Color Lookup Table UID (0028,1214)
    /// VR: UI, VM: 1
    /// Retired
    public static let largePaletteColorLookupTableUID = Tag(group: 0x0028, element: 0x1214)

    /// Palette Color Lookup Table UID (0028,1199)
    /// VR: UI, VM: 1
    ///
    /// Names a Well-known Color Palette (PS3.6 Annex B) when the LUT is one of
    /// the standard's own, so a reader can recognise the palette without
    /// diffing tables.
    public static let paletteColorLookupTableUID = Tag(group: 0x0028, element: 0x1199)
    
    // MARK: - ICC Profile
    
    /// ICC Profile (0028,2000)
    /// VR: OB, VM: 1
    public static let iccProfile = Tag(group: 0x0028, element: 0x2000)
    
    /// Color Space (0028,2002)
    /// VR: CS, VM: 1
    public static let colorSpace = Tag(group: 0x0028, element: 0x2002)
    
    // MARK: - Modality LUT
    
    /// Modality LUT Sequence (0028,3000)
    /// VR: SQ, VM: 1
    public static let modalityLUTSequence = Tag(group: 0x0028, element: 0x3000)
    
    /// Rescale Intercept (0028,1052)
    /// VR: DS, VM: 1
    public static let rescaleIntercept = Tag(group: 0x0028, element: 0x1052)
    
    /// Rescale Slope (0028,1053)
    /// VR: DS, VM: 1
    public static let rescaleSlope = Tag(group: 0x0028, element: 0x1053)
    
    /// Rescale Type (0028,1054)
    /// VR: LO, VM: 1
    public static let rescaleType = Tag(group: 0x0028, element: 0x1054)
    
    // MARK: - VOI LUT (Value of Interest Lookup Table)
    
    /// VOI LUT Sequence (0028,3010)
    /// VR: SQ, VM: 1
    public static let voiLUTSequence = Tag(group: 0x0028, element: 0x3010)
    
    /// Window Center (0028,1050)
    /// VR: DS, VM: 1-n
    public static let windowCenter = Tag(group: 0x0028, element: 0x1050)
    
    /// Window Width (0028,1051)
    /// VR: DS, VM: 1-n
    public static let windowWidth = Tag(group: 0x0028, element: 0x1051)
    
    /// Window Center & Width Explanation (0028,1055)
    /// VR: LO, VM: 1-n
    public static let windowCenterWidthExplanation = Tag(group: 0x0028, element: 0x1055)
    
    /// VOI LUT Function (0028,1056)
    /// VR: CS, VM: 1
    public static let voiLUTFunction = Tag(group: 0x0028, element: 0x1056)
    
    // MARK: - Image Presentation
    
    /// Presentation LUT Sequence (2050,0010)
    /// VR: SQ, VM: 1
    public static let presentationLUTSequence = Tag(group: 0x2050, element: 0x0010)
    
    /// Presentation LUT Shape (2050,0020)
    /// VR: CS, VM: 1
    public static let presentationLUTShape = Tag(group: 0x2050, element: 0x0020)
    
    // MARK: - LUT Descriptor and Data Items (for sequences)
    
    /// LUT Descriptor (0028,3002)
    /// VR: US or SS, VM: 3
    public static let lutDescriptor = Tag(group: 0x0028, element: 0x3002)
    
    /// LUT Explanation (0028,3003)
    /// VR: LO, VM: 1
    public static let lutExplanation = Tag(group: 0x0028, element: 0x3003)
    
    /// LUT Data (0028,3006)
    /// VR: US or OW, VM: 1-n or 1
    public static let lutData = Tag(group: 0x0028, element: 0x3006)
}
