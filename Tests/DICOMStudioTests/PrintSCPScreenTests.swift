// PrintSCPScreenTests.swift
// DICOMStudioTests
//
// DICOM Studio — tests for the Print SCP screen: the settings→configuration
// mapping, film retention, persistence, and the navigation entry.
//
// The protocol machine itself is covered by DICOMNetworkTests/PrintSCPTests;
// what matters here is that a knob on the screen reaches the right field of
// `PrintSCPConfiguration` / `FilmComposerConfiguration`, since a mis-mapped one
// is invisible until a modality fails to associate.

import Testing
import Foundation
@testable import DICOMStudio
import DICOMNetwork
import DICOMPrintKit

// MARK: - Fixtures

private func makeFilmInfo(
    callingAE: String = "MODALITY",
    receivedAt: Date = Date(),
    rows: Int = 2,
    columns: Int = 2
) -> ComposedFilmInfo {
    ComposedFilmInfo(
        printJobUID: "1.2.3.4", filmSessionUID: "1.2.3.5", filmBoxUID: "1.2.3.6",
        callingAETitle: callingAE, receivedAt: receivedAt,
        filmSize: "14INX17IN", filmOrientation: "PORTRAIT",
        imageDisplayFormat: "STANDARD\\\(columns),\(rows)",
        rows: rows, columns: columns, mediumType: "BLUE FILM", numberOfCopies: 1,
        filmSessionLabel: "SESSION", magnificationType: "BILINEAR",
        borderDensity: "BLACK", emptyImageDensity: "BLACK", trim: "NO",
        minDensity: 20, maxDensity: 300, presentationLUTShape: "IDENTITY",
        annotations: ["1: PATIENT"], sheetWidthMillimeters: 355.6,
        sheetHeightMillimeters: 431.8, dpi: 300, densityMapping: .paperDirect,
        filledImageBoxCount: 3, imageBoxCount: 4, skippedImageBoxes: [])
}

/// A composed film of a given byte size, for the retention tests.
private func makeFilm(bytes: Int, receivedAt: Date = Date()) -> ComposedFilm {
    let width = max(1, bytes)
    return ComposedFilm(
        info: makeFilmInfo(receivedAt: receivedAt),
        width: width, height: 1, samplesPerPixel: 1,
        pixels: Data(count: width))
}

// MARK: - Settings

@Suite("Print SCP Settings Tests")
struct PrintSCPSettingsTests {

    @Test("defaults do not collide with the Storage SCP listener port")
    func testDefaultPort() {
        #expect(PrintSCPSettings().port == 11113)
    }

    @Test("blank AE title falls back to the default")
    func testEffectiveAETitle() {
        var settings = PrintSCPSettings()
        settings.aeTitle = "   "
        #expect(settings.effectiveAETitle == "DCMPRINT")
        settings.aeTitle = " MYPRINTER "
        #expect(settings.effectiveAETitle == "MYPRINTER")
    }

    @Test("empty allow-list accepts every caller")
    func testWhitelistEmpty() {
        #expect(PrintSCPSettings().callingAEWhitelist == nil)
    }

    @Test("allow-list splits on commas and whitespace")
    func testWhitelistParsing() {
        var settings = PrintSCPSettings()
        settings.allowedCallingAETitles = "CT1, MR1  US1"
        #expect(settings.callingAEWhitelist == ["CT1", "MR1", "US1"])
    }

    @Test("status info falls back to the status's own text")
    func testStatusInfoFallback() {
        var settings = PrintSCPSettings()
        settings.printerStatus = .failure
        #expect(settings.effectivePrinterStatusInfo == "SUPPLY EMPTY")  // a PS3.3 C.13.9.1 Defined Term
        settings.printerStatusInfo = "OUT OF FILM"
        #expect(settings.effectivePrinterStatusInfo == "OUT OF FILM")
    }

