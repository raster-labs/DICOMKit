import Foundation
import Testing
@testable import DICOMToolbox

// MARK: - dicom-split Command Generation Tests

@Suite("DicomSplit Command Generation Tests")
struct DicomSplitCommandTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomSplit)
    }

    @Test("Basic dicom-split command with required parameters")
    func testBasicCommand() {
        let command = builder.buildCommand(values: [
            "input": "multi.dcm",
        ])
        #expect(command.contains("dicom-split"))
        #expect(command.contains("multi.dcm"))
    }

    @Test("dicom-split with output directory")
    func testWithOutput() {
        let command = builder.buildCommand(values: [
            "input": "multi.dcm",
            "output": "/output/frames",
        ])
        #expect(command.contains("--output /output/frames"))
    }

    @Test("dicom-split with frame range")
    func testWithFrameRange() {
        let command = builder.buildCommand(values: [
            "input": "multi.dcm",
            "frames": "1-10",
        ])
        #expect(command.contains("--frames 1-10"))
    }

    @Test("dicom-split with format")
    func testWithFormat() {
        let command = builder.buildCommand(values: [
            "input": "multi.dcm",
            "format": "png",
        ])
        #expect(command.contains("--format png"))
    }
}

// MARK: - dicom-split Frame Range Parsing Tests

@Suite("DicomSplit Frame Range Tests")
struct DicomSplitFrameRangeTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomSplit)
    }

    @Test("dicom-split format has 3 options")
    func testFormatOptionCount() {
        let tool = ToolRegistry.dicomSplit
        let formatParam = tool.parameters.first { $0.id == "format" }
        #expect(formatParam != nil)
        #expect(formatParam?.enumValues?.count == 3)
    }

    @Test("dicom-split format includes DICOM, PNG, JPEG")
    func testFormatValues() {
        let tool = ToolRegistry.dicomSplit
        let formatParam = tool.parameters.first { $0.id == "format" }
        let values = formatParam?.enumValues?.map(\.value) ?? []
        #expect(values.contains("dicom"))
        #expect(values.contains("png"))
        #expect(values.contains("jpeg"))
    }

    @Test("dicom-split with complex frame range")
    func testComplexFrameRange() {
        let command = builder.buildCommand(values: [
            "input": "multi.dcm",
            "frames": "1-5,8,10-15",
        ])
        #expect(command.contains("--frames 1-5,8,10-15"))
    }

    @Test("dicom-split with recursive flag")
    func testWithRecursive() {
        let command = builder.buildCommand(values: [
            "input": "multi.dcm",
            "recursive": "true",
        ])
        #expect(command.contains("--recursive"))
    }
}

// MARK: - dicom-merge Command Generation Tests

@Suite("DicomMerge Command Generation Tests")
struct DicomMergeCommandTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomMerge)
    }

    @Test("Basic dicom-merge command")
    func testBasicCommand() {
        let command = builder.buildCommand(values: [
            "inputs": "file1.dcm",
            "output": "merged.dcm",
        ])
        #expect(command.contains("dicom-merge"))
        #expect(command.contains("file1.dcm"))
        #expect(command.contains("--output merged.dcm"))
    }

    @Test("dicom-merge with sort option")
    func testWithSort() {
        let command = builder.buildCommand(values: [
            "inputs": "file1.dcm",
            "output": "merged.dcm",
            "sort-by": "InstanceNumber",
        ])
        #expect(command.contains("--sort-by InstanceNumber"))
    }

    @Test("dicom-merge with validate flag")
    func testWithValidate() {
        let command = builder.buildCommand(values: [
            "inputs": "file1.dcm",
            "output": "merged.dcm",
            "validate": "true",
        ])
        #expect(command.contains("--validate"))
    }

    @Test("dicom-merge with recursive flag")
    func testWithRecursive() {
        let command = builder.buildCommand(values: [
            "inputs": "file1.dcm",
            "output": "merged.dcm",
            "recursive": "true",
        ])
        #expect(command.contains("--recursive"))
    }

    @Test("dicom-merge with all parameters")
    func testWithAllParameters() {
        let command = builder.buildCommand(values: [
            "inputs": "file1.dcm",
            "output": "merged.dcm",
            "format": "dicom",
            "sort-by": "SliceLocation",
            "validate": "true",
            "recursive": "true",
        ])
        #expect(command.contains("dicom-merge"))
        #expect(command.contains("file1.dcm"))
        #expect(command.contains("--output merged.dcm"))
        #expect(command.contains("--format dicom"))
        #expect(command.contains("--sort-by SliceLocation"))
        #expect(command.contains("--validate"))
        #expect(command.contains("--recursive"))
    }
}

