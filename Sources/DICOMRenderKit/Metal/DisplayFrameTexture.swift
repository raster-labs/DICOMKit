// DisplayFrameTexture.swift
// DICOMRenderKit — GPU_RENDERING_PLAN.md milestone M5
//
// A rendered frame that has not been flattened into a CGImage, plus the geometry
// that decides where it lands on screen.
//
// NEMA-verified: 2026a, checked 2026-09-30 — rotation before horizontal flip matches PS3.3 2026a C.10.6 (both transforms, by script); the desaturate weights 0.299/0.587/0.114 are the YBR_FULL Y row of C.7.6.3.1.2; zoom, pan, crop mask and the viewer inversion are display geometry with no DICOM attribute.

import Foundation
import simd
#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(Metal)
import Metal

/// A windowed frame living in GPU memory, ready to be drawn.
///
/// Holds the `MTLBuffer` the texture views so the memory cannot be recycled while
/// the texture is still being drawn — the texture itself does not retain the buffer
/// it was created from.
public struct DisplayFrameTexture: @unchecked Sendable {
    public let texture: MTLTexture

    /// True for `.r8Unorm` single-channel frames, which the fragment shader splats
    /// across RGB.
    public let isGrayscale: Bool

    /// The colour space the texture's RGB values are in: the image's ICC Profile
    /// (PS3.3 C.11.15.1.1, P-ICC), or `nil` for device values. `MetalImageView` sets
    /// it on its layer so the system converts to the screen.
    public let colorSpace: CGColorSpace?

    /// Owner of the output buffer the texture views. Retained, never read here.
    ///
    /// Shared with the `CGImage` built over the same memory: the buffer returns to
    /// the pool only once both are gone. Recycling it while either was still reading
    /// would corrupt what is on screen.
    let backing: OutputBufferBox

    init(texture: MTLTexture, isGrayscale: Bool, colorSpace: CGColorSpace? = nil,
         retaining backing: OutputBufferBox) {
        self.texture = texture
        self.isGrayscale = isGrayscale
        self.colorSpace = colorSpace
        self.backing = backing
    }

    public var width: Int { texture.width }
    public var height: Int { texture.height }
}

// MARK: - Presentation

/// How a frame is arranged on screen: the tool state, as pure geometry.
///
/// Every field here is free to change. None of them re-renders anything — they
/// become a 4×4 matrix in the display shader, so a zoom, a rotation or a flip costs
/// one redraw of a textured quad. That is the whole point of M5: before it, a
/// rotation or an invert meant a full CPU `CGContext` pass over every pixel, and a
/// zoom meant a resample.
public struct DisplayPresentation: Equatable, Sendable {
    /// 1.0 = fit to the view.
    public var zoom: Double = 1.0
    /// Pan in points, in view space.
    public var panX: Double = 0
    public var panY: Double = 0
    /// Clockwise rotation in degrees. Any angle — not just quarter turns.
    public var rotationDegrees: Double = 0
    public var flipHorizontal: Bool = false
    public var flipVertical: Bool = false
    /// Grey inversion, applied in the fragment shader as `1 - x`. Exact on 8-bit.
    public var invert: Bool = false

    /// Present a colour frame as its Rec.601 luminance greys.
    ///
    /// The print preview sets this when the job flattens colour sources
    /// ("Print colour images as greys"): the texture stays colour — flattening
    /// is a job setting, not a property of the frame, and must revert the
    /// moment the switch does — so the reduction happens at display time, with
    /// the same 0.299/0.587/0.114 weights `ImagePreprocessor.flattenToGrayscale`
    /// bakes into the film. Applied before ``invert``, matching the wire, where
    /// the flatten happens before the rendered Presentation LUT.
    public var desaturate: Bool = false

