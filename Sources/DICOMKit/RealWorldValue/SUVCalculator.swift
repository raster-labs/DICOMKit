// NEMA-verified: 2026a, checked 2026-09-29 — units codes per PS3.16 2026a CID 85 SUV Unit and DCM 126401-126404 (CID 7180); size-correction factors per DCM 126410-126413 / CID 85 note; Units (0054,1001) terms C.8.9.1.1.3, Decay Correction NONE/START/ADMIN C.8.9.1.1.5, PET Isotope Table C.8-61 (Bq, seconds), Patient Study Table C.7-4a (kg, m) (P-SUV)
//
// SUVCalculator.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// PET Standardized Uptake Value Calculator
///
/// Calculates the SUV normalizations PS3.16 CID 85 "SUV Unit" enumerates:
/// - SUVbw — body weight, `g/ml{SUVbw}`
/// - SUVlbm — lean body mass (James, 128 multiplier), `g/ml{SUVlbm(James128)}`
/// - SUVlbm — lean body mass (Janmahasatian), `g/ml{SUVlbm(Janma)}`
/// - SUVbsa — body surface area, `cm2/ml{SUVbsa}`
/// - SUVibw — ideal body weight, `g/ml{SUVibw}`
///
/// The Standard does not define the SUV formula itself; it defines the *patient
/// size correction factors* (PS3.16 DCM 126410–126413 and the CID 85 note, all
/// citing Sugawara et al., Radiology 1999) and every attribute the calculation
/// consumes:
/// - Radionuclide Total Dose (0018,1074): "measured in Becquerels (Bq) at the
///   Radiopharmaceutical Start Time (0018,1072)" (PS3.3 Table C.8-61).
/// - Radiopharmaceutical Start DateTime (0018,1078) / Start Time (0018,1072):
///   "using the same time base as Series Time (0008,0031)" (Table C.8-61).
/// - Radionuclide Half Life (0018,1075): "in seconds" (Table C.8-61).
/// - Patient's Weight (0010,1030): "in kilograms"; Patient's Size (0010,1020): "in
///   meters" (PS3.3 Table C.7-4a).
/// - Units (0054,1001): pixel value units after Rescale Slope/Intercept, `BQML` =
///   Becquerels/milliliter (PS3.3 C.8.9.1.1.3).
/// - Decay Correction (0054,1102): NONE / START / ADMIN (PS3.3 C.8.9.1.1.5).
///
/// Reference: DICOM PS3.3 C.8.9.1 PET Series Module, C.8.9.2 PET Isotope Module
/// Reference: DICOM PS3.16 CID 85 SUV Unit; DCM 126401 SUVbw, 126402 SUVlbm,
/// 126403 SUVbsa, 126404 SUVibw (CID 7180)
public struct SUVCalculator: Sendable {

    // MARK: - Standard Terms

    /// Decay Correction (0054,1102) Defined Terms, PS3.3 C.8.9.1.1.5: "the
    /// real-world event to which images in this Series were decay corrected".
    public enum DecayCorrection: String, Sendable, CaseIterable {
        /// "no decay correction"
        case none = "NONE"
        /// "acquisition start time, Acquisition Time (0008,0032)"
        case start = "START"
        /// "radiopharmaceutical administration time, Radiopharmaceutical Start Time (0018,1072)"
        case admin = "ADMIN"
    }

    /// Units (0054,1001) Defined Terms, PS3.3 C.8.9.1.1.3 — "The units of the pixel
    /// values obtained after conversion from the stored pixel values (SV) … as
    /// defined by Rescale Intercept (0028,1052) and Rescale Slope (0028,1053)".
    public enum Units: String, Sendable, CaseIterable {
        case cnts = "CNTS"
        case none = "NONE"
        case cm2 = "CM2"
        case cm2ml = "CM2ML"
        case pcnt = "PCNT"
        case cps = "CPS"
        /// Becquerels/milliliter — the only input ``SUVCalculator`` accepts.
        case bqml = "BQML"
        case mgminml = "MGMINML"
        case umolminml = "UMOLMINML"
        case mlming = "MLMING"
        case mlg = "MLG"
        case oneCm = "1CM"
        case umolml = "UMOLML"
        case propcnts = "PROPCNTS"
        case propcps = "PROPCPS"
        case mlminml = "MLMINML"
        case mlml = "MLML"
        /// grams/milliliter — pixel values already are SUV (SUV Type (0054,1006) says which).
        case gml = "GML"
        case stddev = "STDDEV"
    }

