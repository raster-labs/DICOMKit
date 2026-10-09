// ParametricMapHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent parametric map colormap and SUV helpers
// Reference: DICOM PS3.3 C.7.6.16.2.11 (Real World Value Mapping Macro), C.8.32 (Parametric Map), A.75 (Parametric Map IOD)
// NEMA-verified: 2026a, checked 2026-10-05 — citations checked against PS3.3 2026a section titles (C.8.23 is "Surface Segmentation" in 2026a; the Parametric Map modules are C.8.32, corrected); the colormaps, display defaults and SUV(bw) arithmetic carry no DICOM-defined values (the SUV unit g/ml{SUVbw} is PS3.16 2026a CID 85; the display strings are symbols, not codes)

import Foundation

/// Platform-independent helpers for parametric map display and SUV calculation.
public enum ParametricMapHelpers: Sendable {

    // MARK: - Normalization

    /// Normalizes `value` to [0, 1] within the given range, clamping outside.
    public static func normalizedValue(_ value: Double, min: Double, max: Double) -> Double {
        guard max > min else { return 0.0 }
        return Swift.min(Swift.max((value - min) / (max - min), 0.0), 1.0)
    }

    // MARK: - Color Mapping

    /// Maps a scalar `value` in [min, max] to an `RTColor` using the chosen colormap.
    public static func colorForValue(_ value: Double, min: Double, max: Double,
                                     colormap: ColormapName) -> RTColor {
        let t = normalizedValue(value, min: min, max: max)
        switch colormap {
        case .jet:     return _jetColor(t)
        case .viridis: return _viridisColor(t)
        case .hot:     return _hotColor(t)
        case .cool:    return _coolColor(t)
        case .gray:    return _grayColor(t)
        }
    }

    /// Generates `count` evenly-spaced color stops for a colormap legend.
    public static func colorScaleStops(colormap: ColormapName, count: Int) -> [RTColor] {
        guard count > 1 else {
            return [colorForValue(0, min: 0, max: 1, colormap: colormap)]
        }
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            return colorForValue(t, min: 0, max: 1, colormap: colormap)
        }
    }

    // MARK: - SUV

    /// Calculates SUV(bw) from a pixel value (Bq/mL) and acquisition parameters.
    ///
    /// Formula: SUV(bw) = (pixelValue [Bq/mL] × weightKg [kg] × 1000 [g/kg]) / injectedDoseBq [Bq]
    public static func calculateSUV(pixelValue: Double, mapping: SUVInputParameters) -> Double {
        guard mapping.injectedDoseBq > 0 else { return 0 }
        return (pixelValue * mapping.patientWeightKg * 1000.0) / mapping.injectedDoseBq
    }

    // MARK: - Default Display State

    /// Returns a sensible default `ParametricMapDisplayState` for the given map type.
    public static func defaultDisplayState(for mapType: ParametricMapType) -> ParametricMapDisplayState {
        switch mapType {
        case .t1Mapping:
            return ParametricMapDisplayState(mapType: mapType, colormapName: .hot, minValue: 0, maxValue: 3000)
        case .t2Mapping:
            return ParametricMapDisplayState(mapType: mapType, colormapName: .hot, minValue: 0, maxValue: 300)
        case .adcMapping:
            return ParametricMapDisplayState(mapType: mapType, colormapName: .viridis, minValue: 0, maxValue: 3.0)
        case .perfusion:
            return ParametricMapDisplayState(mapType: mapType, colormapName: .jet, minValue: 0, maxValue: 100)
        case .suvMap:
            return ParametricMapDisplayState(mapType: mapType, colormapName: .jet, minValue: 0, maxValue: 20)
        case .custom:
            return ParametricMapDisplayState(mapType: mapType, colormapName: .gray, minValue: 0, maxValue: 1000)
        }
    }

    // MARK: - Formatted Value

    /// Returns a human-readable value string with units for the given map type.
    public static func formattedValue(_ value: Double, mapType: ParametricMapType) -> String {
        switch mapType {
        case .t1Mapping:
            return String(format: "%.1f ms", value)
        case .t2Mapping:
            return String(format: "%.1f ms", value)
        case .adcMapping:
            return String(format: "%.3f mm²/s", value)
        case .perfusion:
            return String(format: "%.1f mL/100g/min", value)
        case .suvMap:
            return String(format: "%.2f g/mL", value)
        case .custom(let name):
            return String(format: "%.2f (\(name))", value)
        }
    }

    // MARK: - Private colormap implementations

    /// Jet colormap: blue → cyan → green → yellow → red
    private static func _jetColor(_ t: Double) -> RTColor {
        let stops: [(Double, RTColor)] = [
            (0.000, RTColor(red: 0.0, green: 0.0, blue: 0.5)),
            (0.125, RTColor(red: 0.0, green: 0.0, blue: 1.0)),
            (0.375, RTColor(red: 0.0, green: 1.0, blue: 1.0)),
            (0.625, RTColor(red: 1.0, green: 1.0, blue: 0.0)),
            (0.875, RTColor(red: 1.0, green: 0.0, blue: 0.0)),
            (1.000, RTColor(red: 0.5, green: 0.0, blue: 0.0)),
        ]
        return _interpolate(t: t, stops: stops)
    }

    /// Viridis colormap: dark purple → blue → teal → green → yellow
    private static func _viridisColor(_ t: Double) -> RTColor {
        let stops: [(Double, RTColor)] = [
            (0.00, RTColor(red: 0.267, green: 0.005, blue: 0.329)),
            (0.25, RTColor(red: 0.229, green: 0.322, blue: 0.545)),
            (0.50, RTColor(red: 0.128, green: 0.566, blue: 0.551)),
            (0.75, RTColor(red: 0.369, green: 0.788, blue: 0.383)),
            (1.00, RTColor(red: 0.993, green: 0.906, blue: 0.144)),
        ]
        return _interpolate(t: t, stops: stops)
    }

    /// Hot colormap: black → red → orange → yellow → white
    private static func _hotColor(_ t: Double) -> RTColor {
        let stops: [(Double, RTColor)] = [
            (0.00, RTColor(red: 0.0, green: 0.0, blue: 0.0)),
            (0.33, RTColor(red: 1.0, green: 0.0, blue: 0.0)),
            (0.66, RTColor(red: 1.0, green: 1.0, blue: 0.0)),
            (1.00, RTColor(red: 1.0, green: 1.0, blue: 1.0)),
        ]
        return _interpolate(t: t, stops: stops)
    }

    /// Cool colormap: cyan → magenta
    private static func _coolColor(_ t: Double) -> RTColor {
        RTColor(red: t, green: 1.0 - t, blue: 1.0)
    }

    /// Grayscale colormap: black → white
    private static func _grayColor(_ t: Double) -> RTColor {
        RTColor(red: t, green: t, blue: t)
    }

    /// Linear interpolation between key color stops.
    private static func _interpolate(t: Double, stops: [(Double, RTColor)]) -> RTColor {
        guard !stops.isEmpty else { return .black }
        if t <= stops.first!.0 { return stops.first!.1 }
        if t >= stops.last!.0  { return stops.last!.1 }
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
        return stops.last!.1
    }
}
