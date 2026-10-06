// CLIWorkshopHelpersTests.swift
// DICOMStudioTests
//
// DICOM Studio — Tests for CLI Tools Workshop helpers (Milestone 16)

import Testing
@testable import DICOMStudio
import Foundation
import DICOMKit
import DICOMCore
import DICOMWeb

@Suite("CLI Workshop Helpers Tests")
struct CLIWorkshopHelpersTests {

    // MARK: - NetworkConfigHelpers

    @Test("validateAETitle accepts valid AE titles")
    func testValidAETitles() {
        #expect(NetworkConfigHelpers.validateAETitle("DICOMSTUDIO") == true)
        #expect(NetworkConfigHelpers.validateAETitle("A") == true)
        #expect(NetworkConfigHelpers.validateAETitle("1234567890123456") == true) // 16 chars
    }

    @Test("validateAETitle rejects invalid AE titles")
    func testInvalidAETitles() {
        #expect(NetworkConfigHelpers.validateAETitle("") == false)
        #expect(NetworkConfigHelpers.validateAETitle("12345678901234567") == false) // 17 chars
        #expect(NetworkConfigHelpers.validateAETitle(" A") == false) // leading space
    }

    @Test("validatePort accepts valid ports")
    func testValidPorts() {
        #expect(NetworkConfigHelpers.validatePort(1) == true)
        #expect(NetworkConfigHelpers.validatePort(11112) == true)
        #expect(NetworkConfigHelpers.validatePort(65535) == true)
    }

    @Test("validatePort rejects invalid ports")
    func testInvalidPorts() {
        #expect(NetworkConfigHelpers.validatePort(0) == false)
        #expect(NetworkConfigHelpers.validatePort(-1) == false)
        #expect(NetworkConfigHelpers.validatePort(65536) == false)
    }

    @Test("validateTimeout accepts valid timeouts")
    func testValidTimeouts() {
        #expect(NetworkConfigHelpers.validateTimeout(5) == true)
        #expect(NetworkConfigHelpers.validateTimeout(60) == true)
        #expect(NetworkConfigHelpers.validateTimeout(300) == true)
    }

    @Test("validateTimeout rejects invalid timeouts")
    func testInvalidTimeouts() {
        #expect(NetworkConfigHelpers.validateTimeout(4) == false)
        #expect(NetworkConfigHelpers.validateTimeout(301) == false)
        #expect(NetworkConfigHelpers.validateTimeout(0) == false)
    }

    @Test("validateHost accepts valid hosts")
    func testValidHosts() {
        #expect(NetworkConfigHelpers.validateHost("localhost") == true)
        #expect(NetworkConfigHelpers.validateHost("192.168.1.1") == true)
        #expect(NetworkConfigHelpers.validateHost("pacs.example.com") == true)
    }

    @Test("validateHost rejects empty or whitespace-only hosts")
    func testInvalidHosts() {
        #expect(NetworkConfigHelpers.validateHost("") == false)
        #expect(NetworkConfigHelpers.validateHost("   ") == false)
    }

    @Test("defaultProfile returns a valid profile")
    func testDefaultProfile() {
        let profile = NetworkConfigHelpers.defaultProfile()
        #expect(profile.name == "Default")
        #expect(profile.aeTitle == "DICOMSTUDIO")
        #expect(profile.calledAET == "ANY-SCP")
        #expect(profile.host == "localhost")
        #expect(profile.port == 11112)
        #expect(profile.timeout == 60)
        #expect(profile.protocolType == .dicom)
        #expect(profile.isDefault == true)
    }

    @Test("connectionSummary formats correctly")
    func testConnectionSummary() {
        let profile = CLINetworkProfile(name: "Test", aeTitle: "MY_AET", calledAET: "PACS",
                                        host: "192.168.1.1", port: 4242)
        let summary = NetworkConfigHelpers.connectionSummary(for: profile)
        #expect(summary.contains("MY_AET"))
        #expect(summary.contains("PACS"))
        #expect(summary.contains("192.168.1.1"))
        #expect(summary.contains("4242"))
    }

    @Test("maxAETitleLength is 16")
    func testMaxAETitleLength() {
        #expect(NetworkConfigHelpers.maxAETitleLength == 16)
    }

    // MARK: - ToolCatalogHelpers

    @Test("allTools returns exactly 33 tools")
    func testAllToolsCount() {
        #expect(ToolCatalogHelpers.allTools().count == 33)
    }

    @Test("totalToolCount is 33")
    func testTotalToolCount() {
        #expect(ToolCatalogHelpers.totalToolCount == 33)
    }

    @Test("fileInspectionTools returns 4 tools")
    func testFileInspectionToolsCount() {
        #expect(ToolCatalogHelpers.fileInspectionTools().count == 4)
    }

    @Test("fileProcessingTools returns 4 tools")
    func testFileProcessingToolsCount() {
        #expect(ToolCatalogHelpers.fileProcessingTools().count == 4)
    }

    @Test("fileOrganizationTools returns 4 tools")
    func testFileOrganizationToolsCount() {
        #expect(ToolCatalogHelpers.fileOrganizationTools().count == 4)
    }

    @Test("dataExportTools returns 7 tools")
    func testDataExportToolsCount() {
        #expect(ToolCatalogHelpers.dataExportTools().count == 7)
    }

    @Test("networkOperationsTools returns 11 tools")
    func testNetworkOperationsToolsCount() {
        #expect(ToolCatalogHelpers.networkOperationsTools().count == 11)
    }

    @Test("automationTools returns 3 tools")
    func testAutomationToolsCount() {
        #expect(ToolCatalogHelpers.automationTools().count == 3)
    }

    @Test("tools(for:) filters correctly by tab")
    func testToolsForTab() {
        for tab in CLIWorkshopTab.allCases {
            let tools = ToolCatalogHelpers.tools(for: tab)
            for tool in tools {
                #expect(tool.category == tab)
            }
        }
    }

    @Test("all tools have unique IDs")
    func testAllToolsUniqueIDs() {
        let ids = ToolCatalogHelpers.allTools().map { $0.id }
        #expect(Set(ids).count == ids.count)
    }

    @Test("all tools have non-empty names and descriptions")
    func testAllToolsProperties() {
        for tool in ToolCatalogHelpers.allTools() {
            #expect(!tool.name.isEmpty)
            #expect(!tool.displayName.isEmpty)
            #expect(!tool.briefDescription.isEmpty)
            #expect(!tool.sfSymbol.isEmpty)
        }
    }

    @Test("network tools require network")
    func testNetworkToolsRequireNetwork() {
        let networkTools = ToolCatalogHelpers.networkOperationsTools()
        for tool in networkTools {
            #expect(tool.requiresNetwork == true)
        }
    }

    @Test("all network tools have a networkToolGroup assigned")
    func testNetworkToolsHaveGroup() {
        let networkTools = ToolCatalogHelpers.networkOperationsTools()
        for tool in networkTools {
            #expect(tool.networkToolGroup != nil, "Tool \(tool.id) should have a networkToolGroup")
        }
    }

    @Test("groupedNetworkOperationsTools returns DIMSE and DICOMweb sections")
    func testGroupedNetworkOperationsTools() {
        let grouped = ToolCatalogHelpers.groupedNetworkOperationsTools()
        #expect(grouped.count == 2)
        #expect(grouped[0].group == .dimse)
        #expect(grouped[1].group == .dicomweb)
    }

    @Test("DIMSE group contains 7 tools")
    func testDIMSEGroupCount() {
        let grouped = ToolCatalogHelpers.groupedNetworkOperationsTools()
        let dimse = grouped.first { $0.group == .dimse }
        #expect(dimse != nil)
        #expect(dimse?.tools.count == 7)
    }

    @Test("DICOMweb group contains 4 tools")
    func testDICOMwebGroupCount() {
        let grouped = ToolCatalogHelpers.groupedNetworkOperationsTools()
        let web = grouped.first { $0.group == .dicomweb }
        #expect(web != nil)
        #expect(web?.tools.count == 4)
        let ids = Set(web?.tools.map { $0.id } ?? [])
        #expect(ids.contains("dicom-qido"))
        #expect(ids.contains("dicom-wado"))
        #expect(ids.contains("dicom-stow"))
        #expect(ids.contains("dicom-ups"))
    }

    @Test("NetworkToolGroup has correct display names")
    func testNetworkToolGroupDisplayNames() {
        #expect(NetworkToolGroup.dimse.displayName == "DIMSE Services")
        #expect(NetworkToolGroup.dicomweb.displayName == "DICOMweb")
    }

    @Test("tools with subcommands are identified correctly")
    func testToolsWithSubcommands() {
        let allTools = ToolCatalogHelpers.allTools()
        let withSubcommands = allTools.filter { $0.hasSubcommands }
        #expect(withSubcommands.count >= 6) // compress, dcmdir, export, wado, mpps, study, uid, script
    }

    // MARK: - CommandBuilderHelpers

    @Test("buildCommand with no parameters returns tool name only")
    func testBuildCommandEmpty() {
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-info", parameterValues: [], parameterDefinitions: [])
        #expect(cmd == "dicom-info")
    }

