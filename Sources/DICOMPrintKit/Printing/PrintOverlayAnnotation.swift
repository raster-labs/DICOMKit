// NEMA-verified: 2026a, checked 2026-09-29 — point conventions of the shape kinds (POINT, POLYLINE, INTERPOLATED, CIRCLE centre + perimeter, ELLIPSE major/minor axis ends) checked against PS3.3 2026a C.10.5.1.2; row/column order per C.7.6.3.1.4
// PrintOverlayAnnotation.swift
// DICOMPrintKit
//
// What a reader drew on a film cell: a line of text, or an arrow pointing at
// something.
//
// These are not DICOM annotation boxes. A printer's annotation boxes carry
// captions the printer lays out itself, in positions it chooses, and many
// printers ignore them; an arrow that has to land on a particular vessel cannot
// be expressed that way at all. So a drawn annotation is burned into the pixels
// of the image it belongs to, which is the only way to be sure the film shows it
// where the reader put it.
//
// Coordinates are normalized to the *image*, not to the film cell: the cell is a
// screen measurement that changes with the window size and the layout, while the
// image is what gets printed. 0,0 is the image's top-left corner and 1,1 its
// bottom-right, matching the row/column order of DICOM pixel data. An annotation
// therefore survives a re-layout, a differently sized sheet, and the difference
// between a 256-pixel preview thumbnail and a 3000-pixel frame.

import Foundation

/// A point on an image, as a fraction of its width and height from the top-left.
public struct PrintOverlayPoint: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double

    /// Clamped on the way in: an annotation outside the image has no pixels to be
    /// burned into, and would simply vanish between the preview and the film.
    public init(x: Double, y: Double) {
        self.x = min(1, max(0, x.isFinite ? x : 0))
        self.y = min(1, max(0, y.isFinite ? y : 0))
    }

    /// This point moved by a normalized delta, still inside the image.
    public func moved(dx: Double, dy: Double) -> PrintOverlayPoint {
        PrintOverlayPoint(x: x + dx, y: y + dy)
    }
}

/// An annotation colour, in sRGB components.
///
/// Kept as plain numbers rather than a `Color`: this module has to draw into
/// pixel buffers, and it is used by command-line tools with no UI framework
/// loaded at all.
public struct PrintOverlayColor: Sendable, Equatable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    /// Yellow — the reading-room default. It reads over both a black background
    /// and a white lung field, and it is not red, which on film means "error".
    public static let yellow = PrintOverlayColor(red: 1, green: 0.85, blue: 0.1)
    public static let white = PrintOverlayColor(red: 1, green: 1, blue: 1)
    public static let red = PrintOverlayColor(red: 1, green: 0.25, blue: 0.2)
    public static let green = PrintOverlayColor(red: 0.3, green: 0.9, blue: 0.4)
    public static let cyan = PrintOverlayColor(red: 0.3, green: 0.85, blue: 1)

    /// What this colour becomes on a greyscale printer.
    ///
    /// Rec. 601 luminance, the same weighting the rest of the print path uses to
    /// flatten colour frames, so a colour chosen here lands at the brightness the
    /// preview showed rather than at some other grey.
    public var luminance: Double {
        0.299 * red + 0.587 * green + 0.114 * blue
    }
}

/// Identity of the image an annotation is drawn on.
///
/// Annotations belong to the image, not to any particular film mark: the same
/// frame can be marked onto more than one film cell, and a drawing made on it
/// should show up wherever that frame appears — in every cell it is marked
/// onto, and in the viewer, whether or not the print tray has ever been
/// opened. `sopInstanceUID` is deliberately not part of this key: a
/// multi-tile viewer layout leaves it `nil` for every tile that is not
/// focused, so keying on it would silently drop annotations for those tiles.
/// `filePath` + `frameIndex` is the one thing every caller always has.
public struct ImageAnnotationKey: Hashable, Sendable, Codable {
    public var filePath: String
    public var frameIndex: Int

    public init(filePath: String, frameIndex: Int) {
        self.filePath = filePath
        self.frameIndex = frameIndex
    }
}

/// One thing a reader drew on one film cell.
public struct PrintOverlayAnnotation: Sendable, Equatable, Identifiable, Codable {

    public enum Kind: String, Sendable, Equatable, Codable {
        case text
        case arrow

