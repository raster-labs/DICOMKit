import XCTest
@testable import DICOMWeb
@testable import DICOMCore

/// Native DICOM Model rules of PS3.19 2026a Annex A.1 (Table A.1.5-2, schema A.1.6) that the
/// XML encoder and decoder must follow.
final class DICOMXMLModelConformanceTests: XCTestCase {

    private func le<T: FixedWidthInteger>(_ values: [T]) -> Data {
        var data = Data()
        for value in values {
            var v = value.littleEndian
            data.append(Data(bytes: &v, count: MemoryLayout<T>.size))
        }
        return data
    }

    func testRootCarriesXMLSpacePreserve() throws {
        let xml = try DICOMXMLEncoder().encodeToString([])
        XCTAssertTrue(xml.contains("<NativeDicomModel xmlns=\"http://dicom.nema.org/PS3.19/models/NativeDICOM\" xml:space=\"preserve\">"),
                      "Table A.1.5-1: the directive xml:space=\"preserve\" shall be included")
    }

    func testNumericVRsAreWrittenAsValuesAndReadBack() throws {
        let rows = DataElement(tag: Tag.rows, vr: .US, length: 2, valueData: le([UInt16(512)]))
        let fl = DataElement(tag: Tag(group: 0x0018, element: 0x0050), vr: .FL, length: 4, valueData: le([Float32(1.5).bitPattern]))
        let sv = DataElement(tag: Tag(group: 0x0072, element: 0x0082), vr: .SV, length: 8, valueData: le([Int64(-5)]))
        let uv = DataElement(tag: Tag(group: 0x0072, element: 0x0083), vr: .UV, length: 8, valueData: le([UInt64.max]))
        let at = DataElement(tag: Tag(group: 0x0072, element: 0x0026), vr: .AT, length: 4, valueData: le([UInt16(0x0010), UInt16(0x0020)]))

        let xml = try DICOMXMLEncoder().encodeToString([rows, fl, sv, uv, at])
        XCTAssertTrue(xml.contains("<Value number=\"1\">512</Value>"), "US value missing (D4)")
        XCTAssertTrue(xml.contains("<Value number=\"1\">1.5</Value>"))
        XCTAssertTrue(xml.contains("<Value number=\"1\">-5</Value>"))
        XCTAssertTrue(xml.contains("<Value number=\"1\">18446744073709551615</Value>"))
        XCTAssertTrue(xml.contains("<Value number=\"1\">00100020</Value>"), "AT is the 8-character uppercase hex tag")

        let decoded = try DICOMXMLDecoder().decode(xml)
        let byTag = Dictionary(uniqueKeysWithValues: decoded.map { ($0.tag, $0) })
        XCTAssertEqual(byTag[Tag.rows]?.uint16Value, 512)
        XCTAssertEqual(byTag[Tag.rows]?.valueData, le([UInt16(512)]))
        XCTAssertEqual(byTag[Tag(group: 0x0018, element: 0x0050)]?.float32Values, [1.5])
        XCTAssertEqual(byTag[Tag(group: 0x0072, element: 0x0082)]?.int64Values, [-5])
        XCTAssertEqual(byTag[Tag(group: 0x0072, element: 0x0083)]?.uint64Values, [UInt64.max])
        XCTAssertEqual(byTag[Tag(group: 0x0072, element: 0x0026)]?.attributeTagValues, [Tag(group: 0x0010, element: 0x0020)])
    }

    func testOVIsInlineBinary() throws {
        let data = le([UInt64(1), UInt64(2)])
        let ov = DataElement(tag: Tag(group: 0x7FE0, element: 0x0001), vr: .OV, length: 16, valueData: data)
        let xml = try DICOMXMLEncoder().encodeToString([ov])
        XCTAssertTrue(xml.contains("<InlineBinary>\(data.base64EncodedString())</InlineBinary>"), "D4: OV omitted from the binary VRs")
        XCTAssertEqual(try DICOMXMLDecoder().decode(xml).first?.valueData, data)
    }

    func testEmptyValuesOfMultiValuedAttributeArePreserved() throws {
        // Table A.1.5-2: "MPG\\XR3" is three Value elements, the second zero length
        let element = DataElement(tag: Tag(group: 0x0008, element: 0x0008), vr: .CS, length: 8, valueData: Data("MPG\\\\XR3".utf8))
        let xml = try DICOMXMLEncoder().encodeToString([element])
        XCTAssertTrue(xml.contains("<Value number=\"1\">MPG</Value>"))
        XCTAssertTrue(xml.contains("<Value number=\"2\"></Value>"))
        XCTAssertTrue(xml.contains("<Value number=\"3\">XR3</Value>"))
        XCTAssertEqual(try DICOMXMLDecoder().decode(xml).first?.stringValue, "MPG\\\\XR3")
    }

    func testGroupLengthIsNotWritten() throws {
        let groupLength = DataElement(tag: Tag(group: 0x0008, element: 0x0000), vr: .UL, length: 4, valueData: le([UInt32(10)]))
        let xml = try DICOMXMLEncoder().encodeToString([groupLength])
        XCTAssertFalse(xml.contains("00080000"), "A.1.1: Group Length attributes shall not be included")
    }

    func testPrivateElementsCarryPrivateCreatorAndRoundTrip() throws {
        let creator = DataElement(tag: Tag(group: 0x0009, element: 0x0010), vr: .LO, length: 8, valueData: Data("ACME 1.0".utf8))
        let value = DataElement(tag: Tag(group: 0x0009, element: 0x1001), vr: .LO, length: 4, valueData: Data("abcd".utf8))
        let xml = try DICOMXMLEncoder().encodeToString([creator, value])
        XCTAssertTrue(xml.contains("tag=\"00090001\" vr=\"LO\" privateCreator=\"ACME 1.0\""),
                      "Table A.1.5-2: private tag has the form gggg00ee and carries privateCreator")
        XCTAssertFalse(xml.contains("00091001"))

        // Decoding assigns the block from the creator, whichever order the attributes come in
        let decoded = try DICOMXMLDecoder().decode(xml)
        XCTAssertEqual(decoded.map { $0.tag }, [Tag(group: 0x0009, element: 0x0010), Tag(group: 0x0009, element: 0x1001)])
        XCTAssertEqual(decoded.last?.stringValue, "abcd")

        // A private element without its creator element in the document gets a block allocated
        let orphan = """
        <NativeDicomModel xmlns="http://dicom.nema.org/PS3.19/models/NativeDICOM">
          <DicomAttribute tag="00090002" vr="SH" privateCreator="OTHER"><Value number="1">x</Value></DicomAttribute>
        </NativeDicomModel>
        """
        let allocated = try DICOMXMLDecoder().decode(orphan)
        XCTAssertEqual(allocated.map { $0.tag }, [Tag(group: 0x0009, element: 0x0010), Tag(group: 0x0009, element: 0x1002)])
        XCTAssertEqual(allocated.first?.stringValue, "OTHER")
    }

    func testBulkDataUUIDIsAcceptedAsReference() throws {
        let xml = """
        <NativeDicomModel xmlns="http://dicom.nema.org/PS3.19/models/NativeDICOM">
          <DicomAttribute tag="7FE00010" vr="OB"><BulkData uuid="3bcfc4fe-a3ba-4a1c-8d2c-000000000001"/></DicomAttribute>
        </NativeDicomModel>
        """
        let decoded = try DICOMXMLDecoder().decode(xml)
        XCTAssertEqual(decoded.first?.vr, .OB)
        XCTAssertTrue(decoded.first?.valueData.isEmpty ?? false)
    }
}
