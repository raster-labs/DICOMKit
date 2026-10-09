//
// ParametricMapTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class ParametricMapTests: XCTestCase {
    
    // MARK: - ParametricMap Initialization Tests
    
    func test_parametricMap_initialization_withRequiredParameters_succeeds() {
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
            rows: 256,
            columns: 256,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15
        )
        
        XCTAssertEqual(parametricMap.sopInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(parametricMap.seriesInstanceUID, "1.2.3.4")
        XCTAssertEqual(parametricMap.studyInstanceUID, "1.2.3")
        XCTAssertEqual(parametricMap.realWorldValueMappings.count, 1)
        XCTAssertEqual(parametricMap.numberOfFrames, 1)
        XCTAssertEqual(parametricMap.rows, 256)
        XCTAssertEqual(parametricMap.columns, 256)
        XCTAssertEqual(parametricMap.bitsAllocated, 16)
        
        // Default values
        XCTAssertEqual(parametricMap.sopClassUID, "1.2.840.10008.5.1.4.1.1.30")
        XCTAssertEqual(parametricMap.samplesPerPixel, 1)
        XCTAssertEqual(parametricMap.photometricInterpretation, "MONOCHROME2")
        XCTAssertEqual(parametricMap.pixelRepresentation, 0)
    }
    
    func test_parametricMap_initialization_withAllParameters_succeeds() {
        let personName = DICOMPersonName.parse("Doe^John")!
        let contentDate = DICOMDate(year: 2024, month: 2, day: 5)
        let contentTime = DICOMTime(hour: 14, minute: 30, second: 0)
        
        let derivationCode = CodedEntry(
            codeValue: "113076",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Apparent Diffusion Coefficient calculation"
        )
        
        let mapping = RealWorldValueMapping(
            label: "ADC Mapping",
            explanation: "Maps pixel values to ADC values in mm²/s",
            measurementUnits: .mm2PerSecond,
            quantityDefinition: .adc,
            mapping: .linear(slope: 0.001, intercept: 0.0)
        )
        
        let referencedSeries = ParametricMapReferencedSeries(seriesInstanceUID: "1.2.3.4.5")
        
        let parametricMap = ParametricMap(
            sopInstanceUID: "1.2.3.4.5.6",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.30",
            seriesInstanceUID: "1.2.3.4.5",
            studyInstanceUID: "1.2.3.4",
            instanceNumber: 42,
            contentLabel: "ADC Map",
            contentDescription: "Diffusion-weighted imaging ADC map",
            contentCreatorName: personName,
            contentDate: contentDate,
            contentTime: contentTime,
            derivationDescription: "Calculated from DWI b-values",
            derivationCodeSequence: [derivationCode],
            realWorldValueMappings: [mapping],
            frameOfReferenceUID: "1.2.3.4.5.6.7",
            dimensionOrganizationUID: "1.2.3.4.5.6.7.8",
            referencedSeries: [referencedSeries],
            numberOfFrames: 20,
            rows: 256,
            columns: 256,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            samplesPerPixel: 1,
            photometricInterpretation: "MONOCHROME2",
            pixelRepresentation: 0
        )
        
        XCTAssertEqual(parametricMap.instanceNumber, 42)
        XCTAssertEqual(parametricMap.contentLabel, "ADC Map")
        XCTAssertEqual(parametricMap.contentDescription, "Diffusion-weighted imaging ADC map")
        XCTAssertEqual(parametricMap.contentCreatorName, personName)
        XCTAssertEqual(parametricMap.contentDate, contentDate)
        XCTAssertEqual(parametricMap.contentTime, contentTime)
        XCTAssertEqual(parametricMap.derivationDescription, "Calculated from DWI b-values")
        XCTAssertEqual(parametricMap.derivationCodeSequence.count, 1)
        XCTAssertEqual(parametricMap.derivationCodeSequence[0].codeValue, "113076")
        XCTAssertEqual(parametricMap.realWorldValueMappings.count, 1)
        XCTAssertEqual(parametricMap.frameOfReferenceUID, "1.2.3.4.5.6.7")
        XCTAssertEqual(parametricMap.dimensionOrganizationUID, "1.2.3.4.5.6.7.8")
        XCTAssertEqual(parametricMap.referencedSeries.count, 1)
        XCTAssertEqual(parametricMap.numberOfFrames, 20)
    }
    
    // MARK: - RealWorldValueMapping Tests
    
    func test_realWorldValueMapping_linearTransformation_succeeds() {
        let mapping = RealWorldValueMapping(
            label: "T1 Mapping",
            explanation: "T1 relaxation time in milliseconds",
            measurementUnits: .millisecond,
            quantityDefinition: .t1,
            mapping: .linear(slope: 1.5, intercept: 100.0)
        )
        
        XCTAssertEqual(mapping.label, "T1 Mapping")
        XCTAssertEqual(mapping.explanation, "T1 relaxation time in milliseconds")
        XCTAssertEqual(mapping.measurementUnits.codeValue, "ms")
        XCTAssertEqual(mapping.quantityDefinition?.codeValue, "113063")   // (113063, DCM, "T1"), PS3.16 Table D-1

        if case .linear(let slope, let intercept) = mapping.mapping {
            XCTAssertEqual(slope, 1.5)
            XCTAssertEqual(intercept, 100.0)
        } else {
            XCTFail("Expected linear mapping")
        }
    }
    
    func test_realWorldValueMapping_lutTransformation_succeeds() {
        let lutData = [0.0, 0.5, 1.0, 1.5, 2.0]
        let mapping = RealWorldValueMapping(
            measurementUnits: .mm2PerSecond,
            mapping: .lut(firstValueMapped: 0.0, lastValueMapped: 4.0, lutData: lutData)
        )
        
        if case .lut(let firstValue, let lastValue, let data) = mapping.mapping {
            XCTAssertEqual(firstValue, 0.0)
            XCTAssertEqual(lastValue, 4.0)
            XCTAssertEqual(data.count, 5)
            XCTAssertEqual(data, lutData)
        } else {
            XCTFail("Expected LUT mapping")
        }
    }
    
    // MARK: - MeasurementUnits Tests
    
    func test_measurementUnits_predefinedUnits_haveCorrectValues() {
        XCTAssertEqual(MeasurementUnits.mm2PerSecond.codeValue, "mm2/s")
        XCTAssertEqual(MeasurementUnits.mm2PerSecond.codingSchemeDesignator, "UCUM")
        
        XCTAssertEqual(MeasurementUnits.millisecond.codeValue, "ms")
        XCTAssertEqual(MeasurementUnits.second.codeValue, "s")
        XCTAssertEqual(MeasurementUnits.gPerML.codeValue, "g/ml")
        XCTAssertEqual(MeasurementUnits.perMinute.codeValue, "/min")
        XCTAssertEqual(MeasurementUnits.ratio.codeValue, "1")
    }
    
    func test_measurementUnits_customUnit_succeeds() {
        let customUnit = MeasurementUnits(
            codeValue: "Bq/ml",
            codingSchemeDesignator: "UCUM",
            codeMeaning: "becquerel per milliliter"
        )
        
        XCTAssertEqual(customUnit.codeValue, "Bq/ml")
        XCTAssertEqual(customUnit.codeMeaning, "becquerel per milliliter")
    }
    
    // MARK: - QuantityDefinition Tests
    
    func test_quantityDefinition_predefinedQuantities_haveCorrectValues() {
        XCTAssertEqual(QuantityDefinition.adc.codeValue, "113041")
        XCTAssertEqual(QuantityDefinition.adc.codingSchemeDesignator, "DCM")
        XCTAssertEqual(QuantityDefinition.adc.codeMeaning, "Apparent Diffusion Coefficient")
        
        XCTAssertEqual(QuantityDefinition.t1.codeValue, "113063")
        XCTAssertEqual(QuantityDefinition.t2.codeValue, "113065")

        XCTAssertEqual(QuantityDefinition.ktrans.codeValue, "126312")
        XCTAssertEqual(QuantityDefinition.ve.codeValue, "126314")
        XCTAssertEqual(QuantityDefinition.vp.codeValue, "126331")
        
        XCTAssertEqual(QuantityDefinition.suv.codeValue, "126400")
        XCTAssertEqual(QuantityDefinition.suvbw.codeValue, "126401")
        XCTAssertEqual(QuantityDefinition.suvlbm.codeValue, "126402")
        XCTAssertEqual(QuantityDefinition.suvbsa.codeValue, "126403")
    }
    
    func test_quantityDefinition_customQuantity_succeeds() {
        let customQuantity = QuantityDefinition(
            codeValue: "123456",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Custom Parameter"
        )
        
        XCTAssertEqual(customQuantity.codeValue, "123456")
        XCTAssertEqual(customQuantity.codeMeaning, "Custom Parameter")
    }
    
    // MARK: - CodedEntry Tests
    
    func test_codedEntry_initialization_succeeds() {
        let entry = CodedEntry(
            codeValue: "113076",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Apparent Diffusion Coefficient calculation"
        )
        
        XCTAssertEqual(entry.codeValue, "113076")
        XCTAssertEqual(entry.codingSchemeDesignator, "DCM")
        XCTAssertEqual(entry.codeMeaning, "Apparent Diffusion Coefficient calculation")
    }
    
    // MARK: - Referenced Series Tests
    
    func test_referencedSeries_initialization_withoutInstances_succeeds() {
        let series = ParametricMapReferencedSeries(seriesInstanceUID: "1.2.3.4.5")
        
        XCTAssertEqual(series.seriesInstanceUID, "1.2.3.4.5")
        XCTAssertTrue(series.referencedInstances.isEmpty)
    }
    
    func test_referencedSeries_initialization_withInstances_succeeds() {
        let instance1 = ReferencedInstance(
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.4",
            referencedSOPInstanceUID: "1.2.3.4.5.6"
        )
        let instance2 = ReferencedInstance(
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.4",
            referencedSOPInstanceUID: "1.2.3.4.5.7",
            referencedFrameNumbers: [1, 2, 3]
        )
        
        let series = ParametricMapReferencedSeries(
            seriesInstanceUID: "1.2.3.4.5",
            referencedInstances: [instance1, instance2]
        )
        
        XCTAssertEqual(series.referencedInstances.count, 2)
        XCTAssertEqual(series.referencedInstances[0].referencedSOPInstanceUID, "1.2.3.4.5.6")
        XCTAssertEqual(series.referencedInstances[1].referencedFrameNumbers, [1, 2, 3])
    }
    
    // MARK: - FunctionalGroup Tests
    
    func test_functionalGroup_initialization_succeeds() {
        let functionalGroup = FunctionalGroup()
        
        XCTAssertNil(functionalGroup.segmentIdentification)
        XCTAssertNil(functionalGroup.derivationImage)
        XCTAssertNil(functionalGroup.frameContent)
    }
}