        /// A label with an arrow pointing from it at the anatomy — the viewer's
        /// combined annotation tool, after Weasis's. `start` is the label's
        /// top-left, `end` the anchor the arrow points at; either half may be
        /// absent (no words yet, or anchor still under the label), so this one
        /// kind covers plain text, plain arrow, and both together.
        case annotation

        // MARK: Shapes read from a presentation state
        //
        // The kinds below are not drawn with the app's own tools. They exist
        // so a presentation state written by another viewer — Weasis's
        // rulers, angles, polygons and ROIs, each a GSPS graphic object with
        // its value in a text object beside it — can be shown on the image
        // and burned into the film exactly as that viewer stated it. They
        // use `points` rather than `start`/`end`, in DICOM's own point
        // conventions (PS3.3 C.10.5.1.2), normalized to the image.

        /// Straight segments through `points`, in order. Closed and filled
        /// when `filled` is set — a polygon. Also what INTERPOLATED becomes:
        /// a curve drawn as its control polyline, which is what most viewers
        /// do with it too.
        case polyline

        /// A circle: `points[0]` is the centre, `points[1]` a point on the
        /// circumference.
        case circle

        /// An ellipse: `points[0...1]` are the ends of the major axis,
        /// `points[2...3]` the ends of the minor axis.
        case ellipse

        /// A single marked point, drawn as a small cross at `points[0]`.
        case point

        /// A display shutter: everything *outside* the shape is painted the
        /// shutter's presentation value. `points` follow the shape:
        /// a rectangle is its top-left and bottom-right, a circle its centre
        /// and a point on the circumference, a polygon its vertices. The
        /// paint colour is `color`. Drawn under every other annotation.
        case shutter

        /// Whether this kind is one of the shapes above rather than a thing
        /// the reader drew with a tool here.
        public var isShape: Bool {
            switch self {
            case .text, .arrow, .annotation: return false
            case .polyline, .circle, .ellipse, .point, .shutter: return true
            }
        }
    }

    public var id: UUID
    public var kind: Kind

    /// Text: where the type starts. Arrow: the tail, the end held.
    public var start: PrintOverlayPoint

    /// The arrow's head, the end that points. Unused by text.
    public var end: PrintOverlayPoint

    /// The words, for a text annotation.
    public var text: String

    /// Type size as a fraction of the image's height.
    ///
    /// A fraction rather than points: the same annotation is drawn on a 200-point
    /// preview cell and burned into a 2000-pixel frame, and only a relative size
    /// looks the same in both. It also sets an arrow's line width and head size,
    /// so one control changes how heavy an annotation reads.
    public var scale: Double

    public var color: PrintOverlayColor

    /// The vertices of a shape kind, normalized to the image. Empty for the
    /// text and arrow kinds, which use `start` and `end`.
    public var points: [PrintOverlayPoint]

    /// Whether a shape is filled (a polygon, a filled ellipse) rather than
    /// outlined. Meaningless for a shutter, which always fills its outside.
    public var filled: Bool

    /// Whether the reader may move, edit or delete this annotation here.
    ///
    /// Set on everything that came out of another viewer's presentation
    /// state: a ruler whose label says "42.3 mm" cannot be dragged without
    /// making the number a lie, and the app has no measuring tool to
    /// recompute it. Locked annotations are displayed and printed exactly
    /// as stated; the whole imported view can still be taken off.
    public var isLocked: Bool

    public init(
        id: UUID = UUID(),
        kind: Kind,
        start: PrintOverlayPoint,
        end: PrintOverlayPoint? = nil,
        text: String = "",
        scale: Double = PrintOverlayAnnotation.defaultScale,
        color: PrintOverlayColor = .yellow,
        points: [PrintOverlayPoint] = [],
        filled: Bool = false,
        isLocked: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end ?? start
        self.text = text
        self.scale = PrintOverlayAnnotation.clampScale(scale)
        self.color = color
        self.points = points
        self.filled = filled
        self.isLocked = isLocked
    }

