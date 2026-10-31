// NEMA-verified: 2026a, checked 2026-10-01 — film-box option vocabularies text-diffed against PS3.3 2026a Tables C.13-1 (Medium Type 5), C.13-3 (Film Size ID 12, Film Orientation 2, Magnification Type 4, Image Display Format 6 forms, Border/Empty Image Density BLACK/WHITE/i, Trim 2), C.13-5 (Polarity 2 with default NORMAL; Bits Stored 8/12) and C.11-4 (Presentation LUT Shape 2): all match (Image Display Format forms and numeric densities added in this pass)
//
// SCPSimulateCommand.swift
// dicom-printscp
//
// `dicom-printscp simulate` — compose a film with no network in the way.
//
// The composer dev loop: iterate on layout, density and DPI without standing up
// an SCU and an SCP. The images go through the same `PrintImagePreparer` an SCU
// sends them through, and the sheet comes out of the same `FilmComposer` the
// emulator composes with, so what lands here is what `serve` would have written.
//

import Foundation
import ArgumentParser
import DICOMKit
import DICOMNetwork
import DICOMPrintKit

struct SCPSimulateCommand: PrintExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "simulate",
        abstract: "Compose film from DICOM files locally, without a network",
        discussion: """
            Prepares the given files exactly as a Print SCU would, lays them out
            exactly as the emulator would, and writes the composed sheet.

            Films spill as they do on the wire: images fill the layout's cells and
            a new sheet starts when the grid is full.

            Examples:
              dicom-printscp simulate scan.dcm --output png
              dicom-printscp simulate study/ --recursive --layout 2x2 --output pdf
              dicom-printscp simulate ct.dcm --density film --dpi 150 --open
            """
    )

    @Argument(help: "DICOM files or directories to compose")
    var paths: [String]

    @OptionGroup var composition: SCPCompositionOptions
    @OptionGroup var filmOutput: SCPFilmOutputOptions
    @OptionGroup var configOptions: SCPConfigOptions

    // MARK: Film box

    @Option(name: .long, help: "Image Display Format (2010,0010): a grid \(SCPOptionTokens.layouts) (R rows by C columns, sent as STANDARD\\C,R) or any PS3.3 Table C.13-3 form — STANDARD\\C,R, ROW\\R1,R2,..., COL\\C1,C2,..., SLIDE, SUPERSLIDE, CUSTOM\\i (auto if omitted)")
    var layout: String?

    @Option(name: .long, help: "Film Size ID (2010,0050): \(SCPOptionTokens.filmSizes) (default: 14x17)")
    var filmSize: String?

    @Option(name: .long, help: "Film Orientation (2010,0040): \(SCPOptionTokens.orientations) (default: portrait)")
    var orientation: String?

    @Option(name: .long, help: "Magnification Type (2010,0060): \(SCPOptionTokens.magnifications) (default: replicate)")
    var magnification: String?

    @Option(name: .long, help: "Medium Type (2000,0030): \(SCPOptionTokens.media) (default: paper)")
    var medium: String?

    @Option(name: .long, help: "Number of Copies (2000,0010) recorded on the film (default: 1)")
    var copies: Int = 1

    @Option(name: .long, help: "Polarity (2020,0020): \(SCPOptionTokens.polarities) (default: normal; PS3.3 Table C.13-5: NORMAL when absent)")
    var polarity: String?

    @Option(name: .long, help: "Presentation LUT Shape (2050,0020): \(SCPOptionTokens.presentationLUTShapes) (default: none)")
    var presentationLut: String?

    @Flag(name: .long, help: "Trim (2010,0140) = YES (default: NO)")
    var trim: Bool = false

    @Option(name: .long, help: "Border Density (2010,0100): BLACK, WHITE, or i hundredths of OD (150 = 1.5 OD) (default: BLACK)")
    var borderDensity: String?

    @Option(name: .long, help: "Empty Image Density (2010,0110): BLACK, WHITE, or i hundredths of OD (default: BLACK)")
    var emptyDensity: String?

    @Option(name: .long, help: "Text String (2030,0020) of a Basic Annotation Box (repeatable; requires --annotation-format)")
    var annotate: [String] = []

    @Option(name: .long, help: "Annotation Display Format ID (2010,0030) (required with --annotate)")
    var annotationFormat: String?

    // MARK: Pixel preparation

    @Option(name: .long, help: "Image box class: grayscale = Basic Grayscale Image Box SOP Class, color = Basic Color Image Box SOP Class (default: grayscale)")
    var color: String?

    @Option(name: .long, help: "1-based frame to take from multi-frame files (default: 1)")
    var frame: Int = 1

    @Flag(name: .long, help: "Take every frame of multi-frame files (one cell per frame)")
    var allFrames: Bool = false

    @Flag(name: .long, help: "Use stored pixel values with no rescale / window / inversion")
    var raw: Bool = false

    @Option(name: .long, help: "Explicit VOI window center (requires --window-width)")
    var windowCenter: Double?

    @Option(name: .long, help: "Explicit VOI window width (requires --window-center)")
    var windowWidth: Double?

    @Option(name: .long, help: "Grayscale Bits Stored: 8 or 12, PS3.3 Table C.13-5 (default: 8)")
    var bitDepth: Int = 8

    // MARK: Input and reporting

    @Flag(name: .shortAndLong, help: "Recursively scan directories for DICOM files")
    var recursive: Bool = false

    @Option(name: .long, help: "Calling AE title recorded on the composed film (default: SIMULATE)")
    var callingAe: String = "SIMULATE"

    @Option(name: .long, help: "Output format: text, json")
    var format: SCPOutputFormat = .text

    @Flag(name: .shortAndLong, help: "Show each film's attributes and per-image progress")
    var verbose: Bool = false

    @Flag(name: .long, help: "Suppress console output; only errors are reported")
    var quiet: Bool = false

    func validate() throws { _ = try makeRequest() }

    private func validateInputs() throws {
        if copies < 1 { throw ValidationError("--copies must be 1 or greater") }
        if frame < 1 { throw ValidationError("--frame is 1-based and must be 1 or greater") }
        if allFrames && frame != 1 { throw ValidationError("--frame and --all-frames are mutually exclusive") }
        if let windowCenter, !windowCenter.isFinite { throw ValidationError("--window-center must be finite") }
        if let windowWidth, !windowWidth.isFinite || windowWidth < 1 { throw ValidationError("--window-width must be finite and 1 or greater") }
        if annotate.count > Int(UInt16.max) { throw ValidationError("Too many --annotate values (maximum 65535)") }
    }

    func execute(context: PrintCommandContext) async throws {
        try validate()
        try Task.checkCancellation()
        let console = SCPConsole(format: format, quiet: quiet, context: context)

        var settings = configOptions.load(context: context)
        try composition.apply(to: &settings)
        try filmOutput.apply(
            to: &settings,
            defaultOutput: "png",
            outputWasConfigured: configOptions.hasStoredSettings(context: context))

        try SCPSettingsChecks.validate(settings, transport: false)
        if configOptions.saveConfig {
            try configOptions.save(settings, context: context)
            console.line("Wrote \(configOptions.url(context: context).path)")
            return
        }

        let request = try makeRequest()
        let files = try gather(paths)
        guard !files.isEmpty else {
            throw PrintSCPCommandError("No DICOM files found in: \(paths.joined(separator: ", "))")
        }
        if verbose { console.line("Composing \(files.count) file(s)") }

        let report: PrintSCPSimulator.ProgressHandler = { @Sendable line in console.line(line) }
        let progress: PrintSCPSimulator.ProgressHandler? = verbose ? report : nil
        let films = try await PrintSCPSimulator().composeFilms(
            paths: files,
            request: request,
            settings: settings,
            callingAETitle: callingAe,
            onProgress: progress)

        guard !films.isEmpty else {
            throw PrintSCPCommandError("Nothing to compose")
        }

        // The same sink stack `serve` uses, so a simulated sheet is written by
        // the same writers with the same naming as a received one.
        let screen = ScreenSink(scrollbackLimit: 1, displayMaxDimension: 256)
        let written = SCPWrittenFilms()
        let sink = try PrintSCPService().makeSink(
            settings: settings,
            screen: screen,
            onFileWritten: { url in written.record(url) },
            onFailure: { sink, error in console.error("Output failed (\(sink)): \(error)") })

        for film in films {
            try Task.checkCancellation()
            try await sink.emit(film)
            switch format {
            case .text:
                console.line(PrintSCPConsole.filmLine(film))
                if verbose { console.lines(PrintSCPConsole.filmDetail(film)) }
            case .json:
                if let json = PrintSCPConsole.filmJSON(film) { console.line(json) }
            }
        }

        for url in written.urls {
            if format == .text { console.line("Wrote \(url.path)") }
            if filmOutput.open { context.openFile(url) }
        }
    }

    // MARK: - Request

    /// Builds the SCU-side job request the simulator composes from.
    func makeRequest() throws -> PrintJobRequest {
        try validateInputs()
        if !annotate.isEmpty, annotationFormat == nil {
            throw PrintSCPCommandError("--annotate requires --annotation-format")
        }
        if (windowCenter == nil) != (windowWidth == nil) {
            throw PrintSCPCommandError("--window-center and --window-width must be given together")
        }
        guard PrintOptionCatalog.bitDepths.contains(bitDepth) else {
            throw PrintSCPCommandError(
                "Invalid --bit-depth \(bitDepth). Valid values: "
                    + PrintOptionCatalog.bitDepths.map(String.init).joined(separator: ", "))
        }

        var request = PrintJobRequest()
        request.copies = max(1, copies)
        if let medium {
            let token = try SCPOptionTokens.validate(
                medium, in: PrintOptionCatalog.mediumTypes.map(\.cliToken),
                terms: SCPOptionTokens.mediumTerms, flag: "--medium")
            request.mediumType = PrintOptionCatalog.mediumType(forToken: token) ?? .paper
        }
        if let layout {
            if let option = PrintLayoutOption(rawValue: layout.lowercased()) {
                request.layoutSelection = .explicit(option)
            } else if let format = PrintImageDisplayFormat.validated(layout) {
                // The forms of PS3.3 Table C.13-3, as `dicom-print --layout` takes them.
                request.layoutSelection = .displayFormat(format)
            } else {
                throw PrintSCPCommandError(
                    "Invalid --layout value '\(layout)'. Valid values: \(SCPOptionTokens.layouts), "
                        + "or an Image Display Format: STANDARD\\C,R, ROW\\R1,R2,..., COL\\C1,C2,..., "
                        + "SLIDE, SUPERSLIDE, CUSTOM\\i")
            }
        }
        if let filmSize {
            let token = try SCPOptionTokens.validate(
                filmSize, in: PrintOptionCatalog.filmSizes.map(\.cliToken),
                terms: SCPOptionTokens.filmSizeTerms, flag: "--film-size")
            request.filmSize = PrintOptionCatalog.filmSize(forToken: token) ?? .size14InX17In
        }
        if let orientation {
            let token = try SCPOptionTokens.validate(
                orientation, in: PrintOptionCatalog.orientations.map(\.cliToken),
                terms: SCPOptionTokens.orientationTerms, flag: "--orientation")
            request.filmOrientation = PrintOptionCatalog.orientations
                .first { $0.cliToken == token }?.value ?? .portrait
        }
        if let magnification {
            let token = try SCPOptionTokens.validate(
                magnification, in: PrintOptionCatalog.magnificationTypes.map(\.cliToken),
                terms: SCPOptionTokens.magnificationTerms, flag: "--magnification")
            request.magnificationType = PrintOptionCatalog.magnificationTypes
                .first { $0.cliToken == token }?.value ?? .replicate
        }
        if let polarity {
            let token = try SCPOptionTokens.validate(
                polarity, in: PrintOptionCatalog.polarities.map(\.cliToken),
                terms: SCPOptionTokens.polarityTerms, flag: "--polarity")
            request.polarity = PrintOptionCatalog.polarities
                .first { $0.cliToken == token }?.value ?? .normal
        }
        if let presentationLut {
            let token = try SCPOptionTokens.validate(
                presentationLut, in: PrintOptionCatalog.presentationLUTShapes.map(\.cliToken),
                terms: SCPOptionTokens.presentationLUTShapeTerms, flag: "--presentation-lut")
            request.presentationLUTShape = PrintOptionCatalog.presentationLUTShapes
                .first { $0.cliToken == token }?.value
        }
        if let color {
            let token = try SCPOptionTokens.validate(
                color, in: PrintOptionCatalog.colorModes.map(\.cliToken), flag: "--color")
            request.colorMode = PrintOptionCatalog.colorModes
                .first { $0.cliToken == token }?.value ?? .grayscale
        }
        if let borderDensity {
            request.borderDensity = try density(borderDensity, flag: "--border-density")
        }
        if let emptyDensity {
            request.emptyImageDensity = try density(emptyDensity, flag: "--empty-density")
        }
        request.trimOption = trim ? .yes : .no
        request.frameSelection = allFrames ? .all : .single(max(1, frame))
        request.raw = raw
        if let windowCenter, let windowWidth {
            request.windowSettings = WindowSettings(center: windowCenter, width: windowWidth)
        }
        request.bitDepth = bitDepth
        request.annotationDisplayFormatID = annotationFormat
        request.annotations = annotate.enumerated().map { index, text in
            DICOMNetwork.PrintAnnotation(position: UInt16(index + 1), text: text)
        }
        try request.validate()
        return request
    }

    /// Border Density (2010,0100) / Empty Image Density (2010,0110): the Defined
    /// Terms BLACK and WHITE, or "i where i represents the desired density in
    /// hundredths of OD" (PS3.3 Table C.13-3), written without leading zeros.
    func density(_ value: String, flag: String) throws -> String {
        let text = value.uppercased()
        if PrintOptionCatalog.densities.contains(text) { return text }
        if !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let hundredths = Int(text) {
            return String(hundredths)
        }
        throw PrintSCPCommandError(
            "Invalid \(flag) value '\(value)'. Valid values: "
                + PrintOptionCatalog.densities.joined(separator: ", ")
                + ", or a density in hundredths of OD (e.g. 150)")
    }

    // MARK: - Input

    /// Expands directories to the files inside them, in sorted order.
    private func gather(_ paths: [String]) throws -> [String] {
        var files: [String] = []
        for path in paths {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                throw PrintSCPCommandError("Path not found: \(path)")
            }
            if isDirectory.boolValue {
                let found = FileGatherer.regularFiles(
                    under: URL(fileURLWithPath: path), recursive: recursive) ?? []
                files.append(contentsOf: found.map(\.path).sorted())
            } else {
                files.append(path)
            }
        }
        return files
    }

}

/// File sink callbacks are synchronous. Retain their URLs synchronously too,
/// so completion cannot race an unstructured Task that records a saved file.
final class SCPWrittenFilms: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    var urls: [URL] { lock.withLock { storage } }
    func record(_ url: URL) { lock.withLock { storage.append(url) } }
}
