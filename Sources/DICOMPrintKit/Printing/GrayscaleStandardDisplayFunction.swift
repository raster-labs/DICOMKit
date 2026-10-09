// NEMA-verified: 2026a, checked 2026-09-29 — the L(j) and j(L) coefficients a…m and A…I text-diffed against PS3.14 2026a 7.1 (Scripts/diff_printkit.py); transmissive and reflective hardcopy per 7.2 and 7.3; the 256 densities of Table D.2-1 reproduced within 0.0015 OD (the table prints 3 decimals) by PrintGSDFTests
// GrayscaleStandardDisplayFunction.swift
// DICOMPrintKit
//
// The Grayscale Standard Display Function (PS3.14), and what it says a print
// looks like.
//
// A P-Value is not a grey level. PS3.14 fixes its "units": a printer spreads
// the P-Values it receives evenly in JND Index between the darkest and the
// brightest luminance its film or paper can show, and the luminance of each
// JND Index is the GSDF's. So the density a conforming printer lays down for
// P-Value p is D(p) = −log10((L(j(p)) − La) / L0) (PS3.14 7.2), and the
// emulator's calibrated rendering (``DensityMapping/gsdf``) draws that film —
// its luminance under the stated viewing conditions, relative to the brightest
// the sheet can be, encoded for an sRGB screen or PDF.

import Foundation

/// The Grayscale Standard Display Function of PS3.14 7.1.
enum GrayscaleStandardDisplayFunction {

    // PS3.14 7.1: log10 L(j) as a rational polynomial in ln j.
    static let a = -1.3011877, b = -2.5840191e-2, c = 8.0242636e-2, d = -1.0320229e-1
    static let e = 1.3646699e-1, f = 2.8745620e-2, g = -2.5468404e-2, h = -3.1978977e-3
    static let k = 1.2992634e-4, m = 1.3635334e-3

    // PS3.14 7.1: j(L) as a polynomial in log10 L.
    static let A = 71.498068, B = 94.593053, C = 41.912053, D = 9.8247004
    static let E = 0.28175407, F = -1.1878455, G = -0.18014349, H = 0.14710899
    static let I = -0.017046845

    /// The JND Index range the function is defined over: 1 to 1023.
    static let jndRange: ClosedRange<Double> = 1...1023

    /// Luminance in cd/m² of JND Index `j` (clamped to 1…1023).
    static func gsdfLuminance(jndIndex j: Double) -> Double {
        let x = log(min(max(j, jndRange.lowerBound), jndRange.upperBound))
        let x2 = x * x, x3 = x2 * x, x4 = x3 * x, x5 = x4 * x
        let numerator = a + c * x + e * x2 + g * x3 + m * x4
        let denominator = 1 + b * x + d * x2 + f * x3 + h * x4 + k * x5
        return pow(10, numerator / denominator)
    }

    /// The JND Index of luminance `L` in cd/m².
    static func jndIndex(luminance: Double) -> Double {
        let y = log10(max(luminance, 1e-6))
        let y2 = y * y, y3 = y2 * y, y4 = y3 * y
        return A + B * y + C * y2 + D * y3 + E * y4
            + F * y4 * y + G * y4 * y2 + H * y4 * y3 + I * y4 * y4
    }
}

/// How a printed sheet is viewed: the light it is seen by, and the densities
/// it can hold (PS3.14 7.2, 7.3).
struct HardcopyViewing: Sendable, Equatable {

    /// Luminance of the light-box with no film present (transmissive), or of
    /// diffuse reflection of the illumination present (reflective): L0, cd/m².
    let illumination: Double

    /// Ambient light reflected by transmissive film: La, cd/m². Zero for
    /// reflective media, whose 7.3 relationship has no such term.
    let reflectedAmbientLight: Double

    /// Minimum and maximum optical density of the sheet.
    let minDensity: Double
    let maxDensity: Double

    /// Transmissive film on a light-box, with PS3.14 7.2's "typical values":
    /// L0 = 2000 cd/m², La = 10 cd/m².
    static func transmissive(minDensity: Double, maxDensity: Double) -> HardcopyViewing {
        HardcopyViewing(illumination: 2000, reflectedAmbientLight: 10,
                        minDensity: minDensity, maxDensity: maxDensity)
    }

    /// Reflective paper, with PS3.14 7.3's typical L0 = 150 cd/m².
    static func reflective(minDensity: Double, maxDensity: Double) -> HardcopyViewing {
        HardcopyViewing(illumination: 150, reflectedAmbientLight: 0,
                        minDensity: minDensity, maxDensity: maxDensity)
    }

    /// Luminance of a patch of optical density `density`:
    /// L = La + L0·10^−D (7.2; 7.3 with La = 0).
    func luminance(density: Double) -> Double {
        reflectedAmbientLight + illumination * pow(10, -density)
    }

    /// The darkest and brightest luminance the sheet can show.
    var luminanceRange: (min: Double, max: Double) {
        (luminance(density: maxDensity), luminance(density: minDensity))
    }

    /// The optical density a conforming printer produces for P-Value `p` of
    /// an `bits`-bit input: j spread linearly over j(Lmin)…j(Lmax), then
    /// D(p) = −log10((L(j(p)) − La) / L0).
    func density(pValue p: Double, bits: Int = 8) -> Double {
        -log10(max(1e-12, (luminance(pValue: p, bits: bits) - reflectedAmbientLight) / illumination))
    }

    /// The luminance the GSDF assigns P-Value `p` on this sheet.
    func luminance(pValue p: Double, bits: Int = 8) -> Double {
        let (low, high) = luminanceRange
        let jMin = GrayscaleStandardDisplayFunction.jndIndex(luminance: low)
        let jMax = GrayscaleStandardDisplayFunction.jndIndex(luminance: high)
        let span = Double((1 << bits) - 1)
        let j = jMin + (min(max(p, 0), span) / span) * (jMax - jMin)
        return GrayscaleStandardDisplayFunction.gsdfLuminance(jndIndex: j)
    }

    /// A luminance as an 8-bit sRGB-encoded grey, relative to the brightest
    /// the sheet can show — what a screen or a PDF reproduces of it.
    func displayValue(luminance: Double) -> UInt8 {
        let relative = min(max(luminance / luminanceRange.max, 0), 1)
        let encoded = relative <= 0.0031308
            ? 12.92 * relative
            : 1.055 * pow(relative, 1 / 2.4) - 0.055
        return UInt8(max(0, min(255, (encoded * 255).rounded())))
    }
}
