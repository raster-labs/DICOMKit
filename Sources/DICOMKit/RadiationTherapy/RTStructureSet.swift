// NEMA-verified: 2026a, checked 2026-09-29 — RT ROI Interpreted Type (25 terms) and ROI Physical Property per PS3.3 2026a Table C.8-44; Contour Geometric Type per Table C.8-42 (CLOSEDPLANAR_XOR); ROI Generation Algorithm per Table C.8-41
//
// RTStructureSet.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// DICOM RT Structure Set IOD
///
/// An RT Structure Set defines regions of interest (ROIs) used in radiation therapy planning.
/// Each ROI consists of one or more contours that define anatomical or planning structures
/// such as target volumes, organs at risk, and external body contours.
///
/// Reference: PS3.3 A.19 - RT Structure Set IOD
/// Reference: PS3.3 C.8.8.5 - Structure Set Module
/// Reference: PS3.3 C.8.8.6 - ROI Contour Module
/// Reference: PS3.3 C.8.8.8 - RT ROI Observations Module
public struct RTStructureSet: Sendable {
    
    // MARK: - Structure Set Identification
    
    /// SOP Instance UID
    public let sopInstanceUID: String
    
    /// SOP Class UID (should be RT Structure Set Storage: 1.2.840.10008.5.1.4.1.1.481.3)
    public let sopClassUID: String
    
    /// Structure Set Label
    public let label: String?
    
    /// Structure Set Name
    public let name: String?
    
    /// Structure Set Description
    public let description: String?
    
    /// Structure Set Date
    public let date: DICOMDate?
    
    /// Structure Set Time
    public let time: DICOMTime?
    
    // MARK: - Referenced Frame of Reference
    
    /// Frame of Reference UID
    public let frameOfReferenceUID: String?
    
    /// Referenced Study Instance UID
    public let referencedStudyInstanceUID: String?
    
    /// Referenced Series Instance UIDs
    public let referencedSeriesInstanceUIDs: [String]
    
    // MARK: - Regions of Interest
    
    /// Structure Set ROIs (regions of interest)
    public let rois: [RTRegionOfInterest]
    
    /// ROI contours (geometric definitions)
    public let roiContours: [ROIContour]
    
    /// ROI observations (clinical interpretations)
    public let roiObservations: [RTROIObservation]
    
    // MARK: - Initialization
    
    /// Initialize an RT Structure Set
    public init(
        sopInstanceUID: String,
        sopClassUID: String = "1.2.840.10008.5.1.4.1.1.481.3",
        label: String? = nil,
        name: String? = nil,
        description: String? = nil,
        date: DICOMDate? = nil,
        time: DICOMTime? = nil,
        frameOfReferenceUID: String? = nil,
        referencedStudyInstanceUID: String? = nil,
        referencedSeriesInstanceUIDs: [String] = [],
        rois: [RTRegionOfInterest] = [],
        roiContours: [ROIContour] = [],
        roiObservations: [RTROIObservation] = []
    ) {
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.label = label
        self.name = name
        self.description = description
        self.date = date
        self.time = time
        self.frameOfReferenceUID = frameOfReferenceUID
        self.referencedStudyInstanceUID = referencedStudyInstanceUID
        self.referencedSeriesInstanceUIDs = referencedSeriesInstanceUIDs
        self.rois = rois
        self.roiContours = roiContours
        self.roiObservations = roiObservations
    }
}

// MARK: - RTRegionOfInterest

/// RT Region of Interest (ROI)
///
/// Represents a structure defined in a radiation therapy plan, such as a tumor volume,
/// organ at risk, or external body contour.
///
/// Reference: PS3.3 C.8.8.5 - Structure Set Module
public struct RTRegionOfInterest: Sendable, Hashable, Identifiable {
    
    /// ROI number (unique within the structure set)
    public let number: Int
    
    /// ROI name
    public let name: String
    
    /// ROI description
    public let description: String?
    
    /// Frame of Reference UID for this ROI
    public let frameOfReferenceUID: String?
    
