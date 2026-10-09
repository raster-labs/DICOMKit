//
// RTPlanTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class RTPlanTests: XCTestCase {
    
    // MARK: - RTPlan Tests
    
    func test_rtPlan_initialization() {
        let plan = RTPlan(
            sopInstanceUID: "1.2.3.4.5",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.481.5",
            label: "Test Plan",
            name: "Prostate IMRT"
        )
        
        XCTAssertEqual(plan.sopInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(plan.sopClassUID, "1.2.840.10008.5.1.4.1.1.481.5")
        XCTAssertEqual(plan.label, "Test Plan")
        XCTAssertEqual(plan.name, "Prostate IMRT")
        XCTAssertEqual(plan.doseReferences.count, 0)
        XCTAssertEqual(plan.fractionGroups.count, 0)
        XCTAssertEqual(plan.beams.count, 0)
        XCTAssertEqual(plan.brachyApplicationSetups.count, 0)
    }
    
    func test_rtPlan_withDoseReferences() {
        let doseRef1 = DoseReference(
            number: 1,
            structureType: "VOLUME",
            type: "TARGET",
            targetPrescriptionDose: 78.0
        )
        let doseRef2 = DoseReference(
            number: 2,
            structureType: "VOLUME",
            type: "ORGAN_AT_RISK",
            organAtRiskMaximumDose: 45.0
        )
        
        let plan = RTPlan(
            sopInstanceUID: "1.2.3.4.5",
            doseReferences: [doseRef1, doseRef2]
        )
        
        XCTAssertEqual(plan.doseReferences.count, 2)
        XCTAssertEqual(plan.doseReferences[0].number, 1)
        XCTAssertEqual(plan.doseReferences[0].targetPrescriptionDose, 78.0)
        XCTAssertEqual(plan.doseReferences[1].number, 2)
        XCTAssertEqual(plan.doseReferences[1].organAtRiskMaximumDose, 45.0)
    }
    
    func test_rtPlan_withFractionGroups() {
        let fractionGroup = FractionGroup(
            number: 1,
            description: "Initial treatment",
            numberOfFractionsPlanned: 39,
            numberOfFractionsPerDay: 1,
            referencedBeamNumbers: [1, 2, 3]
        )
        
        let plan = RTPlan(
            sopInstanceUID: "1.2.3.4.5",
            fractionGroups: [fractionGroup]
        )
        
        XCTAssertEqual(plan.numberOfFractionGroups, 1)
        XCTAssertEqual(plan.fractionGroups[0].numberOfFractionsPlanned, 39)
        XCTAssertEqual(plan.fractionGroups[0].referencedBeamNumbers, [1, 2, 3])
    }
    
    func test_rtPlan_withBeams() {
        let beam1 = RTBeam(
            number: 1,
            name: "AP Beam",
            type: "STATIC",
            radiationType: "PHOTON"
        )
        let beam2 = RTBeam(
            number: 2,
            name: "PA Beam",
            type: "STATIC",
            radiationType: "PHOTON"
        )
        
        let plan = RTPlan(
            sopInstanceUID: "1.2.3.4.5",
            beams: [beam1, beam2]
        )
        
        XCTAssertEqual(plan.numberOfBeams, 2)
        XCTAssertEqual(plan.beams[0].name, "AP Beam")
        XCTAssertEqual(plan.beams[1].name, "PA Beam")
    }
    
    // MARK: - DoseReference Tests
    
    func test_doseReference_initialization() {
        let doseRef = DoseReference(
            number: 1,
            uid: "1.2.3.4.5.6",
            structureType: "VOLUME",
            description: "PTV prescription",
            type: "TARGET",
            targetPrescriptionDose: 78.0,
            targetMaximumDose: 82.0,
            targetMinimumDose: 74.0,
            referencedROINumber: 1
        )
        
        XCTAssertEqual(doseRef.number, 1)
        XCTAssertEqual(doseRef.uid, "1.2.3.4.5.6")
        XCTAssertEqual(doseRef.structureType, "VOLUME")
        XCTAssertEqual(doseRef.description, "PTV prescription")
        XCTAssertEqual(doseRef.type, "TARGET")
        XCTAssertEqual(doseRef.targetPrescriptionDose, 78.0)
        XCTAssertEqual(doseRef.targetMaximumDose, 82.0)
        XCTAssertEqual(doseRef.targetMinimumDose, 74.0)
        XCTAssertEqual(doseRef.referencedROINumber, 1)
    }
    
    func test_doseReference_identifiable() {
        let doseRef = DoseReference(number: 42, type: "TARGET")
        XCTAssertEqual(doseRef.id, 42)
    }
    
    // MARK: - FractionGroup Tests
    
    func test_fractionGroup_initialization() {
        let fractionGroup = FractionGroup(
            number: 1,
            description: "Treatment phase 1",
            numberOfFractionsPlanned: 30,
            numberOfFractionsPerDay: 1,
            repeatFractionCycleLength: 5,
            fractionPattern: "11111",
            numberOfBeams: 5,
            referencedBeamNumbers: [1, 2, 3, 4, 5],
            numberOfBrachyApplicationSetups: 0,
            referencedBrachyApplicationSetupNumbers: []
        )
        
        XCTAssertEqual(fractionGroup.number, 1)
        XCTAssertEqual(fractionGroup.description, "Treatment phase 1")
        XCTAssertEqual(fractionGroup.numberOfFractionsPlanned, 30)
        XCTAssertEqual(fractionGroup.numberOfFractionsPerDay, 1)
        XCTAssertEqual(fractionGroup.repeatFractionCycleLength, 5)
        XCTAssertEqual(fractionGroup.fractionPattern, "11111")
        XCTAssertEqual(fractionGroup.numberOfBeams, 5)
        XCTAssertEqual(fractionGroup.referencedBeamNumbers.count, 5)
    }
    
    func test_fractionGroup_identifiable() {
        let fractionGroup = FractionGroup(number: 2)
        XCTAssertEqual(fractionGroup.id, 2)
    }
    
    // MARK: - BrachyApplicationSetup Tests
    
    func test_brachyApplicationSetup_initialization() {
        let channel1 = BrachyChannel(
            number: 1,
            length: 150.0,
            totalTime: 300.0,
            sourceIsotopeName: "Ir-192"
        )
        
        let setup = BrachyApplicationSetup(
            number: 1,
            type: "HDR",
            name: "Prostate HDR",
            manufacturer: "Varian",
            templateName: "Standard Prostate Template",
            templateType: "STANDARD",
            totalReferenceAirKerma: 1.5,
            channels: [channel1]
        )
        
        XCTAssertEqual(setup.number, 1)
        XCTAssertEqual(setup.type, "HDR")
        XCTAssertEqual(setup.name, "Prostate HDR")
        XCTAssertEqual(setup.manufacturer, "Varian")
        XCTAssertEqual(setup.templateName, "Standard Prostate Template")
        XCTAssertEqual(setup.templateType, "STANDARD")
        XCTAssertEqual(setup.totalReferenceAirKerma, 1.5)
        XCTAssertEqual(setup.channels.count, 1)
    }
    
    func test_brachyApplicationSetup_identifiable() {
        let setup = BrachyApplicationSetup(number: 3, type: "LDR")
        XCTAssertEqual(setup.id, 3)
    }
    
    // MARK: - BrachyChannel Tests
    
    func test_brachyChannel_initialization() {
        let controlPoint1 = BrachyControlPoint(
            index: 0,
            relativePosition: 0.0,
            cumulativeTimeWeight: 0.0
        )
        let controlPoint2 = BrachyControlPoint(
            index: 1,
            relativePosition: 10.0,
            cumulativeTimeWeight: 0.5
        )
        
        let channel = BrachyChannel(
            number: 1,
            length: 150.0,
            totalTime: 600.0,
            sourceIsotopeName: "Ir-192",
            sourceIsotopeHalfLife: 73.83,
            referenceAirKermaRate: 40800.0,
            controlPoints: [controlPoint1, controlPoint2]
        )
        
        XCTAssertEqual(channel.number, 1)
        XCTAssertEqual(channel.length, 150.0)
        XCTAssertEqual(channel.totalTime, 600.0)
        XCTAssertEqual(channel.sourceIsotopeName, "Ir-192")
        XCTAssertEqual(channel.sourceIsotopeHalfLife, 73.83)
        XCTAssertEqual(channel.referenceAirKermaRate, 40800.0)
        XCTAssertEqual(channel.controlPoints.count, 2)
    }
    
    // MARK: - BrachyControlPoint Tests
    
    func test_brachyControlPoint_initialization() {
        let position = Point3D(x: 10.0, y: 20.0, z: 30.0)
        let controlPoint = BrachyControlPoint(
            index: 5,
            relativePosition: 25.5,
            position3D: position,
            cumulativeTimeWeight: 0.75
        )
        
        XCTAssertEqual(controlPoint.index, 5)
        XCTAssertEqual(controlPoint.relativePosition, 25.5)
        XCTAssertEqual(controlPoint.position3D?.x, 10.0)
        XCTAssertEqual(controlPoint.position3D?.y, 20.0)
        XCTAssertEqual(controlPoint.position3D?.z, 30.0)
        XCTAssertEqual(controlPoint.cumulativeTimeWeight, 0.75)
    }

    // MARK: - 2026a term enums (PS3.3 Tables C.8-45, C.8-46, C.8-51)

    func test_rtPlanGeometry_rawValues() {
        XCTAssertEqual(RTPlanGeometry.allCases.map(\.rawValue), ["PATIENT", "TREATMENT_DEVICE"])
        XCTAssertEqual(RTPlan(sopInstanceUID: "1", geometry: "TREATMENT_DEVICE").planGeometry, .treatmentDevice)
        XCTAssertNil(RTPlan(sopInstanceUID: "1").planGeometry)
    }

    func test_doseReference_terms_rawValues() {
        XCTAssertEqual(DoseReferenceStructureType.allCases.map(\.rawValue), ["POINT", "VOLUME", "COORDINATES", "SITE"])
        XCTAssertEqual(DoseReferenceType.allCases.map(\.rawValue), ["TARGET", "ORGAN_AT_RISK"])
        let ref = DoseReference(number: 1, structureType: "SITE", type: "TARGET")
        XCTAssertEqual(ref.structureTypeTerm, .site)
        XCTAssertEqual(ref.doseReferenceType, .target)
        XCTAssertNil(DoseReference(number: 2, structureType: "ROI", type: "OAR").structureTypeTerm)
        XCTAssertNil(DoseReference(number: 2, structureType: "ROI", type: "OAR").doseReferenceType)
    }

    func test_brachyApplicationSetupType_rawValues() {
        XCTAssertEqual(BrachyApplicationSetupType.allCases.map(\.rawValue), [
            "FLETCHER_SUIT", "DELCLOS", "BLOEDORN", "JOSLIN_FLYNN", "CHANDIGARH", "MANCHESTER", "HENSCHKE",
            "NASOPHARYNGEAL", "OESOPHAGEAL", "ENDOBRONCHIAL", "SYED_NEBLETT", "ENDORECTAL", "PERINEAL"
        ])
        XCTAssertEqual(BrachyApplicationSetup(number: 1, type: "MANCHESTER").setupType, .manchester)
        // MANUAL/HDR/MDR/LDR/PDR are Brachy Treatment Type (300A,0202) values, not Application Setup Types
        XCTAssertNil(BrachyApplicationSetup(number: 2, type: "HDR").setupType)
    }
}

