// NEMA-verified: 2026a, checked 2026-10-01 — the 16 Value Types of PS3.3 2026a Table C.17.3-7 and the 7 Relationship Types of Table C.17.3-8 (pinned below as dumped by Scripts/nema_docbook.py), Completion/Verification/Preliminary Flag Enumerated Values of Table C.17-2, Content Template Sequence of Table C.18.8-1, coded entries as PS3.16 2026a 6.1 writes them; codes from PS3.16 Table D-1 and CID 82
import XCTest
import Foundation
import DICOMCore
@testable import DICOMKit
@testable import dicom_report

/// `dicom-report` renders SR documents: every Value Type of PS3.3 2026a Table C.17.3-7 prints a
/// value, coded values print as (CV, CSD, "CM"), and the document status attributes and the
/// root template are shown.
final class SRRenderingTests: XCTestCase {

    /// PS3.3 2026a Table C.17.3-7, column 1, in table order.
    static let table_C_17_3_7 = ["TEXT", "NUM", "CODE", "DATETIME", "DATE", "TIME", "UIDREF", "PNAME",
                                 "COMPOSITE", "IMAGE", "WAVEFORM", "SCOORD", "SCOORD3D", "TCOORD",
                                 "CONTAINER", "TABLE"]
    /// PS3.3 2026a Table C.17.3-8, column 1, in table order.
    static let table_C_17_3_8 = ["CONTAINS", "HAS OBS CONTEXT", "HAS CONCEPT MOD", "HAS PROPERTIES",
                                 "HAS ACQ CONTEXT", "INFERRED FROM", "SELECTED FROM"]

