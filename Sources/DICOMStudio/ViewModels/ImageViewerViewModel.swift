// ImageViewerViewModel.swift
// DICOMStudio
//
// DICOM Studio — Image viewer ViewModel
//
// NEMA-verified: 2026a, checked 2026-10-06 — `applyDefaultWindow` takes the file's default window from DICOMKit `determineModalityWindow` (modality units, PS3.3 C.11.2.1.2.1) and converts it to the viewer's stored-unit state with (c − b) / m, w / |m| (A6 / D65; the deprecated `determineWindowSettings` is no longer called); the viewport now renders through the PS3.4 2026a N.2 chain (D65, D68): `displayModalityLUT` is the image's Modality LUT Sequence else its Rescale pair (PS3.3 C.11.1), or the applied presentation state's (N.2.1.1); `displayWindow` hands the renderer the window in modality units (C.11.2.1.2.1 — the viewer keeps stored-pixel units for its tools and converts c·m+b, w·|m|), `displayVOI` the file's VOI LUT Sequence while the window is the untouched default (C.11.2, one or the other), `displayICCProfile` the ICC Profile (0028,2000) of colour frames (C.11.15.1.1); the Presentation LUT is left to the photometric (MONOCHROME1 → INVERSE, C.7.6.3.1.2); `voiLUTFunction` defaults to LINEAR (C.11.2.1.3); the MONOCHROME1/2 and RGB literals are C.7.6.3.1.2 terms; `isWaveformFile` now excludes the .9.100 Waveform Presentation State branch of the PS3.6 Table A-1 .9 arc (the two were classified as waveforms: corrected); the window fallbacks are the C.11.2.1.2.1 full-range window then the header's own; checked by Scripts/diff_studio_g2_viewer.py

import Foundation
import Observation
import DICOMKit
import DICOMCore
import DICOMRenderKit
import DICOMPrintKit

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// ViewModel for the DICOM image viewer, managing rendering state,
/// window/level controls, cine playback, and zoom/pan gestures.
///
/// Requires macOS 14+ / iOS 17+ for the `@Observable` macro.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@MainActor
@Observable
public final class ImageViewerViewModel {

    // MARK: - Image State

    #if canImport(CoreGraphics)
    /// The currently rendered CGImage.
    public var currentImage: CGImage?
    #endif

    #if canImport(Metal)
    /// The current frame as a GPU texture, when the display path can use one.
    ///
    /// Non-nil means zoom, pan, rotation, flip and inversion are applied by the
    /// display shader instead of by CPU passes and SwiftUI modifiers — so changing
    /// any of them redraws a textured quad and re-renders nothing. Nil means the
    /// viewport falls back to `Image(decorative:)` over ``currentImage``, which is
    /// what happens on a CPU-only machine and whenever a frame needs work the
    /// display path does not do (see ``canUseDisplayTexture``).
    ///
    /// Produced by the same dispatch that produces ``currentImage``, over the same
    /// output memory — having both costs nothing extra.
    public var displayTexture: DisplayFrameTexture?
    #endif

    /// File path of the currently loaded DICOM file.
    public var filePath: String?

    /// Parsed DICOM file for rendering.
    public var dicomFile: DICOMFile?

    /// SOP Instance UID of the loaded file.
    public var sopInstanceUID: String?

    /// Parsed waveform when the loaded file is a Waveform IOD (ECG, hemodynamic,
    /// etc.) rather than an image. Non-nil disables the pixel-rendering path and
    /// drives the waveform display instead.
    public var waveform: Waveform?

    /// Whether the currently loaded file is a waveform (ECG/hemodynamic/…) object
    /// with no displayable pixel data.
    public var isWaveform: Bool { waveform != nil }

    /// Parsed content when the loaded file is not a picture: a structured
    /// report, an encapsulated document, a key object selection, a presentation
    /// state. Non-nil disables the pixel path and drives the document display.
    public var nonImageContent: ViewerNonImageContent?

    /// Whether the loaded file holds something other than pixels or a waveform.
    public var isNonImageContent: Bool { nonImageContent != nil }

    /// The clip on screen, when the instance is a video.
    ///
    /// The one place that answers "is this a video?", so the player, the cine
    /// button and the tool gating cannot disagree about it.
    public var videoContent: DICOMKit.ExtractedVideo? {
        if case .video(let video) = nonImageContent { return video }
        return nil
    }

    /// Whether a clip is on screen.
    public var isVideoContent: Bool { videoContent != nil }

    /// Whether the cine transport applies to what is on screen — a multi-frame
    /// image or a video clip, both of which are things that run.
    public var hasCineTransport: Bool {
        isVideoContent || (isMultiFrame && hasImage && !isWaveform)
    }

    /// What kind of content the viewer is currently showing.
    public var contentKind: ViewerContentKind {
        if let nonImageContent { return nonImageContent.kind }
        return isWaveform ? .waveform : .image
    }

    /// Whether an image is currently loading.
    public var isLoading: Bool = false

    /// Error message if loading or rendering fails.
    public var errorMessage: String?

    // MARK: - Pixel Data Metadata

    /// Image rows (height).
    public var imageRows: Int = 0

    /// Image columns (width).
    public var imageColumns: Int = 0

    /// Bits allocated per sample.
    public var bitsAllocated: Int = 0

    /// Bits stored per sample.
    public var bitsStored: Int = 0

    /// High bit position.
    public var highBit: Int = 0

    /// Whether pixel values are signed.
    public var isSigned: Bool = false

    /// Samples per pixel.
    public var samplesPerPixel: Int = 1

    /// Planar configuration.
    public var planarConfiguration: Int = 0

    /// Photometric interpretation string.
    public var photometricInterpretation: String = ""

    /// Total number of frames.
    public var numberOfFrames: Int = 1

    /// Transfer syntax UID of the loaded file.
    public var transferSyntaxUID: String = ""

    /// Human-readable name for the current transfer syntax.
    public var transferSyntaxName: String = ""

    // MARK: - Window/Level State

    /// Current window center value.
    public var windowCenter: Double = 128.0 { didSet { printMarksFollowScreen(); presentationStateFollowsTools(); noteWindowAction() } }

    /// Current window width value.
    public var windowWidth: Double = 256.0 { didSet { printMarksFollowScreen(); presentationStateFollowsTools(); noteWindowAction() } }

    /// Whether grayscale is inverted.
    public var isInverted: Bool = false { didSet { printMarksFollowScreen(); presentationStateFollowsTools(); noteToolAction() } }

    /// The pseudo-colour palette the focused image is shown through.
    ///
    /// A display choice over the *windowed* grey, exactly as on film: the stored
    /// pixels are untouched, and the same measurement under two palettes is one
    /// measurement seen two ways. `nil` means nobody has chosen — see
    /// ``ViewerPresentation/palette`` for why that is not the same as choosing
    /// ``PseudoColorPalette/grayscale``.
    ///
    /// Set through ``applyPalette(_:)`` rather than assigned: unlike zoom and
    /// inversion, a palette is *pixels* and not an arrangement — the display
    /// shader can turn and crop a frame but it cannot colour one — so changing
    /// it has to re-render rather than redraw.
    public internal(set) var palette: DICOMCore.PseudoColorPalette? {
        didSet { printMarksFollowScreen(); noteToolAction() }
    }

    /// Available window presets for the current modality.
    public var availablePresets: [WindowLevelPreset] = []

    /// Window settings from the DICOM header.
    public var headerWindowSettings: [WindowSettings] = []

    /// Currently selected VOI LUT function.
    public var voiLUTFunction: String = "LINEAR"

    /// Rescale slope from the DICOM header (default 1.0).
    public var rescaleSlope: Double = 1.0

    /// Rescale intercept from the DICOM header (default 0.0).
    public var rescaleIntercept: Double = 0.0

    /// Where the Modality LUT the viewport renders through comes from.
    ///
    /// The image's own — its Modality LUT Sequence or Rescale pair — until a
    /// saved view is applied, then the view's: under a presentation state the
    /// state's Modality LUT replaces the image's, and an absent one is the
    /// identity ("Any Modality LUT or equivalent Attributes in the Image shall
    /// not be used", PS3.4 N.2.1.1). Back to the image's once a tool moves,
    /// when the picture is no longer the saved view.
    @ObservationIgnored var modalityLUTSource: DisplayModalityLUTSource = .image

    /// The file's VOI LUT Sequence table, when the file windows through a table
    /// rather than a centre and width (PS3.3 C.11.2, "one or the other"). Shown
    /// for as long as the window is the untouched default; a drag replaces it
    /// with the window the reader made.
    @ObservationIgnored private var defaultVOILUTTable: LUTData?

    // MARK: - Multi-Frame / Cine State

    /// Current frame index (0-based).
    public var currentFrameIndex: Int = 0 {
        didSet { if currentFrameIndex != oldValue { adoptFrameWindow(for: currentFrameIndex) } }
    }

    /// Whether the loaded file windows or rescales *per frame* — an Enhanced
    /// object whose Frame VOI LUT or Pixel Value Transformation macro sits in
    /// the Per-frame Functional Groups. Only then does paging re-derive the
    /// default window; a cine loop or shared-window volume pays nothing.
    public private(set) var hasPerFrameWindow = false

    /// The window ``applyDefaultWindow(for:slope:intercept:frameIndex:)`` last
    /// derived, in stored space, so a frame change can tell an untouched default
    /// (which follows the frame) from a reader's adjustment (which stays).
    private var frameDefaultWindow: (center: Double, width: Double)?

    /// Cine playback state.
    public var playbackState: PlaybackState = .stopped

    /// Cine playback mode.
    public var playbackMode: PlaybackMode = .loop

    /// Cine playback direction (for bounce mode).
    public var playbackDirection: PlaybackDirection = .forward

    /// Cine playback frames per second.
    public var playbackFPS: Double = CinePlaybackHelpers.defaultFPS

    /// Whether a multi-frame file starts looping the moment it opens.
    ///
    /// On by default: a multi-frame image is a moving picture, and a reader
    /// opening one is looking for the motion, not for frame 0 held still. The
    /// preference exists because that is not true of every multi-frame IOD —
    /// a CT stack is multi-frame too and is read by scrolling, not by playing.
    public var autoPlayMultiFrame: Bool = true

    // MARK: - Zoom / Pan / Rotation

    /// Current zoom level (1.0 = 100%).
    public var zoomLevel: Double = 1.0 { didSet { printMarksFollowScreen(); presentationStateFollowsTools(); noteToolAction() } }

    /// Pan offset X in points.
    public var panOffsetX: Double = 0.0 { didSet { printMarksFollowScreen(); presentationStateFollowsTools(); noteToolAction() } }

    /// Pan offset Y in points.
    public var panOffsetY: Double = 0.0 { didSet { printMarksFollowScreen(); presentationStateFollowsTools(); noteToolAction() } }

    /// Rotation angle in degrees.
    public var rotationAngle: Double = 0.0 { didSet { printMarksFollowScreen(); presentationStateFollowsTools(); noteToolAction() } }

