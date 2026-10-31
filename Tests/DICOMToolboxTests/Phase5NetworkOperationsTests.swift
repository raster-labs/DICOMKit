import Foundation
import Testing
@testable import DICOMToolbox

// MARK: - Network Config Inheritance Tests

@Suite("Network Config Inheritance Tests")
struct NetworkConfigInheritanceTests {
    @Test("Network config provides default server URL for DICOM protocol")
    func testDefaultServerURLDicom() {
        let config = NetworkConfig(
            aeTitle: "MY_SCU",
            calledAET: "ANY-SCP",
            host: "pacs.hospital.org",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
        #expect(config.serverURL == "pacs://pacs.hospital.org:11112")
    }

    @Test("Network config provides default server URL for DICOMweb protocol")
    func testDefaultServerURLDicomweb() {
        let config = NetworkConfig(
            aeTitle: "MY_SCU",
            calledAET: "ANY-SCP",
            host: "pacs.hospital.org",
            port: 443,
            timeout: 60,
            protocolType: .dicomweb
        )
        #expect(config.serverURL == "https://pacs.hospital.org:443/dicom-web")
    }

    @Test("Network tools auto-populate URL from config when not overridden")
    func testNetworkToolAutoURL() {
        let config = NetworkConfig(
            aeTitle: "MY_SCU",
            calledAET: "PACS_SCP",
            host: "server",
            port: 11112,
            timeout: 30,
            protocolType: .dicom
        )
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: config)
        let command = builder.buildCommand(values: [:])
        #expect(command.contains("pacs://server:11112"))
        #expect(command.contains("--aet MY_SCU"))
        #expect(command.contains("--called-aet PACS_SCP"))
        #expect(command.contains("--timeout 30"))
    }

    @Test("Network tools use AET from config")
    func testNetworkToolAETFromConfig() {
        let config = NetworkConfig(
            aeTitle: "TEST_AET",
            calledAET: "REMOTE",
            host: "host",
            port: 104,
            timeout: 60,
            protocolType: .dicom
        )
        let builder = CommandBuilder(tool: ToolRegistry.dicomQuery, networkConfig: config)
        let command = builder.buildCommand(values: ["level": "study"])
        #expect(command.contains("--aet TEST_AET"))
        #expect(command.contains("--called-aet REMOTE"))
    }

    @Test("Network tools use timeout from config")
    func testNetworkToolTimeoutFromConfig() {
        let config = NetworkConfig(
            aeTitle: "SCU",
            calledAET: "SCP",
            host: "host",
            port: 104,
            timeout: 120,
            protocolType: .dicom
        )
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: config)
        let command = builder.buildCommand(values: [:])
        #expect(command.contains("--timeout 120"))
    }

    @Test("Non-network tools do not include network parameters")
    func testNonNetworkToolNoNetworkParams() {
        let config = NetworkConfig(
            aeTitle: "SCU",
            calledAET: "SCP",
            host: "host",
            port: 104,
            timeout: 60,
            protocolType: .dicom
        )
        let builder = CommandBuilder(tool: ToolRegistry.dicomInfo, networkConfig: config)
        let command = builder.buildCommand(values: ["filePath": "test.dcm"])
        #expect(!command.contains("--aet"))
        #expect(!command.contains("--called-aet"))
        #expect(!command.contains("--timeout"))
        #expect(!command.contains("pacs://"))
    }
}

// MARK: - Network Config Override Tests

@Suite("Network Config Override Tests")
struct NetworkConfigOverrideTests {
    private var config: NetworkConfig {
        NetworkConfig(
            aeTitle: "DEFAULT_SCU",
            calledAET: "DEFAULT_SCP",
            host: "default.host",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
    }

    @Test("Override URL replaces config URL")
    func testOverrideURL() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: config)
        let command = builder.buildCommand(values: ["url": "pacs://custom:4242"])
        #expect(command.contains("pacs://custom:4242"))
    }

    @Test("Override AET replaces config AET")
    func testOverrideAET() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: config)
        let command = builder.buildCommand(values: ["aet": "CUSTOM_SCU"])
        #expect(command.contains("--aet CUSTOM_SCU"))
    }

    @Test("Override Called AET replaces config Called AET")
    func testOverrideCalledAET() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: config)
        let command = builder.buildCommand(values: ["called-aet": "CUSTOM_SCP"])
        #expect(command.contains("--called-aet CUSTOM_SCP"))
    }

    @Test("Override timeout replaces config timeout")
    func testOverrideTimeout() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: config)
        let command = builder.buildCommand(values: ["timeout": "120"])
        #expect(command.contains("--timeout 120"))
    }
}

