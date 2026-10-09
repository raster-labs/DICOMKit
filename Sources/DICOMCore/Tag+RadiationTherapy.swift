//
// Tag+RadiationTherapy.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// DICOM tags for Radiation Therapy (RT) related modules
///
/// Reference: PS3.6 Section 6 - Registry of DICOM Data Elements
/// RT tags are in group 0x3006
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    
    // MARK: - Structure Set Module (PS3.3 C.8.8.5)
    
    /// Structure Set Label (3006,0002)
    public static let structureSetLabel = Tag(group: 0x3006, element: 0x0002)
    
    /// Structure Set Name (3006,0004)
    public static let structureSetName = Tag(group: 0x3006, element: 0x0004)
    
    /// Structure Set Description (3006,0006)
    public static let structureSetDescription = Tag(group: 0x3006, element: 0x0006)
    
    /// Structure Set Date (3006,0008)
    public static let structureSetDate = Tag(group: 0x3006, element: 0x0008)
    
    /// Structure Set Time (3006,0009)
    public static let structureSetTime = Tag(group: 0x3006, element: 0x0009)
    
    /// Referenced Frame of Reference Sequence (3006,0010)
    public static let referencedFrameOfReferenceSequence = Tag(group: 0x3006, element: 0x0010)
    
    /// Structure Set ROI Sequence (3006,0020)
    public static let structureSetROISequence = Tag(group: 0x3006, element: 0x0020)
    
    // MARK: - Structure Set ROI Sequence Item Attributes
    
    /// ROI Number (3006,0022)
    public static let roiNumber = Tag(group: 0x3006, element: 0x0022)
    
    /// Referenced Frame of Reference UID (3006,0024)
    public static let referencedFrameOfReferenceUID = Tag(group: 0x3006, element: 0x0024)
    
    /// ROI Name (3006,0026)
    public static let roiName = Tag(group: 0x3006, element: 0x0026)
    
    /// ROI Description (3006,0028)
    public static let roiDescription = Tag(group: 0x3006, element: 0x0028)
    
    /// ROI Generation Algorithm (3006,0036)
    public static let roiGenerationAlgorithm = Tag(group: 0x3006, element: 0x0036)
    
    /// ROI Generation Description (3006,0038)
    public static let roiGenerationDescription = Tag(group: 0x3006, element: 0x0038)
    
    // MARK: - ROI Contour Module (PS3.3 C.8.8.6)
    
    /// ROI Contour Sequence (3006,0039)
    public static let roiContourSequence = Tag(group: 0x3006, element: 0x0039)
    
    /// Contour Sequence (3006,0040)
    public static let contourSequence = Tag(group: 0x3006, element: 0x0040)
    
    /// Contour Geometric Type (3006,0042)
    public static let contourGeometricType = Tag(group: 0x3006, element: 0x0042)
    
    /// Contour Slab Thickness (3006,0044)
    /// Retired in PS3.6 2026a Table 6-1 (RET (2020e)). Kept for reading legacy objects.
    public static let contourSlabThickness = Tag(group: 0x3006, element: 0x0044)
    
    /// Contour Offset Vector (3006,0045)
    /// Retired in PS3.6 2026a Table 6-1 (RET (2020e)). Kept for reading legacy objects.
    public static let contourOffsetVector = Tag(group: 0x3006, element: 0x0045)
    
    /// Number of Contour Points (3006,0046)
    public static let numberOfContourPoints = Tag(group: 0x3006, element: 0x0046)
    
    /// Contour Data (3006,0050)
    public static let contourData = Tag(group: 0x3006, element: 0x0050)
    
    /// ROI Display Color (3006,002A)
    public static let roiDisplayColor = Tag(group: 0x3006, element: 0x002A)
    
    // MARK: - Contour Image Sequence Attributes
    
    /// Contour Image Sequence (3006,0016)
    public static let contourImageSequence = Tag(group: 0x3006, element: 0x0016)
    
    // MARK: - RT ROI Observations Module (PS3.3 C.8.8.8)
    
    /// RT ROI Observations Sequence (3006,0080)
    public static let rtROIObservationsSequence = Tag(group: 0x3006, element: 0x0080)
    
    /// Observation Number (3006,0082)
    public static let observationNumber = Tag(group: 0x3006, element: 0x0082)
    
    /// Referenced ROI Number (3006,0084)
    public static let referencedROINumber = Tag(group: 0x3006, element: 0x0084)
    
    /// RT ROI Interpreted Type (3006,00A4)
    public static let rtROIInterpretedType = Tag(group: 0x3006, element: 0x00A4)
    
    /// ROI Interpreter (3006,00A6)
    public static let roiInterpreter = Tag(group: 0x3006, element: 0x00A6)
    
    /// ROI Physical Properties Sequence (3006,00B0)
    public static let roiPhysicalPropertiesSequence = Tag(group: 0x3006, element: 0x00B0)
    
    /// ROI Physical Property (3006,00B2)
    public static let roiPhysicalProperty = Tag(group: 0x3006, element: 0x00B2)
    
    /// ROI Physical Property Value (3006,00B4)
    public static let roiPhysicalPropertyValue = Tag(group: 0x3006, element: 0x00B4)
    
    /// ROI Elemental Composition Sequence (3006,00B6)
    public static let roiElementalCompositionSequence = Tag(group: 0x3006, element: 0x00B6)
    
    /// ROI Elemental Composition Atomic Number (3006,00B7)
    public static let roiElementalCompositionAtomicNumber = Tag(group: 0x3006, element: 0x00B7)
    
    // MARK: - RT Series Module (PS3.3 C.8.8.1)
    
    /// Modality (0008,0060) - typically "RTSTRUCT"
    /// Already defined in Tag+ImageInformation
    
    /// Series Description (0008,103E)
    /// Already defined in Tag+SeriesInformation
    
    // MARK: - Referenced Study and Series
    
    /// RT Referenced Study Sequence (3006,0012)
    public static let rtReferencedStudySequence = Tag(group: 0x3006, element: 0x0012)
    
    /// RT Referenced Series Sequence (3006,0014)
    public static let rtReferencedSeriesSequence = Tag(group: 0x3006, element: 0x0014)
    
    // MARK: - RT Plan Module (PS3.3 C.8.8.14, C.8.8.15, C.8.8.16)
    // Group 300A
    
    /// RT Plan Label (300A,0002)
    public static let rtPlanLabel = Tag(group: 0x300A, element: 0x0002)
    
    /// RT Plan Name (300A,0003)
    public static let rtPlanName = Tag(group: 0x300A, element: 0x0003)
    
    /// RT Plan Description (300A,0004)
    public static let rtPlanDescription = Tag(group: 0x300A, element: 0x0004)
    
    /// RT Plan Date (300A,0006)
    public static let rtPlanDate = Tag(group: 0x300A, element: 0x0006)
    
    /// RT Plan Time (300A,0007)
    public static let rtPlanTime = Tag(group: 0x300A, element: 0x0007)
    
    /// RT Plan Geometry (300A,000C)
    public static let rtPlanGeometry = Tag(group: 0x300A, element: 0x000C)
    
    /// Prescription Description (300A,000E)
    public static let prescriptionDescription = Tag(group: 0x300A, element: 0x000E)
    
    /// Dose Reference Sequence (300A,0010)
    public static let doseReferenceSequence = Tag(group: 0x300A, element: 0x0010)
    
    /// Dose Reference Number (300A,0012)
    public static let doseReferenceNumber = Tag(group: 0x300A, element: 0x0012)
    
    /// Dose Reference UID (300A,0013)
    public static let doseReferenceUID = Tag(group: 0x300A, element: 0x0013)
    
    /// Dose Reference Structure Type (300A,0014)
    public static let doseReferenceStructureType = Tag(group: 0x300A, element: 0x0014)
    
    /// Dose Reference Description (300A,0016)
    public static let doseReferenceDescription = Tag(group: 0x300A, element: 0x0016)
    
    /// Dose Reference Type (300A,0020)
    public static let doseReferenceType = Tag(group: 0x300A, element: 0x0020)
    
    /// Target Prescription Dose (300A,0026)
    public static let targetPrescriptionDose = Tag(group: 0x300A, element: 0x0026)
    
    /// Target Maximum Dose (300A,0027)
    public static let targetMaximumDose = Tag(group: 0x300A, element: 0x0027)
    
    /// Target Minimum Dose (300A,0025)
    public static let targetMinimumDose = Tag(group: 0x300A, element: 0x0025)
    
    /// Organ at Risk Full-Volume Dose (300A,002A)
    public static let organAtRiskFullVolumeDose = Tag(group: 0x300A, element: 0x002A)
    
    /// Organ at Risk Maximum Dose (300A,002C)
    public static let organAtRiskMaximumDose = Tag(group: 0x300A, element: 0x002C)
    
    /// Fraction Group Sequence (300A,0070)
    public static let fractionGroupSequence = Tag(group: 0x300A, element: 0x0070)
    
    /// Fraction Group Number (300A,0071)
    public static let fractionGroupNumber = Tag(group: 0x300A, element: 0x0071)
    
    /// Fraction Group Description (300A,0072)
    public static let fractionGroupDescription = Tag(group: 0x300A, element: 0x0072)
    
    /// Number of Fractions Planned (300A,0078)
    public static let numberOfFractionsPlanned = Tag(group: 0x300A, element: 0x0078)
    
    /// Number of Fraction Pattern Digits Per Day (300A,0079)
    public static let numberOfFractionPatternDigitsPerDay = Tag(group: 0x300A, element: 0x0079)
    
    /// Repeat Fraction Cycle Length (300A,007A)
    public static let repeatFractionCycleLength = Tag(group: 0x300A, element: 0x007A)
    
    /// Fraction Pattern (300A,007B)
    public static let fractionPattern = Tag(group: 0x300A, element: 0x007B)
    
    /// Number of Beams (300A,0080)
    public static let numberOfBeams = Tag(group: 0x300A, element: 0x0080)
    
    /// Beam Sequence (300A,00B0)
    public static let beamSequence = Tag(group: 0x300A, element: 0x00B0)
    
    /// Beam Number (300A,00C0)
    public static let beamNumber = Tag(group: 0x300A, element: 0x00C0)
    
    /// Beam Name (300A,00C2)
    public static let beamName = Tag(group: 0x300A, element: 0x00C2)
    
    /// Beam Description (300A,00C3)
    public static let beamDescription = Tag(group: 0x300A, element: 0x00C3)
    
    /// Beam Type (300A,00C4)
    public static let beamType = Tag(group: 0x300A, element: 0x00C4)
    
    /// Radiation Type (300A,00C6)
    public static let radiationType = Tag(group: 0x300A, element: 0x00C6)
    
    /// High-Dose Technique Type (300A,00C7) — CS, VM 1 (PS3.6 2026a Table 6-1)
    public static let highDoseTechniqueType = Tag(group: 0x300A, element: 0x00C7)
    
    /// Treatment Delivery Type (300A,00CE) — CS, VM 1 (PS3.6 2026a Table 6-1)
    public static let treatmentDeliveryType = Tag(group: 0x300A, element: 0x00CE)
    
    /// Treatment Machine Name (300A,00B2)
    public static let treatmentMachineName = Tag(group: 0x300A, element: 0x00B2)
    
    /// Manufacturer (0008,0070) - Already defined in core tags
    
    /// Primary Dosimeter Unit (300A,00B3)
    public static let primaryDosimeterUnit = Tag(group: 0x300A, element: 0x00B3)
    
    /// Source-Axis Distance (300A,00B4)
    public static let sourceAxisDistance = Tag(group: 0x300A, element: 0x00B4)
    
    /// Control Point Sequence (300A,0111)
    public static let controlPointSequence = Tag(group: 0x300A, element: 0x0111)
    
    /// Control Point Index (300A,0112)
    public static let controlPointIndex = Tag(group: 0x300A, element: 0x0112)
    
    /// Cumulative Meterset Weight (300A,0134)
    public static let cumulativeMetersetWeight = Tag(group: 0x300A, element: 0x0134)
    
    /// Gantry Angle (300A,011E)
    public static let gantryAngle = Tag(group: 0x300A, element: 0x011E)
    
    /// Gantry Rotation Direction (300A,011F)
    public static let gantryRotationDirection = Tag(group: 0x300A, element: 0x011F)
    
    /// Beam Limiting Device Angle (300A,0120)
    public static let beamLimitingDeviceAngle = Tag(group: 0x300A, element: 0x0120)
    
    /// Beam Limiting Device Rotation Direction (300A,0121)
    public static let beamLimitingDeviceRotationDirection = Tag(group: 0x300A, element: 0x0121)
    
    /// Patient Support Angle (300A,0122)
    public static let patientSupportAngle = Tag(group: 0x300A, element: 0x0122)
    
    /// Patient Support Rotation Direction (300A,0123)
    public static let patientSupportRotationDirection = Tag(group: 0x300A, element: 0x0123)
    
    /// Table Top Vertical Position (300A,0128)
    public static let tableTopVerticalPosition = Tag(group: 0x300A, element: 0x0128)
    
    /// Table Top Longitudinal Position (300A,0129)
    public static let tableTopLongitudinalPosition = Tag(group: 0x300A, element: 0x0129)
    
    /// Table Top Lateral Position (300A,012A)
    public static let tableTopLateralPosition = Tag(group: 0x300A, element: 0x012A)
    
    /// Isocenter Position (300A,012C)
    public static let isocenterPosition = Tag(group: 0x300A, element: 0x012C)
    
    /// Surface Entry Point (300A,012E)
    public static let surfaceEntryPoint = Tag(group: 0x300A, element: 0x012E)
    
    /// Source to Surface Distance (300A,0130)
    public static let sourceToSurfaceDistance = Tag(group: 0x300A, element: 0x0130)
    
    /// Beam Limiting Device Position Sequence (300A,011A)
    public static let beamLimitingDevicePositionSequence = Tag(group: 0x300A, element: 0x011A)
    
    /// RT Beam Limiting Device Type (300A,00B8)
    public static let rtBeamLimitingDeviceType = Tag(group: 0x300A, element: 0x00B8)
    
    /// Leaf/Jaw Positions (300A,011C)
    public static let leafJawPositions = Tag(group: 0x300A, element: 0x011C)
    
    /// Nominal Beam Energy (300A,0114)
    public static let nominalBeamEnergy = Tag(group: 0x300A, element: 0x0114)
    
    /// Dose Rate Set (300A,0115)
    public static let doseRateSet = Tag(group: 0x300A, element: 0x0115)
    
    /// Final Cumulative Meterset Weight (300A,010E)
    public static let finalCumulativeMetersetWeight = Tag(group: 0x300A, element: 0x010E)
    
    /// Referenced Structure Set Sequence (300C,0060)
    public static let referencedStructureSetSequence = Tag(group: 0x300C, element: 0x0060)
    
    /// Referenced Dose Sequence (300C,0080)
    public static let referencedDoseSequence = Tag(group: 0x300C, element: 0x0080)
    
    /// Referenced Beam Number (300C,0006)
    public static let referencedBeamNumber = Tag(group: 0x300C, element: 0x0006)
    
    /// Number of Brachy Application Setups (300A,00A0)
    public static let numberOfBrachyApplicationSetups = Tag(group: 0x300A, element: 0x00A0)
    
    /// Application Setup Sequence (300A,0230) — PS3.6 keyword ApplicationSetupSequence
    public static let applicationSetupSequence = Tag(group: 0x300A, element: 0x0230)

    @available(*, deprecated, renamed: "applicationSetupSequence", message: "PS3.6 keyword is ApplicationSetupSequence")
    public static var brachyApplicationSetupSequence: Tag { .applicationSetupSequence }
    
    /// Application Setup Type (300A,0232)
    public static let applicationSetupType = Tag(group: 0x300A, element: 0x0232)
    
    /// Application Setup Number (300A,0234)
    public static let applicationSetupNumber = Tag(group: 0x300A, element: 0x0234)
    
    // MARK: - RT Dose Module (PS3.3 C.8.8.3)
    // Group 3004
    
    /// DVH Sequence (3004,0050)
    public static let dvhSequence = Tag(group: 0x3004, element: 0x0050)
    
    /// DVH Type (3004,0001)
    public static let dvhType = Tag(group: 0x3004, element: 0x0001)
    
    /// Dose Units (3004,0002)
    public static let doseUnits = Tag(group: 0x3004, element: 0x0002)
    
    /// Dose Type (3004,0004)
    public static let doseType = Tag(group: 0x3004, element: 0x0004)
    
    /// Dose Comment (3004,0006)
    public static let doseComment = Tag(group: 0x3004, element: 0x0006)
    
    /// Dose Summation Type (3004,000A)
    public static let doseSummationType = Tag(group: 0x3004, element: 0x000A)
    
    /// Grid Frame Offset Vector (3004,000C)
    public static let gridFrameOffsetVector = Tag(group: 0x3004, element: 0x000C)
    
    /// Dose Grid Scaling (3004,000E)
    public static let doseGridScaling = Tag(group: 0x3004, element: 0x000E)
    
    /// Tissue Heterogeneity Correction (3004,0014)
    public static let tissueHeterogeneityCorrection = Tag(group: 0x3004, element: 0x0014)
    
    /// Referenced RT Plan Sequence (300C,0002)
    public static let referencedRTPlanSequence = Tag(group: 0x300C, element: 0x0002)
    
    /// Referenced Fraction Group Number (300C,0022)
    public static let referencedFractionGroupNumber = Tag(group: 0x300C, element: 0x0022)
    
    /// DVH Normalization Point (3004,0040)
    public static let dvhNormalizationPoint = Tag(group: 0x3004, element: 0x0040)
    
    /// DVH Normalization Dose Value (3004,0042)
    public static let dvhNormalizationDoseValue = Tag(group: 0x3004, element: 0x0042)
    
    /// DVH Volume Units (3004,0054) — CS, VM 1 (PS3.6 2026a Table 6-1)
    public static let dvhVolumeUnits = Tag(group: 0x3004, element: 0x0054)
    
    /// DVH Data (3004,0058)
    public static let dvhData = Tag(group: 0x3004, element: 0x0058)
    
    /// DVH Minimum Dose (3004,0070)
    public static let dvhMinimumDose = Tag(group: 0x3004, element: 0x0070)
    
    /// DVH Maximum Dose (3004,0072)
    public static let dvhMaximumDose = Tag(group: 0x3004, element: 0x0072)
    
    /// DVH Mean Dose (3004,0074)
    public static let dvhMeanDose = Tag(group: 0x3004, element: 0x0074)
}