    /// Whether the image is flipped horizontally.
    public var isFlippedHorizontal: Bool = false { didSet { printMarksFollowScreen(); presentationStateFollowsTools(); noteToolAction() } }

    /// Whether the image is flipped vertically.
    public var isFlippedVertical: Bool = false { didSet { printMarksFollowScreen(); presentationStateFollowsTools(); noteToolAction() } }

    // MARK: - Series-wide tool memory

    /// One series' tool arrangement — everything the toolbar can do to the
    /// picture, captured when the reader steps off the series and put back
    /// when they return. Zoom, pan, rotation, the flips, inversion, the
    /// palette and the window are statements about how the *series* is being
    /// read: they hold across every slice, survive a detour through another
    /// series, and end where the reader ends them — saving the arrangement as
    /// a presentation state, applying a saved view by hand, Reset, Default
    /// View, or a new study, which drops the lot. The drawn annotations are
    /// deliberately not here: they are per-image statements, and their store
    /// (`printSelection.cellAnnotations`) already keys them that way.
    struct SeriesToolState {
        var windowCenter: Double
        var windowWidth: Double
        /// Whether the window was the reader's doing. A window that merely
        /// arrived with a file is that file's statement, not the series', and
        /// must not overwrite the next file's own header window.
        var userAdjustedWindow: Bool
        var zoomLevel: Double
        var panOffsetX: Double
        var panOffsetY: Double
        var rotationAngle: Double
        var isFlippedHorizontal: Bool
        var isFlippedVertical: Bool
        var isInverted: Bool
        var palette: DICOMCore.PseudoColorPalette?
    }

    /// The unsaved tool arrangement of every series touched this study, keyed
    /// by Series Instance UID. Cleared by ``prepareForNewStudy()``.
    var toolStateBySeries: [String: SeriesToolState] = [:]

    /// The cache key of the image on screen — its Series Instance UID, or its
    /// file path when the file states none. `nil` while nothing cacheable is
    /// showing (a waveform, a report, an empty viewer).
    var currentToolCacheKey: String?

    /// Whether any tool has been moved in the current series — by the reader,
    /// not by a load, a tile focus change, or an applied view. Nothing is
    /// cached until one has: an untouched series has no arrangement worth
    /// remembering, and caching one would suppress the saved-view offers for
    /// no reason.
    var toolsTouchedInSeries = false

    /// Whether the reader has windowed in the current series — see
    /// ``SeriesToolState/userAdjustedWindow``.
    var userAdjustedWindowInSeries = false

    /// Set while a tile's stored arrangement is being copied onto the live
    /// view model — a restore, not a reader action.
    var restoringToolState = false

    /// Marks a tool moved by the reader. Loads, tile restores and applied
    /// views move the same properties, so their flags gate the observers'
    /// calls here.
    func noteToolAction() {
        guard !isLoading, !applyingPresentationState, !restoringToolState else { return }
        toolsTouchedInSeries = true
    }

    /// Marks the window as the reader's — a tool action with the extra fact
    /// that the *window* is now a series-wide statement.
    func noteWindowAction() {
        guard !isLoading, !applyingPresentationState, !restoringToolState else { return }
        toolsTouchedInSeries = true
        userAdjustedWindowInSeries = true
    }

    /// The key a file's tool state is cached under.
    static func toolCacheKey(dataSet: DataSet, path: String) -> String {
        if let uid = dataSet.string(for: .seriesInstanceUID)?
            .trimmingCharacters(in: .whitespaces), !uid.isEmpty {
            return uid
        }
        // A file that does not say what series it is in is its own series.
        return path
    }

    /// Snapshots the tools for the series being stepped off, if the reader has
    /// moved any. Called at the top of every load, before the new file's state
    /// overwrites what this reads.
    func cacheToolStateForCurrentSeries() {
        guard let key = currentToolCacheKey, toolsTouchedInSeries else { return }
        toolStateBySeries[key] = SeriesToolState(
            windowCenter: windowCenter,
            windowWidth: windowWidth,
            userAdjustedWindow: userAdjustedWindowInSeries,
            zoomLevel: zoomLevel,
            panOffsetX: panOffsetX,
            panOffsetY: panOffsetY,
            rotationAngle: rotationAngle,
            isFlippedHorizontal: isFlippedHorizontal,
            isFlippedVertical: isFlippedVertical,
            isInverted: isInverted,
            palette: palette)
    }

    /// Forgets the current series' cached arrangement.
    ///
    /// Called at the moments the memory is finished with: the arrangement was
    /// saved as a presentation state (the store now holds it), a saved view
    /// was applied by hand (the reader replaced it), or Reset / Default View
    /// put the series back to the files' own pictures.
    func forgetSeriesToolState() {
        if let key = currentToolCacheKey { toolStateBySeries[key] = nil }
        toolsTouchedInSeries = false
        userAdjustedWindowInSeries = false
    }

    /// Seeds a freshly hung tile with its series' cached arrangement, so the
    /// grid path shows a returning series the way the reader left it — the
    /// same statement ``loadDICOMData``'s restore makes for the 1×1 viewer.
    /// A series with no cached arrangement leaves the tile at its defaults.
    func seedCellFromToolCache(_ cell: inout ViewerCellState, seriesUID: String?) {
        guard let seriesUID, let cached = toolStateBySeries[seriesUID] else { return }
        cell.zoom = cached.zoomLevel
        cell.panX = cached.panOffsetX
        cell.panY = cached.panOffsetY
        cell.rotationAngle = cached.rotationAngle
        cell.isFlippedHorizontal = cached.isFlippedHorizontal
        cell.isFlippedVertical = cached.isFlippedVertical
        cell.isInverted = cached.isInverted
        cell.palette = cached.palette
        // The window only when the reader dialled it; a nil window makes the
        // tile read at the file's own VOI — see ``restoreArrangement(of:)``.
        if cached.userAdjustedWindow {
            cell.windowCenter = cached.windowCenter
            cell.windowWidth = cached.windowWidth
        }
    }

    /// Detaches the viewer from the cache while non-image content shows: a
    /// waveform has no tools to remember, and a snapshot taken while one is up
    /// would file the previous image's state under the wrong moment.
    func detachFromToolCache() {
        currentToolCacheKey = nil
        toolsTouchedInSeries = false
        userAdjustedWindowInSeries = false
    }

    /// Whether the image-metadata popup is open.
    ///
    /// A popup rather than a corner block. The block was anchored over the
    /// picture's bottom-left, which is where the zoom, image number and
    /// compression lines of the reading annotations already are — so switching
    /// it on laid file, dimensions and transfer syntax straight over the
    /// annotations a reader reads the image by. Presenting it the way the tag
    /// inspector is presented gives it room for the full block, keeps the
    /// picture clear, and makes the two "tell me about this file" surfaces
    /// behave the same way.
    public var showMetadataOverlay: Bool = false

    /// What the open file says, for the corner annotations.
    ///
    /// Read once when the file loads rather than on every draw: the values are a
    /// header's worth of strings and none of them changes while the file is
    /// open, whereas the viewport redraws on every mouse delta of a window drag.
    /// See `ImageViewerViewModel+Annotations.swift`.
    public internal(set) var annotationText = ViewerAnnotationText()

    /// Whether the reading annotations are drawn in the viewport's corners.
    ///
    /// On by default: a workstation that does not say who the patient is, what
    /// window the picture is under and where in the series it sits is not a
    /// workstation. Film is a separate decision — it carries the identification
    /// strip below the picture instead, and has its own switch.
    /// See `ImageViewerViewModel+Annotations.swift`.
    public var showImageAnnotations: Bool = true

    /// Whether the patient-orientation letters are drawn at the four edges.
    ///
    /// On by default, and separate from ``showImageAnnotations`` because it is
    /// a different kind of statement. The corner blocks describe the picture —
    /// who, what window, which frame — and a reader who knows the study can
    /// work without them. The edge letters say which side of the patient is
    /// which, and that is the one thing on screen no reader can derive from
    /// looking: an axial slice is very nearly symmetric, so with the letters
    /// off there is nothing distinguishing left from right.
    ///
    /// So it is a switch rather than a removal. A reader who finds the letters
    /// noisy on a modality where laterality is not in question — a sagittal
    /// topogram, a screen shared for teaching — can turn them off, and the
    /// default keeps the marker where the safety case wants it.
    public var showOrientationLabels: Bool = true

    /// Whether the DICOM tag inspector sheet is visible.
    public var showDICOMInspector: Bool = false

    // MARK: - Series / Multi-File Navigation

    /// All file paths in the current series (empty when viewing a standalone file).
    public var seriesFiles: [String] = []

    /// Index of the currently displayed file within `seriesFiles`.
    public var currentFileIndex: Int = 0

    /// Security-scoped parent URL shared by all files in the current series.
    public var seriesSecurityScopedParent: URL? = nil

    /// Whether the viewer is navigating a multi-file series.
    public var isInSeries: Bool { seriesFiles.count > 1 }

    /// Whether there is a previous file to navigate to.
    public var canGoPreviousFile: Bool { currentFileIndex > 0 }

    /// Whether there is a next file to navigate to.
    public var canGoNextFile: Bool { currentFileIndex < seriesFiles.count - 1 }

    // MARK: - Services

    /// Image rendering service.
    public let renderingService: ImageRenderingService

    /// Image cache service.
    public let cacheService: ImageCacheService

    /// Codec-aware image decoding service (Phase 8).
    public let decodingService: ImageDecodingService

    // MARK: - Performance

    /// Last render time in seconds.
    public var lastRenderTime: Double = 0.0

    // MARK: - DICOM Print

    /// Frames marked for printing, in film-cell order.
    ///
    /// Marking happens here in the viewer; the print sheet consumes this list.
    /// See `ImageViewerViewModel+Print.swift` for the marking API.
    public var printSelection = PrintSelectionModel()

    /// A request for the print screen — the sheet off macOS, the print preview
    /// window on it. Raised by ⌘P and by the library's "Print…"; on macOS the
    /// presenter lowers it again once the window is up, since a window's own
    /// state is the window's, not this flag's.
    public var isPrintSheetPresented: Bool = false

    /// Bumped when the print screen has to come down with the study it belongs
    /// to. A counter rather than a flag: a window is dismissed by an event, and
    /// two studies opened in a row must send two of them.
    ///
    /// Off macOS ``isPrintSheetPresented`` going false closes the sheet on its
    /// own; this is what reaches the separate window.
    public private(set) var printScreenDismissRequests: Int = 0

    /// Whether the print screen is standing in for the viewer's own columns.
    ///
    /// On macOS the print screen takes over the centre panel: the series pane,
    /// the reading area and the print tray step aside — and their toolbar,
    /// toggles included, goes with them — until the film is printed or put
    /// away. One flag rather than three pane flags forced off, so the panes
    /// come back exactly as the reader had them: nothing was collapsed, the
    /// whole column was swapped.
    public var isPrintScreenEmbedded: Bool = false

