//
// SUVStandardConformanceTests.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

/// Pins `SUVCalculator` to the attributes, units and terms the Standard defines:
/// PS3.3 C.8.9.1.1.3 Units, C.8.9.1.1.5 Decay Correction, Table C.8-61 PET
/// Isotope (Bq, seconds), Table C.7-4a (kg, m); PS3.16 CID 85 SUV Unit and the
/// patient size correction factors of DCM 126410–126413.
final class SUVStandardConformanceTests: XCTestCase {

    private let injection = Date(timeIntervalSince1970: 1_700_000_000)
    private let halfLife = SUVCalculator.RadionuclideHalfLife.f18
    private let dose = 370_000_000.0 // Bq

    private func calculator(
        decay: SUVCalculator.DecayCorrection,
        elapsed: TimeInterval,
        weight: Double = 70,
        height: Double? = 1.75,
        sex: PatientSex? = .male
    ) -> SUVCalculator {
        SUVCalculator(
            patientWeight: weight, patientHeight: height, patientSex: sex,
            injectedDose: dose, injectionTime: injection, radionuclideHalfLife: halfLife,
            decayCorrection: decay, acquisitionTime: injection.addingTimeInterval(elapsed))
    }

    // MARK: - Decay Correction (0054,1102), C.8.9.1.1.5

    func test_decayCorrection_definedTerms() {
        XCTAssertEqual(SUVCalculator.DecayCorrection.none.rawValue, "NONE")
        XCTAssertEqual(SUVCalculator.DecayCorrection.start.rawValue, "START")
        XCTAssertEqual(SUVCalculator.DecayCorrection.admin.rawValue, "ADMIN")
        XCTAssertEqual(SUVCalculator.DecayCorrection.allCases.count, 3)
    }

    func test_start_decaysDoseToAcquisitionTime() {
        // START: "acquisition start time, Acquisition Time (0008,0032)" — one half-life later, half the dose.
        let calc = calculator(decay: .start, elapsed: halfLife)
        XCTAssertEqual(calc.decayCorrectedDose(), dose / 2, accuracy: 1)
    }

    func test_admin_appliesNoDecay() {
        // ADMIN: pixel values are corrected to the administration time, the time
        // Radionuclide Total Dose was measured at (Table C.8-61) — no decay.
        let calc = calculator(decay: .admin, elapsed: halfLife)
        XCTAssertEqual(calc.decayCorrectedDose(), dose, accuracy: 1e-6)
    }

    func test_none_decaysDoseToAcquisitionTime() {
        let calc = calculator(decay: .none, elapsed: 2 * halfLife)
        XCTAssertEqual(calc.decayCorrectedDose(), dose / 4, accuracy: 1)
    }

    func test_deprecatedSeriesTimeInitializer_mapsToStartAtAcquisitionTime() {
        @available(*, deprecated)
        func legacy() -> SUVCalculator {
            SUVCalculator(patientWeight: 70, injectedDose: dose, injectionTime: injection,
                          radionuclideHalfLife: halfLife, seriesTime: injection.addingTimeInterval(halfLife))
        }
        let calc = legacy()
        XCTAssertEqual(calc.decayCorrection, .start)
        XCTAssertEqual(calc.acquisitionTime, injection.addingTimeInterval(halfLife))
        XCTAssertEqual(calc.decayCorrectedDose(), dose / 2, accuracy: 1)
    }

    // MARK: - Units (0054,1001), C.8.9.1.1.3

    func test_units_definedTerms() {
        let expected = ["CNTS", "NONE", "CM2", "CM2ML", "PCNT", "CPS", "BQML", "MGMINML", "UMOLMINML",
                        "MLMING", "MLG", "1CM", "UMOLML", "PROPCNTS", "PROPCPS", "MLMINML", "MLML",
                        "GML", "STDDEV"]
        XCTAssertEqual(SUVCalculator.Units.allCases.map(\.rawValue), expected)
    }

    func test_activityConcentration_onlyForBQML_withRescale() {
        // U = m*SV + b (Table C.8-63); BQML is Becquerels/milliliter.
        XCTAssertEqual(SUVCalculator.activityConcentration(storedValue: 1000, rescaleSlope: 2.5, units: .bqml), 2500)
        XCTAssertEqual(SUVCalculator.activityConcentration(storedValue: 1000, rescaleSlope: 2.5,
                                                           rescaleIntercept: 0, units: .bqml), 2500)
        XCTAssertNil(SUVCalculator.activityConcentration(storedValue: 1000, rescaleSlope: 2.5, units: .cnts))
        XCTAssertNil(SUVCalculator.activityConcentration(storedValue: 1000, rescaleSlope: 2.5, units: .gml))
        XCTAssertNil(SUVCalculator.activityConcentration(storedValue: 1000, rescaleSlope: 2.5, units: .cps))
    }

    // MARK: - CID 85 SUV Unit

