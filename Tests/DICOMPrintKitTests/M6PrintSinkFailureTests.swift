import Foundation
import XCTest
import DICOMPrintKit

private final class M6SinkFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(String, String)] = []
    var values: [(String, String)] { lock.withLock { storage } }
    func append(_ name: String, _ message: String) { lock.withLock { storage.append((name, message)) } }
}

final class M6PrintSinkFailureTests: XCTestCase {
    func testOneFailedDestinationIsVisibleWithoutDiscardingSuccessfulScreenFilm() async throws {
        let failures = M6SinkFailures(), good = RecordingSink(), bad = RecordingSink(shouldFail: true)
        let sink = CompositePrintSink([good, bad], onFailure: { failures.append($0, $1) })
        try await sink.emit(try makeComposedFilm())
        let saved = await good.received()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(failures.values.count, 1)
        XCTAssertEqual(failures.values.first?.0, "recording")
        XCTAssertFalse(failures.values.first?.1.isEmpty ?? true)
    }

    func testAllFailuresStillThrowAndEachIsReported() async throws {
        let failures = M6SinkFailures()
        let sink = CompositePrintSink([RecordingSink(shouldFail: true), RecordingSink(shouldFail: true)],
                                      onFailure: { failures.append($0, $1) })
        do { try await sink.emit(try makeComposedFilm()); XCTFail("All failed sinks reported success") }
        catch {}
        XCTAssertEqual(failures.values.count, 2)
    }

    func testPersistentFailureCannotProduceSavedFileCallback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("m6-sink-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let failures = M6SinkFailures(), writes = M6SinkFailures()
        var settings = PrintSCPSettings()
        settings.outputDirectory = directory.path
        settings.savePDF = true
        settings.saveImage = false
        let screen = ScreenSink(scrollbackLimit: 1, displayMaxDimension: 32)
        let stream = await screen.filmStream()
        let sink = try PrintSCPService().makeSink(settings: settings, screen: screen,
            onFileWritten: { writes.append($0.path, "saved") }, onFailure: { failures.append($0, $1) })
        // Break only the persistent destination after assembly, when a real
        // printer could already have accepted an association.
        try FileManager.default.removeItem(at: directory)
        try Data("not a directory".utf8).write(to: directory)
        try await sink.emit(try makeComposedFilm())
        var iterator = stream.makeAsyncIterator()
        let film = await iterator.next()
        XCTAssertNotNil(film)
        XCTAssertEqual(failures.values.count, 1)
        XCTAssertTrue(writes.values.isEmpty)
    }
}