// MARK: - RTPlanParserTests
//
// Round-trip tests for the RT General Plan (PS3.3 2026a Table C.8-45), RT Prescription (C.8-46),
// RT Fraction Scheme (C.8-49), RT Beams (C.8-50) and RT Brachy Application Setups (C.8-51)
// terms through RTPlanParser. Lives in this file because the DICOMKitTests target in
// Package.swift enumerates its RadiationTherapy sources explicitly.
final class RTPlanParserTests: XCTestCase {

    // MARK: - Helpers

    private func cs(_ tag: Tag, _ value: String) -> DataElement {
        DataElement(tag: tag, vr: .CS, length: UInt32(value.count), valueData: value.data(using: .ascii)!)
    }

    private func ds(_ tag: Tag, _ value: String) -> DataElement {
        DataElement(tag: tag, vr: .DS, length: UInt32(value.count), valueData: value.data(using: .ascii)!)
    }

    private func integerString(_ tag: Tag, _ value: Int) -> DataElement {
        let s = String(value)
        return DataElement(tag: tag, vr: .IS, length: UInt32(s.count), valueData: s.data(using: .ascii)!)
    }

    private func sequence(_ tag: Tag, _ items: [SequenceItem]) -> DataElement {
        DataElement(tag: tag, vr: .SQ, length: 0xFFFFFFFF, valueData: Data(), sequenceItems: items)
    }

