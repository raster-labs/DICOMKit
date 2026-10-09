import XCTest
import Foundation
import DICOMKit
@testable import dicom_split

/// P-SPLIT-1 (approved 2026-10-01): `--frame-numbers` selects frames by Frame number, numbered
/// from 1 (PS3.3 2026a C.7.6.16.1.2 "Frames are implicitly numbered starting from 1"; Table
/// 10-3); the 0-based `--frames` keeps its meaning and is deprecated.
final class SplitFrameNumbersTests: XCTestCase {

    func testFrameNumbersAreOneBased() throws {
        let command = try DICOMSplit.parse(["in.dcm", "--frame-numbers", "1,3,5-7"])
        XCTAssertEqual(try command.selectedFrameIndices(), [0, 2, 4, 5, 6])
        XCTAssertEqual(try SplitConsole.parseFrameNumberSelection("2,6,11-16"), [1, 5, 10, 11, 12, 13, 14, 15])
    }

    func testDeprecatedFramesKeepsItsZeroBasedMeaning() throws {
        let command = try DICOMSplit.parse(["in.dcm", "--frames", "1,5,10-15"])
        XCTAssertEqual(try command.selectedFrameIndices(), [1, 5, 10, 11, 12, 13, 14, 15])
        XCTAssertNil(try DICOMSplit.parse(["in.dcm"]).selectedFrameIndices())
    }

    func testFrameNumberZeroIsRejected() throws {
        let command = try DICOMSplit.parse(["in.dcm", "--frame-numbers", "0,1"])
        XCTAssertThrowsError(try command.selectedFrameIndices()) { error in
            XCTAssertTrue("\(error)".contains("Frame numbers start at 1"), "\(error)")
        }
    }

    func testBothOptionsExitOne() {
        XCTAssertThrowsError(try DICOMSplit.parse(["in.dcm", "--frames", "0", "--frame-numbers", "1"])) { error in
            XCTAssertEqual(DICOMSplit.message(for: error), SplitConsole.framesAndFrameNumbersConflictMessage)
            XCTAssertEqual(DICOMSplit.exitCode(for: error).rawValue, 1)
        }
    }

    func testHelpAndDeprecationNote() {
        let help = DICOMSplit.helpMessage(columns: 10_000)
        XCTAssertTrue(help.contains("--frame-numbers"))
        XCTAssertTrue(help.contains("deprecated: 0-based index; use --frame-numbers"))
        XCTAssertEqual(SplitConsole.framesDeprecatedLine,
                       "warning: --frames is deprecated (0-based index); use --frame-numbers (numbered from 1, PS3.3 C.7.6.16.1.2)")
    }

    func testVerboseBannerLabelsFrameNumbers() {
        let lines = SplitConsole.headerLines(input: "a", output: "b", format: .dicom, frames: nil,
                                             applyWindow: false, windowCenter: nil, windowWidth: nil,
                                             frameNumbers: "1,3")
        XCTAssertTrue(lines.contains("Frame numbers: 1,3"))
        XCTAssertEqual(SplitError.frameExtractionFailed(frameIndex: 0).description, "Failed to extract Frame number 1")
    }
}
