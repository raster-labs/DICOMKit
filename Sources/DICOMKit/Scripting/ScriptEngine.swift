// NEMA-verified: 2026a, checked 2026-10-01 — script interpreter, no DICOM-standard data except the templates' dicom-anon --profile ps315 = PS3.15 2026a E.1 Basic Application Level Confidentiality Profile, with --clean-pixel-data = Clean Pixel Data Option (E.3.1) (D202), and the query template's Study Date range as one PS3.4 2026a C.2.2.2.5 range value (D200); dicom-query / dicom-retrieve / dicom-archive template options checked against those tools' current option declarations (D201, D203); templates pass directories with --recursive and no > redirection since the runner uses no shell, validator flags globs/redirection, quoted arguments unquoted (D223)
import Foundation

// Shared scripting engine for the `dicom-script` CLI and DICOMStudio. Parser,
// validator, template generator, and executor live here. The executor never
// shells out itself — it calls an injected `CommandRunner`, so the library stays
// free of `Process` (the CLI supplies a real runner; a sandboxed app can supply a
// dry-run/no-op runner). Verbose output flows through an injected `log` closure.

// MARK: - Errors

public enum ScriptError: Error, LocalizedError {
    case scriptNotFound(String)
    case parseError(String, Int)
    case invalidVariable(String)
    case invalidCommand(String)
    case executionError(String)
    case conditionError(String)
    case invalidTemplate(String)

    public var errorDescription: String? {
        switch self {
        case .scriptNotFound(let path): return "Script not found: \(path)"
        case .parseError(let message, let line): return "Parse error at line \(line): \(message)"
        case .invalidVariable(let varStr): return "Invalid variable format: \(varStr). Use KEY=VALUE"
        case .invalidCommand(let cmd): return "Invalid command: \(cmd)"
        case .executionError(let message): return "Execution error: \(message)"
        case .conditionError(let message): return "Condition error: \(message)"
        case .invalidTemplate(let name): return "Invalid template name: \(name)"
        }
    }
}

// MARK: - Script Models

public enum ScriptCommand: Sendable {
    case toolCommand(ToolCommand)
    case conditional(ConditionalCommand)
    case pipeline(PipelineCommand)
    case setVariable(String, String)
}

public struct ToolCommand: Sendable {
    public let tool: String
    public let arguments: [String]
    public let inputVariable: String?
    public let outputVariable: String?
}

public struct ConditionalCommand: Sendable {
    public let condition: String
    public let thenCommands: [ScriptCommand]
    public let elseCommands: [ScriptCommand]?
}

public struct PipelineCommand: Sendable {
    public let commands: [ToolCommand]
}

struct ScriptContext {
    var variables: [String: String]
    var logger: ScriptLogger
    var dryRun: Bool
    var parallel: Bool
}

// MARK: - Script Parser

public struct ScriptParser {
    public init() {}

    public func parse(content: String) throws -> [ScriptCommand] {
        var commands: [ScriptCommand] = []
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if line.isEmpty || line.hasPrefix("#") {
                i += 1
                continue
            }

            if line.contains("=") && !line.hasPrefix("if ") {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let varName = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let varValue = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    commands.append(.setVariable(varName, varValue))
                    i += 1
                    continue
                }
            }

            if line.hasPrefix("if ") {
                let (conditional, linesConsumed) = try parseConditional(lines: Array(lines), startIndex: i)
                commands.append(.conditional(conditional))
                i += linesConsumed
                continue
            }

            if line.contains("|") {
                let pipeline = try parsePipeline(line: line)
                commands.append(.pipeline(pipeline))
                i += 1
                continue
            }

