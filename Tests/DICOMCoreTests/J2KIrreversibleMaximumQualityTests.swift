// J2KIrreversibleMaximumQualityTests.swift
// DICOMCoreTests — D234
//
// A lossy-intent encode on a `.both` UID (.91 / .203) with `quality: .maximum` is planned as an
// irreversible 9-7 encode (PS3.5 2026a 8.2.4). It must not be held to the bit-exact check that
// only a reversible 5-3 encode guarantees.

import Foundation
import Testing
@testable import DICOMCore

@Suite("J2K irreversible encode at maximum quality (D234)")
struct J2KIrreversibleMaximumQualityTests {

    private func rgbDescriptor(rows: Int, columns: Int) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: rows, columns: columns,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            samplesPerPixel: 3, photometricInterpretation: .rgb, planarConfiguration: 0
        )
    }

    /// Smooth gradient with per-channel offsets; the 9-7 path does not reproduce it bit-exactly.
    private func gradient(_ d: PixelDataDescriptor) -> Data {
        var out = Data(capacity: d.rows * d.columns * 3)
        for r in 0..<d.rows {
            for c in 0..<d.columns {
                out.append(UInt8((r * 13 + c * 7) & 0xFF))
                out.append(UInt8((r * 5 + c * 17 + 40) & 0xFF))
                out.append(UInt8((r * 23 + c * 3 + 90) & 0xFF))
            }
        }
        return out
    }

    private let lossyMaximum = CompressionConfiguration(
        quality: .maximum, speed: .balanced, progressive: false,
        preferLossless: false, maxBitsPerSample: nil, forcedBackend: nil
    )

    @Test("plan for lossy intent at maximum quality is irreversible on .91 and .203",
          arguments: [TransferSyntax.jpeg2000.uid, "1.2.840.10008.1.2.4.203"])
    func planIsIrreversible(uid: String) {
        let plan = J2KRoutePlanner.planEncode(transferSyntaxUID: uid, configuration: lossyMaximum)
        #expect(plan.lossless == false)
        #expect(plan.useReversibleFilter == false)
    }

    @Test("irreversible encode at maximum quality succeeds and decodes to the frame size",
          arguments: [TransferSyntax.jpeg2000.uid, "1.2.840.10008.1.2.4.203"])
    func irreversibleEncodeSucceeds(uid: String) throws {
        let d = rgbDescriptor(rows: 16, columns: 16)
        let codec = J2KSwiftCodec(encodingTransferSyntaxUID: uid)
        let encoded = try codec.encodeFrame(gradient(d), descriptor: d, frameIndex: 0, configuration: lossyMaximum)
        let decoded = try codec.decodeFrame(encoded, descriptor: d, frameIndex: 0)
        #expect(decoded.count == d.bytesPerFrame)
    }

    @Test("a reversible encode is still held to bit-exactness")
    func reversibleStillExact() throws {
        let d = rgbDescriptor(rows: 16, columns: 16)
        let lossless = CompressionConfiguration(
            quality: .maximum, speed: .balanced, progressive: false,
            preferLossless: true, maxBitsPerSample: nil, forcedBackend: nil
        )
        let uid = TransferSyntax.jpeg2000Lossless.uid
        #expect(J2KRoutePlanner.planEncode(transferSyntaxUID: uid, configuration: lossless).lossless)
        let codec = J2KSwiftCodec(encodingTransferSyntaxUID: uid)
        let original = gradient(d)
        let encoded = try codec.encodeFrame(original, descriptor: d, frameIndex: 0, configuration: lossless)
        #expect(try codec.decodeFrame(encoded, descriptor: d, frameIndex: 0) == original)
    }
}
