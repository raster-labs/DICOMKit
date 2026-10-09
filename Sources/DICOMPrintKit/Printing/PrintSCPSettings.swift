// NEMA-verified: 2026a, checked 2026-09-29 — Printer Status NORMAL/WARNING/FAILURE per PS3.3 2026a Table C.13-9 and default Printer Status Info per C.13.9.1 Defined Terms (NO SUPPLY corrected to SUPPLY EMPTY); Medium Type / Film Size tokens via PrintOptionCatalog
//
// PrintSCPSettings.swift
// DICOMPrintKit
//
// The printer emulator's configuration, shared by every surface that runs one.
//
// This is the SCP-side counterpart of `PrintJobRequest`: one settings type that
// both DICOM Studio's Print SCP screen and the `dicom-printscp` CLI fill in, and
// one mapping from those settings onto `PrintSCPConfiguration` (the protocol
// machine) and `FilmComposerConfiguration` (the sheet). Neither surface builds
// those configurations itself, so a film received by the app and a film received
// by the CLI are negotiated and composed identically.
//

import Foundation
import DICOMCore
import DICOMNetwork

// MARK: - Output format

/// The image container auto-saved films are written to.
///
/// Mirrors ``ImageSink/Format`` — declared separately only because the sink's
/// format enum is `CoreGraphics`-gated and this must stay `Codable` everywhere.
public enum FilmImageFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case png
    case tiff

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .png:  return "PNG"
        case .tiff: return "TIFF"
        }
    }
}

// MARK: - Reported status

/// The Printer Status (2110,0010) the emulator reports to N-GET.
///
/// Selectable so an SCU's error handling can be exercised against a printer
/// that says it is out of film — the reason an emulator beats real hardware.
public enum EmulatedPrinterStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case normal = "NORMAL"
    case warning = "WARNING"
    case failure = "FAILURE"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .normal:  return "Normal"
        case .warning: return "Warning"
        case .failure: return "Failure"
        }
    }

    /// Default Printer Status Info (2110,0020) for the state — NORMAL, SUPPLY
    /// LOW and SUPPLY EMPTY, each a Defined Term of PS3.3 C.13.9.1.
    public var defaultStatusInfo: String {
        switch self {
        case .normal:  return "NORMAL"
        case .warning: return "SUPPLY LOW"
        case .failure: return "SUPPLY EMPTY"
        }
    }
}

// MARK: - Settings

/// Everything a printer emulator can be configured with.
///
/// Persisted as JSON by both surfaces (Studio's `PrintSCPSettingsStorageService`
/// and the CLI's `--config`) so a listener comes back on the same port and AE
/// title after a relaunch — a modality is configured once against this printer
/// and must keep finding it.
///
/// Decoding is deliberately tolerant: every field falls back to its default when
/// absent, so a settings file written by an older build keeps working instead of
/// silently reverting the *whole* configuration to defaults.
public struct PrintSCPSettings: Codable, Sendable, Equatable {

    // MARK: Identity and transport

    /// The AE title the emulator answers as (Called AE).
    public var aeTitle: String

    /// The TCP port to listen on.
    ///
    /// Defaults to 11113 rather than the usual 11112: Studio's own Storage SCP
    /// (CLI Workshop → Local Listener) defaults to 11112, and two listeners on
    /// one port fail to bind with nothing but "Address already in use".
    public var port: Int

    /// Maximum concurrent associations.
    public var maxConcurrentAssociations: Int

    /// Seconds an established association may sit idle before it is aborted.
    /// `0` disables the timeout.
    public var associationIdleTimeoutSeconds: Double

    /// Calling AE titles allowed to associate, comma- or whitespace-separated.
    /// Empty accepts every caller.
    public var allowedCallingAETitles: String

    /// Calling AE titles refused, comma- or whitespace-separated. Takes
    /// precedence over ``allowedCallingAETitles``.
    public var deniedCallingAETitles: String

    /// Maximum PDU size accepted during negotiation, in bytes.
    public var maxPDUSize: Int

    // MARK: Negotiated capability

    /// Whether the Color Print Management Meta SOP Class is accepted.
    public var supportsColor: Bool

    /// Whether Presentation LUT N-CREATE is accepted.
    public var acceptPresentationLUT: Bool

    /// Whether Basic Annotation Box N-CREATE / N-SET is accepted.
    public var acceptAnnotationBox: Bool

