import Foundation
import XCTest
import DICOMPrintCommandSupport
@testable import DICOMStudio

final class M6PrintCommandCodecTests: XCTestCase {
    private let scu = CLIWorkshopPrintCatalog.parameters
    private var scp: [CLIParameterDefinition] { CLIWorkshopPrintSCPCatalog.parameters }
    private func form(_ values: [String: String]) -> [CLIParameterValue] {
        values.map { CLIParameterValue(parameterID: $0.key, stringValue: $0.value) }
    }
    private func dictionary(_ values: [CLIParameterValue]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.parameterID, $0.stringValue) })
    }
    private func command(_ arguments: [String]) -> String {
        arguments.map(CommandBuilderHelpers.shellEscape).joined(separator: " ")
    }
    private func importSCU(_ text: String) throws -> [CLIParameterValue] {
        try CLIWorkshopPrintCommandCodec.importCommand(text, toolID: "dicom-print", parameterDefinitions: scu)
    }
    private func scpID(_ flag: String, operation: String) throws -> String {
        try XCTUnwrap(scp.first { $0.flag == flag && ($0.visibleWhen?.values.contains(operation) ?? true) }?.id)
    }

    func testJSONListsAreLosslessAndMalformedInputIsRefused() throws {
        let strings = ["", " leading and trailing ", "semi;colon,comma", "雪", "ROW\\1,3", "a\nb\tc", "'\"$()", "-first"]
        XCTAssertEqual(try CLIWorkshopPrintCommandCodec.listValues(CLIWorkshopPrintCommandCodec.encodedList(strings)), strings)
        XCTAssertEqual(try CLIWorkshopPrintCommandCodec.listValues(""), [])
        XCTAssertEqual(try CLIWorkshopPrintCommandCodec.listValues("[]"), [])
        for invalid in ["one;two", "one,two", " ", "{}", "[1]", "[null]", "[\"unterminated]"] {
            XCTAssertThrowsError(try CLIWorkshopPrintCommandCodec.listValues(invalid))
        }
        XCTAssertThrowsError(try CLIWorkshopPrintCommandCodec.listValues("[\"\\u0000\"]"))
    }

    func testSCUArgumentSnapshotPreservesRepeatedValuesAndLeadingDashPaths() throws {
        let paths = ["-first.dcm", "space path/second; literal.dcm"]
        let annotations = [" first; line ", "ROW\\1,3", "O'Neil \"quote\" $()"]
        let values = form(["url": "pacs://localhost:11112", "aet": "APP", "paths": CLIWorkshopPrintCommandCodec.encodedList(paths),
            "annotate": CLIWorkshopPrintCommandCodec.encodedList(annotations), "annotationFormat": "FMT",
            "layout": "ROW\\1,3", "windowCenter": "-600.5", "windowWidth": "1200.25"])
        let argv = try CLIWorkshopPrintCommandCodec.arguments(toolID: "dicom-print", parameterValues: values, parameterDefinitions: scu)
        XCTAssertEqual(Array(argv.prefix(2)), ["dicom-print", "send"])
        let separator = try XCTUnwrap(argv.firstIndex(of: "--"))
        XCTAssertEqual(Array(argv.suffix(from: separator + 1)), ["pacs://localhost:11112"] + paths)
        XCTAssertTrue(argv.contains("--window-center=-600.5"))
        XCTAssertEqual(argv.enumerated().filter { $0.element == "--annotate" }.map { argv[$0.offset + 1] }, annotations)
        try PrintSCUCommand.validate(arguments: Array(argv.dropFirst()))
        let restored = dictionary(try importSCU(command(argv)))
        XCTAssertEqual(try CLIWorkshopPrintCommandCodec.listValues(restored["paths"]!), paths)
        XCTAssertEqual(try CLIWorkshopPrintCommandCodec.listValues(restored["annotate"]!), annotations)
        XCTAssertEqual(restored["layout"], "ROW\\1,3")
        XCTAssertEqual(restored["windowCenter"], "-600.5")
    }

    func testImportDefaultsAndBothShortAliasesRoundTrip() throws {
        let restored = dictionary(try importSCU("dicom-print pacs://localhost 'space file.dcm' --aet APP -vr --dry-run"))
        XCTAssertEqual(restored["operation"], "send")
        XCTAssertEqual(restored["recursive"], "true"); XCTAssertEqual(restored["verbose"], "true")
        XCTAssertEqual(restored["sendTimeout"], "60"); XCTAssertEqual(restored["queryTimeout"], "30")
        XCTAssertEqual(restored["dryRun"], "true"); XCTAssertEqual(restored["raw"], "false")
        XCTAssertEqual(restored["filmSize"], "14x17")
        let status = dictionary(try importSCU("dicom-print status pacs://localhost --aet APP -v --format=json"))
        XCTAssertEqual(status["operation"], "status"); XCTAssertEqual(status["format"], "json")
    }

    func testSCUStandardAliasesAndExactScalarStringsSurviveImport() throws {
        let text = "dicom-print send pacs://localhost x.dcm --aet APP --film-size 14INX17IN --priority MED --medium 'CLEAR FILM' --presentation-lut 'LIN OD'"
        let values = dictionary(try importSCU(text))
        XCTAssertEqual(values["filmSize"], "14INX17IN"); XCTAssertEqual(values["priority"], "MED")
        XCTAssertEqual(values["medium"], "CLEAR FILM"); XCTAssertEqual(values["presentationLut"], "LIN OD")
        let name = " leading; 'quoted' \\ 雪 "
        let added = dictionary(try importSCU(command(["dicom-print", "add-printer", "--name", name, "--host", "localhost", "--called-ae", "SCP"])))
        XCTAssertEqual(added["name"], name)
        let emptyAnnotation = dictionary(try importSCU("dicom-print send pacs://localhost x.dcm --aet APP --annotate '' --annotation-format FMT"))
        XCTAssertEqual(try CLIWorkshopPrintCommandCodec.listValues(emptyAnnotation["annotate"]!), [""])
    }

    func testSCPInheritAndExplicitInversionsRemainDifferent() throws {
        let defaultArgv = try CLIWorkshopPrintCommandCodec.arguments(toolID: "dicom-printscp", parameterValues: [], parameterDefinitions: scp)
        XCTAssertEqual(Array(defaultArgv.prefix(2)), ["dicom-printscp", "serve"])
        for flag in ["--accept-color", "--no-accept-color", "--presentation-lut", "--no-presentation-lut", "--annotations", "--no-annotations"] {
            XCTAssertFalse(defaultArgv.contains(flag))
        }
        let source = "dicom-printscp --no-accept-color --presentation-lut --no-annotation-box --no-annotations --trim-marks --allow-ae ' A;1 ' --allow-ae B"
        let values = try CLIWorkshopPrintCommandCodec.importCommand(source, toolID: "dicom-printscp", parameterDefinitions: scp)
        let restored = dictionary(values)
        XCTAssertEqual(restored[try scpID("--accept-color", operation: "serve")], "disabled")
        XCTAssertEqual(restored[try scpID("--presentation-lut", operation: "serve")], "enabled")
        XCTAssertEqual(restored[try scpID("--annotation-box", operation: "serve")], "disabled")
        XCTAssertEqual(try CLIWorkshopPrintCommandCodec.listValues(restored[try scpID("--allow-ae", operation: "serve")]!), [" A;1 ", "B"])
        let argv = try CLIWorkshopPrintCommandCodec.arguments(toolID: "dicom-printscp", parameterValues: values, parameterDefinitions: scp)
        XCTAssertTrue(argv.contains("--no-accept-color")); XCTAssertFalse(argv.contains("--accept-color"))
        XCTAssertFalse(argv.contains("--inherit"))
        try PrintSCPCommand.validate(arguments: Array(argv.dropFirst()))
    }

    func testSCPSimulateVariadicPathsAndRepeatedOutputsRemainOrdered() throws {
        let argv = ["dicom-printscp", "simulate", "--output", "png", "--output", "pdf", "--layout", "ROW\\1,3",
                    "--window-center=-600", "--window-width", "1200", "-r", "--", "-literal.dcm", "space; path.dcm"]
        let values = try CLIWorkshopPrintCommandCodec.importCommand(command(argv), toolID: "dicom-printscp", parameterDefinitions: scp)
        let restored = dictionary(values)
        let paths = try XCTUnwrap(scp.first { $0.flag.isEmpty && $0.isRepeatable }?.id)
        XCTAssertEqual(try CLIWorkshopPrintCommandCodec.listValues(restored[paths]!), ["-literal.dcm", "space; path.dcm"])
        XCTAssertEqual(try CLIWorkshopPrintCommandCodec.listValues(restored[try scpID("--output", operation: "simulate")]!), ["png", "pdf"])
    }

    func testHiddenValuesNeverLeakAcrossOperationsAndImportStartsFresh() throws {
        let supplied = form(["operation": "list-printers", "name": "stale", "host": "stale", "layout": "INVALID",
                             "paths": "not JSON", "windowCenter": "-600", "annotate": "not JSON"])
        let argv = try CLIWorkshopPrintCommandCodec.arguments(toolID: "dicom-print", parameterValues: supplied, parameterDefinitions: scu)
        XCTAssertFalse(argv.contains("stale")); XCTAssertFalse(argv.contains("--layout")); XCTAssertFalse(argv.contains("--window-center=-600"))
        try PrintSCUCommand.validate(arguments: Array(argv.dropFirst()))
        let restored = dictionary(try importSCU("dicom-print list-printers"))
        XCTAssertEqual(restored["name"], ""); XCTAssertEqual(restored["layout"], "")
        XCTAssertEqual(restored["windowCenter"], "")
    }

    func testStrictTokenizerPreservesPOSIXQuotingAndEscapedLiteralCharacters() throws {
        let examples: [(String, String)] = [
            (#"'single quoted; $() \ value'"#, "single quoted; $() \\ value"),
            (#""double quoted \"value\" \\ path""#, "double quoted \"value\" \\ path"),
            (#""ROW\1,3""#, "ROW\\1,3"),
            (#"'O'"'"'Neil'"#, "O'Neil"),
            (#"escaped\ space\;\$value"#, "escaped space;$value")
        ]
        for (quoted, expected) in examples {
            let values = dictionary(try importSCU("dicom-print add-printer --name " + quoted + " --host localhost --called-ae SCP"))
            XCTAssertEqual(values["name"], expected, quoted)
        }
    }

    func testShellOperatorsExpansionsAndBrokenQuotesAreRejectedWithoutEffects() throws {
        let base = "dicom-print list-printers"
        for suffix in ["; touch /tmp/m6-codec-must-not-run", " | cat", " && echo x", " > output.json", "\nother-command",
                       " --format $(echo json)", " --format `echo json`", " --format \"$FORMAT\"", " --format $FORMAT",
                       " --format ~", " --format *", " --format [abc]", " --format 'unterminated", " --format value\\"] {
            XCTAssertThrowsError(try importSCU(base + suffix), suffix)
        }
        XCTAssertThrowsError(try importSCU("dicom-print list-printers\0"))
    }

    func testWrongToolUnknownHiddenFlagsAndDuplicateScalarsRefuseAtomically() throws {
        let existing = form(["operation": "list-printers", "format": "json"])
        let before = dictionary(existing)
        for text in ["dicom-printscp status", "dicom-print list-printers --copies 2",
                     "dicom-print send pacs://localhost x.dcm --aet APP --no-raw",
                     "dicom-print status pacs://localhost --aet APP --aet OTHER",
                     "dicom-print status pacs://localhost --aet APP -v --verbose",
                     "dicom-print add-printer --name '' --host localhost --called-ae SCP"] {
            XCTAssertThrowsError(try importSCU(text), text)
            XCTAssertEqual(dictionary(existing), before)
        }
        let conflicted = "dicom-printscp serve --accept-color --no-accept-color"
        XCTAssertThrowsError(try CLIWorkshopPrintCommandCodec.importCommand(conflicted, toolID: "dicom-printscp", parameterDefinitions: scp))
    }

    func testInvalidVisibleListOrBooleanFailsBeforeArgumentPublication() throws {
        for extra in [["annotate": "bad;list"], ["raw": "maybe"], ["paths": "{}"]] {
            var values = ["url": "pacs://localhost", "aet": "APP", "paths": "[\"x.dcm\"]"]
            values.merge(extra) { _, new in new }
            XCTAssertThrowsError(try CLIWorkshopPrintCommandCodec.arguments(toolID: "dicom-print", parameterValues: form(values), parameterDefinitions: scu))
        }
        let duplicated = [CLIParameterValue(parameterID: "operation", stringValue: "list-printers"),
                          CLIParameterValue(parameterID: "operation", stringValue: "add-printer")]
        XCTAssertThrowsError(try CLIWorkshopPrintCommandCodec.arguments(toolID: "dicom-print", parameterValues: duplicated, parameterDefinitions: scu))
    }
}
