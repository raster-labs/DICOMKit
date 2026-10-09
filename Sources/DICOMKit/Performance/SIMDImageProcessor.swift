// NEMA-verified: 2026a, checked 2026-09-29 — applyWindowLevel implements the PS3.3 2026a C.11.2.1.2.1 LINEAR pseudo-code (c − 0.5, w − 1), C.11.2.1.2.1 LINEAR_EXACT and C.11.2.1.3 SIGMOID, operation-for-operation identical to WindowSettings.apply (P-RENDER)
import Foundation
import DICOMCore

#if canImport(Accelerate)
import Accelerate

/// SIMD-accelerated image processing operations for DICOM pixel data
///
/// Provides optimized implementations of common image processing operations
/// using vector instructions (SIMD) for improved performance.
///
/// This implementation uses Apple's Accelerate framework and is only available
/// on Apple platforms (iOS, macOS, visionOS).
public struct SIMDImageProcessor {

    /// Applies the VOI window transformation to pixel data using SIMD acceleration.
    ///
    /// Implements the default LINEAR function of PS3.3 C.11.2.1.2.1 exactly as the
    /// standard's pseudo-code states it, with `ymin = 0` and `ymax = 255`:
    ///
    /// ```
    /// if (x <= c - 0.5 - (w-1)/2), then y = ymin
    /// else if (x > c - 0.5 + (w-1)/2), then y = ymax
    /// else y = ((x - (c - 0.5)) / (w-1) + 0.5) * (ymax - ymin) + ymin
    /// ```
    ///
    /// The arithmetic is carried out in `Double`, in the same order as
    /// `WindowSettings.apply(to:)` — the scalar path `WindowLUT` tabulates for
    /// `PixelDataRenderer` — so the two produce byte-identical output for every
    /// input value. `WindowLUTParityTests` / `SIMDImageProcessorTests` pin that.
    ///
    /// - Parameters:
    ///   - pixelData: Input samples as unsigned stored values (already shifted to
    ///     bit 0 and masked to Bits Stored; sign extension is not applied here).
    ///   - windowCenter: Window Center (0028,1050), `c` above.
    ///   - windowWidth: Window Width (0028,1051), `w` above. Values below 1 are
    ///     clamped to 1, exactly as `WindowSettings.init` does; the standard
    ///     states "Window Width (0028,1051) shall always be greater than or equal to 1".
    ///   - bitsStored: Retained for source compatibility; the samples are taken as
    ///     already-masked stored values, so it does not affect the result.
    /// - Returns: Transformed pixel data (UInt8 values, 0-255 range)
    public static func applyWindowLevel(
        to pixelData: [UInt16],
        windowCenter: Double,
        windowWidth: Double,
        bitsStored: Int = 16
    ) -> [UInt8] {
        applyWindowLevel(
            to: pixelData,
            window: WindowSettings(center: windowCenter, width: windowWidth)
        )
    }

