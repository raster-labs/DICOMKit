// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (arrow proportions)
// PrintArrowGeometry.swift
// DICOMPrintKit
//
// The shape of a drawn arrow, in one place.
//
// An arrow is drawn twice — once over the preview cell in the app, once into the
// pixels the printer receives — and the two have to agree, or the preview is
// lying about the film. Keeping the proportions as numbers in both drawing
// routines is how they drift apart, so they live here and both sides ask for
// them.
//
// Everything is a fraction of the image's height, the same measure the type size
// uses, so one control makes an annotation heavier or lighter as a whole and an
// arrow drawn on a 256-pixel thumbnail reads the same on a 3000-pixel frame.

import Foundation

/// A point in image space, in whatever units the caller is drawing in — screen
/// points for the preview, pixels for the film.
///
/// Deliberately not ``PrintOverlayPoint``: that one is a normalized position and
/// clamps itself to the image, while these are intermediate construction points
/// that may legitimately sit off the edge while a shape is being assembled.
public struct PrintPlanePoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// How heavy an arrow is drawn, for an image of a given height.
public struct PrintArrowGeometry: Sendable, Equatable {

    /// Width of the shaft.
    public let lineWidth: Double

    /// How far back from the point the head reaches.
    public let headLength: Double

    /// Half the head's width across its base.
    public let headHalfWidth: Double

    /// How much wider than the arrow itself its halo is drawn, so the arrow reads
    /// over lung and over mediastinum alike.
    public let haloWidth: Double

    /// The measurements for one arrow.
    ///
    /// - Parameters:
    ///   - scale: the annotation's size, a fraction of the image height.
    ///   - imageHeight: the image's height, in the units being drawn in.
    ///   - arrowLength: tail-to-head distance, in those same units. The head is
    ///     capped against it so a short arrow is an arrow and not a triangle with
    ///     a stub behind it.
    public init(scale: Double, imageHeight: Double, arrowLength: Double) {
        let size = max(0, imageHeight) * PrintOverlayAnnotation.clampScale(scale)
        let width = max(Self.minimumLineWidth, size * Self.lineWidthFraction)

        // The head is generously longer than the shaft is wide: an arrow whose
        // head is only a little wider than its line reads as a line, which is
        // exactly the complaint a barely-visible arrowhead produces.
        var head = max(width * Self.minimumHeadLengthInLineWidths,
                       size * Self.headLengthFraction)
        if arrowLength > 0 {
            head = min(head, arrowLength * Self.maximumHeadFractionOfLength)
        }

        self.lineWidth = width
        self.headLength = head
        self.headHalfWidth = head * Self.headHalfWidthFraction
        self.haloWidth = max(Self.minimumLineWidth, width * Self.haloFraction)
    }

    /// The corners of the arrow, given where its ends are.
    ///
    /// The shaft stops where the head begins, so the head is a solid triangle
    /// rather than a triangle with a line running through its point.
    public func outline(tail: PrintPlanePoint, head: PrintPlanePoint) -> PrintArrowOutline? {
        let dx = head.x - tail.x
        let dy = head.y - tail.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return nil }

        let ux = dx / length
        let uy = dy / length
        let base = PrintPlanePoint(x: head.x - ux * headLength,
                                   y: head.y - uy * headLength)
        return PrintArrowOutline(
            tail: tail,
            shaftEnd: length > headLength ? base : head,
            head: head,
            headBase: base,
            headLeft: PrintPlanePoint(x: base.x - uy * headHalfWidth,
                                      y: base.y + ux * headHalfWidth),
            headRight: PrintPlanePoint(x: base.x + uy * headHalfWidth,
                                       y: base.y - ux * headHalfWidth),
            unitX: ux,
            unitY: uy,
            length: length)
    }

    /// Shaft width as a fraction of the annotation size.
    static let lineWidthFraction: Double = 0.16

    /// Head length as a fraction of the annotation size. Well over the shaft
    /// width, so the head is the part of the arrow the eye lands on.
    static let headLengthFraction: Double = 1.3

    /// Half the head's base, as a fraction of its length — a broad head rather
    /// than a needle.
    static let headHalfWidthFraction: Double = 0.5

    /// The head never eats more than this much of a short arrow.
    static let maximumHeadFractionOfLength: Double = 0.45

    /// However small the annotation, the head stays this many line widths long.
    static let minimumHeadLengthInLineWidths: Double = 3.5

    static let haloFraction: Double = 0.8

    /// Below one unit nothing is drawn at all.
    static let minimumLineWidth: Double = 1
}

/// Where each corner of one drawn arrow sits.
public struct PrintArrowOutline: Sendable, Equatable {

    /// The held end.
    public let tail: PrintPlanePoint

    /// Where the shaft stops — the head's base, unless the arrow is shorter than
    /// its own head, in which case the shaft collapses to the point.
    public let shaftEnd: PrintPlanePoint

    /// The point.
    public let head: PrintPlanePoint

    /// The middle of the head's base, which is where the two barbs meet the shaft.
    public let headBase: PrintPlanePoint

    public let headLeft: PrintPlanePoint
    public let headRight: PrintPlanePoint

    /// The direction tail to head, as a unit vector.
    public let unitX: Double
    public let unitY: Double

    /// Tail-to-head distance.
    public let length: Double
}
