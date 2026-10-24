import Foundation
import Testing
@testable import DICOMToolbox

// MARK: - dicom-study Subcommand Form Tests

@Suite("DicomStudy Subcommand Form Tests")
struct DicomStudySubcommandTests {
    @Test("dicom-study organize with input and pattern")
    func testOrganizeWithPattern() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomStudy)
        let command = builder.buildCommand(values: [
            "input": "/data/studies",
            "pattern": "{PatientName}/{StudyDate}",
        ], subcommand: "organize")
        #expect(command.contains("dicom-study"))
        #expect(command.contains("organize"))
        #expect(command.contains("/data/studies"))
        #expect(command.contains("--pattern '{PatientName}/{StudyDate}'"))
    }

    @Test("dicom-study organize with output directory")
    func testOrganizeWithOutput() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomStudy)
        let command = builder.buildCommand(values: [
            "input": "/data/raw",
            "output": "/data/organized",
        ], subcommand: "organize")
        #expect(command.contains("/data/raw"))
        #expect(command.contains("--output /data/organized"))
    }

    @Test("dicom-study summary with JSON format")
    func testSummaryJSON() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomStudy)
        let command = builder.buildCommand(values: [
            "input": "/data/study1",
            "format": "json",
        ], subcommand: "summary")
        #expect(command.contains("summary"))
        #expect(command.contains("/data/study1"))
        #expect(command.contains("--format json"))
    }

    @Test("dicom-study check with expected series count")
    func testCheckExpectedSeries() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomStudy)
        let command = builder.buildCommand(values: [
            "input": "/data/study",
            "expected-series": "5",
        ], subcommand: "check")
        #expect(command.contains("check"))
        #expect(command.contains("--expected-series 5"))
    }

    @Test("dicom-study compare with two directories")
    func testCompareTwoStudies() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomStudy)
        let command = builder.buildCommand(values: [
            "input": "/data/study1",
            "input2": "/data/study2",
            "format": "text",
        ], subcommand: "compare")
        #expect(command.contains("compare"))
        #expect(command.contains("/data/study1"))
        #expect(command.contains("--format text"))
    }
}

// MARK: - dicom-uid Generate Command Tests

@Suite("DicomUID Command Generation Tests")
struct DicomUIDCommandTests {
    @Test("dicom-uid generate with count")
    func testGenerateWithCount() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomUID)
        let command = builder.buildCommand(values: [
            "count": "5",
        ], subcommand: "generate")
        #expect(command.contains("dicom-uid"))
        #expect(command.contains("generate"))
        #expect(command.contains("--count 5"))
    }

    @Test("dicom-uid generate with root OID")
    func testGenerateWithRoot() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomUID)
        let command = builder.buildCommand(values: [
            "root": "1.2.840.123456",
        ], subcommand: "generate")
        #expect(command.contains("--root 1.2.840.123456"))
    }

    @Test("dicom-uid generate with JSON output")
    func testGenerateWithJSON() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomUID)
        let command = builder.buildCommand(values: [
            "json": "true",
        ], subcommand: "generate")
        #expect(command.contains("--json"))
    }

    @Test("dicom-uid validate requires UID")
    func testValidateRequiresUID() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomUID)
        let valid = builder.isValid(values: ["uid": "1.2.840.10008.1.2"], subcommand: "validate")
        #expect(valid)
        let invalid = builder.isValid(values: [:], subcommand: "validate")
        #expect(!invalid)
    }

    @Test("dicom-uid lookup command generation")
    func testLookup() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomUID)
        let command = builder.buildCommand(values: [
            "uid": "1.2.840.10008.1.2",
        ], subcommand: "lookup")
        #expect(command.contains("lookup"))
        #expect(command.contains("1.2.840.10008.1.2"))
    }

    @Test("dicom-uid regenerate with input and output")
    func testRegenerate() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomUID)
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
            "output": "output.dcm",
            "root": "1.2.840.99999",
        ], subcommand: "regenerate")
        #expect(command.contains("regenerate"))
        #expect(command.contains("scan.dcm"))
        #expect(command.contains("--output output.dcm"))
        #expect(command.contains("--root 1.2.840.99999"))
    }
}

// MARK: - dicom-script Variable Parsing Tests