            let toolCmd = try parseToolCommand(line: line)
            commands.append(.toolCommand(toolCmd))
            i += 1
        }

        return commands
    }

    private func parseToolCommand(line: String) throws -> ToolCommand {
        let parts = Self.tokenize(line)
        guard !parts.isEmpty else {
            throw ScriptError.parseError("Empty command", 0)
        }

        let tool = parts[0]
        let arguments = Array(parts[1...])

        return ToolCommand(tool: tool, arguments: arguments, inputVariable: nil, outputVariable: nil)
    }

    private func parsePipeline(line: String) throws -> PipelineCommand {
        let commandStrings = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        var commands: [ToolCommand] = []
        for cmdStr in commandStrings {
            let cmd = try parseToolCommand(line: cmdStr)
            commands.append(cmd)
        }
        return PipelineCommand(commands: commands)
    }

    private func parseConditional(lines: [Substring], startIndex: Int) throws -> (ConditionalCommand, Int) {
        let line = String(lines[startIndex]).trimmingCharacters(in: .whitespaces)

        guard line.hasPrefix("if ") else {
            throw ScriptError.parseError("Invalid conditional", startIndex + 1)
        }

        let condition = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)

        var thenCommands: [ScriptCommand] = []
        var elseCommands: [ScriptCommand]? = nil
        var i = startIndex + 1
        var inElse = false

        while i < lines.count {
            let blockLine = String(lines[i]).trimmingCharacters(in: .whitespaces)

            if blockLine == "else" {
                inElse = true
                i += 1
                continue
            }

            if blockLine == "endif" || blockLine == "fi" {
                i += 1
                break
            }

            if blockLine.isEmpty || blockLine.hasPrefix("#") {
                i += 1
                continue
            }

            let cmd = try parseToolCommand(line: blockLine)
            if inElse {
                if elseCommands == nil { elseCommands = [] }
                elseCommands?.append(.toolCommand(cmd))
            } else {
                thenCommands.append(.toolCommand(cmd))
            }

            i += 1
        }

        let conditional = ConditionalCommand(condition: condition, thenCommands: thenCommands, elseCommands: elseCommands)
        return (conditional, i - startIndex)
    }
}

extension ScriptParser {
    /// Splits a command line on spaces and tabs; a "double-quoted" or 'single-quoted'
    /// run is one argument with its quotes removed (`--patient-name "DOE*"` passes DOE*).
    /// There is no shell: globs, redirection and backslash escapes are not interpreted.
    public static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inToken = false
        var quote: Character?
        for ch in line {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                inToken = true
            } else if ch == " " || ch == "\t" {
                if inToken { tokens.append(current); current = ""; inToken = false }
            } else {
                current.append(ch)
                inToken = true
            }
        }
        if inToken { tokens.append(current) }
        return tokens
    }

    /// Shell syntax the runner does not interpret, so a script must not rely on it: it
    /// execs each tool directly (no shell), passing `*.dcm` and `> file` through as
    /// literal arguments. Returns the offending words of a raw command line.
    public static func unsupportedShellSyntax(in line: String) -> [String] {
        var words: [String] = []
        var quote: Character?
        var current = ""
        func flush() {
            let word = current
            current = ""
            guard !word.isEmpty else { return }
            let redirection = word.hasPrefix(">") || word.hasPrefix("<") || word.hasPrefix("2>")
                || word.hasPrefix("&>") || word == "&&" || word == "||" || word == ";"
            let glob = (word.contains("*") || word.contains("?")) && !word.hasPrefix("-")
            if redirection || glob { words.append(word) }
        }
        for ch in line {
            if let q = quote {
                if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                current.append("q")  // a quoted run is a literal, never flagged
            } else if ch == " " || ch == "\t" {
                flush()
            } else {
                current.append(ch)
            }
        }
        flush()
        return words
    }
}

// MARK: - Script Executor

public struct ScriptExecutor {
    /// Runs a single tool with arguments and returns its combined output + exit
    /// code. The CLI supplies a `Process`-based runner; a sandboxed app supplies a
    /// no-op/dry-run runner (never invoked when `dryRun` is true).
    public typealias CommandRunner = (_ tool: String, _ arguments: [String]) throws -> (output: String, exitCode: Int32)

    private let runCommand: CommandRunner
    private let log: (String) -> Void

    public init(runCommand: @escaping CommandRunner, log: @escaping (String) -> Void = { _ in }) {
        self.runCommand = runCommand
        self.log = log
    }

