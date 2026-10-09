// NEMA-verified: 2026a, checked 2026-09-29 — Film Box / Image Box / Presentation LUT citations corrected to PS3.3 2026a C.13.3, C.13.5, C.11.4; YBR 4:2:2 layout and partial-range inverse per C.7.6.3.1.2; Border/Empty Density terms per Table C.13-3; Trim = YES prints a trim box around each image per Table C.13-3 (D92); P-Value rendering through the PS3.14 7.2/7.3 GSDF under DensityMapping.gsdf (P-GSDF), linear under paper/film
//
// FilmComposer.swift
// DICOMPrintKit
//
// Milestone C of the Print SCP plan: turn a `ReceivedFilm` — film box
// attributes plus its ordered image boxes — into one rasterized sheet.
//
// This is the only genuinely new piece of the emulator: everything upstream is
// protocol handling and everything downstream is a sink.
//
// Reference: PS3.3 C.13.3 (Basic Film Box Presentation), C.13.5 (Image Box Pixel
// Presentation), C.11.4 (Presentation LUT — the hardcopy module; C.11.6 is the
// softcopy one).
//

import Foundation
import DICOMCore
import DICOMNetwork

#if canImport(CoreGraphics)
import CoreGraphics
import CoreText
#endif

// MARK: - Configuration

/// Tunables for ``FilmComposer``.
public struct FilmComposerConfiguration: Sendable, Hashable {
    /// Rasterization resolution. 300 is print quality; 150 is a fast draft.
    public let dpi: Double

    /// How optical density is interpreted (see ``DensityMapping``).
    public let densityMapping: DensityMapping

    /// Sheet margin in millimetres on all four edges.
    public let marginMillimeters: Double

    /// Gap between adjacent image cells, in millimetres.
    public let cellSpacingMillimeters: Double

    /// Whether to draw Basic Annotation Box text on the sheet.
    public let drawAnnotations: Bool

    /// Which edge the film-wide annotation band occupies (SRS FR-006:
    /// header, footer, side or overlay). Footer is the default and what
    /// every film before this option existed was composed with.
    public let annotationEdge: FilmAnnotationEdge

    /// Whether to print the trim box when Trim (2010,0140) is YES: per PS3.3
    /// Table C.13-3, "a trim box shall be printed surrounding each image on the
    /// film". (The name predates that reading and is kept for source compatibility.)
    public let drawTrimMarks: Bool

    /// Safety cap on the composed bitmap's longest side, in pixels.
    ///
    /// A 14×17 in sheet at 300 DPI is ~4200×5100; a hostile or mistaken
    /// Film Size / DPI combination must not be able to allocate unboundedly.
    public let maximumPixelDimension: Int

    /// Where an image sits in a cell it does not fill (SRS FR-003).
    ///
    /// Centred by default — what a real printer does. Alignment and
    /// ``stretchToFill`` are local composition preferences with no DICOM
    /// attribute behind them: a film received over the wire is composed with
    /// the defaults, so the emulator keeps printing what the SCU asked for.
    public let cellAlignment: PrintCellAlignment

    /// Fill each cell exactly, aspect ratio ignored (SRS FR-003 "stretch").
    /// Not for diagnostic use; local composition only.
    public let stretchToFill: Bool

    /// A pseudo-colour palette laid over received image boxes when the sheet is
    /// composed. Local rendering only, and `nil` — no recolouring — by default.
    ///
    /// This is a *viewing* control, in the same family as ``cellAlignment`` and
    /// ``stretchToFill``: a local composition preference with no DICOM attribute
    /// behind it. It has to be, because Print Management gives it nowhere to
    /// live — "palette" does not appear in PS3.4 Annex H, and PS3.3 Table C.13-5
    /// lets a Basic Color Image Box carry only `RGB`. An SCU therefore cannot
    /// ask for one and cannot be told one was used.
    ///
    /// That is exactly why it must not touch the wire. The P-Values in an image
    /// box are what the sending operator approved; recolouring them on the way
    /// through would make the film disagree with the screen the study was signed
    /// off on, and the SCU would never know. So this reaches the composed bitmap
    /// and nothing else: ``FilmComposer`` applies it when rasterising, the
    /// received ``PrintImageData`` keeps its original samples, and anything
    /// re-sent or re-encoded from them is unaffected.
    public let previewPalette: PseudoColorPalette?

