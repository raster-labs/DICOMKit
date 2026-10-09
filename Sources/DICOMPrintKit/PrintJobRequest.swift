// NEMA-verified: 2026a, checked 2026-09-29 — Bits Stored 8/12 citation and validation message corrected to PS3.3 2026a Table C.13-5 (D23); Requested Image Size (2020,0030) DS rendering per PS3.5 Table 6.2-1; ROW/COL formats per C.13.3; no other standard data
// PrintJobRequest.swift
// DICOMPrintKit
//
// One value type describing a complete DICOM print job, shared by the
// dicom-print CLI and DICOMStudio so both surfaces expose the same knobs
// with the same defaults and the same validation messages.

import Foundation
import DICOMKit
import DICOMNetwork

// MARK: - Errors

/// A print request that cannot be executed as specified.
///
/// The CLI re-throws these as `ValidationError` with the message unchanged, so
/// the wording here **is** the CLI's user-visible contract.
public struct PrintRequestError: Error, CustomStringConvertible, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
    public var localizedDescription: String { message }
}

// MARK: - Frame Selection

/// Which frame(s) of a multi-frame source become image boxes.
public enum PrintFrameSelection: Sendable, Equatable, Codable {
    /// A single 1-based frame number.
    case single(Int)
    /// Every frame of the file, one image box per frame.
    case all

    /// The default: the first frame.
    public static let first = PrintFrameSelection.single(1)
}

// MARK: - Layout Selection

/// How the film layout (rows × columns) is chosen.
public enum PrintLayoutSelection: Sendable, Equatable, Codable {
    /// Let the print service pick an optimal grid for the image count.
    case automatic
    /// An explicit rows × columns grid.
    case explicit(PrintLayoutOption)
    /// A preset that also fixes film size and orientation.
    case template(PrintTemplatePreset)
    /// Any rows × columns grid, for layouts ``PrintLayoutOption`` does not name.
    ///
    /// The viewer offers every grid from 1×1 to 4×4 so the film can mirror what
    /// is on screen; most of those have no catalogue entry.
    case custom(PrintLayout)

    /// A raw Image Display Format (2010,0010) — the `ROW\` and `COL\` films of
    /// PS3.3 C.13.3, whose rows hold different numbers of images.
    ///
    /// A grid cannot say "one large image over three small ones", which is how a
    /// scout-plus-slices film is laid out and what the standard's band forms
    /// exist for. The format travels as written, so what the printer receives is
    /// what was typed.
    case displayFormat(PrintImageDisplayFormat)

    /// The bounding grid, or `nil` for `.automatic` (the service decides).
    ///
    /// For a band layout this is the *bounding* grid and not the film: use
    /// ``imageDisplayFormat`` for anything that lays cells out or counts them.
    public var layout: PrintLayout? {
        switch self {
        case .automatic:            return nil
        case .explicit(let option): return option.layout
        case .template(let preset): return preset.layout
        case .custom(let layout):   return layout
        case .displayFormat(let format): return format.layout
        }
    }

    /// The Image Display Format this selection sends, or `nil` for `.automatic`.
    public var imageDisplayFormat: PrintImageDisplayFormat? {
        switch self {
        case .automatic:                 return nil
        case .explicit(let option):      return PrintImageDisplayFormat(layout: option.layout)
        case .template(let preset):      return PrintImageDisplayFormat.parse(preset.template.imageDisplayFormat)
        case .custom(let layout):        return PrintImageDisplayFormat(layout: layout)
        case .displayFormat(let format): return format
        }
    }
}

// MARK: - Window space

/// Which value space a request's ``PrintJobRequest/windowSettings`` is stated in.
///
/// A VOI window is two numbers with no unit attached, and the same pair means
/// two different pictures depending on which side of Rescale Slope/Intercept it
/// is read on. A window typed by a user ("40 / 400") is in output units — HU on
/// CT — while a window carried off the viewer has already been divided through
/// the rescale pair, because the renderer works on stored values. Handing one
/// where the other is expected is not a subtle shift: on a CT with an intercept
/// of −1024 (or −8192, which occurs) the window lands entirely outside the
/// pixels and the frame prints black.
///
/// So the space travels with the numbers rather than being assumed.
public enum PrintWindowSpace: String, Sendable, Equatable, Codable {
    /// Rescaled output units — Hounsfield on CT. What a user types, and what
    /// `dicom-print --window-center/--window-width` carries.
    case outputUnits

