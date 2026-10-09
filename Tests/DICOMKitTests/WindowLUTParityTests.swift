import XCTest
@testable import DICOMKit
@testable import DICOMCore   // WindowLUT.Parameters — the cache key — is internal
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// `WindowLUT` replaced the per-pixel window chain in
/// `PixelDataRenderer.renderMonochromeFrame` with a table lookup. The table is the
/// operator the Metal kernel will consume later (see `GPU_RENDERING_PLAN.md`, design
/// pillar 1), so its correctness is not "close enough" — it must reproduce the old
/// scalar arithmetic exactly, for every representable sample, across every bit depth
/// and VOI function the renderer supports.
///
/// These tests therefore re-implement the *original* loop as the oracle and demand
/// byte equality.
final class WindowLUTParityTests: XCTestCase {

    // MARK: - Oracle (the pre-LUT scalar chain, transcribed verbatim)

    private func scalarDisplayByte(
        rawValue: Int, descriptor: PixelDataDescriptor, window: WindowSettings
    ) -> UInt8 {
        let shiftedValue = rawValue >> descriptor.bitShift
        var maskedValue = shiftedValue & descriptor.storedBitMask

        if descriptor.isSigned {
            let signBit = 1 << (descriptor.bitsStored - 1)
            if maskedValue & signBit != 0 {
                maskedValue = maskedValue - (1 << descriptor.bitsStored)
            }
        }

        var normalized = window.apply(to: Double(maskedValue))
        if descriptor.photometricInterpretation == .monochrome1 {
            normalized = 1.0 - normalized
        }
        // The floor of the exact value (D63, PS3.3 C.11.2.1.2.1): 1e-9 absorbs the
        // few-ulp shortfall of an exact integer result, written out here rather than
        // calling WindowLUT.displayByte so the reference stays independent.
        return UInt8(max(0, min(255, normalized * 255.0 + 1e-9)))
    }