    /// UCUM unit codes of PS3.16 CID 85 "SUV Unit", exactly as listed.
    public enum UnitCode {
        /// (g/ml{SUVbw}, UCUM, "Standardized Uptake Value body weight")
        public static let bodyWeight = "g/ml{SUVbw}"
        /// (g/ml{SUVlbm(James128)}, UCUM, "Standardized Uptake Value lean body mass (James 128 multiplier)")
        public static let leanBodyMassJames128 = "g/ml{SUVlbm(James128)}"
        /// (g/ml{SUVlbm(Janma)}, UCUM, "Standardized Uptake Value lean body mass (Janma)")
        public static let leanBodyMassJanmahasatian = "g/ml{SUVlbm(Janma)}"
        /// (cm2/ml{SUVbsa}, UCUM, "Standardized Uptake Value body surface area")
        public static let bodySurfaceArea = "cm2/ml{SUVbsa}"
        /// (g/ml{SUVibw}, UCUM, "Standardized Uptake Value ideal body weight")
        public static let idealBodyWeight = "g/ml{SUVibw}"
    }

    // MARK: - Patient Parameters

    /// Patient's Weight (0010,1030) in kilograms
    public let patientWeight: Double

    /// Patient's Size (0010,1020) in meters (optional, required for BSA, LBM and IBW)
    public let patientHeight: Double?

    /// Patient's Sex (0010,0040) (optional, required for LBM and IBW)
    public let patientSex: PatientSex?

    // MARK: - Radiopharmaceutical Parameters

    /// Radionuclide Total Dose (0018,1074) in Bq, "at the Radiopharmaceutical Start Time"
    public let injectedDose: Double

    /// Radiopharmaceutical Start DateTime (0018,1078) (or Start Time (0018,1072))
    public let injectionTime: Date

    /// Radionuclide Half Life (0018,1075) in seconds
    public let radionuclideHalfLife: Double

    /// Acquisition Time (0008,0032) of the image — the event START decay-corrects to.
    ///
    /// PS3.3 C.8.9.1.1.5 names Acquisition Time, not Series Time, as the START
    /// reference; Table C.8-61 requires the injection time to share the Series
    /// Time base, so both dates must be on that base.
    public let acquisitionTime: Date

    /// Decay Correction (0054,1102) of the Series the pixel values come from.
    public let decayCorrection: DecayCorrection

    /// Superseded name of ``acquisitionTime``.
    @available(*, deprecated, renamed: "acquisitionTime",
               message: "PS3.3 C.8.9.1.1.5 decay-corrects START images to Acquisition Time (0008,0032), not Series Time")
    public var seriesTime: Date { acquisitionTime }

    // MARK: - Initialization

    /// Initialize SUV Calculator
    ///
    /// - Parameters:
    ///   - patientWeight: Patient's Weight (0010,1030) in kg
    ///   - patientHeight: Patient's Size (0010,1020) in meters (optional)
    ///   - patientSex: Patient's Sex (0010,0040) (optional)
    ///   - injectedDose: Radionuclide Total Dose (0018,1074) in Bq
    ///   - injectionTime: Radiopharmaceutical Start DateTime (0018,1078)
    ///   - radionuclideHalfLife: Radionuclide Half Life (0018,1075) in seconds
    ///   - decayCorrection: Decay Correction (0054,1102) of the Series; default START
    ///   - acquisitionTime: Acquisition Time (0008,0032) of the image, same time base
    ///     as the injection time
    public init(
        patientWeight: Double,
        patientHeight: Double? = nil,
        patientSex: PatientSex? = nil,
        injectedDose: Double,
        injectionTime: Date,
        radionuclideHalfLife: Double,
        decayCorrection: DecayCorrection = .start,
        acquisitionTime: Date
    ) {
        self.patientWeight = patientWeight
        self.patientHeight = patientHeight
        self.patientSex = patientSex
        self.injectedDose = injectedDose
        self.injectionTime = injectionTime
        self.radionuclideHalfLife = radionuclideHalfLife
        self.decayCorrection = decayCorrection
        self.acquisitionTime = acquisitionTime
    }

