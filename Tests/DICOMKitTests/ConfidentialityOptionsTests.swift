import XCTest
import Foundation
import DICOMCore
import DICOMDictionary
@testable import DICOMKit

/// PS3.15 2026a Annex E options and recording rows closed 2026-10-01: Clean Descriptors
/// (E.3.5, D158), Modified Dates (E.3.6, D157), (0028,0303) (E.2 / E.3.6, D161), Retain
/// Safe Private (E.3.10) and Clean Graphics (E.3.3) (D159), and the legacy Anonymizer's
/// keyword parsing (D163) and --keep (D164).
final class ConfidentialityOptionsTests: XCTestCase {

    private let studyDescription = Tag(group: 0x0008, element: 0x1030)
    private let studyComments = Tag(group: 0x0032, element: 0x4000)
    private let temporalModified = Tag(group: 0x0028, element: 0x0303)

    private func dataSet() -> DataSet {
        var ds = DataSet()
        ds.setString("DOE^JOHN", for: .patientName, vr: .PN)
        ds.setString("MRN12345", for: .patientID, vr: .LO)
        ds.setString("19800101", for: .patientBirthDate, vr: .DA)
        ds.setString("General Hospital", for: .institutionName, vr: .LO)
        ds.setString("CT chest - Dr. Smith", for: studyDescription, vr: .LO)
        ds.setString("Seen 1980-01-01, John Doe (MRN12345) at General Hospital; MR follow-up", for: studyComments, vr: .LT)
        ds.setString("20240102", for: .studyDate, vr: .DA)
        ds.setString("101500", for: .studyTime, vr: .TM)
        ds.setString("20240102101500.5+0100", for: Tag(group: 0x0008, element: 0x002A), vr: .DT)  // Acquisition DateTime
        ds.setString("+0100", for: Tag(group: 0x0008, element: 0x0201), vr: .SH)  // Timezone Offset From UTC
        return ds
    }

    // MARK: - D158 Clean Descriptors

    /// E.3.5: identifying information embedded in descriptors is removed, not kept verbatim;
    /// MR (a modality) survives because it is not a title before a name.
    func testCleanDescriptorsRemovesEmbeddedIdentifiers() {
        var engine = ConfidentialityEngine(options: .init(cleanDescriptors: true))
        let (out, changed) = engine.deidentify(dataSet())
        XCTAssertEqual(out.string(for: studyDescription), "CT chest -")
        XCTAssertEqual(out.string(for: studyComments), "Seen , () at ; MR follow-up")
        XCTAssertTrue(changed.contains(studyComments))
        let codes = (out.sequence(for: Tag(group: 0x0012, element: 0x0064)) ?? []).compactMap { $0.string(for: .codeValue) }
        XCTAssertEqual(codes, ["113100", "113105"])
    }

    /// A descriptor with nothing identifying is kept unchanged (and not reported as changed).
    func testCleanDescriptorsKeepsSafeText() {
        var ds = dataSet()
        ds.setString("CT chest abdomen pelvis", for: studyDescription, vr: .LO)
        var engine = ConfidentialityEngine(options: .init(cleanDescriptors: true))
        let (out, changed) = engine.deidentify(ds)
        XCTAssertEqual(out.string(for: studyDescription), "CT chest abdomen pelvis")
        XCTAssertFalse(changed.contains(studyDescription))
    }

    /// A C sequence keeps its Items with their text cleaned (Reason for Visit Code Sequence).
    func testCleanDescriptorsCleansTextInsideSequences() throws {
        var ds = dataSet()
        var item = DataSet()
        item.setString("Follow-up for John Doe", for: .codeMeaning, vr: .LO)
        ds.setSequence([SequenceItem(elements: item.tags.compactMap { item[$0] })],
                       for: Tag(group: 0x0032, element: 0x1067))
        var engine = ConfidentialityEngine(options: .init(cleanDescriptors: true))
        let (out, _) = engine.deidentify(ds)
        let items = try XCTUnwrap(out.sequence(for: Tag(group: 0x0032, element: 0x1067)))
        XCTAssertEqual(items.first?.string(for: .codeMeaning), "Follow-up for")
    }

    func testWithoutCleanDescriptorsTheDescriptorIsRemoved() {
        var engine = ConfidentialityEngine()
        let (out, _) = engine.deidentify(dataSet())
        XCTAssertNil(out[studyDescription], "Table E.1-1 basic X")
    }

