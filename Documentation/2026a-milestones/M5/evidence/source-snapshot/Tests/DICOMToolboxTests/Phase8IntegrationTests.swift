import Foundation
import Testing
@testable import DICOMToolbox

// MARK: - End-to-End Workflow Tests

@Suite("End-to-End Workflow Tests")
struct EndToEndWorkflowTests {
    @Test("File inspection workflow: select tool → set params → generate command")
    func testFileInspectionWorkflow() {
        let tool = ToolRegistry.tool(withID: "dicom-info")!
        let builder = CommandBuilder(tool: tool)
        let values: [String: String] = ["filePath": "scan.dcm", "format": "json", "statistics": "true"]
        #expect(builder.isValid(values: values))
        let command = builder.buildCommand(values: values)
        #expect(command.contains("dicom-info"))
        #expect(command.contains("scan.dcm"))
        #expect(command.contains("--format json"))
        #expect(command.contains("--statistics"))
        let missing = builder.missingRequiredParameters(values: values)
        #expect(missing.isEmpty)
    }

    @Test("File processing workflow: convert with transfer syntax")
    func testFileProcessingWorkflow() {
        let tool = ToolRegistry.tool(withID: "dicom-convert")!
        let builder = CommandBuilder(tool: tool)
        let values: [String: String] = [
            "inputPath": "input.dcm",
            "output": "output.dcm",
            "transfer-syntax": "explicit-vr-le",
            "validate": "true",
        ]
        #expect(builder.isValid(values: values))
        let command = builder.buildCommand(values: values)
        #expect(command.contains("dicom-convert"))
        #expect(command.contains("input.dcm"))
        #expect(command.contains("--output output.dcm"))
        #expect(command.contains("--transfer-syntax explicit-vr-le"))
        #expect(command.contains("--validate"))
    }

    @Test("Subcommand workflow: compress with codec selection")
    func testSubcommandWorkflow() {
        let tool = ToolRegistry.tool(withID: "dicom-compress")!
        let builder = CommandBuilder(tool: tool)
        let values: [String: String] = [
            "input": "scan.dcm",
            "output": "compressed.dcm",
            "codec": "jpeg2000",
            "quality": "85",
        ]
        #expect(builder.isValid(values: values, subcommand: "compress"))
        let command = builder.buildCommand(values: values, subcommand: "compress")
        #expect(command.contains("dicom-compress compress"))
        #expect(command.contains("scan.dcm"))
        #expect(command.contains("--codec jpeg2000"))
        #expect(command.contains("--quality 85"))
    }

    @Test("Network tool workflow: echo with config")
    func testNetworkToolWorkflow() {
        let profile = ServerProfile(
            name: "Hospital PACS",
            aeTitle: "MYSCU",
            calledAET: "PACS_SCP",
            host: "pacs.hospital.org",
            port: 11112,
            timeout: 30,
            protocolType: .dicom
        )
        let config = profile.toNetworkConfig()
        #expect(config.isValid)
        let tool = ToolRegistry.tool(withID: "dicom-echo")!
        #expect(tool.requiresNetwork)
        let builder = CommandBuilder(tool: tool, networkConfig: config)
        let command = builder.buildCommand(values: ["count": "3", "stats": "true"])
        #expect(command.contains("dicom-echo"))
        #expect(command.contains("pacs://pacs.hospital.org:11112"))
        #expect(command.contains("--aet MYSCU"))
        #expect(command.contains("--called-aet PACS_SCP"))
        #expect(command.contains("--count 3"))
        #expect(command.contains("--stats"))
    }

    @Test("Data export workflow: JSON conversion")
    func testDataExportWorkflow() {
        let tool = ToolRegistry.tool(withID: "dicom-json")!
        let builder = CommandBuilder(tool: tool)
        let values: [String: String] = [
            "input": "study.dcm",
            "output": "study.json",
            "pretty": "true",
        ]
        #expect(builder.isValid(values: values))
        let command = builder.buildCommand(values: values)
        #expect(command.contains("dicom-json"))
        #expect(command.contains("study.dcm"))
        #expect(command.contains("--output study.json"))
        #expect(command.contains("--pretty"))
    }