    /// How many Basic Annotation Boxes a film box offers when the SCU supplies
    /// an Annotation Display Format ID.
    public var annotationBoxesPerFilm: Int

    /// Whether Print Job N-EVENT-REPORTs are pushed after N-ACTION.
    public var pushPrintJobEvents: Bool

    /// Film Size IDs this printer accepts, as CLI tokens ("14x17"). Empty
    /// accepts every size the library knows.
    public var supportedFilmSizeTokens: [String]

    /// Medium Types this printer accepts, as CLI tokens ("paper"). Empty
    /// accepts every medium.
    public var supportedMediumTokens: [String]

    /// Maximum number of image boxes a single film box may declare.
    public var maxImageBoxesPerFilm: Int

    /// Largest image dimension (rows or columns) accepted in an image box.
    public var maxImageBoxPixelDimension: Int

    // MARK: Reported printer characteristics (N-GET on the Printer SOP Instance)

    public var printerName: String
    public var manufacturer: String
    public var manufacturerModelName: String
    public var deviceSerialNumber: String
    public var softwareVersion: String

    /// The Printer Status the emulator reports.
    public var printerStatus: EmulatedPrinterStatus

    /// Printer Status Info; empty uses the status's own default text.
    public var printerStatusInfo: String

    // MARK: Composition

    /// Rasterization resolution of the composed sheet.
    public var dpi: Double

    /// The resolution a fresh install composes at, and what "Reset" restores.
    ///
    /// 600 DPI is the native resolution of the common dry-imager families
    /// (DryPix, DryView, Drystar), so a sheet composed at it maps one composed
    /// pixel to one printed dot with no resampling on the way out.
    public static let defaultDPI: Double = 600

    /// The range the composer accepts; values outside it are clamped there.
    ///
    /// The ceiling is 650: film imagers top out around there — 600 DPI is the
    /// native resolution of the common dry-imager families and the highest any
    /// of them addresses, so anything beyond it is resolution the film cannot
    /// hold. Composing higher only costs memory (a 14×17 in sheet grows with
    /// the square of DPI) and is resampled back down at the printer.
    public static let dpiRange: ClosedRange<Double> = 36...650

    /// How optical density is interpreted when the film is rendered.
    public var densityMapping: DensityMapping

    /// Whether Basic Annotation Box text is drawn on the sheet.
    public var drawAnnotations: Bool

    /// Which edge of the sheet the annotation band occupies (FR-006:
    /// footer, header, side, or drawn over the images).
    public var annotationEdge: FilmAnnotationEdge

    /// Whether a trim box is printed around each image when Trim (2010,0140) is YES (PS3.3 Table C.13-3).
    public var drawTrimMarks: Bool

    /// A pseudo-colour palette laid over received films when they are rendered.
    ///
    /// Off by default, and deliberately: an image box's P-Values are what the
    /// sending operator approved, and Print Management has no way to ask for a
    /// palette or to report that one was used ("palette" appears nowhere in
    /// PS3.4 Annex H). Recolouring silently would make the emulator's film
    /// disagree with the screen the study was signed off on.
    ///
    /// So this is a local viewing control and nothing more. It reaches the
    /// composed sheet — the preview, and the auto-saved PNG/TIFF of it — while
    /// the received P-Values are left exactly as they arrived. Nothing that goes
    /// back on the wire is affected, which is what keeps the emulator conformant
    /// with the palette switched on.
    public var previewPalette: PseudoColorPalette?

    /// Sheet margin in millimetres on all four edges.
    public var marginMillimeters: Double

    /// Gap between adjacent image cells, in millimetres.
    public var cellSpacingMillimeters: Double

    /// Safety cap on the composed bitmap's longest side, in pixels.
    public var maximumPixelDimension: Int

    // MARK: Output

    /// Directory auto-saved films are written to. Empty uses `~/Downloads`.
    public var outputDirectory: String

    /// Write every received film to a PDF.
    public var savePDF: Bool

    /// Write every received film to an image file.
    public var saveImage: Bool

    /// The container used when ``saveImage`` is set.
    public var imageFormat: FilmImageFormat

    /// File-name pattern for saved films (tokens: `{job}`, `{session}`,
    /// `{film}`, `{ae}`, `{index}`, `{timestamp}`).
    public var fileNamePattern: String

    /// Spool every received film to a real printer queue via CUPS `lp`.
    public var sendToPaperQueue: Bool

