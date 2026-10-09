import Testing
import Foundation
@testable import DICOMKit
@testable import DICOMCore

/// A JPEG XL dataset labelled XYB decodes to RGB samples, so decompressing it must
/// relabel Photometric Interpretation to RGB: "Images in XYB transcoded to other
/// Transfer Syntaxes will use RGB" (PS3.3 2026a C.7.6.3.1.2; PS3.5 Table 8.2.15-1).
@Suite("XYB transcode relabelling")
struct XYBTranscodeTests {

    private let width = 8
    private let height = 8

    @Test("Decompressing a JPEG XL XYB dataset writes Photometric Interpretation RGB")
    func testXYBDecodeRelabelsToRGB() throws {
        let pixels = rgbFrame()
        let source = try jxlDataSet(photometric: "XYB", pixels: pixels)

        let result = try TransferSyntaxConverter().transcode(
            dataSetData: source,
            from: .jpegXLLossless,
            to: .explicitVRLittleEndian
        )

        var parser = DICOMParser(data: result.data)
        let elements = try parser.parseDataSet(
            startOffset: 0, transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid)
        #expect(elements[.photometricInterpretation]?.stringValue == "RGB")
        #expect(elements[.samplesPerPixel]?.uint16Value == 3)
        #expect(elements[.pixelData]?.valueData == pixels)
    }

    @Test("A JPEG XL dataset labelled RGB keeps its label")
    func testRGBLabelUnchanged() throws {
        let source = try jxlDataSet(photometric: "RGB", pixels: rgbFrame())

        let result = try TransferSyntaxConverter().transcode(
            dataSetData: source,
            from: .jpegXLLossless,
            to: .explicitVRLittleEndian
        )

        var parser = DICOMParser(data: result.data)
        let elements = try parser.parseDataSet(
            startOffset: 0, transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid)
        #expect(elements[.photometricInterpretation]?.stringValue == "RGB")
    }

    // MARK: - Fixtures

    private func rgbFrame() -> Data {
        var data = Data(count: width * height * 3)
        for i in 0..<data.count { data[i] = UInt8((i * 37) & 0xFF) }
        return data
    }

    /// Explicit VR Little Endian dataset: Image Pixel Module + one JPEG XL Lossless
    /// (.110) frame encapsulated per PS3.5 §A.4.
    private func jxlDataSet(photometric: String, pixels: Data) throws -> Data {
        let descriptor = PixelDataDescriptor(
            rows: height, columns: width,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 3,
            photometricInterpretation: .rgb, planarConfiguration: 0)
        let encoder = try #require(CodecRegistry.shared.encoder(for: TransferSyntax.jpegXLLossless.uid))
        let fragment = try #require(try encoder.encode(pixels, descriptor: descriptor, configuration: .lossless).first)

        var data = Data()
        data += us(0x0028, 0x0002, 3)                 // Samples per Pixel
        data += short(0x0028, 0x0004, "CS", Data(padded(photometric).utf8))
        data += us(0x0028, 0x0006, 0)                 // Planar Configuration
        data += us(0x0028, 0x0010, UInt16(height))    // Rows
        data += us(0x0028, 0x0011, UInt16(width))     // Columns
        data += us(0x0028, 0x0100, 8)                 // Bits Allocated
        data += us(0x0028, 0x0101, 8)                 // Bits Stored
        data += us(0x0028, 0x0102, 7)                 // High Bit
        data += us(0x0028, 0x0103, 0)                 // Pixel Representation

        let evenFragment = fragment.count % 2 == 0 ? fragment : fragment + Data([0])
        data += tag(0x7FE0, 0x0010) + Data("OB".utf8) + Data([0, 0]) + u32(0xFFFF_FFFF)
        data += tag(0xFFFE, 0xE000) + u32(0)                          // empty Basic Offset Table
        data += tag(0xFFFE, 0xE000) + u32(UInt32(evenFragment.count)) + evenFragment
        data += tag(0xFFFE, 0xE0DD) + u32(0)                          // Sequence Delimitation
        return data
    }

    private func padded(_ s: String) -> String { s.count % 2 == 0 ? s : s + " " }
    private func tag(_ g: UInt16, _ e: UInt16) -> Data { u16(g) + u16(e) }
    private func u16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private func short(_ g: UInt16, _ e: UInt16, _ vr: String, _ value: Data) -> Data {
        tag(g, e) + Data(vr.utf8) + u16(UInt16(value.count)) + value
    }
    private func us(_ g: UInt16, _ e: UInt16, _ v: UInt16) -> Data { short(g, e, "US", u16(v)) }
}
