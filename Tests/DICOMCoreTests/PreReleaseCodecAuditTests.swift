import Foundation
import Testing
@testable import DICOMCore
import DICOMKit

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

        for jp3dUID in [
            TransferSyntax.jp3dLossless.uid,
            TransferSyntax.jp3dLossy.uid,
        ] {
            #expect(registry.codec(for: jp3dUID) is JP3DCodec)
            #expect(registry.encoder(for: jp3dUID) is JP3DCodec)
        }

        // JPIP referenced transfer syntaxes must NOT be registered as frame codecs in CodecRegistry.shared.
        for deferredUID in [
            TransferSyntax.jpipReferenced.uid,
            TransferSyntax.jpipReferencedDeflate.uid,
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

    @Test("Legacy HTJ2K CAP Ccap15=0x0020 reversible codestream and PALETTE COLOR / YBR_FULL decode profiles succeed in SwiftJ2KDICOMCodec")
    func legacyReversibleHTJ2KCAPAndDecodeProfiles() throws {
        let descriptor = PixelDataDescriptor(
            rows: 8, columns: 8, numberOfFrames: 1,
            bitsAllocated: 16, bitsStored: 12, highBit: 11,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .paletteColor
        )
        let monoDescriptor = PixelDataDescriptor(
            rows: 8, columns: 8, numberOfFrames: 1,
            bitsAllocated: 16, bitsStored: 12, highBit: 11,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        var pixels = Data(capacity: descriptor.bytesPerFrame)
        for i in 0..<64 {
            var word = UInt16((i * 59) & 0x0FFF).littleEndian
            withUnsafeBytes(of: &word) { pixels.append(contentsOf: $0) }
        }

        let encoder = SwiftJ2KDICOMCodec(encodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid)
        let validStream = try encoder.encodeFrame(pixels, descriptor: monoDescriptor, frameIndex: 0, configuration: .lossless)

        // Inject legacy J2KSwift CAP Ccap15 = 0x0020 (bit 5 HTIRV = 1) into reversible 5/3 HTJ2K codestream
        var legacyCAPStream = [UInt8](validStream)
        if let capRange = validStream.range(of: Data([0xFF, 0x50, 0x00, 0x08, 0x00, 0x02, 0x00, 0x00])) {
            legacyCAPStream[capRange.lowerBound + 8] = 0x00
            legacyCAPStream[capRange.lowerBound + 9] = 0x20
        }
        let legacyData = Data(legacyCAPStream)

        let decoder = SwiftJ2KDICOMCodec(decodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid)
        #expect(SwiftJ2KDICOMCodec.supportsDecodeProfile(
            transferSyntaxUID: TransferSyntax.htj2kLossless.uid,
            descriptor: descriptor,
            decodeBackend: nil
        ))
        let decoded = try decoder.decodeFrame(legacyData, descriptor: descriptor, frameIndex: 0)
        #expect(decoded == pixels)

        let budget = try DICOMAllocationBudget()
        let inBuf = try DICOMByteBuffer(count: legacyData.count, budget: budget, resource: .encoded)
        legacyData.withUnsafeBytes { inBuf.unsafeMutableBytes.copyMemory(from: $0) }
        let managed = try decoder.decodeManagedPixelFrame(inBuf, descriptor: descriptor, frameIndex: 0, budget: budget)
        #expect(managed.data.withUnsafeBytes { Data($0) } == pixels)
        #expect(budget.receipt.current.staging == 0)
    }

    @Test("CodecRegistry.shared JPEG-LS decoders recover legacy 16-bit unclamped-MAXVAL streams without LSE (e.g. dcm4che-1.4.34 / JAI clib_jiio)")
    func codecRegistryRecoversLegacyUnclampedJPEGLSWithoutLSE() async throws {
        let width = 32
        let height = 32
        var pixels = Data(capacity: width * height * 2)
        for i in 0..<(width * height) {
            let signedCT = Int16(truncatingIfNeeded: -1024 + ((i * 313 + 97) % 4500))
            let word = UInt16(bitPattern: signedCT)
            pixels.append(UInt8(word & 0xFF))
            pixels.append(UInt8((word >> 8) & 0xFF))
        }
        let legacyStream = try await JPEGLSCodecStrictDecodingTests.makeLegacyUnclampedCodestream(
            pixels: pixels,
            width: width,
            height: height,
            bitsPerSample: 16
        )
        var paddedStream = legacyStream
        if paddedStream.count % 2 == 1 {
            paddedStream.append(0x00)
        }
        let descriptor = PixelDataDescriptor(
            rows: height,
            columns: width,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            isSigned: true,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let resolved = try #require(
            CodecRegistry.shared.resolveDecoder(
                for: TransferSyntax.jpegLSLossless.uid,
                descriptor: descriptor
            )
        )
        #expect((resolved.codec as? JPEGLSCodec)?.missingPresetPolicy == .allowLegacyUnclampedRecovery)
        #expect((CodecRegistry.shared.codec(for: TransferSyntax.jpegLSNearLossless.uid) as? JPEGLSCodec)?.missingPresetPolicy == .requireStandardDefaults)
        let decoded = try resolved.codec.decodePixelFrame(paddedStream, descriptor: descriptor, frameIndex: 0)
        #expect(decoded.data == pixels)
        #expect(decoded.diagnostics == [.legacyUnclampedPresetRecovered(encodedPrecision: 16)])

        #expect(JPEGLSCodec.isKnownLegacyUnclampedImplementationVersion("DICOMKIT_0.5.0"))
        #expect(JPEGLSCodec.isKnownLegacyUnclampedImplementationVersion("dcm4che-1.4.34"))
        #expect(JPEGLSCodec.isKnownLegacyUnclampedImplementationVersion("clib_jiio_1.1"))
        #expect(!JPEGLSCodec.isKnownLegacyUnclampedImplementationVersion("DICOMKIT_3.2.1"))
        #expect(!JPEGLSCodec.isKnownLegacyUnclampedImplementationVersion(nil))

        // End-to-end DICOMFile metadata-driven upgrade to .preferLegacyUnclampedParameters
        // on the 1x3 [20, 15, 10] stream where standard thresholds silently decode [20, 15, 11].
        let silentPixels = Data([20, 0, 15, 0, 10, 0])
        var silentFragment = try await JPEGLSCodecStrictDecodingTests.makeLegacyUnclampedCodestream(
            pixels: silentPixels,
            width: 3,
            height: 1,
            bitsPerSample: 16
        )
        if silentFragment.count % 2 == 1 {
            silentFragment.append(0x00)
        }
        for legacyVersion in ["DICOMKIT_0.5.0", "dcm4che-1.4.34"] {
            var meta = DataSet()
            meta.setString(TransferSyntax.jpegLSLossless.uid, for: .transferSyntaxUID, vr: .UI)
            meta.setString(legacyVersion, for: .implementationVersionName, vr: .SH)
            var ds = DataSet()
            ds.setUInt16(1, for: .rows)
            ds.setUInt16(3, for: .columns)
            ds.setUInt16(16, for: .bitsAllocated)
            ds.setUInt16(16, for: .bitsStored)
            ds.setUInt16(15, for: .highBit)
            ds.setUInt16(0, for: .pixelRepresentation)
            ds.setUInt16(1, for: .samplesPerPixel)
            ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
            ds[.pixelData] = DataElement(
                tag: .pixelData,
                vr: .OB,
                length: 0xFFFF_FFFF,
                valueData: Data(),
                encapsulatedFragments: [silentFragment],
                encapsulatedOffsetTable: []
            )
            let dicomFile = DICOMFile(fileMetaInformation: meta, dataSet: ds)
            let extracted = try dicomFile.tryPixelData()
            #expect(extracted.data == silentPixels)
        }
    }
}