    /// Superseded: `seriesTime` was used as the decay reference, but PS3.3
    /// C.8.9.1.1.5 defines START as "acquisition start time, Acquisition Time
    /// (0008,0032)". The value is taken as the acquisition time with START correction.
    @available(*, deprecated, renamed: "init(patientWeight:patientHeight:patientSex:injectedDose:injectionTime:radionuclideHalfLife:decayCorrection:acquisitionTime:)")
    public init(
        patientWeight: Double,
        patientHeight: Double? = nil,
        patientSex: PatientSex? = nil,
        injectedDose: Double,
        injectionTime: Date,
        radionuclideHalfLife: Double,
        seriesTime: Date
    ) {
        self.init(
            patientWeight: patientWeight,
            patientHeight: patientHeight,
            patientSex: patientSex,
            injectedDose: injectedDose,
            injectionTime: injectionTime,
            radionuclideHalfLife: radionuclideHalfLife,
            decayCorrection: .start,
            acquisitionTime: seriesTime
        )
    }

    // MARK: - Pixel Value Units

    /// Converts a stored pixel value to Bq/ml when Units (0054,1001) is BQML.
    ///
    /// Applies `U = m*SV + b` with Rescale Slope (0028,1053) as `m` and Rescale
    /// Intercept (0028,1052) as `b` (PS3.3 Table C.8-63; "The Rescale Intercept is
    /// always zero for PET images"). Any other Units value is not an activity
    /// concentration and yields nil: CNTS/CPS need a calibration the Standard does
    /// not carry (a private SUV scale factor is ignored), GML is already an SUV.
    public static func activityConcentration(
        storedValue: Double,
        rescaleSlope: Double,
        rescaleIntercept: Double = 0,
        units: Units
    ) -> Double? {
        guard units == .bqml else { return nil }
        return rescaleSlope * storedValue + rescaleIntercept
    }

    // MARK: - Decay Correction

    /// The injected dose decayed to the event the pixel values are referenced to.
    ///
    /// PS3.3 C.8.9.1.1.5 (Decay Correction (0054,1102)):
    /// - `START` — pixel values are decay corrected to "acquisition start time,
    ///   Acquisition Time (0008,0032)", so the dose is decayed from the injection
    ///   time to ``acquisitionTime``: `A₀ · exp(−ln2 · Δt / T½)`.
    /// - `ADMIN` — pixel values are decay corrected to "radiopharmaceutical
    ///   administration time, Radiopharmaceutical Start Time (0018,1072)", the very
    ///   time the dose was measured at (Table C.8-61), so no decay is applied.
    /// - `NONE` — pixel values are not decay corrected and therefore describe the
    ///   activity present at acquisition; the dose is decayed to ``acquisitionTime``
    ///   so that both sides of the ratio refer to the same instant.
    ///
    /// - Returns: Dose in Bq at the reference event
    public func decayCorrectedDose() -> Double {
        switch decayCorrection {
        case .admin:
            return injectedDose
        case .start, .none:
            let timeElapsed = acquisitionTime.timeIntervalSince(injectionTime)
            let decayConstant = log(2.0) / radionuclideHalfLife
            return injectedDose * exp(-decayConstant * timeElapsed)
        }
    }

    // MARK: - SUV Calculations

    /// Calculate SUV body weight (SUVbw), `g/ml{SUVbw}`.
    ///
    /// SUVbw = (Activity Concentration [Bq/ml]) / (Decay-corrected Dose [Bq] / Patient Weight [g]).
    /// "The patient size correction factor for males and females is body weight"
    /// (PS3.16 DCM 126410).
    ///
    /// - Parameter activityConcentration: Activity concentration in Bq/ml (Units BQML)
    /// - Returns: SUVbw in g/ml
    public func suvBodyWeight(activityConcentration: Double) -> Double {
        let decayedDose = decayCorrectedDose()
        let patientWeightGrams = patientWeight * 1000.0 // kg to g
        return activityConcentration / (decayedDose / patientWeightGrams)
    }