// MARK: - dicom-dcmdir Command Generation Tests

@Suite("DicomDcmdir Command Generation Tests")
struct DicomDcmdirCommandTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomDcmdir)
    }

    @Test("dicom-dcmdir create subcommand")
    func testCreateSubcommand() {
        let command = builder.buildCommand(
            values: ["input": "/dicom/dir"],
            subcommand: "create"
        )
        #expect(command.contains("dicom-dcmdir"))
        #expect(command.contains("create"))
        #expect(command.contains("/dicom/dir"))
    }

    @Test("dicom-dcmdir create with output")
    func testCreateWithOutput() {
        let command = builder.buildCommand(
            values: [
                "input": "/dicom/dir",
                "output": "DICOMDIR",
            ],
            subcommand: "create"
        )
        #expect(command.contains("create"))
        #expect(command.contains("--output DICOMDIR"))
    }

    @Test("dicom-dcmdir validate subcommand")
    func testValidateSubcommand() {
        let command = builder.buildCommand(
            values: ["input": "DICOMDIR"],
            subcommand: "validate"
        )
        #expect(command.contains("dicom-dcmdir"))
        #expect(command.contains("validate"))
        #expect(command.contains("DICOMDIR"))
    }

    @Test("dicom-dcmdir dump subcommand")
    func testDumpSubcommand() {
        let command = builder.buildCommand(
            values: ["input": "DICOMDIR"],
            subcommand: "dump"
        )
        #expect(command.contains("dicom-dcmdir"))
        #expect(command.contains("dump"))
        #expect(command.contains("DICOMDIR"))
    }
}

// MARK: - dicom-dcmdir Subcommand Tests

@Suite("DicomDcmdir Subcommand Tests")
struct DicomDcmdirSubcommandTests {
    @Test("dicom-dcmdir has 3 subcommands")
    func testSubcommandCount() {
        let tool = ToolRegistry.dicomDcmdir
        #expect(tool.subcommands?.count == 3)
    }

    @Test("Subcommands are in correct order")
    func testSubcommandOrder() {
        let tool = ToolRegistry.dicomDcmdir
        let ids = tool.subcommands?.map(\.id) ?? []
        #expect(ids == ["create", "validate", "dump"])
    }

    @Test("Create subcommand has required input")
    func testCreateRequiredInput() {
        let tool = ToolRegistry.dicomDcmdir
        let createSub = tool.subcommands?.first { $0.id == "create" }
        let inputParam = createSub?.parameters.first { $0.id == "input" }
        #expect(inputParam?.isRequired == true)
    }

    @Test("Validate subcommand has only input parameter")
    func testValidateMinimalParams() {
        let tool = ToolRegistry.dicomDcmdir
        let validateSub = tool.subcommands?.first { $0.id == "validate" }
        #expect(validateSub?.parameters.count == 1)
        #expect(validateSub?.parameters.first?.id == "input")
    }
}

// MARK: - dicom-json Command Generation Tests

@Suite("DicomJson Command Generation Tests")
struct DicomJsonCommandTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomJson)
    }

    @Test("Basic dicom-json command")
    func testBasicCommand() {
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
        ])
        #expect(command.contains("dicom-json"))
        #expect(command.contains("scan.dcm"))
    }

    @Test("dicom-json with reverse mode")
    func testReverseMode() {
        let command = builder.buildCommand(values: [
            "input": "data.json",
            "output": "output.dcm",
            "reverse": "true",
        ])
        #expect(command.contains("--reverse"))
        #expect(command.contains("data.json"))
        #expect(command.contains("--output output.dcm"))
    }

    @Test("dicom-json reverse mode disabled not in command")
    func testReverseModeDisabled() {
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
            "reverse": "",
        ])
        #expect(!command.contains("--reverse"))
    }
}