    private static func dcm(_ value: String, _ meaning: String) -> CodedConcept {
        CodedConcept(codeValue: value, codingSchemeDesignator: "DCM", codeMeaning: meaning)
    }
    private static func sct(_ value: String, _ meaning: String) -> CodedConcept {
        CodedConcept(codeValue: value, codingSchemeDesignator: "SCT", codeMeaning: meaning)
    }
    private static let mm = CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "mm")
    private static let ctImage = "1.2.840.10008.5.1.4.1.1.2"           // CT Image Storage
    private static let ecg = "1.2.840.10008.5.1.4.1.1.9.1.1"           // 12-lead ECG Waveform Storage
    private static let segmentation = "1.2.840.10008.5.1.4.1.1.66.4"   // Segmentation Storage

    /// An Extensible SR (the IOD that allows every Value Type, incl. TABLE) using all 16 Value
    /// Types and all 7 Relationship Types, rooted in TID 1500 (DCMR).
    static func fixtureDocument() -> SRDocument {
        let image = AnyContentItem(ImageContentItem(sopClassUID: ctImage, sopInstanceUID: "1.2.3.100",
                                                    frameNumbers: [2], relationshipType: .selectedFrom))
        let scoord = AnyContentItem(SpatialCoordinatesContentItem(
            conceptName: dcm("121055", "Path"), graphicType: .polyline, graphicData: [1, 2, 3.5, 4],
            relationshipType: .inferredFrom, contentItems: [image]))
        let length = AnyContentItem(NumericContentItem(
            conceptName: sct("103339001", "Long Axis"), value: 12, units: mm,
            relationshipType: .contains, contentItems: [scoord]))
        let scoord3D = AnyContentItem(SpatialCoordinates3DContentItem(
            conceptName: dcm("121055", "Path"), graphicType: .point, graphicData: [1, 2, 3],
            frameOfReferenceUID: "1.2.3.200", relationshipType: .inferredFrom))
        let distance = AnyContentItem(NumericContentItem(
            conceptName: dcm("121206", "Distance"), value: 7.25, units: mm,
            relationshipType: .contains, contentItems: [scoord3D]))
        let site = AnyContentItem(CodeContentItem(
            conceptName: sct("363698007", "Finding Site"), conceptCode: sct("76752008", "Breast"),
            relationshipType: .hasProperties))
        let finding = AnyContentItem(CodeContentItem(
            conceptName: dcm("121071", "Finding"), conceptCode: sct("76752008", "Breast"),
            relationshipType: .contains, contentItems: [site]))
        let waveform = AnyContentItem(WaveformContentItem(
            waveformReference: WaveformReference(sopReference: ReferencedSOP(sopClassUID: ecg, sopInstanceUID: "1.2.3.300"),
                                                 channelNumbers: [1, 2]),
            relationshipType: .selectedFrom))
        let tcoord = AnyContentItem(TemporalCoordinatesContentItem(
            conceptName: dcm("121112", "Source of Measurement"), temporalRangeType: .segment,
            samplePositions: [10, 20], relationshipType: .contains, contentItems: [waveform]))
        let composite = AnyContentItem(CompositeContentItem(
            conceptName: dcm("121191", "Referenced Segment"), sopClassUID: segmentation,
            sopInstanceUID: "1.2.3.400", relationshipType: .contains))
        let table = AnyContentItem(TableContentItem(
            conceptName: dcm("126010", "Imaging Measurements"), rows: 1, columns: 1,
            rowDefinitions: [.init(index: 1, concept: sct("103339001", "Long Axis"))],
            columnDefinitions: [.init(index: 1, concept: sct("103339001", "Long Axis"), units: mm)],
            cells: [.init(row: 1, column: 1, value: .decimal([12]), units: mm)],
            relationshipType: .contains))
        let tracking = AnyContentItem(TextContentItem(
            conceptName: dcm("112039", "Tracking Identifier"), textValue: "Lesion 1",
            relationshipType: .hasObsContext))
        let group = AnyContentItem(ContainerContentItem(
            conceptName: dcm("125007", "Measurement Group"),
            contentItems: [tracking, length, distance, finding, tcoord, composite, table],
            relationshipType: .contains))
        let language = AnyContentItem(CodeContentItem(
            conceptName: dcm("121049", "Language of Content Item and Descendants"),
            conceptCode: CodedConcept(codeValue: "en-US", codingSchemeDesignator: "RFC5646", codeMeaning: "English (United States)"),
            relationshipType: .hasConceptMod))
        let observer = AnyContentItem(PersonNameContentItem(
            conceptName: dcm("121008", "Person Observer Name"), personName: "Doe^Jane", relationshipType: .hasObsContext))
        let studyUID = AnyContentItem(UIDRefContentItem(
            conceptName: dcm("121018", "Procedure Study Instance UID"), uidValue: "1.2.3.500", relationshipType: .hasObsContext))
        let date = AnyContentItem(DateContentItem(
            conceptName: dcm("111060", "Study Date"), dateValue: "20260930", relationshipType: .hasAcqContext))
        let time = AnyContentItem(TimeContentItem(
            conceptName: dcm("111061", "Study Time"), timeValue: "101500", relationshipType: .hasAcqContext))
        let dateTime = AnyContentItem(DateTimeContentItem(
            conceptName: dcm("111526", "DateTime Started"), dateTimeValue: "20260930101500", relationshipType: .hasAcqContext))
        let root = ContainerContentItem(
            conceptName: dcm("126000", "Imaging Measurement Report"),
            contentItems: [language, observer, studyUID, date, time, dateTime, group],
            templateIdentifier: "1500", mappingResource: "DCMR")
        return SRDocument(
            sopClassUID: SRDocumentType.extensibleSR.sopClassUID, sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            patientID: "P1", patientName: "Test^Patient", studyInstanceUID: "1.2.3.500",
            studyDate: "20260930", accessionNumber: "A1",
            completionFlag: .complete, verificationFlag: .unverified, preliminaryFlag: .final,
            documentTitle: dcm("126000", "Imaging Measurement Report"), rootContent: root)
    }

    /// The fixture as a Part 10 file, read back through the same path `dicom-report` uses.
    static func fixtureFileData() throws -> Data {
        let document = fixtureDocument()
        let dataSet = try SRDocumentSerializer().serialize(document: document)
        return try DICOMFile.create(dataSet: dataSet, sopClassUID: document.sopClassUID,
                                    sopInstanceUID: document.sopInstanceUID).write()
    }

    private func parsedFixture() throws -> SRDocument {
        let file = try DICOMFile.read(from: Self.fixtureFileData())
        return try SRDocumentParser().parse(dataSet: file.dataSet)
    }

    private func render(_ format: ReportFormat, _ document: SRDocument) throws -> String {
        let options = ReportOptions(format: format, template: "default", embedImages: false,
                                    imageDirectory: nil, customTitle: nil, logoPath: nil, footerText: nil,
                                    includeMeasurements: true, includeSummary: true)
        return String(decoding: try ReportGenerator(document: document, options: options).generate(), as: UTF8.self)
    }

    /// Writes the fixture to $DICOM_REPORT_FIXTURE_DIR/sr-all-value-types.dcm when set, so the
    /// CLI can be run on it and its labels diffed by script.
    func testWritesFixtureWhenAsked() throws {
        guard let dir = ProcessInfo.processInfo.environment["DICOM_REPORT_FIXTURE_DIR"] else { return }
        try Self.fixtureFileData().write(to: URL(fileURLWithPath: dir).appendingPathComponent("sr-all-value-types.dcm"))
    }

    // MARK: - JSON: value_type and relationship_type use the PS3.3 names

    private func walk(_ items: [[String: Any]], _ visit: ([String: Any]) -> Void) {
        for item in items {
            visit(item)
            walk(item["children"] as? [[String: Any]] ?? [], visit)
        }
    }

    func testJSONValueAndRelationshipTypesArePS33Names() throws {
        let document = try parsedFixture()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(render(.json, document).utf8)) as? [String: Any])
        var valueTypes = Set<String>(), relationships = Set<String>()
        walk(json["content"] as? [[String: Any]] ?? []) { item in
            if let v = item["value_type"] as? String { valueTypes.insert(v) }
            if let r = item["relationship_type"] as? String { relationships.insert(r) }
        }
        // The root CONTAINER is not in "content"; its 15 descendants' types plus CONTAINER (group).
        XCTAssertEqual(valueTypes, Set(Self.table_C_17_3_7))
        XCTAssertEqual(relationships, Set(Self.table_C_17_3_8))
        XCTAssertEqual(Set(ContentItemValueType.allCases.map(\.rawValue)), Set(Self.table_C_17_3_7))
        XCTAssertEqual(Set(RelationshipType.allCases.map(\.rawValue)), Set(Self.table_C_17_3_8))
    }

    func testJSONStatusFlagsAndTemplate() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(render(.json, try parsedFixture()).utf8)) as? [String: Any])
        XCTAssertEqual(json["completion_flag"] as? String, "COMPLETE")
        XCTAssertEqual(json["verification_flag"] as? String, "UNVERIFIED")
        XCTAssertEqual(json["preliminary_flag"] as? String, "FINAL")
        let template = try XCTUnwrap(json["content_template"] as? [String: String])
        XCTAssertEqual(template["template_identifier"], "1500")
        XCTAssertEqual(template["mapping_resource"], "DCMR")
        XCTAssertEqual(json["document_type"] as? String, "Extensible SR")   // PS3.6 A-1 name less " Storage"
        XCTAssertEqual(json["title"] as? String, "Imaging Measurement Report")
    }

    // MARK: - Text: every Value Type prints a value

    func testTextPrintsAValueForEveryValueType() throws {
        let text = try render(.text, try parsedFixture())
        XCTAssertFalse(text.contains("[Content]"), text)
        for expected in [
            "Lesion 1",                                                // TEXT
            "12 mm", "7.25 mm",                                        // NUM, Code Meaning of units
            "(76752008, SCT, \"Breast\")",                             // CODE
            "(en-US, RFC5646, \"English (United States)\")",
            "20260930101500",                                          // DATETIME
            "2026-09-30",                                              // DATE
            "101500",                                                  // TIME
            "1.2.3.500",                                               // UIDREF
            "Doe^Jane",                                                // PNAME
            "Composite: 1.2.3.400",                                    // COMPOSITE
            "Image: 1.2.3.100 frames 2",                               // IMAGE
            "Waveform: 1.2.3.300",                                     // WAVEFORM
            "POLYLINE (1,2) (3.5,4)",                                  // SCOORD
            "POINT (1,2,3) in 1.2.3.200",                              // SCOORD3D
            "SEGMENT 10 20",                                           // TCOORD
            "Table: 1 rows x 1 columns",                               // TABLE
        ] {
            XCTAssertTrue(text.contains(expected), "missing \(expected)\n\(text)")
        }
        XCTAssertFalse(text.contains("12.0 mm"))
        // Children of NUM, CODE and TCOORD items are rendered, not only those of CONTAINERs
        XCTAssertTrue(text.contains("    Finding Site:\n      (76752008, SCT, \"Breast\")"), text)
    }

    func testWaveformChannelsPrintWhenPresent() throws {
        let text = try render(.text, Self.fixtureDocument())
        XCTAssertTrue(text.contains("Waveform: 1.2.3.300 channels (M,C) (1,1) (1,2)"), text)
    }

    /// PS3.3 2026a C.18.5.1.1: each channel is an (M,C) pair; the example "applies to the
    /// entire first multiplex group and channels 2 and 3 of the third multiplex group" is
    /// 0001 0000 0003 0002 0003 0003. The multiplex group must be shown, not only C (D225).
    func testWaveformChannelsPrintTheMultiplexGroupOfEachPair() throws {
        let reference = WaveformReference(
            sopReference: ReferencedSOP(sopClassUID: Self.ecg, sopInstanceUID: "1.2.3.301"),
            referencedChannels: [
                WaveformChannelReference(multiplexGroup: 1, channel: 0),
                WaveformChannelReference(multiplexGroup: 3, channel: 2),
                WaveformChannelReference(multiplexGroup: 3, channel: 3),
            ])
        let root = ContainerContentItem(
            conceptName: Self.dcm("126000", "Imaging Measurement Report"),
            contentItems: [AnyContentItem(WaveformContentItem(waveformReference: reference, relationshipType: .contains))])
        let document = SRDocument(
            sopClassUID: SRDocumentType.extensibleSR.sopClassUID, sopInstanceUID: "1.2.3.9",
            patientID: "P1", patientName: "Test^Patient", studyInstanceUID: "1.2.3.500",
            studyDate: "20260930", accessionNumber: "A1",
            completionFlag: .complete, verificationFlag: .unverified, preliminaryFlag: .final,
            documentTitle: Self.dcm("126000", "Imaging Measurement Report"), rootContent: root)
        let text = try render(.text, document)
        XCTAssertTrue(text.contains("Waveform: 1.2.3.301 channels (M,C) (1,0) (3,2) (3,3)"), text)
    }

    func testRefusesADataSetThatIsNotAnSRDocument() throws {
        var ct = DataSet()
        ct.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        XCTAssertThrowsError(try DICOMReport.requireStructuredReport(ct)) { error in
            XCTAssertTrue("\(error)".contains("CT Image Storage"), "\(error)")
        }
        let sr = try SRDocumentSerializer().serialize(document: Self.fixtureDocument())
        XCTAssertNoThrow(try DICOMReport.requireStructuredReport(sr))
    }

    func testTextHeaderShowsSOPClassFlagsAndTemplate() throws {
        let text = try render(.text, try parsedFixture())
        XCTAssertTrue(text.contains("Imaging Measurement Report"))
        XCTAssertTrue(text.contains("Extensible SR"))
        XCTAssertTrue(text.contains("Completion Flag: COMPLETE"))
        XCTAssertTrue(text.contains("Verification Flag: UNVERIFIED"))
        XCTAssertTrue(text.contains("Preliminary Flag: FINAL"))
        // PS3.16 2026a title of TID 1500, from DICOMCore's generated TemplateRegistry
        XCTAssertTrue(text.contains("Content Template: TID 1500 Measurement Report (DCMR)"), text)
    }

    func testMarkdownAndHTMLCarryTheSameStatusLines() throws {
        let document = try parsedFixture()
        let md = try render(.markdown, document)
        XCTAssertTrue(md.contains("- **Completion Flag:** COMPLETE"))
        XCTAssertTrue(md.contains("- **Content Template:** TID 1500 Measurement Report (DCMR)"))
        let html = try render(.html, document)
        XCTAssertTrue(html.contains("<td>Verification Flag:</td><td>UNVERIFIED</td>"))
        // Coded values are escaped in HTML
        XCTAssertTrue(html.contains("(76752008, SCT, &quot;Breast&quot;)"))
    }

    // MARK: - Helpers

    func testCodedEntryNotationOfPS316Section61() {
        XCTAssertEqual(ReportGenerator.codedEntry(Self.sct("76752008", "Breast")), "(76752008, SCT, \"Breast\")")
        XCTAssertEqual(ReportGenerator.codedEntry(CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM",
                                                               codeMeaning: "mm", codingSchemeVersion: "1.4")),
                       "(mm, UCUM [1.4], \"mm\")")
        let long = CodedConcept(codeValue: "", codingSchemeDesignator: "SCT", codeMeaning: "Long",
                                longCodeValue: "12345678901234567890")
        XCTAssertEqual(ReportGenerator.codedEntry(long), "(12345678901234567890, SCT, \"Long\")")
    }

    func testMeasurementTableUsesUnitsCodeMeaningAndPlainNumbers() throws {
        let md = try render(.markdown, try parsedFixture())
        XCTAssertTrue(md.contains("| Long Axis | 12 | mm |"), md)
        XCTAssertTrue(md.contains("| Distance | 7.25 | mm |"), md)
    }
}

