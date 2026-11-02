import Foundation
import Testing
@testable import DICOMToolbox

// MARK: - dicom-convert Command Generation Tests

@Suite("DicomConvert Command Generation Tests")
struct DicomConvertCommandTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomConvert)
    }

    @Test("Basic dicom-convert command with required parameters")
    func testBasicCommand() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "output": "output.dcm",
        ])
        #expect(command.contains("dicom-convert"))
        #expect(command.contains("scan.dcm"))
        #expect(command.contains("--output output.dcm"))
    }

    @Test("dicom-convert with transfer syntax")
    func testWithTransferSyntax() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "output": "output.dcm",
            "transfer-syntax": "explicit-vr-le",
        ])
        #expect(command.contains("--transfer-syntax explicit-vr-le"))
    }

    @Test("dicom-convert with implicit VR transfer syntax")
    func testWithImplicitVR() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "output": "output.dcm",
            "transfer-syntax": "implicit-vr-le",
        ])
        #expect(command.contains("--transfer-syntax implicit-vr-le"))
    }

    @Test("dicom-convert with output format")
    func testWithFormat() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "output": "output.png",
            "format": "png",
        ])
        #expect(command.contains("--format png"))
    }

    @Test("dicom-convert with JPEG quality")
    func testWithQuality() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "output": "output.jpg",
            "format": "jpeg",
            "quality": "90",
        ])
        #expect(command.contains("--format jpeg"))
        #expect(command.contains("--quality 90"))
    }

    @Test("dicom-convert with windowing parameters")
    func testWithWindowing() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "output": "output.png",
            "window-center": "40",
            "window-width": "400",
            "apply-window": "true",
        ])
        #expect(command.contains("--window-center 40"))
        #expect(command.contains("--window-width 400"))
        #expect(command.contains("--apply-window"))
    }

    @Test("dicom-convert with frame number")
    func testWithFrame() {
        let command = builder.buildCommand(values: [
            "inputPath": "multi.dcm",
            "output": "frame.png",
            "frame": "5",
        ])
        #expect(command.contains("--frame 5"))
    }

    @Test("dicom-convert with boolean flags")
    func testWithFlags() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "output": "output.dcm",
            "strip-private": "true",
            "validate": "true",
            "recursive": "true",
            "force": "true",
        ])
        #expect(command.contains("--strip-private"))
        #expect(command.contains("--validate"))
        #expect(command.contains("--recursive"))
        #expect(command.contains("--force"))
    }

    @Test("dicom-convert with all parameters")
    func testWithAllParameters() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "output": "output.jpg",
            "transfer-syntax": "explicit-vr-le",
            "format": "jpeg",
            "quality": "85",
            "window-center": "40",
            "window-width": "400",
            "frame": "0",
            "apply-window": "true",
            "strip-private": "true",
            "validate": "true",
            "recursive": "true",
            "force": "true",
        ])
        #expect(command.contains("dicom-convert"))
        #expect(command.contains("scan.dcm"))
        #expect(command.contains("--output output.jpg"))
        #expect(command.contains("--transfer-syntax explicit-vr-le"))
        #expect(command.contains("--format jpeg"))
        #expect(command.contains("--quality 85"))
        #expect(command.contains("--window-center 40"))
        #expect(command.contains("--window-width 400"))
        #expect(command.contains("--frame 0"))
        #expect(command.contains("--apply-window"))
        #expect(command.contains("--strip-private"))
        #expect(command.contains("--validate"))
        #expect(command.contains("--recursive"))
        #expect(command.contains("--force"))
    }

    @Test("dicom-convert empty optional values excluded")
    func testEmptyValuesExcluded() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "output": "output.dcm",
            "transfer-syntax": "",
            "quality": "",
            "strip-private": "",
        ])
        #expect(!command.contains("--transfer-syntax"))
        #expect(!command.contains("--quality"))
        #expect(!command.contains("--strip-private"))
    }
}

// MARK: - Transfer Syntax Picker Tests

