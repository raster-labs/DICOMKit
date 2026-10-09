import XCTest
import Foundation
import DICOMCore
import DICOMKit

/// D120-D125, D209 (2026-10-01): DICOMKit ArchiveStore against the 2026a text.
/// - PS3.4 C.2.2.2.4: wild cards are case-sensitive except for PN.
/// - PS3.4 C.2.2.2.2 List of UID Matching; C.2.2.2.5.1 DA Range Matching.
/// - The study's modality is Modalities in Study (0008,0061) from all series (PS3.4 Table C.6-5).
/// - Labels are PS3.6 2026a Table 6-1 names; SOP Classes are named from Table A-1.
/// - Patients are keyed on Patient ID + Issuer of Patient ID (0010,0021); an empty Patient ID
///   (Type 2) does not merge different patients.
final class ArchiveMatchingStandardTests: XCTestCase {

    private var dir: URL!
    private var archive: String { dir.appendingPathComponent("archive").path }
    private var counter = 0

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("archive-std-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try ArchiveStore.initArchive(at: archive, force: false)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    @discardableResult
    private func importInstance(patientName: String, patientID: String?, issuer: String? = nil,
                                study: String, series: String, modality: String,
                                studyDate: String? = nil) throws -> String {
        counter += 1
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("\(series).\(counter)", for: .sopInstanceUID, vr: .UI)
        ds.setString(study, for: .studyInstanceUID, vr: .UI)
        ds.setString(series, for: .seriesInstanceUID, vr: .UI)
        ds.setString(modality, for: .modality, vr: .CS)
        ds.setString(patientName, for: .patientName, vr: .PN)
        if let patientID { ds.setString(patientID, for: .patientID, vr: .LO) }
        if let issuer { ds.setString(issuer, for: Tag(group: 0x0010, element: 0x0021), vr: .LO) }
        if let studyDate { ds.setString(studyDate, for: .studyDate, vr: .DA) }
        let url = dir.appendingPathComponent("f\(counter).dcm")
        try DICOMFile.create(dataSet: ds).write().write(to: url)
        return try ArchiveStore.importFiles(into: archive, files: [url.path], recursive: false,
                                            skipDuplicates: true, verbose: false)
    }

    private func studyUIDs(patientName: String? = nil, patientID: String? = nil, studyUID: String? = nil,
                           modality: String? = nil, studyDate: String? = nil) throws -> [String] {
        let json = try ArchiveStore.query(in: archive, patientName: patientName, patientID: patientID,
                                          studyUID: studyUID, modality: modality, studyDate: studyDate, format: "json")
        guard json.hasPrefix("[") else { return [] }
        let items = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        return items.compactMap { $0["studyInstanceUID"] as? String }.sorted()
    }

    // MARK: D120 — C.2.2.2.4 case rules by VR

    func testMatchingFunctionCaseRules() {
        XCTAssertTrue(ArchiveMatching.matches("doe*", "DOE^JANE", caseSensitive: false))   // PN
        XCTAssertFalse(ArchiveMatching.matches("ab*", "AB123", caseSensitive: true))        // LO
        XCTAssertTrue(ArchiveMatching.matches("AB?23", "AB123", caseSensitive: true))
        XCTAssertFalse(ArchiveMatching.matches("ab123", "AB123", caseSensitive: true))      // C.2.2.2.1
        XCTAssertTrue(ArchiveMatching.matches("", "anything", caseSensitive: true))          // C.2.2.2.3
        XCTAssertTrue(ArchiveMatching.matches("*", "", caseSensitive: true))
    }

    func testPatientIDWildCardsAreCaseSensitiveAndPatientsNameIsNot() throws {
        try importInstance(patientName: "DOE^JANE", patientID: "AB123", study: "1.2.1", series: "1.2.1.1", modality: "CT")
        XCTAssertEqual(try studyUIDs(patientID: "AB*"), ["1.2.1"])
        XCTAssertEqual(try studyUIDs(patientID: "ab*"), [])
        XCTAssertEqual(try studyUIDs(patientName: "doe*"), ["1.2.1"])
    }

    // MARK: D121 — C.2.2.2.2 / C.2.2.2.5.1

    func testListOfUIDMatchingInQueryAndExport() throws {
        try importInstance(patientName: "A", patientID: "P1", study: "1.2.1", series: "1.2.1.1", modality: "CT")
        try importInstance(patientName: "A", patientID: "P1", study: "1.2.2", series: "1.2.2.1", modality: "CT")
        try importInstance(patientName: "A", patientID: "P1", study: "1.2.3", series: "1.2.3.1", modality: "CT")
        XCTAssertEqual(try studyUIDs(studyUID: "1.2.1\\1.2.3"), ["1.2.1", "1.2.3"])
        XCTAssertEqual(try studyUIDs(studyUID: "1.2.2"), ["1.2.2"])
        let out = dir.appendingPathComponent("out").path
        let report = try ArchiveStore.export(from: archive, output: out, studyUID: nil, seriesUID: "1.2.1.1\\1.2.2.1",
                                             patientID: nil, flatten: true, verbose: false)
        XCTAssertTrue(report.contains("Exported: 2 file(s)"), report)
    }

    func testDARangeMatching() throws {
        try importInstance(patientName: "A", patientID: "P1", study: "1.2.1", series: "1.2.1.1", modality: "CT", studyDate: "20240105")
        try importInstance(patientName: "A", patientID: "P1", study: "1.2.2", series: "1.2.2.1", modality: "CT", studyDate: "20240201")
        try importInstance(patientName: "A", patientID: "P1", study: "1.2.3", series: "1.2.3.1", modality: "CT")
        XCTAssertEqual(try studyUIDs(studyDate: "20240101-20240131"), ["1.2.1"])
        XCTAssertEqual(try studyUIDs(studyDate: "20240105-20240201"), ["1.2.1", "1.2.2"])   // inclusive
        XCTAssertEqual(try studyUIDs(studyDate: "-20240105"), ["1.2.1"])
        XCTAssertEqual(try studyUIDs(studyDate: "20240106-"), ["1.2.2"])
        XCTAssertEqual(try studyUIDs(studyDate: "20240201"), ["1.2.2"])
        XCTAssertNil(ArchiveMatching.dateRange("20240131-20240101"))   // <date1> must be <= <date2>
    }

    // MARK: D122 / D209 — Modalities in Study in every surface

    func testTableAndTextShowModalitiesInStudyFromAllSeries() throws {
        try importInstance(patientName: "A", patientID: "P1", study: "1.2.1", series: "1.2.1.1", modality: "CT")
        try importInstance(patientName: "A", patientID: "P1", study: "1.2.1", series: "1.2.1.2", modality: "PT")
        for format in ["table", "text"] {
            let out = try ArchiveStore.query(in: archive, patientName: nil, patientID: nil, studyUID: nil,
                                             modality: nil, studyDate: nil, format: format)
            XCTAssertTrue(out.contains("Modalities in Study"), out)
            XCTAssertTrue(out.contains("CT\\PT"), out)
        }
        XCTAssertEqual(try studyUIDs(modality: "PT"), ["1.2.1"])
        XCTAssertEqual(try studyUIDs(modality: "P?"), ["1.2.1"])
        let index = try ArchiveStore.loadIndex(from: archive)
        XCTAssertEqual(index.patients.first?.studies.first?.modalitiesInStudy, ["CT", "PT"])
    }

    // MARK: D123 — PS3.6 labels, Table A-1 names

    func testLabelsArePS36Names() throws {
        try importInstance(patientName: "DOE^JANE", patientID: "P1", study: "1.2.1", series: "1.2.1.1", modality: "CT")
        let table = try ArchiveStore.query(in: archive, patientName: nil, patientID: nil, studyUID: nil,
                                           modality: nil, studyDate: nil, format: "table")
        for label in ["Patient's Name", "Patient ID", "Study Date", "Modalities in Study", "Study Description",
                      "Number of Study Related Series", "Number of Study Related Instances"] {
            XCTAssertTrue(table.contains(label), label)
        }
        XCTAssertFalse(table.contains("Images"))
        let text = try ArchiveStore.query(in: archive, patientName: nil, patientID: nil, studyUID: nil,
                                          modality: nil, studyDate: nil, format: "text")
        for label in ["Patient's Name: DOE^JANE", "Patient ID: P1", "Study Instance UID: 1.2.1",
                      "Number of Study Related Series: 1", "Number of Study Related Instances: 1"] {
            XCTAssertTrue(text.contains(label), label)
        }
        let list = try ArchiveStore.list(in: archive, format: "table", showInstances: false)
        for label in ["Patient's Name", "Number of Patient Related Studies", "Number of Patient Related Series",
                      "Number of Patient Related Instances"] {
            XCTAssertTrue(list.contains(label), label)
        }
        let stats = try ArchiveStore.stats(in: archive, format: "text")
        XCTAssertTrue(stats.contains("1.2.840.10008.5.1.4.1.1.7 (Secondary Capture Image Storage): 1"), stats)
    }

    // MARK: D124 — Patient ID + Issuer of Patient ID; empty Patient ID

    func testPatientsAreKeyedOnPatientIDAndIssuer() throws {
        try importInstance(patientName: "A^ONE", patientID: "123", issuer: "HOSP_A", study: "1.2.1", series: "1.2.1.1", modality: "CT")
        try importInstance(patientName: "B^TWO", patientID: "123", issuer: "HOSP_B", study: "1.2.2", series: "1.2.2.1", modality: "CT")
        try importInstance(patientName: "A^ONE", patientID: "123", issuer: "HOSP_A", study: "1.2.3", series: "1.2.3.1", modality: "CT")
        let index = try ArchiveStore.loadIndex(from: archive)
        XCTAssertEqual(index.patients.count, 2)
        XCTAssertEqual(index.patients.map(\.issuerOfPatientID), ["HOSP_A", "HOSP_B"])
        XCTAssertEqual(index.patients.map { $0.studies.count }, [2, 1])
        let text = try ArchiveStore.query(in: archive, patientName: "B*", patientID: nil, studyUID: nil,
                                          modality: nil, studyDate: nil, format: "text")
        XCTAssertTrue(text.contains("Issuer of Patient ID: HOSP_B"), text)
    }

    func testFilesWithoutPatientIDDoNotMergeDifferentPatients() throws {
        try importInstance(patientName: "X^ONE", patientID: nil, study: "1.2.1", series: "1.2.1.1", modality: "CT")
        try importInstance(patientName: "Y^TWO", patientID: "", study: "1.2.2", series: "1.2.2.1", modality: "CT")
        try importInstance(patientName: "X^ONE", patientID: nil, study: "1.2.3", series: "1.2.3.1", modality: "CT")
        let index = try ArchiveStore.loadIndex(from: archive)
        XCTAssertEqual(index.patients.map(\.patientName).sorted(), ["X^ONE", "Y^TWO"])
        XCTAssertEqual(index.patients.first { $0.patientName == "X^ONE" }?.studies.count, 2)
    }

    func testIndexWithoutIssuerStillLoads() throws {
        let old = """
        {"version":"1.2.1","creationDate":"2026-01-01T00:00:00Z","lastModified":"2026-01-01T00:00:00Z","fileCount":0,
         "patients":[{"patientName":"DOE^JANE","patientID":"P7","studies":[]}]}
        """
        let index = try JSONDecoder().decode(ArchiveIndex.self, from: Data(old.utf8))
        XCTAssertNil(index.patients.first?.issuerOfPatientID)
    }
}