    @Test("File organization workflow: archive creation")
    func testFileOrganizationWorkflow() {
        let tool = ToolRegistry.tool(withID: "dicom-archive")!
        let builder = CommandBuilder(tool: tool)
        let values: [String: String] = [
            "input": "/data/studies",
            "output": "archive.zip",
            "format": "zip",
            "recursive": "true",
        ]
        #expect(builder.isValid(values: values))
        let command = builder.buildCommand(values: values)
        #expect(command.contains("dicom-archive"))
        #expect(command.contains("/data/studies"))
        #expect(command.contains("--output archive.zip"))
        #expect(command.contains("--format zip"))
        #expect(command.contains("--recursive"))
    }

    @Test("Automation workflow: study organize with pattern")
    func testAutomationWorkflow() {
        let tool = ToolRegistry.tool(withID: "dicom-study")!
        let builder = CommandBuilder(tool: tool)
        let values: [String: String] = [
            "input": "/data/incoming",
            "output": "/data/organized",
            "pattern": "{PatientName}/{StudyDate}",
        ]
        #expect(builder.isValid(values: values, subcommand: "organize"))
        let command = builder.buildCommand(values: values, subcommand: "organize")
        #expect(command.contains("dicom-study"))
        #expect(command.contains("organize"))
        #expect(command.contains("/data/incoming"))
        #expect(command.contains("--output /data/organized"))
    }

    @Test("WADO subcommand workflow: retrieve study")
    func testWadoSubcommandWorkflow() {
        let config = NetworkConfig(
            aeTitle: "SCU",
            calledAET: "SCP",
            host: "pacs.web",
            port: 443,
            timeout: 60,
            protocolType: .dicomweb
        )
        let tool = ToolRegistry.tool(withID: "dicom-wado")!
        let builder = CommandBuilder(tool: tool, networkConfig: config)
        let values: [String: String] = [
            "study": "1.2.840.12345",
            "output": "/data/retrieved",
            "metadata": "true",
        ]
        #expect(builder.isValid(values: values, subcommand: "retrieve"))
        let command = builder.buildCommand(values: values, subcommand: "retrieve")
        #expect(command.contains("dicom-wado"))
        #expect(command.contains("retrieve"))
        #expect(command.contains("--study 1.2.840.12345"))
        #expect(command.contains("--metadata"))
    }

    @Test("PS3.15 anonymization workflow with default UID regeneration")
    func testAnonymizationWorkflow() throws {
        let tool = ToolRegistry.tool(withID: "dicom-anon")!
        let builder = CommandBuilder(tool: tool)
        let values: [String: String] = [
            "inputPath": "patient_scan.dcm",
            "output": "anon_scan.dcm",
            "profile": "ps315",
            "shift-dates": "30",
            "retain-uids": "false",
            "backup": "true",
            "audit-log": "audit.csv",
        ]
        #expect(builder.isValid(values: values))
        let invocation = try builder.validatedInvocation(values: values)
        let command = builder.buildCommand(values: values)
        #expect(command == invocation.commandString)
        #expect(command.contains("dicom-anon"))
        #expect(command.contains("patient_scan.dcm"))
        #expect(command.contains("--profile ps315"))
        #expect(command.contains("--output anon_scan.dcm"))
        #expect(command.contains("--shift-dates 30"))
        #expect(!invocation.arguments.contains("--regenerate-uids"))
        #expect(!invocation.arguments.contains("--retain-uids"))
        #expect(command.contains("--backup"))
        #expect(command.contains("--audit-log audit.csv"))
    }

    @Test("Command history workflow: generate, record, export")
    func testCommandHistoryWorkflow() {
        let tool = ToolRegistry.dicomInfo
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["filePath": "scan.dcm"])
        let entry = CommandHistoryEntry(
            toolID: tool.id,
            subcommand: nil,
            parameterValues: ["filePath": "scan.dcm"],
            commandString: command,
            exitCode: 0
        )
        #expect(entry.isSuccess)
        var history: [CommandHistoryEntry] = []
        CommandHistory.addEntry(entry, to: &history)
        #expect(history.count == 1)
        let script = CommandHistory.exportAsShellScript(history)
        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.contains(command))
    }
}

// MARK: - All 29 Tools Valid Syntax Tests

