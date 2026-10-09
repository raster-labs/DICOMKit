import XCTest
import DICOMCore
import DICOMKit
@testable import dicom_tags

/// Pins dicom-tags edits (run by DICOMKit's TagEditor / TagEditRules since D150) to the 2026a text: PS3.5 Table 6.2-1 (VR length, repertoire and
/// range limits), PS3.10 7.1 (group 0002 only in the File Meta Information), PS3.5 7.5
/// (Item / delimiters) and 7.8.1 (unused groups, Private Creator), and PS3.6 keywords.
final class TagEditRulesTests: XCTestCase {

    // "Length of Value" column of PS3.5 2026a Table 6.2-1 (dumped by Scripts/nema_docbook.py).
    func testLengthLimitsAreTable621() {
        let expected: [VR: (Int, TagEditRules.LengthUnit, Bool)] = [
            .AE: (16, .bytes, false), .AS: (4, .bytes, true), .CS: (16, .bytes, false),
            .DA: (8, .bytes, true), .DS: (16, .bytes, false), .DT: (26, .bytes, false),
            .IS: (12, .bytes, false), .LO: (64, .chars, false), .LT: (10240, .chars, false),
            .PN: (64, .chars, false), .SH: (16, .chars, false), .ST: (1024, .chars, false),
            .TM: (14, .bytes, false), .UI: (64, .bytes, false),
        ]
        XCTAssertEqual(Set(TagEditRules.lengthLimits.keys), Set(expected.keys))
        for (vr, limit) in expected {
            let got = TagEditRules.lengthLimits[vr]!
            XCTAssertEqual(got.max, limit.0, vr.rawValue)
            XCTAssertEqual(got.unit, limit.1, vr.rawValue)
            XCTAssertEqual(got.fixed, limit.2, vr.rawValue)
        }
    }

