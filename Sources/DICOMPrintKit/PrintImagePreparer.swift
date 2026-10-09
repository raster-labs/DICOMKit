// NEMA-verified: 2026a, checked 2026-09-29 — --raw frames checked against PS3.3 2026a Table C.13-5 grayscale/colour pixel enumerations (Photometric, Bits Allocated/Stored, Pixel Representation, High Bit); depth clamp cites Table C.13-5; C.11.2 VOI choice documented as implementation choice (C.11.2 sets no precedence or default pair)
// PrintImagePreparer.swift
// DICOMPrintKit
//
// Turns DICOM sources into the uncompressed, presentation-ready frames a Basic
// Grayscale/Color Image Box requires. Shared by the dicom-print CLI and
// DICOMStudio so both produce byte-identical film pixels from the same inputs.

import Foundation
import DICOMCore
import DICOMKit
import DICOMNetwork

// MARK: - Prepared Image

/// One frame ready to be sent as an image box: pixel bytes plus the mandatory
/// image-box pixel attributes (PS3.3 Table C.13-5).
public struct PreparedPrintImage: Sendable {
    /// The pixel bytes to send.
    public var pixelData: Data { descriptor.pixelData }

    /// Rows/Columns/BitsAllocated/PhotometricInterpretation for the image box.
    public let descriptor: PrintImageData

    /// The source file path, when the frame came from a file on disk.
    public let sourcePath: String?

    /// 0-based frame index within the source.
    public let frameIndex: Int

    /// The physical height of one pixel row in millimetres, when the source
    /// records it (see ``PrintPhysicalSize/pixelSpacing(from:)``).
    public let rowSpacingMillimeters: Double?

    /// The physical width of one pixel column in millimetres, when the source
    /// records it. What true-size printing (FR-003) multiplies by
    /// ``PrintImageData/columns`` — so a crop that narrows the frame narrows
    /// the requested size with it, for free.
    public let columnSpacingMillimeters: Double?

    public init(descriptor: PrintImageData, sourcePath: String?, frameIndex: Int,
                rowSpacingMillimeters: Double? = nil,
                columnSpacingMillimeters: Double? = nil) {
        self.descriptor = descriptor
        self.sourcePath = sourcePath
        self.frameIndex = frameIndex
        self.rowSpacingMillimeters = rowSpacingMillimeters
        self.columnSpacingMillimeters = columnSpacingMillimeters
    }

    /// The width this frame prints at 1:1, in millimetres — `nil` when the
    /// source recorded no spacing, in which case true size is undefined.
    public var physicalWidthMillimeters: Double? {
        guard let spacing = columnSpacingMillimeters, spacing > 0,
              descriptor.columns > 0 else { return nil }
        return Double(descriptor.columns) * spacing
    }

    /// One-line summary, e.g. "512x512 MONOCHROME2 8-bit".
    public var summary: String {
        "\(descriptor.columns)x\(descriptor.rows) "
            + "\(descriptor.photometricInterpretation) \(descriptor.bitsStored)-bit"
    }
}

// MARK: - Preparer

/// Decodes and preprocesses DICOM sources into printable frames.
///
/// - Encapsulated sources (JPEG/J2K/JPEG-LS/RLE) are decoded to native frames
///   via `DICOMFile.tryPixelData()` — Print Management carries native pixels
///   in the image box (PS3.3 Table C.13-5, Pixel Data of the Basic Grayscale /
///   Color Image Sequence).
/// - The request's frame selection picks frames from multi-frame files; each
///   selected frame becomes one image box.
/// - Unless the request is `raw`, each frame runs through `ImagePreprocessor`
///   (rescale → VOI window → MONOCHROME1 inversion → 8-bit MONOCHROME2, or
///   8-bit RGB/grayscale for color sources) so the print matches clinical
///   presentation instead of raw stored values.
/// - The window is resolved the way the rest of the app resolves one: the
///   request's own window, else the data set's VOI, else the preprocessor's
///   auto-stretch (see ``resolvedWindow(_:dataSet:)``).
public struct PrintImagePreparer: Sendable {

    /// A progress/diagnostic line emitted while preparing (verbose output).
    public typealias ProgressHandler = @Sendable (String) -> Void

    private let preprocessor: ImagePreprocessor

    public init(preprocessor: ImagePreprocessor = ImagePreprocessor()) {
        self.preprocessor = preprocessor
    }

