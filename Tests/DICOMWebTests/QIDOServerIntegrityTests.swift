import Foundation
import XCTest
import DICOMCore
import DICOMKit
@testable import DICOMWeb
import struct DICOMWeb.InstanceInfo

/// M3 server regression gates. The independent process/HTTP oracle separately
/// uses hand-encoded Part 10 files, so these fixtures do not supply that oracle.
final class QIDOServerIntegrityTests: XCTestCase {
    private func text(_ hex: String, _ vr: VR, _ value: String) -> DataElement {
        .string(tag: QIDOQueryRules.tag(hex), vr: vr, value: value)
    }
    private func sequence(_ items: [[DataElement]]) -> DataElement {
        DataElement(tag: QIDOQueryRules.tag("00400275"), vr: .SQ, length: .max,
                    valueData: Data(), sequenceItems: items.map { SequenceItem(elements: $0) })
    }
    private func attributes(_ elements: [DataElement]) -> [Tag: DataElement] {
        Dictionary(elements.map { ($0.tag, $0) }, uniquingKeysWith: { _, last in last })
    }
    private func rows(_ response: DICOMwebResponse) throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(response.body)) as? [[String: Any]])
    }
    private func fixture() async throws -> InMemoryStorageProvider {
        let storage = InMemoryStorageProvider()
        for (patient, study, series, instance, number) in [
            ("B", "1.2.2", "1.2.2.1", "1.2.2.1.1", Optional("3")),
            ("A", "1.2.1", "1.2.1.2", "1.2.1.2.1", nil),
            ("A", "1.2.1", "1.2.1.1", "1.2.1.1.1", Optional("+002"))
        ] {
            var elements = [text("00080005", .CS, "ISO_IR 192"), text("00100020", .LO, patient),
                text("00100010", .PN, "Müller^\(patient)"), text("00100030", .DA, "19800102"),
                text("0020000D", .UI, study), text("0020000E", .UI, series), text("00080018", .UI, instance),
                text("00080020", .DA, "20260115"), text("00080030", .TM, "093000"),
                text("00080050", .SH, "ACC-\(patient)"), text("00081030", .LO, "Study \(patient)"),
                text("00080201", .SH, "+0530"), text("00080056", .CS, "ONLINE"),
                text("00080060", .CS, patient == "A" ? "CT" : "MR"),
                text("00400244", .DA, "20260115"), text("00400245", .TM, "093000"),
                sequence([[text("00400009", .SH, "SPS-A"), text("00401001", .SH, "RP-X"), text("00321033", .LO, "Radiology")],
                          [text("00400009", .SH, "SPS-B"), text("00401001", .SH, "RP-Y")]])]
            if let number { elements.append(text("00200013", .IS, number)) }
            let data = try DICOMFile.create(dataSet: DataSet(elements: elements)).write()
            try await storage.storeInstance(data: data, studyUID: study, seriesUID: series, instanceUID: instance)
        }
        return storage
    }

    func testRawRequestPreservesRepeatedFieldsAndDecodesExactlyOnce() {
        let request = DICOMwebRequest(method: .get,
            path: "/series?includefield=PatientBirthDate&includefield=00400275%2E00321033&PatientID=A%2526B%2BC")
        XCTAssertEqual(request.path, "/series")
        XCTAssertEqual(request.queryItems.filter { $0.name == "includefield" }.map(\.value), ["PatientBirthDate", "00400275.00321033"])
        XCTAssertEqual(request.queryParameters["PatientID"], "A%26B+C")
        XCTAssertFalse(request.hasMalformedQueryEncoding)
        XCTAssertTrue(DICOMwebRequest(method: .get, path: "/studies?PatientID=%GG").hasMalformedQueryEncoding)
    }

    func testAllResourcesRejectMalformedPaginationAndDuplicatePredicates() async {
        let server = DICOMwebServer(configuration: DICOMwebServerConfiguration(pathPrefix: ""), storage: InMemoryStorageProvider())
        let paths = ["/studies", "/series", "/instances", "/studies/1.2/series", "/studies/1.2/instances", "/studies/1.2/series/1.2.3/instances"]
        for path in paths {
            for query in ["limit=-1", "offset=-1", "limit=NaN", "offset=1.1", "limit=9223372036854775808", "limit=1&limit=2", "PatientID=A&00100020=A", "PatientID=%GG", "UnsupportedField=x"] {
                let response = await server.handleRequest(.init(method: .get, path: path + "?" + query))
                XCTAssertEqual(response.statusCode, 400, path + "?" + query)
            }
            let response = await server.handleRequest(.init(method: .get, path: path + "?limit=0&offset=0"))
            XCTAssertEqual(response.statusCode, 200)
        }
    }

    func testDirectProviderPaginationIsBoundedAndStable() async throws {
        let storage = try await fixture()
        let ordered = try await storage.searchStudies(query: StorageQuery(limit: .max))
        XCTAssertEqual(ordered.map(\.studyInstanceUID), ["1.2.1", "1.2.2"])
        let series = try await storage.searchSeries(studyUID: nil, query: StorageQuery(limit: .max))
        XCTAssertEqual(series.map(\.seriesInstanceUID), ["1.2.1.1", "1.2.1.2", "1.2.2.1"])
        var missing = StorageQuery(); missing.matchingAttributes = ["00200013": "2"]
        let numbered = try await storage.searchInstances(studyUID: nil, seriesUID: nil, query: missing)
        XCTAssertEqual(numbered.map(\.sopInstanceUID), ["1.2.1.1.1"])
        let instances = try await storage.searchInstances(studyUID: nil, seriesUID: nil, query: StorageQuery(offset: 1, limit: .max))
        XCTAssertEqual(instances.map(\.sopInstanceUID), ["1.2.1.2.1", "1.2.2.1.1"])
        for query in [StorageQuery(offset: .max, limit: .max), StorageQuery(limit: 0)] {
            let a = try await storage.searchStudies(query: query)
            let b = try await storage.searchSeries(studyUID: nil, query: query)
            let c = try await storage.searchInstances(studyUID: nil, seriesUID: nil, query: query)
            XCTAssertTrue(a.isEmpty && b.isEmpty && c.isEmpty)
        }
        for query in [StorageQuery(offset: -1), StorageQuery(limit: -1)] {
            do { _ = try await storage.searchStudies(query: query); XCTFail("negative study pagination accepted") } catch {}
            do { _ = try await storage.searchSeries(studyUID: nil, query: query); XCTFail("negative series pagination accepted") } catch {}
            do { _ = try await storage.searchInstances(studyUID: nil, seriesUID: nil, query: query); XCTFail("negative instance pagination accepted") } catch {}
        }
        var malformed = StorageQuery(); malformed.matchingAttributes = ["not-a-tag": "x"]
        do { _ = try await storage.searchStudies(query: malformed); XCTFail("invalid direct predicate accepted") } catch {}
    }

    func testParentPredicatesUIDListsAndInstanceNumberAreConjunctive() async throws {
        let server = DICOMwebServer(configuration: DICOMwebServerConfiguration(pathPrefix: ""), storage: try await fixture())
        let cases: [(String, Int)] = [
            ("/series?PatientID=A&StudyInstanceUID=1.2.1%2C1.2.2&ModalitiesInStudy=CT", 2),
            ("/series?PatientID=B&StudyInstanceUID=1.2.1", 0),
            ("/instances?PatientID=A&SeriesInstanceUID=1.2.1.1,1.2.2.1&InstanceNumber=2", 1),
            ("/instances?00200013=2&SOPInstanceUID=1.2.1.1.1,1.2.2.1.1", 1),
            ("/instances?InstanceNumber=2&SOPInstanceUID=1.2.2.1.1", 0),
            ("/studies/1.2.1/series?PatientID=B", 0),
            ("/studies/1.2.1/instances?PatientID=A&SeriesInstanceUID=1.2.1.2", 1),
            ("/studies/1.2.1/series/1.2.1.1/instances?PatientID=B", 0)
        ]
        for (path, count) in cases {
            let response = await server.handleRequest(.init(method: .get, path: path))
            XCTAssertEqual(response.statusCode, 200, path)
            XCTAssertEqual(try rows(response).count, count, path)
            XCTAssertEqual(response.headers["X-Total-Count"], String(count), path)
        }
    }

    func testStudyUIDListExcludesThirdStudyForKeywordAndTag() async throws {
        let storage = InMemoryStorageProvider()
        for uid in ["1.2.3", "1.2.2", "1.2.1"] {
            try await storage.storeInstance(data: Data(), studyUID: uid, seriesUID: uid + ".1", instanceUID: uid + ".1.1")
        }
        let server = DICOMwebServer(configuration: DICOMwebServerConfiguration(pathPrefix: ""), storage: storage)
        for key in ["StudyInstanceUID", "0020000D"] {
            let response = await server.handleRequest(.init(method: .get, path: "/studies?\(key)=1.2.1%2C1.2.2"))
            XCTAssertEqual(response.statusCode, 200)
            let identifiers = try rows(response).compactMap { ($0["0020000D"] as? [String: Any])?["Value"] as? [String] }.flatMap { $0 }
            XCTAssertEqual(identifiers, ["1.2.1", "1.2.2"])
        }
    }

    func testResourceMatrixRejectsUnsupportedPredicatesInsteadOfBroadening() async {
        let server = DICOMwebServer(configuration: DICOMwebServerConfiguration(pathPrefix: ""), storage: InMemoryStorageProvider())
        for path in ["/studies?InstanceNumber=1", "/studies/1.2/series?StudyDate=20260115",
                     "/studies/1.2/instances?StudyInstanceUID=1.2", "/studies/1.2/series/1.2.3/instances?Modality=CT"] {
            let response = await server.handleRequest(.init(method: .get, path: path))
            XCTAssertEqual(response.statusCode, 400, path)
        }
    }

    func testSequencePredicatesRequireOneMatchingItem() throws {
        let fields = attributes([sequence([[text("00400009", .SH, "A"), text("00401001", .SH, "X")],
                                          [text("00400009", .SH, "B"), text("00401001", .SH, "Y")]])])
        let first = try QIDOQueryRules.canonicalPath("RequestAttributesSequence.00400009")
        let second = try QIDOQueryRules.canonicalPath("00400275.RequestedProcedureID")
        XCTAssertTrue(QIDOQueryRules.matches(fields, predicates: [first: "A", second: "X"], fuzzy: false))
        XCTAssertFalse(QIDOQueryRules.matches(fields, predicates: [first: "A", second: "Y"], fuzzy: false))
    }

    func testCombinedDateTimeRangesIncludeMiddleDays() {
        for (date, time) in [("00080020", "00080030"), ("00400244", "00400245")] {
            let fields = attributes([text(date, .DA, "20260115"), text(time, .TM, "093000")])
            XCTAssertTrue(QIDOQueryRules.matches(fields, predicates: [date: "20260114-20260116", time: "100000-120000"], fuzzy: false))
            XCTAssertFalse(QIDOQueryRules.matches(fields, predicates: [date: "20260115-20260116", time: "100000-120000"], fuzzy: false))
            XCTAssertTrue(QIDOQueryRules.matches(fields, predicates: [date: "-20260116", time: "-120000"], fuzzy: false))
            XCTAssertFalse(QIDOQueryRules.matches(fields, predicates: [date: "20260115-", time: "100000-"], fuzzy: false))
            let precise = attributes([text(date, .DA, "20260115"), text(time, .TM, "093000.000100")])
            XCTAssertFalse(QIDOQueryRules.matches(precise, predicates: [date: "20260115-20260115", time: "093000.000001-093000.000001"], fuzzy: false))
            XCTAssertTrue(QIDOQueryRules.matches(precise, predicates: [date: "20260115-20260115", time: "093000.000100-093000.000100"], fuzzy: false))
            // Different range forms retain independent matching.
            XCTAssertFalse(QIDOQueryRules.matches(fields, predicates: [date: "20260115", time: "100000-120000"], fuzzy: false))
        }
    }

    func testMatchingExpressionsValidateGrammarAndLiteralWildcards() throws {
        for (path, expression) in [("00080020", "20260230"), ("00400245", "-"), ("00080018", "1.2,,1.3"), ("00200013", "1-3"), ("00080061", "CT,MR"), ("00080061", "CT\\MR")] {
            XCTAssertThrowsError(try QIDOQueryRules.validate(expression, path: path))
        }
        XCTAssertTrue(QIDOQueryRules.wildcard("A[1]+.^Müller", pattern: "A[1]+.^M*"))
        XCTAssertFalse(QIDOQueryRules.wildcard("A11x^Müller", pattern: "A[1]+.^M*"))
        XCTAssertTrue(QIDOQueryRules.matches(text("00400245", .TM, "093015.123456"), expression: "093015.1", fuzzy: false))
        XCTAssertFalse(QIDOQueryRules.matches(text("00400245", .TM, "093015.223456"), expression: "093015.1", fuzzy: false))
    }

    func testReturnProjectionPreservesDefaultsRepeatedCommaAndNestedFields() async throws {
        let server = DICOMwebServer(configuration: DICOMwebServerConfiguration(pathPrefix: ""), storage: try await fixture())
        for includes in ["includefield=PatientBirthDate&includefield=00400275.RequestingService", "includefield=PatientBirthDate,RequestAttributesSequence.00321033"] {
            let response = await server.handleRequest(.init(method: .get, path: "/studies/1.2.1/series?" + includes))
            XCTAssertEqual(response.statusCode, 200)
            let result = try XCTUnwrap(try rows(response).first)
            XCTAssertEqual((result["00100030"] as? [String: Any])?["vr"] as? String, "DA")
            XCTAssertNotNil(result["00080060"])
            XCTAssertNotNil(result["0020000E"])
            let sequence = try XCTUnwrap(result["00400275"] as? [String: Any])
            let item = try XCTUnwrap((sequence["Value"] as? [[String: Any]])?.first)
            XCTAssertEqual((item["00321033"] as? [String: Any])?["Value"] as? [String], ["Radiology"])
            XCTAssertNotNil(item["00400009"])
            XCTAssertNotNil(item["00401001"])
        }
        for query in ["includefield=all&includefield=PatientID", "includefield=all,PatientID", "includefield=PatientID,"] {
            let response = await server.handleRequest(.init(method: .get, path: "/studies?" + query))
            XCTAssertEqual(response.statusCode, 400)
        }
    }

    func testProjectionRespectsEntityBoundariesAndPrivateCreators() throws {
        let fields = [text("00081030", .LO, "Study note"), text("0008103E", .LO, "Series note"),
                      text("00200013", .IS, "7"), text("00110010", .LO, "OWNER"), text("00111001", .LO, "private")]
        var query = StorageQuery(); query.includeFields = ["00081030", "0008103E", "00200013", "00111001"]
        let study = try QIDOResponseProjection.project(base: [:], attributes: fields, query: query, resource: .allStudies)
        XCTAssertNotNil(study["00081030"]); XCTAssertNil(study["0008103E"]); XCTAssertNil(study["00200013"])
        XCTAssertNotNil(study["00110010"]); XCTAssertNotNil(study["00111001"])
        query.includeFields = []; query.includeAll = true
        let series = try QIDOResponseProjection.project(base: [:], attributes: fields, query: query, resource: .studySeries)
        XCTAssertNotNil(series["0008103E"]); XCTAssertNil(series["00081030"]); XCTAssertNil(series["00200013"])
        XCTAssertNil(series["00111001"])
        query.includeAll = false; query.includeFields = ["00400275.00111001"]
        let nested = try QIDOResponseProjection.project(base: [:], attributes: [sequence([fields])], query: query, resource: .studySeries)
        let item = ((nested["00400275"] as? [String: Any])?["Value"] as? [[String: Any]])?.first
        XCTAssertNotNil(item?["00111001"]); XCTAssertNotNil(item?["00110010"])
        XCTAssertEqual((item?["00400009"] as? [String: Any])?["vr"] as? String, "SH")
        XCTAssertEqual((item?["00401001"] as? [String: Any])?["vr"] as? String, "SH")
    }

    func testLimitZeroAndFinalPageWarningsUseFilteredTotal() async throws {
        let server = DICOMwebServer(configuration: DICOMwebServerConfiguration(pathPrefix: ""), storage: try await fixture())
        let zero = await server.handleRequest(.init(method: .get, path: "/instances?PatientID=A&limit=0"))
        XCTAssertEqual(try rows(zero).count, 0); XCTAssertEqual(zero.headers["X-Total-Count"], "2")
        XCTAssertNotNil(zero.headers["Warning"])
        let last = await server.handleRequest(.init(method: .get, path: "/instances?PatientID=A&offset=1&limit=1"))
        XCTAssertEqual(try rows(last).count, 1); XCTAssertNil(last.headers["Warning"])
        let beyond = await server.handleRequest(.init(method: .get, path: "/instances?offset=9223372036854775807"))
        XCTAssertEqual(try rows(beyond).count, 0); XCTAssertNil(beyond.headers["Warning"])
    }

    func testKnownConditionalDefaultsAndSOPClassesInStudyAreReturned() async throws {
        let server = DICOMwebServer(configuration: DICOMwebServerConfiguration(pathPrefix: ""), storage: try await fixture())
        for path in ["/studies", "/series", "/instances"] {
            let response = await server.handleRequest(.init(method: .get, path: path + "?includefield=SOPClassesInStudy"))
            let first = try XCTUnwrap(try rows(response).first)
            XCTAssertEqual((first["00080062"] as? [String: Any])?["vr"] as? String, "UI")
            XCTAssertEqual((first["00080062"] as? [String: Any])?["Value"] as? [String], ["1.2.840.10008.5.1.4.1.1.7"])
            XCTAssertEqual((first["00080201"] as? [String: Any])?["Value"] as? [String], ["+0530"])
            if path != "/series" { XCTAssertNotNil(first["00080056"]) }
        }
    }

    func testLegacyProviderRefusesFilteredRequestsWithoutCallingSearch() async {
        let storage = LegacyQIDOProvider()
        let server = DICOMwebServer(configuration: DICOMwebServerConfiguration(pathPrefix: ""), storage: storage)
        for path in ["/studies", "/series", "/instances", "/studies/1.2/series", "/studies/1.2/instances", "/studies/1.2/series/1.2.3/instances"] {
            let response = await server.handleRequest(.init(method: .get, path: path + "?PatientID=A"))
            XCTAssertEqual(response.statusCode, 501)
        }
        let count = await storage.searchCalls
        XCTAssertEqual(count, 0)
    }

    func testCacheKeyRetainsAllRepeatedIncludeValues() async {
        let cache = ServerCacheMiddleware()
        let a = DICOMwebRequest(method: .get, path: "/series?includefield=PatientID&includefield=StudyDescription")
        let b = DICOMwebRequest(method: .get, path: "/series?includefield=PatientID&includefield=PatientBirthDate")
        _ = await cache.cacheResponse(.ok(json: Data("[]".utf8)), for: a)
        let hit = await cache.cachedResponse(for: a)
        let miss = await cache.cachedResponse(for: b)
        XCTAssertNotNil(hit); XCTAssertNil(miss)
    }
}

