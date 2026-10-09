// NEMA-verified: 2026a, checked 2026-09-29 — 60xx overlay attributes and VRs match PS3.6 2026a Table 6-1; the PS3.3 C.9 multi-frame overlay rule is recorded
// OverlayPlaneRenderer.swift
// DICOMKit
//
// Overlay planes (PS3.3 C.9.2, groups 60xx) — the bitmap layer a modality draws
// *over* the image rather than into it.
//
// Scanners use this for things that are not measurements: burned-in graphics,
// ROI outlines, and — the case this was written for — Siemens' "Patient
// Protocol" Secondary Capture, whose Pixel Data is entirely zero and whose whole
// content is a 1-bit overlay bitmap. Rendering only Pixel Data shows a black
// square and loses the page; the overlay has to be drawn on top.

import Foundation
import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One overlay plane of a data set: a 1-bit bitmap and where it sits on the
/// image.
///
/// Only planes carrying their own Overlay Data (60xx,3000) are represented.
/// Overlays packed into the unused high bits of Pixel Data were retired in 2004
/// and are not reconstructed here — see ``OverlayPlaneRenderer/planes(in:)``.
public struct OverlayPlane: Sendable, Equatable {

    /// The plane's group number (0x6000, 0x6002, … 0x601E).
    public let group: UInt16

    /// Overlay Rows (60xx,0010) and Overlay Columns (60xx,0011).
    public let rows: Int
    public let columns: Int

    /// Overlay Origin (60xx,0050), as stored: 1-based, row then column, and
    /// signed — a plane may legitimately start above or left of the image.
    public let originRow: Int
    public let originColumn: Int

    /// Number of Frames in Overlay (60xx,0015); 1 when absent.
    public let frameCount: Int

    /// Image Frame Origin (60xx,0051): the 1-based image frame the plane's first
    /// frame applies to. 1 when absent.
    public let imageFrameOrigin: Int

    /// Overlay Type (60xx,0040): `G` for graphics, `R` for an ROI.
    public let type: String

    /// Overlay Description (60xx,0022), if the plane names itself.
    public let label: String?

    /// Overlay Data (60xx,3000): rows × columns bits, packed little-endian —
    /// within a byte the least significant bit is the leftmost pixel — running
    /// continuously across rows and frames without padding between them.
    public let bits: Data

    public init(
        group: UInt16, rows: Int, columns: Int,
        originRow: Int, originColumn: Int,
        frameCount: Int, imageFrameOrigin: Int,
        type: String, label: String?, bits: Data
    ) {
        self.group = group
        self.rows = rows
        self.columns = columns
        self.originRow = originRow
        self.originColumn = originColumn
        self.frameCount = frameCount
        self.imageFrameOrigin = imageFrameOrigin
        self.type = type
        self.label = label
        self.bits = bits
    }

    /// Whether this plane has anything to draw over the given image frame.
    ///
    /// A single-frame overlay applies to every frame of the image: that is what
    /// scanners mean by it, and the alternative — showing it on frame 0 only —
    /// makes a graphic blink as the user scrolls.
    public func applies(toImageFrame frameIndex: Int) -> Bool {
        guard !bits.isEmpty, rows > 0, columns > 0 else { return false }
        if frameCount <= 1 { return true }
        let first = imageFrameOrigin - 1
        return frameIndex >= first && frameIndex < first + frameCount
    }

    /// Which frame of the overlay covers the given image frame.
    func overlayFrame(forImageFrame frameIndex: Int) -> Int {
        frameCount <= 1 ? 0 : max(0, frameIndex - (imageFrameOrigin - 1))
    }

    /// Whether the bit at `row`/`column` of the given overlay frame is set.
    public func isSet(row: Int, column: Int, frame: Int = 0) -> Bool {
        guard row >= 0, row < rows, column >= 0, column < columns else { return false }
        let index = (frame * rows * columns) + (row * columns) + column
        let byte = index / 8
        guard byte >= 0, byte < bits.count else { return false }
        return (bits[bits.startIndex + byte] >> UInt8(index % 8)) & 1 == 1
    }
}

/// Reads a data set's overlay planes and draws them over a rendered frame.
public enum OverlayPlaneRenderer {

    /// Every overlay plane the data set carries its own bitmap for, in group
    /// order.
    ///
    /// Groups run 0x6000 to 0x601E, even numbers only — sixteen possible planes.
    /// A plane whose Overlay Bits Allocated (60xx,0100) is not 1 is an *embedded*
    /// overlay: its bits live in the high bits of Pixel Data, a construct retired
    /// from the standard in 2004 and one this renderer cannot reach, because by
    /// the time it has a `CGImage` the pixels have already been windowed down to
    /// 8 bits. Those planes are skipped rather than drawn wrongly.
    public static func planes(in dataSet: DataSet) -> [OverlayPlane] {
        var found: [OverlayPlane] = []
        for group in stride(from: UInt16(0x6000), through: UInt16(0x601E), by: 2) {
            guard let plane = plane(inGroup: group, of: dataSet) else { continue }
            found.append(plane)
        }
        return found
    }

