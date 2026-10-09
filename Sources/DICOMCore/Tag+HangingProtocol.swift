//
// Tag+HangingProtocol.swift
// DICOMCore
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// DICOM tags for Hanging Protocol Information Object Definition
///
/// Reference: PS3.3 Part 3 Section A.38 - Hanging Protocol IOD
/// Reference: PS3.3 Part 3 Section C.23 - Hanging Protocol Module
/// Reference: PS3.6 group 0072
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    // MARK: - Hanging Protocol Definition Module (C.23.1)

    /// Hanging Protocol Name (0072,0002)
    public static let hangingProtocolName = Tag(group: 0x0072, element: 0x0002)

    /// Hanging Protocol Description (0072,0004)
    public static let hangingProtocolDescription = Tag(group: 0x0072, element: 0x0004)

    /// Hanging Protocol Level (0072,0006)
    public static let hangingProtocolLevel = Tag(group: 0x0072, element: 0x0006)

    /// Hanging Protocol Creator (0072,0008)
    public static let hangingProtocolCreator = Tag(group: 0x0072, element: 0x0008)

    /// Hanging Protocol Creation DateTime (0072,000A)
    public static let hangingProtocolCreationDateTime = Tag(group: 0x0072, element: 0x000A)

    /// Hanging Protocol Definition Sequence (0072,000C) — items carry Modality,
    /// Anatomic Region Sequence, Laterality, Procedure Code Sequence and Reason
    /// for Requested Procedure Code Sequence (PS3.3 C.23.1). There is no separate
    /// "environment" sequence in the standard; this is it.
    public static let hangingProtocolDefinitionSequence = Tag(group: 0x0072, element: 0x000C)

    @available(*, deprecated, renamed: "hangingProtocolDefinitionSequence",
               message: "(0072,0010) is Hanging Protocol User Group Name; the environment items live in Hanging Protocol Definition Sequence (0072,000C)")
    public static let hangingProtocolEnvironmentSequence = Tag.hangingProtocolDefinitionSequence

    /// Number of Priors Referenced (0072,0014)
    public static let numberOfPriorsReferenced = Tag(group: 0x0072, element: 0x0014)

    // MARK: - Hanging Protocol User Identification Module (C.23.2)

    /// Hanging Protocol User Identification Code Sequence (0072,000E)
    public static let hangingProtocolUserIdentificationCodeSequence = Tag(group: 0x0072, element: 0x000E)

    /// Hanging Protocol User Group Name (0072,0010)
    public static let hangingProtocolUserGroupName = Tag(group: 0x0072, element: 0x0010)

    /// Source Hanging Protocol Sequence (0072,0012)
    public static let sourceHangingProtocolSequence = Tag(group: 0x0072, element: 0x0012)

    // MARK: - Image Sets (C.23.1)

    /// Image Sets Sequence (0072,0020)
    public static let imageSetsSequence = Tag(group: 0x0072, element: 0x0020)

    /// Image Set Selector Sequence (0072,0022) — inside Image Sets Sequence
    public static let imageSetSelectorSequence = Tag(group: 0x0072, element: 0x0022)

    @available(*, deprecated, renamed: "imageSetSelectorSequence",
               message: "(0072,0050) is Selector Attribute VR; the selector items live in Image Set Selector Sequence (0072,0022)")
    public static let selectorSequence = Tag.imageSetSelectorSequence

    /// Image Set Selector Usage Flag (0072,0024)
    public static let imageSetSelectorUsageFlag = Tag(group: 0x0072, element: 0x0024)

    /// Selector Attribute (0072,0026)
    /// VR: AT, VM: 1
    public static let selectorAttribute = Tag(group: 0x0072, element: 0x0026)

    /// Selector Value Number (0072,0028)
    public static let selectorValueNumber = Tag(group: 0x0072, element: 0x0028)

    /// Time Based Image Sets Sequence (0072,0030)
    public static let timeBasedImageSetsSequence = Tag(group: 0x0072, element: 0x0030)

    /// Image Set Number (0072,0032)
    public static let imageSetNumber = Tag(group: 0x0072, element: 0x0032)

    /// Image Set Selector Category (0072,0034)
    public static let imageSetSelectorCategory = Tag(group: 0x0072, element: 0x0034)

    /// Relative Time (0072,0038)
    public static let relativeTime = Tag(group: 0x0072, element: 0x0038)

    /// Relative Time Units (0072,003A)
    public static let relativeTimeUnits = Tag(group: 0x0072, element: 0x003A)

    /// Abstract Prior Value (0072,003C)
    public static let abstractPriorValue = Tag(group: 0x0072, element: 0x003C)

    /// Abstract Prior Code Sequence (0072,003E)
    public static let abstractPriorCodeSequence = Tag(group: 0x0072, element: 0x003E)

    /// Image Set Label (0072,0040)
    public static let imageSetLabel = Tag(group: 0x0072, element: 0x0040)

    // MARK: - Selector Attribute Macro (C.23.4)

    /// Selector Attribute VR (0072,0050)
    public static let selectorAttributeVR = Tag(group: 0x0072, element: 0x0050)

    /// Selector Sequence Pointer (0072,0052)
    public static let selectorSequencePointer = Tag(group: 0x0072, element: 0x0052)

    /// Selector Sequence Pointer Private Creator (0072,0054)
    public static let selectorSequencePointerPrivateCreator = Tag(group: 0x0072, element: 0x0054)

    /// Selector Attribute Private Creator (0072,0056)
    public static let selectorAttributePrivateCreator = Tag(group: 0x0072, element: 0x0056)

    /// Selector AE Value (0072,005E)
    public static let selectorAEValue = Tag(group: 0x0072, element: 0x005E)
    /// Selector AS Value (0072,005F)
    public static let selectorASValue = Tag(group: 0x0072, element: 0x005F)
    /// Selector AT Value (0072,0060)
    public static let selectorATValue = Tag(group: 0x0072, element: 0x0060)
    /// Selector DA Value (0072,0061)
    public static let selectorDAValue = Tag(group: 0x0072, element: 0x0061)
    /// Selector CS Value (0072,0062)
    public static let selectorCSValue = Tag(group: 0x0072, element: 0x0062)
    /// Selector DT Value (0072,0063)
    public static let selectorDTValue = Tag(group: 0x0072, element: 0x0063)
    /// Selector IS Value (0072,0064)
    public static let selectorISValue = Tag(group: 0x0072, element: 0x0064)
    /// Selector OB Value (0072,0065)
    public static let selectorOBValue = Tag(group: 0x0072, element: 0x0065)
    /// Selector LO Value (0072,0066)
    public static let selectorLOValue = Tag(group: 0x0072, element: 0x0066)
    /// Selector OF Value (0072,0067)
    public static let selectorOFValue = Tag(group: 0x0072, element: 0x0067)
    /// Selector LT Value (0072,0068)
    public static let selectorLTValue = Tag(group: 0x0072, element: 0x0068)
    /// Selector OW Value (0072,0069)
    public static let selectorOWValue = Tag(group: 0x0072, element: 0x0069)
    /// Selector PN Value (0072,006A)
    public static let selectorPNValue = Tag(group: 0x0072, element: 0x006A)
    /// Selector TM Value (0072,006B)
    public static let selectorTMValue = Tag(group: 0x0072, element: 0x006B)
    /// Selector SH Value (0072,006C)
    public static let selectorSHValue = Tag(group: 0x0072, element: 0x006C)
    /// Selector UN Value (0072,006D)
    public static let selectorUNValue = Tag(group: 0x0072, element: 0x006D)
    /// Selector ST Value (0072,006E)
    public static let selectorSTValue = Tag(group: 0x0072, element: 0x006E)
    /// Selector UC Value (0072,006F)
    public static let selectorUCValue = Tag(group: 0x0072, element: 0x006F)
    /// Selector UT Value (0072,0070)
    public static let selectorUTValue = Tag(group: 0x0072, element: 0x0070)
    /// Selector UR Value (0072,0071)
    public static let selectorURValue = Tag(group: 0x0072, element: 0x0071)
    /// Selector DS Value (0072,0072)
    public static let selectorDSValue = Tag(group: 0x0072, element: 0x0072)
    /// Selector OD Value (0072,0073)
    public static let selectorODValue = Tag(group: 0x0072, element: 0x0073)
    /// Selector FD Value (0072,0074)
    public static let selectorFDValue = Tag(group: 0x0072, element: 0x0074)
    /// Selector OL Value (0072,0075)
    public static let selectorOLValue = Tag(group: 0x0072, element: 0x0075)
    /// Selector FL Value (0072,0076)
    public static let selectorFLValue = Tag(group: 0x0072, element: 0x0076)
    /// Selector UL Value (0072,0078)
    public static let selectorULValue = Tag(group: 0x0072, element: 0x0078)
    /// Selector US Value (0072,007A)
    public static let selectorUSValue = Tag(group: 0x0072, element: 0x007A)
    /// Selector SL Value (0072,007C)
    public static let selectorSLValue = Tag(group: 0x0072, element: 0x007C)
    /// Selector SS Value (0072,007E)
    public static let selectorSSValue = Tag(group: 0x0072, element: 0x007E)
    /// Selector UI Value (0072,007F)
    public static let selectorUIValue = Tag(group: 0x0072, element: 0x007F)

    /// Selector Code Sequence Value (0072,0080)
    public static let selectorCodeSequenceValue = Tag(group: 0x0072, element: 0x0080)

    /// Selector OV Value (0072,0081)
    public static let selectorOVValue = Tag(group: 0x0072, element: 0x0081)
    /// Selector SV Value (0072,0082)
    public static let selectorSVValue = Tag(group: 0x0072, element: 0x0082)
    /// Selector UV Value (0072,0083)
    public static let selectorUVValue = Tag(group: 0x0072, element: 0x0083)

    // MARK: - Hanging Protocol Environment Module (C.23.2)

    /// Number of Screens (0072,0100)
    public static let numberOfScreens = Tag(group: 0x0072, element: 0x0100)

    /// Nominal Screen Definition Sequence (0072,0102)
    public static let nominalScreenDefinitionSequence = Tag(group: 0x0072, element: 0x0102)

    /// Number of Vertical Pixels (0072,0104)
    public static let numberOfVerticalPixels = Tag(group: 0x0072, element: 0x0104)

    /// Number of Horizontal Pixels (0072,0106)
    public static let numberOfHorizontalPixels = Tag(group: 0x0072, element: 0x0106)

    /// Display Environment Spatial Position (0072,0108)
    public static let displayEnvironmentSpatialPosition = Tag(group: 0x0072, element: 0x0108)

    /// Screen Minimum Grayscale Bit Depth (0072,010A)
    public static let screenMinimumGrayscaleBitDepth = Tag(group: 0x0072, element: 0x010A)

    /// Screen Minimum Color Bit Depth (0072,010C)
    public static let screenMinimumColorBitDepth = Tag(group: 0x0072, element: 0x010C)

    /// Application Maximum Repaint Time (0072,010E)
    public static let applicationMaximumRepaintTime = Tag(group: 0x0072, element: 0x010E)

    // MARK: - Hanging Protocol Display Module (C.23.3)

    /// Display Sets Sequence (0072,0200)
    public static let displaySetsSequence = Tag(group: 0x0072, element: 0x0200)

    /// Display Set Number (0072,0202)
    public static let displaySetNumber = Tag(group: 0x0072, element: 0x0202)

    /// Display Set Label (0072,0203)
    public static let displaySetLabel = Tag(group: 0x0072, element: 0x0203)

    /// Display Set Presentation Group (0072,0204)
    public static let displaySetPresentationGroup = Tag(group: 0x0072, element: 0x0204)

    /// Display Set Presentation Group Description (0072,0206)
    public static let displaySetPresentationGroupDescription = Tag(group: 0x0072, element: 0x0206)

    /// Partial Data Display Handling (0072,0208)
    public static let partialDataDisplayHandling = Tag(group: 0x0072, element: 0x0208)

    /// Synchronized Scrolling Sequence (0072,0210)
    public static let synchronizedScrollingSequence = Tag(group: 0x0072, element: 0x0210)

    /// Display Set Scrolling Group (0072,0212)
    public static let displaySetScrollingGroup = Tag(group: 0x0072, element: 0x0212)

    /// Navigation Indicator Sequence (0072,0214)
    public static let navigationIndicatorSequence = Tag(group: 0x0072, element: 0x0214)

    /// Navigation Display Set (0072,0216)
    public static let navigationDisplaySet = Tag(group: 0x0072, element: 0x0216)

    /// Reference Display Sets (0072,0218)
    public static let referenceDisplaySets = Tag(group: 0x0072, element: 0x0218)

    /// Image Boxes Sequence (0072,0300)
    public static let imageBoxesSequence = Tag(group: 0x0072, element: 0x0300)

    /// Image Box Number (0072,0302)
    public static let imageBoxNumber = Tag(group: 0x0072, element: 0x0302)

    /// Image Box Layout Type (0072,0304)
    public static let imageBoxLayoutType = Tag(group: 0x0072, element: 0x0304)

    /// Image Box Tile Horizontal Dimension (0072,0306)
    public static let imageBoxTileHorizontalDimension = Tag(group: 0x0072, element: 0x0306)

    /// Image Box Tile Vertical Dimension (0072,0308)
    public static let imageBoxTileVerticalDimension = Tag(group: 0x0072, element: 0x0308)

    /// Image Box Scroll Direction (0072,0310)
    public static let imageBoxScrollDirection = Tag(group: 0x0072, element: 0x0310)

    /// Image Box Small Scroll Type (0072,0312)
    public static let imageBoxSmallScrollType = Tag(group: 0x0072, element: 0x0312)

    /// Image Box Small Scroll Amount (0072,0314)
    public static let imageBoxSmallScrollAmount = Tag(group: 0x0072, element: 0x0314)

    /// Image Box Large Scroll Type (0072,0316)
    public static let imageBoxLargeScrollType = Tag(group: 0x0072, element: 0x0316)

    /// Image Box Large Scroll Amount (0072,0318)
    public static let imageBoxLargeScrollAmount = Tag(group: 0x0072, element: 0x0318)

    /// Image Box Overlap Priority (0072,0320)
    public static let imageBoxOverlapPriority = Tag(group: 0x0072, element: 0x0320)

    /// Cine Relative to Real-Time (0072,0330)
    public static let cineRelativeToRealTime = Tag(group: 0x0072, element: 0x0330)

    // MARK: - Filter Operations (C.23.3)

    /// Filter Operations Sequence (0072,0400)
    public static let filterOperationsSequence = Tag(group: 0x0072, element: 0x0400)

    /// Filter-by Category (0072,0402)
    public static let filterByCategory = Tag(group: 0x0072, element: 0x0402)

    /// Filter-by Attribute Presence (0072,0404)
    public static let filterByAttributePresence = Tag(group: 0x0072, element: 0x0404)

    /// Filter-by Operator (0072,0406)
    public static let filterByOperator = Tag(group: 0x0072, element: 0x0406)

    // MARK: - Structured Display (C.11.17)

    /// Structured Display Background CIELab Value (0072,0420)
    public static let structuredDisplayBackgroundCIELabValue = Tag(group: 0x0072, element: 0x0420)

    /// Empty Image Box CIELab Value (0072,0421)
    public static let emptyImageBoxCIELabValue = Tag(group: 0x0072, element: 0x0421)

    /// Structured Display Image Box Sequence (0072,0422)
    public static let structuredDisplayImageBoxSequence = Tag(group: 0x0072, element: 0x0422)

    /// Structured Display Text Box Sequence (0072,0424)
    public static let structuredDisplayTextBoxSequence = Tag(group: 0x0072, element: 0x0424)

    /// Referenced First Frame Sequence (0072,0427)
    public static let referencedFirstFrameSequence = Tag(group: 0x0072, element: 0x0427)

    /// Image Box Synchronization Sequence (0072,0430)
    public static let imageBoxSynchronizationSequence = Tag(group: 0x0072, element: 0x0430)

    /// Synchronized Image Box List (0072,0432)
    public static let synchronizedImageBoxList = Tag(group: 0x0072, element: 0x0432)

    /// Type of Synchronization (0072,0434)
    public static let typeOfSynchronization = Tag(group: 0x0072, element: 0x0434)

    @available(*, unavailable, renamed: "imageBoxSynchronizationSequence",
               message: "No such attribute in PS3.6; (0072,0430) is Image Box Synchronization Sequence")
    public static let imageBoxSynchronizationSequencePointer = Tag.imageBoxSynchronizationSequence
    @available(*, unavailable, renamed: "synchronizedImageBoxList",
               message: "No such attribute in PS3.6; (0072,0432) is Synchronized Image Box List")
    public static let textBoxSequencePointer = Tag.synchronizedImageBoxList
    @available(*, unavailable, renamed: "typeOfSynchronization",
               message: "No such attribute in PS3.6; (0072,0434) is Type of Synchronization")
    public static let imageBoxSynchronizationSequenceItemNumber = Tag.typeOfSynchronization
    @available(*, unavailable,
               message: "No such attribute in PS3.6; (0072,0436) is not assigned")
    public static let textBoxSequenceItemNumber = Tag.typeOfSynchronization

    // MARK: - Blending / Reformatting / Rendering (C.23.3)

    /// Blending Operation Type (0072,0500)
    public static let blendingOperationType = Tag(group: 0x0072, element: 0x0500)

    /// Reformatting Operation Type (0072,0510)
    public static let reformattingOperationType = Tag(group: 0x0072, element: 0x0510)

    /// Reformatting Thickness (0072,0512)
    public static let reformattingThickness = Tag(group: 0x0072, element: 0x0512)

    /// Reformatting Interval (0072,0514)
    public static let reformattingInterval = Tag(group: 0x0072, element: 0x0514)

    /// Reformatting Operation Initial View Direction (0072,0516)
    public static let reformattingOperationInitialViewDirection = Tag(group: 0x0072, element: 0x0516)

    /// 3D Rendering Type (0072,0520)
    public static let threeDRenderingType = Tag(group: 0x0072, element: 0x0520)

    // MARK: - Sorting Operations (C.23.3)

    /// Sorting Operations Sequence (0072,0600)
    public static let sortingOperationsSequence = Tag(group: 0x0072, element: 0x0600)

    /// Sort-by Category (0072,0602)
    public static let sortByCategory = Tag(group: 0x0072, element: 0x0602)

    /// Sorting Direction (0072,0604)
    public static let sortingDirection = Tag(group: 0x0072, element: 0x0604)

    // MARK: - Display Set Presentation (C.23.3)

    /// Display Set Patient Orientation (0072,0700)
    public static let displaySetPatientOrientation = Tag(group: 0x0072, element: 0x0700)

    /// VOI Type (0072,0702)
    public static let voiType = Tag(group: 0x0072, element: 0x0702)

    /// Pseudo-Color Type (0072,0704)
    public static let pseudoColorType = Tag(group: 0x0072, element: 0x0704)

    /// Pseudo-Color Palette Instance Reference Sequence (0072,0705)
    public static let pseudoColorPaletteInstanceReferenceSequence = Tag(group: 0x0072, element: 0x0705)

    /// Show Grayscale Inverted (0072,0706)
    public static let showGrayscaleInverted = Tag(group: 0x0072, element: 0x0706)

    /// Show Image True Size Flag (0072,0710)
    public static let showImageTrueSizeFlag = Tag(group: 0x0072, element: 0x0710)

    /// Show Graphic Annotation Flag (0072,0712)
    public static let showGraphicAnnotationFlag = Tag(group: 0x0072, element: 0x0712)

    /// Show Patient Demographics Flag (0072,0714)
    public static let showPatientDemographicsFlag = Tag(group: 0x0072, element: 0x0714)

    /// Show Acquisition Techniques Flag (0072,0716)
    public static let showAcquisitionTechniquesFlag = Tag(group: 0x0072, element: 0x0716)

    /// Display Set Horizontal Justification (0072,0717)
    public static let displaySetHorizontalJustification = Tag(group: 0x0072, element: 0x0717)

    /// Display Set Vertical Justification (0072,0718)
    public static let displaySetVerticalJustification = Tag(group: 0x0072, element: 0x0718)
}