/// Intentionally implements the pre-M3 protocol only; the default capability
/// must fail closed without requiring an external provider source migration.
private actor LegacyQIDOProvider: DICOMwebStorageProvider {
    var searchCalls = 0
    func searchStudies(query: StorageQuery) async throws -> [StudyRecord] { searchCalls += 1; return [] }
    func searchSeries(studyUID: String?, query: StorageQuery) async throws -> [SeriesRecord] { searchCalls += 1; return [] }
    func searchInstances(studyUID: String?, seriesUID: String?, query: StorageQuery) async throws -> [InstanceRecord] { searchCalls += 1; return [] }
    func getInstance(studyUID: String, seriesUID: String, instanceUID: String) async throws -> Data? { nil }
    func getSeriesInstances(studyUID: String, seriesUID: String) async throws -> [InstanceInfo] { [] }
    func getStudyInstances(studyUID: String) async throws -> [InstanceInfo] { [] }
    func storeInstance(data: Data, studyUID: String, seriesUID: String, instanceUID: String) async throws {}
    func deleteInstance(studyUID: String, seriesUID: String, instanceUID: String, mode: DeletionMode) async throws -> Bool { false }
    func deleteSeries(studyUID: String, seriesUID: String, mode: DeletionMode) async throws -> Int { 0 }
    func deleteStudy(studyUID: String, mode: DeletionMode) async throws -> Int { 0 }
    func getInstanceMetadata(studyUID: String, seriesUID: String, instanceUID: String) async throws -> DataSet? { nil }
    func getSeriesMetadata(studyUID: String, seriesUID: String) async throws -> [DataSet] { [] }
    func getStudyMetadata(studyUID: String) async throws -> [DataSet] { [] }
    func countStudies(query: StorageQuery) async throws -> Int { 0 }
    func countSeries(studyUID: String) async throws -> Int { 0 }
    func countInstances(studyUID: String, seriesUID: String) async throws -> Int { 0 }
}