    private func minimalPlan() -> [Tag: DataElement] {
        var elements: [Tag: DataElement] = [:]
        elements[.sopInstanceUID] = DataElement(tag: .sopInstanceUID, vr: .UI, length: 9, valueData: "1.2.3.4.5".data(using: .ascii)!)
        elements[.sopClassUID] = DataElement(tag: .sopClassUID, vr: .UI, length: 29, valueData: "1.2.840.10008.5.1.4.1.1.481.5".data(using: .ascii)!)
        return elements
    }

    // MARK: - RT General Plan Module (Table C.8-45)

    func test_parse_rtPlanGeometry() throws {
        for term in RTPlanGeometry.allCases {
            var elements = minimalPlan()
            elements[.rtPlanGeometry] = cs(.rtPlanGeometry, term.rawValue)
            let plan = try RTPlanParser.parse(from: DataSet(elements: Array(elements.values)))
            XCTAssertEqual(plan.geometry, term.rawValue)
            XCTAssertEqual(plan.planGeometry, term, term.rawValue)
        }
        XCTAssertEqual(RTPlanGeometry.allCases.map(\.rawValue), ["PATIENT", "TREATMENT_DEVICE"])
    }

    // MARK: - RT Prescription Module (Table C.8-46)

    func test_parse_doseReference_terms() throws {
        var elements = minimalPlan()
        var ref: [Tag: DataElement] = [:]
        ref[.doseReferenceNumber] = integerString(.doseReferenceNumber, 1)
        ref[.doseReferenceStructureType] = cs(.doseReferenceStructureType, "COORDINATES")
        ref[.doseReferenceType] = cs(.doseReferenceType, "ORGAN_AT_RISK")
        elements[.doseReferenceSequence] = sequence(.doseReferenceSequence, [SequenceItem(elements: ref)])

        let plan = try RTPlanParser.parse(from: DataSet(elements: Array(elements.values)))
        XCTAssertEqual(plan.doseReferences.count, 1)
        XCTAssertEqual(plan.doseReferences[0].structureType, "COORDINATES")
        XCTAssertEqual(plan.doseReferences[0].structureTypeTerm, .coordinates)
        XCTAssertEqual(plan.doseReferences[0].type, "ORGAN_AT_RISK")
        XCTAssertEqual(plan.doseReferences[0].doseReferenceType, .organAtRisk)
    }

