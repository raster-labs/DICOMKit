//
// SUVCalculatorTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class SUVCalculatorTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func test_suvCalculator_initialization_succeeds() {
        let injectionTime = Date()
        let seriesTime = injectionTime.addingTimeInterval(3600) // 1 hour later
        
        let calculator = SUVCalculator(
            patientWeight: 70.0,
            patientHeight: 1.75,
            patientSex: .male,
            injectedDose: 370_000_000, // 370 MBq = 10 mCi
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: seriesTime
        )
        
        XCTAssertEqual(calculator.patientWeight, 70.0)
        XCTAssertEqual(calculator.patientHeight, 1.75)
        XCTAssertEqual(calculator.patientSex, .male)
        XCTAssertEqual(calculator.injectedDose, 370_000_000)
    }
    
    // MARK: - Decay Correction Tests
    
    func test_decayCorrectedDose_afterOneHalfLife_reducesBy50Percent() {
        let injectionTime = Date()
        let halfLife = SUVCalculator.RadionuclideHalfLife.f18
        let seriesTime = injectionTime.addingTimeInterval(halfLife)
        
        let calculator = SUVCalculator(
            patientWeight: 70.0,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: halfLife,
            acquisitionTime: seriesTime
        )
        
        let decayedDose = calculator.decayCorrectedDose()
        XCTAssertEqual(decayedDose, 185_000_000, accuracy: 1_000_000) // ~50% of original
    }
    
    func test_decayCorrectedDose_afterTwoHalfLives_reducesBy75Percent() {
        let injectionTime = Date()
        let halfLife = SUVCalculator.RadionuclideHalfLife.f18
        let seriesTime = injectionTime.addingTimeInterval(2 * halfLife)
        
        let calculator = SUVCalculator(
            patientWeight: 70.0,
            injectedDose: 400_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: halfLife,
            acquisitionTime: seriesTime
        )
        
        let decayedDose = calculator.decayCorrectedDose()
        XCTAssertEqual(decayedDose, 100_000_000, accuracy: 5_000_000) // ~25% of original
    }
    
    func test_decayCorrectedDose_atInjectionTime_returnsOriginalDose() {
        let injectionTime = Date()
        
        let calculator = SUVCalculator(
            patientWeight: 70.0,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: injectionTime
        )
        
        let decayedDose = calculator.decayCorrectedDose()
        XCTAssertEqual(decayedDose, 370_000_000, accuracy: 1)
    }
    
    // MARK: - SUV Body Weight Tests
    
    func test_suvBodyWeight_withTypicalValues_calculatesCorrectly() {
        let injectionTime = Date()
        let seriesTime = injectionTime.addingTimeInterval(3600) // 1 hour
        
        let calculator = SUVCalculator(
            patientWeight: 70.0, // 70 kg
            injectedDose: 370_000_000, // 370 MBq
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: seriesTime
        )
        
        let activityConcentration = 5_000.0 // 5 kBq/ml
        let suvbw = calculator.suvBodyWeight(activityConcentration: activityConcentration)
        
        // SUV = (5000 Bq/ml) / (decay_corrected_dose / 70000 g)
        XCTAssertGreaterThan(suvbw, 0)
        XCTAssertLessThan(suvbw, 10) // Typical SUV range
    }
    
    func test_suvBodyWeight_withZeroActivity_returnsZero() {
        let injectionTime = Date()
        
        let calculator = SUVCalculator(
            patientWeight: 70.0,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: injectionTime
        )
        
        let suvbw = calculator.suvBodyWeight(activityConcentration: 0.0)
        XCTAssertEqual(suvbw, 0.0, accuracy: 0.001)
    }
    
    // MARK: - SUV Lean Body Mass Tests
    
    func test_suvLeanBodyMass_withMale_calculatesCorrectly() {
        let injectionTime = Date()
        
        let calculator = SUVCalculator(
            patientWeight: 80.0, // 80 kg
            patientHeight: 1.80, // 180 cm
            patientSex: .male,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: injectionTime
        )
        
        let activityConcentration = 5_000.0
        let suvlbm = calculator.suvLeanBodyMass(activityConcentration: activityConcentration)
        
        XCTAssertNotNil(suvlbm)
        XCTAssertGreaterThan(suvlbm!, 0)
    }
    
    func test_suvLeanBodyMass_withFemale_calculatesCorrectly() {
        let injectionTime = Date()
        
        let calculator = SUVCalculator(
            patientWeight: 60.0,
            patientHeight: 1.65,
            patientSex: .female,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: injectionTime
        )
        
        let activityConcentration = 5_000.0
        let suvlbm = calculator.suvLeanBodyMass(activityConcentration: activityConcentration)
        
        XCTAssertNotNil(suvlbm)
        XCTAssertGreaterThan(suvlbm!, 0)
    }
    
    func test_suvLeanBodyMass_withoutHeight_returnsNil() {
        let injectionTime = Date()
        
        let calculator = SUVCalculator(
            patientWeight: 70.0,
            patientSex: .male,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: injectionTime
        )
        
        let suvlbm = calculator.suvLeanBodyMass(activityConcentration: 5_000.0)
        XCTAssertNil(suvlbm)
    }
    
    func test_suvLeanBodyMass_withoutSex_returnsNil() {
        let injectionTime = Date()
        
        let calculator = SUVCalculator(
            patientWeight: 70.0,
            patientHeight: 1.75,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: injectionTime
        )
        
        let suvlbm = calculator.suvLeanBodyMass(activityConcentration: 5_000.0)
        XCTAssertNil(suvlbm)
    }
    
    // MARK: - SUV Body Surface Area Tests
    
    func test_suvBodySurfaceArea_withTypicalValues_calculatesCorrectly() {
        let injectionTime = Date()
        
        let calculator = SUVCalculator(
            patientWeight: 70.0,
            patientHeight: 1.75,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: injectionTime
        )
        
        let activityConcentration = 5_000.0
        let suvbsa = calculator.suvBodySurfaceArea(activityConcentration: activityConcentration)
        
        XCTAssertNotNil(suvbsa)
        XCTAssertGreaterThan(suvbsa!, 0)
    }
    
    func test_suvBodySurfaceArea_withoutHeight_returnsNil() {
        let injectionTime = Date()
        
        let calculator = SUVCalculator(
            patientWeight: 70.0,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: injectionTime
        )
        
        let suvbsa = calculator.suvBodySurfaceArea(activityConcentration: 5_000.0)
        XCTAssertNil(suvbsa)
    }
    
    // MARK: - SUV Ideal Body Weight Tests
    
    func test_suvIdealBodyWeight_withMale_calculatesCorrectly() {
        let injectionTime = Date()
        
        let calculator = SUVCalculator(
            patientWeight: 85.0,
            patientHeight: 1.80,
            patientSex: .male,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: injectionTime
        )
        
        let activityConcentration = 5_000.0
        let suvibw = calculator.suvIdealBodyWeight(activityConcentration: activityConcentration)
        
        XCTAssertNotNil(suvibw)
        XCTAssertGreaterThan(suvibw!, 0)
    }
    
    func test_suvIdealBodyWeight_withFemale_calculatesCorrectly() {
        let injectionTime = Date()
        
        let calculator = SUVCalculator(
            patientWeight: 65.0,
            patientHeight: 1.65,
            patientSex: .female,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: injectionTime
        )
        
        let activityConcentration = 5_000.0
        let suvibw = calculator.suvIdealBodyWeight(activityConcentration: activityConcentration)
        
        XCTAssertNotNil(suvibw)
        XCTAssertGreaterThan(suvibw!, 0)
    }
    
    func test_suvIdealBodyWeight_withoutRequiredParameters_returnsNil() {
        let injectionTime = Date()
        
        let calculator1 = SUVCalculator(
            patientWeight: 70.0,
            patientSex: .male,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: injectionTime
        )
        XCTAssertNil(calculator1.suvIdealBodyWeight(activityConcentration: 5_000.0))
        
        let calculator2 = SUVCalculator(
            patientWeight: 70.0,
            patientHeight: 1.75,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: injectionTime
        )
        XCTAssertNil(calculator2.suvIdealBodyWeight(activityConcentration: 5_000.0))
    }
    
    // MARK: - PatientSex Tests
    
    func test_patientSex_initWithDICOMString_succeeds() {
        XCTAssertEqual(PatientSex(dicomString: "M"), .male)
        XCTAssertEqual(PatientSex(dicomString: "F"), .female)
        XCTAssertEqual(PatientSex(dicomString: "O"), .other)
        
        XCTAssertEqual(PatientSex(dicomString: "MALE"), .male)
        XCTAssertEqual(PatientSex(dicomString: "FEMALE"), .female)
        XCTAssertEqual(PatientSex(dicomString: "OTHER"), .other)
        
        XCTAssertEqual(PatientSex(dicomString: "m"), .male)
        XCTAssertEqual(PatientSex(dicomString: "f"), .female)
    }
    
    func test_patientSex_initWithInvalidString_returnsNil() {
        XCTAssertNil(PatientSex(dicomString: "X"))
        XCTAssertNil(PatientSex(dicomString: ""))
        XCTAssertNil(PatientSex(dicomString: "UNKNOWN"))
    }
    
    // MARK: - Radionuclide Half-Life Tests
    
    func test_radionuclideHalfLife_commonIsotopes_haveCorrectValues() {
        // F-18: 109.77 minutes
        XCTAssertEqual(SUVCalculator.RadionuclideHalfLife.f18, 6586.2, accuracy: 1.0)
        
        // C-11: 20.38 minutes
        XCTAssertEqual(SUVCalculator.RadionuclideHalfLife.c11, 1222.8, accuracy: 1.0)
        
        // O-15: 2.03 minutes
        XCTAssertEqual(SUVCalculator.RadionuclideHalfLife.o15, 121.8, accuracy: 1.0)
        
        // N-13: 9.97 minutes
        XCTAssertEqual(SUVCalculator.RadionuclideHalfLife.n13, 598.2, accuracy: 1.0)
        
        // Ga-68: 67.71 minutes
        XCTAssertEqual(SUVCalculator.RadionuclideHalfLife.ga68, 4062.6, accuracy: 1.0)
    }
    
    // MARK: - Integration Tests
    
    func test_suvCalculator_multipleNormalizations_fromSameData() {
        let injectionTime = Date()
        let seriesTime = injectionTime.addingTimeInterval(3600)
        
        let calculator = SUVCalculator(
            patientWeight: 70.0,
            patientHeight: 1.75,
            patientSex: .male,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: seriesTime
        )
        
        let activityConcentration = 5_000.0
        
        let suvbw = calculator.suvBodyWeight(activityConcentration: activityConcentration)
        let suvlbm = calculator.suvLeanBodyMass(activityConcentration: activityConcentration)
        let suvbsa = calculator.suvBodySurfaceArea(activityConcentration: activityConcentration)
        let suvibw = calculator.suvIdealBodyWeight(activityConcentration: activityConcentration)
        
        // All should return valid values
        XCTAssertGreaterThan(suvbw, 0)
        XCTAssertNotNil(suvlbm)
        XCTAssertNotNil(suvbsa)
        XCTAssertNotNil(suvibw)
        
        // Values should be different
        XCTAssertNotEqual(suvbw, suvlbm!)
        XCTAssertNotEqual(suvbw, suvbsa!)
        XCTAssertNotEqual(suvbw, suvibw!)
    }
    
    func test_suvCalculator_sendable_canBeUsedInConcurrentContext() async {
        let injectionTime = Date()
        
        let calculator = SUVCalculator(
            patientWeight: 70.0,
            injectedDose: 370_000_000,
            injectionTime: injectionTime,
            radionuclideHalfLife: SUVCalculator.RadionuclideHalfLife.f18,
            acquisitionTime: injectionTime
        )
        
        // Verify we can use in async context (tests Sendable conformance)
        let suvbw = await Task {
            calculator.suvBodyWeight(activityConcentration: 5_000.0)
        }.value
        
        XCTAssertGreaterThan(suvbw, 0)
    }
}
