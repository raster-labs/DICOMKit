//
// Tag+ParametricMap.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// DICOM tags for Parametric Map IOD
///
/// Reference: PS3.6 Section 6 - Registry of DICOM Data Elements
/// Parametric Map tags are in group 0x0068
/// Real World Value Mapping tags are in group 0x0040
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    
    // MARK: - Parametric Map Series Module (PS3.3 C.8.23.1)
    
    /// Content Label (0070,0080)
    /// Already defined in Tag+Segmentation, reused here for consistency
    // public static let contentLabel = Tag(group: 0x0070, element: 0x0080)
    
    /// Content Description (0070,0081)
    /// Already defined in Tag+Segmentation, reused here for consistency
    // public static let contentDescription = Tag(group: 0x0070, element: 0x0081)
    
    /// Content Creator's Name (0070,0084)
    /// Already defined in Tag+Segmentation, reused here for consistency
    // public static let contentCreatorName = Tag(group: 0x0070, element: 0x0084)
    
    // MARK: - Parametric Map Image Module (PS3.3 C.8.23.2)
    
    /// Derivation Description (0008,2111)
    /// Already defined in Tag+Segmentation
    // public static let derivationDescription = Tag(group: 0x0008, element: 0x2111)
    
    /// Derivation Code Sequence (0008,9215)
    /// Already defined in Tag+Segmentation
    // public static let derivationCodeSequence = Tag(group: 0x0008, element: 0x9215)
    
    /// Source Image Sequence (0008,2112)
    /// Already defined in Tag+Segmentation
    // public static let sourceImageSequence = Tag(group: 0x0008, element: 0x2112)
    
    // MARK: - Real World Value Mapping Module (PS3.3 C.7.6.16.2.11)
    
    /// Real World Value Mapping Sequence (0040,9096)
    /// Sequence containing real world value mapping items
    public static let realWorldValueMappingSequence = Tag(group: 0x0040, element: 0x9096)
    
    /// Real World Value LUT Data (0040,9212)
    /// LUT data for real world value mapping
    public static let realWorldValueLUTData = Tag(group: 0x0040, element: 0x9212)
    
    /// LUT Explanation (0028,3003)
    /// Already defined elsewhere - Free text explanation of the LUT
    // public static let lutExplanation = Tag(group: 0x0028, element: 0x3003)
    
    /// Real World Value First Value Mapped (0040,9216)
    /// First pixel value mapped in the LUT
    public static let realWorldValueFirstValueMapped = Tag(group: 0x0040, element: 0x9216)
    
    /// Real World Value Last Value Mapped (0040,9211)
    /// Last pixel value mapped in the LUT
    public static let realWorldValueLastValueMapped = Tag(group: 0x0040, element: 0x9211)
    
    /// Real World Value Intercept (0040,9224)
    /// Intercept value for linear transformation: RealWorldValue = m * StoredValue + b
    public static let realWorldValueIntercept = Tag(group: 0x0040, element: 0x9224)
    
    /// Real World Value Slope (0040,9225)
    /// Slope value for linear transformation: RealWorldValue = m * StoredValue + b
    public static let realWorldValueSlope = Tag(group: 0x0040, element: 0x9225)
    
    /// Measurement Units Code Sequence (0040,08EA)
    /// Already defined in Tag+StructuredReporting
    /// Units of measurement as coded entry (UCUM)
    // public static let measurementUnitsCodeSequence = Tag(group: 0x0040, element: 0x08EA)
    
    /// Quantity Definition Sequence (0040,9220)
    /// Defines the physical quantity being mapped
    public static let quantityDefinitionSequence = Tag(group: 0x0040, element: 0x9220)
    
    /// Double Float Real World Value First Value Mapped (0040,9214)
    /// VR: FD, VM: 1 — first pixel value mapped in the LUT
    public static let doubleFloatRealWorldValueFirstValueMapped = Tag(group: 0x0040, element: 0x9214)
    
    /// Double Float Real World Value Last Value Mapped (0040,9213)
    /// VR: FD, VM: 1 — last pixel value mapped in the LUT
    public static let doubleFloatRealWorldValueLastValueMapped = Tag(group: 0x0040, element: 0x9213)
    
    /// LUT Label (0040,9210)
    /// Label for the LUT
    public static let lutLabel = Tag(group: 0x0040, element: 0x9210)
    
    // MARK: - Multi-frame Functional Groups (already defined in Tag+Segmentation)
    
    /// Shared Functional Groups Sequence (5200,9229)
    /// Already defined in Tag+Segmentation
    // public static let sharedFunctionalGroupsSequence = Tag(group: 0x5200, element: 0x9229)
    
    /// Per-frame Functional Groups Sequence (5200,9230)
    /// Already defined in Tag+Segmentation
    // public static let perFrameFunctionalGroupsSequence = Tag(group: 0x5200, element: 0x9230)
    
    /// Frame Content Sequence (0020,9111)
    /// Already defined in Tag+Segmentation
    // public static let frameContentSequence = Tag(group: 0x0020, element: 0x9111)
    
    /// Plane Position Sequence (0020,9113)
    /// Already defined in Tag+Segmentation
    // public static let planePositionSequence = Tag(group: 0x0020, element: 0x9113)
    
    /// Plane Orientation Sequence (0020,9116)
    /// Already defined in Tag+Segmentation
    // public static let planeOrientationSequence = Tag(group: 0x0020, element: 0x9116)
    
    /// Dimension Index Values (0020,9157)
    /// Already defined in Tag+Segmentation
    // public static let dimensionIndexValues = Tag(group: 0x0020, element: 0x9157)
    
    // MARK: - Code Sequence Macro (for coded entries)
    
    // Note: codeValue (0008,0100), codingSchemeDesignator (0008,0102),
    // codeMeaning (0008,0104) are defined elsewhere
    
    // MARK: - Dimension Organization
    
    /// Dimension Organization UID (0020,9164)
    /// Already defined in Tag+Segmentation
    // public static let dimensionOrganizationUID = Tag(group: 0x0020, element: 0x9164)
    
    /// Dimension Organization Sequence (0020,9221)
    public static let dimensionOrganizationSequence = Tag(group: 0x0020, element: 0x9221)
    
    /// Dimension Index Sequence (0020,9222)
    public static let dimensionIndexSequence = Tag(group: 0x0020, element: 0x9222)
    
    /// Dimension Index Pointer (0020,9165)
    public static let dimensionIndexPointer = Tag(group: 0x0020, element: 0x9165)
    
    /// Functional Group Pointer (0020,9167)
    public static let functionalGroupPointer = Tag(group: 0x0020, element: 0x9167)
    
    // MARK: - PET-specific Tags (for SUV calculation)
    
    /// Radiopharmaceutical Information Sequence (0054,0016)
    /// Already defined in Tag+ModalitySpecific
    // public static let radiopharmaceuticalInformationSequence = Tag(group: 0x0054, element: 0x0016)
    
    /// Radionuclide Total Dose (0018,1074)
    /// Already defined in Tag+ModalitySpecific
    // public static let radionuclideTotalDose = Tag(group: 0x0018, element: 0x1074)
    
    /// Radionuclide Half Life (0018,1075)
    /// Already defined in Tag+ModalitySpecific
    // public static let radionuclideHalfLife = Tag(group: 0x0018, element: 0x1075)
    
    /// Radiopharmaceutical Start Time (0018,1072)
    /// Already defined in Tag+ModalitySpecific
    // public static let radiopharmaceuticalStartTime = Tag(group: 0x0018, element: 0x1072)
    
    /// Series Date (0008,0021)
    /// Already defined elsewhere
    // public static let seriesDate = Tag(group: 0x0008, element: 0x0021)
    
    /// Series Time (0008,0031)
    /// Already defined elsewhere
    // public static let seriesTime = Tag(group: 0x0008, element: 0x0031)
    
    /// Decay Correction (0054,1102)
    /// Already defined in Tag+ModalitySpecific
    // public static let decayCorrection = Tag(group: 0x0054, element: 0x1102)
    
    /// Patient's Weight (0010,1030)
    /// Already defined in Tag+PatientInformation
    // public static let patientWeight = Tag(group: 0x0010, element: 0x1030)
    
    /// Patient's Size (0010,1020)
    /// Already defined in Tag+PatientInformation
    // public static let patientSize = Tag(group: 0x0010, element: 0x1020)
    
    /// Patient's Sex (0010,0040)
    /// Already defined in Tag+PatientInformation
    // public static let patientSex = Tag(group: 0x0010, element: 0x0040)
    
    // MARK: - Referenced Instance Sequence
    
    /// Referenced Instance Sequence (0008,114A)
    public static let referencedInstanceSequence = Tag(group: 0x0008, element: 0x114A)
}
