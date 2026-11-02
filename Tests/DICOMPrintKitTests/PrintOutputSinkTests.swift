//
// PrintOutputSinkTests.swift
// DICOMPrintKitTests
//
// Output sinks (Milestone D) and the emulator end to end: a real Print SCU
// driving the Print SCP, composing the film, and landing it on a sink — the
// plan's checkpoint 2.
//

import XCTest
import DICOMCore
import DICOMNetwork
import CoreGraphics
@testable import DICOMPrintKit

// MARK: - Fixtures

/// Builds a minimal one-image film for sink tests.
func makeTestFilm(
    jobUID: String = "1.2.9.1",
    callingAE: String = "TEST_SCU",
    copies: Int = 1
) -> ReceivedFilm {
    let image = PrintImageData(
        pixelData: Data(repeating: 200, count: 16 * 16),
        rows: 16, columns: 16, bitsAllocated: 8, bitsStored: 8, highBit: 7,
        samplesPerPixel: 1, pixelRepresentation: 0,
        photometricInterpretation: "MONOCHROME2")
    return ReceivedFilm(
        printJobUID: jobUID,
        filmSession: FilmSession(sopInstanceUID: "1.2.9.2", numberOfCopies: copies),
        filmBox: FilmBox(sopInstanceUID: "1.2.9.3", imageDisplayFormat: "STANDARD\\1,1",
                         filmSizeID: .size8InX10In),
        layout: PrintLayout(rows: 1, columns: 1),
        imageBoxes: [ReceivedImageBox(
            sopInstanceUID: "1.2.9.4",
            sopClassUID: basicGrayscaleImageBoxSOPClassUID,
            content: ImageBoxContent(sopInstanceUID: "1.2.9.4", imagePosition: 1),
            image: image)],
        callingAETitle: callingAE,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000))
}

/// Composes a test film at a small resolution.
func makeComposedFilm(jobUID: String = "1.2.9.1", copies: Int = 1) throws -> ComposedFilm {
    try FilmComposer(configuration: FilmComposerConfiguration(dpi: 50))
        .compose(makeTestFilm(jobUID: jobUID, copies: copies))
}

/// A sink that records what it received, and can be told to fail.
actor RecordingSink: PrintOutputSink {
    private(set) var films: [ComposedFilm] = []
    private let shouldFail: Bool

    struct SinkFailure: Error {}

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    nonisolated var sinkName: String { "recording" }

    func emit(_ film: ComposedFilm) async throws {
        if shouldFail { throw SinkFailure() }
        films.append(film)
    }

    func received() -> [ComposedFilm] { films }
}

// MARK: - Screen sink

final class ScreenSinkTests: XCTestCase {

    func testScrollbackKeepsTheMostRecentFilms() async throws {
        let sink = ScreenSink(scrollbackLimit: 3, displayMaxDimension: 256)
        for index in 1...5 {
            try await sink.emit(try makeComposedFilm(jobUID: "1.2.9.\(index)"))
        }
        let films = await sink.films
        XCTAssertEqual(films.count, 3)
        XCTAssertEqual(films.map { $0.info.printJobUID }, ["1.2.9.3", "1.2.9.4", "1.2.9.5"])
        let latest = await sink.latestFilm
        XCTAssertEqual(latest?.info.printJobUID, "1.2.9.5")
    }

    func testScrollbackHoldsDownsampledCopies() async throws {
        let sink = ScreenSink(scrollbackLimit: 2, displayMaxDimension: 256)
        let composed = try makeComposedFilm()
        try await sink.emit(composed)

        let storedFilms = await sink.films
        let stored = try XCTUnwrap(storedFilms.first)
        XCTAssertLessThanOrEqual(max(stored.width, stored.height), 256)
        XCTAssertLessThan(stored.pixels.count, composed.pixels.count,
                          "the viewer copy must not pin the full-resolution bitmap")
        XCTAssertEqual(stored.info.printJobUID, composed.info.printJobUID)
    }