// MARK: - dicom-json Output Model Tests

@Suite("DicomJson Output Model Tests")
struct DicomJsonFormatTests {
    @Test("dicom-json does not expose the removed no-op format option")
    func testRemovedFormatIsAbsent() {
        let tool = ToolRegistry.dicomJson
        #expect(tool.parameters.allSatisfy { $0.id != "format" })
    }

    @Test("legacy format input cannot reintroduce an unsupported CLI flag")
    func testLegacyFormatValueIsIgnored() {
        let command = CommandBuilder(tool: ToolRegistry.dicomJson).buildCommand(values: [
            "input": "scan.dcm",
            "format": "standard",
        ])
        #expect(command.contains("scan.dcm"))
        #expect(!command.contains("--format"))
    }

    @Test("dicom-json with pretty print and metadata-only")
    func testWithOptions() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomJson)
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
            "pretty": "true",
            "metadata-only": "true",
        ])
        #expect(command.contains("--pretty"))
        #expect(command.contains("--metadata-only"))
    }
}

// MARK: - dicom-xml Command Generation Tests

@Suite("DicomXml Command Generation Tests")
struct DicomXmlCommandTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomXml)
    }

    @Test("Basic dicom-xml command")
    func testBasicCommand() {
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
        ])
        #expect(command.contains("dicom-xml"))
        #expect(command.contains("scan.dcm"))
    }

    @Test("dicom-xml with reverse and output")
    func testWithReverseAndOutput() {
        let command = builder.buildCommand(values: [
            "input": "data.xml",
            "output": "output.dcm",
            "reverse": "true",
        ])
        #expect(command.contains("--reverse"))
        #expect(command.contains("--output output.dcm"))
    }

    @Test("dicom-xml with pretty print")
    func testWithPrettyPrint() {
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
            "pretty": "true",
        ])
        #expect(command.contains("--pretty"))
    }

    @Test("dicom-xml with no-keywords and metadata-only")
    func testWithNoKeywordsAndMetadata() {
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
            "no-keywords": "true",
            "metadata-only": "true",
        ])
        #expect(command.contains("--no-keywords"))
        #expect(command.contains("--metadata-only"))
    }
}

// MARK: - dicom-pdf Command Generation Tests

@Suite("DicomPdf Command Generation Tests")
struct DicomPdfCommandTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomPdf)
    }

    @Test("dicom-pdf encapsulate mode")
    func testEncapsulateMode() {
        let command = builder.buildCommand(values: [
            "input": "report.pdf",
            "output": "report.dcm",
            "patient-name": "SMITH^JOHN",
            "patient-id": "12345",
        ])
        #expect(command.contains("dicom-pdf"))
        #expect(command.contains("report.pdf"))
        #expect(command.contains("--output report.dcm"))
        #expect(command.contains("--patient-name 'SMITH^JOHN'"))
        #expect(command.contains("--patient-id 12345"))
    }

    @Test("dicom-pdf extract mode")
    func testExtractMode() {
        let command = builder.buildCommand(values: [
            "input": "report.dcm",
            "output": "extracted.pdf",
            "extract": "true",
        ])
        #expect(command.contains("--extract"))
        #expect(command.contains("report.dcm"))
        #expect(command.contains("--output extracted.pdf"))
    }

    @Test("dicom-pdf with show-metadata")
    func testWithShowMetadata() {
        let command = builder.buildCommand(values: [
            "input": "report.dcm",
            "output": "extracted.pdf",
            "show-metadata": "true",
        ])
        #expect(command.contains("--show-metadata"))
    }

    @Test("dicom-pdf extract disabled not in command")
    func testExtractDisabled() {
        let command = builder.buildCommand(values: [
            "input": "report.pdf",
            "output": "report.dcm",
            "extract": "",
        ])
        #expect(!command.contains("--extract"))
    }
}

// MARK: - dicom-image Command Generation Tests

