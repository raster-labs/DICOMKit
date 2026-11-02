import Foundation
import XCTest
@testable import DICOMStudio

/// Opt-in real ViewModel actions for the M5 CLI/Workshop comparison campaign.
/// The parent campaign supplies synthetic files and loopback endpoints only.
final class M5WorkshopActionHarnessTests: XCTestCase {
    @MainActor
    func testConfiguredWorkshopActions() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let requestPath = environment["DICOMKIT_M5_WORKSHOP_REQUESTS"],
              let outputPath = environment["DICOMKIT_M5_WORKSHOP_OUTPUT"] else {
            throw XCTSkip("Set DICOMKIT_M5_WORKSHOP_REQUESTS and DICOMKIT_M5_WORKSHOP_OUTPUT for synthetic M5 actions")
        }
        let requests = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: requestPath))) as? [[String: Any]])
        XCTAssertFalse(requests.isEmpty)
        var records: [[String: Any]] = []
        for request in requests {
            let name = try XCTUnwrap(request["name"] as? String)
            let tool = try XCTUnwrap(request["tool"] as? String)
            guard ["dicom-script", "dicom-qr", "dicom-anon"].contains(tool) else {
                XCTFail("Tool is outside the M5 Workshop harness scope: \(tool)")
                continue
            }
            let values = try XCTUnwrap(request["values"] as? [String: String])
            let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
            vm.selectTool(id: tool)
            for (id, value) in values { vm.updateParameterValue(parameterID: id, value: value) }
            if request["advanced"] as? Bool == true { vm.experienceMode = .advanced }
            let available = vm.executionUnavailableReason
            let valid = vm.isCommandValid
            let label = vm.runActionTitle
            let renderedIDs = (vm.visibleParameters() + vm.advancedParameters()).map(\.id)
            await vm.executeCommand()
            XCTAssertNotEqual(vm.consoleStatus, .running, name)
            if let expected = request["expectedStatus"] as? String { XCTAssertEqual(vm.consoleStatus.rawValue, expected, name + "\n" + vm.consoleOutput) }
            if let expected = request["expectedExit"] as? Int { XCTAssertEqual(vm.commandHistory.first?.exitCode, expected, name + "\n" + vm.consoleOutput) }
            var record: [String: Any] = ["name": name, "tool": tool, "preview": vm.commandPreview,
                "validBeforeRun": valid, "actionTitle": label, "visibleParameterIDs": renderedIDs,
                "status": vm.consoleStatus.rawValue, "console": vm.consoleOutput,
                "historyCount": vm.commandHistory.count, "retrievedFiles": vm.lastRetrievedFiles]
            record["unavailableReason"] = available.map { $0 as Any } ?? NSNull()
            record["exit"] = (vm.commandHistory.first?.exitCode).map { $0 as Any } ?? NSNull()
            records.append(record)
        }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    }
}
