// NEMA-verified: 2026a, checked 2026-09-29 — MONOCHROME1 polarity of burned text per PS3.3 2026a C.7.6.3.1.2; 8-bit grayscale/RGB image box pixels per Table C.13-5; otherwise CoreGraphics drawing
// ImageAnnotationBurner.swift
// DICOMPrintKit
//
// Burning text into the pixels of a printable frame: the patient caption the
// print path always adds, and whatever the reader drew on the film cell.
//
// A DICOM printer draws annotation from the film box's own annotation boxes,
// which every printer lays out differently and many ignore. Film that must
// carry the patient's name — which is most film — therefore carries it in the
// pixels, exactly where the viewer draws it: in the corners of the picture,
// where a fitted image has background rather than anatomy. A drawn arrow could
// not be expressed as an annotation box at all.
//
// This runs once per image, on the already-prepared 8-bit frame, so the cost is
// one bitmap pass per film cell rather than anything per redraw.

import Foundation
import DICOMNetwork

// MARK: - Style

/// How burned identification text is set (SRS FR-006).
///
/// The default, `.automatic`, is exactly what the burner always did: Helvetica,
/// sized as a fraction of the frame, coloured to the far end of the greyscale
/// from whatever is under it. That logic is good — it adapts to image size and
/// flips correctly for MONOCHROME1 — so overriding it is available, not
/// required.
public struct PrintAnnotationStyle: Sendable, Equatable, Hashable, Codable {

    /// How the caption is coloured.
    public enum Foreground: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
        /// White as the pixels express it, halo at the other end — adapts to
        /// MONOCHROME1 and RGB. The default.
        case automatic
        /// Force white type (black halo). On MONOCHROME1 this is the *dark*
        /// stored value; on film it reads white.
        case white
        /// Force black type (white halo).
        case black
    }

    /// PostScript/family name of the caption font. Names CoreText cannot
    /// resolve fall back to Helvetica, so a bad value degrades to the default
    /// rather than to no caption.
    public var fontFamily: String

    /// The face the caption is set in unless a job asks for another.
    ///
    /// Named rather than spelled out at each call site: the caption is drawn by
    /// the burner on film, by `PatientIdentificationOverlayView` on screen, and
    /// measured by both when deciding where a block has to shrink. Those are
    /// three places a literal could drift apart, and the preview is only worth
    /// looking at while they agree.
    public static let defaultFontFamily = "Helvetica"

    /// Caption height as a fraction of the frame's height, or `nil` for the
    /// automatic size. Clamped to 0.02…0.10: below 2% the caption is
    /// illegible on any cell — the SRS's 8 pt floor, expressed relative to
    /// the picture the way every other size here is — and above 10% it is a
    /// headline over the anatomy.
    public var sizeFraction: Double?

    /// Caption colour.
    public var foreground: Foreground

    /// Whether this film carries one image on the sheet — a 1\u{d7}1 layout.
    ///
    /// The caption is sized as a fraction of the frame so that a 4\u{d7}5 tile and
    /// a full sheet carry type of the same *apparent* size. That proportion is
    /// right everywhere except at the one extreme, where the frame is the whole
    /// film: 3.5% of a full sheet is a caption that reads as a headline over the
    /// anatomy rather than as identification at the edge of it. Every other
    /// layout divides the sheet enough that the fraction lands where it should.
    ///
    /// So the single-image film — and only it — takes ``singleImageFactor``. The
    /// flag rather than a pixel threshold: "how many cells is this sheet cut
    /// into" is the thing that actually decides it, and a frame's pixel count
    /// depends on the printer's resolution, which would make the caption change
    /// size with the DPI. Carried on the style so the burner and the preview
    /// read one value — the two must set the caption at the same size or the
    /// preview cannot be used to judge the film.
    public var singleImageFilm: Bool

    public init(fontFamily: String = PrintAnnotationStyle.defaultFontFamily,
                sizeFraction: Double? = nil,
                foreground: Foreground = .automatic,
                singleImageFilm: Bool = false) {
        self.fontFamily = fontFamily
        self.sizeFraction = sizeFraction.map { min(0.10, max(0.02, $0)) }
        self.foreground = foreground
        self.singleImageFilm = singleImageFilm
    }

    /// What the caption's size is multiplied by on a single-image film.
    ///
    /// Applied to the automatic fraction *and* to a job's own stated fraction:
    /// a reader who asked for 3.5% asked for the size they have been reading on
    /// multi-cell sheets, and the sheet being cut into one cell does not change
    /// what they meant. The floors still apply underneath, so this cannot taper
    /// a caption into illegibility.
    public static let singleImageFactor: Double = 0.6

    /// This style as it applies to a sheet of `cellCount` cells.
    ///
    /// The one place the layout is turned into typography, so a caller that
    /// knows the plan does not have to know the rule.
    public func on(cellCount: Int) -> PrintAnnotationStyle {
        var copy = self
        copy.singleImageFilm = cellCount == 1
        return copy
    }

    /// The fraction of the frame's height a caption is set at under this style,
    /// or `nil` where the automatic height/width pair applies. The taper is
    /// already in it.
    public var resolvedSizeFraction: Double? {
        sizeFraction.map { singleImageFilm ? $0 * Self.singleImageFactor : $0 }
    }

    /// Today's behaviour, byte for byte.
    public static let automatic = PrintAnnotationStyle()
}

#if canImport(CoreGraphics)
import CoreGraphics
import CoreText

public enum ImageAnnotationBurner {

