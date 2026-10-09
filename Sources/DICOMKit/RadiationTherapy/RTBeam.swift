// NEMA-verified: 2026a, checked 2026-09-29 — Beam Type, Radiation Type, Primary Dosimeter Unit, High-Dose Technique Type, RT Beam Limiting Device Type, Treatment Delivery Type, Wedge Type, Wedge Position and rotation directions per PS3.3 2026a Table C.8-50; tags per PS3.6 2026a Table 6-1
//
// RTBeam.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// RT Beam
///
/// Defines an external beam radiation therapy beam with control points that
/// specify the beam state at different positions during treatment delivery.
///
/// Reference: PS3.3 C.8.8.14 - RT Beams Module, Table C.8-50
public struct RTBeam: Sendable, Identifiable {

    // MARK: - Beam Identification

    /// Beam Number (unique within plan)
    public let number: Int

    /// Beam Name
    public let name: String?

    /// Beam Description
    public let description: String?

    /// Beam Type (300A,00C4) as written in the data set.
    /// Standard terms: STATIC, DYNAMIC (see ``BeamType``, PS3.3 Table C.8-50).
    public let type: String?

    /// Beam Type (300A,00C4) as a standard term, `nil` when absent or non-standard.
    public var beamType: BeamType? {
        type.flatMap(BeamType.init(rawValue:))
    }

    /// Radiation Type (300A,00C6) as written in the data set.
    /// Standard terms: PHOTON, ELECTRON, NEUTRON, PROTON (see ``RadiationType``, PS3.3 Table C.8-50).
    public let radiationType: String?

    /// Radiation Type (300A,00C6) as a standard term, `nil` when absent or non-standard.
    public var radiationTypeTerm: RadiationType? {
        radiationType.flatMap(RadiationType.init(rawValue:))
    }

    // MARK: - Machine Parameters

    /// Treatment Machine Name
    public let treatmentMachineName: String?

    /// Manufacturer
    public let manufacturer: String?

    /// Institution Name
    public let institutionName: String?

    /// Primary Dosimeter Unit (300A,00B3) as written in the data set.
    /// Standard terms: MU, MINUTE (see ``PrimaryDosimeterUnit``, PS3.3 Table C.8-50).
    public let primaryDosimeterUnit: String?

    /// Primary Dosimeter Unit (300A,00B3) as a standard term, `nil` when absent or non-standard.
    public var primaryDosimeterUnitTerm: PrimaryDosimeterUnit? {
        primaryDosimeterUnit.flatMap(PrimaryDosimeterUnit.init(rawValue:))
    }
    
    /// Source-Axis Distance (SAD) in mm
    public let sourceAxisDistance: Double?
    
    // MARK: - Beam Delivery
    
    /// Number of Control Points
    public var numberOfControlPoints: Int {
        controlPoints.count
    }
    
    /// Control Points defining beam state at different positions
    public let controlPoints: [BeamControlPoint]
    
    /// Final Cumulative Meterset Weight (typically 1.0)
    public let finalCumulativeMetersetWeight: Double?
    
    /// Number of Wedges
    public let numberOfWedges: Int?
    
    /// Number of Compensators
    public let numberOfCompensators: Int?
    
    /// Number of Boli
    public let numberOfBoli: Int?
    
    /// Number of Blocks
    public let numberOfBlocks: Int?
    
    // MARK: - Treatment Delivery
    
    /// Treatment Delivery Type (300A,00CE) as written in the data set.
    /// Standard terms: TREATMENT, OPEN_PORTFILM, TRMT_PORTFILM, CONTINUATION, SETUP
    /// (see ``TreatmentDeliveryType``, PS3.3 Table C.8-50).
    public let treatmentDeliveryType: String?

    /// Treatment Delivery Type (300A,00CE) as a standard term, `nil` when absent or non-standard.
    public var treatmentDeliveryTypeTerm: TreatmentDeliveryType? {
        treatmentDeliveryType.flatMap(TreatmentDeliveryType.init(rawValue:))
    }

    /// High-Dose Technique Type (300A,00C7) as written in the data set.
    /// Standard terms: TBI, HDR (see ``HighDoseTechniqueType``, PS3.3 Table C.8-50).
    public let highDoseTechniqueType: String?