    /// Stored pixel values, as the viewer and ``DICOMImageExporter`` hold them.
    /// Converted back through the rescale pair before the window is applied.
    case storedValues
}

// MARK: - Print Job Request

/// A complete, validated description of a print job.
///
/// Holds every option the `dicom-print send` command exposes. Construct it,
/// call ``validate()``, then feed it to ``PrintImagePreparer`` (for the pixel
/// side) and ``PrintWorkflow`` (for the DIMSE side).
public struct PrintJobRequest: Sendable, Codable {

    // MARK: Film session

    /// Number of copies of each film.
    public var copies: Int
    /// Print priority (LOW / MED / HIGH).
    public var priority: PrintPriority
    /// Medium the printer should use.
    public var mediumType: MediumType
    /// Where finished film is delivered.
    public var filmDestination: FilmDestination
    /// Optional Film Session Label (2000,0050).
    public var sessionLabel: String?

    // MARK: Film box

    /// Layout selection (auto, explicit grid, or preset).
    public var layoutSelection: PrintLayoutSelection
    /// Film size — overridden by a `.template` layout selection.
    public var filmSize: FilmSize
    /// Film orientation — overridden by a `.template` layout selection.
    public var filmOrientation: FilmOrientation
    /// Interpolation the printer applies when scaling images to cells.
    public var magnificationType: MagnificationType
    /// Border density between cells ("BLACK", "WHITE", or a density value).
    public var borderDensity: String
    /// Density of unfilled cells.
    public var emptyImageDensity: String
    /// Whether the printer draws a trim box around each cell.
    public var trimOption: TrimOption
    /// Printer-specific Configuration Information (2010,0150).
    public var configurationInformation: String?

    // MARK: Image box

    /// How images are scaled to their cells (SRS FR-003).
    ///
    /// Fit and fill travel to a real printer as Decimate/Crop Behavior; true
    /// size additionally sends Requested Image Size per image. Stretch has no
    /// wire form and applies only where this toolkit composes the film itself.
    public var scalingMode: PrintScalingMode

    /// Where an image sits in a cell it does not fill (SRS FR-003).
    ///
    /// Local composition only — a printer receiving the job centres, as
    /// printers do; the preview shows which of the two will happen.
    public var cellAlignment: PrintCellAlignment

    /// Image polarity (NORMAL / REVERSE).
    public var polarity: ImagePolarity
    /// Presentation LUT shape to create and reference, if any.
    public var presentationLUTShape: PresentationLUTShape?
    /// Custom Presentation LUT data, sent instead of a shape (the "Custom"
    /// option) — takes precedence over ``presentationLUTShape``.
    public var presentationLUTTable: PresentationLUTTable?
    /// Film annotations. Only sent when ``annotationDisplayFormatID`` is set.
    public var annotations: [DICOMNetwork.PrintAnnotation]
    /// Printer-configured Annotation Display Format ID (2010,0030).
    public var annotationDisplayFormatID: String?
    /// Annotations for one film each, overriding ``annotations`` on the films
    /// they name — the patient footer of a job whose sheets hold different
    /// studies (see ``FilmIdentificationPlanner``).
    ///
    /// Composed film draws these itself; on the wire they still need
    /// ``annotationDisplayFormatID``, and a caller that has none burns the
    /// caption into the pixels instead.
    public var filmAnnotations: [[DICOMNetwork.PrintAnnotation]]

    // MARK: Pixel preparation

    /// Grayscale or color print management.
    public var colorMode: DICOMNetwork.PrintColorMode