    @Test("output directory expands a tilde")
    func testOutputDirectoryTilde() {
        var settings = PrintSCPSettings()
        settings.outputDirectory = "~/Films"
        #expect(!settings.outputDirectoryURL.path.contains("~"))
        #expect(settings.outputDirectoryURL.lastPathComponent == "Films")
    }

    @Test("memory budget converts megabytes to bytes")
    func testMemoryBudget() {
        var settings = PrintSCPSettings()
        settings.retainedMemoryBudgetMB = 2
        #expect(settings.retainedMemoryBudgetBytes == 2 * 1_048_576)
    }

    @Test("settings round-trip through JSON")
    func testCodableRoundTrip() throws {
        var settings = PrintSCPSettings()
        settings.aeTitle = "FILMPRINT"
        settings.port = 4242
        settings.densityMapping = .filmEmulation
        settings.imageFormat = .tiff
        settings.printerStatus = .warning
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(PrintSCPSettings.self, from: data)
        #expect(decoded == settings)
    }
}

// MARK: - Configuration mapping

@Suite("Print SCP Configuration Mapping Tests")
struct PrintSCPConfigurationMappingTests {

    @Test("listener settings reach the SCP configuration")
    func testListenerMapping() throws {
        var settings = PrintSCPSettings()
        settings.aeTitle = "FILMPRINT"
        settings.port = 4242
        settings.maxConcurrentAssociations = 3
        settings.associationIdleTimeoutSeconds = 45
        settings.allowedCallingAETitles = "CT1,MR1"
        settings.pushPrintJobEvents = true

        let config = try settings.makeConfiguration()
        #expect(config.aeTitle.value == "FILMPRINT")
        #expect(config.port == 4242)
        #expect(config.maxConcurrentAssociations == 3)
        #expect(config.associationIdleTimeout == 45)
        #expect(config.callingAEWhitelist == ["CT1", "MR1"])
        #expect(config.pushPrintJobEvents)
    }

    @Test("capability toggles reach the SCP configuration")
    func testCapabilityMapping() throws {
        var settings = PrintSCPSettings()
        settings.supportsColor = false
        settings.acceptPresentationLUT = false
        settings.acceptAnnotationBox = false

        let config = try settings.makeConfiguration()
        #expect(!config.supportsColor)
        #expect(!config.acceptPresentationLUT)
        #expect(!config.acceptAnnotationBox)
        // Colour off means the colour meta SOP class is not offered.
        #expect(!config.effectiveSOPClasses.contains(basicColorPrintManagementMetaSOPClassUID))
    }

    @Test("reported identity reaches the SCP configuration")
    func testIdentityMapping() throws {
        var settings = PrintSCPSettings()
        settings.printerName = "FILM-1"
        settings.manufacturer = "Acme"
        settings.manufacturerModelName = "Laser 9000"
        settings.deviceSerialNumber = "SN-7"
        settings.softwareVersion = "2.5"

        let config = try settings.makeConfiguration()
        #expect(config.printerName == "FILM-1")
        #expect(config.manufacturer == "Acme")
        #expect(config.manufacturerModelName == "Laser 9000")
        #expect(config.deviceSerialNumber == "SN-7")
        #expect(config.softwareVersion == "2.5")
    }

    @Test("an illegal AE title is rejected rather than silently truncated")
    func testInvalidAETitleThrows() {
        var settings = PrintSCPSettings()
        settings.aeTitle = String(repeating: "A", count: 17)
        #expect(throws: (any Error).self) { try settings.makeConfiguration() }
    }

    @Test("printer status becomes the value the SCP reports to N-GET")
    func testReportedPrinterStatus() {
        var settings = PrintSCPSettings()
        settings.printerStatus = .failure
        settings.printerName = "FILM-1"
        let status = settings.reportedPrinterStatus
        #expect(status.status == "FAILURE")
        #expect(status.statusInfo == "SUPPLY EMPTY")
        #expect(status.printerName == "FILM-1")
        #expect(!status.isNormal)
    }

