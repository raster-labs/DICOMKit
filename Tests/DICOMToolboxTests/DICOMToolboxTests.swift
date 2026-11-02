import Foundation
import Testing
@testable import DICOMToolbox

@Suite("ToolCategory Tests")
struct ToolCategoryTests {
    @Test("All 6 categories are defined")
    func testAllCategoriesDefined() {
        #expect(ToolCategory.allCases.count == 6)
    }

    @Test("Category raw values are correct")
    func testCategoryRawValues() {
        #expect(ToolCategory.fileInspection.rawValue == "File Inspection")
        #expect(ToolCategory.fileProcessing.rawValue == "File Processing")
        #expect(ToolCategory.fileOrganization.rawValue == "File Organization")
        #expect(ToolCategory.dataExport.rawValue == "Data Export")
        #expect(ToolCategory.networkOperations.rawValue == "Network Operations")
        #expect(ToolCategory.automation.rawValue == "Automation")
    }

    @Test("Category icon names are SF Symbols")
    func testCategoryIcons() {
        #expect(ToolCategory.fileInspection.iconName == "doc.text.magnifyingglass")
        #expect(ToolCategory.fileProcessing.iconName == "gearshape.2")
        #expect(ToolCategory.fileOrganization.iconName == "folder.badge.gearshape")
        #expect(ToolCategory.dataExport.iconName == "square.and.arrow.up")
        #expect(ToolCategory.networkOperations.iconName == "network")
        #expect(ToolCategory.automation.iconName == "terminal")
    }

