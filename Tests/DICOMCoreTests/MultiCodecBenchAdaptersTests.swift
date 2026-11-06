import Testing
import Foundation
@testable import DICOMCore

/// Round-trip + interop verification for the multi-format codec-bench adapters
/// (SwiftJLI JPEG, JXLSwift JPEG XL) and their CLI peers (libjpeg-turbo `djpeg`,
/// libjxl `djxl`). The bench's entire premise is bit-exact lossless round-trips,
/// so these guard against silent layout/endianness/precision regressions.
@Suite("Multi-codec bench adapters")
struct MultiCodecBenchAdaptersTests {

    // MARK: - Fixtures

    private func descriptor(_ w: Int, _ h: Int, bitsAllocated: Int, bitsStored: Int,
                            spp: Int) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: h, columns: w,
            bitsAllocated: bitsAllocated, bitsStored: bitsStored, highBit: bitsStored - 1,
            isSigned: false, samplesPerPixel: spp,
            photometricInterpretation: spp == 1 ? .monochrome2 : .rgb,
            planarConfiguration: 0)
    }

    /// A structured (non-constant) frame so prediction/entropy paths are exercised.
    private func frame(_ w: Int, _ h: Int, bitsStored: Int, spp: Int, bytesPerSample: Int) -> Data {
        let maxVal = (1 << bitsStored) - 1
        var data = Data(count: w * h * spp * bytesPerSample)
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            var i = 0
            for y in 0..<h {
                for x in 0..<w {
                    for c in 0..<spp {
                        let v = ((x * 7 + y * 13 + c * 53) ^ (x &* y)) & maxVal
                        if bytesPerSample == 1 {
                            p[i] = UInt8(v); i += 1
                        } else {
                            p[i] = UInt8(v & 0xFF); p[i + 1] = UInt8((v >> 8) & 0xFF); i += 2
                        }
                    }
                }
            }
        }
        return data
    }

    // MARK: - SwiftJLI (JPEG, lossless SOF3)

    @Test("SwiftJLI lossless round-trip — 8-bit grayscale")
    func jliGray8() throws {
        let d = descriptor(40, 32, bitsAllocated: 8, bitsStored: 8, spp: 1)
        let original = frame(40, 32, bitsStored: 8, spp: 1, bytesPerSample: 1)
        let encoded = try JLICodec().encodeFrame(original, descriptor: d, frameIndex: 0, configuration: .lossless)
        let decoded = try JLICodec().decodeFrame(encoded, descriptor: d, frameIndex: 0)
        #expect(decoded == original)
    }

    @Test("SwiftJLI lossless round-trip — 16-bit (12-bit stored) grayscale")
    func jliGray16() throws {
        let d = descriptor(40, 32, bitsAllocated: 16, bitsStored: 12, spp: 1)
        let original = frame(40, 32, bitsStored: 12, spp: 1, bytesPerSample: 2)
        let encoded = try JLICodec().encodeFrame(original, descriptor: d, frameIndex: 0, configuration: .lossless)
        let decoded = try JLICodec().decodeFrame(encoded, descriptor: d, frameIndex: 0)
        #expect(decoded == original)
    }

    @Test("SwiftJLI lossless round-trip — 8-bit RGB")
    func jliRGB8() throws {
        let d = descriptor(24, 24, bitsAllocated: 8, bitsStored: 8, spp: 3)
        let original = frame(24, 24, bitsStored: 8, spp: 3, bytesPerSample: 1)
        let encoded = try JLICodec().encodeFrame(original, descriptor: d, frameIndex: 0, configuration: .lossless)
        let decoded = try JLICodec().decodeFrame(encoded, descriptor: d, frameIndex: 0)
        #expect(decoded == original)
    }

    // MARK: - JXLSwift (JPEG XL, lossless Modular)

    @Test("JXLSwift lossless round-trip — 8-bit grayscale")
    func jxlGray8() throws {
        let d = descriptor(40, 32, bitsAllocated: 8, bitsStored: 8, spp: 1)
        let original = frame(40, 32, bitsStored: 8, spp: 1, bytesPerSample: 1)
        let encoded = try JXLCodec().encodeFrame(original, descriptor: d, frameIndex: 0, configuration: .lossless)
        let decoded = try JXLCodec().decodeFrame(encoded, descriptor: d, frameIndex: 0)
        #expect(decoded == original)
    }

    @Test("JXLSwift lossless round-trip — 16-bit (12-bit stored) grayscale")
    func jxlGray16() throws {
        let d = descriptor(40, 32, bitsAllocated: 16, bitsStored: 12, spp: 1)
        let original = frame(40, 32, bitsStored: 12, spp: 1, bytesPerSample: 2)
        let encoded = try JXLCodec().encodeFrame(original, descriptor: d, frameIndex: 0, configuration: .lossless)
        let decoded = try JXLCodec().decodeFrame(encoded, descriptor: d, frameIndex: 0)
        #expect(decoded == original)
    }

    @Test("JXLSwift lossless round-trip — 8-bit RGB")
    func jxlRGB8() throws {
        let d = descriptor(24, 24, bitsAllocated: 8, bitsStored: 8, spp: 3)
        let original = frame(24, 24, bitsStored: 8, spp: 3, bytesPerSample: 1)
        let encoded = try JXLCodec().encodeFrame(original, descriptor: d, frameIndex: 0, configuration: .lossless)
        let decoded = try JXLCodec().decodeFrame(encoded, descriptor: d, frameIndex: 0)
        #expect(decoded == original)
    }

    // MARK: - CLI peer interop (PNM parse + endianness)

    #if os(macOS)
    @Test("djpeg decodes SwiftJLI's lossless JPEG bit-exactly — 8-bit")
    func djpegInterop8() throws {
        guard DjpegCLICodec.binaryPath != nil else { return }   // peer not installed
        let d = descriptor(40, 32, bitsAllocated: 8, bitsStored: 8, spp: 1)
        let original = frame(40, 32, bitsStored: 8, spp: 1, bytesPerSample: 1)
        let encoded = try JLICodec().encodeFrame(original, descriptor: d, frameIndex: 0, configuration: .lossless)
        let decoded = try DjpegCLICodec().decodeFrame(encoded, descriptor: d)
        #expect(decoded == original)
    }

    @Test("djpeg decodes SwiftJLI's lossless JPEG bit-exactly — 16-bit")
    func djpegInterop16() throws {
        guard DjpegCLICodec.binaryPath != nil else { return }
        let d = descriptor(40, 32, bitsAllocated: 16, bitsStored: 12, spp: 1)
        let original = frame(40, 32, bitsStored: 12, spp: 1, bytesPerSample: 2)
        let encoded = try JLICodec().encodeFrame(original, descriptor: d, frameIndex: 0, configuration: .lossless)
        let decoded = try DjpegCLICodec().decodeFrame(encoded, descriptor: d)
        #expect(decoded == original)
    }

    @Test("djxl decodes JXLSwift's lossless JXL bit-exactly — 8-bit")
    func djxlInterop8() throws {
        guard DjxlCLICodec.binaryPath != nil else { return }
        let d = descriptor(40, 32, bitsAllocated: 8, bitsStored: 8, spp: 1)
        let original = frame(40, 32, bitsStored: 8, spp: 1, bytesPerSample: 1)
        let encoded = try JXLCodec().encodeFrame(original, descriptor: d, frameIndex: 0, configuration: .lossless)
        let decoded = try DjxlCLICodec().decodeFrame(encoded, descriptor: d)
        #expect(decoded == original)
    }

    @Test("djxl decodes JXLSwift's lossless JXL bit-exactly — 16-bit")
    func djxlInterop16() throws {
        guard DjxlCLICodec.binaryPath != nil else { return }
        let d = descriptor(40, 32, bitsAllocated: 16, bitsStored: 12, spp: 1)
        let original = frame(40, 32, bitsStored: 12, spp: 1, bytesPerSample: 2)
        let encoded = try JXLCodec().encodeFrame(original, descriptor: d, frameIndex: 0, configuration: .lossless)
        let decoded = try DjxlCLICodec().decodeFrame(encoded, descriptor: d)
        #expect(decoded == original)
    }
    #endif
}
