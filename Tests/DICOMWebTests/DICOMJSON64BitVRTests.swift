import Testing
import Foundation
@testable import DICOMWeb
import DICOMCore

/// OV, SV and UV in the DICOM JSON Model (PS3.18 Table F.2.3-1): OV is Base64
/// InlineBinary; SV and UV are "Number or String".
@Suite("DICOM JSON 64-bit VR Tests")
struct DICOMJSON64BitVRTests {

    let encoder = DICOMJSONEncoder()
    let decoder = DICOMJSONDecoder()

    @Test("OV encodes as InlineBinary, the same way as OB")
    func testEncodeOVInlineBinary() throws {
        let data = le64(1) + le64(2)
        let ov = DataElement(tag: Tag(group: 0x7FE0, element: 0x0001), vr: .OV, length: 16, valueData: data)
        let ob = DataElement(tag: Tag(group: 0x7FE0, element: 0x0010), vr: .OB, length: 16, valueData: data)
        let result = try encoder.encodeToObject([ov, ob])

        let ovDict = result["7FE00001"] as? [String: Any]
        let obDict = result["7FE00010"] as? [String: Any]
        #expect(ovDict?["vr"] as? String == "OV")
        #expect(ovDict?["InlineBinary"] as? String == data.base64EncodedString())
        #expect(ovDict?["Value"] == nil)
        #expect(NSDictionary(dictionary: ovDict?.filter { $0.key != "vr" } ?? [:])
                == NSDictionary(dictionary: obDict?.filter { $0.key != "vr" } ?? [:]))
    }

    @Test("SV and UV within 2^53 encode as JSON Numbers")
    func testEncodeSmallValuesAsNumbers() throws {
        let sv = DataElement(tag: Tag(group: 0x0072, element: 0x0082), vr: .SV, length: 16,
                             valueData: le64(UInt64(bitPattern: -42)) + le64(7))
        let uv = DataElement(tag: Tag(group: 0x0072, element: 0x0083), vr: .UV, length: 8, valueData: le64(9_007_199_254_740_991))
        let result = try encoder.encodeToObject([sv, uv])

        let svValues = (result["00720082"] as? [String: Any])?["Value"] as? [Any]
        #expect((svValues?[0] as? NSNumber)?.int64Value == -42)
        #expect((svValues?[1] as? NSNumber)?.int64Value == 7)
        let uvValues = (result["00720083"] as? [String: Any])?["Value"] as? [Any]
        #expect((uvValues?[0] as? NSNumber)?.uint64Value == 9_007_199_254_740_991)
    }

    @Test("SV and UV beyond 2^53 encode as Strings to keep precision")
    func testEncodeLargeValuesAsStrings() throws {
        let sv = DataElement(tag: Tag(group: 0x0072, element: 0x0082), vr: .SV, length: 8,
                             valueData: le64(UInt64(bitPattern: Int64.min)))
        let uv = DataElement(tag: Tag(group: 0x0072, element: 0x0083), vr: .UV, length: 8, valueData: le64(UInt64.max))
        let result = try encoder.encodeToObject([sv, uv])

        #expect(((result["00720082"] as? [String: Any])?["Value"] as? [Any])?.first as? String == "-9223372036854775808")
        #expect(((result["00720083"] as? [String: Any])?["Value"] as? [Any])?.first as? String == "18446744073709551615")
    }

    @Test("SV and UV decode from both Numbers and Strings")
    func testDecodeNumberAndString() throws {
        let json = """
        {
            "00720082": { "vr": "SV", "Value": [-42, "-9223372036854775808"] },
            "00720083": { "vr": "UV", "Value": [7, "18446744073709551615"] }
        }
        """
        let elements = try decoder.decode(string: json)
        let sv = elements.first { $0.tag == Tag(group: 0x0072, element: 0x0082) }
        let uv = elements.first { $0.tag == Tag(group: 0x0072, element: 0x0083) }

        #expect(sv?.int64Values == [-42, Int64.min])
        #expect(uv?.uint64Values == [7, UInt64.max])
    }

    @Test("A non-integer SV string is rejected")
    func testDecodeRejectsBadString() {
        let json = """
        { "00720082": { "vr": "SV", "Value": ["12.5"] } }
        """
        #expect(throws: (any Error).self) { try decoder.decode(string: json) }
    }

    @Test("SV, UV and OV round-trip through JSON")
    func testRoundTrip() throws {
        let original = [
            DataElement(tag: Tag(group: 0x0072, element: 0x0081), vr: .OV, length: 8, valueData: le64(1 << 60)),
            DataElement(tag: Tag(group: 0x0072, element: 0x0082), vr: .SV, length: 16,
                        valueData: le64(UInt64(bitPattern: -1)) + le64(UInt64(bitPattern: Int64.max))),
            DataElement(tag: Tag(group: 0x0072, element: 0x0083), vr: .UV, length: 16, valueData: le64(0) + le64(UInt64.max)),
        ]
        let json = try encoder.encode(original)
        let decoded = try decoder.decode(json)

        for element in original {
            let match = decoded.first { $0.tag == element.tag }
            #expect(match?.vr == element.vr)
            #expect(match?.valueData == element.valueData)
        }
    }

    private func le64(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