    /// Force bilinear sampling regardless of scale.
    ///
    /// The viewer leaves this `false` and lets ``magnifies(imageWidth:imageHeight:viewWidth:viewHeight:)``
    /// decide per draw: nearest at or below 1:1 (a texel maps to at most one
    /// device pixel, so nearest is exact and a reader at actual size sees the
    /// actual pixels), bilinear once the picture is magnified (a 154×192 MR
    /// filling a reading area is ~4.6×, and point-replication there shows as
    /// blocks). The print preview sets this `true`: its cells are judged as
    /// pictures on a panel-scaled sheet, its CPU-drawn cells are smoothed by
    /// the platform image view, and a cell must not change texture the moment
    /// its GPU texture arrives.
    public var linearFiltering: Bool = false

    /// The rectangle of source pixels to show, when the caller knows it exactly.
    ///
    /// Set this and ``zoom``/``panX``/``panY`` are ignored: the region is fitted to
    /// the view and centred in it, which is the *film's* composition rather than
    /// the viewer's. See ``sourceRegionTransform(imageWidth:imageHeight:viewWidth:viewHeight:)``
    /// for why the two differ and when that matters.
    ///
    /// The region also masks: the fragment shader paints everything outside it
    /// black, because on a film only the crop exists — the corners a free
    /// rotation leaves empty and the letterbox beside a zoomed crop are
    /// unexposed film, not the neighbouring anatomy the quad happens to carry.
    public var sourceRegion: SourceRegion?

    /// Fill the view exactly, aspect ratio ignored — the film's stretch mode.
    ///
    /// Only meaningful with ``sourceRegion``: the region is composed as usual
    /// (cropped, turned, centred) and the finished picture is then stretched to
    /// the view on both axes, which is what the printer-side stretch does to a
    /// cell. Without a region this flag does nothing.
    public var stretchToFill: Bool = false

    /// The rectangle the fit is computed from, when it differs from
    /// ``sourceRegion``.
    ///
    /// These are the same rectangle whenever a cell is upright, and they part
    /// company the moment one is turned off-square. A freely turned picture
    /// keeps the scale it had upright — that is a fixed contract, pinned by
    /// `testFreeAngleKeepsTheUnrotatedScale`, and it is what stops the rotate
    /// tool from reading as a zoom-out. But keeping that scale means the turned
    /// picture no longer covers its cell: the corners the turn swings inward
    /// leave wedges of cell with no pixels over them.
    ///
    /// The source image usually *has* those pixels — a zoomed, panned cell is
    /// looking at the middle of a much larger frame — so the fix is to ask for
    /// more of them without letting the extra change the fit. ``sourceRegion``
    /// grows to the turned bounding box, which is what feeds the corners and
    /// what the mask spares; this stays the upright rectangle, which is what
    /// the scale is computed from. Set them equal, or leave this `nil`, and the
    /// geometry is exactly what it was.
    public var fittedRegion: SourceRegion?

    /// The rectangle the fit is measured against: ``fittedRegion`` when the
    /// caller set one, and otherwise the source region itself.
    var regionToFit: SourceRegion? { fittedRegion ?? sourceRegion }

    /// A rectangle of source pixels, in the frame's own pixel coordinates with the
    /// origin at its top left.
    public struct SourceRegion: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public init(
        zoom: Double = 1.0, panX: Double = 0, panY: Double = 0,
        rotationDegrees: Double = 0,
        flipHorizontal: Bool = false, flipVertical: Bool = false,
        invert: Bool = false,
        desaturate: Bool = false,
        linearFiltering: Bool = false,
        sourceRegion: SourceRegion? = nil,
        stretchToFill: Bool = false,
        fittedRegion: SourceRegion? = nil
    ) {
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.rotationDegrees = rotationDegrees
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.invert = invert
        self.desaturate = desaturate
        self.linearFiltering = linearFiltering
        self.sourceRegion = sourceRegion
        self.stretchToFill = stretchToFill
        self.fittedRegion = fittedRegion
    }