    @Test("Category identifiers are unique")
    func testCategoryIdentifiers() {
        let ids = ToolCategory.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

@Suite("NetworkConfig Tests")
struct NetworkConfigTests {
    @Test("Default configuration is valid")
    func testDefaultConfigIsValid() {
        let config = NetworkConfig()
        #expect(config.isValid)
    }

    @Test("AE Title validation - valid cases")
    func testAETitleValid() {
        #expect(NetworkConfig.validateAETitle("MYSCU"))
        #expect(NetworkConfig.validateAETitle("A"))
        #expect(NetworkConfig.validateAETitle("1234567890123456"))  // 16 chars max
        #expect(NetworkConfig.validateAETitle("MY_SCU-123"))
    }

    @Test("AE Title validation - empty is invalid")
    func testAETitleEmptyInvalid() {
        #expect(!NetworkConfig.validateAETitle(""))
    }

    @Test("AE Title validation - too long is invalid")
    func testAETitleTooLong() {
        #expect(!NetworkConfig.validateAETitle("12345678901234567"))  // 17 chars
    }

    @Test("AE Title validation - non-ASCII is invalid")
    func testAETitleNonASCII() {
        #expect(!NetworkConfig.validateAETitle("MÿSCU"))
        #expect(!NetworkConfig.validateAETitle("日本語"))
    }

    @Test("Port validation - valid range")
    func testPortValid() {
        #expect(NetworkConfig.validatePort(1))
        #expect(NetworkConfig.validatePort(11112))
        #expect(NetworkConfig.validatePort(65535))
    }

    @Test("Port validation - out of range")
    func testPortInvalid() {
        #expect(!NetworkConfig.validatePort(0))
        #expect(!NetworkConfig.validatePort(-1))
        #expect(!NetworkConfig.validatePort(65536))
    }

    @Test("Timeout validation - valid range")
    func testTimeoutValid() {
        #expect(NetworkConfig.validateTimeout(5))
        #expect(NetworkConfig.validateTimeout(60))
        #expect(NetworkConfig.validateTimeout(300))
    }

    @Test("Timeout validation - out of range")
    func testTimeoutInvalid() {
        #expect(!NetworkConfig.validateTimeout(4))
        #expect(!NetworkConfig.validateTimeout(301))
        #expect(!NetworkConfig.validateTimeout(0))
    }

    @Test("Server URL construction - DICOM protocol")
    func testServerURLDICOM() {
        let config = NetworkConfig(host: "pacs.hospital.org", port: 11112, protocolType: .dicom)
        #expect(config.serverURL == "pacs://pacs.hospital.org:11112")
    }

    @Test("Server URL construction - DICOMweb protocol")
    func testServerURLDICOMweb() {
        let config = NetworkConfig(host: "pacs.hospital.org", port: 443, protocolType: .dicomweb)
        #expect(config.serverURL == "https://pacs.hospital.org:443/dicom-web")
    }

    @Test("Config with empty host is invalid")
    func testEmptyHostInvalid() {
        let config = NetworkConfig(host: "")
        #expect(!config.isValid)
    }

    @Test("Config with invalid port is invalid")
    func testInvalidPortConfig() {
        let config = NetworkConfig(port: 0)
        #expect(!config.isValid)
    }

    @Test("Config with invalid timeout is invalid")
    func testInvalidTimeoutConfig() {
        let config = NetworkConfig(timeout: 0)
        #expect(!config.isValid)
    }
}

@Suite("ValidationRule Tests")
struct ValidationRuleTests {
    @Test("Max length validation")
    func testMaxLength() {
        let rule = ValidationRule(maxLength: 5)
        #expect(rule.validate("hello"))
        #expect(rule.validate("hi"))
        #expect(!rule.validate("hello!"))
    }

    @Test("ASCII-only validation")
    func testASCIIOnly() {
        let rule = ValidationRule(asciiOnly: true)
        #expect(rule.validate("hello"))
        #expect(rule.validate("123"))
        #expect(!rule.validate("héllo"))
    }

    @Test("Min/max value validation")
    func testMinMaxValue() {
        let rule = ValidationRule(minValue: 1, maxValue: 100)
        #expect(rule.validate("1"))
        #expect(rule.validate("50"))
        #expect(rule.validate("100"))
        #expect(!rule.validate("0"))
        #expect(!rule.validate("101"))
    }

    @Test("Pattern validation")
    func testPatternValidation() {
        let rule = ValidationRule(pattern: "^\\d{4}$")
        #expect(rule.validate("1234"))
        #expect(!rule.validate("12345"))
        #expect(!rule.validate("abcd"))
    }

    @Test("Combined validation rules")
    func testCombinedRules() {
        let rule = ValidationRule(maxLength: 16, asciiOnly: true)
        #expect(rule.validate("MYSCU"))
        #expect(!rule.validate("12345678901234567"))  // Too long
        #expect(!rule.validate("MÿSCU"))  // Non-ASCII
    }

    @Test("Empty string passes length and ASCII checks")
    func testEmptyString() {
        let rule = ValidationRule(maxLength: 5, asciiOnly: true)
        #expect(rule.validate(""))
    }

    @Test("Non-numeric value fails min/max validation")
    func testNonNumericMinMax() {
        let rule = ValidationRule(minValue: 1, maxValue: 100)
        // Non-numeric strings should fail when min/max rules are present
        #expect(!rule.validate("abc"))
    }
}

@Suite("ToolRegistry Tests")
struct ToolRegistryTests {
    @Test("All 30 tools are registered")
    func testAllToolsCount() {
        #expect(ToolRegistry.allTools.count == 30)
    }

    @Test("All tool IDs are unique")
    func testUniqueToolIDs() {
        let ids = ToolRegistry.allTools.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("File Inspection category has 4 tools")
    func testFileInspectionCount() {
        let tools = ToolRegistry.tools(for: .fileInspection)
        #expect(tools.count == 4)
    }

    @Test("File Processing category has 4 tools")
    func testFileProcessingCount() {
        let tools = ToolRegistry.tools(for: .fileProcessing)
        #expect(tools.count == 4)
    }

    @Test("File Organization category has 4 tools")
    func testFileOrganizationCount() {
        let tools = ToolRegistry.tools(for: .fileOrganization)
        #expect(tools.count == 4)
    }

    @Test("Data Export category has 7 tools")
    func testDataExportCount() {
        let tools = ToolRegistry.tools(for: .dataExport)
        #expect(tools.count == 7)
    }

    @Test("Network Operations category has 8 tools")
    func testNetworkOpsCount() {
        let tools = ToolRegistry.tools(for: .networkOperations)
        #expect(tools.count == 8)
    }

    @Test("Automation category has 3 tools")
    func testAutomationCount() {
        let tools = ToolRegistry.tools(for: .automation)
        #expect(tools.count == 3)
    }

    @Test("Tool lookup by ID works")
    func testToolLookup() {
        let tool = ToolRegistry.tool(withID: "dicom-info")
        #expect(tool != nil)
        #expect(tool?.name == "DICOM Info")
    }

    @Test("Tool lookup returns nil for unknown ID")
    func testToolLookupUnknown() {
        let tool = ToolRegistry.tool(withID: "nonexistent")
        #expect(tool == nil)
    }

    @Test("Network tools have requiresNetwork set")
    func testNetworkToolsFlag() {
        let networkTools = ToolRegistry.tools(for: .networkOperations)
        for tool in networkTools {
            #expect(tool.requiresNetwork, "Tool \(tool.id) should require network")
        }
    }

    @Test("Non-network tools don't require network")
    func testNonNetworkToolsFlag() {
        let fileTools = ToolRegistry.tools(for: .fileInspection)
        for tool in fileTools {
            #expect(!tool.requiresNetwork, "Tool \(tool.id) should not require network")
        }
    }

    @Test("Tools with subcommands have them defined")
    func testSubcommandTools() {
        let compressTool = ToolRegistry.tool(withID: "dicom-compress")
        #expect(compressTool?.subcommands != nil)
        #expect(compressTool?.subcommands?.count == 4)

        let exportTool = ToolRegistry.tool(withID: "dicom-export")
        #expect(exportTool?.subcommands != nil)
        #expect(exportTool?.subcommands?.count == 2)
    }

    @Test("dicom-info has correct parameters")
    func testDicomInfoParameters() {
        let tool = ToolRegistry.dicomInfo
        #expect(tool.parameters.count == 6)
        let required = tool.parameters.filter(\.isRequired)
        #expect(required.count == 1)
        #expect(required.first?.id == "filePath")
    }
}

@Suite("CommandBuilder Tests")
struct CommandBuilderTests {
    @Test("Basic command string for dicom-info")
    func testBasicCommandInfo() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        let command = builder.buildCommand(values: ["filePath": "scan.dcm"])
        #expect(command == "dicom-info scan.dcm")
    }

    @Test("Command with format option")
    func testCommandWithFormat() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        let command = builder.buildCommand(values: [
            "filePath": "scan.dcm",
            "format": "json",
        ])
        #expect(command.contains("dicom-info"))
        #expect(command.contains("--format json"))
        #expect(command.contains("scan.dcm"))
    }

    @Test("Command with boolean flag")
    func testCommandWithFlag() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        let command = builder.buildCommand(values: [
            "filePath": "scan.dcm",
            "statistics": "true",
        ])
        #expect(command.contains("--statistics"))
    }