    /// Asks for the print screen to be closed.
    public func requestPrintScreenDismissal() {
        isPrintSheetPresented = false
        isPrintScreenEmbedded = false
        printScreenDismissRequests += 1
    }

    /// Whether the tray of selected images is showing on the right.
    ///
    /// Out of the way until there is something in it. A reader opens the viewer
    /// to read, and an empty column headed "On film" is a third of the chrome
    /// spent saying "nothing yet"; the moment an image is marked the tray comes
    /// up on its own — see ``revealPrintTray()``.
    public var isPrintTrayVisible: Bool = false

    // MARK: - Tile Layout

    /// The viewer's tile grid. 1×1 by default — one image, as before.
    ///
    /// The grid mirrors the film: tile order is film-cell order. See
    /// `ImageViewerViewModel+Layout.swift`.
    public internal(set) var layout: ViewerTileLayout = .single

    /// What the grid is a grid *of* — one series per tile, or one image per tile.
    ///
    /// Series-led is the default because it is the reading a grid is usually
    /// wanted for and because it is what the grid has always done; the wheel
    /// already walks a stack one tile at a time. Kept beside ``layout`` rather
    /// than passed to ``applyLayout(_:)`` so that changing the mode re-fills the
    /// grid on its own — the reader picks "Image" and the tiles change under
    /// them, without having to re-choose the shape they already chose.
    public internal(set) var layoutFill: ViewerLayoutFill = .series

    /// Per-tile state. Empty at 1×1, where the view model itself is the tile.
    public internal(set) var cells: [ViewerCellState] = []

    /// The tile currently receiving gestures and window/level.
    public internal(set) var focusedCellIndex: Int = 0

    // MARK: - Study Series

    /// Every series of the open study, for the viewer's series pane.
    ///
    /// Populated by the shell from the library. Empty when the viewer was given
    /// loose files rather than a study, in which case the pane stays hidden.
    /// See `ImageViewerViewModel+Series.swift`.
    public internal(set) var studySeries: [ViewerSeriesEntry] = []

    /// Study Instance UID of the series in ``studySeries``.
    public internal(set) var studyInstanceUID: String?

    /// Series the focused tile is showing, for the pane's "Current series" mark.
    public internal(set) var currentSeriesUID: String?

    // MARK: - Saved views (presentation states)

    /// Where saved views are kept. See `ImageViewerViewModel+PresentationStates.swift`.
    ///
    /// Nil only when the app-support directory could not be reached, in which
    /// case the picker stays hidden rather than offering a save that would fail.
    public internal(set) var presentationStateStore: PresentationStateStore? =
        try? PresentationStateStore.applicationSupport()

    /// Series Instance UIDs of the image series that have at least one saved
    /// view. What the series pane's badge reads.
    ///
    /// Cached rather than computed: answering from the store means parsing
    /// every presentation-state file of the study, and the pane asks once per
    /// card per render. Refreshed where the answer can change — the study
    /// loading, a view being saved, a view being deleted.
    public internal(set) var savedViewSeriesUIDs: Set<String> = []

    /// The presentation-state objects of the study, grouped by the image series
    /// they describe. What the series pane's PR list reads.
    ///
    /// Cached alongside ``savedViewSeriesUIDs`` and refreshed by the same call,
    /// for the same reason: the answer costs a parse of every presentation
    /// state in the study, and the pane would ask once per card per render.
    public internal(set) var savedViewReferencesBySeries: [String: [SavedViewReference]] = [:]

    /// The saved view being shown, or nil for the image as the file describes it.
    ///
    /// Names the view rather than holding it: the store is the authority, and a
    /// label survives the list being reloaded after a save or a delete.
    public internal(set) var selectedPresentationStateLabel: String?

    /// Set while a saved view is being applied.
    ///
    /// The tool paths clear ``selectedPresentationStateLabel`` so a moved tool
    /// stops claiming to be a saved view; applying one moves those same tools,
    /// and without this guard would clear its own selection.
    var applyingPresentationState: Bool = false

    /// Whatever went wrong saving or deleting a view, for the viewer to show.
    public internal(set) var presentationStateError: String?

    /// The saved views to offer the reader for the image just opened.
    ///
    /// Non-nil for as long as the prompt is on screen. Opening an image that
    /// has saved views is the one moment where the choice between them and the
    /// file's own view is live — the reader has not yet adjusted anything, so
    /// applying a view costs them nothing, and *not* offering it means a view
    /// they saved yesterday is quietly ignored until they think to open the
    /// picker. Hence a prompt rather than a silent apply: which of three
    /// windows a slice should be read at is the reader's call, not the app's.
    public internal(set) var savedViewPrompt: SavedViewPrompt?

    /// The series a saved view was last published into the study as.
    ///
    /// Held so the viewer can confirm what happened and name the reference ID
    /// the reader is meant to quote — a publish that says nothing looks like a
    /// button that does nothing, since the new series only shows in the pane
    /// after the shell has filed it.
    public internal(set) var publishedPresentationSeries: PresentationStateStore.PublishedSeries?

    /// Bumped whenever a saved view has been published into the study.
    ///
    /// A counter rather than a flag, for the same reason as the print screen's
    /// dismissal: the shell has to re-read the study's files each time, and
    /// publishing two views in a row must ask twice.
    public internal(set) var presentationSeriesPublishRequests: Int = 0

    /// The presentation states just removed from the study's series.
    ///
    /// Named by SOP Instance UID, which is what the library files them under.
    public internal(set) var unpublishedPresentationStateUIDs: [String] = []

    /// Bumped whenever presentation states have been removed from the study.
    ///
    /// Separate from ``presentationSeriesPublishRequests`` because the shell
    /// does the opposite thing with it: one adds instances to the library's
    /// index, the other takes them out.
    public internal(set) var presentationSeriesRemovalRequests: Int = 0

    // MARK: - Study download

    /// The question asked before the open study leaves the app as a ZIP.
    ///
    /// Non-nil once the archive has been built and measured: the prompt names
    /// the ZIP's exact size so the reader confirms — or declines — knowing what
    /// they are about to write. See `ImageViewerViewModel+StudyDownload.swift`.
    public internal(set) var studyDownloadPrompt: StudyDownloadPrompt?

    /// Set while the study's files are being staged and compressed.
    public internal(set) var isPreparingStudyDownload: Bool = false

    /// Whatever went wrong building the study's ZIP, for the viewer to show.
    public internal(set) var studyDownloadError: String?

    /// The view each image is currently being read at, keyed by SOP Instance UID.
    ///
    /// A choice about a slice, not about a moment: applying a saved view is the
    /// reader saying "this is how I am reading *this* image", and stepping to
    /// the next slice and back must not quietly undo it. So the choice is
    /// recorded here and re-applied on arrival, and the image keeps that
    /// reading until the reader changes it — to another view, or to the default.
    ///
    /// The label alone could not do this. It is a single value describing
    /// whatever is on screen, and nothing clears it on load, so after a step it
    /// names a view of the slice just left. Keying by image is what separates
    /// "this image is being read at the bone window" from "the previous one was".
    ///
    /// An absent key means the image has no standing choice, which is what
    /// makes it a candidate for the prompt. A key holding nil is the reader
    /// having chosen the default view — a real answer, and one that must
    /// survive the round trip just as a saved view does.
    @ObservationIgnored var appliedViewByImage: [String: String?] = [:]

    /// Whether the window on screen is one the reader chose.
    ///
    /// A window differing from the file's is worth naming a view for; one that
    /// matches it adds nothing the file does not already say.
    var hasReaderChosenWindow: Bool {
        guard let file = dicomFile else { return false }
        let fileCenter = file.dataSet.decimalStrings(for: .windowCenter)?.first?.value
        let fileWidth = file.dataSet.decimalStrings(for: .windowWidth)?.first?.value
        guard let fileCenter, let fileWidth else {
            // No window in the file: any window on screen was computed or chosen.
            return true
        }
        // Stored-value space, so the comparison is against the same units the
        // viewer holds. A hair of drift is not a reader's decision.
        let center = rescaleSlope != 0 ? (windowCenter * rescaleSlope + rescaleIntercept) : windowCenter
        let width = rescaleSlope != 0 ? (windowWidth * rescaleSlope) : windowWidth
        return abs(center - fileCenter) > 0.5 || abs(width - fileWidth) > 0.5
    }

    /// Series shown in a tile at some point this session.
    ///
    /// Tracked so the pane can distinguish what has been looked at from what has
    /// not — the reading-completeness cue a "Not yet visited" card carries.
    public internal(set) var visitedSeriesUIDs: Set<String> = []

    /// Whether the series pane is showing.
    public var isSeriesPaneVisible: Bool = true

    /// Whether stepping past either end of the series wraps round to the other.
    ///
    /// On by default: a tile is scrolled through with the wheel, and stopping
    /// dead at the last image reads as a stuck viewer rather than as the end of
    /// the series. See `ImageViewerViewModel+ImageNavigation.swift`.
    public var isRepeatNavigationEnabled: Bool = true

    // MARK: - Codec Inspector (Phase 8)

    /// Codec inspector state — populated after each successful decode.
    public var codecInspector = CodecInspectorViewModel()

    // MARK: - J2KSwift Testing Panel

    /// J2KSwift implementation testing state (benchmark, round-trip, platform probe).
    public var j2kTesting = J2KTestingViewModel()

    // MARK: - JPIP Streaming (Phase 8)

    /// JPIP server URL string for remote streaming.
    /// Set this before calling ``loadFromJPIP()``.
    public var jpipURLString: String = ""

    /// Current JPIP loading state.
    public var jpipLoadingState: JPIPLoadingState = .idle

    /// Whether ROI-based decoding should be active at the current zoom level.
    ///
    /// Set to `true` automatically when zoom exceeds 2× and a JPIP URL is configured.
    public var isROIActiveOnZoom: Bool = false

    // MARK: - Progressive Decode (Phase 8)

    /// The current state of the progressive JPEG 2000 decode pipeline.
    ///
    /// Observe this property to update the quality-level badge in the viewer.
    public var progressiveDecodeState: ProgressiveDecodeState = .idle

    #if canImport(CoreGraphics)
    /// The most recently received progressive CGImage (quarter, half, or full resolution).
    ///
    /// This image replaces `currentImage` during the progressive decode sequence
    /// and is identical to it once the final full-resolution level is delivered.
    public var progressiveImage: CGImage?
    #endif

    /// Internal task handle for the active progressive decode. Cancelled when a new file loads.
    private var progressiveDecodeTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates an image viewer ViewModel with dependency-injected services.
    public init(
        renderingService: ImageRenderingService = ImageRenderingService(),
        cacheService: ImageCacheService = ImageCacheService(),
        decodingService: ImageDecodingService = ImageDecodingService()
    ) {
        self.renderingService = renderingService
        self.cacheService = cacheService
        self.decodingService = decodingService
    }

    // MARK: - File Loading

    /// Loads a DICOM file for viewing.
    ///
    /// - Parameter path: File path to load.
    public func loadFile(at path: String) {
        clearSeriesState()
        loadFileInternal(at: path, securityScopedParent: nil)
    }

