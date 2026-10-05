// PrintViewModel+PresentationStates.swift
// DICOMStudio
//
// DICOM Studio — printing an image the way it was saved.
//
// A reader who saved "Lung window" on a slice has already decided how that
// slice should look; marking it for film and windowing it again by hand is the
// same decision made twice. This file lets a film cell adopt the presentation
// state stored for its image, either automatically as the sheet is composed or
// by name from the cell inspector.
//
// The translation itself is not repeated here. ``ViewerPresentationStateBridge``
// already turns a stored GSPS into window, zoom, pan, rotation, flip and
// inversion for the viewer, and a film cell wants exactly those fields — so the
// same call serves both, and a view that reads one way on screen cannot print
// another.
//
// Two things make a film cell different from a viewer tile, and both are
// handled below:
//
//   * The viewport is the cell, not the viewer's tile. Displayed Area is a
//     rectangle of source pixels, so it restores into whatever viewport it is
//     given — the cell's own size is passed, and the crop keeps the shape it
//     will print at.
//   * A cell the reader has adjusted by hand is left alone. Applying a stored
//     state over it would silently discard work done on the print screen, which
//     is the same rule ``PrintSelectionModel/adjustedIDs`` already enforces
//     against the viewer's re-syncs.

import Foundation
import DICOMKit
import DICOMCore
import DICOMPrintKit

#if canImport(CoreGraphics)
import CoreGraphics
#endif

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
extension PrintViewModel {

    // MARK: - What is available

    /// The saved views covering a mark's image, newest first.
    ///
    /// Empty when nothing was saved for it, when the study is unknown, or when
    /// the mark carries no SOP Instance UID — a mark made from the library
    /// without opening the file has no image identity to look a state up by.
    public func savedViews(forItemID itemID: String) -> [SavedView] {
        guard let item = selection.items.first(where: { $0.id == itemID }) else { return [] }
        return savedViews(for: item)
    }

    /// The saved views covering a mark's image, newest first.
    public func savedViews(for item: PrintSelectionItem) -> [SavedView] {
        guard let store = presentationStateStore,
              let studyInstanceUID = presentationStateStudyUID,
              let sopInstanceUID = item.sopInstanceUID,
              !sopInstanceUID.isEmpty else { return [] }
        return store.views(forStudy: studyInstanceUID, image: sopInstanceUID)
    }

    /// Whether any mark on film has a saved view to offer.
    ///
    /// What the job-wide control keys off: with nothing saved anywhere in the
    /// study, the toggle is a switch that cannot change the film, so the sheet
    /// hides it rather than showing a dead control.
    public var hasSavedViewsForAnyCell: Bool {
        guard presentationStateStore != nil, presentationStateStudyUID != nil else {
            return false
        }
        return printedItems.contains { !savedViews(for: $0).isEmpty }
    }

    /// The names of every saved view available across the marks on film.
    ///
    /// Offered by the job-wide picker. A label saved on only some images still
    /// appears: applying it gives those images their state and leaves the rest
    /// as they are, which is the same promise the viewer's picker makes.
    public var savedViewLabelsOnFilm: [String] {
        var seen = Set<String>()
        var labels: [String] = []
        for item in printedItems {
            for view in savedViews(for: item) where !seen.contains(view.label) {
                seen.insert(view.label)
                labels.append(view.label)
            }
        }
        return labels
    }

    /// How many cells on film a label can actually be applied to.
    ///
    /// The job-wide picker offers the *union* of labels across the sheet, which
    /// is right — a label saved over half a series should still be offerable —
    /// but it means a chosen label lands on some cells and does nothing on the
    /// rest. Silently. The picker shows this count beside each label so a
    /// partial match reads as a partial match rather than as a broken control,
    /// which is the complaint that has been made about every tool on this
    /// screen that quietly declined to act.
    public func cellCountCovered(byLabel label: String) -> Int {
        printedItems.filter { item in
            savedViews(for: item).contains { $0.label == label }
        }.count
    }

    /// How many cells on film carry a saved view at all.
    ///
    /// What the sheet says beside the switch, so "apply saved states" on a film
    /// where only three of twenty images were ever saved is honest about it
    /// before the reader goes looking for the other seventeen.
    public var cellCountWithSavedViews: Int {
        printedItems.filter { !savedViews(for: $0).isEmpty }.count
    }

    /// The saved view a cell is currently printing with, if it was applied from
    /// one and has not been adjusted since.
    public func appliedSavedViewLabel(forItemID itemID: String) -> String? {
        appliedSavedViews[itemID]
    }