    @Test("Boolean flag excluded when false")
    func testCommandBoolFalse() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        let command = builder.buildCommand(values: [
            "filePath": "scan.dcm",
            "statistics": "",
        ])
        #expect(!command.contains("--statistics"))
    }

    @Test("Command with multiple parameters")
    func testCommandMultipleParams() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        let command = builder.buildCommand(values: [
            "filePath": "scan.dcm",
            "format": "json",
            "statistics": "true",
            "show-private": "true",
        ])
        #expect(command.contains("dicom-info"))
        #expect(command.contains("scan.dcm"))
        #expect(command.contains("--format json"))
        #expect(command.contains("--statistics"))
        #expect(command.contains("--show-private"))
    }

    @Test("Command with repeatable option")
    func testCommandRepeatable() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        let command = builder.buildCommand(values: [
            "filePath": "scan.dcm",
            "tag": "PatientName, PatientID",
        ])
        #expect(command.contains("--tag PatientName"))
        #expect(command.contains("--tag PatientID"))
    }

    @Test("Command with subcommand")
    func testCommandSubcommand() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomCompress)
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
            "codec": "jpeg",
        ], subcommand: "compress")
        #expect(command.contains("dicom-compress compress"))
        #expect(command.contains("scan.dcm"))
        #expect(command.contains("--codec jpeg"))
    }

    @Test("Command with network config")
    func testCommandWithNetworkConfig() {
        let config = NetworkConfig(aeTitle: "MYSCU", calledAET: "PACS01", host: "pacs.local", port: 11112)
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: config)
        let command = builder.buildCommand(values: [
            "count": "3",
        ])
        #expect(command.contains("dicom-echo"))
        #expect(command.contains("pacs://pacs.local:11112"))
        #expect(command.contains("--aet MYSCU"))
        #expect(command.contains("--called-aet PACS01"))
        #expect(command.contains("--count 3"))
    }

    @Test("Network config overridden by local values")
    func testNetworkConfigOverride() {
        let config = NetworkConfig(aeTitle: "MYSCU")
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: config)
        let command = builder.buildCommand(values: [
            "aet": "OVERRIDE",
        ])
        #expect(command.contains("--aet OVERRIDE"))
    }

    @Test("Validation - all required params present")
    func testValidationAllPresent() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        #expect(builder.isValid(values: ["filePath": "scan.dcm"]))
    }

    @Test("Validation - missing required param")
    func testValidationMissing() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        #expect(!builder.isValid(values: [:]))
    }

    @Test("Validation - empty required param")
    func testValidationEmpty() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        #expect(!builder.isValid(values: ["filePath": ""]))
    }

    @Test("Validation - with subcommand required params")
    func testValidationSubcommand() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomCompress)
        #expect(builder.isValid(values: ["input": "scan.dcm"], subcommand: "compress"))
        #expect(!builder.isValid(values: [:], subcommand: "compress"))
    }

    @Test("Missing required parameters returns labels")
    func testMissingParams() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomDiff)
        let missing = builder.missingRequiredParameters(values: ["file1": "a.dcm"])
        #expect(missing.contains("File 2"))
        #expect(!missing.contains("File 1"))
    }

    @Test("No missing params when all provided")
    func testNoMissingParams() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomDiff)
        let missing = builder.missingRequiredParameters(values: ["file1": "a.dcm", "file2": "b.dcm"])
        #expect(missing.isEmpty)
    }

    @Test("Parameter validation with rule")
    func testParameterValidation() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomConvert)
        #expect(builder.validateParameter("quality", value: "85"))
        #expect(builder.validateParameter("quality", value: "1"))
        #expect(builder.validateParameter("quality", value: "100"))
        #expect(!builder.validateParameter("quality", value: "0"))
        #expect(!builder.validateParameter("quality", value: "101"))
    }

    @Test("Parameter validation for unknown param returns true")
    func testParameterValidationUnknown() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        #expect(builder.validateParameter("nonexistent", value: "anything"))
    }

    @Test("Execute button disabled when invalid")
    func testExecuteButtonState() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        #expect(!builder.isValid(values: [:]))
        #expect(builder.isValid(values: ["filePath": "test.dcm"]))
    }

    @Test("Command for tool with two required files (dicom-diff)")
    func testDiffCommandTwoFiles() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomDiff)
        let command = builder.buildCommand(values: [
            "file1": "scan1.dcm",
            "file2": "scan2.dcm",
            "ignore-private": "true",
        ])
        #expect(command.contains("dicom-diff"))
        #expect(command.contains("scan1.dcm"))
        #expect(command.contains("scan2.dcm"))
        #expect(command.contains("--ignore-private"))
    }

    @Test("Empty values are not included in command")
    func testEmptyValuesExcluded() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        let command = builder.buildCommand(values: [
            "filePath": "scan.dcm",
            "format": "",
            "tag": "",
        ])
        #expect(!command.contains("--format"))
        #expect(!command.contains("--tag"))
    }
}

