//
// RTStructureSetParserTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class RTStructureSetParserTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    /// Create a minimal RT Structure Set data set for testing
    private func createMinimalRTStructureSet() -> [Tag: DataElement] {
        var elements: [Tag: DataElement] = [:]
        
        // SOP Instance UID
        elements[.sopInstanceUID] = DataElement(
            tag: .sopInstanceUID,
            vr: .UI,
            length: 20,
            valueData: "1.2.3.4.5.6.7.8.9.10".data(using: .utf8)!
        )
        
        // SOP Class UID (RT Structure Set Storage)
        elements[.sopClassUID] = DataElement(
            tag: .sopClassUID,
            vr: .UI,
            length: 30,
            valueData: "1.2.840.10008.5.1.4.1.1.481.3".data(using: .utf8)!
        )
        
        return elements
    }
    
    /// Create a test data set with structure set attributes
    private func createStructureSetWithAttributes() -> [Tag: DataElement] {
        var elements = createMinimalRTStructureSet()
        
        // Structure Set Label
        elements[.structureSetLabel] = DataElement(
            tag: .structureSetLabel,
            vr: .SH,
            length: 15,
            valueData: "Test Structure".data(using: .utf8)!
        )
        
        // Structure Set Name
        elements[.structureSetName] = DataElement(
            tag: .structureSetName,
            vr: .LO,
            length: 12,
            valueData: "Prostate Plan".data(using: .utf8)!
        )
        
        // Structure Set Description
        elements[.structureSetDescription] = DataElement(
            tag: .structureSetDescription,
            vr: .ST,
            length: 25,
            valueData: "Test RT Structure Set".data(using: .utf8)!
        )
        
        return elements
    }
    
    /// Create a Structure Set ROI sequence item
    private func createROIItem(number: Int, name: String) -> SequenceItem {
        var elements: [Tag: DataElement] = [:]
        
        elements[.roiNumber] = DataElement(
            tag: .roiNumber,
            vr: .IS,
            length: UInt32(String(number).count),
            valueData: String(number).data(using: .ascii)!
        )
        
        elements[.roiName] = DataElement(
            tag: .roiName,
            vr: .LO,
            length: UInt32(name.count),
            valueData: name.data(using: .utf8)!
        )
        
        return SequenceItem(elements: elements)
    }
    
    // MARK: - Basic Parsing Tests
    
    func test_parse_minimalRTStructureSet() throws {
        let elements = createMinimalRTStructureSet()
        let dataSet = DataSet(elements: Array(elements.values))
        
        let structureSet = try RTStructureSetParser.parse(from: dataSet)
        
        XCTAssertEqual(structureSet.sopInstanceUID, "1.2.3.4.5.6.7.8.9.10")
        XCTAssertEqual(structureSet.sopClassUID, "1.2.840.10008.5.1.4.1.1.481.3")
        XCTAssertNil(structureSet.label)
        XCTAssertNil(structureSet.name)
        XCTAssertEqual(structureSet.rois.count, 0)
    }
    
    func test_parse_missingSopInstanceUID_throwsError() {
        var elements = createMinimalRTStructureSet()
        elements.removeValue(forKey: .sopInstanceUID)
        let dataSet = DataSet(elements: Array(elements.values))
        
        XCTAssertThrowsError(try RTStructureSetParser.parse(from: dataSet)) { error in
            guard case DICOMError.parsingFailed = error else {
                XCTFail("Expected parsingFailed error")
                return
            }
        }
    }
    
    func test_parse_structureSetAttributes() throws {
        let elements = createStructureSetWithAttributes()
        let dataSet = DataSet(elements: Array(elements.values))
        
        let structureSet = try RTStructureSetParser.parse(from: dataSet)
        
        XCTAssertEqual(structureSet.label, "Test Structure")
        XCTAssertEqual(structureSet.name, "Prostate Plan")
        XCTAssertEqual(structureSet.description, "Test RT Structure Set")
    }
    
    // MARK: - ROI Parsing Tests
    
    func test_parse_structureSetROISequence_single() throws {
        var elements = createMinimalRTStructureSet()
        
        let roiItem = createROIItem(number: 1, name: "PTV")
        elements[.structureSetROISequence] = DataElement(
            tag: .structureSetROISequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [roiItem]
        )
        
        let dataSet = DataSet(elements: Array(elements.values))
        let structureSet = try RTStructureSetParser.parse(from: dataSet)
        
        XCTAssertEqual(structureSet.rois.count, 1)
        XCTAssertEqual(structureSet.rois[0].number, 1)
        XCTAssertEqual(structureSet.rois[0].name, "PTV")
    }
    
    func test_parse_structureSetROISequence_multiple() throws {
        var elements = createMinimalRTStructureSet()
        
        let roi1 = createROIItem(number: 1, name: "PTV")
        let roi2 = createROIItem(number: 2, name: "Bladder")
        let roi3 = createROIItem(number: 3, name: "Rectum")
        
        elements[.structureSetROISequence] = DataElement(
            tag: .structureSetROISequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [roi1, roi2, roi3]
        )
        
        let dataSet = DataSet(elements: Array(elements.values))
        let structureSet = try RTStructureSetParser.parse(from: dataSet)
        
        XCTAssertEqual(structureSet.rois.count, 3)
        XCTAssertEqual(structureSet.rois[0].name, "PTV")
        XCTAssertEqual(structureSet.rois[1].name, "Bladder")
        XCTAssertEqual(structureSet.rois[2].name, "Rectum")
    }
    
    func test_parse_roiWithDescription() throws {
        var elements = createMinimalRTStructureSet()
        
        var roiElements: [Tag: DataElement] = [:]
        roiElements[.roiNumber] = DataElement(
            tag: .roiNumber,
            vr: .IS,
            length: 1,
            valueData: "1".data(using: .ascii)!
        )
        roiElements[.roiName] = DataElement(
            tag: .roiName,
            vr: .LO,
            length: 3,
            valueData: "PTV".data(using: .utf8)!
        )
        roiElements[.roiDescription] = DataElement(
            tag: .roiDescription,
            vr: .ST,
            length: 24,
            valueData: "Planning Target Volume".data(using: .utf8)!
        )
        
        let roiItem = SequenceItem(elements: roiElements)
        elements[.structureSetROISequence] = DataElement(
            tag: .structureSetROISequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [roiItem]
        )
        
        let dataSet = DataSet(elements: Array(elements.values))
        let structureSet = try RTStructureSetParser.parse(from: dataSet)
        
        XCTAssertEqual(structureSet.rois.count, 1)
        XCTAssertEqual(structureSet.rois[0].description, "Planning Target Volume")
    }
    
    // MARK: - ROI Contour Parsing Tests
    
    func test_parse_roiContourSequence_withColor() throws {
        var elements = createMinimalRTStructureSet()
        
        var contourElements: [Tag: DataElement] = [:]
        contourElements[.referencedROINumber] = DataElement(
            tag: .referencedROINumber,
            vr: .IS,
            length: 1,
            valueData: "1".data(using: .ascii)!
        )
        contourElements[.roiDisplayColor] = DataElement(
            tag: .roiDisplayColor,
            vr: .IS,
            length: 11,
            valueData: "255\\128\\64".data(using: .ascii)!
        )
        
        let contourItem = SequenceItem(elements: contourElements)
        elements[.roiContourSequence] = DataElement(
            tag: .roiContourSequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [contourItem]
        )
        
        let dataSet = DataSet(elements: Array(elements.values))
        let structureSet = try RTStructureSetParser.parse(from: dataSet)
        
        XCTAssertEqual(structureSet.roiContours.count, 1)
        XCTAssertEqual(structureSet.roiContours[0].roiNumber, 1)
        XCTAssertEqual(structureSet.roiContours[0].displayColor?.red, 255)
        XCTAssertEqual(structureSet.roiContours[0].displayColor?.green, 128)
        XCTAssertEqual(structureSet.roiContours[0].displayColor?.blue, 64)
    }
    
    func test_parse_contourSequence() throws {
        var elements = createMinimalRTStructureSet()
        
        // Create a contour item
        var contourItemElements: [Tag: DataElement] = [:]
        contourItemElements[.contourGeometricType] = DataElement(
            tag: .contourGeometricType,
            vr: .CS,
            length: 13,
            valueData: "CLOSED_PLANAR".data(using: .ascii)!
        )
        contourItemElements[.numberOfContourPoints] = DataElement(
            tag: .numberOfContourPoints,
            vr: .IS,
            length: 1,
            valueData: "4".data(using: .ascii)!
        )
        
        // Contour data: 4 points forming a square
        let contourData = "0.0\\0.0\\0.0\\10.0\\0.0\\0.0\\10.0\\10.0\\0.0\\0.0\\10.0\\0.0"
        contourItemElements[.contourData] = DataElement(
            tag: .contourData,
            vr: .DS,
            length: UInt32(contourData.count),
            valueData: contourData.data(using: .ascii)!
        )
        
        let contourItem = SequenceItem(elements: contourItemElements)
        
        // Create ROI contour with the contour sequence
        var roiContourElements: [Tag: DataElement] = [:]
        roiContourElements[.referencedROINumber] = DataElement(
            tag: .referencedROINumber,
            vr: .IS,
            length: 1,
            valueData: "1".data(using: .ascii)!
        )
        roiContourElements[.contourSequence] = DataElement(
            tag: .contourSequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [contourItem]
        )
        
        let roiContourItem = SequenceItem(elements: roiContourElements)
        elements[.roiContourSequence] = DataElement(
            tag: .roiContourSequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [roiContourItem]
        )
        
        let dataSet = DataSet(elements: Array(elements.values))
        let structureSet = try RTStructureSetParser.parse(from: dataSet)
        
        XCTAssertEqual(structureSet.roiContours.count, 1)
        XCTAssertEqual(structureSet.roiContours[0].contours.count, 1)
        
        let contour = structureSet.roiContours[0].contours[0]
        XCTAssertEqual(contour.geometricType, .closedPlanar)
        XCTAssertEqual(contour.numberOfPoints, 4)
        XCTAssertEqual(contour.points.count, 4)
        XCTAssertEqual(contour.points[0].x, 0.0)
        XCTAssertEqual(contour.points[0].y, 0.0)
        XCTAssertEqual(contour.points[0].z, 0.0)
        XCTAssertEqual(contour.points[3].x, 0.0)
        XCTAssertEqual(contour.points[3].y, 10.0)
        XCTAssertEqual(contour.points[3].z, 0.0)
    }
    
    // MARK: - RT ROI Observations Tests
    
    func test_parse_rtROIObservationsSequence() throws {
        var elements = createMinimalRTStructureSet()
        
        var obsElements: [Tag: DataElement] = [:]
        obsElements[.observationNumber] = DataElement(
            tag: .observationNumber,
            vr: .IS,
            length: 1,
            valueData: "1".data(using: .ascii)!
        )
        obsElements[.referencedROINumber] = DataElement(
            tag: .referencedROINumber,
            vr: .IS,
            length: 1,
            valueData: "1".data(using: .ascii)!
        )
        obsElements[.rtROIInterpretedType] = DataElement(
            tag: .rtROIInterpretedType,
            vr: .CS,
            length: 3,
            valueData: "PTV".data(using: .ascii)!
        )
        obsElements[.roiInterpreter] = DataElement(
            tag: .roiInterpreter,
            vr: .PN,
            length: 8,
            valueData: "Dr.Smith".data(using: .utf8)!
        )
        
        let obsItem = SequenceItem(elements: obsElements)
        elements[.rtROIObservationsSequence] = DataElement(
            tag: .rtROIObservationsSequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [obsItem]
        )
        
        let dataSet = DataSet(elements: Array(elements.values))
        let structureSet = try RTStructureSetParser.parse(from: dataSet)
        
        XCTAssertEqual(structureSet.roiObservations.count, 1)
        XCTAssertEqual(structureSet.roiObservations[0].observationNumber, 1)
        XCTAssertEqual(structureSet.roiObservations[0].referencedROINumber, 1)
        XCTAssertEqual(structureSet.roiObservations[0].interpretedType, .ptv)
        XCTAssertEqual(structureSet.roiObservations[0].interpreter, "Dr.Smith")
    }
    
    func test_parse_rtROIObservations_withPhysicalProperties() throws {
        var elements = createMinimalRTStructureSet()
        
        // Create physical property item
        var propElements: [Tag: DataElement] = [:]
        propElements[.roiPhysicalProperty] = DataElement(
            tag: .roiPhysicalProperty,
            vr: .CS,
            length: 16,
            valueData: "REL_ELEC_DENSITY".data(using: .ascii)!
        )
        propElements[.roiPhysicalPropertyValue] = DataElement(
            tag: .roiPhysicalPropertyValue,
            vr: .DS,
            length: 4,
            valueData: "1.05".data(using: .ascii)!
        )
        let propItem = SequenceItem(elements: propElements)
        
        // Create observation item with physical properties
        var obsElements: [Tag: DataElement] = [:]
        obsElements[.observationNumber] = DataElement(
            tag: .observationNumber,
            vr: .IS,
            length: 1,
            valueData: "1".data(using: .ascii)!
        )
        obsElements[.referencedROINumber] = DataElement(
            tag: .referencedROINumber,
            vr: .IS,
            length: 1,
            valueData: "1".data(using: .ascii)!
        )
        obsElements[.roiPhysicalPropertiesSequence] = DataElement(
            tag: .roiPhysicalPropertiesSequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [propItem]
        )
        
        let obsItem = SequenceItem(elements: obsElements)
        elements[.rtROIObservationsSequence] = DataElement(
            tag: .rtROIObservationsSequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [obsItem]
        )
        
        let dataSet = DataSet(elements: Array(elements.values))
        let structureSet = try RTStructureSetParser.parse(from: dataSet)
        
        XCTAssertEqual(structureSet.roiObservations.count, 1)
        XCTAssertEqual(structureSet.roiObservations[0].physicalProperties.count, 1)
        XCTAssertEqual(structureSet.roiObservations[0].physicalProperties[0].property, "REL_ELEC_DENSITY")
        XCTAssertEqual(structureSet.roiObservations[0].physicalProperties[0].value, 1.05)
    }
    
    // MARK: - Contour Point Parsing Tests
    
    func test_parseContourPoints_singlePoint() throws {
        var elements = createMinimalRTStructureSet()
        
        var contourItemElements: [Tag: DataElement] = [:]
        contourItemElements[.contourGeometricType] = DataElement(
            tag: .contourGeometricType,
            vr: .CS,
            length: 5,
            valueData: "POINT".data(using: .ascii)!
        )
        contourItemElements[.numberOfContourPoints] = DataElement(
            tag: .numberOfContourPoints,
            vr: .IS,
            length: 1,
            valueData: "1".data(using: .ascii)!
        )
        contourItemElements[.contourData] = DataElement(
            tag: .contourData,
            vr: .DS,
            length: 13,
            valueData: "5.5\\10.3\\-2.7".data(using: .ascii)!
        )
        
        let contourItem = SequenceItem(elements: contourItemElements)
        
        var roiContourElements: [Tag: DataElement] = [:]
        roiContourElements[.referencedROINumber] = DataElement(
            tag: .referencedROINumber,
            vr: .IS,
            length: 1,
            valueData: "1".data(using: .ascii)!
        )
        roiContourElements[.contourSequence] = DataElement(
            tag: .contourSequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [contourItem]
        )
        
        let roiContourItem = SequenceItem(elements: roiContourElements)
        elements[.roiContourSequence] = DataElement(
            tag: .roiContourSequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [roiContourItem]
        )
        
        let dataSet = DataSet(elements: Array(elements.values))
        let structureSet = try RTStructureSetParser.parse(from: dataSet)
        
        let contour = structureSet.roiContours[0].contours[0]
        XCTAssertEqual(contour.geometricType, .point)
        XCTAssertEqual(contour.points.count, 1)
        XCTAssertEqual(contour.points[0].x, 5.5, accuracy: 0.01)
        XCTAssertEqual(contour.points[0].y, 10.3, accuracy: 0.01)
        XCTAssertEqual(contour.points[0].z, -2.7, accuracy: 0.01)
    }
    
    // MARK: - Integration Tests
    
    func test_parse_completeRTStructureSet() throws {
        var elements = createStructureSetWithAttributes()
        
        // Add ROIs
        let roi1 = createROIItem(number: 1, name: "PTV")
        let roi2 = createROIItem(number: 2, name: "Bladder")
        elements[.structureSetROISequence] = DataElement(
            tag: .structureSetROISequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [roi1, roi2]
        )
        
        // Add ROI contours with color
        var contour1Elements: [Tag: DataElement] = [:]
        contour1Elements[.referencedROINumber] = DataElement(
            tag: .referencedROINumber,
            vr: .IS,
            length: 1,
            valueData: "1".data(using: .ascii)!
        )
        contour1Elements[.roiDisplayColor] = DataElement(
            tag: .roiDisplayColor,
            vr: .IS,
            length: 9,
            valueData: "255\\0\\0".data(using: .ascii)!
        )
        
        var contour2Elements: [Tag: DataElement] = [:]
        contour2Elements[.referencedROINumber] = DataElement(
            tag: .referencedROINumber,
            vr: .IS,
            length: 1,
            valueData: "2".data(using: .ascii)!
        )
        contour2Elements[.roiDisplayColor] = DataElement(
            tag: .roiDisplayColor,
            vr: .IS,
            length: 11,
            valueData: "0\\255\\128".data(using: .ascii)!
        )
        
        elements[.roiContourSequence] = DataElement(
            tag: .roiContourSequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [
                SequenceItem(elements: contour1Elements),
                SequenceItem(elements: contour2Elements)
            ]
        )
        
        // Add ROI observations
        var obs1Elements: [Tag: DataElement] = [:]
        obs1Elements[.observationNumber] = DataElement(
            tag: .observationNumber,
            vr: .IS,
            length: 1,
            valueData: "1".data(using: .ascii)!
        )
        obs1Elements[.referencedROINumber] = DataElement(
            tag: .referencedROINumber,
            vr: .IS,
            length: 1,
            valueData: "1".data(using: .ascii)!
        )
        obs1Elements[.rtROIInterpretedType] = DataElement(
            tag: .rtROIInterpretedType,
            vr: .CS,
            length: 3,
            valueData: "PTV".data(using: .ascii)!
        )
        
        var obs2Elements: [Tag: DataElement] = [:]
        obs2Elements[.observationNumber] = DataElement(
            tag: .observationNumber,
            vr: .IS,
            length: 1,
            valueData: "2".data(using: .ascii)!
        )
        obs2Elements[.referencedROINumber] = DataElement(
            tag: .referencedROINumber,
            vr: .IS,
            length: 1,
            valueData: "2".data(using: .ascii)!
        )
        obs2Elements[.rtROIInterpretedType] = DataElement(
            tag: .rtROIInterpretedType,
            vr: .CS,
            length: 5,
            valueData: "ORGAN".data(using: .ascii)!
        )
        
        elements[.rtROIObservationsSequence] = DataElement(
            tag: .rtROIObservationsSequence,
            vr: .SQ,
            length: 0xFFFFFFFF,
            valueData: Data(),
            sequenceItems: [
                SequenceItem(elements: obs1Elements),
                SequenceItem(elements: obs2Elements)
            ]
        )
        
        let dataSet = DataSet(elements: Array(elements.values))
        let structureSet = try RTStructureSetParser.parse(from: dataSet)
        
        // Verify structure set attributes
        XCTAssertEqual(structureSet.label, "Test Structure")
        XCTAssertEqual(structureSet.name, "Prostate Plan")
        
        // Verify ROIs
        XCTAssertEqual(structureSet.rois.count, 2)
        XCTAssertEqual(structureSet.rois[0].number, 1)
        XCTAssertEqual(structureSet.rois[0].name, "PTV")
        XCTAssertEqual(structureSet.rois[1].number, 2)
        XCTAssertEqual(structureSet.rois[1].name, "Bladder")
        
        // Verify ROI contours
        XCTAssertEqual(structureSet.roiContours.count, 2)
        XCTAssertEqual(structureSet.roiContours[0].displayColor?.red, 255)
        XCTAssertEqual(structureSet.roiContours[0].displayColor?.green, 0)
        XCTAssertEqual(structureSet.roiContours[0].displayColor?.blue, 0)
        XCTAssertEqual(structureSet.roiContours[1].displayColor?.red, 0)
        XCTAssertEqual(structureSet.roiContours[1].displayColor?.green, 255)
        XCTAssertEqual(structureSet.roiContours[1].displayColor?.blue, 128)
        
        // Verify observations
        XCTAssertEqual(structureSet.roiObservations.count, 2)
        XCTAssertEqual(structureSet.roiObservations[0].interpretedType, .ptv)
        XCTAssertEqual(structureSet.roiObservations[1].interpretedType, .organ)
    }

    // MARK: - 2026a term round trips

    private func cs(_ tag: Tag, _ value: String) -> DataElement {
        DataElement(tag: tag, vr: .CS, length: UInt32(value.count), valueData: value.data(using: .ascii)!)
    }

    private func integerString(_ tag: Tag, _ value: Int) -> DataElement {
        let s = String(value)
        return DataElement(tag: tag, vr: .IS, length: UInt32(s.count), valueData: s.data(using: .ascii)!)
    }

    private func sequence(_ tag: Tag, _ items: [SequenceItem]) -> DataElement {
        DataElement(tag: tag, vr: .SQ, length: 0xFFFFFFFF, valueData: Data(), sequenceItems: items)
    }

    /// Contour Geometric Type (3006,0042) CLOSEDPLANAR_XOR (PS3.3 2026a Table C.8-42, C.8.8.6.3) parses.
    func test_parse_contourGeometricType_closedPlanarXOR() throws {
        var elements = createMinimalRTStructureSet()

        var contourElements: [Tag: DataElement] = [:]
        contourElements[.contourGeometricType] = cs(.contourGeometricType, "CLOSEDPLANAR_XOR")
        contourElements[.numberOfContourPoints] = integerString(.numberOfContourPoints, 3)
        let contourData = "0\\0\\0\\10\\0\\0\\0\\10\\0"
        contourElements[.contourData] = DataElement(
            tag: .contourData, vr: .DS, length: UInt32(contourData.count), valueData: contourData.data(using: .ascii)!)

        var roiContourElements: [Tag: DataElement] = [:]
        roiContourElements[.referencedROINumber] = integerString(.referencedROINumber, 1)
        roiContourElements[.contourSequence] = sequence(.contourSequence, [SequenceItem(elements: contourElements)])
        elements[.roiContourSequence] = sequence(.roiContourSequence, [SequenceItem(elements: roiContourElements)])

        let structureSet = try RTStructureSetParser.parse(from: DataSet(elements: Array(elements.values)))
        XCTAssertEqual(structureSet.roiContours[0].contours.count, 1)
        XCTAssertEqual(structureSet.roiContours[0].contours[0].geometricType, .closedPlanarXOR)
        XCTAssertEqual(structureSet.roiContours[0].contours[0].geometricType.rawValue, "CLOSEDPLANAR_XOR")
    }

    /// The 2026a RT ROI Interpreted Type terms added for P-RT (PS3.3 Table C.8-44) parse.
    func test_parse_rtROIInterpretedType_2026aTerms() throws {
        var elements = createMinimalRTStructureSet()

        let terms: [(String, RTROIInterpretedType)] = [
            ("OAR", .organAtRisk), ("BRACHY_CHANNEL", .brachyChannel), ("BRACHY_ACCESSORY", .brachyAccessory),
            ("BRACHY_SRC_APP", .brachySourceApplicator), ("BRACHY_CHNL_SHLD", .brachyChannelShield),
            ("DOSE_MEASUREMENT", .doseMeasurement), ("DEVICE", .device), ("IRRAD_VOLUME", .irradiatedVolume)
        ]
        let items = terms.enumerated().map { index, pair -> SequenceItem in
            var obs: [Tag: DataElement] = [:]
            obs[.observationNumber] = integerString(.observationNumber, index + 1)
            obs[.referencedROINumber] = integerString(.referencedROINumber, index + 1)
            obs[.rtROIInterpretedType] = cs(.rtROIInterpretedType, pair.0)
            return SequenceItem(elements: obs)
        }
        elements[.rtROIObservationsSequence] = sequence(.rtROIObservationsSequence, items)

        let structureSet = try RTStructureSetParser.parse(from: DataSet(elements: Array(elements.values)))
        XCTAssertEqual(structureSet.roiObservations.count, terms.count)
        for (index, pair) in terms.enumerated() {
            XCTAssertEqual(structureSet.roiObservations[index].interpretedType, pair.1, pair.0)
        }
    }

    /// ROI Generation Algorithm (Table C.8-41) and ROI Physical Property (Table C.8-44) typed accessors
    /// are populated from the parsed strings.
    func test_parse_roiGenerationAlgorithm_and_physicalPropertyTerms() throws {
        var elements = createMinimalRTStructureSet()

        var roi: [Tag: DataElement] = [:]
        roi[.roiNumber] = integerString(.roiNumber, 1)
        roi[.roiName] = DataElement(tag: .roiName, vr: .LO, length: 3, valueData: "PTV".data(using: .ascii)!)
        roi[.roiGenerationAlgorithm] = cs(.roiGenerationAlgorithm, "AUTOMATIC")
        elements[.structureSetROISequence] = sequence(.structureSetROISequence, [SequenceItem(elements: roi)])

        var prop: [Tag: DataElement] = [:]
        prop[.roiPhysicalProperty] = cs(.roiPhysicalProperty, "MEAN_EXCI_ENERGY")
        prop[.roiPhysicalPropertyValue] = DataElement(
            tag: .roiPhysicalPropertyValue, vr: .DS, length: 4, valueData: "75.0".data(using: .ascii)!)
        var obs: [Tag: DataElement] = [:]
        obs[.observationNumber] = integerString(.observationNumber, 1)
        obs[.referencedROINumber] = integerString(.referencedROINumber, 1)
        obs[.roiPhysicalPropertiesSequence] = sequence(.roiPhysicalPropertiesSequence, [SequenceItem(elements: prop)])
        elements[.rtROIObservationsSequence] = sequence(.rtROIObservationsSequence, [SequenceItem(elements: obs)])

        let structureSet = try RTStructureSetParser.parse(from: DataSet(elements: Array(elements.values)))
        XCTAssertEqual(structureSet.rois[0].generationAlgorithm, "AUTOMATIC")
        XCTAssertEqual(structureSet.rois[0].generationAlgorithmTerm, .automatic)
        XCTAssertEqual(structureSet.roiObservations[0].physicalProperties[0].propertyType, .meanExcitationEnergy)
        XCTAssertEqual(structureSet.roiObservations[0].physicalProperties[0].value, 75.0)
    }
}
