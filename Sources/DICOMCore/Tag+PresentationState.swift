//
// Tag+PresentationState.swift
// DICOMCore
//
// Created by DICOMKit on 2026-02-04.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// DICOM tags for Grayscale Softcopy Presentation State
///
/// Reference: PS3.3 Part 3 Section A.33 - Grayscale Softcopy Presentation State IOD
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    // MARK: - Presentation State Identification Module (C.11.10)
    
    /// Instance Number (0020,0013) — use `Tag.instanceNumber`.
    @available(*, deprecated, renamed: "instanceNumber")
    public static let presentationInstanceNumber = Tag.instanceNumber
    
    /// Content Label (0070,0080) — use `Tag.contentLabel` (Tag+Segmentation.swift);
    /// the attribute is shared by Presentation State, Segmentation and KOS IODs.
    @available(*, deprecated, renamed: "contentLabel")
    public static let presentationLabel = Tag.contentLabel
    
    /// Content Description (0070,0081) — use `Tag.contentDescription`.
    @available(*, deprecated, renamed: "contentDescription")
    public static let presentationDescription = Tag.contentDescription
    
    /// Presentation Creation Date (0070,0082)
    public static let presentationCreationDate = Tag(group: 0x0070, element: 0x0082)
    
    /// Presentation Creation Time (0070,0083)
    public static let presentationCreationTime = Tag(group: 0x0070, element: 0x0083)
    
    /// Content Creator's Name (0070,0084) — use `Tag.contentCreatorName`.
    @available(*, deprecated, renamed: "contentCreatorName")
    public static let presentationCreatorsName = Tag.contentCreatorName
    
    // MARK: - Presentation State Relationship Module (C.11.11)
    
    /// Referenced Series Sequence (0008,1115)
    public static let referencedSeriesSequence = Tag(group: 0x0008, element: 0x1115)
    
    /// Referenced Image Sequence (0008,1140)
    public static let referencedImageSequence = Tag(group: 0x0008, element: 0x1140)
    
    // MARK: - Graphic Annotation Module (C.10.5)
    
    /// Graphic Annotation Sequence (0070,0001)
    public static let graphicAnnotationSequence = Tag(group: 0x0070, element: 0x0001)
    
    /// Graphic Layer (0070,0002)
    public static let graphicLayer = Tag(group: 0x0070, element: 0x0002)
    
    /// Text Object Sequence (0070,0008)
    public static let textObjectSequence = Tag(group: 0x0070, element: 0x0008)
    
    /// Graphic Object Sequence (0070,0009)
    public static let graphicObjectSequence = Tag(group: 0x0070, element: 0x0009)
    
    /// Bounding Box Annotation Units (0070,0003)
    public static let boundingBoxAnnotationUnits = Tag(group: 0x0070, element: 0x0003)
    
    /// Anchor Point Annotation Units (0070,0004)
    public static let anchorPointAnnotationUnits = Tag(group: 0x0070, element: 0x0004)

    /// Graphic Annotation Units (0070,0005) — the units of a Graphic Object's
    /// Graphic Data, distinct from the bounding-box units a Text Object uses.
    public static let graphicAnnotationUnits = Tag(group: 0x0070, element: 0x0005)

    /// Unformatted Text Value (0070,0006) — the words of a Text Object, and the
    /// text of a Waveform Annotation (PS3.3 C.10.9). SR's Text Value (0040,A160)
    /// is `Tag.textValue`, a different attribute; parsers read that as a fallback
    /// for files written before the two were distinguished here.
    public static let unformattedTextValue = Tag(group: 0x0070, element: 0x0006)
    
    @available(*, deprecated, renamed: "unformattedTextValue")
    public static let textObjectUnformattedTextValue = Tag.unformattedTextValue

    /// Bounding Box Top Left Hand Corner (0070,0010)
    public static let boundingBoxTopLeftHandCorner = Tag(group: 0x0070, element: 0x0010)

    /// Bounding Box Bottom Right Hand Corner (0070,0011)
    public static let boundingBoxBottomRightHandCorner = Tag(group: 0x0070, element: 0x0011)

    /// Bounding Box Text Horizontal Justification (0070,0012)
    public static let boundingBoxTextHorizontalJustification = Tag(group: 0x0070, element: 0x0012)
    
    /// Anchor Point (0070,0014)
    public static let anchorPoint = Tag(group: 0x0070, element: 0x0014)
    
    /// Anchor Point Visibility (0070,0015)
    public static let anchorPointVisibility = Tag(group: 0x0070, element: 0x0015)
    
    /// Graphic Dimensions (0070,0020)
    public static let graphicDimensions = Tag(group: 0x0070, element: 0x0020)

    /// Number of Graphic Points (0070,0021)
    public static let numberOfGraphicPoints = Tag(group: 0x0070, element: 0x0021)

    /// Graphic Data (0070,0022)
    public static let graphicData = Tag(group: 0x0070, element: 0x0022)
    
    /// Graphic Type (0070,0023)
    public static let graphicType = Tag(group: 0x0070, element: 0x0023)
    
    /// Graphic Filled (0070,0024)
    public static let graphicFilled = Tag(group: 0x0070, element: 0x0024)
    
    // MARK: - Graphic Layer Module (C.10.7)
    
    /// Graphic Layer Sequence (0070,0060)
    public static let graphicLayerSequence = Tag(group: 0x0070, element: 0x0060)
    
    /// Graphic Layer Order (0070,0062)
    public static let graphicLayerOrder = Tag(group: 0x0070, element: 0x0062)
    
    /// Graphic Layer Recommended Display Grayscale Value (0070,0066)
    public static let graphicLayerRecommendedDisplayGrayscaleValue = Tag(group: 0x0070, element: 0x0066)
    
    /// Graphic Layer Recommended Display RGB Value (0070,0067)
    /// Retired in PS3.6 2026a Table 6-1 (RET (2004)). Kept for reading legacy objects.
    public static let graphicLayerRecommendedDisplayRGBValue = Tag(group: 0x0070, element: 0x0067)
    
    /// Graphic Layer Description (0070,0068)
    public static let graphicLayerDescription = Tag(group: 0x0070, element: 0x0068)
    
    // MARK: - Spatial Transformation Module (C.10.6)
    
    /// Image Rotation (0070,0042)
    public static let imageRotation = Tag(group: 0x0070, element: 0x0042)
    
    /// Image Horizontal Flip (0070,0041)
    public static let imageHorizontalFlip = Tag(group: 0x0070, element: 0x0041)
    
    // MARK: - Display Shutter Module (C.7.6.11)
    
    /// Shutter Shape (0018,1600)
    public static let shutterShape = Tag(group: 0x0018, element: 0x1600)
    
    /// Shutter Left Vertical Edge (0018,1602)
    public static let shutterLeftVerticalEdge = Tag(group: 0x0018, element: 0x1602)
    
    /// Shutter Right Vertical Edge (0018,1604)
    public static let shutterRightVerticalEdge = Tag(group: 0x0018, element: 0x1604)
    
    /// Shutter Upper Horizontal Edge (0018,1606)
    public static let shutterUpperHorizontalEdge = Tag(group: 0x0018, element: 0x1606)
    
    /// Shutter Lower Horizontal Edge (0018,1608)
    public static let shutterLowerHorizontalEdge = Tag(group: 0x0018, element: 0x1608)
    
    /// Center of Circular Shutter (0018,1610)
    public static let centerOfCircularShutter = Tag(group: 0x0018, element: 0x1610)
    
    /// Radius of Circular Shutter (0018,1612)
    public static let radiusOfCircularShutter = Tag(group: 0x0018, element: 0x1612)
    
    /// Vertices of the Polygonal Shutter (0018,1620) — PS3.6 keyword VerticesOfThePolygonalShutter
    public static let verticesOfThePolygonalShutter = Tag(group: 0x0018, element: 0x1620)

    @available(*, deprecated, renamed: "verticesOfThePolygonalShutter", message: "PS3.6 keyword is VerticesOfThePolygonalShutter")
    public static var verticesOfPolygonalShutter: Tag { .verticesOfThePolygonalShutter }
    
    /// Shutter Presentation Value (0018,1622)
    public static let shutterPresentationValue = Tag(group: 0x0018, element: 0x1622)
    
    /// Shutter Overlay Group (0018,1623)
    public static let shutterOverlayGroup = Tag(group: 0x0018, element: 0x1623)
    
    // MARK: - Displayed Area Module (C.10.4)
    
    /// Displayed Area Selection Sequence (0070,005A)
    public static let displayedAreaSelectionSequence = Tag(group: 0x0070, element: 0x005A)
    
    /// Displayed Area Top Left Hand Corner (0070,0052)
    public static let displayedAreaTopLeftHandCorner = Tag(group: 0x0070, element: 0x0052)
    
    /// Displayed Area Bottom Right Hand Corner (0070,0053)
    public static let displayedAreaBottomRightHandCorner = Tag(group: 0x0070, element: 0x0053)
    
    /// Presentation Size Mode (0070,0100)
    public static let presentationSizeMode = Tag(group: 0x0070, element: 0x0100)
    
    /// Presentation Pixel Spacing (0070,0101)
    public static let presentationPixelSpacing = Tag(group: 0x0070, element: 0x0101)
    
    /// Presentation Pixel Aspect Ratio (0070,0102)
    public static let presentationPixelAspectRatio = Tag(group: 0x0070, element: 0x0102)
    
    /// Presentation Pixel Magnification Ratio (0070,0103)
    public static let presentationPixelMagnificationRatio = Tag(group: 0x0070, element: 0x0103)
    
    // MARK: - Modality LUT Module (C.11.1)
    // Note: Modality LUT tags are defined in Tag+PixelData.swift
    // - modalityLUTSequence (0028,3000)
    // - rescaleIntercept (0028,1052)
    // - rescaleSlope (0028,1053)
    // - rescaleType (0028,1054)
    
    // MARK: - Softcopy VOI LUT Module (C.11.8)

    /// Softcopy VOI LUT Sequence (0028,3110) — where a presentation state
    /// carries its window. The Softcopy VOI LUT module has no top-level
    /// Window Center/Width; a viewer reading a PR looks only inside this
    /// sequence, which is why writing the values top-level loses the window.
    public static let softcopyVOILUTSequence = Tag(group: 0x0028, element: 0x3110)

    // MARK: - VOI LUT Module (C.11.2)
    // Note: VOI LUT tags are defined in Tag+PixelData.swift
    // - voiLUTSequence (0028,3010)
    // - windowCenter (0028,1050)
    // - windowWidth (0028,1051)
    // - windowCenterWidthExplanation (0028,1055)
    // - voiLUTFunction (0028,1056)
    
    // MARK: - Presentation LUT Module (C.11.6)
    // Note: Presentation LUT tags are defined in Tag+PixelData.swift
    // - presentationLUTSequence (2050,0010)
    // - presentationLUTShape (2050,0020)
    
    // MARK: - LUT Common Attributes
    // Note: LUT common tags are defined in Tag+PixelData.swift
    // - lutDescriptor (0028,3002)
    // - lutData (0028,3006)
    // - lutExplanation (0028,3003)
}