@Suite("DicomScript Command Tests")
struct DicomScriptCommandTests {
    @Test("dicom-script run with script file")
    func testRunWithScript() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomScript)
        let command = builder.buildCommand(values: [
            "script": "pipeline.dscript",
        ], subcommand: "run")
        #expect(command.contains("dicom-script"))
        #expect(command.contains("run"))
        #expect(command.contains("pipeline.dscript"))
    }

    @Test("dicom-script run with variables")
    func testRunWithVariables() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomScript)
        let command = builder.buildCommand(values: [
            "script": "pipeline.dscript",
            "variables": "INPUT=/data,OUTPUT=/out",
        ], subcommand: "run")
        #expect(command.contains("--variables INPUT=/data"))
        #expect(command.contains("--variables OUTPUT=/out"))
    }

    @Test("dicom-script run with parallel and dry-run")
    func testRunParallelDryRun() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomScript)
        let command = builder.buildCommand(values: [
            "script": "pipeline.dscript",
            "parallel": "true",
            "dry-run": "true",
        ], subcommand: "run")
        #expect(command.contains("--parallel"))
        #expect(command.contains("--dry-run"))
    }

    @Test("dicom-script validate requires script file")
    func testValidateRequiresScript() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomScript)
        let valid = builder.isValid(values: ["script": "test.dscript"], subcommand: "validate")
        #expect(valid)
        let invalid = builder.isValid(values: [:], subcommand: "validate")
        #expect(!invalid)
    }

    @Test("dicom-script template with output")
    func testTemplateWithOutput() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomScript)
        let command = builder.buildCommand(values: [
            "output": "/scripts/new.dscript",
        ], subcommand: "template")
        #expect(command.contains("template"))
        #expect(command.contains("--output /scripts/new.dscript"))
    }
}

// MARK: - Command Execution Tests

/// Thread-safe output collector for testing command execution
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _output: String = ""

    var output: String {
        lock.lock()
        defer { lock.unlock() }
        return _output
    }

    func append(_ text: String) {
        lock.lock()
        _output += text
        lock.unlock()
    }
}

@Suite("Command Execution Tests")
struct CommandExecutionTests {
    @Test("CommandExecutor runs simple command and returns exit code 0")
    func testSuccessfulExecution() async throws {
        let executor = CommandExecutor()
        let collector = OutputCollector()
        let exitCode = try await executor.execute(invocation: .init(executable: "/bin/echo", arguments: ["hello"])) { line in
            collector.append(line)
        }
        #expect(exitCode == 0)
        #expect(collector.output.contains("hello"))
    }

    @Test("CommandExecutor returns non-zero exit code for failing command")
    func testFailedExecution() async throws {
        let executor = CommandExecutor()
        let collector = OutputCollector()
        let exitCode = try await executor.execute(invocation: .init(executable: "/usr/bin/python3", arguments: ["-c", "import sys; sys.exit(42)"])) { line in
            collector.append(line)
        }
        #expect(exitCode == 42)
    }

    @Test("CommandExecutor captures stderr output")
    func testStderrCapture() async throws {
        let executor = CommandExecutor()
        let collector = OutputCollector()
        let exitCode = try await executor.execute(invocation: .init(executable: "/usr/bin/python3", arguments: ["-c", "import sys; sys.stderr.write('error_msg')"])) { line in
            collector.append(line)
        }
        #expect(exitCode == 0)
        #expect(collector.output.contains("error_msg"))
    }

    @Test("CommandExecutor streams multiline output")
    func testMultilineOutput() async throws {
        let executor = CommandExecutor()
        let collector = OutputCollector()
        let exitCode = try await executor.execute(invocation: .init(executable: "/usr/bin/printf", arguments: ["%s\\n", "line1", "line2", "line3"])) { line in
            collector.append(line)
        }
        #expect(exitCode == 0)
        #expect(collector.output.contains("line1"))
        #expect(collector.output.contains("line2"))
        #expect(collector.output.contains("line3"))
    }

    @Test("CommandExecutor cancel terminates process")
    func testCancelExecution() async throws {
        let executor = CommandExecutor()
        let collector = OutputCollector()

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            await executor.cancel()
        }

        do {
            _ = try await executor.execute(invocation: .init(executable: "/bin/sleep", arguments: ["60"])) { line in
                collector.append(line)
            }
            Issue.record("Cancelled command returned normally")
        } catch is CancellationError { }
        #expect(await executor.isRunning == false)
    }

    @Test("CommandExecutor handles command not found")
    func testCommandNotFound() async throws {
        let executor = CommandExecutor()
        let collector = OutputCollector()
        do {
            _ = try await executor.execute(invocation: .init(executable: "nonexistent_command_xyz_12345", arguments: [])) { line in
                collector.append(line)
            }
            Issue.record("Unknown executable returned normally")
        } catch CommandExecutor.ExecutionError.executableNotFound { }
        #expect(await executor.isRunning == false)
    }
}

// MARK: - Command History Tests

