import XCTest
import Foundation
import DICOMCore
import DICOMKit

/// D116-D118 (2026-10-01): the shared study engine against the 2026a text.
/// - Labels are PS3.6 2026a Table 6-1 names.
/// - A file without Series Instance UID (0020,000E) or SOP Instance UID (0008,0018) — Type 1 in
///   PS3.3 Tables C.7-5a / C.12-1 — is reported as skipped, not merged under a placeholder.
/// - `organize --pattern descriptive` gives every series its own folder even when Series Number
///   (Type 2, Table C.7-5a), Modality and Series Description are equal.
final class StudyEngineStandardTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("study-std-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, study: String?, series: String?, sop: String?,
                       seriesNumber: String? = nil, modality: String? = "CT", seriesDescription: String? = nil,
                       in folder: URL? = nil) throws {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        if let sop { ds.setString(sop, for: .sopInstanceUID, vr: .UI) }
        if let study { ds.setString(study, for: .studyInstanceUID, vr: .UI) }
        if let series { ds.setString(series, for: .seriesInstanceUID, vr: .UI) }
        if let seriesNumber { ds.setString(seriesNumber, for: .seriesNumber, vr: .IS) }
        if let modality { ds.setString(modality, for: .modality, vr: .CS) }
        if let seriesDescription { ds.setString(seriesDescription, for: .seriesDescription, vr: .LO) }
        ds.setString("DOE^JANE", for: .patientName, vr: .PN)
        ds.setString("P1", for: .patientID, vr: .LO)
        ds.setString("HEAD", for: .studyDescription, vr: .LO)
        // DICOMFile.create fills an absent SOP Instance UID, so the no-SOP fixture keeps the
        // created File Meta and drops (0008,0018) from the data set afterwards.
        let created = DICOMFile.create(dataSet: ds)
        var body = created.dataSet
        if sop == nil { body.remove(tag: .sopInstanceUID) }
        try DICOMFile(fileMetaInformation: created.fileMetaInformation, dataSet: body).write()
            .write(to: (folder ?? dir).appendingPathComponent(name))
    }

    // MARK: D116

    func testSummaryAndStatsLabelsArePS36Names() throws {
        try write("a.dcm", study: "1.2.3", series: "1.2.3.1", sop: "1.2.3.1.1", seriesNumber: "4", seriesDescription: "AX")
        let studies = StudyScanner.scanStudies(at: dir.path)
        let table = try StudyReport.renderSummary(studies: studies, format: "table", verbose: true)
        for label in ["Study Instance UID: 1.2.3", "Patient's Name: DOE^JANE", "Patient ID: P1",
                      "Study Description: HEAD", "Number of Study Related Series: 1",
                      "Number of Study Related Instances: 1", "Series Number: 4", "Modality: CT",
                      "Series Description: AX", "Number of Series Related Instances: 1"] {
            XCTAssertTrue(table.contains(label), "missing \(label) in\n\(table)")
        }
        for old in ["Study UID:", "Patient Name:", "Series Count:", "Total Instances:", "      Number: 4", "      Description: AX"] {
            XCTAssertFalse(table.contains(old), "old label \(old) still printed")
        }
        let stats = try StudyReport.renderStats(StudyReport.computeStatistics(for: studies[0], detailed: false),
                                                detailed: false, format: "text")
        XCTAssertTrue(stats.contains("Study Instance UID: 1.2.3"))
        XCTAssertTrue(stats.contains("Number of Study Related Series: 1"))
        XCTAssertTrue(stats.contains("Number of Study Related Instances: 1"))
    }

    // MARK: D118

    func testFilesWithoutSeriesOrSOPInstanceUIDAreReportedNotMerged() throws {
        try write("ok.dcm", study: "1.2.3", series: "1.2.3.1", sop: "1.2.3.1.1")
        try write("noseries1.dcm", study: "1.2.3", series: nil, sop: "1.2.3.9.1")
        try write("noseries2.dcm", study: "1.2.3", series: nil, sop: "1.2.3.9.2")
        try write("nosop.dcm", study: "1.2.3", series: "1.2.3.1", sop: nil)
        let result = StudyScanner.scan(at: dir.path)
        XCTAssertEqual(result.studies.count, 1)
        XCTAssertEqual(result.studies[0].series.map(\.seriesInstanceUID), ["1.2.3.1"])
        XCTAssertEqual(result.studies[0].totalInstances, 1)
        XCTAssertFalse(result.studies[0].series.contains { $0.seriesInstanceUID == "UNKNOWN" })
        let reasons = Dictionary(uniqueKeysWithValues: result.skipped.map {
            (URL(fileURLWithPath: $0.path).lastPathComponent, $0.reason)
        })
        XCTAssertEqual(reasons["noseries1.dcm"], "no Series Instance UID (0020,000E)")
        XCTAssertEqual(reasons["noseries2.dcm"], "no Series Instance UID (0020,000E)")
        XCTAssertEqual(reasons["nosop.dcm"], "no SOP Instance UID (0008,0018)")
        XCTAssertEqual(StudyScanner.scanStudies(at: dir.path).first?.totalInstances, 1)
    }

    func testOrganizeSkipsAFileWithoutSeriesInstanceUIDWithAWarning() throws {
        let input = dir.appendingPathComponent("in")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try write("ok.dcm", study: "1.2.3", series: "1.2.3.1", sop: "1.2.3.1.1", in: input)
        try write("noseries.dcm", study: "1.2.3", series: nil, sop: "1.2.3.9.1", in: input)
        var lines: [String] = []
        let out = dir.appendingPathComponent("out").path
        let r = try StudyOrganizer().organize(inputPath: input.path, outputPath: out, pattern: "uid",
                                              copy: true, verbose: false, log: { lines.append($0) })
        XCTAssertEqual(r.copied, 1)
        XCTAssertTrue(lines.contains { $0.contains("Missing Series Instance UID (0020,000E)") && $0.contains("noseries.dcm") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(out)/1.2.3/UNKNOWN_SERIES"))
    }

    // MARK: D117

    func testDescriptiveSeriesFoldersStayUniqueWhenTheirNamesCollide() throws {
        let input = dir.appendingPathComponent("in")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        // Two series without Series Number (Type 2) and with the same Modality/Description,
        // plus one series whose name is unique.
        try write("a.dcm", study: "1.2.3", series: "1.2.3.1", sop: "1.2.3.1.1", in: input)
        try write("b.dcm", study: "1.2.3", series: "1.2.3.2", sop: "1.2.3.2.1", in: input)
        try write("c.dcm", study: "1.2.3", series: "1.2.3.3", sop: "1.2.3.3.1", seriesNumber: "5",
                  seriesDescription: "SAG", in: input)
        let out = dir.appendingPathComponent("out")
        let r = try StudyOrganizer().organize(inputPath: input.path, outputPath: out.path, pattern: "descriptive",
                                              copy: true, verbose: false, log: { _ in })
        XCTAssertEqual(r.copied, 3)
        let studyDir = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: out.path).first)
        let seriesDirs = try FileManager.default.contentsOfDirectory(atPath: out.appendingPathComponent(studyDir).path).sorted()
        XCTAssertEqual(seriesDirs, ["0_CT_Unknown_1.2.3.1", "0_CT_Unknown_1.2.3.2", "5_CT_SAG"])
    }
}
