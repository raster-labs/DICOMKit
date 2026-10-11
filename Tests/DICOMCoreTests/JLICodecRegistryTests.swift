import Testing
import Foundation
@testable import DICOMCore

/// Verifies that JLISwift is wired into `CodecRegistry` as the JPEG codec for all
/// four DICOM JPEG transfer syntaxes, and that the target syntax selects the right
/// process: bit-exact lossless (SOF3) for `.57`/`.70`, and lossy DCT (SOF0/SOF1)
/// for Baseline `.50` / Extended `.51`. Complements the bench-level direct-call
/// coverage in `MultiCodecBenchAdaptersTests`.
@Suite("JLISwift JPEG codec — registry wiring & lossy/lossless modes")
struct JLICodecRegistryTests {

    // MARK: - Transfer syntaxes

    private let baseline = TransferSyntax.jpegBaseline.uid       // .50  lossy 8-bit
    private let extended = TransferSyntax.jpegExtended.uid       // .51  lossy ≤12-bit
    private let lossless = TransferSyntax.jpegLossless.uid       // .57  SOF3
    private let losslessSV1 = TransferSyntax.jpegLosslessSV1.uid // .70  SOF3 P1

    private var allJPEG: [String] { [baseline, extended, lossless, losslessSV1] }

    // MARK: - Fixtures