@Suite("ServerProfile Tests")
struct ServerProfileTests {
    @Test("Profile creates valid NetworkConfig")
    func testProfileToConfig() {
        let profile = ServerProfile(
            name: "Hospital PACS",
            aeTitle: "MYPACS",
            calledAET: "PACS01",
            host: "pacs.hospital.org",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
        let config = profile.toNetworkConfig()
        #expect(config.aeTitle == "MYPACS")
        #expect(config.calledAET == "PACS01")
        #expect(config.host == "pacs.hospital.org")
        #expect(config.port == 11112)
        #expect(config.timeout == 60)
        #expect(config.isValid)
    }

    @Test("Profile with defaults creates valid config")
    func testProfileDefaults() {
        let profile = ServerProfile(name: "Default")
        let config = profile.toNetworkConfig()
        #expect(config.isValid)
        #expect(config.aeTitle == "DICOMTOOLBOX")
        #expect(config.calledAET == "ANY-SCP")
    }

    @Test("Profile is Codable")
    func testProfileCodable() throws {
        let profile = ServerProfile(
            name: "Test",
            aeTitle: "TESTSCU",
            host: "localhost",
            port: 4242
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ServerProfile.self, from: data)
        #expect(decoded.name == "Test")
        #expect(decoded.aeTitle == "TESTSCU")
        #expect(decoded.host == "localhost")
        #expect(decoded.port == 4242)
    }

    @Test("Profile IDs are unique")
    func testProfileUniqueIDs() {
        let p1 = ServerProfile(name: "One")
        let p2 = ServerProfile(name: "Two")
        #expect(p1.id != p2.id)
    }
}

@Suite("ParameterDefinition Tests")
struct ParameterDefinitionTests {
    @Test("Parameter with enum values")
    func testEnumParameter() {
        let param = ParameterDefinition(
            id: "format",
            cliFlag: "--format",
            label: "Format",
            help: "Output format",
            type: .enumeration,
            enumValues: [
                EnumValue(label: "Text", value: "text"),
                EnumValue(label: "JSON", value: "json"),
            ]
        )
        #expect(param.enumValues?.count == 2)
        #expect(param.type == .enumeration)
    }