    func testStreamDeliversFilmsAtFullResolution() async throws {
        let sink = ScreenSink()
        let stream = await sink.filmStream()

        let received = Task { () -> ComposedFilm? in
            for await film in stream { return film }
            return nil
        }
        // Give the iterator a turn before emitting.
        try await Task.sleep(nanoseconds: 20_000_000)
        let composed = try makeComposedFilm()
        try await sink.emit(composed)

        let delivered = await received.value
        let film = try XCTUnwrap(delivered)
        XCTAssertEqual(film.width, composed.width, "the stream carries full resolution")
        XCTAssertEqual(film.pixelFingerprint, composed.pixelFingerprint)
    }

    func testFilmsArrivingWithNoViewerAreCountedNotLost() async throws {
        let sink = ScreenSink()
        try await sink.emit(try makeComposedFilm())
        let dropped = await sink.droppedFilmCount
        let films = await sink.films
        XCTAssertEqual(dropped, 1, "nobody saw it live…")
        XCTAssertEqual(films.count, 1, "…but it is still in the scrollback")
    }

    func testClearEmptiesTheScrollback() async throws {
        let sink = ScreenSink()
        try await sink.emit(try makeComposedFilm())
        await sink.clear()
        let films = await sink.films
        XCTAssertTrue(films.isEmpty)
    }
}

// MARK: - File sinks

final class FileSinkTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("printkit-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    func testImageSinkWritesAPNGPerFilm() async throws {
        let sink = ImageSink(directory: directory, format: .png,
                             naming: FilmOutputNaming(pattern: "{job}-{index}"))
        try await sink.emit(try makeComposedFilm(jobUID: "1.2.9.42"))

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, ["1.2.9.42-001.png"])
        let data = try Data(contentsOf: directory.appendingPathComponent(files[0]))
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "PNG signature")
    }

    func testImageSinkWritesTIFF() async throws {
        let sink = ImageSink(directory: directory, format: .tiff,
                             naming: FilmOutputNaming(pattern: "film"))
        try await sink.emit(try makeComposedFilm())
        let path = directory.appendingPathComponent("film.tiff")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }

    func testPDFSinkWritesAPDF() async throws {
        let sink = PDFSink(directory: directory, naming: FilmOutputNaming(pattern: "{job}"))
        try await sink.emit(try makeComposedFilm(jobUID: "1.2.9.7"))

        let path = directory.appendingPathComponent("1.2.9.7.pdf")
        let data = try Data(contentsOf: path)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "%PDF")
    }

    func testPDFSinkWritesOneMultiPageFileForAMultiFilmJob() throws {
        let films = try (1...3).map { try makeComposedFilm(jobUID: "1.2.9.\($0)") }
        let path = directory.appendingPathComponent("job.pdf")
        try PDFSink.write(films: films, to: path)

        let document = try XCTUnwrap(CGPDFDocument(path as CFURL))
        XCTAssertEqual(document.numberOfPages, 3, "one page per film box")
    }

    func testNamingExpandsEveryToken() throws {
        let film = try makeComposedFilm(jobUID: "1.2.9.5")
        let naming = FilmOutputNaming(pattern: "{ae}-{session}-{film}-{job}-{index}-{timestamp}")
        let name = naming.fileName(for: film, index: 7, extension: "png")
        XCTAssertTrue(name.hasPrefix("TEST_SCU-1.2.9.2-1.2.9.3-1.2.9.5-007-"), name)
        XCTAssertTrue(name.hasSuffix(".png"), name)
    }

    func testNamingSanitizesPathSeparators() throws {
        let film = try makeComposedFilm(jobUID: "../../etc/passwd")
        let name = FilmOutputNaming(pattern: "{job}").fileName(for: film, index: 1, extension: "png")
        XCTAssertFalse(name.contains("/"), name)
    }
}

// MARK: - Composite and paper

final class CompositeAndPaperSinkTests: XCTestCase {

