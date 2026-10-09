import XCTest
import DICOMCore
import DICOMDictionary
@testable import DICOMKit

/// The shared engines behind dicom-dump, dicom-info, dicom-tags and dicom-diff, pinned to
/// the 2026a text (D144-D150, D152, D153).
final class ToolEngineStandardTests: XCTestCase {

    // MARK: - Byte builders (Explicit VR Little Endian)

    private func u16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private func u32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }
    private func short(_ g: UInt16, _ e: UInt16, _ vr: String, _ value: [UInt8]) -> [UInt8] {
        u16(g) + u16(e) + Array(vr.utf8) + u16(UInt16(value.count)) + value
    }
    private func long(_ g: UInt16, _ e: UInt16, _ vr: String, length: UInt32) -> [UInt8] {
        u16(g) + u16(e) + Array(vr.utf8) + [0, 0] + u32(length)
    }
    private func item(_ e: UInt16, length: UInt32) -> [UInt8] { u16(0xFFFE) + u16(e) + u32(length) }

    /// Preamble + "DICM" + (0002,0010), then a data set with a Private Creator, a
    /// defined-length SQ / Item, an undefined-length SQ / Item with delimiters, and
    /// Patient's Name. Offsets: (0002,0010) 132, (0008,0060) 160, (0009,0010) 170,
    /// SQ 186, Item 198, (0040,0007) 206, SQ 216, Item 228, (0008,1150) 236,
    /// Item Delimitation 248, Sequence Delimitation 256, (0010,0010) 264.
    private func sampleFile(preamble: Bool = true) -> Data {
        var b: [UInt8] = preamble ? Array(repeating: 0, count: 128) + Array("DICM".utf8) : []
        b += short(0x0002, 0x0010, "UI", Array("1.2.840.10008.1.2.1".utf8) + [0])
        b += short(0x0008, 0x0060, "CS", Array("CT".utf8))
        b += short(0x0009, 0x0010, "LO", Array("ACME 1.0".utf8))
        let inner = short(0x0040, 0x0007, "LO", Array("XY".utf8))
        b += long(0x0040, 0x0275, "SQ", length: UInt32(8 + inner.count)) + item(0xE000, length: UInt32(inner.count)) + inner
        b += long(0x0008, 0x1140, "SQ", length: 0xFFFF_FFFF) + item(0xE000, length: 0xFFFF_FFFF)
        b += short(0x0008, 0x1150, "UI", Array("1.2".utf8) + [0])
        b += item(0xE00D, length: 0) + item(0xE0DD, length: 0)
        b += short(0x0010, 0x0010, "PN", Array("DOE^JO".utf8))
        return Data(b)
    }

    private func dumper(verbose: Bool = false) -> HexDumper {
        HexDumper(bytesPerLine: 16, useColor: false, annotate: true, verbose: verbose)
    }

    // MARK: - HexDumper (D144, D145, D146)

    /// PS3.6 2026a Table 6-1: (FFFE,E000) Item, (FFFE,E00D) ItemDelimitationItem,
    /// (FFFE,E0DD) SequenceDelimitationItem — annotated, with no VR (PS3.5 7.5); the
    /// elements of a defined-length Item are annotated too.
    func testItemsAndDelimitersAreAnnotated() {
        let out = dumper(verbose: true).dump(data: sampleFile(), startOffset: 0, dicomFile: nil, highlightTag: nil)
        XCTAssertTrue(out.contains("(FFFE,E000) Len=10 Item"), out)
        XCTAssertTrue(out.contains("(FFFE,E00D) Len=0 ItemDelimitationItem"))
        XCTAssertTrue(out.contains("(FFFE,E0DD) Len=0 SequenceDelimitationItem"))
        XCTAssertTrue(out.contains("(0040,0007) VR=LO Len=2 ScheduledProcedureStepDescription"),
                      "an element inside a defined-length Item")
        XCTAssertTrue(out.contains("(0008,1150) VR=UI Len=4 ReferencedSOPClassUID"))
        XCTAssertTrue(out.contains("(0010,0010) VR=PN Len=6 PatientName"))
    }

    /// PS3.5 7.8.1: (gggg,0010-00FF), gggg odd, is a Private Creator Data Element.
    func testPrivateCreatorIsNamed() throws {
        XCTAssertTrue(dumper().dump(data: sampleFile(), startOffset: 0, dicomFile: nil, highlightTag: nil)
            .contains("(0009,0010) Private Creator"))
        var ds = DataSet()
        ds.setString("ACME 1.0", for: Tag(group: 0x0009, element: 0x0010), vr: .LO)
        let file = DICOMFile(fileMetaInformation: DataSet(), dataSet: ds)
        XCTAssertTrue(try XCTUnwrap(HexDumper.tagDump(tag: Tag(group: 0x0009, element: 0x0010), in: file, useColor: false))
            .hasPrefix("Tag: (0009,0010)  Private Creator  VR=LO"))
        XCTAssertEqual(AttributeNames.name(for: Tag(group: 0x0009, element: 0x1001)), nil, "a private data element is not a creator")
    }

    /// PS3.10 7.1: the walk skips 132 bytes only when "DICM" is at 128-131.
    func testFileWithoutPreambleIsAnnotatedFromByteZero() {
        let out = dumper().dump(data: sampleFile(preamble: false), startOffset: 0, dicomFile: nil, highlightTag: nil)
        let first = out.split(separator: "\n").first.map(String.init) ?? ""
        XCTAssertTrue(first.hasPrefix("00000000") && first.contains("(0002,0010) TransferSyntaxUID"), first)
        XCTAssertTrue(out.contains("(0010,0010) PatientName"))
    }

    /// With an offset, annotations and the highlight come from the whole file (D144).
    func testOffsetKeepsAnnotationsOnTheirBytes() {
        let file = sampleFile()
        let out = dumper().dump(fileData: file, startOffset: 200, length: nil, dicomFile: nil, highlightTag: .patientName)
        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 5)
        XCTAssertTrue(lines[0].hasPrefix("000000C8"), lines[0])
        XCTAssertTrue(lines[0].contains("(0040,0007) ScheduledProcedureStepDescription"), "element at 206 is on the line 200-215")
        XCTAssertTrue(lines[1].contains("(0008,1140) ReferencedImageSequence") && lines[1].contains("(FFFE,E000) Item"), lines[1])
        XCTAssertTrue(lines[2].contains("(0008,1150) ReferencedSOPClassUID"), lines[2])
        XCTAssertTrue(lines[4].contains("◀ HIGHLIGHT (0010,0010) PatientName"), lines[4])
        // An element that begins before the dumped range is still highlighted, on line 1.
        let sq = dumper().dump(fileData: file, startOffset: 200, length: 16, dicomFile: nil,
                               highlightTag: Tag(group: 0x0040, element: 0x0275))
        XCTAssertTrue(sq.contains("◀ HIGHLIGHT (0040,0275) RequestAttributesSequence"), sq)
    }

    /// Fragments of encapsulated Pixel Data are Items holding bytes, not elements (PS3.5 A.4).
    func testEncapsulatedFragmentsAreNotDescended() {
        var b: [UInt8] = []
        b += short(0x0008, 0x0060, "CS", Array("CT".utf8))
        b += long(0x7FE0, 0x0010, "OB", length: 0xFFFF_FFFF)
        b += item(0xE000, length: 0)
        let fragment = short(0x0008, 0x0060, "CS", Array("AB".utf8))  // looks like an element
        b += item(0xE000, length: UInt32(fragment.count)) + fragment
        b += item(0xE0DD, length: 0)
        let out = dumper().dump(data: Data(b), startOffset: 0, dicomFile: nil, highlightTag: nil)
        XCTAssertEqual(out.components(separatedBy: "(0008,0060)").count - 1, 1, out)
        XCTAssertEqual(out.components(separatedBy: "(FFFE,E000) Item").count - 1, 2)
        XCTAssertTrue(out.contains("(FFFE,E0DD) SequenceDelimitationItem"))
    }

    // MARK: - MetadataPresenter (D146, D147, D148, D149)

    private func presenterFile() -> DICOMFile {
        var meta = DataSet()
        meta.setString("1.2.840.10008.1.2.1", for: .transferSyntaxUID, vr: .UI)
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setString("DOE^JOHN", for: .patientName, vr: .PN)
        ds[.rows] = .uint16s(tag: .rows, values: [512])
        ds.setString("ACME 1.0", for: Tag(group: 0x0009, element: 0x0010), vr: .LO)
        return DICOMFile(fileMetaInformation: meta, dataSet: ds)
    }

    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.1 "Explicit VR Little Endian",
    /// 1.2.840.10008.5.1.4.1.1.2 "CT Image Storage".
    func testStatisticsNameTheUIDs() throws {
        let text = try MetadataPresenter(file: presenterFile(), showStats: true).render(format: .text)
        XCTAssertTrue(text.contains("Transfer Syntax: 1.2.840.10008.1.2.1 (Explicit VR Little Endian)\n"), text)
        XCTAssertTrue(text.contains("SOP Class: 1.2.840.10008.5.1.4.1.1.2 (CT Image Storage)\n"))
        let json = try MetadataPresenter(file: presenterFile(), showStats: true).render(format: .json)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let stats = try XCTUnwrap(object["statistics"] as? [String: String])
        XCTAssertEqual(stats["transferSyntax"], "1.2.840.10008.1.2.1")
        XCTAssertEqual(stats["transferSyntaxName"], "Explicit VR Little Endian")
        XCTAssertEqual(stats["sopClassName"], "CT Image Storage")
    }

    func testFilterMatchesKeywordsExactly() throws {
        let csv = try MetadataPresenter(file: presenterFile(), filterTags: ["PatientName", "Rows"]).render(format: .csv)
        XCTAssertEqual(csv, """
            Tag,Name,VR,Value
            "(0010,0010)","Patient's Name","PN","DOE^JOHN"
            "(0028,0010)","Rows","US","512"

            """)
        let none = try MetadataPresenter(file: presenterFile(), filterTags: ["patientname"]).render(format: .csv)
        XCTAssertEqual(none, "Tag,Name,VR,Value\n")
    }

    func testJSONCarriesBinaryValuesAndPrivateCreatorName() throws {
        let json = try MetadataPresenter(file: presenterFile(), includePrivate: true).render(format: .json)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let elements = try XCTUnwrap(object["dataSet"] as? [[String: Any]])
        let rows = try XCTUnwrap(elements.first { $0["tag"] as? String == "(0028,0010)" })
        XCTAssertEqual(rows["value"] as? String, "512", "US value as in the text and CSV output")
        let creator = try XCTUnwrap(elements.first { $0["tag"] as? String == "(0009,0010)" })
        XCTAssertEqual(creator["name"] as? String, "Private Creator")
    }

    // MARK: - TagEditor (D150, D146)

    /// The engine path the Workshop uses: refused changes are skipped with a note, the
    /// others applied with the PS3.6 VR (US is binary) — PS3.5 Table 6.2-1, PS3.10 7.1.
    func testApplyChangesUsesTheRules() {
        var ds = DataSet()
        ds.setString("ACME", for: Tag(group: 0x0009, element: 0x0010), vr: .LO)
        let lines = TagEditor().applyChanges(
            to: &ds, sets: ["Rows=512", "StudyDate=2020-01-01", "TransferSyntaxUID=1.2"],
            deletes: ["0009,0010"], deletePrivate: false, sourceDataSet: nil, copyTags: [],
            verbose: false, dryRun: false)
        XCTAssertEqual(lines[0], "DELETE (0009,0010) Private Creator")
        XCTAssertEqual(lines[1], "SET (0028,0010) Rows = 512")
        XCTAssertTrue(lines[2].hasPrefix("SET (0008,0020) Study Date (refused: --set (0008,0020): "), lines[2])
        XCTAssertTrue(lines[3].hasPrefix("SET (0002,0010) Transfer Syntax UID (refused: "), lines[3])
        XCTAssertEqual(ds[.rows]?.vr, .US)
        XCTAssertEqual(ds[.rows].map { Array($0.valueData) }, [0x00, 0x02])
        XCTAssertNil(ds[Tag(group: 0x0008, element: 0x0020)])
        XCTAssertNil(ds[.transferSyntaxUID])
    }

    func testApplyCheckedChangesRefusesTheWholeEdit() {
        var ds = DataSet()
        ds.setString("DOE", for: .patientName, vr: .PN)
        XCTAssertThrowsError(try TagEditor().applyCheckedChanges(
            to: &ds, sets: ["PatientID=1", "Rows=70000"], deletes: ["PatientName"], deletePrivate: false,
            sourceDataSet: nil, copyTags: [], verbose: false, dryRun: false))
        XCTAssertEqual(ds.string(for: .patientName), "DOE", "nothing applied")
        XCTAssertNil(ds[.patientID])
    }

    // MARK: - DICOMComparer (D152, D153)

    private func file(_ ds: DataSet) -> DICOMFile { DICOMFile(fileMetaInformation: DataSet(), dataSet: ds) }

    private func compare(_ a: DataSet, _ b: DataSet, ignorePrivate: Bool = false,
                         pixels: Bool = false, tolerance: Double = 0) throws -> DICOMKit.ComparisonResult {
        try DICOMComparer(file1: file(a), file2: file(b), tagsToIgnore: [], ignorePrivate: ignorePrivate,
                          comparePixels: pixels, pixelTolerance: tolerance, showIdentical: false).compare()
    }

    /// PS3.5 7.8: --ignore-private skips Private Data Elements inside Items too.
    func testIgnorePrivateInsideSequenceItems() throws {
        func dataSet(_ privateValue: String) -> DataSet {
            var item = DataSet()
            item.setString("1.2.3", for: Tag(group: 0x0008, element: 0x1150), vr: .UI)
            item.setString("ACME", for: Tag(group: 0x0009, element: 0x0010), vr: .LO)
            item.setString(privateValue, for: Tag(group: 0x0009, element: 0x1001), vr: .LO)
            var ds = DataSet()
            ds.setSequence([SequenceItem(elements: item.tags.compactMap { item[$0] })],
                           for: Tag(group: 0x0008, element: 0x1140))
            return ds
        }
        XCTAssertEqual(try compare(dataSet("A"), dataSet("B"), ignorePrivate: true).differenceCount, 0)
        XCTAssertEqual(try compare(dataSet("A"), dataSet("B"), ignorePrivate: false).differenceCount, 1)
    }

    /// The dicom-diff report names a Private Creator too (PS3.5 7.8.1, D146).
    func testComparisonReportNamesPrivateCreator() throws {
        var a = DataSet(), b = DataSet()
        a.setString("ACME 1.0", for: Tag(group: 0x0009, element: 0x0010), vr: .LO)
        b.setString("ACME 2.0", for: Tag(group: 0x0009, element: 0x0010), vr: .LO)
        let text = try ComparisonReport(result: compare(a, b), file1Name: "a", file2Name: "b", showIdentical: false)
            .render(format: .text)
        XCTAssertTrue(text.contains("[(0009,0010)] Private Creator\n"), text)
    }

    private func image(_ values: [UInt16], bitsStored: UInt16 = 16, signed: Bool = false,
                       samples: UInt16 = 1, planar: UInt16 = 0, columns: UInt16? = nil) -> DataSet {
        var ds = DataSet()
        let pixels = values.count / Int(samples)
        ds[.rows] = .uint16s(tag: .rows, values: [1])
        ds[.columns] = .uint16s(tag: .columns, values: [columns ?? UInt16(pixels)])
        ds[.bitsAllocated] = .uint16s(tag: .bitsAllocated, values: [16])
        ds[.bitsStored] = .uint16s(tag: .bitsStored, values: [bitsStored])
        ds[.highBit] = .uint16s(tag: .highBit, values: [bitsStored - 1])
        ds[.pixelRepresentation] = .uint16s(tag: .pixelRepresentation, values: [signed ? 1 : 0])
        ds[.samplesPerPixel] = .uint16s(tag: .samplesPerPixel, values: [samples])
        if samples > 1 { ds[.planarConfiguration] = .uint16s(tag: .planarConfiguration, values: [planar]) }
        ds.setString(samples > 1 ? "RGB" : "MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds[.pixelData] = .data(tag: .pixelData, vr: .OW, data: Data(values.flatMap(u16)))
        return ds
    }

    /// PS3.5 8.1.1: 16-bit Pixel Cells. 256 vs 255 differ by 1, not by 255 (the byte view).
    func testPixelDifferenceIsPerSample() throws {
        let r = try compare(image([256, 10]), image([255, 10]), pixels: true, tolerance: 1)
        let diff = try XCTUnwrap(r.pixelDifference)
        XCTAssertEqual(diff.maxDifference, 1)
        XCTAssertEqual(diff.meanDifference, 1)
        XCTAssertEqual(diff.differentPixelCount, 1)
        XCTAssertEqual(diff.totalPixels, 2)
        XCTAssertFalse(r.pixelsDifferent, "within --tolerance 1")
    }

    /// Signed values (Pixel Representation 1) and Bits Stored masking (PS3.5 8.1.1).
    func testSignedAndBitsStored() throws {
        // 0xFFFF as a signed 16-bit sample is -1; vs 1 → 2.
        XCTAssertEqual(try compare(image([0xFFFF]), image([1]), pixels: true).pixelDifference?.maxDifference, 65534)
        XCTAssertEqual(try compare(image([0xFFFF], signed: true), image([1], signed: true), pixels: true)
            .pixelDifference?.maxDifference, 2)
        // Bits Stored 12: bits above the High Bit are not part of the sample.
        XCTAssertEqual(try compare(image([0xF005], bitsStored: 12), image([0x0005], bitsStored: 12), pixels: true)
            .pixelDifference?.maxDifference, 0)
    }

    /// Planar Configuration 0 vs 1 holding the same RGB pixels are identical (PS3.3 C.7.6.3.1.3).
    func testPlanarConfigurationIsNormalised() throws {
        let byPixel = image([1, 2, 3, 4, 5, 6], samples: 3, planar: 0)
        let byPlane = image([1, 4, 2, 5, 3, 6], samples: 3, planar: 1)
        let r = try compare(byPixel, byPlane, pixels: true)
        XCTAssertEqual(r.pixelDifference?.maxDifference, 0)
        XCTAssertEqual(r.pixelDifference?.totalPixels, 2)
        XCTAssertFalse(r.pixelsDifferent)
    }
}