    /// A shape kind, its points stated directly.
    ///
    /// `start` is the first point and `end` the last, so code that only knows
    /// the two-ended kinds still lands somewhere sensible on a shape.
    public init(
        id: UUID = UUID(),
        shape kind: Kind,
        points: [PrintOverlayPoint],
        filled: Bool = false,
        text: String = "",
        scale: Double = PrintOverlayAnnotation.defaultScale,
        color: PrintOverlayColor = .yellow,
        isLocked: Bool = true
    ) {
        self.init(
            id: id, kind: kind,
            start: points.first ?? PrintOverlayPoint(x: 0, y: 0),
            end: points.last,
            text: text, scale: scale, color: color,
            points: points, filled: filled, isLocked: isLocked)
    }

    // MARK: Codable
    //
    // Spelled out so a sidecar written before the shape kinds existed — with
    // no `points`, `filled` or `isLocked` — reads back exactly as it did,
    // and one written now still carries only the keys older builds know
    // when the new fields are at their defaults.

    private enum CodingKeys: String, CodingKey {
        case id, kind, start, end, text, scale, color, points, filled, isLocked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        start = try container.decode(PrintOverlayPoint.self, forKey: .start)
        end = try container.decodeIfPresent(PrintOverlayPoint.self, forKey: .end) ?? start
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        scale = Self.clampScale(
            try container.decodeIfPresent(Double.self, forKey: .scale) ?? Self.defaultScale)
        color = try container.decodeIfPresent(PrintOverlayColor.self, forKey: .color) ?? .yellow
        points = try container.decodeIfPresent([PrintOverlayPoint].self, forKey: .points) ?? []
        filled = try container.decodeIfPresent(Bool.self, forKey: .filled) ?? false
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(text, forKey: .text)
        try container.encode(scale, forKey: .scale)
        try container.encode(color, forKey: .color)
        if !points.isEmpty { try container.encode(points, forKey: .points) }
        if filled { try container.encode(filled, forKey: .filled) }
        if isLocked { try container.encode(isLocked, forKey: .isLocked) }
    }

    /// Whether this annotation would draw nothing — empty text, or an arrow with
    /// no length. Filtered out before burning rather than deleted while editing: a
    /// text annotation is empty for as long as it takes to type into it.
    public var isBlank: Bool {
        switch kind {
        case .text:
            return !hasWords
        case .arrow:
            return !hasArrow
        case .annotation:
            // Either half carries it: a label with no arrow is text, an arrow
            // with no label is an arrow, and only both missing is nothing.
            return !hasWords && !hasArrow
        case .polyline:
            return points.count < 2
        case .circle:
            return points.count < 2
        case .ellipse:
            return points.count < 4
        case .point:
            return points.isEmpty
        case .shutter:
            return points.count < 2
        }
    }

    /// Whether this is a shape stated by a presentation state rather than a
    /// thing drawn with a tool — see ``Kind/isShape``.
    public var isShape: Bool { kind.isShape }

    /// Whether the text says anything once whitespace is stripped.
    public var hasWords: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the two ends are far enough apart to draw an arrow between.
    public var hasArrow: Bool {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return (dx * dx + dy * dy).squareRoot() >= Self.minimumArrowLength
    }

    /// This annotation moved bodily — both ends, so an arrow keeps its direction.
    public func moved(dx: Double, dy: Double) -> PrintOverlayAnnotation {
        var copy = self
        copy.start = start.moved(dx: dx, dy: dy)
        copy.end = end.moved(dx: dx, dy: dy)
        copy.points = points.map { $0.moved(dx: dx, dy: dy) }
        return copy
    }

    public func withScale(_ newScale: Double) -> PrintOverlayAnnotation {
        var copy = self
        copy.scale = Self.clampScale(newScale)
        return copy
    }

    /// Size bounds: below the floor the type is unreadable at any print size,
    /// above the ceiling one annotation covers the anatomy it is pointing at.
    public static func clampScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultScale }
        return min(maximumScale, max(minimumScale, value))
    }

    /// Small enough to sit beside the anatomy rather than over it — the burner's
    /// pixel floor still keeps it legible on any frame. Was 4%, the size of the
    /// patient caption, which read as a headline once every annotation carried it.
    public static let defaultScale: Double = 0.02
    public static let minimumScale: Double = 0.015
    public static let maximumScale: Double = 0.20

    /// Shorter than this and an arrow is a click, not a drawing.
    static let minimumArrowLength: Double = 0.01
}
