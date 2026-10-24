import Foundation
import XCTest
import DICOMCore
import DICOMKit
@testable import DICOMStudio

/// M5 Workshop capability contracts. Temporary scripts and images are synthetic.
@MainActor
final class M5WorkshopContractTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("m5-workshop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func model(_ tool: String, _ values: [String: String] = [:]) -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
        vm.selectTool(id: tool)
        for (id, value) in values { vm.updateParameterValue(parameterID: id, value: value) }
        return vm
    }

    private func body(_ vm: CLIWorkshopViewModel) -> String {
        let prefix = "$ \(vm.commandPreview)\n\n"
        XCTAssertTrue(vm.consoleOutput.hasPrefix(prefix))
        return String(vm.consoleOutput.dropFirst(prefix.count))
    }

    func testEveryCatalogDefinitionHasUniqueParameterIdentity() {
        for tool in ToolCatalogHelpers.allTools() {
            let definitions = ToolCatalogHelpers.parameterDefinitions(for: tool.id)
            XCTAssertEqual(Set(definitions.map(\.id)).count, definitions.count, tool.id)
        }
    }

    func testBurnedInPHIHasOneBindingAndOneFlagInBothExperienceModes() {
        let vm = model("dicom-anon", ["inputPath": "/synthetic.dcm"])
        for mode in [CLIExperienceMode.beginner, .advanced] {
            vm.experienceMode = mode
            let rendered = vm.visibleParameters() + vm.advancedParameters()
            XCTAssertEqual(rendered.filter { $0.id == "allow-burned-in-phi" }.count, 1)
            for enabled in [true, false, true] {
                vm.updateParameterValue(parameterID: "allow-burned-in-phi", value: String(enabled))
                XCTAssertEqual(vm.parameterValues.filter { $0.parameterID == "allow-burned-in-phi" }.count, 1)
                XCTAssertEqual(vm.commandPreview.components(separatedBy: "--allow-burned-in-phi").count - 1, enabled ? 1 : 0)
            }
        }
    }

    func testLiveScriptRefusesBeforeExecutionAndOutputPreparation() async throws {
        let root = try directory()
        let log = root.appendingPathComponent("must-not-exist/run.log")
        let vm = model("dicom-script", ["scriptPath": root.appendingPathComponent("unread.dcmscript").path,
                                        "dryRun": "false", "log": log.path])
        XCTAssertFalse(vm.isCommandValid)
        XCTAssertTrue(vm.executionUnavailableReason?.contains("Live script execution is unavailable") == true)
        XCTAssertFalse(vm.commandPreview.contains("--dry-run"), "The supported CLI live command remains copyable")
        await vm.executeCommand()
        XCTAssertEqual(vm.consoleStatus, .error)
        XCTAssertTrue(vm.commandHistory.isEmpty, "A rejected capability must not create a started execution")
        XCTAssertFalse(vm.consoleOutput.contains("Starting script execution"))
        XCTAssertFalse(vm.consoleOutput.contains("No such file"), "The script must not be read on this path")
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.deletingLastPathComponent().path))
        vm.updateParameterValue(parameterID: "dryRun", value: "true")
        XCTAssertNil(vm.executionUnavailableReason)
        XCTAssertTrue(vm.isCommandValid)
        XCTAssertEqual(vm.runActionTitle, "Dry Run")
    }

    func testTemplateValidateAndDryRunUseSharedSupportedEngines() async throws {
        let root = try directory()
        let script = root.appendingPathComponent("valid.dcmscript")
        try "dicom-info missing-synthetic.dcm\ndicom-uid generate\n".write(to: script, atomically: true, encoding: .utf8)
        let vm = model("dicom-script", ["scriptPath": script.path])
        XCTAssertEqual(vm.runActionTitle, "Dry Run")
        XCTAssertTrue(vm.commandPreview.contains("--dry-run"))
        await vm.executeCommand()
        XCTAssertEqual(vm.consoleStatus, .success, vm.consoleOutput)
        XCTAssertEqual(vm.commandHistory.first?.exitCode, 0)
        var expected = "", calls = 0
        try ScriptExecutor(runCommand: { _, _ in calls += 1; return ("", 0) }, log: { expected += $0 + "\n" })
            .execute(scriptPath: script.path, variables: [:], parallel: false, verbose: false, dryRun: true, logPath: nil)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(body(vm), expected)
        XCTAssertTrue(body(vm).contains("Dry run completed - no commands were actually executed"))

        vm.updateParameterValue(parameterID: "operation", value: "validate")
        XCTAssertEqual(vm.runActionTitle, "Validate")
        XCTAssertFalse(vm.commandPreview.contains("--dry-run"))
        await vm.executeCommand()
        XCTAssertEqual(vm.consoleStatus, .success, vm.consoleOutput)
        XCTAssertEqual(body(vm), ScriptConsole.validationLines(issues: []).joined(separator: "\n") + "\n")

        vm.updateParameterValue(parameterID: "operation", value: "template")
        XCTAssertEqual(vm.runActionTitle, "Generate Template")
        XCTAssertFalse(vm.commandPreview.contains(script.path))
        await vm.executeCommand()
        XCTAssertEqual(vm.consoleStatus, .success)
        XCTAssertEqual(body(vm), try TemplateGenerator().generate(templateName: "workflow"))
    }

    func testUnknownNestedToolsFailValidationAndDryRunDeterministically() async throws {
        let root = try directory()
        let cases = [
            ("dicom-not-a-tool input.dcm", "Command 1: Unknown DICOM tool 'dicom-not-a-tool'"),
            ("dicom-not-a-tool --option=value", "Command 1: Unknown DICOM tool 'dicom-not-a-tool'"),
            ("dicom-info input.dcm | dicom-not-a-tool input.dcm", "Command 1 (pipeline): Command 2: Unknown DICOM tool 'dicom-not-a-tool'"),
            ("if exists absent.dcm\ndicom-not-a-tool input.dcm\nelse\ndicom-info input.dcm\nendif", "Command 1 (then): Command 1: Unknown DICOM tool 'dicom-not-a-tool'"),
            ("if exists absent.dcm\ndicom-info input.dcm | dicom-not-a-tool input.dcm\nendif", "Parse error at line 2: Pipelines inside conditional blocks are not supported"),
            ("dicom-cloud upload input.dcm", "Command 1: DICOM tool 'dicom-cloud' is unavailable in this build")
        ]
        for (index, example) in cases.enumerated() {
            let file = root.appendingPathComponent("invalid-\(index).dcmscript")
            try example.0.write(to: file, atomically: true, encoding: .utf8)
            XCTAssertEqual(try ScriptValidator().validate(scriptPath: file.path, verbose: false), [example.1])
            var runnerCalls = 0, output = ""
            let log = root.appendingPathComponent("must-not-write-\(index).log")
            XCTAssertThrowsError(try ScriptExecutor(runCommand: { _, _ in runnerCalls += 1; return ("", 0) }, log: { output += $0 })
                .execute(scriptPath: file.path, variables: [:], parallel: false, verbose: true, dryRun: true, logPath: log.path)) { error in
                    XCTAssertTrue(error.localizedDescription.contains(example.1))
                }
            XCTAssertEqual(runnerCalls, 0)
            XCTAssertTrue(output.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: log.path))
            for operation in ["validate", "run"] {
                let unusedLog = root.appendingPathComponent("absent-\(index)-\(operation)/log.txt")
                let vm = model("dicom-script", ["operation": operation, "scriptPath": file.path, "log": unusedLog.path])
                await vm.executeCommand()
                XCTAssertEqual(vm.consoleStatus, .error, example.0)
                XCTAssertEqual(vm.commandHistory.first?.exitCode, 1)
                XCTAssertTrue(vm.consoleOutput.contains(example.1))
                XCTAssertFalse(vm.consoleOutput.contains("completed successfully"))
                XCTAssertFalse(vm.consoleOutput.contains("Dry run completed"))
                XCTAssertFalse(FileManager.default.fileExists(atPath: unusedLog.deletingLastPathComponent().path))
            }
        }
    }

    func testRecognizedScriptToolsMatchActivePackageProducts() throws {
        let manifest = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Package.swift")
        let source = try String(contentsOf: manifest, encoding: .utf8).components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        let expression = try NSRegularExpression(pattern: #"\.executable\(\s*name:\s*"(dicom-[^"]+)""#)
        let range = NSRange(source.startIndex..., in: source)
        let names = Set(expression.matches(in: source, range: range).map {
            String(source[Range($0.range(at: 1), in: source)!])
        })
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(ScriptValidator.knownTools, names)
        let root = try directory(), script = root.appendingPathComponent("all-tools.dcmscript")
        try names.sorted().map { $0 + " --help" }.joined(separator: "\n").write(to: script, atomically: true, encoding: .utf8)
        XCTAssertEqual(try ScriptValidator().validate(scriptPath: script.path, verbose: false), [])
    }

    func testSharedLiveRunnerContractAndFailurePropagationRemainIntact() throws {
        let script = try directory().appendingPathComponent("live.dcmscript")
        try "dicom-info first.dcm\ndicom-info second.dcm\n".write(to: script, atomically: true, encoding: .utf8)
        var calls: [String] = []
        try ScriptExecutor(runCommand: { tool, args in calls.append(([tool] + args).joined(separator: " ")); return ("synthetic output", 0) })
            .execute(scriptPath: script.path, variables: [:], parallel: false, verbose: false, dryRun: false, logPath: nil)
        XCTAssertEqual(calls, ["dicom-info first.dcm", "dicom-info second.dcm"])
        calls.removeAll()
        XCTAssertThrowsError(try ScriptExecutor(runCommand: { tool, _ in calls.append(tool); return ("", 7) })
            .execute(scriptPath: script.path, variables: [:], parallel: false, verbose: false, dryRun: false, logPath: nil)) { error in
                XCTAssertTrue(error.localizedDescription.contains("status 7"))
            }
        XCTAssertEqual(calls, ["dicom-info"])
    }

    func testDryRunNameCheckPreservesOptionAndVariableValues() throws {
        let script = try directory().appendingPathComponent("arguments.dcmscript")
        try "NAME = DOE*\ndicom-query localhost --patient-name ${NAME}\ndicom-info --format=json input.dcm\n"
            .write(to: script, atomically: true, encoding: .utf8)
        XCTAssertEqual(try ScriptValidator().validateCommandNames(scriptPath: script.path), [])
        var output = "", calls = 0
        try ScriptExecutor(runCommand: { _, _ in calls += 1; return ("", 0) }, log: { output += $0 + "\n" })
            .execute(scriptPath: script.path, variables: ["EXTRA": "with=equals"], parallel: false,
                     verbose: true, dryRun: true, logPath: nil)
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(output.contains("[DRY RUN] Would execute: dicom-query localhost --patient-name DOE*"))
        XCTAssertTrue(output.contains("[DRY RUN] Would execute: dicom-info --format=json input.dcm"))
        XCTAssertFalse(output.contains("Script execution completed successfully"))
        // A quoted pipe is an argument, not unsupported conditional syntax.
        let literalPipe = "if exists absent.dcm\ndicom-info \"literal|name.dcm\"\nendif"
        try literalPipe.write(to: script, atomically: true, encoding: .utf8)
        XCTAssertEqual(try ScriptValidator().validateCommandNames(scriptPath: script.path), [])
        let parsed = try ScriptParser().parse(content: literalPipe)
        guard case let .conditional(block) = parsed[0],
              case let .toolCommand(command) = block.thenCommands[0] else {
            return XCTFail("Expected a conditional tool command")
        }
        XCTAssertEqual(command.arguments, ["literal|name.dcm"])
        // Arbitrary custom runners remain legal on the live engine path.
        try "custom-runner-tool --option=value".write(to: script, atomically: true, encoding: .utf8)
        try ScriptExecutor(runCommand: { tool, arguments in
            XCTAssertEqual(tool, "custom-runner-tool")
            XCTAssertEqual(arguments, ["--option=value"])
            calls += 1
            return ("", 0)
        }).execute(scriptPath: script.path, variables: [:], parallel: false, verbose: false, dryRun: false, logPath: nil)
        XCTAssertEqual(calls, 1)
    }

    func testQRHasExplicitAutoAndReviewAndRefusesStaleInteractiveBeforeDispatch() async throws {
        let output = try directory().appendingPathComponent("not-created")
        let vm = model("dicom-qr", ["host": "127.0.0.1", "method": "c-get", "output": output.path + "/"])
        let mode = try XCTUnwrap(vm.parameterDefinitions.first { $0.id == "mode" })
        XCTAssertEqual(mode.allowedValues, ["auto", "review"])
        XCTAssertEqual(mode.defaultValue, "auto")
        for value in mode.allowedValues {
            vm.updateParameterValue(parameterID: "mode", value: value)
            XCTAssertNil(vm.executionUnavailableReason)
            XCTAssertTrue(vm.commandPreview.contains("--" + value))
            XCTAssertFalse(vm.commandPreview.contains(value == "auto" ? "--review" : "--auto"))
        }
        for stale in ["interactive", "automatic", "unknown"] {
            vm.updateParameterValue(parameterID: "mode", value: stale)
            XCTAssertFalse(vm.isCommandValid)
            await vm.executeCommand()
            XCTAssertTrue(vm.consoleOutput.contains("Interactive selection is unavailable"))
            XCTAssertEqual(vm.consoleStatus, .error)
            XCTAssertTrue(vm.commandHistory.isEmpty)
            XCTAssertTrue(vm.lastRetrievedFiles.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testSinglePHIControlPreservesSharedAnonymizationRefusalAndIdentityMarking() async throws {
        let root = try directory(), input = root.appendingPathComponent("synthetic.dcm"), output = root.appendingPathComponent("anon.dcm")
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("2.25.5001", for: .sopInstanceUID, vr: .UI)
        ds.setString("2.25.5002", for: .studyInstanceUID, vr: .UI)
        ds.setString("2.25.5003", for: .seriesInstanceUID, vr: .UI)
        ds.setString("M5^SYNTHETIC", for: .patientName, vr: .PN)
        ds.setString("YES", for: .burnedInAnnotation, vr: .CS)
        let original = try DICOMFile.create(dataSet: ds).write()
        try original.write(to: input)
        let vm = model("dicom-anon", ["inputPath": input.path, "output": output.path, "clean-pixel-data": "false"])
        await vm.executeCommand()
        XCTAssertEqual(vm.consoleStatus, .error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        vm.updateParameterValue(parameterID: "allow-burned-in-phi", value: "true")
        await vm.executeCommand()
        XCTAssertEqual(vm.consoleStatus, .success, vm.consoleOutput)
        let written = try DICOMFile.read(from: Data(contentsOf: output))
        XCTAssertEqual(written.dataSet.string(for: DICOMCore.Tag(group: 0x0012, element: 0x0062)), "NO")
        XCTAssertEqual(try Data(contentsOf: input), original)
    }
}
