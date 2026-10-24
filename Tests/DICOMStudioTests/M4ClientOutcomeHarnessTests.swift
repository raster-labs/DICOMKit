import Foundation
import XCTest
@testable import DICOMStudio

/// Opt-in transport gate driven by Scripts/verify_m4_clients.py. This runs the
/// existing Workshop executor against an independent synthetic FE00 peer.
final class M4ClientOutcomeHarnessTests: XCTestCase {
    @MainActor
    func testRestartedServerClients() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let port = env["DICOMKIT_M4_DURABLE_PORT"], let directory = env["DICOMKIT_M4_DURABLE_OUTPUT"],
              let study = env["DICOMKIT_M4_DURABLE_STUDY"] else {
            throw XCTSkip("Run Scripts/verify_m4_durability.py for the real server restart gate")
        }
        var records: [[String: Any]] = []
        for name in ["query", "get", "move"] {
            let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
            vm.selectTool(id: name == "query" ? "dicom-query" : "dicom-retrieve")
            var values = ["host": "127.0.0.1", "port": port, "aet": "M4CLIENT", "called-aet": "M4SCP", "timeout": "5", "study-uid": study]
            if name == "query" {
                values["level"] = "study"; values["output-format"] = "json"
            } else {
                values["method"] = name == "get" ? "c-get" : "c-move"
                values["output"] = directory + "/workshop-get"
                if name == "move" { values["move-dest"] = "M4DEST" }
            }
            for (key, value) in values { vm.updateParameterValue(parameterID: key, value: value) }
            await vm.executeCommand()
            XCTAssertEqual(vm.consoleStatus, .success, vm.consoleOutput)
            XCTAssertEqual(vm.commandHistory.first?.exitCode, 0, vm.consoleOutput)
            if name == "query" { XCTAssertTrue(vm.consoleOutput.contains(study), vm.consoleOutput) }
            if name == "get" { XCTAssertEqual(vm.lastRetrievedFiles.count, 1, vm.consoleOutput) }
            records.append(["name": name, "preview": vm.commandPreview, "console": vm.consoleOutput,
                            "exit": vm.commandHistory.first?.exitCode ?? -1])
        }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("workshop-durability.json"), options: .atomic)
    }

    @MainActor
    func testControlledCancellationOutcomes() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let port = env["DICOMKIT_M4_CLIENT_PORT"], let directory = env["DICOMKIT_M4_CLIENT_OUTPUT"] else {
            throw XCTSkip("Run Scripts/verify_m4_clients.py for loopback CLI/Workshop outcome parity")
        }
        var records: [[String: Any]] = []
        for name in ["find-empty", "find-partial", "move-cancel", "get-cancel"] {
            let query = name.hasPrefix("find")
            let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
            vm.selectTool(id: query ? "dicom-query" : "dicom-retrieve")
            var values = ["host": "127.0.0.1", "port": port, "aet": "M4CLIENT", "called-aet": "M4PEER", "timeout": "5"]
            if query {
                values.merge(["level": "study", "patient-id": name == "find-empty" ? "M4ZERO" : "M4PARTIAL", "output-format": "json"]) { _, new in new }
            } else {
                values.merge(["method": name == "move-cancel" ? "c-move" : "c-get", "study-uid": "2.25.404", "output": directory + "/received"]){ _, new in new }
                if name == "move-cancel" { values["move-dest"] = "M4DEST" }
            }
            for (key, value) in values { vm.updateParameterValue(parameterID: key, value: value) }
            await vm.executeCommand()
            XCTAssertEqual(vm.consoleStatus, .error, name)
            XCTAssertEqual(vm.commandHistory.first?.exitCode, 1, name)
            XCTAssertTrue(vm.consoleOutput.lowercased().contains("cancel"), name)
            if query {
                XCTAssertTrue(vm.consoleOutput.contains("FE00"), name)
                XCTAssertTrue(vm.consoleOutput.contains(name == "find-empty" ? "0 partial result(s)" : "1 partial result(s)"), name)
                if name == "find-partial" { XCTAssertTrue(vm.consoleOutput.contains("M4^PARTIAL")) }
            } else {
                XCTAssertTrue(vm.consoleOutput.contains("2.25.404.9"), name)
                if name == "get-cancel" {
                    XCTAssertFalse(vm.consoleOutput.contains("likely no storage"))
                    XCTAssertTrue(vm.lastRetrievedFiles.isEmpty)
                }
            }
            records.append(["name": name, "preview": vm.commandPreview, "console": vm.consoleOutput,
                            "status": "error", "exit": vm.commandHistory.first?.exitCode ?? -1])
        }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("workshop.json"), options: .atomic)
    }
}