@Suite("All 29 Tools Generate Valid Syntax")
struct AllToolsValidSyntaxTests {
    private func networkConfig() -> NetworkConfig {
        NetworkConfig(
            aeTitle: "TEST_SCU",
            calledAET: "TEST_SCP",
            host: "testserver",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
    }

    @Test("dicom-info generates valid command syntax")
    func testDicomInfoSyntax() {
        let tool = ToolRegistry.dicomInfo
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["filePath": "scan.dcm"])
        #expect(command.hasPrefix("dicom-info"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-dump generates valid command syntax")
    func testDicomDumpSyntax() {
        let tool = ToolRegistry.dicomDump
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["filePath": "scan.dcm"])
        #expect(command.hasPrefix("dicom-dump"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-tags generates valid command syntax")
    func testDicomTagsSyntax() {
        let tool = ToolRegistry.dicomTags
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["input": "scan.dcm"])
        #expect(command.hasPrefix("dicom-tags"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-diff generates valid command syntax")
    func testDicomDiffSyntax() {
        let tool = ToolRegistry.dicomDiff
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["file1": "a.dcm", "file2": "b.dcm"])
        #expect(command.hasPrefix("dicom-diff"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-convert generates valid command syntax")
    func testDicomConvertSyntax() {
        let tool = ToolRegistry.dicomConvert
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["inputPath": "scan.dcm", "output": "out.dcm"])
        #expect(command.hasPrefix("dicom-convert"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-validate generates valid command syntax")
    func testDicomValidateSyntax() {
        let tool = ToolRegistry.dicomValidate
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["inputPath": "scan.dcm"])
        #expect(command.hasPrefix("dicom-validate"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-anon generates valid command syntax")
    func testDicomAnonSyntax() {
        let tool = ToolRegistry.dicomAnon
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["inputPath": "scan.dcm"])
        #expect(command.hasPrefix("dicom-anon"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-compress generates valid command syntax")
    func testDicomCompressSyntax() {
        let tool = ToolRegistry.dicomCompress
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["input": "scan.dcm"], subcommand: "compress")
        #expect(command.hasPrefix("dicom-compress"))
        #expect(command.contains("compress"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-split generates valid command syntax")
    func testDicomSplitSyntax() {
        let tool = ToolRegistry.dicomSplit
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["input": "multi.dcm"])
        #expect(command.hasPrefix("dicom-split"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-merge generates valid command syntax")
    func testDicomMergeSyntax() {
        let tool = ToolRegistry.dicomMerge
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["inputs": "frames/", "output": "merged.dcm"])
        #expect(command.hasPrefix("dicom-merge"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-dcmdir generates valid command syntax")
    func testDicomDcmdirSyntax() {
        let tool = ToolRegistry.dicomDcmdir
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["input": "/dicom/dir"], subcommand: "create")
        #expect(command.hasPrefix("dicom-dcmdir"))
        #expect(command.contains("create"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-archive generates valid command syntax")
    func testDicomArchiveSyntax() {
        let tool = ToolRegistry.dicomArchive
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["input": "study/", "output": "archive.zip"])
        #expect(command.hasPrefix("dicom-archive"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-json generates valid command syntax")
    func testDicomJsonSyntax() {
        let tool = ToolRegistry.dicomJson
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["input": "scan.dcm"])
        #expect(command.hasPrefix("dicom-json"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-xml generates valid command syntax")
    func testDicomXmlSyntax() {
        let tool = ToolRegistry.dicomXml
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["input": "scan.dcm"])
        #expect(command.hasPrefix("dicom-xml"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-pdf generates valid command syntax")
    func testDicomPdfSyntax() {
        let tool = ToolRegistry.dicomPdf
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["input": "report.pdf", "output": "report.dcm"])
        #expect(command.hasPrefix("dicom-pdf"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-image generates valid command syntax")
    func testDicomImageSyntax() {
        let tool = ToolRegistry.dicomImage
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["input": "photo.png", "output": "image.dcm"])
        #expect(command.hasPrefix("dicom-image"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-export generates valid command syntax")
    func testDicomExportSyntax() {
        let tool = ToolRegistry.dicomExport
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["input": "scan.dcm", "output": "scan.png"], subcommand: "single")
        #expect(command.hasPrefix("dicom-export"))
        #expect(command.contains("single"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-pixedit generates valid command syntax")
    func testDicomPixeditSyntax() {
        let tool = ToolRegistry.dicomPixedit
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["input": "scan.dcm", "output": "edited.dcm"])
        #expect(command.hasPrefix("dicom-pixedit"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-echo generates valid command syntax")
    func testDicomEchoSyntax() {
        let tool = ToolRegistry.dicomEcho
        let builder = CommandBuilder(tool: tool, networkConfig: networkConfig())
        let command = builder.buildCommand(values: [:])
        #expect(command.hasPrefix("dicom-echo"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-query generates valid command syntax")
    func testDicomQuerySyntax() {
        let tool = ToolRegistry.dicomQuery
        let builder = CommandBuilder(tool: tool, networkConfig: networkConfig())
        let command = builder.buildCommand(values: ["level": "study"])
        #expect(command.hasPrefix("dicom-query"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-send generates valid command syntax")
    func testDicomSendSyntax() {
        let tool = ToolRegistry.dicomSend
        let builder = CommandBuilder(tool: tool, networkConfig: networkConfig())
        let command = builder.buildCommand(values: ["paths": "scan.dcm"])
        #expect(command.hasPrefix("dicom-send"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-retrieve generates valid command syntax")
    func testDicomRetrieveSyntax() {
        let tool = ToolRegistry.dicomRetrieve
        let builder = CommandBuilder(tool: tool, networkConfig: networkConfig())
        let command = builder.buildCommand(values: ["output": "/output", "study-uid": "1.2.3"])
        #expect(command.hasPrefix("dicom-retrieve"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-qr generates valid command syntax")
    func testDicomQRSyntax() {
        let tool = ToolRegistry.dicomQR
        let builder = CommandBuilder(tool: tool, networkConfig: networkConfig())
        let command = builder.buildCommand(values: ["interactive": "true"])
        #expect(command.hasPrefix("dicom-qr"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-wado generates valid command syntax")
    func testDicomWadoSyntax() {
        let tool = ToolRegistry.dicomWado
        let config = NetworkConfig(
            aeTitle: "SCU",
            calledAET: "SCP",
            host: "web",
            port: 443,
            timeout: 60,
            protocolType: .dicomweb
        )
        let builder = CommandBuilder(tool: tool, networkConfig: config)
        let command = builder.buildCommand(values: ["study": "1.2.840.12345"], subcommand: "retrieve")
        #expect(command.hasPrefix("dicom-wado"))
        #expect(command.contains("retrieve"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-mwl generates valid command syntax")
    func testDicomMWLSyntax() {
        let tool = ToolRegistry.dicomMWL
        let builder = CommandBuilder(tool: tool, networkConfig: networkConfig())
        let command = builder.buildCommand(values: ["date": "20240101"])
        #expect(command.hasPrefix("dicom-mwl"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-mpps generates valid command syntax")
    func testDicomMPPSSyntax() {
        let tool = ToolRegistry.dicomMPPS
        let builder = CommandBuilder(tool: tool, networkConfig: networkConfig())
        let command = builder.buildCommand(values: ["study-uid": "1.2.840.12345"], subcommand: "create")
        #expect(command.hasPrefix("dicom-mpps"))
        #expect(command.contains("create"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-study generates valid command syntax")
    func testDicomStudySyntax() {
        let tool = ToolRegistry.dicomStudy
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["input": "/data/study"], subcommand: "organize")
        #expect(command.hasPrefix("dicom-study"))
        #expect(command.contains("organize"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-uid generates valid command syntax")
    func testDicomUIDSyntax() {
        let tool = ToolRegistry.dicomUID
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["count": "5"], subcommand: "generate")
        #expect(command.hasPrefix("dicom-uid"))
        #expect(command.contains("generate"))
        #expect(!command.isEmpty)
    }

    @Test("dicom-script generates valid command syntax")
    func testDicomScriptSyntax() {
        let tool = ToolRegistry.dicomScript
        let builder = CommandBuilder(tool: tool)
        let command = builder.buildCommand(values: ["script": "pipeline.dscript"], subcommand: "run")
        #expect(command.hasPrefix("dicom-script"))
        #expect(command.contains("run"))
        #expect(!command.isEmpty)
    }
}

// MARK: - File Drag-and-Drop Integration Tests

@Suite("File Drag-and-Drop Integration Tests")
struct FileDragDropIntegrationTests {
    @Test("File path with spaces is handled correctly in command")
    func testFilePathWithSpaces() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        let command = builder.buildCommand(values: [
            "filePath": "/Users/doctor/My Medical Files/scan 2024.dcm",
        ])
        #expect(command.contains("dicom-info"))
        #expect(command.contains("/Users/doctor/My Medical Files/scan 2024.dcm"))
    }

    @Test("Multiple file paths stored and used in merge command")
    func testMultipleFilePaths() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomMerge)
        let paths = "/data/frame1.dcm,/data/frame2.dcm,/data/frame3.dcm"
        let command = builder.buildCommand(values: [
            "inputs": paths,
            "output": "merged.dcm",
        ])
        #expect(command.contains("dicom-merge"))
        #expect(command.contains("merged.dcm"))
    }

    @Test("File extension validation patterns for DICOM files")
    func testFileExtensionValidation() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        #expect(builder.isValid(values: ["filePath": "scan.dcm"]))
        #expect(builder.isValid(values: ["filePath": "scan.dicom"]))
        #expect(builder.isValid(values: ["filePath": "scan"]))
        #expect(builder.isValid(values: ["filePath": "CT.1.2.840.12345"]))
    }

    @Test("Directory paths are accepted for recursive tools")
    func testDirectoryPaths() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomSplit)
        let command = builder.buildCommand(values: [
            "input": "/data/studies/patient001/",
            "recursive": "true",
        ])
        #expect(command.contains("/data/studies/patient001/"))
        #expect(command.contains("--recursive"))
    }

    @Test("Paths with special characters are preserved")
    func testSpecialCharacterPaths() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo)
        let command = builder.buildCommand(values: [
            "filePath": "/data/CT-Head_2024 (1)/scan#001.dcm",
        ])
        #expect(command.contains("dicom-info"))
        #expect(command.contains("/data/CT-Head_2024 (1)/scan#001.dcm"))
    }
}