    public func execute(
        scriptPath: String,
        variables: [String: String],
        parallel: Bool,
        verbose: Bool,
        dryRun: Bool,
        logPath: String?
    ) throws {
        let content = try String(contentsOfFile: scriptPath, encoding: .utf8)
        let parser = ScriptParser()
        let commands = try parser.parse(content: content)

        var logger = ScriptLogger(logPath: logPath, verbose: verbose, emit: log)
        logger.log("Starting script execution: \(scriptPath)")
        logger.log("Variables: \(variables)")

        var context = ScriptContext(variables: variables, logger: logger, dryRun: dryRun, parallel: parallel)

        for command in commands {
            try executeCommand(command, context: &context)
        }

        context.logger.log("Script execution completed successfully")

        if dryRun {
            log("Dry run completed - no commands were actually executed")
        } else {
            log("Script execution completed successfully")
        }
    }

    private func executeCommand(_ command: ScriptCommand, context: inout ScriptContext) throws {
        switch command {
        case .toolCommand(let toolCmd):
            try executeToolCommand(toolCmd, context: &context)
        case .conditional(let condCmd):
            try executeConditional(condCmd, context: &context)
        case .pipeline(let pipeCmd):
            try executePipeline(pipeCmd, context: &context)
        case .setVariable(let name, let value):
            let expandedValue = expandVariables(value, context: context)
            context.variables[name] = expandedValue
            context.logger.log("Set variable: \(name) = \(expandedValue)")
        }
    }

    private func executeToolCommand(_ command: ToolCommand, context: inout ScriptContext) throws {
        let expandedArgs = command.arguments.map { expandVariables($0, context: context) }
        let fullCommand = ([command.tool] + expandedArgs).joined(separator: " ")

        context.logger.log("Executing: \(fullCommand)")

        if context.dryRun {
            context.logger.log("[DRY RUN] Would execute: \(fullCommand)")
            return
        }

        // Run via the injected command runner (no Process in the library itself).
        let result = try runCommand(command.tool, expandedArgs)
        if !result.output.isEmpty {
            context.logger.log("Output: \(result.output)")
        }
        if result.exitCode != 0 {
            throw ScriptError.executionError("Command failed with status \(result.exitCode): \(fullCommand)")
        }
    }

    private func executeConditional(_ command: ConditionalCommand, context: inout ScriptContext) throws {
        let conditionResult = try evaluateCondition(command.condition, context: context)
        context.logger.log("Condition '\(command.condition)' evaluated to: \(conditionResult)")

        if conditionResult {
            for cmd in command.thenCommands {
                try executeCommand(cmd, context: &context)
            }
        } else if let elseCommands = command.elseCommands {
            for cmd in elseCommands {
                try executeCommand(cmd, context: &context)
            }
        }
    }

    private func executePipeline(_ command: PipelineCommand, context: inout ScriptContext) throws {
        context.logger.log("Executing pipeline with \(command.commands.count) commands")

        // --parallel: a pipeline's tool commands are independent by construction
        // (no variable writes can occur between them), so run them concurrently
        // and REPLAY their log lines in source order — output stays byte-stable
        // versus a sequential run. Dry runs stay sequential (nothing to overlap).
        // The injected CommandRunner must be safe to call from multiple threads
        // (the CLI's Process-based runner is; each invocation is independent).
        if context.parallel && !context.dryRun && command.commands.count > 1 {
            final class CommandRunnerBox: @unchecked Sendable {
                let run: CommandRunner

                init(_ run: @escaping CommandRunner) {
                    self.run = run
                }
            }

            final class PipelineResultsBox: @unchecked Sendable {
                private var entries: [(lines: [String], error: Error?)]
                private let lock = NSLock()

                init(count: Int) {
                    entries = Array(repeating: ([], nil), count: count)
                }

                func set(index: Int, lines: [String], error: Error?) {
                    lock.lock()
                    entries[index] = (lines, error)
                    lock.unlock()
                }

                var snapshot: [(lines: [String], error: Error?)] {
                    lock.lock()
                    defer { lock.unlock() }
                    return entries
                }
            }

            let commands = command.commands
            let snapshotVariables = context.variables
            let runnerBox = CommandRunnerBox(self.runCommand)
            let resultsBox = PipelineResultsBox(count: commands.count)

            DispatchQueue.concurrentPerform(iterations: commands.count) { index in
                let toolCmd = commands[index]
                let expandedArgs = toolCmd.arguments.map { Self.expandVariables($0, variables: snapshotVariables) }
                let fullCommand = ([toolCmd.tool] + expandedArgs).joined(separator: " ")
                var lines = ["Executing: \(fullCommand)"]
                var failure: Error? = nil
                do {
                    let result = try runnerBox.run(toolCmd.tool, expandedArgs)
                    if !result.output.isEmpty { lines.append("Output: \(result.output)") }
                    if result.exitCode != 0 {
                        failure = ScriptError.executionError(
                            "Command failed with status \(result.exitCode): \(fullCommand)")
                    }
                } catch {
                    failure = error
                }
                resultsBox.set(index: index, lines: lines, error: failure)
            }
            let results = resultsBox.snapshot
            for entry in results {
                for line in entry.lines { context.logger.log(line) }
            }
            if let firstError = results.compactMap(\.error).first {
                throw firstError
            }
            return
        }

        for toolCmd in command.commands {
            try executeToolCommand(toolCmd, context: &context)
        }
    }

