// NEMA-verified: 2026a, checked 2026-09-29 — Dose Units, Dose Type, Dose Summation Type, Tissue Heterogeneity Correction per PS3.3 2026a Table C.8-39; DVH Type, DVH Volume Units per Table C.8-40
//
// RTDose.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// DICOM RT Dose IOD
///
/// An RT Dose object contains a 3D dose grid representing the calculated or measured
/// radiation dose distribution in a patient. Dose values are stored as 16-bit or 32-bit
/// unsigned integers and must be scaled by the Dose Grid Scaling factor.
///
/// Reference: PS3.3 A.18 - RT Dose IOD
/// Reference: PS3.3 C.8.8.3 - RT Dose Module
public struct RTDose: Sendable {
    
    // MARK: - Dose Identification
    
    /// SOP Instance UID
    public let sopInstanceUID: String
    
    /// SOP Class UID (should be RT Dose Storage: 1.2.840.10008.5.1.4.1.1.481.2)
    public let sopClassUID: String
    
    /// Dose Comment (3004,0006)
    public let comment: String?

    /// Dose Summation Type (3004,000A) as written in the data set.
    /// Standard terms: see ``DoseSummationType`` (PS3.3 Table C.8-39).
    public let summationType: String?

    /// Dose Summation Type (3004,000A) as a standard term, `nil` when absent or non-standard.
    public var doseSummationType: DoseSummationType? {
        summationType.flatMap(DoseSummationType.init(rawValue:))
    }

    /// Dose Type (3004,0004) as written in the data set.
    /// Standard terms: see ``DoseType`` (PS3.3 Table C.8-39).
    public let type: String?

    /// Dose Type (3004,0004) as a standard term, `nil` when absent or non-standard.
    public var doseType: DoseType? {
        type.flatMap(DoseType.init(rawValue:))
    }

    /// Dose Units (3004,0002) as written in the data set.
    /// Standard terms: see ``DoseUnits`` (PS3.3 Table C.8-39).
    public let units: String?

    /// Dose Units (3004,0002) as a standard term, `nil` when absent or non-standard.
    public var doseUnits: DoseUnits? {
        units.flatMap(DoseUnits.init(rawValue:))
    }
    
    // MARK: - Referenced Objects
    
    /// Referenced RT Plan SOP Instance UID
    public let referencedRTPlanUID: String?
    
    /// Referenced Structure Set SOP Instance UID
    public let referencedStructureSetUID: String?
    
    /// Referenced Fraction Group Number
    public let referencedFractionGroupNumber: Int?
    
    /// Referenced Beam Number
    public let referencedBeamNumber: Int?
    
    // MARK: - Dose Grid Geometry
    
    /// Frame of Reference UID
    public let frameOfReferenceUID: String?
    
    /// Image Position (Patient) - origin of dose grid (x, y, z in mm)
    public let imagePosition: Point3D?
    
    /// Image Orientation (Patient) - direction cosines
    public let imageOrientation: [Double]?
    
    /// Grid Frame Offset Vector (mm) - z-positions of slices
    public let gridFrameOffsetVector: [Double]?
    
    /// Pixel Spacing (mm) - [row spacing, column spacing]
    public let pixelSpacing: (row: Double, column: Double)?
    
    /// Slice Thickness (mm)
    public let sliceThickness: Double?
    
    // MARK: - Dose Grid Dimensions
    
    /// Number of Rows in dose grid
    public let rows: Int
    
    /// Number of Columns in dose grid
    public let columns: Int
    
    /// Number of Frames (slices)
    public let numberOfFrames: Int
    
    /// Bits Allocated (16 or 32)
    public let bitsAllocated: Int
    
    /// Bits Stored
    public let bitsStored: Int
    
    /// High Bit
    public let highBit: Int
    
    // MARK: - Dose Scaling
    
    /// Dose Grid Scaling
    /// Multiply raw pixel values by this factor to get dose in units specified by Dose Units
    public let doseGridScaling: Double
    
    /// Tissue Heterogeneity Correction (3004,0014) as written in the data set (VM 1-3, backslash-separated).
    /// Standard terms: see ``TissueHeterogeneityCorrection`` (PS3.3 Table C.8-39).
    public let tissueHeterogeneityCorrection: String?

    /// Tissue Heterogeneity Correction (3004,0014) values as standard terms; non-standard values are dropped.
    public var tissueHeterogeneityCorrections: [TissueHeterogeneityCorrection] {
        guard let raw = tissueHeterogeneityCorrection else { return [] }
        return raw.split(separator: "\\").compactMap {
            TissueHeterogeneityCorrection(rawValue: $0.trimmingCharacters(in: .whitespaces))
        }
    }
    
