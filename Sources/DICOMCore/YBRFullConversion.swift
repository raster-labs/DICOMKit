// NEMA-verified: 2026a, checked 2026-10-01 — YBR_FULL forward equations (Y = .2990R + .5870G + .1140B; CB = -.1687R - .3313G + .5000B + 128; CR = .5000R - .4187G - .0813B + 128, half full scale 128 for 8 bits) dumped from PS3.3 2026a C.7.6.3.1.2; the inverse is computed from those nine coefficients. Used because PS3.5 2026a 8.2.4 / Table 8.2.4-1 permits SGcod MCT = 1 only under YBR_RCT / YBR_ICT, and J2KSwift applies the Part 1 colour transform to every 3-component image (D-CORE-3).

import Foundation

/// Converts native YBR_FULL samples to RGB.
///
/// PS3.3 2026a C.7.6.3.1.2 gives the RGB → YBR_FULL equations (CCIR Recommendation 601-2) for
/// Bits Allocated 8, with "half full scale" as the chrominance offset. This type inverts that
/// matrix exactly (no hand-copied inverse coefficients) and uses 2^(Bits Stored − 1) as half
/// full scale for wider samples. Results are rounded to the nearest integer and clamped to
/// 0 … 2^(Bits Stored) − 1, so the conversion is not bit-preserving.
public enum YBRFullConversion {

    /// The PS3.3 2026a C.7.6.3.1.2 forward matrix, rows Y, CB, CR over columns R, G, B.
    public static let forwardMatrix: [[Double]] = [
        [ 0.2990,  0.5870,  0.1140],
        [-0.1687, -0.3313,  0.5000],
        [ 0.5000, -0.4187, -0.0813],
    ]

    /// The inverse of ``forwardMatrix``: rows R, G, B over columns Y, CB − half, CR − half.
    public static let inverseMatrix: [[Double]] = {
        let m = forwardMatrix
        let a = m[0][0], b = m[0][1], c = m[0][2]
        let d = m[1][0], e = m[1][1], f = m[1][2]
        let g = m[2][0], h = m[2][1], i = m[2][2]
        let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        return [
            [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
            [(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
            [(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det],
        ]
    }()

    /// Whether `descriptor` describes native YBR_FULL samples this type can convert
    /// (3 unsigned samples, 8 or 16 bits allocated).
    public static func canConvert(_ descriptor: PixelDataDescriptor) -> Bool {
        descriptor.photometricInterpretation == .ybrFull
            && descriptor.samplesPerPixel == 3
            && !descriptor.isSigned
            && (descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16)
            && descriptor.bitsStored >= 1 && descriptor.bitsStored <= descriptor.bitsAllocated
    }

    /// The descriptor of the converted samples: Photometric Interpretation RGB, everything else
    /// (including Planar Configuration) unchanged.
    public static func rgbDescriptor(for descriptor: PixelDataDescriptor) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: descriptor.rows, columns: descriptor.columns,
            numberOfFrames: descriptor.numberOfFrames,
            bitsAllocated: descriptor.bitsAllocated, bitsStored: descriptor.bitsStored,
            highBit: descriptor.highBit, isSigned: descriptor.isSigned,
            samplesPerPixel: descriptor.samplesPerPixel,
            photometricInterpretation: .rgb,
            planarConfiguration: descriptor.planarConfiguration)
    }

    /// Converts every frame of `data` (native YBR_FULL, little-endian samples, laid out per
    /// `descriptor` incl. Planar Configuration 0 or 1) to RGB in the same layout.
    /// Returns `nil` when ``canConvert(_:)`` is false or `data` is shorter than the frames.
    public static func rgb(fromYBRFull data: Data, descriptor: PixelDataDescriptor) -> Data? {
        guard canConvert(descriptor) else { return nil }
        let pixelsPerFrame = descriptor.rows * descriptor.columns
        let bytesPerSample = descriptor.bitsAllocated / 8
        let frameBytes = pixelsPerFrame * 3 * bytesPerSample
        guard data.count >= frameBytes * descriptor.numberOfFrames else { return nil }

        let half = Double(1 << (descriptor.bitsStored - 1))
        let maxValue = Double((1 << descriptor.bitsStored) - 1)
        let mask = (1 << descriptor.bitsStored) - 1
        let inv = inverseMatrix
        let planar = descriptor.planarConfiguration == 1

        var out = [UInt8](data)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let src = raw.bindMemory(to: UInt8.self)
            func read(_ offset: Int) -> Int {
                bytesPerSample == 1 ? Int(src[offset]) & mask
                    : (Int(src[offset]) | Int(src[offset + 1]) << 8) & mask
            }
            func write(_ value: Double, _ offset: Int) {
                let v = UInt16(min(maxValue, max(0, value.rounded())))
                out[offset] = UInt8(v & 0xFF)
                if bytesPerSample == 2 { out[offset + 1] = UInt8(v >> 8) }
            }
            for frame in 0..<descriptor.numberOfFrames {
                let base = frame * frameBytes
                for p in 0..<pixelsPerFrame {
                    let step = planar ? pixelsPerFrame * bytesPerSample : bytesPerSample
                    let o0 = base + (planar ? p : p * 3) * bytesPerSample
                    let o1 = o0 + step, o2 = o1 + step
                    let y = Double(read(o0))
                    let cb = Double(read(o1)) - half
                    let cr = Double(read(o2)) - half
                    write(inv[0][0] * y + inv[0][1] * cb + inv[0][2] * cr, o0)
                    write(inv[1][0] * y + inv[1][1] * cb + inv[1][2] * cr, o1)
                    write(inv[2][0] * y + inv[2][1] * cb + inv[2][2] * cr, o2)
                }
            }
        }
        return Data(out)
    }
}
