// NEMA-verified: 2026a, checked 2026-10-01 — pins the deferred DICOM JSON / XML data-exchange rows to the 2026a text: PS3.18 F.2.6 and PS3.19 Table A.1.5-2 (D110, D113, D115), PS3.18 10.4.1.1.2 / 10.4.3.3.2 (D111), PS3.10 7.1 (D-WEB-FILEMETA-1)

import XCTest
@testable import DICOMWeb
import DICOMKit
import DICOMCore

final class DataExchangeDeferredRowsTests: XCTestCase {

    // MARK: - Helpers

    private func str(_ group: UInt16, _ element: UInt16, _ vr: VR, _ value: String) -> DataElement {
        var data = Data(value.utf8)
        if data.count % 2 == 1 { data.append(vr == .UI ? 0 : 0x20) }
        return DataElement(tag: Tag(group: group, element: element), vr: vr, length: UInt32(data.count), valueData: data)
    }

    private func bin(_ group: UInt16, _ element: UInt16, _ vr: VR, count: Int, byte: UInt8 = 0xAB) -> DataElement {
        DataElement(tag: Tag(group: group, element: element), vr: vr, length: UInt32(count),
                    valueData: Data(repeating: byte, count: count))
    }

    private func seq(_ group: UInt16, _ element: UInt16, _ items: [[DataElement]]) -> DataElement {
        DataElement(tag: Tag(group: group, element: element), vr: .SQ, length: 0xFFFFFFFF, valueData: Data(),
                    sequenceItems: items.map { SequenceItem(elements: $0) })
    }

    private func part10(_ elements: [DataElement]) throws -> Data {
        var all = elements
        all.append(str(0x0008, 0x0016, .UI, "1.2.840.10008.5.1.4.1.1.7"))
        all.append(str(0x0008, 0x0018, .UI, "1.2.826.0.1.3680043.10.511.7"))
        return try DICOMFile.create(dataSet: DataSet(elements: all)).write()
    }

    private func allTags(_ object: [String: Any]) -> Set<String> {
        var out = Set(object.keys)
        for case let element as [String: Any] in object.values {
            for case let item as [String: Any] in (element["Value"] as? [Any]) ?? [] { out.formUnion(allTags(item)) }
        }
        return out
    }

    // MARK: - D110: one BulkDataURI per element (PS3.18 F.2.6, PS3.19 Table A.1.5-2)

    private var nestedBulkData: [DataElement] {
        [
            bin(0x7FE0, 0x0010, .OB, count: 2048, byte: 1),
            seq(0x0088, 0x0200, [[bin(0x7FE0, 0x0010, .OB, count: 2048, byte: 2)],
                                 [bin(0x7FE0, 0x0010, .OB, count: 2048, byte: 3)]]),
        ]
    }

    func test_D110_jsonBulkDataURIIsUniquePerElementPath() throws {
        let base = URL(string: "http://h/bulk")!
        let object = try DICOMJSONEncoder(configuration: .init(bulkDataBaseURL: base)).encodeToObject(nestedBulkData)
        XCTAssertEqual((object["7FE00010"] as? [String: Any])?["BulkDataURI"] as? String, "http://h/bulk/7FE00010")
        let items = ((object["00880200"] as? [String: Any])?["Value"] as? [[String: Any]]) ?? []
        let uris = items.compactMap { ($0["7FE00010"] as? [String: Any])?["BulkDataURI"] as? String }
        XCTAssertEqual(uris, ["http://h/bulk/00880200/1/7FE00010", "http://h/bulk/00880200/2/7FE00010"])
    }

    func test_D110_xmlBulkDataURIIsUniquePerElementPath() throws {
        let xml = try DICOMXMLEncoder(configuration: .init(bulkDataBaseURL: URL(string: "http://h/bulk")!))
            .encodeToString(nestedBulkData)
        for uri in ["http://h/bulk/7FE00010", "http://h/bulk/00880200/1/7FE00010", "http://h/bulk/00880200/2/7FE00010"] {
            XCTAssertEqual(xml.components(separatedBy: "uri=\"\(uri)\"").count - 1, 1, uri)
        }
    }

    // MARK: - D111: metadata-only leaves out all Bulk Data (PS3.18 10.4.1.1.2, 10.4.3.3.2)

    private func metadataInput() throws -> Data {
        try part10([
            str(0x0010, 0x0010, .PN, "DOE^JOHN"),
            bin(0x0042, 0x0011, .OB, count: 2048),             // Encapsulated Document
            bin(0x7FE0, 0x0008, .OF, count: 64),               // Float Pixel Data
            bin(0x0028, 0x1201, .OW, count: 16),               // Red Palette LUT Data
            seq(0x0088, 0x0200, [[str(0x0028, 0x0004, .CS, "MONOCHROME2"), bin(0x7FE0, 0x0010, .OB, count: 32)]]),
            bin(0x7FE0, 0x0010, .OB, count: 4096),
        ])
    }

    func test_D111_metadataOnlyLeavesOutBulkDataAtEveryDepth() throws {
        let (data, _) = try DataExchangeWorkflow.encode(dicomData: try metadataInput(), format: .json,
                                                        options: .init(metadataOnly: true))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tags = allTags(object)
        for gone in ["00420011", "7FE00008", "00281201", "7FE00010"] { XCTAssertFalse(tags.contains(gone), gone) }
        for kept in ["00100010", "00880200", "00280004", "00080018"] { XCTAssertTrue(tags.contains(kept), kept) }
    }

