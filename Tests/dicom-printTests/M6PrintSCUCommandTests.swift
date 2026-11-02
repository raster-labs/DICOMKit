import Foundation
import XCTest
import ArgumentParser
import DICOMNetwork
import DICOMPrintKit
@testable import DICOMPrintCommandSupport

final class M6PrintSCUCommandTests: XCTestCase {
    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var outputLines: [String] = []
        private var diagnosticLines: [String] = []
        func output(_ line: String) { lock.lock(); defer { lock.unlock() }; outputLines.append(line) }
        func diagnostic(_ line: String) { lock.lock(); defer { lock.unlock() }; diagnosticLines.append(line) }
        var output: [String] { lock.lock(); defer { lock.unlock() }; return outputLines }
        var diagnostics: [String] { lock.lock(); defer { lock.unlock() }; return diagnosticLines }
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("m6-scu-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func context(_ root: URL, _ capture: Capture = Capture()) -> PrintCommandContext {
        PrintCommandContext(printersURL: root.appendingPathComponent("printers.json"),
            defaultSCPConfigURL: root.appendingPathComponent("unused-scp.json"),
            output: { capture.output($0) }, diagnostic: { capture.diagnostic($0) })
    }

    func testAllSixCommandsAndDefaultSendUseTheSharedParser() throws {
        let cases = [
            ["status", "pacs://localhost:11112", "--aet", "APP"],
            ["send", "pacs://localhost:11112", "image.dcm", "--aet", "APP"],
            ["job", "pacs://localhost:11112", "--aet", "APP", "--job-id", "2.25.6"],
            ["list-printers"],
            ["add-printer", "--name", "synthetic", "--host", "localhost", "--called-ae", "PRINTER"],
            ["remove-printer", "--name", "synthetic"]
        ]
        for args in cases {
            XCTAssertNoThrow(try PrintSCUCommand.validate(arguments: args), args.joined(separator: " "))
            XCTAssertThrowsError(try PrintSCUCommand.validate(arguments: args + ["--not-a-print-option"]))
        }
        for args in [["status"], ["send"], ["job", "pacs://localhost", "--aet", "APP"],
                     ["add-printer", "--name", "synthetic"], ["remove-printer"]] {
            XCTAssertThrowsError(try PrintSCUCommand.validate(arguments: args))
        }
        let implicit = try PrintSCUCommand.parseAsRoot(["pacs://localhost", "image.dcm", "--aet", "APP"])
        let send = try XCTUnwrap(implicit as? SCUSendCommand)
        XCTAssertEqual(send.paths, ["image.dcm"])
        XCTAssertEqual(send.timeout, 60)
        XCTAssertEqual(try SCUStatusCommand.parse(["pacs://localhost", "--aet", "APP"]).timeout, 30)
    }

    func testSendMapsEveryCurrentControlAndPreservesLiteralRepeatedValues() throws {
        let annotations = ["first; literal, value", "second 'quote' \\ slash"]
        let args = ["pacs://127.0.0.1:11112", "space path/one.dcm", "second;literal.dcm", "--aet", "APP",
            "--called-aet", "SCP", "--copies", "2", "--film-size", "A4", "--orientation", "LANDSCAPE",
            "--priority", "HIGH", "--layout", "ROW\\1,3", "--medium", "MAMMO BLUE FILM", "--magnification", "CUBIC",
            "--film-destination", "BIN_42", "--check-status", "--verify", "--format", "json", "--color", "color",
            "--frame", "1", "--all-frames", "--window-center=-600.25", "--window-width", "1200.5",
            "--bit-depth", "12", "--presentation-lut", "IDENTITY", "--palette", "hot-metal-blue",
            "--annotate", annotations[0], "--annotate", annotations[1], "--annotation-format", "FMT_1",
            "--recursive", "--dry-run", "--verbose", "--timeout", "7", "--retries", "2"]
        let command = try SCUSendCommand.parse(args)
        let request = try command.makeRequest()
        XCTAssertEqual(command.paths, ["space path/one.dcm", "second;literal.dcm"])
        XCTAssertEqual(command.aet, "APP"); XCTAssertEqual(command.calledAet, "SCP")
        XCTAssertEqual(command.timeout, 7); XCTAssertEqual(command.format, .json)
        XCTAssertTrue(command.recursive); XCTAssertTrue(command.verbose)
        XCTAssertEqual(request.copies, 2); XCTAssertEqual(request.priority.rawValue, "HIGH")
        XCTAssertEqual(request.filmSize.rawValue, "A4"); XCTAssertEqual(request.filmOrientation.rawValue, "LANDSCAPE")
        XCTAssertEqual(request.mediumType.wireValue, "MAMMO BLUE FILM")
        XCTAssertEqual(request.magnificationType.rawValue, "CUBIC")
        XCTAssertEqual(request.filmDestination.rawValue, "BIN_42")
        XCTAssertEqual(request.layoutSelection.imageDisplayFormat?.raw, "ROW\\1,3")
        XCTAssertTrue(request.verifyFirst); XCTAssertTrue(request.checkStatus)
        XCTAssertEqual(request.colorMode, .color); XCTAssertEqual(request.frameSelection, .all)
        XCTAssertFalse(request.raw); XCTAssertEqual(request.windowSettings?.center, -600.25)
        XCTAssertEqual(request.windowSettings?.width, 1200.5); XCTAssertEqual(request.bitDepth, 12)
        XCTAssertEqual(request.presentationLUTShape?.wireValue, "IDENTITY"); XCTAssertNotNil(request.palette)
        XCTAssertEqual(request.annotations.map(\.text), annotations)
        XCTAssertEqual(request.annotations.map(\.position), [1, 2])
        XCTAssertEqual(request.annotationDisplayFormatID, "FMT_1")
        XCTAssertEqual(request.retries, 2); XCTAssertTrue(request.dryRun)
        let raw = try SCUSendCommand.parse(["pacs://localhost", "x.dcm", "--aet", "APP", "--raw"])
        XCTAssertTrue(try raw.makeRequest().raw)
        for name in ["single", "comparison", "grid", "multi-phase"] {
            let preset = try SCUSendCommand.parse(["pacs://localhost", "x.dcm", "--aet", "APP", "--template", name])
            XCTAssertNotNil(preset.template)
            XCTAssertNotNil(try preset.makeRequest().layoutSelection.layout)
        }
    }