    @Test("buildCommand with subcommand includes it")
    func testBuildCommandSubcommand() {
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-compress", subcommand: "compress",
                                                     parameterValues: [], parameterDefinitions: [])
        #expect(cmd == "dicom-compress compress")
    }

    @Test("dicom-qido does not expose subcommand parameter")
    func testDicomQIDONoSubcommandParameter() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-qido")
        #expect(!defs.contains(where: { $0.id == "operation" }))
    }

    @Test("buildCommand includes flag and value parameters")
    func testBuildCommandWithParams() {
        let defs = [
            CLIParameterDefinition(id: "format", flag: "--format", displayName: "Format", parameterType: .enumPicker)
        ]
        let vals = [CLIParameterValue(parameterID: "format", stringValue: "json")]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-info", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd == "dicom-info --format json")
    }

    @Test("buildCommand uses positional host port for dicom-echo")
    func testBuildCommandDICOMEchoPositionalHostPort() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-echo")
        let vals = [
            CLIParameterValue(parameterID: "host", stringValue: "172.17.1.111"),
            CLIParameterValue(parameterID: "port", stringValue: "11112"),
            CLIParameterValue(parameterID: "aet", stringValue: "DICOMSTUDIO"),
            CLIParameterValue(parameterID: "called-aet", stringValue: "DCM4CHEE"),
            CLIParameterValue(parameterID: "count", stringValue: "1"),
            CLIParameterValue(parameterID: "timeout", stringValue: "30"),
        ]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-echo", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd == "dicom-echo 172.17.1.111:11112 --aet DICOMSTUDIO --called-aet DCM4CHEE --count 1 --timeout 30")
    }

    @Test("buildCommand handles boolean toggles correctly")
    func testBuildCommandBooleanToggle() {
        let defs = [
            CLIParameterDefinition(id: "verbose", flag: "--verbose", displayName: "Verbose", parameterType: .booleanToggle)
        ]
        let valsTrue = [CLIParameterValue(parameterID: "verbose", stringValue: "true")]
        let valsFalse = [CLIParameterValue(parameterID: "verbose", stringValue: "false")]
        let cmdTrue = CommandBuilderHelpers.buildCommand(toolName: "dicom-info", parameterValues: valsTrue, parameterDefinitions: defs)
        let cmdFalse = CommandBuilderHelpers.buildCommand(toolName: "dicom-info", parameterValues: valsFalse, parameterDefinitions: defs)
        #expect(cmdTrue == "dicom-info --verbose")
        #expect(cmdFalse == "dicom-info")
    }

    @Test("buildCommand expands repeatable options into repeated flags")
    func testBuildCommandRepeatableFlag() {
        let defs = [
            CLIParameterDefinition(id: "tag", flag: "--tag", displayName: "Filter Tag(s)",
                                   parameterType: .textField, isRepeatable: true)
        ]
        // Values are separated by a semicolon in the UI field.
        let vals = [CLIParameterValue(parameterID: "tag", stringValue: "PatientName;Modality")]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-info", parameterValues: vals, parameterDefinitions: defs)
        // Must match the real CLI's repeated-flag contract, not a single joined flag.
        #expect(cmd == "dicom-info --tag PatientName --tag Modality")
    }

    @Test("buildCommand repeatable option keeps a hex tag's comma intact")
    func testBuildCommandRepeatableKeepsHexComma() {
        let defs = [
            CLIParameterDefinition(id: "tag", flag: "--tag", displayName: "Filter Tag(s)",
                                   parameterType: .textField, isRepeatable: true)
        ]
        // A tag number contains a comma; the semicolon separator keeps it whole.
        let vals = [CLIParameterValue(parameterID: "tag", stringValue: "Patient's Name; 0008,0060")]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-info", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd == "dicom-info --tag 'Patient'\\''s Name' --tag 0008,0060")
    }

    @Test("buildCommand keeps non-repeatable comma values as a single flag")
    func testBuildCommandNonRepeatableKeepsComma() {
        let defs = [
            CLIParameterDefinition(id: "tags", flag: "--tags", displayName: "Tags to Copy",
                                   parameterType: .textField)   // isRepeatable defaults to false
        ]
        let vals = [CLIParameterValue(parameterID: "tags", stringValue: "PatientName,PatientID")]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-tags", parameterValues: vals, parameterDefinitions: defs)
        // dicom-tags --tags is comma-split by the CLI itself, so it stays joined.
        #expect(cmd == "dicom-tags --tags PatientName,PatientID")
    }

    @Test("buildCommand expands repeatable empty-flag definition into variadic positional tokens")
    func testBuildCommandRepeatablePositionalExpansion() {
        // An empty flag + isRepeatable models a variadic positional list
        // (`@Argument var inputs: [String]`): each semicolon-separated item
        // must become its own shell-escaped token, not one joined token.
        let defs = [
            CLIParameterDefinition(id: "inputs", flag: "", displayName: "Input Files",
                                   parameterType: .filePath, isRepeatable: true)
        ]
        let vals = [CLIParameterValue(parameterID: "inputs", stringValue: "in put.dcm; b.dcm")]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-validate", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd == "dicom-validate 'in put.dcm' b.dcm")

        // Same contract for the non-file default branch (e.g. `dicom-uid validate <uid> <uid>`).
        let textDefs = [
            CLIParameterDefinition(id: "uids", flag: "", displayName: "UIDs",
                                   parameterType: .textField, isRepeatable: true)
        ]
        let textVals = [CLIParameterValue(parameterID: "uids", stringValue: "1.2.840.10008.1.2; 1.2.840.10008.1.2.1")]
        let textCmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-uid", parameterValues: textVals, parameterDefinitions: textDefs)
        #expect(textCmd == "dicom-uid 1.2.840.10008.1.2 1.2.840.10008.1.2.1")
    }

    @Test("buildCommand booleanToggle with negatedFlag emits inverted token when off")
    func testBuildCommandBooleanToggleNegatedFlag() {
        // Inverted CLI flag (`@Flag(inversion: .prefixedNo)`, default true):
        // toggling OFF must emit the negated token (`--no-recursive`) so the
        // pasted command does not silently re-enable the disabled behavior.
        let defs = [
            CLIParameterDefinition(id: "recursive", flag: "--recursive", displayName: "Recursive",
                                   parameterType: .booleanToggle,
                                   negatedFlag: "--no-recursive", defaultValue: "true")
        ]
        let valsTrue = [CLIParameterValue(parameterID: "recursive", stringValue: "true")]
        let valsFalse = [CLIParameterValue(parameterID: "recursive", stringValue: "false")]
        let cmdTrue = CommandBuilderHelpers.buildCommand(toolName: "dicom-dcmdir", parameterValues: valsTrue, parameterDefinitions: defs)
        let cmdFalse = CommandBuilderHelpers.buildCommand(toolName: "dicom-dcmdir", parameterValues: valsFalse, parameterDefinitions: defs)
        #expect(cmdTrue == "dicom-dcmdir --recursive")
        #expect(cmdFalse == "dicom-dcmdir --no-recursive")
    }

    @Test("splitMultiValue splits on semicolons and preserves commas/spaces in values")
    func testSplitMultiValueSemicolon() {
        // Tag numbers keep their comma; names keep spaces and apostrophes.
        #expect(CommandBuilderHelpers.splitMultiValue("Patient's Name; 0008,0060") == ["Patient's Name", "0008,0060"])
        #expect(CommandBuilderHelpers.splitMultiValue("SOPInstanceUID; 0008,0012") == ["SOPInstanceUID", "0008,0012"])
        #expect(CommandBuilderHelpers.splitMultiValue("0010,0010; 0008,0018") == ["0010,0010", "0008,0018"])
        #expect(CommandBuilderHelpers.splitMultiValue("PatientName=DOE^JOHN; 0008,0090=DR.SMITH")
                == ["PatientName=DOE^JOHN", "0008,0090=DR.SMITH"])
        // Single value with a comma is NOT split.
        #expect(CommandBuilderHelpers.splitMultiValue("0008,0060") == ["0008,0060"])
        // Empties and stray separators are dropped.
        #expect(CommandBuilderHelpers.splitMultiValue("") == [])
        #expect(CommandBuilderHelpers.splitMultiValue(" ; Modality ; ") == ["Modality"])
    }

    @Test("dicom-diff ignore-tag emits repeated flags for two hex tags")
    func testBuildCommandDiffIgnoreTagRepeated() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-diff")
        let vals = [
            CLIParameterValue(parameterID: "file1", stringValue: "a.dcm"),
            CLIParameterValue(parameterID: "file2", stringValue: "b.dcm"),
            CLIParameterValue(parameterID: "ignore-tag", stringValue: "0010,0010; 0008,0018"),
        ]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-diff", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd.contains("--ignore-tag 0010,0010"))
        #expect(cmd.contains("--ignore-tag 0008,0018"))
    }

    @Test("buildCommand handles flagPicker by emitting --value")
    func testBuildCommandFlagPicker() {
        let defs = [
            CLIParameterDefinition(id: "host", flag: "--host", displayName: "Host", parameterType: .textField),
            CLIParameterDefinition(
                id: "mode", flag: "", displayName: "Operation Mode",
                parameterType: .flagPicker, allowedValues: ["interactive", "auto", "review"]
            ),
        ]
        let vals = [
            CLIParameterValue(parameterID: "host", stringValue: "192.168.1.1"),
            CLIParameterValue(parameterID: "mode", stringValue: "interactive"),
        ]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-qr", parameterValues: vals, parameterDefinitions: defs)
        // dicom-qr uses a positional host:port endpoint (see CommandBuilderHelpers
        // usesPositionalEndpoint), so --host is collapsed into the positional arg.
        #expect(cmd == "dicom-qr 192.168.1.1 --interactive")
    }

    @Test("buildCommand flagPicker emits --auto for auto value")
    func testBuildCommandFlagPickerAuto() {
        let defs = [
            CLIParameterDefinition(
                id: "mode", flag: "", displayName: "Mode",
                parameterType: .flagPicker, allowedValues: ["interactive", "auto", "review"]
            ),
        ]
        let vals = [CLIParameterValue(parameterID: "mode", stringValue: "auto")]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-qr", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd == "dicom-qr --auto")
    }

    @Test("buildCommand handles file path with spaces")
    func testBuildCommandFilePathSpaces() {
        let defs = [
            CLIParameterDefinition(id: "input", flag: "", displayName: "Input", parameterType: .filePath)
        ]
        let vals = [CLIParameterValue(parameterID: "input", stringValue: "/path/to my/file.dcm")]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-info", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd.contains("'/path/to my/file.dcm'"))
    }

    @Test("shellEscape handles paths with spaces")
    func testShellEscapeSpaces() {
        #expect(CommandBuilderHelpers.shellEscape("/simple/path") == "/simple/path")
        #expect(CommandBuilderHelpers.shellEscape("/path with spaces/file.dcm") == "'/path with spaces/file.dcm'")
    }

    @Test("shellEscape handles single quotes")
    func testShellEscapeSingleQuotes() {
        let result = CommandBuilderHelpers.shellEscape("it's a file")
        #expect(result.contains("'\\''"))
    }

    @Test("validateRequired returns true when all required params have values")
    func testValidateRequiredTrue() {
        let defs = [
            CLIParameterDefinition(id: "input", flag: "", displayName: "Input", parameterType: .filePath, isRequired: true)
        ]
        let vals = [CLIParameterValue(parameterID: "input", stringValue: "file.dcm")]
        #expect(CommandBuilderHelpers.validateRequired(parameterValues: vals, parameterDefinitions: defs) == true)
    }

    @Test("validateRequired returns false when required param is missing")
    func testValidateRequiredFalse() {
        let defs = [
            CLIParameterDefinition(id: "input", flag: "", displayName: "Input", parameterType: .filePath, isRequired: true)
        ]
        #expect(CommandBuilderHelpers.validateRequired(parameterValues: [], parameterDefinitions: defs) == false)
    }

    @Test("validateRequired returns false when required param is empty")
    func testValidateRequiredEmpty() {
        let defs = [
            CLIParameterDefinition(id: "input", flag: "", displayName: "Input", parameterType: .filePath, isRequired: true)
        ]
        let vals = [CLIParameterValue(parameterID: "input", stringValue: "  ")]
        #expect(CommandBuilderHelpers.validateRequired(parameterValues: vals, parameterDefinitions: defs) == false)
    }

    @Test("missingRequiredParameters lists missing params")
    func testMissingRequiredParameters() {
        let defs = [
            CLIParameterDefinition(id: "input", flag: "", displayName: "Input File", parameterType: .filePath, isRequired: true),
            CLIParameterDefinition(id: "format", flag: "--format", displayName: "Format", parameterType: .enumPicker, isRequired: false),
        ]
        let missing = CommandBuilderHelpers.missingRequiredParameters(parameterValues: [], parameterDefinitions: defs)
        #expect(missing == ["Input File"])
    }

    @Test("buildCommand emits cliMapping tokens for internal parameters")
    func testBuildCommandCLIMapping() {
        let defs = [
            CLIParameterDefinition(
                id: "proto", flag: "", displayName: "Protocol",
                parameterType: .enumPicker, isInternal: true,
                defaultValue: "wado-rs", allowedValues: ["wado-rs", "wado-uri"],
                cliMapping: ["wado-uri": "--uri"]
            ),
            CLIParameterDefinition(
                id: "url", flag: "", displayName: "URL",
                parameterType: .textField
            ),
        ]
        // When mapped value is selected, the mapped flag appears
        let valsURI = [
            CLIParameterValue(parameterID: "proto", stringValue: "wado-uri"),
            CLIParameterValue(parameterID: "url", stringValue: "http://server/wado"),
        ]
        let cmdURI = CommandBuilderHelpers.buildCommand(toolName: "dicom-wado retrieve", parameterValues: valsURI, parameterDefinitions: defs)
        // Mapped tokens from internal parameters are deferred until after the first
        // positional argument (URL) — see CommandBuilderHelpers deferredMappedTokens.
        #expect(cmdURI == "dicom-wado retrieve http://server/wado --uri")

        // When unmapped value is selected, no extra flag appears
        let valsRS = [
            CLIParameterValue(parameterID: "proto", stringValue: "wado-rs"),
            CLIParameterValue(parameterID: "url", stringValue: "http://server/dicom-web"),
        ]
        let cmdRS = CommandBuilderHelpers.buildCommand(toolName: "dicom-wado retrieve", parameterValues: valsRS, parameterDefinitions: defs)
        #expect(cmdRS == "dicom-wado retrieve http://server/dicom-web")
    }

    @Test("buildCommand cliMapping emits multi-token values")
    func testBuildCommandCLIMappingMultiToken() {
        let defs = [
            CLIParameterDefinition(
                id: "ctype", flag: "", displayName: "Content Type",
                parameterType: .enumPicker, isInternal: true,
                defaultValue: "application/dicom",
                allowedValues: ["application/dicom", "image/jpeg"],
                cliMapping: ["image/jpeg": "--content-type image/jpeg"]
            ),
        ]
        let vals = [CLIParameterValue(parameterID: "ctype", stringValue: "image/jpeg")]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-wado retrieve", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd == "dicom-wado retrieve --content-type image/jpeg")

        // Default value has no mapping → no extra tokens
        let valsDefault = [CLIParameterValue(parameterID: "ctype", stringValue: "application/dicom")]
        let cmdDefault = CommandBuilderHelpers.buildCommand(toolName: "dicom-wado retrieve", parameterValues: valsDefault, parameterDefinitions: defs)
        #expect(cmdDefault == "dicom-wado retrieve")
    }

    @Test("buildCommand omits UPS output format for non-retrieval operations")
    func testBuildCommandUPSOutputFormatVisibility() {
        let defs = [
            CLIParameterDefinition(
                id: "operation", flag: "", displayName: "Operation",
                parameterType: .enumPicker, isInternal: true,
                defaultValue: "search", allowedValues: ["search", "get", "create-workitem", "change-state", "subscribe"]
            ),
            CLIParameterDefinition(
                id: "url", flag: "", displayName: "Base URL",
                parameterType: .textField
            ),
            CLIParameterDefinition(
                id: "output-format", flag: "--format", displayName: "Output Format",
                parameterType: .enumPicker,
                defaultValue: "table",
                allowedValues: ["table", "json"],
                visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["search", "get"])
            ),
            CLIParameterDefinition(
                id: "create-workitem-flag", flag: "--create-workitem", displayName: "Create Workitem",
                parameterType: .booleanToggle,
                visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create-workitem"])
            ),
        ]

        let retrievalValues = [
            CLIParameterValue(parameterID: "operation", stringValue: "search"),
            CLIParameterValue(parameterID: "url", stringValue: "https://server/dicom-web"),
            CLIParameterValue(parameterID: "output-format", stringValue: "table"),
        ]
        let retrievalCommand = CommandBuilderHelpers.buildCommand(
            toolName: "dicom-wado ups",
            parameterValues: retrievalValues,
            parameterDefinitions: defs
        )
        #expect(retrievalCommand.contains("--format table"))

        let createValues = [
            CLIParameterValue(parameterID: "operation", stringValue: "create-workitem"),
            CLIParameterValue(parameterID: "url", stringValue: "https://server/dicom-web"),
            CLIParameterValue(parameterID: "output-format", stringValue: "table"),
            CLIParameterValue(parameterID: "create-workitem-flag", stringValue: "true"),
        ]
        let createCommand = CommandBuilderHelpers.buildCommand(
            toolName: "dicom-wado ups",
            parameterValues: createValues,
            parameterDefinitions: defs
        )
        #expect(!createCommand.contains("--format"))
        #expect(createCommand.contains("--create-workitem"))
    }

    @Test("tokenize correctly identifies tool name, flags, values, and paths")
    func testTokenize() {
        let tokens = CommandBuilderHelpers.tokenize("dicom-info --format json /path/to/file.dcm")
        #expect(tokens.count == 4)
        #expect(tokens[0].tokenType == .toolName)
        #expect(tokens[1].tokenType == .flag)
        #expect(tokens[2].tokenType == .value)
        #expect(tokens[3].tokenType == .path)
    }

    @Test("tokenize handles empty command")
    func testTokenizeEmpty() {
        let tokens = CommandBuilderHelpers.tokenize("")
        #expect(tokens.isEmpty)
    }

    // MARK: - FileDropHelpers

    @Test("isDICOMFile recognizes DICOM extensions")
    func testIsDICOMFile() {
        #expect(FileDropHelpers.isDICOMFile("scan.dcm") == true)
        #expect(FileDropHelpers.isDICOMFile("scan.dicom") == true)
        #expect(FileDropHelpers.isDICOMFile("scan.dic") == true)
        #expect(FileDropHelpers.isDICOMFile("scan.DCM") == true)
    }

    @Test("isDICOMFile recognizes extensionless files as potential DICOM")
    func testIsDICOMFileNoExtension() {
        #expect(FileDropHelpers.isDICOMFile("DICOMDIR") == true)
    }

    @Test("isDICOMFile rejects non-DICOM extensions")
    func testIsDICOMFileRejectsNonDICOM() {
        #expect(FileDropHelpers.isDICOMFile("image.png") == false)
        #expect(FileDropHelpers.isDICOMFile("data.json") == false)
    }

    @Test("formatFileSize formats bytes correctly")
    func testFormatFileSize() {
        #expect(FileDropHelpers.formatFileSize(512) == "512 B")
        #expect(FileDropHelpers.formatFileSize(1536).contains("KB"))
        #expect(FileDropHelpers.formatFileSize(2_097_152).contains("MB"))
        #expect(FileDropHelpers.formatFileSize(2_147_483_648).contains("GB"))
    }

    @Test("fileSummary describes file count correctly")
    func testFileSummary() {
        #expect(FileDropHelpers.fileSummary([]) == "No files selected")
        let file = CLIFileEntry(path: "/f", filename: "scan.dcm")
        #expect(FileDropHelpers.fileSummary([file]) == "scan.dcm")
        let file2 = CLIFileEntry(path: "/g", filename: "other.dcm")
        #expect(FileDropHelpers.fileSummary([file, file2]) == "2 files selected")
    }

    // MARK: - ConsoleHelpers

    @Test("maxHistoryCount is 50")
    func testMaxHistoryCount() {
        #expect(ConsoleHelpers.maxHistoryCount == 50)
    }

    @Test("redactPHI redacts patient names")
    func testRedactPHIPatientName() {
        let cmd = "dicom-anon --patient-name \"John Doe\" file.dcm"
        let redacted = ConsoleHelpers.redactPHI(cmd)
        #expect(!redacted.contains("John Doe"))
        #expect(redacted.contains("<redacted>"))
    }

    @Test("redactPHI redacts patient IDs")
    func testRedactPHIPatientID() {
        let cmd = "dicom-anon --patient-id MRN123456 file.dcm"
        let redacted = ConsoleHelpers.redactPHI(cmd)
        #expect(!redacted.contains("MRN123456"))
        #expect(redacted.contains("<redacted>"))
    }

    @Test("redactPHI redacts OAuth tokens")
    func testRedactPHIOAuth() {
        let cmd = "dicom-wado --token secret123abc retrieve"
        let redacted = ConsoleHelpers.redactPHI(cmd)
        #expect(!redacted.contains("secret123abc"))
        #expect(redacted.contains("<redacted>"))
    }

    @Test("redactPHI preserves non-PHI command parts")
    func testRedactPHIPreserves() {
        let cmd = "dicom-info --format json file.dcm"
        let redacted = ConsoleHelpers.redactPHI(cmd)
        #expect(redacted == cmd)
    }

    @Test("formatTimestamp produces non-empty string")
    func testFormatTimestamp() {
        let result = ConsoleHelpers.formatTimestamp(Date())
        #expect(!result.isEmpty)
    }

    @Test("trimHistory keeps at most 50 entries")
    func testTrimHistory() {
        var history: [CLICommandHistoryEntry] = []
        for i in 0..<60 {
            history.append(CLICommandHistoryEntry(toolName: "t\(i)", rawCommand: "c", redactedCommand: "c"))
        }
        let trimmed = ConsoleHelpers.trimHistory(history)
        #expect(trimmed.count == 50)
    }

    @Test("trimHistory preserves history under limit")
    func testTrimHistoryUnderLimit() {
        let history = [CLICommandHistoryEntry(toolName: "t", rawCommand: "c", redactedCommand: "c")]
        let trimmed = ConsoleHelpers.trimHistory(history)
        #expect(trimmed.count == 1)
    }

    // MARK: - EducationalHelpers

    @Test("defaultGlossaryEntries returns 15 entries")
    func testDefaultGlossaryCount() {
        #expect(EducationalHelpers.defaultGlossaryEntries().count == 15)
    }

    @Test("defaultGlossaryCount matches array count")
    func testDefaultGlossaryCountProperty() {
        #expect(EducationalHelpers.defaultGlossaryCount == EducationalHelpers.defaultGlossaryEntries().count)
    }

    @Test("all glossary entries have non-empty term and definition")
    func testGlossaryEntriesContent() {
        for entry in EducationalHelpers.defaultGlossaryEntries() {
            #expect(!entry.term.isEmpty)
            #expect(!entry.definition.isEmpty)
        }
    }

    @Test("filterGlossary returns all entries for empty query")
    func testFilterGlossaryEmptyQuery() {
        let entries = EducationalHelpers.defaultGlossaryEntries()
        let filtered = EducationalHelpers.filterGlossary(entries, query: "")
        #expect(filtered.count == entries.count)
    }

    @Test("filterGlossary filters by term")
    func testFilterGlossaryByTerm() {
        let entries = EducationalHelpers.defaultGlossaryEntries()
        let filtered = EducationalHelpers.filterGlossary(entries, query: "AE Title")
        #expect(filtered.count >= 1)
        #expect(filtered[0].term == "AE Title")
    }

    @Test("filterGlossary filters by definition content")
    func testFilterGlossaryByDefinition() {
        let entries = EducationalHelpers.defaultGlossaryEntries()
        let filtered = EducationalHelpers.filterGlossary(entries, query: "verification")
        #expect(filtered.count >= 1)
    }

    @Test("filterGlossary is case-insensitive")
    func testFilterGlossaryCaseInsensitive() {
        let entries = EducationalHelpers.defaultGlossaryEntries()
        let upper = EducationalHelpers.filterGlossary(entries, query: "AE TITLE")
        let lower = EducationalHelpers.filterGlossary(entries, query: "ae title")
        #expect(upper.count == lower.count)
    }

    @Test("examplePresets returns entries for known tools")
    func testExamplePresetsKnown() {
        let presets = EducationalHelpers.examplePresets(for: "dicom-info")
        #expect(!presets.isEmpty)
        for p in presets {
            #expect(p.toolID == "dicom-info")
            #expect(!p.commandString.isEmpty)
        }
    }

    @Test("examplePresets returns empty for unknown tool")
    func testExamplePresetsUnknown() {
        let presets = EducationalHelpers.examplePresets(for: "nonexistent-tool")
        #expect(presets.isEmpty)
    }

    // MARK: - buildCommand visibleWhen filtering

    @Test("buildCommand excludes parameters whose visibleWhen condition is not met")
    func testBuildCommandVisibleWhenExcludesHidden() {
        let defs = [
            CLIParameterDefinition(
                id: "operation", flag: "", displayName: "Operation",
                parameterType: .subcommand, allowedValues: ["query", "create"]
            ),
            CLIParameterDefinition(
                id: "modality", flag: "--modality", displayName: "Modality",
                parameterType: .enumPicker,
                visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])
            ),
            CLIParameterDefinition(
                id: "patient-name", flag: "--patient-name", displayName: "Patient Name",
                parameterType: .textField,
                visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
            ),
        ]
        // Operation is "query" — modality should appear, patient-name should not
        let vals = [
            CLIParameterValue(parameterID: "operation", stringValue: "query"),
            CLIParameterValue(parameterID: "modality", stringValue: "CT"),
            CLIParameterValue(parameterID: "patient-name", stringValue: "DOE^JOHN"),
        ]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-mwl", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd.contains("--modality CT"))
        #expect(!cmd.contains("--patient-name"))
        #expect(!cmd.contains("DOE^JOHN"))
    }

    @Test("buildCommand includes parameters whose visibleWhen condition IS met")
    func testBuildCommandVisibleWhenIncludesVisible() {
        let defs = [
            CLIParameterDefinition(
                id: "operation", flag: "", displayName: "Operation",
                parameterType: .subcommand, allowedValues: ["query", "create"]
            ),
            CLIParameterDefinition(
                id: "patient-name", flag: "--patient-name", displayName: "Patient Name",
                parameterType: .textField,
                visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])
            ),
        ]
        // Operation is "create" — patient-name should appear
        let vals = [
            CLIParameterValue(parameterID: "operation", stringValue: "create"),
            CLIParameterValue(parameterID: "patient-name", stringValue: "DOE^JOHN"),
        ]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-mwl", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd.contains("--patient-name DOE^JOHN"))
    }

    @Test("buildCommand includes parameters without visibleWhen (always visible)")
    func testBuildCommandNoVisibleWhenAlwaysIncluded() {
        let defs = [
            CLIParameterDefinition(
                id: "host", flag: "--host", displayName: "Host",
                parameterType: .textField
            ),
        ]
        let vals = [CLIParameterValue(parameterID: "host", stringValue: "localhost")]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-mwl", parameterValues: vals, parameterDefinitions: defs)
        // dicom-mwl uses a positional host:port endpoint, so --host collapses into
        // the positional arg even though the parameter has no visibleWhen guard.
        #expect(cmd == "dicom-mwl localhost")
    }

    @Test("buildCommand uses default value for visibleWhen check when parameter value is empty")
    func testBuildCommandVisibleWhenDefaultValue() {
        let defs = [
            CLIParameterDefinition(
                id: "operation", flag: "", displayName: "Operation",
                parameterType: .subcommand, defaultValue: "query",
                allowedValues: ["query", "create"]
            ),
            CLIParameterDefinition(
                id: "modality", flag: "--modality", displayName: "Modality",
                parameterType: .enumPicker,
                visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])
            ),
        ]
        // No explicit operation value — should fall back to default "query"
        let vals = [
            CLIParameterValue(parameterID: "operation", stringValue: ""),
            CLIParameterValue(parameterID: "modality", stringValue: "MR"),
        ]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-mwl", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd.contains("--modality MR"))
    }

    // MARK: - dicom-convert Parameter Definitions

    @Test("dicom-convert has parameter definitions")
    func testDicomConvertHasParameterDefs() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-convert")
        #expect(!defs.isEmpty)
    }

    @Test("dicom-convert requires inputPath and output")
    func testDicomConvertRequiredParams() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-convert")
        let required = defs.filter { $0.isRequired }
        let requiredIDs = Set(required.map { $0.id })
        #expect(requiredIDs.contains("inputPath"))
        #expect(requiredIDs.contains("output"))
        #expect(required.count == 2)
    }

    @Test("dicom-convert has expected parameter count (14: --frame-number joined the deprecated --frame)")
    func testDicomConvertParameterCount() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-convert")
        #expect(defs.count == 14)
    }

    @Test("dicom-convert format parameter has enum values")
    func testDicomConvertFormatParam() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-convert")
        let formatParam = defs.first { $0.id == "format" }
        #expect(formatParam != nil)
        #expect(formatParam?.parameterType == .enumPicker)
        #expect(formatParam?.allowedValues.contains("dicom") == true)
        #expect(formatParam?.allowedValues.contains("png") == true)
        #expect(formatParam?.allowedValues.contains("jpeg") == true)
        #expect(formatParam?.allowedValues.contains("tiff") == true)
        #expect(formatParam?.defaultValue == "dicom")
    }

    @Test("dicom-convert transfer-syntax visible only for DICOM format")
    func testDicomConvertTransferSyntaxVisibility() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-convert")
        let tsParam = defs.first { $0.id == "transfer-syntax" }
        #expect(tsParam != nil)
        #expect(tsParam?.visibleWhen?.parameterId == "format")
        #expect(tsParam?.visibleWhen?.values == ["dicom"])
    }

    @Test("dicom-convert quality visible only for JPEG format")
    func testDicomConvertQualityVisibility() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-convert")
        let qualityParam = defs.first { $0.id == "quality" }
        #expect(qualityParam != nil)
        #expect(qualityParam?.visibleWhen?.parameterId == "format")
        #expect(qualityParam?.visibleWhen?.values == ["jpeg"])
        #expect(qualityParam?.minValue == 1)
        #expect(qualityParam?.maxValue == 100)
        #expect(qualityParam?.defaultValue == "90")
    }

    @Test("dicom-convert windowing params visible only for image formats")
    func testDicomConvertWindowingVisibility() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-convert")
        let imageFormats = ["png", "jpeg", "tiff"]
        for paramID in ["window-center", "window-width", "apply-window", "frame"] {
            let param = defs.first { $0.id == paramID }
            #expect(param != nil, "Expected parameter \(paramID)")
            #expect(param?.visibleWhen?.parameterId == "format")
            #expect(param?.visibleWhen?.values == imageFormats, "\(paramID) should be visible for image formats")
        }
    }

    @Test("dicom-convert advanced params are flagged correctly")
    func testDicomConvertAdvancedParams() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-convert")
        let advancedIDs = Set(defs.filter { $0.isAdvanced }.map { $0.id })
        #expect(advancedIDs.contains("strip-private"))
        #expect(advancedIDs.contains("recursive"))
        #expect(advancedIDs.contains("validate"))
        #expect(advancedIDs.contains("force"))
    }

    @Test("dicom-convert buildCommand produces correct output for DICOM conversion")
    func testDicomConvertBuildCommandDicom() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-convert")
        let vals: [CLIParameterValue] = [
            CLIParameterValue(parameterID: "inputPath", stringValue: "scan.dcm"),
            CLIParameterValue(parameterID: "output", stringValue: "out.dcm"),
            CLIParameterValue(parameterID: "format", stringValue: "dicom"),
            CLIParameterValue(parameterID: "transfer-syntax", stringValue: "ExplicitVRLittleEndian"),
        ]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-convert", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd.contains("dicom-convert"))
        #expect(cmd.contains("scan.dcm"))
        #expect(cmd.contains("--output out.dcm"))
        #expect(cmd.contains("--format dicom"))
        #expect(cmd.contains("--transfer-syntax ExplicitVRLittleEndian"))
    }

    @Test("dicom-convert buildCommand produces correct output for image export")
    func testDicomConvertBuildCommandImage() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-convert")
        let vals: [CLIParameterValue] = [
            CLIParameterValue(parameterID: "inputPath", stringValue: "ct.dcm"),
            CLIParameterValue(parameterID: "output", stringValue: "ct.png"),
            CLIParameterValue(parameterID: "format", stringValue: "png"),
            CLIParameterValue(parameterID: "apply-window", stringValue: "true"),
            CLIParameterValue(parameterID: "window-center", stringValue: "40"),
            CLIParameterValue(parameterID: "window-width", stringValue: "400"),
        ]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-convert", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd.contains("--format png"))
        #expect(cmd.contains("--window-center 40"))
        #expect(cmd.contains("--window-width 400"))
        #expect(cmd.contains("--apply-window"))
    }

    @Test("dicom-convert buildCommand handles boolean flags")
    func testDicomConvertBuildCommandFlags() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-convert")
        let vals: [CLIParameterValue] = [
            CLIParameterValue(parameterID: "inputPath", stringValue: "dir/"),
            CLIParameterValue(parameterID: "output", stringValue: "out/"),
            CLIParameterValue(parameterID: "format", stringValue: "dicom"),
            CLIParameterValue(parameterID: "transfer-syntax", stringValue: "ImplicitVRLittleEndian"),
            CLIParameterValue(parameterID: "strip-private", stringValue: "true"),
            CLIParameterValue(parameterID: "recursive", stringValue: "true"),
            CLIParameterValue(parameterID: "validate", stringValue: "true"),
            CLIParameterValue(parameterID: "force", stringValue: "true"),
        ]
        let cmd = CommandBuilderHelpers.buildCommand(toolName: "dicom-convert", parameterValues: vals, parameterDefinitions: defs)
        #expect(cmd.contains("--strip-private"))
        #expect(cmd.contains("--recursive"))
        #expect(cmd.contains("--validate"))
        #expect(cmd.contains("--force"))
    }

    @Test("dicom-convert example presets exist")
    func testDicomConvertExamplePresets() {
        let presets = EducationalHelpers.examplePresets(for: "dicom-convert")
        #expect(presets.count == 4)
        #expect(presets.allSatisfy { $0.toolID == "dicom-convert" })
        #expect(presets.allSatisfy { !$0.title.isEmpty })
        #expect(presets.allSatisfy { !$0.commandString.isEmpty })
    }

    @Test("dicom-convert validateRequired detects missing required fields")
    func testDicomConvertValidateRequired() {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-convert")

        // No values: should fail
        #expect(CommandBuilderHelpers.validateRequired(parameterValues: [], parameterDefinitions: defs) == false)

        // Only input: should fail (output missing)
        let partialVals = [CLIParameterValue(parameterID: "inputPath", stringValue: "test.dcm")]
        #expect(CommandBuilderHelpers.validateRequired(parameterValues: partialVals, parameterDefinitions: defs) == false)

        // Both input and output: should pass
        let fullVals = [
            CLIParameterValue(parameterID: "inputPath", stringValue: "test.dcm"),
            CLIParameterValue(parameterID: "output", stringValue: "out.dcm"),
        ]
        #expect(CommandBuilderHelpers.validateRequired(parameterValues: fullVals, parameterDefinitions: defs) == true)
    }

    // MARK: - dicom-anon --profile (PS3.15 2026a Annex E; P-ANON-PROFILE)

    @Test("Workshop dicom-anon --profile offers the CLI's legacy lists and defaults to legacy-basic, not the PS3.15 alias basic")
    func testAnonProfilePickerMirrorsCLILegacyNames() {
        let params = ToolCatalogHelpers.parameterDefinitions(for: "dicom-anon")
        let profile = params.first { $0.flag == "--profile" }
        #expect(profile != nil)
        #expect(profile?.allowedValues == ["legacy-basic", "legacy-clinical-trial", "legacy-research"])
        #expect(profile?.defaultValue == "legacy-basic")
        #expect(profile?.helpText.contains("PS3.15") == true)
    }

    @Test("Workshop dicom-anon presets do not send --profile basic (now the PS3.15 Basic Profile)")
    func testAnonPresetsUseLegacyBasic() {
        let presets = EducationalHelpers.examplePresets(for: "dicom-anon")
        #expect(!presets.isEmpty)
        for preset in presets {
            #expect(!preset.commandString.contains("--profile basic"), Comment(rawValue: preset.commandString))
            #expect(preset.commandString.contains("--profile legacy-basic"), Comment(rawValue: preset.commandString))
        }
    }


    // MARK: - Pixel / codec tools mirror the dicom-* CLIs (DICOM 2026a; P-ANON-*, P-IMAGE-VR, P-PIXEDIT-RANGE, P-VIDEO-*, P-CONVERT-*, P-COMPRESS-*)

    private func pixelParam(_ tool: String, _ id: String) -> CLIParameterDefinition? {
        ToolCatalogHelpers.parameterDefinitions(for: tool).first { $0.id == id }
    }

    @Test("dicom-anon offers every PS3.15 2026a E.3 Option flag of dicom-anon (CID 7050 names in the help), --retain-dates deprecated, the pixel-cleaning options")
    func anonOptionFlags() throws {
        let expected = ["retain-dates", "retain-full-dates", "retain-modified-dates", "retain-characteristics", "retain-device",
                        "retain-institution", "retain-uids", "clean-descriptors", "retain-safe-private", "clean-graphics",
                        "clean-structured-content", "clean-recognizable-visual-features", "clean-pixel-data", "allow-burned-in-phi"]
        for id in expected {
            let p = try #require(pixelParam("dicom-anon", id), Comment(rawValue: id))
            #expect(p.flag == "--" + id)
            #expect(p.parameterType == .booleanToggle)
            #expect(p.defaultValue.isEmpty)                      // never emitted unless switched on
        }
        #expect(pixelParam("dicom-anon", "retain-dates")?.helpText.hasPrefix("Deprecated: use --retain-full-dates or --retain-modified-dates") == true)
        #expect(pixelParam("dicom-anon", "retain-uids")?.helpText.contains("Retain UIDs Option") == true)              // CID 7050 113110
        #expect(pixelParam("dicom-anon", "retain-full-dates")?.helpText.contains("Retain Longitudinal Temporal Information With Full Dates Option") == true)
        let region = try #require(pixelParam("dicom-anon", "redact-region"))
        #expect(region.isRepeatable && region.flag == "--redact-region")
        #expect(pixelParam("dicom-anon", "redact-fill")?.parameterType == .integerField)
    }

    @Test("dicom-image / dicom-pdf --conversion-type offer the 8 PS3.3 2026a Table C.8-24 Defined Terms (ConversionType.definedTerms), empty = the CLI's WSD")
    func conversionTypePickers() throws {
        for tool in ["dicom-image", "dicom-pdf"] {
            let p = try #require(pixelParam(tool, "conversion-type"), Comment(rawValue: tool))
            #expect(p.allowedValues == [""] + ConversionType.definedTerms)
            #expect(ConversionType.definedTerms == ["DV", "DI", "DF", "WSD", "SD", "SI", "DRW", "SYN"])
            #expect(p.defaultValue.isEmpty)
            #expect(pixelParam(tool, "strict-modality")?.flag == "--strict-modality")
        }
        #expect(pixelParam("dicom-pdf", "burned-in-annotation")?.allowedValues == ["", "YES", "NO"])        // PS3.3 Table C.24-2
        #expect(pixelParam("dicom-pdf", "hl7-instance-identifier")?.flag == "--hl7-instance-identifier")   // Type 1C for CDA
        #expect(pixelParam("dicom-image", "modality")?.helpText == ModalityOptionValidator.helpText("to write (default: OT)"))
        #expect(pixelParam("dicom-image", "modality")?.defaultValue.isEmpty == true)
    }

    @Test("dicom-video offers --strict-modality and --audio-channel-source (PS3.16 CID 3000 keywords, D56); the refusal help suffixes are the CLI's")
    func videoConformanceRows() throws {
        let src = try #require(pixelParam("dicom-video", "audioChannelSource"))
        #expect(src.flag == "--audio-channel-source" && src.isRepeatable)
        #expect(src.helpText.hasPrefix(AudioChannelSourceOption.help))
        #expect(AudioChannelSourceOption.keywords.map(\.keyword) ==
                ["voice", "operators-narrative", "ambient-room-environment", "doppler-audio", "phonocardiogram", "physiological-audio-signal"])
        #expect(AudioChannelSourceOption.keywords.map(\.source.codeValue) == ["109110", "109111", "109112", "109113", "109114", "109115"])
        #expect(try AudioChannelSourceOption.parse("Voice") == .voice)
        #expect(try AudioChannelSourceOption.parse("DCM:109113") == .dopplerAudio)
        #expect(throws: AudioChannelSourceOption.ParseError.missingMeaning("DCM:1")) { try AudioChannelSourceOption.parse("DCM:1") }
        #expect(pixelParam("dicom-video", "strictModality")?.flag == "--strict-modality")
        #expect(pixelParam("dicom-video", "modality")?.helpText == VideoOptionConformance.modalityHelp)
        #expect(pixelParam("dicom-video", "patientSex")?.helpText == VideoOptionConformance.patientSexHelp)
        #expect(pixelParam("dicom-video", "patientBirthDate")?.helpText == VideoOptionConformance.patientBirthDateHelp)
        #expect(pixelParam("dicom-video", "transferSyntax")?.helpText.hasPrefix(VideoOptionConformance.transferSyntaxHelp) == true)
        // PS3.3 A.32.5.4.1 / A.32.6.4.1 / A.32.7.4.1 and Table C.7-1
        var meta = VideoWorkflow.Metadata(patientBirthDate: "2024-01-01", patientSex: "U", modality: "CT")
        var lines = VideoOptionConformance.violations(type: .endoscopic, metadata: meta, transferSyntax: "1.2.840.10008.1.2.4.107.1")
        #expect(lines.count == 4)
        #expect(lines[0].contains("not registered in PS3.6 Table A-1"))
        #expect(lines[1].contains("PS3.3 A.32.5.4.1 requires Modality (0008,0060) ES"))
        #expect(lines[2].contains("M, F or O; PS3.3 Table C.7-1"))
        #expect(lines[3].contains("is not a DA value"))
        meta = VideoWorkflow.Metadata(patientBirthDate: "20240101", patientSex: "F", modality: "GM")
        lines = VideoOptionConformance.violations(type: .microscopic, metadata: meta, transferSyntax: "1.2.840.10008.1.2.4.108")
        #expect(lines.isEmpty)
    }

    @Test("dicom-convert --transfer-syntax offers DICOMConverter.cliTokens (P-CONVERT-TS-KEYWORDS), old spellings canonicalise, --frame-number from 1 with --frame deprecated (P-CONVERT-FRAME)")
    func convertTokensAndFrames() throws {
        let ts = try #require(pixelParam("dicom-convert", "transfer-syntax"))
        #expect(ts.allowedValues == [""] + DICOMConverter.cliTokens)
        #expect(ts.allowedValues.contains("JPEG2000Reversible") && ts.allowedValues.contains("ExplicitVRLittleEndian"))
        #expect(ts.helpText == DICOMConverter.transferSyntaxOptionHelpWithKeywords)
        #expect(WorkshopConvertPicker.canonicalToken("jpeg2000-lossless") == "JPEG2000Reversible")
        #expect(WorkshopConvertPicker.canonicalToken("1.2.840.10008.1.2.1") == "ExplicitVRLittleEndian")
        #expect(WorkshopConvertPicker.canonicalToken("JPEG2000Lossless") == "JPEG2000Lossless")   // reassigned: kept, the executor prints the note
        #expect(WorkshopConvertPicker.canonicalToken("bogus") == "bogus")
        #expect(DICOMConverter.resolveTargetEncoding("JPEGBaseline8Bit")?.transferSyntax.uid == "1.2.840.10008.1.2.4.50")
        #expect(DICOMConverter.resolveTargetEncoding("JPEG2000Lossless")?.transferSyntax.uid == "1.2.840.10008.1.2.4.90")
        #expect(TransferSyntax.reassignedKeywordNote(for: "JPEG2000Lossless") != nil)
        let fn = try #require(pixelParam("dicom-convert", "frame-number"))
        #expect(fn.minValue == 1 && fn.defaultValue.isEmpty && fn.helpText.contains("numbered from 1 (PS3.3 Table 10-3"))
        let fr = try #require(pixelParam("dicom-convert", "frame"))
        #expect(fr.helpText == "deprecated: 0-based index; use --frame-number" && fr.defaultValue.isEmpty)
        #expect(pixelParam("dicom-convert", "window-width")?.helpText == "Window width value (Window Width (0028,1051), at least 1)")
    }

    @Test("dicom-compress --syntax offers only the native targets of CompressionConsole.NativeTargetSyntax (D267) (P-COMPRESS-SYNTAX); codec names are refused with the CLI's text")
    func compressSyntaxPicker() throws {
        let p = try #require(pixelParam("dicom-compress", "syntax"))
        #expect(p.allowedValues == ["explicit-le", "implicit-le", "deflate", "explicit-be"])
        #expect(p.defaultValue == "explicit-le")
        #expect(try CompressionConsole.NativeTargetSyntax.resolve("deflate") == .deflatedExplicitVRLittleEndian)
        #expect(try CompressionConsole.NativeTargetSyntax.resolve("Explicit-BE") == .explicitVRBigEndian)
        do {
            _ = try CompressionConsole.NativeTargetSyntax.resolve("jpeg2000")
            Issue.record("jpeg2000 must be refused as a decompress target")
        } catch {
            #expect("\(error)".contains("an encapsulated (compressed) Transfer Syntax (PS3.6 2026a Table A-1)"))
            #expect("\(error)".contains("Native targets: explicit-le, implicit-le, deflate, explicit-be"))
        }
        do {
            _ = try CompressionConsole.NativeTargetSyntax.resolve("nope")
            Issue.record("unknown must be refused")
        } catch {
            #expect("\(error)" == "Unknown syntax 'nope'. Native targets: explicit-le, implicit-le, deflate, explicit-be")
        }
    }

    @Test("dicom-pixedit help texts are the CLI's; --fill-value carries no default (P-PIXEDIT-RANGE refusals in the executor)")
    func pixeditRows() throws {
        let fv = try #require(pixelParam("dicom-pixedit", "fill-value"))
        #expect(fv.defaultValue.isEmpty)
        #expect(fv.helpText.contains("Bits Stored (0028,0101) and Pixel Representation (0028,0103) (PS3.3 C.7.6.3.1), else exit 1"))
        #expect(pixelParam("dicom-pixedit", "window-width")?.helpText.contains("at least 1 (PS3.3 C.11.2.1.2), else exit 1") == true)
        #expect(pixelParam("dicom-pixedit", "crop")?.helpText.contains("Image Position (Patient) are updated") == true)
    }

    // MARK: - File tools mirror the dicom-* CLIs (DICOM 2026a; D29, D114, D127, D132, D154)

    private func fileToolParam(_ tool: String, _ id: String) -> CLIParameterDefinition? {
        ToolCatalogHelpers.parameterDefinitions(for: tool).first { $0.id == id }
    }

    @Test("dicom-dcmdir --profile offers only the PS3.11 2026a identifiers of DICOMDIRProfile.allStandard (D29)")
    func dcmdirProfilePickerIsPS311() {
        let p = fileToolParam("dicom-dcmdir", "profile")
        #expect(p?.allowedValues == DICOMDIRProfile.allStandard.map(\.rawValue))
        #expect(p?.defaultValue == "STD-GEN-CD")
        #expect(p?.allowedValues.contains("STD-GEN-DVD") == false)      // Annex H family heading, not an identifier
        #expect(p?.allowedValues.contains("STD-GEN-USB") == false)      // Annex J family heading
        #expect(p?.allowedValues.contains("STD-GEN-DVD-JPEG") == true)
    }

    @Test("dicom-dcmdir create: File-set ID rule (PS3.10 8.1, 8.5) in help, --copy-to offered")
    func dcmdirCreateForm() {
        #expect(fileToolParam("dicom-dcmdir", "fileSetID")?.helpText.contains("up to 16 characters A-Z, 0-9, _ (PS3.10 8.1, 8.5)") == true)
        let copyTo = fileToolParam("dicom-dcmdir", "copyTo")
        #expect(copyTo?.flag == "--copy-to")
        #expect(copyTo?.visibleWhen?.values == ["create"])
        #expect(fileToolParam("dicom-dcmdir", "checkFiles")?.helpText.contains("(0004,1500)") == true)
    }

    @Test("dicom-export selects frames by Frame number from 1 (PS3.3 Table 10-3); the 0-based options are deprecated (D127)")
    func exportFrameNumbers() {
        let fn = fileToolParam("dicom-export", "frame-number")
        #expect(fn?.flag == "--frame-number")
        #expect(fn?.minValue == 1)
        #expect(fn?.helpText.contains("numbered from 1") == true)
        #expect(fileToolParam("dicom-export", "frame")?.helpText == "deprecated: 0-based index; use --frame-number")
        #expect(fileToolParam("dicom-export", "frame")?.defaultValue.isEmpty == true)
        #expect(fileToolParam("dicom-export", "start-frame-number")?.minValue == 1)
        #expect(fileToolParam("dicom-export", "end-frame-number")?.minValue == 1)
        #expect(fileToolParam("dicom-export", "start-frame")?.defaultValue.isEmpty == true)   // a default would emit the deprecated option
        #expect(fileToolParam("dicom-export", "start-frame")?.helpText == "deprecated: 0-based index; use --start-frame-number")
        #expect(fileToolParam("dicom-export", "end-frame")?.helpText == "deprecated: 0-based index; use --end-frame-number")
    }

    @Test("dicom-export --fps has no fixed default: the file's Cine Module rate (PS3.3 Table C.7-13)")
    func exportFPSDefaultIsTheFileRate() {
        let fps = fileToolParam("dicom-export", "fps")
        #expect(fps?.defaultValue.isEmpty == true)
        for tag in ["Recommended Display Frame Rate (0008,2144)", "Cine Rate (0018,0040)", "Frame Time (0018,1063)"] {
            #expect(fps?.helpText.contains(tag) == true, Comment(rawValue: tag))
        }
    }

    @Test("dicom-export --apply-window is deprecated on contact-sheet and bulk only (P-EXPORT-3)")
    func exportApplyWindowDeprecation() {
        #expect(fileToolParam("dicom-export", "apply-window")?.visibleWhen?.values == ["single", "animate"])
        let dep = fileToolParam("dicom-export", "apply-window-deprecated")
        #expect(dep?.flag == "--apply-window")
        #expect(dep?.visibleWhen?.values == ["contact-sheet", "bulk"])
        #expect(dep?.helpText.hasPrefix("deprecated: no effect") == true)
    }

    @Test("dicom-export pickers are the shared ExportImageFormat / OrganizationScheme with the CLI's per-subcommand defaults")
    func exportPickers() {
        #expect(fileToolParam("dicom-export", "format")?.defaultValue == "jpeg")
        #expect(fileToolParam("dicom-export", "sheet-format")?.defaultValue == "png")
        #expect(fileToolParam("dicom-export", "bulk-format")?.defaultValue == "png")
        #expect(fileToolParam("dicom-export", "sheet-format")?.allowedValues == ExportImageFormat.allCases.map(\.rawValue))
        #expect(fileToolParam("dicom-export", "organize-by")?.allowedValues == OrganizationScheme.allCases.map(\.rawValue))
        #expect(fileToolParam("dicom-export", "organize-by")?.helpText.contains("Patient ID (0010,0020)") == true)
    }

    @Test("dicom-study defaults mirror the CLI: organize moves unless --copy; summary table, stats / compare text")
    func studyDefaults() {
        #expect(fileToolParam("dicom-study", "copy")?.defaultValue == "false")
        #expect(fileToolParam("dicom-study", "summary-format")?.defaultValue == "table")
        #expect(fileToolParam("dicom-study", "stats-format")?.defaultValue == "text")
        #expect(fileToolParam("dicom-study", "compare-format")?.defaultValue == "text")
        #expect(fileToolParam("dicom-study", "stats-format")?.helpText.contains("NumberOfStudyRelatedSeries") == true)
        #expect(fileToolParam("dicom-study", "expected-series")?.helpText.contains("(0020,1206)") == true)
    }

    @Test("dicom-archive query offers --strict-modality and the shared modality help (PS3.3 C.7.3.1.1.1)")
    func archiveQueryKeys() {
        let strict = fileToolParam("dicom-archive", "strict-modality")
        #expect(strict?.flag == "--strict-modality")
        #expect(strict?.visibleWhen?.values == ["query"])
        #expect(fileToolParam("dicom-archive", "modality")?.helpText.hasPrefix(ModalityOptionValidator.helpText("filter")) == true)
        #expect(fileToolParam("dicom-archive", "study-date")?.helpText.contains("C.2.2.2.5.1") == true)
        #expect(fileToolParam("dicom-archive", "patient-name")?.helpText.contains("(0010,0010)") == true)
    }

    @Test("dicom-json / dicom-xml keep empty attributes by default with --no-include-empty (PS3.18 F.2.5; D114)")
    func dataExchangeIncludeEmptyDefault() {
        for tool in ["dicom-json", "dicom-xml"] {
            let p = fileToolParam(tool, "include-empty")
            #expect(p?.defaultValue == "true", Comment(rawValue: tool))
            #expect(p?.negatedFlag == "--no-include-empty", Comment(rawValue: tool))
        }
        #expect(fileToolParam("dicom-json", "no-sort-keys")?.helpText.hasPrefix("Deprecated") == true)
        #expect(fileToolParam("dicom-xml", "no-keywords")?.helpText.hasPrefix("Deprecated") == true)
    }

    @Test("dicom-split --frame-numbers (from 1, PS3.3 C.7.6.16.1.2) and the deprecated 0-based --frames (D154)")
    func splitFrameSelectionHelp() {
        #expect(fileToolParam("dicom-split", "frame-numbers")?.helpText
                == "Frames to extract by Frame number, numbered from 1 (PS3.3 C.7.6.16.1.2), e.g. '1,3,5-10' (default: all)")
        #expect(fileToolParam("dicom-split", "frames")?.helpText == "deprecated: 0-based index; use --frame-numbers")
    }

    @Test("dicom-dump / dicom-tags / dicom-uid / dicom-merge forms mirror the CLI surface")
    func dumpTagsUIDMergeForms() {
        #expect(fileToolParam("dicom-dump", "no-color")?.defaultValue == "false")
        #expect(fileToolParam("dicom-tags", "inputPath")?.isRequired == false)              // --list-modalities needs no input
        #expect(fileToolParam("dicom-tags", "list-modalities")?.flag == "--list-modalities")
        #expect(fileToolParam("dicom-uid", "lookup-type")?.allowedValues == [""] + UIDConsole.lookupTypeFilters.map(\.value))
        #expect(fileToolParam("dicom-uid", "uuid")?.flag == "--uuid")
        #expect(fileToolParam("dicom-merge", "sort-by")?.defaultValue == MergeSortCriteria.instanceNumber.rawValue)
        #expect(fileToolParam("dicom-validate", "iod")?.helpText.contains("PS3.6 Table A-1") == true)
    }

    @Test("ValidationHelpers.knownIODs are PS3.6 2026a Table A-1 UID Keywords; level texts carry dicom-validate's --level help")
    func validationHelpersIODKeywordsAndLevels() {
        for keyword in ValidationHelpers.knownIODs {
            #expect(UIDDictionary.lookup(keyword: keyword) != nil, Comment(rawValue: keyword))
        }
        #expect(ValidationHelpers.knownIODs.contains("UltrasoundMultiFrameImageStorage"))           // was "…Multiframe…"
        #expect(ValidationHelpers.knownIODs.contains("MultiFrameTrueColorSecondaryCaptureImageStorage"))
        #expect(!ValidationHelpers.knownIODs.contains { $0.contains("Multiframe") })
        #expect(ValidationHelpers.levelDescription(1) == "1 — File Meta Information (PS3.10 Table 7.1-1)")
        #expect(ValidationHelpers.levelDescription(3) == "3 — IOD Type 1/1C/2/2C (PS3.3)")
        #expect(ValidationHelpers.levelDescription(5) == "5 — J2K codestream")
    }

    // MARK: - Network tools (workshop-net, DICOM 2026a)

    private func netParam(_ tool: String, _ id: String) -> CLIParameterDefinition? {
        ToolCatalogHelpers.parameterDefinitions(for: tool).first { $0.id == id }
    }

    @Test("dicom-query --level offers the PS3.4 2026a Table C.6.1-1 / C.6.2-1 values (patient, study, series, image), not 'instance'")
    func queryLevelPickerIsPS34() throws {
        let level = try #require(netParam("dicom-query", "level"))
        #expect(level.allowedValues == ["patient", "study", "series", "image"])
        #expect(level.defaultValue == "study")
        #expect(level.helpText.contains("Tables C.6.1-1 / C.6.2-1"))
        let parent = try #require(netParam("dicom-query", "include-parent-keys"))
        #expect(parent.visibleWhen?.values == ["series", "image"])
    }

    @Test("dicom-query --format offers dicom-json (PS3.18 F.2), --csv-keywords and --strict-modality are offered; --modality help is the shared text")
    func queryFormatAndModalityRows() throws {
        let format = try #require(netParam("dicom-query", "output-format"))
        #expect(format.allowedValues == ["table", "json", "csv", "compact", "dicom-json"])
        #expect(format.defaultValue == "table")
        let csvKeywords = try #require(netParam("dicom-query", "csv-keywords"))
        #expect(csvKeywords.flag == "--csv-keywords")
        #expect(csvKeywords.visibleWhen?.parameterId == "output-format")
        #expect(netParam("dicom-query", "strict-modality")?.flag == "--strict-modality")
        #expect(netParam("dicom-query", "modality")?.helpText == ModalityOptionValidator.helpText("filter"))
        // The presets are paste-runnable: the CLIs take the endpoint as a positional argument.
        for preset in EducationalHelpers.examplePresets(for: "dicom-query") + EducationalHelpers.examplePresets(for: "dicom-echo") {
            #expect(!preset.commandString.contains("--host"), Comment(rawValue: preset.commandString))
        }
    }

    @Test("dicom-send offers --transfer-syntax (PS3.8 7.1.1.13; DICOMCore.TransferSyntax tokens) and the PS3.7 Table 9.3-1 priority values")
    func sendTransferSyntaxAndPriorityRows() throws {
        let ts = try #require(netParam("dicom-send", "transfer-syntax"))
        #expect(ts.flag == "--transfer-syntax")
        #expect(ts.allowedValues == [""] + TransferSyntax.negotiableImageTokens)
        #expect(ts.defaultValue.isEmpty)                       // empty = send the file unchanged
        for token in TransferSyntax.negotiableImageTokens {
            #expect(TransferSyntax.parse(token) != nil, Comment(rawValue: token))   // the CLI's parser accepts every token
        }
        let priority = try #require(netParam("dicom-send", "priority"))
        #expect(priority.allowedValues == ["low", "medium", "high"])
        #expect(priority.defaultValue == "medium")
        #expect(priority.helpText.contains("PS3.7 Table 9.3-1"))
    }

    @Test("dicom-retrieve / dicom-qr offer --priority (PS3.7 Tables 9.3-9 / 9.3-6), --relational-retrieve (PS3.4 C.5.2.1), --strict-modality and --include-parent-keys")
    func retrieveAndQRRows() throws {
        for tool in ["dicom-retrieve", "dicom-qr"] {
            let priority = try #require(netParam(tool, "priority"), Comment(rawValue: tool))
            #expect(priority.allowedValues == ["low", "medium", "high"])
            #expect(priority.defaultValue == "medium")
            #expect(priority.helpText.contains("PS3.7 Tables 9.3-9 / 9.3-6"))
            let ts = try #require(netParam(tool, "transfer-syntax"))
            #expect(ts.allowedValues == [""] + TransferSyntax.negotiableImageTokens)
        }
        let relational = try #require(netParam("dicom-retrieve", "relational-retrieve"))
        #expect(relational.flag == "--relational-retrieve")
        #expect(relational.helpText.contains("PS3.4 C.5.2.1 / C.5.3.1, Table C.5-3 byte 1"))
        #expect(netParam("dicom-retrieve", "series-uid")?.helpText.contains("Query/Retrieve Level SERIES") == true)
        #expect(netParam("dicom-retrieve", "instance-uid")?.helpText.contains("Query/Retrieve Level IMAGE") == true)
        #expect(netParam("dicom-qr", "strict-modality")?.flag == "--strict-modality")
        #expect(netParam("dicom-qr", "include-parent-keys")?.flag == "--include-parent-keys")
        #expect(netParam("dicom-qr", "modality")?.helpText == ModalityOptionValidator.helpText("filter"))
    }

    @Test("dicom-mwl --sps-status offers the PS3.3 2026a Table C.4-10 Defined Terms; --specific-character-set and --strict-modality are offered")
    func mwlRows() throws {
        let sps = try #require(netParam("dicom-mwl", "sps-status"))
        #expect(sps.allowedValues == ["", "SCHEDULED", "ARRIVED", "READY", "STARTED", "DEPARTED"])
        #expect(!sps.allowedValues.contains("IN PROGRESS"))    // Performed Procedure Step Status words (Table C.4-14) never appear in a worklist
        #expect(sps.helpText.contains("PS3.3 Table C.4-10"))
        let charset = try #require(netParam("dicom-mwl", "specific-character-set"))
        #expect(charset.flag == "--specific-character-set")
        #expect(charset.visibleWhen?.values == ["query"])
        #expect(netParam("dicom-mwl", "strict-modality")?.visibleWhen?.values == ["query"])
        #expect(netParam("dicom-mwl", "modality")?.helpText == ModalityOptionValidator.helpText("filter"))
        let op = try #require(netParam("dicom-mwl", "operation"))
        #expect(op.allowedValues == ["query", "create"])        // create is Studio-only (P-STUDIO-MWL-CREATE)
    }

    @Test("dicom-mpps create requires --modality (PS3.4 Table F.7.2-1 Type 1); the discontinuation reason examples are PS3.16 CID 9301 pairs (D85)")
    func mppsRows() throws {
        let modality = try #require(netParam("dicom-mpps", "modality"))
        #expect(modality.isRequired)
        #expect(!modality.allowedValues.contains(""))
        #expect(modality.helpText.hasPrefix(ModalityOptionValidator.helpText("value")))
        #expect(netParam("dicom-mpps", "strict-modality")?.visibleWhen?.values == ["create"])
        let reason = try #require(netParam("dicom-mpps", "discontinuation-reason"))
        #expect(reason.placeholder == "110513|DCM|Discontinued for unspecified reason")
        #expect(!reason.helpText.contains("110518"))           // not a CID 9301 code
        #expect(!reason.helpText.contains("110514|DCM|Equipment failure"))   // 110514 is "Incorrect worklist entry selected"
        for pair in ["110513|DCM|Discontinued for unspecified reason", "110500|DCM|Doctor canceled procedure",
                     "110501|DCM|Equipment failure", "110507|DCM|Patient did not arrive"] {
            #expect(reason.helpText.contains(pair), Comment(rawValue: pair))
        }
        #expect(netParam("dicom-mpps", "patient-birth-date")?.helpText.contains("VR DA, PS3.5 Table 6.2-1") == true)
        #expect(netParam("dicom-mpps", "patient-sex")?.helpText.contains("PS3.3 Table C.2-3") == true)
    }

    @Test("dicom-qido offers --strict-modality, --fuzzy-matching (PS3.18 8.3.4.2) and --format dicom-json (PS3.18 F.2); --limit may be 0 (8.3.4.4)")
    func qidoRows() throws {
        #expect(netParam("dicom-qido", "strict-modality")?.flag == "--strict-modality")
        let fuzzy = try #require(netParam("dicom-qido", "fuzzy-matching"))
        #expect(fuzzy.flag == "--fuzzy-matching")
        #expect(fuzzy.helpText.contains("PS3.18 8.3.4.2"))
        #expect(netParam("dicom-qido", "output-format")?.allowedValues == ["table", "json", "csv", "dicom-json"])
        #expect(netParam("dicom-qido", "level")?.allowedValues == ["study", "series", "instance"])
        #expect(netParam("dicom-qido", "limit")?.minValue == 0)
        #expect(netParam("dicom-qido", "modality")?.helpText == ModalityOptionValidator.helpText("filter"))
    }

    @Test("dicom-wado retrieve offers the WADO-URI parameters of PS3.18 Tables 9.1.2-2 / 9.4.1-1 / 9.5.1-1, gated on --uri; --content-type is the shared Table 8.7.4-1 list; --format is the metadata json | xml")
    func wadoRetrieveRows() throws {
        let contentType = try #require(netParam("dicom-wado", "content-type"))
        #expect(contentType.flag == "--content-type")
        #expect(!contentType.isInternal)
        #expect(contentType.allowedValues == [""] + WADOURIClient.MediaType.allowed.map(\.rawValue))
        #expect(contentType.allowedValues.count == 16)                       // "" + application/dicom + 14 Rendered Media Types
        for id in ["content-type", "transfer-syntax", "anonymize", "rows", "columns", "charset", "annotation",
                   "image-quality", "region", "window-center", "window-width", "presentation-uid", "presentation-series-uid"] {
            let def = try #require(netParam("dicom-wado", id), Comment(rawValue: id))
            #expect(def.visibleWhen?.parameterId == "wado-protocol" && def.visibleWhen?.values == ["wado-uri"], Comment(rawValue: id))
            #expect(def.flag == "--" + id, Comment(rawValue: id))
        }
        #expect(netParam("dicom-wado", "rows")?.minValue == 1)
        let format = try #require(netParam("dicom-wado", "format"))
        #expect(format.allowedValues == ["json", "xml"] && format.defaultValue == "json")   // retrieve's MetadataFormat, not the query/ups result rendering
        #expect(netParam("dicom-wado", "wado-protocol")?.cliMapping["wado-uri"] == "--uri")
    }

    @Test("dicom-ups: --change-state with deprecated --update, --state offers only the PS3.18 11.7.1.4 targets, states spelled per PS3.3 Table C.30.1-1, priorities per Table C.30.2-1, --format csv / dicom-json")
    func upsRows() throws {
        let changeState = try #require(netParam("dicom-ups", "update-uid"))
        #expect(changeState.flag == "--change-state")
        let deprecated = try #require(netParam("dicom-ups", "update-uid-deprecated"))
        #expect(deprecated.flag == "--update" && deprecated.helpText.hasPrefix("Deprecated alias of --change-state"))
        let state = try #require(netParam("dicom-ups", "state"))
        #expect(state.allowedValues == ["IN PROGRESS", "COMPLETED", "CANCELED"])      // SCHEDULED is refused (PS3.4 Table CC.1.1-2, C303H)
        #expect(state.defaultValue == "IN PROGRESS")
        #expect(netParam("dicom-ups", "filter-state")?.allowedValues == ["", "SCHEDULED", "IN PROGRESS", "COMPLETED", "CANCELED"])
        #expect(netParam("dicom-ups", "create-priority")?.allowedValues == ["HIGH", "MEDIUM", "LOW"])
        #expect(netParam("dicom-ups", "create-patient-sex")?.allowedValues == ["", "M", "F", "O"])
        #expect(netParam("dicom-ups", "output-format")?.allowedValues == ["table", "json", "csv", "dicom-json"])
        let op = try #require(netParam("dicom-ups", "operation"))
        #expect(op.cliMapping == ["search": "--search", "create-workitem": "--create-workitem",
                                  "subscribe": "--subscribe", "unsubscribe": "--unsubscribe"])
    }
}