    func testRepertoiresAreTable621() {
        XCTAssertEqual(TagEditRules.repertoires[.DA], Set("0123456789"))
        XCTAssertEqual(TagEditRules.repertoires[.UI], Set("0123456789."))
        XCTAssertEqual(TagEditRules.repertoires[.AS], Set("0123456789DWMY"))
        XCTAssertEqual(TagEditRules.repertoires[.IS], Set("0123456789+- "))
        XCTAssertEqual(TagEditRules.repertoires[.DS], Set("0123456789+-Ee. "))
        XCTAssertEqual(TagEditRules.repertoires[.DT], Set("0123456789+-. "))
        XCTAssertEqual(TagEditRules.repertoires[.TM], Set("0123456789. "))
        XCTAssertEqual(TagEditRules.repertoires[.CS], Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ _"))
    }

    func testValuesWithinTheLimitsAreAccepted() {
        XCTAssertNil(TagEditRules.valueProblem("20200101", vr: .DA))
        XCTAssertNil(TagEditRules.valueProblem("ORIGINAL\\PRIMARY", vr: .CS))
        XCTAssertNil(TagEditRules.valueProblem(String(repeating: "A", count: 64), vr: .LO))
        XCTAssertNil(TagEditRules.valueProblem("Doe^John^^Dr^PhD=A^B=C^D", vr: .PN))
        XCTAssertNil(TagEditRules.valueProblem("120000.123456", vr: .TM))
        XCTAssertNil(TagEditRules.valueProblem("018M", vr: .AS))
        XCTAssertNil(TagEditRules.valueProblem("a\\b", vr: .LT), "LT is single-valued; a backslash is text")
        XCTAssertNil(TagEditRules.valueProblem("", vr: .DA), "zero-length Value")
        XCTAssertNil(TagEditRules.valueProblem("512", vr: .US))
        XCTAssertNil(TagEditRules.valueProblem("-1\\2", vr: .SS))
        XCTAssertNil(TagEditRules.valueProblem("0.5", vr: .FD))
    }

    func testValuesOutsideTheLimitsAreRefused() {
        XCTAssertNotNil(TagEditRules.valueProblem("2020-01-01", vr: .DA))
        XCTAssertNotNil(TagEditRules.valueProblem("2020011", vr: .DA), "8 bytes fixed")
        XCTAssertNotNil(TagEditRules.valueProblem("ct", vr: .CS))
        XCTAssertNotNil(TagEditRules.valueProblem(String(repeating: "A", count: 17), vr: .CS))
        XCTAssertNotNil(TagEditRules.valueProblem(String(repeating: "A", count: 65), vr: .LO))
        XCTAssertNotNil(TagEditRules.valueProblem(String(repeating: "A", count: 65), vr: .PN))
        XCTAssertNotNil(TagEditRules.valueProblem("A=B=C=D", vr: .PN), "three component groups")
        XCTAssertNotNil(TagEditRules.valueProblem("A^B^C^D^E^F", vr: .PN), "five components")
        XCTAssertNotNil(TagEditRules.valueProblem("1.2.3a", vr: .UI))
        XCTAssertNotNil(TagEditRules.valueProblem(String(repeating: "1", count: 65), vr: .UI))
        XCTAssertNotNil(TagEditRules.valueProblem("2147483648", vr: .IS))
        XCTAssertNotNil(TagEditRules.valueProblem("    ", vr: .AE))
        XCTAssertNotNil(TagEditRules.valueProblem("a\u{07}b", vr: .LO))
        XCTAssertNotNil(TagEditRules.valueProblem("65536", vr: .US))
        XCTAssertNotNil(TagEditRules.valueProblem("-1", vr: .UL))
        XCTAssertNotNil(TagEditRules.valueProblem("x", vr: .FL))
        for vr: VR in [.AT, .OB, .OD, .OF, .OL, .OV, .OW, .SQ, .SV, .UN, .UV] {
            XCTAssertNotNil(TagEditRules.valueProblem("1", vr: vr), vr.rawValue)
        }
    }

    // PS3.10 2026a 7.1, PS3.5 2026a 7.5 and 7.8.1.
    func testDataSetRefusals() {
        XCTAssertNotNil(TagEditRules.dataSetRefusal(for: Tag(group: 0x0002, element: 0x0010)))
        XCTAssertNotNil(TagEditRules.dataSetRefusal(for: Tag(group: 0xFFFE, element: 0xE000)))
        XCTAssertNotNil(TagEditRules.dataSetRefusal(for: Tag(group: 0x0001, element: 0x0010)))
        XCTAssertNotNil(TagEditRules.dataSetRefusal(for: Tag(group: 0xFFFF, element: 0x0010)))
        XCTAssertNil(TagEditRules.dataSetRefusal(for: Tag(group: 0x0010, element: 0x0010)))
        XCTAssertNil(TagEditRules.dataSetRefusal(for: Tag(group: 0x0009, element: 0x0010)))
    }

    private func checked(deletes: [String] = [], copyTags: [String] = [], sets: [String] = [],
                         source: DataSet? = nil, dryRun: Bool = false,
                         into ds: inout DataSet) throws -> [String] {
        try TagEditor().applyCheckedChanges(to: &ds, sets: sets, deletes: deletes, deletePrivate: false,
                                            sourceDataSet: source ?? (copyTags.isEmpty ? nil : DataSet()),
                                            copyTags: copyTags, verbose: false, dryRun: dryRun)
    }

    func testGroup0002EditsAreRefusedByKeywordAndByTag() {
        var ds = DataSet()
        XCTAssertThrowsError(try checked(sets: ["TransferSyntaxUID=1.2.840.10008.1.2"], into: &ds))
        XCTAssertThrowsError(try checked(deletes: ["0002,0013"], into: &ds))
        XCTAssertThrowsError(try checked(copyTags: ["MediaStorageSOPInstanceUID"], into: &ds))
        XCTAssertNoThrow(try checked(deletes: ["PatientName"], copyTags: ["PatientID"], sets: ["StudyDate=20200101"], into: &ds))
    }

    // PS3.6 dictionary VR; Private Creator is LO (PS3.5 7.8.1).
    func testWriteVR() {
        XCTAssertEqual(TagEditRules.writeVR(for: Tag(group: 0x0028, element: 0x0010), existing: nil), .US)
        XCTAssertEqual(TagEditRules.writeVR(for: Tag(group: 0x0008, element: 0x0020), existing: .UN), .DA)
        XCTAssertEqual(TagEditRules.writeVR(for: Tag(group: 0x0008, element: 0x0020), existing: .LO), .DA)
        XCTAssertEqual(TagEditRules.writeVR(for: Tag(group: 0x0009, element: 0x0010), existing: .UN), .LO)
        XCTAssertEqual(TagEditRules.writeVR(for: Tag(group: 0x0009, element: 0x1001), existing: .DS), .DS)
        XCTAssertEqual(TagEditRules.writeVR(for: Tag(group: 0x0009, element: 0x1001), existing: nil), .LO)
    }

    func testSetWritesBinaryUSForRows() throws {
        var ds = DataSet()
        let lines = try checked(sets: ["Rows=512"], into: &ds)
        XCTAssertEqual(lines, ["SET (0028,0010) Rows = 512"])
        let rows = try XCTUnwrap(ds[Tag(group: 0x0028, element: 0x0010)])
        XCTAssertEqual(rows.vr, .US)
        XCTAssertEqual(Array(rows.valueData), [0x00, 0x02])
    }

    func testSetKeepsOrderAndSkipLinesAndHonoursDryRun() throws {
        var ds = DataSet()
        let lines = try checked(sets: ["Foo=1", "bad", "PatientName=DOE^JOHN"], dryRun: true, into: &ds)
        XCTAssertEqual(lines, [
            "SET Foo (unknown tag, skipped)",
            "SET bad (invalid format, expected TagName=Value)",
            "SET (0010,0010) Patient's Name = DOE^JOHN",
        ])
        XCTAssertNil(ds[Tag(group: 0x0010, element: 0x0010)])
    }

    func testRefusedSetLeavesTheDataSetUntouched() {
        var ds = DataSet()
        XCTAssertThrowsError(try checked(deletes: ["PatientID"], sets: ["PatientName=DOE", "StudyDate=2020-01-01"], into: &ds))
        XCTAssertNil(ds[Tag(group: 0x0010, element: 0x0010)])
    }

    // PS3.5 7.8.1: Private Creator is LO, VM 1, Default Character Repertoire.
    func testPrivateCreatorValues() {
        let creator = Tag(group: 0x0009, element: 0x0010)
        XCTAssertNoThrow(try TagEditRules.element(tag: creator, vr: .LO, text: "ACME 1.0").get())
        XCTAssertThrowsError(try TagEditRules.element(tag: creator, vr: .LO, text: "A\\B").get())
        XCTAssertThrowsError(try TagEditRules.element(tag: creator, vr: .LO, text: "ÄCME").get())
    }

    func testKeywordsAreExactPS36Keywords() {
        let editor = TagEditor()
        XCTAssertEqual(editor.parseTagSpecifier("PatientName"), Tag(group: 0x0010, element: 0x0010))
        XCTAssertNil(editor.parseTagSpecifier("patientname"))
        XCTAssertEqual(editor.parseTagSpecifier("(0010,0010)"), Tag(group: 0x0010, element: 0x0010))
    }

    func testHelpNamesKeywords() {
        let help = DICOMTags.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(help.contains("Keyword=Value or GGGG,EEEE=Value"))
        XCTAssertTrue(help.contains("PS3.5 Table 6.2-1"))
    }
}
