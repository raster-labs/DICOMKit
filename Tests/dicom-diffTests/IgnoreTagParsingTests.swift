import XCTest
import DICOMCore
@testable import dicom_diff

/// `dicom-diff --ignore-tag` values against DICOM 2026a: the Tag notation of the
/// PS3.6 Table 6-1 Tag column (PS3.5 7.1.1) and the Table 6-1 keywords.
final class IgnoreTagParsingTests: XCTestCase {

    // PS3.6 2026a Table 6-1: (0008,0018) SOP Instance UID, keyword SOPInstanceUID.
    private let sopInstanceUID = Tag(group: 0x0008, element: 0x0018)

    func testAcceptsTheNotationTheReportPrints() {
        // The text/JSON report prints tags as "(gggg,eeee)"; that form must round-trip.
        XCTAssertEqual(sopInstanceUID.description, "(0008,0018)")
        XCTAssertEqual(DICOMDiff.parseTag(sopInstanceUID.description), sopInstanceUID)
    }

    func testAcceptsCommaAndEightDigitForms() {
        XCTAssertEqual(DICOMDiff.parseTag("0008,0018"), sopInstanceUID)
        XCTAssertEqual(DICOMDiff.parseTag("00080018"), sopInstanceUID)
        XCTAssertEqual(DICOMDiff.parseTag("7fe0,0010"), Tag(group: 0x7FE0, element: 0x0010))
        // Short hex components were always accepted; keep them.
        XCTAssertEqual(DICOMDiff.parseTag("8,18"), sopInstanceUID)
    }

    func testAcceptsPS36Keywords() {
        // PS3.6 2026a Table 6-1 rows, dumped by script.
        XCTAssertEqual(DICOMDiff.parseTag("SOPInstanceUID"), sopInstanceUID)
        XCTAssertEqual(DICOMDiff.parseTag("PatientName"), Tag(group: 0x0010, element: 0x0010))
        XCTAssertEqual(DICOMDiff.parseTag("PatientBirthDate"), Tag(group: 0x0010, element: 0x0030))
        XCTAssertEqual(DICOMDiff.parseTag("PixelData"), Tag(group: 0x7FE0, element: 0x0010))
    }

    func testRejectsMalformedValues() {
        XCTAssertNil(DICOMDiff.parseTag("0008"))
        XCTAssertNil(DICOMDiff.parseTag("00080018FF"))
        XCTAssertNil(DICOMDiff.parseTag("(0008,0018"))
        XCTAssertNil(DICOMDiff.parseTag("0008,00180"))
        XCTAssertNil(DICOMDiff.parseTag("NotAKeyword"))
    }
}
