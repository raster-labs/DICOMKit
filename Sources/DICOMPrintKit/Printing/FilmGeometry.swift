// NEMA-verified: 2026a, checked 2026-09-29 — sheet size of all 12 Film Size ID terms diffed against PS3.3 2026a Table C.13-3 (10INX14IN corrected to 257 x 364 mm as the table states); Image Display Format layouts and COL column-major numbering per C.13.3 and C.13.5.1; CROP without a size read as filling the box (P-CROP, PRINT_CONFORMANCE.md 3.5)
//
// FilmGeometry.swift
// DICOMPrintKit
//
// Physical film geometry: sheet size in millimetres for every Film Size ID, and
// the cell rectangles an Image Display Format lays out on that sheet.
//
// Deliberately free of CoreGraphics so the layout maths is testable anywhere
// and independent of the rasterizer that consumes it.
//
// Reference: PS3.3 C.13.3 (Basic Film Box Presentation Module): Film Size ID
// (2010,0050) and Image Display Format (2010,0010) are both defined there.
//

import Foundation
import DICOMNetwork

// MARK: - Sheet

/// The physical sheet a film is printed on.
public struct FilmSheet: Sendable, Equatable {
    /// Sheet width in millimetres, after orientation is applied.
    public let widthMillimeters: Double

    /// Sheet height in millimetres, after orientation is applied.
    public let heightMillimeters: Double

    /// Rasterization resolution in dots per inch.
    public let dpi: Double

    public init(widthMillimeters: Double, heightMillimeters: Double, dpi: Double) {
        self.widthMillimeters = max(1, widthMillimeters)
        self.heightMillimeters = max(1, heightMillimeters)
        self.dpi = max(1, dpi)
    }

    /// The sheet for a Film Size ID in the given orientation.
    public init(filmSize: FilmSize, orientation: FilmOrientation, dpi: Double) {
        let portrait = FilmSheet.portraitSizeMillimeters(for: filmSize)
        switch orientation {
        case .portrait:
            self.init(widthMillimeters: portrait.width, heightMillimeters: portrait.height, dpi: dpi)
        case .landscape:
            self.init(widthMillimeters: portrait.height, heightMillimeters: portrait.width, dpi: dpi)
        }
    }

    /// Pixels per millimetre at this resolution.
    public var pixelsPerMillimeter: Double { dpi / 25.4 }

    /// Sheet width in pixels.
    public var pixelWidth: Int { Int((widthMillimeters * pixelsPerMillimeter).rounded()) }

    /// Sheet height in pixels.
    public var pixelHeight: Int { Int((heightMillimeters * pixelsPerMillimeter).rounded()) }

    /// Converts millimetres to pixels at this resolution.
    public func pixels(fromMillimeters millimeters: Double) -> Double {
        millimeters * pixelsPerMillimeter
    }

    /// The nominal portrait size of a Film Size ID, in millimetres.
    ///
    /// Imperial sizes are the exact inch conversions (1 in = 25.4 mm) and the
    /// metric and ISO sizes their stated dimensions — except 10INX14IN, which
    /// PS3.3 Table C.13-3 says "corresponds with 25.7CMX36.4CM" (the JIS B4
    /// sheet sold as 10×14), not 254 × 355.6 mm. A4 (210 × 297) and A3
    /// (297 × 420) are as the same row states them.
    public static func portraitSizeMillimeters(for filmSize: FilmSize) -> (width: Double, height: Double) {
        func inches(_ w: Double, _ h: Double) -> (Double, Double) { (w * 25.4, h * 25.4) }
        switch filmSize {
        case .size8InX10In:    return inches(8, 10)
        case .size8_5InX11In:  return inches(8.5, 11)
        case .size10InX12In:   return inches(10, 12)
        case .size10InX14In:   return (257, 364)
        case .size11InX14In:   return inches(11, 14)
        case .size11InX17In:   return inches(11, 17)
        case .size14InX14In:   return inches(14, 14)
        case .size14InX17In:   return inches(14, 17)
        case .size24CmX24Cm:   return (240, 240)
        case .size24CmX30Cm:   return (240, 300)
        case .a4:              return (210, 297)
        case .a3:              return (297, 420)
        }
    }
}