    /// The region as the shader's mask rectangle: (minU, minV, maxU, maxV).
    ///
    /// Grown by half a texel on every side. The mask boundary and the region's
    /// edge are the same line, and a fill-scaled cell puts that line exactly on
    /// the view's border — sampled there with float arithmetic, a coordinate a
    /// rounding error outside would flicker black along the cell's edge. Half a
    /// texel of slack keeps the border pixel; it is the same outward rounding
    /// the CPU crop performs when it floors and ceils the region to whole
    /// pixels.
    ///
    /// `(0,0,1,1)` — the whole frame — when there is no region, which turns the
    /// mask off; the viewer's own path always answers that.
    func sourceRegionUV(imageWidth: Int, imageHeight: Int) -> SIMD4<Float> {
        guard let region = sourceRegion, imageWidth > 0, imageHeight > 0 else {
            return SIMD4<Float>(0, 0, 1, 1)
        }
        let w = Double(imageWidth), h = Double(imageHeight)
        let slackU = 0.5 / w, slackV = 0.5 / h
        return SIMD4<Float>(
            Float(max(0, region.x / w - slackU)),
            Float(max(0, region.y / h - slackV)),
            Float(min(1, (region.x + region.width) / w + slackU)),
            Float(min(1, (region.y + region.height) / h + slackV)))
    }

    public static let identity = DisplayPresentation()
}

/// The parameter block the display shader reads. Layout must match `DisplayParams`
/// in the shader (`Metal/FrameRender.metal.txt`) — field order included: the
/// `float4` sits directly after the matrix on both sides so the two layouts
/// cannot disagree about padding.
struct DisplayShaderParams {
    var transform: simd_float4x4
    /// The film's crop as (minU, minV, maxU, maxV); fragments outside it are
    /// black. (0,0,1,1) — the whole frame — disables the mask.
    var sourceRegion: SIMD4<Float>
    var invert: UInt32
    var isGrayscale: UInt32
    var linearFilter: UInt32
    var desaturate: UInt32
}

extension DisplayPresentation {
    /// Builds the image-quad → normalised-device-coordinates matrix.
    ///
    /// Order matters and is: aspect-fit, then zoom, then rotate, then flip, then
    /// pan. Fit first so zoom is relative to the fitted image rather than to the
    /// view; rotate after zoom so the image spins about its own centre; pan last so
    /// dragging moves the picture across the screen rather than through its own
    /// rotated frame — which is what a hand tool is expected to feel like.
    ///
    /// Flip goes *after* the rotation, which is what every other path in the
    /// codebase already does — ``sourceRegionTransform`` below, and
    /// `FrameRenderer.applying`'s `CGContext`. Folding the mirror into the fit
    /// scale put it *before* the rotation instead, and the two orders are the
    /// same picture only while the image is unturned. On a quarter turn they
    /// differ by a half turn: flip an image rotated 90° and it came back upside
    /// down rather than mirrored, and the film — composing in the other order —
    /// disagreed with the screen it was supposed to be showing.
    ///
    /// Returns `nil` for a degenerate viewport. **A zero-sized drawable is the known
    /// hazard here**: this codebase has already shipped a viewer that blanked every
    /// progressively-decoded J2K file because its canvas resolved to zero size under
    /// `.aspectRatio` (see `ProgressiveImageView`). Answering `nil` rather than
    /// dividing by zero is what makes that case detectable instead of silent.
    /// Whether the picture is drawn larger than 1 device pixel per image pixel.
    ///
    /// The aspect-fit scale the transform starts from, times the reader's zoom,
    /// measured in *drawable* pixels — so a 2× display magnifies at half the
    /// point-space zoom, which is what the eye sees. This is what picks the
    /// display shader's sampler: nearest is exact up to 1:1 and bilinear above
    /// it. A film crop (``sourceRegion``) composes its own scale and sets
    /// ``linearFiltering`` explicitly, so it is never magnified by this rule.
    /// A degenerate image or viewport is not magnified.
    public func magnifies(imageWidth: Int, imageHeight: Int,
                          viewWidth: Double, viewHeight: Double) -> Bool {
        guard sourceRegion == nil,
              imageWidth > 0, imageHeight > 0, viewWidth > 0, viewHeight > 0 else { return false }
        let fit = min(viewWidth / Double(imageWidth), viewHeight / Double(imageHeight))
        return fit * zoom > 1.0
    }