    // MARK: - D157 Modified Dates

    func testModifiedDatesShiftDAAndDTKeepTM() {
        var engine = ConfidentialityEngine(options: .init(retainLongitudinalTemporal: true, dateOffsetDays: -3))
        let (out, _) = engine.deidentify(dataSet())
        XCTAssertEqual(out.string(for: .studyDate), "20231230")
        XCTAssertEqual(out.string(for: Tag(group: 0x0008, element: 0x002A)), "20231230101500.5+0100",
                       "the DT date part shifts; time and offset kept")
        XCTAssertEqual(out.string(for: .studyTime), "101500", "a whole-day shift keeps the time of day")
        XCTAssertNil(out[Tag(group: 0x0008, element: 0x0201)], "Timezone Offset From UTC: Basic Profile X")
        XCTAssertEqual(out.string(for: .patientBirthDate), "", "no Modified Dates entry: Z")
    }

    /// Whole days in UTC: a shift across a daylight-saving change keeps the date arithmetic exact.
    func testShiftDICOMDate() {
        XCTAssertEqual(ConfidentialityEngine.shiftDICOMDate("20240331", byDays: 1), "20240401")
        XCTAssertEqual(ConfidentialityEngine.shiftDICOMDate("20241027", byDays: -1), "20241026")
        XCTAssertEqual(ConfidentialityEngine.shiftDICOMDate("20240229", byDays: 365), "20250228")
        XCTAssertNil(ConfidentialityEngine.shiftDICOMDate("2024", byDays: 1))
        XCTAssertNil(ConfidentialityEngine.shiftDICOMDateTime("202401", byDays: 1))
    }

    // MARK: - D161 (0028,0303)

    /// PS3.3 Table C.7-1 Enumerated Values; PS3.15 E.2 and E.3.6.
    func testLongitudinalTemporalInformationModified() {
        func value(_ options: ConfidentialityProfile.Options) -> (String?, VR?) {
            var engine = ConfidentialityEngine(options: options)
            let out = engine.deidentify(dataSet()).0
            return (out.string(for: temporalModified), out[temporalModified]?.vr)
        }
        XCTAssertEqual(value(.basic).0, "REMOVED")
        XCTAssertEqual(value(.basic).1, .CS)
        XCTAssertEqual(value(.init(retainLongitudinalTemporal: true)).0, "UNMODIFIED")
        XCTAssertEqual(value(.init(retainLongitudinalTemporal: true, dateOffsetDays: 5)).0, "MODIFIED")
    }

    // MARK: - D159 Retain Safe Private, Clean Graphics

    /// Table E.3.10-1 rows (dumped by Scripts/generate_confidentiality_profile.py):
    /// (0019,xx23) GEMS_ACQU_01 DS "Table Speed [mm/rotation]"; (7053,xx00) Philips PET
    /// Private Group DS "SUV Factor"; 479 rows in all.
    func testSafePrivateTableIsE3101() {
        XCTAssertEqual(ConfidentialityProfile.safePrivateAttributes.count, 479)
        XCTAssertEqual(ConfidentialityProfile.safePrivateAttributes["GEMS_ACQU_01|0019|23"], "DS")
        XCTAssertEqual(ConfidentialityProfile.safePrivateAttributes["Philips PET Private Group|7053|00"], "DS")
    }

