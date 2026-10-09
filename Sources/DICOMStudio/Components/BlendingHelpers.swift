// BlendingHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent image blending helpers
//
// NEMA-verified: 2026a, checked 2026-10-05 — alpha blend underlay·(1−α) + overlay·α agrees with Relative Opacity (0070,0403) in PS3.3 2026a C.11.14 Presentation State Blending Module (1.0 = superimposed replaces underlying); the citation read C.11.11, which is the Presentation State Relationship Module in 2026a, and was corrected; opacities and fusion labels are UI values

import Foundation

/// Platform-independent helpers for image blending operations.
///
/// Provides alpha blending, opacity control, and color map application
/// for PET/CT fusion and registered image overlay. The alpha blend follows the
/// Blending Presentation State's Relative Opacity (0070,0403), PS3.3 C.11.14:
/// 1.0 means the superimposed (overlay) image completely replaces the underlying
/// one, 0.0 that the underlying image shows through unchanged.
public enum BlendingHelpers: Sendable {

    // MARK: - Alpha Blending

    /// Blends two grayscale values with alpha opacity.
    ///
    /// result = underlay * (1 - alpha) + overlay * alpha
    ///
    /// - Parameters:
    ///   - underlay: Underlay (background) value in [0, 1].
    ///   - overlay: Overlay (foreground) value in [0, 1].
    ///   - alpha: Blending opacity in [0, 1].
    /// - Returns: Blended value in [0, 1].
    public static func blendGrayscale(underlay: Double, overlay: Double, alpha: Double) -> Double {
        let a = clampUnit(alpha)
        return clampUnit(underlay * (1.0 - a) + overlay * a)
    }

    /// Blends two color entries with alpha opacity.
    ///
    /// - Parameters:
    ///   - underlay: Underlay color.
    ///   - overlay: Overlay color.
    ///   - alpha: Blending opacity in [0, 1].
    /// - Returns: Blended color entry.
    public static func blendColor(underlay: ColorEntry, overlay: ColorEntry, alpha: Double) -> ColorEntry {
        let a = clampUnit(alpha)
        let oneMinusA = 1.0 - a

        let r = UInt8(min(255, Int(Double(underlay.red) * oneMinusA + Double(overlay.red) * a)))
        let g = UInt8(min(255, Int(Double(underlay.green) * oneMinusA + Double(overlay.green) * a)))
        let b = UInt8(min(255, Int(Double(underlay.blue) * oneMinusA + Double(overlay.blue) * a)))

        return ColorEntry(red: r, green: g, blue: b)
    }

    // MARK: - Fusion Blending

    /// Performs PET/CT fusion blending.
    ///
    /// The CT underlay is displayed as grayscale, and the PET overlay
    /// is colorized through a pseudo-color palette then blended on top.
    ///
    /// - Parameters:
    ///   - ctValue: CT grayscale value in [0, 1].
    ///   - petValue: PET grayscale value in [0, 1].
    ///   - petPalette: Color LUT for the PET overlay.
    ///   - opacity: PET overlay opacity in [0, 1].
    /// - Returns: Blended color entry.
    public static func fusionBlend(
        ctValue: Double,
        petValue: Double,
        petPalette: [ColorEntry],
        opacity: Double
    ) -> ColorEntry {
        let ctGray = UInt8(min(255, max(0, Int(ctValue * 255.0))))
        let underlayColor = ColorEntry(red: ctGray, green: ctGray, blue: ctGray)

        let overlayColor = ColorLUTHelpers.applyLUT(grayValue: petValue, lut: petPalette)

        return blendColor(underlay: underlayColor, overlay: overlayColor, alpha: opacity)
    }

    // MARK: - Opacity

    /// Clamps an opacity value to [0, 1].
    ///
    /// - Parameter opacity: Input opacity.
    /// - Returns: Clamped opacity.
    public static func clampOpacity(_ opacity: Double) -> Double {
        clampUnit(opacity)
    }

    /// Formats an opacity value as a percentage string.
    ///
    /// - Parameter opacity: Opacity value in [0, 1].
    /// - Returns: Formatted string (e.g., "50%").
    public static func opacityLabel(_ opacity: Double) -> String {
        let percent = Int(clampUnit(opacity) * 100)
        return "\(percent)%"
    }

    /// Minimum allowed opacity.
    public static let minOpacity: Double = 0.0

    /// Maximum allowed opacity.
    public static let maxOpacity: Double = 1.0

    /// Default blending opacity.
    public static let defaultOpacity: Double = 0.5

    /// Standard opacity step size for UI controls.
    public static let opacityStep: Double = 0.05

    // MARK: - Blending Modes Display

    /// Returns a display label for common fusion types.
    ///
    /// - Parameter type: Fusion type string.
    /// - Returns: Human-readable label.
    public static func fusionLabel(for type: String) -> String {
        switch type.uppercased() {
        case "PET/CT", "PETCT": return "PET/CT Fusion"
        case "SPECT/CT", "SPECTCT": return "SPECT/CT Fusion"
        case "MR/PET", "MRPET": return "MR/PET Fusion"
        default: return "Image Fusion"
        }
    }

    // MARK: - Utilities

    /// Clamps a value to [0, 1].
    private static func clampUnit(_ value: Double) -> Double {
        max(0.0, min(1.0, value))
    }
}