    func testCompositeFansOutToEverySink() async throws {
        let first = RecordingSink(), second = RecordingSink()
        let composite = CompositePrintSink([first, second])
        try await composite.emit(try makeComposedFilm())

        let firstFilms = await first.received()
        let secondFilms = await second.received()
        XCTAssertEqual(firstFilms.count, 1)
        XCTAssertEqual(secondFilms.count, 1)
        XCTAssertEqual(composite.sinkName, "composite(recording+recording)")
    }

    func testCompositeToleratesOneFailingSinkByDefault() async throws {
        let good = RecordingSink()
        let composite = CompositePrintSink([RecordingSink(shouldFail: true), good])
        // A dead archive sink must not stop the film reaching the screen.
        try await composite.emit(try makeComposedFilm())
        let films = await good.received()
        XCTAssertEqual(films.count, 1)
    }

    func testCompositeFailsWhenEverySinkFails() async throws {
        let composite = CompositePrintSink([
            RecordingSink(shouldFail: true), RecordingSink(shouldFail: true)
        ])
        do {
            try await composite.emit(try makeComposedFilm())
            XCTFail("Expected the emit to fail when no sink accepted the film")
        } catch {
            // Expected.
        }
    }

    func testCompositeRequiresAllPropagatesTheFirstFailure() async throws {
        let good = RecordingSink()
        let composite = CompositePrintSink([RecordingSink(shouldFail: true), good], requiresAll: true)
        do {
            try await composite.emit(try makeComposedFilm())
            XCTFail("Expected requiresAll to propagate the failure")
        } catch {
            let films = await good.received()
            XCTAssertTrue(films.isEmpty, "the fan-out stops at the first failure")
        }
    }

    /// Paper output must be impossible to trigger by accident — a misconfigured
    /// emulator that spools hundreds of pages is the failure mode this guards.
    #if os(macOS) || os(Linux)
    func testPaperSinkRefusesUnlessExplicitlyAllowed() async throws {
        let sink = PaperPrinterSink(queue: "NoSuchQueue", allowPaper: false)
        do {
            try await sink.emit(try makeComposedFilm())
            XCTFail("Expected paper output to be refused")
        } catch let error as PrintSinkError {
            guard case .paperOutputNotAllowed = error else {
                return XCTFail("Expected paperOutputNotAllowed, got \(error)")
            }
        }
    }
    #endif
}

#if canImport(Network)

// MARK: - End to end

/// The emulator, whole: `DICOMPrintService` (SCU) → `DICOMPrintServer` (SCP) →
/// `FilmComposingPrintHandler` → sink.
final class PrintEmulatorEndToEndTests: XCTestCase {

    private var server: DICOMPrintServer!
    private var handler: FilmComposingPrintHandler!
    private var screen: ScreenSink!
    private var port: UInt16 = 0
    private static let calledAE = "DCMPRINT"

    override func setUp() async throws {
        try await super.setUp()
        screen = ScreenSink(scrollbackLimit: 5, displayMaxDimension: 512)
        handler = FilmComposingPrintHandler(
            composer: FilmComposer(configuration: FilmComposerConfiguration(dpi: 50)),
            sink: screen)
        server = DICOMPrintServer(
            configuration: PrintSCPConfiguration(aeTitle: try AETitle(Self.calledAE), port: 0),
            delegate: handler)
        try await server.start()
        port = await server.boundPort
    }

    override func tearDown() async throws {
        await server?.stop()
        server = nil
        handler = nil
        screen = nil
        try await super.tearDown()
    }

    private func configuration(colorMode: PrintColorMode = .grayscale) -> PrintConfiguration {
        PrintConfiguration(
            host: "127.0.0.1", port: port,
            callingAETitle: "MODALITY1", calledAETitle: Self.calledAE,
            timeout: 15, colorMode: colorMode)
    }

