import XCTest
@testable import dicom_study

/// `dicom-study` help against DICOM 2026a: grouping by the Study / Series level unique keys of
/// PS3.4 Tables C.6-2 / C.6-3, folder-name parts and counts named as in PS3.6 Table 6-1, and
/// the Instance Number gap check labelled a heuristic (PS3.3 Table C.7-9).
final class StudyHelpTests: XCTestCase {

    func testOrganizePatternNamesTheAttributes() throws {
        let help = DICOMStudy.Organize.helpMessage(columns: 400)
        for name in ["<Patient's Name>", "<Study Description>", "Study Instance UID", "<Series Number>",
                     "<Modality>", "<Series Description>", "<Series Instance UID>"] {
            XCTAssertTrue(help.contains(name), name)
        }
        XCTAssertEqual(try DICOMStudy.Organize.parse(["in", "--output", "out"]).pattern, "descriptive")
    }

    func testGroupingKeysAreTheUniqueKeys() {
        let help = DICOMStudy.helpMessage(columns: 400)
        XCTAssertTrue(help.contains("Study Instance UID (0020,000D)"))
        XCTAssertTrue(help.contains("Series Instance UID (0020,000E)"))
    }

    func testCheckSaysInstanceNumberGapsAreAHeuristic() {
        let help = DICOMStudy.Check.helpMessage(columns: 400)
        XCTAssertTrue(help.contains("Instance Number (0020,0013)"))
        XCTAssertTrue(help.contains("heuristic"))
        XCTAssertTrue(help.contains("Number of Study Related Series"))
        XCTAssertTrue(help.contains("Number of Series Related Instances"))
    }
}