    /// Keep a colour source's colour even when the job is configured grayscale.
    ///
    /// On by default, because losing colour is almost never what was meant.
    /// A colour ultrasound or a fused PET/CT carries its diagnosis *in* the
    /// colour — flow direction, uptake — and flattening it to greys throws that
    /// away silently, while a raw job of the same image keeps it. The mismatch
    /// is resolved on the wire instead: ``PrintWorkflow/execute`` moves the job
    /// onto Basic Colour Print Management when the prepared frames turn out to
    /// carry colour, so the pixels and the SOP class always agree.
    ///
    /// Set `false` for the old behaviour — deliberately rendering colour sources
    /// as greys, which is what a grayscale-only printer or a monochrome film
    /// stock actually wants.
    public var preservesSourceColor: Bool = true
    /// Which frames of multi-frame sources to print.
    public var frameSelection: PrintFrameSelection
    /// Send stored pixel values with no rescale / window / inversion applied.
    public var raw: Bool
    /// Explicit VOI window overriding the data set's own window.
    public var windowSettings: WindowSettings?
    /// The space ``windowSettings`` is stated in (see ``PrintWindowSpace``).
    public var windowSpace: PrintWindowSpace
    /// Grayscale output bit depth: 8 or 12.
    ///
    /// PS3.3 Table C.13-5 enumerates Bits Stored as 8 or 12 for the Basic
    /// Grayscale Image Sequence. 16 is still accepted here — earlier builds offered
    /// it and it survives in saved settings — but it is clamped to 12 before it
    /// reaches the wire, with a diagnostic, rather than producing an image box
    /// no conforming printer may accept.
    public var bitDepth: Int
    /// A pseudo-colour palette to bake into the prepared pixels.
    ///
    /// Set per image by the print sheet, from the cell's own presentation. It
    /// takes a monochrome frame to 8-bit RGB, since Print Management has no way
    /// to carry a palette by reference — PS3.3 Table C.13-5 allows only `RGB` in
    /// a Basic Color Image Sequence. ``bitDepth`` is therefore ignored for a
    /// coloured frame: the standard fixes colour at 8 bits per sample.
    ///
    /// Grey palettes are not set here; they are the absence of colour, and
    /// leaving this `nil` keeps the frame on the grayscale path with its bit
    /// depth and density curve intact.
    public var palette: PseudoColorPalette?

    // MARK: Execution

    /// C-ECHO the printer AE before printing.
    public var verifyFirst: Bool
    /// N-GET printer status before printing; abort on FAILURE, warn on WARNING.
    public var checkStatus: Bool
    /// Retry count for connection/setup failures (0 = no retry).
    public var retries: Int
    /// Report what would be printed without contacting the printer.
    public var dryRun: Bool

    public init(
        copies: Int = 1,
        priority: PrintPriority = .medium,
        mediumType: MediumType = .paper,
        filmDestination: FilmDestination = .processor,
        sessionLabel: String? = nil,
        layoutSelection: PrintLayoutSelection = .automatic,
        filmSize: FilmSize = .size14InX17In,
        filmOrientation: FilmOrientation = .portrait,
        magnificationType: MagnificationType = .replicate,
        borderDensity: String = "BLACK",
        emptyImageDensity: String = "BLACK",
        trimOption: TrimOption = .no,
        configurationInformation: String? = nil,
        scalingMode: PrintScalingMode = .fitToFilm,
        cellAlignment: PrintCellAlignment = .center,
        polarity: ImagePolarity = .normal,
        presentationLUTShape: PresentationLUTShape? = nil,
        presentationLUTTable: PresentationLUTTable? = nil,
        annotations: [DICOMNetwork.PrintAnnotation] = [],
        annotationDisplayFormatID: String? = nil,
        filmAnnotations: [[DICOMNetwork.PrintAnnotation]] = [],
        colorMode: DICOMNetwork.PrintColorMode = .grayscale,
        preservesSourceColor: Bool = true,
        frameSelection: PrintFrameSelection = .first,
        raw: Bool = false,
        windowSettings: WindowSettings? = nil,
        windowSpace: PrintWindowSpace = .outputUnits,
        bitDepth: Int = 8,
        palette: PseudoColorPalette? = nil,
        verifyFirst: Bool = false,
        checkStatus: Bool = false,
        retries: Int = 0,
        dryRun: Bool = false
    ) {
        self.copies = copies
        self.priority = priority
        self.mediumType = mediumType
        self.filmDestination = filmDestination
        self.sessionLabel = sessionLabel
        self.layoutSelection = layoutSelection
        self.filmSize = filmSize
        self.filmOrientation = filmOrientation
        self.magnificationType = magnificationType
        self.borderDensity = borderDensity
        self.emptyImageDensity = emptyImageDensity
        self.trimOption = trimOption
        self.configurationInformation = configurationInformation
        self.scalingMode = scalingMode
        self.cellAlignment = cellAlignment
        self.polarity = polarity
        self.presentationLUTShape = presentationLUTShape
        self.presentationLUTTable = presentationLUTTable
        self.annotations = annotations
        self.annotationDisplayFormatID = annotationDisplayFormatID
        self.filmAnnotations = filmAnnotations
        self.colorMode = colorMode
        self.preservesSourceColor = preservesSourceColor
        self.frameSelection = frameSelection
        self.raw = raw
        self.windowSettings = windowSettings
        self.windowSpace = windowSpace
        self.bitDepth = bitDepth
        self.palette = palette
        self.verifyFirst = verifyFirst
        self.checkStatus = checkStatus
        self.retries = retries
        self.dryRun = dryRun
    }