    private func gradient(size: UInt16 = 32) -> (Data, PrintImageData) {
        let count = Int(size) * Int(size)
        let pixels = Data((0..<count).map { UInt8($0 % 256) })
        return (pixels, PrintImageData(
            pixelData: pixels, rows: size, columns: size,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 1, pixelRepresentation: 0,
            photometricInterpretation: "MONOCHROME2"))
    }

    func testPrintingFromAnSCUProducesAComposedFilmOnScreen() async throws {
        let (pixels, descriptor) = gradient()
        let result = try await DICOMPrintService.printImages(
            configuration: configuration(),
            images: [pixels],
            options: PrintOptions(
                numberOfCopies: 2, filmSize: .size14InX17In,
                filmOrientation: .landscape, sessionLabel: "EMULATOR"),
            imageDescriptors: [descriptor])

        XCTAssertTrue(result.success, result.errorMessage ?? "")

        let films = await screen.films
        XCTAssertEqual(films.count, 1)
        let film = try XCTUnwrap(films.first)
        XCTAssertEqual(film.info.callingAETitle, "MODALITY1")
        XCTAssertEqual(film.info.filmSize, "14INX17IN")
        XCTAssertEqual(film.info.filmOrientation, "LANDSCAPE")
        XCTAssertEqual(film.info.numberOfCopies, 2)
        XCTAssertEqual(film.info.filmSessionLabel, "EMULATOR")
        XCTAssertEqual(film.info.filledImageBoxCount, 1)
        XCTAssertEqual(film.info.printJobUID, result.printJobUID)
        XCTAssertTrue(film.info.skippedImageBoxes.isEmpty)
        // Landscape: the composed sheet is wider than it is tall.
        XCTAssertGreaterThan(film.width, film.height)

        let count = await handler.composedFilmCount
        XCTAssertEqual(count, 1)
    }

    func testMultiImageJobFillsEveryCell() async throws {
        let images = (0..<4).map { _ in gradient(size: 16) }
        let result = try await DICOMPrintService.printImages(
            configuration: configuration(),
            images: images.map(\.0), options: .default,
            imageDescriptors: images.map(\.1),
            layout: PrintLayout(rows: 2, columns: 2))

        XCTAssertTrue(result.success, result.errorMessage ?? "")
        let films = await screen.films
        let film = try XCTUnwrap(films.first)
        XCTAssertEqual(film.info.filledImageBoxCount, 4)
        XCTAssertEqual(film.info.imageBoxCount, 4)
        XCTAssertEqual(film.info.rows, 2)
        XCTAssertEqual(film.info.columns, 2)
    }

    func testColorJobProducesAColorFilm() async throws {
        let pixels = Data((0..<(16 * 16)).flatMap { _ in [UInt8(220), 30, 30] })
        let descriptor = PrintImageData(
            pixelData: pixels, rows: 16, columns: 16,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 3, pixelRepresentation: 0,
            photometricInterpretation: "RGB")

        let result = try await DICOMPrintService.printImages(
            configuration: configuration(colorMode: .color),
            images: [pixels], options: .default, imageDescriptors: [descriptor],
            progressHandler: { print("[colour-film phase] \($0.phase)") })

        XCTAssertTrue(result.success, result.errorMessage ?? "")
        let films = await screen.films
        XCTAssertTrue(try XCTUnwrap(films.first).isColor)
    }