    /// High-Dose Technique Type (300A,00C7) as a standard term, `nil` when absent or non-standard.
    public var highDoseTechniqueTypeTerm: HighDoseTechniqueType? {
        highDoseTechniqueType.flatMap(HighDoseTechniqueType.init(rawValue:))
    }
    
    /// Referenced Patient Setup Number
    public let referencedPatientSetupNumber: Int?
    
    /// Referenced Tolerance Table Number
    public let referencedToleranceTableNumber: Int?
    
    // MARK: - Identifiable Conformance
    
    public var id: Int { number }
    
    // MARK: - Initialization
    
    /// Initialize an RT Beam
    public init(
        number: Int,
        name: String? = nil,
        description: String? = nil,
        type: String? = nil,
        radiationType: String? = nil,
        treatmentMachineName: String? = nil,
        manufacturer: String? = nil,
        institutionName: String? = nil,
        primaryDosimeterUnit: String? = nil,
        sourceAxisDistance: Double? = nil,
        controlPoints: [BeamControlPoint] = [],
        finalCumulativeMetersetWeight: Double? = nil,
        numberOfWedges: Int? = nil,
        numberOfCompensators: Int? = nil,
        numberOfBoli: Int? = nil,
        numberOfBlocks: Int? = nil,
        treatmentDeliveryType: String? = nil,
        highDoseTechniqueType: String? = nil,
        referencedPatientSetupNumber: Int? = nil,
        referencedToleranceTableNumber: Int? = nil
    ) {
        self.number = number
        self.name = name
        self.description = description
        self.type = type
        self.radiationType = radiationType
        self.treatmentMachineName = treatmentMachineName
        self.manufacturer = manufacturer
        self.institutionName = institutionName
        self.primaryDosimeterUnit = primaryDosimeterUnit
        self.sourceAxisDistance = sourceAxisDistance
        self.controlPoints = controlPoints
        self.finalCumulativeMetersetWeight = finalCumulativeMetersetWeight
        self.numberOfWedges = numberOfWedges
        self.numberOfCompensators = numberOfCompensators
        self.numberOfBoli = numberOfBoli
        self.numberOfBlocks = numberOfBlocks
        self.treatmentDeliveryType = treatmentDeliveryType
        self.highDoseTechniqueType = highDoseTechniqueType
        self.referencedPatientSetupNumber = referencedPatientSetupNumber
        self.referencedToleranceTableNumber = referencedToleranceTableNumber
    }
}

// MARK: - Beam Terms

/// Beam Type (300A,00C4) Enumerated Values.
///
/// Reference: PS3.3 C.8.8.14 RT Beams Module, Table C.8-50
public enum BeamType: String, Sendable, Hashable, CaseIterable {
    /// All Control Point Sequence (300A,0111) Attributes remain unchanged between consecutive
    /// pairs of control points with changing Cumulative Meterset Weight (300A,0134).
    case `static` = "STATIC"

    /// One or more Control Point Sequence (300A,0111) Attributes change between one or more
    /// consecutive pairs of control points with changing Cumulative Meterset Weight (300A,0134).
    case dynamic = "DYNAMIC"
}

/// Radiation Type (300A,00C6) Defined Terms.
///
/// Reference: PS3.3 C.8.8.14 RT Beams Module, Table C.8-50
public enum RadiationType: String, Sendable, Hashable, CaseIterable {
    case photon = "PHOTON"
    case electron = "ELECTRON"
    case neutron = "NEUTRON"
    case proton = "PROTON"
}

/// Primary Dosimeter Unit (300A,00B3) Enumerated Values.
///
/// Reference: PS3.3 C.8.8.14 RT Beams Module, Table C.8-50 and C.8.8.14.1
public enum PrimaryDosimeterUnit: String, Sendable, Hashable, CaseIterable {
    /// Monitor Unit
    case monitorUnit = "MU"

    /// minute
    case minute = "MINUTE"
}

/// High-Dose Technique Type (300A,00C7) Defined Terms.
///
/// Reference: PS3.3 C.8.8.14 RT Beams Module, Table C.8-50
public enum HighDoseTechniqueType: String, Sendable, Hashable, CaseIterable {
    /// Total Body Irradiation
    case totalBodyIrradiation = "TBI"

    /// High Dose Rate
    case highDoseRate = "HDR"
}

