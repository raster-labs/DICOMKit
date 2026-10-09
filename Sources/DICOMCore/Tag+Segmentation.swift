//
// Tag+Segmentation.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// DICOM tags for Segmentation IOD and Multi-frame Functional Groups
///
/// Reference: PS3.6 Section 6 - Registry of DICOM Data Elements
/// Segmentation tags are in group 0x0062
/// Multi-frame Functional Groups tags are in group 0x5200
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    
    // MARK: - Segmentation Image Module (PS3.3 C.8.20.2)
    
    /// Content Label (0070,0080)
    /// Same tag as Presentation Label, used in Segmentation for content identification
    public static let contentLabel = Tag(group: 0x0070, element: 0x0080)
    
    /// Content Description (0070,0081)
    /// Same tag as Presentation Description, used in Segmentation
    public static let contentDescription = Tag(group: 0x0070, element: 0x0081)
    
    /// Content Creator's Name (0070,0084)
    /// Same tag as Presentation Creator's Name, used in Segmentation
    public static let contentCreatorName = Tag(group: 0x0070, element: 0x0084)
    
    /// Segmentation Type (0062,0001)
    /// Required. Values: BINARY or FRACTIONAL
    public static let segmentationType = Tag(group: 0x0062, element: 0x0001)
    
    /// Segment Sequence (0062,0002)
    /// Required. Sequence defining all segments in this segmentation
    public static let segmentSequence = Tag(group: 0x0062, element: 0x0002)
    
    /// Maximum Fractional Value (0062,000E) — PS3.6 keyword MaximumFractionalValue
    /// Required if Segmentation Type is FRACTIONAL
    public static let maximumFractionalValue = Tag(group: 0x0062, element: 0x000E)

    @available(*, deprecated, renamed: "maximumFractionalValue", message: "PS3.6 keyword is MaximumFractionalValue")
    public static var maxFractionalValue: Tag { .maximumFractionalValue }
    
    /// Segmentation Fractional Type (0062,0010)
    /// Required if Segmentation Type is FRACTIONAL. Values: PROBABILITY or OCCUPANCY
    public static let segmentationFractionalType = Tag(group: 0x0062, element: 0x0010)
    
    // MARK: - Segment Description Macro (PS3.3 C.8.20.4)
    
    /// Segmented Property Category Code Sequence (0062,0003)
    public static let segmentedPropertyCategoryCodeSequence = Tag(group: 0x0062, element: 0x0003)
    
    /// Segment Number (0062,0004)
    /// Required. Unique identifier for this segment (starts from 1)
    public static let segmentNumber = Tag(group: 0x0062, element: 0x0004)
    
    /// Segment Label (0062,0005)
    /// Required. Human-readable name for this segment
    public static let segmentLabel = Tag(group: 0x0062, element: 0x0005)
    
    /// Segment Description (0062,0006)
    public static let segmentDescription = Tag(group: 0x0062, element: 0x0006)
    
    /// Segment Algorithm Type (0062,0008)
    /// Values: AUTOMATIC, SEMIAUTOMATIC, MANUAL
    public static let segmentAlgorithmType = Tag(group: 0x0062, element: 0x0008)
    
    /// Segment Algorithm Name (0062,0009)
    public static let segmentAlgorithmName = Tag(group: 0x0062, element: 0x0009)
    
    /// Recommended Display CIELab Value (0062,000D)
    /// Three values: L*, a*, b* (each 0-65535)
    public static let recommendedDisplayCIELabValue = Tag(group: 0x0062, element: 0x000D)
    
    /// Segmented Property Type Code Sequence (0062,000F)
    public static let segmentedPropertyTypeCodeSequence = Tag(group: 0x0062, element: 0x000F)
    
    /// Tracking ID (0062,0020)
    public static let trackingID = Tag(group: 0x0062, element: 0x0020)
    
    /// Tracking UID (0062,0021)
    public static let trackingUID = Tag(group: 0x0062, element: 0x0021)
    
    // MARK: - Multi-frame Functional Groups Module (PS3.3 C.7.6.16)
    
    /// Shared Functional Groups Sequence (5200,9229)
    /// Contains functional groups shared by all frames
    public static let sharedFunctionalGroupsSequence = Tag(group: 0x5200, element: 0x9229)
    
    /// Per-frame Functional Groups Sequence (5200,9230)
    /// Contains functional groups specific to each frame
    public static let perFrameFunctionalGroupsSequence = Tag(group: 0x5200, element: 0x9230)
    
    // MARK: - Functional Group Macros
    
    /// Segment Identification Sequence (0062,000A)
    /// Identifies which segment a frame belongs to
    public static let segmentIdentificationSequence = Tag(group: 0x0062, element: 0x000A)
    
    // Note: referencedSegmentNumber (0062,000B) is defined in Tag+StructuredReporting.swift
    
    /// Derivation Image Sequence (0008,9124)
    /// Describes how frame was derived from source images
    public static let derivationImageSequence = Tag(group: 0x0008, element: 0x9124)
    
    /// Source Image Sequence (0008,2112)
    /// References source images used for derivation
    public static let sourceImageSequence = Tag(group: 0x0008, element: 0x2112)
    
    /// Derivation Description (0008,2111)
    public static let derivationDescription = Tag(group: 0x0008, element: 0x2111)
    
    /// Derivation Code Sequence (0008,9215)
    public static let derivationCodeSequence = Tag(group: 0x0008, element: 0x9215)
    
    // Note: purposeOfReferenceCodeSequence (0040,A170) is defined in Tag+StructuredReporting.swift
    
    /// Frame Content Sequence (0020,9111)
    /// Contains frame-specific temporal and organizational information
    public static let frameContentSequence = Tag(group: 0x0020, element: 0x9111)

    /// Pixel Measures Sequence (0028,9110)
    /// Contains Pixel Spacing / Slice Thickness / Spacing Between Slices
    public static let pixelMeasuresSequence = Tag(group: 0x0028, element: 0x9110)

    /// Stack ID (0020,9056)
    public static let stackID = Tag(group: 0x0020, element: 0x9056)

    /// In-Stack Position Number (0020,9057)
    public static let inStackPositionNumber = Tag(group: 0x0020, element: 0x9057)

    /// Frame Acquisition Number (0020,9156)
    public static let frameAcquisitionNumber = Tag(group: 0x0020, element: 0x9156)
    
    /// Frame Reference DateTime (0018,9151)
    public static let frameReferenceDateTime = Tag(group: 0x0018, element: 0x9151)
    
    /// Frame Acquisition DateTime (0018,9074)
    public static let frameAcquisitionDateTime = Tag(group: 0x0018, element: 0x9074)
    
    /// Dimension Index Values (0020,9157)
    public static let dimensionIndexValues = Tag(group: 0x0020, element: 0x9157)
    
    /// Plane Position Sequence (0020,9113)
    /// Contains Image Position (Patient)
    public static let planePositionSequence = Tag(group: 0x0020, element: 0x9113)
    
    // Note: imagePositionPatient (0020,0032) is defined in Tag+ImageInformation.swift
    
    /// Plane Orientation Sequence (0020,9116)
    /// Contains Image Orientation (Patient)
    public static let planeOrientationSequence = Tag(group: 0x0020, element: 0x9116)
    
    // Note: imageOrientationPatient (0020,0037) is defined in Tag+ImageInformation.swift
    
    /// Dimension Organization UID (0020,9164)
    /// Identifies the dimension organization
    public static let dimensionOrganizationUID = Tag(group: 0x0020, element: 0x9164)
    
    // MARK: - Anatomic Region Sequence (shared with SR)
    
    // Note: anatomicRegionSequence (0008,2218) is defined in Tag+SeriesInformation.swift
    // Note: anatomicRegionModifierSequence (0008,2220) is defined in Tag+SeriesInformation.swift
}
