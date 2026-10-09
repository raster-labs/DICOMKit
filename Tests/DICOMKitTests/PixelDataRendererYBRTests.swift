import XCTest
import DICOMCore
@testable import DICOMKit

#if canImport(CoreGraphics)
import CoreGraphics

/// Pins `PixelDataRenderer`'s colour conversions to PS3.3 C.7.6.3.1.2:
/// - YBR_FULL / YBR_FULL_422 are inverted with the full-range equations,
/// - YBR_PARTIAL_420 / YBR_PARTIAL_422 with the partial-range (Y − 16) equations,
/// - YBR_ICT / YBR_RCT are JPEG 2000 codestream transforms the decoder has already
///   inverted, so the samples are passed through as RGB,
/// - native YBR_FULL_422 is the packed "Y1 Y2 Cb Cr" layout.
final class PixelDataRendererYBRTests: XCTestCase {

    // MARK: - Forward equations, quoted from PS3.3 C.7.6.3.1.2

    /// YBR_FULL, Bits Allocated 8:
    /// Y = .2990R + .5870G + .1140B; CB = −.1687R − .3313G + .5000B + 128;
    /// CR = .5000R − .4187G − .0813B + 128
    private func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }

    private func ybrFull(r: Double, g: Double, b: Double) -> (UInt8, UInt8, UInt8) {
        let y = 0.2990 * r + 0.5870 * g + 0.1140 * b
        let cb = -0.1687 * r - 0.3313 * g + 0.5000 * b + 128
        let cr = 0.5000 * r - 0.4187 * g - 0.0813 * b + 128
        return (byte(y), byte(cb), byte(cr))
    }

    /// YBR_PARTIAL_420, Bits Allocated 8:
    /// Y = .2568R + .5041G + .0979B + 16; CB = −.1482R − .2910G + .4392B + 128;
    /// CR = .4392R − .3678G − .0714B + 128
    private func ybrPartial(r: Double, g: Double, b: Double) -> (UInt8, UInt8, UInt8) {
        let y = 0.2568 * r + 0.5041 * g + 0.0979 * b + 16
        let cb = -0.1482 * r - 0.2910 * g + 0.4392 * b + 128
        let cr = 0.4392 * r - 0.3678 * g - 0.0714 * b + 128
        return (byte(y), byte(cb), byte(cr))
    }

    private let samples: [(Double, Double, Double)] = [
        (0, 0, 0), (255, 255, 255), (255, 0, 0), (0, 255, 0), (0, 0, 255),
        (128, 128, 128), (200, 30, 90), (17, 250, 140), (64, 64, 200), (255, 128, 0),
    ]

    private func descriptor(_ pi: PhotometricInterpretation, columns: Int, rows: Int = 1) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: rows, columns: columns, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            samplesPerPixel: 3, photometricInterpretation: pi, planarConfiguration: 0
        )
    }

    private func rgba(of image: CGImage?) throws -> [UInt8] {
        let cg = try XCTUnwrap(image)
        let px = try XCTUnwrap(cg.dataProvider?.data)
        return Array(UnsafeBufferPointer(start: CFDataGetBytePtr(px), count: CFDataGetLength(px)))
    }

    private func assertRoundTrip(pi: PhotometricInterpretation,
                                 forward: (Double, Double, Double) -> (UInt8, UInt8, UInt8),
                                 tolerance: Int = 2) throws {
        var data = Data()
        for (r, g, b) in samples {
            let (y, cb, cr) = forward(r, g, b)
            data.append(contentsOf: [y, cb, cr])
        }
        let renderer = PixelDataRenderer(pixelData: PixelData(data: data, descriptor: descriptor(pi, columns: samples.count)))
        let out = try rgba(of: renderer.renderColorFrame(0))
        XCTAssertEqual(out.count, samples.count * 4)
        for (i, (r, g, b)) in samples.enumerated() {
            let o = i * 4
            XCTAssertLessThanOrEqual(abs(Int(out[o]) - Int(r)), tolerance, "\(pi.rawValue) pixel \(i) R")
            XCTAssertLessThanOrEqual(abs(Int(out[o + 1]) - Int(g)), tolerance, "\(pi.rawValue) pixel \(i) G")
            XCTAssertLessThanOrEqual(abs(Int(out[o + 2]) - Int(b)), tolerance, "\(pi.rawValue) pixel \(i) B")
        }
    }

    // MARK: - Full range

    func test_ybrFull_invertsTheFullRangeEquations() throws {
        try assertRoundTrip(pi: .ybrFull, forward: ybrFull)
    }

    func test_ybrFull_blackIsYZero_noColourIsHalfScale() {
        // "Black is represented by Y equal to zero. The absence of color is
        // represented by both CB and CR values equal to half full scale."
        let (r, g, b) = PixelDataRenderer.ybrFullToRGB(y: 0, cb: 128, cr: 128)
        XCTAssertEqual([r, g, b], [0, 0, 0])
        let (r2, g2, b2) = PixelDataRenderer.ybrFullToRGB(y: 255, cb: 128, cr: 128)
        XCTAssertEqual([r2, g2, b2], [255, 255, 255])
    }

    // MARK: - Partial range

    func test_ybrPartial420_invertsThePartialRangeEquations() throws {
        try assertRoundTrip(pi: .ybrPartial420, forward: ybrPartial)
    }

    func test_ybrPartial422_usesThePartialRangeEquations_whenUpsampled() throws {
        try assertRoundTrip(pi: .ybrPartial422, forward: ybrPartial)
    }

    func test_ybrPartial_blackIsY16_whiteIsY235() {
        // "black corresponds to Y = 16", "Y is restricted to 220 levels (i.e., the
        // maximum value is 235)", "lack of color is represented by CB and CR equal to 128"
        let black = PixelDataRenderer.ybrPartialToRGB(y: 16, cb: 128, cr: 128)
        XCTAssertEqual([black.0, black.1, black.2], [0, 0, 0])
        let white = PixelDataRenderer.ybrPartialToRGB(y: 235, cb: 128, cr: 128)
        XCTAssertEqual([white.0, white.1, white.2], [255, 255, 255])
        // Treating a partial-range Y=16 with the full-range equation would give 16, not 0.
        let wrong = PixelDataRenderer.ybrFullToRGB(y: 16, cb: 128, cr: 128)
        XCTAssertEqual(wrong.0, 16)
    }

    // MARK: - JPEG 2000 transforms

    func test_ybrICT_and_ybrRCT_areNotReconverted() throws {
        // The decoder has already inverted the ISO/IEC 15444-1 component transform;
        // the buffer is RGB and must reach the screen unchanged.
        var data = Data()
        for (r, g, b) in samples { data.append(contentsOf: [UInt8(r), UInt8(g), UInt8(b)]) }
        for pi in [PhotometricInterpretation.ybrICT, .ybrRCT] {
            let renderer = PixelDataRenderer(pixelData: PixelData(data: data, descriptor: descriptor(pi, columns: samples.count)))
            let out = try rgba(of: renderer.renderColorFrame(0))
            for (i, (r, g, b)) in samples.enumerated() {
                XCTAssertEqual(Array(out[(i * 4)..<(i * 4 + 3)]), [UInt8(r), UInt8(g), UInt8(b)], "\(pi.rawValue) pixel \(i)")
            }
        }
    }

    // MARK: - Native 4:2:2 packing

    func test_nativeYbrFull422_isPackedTwoYThenCbCr() throws {
        // "Two Y values shall be stored followed by one CB and one CR value. The CB
        // and CR values shall be sampled at the location of the first of the two Y
        // values." Value Length is Rows × Columns × 2, not × 3.
        let (y1, cb, cr) = ybrFull(r: 200, g: 30, b: 90)
        let (y2, _, _) = ybrFull(r: 210, g: 40, b: 100)
        let packed = Data([y1, y2, cb, cr])
        XCTAssertEqual(packed.count, 1 * 2 * 2)
        let renderer = PixelDataRenderer(pixelData: PixelData(data: packed, descriptor: descriptor(.ybrFull422, columns: 2)))
        let out = try rgba(of: renderer.renderColorFrame(0))
        XCTAssertEqual(out.count, 8)
        let first = PixelDataRenderer.ybrFullToRGB(y: Double(y1), cb: Double(cb), cr: Double(cr))
        let second = PixelDataRenderer.ybrFullToRGB(y: Double(y2), cb: Double(cb), cr: Double(cr))
        XCTAssertEqual(Array(out[0..<3]), [first.0, first.1, first.2])
        XCTAssertEqual(Array(out[4..<7]), [second.0, second.1, second.2])
        XCTAssertLessThanOrEqual(abs(Int(first.0) - 200), 2)
        XCTAssertLessThanOrEqual(abs(Int(second.2) - 100), 3)
    }
}

#endif