    @Test("composition settings reach the film composer configuration")
    func testComposerMapping() {
        var settings = PrintSCPSettings()
        settings.dpi = 150
        settings.densityMapping = .filmEmulation
        settings.drawAnnotations = false
        settings.drawTrimMarks = false

        let config = settings.makeComposerConfiguration()
        #expect(config.dpi == 150)
        #expect(config.densityMapping == .filmEmulation)
        #expect(!config.drawAnnotations)
        #expect(!config.drawTrimMarks)
    }
}

// MARK: - Persistence

@Suite("Print SCP Settings Storage Tests")
struct PrintSCPSettingsStorageTests {

    private func makeStorage() -> PrintSCPSettingsStorageService {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PrintSCPTests-\(UUID().uuidString)", isDirectory: true)
        return PrintSCPSettingsStorageService(
            storageService: StorageService(baseDirectory: directory))
    }

    @Test("missing file loads the defaults")
    func testLoadDefaults() {
        #expect(makeStorage().load() == PrintSCPSettings())
    }

    @Test("settings survive a save and load")
    func testRoundTrip() throws {
        let storage = makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.storageService.baseDirectory) }

        var settings = PrintSCPSettings()
        settings.aeTitle = "FILMPRINT"
        settings.port = 4242
        settings.savePDF = true
        try storage.save(settings)

        #expect(storage.load() == settings)
    }

    @Test("a corrupt file falls back to the defaults rather than throwing")
    func testCorruptFile() throws {
        let storage = makeStorage()
        defer { try? FileManager.default.removeItem(at: storage.storageService.baseDirectory) }

        try storage.storageService.createDirectories()
        try Data("not json".utf8).write(to: storage.fileURL)
        #expect(storage.load() == PrintSCPSettings())
    }
}

// MARK: - Service

@Suite("Print SCP Service Tests")
struct PrintSCPServiceTests {

    @Test("the screen sink alone is used when no output is enabled")
    func testScreenOnlySink() throws {
        let sink = try PrintSCPService().makeSink(
            settings: PrintSCPSettings(), screen: ScreenSink())
        #expect(sink.sinkName == "screen")
    }

    @Test("enabling PDF output composes a sink onto the screen")
    func testCompositeSink() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PrintSCPSink-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var settings = PrintSCPSettings()
        settings.outputDirectory = directory.path
        settings.savePDF = true

        let sink = try PrintSCPService().makeSink(settings: settings, screen: ScreenSink())
        #expect(sink.sinkName.contains("screen"))
        #expect(sink.sinkName.contains("pdf"))
        // The directory is created up front: discovering it cannot be written
        // after the first film has printed is worse than refusing to start.
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("the thumbnail is bounded to the list's size")
    func testThumbnail() {
        let film = ComposedFilm(
            info: makeFilmInfo(), width: 2000, height: 1000, samplesPerPixel: 1,
            pixels: Data(count: 2000 * 1000))
        let thumbnail = PrintSCPService().makeThumbnail(of: film)
        #expect(max(thumbnail.width, thumbnail.height) <= PrintSCPService.thumbnailMaxDimension)
    }

    @Test("the file extension chooses the writer")
    func testWriteFormats() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PrintSCPWrite-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let film = ComposedFilm(
            info: makeFilmInfo(), width: 16, height: 16, samplesPerPixel: 1,
            pixels: Data(count: 16 * 16))
        let service = PrintSCPService()

        for ext in ["pdf", "png", "tiff"] {
            let url = directory.appendingPathComponent("film.\(ext)")
            try service.write(film: film, to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }
}

// MARK: - ViewModel

@Suite("Print SCP ViewModel Tests")
struct PrintSCPViewModelTests {

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    private func makeViewModel() -> PrintSCPViewModel {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PrintSCPVM-\(UUID().uuidString)", isDirectory: true)
        return PrintSCPViewModel(
            storage: PrintSCPSettingsStorageService(
                storageService: StorageService(baseDirectory: directory)))
    }

