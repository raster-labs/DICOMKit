// ColorLUTHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent color lookup table helpers
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data: the palette ramps are this app's own (PS3.6 2026a Table B.1-1 defines HOT_IRON, PET, HOT_METAL_BLUE, PET_20_STEP, SPRING, SUMMER, FALL and WINTER by 256-entry tables in B.1.1–B.1.8; the ramps here are formulae that share three of those names and are not those tables — the standard palettes live in DICOMCore `PseudoColorPalette`); the citation was "C.11.10", which in 2026a is the Presentation State Identification Module: corrected to PS3.6 Annex B / PS3.3 A.33.3

import Foundation

/// Platform-independent helpers for pseudo-color palette and color LUT operations.
///
/// Generates the palettes a stored Pseudo-Color Softcopy Presentation State
/// (PS3.3 A.33.3) names through `PresentationStatePalette`. These ramps are
/// computed, not the Well-known Color Palettes of PS3.6 Annex B (Table B.1-1
/// lists them by UID; their tables are B.1.1–B.1.8): "Hot Iron", "PET" and
/// "PET 20-Step" here share a name with those but are not those tables, and
/// "Rainbow", "Hot Metal" and "Grayscale" have no standard counterpart. The
/// standard tables themselves are DICOMCore's `PseudoColorPalette`.
public enum ColorLUTHelpers: Sendable {

    /// Standard LUT size (256 entries for 8-bit output).
    public static let standardLUTSize = 256

    // MARK: - Standard Palette Generation

    /// Generates a Hot Iron pseudo-color palette.
    ///
    /// Transitions from black → dark red → orange → yellow → white.
    ///
    /// - Returns: Array of 256 ColorEntry values.
    public static func hotIronPalette() -> [ColorEntry] {
        (0..<standardLUTSize).map { i in
            let t = Double(i) / 255.0
            let r: UInt8
            let g: UInt8
            let b: UInt8

            if t < 0.5 {
                r = UInt8(min(255, Int(t * 2.0 * 255.0)))
                g = 0
                b = 0
            } else if t < 0.75 {
                r = 255
                g = UInt8(min(255, Int((t - 0.5) * 4.0 * 255.0)))
                b = 0
            } else {
                r = 255
                g = 255
                b = UInt8(min(255, Int((t - 0.75) * 4.0 * 255.0)))
            }

            return ColorEntry(red: r, green: g, blue: b)
        }
    }

    /// Generates a Rainbow pseudo-color palette.
    ///
    /// Transitions through the full spectrum: red → yellow → green → cyan → blue → magenta.
    ///
    /// - Returns: Array of 256 ColorEntry values.
    public static func rainbowPalette() -> [ColorEntry] {
        (0..<standardLUTSize).map { i in
            let t = Double(i) / 255.0
            let (r, g, b) = hsvToRGB(h: t * 300.0, s: 1.0, v: 1.0)
            return ColorEntry(red: r, green: g, blue: b)
        }
    }

    /// Generates a Hot Metal pseudo-color palette.
    ///
    /// Transitions from black → dark red → red → yellow → white.
    ///
    /// - Returns: Array of 256 ColorEntry values.
    public static func hotMetalPalette() -> [ColorEntry] {
        (0..<standardLUTSize).map { i in
            let t = Double(i) / 255.0
            let r = UInt8(min(255, Int(min(1.0, t * 2.5) * 255.0)))
            let g = UInt8(min(255, Int(max(0.0, (t - 0.4) * 2.5) * 255.0)))
            let b = UInt8(min(255, Int(max(0.0, (t - 0.7) * 3.33) * 255.0)))
            return ColorEntry(red: r, green: g, blue: b)
        }
    }

    /// Generates a PET pseudo-color palette.
    ///
    /// Common nuclear medicine palette emphasizing hot spots.
    ///
    /// - Returns: Array of 256 ColorEntry values.
    public static func petPalette() -> [ColorEntry] {
        (0..<standardLUTSize).map { i in
            let t = Double(i) / 255.0
            let r: UInt8
            let g: UInt8
            let b: UInt8

            if t < 0.33 {
                r = 0
                g = 0
                b = UInt8(min(255, Int(t * 3.0 * 255.0)))
            } else if t < 0.66 {
                r = UInt8(min(255, Int((t - 0.33) * 3.0 * 255.0)))
                g = UInt8(min(255, Int((t - 0.33) * 3.0 * 255.0)))
                b = UInt8(max(0, Int((1.0 - (t - 0.33) * 3.0) * 255.0)))
            } else {
                r = 255
                g = UInt8(min(255, Int((t - 0.66) * 3.0 * 255.0)))
                b = 0
            }

            return ColorEntry(red: r, green: g, blue: b)
        }
    }

