import Testing
import Foundation
@testable import DICOMWeb
import DICOMCore

/// DICOM JSON Model rules of PS3.18 2026a Annex F that the encoder and decoder must follow:
/// F.2.2 (layout, ordering, Group Length), F.2.3 (AT format), F.2.5 (null and empty values),
/// F.2.6 / F.2.7 (BulkDataURI and InlineBinary as siblings of vr).
@Suite("DICOM JSON Model conformance (PS3.18 Annex F)")
struct DICOMJSONModelConformanceTests {

    let encoder = DICOMJSONEncoder()
    let decoder = DICOMJSONDecoder()

    @Test("F.2.2: InlineBinary and BulkDataURI are siblings of vr, and no Value is written (D2)")
    func testBinaryCarriersAreSiblings() throws {
        let data = Data((0..<8).map { UInt8($0) })
        let element = DataElement(tag: Tag(group: 0x7FE0, element: 0x0010), vr: .OW, length: 8, valueData: data)

        let inline = try encoder.encodeToObject([element])["7FE00010"] as? [String: Any]
        #expect(inline?.keys.sorted() == ["InlineBinary", "vr"])
        #expect(inline?["InlineBinary"] as? String == data.base64EncodedString())

        let bulk = DICOMJSONEncoder(configuration: .init(inlineBinaryThreshold: 4, bulkDataBaseURL: URL(string: "https://s/bulk")!))
        let uri = try bulk.encodeToObject([element])["7FE00010"] as? [String: Any]
        #expect(uri?.keys.sorted() == ["BulkDataURI", "vr"])
        #expect(uri?["BulkDataURI"] as? String == "https://s/bulk/7FE00010")
    }

    @Test("F.2.2: every VR of Table F.2.3-1 that is Base64 is carried as InlineBinary")
    func testAllBinaryVRs() throws {
        let data = Data([1, 2, 3, 4, 5, 6, 7, 8])
        for vr in [VR.OB, .OD, .OF, .OL, .OV, .OW, .UN] {
            let element = DataElement(tag: Tag(group: 0x0009, element: 0x1010), vr: vr, length: 8, valueData: data)
            let object = try encoder.encodeToObject([element])["00091010"] as? [String: Any]
            #expect(object?["InlineBinary"] as? String == data.base64EncodedString(), "\(vr)")
            #expect(object?["Value"] == nil, "\(vr)")
        }
    }

    @Test("F.2.3: AT values are the eight-character uppercase hexadecimal tag (D3)")
    func testAttributeTagEncodesAsString() throws {
        var data = Data()
        for value: UInt16 in [0x0010, 0x0020, 0x0008, 0x103E] {
            var le = value.littleEndian
            data.append(Data(bytes: &le, count: 2))
        }
        let element = DataElement(tag: Tag(group: 0x0072, element: 0x0026), vr: .AT, length: 8, valueData: data)
        let object = try encoder.encodeToObject([element])["00720026"] as? [String: Any]
        #expect(object?["Value"] as? [String] == ["00100020", "0008103E"])

        let decoded = try decoder.decode(try encoder.encode([element]))
        #expect(decoded.first?.attributeTagValues == [Tag(group: 0x0010, element: 0x0020), Tag(group: 0x0008, element: 0x103E)])
    }

    @Test("F.2.2: Group Length attributes are not included")
    func testGroupLengthExcluded() throws {
        var length = UInt32(10).littleEndian
        let groupLength = DataElement(tag: Tag(group: 0x0008, element: 0x0000), vr: .UL, length: 4,
                                      valueData: Data(bytes: &length, count: 4))
        let patientID = DataElement(tag: Tag.patientID, vr: .LO, length: 4, valueData: Data("ID01".utf8))
        let object = try encoder.encodeToObject([groupLength, patientID])
        #expect(object["00080000"] == nil)
        #expect(object["00100020"] != nil)
    }

    @Test("F.2.2: attribute objects are ordered by property name")
    func testSortedByTag() throws {
        let a = DataElement(tag: Tag(group: 0x0020, element: 0x000D), vr: .UI, length: 4, valueData: Data("1.2\0".utf8))
        let b = DataElement(tag: Tag(group: 0x0008, element: 0x0016), vr: .UI, length: 4, valueData: Data("1.3\0".utf8))
        let json = try encoder.encodeToString([a, b])
        let first = json.range(of: "00080016")!.lowerBound
        let second = json.range(of: "0020000D")!.lowerBound
        #expect(first < second)
    }

    @Test("F.2.5: an empty value of a multi-valued attribute is null, in both directions")
    func testNullValues() throws {
        let element = DataElement(tag: Tag(group: 0x0008, element: 0x0060), vr: .CS, length: 8,
                                  valueData: Data("CT\\\\MR\\US".utf8))
        let object = try encoder.encodeToObject([element])["00080060"] as? [String: Any]
        let values = object?["Value"] as? [Any]
        #expect(values?.count == 4)
        #expect(values?[0] as? String == "CT")
        #expect(values?[1] is NSNull)
        #expect(values?[2] as? String == "MR")

        let json = """
        {"00080060": {"vr": "CS", "Value": ["CT", null, "MR"]},
         "00100010": {"vr": "PN", "Value": [{"Alphabetic": "Doe^John"}, null]}}
        """
        let decoded = try decoder.decode(string: json)
        #expect(decoded.first { $0.tag == Tag(group: 0x0008, element: 0x0060) }?.stringValue == "CT\\\\MR")
        #expect(decoded.first { $0.tag == Tag.patientName }?.stringValue == "Doe^John\\")
    }

    @Test("F.2.5: an empty attribute keeps vr and nothing else; an empty sequence too")
    func testEmptyAttributes() throws {
        let empty = DataElement(tag: Tag.patientName, vr: .PN, length: 0, valueData: Data())
        let sequence = DataElement(tag: Tag(group: 0x0008, element: 0x1110), vr: .SQ, length: 0, valueData: Data(), sequenceItems: [])
        let binary = DataElement(tag: Tag(group: 0x7FE0, element: 0x0010), vr: .OB, length: 0, valueData: Data())
        let object = try encoder.encodeToObject([empty, sequence, binary])
        for key in ["00100010", "00081110", "7FE00010"] {
            let attribute = object[key] as? [String: Any]
            #expect(attribute?.count == 1, Comment(rawValue: key))
            #expect(attribute?["vr"] != nil, Comment(rawValue: key))
        }
    }

    @Test("F.2.2: PN component groups are Alphabetic, Ideographic and Phonetic strings; empty groups are omitted")
    func testPersonNameGroups() throws {
        let element = DataElement(tag: Tag.patientName, vr: .PN, length: 18,
                                  valueData: Data("Wang^XiaoDong=王^小東=".utf8))
        let object = try encoder.encodeToObject([element])["00100010"] as? [String: Any]
        let value = (object?["Value"] as? [[String: Any]])?.first
        #expect(value?["Alphabetic"] as? String == "Wang^XiaoDong")
        #expect(value?["Ideographic"] as? String == "王^小東")
        #expect(value?["Phonetic"] == nil)
    }

    @Test("DS and IS are written as strings (F.2.3 Note: preserves the original format)")
    func testDecimalAndIntegerStrings() throws {
        let ds = DataElement(tag: Tag(group: 0x0028, element: 0x0030), vr: .DS, length: 8, valueData: Data("0.5\\0.50".utf8))
        let object = try encoder.encodeToObject([ds])["00280030"] as? [String: Any]
        #expect(object?["Value"] as? [String] == ["0.5", "0.50"])
    }
}