    @Test("starts stopped with nothing received")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testInitialState() {
        let viewModel = makeViewModel()
        #expect(!viewModel.isRunning)
        #expect(viewModel.films.isEmpty)
        #expect(viewModel.selectedFilm == nil)
        #expect(viewModel.filmCount == 0)
        #expect(viewModel.startErrorMessage == nil)
    }

    @Test("the endpoint reads as the AE title and port to configure on the sender")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testEndpointDescription() {
        let viewModel = makeViewModel()
        viewModel.settings.aeTitle = "FILMPRINT"
        viewModel.settings.port = 4242
        #expect(viewModel.endpointDescription == "FILMPRINT : 4242")
    }

    @Test("a received film is retained and selected")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testRetainSelectsFirstFilm() {
        let viewModel = makeViewModel()
        viewModel.retain(makeFilm(bytes: 1024))
        #expect(viewModel.films.count == 1)
        #expect(viewModel.selectedFilmID == viewModel.films[0].id)
        #expect(viewModel.retainedBytes > 0)
    }

    @Test("films are listed newest first")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testNewestFirst() {
        let viewModel = makeViewModel()
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        viewModel.retain(makeFilm(bytes: 64, receivedAt: older))
        viewModel.retain(makeFilm(bytes: 64, receivedAt: newer))
        #expect(viewModel.films.first?.receivedAt == newer)
        #expect(viewModel.films.last?.receivedAt == older)
    }

    @Test("the count limit evicts the oldest films")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testCountLimitEviction() {
        let viewModel = makeViewModel()
        viewModel.settings.retainedFilmLimit = 2
        for index in 0..<5 {
            viewModel.retain(makeFilm(bytes: 32,
                                      receivedAt: Date(timeIntervalSince1970: Double(index))))
        }
        #expect(viewModel.films.count == 2)
        #expect(viewModel.evictedFilmCount == 3)
        #expect(viewModel.films.first?.receivedAt == Date(timeIntervalSince1970: 4))
    }

    @Test("the memory ceiling evicts even under the count limit")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testMemoryBudgetEviction() {
        let viewModel = makeViewModel()
        viewModel.settings.retainedFilmLimit = 100
        viewModel.settings.retainedMemoryBudgetMB = 1

        // Each film is ~400 KB, so the third one pushes past a 1 MB ceiling.
        for _ in 0..<3 {
            viewModel.retain(makeFilm(bytes: 400_000))
        }
        #expect(viewModel.films.count == 2)
        #expect(viewModel.retainedBytes <= viewModel.settings.retainedMemoryBudgetBytes)
    }

    @Test("the newest film is always kept, however large")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testOversizedFilmStillKept() {
        let viewModel = makeViewModel()
        viewModel.settings.retainedMemoryBudgetMB = 1
        viewModel.retain(makeFilm(bytes: 4_000_000))
        #expect(viewModel.films.count == 1)
    }

    @Test("clearing forgets the retained films and the selection")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testClearFilms() {
        let viewModel = makeViewModel()
        viewModel.retain(makeFilm(bytes: 128))
        viewModel.clearFilms()
        #expect(viewModel.films.isEmpty)
        #expect(viewModel.selectedFilmID == nil)
        #expect(viewModel.retainedBytes == 0)
    }

    @Test("the selected film's attributes serialize as JSON for copying")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testAttributesJSON() throws {
        let viewModel = makeViewModel()
        viewModel.retain(makeFilm(bytes: 128))
        let json = try #require(viewModel.selectedFilmAttributesJSON())
        #expect(json.contains("\"callingAETitle\""))
        #expect(json.contains("MODALITY"))
    }

    @Test("settings persist across view models")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testSettingsPersist() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PrintSCPVM-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = PrintSCPSettingsStorageService(
            storageService: StorageService(baseDirectory: directory))

        let first = PrintSCPViewModel(storage: storage)
        first.settings.aeTitle = "FILMPRINT"
        first.settings.port = 4242
        first.saveSettings()