    private func privateDataSet() -> DataSet {
        var ds = DataSet()
        ds.setString("DOE^JOHN", for: .patientName, vr: .PN)
        // Block 10 of group 0019: GE acquisition (Table Speed is listed safe).
        ds.setString("GEMS_ACQU_01", for: Tag(group: 0x0019, element: 0x0010), vr: .LO)
        ds.setString("12.5", for: Tag(group: 0x0019, element: 0x1023), vr: .DS)
        ds.setString("DOE JOHN", for: Tag(group: 0x0019, element: 0x1030), vr: .LO)  // not listed
        // Block 10 of group 0029: declared in (0008,0300) as MIXED, element 01 safe, 02 Z.
        ds.setString("ACME 1.0", for: Tag(group: 0x0029, element: 0x0010), vr: .LO)
        ds.setString("SAFE VALUE", for: Tag(group: 0x0029, element: 0x1001), vr: .LO)
        ds.setString("OPERATOR", for: Tag(group: 0x0029, element: 0x1002), vr: .LO)
        ds.setString("OTHER", for: Tag(group: 0x0029, element: 0x1003), vr: .LO)
        // Block 10 of group 0031: nothing safe, so its creator goes too.
        ds.setString("UNKNOWN", for: Tag(group: 0x0031, element: 0x0010), vr: .LO)
        ds.setString("SECRET", for: Tag(group: 0x0031, element: 0x1001), vr: .LO)
        var action = DataSet()
        action[Tag(group: 0x0008, element: 0x0306)] = .uint16s(tag: Tag(group: 0x0008, element: 0x0306), values: [0x02])
        action.setString("Z", for: Tag(group: 0x0008, element: 0x0307), vr: .CS)
        var declaration = DataSet()
        declaration[Tag(group: 0x0008, element: 0x0301)] = .uint16s(tag: Tag(group: 0x0008, element: 0x0301), values: [0x0029])
        declaration.setString("ACME 1.0", for: Tag(group: 0x0008, element: 0x0302), vr: .LO)
        declaration.setString("MIXED", for: Tag(group: 0x0008, element: 0x0303), vr: .CS)
        declaration[Tag(group: 0x0008, element: 0x0304)] = .uint16s(tag: Tag(group: 0x0008, element: 0x0304), values: [0x01])
        declaration.setSequence([SequenceItem(elements: action.tags.compactMap { action[$0] })],
                                for: Tag(group: 0x0008, element: 0x0305))
        ds.setSequence([SequenceItem(elements: declaration.tags.compactMap { declaration[$0] })],
                       for: Tag(group: 0x0008, element: 0x0300))
        return ds
    }

    /// PS3.15 E.3.10: safe Private Attributes are kept with their Private Creator; others go.
    func testRetainSafePrivate() {
        var engine = ConfidentialityEngine(options: .init(retainSafePrivate: true))
        let (out, _) = engine.deidentify(privateDataSet())
        XCTAssertEqual(out.string(for: Tag(group: 0x0019, element: 0x0010)), "GEMS_ACQU_01")
        XCTAssertEqual(out.string(for: Tag(group: 0x0019, element: 0x1023)), "12.5", "Table E.3.10-1")
        XCTAssertNil(out[Tag(group: 0x0019, element: 0x1030)], "not listed: removed")
        XCTAssertEqual(out.string(for: Tag(group: 0x0029, element: 0x1001)), "SAFE VALUE", "(0008,0304)")
        XCTAssertEqual(out.string(for: Tag(group: 0x0029, element: 0x1002)), "", "(0008,0307) Z")
        XCTAssertNil(out[Tag(group: 0x0029, element: 0x1003)])
        XCTAssertNil(out[Tag(group: 0x0031, element: 0x0010)], "a creator with nothing kept goes")
        XCTAssertNil(out[Tag(group: 0x0031, element: 0x1001)])
        let codes = (out.sequence(for: Tag(group: 0x0012, element: 0x0064)) ?? []).compactMap { $0.string(for: .codeValue) }
        XCTAssertEqual(codes, ["113100", "113111"])

        var basic = ConfidentialityEngine()
        let removed = basic.deidentify(privateDataSet()).0
        XCTAssertTrue(removed.tags.allSatisfy { $0.group & 1 == 0 }, "without the Option every private attribute goes")
    }

    /// PS3.15 E.3.3: Graphic Annotation Sequence kept, its text cleaned (not a dummy).
    func testCleanGraphics() throws {
        var text = DataSet()
        text.setString("Patient DOE JOHN, MRN12345", for: Tag(group: 0x0070, element: 0x0006), vr: .ST)
        var annotation = DataSet()
        annotation.setString("LAYER1", for: Tag(group: 0x0070, element: 0x0002), vr: .CS)
        annotation.setSequence([SequenceItem(elements: text.tags.compactMap { text[$0] })],
                               for: Tag(group: 0x0070, element: 0x0008))
        var ds = dataSet()
        ds.setSequence([SequenceItem(elements: annotation.tags.compactMap { annotation[$0] })],
                       for: Tag(group: 0x0070, element: 0x0001))

        var engine = ConfidentialityEngine(options: .init(cleanGraphics: true))
        let (out, _) = engine.deidentify(ds)
        let item = try XCTUnwrap(out.sequence(for: Tag(group: 0x0070, element: 0x0001))?.first)
        let textItem = try XCTUnwrap(DataSet(elements: item.allElements).sequence(for: Tag(group: 0x0070, element: 0x0008))?.first)
        XCTAssertEqual(textItem.string(for: Tag(group: 0x0070, element: 0x0006)), "Patient ,")
        let codes = (out.sequence(for: Tag(group: 0x0012, element: 0x0064)) ?? []).compactMap { $0.string(for: .codeValue) }
        XCTAssertEqual(codes, ["113100", "113103"])

        var basic = ConfidentialityEngine()
        let dummy = try XCTUnwrap(basic.deidentify(ds).0.sequence(for: Tag(group: 0x0070, element: 0x0001))?.first)
        let dummyText = try XCTUnwrap(DataSet(elements: dummy.allElements).sequence(for: Tag(group: 0x0070, element: 0x0008))?.first)
        XCTAssertEqual(dummyText.string(for: Tag(group: 0x0070, element: 0x0006)), "ANONYMIZED", "Basic Profile D")
    }

