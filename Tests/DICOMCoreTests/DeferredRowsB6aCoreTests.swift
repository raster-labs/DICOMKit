// DeferredRowsB6aCoreTests.swift — DICOMCore half of deferred-row batch b6a-codec (2026-10-01):
// D190 / D-CORE-2 (JPEG colour = YBR_FULL_422, PS3.5 2026a Table 8.2.1-1), D-CORE-3 (YBR_FULL →
// JPEG 2000 / HTJ2K, PS3.5 2026a 8.2.4 / Table 8.2.4-1), D206 (byte-swapped values, PS3.5 7.3).

import Testing
import Foundation
@testable import DICOMCore

@Suite("Deferred rows b6a (DICOMCore, 2026a)")
struct DeferredRowsB6aCoreTests {

    private func us(_ tag: DICOMCore.Tag, _ v: UInt16) -> DataElement {
        var x = v.littleEndian
        return DataElement(tag: tag, vr: .US, length: 2, valueData: Data(bytes: &x, count: 2))
    }

    private func colourDataSet(_ pi: String, pixels: Data, rows: Int = 16, columns: Int = 16) -> Data {
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        let piValue = pi.count % 2 == 0 ? pi : pi + " "
        let elements: [DataElement] = [
            us(.samplesPerPixel, 3),
            DataElement(tag: .photometricInterpretation, vr: .CS, length: UInt32(piValue.count), valueData: Data(piValue.utf8)),
            us(.planarConfiguration, 0),
            us(.rows, UInt16(rows)), us(.columns, UInt16(columns)),
            us(.bitsAllocated, 8), us(.bitsStored, 8), us(.highBit, 7), us(.pixelRepresentation, 0),
            DataElement(tag: .pixelData, vr: .OB, length: UInt32(pixels.count), valueData: pixels),
        ]
        return elements.reduce(into: Data()) { $0.append(writer.serializeElement($1)) }
    }

    private func gradient(_ rows: Int = 16, _ columns: Int = 16) -> Data {
        var d = Data()
        for y in 0..<rows { for x in 0..<columns {
            d.append(UInt8((x * 16) % 256)); d.append(UInt8((y * 16) % 256)); d.append(UInt8(((x + y) * 8) % 256))
        } }
        return d
    }

    /// Top-level element value of an Explicit VR LE data set (no sequences before it).
    private func value(_ tag: DICOMCore.Tag, in data: Data) -> Data? {
        let b = [UInt8](data)
        var i = 0
        while i + 8 <= b.count {
            let g = UInt16(b[i]) | UInt16(b[i + 1]) << 8, e = UInt16(b[i + 2]) | UInt16(b[i + 3]) << 8
            let vr = String(bytes: b[(i + 4)..<(i + 6)], encoding: .ascii) ?? ""
            let long = ["OB", "OW", "OF", "SQ", "UT", "UN", "OD", "OL", "OV", "UC", "UR", "SV", "UV"].contains(vr)
            let length = long ? Int(b[i + 8]) | Int(b[i + 9]) << 8 | Int(b[i + 10]) << 16 | Int(b[i + 11]) << 24
                               : Int(b[i + 6]) | Int(b[i + 7]) << 8
            let header = long ? 12 : 8
            if g == tag.group && e == tag.element { return Data(b[(i + header)..<min(b.count, i + header + max(0, length))]) }
            if length == 0xFFFF_FFFF { return nil }
            i += header + length
        }
        return nil
    }

