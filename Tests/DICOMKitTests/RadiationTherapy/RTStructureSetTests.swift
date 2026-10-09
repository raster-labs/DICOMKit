//
// RTStructureSetTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class RTStructureSetTests: XCTestCase {
    
    // MARK: - RTStructureSet Tests
    
    func test_rtStructureSet_initialization() {
        let structureSet = RTStructureSet(
            sopInstanceUID: "1.2.3.4.5",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.481.3",
            label: "Test Structure Set",
            name: "Prostate Plan"
        )
        
        XCTAssertEqual(structureSet.sopInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(structureSet.sopClassUID, "1.2.840.10008.5.1.4.1.1.481.3")
        XCTAssertEqual(structureSet.label, "Test Structure Set")
        XCTAssertEqual(structureSet.name, "Prostate Plan")
        XCTAssertEqual(structureSet.rois.count, 0)
        XCTAssertEqual(structureSet.roiContours.count, 0)
        XCTAssertEqual(structureSet.roiObservations.count, 0)
    }
    
    func test_rtStructureSet_withROIs() {
        let roi1 = RTRegionOfInterest(number: 1, name: "PTV")
        let roi2 = RTRegionOfInterest(number: 2, name: "Bladder")
        
        let structureSet = RTStructureSet(
            sopInstanceUID: "1.2.3.4.5",
            rois: [roi1, roi2]
        )
        
        XCTAssertEqual(structureSet.rois.count, 2)
        XCTAssertEqual(structureSet.rois[0].name, "PTV")
        XCTAssertEqual(structureSet.rois[1].name, "Bladder")
    }
    
    // MARK: - RTRegionOfInterest Tests
    
    func test_rtRegionOfInterest_initialization() {
        let roi = RTRegionOfInterest(
            number: 1,
            name: "PTV",
            description: "Planning Target Volume",
            frameOfReferenceUID: "1.2.3.4",
            generationAlgorithm: "AUTOMATIC",
            generationDescription: "Auto-segmented by AI"
        )
        
        XCTAssertEqual(roi.number, 1)
        XCTAssertEqual(roi.name, "PTV")
        XCTAssertEqual(roi.description, "Planning Target Volume")
        XCTAssertEqual(roi.frameOfReferenceUID, "1.2.3.4")
        XCTAssertEqual(roi.generationAlgorithm, "AUTOMATIC")
        XCTAssertEqual(roi.generationDescription, "Auto-segmented by AI")
    }
    
    func test_rtRegionOfInterest_identifiable() {
        let roi = RTRegionOfInterest(number: 42, name: "Test")
        XCTAssertEqual(roi.id, 42)
    }
    
    func test_rtRegionOfInterest_hashable() {
        let roi1 = RTRegionOfInterest(number: 1, name: "PTV")
        let roi2 = RTRegionOfInterest(number: 1, name: "PTV")
        let roi3 = RTRegionOfInterest(number: 2, name: "GTV")
        
        XCTAssertEqual(roi1, roi2)
        XCTAssertNotEqual(roi1, roi3)
        
        let set: Set = [roi1, roi2, roi3]
        XCTAssertEqual(set.count, 2)
    }
    
    // MARK: - Point3D Tests
    
    func test_point3D_initialization() {
        let point = Point3D(x: 10.5, y: 20.3, z: 30.7)
        
        XCTAssertEqual(point.x, 10.5)
        XCTAssertEqual(point.y, 20.3)
        XCTAssertEqual(point.z, 30.7)
    }
    
    func test_point3D_hashable() {
        let point1 = Point3D(x: 1.0, y: 2.0, z: 3.0)
        let point2 = Point3D(x: 1.0, y: 2.0, z: 3.0)
        let point3 = Point3D(x: 1.0, y: 2.0, z: 4.0)
        
        XCTAssertEqual(point1, point2)
        XCTAssertNotEqual(point1, point3)
    }
    
    // MARK: - Vector3D Tests
    
    func test_vector3D_initialization() {
        let vector = Vector3D(x: 1.0, y: 0.0, z: 0.0)
        
        XCTAssertEqual(vector.x, 1.0)
        XCTAssertEqual(vector.y, 0.0)
        XCTAssertEqual(vector.z, 0.0)
    }
    
    // MARK: - DisplayColor Tests
    
    func test_displayColor_initialization() {
        let color = DisplayColor(red: 255, green: 0, blue: 0)
        
        XCTAssertEqual(color.red, 255)
        XCTAssertEqual(color.green, 0)
        XCTAssertEqual(color.blue, 0)
    }
    
    func test_displayColor_hashable() {
        let color1 = DisplayColor(red: 255, green: 0, blue: 0)
        let color2 = DisplayColor(red: 255, green: 0, blue: 0)
        let color3 = DisplayColor(red: 0, green: 255, blue: 0)
        
        XCTAssertEqual(color1, color2)
        XCTAssertNotEqual(color1, color3)
    }
    
    // MARK: - Contour Tests
    
    func test_contour_initialization() {
        let points = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 10.0, y: 0.0, z: 0.0),
            Point3D(x: 10.0, y: 10.0, z: 0.0),
            Point3D(x: 0.0, y: 10.0, z: 0.0)
        ]
        
        let contour = Contour(
            geometricType: .closedPlanar,
            numberOfPoints: 4,
            points: points,
            referencedSOPInstanceUID: "1.2.3.4.5",
            slabThickness: 2.5
        )
        
        XCTAssertEqual(contour.geometricType, .closedPlanar)
        XCTAssertEqual(contour.numberOfPoints, 4)
        XCTAssertEqual(contour.points.count, 4)
        XCTAssertEqual(contour.referencedSOPInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(contour.slabThickness, 2.5)
    }
    
    func test_contour_withOffsetVector() {
        let points = [Point3D(x: 0.0, y: 0.0, z: 0.0)]
        let offsetVector = Vector3D(x: 1.0, y: 2.0, z: 3.0)
        
        let contour = Contour(
            geometricType: .point,
            numberOfPoints: 1,
            points: points,
            offsetVector: offsetVector
        )
        
        XCTAssertEqual(contour.offsetVector?.x, 1.0)
        XCTAssertEqual(contour.offsetVector?.y, 2.0)
        XCTAssertEqual(contour.offsetVector?.z, 3.0)
    }
    
    // MARK: - ContourGeometricType Tests
    
    /// PS3.3 2026a Table C.8-42, Contour Geometric Type (3006,0042) Enumerated Values
    func test_contourGeometricType_rawValues() {
        XCTAssertEqual(ContourGeometricType.point.rawValue, "POINT")
        XCTAssertEqual(ContourGeometricType.openPlanar.rawValue, "OPEN_PLANAR")
        XCTAssertEqual(ContourGeometricType.openNonplanar.rawValue, "OPEN_NONPLANAR")
        XCTAssertEqual(ContourGeometricType.closedPlanar.rawValue, "CLOSED_PLANAR")
        XCTAssertEqual(ContourGeometricType.closedPlanarXOR.rawValue, "CLOSEDPLANAR_XOR")
        XCTAssertEqual(ContourGeometricType.standardValues.map(\.rawValue),
                       ["POINT", "OPEN_PLANAR", "OPEN_NONPLANAR", "CLOSED_PLANAR", "CLOSEDPLANAR_XOR"])
    }

    func test_contourGeometricType_fromString() {
        XCTAssertEqual(ContourGeometricType(rawValue: "POINT"), .point)
        XCTAssertEqual(ContourGeometricType(rawValue: "CLOSED_PLANAR"), .closedPlanar)
        XCTAssertEqual(ContourGeometricType(rawValue: "CLOSEDPLANAR_XOR"), .closedPlanarXOR)
        XCTAssertNil(ContourGeometricType(rawValue: "INVALID"))
    }

    /// The pre-2026a DICOMKit value CLOSED_NONPLANAR is not a standard term but must still parse.
    @available(*, deprecated)
    func test_contourGeometricType_legacyClosedNonplanarStillParses() {
        XCTAssertEqual(ContourGeometricType(rawValue: "CLOSED_NONPLANAR"), .closedNonplanar)
        XCTAssertFalse(ContourGeometricType.standardValues.contains(.closedNonplanar))
    }

    // MARK: - RTROIInterpretedType Tests

    /// PS3.3 2026a Table C.8-44, RT ROI Interpreted Type (3006,00A4) Defined Terms, in table order
    func test_rtROIInterpretedType_allTableC8_44Terms() {
        let expected = [
            "EXTERNAL", "PTV", "CTV", "GTV", "TREATED_VOLUME", "IRRAD_VOLUME", "OAR", "BOLUS",
            "AVOIDANCE", "ORGAN", "MARKER", "REGISTRATION", "ISOCENTER", "CONTRAST_AGENT", "CAVITY",
            "BRACHY_CHANNEL", "BRACHY_ACCESSORY", "BRACHY_SRC_APP", "BRACHY_CHNL_SHLD", "SUPPORT",
            "FIXATION", "DOSE_REGION", "CONTROL", "DOSE_MEASUREMENT", "DEVICE"
        ]
        XCTAssertEqual(RTROIInterpretedType.allCases.map(\.rawValue), expected)
        XCTAssertEqual(RTROIInterpretedType.allCases.count, 25)
        XCTAssertEqual(RTROIInterpretedType.organAtRisk.rawValue, "OAR")
        XCTAssertEqual(RTROIInterpretedType.brachyChannel.rawValue, "BRACHY_CHANNEL")
        XCTAssertEqual(RTROIInterpretedType.brachyAccessory.rawValue, "BRACHY_ACCESSORY")
        XCTAssertEqual(RTROIInterpretedType.brachySourceApplicator.rawValue, "BRACHY_SRC_APP")
        XCTAssertEqual(RTROIInterpretedType.brachyChannelShield.rawValue, "BRACHY_CHNL_SHLD")
        XCTAssertEqual(RTROIInterpretedType.doseMeasurement.rawValue, "DOSE_MEASUREMENT")
        XCTAssertEqual(RTROIInterpretedType.device.rawValue, "DEVICE")
        XCTAssertEqual(RTROIInterpretedType.irradiatedVolume.rawValue, "IRRAD_VOLUME")
        XCTAssertEqual(RTROIInterpretedType.fixationDevice.rawValue, "FIXATION")
        XCTAssertEqual(RTROIInterpretedType.controlPoint.rawValue, "CONTROL")
    }

    // MARK: - ROI term enums

    /// PS3.3 2026a Table C.8-44, ROI Physical Property (3006,00B2) Defined Terms
    func test_roiPhysicalPropertyType_rawValues() {
        XCTAssertEqual(ROIPhysicalPropertyType.allCases.map(\.rawValue),
                       ["REL_MASS_DENSITY", "REL_ELEC_DENSITY", "EFFECTIVE_Z", "EFF_Z_PER_A",
                        "REL_STOP_RATIO", "ELEM_FRACTION", "MEAN_EXCI_ENERGY"])
        let property = ROIPhysicalProperty(property: "REL_ELEC_DENSITY", value: 1.05)
        XCTAssertEqual(property.propertyType, .relativeElectronDensity)
        XCTAssertNil(ROIPhysicalProperty(property: "DENSITY", value: 1).propertyType)
    }

    /// PS3.3 2026a Table C.8-41, ROI Generation Algorithm (3006,0036) Defined Terms
    func test_roiGenerationAlgorithm_rawValues() {
        XCTAssertEqual(ROIGenerationAlgorithm.allCases.map(\.rawValue), ["AUTOMATIC", "SEMIAUTOMATIC", "MANUAL"])
        let roi = RTRegionOfInterest(number: 1, name: "PTV", generationAlgorithm: "SEMIAUTOMATIC")
        XCTAssertEqual(roi.generationAlgorithmTerm, .semiautomatic)
        XCTAssertNil(RTRegionOfInterest(number: 2, name: "X", generationAlgorithm: "AUTO").generationAlgorithmTerm)
        XCTAssertNil(RTRegionOfInterest(number: 3, name: "Y").generationAlgorithmTerm)
    }
    
    // MARK: - ROIContour Tests
    
    func test_roiContour_initialization() {
        let color = DisplayColor(red: 255, green: 0, blue: 0)
        let points = [Point3D(x: 0.0, y: 0.0, z: 0.0)]
        let contour = Contour(
            geometricType: .point,
            numberOfPoints: 1,
            points: points
        )
        
        let roiContour = ROIContour(
            roiNumber: 1,
            displayColor: color,
            contours: [contour]
        )
        
        XCTAssertEqual(roiContour.roiNumber, 1)
        XCTAssertEqual(roiContour.displayColor?.red, 255)
        XCTAssertEqual(roiContour.contours.count, 1)
    }
    
    // MARK: - RTROIObservation Tests
    
    func test_rtROIObservation_initialization() {
        let observation = RTROIObservation(
            observationNumber: 1,
            referencedROINumber: 1,
            interpretedType: .ptv,
            interpreter: "Dr. Smith"
        )
        
        XCTAssertEqual(observation.observationNumber, 1)
        XCTAssertEqual(observation.referencedROINumber, 1)
        XCTAssertEqual(observation.interpretedType, .ptv)
        XCTAssertEqual(observation.interpreter, "Dr. Smith")
        XCTAssertEqual(observation.physicalProperties.count, 0)
    }
    
    func test_rtROIObservation_withPhysicalProperties() {
        let property1 = ROIPhysicalProperty(property: "REL_ELEC_DENSITY", value: 1.05)
        let property2 = ROIPhysicalProperty(property: "REL_MASS_DENSITY", value: 1.03)
        
        let observation = RTROIObservation(
            observationNumber: 1,
            referencedROINumber: 1,
            physicalProperties: [property1, property2]
        )
        
        XCTAssertEqual(observation.physicalProperties.count, 2)
        XCTAssertEqual(observation.physicalProperties[0].property, "REL_ELEC_DENSITY")
        XCTAssertEqual(observation.physicalProperties[0].value, 1.05)
    }
    
    // MARK: - RTROIInterpretedType Tests
    
    func test_rtROIInterpretedType_rawValues() {
        XCTAssertEqual(RTROIInterpretedType.ptv.rawValue, "PTV")
        XCTAssertEqual(RTROIInterpretedType.ctv.rawValue, "CTV")
        XCTAssertEqual(RTROIInterpretedType.gtv.rawValue, "GTV")
        XCTAssertEqual(RTROIInterpretedType.organ.rawValue, "ORGAN")
        XCTAssertEqual(RTROIInterpretedType.external.rawValue, "EXTERNAL")
        XCTAssertEqual(RTROIInterpretedType.avoidance.rawValue, "AVOIDANCE")
        XCTAssertEqual(RTROIInterpretedType.marker.rawValue, "MARKER")
        XCTAssertEqual(RTROIInterpretedType.isocenter.rawValue, "ISOCENTER")
    }
    
    func test_rtROIInterpretedType_fromString() {
        XCTAssertEqual(RTROIInterpretedType(rawValue: "PTV"), .ptv)
        XCTAssertEqual(RTROIInterpretedType(rawValue: "ORGAN"), .organ)
        XCTAssertNil(RTROIInterpretedType(rawValue: "INVALID"))
    }
    
    // MARK: - ROIPhysicalProperty Tests
    
    func test_roiPhysicalProperty_initialization() {
        let property = ROIPhysicalProperty(property: "REL_ELEC_DENSITY", value: 1.05)
        
        XCTAssertEqual(property.property, "REL_ELEC_DENSITY")
        XCTAssertEqual(property.value, 1.05)
    }
    
    func test_roiPhysicalProperty_hashable() {
        let prop1 = ROIPhysicalProperty(property: "REL_ELEC_DENSITY", value: 1.05)
        let prop2 = ROIPhysicalProperty(property: "REL_ELEC_DENSITY", value: 1.05)
        let prop3 = ROIPhysicalProperty(property: "REL_MASS_DENSITY", value: 1.03)
        
        XCTAssertEqual(prop1, prop2)
        XCTAssertNotEqual(prop1, prop3)
    }
}