    // MARK: - D163, D164 legacy Anonymizer

    func testParseFlexibleTagTakesEveryPS36Keyword() {
        XCTAssertEqual(Anonymizer.parseFlexibleTag("PatientAge"), Tag(group: 0x0010, element: 0x1010))
        XCTAssertEqual(Anonymizer.parseFlexibleTag("AccessionNumber"), Tag(group: 0x0008, element: 0x0050))
        XCTAssertEqual(Anonymizer.parseFlexibleTag("(0010,0010)"), .patientName)
        XCTAssertNil(Anonymizer.parseFlexibleTag("patientname"), "keywords are exact")
    }

    func testKeepWinsOverTheLegacyDateShiftAndUIDs() throws {
        var ds = DataSet()
        ds.setString("20240102", for: .studyDate, vr: .DA)
        ds.setString("20240102", for: .seriesDate, vr: .DA)
        ds.setString("1.2.3", for: .studyInstanceUID, vr: .UI)
        let file = DICOMFile(fileMetaInformation: DataSet(), dataSet: ds)
        let anonymizer = Anonymizer(profile: .research, shiftDates: 10, regenerateUIDs: true,
                                    preserveTags: [.studyDate, .studyInstanceUID])
        let (out, _) = try anonymizer.anonymize(file: file, filePath: "x")
        XCTAssertEqual(out.dataSet.string(for: .studyDate), "20240102")
        XCTAssertEqual(out.dataSet.string(for: .seriesDate), "20240112")
        XCTAssertEqual(out.dataSet.string(for: .studyInstanceUID), "1.2.3")
    }
}

// MARK: - D159 Clean Structured Content (PS3.15 2026a E.3.4, Table E.3.4-1)

extension ConfidentialityOptionsTests {

    /// Table E.3.4-1 rows, dumped by Scripts/generate_confidentiality_profile.py: 211 rows,
    /// plus the SRT / SNM3 / 99SDM SNOMED IDs (PS3.16 Table O-1) of its 11 SCT rows.
    func testStructuredContentTableIsE341() {
        let rows = ConfidentialityProfile.structuredContentRows
        XCTAssertEqual(rows.count, 211 + 11 * 3)
        XCTAssertEqual(rows["DCM|121022|TEXT"], .init(meaning: "Accession Number", basic: "X"))
        XCTAssertEqual(rows["DCM|121008|PNAME"], .init(meaning: "Person Observer Name", basic: "D"))
        XCTAssertEqual(rows["DCM|126201|DATE"], .init(meaning: "Acquisition Date", basic: "X", fullDates: "K", modifiedDates: "C"))
        XCTAssertEqual(rows["DCM|121080|IMAGE"], .init(meaning: "Best illustration of finding", basic: "X", uids: "K"))
        XCTAssertEqual(rows["NCDR|76|PNAME"], .init(meaning: "Catheterization Operator", basic: "D"), "NCDR [2.0b]: designator NCDR")
        // SCT 371524004 Clinical Report = SNOMED ID R-42B89 (PS3.16 2026a Table O-1).
        XCTAssertEqual(rows["SCT|371524004|TEXT"], .init(meaning: "Clinical Report", basic: "X", cleanDescriptors: "C"))
        for designator in ["SRT", "SNM3", "99SDM"] {
            XCTAssertEqual(rows["\(designator)|R-42B89|TEXT"]?.basic, "X")
        }
    }

