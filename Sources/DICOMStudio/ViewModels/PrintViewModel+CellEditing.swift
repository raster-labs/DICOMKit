// PrintViewModel+CellEditing.swift
// DICOMStudio
//
// DICOM Studio — adjusting a single film cell from inside the print preview.
//
// Windowing a cell on the film is the last chance to fix a picture before it is
// committed to a sheet, and it is where the user is already looking. Every edit
// here writes back into the mark itself, which is the same field
// ``PrintService/prepare(items:request:useViewerWindow:applyViewerPresentation:onProgress:)``
// reads — so the preview cannot drift away from the film. Nothing here renders,
// and nothing here is print-only state.
//
// NEMA-verified: 2026a, checked 2026-10-06 — a seeded (and reset-to-seed) cell window is DICOMKit determineModalityWindow's, in modality units, and carries windowSpace .outputUnits (PS3.3 C.11.2.1.2.1; A6 / D65);
// the colour test reads Samples per Pixel (0028,0002) first and falls back
// to Photometric Interpretation, treating MONOCHROME1 and MONOCHROME2 (PS3.3 2026a C.7.6.3.1.2 terms) as
// grey — the rule PS3.3 Table C.13-5 fixes for the Basic Color Image Box (RGB, 3 samples). Polarity REVERSE
// (2020,0020) and the Presentation LUT inverse compose as FilmComposer composes them; no other literal.

import Foundation
import DICOMCore
import DICOMKit
import DICOMPrintKit

#if canImport(CoreGraphics)
import CoreGraphics
#endif

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
extension PrintViewModel {

    // MARK: - What the preview must show

    /// The marks as they will actually print, with the job-wide settings folded in.
    ///
    /// The preview renders these rather than the raw marks: a job-wide explicit
    /// window, or `useViewerWindow`/`useViewerPresentation` switched off, changes
    /// what the printer receives, and a preview still showing the mark's own
    /// arrangement would be quietly lying about the film.
    public var previewItems: [PrintSelectionItem] {
        printedItems.map(previewItem(for:))
    }

    /// One mark resolved against the job-wide settings.
    public func previewItem(for item: PrintSelectionItem) -> PrintSelectionItem {
        // Raw sends stored pixels: no window, no arrangement, by definition.
        if sendRawPixels {
            return item.with(windowCenter: .some(nil), windowWidth: .some(nil),
                             presentation: .some(nil))
        }
        let center: Double? = useExplicitWindow ? explicitWindowCenter
                            : (useViewerWindow ? item.windowCenter : nil)
        let width: Double? = useExplicitWindow ? explicitWindowWidth
                           : (useViewerWindow ? item.windowWidth : nil)
        // The job-wide window is typed by a user, so it is in output units (HU);
        // the mark's own window came off the viewer, which holds stored values.
        // Rendering one as the other puts the window nowhere near the pixels and
        // washes the cell out, so which it is travels with the numbers.
        var presentation = useViewerPresentation ? item.presentation : nil
        // "Print colour images as greys" drops the palette for colour sources
        // before preparation (see `PrintImagePreparer.preparationPalette`), so
        // the preview's texture must lose it too — a Hot-Iron thumbnail of a
        // cell that prints as the picture's own greys is the preview lying.
        if presentation?.palette != nil, cellIsFlattenedToGrey(item) {
            presentation?.palette = nil
        }
        return item.with(
            windowCenter: .some(center),
            windowWidth: .some(width),
            windowSpace: useExplicitWindow ? .outputUnits : item.windowSpace,
            presentation: .some(presentation))
    }

    /// Whether the job deliberately flattens this cell's colour to greys.
    ///
    /// True only for colour *sources* under "Print colour images as greys" on a
    /// processed job: raw sends stored pixels untouched, and a monochrome cell
    /// has no colour to flatten — a pseudo-colour palette on one is a deliberate
    /// act the toggle does not speak to.
    public func cellIsFlattenedToGrey(_ item: PrintSelectionItem) -> Bool {
        !sendRawPixels && !preservesSourceColor
            && (sourceIsColorByPath[item.filePath] ?? false)
    }

    /// Whether this cell's prepared pixels leave the app in colour.
    ///
    /// The per-cell truth behind ``willPrintInColor``: colour sources keep their
    /// colour unless the job flattens them, and a non-grey pseudo-colour palette
    /// puts colour into a monochrome cell. Mirrors
    /// `PrintImagePreparer.preparationColorMode` so the preview and the film
    /// agree cell by cell.
    public func cellPrintsInColor(_ item: PrintSelectionItem) -> Bool {
        let sourceIsColor = sourceIsColorByPath[item.filePath] ?? false
        // Raw copies the source descriptor: colour stays colour, grey stays
        // grey, and the palette never applies.
        if sendRawPixels { return sourceIsColor }
        if cellIsFlattenedToGrey(item) { return false }
        if sourceIsColor { return true }
        if useViewerPresentation, let palette = item.presentation?.palette,
           !palette.isGrayscale { return true }
        return false
    }

    /// The film-wide inversion composed over a cell's own invert.
    ///
    /// Two independent switches flip a cell beyond its invert tool, and they
    /// compose (each flips the sense of the other) exactly as
    /// `FilmComposer.shouldInvert` composes them on the sheet:
    ///
    ///   * Polarity REVERSE (2020,0020) — applied by the printer to every image
    ///     box, colour and grey alike, raw included.
    ///   * A rendered-inverse Presentation LUT — realised in the pixels by the
    ///     preparer, which only inverts cells leaving as greys (inverting only
    ///     the luminance of a colour cell would change its hue) and never runs
    ///     on a raw job.
    public func filmWideInversion(for item: PrintSelectionItem) -> Bool {
        var inverts = polarity == .reverse
        if !sendRawPixels, presentationLUTShape?.invertsPixels == true,
           !cellPrintsInColor(item) {
            inverts.toggle()
        }
        return inverts
    }