    /// Applies a ``WindowSettings`` (LINEAR, LINEAR_EXACT or SIGMOID) using SIMD.
    ///
    /// Dispatches on `window.function`:
    /// - `LINEAR` — PS3.3 C.11.2.1.2.1 pseudo-code (see ``applyWindowLevel(to:windowCenter:windowWidth:bitsStored:)``).
    /// - `LINEAR_EXACT` — `y = (x - c) / w + 0.5` clipped to the output range.
    /// - `SIGMOID` — PS3.3 C.11.2.1.3: `y = (ymax - ymin) / (1 + exp(-4 (x - c) / w)) + ymin`.
    ///
    /// Every branch performs the same floating-point operations, in the same order,
    /// as `WindowSettings.apply(to:)`, then `WindowLUT.displayByte` (× 255, the D63 tolerance, truncated)
    /// — the exact chain `WindowLUT.Parameters.build()` runs for an unsigned
    /// MONOCHROME2 sample. Output is therefore bit-identical to the scalar path.
    public static func applyWindowLevel(
        to pixelData: [UInt16],
        window: WindowSettings
    ) -> [UInt8] {
        let count = pixelData.count
        var output = [UInt8](repeating: 0, count: count)
        guard count > 0 else { return output }

        let n = vDSP_Length(count)
        let center = window.center
        let width = window.width // WindowSettings.admissibleWidth: >= 1 for LINEAR, > 0 otherwise

        // Stored values → Double, matching `Double(maskedValue)` in the scalar path.
        var x = [Double](repeating: 0, count: count)
        vDSP_vfltu16D(pixelData, 1, &x, 1, n)

        switch window.function {
        case .linear:
            if width == 1.0 {
                // C.11.2.1.2.1, w = 1: a threshold. x <= c - 0.5 → ymin, x > c - 0.5 → ymax.
                // The continuous segment "will never be reached for that case", and
                // (w - 1) would be 0, so it is not evaluated at all.
                // d = (c - 0.5) - x; d >= 0 ⇔ x <= c - 0.5 → 0, otherwise 255.
                var negX = [Double](repeating: 0, count: count)
                vDSP_vnegD(x, 1, &negX, 1, n)
                var threshold = center - 0.5
                vDSP_vsaddD(negX, 1, &threshold, &negX, 1, n)
                // vlim: +255 where d >= 0, −255 where d < 0.
                var zero = 0.0
                var limit = 255.0
                vDSP_vlimD(negX, 1, &zero, &limit, &negX, 1, n)
                // (255 − lim) / 2 → 0 where d >= 0, 255 where d < 0.
                vDSP_vnegD(negX, 1, &negX, 1, n)
                vDSP_vsaddD(negX, 1, &limit, &negX, 1, n)
                var half = 0.5
                vDSP_vsmulD(negX, 1, &half, &x, 1, n)
            } else {
                // y = ((x - (c - 0.5)) / (w - 1)) + 0.5, then × 255 and clip to [0, 255].
                // The clip reproduces the two boundary branches of the pseudo-code:
                // the linear segment evaluates to exactly 0 and 255 at the boundaries,
                // so clamping and the piecewise definition agree everywhere.
                var offset = -(center - 0.5)
                vDSP_vsaddD(x, 1, &offset, &x, 1, n)
                var divisor = width - 1.0
                vDSP_vsdivD(x, 1, &divisor, &x, 1, n)
                var half = 0.5
                vDSP_vsaddD(x, 1, &half, &x, 1, n)
                scaleClipAndTruncate(&x, into: &output, n)
                return output
            }
            scaleClipAndTruncate(&x, into: &output, n)
            return output

        case .linearExact:
            // WindowSettings.applyLinearExact: (x - c) / w + 0.5, boundaries at c ± w/2.
            var offset = -center
            vDSP_vsaddD(x, 1, &offset, &x, 1, n)
            var divisor = width
            vDSP_vsdivD(x, 1, &divisor, &x, 1, n)
            var half = 0.5
            vDSP_vsaddD(x, 1, &half, &x, 1, n)
            scaleClipAndTruncate(&x, into: &output, n)
            return output

        case .sigmoid:
            // WindowSettings.applySigmoid: exponent = -4 (x - c) / w; 1 / (1 + exp(exponent)).
            var offset = -center
            vDSP_vsaddD(x, 1, &offset, &x, 1, n)
            var scale = -4.0
            vDSP_vsmulD(x, 1, &scale, &x, 1, n)
            var divisor = width
            vDSP_vsdivD(x, 1, &divisor, &x, 1, n)
            // `exp` is evaluated with the same libm routine the scalar path calls,
            // not vForce's `vvexp`, whose last-ULP differences could move a value
            // across a truncation boundary and break the byte-for-byte parity.
            var exponent = x.map { Foundation.exp($0) }
            var one = 1.0
            vDSP_vsaddD(exponent, 1, &one, &exponent, 1, n)
            vDSP_svdivD(&one, exponent, 1, &x, 1, n)
            scaleClipAndTruncate(&x, into: &output, n)
            return output
        }
    }

    /// `WindowLUT.displayByte` — the scalar path's final step — vectorised: multiply,
    /// add `WindowLUT.quantisationTolerance`, clip, truncate toward zero
    /// (`vDSP_vfixu8D` truncates, as the `UInt8(_:)` initializer does). The same
    /// operations in the same order, so the bytes are identical (D63).
    private static func scaleClipAndTruncate(
        _ normalized: inout [Double],
        into output: inout [UInt8],
        _ n: vDSP_Length
    ) {
        var scale = 255.0
        vDSP_vsmulD(normalized, 1, &scale, &normalized, 1, n)
        var tolerance = WindowLUT.quantisationTolerance
        vDSP_vsaddD(normalized, 1, &tolerance, &normalized, 1, n)
        var lower = 0.0
        var upper = 255.0
        vDSP_vclipD(normalized, 1, &lower, &upper, &normalized, 1, n)
        vDSP_vfixu8D(normalized, 1, &output, 1, n)
    }