    func test_D111_metadataOnlyWithBulkDataURLReferencesEveryBulkDataElement() throws {
        let (data, _) = try DataExchangeWorkflow.encode(
            dicomData: try metadataInput(), format: .json,
            options: .init(bulkDataURL: "http://h/b", metadataOnly: true))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("InlineBinary"))
        for uri in ["http://h/b/00420011", "http://h/b/7FE00008", "http://h/b/00281201",
                    "http://h/b/00880200/1/7FE00010", "http://h/b/7FE00010"] {
            XCTAssertTrue(text.contains(uri.replacingOccurrences(of: "/", with: "\\/")) || text.contains(uri), uri)
        }
    }

    // MARK: - D113: BulkData references on reverse conversion (PS3.18 F.2.6, PS3.19 A.1.5-2)

    func test_D113_unresolvableBulkDataURIIsReported() throws {
        let json = """
        {"00080016": {"vr": "UI", "Value": ["1.2.840.10008.5.1.4.1.1.7"]},
         "00080018": {"vr": "UI", "Value": ["1.2.3.4"]},
         "7FE00010": {"vr": "OB", "BulkDataURI": "http://h/bulk/7FE00010"}}
        """
        let (_, console) = try DataExchangeWorkflow.decode(textData: Data(json.utf8), format: .json,
                                                          options: .init(reverse: true))
        XCTAssertEqual(console.filter { $0.hasPrefix("Warning: (7FE0,0010) BulkDataURI http://h/bulk/7FE00010") }.count, 1)
    }

    func test_D113_fileBulkDataReferenceIsResolved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("d113-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = Data((0..<64).map { UInt8($0) })
        let file = dir.appendingPathComponent("pixels.bin")
        try payload.write(to: file)

        let json = """
        {"00080016": {"vr": "UI", "Value": ["1.2.840.10008.5.1.4.1.1.7"]},
         "00080018": {"vr": "UI", "Value": ["1.2.3.4"]},
         "7FE00010": {"vr": "OB", "BulkDataURI": "\(file.absoluteString)"}}
        """
        let (data, console) = try DataExchangeWorkflow.decode(textData: Data(json.utf8), format: .json,
                                                              options: .init(reverse: true))
        XCTAssertTrue(console.filter { $0.hasPrefix("Warning:") }.isEmpty)
        XCTAssertEqual(try DICOMFile.read(from: data).dataSet[Tag.pixelData]?.valueData, payload)

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <NativeDicomModel xmlns="http://dicom.nema.org/PS3.19/models/NativeDICOM" xml:space="preserve">
          <DicomAttribute tag="00080016" vr="UI"><Value number="1">1.2.840.10008.5.1.4.1.1.7</Value></DicomAttribute>
          <DicomAttribute tag="00080018" vr="UI"><Value number="1">1.2.3.4</Value></DicomAttribute>
          <DicomAttribute tag="00420011" vr="OB"><BulkData uri="\(file.absoluteString)"/></DicomAttribute>
          <DicomAttribute tag="7FE00010" vr="OB"><BulkData uuid="b0c2b0e4-0000-4000-8000-000000000001"/></DicomAttribute>
        </NativeDicomModel>
        """
        let (xdata, xconsole) = try DataExchangeWorkflow.decode(textData: Data(xml.utf8), format: .xml,
                                                                options: .init(reverse: true))
        XCTAssertEqual(try DICOMFile.read(from: xdata).dataSet[Tag(group: 0x0042, element: 0x0011)]?.valueData, payload)
        XCTAssertEqual(xconsole.filter { $0.hasPrefix("Warning: (7FE0,0010) BulkData b0c2b0e4") }.count, 1)
    }

    // MARK: - D115: PersonName numbering 1..n by 1 (PS3.19 Table A.1.5-2)

    func test_D115_emptyPersonNameValueKeepsItsNumberAndRoundTrips() throws {
        let value = "A^B\\\\C^D^E^Dr^Jr"
        let xml = try DICOMXMLEncoder().encodeToString([str(0x0010, 0x1001, .PN, value)])
        XCTAssertTrue(xml.contains("<PersonName number=\"1\">"))
        XCTAssertTrue(xml.contains("<PersonName number=\"2\"/>"))
        XCTAssertTrue(xml.contains("<PersonName number=\"3\">"))
        let decoded = try DICOMXMLDecoder().decode(xml)
        XCTAssertEqual(decoded.first?.stringValue?.trimmingCharacters(in: .whitespaces), value)
    }

    // MARK: - D-WEB-FILEMETA-1: group 0002 stays out of the data set (PS3.10 7.1)

    func test_fileMeta_group0002InInputIsNotWrittenIntoTheDataSet() throws {
        let json = """
        {"00020010": {"vr": "UI", "Value": ["1.2.840.10008.1.2"]},
         "00020013": {"vr": "SH", "Value": ["OTHER_TOOL"]},
         "00080016": {"vr": "UI", "Value": ["1.2.840.10008.5.1.4.1.1.7"]},
         "00080018": {"vr": "UI", "Value": ["1.2.3.4"]},
         "00100010": {"vr": "PN", "Value": [{"Alphabetic": "DOE^JOHN"}]}}
        """
        let (data, _) = try DataExchangeWorkflow.decode(textData: Data(json.utf8), format: .json,
                                                        options: .init(reverse: true))
        let file = try DICOMFile.read(from: data)
        XCTAssertEqual(file.dataSet.allElements.filter { $0.tag.group == 0x0002 }.map(\.tag), [])
        XCTAssertEqual(file.fileMetaInformation.string(for: .transferSyntaxUID), "1.2.840.10008.1.2")
        XCTAssertEqual(file.dataSet.string(for: .patientName), "DOE^JOHN")
    }
}
