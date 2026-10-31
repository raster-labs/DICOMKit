import XCTest
import ArgumentParser
import DICOMWeb
@testable import dicom_wado

final class QIDOOutgoingResourceTests: XCTestCase {
    func testRealParserBuildsSixResourceFormsWithExactKeys() throws {
        let rows: [([String], String, [String: String])] = [
            (["--level", "study", "--study-date=-20261024", "--modality", "CT"], "/studies", ["00080020": "-20261024", "00080061": "CT"]),
            (["--level", "series", "--study-date", "20261024-", "--modality", "CT", "--pps-start-time=-120000"], "/series", ["00080020": "20261024-", "00080060": "CT", "00400245": "-120000"]),
            (["--level", "series", "--study", "2.25.1", "--modality", "CT"], "/studies/2.25.1/series", ["00080060": "CT"]),
            (["--level", "instance", "--study-date", "20261024", "--modality", "MR", "--sps-id", "SPS*"], "/instances", ["00080020": "20261024", "00080060": "MR", "00400275.00400009": "SPS*"]),
            (["--level", "instance", "--study", "2.25.1", "--modality", "MR", "--requested-procedure-id", "RP?"], "/studies/2.25.1/instances", ["00080060": "MR", "00400275.00401001": "RP?"]),
            (["--level", "instance", "--study", "2.25.1", "--series", "2.25.2"], "/studies/2.25.1/series/2.25.2/instances", [:]),
        ]
        for (options, path, expectedFilters) in rows {
            let command = try QueryCommand.parse(["http://127.0.0.1:1/dicom-web", "--patient-name", "Müller^*", "--patient-id", "PAT?"] + options)
            let request = try command.buildRequest()
            XCTAssertEqual(request.path, path)
            var expected = expectedFilters
            expected.merge(["00100010": "Müller^*", "00100020": "PAT?", "limit": "100", "offset": "0"]) { _, new in new }
            XCTAssertEqual(request.query.toParameters(), expected)
        }
    }

    func testUnsupportedScopeRefusesBeforeURLConfigurationOrDispatch() async throws {
        let cases: [[String]] = [
            ["--level", "instance", "--study", "2.25.1", "--series", "2.25.2", "--modality", "CT"],
            ["--level", "series", "--study", "2.25.1", "--study-date", "20261024"],
            ["--level", "instance", "--study", "2.25.1", "--accession-number", "ACC"],
            ["--level", "study", "--pps-start-date", "20261024"],
            ["--level", "study", "--pps-start-time", "120000"],
            ["--level", "study", "--sps-id", "SPS"],
            ["--level", "study", "--requested-procedure-id", "RP"],
        ]
        for options in cases {
            // This URL is deliberately unusable. The scope refusal must precede
            // even configuration; no test network connection is needed.
            let command = try QueryCommand.parse(["http://["] + options)
            do {
                try await command.run()
                XCTFail("accepted \(options)")
            } catch {
                XCTAssertTrue(error is ValidationError, "\(error)")
                XCTAssertTrue(String(describing: error).contains("not permitted"))
                XCTAssertEqual(QueryCommand.exitCode(for: error).rawValue, 64)
            }
        }
    }

    func testRelationalInstancePPSKeysAreAcceptedWithoutIgnoredBehavior() throws {
        for scope in [[], ["--study", "2.25.1"]] {
            let command = try QueryCommand.parse(["http://h", "--level", "instance",
                "--pps-start-date=-20261024", "--pps-start-time", "080000-",
                "--sps-id", "SPS*", "--requested-procedure-id", "RP?"] + scope)
            let p = try command.buildQuery().toParameters()
            XCTAssertEqual(p["00400244"], "-20261024")
            XCTAssertEqual(p["00400245"], "080000-")
            XCTAssertEqual(p["00400275.00400009"], "SPS*")
            XCTAssertEqual(p["00400275.00401001"], "RP?")
        }
    }

    func testUIDListOptionsAreQueriesRatherThanPathComponents() throws {
        let request = try QueryCommand.parse(["http://h", "--level", "instance", "--study", "2.25.1,2.25.2",
                                             "--series", "2.25.3,2.25.4"]).buildRequest()
        XCTAssertEqual(request.path, "/instances")
        XCTAssertEqual(request.query.toParameters()["0020000D"], "2.25.1,2.25.2")
        XCTAssertEqual(request.query.toParameters()["0020000E"], "2.25.3,2.25.4")
    }
}
