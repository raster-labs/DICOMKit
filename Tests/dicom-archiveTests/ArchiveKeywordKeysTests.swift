import XCTest
import Foundation
import DICOMCore
import DICOMKit
@testable import dicom_archive

/// P-ARCHIVE-1 (approved 2026-10-01): the archive index and query JSON carry the PS3.6 2026a
/// Table 6-1 keywords ModalitiesInStudy (0008,0061), NumberOfStudyRelatedSeries (0020,1206) and
/// NumberOfStudyRelatedInstances (0020,1208) (PS3.4 Table C.6-5) next to the deprecated
/// `modality`, `seriesCount` and `imageCount`; indexes written before keep loading.
final class ArchiveKeywordKeysTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("archive-keywords-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeInstance(_ name: String, series: String, sop: String, modality: String) throws -> String {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString(sop, for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.826.0.1.3680043.10.999.7", for: .studyInstanceUID, vr: .UI)
        ds.setString(series, for: .seriesInstanceUID, vr: .UI)
        ds.setString(modality, for: .modality, vr: .CS)
        ds.setString("DOE^JANE", for: .patientName, vr: .PN)
        ds.setString("P7", for: .patientID, vr: .LO)
        let url = dir.appendingPathComponent(name)
        try DICOMFile.create(dataSet: ds).write().write(to: url)
        return url.path
    }

    func testQueryJSONAndIndexCarryTheKeywordKeys() throws {
        let archive = dir.appendingPathComponent("archive").path
        _ = try ArchiveStore.initArchive(at: archive, force: false)
        let files = [
            try writeInstance("a.dcm", series: "1.2.826.0.1.3680043.10.999.7.1", sop: "1.2.826.0.1.3680043.10.999.7.1.1", modality: "CT"),
            try writeInstance("b.dcm", series: "1.2.826.0.1.3680043.10.999.7.1", sop: "1.2.826.0.1.3680043.10.999.7.1.2", modality: "CT"),
            try writeInstance("c.dcm", series: "1.2.826.0.1.3680043.10.999.7.2", sop: "1.2.826.0.1.3680043.10.999.7.2.1", modality: "PT"),
        ]
        _ = try ArchiveStore.importFiles(into: archive, files: files, recursive: false, skipDuplicates: true, verbose: false)

        let json = try ArchiveStore.query(in: archive, patientName: nil, patientID: nil, studyUID: nil,
                                          modality: nil, studyDate: nil, format: "json")
        let items = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let study = try XCTUnwrap(items.first)
        XCTAssertEqual(study["ModalitiesInStudy"] as? [String], ["CT", "PT"])
        XCTAssertEqual(study["NumberOfStudyRelatedSeries"] as? Int, 2)
        XCTAssertEqual(study["NumberOfStudyRelatedInstances"] as? Int, 3)
        // deprecated keys keep their former values
        XCTAssertEqual(study["modality"] as? String, "CT")
        XCTAssertEqual(study["seriesCount"] as? Int, 2)
        XCTAssertEqual(study["imageCount"] as? Int, 3)

        let indexURL = URL(fileURLWithPath: archive).appendingPathComponent("archive_index.json")
        let index = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any])
        let patients = try XCTUnwrap(index["patients"] as? [[String: Any]])
        let studies = try XCTUnwrap(patients.first?["studies"] as? [[String: Any]])
        XCTAssertEqual(studies.first?["ModalitiesInStudy"] as? [String], ["CT", "PT"])
        XCTAssertEqual(studies.first?["modality"] as? String, "CT")
    }

    func testIndexWithoutModalitiesInStudyStillLoads() throws {
        let old = """
        {"version":"1.2.1","creationDate":"2026-01-01T00:00:00Z","lastModified":"2026-01-01T00:00:00Z","fileCount":1,
         "patients":[{"patientName":"DOE^JANE","patientID":"P7","studies":[{"studyInstanceUID":"1.2.3","modality":"MR",
         "series":[{"seriesInstanceUID":"1.2.3.1","modality":"MR","instances":[]}]}]}]}
        """
        let index = try JSONDecoder().decode(ArchiveIndex.self, from: Data(old.utf8))
        let study = try XCTUnwrap(index.patients.first?.studies.first)
        XCTAssertEqual(study.modality, "MR")
        XCTAssertEqual(study.modalitiesInStudy, ["MR"])
    }
}
