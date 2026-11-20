// ImageViewerViewModel+Series.swift
// DICOMStudio
//
// DICOM Studio — the study's series, and hanging them in tiles.
//
// The viewer's left pane lists every series of the open study. A series is hung
// in a tile by dragging its card onto the tile, or by selecting the tile and
// double-clicking the card. Each tile keeps its own series, so a 2×2 can show
// four different series of the same study side by side.

import Foundation

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
extension ImageViewerViewModel {

    // MARK: - The study's series

    /// Loads the series pane's contents.
    ///
    /// Marks as visited whichever series the viewer is already showing, so the
    /// pane opens describing the state the user is actually in.
    public func loadStudySeries(_ entries: [ViewerSeriesEntry], studyUID: String? = nil) {
        // Series Number order, whatever order the caller had them in: the pane
        // is how a reader finds "series 4", and that only works if the list is
        // in the order the study itself asserts. Unnumbered series sort last —
        // see `ViewerSeriesCatalog.isOrderedBefore`.
        studySeries = entries.sorted(by: ViewerSeriesCatalog.isOrderedBefore)
        studyInstanceUID = studyUID
        // The pane's saved-view badges, refreshed here because this is where
        // the Study Instance UID the store files views under arrives.
        refreshSavedViewSeriesUIDs()
        if let current = seriesEntry(containing: filePath) {
            currentSeriesUID = current.seriesInstanceUID
            visitedSeriesUIDs.insert(current.seriesInstanceUID)
            // The navigation list may predate an instance-order repair: the
            // series was handed over in the index's stale order, and the
            // repaired entry now asserts the study's own. Same files in a new
            // order is that repair arriving — adopt it, keeping the image on
            // screen exactly where it is so nothing jumps under the reader.
            if current.filePaths != seriesFiles,
               Set(current.filePaths) == Set(seriesFiles) {
                seriesFiles = current.filePaths
                if let path = filePath,
                   let index = current.filePaths.firstIndex(of: path) {
                    currentFileIndex = index
                }
            }
            // The image loaded before the study did, so its saved views could
            // not be looked up then: the store files them under the Study
            // Instance UID that has only just arrived.
            offerSavedViewsIfNeeded()
            return
        }
        // Nothing of this study is on screen yet — open the pane on its first
        // series, showing that series' first image. A study that lists its
        // series but shows none of them leaves the reader with an empty viewer
        // and no obvious next click.
        selectFirstSeriesIfNothingShown()
    }

    /// Clears the viewer down to a blank slate for a different study.
    ///
    /// Opening a study from the library is a fresh read, and everything the
    /// previous one left behind is misleading here: another study's tiles in the
    /// grid, its zoom and rotation, its window, its stale error or report — and
    /// its print selection, whose marks point at files that are no longer on
    /// screen. Opening a study from the library is the one entry point that means
    /// "start over", so the selected-images panel starts over with it; the
    /// library's own "Print…" does not come through here, so the files it marks
    /// survive.
    /// Clears the viewer completely, including the image on screen.
    ///
    /// `prepareForNewStudy()` leaves the current file loaded because a new one
    /// is about to replace it. When a study is *deleted* there is no
    /// replacement: its files are gone, so the image, the navigation list and
    /// the decoded pixels behind them all have to go too, or the viewer keeps
    /// displaying a study that no longer exists.
    public func closeStudy() {
        prepareForNewStudy()
        seriesFiles = []
        currentFileIndex = 0
        filePath = nil
        sopInstanceUID = nil
        dicomFile = nil
        #if canImport(CoreGraphics)
        currentImage = nil
        displayTexture = nil
        #endif
        isLoading = false
    }

