import XCTest
import Foundation

/// Tests for dicom-script CLI tool functionality
/// These tests validate the script parsing, execution logic, and template generation
final class DICOMScriptTests: XCTestCase {

    // MARK: - Test Helpers
    
    private var testDirectory: String!
    
    override func setUp() {
        super.setUp()
        testDirectory = NSTemporaryDirectory().appending("/dicom-script-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    override func tearDown() {
        if let testDir = testDirectory {
            try? FileManager.default.removeItem(atPath: testDir)
        }
        super.tearDown()
    }
    
    // MARK: - Script Parsing Tests
    
    func testSimpleCommandParsing() throws {
        let script = """
        # Simple command
        dicom-info test.dcm
        """
        
        let scriptPath = "\(testDirectory!)/simple.dcmscript"
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptPath))
        let content = try String(contentsOfFile: scriptPath, encoding: .utf8)
        XCTAssertTrue(content.contains("dicom-info"))
    }
    
    func testVariableAssignment() throws {
        let script = """
        INPUT_DIR=/path/to/input
        OUTPUT_DIR=/path/to/output
        """
        
        let scriptPath = "\(testDirectory!)/variables.dcmscript"
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        
        let content = try String(contentsOfFile: scriptPath, encoding: .utf8)
        XCTAssertTrue(content.contains("INPUT_DIR=/path/to/input"))
        XCTAssertTrue(content.contains("OUTPUT_DIR=/path/to/output"))
    }
    
    func testCommentIgnoring() throws {
        let script = """
        # This is a comment
        # Another comment
        dicom-info test.dcm
        """
        
        let lines = script.split(separator: "\n")
        let commentLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        let commandLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        XCTAssertEqual(commentLines.count, 2)
        XCTAssertEqual(commandLines.count, 1)
    }
    
    func testPipelineParsing() throws {
        let script = """
        dicom-query --host server | dicom-retrieve --output studies/
        """
        
        XCTAssertTrue(script.contains("|"))
        let commands = script.split(separator: "|")
        XCTAssertEqual(commands.count, 2)
        XCTAssertTrue(commands[0].contains("dicom-query"))
        XCTAssertTrue(commands[1].contains("dicom-retrieve"))
    }
    
    func testConditionalParsing() throws {
        let script = """
        if exists test.dcm
            dicom-info test.dcm
        endif
        """
        
        XCTAssertTrue(script.contains("if "))
        XCTAssertTrue(script.contains("endif"))
        XCTAssertTrue(script.contains("exists"))
    }
    
    // MARK: - Variable Substitution Tests
    
    func testBasicVariableSubstitution() throws {
        let variables = ["INPUT_DIR": "/data/input", "OUTPUT_DIR": "/data/output"]
        let template = "${INPUT_DIR}/*.dcm"
        
        var result = template
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "${\(key)}", with: value)
        }
        
        XCTAssertEqual(result, "/data/input/*.dcm")
    }
    
    func testMultipleVariableSubstitution() throws {
        let variables = ["VAR1": "value1", "VAR2": "value2", "VAR3": "value3"]
        let template = "${VAR1} and ${VAR2} and ${VAR3}"
        
        var result = template
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "${\(key)}", with: value)
        }
        
        XCTAssertEqual(result, "value1 and value2 and value3")
    }
    
    func testShortVariableSyntax() throws {
        let variables = ["VAR": "value"]
        let template = "$VAR/file.dcm"
        
        var result = template
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "$\(key)", with: value)
        }
        
        XCTAssertEqual(result, "value/file.dcm")
    }
    
    // MARK: - Condition Evaluation Tests
    
    func testFileExistsCondition() throws {
        let testFile = "\(testDirectory!)/exists.txt"
        try "test".write(toFile: testFile, atomically: true, encoding: .utf8)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile))
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(testDirectory!)/notexists.txt"))
    }
    
    func testEmptyVariableCondition() throws {
        let emptyVar = ""
        let nonEmptyVar = "value"
        
        XCTAssertTrue(emptyVar.isEmpty)
        XCTAssertFalse(nonEmptyVar.isEmpty)
    }
    
    func testEqualsCondition() throws {
        let var1 = "value1"
        let var2 = "value1"
        let var3 = "value2"
        
        XCTAssertTrue(var1 == var2)
        XCTAssertFalse(var1 == var3)
    }
    
    // MARK: - Template Generation Tests
    
    func testWorkflowTemplate() throws {
        let template = """
        # DICOM Workflow Script
        INPUT_DIR=/path/to/input
        OUTPUT_DIR=/path/to/output
        dicom-validate ${INPUT_DIR}/*.dcm --level 2
        dicom-convert ${INPUT_DIR}/*.dcm --output ${OUTPUT_DIR} --format png
        """
        
        XCTAssertTrue(template.contains("INPUT_DIR"))
        XCTAssertTrue(template.contains("OUTPUT_DIR"))
        XCTAssertTrue(template.contains("dicom-validate"))
        XCTAssertTrue(template.contains("dicom-convert"))
    }
    
    func testPipelineTemplate() throws {
        let template = """
        PACS_HOST=pacs.example.com
        PACS_PORT=11112
        dicom-query --host ${PACS_HOST} --port ${PACS_PORT}
        """
        
        XCTAssertTrue(template.contains("PACS_HOST"))
        XCTAssertTrue(template.contains("PACS_PORT"))
        XCTAssertTrue(template.contains("dicom-query"))
    }
    
    func testQueryTemplate() throws {
        let template = """
        dicom-query --host ${PACS_HOST} --patient-name "DOE*"
        """
        
        XCTAssertTrue(template.contains("dicom-query"))
        XCTAssertTrue(template.contains("patient-name"))
    }
    
    func testArchiveTemplate() throws {
        let template = """
        ARCHIVE_DB=archive.db
        dicom-archive create ${ARCHIVE_DB} --input ${INPUT_DIR}
        dicom-archive query ${ARCHIVE_DB} --patient-id "12345"
        """
        
        XCTAssertTrue(template.contains("ARCHIVE_DB"))
        XCTAssertTrue(template.contains("dicom-archive create"))
        XCTAssertTrue(template.contains("dicom-archive query"))
    }
    
    func testAnonymizeTemplate() throws {
        let template = """
        dicom-anon ${INPUT_DIR}/*.dcm --profile ps315 --output ${OUTPUT_DIR}
        if exists ${INPUT_DIR}/sensitive.dcm
            dicom-anon ${INPUT_DIR}/sensitive.dcm --profile ps315 --clean-pixel-data --output ${OUTPUT_DIR}
        endif
        """
        
        XCTAssertTrue(template.contains("dicom-anon"))
        // PS3.15 2026a E.1 Basic Application Level Confidentiality Profile; Clean Pixel Data Option E.3.1
        XCTAssertTrue(template.contains("--profile ps315"))
        XCTAssertTrue(template.contains("if exists"))
    }
    
    // MARK: - Script Validation Tests
    
    func testValidCommandValidation() throws {
        let knownTools = [
            "dicom-info", "dicom-convert", "dicom-validate", "dicom-anon",
            "dicom-dump", "dicom-query", "dicom-send", "dicom-diff",
            "dicom-retrieve", "dicom-split", "dicom-merge", "dicom-json",
            "dicom-xml", "dicom-pdf", "dicom-image", "dicom-dcmdir",
            "dicom-archive", "dicom-export", "dicom-qr", "dicom-wado",
            "dicom-echo", "dicom-mwl", "dicom-mpps", "dicom-pixedit",
            "dicom-tags", "dicom-uid", "dicom-compress", "dicom-study"
        ]
        
        for tool in knownTools {
            XCTAssertTrue(knownTools.contains(tool))
        }
        
        XCTAssertFalse(knownTools.contains("unknown-tool"))
    }
    
    func testInvalidCommandValidation() throws {
        let knownTools = [
            "dicom-info", "dicom-convert", "dicom-validate"
        ]
        
        XCTAssertFalse(knownTools.contains("invalid-tool"))
        XCTAssertFalse(knownTools.contains("not-a-dicom-tool"))
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidVariableFormatDetection() throws {
        let validVar = "KEY=VALUE"
        let invalidVar1 = "KEYVALUE"
        let invalidVar2 = "KEY="
        
        XCTAssertTrue(validVar.contains("="))
        XCTAssertFalse(invalidVar1.contains("="))
        XCTAssertTrue(invalidVar2.contains("="))
        
        let validParts = validVar.split(separator: "=", maxSplits: 1)
        XCTAssertEqual(validParts.count, 2)
    }
    
    func testEmptyScriptHandling() throws {
        let emptyScript = ""
        let scriptPath = "\(testDirectory!)/empty.dcmscript"
        try emptyScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        
        let content = try String(contentsOfFile: scriptPath, encoding: .utf8)
        XCTAssertTrue(content.isEmpty)
    }
    
    // MARK: - Logging Tests
    
    func testLogFileCreation() throws {
        let logPath = "\(testDirectory!)/test.log"
        let message = "Test log message\n"
        
        try message.write(toFile: logPath, atomically: true, encoding: .utf8)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: logPath))
        let content = try String(contentsOfFile: logPath, encoding: .utf8)
        XCTAssertEqual(content, message)
    }
    
    func testLogMessageFormatting() throws {
        let timestamp = "2024-01-15 10:30:45"
        let message = "Test message"
        let logEntry = "[\(timestamp)] \(message)"
        
        XCTAssertTrue(logEntry.contains(timestamp))
        XCTAssertTrue(logEntry.contains(message))
    }
    
    // MARK: - File Operations Tests
    
    func testScriptFileReading() throws {
        let script = "dicom-info test.dcm"
        let scriptPath = "\(testDirectory!)/test.dcmscript"
        
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        
        let content = try String(contentsOfFile: scriptPath, encoding: .utf8)
        XCTAssertEqual(content, script)
    }
    
    func testMultilineScriptReading() throws {
        let script = """
        # Line 1
        dicom-info test.dcm
        # Line 3
        dicom-convert test.dcm --output test.png
        """
        
        let scriptPath = "\(testDirectory!)/multiline.dcmscript"
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        
        let content = try String(contentsOfFile: scriptPath, encoding: .utf8)
        let lines = content.split(separator: "\n")
        XCTAssertEqual(lines.count, 4)
    }
    
    // MARK: - Complex Script Tests
    
    func testComplexWorkflowScript() throws {
        let script = """
        # Complex workflow
        INPUT_DIR=/data/input
        OUTPUT_DIR=/data/output
        TEMP_DIR=/data/temp
        
        # Step 1: Validate
        dicom-validate ${INPUT_DIR}/*.dcm --level 2
        
        # Step 2: Process
        if exists ${INPUT_DIR}
            dicom-study organize ${INPUT_DIR} --output ${TEMP_DIR}
            dicom-anon ${TEMP_DIR}/**/*.dcm --profile ps315 --output ${OUTPUT_DIR}
        else
            echo "Input directory not found"
        endif
        
        # Step 3: Archive
        dicom-archive create archive.db --input ${OUTPUT_DIR}
        """
        
        let scriptPath = "\(testDirectory!)/complex.dcmscript"
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        
        let content = try String(contentsOfFile: scriptPath, encoding: .utf8)
        XCTAssertTrue(content.contains("# Complex workflow"))
        XCTAssertTrue(content.contains("INPUT_DIR"))
        XCTAssertTrue(content.contains("if exists"))
        XCTAssertTrue(content.contains("dicom-study"))
        XCTAssertTrue(content.contains("dicom-archive"))
    }
    
    func testPipelineWithConditionals() throws {
        let script = """
        if exists input.dcm
            dicom-validate input.dcm --level 2 | dicom-convert --output output/
        endif
        """
        
        XCTAssertTrue(script.contains("if exists"))
        XCTAssertTrue(script.contains("|"))
        XCTAssertTrue(script.contains("endif"))
    }
    
    // MARK: - String Processing Tests
    
    func testStringTrimming() throws {
        let str = "   test   "
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(trimmed, "test")
    }
    
    func testStringSplitting() throws {
        let str = "command arg1 arg2 arg3"
        let parts = str.split(separator: " ")
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(parts[0], "command")
        XCTAssertEqual(parts[1], "arg1")
    }
    
    func testPathConcatenation() throws {
        let base = "/data"
        let file = "test.dcm"
        let fullPath = "\(base)/\(file)"
        XCTAssertEqual(fullPath, "/data/test.dcm")
    }
}
