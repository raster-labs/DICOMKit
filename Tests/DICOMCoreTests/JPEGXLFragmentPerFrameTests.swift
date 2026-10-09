import Testing
import Foundation
@testable import DICOMKit
@testable import DICOMCore

/// PS3.5 2026a §A.4.12: for the JPEG XL Transfer Syntaxes "each Frame shall be encoded
/// separately as a single Fragment". Checks the encapsulation the converter writes (P7).
@Suite("JPEG XL one fragment per frame")
struct JPEGXLFragmentPerFrameTests {

    private let width = 8, height = 8, frames = 3

    @Test("A multi-frame image compressed to JPEG XL Lossless has exactly one fragment per frame")
    func testOneFragmentPerFrame() throws {
        let source = nativeDataSet()
        let result = try TransferSyntaxConverter().transcode(
            dataSetData: source, from: .explicitVRLittleEndian, to: .jpegXLLossless)

        var parser = DICOMParser(data: result.data)
        let elements = try parser.parseDataSet(startOffset: 0, transferSyntaxUID: TransferSyntax.jpegXLLossless.uid)
        let pixel = try #require(elements[.pixelData])
        let fragments = try #require(pixel.encapsulatedFragments)
        #expect(fragments.count == frames)
        #expect(pixel.encapsulatedOffsetTable?.count == frames || pixel.encapsulatedOffsetTable == nil)
        for fragment in fragments {
            #expect(fragment.count % 2 == 0, "PS3.5 §A.4: even-length fragments")
            #expect(fragment.count > 0)
        }
    }

    @Test("The same holds for the general JPEG XL syntax (.112)")
    func testOneFragmentPerFrameLossy() throws {
        let result = try TransferSyntaxConverter(configuration: .maxCompression).transcode(
            dataSetData: nativeDataSet(), from: .explicitVRLittleEndian, to: .jpegXL)
        var parser = DICOMParser(data: result.data)
        let elements = try parser.parseDataSet(startOffset: 0, transferSyntaxUID: TransferSyntax.jpegXL.uid)
        #expect(elements[.pixelData]?.encapsulatedFragments?.count == frames)
    }

    // MARK: - Fixture: Explicit VR LE, MONOCHROME2, 8-bit, 3 frames

    private func nativeDataSet() -> Data {
        var pixels = Data(count: width * height * frames)
        for i in 0..<pixels.count { pixels[i] = UInt8((i * 29 + 7) & 0xFF) }
        var data = Data()
        data += us(0x0028, 0x0002, 1)
        data += short(0x0028, 0x0004, "CS", Data("MONOCHROME2 ".utf8))
        data += short(0x0028, 0x0008, "IS", Data("3 ".utf8))
        data += us(0x0028, 0x0010, UInt16(height))
        data += us(0x0028, 0x0011, UInt16(width))
        data += us(0x0028, 0x0100, 8)
        data += us(0x0028, 0x0101, 8)
        data += us(0x0028, 0x0102, 7)
        data += us(0x0028, 0x0103, 0)
        data += tag(0x7FE0, 0x0010) + Data("OB".utf8) + Data([0, 0]) + u32(UInt32(pixels.count)) + pixels
        return data
    }
    private func tag(_ g: UInt16, _ e: UInt16) -> Data { u16(g) + u16(e) }
    private func u16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private func short(_ g: UInt16, _ e: UInt16, _ vr: String, _ value: Data) -> Data {
        tag(g, e) + Data(vr.utf8) + u16(UInt16(value.count)) + value
    }
    private func us(_ g: UInt16, _ e: UInt16, _ v: UInt16) -> Data { short(g, e, "US", u16(v)) }
}