    /// Calculate SUV lean body mass (SUVlbm), James method with the 128 multiplier,
    /// `g/ml{SUVlbm(James128)}`.
    ///
    /// PS3.16 DCM 126411: "The patient size correction factor for males is
    /// 1.10 * weight - (120 or 128) * (weight/height)^2, and for females is
    /// 1.07 * weight - 148 * (weight/height)^2", weight in kg and height in cm.
    /// This implementation uses 128, the original James & Waterlow value, which
    /// CID 85 distinguishes as "Standardized Uptake Value lean body mass (James 128
    /// multiplier)".
    ///
    /// - Parameter activityConcentration: Activity concentration in Bq/ml
    /// - Returns: SUVlbm, or nil if height or a male/female sex is not available
    public func suvLeanBodyMass(activityConcentration: Double) -> Double? {
        guard let height = patientHeight, let sex = patientSex,
              let lbm = Self.leanBodyMassJames128(weight: patientWeight, height: height, sex: sex) else {
            return nil
        }
        return activityConcentration / (decayCorrectedDose() / (lbm * 1000.0))
    }

    /// Calculate SUV lean body mass (SUVlbm), Janmahasatian method,
    /// `g/ml{SUVlbm(Janma)}`.
    ///
    /// PS3.16 CID 85 note: males `9.27E3 * weight / (6.68E3 + 216 * weight / (height^2))`,
    /// females `9.27E3 * weight / (8.78E3 + 244 * weight / (height^2))`, weight in
    /// kg and height in cm.
    ///
    /// - Parameter activityConcentration: Activity concentration in Bq/ml
    /// - Returns: SUVlbm, or nil if height or a male/female sex is not available
    public func suvLeanBodyMassJanmahasatian(activityConcentration: Double) -> Double? {
        guard let height = patientHeight, let sex = patientSex,
              let lbm = Self.leanBodyMassJanmahasatian(weight: patientWeight, height: height, sex: sex) else {
            return nil
        }
        return activityConcentration / (decayCorrectedDose() / (lbm * 1000.0))
    }

    /// Calculate SUV body surface area (SUVbsa), `cm2/ml{SUVbsa}`.
    ///
    /// PS3.16 DCM 126412: "The patient size correction factor for males and females
    /// is weight^ 0.425 * height^0.725 * 0.007184" (Du Bois), weight in kg and
    /// height in cm, giving m²; the factor is applied in cm².
    ///
    /// - Parameter activityConcentration: Activity concentration in Bq/ml
    /// - Returns: SUVbsa, or nil if height is not available
    public func suvBodySurfaceArea(activityConcentration: Double) -> Double? {
        guard let height = patientHeight else {
            return nil
        }
        let bsa = Self.bodySurfaceArea(weight: patientWeight, height: height)
        let bsaCm2 = bsa * 10000.0 // m² to cm²
        return activityConcentration / (decayCorrectedDose() / bsaCm2)
    }

    /// Calculate SUV ideal body weight (SUVibw), `g/ml{SUVibw}`.
    ///
    /// PS3.16 DCM 126413: "The patient size correction factor for males is
    /// 48.0 + 1.06 * (height - 152) and for females is 45.5 + 0.91 * (height - 152)",
    /// height in cm, result in kg.
    ///
    /// - Parameter activityConcentration: Activity concentration in Bq/ml
    /// - Returns: SUVibw, or nil if height or a male/female sex is not available
    public func suvIdealBodyWeight(activityConcentration: Double) -> Double? {
        guard let height = patientHeight, let sex = patientSex,
              let ibw = Self.idealBodyWeight(height: height, sex: sex) else {
            return nil
        }
        return activityConcentration / (decayCorrectedDose() / (ibw * 1000.0))
    }

    // MARK: - Patient Size Correction Factors (PS3.16 DCM 126410-126413, CID 85 note)

