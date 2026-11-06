import Foundation
import Testing
import SwiftRLE
@testable import DICOMCore

@Suite("SwiftRLE DICOMCore Integration")
struct SwiftRLEIntegrationTests {
    @Test("RLECodec encoded frame decodes directly via SwiftRLE.Decoder and vice versa")
    func crossDecodeWithUpstreamSwiftRLE() throws {
        let rows = 33
        let columns = 47
        let descriptor = PixelDataDescriptor(
            rows: rows,
            columns: columns,
            numberOfFrames: 1,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            isSigned: true,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )

        var source = Data(capacity: rows * columns * 2)
        for index in 0..<(rows * columns) {
            let sample = Int16(truncatingIfNeeded: (index * 521) &- 16_384)
            let raw = UInt16(bitPattern: sample)
            source.append(UInt8(raw & 0xFF))
            source.append(UInt8(raw >> 8))
        }

        let codec = RLECodec()
        let encodedByDICOMCore = try codec.encodeFrame(
            source,
            descriptor: descriptor,
            frameIndex: 0,
            configuration: .lossless
        )

        // Verify 64-byte PS3.5 Annex G header: 2 segments (16-bit monochrome), offset[0] == 64, unused slots == 0
        let parsedHeader = try SwiftRLE.DICOMRLEHeader(encodedByDICOMCore, expectedSegmentCount: 2)
        #expect(parsedHeader.segmentRanges.count == 2)
        #expect(parsedHeader.segmentRanges[0].lowerBound == 64)
        #expect(encodedByDICOMCore.count % 2 == 0)

        // Decode DICOMCore-encoded payload using upstream SwiftRLE directly
        let rleDescriptor = try SwiftRLE.RLEFrameDescriptor(
            width: columns,
            height: rows,
            sampleType: .signedInteger,
            storageBits: 16,
            meaningfulBits: 16,
            byteOrder: SwiftRLE.ByteOrder.littleEndian,
            components: [.grey],
            colour: .greyscale,
            planarConfiguration: 0,
            limits: .general
        )
        let rawCells = try SwiftRLE.DICOMRLEFrame.decodeAllocatedCells(
            encodedByDICOMCore,
            descriptor: rleDescriptor
        )
        #expect(rawCells.report.fidelity == SwiftRLE.Fidelity.exactSamples)
        let upstreamDecoded = try rawCells.storage.withUnsafeBytes { Data($0) }
        #expect(upstreamDecoded == source)

        // Encode directly with upstream SwiftRLE.Encoder and decode via DICOMCore RLECodec
        let ownedSource = try SwiftRLE.OwnedImageStorage(
            byteCount: rleDescriptor.imageDescriptor.requiredByteCount,
            limits: .general
        )
        let writeLease = try ownedSource.reserveWrite()
        _ = try ownedSource.withUnsafeMutableBytes(lease: writeLease) { dst in
            source.copyBytes(to: dst)
        }
        let sealedSource = try ownedSource.finishAndSeal(lease: writeLease)
        let upstreamImage = try SwiftRLE.Image(
            descriptor: rleDescriptor.imageDescriptor,
            storage: sealedSource,
            limits: .general
        )
        let codecOptions = try SwiftRLE.CodecOptions(
            profile: .dicomRLEFrame,
            frameDescriptor: rleDescriptor
        )
        let encoderConfig = try SwiftRLE.EncoderConfiguration(
            mode: .lossless,
            codecOptions: codecOptions
        )
        let encodedByUpstream = try SwiftRLE.Encoder(configuration: encoderConfig)
            .encodeSynchronously(
                upstreamImage,
                options: SwiftRLE.EncodeOptions(copyPolicy: .requireSharedStorage)
            )
        #expect(encodedByUpstream.report.fidelity == SwiftRLE.Fidelity.exactSamples)
        #expect(encodedByUpstream.report.copyEvents.isEmpty)

        let decodedByDICOMCore = try codec.decodeFrame(
            encodedByUpstream.data,
            descriptor: descriptor,
            frameIndex: 0
        )
        #expect(decodedByDICOMCore == source)
    }

