import XCTest
import Foundation
import DICOMKit
@testable import dicom_study

/// P-STUDY-1 (approved 2026-10-01): summary CSV and stats / compare JSON carry the PS3.6 2026a
/// Table 6-1 keywords StudyInstanceUID (0020,000D), NumberOfStudyRelatedSeries (0020,1206),
/// NumberOfStudyRelatedInstances (0020,1208), ModalitiesInStudy (0008,0061) and
/// SeriesInstanceUID (0020,000E) next to the former, deprecated keys.
final class StudyKeywordKeysTests: XCTestCase {

    private func study(_ uid: String, series: [(String, String, Int)]) -> StudyMetadata {
        StudyMetadata(
            studyInstanceUID: uid, studyDate: "20261001", studyTime: nil, studyDescription: nil,
            patientName: "DOE^JANE", patientID: "P1", accessionNumber: nil,
            series: series.map { uid, modality, count in
                SeriesMetadata(seriesInstanceUID: uid, seriesNumber: "1", seriesDescription: nil, modality: modality,
                               instances: (0..<count).map {
                                   InstanceMetadata(sopInstanceUID: "\(uid).\($0)", instanceNumber: "\($0 + 1)",
                                                    filePath: "/x/\(uid).\($0)", fileSize: 10)
                               })
            })
    }

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func testSummaryCSVAppendsKeywordColumnsAndKeepsTheOldOnes() throws {
        let csv = try StudyReport.renderSummary(studies: [study("1.2.3", series: [("1.2.3.1", "CT", 2), ("1.2.3.2", "SR", 1)])],
                                                format: "csv", verbose: false)
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "StudyUID,StudyDate,PatientName,PatientID,SeriesCount,InstanceCount,StudyInstanceUID,NumberOfStudyRelatedSeries,NumberOfStudyRelatedInstances")
        XCTAssertEqual(lines[1], "1.2.3,20261001,DOE^JANE,P1,2,3,1.2.3,2,3")
    }

    func testStatsJSONCarriesKeywordKeysAndTheDeprecatedOnes() throws {
        let stats = StudyReport.computeStatistics(for: study("1.2.3", series: [("1.2.3.1", "CT", 2), ("1.2.3.2", "SR", 1)]), detailed: false)
        let json = try object(try StudyReport.renderStats(stats, detailed: false, format: "json"))
        XCTAssertEqual(json["StudyInstanceUID"] as? String, "1.2.3")
        XCTAssertEqual(json["NumberOfStudyRelatedSeries"] as? Int, 2)
        XCTAssertEqual(json["NumberOfStudyRelatedInstances"] as? Int, 3)
        XCTAssertEqual(json["ModalitiesInStudy"] as? [String], ["CT", "SR"])
        XCTAssertEqual(json["studyUID"] as? String, "1.2.3")
        XCTAssertEqual(json["seriesCount"] as? Int, 2)
        XCTAssertEqual(json["totalInstances"] as? Int, 3)
        // still decodes from the old keys
        let back = try JSONDecoder().decode(Statistics.self, from: try JSONEncoder().encode(stats))
        XCTAssertEqual(back.totalInstances, 3)
    }

    func testCompareJSONCarriesPerStudyKeywordObjects() throws {
        let a = study("1.2.3", series: [("1.2.3.1", "CT", 2)])
        let b = study("1.2.4", series: [("1.2.3.1", "CT", 1), ("1.2.4.2", "CT", 1)])
        let json = try object(try StudyReport.renderComparison(StudyReport.compareStudies(a, b), format: "json", verbose: false))
        let s1 = try XCTUnwrap(json["study1"] as? [String: Any])
        let s2 = try XCTUnwrap(json["study2"] as? [String: Any])
        XCTAssertEqual(s1["StudyInstanceUID"] as? String, "1.2.3")
        XCTAssertEqual(s1["NumberOfStudyRelatedSeries"] as? Int, 1)
        XCTAssertEqual(s1["NumberOfStudyRelatedInstances"] as? Int, 2)
        XCTAssertEqual(s2["StudyInstanceUID"] as? String, "1.2.4")
        XCTAssertEqual(s2["NumberOfStudyRelatedSeries"] as? Int, 2)
        XCTAssertEqual(json["study1UID"] as? String, "1.2.3")
        let diffs = try XCTUnwrap(json["seriesDifferences"] as? [[String: Any]])
        XCTAssertEqual(diffs.first?["SeriesInstanceUID"] as? String, "1.2.3.1")
        XCTAssertEqual(diffs.first?["seriesUID"] as? String, "1.2.3.1")
    }
}
