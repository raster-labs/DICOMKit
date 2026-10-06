import XCTest
import DICOMCore
@testable import DICOMKit
@testable import dicom_export

/// P-EXPORT-1 / -2 / -3 (approved 2026-10-01):
/// - frames are selected by Frame number, numbered from 1 (PS3.3 2026a Table 10-3 "The first Frame
///   shall be denoted as Frame number 1"); the 0-based options are deprecated;
/// - `bulk --organize-by patient` keys the patient folder on Patient ID (0010,0020) and Issuer of
///   Patient ID (0010,0021) (PS3.3 Table C.7-1 / Table 10-18);
/// - `--apply-window` on contact-sheet and bulk is deprecated (it has no effect there).
final class ExportPItemsTests: XCTestCase {

    // MARK: - P-EXPORT-1: single

    func testSingleFrameNumberIsOneBased() throws {
        XCTAssertEqual(try DICOMExport.Single.parse(["a.dcm", "--frame-number", "3"]).frameIndex, 2)
        XCTAssertEqual(try DICOMExport.Single.parse(["a.dcm"]).frameIndex, 0)
        // the deprecated 0-based option keeps its meaning
        XCTAssertEqual(try DICOMExport.Single.parse(["a.dcm", "--frame", "2"]).frameIndex, 2)
    }

    func testSingleRejectsFrameNumberZeroAndBothOptions() {
        XCTAssertThrowsError(try DICOMExport.Single.parse(["a.dcm", "--frame-number", "0"]))
        XCTAssertThrowsError(try DICOMExport.Single.parse(["a.dcm", "--frame", "1", "--frame-number", "2"])) { error in
            XCTAssertTrue(DICOMExport.message(for: error).contains("--frame (deprecated, 0-based) and --frame-number (numbered from 1) cannot be used together"))
            XCTAssertEqual(DICOMExport.exitCode(for: error).rawValue, 1, "refused with exit 1, not the usage exit 64")
        }
    }

    func testSingleHelpMarksFrameDeprecated() {
        let help = DICOMExport.Single.helpMessage(columns: 400)
        XCTAssertTrue(help.contains("--frame-number"))
        XCTAssertTrue(help.contains("deprecated: 0-based index; use --frame-number"))
    }

    func testDeprecationNoteAndOutOfRangeText() {
        XCTAssertEqual(DICOMImageExporter.FrameSelection.deprecationNote(option: "--frame", replacement: "--frame-number"),
                       "warning: --frame is deprecated (0-based index); use --frame-number (numbered from 1, PS3.3 Table 10-3: the first Frame is Frame number 1)")
        XCTAssertEqual(DICOMImageExporter.FrameSelection.invalidFrameNumberMessage(requested: 5, total: 3),
                       "Frame number 5 does not exist. The file has 3 frames, numbered 1 to 3.")
    }

    // MARK: - P-EXPORT-1: animate

    func testAnimateFrameNumberRange() throws {
        let numbers = try DICOMExport.Animate.parse(["c.dcm", "-o", "c.gif", "--start-frame-number", "11", "--end-frame-number", "51"])
        XCTAssertEqual(numbers.frameIndexRange.start, 10)
        XCTAssertEqual(numbers.frameIndexRange.end, 50)
        let legacy = try DICOMExport.Animate.parse(["c.dcm", "-o", "c.gif", "--start-frame", "10", "--end-frame", "50"])
        XCTAssertEqual(legacy.frameIndexRange.start, 10)
        XCTAssertEqual(legacy.frameIndexRange.end, 50)
        let whole = try DICOMExport.Animate.parse(["c.dcm", "-o", "c.gif"])
        XCTAssertEqual(whole.frameIndexRange.start, 0)
        XCTAssertNil(whole.frameIndexRange.end)
    }

    func testAnimateRefusesMixedOptions() {
        XCTAssertThrowsError(try DICOMExport.Animate.parse(["c.dcm", "-o", "c.gif", "--start-frame", "0", "--end-frame-number", "5"])) { error in
            XCTAssertTrue(DICOMExport.message(for: error).contains("--start-frame (deprecated, 0-based) and --end-frame-number"))
            XCTAssertEqual(DICOMExport.exitCode(for: error).rawValue, 1)
        }
        XCTAssertThrowsError(try DICOMExport.Animate.parse(["c.dcm", "-o", "c.gif", "--start-frame-number", "0"]))
        let help = DICOMExport.Animate.helpMessage(columns: 400)
        XCTAssertTrue(help.contains("deprecated: 0-based index; use --start-frame-number"))
        XCTAssertTrue(help.contains("deprecated: 0-based index; use --end-frame-number"))
    }

    // MARK: - P-EXPORT-2

    func testPatientFolderIsPatientIDPlusIssuer() {
        XCTAssertEqual(DICOMImageExporter.patientFolderName(patientID: "12345", issuerOfPatientID: nil), "12345")
        XCTAssertEqual(DICOMImageExporter.patientFolderName(patientID: "12345", issuerOfPatientID: "HOSP A"), "12345@HOSP_A")
        XCTAssertEqual(DICOMImageExporter.patientFolderName(patientID: "12345", issuerOfPatientID: " "), "12345")
        XCTAssertEqual(DICOMImageExporter.patientFolderName(patientID: nil, issuerOfPatientID: nil), "UNKNOWN")
        XCTAssertEqual(DICOMImageExporter.patientFolderName(patientID: "", issuerOfPatientID: "HOSP"), "UNKNOWN@HOSP")
    }

    func testOrganizedPathsUsePatientID() {
        func path(_ scheme: OrganizationScheme) -> String {
            DICOMImageExporter.buildOrganizedPath(baseOutput: "/out", scheme: scheme, patientID: "P1", issuerOfPatientID: "ISS",
                                                  studyUID: "1.2.3", seriesUID: "1.2.3.4", filename: "a.png")
        }
        XCTAssertEqual(path(.flat), "/out/a.png")
        XCTAssertEqual(path(.patient), "/out/P1@ISS/a.png")
        XCTAssertEqual(path(.study), "/out/P1@ISS/1.2.3/a.png")
        XCTAssertEqual(path(.series), "/out/P1@ISS/1.2.3/1.2.3.4/a.png")
    }

    func testBulkHelpNamesPatientID() {
        let help = DICOMExport.Bulk.helpMessage(columns: 400)
        XCTAssertTrue(help.contains("patient = Patient ID (0010,0020)"))
        XCTAssertTrue(help.contains("Issuer of Patient ID (0010,0021)"))
    }

    // MARK: - P-EXPORT-3

    func testApplyWindowIsDeprecatedOnContactSheetAndBulk() throws {
        XCTAssertTrue(DICOMExport.ContactSheet.helpMessage(columns: 400).contains("--apply-window      deprecated: no effect")
                      || DICOMExport.ContactSheet.helpMessage(columns: 400).contains("deprecated: no effect"))
        XCTAssertTrue(DICOMExport.Bulk.helpMessage(columns: 400).contains("deprecated: no effect"))
        XCTAssertTrue(try DICOMExport.Bulk.parse(["in", "-o", "out", "--apply-window"]).applyWindow, "still parses")
        XCTAssertTrue(DICOMImageExporter.ApplyWindowDeprecation.note(subcommand: "bulk").hasPrefix("warning: bulk --apply-window is deprecated"))
        // single and animate keep a working --apply-window
        XCTAssertFalse(DICOMExport.Single.helpMessage(columns: 400).contains("deprecated: no effect"))
    }
}