    func testSemanticValidationRefusesInvalidCombinationsBeforeEffects() throws {
        let base = ["send", "pacs://localhost", "x.dcm", "--aet", "APP"]
        for invalid in [
            ["--layout", "1x1", "--template", "single"], ["--all-frames", "--frame", "2"],
            ["--window-center=-600"], ["--window-width", "400"], ["--copies", "0"],
            ["--frame", "0"], ["--retries=-1"], ["--annotate", "requires format"], ["--no-raw"],
            ["--film-size", "15x15"], ["--layout", "DIAGONAL\\2"], ["--film-destination", "BIN_00"]
        ] {
            XCTAssertThrowsError(try PrintSCUCommand.validate(arguments: base + invalid), invalid.joined(separator: " "))
        }
        for url in ["http://localhost", "pacs://localhost:0", "pacs://localhost:65536"] {
            XCTAssertThrowsError(try PrintSCUCommand.validate(arguments: ["status", url, "--aet", "APP"]))
        }
        var overflow = try SCUSendCommand.parse(Array(base.dropFirst()))
        overflow.annotate = Array(repeating: "x", count: Int(UInt16.max) + 1)
        XCTAssertThrowsError(try overflow.makeRequest(), "Annotation count cannot trap in UInt16 conversion")
    }

    func testRegistryPersistenceDefaultReplacementAndExactNames() async throws {
        let root = try directory(), capture = Capture(), ctx = context(root, capture)
        let first = "Printer; A, 'quoted' \\ 雪"
        try await PrintSCUCommand.execute(arguments: ["add-printer", "--name", first, "--host", "127.0.0.1",
            "--port", "11112", "--called-ae", "FIRST", "--calling-ae", "APP", "--default"], context: ctx)
        try await PrintSCUCommand.execute(arguments: ["add-printer", "--name", "second", "--host", "localhost",
            "--called-ae", "SECOND", "--color", "color", "--default"], context: ctx)
        let freshCapture = Capture()
        try await PrintSCUCommand.execute(arguments: ["list-printers", "--format", "json"], context: context(root, freshCapture))
        let json = try XCTUnwrap(freshCapture.output.last)
        let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(objects.map { $0["name"] as? String }, [first, "second"])
        XCTAssertEqual(objects.map { $0["isDefault"] as? Bool }, [false, true])
        XCTAssertEqual(objects[0]["callingAETitle"] as? String, "APP")
        XCTAssertEqual(objects[1]["colorMode"] as? String, "color")
        XCTAssertTrue(freshCapture.diagnostics.isEmpty)
        let before = try Data(contentsOf: ctx.printersURL)
        do {
            try await PrintSCUCommand.execute(arguments: ["add-printer", "--name", first, "--host", "elsewhere", "--called-ae", "NEW"], context: ctx)
            XCTFail("Duplicate name must be refused")
        } catch { XCTAssertTrue(String(describing: error).contains("already exists")) }
        XCTAssertEqual(try Data(contentsOf: ctx.printersURL), before)
        do {
            try await PrintSCUCommand.execute(arguments: ["remove-printer", "--name", "missing"], context: ctx)
            XCTFail("Missing name must be refused")
        } catch { XCTAssertTrue(String(describing: error).contains("not found")) }
        XCTAssertEqual(try Data(contentsOf: ctx.printersURL), before)
        try await PrintSCUCommand.execute(arguments: ["remove-printer", "--name", "second"], context: ctx)
        let remaining = try JSONDecoder().decode([SCUSavedPrinterConfig].self, from: Data(contentsOf: ctx.printersURL))
        XCTAssertEqual(remaining.map(\.name), [first]); XCTAssertFalse(remaining[0].isDefault)
    }