    // MARK: - RT Fraction Scheme Module (Table C.8-49)

    /// Fraction Pattern (300A,007B) is VR LT (PS3.6): a string of 0's and 1's, 7 x digits-per-day x cycle length long.
    func test_parse_fractionPattern_LT() throws {
        var elements = minimalPlan()
        var group: [Tag: DataElement] = [:]
        group[.fractionGroupNumber] = integerString(.fractionGroupNumber, 1)
        group[.numberOfFractionsPlanned] = integerString(.numberOfFractionsPlanned, 5)
        group[.numberOfFractionPatternDigitsPerDay] = integerString(.numberOfFractionPatternDigitsPerDay, 1)
        group[.repeatFractionCycleLength] = integerString(.repeatFractionCycleLength, 1)
        let pattern = "1111100"   // Monday..Friday treated, weekend not
        group[.fractionPattern] = DataElement(tag: .fractionPattern, vr: .LT, length: UInt32(pattern.count), valueData: pattern.data(using: .ascii)!)
        group[.numberOfBeams] = integerString(.numberOfBeams, 0)
        elements[.fractionGroupSequence] = sequence(.fractionGroupSequence, [SequenceItem(elements: group)])

        let plan = try RTPlanParser.parse(from: DataSet(elements: Array(elements.values)))
        XCTAssertEqual(plan.fractionGroups.count, 1)
        let parsed = plan.fractionGroups[0]
        XCTAssertEqual(parsed.fractionPattern, pattern)
        XCTAssertEqual(parsed.fractionPattern?.count, 7 * 1 * 1)
        XCTAssertEqual(parsed.numberOfFractionsPerDay, 1)
        XCTAssertEqual(parsed.repeatFractionCycleLength, 1)
        XCTAssertEqual(parsed.numberOfFractionsPlanned, 5)
    }

