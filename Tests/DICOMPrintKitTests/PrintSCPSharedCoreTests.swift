//
// PrintSCPSharedCoreTests.swift
// DICOMPrintKitTests
//
// The emulator's shared core: the settings→configuration mapping, the assembly,
// the console wording, and the local composer.
//
// These types back both DICOM Studio's Print SCP screen and `dicom-printscp`, so
// a mis-mapped knob or a re-phrased line is a divergence between the app and the
// terminal — exactly what the shared-API rule exists to prevent.
//

import XCTest
import DICOMCore
import DICOMNetwork
@testable import DICOMPrintKit

// MARK: - Settings → configuration

final class PrintSCPSettingsMappingTests: XCTestCase {

    func testDefaultsMatchTheEmulatorContract() {
        let settings = PrintSCPSettings()
        // 11113, not 11112: the Storage SCP owns the usual port, and two
        // listeners on one port fail to bind.
        XCTAssertEqual(settings.port, 11113)
        XCTAssertEqual(settings.effectiveAETitle, "DCMPRINT")
        XCTAssertNil(settings.callingAEWhitelist)
        XCTAssertNil(settings.callingAEBlacklist)
        XCTAssertEqual(settings.supportedFilmSizes, Set(FilmSize.allCases))
        XCTAssertEqual(settings.supportedMediumTypes, Set(MediumType.allCases))
    }

    func testTransportFieldsReachTheConfiguration() throws {
        var settings = PrintSCPSettings()
        settings.aeTitle = "PRINTER1"
        settings.port = 12345
        settings.maxConcurrentAssociations = 3
        settings.associationIdleTimeoutSeconds = 45
        settings.allowedCallingAETitles = "CT1, MR1"
        settings.deniedCallingAETitles = "BADAE"
        settings.maxPDUSize = 32768

        let configuration = try settings.makeConfiguration()
        XCTAssertEqual(configuration.aeTitle.value, "PRINTER1")
        XCTAssertEqual(configuration.port, 12345)
        XCTAssertEqual(configuration.maxConcurrentAssociations, 3)
        XCTAssertEqual(configuration.associationIdleTimeout, 45)
        XCTAssertEqual(configuration.callingAEWhitelist, ["CT1", "MR1"])
        XCTAssertEqual(configuration.callingAEBlacklist, ["BADAE"])
        XCTAssertEqual(configuration.maxPDUSize, 32768)
    }

    func testCapabilityFieldsReachTheConfiguration() throws {
        var settings = PrintSCPSettings()
        settings.supportsColor = false
        settings.acceptPresentationLUT = false
        settings.acceptAnnotationBox = false
        settings.annotationBoxesPerFilm = 2
        settings.pushPrintJobEvents = true
        settings.supportedFilmSizeTokens = ["14x17", "a4"]
        settings.supportedMediumTokens = ["clear-film"]
        settings.maxImageBoxesPerFilm = 4
        settings.maxImageBoxPixelDimension = 2048

        let configuration = try settings.makeConfiguration()
        XCTAssertFalse(configuration.supportsColor)
        XCTAssertFalse(configuration.acceptPresentationLUT)
        XCTAssertFalse(configuration.acceptAnnotationBox)
        XCTAssertEqual(configuration.annotationBoxesPerFilm, 2)
        XCTAssertTrue(configuration.pushPrintJobEvents)
        XCTAssertEqual(configuration.supportedFilmSizes, [.size14InX17In, .a4])
        XCTAssertEqual(configuration.supportedMediumTypes, [.clearFilm])
        XCTAssertEqual(configuration.maxImageBoxesPerFilm, 4)
        XCTAssertEqual(configuration.maxImageBoxPixelDimension, 2048)
    }

    func testUnknownSizeTokensDoNotSilentlyNarrowWhatIsAccepted() throws {
        var settings = PrintSCPSettings()
        settings.supportedFilmSizeTokens = ["not-a-size"]
        // An unusable list must not become "accept nothing" — a printer that
        // rejects every film box is far worse than one that accepts all sizes.
        XCTAssertEqual(try settings.makeConfiguration().supportedFilmSizes, Set(FilmSize.allCases))
    }