    /// Whether a job-wide window is overriding every cell's own window.
    ///
    /// While this is on, editing one cell changes nothing on film, so the
    /// preview says so rather than accepting edits that will be discarded.
    public var isCellWindowingOverridden: Bool {
        sendRawPixels || useExplicitWindow
    }

    /// Why cell windowing is currently unavailable, if it is.
    public var cellWindowingBlockedReason: String? {
        if sendRawPixels {
            return "Raw pixels are being sent — windowing is not applied to this job."
        }
        if useExplicitWindow {
            return "One window is set for the whole job, so per-image windows are ignored."
        }
        return nil
    }

    // MARK: - Identification

    /// The identification each marked file carries, keyed by path.
    ///
    /// The same lines the preview overlays — patient, ID and study date, the
    /// study description, and what made the picture — so film, screen and
    /// preview all say the same thing about whose study this is.
    ///
    /// Read here rather than taken from the preview's cache: printing must not
    /// depend on whether the user happened to look at the preview first, and a
    /// missing caption is not something to discover on the film.
    public func identificationTexts(
        for items: [PrintSelectionItem]
    ) async -> [String: PatientOverlayText] {
        var result: [String: PatientOverlayText] = [:]
        for path in Set(items.map(\.filePath)).sorted() {
            let text = await Task.detached(priority: .userInitiated) { () -> PatientOverlayText? in
                guard let data = FileManager.default.contents(atPath: path),
                      let file = try? DICOMFile.read(from: data, force: true) else { return nil }
                return PatientOverlayText.make(from: file.dataSet)
            }.value
            guard let text, !text.isEmpty else { continue }
            result[path] = text
        }
        return result
    }

    // MARK: - Source colour

    /// Reads Samples per Pixel out of every marked file that has not been read
    /// yet, so ``PrintViewModel/resolvedColorMode`` can tell a colour study from
    /// a monochrome one.
    ///
    /// Only the header is parsed — the pixels are not decoded — so this stays
    /// cheap enough to run whenever the marks change. Files already in the cache
    /// are skipped, and a file that cannot be read is recorded as monochrome
    /// rather than retried on every redraw.
    public func refreshSourceColor() async {
        let paths = Set(printedItems.map(\.filePath))
            .filter { sourceIsColorByPath[$0] == nil }
        guard !paths.isEmpty else { return }

        for path in paths.sorted() {
            let isColor = await Task.detached(priority: .utility) { () -> Bool in
                guard let data = FileManager.default.contents(atPath: path),
                      let file = try? DICOMFile.read(from: data, force: true) else { return false }
                // Samples per Pixel is the attribute the Image Box is validated
                // against, so it is the one that decides the SOP class. The
                // photometric interpretation is the fallback for files that omit
                // it — PALETTE COLOR in particular stores one sample per pixel
                // and still prints in colour.
                let ds = file.dataSet
                if let samples = ds.uint16(for: .samplesPerPixel), samples > 1 { return true }
                guard let photometric = ds.string(for: .photometricInterpretation) else { return false }
                let normalized = photometric.trimmingCharacters(in: .whitespaces).uppercased()
                return normalized != "MONOCHROME1" && normalized != "MONOCHROME2"
            }.value
            setSourceIsColor(isColor, forPath: path)
        }
    }

    /// How each film of a job states its identification, in film order.
    ///
    /// Under each image, or — when identification is switched off, or nothing
    /// could be read from the files — not at all. A caption states the technique
    /// of the image it sits under as well as the patient, and that differs from
    /// cell to cell, so there is nothing a single footer could say for a whole
    /// sheet. The rule lives in ``FilmIdentificationPlanner``, shared with the
    /// preview and the composer so all three agree.
    public func filmIdentifications(
        for items: [PrintSelectionItem],
        texts: [String: PatientOverlayText],
        plan: PrintPlan
    ) -> [FilmIdentification] {
        guard showPatientIdentification else {
            return Array(repeating: .none, count: max(0, plan.filmCount))
        }
        return (0..<max(0, plan.filmCount)).map { filmIndex in
            let sources = plan.imageIndices(onFilm: filmIndex).compactMap { index -> FilmIdentificationSource? in
                guard items.indices.contains(index) else { return nil }
                let item = items[index]
                let text = texts[item.filePath]
                return FilmIdentificationSource(
                    key: item.id,
                    studyKey: text?.studyInstanceUID ?? "",
                    lines: text?.lines ?? [])
            }
            return FilmIdentificationPlanner.identification(for: sources, placement: .perImage)
        }
    }

    /// The corner text to burn into each mark's pixels, keyed by mark ID.
    ///
    /// Burned rather than sent as annotation boxes: a DICOM printer lays those
    /// out to its own configured format and many ignore them, and a caption that
    /// names the slice it stands on is no use anywhere but on that slice.
    public func identificationBurns(
        for items: [PrintSelectionItem],
        texts: [String: PatientOverlayText],
        identifications: [FilmIdentification],
        plan: PrintPlan
    ) -> [String: PrintCornerAnnotation] {
        var result: [String: PrintCornerAnnotation] = [:]
        for filmIndex in 0..<max(0, plan.filmCount) {
            let identification = filmIndex < identifications.count
                ? identifications[filmIndex] : .perImage
            guard identification != .none else { continue }
            for index in plan.imageIndices(onFilm: filmIndex) {
                guard items.indices.contains(index) else { continue }
                let item = items[index]
                guard let corners = texts[item.filePath]?
                    .corners(including: identificationFields),
                    !corners.isEmpty else { continue }
                result[item.id] = corners
            }
        }
        return result
    }

    // MARK: - Focus

    /// The cell the preview's tools act on, identified by its mark.
    public var focusedItem: PrintSelectionItem? {
        guard let focusedItemID else { return nil }
        return selection.items.first { $0.id == focusedItemID }
    }

    /// Focuses a cell, or clears the focus when passed `nil`.
    public func focusCell(_ itemID: String?) {
        focusedItemID = itemID
    }