@Suite("Transfer Syntax Picker Tests")
struct TransferSyntaxPickerTests {
    @Test("dicom-convert has 4 transfer syntax options")
    func testTransferSyntaxCount() {
        let tool = ToolRegistry.dicomConvert
        let syntaxParam = tool.parameters.first { $0.id == "transfer-syntax" }
        #expect(syntaxParam != nil)
        #expect(syntaxParam?.enumValues?.count == 4)
    }

    @Test("Transfer syntax options include all standard syntaxes")
    func testTransferSyntaxValues() {
        let tool = ToolRegistry.dicomConvert
        let syntaxParam = tool.parameters.first { $0.id == "transfer-syntax" }
        let values = syntaxParam?.enumValues?.map(\.value) ?? []
        #expect(values.contains("explicit-vr-le"))
        #expect(values.contains("implicit-vr-le"))
        #expect(values.contains("explicit-vr-be"))
        #expect(values.contains("deflate"))
    }

    @Test("Transfer syntax options have descriptions")
    func testTransferSyntaxDescriptions() {
        let tool = ToolRegistry.dicomConvert
        let syntaxParam = tool.parameters.first { $0.id == "transfer-syntax" }
        if let enumValues = syntaxParam?.enumValues {
            for ev in enumValues {
                #expect(!ev.description.isEmpty, "Transfer syntax \(ev.value) should have a description")
            }
        }
    }

    @Test("Output format has 4 options")
    func testOutputFormatCount() {
        let tool = ToolRegistry.dicomConvert
        let formatParam = tool.parameters.first { $0.id == "format" }
        #expect(formatParam?.enumValues?.count == 4)
        let values = formatParam?.enumValues?.map(\.value) ?? []
        #expect(values.contains("dicom"))
        #expect(values.contains("png"))
        #expect(values.contains("jpeg"))
        #expect(values.contains("tiff"))
    }
}

// MARK: - dicom-validate Command Generation Tests

@Suite("DicomValidate Command Generation Tests")
struct DicomValidateCommandTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomValidate)
    }

    @Test("Basic dicom-validate command")
    func testBasicCommand() {
        let command = builder.buildCommand(values: ["inputPath": "scan.dcm"])
        #expect(command.contains("dicom-validate"))
        #expect(command.contains("scan.dcm"))
    }

    @Test("dicom-validate with validation level")
    func testWithLevel() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "level": "3",
        ])
        #expect(command.contains("--level 3"))
    }

    @Test("dicom-validate with output format")
    func testWithFormat() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "format": "json",
        ])
        #expect(command.contains("--format json"))
    }

    @Test("dicom-validate with output file")
    func testWithOutputFile() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "output": "report.json",
            "format": "json",
        ])
        #expect(command.contains("--output report.json"))
        #expect(command.contains("--format json"))
    }

    @Test("dicom-validate with all boolean flags")
    func testWithAllFlags() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "detailed": "true",
            "recursive": "true",
            "strict": "true",
            "force": "true",
        ])
        #expect(command.contains("--detailed"))
        #expect(command.contains("--recursive"))
        #expect(command.contains("--strict"))
        #expect(command.contains("--force"))
    }

    @Test("dicom-validate with all parameters")
    func testWithAllParameters() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "level": "4",
            "format": "json",
            "output": "report.json",
            "detailed": "true",
            "recursive": "true",
            "strict": "true",
            "force": "true",
        ])
        #expect(command.contains("dicom-validate"))
        #expect(command.contains("scan.dcm"))
        #expect(command.contains("--level 4"))
        #expect(command.contains("--format json"))
        #expect(command.contains("--output report.json"))
        #expect(command.contains("--detailed"))
        #expect(command.contains("--recursive"))
        #expect(command.contains("--strict"))
        #expect(command.contains("--force"))
    }
}

// MARK: - Validation Level Description Tests

@Suite("Validation Level Description Tests")
struct ValidationLevelTests {
    @Test("dicom-validate has 4 validation levels")
    func testLevelCount() {
        let tool = ToolRegistry.dicomValidate
        let levelParam = tool.parameters.first { $0.id == "level" }
        #expect(levelParam != nil)
        #expect(levelParam?.enumValues?.count == 4)
    }

