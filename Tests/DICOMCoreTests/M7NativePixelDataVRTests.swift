import Foundation
import Testing
@testable import DICOMCore
@testable import DICOMKit

@Suite("M7 native Pixel Data VR, byte order and final padding")
struct M7NativePixelDataVRTests {
    // Independent implicit-VR bytes: Bits Allocated followed by four Pixel Data
    // bytes. No writer or dictionary inference participates in the fixture.
    private func implicitNative(allocated: UInt8) -> Data {
        Data([0x28, 0x00, 0x00, 0x01, 2, 0, 0, 0, allocated, 0,
              0xE0, 0x7F, 0x10, 0x00, 4, 0, 0, 0, 1, 0, 0x23, 1])
    }

    @Test("Implicit native OW agrees across eager and lazy reads; metadata mode omits pixels",
          arguments: [UInt8(8), UInt8(16)])
    func implicitParsingModes(allocated: UInt8) throws {
        let raw = implicitNative(allocated: allocated)
        for options in [ParsingOptions.default, .strict, .lazyPixelData, .metadataOnly] {
            var parser = DICOMParser(data: raw, options: options)
            let dataSet = try parser.parseDataSet(startOffset: 0,
                transferSyntaxUID: TransferSyntax.implicitVRLittleEndian.uid)
            #expect(dataSet[.bitsAllocated]?.uint16Value == UInt16(allocated))
            switch options.mode {
            case .metadataOnly:
                #expect(dataSet[.pixelData] == nil)
            case .full:
                let pixel = try #require(dataSet[.pixelData])
                #expect(pixel.vr == .OW)
                #expect(pixel.length == 4)
                #expect(pixel.valueData == Data([1, 0, 0x23, 1]))
            case .lazyPixelData:
                let pixel = try #require(dataSet[.pixelData])
                #expect(pixel.vr == .OW)
                #expect(pixel.length == 4)
                #expect(pixel.valueData.isEmpty)
            }
        }
    }

    @Test("Implicit16 to explicit preserves OW and numerical samples through both conversion paths")
    func implicitToExplicitWords() throws {
        let raw = implicitNative(allocated: 16)
        var parser = DICOMParser(data: raw)
        let dataSet = try parser.parseDataSet(startOffset: 0,
            transferSyntaxUID: TransferSyntax.implicitVRLittleEndian.uid)
        for target in [TransferSyntax.explicitVRLittleEndian, .explicitVRBigEndian] {
            let kitOutput = dataSet.write(using: DICOMWriter(byteOrder: target.byteOrder, explicitVR: true))
            let coreOutput = try TransferSyntaxConverter().transcode(dataSetData: raw,
                from: .implicitVRLittleEndian, to: target).data
            for output in [kitOutput, coreOutput] {
                var resultParser = DICOMParser(data: output)
                let result = try resultParser.parseDataSet(startOffset: 0, transferSyntaxUID: target.uid)
                let pixel = try #require(result[.pixelData])
                #expect(pixel.vr == .OW)
                #expect(pixel.uint16Values == [1, 0x123])
                #expect(pixel.valueData == DICOMWriter(byteOrder: target.byteOrder).serializeUInt16s([1, 0x123]))
            }
        }
    }

    @Test("Explicit Pixel Data VR is retained, including a wrong OB16 for later validation")
    func explicitVRIsNotRewritten() throws {
        for vr in [VR.OB, .OW] {
            let writer = DICOMWriter()
            let pixel = DataElement(tag: .pixelData, vr: vr, length: 4,
                valueData: Data([1, 0, 0x23, 1]))
            let raw = writer.serializeElement(.uint16(tag: .bitsAllocated, value: 16))
                + writer.serializeElement(pixel)
            for options in [ParsingOptions.default, .lazyPixelData] {
                var parser = DICOMParser(data: raw, options: options)
                let dataSet = try parser.parseDataSet(startOffset: 0,
                    transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid)
                #expect(dataSet[.pixelData]?.vr == vr)
            }
        }
    }