        let second = PrintSCPViewModel(storage: storage)
        #expect(second.settings.aeTitle == "FILMPRINT")
        #expect(second.settings.port == 4242)
    }
}

// MARK: - Navigation

@Suite("Print SCP Navigation Tests")
struct PrintSCPNavigationTests {

    @Test("printSCP is a navigable destination")
    func testDestinationExists() {
        #expect(NavigationDestination.allCases.contains(.printSCP))
        #expect(NavigationDestination.printSCP.rawValue == "Printer Emulator")
    }

    @Test("printSCP has an icon and an accessibility label")
    func testDestinationLabels() {
        #expect(!NavigationDestination.printSCP.systemImage.isEmpty)
        #expect(!NavigationDestination.printSCP.accessibilityLabel.isEmpty)
    }

    @Test("printSCP sits beside Print under Data & Tools")
    func testDestinationPlacement() throws {
        #expect(NavigationDestination.printSCP.category == .dataTools)
        let allCases = NavigationDestination.allCases
        let printIndex = try #require(allCases.firstIndex(of: .printing))
        let scpIndex = try #require(allCases.firstIndex(of: .printSCP))
        #expect(scpIndex == printIndex + 1)
    }

    @Test("printSCP is a primary destination")
    func testPrimaryDestination() {
        #expect(NavigationService.primaryDestinations.contains(.printSCP))
    }
}

// MARK: - Attribute inspector

#if canImport(SwiftUI)
@Suite("Print SCP Attribute Inspector Tests")
struct PrintSCPAttributeRowTests {

    @Test("the inspector reports the film-box attributes an SCU asked for")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testAttributeRows() {
        let rows = PrintSCPView.attributeRows(makeFilmInfo())
        let labels = rows.map(\.0)
        #expect(labels.contains("Calling AE"))
        #expect(labels.contains("Film Size ID (2010,0050)"))   // PS3.6 Table 6-1 name of (2010,0050)
        #expect(labels.contains("Image Display Format (2010,0010)"))
        #expect(labels.contains("Min Density (2010,0120)"))
        #expect(labels.contains("Presentation LUT Shape (2050,0020)"))
        #expect(labels.contains("Annotation 1"))
        let images = rows.first { $0.0 == "Images" }?.1
        #expect(images == "3 of 4 boxes filled")
    }

    @Test("absent optional attributes are left out rather than shown empty")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testOptionalAttributesOmitted() {
        var info = makeFilmInfo()
        info = ComposedFilmInfo(
            printJobUID: info.printJobUID, filmSessionUID: info.filmSessionUID,
            filmBoxUID: info.filmBoxUID, callingAETitle: info.callingAETitle,
            receivedAt: info.receivedAt, filmSize: info.filmSize,
            filmOrientation: info.filmOrientation, imageDisplayFormat: info.imageDisplayFormat,
            rows: info.rows, columns: info.columns, mediumType: info.mediumType,
            numberOfCopies: info.numberOfCopies, filmSessionLabel: nil,
            magnificationType: info.magnificationType, borderDensity: info.borderDensity,
            emptyImageDensity: info.emptyImageDensity, trim: info.trim,
            minDensity: nil, maxDensity: nil, presentationLUTShape: nil,
            annotations: [], sheetWidthMillimeters: info.sheetWidthMillimeters,
            sheetHeightMillimeters: info.sheetHeightMillimeters, dpi: info.dpi,
            densityMapping: info.densityMapping,
            filledImageBoxCount: info.filledImageBoxCount,
            imageBoxCount: info.imageBoxCount, skippedImageBoxes: [])

        let labels = PrintSCPView.attributeRows(info).map(\.0)
        #expect(!labels.contains("Min Density (2010,0120)"))
        #expect(!labels.contains("Film Session Label (2000,0050)"))
        #expect(!labels.contains("Annotation 1"))
    }
}
#endif

// MARK: - End to end