    @Test("Each validation level has a description")
    func testLevelDescriptions() {
        let tool = ToolRegistry.dicomValidate
        let levelParam = tool.parameters.first { $0.id == "level" }
        if let enumValues = levelParam?.enumValues {
            for ev in enumValues {
                #expect(!ev.description.isEmpty, "Level \(ev.value) should have a description")
            }
        }
    }

    @Test("Validation levels have correct values")
    func testLevelValues() {
        let tool = ToolRegistry.dicomValidate
        let levelParam = tool.parameters.first { $0.id == "level" }
        let values = levelParam?.enumValues?.map(\.value) ?? []
        #expect(values == ["1", "2", "3", "4"])
    }

    @Test("Default validation level is 1")
    func testDefaultLevel() {
        let tool = ToolRegistry.dicomValidate
        let levelParam = tool.parameters.first { $0.id == "level" }
        #expect(levelParam?.defaultValue == "1")
    }
}

// MARK: - dicom-anon Command Generation Tests

@Suite("DicomAnon Command Generation Tests")
struct DicomAnonCommandTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomAnon)
    }

    @Test("Basic dicom-anon command")
    func testBasicCommand() {
        let command = builder.buildCommand(values: ["inputPath": "scan.dcm"])
        #expect(command.contains("dicom-anon"))
        #expect(command.contains("scan.dcm"))
    }

    @Test("dicom-anon with output path")
    func testWithOutput() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "output": "anon_scan.dcm",
        ])
        #expect(command.contains("--output anon_scan.dcm"))
    }

    @Test("dicom-anon with profile")
    func testWithProfile() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "profile": "ps315",
        ])
        #expect(command.contains("--profile ps315"))
    }

    @Test("dicom-anon with date shift")
    func testWithDateShift() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "shift-dates": "30",
        ])
        #expect(command.contains("--shift-dates 30"))
    }

    @Test("dicom-anon with retain UIDs")
    func testWithRetainUIDs() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "retain-uids": "true",
        ])
        #expect(command.contains("--retain-uids"))
    }

    @Test("dicom-anon with custom tag actions")
    func testWithTagActions() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "remove": "0010,0010,0010,0020",
            "replace": "0008,0080=HOSPITAL",
        ])
        #expect(command.contains("--remove 0010,0010"))
        #expect(command.contains("--remove 0010,0020"))
        #expect(command.contains("--replace 0008,0080=HOSPITAL"))
        #expect(!command.contains("--keep"))
    }

    @Test("dicom-anon with all boolean flags")
    func testWithFlags() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "recursive": "true",
            "dry-run": "true",
            "backup": "true",
        ])
        #expect(command.contains("--recursive"))
        #expect(command.contains("--dry-run"))
        #expect(command.contains("--backup"))
    }

    @Test("dicom-anon with audit log")
    func testWithAuditLog() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "audit-log": "audit.log",
        ])
        #expect(command.contains("--audit-log audit.log"))
    }

    @Test("dicom-anon with all parameters")
    func testWithAllParameters() {
        let command = builder.buildCommand(values: [
            "inputPath": "scan.dcm",
            "output": "anon/",
            "profile": "ps315",
            "shift-dates": "90",
            "retain-uids": "true",
            "remove": "0010,0030",
            "replace": "0010,0010=ANONYMOUS",
            "recursive": "true",
            "dry-run": "true",
            "backup": "true",
            "audit-log": "audit.csv",
        ])
        #expect(command.contains("dicom-anon"))
        #expect(command.contains("scan.dcm"))
        #expect(command.contains("--output anon/"))
        #expect(command.contains("--profile ps315"))
        #expect(command.contains("--shift-dates 90"))
        #expect(command.contains("--retain-uids"))
        #expect(command.contains("--remove 0010,0030"))
        #expect(command.contains("--replace 0010,0010=ANONYMOUS"))
        #expect(!command.contains("--keep"))
        #expect(command.contains("--recursive"))
        #expect(command.contains("--dry-run"))
        #expect(command.contains("--backup"))
        #expect(command.contains("--audit-log audit.csv"))
    }
}