    /// The CUPS queue name; empty uses the system default queue.
    public var paperQueue: String

    // MARK: Retention

    /// How many received films a surface keeps for review.
    public var retainedFilmLimit: Int

    /// Memory ceiling for retained films, in megabytes. Films are evicted
    /// oldest-first once the retained bitmaps exceed it — a 14×17 in sheet at
    /// 300 DPI is ~21 MB, so an unbounded scrollback exhausts memory in minutes
    /// on a busy listener.
    public var retainedMemoryBudgetMB: Int

    public init(
        aeTitle: String = "DCMPRINT",
        port: Int = 11113,
        maxConcurrentAssociations: Int = 10,
        associationIdleTimeoutSeconds: Double = 300,
        allowedCallingAETitles: String = "",
        deniedCallingAETitles: String = "",
        maxPDUSize: Int = Int(defaultMaxPDUSize),
        supportsColor: Bool = true,
        acceptPresentationLUT: Bool = true,
        acceptAnnotationBox: Bool = true,
        annotationBoxesPerFilm: Int = 6,
        pushPrintJobEvents: Bool = false,
        supportedFilmSizeTokens: [String] = [],
        supportedMediumTokens: [String] = [],
        maxImageBoxesPerFilm: Int = 64,
        maxImageBoxPixelDimension: Int = 10000,
        printerName: String = "DICOMKIT-PRINTER",
        manufacturer: String = "DICOMKit",
        manufacturerModelName: String = "DICOM Print Emulator",
        deviceSerialNumber: String = "1",
        softwareVersion: String = "1.0",
        printerStatus: EmulatedPrinterStatus = .normal,
        printerStatusInfo: String = "",
        dpi: Double = PrintSCPSettings.defaultDPI,
        densityMapping: DensityMapping = .paperDirect,
        drawAnnotations: Bool = true,
        annotationEdge: FilmAnnotationEdge = .bottom,
        drawTrimMarks: Bool = true,
        previewPalette: PseudoColorPalette? = nil,
        marginMillimeters: Double = 5,
        cellSpacingMillimeters: Double = 2,
        maximumPixelDimension: Int = 12000,
        outputDirectory: String = "",
        savePDF: Bool = false,
        saveImage: Bool = false,
        imageFormat: FilmImageFormat = .png,
        fileNamePattern: String = "film-{timestamp}-{index}",
        sendToPaperQueue: Bool = false,
        paperQueue: String = "",
        retainedFilmLimit: Int = 20,
        retainedMemoryBudgetMB: Int = 256
    ) {
        self.aeTitle = aeTitle
        self.port = port
        self.maxConcurrentAssociations = maxConcurrentAssociations
        self.associationIdleTimeoutSeconds = associationIdleTimeoutSeconds
        self.allowedCallingAETitles = allowedCallingAETitles
        self.deniedCallingAETitles = deniedCallingAETitles
        self.maxPDUSize = maxPDUSize
        self.supportsColor = supportsColor
        self.acceptPresentationLUT = acceptPresentationLUT
        self.acceptAnnotationBox = acceptAnnotationBox
        self.annotationBoxesPerFilm = annotationBoxesPerFilm
        self.pushPrintJobEvents = pushPrintJobEvents
        self.supportedFilmSizeTokens = supportedFilmSizeTokens
        self.supportedMediumTokens = supportedMediumTokens
        self.maxImageBoxesPerFilm = maxImageBoxesPerFilm
        self.maxImageBoxPixelDimension = maxImageBoxPixelDimension
        self.printerName = printerName
        self.manufacturer = manufacturer
        self.manufacturerModelName = manufacturerModelName
        self.deviceSerialNumber = deviceSerialNumber
        self.softwareVersion = softwareVersion
        self.printerStatus = printerStatus
        self.printerStatusInfo = printerStatusInfo
        self.dpi = dpi
        self.densityMapping = densityMapping
        self.drawAnnotations = drawAnnotations
        self.annotationEdge = annotationEdge
        self.previewPalette = previewPalette
        self.drawTrimMarks = drawTrimMarks
        self.marginMillimeters = marginMillimeters
        self.cellSpacingMillimeters = cellSpacingMillimeters
        self.maximumPixelDimension = maximumPixelDimension
        self.outputDirectory = outputDirectory
        self.savePDF = savePDF
        self.saveImage = saveImage
        self.imageFormat = imageFormat
        self.fileNamePattern = fileNamePattern
        self.sendToPaperQueue = sendToPaperQueue
        self.paperQueue = paperQueue
        self.retainedFilmLimit = retainedFilmLimit
        self.retainedMemoryBudgetMB = retainedMemoryBudgetMB
    }