    func testCompositionFieldsReachTheComposer() {
        var settings = PrintSCPSettings()
        settings.dpi = 150
        settings.densityMapping = .filmEmulation
        settings.marginMillimeters = 8
        settings.cellSpacingMillimeters = 4
        settings.drawAnnotations = false
        settings.drawTrimMarks = false
        settings.maximumPixelDimension = 4000

        let configuration = settings.makeComposerConfiguration()
        XCTAssertEqual(configuration.dpi, 150)
        XCTAssertEqual(configuration.densityMapping, .filmEmulation)
        XCTAssertEqual(configuration.marginMillimeters, 8)
        XCTAssertEqual(configuration.cellSpacingMillimeters, 4)
        XCTAssertFalse(configuration.drawAnnotations)
        XCTAssertFalse(configuration.drawTrimMarks)
        XCTAssertEqual(configuration.maximumPixelDimension, 4000)
    }

    func testPrinterStatusInfoFallsBackToTheStatusText() {
        var settings = PrintSCPSettings()
        settings.printerStatus = .failure
        XCTAssertEqual(settings.effectivePrinterStatusInfo, "SUPPLY EMPTY")  // a PS3.3 C.13.9.1 Defined Term
        settings.printerStatusInfo = "OUT OF FILM"
        XCTAssertEqual(settings.reportedPrinterStatus.statusInfo, "OUT OF FILM")
        XCTAssertEqual(settings.reportedPrinterStatus.status, "FAILURE")
    }

    func testInvalidAETitleIsRejectedBeforeTheListenerStarts() {
        var settings = PrintSCPSettings()
        settings.aeTitle = String(repeating: "X", count: 32)
        XCTAssertThrowsError(try settings.makeConfiguration())
    }
}

// MARK: - Persistence

final class PrintSCPSettingsFileTests: XCTestCase {

    func testRoundTrip() throws {
        var settings = PrintSCPSettings()
        settings.aeTitle = "FILMBOX"
        settings.port = 11999
        settings.supportedMediumTokens = ["paper", "blue-film"]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("printscp-\(UUID().uuidString)/settings.json")
        try PrintSCPSettingsFile.write(settings, to: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        XCTAssertEqual(PrintSCPSettingsFile.read(from: url), settings)
    }

    func testPartialDocumentKeepsItsValuesAndDefaultsTheRest() throws {
        // The whole point of the tolerant decoder: a file from another build
        // must not reset the port and AE title a modality is configured against.
        let json = Data(#"{"aeTitle":"OLDBUILD","port":11500}"#.utf8)
        let settings = try PrintSCPSettingsFile.decode(json)
        XCTAssertEqual(settings.aeTitle, "OLDBUILD")
        XCTAssertEqual(settings.port, 11500)
        XCTAssertEqual(settings.dpi, PrintSCPSettings().dpi)
        XCTAssertEqual(settings.retainedFilmLimit, PrintSCPSettings().retainedFilmLimit)
    }

    func testMissingFileReadsAsDefaults() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("printscp-missing-\(UUID().uuidString).json")
        XCTAssertEqual(PrintSCPSettingsFile.read(from: url), PrintSCPSettings())
    }
}

// MARK: - Option catalog

final class PrintSCPOptionCatalogTests: XCTestCase {

    func testTokensResolveBothWays() {
        XCTAssertEqual(PrintOptionCatalog.mediumType(forToken: "clear-film"), .clearFilm)
        XCTAssertEqual(PrintOptionCatalog.densityMapping(forToken: "film"), .filmEmulation)
        XCTAssertEqual(PrintOptionCatalog.emulatedPrinterStatus(forToken: "warning"), .warning)
        XCTAssertNil(PrintOptionCatalog.densityMapping(forToken: "paper-direct"))
    }

    func testEveryCatalogueTokenIsDistinctAndLowercase() {
        let tokens = PrintOptionCatalog.densityMappings.map(\.cliToken)
            + PrintOptionCatalog.emulatedPrinterStatuses.map(\.cliToken)
        XCTAssertEqual(Set(tokens).count, tokens.count)
        XCTAssertTrue(tokens.allSatisfy { $0 == $0.lowercased() })
    }

    func testEveryDensityMappingAndStatusHasAToken() {
        XCTAssertEqual(PrintOptionCatalog.densityMappings.count, DensityMapping.allCases.count)
        XCTAssertEqual(
            PrintOptionCatalog.emulatedPrinterStatuses.count,
            EmulatedPrinterStatus.allCases.count)
    }
}

// MARK: - Console

final class PrintSCPConsoleTests: XCTestCase {