    // MARK: - RT Beams Module (Table C.8-50)

    private func beamItem(number: Int, type: String, radiation: String, dosimeter: String,
                          delivery: String? = nil, highDose: String? = nil,
                          controlPoints: [SequenceItem] = []) -> SequenceItem {
        var beam: [Tag: DataElement] = [:]
        beam[.beamNumber] = integerString(.beamNumber, number)
        beam[.beamType] = cs(.beamType, type)
        beam[.radiationType] = cs(.radiationType, radiation)
        beam[.primaryDosimeterUnit] = cs(.primaryDosimeterUnit, dosimeter)
        if let delivery {
            beam[Tag(group: 0x300A, element: 0x00CE)] = cs(Tag(group: 0x300A, element: 0x00CE), delivery)
        }
        if let highDose {
            beam[Tag(group: 0x300A, element: 0x00C7)] = cs(Tag(group: 0x300A, element: 0x00C7), highDose)
        }
        if !controlPoints.isEmpty {
            beam[.controlPointSequence] = sequence(.controlPointSequence, controlPoints)
        }
        return SequenceItem(elements: beam)
    }

    func test_parse_beam_terms() throws {
        var elements = minimalPlan()
        elements[.beamSequence] = sequence(.beamSequence, [
            beamItem(number: 1, type: "STATIC", radiation: "PHOTON", dosimeter: "MU", delivery: "TREATMENT", highDose: "TBI"),
            beamItem(number: 2, type: "DYNAMIC", radiation: "ELECTRON", dosimeter: "MINUTE", delivery: "SETUP"),
            beamItem(number: 3, type: "ARC", radiation: "CARBON", dosimeter: "MINUTES", delivery: "PORTFILM"),
        ])

        let plan = try RTPlanParser.parse(from: DataSet(elements: Array(elements.values)))
        XCTAssertEqual(plan.beams.count, 3)

        let b1 = plan.beams[0]
        XCTAssertEqual(b1.type, "STATIC")
        XCTAssertEqual(b1.beamType, .static)
        XCTAssertEqual(b1.radiationType, "PHOTON")
        XCTAssertEqual(b1.radiationTypeTerm, .photon)
        XCTAssertEqual(b1.primaryDosimeterUnit, "MU")
        XCTAssertEqual(b1.primaryDosimeterUnitTerm, .monitorUnit)
        XCTAssertEqual(b1.treatmentDeliveryType, "TREATMENT")
        XCTAssertEqual(b1.treatmentDeliveryTypeTerm, .treatment)
        XCTAssertEqual(b1.highDoseTechniqueType, "TBI")
        XCTAssertEqual(b1.highDoseTechniqueTypeTerm, .totalBodyIrradiation)

        let b2 = plan.beams[1]
        XCTAssertEqual(b2.beamType, .dynamic)
        XCTAssertEqual(b2.radiationTypeTerm, .electron)
        XCTAssertEqual(b2.primaryDosimeterUnitTerm, .minute)
        XCTAssertEqual(b2.treatmentDeliveryTypeTerm, .setup)
        XCTAssertNil(b2.highDoseTechniqueType)
        XCTAssertNil(b2.highDoseTechniqueTypeTerm)

        // Non-standard strings are preserved, typed accessors are nil
        let b3 = plan.beams[2]
        XCTAssertEqual(b3.type, "ARC")
        XCTAssertNil(b3.beamType)
        XCTAssertEqual(b3.radiationType, "CARBON")
        XCTAssertNil(b3.radiationTypeTerm)
        XCTAssertEqual(b3.primaryDosimeterUnit, "MINUTES")
        XCTAssertNil(b3.primaryDosimeterUnitTerm)
        XCTAssertNil(b3.treatmentDeliveryTypeTerm)
    }

