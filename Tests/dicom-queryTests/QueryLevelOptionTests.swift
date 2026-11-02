import XCTest
import DICOMNetwork
@testable import dicom_query

/// `--level` pins the Query/Retrieve Level (0008,0052) values of PS3.4 2026a
/// Tables C.6.1-1 (Patient Root) and C.6.2-1 (Study Root): PATIENT, STUDY,
/// SERIES, IMAGE. The CLI word `instance` stays accepted as an alias of `image`;
/// the value sent on the wire is always the standard's IMAGE.
final class QueryLevelOptionTests: XCTestCase {

    func testStandardLevelWordsMapToTheirQueryRetrieveLevelValues() {
        XCTAssertEqual(QueryLevelOption(argument: "patient")?.queryLevel.rawValue, "PATIENT")
        XCTAssertEqual(QueryLevelOption(argument: "study")?.queryLevel.rawValue, "STUDY")
        XCTAssertEqual(QueryLevelOption(argument: "series")?.queryLevel.rawValue, "SERIES")
        XCTAssertEqual(QueryLevelOption(argument: "image")?.queryLevel.rawValue, "IMAGE")
    }

    func testInstanceIsAnAliasOfImage() {
        XCTAssertEqual(QueryLevelOption(argument: "instance"), .image)
        XCTAssertEqual(QueryLevelOption(argument: "INSTANCE"), .image)
        XCTAssertEqual(QueryLevelOption(argument: "instance")?.queryLevel, .image)
        XCTAssertEqual(QueryLevelOption(argument: "instance")?.queryLevel.rawValue, "IMAGE")
    }

    func testUnknownLevelIsRejected() {
        XCTAssertNil(QueryLevelOption(argument: "frame"))
        XCTAssertNil(QueryLevelOption(argument: ""))
    }

    func testEveryStandardLevelValueHasAnOption() {
        // PS3.4 Table C.6.1-1 lists the four values; C.6.2-1 the lower three.
        let wire = Set(QueryLevelOption.allCases.map { $0.queryLevel.rawValue })
        XCTAssertEqual(wire, ["PATIENT", "STUDY", "SERIES", "IMAGE"])
        XCTAssertEqual(QueryLevelOption.allValueStrings, ["patient", "study", "series", "image", "instance"])
    }

    func testHelpNamesTheImageLevel() throws {
        // ArgumentParser wraps help text, so compare with runs of whitespace collapsed.
        let help = DICOMQuery.helpMessage()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(help.contains("patient, study, series, image"), help)
        XCTAssertTrue(help.contains("(0008,0052)"), help)
        XCTAssertFalse(help.contains("SERIES/INSTANCE"), help)
    }

    func testImageLevelRequiresStudyAndSeriesUIDs() throws {
        XCTAssertThrowsError(try DICOMQuery.parse(["server", "--aet", "SCU", "--level", "image"]))
        XCTAssertThrowsError(try DICOMQuery.parse(["server", "--aet", "SCU", "--level", "instance", "--study-uid", "1.2"]))
        let ok = try DICOMQuery.parse(["server", "--aet", "SCU", "--level", "instance",
                                       "--study-uid", "1.2", "--series-uid", "1.2.3"])
        XCTAssertEqual(ok.level, .image)
    }

    func testUnsupportedFiltersAreRefusedBeforeDispatch() throws {
        let image = ["server", "--aet", "SCU", "--level", "instance",
                     "--study-uid", "1.2", "--series-uid", "1.2.3"]
        for filter in [["--patient-name", "DOE^J"], ["--modality", "CT"]] {
            XCTAssertThrowsError(try DICOMQuery.parse(image + filter)) { error in
                let text = String(describing: error)
                XCTAssertTrue(text.contains("at IMAGE level"), text)
                XCTAssertTrue(text.contains("No query was sent"), text)
                XCTAssertFalse(text.contains("will be ignored"), text)
            }
        }
        for filter in [["--study-date", "20260101-20260331"],
                       ["--study-description", "CHEST*"], ["--study-uid", "1.2"]] {
            XCTAssertThrowsError(try DICOMQuery.parse(["server", "--aet", "SCU", "--level", "patient"] + filter))
        }
        XCTAssertThrowsError(try DICOMQuery.parse(image + ["--modality", "CT", "--include-parent-keys"]))
    }

    func testAppliedFiltersReflectAcceptedWireKeysAndPreserveMatchingExpressions() throws {
        let study = try DICOMQuery.parse(["server", "--aet", "SCU", "--modality", "CT",
            "--study-date", "20260101-20260331", "--patient-name", "DOE*", "--study-description", "CHE?T*"])
        XCTAssertEqual(study.appliedFilters().map(\.value), ["DOE*", "20260101-20260331", "CT", "CHE?T*"])
        XCTAssertNil(study.buildQueryKeys().rejectionReason)
        let series = try DICOMQuery.parse(["server", "--aet", "SCU", "--level", "series",
            "--study-uid", "1.2", "--modality", "CT", "--include-parent-keys"])
        XCTAssertEqual(series.appliedFilters().map(\.value), ["CT", "1.2"])
    }
}