    private func evaluateCondition(_ condition: String, context: ScriptContext) throws -> Bool {
        let expanded = expandVariables(condition, context: context)

        let parts = expanded.split(separator: " ", omittingEmptySubsequences: true)
        guard !parts.isEmpty else {
            throw ScriptError.conditionError("Empty condition")
        }

        let operatorName = String(parts[0])

        switch operatorName {
        case "exists":
            guard parts.count == 2 else {
                throw ScriptError.conditionError("'exists' requires a path argument")
            }
            return FileManager.default.fileExists(atPath: String(parts[1]))

        case "empty":
            guard parts.count == 2 else {
                throw ScriptError.conditionError("'empty' requires a variable name")
            }
            let varValue = context.variables[String(parts[1])] ?? ""
            return varValue.isEmpty

        case "equals":
            guard parts.count == 3 else {
                throw ScriptError.conditionError("'equals' requires two arguments")
            }
            return String(parts[1]) == String(parts[2])

        default:
            throw ScriptError.conditionError("Unknown operator: \(operatorName)")
        }
    }

    private func expandVariables(_ string: String, context: ScriptContext) -> String {
        Self.expandVariables(string, variables: context.variables)
    }

    private static func expandVariables(_ string: String, variables: [String: String]) -> String {
        var result = string
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "${\(key)}", with: value)
            result = result.replacingOccurrences(of: "$\(key)", with: value)
        }
        return result
    }
}

// MARK: - Script Validator

public struct ScriptValidator {
    private let log: (String) -> Void

    public init(log: @escaping (String) -> Void = { _ in }) {
        self.log = log
    }

    public func validate(scriptPath: String, verbose: Bool) throws -> [String] {
        let content = try String(contentsOfFile: scriptPath, encoding: .utf8)
        let parser = ScriptParser()

        var issues: [String] = []

        do {
            let commands = try parser.parse(content: content)

            // No shell runs the tools (D223): flag globs and redirection, which would reach
            // the tool as literal arguments.
            for (number, rawLine) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("if "),
                      !(line.contains("=") && !line.contains(" ")) else { continue }
                let words = ScriptParser.unsupportedShellSyntax(in: line)
                if !words.isEmpty {
                    issues.append("Line \(number + 1): \(words.joined(separator: " ")) is passed to the tool literally: "
                        + "scripts run tools without a shell, so globs and redirection are not expanded "
                        + "(pass a directory with --recursive; tool output goes to the log)")
                }
            }

            for (index, command) in commands.enumerated() {
                let commandIssues = validateCommand(command, index: index)
                issues.append(contentsOf: commandIssues)
            }

            if verbose && issues.isEmpty {
                log("Parsed \(commands.count) commands successfully")
            }

        } catch let error as ScriptError {
            issues.append(error.localizedDescription)
        } catch {
            issues.append("Unknown error: \(error.localizedDescription)")
        }

