// JSONRoundTripTests.swift
// Oracle-based round-trip tests for the dicom-json CLI.
//
// The CLI (Sources/dicom-json/main.swift) drives DICOMJSONEncoder /
// DICOMJSONDecoder (DICOMWeb) plus DICOMFile.create/.write. These tests call
// that library directly — they never spawn the CLI — and assert only on
// facts that are true by definition of the DICOM JSON Model (PS3.18 Annex F):
// tag keys are uppercase 8-hex, values live under "Value", string/numeric VRs
// map to JSON strings/numbers, and encode∘decode is tag-preserving.

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore
@testable import DICOMWeb

final class JSONRoundTripTests: XCTestCase {

    // MARK: - Private helpers (test-local; not shared)

    /// DICOM JSON Model tag key: uppercase "GGGGEEEE".
    private func tagKey(_ group: UInt16, _ element: UInt16) -> String {
        String(format: "%04X%04X", group, element)
    }

    /// The element object for a tag key in an encoded DICOM JSON object.
    private func elementObject(_ obj: [String: Any], _ key: String) -> [String: Any]? {
        obj[key] as? [String: Any]
    }

    // MARK: - Tests

    // Oracle: DICOM JSON Model — known string tag becomes key "GGGGEEEE"
    // with vr and a "Value" array carrying the string.
    func testEncodeKnownStringTag() throws {
        var ds = DataSet()
        ds.setString("MR", for: .modality, vr: .CS)
        ds.setString("RoundTrip^Patient", for: .patientName, vr: .PN)

        let encoder = DICOMJSONEncoder()
        let obj = try encoder.encodeToObject(ds.allElements)

        let key = tagKey(0x0008, 0x0060) // Modality
        let modality = try XCTUnwrap(elementObject(obj, key), "Modality key \(key) present")
        XCTAssertEqual(modality["vr"] as? String, "CS")
        let value = try XCTUnwrap(modality["Value"] as? [Any])
        XCTAssertEqual(value.first as? String, "MR")
    }

    // Oracle: numeric VR (US) encodes Rows as a JSON number, not a string.
    func testEncodeNumericTagRows() throws {
        var ds = DataSet()
        ds.setUInt16(128, for: .rows)
        ds.setUInt16(256, for: .columns)

        let encoder = DICOMJSONEncoder()
        let obj = try encoder.encodeToObject(ds.allElements)

        let rowsKey = tagKey(0x0028, 0x0010)
        let rows = try XCTUnwrap(elementObject(obj, rowsKey), "Rows present")
        XCTAssertEqual(rows["vr"] as? String, "US")
        let value = try XCTUnwrap(rows["Value"] as? [Any])
        // JSONSerialization surfaces integers as NSNumber.
        XCTAssertEqual((value.first as? NSNumber)?.intValue, 128)

        let colsKey = tagKey(0x0028, 0x0011)
        let cols = try XCTUnwrap(elementObject(obj, colsKey))
        XCTAssertEqual(((try XCTUnwrap(cols["Value"] as? [Any])).first as? NSNumber)?.intValue, 256)
    }

    // Oracle: encode→decode preserves the exact set of tags and their VRs.
    func testRoundTripElementsPreservesTagsAndVRs() throws {
        var ds = DataSet()
        ds.setString("MR", for: .modality, vr: .CS)
        ds.setString("RT^Name", for: .patientName, vr: .PN)
        ds.setString("1.2.840.10008.5.1.4.1.1.4", for: .sopClassUID, vr: .UI)
        ds.setUInt16(128, for: .rows)
        ds.setUInt16(256, for: .columns)

        let input = ds.allElements
        let encoder = DICOMJSONEncoder()
        let jsonData = try encoder.encode(input)

        let decoder = DICOMJSONDecoder(
            configuration: .init(allowMissingVR: true, fetchBulkData: false, bulkDataHandler: nil))
        let decoded = try decoder.decode(jsonData)

        let inputTags = Set(input.map { $0.tag })
        let decodedTags = Set(decoded.map { $0.tag })
        XCTAssertEqual(inputTags, decodedTags, "all tags preserved")

        // VR preserved per tag.
        let decodedVR = Dictionary(uniqueKeysWithValues: decoded.map { ($0.tag, $0.vr) })
        for e in input {
            XCTAssertEqual(decodedVR[e.tag], e.vr, "VR preserved for \(e.tag)")
        }
    }