    /// Generates a PET 20-step pseudo-color palette.
    ///
    /// Quantized version with 20 distinct color levels.
    ///
    /// - Returns: Array of 256 ColorEntry values.
    public static func pet20StepPalette() -> [ColorEntry] {
        let basePalette = petPalette()
        let steps = 20
        let stepSize = standardLUTSize / steps

        return (0..<standardLUTSize).map { i in
            let quantized = (i / stepSize) * stepSize + stepSize / 2
            let index = min(standardLUTSize - 1, quantized)
            return basePalette[index]
        }
    }

    /// Generates a grayscale pseudo-color palette (identity).
    ///
    /// - Returns: Array of 256 ColorEntry values.
    public static func grayscalePalette() -> [ColorEntry] {
        (0..<standardLUTSize).map { i in
            let v = UInt8(i)
            return ColorEntry(red: v, green: v, blue: v)
        }
    }

    /// Returns the palette for a given pseudo-color type.
    ///
    /// - Parameter palette: Pseudo-color palette type.
    /// - Returns: Array of 256 ColorEntry values.
    public static func palette(for type: PresentationStatePalette) -> [ColorEntry] {
        switch type {
        case .hotIron: return hotIronPalette()
        case .rainbow: return rainbowPalette()
        case .hotMetal: return hotMetalPalette()
        case .pet: return petPalette()
        case .petTwentyStep: return pet20StepPalette()
        case .grayscale: return grayscalePalette()
        case .custom: return grayscalePalette()
        }
    }

    // MARK: - LUT Application

    /// Applies a color LUT to a grayscale value.
    ///
    /// - Parameters:
    ///   - grayValue: Grayscale value in [0, 1].
    ///   - lut: Color lookup table (256 entries).
    /// - Returns: Color entry for the input gray value.
    public static func applyLUT(grayValue: Double, lut: [ColorEntry]) -> ColorEntry {
        guard !lut.isEmpty else {
            return ColorEntry(red: 0, green: 0, blue: 0)
        }
        let index = max(0, min(lut.count - 1, Int(grayValue * Double(lut.count - 1))))
        return lut[index]
    }

    // MARK: - Color Utilities

    /// Converts HSV color to RGB.
    ///
    /// - Parameters:
    ///   - h: Hue in degrees (0-360).
    ///   - s: Saturation (0-1).
    ///   - v: Value (0-1).
    /// - Returns: RGB tuple as UInt8 values.
    public static func hsvToRGB(h: Double, s: Double, v: Double) -> (UInt8, UInt8, UInt8) {
        let c = v * s
        let x = c * (1.0 - abs((h / 60.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
        let m = v - c

        let r1: Double
        let g1: Double
        let b1: Double

        switch h {
        case 0..<60:
            (r1, g1, b1) = (c, x, 0)
        case 60..<120:
            (r1, g1, b1) = (x, c, 0)
        case 120..<180:
            (r1, g1, b1) = (0, c, x)
        case 180..<240:
            (r1, g1, b1) = (0, x, c)
        case 240..<300:
            (r1, g1, b1) = (x, 0, c)
        default:
            (r1, g1, b1) = (c, 0, x)
        }

        return (
            UInt8(min(255, max(0, Int((r1 + m) * 255.0)))),
            UInt8(min(255, max(0, Int((g1 + m) * 255.0)))),
            UInt8(min(255, max(0, Int((b1 + m) * 255.0))))
        )
    }

    // MARK: - Display Text

    /// Returns a display label for a pseudo-color palette.
    ///
    /// - Parameter palette: Pseudo-color palette type.
    /// - Returns: Human-readable label.
    public static func paletteLabel(for palette: PresentationStatePalette) -> String {
        switch palette {
        case .hotIron: return "Hot Iron"
        case .rainbow: return "Rainbow"
        case .hotMetal: return "Hot Metal"
        case .pet: return "PET"
        case .petTwentyStep: return "PET 20-Step"
        case .grayscale: return "Grayscale"
        case .custom: return "Custom"
        }
    }
}