    /// The plane of one group, if it is present and drawable.
    public static func plane(inGroup group: UInt16, of dataSet: DataSet) -> OverlayPlane? {
        func tag(_ element: UInt16) -> Tag { Tag(group: group, element: element) }

        guard let data = dataSet[tag(0x3000)]?.valueData, !data.isEmpty,
              let rows = dataSet.uint16(for: tag(0x0010)).map({ Int($0) }), rows > 0,
              let columns = dataSet.uint16(for: tag(0x0011)).map({ Int($0) }), columns > 0
        else { return nil }

        // Bits Allocated is Type 1, but a plane that omits it and carries its own
        // data can only be a 1-bit one — the embedded form has no (60xx,3000).
        let bitsAllocated = dataSet.uint16(for: tag(0x0100)).map { Int($0) } ?? 1
        guard bitsAllocated == 1 else { return nil }

        // The bitmap has to be big enough for one frame, or it is truncated and
        // drawing it would paint garbage across the image.
        guard data.count * 8 >= rows * columns else { return nil }

        let origin = dataSet[tag(0x0050)]?.int16Values ?? []
        let frameCount = dataSet.integerString(for: tag(0x0015)).map { Int($0.value) } ?? 1
        let frameOrigin = dataSet.uint16(for: tag(0x0051)).map { Int($0) } ?? 1

        return OverlayPlane(
            group: group,
            rows: rows,
            columns: columns,
            originRow: origin.count > 0 ? Int(origin[0]) : 1,
            originColumn: origin.count > 1 ? Int(origin[1]) : 1,
            frameCount: max(1, frameCount),
            imageFrameOrigin: max(1, frameOrigin),
            type: dataSet.string(for: tag(0x0040))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "G",
            label: dataSet.string(for: tag(0x0022))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            bits: data
        )
    }

    /// Whether the data set has any overlay to draw over the given frame.
    ///
    /// Cheap enough to ask before rendering, so files without overlays — nearly
    /// all of them — pay nothing but a handful of dictionary lookups.
    public static func hasOverlay(_ dataSet: DataSet, forFrame frameIndex: Int = 0) -> Bool {
        planes(in: dataSet).contains { $0.applies(toImageFrame: frameIndex) }
    }

    // MARK: - Burning into samples

    /// Draws the data set's overlay planes into a preprocessed frame's samples.
    ///
    /// The pixel-buffer counterpart of ``burningOverlays(of:onto:frameIndex:color:)``,
    /// for the print path — which never builds a `CGImage`, and which must put on
    /// film what the preview showed. Returns the samples unchanged when there is
    /// nothing to draw or the buffer is not the size it claims to be.
    ///
    /// The overlay is drawn in the brightest value the buffer can hold, except on
    /// MONOCHROME1 where zero is white.
    public static func burningOverlays(
        of dataSet: DataSet,
        into samples: Data,
        width: Int,
        height: Int,
        bitsAllocated: Int,
        bitsStored: Int,
        samplesPerPixel: Int,
        photometricInterpretation: String,
        frameIndex: Int = 0
    ) -> Data {
        let drawable = planes(in: dataSet).filter { $0.applies(toImageFrame: frameIndex) }
        guard !drawable.isEmpty, width > 0, height > 0,
              samplesPerPixel >= 1, bitsAllocated == 8 || bitsAllocated == 16
        else { return samples }

        let bytesPerSample = bitsAllocated / 8
        let bytesPerPixel = bytesPerSample * samplesPerPixel
        guard samples.count >= width * height * bytesPerPixel else { return samples }

        let isInverted = photometricInterpretation
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "MONOCHROME1"
        let maximum = bitsStored > 0 && bitsStored <= bitsAllocated
            ? (1 << bitsStored) - 1
            : (1 << bitsAllocated) - 1
        let value = isInverted ? 0 : maximum

        var output = [UInt8](samples)
        for plane in drawable {
            let frame = plane.overlayFrame(forImageFrame: frameIndex)
            // Overlay Origin is 1-based in the image matrix.
            let rowOffset = plane.originRow - 1
            let columnOffset = plane.originColumn - 1

            for row in 0..<plane.rows {
                let imageRow = row + rowOffset
                guard imageRow >= 0, imageRow < height else { continue }
                for column in 0..<plane.columns
                where plane.isSet(row: row, column: column, frame: frame) {
                    let imageColumn = column + columnOffset
                    guard imageColumn >= 0, imageColumn < width else { continue }
                    let pixel = (imageRow * width + imageColumn) * bytesPerPixel
                    for sample in 0..<samplesPerPixel {
                        let offset = pixel + sample * bytesPerSample
                        if bytesPerSample == 1 {
                            output[offset] = UInt8(value & 0xFF)
                        } else {
                            // Little-endian, the byte order Basic Print sends.
                            output[offset] = UInt8(value & 0xFF)
                            output[offset + 1] = UInt8((value >> 8) & 0xFF)
                        }
                    }
                }
            }
        }
        return Data(output)
    }

