import Foundation
import XCTest
import DICOMPrintCommandSupport
@testable import DICOMStudio

/// Real ViewModel actions. Ordinary tests use explicit temporary SCP settings;
/// the opt-in process harness additionally requires an isolated registry root.
@MainActor
final class M6WorkshopExecutionTests: XCTestCase {
    private func makeVM(_ tool: String) -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
        vm.selectTool(id: tool)
        return vm
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("m6-workshop-execution-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func command(_ arguments: [String]) -> String {
        arguments.map(CommandBuilderHelpers.shellEscape).joined(separator: " ")
    }

    private func waitUntil(seconds: TimeInterval = 8, _ predicate: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate() && Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
        return predicate()
    }

    private func set(_ flag: String, _ value: String, on vm: CLIWorkshopViewModel) throws {
        let definition = try XCTUnwrap(vm.parameterDefinitions.first { $0.flag == flag &&
            ($0.visibleWhen?.values.contains(vm.parameterValues.first { $0.parameterID == "subcommand" }?.stringValue ?? "serve") ?? true) })
        vm.updateParameterValue(parameterID: definition.id, value: value)
    }

    func testSuccessfulImportPersistsAndFailedImportPreservesAllCurrentState() throws {
        let vm = makeVM("dicom-print")
        try vm.importPrintCommand("dicom-print list-printers --format json")
        vm.loadFromService()
        XCTAssertEqual(vm.parameterValues.first { $0.parameterID == "operation" }?.stringValue, "list-printers")
        XCTAssertEqual(vm.parameterValues.first { $0.parameterID == "format" }?.stringValue, "json")
        XCTAssertTrue(vm.isCommandValid)
        let grant = URL(fileURLWithPath: "/tmp/m6-import-synthetic-grant.dcm")
        vm.securityScopedURLs = ["paths#0": grant]
        let values = vm.parameterValues, preview = vm.commandPreview, history = vm.commandHistory
        for invalid in ["dicom-printscp status", "dicom-print send pacs://localhost x.dcm --aet APP --no-raw",
                        "dicom-print list-printers; echo unintended", "dicom-print list-printers --format json --format text"] {
            XCTAssertThrowsError(try vm.importPrintCommand(invalid), invalid)
            XCTAssertEqual(vm.parameterValues, values)
            XCTAssertEqual(vm.commandPreview, preview)
            XCTAssertEqual(vm.securityScopedURLs, ["paths#0": grant])
            XCTAssertEqual(vm.commandHistory, history)
        }
        try vm.importPrintCommand("dicom-print status pacs://localhost --aet APP")
        XCTAssertTrue(vm.securityScopedURLs.isEmpty)
        XCTAssertEqual(vm.parameterValues.first { $0.parameterID == "operation" }?.stringValue, "status")
    }

    func testInvalidPreflightDoesNotRunOrCreateHistory() async throws {
        let vm = makeVM("dicom-print")
        try vm.importPrintCommand("dicom-print send pacs://localhost:1 absent.dcm --aet APP --dry-run")
        vm.appendConsoleOutput("Previous operation output\n")
        vm.updateParameterValue(parameterID: "windowCenter", value: "-600")
        XCTAssertFalse(vm.isCommandValid)
        XCTAssertNotNil(vm.printCommandValidationError)
        await vm.executeCommand()
        XCTAssertEqual(vm.consoleStatus, .error)
        XCTAssertTrue(vm.consoleOutput.hasPrefix("Cannot run:"))
        XCTAssertFalse(vm.consoleOutput.contains("$ dicom-print"))
        XCTAssertFalse(vm.consoleOutput.contains("Previous operation output"))
        let refusedConsole = vm.consoleOutput
        vm.loadFromService()
        XCTAssertEqual(vm.consoleOutput, refusedConsole)
        XCTAssertTrue(vm.commandHistory.isEmpty)
        XCTAssertFalse(vm.isPrintCommandRunning)
        XCTAssertNil(vm.printListenerPort)
    }