/// Treatment Delivery Type (300A,00CE) Defined Terms.
///
/// Reference: PS3.3 C.8.8.14 RT Beams Module, Table C.8-50
public enum TreatmentDeliveryType: String, Sendable, Hashable, CaseIterable {
    /// normal patient treatment
    case treatment = "TREATMENT"

    /// portal image acquisition with open field
    case openPortfilm = "OPEN_PORTFILM"

    /// portal image acquisition with treatment port
    case treatmentPortfilm = "TRMT_PORTFILM"

    /// continuation of interrupted treatment
    case continuation = "CONTINUATION"

    /// no treatment beam is applied for this RT Beam; specifies gantry, couch and other machine
    /// positions where X-Ray set-up images or measurements are to be taken
    case setup = "SETUP"
}

/// RT Beam Limiting Device Type (300A,00B8) Defined Terms.
///
/// Reference: PS3.3 C.8.8.14 RT Beams Module, Table C.8-50
public enum RTBeamLimitingDeviceType: String, Sendable, Hashable, CaseIterable {
    /// symmetric jaw pair in IEC X direction
    case x = "X"

    /// symmetric jaw pair in IEC Y direction
    case y = "Y"

    /// asymmetric jaw pair in IEC X direction
    case asymmetricX = "ASYMX"

    /// asymmetric jaw pair in IEC Y direction
    case asymmetricY = "ASYMY"

    /// single layer multileaf collimator in IEC X direction
    case mlcX = "MLCX"

    /// single layer multileaf collimator in IEC Y direction
    case mlcY = "MLCY"
}

/// Rotation direction Enumerated Values shared by Gantry Rotation Direction (300A,011F),
/// Gantry Pitch Rotation Direction (300A,014C), Beam Limiting Device Rotation Direction (300A,0121),
/// Patient Support Rotation Direction (300A,0123), Table Top Eccentric Rotation Direction (300A,0126),
/// Table Top Pitch Rotation Direction (300A,0142) and Table Top Roll Rotation Direction (300A,0146).
///
/// Reference: PS3.3 C.8.8.14 RT Beams Module, Table C.8-50 and C.8.8.14.8
public enum RotationDirection: String, Sendable, Hashable, CaseIterable {
    /// clockwise
    case clockwise = "CW"

    /// counter-clockwise
    case counterClockwise = "CC"

    /// no rotation
    case none = "NONE"
}

/// Wedge Type (300A,00D3) Defined Terms.
///
/// Reference: PS3.3 C.8.8.14 RT Beams Module, Table C.8-50
public enum WedgeType: String, Sendable, Hashable, CaseIterable {
    /// standard (static) wedge
    case standard = "STANDARD"

    /// moving beam limiting device (collimator) jaw simulating wedge
    case dynamic = "DYNAMIC"

    /// single wedge that can be removed from beam remotely
    case motorized = "MOTORIZED"
}

/// Wedge Position (300A,0118) Enumerated Values.
///
/// Reference: PS3.3 C.8.8.14 RT Beams Module, Table C.8-50
public enum WedgePlacement: String, Sendable, Hashable, CaseIterable {
    case `in` = "IN"
    case out = "OUT"
}

// MARK: - BeamControlPoint

/// Beam Control Point
///
/// Defines the beam state at a specific position during treatment delivery.
/// Control points specify gantry angle, collimator angle, jaw positions, MLC positions, etc.
///
/// Reference: PS3.3 C.8.8.14 - RT Beams Module, Table C.8-50 (Control Point Sequence (300A,0111))
public struct BeamControlPoint: Sendable {

    /// Control Point Index
    public let index: Int

    /// Cumulative Meterset Weight (0.0 to 1.0)
    public let cumulativeMetersetWeight: Double?

    // MARK: - Geometric Parameters

    /// Gantry Angle (degrees, 0-360)
    public let gantryAngle: Double?

    /// Gantry Rotation Direction (300A,011F) as written; standard values CW, CC, NONE (see ``RotationDirection``)
    public let gantryRotationDirection: String?

    /// Gantry Rotation Direction (300A,011F) as a standard value, `nil` when absent or non-standard.
    public var gantryRotation: RotationDirection? {
        gantryRotationDirection.flatMap(RotationDirection.init(rawValue:))
    }

    /// Beam Limiting Device Angle (collimator angle, degrees)
    public let beamLimitingDeviceAngle: Double?

    /// Beam Limiting Device Rotation Direction (300A,0121) as written; standard values CW, CC, NONE (see ``RotationDirection``)
    public let beamLimitingDeviceRotationDirection: String?