        return issues
    }

    private func validateCommand(_ command: ScriptCommand, index: Int) -> [String] {
        var issues: [String] = []

        switch command {
        case .toolCommand(let toolCmd):
            let knownTools = [
                "dicom-info", "dicom-convert", "dicom-validate", "dicom-anon",
                "dicom-dump", "dicom-query", "dicom-send", "dicom-diff",
                "dicom-retrieve", "dicom-split", "dicom-merge", "dicom-json",
                "dicom-xml", "dicom-pdf", "dicom-image", "dicom-dcmdir",
                "dicom-archive", "dicom-export", "dicom-qr", "dicom-wado",
                "dicom-echo", "dicom-mwl", "dicom-mpps", "dicom-pixedit",
                "dicom-tags", "dicom-uid", "dicom-compress", "dicom-study"
            ]

            if !knownTools.contains(toolCmd.tool) {
                issues.append("Command \(index + 1): Unknown DICOM tool '\(toolCmd.tool)'")
            }

        case .conditional(let condCmd):
            if condCmd.condition.isEmpty {
                issues.append("Command \(index + 1): Empty condition")
            }

            for (subIndex, subCmd) in condCmd.thenCommands.enumerated() {
                let subIssues = validateCommand(subCmd, index: subIndex)
                issues.append(contentsOf: subIssues.map { "Command \(index + 1) (then): \($0)" })
            }

            if let elseCommands = condCmd.elseCommands {
                for (subIndex, subCmd) in elseCommands.enumerated() {
                    let subIssues = validateCommand(subCmd, index: subIndex)
                    issues.append(contentsOf: subIssues.map { "Command \(index + 1) (else): \($0)" })
                }
            }

        case .pipeline(let pipeCmd):
            if pipeCmd.commands.isEmpty {
                issues.append("Command \(index + 1): Empty pipeline")
            }

        case .setVariable(let name, let value):
            if name.isEmpty {
                issues.append("Command \(index + 1): Empty variable name")
            }
            if value.isEmpty {
                issues.append("Command \(index + 1): Empty variable value for '\(name)'")
            }
        }

        return issues
    }
}

// MARK: - Template Generator

public struct TemplateGenerator {
    public init() {}

    public func generate(templateName: String) throws -> String {
        switch templateName.lowercased() {
        case "workflow": return workflowTemplate
        case "pipeline": return pipelineTemplate
        case "query": return queryTemplate
        case "archive": return archiveTemplate
        case "anonymize": return anonymizeTemplate
        default: throw ScriptError.invalidTemplate(templateName)
        }
    }

    private var workflowTemplate: String {
        """
        # DICOM Workflow Script
        # Generated by dicom-script v1.3.5

        # Define variables
        INPUT_DIR=/path/to/input
        OUTPUT_DIR=/path/to/output

        # Tools run without a shell: pass a directory with --recursive (no *.dcm globs),
        # and tool output goes to the script log (no > redirection).

        # Validate input files
        dicom-validate ${INPUT_DIR} --recursive --level 2

        # Process files
        dicom-convert ${INPUT_DIR} --output ${OUTPUT_DIR} --format png --recursive

        # Summarize the study (printed as JSON)
        dicom-study summary ${INPUT_DIR} --format json
        """
    }

    private var pipelineTemplate: String {
        """
        # DICOM Pipeline Script
        # Generated by dicom-script v1.3.5

        # Pipeline: query -> retrieve -> validate -> anonymize -> archive

        PACS_HOST=pacs.example.com
        PACS_PORT=11112
        PACS_AET=PACS
        LOCAL_AET=WORKSTATION
        PATIENT_ID=12345
        # Set to a Study Instance UID (0020,000D) returned by the query
        STUDY_UID=1.2.3.4.5.6.7.8.9

        # Query PACS (host is the positional argument; --aet is the calling AE Title)
        # (one command per line: the script language splits on newlines and does
        # not support backslash line-continuations)
        dicom-query ${PACS_HOST} --port ${PACS_PORT} --called-aet ${PACS_AET} --aet ${LOCAL_AET} --patient-id ${PATIENT_ID} --level study

        # Retrieve the study (C-GET; Query/Retrieve Level STUDY, PS3.4 C.4.3)
        dicom-retrieve ${PACS_HOST} --port ${PACS_PORT} --called-aet ${PACS_AET} --aet ${LOCAL_AET} --study-uid ${STUDY_UID} --method c-get --output studies/

        # Validate retrieved files (a directory with --recursive: no shell expands *.dcm)
        dicom-validate studies/ --recursive --level 2

        # Anonymize (PS3.15 Basic Application Level Confidentiality Profile)
        dicom-anon studies/ --profile ps315 --output anon/ --recursive

        # Archive
        dicom-archive init --path archive
        dicom-archive import anon/ --archive archive --recursive
        """
    }