    func testEmptyPrinterJSONForAbsentEmptyAndLastRemovedRegistries() async throws {
        for scenario in ["absent", "empty", "last-removed"] {
            let root = try directory(), setup = context(root)
            if scenario == "empty" {
                try Data("[]\n".utf8).write(to: setup.printersURL)
            } else if scenario == "last-removed" {
                try await PrintSCUCommand.execute(arguments: ["add-printer", "--name", "last", "--host", "localhost",
                    "--called-ae", "SYNTHETIC"], context: setup)
                try await PrintSCUCommand.execute(arguments: ["remove-printer", "--name", "last"], context: setup)
            }
            let before = try? Data(contentsOf: setup.printersURL)
            let jsonCapture = Capture()
            try await PrintSCUCommand.execute(arguments: ["list-printers", "--format", "json"],
                context: context(root, jsonCapture))
            XCTAssertEqual(jsonCapture.output.count, 1, scenario)
            let json = try XCTUnwrap(jsonCapture.output.first, scenario)
            let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any], scenario)
            XCTAssertTrue(entries.isEmpty, scenario)
            XCTAssertTrue(jsonCapture.diagnostics.isEmpty, scenario)

            let textCapture = Capture()
            try await PrintSCUCommand.execute(arguments: ["list-printers"], context: context(root, textCapture))
            XCTAssertTrue(textCapture.output.isEmpty, scenario)
            XCTAssertTrue(textCapture.diagnostics.contains("No printers configured."), scenario)
            XCTAssertTrue(textCapture.diagnostics.contains("Add a printer with:"), scenario)
            XCTAssertEqual(try? Data(contentsOf: setup.printersURL), before, "Listing is read-only: \(scenario)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: setup.defaultSCPConfigURL.path), scenario)
        }
    }

    func testMalformedRegistryIsNotOverwrittenAndOutputFailureIsReported() async throws {
        let root = try directory(), ctx = context(root)
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: ctx.printersURL)
        for args in [["list-printers"], ["remove-printer", "--name", "x"],
                     ["add-printer", "--name", "x", "--host", "localhost", "--called-ae", "SCP"]] {
            do { try await PrintSCUCommand.execute(arguments: args, context: ctx); XCTFail("Corrupt registry must fail") }
            catch { }
        }
        XCTAssertEqual(try Data(contentsOf: ctx.printersURL), corrupt)
        let fileAsParent = root.appendingPathComponent("file-not-directory")
        try Data([1]).write(to: fileAsParent)
        do {
            try await PrintSCUCommand.execute(arguments: ["add-printer", "--name", "x", "--host", "localhost", "--called-ae", "SCP"],
                context: context(fileAsParent))
            XCTFail("Registry publication must report an unwritable path")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: fileAsParent), Data([1]))
    }

    func testDryRunDiscoversFilesWithoutConnectingOrChangingInput() async throws {
        let root = try directory(), nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        // Discovery-only fixture: dry-run intentionally does not parse or decode pixels.
        let original = Data(repeating: 0, count: 128) + Data("DICM".utf8)
        let source = nested.appendingPathComponent("literal; file.dcm")
        try original.write(to: source)
        let capture = Capture()
        try await PrintSCUCommand.execute(arguments: ["send", "pacs://127.0.0.1:1", root.path,
            "--aet", "APP", "--recursive", "--dry-run", "--verbose"], context: context(root, capture))
        XCTAssertTrue(capture.output.isEmpty)
        XCTAssertTrue(capture.diagnostics.contains("Found 1 file(s) to print"))
        XCTAssertTrue(capture.diagnostics.contains("Dry run complete. Use without --dry-run to print files."))
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("printers.json").path))
    }

    func testCancelledCommandDoesNotPublishRegistryOrSuccess() async throws {
        let root = try directory(), capture = Capture(), ctx = context(root, capture)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await PrintSCUCommand.execute(arguments: ["add-printer", "--name", "x", "--host", "localhost", "--called-ae", "SCP"], context: ctx)
        }
        do { try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        XCTAssertTrue(capture.output.isEmpty); XCTAssertTrue(capture.diagnostics.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ctx.printersURL.path))
    }
}