/// P-REPORT-TEMPLATE and P-REPORT-SUMMARY: `--style` is a styling preset (unknown values are
/// refused; `--template` is a deprecated alias) and `--include-summary` gates the summary sections.
final class ReportStyleAndSummaryTests: XCTestCase {

    func testStyleResolvesKnownPresetsCaseInsensitively() throws {
        XCTAssertEqual(try DICOMReport.resolveStyle(style: nil, template: nil).style.name, "default")
        XCTAssertEqual(try DICOMReport.resolveStyle(style: "Radiology", template: nil).style.name, "radiology")
        XCTAssertTrue(try DICOMReport.resolveStyle(style: "oncology", template: nil).notes.isEmpty)
        XCTAssertEqual(ReportTemplate.all.map(\.name), ["default", "cardiology", "radiology", "oncology"])
    }

    func testTemplateIsADeprecatedAliasWithANote() throws {
        let resolution = try DICOMReport.resolveStyle(style: nil, template: "cardiology")
        XCTAssertEqual(resolution.style.name, "cardiology")
        XCTAssertEqual(resolution.notes.count, 1)
        XCTAssertTrue(resolution.notes[0].contains("--template is deprecated; use --style"))
    }

    func testBothGivenIsRefused() {
        XCTAssertThrowsError(try DICOMReport.resolveStyle(style: "default", template: "default")) { error in
            XCTAssertTrue("\(error)".contains("both given"), "\(error)")
        }
    }