// MARK: - dicom-anon Profile Tests

@Suite("DicomAnon Profile Tests")
struct DicomAnonProfileTests {
    @Test("dicom-anon offers the two current CLI profile tokens")
    func testProfileCount() {
        let tool = ToolRegistry.dicomAnon
        let profileParam = tool.parameters.first { $0.id == "profile" }
        #expect(profileParam != nil)
        #expect(profileParam?.enumValues?.count == 2)
    }

    @Test("Profile options include ps315 and the basic alias")
    func testProfileValues() {
        let tool = ToolRegistry.dicomAnon
        let profileParam = tool.parameters.first { $0.id == "profile" }
        let values = profileParam?.enumValues?.map(\.value) ?? []
        #expect(values.contains("basic"))
        #expect(values.contains("ps315"))
        #expect(!values.contains("research"))
        #expect(!values.contains("clinical-trial"))
    }

    @Test("Default profile is ps315")
    func testDefaultProfile() {
        let tool = ToolRegistry.dicomAnon
        let profileParam = tool.parameters.first { $0.id == "profile" }
        #expect(profileParam?.defaultValue == "ps315")
    }
}

// MARK: - dicom-compress Command Generation Tests

@Suite("DicomCompress Command Generation Tests")
struct DicomCompressCommandTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomCompress)
    }

    @Test("dicom-compress compress subcommand basic")
    func testCompressBasic() {
        let command = builder.buildCommand(
            values: ["input": "scan.dcm"],
            subcommand: "compress"
        )
        #expect(command.contains("dicom-compress"))
        #expect(command.contains("compress"))
        #expect(command.contains("scan.dcm"))
    }

    @Test("dicom-compress compress with codec and quality")
    func testCompressWithCodec() {
        let command = builder.buildCommand(
            values: [
                "input": "scan.dcm",
                "codec": "jpeg2000",
                "quality": "80",
            ],
            subcommand: "compress"
        )
        #expect(command.contains("compress"))
        #expect(command.contains("--codec jpeg2000"))
        #expect(command.contains("--quality 80"))
    }

    @Test("dicom-compress compress with output")
    func testCompressWithOutput() {
        let command = builder.buildCommand(
            values: [
                "input": "scan.dcm",
                "output": "compressed.dcm",
            ],
            subcommand: "compress"
        )
        #expect(command.contains("--output compressed.dcm"))
    }

    @Test("dicom-compress decompress subcommand")
    func testDecompress() {
        let command = builder.buildCommand(
            values: [
                "input": "compressed.dcm",
                "output": "decompressed.dcm",
            ],
            subcommand: "decompress"
        )
        #expect(command.contains("dicom-compress"))
        #expect(command.contains("decompress"))
        #expect(command.contains("compressed.dcm"))
        #expect(command.contains("--output decompressed.dcm"))
    }

    @Test("dicom-compress info subcommand")
    func testInfo() {
        let command = builder.buildCommand(
            values: ["input": "scan.dcm"],
            subcommand: "info"
        )
        #expect(command.contains("dicom-compress"))
        #expect(command.contains("info"))
        #expect(command.contains("scan.dcm"))
    }

    @Test("dicom-compress batch subcommand")
    func testBatch() {
        let command = builder.buildCommand(
            values: [
                "input": "/dicom/dir",
                "output": "/output/dir",
                "codec": "jpeg",
                "recursive": "true",
            ],
            subcommand: "batch"
        )
        #expect(command.contains("dicom-compress"))
        #expect(command.contains("batch"))
        #expect(command.contains("/dicom/dir"))
        #expect(command.contains("--output /output/dir"))
        #expect(command.contains("--codec jpeg"))
        #expect(command.contains("--recursive"))
    }

    @Test("dicom-compress compress has 4 codec options")
    func testCompressCodecCount() {
        let tool = ToolRegistry.dicomCompress
        let compressSub = tool.subcommands?.first { $0.id == "compress" }
        let codecParam = compressSub?.parameters.first { $0.id == "codec" }
        #expect(codecParam?.enumValues?.count == 4)
    }

    @Test("dicom-compress batch has 2 codec options")
    func testBatchCodecCount() {
        let tool = ToolRegistry.dicomCompress
        let batchSub = tool.subcommands?.first { $0.id == "batch" }
        let codecParam = batchSub?.parameters.first { $0.id == "codec" }
        #expect(codecParam?.enumValues?.count == 2)
    }
}

