import Foundation
import Testing
import SwiftJLS
@testable import DICOMCore

@Suite("SwiftJLS Integration Tests")
struct SwiftJLSIntegrationTests {

    // MARK: - Helpers

    private static func findSOSInterleaveAndNear(_ codestream: Data) -> (ilv: UInt8, near: UInt8)? {
        let bytes = [UInt8](codestream)
        var i = 0
        while i + 1 < bytes.count {
            guard bytes[i] == 0xFF else {
                i += 1
                continue
            }
            while i < bytes.count && bytes[i] == 0xFF { i += 1 }
            guard i < bytes.count else { break }
            let marker = bytes[i]
            i += 1
            if marker == 0xD8 || (0xD0...0xD7).contains(marker) { continue }
            if marker == 0xD9 { break }
            guard i + 2 <= bytes.count else { break }
            let length = (Int(bytes[i]) << 8) | Int(bytes[i + 1])
            guard length >= 2, i + length <= bytes.count else { break }
            if marker == 0xDA {
                let ns = Int(bytes[i + 2])
                let nearOffset = i + 3 + 2 * ns
                let ilvOffset = nearOffset + 1
                guard ilvOffset < i + length else { return nil }
                return (ilv: bytes[ilvOffset], near: bytes[nearOffset])
            }
            i += length
        }
        return nil
    }

    private static func containsSPIFFApp8(_ codestream: Data) -> Bool {
        let spiffSignature = Data([0xFF, 0xE8, 0x00, 0x20, 0x53, 0x50, 0x49, 0x46, 0x46, 0x00])
        return codestream.range(of: spiffSignature) != nil
    }

    // MARK: - Monochrome 2...16-bit Signed & Unsigned Lossless (.80)