    func test_unitCodes_matchCID85() {
        XCTAssertEqual(SUVCalculator.UnitCode.bodyWeight, "g/ml{SUVbw}")
        XCTAssertEqual(SUVCalculator.UnitCode.leanBodyMassJames128, "g/ml{SUVlbm(James128)}")
        XCTAssertEqual(SUVCalculator.UnitCode.leanBodyMassJanmahasatian, "g/ml{SUVlbm(Janma)}")
        XCTAssertEqual(SUVCalculator.UnitCode.bodySurfaceArea, "cm2/ml{SUVbsa}")
        XCTAssertEqual(SUVCalculator.UnitCode.idealBodyWeight, "g/ml{SUVibw}")
    }

    // MARK: - Patient size correction factors (DCM 126410-126413, CID 85 note)

    func test_suvbw_usesWeightInGrams_andDoseInBq() {
        // DCM 126410: correction factor is body weight. 70 kg, dose at ADMIN, 5000 Bq/ml:
        // SUVbw = 5000 / (370e6 / 70000) = 0.9459…
        let calc = calculator(decay: .admin, elapsed: 3600)
        XCTAssertEqual(calc.suvBodyWeight(activityConcentration: 5000), 5000 / (dose / 70_000), accuracy: 1e-9)
    }

    func test_leanBodyMass_James128() {
        // DCM 126411: males 1.10 * weight - 128 * (weight/height)^2; females 1.07 * weight - 148 * (weight/height)^2; height in cm.
        XCTAssertEqual(SUVCalculator.leanBodyMassJames128(weight: 80, height: 1.80, sex: .male)!,
                       1.10 * 80 - 128 * pow(80 / 180, 2), accuracy: 1e-9)
        XCTAssertEqual(SUVCalculator.leanBodyMassJames128(weight: 60, height: 1.65, sex: .female)!,
                       1.07 * 60 - 148 * pow(60 / 165, 2), accuracy: 1e-9)
        XCTAssertNil(SUVCalculator.leanBodyMassJames128(weight: 60, height: 1.65, sex: .other))
    }

    func test_leanBodyMass_Janmahasatian() {
        // CID 85 note: males 9.27E3 * weight / (6.68E3 + 216 * weight / (height^2)); females … (8.78E3 + 244 …)
        XCTAssertEqual(SUVCalculator.leanBodyMassJanmahasatian(weight: 80, height: 1.80, sex: .male)!,
                       9.27e3 * 80 / (6.68e3 + 216 * 80 / (180.0 * 180.0)), accuracy: 1e-9)
        XCTAssertEqual(SUVCalculator.leanBodyMassJanmahasatian(weight: 60, height: 1.65, sex: .female)!,
                       9.27e3 * 60 / (8.78e3 + 244 * 60 / (165.0 * 165.0)), accuracy: 1e-9)
        let calc = calculator(decay: .admin, elapsed: 0, weight: 80, height: 1.80, sex: .male)
        let lbm = 9.27e3 * 80 / (6.68e3 + 216 * 80 / (180.0 * 180.0))
        XCTAssertEqual(calc.suvLeanBodyMassJanmahasatian(activityConcentration: 5000)!,
                       5000 / (dose / (lbm * 1000)), accuracy: 1e-9)
    }

    func test_bodySurfaceArea_DuBois() {
        // DCM 126412: weight^0.425 * height^0.725 * 0.007184, height in cm.
        XCTAssertEqual(SUVCalculator.bodySurfaceArea(weight: 70, height: 1.75),
                       pow(70, 0.425) * pow(175, 0.725) * 0.007184, accuracy: 1e-12)
        let calc = calculator(decay: .admin, elapsed: 0)
        let bsaCm2 = pow(70, 0.425) * pow(175, 0.725) * 0.007184 * 10_000
        XCTAssertEqual(calc.suvBodySurfaceArea(activityConcentration: 5000)!, 5000 / (dose / bsaCm2), accuracy: 1e-9)
    }

    func test_idealBodyWeight_perDCM126413() {
        // "males is 48.0 + 1.06 * (height - 152) and for females is 45.5 + 0.91 * (height - 152)", height in cm.
        XCTAssertEqual(SUVCalculator.idealBodyWeight(height: 1.80, sex: .male)!, 48.0 + 1.06 * (180 - 152), accuracy: 1e-9)
        XCTAssertEqual(SUVCalculator.idealBodyWeight(height: 1.65, sex: .female)!, 45.5 + 0.91 * (165 - 152), accuracy: 1e-9)
        XCTAssertNil(SUVCalculator.idealBodyWeight(height: 1.65, sex: .other))
        let calc = calculator(decay: .admin, elapsed: 0, weight: 85, height: 1.80, sex: .male)
        let ibw = 48.0 + 1.06 * (180 - 152)
        XCTAssertEqual(calc.suvIdealBodyWeight(activityConcentration: 5000)!, 5000 / (dose / (ibw * 1000)), accuracy: 1e-9)
    }

    func test_sexOther_hasNoStandardFactor_returnsNil() {
        let calc = calculator(decay: .admin, elapsed: 0, sex: .other)
        XCTAssertNil(calc.suvLeanBodyMass(activityConcentration: 5000))
        XCTAssertNil(calc.suvIdealBodyWeight(activityConcentration: 5000))
        XCTAssertNotNil(calc.suvBodySurfaceArea(activityConcentration: 5000))
    }
}
