// CLIShellCatalogueTests.swift
// DICOMStudioTests
//
// DICOM Studio — pins for the CLI shell catalogue, browser citations, parameter builder CLI surface and PHI
// redaction keywords verified against DICOM 2026a and the dicom-* ArgumentParser surfaces (2026-10-05).

import Testing
@testable import DICOMStudio
import Foundation

@Suite("CLI Shell Catalogue Tests")
struct CLIShellCatalogueTests {

    /// The `dicom-*` executable targets of the package (one directory per tool under Sources/).
    private static var shippedTools: Set<String> {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: sources.path)) ?? []
        return Set(names.filter { $0.hasPrefix("dicom-") })
    }

    // MARK: - Tool registry (CLIShellFoundation)

    @Test("ToolRegistryHelpers.allToolNames is exactly the set of Sources/dicom-* targets, each once")
    func test_allToolNames_matchesShippedTools() {
        let shipped = Self.shippedTools
        #expect(shipped.count == 42)
        #expect(Set(ToolRegistryHelpers.allToolNames) == shipped)
        #expect(ToolRegistryHelpers.allToolNames.count == shipped.count)
        #expect(ToolRegistryHelpers.totalToolCount == shipped.count)
    }

    @Test("ToolCategory.toolNames partition the shipped tools (no tool twice, none missing)")
    func test_toolCategory_partitionsShippedTools() {
        let all = ToolCategory.allCases.flatMap(\.toolNames)
        #expect(all.count == Set(all).count)
        #expect(Set(all) == Self.shippedTools)
    }

    @Test("The four previously unlisted tools are catalogued with display names")
    func test_newTools_catalogued() {
        #expect(ToolRegistryHelpers.toolCategory(for: "dicom-j2k") == .fileProcessing)
        #expect(ToolRegistryHelpers.toolCategory(for: "dicom-jpip") == .networking)
        #expect(ToolRegistryHelpers.toolCategory(for: "dicom-printscp") == .networking)
        #expect(ToolRegistryHelpers.toolCategory(for: "dicom-video") == .dataExchange)
        #expect(ToolRegistryHelpers.toolDisplayName(for: "dicom-j2k") == "J2K")
        #expect(ToolRegistryHelpers.toolDisplayName(for: "dicom-jpip") == "JPIP")
        #expect(ToolRegistryHelpers.toolDisplayName(for: "dicom-printscp") == "Print SCP")
    }

    @Test("Tool descriptions say what the tools do (dicom-tags edits tags; dicom-image converts images to Secondary Capture)")
    func test_toolDescriptions_corrected() {
        #expect(ToolRegistryHelpers.toolDescription(for: "dicom-tags") == "Add, modify, and delete tags in DICOM files")
        #expect(ToolRegistryHelpers.toolDescription(for: "dicom-image").contains("Secondary Capture"))
        #expect(ToolRegistryHelpers.toolDescription(for: "dicom-wado").contains("QIDO-RS"))
        for tool in Self.shippedTools {
            #expect(ToolRegistryHelpers.toolDescription(for: tool) != "DICOM command-line tool", "\(tool) has no description")
        }
    }

    // MARK: - Integration scenarios

    @Test("IntegrationTestToolCategory.toolNames are the shipped tools, each once (dicom-qido/stow/ups are dicom-wado subcommands)")
    func test_integrationToolNames_matchShippedTools() {
        let all = IntegrationTestToolCategory.allCases.flatMap(\.toolNames)
        #expect(all.count == Set(all).count)
        #expect(Set(all) == Self.shippedTools)
        #expect(!all.contains("dicom-qido"))
        #expect(!all.contains("dicom-stow"))
        #expect(!all.contains("dicom-ups"))
    }

    // MARK: - Browser navigation standard references

    @Test("dicom-wado header cites PS3.18 §10 (Studies Service); PS3.18 2026a has no §6.5")
    func test_browser_wadoReference() {
        #expect(ContentLayoutHelpers.toolHeaderInfo(for: "dicom-wado").dicomStandardRef == "PS3.18 §10")
        #expect(ContentLayoutHelpers.toolHeaderInfo(for: "dicom-echo").dicomStandardRef == "PS3.7 §9.1.5")
    }

    // MARK: - Parameter builder vs the CLI surface

    @Test("DIMSE tools take the host as a positional <host> argument and --aet, not --host / --calling-aet")
    func test_networkTools_useRealOptionNames() {
        for tool in ["dicom-echo", "dicom-query", "dicom-send", "dicom-retrieve"] {
            let names = ParameterCatalogHelpers.config(for: tool)!.parameters.map(\.name)
            #expect(names.contains("<host>"), "\(tool)")
            #expect(names.contains("--aet"), "\(tool)")
            #expect(names.contains("--called-aet"), "\(tool)")
            #expect(!names.contains("--host"), "\(tool)")
            #expect(!names.contains("--calling-aet"), "\(tool)")
            let port = ParameterCatalogHelpers.config(for: tool)!.parameters.first { $0.name == "--port" }
            #expect(port?.defaultValue == .int(11112), "\(tool): PS3.8 2026a 9.1.1 registered DICOM port")
            let called = ParameterCatalogHelpers.config(for: tool)!.parameters.first { $0.name == "--called-aet" }
            #expect(called?.defaultValue == .string("ANY-SCP"), "\(tool)")
        }
    }

    @Test("dicom-query --level offers the PS3.4 Query/Retrieve Level values patient, study, series, image")
    func test_queryLevel_values() {
        let level = ParameterCatalogHelpers.config(for: "dicom-query")!.parameters.first { $0.name == "--level" }!
        guard case .picker(let options) = level.type else { Issue.record("--level is not a picker"); return }
        #expect(options.map(\.cliValue) == ["patient", "study", "series", "image"])
        #expect(level.defaultValue == .string("study"))
    }

    @Test("dicom-anon --profile defaults to ps315 (PS3.15 Basic Profile) and offers no standard/full")
    func test_anonProfile_values() {
        let profile = ParameterCatalogHelpers.config(for: "dicom-anon")!.parameters.first { $0.name == "--profile" }!
        guard case .radio(let options) = profile.type else { Issue.record("--profile is not a radio"); return }
        #expect(options.first?.cliValue == "ps315")
        #expect(!options.map(\.cliValue).contains("standard"))
        #expect(!options.map(\.cliValue).contains("full"))
        #expect(profile.defaultValue == .string("ps315"))
    }

    @Test("dicom-retrieve --method offers c-move and c-get, default c-move")
    func test_retrieveMethod_values() {
        let method = ParameterCatalogHelpers.config(for: "dicom-retrieve")!.parameters.first { $0.name == "--method" }!
        guard case .picker(let options) = method.type else { Issue.record("--method is not a picker"); return }
        #expect(options.map(\.cliValue) == ["c-move", "c-get"])
        #expect(method.defaultValue == .string("c-move"))
    }

    @Test("File tools take their input as a positional argument; dicom-json uses --pretty; dicom-image converts images")
    func test_fileTools_positionalInput() {
        #expect(ParameterCatalogHelpers.config(for: "dicom-info")!.parameters.first?.name == "<file-path>")
        #expect(ParameterCatalogHelpers.config(for: "dicom-diff")!.parameters.map(\.name).prefix(2) == ["<file1>", "<file2>"])
        #expect(ParameterCatalogHelpers.config(for: "dicom-json")!.parameters.map(\.name).contains("--pretty"))
        #expect(!ParameterCatalogHelpers.config(for: "dicom-json")!.parameters.map(\.name).contains("--pretty-print"))
        #expect(!ParameterCatalogHelpers.config(for: "dicom-image")!.parameters.map(\.name).contains("--format"))
        #expect(!ParameterCatalogHelpers.config(for: "dicom-info")!.parameters.map(\.name).contains("--verbose"))
    }

    @Test("generateCommand emits a <positional> argument as its bare value")
    func test_generateCommand_positional() {
        let host = ToolParameterDefinition(name: "<host>", displayName: "Host", description: "", type: .host, isRequired: true)
        let port = ToolParameterDefinition(name: "--port", displayName: "Port", description: "", type: .port, isRequired: false)
        let entries = [
            ParameterFormEntry(definition: host, currentValue: .string("pacs.local")),
            ParameterFormEntry(definition: port, currentValue: .int(11112)),
        ]
        #expect(FormRenderingHelpers.isPositional("<host>"))
        #expect(!FormRenderingHelpers.isPositional("--host"))
        #expect(FormRenderingHelpers.generateCommand(toolName: "dicom-echo", subcommand: nil, entries: entries) == "dicom-echo pacs.local --port 11112")
    }

    @Test("Service generates a runnable dicom-echo command from the catalogue defaults")
    func test_service_echoCommand_isRunnable() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-echo")
        service.updateValue(.string("pacs.local"), for: "<host>")
        let cmd = service.getFormState().generatedCommand
        #expect(cmd.hasPrefix("dicom-echo pacs.local"))
        #expect(cmd.contains("--port 11112"))
        #expect(cmd.contains("--called-aet ANY-SCP"))
        #expect(!cmd.contains("--host"))
    }

    // MARK: - AE Title (PS3.5 Table 6.2-1) and PHI redaction (PS3.15 Table E.1-1)

    @Test("validateAETitle accepts 16 characters and lower case (PS3.5 2026a Table 6.2-1: AE is 16 bytes maximum)")
    func test_aeTitle_limit() {
        #expect(ParameterValidationHelpers.validateAETitle("ABCDEFGHIJKLMNOP") == nil)
        #expect(ParameterValidationHelpers.validateAETitle("ABCDEFGHIJKLMNOPQ") != nil)
        #expect(ParameterValidationHelpers.validateAETitle("pacs_scp") == nil)
    }

    @Test("redactPHI redacts the 7 PS3.15 Table E.1-1 attributes it names")
    func test_redactPHI_sevenAttributes() {
        for keyword in ["PatientName", "PatientID", "PatientBirthDate", "AccessionNumber",
                        "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID"] {
            let redacted = CommandHistoryHelpers.redactPHI(from: "dicom-tags --set \(keyword)=SECRET123 x.dcm")
            #expect(!redacted.contains("SECRET123"), "\(keyword)")
            #expect(redacted.contains("\(keyword)=<redacted>"), "\(keyword)")
        }
    }
}