    // MARK: Codable

    /// Decodes field by field, defaulting anything the stored file lacks.
    ///
    /// The all-or-nothing synthesized initializer would turn one unknown build's
    /// settings file into a wholesale reset — including the port and AE title a
    /// modality was configured against, which is the one thing that must survive.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = PrintSCPSettings()

        func string(_ key: CodingKeys, _ value: String) -> String {
            (try? container.decodeIfPresent(String.self, forKey: key)).flatMap { $0 } ?? value
        }
        func int(_ key: CodingKeys, _ value: Int) -> Int {
            (try? container.decodeIfPresent(Int.self, forKey: key)).flatMap { $0 } ?? value
        }
        func double(_ key: CodingKeys, _ value: Double) -> Double {
            (try? container.decodeIfPresent(Double.self, forKey: key)).flatMap { $0 } ?? value
        }
        func bool(_ key: CodingKeys, _ value: Bool) -> Bool {
            (try? container.decodeIfPresent(Bool.self, forKey: key)).flatMap { $0 } ?? value
        }
        func strings(_ key: CodingKeys, _ value: [String]) -> [String] {
            (try? container.decodeIfPresent([String].self, forKey: key)).flatMap { $0 } ?? value
        }

        self.init(
            aeTitle: string(.aeTitle, fallback.aeTitle),
            port: int(.port, fallback.port),
            maxConcurrentAssociations: int(.maxConcurrentAssociations, fallback.maxConcurrentAssociations),
            associationIdleTimeoutSeconds: double(.associationIdleTimeoutSeconds, fallback.associationIdleTimeoutSeconds),
            allowedCallingAETitles: string(.allowedCallingAETitles, fallback.allowedCallingAETitles),
            deniedCallingAETitles: string(.deniedCallingAETitles, fallback.deniedCallingAETitles),
            maxPDUSize: int(.maxPDUSize, fallback.maxPDUSize),
            supportsColor: bool(.supportsColor, fallback.supportsColor),
            acceptPresentationLUT: bool(.acceptPresentationLUT, fallback.acceptPresentationLUT),
            acceptAnnotationBox: bool(.acceptAnnotationBox, fallback.acceptAnnotationBox),
            annotationBoxesPerFilm: int(.annotationBoxesPerFilm, fallback.annotationBoxesPerFilm),
            pushPrintJobEvents: bool(.pushPrintJobEvents, fallback.pushPrintJobEvents),
            supportedFilmSizeTokens: strings(.supportedFilmSizeTokens, fallback.supportedFilmSizeTokens),
            supportedMediumTokens: strings(.supportedMediumTokens, fallback.supportedMediumTokens),
            maxImageBoxesPerFilm: int(.maxImageBoxesPerFilm, fallback.maxImageBoxesPerFilm),
            maxImageBoxPixelDimension: int(.maxImageBoxPixelDimension, fallback.maxImageBoxPixelDimension),
            printerName: string(.printerName, fallback.printerName),
            manufacturer: string(.manufacturer, fallback.manufacturer),
            manufacturerModelName: string(.manufacturerModelName, fallback.manufacturerModelName),
            deviceSerialNumber: string(.deviceSerialNumber, fallback.deviceSerialNumber),
            softwareVersion: string(.softwareVersion, fallback.softwareVersion),
            printerStatus: (try? container.decodeIfPresent(EmulatedPrinterStatus.self, forKey: .printerStatus))
                .flatMap { $0 } ?? fallback.printerStatus,
            printerStatusInfo: string(.printerStatusInfo, fallback.printerStatusInfo),
            dpi: double(.dpi, fallback.dpi),
            densityMapping: (try? container.decodeIfPresent(DensityMapping.self, forKey: .densityMapping))
                .flatMap { $0 } ?? fallback.densityMapping,
            drawAnnotations: bool(.drawAnnotations, fallback.drawAnnotations),
            annotationEdge: (try? container.decodeIfPresent(FilmAnnotationEdge.self, forKey: .annotationEdge))
                .flatMap { $0 } ?? fallback.annotationEdge,
            drawTrimMarks: bool(.drawTrimMarks, fallback.drawTrimMarks),
            previewPalette: (try? container.decodeIfPresent(
                PseudoColorPalette.self, forKey: .previewPalette))
                .flatMap { $0 } ?? fallback.previewPalette,
            marginMillimeters: double(.marginMillimeters, fallback.marginMillimeters),
            cellSpacingMillimeters: double(.cellSpacingMillimeters, fallback.cellSpacingMillimeters),
            maximumPixelDimension: int(.maximumPixelDimension, fallback.maximumPixelDimension),
            outputDirectory: string(.outputDirectory, fallback.outputDirectory),
            savePDF: bool(.savePDF, fallback.savePDF),
            saveImage: bool(.saveImage, fallback.saveImage),
            imageFormat: (try? container.decodeIfPresent(FilmImageFormat.self, forKey: .imageFormat))
                .flatMap { $0 } ?? fallback.imageFormat,
            fileNamePattern: string(.fileNamePattern, fallback.fileNamePattern),
            sendToPaperQueue: bool(.sendToPaperQueue, fallback.sendToPaperQueue),
            paperQueue: string(.paperQueue, fallback.paperQueue),
            retainedFilmLimit: int(.retainedFilmLimit, fallback.retainedFilmLimit),
            retainedMemoryBudgetMB: int(.retainedMemoryBudgetMB, fallback.retainedMemoryBudgetMB)
        )
    }

    // MARK: Derived values

    /// The effective AE title, falling back to the default when blank.
    public var effectiveAETitle: String {
        let trimmed = aeTitle.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "DCMPRINT" : trimmed
    }

    /// The parsed calling-AE whitelist; `nil` accepts every caller.
    public var callingAEWhitelist: Set<String>? {
        Self.parseAETitles(allowedCallingAETitles)
    }

    /// The parsed calling-AE blacklist; `nil` refuses nobody.
    public var callingAEBlacklist: Set<String>? {
        Self.parseAETitles(deniedCallingAETitles)
    }

    /// Splits a comma- or whitespace-separated AE title list.
    static func parseAETitles(_ list: String) -> Set<String>? {
        let titles = list
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return titles.isEmpty ? nil : Set(titles)
    }

    /// Film sizes the emulator accepts; every known size when unconstrained.
    public var supportedFilmSizes: Set<FilmSize> {
        let sizes = supportedFilmSizeTokens.compactMap { PrintOptionCatalog.filmSize(forToken: $0.lowercased()) }
        return sizes.isEmpty ? Set(FilmSize.allCases) : Set(sizes)
    }

    /// Medium types the emulator accepts; every known type when unconstrained.
    public var supportedMediumTypes: Set<MediumType> {
        let media = supportedMediumTokens.compactMap { PrintOptionCatalog.mediumType(forToken: $0.lowercased()) }
        return media.isEmpty ? Set(MediumType.allCases) : Set(media)
    }

    /// Where auto-saved films are written.
    public var outputDirectoryURL: URL {
        let trimmed = outputDirectory.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            let downloads = NSSearchPathForDirectoriesInDomains(
                .downloadsDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
            return URL(fileURLWithPath: downloads).appendingPathComponent("DICOMKit Films")
        }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
    }

    /// The Printer Status Info reported to N-GET.
    public var effectivePrinterStatusInfo: String {
        let trimmed = printerStatusInfo.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? printerStatus.defaultStatusInfo : trimmed
    }

    /// The printer status as the network layer's value type.
    public var reportedPrinterStatus: PrinterStatus {
        PrinterStatus(
            status: printerStatus.rawValue,
            statusInfo: effectivePrinterStatusInfo,
            printerName: printerName,
            manufacturer: manufacturer,
            manufacturerModelName: manufacturerModelName)
    }

    /// Retained-film memory ceiling in bytes.
    public var retainedMemoryBudgetBytes: Int {
        max(1, retainedMemoryBudgetMB) * 1_048_576
    }

    /// Builds the SCP configuration.
    ///
    /// - Throws: `DICOMError` when the AE title is not a legal DICOM AE title.
    public func makeConfiguration() throws -> PrintSCPConfiguration {
        PrintSCPConfiguration(
            aeTitle: try AETitle(effectiveAETitle),
            port: UInt16(clamping: max(0, port)),
            maxPDUSize: UInt32(clamping: max(0, maxPDUSize)),
            maxConcurrentAssociations: maxConcurrentAssociations,
            callingAEWhitelist: callingAEWhitelist,
            callingAEBlacklist: callingAEBlacklist,
            supportsColor: supportsColor,
            supportedFilmSizes: supportedFilmSizes,
            supportedMediumTypes: supportedMediumTypes,
            maxImageBoxesPerFilm: maxImageBoxesPerFilm,
            maxImageBoxPixelDimension: UInt16(clamping: max(0, maxImageBoxPixelDimension)),
            printerName: printerName,
            manufacturer: manufacturer,
            manufacturerModelName: manufacturerModelName,
            deviceSerialNumber: deviceSerialNumber,
            softwareVersion: softwareVersion,
            acceptPresentationLUT: acceptPresentationLUT,
            acceptAnnotationBox: acceptAnnotationBox,
            annotationBoxesPerFilm: annotationBoxesPerFilm,
            associationIdleTimeout: associationIdleTimeoutSeconds,
            pushPrintJobEvents: pushPrintJobEvents)
    }

    /// Builds the film-composition configuration.
    public func makeComposerConfiguration() -> FilmComposerConfiguration {
        FilmComposerConfiguration(
            dpi: dpi,
            densityMapping: densityMapping,
            marginMillimeters: marginMillimeters,
            cellSpacingMillimeters: cellSpacingMillimeters,
            drawAnnotations: drawAnnotations,
            annotationEdge: annotationEdge,
            drawTrimMarks: drawTrimMarks,
            maximumPixelDimension: maximumPixelDimension,
            previewPalette: previewPalette)
    }
}