    /// Prepares every selected frame of every given file, in file order.
    ///
    /// - Parameters:
    ///   - paths: DICOM file paths, already gathered and ordered.
    ///   - request: The job whose frame selection and rendering options apply.
    ///   - onProgress: Optional per-frame diagnostic line.
    /// - Throws: ``PrintRequestError`` with the CLI's message text on unreadable
    ///   files, undecodable pixels, out-of-range frames, or oversized images.
    public func prepare(
        paths: [String],
        request: PrintJobRequest,
        onProgress: ProgressHandler? = nil
    ) async throws -> [PreparedPrintImage] {
        var prepared: [PreparedPrintImage] = []

        for path in paths {
            guard let data = FileManager.default.contents(atPath: path) else {
                throw PrintRequestError("Cannot read file: \(path)")
            }

            let file = try DICOMFile.read(from: data, force: true)
            let pixelData: PixelData
            do {
                pixelData = try file.tryPixelData()
            } catch {
                throw PrintRequestError(
                    "Cannot extract printable pixel data from \(path): \(error)")
            }

            let frames = try await prepare(
                pixelData: pixelData,
                dataSet: file.dataSet,
                request: request,
                sourcePath: path,
                onProgress: onProgress
            )
            prepared.append(contentsOf: frames)
        }

        return prepared
    }