    /// ROI Generation Algorithm (3006,0036) as written in the data set.
    /// Standard terms: see ``ROIGenerationAlgorithm`` (PS3.3 Table C.8-41).
    public let generationAlgorithm: String?

    /// ROI Generation Algorithm (3006,0036) as a standard term, `nil` when absent or non-standard.
    public var generationAlgorithmTerm: ROIGenerationAlgorithm? {
        generationAlgorithm.flatMap(ROIGenerationAlgorithm.init(rawValue:))
    }

    /// ROI generation description
    public let generationDescription: String?

    /// Identifiable conformance
    public var id: Int { number }
    
    /// Initialize an RT Region of Interest
    public init(
        number: Int,
        name: String,
        description: String? = nil,
        frameOfReferenceUID: String? = nil,
        generationAlgorithm: String? = nil,
        generationDescription: String? = nil
    ) {
        self.number = number
        self.name = name
        self.description = description
        self.frameOfReferenceUID = frameOfReferenceUID
        self.generationAlgorithm = generationAlgorithm
        self.generationDescription = generationDescription
    }
}

// MARK: - ROIGenerationAlgorithm

/// ROI Generation Algorithm (3006,0036) Defined Terms.
///
/// Reference: PS3.3 C.8.8.5 Structure Set Module, Table C.8-41
public enum ROIGenerationAlgorithm: String, Sendable, Hashable, CaseIterable {
    /// calculated ROI
    case automatic = "AUTOMATIC"

    /// ROI calculated with user assistance
    case semiautomatic = "SEMIAUTOMATIC"

    /// user-entered ROI
    case manual = "MANUAL"
}

// MARK: - ROIContour

/// ROI Contour
///
/// Contains the geometric definition of an ROI as a sequence of contours.
/// Each contour defines a closed planar curve on a specific image slice.
///
/// Reference: PS3.3 C.8.8.6 - ROI Contour Module
public struct ROIContour: Sendable {
    
    /// Referenced ROI number
    public let roiNumber: Int
    
    /// ROI display color (RGB, 0-255)
    public let displayColor: DisplayColor?
    
    /// Contours that define this ROI
    public let contours: [Contour]
    
    /// Initialize an ROI Contour
    public init(
        roiNumber: Int,
        displayColor: DisplayColor? = nil,
        contours: [Contour] = []
    ) {
        self.roiNumber = roiNumber
        self.displayColor = displayColor
        self.contours = contours
    }
}

// MARK: - DisplayColor

/// RGB color for ROI display
public struct DisplayColor: Sendable, Hashable {
    /// Red component (0-255)
    public let red: Int
    
    /// Green component (0-255)
    public let green: Int
    
    /// Blue component (0-255)
    public let blue: Int
    
    /// Initialize a display color
    public init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

// MARK: - Contour

/// Contour
///
/// A single contour defining a closed planar curve in 3D patient space.
/// Contour points are specified in millimeters in the patient coordinate system.
///
/// Reference: PS3.3 C.8.8.6 - ROI Contour Module
public struct Contour: Sendable {
    
    /// Geometric type of the contour
    public let geometricType: ContourGeometricType
    
    /// Number of contour points
    public let numberOfPoints: Int
    
    /// Contour data points (x, y, z coordinates in mm)
    /// Array of 3D points where each point is (x, y, z)
    public let points: [Point3D]
    
    /// Referenced SOP Instance UID (the image this contour is drawn on)
    public let referencedSOPInstanceUID: String?
    
    /// Contour slab thickness (mm)
    public let slabThickness: Double?
    
    /// Contour offset vector
    public let offsetVector: Vector3D?
    
    /// Initialize a Contour
    public init(
        geometricType: ContourGeometricType,
        numberOfPoints: Int,
        points: [Point3D],
        referencedSOPInstanceUID: String? = nil,
        slabThickness: Double? = nil,
        offsetVector: Vector3D? = nil
    ) {
        self.geometricType = geometricType
        self.numberOfPoints = numberOfPoints
        self.points = points
        self.referencedSOPInstanceUID = referencedSOPInstanceUID
        self.slabThickness = slabThickness
        self.offsetVector = offsetVector
    }
}

// MARK: - Vector3D

/// 3D vector in patient coordinate system
public struct Vector3D: Sendable, Hashable {
    /// X component
    public let x: Double
    