    func testEventsAreWordedOnceForBothSurfaces() throws {
        let rejected = PrintSCPConsole.logEntry(
            for: .associationRejected(callingAE: "BADAE", reason: "not on the whitelist"))
        XCTAssertEqual(rejected?.level, .warning)
        XCTAssertEqual(rejected?.remoteAETitle, "BADAE")
        XCTAssertEqual(rejected?.message, "Rejected BADAE: not on the whitelist")

        let failed = PrintSCPConsole.logEntry(
            for: .requestFailed(command: .nCreateRequest, status: .printQueueFull, detail: nil))
        XCTAssertEqual(failed?.level, .warning)
        XCTAssertEqual(failed?.message.contains("0xC601"), true)
        // PS3.4 Table H.4-4 wording for C601.
        XCTAssertEqual(
            failed?.message.contains("Unable to create Print Job SOP Instance; print queue is full"),
            true)

        // `.started` carries no line of its own: the bound port belongs to the
        // surface's own "listening on…" line, which knows the AE title.
        XCTAssertNil(PrintSCPConsole.logEntry(for: .started(port: 104)))
    }

    func testConsoleLineIsTimestampedAndTagged() {
        let entry = PrintSCPLogEntry(level: .filmReceived, message: "Film printed")
        let line = PrintSCPConsole.consoleLine(for: entry)
        XCTAssertTrue(line.hasSuffix("[film]  Film printed"), line)
    }

    func testJSONLineCarriesTheCallingAE() throws {
        let entry = PrintSCPLogEntry(level: .connection, message: "Association", remoteAETitle: "CT1")
        let json = try XCTUnwrap(PrintSCPConsole.jsonLine(for: entry))
        XCTAssertTrue(json.contains("\"callingAE\":\"CT1\""), json)
        XCTAssertTrue(json.contains("\"level\":\"connection\""), json)
        XCTAssertFalse(json.contains("\n"), "an event line must stay on one line")
    }

    func testStartupSummaryStatesWhereFilmsGo() {
        var settings = PrintSCPSettings()
        settings.saveImage = true
        settings.savePDF = true
        settings.outputDirectory = "/tmp/films"
        settings.allowedCallingAETitles = "CT1"

        let lines = PrintSCPConsole.startupSummary(settings: settings, boundPort: 11113)
        XCTAssertEqual(lines.first, "Listening on port 11113 as DCMPRINT")
        XCTAssertTrue(lines.contains { $0.contains("PNG + PDF → /tmp/films") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("Accepting:") && $0.contains("CT1") }, "\(lines)")
    }

    func testOutputSummarySaysSoWhenFilmsAreDiscarded() {
        let settings = PrintSCPSettings()
        XCTAssertTrue(PrintSCPConsole.outputSummary(settings: settings).contains("discarded"))
    }

    func testCountersTallyTheEventsThatMatter() {
        var counters = PrintSCPSessionCounters()
        counters.record(.associationEstablished(AssociationInfo(
            callingAETitle: "CT1", calledAETitle: "DCMPRINT",
            remoteHost: "127.0.0.1", remotePort: 5000,
            proposedSOPClasses: [], proposedTransferSyntaxes: [])))
        counters.record(.deleted(uid: "1.2.3"))
        counters.record(.requestFailed(command: .nSetRequest, status: .unableToProcess, detail: nil))
        XCTAssertEqual(counters.associations, 1)
        XCTAssertEqual(counters.films, 0)
        XCTAssertEqual(counters.errors, 1)
        XCTAssertEqual(counters.summary, "1 association, 0 films, 1 error")
    }
}

#if canImport(CoreGraphics)

// MARK: - Assembly

final class PrintSCPServiceAssemblyTests: XCTestCase {

    func testScreenOnlyWhenNothingIsEnabled() throws {
        let sink = try PrintSCPService().makeSink(
            settings: PrintSCPSettings(), screen: ScreenSink())
        XCTAssertEqual(sink.sinkName, "screen")
    }