#if canImport(Network)
/// Drives the screen's listener with a real Print SCU.
///
/// The unit tests above prove the settings reach the configuration; this proves
/// the screen is wired to the protocol machine at all — a film sent by an SCU
/// has to arrive, be composed, and land in the list the UI renders.
@Suite("Print SCP End-to-End Tests", .serialized)
struct PrintSCPEndToEndTests {

    /// A 2×2 8-bit MONOCHROME2 image and its descriptor.
    private func makeImage() -> (Data, PrintImageData) {
        let pixels = Data([0, 64, 128, 255])
        return (pixels, PrintImageData(
            pixelData: pixels,
            rows: 2, columns: 2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 1, pixelRepresentation: 0,
            photometricInterpretation: "MONOCHROME2"))
    }

    @Test("a film sent by a Print SCU is received, composed and listed")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testReceivesFilmFromSCU() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PrintSCPE2E-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let viewModel = PrintSCPViewModel(
            storage: PrintSCPSettingsStorageService(
                storageService: StorageService(baseDirectory: directory)))
        viewModel.settings.aeTitle = "STUDIOPRINT"
        viewModel.settings.port = 0          // ephemeral: no race for a fixed port
        viewModel.settings.dpi = 72          // a draft sheet keeps the test quick
        await viewModel.start()

        #expect(viewModel.isRunning)
        #expect(viewModel.startErrorMessage == nil)
        let port = viewModel.boundPort
        #expect(port != 0)

        let (pixels, descriptor) = makeImage()
        let result = try await DICOMPrintService.printImages(
            configuration: PrintConfiguration(
                host: "127.0.0.1", port: port,
                callingAETitle: "TESTSCU", calledAETitle: "STUDIOPRINT",
                timeout: 15),
            images: [pixels],
            imageDescriptors: [descriptor])
        #expect(result.success)

        // The view model exposes two independently-delivered signals: `films` (the
        // record array, from the sink stream) and `filmCount` (the `.filmPrinted`
        // counter). Waiting on `films` alone can arrive before the counter it is
        // asserted against, so both are waited for. The wait is against a deadline
        // rather than a fixed number of sleeps: under a loaded run the sleeps
        // themselves are what get delayed, so a tick budget expires in far less
        // wall-clock time than it reads as.
        let deadline = ContinuousClock.now + .seconds(30)
        while viewModel.films.isEmpty || viewModel.filmCount < 1,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(viewModel.films.count == 1)
        #expect(viewModel.filmCount == 1)
        #expect(viewModel.associationCount == 1)
        let film = try #require(viewModel.films.first)
        #expect(film.film.info.callingAETitle == "TESTSCU")
        #expect(film.film.info.filledImageBoxCount == 1)
        #expect(film.film.width > 0 && film.film.height > 0)
        #expect(viewModel.selectedFilmID == film.id)

        await viewModel.stop()
        #expect(!viewModel.isRunning)
    }

    @Test("a rejected calling AE is reported rather than silently dropped")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @MainActor
    func testRejectsUnlistedCallingAE() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PrintSCPE2E-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let viewModel = PrintSCPViewModel(
            storage: PrintSCPSettingsStorageService(
                storageService: StorageService(baseDirectory: directory)))
        viewModel.settings.aeTitle = "STUDIOPRINT"
        viewModel.settings.port = 0
        viewModel.settings.allowedCallingAETitles = "APPROVED"
        await viewModel.start()
        #expect(viewModel.isRunning)

        let (pixels, descriptor) = makeImage()
        let result = try? await DICOMPrintService.printImages(
            configuration: PrintConfiguration(
                host: "127.0.0.1", port: viewModel.boundPort,
                callingAETitle: "STRANGER", calledAETitle: "STUDIOPRINT",
                timeout: 10),
            images: [pixels],
            imageDescriptors: [descriptor])
        #expect(result?.success != true)
        #expect(viewModel.films.isEmpty)

        await viewModel.stop()
    }
}
#endif
