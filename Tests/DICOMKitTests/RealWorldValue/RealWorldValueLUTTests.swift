//
// RealWorldValueLUTTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class RealWorldValueLUTTests: XCTestCase {
    
    // MARK: - Linear Transformation Tests
    
    func test_linearTransformation_withPositiveSlope_transformsCorrectly() {
        let lut = RealWorldValueLUT(
            measurementUnits: .hounsfield,
            transformation: .linear(slope: 1.0, intercept: -1024.0)
        )
        
        XCTAssertEqual(lut.apply(to: 0), -1024.0, accuracy: 0.001)
        XCTAssertEqual(lut.apply(to: 1024), 0.0, accuracy: 0.001)
        XCTAssertEqual(lut.apply(to: 2048), 1024.0, accuracy: 0.001)
    }
    
    func test_linearTransformation_withFractionalSlope_transformsCorrectly() {
        let lut = RealWorldValueLUT(
            measurementUnits: .mm2PerSecond,
            quantityDefinition: .adc,
            transformation: .linear(slope: 0.001, intercept: 0.0)
        )
        
        XCTAssertEqual(lut.apply(to: 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(lut.apply(to: 1000), 1.0, accuracy: 0.0001)
        XCTAssertEqual(lut.apply(to: 2500), 2.5, accuracy: 0.0001)
    }
    
    func test_linearTransformation_withNegativeIntercept_transformsCorrectly() {
        let lut = RealWorldValueLUT(
            measurementUnits: .hounsfield,
            transformation: .linear(slope: 1.0, intercept: -1000.0)
        )
        
        XCTAssertEqual(lut.apply(to: 500), -500.0, accuracy: 0.001)
        XCTAssertEqual(lut.apply(to: 1000), 0.0, accuracy: 0.001)
        XCTAssertEqual(lut.apply(to: 1500), 500.0, accuracy: 0.001)
    }
    
    func test_linearTransformation_withDoubleInput_transformsCorrectly() {
        let lut = RealWorldValueLUT(
            measurementUnits: .millisecond,
            transformation: .linear(slope: 2.0, intercept: 10.0)
        )
        
        XCTAssertEqual(lut.apply(to: 0.5), 11.0, accuracy: 0.001)
        XCTAssertEqual(lut.apply(to: 1.5), 13.0, accuracy: 0.001)
        XCTAssertEqual(lut.apply(to: 2.5), 15.0, accuracy: 0.001)
    }
    
    // MARK: - LUT Transformation Tests
    
    func test_lutTransformation_withSimpleLUT_transformsCorrectly() {
        let descriptor = RealWorldValueLUT.LUTDescriptor(
            firstValueMapped: 0.0,
            lastValueMapped: 4.0
        )
        let lutData = [0.0, 10.0, 20.0, 30.0, 40.0]
        
        let lut = RealWorldValueLUT(
            measurementUnits: .ratio,
            transformation: .lut(descriptor, data: lutData)
        )
        
        XCTAssertEqual(lut.apply(to: 0), 0.0, accuracy: 0.001)
        XCTAssertEqual(lut.apply(to: 1), 10.0, accuracy: 0.001)
        XCTAssertEqual(lut.apply(to: 2), 20.0, accuracy: 0.001)
        XCTAssertEqual(lut.apply(to: 3), 30.0, accuracy: 0.001)
        XCTAssertEqual(lut.apply(to: 4), 40.0, accuracy: 0.001)
    }
    
    func test_lutTransformation_withOutOfRangeValue_clampsCorrectly() {
        let descriptor = RealWorldValueLUT.LUTDescriptor(
            firstValueMapped: 10.0,
            lastValueMapped: 14.0
        )
        let lutData = [100.0, 200.0, 300.0, 400.0, 500.0]
        
        let lut = RealWorldValueLUT(
            measurementUnits: .ratio,
            transformation: .lut(descriptor, data: lutData)
        )
        
        // Below range - should return first value
        XCTAssertEqual(lut.apply(to: 5), 100.0, accuracy: 0.001)
        
        // Above range - should return last value
        XCTAssertEqual(lut.apply(to: 20), 500.0, accuracy: 0.001)
        
        // Within range
        XCTAssertEqual(lut.apply(to: 12), 300.0, accuracy: 0.001)
    }
    
    func test_lutTransformation_withDoubleInput_transformsCorrectly() {
        let descriptor = RealWorldValueLUT.LUTDescriptor(
            firstValueMapped: 0.0,
            lastValueMapped: 2.0
        )
        let lutData = [1.0, 2.0, 3.0]
        
        let lut = RealWorldValueLUT(
            measurementUnits: .ratio,
            transformation: .lut(descriptor, data: lutData)
        )
        
        XCTAssertEqual(lut.apply(to: 0.0), 1.0, accuracy: 0.001)
        XCTAssertEqual(lut.apply(to: 1.0), 2.0, accuracy: 0.001)
        XCTAssertEqual(lut.apply(to: 2.0), 3.0, accuracy: 0.001)
    }
    
    // MARK: - LUT Descriptor Tests
    
    func test_lutDescriptor_numberOfEntries_calculatesCorrectly() {
        let descriptor1 = RealWorldValueLUT.LUTDescriptor(
            firstValueMapped: 0.0,
            lastValueMapped: 9.0
        )
        XCTAssertEqual(descriptor1.numberOfEntries, 10)
        
        let descriptor2 = RealWorldValueLUT.LUTDescriptor(
            firstValueMapped: 100.0,
            lastValueMapped: 104.0
        )
        XCTAssertEqual(descriptor2.numberOfEntries, 5)
    }
    
    func test_lutDescriptor_lookup_handlesEdgeCases() {
        let descriptor = RealWorldValueLUT.LUTDescriptor(
            firstValueMapped: 5.0,
            lastValueMapped: 9.0
        )
        let data = [10.0, 20.0, 30.0, 40.0, 50.0]
        
        // Exact matches
        XCTAssertEqual(descriptor.lookup(5.0, in: data), 10.0, accuracy: 0.001)
        XCTAssertEqual(descriptor.lookup(9.0, in: data), 50.0, accuracy: 0.001)
        
        // Out of bounds (clamped)
        XCTAssertEqual(descriptor.lookup(0.0, in: data), 10.0, accuracy: 0.001)
        XCTAssertEqual(descriptor.lookup(100.0, in: data), 50.0, accuracy: 0.001)
    }
    
    // MARK: - Frame Scope Tests
    
    func test_frameScope_allFrames_isCorrect() {
        let lut = RealWorldValueLUT(
            measurementUnits: .ratio,
            transformation: .linear(slope: 1.0, intercept: 0.0),
            frameScope: .allFrames
        )
        
        XCTAssertEqual(lut.frameScope, .allFrames)
    }
    
    func test_frameScope_firstFrame_isCorrect() {
        let lut = RealWorldValueLUT(
            measurementUnits: .ratio,
            transformation: .linear(slope: 1.0, intercept: 0.0),
            frameScope: .firstFrame
        )
        
        XCTAssertEqual(lut.frameScope, .firstFrame)
    }
    
    func test_frameScope_specificFrames_isCorrect() {
        let frames = [1, 3, 5, 7]
        let lut = RealWorldValueLUT(
            measurementUnits: .ratio,
            transformation: .linear(slope: 1.0, intercept: 0.0),
            frameScope: .specificFrames(frames)
        )
        
        XCTAssertEqual(lut.frameScope, .specificFrames(frames))
    }
    
    // MARK: - RealWorldValueUnits Tests
    
    func test_realWorldValueUnits_commonUnits_haveCorrectValues() {
        XCTAssertEqual(RealWorldValueUnits.hounsfield.codeValue, "[hnsf'U]")
        XCTAssertEqual(RealWorldValueUnits.hounsfield.codingSchemeDesignator, "UCUM")
        
        XCTAssertEqual(RealWorldValueUnits.mm2PerSecond.codeValue, "mm2/s")
        XCTAssertEqual(RealWorldValueUnits.millisecond.codeValue, "ms")
        XCTAssertEqual(RealWorldValueUnits.second.codeValue, "s")
        XCTAssertEqual(RealWorldValueUnits.gPerML.codeValue, "g/ml")
        XCTAssertEqual(RealWorldValueUnits.bqPerML.codeValue, "Bq/ml")
        XCTAssertEqual(RealWorldValueUnits.perMinute.codeValue, "/min")
        XCTAssertEqual(RealWorldValueUnits.mlPer100gPerMin.codeValue, "ml/(100.g.min)")
        XCTAssertEqual(RealWorldValueUnits.ratio.codeValue, "1")
        XCTAssertEqual(RealWorldValueUnits.percent.codeValue, "%")
    }
    
    func test_realWorldValueUnits_customUnits_canBeCreated() {
        let customUnits = RealWorldValueUnits(
            codeValue: "custom",
            codingSchemeDesignator: "LOCAL",
            codeMeaning: "Custom Units"
        )
        
        XCTAssertEqual(customUnits.codeValue, "custom")
        XCTAssertEqual(customUnits.codingSchemeDesignator, "LOCAL")
        XCTAssertEqual(customUnits.codeMeaning, "Custom Units")
    }
    
    // MARK: - CodedConcept Tests
    
    func test_codedConcept_diffusionQuantities_haveCorrectValues() {
        XCTAssertEqual(CodedConcept.adc.codeValue, "113041")
        XCTAssertEqual(CodedConcept.adc.codingSchemeDesignator, "DCM")
        XCTAssertEqual(CodedConcept.adc.codeMeaning, "Apparent Diffusion Coefficient")
    }
    
    func test_codedConcept_relaxationTimes_haveCorrectValues() {
        // PS3.16 2026a Table D-1
        XCTAssertEqual(CodedConcept.t1.codeValue, "113063")
        XCTAssertEqual(CodedConcept.t2.codeValue, "113065")
        XCTAssertEqual(CodedConcept.t2Star.codeValue, "113064")
    }

    func test_codedConcept_perfusionQuantities_haveCorrectValues() {
        // PS3.16 2026a Table D-1
        XCTAssertEqual(CodedConcept.ktrans.codeValue, "126312")
        XCTAssertEqual(CodedConcept.ve.codeValue, "126314")
        XCTAssertEqual(CodedConcept.vp.codeValue, "126331")
        XCTAssertEqual(CodedConcept.cbf.codeValue, "113055")
        XCTAssertEqual(CodedConcept.cbf.codeMeaning, "Regional Cerebral Blood Flow")
        XCTAssertEqual(CodedConcept.cbv.codeValue, "113056")
        XCTAssertEqual(CodedConcept.mtt.codeValue, "113052")
    }
    
    func test_codedConcept_suvQuantities_haveCorrectValues() {
        XCTAssertEqual(CodedConcept.suv.codeValue, "126400")
        XCTAssertEqual(CodedConcept.suvbw.codeValue, "126401")
        XCTAssertEqual(CodedConcept.suvlbm.codeValue, "126402")
        XCTAssertEqual(CodedConcept.suvbsa.codeValue, "126403")
        XCTAssertEqual(CodedConcept.suvibw.codeValue, "126404")
    }
    
    func test_codedConcept_ctQuantities_haveCorrectValues() {
        XCTAssertEqual(CodedConcept.hounsfield.codeValue, "112031")
        XCTAssertEqual(CodedConcept.hounsfield.codeMeaning, "Attenuation Coefficient")
    }
    
    // MARK: - Integration Tests
    
    func test_realWorldValueLUT_withLabel_storesCorrectly() {
        let lut = RealWorldValueLUT(
            label: "ADC Mapping",
            explanation: "Converts pixel values to ADC in mm²/s",
            measurementUnits: .mm2PerSecond,
            quantityDefinition: .adc,
            transformation: .linear(slope: 0.001, intercept: 0.0)
        )
        
        XCTAssertEqual(lut.label, "ADC Mapping")
        XCTAssertEqual(lut.explanation, "Converts pixel values to ADC in mm²/s")
        XCTAssertEqual(lut.measurementUnits.codeValue, "mm2/s")
        XCTAssertEqual(lut.quantityDefinition?.codeValue, "113041")
    }
    
    func test_realWorldValueLUT_sendable_canBeUsedInConcurrentContext() async {
        let lut = RealWorldValueLUT(
            measurementUnits: .hounsfield,
            transformation: .linear(slope: 1.0, intercept: -1024.0)
        )
        
        // Verify we can use in async context (tests Sendable conformance)
        let result = await Task {
            lut.apply(to: 1024)
        }.value
        
        XCTAssertEqual(result, 0.0, accuracy: 0.001)
    }
    
    func test_realWorldValueLUT_hashable_canBeUsedInSet() {
        let lut1 = RealWorldValueLUT(
            measurementUnits: .hounsfield,
            transformation: .linear(slope: 1.0, intercept: -1024.0)
        )
        
        let lut2 = RealWorldValueLUT(
            measurementUnits: .mm2PerSecond,
            transformation: .linear(slope: 0.001, intercept: 0.0)
        )
        
        let set: Set<RealWorldValueLUT> = [lut1, lut2]
        XCTAssertEqual(set.count, 2)
    }
}