// MARK: - dicom-compress Subcommand Switching Tests

@Suite("DicomCompress Subcommand Switching Tests")
struct DicomCompressSubcommandTests {
    @Test("dicom-compress has 4 subcommands")
    func testSubcommandCount() {
        let tool = ToolRegistry.dicomCompress
        #expect(tool.subcommands?.count == 4)
    }

    @Test("Subcommands are in correct order")
    func testSubcommandOrder() {
        let tool = ToolRegistry.dicomCompress
        let ids = tool.subcommands?.map(\.id) ?? []
        #expect(ids == ["compress", "decompress", "info", "batch"])
    }

    @Test("Compress subcommand has required input")
    func testCompressRequiredInput() {
        let tool = ToolRegistry.dicomCompress
        let compressSub = tool.subcommands?.first { $0.id == "compress" }
        let inputParam = compressSub?.parameters.first { $0.id == "input" }
        #expect(inputParam?.isRequired == true)
    }

    @Test("Info subcommand has only input parameter")
    func testInfoMinimalParams() {
        let tool = ToolRegistry.dicomCompress
        let infoSub = tool.subcommands?.first { $0.id == "info" }
        #expect(infoSub?.parameters.count == 1)
        #expect(infoSub?.parameters.first?.id == "input")
    }

    @Test("Batch subcommand has recursive option")
    func testBatchRecursive() {
        let tool = ToolRegistry.dicomCompress
        let batchSub = tool.subcommands?.first { $0.id == "batch" }
        let recursiveParam = batchSub?.parameters.first { $0.id == "recursive" }
        #expect(recursiveParam != nil)
        #expect(recursiveParam?.type == .boolean)
    }
}

// MARK: - Required Parameter Validation Tests (Phase 3)

@Suite("Phase 3 Required Parameter Validation Tests")
struct Phase3RequiredParameterValidationTests {
    @Test("dicom-convert requires inputPath and output")
    func testConvertRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomConvert)
        #expect(!builder.isValid(values: [:]))
        #expect(!builder.isValid(values: ["inputPath": "scan.dcm"]))
        #expect(!builder.isValid(values: ["output": "out.dcm"]))
        #expect(builder.isValid(values: ["inputPath": "scan.dcm", "output": "out.dcm"]))
    }

    @Test("dicom-validate requires inputPath")
    func testValidateRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomValidate)
        #expect(!builder.isValid(values: [:]))
        #expect(!builder.isValid(values: ["inputPath": ""]))
        #expect(builder.isValid(values: ["inputPath": "scan.dcm"]))
    }

    @Test("dicom-anon requires inputPath")
    func testAnonRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomAnon)
        #expect(!builder.isValid(values: [:]))
        #expect(builder.isValid(values: ["inputPath": "scan.dcm"]))
    }

    @Test("dicom-compress compress requires input")
    func testCompressRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomCompress)
        #expect(!builder.isValid(values: [:], subcommand: "compress"))
        #expect(builder.isValid(values: ["input": "scan.dcm"], subcommand: "compress"))
    }

    @Test("dicom-compress decompress requires input")
    func testDecompressRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomCompress)
        #expect(!builder.isValid(values: [:], subcommand: "decompress"))
        #expect(builder.isValid(values: ["input": "scan.dcm"], subcommand: "decompress"))
    }

    @Test("dicom-compress info requires input")
    func testInfoRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomCompress)
        #expect(!builder.isValid(values: [:], subcommand: "info"))
        #expect(builder.isValid(values: ["input": "scan.dcm"], subcommand: "info"))
    }

    @Test("dicom-compress batch requires input")
    func testBatchRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomCompress)
        #expect(!builder.isValid(values: [:], subcommand: "batch"))
        #expect(builder.isValid(values: ["input": "/dir"], subcommand: "batch"))
    }
}

