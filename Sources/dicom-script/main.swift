// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (runs, validates and prints templates of the shell-like script language in DICOMKit/Scripting; scripts name dicom-* tools and their options, not DICOM keywords, tags or UIDs)
import Foundation
import ArgumentParser
import DICOMKit

// The script engine (parser/executor/validator/template generator) now lives in
// the DICOMKit library (Sources/DICOMKit/Scripting/). The executor calls an
// injected command runner; this CLI supplies the real `Process`-based runner.
private func processCommandRunner(_ tool: String, _ arguments: [String]) throws -> (output: String, exitCode: Int32) {
    #if os(macOS) || os(Linux)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [tool] + arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
    #else
    throw ScriptError.executionError(ScriptConsole.unsupportedRunnerMessage(tool: tool))
    #endif
}

@available(macOS 10.15, *)
struct DICOMScript: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-script",
        abstract: "Execute DICOM workflow scripts and pipelines",
        discussion: """
            Execute workflow scripts written in the DICOM Script Language (DSL).
            Supports pipeline operations, conditional logic, variable substitution,
            parallel execution, and error handling.
            
            Examples:
              dicom-script run workflow.dcmscript
              dicom-script run pipeline.dcmscript --var PATIENT_ID=12345
              dicom-script validate workflow.dcmscript
              dicom-script template workflow > workflow.dcmscript
            """,
        version: "1.3.5",
        subcommands: [Run.self, Validate.self, Template.self]
    )
}

// MARK: - Run Command

@available(macOS 10.15, *)
extension DICOMScript {
    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Execute a DICOM workflow script"
        )
        
        @Argument(help: "Script file path")
        var scriptPath: String
        
        @Option(name: .long, parsing: .upToNextOption, help: "Variables in KEY=VALUE format")
        var variables: [String] = []
        
        @Flag(name: .long, help: "Enable parallel execution where possible")
        var parallel: Bool = false
        
        @Flag(name: .shortAndLong, help: "Show verbose output")
        var verbose: Bool = false
        
        @Flag(name: .long, help: "Dry run - show what would be executed")
        var dryRun: Bool = false
        
        @Option(name: .long, help: "Log file path")
        var log: String?
        
        mutating func run() throws {
            guard FileManager.default.fileExists(atPath: scriptPath) else {
                throw ScriptError.scriptNotFound(scriptPath)
            }
            
            // Shared KEY=VALUE parser (one copy of the grammar + its error text).
            let parsedVariables = try ScriptConsole.parseVariables(variables)
            
            // Route the shared engine's output to STDOUT so the CLI and DICOMStudio
            // (which renders it in-console) are text-exact.
            let executor = ScriptExecutor(runCommand: processCommandRunner, log: { print($0) })
            try executor.execute(
                scriptPath: scriptPath,
                variables: parsedVariables,
                parallel: parallel,
                verbose: verbose,
                dryRun: dryRun,
                logPath: log
            )
        }
    }
}

// MARK: - Validate Command

@available(macOS 10.15, *)
extension DICOMScript {
    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Validate a DICOM workflow script"
        )
        
        @Argument(help: "Script file path")
        var scriptPath: String
        
        @Flag(name: .shortAndLong, help: "Show verbose validation output")
        var verbose: Bool = false
        
        mutating func run() throws {
            guard FileManager.default.fileExists(atPath: scriptPath) else {
                throw ScriptError.scriptNotFound(scriptPath)
            }
            
            let validator = ScriptValidator(log: { print($0) })
            let issues = try validator.validate(scriptPath: scriptPath, verbose: verbose)

            // Verdict block via the shared ScriptConsole — same lines in-app.
            for line in ScriptConsole.validationLines(issues: issues) { print(line) }
            if !issues.isEmpty { throw ExitCode.failure }
        }
    }
}

// MARK: - Template Command

@available(macOS 10.15, *)
extension DICOMScript {
    struct Template: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate workflow script templates"
        )
        
        @Argument(help: "Template name: 'workflow', 'pipeline', 'query', 'archive', 'anonymize'")
        var templateName: String
        
        mutating func run() throws {
            let generator = TemplateGenerator()
            let template = try generator.generate(templateName: templateName)
            print(template)
        }
    }
}

private func fprintln(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
}

DICOMScript.main()