    /// Prepares the selected frames of one already-open data set.
    ///
    /// The in-app path: the viewer already holds a decoded `PixelData`, so this
    /// avoids re-reading and re-decoding the file.
    public func prepare(
        pixelData: PixelData,
        dataSet: DataSet,
        request: PrintJobRequest,
        sourcePath: String? = nil,
        onProgress: ProgressHandler? = nil
    ) async throws -> [PreparedPrintImage] {
        let sourceDescriptor = pixelData.descriptor
        let label = sourcePath ?? "data set"

        // Once per data set rather than once per frame: a 300-frame series
        // would otherwise repeat the same sentence 300 times and bury the rest
        // of the log.
        if let note = Self.clampNote(request) { onProgress?(note) }

        let frameIndices: [Int]
        switch request.frameSelection {
        case .all:
            frameIndices = Array(0..<sourceDescriptor.numberOfFrames)
        case .single(let frameNumber):
            guard frameNumber <= sourceDescriptor.numberOfFrames else {
                throw PrintRequestError(
                    "--frame \(frameNumber) is out of range "
                    + "(file has \(sourceDescriptor.numberOfFrames) frame(s)): \(label)")
            }
            frameIndices = [frameNumber - 1]
        }

        // Read once per source: every frame of a file shares its spacing.
        let pixelSpacing = PrintPhysicalSize.pixelSpacing(from: dataSet)

        var prepared: [PreparedPrintImage] = []
        for frameIndex in frameIndices {
            let descriptor: PrintImageData
            if request.raw {
                // Raw sends the stored values as they are, so a pixel module
                // the image box cannot carry cannot be corrected here either —
                // it is refused, with the rule, rather than sent non-conformant.
                if let problem = Self.rawConformanceProblem(sourceDescriptor) {
                    throw PrintRequestError(
                        "--raw cannot print \(label): \(problem) Print without --raw "
                        + "to have the frame converted.")
                }
                guard let frameBytes = pixelData.frameData(at: frameIndex) else {
                    throw PrintRequestError(
                        "Frame \(frameIndex + 1) of \(label) is truncated or missing")
                }
                guard sourceDescriptor.rows <= Int(UInt16.max),
                      sourceDescriptor.columns <= Int(UInt16.max) else {
                    throw PrintRequestError("Image dimensions out of range in: \(label)")
                }
                descriptor = PrintImageData(
                    pixelData: frameBytes,
                    rows: UInt16(sourceDescriptor.rows),
                    columns: UInt16(sourceDescriptor.columns),
                    bitsAllocated: UInt16(sourceDescriptor.bitsAllocated),
                    bitsStored: UInt16(sourceDescriptor.bitsStored),
                    highBit: UInt16(sourceDescriptor.highBit),
                    samplesPerPixel: UInt16(sourceDescriptor.samplesPerPixel),
                    pixelRepresentation: sourceDescriptor.isSigned ? 1 : 0,
                    photometricInterpretation: sourceDescriptor.photometricInterpretation.rawValue
                )
            } else {
                let voi = Self.resolvedVOI(request, dataSet: dataSet)
                // A colour source keeps its colour unless the job says otherwise.
                //
                // Handing the preprocessor GRAYSCALE is what makes it flatten
                // RGB to luminance, and that is a decision about the *source*,
                // not about the printer: a raw job of the same ultrasound comes
                // out in colour, so a processed one coming out grey is a
                // surprise nobody asked for. The printer's own limits are
                // applied later, on the wire, where the prepared pixels are
                // known — see `PrintWorkflow.reconcilingColorMode`.
                let colorMode = Self.preparationColorMode(
                    request, sourceDescriptor: sourceDescriptor)
                // A coloured frame is fixed at 8 bits per sample by the
                // standard, so asking for 12- or 16-bit greys alongside a
                // palette is a contradiction; the palette wins and the depth is
                // dropped rather than silently producing a frame the colour
                // image box cannot describe.
                let image = try await preprocessor.prepareForPrint(
                    pixelData: pixelData,
                    dataSet: dataSet,
                    frameIndex: frameIndex,
                    colorMode: colorMode,
                    windowSettings: voi.window,
                    outputBitDepth: Self.preparationBitDepth(
                        request, sourceDescriptor: sourceDescriptor),
                    voiLUT: voi.lut,
                    palette: Self.preparationPalette(
                        request, sourceDescriptor: sourceDescriptor)
                )
                guard image.width <= Int(UInt16.max),
                      image.height <= Int(UInt16.max) else {
                    throw PrintRequestError("Image dimensions out of range in: \(label)")
                }
                let stored = UInt16(image.bitsStored)
                // Whatever the modality drew *over* the image goes on the film
                // too. Some Secondary Captures — a Siemens Patient Protocol —
                // have all-zero Pixel Data and put their whole content in a
                // 1-bit overlay plane, and the preview shows it; a film printed
                // without it is a black sheet that disagrees with the screen it
                // was approved on. Not for `--raw`, which sends stored pixels
                // untouched by definition.
                var samples = OverlayPlaneRenderer.burningOverlays(
                    of: dataSet,
                    into: image.pixelData,
                    width: image.width,
                    height: image.height,
                    bitsAllocated: image.bitsAllocated,
                    bitsStored: image.bitsStored,
                    samplesPerPixel: image.samplesPerPixel,
                    photometricInterpretation: image.photometricInterpretation,
                    frameIndex: frameIndex)

                // The Presentation LUT, for the one option the printer cannot
                // apply for us. IDENTITY and LIN OD go on the wire as a shape
                // and are the printer's job — applying them here too would
                // double them. A rendered inverse has no legal shape to send
                // (PS3.3 C.11.4), so the inversion has to happen in the pixels.
                if request.presentationLUTShape?.invertsPixels == true,
                   let curve = PresentationLUTTransform.curve(
                       for: request.presentationLUTShape) {
                    samples = PresentationLUTTransform.apply(
                        curve: curve,
                        to: samples,
                        samplesPerPixel: image.samplesPerPixel,
                        bitsStored: image.bitsStored)
                }
                descriptor = PrintImageData(
                    pixelData: samples,
                    rows: UInt16(image.height),
                    columns: UInt16(image.width),
                    bitsAllocated: UInt16(image.bitsAllocated),
                    bitsStored: stored,
                    highBit: stored > 0 ? stored - 1 : 0,
                    samplesPerPixel: UInt16(image.samplesPerPixel),
                    pixelRepresentation: 0,
                    photometricInterpretation: image.photometricInterpretation
                )
                onProgress?(
                    "Prepared \(label) frame \(frameIndex + 1): "
                    + "\(image.width)x\(image.height) "
                    + "\(image.photometricInterpretation) \(image.bitsStored)-bit")
            }

            prepared.append(PreparedPrintImage(
                descriptor: descriptor,
                sourcePath: sourcePath,
                frameIndex: frameIndex,
                rowSpacingMillimeters: pixelSpacing?.row,
                columnSpacingMillimeters: pixelSpacing?.column
            ))
        }

        return prepared
    }

    // MARK: - Raw frames

    /// The Basic Grayscale Image Sequence's pixel enumerations, PS3.3 Table
    /// C.13-5. A raw frame is sent with the source's own pixel module, so it
    /// has to meet them as it stands.
    static let rawGrayscalePhotometric = ["MONOCHROME1", "MONOCHROME2"]
    static let rawGrayscaleBitsAllocated = [8, 16]
    static let rawGrayscaleBitsStored = [8, 12]
    static let rawPixelRepresentation = [0]