// MARK: - Persistence

/// Reads and writes ``PrintSCPSettings`` JSON.
///
/// Both surfaces persist the same document with the same formatting — Studio in
/// its application-support directory, `dicom-printscp` at `--config` — so a
/// settings file can be moved between them and a diff of the two is meaningful.
/// Only the location differs, which is the one thing a sandboxed app and a CLI
/// genuinely cannot share.
public enum PrintSCPSettingsFile {

    /// Encodes settings as pretty-printed, key-sorted JSON.
    public static func encode(_ settings: PrintSCPSettings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    /// Decodes settings from JSON.
    public static func decode(_ data: Data) throws -> PrintSCPSettings {
        try JSONDecoder().decode(PrintSCPSettings.self, from: data)
    }

    /// Writes settings to `url`, creating the enclosing directory.
    public static func write(_ settings: PrintSCPSettings, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(settings).write(to: url, options: .atomic)
    }

    /// Reads settings from `url`, returning defaults when the file is missing or
    /// unreadable.
    ///
    /// A settings file written by an older build that no longer decodes must not
    /// stop the printer from starting, so failures fall back to the defaults
    /// rather than propagating.
    public static func read(from url: URL) -> PrintSCPSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? decode(data) else {
            return PrintSCPSettings()
        }
        return settings
    }
}