    @Test("Required parameter flag")
    func testRequiredParameter() {
        let param = ParameterDefinition(
            id: "input",
            cliFlag: "@argument",
            label: "Input",
            help: "Input file",
            type: .file,
            isRequired: true
        )
        #expect(param.isRequired)
    }

    @Test("Optional parameter flag")
    func testOptionalParameter() {
        let param = ParameterDefinition(
            id: "verbose",
            cliFlag: "--verbose",
            label: "Verbose",
            help: "Verbose output",
            type: .boolean
        )
        #expect(!param.isRequired)
    }
}

@Suite("ProtocolType Tests")
struct ProtocolTypeTests {
    @Test("Protocol types have correct raw values")
    func testRawValues() {
        #expect(ProtocolType.dicom.rawValue == "DICOM")
        #expect(ProtocolType.dicomweb.rawValue == "DICOMweb")
    }

    @Test("All protocol types are enumerated")
    func testAllCases() {
        #expect(ProtocolType.allCases.count == 2)
    }
}

@Suite("ToolDefinition Tests")
struct ToolDefinitionTests {
    @Test("Tool with subcommands")
    func testToolSubcommands() {
        let tool = ToolRegistry.dicomCompress
        #expect(tool.subcommands?.count == 4)
        let subIDs = tool.subcommands?.map(\.id) ?? []
        #expect(subIDs.contains("compress"))
        #expect(subIDs.contains("decompress"))
        #expect(subIDs.contains("info"))
        #expect(subIDs.contains("batch"))
    }

    @Test("Tool without subcommands has nil")
    func testToolNoSubcommands() {
        let tool = ToolRegistry.dicomInfo
        #expect(tool.subcommands == nil)
    }

    @Test("Subcommand has own parameters")
    func testSubcommandParameters() {
        let tool = ToolRegistry.dicomCompress
        let compressSub = tool.subcommands?.first { $0.id == "compress" }
        #expect(compressSub != nil)
        let paramIDs = compressSub?.parameters.map(\.id) ?? []
        #expect(paramIDs.contains("input"))
        #expect(paramIDs.contains("codec"))
        #expect(paramIDs.contains("quality"))
    }
}

@Suite("DicomReport ToolRegistry Tests")
struct DicomReportToolRegistryTests {
    @Test("dicom-report tool is registered")
    func testReportToolRegistered() {
        let tool = ToolRegistry.tool(withID: "dicom-report")
        #expect(tool != nil)
        #expect(tool?.name == "DICOM Report")
    }

    @Test("dicom-report is in Data Export category")
    func testReportCategory() {
        let tool = ToolRegistry.dicomReport
        #expect(tool.category == .dataExport)
    }

    @Test("dicom-report has correct parameters")
    func testReportParameters() {
        let tool = ToolRegistry.dicomReport
        #expect(tool.parameters.count == 14)
        let required = tool.parameters.filter(\.isRequired)
        #expect(required.count == 2)
        let requiredIDs = required.map(\.id)
        #expect(requiredIDs.contains("filePath"))
        #expect(requiredIDs.contains("output"))
    }

