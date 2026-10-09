// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (label/leader plane geometry)
// PrintAnnotationLayout.swift
// DICOMPrintKit
//
// Where a combined annotation's arrow leaves its label — the one piece of
// geometry the merged text-and-arrow kind adds over its parents.
//
// A combined annotation (`PrintOverlayAnnotation.Kind.annotation`) draws its
// arrow from the label toward the anchor, the way Weasis's Annotation graphic
// does: the shaft starts at the label box's border, on the segment from the
// box's centre to the anchor, so the line visibly comes *from* the words
// without crossing them. When the anchor sits inside the box there is nothing
// sensible to draw — an arrow would point at the words themselves — so the
// arrow is suppressed rather than drawn underneath.
//
// Shared here because four renderers draw that same leader — the burner for
// film, the viewer's GPU overlay (which rasterizes through the burner), the
// viewer's non-Metal fallback, and the film cell preview — and each works in
// its own units. The clipping is pure plane geometry, so it takes plain
// numbers and stays unit-agnostic.

import Foundation

public enum PrintAnnotationLayout {

    /// The point where the segment from the label box's centre to the anchor
    /// crosses the box's border — the tail of a combined annotation's arrow —
    /// or `nil` when the anchor lies inside the box and no arrow should be
    /// drawn at all.
    ///
    /// Units are the caller's, as long as origin, size and anchor agree; the
    /// box is axis-aligned with `boxOrigin` its top-left (or any corner —
    /// the intersection is symmetric).
    public static func leaderExit(
        boxOrigin: PrintPlanePoint,
        boxWidth: Double,
        boxHeight: Double,
        anchor: PrintPlanePoint
    ) -> PrintPlanePoint? {
        let halfWidth = max(0, boxWidth) / 2
        let halfHeight = max(0, boxHeight) / 2
        let center = PrintPlanePoint(x: boxOrigin.x + halfWidth,
                                     y: boxOrigin.y + halfHeight)
        let dx = anchor.x - center.x
        let dy = anchor.y - center.y

        // How far along centre→anchor each pair of box edges is met, as a
        // fraction of the whole segment. The nearer pair is the border
        // crossing; a fraction of 1 or more means the anchor never leaves
        // the box.
        var toEdge = Double.infinity
        if abs(dx) > 0 { toEdge = min(toEdge, halfWidth / abs(dx)) }
        if abs(dy) > 0 { toEdge = min(toEdge, halfHeight / abs(dy)) }
        guard toEdge.isFinite, toEdge < 1 else { return nil }

        return PrintPlanePoint(x: center.x + dx * toEdge,
                               y: center.y + dy * toEdge)
    }

    /// A combined annotation's arrow tail in image-normalized coordinates:
    /// the label box's border when there are words, the raw `start` when
    /// there are none, and `nil` when no arrow should be drawn — the ends
    /// too close together, or the anchor under the label itself.
    ///
    /// - Parameters:
    ///   - imageWidth: The image's columns, in pixels — the label box is
    ///     measured in pixels (type size is a fraction of the image height)
    ///     and the result converted back to fractions.
    ///   - imageHeight: The image's rows.
    public static func leaderTail(
        for annotation: PrintOverlayAnnotation,
        imageWidth: Double,
        imageHeight: Double
    ) -> PrintOverlayPoint? {
        guard annotation.hasArrow, imageWidth > 0, imageHeight > 0 else { return nil }
        guard annotation.hasWords else { return annotation.start }

        let size = PrintOverlayAnnotationGSPS.measuredTextSize(
            annotation.text, imageHeight: imageHeight, scale: annotation.scale)
        let exit = leaderExit(
            boxOrigin: PrintPlanePoint(x: annotation.start.x * imageWidth,
                                       y: annotation.start.y * imageHeight),
            boxWidth: size.width,
            boxHeight: size.height,
            anchor: PrintPlanePoint(x: annotation.end.x * imageWidth,
                                    y: annotation.end.y * imageHeight))
        guard let exit else { return nil }
        return PrintOverlayPoint(x: exit.x / imageWidth, y: exit.y / imageHeight)
    }
}