    public func prepareForNewStudy() {
        layout = .single
        cells = []
        focusedCellIndex = 0
        studySeries = []
        studyInstanceUID = nil
        currentSeriesUID = nil
        savedViewSeriesUIDs = []
        savedViewReferencesBySeries = [:]
        // A prompt left standing belongs to the study being left, as do the
        // readings its images were being held at.
        savedViewPrompt = nil
        isSRComposerPresented = false
        clinicalSRDraft = ClinicalSRDraft()
        structuredReportComposerError = nil
        appliedViewByImage = [:]
        visitedSeriesUIDs = []
        waveform = nil
        nonImageContent = nil
        errorMessage = nil
        #if canImport(CoreGraphics)
        currentImage = nil
        #endif
        currentFrameIndex = 0
        playbackState = .stopped
        resetTransformations()
        isInverted = false
        // Everything the print panel held: the marks, their captured windows and
        // their film positions, and the print screen itself if it was still up —
        // the film on it was composed from the study being left behind.
        printSelection.clear()
        // And the drawings: text and arrows are tool state like window and
        // zoom, and they reset with the study the same way. Drawings worth
        // keeping have a home already — saving a view writes them into the
        // presentation state — so what is left here is the scratch work of a
        // read that is over. Kept per image rather than per mark, so `clear()`
        // above does not reach them.
        printSelection.clearAllAnnotations()
        requestPrintScreenDismissal()
        // And the panel that held them: with nothing on the film, the tray is
        // back to where it starts — out of the way until this study's first
        // image is marked.
        isPrintTrayVisible = false
        // The tool arrangements of every series read, dropped with the study
        // that owns them — cleared last, so the resets above cannot re-mark
        // the series as touched.
        toolStateBySeries = [:]
        detachFromToolCache()
    }

    /// Hangs the first series of the study when the viewer has nothing to show.
    ///
    /// Deliberately conditional: a viewer already showing an image is showing
    /// what the user asked for, and replacing it would take the study away from
    /// them the moment the pane finished loading.
    func selectFirstSeriesIfNothingShown() {
        guard filePath == nil, let first = studySeries.first(where: { $0.firstFilePath != nil })
        else { return }
        selectSeries(first.seriesInstanceUID)
    }

    /// Shows a series in the viewer, from its first image.
    ///
    /// The single-click path from the series pane: clicking a card is a request
    /// to read that series, which means it lands in the tile the user is working
    /// in and starts at the top of the stack.
    @discardableResult
    public func selectSeries(_ uid: String) -> Bool {
        assignSeriesToFocusedCell(uid)
    }

    /// Shows a series starting at one of its objects.
    ///
    /// The path from a card's per-object previews: a series of several cines
    /// shows one preview per object, and clicking the second loop is a request
    /// to read *that* recording, not to start over at the first.
    @discardableResult
    public func selectSeries(_ uid: String, startingAtFile filePath: String) -> Bool {
        assignSeries(uid, toCell: cells.isEmpty ? 0 : focusedCellIndex,
                     startingAtFile: filePath)
    }

    /// The series pane entry a file belongs to, if any.
    public func seriesEntry(containing filePath: String?) -> ViewerSeriesEntry? {
        guard let filePath else { return nil }
        return studySeries.first { $0.filePaths.contains(filePath) }
    }

    /// The entry for a series UID.
    public func seriesEntry(uid: String) -> ViewerSeriesEntry? {
        studySeries.first { $0.seriesInstanceUID == uid }
    }

    /// Whether a series has been shown in a tile at some point this session.
    public func isSeriesVisited(_ uid: String) -> Bool {
        visitedSeriesUIDs.contains(uid)
    }

    /// Whether a series is the one the focused tile is showing.
    public func isCurrentSeries(_ uid: String) -> Bool {
        currentSeriesUID == uid
    }

    // MARK: - Hanging a series