    // MARK: - Dose Statistics
    
    /// Maximum Dose (in dose units, after scaling)
    public let maximumDose: Double?
    
    /// Minimum Dose (in dose units, after scaling)
    public let minimumDose: Double?
    
    /// Mean Dose (in dose units, after scaling)
    public let meanDose: Double?
    
    // MARK: - DVH Data
    
    /// DVH (Dose Volume Histogram) data
    public let dvhData: [DVHData]
    
    // MARK: - Dose Grid Data
    
    /// Raw dose grid pixel data (before scaling)
    /// 3D array: [frame][row][column]
    /// Values must be multiplied by doseGridScaling to get actual dose
    public let pixelData: [[[UInt16]]]?
    
    /// Raw dose grid pixel data (32-bit, before scaling)
    /// 3D array: [frame][row][column]
    /// Values must be multiplied by doseGridScaling to get actual dose
    public let pixelData32: [[[UInt32]]]?
    
    // MARK: - Initialization
    
    /// Initialize an RT Dose
    public init(
        sopInstanceUID: String,
        sopClassUID: String = "1.2.840.10008.5.1.4.1.1.481.2",
        comment: String? = nil,
        summationType: String? = nil,
        type: String? = nil,
        units: String? = nil,
        referencedRTPlanUID: String? = nil,
        referencedStructureSetUID: String? = nil,
        referencedFractionGroupNumber: Int? = nil,
        referencedBeamNumber: Int? = nil,
        frameOfReferenceUID: String? = nil,
        imagePosition: Point3D? = nil,
        imageOrientation: [Double]? = nil,
        gridFrameOffsetVector: [Double]? = nil,
        pixelSpacing: (row: Double, column: Double)? = nil,
        sliceThickness: Double? = nil,
        rows: Int,
        columns: Int,
        numberOfFrames: Int,
        bitsAllocated: Int = 16,
        bitsStored: Int = 16,
        highBit: Int = 15,
        doseGridScaling: Double,
        tissueHeterogeneityCorrection: String? = nil,
        maximumDose: Double? = nil,
        minimumDose: Double? = nil,
        meanDose: Double? = nil,
        dvhData: [DVHData] = [],
        pixelData: [[[UInt16]]]? = nil,
        pixelData32: [[[UInt32]]]? = nil
    ) {
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.comment = comment
        self.summationType = summationType
        self.type = type
        self.units = units
        self.referencedRTPlanUID = referencedRTPlanUID
        self.referencedStructureSetUID = referencedStructureSetUID
        self.referencedFractionGroupNumber = referencedFractionGroupNumber
        self.referencedBeamNumber = referencedBeamNumber
        self.frameOfReferenceUID = frameOfReferenceUID
        self.imagePosition = imagePosition
        self.imageOrientation = imageOrientation
        self.gridFrameOffsetVector = gridFrameOffsetVector
        self.pixelSpacing = pixelSpacing
        self.sliceThickness = sliceThickness
        self.rows = rows
        self.columns = columns
        self.numberOfFrames = numberOfFrames
        self.bitsAllocated = bitsAllocated
        self.bitsStored = bitsStored
        self.highBit = highBit
        self.doseGridScaling = doseGridScaling
        self.tissueHeterogeneityCorrection = tissueHeterogeneityCorrection
        self.maximumDose = maximumDose
        self.minimumDose = minimumDose
        self.meanDose = meanDose
        self.dvhData = dvhData
        self.pixelData = pixelData
        self.pixelData32 = pixelData32
    }
    
    // MARK: - Dose Value Access
    
    /// Get the scaled dose value at a specific grid position
    /// - Parameters:
    ///   - frame: Frame (slice) index
    ///   - row: Row index
    ///   - column: Column index
    /// - Returns: Dose value in units specified by Dose Units, or nil if position is invalid
    public func doseValue(frame: Int, row: Int, column: Int) -> Double? {
        guard frame >= 0 && frame < numberOfFrames,
              row >= 0 && row < rows,
              column >= 0 && column < columns else {
            return nil
        }
        
        if let pixelData = pixelData {
            return Double(pixelData[frame][row][column]) * doseGridScaling
        } else if let pixelData32 = pixelData32 {
            return Double(pixelData32[frame][row][column]) * doseGridScaling
        }
        
        return nil
    }
    