    private func photometric(_ data: Data) -> String? {
        value(.photometricInterpretation, in: data).flatMap { String(data: $0, encoding: .ascii) }?
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - YBR_FULL equations (PS3.3 2026a C.7.6.3.1.2)

    @Test("YBR_FULL inverse matrix inverts the PS3.3 C.7.6.3.1.2 forward equations")
    func ybrInverse() {
        let f = YBRFullConversion.forwardMatrix, inv = YBRFullConversion.inverseMatrix
        #expect(f == [[0.2990, 0.5870, 0.1140], [-0.1687, -0.3313, 0.5000], [0.5000, -0.4187, -0.0813]])
        for r in 0..<3 { for c in 0..<3 {
            let product = (0..<3).reduce(0.0) { $0 + inv[r][$1] * f[$1][c] }
            #expect(abs(product - (r == c ? 1 : 0)) < 1e-12)
        } }
        // Black, white, and a pure red forward-converted with the PS3.3 equations.
        let red = Data([76, 85, 255])   // Y = .299·255, CB = −.1687·255 + 128, CR = .5·255 + 128 (clamped)
        let d = PixelDataDescriptor(rows: 1, columns: 3, bitsAllocated: 8, bitsStored: 8, highBit: 7,
                                    isSigned: false, samplesPerPixel: 3, photometricInterpretation: .ybrFull)
        let rgb = YBRFullConversion.rgb(fromYBRFull: Data([0, 128, 128, 255, 128, 128]) + red, descriptor: d)
        #expect(rgb.map { Array($0) } == [0, 0, 0, 255, 255, 255, 254, 0, 0])
    }

    // MARK: - D-CORE-3: YBR_FULL → JPEG 2000 / HTJ2K

    @Test("D-CORE-3: YBR_FULL lossy J2K is converted to RGB and labelled YBR_ICT; reversible is refused")
    func ybrFullToJ2K() throws {
        let source = colourDataSet("YBR_FULL", pixels: gradient())
        for target in [TransferSyntax.jpeg2000, .htj2kLossy] {
            let converter = TransferSyntaxConverter(
                configuration: TranscodingConfiguration(preferredSyntaxes: [target], allowLossyCompression: true,
                                                        preservePixelDataFidelity: false),
                compressionConfiguration: .default)
            let encoded = try converter.transcode(dataSetData: source, from: .explicitVRLittleEndian, to: target)
            #expect(photometric(encoded.data) == "YBR_ICT", "\(target.uid)")
            let back = try converter.transcode(dataSetData: encoded.data, from: target, to: .explicitVRLittleEndian)
            #expect(photometric(back.data) == "RGB", "\(target.uid)")
        }
        let lossless = TransferSyntaxConverter(
            configuration: TranscodingConfiguration(preferredSyntaxes: [.jpeg2000Lossless], allowLossyCompression: false,
                                                    preservePixelDataFidelity: true),
            compressionConfiguration: .lossless)
        #expect(throws: TranscodingError.self) {
            try lossless.transcode(dataSetData: source, from: .explicitVRLittleEndian, to: .jpeg2000Lossless)
        }
    }

    // MARK: - D190 / D-CORE-2: JPEG Baseline colour