    func testPaperQueueWithoutExplicitConsentRefusesBeforeAnyOutput() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("must-not-exist")
        let vm = makeVM("dicom-printscp")
        try vm.importPrintCommand(command(["dicom-printscp", "serve", "--config", directory.appendingPathComponent("absent.json").path,
            "--port", "0", "--output", "none", "--output-dir", output.path]))
        try set("--paper-queue", "M6_DO_NOT_SPOOL", on: vm)
        XCTAssertFalse(vm.isCommandValid)
        XCTAssertTrue(vm.printCommandValidationError?.contains("--allow-paper") == true)
        await vm.executeCommand()
        XCTAssertEqual(vm.consoleStatus, .error)
        XCTAssertTrue(vm.commandHistory.isEmpty)
        XCTAssertFalse(vm.isPrintCommandRunning)
        XCTAssertNil(vm.printListenerPort)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testQuietServePublishesBoundStateBlocksSwitchingAndStopReleasesPortForRestart() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vm = makeVM("dicom-printscp")
        func serve(_ port: UInt16) throws {
            try vm.importPrintCommand(command(["dicom-printscp", "serve", "--config", directory.appendingPathComponent("absent.json").path,
                "--port", String(port), "--output", "none", "--quiet", "--duration", "12"]))
        }
        try serve(0)
        XCTAssertEqual(vm.runActionTitle, "Start")
        var firstFinished = false
        let first = Task { await vm.executeCommand(); firstFinished = true }
        defer { first.cancel(); vm.stopPrintCommand() }
        let firstReady = await waitUntil { vm.printListenerPort != nil || firstFinished }
        guard firstReady, let port = vm.printListenerPort else {
            vm.stopPrintCommand(); XCTFail("Listener did not become ready: \(vm.consoleOutput)"); return
        }
        XCTAssertGreaterThan(port, 0)
        XCTAssertTrue(vm.isPrintCommandRunning)
        XCTAssertEqual(vm.consoleStatus, .running)
        XCTAssertFalse(vm.consoleOutput.contains("Listening"), "Quiet mode must not be used as the readiness signal")
        let selected = vm.selectedToolID, tab = vm.activeTab, values = vm.parameterValues
        vm.selectTool(id: "dicom-print")
        vm.selectCategory(.dataExport)
        XCTAssertEqual(vm.selectedToolID, selected)
        XCTAssertEqual(vm.activeTab, tab)
        XCTAssertEqual(vm.parameterValues, values)
        XCTAssertThrowsError(try vm.importPrintCommand("dicom-printscp queues"))
        await vm.executeCommand() // A second Run cannot create another command.
        XCTAssertTrue(vm.commandHistory.isEmpty)
        vm.stopPrintCommand()
        let firstStopped = await waitUntil { firstFinished }
        guard firstStopped else { XCTFail("Stop did not finish the listener promptly"); return }
        await first.value
        XCTAssertFalse(vm.isPrintCommandRunning)
        XCTAssertNil(vm.printListenerPort)
        XCTAssertEqual(vm.commandHistory.count, 1)
        XCTAssertEqual(vm.commandHistory.last?.exitCode, 130)
        XCTAssertTrue(vm.consoleOutput.contains("Stopped by user"))