// MARK: - Network Mock Testing

@Suite("Network Integration Tests")
struct NetworkIntegrationTests {
    @Test("DICOM protocol URL construction integrates with echo tool")
    func testDicomProtocolURLIntegration() {
        let config = NetworkConfig(
            aeTitle: "ECHO_SCU",
            calledAET: "PACS_SCP",
            host: "pacs.hospital.org",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
        #expect(config.serverURL == "pacs://pacs.hospital.org:11112")
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: config)
        let command = builder.buildCommand(values: [:])
        #expect(command.contains("pacs://pacs.hospital.org:11112"))
    }

    @Test("DICOMweb protocol URL construction integrates with WADO tool")
    func testDicomwebProtocolIntegration() {
        let config = NetworkConfig(
            aeTitle: "WEB_SCU",
            calledAET: "WEB_SCP",
            host: "dicomweb.hospital.org",
            port: 443,
            timeout: 60,
            protocolType: .dicomweb
        )
        #expect(config.serverURL == "https://dicomweb.hospital.org:443/dicom-web")
        let builder = CommandBuilder(tool: ToolRegistry.dicomWado, networkConfig: config)
        let command = builder.buildCommand(values: ["study": "1.2.840.12345"], subcommand: "retrieve")
        #expect(command.contains("dicom-wado"))
        #expect(command.contains("retrieve"))
    }