    /// Y component
    public let y: Double
    
    /// Z component
    public let z: Double
    
    /// Initialize a 3D vector
    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

// MARK: - Point3D

/// 3D point in patient coordinate system
public struct Point3D: Sendable, Hashable {
    /// X coordinate (mm)
    public let x: Double
    
    /// Y coordinate (mm)
    public let y: Double
    
    /// Z coordinate (mm)
    public let z: Double
    
    /// Initialize a 3D point
    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

// MARK: - ContourGeometricType

/// Contour Geometric Type (3006,0042) Enumerated Values.
///
/// Reference: PS3.3 C.8.8.6 ROI Contour Module, Table C.8-42 and C.8.8.6.3
public enum ContourGeometricType: String, Sendable, Hashable {
    /// single point
    case point = "POINT"

    /// open contour containing coplanar points
    case openPlanar = "OPEN_PLANAR"

    /// closed contour (polygon) containing coplanar points
    case closedPlanar = "CLOSED_PLANAR"

    /// open contour containing non-coplanar points
    case openNonplanar = "OPEN_NONPLANAR"

    /// closed contour (polygon) containing coplanar points of an inner or outer contour
    /// combined using an XOR operator (the "XOR" technique of PS3.3 C.8.8.6.3)
    case closedPlanarXOR = "CLOSEDPLANAR_XOR"

    /// Not a term of PS3.3 2026a Table C.8-42. Retained only so that data sets written with
    /// this value by earlier DICOMKit versions still parse; never write it.
    @available(*, deprecated, renamed: "closedPlanarXOR", message: "CLOSED_NONPLANAR is not a Contour Geometric Type in PS3.3 2026a Table C.8-42; the standard XOR term is CLOSEDPLANAR_XOR")
    case closedNonplanar = "CLOSED_NONPLANAR"

    /// The five Enumerated Values of PS3.3 2026a Table C.8-42, in table order.
    public static let standardValues: [ContourGeometricType] = [
        .point, .openPlanar, .openNonplanar, .closedPlanar, .closedPlanarXOR
    ]
}

// MARK: - RTROIObservation

/// RT ROI Observation
///
/// Clinical interpretation and metadata for an ROI, including the interpreted type
/// (e.g., PTV, GTV, organ at risk) and optional physical properties.
///
/// Reference: PS3.3 C.8.8.8 - RT ROI Observations Module
public struct RTROIObservation: Sendable, Hashable {
    
    /// Observation number (unique within structure set)
    public let observationNumber: Int
    
    /// Referenced ROI number
    public let referencedROINumber: Int
    
    /// RT ROI interpreted type (e.g., PTV, CTV, ORGAN)
    public let interpretedType: RTROIInterpretedType?
    
    /// ROI interpreter (person or algorithm)
    public let interpreter: String?
    
    /// ROI physical properties
    public let physicalProperties: [ROIPhysicalProperty]
    
    /// Initialize an RT ROI Observation
    public init(
        observationNumber: Int,
        referencedROINumber: Int,
        interpretedType: RTROIInterpretedType? = nil,
        interpreter: String? = nil,
        physicalProperties: [ROIPhysicalProperty] = []
    ) {
        self.observationNumber = observationNumber
        self.referencedROINumber = referencedROINumber
        self.interpretedType = interpretedType
        self.interpreter = interpreter
        self.physicalProperties = physicalProperties
    }
}

// MARK: - RTROIInterpretedType

/// RT ROI Interpreted Type (3006,00A4) Defined Terms.
///
/// The 25 terms of PS3.3 2026a Table C.8-44, in table order.
///
/// Reference: PS3.3 C.8.8.8 RT ROI Observations Module, Table C.8-44 and C.8.8.8.1
public enum RTROIInterpretedType: String, Sendable, Hashable, CaseIterable {
    /// external patient contour
    case external = "EXTERNAL"

    /// Planning Target Volume (as defined in ICRU Report 50)
    case ptv = "PTV"