    @Test("Lossless (.80) monochrome unsigned round-trip across 2, 6, 8, 12, and 16 bits")
    func monochromeUnsignedBitDepthRoundTrip() throws {
        let codec = JPEGLSCodec(decodingSyntax: .lossless)
        let cases: [(bitsAllocated: Int, bitsStored: Int)] = [
            (8, 2),
            (8, 6),
            (8, 8),
            (16, 12),
            (16, 16)
        ]

        for (bitsAllocated, bitsStored) in cases {
            let rows = 8
            let cols = 8
            let descriptor = PixelDataDescriptor(
                rows: rows,
                columns: cols,
                numberOfFrames: 1,
                bitsAllocated: bitsAllocated,
                bitsStored: bitsStored,
                highBit: bitsStored - 1,
                isSigned: false,
                samplesPerPixel: 1,
                photometricInterpretation: .monochrome2
            )
            let maxVal = (1 << bitsStored) - 1
            var raw = Data(capacity: descriptor.bytesPerFrame)
            for idx in 0..<(rows * cols) {
                let sample = (idx * 37) % (maxVal + 1)
                if bitsAllocated == 8 {
                    raw.append(UInt8(sample))
                } else {
                    var le = UInt16(sample).littleEndian
                    withUnsafeBytes(of: &le) { raw.append(contentsOf: $0) }
                }
            }

            let encoded = try codec.encodeFrame(raw, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
            let sos = try #require(Self.findSOSInterleaveAndNear(encoded))
            #expect(sos.near == 0)
            let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
            #expect(decoded == raw)
        }
    }

    @Test("Lossless (.80) signed 12-bit CT (cooked sign-extended) and signed 16-bit monochrome round-trip")
    func monochromeSignedRoundTrip() throws {
        let codec = JPEGLSCodec(decodingSyntax: .lossless)

        // 12-bit signed CT with sign-extended negative cells (e.g. -2048 = 0xF800, -1 = 0xFFFF)
        let ct12 = PixelDataDescriptor(
            rows: 2,
            columns: 2,
            numberOfFrames: 1,
            bitsAllocated: 16,
            bitsStored: 12,
            highBit: 11,
            isSigned: true,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let cookedWords: [UInt16] = [0xF800, 0xFFFF, 0x0000, 0x07FF]
        var ctRaw = Data()
        for word in cookedWords {
            var le = word.littleEndian
            withUnsafeBytes(of: &le) { ctRaw.append(contentsOf: $0) }
        }

        let encodedCT = try codec.encodeFrame(ctRaw, descriptor: ct12, frameIndex: 0, configuration: .lossless)
        let decodedCT = try codec.decodeFrame(encodedCT, descriptor: ct12, frameIndex: 0)
        #expect(decodedCT.count == 8)
        let decodedSigned12: [Int] = (0..<4).map { idx in
            let cell = UInt16(decodedCT[idx * 2]) | (UInt16(decodedCT[idx * 2 + 1]) << 8)
            return ct12.storedValue(fromCell: Int(cell))
        }
        #expect(decodedSigned12 == [-2048, -1, 0, 2047])

        // 16-bit signed full-range
        let s16 = PixelDataDescriptor(
            rows: 2,
            columns: 2,
            numberOfFrames: 1,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            isSigned: true,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let s16Values: [Int16] = [.min, -1, 0, .max]
        var s16Raw = Data()
        for value in s16Values {
            var le = UInt16(bitPattern: value).littleEndian
            withUnsafeBytes(of: &le) { s16Raw.append(contentsOf: $0) }
        }
        let encodedS16 = try codec.encodeFrame(s16Raw, descriptor: s16, frameIndex: 0, configuration: .lossless)
        let decodedS16 = try codec.decodeFrame(encodedS16, descriptor: s16, frameIndex: 0)
        #expect(decodedS16 == s16Raw)
    }

    // MARK: - Near-Lossless (.81) & NEAR Parameter Mapping

    @Test("Near-Lossless (.81) maps quality to NEAR > 0, bounds error <= NEAR, and is rejected under .lossless")
    func nearLosslessBoundsAndProfileEnforcement() throws {
        let descriptor = PixelDataDescriptor(
            rows: 16,
            columns: 16,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        var raw = Data(capacity: 256)
        for i in 0..<256 { raw.append(UInt8(i)) }

        let config = CompressionConfiguration(quality: .custom(0.75), preferLossless: false)
        let encoder = JPEGLSCodec()
        let encoded = try encoder.encodeFrame(raw, descriptor: descriptor, frameIndex: 0, configuration: config)
        let sos = try #require(Self.findSOSInterleaveAndNear(encoded))
        #expect(sos.near > 0)

        // Rejected when strict lossless (.80) profile is requested
        let strictLossless = JPEGLSCodec(decodingSyntax: .lossless)
        #expect(throws: DICOMError.self) {
            _ = try strictLossless.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
        }

        // Accepted under .nearLossless (.81) within maximum absolute error <= NEAR
        let nearDecoder = JPEGLSCodec(decodingSyntax: .nearLossless)
        let decoded = try nearDecoder.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
        #expect(decoded.count == raw.count)
        let maxBound = Int(sos.near)
        for i in 0..<raw.count {
            let diff = abs(Int(raw[i]) - Int(decoded[i]))
            #expect(diff <= maxBound)
        }
    }

    // MARK: - Interleave Modes (ILV 0/1/2) & Planar / Chunky RGB (8-bit and 16-bit)

    @Test("RGB 8-bit and 16-bit round-trip across ILV (.none, .line, .sample) and PlanarConfiguration (0, 1) without SPIFF")
    func rgbInterleaveAndPlanarRoundTrip() throws {
        let codec = JPEGLSCodec(decodingSyntax: .lossless)
        let interleaveModes: [(JPEGLSCodec.InterleaveMode, UInt8)] = [
            (.none, 0),
            (.line, 1),
            (.sample, 2)
        ]

        for bits in [8, 16] {
            for planar in [0, 1] {
                let descriptor = PixelDataDescriptor(
                    rows: 6,
                    columns: 7,
                    numberOfFrames: 1,
                    bitsAllocated: bits,
                    bitsStored: bits,
                    highBit: bits - 1,
                    isSigned: false,
                    samplesPerPixel: 3,
                    photometricInterpretation: .rgb,
                    planarConfiguration: planar
                )
                var raw = Data(capacity: descriptor.bytesPerFrame)
                let sampleCount = 6 * 7 * 3
                for idx in 0..<sampleCount {
                    if bits == 8 {
                        raw.append(UInt8((idx * 29 + 7) & 0xFF))
                    } else {
                        var word = UInt16((idx * 1013 + 19) & 0xFFFF).littleEndian
                        withUnsafeBytes(of: &word) { raw.append(contentsOf: $0) }
                    }
                }

                for (mode, expectedILV) in interleaveModes {
                    let encoded = try codec.encodeFrame(
                        raw,
                        descriptor: descriptor,
                        frameIndex: 0,
                        configuration: .lossless,
                        interleaveMode: mode
                    )
                    #expect(!Self.containsSPIFFApp8(encoded))
                    _ = try JPEGFrameEnvelope.parse(encoded, jpegLS: true)
                    let sos = try #require(Self.findSOSInterleaveAndNear(encoded))
                    #expect(sos.ilv == expectedILV)
                    #expect(sos.near == 0)

                    let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
                    #expect(decoded == raw)
                }
            }
        }
    }

    // MARK: - Managed Budget Decoding (8-bit mono, 16-bit mono, 3-component RGB)

    @Test("Managed decode charges DICOMAllocationBudget across 8-bit mono, 16-bit mono, and 8-bit RGB")
    func managedBudgetDecodeAcrossProfiles() throws {
        let codec = JPEGLSCodec(decodingSyntax: .lossless)
        let budget = try DICOMAllocationBudget()

        let profiles: [PixelDataDescriptor] = [
            PixelDataDescriptor(
                rows: 8, columns: 8, numberOfFrames: 1,
                bitsAllocated: 8, bitsStored: 8, highBit: 7,
                isSigned: false, samplesPerPixel: 1, photometricInterpretation: .monochrome2
            ),
            PixelDataDescriptor(
                rows: 8, columns: 8, numberOfFrames: 1,
                bitsAllocated: 16, bitsStored: 12, highBit: 11,
                isSigned: false, samplesPerPixel: 1, photometricInterpretation: .monochrome2
            ),
            PixelDataDescriptor(
                rows: 8, columns: 8, numberOfFrames: 1,
                bitsAllocated: 8, bitsStored: 8, highBit: 7,
                isSigned: false, samplesPerPixel: 3, photometricInterpretation: .rgb, planarConfiguration: 0
            )
        ]

        for descriptor in profiles {
            var raw = Data(capacity: descriptor.bytesPerFrame)
            if descriptor.bitsAllocated == 8 {
                for i in 0..<descriptor.bytesPerFrame { raw.append(UInt8((i * 17) & 0xFF)) }
            } else {
                for i in 0..<(descriptor.rows * descriptor.columns) {
                    var word = UInt16((i * 73) & 0x0FFF).littleEndian
                    withUnsafeBytes(of: &word) { raw.append(contentsOf: $0) }
                }
            }

            let encoded = try codec.encodeFrame(raw, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
            let admitted = try DICOMByteBuffer(count: encoded.count, budget: budget, resource: .encoded)
            encoded.withUnsafeBytes { admitted.unsafeMutableBytes.copyMemory(from: $0) }
            let managed = try codec.decodeManagedPixelFrame(admitted, descriptor: descriptor, frameIndex: 0, budget: budget)
            #expect(budget.receipt.current.staging == 0)
            let decodedData = managed.data.withUnsafeBytes { Data($0) }
            #expect(decodedData == raw)
        }
    }

    // MARK: - SwiftJLS Shared Storage & Exact Fidelity Direct Contract

    @Test("Direct SwiftJLS decode into caller-allocated ImageDestination reports zero copy events and exactSamples")
    func swiftJLSRequireSharedStorageContract() async throws {
        let descriptor = PixelDataDescriptor(
            rows: 8,
            columns: 8,
            numberOfFrames: 1,
            bitsAllocated: 16,
            bitsStored: 12,
            highBit: 11,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        var raw = Data(capacity: 128)
        for i in 0..<64 {
            var word = UInt16((i * 63) & 0x0FFF).littleEndian
            withUnsafeBytes(of: &word) { raw.append(contentsOf: $0) }
        }
        let encoded = try JPEGLSCodec().encodeFrame(raw, descriptor: descriptor, frameIndex: 0, configuration: .lossless)

        let jlsDesc = try SwiftJLS.ImageDescriptor.greyscale16(width: 8, height: 8, meaningfulBits: 12)
        let dest = try SwiftJLS.ImageDestination.allocate(descriptor: jlsDesc)
        let decoder = try SwiftJLS.Decoder()
        let result = try await decoder.decode(
            encoded,
            into: dest,
            options: .init(copyPolicy: .requireSharedStorage, metadataPolicy: .discardAncillary)
        )
        #expect(result.report.copyEvents.isEmpty)
        #expect(result.report.fidelity == .exactSamples)
        let bytes = try result.image.storage.withUnsafeBytes { Data($0) }
        #expect(bytes == raw)
    }
}