    @Test("Preserves 12-in-16 raw allocated cells, RGB planar/chunky, YBR_FULL, PALETTE COLOR, and 6-segment 16-bit RGB PackBits fallback")
    func multiPhotometricAndBitDepthMatrix() throws {
        let codec = RLECodec()

        // 1. 12-in-16 monochrome with non-zero upper bits preserved verbatim
        let mono12 = PixelDataDescriptor(
            rows: 17,
            columns: 19,
            numberOfFrames: 1,
            bitsAllocated: 16,
            bitsStored: 12,
            highBit: 11,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome1,
            planarConfiguration: 0
        )
        var mono12Bytes = Data(capacity: mono12.bytesPerFrame)
        for i in 0..<(mono12.rows * mono12.columns) {
            let word = UInt16(truncatingIfNeeded: ((i * 257) & 0x0FFF) | ((i & 1) == 0 ? 0x8000 : 0x0000))
            mono12Bytes.append(UInt8(word & 0xFF))
            mono12Bytes.append(UInt8(word >> 8))
        }
        let mono12Encoded = try codec.encodeFrame(
            mono12Bytes,
            descriptor: mono12,
            frameIndex: 0,
            configuration: .lossless
        )
        #expect(try codec.decodeFrame(mono12Encoded, descriptor: mono12, frameIndex: 0) == mono12Bytes)

        // 2. Chunky vs Planar 8-bit RGB + YBR_FULL + PALETTE COLOR
        for (photometric, planar) in [
            (PhotometricInterpretation.rgb, 0),
            (PhotometricInterpretation.rgb, 1),
            (PhotometricInterpretation.ybrFull, 0),
            (PhotometricInterpretation.paletteColor, 0)
        ] {
            let samples = photometric == .paletteColor ? 1 : 3
            let desc = PixelDataDescriptor(
                rows: 15,
                columns: 23,
                numberOfFrames: 1,
                bitsAllocated: 8,
                bitsStored: 8,
                highBit: 7,
                isSigned: false,
                samplesPerPixel: samples,
                photometricInterpretation: photometric,
                planarConfiguration: planar
            )
            let payload = Data((0..<desc.bytesPerFrame).map { UInt8(($0 * 37 + 11) & 0xFF) })
            let encoded = try codec.encodeFrame(
                payload,
                descriptor: desc,
                frameIndex: 0,
                configuration: .lossless
            )

            // Exercise non-zero Data slice + caller-owned destination buffer
            var padded = Data([0xAA, 0xBB, 0xCC])
            padded.append(encoded)
            padded.append(contentsOf: [0xDD, 0xEE])
            let slice = padded[3..<(3 + encoded.count)]

            var callerOwned = [UInt8](repeating: 0, count: desc.bytesPerFrame)
            let written = try callerOwned.withUnsafeMutableBytes { dst in
                try codec.decodeFrame(slice, descriptor: desc, frameIndex: 0, into: dst)
            }
            #expect(written == desc.bytesPerFrame)
            #expect(Data(callerOwned) == payload)
        }

        // 3. 3-component 16-bit RGB (6 segments) PackBits byte-plane fallback
        let sixSegmentRGB16 = PixelDataDescriptor(
            rows: 9,
            columns: 11,
            numberOfFrames: 1,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            isSigned: false,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0
        )
        let sixSegmentBytes = Data((0..<sixSegmentRGB16.bytesPerFrame).map { UInt8(($0 * 73) & 0xFF) })
        let sixSegmentEncoded = try codec.encodeFrame(
            sixSegmentBytes,
            descriptor: sixSegmentRGB16,
            frameIndex: 0,
            configuration: .lossless
        )
        #expect(try codec.decodeFrame(sixSegmentEncoded, descriptor: sixSegmentRGB16, frameIndex: 0) == sixSegmentBytes)
    }

    @Test("Managed budget-accounted SwiftRLE decode releases staging and retains exact decoded bytes")
    func managedBudgetDecodeLifecycle() throws {
        let descriptor = PixelDataDescriptor(
            rows: 31,
            columns: 29,
            numberOfFrames: 1,
            bitsAllocated: 16,
            bitsStored: 12,
            highBit: 11,
            isSigned: true,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )
        var raw = Data(capacity: descriptor.bytesPerFrame)
        for index in 0..<(descriptor.rows * descriptor.columns) {
            let signedSample = Int16(truncatingIfNeeded: ((index * 97) % 4096) - 2048)
            let word = UInt16(bitPattern: signedSample)
            raw.append(UInt8(word & 0xFF))
            raw.append(UInt8(word >> 8))
        }

        let codec = RLECodec()
        let encoded = try codec.encodeFrame(
            raw,
            descriptor: descriptor,
            frameIndex: 0,
            configuration: .lossless
        )

        let budget = try DICOMAllocationBudget()
        let encodedBuffer = try DICOMByteBuffer(count: encoded.count, budget: budget, resource: .encoded)
        encoded.withUnsafeBytes { encodedBuffer.unsafeMutableBytes.copyMemory(from: $0) }

        let managedFrame = try codec.decodeManagedPixelFrame(
            encodedBuffer,
            descriptor: descriptor,
            frameIndex: 0,
            budget: budget
        )
        #expect(budget.receipt.current.staging == 0)
        #expect(budget.receipt.current.decoded > 0)
        #expect(managedFrame.descriptor == descriptor)
        let decodedBytes = managedFrame.data.withUnsafeBytes { Data($0) }
        #expect(decodedBytes == raw)
    }
}