@Suite("DicomImage Command Generation Tests")
struct DicomImageCommandTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomImage)
    }

    @Test("Basic dicom-image command")
    func testBasicCommand() {
        let command = builder.buildCommand(values: [
            "input": "photo.jpg",
            "output": "photo.dcm",
        ])
        #expect(command.contains("dicom-image"))
        #expect(command.contains("photo.jpg"))
        #expect(command.contains("--output photo.dcm"))
    }

    @Test("dicom-image with EXIF toggle")
    func testWithExif() {
        let command = builder.buildCommand(values: [
            "input": "photo.jpg",
            "output": "photo.dcm",
            "use-exif": "true",
        ])
        #expect(command.contains("--use-exif"))
    }

    @Test("dicom-image with EXIF disabled not in command")
    func testExifDisabled() {
        let command = builder.buildCommand(values: [
            "input": "photo.jpg",
            "output": "photo.dcm",
            "use-exif": "",
        ])
        #expect(!command.contains("--use-exif"))
    }
}

// MARK: - dicom-image Metadata Tests

@Suite("DicomImage Metadata Tests")
struct DicomImageMetadataTests {
    @Test("dicom-image with patient metadata")
    func testWithPatientMetadata() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomImage)
        let command = builder.buildCommand(values: [
            "input": "photo.jpg",
            "output": "photo.dcm",
            "patient-name": "DOE^JANE",
            "patient-id": "67890",
            "modality": "SC",
        ])
        #expect(command.contains("--patient-name 'DOE^JANE'"))
        #expect(command.contains("--patient-id 67890"))
        #expect(command.contains("--modality SC"))
    }

    @Test("dicom-image with recursive")
    func testWithRecursive() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomImage)
        let command = builder.buildCommand(values: [
            "input": "/images/",
            "output": "/dicom/",
            "recursive": "true",
        ])
        #expect(command.contains("--recursive"))
    }

    @Test("dicom-image with all parameters")
    func testWithAllParameters() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomImage)
        let command = builder.buildCommand(values: [
            "input": "photo.jpg",
            "output": "photo.dcm",
            "patient-name": "DOE^JANE",
            "patient-id": "67890",
            "modality": "OT",
            "use-exif": "true",
            "recursive": "true",
        ])
        #expect(command.contains("dicom-image"))
        #expect(command.contains("photo.jpg"))
        #expect(command.contains("--output photo.dcm"))
        #expect(command.contains("--patient-name 'DOE^JANE'"))
        #expect(command.contains("--patient-id 67890"))
        #expect(command.contains("--modality OT"))
        #expect(command.contains("--use-exif"))
        #expect(command.contains("--recursive"))
    }
}

// MARK: - dicom-export Command Generation Tests

@Suite("DicomExport Command Generation Tests")
struct DicomExportCommandTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomExport)
    }

    @Test("dicom-export single subcommand basic")
    func testSingleBasic() {
        let command = builder.buildCommand(
            values: [
                "input": "scan.dcm",
                "output": "scan.png",
            ],
            subcommand: "single"
        )
        #expect(command.contains("dicom-export"))
        #expect(command.contains("single"))
        #expect(command.contains("scan.dcm"))
        #expect(command.contains("--output scan.png"))
    }

    @Test("dicom-export single with format")
    func testSingleWithFormat() {
        let command = builder.buildCommand(
            values: [
                "input": "scan.dcm",
                "output": "scan.jpg",
                "format": "jpeg",
            ],
            subcommand: "single"
        )
        #expect(command.contains("single"))
        #expect(command.contains("--format jpeg"))
    }

    @Test("dicom-export bulk subcommand")
    func testBulk() {
        let command = builder.buildCommand(
            values: [
                "input": "/dicom/dir",
                "output": "/images/dir",
                "format": "png",
                "recursive": "true",
            ],
            subcommand: "bulk"
        )
        #expect(command.contains("dicom-export"))
        #expect(command.contains("bulk"))
        #expect(command.contains("/dicom/dir"))
        #expect(command.contains("--output /images/dir"))
        #expect(command.contains("--format png"))
        #expect(command.contains("--recursive"))
    }

    @Test("dicom-export single has 3 format options")
    func testSingleFormatCount() {
        let tool = ToolRegistry.dicomExport
        let singleSub = tool.subcommands?.first { $0.id == "single" }
        let formatParam = singleSub?.parameters.first { $0.id == "format" }
        #expect(formatParam?.enumValues?.count == 3)
    }

    @Test("dicom-export bulk has 2 format options")
    func testBulkFormatCount() {
        let tool = ToolRegistry.dicomExport
        let bulkSub = tool.subcommands?.first { $0.id == "bulk" }
        let formatParam = bulkSub?.parameters.first { $0.id == "format" }
        #expect(formatParam?.enumValues?.count == 2)
    }

    @Test("dicom-export has 2 subcommands")
    func testSubcommandCount() {
        let tool = ToolRegistry.dicomExport
        #expect(tool.subcommands?.count == 2)
    }

    @Test("dicom-export subcommands are in correct order")
    func testSubcommandOrder() {
        let tool = ToolRegistry.dicomExport
        let ids = tool.subcommands?.map(\.id) ?? []
        #expect(ids == ["single", "bulk"])
    }

    @Test("dicom-export single requires input and output")
    func testSingleRequired() {
        let tool = ToolRegistry.dicomExport
        let singleSub = tool.subcommands?.first { $0.id == "single" }
        let inputParam = singleSub?.parameters.first { $0.id == "input" }
        let outputParam = singleSub?.parameters.first { $0.id == "output" }
        #expect(inputParam?.isRequired == true)
        #expect(outputParam?.isRequired == true)
    }
}

