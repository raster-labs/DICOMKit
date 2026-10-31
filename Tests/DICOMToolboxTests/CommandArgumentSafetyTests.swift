import Foundation
import Testing
@testable import DICOMToolbox

@Suite("Toolbox literal argument safety")
struct CommandArgumentSafetyTests {
    private func builder() -> CommandBuilder {
        CommandBuilder(tool: ToolDefinition(id: "dicom-info", name: "Fixture", icon: "", category: .fileInspection,
            description: "", parameters: [
                ParameterDefinition(id: "file", cliFlag: "@argument", label: "File", help: "", type: .file),
                ParameterDefinition(id: "value", cliFlag: "--value", label: "Value", help: "", type: .string),
                ParameterDefinition(id: "date", cliFlag: "--study-date", label: "Date", help: "", type: .string)
            ]))
    }

    @Test("Structured values preserve DICOM VM, wildcards and shell characters", arguments: [
        "DOE*", "DOE?", "ORIGINAL\\PRIMARY", "two words", "O'Neil", "a\"b", "line\nbreak",
        "a;b", "$(touch sentinel)", "`touch sentinel`", "$HOME", "=ls", "=printf", "=not-a-command"
    ])
    func literalValues(_ value: String) {
        let invocation = builder().buildInvocation(values: ["file": "space path/image.dcm", "value": value])
        #expect(invocation.executable == "dicom-info")
        #expect(invocation.arguments == ["space path/image.dcm", "--value", value])
        #expect(builder().buildCommand(values: ["file": "space path/image.dcm", "value": value]) == invocation.commandString)
    }

    @Test("Leading hyphen range is attached to its option")
    func ranges() {
        let invocation = builder().buildInvocation(values: ["file": "scan.dcm", "date": "-20261024"])
        #expect(invocation.arguments == ["scan.dcm", "--study-date=-20261024"])
        #expect(invocation.commandString.contains("--study-date=-20261024"))
    }

    @Test("Default network values use the same literal option encoding")
    func networkDefaults() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho,
                                     networkConfig: NetworkConfig(aeTitle: "-SCU", calledAET: "SCP O'Neil"))
        let invocation = builder.buildInvocation(values: [:])
        #expect(invocation.arguments.contains("--aet=-SCU"))
        let index = invocation.arguments.firstIndex(of: "--called-aet")
        #expect(index.map { invocation.arguments[$0 + 1] } == "SCP O'Neil")
        #expect(invocation.commandString == builder.buildCommand(values: [:]))
    }

    @Test("History replay uses persisted argv and its matching preview")
    func history() throws {
        let invocation = builder().buildInvocation(values: ["file": "O'Neil scan.dcm", "value": "DOE*\\PRIMARY"])
        let entry = CommandHistoryEntry(toolID: "dicom-info", parameterValues: [:],
                                        commandString: "untrusted display text", invocation: invocation)
        let decoded = try JSONDecoder().decode(CommandHistoryEntry.self, from: JSONEncoder().encode(entry.withExitCode(0)))
        #expect(decoded.replayInvocation == invocation)
        #expect(decoded.displayCommand == invocation.commandString)
        #expect(decoded.copyableCommand == invocation.commandString)
        #expect(CommandHistory.exportAsShellScript([decoded]).contains(invocation.commandString))
    }

    @Test("Legacy history remains readable but raw text cannot become executable replay/export/copy")
    func legacyHistory() throws {
        let entry = CommandHistoryEntry(toolID: "dicom-info", parameterValues: [:], commandString: "scan; touch sentinel\nrm example")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        object.removeValue(forKey: "invocation")
        let legacy = try JSONDecoder().decode(CommandHistoryEntry.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.replayInvocation == nil)
        #expect(legacy.displayCommand == entry.commandString)
        #expect(legacy.copyableCommand.components(separatedBy: "\n").allSatisfy { $0.hasPrefix("# ") })
        #expect(!CommandHistory.exportAsShellScript([legacy]).contains("\nrm example"))
    }

    @Test("A different executable in history is not replayable")
    func mismatchedHistoryExecutable() {
        let entry = CommandHistoryEntry(toolID: "dicom-info", parameterValues: [:], commandString: "ignored",
                                        invocation: CommandInvocation(executable: "/bin/sh", arguments: ["-c", "bad"]))
        #expect(entry.replayInvocation == nil)
        #expect(entry.copyableCommand.hasPrefix("# "))
    }
}