    /// Hangs a series in a tile.
    ///
    /// The tile starts at the series' first instance, with *this series'*
    /// remembered arrangement if the reader has one, and a clean arrangement
    /// otherwise: a zoom and pan chosen for a different series would be
    /// meaningless here, and silently carrying one over would print a crop the
    /// user never composed — but the arrangement this series was left at is
    /// exactly what coming back to it means. See ``SeriesToolState``.
    ///
    /// - Returns: `true` when the series was hung.
    @discardableResult
    public func assignSeries(
        _ uid: String, toCell index: Int, startingAtFile startFile: String? = nil
    ) -> Bool {
        guard let entry = seriesEntry(uid: uid),
              entry.firstFilePath != nil else { return false }

        // The requested object, when it is actually the series' — a stale path
        // falls back to the top of the stack rather than refusing the series.
        let fileIndex = startFile.flatMap { entry.filePaths.firstIndex(of: $0) } ?? 0
        let file = entry.filePaths[fileIndex]

        // At 1×1 there are no tiles until a layout is applied; hang the series
        // in the viewer itself.
        guard cells.indices.contains(index) else {
            guard index == 0 else { return false }
            return hangInViewer(entry, startIndex: fileIndex)
        }

        captureFocusedCell()

        var cell = ViewerCellState(index: index)
        cell.filePath = file
        cell.seriesUID = entry.seriesInstanceUID
        cell.seriesFiles = entry.filePaths
        cell.fileIndex = fileIndex
        // The series' cached arrangement, seeded into the tile so
        // ``restoreArrangement(of:)`` puts it on screen rather than wiping the
        // restore the file load just performed.
        seedCellFromToolCache(&cell, seriesUID: entry.seriesInstanceUID)
        // The tile keeps the size it already occupies on screen.
        if cells.indices.contains(index) {
            cell.viewportWidth = cells[index].viewportWidth
            cell.viewportHeight = cells[index].viewportHeight
        }
        cells[index] = cell

        visitedSeriesUIDs.insert(entry.seriesInstanceUID)
        if index == focusedCellIndex {
            loadCell(at: index)
        }
        return true
    }

    /// Hangs a series in the focused tile — the double-click path.
    @discardableResult
    public func assignSeriesToFocusedCell(_ uid: String) -> Bool {
        assignSeries(uid, toCell: cells.isEmpty ? 0 : focusedCellIndex)
    }

    /// Replaces the whole viewer with a series, for the 1×1 case.
    ///
    /// No reset of its own: the load path resets every tool to the file's
    /// picture and then restores this series' cached arrangement over it —
    /// see ``SeriesToolState``. The `resetTransformations()` that used to sit
    /// here ran *after* that restore, which is why coming back to a rotated
    /// series showed it upright: it wiped the restored tools and, being a
    /// reader-visible mutation, re-snapshotted the wiped state over the good
    /// cache entry on the next depart.
    private func hangInViewer(_ entry: ViewerSeriesEntry, startIndex: Int) -> Bool {
        loadSeries(
            files: entry.filePaths,
            startIndex: startIndex,
            securityScopedParent: seriesSecurityScopedParent)
        currentSeriesUID = entry.seriesInstanceUID
        visitedSeriesUIDs.insert(entry.seriesInstanceUID)
        return true
    }

    /// Loads a tile's series and file into the live view model.
    func loadCell(at index: Int) {
        guard cells.indices.contains(index) else { return }
        let cell = cells[index]

        // The live viewport is the focused tile's, not the previous tile's —
        // and this holds even for an empty tile, which will adopt the viewer's
        // file on the next capture and would otherwise adopt a stale size with
        // it, resolving its zoom against the wrong viewport.
        if cell.viewportWidth > 0, cell.viewportHeight > 0 {
            viewContentWidth = cell.viewportWidth
            viewContentHeight = cell.viewportHeight
        }

        guard let path = cell.filePath else { return }

        // The focused tile owns navigation: arrow keys and the series controls
        // step through *its* series, not whatever was loaded before it.
        if !cell.seriesFiles.isEmpty {
            seriesFiles = cell.seriesFiles
            currentFileIndex = min(cell.fileIndex, max(0, cell.seriesFiles.count - 1))
        }
        currentSeriesUID = cell.seriesUID ?? seriesEntry(containing: path)?.seriesInstanceUID

        if path != filePath {
            loadFileInternal(at: path, securityScopedParent: seriesSecurityScopedParent)
        }
        restoreArrangement(of: cell)
    }
}