    /// Draws identification into the four corners of a prepared frame.
    ///
    /// Over the picture, not in a strip taken out of it: the corners of a fitted
    /// image are background, and every pixel the anatomy has is a pixel the
    /// reader keeps. Each line is drawn twice — a halo at the far end of the
    /// scale, then the text — so it survives both a black background and a white
    /// lung field.
    ///
    /// Returns the frame unchanged when there is nothing to draw, or when the
    /// pixels are not 8-bit grayscale or 8-bit RGB — the two formats an image
    /// box is prepared into. Refusing quietly is deliberate: an unexpected
    /// format is a reason to print the picture without a caption, never a reason
    /// to fail the job or to write text into pixels of a depth this has not
    /// been asked to interpret.
    public static func burning(
        corners: PrintCornerAnnotation,
        into image: PreparedPrintImage,
        style: PrintAnnotationStyle = .automatic
    ) -> PreparedPrintImage {
        guard !corners.isEmpty else { return image }

        return rendering(into: image) { canvas in
            let fontSize = fittedCaptionFontSize(
                for: corners, width: canvas.width, height: canvas.height,
                style: style)
            let margin = fontSize * captionMarginFactor
            let lineHeight = fontSize * captionLineFactor
            let foreground = canvas.captionForeground(style.foreground)
            let shadow = canvas.captionShadow(style.foreground)

            // A bitmap context's origin is its bottom-left, so the top corners
            // are the high `y` values — and the top of the anatomy as it is
            // displayed, since a DICOM image's rows run top to bottom.
            let top = Double(canvas.height) - margin - fontSize
            let bottom = margin

            func block(_ lines: [String], top isTop: Bool, trailing: Bool) {
                for (index, text) in lines.enumerated() {
                    let step = Double(isTop ? index : lines.count - 1 - index) * lineHeight
                    let baseline = isTop ? top - step : bottom + step
                    drawLine(text, in: canvas.context, fontSize: fontSize,
                             baseline: baseline, margin: margin,
                             width: Double(canvas.width), trailing: trailing,
                             foreground: foreground, shadow: shadow,
                             fontFamily: style.fontFamily)
                }
            }

            block(corners.topLeft, top: true, trailing: false)
            block(corners.topRight, top: true, trailing: true)
            block(corners.bottomLeft, top: false, trailing: false)
            block(corners.bottomRight, top: false, trailing: true)
        }
    }

    /// Draws what the reader drew on the film cell — text where they put it, and
    /// arrows pointing where they pointed.
    ///
    /// Positions are fractions of the image, so the same annotations drawn on a
    /// preview thumbnail land in the same places on a full-resolution frame. Blank
    /// annotations are skipped: a text box is empty for as long as it takes to
    /// type into it, and that is not a reason to draw nothing at all.
    ///
    /// - Parameter orientation: how the frame was arranged before it got here,
    ///   or `nil` for a frame that was not arranged at all. The pixels handed
    ///   in have already been cropped, turned and mirrored, while the
    ///   annotations are still in the *original* image's coordinates — so
    ///   without this an annotation on a turned cell is burned wherever that
    ///   fraction happens to fall in the turned buffer, which is not where the
    ///   reader put it. See ``PrintOverlayOrientation``.
    public static func burning(
        overlays: [PrintOverlayAnnotation],
        into image: PreparedPrintImage,
        orientation: PrintOverlayOrientation? = nil
    ) -> PreparedPrintImage {
        let drawable = drawOrder(overlays)
        guard !drawable.isEmpty else { return image }

        return rendering(into: image) { canvas in
            for overlay in drawable {
                switch overlay.kind {
                case .text:  drawText(overlay, in: canvas, orientation: orientation)
                case .arrow: drawArrow(overlay, in: canvas, orientation: orientation)
                case .annotation:
                    drawCombined(overlay, in: canvas, orientation: orientation)
                case .polyline, .circle, .ellipse, .point:
                    drawShape(overlay, in: canvas, orientation: orientation)
                case .shutter:
                    drawShutter(overlay, in: canvas, orientation: orientation)
                }
            }
        }
    }

    /// The overlays worth drawing, in the order they must be drawn: shutters
    /// first, so a mask never paints over a ruler or a label that sits inside
    /// the open region's edge; blanks dropped.
    static func drawOrder(_ overlays: [PrintOverlayAnnotation]) -> [PrintOverlayAnnotation] {
        let drawable = overlays.filter { !$0.isBlank }
        return drawable.filter { $0.kind == .shutter } + drawable.filter { $0.kind != .shutter }
    }

    /// Rasterizes what the reader drew onto a transparent RGBA canvas, instead
    /// of burning it into a prepared frame's own pixels.
    ///
    /// Same drawing routines as ``burning(overlays:into:)`` — the halo, the
    /// arrowhead geometry, the anchor points — so a caller showing this
    /// (the main viewer's GPU overlay) can never drift from what a print
    /// job would have burned. The one difference is the destination: this
    /// draws onto its own transparent buffer at the given dimensions rather
    /// than into a `PreparedPrintImage`'s pixels, and always in plain RGB —
    /// there is no photometric interpretation to flatten to here, unlike a
    /// frame that is actually being sent to a printer.
    ///
    /// - Returns: `nil` only if the CoreGraphics context could not be built.
    ///   An empty or entirely-blank `overlays` still returns bytes — all
    ///   zero, i.e. fully transparent — rather than `nil`, so a caller does
    ///   not need a separate "nothing to draw" branch.
    /// - Parameter orientation: the arrangement the *display* will apply to
    ///   this texture after it is built. The viewer's shader turns and mirrors
    ///   the overlay along with the picture, which puts an annotation's anchor
    ///   in the right place for free but also writes its words backwards on a
    ///   mirrored image and upside down on a half-turned one. Passing the
    ///   arrangement here pre-cancels that for the lettering only — the anchor
    ///   is left in image space for the shader to move, and arrows are left
    ///   alone, because a turned arrow still points where it pointed.
    public static func rasterizing(
        overlays: [PrintOverlayAnnotation],
        width: Int,
        height: Int,
        orientation: PrintOverlayOrientation? = nil
    ) -> (bytes: [UInt8], bytesPerRow: Int)? {
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)