    func transform(imageWidth: Int, imageHeight: Int,
                   viewWidth: Double, viewHeight: Double) -> simd_float4x4? {
        if sourceRegion != nil {
            return sourceRegionTransform(
                imageWidth: imageWidth, imageHeight: imageHeight,
                viewWidth: viewWidth, viewHeight: viewHeight)
        }
        guard imageWidth > 0, imageHeight > 0,
              viewWidth > 0, viewHeight > 0,
              zoom > 0 else { return nil }

        // Aspect fit: scale the unit quad so the image's aspect ratio is preserved
        // inside the view and its longest constrained edge just touches the bounds.
        let imageAspect = Double(imageWidth) / Double(imageHeight)
        let viewAspect = viewWidth / viewHeight
        var fitX = 1.0
        var fitY = 1.0
        if imageAspect > viewAspect {
            fitY = viewAspect / imageAspect   // width-limited: shrink vertically
        } else {
            fitX = imageAspect / viewAspect   // height-limited: shrink horizontally
        }

        // The mirror is deliberately *not* folded in here — see the note above.
        // It is applied after the rotation, below.
        let scaleX = fitX * zoom
        let scaleY = fitY * zoom
        var matrix = simd_float4x4(diagonal: SIMD4<Float>(Float(scaleX), Float(scaleY), 1, 1))

        if rotationDegrees != 0 {
            // Negated: the viewer rotates clockwise in screen space while NDC y runs
            // upward, so a positive angle here would turn the image the wrong way.
            let radians = Float(-rotationDegrees * .pi / 180)
            let c = cos(radians), s = sin(radians)
            let rotation = simd_float4x4(
                SIMD4<Float>( c, s, 0, 0),
                SIMD4<Float>(-s, c, 0, 0),
                SIMD4<Float>( 0, 0, 1, 0),
                SIMD4<Float>( 0, 0, 0, 1)
            )
            // Rotate in a square space, not in NDC. NDC's two units span the view
            // whatever its shape, so turning a picture there stretches it as it goes
            // — a square would leave the quarter turn as a rectangle in any viewport
            // that isn't itself square, and at the in-between angles the rotate tool
            // sweeps through, the picture would breathe as it turned. Scaling x by the
            // view's aspect makes one unit mean the same distance on both axes, and
            // the inverse afterwards puts the result back in NDC.
            let toSquare = simd_float4x4(diagonal:
                SIMD4<Float>(Float(viewAspect), 1, 1, 1))
            let fromSquare = simd_float4x4(diagonal:
                SIMD4<Float>(Float(1 / viewAspect), 1, 1, 1))
            matrix = fromSquare * rotation * toSquare * matrix
        }

        // Mirror, after the turn: the flip buttons mirror what is on screen —
        // left-to-right as the reader sees it — not the image's own stored axes.
        if flipHorizontal || flipVertical {
            let flip = simd_float4x4(diagonal: SIMD4<Float>(
                flipHorizontal ? -1 : 1, flipVertical ? -1 : 1, 1, 1))
            matrix = flip * matrix
        }

        // Pan is in points; NDC spans 2 units across the view, hence the doubling.
        if panX != 0 || panY != 0 {
            var translation = matrix_identity_float4x4
            translation.columns.3 = SIMD4<Float>(
                Float(2 * panX / viewWidth),
                Float(-2 * panY / viewHeight),   // view y grows downward, NDC upward
                0, 1
            )
            matrix = translation * matrix
        }

        return matrix
    }