    // MARK: Derived values

    /// The film size actually used (a template preset overrides the field).
    public var effectiveFilmSize: FilmSize {
        if case .template(let preset) = layoutSelection { return preset.filmSize }
        return filmSize
    }

    /// The orientation actually used (a template preset overrides the field).
    public var effectiveFilmOrientation: FilmOrientation {
        if case .template(let preset) = layoutSelection { return preset.filmOrientation }
        return filmOrientation
    }

    /// The resolved layout, or `nil` when the service should choose one.
    public var resolvedLayout: PrintLayout? { layoutSelection.layout }

    /// The Image Display Format sent, or `nil` when the service should choose one.
    public var resolvedDisplayFormat: PrintImageDisplayFormat? {
        layoutSelection.imageDisplayFormat
    }

    /// The color mode used by `ImagePreprocessor`.
    ///
    /// `DICOMKit.PrintColorMode` and `DICOMNetwork.PrintColorMode` are both
    /// `DICOMCore.PrintColorMode` since D24 was closed, so this is `colorMode` itself;
    /// kept so existing call sites keep compiling.
    public var preprocessColorMode: DICOMKit.PrintColorMode { colorMode }

    /// The `PrintOptions` this request maps to for the Print SCU.
    public var printOptions: PrintOptions {
        PrintOptions(
            numberOfCopies: copies,
            priority: priority,
            filmSize: effectiveFilmSize,
            filmOrientation: effectiveFilmOrientation,
            mediumType: mediumType,
            filmDestination: filmDestination,
            borderDensity: borderDensity,
            emptyImageDensity: emptyImageDensity,
            magnificationType: magnificationType,
            polarity: polarity,
            trimOption: trimOption,
            sessionLabel: sessionLabel,
            presentationLUTShape: presentationLUTShape,
            presentationLUTTable: presentationLUTTable,
            annotations: annotations,
            annotationDisplayFormatID: annotationDisplayFormatID,
            configurationInformation: configurationInformation,
            filmAnnotations: filmAnnotations
        )
    }

    /// The per-image scaling attributes ``scalingMode`` sends on the wire.
    ///
    /// - Fit and stretch send nothing: DECIMATE is the printer default, and
    ///   stretch has no DICOM form.
    /// - Fill sends CROP for every image.
    /// - True size sends CROP plus Requested Image Size (2020,0030) — the
    ///   image's physical width — for every image whose source recorded its
    ///   pixel spacing. An image without spacing **falls back to fit**, and
    ///   ``trueSizeFallbackCount(for:)`` is how a caller finds out and says so:
    ///   a film silently printed at the wrong scale is a film a clinician
    ///   might measure against.
    public func imageBoxOptions(for images: [PreparedPrintImage]) -> [PrintImageBoxOptions] {
        switch scalingMode {
        case .fitToFilm, .stretch:
            return []
        case .fillToFilm:
            return images.map { _ in
                PrintImageBoxOptions(requestedDecimateCropBehavior: .crop)
            }
        case .trueSize:
            return images.map { image in
                guard let millimeters = image.physicalWidthMillimeters else {
                    return PrintImageBoxOptions()
                }
                return PrintImageBoxOptions(
                    requestedImageSize: Self.decimalString(millimeters),
                    requestedDecimateCropBehavior: .crop)
            }
        }
    }