// MARK: - Cells

/// One image-box cell on a film sheet, in pixels, origin top-left.
public struct FilmCell: Sendable, Equatable {
    /// The 1-based Image Box Position this cell belongs to.
    public let position: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(position: Int, x: Double, y: Double, width: Double, height: Double) {
        self.position = position
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Whether the cell has a drawable area.
    public var isEmpty: Bool { width <= 0 || height <= 0 }
}

/// Which edge of the sheet a film-wide annotation band occupies.
///
/// SRS FR-006 names header, footer, side and overlay positions. The band is
/// carved out of the picture area on the named edge; `.overlay` reserves
/// nothing and the text is drawn over the pictures instead.
public enum FilmAnnotationEdge: String, CaseIterable, Sendable, Codable {
    /// A strip along the bottom — the footer, and the default.
    case bottom
    /// A strip along the top — the header.
    case top
    /// A strip along the left edge; the text runs top-to-bottom (spine-wise).
    case left
    /// A strip along the right edge; the text runs bottom-to-top.
    case right
    /// No strip: the text is drawn over the bottom of the pictures.
    case overlay

    /// Menu title.
    public var title: String {
        switch self {
        case .bottom:  return "Footer"
        case .top:     return "Header"
        case .left:    return "Left edge"
        case .right:   return "Right edge"
        case .overlay: return "Over the images"
        }
    }
}

/// Lays out the cells an Image Display Format defines on a sheet.
public enum FilmCellLayout {

    /// Computes cell rectangles in pixels, in Image Box Position order.
    ///
    /// - `STANDARD\C,R` — a uniform grid filled left-to-right, top-to-bottom.
    /// - `ROW\c1,c2,…`  — one band per row; each band's cells share the full width.
    /// - `COL\r1,r2,…`  — one band per column; each band's cells share the full height.
    /// - `SLIDE` / `SUPERSLIDE` / `CUSTOM\i` — a single cell filling the sheet.
    ///
    /// - Parameters:
    ///   - format: the parsed Image Display Format.
    ///   - sheet: the film sheet.
    ///   - margin: sheet margin in millimetres, applied on all four edges.
    ///   - spacing: gap between adjacent cells in millimetres.
    ///   - footer: a strip in millimetres kept clear along `edge`, inside the
    ///     margin, for film-wide text. The cells are laid out in what is left,
    ///     so the band never lands on an edge row's anatomy. (The parameter
    ///     keeps its historical name from when the bottom was the only edge.)
    ///   - edge: which edge the strip comes off. `.overlay` reserves nothing.
    public static func cells(
        for format: PrintImageDisplayFormat,
        on sheet: FilmSheet,
        marginMillimeters margin: Double = 5,
        spacingMillimeters spacing: Double = 2,
        footerMillimeters footer: Double = 0,
        annotationEdge edge: FilmAnnotationEdge = .bottom
    ) -> [FilmCell] {
        let inset = max(0, sheet.pixels(fromMillimeters: margin))
        let gap = max(0, sheet.pixels(fromMillimeters: spacing))
        // The band eats into the picture area, never into its own clearance:
        // a strip deeper than the sheet can spare would leave no cells at
        // all, so it is capped at a third of what the margins left on its axis.
        let availableWidth = max(0, Double(sheet.pixelWidth) - 2 * inset)
        let availableHeight = max(0, Double(sheet.pixelHeight) - 2 * inset)
        let onSide = edge == .left || edge == .right
        let axis = onSide ? availableWidth : availableHeight
        let reserved = edge == .overlay
            ? 0
            : min(max(0, sheet.pixels(fromMillimeters: footer)), axis / 3)

        let originX = inset + (edge == .left ? reserved : 0)
        let originY = inset + (edge == .top ? reserved : 0)
        let usableWidth = availableWidth - (onSide ? reserved : 0)
        let usableHeight = availableHeight - (onSide ? 0 : reserved)

        switch format.kind {
        case .standard(let rows, let columns):
            return grid(rows: rows, columns: columns,
                        originX: originX, originY: originY,
                        width: usableWidth, height: usableHeight, gap: gap)

        case .row(let counts):
            var cells: [FilmCell] = []
            var position = 1
            let bandHeight = band(usableHeight, count: counts.count, gap: gap)
            for (rowIndex, cellCount) in counts.enumerated() {
                let cellWidth = band(usableWidth, count: cellCount, gap: gap)
                let y = originY + Double(rowIndex) * (bandHeight + gap)
                for column in 0..<cellCount {
                    cells.append(FilmCell(
                        position: position,
                        x: originX + Double(column) * (cellWidth + gap),
                        y: y, width: cellWidth, height: bandHeight))
                    position += 1
                }
            }
            return cells

        case .column(let counts):
            var cells: [FilmCell] = []
            var position = 1
            let bandWidth = band(usableWidth, count: counts.count, gap: gap)
            for (columnIndex, cellCount) in counts.enumerated() {
                let cellHeight = band(usableHeight, count: cellCount, gap: gap)
                let x = originX + Double(columnIndex) * (bandWidth + gap)
                for row in 0..<cellCount {
                    cells.append(FilmCell(
                        position: position,
                        x: x,
                        y: originY + Double(row) * (cellHeight + gap),
                        width: bandWidth, height: cellHeight))
                    position += 1
                }
            }
            return cells

        case .slide, .superslide, .custom:
            return [FilmCell(position: 1, x: originX, y: originY,
                             width: usableWidth, height: usableHeight)]
        }
    }