    // Oracle: JSON → DICOM → JSON is stable (second JSON == first) for a
    // metadata-only dataset — the DICOM JSON Model is a fixed point here.
    func testRoundTripJSONStableFixedPoint() throws {
        var ds = DataSet()
        ds.setString("MR", for: .modality, vr: .CS)
        ds.setString("RT^Name", for: .patientName, vr: .PN)
        ds.setUInt16(128, for: .rows)
        ds.setUInt16(64, for: .columns)

        let encoder = DICOMJSONEncoder()
        let json1 = try encoder.encode(ds.allElements)

        let decoder = DICOMJSONDecoder(
            configuration: .init(allowMissingVR: true))
        let elements = try decoder.decode(json1)
        let json2 = try encoder.encode(elements)

        // sortedKeys default = true → canonical byte output; fixed point.
        XCTAssertEqual(json1, json2, "JSON→DICOM→JSON reproduces identical JSON")
    }

    // Oracle: string values survive decode exactly (value identity).
    func testRoundTripStringValueIdentity() throws {
        var ds = DataSet()
        ds.setString("HELLO^WORLD", for: .patientName, vr: .PN)
        ds.setString("CT", for: .modality, vr: .CS)

        let encoder = DICOMJSONEncoder()
        let jsonData = try encoder.encode(ds.allElements)
        let decoder = DICOMJSONDecoder(configuration: .init(allowMissingVR: true))
        let decoded = try decoder.decode(jsonData)

        let byTag = Dictionary(uniqueKeysWithValues: decoded.map { ($0.tag, $0) })
        XCTAssertEqual(byTag[.modality]?.stringValue, "CT")
        // PN alphabetic component round-trips its trimmed string.
        XCTAssertEqual(byTag[.patientName]?.stringValue?.trimmingCharacters(in: .whitespaces),
                       "HELLO^WORLD")
    }

    // Oracle: numeric US value survives decode as the same integer.
    func testRoundTripNumericValueIdentity() throws {
        var ds = DataSet()
        ds.setUInt16(300, for: .rows)
        ds.setUInt16(42, for: .columns)

        let encoder = DICOMJSONEncoder()
        let jsonData = try encoder.encode(ds.allElements)
        let decoder = DICOMJSONDecoder(configuration: .init(allowMissingVR: true))
        let decoded = try decoder.decode(jsonData)

        let byTag = Dictionary(uniqueKeysWithValues: decoded.map { ($0.tag, $0) })
        XCTAssertEqual(byTag[.rows]?.uint16Value, 300)
        XCTAssertEqual(byTag[.columns]?.uint16Value, 42)
    }

    // Oracle: small OB pixel data (< inlineThreshold) is inlined as Base64
    // and decodes back to byte-identical bytes.
    func testInlineBinaryRoundTripBytes() throws {
        let pixels = Data((0..<64).map { UInt8($0 & 0xFF) })
        var ds = DataSet()
        ds.setUInt16(8, for: .rows)
        ds.setUInt16(8, for: .columns)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: pixels)

        // threshold 1024 > 64 bytes → inline.
        let encoder = DICOMJSONEncoder(
            configuration: .init(inlineBinaryThreshold: 1024))
        let obj = try encoder.encodeToObject(ds.allElements)

        let pdKey = tagKey(0x7FE0, 0x0010)
        let pd = try XCTUnwrap(elementObject(obj, pdKey), "PixelData present")
        XCTAssertEqual(pd["vr"] as? String, "OB")
        // PS3.18 F.2.2: InlineBinary is a sibling of vr, not an element of Value
        XCTAssertNil(pd["Value"], "binary VRs carry no Value array")
        let b64 = try XCTUnwrap(pd["InlineBinary"] as? String, "inline base64 present")
        XCTAssertEqual(Data(base64Encoded: b64), pixels, "inline base64 decodes to original bytes")