// MARK: - URL Auto-Construction Tests

@Suite("URL Auto-Construction Tests")
struct URLAutoConstructionTests {
    @Test("DICOM protocol URL uses pacs:// scheme")
    func testDicomProtocolURL() {
        let config = NetworkConfig(
            aeTitle: "SCU",
            calledAET: "SCP",
            host: "myserver",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
        #expect(config.serverURL == "pacs://myserver:11112")
    }

    @Test("DICOMweb protocol URL uses https:// scheme")
    func testDicomwebProtocolURL() {
        let config = NetworkConfig(
            aeTitle: "SCU",
            calledAET: "SCP",
            host: "myserver",
            port: 8080,
            timeout: 60,
            protocolType: .dicomweb
        )
        #expect(config.serverURL == "https://myserver:8080/dicom-web")
    }

    @Test("URL with custom port constructs correctly")
    func testCustomPortURL() {
        let config = NetworkConfig(
            aeTitle: "SCU",
            calledAET: "SCP",
            host: "pacs.local",
            port: 104,
            timeout: 60,
            protocolType: .dicom
        )
        #expect(config.serverURL == "pacs://pacs.local:104")
    }
}

// MARK: - dicom-echo Command Generation Tests

@Suite("DicomEcho Command Generation Tests")
struct DicomEchoCommandTests {
    private var config: NetworkConfig {
        NetworkConfig(
            aeTitle: "TEST_SCU",
            calledAET: "TEST_SCP",
            host: "pacs",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
    }

    @Test("Basic dicom-echo command with network config")
    func testBasicCommand() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: config)
        let command = builder.buildCommand(values: [:])
        #expect(command.contains("dicom-echo"))
        #expect(command.contains("pacs://pacs:11112"))
    }

    @Test("dicom-echo with count parameter")
    func testWithCount() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: config)
        let command = builder.buildCommand(values: ["count": "5"])
        #expect(command.contains("--count 5"))
    }

    @Test("dicom-echo with stats flag")
    func testWithStats() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: config)
        let command = builder.buildCommand(values: ["stats": "true"])
        #expect(command.contains("--stats"))
    }

    @Test("dicom-echo with diagnose flag")
    func testWithDiagnose() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho, networkConfig: config)
        let command = builder.buildCommand(values: ["diagnose": "true"])
        #expect(command.contains("--diagnose"))
    }
}

// MARK: - dicom-query Command Generation Tests

@Suite("DicomQuery Command Generation Tests")
struct DicomQueryCommandTests {
    private var config: NetworkConfig {
        NetworkConfig(
            aeTitle: "QUERY_SCU",
            calledAET: "PACS_SCP",
            host: "pacs.hospital.com",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
    }

    @Test("dicom-query with patient name search")
    func testPatientNameSearch() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomQuery, networkConfig: config)
        let command = builder.buildCommand(values: ["patient-name": "SMITH*"])
        #expect(command.contains("dicom-query"))
        #expect(command.contains("--patient-name 'SMITH*'"))
    }

    @Test("dicom-query with study date filter")
    func testStudyDateFilter() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomQuery, networkConfig: config)
        let command = builder.buildCommand(values: ["study-date": "20240101"])
        #expect(command.contains("--study-date 20240101"))
    }

    @Test("dicom-query with modality filter")
    func testModalityFilter() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomQuery, networkConfig: config)
        let command = builder.buildCommand(values: ["modality": "CT"])
        #expect(command.contains("--modality CT"))
    }

    @Test("dicom-query with query level")
    func testQueryLevel() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomQuery, networkConfig: config)
        let command = builder.buildCommand(values: ["level": "series"])
        #expect(command.contains("--level series"))
    }

    @Test("dicom-query with output format")
    func testOutputFormat() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomQuery, networkConfig: config)
        let command = builder.buildCommand(values: ["format": "json"])
        #expect(command.contains("--format json"))
    }

    @Test("dicom-query with multiple search criteria")
    func testMultipleSearchCriteria() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomQuery, networkConfig: config)
        let command = builder.buildCommand(values: [
            "patient-name": "SMITH*",
            "modality": "CT",
            "study-date": "20240101",
        ])
        #expect(command.contains("--patient-name 'SMITH*'"))
        #expect(command.contains("--modality CT"))
        #expect(command.contains("--study-date 20240101"))
    }

    @Test("dicom-query with patient ID")
    func testPatientID() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomQuery, networkConfig: config)
        let command = builder.buildCommand(values: ["patient-id": "12345"])
        #expect(command.contains("--patient-id 12345"))
    }

    @Test("dicom-query with verbose flag")
    func testVerbose() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomQuery, networkConfig: config)
        let command = builder.buildCommand(values: ["verbose": "true"])
        #expect(command.contains("--verbose"))
    }
}

