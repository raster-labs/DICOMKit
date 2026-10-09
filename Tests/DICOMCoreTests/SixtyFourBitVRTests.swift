import Testing
import Foundation
@testable import DICOMCore

/// OV, SV and UV (PS3.5 Table 6.2-1, CP 1819): value accessors and byte-order
/// transcoding (PS3.5 §7.3 lists them with OD and FD as the 8-byte swapped VRs).
@Suite("64-bit VR (OV/SV/UV) Tests")
struct SixtyFourBitVRTests {

    // MARK: - Value accessors

    @Test("UV single and multi-value extraction")
    func testUVValues() {
        let data = le64(0x0102_0304_0506_0708) + le64(UInt64.max)
        let element = DataElement(tag: Tag(group: 0x0072, element: 0x0083), vr: .UV, length: 16, valueData: data)

        #expect(element.uint64Value == 0x0102_0304_0506_0708)
        #expect(element.uint64Values == [0x0102_0304_0506_0708, UInt64.max])
        #expect(element.int64Value == nil)
    }

    @Test("SV signed extraction keeps negative values")
    func testSVValues() {
        let data = le64(UInt64(bitPattern: -2)) + le64(UInt64(bitPattern: Int64.min))
        let element = DataElement(tag: Tag(group: 0x0072, element: 0x0082), vr: .SV, length: 16, valueData: data)

        #expect(element.int64Value == -2)
        #expect(element.int64Values == [-2, Int64.min])
        // The unsigned view reads the raw bit pattern, as uint32Value does for SL.
        #expect(element.uint64Value == UInt64(bitPattern: -2))
    }

    @Test("OV stream reads as 64-bit words")
    func testOVValues() {
        let data = le64(0) + le64(123_456) + le64(1 << 40)
        let element = DataElement(tag: Tag(group: 0x7FE0, element: 0x0001), vr: .OV, length: 24, valueData: data)

        #expect(element.uint64Values == [0, 123_456, 1 << 40])
        #expect(element.int64Values == nil)
    }

    @Test("Big-endian element decodes 64-bit values in its own byte order")
    func testBigEndianElement() {
        let data = Data(le64(UInt64(bitPattern: -5)).reversed())
        let element = DataElement(tag: Tag(group: 0x0072, element: 0x0082), vr: .SV, length: 8,
                                  valueData: data, byteOrder: .bigEndian)

        #expect(element.int64Value == -5)
    }

    @Test("Short or non-64-bit data returns nil")
    func testRejectsWrongVROrLength() {
        let short = DataElement(tag: Tag(group: 0x0072, element: 0x0083), vr: .UV, length: 4,
                                valueData: Data([1, 2, 3, 4]))
        #expect(short.uint64Value == nil)

        let ul = DataElement(tag: Tag(group: 0x0008, element: 0x0000), vr: .UL, length: 8, valueData: le64(1))
        #expect(ul.uint64Value == nil)
        #expect(ul.uint64Values == nil)
    }

    // MARK: - Byte-order transcoding

    @Test("OV, SV and UV are byte-swapped per 64-bit word on LE→BE→LE")
    func testEndianTranscodeRoundTrip() throws {
        let uv: UInt64 = 0x0102_0304_0506_0708
        let sv: Int64 = -2
        var src = Data()
        src += explicitLongElement(group: 0x0072, element: 0x0081, vr: "OV", value: le64(uv) + le64(7))
        src += explicitLongElement(group: 0x0072, element: 0x0082, vr: "SV", value: le64(UInt64(bitPattern: sv)))
        src += explicitLongElement(group: 0x0072, element: 0x0083, vr: "UV", value: le64(uv))

        let converter = TransferSyntaxConverter()
        let be = try converter.transcode(dataSetData: src, from: .explicitVRLittleEndian, to: .explicitVRBigEndian)
        let out = [UInt8](be.data)

        // Each 64-bit word must be fully reversed, not left in little-endian order.
        #expect(containsSubsequence(out, [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]))
        #expect(!containsSubsequence(out, [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]))
        #expect(containsSubsequence(out, [0, 0, 0, 0, 0, 0, 0, 7]))
        #expect(containsSubsequence(out, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE]))

        let back = try converter.transcode(dataSetData: be.data, from: .explicitVRBigEndian, to: .explicitVRLittleEndian)
        #expect(back.data == src)
    }

    // MARK: - Helpers

    private func le64(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// Explicit VR Little Endian element with the reserved-bytes + 32-bit length header
    /// (PS3.5 Table 7.1-1), which OV, SV and UV use.
    private func explicitLongElement(group: UInt16, element: UInt16, vr: String, value: Data) -> Data {
        var data = Data()
        data += withUnsafeBytes(of: group.littleEndian) { Data($0) }
        data += withUnsafeBytes(of: element.littleEndian) { Data($0) }
        data += Data(vr.utf8)
        data += Data([0x00, 0x00])
        data += withUnsafeBytes(of: UInt32(value.count).littleEndian) { Data($0) }
        data += value
        return data
    }

    private func containsSubsequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<start + needle.count]) == needle { return true }
        }
        return false
    }
}