    /// Beam Limiting Device Rotation Direction (300A,0121) as a standard value, `nil` when absent or non-standard.
    public var beamLimitingDeviceRotation: RotationDirection? {
        beamLimitingDeviceRotationDirection.flatMap(RotationDirection.init(rawValue:))
    }

    /// Patient Support Angle (couch angle, degrees)
    public let patientSupportAngle: Double?

    /// Patient Support Rotation Direction (300A,0123) as written; standard values CW, CC, NONE (see ``RotationDirection``)
    public let patientSupportRotationDirection: String?

    /// Patient Support Rotation Direction (300A,0123) as a standard value, `nil` when absent or non-standard.
    public var patientSupportRotation: RotationDirection? {
        patientSupportRotationDirection.flatMap(RotationDirection.init(rawValue:))
    }
    
    /// Table Top Vertical Position (mm)
    public let tableTopVerticalPosition: Double?
    
    /// Table Top Longitudinal Position (mm)
    public let tableTopLongitudinalPosition: Double?
    
    /// Table Top Lateral Position (mm)
    public let tableTopLateralPosition: Double?
    
    // MARK: - Isocenter Position
    
    /// Isocenter Position (x, y, z in mm)
    public let isocenterPosition: Point3D?
    
    /// Surface Entry Point (x, y, z in mm)
    public let surfaceEntryPoint: Point3D?
    
    // MARK: - Source Position
    
    /// Source to Surface Distance (SSD, mm)
    public let sourceToSurfaceDistance: Double?
    
    /// Source to External Contour Distance (mm)
    public let sourceToExternalContourDistance: Double?
    
    // MARK: - Beam Limiting Devices
    
    /// Beam Limiting Device Positions (jaws, MLC leaves)
    public let beamLimitingDevicePositions: [BeamLimitingDevicePosition]
    
    // MARK: - Dose Parameters
    
    /// Nominal Beam Energy (MeV)
    public let nominalBeamEnergy: Double?
    
    /// Dose Rate Set (MU/min or Gy/min)
    public let doseRateSet: Double?
    
    // MARK: - Wedge and Compensator
    
    /// Wedge Position Sequence
    public let wedgePositions: [WedgePosition]
    
    // MARK: - Scanning Spot Parameters (for proton/particle therapy)
    
    /// Scan Spot Meterset Weights
    public let scanSpotMetersetWeights: [Double]
    
    /// Scan Spot Position Map (x, y positions)
    public let scanSpotPositionMap: [(x: Float, y: Float)]
    
    /// Scan Spot Tune ID
    public let scanSpotTuneID: String?
    
    // MARK: - Initialization
    
    /// Initialize a Beam Control Point
    public init(
        index: Int,
        cumulativeMetersetWeight: Double? = nil,
        gantryAngle: Double? = nil,
        gantryRotationDirection: String? = nil,
        beamLimitingDeviceAngle: Double? = nil,
        beamLimitingDeviceRotationDirection: String? = nil,
        patientSupportAngle: Double? = nil,
        patientSupportRotationDirection: String? = nil,
        tableTopVerticalPosition: Double? = nil,
        tableTopLongitudinalPosition: Double? = nil,
        tableTopLateralPosition: Double? = nil,
        isocenterPosition: Point3D? = nil,
        surfaceEntryPoint: Point3D? = nil,
        sourceToSurfaceDistance: Double? = nil,
        sourceToExternalContourDistance: Double? = nil,
        beamLimitingDevicePositions: [BeamLimitingDevicePosition] = [],
        nominalBeamEnergy: Double? = nil,
        doseRateSet: Double? = nil,
        wedgePositions: [WedgePosition] = [],
        scanSpotMetersetWeights: [Double] = [],
        scanSpotPositionMap: [(x: Float, y: Float)] = [],
        scanSpotTuneID: String? = nil
    ) {
        self.index = index
        self.cumulativeMetersetWeight = cumulativeMetersetWeight
        self.gantryAngle = gantryAngle
        self.gantryRotationDirection = gantryRotationDirection
        self.beamLimitingDeviceAngle = beamLimitingDeviceAngle
        self.beamLimitingDeviceRotationDirection = beamLimitingDeviceRotationDirection
        self.patientSupportAngle = patientSupportAngle
        self.patientSupportRotationDirection = patientSupportRotationDirection
        self.tableTopVerticalPosition = tableTopVerticalPosition
        self.tableTopLongitudinalPosition = tableTopLongitudinalPosition
        self.tableTopLateralPosition = tableTopLateralPosition
        self.isocenterPosition = isocenterPosition
        self.surfaceEntryPoint = surfaceEntryPoint
        self.sourceToSurfaceDistance = sourceToSurfaceDistance
        self.sourceToExternalContourDistance = sourceToExternalContourDistance
        self.beamLimitingDevicePositions = beamLimitingDevicePositions
        self.nominalBeamEnergy = nominalBeamEnergy
        self.doseRateSet = doseRateSet
        self.wedgePositions = wedgePositions
        self.scanSpotMetersetWeights = scanSpotMetersetWeights
        self.scanSpotPositionMap = scanSpotPositionMap
        self.scanSpotTuneID = scanSpotTuneID
    }
}