    /// Loads a DICOM file for viewing, using a security-scoped parent URL
    /// for sandbox access if needed.
    ///
    /// - Parameters:
    ///   - path: File path to load.
    ///   - securityScopedParent: Optional parent URL with security-scoped access rights.
    public func loadFile(at path: String, securityScopedParent: URL?) {
        clearSeriesState()
        loadFileInternal(at: path, securityScopedParent: securityScopedParent)
    }

    // MARK: - Series Navigation

    /// Loads a set of DICOM files as a navigable series and displays the file at `startIndex`.
    ///
    /// - Parameters:
    ///   - files: Ordered list of file paths belonging to the series.
    ///   - startIndex: Index of the file to display first (clamped to valid range).
    ///   - securityScopedParent: Optional security-scoped parent URL covering all files.
    public func loadSeries(files: [String], startIndex: Int = 0, securityScopedParent: URL? = nil) {
        guard !files.isEmpty else { return }
        let idx = max(0, min(startIndex, files.count - 1))
        seriesFiles = files
        currentFileIndex = idx
        seriesSecurityScopedParent = securityScopedParent
        loadFileInternal(at: files[idx], securityScopedParent: securityScopedParent)
    }

    /// Navigates to the previous file in the series.
    public func navigateToPreviousFile() {
        guard canGoPreviousFile else { return }
        currentFileIndex -= 1
        loadFileInternal(at: seriesFiles[currentFileIndex], securityScopedParent: seriesSecurityScopedParent)
    }

    /// Navigates to the next file in the series.
    public func navigateToNextFile() {
        guard canGoNextFile else { return }
        currentFileIndex += 1
        loadFileInternal(at: seriesFiles[currentFileIndex], securityScopedParent: seriesSecurityScopedParent)
    }

    // MARK: - Internal Helpers

    /// Clears series navigation state. Called when a standalone file is opened directly.
    private func clearSeriesState() {
        seriesFiles = []
        currentFileIndex = 0
        seriesSecurityScopedParent = nil
        cancelProgressiveDecode()
    }

