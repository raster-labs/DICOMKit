// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (annotation mapping through crop, rotation and flips)
// PrintOverlayOrientation.swift
// DICOMPrintKit
//
// Where a drawn annotation lands, and which way up its words read, once the
// picture underneath it has been turned or mirrored.
//
// A `PrintOverlayAnnotation` is stored in *image* coordinates — a fraction of
// the original frame's width and height — because that is the one space that
// survives a re-layout, a differently sized sheet, and the gap between a
// 256-pixel preview thumbnail and a 3000-pixel frame. See
// ``PrintOverlayAnnotation``.
//
// The arrangement a reader composes is not in that space. Rotating a cell
// permutes its pixels; the frame handed to the burner has already been cropped,
// turned and mirrored, and its top-left corner is no longer the image's. So the
// two spaces have to be reconciled somewhere, and it has to be *one* somewhere,
// because two screens and a printer draw the same annotation:
//
//   * The film's burn (``ImageAnnotationBurner``) draws into the arranged
//     frame's own pixels, so an image-space anchor has to be mapped forward
//     into that frame or the mark lands somewhere else on paper.
//   * The viewer's GPU overlay rasterizes at the *unarranged* frame's size and
//     lets the display shader turn it with the picture, which puts the anchor
//     in the right place for free — and turns the words with it, which is how a
//     mirrored image ended up with mirror-written text.
//
// Two questions, then, and this type answers both:
//
//   1. `point(_:)` — where an image-space fraction lands in the arranged frame.
//   2. `textAngleDegrees` / `textIsMirrored` — how much a glyph has to be
//      turned back so it reads left-to-right and right way up after the
//      arrangement has had its way with it.
//
// Answer (2) is always "cancel the arrangement": a reader's words are a note
// *about* the picture, not part of the anatomy, and there is no orientation of
// a film on which upside-down or mirror-written text is the correct rendering.
// An arrow is different and is deliberately left alone — a turned arrow still
// points where it pointed, which is the whole of what an arrow says.

import Foundation

/// How the arrangement of a picture bears on the annotations drawn over it.
///
/// Built from a ``ViewerPresentation`` and the *original* image's pixel size,
/// which together are everything the mapping needs.
public struct PrintOverlayOrientation: Sendable, Equatable {

    /// The arrangement the picture is in.
    public let presentation: ViewerPresentation

    /// The original frame's size, before the arrangement cropped or turned it.
    public let imageWidth: Int
    public let imageHeight: Int

    /// Whether the picture is laid in covering its cell rather than fitted —
    /// the crop's own question, passed through to ``ViewerPresentation``.
    public let covers: Bool

    public init(
        presentation: ViewerPresentation,
        imageWidth: Int,
        imageHeight: Int,
        covers: Bool = false
    ) {
        self.presentation = presentation
        self.imageWidth = max(0, imageWidth)
        self.imageHeight = max(0, imageHeight)
        self.covers = covers
    }

    /// The arrangement that changes nothing — an unturned, unmirrored, uncropped
    /// picture. Its ``point(_:)`` is the identity, so callers with no
    /// arrangement to speak of need no separate branch.
    public static func identity(imageWidth: Int, imageHeight: Int) -> PrintOverlayOrientation {
        PrintOverlayOrientation(
            presentation: ViewerPresentation(),
            imageWidth: imageWidth,
            imageHeight: imageHeight)
    }

    /// Whether the arrangement moves an annotation at all.
    ///
    /// A cell that is merely windowed or inverted leaves both the anchor and
    /// the lettering exactly where an unarranged one would put them, and saying
    /// so lets the callers keep their cheap path.
    public var isIdentity: Bool {
        visibleRegion == nil
            && presentation.rotationDegrees == 0
            && !presentation.flipHorizontal
            && !presentation.flipVertical
    }

    /// The crop the arrangement takes out of the image, or `nil` for all of it.
    var visibleRegion: PixelRegion? {
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        return presentation.visibleRegion(
            imageWidth: imageWidth, imageHeight: imageHeight, covers: covers)
    }