// MARK: - dicom-pixedit Command Generation Tests

@Suite("DicomPixedit Command Generation Tests")
struct DicomPixeditCommandTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomPixedit)
    }

    @Test("Basic dicom-pixedit command")
    func testBasicCommand() {
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
            "output": "edited.dcm",
        ])
        #expect(command.contains("dicom-pixedit"))
        #expect(command.contains("scan.dcm"))
        #expect(command.contains("--output edited.dcm"))
    }

    @Test("dicom-pixedit with mask region")
    func testWithMaskRegion() {
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
            "output": "edited.dcm",
            "mask-region": "10,20,100,50",
        ])
        #expect(command.contains("--mask-region 10,20,100,50"))
    }

    @Test("dicom-pixedit with invalid format still generates command")
    func testWithRegionFormat() {
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
            "output": "edited.dcm",
            "mask-region": "0,0,256,256",
            "fill-value": "0",
        ])
        #expect(command.contains("--mask-region 0,0,256,256"))
        #expect(command.contains("--fill-value 0"))
    }
}

// MARK: - dicom-pixedit Region Format Tests

@Suite("DicomPixedit Region Format Tests")
struct DicomPixeditRegionTests {
    private var builder: CommandBuilder {
        CommandBuilder(tool: ToolRegistry.dicomPixedit)
    }

    @Test("dicom-pixedit with crop region")
    func testWithCropRegion() {
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
            "output": "cropped.dcm",
            "crop": "0,0,256,256",
        ])
        #expect(command.contains("--crop 0,0,256,256"))
    }

    @Test("dicom-pixedit with invert flag")
    func testWithInvert() {
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
            "output": "inverted.dcm",
            "invert": "true",
        ])
        #expect(command.contains("--invert"))
    }

    @Test("dicom-pixedit with all parameters")
    func testWithAllParameters() {
        let command = builder.buildCommand(values: [
            "input": "scan.dcm",
            "output": "edited.dcm",
            "mask-region": "10,20,100,50",
            "fill-value": "255",
            "crop": "0,0,512,512",
            "invert": "true",
        ])
        #expect(command.contains("dicom-pixedit"))
        #expect(command.contains("scan.dcm"))
        #expect(command.contains("--output edited.dcm"))
        #expect(command.contains("--mask-region 10,20,100,50"))
        #expect(command.contains("--fill-value 255"))
        #expect(command.contains("--crop 0,0,512,512"))
        #expect(command.contains("--invert"))
    }
}

// MARK: - Multi-file Drop Zone Tests

@Suite("Multi-file Drop Zone Tests")
struct MultiFileDropZoneTests {
    @Test("dicom-merge inputs parameter supports multi-file")
    func testMergeInputsParam() {
        let tool = ToolRegistry.dicomMerge
        let inputParam = tool.parameters.first { $0.id == "inputs" }
        #expect(inputParam != nil)
        #expect(inputParam?.type == .file)
        #expect(inputParam?.isRequired == true)
    }

