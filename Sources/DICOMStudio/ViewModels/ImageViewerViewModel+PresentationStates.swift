// ImageViewerViewModel+PresentationStates.swift
// DICOMStudio
//
// Saving what a reader is looking at, and putting it back.
//
// NEMA-verified: 2026a, checked 2026-10-05 — saves hand DICOMPrintKit the image's Photometric Interpretation and Rescale Type (D42): a colour image is saved as a Color Softcopy Presentation State (PS3.3 2026a A.33.1.1 "may only be used to reference monochrome images", A.33.2), a MONOCHROME1 image folds its polarity into the Presentation LUT (PS3.4 N.2.1.4, Photometric Interpretation ignored) and the state's Modality LUT carries the Rescale Type (C.11.1.1.2); restores read the state's Presentation LUT against the image's photometric; a state's Modality LUT replaces the image's while shown and an absent one is the identity (N.2.1.1, D28) — except this app's own pre-2026-09-29 objects (sidecar not imported, no Modality LUT), which were written in the image's rescaled units and are read with it (the S-2 migration rule); a state's window is undone through its own rescale, not the image's; the Secondary Capture fallback UID 1.2.840.10008.5.1.4.1.1.7 is a PS3.6 Table A-1 row; checked by Scripts/diff_studio_g2_viewer.py
//
// The viewer holds one extra idea because of this: a *selected* view. It starts
// as the default — the image as the file describes it — and naming one of the
// saved views applies that instead. The selection is remembered per image so
// stepping through a series does not silently drop it, and cleared whenever the
// reader moves a tool, because at that point what is on screen is no longer the
// view that was saved.

import Foundation
import DICOMKit
import DICOMCore
import DICOMPrintKit

extension ImageViewerViewModel {

    // MARK: - Listing

    /// The saved views that apply to the image on screen.
    ///
    /// Empty when nothing has been saved for it — the picker then has only the
    /// default view to offer, and hides itself.
    public var savedViewsForCurrentImage: [SavedView] {
        guard let studyInstanceUID, let sopInstanceUID,
              let store = presentationStateStore else { return [] }
        return store.views(forStudy: studyInstanceUID, image: sopInstanceUID)
    }

    /// Whether there is anything to choose between.
    public var hasSavedViews: Bool { !savedViewsForCurrentImage.isEmpty }

    /// Whether any saved view covers an image of the given series.
    ///
    /// Answered from ``savedViewSeriesUIDs`` — see its note on why the store
    /// is not asked directly.
    public func seriesHasSavedViews(_ seriesInstanceUID: String) -> Bool {
        savedViewSeriesUIDs.contains(seriesInstanceUID)
    }

