import Foundation
import Testing
import SwiftJXL
@testable import DICOMCore

@Suite("SwiftJXL Integration Conformance")
struct SwiftJXLIntegrationTests {

    @Test("Lossless (.110) preserves 8/12/16-bit unsigned, signed 16-bit CT, chunky/planar RGB, and XYB->RGB relabelling")
    func losslessModularAndPhotometricConformance() throws {
        let encoder = JXLCodec(encodingTransferSyntaxUID: TransferSyntax.jpegXLLossless.uid)
        let decoder = JXLCodec(decodingTransferSyntaxUID: TransferSyntax.jpegXLLossless.uid)

        // 1. Signed 16-bit CT (12-bit and 16-bit stored)
        for bitsStored in [12, 16] {
            let ctDesc = PixelDataDescriptor(
                rows: 24,
                columns: 32,
                bitsAllocated: 16,
                bitsStored: bitsStored,
                highBit: bitsStored - 1,
                isSigned: true,
                samplesPerPixel: 1,
                photometricInterpretation: .monochrome2
            )
            let half = 1 << (bitsStored - 1)
            let mask = (1 << bitsStored) - 1
            var raw = Data(capacity: ctDesc.bytesPerFrame)
            for i in 0..<(24 * 32) {
                let signed = Int16(truncatingIfNeeded: ((i * 73) & mask) - half)
                let word = UInt16(bitPattern: signed)
                raw.append(UInt8(word & 0xFF))
                raw.append(UInt8(word >> 8))
            }
            let encoded = try encoder.encodeFrame(raw, descriptor: ctDesc, frameIndex: 0, configuration: .lossless)
            let decoded = try decoder.decodeFrame(encoded, descriptor: ctDesc, frameIndex: 0)
            #expect(decoded == raw)
        }

        // 2. Chunky & planar 16-bit RGB + XYB -> RGB relabelling (D12)
        for planar in [0, 1] {
            let xybDesc = PixelDataDescriptor(
                rows: 16,
                columns: 16,
                bitsAllocated: 16,
                bitsStored: 16,
                highBit: 15,
                isSigned: false,
                samplesPerPixel: 3,
                photometricInterpretation: .xyb,
                planarConfiguration: planar
            )
            var rgbRaw = Data(capacity: xybDesc.bytesPerFrame)
            for i in 0..<(16 * 16 * 3) {
                let word = UInt16((i * 257) & 0xFFFF)
                rgbRaw.append(UInt8(word & 0xFF))
                rgbRaw.append(UInt8(word >> 8))
            }
            let encoded = try encoder.encodeFrame(rgbRaw, descriptor: xybDesc, frameIndex: 0, configuration: .lossless)
            let pixelFrame = try decoder.decodePixelFrame(encoded, descriptor: xybDesc, frameIndex: 0)
            #expect(pixelFrame.data == rgbRaw)
            #expect(pixelFrame.descriptor.photometricInterpretation == .rgb)
            #expect(pixelFrame.descriptor.planarConfiguration == planar)
        }
    }

    @Test("JPEG Recompression (.111) round-trips JPEG fragments byte-for-byte and decodes to pixels")
    func jpegRecompressionBitstreamAndPixelDecode() throws {
        let rgbDesc = PixelDataDescriptor(
            rows: 16,
            columns: 16,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0
        )
        let rgbRaw = Data((0..<rgbDesc.bytesPerFrame).map { UInt8(($0 * 19) & 0xFF) })
        let jpegBytes = try JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid)
            .encodeFrame(rgbRaw, descriptor: rgbDesc, frameIndex: 0, configuration: .default)

        // Pad odd JPEG to even length as DICOM encapsulation does; recompress must trim EOI pad.
        var paddedJPEG = jpegBytes
        if paddedJPEG.count % 2 == 1 {
            paddedJPEG.append(0x00)
        }
        let jxlContainer = try JXLCodec.recompressJPEGFragment(paddedJPEG)
        var paddedJXL = jxlContainer
        if paddedJXL.count % 2 == 1 {
            paddedJXL.append(0x00)
        }
        let reconstructed = try JXLCodec.reconstructJPEGFragment(paddedJXL)
        #expect(reconstructed == jpegBytes)

        // Pixel decode via .recompression and .any matches JLICodec decode of the wrapped JPEG.
        let expectedPixels = try JLICodec(decodingSyntax: .baseline)
            .decodeFrame(jpegBytes, descriptor: rgbDesc, frameIndex: 0)
        let recompPixels = try JXLCodec(decodingSyntax: .recompression)
            .decodeFrame(paddedJXL, descriptor: rgbDesc, frameIndex: 0)
        #expect(recompPixels == expectedPixels)