// MARK: - dicom-send Multi-File Command Tests

@Suite("DicomSend Command Generation Tests")
struct DicomSendCommandTests {
    private var config: NetworkConfig {
        NetworkConfig(
            aeTitle: "SEND_SCU",
            calledAET: "PACS_SCP",
            host: "pacs.hospital.com",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
    }

    @Test("dicom-send with single file")
    func testSingleFile() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomSend, networkConfig: config)
        let command = builder.buildCommand(values: ["paths": "scan.dcm"])
        #expect(command.contains("dicom-send"))
        #expect(command.contains("scan.dcm"))
    }

    @Test("dicom-send with recursive flag")
    func testRecursive() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomSend, networkConfig: config)
        let command = builder.buildCommand(values: [
            "paths": "study/",
            "recursive": "true",
        ])
        #expect(command.contains("--recursive"))
    }

    @Test("dicom-send with verify flag")
    func testVerify() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomSend, networkConfig: config)
        let command = builder.buildCommand(values: [
            "paths": "scan.dcm",
            "verify": "true",
        ])
        #expect(command.contains("--verify"))
    }

    @Test("dicom-send with retry count")
    func testRetryCount() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomSend, networkConfig: config)
        let command = builder.buildCommand(values: [
            "paths": "scan.dcm",
            "retry": "3",
        ])
        #expect(command.contains("--retry 3"))
    }

    @Test("dicom-send with dry run")
    func testDryRun() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomSend, networkConfig: config)
        let command = builder.buildCommand(values: [
            "paths": "scan.dcm",
            "dry-run": "true",
        ])
        #expect(command.contains("--dry-run"))
    }

    @Test("dicom-send with HTJ2K transfer syntax")
    func testHTJ2KTransferSyntax() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomSend, networkConfig: config)
        let command = builder.buildCommand(values: [
            "paths": "scan.dcm",
            "transfer-syntax": "htj2k-lossless",
        ])
        #expect(command.contains("--transfer-syntax htj2k-lossless"))
    }
}

// MARK: - dicom-retrieve Method-Dependent Fields Tests

