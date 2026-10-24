import XCTest
@testable import DICOMWeb

final class QIDOResourcePolicyTests: XCTestCase {
    func testResourceIETruthTableFromPS318() {
        // Independent matrix: PS3.18 2026a 10.6.1.2.1 / Table 10.6.1-4.
        let rows: [(QIDOResource, Bool, Bool, Bool)] = [
            (.allStudies, true, false, false), (.studySeries, false, true, false),
            (.studyInstances, false, true, true), (.allSeries, true, true, false),
            (.studySeriesInstances, false, false, true), (.allInstances, true, true, true),
        ]
        for (resource, study, series, instance) in rows {
            XCTAssertTrue(resource.allows(.patient), resource.rawValue)
            XCTAssertEqual(resource.allows(.study), study, resource.rawValue)
            XCTAssertEqual(resource.allows(.series), series, resource.rawValue)
            XCTAssertEqual(resource.allows(.instance), instance, resource.rawValue)
        }
    }

    func testSixRoutesNeverDuplicatePathUIDsAsParentFilters() throws {
        let rows: [(String, String?, String?, QIDOResource, String)] = [
            ("study", nil, nil, .allStudies, "/studies"),
            ("series", nil, nil, .allSeries, "/series"),
            ("series", "2.25.1", nil, .studySeries, "/studies/2.25.1/series"),
            ("instance", nil, nil, .allInstances, "/instances"),
            ("instance", "2.25.1", nil, .studyInstances, "/studies/2.25.1/instances"),
            ("instance", "2.25.1", "2.25.2", .studySeriesInstances, "/studies/2.25.1/series/2.25.2/instances"),
        ]
        for (level, study, series, resource, path) in rows {
            let request = try QIDORequest(level: level, studyUID: study, seriesUID: series,
                                          query: QIDOQuery().patientName("Müller^*").patientID("PAT?"))
            XCTAssertEqual(request.resource, resource)
            XCTAssertEqual(request.path, path)
            XCTAssertEqual(request.query.toParameters(), ["00100010": "Müller^*", "00100020": "PAT?"])
        }
    }

    func testModalityIsStudyOrSeriesAttributeAndIsRejectedForSeriesInstances() throws {
        XCTAssertEqual(try QIDORequest(level: "study", modality: "CT").query.toParameters(), ["00080061": "CT"])
        for (level, study) in [("series", nil), ("series", "2.25.1"), ("instance", nil), ("instance", "2.25.1")] as [(String, String?)] {
            XCTAssertEqual(try QIDORequest(level: level, studyUID: study, modality: "CT").query.toParameters(), ["00080060": "CT"])
        }
        XCTAssertThrowsError(try QIDORequest(level: "instance", studyUID: "2.25.1", seriesUID: "2.25.2", modality: "CT")) {
            XCTAssertEqual(($0 as? DICOMwebOptionRefusal)?.exitCode, 64)
            XCTAssertTrue($0.localizedDescription.contains("--modality"))
            XCTAssertTrue($0.localizedDescription.contains("PS3.18 10.6.1.2.1"))
        }
    }

    func testScopeRefusesEveryUnsupportedKnownFilterRatherThanDroppingIt() throws {
        let studyKeys = ["00080020", "00080050", "00081030", "00080061"]
        let seriesKeys = ["00400244", "00400245", "00400275.00400009", "00400275.00401001"]
        for key in studyKeys {
            for level in ["series", "instance"] {
                XCTAssertThrowsError(try QIDORequest(level: level, studyUID: "2.25.1", query: QIDOQuery(parameters: [key: "X"])))
            }
        }
        for key in seriesKeys {
            XCTAssertThrowsError(try QIDORequest(level: "study", query: QIDOQuery(parameters: [key: "X"])))
            XCTAssertThrowsError(try QIDORequest(level: "instance", studyUID: "2.25.1", seriesUID: "2.25.2", query: QIDOQuery(parameters: [key: "X"])))
            XCTAssertNoThrow(try QIDORequest(level: "instance", query: QIDOQuery(parameters: [key: "X"])))
            XCTAssertNoThrow(try QIDORequest(level: "instance", studyUID: "2.25.1", query: QIDOQuery(parameters: [key: "X"])))
        }
        XCTAssertThrowsError(try QIDORequest(level: "study", seriesUID: "2.25.2"))
    }

    func testUIDListsRemainPredicatesAndMatchingExpressionsArePreserved() throws {
        let query = QIDOQuery().patientName("Müller^*").studyDate("-20261024")
            .performedProcedureStepStartTime("080000-").scheduledProcedureStepID("SPS?")
        let request = try QIDORequest(level: "instance", studyUID: "2.25.1,2.25.2", seriesUID: "2.25.3,2.25.4", query: query)
        XCTAssertEqual(request.resource, .allInstances)
        XCTAssertEqual(request.path, "/instances")
        XCTAssertEqual(request.query.toParameters(), ["00100010": "Müller^*", "00080020": "-20261024",
            "00400245": "080000-", "00400275.00400009": "SPS?", "0020000D": "2.25.1,2.25.2", "0020000E": "2.25.3,2.25.4"])
        let studyScoped = try QIDORequest(level: "instance", studyUID: "2.25.1", seriesUID: "2.25.3,2.25.4")
        XCTAssertEqual(studyScoped.resource, .studyInstances)
        XCTAssertEqual(studyScoped.query.toParameters(), ["0020000E": "2.25.3,2.25.4"])
        for invalid in ["1..2", "1.02", "2.25.1,", ",2.25.1", "2.25.1/series", "2.25.*"] {
            XCTAssertThrowsError(try QIDORequest(level: "series", studyUID: invalid), invalid)
        }
    }
}
