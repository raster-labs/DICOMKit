// NEMA-verified: 2026a, checked 2026-09-29 — Presentation LUT Shape IDENTITY/LIN OD per PS3.3 2026a C.11.4; Max Density (2010,0130) per PS3.6 Table 6-1 (C.11.4 text misprints it as 2010,1030); LIN OD transmission 10^-D per PS3.14 2026a 7.2 with La = 0; default densities are this toolkit's
// PresentationLUTTransform.swift
// DICOMPrintKit
//
// Applies a Presentation LUT to prepared print pixels.
//
// Reference: PS3.3 C.11.4 (Presentation LUT Module, the hardcopy one). That
// module enumerates IDENTITY and LIN OD only; INVERSE belongs to the softcopy
// module C.11.6 and is not legal in a print context, so inversion is realised
// here in the pixels instead — the same choice DCMTK makes with
// `--inverse-plut`. LIN OD: "input to Presentation LUT is in linear optical
// density over the range of Min Density (2010,0120) and Max Density" — the
// 2026a text of C.11.4 prints that tag as (2010,1030), a misprint: PS3.6
// Table 6-1 has Max Density (2010,0130).

import Foundation
import DICOMNetwork

/// The pixel-side half of the Presentation LUT.
///
/// The printer owns this transform whenever a legal shape is sent on the wire,
/// so this type exists for the two cases where nobody else will do it: the
/// on-screen film preview, which has no printer to defer to, and the rendered
/// inversion, which is *defined* as happening before transmission.
public enum PresentationLUTTransform {

    /// Film stock bounds, in hundredths of OD (the unit PS3.3 Table C.13-3 gives
    /// Min/Max Density), used when the film box does not state them. The
    /// standard sets no default — a printer uses its own minimum and maximum
    /// density — so 0.20 / 3.00 OD, ordinary clear-base film, is this
    /// toolkit's choice.
    public static let defaultMinDensity = 20
    public static let defaultMaxDensity = 300

    /// A 256-entry input → output curve for `shape`, or `nil` when the shape
    /// leaves 8-bit pixels unchanged (IDENTITY, or no shape at all).
    ///
    /// - Parameters:
    ///   - shape: the selected Presentation LUT option.
    ///   - minDensity: Min Density (2010,0120) in hundredths of OD.
    ///   - maxDensity: Max Density (2010,0130) in hundredths of OD.
    public static func curve(
        for shape: PresentationLUTShape?,
        minDensity: Int? = nil,
        maxDensity: Int? = nil
    ) -> [UInt8]? {
        switch shape {
        case nil, .identity:
            return nil
        case .inverseRendered:
            return (0...255).map { UInt8(255 - $0) }
        case .linearOpticalDensity:
            return linearOpticalDensityCurve(
                minDensity: minDensity ?? defaultMinDensity,
                maxDensity: maxDensity ?? defaultMaxDensity)
        }
    }

    /// The LIN OD transfer curve as a P-value → luminance table.
    ///
    /// Under LIN OD the input is linearly proportional to *optical density*, so
    /// low input prints light and high input dark. A screen shows transmitted
    /// luminance, which falls off as 10^(−OD): equal density steps are
    /// exponential luminance steps, not the straight line a negation draws.
    ///
    ///     OD(p) = Dmin + (p/255)·(Dmax − Dmin)
    ///     l(p)  = (10^(−OD(p)) − 10^(−Dmax)) / (10^(−Dmin) − 10^(−Dmax))
    static func linearOpticalDensityCurve(minDensity: Int, maxDensity: Int) -> [UInt8]? {
        let minOD = Double(minDensity) / 100
        let maxOD = Double(maxDensity) / 100
        guard maxOD > minOD else { return nil }

        let brightest = pow(10, -minOD)
        let darkest = pow(10, -maxOD)
        return (0...255).map { p in
            let density = minOD + (Double(p) / 255) * (maxOD - minOD)
            let luminance = (pow(10, -density) - darkest) / (brightest - darkest)
            return UInt8(max(0, min(255, (luminance * 255).rounded())))
        }
    }

    /// Applies `curve` to 8-bit samples.
    ///
    /// Colour samples are passed through untouched: a density curve has no
    /// meaning for an RGB box, and inverting only the luminance of a colour
    /// image would change its hue.
    public static func apply(
        curve: [UInt8],
        to samples: Data,
        samplesPerPixel: Int,
        bitsStored: Int
    ) -> Data {
        guard curve.count == 256, samplesPerPixel == 1, bitsStored <= 8 else {
            return samples
        }
        return Data(samples.map { curve[Int($0)] })
    }
}
