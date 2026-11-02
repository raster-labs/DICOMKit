import Foundation
import XCTest
import ArgumentParser
import DICOMNetwork
import DICOMPrintKit
import DICOMPrintTestSupport
@testable import DICOMPrintCommandSupport

private final class SCPTestOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var out: [String] = [], err: [String] = [], files: [URL] = []
    private var ports: [UInt16?] = []
    var output: [String] { lock.withLock { out } }
    var errors: [String] { lock.withLock { err } }
    var opened: [URL] { lock.withLock { files } }
    var listenerStates: [UInt16?] { lock.withLock { ports } }
    func context(_ directory: URL) -> PrintCommandContext {
        PrintCommandContext(printersURL: directory.appendingPathComponent("printers.json"),
                            defaultSCPConfigURL: directory.appendingPathComponent("printscp.json"),
                            output: { [self] value in lock.withLock { out.append(value) } },
                            diagnostic: { [self] value in lock.withLock { err.append(value) } },
                            openFile: { [self] value in lock.withLock { files.append(value) } },
                            listenerState: { [self] value in lock.withLock { ports.append(value) } })
    }
}

final class M6SCPCommandTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("m6-scp-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testRootDefaultsAndAllCommandsUseSharedParser() throws {
        XCTAssertTrue(try PrintSCPCommand.parseAsRoot([]) is SCPServeCommand)
        for arguments in [["serve"], ["simulate", "absent.dcm"], ["status"], ["queues"]] {
            try PrintSCPCommand.validate(arguments: arguments)
        }
        for arguments in [["unknown"], ["queues", "--port", "12345"], ["simulate", "a.dcm", "--no-raw"],
                          ["status", "--format", "yaml"], ["serve", "--unknown"]] {
            XCTAssertThrowsError(try PrintSCPCommand.validate(arguments: arguments), arguments.joined(separator: " "))
        }
    }

    func testOptionalInvertedFlagsPreserveNilAndExplicitFalse() throws {
        let absent = try SCPStatusCommand.parse([])
        XCTAssertNil(absent.transport.acceptColor)
        XCTAssertNil(absent.transport.presentationLUT)
        XCTAssertNil(absent.transport.annotationBox)
        XCTAssertNil(absent.composition.annotations)
        XCTAssertNil(absent.composition.trimMarks)
        let off = try SCPStatusCommand.parse(["--no-accept-color", "--no-presentation-lut", "--no-annotation-box", "--no-annotations", "--no-trim-marks"])
        XCTAssertEqual(off.transport.acceptColor, false)
        XCTAssertEqual(off.transport.presentationLUT, false)
        XCTAssertEqual(off.transport.annotationBox, false)
        XCTAssertEqual(off.composition.annotations, false)
        XCTAssertEqual(off.composition.trimMarks, false)
        let on = try SCPStatusCommand.parse(["--accept-color", "--presentation-lut", "--annotation-box", "--annotations", "--trim-marks"])
        XCTAssertEqual(on.transport.acceptColor, true)
        XCTAssertEqual(on.transport.presentationLUT, true)
        XCTAssertEqual(on.transport.annotationBox, true)
        XCTAssertEqual(on.composition.annotations, true)
        XCTAssertEqual(on.composition.trimMarks, true)
    }

    func testConfigPrecedenceAndPaperGateAreSharedWithoutBinding() async throws {
        let root = try directory(), output = SCPTestOutput(), context = output.context(root)
        var saved = PrintSCPSettings()
        saved.supportsColor = false
        saved.acceptPresentationLUT = false
        saved.drawAnnotations = false
        saved.savePDF = true
        saved.saveImage = false
        saved.sendToPaperQueue = true
        saved.paperQueue = "SHOULD_NOT_SPOOL"
        try PrintSCPSettingsFile.write(saved, to: context.defaultSCPConfigURL)
        try await PrintSCPCommand.execute(arguments: ["status", "--verbose", "--format", "json", "--accept-color"], context: context)
        let resolved = try PrintSCPSettingsFile.decode(Data(try XCTUnwrap(output.output.first).utf8))
        XCTAssertTrue(resolved.supportsColor)
        XCTAssertFalse(resolved.acceptPresentationLUT)
        XCTAssertFalse(resolved.drawAnnotations)
        XCTAssertTrue(resolved.savePDF)
        XCTAssertFalse(resolved.saveImage)
        XCTAssertFalse(resolved.sendToPaperQueue, "Stored paper settings cannot bypass --allow-paper")
        XCTAssertThrowsError(try PrintSCPCommand.validate(arguments: ["status", "--paper-queue", "TEST"]))
        XCTAssertTrue(output.errors.isEmpty)
        XCTAssertTrue(output.opened.isEmpty)
    }

    func testSaveConfigExitsBeforeSimulateInputOrOutputEffects() async throws {
        let root = try directory(), output = SCPTestOutput(), context = output.context(root)
        let films = root.appendingPathComponent("not-created"), config = root.appendingPathComponent("nested/settings.json")
        try await PrintSCPCommand.execute(arguments: ["simulate", root.appendingPathComponent("absent.dcm").path,
            "--config", config.path, "--save-config", "--output-dir", films.path, "--output", "pdf", "--dpi", "80"], context: context)
        let settings = try PrintSCPSettingsFile.decode(Data(contentsOf: config))
        XCTAssertEqual(settings.dpi, 80)
        XCTAssertTrue(settings.savePDF)
        XCTAssertFalse(settings.saveImage)
        XCTAssertEqual(output.output, ["Wrote \(config.path)"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: films.path))
        XCTAssertTrue(output.opened.isEmpty)
        for command in ["serve", "status"] {
            try await PrintSCPCommand.execute(arguments: [command, "--config", config.path, "--save-config", "--port", "0"], context: context)
        }
        XCTAssertFalse(output.output.contains { $0.contains("Listening on port") })
    }

    func testNumericResourceRefusalsHappenInParserBeforeEffects() throws {
        let invalid = [
            ["serve", "--duration", "nan"], ["serve", "--duration", "inf"], ["serve", "--duration", "1e100"],
            ["serve", "--duration", "0"], ["serve", "--max-films", "0"], ["serve", "--port", "65536"],
            ["status", "--max-associations", "0"], ["status", "--idle-timeout", "nan"],
            ["status", "--max-pdu", "4294967296"], ["status", "--max-image-boxes", "0"],
            ["status", "--max-image-dimension", "65536"], ["status", "--annotation-boxes-per-film", "65536"],
            ["simulate", "a.dcm", "--dpi", "nan"], ["simulate", "a.dcm", "--dpi", "0"],
            ["simulate", "a.dcm", "--margin-mm=-1"], ["simulate", "a.dcm", "--cell-spacing-mm", "inf"],
            ["simulate", "a.dcm", "--max-pixels", "0"], ["simulate", "a.dcm", "--copies", "0"],
            ["simulate", "a.dcm", "--window-center", "nan", "--window-width", "2"],
            ["simulate", "a.dcm", "--frame", "2", "--all-frames"]
        ]
        for args in invalid {
            XCTAssertThrowsError(try PrintSCPCommand.validate(arguments: args), args.joined(separator: " "))
        }
    }

    func testRepeatedArgumentsKeepValuesAndOrder() throws {
        let command = try SCPSimulateCommand.parse(["one file.dcm", "two;file.dcm", "--layout", "ROW\\1,3",
            "--annotate", "  FIRST; value  ", "--annotate", "SECOND\\value", "--annotation-format", "ANNOTATION",
            "--window-center=-600", "--window-width", "1500"])
        XCTAssertEqual(command.paths, ["one file.dcm", "two;file.dcm"])
        let request = try command.makeRequest()
        XCTAssertEqual(request.annotations.map(\.text), ["  FIRST; value  ", "SECOND\\value"])
        XCTAssertEqual(request.windowSettings?.center, -600)
        XCTAssertEqual(request.windowSettings?.width, 1500)
        if case let .displayFormat(layout) = request.layoutSelection { XCTAssertEqual(layout.raw, "ROW\\1,3") }
        else { XCTFail("Expected the ROW display format") }
    }

    func testRepeatedOutputLastRasterFormatAndNonePreserveContract() throws {
        var settings = PrintSCPSettings()
        let options = try SCPFilmOutputOptions.parse(["--output", "png", "--output", "pdf", "--output", "tiff", "--output", "none"])
        try options.apply(to: &settings)
        XCTAssertTrue(settings.savePDF)
        XCTAssertTrue(settings.saveImage)
        XCTAssertEqual(settings.imageFormat, .tiff)
        try SCPFilmOutputOptions.parse(["--output", "none"]).apply(to: &settings)
        XCTAssertFalse(settings.savePDF)
        XCTAssertFalse(settings.saveImage)
    }

    func testQueuesJSONMatchesObjectContractAndDoesNotCreateSettings() async throws {
        let root = try directory(), output = SCPTestOutput(), context = output.context(root)
        try await PrintSCPCommand.execute(arguments: ["queues", "--format", "json"], context: context)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.output.joined().utf8)) as? [String: Any])
        let queues = try XCTUnwrap(object["queues"] as? [String])
        XCTAssertEqual(object["count"] as? Int, queues.count)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.defaultSCPConfigURL.path))
    }

    func testQuietServeStillReportsListenerStateAndStopsAtDuration() async throws {
        let root = try directory(), output = SCPTestOutput(), context = output.context(root)
        try await PrintSCPCommand.execute(arguments: ["serve", "--port", "0", "--output", "none", "--duration", "0.05", "--quiet"], context: context)
        XCTAssertTrue(output.output.isEmpty)
        XCTAssertEqual(output.listenerStates.count, 2)
        XCTAssertGreaterThan(try XCTUnwrap(output.listenerStates.first.flatMap { $0 }), 0)
        XCTAssertNil(output.listenerStates.last.flatMap { $0 })
    }

    func testSimulateProducesFilesAndNativeOpenCallbacksAfterWrites() async throws {
        let root = try directory(), output = SCPTestOutput(), context = output.context(root)
        let original = try SyntheticPrintFixture.data()
        let copied = root.appendingPathComponent("input ; space.dcm")
        try original.write(to: copied)
        let films = root.appendingPathComponent("films")
        try await PrintSCPCommand.execute(arguments: ["simulate", copied.path, "--output-dir", films.path,
            "--output", "png", "--output", "pdf", "--dpi", "36", "--max-pixels", "1024", "--open"], context: context)
        let files = try FileManager.default.contentsOfDirectory(at: films, includingPropertiesForKeys: nil)
        XCTAssertEqual(Set(files.map(\.pathExtension)), ["png", "pdf"])
        XCTAssertEqual(Set(output.opened.map { $0.resolvingSymlinksInPath() }),
                       Set(files.map { $0.resolvingSymlinksInPath() }))
        for file in files { XCTAssertGreaterThan(try Data(contentsOf: file).count, 100) }
        XCTAssertEqual(try Data(contentsOf: copied), original)
        XCTAssertTrue(output.errors.isEmpty)
    }

    func testCancellationStopsListenerAndAllowsImmediateRestart() async throws {
        let root = try directory(), output = SCPTestOutput(), context = output.context(root)
        let first = Task { try await PrintSCPCommand.execute(arguments: ["serve", "--port", "0", "--output", "none"], context: context) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !output.output.contains(where: { $0.hasPrefix("Listening on port ") }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let line = output.output.first(where: { $0.hasPrefix("Listening on port ") }),
              let port = line.split(separator: " ").dropFirst(3).first else {
            first.cancel()
            _ = try? await first.value
            return XCTFail("Listener did not report a bound port")
        }
        first.cancel()
        do { try await first.value; XCTFail("Cancellation reported success") }
        catch is CancellationError {}
        XCTAssertTrue(output.output.contains { $0.contains("cancelled") })
        try await PrintSCPCommand.execute(arguments: ["serve", "--port", String(port), "--duration", "0.05", "--output", "none"], context: context)
        XCTAssertEqual(output.output.filter { $0.hasPrefix("Listening on port ") }.count, 2)
    }

    func testOccupiedPortDoesNotStopExistingListener() async throws {
        let root = try directory(), output = SCPTestOutput(), context = output.context(root)
        let existing = Task { try await PrintSCPCommand.execute(arguments: ["serve", "--port", "0", "--output", "none"], context: context) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !output.output.contains(where: { $0.hasPrefix("Listening on port ") }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let line = output.output.first(where: { $0.hasPrefix("Listening on port ") }),
              let port = line.split(separator: " ").dropFirst(3).first else {
            existing.cancel(); _ = try? await existing.value
            return XCTFail("Listener did not report a bound port")
        }
        do {
            try await PrintSCPCommand.execute(arguments: ["serve", "--port", String(port), "--duration", "0.05", "--output", "none"], context: context)
            XCTFail("Occupied port was accepted")
        } catch { XCTAssertTrue(String(describing: error).contains("Failed to start printer")) }
        XCTAssertFalse(output.output.contains { $0.contains("cancelled") })
        existing.cancel()
        _ = try? await existing.value
    }
}