    /// Clinical Target Volume (as defined in ICRU Report 50)
    case ctv = "CTV"

    /// Gross Tumor Volume (as defined in ICRU Report 50)
    case gtv = "GTV"

    /// Treated Volume (as defined in ICRU Report 50)
    case treatedVolume = "TREATED_VOLUME"

    /// Irradiated Volume (as defined in ICRU Report 50)
    case irradiatedVolume = "IRRAD_VOLUME"

    /// Organ at Risk (as defined in ICRU Report 50)
    case organAtRisk = "OAR"

    /// patient bolus to be used for external beam therapy
    case bolus = "BOLUS"

    /// region in which dose is to be minimized
    case avoidance = "AVOIDANCE"

    /// patient organ
    case organ = "ORGAN"

    /// patient marker or marker on a localizer
    case marker = "MARKER"

    /// registration ROI
    case registration = "REGISTRATION"

    /// treatment isocenter to be used for external beam therapy
    case isocenter = "ISOCENTER"

    /// volume into which a contrast agent has been injected
    case contrastAgent = "CONTRAST_AGENT"

    /// patient anatomical cavity
    case cavity = "CAVITY"

    /// brachytherapy channel
    case brachyChannel = "BRACHY_CHANNEL"

    /// brachytherapy accessory device
    case brachyAccessory = "BRACHY_ACCESSORY"

    /// brachytherapy source applicator
    case brachySourceApplicator = "BRACHY_SRC_APP"

    /// brachytherapy channel shield
    case brachyChannelShield = "BRACHY_CHNL_SHLD"

    /// external patient support device
    case support = "SUPPORT"

    /// external patient fixation or immobilization device
    case fixationDevice = "FIXATION"

    /// ROI to be used as a dose reference
    case doseRegion = "DOSE_REGION"

    /// ROI to be used in control of dose optimization and calculation
    case controlPoint = "CONTROL"

    /// ROI representing a dose measurement device, such as a chamber or TLD
    case doseMeasurement = "DOSE_MEASUREMENT"

    /// device not addressed by another Defined Term
    case device = "DEVICE"
}

// MARK: - ROIPhysicalPropertyType

/// ROI Physical Property (3006,00B2) Defined Terms.
///
/// Reference: PS3.3 C.8.8.8 RT ROI Observations Module, Table C.8-44
public enum ROIPhysicalPropertyType: String, Sendable, Hashable, CaseIterable {
    /// mass density relative to water
    case relativeMassDensity = "REL_MASS_DENSITY"

    /// electron density relative to water
    case relativeElectronDensity = "REL_ELEC_DENSITY"

    /// effective atomic number
    case effectiveZ = "EFFECTIVE_Z"

    /// ratio of effective atomic number to mass (AMU-1)
    case effectiveZPerA = "EFF_Z_PER_A"

    /// ratio of linear stopping power of material relative to linear stopping power of water
    case relativeStoppingRatio = "REL_STOP_RATIO"

    /// elemental composition of the material (ROI Elemental Composition Sequence (3006,00B6) is then required)
    case elementalFraction = "ELEM_FRACTION"

    /// Mean Excitation Energy of the material (eV)
    case meanExcitationEnergy = "MEAN_EXCI_ENERGY"
}

// MARK: - ROIPhysicalProperty

/// ROI Physical Property
///
/// Physical properties of an ROI such as density or elemental composition.
///
/// Reference: PS3.3 C.8.8.8 - RT ROI Observations Module
public struct ROIPhysicalProperty: Sendable, Hashable {
    
    /// ROI Physical Property (3006,00B2) as written in the data set.
    /// Standard terms: see ``ROIPhysicalPropertyType`` (PS3.3 Table C.8-44).
    public let property: String

    /// ROI Physical Property (3006,00B2) as a standard term, `nil` when non-standard.
    public var propertyType: ROIPhysicalPropertyType? {
        ROIPhysicalPropertyType(rawValue: property)
    }

    /// ROI Physical Property Value (3006,00B4)
    public let value: Double
    
    /// Initialize an ROI Physical Property
    public init(property: String, value: Double) {
        self.property = property
        self.value = value
    }
}