    /// How many of `images` cannot be printed true-size because their source
    /// records no pixel spacing. Zero unless ``scalingMode`` is `.trueSize`.
    public func trueSizeFallbackCount(for images: [PreparedPrintImage]) -> Int {
        guard scalingMode == .trueSize else { return 0 }
        return images.filter { $0.physicalWidthMillimeters == nil }.count
    }

    /// A DS-legal rendering of a millimetre value (≤ 16 characters).
    static func decimalString(_ value: Double) -> String {
        var text = String(format: "%.4f", value)
        if text.count > 16 { text = String(format: "%.6g", value) }
        return text
    }

    /// How many physical films `imageCount` images produce under this request.
    ///
    /// Mirrors the film-box chunking in `DICOMPrintService`: images spill onto
    /// additional films whenever they exceed the layout's cell count. With an
    /// automatic layout the service sizes the grid to the image count, so the
    /// answer is always one film.
    public func filmCount(forImageCount imageCount: Int) -> Int {
        guard imageCount > 0 else { return 0 }
        guard let format = resolvedDisplayFormat else {
            return PrintPlan.automaticFilmCount(forImageCount: imageCount)
        }
        let cells = max(1, format.imageBoxCount)
        return max(1, (imageCount + cells - 1) / cells)
    }

    /// A film-by-film plan for `imageCount` images, for previews and dry runs.
    public func plan(forImageCount imageCount: Int) -> PrintPlan {
        PrintPlan(request: self, imageCount: imageCount)
    }

    // MARK: Validation

    /// Validates the request, throwing the first problem found.
    ///
    /// The messages match the `dicom-print send` validation text exactly.
    public func validate() throws {
        if retries < 0 {
            throw PrintRequestError("--retries must be zero or greater")
        }
        if case .single(let frame) = frameSelection, frame < 1 {
            throw PrintRequestError("--frame is 1-based and must be 1 or greater")
        }
        if let width = windowSettings?.width, width < 1 {
            throw PrintRequestError("--window-width must be 1 or greater")
        }
        // 16 is accepted and clamped rather than refused: it was offered by
        // earlier builds and is stored in saved print settings, so failing on it
        // would break jobs that used to run. `PrintImagePreparer` drops it to
        // the deepest legal value and says so — see `preparationBitDepth`.
        guard [8, 12, 16].contains(bitDepth) else {
            throw PrintRequestError(
                "--bit-depth must be 8 or 12 (PS3.3 Table C.13-5 enumerates Bits "
                + "Stored as 8 or 12 for the Basic Grayscale Image Box)")
        }
        if raw && (windowSettings != nil || bitDepth != 8) {
            throw PrintRequestError(
                "--raw bypasses preprocessing; it cannot be combined with "
                + "--window-center/--window-width or --bit-depth")
        }
        if !annotations.isEmpty && annotationDisplayFormatID == nil {
            throw PrintRequestError(
                "--annotate requires --annotation-format "
                + "(the printer-configured Annotation Display Format ID)")
        }
        if copies < 1 {
            throw PrintRequestError("--copies must be 1 or greater")
        }
    }
}

// MARK: - Print Plan

/// The film-by-film breakdown of a job — what a preview or dry run reports.
public struct PrintPlan: Sendable, Equatable {
    /// Number of images to be placed.
    public let imageCount: Int
    /// Rows × columns actually used (resolved, never `nil`).
    ///
    /// The *bounding* grid of the film. For a `ROW\` or `COL\` layout the cells
    /// are not that grid — ``displayFormat`` is what describes the film, and
    /// ``cells(onSheetOfWidth:height:margin:spacing:)`` is what lays it out.
    public let layout: (rows: Int, columns: Int)
    /// The Image Display Format the film boxes carry.
    public let displayFormat: PrintImageDisplayFormat
    /// Number of physical films.
    public let filmCount: Int
    /// Cells per film.
    public let cellsPerFilm: Int
    /// Copies of each film.
    public let copies: Int
    /// Film size in use.
    public let filmSize: FilmSize
    /// Orientation in use.
    public let filmOrientation: FilmOrientation

    /// Total sheets consumed: films × copies.
    public var totalSheets: Int { filmCount * copies }