    /// A uniform rows × columns grid, filled row-major.
    private static func grid(
        rows: Int, columns: Int,
        originX: Double, originY: Double,
        width: Double, height: Double, gap: Double
    ) -> [FilmCell] {
        let rows = max(1, rows), columns = max(1, columns)
        let cellWidth = band(width, count: columns, gap: gap)
        let cellHeight = band(height, count: rows, gap: gap)
        var cells: [FilmCell] = []
        var position = 1
        for row in 0..<rows {
            for column in 0..<columns {
                cells.append(FilmCell(
                    position: position,
                    x: originX + Double(column) * (cellWidth + gap),
                    y: originY + Double(row) * (cellHeight + gap),
                    width: cellWidth, height: cellHeight))
                position += 1
            }
        }
        return cells
    }

    /// The size of one band when `count` bands share `total` with `gap` between them.
    private static func band(_ total: Double, count: Int, gap: Double) -> Double {
        guard count > 0 else { return 0 }
        return max(0, (total - gap * Double(count - 1)) / Double(count))
    }
}

// MARK: - Fitting

/// How an image is placed inside its cell.
public enum FilmFitResult: Sendable, Equatable {
    /// The destination rectangle in sheet pixels, and the source rectangle in
    /// image pixels that maps onto it (the full image unless cropped).
    case placed(destination: FilmCell, sourceX: Double, sourceY: Double,
                sourceWidth: Double, sourceHeight: Double)
    /// The image could not be placed (FAIL decimate/crop behavior).
    case failed(reason: String)
}

/// Places an image inside a cell honoring Requested Image Size and
/// Requested Decimate/Crop Behavior.
public enum FilmImageFitter {