    private func contentItem(_ valueType: String, _ designator: String, _ code: String, _ meaning: String,
                             value: (Tag, VR, String)? = nil, children: [SequenceItem] = []) -> SequenceItem {
        var concept = DataSet()
        concept.setString(code, for: .codeValue, vr: .SH)
        concept.setString(designator, for: .codingSchemeDesignator, vr: .SH)
        concept.setString(meaning, for: .codeMeaning, vr: .LO)
        var item = DataSet()
        item.setString("CONTAINS", for: Tag(group: 0x0040, element: 0xA010), vr: .CS)
        item.setString(valueType, for: .valueType, vr: .CS)
        item.setSequence([SequenceItem(elements: concept.tags.compactMap { concept[$0] })], for: .conceptNameCodeSequence)
        if let (tag, vr, text) = value { item.setString(text, for: tag, vr: vr) }
        if !children.isEmpty { item.setSequence(children, for: .contentSequence) }
        return SequenceItem(elements: item.tags.compactMap { item[$0] })
    }

    private func srDataSet() -> DataSet {
        var ds = dataSet()
        let date = Tag(group: 0x0040, element: 0xA121)
        let observer = contentItem("PNAME", "DCM", "121008", "Person Observer Name",
                                   value: (.personName, .PN, "SMITH^ANNA"))
        ds.setSequence([
            contentItem("TEXT", "DCM", "121022", "Accession Number", value: (.textValue, .UT, "ACC777")),
            contentItem("TEXT", "DCM", "121106", "Comment", value: (.textValue, .UT, "Reviewed with John Doe, ACC777")),
            contentItem("DATE", "DCM", "126201", "Acquisition Date", value: (date, .DA, "20240102")),
            contentItem("TEXT", "DCM", "121073", "Impression", value: (.textValue, .UT, "Stable; John Doe to follow up")),
            contentItem("TEXT", "SRT", "R-42B89", "Clinical report", value: (.textValue, .UT, "old-style code")),
            contentItem("CONTAINER", "DCM", "121064", "Current Procedure Descriptions", children: [observer]),
        ], for: .contentSequence)
        return ds
    }

    private func content(_ out: DataSet) -> [DataSet] {
        (out.sequence(for: .contentSequence) ?? []).map { DataSet(elements: $0.allElements) }
    }

    private func conceptCode(_ item: DataSet) -> String? {
        item.sequence(for: .conceptNameCodeSequence)?.first?.string(for: .codeValue)
    }

    /// E.3.4 with Table E.3.4-1: X Content Items go (Accession Number, Comment, Acquisition
    /// Date, and the retired SRT code of Clinical Report), D replaces the value (Person
    /// Observer Name), an unlisted concept is kept with its text cleaned; 113104 recorded.
    func testCleanStructuredContentAppliesTableE341() throws {
        var engine = ConfidentialityEngine(options: .init(cleanStructuredContent: true))
        let (out, changed) = engine.deidentify(srDataSet())
        let items = content(out)
        XCTAssertEqual(items.map(conceptCode), ["121073", "121064"])
        XCTAssertEqual(items[0].string(for: .textValue), "Stable; to follow up", "unlisted: kept, text cleaned")
        let observer = try XCTUnwrap(items[1].sequence(for: .contentSequence)?.first)
        XCTAssertEqual(observer.string(for: .personName), "ANONYMOUS", "Person Observer Name: D")
        XCTAssertTrue(changed.contains(.contentSequence))
        let codes = (out.sequence(for: Tag(group: 0x0012, element: 0x0064)) ?? []).compactMap { $0.string(for: .codeValue) }
        XCTAssertEqual(codes, ["113100", "113104"])
        XCTAssertEqual(out.string(for: Tag(group: 0x0012, element: 0x0063))?.components(separatedBy: "\\").last, "Clean Structured Content Option")
    }

    /// The option columns of Table E.3.4-1: Clean Descriptors cleans Comment (C), Full Dates
    /// keeps Acquisition Date (K), Modified Dates shifts it (C).
    func testCleanStructuredContentOptionColumns() throws {
        let date = Tag(group: 0x0040, element: 0xA121)
        var descriptors = ConfidentialityEngine(options: .init(cleanDescriptors: true, cleanStructuredContent: true))
        let d = content(descriptors.deidentify(srDataSet()).0)
        XCTAssertEqual(d.first { conceptCode($0) == "121106" }?.string(for: .textValue), "Reviewed with ,")
        XCTAssertNil(d.first { conceptCode($0) == "121022" }, "Accession Number has no option column: X")

        var full = ConfidentialityEngine(options: .init(retainLongitudinalTemporal: true, cleanStructuredContent: true))
        XCTAssertEqual(content(full.deidentify(srDataSet()).0).first { conceptCode($0) == "126201" }?.string(for: date), "20240102")

        var modified = ConfidentialityEngine(options: .init(retainLongitudinalTemporal: true, dateOffsetDays: 10,
                                                            cleanStructuredContent: true))
        XCTAssertEqual(content(modified.deidentify(srDataSet()).0).first { conceptCode($0) == "126201" }?.string(for: date), "20240112")
    }

