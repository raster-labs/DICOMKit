import Foundation
import Testing
@testable import DICOMCore
import SwiftJLI

@Suite("SwiftJLI Integration Conformance")
struct SwiftJLIIntegrationTests {

    @Test("Baseline (.50) writes JFIF-free 4:2:2 YCbCr for RGB and preserves preconverted YBR_FULL_422")
    func baseline8BitAndYBR422Conformance() throws {
        let encoder = JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid)
        let decoder = JLICodec(decodingSyntax: .baseline)

        let rgbDesc = PixelDataDescriptor(
            rows: 16,
            columns: 16,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0
        )
        let ybrDesc = PixelDataDescriptor(
            rows: 16,
            columns: 16,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 3,
            photometricInterpretation: .ybrFull422,
            planarConfiguration: 0
        )

        var gradient = Data(capacity: 16 * 16 * 3)
        for y in 0..<16 {
            for x in 0..<16 {
                gradient.append(UInt8((x * 16) & 0xFF))
                gradient.append(UInt8((y * 16) & 0xFF))
                gradient.append(UInt8(((x + y) * 8) & 0xFF))
            }
        }

        let cfg = CompressionConfiguration(quality: .maximum, speed: .balanced)
        let encodedRGB = try encoder.encodeFrame(gradient, descriptor: rgbDesc, frameIndex: 0, configuration: cfg)
        #expect(!JPEGInterchangeFormat.containsJFIFSegment(encodedRGB))
        #expect(JPEGInterchangeFormat.isHorizontally422(encodedRGB))
        #expect(try JPEGFrameEnvelope.parse(encodedRGB, jpegLS: false).process == 0xC0)

        let decodedRGB = try decoder.decodePixelFrame(encodedRGB, descriptor: ybrDesc, frameIndex: 0)
        #expect(decodedRGB.descriptor.photometricInterpretation == .rgb)
        #expect(decodedRGB.data.count == gradient.count)