@Suite("DicomRetrieve Command Generation Tests")
struct DicomRetrieveCommandTests {
    private var config: NetworkConfig {
        NetworkConfig(
            aeTitle: "RET_SCU",
            calledAET: "PACS_SCP",
            host: "pacs",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
    }

    @Test("dicom-retrieve with study UID")
    func testStudyUID() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomRetrieve, networkConfig: config)
        let command = builder.buildCommand(values: [
            "study-uid": "1.2.840.12345",
            "output": "/output",
        ])
        #expect(command.contains("--study-uid 1.2.840.12345"))
        #expect(command.contains("--output /output"))
    }

    @Test("dicom-retrieve with C-MOVE method")
    func testCMoveMethod() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomRetrieve, networkConfig: config)
        let command = builder.buildCommand(values: [
            "study-uid": "1.2.840.12345",
            "output": "/output",
            "method": "c-move",
            "move-dest": "MY_SCP",
        ])
        #expect(command.contains("--method c-move"))
        #expect(command.contains("--move-dest MY_SCP"))
    }

    @Test("dicom-retrieve with C-GET method")
    func testCGetMethod() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomRetrieve, networkConfig: config)
        let command = builder.buildCommand(values: [
            "study-uid": "1.2.840.12345",
            "output": "/output",
            "method": "c-get",
        ])
        #expect(command.contains("--method c-get"))
    }

    @Test("dicom-retrieve with parallel operations")
    func testParallel() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomRetrieve, networkConfig: config)
        let command = builder.buildCommand(values: [
            "study-uid": "1.2.840.12345",
            "output": "/output",
            "parallel": "4",
        ])
        #expect(command.contains("--parallel 4"))
    }

    @Test("dicom-retrieve with HTJ2K transfer syntax")
    func testRetrieveHTJ2KTransferSyntax() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomRetrieve, networkConfig: config)
        let command = builder.buildCommand(values: [
            "study-uid": "1.2.840.12345",
            "output": "/output",
            "transfer-syntax": "htj2k-rpcl",
        ])
        #expect(command.contains("--transfer-syntax htj2k-rpcl"))
    }
}

// MARK: - dicom-qr Combined Workflow Tests

@Suite("DicomQR Command Generation Tests")
struct DicomQRCommandTests {
    private var config: NetworkConfig {
        NetworkConfig(
            aeTitle: "QR_SCU",
            calledAET: "QR_SCP",
            host: "pacs",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
    }

    @Test("dicom-qr with interactive mode")
    func testInteractiveMode() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomQR, networkConfig: config)
        let command = builder.buildCommand(values: ["interactive": "true"])
        #expect(command.contains("--interactive"))
    }

    @Test("dicom-qr with auto retrieve")
    func testAutoRetrieve() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomQR, networkConfig: config)
        let command = builder.buildCommand(values: ["auto": "true"])
        #expect(command.contains("--auto"))
    }

    @Test("dicom-qr with method and move destination")
    func testMethodAndMoveDest() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomQR, networkConfig: config)
        let command = builder.buildCommand(values: [
            "method": "c-move",
            "move-dest": "LOCAL_SCP",
        ])
        #expect(command.contains("--method c-move"))
        #expect(command.contains("--move-dest LOCAL_SCP"))
    }

    @Test("dicom-qr with output directory")
    func testOutputDirectory() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomQR, networkConfig: config)
        let command = builder.buildCommand(values: ["output": "/data/retrieved"])
        #expect(command.contains("--output /data/retrieved"))
    }
}

// MARK: - dicom-wado Subcommand Form Tests

@Suite("DicomWado Command Generation Tests")
struct DicomWadoCommandTests {
    @Test("dicom-wado retrieve with study UID")
    func testRetrieveStudy() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomWado)
        let command = builder.buildCommand(values: [
            "study": "1.2.840.12345",
        ], subcommand: "retrieve")
        #expect(command.contains("dicom-wado"))
        #expect(command.contains("retrieve"))
        #expect(command.contains("--study 1.2.840.12345"))
    }

    @Test("dicom-wado retrieve with metadata only")
    func testRetrieveMetadataOnly() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomWado)
        let command = builder.buildCommand(values: [
            "study": "1.2.840.12345",
            "metadata": "true",
        ], subcommand: "retrieve")
        #expect(command.contains("--metadata"))
    }

    @Test("dicom-wado store with input files")
    func testStoreFiles() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomWado)
        let command = builder.buildCommand(values: [
            "input": "study/",
        ], subcommand: "store")
        #expect(command.contains("store"))
        #expect(command.contains("study/"))
    }

    @Test("dicom-wado query with level")
    func testQueryLevel() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomWado)
        let command = builder.buildCommand(values: [
            "level": "study",
        ], subcommand: "query")
        #expect(command.contains("query"))
        #expect(command.contains("--level study"))
    }

    @Test("dicom-wado has 3 subcommands")
    func testSubcommandCount() {
        let tool = ToolRegistry.dicomWado
        #expect(tool.subcommands?.count == 3)
    }

    @Test("dicom-wado retrieve subcommand has study parameter as required")
    func testRetrieveStudyRequired() {
        let tool = ToolRegistry.dicomWado
        let retrieveSub = tool.subcommands?.first(where: { $0.id == "retrieve" })
        let studyParam = retrieveSub?.parameters.first(where: { $0.id == "study" })
        #expect(studyParam?.isRequired == true)
    }
}