    /// The 0-based image indices placed on `filmIndex`, in cell order.
    public func imageIndices(onFilm filmIndex: Int) -> Range<Int> {
        let start = min(filmIndex * cellsPerFilm, imageCount)
        let end = min(start + cellsPerFilm, imageCount)
        return start..<end
    }

    init(request: PrintJobRequest, imageCount: Int) {
        self.imageCount = imageCount
        let format = request.resolvedDisplayFormat
            ?? PrintImageDisplayFormat(layout: PrintPlan.automaticLayout(forImageCount: imageCount))
        self.displayFormat = format
        self.layout = (format.layout.rows, format.layout.columns)
        self.cellsPerFilm = max(1, format.imageBoxCount)
        self.filmCount = imageCount > 0
            ? max(1, (imageCount + self.cellsPerFilm - 1) / self.cellsPerFilm)
            : 0
        self.copies = request.copies
        self.filmSize = request.effectiveFilmSize
        self.filmOrientation = request.effectiveFilmOrientation
    }

    /// The cells this film lays out on a sheet of the given size, in that sheet's
    /// own units, in Image Box Position order.
    ///
    /// The same ``FilmCellLayout`` the SCP composes received film with, so a
    /// preview drawn from these rectangles is drawn by the code that prints.
    public func cells(
        onSheetOfWidth width: Double,
        height: Double,
        margin: Double = 5,
        spacing: Double = 2,
        footer: Double = 0
    ) -> [FilmCell] {
        // A sheet at 25.4 dpi is one unit per millimetre, so the caller's units
        // pass straight through: the layout maths cares only about proportion.
        let sheet = FilmSheet(widthMillimeters: width, heightMillimeters: height, dpi: 25.4)
        return FilmCellLayout.cells(
            for: displayFormat, on: sheet,
            marginMillimeters: margin, spacingMillimeters: spacing,
            footerMillimeters: footer)
    }

    /// The identification footer's depth in the units of a sheet drawn `height`
    /// units tall — the millimetres it takes on real film, to the same scale.
    ///
    /// A preview is a few hundred points tall and the film is a few hundred
    /// millimetres; taking the strip straight in the caller's units would draw
    /// a footer of the wrong proportion, and the preview's whole job is to show
    /// what the sheet will look like.
    public func footerUnits(forLineCount lineCount: Int, sheetHeight height: Double) -> Double {
        guard lineCount > 0, height > 0, sheetHeightMillimeters > 0 else { return 0 }
        return FilmIdentificationFooter.heightMillimeters(
            lineCount: lineCount, sheetHeightMillimeters: sheetHeightMillimeters)
            * (height / sheetHeightMillimeters)
    }

    /// The height of the sheet this job prints on, in millimetres.
    ///
    /// What the footer's type is scaled against: a caption is read at the
    /// distance its film is read from, and that goes with the sheet.
    public var sheetHeightMillimeters: Double {
        FilmSheet(filmSize: filmSize, orientation: filmOrientation, dpi: 25.4)
            .heightMillimeters
    }

    public static func == (lhs: PrintPlan, rhs: PrintPlan) -> Bool {
        lhs.imageCount == rhs.imageCount
            && lhs.displayFormat == rhs.displayFormat
            && lhs.layout == rhs.layout
            && lhs.filmCount == rhs.filmCount
            && lhs.cellsPerFilm == rhs.cellsPerFilm
            && lhs.copies == rhs.copies
            && lhs.filmSize == rhs.filmSize
            && lhs.filmOrientation == rhs.filmOrientation
    }

    /// The grid `DICOMPrintService` picks when no layout is given.
    ///
    /// A single image is always 1×1; otherwise it is `PrintLayout.optimalLayout`.
    public static func automaticLayout(forImageCount imageCount: Int) -> PrintLayout {
        guard imageCount > 1 else { return PrintLayout(rows: 1, columns: 1) }
        return PrintLayout.optimalLayout(for: imageCount)
    }

    /// Film count under an automatic layout (25 cells is the largest auto grid).
    public static func automaticFilmCount(forImageCount imageCount: Int) -> Int {
        guard imageCount > 0 else { return 0 }
        let layout = automaticLayout(forImageCount: imageCount)
        let cells = max(1, layout.rows * layout.columns)
        return max(1, (imageCount + cells - 1) / cells)
    }
}
