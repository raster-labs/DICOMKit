// PrintCellTextureCache.swift
// DICOMStudio
//
// DICOM Studio — GPU textures for the film preview's cells.
//
// The film preview is where a cell is *worked on*: window/level, zoom, pan,
// rotate and invert all run as drags over the picture, and every one of them used
// to re-render the cell on the CPU — decode-free but still a full windowing pass,
// an arrangement pass and a downscale per mouse delta. The GPU tile path exists
// precisely to remove that, and a preview being dragged has more claim on it than
// a tile sitting still.
//
// So this is `ViewerTileTextureCache`'s sibling, keyed for a print mark. It keys
// on what the shader cannot change — the file, the frame and the window — and
// nothing else: the arrangement is the display transform, so a zoom or a rotation
// re-draws a quad and re-renders nothing. Only a window change costs a render, and
// that one is a GPU dispatch rather than a pass over every pixel on the CPU.
//
// Textures are full-resolution GPU allocations, so only the film on screen holds
// them; paging to another film releases the last one's.
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data; Polarity REVERSE (2020,0020, PS3.3
// 2026a Table C.13-5) and the rendered-inverse Presentation LUT are composed into the shader's invert flag
// exactly as DICOMPrintKit's FilmComposer composes them on the sheet.

import Foundation
import DICOMNetwork
import DICOMPrintKit
import DICOMRenderKit

#if canImport(Metal)
import Metal

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@MainActor
@Observable
public final class PrintCellTextureCache {

    /// Textures in hand, by the mark state that produced them.
    private var textures: [String: DisplayFrameTexture] = [:]

    /// The last texture rendered for each mark, by identity rather than by state.
    ///
    /// A window/level drag changes the key on every delta, and the new texture
    /// takes a dispatch to arrive. Without a stand-in the cell would fall back to
    /// its CPU thumbnail for that moment — which is not merely a flicker: the
    /// thumbnail for the new window does not exist either, so a drag would kick off
    /// a CPU render per delta, the exact cost this path removes. The previous
    /// picture stands in instead, and is replaced the instant the new one lands.
    private var standIns: [String: DisplayFrameTexture] = [:]

    /// Marks that cannot be put on the GPU — a burned overlay plane, a window that
    /// only the CPU's auto-windowing can resolve, YBR pixels, no Metal device.
    /// Remembered so a cell falls to the CPU path once and stays there instead of
    /// re-attempting on every refresh.
    private var unavailable: Set<String> = []

    /// Renders in flight, so a cell is not rendered twice while it loads.
    private var inFlight: Set<String> = []

    /// The cells the preview is currently showing. A render that finishes after
    /// its film has been paged away is discarded rather than retained.
    private var live: Set<String> = []

    /// The marks the preview is currently showing, by identity.
    ///
    /// Separate from ``live`` because the two answer different questions. A
    /// window/level drag gives the cell a new key on every mouse event, so by
    /// the time a render lands its key is usually no longer live — but the
    /// *mark* still is, and its picture is still wanted. Judging those renders
    /// by key alone threw every one of them away and left the cell being dragged
    /// frozen on the picture it started from, while the cells beside it — whose
    /// windows move in rounded steps and so keep a key long enough — updated
    /// normally.
    private var liveIdentities: Set<String> = []

    public init() {}

    /// Whether the GPU cell path can run at all on this machine.
    public static var isAvailable: Bool {
        FrameRenderService.shared.displayRenderer != nil
    }

    /// The texture for a mark, or `nil` if it has never been rendered or cannot be
    /// shown on the GPU. A `nil` is the caller's cue to draw the CPU thumbnail.
    ///
    /// While a mark is being re-windowed the previous texture stands in, so the
    /// cell keeps showing the picture through the gesture.
    public func texture(for item: PrintSelectionItem) -> DisplayFrameTexture? {
        textures[Self.key(for: item)] ?? standIns[item.id]
    }

    /// The texture rendered for this exact state, with no stand-in.
    ///
    /// The stand-in exists so a cell does not blink during a drag; anything asking
    /// "has *this* window been rendered yet?" — a test, or a caller waiting for the
    /// picture to settle — must not be answered with the previous one.
    public func renderedTexture(for item: PrintSelectionItem) -> DisplayFrameTexture? {
        textures[Self.key(for: item)]
    }

    /// Whether this mark is known not to work on the GPU, so the caller can stop
    /// waiting and show its CPU thumbnail rather than a spinner.
    public func isUnavailable(_ item: PrintSelectionItem) -> Bool {
        unavailable.contains(Self.key(for: item))
    }

    /// Renders textures the given marks still need, and releases the rest.
    ///
    /// Pass only the marks on the film being shown. A hundred-image selection is
    /// a hundred full-resolution textures if this is handed the whole thing, and
    /// the preview draws one film at a time.
    public func refresh(for items: [PrintSelectionItem]) {
        live = Set(items.map { Self.key(for: $0) })
        liveIdentities = Set(items.map(\.id))

        textures = textures.filter { live.contains($0.key) }
        standIns = standIns.filter { liveIdentities.contains($0.key) }
        unavailable.formIntersection(live)
        inFlight.formIntersection(live)

        for item in items {
            let key = Self.key(for: item)
            guard textures[key] == nil,
                  !unavailable.contains(key),
                  !inFlight.contains(key) else { continue }

            inFlight.insert(key)
            Task { [weak self] in
                let rendered = await FrameRenderer.renderDisplayTexture(
                    path: item.filePath,
                    frameIndex: item.frameIndex,
                    windowCenter: item.windowCenter,
                    windowWidth: item.windowWidth,
                    windowSpace: item.windowSpace,
                    palette: item.presentation?.palette)
                guard let self else { return }
                self.inFlight.remove(key)
                // The film this cell was on may have been paged away, or the
                // mark taken off the film entirely, while it rendered.
                guard self.liveIdentities.contains(item.id) else { return }
                if let rendered {
                    // Only the state still on screen is worth the GPU
                    // allocation; a superseded window is not kept as a texture.
                    if self.live.contains(key) {
                        self.textures[key] = rendered
                    }
                    // It is still the best stand-in there is, though — one
                    // mouse event behind the drag rather than frozen at the
                    // window the drag began from.
                    self.standIns[item.id] = rendered
                } else if self.live.contains(key) {
                    self.unavailable.insert(key)
                    // Nothing to stand in for a cell the GPU will not take: it
                    // draws the CPU thumbnail, and a stale texture over that would
                    // be a picture of the wrong window.
                    self.standIns[item.id] = nil
                }
            }
        }
    }

    /// Forgets everything, e.g. when the preview closes.
    public func clear() {
        textures = [:]
        standIns = [:]
        unavailable = []
        inFlight = []
        liveIdentities = []
        live = []
    }

    /// Everything about a mark that changes its *pixels*.
    ///
    /// Deliberately not the arrangement. Zoom, pan, rotation, flip and inversion
    /// are the display shader's transform here, so including them would re-render
    /// a texture that did not need to change — the exact cost this path exists to
    /// remove. The window *space* is in the key because the same two numbers are
    /// two different pictures in stored values and in output units.
    ///
    /// The palette is pixels, not arrangement, and so it *is* here: the shader
    /// has no colour table, the render bakes the ramp into the texture, and a
    /// key without it served the previous palette's texture back after every
    /// change — which looked exactly like the picker doing nothing.
    static func key(for item: PrintSelectionItem) -> String {
        let centre = item.windowCenter.map { String($0) } ?? "-"
        let width = item.windowWidth.map { String($0) } ?? "-"
        let space = item.windowCenter == nil ? "-" : item.windowSpace.rawValue
        let palette = item.presentation?.palette?.rawValue ?? "-"
        return "\(item.filePath)|\(item.frameIndex)|\(centre)|\(width)|\(space)|\(palette)"
    }
}

// MARK: - Geometry

/// Where a mark's picture lands in its cell, on the GPU path.
///
/// The film preview's promise is that a cell which looks right prints that way, so
/// the shader is given the *film's* geometry and not the viewer's. The region is
/// resolved by ``ViewerPresentation/visibleRegion(imageWidth:imageHeight:)`` — the
/// single place that decision is made, and the same call the print path makes —
/// and handed to the display transform, which fits and centres it exactly as the
/// printer fits it into an image box.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public enum PrintCellDisplay {

    /// The shader geometry for a mark over a frame of the given size.
    ///
    /// - Parameter fillingCellOfSize: when set, the region is cropped to the
    ///   cell's aspect (SRS FR-003 fill-to-film) so the shader's centred fit
    ///   covers the cell exactly — the fill happens in the source region, and
    ///   the view showing it never has to change size.
    /// - Parameter presentationLUTShape: the film's Presentation LUT. A
    ///   rendered inverse flips the cell, composing with the per-cell invert
    ///   exactly as the two inversions compose on the printed film, so a cell
    ///   already inverted comes back to normal polarity under it. Pass `nil`
    ///   for cells whose pixels leave as colour — the preparer's inversion
    ///   only runs on greys, and the preview must not invert what the film
    ///   will not.
    /// - Parameter polarityInverted: the film box's Polarity (2020,0020) is
    ///   REVERSE. Applied by the printer to every image box — colour, grey and
    ///   raw alike — and composed here the same way.
    /// - Parameter desaturated: the job flattens this colour cell to greys
    ///   ("Print colour images as greys"), so the cell is shown as the Rec.601
    ///   luminance the film will carry.
    public static func presentation(
        for item: PrintSelectionItem, imageWidth: Int, imageHeight: Int,
        fillingCellOfSize cellSize: CGSize? = nil,
        stretchingToCell: Bool = false,
        presentationLUTShape: DICOMNetwork.PresentationLUTShape? = nil,
        polarityInverted: Bool = false,
        desaturated: Bool = false
    ) -> DisplayPresentation {
        let arrangement = item.presentation
        // A filling cell reads its region with the covering geometry: the crop
        // is smaller than the image even unzoomed, and the pan chooses which
        // part shows. Read as fitted, the region came back "the whole image",
        // the fill crop below re-centred it, and the pan a filled cell stored
        // never moved anything on screen.
        let region = arrangement?.visibleRegion(
            imageWidth: imageWidth, imageHeight: imageHeight,
            covers: cellSize != nil)
        // No region means the whole frame is on the film — which the transform
        // states as the frame's own rectangle rather than as a special case.
        var source = DisplayPresentation.SourceRegion(
            x: Double(region?.x ?? 0),
            y: Double(region?.y ?? 0),
            width: Double(region?.width ?? imageWidth),
            height: Double(region?.height ?? imageHeight))
        if let cellSize, cellSize.width > 0, cellSize.height > 0 {
            source = fillCrop(
                of: source,
                cellAspect: Double(cellSize.width / cellSize.height),
                quarterTurns: arrangement.map {
                    ViewerPresentation.quarterTurns(fromDegrees: $0.rotationDegrees)
                } ?? 0)
        }
        // Off-square, the cell's corners need pixels the fitted rectangle does
        // not contain. Grow the sampled region to the turned bounding box —
        // clamped to the frame, because pixels outside it do not exist — and
        // hand the fitted rectangle along separately so the scale is still the
        // upright one. Upright and at the quarter turns the two are identical
        // and nothing about the geometry changes.
        let sampled = Self.grownToCoverTurnedCell(
            source, degrees: arrangement?.rotationDegrees ?? 0,
            imageWidth: imageWidth, imageHeight: imageHeight)
        return DisplayPresentation(
            // The angle itself, not the nearest quarter turn: the viewer's
            // rotate tool turns freely and the film now follows it.
            rotationDegrees: arrangement?.rotationDegrees ?? 0,
            flipHorizontal: arrangement?.flipHorizontal ?? false,
            flipVertical: arrangement?.flipVertical ?? false,
            invert: ((arrangement?.invert ?? false)
                != (presentationLUTShape?.invertsPixels ?? false))
                != polarityInverted,
            desaturate: desaturated,
            // Bilinear: a film cell is judged as a picture on a panel-scaled
            // sheet, and its CPU-drawn neighbours are smoothed — the viewer's
            // pixel-exact nearest sampling belongs to the viewer.
            linearFiltering: true,
            sourceRegion: sampled,
            // Stretch keeps the fitted region — it distorts, it does not crop —
            // and the shader pulls the composed picture out to the cell's edges.
            stretchToFill: stretchingToCell,
            fittedRegion: source
        )
    }

    /// A region grown to the bounding box its own turned rectangle sweeps,
    /// held inside the frame.
    ///
    /// What this buys is the corners. A freely turned cell keeps the scale it
    /// had upright — the anatomy must not shrink as the rotate tool is dragged
    /// — so the turned rectangle no longer covers the cell, and the wedges it
    /// leaves had nothing over them but the shader's black. The frame very
    /// often *has* those pixels, and this is what asks for them; because the
    /// fit is still measured on the ungrown rectangle, the extra simply falls
    /// outside the cell and is cropped.
    ///
    /// The growth itself is `ViewerPresentation.regionCoveringTurnedCell` — the
    /// same call the print path makes, so the preview and the film crop alike.
    /// This only carries it across the two rectangle types.
    static func grownToCoverTurnedCell(
        _ region: DisplayPresentation.SourceRegion,
        degrees: Double, imageWidth: Int, imageHeight: Int
    ) -> DisplayPresentation.SourceRegion {
        guard region.width > 0, region.height > 0,
              imageWidth > 0, imageHeight > 0 else { return region }
        let pixels = PixelRegion(
            x: Int(region.x.rounded(.down)), y: Int(region.y.rounded(.down)),
            width: max(1, Int(region.width.rounded())),
            height: max(1, Int(region.height.rounded())))
        let grown = ViewerPresentation(rotationDegrees: degrees)
            .regionCoveringTurnedCell(
                pixels, imageWidth: imageWidth, imageHeight: imageHeight)
        guard grown != pixels else { return region }
        return DisplayPresentation.SourceRegion(
            x: Double(grown.x), y: Double(grown.y),
            width: Double(grown.width), height: Double(grown.height))
    }

    /// The centred crop of a source region that matches a cell's aspect —
    /// fill-to-film, stated in source pixels.
    ///
    /// The comparison happens on the region as it will be *after* turning: a
    /// quarter turn makes a wide crop a tall one, so the aspect the cell must
    /// be matched against swaps with it. The crop is centred; a non-centre
    /// alignment shows in the composed film, where the fitter places it.
    static func fillCrop(
        of region: DisplayPresentation.SourceRegion,
        cellAspect: Double,
        quarterTurns: Int
    ) -> DisplayPresentation.SourceRegion {
        guard region.width > 0, region.height > 0, cellAspect > 0 else { return region }
        let odd = quarterTurns % 2 == 1
        // The aspect the *unturned* region must have for its turned form to
        // match the cell.
        let target = odd ? 1 / cellAspect : cellAspect
        let aspect = region.width / region.height
        var cropped = region
        if aspect > target {
            // Too wide: narrow it, keeping the centre.
            cropped.width = region.height * target
            cropped.x += (region.width - cropped.width) / 2
        } else if aspect < target {
            cropped.height = region.width / target
            cropped.y += (region.height - cropped.height) / 2
        }
        return cropped
    }

    /// The size, in source pixels, of the picture this cell actually prints:
    /// the visible region, with its axes swapped on a quarter turn.
    ///
    /// This is what decides the picture's shape inside the cell, and so where the
    /// reader's annotations anchor — the margin either side of a fitted picture is
    /// not part of the image and the printer has no pixels there.
    public static func arrangedPixelSize(
        for item: PrintSelectionItem, imageWidth: Int, imageHeight: Int
    ) -> (width: Int, height: Int) {
        let arrangement = item.presentation
        let region = arrangement?.visibleRegion(imageWidth: imageWidth, imageHeight: imageHeight)
        let width = region?.width ?? imageWidth
        let height = region?.height ?? imageHeight
        guard let arrangement else { return (width, height) }
        // Quarter turns swap the axes; a free angle does not change the shape at
        // all. The picture turns about its centre at the size it already had and
        // the corners that leave the cell are cut — on screen and on film alike
        // — so the rectangle the film carries is still the region's own.
        guard arrangement.isQuarterTurn else { return (width, height) }
        return arrangement.quarterTurns % 2 == 1 ? (height, width) : (width, height)
    }
}
#endif