        let encodedYBR = try encoder.encodeFrame(gradient, descriptor: ybrDesc, frameIndex: 0, configuration: cfg)
        #expect(!JPEGInterchangeFormat.containsJFIFSegment(encodedYBR))
        #expect(JPEGInterchangeFormat.isHorizontally422(encodedYBR))
        #expect(encodedYBR != encodedRGB)
    }

    @Test("Extended (.51) promotes 8-bit to SOF1 and encodes 12-bit monochrome Process 4")
    func extended8And12BitConformance() throws {
        let encoder = JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegExtended.uid)
        let decoder = JLICodec(decodingSyntax: .extended)
        let cfg = CompressionConfiguration(quality: .maximum, speed: .balanced)

        // 8-bit Extended (SOF1 P=8)
        let desc8 = PixelDataDescriptor(
            rows: 24,
            columns: 24,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let raw8 = Data((0..<(24 * 24)).map { UInt8(($0 * 3) & 0xFF) })
        let enc8 = try encoder.encodeFrame(raw8, descriptor: desc8, frameIndex: 0, configuration: cfg)
        let hdr8 = try JPEGFrameEnvelope.parse(enc8, jpegLS: false)
        #expect(hdr8.process == 0xC1)
        #expect(hdr8.precision == 8)
        #expect(!JPEGInterchangeFormat.containsJFIFSegment(enc8))
        let dec8 = try decoder.decodeFrame(enc8, descriptor: desc8, frameIndex: 0)
        #expect(dec8.count == raw8.count)

        // 12-bit Extended (SOF1 P=12)
        let desc12 = PixelDataDescriptor(
            rows: 24,
            columns: 24,
            bitsAllocated: 16,
            bitsStored: 12,
            highBit: 11,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        var raw12 = Data(capacity: 24 * 24 * 2)
        for y in 0..<24 {
            for x in 0..<24 {
                let sample = UInt16(((x + y) * 4095) / 46)
                raw12.append(UInt8(sample & 0xFF))
                raw12.append(UInt8(sample >> 8))
            }
        }
        let enc12 = try encoder.encodeFrame(raw12, descriptor: desc12, frameIndex: 0, configuration: cfg)
        let hdr12 = try JPEGFrameEnvelope.parse(enc12, jpegLS: false)
        #expect(hdr12.process == 0xC1)
        #expect(hdr12.precision == 12)
        let dec12 = try decoder.decodeFrame(enc12, descriptor: desc12, frameIndex: 0)
        #expect(dec12.count == raw12.count)
    }

    @Test("Lossless (.57 and .70) preserves 2...16-bit unsigned/signed monochrome, chunky/planar RGB, and numeric SOF3 RGB IDs")
    func lossless2Through16BitSignedUnsignedAndRGB() throws {
        for uid in [TransferSyntax.jpegLossless.uid, TransferSyntax.jpegLosslessSV1.uid] {
            let codec = JLICodec(encodingTransferSyntaxUID: uid, decodingTransferSyntaxUID: uid)

            // Sweep precisions 2, 4, 8, 10, 12, 14, 16 unsigned monochrome
            for bits in [2, 4, 8, 10, 12, 14, 16] {
                let ba = bits <= 8 ? 8 : 16
                let bps = ba / 8
                let mask = (1 << bits) - 1
                let desc = PixelDataDescriptor(
                    rows: 6,
                    columns: 8,
                    bitsAllocated: ba,
                    bitsStored: bits,
                    highBit: bits - 1,
                    isSigned: false,
                    samplesPerPixel: 1,
                    photometricInterpretation: .monochrome2
                )
                var raw = Data(capacity: 48 * bps)
                for i in 0..<48 {
                    let v = (i * 73 + 5) & mask
                    if bps == 1 {
                        raw.append(UInt8(v))
                    } else {
                        raw.append(UInt8(v & 0xFF))
                        raw.append(UInt8((v >> 8) & 0xFF))
                    }
                }
                let encoded = try codec.encodeFrame(raw, descriptor: desc, frameIndex: 0, configuration: .lossless)
                let decoded = try codec.decodeFrame(encoded, descriptor: desc, frameIndex: 0)
                #expect(decoded == raw, "Unsigned lossless mismatch for bits=\(bits) uid=\(uid)")
            }

            // Cooked sign-extended 12-bit signed CT samples (-2048, -1, 0, 2047)
            let ct12 = PixelDataDescriptor(
                rows: 2,
                columns: 2,
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
            let encCT = try codec.encodeFrame(ctRaw, descriptor: ct12, frameIndex: 0, configuration: .lossless)
            let decCT = try codec.decodeFrame(encCT, descriptor: ct12, frameIndex: 0)
            let recoveredSigned: [Int] = (0..<4).map { idx in
                let cell = UInt16(decCT[idx * 2]) | (UInt16(decCT[idx * 2 + 1]) << 8)
                return ct12.storedValue(fromCell: Int(cell))
            }
            #expect(recoveredSigned == [-2048, -1, 0, 2047])

            // Planar & chunky 8-bit RGB + external numeric [1, 2, 3] SOF3 component-ID normalization
            for planar in [0, 1] {
                let rgbDesc = PixelDataDescriptor(
                    rows: 8,
                    columns: 10,
                    bitsAllocated: 8,
                    bitsStored: 8,
                    highBit: 7,
                    isSigned: false,
                    samplesPerPixel: 3,
                    photometricInterpretation: .rgb,
                    planarConfiguration: planar
                )
                let rgbRaw = Data((0..<rgbDesc.bytesPerFrame).map { UInt8(($0 * 29 + 11) & 0xFF) })
                let encRGB = try codec.encodeFrame(rgbRaw, descriptor: rgbDesc, frameIndex: 0, configuration: .lossless)
                let decRGB = try codec.decodeFrame(encRGB, descriptor: rgbDesc, frameIndex: 0)
                #expect(decRGB == rgbRaw)

                // Rewrite 'R','G','B' component IDs in SOF3 and SOS to numeric 1, 2, 3 to simulate IJG/DCMTK output
                var numericStream = [UInt8](encRGB)
                var offset = 2
                while offset + 4 <= numericStream.count, numericStream[offset] == 0xFF {
                    let marker = numericStream[offset + 1]
                    let length = (Int(numericStream[offset + 2]) << 8) | Int(numericStream[offset + 3])
                    let payload = offset + 4
                    if marker == 0xC3, length == 17 {
                        numericStream[payload + 6] = 1
                        numericStream[payload + 9] = 2
                        numericStream[payload + 12] = 3
                    } else if marker == 0xDA, length == 12 {
                        numericStream[payload + 1] = 1
                        numericStream[payload + 3] = 2
                        numericStream[payload + 5] = 3
                        break
                    }
                    offset += 2 + length
                }
                let decNumeric = try codec.decodeFrame(Data(numericStream), descriptor: rgbDesc, frameIndex: 0)
                #expect(decNumeric == rgbRaw)
            }
        }
    }

    @Test("Managed budget-accounted decode releases staging and retains exact decoded bytes")
    func managedBudgetDecodeAccounting() throws {
        let budget = try DICOMAllocationBudget()
        let baselineTotal = budget.receipt.currentTotal

        let desc = PixelDataDescriptor(
            rows: 16,
            columns: 16,
            bitsAllocated: 16,
            bitsStored: 12,
            highBit: 11,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        var raw = Data(capacity: desc.bytesPerFrame)
        for i in 0..<(16 * 16) {
            let v = UInt16((i * 37) & 0x0FFF)
            raw.append(UInt8(v & 0xFF))
            raw.append(UInt8(v >> 8))
        }
        let encoded = try JLICodec().encodeFrame(raw, descriptor: desc, frameIndex: 0, configuration: .lossless)
        do {
            let input = try DICOMByteBuffer(count: encoded.count, budget: budget, resource: .encoded)
            encoded.withUnsafeBytes { input.unsafeMutableBytes.copyMemory(from: $0) }
            let managed = try JLICodec(decodingSyntax: .losslessSV1)
                .decodeManagedPixelFrame(input, descriptor: desc, frameIndex: 0, budget: budget)
            #expect(managed.data.withUnsafeBytes { Data($0) } == raw)
            #expect(budget.receipt.current.staging == 0)
            #expect(budget.receipt.current.decoded == managed.data.capacity)
        }
        #expect(budget.receipt.currentTotal == baselineTotal)
    }

    @Test("Direct SwiftJLI Encoder and Decoder enforce requireSharedStorage and Fidelity.exactSamples")
    func directSwiftJLISharedStorageAndFidelity() async throws {
        let descriptor = try SwiftJLI.ImageDescriptor.greyscale16(width: 8, height: 8, meaningfulBits: 12)
        let srcDest = try SwiftJLI.ImageDestination.allocate(descriptor: descriptor)
        let image = try srcDest.writeUInt16 { x, y in
            UInt16(((x * 131 + y * 257) & 0x0FFF))
        }

        let encoder = try SwiftJLI.Encoder(configuration: .default)
        let encoded = try await encoder.encode(
            image,
            options: SwiftJLI.EncodeOptions(copyPolicy: .requireSharedStorage, metadataPolicy: .discardAncillary)
        )
        #expect(encoded.report.copyEvents.isEmpty)
        #expect(encoded.report.fidelity == .exactSamples)

        let outDest = try SwiftJLI.ImageDestination.allocate(descriptor: descriptor)
        let decoder = try SwiftJLI.Decoder()
        let decoded = try await decoder.decode(
            encoded.data,
            into: outDest,
            options: SwiftJLI.DecodeOptions(copyPolicy: .requireSharedStorage, metadataPolicy: .discardAncillary)
        )
        #expect(decoded.report.copyEvents.isEmpty)
        #expect(decoded.report.fidelity == .exactSamples)

        let inBytes = try image.storage.withUnsafeBytes { Data($0) }
        let outBytes = try decoded.image.storage.withUnsafeBytes { Data($0) }
        #expect(inBytes == outBytes)
    }

    @Test("Ancillary APPn (XMP, vendor ICC, Adobe) and COM segments decode cleanly")
    func ancillaryMetadataSegmentsStrippedOnDecode() throws {
        let desc = PixelDataDescriptor(
            rows: 8,
            columns: 8,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0
        )
        let raw = Data((0..<(8 * 8 * 3)).map { UInt8(($0 * 29) & 0xFF) })
        let baseStream = try JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid)
            .encodeFrame(raw, descriptor: desc, frameIndex: 0, configuration: .default)

        // Inject odd-length APP1 (XMP), APP13, and COM (0xFE) segments right after SOI,
        // plus DICOM even-length trailing zero pad if odd.
        func makeSegment(_ marker: UInt8, _ payload: [UInt8]) -> [UInt8] {
            let len = payload.count + 2
            return [0xFF, marker, UInt8(len >> 8), UInt8(len & 0xFF)] + payload
        }
        var augmented: [UInt8] = [0xFF, 0xD8]
        augmented += makeSegment(0xE1, Array("http://ns.adobe.com/xap/1.0/\0<x/>".utf8))
        augmented += makeSegment(0xED, [0x50, 0x68, 0x6F, 0x74, 0x6F])
        augmented += makeSegment(0xFE, Array("Apple ImageIO comment".utf8))
        augmented += baseStream.dropFirst(2)
        if augmented.count % 2 == 1 {
            augmented.append(0x00)
        }

        let codec = JLICodec(decodingSyntax: .baseline)
        let decoded = try codec.decodeFrame(Data(augmented), descriptor: desc, frameIndex: 0)
        #expect(decoded.count == raw.count)

        let budget = try DICOMAllocationBudget()
        let input = try DICOMByteBuffer(count: augmented.count, budget: budget, resource: .encoded)
        Data(augmented).withUnsafeBytes { input.unsafeMutableBytes.copyMemory(from: $0) }
        let managed = try codec.decodeManagedPixelFrame(input, descriptor: desc, frameIndex: 0, budget: budget)
        #expect(managed.data.count == raw.count)
    }
}