@Suite("Command History Tests")
struct CommandHistoryTests {
    @Test("CommandHistoryEntry stores all fields correctly")
    func testEntryFields() {
        let entry = CommandHistoryEntry(
            toolID: "dicom-info",
            subcommand: nil,
            parameterValues: ["filePath": "scan.dcm"],
            commandString: "dicom-info scan.dcm",
            exitCode: 0
        )
        #expect(entry.toolID == "dicom-info")
        #expect(entry.subcommand == nil)
        #expect(entry.commandString == "dicom-info scan.dcm")
        #expect(entry.exitCode == 0)
        #expect(entry.isSuccess)
    }

    @Test("CommandHistoryEntry withExitCode creates updated copy")
    func testWithExitCode() {
        let entry = CommandHistoryEntry(
            toolID: "dicom-echo",
            parameterValues: [:],
            commandString: "dicom-echo pacs://host:11112"
        )
        #expect(entry.exitCode == nil)

        let completed = entry.withExitCode(0)
        #expect(completed.exitCode == 0)
        #expect(completed.isSuccess)
        #expect(completed.id == entry.id)
        #expect(completed.commandString == entry.commandString)
    }

    @Test("CommandHistory limits to 50 entries")
    func testMaxEntries() {
        var entries: [CommandHistoryEntry] = []
        for i in 0..<60 {
            let entry = CommandHistoryEntry(
                toolID: "dicom-uid",
                parameterValues: [:],
                commandString: "dicom-uid generate --count \(i)",
                exitCode: 0
            )
            CommandHistory.addEntry(entry, to: &entries)
        }
        #expect(entries.count == CommandHistory.maxEntries)
        // Most recent entry should be first
        #expect(entries.first?.commandString == "dicom-uid generate --count 59")
    }

    @Test("CommandHistory adds entries in reverse chronological order")
    func testOrderPreserved() {
        var entries: [CommandHistoryEntry] = []
        let first = CommandHistoryEntry(
            toolID: "dicom-info",
            parameterValues: [:],
            commandString: "dicom-info first.dcm",
            exitCode: 0
        )
        let second = CommandHistoryEntry(
            toolID: "dicom-info",
            parameterValues: [:],
            commandString: "dicom-info second.dcm",
            exitCode: 0
        )
        CommandHistory.addEntry(first, to: &entries)
        CommandHistory.addEntry(second, to: &entries)
        #expect(entries.first?.commandString == "dicom-info second.dcm")
    }

    @Test("CommandHistory exports shell script format")
    func testExportShellScript() {
        let entries = [
            CommandHistoryEntry(
                toolID: "dicom-info",
                parameterValues: [:],
                commandString: "dicom-info scan.dcm",
                exitCode: 0
            ),
            CommandHistoryEntry(
                toolID: "dicom-echo",
                parameterValues: [:],
                commandString: "dicom-echo pacs://host:11112",
                exitCode: 0
            ),
        ]
        let script = CommandHistory.exportAsShellScript(entries)
        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.contains("DICOMToolbox Command History"))
        #expect(script.contains("dicom-info scan.dcm"))
        #expect(script.contains("dicom-echo pacs://host:11112"))
    }

    @Test("Failed command entry reports isSuccess false")
    func testFailedEntry() {
        let entry = CommandHistoryEntry(
            toolID: "dicom-validate",
            parameterValues: [:],
            commandString: "dicom-validate bad.dcm",
            exitCode: 1
        )
        #expect(!entry.isSuccess)
    }
}

// MARK: - Tool Registry Automation Tests

@Suite("ToolRegistry Automation Category Tests")
struct ToolRegistryAutomationTests {
    @Test("Automation category has 3 tools")
    func testAutomationToolCount() {
        let automationTools = ToolRegistry.tools(for: .automation)
        #expect(automationTools.count == 3)
    }

    @Test("dicom-study has 5 subcommands")
    func testStudySubcommands() {
        let tool = ToolRegistry.dicomStudy
        #expect(tool.subcommands?.count == 5)
        let ids = tool.subcommands?.map(\.id) ?? []
        #expect(ids.contains("organize"))
        #expect(ids.contains("summary"))
        #expect(ids.contains("check"))
        #expect(ids.contains("stats"))
        #expect(ids.contains("compare"))
    }

    @Test("dicom-uid has 4 subcommands")
    func testUIDSubcommands() {
        let tool = ToolRegistry.dicomUID
        #expect(tool.subcommands?.count == 4)
        let ids = tool.subcommands?.map(\.id) ?? []
        #expect(ids.contains("generate"))
        #expect(ids.contains("validate"))
        #expect(ids.contains("lookup"))
        #expect(ids.contains("regenerate"))
    }

    @Test("dicom-script has 3 subcommands")
    func testScriptSubcommands() {
        let tool = ToolRegistry.dicomScript
        #expect(tool.subcommands?.count == 3)
        let ids = tool.subcommands?.map(\.id) ?? []
        #expect(ids.contains("run"))
        #expect(ids.contains("validate"))
        #expect(ids.contains("template"))
    }
}