        try serve(port)
        var secondFinished = false
        let second = Task { await vm.executeCommand(); secondFinished = true }
        defer { second.cancel(); vm.stopPrintCommand() }
        let secondReady = await waitUntil { vm.printListenerPort != nil || secondFinished }
        guard secondReady, vm.printListenerPort == port else {
            vm.stopPrintCommand(); XCTFail("Stopped listener still owns port \(port): \(vm.consoleOutput)"); return
        }
        XCTAssertFalse(vm.printCancellationRequested)
        vm.stopPrintCommand()
        let secondStopped = await waitUntil { secondFinished }
        guard secondStopped else { XCTFail("Restarted listener did not stop promptly"); return }
        await second.value
        XCTAssertEqual(vm.commandHistory.count, 2)
        let lastRunConsole = vm.consoleOutput
        vm.loadFromService()
        XCTAssertEqual(vm.consoleOutput, lastRunConsole, "Backing state must not concatenate prior print runs")
        XCTAssertEqual(vm.commandHistory.last?.exitCode, 130)
        XCTAssertNil(vm.printListenerPort)
        XCTAssertFalse(vm.isPrintCommandRunning)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    /// Request array: {name, command, expectedExit, stopAfterListening?,
    /// timeoutSeconds?, stopSignalPath?, readyPath?}. A ready JSON file is written
    /// while the real listener is active; an external driver may then send film
    /// and create stopSignalPath. Without a signal path, stopAfterListening stops
    /// immediately after readiness. No request may enable paper spooling.
    func testConfiguredWorkshopActions() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let requestPath = env["DICOMKIT_M6_WORKSHOP_REQUESTS"],
              let outputPath = env["DICOMKIT_M6_WORKSHOP_OUTPUT"],
              let settingsPath = env["DICOMKIT_PRINT_TEST_SETTINGS_DIRECTORY"] else {
            throw XCTSkip("Set M6 Workshop request/output paths and an isolated print settings directory to run the external campaign")
        }
        guard settingsPath.hasPrefix("/"),
              PrintCommandContext.defaultSettingsDirectory.standardizedFileURL == URL(fileURLWithPath: settingsPath).standardizedFileURL else {
            XCTFail("The DEBUG print settings override must resolve to the external campaign directory"); return
        }
        let requests = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: requestPath))) as? [[String: Any]])
        XCTAssertFalse(requests.isEmpty)
        var records: [[String: Any]] = []
        func write(_ object: Any, to path: String) throws {
            try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        for request in requests {
            let name = try XCTUnwrap(request["name"] as? String)
            let text = try XCTUnwrap(request["command"] as? String)
            let expectedExit = try XCTUnwrap(request["expectedExit"] as? Int)
            let tool = try XCTUnwrap(text.split(whereSeparator: { $0 == " " || $0 == "\t" }).first).description
            guard ["dicom-print", "dicom-printscp"].contains(tool) else { XCTFail("Unexpected harness tool: \(tool)"); continue }
            let vm = makeVM(tool)
            try vm.importPrintCommand(text)
            guard !vm.parameterValues.contains(where: { value in
                vm.parameterDefinitions.contains { $0.id == value.parameterID && $0.flag == "--allow-paper" } && value.stringValue == "true"
            }) else { XCTFail("The synthetic Workshop campaign must never enable physical paper output"); continue }
            XCTAssertTrue(vm.isCommandValid, name)
            let preview = vm.commandPreview
            let snapshot = Dictionary(uniqueKeysWithValues: vm.parameterValues.map { ($0.parameterID, $0.stringValue) })
            let stopAfterListening = request["stopAfterListening"] as? Bool ?? false
            let timeout = request["timeoutSeconds"] as? Double ?? 30
            let readyPath = request["readyPath"] as? String ?? outputPath + ".ready.json"
            let stopPath = request["stopSignalPath"] as? String
            var finished = false, readyPort: UInt16?, timedOut = false
            let action = Task { await vm.executeCommand(); finished = true }
            defer { action.cancel(); vm.stopPrintCommand() }
            let deadline = Date().addingTimeInterval(timeout)
            while !finished && Date() < deadline {
                if let port = vm.printListenerPort, readyPort == nil {
                    readyPort = port
                    try write(["name": name, "port": Int(port), "running": vm.isPrintCommandRunning,
                               "status": vm.consoleStatus.rawValue, "preview": preview], to: readyPath)
                    // Exercise the public guards while an actual listener runs.
                    let oldTool = vm.selectedToolID, oldTab = vm.activeTab
                    vm.selectTool(id: "dicom-info"); vm.selectCategory(.dataExport)
                    XCTAssertEqual(vm.selectedToolID, oldTool, name)
                    XCTAssertEqual(vm.activeTab, oldTab, name)
                    XCTAssertThrowsError(try vm.importPrintCommand("dicom-printscp queues"), name)
                }
                if stopAfterListening, readyPort != nil,
                   stopPath == nil || FileManager.default.fileExists(atPath: stopPath!) { vm.stopPrintCommand() }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            if !finished {
                timedOut = true; vm.stopPrintCommand(); action.cancel()
                let stopped = await waitUntil { finished }
                guard stopped else { XCTFail("\(name) did not complete or stop before the harness timeout"); return }
            }
            await action.value
            XCTAssertFalse(timedOut, name + " exceeded its bounded execution deadline")
            XCTAssertFalse(vm.isPrintCommandRunning, name)
            XCTAssertNil(vm.printListenerPort, name)
            XCTAssertEqual(vm.commandHistory.count, 1, name)
            XCTAssertEqual(vm.commandHistory.last?.exitCode, expectedExit, name + "\n" + vm.consoleOutput)
            XCTAssertEqual(vm.consoleStatus, expectedExit == 0 ? .success : .error, name)
            records.append(["name": name, "tool": tool, "command": text, "preview": preview,
                "values": snapshot, "status": vm.consoleStatus.rawValue, "console": vm.consoleOutput,
                "historyCount": vm.commandHistory.count, "exit": (vm.commandHistory.last?.exitCode).map { $0 as Any } ?? NSNull(),
                "listenerPortWhileActive": readyPort.map { Int($0) as Any } ?? NSNull(),
                "runningAfterCompletion": vm.isPrintCommandRunning, "timedOut": timedOut,
                "settingsDirectory": settingsPath])
            try write(records, to: outputPath)
        }
    }
}