    /// The Basic Color Image Sequence's, same table: RGB, 8 bits allocated and
    /// stored (Planar Configuration 1 is the SCU's to write — it re-lays the
    /// samples out color-by-plane on the wire).
    static let rawColorPhotometric = ["RGB"]
    static let rawColorBitsAllocated = [8]
    static let rawColorBitsStored = [8]

    /// Why a source's stored pixels cannot go into an image box untouched, or
    /// `nil` when they can.
    ///
    /// These are Enumerated Values, so a value outside them is non-conformant
    /// (PS3.5 6.3), and High Bit "shall be one less than Bits
    /// Stored" in both sequences. A signed CT (Pixel Representation 1), a
    /// 16-bit-stored image, a YBR or PALETTE COLOR source all fail here; the
    /// ordinary path converts every one of them.
    static func rawConformanceProblem(_ source: PixelDataDescriptor) -> String? {
        let photometric = source.photometricInterpretation.rawValue
        let representation = source.isSigned ? 1 : 0
        func fail(_ what: String, _ value: CustomStringConvertible, _ allowed: [CustomStringConvertible]) -> String {
            "PS3.3 Table C.13-5 allows \(what) \(allowed.map(\.description).joined(separator: " or ")) "
                + "in an image box, and the frame has \(value)."
        }
        switch source.samplesPerPixel {
        case 1:
            guard rawGrayscalePhotometric.contains(photometric) else {
                return fail("Photometric Interpretation", photometric, rawGrayscalePhotometric)
            }
            guard rawGrayscaleBitsAllocated.contains(source.bitsAllocated) else {
                return fail("Bits Allocated", source.bitsAllocated, rawGrayscaleBitsAllocated)
            }
            guard rawGrayscaleBitsStored.contains(source.bitsStored) else {
                return fail("Bits Stored", source.bitsStored, rawGrayscaleBitsStored)
            }
        case 3:
            guard rawColorPhotometric.contains(photometric) else {
                return fail("Photometric Interpretation", photometric, rawColorPhotometric)
            }
            guard rawColorBitsAllocated.contains(source.bitsAllocated) else {
                return fail("Bits Allocated", source.bitsAllocated, rawColorBitsAllocated)
            }
            guard rawColorBitsStored.contains(source.bitsStored) else {
                return fail("Bits Stored", source.bitsStored, rawColorBitsStored)
            }
        default:
            return fail("Samples per Pixel", source.samplesPerPixel, [1, 3])
        }
        guard rawPixelRepresentation.contains(representation) else {
            return fail("Pixel Representation", representation, rawPixelRepresentation)
        }
        guard source.highBit == source.bitsStored - 1 else {
            return "PS3.3 Table C.13-5 requires High Bit one less than Bits Stored, and the "
                + "frame has High Bit \(source.highBit) with Bits Stored \(source.bitsStored)."
        }
        return nil
    }

    // MARK: - Colour preparation

    /// The colour mode the *preprocessor* is driven with for one source.
    ///
    /// Colour is preserved when the source has it and the request allows it;
    /// everything else keeps the request's own mode. Note this only ever widens
    /// the result — a monochrome source stays monochrome whatever is asked for,
    /// since there is no colour in it to keep.
    ///
    /// A pseudo-colour palette is the one thing that *does* put colour into a
    /// monochrome source, so it widens too. Without this a palettised cell would
    /// be prepared as grey and the chosen colours would never reach the film.
    static func preparationColorMode(
        _ request: PrintJobRequest,
        sourceDescriptor: PixelDataDescriptor
    ) -> DICOMKit.PrintColorMode {
        // "Print colour images as greys" is the reader's explicit word on
        // colour *sources*, and it outranks everything else that could put
        // colour on this cell — the job's own colour mode and a lingering
        // palette included. Before this check came first, a film-wide palette
        // quietly forced the cell back to colour and the switch looked dead.
        if Self.isColorSource(sourceDescriptor), !request.preservesSourceColor {
            return .grayscale
        }
        if Self.preparationPalette(request, sourceDescriptor: sourceDescriptor) != nil {
            return .color
        }
        return Self.isColorSource(sourceDescriptor) ? .color : request.preprocessColorMode
    }

    /// Whether a source's own pixels carry colour.
    static func isColorSource(_ descriptor: PixelDataDescriptor) -> Bool {
        let photometric = descriptor.photometricInterpretation
        return descriptor.samplesPerPixel > 1
            || photometric.isColor
            || photometric.isPaletteColor
    }