        let drawn: Bool = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            let canvas = Canvas(context: context, width: width, height: height,
                                isInverted: false, isGrayscale: false)
            for overlay in drawOrder(overlays) {
                switch overlay.kind {
                // Lettering only: `uprightOnly` turns the glyphs back without
                // moving the anchor, because the shader moves the anchor.
                case .text:  drawText(overlay, in: canvas,
                                      orientation: orientation, uprightOnly: true)
                case .arrow: drawArrow(overlay, in: canvas)
                case .annotation:
                    drawCombined(overlay, in: canvas,
                                 orientation: orientation, uprightOnly: true)
                // Shapes and shutters sit in image space like arrows do: the
                // shader turns them with the picture, so they are left unmapped.
                case .polyline, .circle, .ellipse, .point:
                    drawShape(overlay, in: canvas)
                case .shutter:
                    drawShutter(overlay, in: canvas)
                }
            }
            return true
        }
        guard drawn else { return nil }
        return (rgba, bytesPerRow)
    }

    // MARK: - The pixel buffer

    /// A prepared frame's pixels, wrapped in something drawable.
    ///
    /// Both burners need the same three things — a context the right way up, the
    /// frame's size, and colours that will read against these pixels — and the
    /// last of those depends on the photometric, which is easy to get wrong twice.
    struct Canvas {
        let context: CGContext
        let width: Int
        let height: Int

        /// True for MONOCHROME1, whose maximum value is *black*.
        let isInverted: Bool

        /// True when the frame carries one sample per pixel, so a colour has to
        /// be flattened to a grey before it can be drawn.
        let isGrayscale: Bool

        /// White as these pixels express it.
        var captionForeground: CGColor {
            isGrayscale ? CGColor(gray: isInverted ? 0 : 1, alpha: 1)
                        : CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        }

        /// The halo colour: the opposite end of the scale.
        var captionShadow: CGColor { background }

        /// The caption colour a style asks for, in these pixels' terms.
        ///
        /// "White" and "black" are what the *film* shows, so on MONOCHROME1 —
        /// whose maximum stored value is black — the forced values flip just
        /// as the automatic ones do.
        func captionForeground(_ choice: PrintAnnotationStyle.Foreground) -> CGColor {
            switch choice {
            case .automatic: return captionForeground
            case .white:
                return isGrayscale ? CGColor(gray: isInverted ? 0 : 1, alpha: 1)
                                   : CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            case .black:
                return isGrayscale ? CGColor(gray: isInverted ? 1 : 0, alpha: 1)
                                   : CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            }
        }

        /// The halo for a styled caption: always the far end from the type.
        func captionShadow(_ choice: PrintAnnotationStyle.Foreground) -> CGColor {
            switch choice {
            case .automatic, .white: return captionShadow
            case .black:             return captionForeground
            }
        }

        /// Black as these pixels express it — the fill behind a reserved strip,
        /// and the halo a caption is drawn over.
        var background: CGColor {
            isGrayscale ? CGColor(gray: isInverted ? 1 : 0, alpha: 1)
                        : CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        }

        /// An annotation's colour, as this frame can express it.
        ///
        /// A greyscale frame gets the colour's luminance — the film is being
        /// printed in greys, and a yellow arrow at full luminance is what the
        /// preview showed. On MONOCHROME1 the value is flipped, so a bright
        /// colour stays bright on film.
        func color(for overlay: PrintOverlayColor) -> CGColor {
            guard isGrayscale else {
                return CGColor(red: overlay.red, green: overlay.green,
                               blue: overlay.blue, alpha: 1)
            }
            let value = isInverted ? 1 - overlay.luminance : overlay.luminance
            return CGColor(gray: value, alpha: 1)
        }

        /// The halo drawn behind an annotation so it survives whatever is under
        /// it: the far end of the scale from the annotation itself.
        func halo(for overlay: PrintOverlayColor) -> CGColor {
            let dark = overlay.luminance > 0.45
            if isGrayscale {
                let value = dark ? 0.0 : 1.0
                return CGColor(gray: isInverted ? 1 - value : value, alpha: 1)
            }
            let value = dark ? 0.0 : 1.0
            return CGColor(red: value, green: value, blue: value, alpha: 1)
        }
    }

    /// Runs a drawing pass over a prepared frame's pixels.
    ///
    /// Returns the frame unchanged when there is nothing drawable about it: not
    /// 8-bit, not 1 or 3 samples, or short of the pixels its own descriptor
    /// claims. Refusing quietly is deliberate — an unexpected format is a reason
    /// to print the picture without annotation, never a reason to fail the job or
    /// to write into pixels of a depth this has not been asked to interpret.
    private static func rendering(
        into image: PreparedPrintImage,
        draw: (Canvas) -> Void
    ) -> PreparedPrintImage {
        let descriptor = image.descriptor
        guard descriptor.bitsAllocated == 8,
              descriptor.rows > 0, descriptor.columns > 0 else { return image }

        let width = Int(descriptor.columns)
        let height = Int(descriptor.rows)
        let samples = Int(descriptor.samplesPerPixel)
        guard samples == 1 || samples == 3 else { return image }
        guard descriptor.pixelData.count >= width * height * samples else { return image }

        let isInverted = descriptor.photometricInterpretation.uppercased() == "MONOCHROME1"

        let burned: Data? = samples == 1
            ? drawGrayscale(pixels: descriptor.pixelData, width: width, height: height,
                            inverted: isInverted, draw: draw)
            : drawRGB(pixels: descriptor.pixelData, width: width, height: height,
                      inverted: isInverted, draw: draw)

        guard let burned else { return image }

        return PreparedPrintImage(
            descriptor: PrintImageData(
                pixelData: burned,
                rows: descriptor.rows,
                columns: descriptor.columns,
                bitsAllocated: descriptor.bitsAllocated,
                bitsStored: descriptor.bitsStored,
                highBit: descriptor.highBit,
                samplesPerPixel: descriptor.samplesPerPixel,
                pixelRepresentation: descriptor.pixelRepresentation,
                photometricInterpretation: descriptor.photometricInterpretation
            ),
            sourcePath: image.sourcePath,
            frameIndex: image.frameIndex,
            rowSpacingMillimeters: image.rowSpacingMillimeters,
            columnSpacingMillimeters: image.columnSpacingMillimeters
        )
    }

    // MARK: - Grayscale

    private static func drawGrayscale(
        pixels: Data,
        width: Int,
        height: Int,
        inverted: Bool,
        draw: (Canvas) -> Void
    ) -> Data? {
        var bytes = [UInt8](pixels.prefix(width * height))
        guard bytes.count == width * height else { return nil }

        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return false }
            draw(Canvas(context: context, width: width, height: height,
                        isInverted: inverted, isGrayscale: true))
            return true
        }
        return drawn ? Data(bytes) : nil
    }

    // MARK: - Colour

    private static func drawRGB(
        pixels: Data,
        width: Int,
        height: Int,
        inverted: Bool,
        draw: (Canvas) -> Void
    ) -> Data? {
        // CoreGraphics has no 24-bit RGB context, so the frame is widened to
        // RGBA for the draw and packed back afterwards. The alpha channel is
        // scratch space and never leaves this function.
        let pixelCount = width * height
        var rgba = [UInt8](repeating: 255, count: pixelCount * 4)
        pixels.withUnsafeBytes { source in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return }
            for index in 0..<pixelCount {
                rgba[index * 4] = base[index * 3]
                rgba[index * 4 + 1] = base[index * 3 + 1]
                rgba[index * 4 + 2] = base[index * 3 + 2]
            }
        }

        let drawn: Bool = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else { return false }
            draw(Canvas(context: context, width: width, height: height,
                        isInverted: inverted, isGrayscale: false))
            return true
        }
        guard drawn else { return nil }

        var packed = [UInt8](repeating: 0, count: pixelCount * 3)
        for index in 0..<pixelCount {
            packed[index * 3] = rgba[index * 4]
            packed[index * 3 + 1] = rgba[index * 4 + 1]
            packed[index * 3 + 2] = rgba[index * 4 + 2]
        }
        return Data(packed)
    }

    // MARK: - Drawing

    /// Draws one line at a baseline, against the left or the right margin.
    ///
    /// A line too long for the frame is pulled back to the margin rather than
    /// allowed to run off the edge: a patient's name half printed is a name that
    /// can be misread, and the halo makes the overlap survivable.
    private static func drawLine(
        _ text: String,
        in context: CGContext,
        fontSize: Double,
        baseline: Double,
        margin: Double,
        width: Double,
        trailing: Bool,
        foreground: CGColor,
        shadow: CGColor,
        fontFamily: String = PrintAnnotationStyle.defaultFontFamily
    ) {
        // Plain, as the preview sets it: one weight for the whole block, because
        // nothing in the corners is a different kind of statement from anything
        // else there. The halo below is what keeps it legible, not the weight.
        // CTFontCreateWithName resolves unknown names to a fallback face, so a
        // bad family degrades to a readable caption rather than to none.
        let font = CTFontCreateWithName(fontFamily as CFString, fontSize, nil)
        context.saveGState()
        context.textMatrix = .identity
        // Drawn twice: a halo at the far end of the scale, then the text — so it
        // survives both a white lung field and a black background.
        let spread = max(1.0, fontSize * 0.08)
        for (offset, color) in [(spread, shadow), (0.0, foreground)] {
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: color
            ]
            guard let attributed = CFAttributedStringCreate(
                nil, text as CFString, attributes as CFDictionary) else { continue }
            let line = CTLineCreateWithAttributedString(attributed)
            let bounds = CTLineGetImageBounds(line, context)
            let x = trailing
                ? max(margin, width - margin - Double(bounds.width))
                : margin
            if offset > 0 {
                for dx in [-offset, 0, offset] {
                    for dy in [-offset, 0, offset] where !(dx == 0 && dy == 0) {
                        context.textPosition = CGPoint(x: x + dx, y: baseline + dy)
                        CTLineDraw(line, context)
                    }
                }
            } else {
                context.textPosition = CGPoint(x: x, y: baseline)
                CTLineDraw(line, context)
            }
        }
        context.restoreGState()
    }

    /// Type size as a fraction of the frame, so a 512² CT and a 3000² CR carry
    /// a caption of the same apparent size.
    ///
    /// This is the *one* proportion the caption is set at, on film and in the
    /// preview alike: `PatientIdentificationOverlayView` scales it by the cell
    /// it draws in rather than keeping a second set of numbers. The two used to
    /// disagree — 3.5% of the frame here against 2.3% of the cell there, capped
    /// at 11 pt, so a full-sheet preview set the caption at well under half the
    /// size the film printed it — and a preview whose type is a different size
    /// from the film's is a preview that cannot be used to judge the film.
    public static let heightFraction: Double = 0.035

    /// The width bound, so a wide-and-short frame does not carry a caption
    /// sized for its height. Applied against the *height* fraction, whichever
    /// is smaller.
    public static let widthFraction: Double = 0.030

    /// Never below this, in the pixels of the frame being drawn into: a
    /// caption smaller than this is unreadable at any viewing distance.
    ///
    /// The preview applies its own floor, in points, for the same reason — the
    /// two are floors on different units and neither is the other's business.
    public static let minimumFontSize: Double = 9

    /// The share of the frame's width one corner block is allotted, so the two
    /// blocks along an edge cannot collide. The preview allots the same share
    /// of its cell.
    public static let cornerWidthFraction: Double = 0.48

    /// The floor the block-shrink stops at, as a multiple of the base size:
    /// past this a line is truncated rather than dragging the patient's name
    /// into illegibility with it. Shared with the preview so both step down to
    /// the same size on the same line.
    public static let minimumShrinkFactor: Double = 0.5

    /// The size the caption is set at on a frame of these dimensions.
    public static func captionFontSize(width: Int, height: Int) -> Double {
        captionFontSize(width: width, height: height, singleImageFilm: false)
    }

    /// The automatic size, tapered where the sheet carries a single image.
    ///
    /// See ``PrintAnnotationStyle/singleImageFilm``: the fraction that is right
    /// for a tile is a headline on a whole sheet. The floor is applied after the
    /// taper, so the caption can be made smaller but never unreadable.
    public static func captionFontSize(
        width: Int, height: Int, singleImageFilm: Bool
    ) -> Double {
        let factor = singleImageFilm ? PrintAnnotationStyle.singleImageFactor : 1
        return max(minimumFontSize,
                   min(Double(height) * heightFraction,
                       Double(width) * widthFraction) * factor)
    }

    /// The styled size: the style's own fraction of the frame height when it
    /// sets one (already clamped to the legible range by the style), else the
    /// automatic size. The floor still applies — a fraction of a tiny
    /// thumbnail must not become unreadable type.
    public static func captionFontSize(width: Int, height: Int, style: PrintAnnotationStyle) -> Double {
        guard let fraction = style.resolvedSizeFraction else {
            return captionFontSize(width: width, height: height,
                                   singleImageFilm: style.singleImageFilm)
        }
        return max(minimumFontSize, Double(height) * fraction)
    }

    /// The caption size for a cell, shrunk as one block until the widest line
    /// fits its corner.
    ///
    /// Every line of every corner is set at this one size — the preview does
    /// the same (see `PatientIdentificationOverlayView`), so a long study
    /// description costs the whole block a step of size on screen and on film
    /// alike, instead of shrinking alone and printing the corners in two
    /// sizes. A corner is allotted just under half the frame, the same share
    /// the preview gives it, so the two blocks along an edge cannot collide.
    /// Never below half the base size: past that a line is cut off rather
    /// than dragging the patient's name into illegibility with it.
    public static func fittedCaptionFontSize(
        for corners: PrintCornerAnnotation,
        width: Int, height: Int,
        style: PrintAnnotationStyle = .automatic
    ) -> Double {
        let base = captionFontSize(width: width, height: height, style: style)
        let available = Double(width) * cornerWidthFraction
        guard available > 0 else { return base }
        let font = CTFontCreateWithName(style.fontFamily as CFString, base, nil)
        let widest = corners.allLines.map { line -> Double in
            let attributes: [CFString: Any] = [kCTFontAttributeName: font]
            guard let attributed = CFAttributedStringCreate(
                nil, line as CFString, attributes as CFDictionary) else { return 0 }
            return CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(attributed), nil, nil, nil)
        }.max() ?? 0
        guard widest > available else { return base }
        return base * max(minimumShrinkFactor, available / widest)
    }

    /// How deep a corner block of this many lines is, in pixels — the room the
    /// text takes at the edge it is drawn against.
    public static func captionBlockHeight(lineCount: Int, width: Int, height: Int) -> Double {
        guard lineCount > 0 else { return 0 }
        let fontSize = captionFontSize(width: width, height: height)
        return fontSize * (captionMarginFactor + Double(lineCount) * captionLineFactor)
    }

    // Must match the corner layout: a margin off the edge, then one line box per
    // line, running in towards the middle.
    public static let captionMarginFactor: Double = 0.6
    public static let captionLineFactor: Double = 1.3

    // MARK: - Drawn annotations

    /// The face a reader's own text is set in, wherever it is drawn.
    ///
    /// Bold, unlike the corner caption: the caption states what the picture is
    /// and the reader's text points at something in it, so it is the one piece
    /// of text on a film that is meant to carry emphasis.
    ///
    /// Named here because four renderers draw this same text — the burner for
    /// the film and for the saved/downloaded copy, the viewer's Metal overlay
    /// (which rasterizes through this file), and the print preview's own
    /// SwiftUI layer, which cannot use CoreText and so names the family
    /// itself. A literal in each was a promise kept by hand; this is the one
    /// place to change the face and have every surface follow.
    public static let overlayFontFamily = "Helvetica-Bold"

    /// The size a drawn annotation's text is set at on an image of this height.
    ///
    /// The scale is a fraction of the image's height (see
    /// ``PrintOverlayAnnotation/scale``), so the same annotation reads the same
    /// on a 200-point preview cell and in a 3000-pixel frame. Shared so the
    /// preview and the film apply the same floor as well as the same fraction
    /// — the floors are in different units, points against pixels, but the
    /// arithmetic above them must not differ.
    public static func overlayFontSize(imageHeight: Double, scale: Double) -> Double {
        max(minimumFontSize, imageHeight * scale)
    }

    /// The size a drawn text annotation occupies on an image of this height, in
    /// that image's own pixels — measured with the same face and size the burner
    /// draws with, so a bounding box derived from it states where the words
    /// actually land.
    ///
    /// Used to write the Graphic Annotation Sequence's bounding box (a GSPS text
    /// object requires one) and to hit-test the words on the viewer's overlay.
    /// Zero for empty text: no words, no box.
    public static func overlayTextSize(
        _ text: String, imageHeight: Double, scale: Double
    ) -> CGSize {
        guard !text.isEmpty else { return .zero }
        let fontSize = overlayFontSize(imageHeight: imageHeight, scale: scale)
        let font = CTFontCreateWithName(overlayFontFamily as CFString, fontSize, nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font]
        guard let attributed = CFAttributedStringCreate(
            nil, text as CFString, attributes as CFDictionary) else {
            return CGSize(width: fontSize * 0.6 * Double(text.count), height: fontSize)
        }
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return CGSize(width: width, height: Double(ascent + descent))
    }

    /// A line of the reader's own text, at the point they put it.
    ///
    /// The anchor is the text's top-left, which is where a caret sits when you
    /// click — a baseline anchor would make text appear above the click.
    ///
    /// - Parameters:
    ///   - orientation: the arrangement the picture is in, so the words can be
    ///     turned back level. `nil` leaves them as they always were.
    ///   - uprightOnly: cancel the arrangement's effect on the *lettering* but
    ///     leave the anchor in image space. What the viewer's overlay texture
    ///     wants: its shader will move the anchor itself, and moving it here as
    ///     well would move it twice.
    private static func drawText(
        _ overlay: PrintOverlayAnnotation,
        in canvas: Canvas,
        orientation: PrintOverlayOrientation? = nil,
        uprightOnly: Bool = false
    ) {
        let fontSize = overlayFontSize(imageHeight: Double(canvas.height), scale: overlay.scale)
        let font = CTFontCreateWithName(overlayFontFamily as CFString, fontSize, nil)
        let anchor = uprightOnly
            ? (x: overlay.start.x, y: overlay.start.y)
            : (orientation?.point(overlay.start) ?? (x: overlay.start.x, y: overlay.start.y))
        let x = anchor.x * Double(canvas.width)
        // Fractions run top-down, a bitmap context runs bottom-up, and the anchor
        // is the top of the type — so the baseline sits one ascent lower.
        let ascent = CTFontGetAscent(font)
        let y = Double(canvas.height) * (1 - anchor.y) - ascent

        canvas.context.saveGState()

        // Turn the type back level, about the anchor, so the words read
        // left-to-right and right way up however the picture beneath them has
        // been turned or mirrored. A reader's note is *about* the anatomy, not
        // part of it, and there is no film on which mirror-written text is the
        // correct rendering. Done as a context transform rather than a text
        // matrix so the halo passes below, which offset in context units, turn
        // with it.
        //
        // The angle's sign is the context's, not the screen's: a bitmap context
        // runs bottom-up, so a clockwise screen turn is a positive rotation
        // here. And the mirror is undone before the turn, because the
        // arrangement mirrors *after* turning — undoing a composition means
        // undoing it from the outside in.
        if let orientation, !orientation.isIdentity {
            canvas.context.translateBy(x: x, y: y)
            // The mirror is undone on the axis the arrangement actually
            // mirrored. Always negating x was right for a horizontal flip and
            // wrong for a vertical one, where it turned the glyph into its own
            // 180° rotation instead of its reflection.
            if orientation.textIsMirrored {
                if orientation.presentation.flipVertical {
                    canvas.context.scaleBy(x: 1, y: -1)
                } else {
                    canvas.context.scaleBy(x: -1, y: 1)
                }
            }
            // Negated: `textAngleDegrees` is stated in screen terms — clockwise
            // as the reader sees it — while this bitmap context runs bottom-up,
            // so the same turn is the opposite sign here. Applied unnegated, a
            // quarter-turned picture had its words laid on the wrong side.
            canvas.context.rotate(by: -orientation.textAngleDegrees * .pi / 180)
            canvas.context.translateBy(x: -x, y: -y)
        }
        canvas.context.textMatrix = .identity
        // Drawn twice: a halo, then the text, so it survives both a black
        // background and a white lung field.
        let halo = canvas.halo(for: overlay.color)
        let offset = max(1.0, fontSize * 0.06)
        for (spread, color) in [(offset, halo), (0.0, canvas.color(for: overlay.color))] {
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: color
            ]
            guard let attributed = CFAttributedStringCreate(
                nil, overlay.text as CFString, attributes as CFDictionary) else { continue }
            let line = CTLineCreateWithAttributedString(attributed)
            if spread > 0 {
                for dx in [-spread, 0, spread] {
                    for dy in [-spread, 0, spread] where !(dx == 0 && dy == 0) {
                        canvas.context.textPosition = CGPoint(x: x + dx, y: y + dy)
                        CTLineDraw(line, canvas.context)
                    }
                }
            } else {
                canvas.context.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(line, canvas.context)
            }
        }
        canvas.context.restoreGState()
    }

    /// A combined annotation: the words at their anchor, and an arrow from the
    /// label's border to the point it names.
    ///
    /// The arrow's tail is clipped to the label box (see
    /// ``PrintAnnotationLayout``), so the shaft comes *from* the words without
    /// crossing them — and is left out entirely when the anchor sits under the
    /// label, where an arrow would only point at its own caption. Either half
    /// alone is legal: words with no arrow burn as text, an arrow with no words
    /// burns as an arrow.
    private static func drawCombined(
        _ overlay: PrintOverlayAnnotation,
        in canvas: Canvas,
        orientation: PrintOverlayOrientation? = nil,
        uprightOnly: Bool = false
    ) {
        if overlay.hasWords {
            drawText(overlay, in: canvas,
                     orientation: orientation, uprightOnly: uprightOnly)
        }
        guard let tail = PrintAnnotationLayout.leaderTail(
            for: overlay,
            imageWidth: Double(canvas.width),
            imageHeight: Double(canvas.height)) else { return }
        var arrow = overlay
        arrow.start = tail
        // The viewer's overlay leaves arrows unmapped — its shader turns them
        // with the picture — while a film burn maps both ends. Same rule the
        // plain arrow kind follows in the two callers above.
        drawArrow(arrow, in: canvas, orientation: uprightOnly ? nil : orientation)
    }

    /// A straight arrow from tail to head, with a filled head.
    ///
    /// Drawn with a halo underneath for the same reason the text is: an arrow that
    /// crosses from lung into mediastinum has to stay visible in both.
    ///
    /// Unlike text, an arrow is not turned back: it points at anatomy, and
    /// anatomy that has been turned needs the arrow turned with it. Only the
    /// two ends are mapped, and only for the burn — the viewer's shader turns
    /// the whole overlay itself.
    private static func drawArrow(
        _ overlay: PrintOverlayAnnotation,
        in canvas: Canvas,
        orientation: PrintOverlayOrientation? = nil
    ) {
        let tail = pixelPoint(overlay.start, in: canvas, orientation: orientation)
        let head = pixelPoint(overlay.end, in: canvas, orientation: orientation)
        let dx = head.x - tail.x
        let dy = head.y - tail.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return }

        // Line weight and head size come off the same control as the type size, so
        // one setting makes an annotation heavier or lighter as a whole — and off
        // the shared geometry, so the film matches the preview that was approved.
        let geometry = PrintArrowGeometry(
            scale: overlay.scale, imageHeight: Double(canvas.height), arrowLength: length)
        guard let outline = geometry.outline(
            tail: PrintPlanePoint(x: tail.x, y: tail.y),
            head: PrintPlanePoint(x: head.x, y: head.y)) else { return }

        let shaftEnd = cgPoint(outline.shaftEnd)
        let left = cgPoint(outline.headLeft)
        let right = cgPoint(outline.headRight)

        canvas.context.saveGState()
        canvas.context.setLineCap(.round)
        canvas.context.setLineJoin(.round)

        for (extra, color) in [(geometry.haloWidth, canvas.halo(for: overlay.color)),
                               (0.0, canvas.color(for: overlay.color))] {
            canvas.context.setStrokeColor(color)
            canvas.context.setFillColor(color)
            canvas.context.setLineWidth(geometry.lineWidth + extra)

            canvas.context.beginPath()
            canvas.context.move(to: tail)
            canvas.context.addLine(to: shaftEnd)
            canvas.context.strokePath()

            canvas.context.beginPath()
            canvas.context.move(to: head)
            canvas.context.addLine(to: left)
            canvas.context.addLine(to: right)
            canvas.context.closePath()
            // The halo pass strokes the head outline as well as filling it, which
            // is what widens it into a halo.
            canvas.context.drawPath(using: extra > 0 ? .fillStroke : .fill)
        }
        canvas.context.restoreGState()
    }

    private static func cgPoint(_ point: PrintPlanePoint) -> CGPoint {
        CGPoint(x: point.x, y: point.y)
    }

    // MARK: - Shapes from a presentation state

    /// The stroke a shape is drawn with: the arrow's line weight for the same
    /// `scale`, so a ruler and an arrow on one image read as one hand.
    public static func shapeLineWidths(scale: Double, imageHeight: Double)
        -> (line: Double, halo: Double)
    {
        let geometry = PrintArrowGeometry(
            scale: scale, imageHeight: imageHeight, arrowLength: imageHeight)
        return (geometry.lineWidth, geometry.haloWidth)
    }

    /// The path of a shape kind, in the context's bottom-up pixel coordinates.
    ///
    /// Every vertex goes through the arrangement first, the way an arrow's
    /// ends do: a circle drawn on a picture that was then turned a quarter is
    /// still a circle around the same anatomy. An ellipse is rebuilt from its
    /// mapped axes rather than mapped point by point, which keeps it an
    /// ellipse under a quarter turn or a mirror (the only arrangements a film
    /// cell applies to it besides a uniform crop).
    static func shapePath(
        _ overlay: PrintOverlayAnnotation,
        width: Int, height: Int,
        orientation: PrintOverlayOrientation? = nil
    ) -> CGPath? {
        func pixel(_ point: PrintOverlayPoint) -> CGPoint {
            let mapped = orientation?.point(point) ?? (x: point.x, y: point.y)
            return CGPoint(x: mapped.x * Double(width),
                           y: Double(height) * (1 - mapped.y))
        }
        let points = overlay.points.map(pixel)
        let path = CGMutablePath()

        switch overlay.kind {
        case .polyline:
            guard points.count >= 2 else { return nil }
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            if overlay.filled { path.closeSubpath() }

        case .circle:
            guard points.count >= 2 else { return nil }
            let centre = points[0]
            let radius = hypot(points[1].x - centre.x, points[1].y - centre.y)
            guard radius > 0 else { return nil }
            path.addEllipse(in: CGRect(
                x: centre.x - radius, y: centre.y - radius,
                width: radius * 2, height: radius * 2))

        case .ellipse:
            guard points.count >= 4 else { return nil }
            let centre = CGPoint(x: (points[0].x + points[1].x) / 2,
                                 y: (points[0].y + points[1].y) / 2)
            let semiMajor = hypot(points[1].x - points[0].x, points[1].y - points[0].y) / 2
            let semiMinor = hypot(points[3].x - points[2].x, points[3].y - points[2].y) / 2
            guard semiMajor > 0, semiMinor > 0 else { return nil }
            let angle = atan2(points[1].y - points[0].y, points[1].x - points[0].x)
            let transform = CGAffineTransform(translationX: centre.x, y: centre.y)
                .rotated(by: angle)
            path.addEllipse(
                in: CGRect(x: -semiMajor, y: -semiMinor,
                           width: semiMajor * 2, height: semiMinor * 2),
                transform: transform)

        case .point:
            guard let centre = points.first else { return nil }
            // A cross the size of the type, so a marked point is findable on
            // film without hiding what it marks.
            let arm = max(3, overlayFontSize(
                imageHeight: Double(height), scale: overlay.scale) * 0.5)
            path.move(to: CGPoint(x: centre.x - arm, y: centre.y))
            path.addLine(to: CGPoint(x: centre.x + arm, y: centre.y))
            path.move(to: CGPoint(x: centre.x, y: centre.y - arm))
            path.addLine(to: CGPoint(x: centre.x, y: centre.y + arm))

        case .shutter:
            // The open region — what `drawShutter` paints *around*.
            guard points.count >= 2 else { return nil }
            if points.count == 2 {
                // Two points are a rectangle's corners unless the reader of the
                // state said circle; `filled` carries that distinction.
                if overlay.filled {
                    let centre = points[0]
                    let radius = hypot(points[1].x - centre.x, points[1].y - centre.y)
                    guard radius > 0 else { return nil }
                    path.addEllipse(in: CGRect(
                        x: centre.x - radius, y: centre.y - radius,
                        width: radius * 2, height: radius * 2))
                } else {
                    path.addRect(CGRect(
                        x: min(points[0].x, points[1].x),
                        y: min(points[0].y, points[1].y),
                        width: abs(points[1].x - points[0].x),
                        height: abs(points[1].y - points[0].y)))
                }
            } else {
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
            }

        case .text, .arrow, .annotation:
            return nil
        }
        return path
    }

    /// A ruler, an angle, a polygon, an ROI — stroked (or filled) with a halo
    /// underneath, the way an arrow is, so it survives whatever it crosses.
    private static func drawShape(
        _ overlay: PrintOverlayAnnotation,
        in canvas: Canvas,
        orientation: PrintOverlayOrientation? = nil
    ) {
        guard let path = shapePath(
            overlay, width: canvas.width, height: canvas.height,
            orientation: orientation) else { return }
        let widths = shapeLineWidths(scale: overlay.scale, imageHeight: Double(canvas.height))

        canvas.context.saveGState()
        canvas.context.setLineCap(.round)
        canvas.context.setLineJoin(.round)
        for (extra, color) in [(widths.halo, canvas.halo(for: overlay.color)),
                               (0.0, canvas.color(for: overlay.color))] {
            canvas.context.setStrokeColor(color)
            canvas.context.setFillColor(color)
            canvas.context.setLineWidth(widths.line + extra)
            canvas.context.addPath(path)
            // Outline only, filled or not: a viewer fills an ROI translucently,
            // and film has no alpha — a solid fill would hide the anatomy the
            // ROI was drawn to measure. `filled` still closes the path.
            canvas.context.strokePath()
        }
        canvas.context.restoreGState()
    }

    /// Paints the shutter's presentation value everywhere outside its shape.
    ///
    /// Even-odd fill of the whole frame minus the open region: one pass, no
    /// per-pixel test, and the same rule whether the shape is a rectangle, a
    /// circle or a polygon.
    private static func drawShutter(
        _ overlay: PrintOverlayAnnotation,
        in canvas: Canvas,
        orientation: PrintOverlayOrientation? = nil
    ) {
        guard let open = shapePath(
            overlay, width: canvas.width, height: canvas.height,
            orientation: orientation) else { return }
        let mask = CGMutablePath()
        mask.addRect(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        mask.addPath(open)

        canvas.context.saveGState()
        canvas.context.setFillColor(canvas.color(for: overlay.color))
        canvas.context.addPath(mask)
        canvas.context.fillPath(using: .evenOdd)
        canvas.context.restoreGState()
    }

    /// A normalized point in the context's own coordinates, which run bottom-up.
    private static func pixelPoint(
        _ point: PrintOverlayPoint,
        in canvas: Canvas,
        orientation: PrintOverlayOrientation? = nil
    ) -> CGPoint {
        let mapped = orientation?.point(point) ?? (x: point.x, y: point.y)
        return CGPoint(x: mapped.x * Double(canvas.width),
                       y: Double(canvas.height) * (1 - mapped.y))
    }
}
#endif