    @Test("Network config from ServerProfile propagates to command builder")
    func testNetworkConfigInheritance() {
        let profile = ServerProfile(
            name: "Research PACS",
            aeTitle: "RESEARCH",
            calledAET: "PACS01",
            host: "research.pacs.edu",
            port: 4242,
            timeout: 120,
            protocolType: .dicom
        )
        let config = profile.toNetworkConfig()
        #expect(config.aeTitle == "RESEARCH")
        #expect(config.calledAET == "PACS01")
        #expect(config.host == "research.pacs.edu")
        #expect(config.port == 4242)
        let builder = CommandBuilder(tool: ToolRegistry.dicomQuery, networkConfig: config)
        let command = builder.buildCommand(values: ["level": "study"])
        #expect(command.contains("--aet RESEARCH"))
        #expect(command.contains("--called-aet PACS01"))
        #expect(command.contains("pacs://research.pacs.edu:4242"))
    }

    @Test("Timeout propagates from config to network tool commands")
    func testTimeoutPropagation() {
        let config = NetworkConfig(
            aeTitle: "SCU",
            calledAET: "SCP",
            host: "slow-pacs",
            port: 11112,
            timeout: 300,
            protocolType: .dicom
        )
        let builder = CommandBuilder(tool: ToolRegistry.dicomSend, networkConfig: config)
        let command = builder.buildCommand(values: ["paths": "scan.dcm"])
        #expect(command.contains("--timeout 300"))
    }