    /// Records the size a cell is being drawn at, for controls that live
    /// outside the preview.
    ///
    /// The preview owns the cell geometry — every tool is handed it at the
    /// point of the drag — but the settings sidebar has none, and a saved-view
    /// restore needs a viewport: Displayed Area is a rectangle of source pixels
    /// and only becomes a zoom against one. Restoring against the mark's old
    /// viewer tile instead gives the crop the shape of a tile the film will
    /// never have. So the preview reports the cell it drew and the sidebar
    /// restores against the cell the picture will actually print in.
    public func recordCellSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, lastCellSize != size else { return }
        lastCellSize = size
    }

    /// Drops the focus if the focused mark is no longer on film.
    ///
    /// "On film" is ``printedItems`` — the marks the films actually carry — not
    /// the raw selection: an image range can hide a mark without unmarking it,
    /// and a focus ring on a cell no sheet is showing decides where the next
    /// keyboard reset or delete lands, invisibly.
    public func pruneFocus() {
        if let focusedItemID, !printedItems.contains(where: { $0.id == focusedItemID }) {
            self.focusedItemID = nil
        }
    }

    // MARK: - Windowing

    /// The window a mark is currently printing with, once it is known.
    public func window(forItemID itemID: String) -> WindowSettings? {
        guard let item = selection.items.first(where: { $0.id == itemID }),
              let center = item.windowCenter, let width = item.windowWidth else { return nil }
        return WindowSettings(center: center, width: width)
    }

    /// Gives a mark a concrete window if it has none, without changing the picture.
    ///
    /// A mark made without ever opening the file (marking a whole series, say)
    /// carries no window, and the cell is rendered with the file's own. An edit
    /// has to start from those same values or the first drag would jump; this
    /// resolves them through the shared export policy the renderer uses.
    public func seedWindowIfNeeded(forItemID itemID: String) async {
        #if canImport(CoreGraphics)
        guard let item = selection.items.first(where: { $0.id == itemID }),
              item.windowCenter == nil || item.windowWidth == nil else { return }
        guard let resolved = await FrameRenderer.resolvedWindow(
            path: item.filePath, frameIndex: item.frameIndex) else { return }
        // The mark may have been unmarked or edited while the file was read.
        guard let current = selection.items.first(where: { $0.id == itemID }),
              current.windowCenter == nil || current.windowWidth == nil else { return }
        // Seeding is not an edit: the values are the ones already on screen, so
        // the mark is not flagged as hand-adjusted by having been picked up.
        // The resolved window is in modality units (A6 / D65), so the mark carries
        // that space and the renderer applies it without a rescale round trip.
        selection.update(current.with(
            windowCenter: .some(resolved.center), windowWidth: .some(resolved.width),
            windowSpace: FrameRenderer.resolvedWindowSpace),
                         force: true)
        // Remembered so ``isCellEdited(_:)`` does not mistake the seed for an
        // edit — see ``seededWindows``.
        seededWindows[itemID] = WindowSettings(
            center: resolved.center, width: resolved.width)
        #endif
    }

    /// Sets a mark's window. Width is held at 1 or more — a zero-width window is
    /// not a picture.
    public func setWindow(forItemID itemID: String, center: Double, width: Double) {
        guard let item = selection.items.first(where: { $0.id == itemID }) else { return }
        guard center.isFinite, width.isFinite else { return }
        // Read before the write: a synchronised edit is carried to the other
        // cells as a proportion of this one's change, which is gone once the
        // new numbers are in. See `PrintViewModel+CellSync.swift`.
        let previous = window(forItemID: itemID)
        // Rounded to whole units. A drag emits a window value per mouse event
        // and each distinct value is a re-render; fractions of a Hounsfield unit
        // change no pixel, so they are quantised away before they can queue up.
        let current = WindowSettings(center: center.rounded(), width: max(1, width.rounded()))
        // The space is whatever the cell's window was already in: a drag nudges
        // the numbers, it does not move them between spaces. Writing the default
        // here would relabel a preset's HU values as stored values mid-drag.
        selection.adjust(item.with(
            windowCenter: .some(current.center),
            windowWidth: .some(current.width),
            windowSpace: item.windowSpace))
        if let previous {
            propagateWindowDelta(from: itemID, previous: previous, current: current)
        }
    }

    /// Nudges a mark's window, as a window/level drag does.
    public func adjustWindow(forItemID itemID: String, deltaCenter: Double, deltaWidth: Double) {
        guard let current = window(forItemID: itemID) else { return }
        setWindow(forItemID: itemID,
                  center: current.center + deltaCenter,
                  width: current.width + deltaWidth)
    }

    /// Applies a preset to a mark.
    ///
    /// A preset is copied to synchronised cells as the window it is, not as the
    /// change it made here: "lung" names a tissue, and the cells beside this one
    /// should show that tissue too.
    public func applyWindowPreset(_ preset: WindowLevelPreset, toItemID itemID: String) {
        let window = WindowSettings(center: preset.center, width: preset.width)
        guard let item = selection.items.first(where: { $0.id == itemID }) else { return }
        // A preset states output units — a CT "Lung" is −600 HU, not a stored
        // value. On a CT with a −1024 Rescale Intercept, −600 read as a stored
        // value sits below every pixel and the cell washes out to white, so the
        // space travels with the numbers and the renderer converts through the
        // file's own rescale pair.
        selection.adjust(item.with(
            windowCenter: .some(window.center.rounded()),
            windowWidth: .some(max(1, window.width.rounded())),
            windowSpace: .outputUnits))
        propagateWindowAbsolute(from: itemID, window: window, space: .outputUnits)
    }

    /// Gives every cell **on the focused cell's film** that cell's window.
    ///
    /// Bounded to one sheet, like every other cell-to-cell edit here — see
    /// ``PrintCellSyncScope``, whose whole premise is that an edit stops at the
    /// edge of the sheet being judged. This wrote `selection.items` instead:
    /// every mark in the job, so "Apply to All" on a four-cell sheet of a
    /// 300-image job rewrote all 300 marks, 296 of them on films the reader
    /// could not see and had not turned to. The menu item and the button both
    /// say "on film"/"every image on film", so the promise was already this one
    /// — only the loop disagreed.
    ///
    /// It is also what made the action expensive: each write is observed, and
    /// the preview reacts to a changed mark list, so the cost scaled with the
    /// whole job rather than with the sheet in front of the reader.
    ///
    /// The job-wide explicit window is switched off as part of this: the two are
    /// the same intent expressed twice, and leaving the override on would make
    /// every cell ignore the values just written to it.
    public func applyFocusedWindowToAllCells() {
        guard let focusedItemID, let window = window(forItemID: focusedItemID) else { return }
        // The numbers only mean what their space says they mean, so the copy
        // carries the focused cell's space with them — HU stays HU.
        let space = focusedItem?.windowSpace ?? .storedValues
        useExplicitWindow = false
        for item in cellsOnFilm(containing: focusedItemID) {
            selection.adjust(item.with(
                windowCenter: .some(window.center), windowWidth: .some(window.width),
                windowSpace: space))
        }
    }

    /// Copies the focused cell's window into the job-wide explicit window fields.
    public func liftFocusedWindowToJob() {
        guard let focusedItemID, let window = window(forItemID: focusedItemID) else { return }
        explicitWindowCenter = window.center
        explicitWindowWidth = window.width
    }

    // MARK: - Zoom, pan and orientation

    /// Zooms a cell about its centre.
    ///
    /// - Parameter cellSize: the size the cell is drawn at, which stands in as
    ///   the viewport for marks that never carried one (marked from the library
    ///   rather than composed on screen). Zoom and pan are meaningless without a
    ///   viewport — see ``ViewerPresentation/visibleRegion(imageWidth:imageHeight:)``.
    /// - Parameter pixelSize: the source frame's own size, when the caller knows
    ///   it, so the pan can be held to what the image covers. Without it the
    ///   cell is assumed to be filled by the image, which bounds the pan on the
    ///   tight axis and is no worse than not bounding it at all.
    public func adjustZoom(
        forItemID itemID: String, factor: Double, cellSize: CGSize,
        pixelSize: CGSize? = nil
    ) {
        guard factor.isFinite, factor > 0 else { return }
        let covers = picturesCoverTheirCells
        mutatePresentation(forItemID: itemID, cellSize: cellSize) { presentation in
            presentation.zoom = min(Self.maximumCellZoom,
                                    max(Self.minimumCellZoom, presentation.zoom * factor))
            if presentation.zoom <= 1.0 && !covers {
                // Back to fitted: a pan that was only meaningful while zoomed in
                // would otherwise keep cropping the fitted image. Not so on a
                // filled cell, where zoom 1 is already a crop and the pan
                // chooses which part of it prints — throwing that away would
                // undo the reader's framing every time they zoomed back out.
                presentation.panX = 0
                presentation.panY = 0
            } else {
                // Zooming back out leaves less of the image hidden, so a pan
                // that was legal a moment ago can now be off the edge.
                Self.clampPan(of: &presentation, pixelSize: pixelSize,
                              covers: covers)
            }
        }
        propagateZoomPan(from: itemID, cellSize: cellSize)
    }

    /// Pans a cell by a drag in cell points.
    ///
    /// - Parameter pixelSize: the source frame's own size — see
    ///   ``adjustZoom(forItemID:factor:cellSize:pixelSize:)``.
    public func panCell(
        forItemID itemID: String, dx: Double, dy: Double, cellSize: CGSize,
        pixelSize: CGSize? = nil
    ) {
        guard dx.isFinite, dy.isFinite, cellSize.width > 0 else { return }
        let covers = picturesCoverTheirCells
        mutatePresentation(forItemID: itemID, cellSize: cellSize) { presentation in
            // The drag is measured on the cell; the pan is stored in the
            // viewport the mark was composed in, which is usually larger.
            let scale = presentation.viewportWidth / Double(cellSize.width)
            presentation.panX += dx * scale
            presentation.panY += dy * scale
            // The picture slides and stops at the image's edge; without this the
            // drag runs off it and the cell refits a shrinking crop instead.
            Self.clampPan(of: &presentation, pixelSize: pixelSize,
                          covers: covers)
        }
        propagateZoomPan(from: itemID, cellSize: cellSize)
    }

    /// Whether a pan on this cell has anywhere to go.
    ///
    /// A pan on film chooses which *hidden* part of the picture shows in the
    /// cell, and a printer fits a cell's crop centred — there is no printable
    /// "whole image, pushed sideways". So travel exists only where something is
    /// hidden: a zoomed-in cell, or any cell under fill scaling, which crops at
    /// every zoom. The viewer's pan is different in kind — it scrolls the
    /// screen and is never printed — which is why the same tool works unzoomed
    /// there and cannot here.
    public func cellHasPanTravel(_ item: PrintSelectionItem) -> Bool {
        picturesCoverTheirCells || (item.presentation?.zoom ?? 1) > 1
    }

    /// Whether the film's scaling *crops* each picture to cover its whole cell.
    ///
    /// Fill only. What it decides is whether a pan has anywhere to go at zoom 1
    /// — a fill-cropped cell is showing part of the image, so it does. Stretch
    /// also covers the cell but by distortion, not by cropping: the whole image
    /// is in the cell and there is nothing hidden for a pan to bring in, which
    /// is the fitted situation, not the filled one.
    var picturesCoverTheirCells: Bool {
        scalingMode == .fillToFilm
    }

    /// Holds a presentation's pan inside the image it is over.
    ///
    /// With no frame size to go on the viewport stands in for the image, which
    /// is exact on whichever axis the image fills and generous on the other.
    static func clampPan(of presentation: inout ViewerPresentation,
                                 pixelSize: CGSize?, covers: Bool = false) {
        let width = Int((pixelSize.map { Double($0.width) } ?? presentation.viewportWidth).rounded())
        let height = Int((pixelSize.map { Double($0.height) } ?? presentation.viewportHeight).rounded())
        guard width > 0, height > 0 else { return }
        let clamped = presentation.clampedPan(
            x: presentation.panX, y: presentation.panY,
            imageWidth: width, imageHeight: height, covers: covers)
        presentation.panX = clamped.x
        presentation.panY = clamped.y
    }

    /// Turns a cell a quarter turn clockwise.
    ///
    /// The exact turn, taken by permuting pixels rather than resampling them —
    /// which is why it is worth having beside the free-angle drag below. From
    /// an angle that is not a quarter turn it lands on the next one round,
    /// squaring the picture up rather than adding 90° to a tilt.
    public func rotateCell(forItemID itemID: String, cellSize: CGSize) {
        mutatePresentation(forItemID: itemID, cellSize: cellSize) { presentation in
            presentation.quarterTurns = (presentation.quarterTurns + 1) % 4
        }
        propagateRotation(from: itemID, cellSize: cellSize)
    }

    /// Turns a cell by a signed angle, as the rotate tool's drag does.
    ///
    /// Free-angle, like the viewer's rotate tool: the pointer is a handle on the
    /// picture and the cell follows it round, either way, through the whole
    /// circle. The angle is added to whatever the cell already had, so a drag can
    /// start anywhere and the picture keeps the orientation it was at.
    ///
    /// A cell at a free angle prints as one: ``ViewerPresentation`` stores the
    /// angle rather than quarter turns, the composer resamples it once at print
    /// time and fits the turned picture inside its image box, and the preview's
    /// shader masks outside that same crop — so what is dragged here is what
    /// comes off the printer.
    ///
    /// - Parameter degrees: signed clockwise angle to add. Small per-event
    ///   deltas are expected: a drag emits one of these per mouse move.
    public func rotateCell(
        forItemID itemID: String, byDegrees degrees: Double, cellSize: CGSize
    ) {
        guard degrees.isFinite, degrees != 0 else { return }
        mutatePresentation(forItemID: itemID, cellSize: cellSize) { presentation in
            presentation.rotationDegrees += degrees
        }
        propagateRotation(from: itemID, cellSize: cellSize)
    }

    /// Squares a cell up: back to the nearest quarter turn.
    ///
    /// The way out of a free-angle drag that has left the picture a few degrees
    /// off, without throwing away the window and the crop that a full reset
    /// would take with it. Already-square cells are left exactly where they are.
    public func straightenCell(forItemID itemID: String, cellSize: CGSize? = nil) {
        mutatePresentation(forItemID: itemID, cellSize: cellSize) { presentation in
            presentation.quarterTurns = presentation.quarterTurns
        }
        propagateRotation(from: itemID, cellSize: cellSize)
    }

    /// Mirrors a cell left to right.
    ///
    /// Deliberately not propagated to the other cells, and deliberately not on
    /// the lock list: a flip is a statement about laterality, not a way of
    /// standing a run of images up the same way. Mirroring a whole film because
    /// one image was marked from the far side prints a sheet nobody can read.
    /// See ``PrintCellSyncOptions`` for the same rule stated from the lock side.
    ///
    /// - Parameter cellSize: the cell the picture is drawn in, when the caller
    ///   knows it. Optional for the same reason inversion's is: a rail button
    ///   has no cell to speak of, and re-basing the viewport on a guess would
    ///   change the crop while claiming only to have mirrored the picture.
    public func flipCellHorizontal(forItemID itemID: String, cellSize: CGSize? = nil) {
        mutatePresentation(forItemID: itemID, cellSize: cellSize) { presentation in
            presentation.flipHorizontal.toggle()
        }
    }

    /// Mirrors a cell top to bottom. Same non-propagation rule as the
    /// horizontal flip above.
    public func flipCellVertical(forItemID itemID: String, cellSize: CGSize? = nil) {
        mutatePresentation(forItemID: itemID, cellSize: cellSize) { presentation in
            presentation.flipVertical.toggle()
        }
    }

    /// Whether a cell is mirrored on either axis — what the rail's Flip buttons
    /// light from, and what tells a reader the picture is not as it was sent.
    public func isCellFlipped(_ itemID: String) -> Bool {
        guard let presentation = selection.items
            .first(where: { $0.id == itemID })?.presentation else { return false }
        return presentation.flipHorizontal || presentation.flipVertical
    }

    /// Whether a cell is turned to an angle that is not a quarter turn.
    ///
    /// What decides whether straightening has anything to do — and worth saying
    /// on screen, because a free angle is the one arrangement that costs the
    /// film the corners of its picture.
    public func isCellSkewed(_ itemID: String) -> Bool {
        guard let presentation = selection.items
            .first(where: { $0.id == itemID })?.presentation else { return false }
        return !presentation.isQuarterTurn
    }

    /// The angle a cell is turned to, in degrees clockwise.
    public func rotation(forItemID itemID: String) -> Double {
        selection.items.first(where: { $0.id == itemID })?
            .presentation?.rotationDegrees ?? 0
    }

    /// Sets the film's palette, and carries it to every cell that has not
    /// chosen one of its own.
    ///
    /// Written through rather than resolved at render time. The alternative —
    /// leaving cells `nil` and having each renderer fall back to the film — puts
    /// the same fallback in four places (two preview paths, the preparer and the
    /// composer) and guarantees they will disagree eventually; the cell's
    /// presentation is already the one thing every path reads, so the answer
    /// lives there.
    ///
    /// A cell that chose its own palette keeps it. That is the whole point of a
    /// per-cell choice, and quietly overwriting it would make the film-wide
    /// picker a destructive control.
    ///
    /// Which cells those are is read from ``selfPalettedItemIDs`` rather than
    /// inferred by comparing each cell against the film's previous value. The
    /// comparison was only sound while the picker was the sole writer: reset,
    /// revert and saved-view adoption all move a cell's palette too, and a cell
    /// that drifted off the old value was then read as having chosen for itself
    /// — so the film-wide picker went dead on it and never recovered.
    ///
    /// - Parameter palette: the film's palette, or `nil` for a grey film. `nil`
    ///   clears the cells that were following the film and leaves the ones that
    ///   chose for themselves alone.
    public func applyFilmPalette(_ palette: DICOMCore.PseudoColorPalette?) {
        filmPalette = palette
        for item in selection.items where !selfPalettedItemIDs.contains(item.id) {
            guard item.presentation?.palette != palette else { continue }
            mutatePresentation(forItemID: item.id, cellSize: nil) { presentation in
                presentation.palette = palette
            }
        }
    }

    /// Sets a cell's pseudo-colour palette.
    ///
    /// - Parameters:
    ///   - palette: the palette, or `nil` to take the colour off and leave the
    ///     cell showing whatever the film's own default says. Passing
    ///     ``PseudoColorPalette/grayscale`` is the *other* thing: it says this
    ///     cell stays grey even if the film is coloured.
    ///   - cellSize: optional for the same reason inversion's is — colour is not
    ///     geometry, and a palette chosen from the inspector has no cell to
    ///     re-base a viewport on. Re-basing on a guess would change the crop
    ///     while claiming only to have recoloured.
    public func setCellPalette(
        _ palette: DICOMCore.PseudoColorPalette?,
        forItemID itemID: String,
        cellSize: CGSize? = nil
    ) {
        mutatePresentation(forItemID: itemID, cellSize: cellSize) { presentation in
            presentation.palette = palette
        }
        // Picking the film's own colour by hand is not "choosing for yourself":
        // the cell is where the film would have put it anyway, and marking it
        // self-chosen would silently exclude it from the next film-wide pick.
        // Anything else — including grey on a coloured film — is a real choice.
        if palette == filmPalette {
            selfPalettedItemIDs.remove(itemID)
        } else {
            selfPalettedItemIDs.insert(itemID)
        }
        propagatePalette(from: itemID, cellSize: cellSize)
    }

    /// The palette a cell is currently shown and printed with.
    ///
    /// `nil` means the cell has made no choice of its own and is showing the
    /// film's default, which is what the picker needs to know to show "Film
    /// default" rather than naming a palette the cell does not own.
    public func cellPalette(forItemID itemID: String) -> DICOMCore.PseudoColorPalette? {
        selection.items.first(where: { $0.id == itemID })?.presentation?.palette
    }

    /// Inverts a cell's greyscale.
    ///
    /// - Parameter cellSize: the cell the picture is drawn in, when the caller
    ///   knows it. Optional because inversion is not geometry: a rail button has
    ///   no cell to speak of, and re-basing the viewport on a guess would change
    ///   the crop while claiming only to have flipped the greys.
    public func toggleCellInversion(forItemID itemID: String, cellSize: CGSize? = nil) {
        mutatePresentation(forItemID: itemID, cellSize: cellSize) { presentation in
            presentation.invert.toggle()
        }
        propagateInversion(from: itemID, cellSize: cellSize)
    }

    /// Returns a cell to the untouched frame: the file's own window, no crop, no
    /// rotation, no inversion.
    public func resetCell(forItemID itemID: String) {
        guard let item = selection.items.first(where: { $0.id == itemID }) else { return }
        // The untouched frame is not a saved view, so the inspector must stop
        // naming one — otherwise the picker claims a state the cell just lost.
        appliedSavedViews.removeValue(forKey: itemID)
        // The untouched frame still needs concrete window values a drag can
        // start from. Reset leaves the cell focused, and seeding only runs when
        // a cell is *taken* — so a reset that merely cleared the window left
        // the window tool dead on that cell until another was visited. The
        // seed baseline holds exactly the file's own resolved window, so it is
        // written straight back; a never-seeded cell resolves it from the file.
        let seed = seededWindows[itemID]
        // The film's own palette is not a hand-made arrangement, so reset gives
        // the cell back to it rather than to grey. Clearing the presentation
        // outright would leave one grey cell on a coloured sheet — which reads
        // as reset having broken the cell rather than restored it.
        let restored: ViewerPresentation? = filmPalette.map {
            ViewerPresentation(palette: $0)
        }
        // Back on the film default, so the film-wide picker reaches it again.
        selfPalettedItemIDs.remove(itemID)
        // A seed is in modality units (FrameRenderer.resolvedWindowSpace, A6 / D65).
        selection.update(item.with(
            windowCenter: .some(seed?.center), windowWidth: .some(seed?.width),
            windowSpace: seed == nil ? item.windowSpace : .outputUnits,
            presentation: .some(restored)),
                         force: true)
        // The untouched frame is not a hand-made arrangement worth defending
        // from the viewer, so the cell follows the screen again.
        selection.clearAdjustment(forID: itemID)
        if seed == nil {
            Task { await seedWindowIfNeeded(forItemID: itemID) }
        }
    }

    /// Returns the focused cell to the untouched frame.
    ///
    /// The same edit as ``resetCell(forItemID:)``, aimed at the focus rather
    /// than at a cell named by the caller: the menu's own reset acts on whatever
    /// was right-clicked, which is not always the cell the tools are on.
    public func resetFocusedCell() {
        guard let focusedItemID else { return }
        resetCell(forItemID: focusedItemID)
    }

    /// Returns every cell on the film to the untouched frame.
    ///
    /// The way out of an arrangement that has gone wrong across the sheet —
    /// which linked cells make easy to produce, since one drag now moves many.
    /// Job-wide switches are left alone: this undoes the hand-made arrangement,
    /// and how the job is set up is a different decision.
    public func resetAllCells() {
        for item in selection.items {
            resetCell(forItemID: item.id)
        }
    }

    /// Puts every cell back to the untouched frame as a film is opened.
    ///
    /// The sheet-wide counterpart of ``resetCell(forItemID:)``, and deliberately
    /// not the same call: ``resetAllCells()`` is a reader undoing their own work
    /// mid-visit, so it re-seeds each cell's window ready for the next drag.
    /// This runs before anyone is looking — no cell is focused, no drag is
    /// coming — and re-reading every marked file to seed windows nobody has
    /// asked for would stall the launch on a large selection. The cells seed
    /// themselves as they are clicked, exactly as they do on a first visit.
    ///
    /// What is drawn on an image is left alone. An arrow marking a finding is
    /// about the anatomy under it, not about how the sheet was laid out, and it
    /// is stored against the image rather than the mark for that reason — so it
    /// outlives the film it was drawn on, while the zoom that framed it does
    /// not.
    /// What the reader asked for wins over the fresh sheet. "Match the viewer's
    /// window/level" and "Match the viewer's zoom, rotation and flip" are
    /// standing instructions about how film should relate to screen, so a mark's
    /// captured window and arrangement survive the reset whenever the
    /// corresponding switch is on. Only the fields whose switch is *off* are
    /// cleared — otherwise the film opened blank of everything the viewer had
    /// done, both switches read as dead, and no amount of toggling brought the
    /// screen's window back because there was nothing left in the mark to match.
    func resetCellToolsForNewFilm() {
        seededWindows = [:]
        let clearWindow = !useViewerWindow
        let clearPresentation = !useViewerPresentation
        for item in selection.items {
            if clearWindow || clearPresentation {
                selection.update(item.with(
                    windowCenter: clearWindow ? .some(nil) : .none,
                    windowWidth: clearWindow ? .some(nil) : .none,
                    windowSpace: item.windowSpace,
                    presentation: clearPresentation ? .some(nil) : .none),
                                 force: true)
            }
            selection.clearAdjustment(forID: item.id)
        }
        // The film's palette is a property of the *sheet*, and the sheet is new.
        // Left standing from the previous visit it desyncs from the cells this
        // reset has just cleared, and ``applyFilmPalette(_:)`` — which carries
        // the film's colour only to cells that still hold what the film last
        // said — then finds nothing to carry it to and the picker reads dead.
        // Written directly rather than through ``applyFilmPalette(_:)``: the
        // cells above are already at the state this palette describes, and
        // routing through the write-through would re-mark them as edited.
        // No cell on a sheet just opened has chosen a palette by hand.
        selfPalettedItemIDs = []
        filmPalette = clearPresentation ? nil : inferredFilmPalette()
    }

    /// The palette a freshly opened film should claim as its own.
    ///
    /// Only asked when the marks' presentations survive the reset — that is,
    /// when "match the viewer's arrangement" is on and the cells arrived
    /// already wearing whatever the reader had them coloured with on screen.
    /// The film's picker has to name something the cells actually hold, or the
    /// first pick made from it lands on no cell at all.
    ///
    /// Unanimity is the test: a sheet whose cells agree on a colour *is* a film
    /// of that colour, and the picker can say so honestly. A sheet that
    /// disagrees has no single film colour to name, so the film claims none and
    /// the first pick from the picker reaches every cell that has not chosen
    /// for itself — which on a mixed sheet is the cells holding nothing.
    private func inferredFilmPalette() -> DICOMCore.PseudoColorPalette? {
        var found: DICOMCore.PseudoColorPalette?
        for item in selection.items {
            guard let palette = item.presentation?.palette else { return nil }
            if let found {
                guard found == palette else { return nil }
            } else {
                found = palette
            }
        }
        return found
    }

    /// Whether any cell differs from the untouched frame, so a sheet-wide reset
    /// has something to undo.
    public var hasEditedCells: Bool {
        selection.items.contains { isCellEdited($0) }
    }

    /// Takes back the adjustments made to a cell here, restoring the mark to how
    /// the viewer left it.
    ///
    /// Distinct from ``resetCell(forItemID:)``: reset goes to the untouched
    /// frame, revert goes back to what was marked — usually the window the user
    /// had set on screen, which reset would throw away too.
    public func revertCell(forItemID itemID: String) {
        // Reverting goes back to the mark as the viewer made it, which is not
        // the applied saved view either — see ``resetCell(forItemID:)``.
        appliedSavedViews.removeValue(forKey: itemID)
        // The hand-made choice is exactly what revert takes back, so the cell
        // follows the film again.
        selfPalettedItemIDs.remove(itemID)
        selection.revertAdjustments(forID: itemID)
    }

    /// Takes back the adjustments made to the focused cell.
    ///
    /// The focus rather than a named cell, for the rail: the tool rail acts on
    /// whatever the tools are on, which is the focused cell.
    public func revertFocusedCell() {
        guard let focusedItemID else { return }
        revertCell(forItemID: focusedItemID)
    }

    /// Takes back every adjustment made on this screen, restoring every cell to
    /// the arrangement it was marked with in the viewer.
    ///
    /// The sheet-wide counterpart of ``revertCell(forItemID:)``, and the way out
    /// of a print-screen session that has gone wrong: the film goes back to
    /// showing exactly what the viewer showed, without discarding the window and
    /// arrangement the reader set on screen the way ``resetAllCells()`` would.
    ///
    /// Job settings — printer, film size, layout — are left alone: this undoes
    /// what the tools did to the pictures, and how the job is set up is a
    /// different decision. So is anything drawn: an arrow marking a finding is
    /// about the anatomy under it, not about how the sheet was composed.
    public func revertAllCells() {
        for item in selection.items where selection.isAdjusted(item.id) {
            revertCell(forItemID: item.id)
        }
    }

    /// Whether a cell has been adjusted here and can be taken back.
    public func isCellAdjusted(_ itemID: String) -> Bool {
        selection.isAdjusted(itemID)
    }

    /// Whether any cell has been adjusted on this screen, so a sheet-wide revert
    /// has something to take back.
    public var hasAdjustedCells: Bool {
        selection.items.contains { selection.isAdjusted($0.id) }
    }

    /// Whether a cell differs from the untouched frame.
    ///
    /// A window equal to the one the cell was seeded with does not count: the
    /// seed *is* the untouched frame's own window, written into the mark only so
    /// a drag has numbers to start from. Counting it lit "Reset Cell" the moment
    /// a cell was clicked, and — because seeding is an asynchronous file read —
    /// re-lit it when a seed landed after a reset, as though the reset had not
    /// taken.
    public func isCellEdited(_ item: PrintSelectionItem) -> Bool {
        if item.presentation.map({ !$0.isIdentity }) ?? false { return true }
        guard let center = item.windowCenter, let width = item.windowWidth else {
            return false
        }
        guard let seeded = seededWindows[item.id] else { return true }
        return seeded.center != center || seeded.width != width
    }

    /// Edits a mark's presentation, giving it one first if it has none.
    ///
    /// Deliberately does not propagate to synchronised cells: this is the write
    /// itself, and the peers are driven from the public tools above so that one
    /// gesture produces one round of propagation rather than a cascade. See
    /// `PrintViewModel+CellSync.swift`.
    func mutatePresentation(
        forItemID itemID: String,
        cellSize: CGSize?,
        _ transform: (inout ViewerPresentation) -> Void
    ) {
        guard let item = selection.items.first(where: { $0.id == itemID }) else { return }
        var presentation = item.presentation ?? ViewerPresentation()

        // Arranging a cell says the film should carry arrangements. With the
        // job-wide switch off the edit is written to the mark and then dropped
        // by `previewItem(for:)`, so the tool looks broken — nothing on the cell
        // moves however far it is dragged. Raw pixels are left alone: there the
        // switch would change nothing either way.
        if !useViewerPresentation && !sendRawPixels {
            useViewerPresentation = true
        }

        // The film cell becomes the viewport for anything adjusted here.
        //
        // The viewport decides the *shape* of the region a zoom keeps: crop an
        // image through a tall viewer tile and show the result in a wide film
        // cell, and the cell can only letterbox it — which reads as the image
        // being cut off in height rather than filling the cell. Re-basing on the
        // cell means what the user zooms into is the shape of what will print.
        // The zoom factor is carried across so the picture does not jump: the
        // same magnification, seen through a differently shaped window.
        if let cellSize {
            let cellWidth = max(1, Double(cellSize.width))
            let cellHeight = max(1, Double(cellSize.height))
            if !Self.aspectsMatch(width: presentation.viewportWidth,
                                  height: presentation.viewportHeight,
                                  otherWidth: cellWidth, otherHeight: cellHeight) {
                // The pan travels with the viewport it was made in. It is
                // stored in view points, so the same numbers against a
                // differently sized viewport are a different crop — a mark
                // panned in a big viewer tile jumped on the film cell's first
                // tool touch, which read as the tool moving the picture on its
                // own. Scaled per axis, the crop keeps its relative position;
                // the clamp after the edit holds it inside the image.
                if presentation.viewportWidth > 0, presentation.viewportHeight > 0 {
                    presentation.panX *= cellWidth / presentation.viewportWidth
                    presentation.panY *= cellHeight / presentation.viewportHeight
                }
                presentation.viewportWidth = cellWidth
                presentation.viewportHeight = cellHeight
            }
        }
        transform(&presentation)
        // Quantised for the same reason as the window: a zoom that differs in
        // the fourth decimal is the same picture, and re-rendering for it makes
        // the drag stutter without changing anything on screen.
        presentation.zoom = (presentation.zoom * 100).rounded() / 100
        presentation.panX = presentation.panX.rounded()
        presentation.panY = presentation.panY.rounded()
        // The angle is deliberately *not* quantised the way zoom and pan are.
        //
        // A rotate drag adds a delta per mouse event to the angle already
        // stored, so rounding the result of each one rounds the error in too:
        // at a tenth of a degree, twenty-four events of 1.25° come out as 31.2°
        // rather than 30°, and a slow drag visibly over-turns. Zoom and pan
        // survive that because they are recomputed from an anchor rather than
        // accumulated. Float noise is not worth buying at that price — nothing
        // downstream re-renders on the angle (the texture key excludes the
        // arrangement, so a turn is a matrix update), and exact quarter turns
        // come from ``straightenCell(forItemID:cellSize:)``, which sets them
        // outright, rather than from a drag happening to land on one.
        selection.adjust(item.with(presentation: .some(presentation)))
    }

    /// Whether two viewports are the same shape, within rounding.
    ///
    /// Cell sizes arrive from layout as fractional points, so an exact
    /// comparison would re-base the viewport on every redraw and slowly walk the
    /// crop across the image.
    static func aspectsMatch(
        width: Double, height: Double,
        otherWidth: Double, otherHeight: Double
    ) -> Bool {
        guard width > 0, height > 0, otherWidth > 0, otherHeight > 0 else { return false }
        return abs(width / height - otherWidth / otherHeight) < 0.01
    }

    /// Zoom bounds for a cell.
    ///
    /// The floor is fitted, not the viewer's 0.25. A film cell cannot show less
    /// than the fitted frame — below zoom 1 the visible region is simply the
    /// whole image, so every value in [0.25, 1) rendered *identically* to 1 and
    /// printed identically too. That range was a dead zone the zoom drag fell
    /// into invisibly: dragging down changed nothing on screen, and the next
    /// drag up spent its whole travel climbing back to 1 before anything moved
    /// — which read as "the zoom tool is broken", took the pan tool down with
    /// it (a pan is clamped to zero while zoom ≤ 1 on a fitted cell), and made
    /// reset look like it did nothing, since the cell already looked untouched.
    /// The ceiling is the viewer's own.
    static let minimumCellZoom: Double = 1.0
    static let maximumCellZoom: Double = 20.0
}