    /// Lean body mass, James method with the 128 multiplier, in kg.
    ///
    /// Males: `1.10 * weight - 128 * (weight/height)^2`; females:
    /// `1.07 * weight - 148 * (weight/height)^2`; height in cm. The Standard
    /// defines no factor for a sex other than male or female, so `.other` yields nil.
    ///
    /// - Parameters:
    ///   - weight: Patient's Weight in kg
    ///   - height: Patient's Size in meters
    ///   - sex: Patient's Sex
    static func leanBodyMassJames128(weight: Double, height: Double, sex: PatientSex) -> Double? {
        let heightCm = height * 100.0
        switch sex {
        case .male:
            return 1.10 * weight - 128.0 * pow(weight / heightCm, 2)
        case .female:
            return 1.07 * weight - 148.0 * pow(weight / heightCm, 2)
        case .other:
            return nil
        }
    }

    /// Lean body mass, Janmahasatian method, in kg (CID 85 note), height in cm.
    static func leanBodyMassJanmahasatian(weight: Double, height: Double, sex: PatientSex) -> Double? {
        let heightCm = height * 100.0
        switch sex {
        case .male:
            return 9.27e3 * weight / (6.68e3 + 216.0 * weight / (heightCm * heightCm))
        case .female:
            return 9.27e3 * weight / (8.78e3 + 244.0 * weight / (heightCm * heightCm))
        case .other:
            return nil
        }
    }

    /// Body surface area in m²: `weight^0.425 * height^0.725 * 0.007184`, height in cm
    /// (PS3.16 DCM 126412).
    static func bodySurfaceArea(weight: Double, height: Double) -> Double {
        let heightCm = height * 100.0
        return 0.007184 * pow(heightCm, 0.725) * pow(weight, 0.425)
    }

    /// Ideal body weight in kg (PS3.16 DCM 126413), height in cm:
    /// males `48.0 + 1.06 * (height - 152)`, females `45.5 + 0.91 * (height - 152)`.
    /// The Standard defines no factor for `.other`, which yields nil.
    static func idealBodyWeight(height: Double, sex: PatientSex) -> Double? {
        let heightCm = height * 100.0
        switch sex {
        case .male:
            return 48.0 + 1.06 * (heightCm - 152.0)
        case .female:
            return 45.5 + 0.91 * (heightCm - 152.0)
        case .other:
            return nil
        }
    }
}

// MARK: - PatientSex

/// Patient's Sex (0010,0040) enumeration
public enum PatientSex: String, Sendable {
    case male = "M"
    case female = "F"
    case other = "O"

    /// Initialize from DICOM Patient's Sex string
    ///
    /// - Parameter dicomString: DICOM Patient's Sex value (M, F, O, or other)
    /// - Returns: PatientSex value, or nil if unrecognized
    public init?(dicomString: String) {
        let normalized = dicomString.uppercased().trimmingCharacters(in: .whitespaces)

        switch normalized {
        case "M", "MALE":
            self = .male
        case "F", "FEMALE":
            self = .female
        case "O", "OTHER":
            self = .other
        default:
            return nil
        }
    }
}

// MARK: - Common Radionuclides

extension SUVCalculator {

    /// Common PET radionuclide half-lives, in seconds — the unit of Radionuclide
    /// Half Life (0018,1075). Prefer the value carried in the object: it is "the
    /// radionuclide half life … that was used in the correction of this image".
    public enum RadionuclideHalfLife {
        /// F-18 (Fluorine-18) half-life: 109.77 minutes
        public static let f18: Double = 109.77 * 60.0 // seconds

        /// C-11 (Carbon-11) half-life: 20.38 minutes
        public static let c11: Double = 20.38 * 60.0 // seconds

        /// O-15 (Oxygen-15) half-life: 2.03 minutes
        public static let o15: Double = 2.03 * 60.0 // seconds

        /// N-13 (Nitrogen-13) half-life: 9.97 minutes
        public static let n13: Double = 9.97 * 60.0 // seconds

        /// Ga-68 (Gallium-68) half-life: 67.71 minutes
        public static let ga68: Double = 67.71 * 60.0 // seconds

        /// Cu-64 (Copper-64) half-life: 12.7 hours
        public static let cu64: Double = 12.7 * 3600.0 // seconds

        /// Zr-89 (Zirconium-89) half-life: 78.41 hours
        public static let zr89: Double = 78.41 * 3600.0 // seconds

        /// I-124 (Iodine-124) half-life: 4.176 days
        public static let i124: Double = 4.176 * 24.0 * 3600.0 // seconds
    }
}
