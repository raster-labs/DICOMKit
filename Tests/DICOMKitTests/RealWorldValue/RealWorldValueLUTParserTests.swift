//
// RealWorldValueLUTParserTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class RealWorldValueLUTParserTests: XCTestCase {
    
    // MARK: - Modality LUT Parsing Tests
    
    func test_parseModalityLUT_withCTRescale_parsesCorrectly() throws {
        var dataset = DataSet()
        
        dataset[Tag.rescaleSlope] = DataElement.float64(tag: Tag.rescaleSlope, value: 1.0)
        dataset[Tag.rescaleIntercept] = DataElement.float64(tag: Tag.rescaleIntercept, value: -1024.0)
        dataset[Tag.rescaleType] = DataElement.string(tag: Tag.rescaleType, vr: .LO, value: "HU")
        
        let luts = RealWorldValueLUTParser.parse(from: dataset)
        
        XCTAssertEqual(luts.count, 1)
        
        let lut = luts[0]
        XCTAssertEqual(lut.label, "HU")
        XCTAssertEqual(lut.measurementUnits.codeValue, "[hnsf'U]")
        
        // Test transformation
        if case .linear(let slope, let intercept) = lut.transformation {
            XCTAssertEqual(slope, 1.0, accuracy: 0.001)
            XCTAssertEqual(intercept, -1024.0, accuracy: 0.001)
        } else {
            XCTFail("Expected linear transformation")
        }
        
        // Verify transformation application
        XCTAssertEqual(lut.apply(to: 1024), 0.0, accuracy: 0.001) // Air in CT
        XCTAssertEqual(lut.apply(to: 2048), 1024.0, accuracy: 0.001) // Bone in CT
    }
    
    func test_parseModalityLUT_withoutRescaleType_usesRatio() throws {
        var dataset = DataSet()
        
        dataset[Tag.rescaleSlope] = DataElement.float64(tag: Tag.rescaleSlope, value: 2.0)
        dataset[Tag.rescaleIntercept] = DataElement.float64(tag: Tag.rescaleIntercept, value: 100.0)
        
        let luts = RealWorldValueLUTParser.parse(from: dataset)
        
        XCTAssertEqual(luts.count, 1)
        
        let lut = luts[0]
        XCTAssertEqual(lut.measurementUnits.codeValue, "1") // ratio
        XCTAssertNil(lut.quantityDefinition)
    }
    
    func test_parseModalityLUT_withOpticalDensity_parsesCorrectly() throws {
        var dataset = DataSet()
        
        dataset[Tag.rescaleSlope] = DataElement.float64(tag: Tag.rescaleSlope, value: 0.5)
        dataset[Tag.rescaleIntercept] = DataElement.float64(tag: Tag.rescaleIntercept, value: 0.0)
        dataset[Tag.rescaleType] = DataElement.string(tag: Tag.rescaleType, vr: .LO, value: "OD")
        
        let luts = RealWorldValueLUTParser.parse(from: dataset)
        
        XCTAssertEqual(luts.count, 1)
        
        let lut = luts[0]
        XCTAssertEqual(lut.label, "OD")
        XCTAssertEqual(lut.measurementUnits.codeValue, "{od}")
    }
    
    func test_parseModalityLUT_withoutRequiredFields_returnsEmpty() throws {
        var dataset = DataSet()
        
        // Only set slope, missing intercept
        dataset[Tag.rescaleSlope] = DataElement.float64(tag: Tag.rescaleSlope, value: 1.0)
        
        let luts = RealWorldValueLUTParser.parse(from: dataset)
        
        XCTAssertEqual(luts.count, 0)
    }
    
    // MARK: - Real World Value Mapping Sequence Parsing Tests
    
    func test_parseRWVMappingSequence_withLinearTransformation_parsesCorrectly() throws {
        var dataset = DataSet()
        
        // Create RWV Mapping Item
        var rwvMappingDS = DataSet()
        rwvMappingDS[Tag(group: 0x0040, element: 0x9210)] = DataElement.string(tag: Tag(group: 0x0040, element: 0x9210), vr: .LO, value: "ADC Mapping")
        rwvMappingDS[Tag.lutExplanation] = DataElement.string(tag: Tag.lutExplanation, vr: .LO, value: "Apparent Diffusion Coefficient")
        
        // Measurement Units Code Sequence
        var unitsDS = DataSet()
        unitsDS[Tag.codeValue] = DataElement.string(tag: Tag.codeValue, vr: .SH, value: "mm2/s")
        unitsDS[Tag.codingSchemeDesignator] = DataElement.string(tag: Tag.codingSchemeDesignator, vr: .SH, value: "UCUM")
        unitsDS[Tag.codeMeaning] = DataElement.string(tag: Tag.codeMeaning, vr: .LO, value: "square millimeter per second")
        rwvMappingDS.setSequence([SequenceItem(elements: unitsDS.allElements)], for: Tag(group: 0x0040, element: 0x08EA))
        
        // Quantity Definition Sequence
        var quantityDS = DataSet()
        quantityDS[Tag.codeValue] = DataElement.string(tag: Tag.codeValue, vr: .SH, value: "113041")
        quantityDS[Tag.codingSchemeDesignator] = DataElement.string(tag: Tag.codingSchemeDesignator, vr: .SH, value: "DCM")
        quantityDS[Tag.codeMeaning] = DataElement.string(tag: Tag.codeMeaning, vr: .LO, value: "Apparent Diffusion Coefficient")
        rwvMappingDS.setSequence([SequenceItem(elements: quantityDS.allElements)], for: Tag(group: 0x0040, element: 0x9220))
        
        // Real World Value Slope and Intercept
        rwvMappingDS[Tag(group: 0x0040, element: 0x9225)] = DataElement.float64(tag: Tag(group: 0x0040, element: 0x9225), value: 0.001)
        rwvMappingDS[Tag(group: 0x0040, element: 0x9224)] = DataElement.float64(tag: Tag(group: 0x0040, element: 0x9224), value: 0.0)
        
        // Create Shared Functional Groups
        var sharedFunctionalGroupDS = DataSet()
        sharedFunctionalGroupDS.setSequence([SequenceItem(elements: rwvMappingDS.allElements)], for: Tag(group: 0x0040, element: 0x9096))
        
        // Add to dataset
        dataset.setSequence([SequenceItem(elements: sharedFunctionalGroupDS.allElements)], for: Tag(group: 0x5200, element: 0x9229))
        
        let luts = RealWorldValueLUTParser.parse(from: dataset)
        
        XCTAssertEqual(luts.count, 1)
        
        let lut = luts[0]
        XCTAssertEqual(lut.label, "ADC Mapping")
        XCTAssertEqual(lut.explanation, "Apparent Diffusion Coefficient")
        XCTAssertEqual(lut.measurementUnits.codeValue, "mm2/s")
        XCTAssertEqual(lut.quantityDefinition?.codeValue, "113041")
        
        // Verify transformation
        if case .linear(let slope, let intercept) = lut.transformation {
            XCTAssertEqual(slope, 0.001, accuracy: 0.0001)
            XCTAssertEqual(intercept, 0.0, accuracy: 0.0001)
        } else {
            XCTFail("Expected linear transformation")
        }
        
        XCTAssertEqual(lut.apply(to: 1000), 1.0, accuracy: 0.0001)
    }
    
    // Note: LUT transformation test skipped - would require creating float64 array DataElement  
    // The LUT parsing is tested via RealWorldValueLUTTests
    
    func test_parseRWVMappingSequence_fromPerFrameFunctionalGroups_parsesCorrectly() throws {
        var dataset = DataSet()
        
        // Create RWV Mapping Item
        var rwvMappingDS = DataSet()
        rwvMappingDS[Tag(group: 0x0040, element: 0x9210)] = DataElement.string(tag: Tag(group: 0x0040, element: 0x9210), vr: .LO, value: "Frame LUT")
        
        // Measurement Units
        var unitsDS = DataSet()
        unitsDS[Tag.codeValue] = DataElement.string(tag: Tag.codeValue, vr: .SH, value: "ms")
        unitsDS[Tag.codingSchemeDesignator] = DataElement.string(tag: Tag.codingSchemeDesignator, vr: .SH, value: "UCUM")
        unitsDS[Tag.codeMeaning] = DataElement.string(tag: Tag.codeMeaning, vr: .LO, value: "millisecond")
        rwvMappingDS.setSequence([SequenceItem(elements: unitsDS.allElements)], for: Tag(group: 0x0040, element: 0x08EA))
        
        rwvMappingDS[Tag(group: 0x0040, element: 0x9225)] = DataElement.float64(tag: Tag(group: 0x0040, element: 0x9225), value: 2.0)
        rwvMappingDS[Tag(group: 0x0040, element: 0x9224)] = DataElement.float64(tag: Tag(group: 0x0040, element: 0x9224), value: 10.0)
        
        // Create Per-Frame Functional Groups
        var perFrameGroupDS = DataSet()
        perFrameGroupDS.setSequence([SequenceItem(elements: rwvMappingDS.allElements)], for: Tag(group: 0x0040, element: 0x9096))
        
        // Per-Frame Functional Groups Sequence (5200,9230)
        dataset.setSequence([SequenceItem(elements: perFrameGroupDS.allElements)], for: Tag(group: 0x5200, element: 0x9230))
        
        let luts = RealWorldValueLUTParser.parse(from: dataset)
        
        XCTAssertEqual(luts.count, 1)
        XCTAssertEqual(luts[0].label, "Frame LUT")
        XCTAssertEqual(luts[0].measurementUnits.codeValue, "ms")
    }
    
    // MARK: - Priority Tests (RWV Mapping over Modality LUT)
    
    func test_parse_withBothRWVAndModalityLUT_prefersRWV() throws {
        var dataset = DataSet()
        
        // Add Modality LUT (legacy)
        dataset[Tag.rescaleSlope] = DataElement.float64(tag: Tag.rescaleSlope, value: 1.0)
        dataset[Tag.rescaleIntercept] = DataElement.float64(tag: Tag.rescaleIntercept, value: -1024.0)
        dataset[Tag.rescaleType] = DataElement.string(tag: Tag.rescaleType, vr: .LO, value: "HU")
        
        // Add RWV Mapping Sequence (modern)
        var rwvMappingDS = DataSet()
        rwvMappingDS[Tag(group: 0x0040, element: 0x9210)] = DataElement.string(tag: Tag(group: 0x0040, element: 0x9210), vr: .LO, value: "RWV LUT")
        
        var unitsDS = DataSet()
        unitsDS[Tag.codeValue] = DataElement.string(tag: Tag.codeValue, vr: .SH, value: "[hnsf'U]")
        unitsDS[Tag.codingSchemeDesignator] = DataElement.string(tag: Tag.codingSchemeDesignator, vr: .SH, value: "UCUM")
        unitsDS[Tag.codeMeaning] = DataElement.string(tag: Tag.codeMeaning, vr: .LO, value: "Hounsfield unit")
        rwvMappingDS.setSequence([SequenceItem(elements: unitsDS.allElements)], for: Tag(group: 0x0040, element: 0x08EA))
        
        rwvMappingDS[Tag(group: 0x0040, element: 0x9225)] = DataElement.float64(tag: Tag(group: 0x0040, element: 0x9225), value: 1.5)
        rwvMappingDS[Tag(group: 0x0040, element: 0x9224)] = DataElement.float64(tag: Tag(group: 0x0040, element: 0x9224), value: -1000.0)
        
        var sharedFunctionalGroupDS = DataSet()
        sharedFunctionalGroupDS.setSequence([SequenceItem(elements: rwvMappingDS.allElements)], for: Tag(group: 0x0040, element: 0x9096))
        
        dataset.setSequence([SequenceItem(elements: sharedFunctionalGroupDS.allElements)], for: Tag(group: 0x5200, element: 0x9229))
        
        let luts = RealWorldValueLUTParser.parse(from: dataset)
        
        // Should parse RWV Mapping, not Modality LUT
        XCTAssertEqual(luts.count, 1)
        XCTAssertEqual(luts[0].label, "RWV LUT")
        
        if case .linear(let slope, _) = luts[0].transformation {
            XCTAssertEqual(slope, 1.5, accuracy: 0.001) // RWV slope, not modality slope
        } else {
            XCTFail("Expected linear transformation")
        }
    }
    
    func test_parse_withOnlyModalityLUT_fallsBackToModality() throws {
        var dataset = DataSet()
        
        // Only Modality LUT, no RWV Mapping
        dataset[Tag.rescaleSlope] = DataElement.float64(tag: Tag.rescaleSlope, value: 1.0)
        dataset[Tag.rescaleIntercept] = DataElement.float64(tag: Tag.rescaleIntercept, value: -1024.0)
        dataset[Tag.rescaleType] = DataElement.string(tag: Tag.rescaleType, vr: .LO, value: "HU")
        
        let luts = RealWorldValueLUTParser.parse(from: dataset)
        
        XCTAssertEqual(luts.count, 1)
        XCTAssertEqual(luts[0].label, "HU")
    }
    
    // MARK: - Edge Cases
    
    func test_parse_emptyDataSet_returnsEmpty() throws {
        let dataset = DataSet()
        
        let luts = RealWorldValueLUTParser.parse(from: dataset)
        
        XCTAssertEqual(luts.count, 0)
    }
    
    // MARK: - Integration Tests
    
    func test_parse_withRealWorldPETSUVData_parsesCorrectly() throws {
        var dataset = DataSet()
        
        var rwvMappingDS = DataSet()
        rwvMappingDS[Tag(group: 0x0040, element: 0x9210)] = DataElement.string(tag: Tag(group: 0x0040, element: 0x9210), vr: .LO, value: "SUVbw")
        rwvMappingDS[Tag.lutExplanation] = DataElement.string(tag: Tag.lutExplanation, vr: .LO, value: "Standardized Uptake Value body weight")
        
        var unitsDS = DataSet()
        unitsDS[Tag.codeValue] = DataElement.string(tag: Tag.codeValue, vr: .SH, value: "g/ml")
        unitsDS[Tag.codingSchemeDesignator] = DataElement.string(tag: Tag.codingSchemeDesignator, vr: .SH, value: "UCUM")
        unitsDS[Tag.codeMeaning] = DataElement.string(tag: Tag.codeMeaning, vr: .LO, value: "gram per milliliter")
        rwvMappingDS.setSequence([SequenceItem(elements: unitsDS.allElements)], for: Tag(group: 0x0040, element: 0x08EA))
        
        var quantityDS = DataSet()
        quantityDS[Tag.codeValue] = DataElement.string(tag: Tag.codeValue, vr: .SH, value: "126401")
        quantityDS[Tag.codingSchemeDesignator] = DataElement.string(tag: Tag.codingSchemeDesignator, vr: .SH, value: "DCM")
        quantityDS[Tag.codeMeaning] = DataElement.string(tag: Tag.codeMeaning, vr: .LO, value: "Standardized Uptake Value body weight")
        rwvMappingDS.setSequence([SequenceItem(elements: quantityDS.allElements)], for: Tag(group: 0x0040, element: 0x9220))
        
        // Typical PET SUV rescale
        rwvMappingDS[Tag(group: 0x0040, element: 0x9225)] = DataElement.float64(tag: Tag(group: 0x0040, element: 0x9225), value: 0.00012345)
        rwvMappingDS[Tag(group: 0x0040, element: 0x9224)] = DataElement.float64(tag: Tag(group: 0x0040, element: 0x9224), value: 0.0)
        
        var sharedFunctionalGroupDS = DataSet()
        sharedFunctionalGroupDS.setSequence([SequenceItem(elements: rwvMappingDS.allElements)], for: Tag(group: 0x0040, element: 0x9096))
        
        dataset.setSequence([SequenceItem(elements: sharedFunctionalGroupDS.allElements)], for: Tag(group: 0x5200, element: 0x9229))
        
        let luts = RealWorldValueLUTParser.parse(from: dataset)
        
        XCTAssertEqual(luts.count, 1)
        
        let lut = luts[0]
        XCTAssertEqual(lut.label, "SUVbw")
        XCTAssertEqual(lut.measurementUnits.codeValue, "g/ml")
        XCTAssertEqual(lut.quantityDefinition?.codeValue, "126401")
        
        // Verify transformation
        let testValue = 10000
        let result = lut.apply(to: testValue)
        XCTAssertEqual(result, 1.2345, accuracy: 0.0001)
    }
}