    @Test("D190: JLICodec colour Baseline is 4:2:2 and the transcoder labels it YBR_FULL_422")
    func jpegColour422() throws {
        let converter = TransferSyntaxConverter(
            configuration: TranscodingConfiguration(preferredSyntaxes: [.jpegBaseline], allowLossyCompression: true,
                                                    preservePixelDataFidelity: false),
            compressionConfiguration: .default)
        let encoded = try converter.transcode(dataSetData: colourDataSet("RGB", pixels: gradient()),
                                              from: .explicitVRLittleEndian, to: .jpegBaseline)
        #expect(photometric(encoded.data) == "YBR_FULL_422")
        #expect(value(.planarConfiguration, in: encoded.data) == Data([0, 0]))

        let d = PixelDataDescriptor(rows: 16, columns: 16, bitsAllocated: 8, bitsStored: 8, highBit: 7,
                                    isSigned: false, samplesPerPixel: 3, photometricInterpretation: .rgb)
        let frame = try JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid)
            .encodeFrame(gradient(), descriptor: d, frameIndex: 0, configuration: .default)
        let components = try #require(JPEGInterchangeFormat.frameComponents(in: frame))
        #expect(components.map { [$0.horizontalSampling, $0.verticalSampling] } == [[2, 1], [1, 1], [1, 1]])
        #expect(JPEGInterchangeFormat.isHorizontally422(frame))
        // JPEG Extended has no 3-sample row in Table 8.2.1-1.
        #expect(!JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegExtended.uid)
            .canEncode(with: .default, descriptor: d))
    }

    // MARK: - D206: byte order (PS3.5 2026a 7.3)

    @Test("D206: DICOMWriter swaps 2/4/8-byte binary VRs into its byte order, not strings or OB")
    func writerSwapsValues() {
        let be = DICOMWriter(byteOrder: .bigEndian, explicitVR: true)
        let cases: [(VR, Data, Data)] = [
            (.US, Data([0x34, 0x12]), Data([0x12, 0x34])),
            (.AT, Data([0x28, 0x00, 0x10, 0x00]), Data([0x00, 0x28, 0x00, 0x10])),
            (.UL, Data([1, 2, 3, 4]), Data([4, 3, 2, 1])),
            (.FD, Data([1, 2, 3, 4, 5, 6, 7, 8]), Data([8, 7, 6, 5, 4, 3, 2, 1])),
            (.OW, Data([1, 2, 3, 4]), Data([2, 1, 4, 3])),
            (.OB, Data([1, 2, 3, 4]), Data([1, 2, 3, 4])),
            (.LO, Data("ABCD".utf8), Data("ABCD".utf8)),
        ]
        for (vr, le, expected) in cases {
            let element = DataElement(tag: Tag(group: 0x0009, element: 0x1000), vr: vr, length: UInt32(le.count), valueData: le)
            #expect(be.serializeElement(element).suffix(le.count) == expected, "\(vr)")
            // Already big-endian values are written as they are.
            let marked = DataElement(tag: element.tag, vr: vr, length: UInt32(le.count), valueData: expected, byteOrder: .bigEndian)
            #expect(be.serializeElement(marked).suffix(le.count) == expected, "\(vr)")
        }
    }

    @Test("D206: TransferSyntaxConverter LE → BE → LE is lossless (no double swap)")
    func converterBigEndianRoundTrip() throws {
        let source = colourDataSet("MONOCHROME2", pixels: Data([1, 2, 3, 4]), rows: 1, columns: 4)
        let converter = TransferSyntaxConverter()
        let be = try converter.transcode(dataSetData: source, from: .explicitVRLittleEndian, to: .explicitVRBigEndian)
        #expect(be.data.range(of: Data([0x00, 0x28, 0x00, 0x11, 0x55, 0x53, 0x00, 0x02, 0x00, 0x04])) != nil)
        let back = try converter.transcode(dataSetData: be.data, from: .explicitVRBigEndian, to: .explicitVRLittleEndian)
        #expect(back.data == source)
    }

    @Test("D206 / D-CORE-5: Big Endian 16-bit source with a nested US → JPEG 2000 Lossless keeps values and the sequence")
    func bigEndianSourceToJ2K() throws {
        let le = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        let beWriter = DICOMWriter(byteOrder: .bigEndian, explicitVR: true)
        let item = SequenceItem(elements: [us(Tag(group: 0x0028, element: 0x0010), 7)])
        let sq = DataElement(tag: Tag(group: 0x0008, element: 0x1140), vr: .SQ, length: 0, valueData: Data(),
                             sequenceItems: [item])
        let samples: [UInt16] = [0x0102, 0x0304, 0x0506, 0x0708, 0x0A0B, 0x0C0D]
        let pixelLE = samples.reduce(into: Data()) { $0.append(UInt8($1 & 0xFF)); $0.append(UInt8($1 >> 8)) }
        let elements: [DataElement] = [
            sq,
            us(.samplesPerPixel, 1),
            DataElement(tag: .photometricInterpretation, vr: .CS, length: 12, valueData: Data("MONOCHROME2 ".utf8)),
            us(.rows, 2), us(.columns, 3),
            us(.bitsAllocated, 16), us(.bitsStored, 16), us(.highBit, 15), us(.pixelRepresentation, 0),
            DataElement(tag: .pixelData, vr: .OW, length: UInt32(pixelLE.count), valueData: pixelLE),
        ]
        let leSource = elements.reduce(into: Data()) { $0.append(le.serializeElement($1)) }
        let beSource = elements.reduce(into: Data()) { $0.append(beWriter.serializeElement($1)) }
        #expect(leSource != beSource)

        let converter = TransferSyntaxConverter(
            configuration: TranscodingConfiguration(preferredSyntaxes: [.jpeg2000Lossless], allowLossyCompression: false,
                                                    preservePixelDataFidelity: true),
            compressionConfiguration: .lossless)
        let j2k = try converter.transcode(dataSetData: beSource, from: .explicitVRBigEndian, to: .jpeg2000Lossless)
        let back = try converter.transcode(dataSetData: j2k.data, from: .jpeg2000Lossless, to: .explicitVRLittleEndian)
        #expect(value(.pixelData, in: back.data) == pixelLE)
        #expect(value(.rows, in: back.data) == Data([2, 0]))
        // The nested Rows (0028,0010) US 7 inside the defined-length sequence, little-endian.
        #expect(back.data.range(of: Data([0x28, 0x00, 0x10, 0x00, 0x55, 0x53, 0x02, 0x00, 0x07, 0x00])) != nil)
    }
}