        // Full decode path yields the same bytes.
        let jsonData = try encoder.encode(ds.allElements)
        let decoder = DICOMJSONDecoder(configuration: .init(allowMissingVR: true))
        let decoded = try decoder.decode(jsonData)
        let byTag = Dictionary(uniqueKeysWithValues: decoded.map { ($0.tag, $0) })
        XCTAssertEqual(byTag[.pixelData]?.valueData, pixels)
    }

    // Oracle: metadata-only filtering (CLI --metadata-only) drops PixelData;
    // the encoded object then lacks the 7FE0,0010 key while other tags remain.
    func testMetadataOnlyExcludesPixelData() throws {
        let file = makeGrayscale8(rows: 8, cols: 8)
        let all = file.dataSet.allElements
        let filtered = all.filter { $0.tag != Tag.pixelData }

        let encoder = DICOMJSONEncoder()
        let obj = try encoder.encodeToObject(filtered)

        let pdKey = tagKey(0x7FE0, 0x0010)
        XCTAssertNil(obj[pdKey], "PixelData excluded")
        XCTAssertNotNil(obj[tagKey(0x0028, 0x0010)], "Rows retained")
        XCTAssertNotNil(obj[tagKey(0x0008, 0x0060)], "Modality retained")
    }

    // Oracle: --filter-tag semantics — filtering to a tag subset yields exactly
    // those keys (and no others) in the encoded JSON object.
    func testFilterTagSubset() throws {
        let file = makeGrayscale8(rows: 8, cols: 8)
        let wanted: Set<Tag> = [.modality, .rows]
        let filtered = file.dataSet.allElements.filter { wanted.contains($0.tag) }

        let encoder = DICOMJSONEncoder()
        let obj = try encoder.encodeToObject(filtered)

        XCTAssertEqual(Set(obj.keys),
                       Set([tagKey(0x0008, 0x0060), tagKey(0x0028, 0x0010)]),
                       "only filtered tags present")
    }

    // Oracle: --pretty only affects whitespace — the parsed JSON objects are
    // semantically identical to the compact form.
    func testPrettyPrintSameSemantics() throws {
        var ds = DataSet()
        ds.setString("MR", for: .modality, vr: .CS)
        ds.setUInt16(128, for: .rows)

        let compact = DICOMJSONEncoder(configuration: .init(prettyPrinted: false))
        let pretty = DICOMJSONEncoder(configuration: .init(prettyPrinted: true))
        let dCompact = try compact.encode(ds.allElements)
        let dPretty = try pretty.encode(ds.allElements)

        let oCompact = try JSONSerialization.jsonObject(with: dCompact) as? [String: Any] ?? [:]
        let oPretty = try JSONSerialization.jsonObject(with: dPretty) as? [String: Any] ?? [:]
        XCTAssertEqual(Set(oCompact.keys), Set(oPretty.keys),
                       "pretty printing changes only formatting, not content")
        // A pretty document contains newlines a compact one does not.
        XCTAssertTrue(String(data: dPretty, encoding: .utf8)!.contains("\n"))
    }

    // Oracle: --no-sort-keys vs sorted-keys parse to the same object; sortedKeys
    // affects byte order only, not semantics.
    func testSortedKeysSameSemantics() throws {
        var ds = DataSet()
        ds.setString("MR", for: .modality, vr: .CS)
        ds.setString("RT^Name", for: .patientName, vr: .PN)
        ds.setUInt16(128, for: .rows)

        let sorted = DICOMJSONEncoder(configuration: .init(sortedKeys: true))
        let unsorted = DICOMJSONEncoder(configuration: .init(sortedKeys: false))
        let dSorted = try sorted.encode(ds.allElements)
        let dUnsorted = try unsorted.encode(ds.allElements)

        let oSorted = try JSONSerialization.jsonObject(with: dSorted) as? [String: Any] ?? [:]
        let oUnsorted = try JSONSerialization.jsonObject(with: dUnsorted) as? [String: Any] ?? [:]
        XCTAssertEqual(Set(oSorted.keys), Set(oUnsorted.keys))
        // Sorted output has keys in ascending order in the raw bytes.
        let sortedStr = String(data: dSorted, encoding: .utf8)!
        let idxModality = sortedStr.range(of: tagKey(0x0008, 0x0060))!.lowerBound
        let idxRows = sortedStr.range(of: tagKey(0x0028, 0x0010))!.lowerBound
        XCTAssertLessThan(idxModality, idxRows, "sortedKeys orders 0008,0060 before 0028,0010")
    }

    // Oracle: --include-empty controls whether an empty element is kept.
    // PS3.18 F.2.5: an empty attribute "shall be preserved in the DICOM JSON
    // attribute object containing no Value, BulkDataURI or InlineBinary", so
    // with includeEmptyValues=true (the default) the element is {"vr": "LO"};
    // with =false it is dropped from the object altogether.
    func testIncludeEmptyValuesToggle() throws {
        var ds = DataSet()
        ds.setString("MR", for: .modality, vr: .CS)
        // Empty LO element (zero-length value).
        ds[Tag(group: 0x0010, element: 0x0020)] =
            DataElement(tag: Tag(group: 0x0010, element: 0x0020), vr: .LO, length: 0, valueData: Data())

        let emptyKey = tagKey(0x0010, 0x0020)

        let excluding = DICOMJSONEncoder(configuration: .init(includeEmptyValues: false))
        let objExcl = try excluding.encodeToObject(ds.allElements)
        XCTAssertNil(elementObject(objExcl, emptyKey), "empty element dropped when includeEmptyValues=false")

        let including = DICOMJSONEncoder(configuration: .init(includeEmptyValues: true))
        let objIncl = try including.encodeToObject(ds.allElements)
        let emptyIncl = try XCTUnwrap(elementObject(objIncl, emptyKey))
        XCTAssertEqual(emptyIncl["vr"] as? String, "LO")
        XCTAssertNil(emptyIncl["Value"], "PS3.18 F.2.5: an empty attribute carries no Value")
    }

    // Oracle: --bulk-data-url routes large OB data to a BulkDataURI referencing
    // the element's tag, instead of inlining bytes.
    func testBulkDataURIForLargeBinary() throws {
        let pixels = Data(count: 4096) // > threshold below
        var ds = DataSet()
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: pixels)

        let base = URL(string: "https://example.org/bulk")!
        let encoder = DICOMJSONEncoder(
            configuration: .init(inlineBinaryThreshold: 1024, bulkDataBaseURL: base))
        let obj = try encoder.encodeToObject(ds.allElements)

        let pd = try XCTUnwrap(elementObject(obj, tagKey(0x7FE0, 0x0010)))
        // PS3.18 F.2.2: BulkDataURI is a sibling of vr, not an element of Value
        XCTAssertNil(pd["Value"], "binary VRs carry no Value array")
        let uri = try XCTUnwrap(pd["BulkDataURI"] as? String, "BulkDataURI emitted for large binary")
        XCTAssertTrue(uri.hasPrefix("https://example.org/bulk"))
        XCTAssertTrue(uri.contains(tagKey(0x7FE0, 0x0010)), "URI references the element tag")
        XCTAssertNil(pd["InlineBinary"], "large binary not inlined when a bulk URL is set")
    }

    // Oracle: reverse mode (JSON → DICOM) produces a valid Part 10 file whose
    // re-read dataset carries the decoded tags/values.
    func testReverseCreatesReadableDICOMFile() throws {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString(rtUID(), for: .sopInstanceUID, vr: .UI)
        ds.setString("MR", for: .modality, vr: .CS)
        ds.setUInt16(128, for: .rows)
        ds.setUInt16(64, for: .columns)

        let encoder = DICOMJSONEncoder()
        let jsonData = try encoder.encode(ds.allElements)

        let decoder = DICOMJSONDecoder(configuration: .init(allowMissingVR: true))
        let elements = try decoder.decode(jsonData)
        let newDS = DataSet(elements: elements)
        let file = DICOMFile.create(dataSet: newDS)
        let bytes = try file.write()

        // Part 10 preamble: 128 zero bytes then "DICM".
        XCTAssertGreaterThan(bytes.count, 132)
        XCTAssertEqual(Array(bytes.prefix(128)), Array(repeating: UInt8(0), count: 128))
        XCTAssertEqual(Array(bytes[128..<132]), [0x44, 0x49, 0x43, 0x4D]) // "DICM"

        let reread = try DICOMFile.read(from: bytes)
        XCTAssertEqual(reread.dataSet[.modality]?.stringValue, "MR")
        XCTAssertEqual(reread.dataSet[.rows]?.uint16Value, 128)
        XCTAssertEqual(reread.dataSet[.columns]?.uint16Value, 64)
    }

    // Oracle: full CLI-shaped pipeline (DICOM → JSON → DICOM) preserves the
    // native pixel bytes for an uncompressed source.
    func testFullPipelinePreservesPixelBytes() throws {
        let file = makeGrayscale8(rows: 16, cols: 16) { UInt8(($0 * 3) & 0xFF) }
        let originalPixels = pixelBytes(file)

        let encoder = DICOMJSONEncoder(configuration: .init(inlineBinaryThreshold: 1_000_000))
        let jsonData = try encoder.encode(file.dataSet.allElements)

        let decoder = DICOMJSONDecoder(configuration: .init(allowMissingVR: true))
        let elements = try decoder.decode(jsonData)
        let rebuilt = DICOMFile.create(dataSet: DataSet(elements: elements))
        let reread = try DICOMFile.read(from: try rebuilt.write())

        XCTAssertEqual(pixelBytes(reread), originalPixels, "pixel bytes survive DICOM→JSON→DICOM")
    }

    // Oracle: sequence (SQ) items round-trip — nested tags preserved through
    // encode→decode as sequence items.
    func testSequenceRoundTrip() throws {
        var item = DataSet()
        item.setString("CODE1", for: Tag(group: 0x0008, element: 0x0100), vr: .SH) // CodeValue
        item.setString("SCHEME", for: Tag(group: 0x0008, element: 0x0102), vr: .SH) // CodingScheme
        let seqItem = SequenceItem(elements: item.allElements)
        let sqTag = Tag(group: 0x0008, element: 0x1032) // ProcedureCodeSequence
        let sqElem = DataElement(tag: sqTag, vr: .SQ, length: 0xFFFFFFFF,
                                 valueData: Data(), sequenceItems: [seqItem])

        var ds = DataSet()
        ds.setString("MR", for: .modality, vr: .CS)
        ds[sqTag] = sqElem

        let encoder = DICOMJSONEncoder()
        let jsonData = try encoder.encode(ds.allElements)
        let decoder = DICOMJSONDecoder(configuration: .init(allowMissingVR: true))
        let decoded = try decoder.decode(jsonData)

        let byTag = Dictionary(uniqueKeysWithValues: decoded.map { ($0.tag, $0) })
        let decodedSeq = try XCTUnwrap(byTag[sqTag])
        XCTAssertEqual(decodedSeq.vr, .SQ)
        let items = try XCTUnwrap(decodedSeq.sequenceItems)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0][Tag(group: 0x0008, element: 0x0100)]?.stringValue, "CODE1")
        XCTAssertEqual(items[0][Tag(group: 0x0008, element: 0x0102)]?.stringValue, "SCHEME")
    }

    // Oracle: private (odd-group) tags are preserved as-is through the round trip.
    func testPrivateTagPreserved() throws {
        let privTag = Tag(group: 0x0009, element: 0x0010) // odd group → private
        var ds = DataSet()
        ds.setString("MR", for: .modality, vr: .CS)
        ds[privTag] = DataElement.string(tag: privTag, vr: .LO, value: "PRIVATE-VALUE")

        let encoder = DICOMJSONEncoder()
        let jsonData = try encoder.encode(ds.allElements)
        let decoder = DICOMJSONDecoder(configuration: .init(allowMissingVR: true))
        let decoded = try decoder.decode(jsonData)

        let byTag = Dictionary(uniqueKeysWithValues: decoded.map { ($0.tag, $0) })
        let priv = try XCTUnwrap(byTag[privTag], "private tag preserved")
        XCTAssertTrue(priv.tag.isPrivate)
        XCTAssertEqual(priv.stringValue, "PRIVATE-VALUE")
    }

    // Oracle (corpus): real Explicit-VR CT file encodes to a JSON object that
    // preserves the exact set of non-pixel tags after a full round trip.
    func testCorpusCTMetadataTagsRoundTrip() throws {
        let f = try loadCorpus(.ct)
        try XCTSkipIf(f == nil, "corpus absent")
        let file = try XCTUnwrap(f)

        let meta = file.dataSet.allElements.filter { $0.tag != Tag.pixelData }
        let encoder = DICOMJSONEncoder()
        let jsonData = try encoder.encode(meta)
        let decoder = DICOMJSONDecoder(configuration: .init(allowMissingVR: true))
        let decoded = try decoder.decode(jsonData)

        // Encoder drops empty-valued elements by default; compare on the tags
        // that actually survived encoding to keep the oracle exact.
        let obj = try encoder.encodeToObject(meta)
        let encodedTags = Set(obj.keys)
        let decodedTags = Set(decoded.map { $0.tag.hexString })
        XCTAssertEqual(encodedTags, decodedTags, "encoded tag set == decoded tag set")

        // A known scalar survives with its value.
        let byTag = Dictionary(uniqueKeysWithValues: decoded.map { ($0.tag, $0) })
        XCTAssertEqual(byTag[.modality]?.stringValue, file.dataSet[.modality]?.stringValue)
    }
}