    /// What the cell inspector's picker shows.
    public func savedViewSelectionLabel(forItemID itemID: String) -> String {
        appliedSavedViews[itemID] ?? Self.defaultViewLabel
    }

    /// What the picker calls the image as it was marked.
    ///
    /// Deliberately not the viewer's "Default view": on a film cell the state
    /// being returned to is the mark as the viewer made it, which already
    /// carries the reader's window and arrangement.
    public static let defaultViewLabel = "As marked"

    /// Why picking a saved view will not change the film, if it will not.
    ///
    /// A saved view is applied to the *mark*, and the job-wide settings are
    /// applied on top of it by ``previewItem(for:)``. So the write can land in
    /// full and still be discarded before it reaches a pixel — and picking a
    /// view then looks exactly like a broken control, which is the one thing
    /// this screen must never look like. The same reasoning as
    /// ``cellWindowingBlockedReason``, which says it for the windowing tools;
    /// this says it for the view picker, which sits outside their `.disabled`
    /// because a view is not only a window.
    ///
    /// Nil when a view can carry something, including the partial case: with a
    /// job-wide window on, the zoom and orientation still land, so the picker
    /// stays live and the caption says only the window is being overridden.
    public var savedViewBlockedReason: String? {
        if sendRawPixels {
            return "Raw pixels are being sent, so a saved view cannot change this film — "
                 + "neither its window nor its zoom and orientation are applied."
        }
        if useExplicitWindow {
            return "One window is set for the whole job, so a saved view's window is "
                 + "ignored. Its zoom, rotation and inversion still apply."
        }
        return nil
    }

    /// Whether a saved view can reach the film at all.
    ///
    /// False only when *nothing* it carries would survive — raw pixels. A
    /// job-wide window costs a view its window and keeps the rest, so the
    /// picker stays usable.
    public var savedViewsCanReachTheFilm: Bool { !sendRawPixels }

    // MARK: - Applying

    /// Applies a stored presentation state to one cell.
    ///
    /// - Parameters:
    ///   - view: The saved view to take the state from.
    ///   - itemID: The mark to write it into.
    ///   - cellSize: The cell the picture is drawn in, which becomes the
    ///     viewport the stored Displayed Area is restored against. Passing nil
    ///     keeps whatever viewport the mark already carried — honest, but the
    ///     crop is then the shape of the viewer tile it was marked in rather
    ///     than of the cell it will print in.
    /// - Returns: Whether anything was written.
    @discardableResult
    public func applySavedView(
        _ view: SavedView, toItemID itemID: String, cellSize: CGSize? = nil
    ) async -> Bool {
        guard let item = selection.items.first(where: { $0.id == itemID }),
              let sopInstanceUID = item.sopInstanceUID,
              let stored = view.state(forImage: sopInstanceUID) else { return false }

        // Displayed Area is stated in source pixels, so the restore needs the
        // frame's real size. Read once per file and kept — see ``pixelSizes``.
        let pixelSize = await pixelSize(forPath: item.filePath)
        // And its Photometric Interpretation: the state's Presentation LUT is
        // read against it (PS3.4 N.2 — INVERSE on a MONOCHROME1 image is the
        // upright picture). Through the same cache the renderer fills, so a
        // cell already on film costs nothing.
        let photometric = await FrameRenderer.photometricInterpretation(path: item.filePath)

        // The mark may have been unmarked or edited while the file was read.
        guard let item = selection.items.first(where: { $0.id == itemID }) else { return false }

        guard let updated = itemApplying(
            stored, to: item, cellSize: cellSize, pixelSize: pixelSize,
            photometricInterpretation: photometric) else { return false }

        // A hand adjustment, because it is one: the reader picked this view for
        // this cell, and the choice must survive the viewer's next re-sync the
        // same way a windowing drag does.
        selection.adjust(updated)
        appliedSavedViews[itemID] = view.label

        // The drawings come with the view, exactly as they do in the viewer.
        // Replacing rather than merging: the saved view is a complete statement
        // about the image, so an arrow deleted before saving must not survive.
        // The cell shows one frame, so it takes that frame's drawings — an
        // arrow on another frame of the same image belongs to that frame's
        // cell, not this one.
        selection.cellAnnotations[item.annotationKey] =
            stored.annotations(forImage: sopInstanceUID, frame: item.annotationKey.frameIndex)

        return true
    }