    /// The transform that shows ``sourceRegion``, composed the way film is.
    ///
    /// The viewer's transform above and this one answer different questions. The
    /// viewer's is "where does the picture sit on screen while the user drags it":
    /// the frame is fitted, zoomed, spun about its centre and then pushed around by
    /// the pan, and what falls outside the view is simply not seen. A printer does
    /// something else entirely — it is handed a *rectangle of source pixels*, turns
    /// it, and fits that into the film's image box, centred, with no notion of
    /// "outside the image". The two agree while a cell is merely zoomed and agree
    /// exactly nowhere else: a quarter turn changes the shape being fitted, and a
    /// pan far enough to run off the edge is a crop the printer centres and the
    /// viewer leaves lying against one side.
    ///
    /// So a preview of a film composes like film. The caller works out the region —
    /// `ViewerPresentation.visibleRegion` is the one place that decision is made,
    /// and it is the same call the print path makes — and this turns that region
    /// into the quad's matrix. Nothing here re-renders: it is still one redraw per
    /// tool step, with the film's geometry instead of the viewer's.
    ///
    /// Order, and it is not the viewer's: fit the region, centre it, rotate, then
    /// flip. Flipping *after* the rotation is what `FrameRenderer.applying` does
    /// with its `CGContext` (scale, then rotate, applied to the drawing in reverse),
    /// and on quarter turns the other order is a different picture.
    func sourceRegionTransform(imageWidth: Int, imageHeight: Int,
                               viewWidth: Double, viewHeight: Double) -> simd_float4x4? {
        guard let region = sourceRegion,
              imageWidth > 0, imageHeight > 0,
              viewWidth > 0, viewHeight > 0,
              region.width > 0, region.height > 0,
              region.x.isFinite, region.y.isFinite else { return nil }

        // The region as it will be *after* turning, which is the shape actually
        // being fitted — a quarter turn makes a wide crop a tall one.
        //
        // Quarter turns only. A free angle turns the picture about its centre at
        // the scale the region already had, and the corners that swing outside
        // the cell are cut — the way the viewer turns a picture, and the way the
        // film's own resampler now composes one. Fitting the turned *bounding
        // box* instead would keep those corners at the cost of the anatomy's
        // size: √2 smaller at 45°, and visibly smaller at the small angles used
        // to straighten a tilted head.
        // Measured on the *fitted* rectangle, not on the region actually
        // sampled. Off-square, the two differ: the region has been grown to the
        // turned bounding box so the cell's corners have pixels over them, and
        // fitting that grown box would shrink the anatomy by exactly the amount
        // the growth added — which is the shrink `testFreeAngleKeepsTheUnrotatedScale`
        // exists to forbid. The fit stays on the upright rectangle; the extra
        // pixels spill past the cell's edges and are cropped, as they should be.
        let fitted = (regionToFit?.width ?? 0) > 0 && (regionToFit?.height ?? 0) > 0
            ? (regionToFit ?? region) : region
        let (turnedWidth, turnedHeight) = Self.quarterTurnedSize(
            width: fitted.width, height: fitted.height, degrees: rotationDegrees)

        // Points per source pixel: the fit the printer performs into its box.
        let scale = min(viewWidth / turnedWidth, viewHeight / turnedHeight)
        guard scale > 0, scale.isFinite else { return nil }

        // The whole frame is in the texture, so the quad is the whole frame drawn
        // at that scale — the region is selected by where it is centred and by the
        // view's own edges, not by a smaller quad.
        let drawnWidth = Double(imageWidth) * scale
        let drawnHeight = Double(imageHeight) * scale
        var matrix = simd_float4x4(diagonal: SIMD4<Float>(
            Float(drawnWidth / viewWidth), Float(drawnHeight / viewHeight), 1, 1))

        // Centre the region: shift the frame by how far the region's middle is
        // from the frame's, in points. Before the rotation, because the offset is
        // stated in the frame's own axes.
        // Centred on the *fitted* rectangle. It is the picture the reader
        // composed; the grown region around it is only the margin that keeps
        // the turned cell's corners fed, and centring on that margin would
        // shift the anatomy whenever clamping to the frame's edge made the
        // growth lopsided.
        let offsetX = (Double(imageWidth) / 2 - (fitted.x + fitted.width / 2)) * scale
        let offsetY = (Double(imageHeight) / 2 - (fitted.y + fitted.height / 2)) * scale
        if offsetX != 0 || offsetY != 0 {
            var translation = matrix_identity_float4x4
            translation.columns.3 = SIMD4<Float>(
                Float(2 * offsetX / viewWidth),
                Float(-2 * offsetY / viewHeight),  // view y grows downward, NDC upward
                0, 1
            )
            matrix = translation * matrix
        }

        if rotationDegrees != 0 {
            let radians = Float(-rotationDegrees * .pi / 180)
            let c = cos(radians), s = sin(radians)
            let rotation = simd_float4x4(
                SIMD4<Float>( c, s, 0, 0),
                SIMD4<Float>(-s, c, 0, 0),
                SIMD4<Float>( 0, 0, 1, 0),
                SIMD4<Float>( 0, 0, 0, 1)
            )
            // Rotate where one unit is the same distance on both axes — see the
            // viewer transform above for why NDC on its own will not do.
            let viewAspect = viewWidth / viewHeight
            let toSquare = simd_float4x4(diagonal: SIMD4<Float>(Float(viewAspect), 1, 1, 1))
            let fromSquare = simd_float4x4(diagonal: SIMD4<Float>(Float(1 / viewAspect), 1, 1, 1))
            matrix = fromSquare * rotation * toSquare * matrix
        }

        if flipHorizontal || flipVertical {
            let flip = simd_float4x4(diagonal: SIMD4<Float>(
                flipHorizontal ? -1 : 1, flipVertical ? -1 : 1, 1, 1))
            matrix = flip * matrix
        }

        // Stretch, last of all: the composed picture — cropped, turned, flipped,
        // centred — is pulled out to the view's edges on each axis independently,
        // which is what the film's stretch mode does to a finished cell. Applied
        // after the rotation so it stretches the *turned* picture to the cell,
        // as the printer-side composition does; before it, an anisotropic scale
        // would shear a turned image rather than stretch it.
        if stretchToFill {
            let fittedWidth = turnedWidth * scale
            let fittedHeight = turnedHeight * scale
            if fittedWidth > 0, fittedHeight > 0 {
                let stretch = simd_float4x4(diagonal: SIMD4<Float>(
                    Float(viewWidth / fittedWidth),
                    Float(viewHeight / fittedHeight), 1, 1))
                matrix = stretch * matrix
            }
        }

        return matrix
    }