    private func source(allocated: Int, stored: Int, rows: Int, columns: Int,
                        frames: [Data]) throws -> Data {
        let descriptor = PixelDataDescriptor(rows: rows, columns: columns,
            numberOfFrames: frames.count, bitsAllocated: allocated, bitsStored: stored,
            highBit: stored - 1, isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2)
        let encoder = try #require(CodecRegistry.shared.encoder(for: TransferSyntax.rleLossless.uid))
        var fragments: [Data] = []
        for (index, frame) in frames.enumerated() {
            fragments.append(try encoder.encodeFrame(frame, descriptor: descriptor,
                frameIndex: index, configuration: .lossless))
        }
        let fields: [(DICOMCore.Tag, UInt16)] = [(.samplesPerPixel, 1), (.rows, UInt16(rows)),
            (.columns, UInt16(columns)), (.bitsAllocated, UInt16(allocated)),
            (.bitsStored, UInt16(stored)), (.highBit, UInt16(stored - 1)), (.pixelRepresentation, 0)]
        var elements = fields.map { DataElement.uint16(tag: $0.0, value: $0.1) }
        elements.append(.string(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"))
        if frames.count > 1 {
            elements.append(.string(tag: .numberOfFrames, vr: .IS, value: String(frames.count)))
        }
        elements.append(DataElement(tag: .pixelData, vr: .OB, length: UInt32.max,
            valueData: Data(), encapsulatedFragments: fragments, encapsulatedOffsetTable: []))
        let writer = DICOMWriter()
        return elements.sorted { $0.tag < $1.tag }.reduce(into: Data()) { data, element in
            data.append(writer.serializeElement(element))
        }
    }

    private func decode(_ source: Data, to target: TransferSyntax) throws -> DataElement {
        let result = try TransferSyntaxConverter().transcode(dataSetData: source,
            from: .rleLossless, to: target)
        var parser = DICOMParser(data: result.data)
        let dataSet = try parser.parseDataSet(startOffset: 0, transferSyntaxUID: target.uid)
        return try #require(dataSet[.pixelData])
    }

    @Test("Allocated16 always writes OW, including Stored8, with correct target word order",
          arguments: [8, 12, 16])
    func nativeWords(stored: Int) throws {
        let words: [UInt16] = stored == 8 ? [0, 1, 127, 128, 254, 255] : [0, 1, 255, 256, 1023, 4095]
        let little = DICOMWriter().serializeUInt16s(words)
        let encoded = try source(allocated: 16, stored: stored, rows: 2, columns: 3, frames: [little])
        for target in [TransferSyntax.explicitVRLittleEndian, .explicitVRBigEndian, .implicitVRLittleEndian] {
            let pixel = try decode(encoded, to: target)
            #expect(pixel.vr == .OW)
            #expect(pixel.length == 12)
            #expect(!pixel.isEncapsulated)
            #expect(pixel.uint16Values == words)
            let expected = DICOMWriter(byteOrder: target.byteOrder).serializeUInt16s(words)
            #expect(pixel.valueData == expected, "Raw word bytes must match the target byte order")
        }
    }

    @Test("One odd8-bit frame has a single final NUL and native explicit OB or implicit OW")
    func oddByteFramePadding() throws {
        let frame = Data([1, 2, 3, 4, 5, 6, 7, 8, 9])
        let encoded = try source(allocated: 8, stored: 8, rows: 3, columns: 3, frames: [frame])
        for target in [TransferSyntax.explicitVRLittleEndian, .explicitVRBigEndian, .implicitVRLittleEndian] {
            let pixel = try decode(encoded, to: target)
            #expect(pixel.vr == (target.isExplicitVR ? .OB : .OW))
            #expect(pixel.length == 10)
            #expect(pixel.valueData == frame + Data([0]))
        }
    }

    @Test("Odd-sized frames concatenate without padding between frames")
    func paddingIsAfterAllFrames() throws {
        let first = Data([1, 2, 3, 4, 5, 6, 7, 8, 9])
        let second = Data([31, 32, 33, 34, 35, 36, 37, 38, 39])
        let encoded = try source(allocated: 8, stored: 8, rows: 3, columns: 3, frames: [first, second])
        for target in [TransferSyntax.explicitVRLittleEndian, .implicitVRLittleEndian] {
            let pixel = try decode(encoded, to: target)
            #expect(pixel.length == 18)
            #expect(pixel.valueData == first + second)
        }
    }
}