    /// Rebuilds ``savedViewSeriesUIDs`` from the store.
    ///
    /// The series a view belongs to is read off its states' Referenced Series
    /// Sequence — the series of the *images* it describes, not the
    /// presentation-state series the objects themselves live in, which is what
    /// the pane's cards are named by.
    func refreshSavedViewSeriesUIDs() {
        guard let studyInstanceUID, let store = presentationStateStore else {
            savedViewSeriesUIDs = []
            savedViewReferencesBySeries = [:]
            return
        }

        // One pass over the study's states feeds both caches: the badge asks
        // whether a series has any, the list asks which images they are on, and
        // parsing the study twice to answer two questions about the same files
        // would double the cost of every save and delete.
        let views = store.views(forStudy: studyInstanceUID)
        var seriesUIDs: Set<String> = []
        var references: [String: [SavedViewReference]] = [:]

        for view in views {
            for state in view.states {
                for series in state.state.referencedSeries {
                    seriesUIDs.insert(series.seriesInstanceUID)
                    for image in series.referencedImages {
                        references[series.seriesInstanceUID, default: []].append(
                            SavedViewReference(
                                sopInstanceUID: state.state.sopInstanceUID,
                                label: view.label,
                                imageSeriesInstanceUID: series.seriesInstanceUID,
                                imageSOPInstanceUID: image.sopInstanceUID,
                                // The image's own numbering, which only the
                                // pane knows — the state records the image by
                                // UID, as the IOD requires, not by position.
                                imageInstanceNumber: instanceNumber(
                                    ofImage: image.sopInstanceUID,
                                    inSeries: series.seriesInstanceUID),
                                imageSeriesNumber: studySeries.first {
                                    $0.seriesInstanceUID == series.seriesInstanceUID
                                }?.seriesNumber,
                                stateSeriesNumber: state.seriesNumber,
                                stateInstanceNumber: state.state.instanceNumber,
                                isColour: state.palette.map { !$0.isGrayscale } ?? false,
                                // The frames its drawings are on. The series
                                // reference above deliberately names none —
                                // window and zoom cover the whole object — so
                                // the frame lives only on the graphic
                                // annotations, one-based as (0008,1160) says.
                                annotatedFrameNumbers: Set(
                                    state.state.graphicAnnotations.flatMap { annotation in
                                        annotation.referencedImages
                                            .filter { $0.sopInstanceUID == image.sopInstanceUID }
                                            .flatMap { $0.referencedFrameNumbers ?? [] }
                                    }).sorted()))
                    }
                }
            }
        }

        savedViewSeriesUIDs = seriesUIDs
        // Ordered by where the image sits, then by view name, so a series with
        // several views reads down the slices rather than jumping between them.
        savedViewReferencesBySeries = references.mapValues { list in
            list.sorted {
                if $0.imageInstanceNumber != $1.imageInstanceNumber {
                    return ($0.imageInstanceNumber ?? .max) < ($1.imageInstanceNumber ?? .max)
                }
                return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
        }
    }

    /// The saved-view objects that describe images of one series.
    ///
    /// Answered from the cache ``savedViewReferencesBySeries`` — the pane asks
    /// once per card per render, and the store would have to reparse the
    /// study's presentation states to answer.
    public func savedViewReferences(forSeries seriesInstanceUID: String) -> [SavedViewReference] {
        savedViewReferencesBySeries[seriesInstanceUID] ?? []
    }

    /// Instance Number of one image of the open study.
    ///
    /// Read from the pane's own entry, which carries the number the library
    /// indexed at import. Nil when the series is not the pane's or the study
    /// does not number that image — the list then names the series alone
    /// rather than inventing a slice.
    private func instanceNumber(ofImage sopInstanceUID: String, inSeries seriesUID: String) -> Int? {
        studySeries.first { $0.seriesInstanceUID == seriesUID }?
            .instanceNumbersBySOPUID[sopInstanceUID]
    }

    /// The name shown on the picker: the selected view, or the default.
    public var selectedViewLabel: String {
        selectedPresentationStateLabel ?? Self.defaultViewLabel
    }

    /// What the picker calls the image as the file describes it.
    public static let defaultViewLabel = "Default view"

    /// The name to offer when the reader saves, so editing a saved view and
    /// saving again updates it instead of prompting for a new name.
    ///
    /// Deliberately not ``selectedPresentationStateLabel``: moving a tool
    /// clears that immediately, because the picker must stop claiming the
    /// saved view is on screen *unchanged* — see
    /// ``presentationStateFollowsTools()``. But the reader who nudged the
    /// window on a view they just applied is still revising that view, not
    /// starting a new one, and a blank textbox at that point reads as "your
    /// edit isn't attached to anything" when it plainly is. The standing
    /// choice in `appliedViewByImage` is what survives the edit; a present
    /// key holding nil means the reader is deliberately at the default view,
    /// which correctly still offers a blank name.
    ///
    /// With no standing choice at all, the image's own saved views answer
    /// instead. An image that already has a presentation state has a name the
    /// reader gave it, and a blank box in front of that name is an invitation
    /// to type a second one — the reader means to update the view they can see
    /// in the picker, not to fork it. Nothing has been applied in the cases
    /// that reach here: a multi-cell layout never raises the prompt, and a
    /// session that opened straight onto the image has not answered it yet.
    /// The store's newest-first order picks the view, matching what the
    /// picker lists first.
    var savePromptLabel: String {
        if !standingViewLabel.isEmpty { return standingViewLabel }
        // Unanswered — not answered *with the default*, which
        // ``standingViewLabel`` and this both read as nameless.
        guard let sopInstanceUID,
              appliedViewByImage[sopInstanceUID] == nil else { return "" }
        return savedViewsForCurrentImage.first?.label ?? ""
    }

    /// The view this image actually stands on, or empty for the default.
    ///
    /// The strict half of ``savePromptLabel``: no fallback to what is merely
    /// stored, because the callers that revert a view act on *every* image
    /// standing on a label. A stored-but-unapplied name here would revert
    /// slices the reader never put that view on.
    var standingViewLabel: String {
        guard let sopInstanceUID,
              let standing = appliedViewByImage[sopInstanceUID],
              let label = standing else { return "" }
        return label
    }

    // MARK: - Offering saved views on open

    /// The question asked when an image with saved views is opened.
    ///
    /// Carries the views rather than re-reading them: the prompt is a statement
    /// about the image that was *just* loaded, and a series step behind an open
    /// dialog would otherwise change the list under the reader's cursor.
    public struct SavedViewPrompt: Identifiable, Equatable {

        /// The image the question is about, so a late answer can be checked
        /// against what is on screen before it is acted on.
        public let sopInstanceUID: String

        /// The views covering that image, newest first, as the store orders them.
        public let views: [SavedView]

        public var id: String { sopInstanceUID }
    }

    /// Restores the image's standing view, or asks which one to use.
    ///
    /// Called from the two places that can complete an image's identity: the
    /// file load, and the study pane arriving with the Study Instance UID the
    /// store files views under. Either can be last, so both call this and it is
    /// written to be harmless when called twice for the same image.
    ///
    /// Two different arrivals, and they are not the same question:
    ///
    /// - The image has been answered before — a saved view applied to it, or
    ///   the default chosen. That answer is a statement about the slice, so it
    ///   is put back silently. Asking again would mean a reader who set a bone
    ///   window on slice 21 gets the dialog every time they scroll past it, and
    ///   sees the file's own view if they dismiss it.
    /// - The image has no standing answer. Then the views are worth offering,
    ///   because otherwise a view saved yesterday is invisible until the reader
    ///   thinks to open the picker.
    ///
    /// An image keeps its reading until the reader changes it, and changing it
    /// to the default view is a change like any other — see ``applyDefaultView()``.
    func offerSavedViewsIfNeeded() {
        // A grid is a comparison, not a reading of one image: focus moves
        // between tiles constantly, and a dialog on each move would make the
        // layout unusable. The picker is still there for the focused tile.
        guard !isMultiCellLayout else { return }
        // Mid-apply — restoring a view loads nothing, but a caller that
        // reloaded the file while applying one must not be interrupted by a
        // question it is in the middle of answering.
        guard !applyingPresentationState else { return }
        // The reader's own unsaved arrangement stands over this series — put
        // back a moment ago from the tool cache — and both the standing-choice
        // restore and the prompt below would overwrite it. The offers resume
        // when the arrangement is saved, reset, or replaced by a view applied
        // by hand; the picker still lists the views throughout.
        if let key = currentToolCacheKey, toolStateBySeries[key] != nil { return }
        guard let sopInstanceUID else { return }
        // Already up for this image: the second of the two trigger points
        // firing, which must not rebuild the sheet under the reader's cursor.
        guard savedViewPrompt?.sopInstanceUID != sopInstanceUID else { return }

        // A standing choice for this image. Note the double optional: the key
        // being present is what says "answered", and the value inside it says
        // with what — nil being the default view, which needs nothing applied
        // because the image has just loaded showing exactly that.
        if let standing = appliedViewByImage[sopInstanceUID] {
            guard let label = standing else {
                // The reader chose the default view for this slice. It is what
                // just loaded, so there is nothing to do but not ask again.
                selectedPresentationStateLabel = nil
                return
            }
            // The named view may have been deleted since it was applied, in
            // which case the image falls back to the file's own view and the
            // stale choice is dropped rather than left pointing at nothing.
            //
            // Not by hand: this slice is restoring what it already stood on, so
            // it must not re-stamp the label over slices the reader has since
            // put back to the default.
            if applySavedView(label: label, byHand: false) { return }
            // Assigning `nil` to a `[String: String?]` subscript *removes* the
            // key, which would put the image back to unanswered and re-offer
            // the prompt. `String?.none` is the present-key-holding-nil that
            // means "answered, with the default".
            appliedViewByImage[sopInstanceUID] = String?.none
            selectedPresentationStateLabel = nil
            return
        }

        // An unanswered image with saved views: apply the best one and show
        // it, rather than asking. This used to raise the "A saved view exists
        // for this image" sheet, which put a dialog between the reader and the
        // picture on every arrival at a new image — exactly the interruption
        // the on-image badge exists to remove. The workflow is the badge's:
        // the series-wide view when the series has one, else the image's
        // first, and the badge then steps to the others or the default view.
        //
        // Not by hand: this is the automatic display of what exists, not an
        // instruction from the reader, so it speaks only for this slice —
        // slices already put back to the default stay there.
        let cycle = savedViewCycle
        guard let best = cycle.first else { return }
        applySavedView(best, byHand: false)
    }

    /// Answers the prompt with one of the saved views.
    ///
    /// Ignores an answer that arrived after the reader moved on: the dialog
    /// names the image it was raised for, and applying a view to a different
    /// slice because a click landed late would be worse than dropping it.
    public func acceptSavedViewPrompt(_ view: SavedView) {
        guard let prompt = savedViewPrompt else { return }
        savedViewPrompt = nil
        guard prompt.sopInstanceUID == sopInstanceUID else { return }
        applySavedView(view)
    }

    /// Answers the prompt with the image as the file describes it.
    ///
    /// Nothing is applied: an image that has just loaded is already showing the
    /// file's own view, and running ``applyDefaultView()`` over it would clear
    /// drawings the reader has not seen yet on a slower load. Dismissing is the
    /// whole action.
    public func dismissSavedViewPrompt() {
        guard let prompt = savedViewPrompt else { return }
        savedViewPrompt = nil
        // Nothing is applied — the image already shows the file's own view —
        // but the choice is still recorded, or returning to the slice would
        // offer the views the reader has just turned down. A present key
        // holding nil is "answered, with the default".
        appliedViewByImage[prompt.sopInstanceUID] = String?.none
    }

    // MARK: - Drawn annotations

    /// This image's identity in the annotation store.
    ///
    /// Keyed on file path and frame rather than SOP Instance UID, matching
    /// ``ImageAnnotationKey`` — a multi-tile layout leaves the UID nil for
    /// unfocused tiles, so keying on it would drop their annotations.
    var currentAnnotationKey: ImageAnnotationKey? {
        guard let filePath else { return nil }
        return ImageAnnotationKey(filePath: filePath, frameIndex: currentFrameIndex)
    }

    /// The text and arrows drawn on the image on screen.
    var currentDrawnAnnotations: [PrintOverlayAnnotation] {
        guard let key = currentAnnotationKey else { return [] }
        return printSelection.cellAnnotations[key] ?? []
    }

    /// Everything drawn on one file, keyed by frame, blanks dropped.
    ///
    /// This is what a save records for an image: the annotation store keys
    /// drawings by file and frame, and a multi-frame image's arrows are
    /// statements about individual frames. Reading only the current frame —
    /// or worse, only frame 0 — would save an image and silently leave the
    /// arrows on its other frames behind.
    func drawnAnnotationsByFrame(forFile path: String) -> [Int: [PrintOverlayAnnotation]] {
        var byFrame: [Int: [PrintOverlayAnnotation]] = [:]
        for (key, annotations) in printSelection.cellAnnotations
        where key.filePath == path {
            let drawn = annotations.filter { !$0.isBlank }
            if !drawn.isEmpty { byFrame[key.frameIndex] = drawn }
        }
        return byFrame
    }

    // MARK: - Save scope

    /// What a save covers: the image on screen, or the series it belongs to.
    ///
    /// A saved view is the same object either way — presentation states under
    /// one label, one per image. The scope only decides which images get one,
    /// which is why applying, updating, deleting and exporting a series view
    /// go through exactly the code paths an image view does.
    ///
    /// There is deliberately no study-wide scope. A saved view is a window,
    /// zoom, pan and orientation, and those belong to an acquisition: a lung
    /// window is wrong for the abdomen series, and a scout's zoom means
    /// nothing on thin slices. Spreading one view over every series writes
    /// mostly-wrong presentation states that the reader then has to delete.
    /// Both scopes here stay inside one acquisition, where a shared view is
    /// actually a statement about the same pixels.
    public enum SavedViewScope: Sendable, Equatable {
        case currentImage
        case currentSeries
    }

    /// Whether saving for the series would cover more than saving the image.
    ///
    /// False for a lone image, where the two scopes are the same save and a
    /// second button would be a choice without a difference.
    public var canSaveViewForSeries: Bool {
        imageFilePaths(for: .currentSeries).count > 1
    }

    /// The files a scope's save would cover, in series order.
    func imageFilePaths(for scope: SavedViewScope) -> [String] {
        switch scope {
        case .currentImage:
            return filePath.map { [$0] } ?? []
        case .currentSeries:
            // The series pane is the authority on what the series holds; the
            // navigation list stands in when there is no pane — a folder of
            // files opened directly, for instance.
            if let uid = currentSeriesUID, let entry = seriesEntry(uid: uid) {
                return entry.filePaths
            }
            if let entry = seriesEntry(containing: filePath) {
                return entry.filePaths
            }
            if !seriesFiles.isEmpty { return seriesFiles }
            return filePath.map { [$0] } ?? []
        }
    }

    // MARK: - Saving

    /// Whether the current view is worth offering to save.
    ///
    /// An untouched image has nothing in it that the file does not already say,
    /// so saving it would add an entry to the picker that changes nothing.
    public var canSaveCurrentView: Bool {
        guard studyInstanceUID != nil, sopInstanceUID != nil,
              dicomFile != nil else { return false }
        // Any tool moved, or a window the reader chose: `isIdentity` covers
        // zoom, pan, rotation, flips and inversion, and a changed window is the
        // other thing worth naming a view for. A drawing counts on its own —
        // an untouched image with an arrow on it is worth saving, and was not
        // offerable before annotations were part of a view. Any frame's drawing
        // counts, because the save records every frame's. And a palette is a
        // choice the file does not describe — including a deliberate grey, the
        // choice a film-wide colour will not overwrite — so a coloured but
        // otherwise untouched image is worth a view too.
        return !currentPresentation.isIdentity
            || hasReaderChosenWindow
            || palette != nil
            || filePath.map { !drawnAnnotationsByFrame(forFile: $0).isEmpty } ?? false
    }

    /// Saves the current view under a name, as a series of the study.
    ///
    /// Only the image on screen is recorded. A reader who wants a window across
    /// a whole series saves it on each image they care about — which is also
    /// what makes the picker's per-image list honest.
    ///
    /// Saving writes the view twice, to two places that answer two different
    /// questions. The store's copy is what the picker reads: it is indexed by
    /// study and image, and it is what makes "which views does this slice have"
    /// answerable without touching the study's own folder. The study's copy is
    /// the presentation state as *part of the study* — a "PR" series sitting
    /// beside the images it describes, which travels when the study is copied,
    /// is picked up by anything that reads the folder, and carries the
    /// reference ID the reader quotes.
    ///
    /// Both are the same conformant GSPS objects; the second is a copy of the
    /// first, never a rebuild, so there is one definition of what a saved view
    /// is and no second code path to drift from it.
    ///
    /// - Returns: Whether anything was written.
    @discardableResult
    public func saveCurrentView(label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let studyInstanceUID,
              let sopInstanceUID,
              let file = dicomFile,
              let store = presentationStateStore else { return false }

        let sopClassUID = file.dataSet.string(for: .sopClassUID)
            ?? "1.2.840.10008.5.1.4.1.1.7"

        let display = ViewerPresentationStateBridge.capture(
            presentation: currentPresentation,
            // In rescaled units — the PR's VOI applies after the Modality LUT.
            windowCenter: presentationStateWindowCenter,
            windowWidth: presentationStateWindowWidth,
            imageWidth: imageColumns,
            imageHeight: imageRows,
            // PS3.4 N.2: the state's Presentation LUT replaces the image's
            // polarity, so a MONOCHROME1 image's inversion folds into it.
            photometricInterpretation: photometricInterpretation)

        var context = PresentationStatePatientContext.make(from: file.dataSet)
        // The data set is the authority on study identity, but a file loaded
        // without one would otherwise be filed under an empty UID.
        if context.studyInstanceUID.isEmpty {
            context.studyInstanceUID = studyInstanceUID
        }

        let image = PresentationStateStore.ImageToSave(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            seriesInstanceUID: currentSeriesUID
                ?? file.dataSet.string(for: .seriesInstanceUID) ?? "",
            display: display,
            // Every frame's drawings, not just the one on screen: an arrow on
            // frame 3 belongs to the view as much as one on the frame showing.
            annotationsByFrame: filePath.map(drawnAnnotationsByFrame(forFile:)) ?? [:],
            // The colour the image is being read through. GSPS cannot carry
            // it, so the store keeps it in the sidecar with the drawings.
            palette: palette,
            // The drawings are stored as fractions of the image; the GSPS's
            // Graphic Annotation Sequence states pixels, and these are what
            // convert one to the other.
            imageWidth: imageColumns,
            imageHeight: imageRows,
            // What sizes a coloured save's palette table: the table needs one
            // entry per storable pixel value or an exported view renders as a
            // single colour in any conforming viewer.
            bitsStored: bitsStored,
            isSigned: isSigned,
            rescaleSlope: rescaleSlope,
            rescaleIntercept: rescaleIntercept,
            // What lets the drawings name their frames: an arrow on frame 3 of
            // a cine has to say frame 3, or every other viewer paints it onto
            // all of them.
            numberOfFrames: numberOfFrames,
            // What decides the IOD: a GSPS "may only be used to reference
            // monochrome images" (PS3.3 A.33.1.1), so a colour image is saved
            // as a Color Softcopy Presentation State (A.33.2).
            photometricInterpretation: photometricInterpretation,
            // Written with the state's own Modality LUT (PS3.4 N.2.1.1): HU on
            // CT, else whatever the image declares.
            rescaleType: file.dataSet.string(for: .rescaleType))

        do {
            let saved = try store.save(
                images: [image], label: trimmed, patient: context)
            guard saved != nil else { return false }
            // The reader is now looking at the view they just named, and the
            // image keeps that reading the way an applied one does.
            selectedPresentationStateLabel = trimmed
            appliedViewByImage[sopInstanceUID] = trimmed
            presentationStateError = nil
            // And the study now holds it as a series. Done after the store
            // write and without failing the save: a view that is in the picker
            // but not yet in the study's folder is a recoverable state — saving
            // again publishes it — whereas reporting the whole save as failed
            // would send the reader back to set the window up a second time.
            addSavedViewToStudy(label: trimmed)
            refreshSavedViewSeriesUIDs()
            // The arrangement is a saved view now; the unsaved series cache
            // has nothing left to remember.
            forgetSeriesToolState()
            return true
        } catch {
            presentationStateError = "Could not save the view: \(error.localizedDescription)"
            return false
        }
    }

    /// Saves the current view under a name, over a chosen scope.
    ///
    /// The image scope is ``saveCurrentView(label:)`` unchanged. The series
    /// scope writes the *same* view — this window, zoom and orientation — onto
    /// every image of the series: one presentation state per image, all under
    /// the one label. That shape is what makes the rest free: the store already
    /// groups by label, so updating (re-saving the name), deleting, applying
    /// and exporting a series view are the same operations an image view gets.
    ///
    /// Each covered image is described against its *own* pixel dimensions —
    /// Displayed Area is a rectangle of source pixels, and a series whose
    /// scout is a different size than its slices must not inherit the wrong
    /// crop. Drawings stay per image: the current image contributes what is on
    /// screen, other images whatever was drawn on them; a series save does not
    /// stamp one image's arrows across the rest.
    ///
    /// Async because the covered images' identities are read from their files,
    /// off the main actor — a several-hundred-slice series must not freeze the
    /// viewer for the read. Files that cannot be read are skipped rather than
    /// failing the save; the image on screen is taken from memory and is never
    /// skipped.
    ///
    /// - Returns: Whether anything was written.
    @discardableResult
    public func saveCurrentView(label: String, scope: SavedViewScope) async -> Bool {
        guard scope != .currentImage else { return saveCurrentView(label: label) }

        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let studyInstanceUID,
              let sopInstanceUID,
              let file = dicomFile,
              let store = presentationStateStore else { return false }

        let paths = imageFilePaths(for: scope)

        // The image on screen never goes to disk for its identity: it is
        // already in memory, and its file may live somewhere the reader has
        // since moved.
        let currentPath = filePath
        let othersToRead = paths.filter { $0 != currentPath }
        let read = await Task.detached(priority: .userInitiated) {
            Self.readImageIdentities(paths: othersToRead)
        }.value

        var byPath: [String: SeriesImageIdentity] = [:]
        for identity in read { byPath[identity.filePath] = identity }
        if let currentPath {
            byPath[currentPath] = SeriesImageIdentity(
                filePath: currentPath,
                sopClassUID: file.dataSet.string(for: .sopClassUID)
                    ?? "1.2.840.10008.5.1.4.1.1.7",
                sopInstanceUID: sopInstanceUID,
                seriesInstanceUID: currentSeriesUID
                    ?? file.dataSet.string(for: .seriesInstanceUID) ?? "",
                columns: imageColumns,
                rows: imageRows,
                bitsStored: bitsStored,
                isSigned: isSigned,
                rescaleSlope: rescaleSlope,
                rescaleIntercept: rescaleIntercept,
                numberOfFrames: numberOfFrames,
                photometricInterpretation: photometricInterpretation,
                rescaleType: file.dataSet.string(for: .rescaleType))
        }
        let identities = paths.compactMap { byPath[$0] }
        guard !identities.isEmpty else {
            presentationStateError =
                "None of the series' images could be read, so nothing was saved."
            return false
        }

        var context = PresentationStatePatientContext.make(from: file.dataSet)
        if context.studyInstanceUID.isEmpty {
            context.studyInstanceUID = studyInstanceUID
        }

        let presentation = currentPresentation
        var images: [PresentationStateStore.ImageToSave] = []
        for identity in identities {
            let width = identity.columns > 0 ? identity.columns : imageColumns
            let height = identity.rows > 0 ? identity.rows : imageRows
            let display = ViewerPresentationStateBridge.capture(
                presentation: presentation,
                // In rescaled units, like the single-image save: one rescale
                // per series is the CT norm, and these identities are slices
                // of the series on screen.
                windowCenter: presentationStateWindowCenter,
                windowWidth: presentationStateWindowWidth,
                imageWidth: width,
                imageHeight: height,
                // Each image's own photometric: a series can mix MONOCHROME1
                // and MONOCHROME2, and the fold is per image (PS3.4 N.2).
                photometricInterpretation: identity.photometricInterpretation)
            images.append(PresentationStateStore.ImageToSave(
                sopClassUID: identity.sopClassUID,
                sopInstanceUID: identity.sopInstanceUID,
                seriesInstanceUID: identity.seriesInstanceUID,
                display: display,
                // The annotation store keys drawings by file and frame, and
                // holds them for every image of the series, current or not —
                // so each image contributes what was actually drawn on it,
                // frame by frame, rather than only its first frame's arrows.
                annotationsByFrame: drawnAnnotationsByFrame(forFile: identity.filePath),
                // The one palette is the view's, like the one window: a series
                // view is this reading spread over the series.
                palette: palette,
                imageWidth: width,
                imageHeight: height,
                bitsStored: identity.bitsStored,
                isSigned: identity.isSigned,
                rescaleSlope: identity.rescaleSlope,
                rescaleIntercept: identity.rescaleIntercept,
                numberOfFrames: identity.numberOfFrames,
                photometricInterpretation: identity.photometricInterpretation,
                rescaleType: identity.rescaleType))
        }

        do {
            let saved = try store.save(images: images, label: trimmed, patient: context)
            guard saved != nil else { return false }
            selectedPresentationStateLabel = trimmed
            // Every covered image now reads at this view, so stepping through
            // the series shows it slice after slice without asking again —
            // the same standing choice applying the view by hand records.
            for identity in identities {
                appliedViewByImage[identity.sopInstanceUID] = trimmed
            }
            presentationStateError = nil
            // Into the study as a series, exactly as the image save does.
            addSavedViewToStudy(label: trimmed)
            refreshSavedViewSeriesUIDs()
            // Saved as a PR: the unsaved series cache is finished with.
            forgetSeriesToolState()
            return true
        } catch {
            presentationStateError = "Could not save the view: \(error.localizedDescription)"
            return false
        }
    }


    // MARK: - The window, in the PR's units

    /// The viewer's window is kept in stored-pixel units; a presentation
    /// state's Softcopy VOI LUT applies *after* the Modality LUT (PS3.3
    /// C.11.8), so the object must carry rescaled units — 40 HU, not 8232.
    /// Writing stored units put the window above every pixel the image can
    /// rescale to, and a conforming viewer showed the state black (or, with
    /// the window ignored, unwindowed).
    private var presentationStateWindowCenter: Double {
        rescaleSlope != 0 ? windowCenter * rescaleSlope + rescaleIntercept : windowCenter
    }

    private var presentationStateWindowWidth: Double {
        rescaleSlope != 0 ? windowWidth * abs(rescaleSlope) : windowWidth
    }

    /// One image's identity, as a series save needs it.
    struct SeriesImageIdentity: Sendable, Equatable {
        let filePath: String
        let sopClassUID: String
        let sopInstanceUID: String
        let seriesInstanceUID: String
        let columns: Int
        let rows: Int
        let bitsStored: Int
        let isSigned: Bool
        let rescaleSlope: Double
        let rescaleIntercept: Double
        /// How many frames this image has — what decides whether its saved
        /// drawings name the frame they were made on. One when the header says
        /// nothing, which is what a single-frame image has.
        var numberOfFrames: Int = 1
        /// Photometric Interpretation (0028,0004): decides the IOD of the save
        /// (PS3.3 A.33.1.1) and the Presentation LUT fold (PS3.4 N.2). `nil`
        /// when the header says nothing, which reads as MONOCHROME2.
        var photometricInterpretation: String? = nil
        /// Rescale Type (0028,1054), written with the state's Modality LUT.
        var rescaleType: String? = nil
    }

    /// Reads each file's identity — headers only, no pixel data.
    ///
    /// Files that cannot be read are skipped rather than thrown on: one
    /// unreadable slice must not cost the reader the series save. Presentation
    /// states are skipped too — a study folder that already holds a published
    /// "PR" series must not have views saved *onto* the views.
    nonisolated static func readImageIdentities(paths: [String]) -> [SeriesImageIdentity] {
        var identities: [SeriesImageIdentity] = []
        for path in paths {
            guard let file = try? DICOMFile.read(
                      from: URL(fileURLWithPath: path), options: .metadataOnly),
                  let sopClassUID = file.dataSet.string(for: .sopClassUID),
                  let sopInstanceUID = file.dataSet.string(for: .sopInstanceUID),
                  !sopInstanceUID.isEmpty,
                  // Any presentation state class, not just GSPS: a coloured
                  // saved view is a Pseudo-Color object (…11.3) and must not be
                  // mistaken for an image of the series either.
                  !sopClassUID.hasPrefix(ViewerContentKind.presentationStatePrefix)
            else { continue }
            identities.append(SeriesImageIdentity(
                filePath: path,
                sopClassUID: sopClassUID,
                sopInstanceUID: sopInstanceUID,
                seriesInstanceUID: file.dataSet.string(for: .seriesInstanceUID) ?? "",
                columns: file.dataSet.uint16(for: .columns).map(Int.init) ?? 0,
                rows: file.dataSet.uint16(for: .rows).map(Int.init) ?? 0,
                bitsStored: file.dataSet.uint16(for: .bitsStored).map(Int.init) ?? 0,
                isSigned: (file.dataSet.uint16(for: .pixelRepresentation) ?? 0) == 1,
                rescaleSlope: file.dataSet.decimalStrings(for: .rescaleSlope)?
                    .first?.value ?? 1,
                rescaleIntercept: file.dataSet.decimalStrings(for: .rescaleIntercept)?
                    .first?.value ?? 0,
                // Read from the header like the rest: a series save covers
                // images the reader is not looking at, and a cine among them
                // still needs its drawings pinned to their frames.
                numberOfFrames: file.dataSet.string(for: .numberOfFrames)
                    .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 1,
                photometricInterpretation: file.dataSet.string(for: .photometricInterpretation),
                rescaleType: file.dataSet.string(for: .rescaleType)))
        }
        return identities
    }

    // MARK: - The series in the study

    /// Where the study's presentation-state series is written.
    ///
    /// The directory holding the study's own files. A presentation state is
    /// part of the study it describes, and putting it anywhere else would leave
    /// a series that vanishes the moment the study is copied somewhere.
    ///
    /// Taken from the *series pane* rather than from whatever file is on
    /// screen, and only from a file that is really there. The pane is the one
    /// thing that knows which files this study actually consists of; the
    /// viewer's own `filePath` can be an image opened from anywhere — a loose
    /// file, a fixture, a download — and writing a study's series into that
    /// file's folder would scatter presentation states into directories that
    /// are not studies at all. Nil is the correct answer for a viewer showing
    /// something that is not part of a study on disk: the view is still saved
    /// in the store and still appears in the picker, it simply has no study
    /// folder to become a series in.
    var studySeriesDirectory: URL? {
        let fileManager = FileManager.default
        // The image on screen, but only if the study claims it; otherwise the
        // study's first file, which is the pane's own statement of where it is.
        let candidates = [
            filePath.flatMap { path in
                studySeries.contains { $0.filePaths.contains(path) } ? path : nil
            },
            studySeries.first(where: { $0.firstFilePath != nil })?.firstFilePath
        ]
        for case let path? in candidates where fileManager.fileExists(atPath: path) {
            return URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        return nil
    }

    /// Files a saved view into the study as a presentation-state series.
    ///
    /// Called by ``saveCurrentView(label:)`` as part of saving — a saved view
    /// *is* a series of the study, not something optionally promoted into one
    /// later. Exposed separately so a view saved before the study's folder was
    /// reachable can be filed once it is.
    ///
    /// Every one of a study's saved views goes into the *same* series, which is
    /// the arrangement the store has used from the start: one "PR" series per
    /// study, one object per image per view. Saving a second view therefore
    /// adds objects to the series already there rather than making another, and
    /// re-saving a view under a name it already has overwrites its objects.
    @discardableResult
    public func addSavedViewToStudy(label: String)
        -> PresentationStateStore.PublishedSeries? {
        guard let studyInstanceUID,
              let store = presentationStateStore,
              let destination = studySeriesDirectory else { return nil }

        do {
            guard let published = try store.publish(
                label: label,
                studyInstanceUID: studyInstanceUID,
                into: destination) else {
                presentationStateError =
                    "There is no saved view called “\(label)” to add to the study."
                return nil
            }
            publishedPresentationSeries = published
            presentationSeriesPublishRequests += 1
            presentationStateError = nil
            return published
        } catch {
            presentationStateError =
                "Could not add the view to the study: \(error.localizedDescription)"
            return nil
        }
    }

    /// Removes a view's objects from the study's presentation-state series.
    ///
    /// The published objects carry the same SOP Instance UIDs as the store's,
    /// which is what makes them findable by name without re-reading them.
    func removeSavedViewFromStudy(label: String) {
        guard let studyInstanceUID,
              let store = presentationStateStore,
              let directory = studySeriesDirectory else { return }

        let views = store.views(forStudy: studyInstanceUID)
        guard let view = views.first(where: { $0.label == label }) else { return }

        let fileManager = FileManager.default
        var removed: [String] = []
        for state in view.states {
            let url = directory.appendingPathComponent(
                "\(state.state.sopInstanceUID).dcm")
            // Only files this study's series actually holds: a saved view that
            // was never published has nothing here, and a missing file is the
            // ordinary case rather than a failure.
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try? fileManager.removeItem(at: url)
            // The drawings go with the object, exactly as they do in the store.
            try? fileManager.removeItem(
                at: url.deletingPathExtension().appendingPathExtension("annotations.json"))
            removed.append(state.state.sopInstanceUID)
        }

        guard !removed.isEmpty else { return }
        // Its own signal, not the publish counter: the shell has to *unfile*
        // these instances, and a delete announced as a publish would have it
        // adding back the objects that were just removed.
        unpublishedPresentationStateUIDs = removed
        presentationSeriesRemovalRequests += 1
    }

    /// Dismisses the confirmation naming the published series.
    public func dismissPublishedSeriesConfirmation() {
        publishedPresentationSeries = nil
    }

    /// Removes a saved view from the study.
    ///
    /// Both copies go: the store's, which is what the picker lists, and the
    /// objects in the study's own presentation-state series. Leaving the
    /// second behind would make a deleted view come back the next time the
    /// study's folder was scanned.
    public func deleteSavedView(label: String) {
        guard let studyInstanceUID, let store = presentationStateStore else { return }
        do {
            // Before the store's copy, which is what knows the object UIDs that
            // name the files in the study.
            removeSavedViewFromStudy(label: label)
            try store.deleteView(label: label, studyInstanceUID: studyInstanceUID)
            // The image on screen is showing the view that was just deleted —
            // not just named after it, but rendered with its window, geometry
            // and drawings. Naming it gone without resetting the pixels would
            // leave a dangling view on screen that the picker no longer admits
            // exists. `applyDefaultView()` is what a reader picking "Default
            // view" gets, and this is the same situation forced by the delete.
            if selectedPresentationStateLabel == label {
                applyDefaultView()
            }
            // No image is being read at a view that no longer exists. Dropping
            // the choices rather than rewriting them to the default: the reader
            // deleted the view, they did not decide how those slices now read.
            appliedViewByImage = appliedViewByImage.filter { $0.value != label }
            presentationStateError = nil
            refreshSavedViewSeriesUIDs()
        } catch {
            presentationStateError = "Could not delete the view: \(error.localizedDescription)"
        }
    }

    // MARK: - Applying

    /// Puts the image back to how the file describes it.
    ///
    /// "The image as the file describes it" includes carrying no drawings: the
    /// file describes none, so the default view shows none. Picking it after
    /// reading a marked-up view therefore gives a clean image — window, zoom
    /// and orientation reset, arrows and labels gone, and only the corner
    /// identification text, which is drawn from the data set rather than
    /// drawn by the reader.
    ///
    /// The drawings are not lost by this. They were written into the saved
    /// view when it was saved, so choosing that view again brings them back;
    /// what this clears is the working copy on screen.
    public func applyDefaultView() {
        // One image, and only this one.
        //
        // This used to sweep the whole study: every image standing on the same
        // label was reverted along with the one on screen, on the reasoning
        // that a view saved across a series stamps its label into each slice
        // it covers, so leaving the others would re-apply the view the reader
        // had just backed out of when they stepped to one.
        //
        // That reasoning does not hold, and the sweep was the bug behind
        // "Default view resets the whole series". Each slice's standing choice
        // is read independently on arrival — see
        // ``offerSavedViewsIfNeeded()``, which looks up
        // `appliedViewByImage[sopInstanceUID]` for the image being shown and
        // nothing else. Reverting this image therefore cannot cause any other
        // image to re-apply anything: the next slice applies *its own* standing
        // label, which the reader chose there and has not backed out of. The
        // sweep was not preventing a re-apply, it was silently answering for
        // slices the reader never spoke about.
        //
        // Reverting a whole series is a different act and has its own row in
        // the picker — ``applyDefaultViewForSeries()`` — which is where a
        // reader who means all of them says so.
        selectedPresentationStateLabel = nil
        // Choosing the default is an answer, not the absence of one: the image
        // is read this way from now on, and arriving at it again must not
        // re-offer the views the reader has just turned down. Recorded as a
        // present key holding nil.
        if let sopInstanceUID { appliedViewByImage[sopInstanceUID] = String?.none }
        applyingPresentationState = true
        defer { applyingPresentationState = false }
        resetTransformations()
        // Inversion is part of a view, not a separate mode: ``canSaveCurrentView``
        // offers to save an image *because* it is inverted (`isIdentity` counts
        // `invert`), and `applySavedView` restores it. `resetTransformations` is
        // geometry only, so the default view used to come back still inverted —
        // a presentation state applied to a monochrome image left the greys
        // swapped with the picker claiming the file's own view was on screen.
        isInverted = false
        // And the Modality LUT: the file's own, not the view's (PS3.4 N.2.1.1).
        modalityLUTSource = .image
        // And the colour with it, for the same reason: "the image as the file
        // describes it" is a grey image, because the file describes no palette.
        palette = nil
        if isMultiCellLayout, cells.indices.contains(focusedCellIndex) {
            cells[focusedCellIndex].palette = nil
        }
        resetWindowToFileDefault()
        clearDrawnAnnotationsForCurrentImage()
        // The series' remembered arrangement goes with it: "the image as the
        // file describes it" must hold across a step away and back.
        forgetSeriesToolState()
        renderCurrentFrame()
    }

    /// Puts the whole current series back to how the files describe it.
    ///
    /// ``applyDefaultView()`` is a statement about one image; this is the same
    /// statement about every image of the series on screen. The two are
    /// genuinely different answers, which is why both are offered: a reader
    /// who applied a view across a series and wants out of it on *this slice
    /// only* is served by the first, and one who wants the series back as the
    /// scanner described it is served by this.
    ///
    /// Every image of the series gets a present key holding nil — the same
    /// "the reader has chosen the default" answer the single-image revert
    /// records, so stepping through the series afterwards neither re-applies
    /// the view nor re-raises the open prompt on each slice.
    ///
    /// Images *outside* this series keep the view they stand on: a view saved
    /// across the study survives on the other series. Nothing has to be undone
    /// to achieve that — ``applyDefaultView()`` speaks only for the image on
    /// screen — so this simply names its own slices and sets each of them.
    ///
    /// Async because the covered images' SOP Instance UIDs come from their
    /// headers, read metadata-only.
    public func applyDefaultViewForSeries() async {
        let paths = imageFilePaths(for: .currentSeries)

        let identities = paths.count > 1
            ? await Task.detached(priority: .userInitiated) {
                  Self.readImageIdentities(paths: paths)
              }.value
            : []

        // The series may have changed under the read — a different series hung
        // in the tile, the study closed. Reverting the slices of a series the
        // reader has left would be a statement about images they never chose.
        guard imageFilePaths(for: .currentSeries) == paths else { return }

        // The image on screen, by the ordinary path: it also resets the pixels,
        // the window, the palette and the drawings, which the other slices do
        // not need since they are not being displayed.
        applyDefaultView()

        // And every other slice of this series, so stepping through them
        // afterwards neither re-applies the view nor re-raises the prompt.
        for identity in identities {
            appliedViewByImage[identity.sopInstanceUID] = String?.none
        }
    }

    /// Whether reverting the series would cover more than reverting the image.
    ///
    /// False for a lone image, where the two are the same act — the same
    /// reasoning as ``canSaveViewForSeries``, which gates the save side.
    public var canApplyDefaultViewForSeries: Bool { canSaveViewForSeries }

    /// Drops the drawings on the image on screen, leaving other images alone.
    ///
    /// Scoped to the current image because the default view is a statement
    /// about one image: stepping to the next frame and picking it there must
    /// not take the previous frame's arrows with it.
    func clearDrawnAnnotationsForCurrentImage() {
        guard let key = currentAnnotationKey else { return }
        // A selection pointing into the annotations being removed would
        // outlive them, and the editing paths treat a selected id as live.
        if let ids = printSelection.cellAnnotations[key]?.map(\.id),
           ids.contains(where: { $0 == printSelection.selectedAnnotationID }) {
            printSelection.selectedAnnotationID = nil
        }
        printSelection.cellAnnotations[key] = nil
    }

    /// Applies a saved view to the image on screen.
    ///
    /// A view that covers other images but not this one leaves the viewer alone:
    /// the picker does not offer those, but a stale selection carried across a
    /// series step can still land here.
    ///
    /// - Parameter byHand: whether the reader picked this view themselves — a
    ///   click in the list or the picker — as opposed to it being restored
    ///   automatically on arrival at a slice that already stood on it. A
    ///   by-hand apply is an instruction about every image the view covers; an
    ///   automatic one speaks only for the slice being shown. See the stamping
    ///   loop at the end of this method.
    @discardableResult
    public func applySavedView(_ view: SavedView, byHand: Bool = true) -> Bool {
        guard let sopInstanceUID,
              let stored = view.state(forImage: sopInstanceUID) else { return false }

        let restored = ViewerPresentationStateBridge.restore(
            stored.state,
            imageWidth: imageColumns,
            imageHeight: imageRows,
            viewportWidth: viewContentWidth,
            viewportHeight: viewContentHeight,
            // The Presentation LUT folds back out exactly as the save folded
            // it in: INVERSE on a MONOCHROME1 image is its upright picture.
            photometricInterpretation: photometricInterpretation)

        // Applied without going through the tool paths: those clear the
        // selection, which would drop the view the moment it was applied.
        applyingPresentationState = true
        defer { applyingPresentationState = false }

        // The state's Modality LUT replaces the image's for as long as the view
        // is on screen; a state without one is the identity, and "any Modality
        // LUT or equivalent Attributes in the Image shall not be used" (PS3.4
        // N.2.1.1). The one exception is this app's own objects from before
        // the store wrote a Modality LUT (2026-09-29): those carry the window
        // in the image's rescaled units with no rescale to say so, and are read
        // with the image's — an adopted object never is.
        let modalityLUT: ModalityLUT?
        if let own = stored.state.modalityLUT {
            modalityLUT = own
        } else if !stored.isImported, rescaleSlope != 0,
                  rescaleSlope != 1 || rescaleIntercept != 0 {
            modalityLUT = .rescale(slope: rescaleSlope, intercept: rescaleIntercept, type: nil)
        } else {
            modalityLUT = nil
        }
        modalityLUTSource = .presentationState(modalityLUT)

        if let center = restored.windowCenter, let width = restored.windowWidth {
            // The object's window is in the units its Modality LUT puts out;
            // the viewer's window is kept in stored-pixel units, so a rescale
            // is undone here and re-applied when the frame is rendered (see
            // ``displayWindow``). A table LUT or the identity leaves the
            // numbers as they are.
            if case .rescale(let slope, let intercept, _)? = modalityLUT, slope != 0 {
                windowCenter = (center - intercept) / slope
                windowWidth = width / abs(slope)
            } else {
                windowCenter = center
                windowWidth = width
            }
        }
        zoomLevel = restored.zoom
        panOffsetX = restored.panX
        panOffsetY = restored.panY
        rotationAngle = restored.rotationDegrees
        isFlippedHorizontal = restored.flipHorizontal
        // GSPS carries no vertical flip: the bridge folded it into the rotation
        // on the way out, so restoring one is always "not flipped vertically".
        isFlippedVertical = false
        if isInverted != restored.invert {
            toggleInversion()
        }

        // The drawings come back with the view, frame by frame. Replacing
        // rather than merging — and replacing *every* frame of this file, not
        // just the one showing: the saved view is a complete statement of what
        // was on this image, so an arrow deleted before saving must not survive
        // the restore, on this frame or any other.
        if let filePath {
            let replaced = printSelection.cellAnnotations.keys
                .filter { $0.filePath == filePath }
            // A selection pointing into the annotations being replaced would
            // outlive them, and the editing paths treat a selected id as live.
            if let selected = printSelection.selectedAnnotationID,
               replaced.contains(where: { key in
                   printSelection.cellAnnotations[key]?
                       .contains { $0.id == selected } ?? false
               }) {
                printSelection.selectedAnnotationID = nil
            }
            for key in replaced { printSelection.cellAnnotations[key] = nil }
            for (frame, annotations) in stored.annotationsByFrame(forImage: sopInstanceUID) {
                printSelection.cellAnnotations[
                    ImageAnnotationKey(filePath: filePath, frameIndex: frame)] = annotations
            }
        }

        // And the colour, which is part of the reading the same way the window
        // is. A view with none says grey — the complete-statement rule again,
        // not silence — so applying it over a coloured image takes the colour
        // off. Views saved before palettes were recorded read back as none,
        // which restores exactly what they used to.
        palette = stored.palette
        if isMultiCellLayout, cells.indices.contains(focusedCellIndex) {
            cells[focusedCellIndex].palette = stored.palette
        }

        selectedPresentationStateLabel = view.label
        // Every image the view covers is now being read this way, and stays
        // that way until the reader says otherwise — including across a step
        // away and back. For a view saved on one image this is that image
        // alone, as it always was; for a view saved over a series it is the
        // series, which is what makes applying a series view once hold while
        // stepping through its slices.
        //
        // Every covered image, unconditionally, when the reader asked for this
        // view by name — `byHand` — and only the unanswered ones when the view
        // is being restored automatically on arrival at a slice.
        //
        // The distinction is the whole point. Picking a view out of the list is
        // a fresh instruction about the images it covers, and it has to reach
        // all of them or a series view applies to one slice; that is what the
        // reader is asking for when they click it.
        //
        // Re-applying on arrival is not an instruction at all — it is this
        // slice restoring what it already stood on — so it must not sweep the
        // label back across slices the reader has since put back to the
        // default. Without that half, reverting one slice and stepping to the
        // next re-stamped the reverted one, and stepping back showed it reading
        // the view again.
        //
        // A guard of "only images with no standing choice" cannot serve both:
        // after any revert every slice carries a present-key-holding-nil, so it
        // skipped the entire series and a view picked from the list applied to
        // the current image alone.
        for uid in view.states.flatMap(\.referencedImageUIDs)
        where byHand || uid == sopInstanceUID || appliedViewByImage[uid] == nil {
            appliedViewByImage[uid] = view.label
        }
        // A view picked by name replaces whatever unsaved arrangement the
        // reader had standing over the series; an automatic restore must not
        // touch it (and cannot reach here while one stands — see
        // ``offerSavedViewsIfNeeded()``).
        if byHand { forgetSeriesToolState() }
        renderCurrentFrame()
        return true
    }

    /// Applies the saved view of a given name, if the current image has one.
    @discardableResult
    public func applySavedView(label: String, byHand: Bool = true) -> Bool {
        guard let view = savedViewsForCurrentImage.first(where: { $0.label == label })
        else { return false }
        return applySavedView(view, byHand: byHand)
    }

    // MARK: - The badge's cycle

    /// The saved views for the image on screen, in the order the badge steps
    /// through them: series-wide views first, then single-image views.
    ///
    /// Series-wide first because that is the reading most deliberately set up —
    /// someone arranged a whole series and saved it — so it is what the first
    /// press of the badge should land on. Within each group the store's own
    /// order is kept, so the cycle is stable from press to press.
    public var savedViewCycle: [SavedView] {
        let views = savedViewsForCurrentImage
        return views.filter { $0.coveredImageCount > 1 }
             + views.filter { $0.coveredImageCount <= 1 }
    }

    /// One press of the on-image saved-views badge.
    ///
    /// The badge applies rather than listing: pressing it steps through the
    /// image's readings, so no popup stands between the reader and the picture.
    ///
    ///  - Nothing applied yet → the first view in ``savedViewCycle``: the
    ///    series-wide view when the series has one, else the image's first.
    ///  - A view applied → the next one in the cycle.
    ///  - The last view applied → the default view, the image as the file
    ///    describes it.
    ///  - The default showing (after a full lap) → the first view again.
    ///
    /// A view is applied by hand here — the reader pressed the badge — so a
    /// series-wide view reaches every slice it covers, exactly as it would from
    /// the toolbar picker.
    ///
    /// - Returns: The label now showing — a view's name, or the default-view
    ///   label — or `nil` when the image has no saved views at all.
    @discardableResult
    public func applyNextSavedView() -> String? {
        let cycle = savedViewCycle
        guard !cycle.isEmpty else { return nil }

        // Where the cycle stands. A tool edit clears the selected label while
        // the reading stays on screen; the next press then starts the cycle
        // over from the top, which is also the right answer for a label whose
        // view has been deleted since it was applied.
        if let current = selectedPresentationStateLabel,
           let index = cycle.firstIndex(where: { $0.label == current }) {
            let next = index + 1
            if next < cycle.count {
                applySavedView(cycle[next], byHand: true)
                return cycle[next].label
            }
            // Past the end: back to the image as the file describes it. This
            // image alone — the series row of work the reader may have done on
            // other slices is not this press's to undo.
            applyDefaultView()
            return Self.defaultViewLabel
        }

        applySavedView(cycle[0], byHand: true)
        return cycle[0].label
    }

    // MARK: - Keeping the selection honest

    /// Drops the selected view once the reader moves a tool.
    ///
    /// What is on screen after a drag is no longer the view that was saved, and
    /// a picker still naming it would be lying. Called from the tool paths
    /// rather than from the property observers, so that *applying* a state does
    /// not immediately clear itself.
    func presentationStateFollowsTools() {
        guard !applyingPresentationState else { return }
        // A moved tool is no longer the state's picture, so the image's own
        // Modality LUT comes back with it (PS3.4 N.2.1.1 binds the state's
        // only while the state is what is shown).
        modalityLUTSource = .image
        guard selectedPresentationStateLabel != nil else { return }
        selectedPresentationStateLabel = nil
        // Only the label goes. The standing choice in `appliedViewByImage`
        // stays: moving a tool means the picker must stop claiming the saved
        // view is on screen *unchanged*, but it does not mean the reader has
        // stopped reading the slice at that view. Writing "default" here would
        // make a nudge of the zoom silently discard the applied view, so that
        // coming back to the slice showed the file's own image instead.
    }
}
