import Foundation
import XCTest
@testable import DICOMWeb

/// Opt-in process boundary for the independent Python oracle. It uses the real
/// provider and request router; the HTTP adapter deliberately lives in test code.
final class M3QueryProcessHarnessTests: XCTestCase {
    func testQueryProcessHarness() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["DICOMKIT_M3_BRIDGE_DIR"] else {
            throw XCTSkip("Run Scripts/verify_m3_queries.py for isolated process and HTTP gates")
        }
        let root = URL(fileURLWithPath: directory)
        struct Fixture: Decodable { let file: String; let study: String; let series: String; let instance: String }
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("fixtures.json")))
        let storage = InMemoryStorageProvider()
        // Deliberately insert in reverse order: the result order must not depend on insertion.
        for fixture in fixtures.reversed() {
            try await storage.storeInstance(data: Data(contentsOf: root.appendingPathComponent(fixture.file)),
                studyUID: fixture.study, seriesUID: fixture.series, instanceUID: fixture.instance)
        }
        let server = DICOMwebServer(storage: storage)
        func reply(_ path: String, to output: URL) async throws {
            let response = await server.handleRequest(DICOMwebRequest(method: .get, path: path))
            let value: [String: Any] = ["status": response.statusCode, "headers": response.headers,
                "body": response.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""]
            try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: output, options: .atomic)
        }
        if let request = env["DICOMKIT_M3_PROBE_PATH"] {
            try await reply(request, to: root.appendingPathComponent("probe-response.json"))
            return
        }
        try Data("ready".utf8).write(to: root.appendingPathComponent("ready"), options: .atomic)
        let deadline = Date().addingTimeInterval(3600)
        while Date() < deadline && !FileManager.default.fileExists(atPath: root.appendingPathComponent("stop").path) {
            let pending = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix(".request") }.sorted { $0.path < $1.path }
            for file in pending {
                let path = try String(contentsOf: file, encoding: .utf8)
                try await reply(path, to: file.deletingPathExtension().appendingPathExtension("response"))
                try FileManager.default.removeItem(at: file)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