    @Test("dicom-merge builds command with comma-separated inputs")
    func testMergeMultiFileCommand() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomMerge)
        let command = builder.buildCommand(values: [
            "inputs": "/path/to/file1.dcm",
            "output": "merged.dcm",
        ])
        #expect(command.contains("/path/to/file1.dcm"))
        #expect(command.contains("--output merged.dcm"))
    }

    @Test("dicom-split input parameter is file type")
    func testSplitInputType() {
        let tool = ToolRegistry.dicomSplit
        let inputParam = tool.parameters.first { $0.id == "input" }
        #expect(inputParam?.type == .file)
    }

    @Test("dicom-archive input parameter is file type")
    func testArchiveInputType() {
        let tool = ToolRegistry.dicomArchive
        let inputParam = tool.parameters.first { $0.id == "input" }
        #expect(inputParam?.type == .file)
    }
}

// MARK: - Required Parameter Validation Tests (Phase 4)

@Suite("Phase 4 Required Parameter Validation Tests")
struct Phase4RequiredParameterValidationTests {
    @Test("dicom-split requires input")
    func testSplitRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomSplit)
        #expect(!builder.isValid(values: [:]))
        #expect(builder.isValid(values: ["input": "multi.dcm"]))
    }

    @Test("dicom-merge requires inputs and output")
    func testMergeRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomMerge)
        #expect(!builder.isValid(values: [:]))
        #expect(!builder.isValid(values: ["inputs": "file1.dcm"]))
        #expect(!builder.isValid(values: ["output": "merged.dcm"]))
        #expect(builder.isValid(values: ["inputs": "file1.dcm", "output": "merged.dcm"]))
    }

    @Test("dicom-archive requires input and output")
    func testArchiveRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomArchive)
        #expect(!builder.isValid(values: [:]))
        #expect(!builder.isValid(values: ["input": "dir"]))
        #expect(builder.isValid(values: ["input": "dir", "output": "archive.zip"]))
    }

    @Test("dicom-json requires input")
    func testJsonRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomJson)
        #expect(!builder.isValid(values: [:]))
        #expect(builder.isValid(values: ["input": "scan.dcm"]))
    }

    @Test("dicom-xml requires input")
    func testXmlRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomXml)
        #expect(!builder.isValid(values: [:]))
        #expect(builder.isValid(values: ["input": "scan.dcm"]))
    }

    @Test("dicom-pdf requires input and output")
    func testPdfRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomPdf)
        #expect(!builder.isValid(values: [:]))
        #expect(!builder.isValid(values: ["input": "report.pdf"]))
        #expect(builder.isValid(values: ["input": "report.pdf", "output": "report.dcm"]))
    }

    @Test("dicom-image requires input and output")
    func testImageRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomImage)
        #expect(!builder.isValid(values: [:]))
        #expect(!builder.isValid(values: ["input": "photo.jpg"]))
        #expect(builder.isValid(values: ["input": "photo.jpg", "output": "photo.dcm"]))
    }

    @Test("dicom-pixedit requires input and output")
    func testPixeditRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomPixedit)
        #expect(!builder.isValid(values: [:]))
        #expect(!builder.isValid(values: ["input": "scan.dcm"]))
        #expect(builder.isValid(values: ["input": "scan.dcm", "output": "edited.dcm"]))
    }

    @Test("dicom-dcmdir create requires input")
    func testDcmdirCreateRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomDcmdir)
        #expect(!builder.isValid(values: [:], subcommand: "create"))
        #expect(builder.isValid(values: ["input": "/dicom/dir"], subcommand: "create"))
    }

    @Test("dicom-export single requires input and output")
    func testExportSingleRequires() {
        let builder = CommandBuilder(tool: ToolRegistry.dicomExport)
        #expect(!builder.isValid(values: [:], subcommand: "single"))
        #expect(!builder.isValid(values: ["input": "scan.dcm"], subcommand: "single"))
        #expect(builder.isValid(values: ["input": "scan.dcm", "output": "scan.png"], subcommand: "single"))
    }
}

// MARK: - Help Content Tests (Phase 4)

