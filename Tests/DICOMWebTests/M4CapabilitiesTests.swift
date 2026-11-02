import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
import DICOMCore
import DICOMKit
@testable import DICOMWeb

final class M4CapabilitiesTests: XCTestCase {
    private let study = "2.25.401", series = "2.25.401.1", instance = "2.25.401.1.1"
    private let xml = "application/vnd.sun.wadl+xml"

    private func fixture(ups: Bool = false) async throws -> (DICOMwebServer, Data) {
        let file = try DICOMFile.create(dataSet: DataSet(elements: [
            .string(tag: .studyInstanceUID, vr: .UI, value: study),
            .string(tag: .seriesInstanceUID, vr: .UI, value: series),
            .string(tag: .sopInstanceUID, vr: .UI, value: instance),
            .string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"),
            .string(tag: .patientName, vr: .PN, value: "CAPABILITIES^SYNTHETIC")
        ])).write()
        let storage = InMemoryStorageProvider()
        try await storage.storeInstance(data: file, studyUID: study, seriesUID: series, instanceUID: instance)
        let server = DICOMwebServer(storage: storage)
        if ups {
            await server.setUPSStorage(InMemoryUPSStorageProvider(workitems: [Workitem(workitemUID: "2.25.402", state: .scheduled)]))
        }
        return (server, file)
    }