    /// Internal file loader that does NOT reset series state.
    /// Used by both the public loadFile methods (after they clear series state)
    /// and by series navigation methods.
    /// Loads a file *without* touching series state.
    ///
    /// Internal rather than private so tile focus can move between files of the
    /// loaded series: `loadFile(at:)` clears the series, which would throw away
    /// navigation the moment the user clicked a second tile.
    func loadFileInternal(at path: String, securityScopedParent: URL?) {
        if let scopedURL = securityScopedParent {
            isLoading = true
            errorMessage = nil
            let accessing = scopedURL.startAccessingSecurityScopedResource()
            defer { if accessing { scopedURL.stopAccessingSecurityScopedResource() } }
            do {
                let url = URL(fileURLWithPath: path)
                let data = try Data(contentsOf: url)
                try loadDICOMData(data, path: path)
            } catch {
                errorMessage = "Failed to load file: \(error.localizedDescription)"
                isLoading = false
            }
        } else {
            isLoading = true
            errorMessage = nil
            do {
                let url = URL(fileURLWithPath: path)
                let data = try Data(contentsOf: url)
                try loadDICOMData(data, path: path)
            } catch {
                errorMessage = "Failed to load file: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    /// Returns whether the data set represents a Waveform IOD.
    ///
    /// Detects by SOP Class UID — the `1.2.840.10008.5.1.4.1.1.9.*` arc of PS3.6
    /// Table A-1 holds the Waveform Storage classes, except its `.9.100.*`
    /// branch, which is the two Waveform Presentation State Storage classes
    /// (objects about waveforms, with no Waveform Sequence of their own) — or
    /// by the presence of a Waveform Sequence, so legacy files with a
    /// missing/other SOP Class UID but valid waveform data are still recognized.
    private static func isWaveformFile(_ ds: DataSet) -> Bool {
        if let sopClass = ds.string(for: .sopClassUID)?.trimmingCharacters(in: .whitespaces),
           sopClass.hasPrefix("1.2.840.10008.5.1.4.1.1.9."),
           !sopClass.hasPrefix("1.2.840.10008.5.1.4.1.1.9.100.") {
            return true
        }
        return ds.sequence(for: .waveformSequence)?.isEmpty == false
    }

    /// The frame rate the file asks to be played at, if it states one.
    ///
    /// Three tags can carry it, and they are read in the order the standard
    /// prefers: Recommended Display Frame Rate (0008,2144) is the display
    /// instruction, Cine Rate (0018,0040) is the rate the equipment captured
    /// at, and Frame Time (0018,1063) gives the interval in milliseconds, which
    /// inverts to a rate. Returns `nil` when the file states none of them, so
    /// the caller can keep the reader's own setting rather than reset it.
    private static func headerFrameRate(in ds: DataSet) -> Double? {
        func number(_ tag: Tag) -> Double? {
            guard let raw = ds.string(for: tag)?.trimmingCharacters(in: .whitespaces),
                  let value = Double(raw), value > 0 else { return nil }
            return value
        }

        if let rate = number(.recommendedDisplayFrameRate) { return rate }
        if let rate = number(.cineRate) { return rate }
        // Frame Time is a per-frame interval in milliseconds: 33.3 ms → 30 fps.
        if let milliseconds = number(.frameTime) { return 1000.0 / milliseconds }
        return nil
    }

    /// Shared implementation for loading parsed DICOM data.
    private func loadDICOMData(_ data: Data, path: String) throws {
        // The series being stepped off keeps its tool arrangement — captured
        // before anything below mutates the state it reads. See
        // ``SeriesToolState``.
        cacheToolStateForCurrentSeries()

        // Clear any prior waveform so a failed/non-waveform load can't leave a stale
        // tracing on screen. The same holds for a report or document.
        self.waveform = nil
        self.nonImageContent = nil

        let file: DICOMFile
        do {
            file = try DICOMFile.read(from: data)
        } catch {
            // Retry with force=true for legacy DICOM files without Part 10 header
            file = try DICOMFile.read(from: data, force: true)
        }

        self.dicomFile = file
        // A new image renders through its own Modality LUT until a view is applied.
        modalityLUTSource = .image
        // The decoded pixels belong to the *previous* file. Anything that assigns
        // `dicomFile` must clear them, or the viewport shows the last image's pixels
        // under the new one's window. This is the only assignment site; keep it that
        // way, or move the call next to the new one.
        invalidateDecodedPixels()
        self.filePath = path
        self.sopInstanceUID = file.dataSet.string(for: .sopInstanceUID)

        let ds = file.dataSet
        let fmi = file.fileMetaInformation

        // Extract transfer syntax information
        let tsUID = fmi.string(for: .transferSyntaxUID)
            ?? ds.string(for: .transferSyntaxUID)
            ?? file.transferSyntaxUID
            ?? ""
        self.transferSyntaxUID = tsUID
        self.transferSyntaxName = ImageMetadataHelpers.transferSyntaxLabel(for: tsUID)
        self.annotationText = ViewerAnnotationText.make(from: ds, transferSyntaxUID: tsUID)

        // Waveform IODs (ECG, hemodynamic, EP, audio, …) carry a Waveform Sequence
        // instead of Pixel Data. Detect and parse them here so the viewer can render
        // a waveform tracing rather than failing the pixel-rendering path with an
        // "unable to render pixel data" error.
        if Self.isWaveformFile(ds),
           let parsed = try? WaveformParser.parse(from: ds),
           !parsed.multiplexGroups.isEmpty {
            self.waveform = parsed
            self.currentImage = nil
            self.numberOfFrames = 1
            self.currentFrameIndex = 0
            self.errorMessage = nil
            self.isLoading = false
            detachFromToolCache()
            return
        }

        // Reports, encapsulated documents, key object selections and
        // presentation states carry no Pixel Data; a video's Pixel Data is an
        // encoded bit stream no still-image codec can decode. All are
        // classified before the pixel path runs: falling through would report
        // a perfectly valid SR — or a playable clip — as an image that failed
        // to decode.
        if let content = ViewerNonImageContentReader.content(
            of: ds, sopClassUID: ds.string(for: .sopClassUID),
            transferSyntaxUID: file.transferSyntaxUID) {
            self.nonImageContent = content
            self.currentImage = nil
            self.numberOfFrames = 1
            self.currentFrameIndex = 0
            self.errorMessage = nil
            self.isLoading = false
            // A clip opens running for the same reason a multi-frame image
            // does — the motion is the content. Everything else with no pixels
            // has nothing to play and stays stopped, which is also what keeps
            // the toolbar's cine button off a report.
            self.playbackMode = .loop
            self.playbackState = (content.kind == .video && autoPlayMultiFrame)
                ? .playing : .stopped
            detachFromToolCache()
            return
        }

        // Read metadata directly from current file tags first.
        // This ensures overlay values match what is actually stored in the
        // currently loaded DICOM file (including transcoded outputs).
        imageRows = ds.uint16(for: .rows).map(Int.init) ?? 0
        imageColumns = ds.uint16(for: .columns).map(Int.init) ?? 0
        bitsAllocated = ds.uint16(for: .bitsAllocated).map(Int.init) ?? 0
        bitsStored = ds.uint16(for: .bitsStored).map(Int.init) ?? 0
        highBit = ds.uint16(for: .highBit).map(Int.init) ?? 0
        isSigned = (ds.uint16(for: .pixelRepresentation) ?? 0) == 1
        samplesPerPixel = ds.uint16(for: .samplesPerPixel).map(Int.init) ?? 1
        planarConfiguration = ds.uint16(for: .planarConfiguration).map(Int.init) ?? 0
        photometricInterpretation = ds.string(for: .photometricInterpretation) ?? ""
        numberOfFrames = ds.string(for: .numberOfFrames)
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            ?? 1

        // Fallback to pixel descriptor for missing tags only.
        if let descriptor = file.pixelDataDescriptor() {
            if imageRows == 0 { imageRows = descriptor.rows }
            if imageColumns == 0 { imageColumns = descriptor.columns }
            if bitsAllocated == 0 { bitsAllocated = descriptor.bitsAllocated }
            if bitsStored == 0 { bitsStored = descriptor.bitsStored }
            if highBit == 0 && descriptor.highBit != 0 { highBit = descriptor.highBit }
            if samplesPerPixel == 0 { samplesPerPixel = descriptor.samplesPerPixel }
            if planarConfiguration == 0 && descriptor.samplesPerPixel > 1 {
                planarConfiguration = descriptor.planarConfiguration
            }
            if photometricInterpretation.isEmpty {
                photometricInterpretation = descriptor.photometricInterpretation.rawValue
            }
            if numberOfFrames <= 0 { numberOfFrames = descriptor.numberOfFrames }
            if ds.uint16(for: .pixelRepresentation) == nil {
                isSigned = descriptor.isSigned
            }
        }

        // Extract rescale parameters for window correction — frame 0's on an
        // Enhanced object, the file's otherwise (the accessors fall back to the
        // functional groups themselves).
        hasPerFrameWindow = file.dataSet.hasPerFrameWindowOrRescale
        let slope = file.rescaleSlope(frameIndex: 0)
        let intercept = file.rescaleIntercept(frameIndex: 0)
        self.rescaleSlope = slope
        self.rescaleIntercept = intercept

        // Extract window settings from header
        applyDefaultWindow(for: file, slope: slope, intercept: intercept, frameIndex: 0)

        // Load modality presets
        let modality = file.dataSet.string(for: .modality) ?? ""
        availablePresets = WindowLevelPresets.presets(for: modality)

        // Reset viewer state
        currentFrameIndex = 0
        playbackDirection = .forward
        // What the file says it should be played at, before deciding whether to
        // play it. A file with no rate keeps whatever the reader last dialled in.
        if let headerFPS = Self.headerFrameRate(in: ds) {
            playbackFPS = CinePlaybackHelpers.clampFPS(headerFPS)
        }
        // A multi-frame image opens running, so the motion is visible without
        // the reader having to find the transport bar first. Single-frame files
        // have nothing to play, and stay stopped.
        playbackMode = .loop
        playbackState = (numberOfFrames > 1 && autoPlayMultiFrame) ? .playing : .stopped
        // Every tool back to the file's own picture first — then, if the
        // reader has an unsaved arrangement standing over this series, that
        // arrangement back over it. The tools are series-wide: zoom, window,
        // rotation, the flips, inversion and colour are how the *series* is
        // being read, so stepping slice to slice keeps them, stepping to
        // another series swaps them for that series' own, and coming back
        // restores them — until the arrangement is saved as a presentation
        // state, reset, or the study closes. See ``SeriesToolState``.
        zoomLevel = 1.0
        panOffsetX = 0.0
        panOffsetY = 0.0
        rotationAngle = 0.0
        isFlippedHorizontal = false
        isFlippedVertical = false
        isInverted = false
        palette = nil
        let toolKey = Self.toolCacheKey(dataSet: ds, path: path)
        currentToolCacheKey = toolKey
        if let cached = toolStateBySeries[toolKey] {
            zoomLevel = cached.zoomLevel
            panOffsetX = cached.panOffsetX
            panOffsetY = cached.panOffsetY
            rotationAngle = cached.rotationAngle
            isFlippedHorizontal = cached.isFlippedHorizontal
            isFlippedVertical = cached.isFlippedVertical
            isInverted = cached.isInverted
            palette = cached.palette
            // The window only when the reader dialled it: a header window
            // that merely tagged along in a snapshot belongs to the slice it
            // came from, and this slice has just applied its own above.
            if cached.userAdjustedWindow {
                windowCenter = cached.windowCenter
                windowWidth = cached.windowWidth
            }
            toolsTouchedInSeries = true
            userAdjustedWindowInSeries = cached.userAdjustedWindow
        } else {
            toolsTouchedInSeries = false
            userAdjustedWindowInSeries = false
        }
        if isMultiCellLayout, cells.indices.contains(focusedCellIndex) {
            cells[focusedCellIndex].palette = palette
        }

        // Render first frame
        renderCurrentFrame()

        // Populate the codec inspector with metadata for this file (Phase 8)
        let inspectorStatus = decodingService.inspectorStatus(for: file)
        switch inspectorStatus {
        case .uncompressed:
            codecInspector.status = inspectorStatus
        default:
            // For compressed files, do a timed decode to populate timing info
            if let result = decodingService.decode(file: file) {
                codecInspector.update(from: result, frameCount: numberOfFrames)
            } else {
                codecInspector.status = inspectorStatus
            }
        }

        isLoading = false

        // Start progressive decode for J2K/HTJ2K files (Phase 8).
        startProgressiveDecode()

        // The label describes what was on screen a moment ago, which is the
        // slice being left. The new image's own reading is restored just below
        // if it has one, so this only has to stop the stale name standing in
        // for it in the meantime.
        selectedPresentationStateLabel = nil

        // The image is now identified, so its standing view can be put back —
        // or, if it has none, its saved views offered. Harmless when the study
        // pane has not arrived yet: it calls this too, and whichever is last
        // does the work.
        offerSavedViewsIfNeeded()
    }

    // MARK: - Decoded pixel cache

    /// The decoded pixels behind the focused viewport, held across re-windows.
    ///
    /// ``renderCurrentFrame()`` runs on **every** window/level delta, and it used to
    /// reach the pixels through `DICOMFile.tryRenderFrame` → `tryPixelData()`, which
    /// decodes from scratch each call. So a drag re-ran the codec once per mouse
    /// event. Measured on a 2048×2500 CR (Apple M4, release), per drag step:
    ///
    /// | Transfer syntax | decoding each step | cached |
    /// |---|---|---|
    /// | Uncompressed | 2.319 ms | 0.570 ms |
    /// | JPEG 2000 lossless | 16.161 ms | 0.558 ms |
    /// | JPEG-LS lossless | 74.120 ms | 0.589 ms |
    /// | RLE lossless | 354.986 ms | 0.526 ms |
    ///
    /// RLE was under three frames a second. Note the uncompressed row: its decode is
    /// 0.001 ms, so the 1.7 ms it still saves is `PixelData.frameData(at:)` copying
    /// the frame out on every call. That is why this caches **both** compressed and
    /// uncompressed sources rather than only the expensive-looking case.
    ///
    /// The tile and film path has done this since `FrameSourceCache` was written;
    /// the focused viewport simply never got the same treatment.
    @ObservationIgnored private var decodedPixels: PixelData?
    @ObservationIgnored private var decodedPalette: PaletteColorLUT?
    @ObservationIgnored private var decodeFailure: (any Error)?
    @ObservationIgnored private var decodeAttempted = false

    /// Whether to page-align cached pixels so the GPU can read them in place.
    /// Resolved once — the backend cannot change during a run.
    @ObservationIgnored
    private static let alignsForGPU = FrameRenderService.shared.prefersAlignedPixelData

    /// Forgets the decoded pixels. **Must** be called whenever `dicomFile` changes,
    /// or the viewport would keep showing the previous image's pixels.
    private func invalidateDecodedPixels() {
        decodedPixels = nil
        decodedPalette = nil
        decodeFailure = nil
        decodeAttempted = false
    }

    /// The decoded pixels for the loaded file, decoding on first use.
    ///
    /// A failed decode is cached too: without that, a file with no usable pixel data
    /// would re-attempt — and re-fail — the full decode on every render, which is the
    /// same per-event cost this cache exists to remove.
    private func decodedPixelSource(for file: DICOMFile) throws -> (PixelData, PaletteColorLUT?) {
        if let decodedPixels { return (decodedPixels, decodedPalette) }
        if decodeAttempted, let decodeFailure { throw decodeFailure }

        decodeAttempted = true
        do {
            let decoded = try file.tryPixelData()
            // Aligned once, here — never per render.
            let prepared = Self.alignsForGPU ? decoded.pageAligned() : decoded
            decodedPixels = prepared
            decodedPalette = file.dataSet.paletteColorLUT()
            return (prepared, decodedPalette)
        } catch {
            decodeFailure = error
            throw error
        }
    }

    /// The stored value of one pixel of the current frame, or `nil` when the
    /// pixels cannot be read.
    ///
    /// Reads the same decoded pixels the viewport is drawn from — the ones
    /// already held above — so a cursor moving across the image costs a lookup
    /// rather than a decode. Colour images answer their three samples instead.
    func storedPixelValue(column: Int, row: Int) -> (gray: Int?, rgb: (Int, Int, Int)?) {
        guard let file = dicomFile,
              let source = try? decodedPixelSource(for: file) else { return (nil, nil) }
        let pixels = source.0
        if samplesPerPixel >= 3 {
            let colour = pixels.colorValue(row: row, column: column, frame: currentFrameIndex)
            return (nil, colour)
        }
        return (pixels.pixelValue(row: row, column: column, frame: currentFrameIndex), nil)
    }

    // MARK: - GPU display path

    #if canImport(Metal)
    /// Whether this frame can be shown straight from a GPU texture.
    ///
    /// The one thing the display path does not do is burn overlay planes. Those are
    /// drawn *over* the image rather than into it, and some Secondary Captures —
    /// Siemens' Patient Protocol is the standing example — carry all-zero pixel data
    /// with their entire content in a 1-bit overlay. Showing the texture for one of
    /// those would present a black square where a page of text belongs, so frames
    /// with drawable overlays keep the CPU-burned `CGImage`.
    private func canUseDisplayTexture(for file: DICOMFile) -> Bool {
        !OverlayPlaneRenderer.hasOverlay(file.dataSet, forFrame: currentFrameIndex)
    }

    /// The tool state, as the display shader's geometry.
    ///
    /// Reading this rather than re-rendering is what makes zoom, pan, rotation, flip
    /// and inversion cost a redraw instead of a pass over every pixel.
    public var displayPresentation: DisplayPresentation {
        DisplayPresentation(
            zoom: zoomLevel,
            panX: panOffsetX,
            panY: panOffsetY,
            rotationDegrees: rotationAngle,
            flipHorizontal: isFlippedHorizontal,
            flipVertical: isFlippedVertical,
            invert: isInverted
        )
    }
    #endif

    // MARK: - The PS3.4 N.2 chain

    /// The Modality LUT the viewport renders through (PS3.3 C.11.1): the
    /// image's Modality LUT Sequence, else its Rescale pair (`nil` for the
    /// identity 1 / 0) — or, under a saved view, the view's (PS3.4 N.2.1.1).
    var displayModalityLUT: ModalityLUT? {
        switch modalityLUTSource {
        case .presentationState(let lut):
            return lut
        case .image:
            if let table = dicomFile?.dataSet.modalityLUTData() { return .lut(table) }
            guard rescaleSlope != 0, rescaleSlope != 1 || rescaleIntercept != 0 else { return nil }
            return .rescale(slope: rescaleSlope, intercept: rescaleIntercept,
                            type: dicomFile?.dataSet.string(for: .rescaleType))
        }
    }

    /// The linear pair the viewer's stored-unit window converts through.
    ///
    /// `windowCenter` / `windowWidth` are held in stored-pixel units — the
    /// tools, the panel and the print marks all speak them. The renderer
    /// applies the Modality LUT first and the window to its output (PS3.3
    /// C.11.2.1.2.1), so the window goes to it in modality units: `c·m + b`,
    /// `w·|m|` for a rescale, and unchanged for a table LUT or the identity,
    /// whose stored numbers already are the modality numbers the window
    /// was converted from.
    var displayRescale: (slope: Double, intercept: Double) {
        if case .rescale(let slope, let intercept, _)? = displayModalityLUT, slope != 0 {
            return (slope, intercept)
        }
        return (1, 0)
    }

    /// The window on screen in modality units, with its VOI LUT Function
    /// (PS3.3 C.11.2.1.2.1, C.11.2.1.3).
    var displayWindow: WindowSettings {
        let (slope, intercept) = displayRescale
        return WindowSettings(center: windowCenter * slope + intercept,
                              width: windowWidth * abs(slope),
                              function: VOILUTFunction.parse(voiLUTFunction))
    }

    /// The VOI the viewport renders with (PS3.3 C.11.2): the file's VOI LUT
    /// table while the window is the untouched default of a file that windows
    /// through one, else the window on screen.
    var displayVOI: VOILUT {
        if let table = defaultVOILUTTable, let untouched = frameDefaultWindow,
           untouched.center == windowCenter, untouched.width == windowWidth {
            return .lut(table)
        }
        return VOILUT(displayWindow)
    }

    /// The image's ICC Profile (0028,2000), for colour output (PS3.3 C.11.15.1.1).
    var displayICCProfile: Data? {
        guard samplesPerPixel > 1,
              let data = dicomFile?.dataSet[.iccProfile]?.valueData, !data.isEmpty else { return nil }
        return data
    }

    /// The current frame's render request through the PS3.4 N.2 chain.
    ///
    /// `voi` nil asks the renderer for its auto-window over the Modality LUT's
    /// output. The Presentation LUT is left to the photometric (MONOCHROME1 →
    /// INVERSE, C.7.6.3.1.2); the reader's inversion is applied to the rendered
    /// frame, or in the display shader, as it always was.
    func displayRenderRequest(
        pixelData: PixelData, paletteLUT: PaletteColorLUT?, voi: VOILUT?
    ) -> FrameRenderRequest {
        FrameRenderRequest(
            pixelData: pixelData, frameIndex: currentFrameIndex,
            window: nil, paletteLUT: paletteLUT,
            pseudoColorPalette: palette,
            modalityLUT: displayModalityLUT,
            voiLUT: voi,
            presentationLUT: nil,
            iccProfile: displayICCProfile)
    }

    // MARK: - Rendering

    /// Renders the current frame with the current window/level settings.
    /// Uses throwing rendering variants so detailed PixelDataError descriptions are
    /// surfaced in the UI instead of a generic fallback message.
    public func renderCurrentFrame() {
        #if canImport(CoreGraphics)
        guard let file = dicomFile else { return }

        let start = Date()
        var image: CGImage?
        var detailedError: String?
        var source: (pixelData: PixelData, palette: PaletteColorLUT?)?

        #if canImport(Metal)
        displayTexture = nil
        #endif

        do {
            let decoded = try decodedPixelSource(for: file)
            source = (decoded.0, decoded.1)
            // The PS3.4 N.2 chain: the Modality LUT, then the window in modality
            // units (PS3.3 C.11.2.1.2.1) or the file's VOI LUT table, then the
            // Presentation LUT the photometric implies; the ICC Profile for
            // colour frames (C.11.15.1.1). The reader's colour choice is folded
            // into the same request, so the GPU display path colours in the
            // dispatch that windows — and the picture on screen is the one the
            // film composer builds from the same request.
            let request = displayRenderRequest(
                pixelData: decoded.0, paletteLUT: decoded.1, voi: displayVOI)

            #if canImport(Metal)
            // The GPU display path, when this frame qualifies: one dispatch yields
            // both the texture the viewport draws and the image everything else
            // expects, over the same output memory.
            if canUseDisplayTexture(for: file),
               let metal = FrameRenderService.shared.displayRenderer,
               let rendered = metal.renderForDisplay(request) {
                displayTexture = rendered.texture
                image = rendered.image
            } else {
                image = FrameRenderService.shared.renderFrame(request)
            }
            #else
            image = FrameRenderService.shared.renderFrame(request)
            #endif
        } catch let e as PixelDataError {
            detailedError = e.description
        } catch {
            detailedError = error.localizedDescription
        }

        // Fallback 1: automatic windowing from the frame's actual range — the
        // full-range window of C.11.2.1.2.1 over the Modality LUT's output. This
        // recovers from a degenerate explicit window far more usefully than the
        // header's window, which on a CT with a large Rescale Intercept can clip
        // almost everything to black and look like a blank image.
        //
        // A nil VOI means "auto-window", which the CPU renderer resolves from the
        // frame's range — the same thing `tryRenderFrame(_:)` did here before.
        if image == nil, let source,
           let auto = FrameRenderService.shared.renderFrame(displayRenderRequest(
               pixelData: source.pixelData, paletteLUT: source.palette, voi: nil)) {
            image = auto
            detailedError = nil
        }

        // Fallback 2: the header's own window, in the modality units the header
        // states it in, as a last resort.
        if image == nil, let source, let header = file.windowSettings() {
            if let stored = FrameRenderService.shared.renderFrame(displayRenderRequest(
                pixelData: source.pixelData, paletteLUT: source.palette,
                voi: VOILUT(header))) {
                image = stored
                detailedError = nil
            }
        }

        // Anything the modality drew *over* the image rather than into it.
        // Some Secondary Captures — Siemens' Patient Protocol is the standing
        // example — carry pixel data that is entirely zero and put their whole
        // content in a 1-bit overlay plane, so a viewer that renders only Pixel
        // Data shows a black square where a page of text should be.
        if let rendered = image {
            image = OverlayPlaneRenderer.burningOverlays(
                of: file.dataSet, onto: rendered, frameIndex: currentFrameIndex)
        }

        // Inversion is applied to the rendered frame rather than the window: the
        // renderer has no invert option, and negating the window would clip
        // differently for signed and rescaled modalities.
        //
        // On the GPU display path this is skipped: inversion is a fragment-stage
        // `1 - x` in the display shader, which is exact on 8-bit and free, and the
        // texture is what the viewport actually draws. Toggling it then costs a
        // redraw rather than a full-frame CPU pass.
        #if canImport(Metal)
        let invertOnGPU = displayTexture != nil
        #else
        let invertOnGPU = false
        #endif
        if isInverted, !invertOnGPU, let rendered = image {
            image = ImageInversion.inverted(rendered) ?? rendered
        }

        lastRenderTime = Date().timeIntervalSince(start)
        currentImage = image

        if image == nil {
            // Never fail to a silent blank: name the exact reason. A missing codec
            // for an encapsulated transfer syntax is the signature of a build whose
            // linked codec registry is stale (e.g. predating Part 2 / HTJ2K support)
            // — surface that explicitly so it's actionable instead of mysterious.
            let tsUID = file.transferSyntaxUID ?? ""
            let isEncapsulated = TransferSyntax.from(uid: tsUID)?.isEncapsulated ?? false
            if isEncapsulated && !CodecRegistry.shared.hasCodec(for: tsUID) {
                let name = transferSyntaxName.isEmpty ? tsUID : transferSyntaxName
                errorMessage = "No decoder registered for \(name) (\(tsUID)) in this build. "
                    + "Rebuild the app so the current codec registry is linked."
            } else if errorMessage == nil {
                let tsInfo = transferSyntaxName.isEmpty ? "" : " Transfer Syntax: \(transferSyntaxName)."
                errorMessage = detailedError
                    ?? "Unable to render pixel data.\(tsInfo) The file may use an unsupported transfer syntax or contain no displayable image data."
            }
        } else {
            // Clear any previous rendering error upon success
            errorMessage = nil
        }
        #endif
    }

    // MARK: - Window/Level

    /// Adopts a file's own presentation: its header VOI, or the pixel range when
    /// it declares none.
    ///
    /// The viewer holds its window in stored-pixel units, so header values (which
    /// are in modality units) are converted through the rescale pair here and
    /// back again when the frame is rendered — the renderer applies the window
    /// *after* the Modality LUT (PS3.3 C.11.2.1.2.1), see ``displayWindow``.
    /// The numbers come from ``DICOMImageExporter/determineModalityWindow`` — the
    /// one window-resolution policy shared with export, the tile cache and the
    /// film — so a tile and the viewport showing the same image cannot disagree.
    /// A file that windows through a VOI LUT Sequence instead of a centre and
    /// width keeps that table on screen until the reader drags (``displayVOI``).
    ///
    /// `frameIndex` picks the frame whose functional groups supply the VOI on an
    /// Enhanced object (default: the frame on screen), so a reset lands on the
    /// window of the frame the reader is looking at, not frame 0's.
    func applyDefaultWindow(for file: DICOMFile, slope: Double, intercept: Double,
                            frameIndex: Int? = nil) {
        let frame = frameIndex ?? currentFrameIndex
        headerWindowSettings = file.allWindowSettings(frameIndex: frame)
        if let firstWindow = headerWindowSettings.first {
            voiLUTFunction = firstWindow.function.rawValue
        }
        // PS3.3 C.11.2: a window pair or a VOI LUT, one or the other. The table
        // is the file's default presentation only when it has no window pair.
        defaultVOILUTTable = headerWindowSettings.isEmpty
            ? file.dataSet.voiLUT().map(LUTData.init) : nil
        defer { frameDefaultWindow = (windowCenter, windowWidth) }
        guard let pixData = file.pixelData() else {
            // No pixels to measure: the header VOI is all there is to go on.
            guard let firstWindow = headerWindowSettings.first else { return }
            if slope != 0 {
                windowCenter = (firstWindow.center - intercept) / slope
                windowWidth = firstWindow.width / abs(slope)
            } else {
                windowCenter = firstWindow.center
                windowWidth = firstWindow.width
            }
            return
        }
        // The shared policy states the window in modality units (A6 / D65); the
        // viewer's state is in stored units, so it goes back through this frame's
        // rescale pair, (c − b) / m and w / |m|, as the branch above does.
        let window = DICOMImageExporter.determineModalityWindow(
            from: file, pixelData: pixData, frameIndex: frame,
            windowCenter: nil, windowWidth: nil)
        if slope != 0 {
            windowCenter = (window.center - intercept) / slope
            windowWidth = window.width / abs(slope)
        } else {
            windowCenter = window.center
            windowWidth = window.width
        }
    }

    /// Lets the window follow the frame on a file that windows per frame.
    ///
    /// A multi-echo Enhanced MR or a per-frame-windowed PET declares a Frame VOI
    /// LUT (and sometimes a Pixel Value Transformation) for each frame. Paging
    /// such a file adopts the new frame's rescale pair always — those are facts
    /// about the pixels, not reader state — and re-derives the default window
    /// only while the reader has not adjusted it: a dragged window survives
    /// paging exactly as it does on a cine loop. The header is read directly
    /// (no pixel decode), so this is cheap enough for cine playback.
    private func adoptFrameWindow(for frameIndex: Int) {
        guard hasPerFrameWindow, let file = dicomFile else { return }
        let slope = file.rescaleSlope(frameIndex: frameIndex)
        let intercept = file.rescaleIntercept(frameIndex: frameIndex)
        rescaleSlope = slope
        rescaleIntercept = intercept
        guard let untouched = frameDefaultWindow,
              untouched.center == windowCenter, untouched.width == windowWidth else { return }
        let header = file.allWindowSettings(frameIndex: frameIndex)
        guard let window = header.first else { return }
        // Following the frame is not a reader action: it must not mark the
        // series as window-adjusted the way a drag does.
        let wasRestoring = restoringToolState
        restoringToolState = true
        defer { restoringToolState = wasRestoring }
        headerWindowSettings = header
        voiLUTFunction = window.function.rawValue
        if slope != 0 {
            windowCenter = (window.center - intercept) / slope
            windowWidth = window.width / abs(slope)
        } else {
            windowCenter = window.center
            windowWidth = window.width
        }
        frameDefaultWindow = (windowCenter, windowWidth)
    }

    /// Re-adopts the loaded file's default window, discarding any adjustment.
    ///
    /// Used when a tile has no window of its own — a freshly hung series must
    /// read at its own VOI, not at whatever the previous image was set to.
    func resetWindowToFileDefault() {
        guard let file = dicomFile else { return }
        applyDefaultWindow(for: file, slope: rescaleSlope, intercept: rescaleIntercept)
    }

    /// Applies a window/level preset.
    ///
    /// Preset values are in modality units (HU on CT); the viewer holds its
    /// window in stored-pixel units, so they are converted through the rescale
    /// pair and converted back when rendered (``displayWindow``).
    /// - Parameter preset: The preset to apply.
    public func applyPreset(_ preset: WindowLevelPreset) {
        if rescaleSlope != 0 {
            windowCenter = (preset.center - rescaleIntercept) / rescaleSlope
            windowWidth = preset.width / abs(rescaleSlope)
        } else {
            windowCenter = preset.center
            windowWidth = preset.width
        }
        renderCurrentFrame()
    }

    /// Applies window settings from the DICOM header.
    ///
    /// Header values are in modality units; the viewer holds its window in
    /// stored-pixel units, so they are converted through the rescale pair and
    /// converted back when rendered (``displayWindow``).
    /// - Parameter settings: The window settings to apply.
    public func applyWindowSettings(_ settings: WindowSettings) {
        if rescaleSlope != 0 {
            windowCenter = (settings.center - rescaleIntercept) / rescaleSlope
            windowWidth = settings.width / abs(rescaleSlope)
        } else {
            windowCenter = settings.center
            windowWidth = settings.width
        }
        voiLUTFunction = settings.function.rawValue
        renderCurrentFrame()
    }

    /// Auto-adjusts window/level back to the file's own default.
    ///
    /// Falls through to the measured window when the header carries no VOI.
    /// The header is not always there — CTs written by some scanners, and most
    /// secondary captures, have no Window Center at all — and a reset that
    /// silently did nothing on those files is what made "Reset View" look
    /// broken for windowing: the geometry snapped back and the drag the reader
    /// wanted undone stayed exactly where it was. `applyDefaultWindow` is the
    /// shared policy that `loadFile` itself opens on, so a reset lands on the
    /// picture the file first showed rather than on a second-guess.
    public func autoWindowLevel() {
        if let file = dicomFile {
            applyDefaultWindow(for: file, slope: rescaleSlope, intercept: rescaleIntercept)
            voiLUTFunction = headerWindowSettings.first?.function.rawValue ?? voiLUTFunction
            renderCurrentFrame()
        } else if let firstWindow = headerWindowSettings.first {
            applyWindowSettings(firstWindow)
        }
    }

    /// Adjusts window/level from a drag gesture.
    ///
    /// - Parameters:
    ///   - deltaX: Horizontal drag distance.
    ///   - deltaY: Vertical drag distance.
    public func adjustWindowLevel(deltaX: Double, deltaY: Double) {
        let result = GestureHelpers.windowLevelFromDrag(
            currentCenter: windowCenter,
            currentWidth: windowWidth,
            deltaX: deltaX,
            deltaY: deltaY
        )
        windowCenter = result.center
        windowWidth = result.width
        renderCurrentFrame()
    }

    // MARK: - Pseudo-colour

    /// Shows the image through a pseudo-colour palette, or takes the colour off.
    ///
    /// Always re-renders, even on the GPU display path: the shader's transform
    /// covers zoom, pan, rotation, flip and inversion, but colour is decided
    /// when the window LUT is built, so a palette change is a new render rather
    /// than a new draw. That is one dispatch, which is what the display path
    /// costs anyway.
    ///
    /// - Parameter palette: the palette, or `nil` to go back to no choice at
    ///   all. ``PseudoColorPalette/grayscale`` is the *other* grey — a choice of
    ///   grey, which a film-wide default will not overwrite. In the viewer the
    ///   two look identical; the difference is carried to the film with the
    ///   mark, so a reader who deliberately kept a PET grey keeps it grey when
    ///   the film is coloured. See ``ViewerPresentation/palette``.
    public func applyPalette(_ palette: DICOMCore.PseudoColorPalette?) {
        guard palette != self.palette else { return }
        self.palette = palette
        // The focused tile owns this choice, so it goes into `cells` now rather
        // than at the next focus change: the tray, the film preview and the
        // grid's own unfocused tiles all read `cells`, and until this lands
        // they would draw the tile in the colour it had a moment ago.
        if isMultiCellLayout, cells.indices.contains(focusedCellIndex) {
            cells[focusedCellIndex].palette = palette
        }
        renderCurrentFrame()
    }

    /// Whether a palette is actually colouring the image on screen.
    ///
    /// False only when no palette is chosen or the chosen one is grey — grey is
    /// not a recolouring. A frame that carries its own colours is *not* an
    /// exception any more: the ramp is applied to its luminance, so the toolbar
    /// showing the ramp is showing what the renderer produced. The toolbar reads
    /// this to decide whether to look active, so it must agree with the
    /// renderers — see `FrameRenderRequest.readerPalette`.
    public var isPseudoColored: Bool {
        guard let palette else { return false }
        return !palette.isGrayscale
    }

    /// Toggles grayscale inversion.
    public func toggleInversion() {
        isInverted.toggle()
        #if canImport(Metal)
        // On the GPU display path inversion is part of the presentation, so the
        // view redraws with a different flag and nothing is re-rendered. The CPU
        // path has no such option and must run its full-frame pass.
        if displayTexture != nil { return }
        #endif
        renderCurrentFrame()
    }

    // MARK: - Frame Navigation

    /// Navigates to a specific frame.
    ///
    /// - Parameter index: Frame index (0-based).
    public func goToFrame(_ index: Int) {
        guard index >= 0, index < numberOfFrames else { return }
        currentFrameIndex = index
        renderCurrentFrame()
    }

    /// Steps to the next frame.
    public func nextFrame() {
        currentFrameIndex = CinePlaybackHelpers.nextFrameStep(
            current: currentFrameIndex,
            total: numberOfFrames
        )
        renderCurrentFrame()
    }

    /// Steps to the previous frame.
    public func previousFrame() {
        currentFrameIndex = CinePlaybackHelpers.previousFrame(
            current: currentFrameIndex,
            total: numberOfFrames
        )
        renderCurrentFrame()
    }

    // MARK: - Cine Playback

    /// Toggles play/pause.
    public func togglePlayback() {
        switch playbackState {
        case .stopped, .paused:
            playbackState = .playing
        case .playing:
            playbackState = .paused
        }
    }

    /// Stops playback and resets to first frame.
    public func stopPlayback() {
        playbackState = .stopped
        currentFrameIndex = 0
        playbackDirection = .forward
        renderCurrentFrame()
    }

    /// Advances one cine frame (called by the timer).
    public func advanceCineFrame() {
        let result = CinePlaybackHelpers.nextFrame(
            current: currentFrameIndex,
            total: numberOfFrames,
            mode: playbackMode,
            direction: playbackDirection
        )

        currentFrameIndex = result.frame
        playbackDirection = result.direction

        if result.shouldStop {
            playbackState = .stopped
        }

        renderCurrentFrame()
    }

    // MARK: - Zoom / Pan / Rotation

    /// Zooms in by a step.
    ///
    /// Automatically enables ROI decode when zoom exceeds 2× and a JPIP URL is configured.
    public func zoomIn() {
        zoomLevel = GestureHelpers.clampZoom(zoomLevel * 1.25)
        updateROIOnZoom()
    }

    /// Zooms out by a step.
    public func zoomOut() {
        zoomLevel = GestureHelpers.clampZoom(zoomLevel / 1.25)
        updateROIOnZoom()
    }

    /// Resets the image back to how it looked when it was first opened: zoom,
    /// pan, rotation, flip, window/level, inversion, colour and the drawn
    /// annotations all undone — and the series' remembered tool arrangement
    /// with them, so stepping away and back does not put back what was just
    /// reset.
    public func resetView() {
        resetTransformations()
        autoWindowLevel()
        isInverted = false
        // The palette goes with the inversion, and for the reader's reason
        // rather than a structural one: both are ways of mapping grey to what
        // the eye sees, and "back to how it was opened" means the file's own
        // picture. A reset that left the image in Hot Iron would be answering a
        // different question from the one the button asks.
        palette = nil
        if isMultiCellLayout, cells.indices.contains(focusedCellIndex) {
            cells[focusedCellIndex].palette = nil
        }
        // The drawings too: they are tool work like the rest, and a reset
        // that kept the arrows would not be the original image the button
        // promises.
        clearDrawnAnnotationsForCurrentImage()
        forgetSeriesToolState()
        renderCurrentFrame()
    }

    /// Resets all image transforms: zoom, pan, rotation, and flip.
    public func resetTransformations() {
        zoomLevel = 1.0
        panOffsetX = 0.0
        panOffsetY = 0.0
        rotationAngle = 0.0
        isFlippedHorizontal = false
        isFlippedVertical = false
    }

    /// Fits the image to the view: the whole picture on screen, re-centred.
    ///
    /// Zoom here is *relative to the fitted image*, not a pixel ratio — every
    /// display path aspect-fits the frame before applying zoom, so 1.0 already
    /// means "the whole picture, as large as the viewport allows". The GPU path
    /// does the fit in its transform (see `DisplayPresentation.transform`), and
    /// the CPU path does it with `.aspectRatio(contentMode: .fit)` ahead of the
    /// `.scaleEffect`.
    ///
    /// This used to assign `GestureHelpers.fitZoom` — a *pixel-space* answer,
    /// `min(viewW/imageW, viewH/imageH)` — into that fit-relative field, so the
    /// fit was applied twice and the button shrank the image instead of fitting
    /// it. A 4096-wide CT in a 900pt viewport landed at 0.22× and all but
    /// vanished; it only looked right when the image happened to be viewport-
    /// sized. `fitZoom` is correct in itself and still serves callers working in
    /// pixel space — it is simply not what this field holds.
    ///
    /// The parameters are kept so the call sites need not change and so the
    /// degenerate-viewport guard below has something to check.
    ///
    /// - Parameters:
    ///   - viewWidth: Available view width.
    ///   - viewHeight: Available view height.
    public func fitToView(viewWidth: Double, viewHeight: Double) {
        // A viewport that has not been laid out yet cannot be fitted to. Leaving
        // the arrangement alone is the honest answer: resetting zoom against a
        // zero-sized view would move the picture on the reader's behalf for a
        // measurement that was never taken.
        guard viewWidth > 0, viewHeight > 0 else { return }
        zoomLevel = GestureHelpers.defaultZoom
        panOffsetX = 0.0
        panOffsetY = 0.0
    }

    /// Stored view dimensions — updated by the view layer when the container resizes.
    public var viewContentWidth: Double = 0
    public var viewContentHeight: Double = 0

    /// Fits the image using the last-known view dimensions. Used by Commands (no access to view state).
    public func fitToView() {
        fitToView(viewWidth: viewContentWidth, viewHeight: viewContentHeight)
    }

    /// Rotates the image 90° clockwise.
    public func rotateClockwise() {
        rotationAngle = GestureHelpers.rotateClockwise(from: rotationAngle)
    }

    /// Rotates the image 90° counter-clockwise.
    public func rotateCounterClockwise() {
        rotationAngle = GestureHelpers.rotateCounterClockwise(from: rotationAngle)
    }

    /// Turns the image by an arbitrary angle, clockwise for a positive delta.
    ///
    /// This is the rotate *tool*'s path: a drag turns the picture continuously
    /// through the full circle either way, where the toolbar's quarter-turn
    /// actions above snap back to the orthogonal angles.
    ///
    /// - Parameter degrees: Signed rotation to add, in degrees.
    public func rotate(byDegrees degrees: Double) {
        rotationAngle = GestureHelpers.normalizeRotation(rotationAngle + degrees)
    }

    /// Flips the image horizontally.
    public func flipHorizontal() {
        isFlippedHorizontal.toggle()
    }

    /// Flips the image vertically.
    public func flipVertical() {
        isFlippedVertical.toggle()
    }

    // MARK: - Display Text Helpers

    /// Formatted window/level text.
    public var windowLevelText: String {
        ImageMetadataHelpers.windowLevelText(center: windowCenter, width: windowWidth)
    }

    /// Formatted frame info text.
    public var frameText: String {
        ImageMetadataHelpers.frameText(current: currentFrameIndex + 1, total: numberOfFrames)
    }

    /// Formatted dimensions text.
    public var dimensionsText: String {
        ImageMetadataHelpers.dimensionsText(columns: imageColumns, rows: imageRows)
    }

    /// Formatted bit depth text.
    public var bitDepthText: String {
        ImageMetadataHelpers.bitDepthText(
            bitsAllocated: bitsAllocated,
            bitsStored: bitsStored,
            highBit: highBit
        )
    }

    /// Formatted pixel representation text.
    public var pixelRepresentationText: String {
        ImageMetadataHelpers.pixelRepresentationText(isSigned: isSigned)
    }

    /// Formatted photometric interpretation label.
    public var photometricLabel: String {
        ImageMetadataHelpers.photometricLabel(for: photometricInterpretation)
    }

    /// Formatted render time text.
    public var renderTimeText: String {
        ImageCacheHelpers.renderTimeText(lastRenderTime)
    }

    /// Formatted transfer syntax label for the currently loaded file.
    public var transferSyntaxLabel: String {
        transferSyntaxName.isEmpty ? "N/A" : transferSyntaxName
    }

    /// Whether the loaded image is a multi-frame image.
    public var isMultiFrame: Bool {
        numberOfFrames > 1
    }

    /// Whether an image is loaded and ready for viewing.
    public var hasImage: Bool {
        dicomFile != nil
    }

    /// Whether the photometric interpretation is monochrome.
    public var isMonochrome: Bool {
        let pi = photometricInterpretation.uppercased()
        return pi == "MONOCHROME1" || pi == "MONOCHROME2"
    }

    /// Whether the frame carries its own colours, and so has nothing for a
    /// pseudo-colour ramp to say.
    ///
    /// Photometric Interpretation is asked first because it is the tag that
    /// actually states this, and it catches the two cases a sample count misses.
    /// `PALETTE COLOR` stores one sample per pixel through its own LUT — colour
    /// already, though a sample count alone would call it grey and offer a ramp
    /// that the renderer then discards. And an ultrasound whose Samples per
    /// Pixel sits in the per-frame functional groups rather than at the top of
    /// the dataset reads back as the default 1, which would grey out the control
    /// on a genuinely monochrome image — the common shape behind "the palette is
    /// dead on US". The sample count stays as the fallback for a file whose
    /// Photometric Interpretation is missing or unrecognised.
    public var carriesOwnColor: Bool {
        if let pi = DICOMCore.PhotometricInterpretation.parse(photometricInterpretation) {
            return pi.isColor
        }
        return samplesPerPixel >= 3
    }

    /// Human-readable series position text, e.g. "3 / 12".
    public var seriesPositionText: String {
        guard isInSeries else { return "" }
        return "\(currentFileIndex + 1) / \(seriesFiles.count)"
    }

    // MARK: - JPIP Loading (Phase 8)

    /// Loads and renders a DICOM image from a JPIP server.
    ///
    /// Fetches an initial low-quality preview (1 quality layer) first, then
    /// progressively refines to full quality. The ``jpipLoadingState`` property
    /// tracks progress.
    ///
    /// - Note: Requires a valid URL in ``jpipURLString`` and an active network connection.
    public func loadFromJPIP() async {
        guard !jpipURLString.isEmpty else {
            jpipLoadingState = .failed(reason: "No JPIP URL provided")
            return
        }
        guard let serverURL = extractJPIPServerURL(from: jpipURLString),
              let jpipURI   = URL(string: jpipURLString) else {
            jpipLoadingState = .failed(reason: "Invalid JPIP URL: \(jpipURLString)")
            return
        }

        // JPIP retrieval is unavailable: DICOMJPIPClient's fetch methods are marked
        // @available(*, unavailable) because every request path in the pinned upstream
        // J2KSwift JPIP module (11.0.2) throws notImplemented. The two-phase
        // preview-then-refine flow (and its applyJPIPImage calls) is recoverable from git
        // history at de67c39 and should be restored when upstream lands. Surfacing the
        // real reason beats a spinner that never resolves.
        // Tracked as F1 in RESEARCH_ADOPTION_PLAN.md.
        _ = serverURL
        _ = jpipURI
        jpipLoadingState = .failed(
            reason: DICOMJPIPError.retrievalUnavailable.description
        )
    }

    // MARK: - Private Phase 8 Helpers

    /// Updates ``isROIActiveOnZoom`` based on the current zoom level and JPIP URL.
    private func updateROIOnZoom() {
        isROIActiveOnZoom = zoomLevel > 2.0 && !jpipURLString.isEmpty
    }

    /// Applies a received `DICOMJPIPImage` to the viewer state.
    ///
    /// Updates dimension and bit-depth metadata. Rendering from raw JPIP pixel
    /// data requires a `DICOMFile` wrapper; consumers should call
    /// `renderCurrentFrame()` once the file has been created from the JPIP bytes.
    private func applyJPIPImage(_ jpipImage: DICOMJPIPImage, layers: Int) {
        imageRows         = jpipImage.height
        imageColumns      = jpipImage.width
        bitsAllocated     = jpipImage.bitDepth
        bitsStored        = jpipImage.bitDepth
        samplesPerPixel   = jpipImage.components
        numberOfFrames    = 1
        photometricInterpretation = jpipImage.components == 1 ? "MONOCHROME2" : "RGB"
        // Note: currentImage is populated by renderCurrentFrame() once the caller
        // wraps jpipImage.pixelData in a DICOMFile and calls loadFile(_:).
    }

    /// Extracts the JPIP server base URL from a full JPIP URI.
    ///
    ///     "jpip://pacs.example.com:8080/dcm4chee-arc/wado?..." → "http://pacs.example.com:8080"
    private func extractJPIPServerURL(from jpipURIString: String) -> URL? {
        var s = jpipURIString
        if s.hasPrefix("jpips://") { s = "https://" + s.dropFirst(8) }
        else if s.hasPrefix("jpip://") { s = "http://" + s.dropFirst(7) }
        guard let url = URL(string: s),
              let scheme = url.scheme,
              let host   = url.host else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return URL(string: "\(scheme)://\(host)\(port)")
    }

    // MARK: - Progressive Decode (Phase 8)

    /// Starts the progressive decode pipeline for the currently loaded J2K/HTJ2K file.
    ///
    /// Cancels any previous progressive decode task, then launches a new unstructured
    /// `Task` that iterates the `AsyncStream` from
    /// ``ImageDecodingService/decodeProgressively(file:windowCenter:windowWidth:)``.
    ///
    /// State machine:
    /// - `.unavailable` is set synchronously when the file is not J2K/HTJ2K.
    /// - `.decoding(.quarter)` after the first yielded frame.
    /// - `.decoding(.half)` after the second frame.
    /// - `.complete(_:)` after the third (full-resolution) frame.
    ///
    /// Each frame is reflected into `progressiveImage` (and `currentImage`) for the
    /// SwiftUI `Canvas` in `ProgressiveImageView` to pick up automatically.
    func startProgressiveDecode() {
        #if canImport(CoreGraphics)
        guard let file = dicomFile else { return }

        // Cancel any in-flight task from a previous file load.
        progressiveDecodeTask?.cancel()

        let tsUID = file.transferSyntaxUID ?? ""
        guard ProgressiveDecodeHelpers.isJ2KTransferSyntax(tsUID) else {
            progressiveDecodeState = .unavailable
            return
        }

        let svc = decodingService
        // The decoder windows after the Modality LUT (PS3.3 C.11.2.1.2.1), so
        // it is given the window in modality units, not the viewer's stored
        // pixel units.
        let wc = displayWindow.center
        let ww = displayWindow.width

        progressiveDecodeState = .decoding(level: .quarter)

        progressiveDecodeTask = Task { [weak self] in
            guard let self else { return }
            let stream = svc.decodeProgressively(file: file, windowCenter: wc, windowWidth: ww)
            for await (level, image, decodeMs) in stream {
                guard !Task.isCancelled else { break }
                // Property mutations inherit @MainActor isolation from the class.
                self.progressiveImage = image
                self.currentImage = image
                if level.isFinal {
                    self.progressiveDecodeState = .complete(totalDecodeMs: decodeMs)
                } else {
                    self.progressiveDecodeState = .decoding(level: level)
                }
            }
        }
        #endif
    }

    /// Cancels the active progressive decode task and resets the state to `.idle`.
    ///
    /// Called automatically when `clearSeriesState()` runs, ensuring no stale frames
    /// are applied after a new file is opened.
    private func cancelProgressiveDecode() {
        progressiveDecodeTask?.cancel()
        progressiveDecodeTask = nil
        progressiveDecodeState = .idle
        #if canImport(CoreGraphics)
        progressiveImage = nil
        #endif
    }
}

/// Whose Modality LUT the viewport renders through — see
/// ``ImageViewerViewModel/modalityLUTSource``.
enum DisplayModalityLUTSource: Equatable, Sendable {
    /// The image's own: its Modality LUT Sequence or Rescale pair.
    case image
    /// The applied presentation state's; `nil` is the identity (PS3.4 N.2.1.1).
    case presentationState(ModalityLUT?)
}