    public init(
        dpi: Double = PrintSCPSettings.defaultDPI,
        densityMapping: DensityMapping = .paperDirect,
        marginMillimeters: Double = 5,
        cellSpacingMillimeters: Double = 2,
        drawAnnotations: Bool = true,
        annotationEdge: FilmAnnotationEdge = .bottom,
        drawTrimMarks: Bool = true,
        maximumPixelDimension: Int = 12000,
        cellAlignment: PrintCellAlignment = .center,
        stretchToFill: Bool = false,
        previewPalette: PseudoColorPalette? = nil
    ) {
        // Clamped to the one range the whole app agrees on, so the settings UI
        // and the composer cannot drift apart on what a printable DPI is.
        self.dpi = min(max(dpi, PrintSCPSettings.dpiRange.lowerBound),
                       PrintSCPSettings.dpiRange.upperBound)
        self.densityMapping = densityMapping
        self.marginMillimeters = max(0, marginMillimeters)
        self.cellSpacingMillimeters = max(0, cellSpacingMillimeters)
        self.drawAnnotations = drawAnnotations
        self.annotationEdge = annotationEdge
        self.drawTrimMarks = drawTrimMarks
        self.maximumPixelDimension = max(256, maximumPixelDimension)
        self.cellAlignment = cellAlignment
        self.stretchToFill = stretchToFill
        // Grey is not a recolouring, and carrying it would push mono boxes down
        // the RGB path for nothing. Dropped here so every reader downstream can
        // treat non-nil as "there are colours to apply".
        self.previewPalette = previewPalette.flatMap { $0.isGrayscale ? nil : $0 }
    }

    /// This configuration with a different cell placement — how the simulator
    /// and save-film apply a job's scaling mode over the emulator's settings.
    public func withPlacement(
        alignment: PrintCellAlignment, stretch: Bool
    ) -> FilmComposerConfiguration {
        FilmComposerConfiguration(
            dpi: dpi,
            densityMapping: densityMapping,
            marginMillimeters: marginMillimeters,
            cellSpacingMillimeters: cellSpacingMillimeters,
            drawAnnotations: drawAnnotations,
            annotationEdge: annotationEdge,
            drawTrimMarks: drawTrimMarks,
            maximumPixelDimension: maximumPixelDimension,
            cellAlignment: alignment,
            stretchToFill: stretch,
            previewPalette: previewPalette)
    }

    /// Print-quality defaults (600 DPI, paper-direct density).
    public static let `default` = FilmComposerConfiguration()

    /// A fast, low-resolution configuration for previews.
    public static let draft = FilmComposerConfiguration(dpi: 150)
}

// MARK: - Errors

/// Failures raised while composing a film.
public enum FilmCompositionError: Error, Sendable, Equatable, CustomStringConvertible {
    /// CoreGraphics is unavailable or the bitmap context could not be created.
    case rasterizerUnavailable
    /// The sheet would exceed ``FilmComposerConfiguration/maximumPixelDimension``.
    case sheetTooLarge(width: Int, height: Int, limit: Int)
    /// An image box carried a photometric interpretation we cannot render.
    case unsupportedPhotometricInterpretation(String)

    public var description: String {
        switch self {
        case .rasterizerUnavailable:
            return "No rasterizer available on this platform"
        case .sheetTooLarge(let width, let height, let limit):
            return "Composed sheet \(width)×\(height) px exceeds the \(limit) px limit"
        case .unsupportedPhotometricInterpretation(let value):
            return "Unsupported Photometric Interpretation: \(value)"
        }
    }
}

// MARK: - Composer

/// Composes a received film into a printable sheet.
///
/// Pure and synchronous: no network, no file system, no global state, so the
/// composition can be golden-tested by hashing the resulting bitmap.
public struct FilmComposer: Sendable {

    public let configuration: FilmComposerConfiguration

    public init(configuration: FilmComposerConfiguration = .default) {
        self.configuration = configuration
    }

    /// Composes one film.
    public func compose(_ film: ReceivedFilm) throws -> ComposedFilm {
        #if canImport(CoreGraphics)
        return try rasterize(film)
        #else
        throw FilmCompositionError.rasterizerUnavailable
        #endif
    }

    // MARK: Sheet setup

    /// The sheet geometry a film will be composed on.
    public func sheet(for film: ReceivedFilm) -> FilmSheet {
        FilmSheet(
            filmSize: film.filmBox.filmSizeID,
            orientation: film.filmBox.filmOrientation,
            dpi: configuration.dpi)
    }

    /// The cell rectangles a film's layout produces.
    public func cells(for film: ReceivedFilm) -> [FilmCell] {
        FilmCellLayout.cells(
            for: PrintImageDisplayFormat.parse(film.filmBox.imageDisplayFormat),
            on: sheet(for: film),
            marginMillimeters: configuration.marginMillimeters,
            spacingMillimeters: configuration.cellSpacingMillimeters,
            footerMillimeters: footerMillimeters(for: film),
            annotationEdge: configuration.annotationEdge)
    }

    /// The strip this film's annotations need along the bottom of the sheet.
    ///
    /// Zero when annotations are switched off or there are none — a film with
    /// nothing to say at its foot gives the whole sheet to the pictures.
    func footerMillimeters(for film: ReceivedFilm) -> Double {
        guard configuration.drawAnnotations, !film.annotations.isEmpty else { return 0 }
        return FilmIdentificationFooter.heightMillimeters(
            for: film.annotations,
            sheetHeightMillimeters: sheet(for: film).heightMillimeters)
    }

    #if canImport(CoreGraphics)