// MARK: - BeamLimitingDevicePosition

/// Beam Limiting Device Position
///
/// Defines jaw or MLC (Multi-Leaf Collimator) positions for beam shaping.
///
/// Reference: PS3.3 C.8.8.14 - RT Beams Module, Table C.8-50 (Beam Limiting Device Position Sequence (300A,011A))
public struct BeamLimitingDevicePosition: Sendable {

    /// RT Beam Limiting Device Type (300A,00B8) as written in the data set.
    /// Standard terms: X, Y, ASYMX, ASYMY, MLCX, MLCY (see ``RTBeamLimitingDeviceType``, PS3.3 Table C.8-50).
    public let type: String

    /// RT Beam Limiting Device Type (300A,00B8) as a standard term, `nil` when non-standard.
    public var deviceType: RTBeamLimitingDeviceType? {
        RTBeamLimitingDeviceType(rawValue: type)
    }
    
    /// Number of Leaf/Jaw Pairs
    public let numberOfLeafJawPairs: Int?
    
    /// Leaf/Jaw Positions (mm, boundary pairs)
    /// For jaws: [X1, X2] or [Y1, Y2]
    /// For MLC: [A1, B1, A2, B2, ...] for each leaf pair
    public let positions: [Double]
    
    /// Initialize a Beam Limiting Device Position
    public init(
        type: String,
        numberOfLeafJawPairs: Int? = nil,
        positions: [Double]
    ) {
        self.type = type
        self.numberOfLeafJawPairs = numberOfLeafJawPairs
        self.positions = positions
    }
}

// MARK: - WedgePosition

/// Wedge Position
///
/// Defines wedge orientation and position in the beam.
///
/// Reference: PS3.3 C.8.8.14 - RT Beams Module, Table C.8-50 (Wedge Sequence (300A,00D1), Wedge Position Sequence (300A,0116))
public struct WedgePosition: Sendable {

    /// Wedge Number
    public let number: Int

    /// Wedge Type (300A,00D3) as written in the data set.
    /// Standard terms: STANDARD, DYNAMIC, MOTORIZED (see ``WedgeType``, PS3.3 Table C.8-50).
    public let type: String?

    /// Wedge Type (300A,00D3) as a standard term, `nil` when absent or non-standard.
    public var wedgeType: WedgeType? {
        type.flatMap(WedgeType.init(rawValue:))
    }
    
    /// Wedge ID
    public let id: String?
    
    /// Wedge Angle (degrees)
    public let angle: Double?
    
    /// Wedge Factor
    public let factor: Double?
    
    /// Wedge Orientation (degrees from positive Y axis)
    public let orientation: Double?
    
    /// Wedge Position (300A,0118) as written in the data set.
    /// Standard values: IN, OUT (see ``WedgePlacement``, PS3.3 Table C.8-50).
    public let position: String?

    /// Wedge Position (300A,0118) as a standard value, `nil` when absent or non-standard.
    public var placement: WedgePlacement? {
        position.flatMap(WedgePlacement.init(rawValue:))
    }
    
    /// Initialize a Wedge Position
    public init(
        number: Int,
        type: String? = nil,
        id: String? = nil,
        angle: Double? = nil,
        factor: Double? = nil,
        orientation: Double? = nil,
        position: String? = nil
    ) {
        self.number = number
        self.type = type
        self.id = id
        self.angle = angle
        self.factor = factor
        self.orientation = orientation
        self.position = position
    }
}