// MARK: - dicom-mwl Command Generation Tests

@Suite("DicomMWL Command Generation Tests")
struct DicomMWLCommandTests {
    private var config: NetworkConfig {
        NetworkConfig(
            aeTitle: "MWL_SCU",
            calledAET: "RIS_SCP",
            host: "ris",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
    }

    @Test("dicom-mwl with date filter")
    func testDateFilter() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomMWL, networkConfig: config)
        let command = builder.buildCommand(values: ["date": "20240115"])
        #expect(command.contains("--date 20240115"))
    }

    @Test("dicom-mwl with patient filter")
    func testPatientFilter() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomMWL, networkConfig: config)
        let command = builder.buildCommand(values: ["patient": "SMITH*"])
        #expect(command.contains("--patient 'SMITH*'"))
    }

    @Test("dicom-mwl with JSON output")
    func testJsonOutput() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomMWL, networkConfig: config)
        let command = builder.buildCommand(values: ["json": "true"])
        #expect(command.contains("--json"))
    }
}

// MARK: - dicom-mpps Command Generation Tests

@Suite("DicomMPPS Command Generation Tests")
struct DicomMPPSCommandTests {
    private var config: NetworkConfig {
        NetworkConfig(
            aeTitle: "MPPS_SCU",
            calledAET: "MPPS_SCP",
            host: "pacs",
            port: 11112,
            timeout: 60,
            protocolType: .dicom
        )
    }

    @Test("dicom-mpps create with study UID")
    func testCreateWithStudyUID() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomMPPS, networkConfig: config)
        let command = builder.buildCommand(values: [
            "study-uid": "1.2.840.12345",
        ], subcommand: "create")
        #expect(command.contains("dicom-mpps"))
        #expect(command.contains("create"))
        #expect(command.contains("--study-uid 1.2.840.12345"))
    }

    @Test("dicom-mpps update with status")
    func testUpdateWithStatus() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomMPPS, networkConfig: config)
        let command = builder.buildCommand(values: [
            "study-uid": "1.2.840.12345",
            "status": "COMPLETED",
        ], subcommand: "update")
        #expect(command.contains("update"))
        #expect(command.contains("--status COMPLETED"))
    }

    @Test("dicom-mpps has 2 subcommands")
    func testSubcommandCount() {
        let tool = ToolRegistry.dicomMPPS
        #expect(tool.subcommands?.count == 2)
    }
}

// MARK: - Tool Registry Network Tool Tests

@Suite("Network Tool Registry Tests")
struct NetworkToolRegistryTests {
    @Test("Network operations category has 8 tools")
    func testNetworkToolCount() {
        let tools = ToolRegistry.tools(for: .networkOperations)
        #expect(tools.count == 8)
    }

    @Test("All network tools have requiresNetwork set to true")
    func testAllNetworkToolsRequireNetwork() {
        let tools = ToolRegistry.tools(for: .networkOperations)
        for tool in tools {
            #expect(tool.requiresNetwork == true)
        }
    }

    @Test("dicom-echo tool exists in registry")
    func testEchoToolExists() {
        let tool = ToolRegistry.tool(withID: "dicom-echo")
        #expect(tool != nil)
        #expect(tool?.category == .networkOperations)
    }

    @Test("dicom-query tool has modality enum parameter")
    func testQueryModalityEnum() {
        let tool = ToolRegistry.dicomQuery
        let modality = tool.parameters.first(where: { $0.id == "modality" })
        #expect(modality?.type == .enumeration)
        #expect(modality?.enumValues?.count == 5)
    }

    @Test("dicom-send tool requires files parameter")
    func testSendRequiresFiles() {
        let tool = ToolRegistry.dicomSend
        let paths = tool.parameters.first(where: { $0.id == "paths" })
        #expect(paths?.isRequired == true)
        #expect(paths?.type == .file)
    }