    private var queryTemplate: String {
        """
        # DICOM Query Script
        # Generated by dicom-script v1.3.5

        PACS_HOST=pacs.example.com
        PACS_PORT=11112
        PACS_AET=PACS
        LOCAL_AET=WORKSTATION

        # Query by patient name (host is the positional argument; --aet is the calling AE Title)
        # (one command per line: the script language splits on newlines and does
        # not support backslash line-continuations)
        dicom-query ${PACS_HOST} --port ${PACS_PORT} --called-aet ${PACS_AET} --aet ${LOCAL_AET} --patient-name "DOE*" --level patient

        # Query by date range: one Study Date range value (PS3.4 C.2.2.2.5)
        dicom-query ${PACS_HOST} --port ${PACS_PORT} --called-aet ${PACS_AET} --aet ${LOCAL_AET} --study-date 20240101-20241231 --level study
        """
    }

    private var archiveTemplate: String {
        """
        # DICOM Archive Script
        # Generated by dicom-script v1.3.5

        ARCHIVE=/path/to/archive
        INPUT_DIR=/path/to/dicoms

        # Create the archive and import files into it
        dicom-archive init --path ${ARCHIVE}
        dicom-archive import ${INPUT_DIR} --archive ${ARCHIVE} --recursive

        # Query archive
        dicom-archive query --archive ${ARCHIVE} --patient-id "12345"

        # Export from archive
        dicom-archive export --archive ${ARCHIVE} --patient-id "12345" --output exported/
        """
    }

    private var anonymizeTemplate: String {
        """
        # DICOM Anonymization Script
        # Generated by dicom-script v1.3.5

        INPUT_DIR=/path/to/input
        OUTPUT_DIR=/path/to/anonymized

        # Anonymize with the PS3.15 Basic Application Level Confidentiality Profile
        # (a directory with --recursive: tools run without a shell, so *.dcm is not expanded)
        dicom-anon ${INPUT_DIR} --profile ps315 --output ${OUTPUT_DIR} --recursive

        # Conditional anonymization: also blank burned-in text (PS3.15 Clean Pixel Data Option)
        if exists ${INPUT_DIR}/sensitive.dcm
            dicom-anon ${INPUT_DIR}/sensitive.dcm --profile ps315 --clean-pixel-data --output ${OUTPUT_DIR}
        endif

        # Validate anonymized files
        dicom-validate ${OUTPUT_DIR} --recursive --level 2
        """
    }
}

// MARK: - Script Logger

struct ScriptLogger {
    let logPath: String?
    let verbose: Bool
    let emit: (String) -> Void
    private let dateFormatter: DateFormatter

    init(logPath: String?, verbose: Bool, emit: @escaping (String) -> Void) {
        self.logPath = logPath
        self.verbose = verbose
        self.emit = emit
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    mutating func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"

        if verbose {
            emit(logMessage)
        }

        if let logPath = logPath {
            do {
                let fileHandle: FileHandle
                if FileManager.default.fileExists(atPath: logPath) {
                    fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
                    try fileHandle.seekToEnd()
                } else {
                    _ = FileManager.default.createFile(atPath: logPath, contents: nil)
                    fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
                }

                if let data = (logMessage + "\n").data(using: .utf8) {
                    fileHandle.write(data)
                }
                try fileHandle.close()
            } catch {
                emit("Warning: Failed to write to log file: \(error.localizedDescription)")
            }
        }
    }
}
