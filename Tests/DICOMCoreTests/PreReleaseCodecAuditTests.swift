import Foundation
import Testing
@testable import DICOMCore

@Suite("Pre-Release Codec Placement, Buffer & Cancellation Audit")
struct PreReleaseCodecAuditTests {

    @Test("All 17 active standard encapsulated Transfer Syntaxes map to pure-Swift raster-labs codecs with zero implicit ImageIO fallbacks")
    func registryPlacementMatrix() {
        let registry = CodecRegistry.shared
        #expect(registry.j2kProvider.providerID == CodecProviderID.swiftJ2K)
        #expect(registry.j2kFallbackPolicy == .strict)

        let jliUIDs = [
            TransferSyntax.jpegBaseline.uid,     // .50
            TransferSyntax.jpegExtended.uid,     // .51
            TransferSyntax.jpegLossless.uid,     // .57
            TransferSyntax.jpegLosslessSV1.uid,  // .70
        ]
        for uid in jliUIDs {
            let dec = registry.resolveDecoder(for: uid)
            #expect(dec?.codec is JLICodec, "Expected JLICodec decoder for \(uid)")
            #expect(!(dec?.codec is NativeJPEGCodec))
            #expect(registry.encoder(for: uid) is JLICodec, "Expected JLICodec encoder for \(uid)")
        }

        let jlsUIDs = [
            TransferSyntax.jpegLSLossless.uid,     // .80
            TransferSyntax.jpegLSNearLossless.uid, // .81
        ]
        for uid in jlsUIDs {
            #expect(registry.codec(for: uid) is JPEGLSCodec, "Expected JPEGLSCodec decoder for \(uid)")
            #expect(registry.encoder(for: uid) is JPEGLSCodec, "Expected JPEGLSCodec encoder for \(uid)")
        }

        let j2kUIDs: [String] = [
            TransferSyntax.jpeg2000Lossless.uid,      // .90
            TransferSyntax.jpeg2000.uid,              // .91
            TransferSyntax.jpeg2000Part2Lossless.uid, // .92
            TransferSyntax.jpeg2000Part2.uid,         // .93
            TransferSyntax.htj2kLossless.uid,         // .201
            TransferSyntax.htj2kRPCLLossless.uid,     // .202
            TransferSyntax.htj2kLossy.uid,            // .203
        ]
        for uid in j2kUIDs {
            let dec = registry.resolveDecoder(for: uid)
            #expect(dec?.providerID == CodecProviderID.swiftJ2K)
            #expect(dec?.codec is SwiftJ2KDICOMCodec, "Expected SwiftJ2KDICOMCodec decoder for \(uid)")
            #expect(!(dec?.codec is NativeJPEG2000Codec))
            #expect(registry.encoder(for: uid) is SwiftJ2KDICOMCodec, "Expected SwiftJ2KDICOMCodec encoder for \(uid)")
        }

        let jxlDecodeUIDs = [
            TransferSyntax.jpegXLLossless.uid,      // .110
            TransferSyntax.jpegXLRecompression.uid, // .111
            TransferSyntax.jpegXL.uid,              // .112
        ]
        for uid in jxlDecodeUIDs {
            #expect(registry.codec(for: uid) is JXLCodec, "Expected JXLCodec decoder for \(uid)")
        }
        #expect(registry.encoder(for: TransferSyntax.jpegXLLossless.uid) is JXLCodec)
        #expect(registry.encoder(for: TransferSyntax.jpegXL.uid) is JXLCodec)
        #expect(registry.encoder(for: TransferSyntax.jpegXLRecompression.uid) == nil)

        #expect(registry.codec(for: TransferSyntax.rleLossless.uid) is RLECodec)
        #expect(registry.encoder(for: TransferSyntax.rleLossless.uid) is RLECodec)

        // Deferred SwiftJ2K 12.2.0 surfaces must NOT be registered in CodecRegistry.shared.
        for deferredUID in [
            TransferSyntax.jpipReferenced.uid,
            TransferSyntax.jpipReferencedDeflate.uid,
            "1.2.826.0.1.3680043.10.511.1",
            "1.2.826.0.1.3680043.10.511.2",
        ] {
            #expect(registry.codec(for: deferredUID) == nil)
            #expect(registry.encoder(for: deferredUID) == nil)
        }
    }