    /// Applies inversion (MONOCHROME1) to pixel data using SIMD
    ///
    /// - Parameter pixelData: Input pixel data (UInt8 values, 0-255)
    /// - Returns: Inverted pixel data
    public static func invertPixels(_ pixelData: [UInt8]) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: pixelData.count)

        // Convert to float
        var floatPixels = [Float](repeating: 0, count: pixelData.count)
        vDSP_vfltu8(pixelData, 1, &floatPixels, 1, vDSP_Length(pixelData.count))

        // Invert: output = 255 - input
        var maxValue: Float = 255
        vDSP_vneg(floatPixels, 1, &floatPixels, 1, vDSP_Length(pixelData.count))
        vDSP_vsadd(floatPixels, 1, &maxValue, &floatPixels, 1, vDSP_Length(pixelData.count))

        // Convert back to UInt8
        vDSP_vfixu8(floatPixels, 1, &output, 1, vDSP_Length(pixelData.count))

        return output
    }

    /// Normalizes pixel data to 8-bit range using SIMD
    ///
    /// Maps input values from [minValue, maxValue] to [0, 255]
    ///
    /// - Parameters:
    ///   - pixelData: Input pixel data
    ///   - minValue: Minimum input value
    ///   - maxValue: Maximum input value
    /// - Returns: Normalized pixel data (UInt8)
    public static func normalize(
        _ pixelData: [UInt16],
        minValue: UInt16,
        maxValue: UInt16
    ) -> [UInt8] {
        let count = pixelData.count
        var output = [UInt8](repeating: 0, count: count)

        let range = Double(maxValue) - Double(minValue)
        guard range > 0 else {
            return output
        }

        let scale = 255.0 / range
        let offset = -Double(minValue) * scale

        // Convert to float
        var floatPixels = [Float](repeating: 0, count: count)
        vDSP_vfltu16(pixelData, 1, &floatPixels, 1, vDSP_Length(count))

        // Scale and offset
        var scaleFloat = Float(scale)
        var offsetFloat = Float(offset)
        vDSP_vsmsa(floatPixels, 1, &scaleFloat, &offsetFloat, &floatPixels, 1, vDSP_Length(count))

        // Clip to [0, 255]
        var lowerBound: Float = 0
        var upperBound: Float = 255
        vDSP_vclip(floatPixels, 1, &lowerBound, &upperBound, &floatPixels, 1, vDSP_Length(count))

        // Convert to UInt8
        vDSP_vfixu8(floatPixels, 1, &output, 1, vDSP_Length(count))

        return output
    }

    /// Finds minimum and maximum values in pixel data using SIMD
    ///
    /// - Parameter pixelData: Input pixel data
    /// - Returns: Tuple of (min, max) values
    public static func findMinMax(_ pixelData: [UInt16]) -> (min: UInt16, max: UInt16) {
        guard !pixelData.isEmpty else {
            return (0, 0)
        }

        // Convert to float for vDSP operations
        var floatPixels = [Float](repeating: 0, count: pixelData.count)
        vDSP_vfltu16(pixelData, 1, &floatPixels, 1, vDSP_Length(pixelData.count))

        var minValue: Float = 0
        var maxValue: Float = 0

        vDSP_minv(floatPixels, 1, &minValue, vDSP_Length(pixelData.count))
        vDSP_maxv(floatPixels, 1, &maxValue, vDSP_Length(pixelData.count))

        return (min: UInt16(minValue), max: UInt16(maxValue))
    }

    /// Applies linear contrast adjustment using SIMD
    ///
    /// - Parameters:
    ///   - pixelData: Input pixel data (UInt8)
    ///   - alpha: Contrast multiplier (1.0 = no change, >1.0 = more contrast)
    ///   - beta: Brightness offset (0 = no change)
    /// - Returns: Adjusted pixel data
    public static func adjustContrast(
        _ pixelData: [UInt8],
        alpha: Float,
        beta: Float
    ) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: pixelData.count)

        // Convert to float
        var floatPixels = [Float](repeating: 0, count: pixelData.count)
        vDSP_vfltu8(pixelData, 1, &floatPixels, 1, vDSP_Length(pixelData.count))

        // Apply: output = alpha * input + beta
        var alphaVar = alpha
        var betaVar = beta
        vDSP_vsmsa(floatPixels, 1, &alphaVar, &betaVar, &floatPixels, 1, vDSP_Length(pixelData.count))

        // Clip to [0, 255]
        var lowerBound: Float = 0
        var upperBound: Float = 255
        vDSP_vclip(floatPixels, 1, &lowerBound, &upperBound, &floatPixels, 1, vDSP_Length(pixelData.count))

        // Convert back to UInt8
        vDSP_vfixu8(floatPixels, 1, &output, 1, vDSP_Length(pixelData.count))

        return output
    }
}

#endif