    private func rasterize(_ film: ReceivedFilm) throws -> ComposedFilm {
        let sheet = self.sheet(for: film)
        let width = sheet.pixelWidth
        let height = sheet.pixelHeight
        guard max(width, height) <= configuration.maximumPixelDimension else {
            throw FilmCompositionError.sheetTooLarge(
                width: width, height: height, limit: configuration.maximumPixelDimension)
        }

        // A palette makes colour out of grey, so it decides the sheet's depth
        // as surely as a colour box does. Without this an all-grayscale film
        // would compose into a grayscale context and throw the palette's colours
        // away at the last step, which is precisely the failure that made a
        // chosen palette look like it did nothing.
        let isColor = configuration.previewPalette != nil
            || film.imageBoxes.contains { ($0.image?.samplesPerPixel ?? 1) > 1 }
        let samplesPerPixel = isColor ? 3 : 1

        // A bitmap CGContext supports 8 bpp gray, but *not* 24 bpp RGB — colour
        // has to be drawn into a 32 bpp RGBX buffer and compacted afterwards.
        // (A 24 bpp `CGImage` is fine, which is why `ComposedFilm` can still
        // publish tightly packed RGB.)
        let contextSamples = isColor ? 4 : 1
        let contextBytesPerRow = width * contextSamples
        var scratch = Data(count: contextBytesPerRow * height)
        var skipped: [String] = []

        let composed: Bool = try scratch.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: contextBytesPerRow,
                    space: isColor ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: isColor
                        ? CGImageAlphaInfo.noneSkipLast.rawValue
                        : CGImageAlphaInfo.none.rawValue) else { return false }