#if os(macOS) || os(Linux)
private final class CapturedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    func append(_ text: String) { lock.lock(); value += text; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return value }
}

@Suite("Toolbox process safety", .serialized)
struct CommandExecutorSafetyTests {
    private let python = "/usr/bin/python3"

    private func waitFor(_ output: CapturedOutput, containing value: String) async throws -> Bool {
        for _ in 0..<200 {
            if output.text.contains(value) { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test("Direct spawn captures literal argv without executing metacharacters")
    func argvCapture() async throws {
        let sentinel = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: sentinel) }
        let values = ["space path/image.dcm", "DOE*", "?", "ORIGINAL\\PRIMARY", "O'Neil", "a\"b", "line\nbreak",
                      "; touch \(sentinel.path)", "$(touch \(sentinel.path))", "`touch \(sentinel.path)`", "$HOME", "", "=ls"]
        let invocation = CommandInvocation(executable: python, arguments: ["-c", "import json,sys; print(json.dumps(sys.argv[1:]))"] + values)
        let output = CapturedOutput()
        let executor = CommandExecutor()
        let code = try await executor.execute(invocation: invocation) { output.append($0) }
        #expect(code == 0)
        let received = try JSONDecoder().decode([String].self, from: Data(output.text.utf8))
        #expect(received == values)
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
        #expect(await executor.isRunning == false)
    }

    @Test("Copied commands round-trip through sh and zsh without expansion")
    func copiedCommand() async throws {
        let values = ["DOE*", "?", "ORIGINAL\\PRIMARY", "O'Neil", "two words", "\"quote\"", "line\nbreak", ";", "$HOME", "$(echo wrong)", "", "=ls", "=printf", "=not-a-command"]
        let command = CommandInvocation(executable: python, arguments: ["-c", "import json,sys; print(json.dumps(sys.argv[1:]))"] + values)
        for shell in ["/bin/sh", "/bin/zsh"] where FileManager.default.isExecutableFile(atPath: shell) {
            let output = CapturedOutput()
            // Shell use is intentional only in this copy/paste oracle, never normal tool execution.
            let code = try await CommandExecutor().execute(invocation: .init(executable: shell, arguments: ["-f", "-c", command.commandString])) { output.append($0) }
            #expect(code == 0)
            #expect(try JSONDecoder().decode([String].self, from: Data(output.text.utf8)) == values)
        }
    }

    @Test("Both streams arrive before completion, preserve split UTF8, and drain final output")
    func streaming() async throws {
        let executor = CommandExecutor(), output = CapturedOutput()
        let script = "import os,time; os.write(1,b'ready\\n'); os.write(2,b'error\\n'); time.sleep(0.2); os.write(1,b'\\xc3'); time.sleep(0.05); os.write(1,b'\\xa9'); time.sleep(0.1); os.write(2,b'last')"
        let task = Task { try await executor.execute(invocation: .init(executable: python, arguments: ["-c", script])) { output.append($0) } }
        let early = try await waitFor(output, containing: "ready")
        #expect(early)
        #expect(await executor.isRunning)
        #expect(try await task.value == 0)
        #expect(output.text.contains("ready\n"))
        #expect(output.text.contains("error\n"))
        #expect(output.text.contains("é"))
        #expect(!output.text.contains("�"))
        #expect(output.text.hasSuffix("last"))
    }

    @Test("Immediate exit and large stdout/stderr do not lose completion or deadlock")
    func exitAndDrain() async throws {
        let executor = CommandExecutor()
        for _ in 0..<12 {
            #expect(try await executor.execute(invocation: .init(executable: "/usr/bin/true", arguments: [])) { _ in } == 0)
        }
        let output = CapturedOutput()
        let code = try await executor.execute(invocation: .init(executable: python, arguments: ["-c", "import os,sys; os.write(1,b'x'*200000); os.write(2,b'y'*200000); sys.exit(7)"])) { output.append($0) }
        #expect(code == 7)
        #expect(output.text.filter { $0 == "x" }.count == 200000)
        #expect(output.text.filter { $0 == "y" }.count == 200000)
    }

    @Test("Cancellation terminates an uncooperative group and rejects overlap until cleanup")
    func cancellation() async throws {
        let executor = CommandExecutor(), output = CapturedOutput()
        let script = "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print('ready',flush=True); time.sleep(20)"
        let task = Task { try await executor.execute(invocation: .init(executable: python, arguments: ["-c", script])) { output.append($0) } }
        let ready = try await waitFor(output, containing: "ready")
        await executor.cancel()
        #expect(ready)
        do {
            _ = try await executor.execute(invocation: .init(executable: "/usr/bin/true", arguments: [])) { _ in }
            Issue.record("Overlapping command was accepted during shutdown")
        } catch CommandExecutor.ExecutionError.alreadyRunning { }
        do { _ = try await task.value; Issue.record("Cancellation returned success") }
        catch is CancellationError { }
        #expect(await executor.isRunning == false)
        #expect(try await executor.execute(invocation: .init(executable: "/usr/bin/true", arguments: [])) { _ in } == 0)
    }

    @Test("Task cancellation reaches the owned process")
    func taskCancellation() async throws {
        let executor = CommandExecutor(), output = CapturedOutput()
        let task = Task { try await executor.execute(invocation: .init(executable: python, arguments: ["-c", "import time; print('ready',flush=True); time.sleep(20)"])) { output.append($0) } }
        let ready = try await waitFor(output, containing: "ready")
        task.cancel()
        #expect(ready)
        do { _ = try await task.value; Issue.record("Cancelled task returned success") }
        catch is CancellationError { }
        #expect(await executor.isRunning == false)
    }

    @Test("Cancellation reaches descendants holding inherited pipes after their parent exits")
    func descendantCancellation() async throws {
        let executor = CommandExecutor(), output = CapturedOutput()
        let child = "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print('child-ready',flush=True); time.sleep(20)"
        let script = "import subprocess,sys; subprocess.Popen([sys.executable,'-c',sys.argv[1]])"
        let task = Task { try await executor.execute(invocation: .init(executable: python, arguments: ["-c", script, child])) { output.append($0) } }
        let ready = try await waitFor(output, containing: "child-ready")
        #expect(ready)
        let start = ContinuousClock.now
        await executor.cancel()
        do { _ = try await task.value; Issue.record("Cancelled group returned success") }
        catch is CancellationError { }
        #expect(start.duration(to: .now) < .seconds(4))
        #expect(await executor.isRunning == false)
    }

    @Test("Launch failure and invalid NUL leave executor reusable")
    func launchFailure() async throws {
        let executor = CommandExecutor()
        do {
            _ = try await executor.execute(invocation: .init(executable: "/no/such/tool", arguments: [])) { _ in }
            Issue.record("Missing executable accepted")
        } catch CommandExecutor.ExecutionError.executableNotFound { }
        do {
            _ = try await executor.execute(invocation: .init(executable: python, arguments: ["a\0b"])) { _ in }
            Issue.record("NUL argument accepted")
        } catch CommandExecutor.ExecutionError.invalidArgument { }
        let invalid = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: invalid) }
        try Data("not an executable image".utf8).write(to: invalid)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: invalid.path)
        do {
            _ = try await executor.execute(invocation: .init(executable: invalid.path, arguments: [])) { _ in }
            Issue.record("Invalid executable image accepted")
        } catch { }
        #expect(await executor.isRunning == false)
        #expect(try await executor.execute(invocation: .init(executable: "/usr/bin/true", arguments: [])) { _ in } == 0)
    }
}
#endif