    private func json(_ response: DICOMwebResponse) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(response.body)) as? [String: Any])
    }
    private func root(_ response: DICOMwebResponse, base: String) throws -> [String: Any] {
        let object = try json(response)
        XCTAssertEqual(Set(object.keys), ["application"])
        let application = try XCTUnwrap(object["application"] as? [String: Any])
        XCTAssertEqual(application["@xmlns"] as? String, "http://wadl.dev.java.net/2009/02")
        let resources = try XCTUnwrap(application["resources"] as? [[String: Any]])
        XCTAssertEqual(resources.count, 1)
        XCTAssertEqual(resources[0]["@base"] as? String, base)
        let target = try XCTUnwrap(resources[0]["resource"] as? [[String: Any]])
        XCTAssertEqual(target.count, 1)
        XCTAssertEqual(target[0]["@path"] as? String, "")
        return target[0]
    }
    private func entries(_ resource: [String: Any], prefix: String = "") -> [(path: String, name: String, types: [String], statuses: [String])] {
        let own = resource["@path"] as? String ?? ""
        let path = own.isEmpty ? prefix : prefix + "/" + own
        let methods = (resource["method"] as? [[String: Any]] ?? []).map { method in
            let types = (method["response"] as? [[String: Any]] ?? []).flatMap {
                ($0["representation"] as? [[String: Any]] ?? []).compactMap { $0["@mediaType"] as? String }
            }
            let statuses = (method["response"] as? [[String: Any]] ?? []).compactMap { $0["@status"] as? String }
            return (path: path, name: method["@name"] as? String ?? "", types: types, statuses: statuses)
        }
        return methods + (resource["resource"] as? [[String: Any]] ?? []).flatMap { entries($0, prefix: path) }
    }
    private func concrete(_ path: String) -> String {
        path.replacingOccurrences(of: "{studyUID}", with: study).replacingOccurrences(of: "{seriesUID}", with: series)
            .replacingOccurrences(of: "{instanceUID}", with: instance).replacingOccurrences(of: "{workitemUID}", with: "2.25.402")
    }

    func testServiceBaseProducesWADLJSONAndXMLWithConfiguredBase() async throws {
        for prefix in ["/dicom-web", "/custom/service/", "", "/"] {
            let config = DICOMwebServerConfiguration(port: 8042, host: "localhost", pathPrefix: prefix)
            let server = DICOMwebServer(configuration: config, storage: InMemoryStorageProvider())
            let path = prefix.isEmpty ? "/" : prefix
            let response = await server.handleRequest(.init(method: .options, path: path, headers: ["Accept": "application/json"]))
            XCTAssertEqual(response.statusCode, 200)
            XCTAssertEqual(response.headers["Content-Type"], "application/json")
            XCTAssertEqual(response.headers["Content-Length"], String(try XCTUnwrap(response.body).count))
            let target = try root(response, base: config.baseURL.absoluteString)
            let xmlResponse = await server.handleRequest(.init(method: .options, path: path, headers: ["Accept": xml]))
            XCTAssertEqual(xmlResponse.statusCode, 200)
            XCTAssertEqual(xmlResponse.headers["Content-Type"], xml)
            let parser = XMLParser(data: try XCTUnwrap(xmlResponse.body)), capture = WADLCapture()
            parser.shouldProcessNamespaces = true
            parser.delegate = capture
            XCTAssertTrue(parser.parse(), String(describing: parser.parserError))
            XCTAssertEqual(capture.applications, 1)
            XCTAssertEqual(capture.bases, [config.baseURL.absoluteString])
            XCTAssertEqual(capture.methodPaths, Set(entries(target).map { $0.name + " " + $0.path }))
            XCTAssertFalse(capture.methodPaths.contains { $0.hasPrefix("OPTIONS ") }) // Annex H excludes self-description.
            if prefix == "/dicom-web", let directory = ProcessInfo.processInfo.environment["DICOMKIT_M4_CAPABILITIES_EXPORT"] {
                let url = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try response.body!.write(to: url.appendingPathComponent("capabilities.json"))
                try xmlResponse.body!.write(to: url.appendingPathComponent("capabilities.xml"))
            }
        }
    }

    func testNegotiationHonorsWeightsSpecificExclusionsAndUTF8() async {
        let server = DICOMwebServer(storage: InMemoryStorageProvider())
        let cases: [(String?, String?, Int, String?)] = [
            (nil, nil, 406, nil), ("", nil, 406, nil), ("image/png", nil, 406, nil),
            ("*/*", nil, 200, "application/json"), ("application/*", nil, 200, "application/json"),
            ("application/json;q=0.2, \(xml);q=0.9", nil, 200, xml),
            ("application/json;q=0, */*;q=1", nil, 200, xml),
            ("application/json;q=0, \(xml);q=0, */*", nil, 406, nil),
            ("application/json;q=bogus", nil, 406, nil), ("application/json;q=1.001", nil, 406, nil),
            ("application/json;q", nil, 406, nil), ("application/json;q=0;q=1", nil, 406, nil),
            ("application/json;q=\"1\"", nil, 406, nil), ("application/json", ";", 406, nil),
            ("garbage, application/json", nil, 200, "application/json"),
            ("application/json; charset=utf-8", nil, 200, "application/json"),
            ("application/json; charset=iso-8859-1", nil, 406, nil),
            ("application/json", "iso-8859-1", 406, nil), ("application/json", "utf-8;q=0, *;q=1", 406, nil),
            ("application/json", "UTF-8", 200, "application/json"), (xml, "*", 200, xml)
        ]
        for (accept, charset, status, selected) in cases {
            var headers: [String: String] = [:]
            headers["Accept"] = accept; headers["Accept-Charset"] = charset
            let response = await server.handleRequest(.init(method: .options, path: "/dicom-web", headers: headers))
            XCTAssertEqual(response.statusCode, status, String(describing: headers))
            XCTAssertEqual(response.headers["Content-Type"], selected)
            if status != 200 { XCTAssertNil(response.body) }
            XCTAssertEqual(response.headers["Vary"], "Accept, Accept-Charset")
        }
    }

    func testInvalidCapabilitiesRequestsAndUnknownPrefixesFailExplicitly() async {
        let server = DICOMwebServer(storage: InMemoryStorageProvider())
        for request in [DICOMwebRequest(method: .options, path: "/dicom-web?limit=1", headers: ["Accept": xml]),
                        .init(method: .options, path: "/dicom-web?bad=%XX", headers: ["Accept": xml]),
                        .init(method: .options, path: "/dicom-web", headers: ["Accept": xml], body: Data([1]))] {
            let response = await server.handleRequest(request)
            XCTAssertEqual(response.statusCode, 400)
            XCTAssertNil(response.body)
        }
        for path in ["/other", "/dicom-web-other", "/dicom-web-other/studies"] {
            let response = await server.handleRequest(.init(method: .options, path: path, headers: ["Accept": xml]))
            XCTAssertEqual(response.statusCode, 404)
        }
        for (path, method, allow) in [("/dicom-web", DICOMwebRequest.HTTPMethod.post, "GET, OPTIONS"),
                                    ("/dicom-web/studies", .put, "GET, POST"),
                                    ("/dicom-web/studies", .options, "GET, POST"),
                                    ("/dicom-web/studies/2.25.1/metadata", .delete, "GET")] {
            let response = await server.handleRequest(.init(method: method, path: path, headers: ["Accept": xml]))
            XCTAssertEqual(response.statusCode, 405)
            XCTAssertEqual(response.headers["Allow"], allow)
        }
    }

    func testCORSPreflightIsDistinctFromOriginBearingCapabilities() async {
        let server = DICOMwebServer(configuration: .init(corsConfiguration: .allowAll), storage: InMemoryStorageProvider())
        for path in ["/dicom-web", "/dicom-web/studies"] {
            let response = await server.handleRequest(.init(method: .options, path: path,
                headers: ["Origin": "https://client.invalid", "Access-Control-Request-Method": "GET", "Access-Control-Request-Headers": "Accept"]))
            XCTAssertEqual(response.statusCode, 204)
            XCTAssertEqual(response.headers["Access-Control-Allow-Origin"], "*")
            XCTAssertTrue(response.headers["Access-Control-Allow-Methods"]?.contains("GET") == true)
            XCTAssertNil(response.body)
        }
        let ordinary = await server.handleRequest(.init(method: .options, path: "/dicom-web",
            headers: ["Origin": "https://client.invalid", "Accept": xml]))
        XCTAssertEqual(ordinary.statusCode, 200)
        XCTAssertEqual(ordinary.headers["Access-Control-Allow-Origin"], "*")
        XCTAssertNotNil(ordinary.body)
    }

    func testEveryAdvertisedGETRunsAgainstMinimalFixtureAndDeclaredMediaType() async throws {
        let (server, file) = try await fixture(ups: true)
        let response = await server.handleRequest(.init(method: .options, path: "/dicom-web", headers: ["Accept": "application/json"]))
        let target = try root(response, base: "http://127.0.0.1:8042/dicom-web")
        let advertised = entries(target)
        let retrieval = Set(advertised.filter { $0.name == "GET" && $0.path.contains("{instanceUID}") || $0.name == "GET" && $0.types.contains { $0.contains("multipart") } }.map(\.path))
        XCTAssertTrue(retrieval.contains("/studies/{studyUID}"))
        XCTAssertTrue(retrieval.contains("/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/metadata"))
        let expectedGETPaths: Set<String> = ["", "/capabilities", "/studies", "/series", "/instances",
            "/studies/{studyUID}", "/studies/{studyUID}/metadata", "/studies/{studyUID}/series", "/studies/{studyUID}/instances",
            "/studies/{studyUID}/series/{seriesUID}", "/studies/{studyUID}/series/{seriesUID}/metadata",
            "/studies/{studyUID}/series/{seriesUID}/instances", "/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}",
            "/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/metadata", "/workitems", "/workitems/{workitemUID}"]
        XCTAssertEqual(Set(advertised.filter { $0.name == "GET" }.map(\.path)), expectedGETPaths)
        for entry in advertised {
            // Independent router cross-check covers every advertised method,
            // including POST/PUT/DELETE, without mutating the fixture here.
            let method = try XCTUnwrap(DICOMwebRequest.HTTPMethod(rawValue: entry.name))
            XCTAssertNotNil(DICOMwebRouter().match(path: "/dicom-web" + concrete(entry.path), method: method), entry.path)
            guard entry.name == "GET" else { continue }
            for type in entry.types {
                let result = await server.handleRequest(.init(method: .get, path: "/dicom-web" + concrete(entry.path), headers: ["Accept": type]))
                XCTAssertEqual(result.statusCode, 200, entry.path + " " + type)
                let body = try XCTUnwrap(result.body)
                if type.contains("multipart") {
                    XCTAssertTrue(result.headers["Content-Type"]?.hasPrefix("multipart/related") == true)
                    XCTAssertNotNil(body.range(of: file), entry.path)
                } else if type == "application/dicom" { XCTAssertEqual(body, file) }
                else {
                    XCTAssertEqual(result.headers["Content-Type"], type)
                    XCTAssertNotNil(try JSONSerialization.jsonObject(with: body))
                }
            }
        }
    }

    func testAdvertisedUPSCreateAndUpdateResponsesMatchImplementedTargets() async throws {
        let (server, _) = try await fixture(ups: true)
        let capabilities = await server.handleRequest(.init(method: .options, path: "/dicom-web", headers: ["Accept": "application/json"]))
        let advertised = entries(try root(capabilities, base: "http://127.0.0.1:8042/dicom-web"))
        let cases: [(String, String, DICOMwebRequest.HTTPMethod, Int)] = [
            ("/workitems", "/workitems?workitem=2.25.403", .post, 201),
            ("/workitems/{workitemUID}", "/workitems/2.25.402", .post, 200),
            ("/workitems/{workitemUID}", "/workitems/2.25.402", .put, 200)
        ]
        for (path, target, method, status) in cases {
            let entry = try XCTUnwrap(advertised.first { $0.path == path && $0.name == method.rawValue })
            XCTAssertEqual(entry.statuses, [String(status)])
            XCTAssertTrue(entry.types.isEmpty, "Successful creation and update have no response payload")
            let body = try JSONSerialization.data(withJSONObject: ["00741000": ["vr": "CS", "Value": ["SCHEDULED"]]])
            let response = await server.handleRequest(.init(method: method, path: "/dicom-web" + target,
                headers: ["Content-Type": "application/dicom+json"], body: body))
            XCTAssertEqual(response.statusCode, status)
            if status == 201 { XCTAssertNotNil(response.headers["Location"]) }
            XCTAssertNil(response.body)
        }
    }

    func testUnsupportedRetrievalIsAbsentAndReturns501() async throws {
        let (server, _) = try await fixture()
        let response = await server.handleRequest(.init(method: .options, path: "/dicom-web", headers: ["Accept": "application/json"]))
        let advertised = entries(try root(response, base: "http://127.0.0.1:8042/dicom-web"))
        XCTAssertFalse(advertised.contains { entry in ["bulkdata", "frames", "rendered", "thumbnail", "workitems"].contains(where: entry.path.contains) })
        let base = "/dicom-web/studies/\(study)/series/\(series)"
        for path in [base + "/rendered", base + "/thumbnail", base + "/instances/\(instance)/rendered",
                     base + "/instances/\(instance)/thumbnail", base + "/instances/\(instance)/bulkdata",
                     base + "/instances/\(instance)/frames/1", base + "/instances/\(instance)/frames/1/rendered"] {
            let result = await server.handleRequest(.init(method: .get, path: path, headers: ["Accept": "*/*"]))
            XCTAssertEqual(result.statusCode, 501, path)
        }
        for path in ["/dicom-web", "/dicom-web/capabilities"] {
            let result = await server.handleRequest(.init(method: .get, path: path))
            let document = try json(result)
            let services = try XCTUnwrap(document["services"] as? [String: Bool])
            XCTAssertEqual(services["bulkdata"], false)
            XCTAssertEqual(services["rendered"], false)
            XCTAssertEqual(services["thumbnails"], false)
            let types = try XCTUnwrap(document["mediaTypes"] as? [String: Any])
            XCTAssertEqual(types["rendered"] as? [String], [])
        }
    }
}

private final class WADLCapture: NSObject, XMLParserDelegate {
    var applications = 0, bases: [String] = [], paths: [String] = [], methodPaths: Set<String> = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        XCTAssertEqual(namespaceURI, "http://wadl.dev.java.net/2009/02")
        if name == "application" { applications += 1 }
        if name == "resources", let base = attributes["base"] { bases.append(base) }
        if name == "resource" { paths.append(attributes["path"] ?? "") }
        if name == "method" { methodPaths.insert((attributes["name"] ?? "") + " " + paths.filter { !$0.isEmpty }.map { "/" + $0 }.joined()) }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "resource" { paths.removeLast() }
    }
}