            try draw(film: film, sheet: sheet, in: context, isColor: isColor, skipped: &skipped)
            return true
        }
        guard composed else { throw FilmCompositionError.rasterizerUnavailable }

        let pixels = isColor
            ? Self.compactRGBX(scratch, width: width, height: height)
            : scratch

        return ComposedFilm(
            info: info(for: film, sheet: sheet, skipped: skipped),
            width: width, height: height,
            samplesPerPixel: samplesPerPixel,
            pixels: pixels)
    }

    /// Drops the unused fourth byte of each RGBX pixel.
    private static func compactRGBX(_ source: Data, width: Int, height: Int) -> Data {
        var output = Data(count: width * height * 3)
        source.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { result in
                guard let src = input.bindMemory(to: UInt8.self).baseAddress,
                      let dst = result.bindMemory(to: UInt8.self).baseAddress else { return }
                for index in 0..<(width * height) {
                    dst[index * 3] = src[index * 4]
                    dst[index * 3 + 1] = src[index * 4 + 1]
                    dst[index * 3 + 2] = src[index * 4 + 2]
                }
            }
        }
        return output
    }

    /// Draws the whole sheet. The context uses CoreGraphics' native
    /// bottom-left origin; cell rectangles are top-left, so every rect is
    /// flipped once, here, rather than by a global transform (which would also
    /// mirror the images and the text).
    private func draw(
        film: ReceivedFilm,
        sheet: FilmSheet,
        in context: CGContext,
        isColor: Bool,
        skipped: inout [String]
    ) throws {
        let sheetHeight = Double(sheet.pixelHeight)
        func flip(_ cell: FilmCell) -> CGRect {
            CGRect(x: cell.x, y: sheetHeight - (cell.y + cell.height),
                   width: cell.width, height: cell.height)
        }

        context.interpolationQuality = interpolation(for: film.filmBox.magnificationType)

        // Border: the sheet's background outside the image cells.
        let border = luminance(
            forDensity: film.filmBox.borderDensity, film: film, default: 0)
        context.setFillColor(gray(border, isColor: isColor))
        context.fill(CGRect(x: 0, y: 0, width: Double(sheet.pixelWidth), height: sheetHeight))

        let emptyDensity = luminance(
            forDensity: film.filmBox.emptyImageDensity, film: film, default: 0)
        let boxesByPosition = Dictionary(
            film.imageBoxes.map { (Int($0.content.imagePosition), $0) },
            uniquingKeysWith: { first, _ in first })

        // Where each image landed, for the Trim (2010,0140) box.
        var imageRects: [CGRect] = []
        for cell in cells(for: film) where !cell.isEmpty {
            let destination = flip(cell)
            guard let box = boxesByPosition[cell.position], let image = box.image else {
                // An unfilled box shows Empty Image Density, not the border.
                context.setFillColor(gray(emptyDensity, isColor: isColor))
                context.fill(destination)
                continue
            }

            do {
                imageRects.append(try draw(box: box, image: image, film: film, cell: cell,
                                           sheet: sheet, in: context, isColor: isColor,
                                           emptyDensity: emptyDensity))
            } catch {
                context.setFillColor(gray(emptyDensity, isColor: isColor))
                context.fill(destination)
                skipped.append("position \(cell.position): \(error)")
            }
        }

        if configuration.drawTrimMarks, film.filmBox.trimOption == .yes {
            drawTrimBoxes(around: imageRects, sheet: sheet, in: context,
                          isColor: isColor, border: border)
        }
        if configuration.drawAnnotations, !film.annotations.isEmpty {
            drawAnnotations(film.annotations, sheet: sheet, in: context,
                            isColor: isColor, background: border)
        }
    }

    /// Draws one image box into its cell and returns the rectangle the image
    /// occupies (CoreGraphics coordinates).
    @discardableResult
    private func draw(
        box: ReceivedImageBox,
        image: PrintImageData,
        film: ReceivedFilm,
        cell: FilmCell,
        sheet: FilmSheet,
        in context: CGContext,
        isColor: Bool,
        emptyDensity: Double
    ) throws -> CGRect {
        let invert = shouldInvert(box: box, image: image, film: film)
        let transfer = displayTransfer(film: film)
        guard let cgImage = try makeCGImage(
            from: image, invert: invert, transfer: transfer, forceColor: isColor) else {
            throw FilmCompositionError.unsupportedPhotometricInterpretation(
                image.photometricInterpretation)
        }

        let requestedMillimeters = box.content.requestedImageSize
            .flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        let placement = FilmImageFitter.fit(
            imageWidth: Double(image.columns), imageHeight: Double(image.rows),
            in: cell,
            requestedSizeMillimeters: requestedMillimeters,
            behavior: box.content.requestedDecimateCropBehavior,
            sheet: sheet,
            alignment: configuration.cellAlignment,
            stretch: configuration.stretchToFill)

        switch placement {
        case .failed(let reason):
            throw FilmCompositionError.unsupportedPhotometricInterpretation(reason)

        case .placed(let destination, let sourceX, let sourceY, let sourceWidth, let sourceHeight):
            let source: CGImage
            if sourceWidth < Double(image.columns) || sourceHeight < Double(image.rows) {
                // CROP: `cropping(to:)` takes image coordinates (origin top-left),
                // which is exactly what the fitter reports.
                guard let cropped = cgImage.cropping(to: CGRect(
                    x: sourceX, y: sourceY, width: sourceWidth, height: sourceHeight)) else {
                    throw FilmCompositionError.rasterizerUnavailable
                }
                source = cropped
            } else {
                source = cgImage
            }

            let sheetHeight = Double(sheet.pixelHeight)
            let rect = CGRect(
                x: destination.x, y: sheetHeight - (destination.y + destination.height),
                width: destination.width, height: destination.height)

            // The unused part of the cell keeps Empty Image Density so a
            // letterboxed image does not show the border colour instead.
            context.saveGState()
            context.setFillColor(gray(emptyDensity, isColor: isColor))
            context.fill(CGRect(
                x: cell.x, y: sheetHeight - (cell.y + cell.height),
                width: cell.width, height: cell.height))
            context.draw(source, in: rect)
            context.restoreGState()
            return rect
        }
    }

    // MARK: Pixels

    /// Recolours 8-bit samples through a palette, returning interleaved RGB.
    ///
    /// Takes one or three samples per pixel and always returns three: a colour
    /// box is reduced to Rec.601 luminance first — the same coefficients the
    /// rest of the kit reduces colour with — because a palette indexes a single
    /// scalar. Reducing a colour box does discard its original hue, which for a
    /// colour-Doppler ultrasound is the velocity encoding; that is inherent to
    /// asking for a palette over colour, and it is why this is off unless the
    /// operator turns it on.
    ///
    /// Purely a function of its input. The caller's buffer is not modified.
    static func palettise(
        _ samples: Data, samplesPerPixel: Int, palette: PseudoColorPalette
    ) -> Data {
        let table = palette.entries()
        let lastIndex = table.count - 1
        let pixelCount = samples.count / max(1, samplesPerPixel)

        var rgb = Data(count: pixelCount * 3)
        rgb.withUnsafeMutableBytes { destination in
            samples.withUnsafeBytes { source in
                guard let dst = destination.bindMemory(to: UInt8.self).baseAddress,
                      let src = source.bindMemory(to: UInt8.self).baseAddress else { return }
                for pixel in 0..<pixelCount {
                    let level: Double
                    if samplesPerPixel == 3 {
                        let offset = pixel * 3
                        level = 0.299 * Double(src[offset])
                            + 0.587 * Double(src[offset + 1])
                            + 0.114 * Double(src[offset + 2])
                    } else {
                        level = Double(src[pixel])
                    }
                    let index = Swift.min(
                        lastIndex, Int(level / 255.0 * Double(lastIndex) + 0.5))
                    let entry = table[index]
                    let base = pixel * 3
                    dst[base] = entry.red
                    dst[base + 1] = entry.green
                    dst[base + 2] = entry.blue
                }
            }
        }
        return rgb
    }

    /// Converts an image box's P-Values into an 8-bit `CGImage`.
    ///
    /// `transfer`, when present, is a 256-entry P-value → luminance curve
    /// (LIN OD) applied after the inversions — grayscale only, since a density
    /// curve has no meaning for an RGB box.
    private func makeCGImage(
        from image: PrintImageData,
        invert: Bool,
        transfer: [UInt8]? = nil,
        forceColor: Bool
    ) throws -> CGImage? {
        let width = Int(image.columns), height = Int(image.rows)
        guard width > 0, height > 0 else { return nil }

        let photometric = image.photometricInterpretation
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")).uppercased()
        let isColorSource = image.samplesPerPixel == 3

        var samples: Data
        var samplesPerPixel: Int
        if isColorSource {
            samples = try rgbSamples(from: image, photometric: photometric)
            samplesPerPixel = 3
        } else {
            samples = graySamples(from: image)
            samplesPerPixel = 1
        }

        if invert {
            samples = Data(samples.map { 255 &- $0 })
        }
        if let transfer, samplesPerPixel == 1 {
            samples = Data(samples.map { transfer[Int($0)] })
        }

        // The operator's palette, applied to the pixels on their way into the
        // bitmap and nowhere else. `image` is not written back, so the received
        // P-Values keep their original values for anything that re-reads them.
        //
        // Placed after the inversions and the density curve so the colour lands
        // on the levels the sheet would actually have shown — the same ordering
        // the viewer uses, where the palette follows the VOI rather than
        // preceding it.
        //
        // Every photometric interpretation is eligible here, colour included: a
        // three-sample box is reduced to Rec.601 luminance first, since a
        // palette indexes one scalar and there is otherwise nothing to index.
        if let palette = configuration.previewPalette {
            samples = Self.palettise(
                samples, samplesPerPixel: samplesPerPixel, palette: palette)
            samplesPerPixel = 3
        }

        // A grayscale box on a colour film has to be widened to RGB so it can
        // share one bitmap context with the colour boxes.
        if forceColor && samplesPerPixel == 1 {
            var rgb = Data(count: samples.count * 3)
            samples.withUnsafeBytes { source in
                rgb.withUnsafeMutableBytes { destination in
                    guard let src = source.bindMemory(to: UInt8.self).baseAddress,
                          let dst = destination.bindMemory(to: UInt8.self).baseAddress else { return }
                    for index in 0..<samples.count {
                        dst[index * 3] = src[index]
                        dst[index * 3 + 1] = src[index]
                        dst[index * 3 + 2] = src[index]
                    }
                }
            }
            samples = rgb
            samplesPerPixel = 3
        }

        guard samples.count >= width * height * samplesPerPixel,
              let provider = CGDataProvider(data: samples as CFData) else { return nil }

        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 8 * samplesPerPixel,
            bytesPerRow: width * samplesPerPixel,
            space: samplesPerPixel == 3 ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// 8-bit grayscale samples, rescaled from Bits Stored and sign-corrected.
    private func graySamples(from image: PrintImageData) -> Data {
        let count = Int(image.rows) * Int(image.columns)
        if image.bitsAllocated == 8 {
            var data = image.pixelData.prefix(count)
            if data.count < count { data.append(contentsOf: repeatElement(0, count: count - data.count)) }
            return Data(data)
        }

        // 16-bit allocated: little-endian P-Values scaled from Bits Stored.
        let stored = max(1, min(16, Int(image.bitsStored)))
        let maximum = Double((1 << stored) - 1)
        let signed = image.pixelRepresentation == 1
        let offset = signed ? Double(1 << (stored - 1)) : 0

        var output = Data(count: count)
        image.pixelData.withUnsafeBytes { raw in
            output.withUnsafeMutableBytes { out in
                guard let src = raw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let dst = out.bindMemory(to: UInt8.self).baseAddress else { return }
                let available = min(count, raw.count / 2)
                for index in 0..<available {
                    let low = UInt16(src[index * 2])
                    let high = UInt16(src[index * 2 + 1])
                    let raw16 = low | (high << 8)
                    let value = signed
                        ? Double(Int16(bitPattern: raw16)) + offset
                        : Double(raw16)
                    let scaled = (value / maximum) * 255
                    dst[index] = UInt8(max(0, min(255, scaled.rounded())))
                }
            }
        }
        return output
    }

    /// 8-bit interleaved RGB samples for a colour image box.
    ///
    /// PS3.3 Table C.13-5 enumerates only RGB for the Basic Color Image
    /// Sequence, and our own SCU converts to RGB before sending, but
    /// third-party SCUs do send YBR — including the 4:2:2 packed form, Y1 Y2 Cb
    /// Cr per pixel pair (PS3.3 C.7.6.3.1.2) — so the composer reads both
    /// rather than refuse the film. The partial-range equations are the
    /// inverse of the C.7.6.3.1.2 YBR_PARTIAL_422 definition.
    private func rgbSamples(from image: PrintImageData, photometric: String) throws -> Data {
        let width = Int(image.columns), height = Int(image.rows)
        let pixelCount = width * height
        let source = image.pixelData

        switch photometric {
        case "RGB", "":
            var data = source.prefix(pixelCount * 3)
            if data.count < pixelCount * 3 {
                data.append(contentsOf: repeatElement(0, count: pixelCount * 3 - data.count))
            }
            return Data(data)

        case "YBR_FULL", "YBR_PARTIAL_420", "YBR_ICT", "YBR_RCT":
            guard photometric == "YBR_FULL" else {
                throw FilmCompositionError.unsupportedPhotometricInterpretation(photometric)
            }
            var output = Data(count: pixelCount * 3)
            for index in 0..<pixelCount {
                let base = index * 3
                guard base + 2 < source.count else { break }
                let (r, g, b) = Self.ybrToRGB(
                    y: Double(source[source.startIndex + base]),
                    cb: Double(source[source.startIndex + base + 1]),
                    cr: Double(source[source.startIndex + base + 2]),
                    fullRange: true)
                output[base] = r; output[base + 1] = g; output[base + 2] = b
            }
            return output

        case "YBR_FULL_422", "YBR_PARTIAL_422":
            // Packed: Y1 Y2 Cb Cr per horizontal pixel pair.
            let fullRange = photometric == "YBR_FULL_422"
            var output = Data(count: pixelCount * 3)
            var pixel = 0
            var offset = source.startIndex
            while pixel + 1 < pixelCount, offset + 3 < source.endIndex {
                let y1 = Double(source[offset])
                let y2 = Double(source[offset + 1])
                let cb = Double(source[offset + 2])
                let cr = Double(source[offset + 3])
                let first = Self.ybrToRGB(y: y1, cb: cb, cr: cr, fullRange: fullRange)
                let second = Self.ybrToRGB(y: y2, cb: cb, cr: cr, fullRange: fullRange)
                output[pixel * 3] = first.0
                output[pixel * 3 + 1] = first.1
                output[pixel * 3 + 2] = first.2
                output[(pixel + 1) * 3] = second.0
                output[(pixel + 1) * 3 + 1] = second.1
                output[(pixel + 1) * 3 + 2] = second.2
                pixel += 2
                offset += 4
            }
            return output

        default:
            throw FilmCompositionError.unsupportedPhotometricInterpretation(photometric)
        }
    }

    /// YCbCr → RGB. Full range is the DICOM YBR_FULL convention; partial range
    /// is BT.601 studio swing (Y 16–235, C 16–240).
    static func ybrToRGB(y: Double, cb: Double, cr: Double, fullRange: Bool) -> (UInt8, UInt8, UInt8) {
        let yy: Double, cbb: Double, crr: Double
        if fullRange {
            yy = y; cbb = cb - 128; crr = cr - 128
        } else {
            yy = (y - 16) * (255.0 / 219.0)
            cbb = (cb - 128) * (255.0 / 224.0)
            crr = (cr - 128) * (255.0 / 224.0)
        }
        let r = yy + 1.402 * crr
        let g = yy - 0.344136 * cbb - 0.714136 * crr
        let b = yy + 1.772 * cbb
        func clamp(_ value: Double) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }
        return (clamp(r), clamp(g), clamp(b))
    }

    // MARK: Density and polarity

    /// Whether an image box's pixels must be inverted before drawing.
    ///
    /// Four independent inversions compose (each flips the sense of the last):
    /// MONOCHROME1 source, Polarity REVERSE, a rendered-inverse Presentation
    /// LUT shape, and film-emulation density mapping.
    func shouldInvert(box: ReceivedImageBox, image: PrintImageData, film: ReceivedFilm) -> Bool {
        var invert = false
        let photometric = image.photometricInterpretation
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")).uppercased()
        if photometric == "MONOCHROME1" { invert.toggle() }
        if box.content.polarity == .reverse { invert.toggle() }
        switch film.presentationLUTShape {
        case .inverseRendered: invert.toggle()
        // LIN OD is not a negation — it is the density curve applied in
        // ``linODTransfer(film:)``, whose low-P-is-dark orientation already
        // contains the reversal this switch used to fake with a toggle.
        case .identity, .linearOpticalDensity, nil: break
        }
        if configuration.densityMapping == .filmEmulation { invert.toggle() }
        return invert
    }

    /// The grayscale transfer the sheet is drawn through: the calibrated
    /// P-Value (or LIN OD) → displayed-grey curve under ``DensityMapping/gsdf``,
    /// else the LIN OD curve when that shape is in force, else none.
    func displayTransfer(film: ReceivedFilm) -> [UInt8]? {
        guard configuration.densityMapping == .gsdf else { return linODTransfer(film: film) }
        let viewing = hardcopyViewing(for: film)
        return (0...255).map { p in
            let luminance = film.presentationLUTShape == .linearOpticalDensity
                // C.11.4 LIN OD: the input is linear in optical density over
                // Min…Max Density, low input light, as `linODTransfer` reads it.
                ? viewing.luminance(density: viewing.minDensity
                    + Double(p) / 255 * (viewing.maxDensity - viewing.minDensity))
                // IDENTITY (or no shape): the input is P-Values, laid down
                // through the GSDF (PS3.14 7.2 / 7.3).
                : viewing.luminance(pValue: Double(p))
            return viewing.displayValue(luminance: luminance)
        }
    }

    /// How the sheet is viewed under ``DensityMapping/gsdf``: PAPER is a
    /// reflective print (PS3.14 7.3), every film medium transmissive (7.2);
    /// Min/Max Density from the film box, or 0.20/3.00 OD.
    func hardcopyViewing(for film: ReceivedFilm) -> HardcopyViewing {
        let minOD = Double(film.minDensity ?? 20) / 100
        let maxOD = Double(film.maxDensity ?? 300) / 100
        let (low, high) = maxOD > minOD ? (minOD, maxOD) : (0.2, 3.0)
        return film.filmSession.mediumType == .paper
            ? .reflective(minDensity: low, maxDensity: high)
            : .transmissive(minDensity: low, maxDensity: high)
    }

    /// The LIN OD transfer curve as a 256-entry P-value → luminance table.
    ///
    /// Under LIN OD the input values are linearly proportional to *optical
    /// density*, low input printing light (Min Density) and high input dark —
    /// the same orientation the previous invert-toggle approximated. What the
    /// toggle got wrong is the curve: a screen shows transmitted luminance,
    /// which falls off as 10^(−OD), so equal density steps are exponential
    /// luminance steps, not the straight line a negation draws:
    ///
    ///     OD(p) = Dmin + (p/255)·(Dmax − Dmin)
    ///     l(p)  = (10^(−OD(p)) − 10^(−Dmax)) / (10^(−Dmin) − 10^(−Dmax))
    ///
    /// Min/Max Density arrive in hundredths of OD (PS3.3 C.13.3), defaulting
    /// to 0.2 / 3.0 — ordinary film stock — when the film box does not say.
    func linODTransfer(film: ReceivedFilm) -> [UInt8]? {
        guard film.presentationLUTShape == .linearOpticalDensity else { return nil }
        let minOD = Double(film.minDensity ?? 20) / 100
        let maxOD = Double(film.maxDensity ?? 300) / 100
        guard maxOD > minOD else { return nil }

        let brightest = pow(10, -minOD)
        let darkest = pow(10, -maxOD)
        return (0...255).map { p in
            let density = minOD + (Double(p) / 255) * (maxOD - minOD)
            let luminance = (pow(10, -density) - darkest) / (brightest - darkest)
            return UInt8(max(0, min(255, (luminance * 255).rounded())))
        }
    }

    /// Maps a Border / Empty Image Density value to a luminance in 0...1.
    ///
    /// The attribute is either `BLACK`, `WHITE`, or a numeric optical density in
    /// hundredths (PS3.3 C.13.3), which is interpolated between the film box's
    /// Min and Max Density when both are known.
    func luminance(forDensity value: String, film: ReceivedFilm, default fallback: Double) -> Double {
        let text = value.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")).uppercased()
        if configuration.densityMapping == .gsdf {
            // A density is a density: BLACK the sheet's maximum, WHITE its
            // minimum, i hundredths of OD (Table C.13-3), seen as L = La +
            // L0·10^−D (PS3.14 7.2 / 7.3).
            let viewing = hardcopyViewing(for: film)
            let density: Double
            switch text {
            case "BLACK": density = viewing.maxDensity
            case "WHITE": density = viewing.minDensity
            default:
                guard let hundredths = Double(text) else { return fallback }
                density = hundredths / 100
            }
            return Double(viewing.displayValue(luminance: viewing.luminance(density: density))) / 255
        }
        switch text {
        case "BLACK": return configuration.densityMapping == .filmEmulation ? 1 : 0
        case "WHITE": return configuration.densityMapping == .filmEmulation ? 0 : 1
        default:
            guard let density = Double(text) else { return fallback }
            let minimum = Double(film.minDensity ?? 20)
            let maximum = Double(film.maxDensity ?? 300)
            guard maximum > minimum else { return fallback }
            // Higher optical density = darker on film.
            let normalized = (density - minimum) / (maximum - minimum)
            let clamped = max(0, min(1, normalized))
            return configuration.densityMapping == .filmEmulation ? clamped : 1 - clamped
        }
    }

    private func gray(_ luminance: Double, isColor: Bool) -> CGColor {
        let value = max(0, min(1, luminance))
        if isColor {
            return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                           components: [value, value, value, 1])
                ?? CGColor(gray: value, alpha: 1)
        }
        return CGColor(gray: value, alpha: 1)
    }

    private func interpolation(for magnification: MagnificationType) -> CGInterpolationQuality {
        switch magnification {
        case .none, .replicate: return .none
        case .bilinear: return .low
        case .cubic: return .high
        }
    }

    // MARK: Decoration

    /// Trim = YES: "a trim box shall be printed surrounding each image on the
    /// film" (PS3.3 Table C.13-3, Trim (2010,0140)). One rectangle per placed
    /// image, stroked just outside the image so no pixel of it is covered, in
    /// the tone that contrasts with the Border Density.
    private func drawTrimBoxes(
        around imageRects: [CGRect], sheet: FilmSheet,
        in context: CGContext, isColor: Bool, border: Double
    ) {
        guard !imageRects.isEmpty else { return }
        let lineWidth = max(1, sheet.pixels(fromMillimeters: 0.3))
        context.saveGState()
        context.setStrokeColor(gray(border > 0.5 ? 0 : 1, isColor: isColor))
        context.setLineWidth(lineWidth)
        for rect in imageRects {
            context.stroke(rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2))
        }
        context.restoreGState()
    }

    /// Draws Basic Annotation Box text in the strip kept clear along the bottom
    /// of the sheet.
    ///
    /// A real printer places annotations per its configured Annotation Display
    /// Format; an emulator has no such configuration, so positions are laid out
    /// in order along the bottom of the sheet, which is where film headers
    /// conventionally sit — and where a film-wide patient footer belongs.
    ///
    /// Centred, and in the band ``cells(for:)`` has already taken out of the
    /// layout, so the text sits under the pictures rather than across the
    /// bottom row of them.
    private func drawAnnotations(
        _ annotations: [PrintAnnotation],
        sheet: FilmSheet,
        in context: CGContext,
        isColor: Bool,
        background: Double
    ) {
        // Type off the sheet, so the same caption reads at the distance a film
        // of this size is read from.
        let fontMillimeters = FilmIdentificationFooter.fontMillimeters(
            sheetHeightMillimeters: sheet.heightMillimeters)
        let fontSize = max(8, sheet.pixels(fromMillimeters: fontMillimeters))
        let font = CTFontCreateWithName(
            PrintAnnotationStyle.defaultFontFamily as CFString, fontSize, nil)
        let color = gray(background > 0.5 ? 0 : 1, isColor: isColor)
        let lineHeight = fontSize * FilmIdentificationFooter.lineFactor
        let margin = sheet.pixels(fromMillimeters: configuration.marginMillimeters)
        let padding = fontSize * FilmIdentificationFooter.paddingFactor
        let edge = configuration.annotationEdge
        let sheetWidth = Double(sheet.pixelWidth)
        let sheetHeight = Double(sheet.pixelHeight)

        context.saveGState()
        context.textMatrix = .identity
        // A side band runs the text along the edge: the whole context turns a
        // quarter, lines then lay out exactly as they do on a horizontal band.
        // (CG origin is bottom-left, +y up; rotations are counterclockwise.)
        switch edge {
        case .left:
            // Baseline runs down the sheet (reads top-to-bottom, glyph tops
            // inward) — spine orientation. Lines stack in from the left edge.
            context.rotate(by: -.pi / 2)
            context.translateBy(x: -sheetHeight, y: 0)
        case .right:
            // Baseline runs up the sheet (reads bottom-to-top, glyph tops
            // inward). Lines stack in from the right edge.
            context.rotate(by: .pi / 2)
            context.translateBy(x: 0, y: -sheetWidth)
        case .top, .bottom, .overlay:
            break
        }
        // The band's coordinate space: on a side band the "width" to centre in
        // is the sheet's height, and the lines stack in from the turned edge.
        let bandWidth = (edge == .left || edge == .right) ? sheetHeight : sheetWidth

        for (index, annotation) in annotations.enumerated() {
            // CoreText attribute keys directly: DICOMPrintKit must not pull in
            // AppKit/UIKit for `NSAttributedString.Key.font`.
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: color
            ]
            let attributed = CFAttributedStringCreate(
                nil, annotation.text as CFString, attributes as CFDictionary)
            guard let attributed else { continue }
            let line = CTLineCreateWithAttributedString(attributed)
            let bounds = CTLineGetImageBounds(line, context)
            let x = max(margin, (bandWidth - Double(bounds.width)) / 2)
            let y: Double
            switch edge {
            case .bottom, .overlay, .left, .right:
                // Stack upwards from the near margin, first position innermost.
                y = margin + padding + Double(annotations.count - index - 1) * lineHeight
            case .top:
                // Stack downward from the top, first position uppermost.
                y = sheetHeight - margin - padding - Double(index + 1) * lineHeight
            }
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }

    #endif

    // MARK: Metadata

    /// Builds the metadata payload that travels with the bitmap.
    func info(for film: ReceivedFilm, sheet: FilmSheet, skipped: [String]) -> ComposedFilmInfo {
        let format = PrintImageDisplayFormat.parse(film.filmBox.imageDisplayFormat)
        return ComposedFilmInfo(
            printJobUID: film.printJobUID,
            filmSessionUID: film.filmSession.sopInstanceUID,
            filmBoxUID: film.filmBox.sopInstanceUID,
            callingAETitle: film.callingAETitle,
            receivedAt: film.timestamp,
            filmSize: film.filmBox.filmSizeID.rawValue,
            filmOrientation: film.filmBox.filmOrientation.rawValue,
            imageDisplayFormat: film.filmBox.imageDisplayFormat,
            rows: format.layout.rows,
            columns: format.layout.columns,
            mediumType: film.filmSession.mediumType.wireValue,
            numberOfCopies: film.filmSession.numberOfCopies,
            filmSessionLabel: film.filmSession.filmSessionLabel,
            magnificationType: film.filmBox.magnificationType.rawValue,
            borderDensity: film.filmBox.borderDensity,
            emptyImageDensity: film.filmBox.emptyImageDensity,
            trim: film.filmBox.trimOption.rawValue,
            minDensity: film.minDensity,
            maxDensity: film.maxDensity,
            presentationLUTShape: film.presentationLUTShape?.rawValue,
            annotations: film.annotations.map { "\($0.position): \($0.text)" },
            sheetWidthMillimeters: sheet.widthMillimeters,
            sheetHeightMillimeters: sheet.heightMillimeters,
            dpi: sheet.dpi,
            densityMapping: configuration.densityMapping,
            filledImageBoxCount: film.filledImageBoxes.count,
            imageBoxCount: film.imageBoxes.count,
            skippedImageBoxes: skipped)
    }
}
