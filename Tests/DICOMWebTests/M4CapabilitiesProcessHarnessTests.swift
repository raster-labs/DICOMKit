import Foundation
import XCTest
@testable import DICOMWeb

/// Opt-in process bridge for real OPTIONS, GET and CORS loopback requests.
/// The caller supplies independent Part 10 fixtures and an HTTP adapter; this
/// harness runs the actual server/provider and preserves binary response bodies.
final class M4CapabilitiesProcessHarnessTests: XCTestCase {
    func testCapabilitiesProcessHarness() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["DICOMKIT_M4_CAPABILITIES_BRIDGE"] else {
            throw XCTSkip("Set DICOMKIT_M4_CAPABILITIES_BRIDGE for the loopback capabilities gate")
        }
        let root = URL(fileURLWithPath: directory)
        struct Fixture: Decodable { let file: String; let study: String; let series: String; let instance: String }
        struct Request: Decodable { let method: String; let path: String; let headers: [String: String]; let bodyBase64: String? }
        let storage = InMemoryStorageProvider()
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("fixtures.json")))
        for fixture in fixtures {
            try await storage.storeInstance(data: Data(contentsOf: root.appendingPathComponent(fixture.file)),
                studyUID: fixture.study, seriesUID: fixture.series, instanceUID: fixture.instance)
        }
        let base = try XCTUnwrap(URL(string: environment["DICOMKIT_M4_CAPABILITIES_BASE"] ?? "http://127.0.0.1:8042/dicom-web"))
        let config = DICOMwebServerConfiguration(port: base.port ?? 80, host: base.host ?? "127.0.0.1", pathPrefix: base.path,
                                                corsConfiguration: .allowAll)
        let server = DICOMwebServer(configuration: config, storage: storage)
        try Data("ready".utf8).write(to: root.appendingPathComponent("ready"), options: .atomic)
        let deadline = Date().addingTimeInterval(3600)
        while Date() < deadline && !FileManager.default.fileExists(atPath: root.appendingPathComponent("stop").path) {
            let requests = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "request" }.sorted { $0.path < $1.path }
            for file in requests {
                let request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: file))
                let method = try XCTUnwrap(DICOMwebRequest.HTTPMethod(rawValue: request.method))
                let body = try request.bodyBase64.map { try XCTUnwrap(Data(base64Encoded: $0)) }
                let response = await server.handleRequest(.init(method: method, path: request.path, headers: request.headers, body: body))
                let value: [String: Any] = ["status": response.statusCode, "headers": response.headers,
                                          "bodyBase64": response.body?.base64EncodedString() ?? ""]
                try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                    .write(to: file.deletingPathExtension().appendingPathExtension("response"), options: .atomic)
                try FileManager.default.removeItem(at: file)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
