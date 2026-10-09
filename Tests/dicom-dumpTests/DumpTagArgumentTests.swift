import XCTest
import DICOMCore
@testable import dicom_dump

/// `--tag` / `--highlight` take (gggg,eeee) or a PS3.6 2026a keyword (exact);
/// `--length` and `--bytes-per-line` are range-checked (a negative length used to trap,
/// a zero line width used to loop forever).
final class DumpTagArgumentTests: XCTestCase {

    func testHexForms() throws {
        XCTAssertEqual(try DICOMDump.parseTagArgument("0010,0010"), Tag(group: 0x0010, element: 0x0010))
        XCTAssertEqual(try DICOMDump.parseTagArgument("(7FE0,0010)"), Tag(group: 0x7FE0, element: 0x0010))
        XCTAssertEqual(try DICOMDump.parseTagArgument("00080060"), Tag(group: 0x0008, element: 0x0060))
    }

    func testPS36Keywords() throws {
        XCTAssertEqual(try DICOMDump.parseTagArgument("PatientName"), Tag(group: 0x0010, element: 0x0010))
        XCTAssertEqual(try DICOMDump.parseTagArgument("TransferSyntaxUID"), Tag(group: 0x0002, element: 0x0010))
        XCTAssertEqual(try DICOMDump.parseTagArgument("PixelData"), Tag(group: 0x7FE0, element: 0x0010))
        XCTAssertThrowsError(try DICOMDump.parseTagArgument("patientname"))
        XCTAssertThrowsError(try DICOMDump.parseTagArgument("0010"))
    }

    func testRangeChecks() {
        XCTAssertThrowsError(try DICOMDump.parse(["f.dcm", "--length=-1"]))
        XCTAssertThrowsError(try DICOMDump.parse(["f.dcm", "--bytes-per-line", "0"]))
        XCTAssertNoThrow(try DICOMDump.parse(["f.dcm", "--length", "0", "--bytes-per-line", "8"]))
    }
}