    func testUnknownStyleIsRefusedListingTheValidStyles() {
        XCTAssertThrowsError(try DICOMReport.resolveStyle(style: "neuro", template: nil)) { error in
            let text = "\(error)"
            XCTAssertTrue(text.contains("Valid styles: default, cardiology, radiology, oncology."), text)
            XCTAssertFalse(text.contains("PS3.16"), text)
        }
    }

    func testTIDLikeValueExplainsPS316Templates() {
        for value in ["1500", "TID 1500", "tid1500", "TID-2000"] {
            XCTAssertThrowsError(try DICOMReport.resolveStyle(style: nil, template: value)) { error in
                let text = "\(error)"
                XCTAssertTrue(text.contains("SR templates are PS3.16 Template IDs (TIDs)"), text)
                XCTAssertTrue(text.contains("Content Template Sequence (0040,A504)"), text)
                XCTAssertTrue(text.contains("styling preset"), text)
            }
        }
        XCTAssertFalse(ReportStyleError.looksLikeTID("radiology"))
        XCTAssertFalse(ReportStyleError.looksLikeTID("TID"))
    }

    /// An SR whose tree has an Impressions and a Recommendation item.
    private static func summaryDocument() -> SRDocument {
        let impression = AnyContentItem(TextContentItem(
            conceptName: CodedConcept(codeValue: "121073", codingSchemeDesignator: "DCM", codeMeaning: "Impression"),
            textValue: "No acute finding", relationshipType: .contains))
        let recommendation = AnyContentItem(TextContentItem(
            conceptName: CodedConcept(codeValue: "121075", codingSchemeDesignator: "DCM", codeMeaning: "Recommendation"),
            textValue: "Follow up in 6 months", relationshipType: .contains))
        let root = ContainerContentItem(
            conceptName: CodedConcept(codeValue: "18748-4", codingSchemeDesignator: "LN", codeMeaning: "Diagnostic Imaging Report"),
            contentItems: [impression, recommendation])
        return SRDocument(sopClassUID: SRDocumentType.comprehensiveSR.sopClassUID, sopInstanceUID: "1.2.3.9",
                          documentTitle: root.conceptName, rootContent: root)
    }