    /// Without the Option the Content Sequence gets its Table E.1-1 Basic action D (C only
    /// under the Option): the Content Items are kept, and the action reaches all of their
    /// contents (E.1.1), so no Text Value is released verbatim; no 113104 is recorded (D236).
    func testWithoutCleanStructuredContentNoContentItemIsRemoved() throws {
        let row = try XCTUnwrap(ConfidentialityProfile.tableE11[0x0040A730])
        XCTAssertEqual(row.basic, "D")
        XCTAssertEqual(row.cleanStructuredContent, "C")
        var engine = ConfidentialityEngine()
        let (out, changed) = engine.deidentify(srDataSet())
        let items = content(out)
        XCTAssertEqual(items.map(conceptCode), ["121022", "121106", "126201", "121073", "R-42B89", "121064"],
                       "D: a non-zero length Sequence, every Content Item and Concept Name kept")
        XCTAssertEqual(items.compactMap { $0.string(for: .textValue) }, Array(repeating: "ANONYMIZED", count: 4),
                       "Text Value has no Table E.1-1 row: it takes the D of the Content Sequence")
        XCTAssertEqual(items[2].string(for: Tag(group: 0x0040, element: 0xA121)), "19000101", "Date (0040,A121): D")
        let observer = try XCTUnwrap(items[5].sequence(for: .contentSequence)?.first)
        XCTAssertEqual(observer.string(for: .personName), "ANONYMOUS", "Person Name (0040,A123): D, nested Content Sequence")
        XCTAssertTrue(changed.contains(.contentSequence))
        let codes = (out.sequence(for: Tag(group: 0x0012, element: 0x0064)) ?? []).compactMap { $0.string(for: .codeValue) }
        XCTAssertEqual(codes, ["113100"])
    }