    // MARK: - Where it lands

    /// An image-space annotation point, in the arranged frame's own fractions.
    ///
    /// Follows the pixel path in ``PrintPresentationTransform`` step for step —
    /// crop, then rotate, then the horizontal flip, then the vertical one —
    /// because the frame this lands on is the frame that path produced. Any
    /// other order gives a mark that is right on some arrangements and subtly
    /// wrong on the rest, which is worse than being wrong on all of them.
    ///
    /// Points outside the crop come back outside 0…1 rather than clamped: an
    /// annotation drawn on anatomy the reader has since panned away from is not
    /// on this film, and clamping it would stick it to an edge as though it
    /// were pointing at something there.
    public func point(_ point: PrintOverlayPoint) -> (x: Double, y: Double) {
        var x = point.x
        var y = point.y

        // 1. Crop. The region is in source pixels, so the fraction is re-based
        //    on it: a mark halfway down the image is not halfway down a crop
        //    that starts below it.
        if let region = visibleRegion, region.width > 0, region.height > 0 {
            x = (point.x * Double(imageWidth) - Double(region.x)) / Double(region.width)
            y = (point.y * Double(imageHeight) - Double(region.y)) / Double(region.height)
        }

        // 2. Rotate about the centre. Quarter turns are the exact permutation
        //    the pixel path applies; a free angle turns in the cropped
        //    rectangle's own aspect, which is what the resampler does — it
        //    keeps the region's size and lets the corners fall outside.
        if presentation.rotationDegrees != 0 {
            if presentation.isQuarterTurn {
                switch presentation.quarterTurns {
                case 1:  (x, y) = (1 - y, x)
                case 2:  (x, y) = (1 - x, 1 - y)
                case 3:  (x, y) = (y, 1 - x)
                default: break
                }
            } else {
                // In fractions of a non-square rectangle a rotation is not a
                // rotation, so it is done in the rectangle's own pixels and
                // put back afterwards.
                let (width, height) = croppedSize
                let (cosine, sine) = presentation.rotationComponents
                let dx = (x - 0.5) * width
                let dy = (y - 0.5) * height
                // Clockwise on screen, which is where the angle is measured —
                // the inverse of the resampler's backwards sampling.
                let rx = dx * cosine - dy * sine
                let ry = dx * sine + dy * cosine
                x = rx / width + 0.5
                y = ry / height + 0.5
            }
        }

        // 3. The mirrors, in the pixel path's order. Either one alone is its own
        //    inverse, so the order only matters for reading this against that.
        if presentation.flipHorizontal { x = 1 - x }
        if presentation.flipVertical   { y = 1 - y }

        return (x, y)
    }

    /// The way back: a point in the arranged frame's fractions, in the image's.
    ///
    /// What a click on a turned cell means. The arrangement is undone from the
    /// outside in — mirrors, then the turn, then the crop — because that is the
    /// reverse of the order ``point(_:)`` applies them in, and a composition
    /// inverted in its own order is a different transform, not the inverse.
    public func imagePoint(x: Double, y: Double) -> PrintOverlayPoint {
        var x = x
        var y = y

        if presentation.flipVertical   { y = 1 - y }
        if presentation.flipHorizontal { x = 1 - x }

        if presentation.rotationDegrees != 0 {
            if presentation.isQuarterTurn {
                switch presentation.quarterTurns {
                case 1:  (x, y) = (y, 1 - x)
                case 2:  (x, y) = (1 - x, 1 - y)
                case 3:  (x, y) = (1 - y, x)
                default: break
                }
            } else {
                let (width, height) = croppedSize
                let (cosine, sine) = presentation.rotationComponents
                let dx = (x - 0.5) * width
                let dy = (y - 0.5) * height
                // The transpose, which for a rotation is the inverse.
                let rx = dx * cosine + dy * sine
                let ry = -dx * sine + dy * cosine
                x = rx / width + 0.5
                y = ry / height + 0.5
            }
        }

        if let region = visibleRegion, region.width > 0, region.height > 0,
           imageWidth > 0, imageHeight > 0 {
            x = (Double(region.x) + x * Double(region.width)) / Double(imageWidth)
            y = (Double(region.y) + y * Double(region.height)) / Double(imageHeight)
        }

        return PrintOverlayPoint(x: x, y: y)
    }