    /// The reported failure, end to end.
    ///
    /// A colour ultrasound sent raw keeps Samples per Pixel 3, and the job was
    /// still configured GRAYSCALE — which the Basic Grayscale Image Box refuses
    /// ("Samples per Pixel must be 1", 0x0106), so all three attempts failed and
    /// nothing printed. Going through ``PrintWorkflow/execute`` the SOP class
    /// now follows the pixels, and the film comes out in colour.
    func testRawColorJobOnAGrayscaleRequestStillPrintsInColor() async throws {
        let pixels = Data((0..<(16 * 16)).flatMap { _ in [UInt8(220), 30, 30] })
        let descriptor = PrintImageData(
            pixelData: pixels, rows: 16, columns: 16,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 3, pixelRepresentation: 0,
            photometricInterpretation: "RGB")
        let image = PreparedPrintImage(
            descriptor: descriptor, sourcePath: nil, frameIndex: 0)

        var request = PrintJobRequest()
        request.colorMode = .grayscale
        request.raw = true

        let result = try await PrintWorkflow.execute(
            configuration: configuration(colorMode: .grayscale),
            request: request,
            images: [image])

        XCTAssertTrue(result.success, result.errorMessage ?? "")
        let films = await screen.films
        XCTAssertTrue(try XCTUnwrap(films.first).isColor)
    }

    func testFilmAlsoReachesAFileSinkWhenComposed() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("emulator-e2e-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let localScreen = ScreenSink()
        let archive = ImageSink(directory: directory, format: .png,
                                naming: FilmOutputNaming(pattern: "{ae}-{index}"))
        let composing = FilmComposingPrintHandler(
            composer: FilmComposer(configuration: FilmComposerConfiguration(dpi: 50)),
            sink: CompositePrintSink([localScreen, archive]))
        let localServer = DICOMPrintServer(
            configuration: PrintSCPConfiguration(aeTitle: try AETitle("ARCHIVE"), port: 0),
            delegate: composing)
        try await localServer.start()
        defer { Task { await localServer.stop() } }

        let (pixels, descriptor) = gradient(size: 16)
        let result = try await DICOMPrintService.printImages(
            configuration: PrintConfiguration(
                host: "127.0.0.1", port: await localServer.boundPort,
                callingAETitle: "MODALITY1", calledAETitle: "ARCHIVE", timeout: 15),
            images: [pixels], options: .default, imageDescriptors: [descriptor])

        XCTAssertTrue(result.success, result.errorMessage ?? "")
        let onScreen = await localScreen.films
        XCTAssertEqual(onScreen.count, 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, ["MODALITY1-001.png"])
    }

    func testCompositionFailureIsReportedToTheSCU() async throws {
        // A 1×1 px film sheet cap makes composition impossible; the SCU must be
        // told the film did not print rather than getting a silent success.
        let failing = FilmComposingPrintHandler(
            composer: FilmComposer(configuration: FilmComposerConfiguration(
                dpi: 300, maximumPixelDimension: 256)),
            sink: ScreenSink())
        let failingServer = DICOMPrintServer(
            configuration: PrintSCPConfiguration(aeTitle: try AETitle("FAILCOMP"), port: 0),
            delegate: failing)
        try await failingServer.start()
        defer { Task { await failingServer.stop() } }

        let (pixels, descriptor) = gradient(size: 16)
        do {
            _ = try await DICOMPrintService.printImages(
                configuration: PrintConfiguration(
                    host: "127.0.0.1", port: await failingServer.boundPort,
                    callingAETitle: "MODALITY1", calledAETitle: "FAILCOMP", timeout: 15),
                images: [pixels], options: .default, imageDescriptors: [descriptor])
            XCTFail("Expected the composition failure to surface to the SCU")
        } catch DICOMNetworkError.printOperationFailed(let status, let detail) {
            XCTAssertEqual(status.rawValue, PrintSCPStatus.processingFailure.rawValue)
            XCTAssertEqual(detail?.contains("exceeds") ?? false, true, detail ?? "no detail")
        }

        let lastError = await failing.lastError
        XCTAssertNotNil(lastError)
    }

    func testPrinterStatusIsAnsweredByTheHandler() async throws {
        await handler.setStatus(PrinterStatus(status: "WARNING", statusInfo: "SUPPLY LOW"))
        let status = try await DICOMPrintService.getPrinterStatus(configuration: configuration())
        XCTAssertEqual(status.status, "WARNING")
        XCTAssertEqual(status.statusInfo, "SUPPLY LOW")
    }
}

#endif