    /// Basic D on a NUM and a TABLE Content Item: the numeric values and the cell values are
    /// dummies of their VR with the number of values kept; units, codes and the Rational
    /// Denominator (non-zero) stay valid; Retain Longitudinal Full Dates still keeps Date
    /// (0040,A121) by its own Table E.1-1 row (D236).
    func testBasicContentSequenceReplacesNumericAndTableValues() throws {
        var units = DataSet()
        units.setString("mm", for: .codeValue, vr: .SH)
        units.setString("UCUM", for: .codingSchemeDesignator, vr: .SH)
        units.setString("millimeter", for: .codeMeaning, vr: .LO)
        let unitsItem = SequenceItem(elements: units.tags.compactMap { units[$0] })
        var measured = DataSet()
        measured.setString("89", for: Tag(group: 0x0040, element: 0xA30A), vr: .DS)
        measured[Tag(group: 0x0040, element: 0xA162)] = DataElement.data(tag: Tag(group: 0x0040, element: 0xA162), vr: .SL,
                                                                          data: Data([89, 0, 0, 0]))
        measured[Tag(group: 0x0040, element: 0xA163)] = DataElement.data(tag: Tag(group: 0x0040, element: 0xA163), vr: .UL,
                                                                          data: Data([1, 0, 0, 0]))
        measured.setSequence([unitsItem], for: Tag(group: 0x0040, element: 0x08EA))
        var num = DataSet(elements: contentItem("NUM", "DCM", "121033", "Subject Age").allElements)
        num.setSequence([SequenceItem(elements: measured.tags.compactMap { measured[$0] })], for: Tag(group: 0x0040, element: 0xA300))

        var cell = DataSet()
        cell.setString("UC", for: Tag(group: 0x0072, element: 0x0050), vr: .CS)
        cell.setString("John Doe\\MRN12345", for: Tag(group: 0x0072, element: 0x006F), vr: .UC)
        var table = DataSet()
        table.setSequence([SequenceItem(elements: cell.tags.compactMap { cell[$0] })], for: Tag(group: 0x0040, element: 0xA808))
        var tableItem = DataSet(elements: contentItem("TABLE", "DCM", "111111", "Table").allElements)
        tableItem.setSequence([SequenceItem(elements: table.tags.compactMap { table[$0] })], for: Tag(group: 0x0040, element: 0xA801))

        var ds = srDataSet()
        var items = ds.sequence(for: .contentSequence) ?? []
        items += [SequenceItem(elements: num.tags.compactMap { num[$0] }),
                  SequenceItem(elements: tableItem.tags.compactMap { tableItem[$0] })]
        ds.setSequence(items, for: .contentSequence)

        var engine = ConfidentialityEngine()
        let out = content(engine.deidentify(ds).0)
        let value = DataSet(elements: try XCTUnwrap(out[6].sequence(for: Tag(group: 0x0040, element: 0xA300))?.first).allElements)
        XCTAssertEqual(value.string(for: Tag(group: 0x0040, element: 0xA30A)), "0")
        XCTAssertEqual(value[Tag(group: 0x0040, element: 0xA162)]?.valueData, Data([0, 0, 0, 0]))
        XCTAssertEqual(value[Tag(group: 0x0040, element: 0xA163)]?.valueData, Data([1, 0, 0, 0]))
        XCTAssertEqual(value.sequence(for: Tag(group: 0x0040, element: 0x08EA))?.first?.string(for: .codeValue), "mm")
        let tabulated = DataSet(elements: try XCTUnwrap(out[7].sequence(for: Tag(group: 0x0040, element: 0xA801))?.first).allElements)
        let outCell = try XCTUnwrap(tabulated.sequence(for: Tag(group: 0x0040, element: 0xA808))?.first)
        XCTAssertEqual(outCell.string(for: Tag(group: 0x0072, element: 0x006F)), "ANONYMIZED\\ANONYMIZED")
        XCTAssertEqual(outCell.string(for: Tag(group: 0x0072, element: 0x0050)), "UC")

        var full = ConfidentialityEngine(options: .init(retainLongitudinalTemporal: true))
        let kept = content(full.deidentify(ds).0)
        XCTAssertEqual(kept[2].string(for: Tag(group: 0x0040, element: 0xA121)), "20240102", "Date: Full Dates K")
        XCTAssertEqual(kept[1].string(for: .textValue), "ANONYMIZED")
    }

    /// Acquisition Context Sequence (0040,0555) Items are Content Items too (E.3.4).
    func testCleanStructuredContentCoversAcquisitionContext() {
        var ds = dataSet()
        ds.setSequence([contentItem("TEXT", "DCM", "121022", "Accession Number", value: (.textValue, .UT, "ACC777")),
                        contentItem("TEXT", "DCM", "121073", "Impression", value: (.textValue, .UT, "ok"))],
                       for: Tag(group: 0x0040, element: 0x0555))
        var engine = ConfidentialityEngine(options: .init(cleanStructuredContent: true))
        let out = engine.deidentify(ds).0
        XCTAssertEqual(out.sequence(for: Tag(group: 0x0040, element: 0x0555))?.count, 1)
        var basic = ConfidentialityEngine()
        XCTAssertNil(basic.deidentify(ds).0[Tag(group: 0x0040, element: 0x0555)], "Table E.1-1 basic X/Z: X")
    }

    /// The engine keeps the 113102 Item and (0028,0302) NO written by the Clean Recognizable
    /// Visual Features pass of PixelRedactor, and names it in (0012,0063) (E.3.2, D160).
    func testEngineKeepsTheRecognizableVisualFeaturesRecord() {
        var ds = dataSet()
        ds.setString("NO", for: .recognizableVisualFeatures, vr: .CS)
        ds.setSequence([ConfidentialityProfile.DeidentificationMethodCode.cleanRecognizableVisualFeaturesOption.sequenceItem],
                       for: Tag(group: 0x0012, element: 0x0064))
        var engine = ConfidentialityEngine()
        let out = engine.deidentify(ds).0
        XCTAssertEqual(out.string(for: .recognizableVisualFeatures), "NO")
        let codes = (out.sequence(for: Tag(group: 0x0012, element: 0x0064)) ?? []).compactMap { $0.string(for: .codeValue) }
        XCTAssertEqual(codes, ["113100", "113102"])
        XCTAssertEqual(out.string(for: Tag(group: 0x0012, element: 0x0063))?.components(separatedBy: "\\").last, "Clean Recognizable Visual Features Option")
    }
}
