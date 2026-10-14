import Foundation
#if canImport(CoreGraphics) && canImport(CoreText)
import CoreGraphics
import CoreText
#endif

/// Rasterizes the `label` redaction style: a fixed stamp (default `REDACTED`) drawn
/// **into an already-blanked region** so a reviewer sees "cleaned deliberately", not a
/// suspected rendering bug.
///
/// The output is a glyph coverage mask, not pixels: ``PixelEditor`` maps it onto the
/// image's real bit depth (foreground = the stored value farthest from the fill). The
/// text is fitted to the box, deliberately not imitating the device's font, so output
/// never masquerades as original acquisition rendering.
public enum RedactionLabelRenderer {

    /// Default stamp text.
    public static let defaultLabel = "REDACTED"

    /// Smallest box a stamp is drawn into. Below this the glyphs are illegible, and
    /// the caller falls back to plain blanking **with an audit note** — never silently.
    public static let minimumHeight = 8
    public static let minimumWidthPerCharacter = 4

    /// True when the box can carry a legible stamp for `text`.
    public static func fits(text: String, width: Int, height: Int) -> Bool {
        guard !text.isEmpty else { return false }
        return height >= minimumHeight && width >= text.count * minimumWidthPerCharacter
    }

    /// True when glyph rasterization is available in this build.
    public static var isAvailable: Bool {
        #if canImport(CoreGraphics) && canImport(CoreText)
        return true
        #else
        return false
        #endif
    }

    /// Renders `text` centred in a `width × height` box as a row-major 8-bit coverage
    /// mask (255 = ink), top-left origin. Returns `nil` when the box is too small or
    /// rasterization is unavailable.
    public static func glyphMask(text: String, width: Int, height: Int) -> Data? {
        guard fits(text: text, width: width, height: height) else { return nil }
        #if canImport(CoreGraphics) && canImport(CoreText)
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setShouldAntialias(true)

        // Fit: start from the box height and shrink until the line fits with a margin.
        let margin = max(1.0, Double(min(width, height)) * 0.1)
        var pointSize = Double(height) - 2 * margin
        var line: CTLine?
        var bounds = CGRect.zero
        while pointSize >= 4 {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, CGFloat(pointSize), nil)
            let attributed = NSAttributedString(string: text, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1),
            ])
            let candidate = CTLineCreateWithAttributedString(attributed)
            let b = CTLineGetBoundsWithOptions(candidate, .useGlyphPathBounds)
            if b.width <= Double(width) - 2 * margin && b.height <= Double(height) - 2 * margin {
                line = candidate
                bounds = b
                break
            }
            pointSize -= 1
        }
        guard let line else { return nil }

        // Centre the glyph box; CG origin is bottom-left.
        let x = (CGFloat(width) - bounds.width) / 2 - bounds.minX
        let y = (CGFloat(height) - bounds.height) / 2 - bounds.minY
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)

        guard let raw = ctx.data else { return nil }
        // A CGBitmapContext stores row 0 of memory as the visual TOP row (the context's
        // bottom-left origin is handled by the CTM), so the buffer is already in the
        // DICOM top-left row order — copy it straight through.
        let mask = Data(bytes: raw, count: width * height)
        // Ensure the mask really carries ink; an empty render is a failure, not a stamp.
        guard mask.contains(where: { $0 > 127 }) else { return nil }
        return mask
        #else
        return nil
        #endif
    }
}