    /// The box a rectangle occupies once turned, counting quarter turns only.
    ///
    /// A quarter turn swaps the sides; any other angle leaves the box alone,
    /// because a freely turned picture keeps its scale and loses its corners
    /// rather than shrinking to fit its own bounding rectangle. Exact at the
    /// quarter turns — `cos(90°)` is 6e-17 in binary floating point, and a crop
    /// that is a pixel out is a crop that disagrees with the film.
    static func quarterTurnedSize(
        width: Double, height: Double, degrees: Double
    ) -> (width: Double, height: Double) {
        let turns = quarterTurns(fromDegrees: degrees)
        guard abs(degrees - Double(turns) * 90) <= 1e-6 else { return (width, height) }
        return turns % 2 == 1 ? (height, width) : (width, height)
    }

    /// The full bounding box a rectangle occupies once turned by any angle.
    ///
    /// Not what the display fits — see ``quarterTurnedSize(width:height:degrees:)``
    /// — but still the honest answer to "how much room would this need to keep
    /// every corner", which the film's own geometry asks elsewhere.
    static func turnedSize(
        width: Double, height: Double, degrees: Double
    ) -> (width: Double, height: Double) {
        let turns = quarterTurns(fromDegrees: degrees)
        if abs(degrees - Double(turns) * 90) <= 1e-6 {
            return turns % 2 == 1 ? (height, width) : (width, height)
        }
        let radians = degrees * .pi / 180
        let c = abs(cos(radians)), s = abs(sin(radians))
        return (width * c + height * s, width * s + height * c)
    }

    /// Normalises any angle to 0–3 clockwise quarter turns.
    static func quarterTurns(fromDegrees degrees: Double) -> Int {
        guard degrees.isFinite else { return 0 }
        let turns = Int((degrees / 90).rounded()) % 4
        return turns < 0 ? turns + 4 : turns
    }
}
#endif