    private func render(_ format: ReportFormat, includeSummary: Bool) throws -> String {
        let options = ReportOptions(format: format, template: "cardiology", embedImages: false, imageDirectory: nil,
                                    customTitle: nil, logoPath: nil, footerText: nil,
                                    includeMeasurements: true, includeSummary: includeSummary)
        return String(decoding: try ReportGenerator(document: Self.summaryDocument(), options: options).generate(),
                      as: UTF8.self)
    }

    func testIncludeSummaryGatesImpressionsAndRecommendations() throws {
        let on = try render(.text, includeSummary: true)
        XCTAssertTrue(on.contains("IMPRESSIONS"), on)
        XCTAssertTrue(on.contains("RECOMMENDATIONS"), on)
        let off = try render(.text, includeSummary: false)
        XCTAssertFalse(off.contains("IMPRESSIONS"), off)
        XCTAssertFalse(off.contains("RECOMMENDATIONS"), off)
        XCTAssertTrue(off.contains("No acute finding"), off)   // the content tree is still rendered
        XCTAssertFalse(try render(.markdown, includeSummary: false).contains("## Impressions"))
        XCTAssertTrue(try render(.markdown, includeSummary: true).contains("## Impressions"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try render(.json, includeSummary: false).utf8)) as? [String: Any])
        XCTAssertEqual(json["include_summary"] as? Bool, false)
    }
}