    /// A drag in the arranged frame's fractions, as a move in the image's.
    ///
    /// A delta, not a point: the crop's *offset* and the mirrors' reflections
    /// are translations, and a translation does not move a difference — only
    /// the crop's scale and the turn bear. Deliberately not two `imagePoint`
    /// calls subtracted, for two reasons that both bite: those clamp to 0…1,
    /// so a leftward drag from the origin came back as no drag at all; and the
    /// crop's offset would be added into each end and only mostly cancel.
    public func imageDelta(dx: Double, dy: Double) -> (dx: Double, dy: Double) {
        var dx = dx
        var dy = dy

        // The mirrors negate a difference rather than reflect it.
        if presentation.flipVertical   { dy = -dy }
        if presentation.flipHorizontal { dx = -dx }

        if presentation.rotationDegrees != 0 {
            if presentation.isQuarterTurn {
                switch presentation.quarterTurns {
                case 1:  (dx, dy) = (dy, -dx)
                case 2:  (dx, dy) = (-dx, -dy)
                case 3:  (dx, dy) = (-dy, dx)
                default: break
                }
            } else {
                let (width, height) = croppedSize
                let (cosine, sine) = presentation.rotationComponents
                let px = dx * width
                let py = dy * height
                dx = (px * cosine + py * sine) / width
                dy = (-px * sine + py * cosine) / height
            }
        }

        // Only the crop's scale survives: a drag of half a crop's width is half
        // that fraction of the whole image.
        if let region = visibleRegion, region.width > 0, region.height > 0,
           imageWidth > 0, imageHeight > 0 {
            dx *= Double(region.width) / Double(imageWidth)
            dy *= Double(region.height) / Double(imageHeight)
        }

        return (dx, dy)
    }

    /// The crop's pixel size, or the whole image when nothing is cropped —
    /// what a free-angle rotation is measured in.
    private var croppedSize: (width: Double, height: Double) {
        if let region = visibleRegion, region.width > 0, region.height > 0 {
            return (Double(region.width), Double(region.height))
        }
        return (Double(max(1, imageWidth)), Double(max(1, imageHeight)))
    }

    // MARK: - Which way up the words read

    /// How far a line of type has to be turned so it reads level once the
    /// arrangement has turned the picture under it, in degrees clockwise.
    ///
    /// A mirror reverses the sense of a rotation, which is why this is not
    /// simply the negated angle: mirroring a picture that was turned 30°
    /// clockwise leaves the words running 30° the *other* way, and un-turning
    /// them by 30° would double the tilt rather than remove it. One mirror
    /// flips the sign.
    ///
    /// Two mirrors are not a mirror at all but a half turn, so
    /// ``textIsMirrored`` rightly declines them — which leaves that half turn
    /// for this to take out, on top of the rotation. Without the added 180°
    /// a picture flipped both ways showed its annotations upside down: the
    /// right way round, and unreadable.
    public var textAngleDegrees: Double {
        let mirrors = (presentation.flipHorizontal ? 1 : 0)
            + (presentation.flipVertical ? 1 : 0)
        switch mirrors {
        case 1:  return presentation.rotationDegrees
        case 2:  return -presentation.rotationDegrees + 180
        default: return -presentation.rotationDegrees
        }
    }

    /// Whether the arrangement mirrors the lettering, so the drawing has to
    /// mirror it back.
    ///
    /// Both flips together are a half turn, not a mirror — the words come out
    /// upside down but the right way round — and that is taken out by the angle
    /// above rather than here.
    public var textIsMirrored: Bool {
        presentation.flipHorizontal != presentation.flipVertical
    }
}
