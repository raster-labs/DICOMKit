import XCTest
@testable import dicom_archive

/// `dicom-archive` query and export keys against PS3.4 2026a C.2.2.2: DICOMKit ArchiveStore now
/// performs Range Matching of Study Date (C.2.2.2.5.1) and List of UID Matching (C.2.2.2.2), so
/// only a Study Date that is neither a DA value nor a DA range is warned; the help names the
/// PS3.6 Table 6-1 attribute each key matches.
final class ArchiveQueryKeysTests: XCTestCase {

    func testSingleDAValueAndRangesHaveNoWarning() {
        XCTAssertNil(ArchiveQueryKeys.studyDateWarning(nil))
        // C.2.2.2.5.1: "<date1> - <date2>", "- <date1>", "<date1> -".
        for value in ["20240101", "20240101-20240131", "-20240131", "20240101-"] {
            XCTAssertNil(ArchiveQueryKeys.studyDateWarning(value), value)
        }
    }

    func testNonDAValueIsWarned() throws {
        for value in ["2024/01/01", "20240131-20240101", "2024-01-01"] {
            let warning = try XCTUnwrap(ArchiveQueryKeys.studyDateWarning(value), value)
            XCTAssertTrue(warning.contains("neither a DA value (YYYYMMDD) nor a DA range"), value)
            XCTAssertTrue(warning.contains("Study Date (0008,0020)"))
        }
    }

    func testQueryHelpNamesTheAttributes() {
        let help = DICOMArchive.Query.helpMessage(columns: 400)
        for name in ["Patient's Name (0010,0010)", "Patient ID (0010,0020)", "Study Instance UID (0020,000D)",
                     "Study Date (0008,0020)", "Modalities in Study (0008,0061)"] {
            XCTAssertTrue(help.contains(name), name)
        }
        XCTAssertTrue(help.contains("case-sensitive (PS3.4 C.2.2.2.4)"))
        XCTAssertTrue(help.contains("backslash-separated list (PS3.4 C.2.2.2.2)"))
        XCTAssertTrue(help.contains("PS3.4 C.2.2.2.5.1"))
        XCTAssertFalse(help.contains("exact match"))
    }

    func testExportHelpNamesTheAttributes() {
        let help = DICOMArchive.Export.helpMessage(columns: 400)
        for name in ["Study Instance UID (0020,000D)", "Series Instance UID (0020,000E)", "Patient ID (0010,0020)"] {
            XCTAssertTrue(help.contains(name), name)
        }
    }
}
