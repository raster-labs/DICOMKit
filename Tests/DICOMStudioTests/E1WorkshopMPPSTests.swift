import Foundation
import XCTest
@testable import DICOMStudio

@MainActor
final class E1WorkshopMPPSTests: XCTestCase {
    private func model() -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
        vm.selectTool(id: "dicom-mpps")
        for (key, value) in ["operation": "update", "host": "127.0.0.1", "port": "1",
                             "aet": "E1TEST", "mpps-uid": "2.25.108"] {
            vm.updateParameterValue(parameterID: key, value: value)
        }
        return vm
    }

    func testIntermediatePreviewAndDescriptionAreOperationScoped() {
        let vm = model()
        XCTAssertTrue(vm.commandPreview.contains("--status COMPLETED"))
        vm.updateParameterValue(parameterID: "procedure-step-description", value: "Hidden create value")
        vm.updateParameterValue(parameterID: "update-procedure-step-description", value: "Acquisition continuing")
        vm.updateParameterValue(parameterID: "status-update", value: "IN PROGRESS")
        XCTAssertTrue(vm.commandPreview.contains("--status 'IN PROGRESS'"), vm.commandPreview)
        XCTAssertTrue(vm.commandPreview.contains("--procedure-step-description 'Acquisition continuing'"), vm.commandPreview)
        XCTAssertFalse(vm.commandPreview.contains("Hidden create value"))
        vm.updateParameterValue(parameterID: "status-update", value: "")
        XCTAssertFalse(vm.commandPreview.contains("--status"), vm.commandPreview)
        XCTAssertTrue(vm.visibleParameters().contains { $0.id == "update-procedure-step-description" })
        vm.updateParameterValue(parameterID: "operation", value: "create")
        XCTAssertFalse(vm.visibleParameters().contains { $0.id == "update-procedure-step-description" })
        XCTAssertFalse(vm.commandPreview.contains("Acquisition continuing"))
    }

    func testIntermediateStatusChoicesPreserveTerminalDefault() throws {
        let status = try XCTUnwrap(ToolCatalogHelpers.parameterDefinitions(for: "dicom-mpps")
            .first { $0.id == "status-update" })
        XCTAssertEqual(status.defaultValue, "COMPLETED")
        XCTAssertEqual(status.allowedValues, ["", "IN PROGRESS", "COMPLETED", "DISCONTINUED"])
    }

    func testIntermediateDiscontinuationReasonRefusesBeforeConnection() async {
        let vm = model()
        vm.updateParameterValue(parameterID: "status-update", value: "IN PROGRESS")
        vm.updateParameterValue(parameterID: "update-procedure-step-description", value: "Continuing")
        vm.updateParameterValue(parameterID: "discontinuation-reason", value: "110513|DCM|Stopped")
        await vm.executeCommand()
        XCTAssertEqual(vm.commandHistory.first?.exitCode, 64)
        XCTAssertTrue(vm.consoleOutput.contains("only valid with --status DISCONTINUED"), vm.consoleOutput)
    }

    func testEmptyIntermediateUpdateHasCLIUsageFailure() async {
        let vm = model()
        vm.updateParameterValue(parameterID: "status-update", value: "")
        await vm.executeCommand()
        XCTAssertEqual(vm.commandHistory.first?.exitCode, 64)
        XCTAssertTrue(vm.consoleOutput.contains("needs --procedure-step-description or a full --series-uid snapshot"))
    }

    /// Actual shared Workshop execution against the independent loopback SCP.
    /// Ordinary runs explicitly skip this external gate; the E1 campaign enables it.
    func testIndependentPeerActions() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["DICOMKIT_E1_WORKSHOP_REQUESTS"],
              let output = env["DICOMKIT_E1_WORKSHOP_OUTPUT"] else {
            throw XCTSkip("Run Scripts/verify_mpps_intermediate.py for the independent MPPS peer gate")
        }
        let requests = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: input))) as? [[String: Any]])
        XCTAssertFalse(requests.isEmpty)
        var records: [[String: Any]] = []
        var createdUIDs: [String: String] = [:]
        for request in requests {
            let name = try XCTUnwrap(request["name"] as? String)
            let values = try XCTUnwrap(request["values"] as? [String: String])
            XCTAssertEqual(values["host"], "127.0.0.1", "Only synthetic loopback peers")
            let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
            vm.selectTool(id: "dicom-mpps")
            for (key, value) in values {
                let resolved = value.hasPrefix("$")
                    ? try XCTUnwrap(createdUIDs[String(value.dropFirst())], "Unknown synthetic UID reference") : value
                vm.updateParameterValue(parameterID: key, value: resolved)
            }
            let preview = vm.commandPreview
            await vm.executeCommand()
            let expectedExit = try XCTUnwrap(request["expectedExit"] as? Int)
            XCTAssertEqual(vm.commandHistory.first?.exitCode, expectedExit, name + "\n" + vm.consoleOutput)
            XCTAssertEqual(vm.consoleStatus, expectedExit == 0 ? .success : .error, name + "\n" + vm.consoleOutput)
            if let saveUID = request["saveUID"] as? String {
                let uid = try XCTUnwrap(vm.parameterValues.first { $0.parameterID == "mpps-uid" }?.stringValue)
                XCTAssertFalse(uid.isEmpty)
                createdUIDs[saveUID] = uid
            }
            records.append(["name": name, "preview": preview, "console": vm.consoleOutput,
                            "exit": vm.commandHistory.first?.exitCode ?? -1])
        }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: output), options: .atomic)
    }
}