// MARK: - SCP-side option tokens

extension PrintOptionCatalog {

    /// Resolves a CLI medium token ("clear-film") to its `MediumType`.
    public static func mediumType(forToken token: String) -> MediumType? {
        mediumTypes.first { $0.cliToken == token }?.value
    }

    /// Density interpretations offered by the emulator, in `--density` order.
    public static let densityMappings: [(value: DensityMapping, cliToken: String, label: String)] = [
        (.paperDirect,   "paper", "Paper (direct)"),
        (.filmEmulation, "film",  "Film emulation"),
        (.gsdf,          "gsdf",  "Calibrated (PS3.14 GSDF)")
    ]

    /// Resolves a CLI density token ("film") to its `DensityMapping`.
    public static func densityMapping(forToken token: String) -> DensityMapping? {
        densityMappings.first { $0.cliToken == token }?.value
    }

    /// Printer statuses the emulator can report, in `--printer-status` order.
    public static let emulatedPrinterStatuses: [(value: EmulatedPrinterStatus, cliToken: String, label: String)] = [
        (.normal,  "normal",  "Normal"),
        (.warning, "warning", "Warning"),
        (.failure, "failure", "Failure")
    ]

    /// Resolves a CLI printer-status token ("warning") to its status.
    public static func emulatedPrinterStatus(forToken token: String) -> EmulatedPrinterStatus? {
        emulatedPrinterStatuses.first { $0.cliToken == token }?.value
    }
}
