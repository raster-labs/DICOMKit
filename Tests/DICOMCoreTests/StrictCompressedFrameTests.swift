import Foundation
import Testing
@testable import DICOMCore

@Suite("Strict compressed frame admission")
struct StrictCompressedFrameTests {
    func descriptor(_ rows: Int = 8, _ columns: Int = 16, bits: Int = 8,
                    frames: Int = 1, spp: Int = 1) -> PixelDataDescriptor {
        PixelDataDescriptor(rows: rows, columns: columns, numberOfFrames: frames,
            bitsAllocated: bits > 8 ? 16 : 8, bitsStored: bits, highBit: bits - 1,
            isSigned: false, samplesPerPixel: spp,
            photometricInterpretation: spp == 1 ? .monochrome2 : .rgb)
    }

    @Test func rejectsMismatchedJPEGHeaderAndSyntax() throws {
        let d = descriptor()
        let encoded = try JLICodec().encodeFrame(Data(repeating: 40, count: d.bytesPerFrame),
            descriptor: d, frameIndex: 0, configuration: .lossless)
        for bad in [descriptor(16, 8), descriptor(8, 15), descriptor(bits: 12), descriptor(spp: 3)] {
            #expect(throws: DICOMError.self) { try JLICodec().decodeFrame(encoded, descriptor: bad, frameIndex: 0) }
        }
        let baseline = try #require(CodecRegistry.shared.codec(for: TransferSyntax.jpegBaseline.uid))
        #expect(throws: DICOMError.self) { try baseline.decodeFrame(encoded, descriptor: d, frameIndex: 0) }
        let sv1 = try #require(CodecRegistry.shared.codec(for: TransferSyntax.jpegLosslessSV1.uid))
        var predictor2 = encoded
        let sos = try #require(encoded.range(of: Data([0xff, 0xda])))
        let count = Int(encoded[sos.lowerBound + 4])
        predictor2[sos.lowerBound + 5 + count * 2] = 2
        #expect(throws: DICOMError.self) { try sv1.decodeFrame(predictor2, descriptor: d, frameIndex: 0) }
        for bad in [Data(encoded.dropLast(2)), encoded + encoded, encoded + Data([3])] {
            #expect(throws: DICOMError.self) { try sv1.decodeFrame(bad, descriptor: d, frameIndex: 0) }
        }
    }

    @Test func losslessPrecisionAndContainerBytes() throws {
        for bits in [8, 12, 16] {
            let d = descriptor(bits: bits)
            let samples = (0..<d.pixelsPerFrame).map { ($0 * 257) & ((1 << bits) - 1) }
            let bytes = Data(samples.flatMap { bits == 8 ? [UInt8($0)] : [UInt8($0 & 255), UInt8($0 >> 8)] })
            let encoded = try JLICodec().encodeFrame(bytes, descriptor: d, frameIndex: 0, configuration: .lossless)
            #expect(try JLICodec().decodeFrame(encoded, descriptor: d, frameIndex: 0) == bytes)
        }
        let d = descriptor()
        let encoded = try JLICodec().encodeFrame(Data(repeating: 240, count: d.bytesPerFrame),
            descriptor: d, frameIndex: 0, configuration: .lossless)
        let wide = PixelDataDescriptor(rows: d.rows, columns: d.columns, bitsAllocated: 16,
            bitsStored: 8, highBit: 7, isSigned: false, photometricInterpretation: .monochrome2)
        #expect(try JLICodec().decodeFrame(encoded, descriptor: wide, frameIndex: 0)
                == Data((0..<d.pixelsPerFrame).flatMap { _ in [UInt8(240), 0] }))
    }

    @Test func boundedBeforeDecodeAndEffectiveLSHeader() throws {
        let d = descriptor()
        let encoded = try JPEGLSCodec().encodeFrame(Data(repeating: 50, count: d.bytesPerFrame),
            descriptor: d, frameIndex: 0, configuration: .lossless)
        #expect(throws: DICOMError.self) {
            try JPEGLSCodec(decodingLimits: .init(maximumDecodedBytes: 10))
                .decodeFrame(encoded, descriptor: d, frameIndex: 0)
        }
        #expect(throws: DICOMError.self) {
            try JPEGLSCodec().decodeFrame(encoded, descriptor: descriptor(16, 8), frameIndex: 0)
        }
        let lse = Data([0xff, 0xf8, 0, 12, 4, 4, 0, 1, 0x86, 0xa0, 0, 1, 0x86, 0xa0])
        var huge = Data(encoded.prefix(2)) + lse + encoded.dropFirst(2)
        let sof = try #require(huge.range(of: Data([0xff, 0xf7]))).lowerBound
        for i in (sof + 5)...(sof + 8) { huge[i] = 0 }
        #expect(throws: DICOMError.self) { try JPEGLSCodec().decodeFrame(huge, descriptor: d, frameIndex: 0) }
        let oversized = descriptor(Int.max, Int.max)
        #expect(throws: DICOMError.self) { try JLICodec().decodeFrame(encoded, descriptor: oversized, frameIndex: 0) }
    }

    @Test func frameTablesAreExactAndSelectionIsStable() throws {
        let fragments = [Data([1, 2]), Data([3, 4, 5, 6]), Data([7, 8])]
        let d = descriptor(frames: 2)
        let valid = EncapsulatedPixelData(offsetTable: [0, 22], fragments: fragments, descriptor: d)
        for i in [1, 0, 1, 0] {
            #expect(valid.frameData(at: i) == (i == 0 ? fragments[0] + fragments[1] : fragments[2]))
        }
        for table: [UInt32] in [[0], [0, 0], [0, 11], [0, 100], [0, 22, 32], [10, 0]] {
            let value = EncapsulatedPixelData(offsetTable: table, fragments: fragments, descriptor: d)
            #expect(value.frameData(at: 0) == nil)
        }
        let ambiguous = EncapsulatedPixelData(offsetTable: [], fragments: fragments, descriptor: d)
        #expect(ambiguous.frameData(at: 0) == nil)
        #expect(ambiguous.makeFrameIndex(extendedOffsets: [UInt64.max, 0]) == nil)
        #expect(ambiguous.makeFrameIndex(extendedOffsets: [0]) == nil)
        let single = EncapsulatedPixelData(offsetTable: [], fragments: fragments, descriptor: descriptor())
        #expect(single.frameData(at: 0) == fragments.reduce(Data(), +))
    }
}