    /// - Parameters:
    ///   - imageWidth/imageHeight: the image's pixel dimensions.
    ///   - cell: the destination cell in sheet pixels.
    ///   - requestedSizeMillimeters: Requested Image Size (2020,0030), the
    ///     desired *width* of the printed image, when the SCU asked for one.
    ///   - behavior: Requested Decimate/Crop Behavior (2020,0040).
    ///   - sheet: the sheet, for millimetre → pixel conversion.
    ///   - alignment: where the image sits when it does not fill the cell —
    ///     placement of the picture inside its letterbox, or of the crop
    ///     window over the source (SRS FR-003). Centred by default, which is
    ///     what every printer does and what every existing call site expects.
    ///   - stretch: fill the cell exactly, aspect ratio ignored. Overrides
    ///     `behavior`; local composition only, no wire form.
    public static func fit(
        imageWidth: Double,
        imageHeight: Double,
        in cell: FilmCell,
        requestedSizeMillimeters: Double?,
        behavior: DecimateCropBehavior,
        sheet: FilmSheet,
        alignment: PrintCellAlignment = .center,
        stretch: Bool = false
    ) -> FilmFitResult {
        guard imageWidth > 0, imageHeight > 0, !cell.isEmpty else {
            return .failed(reason: "Empty image or cell")
        }

        if stretch {
            // The whole image onto the whole cell; x and y scale independently.
            return .placed(
                destination: cell,
                sourceX: 0, sourceY: 0, sourceWidth: imageWidth, sourceHeight: imageHeight)
        }

        /// The destination for `width` × `height` content, placed by alignment.
        func placed(width: Double, height: Double) -> FilmCell {
            let origin = alignment.origin(forContentWidth: width, height: height, in: cell)
            return FilmCell(position: cell.position,
                            x: origin.x, y: origin.y, width: width, height: height)
        }

        // A requested physical width pins the scale; otherwise fit the cell.
        let requestedPixels = requestedSizeMillimeters.map { sheet.pixels(fromMillimeters: $0) }

        switch behavior {
        case .decimate:
            let scale: Double
            if let requested = requestedPixels, requested > 0 {
                // Honor the request, but never overflow the cell.
                scale = min(requested / imageWidth,
                            min(cell.width / imageWidth, cell.height / imageHeight))
            } else {
                scale = min(cell.width / imageWidth, cell.height / imageHeight)
            }
            return .placed(
                destination: placed(width: imageWidth * scale, height: imageHeight * scale),
                sourceX: 0, sourceY: 0, sourceWidth: imageWidth, sourceHeight: imageHeight)

        case .crop:
            // Print at the requested size when one was asked for — Requested
            // Image Size "overrides the size that corresponds with optimal
            // filling of the Image Box", and CROP deletes the rows and columns
            // that then exceed it (PS3.3 Table C.13-5) — and fill the cell when
            // none was. Either way the overflow is cropped, with the crop
            // window placed by alignment so "top" keeps the top of the anatomy.
            //
            // The no-size case is this toolkit's reading: C.13-5 applies CROP
            // only "if the image rows or columns is greater than the available
            // printable pixels" at the size of "optimal filling", which it does
            // not define. "Optimal filling" is read as filling the box, which
            // is what the "Fill to Film" mode sends CROP for (decided
            // 2026-09-29, P-CROP; PRINT_CONFORMANCE.md 3.5).
            let scale: Double
            if let requested = requestedPixels, requested > 0 {
                scale = requested / imageWidth
            } else {
                scale = max(cell.width / imageWidth, cell.height / imageHeight)
            }
            let visibleWidth = min(imageWidth, cell.width / scale)
            let visibleHeight = min(imageHeight, cell.height / scale)
            return .placed(
                destination: placed(width: visibleWidth * scale, height: visibleHeight * scale),
                sourceX: (imageWidth - visibleWidth) * alignment.horizontalFraction,
                sourceY: (imageHeight - visibleHeight) * alignment.verticalFraction,
                sourceWidth: visibleWidth, sourceHeight: visibleHeight)

        case .failOver:
            // FAIL: the image must fit at 1:1 (or at the requested size) or the
            // box is reported as unprintable.
            let scale = requestedPixels.map { $0 / imageWidth } ?? 1
            let width = imageWidth * scale
            let height = imageHeight * scale
            guard width <= cell.width + 0.5, height <= cell.height + 0.5 else {
                return .failed(reason: String(
                    format: "Image %.0f×%.0f px does not fit cell %.0f×%.0f px and behavior is FAIL",
                    width, height, cell.width, cell.height))
            }
            return .placed(
                destination: placed(width: width, height: height),
                sourceX: 0, sourceY: 0, sourceWidth: imageWidth, sourceHeight: imageHeight)
        }
    }
}