    @Test("dicom-retrieve tool has method enum with 2 options")
    func testRetrieveMethodEnum() {
        let tool = ToolRegistry.dicomRetrieve
        let method = tool.parameters.first(where: { $0.id == "method" })
        #expect(method?.type == .enumeration)
        #expect(method?.enumValues?.count == 2)
    }
}

// MARK: - Validation Tests for Network Parameters

@Suite("Network Parameter Validation Tests")
struct NetworkParameterValidationTests {
    @Test("dicom-echo count validation accepts valid range")
    func testEchoCountValid() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho)
        #expect(builder.validateParameter("count", value: "1") == true)
        #expect(builder.validateParameter("count", value: "50") == true)
        #expect(builder.validateParameter("count", value: "100") == true)
    }

    @Test("dicom-echo count validation rejects out of range")
    func testEchoCountInvalid() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomEcho)
        #expect(builder.validateParameter("count", value: "0") == false)
        #expect(builder.validateParameter("count", value: "101") == false)
    }

    @Test("dicom-send retry validation accepts valid range")
    func testSendRetryValid() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomSend)
        #expect(builder.validateParameter("retry", value: "0") == true)
        #expect(builder.validateParameter("retry", value: "5") == true)
        #expect(builder.validateParameter("retry", value: "10") == true)
    }

    @Test("dicom-send retry validation rejects out of range")
    func testSendRetryInvalid() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomSend)
        #expect(builder.validateParameter("retry", value: "-1") == false)
        #expect(builder.validateParameter("retry", value: "11") == false)
    }

    @Test("dicom-retrieve parallel validation accepts valid range")
    func testRetrieveParallelValid() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomRetrieve)
        #expect(builder.validateParameter("parallel", value: "1") == true)
        #expect(builder.validateParameter("parallel", value: "4") == true)
        #expect(builder.validateParameter("parallel", value: "8") == true)
    }

    @Test("dicom-retrieve parallel validation rejects out of range")
    func testRetrieveParallelInvalid() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomRetrieve)
        #expect(builder.validateParameter("parallel", value: "0") == false)
        #expect(builder.validateParameter("parallel", value: "9") == false)
    }
}

// MARK: - Required Parameter Tests

@Suite("Network Tool Required Parameter Tests")
struct NetworkToolRequiredParameterTests {
    @Test("dicom-send is invalid without required files")
    func testSendInvalidWithoutFiles() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomSend)
        #expect(builder.isValid(values: [:]) == false)
    }

    @Test("dicom-send is valid with required files")
    func testSendValidWithFiles() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomSend)
        #expect(builder.isValid(values: ["paths": "scan.dcm"]) == true)
    }

    @Test("dicom-retrieve is invalid without required output")
    func testRetrieveInvalidWithoutOutput() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomRetrieve)
        #expect(builder.isValid(values: ["study-uid": "1.2.3"]) == false)
    }

    @Test("dicom-retrieve is valid with required output")
    func testRetrieveValidWithOutput() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomRetrieve)
        #expect(builder.isValid(values: ["output": "/output"]) == true)
    }

    @Test("dicom-wado retrieve is invalid without required study UID")
    func testWadoRetrieveInvalidWithoutStudy() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomWado)
        #expect(builder.isValid(values: [:], subcommand: "retrieve") == false)
    }

    @Test("dicom-wado retrieve is valid with required study UID")
    func testWadoRetrieveValidWithStudy() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomWado)
        #expect(builder.isValid(values: ["study": "1.2.3"], subcommand: "retrieve") == true)
    }

    @Test("dicom-mpps create is invalid without required study UID")
    func testMPPSCreateInvalidWithoutStudyUID() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomMPPS)
        #expect(builder.isValid(values: [:], subcommand: "create") == false)
    }

    @Test("dicom-mpps create is valid with required study UID")
    func testMPPSCreateValidWithStudyUID() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomMPPS)
        #expect(builder.isValid(values: ["study-uid": "1.2.3"], subcommand: "create") == true)
    }
}