    /// The palette actually applied to a job, or `nil` for a grey film.
    ///
    /// Grey palettes are dropped here rather than carried down: the preprocessor
    /// would fall through to the grayscale path anyway, and dropping them early
    /// keeps ``preparationColorMode`` and ``preparationBitDepth`` from treating
    /// "the reader chose grey" as a reason to spend the film's bit depth.
    ///
    /// Raw jobs never colourise. Raw means the stored values reach the printer
    /// untouched, and a palette is by definition a transformation of them.
    ///
    /// When the source is known, "print colour images as greys" also drops the
    /// palette for colour sources: the reader asked for the picture's own greys,
    /// not for a palette-shaped remap of them. Monochrome sources keep theirs —
    /// colourising a grey CT is a deliberate act the toggle does not speak to.
    static func preparationPalette(
        _ request: PrintJobRequest,
        sourceDescriptor: PixelDataDescriptor? = nil
    ) -> PseudoColorPalette? {
        guard !request.raw, let palette = request.palette, !palette.isGrayscale else {
            return nil
        }
        if let sourceDescriptor, Self.isColorSource(sourceDescriptor),
           !request.preservesSourceColor {
            return nil
        }
        return palette
    }

    /// The bit depth a frame is prepared at.
    ///
    /// Two rules, both from the standard rather than from preference:
    ///
    ///   * Eight, whenever a palette is in force: PS3.3 Table C.13-5 fixes Bits
    ///     Allocated and Bits Stored at 8 for the Basic Color Image Box, so a
    ///     coloured frame has no deeper form to take.
    ///   * Otherwise the requested depth, clamped to what PS3.3 Table C.13-5
    ///     enumerates for the Basic Grayscale Image Box — 8 or 12. A request for
    ///     16 is dropped to 12 rather than refused: every pixel of it is
    ///     meaningful and only the label is illegal, so the film is worth
    ///     printing. The caller is told through ``clampNote`` so the setting
    ///     gets corrected rather than silently tolerated forever.
    static func preparationBitDepth(
        _ request: PrintJobRequest,
        sourceDescriptor: PixelDataDescriptor? = nil
    ) -> Int {
        guard Self.preparationPalette(request, sourceDescriptor: sourceDescriptor) == nil
        else { return 8 }
        return Self.clampedGrayscaleBitDepth(request.bitDepth)
    }

    /// The deepest legal grayscale depth not exceeding `requested`.
    ///
    /// Never rounds *up*: a sender asking for 8 gets 8, because manufacturing
    /// precision nobody asked for is its own kind of wrong.
    static func clampedGrayscaleBitDepth(_ requested: Int) -> Int {
        let legal = PrintOptionCatalog.bitDepths.sorted()
        return legal.last(where: { $0 <= requested }) ?? legal.first ?? 8
    }

    /// What to tell the operator when the requested depth could not be honoured.
    ///
    /// `nil` when the request was already legal, which is the ordinary case.
    static func clampNote(_ request: PrintJobRequest) -> String? {
        guard !request.raw else { return nil }

        if Self.preparationPalette(request) != nil, request.bitDepth != 8 {
            return "Requested \(request.bitDepth)-bit, but a pseudo-colour palette is in "
                + "force and PS3.3 Table C.13-5 fixes the Basic Color Image Box at 8-bit "
                + "RGB — preparing at 8-bit."
        }

        let effective = Self.clampedGrayscaleBitDepth(request.bitDepth)
        guard effective != request.bitDepth else { return nil }
        return "Requested \(request.bitDepth)-bit, which PS3.3 Table C.13-5 does not allow "
            + "for the Basic Grayscale Image Box (Bits Stored must be 8 or 12) — "
            + "preparing at \(effective)-bit instead."
    }

    // MARK: - Window resolution

