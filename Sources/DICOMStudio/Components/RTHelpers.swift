// RTHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent Radiation Therapy visualization helpers
// Reference: DICOM PS3.3 C.8.8 (Radiotherapy Modules), C.8.8.5 (Structure Set Module), C.8.8.8 (RT ROI Observations Module), C.8.8.3 (RT Dose Module)
// NEMA-verified: 2026a, checked 2026-10-05 — citations checked against PS3.3 2026a section titles (C.8.8.5 is the Structure Set Module, not RT Plan: corrected); switches over RTROIType / RTDoseUnits are exhaustive over the model enums verified in SpecializedModalityModel.swift (P-STUDIO-RT-ROI-TYPES, P-STUDIO-RT-DOSE-UNITS); isodose percentages, colour washes and DVH interpolation are display conventions with no DICOM-defined values

import Foundation

/// Platform-independent helpers for RT dose and structure-set visualization.
public enum RTHelpers: Sendable {

    /// Returns the conventional color for a given RT ROI type (a display convention; every
    /// Defined Term gets a distinct colour).
    public static func colorForROIType(_ roiType: RTROIType) -> RTColor {
        switch roiType {
        case .ptv:      return .red
        case .ctv:      return .blue
        case .gtv:      return .green
        case .oar:      return .yellow
        case .external: return .cyan
        case .support:  return .orange
        case .treatedVolume:          return RTColor(red: 0.8, green: 0.2, blue: 0.2)
        case .irradiatedVolume:       return RTColor(red: 0.6, green: 0.1, blue: 0.1)
        case .bolus:                  return RTColor(red: 0.5, green: 0.8, blue: 1.0)
        case .avoidance:              return RTColor(red: 0.9, green: 0.9, blue: 0.5)
        case .organ:                  return .pink
        case .marker:                 return RTColor(red: 1.0, green: 0.0, blue: 1.0)
        case .registration:           return RTColor(red: 0.5, green: 0.5, blue: 1.0)
        case .isocenter:              return .white
        case .contrastAgent:          return RTColor(red: 0.0, green: 0.6, blue: 0.6)
        case .cavity:                 return RTColor(red: 0.4, green: 0.4, blue: 0.4)
        case .brachyChannel:          return RTColor(red: 0.6, green: 0.4, blue: 0.2)
        case .brachyAccessory:        return RTColor(red: 0.8, green: 0.6, blue: 0.4)
        case .brachySourceApplicator: return RTColor(red: 0.7, green: 0.5, blue: 0.0)
        case .brachyChannelShield:    return RTColor(red: 0.3, green: 0.2, blue: 0.1)
        case .fixation:               return RTColor(red: 0.6, green: 0.6, blue: 0.8)
        case .doseRegion:             return RTColor(red: 0.0, green: 0.5, blue: 0.0)
        case .control:                return RTColor(red: 0.5, green: 1.0, blue: 0.5)
        case .doseMeasurement:        return RTColor(red: 0.0, green: 0.3, blue: 0.7)
        case .device:                 return RTColor(red: 0.7, green: 0.7, blue: 0.7)
        default:                      return .purple   // deprecated `other`
        }
    }

    /// Returns the SF Symbol name for a given RT ROI type.
    public static func sfSymbolForROIType(_ roiType: RTROIType) -> String {
        roiType.sfSymbol
    }

    /// Generates standard isodose lines at fixed percentages of the maximum dose.
    ///
    /// Lines are produced at 30 %, 50 %, 70 %, 80 %, 90 %, 95 % and 100 % of `maxDose`.
    public static func isodoseLevels(for maxDose: Double) -> [RTIsodoseLevel] {
        let levels: [(Double, RTColor)] = [
            (30.0,  .blue),
            (50.0,  .cyan),
            (70.0,  .green),
            (80.0,  .yellow),
            (90.0,  .orange),
            (95.0,  .red),
            (100.0, .white),
        ]
        return levels.map { (pct, color) in
            RTIsodoseLevel(percentage: pct, color: color)
        }
    }

    /// Maps a dose value to a rainbow color wash between 0 and `maxDose`.
    ///
    /// - blue at 0 %, cyan at 25 %, green at 50 %, yellow at 75 %, red at 100 %.
    public static func doseColorWash(dose: Double, maxDose: Double) -> RTColor {
        guard maxDose > 0 else { return .blue }
        let t = min(max(dose / maxDose, 0.0), 1.0)
        return _rainbowColor(t: t)
    }

    /// Returns a formatted dose string, e.g. `"60.00 Gy"` or `"6000.00 cGy"`.
    public static func formattedDose(_ dose: Double, units: RTDoseUnits) -> String {
        String(format: "%.2f \(units.displayName)", dose)
    }

    /// Returns the mean dose of a DVH curve, computing it from points if not stored.
    public static func meanDose(from curve: DVHCurve) -> Double {
        if let mean = curve.meanDose { return mean }
        guard !curve.points.isEmpty else { return 0 }
        let sum = curve.points.map(\.dose).reduce(0, +)
        return sum / Double(curve.points.count)
    }

    /// Linearly interpolates the volume at a target dose in a DVH curve.
    ///
    /// Returns `nil` if the curve has no points.
    public static func dvhVolumeAtDose(_ targetDose: Double, curve: DVHCurve) -> Double? {
        let pts = curve.points
        guard !pts.isEmpty else { return nil }
        // If target is below minimum or above maximum, clamp
        if targetDose <= pts.first!.dose { return pts.first!.volume }
        if targetDose >= pts.last!.dose  { return pts.last!.volume }
        for i in 0..<(pts.count - 1) {
            let p0 = pts[i]
            let p1 = pts[i + 1]
            if targetDose >= p0.dose && targetDose <= p1.dose {
                let span = p1.dose - p0.dose
                guard span > 0 else { return p0.volume }
                let frac = (targetDose - p0.dose) / span
                return p0.volume + frac * (p1.volume - p0.volume)
            }
        }
        return pts.last!.volume
    }

    /// Formats a beam angle in degrees, e.g. `"45°"` or `"45.5°"`.
    public static func beamDisplayAngle(_ angle: Double) -> String {
        let rounded = (angle * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))°"
        }
        return String(format: "%.1f°", rounded)
    }

    /// Computes the total plan dose by summing all beam doses across all fraction groups.
    public static func totalPlanDose(fractionGroups: [RTFractionGroup]) -> Double {
        fractionGroups.reduce(0.0) { total, group in
            total + group.beamDoses.reduce(0.0) { $0 + $1.dose }
        }
    }

    // MARK: - Private

    /// Linear rainbow interpolation between blue → cyan → green → yellow → red.
    private static func _rainbowColor(t: Double) -> RTColor {
        // Key stops: t=0 → blue, t=0.25 → cyan, t=0.5 → green, t=0.75 → yellow, t=1 → red
        let stops: [(Double, RTColor)] = [
            (0.00, .blue),
            (0.25, .cyan),
            (0.50, .green),
            (0.75, .yellow),
            (1.00, .red),
        ]
        // Find bracketing pair
        for i in 0..<(stops.count - 1) {
            let (t0, c0) = stops[i]
            let (t1, c1) = stops[i + 1]
            if t >= t0 && t <= t1 {
                let span = t1 - t0
                guard span > 0 else { return c0 }
                let f = (t - t0) / span
                return RTColor(
                    red:   c0.red   + f * (c1.red   - c0.red),
                    green: c0.green + f * (c1.green - c0.green),
                    blue:  c0.blue  + f * (c1.blue  - c0.blue)
                )
            }
        }
        return .red
    }
}