    /// Applies the saved view of a given name to a cell, if it has one.
    @discardableResult
    public func applySavedView(
        label: String, toItemID itemID: String, cellSize: CGSize? = nil
    ) async -> Bool {
        guard let view = savedViews(forItemID: itemID).first(where: { $0.label == label })
        else { return false }
        return await applySavedView(view, toItemID: itemID, cellSize: cellSize)
    }

    /// The source frame's pixel size, read once per file and kept.
    ///
    /// A film of sixteen cells off one series would otherwise re-read the same
    /// headers on every adoption pass.
    private func pixelSize(forPath path: String) async -> CGSize? {
        if let known = pixelSizes[path] { return known }
        guard let size = await FrameRenderer.pixelSize(path: path) else { return nil }
        pixelSizes[path] = size
        return size
    }

    /// Returns a cell to the mark as the viewer made it.
    ///
    /// The counterpart of picking "As marked": the stored state is taken back
    /// off, and the cell follows the viewer again.
    public func clearSavedView(forItemID itemID: String) {
        guard appliedSavedViews.removeValue(forKey: itemID) != nil else { return }
        selection.revertAdjustments(forID: itemID)
    }

    /// Takes every applied saved view back off, returning those cells to the
    /// marks the viewer made.
    ///
    /// What switching the job-wide control off does. Cells the reader adjusted
    /// by hand here never carried an applied view, so they are untouched.
    public func clearAllSavedViews() {
        for itemID in appliedSavedViews.keys {
            selection.revertAdjustments(forID: itemID)
        }
        appliedSavedViews.removeAll()
    }

    /// Gives every cell on film the saved view of a given name, where one exists.
    ///
    /// Cells whose image has no state under that label are left as they were —
    /// a label saved on three slices of a series says nothing about the fourth.
    /// - Returns: How many cells took it.
    @discardableResult
    public func applySavedViewToAllCells(label: String) async -> Int {
        var applied = 0
        for item in printedItems {
            if await applySavedView(label: label, toItemID: item.id) { applied += 1 }
        }
        return applied
    }

    // MARK: - Automatic adoption

    /// Gives each cell its image's saved view, without disturbing hand-made work.
    ///
    /// Run as the print screen opens and whenever the marks change, so a sheet
    /// composed from images that were saved a particular way opens looking that
    /// way. Three things are deliberately left alone:
    ///
    ///   * a cell the reader adjusted here, whose work this would discard;
    ///   * a cell already carrying the state that would be applied, so a redraw
    ///     is not a write;
    ///   * every cell, when the job-wide switch is off.
    ///
    /// Which state a cell adopts is ``defaultSavedViewLabel`` when the reader
    /// named one, and otherwise the image's most recently saved view — the same
    /// "newest first" order the viewer's picker lists.
    public func adoptSavedViewsWhereUntouched() async {
        guard applySavedPresentationStates else { return }
        guard presentationStateStore != nil, presentationStateStudyUID != nil else { return }

        for item in printedItems {
            // Every cell costs a suspension, and each write is observed by the
            // preview — which asks for adoption again. A superseded pass has to
            // stop rather than go on writing marks the newer pass is also
            // writing; without this the two interleave at every await and the
            // screen stops answering. `Task.isCancelled` rather than a throw:
            // a cancelled adoption is a completed no-op, not a failure.
            if Task.isCancelled { return }
            // The switch can be turned off while the pass is walking the film.
            guard applySavedPresentationStates else { return }
            // Hand-made work wins. `adjustedIDs` covers the print screen's own
            // tools; a cell this method applied a state to is flagged too, and
            // is filtered back in below so a *changed* default still lands.
            let appliedHere = appliedSavedViews[item.id]
            if selection.isAdjusted(item.id) && appliedHere == nil { continue }

            let available = savedViews(for: item)
            guard !available.isEmpty else { continue }

            let chosen: SavedView?
            if let label = defaultSavedViewLabel {
                chosen = available.first { $0.label == label }
            } else {
                // Newest first is the store's own order.
                chosen = available.first
            }
            guard let chosen else { continue }
            // Already showing it — nothing to write.
            guard appliedHere != chosen.label else { continue }

            // The cell the preview is drawing, when it has drawn one: a crop
            // restored against the viewer tile the mark was made in is the
            // wrong shape for the film.
            await applySavedView(chosen, toItemID: item.id, cellSize: lastCellSize)
        }
    }

    /// Drops adoption bookkeeping for marks that are no longer on film.
    ///
    /// Without this a mark unmarked and marked again would come back claiming a
    /// saved view it no longer carries, and the inspector would name a state the
    /// cell is not showing.
    public func pruneAppliedSavedViews() {
        let live = Set(selection.items.map(\.id))
        appliedSavedViews = appliedSavedViews.filter { live.contains($0.key) }
    }