    #if canImport(CoreGraphics)

    /// Draws the data set's overlay planes over a rendered frame.
    ///
    /// Returns the image unchanged when there is nothing to draw, so this can sit
    /// in every render path without a caller-side test.
    ///
    /// The planes are drawn in the image's own pixel grid: an overlay is defined
    /// against the *image* matrix, so a 512×512 plane belongs on a 512×512 frame
    /// whatever size it is displayed at. When the frame has been scaled — a
    /// thumbnail, a downscaled tile — the plane is scaled with it, which keeps
    /// hairline graphics visible instead of dropping them between sample points.
    public static func burningOverlays(
        of dataSet: DataSet,
        onto image: CGImage,
        frameIndex: Int = 0,
        color: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    ) -> CGImage {
        let drawable = planes(in: dataSet).filter { $0.applies(toImageFrame: frameIndex) }
        guard !drawable.isEmpty else { return image }
        return burn(drawable, onto: image, frameIndex: frameIndex, color: color) ?? image
    }

    /// Draws the given planes over a frame.
    public static func burn(
        _ planes: [OverlayPlane],
        onto image: CGImage,
        frameIndex: Int = 0,
        color: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    ) -> CGImage? {
        guard !planes.isEmpty else { return image }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return image }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        for plane in planes {
            guard let layer = layer(for: plane, frameIndex: frameIndex, color: color)
            else { continue }

            // Overlay Origin is 1-based in the image matrix, so (1,1) is the
            // image's own top-left corner and needs no offset.
            let left = Double(plane.originColumn - 1)
            let top = Double(plane.originRow - 1)

            // The plane is sized against the image's full pixel matrix; if the
            // rendered frame has been scaled, the plane scales by the same
            // factor so it still lands over the pixels it describes.
            let scaleX = Double(width) / Double(max(plane.columns, 1))
            let scaleY = Double(height) / Double(max(plane.rows, 1))
            let scale = min(scaleX, scaleY)
            let drawWidth = Double(plane.columns) * scale
            let drawHeight = Double(plane.rows) * scale

            // CoreGraphics draws from the bottom-left; the overlay's rows run
            // from the top, like the image's.
            let rect = CGRect(
                x: left * scale,
                y: Double(height) - (top * scale) - drawHeight,
                width: drawWidth,
                height: drawHeight)

            context.draw(layer, in: rect)
        }

        return context.makeImage() ?? image
    }

    /// A one-bit plane as a transparent RGBA layer: the overlay colour where the
    /// bit is set, nothing at all where it is not.
    ///
    /// Drawn as an ordinary image rather than clipped through a `CGImage` mask —
    /// mask polarity is the kind of detail that silently paints the whole frame
    /// white when it is read the wrong way round, and an alpha layer says what it
    /// means. Premultiplied, so the colour is stored already scaled by alpha and
    /// the transparent pixels are all-zero bytes.
    private static func layer(
        for plane: OverlayPlane,
        frameIndex: Int,
        color: CGColor
    ) -> CGImage? {
        let frame = plane.overlayFrame(forImageFrame: frameIndex)
        let width = plane.columns
        let height = plane.rows
        let components = color.components ?? [1, 1, 1, 1]
        let alpha = UInt8(max(0, min(1, color.alpha)) * 255)
        func channel(_ index: Int) -> UInt8 {
            let value = components.count > index ? components[index] : 1
            return UInt8(max(0, min(1, value)) * Double(alpha))
        }
        let red = channel(0)
        let green = components.count >= 3 ? channel(1) : red
        let blue = components.count >= 3 ? channel(2) : red

        var samples = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let rowStart = row * width
            for column in 0..<width where plane.isSet(row: row, column: column, frame: frame) {
                let offset = (rowStart + column) * 4
                samples[offset] = red
                samples[offset + 1] = green
                samples[offset + 2] = blue
                samples[offset + 3] = alpha
            }
        }

        guard let provider = CGDataProvider(data: Data(samples) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
    }

    #endif
}
