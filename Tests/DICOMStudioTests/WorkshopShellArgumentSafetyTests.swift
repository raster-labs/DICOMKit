// M1 WS-FIX-01/02: exercise the real shell, CLI parser and shared MWL key builder.
// No DICOM peer is contacted and no CLI command is run by these tests.

import Foundation
import Testing
import ArgumentParser
import DICOMCore
@testable import DICOMNetwork
@testable import DICOMStudio
@testable import dicom_mwl

#if os(macOS) || os(Linux)
@Suite("Workshop shell argument safety")
struct WorkshopShellArgumentSafetyTests {
    private var shells: [String] {
        ["/bin/sh", "/bin/zsh"].filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Capture NUL-delimited argv using only a shell builtin. Prefixing the
    /// preview with capture means the displayed CLI executable never runs.
    private func capture(_ command: String, shell: String) throws -> [String] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("workshop-shell-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Make wildcard expansion observable in sh as well as zsh: an empty
        // directory would let an unquoted glob appear unchanged under sh.
        try Data().write(to: directory.appendingPathComponent("DOE_MATCH"))
        try Data().write(to: directory.appendingPathComponent("DOE1"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.currentDirectoryURL = directory
        let script = "capture() { printf '%s\\0' \"$@\"; }\ncapture " + command
        process.arguments = shell.hasSuffix("/zsh") ? ["-f", "-c", script] : ["-c", script]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let diagnostic = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(shell): \(diagnostic)")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("sentinel").path),
                "A value executed an additional shell command")
        #expect(data.last == 0, "argv capture must end with a NUL delimiter")
        return data.split(separator: 0, omittingEmptySubsequences: false).dropLast()
            .map { String(decoding: $0, as: UTF8.self) }
    }

    @Test("Literal shell arguments survive sh and zsh without expansion or execution")
    func literalArgumentsRoundTrip() throws {
        let values = [
            "", "plain", "DOE*", "DOE?", "ImageType=ORIGINAL\\PRIMARY",
            "=ls", "=printf", "=workshop_nonexistent_command",
            "two words", "Patient's Name", "a\"quote", "tab\tvalue", "line\nbreak",
            "a;b", "$HOME", "${HOME}", "(parentheses)", "{brace,expansion}",
            "https://example.invalid/q?name=DOE*&limit=2", "#comment", "~user", "é^患者",
            ";touch${IFS}sentinel", "$(touch${IFS}sentinel)", "`touch${IFS}sentinel`",
        ]
        #expect(!shells.isEmpty)
        for shell in shells {
            let command = values.map(CommandBuilderHelpers.shellEscape).joined(separator: " ")
            #expect(try capture(command, shell: shell) == values)
        }
    }

    @Test("Built previews retain scalar, repeated and positional DICOM values")
    func commandValuesRoundTrip() throws {
        let definitions = [
            CLIParameterDefinition(id: "input", flag: "", displayName: "Input", parameterType: .filePath),
            CLIParameterDefinition(id: "patient", flag: "--patient", displayName: "Patient", parameterType: .textField),
            CLIParameterDefinition(id: "set", flag: "--set", displayName: "Set", parameterType: .textField,
                                   isRepeatable: true),
            CLIParameterDefinition(id: "note", flag: "--note", displayName: "Note", parameterType: .textField),
            CLIParameterDefinition(id: "output", flag: "--output", displayName: "Output", parameterType: .outputPath),
        ]
        let values = [
            CLIParameterValue(parameterID: "input", stringValue: "folder's scan?.dcm"),
            CLIParameterValue(parameterID: "patient", stringValue: "DOE*"),
            CLIParameterValue(parameterID: "set", stringValue: "ImageType=ORIGINAL\\PRIMARY; PatientName=DOE^JANE"),
            CLIParameterValue(parameterID: "note", stringValue: "line\nbreak;$HOME"),
            CLIParameterValue(parameterID: "output", stringValue: "-output file.dcm"),
        ]
        let preview = CommandBuilderHelpers.buildCommand(toolName: "dicom-probe",
            parameterValues: values, parameterDefinitions: definitions)
        let expected = ["dicom-probe", "folder's scan?.dcm", "--patient", "DOE*",
                        "--set", "ImageType=ORIGINAL\\PRIMARY", "--set", "PatientName=DOE^JANE",
                        "--note", "line\nbreak;$HOME", "--output=-output file.dcm"]
        for shell in shells {
            #expect(try capture(preview, shell: shell) == expected)
        }
    }

    @Test("Every repeated leading-hyphen option value is bound to its flag")
    func repeatedLeadingHyphenValues() throws {
        let definitions = [CLIParameterDefinition(id: "value", flag: "--value", displayName: "Value",
                                                  parameterType: .textField, isRepeatable: true)]
        let values = [CLIParameterValue(parameterID: "value", stringValue: "-first; normal; -third value")]
        let preview = CommandBuilderHelpers.buildCommand(toolName: "dicom-probe",
            parameterValues: values, parameterDefinitions: definitions)
        for shell in shells {
            #expect(try capture(preview, shell: shell)
                    == ["dicom-probe", "--value=-first", "--value", "normal", "--value=-third value"])
        }
    }

    private struct ShortOutputProbe: ParsableArguments {
        @Option(name: .shortAndLong)
        var output: String
    }

    @Test("A short option binds a leading-hyphen value without adding an equals sign")
    func shortOptionLeadingHyphenValue() throws {
        let definitions = [CLIParameterDefinition(id: "output", flag: "-o", displayName: "Output",
                                                  parameterType: .outputPath)]
        for value in ["-output", "-output file.dcm", "--output=literal", "-"] {
            let preview = CommandBuilderHelpers.buildCommand(toolName: "dicom-probe",
                parameterValues: [CLIParameterValue(parameterID: "output", stringValue: value)],
                parameterDefinitions: definitions)
            for shell in shells {
                let arguments = try capture(preview, shell: shell)
                #expect(arguments == ["dicom-probe", "-o=\(value)"])
                let parsed = try ShortOutputProbe.parse(Array(arguments.dropFirst()))
                #expect(parsed.output == value)
            }
        }
    }

    @Test("Trusted catalog prefixes retain separate executable and subcommand tokens")
    func catalogCommandPrefixes() throws {
        let prefixes = ["dicom-wado query", "dicom-wado retrieve", "dicom-wado store", "dicom-wado ups"]
        for prefix in prefixes {
            #expect(ToolCatalogHelpers.allTools().contains { $0.name == prefix })
            let preview = CommandBuilderHelpers.buildCommand(toolName: prefix,
                parameterValues: [], parameterDefinitions: [])
            for shell in shells {
                #expect(try capture(preview, shell: shell) == prefix.split(separator: " ").map(String.init))
            }
        }
        // A caller-supplied executable path containing spaces must not acquire
        // an invented subcommand merely because catalog names can have one.
        for name in ["/path with spaces/dicom-probe", "probe;touch${IFS}sentinel"] {
            let preview = CommandBuilderHelpers.buildCommand(toolName: name,
                parameterValues: [], parameterDefinitions: [])
            for shell in shells {
                #expect(try capture(preview, shell: shell) == [name])
            }
        }
    }

    private func mwlPreview(date: String, time: String) -> String {
        let values = [
            CLIParameterValue(parameterID: "operation", stringValue: "query"),
            CLIParameterValue(parameterID: "host", stringValue: "127.0.0.1"),
            CLIParameterValue(parameterID: "aet", stringValue: "M1_TEST"),
            CLIParameterValue(parameterID: "date-from", stringValue: date),
            CLIParameterValue(parameterID: "time-from", stringValue: time),
            CLIParameterValue(parameterID: "patient", stringValue: "DOE*"),
        ]
        return CommandBuilderHelpers.buildCommand(toolName: "dicom-mwl", parameterValues: values,
            parameterDefinitions: ToolCatalogHelpers.parameterDefinitions(for: "dicom-mwl"))
    }

    private func parseMWL(_ arguments: [String]) throws -> DICOMMWLCommand.Query {
        let parsed = try DICOMMWLCommand.parseAsRoot(Array(arguments.dropFirst()))
        return try #require(parsed as? DICOMMWLCommand.Query)
    }

    @Test("Real MWL parser receives open-ended, bounded and single DA/TM values unchanged")
    func worklistRangesReachParserAndKeys() throws {
        let cases = [("-20261024", "-180000"), ("20261001-20261024", "1000-1800"),
                     ("20261001-", "1000-"), ("20261024", "101530.123456")]
        for (date, time) in cases {
            let preview = mwlPreview(date: date, time: time)
            for shell in shells {
                let parsed = try parseMWL(capture(preview, shell: shell))
                #expect(parsed.date == date)
                #expect(parsed.time == time)
                #expect(parsed.patient == "DOE*")
                #expect(parsed.aet == "M1_TEST")
                let cliKeys = try WorklistQueryKeys.forQuery(date: parsed.date ?? "", time: parsed.time ?? "")
                let appKeys = try WorklistQueryKeys.forQuery(date: date, time: time)
                #expect(cliKeys.allSPSKeys == appKeys.allSPSKeys)
                #expect(cliKeys.allSPSKeys[Tag(group: 0x0040, element: 0x0002)] == date)
                #expect(cliKeys.allSPSKeys[Tag(group: 0x0040, element: 0x0003)] == time)
            }
        }
    }

    @Test("Shell quoting alone cannot make a leading-hyphen range an MWL option value")
    func separatedRangeRemainsAParserError() {
        #expect(throws: (any Error).self) {
            try DICOMMWLCommand.Query.parse(["127.0.0.1", "--aet", "M1_TEST", "--date", "-20261024"])
        }
        #expect(throws: (any Error).self) {
            try DICOMMWLCommand.Query.parse(["127.0.0.1", "--aet", "M1_TEST", "--time", "-180000"])
        }
    }

    private func invalidRangeMessage(date: String, time: String) -> String? {
        do {
            _ = try WorklistQueryKeys.forQuery(date: date, time: time)
            return nil
        } catch {
            return String(describing: error)
        }
    }

    @Test("Malformed ranges survive parsing then fail identically in the shared validator")
    func malformedRangesFailCommonValidation() throws {
        let cases = [("-", "1000"), ("20261001--20261024", "1000"),
                     ("20261024", "-"), ("20261024", "1000-1800-2000")]
        for (date, time) in cases {
            let expected = try #require(invalidRangeMessage(date: date, time: time))
            for shell in shells {
                let parsed = try parseMWL(capture(mwlPreview(date: date, time: time), shell: shell))
                #expect(parsed.date == date)
                #expect(parsed.time == time)
                #expect(invalidRangeMessage(date: parsed.date ?? "", time: parsed.time ?? "") == expected)
            }
        }
    }
}
#endif