// MARK: - Help Content Tests (Phase 3)

@Suite("Phase 3 Help Content Tests")
struct Phase3HelpContentTests {
    @Test("dicom-convert has discussion text")
    func testConvertDiscussion() {
        let tool = ToolRegistry.dicomConvert
        #expect(!tool.discussion.isEmpty)
    }

    @Test("dicom-validate has discussion text")
    func testValidateDiscussion() {
        let tool = ToolRegistry.dicomValidate
        #expect(!tool.discussion.isEmpty)
    }

    @Test("dicom-anon has discussion text")
    func testAnonDiscussion() {
        let tool = ToolRegistry.dicomAnon
        #expect(!tool.discussion.isEmpty)
    }

    @Test("dicom-compress has discussion text")
    func testCompressDiscussion() {
        let tool = ToolRegistry.dicomCompress
        #expect(!tool.discussion.isEmpty)
    }

    @Test("All file processing tools have parameters with help text")
    func testAllParamsHaveHelp() {
        let tools = ToolRegistry.tools(for: .fileProcessing)
        for tool in tools {
            for param in tool.parameters {
                #expect(!param.help.isEmpty, "Parameter \(param.id) in \(tool.id) should have help text")
            }
        }
    }

    @Test("All file processing tools have SF Symbol icons")
    func testToolIcons() {
        let tools = ToolRegistry.tools(for: .fileProcessing)
        for tool in tools {
            #expect(!tool.icon.isEmpty, "Tool \(tool.id) should have an icon")
        }
    }
}

// MARK: - Missing Parameter Labels Tests (Phase 3)

@Suite("Phase 3 Missing Parameter Label Tests")
struct Phase3MissingParameterTests {
    @Test("dicom-convert missing files shows labels")
    func testConvertMissingFiles() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomConvert)
        let missing = builder.missingRequiredParameters(values: [:])
        #expect(missing.contains("Input File"))
        #expect(missing.contains("Output Path"))
    }

    @Test("dicom-validate missing file shows label")
    func testValidateMissingFile() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomValidate)
        let missing = builder.missingRequiredParameters(values: [:])
        #expect(missing.contains("Input File"))
    }

    @Test("dicom-anon no missing when file provided")
    func testAnonNoMissing() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomAnon)
        let missing = builder.missingRequiredParameters(values: ["inputPath": "scan.dcm"])
        #expect(missing.isEmpty)
    }
}

// MARK: - File Processing Tool Routing Tests

@Suite("File Processing Tool Routing Tests")
struct FileProcessingToolRoutingTests {
    @Test("File Processing category has exactly 4 tools")
    func testFileProcessingToolCount() {
        let tools = ToolRegistry.tools(for: .fileProcessing)
        #expect(tools.count == 4)
    }

    @Test("File Processing tools are in correct order")
    func testFileProcessingToolOrder() {
        let tools = ToolRegistry.tools(for: .fileProcessing)
        #expect(tools[0].id == "dicom-convert")
        #expect(tools[1].id == "dicom-validate")
        #expect(tools[2].id == "dicom-anon")
        #expect(tools[3].id == "dicom-compress")
    }

    @Test("File Processing tools do not require network")
    func testNoNetworkRequired() {
        let tools = ToolRegistry.tools(for: .fileProcessing)
        for tool in tools {
            #expect(!tool.requiresNetwork, "Tool \(tool.id) should not require network")
        }
    }

    @Test("Only dicom-compress has subcommands")
    func testSubcommandPresence() {
        let tools = ToolRegistry.tools(for: .fileProcessing)
        for tool in tools {
            if tool.id == "dicom-compress" {
                #expect(tool.subcommands != nil, "dicom-compress should have subcommands")
            } else {
                #expect(tool.subcommands == nil, "Tool \(tool.id) should not have subcommands")
            }
        }
    }
}