@Suite("Phase 4 Help Content Tests")
struct Phase4HelpContentTests {
    @Test("All file organization tools have parameters with help text")
    func testFileOrgParamsHaveHelp() {
        let tools = ToolRegistry.tools(for: .fileOrganization)
        for tool in tools {
            for param in tool.parameters {
                #expect(!param.help.isEmpty, "Parameter \(param.id) in \(tool.id) should have help text")
            }
        }
    }

    @Test("All data export tools have parameters with help text")
    func testDataExportParamsHaveHelp() {
        let tools = ToolRegistry.tools(for: .dataExport)
        for tool in tools {
            for param in tool.parameters {
                #expect(!param.help.isEmpty, "Parameter \(param.id) in \(tool.id) should have help text")
            }
        }
    }

    @Test("All file organization tools have SF Symbol icons")
    func testFileOrgIcons() {
        let tools = ToolRegistry.tools(for: .fileOrganization)
        for tool in tools {
            #expect(!tool.icon.isEmpty, "Tool \(tool.id) should have an icon")
        }
    }

    @Test("All data export tools have SF Symbol icons")
    func testDataExportIcons() {
        let tools = ToolRegistry.tools(for: .dataExport)
        for tool in tools {
            #expect(!tool.icon.isEmpty, "Tool \(tool.id) should have an icon")
        }
    }
}

// MARK: - File Organization Tool Routing Tests

@Suite("File Organization Tool Routing Tests")
struct FileOrganizationToolRoutingTests {
    @Test("File Organization category has exactly 4 tools")
    func testFileOrgToolCount() {
        let tools = ToolRegistry.tools(for: .fileOrganization)
        #expect(tools.count == 4)
    }

    @Test("File Organization tools are in correct order")
    func testFileOrgToolOrder() {
        let tools = ToolRegistry.tools(for: .fileOrganization)
        #expect(tools[0].id == "dicom-split")
        #expect(tools[1].id == "dicom-merge")
        #expect(tools[2].id == "dicom-dcmdir")
        #expect(tools[3].id == "dicom-archive")
    }

    @Test("File Organization tools do not require network")
    func testNoNetworkRequired() {
        let tools = ToolRegistry.tools(for: .fileOrganization)
        for tool in tools {
            #expect(!tool.requiresNetwork, "Tool \(tool.id) should not require network")
        }
    }

    @Test("Only dicom-dcmdir has subcommands in File Organization")
    func testSubcommandPresence() {
        let tools = ToolRegistry.tools(for: .fileOrganization)
        for tool in tools {
            if tool.id == "dicom-dcmdir" {
                #expect(tool.subcommands != nil, "dicom-dcmdir should have subcommands")
            } else {
                #expect(tool.subcommands == nil, "Tool \(tool.id) should not have subcommands")
            }
        }
    }
}

// MARK: - Data Export Tool Routing Tests

@Suite("Data Export Tool Routing Tests")
struct DataExportToolRoutingTests {
    @Test("Data Export category has exactly 7 tools")
    func testDataExportToolCount() {
        let tools = ToolRegistry.tools(for: .dataExport)
        #expect(tools.count == 7)
    }

    @Test("Data Export tools are in correct order")
    func testDataExportToolOrder() {
        let tools = ToolRegistry.tools(for: .dataExport)
        #expect(tools[0].id == "dicom-json")
        #expect(tools[1].id == "dicom-xml")
        #expect(tools[2].id == "dicom-pdf")
        #expect(tools[3].id == "dicom-image")
        #expect(tools[4].id == "dicom-export")
        #expect(tools[5].id == "dicom-pixedit")
    }

    @Test("Only dicom-export has subcommands in Data Export")
    func testSubcommandPresence() {
        let tools = ToolRegistry.tools(for: .dataExport)
        for tool in tools {
            if tool.id == "dicom-export" {
                #expect(tool.subcommands != nil, "dicom-export should have subcommands")
            } else {
                #expect(tool.subcommands == nil, "Tool \(tool.id) should not have subcommands")
            }
        }
    }

    @Test("Data Export tools do not require network")
    func testNoNetworkRequired() {
        let tools = ToolRegistry.tools(for: .dataExport)
        for tool in tools {
            #expect(!tool.requiresNetwork, "Tool \(tool.id) should not require network")
        }
    }
}
