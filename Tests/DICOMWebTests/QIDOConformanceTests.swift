import Testing
import Foundation
@testable import DICOMWeb

/// QIDO-RS against PS3.18 Table 10.6.1-5 (DICOM_TAG_AUDIT_PHASE2_FINDINGS.md §6).
@Suite("QIDO-RS conformance")
struct QIDOConformanceTests {

    // MARK: - DA/TM matching values (PS3.4 C.2.2.2.5)

    @Test("DateRange parses single value and every range form")
    func dateRangeParsing() throws {
        let single = try #require(StorageQuery.DateRange(dicomValue: "20240115"))
        #expect(single.start == single.end)

        let closed = try #require(StorageQuery.DateRange(dicomValue: "20240101-20240131"))
        #expect(closed.start != nil && closed.end != nil)

        let open = try #require(StorageQuery.DateRange(dicomValue: "20240101-"))
        #expect(open.start != nil && open.end == nil)

        let until = try #require(StorageQuery.DateRange(dicomValue: "-20240131"))
        #expect(until.start == nil && until.end != nil)

        #expect(StorageQuery.DateRange(dicomValue: "notadate") == nil)
        #expect(StorageQuery.DateRange(dicomValue: "-") == nil)
    }

    @Test("DateRange contains stored DA values")
    func dateRangeContains() throws {
        let range = try #require(StorageQuery.DateRange(dicomValue: "20240101-20240131"))
        #expect(range.contains(dicomValue: "20240115"))
        #expect(!range.contains(dicomValue: "20240201"))
        #expect(!range.contains(dicomValue: nil), "an undated study never matches a date filter")

        let time = try #require(StorageQuery.DateRange(dicomValue: "100000-120000", format: "HHmmss"))
        #expect(time.contains(dicomValue: "113000", format: "HHmmss"))
        #expect(!time.contains(dicomValue: "130000", format: "HHmmss"))
    }

    // MARK: - Server: required matching keys, hex-tag form, required return attributes

    private func server() async throws -> (DICOMwebServer, InMemoryStorageProvider) {
        let storage = InMemoryStorageProvider()
        try await storage.storeInstance(data: Data("a".utf8), studyUID: "1.1", seriesUID: "1.1.1", instanceUID: "1.1.1.1")
        try await storage.storeInstance(data: Data("b".utf8), studyUID: "2.2", seriesUID: "2.2.2", instanceUID: "2.2.2.2")
        return (DICOMwebServer(storage: storage), storage)
    }

    private func results(_ response: DICOMwebResponse) throws -> [[String: Any]] {
        let body = try #require(response.body)
        return try #require(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
    }

    @Test("Study Instance UID filter accepted as keyword and as hex tag")
    func hexTagForm() async throws {
        let (server, _) = try await server()
        let byKeyword = await server.handleRequest(DICOMwebRequest(
            method: .get, path: "/dicom-web/studies", queryParameters: ["StudyInstanceUID": "1.1"]))
        let byTag = await server.handleRequest(DICOMwebRequest(
            method: .get, path: "/dicom-web/studies", queryParameters: ["0020000D": "1.1"]))
        #expect(try results(byKeyword).count == 1)
        #expect(try results(byTag).count == 1, "PS3.18 8.3.4.1: {attributeID} may be the 8-hex tag")
    }

    @Test("StudyDate filter is honoured (undated studies do not match)")
    func studyDateFilter() async throws {
        let (server, _) = try await server()
        let all = await server.handleRequest(DICOMwebRequest(method: .get, path: "/dicom-web/studies"))
        #expect(try results(all).count == 2)
        let dated = await server.handleRequest(DICOMwebRequest(
            method: .get, path: "/dicom-web/studies", queryParameters: ["StudyDate": "20240101-20241231"]))
        #expect(try results(dated).isEmpty, "a StudyDate filter must not return every study")
    }

    @Test("Study, series and instance results carry Retrieve URL and Instance Availability")
    func requiredReturnAttributes() async throws {
        let (server, _) = try await server()
        let studies = try results(await server.handleRequest(DICOMwebRequest(method: .get, path: "/dicom-web/studies")))
        let study = try #require(studies.first { ($0["0020000D"] as? [String: Any])?["Value"] as? [String] == ["1.1"] })
        #expect(((study["00081190"] as? [String: Any])?["Value"] as? [String])?.first?.hasSuffix("/studies/1.1") == true)
        #expect(((study["00080056"] as? [String: Any])?["Value"] as? [String]) == ["ONLINE"])

        let series = try results(await server.handleRequest(DICOMwebRequest(method: .get, path: "/dicom-web/studies/1.1/series")))
        #expect(((series.first?["00081190"] as? [String: Any])?["Value"] as? [String])?.first?.hasSuffix("/studies/1.1/series/1.1.1") == true)

        let instances = try results(await server.handleRequest(DICOMwebRequest(method: .get, path: "/dicom-web/studies/1.1/series/1.1.1/instances")))
        #expect(((instances.first?["00081190"] as? [String: Any])?["Value"] as? [String])?.first?.hasSuffix("/instances/1.1.1.1") == true)
    }

    // MARK: - Client: series-level Request Attributes

    @Test("Series result exposes PPS Start Time and Request Attributes Sequence")
    func seriesRequestAttributes() {
        let json: [String: Any] = [
            "0020000E": ["vr": "UI", "Value": ["1.2"]],
            "00400245": ["vr": "TM", "Value": ["093000"]],
            "00400275": ["vr": "SQ", "Value": [[
                "00400009": ["vr": "SH", "Value": ["SPS7"]],
                "00401001": ["vr": "SH", "Value": ["RP9"]],
            ]]],
        ]
        let result = QIDOSeriesResult(attributes: json)
        #expect(result.performedProcedureStepStartTime == "093000")
        #expect(result.requestAttributes.first?.scheduledProcedureStepID == "SPS7")
        #expect(result.requestAttributes.first?.requestedProcedureID == "RP9")
    }

    @Test("Query builder emits the sequence-attribute matching form")
    func sequenceAttributeQuery() {
        let query = QIDOQuery().scheduledProcedureStepID("SPS7").performedProcedureStepStartTime("0900-1000")
        let params = query.toParameters()
        #expect(params["00400275.00400009"] == "SPS7")
        #expect(params["00400245"] == "0900-1000")
    }
}