    // MARK: - Translation

    /// One mark with a stored state folded into it.
    ///
    /// Nil when the state says nothing this mark can carry, which keeps
    /// ``applySavedView(_:toItemID:cellSize:)`` from flagging a cell as adjusted
    /// for a write that changed nothing.
    private func itemApplying(
        _ stored: StoredPresentationState,
        to item: PrintSelectionItem,
        cellSize: CGSize?,
        pixelSize: CGSize?,
        photometricInterpretation: String? = nil
    ) -> PrintSelectionItem? {
        // The viewport the state is restored against. The cell when the caller
        // knows it, else whatever the mark was composed in, else a square —
        // Displayed Area needs *some* viewport to become a zoom, and a mark made
        // from the library carries none.
        let existing = item.presentation
        let viewportWidth = cellSize.map { Double($0.width) }
            ?? existing?.viewportWidth ?? Self.fallbackViewportSide
        let viewportHeight = cellSize.map { Double($0.height) }
            ?? existing?.viewportHeight ?? Self.fallbackViewportSide

        let imageWidth = pixelSize.map { Int($0.width.rounded()) } ?? Int(viewportWidth.rounded())
        let imageHeight = pixelSize.map { Int($0.height.rounded()) } ?? Int(viewportHeight.rounded())

        let restored = ViewerPresentationStateBridge.restore(
            stored.state,
            imageWidth: max(1, imageWidth),
            imageHeight: max(1, imageHeight),
            viewportWidth: max(1, viewportWidth),
            viewportHeight: max(1, viewportHeight),
            covers: picturesCoverTheirCells,
            photometricInterpretation: photometricInterpretation)

        var presentation = ViewerPresentation(
            zoom: restored.zoom,
            panX: restored.panX,
            panY: restored.panY,
            viewportWidth: max(1, viewportWidth),
            viewportHeight: max(1, viewportHeight),
            rotationDegrees: restored.rotationDegrees,
            flipHorizontal: restored.flipHorizontal,
            // GSPS carries no vertical flip: the bridge folded it into the
            // rotation on the way out, so a restore is never flipped vertically.
            flipVertical: false,
            invert: restored.invert)

        // The view's own palette when it recorded one — the sidecar carries it
        // now, because a GSPS cannot say "coloured" (see the bridge — palettes
        // are absent from its vocabulary). A view that recorded none stays
        // silent about colour rather than against it, and the mark's palette
        // survives: a saved window applied to a PET cell must not grey the
        // cell out on the say-so of a view that never spoke of colour.
        presentation.palette = stored.palette ?? existing?.palette

        Self.clampPan(of: &presentation,
                      pixelSize: pixelSize,
                      covers: picturesCoverTheirCells)

        // Quantised for the same reason the cell tools quantise: a zoom that
        // differs in the fourth decimal is the same picture, and re-rendering
        // for it costs a frame without changing one.
        presentation.zoom = (presentation.zoom * 100).rounded() / 100
        presentation.panX = presentation.panX.rounded()
        presentation.panY = presentation.panY.rounded()

        // A GSPS VOI LUT is stated against the image's own stored values, which
        // is the space a mark's window off the viewer is already in. Saying so
        // explicitly stops a cell that had been given a preset — and so carried
        // output units — from reading the restored numbers in the wrong space.
        let hasWindow = restored.windowCenter != nil && restored.windowWidth != nil

        // Arranging a cell says the film should carry arrangements, and a stored
        // state is an arrangement. Without this the write lands in the mark and
        // is then dropped by `previewItem(for:)`, so applying a view would
        // appear to do nothing at all.
        if !useViewerPresentation && !sendRawPixels {
            useViewerPresentation = true
        }
        if hasWindow && !useViewerWindow && !sendRawPixels {
            useViewerWindow = true
        }

        return item.with(
            windowCenter: hasWindow ? .some(restored.windowCenter) : .none,
            windowWidth: hasWindow ? .some(restored.windowWidth) : .none,
            windowSpace: hasWindow ? .storedValues : item.windowSpace,
            presentation: .some(presentation))
    }

    /// Stands in as a viewport for a mark that never carried one.
    ///
    /// Square, so neither axis is favoured: the restored crop is then the shape
    /// the Displayed Area itself describes rather than one inherited from a
    /// viewport that was never real.
    static let fallbackViewportSide: Double = 512
}