    @Test("dicom-report format parameter has 5 options")
    func testReportFormatOptions() {
        let tool = ToolRegistry.dicomReport
        let formatParam = tool.parameters.first { $0.id == "format" }
        #expect(formatParam != nil)
        #expect(formatParam?.enumValues?.count == 5)
        let values = formatParam?.enumValues?.map(\.value) ?? []
        #expect(values.contains("text"))
        #expect(values.contains("html"))
        #expect(values.contains("json"))
        #expect(values.contains("markdown"))
        #expect(values.contains("pdf"))
    }

    @Test("dicom-report template parameter has 4 options")
    func testReportTemplateOptions() {
        let tool = ToolRegistry.dicomReport
        let templateParam = tool.parameters.first { $0.id == "template" }
        #expect(templateParam != nil)
        #expect(templateParam?.enumValues?.count == 4)
        let values = templateParam?.enumValues?.map(\.value) ?? []
        #expect(values.contains("default"))
        #expect(values.contains("cardiology"))
        #expect(values.contains("radiology"))
        #expect(values.contains("oncology"))
    }

    @Test("dicom-report language parameter has 4 options")
    func testReportLanguageOptions() {
        let tool = ToolRegistry.dicomReport
        let langParam = tool.parameters.first { $0.id == "language" }
        #expect(langParam != nil)
        #expect(langParam?.enumValues?.count == 4)
        let values = langParam?.enumValues?.map(\.value) ?? []
        #expect(values.contains("en"))
        #expect(values.contains("es"))
        #expect(values.contains("fr"))
        #expect(values.contains("de"))
    }

    @Test("dicom-report has branding parameters")
    func testReportBrandingParams() {
        let tool = ToolRegistry.dicomReport
        let paramIDs = tool.parameters.map(\.id)
        #expect(paramIDs.contains("title"))
        #expect(paramIDs.contains("logo"))
        #expect(paramIDs.contains("footer"))
    }

    @Test("dicom-report has image embedding parameters")
    func testReportImageParams() {
        let tool = ToolRegistry.dicomReport
        let paramIDs = tool.parameters.map(\.id)
        #expect(paramIDs.contains("embed-images"))
        #expect(paramIDs.contains("image-dir"))
    }

    @Test("dicom-report requires output")
    func testReportRequiresOutput() {
        let tool = ToolRegistry.dicomReport
        #expect(tool.requiresOutput)
    }

    @Test("dicom-report does not require network")
    func testReportNoNetwork() {
        let tool = ToolRegistry.dicomReport
        #expect(!tool.requiresNetwork)
    }

    @Test("dicom-report has no subcommands")
    func testReportNoSubcommands() {
        let tool = ToolRegistry.dicomReport
        #expect(tool.subcommands == nil)
    }

    @Test("dicom-report command builder works")
    func testReportCommandBuilder() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomReport)
        let command = builder.buildCommand(values: [
            "filePath": "sr.dcm",
            "output": "report.html",
            "format": "html",
            "template": "cardiology",
            "language": "es",
        ])
        #expect(command.contains("dicom-report"))
        #expect(command.contains("sr.dcm"))
        #expect(command.contains("--output report.html"))
        #expect(command.contains("--format html"))
        #expect(command.contains("--template cardiology"))
        #expect(command.contains("--language es"))
    }

    @Test("dicom-report command with branding options")
    func testReportCommandBranding() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomReport)
        let command = builder.buildCommand(values: [
            "filePath": "sr.dcm",
            "output": "report.html",
            "title": "Custom Title",
            "logo": "logo.png",
            "footer": "Confidential",
            "embed-images": "true",
        ])
        #expect(command.contains("--title 'Custom Title'"))
        #expect(command.contains("--logo logo.png"))
        #expect(command.contains("--footer Confidential"))
        #expect(command.contains("--embed-images"))
    }

    @Test("dicom-report validation requires input and output")
    func testReportValidation() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomReport)
        #expect(!builder.isValid(values: [:]))
        #expect(!builder.isValid(values: ["filePath": "sr.dcm"]))
        #expect(!builder.isValid(values: ["output": "report.txt"]))
        #expect(builder.isValid(values: ["filePath": "sr.dcm", "output": "report.txt"]))
    }

    @Test("dicom-report example presets exist")
    func testReportExamplePresets() {
        let presets = ExamplePresets.presets(for: "dicom-report")
        #expect(presets.count == 5)
    }
}