    /// Get the dose value at a physical position in patient coordinate system
    /// - Parameter position: 3D position in patient coordinates (mm)
    /// - Returns: Interpolated dose value, or nil if position is outside grid
    public func doseValue(at position: Point3D) -> Double? {
        guard let imagePosition = imagePosition,
              let pixelSpacing = pixelSpacing,
              let gridFrameOffsetVector = gridFrameOffsetVector else {
            return nil
        }
        
        // Convert physical position to grid indices
        // This is a simplified version - proper implementation would use image orientation
        let colIndex = (position.x - imagePosition.x) / pixelSpacing.column
        let rowIndex = (position.y - imagePosition.y) / pixelSpacing.row
        
        // Find frame index based on z position
        var frameIndex = 0
        for (index, offset) in gridFrameOffsetVector.enumerated() {
            let frameZ = imagePosition.z + offset
            if abs(position.z - frameZ) < abs(position.z - (imagePosition.z + (frameIndex < gridFrameOffsetVector.count ? gridFrameOffsetVector[frameIndex] : 0))) {
                frameIndex = index
            }
        }
        
        // Check bounds and get nearest voxel value
        let col = Int(round(colIndex))
        let row = Int(round(rowIndex))
        
        return doseValue(frame: frameIndex, row: row, column: col)
    }
}

// MARK: - Dose Terms

/// Dose Units (3004,0002) Enumerated Values.
///
/// In the RT Dose Module the values are GY, RELATIVE and CODED (Table C.8-39); in the
/// RT DVH Module only GY and RELATIVE are enumerated (Table C.8-40).
///
/// Reference: PS3.3 C.8.8.3 RT Dose Module, Table C.8-39; C.8.8.4 RT DVH Module, Table C.8-40
public enum DoseUnits: String, Sendable, Hashable, CaseIterable {
    /// Gray
    case gray = "GY"

    /// dose relative to implicit reference value (RT Dose) or to DVH Normalization Dose Value (3004,0042) (RT DVH)
    case relative = "RELATIVE"

    /// unit described by code in Dose Units Code Sequence (3004,0020) (RT Dose Module only)
    case coded = "CODED"
}

/// Dose Type (3004,0004) Defined Terms.
///
/// In the RT Dose Module the terms are PHYSICAL, EFFECTIVE, ERROR and CODED (Table C.8-39); in the
/// RT DVH Module only PHYSICAL, EFFECTIVE and ERROR are listed (Table C.8-40).
///
/// Reference: PS3.3 C.8.8.3 RT Dose Module, Table C.8-39 and C.8.8.3.6; C.8.8.4 RT DVH Module, Table C.8-40
public enum DoseType: String, Sendable, Hashable, CaseIterable {
    /// physical dose
    case physical = "PHYSICAL"

    /// physical dose after correction for biological effect using user-defined modeling technique
    case effective = "EFFECTIVE"

    /// difference between desired and planned dose
    case error = "ERROR"

    /// described by code in RT Dose Interpreted Type Code Sequence (3004,0021) (RT Dose Module only)
    case coded = "CODED"
}

/// Dose Summation Type (3004,000A) Defined Terms.
///
/// Reference: PS3.3 C.8.8.3 RT Dose Module, Table C.8-39
public enum DoseSummationType: String, Sendable, Hashable, CaseIterable {
    /// dose calculated for entire delivery of all fraction groups of RT Plan
    case plan = "PLAN"

    /// dose calculated for entire delivery of 2 or more RT Plans
    case multiPlan = "MULTI_PLAN"

    /// dose calculated with respect to plan overview parameters
    case planOverview = "PLAN_OVERVIEW"

    /// dose calculated for entire delivery of a single Fraction Group within RT Plan
    case fraction = "FRACTION"

    /// dose calculated for entire delivery of one or more Beams within RT Plan
    case beam = "BEAM"

    /// dose calculated for entire delivery of one or more Brachy Application Setups within RT Plan
    case brachy = "BRACHY"

    /// dose calculated for a single session ("fraction") of a single Fraction Group within RT Plan
    case fractionSession = "FRACTION_SESSION"

    /// dose calculated for a single session ("fraction") of one or more Beams within RT Plan
    case beamSession = "BEAM_SESSION"

    /// dose calculated for a single session ("fraction") of one or more Brachy Application Setups within RT Plan
    case brachySession = "BRACHY_SESSION"

    /// dose calculated for one or more Control Points within a Beam for a single fraction
    case controlPoint = "CONTROL_POINT"

    /// dose calculated for RT Beams Treatment Record
    case record = "RECORD"
}

/// Tissue Heterogeneity Correction (3004,0014) Defined Terms.
///
/// Reference: PS3.3 C.8.8.3 RT Dose Module, Table C.8-39
public enum TissueHeterogeneityCorrection: String, Sendable, Hashable, CaseIterable {
    /// image data
    case image = "IMAGE"