    private func descriptor(_ w: Int, _ h: Int, bitsAllocated: Int, bitsStored: Int,
                            spp: Int, isSigned: Bool = false) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: h, columns: w,
            bitsAllocated: bitsAllocated, bitsStored: bitsStored, highBit: bitsStored - 1,
            isSigned: isSigned, samplesPerPixel: spp,
            photometricInterpretation: spp == 1 ? .monochrome2 : .rgb,
            planarConfiguration: 0)
    }

    /// High-frequency XOR pattern — the worst case for prediction/entropy, so a
    /// lossless round-trip that survives it survives anything.
    private func noisyFrame(_ w: Int, _ h: Int, bitsStored: Int, spp: Int, bytesPerSample: Int) -> Data {
        let maxVal = (1 << bitsStored) - 1
        var data = Data(count: w * h * spp * bytesPerSample)
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            var i = 0
            for y in 0..<h {
                for x in 0..<w {
                    for c in 0..<spp {
                        let v = ((x * 7 + y * 13 + c * 53) ^ (x &* y)) & maxVal
                        if bytesPerSample == 1 { p[i] = UInt8(v); i += 1 }
                        else { p[i] = UInt8(v & 0xFF); p[i + 1] = UInt8((v >> 8) & 0xFF); i += 2 }
                    }
                }
            }
        }
        return data
    }

    /// Smooth diagonal gradient — a fair target for the lossy DCT path (DCT is
    /// built for low-frequency content), so a fidelity bound is meaningful.
    private func smoothFrame(_ w: Int, _ h: Int, bitsStored: Int, spp: Int, bytesPerSample: Int) -> Data {
        let maxVal = (1 << bitsStored) - 1
        var data = Data(count: w * h * spp * bytesPerSample)
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            var i = 0
            for y in 0..<h {
                for x in 0..<w {
                    for _ in 0..<spp {
                        let v = ((x + y) * maxVal) / max(1, (w + h - 2))
                        if bytesPerSample == 1 { p[i] = UInt8(v & 0xFF); i += 1 }
                        else { p[i] = UInt8(v & 0xFF); p[i + 1] = UInt8((v >> 8) & 0xFF); i += 2 }
                    }
                }
            }
        }
        return data
    }

    /// Peak-signal-to-noise ratio (dB) between two equal-length sample buffers.
    private func psnr(_ a: Data, _ b: Data, bytesPerSample: Int, maxVal: Int) -> Double {
        precondition(a.count == b.count)
        let sampleCount = a.count / bytesPerSample
        var mse = 0.0
        let aB = [UInt8](a), bB = [UInt8](b)
        for s in 0..<sampleCount {
            let o = s * bytesPerSample
            let va = bytesPerSample == 1 ? Int(aB[o]) : Int(aB[o]) | (Int(aB[o + 1]) << 8)
            let vb = bytesPerSample == 1 ? Int(bB[o]) : Int(bB[o]) | (Int(bB[o + 1]) << 8)
            let d = Double(va - vb)
            mse += d * d
        }
        mse /= Double(sampleCount)
        if mse == 0 { return .infinity }
        return 10.0 * log10(Double(maxVal * maxVal) / mse)
    }

    // MARK: - Registry wiring

    @Test("CodecRegistry exposes a JLISwift decoder and encoder for all four JPEG syntaxes")
    func registryWiring() {
        let reg = CodecRegistry.shared
        for uid in allJPEG {
            #expect(reg.hasCodec(for: uid), "missing decoder for \(uid)")
            #expect(reg.hasEncoder(for: uid), "missing encoder for \(uid)")
            #expect(reg.codec(for: uid) is JLICodec, "decoder for \(uid) is not JLICodec")
            #expect(reg.encoder(for: uid) is JLICodec, "encoder for \(uid) is not JLICodec")
        }
    }

    // MARK: - Lossless (bit-exact through the registry)

    @Test("Registry lossless round-trip is bit-exact",
          arguments: [
            (uid: TransferSyntax.jpegLossless.uid, ba: 8, bs: 8, spp: 1, signed: false),
            (uid: TransferSyntax.jpegLossless.uid, ba: 16, bs: 12, spp: 1, signed: false),
            (uid: TransferSyntax.jpegLossless.uid, ba: 16, bs: 16, spp: 1, signed: false),
            (uid: TransferSyntax.jpegLossless.uid, ba: 8, bs: 8, spp: 3, signed: false),
            (uid: TransferSyntax.jpegLosslessSV1.uid, ba: 16, bs: 12, spp: 1, signed: false),
            (uid: TransferSyntax.jpegLosslessSV1.uid, ba: 8, bs: 8, spp: 3, signed: false),
            // Signed 16-bit (e.g. CT Hounsfield) — lossless preserves bytes regardless of sign.
            (uid: TransferSyntax.jpegLosslessSV1.uid, ba: 16, bs: 16, spp: 1, signed: true),
          ])
    func losslessRoundTrip(uid: String, ba: Int, bs: Int, spp: Int, signed: Bool) throws {
        let reg = CodecRegistry.shared
        let bps = ba <= 8 ? 1 : 2
        let d = descriptor(20, 16, bitsAllocated: ba, bitsStored: bs, spp: spp, isSigned: signed)
        let original = noisyFrame(20, 16, bitsStored: bs, spp: spp, bytesPerSample: bps)

        let encoder = try #require(reg.encoder(for: uid))
        let decoder = try #require(reg.codec(for: uid))
        #expect(encoder.canEncode(with: .lossless, descriptor: d))

        let encoded = try encoder.encodeFrame(original, descriptor: d, frameIndex: 0, configuration: .lossless)
        let decoded = try decoder.decodeFrame(encoded, descriptor: d, frameIndex: 0)
        #expect(decoded == original, "lossless \(uid) ba=\(ba) bs=\(bs) spp=\(spp) signed=\(signed) not bit-exact")
    }

    // MARK: - Lossy (valid + high fidelity through the registry)

    @Test("Registry Baseline (.50) lossy round-trip keeps size and high fidelity",
          arguments: [1, 3])
    func baselineLossy(spp: Int) throws {
        let reg = CodecRegistry.shared
        let d = descriptor(32, 32, bitsAllocated: 8, bitsStored: 8, spp: spp)
        let original = smoothFrame(32, 32, bitsStored: 8, spp: spp, bytesPerSample: 1)

        let encoder = try #require(reg.encoder(for: baseline))
        let decoder = try #require(reg.codec(for: baseline))
        #expect(encoder.canEncode(with: .default, descriptor: d))

        let config = CompressionConfiguration(quality: .maximum, speed: .balanced)
        let encoded = try encoder.encodeFrame(original, descriptor: d, frameIndex: 0, configuration: config)
        // JPEG encoding transforms RGB to YBR_FULL_422; the compressed descriptor
        // must describe that stream (as CompressionManager writes it).
        let compressed = PixelDataDescriptor(rows: d.rows, columns: d.columns,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false, samplesPerPixel: spp,
            photometricInterpretation: spp == 3 ? .ybrFull422 : .monochrome2)
        let decoded = try decoder.decodeFrame(encoded, descriptor: compressed, frameIndex: 0)

        #expect(decoded.count == original.count)
        let q = psnr(original, decoded, bytesPerSample: 1, maxVal: 255)
        #expect(q > 35.0, "Baseline spp=\(spp) PSNR \(q) dB too low")
    }

    @Test("Registry Extended (.51) lossy round-trip handles 12-bit with high fidelity")
    func extendedLossy12bit() throws {
        let reg = CodecRegistry.shared
        let d = descriptor(32, 32, bitsAllocated: 16, bitsStored: 12, spp: 1)
        let original = smoothFrame(32, 32, bitsStored: 12, spp: 1, bytesPerSample: 2)

        let encoder = try #require(reg.encoder(for: extended))
        let decoder = try #require(reg.codec(for: extended))
        #expect(encoder.canEncode(with: .default, descriptor: d))

        let config = CompressionConfiguration(quality: .maximum, speed: .balanced)
        let encoded = try encoder.encodeFrame(original, descriptor: d, frameIndex: 0, configuration: config)
        let decoded = try decoder.decodeFrame(encoded, descriptor: d, frameIndex: 0)

        #expect(decoded.count == original.count)
        let q = psnr(original, decoded, bytesPerSample: 2, maxVal: 4095)
        #expect(q > 35.0, "Extended 12-bit PSNR \(q) dB too low")
    }

    // MARK: - canEncode gating

    @Test("canEncode enforces each JPEG process's pixel constraints")
    func canEncodeGating() {
        let reg = CodecRegistry.shared
        let baselineEnc = reg.encoder(for: baseline)!
        let extendedEnc = reg.encoder(for: extended)!
        let losslessEnc = reg.encoder(for: lossless)!

        let gray8 = descriptor(8, 8, bitsAllocated: 8, bitsStored: 8, spp: 1)
        let gray12 = descriptor(8, 8, bitsAllocated: 16, bitsStored: 12, spp: 1)
        let gray16 = descriptor(8, 8, bitsAllocated: 16, bitsStored: 16, spp: 1)
        let signed8 = descriptor(8, 8, bitsAllocated: 8, bitsStored: 8, spp: 1, isSigned: true)
        let signed16 = descriptor(8, 8, bitsAllocated: 16, bitsStored: 16, spp: 1, isSigned: true)

        // Baseline: 8-bit unsigned only.
        #expect(baselineEnc.canEncode(with: .default, descriptor: gray8))
        #expect(!baselineEnc.canEncode(with: .default, descriptor: gray12))
        #expect(!baselineEnc.canEncode(with: .default, descriptor: signed8))   // signed → lossy rejects

        // Extended: up to 12-bit unsigned; 16-bit-stored and signed are out.
        #expect(extendedEnc.canEncode(with: .default, descriptor: gray12))
        #expect(!extendedEnc.canEncode(with: .default, descriptor: gray16))
        #expect(!extendedEnc.canEncode(with: .default, descriptor: signed16))

        // Lossless: 2–16 bit, signed welcome.
        #expect(losslessEnc.canEncode(with: .lossless, descriptor: gray8))
        #expect(losslessEnc.canEncode(with: .lossless, descriptor: gray16))
        #expect(losslessEnc.canEncode(with: .lossless, descriptor: signed16))
    }

    // MARK: - Photometric Interpretation drives the JLIEncoder color model

    /// A YBR_FULL_422-tagged descriptor. Component values are meaningless as
    /// literal Y/Cb/Cr numbers for this test — the point is only to prove the
    /// codec no longer treats them as RGB and re-transforms them.
    private func colorDescriptor(_ w: Int, _ h: Int, photometric: PhotometricInterpretation) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: h, columns: w,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 3,
            photometricInterpretation: photometric,
            planarConfiguration: 0)
    }

    @Test("Baseline encode routes YBR_FULL_422 input through the YCbCr passthrough, not the RGB transform")
    func baselineEncodeHonoursYBRPhotometricInterpretation() throws {
        let reg = CodecRegistry.shared
        let encoder = try #require(reg.encoder(for: baseline))
        let decoder = try #require(reg.codec(for: baseline))

        let rgbDescriptor = colorDescriptor(16, 16, photometric: .rgb)
        let ybrDescriptor = colorDescriptor(16, 16, photometric: .ybrFull422)
        let original = smoothFrame(16, 16, bitsStored: 8, spp: 3, bytesPerSample: 1)
        let config = CompressionConfiguration(quality: .maximum, speed: .balanced)

        let encodedAsRGB = try encoder.encodeFrame(original, descriptor: rgbDescriptor, frameIndex: 0, configuration: config)
        let encodedAsYBR = try encoder.encodeFrame(original, descriptor: ybrDescriptor, frameIndex: 0, configuration: config)

        // Before the fix, both descriptors produced identical output — the codec
        // never looked at photometricInterpretation and always assumed RGB, so
        // YBR_FULL_422 input was silently (and wrongly) re-transformed as if it
        // were RGB. They must now diverge: one path transforms, the other doesn't.
        #expect(encodedAsRGB != encodedAsYBR,
                "YBR_FULL_422 encode produced byte-identical output to RGB encode — photometricInterpretation is being ignored again")

        // The YCbCr-passthrough path must still decode to a full-size, valid frame.
        let decoded = try decoder.decodeFrame(encodedAsYBR, descriptor: ybrDescriptor, frameIndex: 0)
        #expect(decoded.count == original.count)
    }

    @Test("canEncode rejects 12-bit YBR_FULL_422 (JLIEncoder's YCbCr passthrough is 8-bit only)")
    func canEncodeRejects12BitYBR() {
        let reg = CodecRegistry.shared
        let extendedEnc = reg.encoder(for: extended)!

        let ybr16 = PixelDataDescriptor(
            rows: 8, columns: 8,
            bitsAllocated: 16, bitsStored: 12, highBit: 11,
            isSigned: false, samplesPerPixel: 3,
            photometricInterpretation: .ybrFull422,
            planarConfiguration: 0)
        #expect(!extendedEnc.canEncode(with: .default, descriptor: ybr16))
    }

    // MARK: - Default instance stays lossless (bench / adapter contract)

    @Test("Bare JLICodec() encodes lossless regardless of a lossy configuration")
    func defaultInstanceStaysLossless() throws {
        let d = descriptor(20, 16, bitsAllocated: 16, bitsStored: 12, spp: 1)
        let original = noisyFrame(20, 16, bitsStored: 12, spp: 1, bytesPerSample: 2)
        // Pass a *lossy* configuration — the default instance targets SV1, so the
        // transfer syntax (not the config) must keep the output bit-exact.
        let lossyConfig = CompressionConfiguration(quality: .low, speed: .fast)
        let encoded = try JLICodec().encodeFrame(original, descriptor: d, frameIndex: 0, configuration: lossyConfig)
        let decoded = try JLICodec().decodeFrame(encoded, descriptor: d, frameIndex: 0)
        #expect(decoded == original)
    }
}