    func test_parse_allRadiationAndDeliveryTypes() throws {
        var elements = minimalPlan()
        let radiation = RadiationType.allCases
        let delivery = TreatmentDeliveryType.allCases
        var items: [SequenceItem] = []
        for i in 0..<max(radiation.count, delivery.count) {
            items.append(beamItem(number: i + 1, type: "STATIC",
                                  radiation: radiation[i % radiation.count].rawValue, dosimeter: "MU",
                                  delivery: delivery[i % delivery.count].rawValue))
        }
        elements[.beamSequence] = sequence(.beamSequence, items)

        let plan = try RTPlanParser.parse(from: DataSet(elements: Array(elements.values)))
        for (i, beam) in plan.beams.enumerated() {
            XCTAssertEqual(beam.radiationTypeTerm, radiation[i % radiation.count])
            XCTAssertEqual(beam.treatmentDeliveryTypeTerm, delivery[i % delivery.count])
        }
    }

    func test_parse_controlPoint_rotationDirections_and_beamLimitingDeviceType() throws {
        var bld: [Tag: DataElement] = [:]
        bld[.rtBeamLimitingDeviceType] = cs(.rtBeamLimitingDeviceType, "MLCX")
        bld[.leafJawPositions] = ds(.leafJawPositions, "-10\\10\\-20\\20")

        var cp: [Tag: DataElement] = [:]
        cp[.controlPointIndex] = integerString(.controlPointIndex, 0)
        cp[.gantryRotationDirection] = cs(.gantryRotationDirection, "CW")
        cp[.beamLimitingDeviceRotationDirection] = cs(.beamLimitingDeviceRotationDirection, "CC")
        cp[.patientSupportRotationDirection] = cs(.patientSupportRotationDirection, "NONE")
        cp[.beamLimitingDevicePositionSequence] = sequence(.beamLimitingDevicePositionSequence, [SequenceItem(elements: bld)])

        var elements = minimalPlan()
        elements[.beamSequence] = sequence(.beamSequence, [
            beamItem(number: 1, type: "DYNAMIC", radiation: "PROTON", dosimeter: "MU", controlPoints: [SequenceItem(elements: cp)])
        ])

        let plan = try RTPlanParser.parse(from: DataSet(elements: Array(elements.values)))
        let point = try XCTUnwrap(plan.beams.first?.controlPoints.first)
        XCTAssertEqual(point.gantryRotationDirection, "CW")
        XCTAssertEqual(point.gantryRotation, .clockwise)
        XCTAssertEqual(point.beamLimitingDeviceRotationDirection, "CC")
        XCTAssertEqual(point.beamLimitingDeviceRotation, .counterClockwise)
        XCTAssertEqual(point.patientSupportRotationDirection, "NONE")
        XCTAssertEqual(point.patientSupportRotation, RotationDirection.none)
        XCTAssertEqual(point.beamLimitingDevicePositions.count, 1)
        XCTAssertEqual(point.beamLimitingDevicePositions[0].type, "MLCX")
        XCTAssertEqual(point.beamLimitingDevicePositions[0].deviceType, .mlcX)
        XCTAssertEqual(point.beamLimitingDevicePositions[0].positions, [-10, 10, -20, 20])
    }

    // MARK: - RT Brachy Application Setups Module (Table C.8-51)

    func test_parse_brachyApplicationSetupType() throws {
        var elements = minimalPlan()
        var setup: [Tag: DataElement] = [:]
        setup[.applicationSetupNumber] = integerString(.applicationSetupNumber, 1)
        setup[.applicationSetupType] = cs(.applicationSetupType, "FLETCHER_SUIT")
        var legacy: [Tag: DataElement] = [:]
        legacy[.applicationSetupNumber] = integerString(.applicationSetupNumber, 2)
        legacy[.applicationSetupType] = cs(.applicationSetupType, "HDR")   // a Brachy Treatment Type value, not a setup type
        elements[.brachyApplicationSetupSequence] = sequence(.brachyApplicationSetupSequence, [
            SequenceItem(elements: setup), SequenceItem(elements: legacy)
        ])

        let plan = try RTPlanParser.parse(from: DataSet(elements: Array(elements.values)))
        XCTAssertEqual(plan.brachyApplicationSetups.count, 2)
        XCTAssertEqual(plan.brachyApplicationSetups[0].type, "FLETCHER_SUIT")
        XCTAssertEqual(plan.brachyApplicationSetups[0].setupType, .fletcherSuit)
        XCTAssertEqual(plan.brachyApplicationSetups[1].type, "HDR")
        XCTAssertNil(plan.brachyApplicationSetups[1].setupType)
    }
}