    /// The window a frame is printed with, in the units ``ImagePreprocessor``
    /// windows in (output units — HU on CT).
    ///
    /// Three rungs, in the order the rest of the app resolves a window
    /// (`DICOMImageExporter.determineWindowSettings`): the request's own window,
    /// then the data set's VOI, then nothing — which leaves the preprocessor to
    /// stretch the frame's full pixel range.
    ///
    /// The middle rung is why this exists. A mark made without opening the file
    /// — marking a whole series, or printing straight from the library — carries
    /// no window, and auto-stretching a CT from air to bone leaves soft tissue
    /// in a handful of indistinguishable greys. The viewer, the tiles and export
    /// all fall back to the VOI the scanner recorded; film that does not is film
    /// that disagrees with the screen it was approved on.
    ///
    /// A multi-valued VOI (`-600\50` / `1200\350`, a lung and a soft-tissue
    /// window in one element) resolves to its first pair. PS3.3 C.11.2 only
    /// says the values "shall be considered as pairs" and that one may be
    /// applied; it names no default, so the first — what viewers conventionally
    /// open with — is this toolkit's choice.
    static func resolvedWindow(
        _ request: PrintJobRequest,
        dataSet: DataSet
    ) -> WindowSettings? {
        if request.windowSettings != nil {
            return windowInOutputUnits(request, dataSet: dataSet)
        }
        // Header VOI values are already in output units — that is the space the
        // attribute is defined in — so this rung needs no conversion.
        return dataSet.allWindowSettings().first ?? dataSet.windowSettings()
    }

    /// The full VOI resolution, table LUTs included (SRS FR-004).
    ///
    /// PS3.3 C.11.2 lets either a Window Center/Width pair "or the VOI LUT, but
    /// not both at the same time" be applied, and sets no precedence between
    /// them. The order below is this toolkit's, highest first:
    ///
    /// 1. The request's explicit window — the user (or the viewer the film
    ///    must match) asked for it, so it beats everything, the file's own
    ///    table included.
    /// 2. The file's VOI LUT Sequence (0028,3010): a file carrying both is
    ///    printed through the table, the more specific of the two.
    /// 3. Window Center/Width from the header.
    /// 4. Nothing — the preprocessor auto-stretches.
    static func resolvedVOI(
        _ request: PrintJobRequest,
        dataSet: DataSet
    ) -> (window: WindowSettings?, lut: GrayscaleLUT?) {
        if request.windowSettings != nil {
            return (windowInOutputUnits(request, dataSet: dataSet), nil)
        }
        if let lut = dataSet.voiLUT() {
            return (nil, lut)
        }
        return (dataSet.allWindowSettings().first ?? dataSet.windowSettings(), nil)
    }

    /// The request's window in the units ``ImagePreprocessor`` windows in.
    ///
    /// The preprocessor rescales before it windows, so it expects output units.
    /// A window taken off the viewer is in stored values — the space the
    /// renderer works in — and has to be put back through the rescale pair, or
    /// the window sits nowhere near the pixels and the frame prints as a flat
    /// black (or white) cell. See ``PrintWindowSpace``.
    static func windowInOutputUnits(
        _ request: PrintJobRequest,
        dataSet: DataSet
    ) -> WindowSettings? {
        guard let window = request.windowSettings else { return nil }
        let function = resolvedFunction(for: window, dataSet: dataSet)
        guard request.windowSpace == .storedValues else {
            return WindowSettings(
                center: window.center, width: window.width,
                explanation: window.explanation, function: function)
        }

        let slope = dataSet.rescaleSlope()
        guard slope != 0 else { return window }
        let intercept = dataSet.rescaleIntercept()
        return WindowSettings(
            center: window.center * slope + intercept,
            width: window.width * abs(slope),
            explanation: window.explanation,
            function: function)
    }

    /// The VOI LUT Function the window is applied with.
    ///
    /// PS3.3 C.11.2.1.3: the function belongs to the *image* — (0028,1056)
    /// says how any Window Center/Width is to be interpreted for it. A window
    /// carried off a viewer mark arrives as two bare numbers whose `function`
    /// defaulted to linear, so a SIGMOID image would print with linear
    /// contrast, silently, while the screen showed sigmoid. `.linear` is the
    /// "nothing was said" default, so it defers to the file; an explicit
    /// LINEAR_EXACT or SIGMOID on the request is a real choice and stands.
    static func resolvedFunction(
        for window: WindowSettings,
        dataSet: DataSet
    ) -> VOILUTFunction {
        guard window.function == .linear else { return window.function }
        return VOILUTFunction.parse(dataSet.string(for: .voiLUTFunction))
    }
}

// MARK: - Convenience

public extension Array where Element == PreparedPrintImage {
    /// The pixel payloads, in order, for `DICOMPrintService.printImages`.
    var pixelPayloads: [Data] { map(\.pixelData) }

    /// The image-box descriptors, in order.
    var imageDescriptors: [PrintImageData] { map(\.descriptor) }
}