    func testEnabledOutputsCompositeOntoTheScreen() throws {
        var settings = PrintSCPSettings()
        settings.saveImage = true
        settings.imageFormat = .tiff
        settings.savePDF = true
        settings.outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("printscp-sink-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: settings.outputDirectory) }

        let sink = try PrintSCPService().makeSink(settings: settings, screen: ScreenSink())
        XCTAssertEqual(sink.sinkName, "composite(screen+pdf+tiff)")
    }

    func testHandlerReportsTheConfiguredPrinterStatus() async throws {
        var settings = PrintSCPSettings()
        settings.printerStatus = .warning
        let handler = PrintSCPService().makeHandler(settings: settings, sink: ScreenSink())
        let status = await handler.printerStatus()
        XCTAssertEqual(status.status, "WARNING")
        XCTAssertEqual(status.statusInfo, "SUPPLY LOW")
    }
}

#endif

#if canImport(Network) && canImport(CoreGraphics)

// MARK: - End to end, as both surfaces run it

/// A film printed by a real SCU into a listener assembled the way the CLI and
/// the app assemble one — settings in, PNG on disk, console lines out.
final class PrintSCPSharedRuntimeTests: XCTestCase {

    func testAssembledEmulatorReceivesComposesAndWritesAFilm() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("printscp-e2e-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        var settings = PrintSCPSettings()
        settings.port = 0                       // ephemeral: no clash with a real listener
        settings.aeTitle = "SHAREDSCP"
        settings.dpi = 50
        settings.saveImage = true
        settings.imageFormat = .png
        settings.outputDirectory = directory.path
        settings.fileNamePattern = "film-{ae}-{index}"

        let service = PrintSCPService()
        let screen = ScreenSink(scrollbackLimit: 2, displayMaxDimension: 256)
        let written = WrittenPaths()
        let sink = try service.makeSink(
            settings: settings, screen: screen,
            onFileWritten: { url in Task { await written.record(url) } })
        let handler = service.makeHandler(settings: settings, sink: sink)
        let server = try service.makeServer(settings: settings, delegate: handler)

        let events = await server.events
        try await server.start()
        let boundPort = await server.boundPort
        defer { Task { await server.stop() } }

        let collector = Task { () -> [PrintSCPLogEntry] in
            var entries: [PrintSCPLogEntry] = []
            for await event in events {
                if let entry = PrintSCPConsole.logEntry(for: event) { entries.append(entry) }
                if case .filmPrinted = event { break }
            }
            return entries
        }

        let pixels = Data((0..<(32 * 32)).map { UInt8($0 % 256) })
        let descriptor = PrintImageData(
            pixelData: pixels, rows: 32, columns: 32,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 1, pixelRepresentation: 0,
            photometricInterpretation: "MONOCHROME2")

        let result = try await DICOMPrintService.printImages(
            configuration: PrintConfiguration(
                host: "127.0.0.1", port: boundPort,
                callingAETitle: "MODALITY1", calledAETitle: "SHAREDSCP",
                timeout: 15),
            images: [pixels],
            options: PrintOptions(filmSize: .size14InX17In),
            imageDescriptors: [descriptor])
        XCTAssertTrue(result.success, result.errorMessage ?? "")

        let entries = await collector.value
        XCTAssertTrue(entries.contains { $0.level == .connection && $0.remoteAETitle == "MODALITY1" },
                      entries.map(\.message).joined(separator: " | "))
        XCTAssertTrue(entries.contains { $0.level == .filmReceived },
                      entries.map(\.message).joined(separator: " | "))

        // The composed sheet reached the screen channel every surface listens on…
        let films = await screen.films
        let film = try XCTUnwrap(films.first)
        XCTAssertEqual(film.info.callingAETitle, "MODALITY1")
        XCTAssertTrue(PrintSCPConsole.filmLine(film).contains("MODALITY1"))

        // …and the file sink wrote it under the configured name pattern.
        try await waitUntil { await written.paths.isEmpty == false }
        let paths = await written.paths
        let path = try XCTUnwrap(paths.first)
        XCTAssertEqual(path.lastPathComponent, "film-MODALITY1-001.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }

    /// Polls a condition, so the test does not race the sink's write callback.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @Sendable () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Condition not met within \(timeout)s")
    }
}

/// Collects the paths the sinks report.
actor WrittenPaths {
    private(set) var paths: [URL] = []

    func record(_ url: URL) {
        paths.append(url)
    }
}

#endif