        // .lossless (.110) must reject a `jbrd` container.
        #expect(throws: DICOMError.self) {
            _ = try JXLCodec(decodingSyntax: .lossless).decodeFrame(jxlContainer, descriptor: rgbDesc, frameIndex: 0)
        }
    }

    @Test("Lossy (.112) emits VarDCT for bounded frames, refuses under .110, and falls back to Modular above 4096")
    func lossyVarDCTAndOversizedModularFallback() throws {
        let desc = PixelDataDescriptor(
            rows: 32,
            columns: 32,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb
        )
        let raw = Data((0..<desc.bytesPerFrame).map { UInt8(($0 * 31) & 0xFF) })
        let lossyCfg = CompressionConfiguration(quality: .maximum, speed: .balanced, preferLossless: false)
        let lossyEncoded = try JXLCodec(encodingTransferSyntaxUID: TransferSyntax.jpegXL.uid)
            .encodeFrame(raw, descriptor: desc, frameIndex: 0, configuration: lossyCfg)

        // Even at `.maximum` quality, lossy intent produces a VarDCT stream rejected by `.110` Lossless.
        #expect(throws: DICOMError.self) {
            _ = try JXLCodec(decodingSyntax: .lossless).decodeFrame(lossyEncoded, descriptor: desc, frameIndex: 0)
        }
        let lossyDecoded = try JXLCodec(decodingSyntax: .general)
            .decodeFrame(lossyEncoded, descriptor: desc, frameIndex: 0)
        #expect(lossyDecoded.count == raw.count)

        // Frame wider than VarDCT's 4096-pixel axis bound transparently falls back to Modular lossless.
        let wideDesc = PixelDataDescriptor(
            rows: 8,
            columns: 4104,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let wideRaw = Data((0..<wideDesc.bytesPerFrame).map { UInt8(($0 * 7) & 0xFF) })
        let wideEncoded = try JXLCodec(encodingTransferSyntaxUID: TransferSyntax.jpegXL.uid)
            .encodeFrame(wideRaw, descriptor: wideDesc, frameIndex: 0, configuration: lossyCfg)
        let wideDecoded = try JXLCodec(decodingSyntax: .general)
            .decodeFrame(wideEncoded, descriptor: wideDesc, frameIndex: 0)
        #expect(wideDecoded == wideRaw)
    }

    @Test("Managed decode enforces zero-staging SizeHeader pre-admission and releases staging on completion")
    func managedDecodeZeroStagingAndBudgetAccounting() throws {
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal

        let desc = PixelDataDescriptor(
            rows: 16,
            columns: 16,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            isSigned: true,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        var raw = Data(capacity: desc.bytesPerFrame)
        for i in 0..<(16 * 16) {
            let signed = Int16(truncatingIfNeeded: i * 101 - 12000)
            let word = UInt16(bitPattern: signed)
            raw.append(UInt8(word & 0xFF))
            raw.append(UInt8(word >> 8))
        }
        let encoded = try JXLCodec().encodeFrame(raw, descriptor: desc, frameIndex: 0, configuration: .lossless)

        // Staging limit capped strictly to the two metadata control pages (ledger + input buffer)
        // guarantees any staging admission would be refused, and peak.staging == 0 confirms none occurred.
        let zeroStaging = try DICOMAllocationBudget(
            limits: .init(staging: DICOMAllocationBudget.controlCapacity * 2)
        )
        let wrongDesc = PixelDataDescriptor(
            rows: 8,
            columns: 8,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            isSigned: true,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        do {
            let badIn = try DICOMByteBuffer(count: encoded.count, budget: zeroStaging, resource: .encoded)
            encoded.withUnsafeBytes { badIn.unsafeMutableBytes.copyMemory(from: $0) }
            let outcome = JXLCodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrameOutcome(badIn, descriptor: wrongDesc, frameIndex: 0, budget: zeroStaging)
            if case .failure(let failure) = outcome {
                #expect(failure.code == .codecResultMismatch)
            } else {
                Issue.record("Expected dimension mismatch failure before staging admission")
            }
            #expect(zeroStaging.receipt.peak.staging == 0)
        }

        // Valid managed decode releases staging and retains exact decoded bytes.
        do {
            let input = try DICOMByteBuffer(count: encoded.count, budget: budget, resource: .encoded)
            encoded.withUnsafeBytes { input.unsafeMutableBytes.copyMemory(from: $0) }
            let managed = try JXLCodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrame(input, descriptor: desc, frameIndex: 0, budget: budget)
            #expect(managed.data.withUnsafeBytes { Data($0) } == raw)
            #expect(budget.receipt.current.staging == 0)
            #expect(managed.data.count == raw.count)
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("Direct SwiftJXL Encoder, Decoder, and Transcoder report scalarCPU backend and expected Fidelity")
    func directSwiftJXLProvenanceAndFidelity() async throws {
        let descriptor = try SwiftJXL.ImageDescriptor.greyscale16(width: 8, height: 8, meaningfulBits: 12)
        let srcDest = try SwiftJXL.ImageDestination.allocate(descriptor: descriptor)
        let image = try srcDest.writeUInt16 { x, y in
            UInt16(((x * 131 + y * 257) & 0x0FFF))
        }

        let encoder = try SwiftJXL.Encoder(configuration: .default)
        let encoded = try await encoder.encode(
            image,
            options: SwiftJXL.EncodeOptions(copyPolicy: .requireSharedStorage, metadataPolicy: .discardAncillary)
        )
        #expect(encoded.report.backend == .scalarCPU)
        #expect(encoded.report.copyEvents.isEmpty)
        #expect(encoded.report.fidelity == .exactSamples)

        let outDest = try SwiftJXL.ImageDestination.allocate(descriptor: descriptor)
        let decoder = try SwiftJXL.Decoder()
        let decoded = try await decoder.decode(
            encoded.data,
            into: outDest,
            options: SwiftJXL.DecodeOptions(copyPolicy: .requireSharedStorage, metadataPolicy: .discardAncillary)
        )
        #expect(decoded.report.backend == .scalarCPU)
        #expect(decoded.report.copyEvents.isEmpty)
        #expect(decoded.report.fidelity == .exactSamples)

        let inBytes = try image.storage.withUnsafeBytes { Data($0) }
        let outBytes = try decoded.image.storage.withUnsafeBytes { Data($0) }
        #expect(inBytes == outBytes)
    }
}
