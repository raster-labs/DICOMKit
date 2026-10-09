import XCTest
import DICOMCore
import DICOMNetwork
@testable import dicom_query

/// P-QUERY-JSON / P-QUERY-COLUMNS (2026-10-01).
///  - `--format dicom-json`: the PS3.18 2026a F.2 DICOM JSON Model (tag keys,
///    `vr`, `Value`, PN component objects; UTF-8 / ISO_IR 192 per F.2).
///  - table labels: PS3.6 2026a Table 6-1 Attribute Names; `--csv-keywords`:
///    PS3.6 Keywords in the CSV header (default header unchanged).
final class QueryOutputFormatTests: XCTestCase {

    private func study() -> GenericQueryResult {
        GenericQueryResult(attributes: [
            .specificCharacterSet: Data("ISO_IR 100".utf8),
            .patientName: "MÜLLER^HANS ".data(using: .isoLatin1)!,
            .patientID: Data("12345 ".utf8),
            .studyDate: Data("20261001".utf8),
            .studyInstanceUID: Data("1.2.3\0".utf8),
            .modalitiesInStudy: Data("CT\\PR".utf8),
            .numberOfStudyRelatedSeries: Data("2 ".utf8),
        ], level: .study)
    }

    func testDICOMJSONIsThePS318F2Model() throws {
        let text = DICOMQuery.formatter(format: .dicomJSON, level: .study, csvKeywords: false)
            .format(results: [study()])
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        let object = array[0]
        // F.2.2: eight uppercase hex digit keys, each with "vr" and "Value".
        let name = try XCTUnwrap(object["00100010"] as? [String: Any])
        XCTAssertEqual(name["vr"] as? String, "PN")
        XCTAssertEqual((name["Value"] as? [[String: String]])?.first?["Alphabetic"], "MÜLLER^HANS")
        let modalities = try XCTUnwrap(object["00080061"] as? [String: Any])
        XCTAssertEqual(modalities["vr"] as? String, "CS")
        XCTAssertEqual(modalities["Value"] as? [String], ["CT", "PR"])
        XCTAssertEqual((object["0020000D"] as? [String: Any])?["Value"] as? [String], ["1.2.3"])
        // IS is a "Number or String" VR; DICOMWeb writes it as a string (F.2.3 Note).
        XCTAssertEqual((object["00201206"] as? [String: Any])?["vr"] as? String, "IS")
        // F.2: UTF-8 / ISO_IR 192 — the Latin-1 response is transcoded.
        XCTAssertEqual((object["00080005"] as? [String: Any])?["Value"] as? [String], ["ISO_IR 192"])
        XCTAssertNil(object["(0010,0010)"], "no tool-summary keys")
        // F.2.2: attribute objects in ascending tag order.
        let keys = text.components(separatedBy: "\n").compactMap { line -> String? in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.count > 11, t.hasPrefix("\""), t.dropFirst(9).hasPrefix("\" :") || t.dropFirst(9).hasPrefix("\":") else { return nil }
            return String(t.dropFirst().prefix(8))
        }
        XCTAssertEqual(keys, keys.sorted(), text)
    }

    func testJSONSummaryIsUnchanged() {
        let text = DICOMQuery.formatter(format: .json, level: .study, csvKeywords: false).format(results: [study()])
        XCTAssertTrue(text.contains("\"(0010,0010)\" : \"MÜLLER^HANS\""), text)
    }

    func testFormatOptionAcceptsDicomJSON() throws {
        let cmd = try DICOMQuery.parse(["server", "--aet", "SCU", "--format", "dicom-json"])
        XCTAssertEqual(cmd.format, .dicomJSON)
        XCTAssertEqual(OutputFormat.allCases.map(\.rawValue), ["table", "json", "csv", "compact", "dicom-json"])
        XCTAssertEqual(OutputFormat.dicomJSON.asShared, .dicomJSON)
    }

    func testCSVHeaderDefaultIsTagsAndKeywordsOnRequest() throws {
        let tags = DICOMQuery.formatter(format: .csv, level: .study, csvKeywords: false).format(results: [study()])
        XCTAssertTrue(tags.hasPrefix("\"(0008,0005)\"") || tags.hasPrefix("(0008,0005)"), tags)
        let keywords = DICOMQuery.formatter(format: .csv, level: .study, csvKeywords: true).format(results: [study()])
        let header = try XCTUnwrap(keywords.components(separatedBy: "\n").first)
        XCTAssertEqual(header, "SpecificCharacterSet,StudyDate,ModalitiesInStudy,PatientName,PatientID,StudyInstanceUID,NumberOfStudyRelatedSeries")
        XCTAssertTrue(try DICOMQuery.parse(["server", "--aet", "SCU", "--csv-keywords"]).csvKeywords)
    }

    /// Column labels per PS3.6 2026a Table 6-1 Attribute Names (dumped by
    /// Scripts/nema_docbook.py), and the value columns stay aligned under them.
    func testTableLabelsArePS36AttributeNames() {
        func header(_ level: QueryLevel) -> String {
            let text = DICOMQueryResultFormatter(format: .table, level: level)
                .format(results: [GenericQueryResult(attributes: [.patientName: Data("X".utf8)], level: level)])
            return text.components(separatedBy: "\n")[1]
        }
        let expected: [QueryLevel: [String]] = [
            .patient: ["Patient's Name", "Patient ID", "Patient's Birth Date", "Patient's Sex",
                       "Number of Patient Related Studies"],
            .study: ["Patient's Name", "Patient ID", "Study Date", "Study Description", "Modalities in Study",
                     "Number of Study Related Series"],
            .series: ["Series Number", "Modality", "Series Description", "Series Date",
                      "Number of Series Related Instances"],
            .image: ["Instance Number", "SOP Class UID", "Columns × Rows", "Number of Frames"],
        ]
        for (level, labels) in expected {
            let line = header(level)
            for label in labels { XCTAssertTrue(line.contains(label), "\(level): \(line)") }
        }
        XCTAssertFalse(header(.image).contains("Dimensions"))
        XCTAssertFalse(header(.study).contains(" Modalities  "))
        // Rule length equals the header width.
        let study = DICOMQueryResultFormatter(format: .table, level: .study).format(results: [self.study()])
        let lines = study.components(separatedBy: "\n")
        XCTAssertEqual(lines[0].count, lines[1].count, study)
        XCTAssertTrue(lines[3].hasPrefix("MÜLLER^HANS"), study)
    }
}
