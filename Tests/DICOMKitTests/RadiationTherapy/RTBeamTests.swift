//
// RTBeamTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class RTBeamTests: XCTestCase {
    
    // MARK: - RTBeam Tests
    
    func test_rtBeam_initialization() {
        let beam = RTBeam(
            number: 1,
            name: "AP Beam",
            description: "Anterior-Posterior field",
            type: "STATIC",
            radiationType: "PHOTON",
            treatmentMachineName: "TrueBeam",
            manufacturer: "Varian",
            institutionName: "Test Hospital",
            primaryDosimeterUnit: "MU",
            sourceAxisDistance: 1000.0
        )
        
        XCTAssertEqual(beam.number, 1)
        XCTAssertEqual(beam.name, "AP Beam")
        XCTAssertEqual(beam.description, "Anterior-Posterior field")
        XCTAssertEqual(beam.type, "STATIC")
        XCTAssertEqual(beam.radiationType, "PHOTON")
        XCTAssertEqual(beam.treatmentMachineName, "TrueBeam")
        XCTAssertEqual(beam.manufacturer, "Varian")
        XCTAssertEqual(beam.institutionName, "Test Hospital")
        XCTAssertEqual(beam.primaryDosimeterUnit, "MU")
        XCTAssertEqual(beam.sourceAxisDistance, 1000.0)
    }
    
    func test_rtBeam_identifiable() {
        let beam = RTBeam(number: 42, name: "Test Beam")
        XCTAssertEqual(beam.id, 42)
    }
    
    func test_rtBeam_withControlPoints() {
        let cp1 = BeamControlPoint(index: 0, cumulativeMetersetWeight: 0.0)
        let cp2 = BeamControlPoint(index: 1, cumulativeMetersetWeight: 0.5)
        let cp3 = BeamControlPoint(index: 2, cumulativeMetersetWeight: 1.0)
        
        let beam = RTBeam(
            number: 1,
            name: "IMRT Beam",
            controlPoints: [cp1, cp2, cp3],
            finalCumulativeMetersetWeight: 1.0
        )
        
        XCTAssertEqual(beam.numberOfControlPoints, 3)
        XCTAssertEqual(beam.controlPoints[0].index, 0)
        XCTAssertEqual(beam.controlPoints[1].cumulativeMetersetWeight, 0.5)
        XCTAssertEqual(beam.finalCumulativeMetersetWeight, 1.0)
    }
    
    // MARK: - BeamControlPoint Tests
    
    func test_beamControlPoint_initialization() {
        let isocenter = Point3D(x: 0.0, y: 0.0, z: 0.0)
        let controlPoint = BeamControlPoint(
            index: 0,
            cumulativeMetersetWeight: 0.0,
            gantryAngle: 0.0,
            gantryRotationDirection: "CW",
            beamLimitingDeviceAngle: 0.0,
            beamLimitingDeviceRotationDirection: "NONE",
            patientSupportAngle: 0.0,
            patientSupportRotationDirection: "NONE",
            tableTopVerticalPosition: -150.0,
            tableTopLongitudinalPosition: 0.0,
            tableTopLateralPosition: 0.0,
            isocenterPosition: isocenter,
            sourceToSurfaceDistance: 950.0,
            nominalBeamEnergy: 6.0,
            doseRateSet: 600.0
        )
        
        XCTAssertEqual(controlPoint.index, 0)
        XCTAssertEqual(controlPoint.cumulativeMetersetWeight, 0.0)
        XCTAssertEqual(controlPoint.gantryAngle, 0.0)
        XCTAssertEqual(controlPoint.gantryRotationDirection, "CW")
        XCTAssertEqual(controlPoint.beamLimitingDeviceAngle, 0.0)
        XCTAssertEqual(controlPoint.patientSupportAngle, 0.0)
        XCTAssertEqual(controlPoint.tableTopVerticalPosition, -150.0)
        XCTAssertEqual(controlPoint.isocenterPosition?.x, 0.0)
        XCTAssertEqual(controlPoint.sourceToSurfaceDistance, 950.0)
        XCTAssertEqual(controlPoint.nominalBeamEnergy, 6.0)
        XCTAssertEqual(controlPoint.doseRateSet, 600.0)
    }
    
    func test_beamControlPoint_withBeamLimitingDevices() {
        let jawX = BeamLimitingDevicePosition(
            type: "ASYMX",
            numberOfLeafJawPairs: 1,
            positions: [-100.0, 100.0]
        )
        let jawY = BeamLimitingDevicePosition(
            type: "ASYMY",
            numberOfLeafJawPairs: 1,
            positions: [-100.0, 100.0]
        )
        
        let controlPoint = BeamControlPoint(
            index: 0,
            beamLimitingDevicePositions: [jawX, jawY]
        )
        
        XCTAssertEqual(controlPoint.beamLimitingDevicePositions.count, 2)
        XCTAssertEqual(controlPoint.beamLimitingDevicePositions[0].type, "ASYMX")
        XCTAssertEqual(controlPoint.beamLimitingDevicePositions[0].positions, [-100.0, 100.0])
    }
    
    // MARK: - BeamLimitingDevicePosition Tests
    
    func test_beamLimitingDevicePosition_jaws() {
        let jawX = BeamLimitingDevicePosition(
            type: "X",
            numberOfLeafJawPairs: 1,
            positions: [-50.0, 50.0]
        )
        
        XCTAssertEqual(jawX.type, "X")
        XCTAssertEqual(jawX.numberOfLeafJawPairs, 1)
        XCTAssertEqual(jawX.positions.count, 2)
        XCTAssertEqual(jawX.positions[0], -50.0)
        XCTAssertEqual(jawX.positions[1], 50.0)
    }
    
    func test_beamLimitingDevicePosition_mlc() {
        // Simulating a 5-leaf MLC with positions for each bank
        let mlc = BeamLimitingDevicePosition(
            type: "MLCX",
            numberOfLeafJawPairs: 5,
            positions: [
                -20.0, 20.0,  // Leaf 1: A1, B1
                -20.0, 20.0,  // Leaf 2: A2, B2
                -20.0, 20.0,  // Leaf 3: A3, B3
                -20.0, 20.0,  // Leaf 4: A4, B4
                -20.0, 20.0   // Leaf 5: A5, B5
            ]
        )
        
        XCTAssertEqual(mlc.type, "MLCX")
        XCTAssertEqual(mlc.numberOfLeafJawPairs, 5)
        XCTAssertEqual(mlc.positions.count, 10)
    }
    
    // MARK: - WedgePosition Tests
    
    func test_wedgePosition_initialization() {
        let wedge = WedgePosition(
            number: 1,
            type: "STANDARD",
            id: "W15",
            angle: 15.0,
            factor: 0.85,
            orientation: 0.0,
            position: "IN"
        )
        
        XCTAssertEqual(wedge.number, 1)
        XCTAssertEqual(wedge.type, "STANDARD")
        XCTAssertEqual(wedge.id, "W15")
        XCTAssertEqual(wedge.angle, 15.0)
        XCTAssertEqual(wedge.factor, 0.85)
        XCTAssertEqual(wedge.orientation, 0.0)
        XCTAssertEqual(wedge.position, "IN")
    }
    
    func test_wedgePosition_dynamicWedge() {
        let wedge = WedgePosition(
            number: 1,
            type: "DYNAMIC",
            angle: 60.0,
            orientation: 90.0
        )
        
        XCTAssertEqual(wedge.type, "DYNAMIC")
        XCTAssertEqual(wedge.angle, 60.0)
        XCTAssertEqual(wedge.orientation, 90.0)
    }
    
    // MARK: - Integration Tests
    
    func test_rtBeam_complexConfiguration() {
        // Create a complex IMRT beam with multiple control points and MLC positions
        let mlc = BeamLimitingDevicePosition(
            type: "MLCX",
            numberOfLeafJawPairs: 3,
            positions: [-15.0, 15.0, -15.0, 15.0, -15.0, 15.0]
        )
        
        let cp1 = BeamControlPoint(
            index: 0,
            cumulativeMetersetWeight: 0.0,
            gantryAngle: 0.0,
            gantryRotationDirection: "CW",
            beamLimitingDeviceAngle: 0.0,
            beamLimitingDevicePositions: [mlc],
            nominalBeamEnergy: 6.0
        )
        
        let cp2 = BeamControlPoint(
            index: 1,
            cumulativeMetersetWeight: 0.5,
            gantryAngle: 45.0,
            gantryRotationDirection: "CW",
            beamLimitingDeviceAngle: 10.0,
            beamLimitingDevicePositions: [mlc],
            nominalBeamEnergy: 6.0
        )
        
        let cp3 = BeamControlPoint(
            index: 2,
            cumulativeMetersetWeight: 1.0,
            gantryAngle: 90.0,
            gantryRotationDirection: "NONE",
            beamLimitingDeviceAngle: 20.0,
            beamLimitingDevicePositions: [mlc],
            nominalBeamEnergy: 6.0
        )
        
        let beam = RTBeam(
            number: 1,
            name: "VMAT Arc 1",
            description: "CW arc from 0 to 90 degrees",
            type: "DYNAMIC",
            radiationType: "PHOTON",
            treatmentMachineName: "TrueBeam",
            primaryDosimeterUnit: "MU",
            sourceAxisDistance: 1000.0,
            controlPoints: [cp1, cp2, cp3],
            finalCumulativeMetersetWeight: 1.0
        )
        
        XCTAssertEqual(beam.numberOfControlPoints, 3)
        XCTAssertEqual(beam.type, "DYNAMIC")
        XCTAssertEqual(beam.beamType, .dynamic)
        XCTAssertEqual(beam.controlPoints[0].gantryAngle, 0.0)
        XCTAssertEqual(beam.controlPoints[1].gantryAngle, 45.0)
        XCTAssertEqual(beam.controlPoints[2].gantryAngle, 90.0)
        XCTAssertEqual(beam.controlPoints[2].cumulativeMetersetWeight, 1.0)
    }

    // MARK: - 2026a term enums (PS3.3 Table C.8-50)

    func test_beamType_rawValues() {
        XCTAssertEqual(BeamType.allCases.map(\.rawValue), ["STATIC", "DYNAMIC"])
    }

    func test_radiationType_rawValues() {
        XCTAssertEqual(RadiationType.allCases.map(\.rawValue), ["PHOTON", "ELECTRON", "NEUTRON", "PROTON"])
    }

    func test_primaryDosimeterUnit_rawValues() {
        XCTAssertEqual(PrimaryDosimeterUnit.allCases.map(\.rawValue), ["MU", "MINUTE"])
    }

    func test_highDoseTechniqueType_rawValues() {
        XCTAssertEqual(HighDoseTechniqueType.allCases.map(\.rawValue), ["TBI", "HDR"])
    }

    func test_treatmentDeliveryType_rawValues() {
        XCTAssertEqual(TreatmentDeliveryType.allCases.map(\.rawValue),
                       ["TREATMENT", "OPEN_PORTFILM", "TRMT_PORTFILM", "CONTINUATION", "SETUP"])
    }

    func test_rtBeamLimitingDeviceType_rawValues() {
        XCTAssertEqual(RTBeamLimitingDeviceType.allCases.map(\.rawValue), ["X", "Y", "ASYMX", "ASYMY", "MLCX", "MLCY"])
    }

    func test_rotationDirection_rawValues() {
        XCTAssertEqual(RotationDirection.allCases.map(\.rawValue), ["CW", "CC", "NONE"])
    }

    func test_wedgeType_and_placement_rawValues() {
        XCTAssertEqual(WedgeType.allCases.map(\.rawValue), ["STANDARD", "DYNAMIC", "MOTORIZED"])
        XCTAssertEqual(WedgePlacement.allCases.map(\.rawValue), ["IN", "OUT"])
    }

    func test_rtBeam_typedAccessors_deriveFromStrings() {
        let beam = RTBeam(
            number: 1,
            type: "STATIC",
            radiationType: "NEUTRON",
            primaryDosimeterUnit: "MINUTE",
            treatmentDeliveryType: "TRMT_PORTFILM",
            highDoseTechniqueType: "HDR"
        )
        XCTAssertEqual(beam.beamType, .static)
        XCTAssertEqual(beam.radiationTypeTerm, .neutron)
        XCTAssertEqual(beam.primaryDosimeterUnitTerm, .minute)
        XCTAssertEqual(beam.treatmentDeliveryTypeTerm, .treatmentPortfilm)
        XCTAssertEqual(beam.highDoseTechniqueTypeTerm, .highDoseRate)

        let legacy = RTBeam(number: 2, type: "MODULATED", radiationType: "CARBON", primaryDosimeterUnit: "MINUTES")
        XCTAssertEqual(legacy.type, "MODULATED")
        XCTAssertNil(legacy.beamType)
        XCTAssertNil(legacy.radiationTypeTerm)
        XCTAssertNil(legacy.primaryDosimeterUnitTerm)
        XCTAssertNil(legacy.treatmentDeliveryTypeTerm)
    }

    func test_controlPoint_and_device_typedAccessors() {
        let jaw = BeamLimitingDevicePosition(type: "ASYMY", positions: [-5, 5])
        XCTAssertEqual(jaw.deviceType, .asymmetricY)
        XCTAssertNil(BeamLimitingDevicePosition(type: "MLC", positions: []).deviceType)

        let point = BeamControlPoint(
            index: 0,
            gantryRotationDirection: "CC",
            beamLimitingDeviceRotationDirection: "CW",
            patientSupportRotationDirection: "NONE"
        )
        XCTAssertEqual(point.gantryRotation, .counterClockwise)
        XCTAssertEqual(point.beamLimitingDeviceRotation, .clockwise)
        XCTAssertEqual(point.patientSupportRotation, RotationDirection.none)
        XCTAssertNil(BeamControlPoint(index: 1).gantryRotation)

        let wedge = WedgePosition(number: 1, type: "MOTORIZED", position: "IN")
        XCTAssertEqual(wedge.wedgeType, .motorized)
        XCTAssertEqual(wedge.placement, .in)
    }
}