    /// one or more ROI densities override image or water values where they exist
    case roiOverride = "ROI_OVERRIDE"

    /// entire volume treated as water equivalent
    case water = "WATER"
}

/// DVH Type (3004,0001) Defined Terms.
///
/// Reference: PS3.3 C.8.8.4 RT DVH Module, Table C.8-40
public enum DVHType: String, Sendable, Hashable, CaseIterable {
    /// differential dose-volume histogram
    case differential = "DIFFERENTIAL"

    /// cumulative dose-volume histogram
    case cumulative = "CUMULATIVE"

    /// natural dose volume histogram
    case natural = "NATURAL"
}

/// DVH Volume Units (3004,0054) Defined Terms.
///
/// Reference: PS3.3 C.8.8.4 RT DVH Module, Table C.8-40 and C.8.8.4.3
public enum DVHVolumeUnits: String, Sendable, Hashable, CaseIterable {
    /// cubic centimeters
    case cubicCentimeters = "CM3"

    /// percent
    case percent = "PERCENT"

    /// volume per u with u(dose) = dose^-3/2 (Anderson, Medical Physics 13(6), 1986)
    case perU = "PER_U"
}

// MARK: - DVHData

/// DVH (Dose Volume Histogram) Data
///
/// Represents a dose-volume histogram for a specific structure.
///
/// Reference: PS3.3 C.8.8.4 - RT DVH Module, Table C.8-40
public struct DVHData: Sendable {

    /// DVH Type (3004,0001) as written in the data set. Standard terms: see ``DVHType``.
    public let type: String?

    /// DVH Type (3004,0001) as a standard term, `nil` when absent or non-standard.
    public var dvhType: DVHType? {
        type.flatMap(DVHType.init(rawValue:))
    }

    /// Dose Units (3004,0002) as written in the data set. Standard terms: GY, RELATIVE (see ``DoseUnits``).
    public let doseUnits: String?

    /// Dose Units (3004,0002) as a standard term, `nil` when absent or non-standard.
    public var doseUnitsTerm: DoseUnits? {
        doseUnits.flatMap(DoseUnits.init(rawValue:))
    }

    /// Dose Type (3004,0004) as written in the data set. Standard terms: PHYSICAL, EFFECTIVE, ERROR (see ``DoseType``).
    public let doseType: String?

    /// Dose Type (3004,0004) as a standard term, `nil` when absent or non-standard.
    public var doseTypeTerm: DoseType? {
        doseType.flatMap(DoseType.init(rawValue:))
    }

    /// DVH Volume Units (3004,0054) as written in the data set. Standard terms: see ``DVHVolumeUnits``.
    public let volumeUnits: String?

    /// DVH Volume Units (3004,0054) as a standard term, `nil` when absent or non-standard.
    public var dvhVolumeUnits: DVHVolumeUnits? {
        volumeUnits.flatMap(DVHVolumeUnits.init(rawValue:))
    }
    
    /// Referenced ROI Number
    public let referencedROINumber: Int?
    
    /// DVH Normalization Point (x, y, z in mm)
    public let normalizationPoint: Point3D?
    
    /// DVH Normalization Dose Value
    public let normalizationDoseValue: Double?
    
    /// DVH Minimum Dose
    public let minimumDose: Double?
    
    /// DVH Maximum Dose
    public let maximumDose: Double?
    
    /// DVH Mean Dose
    public let meanDose: Double?
    
    /// DVH Data array (dose-volume pairs)
    /// Each element represents [dose, volume] pair
    public let data: [(dose: Double, volume: Double)]
    
    /// Initialize DVH Data
    public init(
        type: String? = nil,
        doseUnits: String? = nil,
        doseType: String? = nil,
        volumeUnits: String? = nil,
        referencedROINumber: Int? = nil,
        normalizationPoint: Point3D? = nil,
        normalizationDoseValue: Double? = nil,
        minimumDose: Double? = nil,
        maximumDose: Double? = nil,
        meanDose: Double? = nil,
        data: [(dose: Double, volume: Double)] = []
    ) {
        self.type = type
        self.doseUnits = doseUnits
        self.doseType = doseType
        self.volumeUnits = volumeUnits
        self.referencedROINumber = referencedROINumber
        self.normalizationPoint = normalizationPoint
        self.normalizationDoseValue = normalizationDoseValue
        self.minimumDose = minimumDose
        self.maximumDose = maximumDose
        self.meanDose = meanDose
        self.data = data
    }
}
