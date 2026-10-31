import Foundation
import Testing
@testable import DICOMCore

@Suite("M7 JPEG Extended 8-bit coding process")
struct M7JPEGExtendedProcessTests {
    private var descriptor: PixelDataDescriptor {
        PixelDataDescriptor(rows: 48, columns: 64, bitsAllocated: 8, bitsStored: 8,
            highBit: 7, isSigned: false, samplesPerPixel: 1, photometricInterpretation: .monochrome2)
    }
    private var pixels: Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64 * 48)
        for row in 0..<48 {
            for column in 0..<64 {
                let sample: Int = (column * 2 + row * 2) % 256
                bytes.append(UInt8(sample))
            }
        }
        return Data(bytes)
    }
    private func encoded(_ syntax: TransferSyntax) throws -> Data {
        try JLICodec(encodingTransferSyntaxUID: syntax.uid).encodeFrame(pixels,
            descriptor: descriptor, frameIndex: 0,
            configuration: CompressionConfiguration(quality: .maximum, speed: .balanced))
    }

    @Test("Extended8 writes SOF1 and strict decoders produce the same pixels as Baseline")
    func extended8ProcessAndPixels() throws {
        let baseline = try encoded(.jpegBaseline)
        let extended = try encoded(.jpegExtended)
        #expect(try JPEGFrameEnvelope.parse(baseline, jpegLS: false).process == 0xC0)
        let header = try JPEGFrameEnvelope.parse(extended, jpegLS: false)
        #expect(header.process == 0xC1)
        #expect(header.precision == 8)
        #expect(baseline.count == extended.count)
        #expect(zip(baseline, extended).filter { pair in pair.0 != pair.1 }.count == 1)
        let left = try JLICodec(decodingSyntax: .baseline).decodeFrame(baseline,
            descriptor: descriptor, frameIndex: 0)
        let right = try JLICodec(decodingSyntax: .extended).decodeFrame(extended,
            descriptor: descriptor, frameIndex: 0)
        #expect(left == right)
        #expect(right.count == pixels.count)
        #expect(zip(pixels, right).map { pair in abs(Int(pair.0) - Int(pair.1)) }.max()! <= 8)
        #expect(try JPEGInterchangeFormat.promotingEightBitBaselineToExtended(extended) == extended)
    }

    @Test("Marker walk skips APP payload marker lookalikes and preserves every other byte")
    func markerPayloadIsNeverEdited() throws {
        let baseline = try encoded(.jpegBaseline)
        let app = Data([0xFF, 0xE2, 0x00, 0x08, 0xFF, 0xC0, 0x11, 0x22, 0x33, 0x44])
        let withAPP = baseline.prefix(2) + app + baseline.dropFirst(2)
        let extended = try JPEGInterchangeFormat.promotingEightBitBaselineToExtended(withAPP)
        #expect(extended.prefix(2 + app.count) == withAPP.prefix(2 + app.count))
        #expect(zip(withAPP, extended).filter { pair in pair.0 != pair.1 }.count == 1)
        #expect(try JPEGFrameEnvelope.parse(extended, jpegLS: false).process == 0xC1)
    }

    @Test("Truncated segments and other JPEG processes cannot be relabeled")
    func rejectsMalformedOrOtherProcess() throws {
        let malformed: [[UInt8]] = [[], [0xFF, 0xD8], [0xFF, 0xD8, 0xFF, 0xE2, 0xFF, 0xFF],
                                    [0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x01, 0xFF, 0xD9]]
        for bytes in malformed {
            #expect(throws: (any Error).self) {
                try JPEGInterchangeFormat.promotingEightBitBaselineToExtended(Data(bytes))
            }
        }
        let lossless = try JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid)
            .encodeFrame(pixels, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        #expect(throws: (any Error).self) {
            try JPEGInterchangeFormat.promotingEightBitBaselineToExtended(lossless)
        }
    }

    @Test("The Extended color restriction remains enforced")
    func extendedColorIsUnsupported() {
        let color = PixelDataDescriptor(rows: 48, columns: 64, bitsAllocated: 8, bitsStored: 8,
            highBit: 7, isSigned: false, samplesPerPixel: 3, photometricInterpretation: .rgb)
        #expect(!JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegExtended.uid)
            .canEncode(with: .default, descriptor: color))
    }
}
