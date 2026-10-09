// ArchiveStudyDateWarningTests.swift
// DICOM 2026a deferred row D249: the `--study-date` warning of `dicom-archive query` and the
// DICOMStudio Workshop is ArchiveMatching.studyDateKeyWarning — nil for the DA value of
// PS3.5 2026a Table 6.2-1 and the three DA range forms of PS3.4 2026a C.2.2.2.5.1.

import XCTest
@testable import DICOMKit

final class ArchiveStudyDateWarningTests: XCTestCase {

    func testDAValueAndTheThreeRangeFormsOfC22251AreNotWarned() {
        XCTAssertNil(ArchiveMatching.studyDateKeyWarning(nil))
        XCTAssertNil(ArchiveMatching.studyDateKeyWarning(""), "zero-length key: Universal Matching")
        // C.2.2.2.5.1: "<date1> - <date2>", "- <date1>", "<date1> -".
        for value in ["20240101", "20240101-20240131", "-20240131", "20240101-", "20240101 - 20240131"] {
            XCTAssertNil(ArchiveMatching.studyDateKeyWarning(value), value)
            XCTAssertNotNil(ArchiveMatching.dateRange(value), value)
        }
    }

    func testOtherValuesAreWarnedWithTheCLIText() throws {
        for value in ["2024/01/01", "20240131-20240101", "2024-01-01", "2024", "abc"] {
            let warning = try XCTUnwrap(ArchiveMatching.studyDateKeyWarning(value), value)
            XCTAssertEqual(warning,
                           "warning: --study-date '\(value)' is neither a DA value (YYYYMMDD) nor a DA range "
                           + "(PS3.4 C.2.2.2.5.1); it matches only a Study Date (0008,0020) equal to the whole string")
            XCTAssertNil(ArchiveMatching.dateRange(value), value)
        }
    }

    func testOptionLabelIsSubstituted() {
        XCTAssertEqual(ArchiveMatching.studyDateKeyWarning("x", option: "StudyDate")?.hasPrefix("warning: StudyDate 'x' is neither"), true)
    }
}