    private func descriptor(
        bitsAllocated: Int, bitsStored: Int, highBit: Int, isSigned: Bool,
        photometric: PhotometricInterpretation = .monochrome2,
        rows: Int = 4, columns: Int = 4
    ) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: rows, columns: columns,
            bitsAllocated: bitsAllocated, bitsStored: bitsStored, highBit: highBit,
            isSigned: isSigned, samplesPerPixel: 1,
            photometricInterpretation: photometric
        )
    }

    /// Every (bit depth, signedness, photometric) shape the monochrome renderer takes.
    private var descriptorMatrix: [PixelDataDescriptor] {
        var all: [PixelDataDescriptor] = []
        for photometric: PhotometricInterpretation in [.monochrome2, .monochrome1] {
            for isSigned in [false, true] {
                all.append(descriptor(bitsAllocated: 8, bitsStored: 8, highBit: 7,
                                      isSigned: isSigned, photometric: photometric))
                all.append(descriptor(bitsAllocated: 16, bitsStored: 16, highBit: 15,
                                      isSigned: isSigned, photometric: photometric))
                all.append(descriptor(bitsAllocated: 16, bitsStored: 12, highBit: 11,
                                      isSigned: isSigned, photometric: photometric))
                // High Bit above Bits Stored − 1: a non-zero bit shift.
                all.append(descriptor(bitsAllocated: 16, bitsStored: 12, highBit: 15,
                                      isSigned: isSigned, photometric: photometric))
                all.append(descriptor(bitsAllocated: 16, bitsStored: 10, highBit: 9,
                                      isSigned: isSigned, photometric: photometric))
            }
        }
        return all
    }

    private var windowMatrix: [WindowSettings] {
        [
            WindowSettings(center: 40, width: 400),
            WindowSettings(center: 2048, width: 4096),
            WindowSettings(center: 0, width: 1),           // degenerate minimum width
            WindowSettings(center: -500, width: 1500),     // signed / negative centre
            WindowSettings(center: 32768, width: 65536),
            WindowSettings(center: 40, width: 400, function: .linearExact),
            WindowSettings(center: 40, width: 400, function: .sigmoid),
            WindowSettings(center: 2048, width: 4096, function: .sigmoid)
        ]
    }

    // MARK: - Table equals the scalar chain, entry for entry

    func testTableMatchesScalarChainForEveryEntry() {
        for descriptor in descriptorMatrix {
            for window in windowMatrix {
                let lut = WindowLUT.makeGrayscale(descriptor: descriptor, window: window)
                XCTAssertEqual(lut.count, descriptor.bytesPerSample == 1 ? 256 : 65_536)

                for rawValue in 0..<lut.count {
                    let expected = scalarDisplayByte(
                        rawValue: rawValue, descriptor: descriptor, window: window
                    )
                    if lut[rawValue] != expected {
                        XCTFail("""
                            LUT diverged at raw value \(rawValue): got \(lut[rawValue]), \
                            expected \(expected) — bitsAllocated \(descriptor.bitsAllocated), \
                            bitsStored \(descriptor.bitsStored), highBit \(descriptor.highBit), \
                            signed \(descriptor.isSigned), \
                            \(descriptor.photometricInterpretation.rawValue), \
                            window \(window.center)/\(window.width) \(window.function.rawValue)
                            """)
                        return   // one failure per configuration is enough to diagnose
                    }
                }
            }
        }
    }

    // MARK: - Rendered frames are byte-identical

    #if canImport(CoreGraphics)
    /// Renders through `PixelDataRenderer` and compares against a frame windowed by the
    /// oracle — the end-to-end version of the check above, including the byte assembly
    /// and the frame-bounds handling.
    func testRenderedFrameMatchesScalarChain() throws {
        for descriptor in descriptorMatrix {
            let totalPixels = descriptor.pixelsPerFrame
            var raws: [Int] = []
            var bytes = Data()
            let maxRaw = descriptor.bytesPerSample == 1 ? 255 : 65_535
            for i in 0..<totalPixels {
                // Spread the samples over the full representable range, including both
                // endpoints, so clamping at either end of the window is exercised.
                let raw = (i * maxRaw) / max(1, totalPixels - 1)
                raws.append(raw)
                if descriptor.bytesPerSample == 1 {
                    bytes.append(UInt8(raw))
                } else {
                    bytes.append(UInt8(raw & 0xFF))
                    bytes.append(UInt8((raw >> 8) & 0xFF))
                    for _ in 2..<descriptor.bytesPerSample { bytes.append(0) }
                }
            }

            let pixelData = PixelData(data: bytes, descriptor: descriptor)
            let renderer = PixelDataRenderer(pixelData: pixelData)

            for window in windowMatrix {
                let image = try XCTUnwrap(renderer.renderMonochromeFrame(0, window: window))
                let rendered = try XCTUnwrap(image.dataProvider?.data as Data?)
                XCTAssertEqual(rendered.count, totalPixels)

                let expected = raws.map {
                    scalarDisplayByte(rawValue: $0, descriptor: descriptor, window: window)
                }
                XCTAssertEqual([UInt8](rendered), expected,
                               "rendered frame diverged for \(descriptor.bitsStored)-bit "
                               + "signed=\(descriptor.isSigned) "
                               + "window \(window.center)/\(window.width)")
            }
        }
    }

    /// A single-byte-per-sample frame must index the 256-entry table, not a 16-bit one.
    /// Getting the table size wrong is the one way this refactor could trap rather than
    /// merely differ, so it gets its own check at both endpoints.
    func testEightBitFrameUsesByteIndexedTable() throws {
        let descriptor = self.descriptor(bitsAllocated: 8, bitsStored: 8, highBit: 7,
                                         isSigned: false, rows: 1, columns: 256)
        let bytes = Data((0...255).map { UInt8($0) })
        let renderer = PixelDataRenderer(pixelData: PixelData(data: bytes, descriptor: descriptor))
        let window = WindowSettings(center: 128, width: 256)
        let image = try XCTUnwrap(renderer.renderMonochromeFrame(0, window: window))
        let rendered = [UInt8](try XCTUnwrap(image.dataProvider?.data as Data?))
        XCTAssertEqual(rendered.count, 256)
        XCTAssertEqual(rendered.first, scalarDisplayByte(rawValue: 0, descriptor: descriptor,
                                                         window: window))
        XCTAssertEqual(rendered.last, scalarDisplayByte(rawValue: 255, descriptor: descriptor,
                                                        window: window))
    }
    #endif

    // MARK: - Cache behaviour

    func testCacheReturnsEqualTablesAndDoesNotSplitOnExplanation() {
        let descriptor = self.descriptor(bitsAllocated: 16, bitsStored: 12, highBit: 11,
                                         isSigned: false)
        let plain = WindowSettings(center: 40, width: 400)
        let labelled = WindowSettings(center: 40, width: 400, explanation: "SOFT TISSUE")

        let first = WindowLUT.grayscale(descriptor: descriptor, window: plain)
        let second = WindowLUT.grayscale(descriptor: descriptor, window: labelled)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, WindowLUT.makeGrayscale(descriptor: descriptor, window: plain))
    }

    /// Two descriptors that differ only in dimensions must share one cached table —
    /// otherwise every differently-sized image in a study rebuilds it.
    func testCacheIgnoresDimensions() {
        let small = descriptor(bitsAllocated: 16, bitsStored: 16, highBit: 15,
                               isSigned: false, rows: 8, columns: 8)
        let large = descriptor(bitsAllocated: 16, bitsStored: 16, highBit: 15,
                               isSigned: false, rows: 3000, columns: 4000)
        let window = WindowSettings(center: 1000, width: 2000)
        XCTAssertEqual(
            WindowLUT.Parameters(descriptor: small, window: window),
            WindowLUT.Parameters(descriptor: large, window: window)
        )
    }

    /// Signedness, bit depth and photometric interpretation must each split the cache.
    func testCacheKeyDistinguishesRenderRelevantFields() {
        let window = WindowSettings(center: 100, width: 200)
        let base = descriptor(bitsAllocated: 16, bitsStored: 12, highBit: 11, isSigned: false)
        let variants = [
            descriptor(bitsAllocated: 16, bitsStored: 12, highBit: 11, isSigned: true),
            descriptor(bitsAllocated: 16, bitsStored: 16, highBit: 15, isSigned: false),
            descriptor(bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false),
            descriptor(bitsAllocated: 16, bitsStored: 12, highBit: 15, isSigned: false),
            descriptor(bitsAllocated: 16, bitsStored: 12, highBit: 11, isSigned: false,
                       photometric: .monochrome1)
        ]
        let baseKey = WindowLUT.Parameters(descriptor: base, window: window)
        for variant in variants {
            XCTAssertNotEqual(baseKey, WindowLUT.Parameters(descriptor: variant, window: window))
        }
        for other in [WindowSettings(center: 101, width: 200),
                      WindowSettings(center: 100, width: 201),
                      WindowSettings(center: 100, width: 200, function: .sigmoid)] {
            XCTAssertNotEqual(baseKey, WindowLUT.Parameters(descriptor: base, window: other))
        }
    }
}