    @Test("Switching between server profiles produces different commands")
    func testProfileSwitching() {
        let profile1 = ServerProfile(
            name: "PACS A",
            aeTitle: "SCU_A",
            calledAET: "SCP_A",
            host: "pacs-a.hospital.org",
            port: 11112
        )
        let profile2 = ServerProfile(
            name: "PACS B",
            aeTitle: "SCU_B",
            calledAET: "SCP_B",
            host: "pacs-b.hospital.org",
            port: 4242
        )
        let builder1 = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: profile1.toNetworkConfig())
        let builder2 = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: profile2.toNetworkConfig())
        let command1 = builder1.buildCommand(values: [:])
        let command2 = builder2.buildCommand(values: [:])
        #expect(command1.contains("pacs://pacs-a.hospital.org:11112"))
        #expect(command1.contains("--aet SCU_A"))
        #expect(command2.contains("pacs://pacs-b.hospital.org:4242"))
        #expect(command2.contains("--aet SCU_B"))
        #expect(command1 != command2)
    }
}

// MARK: - Performance Benchmark Tests

@Suite("Performance Benchmark Tests")
struct PerformanceBenchmarkTests {
    @Test("Command generation for all 29 tools completes quickly")
    func testCommandGenerationPerformance() {
        let config = NetworkConfig(
            aeTitle: "PERF_SCU",
            calledAET: "PERF_SCP",
            host: "perfhost",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
        let start = Date()
        for tool in ToolRegistry.allTools {
            let builder: CommandBuilder
            if tool.requiresNetwork {
                builder = CommandBuilder(tool: tool, networkConfig: config)
            } else {
                builder = CommandBuilder(tool: tool)
            }
            // Build a command with minimal values for each tool
            var values: [String: String] = [:]
            let params: [ParameterDefinition]
            if let firstSub = tool.subcommands?.first {
                params = firstSub.parameters
            } else {
                params = tool.parameters
            }
            for param in params where param.isRequired {
                values[param.id] = "test_value"
            }
            let subcommand = tool.subcommands?.first?.id
            _ = builder.buildCommand(values: values, subcommand: subcommand)
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 1.0, "Command generation for all 29 tools took \(elapsed)s, expected < 1.0s")
    }

    @Test("Tool registry lookups are fast")
    func testRegistryLookupPerformance() {
        let toolIDs = ToolRegistry.allTools.map(\.id)
        let start = Date()
        for _ in 0..<1000 {
            for id in toolIDs {
                _ = ToolRegistry.tool(withID: id)
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 1.0, "1000 iterations of 29 lookups took \(elapsed)s, expected < 1.0s")
    }

    @Test("History operations with many entries are performant")
    func testHistoryPerformance() {
        var entries: [CommandHistoryEntry] = []
        let start = Date()
        for i in 0..<200 {
            let entry = CommandHistoryEntry(
                toolID: "dicom-info",
                parameterValues: ["filePath": "scan\(i).dcm"],
                commandString: "dicom-info scan\(i).dcm",
                exitCode: 0
            )
            CommandHistory.addEntry(entry, to: &entries)
        }
        let script = CommandHistory.exportAsShellScript(entries)
        let elapsed = Date().timeIntervalSince(start)
        #expect(entries.count == CommandHistory.maxEntries)
        #expect(!script.isEmpty)
        #expect(elapsed < 1.0, "History operations took \(elapsed)s, expected < 1.0s")
    }
}