    @Test("J2KSwiftCodec and HTJ2KCodec caller-owned buffer decode matches Data decode byte-for-byte")
    func j2kWrapperCallerOwnedBufferDecode() throws {
        let descriptor = PixelDataDescriptor(
            rows: 8, columns: 8, numberOfFrames: 1,
            bitsAllocated: 16, bitsStored: 12, highBit: 11,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        var pixels = Data(capacity: descriptor.bytesPerFrame)
        for i in 0..<(8 * 8) {
            var sample = UInt16((i * 37) & 0x0FFF).littleEndian
            withUnsafeBytes(of: &sample) { pixels.append(contentsOf: $0) }
        }
        let config = CompressionConfiguration(quality: .maximum, preferLossless: true)

        let j2k = J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid)
        let j2kEncoded = try j2k.encodeFrame(pixels, descriptor: descriptor, frameIndex: 0, configuration: config)
        var j2kOut = Data(repeating: 0xAA, count: descriptor.bytesPerFrame)
        let j2kWritten = try j2kOut.withUnsafeMutableBytes { dst in
            try j2k.decodeFrame(j2kEncoded, descriptor: descriptor, frameIndex: 0, into: dst)
        }
        #expect(j2kWritten == descriptor.bytesPerFrame)
        #expect(j2kOut == pixels)

        let htj2k = HTJ2KCodec(targetTransferSyntaxUID: TransferSyntax.htj2kLossless.uid)
        let htj2kEncoded = try htj2k.encodeFrame(pixels, descriptor: descriptor, frameIndex: 0, configuration: config)
        var htj2kOut = Data(repeating: 0x55, count: descriptor.bytesPerFrame)
        let htj2kWritten = try htj2kOut.withUnsafeMutableBytes { dst in
            try htj2k.decodeFrame(htj2kEncoded, descriptor: descriptor, frameIndex: 0, into: dst)
        }
        #expect(htj2kWritten == descriptor.bytesPerFrame)
        #expect(htj2kOut == pixels)
    }

    @Test("Pre-cancelled Task propagates cleanly as .cancelled across all 5 codec families without leaking budget bytes")
    func preCancelledTaskManagedDecodeAcrossAllFiveFamilies() async throws {
        let descriptor = PixelDataDescriptor(
            rows: 8, columns: 8, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let pixels = Data((0..<64).map { UInt8($0 * 3) })
        let lossless = CompressionConfiguration(quality: .maximum, preferLossless: true)

        let rlePayload = try RLECodec().encodeFrame(pixels, descriptor: descriptor, frameIndex: 0, configuration: lossless)
        let jlsPayload = try JPEGLSCodec().encodeFrame(pixels, descriptor: descriptor, frameIndex: 0, configuration: lossless)
        let jliPayload = try JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid)
            .encodeFrame(pixels, descriptor: descriptor, frameIndex: 0, configuration: lossless)
        let jxlPayload = try JXLCodec(encodingTransferSyntaxUID: TransferSyntax.jpegXLLossless.uid)
            .encodeFrame(pixels, descriptor: descriptor, frameIndex: 0, configuration: lossless)
        let j2kPayload = try J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid)
            .encodeFrame(pixels, descriptor: descriptor, frameIndex: 0, configuration: lossless)

        typealias ManagedCall = @Sendable (borrowing DICOMByteBuffer, PixelDataDescriptor, borrowing DICOMAllocationBudget) -> DICOMManagedOutcome<ManagedDecodedPixelFrame>

        let cases: [(name: String, payload: Data, run: ManagedCall)] = [
            ("SwiftRLE", rlePayload, { buf, desc, b in
                RLECodec().decodeManagedPixelFrameOutcome(buf, descriptor: desc, frameIndex: 0, budget: b)
            }),
            ("SwiftJLS", jlsPayload, { buf, desc, b in
                JPEGLSCodec(decodingTransferSyntaxUID: TransferSyntax.jpegLSLossless.uid)
                    .decodeManagedPixelFrameOutcome(buf, descriptor: desc, frameIndex: 0, budget: b)
            }),
            ("SwiftJLI", jliPayload, { buf, desc, b in
                JLICodec(decodingTransferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid)
                    .decodeManagedPixelFrameOutcome(buf, descriptor: desc, frameIndex: 0, budget: b)
            }),
            ("SwiftJXL", jxlPayload, { buf, desc, b in
                JXLCodec(decodingTransferSyntaxUID: TransferSyntax.jpegXLLossless.uid)
                    .decodeManagedPixelFrameOutcome(buf, descriptor: desc, frameIndex: 0, budget: b)
            }),
            ("SwiftJ2K-wrapper", j2kPayload, { buf, desc, b in
                J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid)
                    .decodeManagedPixelFrameOutcome(buf, descriptor: desc, frameIndex: 0, budget: b)
            }),
            ("SwiftJ2K-direct", j2kPayload, { buf, desc, b in
                SwiftJ2KDICOMCodec(decodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid)
                    .decodeManagedPixelFrameOutcome(buf, descriptor: desc, frameIndex: 0, budget: b)
            }),
        ]

        for item in cases {
            let task = Task<DICOMManagedFailure.Code?, any Error> {
                withUnsafeCurrentTask { $0?.cancel() }
                let budget = try DICOMAllocationBudget.make().get()
                let baseline = budget.receipt
                let code: DICOMManagedFailure.Code? = try {
                    let encodedBuf = try DICOMByteBuffer(count: item.payload.count, budget: budget, resource: .encoded)
                    item.payload.withUnsafeBytes { encodedBuf.unsafeMutableBytes.copyMemory(from: $0) }
                    let outcome = item.run(encodedBuf, descriptor, budget)
                    switch outcome {
                    case .success:
                        return nil
                    case .failure(let failure):
                        return failure.code
                    }
                }()
                #expect(budget.receipt.currentTotal == baseline.currentTotal, "\(item.name) leaked budget bytes")
                return code
            }
            let result = await task.result
            let code = try result.get()
            #expect(code == .cancelled, "Expected .cancelled for \(item.name), got \(String(describing: code))")
        }
    }
}
