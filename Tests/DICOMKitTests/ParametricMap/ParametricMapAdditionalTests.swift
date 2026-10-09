//
// ParametricMapAdditionalTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class ParametricMapAdditionalTests: XCTestCase {
    
    // MARK: - LUT Mapping Tests
    
    func test_realWorldValueMapping_lutTransformation_interpolation_succeeds() {
        let mapping = RealWorldValueMapping(
            label: "Test LUT",
            explanation: "Testing LUT interpolation",
            measurementUnits: .millisecond,
            mapping: .lut(firstValueMapped: 0.0, lastValueMapped: 100.0, lutData: [0.0, 50.0, 100.0])
        )
        
        XCTAssertEqual(mapping.label, "Test LUT")
        XCTAssertEqual(mapping.explanation, "Testing LUT interpolation")
        XCTAssertEqual(mapping.measurementUnits.codeValue, "ms")
        
        if case let .lut(first, last, data) = mapping.mapping {
            XCTAssertEqual(first, 0.0)
            XCTAssertEqual(last, 100.0)
            XCTAssertEqual(data.count, 3)
        } else {
            XCTFail("Expected LUT mapping")
        }
    }
    
    func test_realWorldValueMapping_lutTransformation_singleValue_succeeds() {
        let mapping = RealWorldValueMapping(
            measurementUnits: .ratio,
            mapping: .lut(firstValueMapped: 42.0, lastValueMapped: 42.0, lutData: [1.0])
        )
        
        if case let .lut(first, last, data) = mapping.mapping {
            XCTAssertEqual(first, 42.0)
            XCTAssertEqual(last, 42.0)
            XCTAssertEqual(data.count, 1)
            XCTAssertEqual(data[0], 1.0)
        } else {
            XCTFail("Expected LUT mapping")
        }
    }
    
    // MARK: - Measurement Units Tests
    
    func test_measurementUnits_allPredefinedUnits_haveUCUMScheme() {
        let units: [MeasurementUnits] = [
            .mm2PerSecond,
            .millisecond,
            .second,
            .gPerML,
            .perMinute,
            .ratio
        ]
        
        for unit in units {
            XCTAssertEqual(unit.codingSchemeDesignator, "UCUM")
            XCTAssertFalse(unit.codeValue.isEmpty)
            XCTAssertFalse(unit.codeMeaning.isEmpty)
        }
    }
    
    func test_measurementUnits_mm2PerSecond_hasCorrectValues() {
        let unit = MeasurementUnits.mm2PerSecond
        XCTAssertEqual(unit.codeValue, "mm2/s")
        XCTAssertEqual(unit.codeMeaning, "square millimeter per second")
        XCTAssertEqual(unit.codingSchemeDesignator, "UCUM")
    }
    
    func test_measurementUnits_perMinute_hasCorrectValues() {
        let unit = MeasurementUnits.perMinute
        XCTAssertEqual(unit.codeValue, "/min")
        XCTAssertEqual(unit.codeMeaning, "per minute")
    }
    
    // MARK: - Quantity Definition Tests
    
    func test_quantityDefinition_allPredefinedQuantities_haveValidCodes() {
        let quantities: [QuantityDefinition] = [
            .adc,
            .t1,
            .t2,
            .ktrans,
            .ve,
            .vp,
            .suv,
            .suvbw,
            .suvlbm,
            .suvbsa
        ]
        
        for quantity in quantities {
            XCTAssertFalse(quantity.codeValue.isEmpty)
            XCTAssertFalse(quantity.codingSchemeDesignator.isEmpty)
            XCTAssertFalse(quantity.codeMeaning.isEmpty)
            XCTAssertTrue(quantity.codingSchemeDesignator == "DCM" || quantity.codingSchemeDesignator == "SCT")
        }
    }
    
    func test_quantityDefinition_perfusionParameters_haveCorrectCodes() {
        XCTAssertEqual(QuantityDefinition.ktrans.codeValue, "126312")
        XCTAssertEqual(QuantityDefinition.ktrans.codeMeaning, "Ktrans")
        
        // PS3.16 2026a Table D-1: (126314, DCM, "ve"), (126331, DCM, "Vp")
        XCTAssertEqual(QuantityDefinition.ve.codeValue, "126314")
        XCTAssertEqual(QuantityDefinition.ve.codeMeaning, "ve")

        XCTAssertEqual(QuantityDefinition.vp.codeValue, "126331")
        XCTAssertEqual(QuantityDefinition.vp.codeMeaning, "Vp")
    }

    func test_quantityDefinition_suvVariants_haveCorrectCodes() {
        XCTAssertEqual(QuantityDefinition.suv.codeValue, "126400")
        XCTAssertEqual(QuantityDefinition.suvbw.codeValue, "126401")
        XCTAssertEqual(QuantityDefinition.suvlbm.codeValue, "126402")
        XCTAssertEqual(QuantityDefinition.suvbsa.codeValue, "126403")

        // PS3.16 2026a Table D-1 / CID 7180 meaning
        XCTAssertEqual(QuantityDefinition.suvbw.codeMeaning, "SUVbw")
    }

    func test_quantityDefinition_relaxationTimes_haveDCMScheme() {
        XCTAssertEqual(QuantityDefinition.t1.codingSchemeDesignator, "DCM")
        XCTAssertEqual(QuantityDefinition.t2.codingSchemeDesignator, "DCM")
        XCTAssertEqual(QuantityDefinition.t1.codeValue, "113063")
        XCTAssertEqual(QuantityDefinition.t2.codeValue, "113065")
    }
    
    // MARK: - Pixel Representation Edge Cases
    
    func test_parametricMap_pixelRepresentation_float_succeeds() {
        let mapping = RealWorldValueMapping(
            measurementUnits: .millisecond,
            mapping: .linear(slope: 1.0, intercept: 0.0)
        )
        
        let parametricMap = ParametricMap(
            sopInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4",
            studyInstanceUID: "1.2.3",
            realWorldValueMappings: [mapping],
            numberOfFrames: 1,
            rows: 128,
            columns: 128,
            bitsAllocated: 32,
            bitsStored: 32,
            highBit: 31,
            pixelRepresentation: 2  // Float (32-bit IEEE)
        )
        
        XCTAssertEqual(parametricMap.pixelRepresentation, 2)
        XCTAssertEqual(parametricMap.bitsAllocated, 32)
    }
    
    func test_parametricMap_pixelRepresentation_double_succeeds() {
        let mapping = RealWorldValueMapping(
            measurementUnits: .mm2PerSecond,
            mapping: .linear(slope: 0.001, intercept: 0.0)
        )
        
        let parametricMap = ParametricMap(
            sopInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4",
            studyInstanceUID: "1.2.3",
            realWorldValueMappings: [mapping],
            numberOfFrames: 1,
            rows: 256,
            columns: 256,
            bitsAllocated: 64,
            bitsStored: 64,
            highBit: 63,
            pixelRepresentation: 3  // Double (64-bit IEEE)
        )
        
        XCTAssertEqual(parametricMap.pixelRepresentation, 3)
        XCTAssertEqual(parametricMap.bitsAllocated, 64)
    }
    
    // MARK: - Functional Group Tests
    
    func test_functionalGroup_initialization_withAllNil_succeeds() {
        let functionalGroup = FunctionalGroup()
        
        XCTAssertNil(functionalGroup.segmentIdentification)
        XCTAssertNil(functionalGroup.derivationImage)
        XCTAssertNil(functionalGroup.frameContent)
        XCTAssertNil(functionalGroup.planePosition)
        XCTAssertNil(functionalGroup.planeOrientation)
    }
    
    func test_functionalGroup_initialization_withFrameContent_succeeds() {
        let frameContent = FrameContent(
            frameAcquisitionNumber: 1,
            frameReferenceDateTime: nil,
            frameAcquisitionDateTime: nil,
            dimensionIndexValues: []
        )
        
        let functionalGroup = FunctionalGroup(frameContent: frameContent)
        
        XCTAssertNotNil(functionalGroup.frameContent)
        XCTAssertEqual(functionalGroup.frameContent?.frameAcquisitionNumber, 1)
    }
    
    // MARK: - Referenced Series Tests
    
    func test_referencedSeries_multipleInstances_succeeds() {
        let instances = [
            ReferencedInstance(
                referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
                referencedSOPInstanceUID: "1.2.3.4.5.1"
            ),
            ReferencedInstance(
                referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
                referencedSOPInstanceUID: "1.2.3.4.5.2"
            ),
            ReferencedInstance(
                referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
                referencedSOPInstanceUID: "1.2.3.4.5.3",
                referencedFrameNumbers: [1, 2, 3]
            )
        ]
        
        let referencedSeries = ParametricMapReferencedSeries(
            seriesInstanceUID: "1.2.3.4.5",
            referencedInstances: instances
        )
        
        XCTAssertEqual(referencedSeries.seriesInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(referencedSeries.referencedInstances.count, 3)
        XCTAssertEqual(referencedSeries.referencedInstances[0].referencedSOPInstanceUID, "1.2.3.4.5.1")
        XCTAssertEqual(referencedSeries.referencedInstances[1].referencedSOPInstanceUID, "1.2.3.4.5.2")
        XCTAssertEqual(referencedSeries.referencedInstances[2].referencedSOPInstanceUID, "1.2.3.4.5.3")
        XCTAssertEqual(referencedSeries.referencedInstances[2].referencedFrameNumbers, [1, 2, 3])
    }
}
