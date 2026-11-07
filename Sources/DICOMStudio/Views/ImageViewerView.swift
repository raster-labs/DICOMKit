// ImageViewerView.swift
// DICOMStudio
//
// DICOM Studio — Main image viewer view

#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import DICOMCore
import DICOMNetwork
import DICOMPrintKit
import DICOMRenderKit

/// Main DICOM image viewer view.
///
/// Displays the rendered DICOM image with zoom/pan gestures,
/// window/level controls, cine playback, and metadata overlay.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct ImageViewerView: View {
    @Bindable var viewModel: ImageViewerViewModel

    @State private var magnifyBy: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var viewSize: CGSize = .zero
    @State private var wlDragStart: CGSize = .zero

    /// Anchor for a zoom-tool drag, so the gesture applies deltas not absolutes.
    @State private var zoomDragStart: CGSize = .zero

    /// The pointer's bearing around the picture's centre at the previous step of a
    /// rotate-tool drag, or `nil` before the drag has left the dead zone at the
    /// centre. Held so each step turns the image by the arc just swept.
    @State private var rotateDragBearing: Double?

    /// Size of the view the drag tools are attached to — the whole reading area at
    /// 1×1, one tile in a grid. Its centre is the pivot a rotate drag turns about,
    /// which is why this is measured separately from ``viewSize``.
    @State private var toolSpaceSize: CGSize = .zero

    /// Where the pointer is over the image area, or `nil` when it has left.
    @State private var hoverPoint: CGPoint?

    /// Whether the on-image saved-views list is open. See `savedViewsBadge`.
    @State private var isSavedViewListPresented = false

    #if canImport(Metal)
    /// Memoizes the GPU annotation overlay, rebuilt only on an actual edit —
    /// not on every pan/zoom-driven body re-evaluation. Outside `@Observable`
    /// on purpose: see ``annotationOverlayTexture``.
    @State private var annotationTextureCache = AnnotationOverlayTextureCache()
    #endif

    /// The click-and-drag tool currently armed. Pan is the resting state.
    ///
    /// The tools are mutually exclusive: picking one arms it and disarms the
    /// others, and the toolbar highlights whichever is active. Pressing an armed
    /// tool's own button or key again drops back to pan, as does escape.
    @State private var activeTool: ImageViewerDragTool = .pan

    /// True while the armed tool's drag is actually in progress, so the pointer
    /// can confirm the gesture for exactly as long as it is running: the closed
    /// hand while the image is carried, and the tool's own glyph — filled in
    /// rather than outlined — while it is being windowed, zoomed or turned.
    @State private var isToolDragging = false

    /// The text annotation open for typing in the edit layer, if any. Held here
    /// rather than in the layer so ``annotationOverlayTexture`` can leave that
    /// annotation's words out of the GPU overlay while the editor shows them —
    /// otherwise every committed keystroke would also render under the field.
    @State private var editingAnnotationTextID: UUID?

    /// Turns scroll events into whole image steps — one per wheel notch.
    @State private var scrollSteps = ScrollStepAccumulator()

    /// Keyboard focus for the image area, so the arrow keys reach `onKeyPress`.
    @FocusState private var isImageAreaFocused: Bool

    /// Print state. Injected by the shell so the print sheet, the standalone
    /// Print screen, and job history are one shared state; created locally only
    /// when this view is used stand-alone.
    @State private var printViewModel: PrintViewModel?

    /// True between "Download" being clicked on the size prompt and the save
    /// dialog closing — what presents the `fileMover` that writes the ZIP.
    @State private var isMovingStudyDownload = false

    /// Size of the window the print sheet was raised from, so the sheet opens at
    /// the same size as the screen behind it.
    @State private var parentWindowSize: CGSize?

    public init(viewModel: ImageViewerViewModel, printViewModel: PrintViewModel? = nil) {
        self.viewModel = viewModel
        _printViewModel = State(initialValue: printViewModel)
    }

    /// Series pane, reading area, selection tray.
    ///
    /// Three columns on three planes, not three panels of equal weight. The panes
    /// are the lightest surface and each is titled; the gutter between them is
    /// the darkest chrome; and the reading area is pure black, framed, titled and
    /// lifted off its mount by a shadow. That is the habit a reporting station
    /// trains — the darkest, quietest rectangle is the one being read, and here
    /// it is also the one whose title strip says how much of it prints.
    public var body: some View {
        Group {
            if viewModel.isPrintScreenEmbedded, let printViewModel {
                // The print screen in the viewer's place, whole. Not a fourth
                // column beside the panes: composing a film is the one job on
                // screen while it lasts, and the panes' width — like their
                // toolbar toggles, which leave with the reading area — is width
                // the film can use. The panes are not collapsed, the column is
                // swapped, so putting the film away brings every pane back
                // exactly as the reader had it.
                PrintSettingsView(viewModel: printViewModel,
                                  presentation: .embedded,
                                  onClose: { viewModel.isPrintScreenEmbedded = false })
            } else {
                viewerColumns
            }
        }
        // On the swap's host, not inside the viewer columns: a print request —
        // the toolbar's button, or the library's "Print…" — must stay heard
        // while the print screen itself is standing in for the columns, or a
        // request raised then would sit unanswered until the columns returned
        // and answer twice on the way back.
        .modifier(
            PrintScreenPresenter(isRequested: $viewModel.isPrintSheetPresented,
                                 prepare: preparePrintScreen,
                                 embed: { viewModel.isPrintScreenEmbedded = true }) {
                // Hosted rather than inlined: the print state has to be created
                // by the sheet itself when the request came from the library.
                PrintSheetHost(
                    selection: viewModel.printSelection,
                    printViewModel: $printViewModel,
                    parentSize: parentWindowSize
                )
            })
    }

    /// Series pane, reading area, selection tray — the viewer as its three
    /// columns, when the print screen has not taken the panel over.
    private var viewerColumns: some View {
        HStack(spacing: 0) {
            // The study's series, when the viewer was opened from a study. Loose
            // files have no series to list, so the pane stays out of the way.
            if viewModel.isSeriesPaneVisible && !viewModel.studySeries.isEmpty {
                ViewerSeriesPaneView(viewModel: viewModel)
                    .frame(width: Self.seriesPaneWidth)
            }

            readingArea

            // The selection, on the right: what has been picked, in film order.
            if viewModel.isPrintTrayVisible {
                ViewerPrintTrayView(viewModel: viewModel)
                    .frame(width: Self.printTrayWidth)
            }
        }
        // No dividers of their own: each pane carries a seam on the side facing
        // the picture, which is one edge rather than the two a shared hairline
        // and a framed light box would put next to each other.
        .background(StudioColors.viewerChrome)
    }

    /// The image, titled, framed and inset into the chrome.
    ///
    /// The title strip is what makes this column the reading area rather than a
    /// third panel of the same weight: it names the surface, says how it is laid
    /// out, and reports how much of what is on it is going to print — the one
    /// question the three identical dark columns could not answer between them.
    private var readingArea: some View {
        VStack(spacing: 0) {
            readingAreaHeader

            imageArea
                .background(Color.black)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.readingAreaCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.readingAreaCornerRadius)
                .strokeBorder(readingAreaBorderColor, lineWidth: Self.readingAreaBorderWidth)
        }
        // A cast shadow lifts the reading area off its mount, so the middle
        // column reads as the thing in front and the panes as what flanks it.
        .shadow(color: .black.opacity(0.55), radius: 6, y: 1)
        .padding(Self.readingAreaGutter)
    }

    /// Names the reading area and reports what of it is on the film.
    private var readingAreaHeader: some View {
        let marked = viewModel.layoutMarkedForPrintCount
        let total = viewModel.layoutImageCount
        return HStack(spacing: 8) {
            Image(systemName: "viewfinder")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))

            Text("READING AREA")
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.85))

            if viewModel.hasImage {
                Text(viewModel.layout.displayName)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 4)

            // The count is the point of the strip, so it is a lit chip rather
            // than another line of grey: at a glance, this column prints.
            if viewModel.hasImage {
                HStack(spacing: 4) {
                    Image(systemName: marked > 0 ? "printer.fill" : "printer")
                        .font(.caption2)
                    Text(marked > 0 ? "\(marked) of \(total) on film" : "none on film")
                        .font(.caption2.monospacedDigit().weight(.medium))
                }
                .foregroundStyle(marked > 0 ? Color.accentColor : .white.opacity(0.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    marked > 0 ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.06),
                    in: Capsule())
                .accessibilityLabel(marked > 0
                                    ? "\(marked) of \(total) images on screen are marked for print"
                                    : "No images on screen are marked for print")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: ViewerPaneMetrics.headerHeight)
        .background(readingAreaHeaderFill)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(height: 1)
        }
    }

    /// The strip's own surface — accent-washed while the keyboard is here, so
    /// the column that the arrow keys and the tools will act on is lit at the
    /// top as well as ringed at the edge.
    private var readingAreaHeaderFill: Color {
        isImageAreaFocused && viewModel.hasImage
            ? Color.accentColor.opacity(0.28)
            : StudioColors.viewerPanelHeader
    }

    /// The frame around the reading area.
    ///
    /// Neutral while the viewer is idle; picking up the accent once the image
    /// area holds the keyboard, which is what says the arrow keys will walk this
    /// stack. It stays on in a grid too — the ring says which *column* is live,
    /// the tile's own ring says which tile inside it is, and losing the outer one
    /// was what left the three columns looking alike.
    private var readingAreaBorderColor: Color {
        guard isImageAreaFocused, viewModel.hasImage else {
            return StudioColors.readingAreaBorder
        }
        return Color.accentColor.opacity(0.55)
    }

    /// Thicker than a hairline: this is the edge of the working surface, and at
    /// one point it disappeared against the mount from a normal seating distance.
    private static let readingAreaBorderWidth: CGFloat = 1.5

    /// Width of the selection tray — a legible thumbnail and two lines of label.
    private static let printTrayWidth: CGFloat = 180

    /// Width of the series pane — enough for a legible thumbnail and two lines
    /// of series description.
    private static let seriesPaneWidth: CGFloat = 190

    /// Chrome left visible around the image. Small on purpose: enough to read as
    /// a separate surface, not enough to cost the picture real room.
    private static let readingAreaGutter: CGFloat = 6

    private static let readingAreaCornerRadius: CGFloat = 5

    private var imageArea: some View {
        ZStack {
            // The light box. Painted by the reading area around it too, so this
            // one only has to cover the content — it must not spill past the
            // frame, which is what `ignoresSafeArea` here used to do.
            Color.black

            if viewModel.isLoading {
                ProgressView("Loading…")
                    .foregroundStyle(.white)
            } else if let waveform = viewModel.waveform {
                WaveformChartView(waveform: waveform)
            } else if let content = viewModel.nonImageContent {
                // Reports, encapsulated documents and the rest are read, not
                // rendered. This branch sits ahead of the error branch because
                // such an object is not a picture that failed — it never was one.
                ViewerNonImageContentView(
                    content: content,
                    // The clip and the toolbar's cine button read and write one
                    // state, so pressing either one moves the other.
                    isPlaying: Binding(
                        get: { viewModel.playbackState == .playing },
                        set: { viewModel.playbackState = $0 ? .playing : .paused }),
                    // Which object this is, so stepping to the next clip of a
                    // series rebuilds the player rather than leaving the
                    // previous recording running.
                    instanceUID: viewModel.sopInstanceUID)
                // Scrolling steps between the objects of a multi-clip series
                // here too. The handler that does this for pixels lives inside
                // `imageContent`, which this branch pre-empts, so a video
                // series had no wheel navigation at 1×1 at all.
                .background(ScrollWheelHandler { scrollImages($0) })
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)
                    Text(errorMessage)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if viewModel.hasImage {
                // At 1×1 the viewer is the image; beyond that it is one tile of
                // a grid, and the grid decides where the live viewer sits.
                Group {
                    if viewModel.isMultiCellLayout {
                        // The edit layer rides on the focused tile's live
                        // content, so its coordinates are the tile's — the same
                        // space the drag tools measure in.
                        ViewerTileGridView(viewModel: viewModel) {
                            imageContent.overlay(annotationEditLayer)
                        }
                    } else {
                        imageContent.overlay(annotationEditLayer)
                    }
                }
                    // Zoom and pan are drawn with `scaleEffect`/`offset`, which
                    // do not affect layout: without clipping, a zoomed image
                    // paints straight over the series pane and the selection
                    // tray beside it. The viewer is its own viewport.
                    .clipped()
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Fit to View") {
                            viewModel.fitToView(viewWidth: viewSize.width, viewHeight: viewSize.height)
                        }
                        // The full reset, the same one the toolbar's "Reset to
                        // original image" and ⌘R run. `resetTransformations()`
                        // undoes geometry only, so this menu item left the
                        // window/level drag and the inversion in place — the two
                        // things a reader most often wants a reset *for*.
                        Button("Reset View") {
                            viewModel.resetView()
                        }
                        Divider()
                        Button("Rotate Clockwise") { viewModel.rotateClockwise() }
                        Button("Rotate Counter-Clockwise") { viewModel.rotateCounterClockwise() }
                        Button("Flip Horizontal") { viewModel.flipHorizontal() }
                        Button("Flip Vertical") { viewModel.flipVertical() }
                        // Saved views, when the study has any for this image.
                        // The default view is always offered: a reader must
                        // never be unable to get back to the file's own picture.
                        if !viewModel.savedViewsForCurrentImage.isEmpty {
                            Divider()
                            Button(ImageViewerViewModel.defaultViewLabel) {
                                viewModel.applyDefaultView()
                            }
                            .disabled(viewModel.selectedPresentationStateLabel == nil)
                            ForEach(viewModel.savedViewsForCurrentImage) { saved in
                                Button(saved.label) {
                                    viewModel.applySavedView(saved)
                                }
                                .disabled(
                                    viewModel.selectedPresentationStateLabel == saved.label)
                            }
                        }
                        Divider()
                        Button(viewModel.showImageAnnotations
                               ? "Hide Image Annotations" : "Show Image Annotations") {
                            viewModel.showImageAnnotations.toggle()
                        }
                        // Laterality gets its own item rather than riding along
                        // with the block above — see
                        // `showOrientationLabels` for why the two are
                        // different decisions.
                        Button(viewModel.showOrientationLabels
                               ? "Hide Orientation Markers" : "Show Orientation Markers") {
                            viewModel.showOrientationLabels.toggle()
                        }
                        if viewModel.isMonochrome {
                            Divider()
                            Button(viewModel.isInverted ? "Remove Inversion" : "Invert Grayscale") {
                                viewModel.toggleInversion()
                            }
                            // The palette sits beside inversion because it is
                            // the same kind of thing: a way of mapping the
                            // windowed grey to what the eye sees, with the
                            // stored pixels untouched. Nested rather than laid
                            // out flat — twenty-odd ramps would bury the print
                            // items below.
                            Menu("Colour Palette") {
                                Button("None (grayscale)") {
                                    viewModel.applyPalette(nil)
                                }
                                .disabled(viewModel.palette == nil)
                                ForEach(DICOMCore.PseudoColorPalette.catalog, id: \.group) { entry in
                                    Section(entry.group.title) {
                                        ForEach(entry.palettes, id: \.self) { palette in
                                            Button(palette.displayName) {
                                                viewModel.applyPalette(palette)
                                            }
                                            .disabled(palette == viewModel.palette)
                                        }
                                    }
                                }
                            }
                        }
                        Divider()
                        Button(viewModel.isCurrentFrameMarkedForPrint
                               ? "Unmark for Print" : "Mark for Print") {
                            viewModel.togglePrintMarkForCurrentFrame()
                        }
                        // "All" is what is on screen — the images the current
                        // layout is showing, not the study behind them.
                        Button("Select All for Print") {
                            viewModel.markLayoutForPrint()
                        }
                        .disabled(viewModel.isLayoutFullyMarkedForPrint)
                        // "Unselect all" takes every mark off, not only the ones
                        // the layout happens to be showing: marks are made while
                        // scrolling a series, so a screen-scoped unselect leaves
                        // most of the film behind and reads as doing nothing.
                        Button("Unselect All for Print") {
                            viewModel.clearAllPrintMarks()
                        }
                        .disabled(viewModel.printSelection.isEmpty)
                        if viewModel.isMultiFrame {
                            Button("Mark All Frames for Print") {
                                viewModel.markAllFramesOfCurrentFileForPrint()
                            }
                        }
                        if viewModel.isInSeries {
                            Button("Mark Whole Series for Print") {
                                viewModel.markWholeSeriesForPrint()
                            }
                        }
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundStyle(.gray)
                    Text("No image loaded")
                        .foregroundStyle(.gray)
                }
            }
        }
        // Arrow-key image navigation. The image area takes focus so the keys are
        // delivered here; `.focusEffectDisabled()` keeps the focus ring off the
        // film. Left/Right walk images (frames, then files); Up/Down jump whole
        // files, which is how one skims a series past a long cine loop.
        // At 1×1 the whole image area is the drop target; in a grid each tile
        // has its own, so this one would swallow the drop first.
        .dropDestination(for: String.self) { seriesUIDs, _ in
            guard !viewModel.isMultiCellLayout, let uid = seriesUIDs.first else { return false }
            return viewModel.assignSeries(uid, toCell: 0)
        }
        .focusable(viewModel.hasImage)
        .focusEffectDisabled()
        .focused($isImageAreaFocused)
        .onAppear { isImageAreaFocused = true }
        .onChange(of: viewModel.filePath) { _, _ in isImageAreaFocused = true }
        .onKeyPress(.leftArrow) {
            viewModel.navigateToPreviousImage() ? .handled : .ignored
        }
        .onKeyPress(.rightArrow) {
            viewModel.navigateToNextImage() ? .handled : .ignored
        }
        .onKeyPress(.upArrow) {
            guard viewModel.canGoPreviousFile else { return .ignored }
            viewModel.navigateToPreviousFile()
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard viewModel.canGoNextFile else { return .ignored }
            viewModel.navigateToNextFile()
            return .handled
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        viewSize = geo.size
                        updateViewportSize(geo.size)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        viewSize = newSize
                        updateViewportSize(newSize)
                    }
            }
        )
        .background(toolShortcuts)
        .focusedValue(\.imageViewerViewModel, viewModel)
        // Reading annotations in the four corners, over the picture. In a grid
        // each tile draws its own, so this one is the 1×1 case only.
        .overlay {
            // Images only: a report or a document is not a picture, and a block
            // of corner annotation over a page of text obscures the text.
            if viewModel.showImageAnnotations && viewModel.hasImage
                && !viewModel.isWaveform && !viewModel.isNonImageContent
                && !viewModel.isMultiCellLayout {
                ViewerAnnotationOverlayView(
                    text: viewModel.annotationText,
                    state: viewModel.annotationViewportState(
                        viewSize: viewSize, cursor: cursorReadout),
                    cellSize: viewSize,
                    // No top-trailing inset: the print checkbox and the
                    // saved-views badge that used to occupy that corner now sit
                    // at the middle of the right edge, so the identification
                    // block starts at the same height on every image.
                    showOrientation: viewModel.showOrientationLabels,
                    // Those controls are at the middle of the right edge, which
                    // is where the right-hand orientation letter is centred —
                    // the tick covered the "L". Enough room for the widest of
                    // them, so the letter sits clear whether or not the badge
                    // is showing.
                    trailingControlsInset: Self.trailingControlsInset
                )
            }
        }
        // The pointer's position over the picture, for the pixel and patient
        // coordinates in the top-left block. Tracked on the image area rather
        // than on the image itself: the image is transformed by zoom, pan and
        // rotation, so a point in *its* space is already past the mapping the
        // readout exists to perform, whereas the image area is the viewport the
        // transforms are defined against.
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point): hoverPoint = point
            case .ended: hoverPoint = nil
            }
        }
        .overlay(alignment: .bottom) {
            // Images only: this bar scrubs a frame index, and a clip has none —
            // the player brings its own transport for that.
            if viewModel.isMultiFrame && viewModel.hasImage && !viewModel.isWaveform {
                CineControlsView(viewModel: viewModel)
                    .padding(.bottom, 40)
            }
        }
        // The drawn-annotation styling strip, below the cine controls' spot so
        // the two coexist on a multi-frame file.
        .overlay(alignment: .bottom) {
            annotationStyleBar
        }
        // The pointer, over everything the picture is made of — and this
        // position is the whole trick.
        //
        // A cursor rect belongs to the topmost view under the pointer, and the
        // reading area is covered by things that sit above the picture: the
        // `contentShape(Rectangle())` that carries the context menu, the
        // continuous-hover reader behind the coordinate readout, the annotation
        // and cine overlays. Attached to the image itself this layer is under
        // all of them, so AppKit asks one of *them* what shape to use and gets
        // the arrow. Attached here it is above them, over the whole area every
        // one of those covers, and the tool's shape is the one that shows.
        //
        // Deaf to the mouse, so none of what it covers stops working.
        .overlay(toolCursorLayer)
        // The image's own controls go *above* the cursor layer, which is the
        // one thing they must outrank.
        //
        // Everything below this line is picture, and the picture wants the
        // armed tool's pointer. These are not picture: they are a checkbox and
        // a badge that happen to float on it, and under the tool cursor's rect
        // they claimed the windowing sun or the zoom magnifier — a pointer that
        // says "drag me to window this image" over a control that does nothing
        // of the kind. Sitting above the cursor layer, their own `arrowPointer`
        // rect is the topmost one at those few points and the arrow wins there,
        // while the tool keeps every other pixel of the image.
        .overlay(alignment: .trailing) {
            // The image's own controls — the print mark, and the saved-views
            // badge when there are any — down the middle of the right edge.
            //
            // They used to sit in the top-right corner, which is where the
            // identification block's top-right corner also goes, so the block
            // had to be pushed down past them by an inset that changed with
            // what was showing: 34pt for the checkbox alone, more with the
            // badge under it. The patient data therefore sat at a different
            // height on an image with saved views than on one without, and the
            // corner text is exactly the thing a reader expects to find in the
            // same place every time. The middle of the edge is empty in the
            // four-corner annotation scheme, so putting the controls there
            // costs the text nothing and the inset disappears.
            //
            // In a grid each tile carries its own checkbox, so this one would be
            // ambiguous about which image it marks.
            if viewModel.hasImage && !viewModel.isWaveform && !viewModel.isMultiCellLayout {
                VStack(alignment: .trailing, spacing: 6) {
                    printMarkCheckbox
                    if viewModel.hasSavedViews {
                        savedViewsBadge
                    }
                }
                .padding(8)
                // The arrow over the controls themselves, beating the tool
                // cursor's rect underneath. Inside the padding, so the rect
                // covers the controls and not the gap around them — the picture
                // right up to their edge keeps the tool's pointer.
                #if os(macOS)
                .arrowPointer()
                #endif
            }
        }
        .toolbar {
            viewerToolbar
        }
        .sheet(isPresented: $viewModel.showDICOMInspector) {
            if let file = viewModel.dicomFile {
                DICOMInspectorView(dicomFile: file)
            }
        }
        // Image metadata, presented the way the tag inspector is rather than
        // drawn into the picture's bottom-left corner. That corner already
        // carries the reading annotations' zoom, image-number and compression
        // lines, so the old block sat straight on top of them — the reader
        // turned metadata on and lost the annotations they read the image by.
        // A panel has room for the whole block at a legible size, leaves the
        // picture alone, and makes the two "tell me about this file" surfaces
        // open and close the same way.
        .sheet(isPresented: $viewModel.showMetadataOverlay) {
            ImageMetadataPanelView(viewModel: viewModel)
        }
        // The "A saved view exists for this image" sheet is HELD — no longer
        // wired, so it cannot appear over the picture. Opening an image with
        // saved views now applies the best one directly (series-wide first,
        // else the image's first) and the on-image badge steps through the
        // rest and the default. See `offerSavedViewsIfNeeded`, which no longer
        // raises `savedViewPrompt`.
        // The study-download confirmation and save dialog — one modifier so
        // the (already large) body stays type-checkable.
        .modifier(StudyDownloadPresenter(viewModel: viewModel,
                                         isMoving: $isMovingStudyDownload))
    }

    // MARK: - Print

    /// Room the right-edge controls take, which the orientation letter beside
    /// them starts inside of.
    ///
    /// Measured against the widest of them — the ticked checkbox reading
    /// "Print 12" — rather than what is showing at the moment, so the letter
    /// does not shift sideways as the reader ticks and unticks.
    private static let trailingControlsInset: CGFloat = 96

    /// On-image checkbox that marks the displayed frame for print.
    ///
    /// Unchecked by default — nothing is printed unless the user ticks it. When
    /// ticked it also shows the frame's 1-based film position.
    private var printMarkCheckbox: some View {
        let isMarked = viewModel.isCurrentFrameMarkedForPrint
        return Button {
            viewModel.togglePrintMarkForCurrentFrame()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isMarked ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundStyle(isMarked ? Color.accentColor : .secondary)
                if let position = viewModel.currentFramePrintPosition {
                    Text("Print \(position)")
                        .font(.caption.monospacedDigit())
                } else {
                    Text("Print")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        // Capsule-matching radius: the control already wears a material
        // capsule, and a rounded rectangle behind it would show its corners.
        .interactiveControl(cornerRadius: 16, horizontal: 3, vertical: 3)
        .accessibilityLabel(isMarked ? "Unmark image for print" : "Mark image for print")
        .accessibilityAddTraits(isMarked ? [.isSelected] : [])
        .help(isMarked ? "Marked for print — click to unmark (M)"
                       : "Mark this image for print (M)")
    }

    /// On-image badge saying this image has saved views (presentation states).
    ///
    /// The picker's glyph and purple, on the checkbox's capsule: the colour is
    /// what says "presentation state" in the toolbar, and here it has to say
    /// the same thing from the corner of the picture.
    ///
    /// The capsule names the reading now showing — the first PR is applied
    /// automatically when the image opens (see `offerSavedViewsIfNeeded`) — and
    /// clicking opens the list, where one click applies another view or the
    /// default. So the badge answers "what am I looking at" at rest and is the
    /// way to change it on click.
    private var savedViewsBadge: some View {
        Button {
            isSavedViewListPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.below.rectangle")
                    .font(.caption.bold())
                Text(savedViewsBadgeText)
                    .font(.caption)
                    .lineLimit(1)
                    // No `.frame(maxWidth:)` here — a max-width frame is
                    // greedy and took its full width whatever the text, so a
                    // three-letter name sat at the left end of a long empty
                    // capsule. The capsule hugs the text instead; a very long
                    // name is shortened in `savedViewsBadgeText`, in the
                    // string, so the layout never has to cut it.
            }
            .foregroundStyle(Color.purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .interactiveControl(cornerRadius: 16, horizontal: 3, vertical: 3)
        // The badge's own list. Closing goes through this view's binding,
        // passed in — never `@Environment(\.dismiss)`, which cannot clear an
        // `isPresented` its caller owns and left the list standing open over
        // an image it had already changed.
        .popover(isPresented: $isSavedViewListPresented, arrowEdge: .bottom) {
            ViewerImageSavedViewList(viewModel: viewModel) {
                isSavedViewListPresented = false
            }
        }
        .accessibilityLabel("Saved views for this image")
        .accessibilityValue(savedViewsBadgeText)
        .help(savedViewsBadgeHelp)
    }

    /// What the badge's capsule says: the reading now showing, by name.
    ///
    /// The default view is named too — the capsule used to fall back to the
    /// bare count of saved views ("1", "2"), which read as a mystery number
    /// over the picture. "Default view" says what is actually on screen; how
    /// many views there are is the list's job, one click away.
    ///
    /// Shortened in the string rather than by layout, so the capsule always
    /// hugs what it shows: a truncating frame has to be given a width, and a
    /// fixed width is exactly the long empty capsule this replaces.
    private var savedViewsBadgeText: String {
        let label = viewModel.selectedPresentationStateLabel
            ?? ImageViewerViewModel.defaultViewLabel
        guard label.count > 22 else { return label }
        return label.prefix(21) + "…"
    }

    private var savedViewsBadgeHelp: String {
        let count = viewModel.savedViewsForCurrentImage.count
        let plural = count == 1 ? "1 saved view" : "\(count) saved views"
        return "\(plural) — the first is applied when the image opens; "
             + "click to list them and apply another, or the default view."
    }

    /// Records the size the focused image is displayed at.
    ///
    /// In a grid the tiles report their own sizes, and the focused tile's is far
    /// smaller than the whole viewer — taking the outer size there would resolve
    /// zoom and pan against the wrong viewport and crop the wrong region.
    private func updateViewportSize(_ size: CGSize) {
        guard !viewModel.isMultiCellLayout else { return }
        viewModel.viewContentWidth = size.width
        viewModel.viewContentHeight = size.height
    }

    /// Asks for the print screen. What that raises — a window on macOS, a sheet
    /// elsewhere — is `PrintScreenPresenter`'s business, and so is preparing the
    /// print state, since the same request also comes from the library.
    private func openPrintSheet() {
        viewModel.isPrintSheetPresented = true
    }

    /// Brings the print state in line with the viewer, just before the print
    /// screen reads it. Idempotent: the request can arrive more than once.
    private func preparePrintScreen() {
        if printViewModel == nil {
            printViewModel = PrintViewModel(selection: viewModel.printSelection)
        } else {
            // Printers may have been added since it was last open.
            printViewModel?.loadPrinters()
        }

        // Film order follows the grid, so the preview reads like the screen.
        // Ordering only — it moves marks, it does not re-window them.
        viewModel.syncPrintOrderToViewer()

        // Marks are brought up to date with the screen *before* the sheet is
        // reset, because the reset reads them: a mark still carrying the window
        // it was ticked with, rather than the one the reader has since dragged
        // to, is what "Match the viewer's window/level" would have matched.
        // Only the fields the switches ask for survive the reset (see
        // `resetCellToolsForNewFilm`), so this is safe when both are off — the
        // film still opens on the plain images.
        //
        // Read against the *defaults* the imminent reset will restore, not
        // against the switches as the previous visit left them. Both default to
        // on, so the sync is unconditional: testing the live values meant a
        // reader who turned them off last visit got no refresh, while the reset
        // turned the switches back on — a film that claimed to match the screen
        // and was built from marks nobody had re-synced.
        viewModel.refreshMarksFromViewer()

        // Where the study's saved views are read from. Handed over before the
        // reset so the fresh sheet can adopt them; the viewer owns the store,
        // and the marks carry no study of their own to look them up by.
        printViewModel?.presentationStateStore = viewModel.presentationStateStore
        printViewModel?.presentationStateStudyUID = viewModel.studyInstanceUID

        // The film is put back to a fresh sheet *last*, after the marks have
        // been ordered and re-synced. Order matters: the reset is what puts a
        // cell back to the untouched frame, so anything that writes the
        // viewer's own window and arrangement into the marks has to happen
        // before it, not after. "If needed": a visit returning to the same
        // marks is returning to a film in progress, and keeps it — only a
        // changed tray or a finished job cuts a fresh sheet.
        printViewModel?.resetForNewFilmIfNeeded()

        // Captured before the sheet exists, while the key window is still the
        // viewer's: the sheet opens at the size of the screen it came from. The
        // window sizes itself, so this only matters off macOS.
        #if canImport(AppKit)
        parentWindowSize = NSApplication.shared.keyWindow?.frame.size
        #endif

        // Mirror the viewer's grid on film, so the preview matches the screen.
        if viewModel.isMultiCellLayout {
            printViewModel?.viewerLayout = PrintLayout(
                rows: viewModel.layout.rows, columns: viewModel.layout.columns)
            printViewModel?.layoutMode = .matchViewer
        } else {
            printViewModel?.viewerLayout = nil
            if printViewModel?.layoutMode == .matchViewer {
                printViewModel?.layoutMode = .automatic
            }
        }
        // The console is cleared by the reset above, so the preview reads like a
        // fresh log each time it is opened rather than a running transcript.
    }

    // MARK: - Cursor readout

    /// The pixel under the pointer, with the in-flight gesture folded in.
    ///
    /// A pan drag moves the picture continuously and only commits on release, so
    /// the readout has to be mapped through the arrangement *on screen* — the
    /// committed one would name the pixel that was under the cursor before the
    /// drag began, which is the one place a stale number would look plausible.
    private var cursorReadout: ViewerCursorReadout? {
        guard let hoverPoint else { return nil }
        return viewModel.cursorReadout(
            atViewPoint: hoverPoint,
            viewSize: viewSize,
            zoom: viewModel.zoomLevel * Double(magnifyBy),
            panX: viewModel.panOffsetX + Double(dragOffset.width),
            panY: viewModel.panOffsetY + Double(dragOffset.height))
    }

    // MARK: - Image Content

    #if canImport(Metal)
    /// The GPU-resident frame, when the display path is in use.
    private var metalDisplayFrame: DisplayFrameTexture? { viewModel.displayTexture }

    /// The view model's tool state plus whatever the in-flight gesture is adding.
    ///
    /// Gestures are folded in here rather than applied as view modifiers, because on
    /// this path the transform *is* the arrangement — a `.scaleEffect` on top would
    /// scale the already-transformed quad and compound the zoom.
    private var livePresentation: DisplayPresentation {
        var presentation = viewModel.displayPresentation
        presentation.zoom *= magnifyBy
        presentation.panX += dragOffset.width
        presentation.panY += dragOffset.height
        return presentation
    }

    /// This image's identity in the annotation store — `nil` when nothing is
    /// loaded, matching every other "no file" branch in this view.
    private var currentAnnotationKey: ImageAnnotationKey? {
        guard let filePath = viewModel.filePath else { return nil }
        return ImageAnnotationKey(filePath: filePath, frameIndex: viewModel.currentFrameIndex)
    }

    /// The text and arrows drawn on this image, wherever they were drawn —
    /// the print tray or this viewer. Reachable without the print tray ever
    /// having been opened: `printSelection` is eagerly constructed, not
    /// lazy like the print sheet itself.
    private var currentAnnotations: [PrintOverlayAnnotation] {
        guard let key = currentAnnotationKey else { return [] }
        return viewModel.printSelection.cellAnnotations[key] ?? []
    }

    /// The annotation texture for the frame on screen, rebuilt only when its
    /// image identity or its annotations actually changed.
    ///
    /// A plain computed property here would rebuild the texture on every
    /// evaluation of `imageContent`'s body — including the ones a pan or
    /// zoom drag triggers by changing `livePresentation`, which reads
    /// nothing about annotations. `annotationTextureCache` is a bare
    /// reference type outside Observation, so reading and writing it here
    /// does not itself trigger a re-render; only an edit that changes
    /// `currentAnnotations` produces a different cache key and a rebuild.
    private var annotationOverlayTexture: AnnotationOverlayTexture? {
        guard let key = currentAnnotationKey,
              let texture = metalDisplayFrame,
              let device = MetalRenderDevice.shared?.device else { return nil }
        // The annotation being typed into is the editor's to show, not the
        // GPU's — see ``editingAnnotationTextID``.
        let overlays = currentAnnotations.filter { $0.id != editingAnnotationTextID }
        return annotationTextureCache.texture(
            for: key, overlays: overlays,
            width: texture.width, height: texture.height, device: device,
            orientation: annotationOrientation)
    }
    #else
    private var metalDisplayFrame: Never? { nil }
    private var livePresentation: Int { 0 }
    #endif

    /// The turn and the mirrors the shader is about to apply to the overlay,
    /// so the lettering can be rasterized level against them.
    ///
    /// Rotation and the flips only — deliberately no zoom, pan or viewport.
    /// The shader moves the overlay with the picture, so the anchor needs no
    /// help; the one thing it gets wrong is which way up the words come out,
    /// and that is decided by the turn and the mirrors alone. Feeding the crop
    /// in as well would move the anchor a second time.
    private var annotationOrientation: PrintOverlayOrientation {
        PrintOverlayOrientation(
            presentation: ViewerPresentation(
                rotationDegrees: viewModel.rotationAngle,
                flipHorizontal: viewModel.isFlippedHorizontal,
                flipVertical: viewModel.isFlippedVertical),
            imageWidth: viewModel.imageColumns,
            imageHeight: viewModel.imageRows)
    }

    @ViewBuilder
    private var imageContent: some View {
        #if canImport(CoreGraphics)
        // Use the Canvas-based ProgressiveImageView only while coarse J2K/HTJ2K
        // previews are actively streaming; once `.complete` arrives, hand off to
        // MetalImageView so GPU W/L, annotations, and multi-frame scrubbing work.
        if case .decoding = viewModel.progressiveDecodeState,
           viewModel.progressiveImage != nil || viewModel.currentImage != nil {
            ProgressiveImageView(viewModel: viewModel)
                .background(toolSpaceReader)
                .gesture(panGesture)
                .gesture(magnificationGesture)
                #if os(macOS)
                .background(ScrollWheelHandler { scrollImages($0) })
                #endif
        } else if let texture = metalDisplayFrame {
            // GPU display path (GPU_RENDERING_PLAN.md M5). Zoom, pan, rotation, flip
            // and inversion are in the shader's transform, so none of the modifiers
            // below this branch apply — and none of them re-render anything. A tool
            // action costs one redraw of a textured quad.
            MetalImageView(frame: texture, presentation: livePresentation,
                           annotationOverlay: annotationOverlayTexture)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(toolSpaceReader)
                .gesture(panGesture)
                .gesture(magnificationGesture)
                .accessibilityLabel("DICOM Image")
                .accessibilityValue(viewModel.dimensionsText)
                .accessibilityHint(imageAccessibilityHint)
                #if os(macOS)
                .background(ScrollWheelHandler { scrollImages($0) })
                #endif
        } else if let cgImage = viewModel.currentImage {
            // CPU fallback path. The transforms go on the picture and the gestures
            // on the container around it — a `DragGesture` reports its locations in
            // the space of the view it is attached to, so hanging it off the rotated,
            // flipped image would have the rotate tool measuring the pointer in a
            // frame that turns with the drag (half speed, and backwards under a flip).
            // The container never moves, so its space is the screen's.
            ZStack {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    // Uses the whole viewport, aspect ratio intact: `.fit` grows the
                    // image until one edge meets the cell, so nothing is stretched
                    // and nothing is left unnecessarily small.
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(viewModel.zoomLevel * magnifyBy)
                    .offset(
                        x: viewModel.panOffsetX + dragOffset.width,
                        y: viewModel.panOffsetY + dragOffset.height
                    )
                    // Mirror outside the rotation, so the flip acts on what is on
                    // screen rather than on the image's own axes. SwiftUI applies
                    // modifiers inside-out, so the `scaleEffect` written after the
                    // `rotationEffect` is the one that happens last — matching the
                    // GPU transform, the film, and `FrameRenderer.applying`.
                    .rotationEffect(.degrees(viewModel.rotationAngle))
                    .scaleEffect(
                        x: viewModel.isFlippedHorizontal ? -1 : 1,
                        y: viewModel.isFlippedVertical   ? -1 : 1
                    )
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Keeps the whole viewport draggable, letterbox included, as the
                // image's own frame did before it was wrapped.
                .contentShape(Rectangle())
                .background(toolSpaceReader)
                .gesture(panGesture)
                .gesture(magnificationGesture)
                .accessibilityLabel("DICOM Image")
                .accessibilityValue(viewModel.dimensionsText)
                .accessibilityHint(imageAccessibilityHint)
                #if os(macOS)
                .background(ScrollWheelHandler { scrollImages($0) })
                #endif
        } else {
            Text("Unable to render image")
                .foregroundStyle(.gray)
        }
        #endif
    }

    // MARK: - Drawn annotations

    /// The editing surface for drawn text and arrows, over the live picture.
    ///
    /// Present whenever an image is — not only while a drawing tool is armed —
    /// because existing annotations stay selectable and draggable under any
    /// tool, exactly as they do on a film cell. Its own hit-testing rules keep
    /// it out of the way of the drag tools; see the layer.
    @ViewBuilder
    private var annotationEditLayer: some View {
        if viewModel.hasImage && !viewModel.isWaveform && !viewModel.isNonImageContent {
            ViewerAnnotationEditLayer(
                viewModel: viewModel,
                tool: activeTool,
                liveZoom: viewModel.zoomLevel * Double(magnifyBy),
                livePanX: viewModel.panOffsetX + Double(dragOffset.width),
                livePanY: viewModel.panOffsetY + Double(dragOffset.height),
                editingTextID: $editingAnnotationTextID)
        }
    }

    /// The drawn-annotation styling controls — the film inspector's swatches,
    /// size and delete, condensed to a strip over the picture.
    ///
    /// Shown while a drawing tool is armed or something is selected: that is
    /// exactly when a colour or size decision can land somewhere, and the rest
    /// of the time the strip would sit over anatomy saying nothing.
    @ViewBuilder
    private var annotationStyleBar: some View {
        if viewModel.hasImage && !viewModel.isWaveform && !viewModel.isNonImageContent
            && (activeTool.isDrawing
                || viewModel.printSelection.selectedAnnotationLocation != nil) {
            HStack(spacing: 10) {
                ForEach(Self.annotationSwatches, id: \.name) { swatch in
                    annotationSwatchButton(swatch.color, name: swatch.name)
                }

                Divider().frame(height: 16)

                Slider(value: annotationScaleBinding,
                       in: PrintOverlayAnnotation.minimumScale...PrintOverlayAnnotation.maximumScale)
                    .frame(width: 110)
                    .accessibilityLabel("Annotation size")
                Text(annotationSizeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)

                Divider().frame(height: 16)

                Button {
                    viewModel.removeSelectedDrawnAnnotation()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .interactiveControl(
                    cornerRadius: 5, horizontal: 5, vertical: 3,
                    isEnabled: viewModel.printSelection.selectedAnnotationLocation != nil)
                .disabled(viewModel.printSelection.selectedAnnotationLocation == nil)
                .accessibilityLabel("Delete selected annotation")
                .help("Delete the selected annotation (⌫)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, 8)
        }
    }

    /// The film's palette, name for name, so a colour picked on either screen
    /// is the same colour on the other.
    private static let annotationSwatches: [(name: String, color: PrintOverlayColor)] = [
        ("Yellow", .yellow), ("White", .white), ("Red", .red),
        ("Green", .green), ("Cyan", .cyan)
    ]

    private func annotationSwatchButton(
        _ color: PrintOverlayColor, name: String
    ) -> some View {
        let current = viewModel.printSelection.selectedAnnotationLocation?
            .annotation.color ?? viewModel.printSelection.annotationColor
        return Button {
            if let selected = viewModel.printSelection.selectedAnnotationLocation {
                viewModel.printSelection.setAnnotationColor(
                    color, id: selected.annotation.id, forKey: selected.key)
            } else {
                viewModel.printSelection.annotationColor = color
            }
        } label: {
            Circle()
                .fill(Color(red: color.red, green: color.green, blue: color.blue))
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(
                    current == color ? Color.accentColor : Color.primary.opacity(0.2),
                    lineWidth: current == color ? 2 : 1))
        }
        .buttonStyle(.plain)
        .interactiveControl(cornerRadius: 11, horizontal: 3, vertical: 3)
        .accessibilityLabel("\(name) annotation colour")
        .accessibilityAddTraits(current == color ? [.isSelected] : [])
        .help(name)
    }

    /// The selected annotation's size, or the size the next one will take.
    private var annotationScaleBinding: Binding<Double> {
        Binding(
            get: {
                viewModel.printSelection.selectedAnnotationLocation?.annotation.scale
                    ?? viewModel.printSelection.annotationScale
            },
            set: { newValue in
                if let selected = viewModel.printSelection.selectedAnnotationLocation {
                    viewModel.printSelection.setAnnotationScale(
                        newValue, id: selected.annotation.id, forKey: selected.key)
                } else {
                    viewModel.printSelection.annotationScale =
                        PrintOverlayAnnotation.clampScale(newValue)
                }
            })
    }

    /// Percent of the image's height, as the film inspector states it.
    private var annotationSizeLabel: String {
        let scale = viewModel.printSelection.selectedAnnotationLocation?.annotation.scale
            ?? viewModel.printSelection.annotationScale
        return "\(Int((scale * 100).rounded()))%"
    }

    // MARK: - Gestures

    /// Steps through the series with the scroll wheel.
    ///
    /// Scrolling pages images rather than zooming: on a wheel that is the
    /// reading gesture — walk the stack — and zoom is on the mouse button
    /// (⌘-drag), where it can be held steady. One notch is one image, however
    /// hard the wheel is spun; see ``ScrollStepAccumulator``.
    private func scrollImages(_ delta: ScrollWheelDelta) {
        let steps = scrollSteps.steps(for: delta)
        guard steps != 0 else { return }
        for _ in 0..<abs(steps) {
            // Scrolling up walks back through the stack, as it does in a list.
            if steps > 0 {
                viewModel.navigateToPreviousImage()
            } else {
                viewModel.navigateToNextImage()
            }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                magnifyBy = value.magnification
            }
            .onEnded { value in
                viewModel.zoomLevel = GestureHelpers.clampZoom(
                    viewModel.zoomLevel * value.magnification
                )
                magnifyBy = 1.0
            }
    }

    /// Drag: pans by default, or applies whichever tool is armed.
    ///
    /// A single click still reaches tile focus/selection unaffected — this is
    /// a `DragGesture`, so a tap that never moves resolves as a tap on the
    /// container instead. Dragging up enlarges, as pushing a zoom slider away
    /// from you does.
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Every tool records that its drag is live, not just pan: the
                // pointer changes on mouse-down to confirm the gesture took, and
                // a tool whose drag was never marked would go on showing its
                // resting shape all the way through the action.
                isToolDragging = true
                switch activeTool {
                case .windowing:
                    let dx = Double(value.translation.width - wlDragStart.width)
                    let dy = Double(value.translation.height - wlDragStart.height)
                    viewModel.adjustWindowLevel(deltaX: dx, deltaY: dy)
                    wlDragStart = value.translation
                case .zoom:
                    let dy = Double(value.translation.height - zoomDragStart.height)
                    viewModel.zoomLevel = GestureHelpers.clampZoom(
                        viewModel.zoomLevel * (1.0 - dy * Self.dragZoomSensitivity))
                    zoomDragStart = value.translation
                case .rotate:
                    rotateByDrag(to: value.location)
                case .pan:
                    dragOffset = value.translation
                case .annotation:
                    // The drawing tool's gestures live on the annotation
                    // overlay, which sits above this one and consumes what it
                    // uses. A drag that reaches here (the tool over the
                    // letterbox, say) must not also move the picture.
                    break
                }
            }
            .onEnded { value in
                isToolDragging = false
                switch activeTool {
                case .windowing:
                    wlDragStart = .zero
                case .zoom:
                    zoomDragStart = .zero
                case .rotate:
                    rotateByDrag(to: value.location)
                    rotateDragBearing = nil
                case .pan:
                    viewModel.panOffsetX += value.translation.width
                    viewModel.panOffsetY += value.translation.height
                    dragOffset = .zero
                case .annotation:
                    break
                }
            }
    }

    /// Zoom fraction per point dragged.
    private static let dragZoomSensitivity: Double = 0.005

    /// What a drag will do right now, spoken.
    ///
    /// The pointer's shape carries this for a sighted reader; the hint is the
    /// same fact for one using VoiceOver, which is why it names the armed tool
    /// rather than listing every tool that could be armed.
    private var imageAccessibilityHint: String {
        "\(activeTool.displayName) tool armed. \(activeTool.guidance) "
        + "Press W, Z, E, A or H to change tool; scroll to step through images."
    }

    /// Sets the pointer's shape over the reading area to match the armed tool.
    ///
    /// Only once there is a picture: over an empty viewer none of the tools has
    /// anything to act on, and a magnifier over it promises otherwise.
    ///
    /// The pointer's shape for the armed tool.
    ///
    /// Applied as the outermost overlay of the whole image area rather than on
    /// the picture — see the call site for why that position is load-bearing.
    /// `allowsHitTesting(false)` is what stops it swallowing the drags, clicks
    /// and right-clicks of everything it now covers.
    @ViewBuilder
    private var toolCursorLayer: some View {
        #if os(macOS)
        // The closed hand for as long as the image is being carried, the tool's
        // own shape the rest of the time — the same before/during distinction
        // the film preview makes.
        //
        // No `.allowsHitTesting(false)` here, deliberately. SwiftUI's exclusion
        // can detach the view from the window's tracking altogether, and the
        // pointer then never changes at all. `ToolCursor`'s own view already
        // overrides `hitTest` to return nil, which refuses the clicks and drags
        // without giving up its cursor rect, so the gestures underneath still
        // get every event. The film preview does the same thing for the same
        // reason.
        ToolCursor(cursor: viewModel.hasImage
                   ? activeTool.cursor(isDragging: isToolDragging)
                   : nil)
        #else
        Color.clear
        #endif
    }

    /// The keys that arm each tool, and the one-shot actions beside them.
    ///
    /// Zero-sized buttons behind the image: the toolbar's own buttons could
    /// carry these, but the flip and invert icons come and go with the image's
    /// photometric interpretation, and a key that disappears with its button is
    /// worse than no key. Delivered wherever the viewer is, like the film's.
    private var toolShortcuts: some View {
        ZStack {
            ForEach(ImageViewerDragTool.allCases) { tool in
                Button("") { arm(tool) }
                    .keyboardShortcut(KeyEquivalent(tool.shortcut), modifiers: [])
            }

            // No escape key here. Escape is how the inspector sheet, the print
            // sheet and the ⌘/ popover are dismissed, and a second always-live
            // claim on it risks the reader's way out of a modal to save them
            // pressing H. H is the way back to pan.

            // Guarded in the action rather than by `.disabled`: inversion is
            // meaningless on a colour image, and doing the check here means the
            // key is simply inert there instead of depending on whether a
            // disabled button forgoes its shortcut or swallows it.
            Button("") {
                guard viewModel.isMonochrome else { return }
                viewModel.toggleInversion()
            }
            .keyboardShortcut("v", modifiers: [])

            // The bracket pair reads as the two mirror axes: [ lays the image
            // over left-to-right, ] over top-to-bottom.
            Button("") { viewModel.flipHorizontal() }
                .keyboardShortcut("[", modifiers: [])
            Button("") { viewModel.flipVertical() }
                .keyboardShortcut("]", modifiers: [])

            // Deletes the selected drawn annotation, as on the film. Inert
            // when nothing is selected — the viewer has no other use for the
            // key, so there is nothing to swallow.
            Button("") { viewModel.removeSelectedDrawnAnnotation() }
                .keyboardShortcut(.delete, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Arms a tool, or drops back to pan if it was already armed.
    ///
    /// Pan itself is the resting state, so pressing it twice cannot leave the
    /// viewer with nothing armed.
    private func arm(_ tool: ImageViewerDragTool) {
        activeTool = (activeTool == tool) ? .pan : tool
    }

    /// Measures the space a drag reports its locations in, so the rotate tool knows
    /// where the centre of the picture it is turning actually is.
    private var toolSpaceReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { toolSpaceSize = geo.size }
                .onChange(of: geo.size) { _, newSize in toolSpaceSize = newSize }
        }
    }

    /// Turns the image by the arc the pointer just swept around the picture's centre.
    ///
    /// The pointer is a handle on the picture: drag round clockwise and it follows
    /// clockwise, drag back and it unwinds, all the way through the full circle in
    /// either direction with no quarter-turn snapping. Deltas rather than absolutes,
    /// so the picture keeps whatever angle it already had and the drag can start
    /// anywhere on the image.
    ///
    /// Near the centre the bearing is noise — a pixel of jitter there swings it
    /// wildly — so ``GestureHelpers/dragBearing(x:y:pivotX:pivotY:minimumRadius:)``
    /// stays silent until the pointer is far enough out, and the first bearing after
    /// that only anchors the drag.
    private func rotateByDrag(to location: CGPoint) {
        let space = toolSpaceSize == .zero ? viewSize : toolSpaceSize
        guard space.width > 0, space.height > 0 else { return }
        guard let bearing = GestureHelpers.dragBearing(
            x: Double(location.x),
            y: Double(location.y),
            pivotX: Double(space.width) / 2,
            pivotY: Double(space.height) / 2
        ) else { return }
        defer { rotateDragBearing = bearing }
        guard let previous = rotateDragBearing else { return }
        viewModel.rotate(byDegrees: GestureHelpers.shortestAngleDelta(
            from: previous, to: bearing))
    }

    // MARK: - Toolbar tool buttons

    /// A toolbar icon for an armable tool (windowing, zoom): tinted while
    /// active, so it's clear at a glance which one a drag will apply.
    @ViewBuilder
    private func toolButton(
        systemImage: String,
        isActive: Bool,
        label: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .help(help)
        // Hover, press and armed all through the one modifier the rest of the
        // app's controls use, rather than a bare accent wash of its own.
        //
        // The wash alone left this rail saying less than any other control in
        // the app: nothing happened on hover, so a reader could not tell the
        // four tool glyphs from the one-shot action glyphs beside them without
        // clicking, and the armed tool was a soft tint with no edge — the
        // weakest statement on screen for the question the rail exists to
        // answer, which is "what will my next drag do".
        // Inset, because this lives in a `ToolbarItemGroup`: the group lays its
        // items to a fixed metric inside one shared bezel, so a highlight that
        // *grows* the item draws outside that bezel and over the neighbouring
        // group — which is exactly what the armed tool's border was doing.
        //
        // Inset it is instead: the plate is drawn a point inside the item's own
        // bounds rather than several points outside them. A point, not the
        // 5×4 the rail chips use — an inset that large would shrink the plate
        // to less than the glyph it is supposed to sit behind.
        .interactiveControl(cornerRadius: 5, horizontal: 1, vertical: 1,
                            isSelected: isActive, isInset: true)
        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
    }

    // MARK: - Toolbar

    /// Everything the print menu's items read, rolled into one identity.
    ///
    /// The two flags are the ones that grey an item out; the other two decide
    /// whether an item is in the menu at all. Any of them changing has to give
    /// the toolbar a menu it has not built before — see the `.id` that uses it.
    private var printMenuIdentity: String {
        let marked = viewModel.printSelection.count
        let full = viewModel.isLayoutFullyMarkedForPrint
        return "\(marked)|\(full)|\(viewModel.isInSeries)|\(viewModel.isMultiFrame)"
    }

    /// The layout button's face: the grid, and what it is filled with.
    ///
    /// The fill is named only when there is a grid to fill — at 1×1 there is one
    /// image and "1×1 Series" would be answering a question nobody asked.
    private var layoutMenuLabel: String {
        guard viewModel.isMultiCellLayout else { return viewModel.layout.displayName }
        return "\(viewModel.layout.displayName) \(viewModel.layoutFill.displayName)"
    }

    @ToolbarContentBuilder
    private var viewerToolbar: some ToolbarContent {
        // The series pane toggle, ahead of everything else. It is the only
        // item that acts on the window rather than on the picture — it opens
        // and closes a whole column — and it is what a reader reaches for
        // first, to find the series they mean before doing anything to it.
        // Leading position keeps it off the overflow menu the tool run pushes
        // items into on a narrow window, and puts it beside the pane it hides.
        if !viewModel.studySeries.isEmpty {
            ToolbarItem(placement: .navigation) {
                Button {
                    viewModel.isSeriesPaneVisible.toggle()
                } label: {
                    Image(systemName: viewModel.isSeriesPaneVisible
                          ? "sidebar.left" : "sidebar.leading")
                }
                .keyboardShortcut("s", modifiers: [])
                .accessibilityLabel(viewModel.isSeriesPaneVisible
                                    ? "Hide series list" : "Show series list")
                .help("Series pane (S) — every series in the study; drag one onto a tile to load it")
            }
        }

        // Series navigation — grouped in one item so it doesn't fragment the toolbar
        if viewModel.isInSeries {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 4) {
                    Button {
                        viewModel.navigateToPreviousFile()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!viewModel.canGoPreviousFile)
                    .accessibilityLabel("Previous file in series")
                    .help("Previous file in series (↑)")

                    Text(viewModel.seriesPositionText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("File \(viewModel.currentFileIndex + 1) of \(viewModel.seriesFiles.count)")

                    Button {
                        viewModel.navigateToNextFile()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!viewModel.canGoNextFile)
                    .accessibilityLabel("Next file in series")
                    .help("Next file in series (↓)")
                }
            }
        }

        // Cine transport for anything that runs — a multi-frame image or a
        // video clip, which both open already looping.
        // The overlay bar at the bottom of the picture carries the full set of
        // controls; this is the stop/start alone, kept in the toolbar so the
        // reader can halt the motion without first going hunting for that bar.
        if viewModel.hasCineTransport {
            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.playbackState == .playing
                          ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(viewModel.playbackState == .playing
                                    ? "Stop cine playback" : "Start cine playback")
                .help(viewModel.playbackState == .playing
                      ? "Stop the loop (Space) — the frame on screen stays put"
                      : "Loop the frames (Space)")
            }
        }

        // Saved views — the default view and whatever the reader has stored for
        // the image on screen. Placed beside the series controls because it is
        // navigation of a kind: which of several readings of this image to show.
        if viewModel.dicomFile != nil {
            ToolbarItem(placement: .automatic) {
                SavedViewPickerView(viewModel: viewModel)
            }
        }

        // Tile layout — the viewer grid, which is also the film grid
        if showsImageTools {
            ToolbarItem(placement: .automatic) {
                Menu {
                    // What the grid is a grid *of*, before its shape: the shapes
                    // below all mean something different depending on this answer,
                    // so it reads top-down as "a grid of images, three by three".
                    Section("Fill with") {
                        ForEach(ViewerLayoutFill.allCases) { fill in
                            Button {
                                viewModel.applyLayoutFill(fill)
                            } label: {
                                if fill == viewModel.layoutFill {
                                    Label(fill.displayName, systemImage: "checkmark")
                                } else {
                                    Label(fill.displayName, systemImage: fill.symbolName)
                                }
                            }
                            .help(fill.note)
                        }
                    }

                    Section("Grid") {
                    ForEach(ViewerTileLayout.allCases) { option in
                        Button {
                            viewModel.applyLayout(option)
                        } label: {
                            if option == viewModel.layout {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                        // The square grids get a digit each — the digit is the side,
                        // so ⌘3 is 3×3. The oblong layouts stay menu-only rather than
                        // taking digits whose number means nothing.
                        .modifier(SquareLayoutShortcut(layout: option))
                    }
                    }
                } label: {
                    Label(layoutMenuLabel, systemImage: "square.grid.2x2")
                }
                .disabled(!viewModel.hasImage)
                // A fresh menu whenever the shape or the fill changes, for the same
                // reason the print menu carries one: a toolbar `Menu` is bridged to
                // an AppKit menu that is built once and re-used, so the ticks beside
                // the items would otherwise keep the state they were born with.
                .id("\(viewModel.layout.id)|\(viewModel.layoutFill.rawValue)")
                .accessibilityLabel("Tile layout, currently \(layoutMenuLabel)")
                .help("Tile layout (⌘1–⌘4 for 1×1 to 4×4) — splits the reading area into tiles; "
                      + "they map to film cells in the same order. Fill them with one series "
                      + "each, or with consecutive images of this series.")
            }
        }

        // DICOM print — mark the current frame, then open the print sheet
        if showsImageTools {
            ToolbarItemGroup(placement: .automatic) {
                // Clicking marks the image on screen; the menu offers the bulk
                // selections, so "select all" is one click from where marking lives.
                Menu {
                    Button("Select All for Print") {
                        viewModel.markLayoutForPrint()
                    }
                    .disabled(viewModel.isLayoutFullyMarkedForPrint)
                    // Every mark comes off, wherever it was made — see the same item
                    // in the image's context menu.
                    Button("Unselect All for Print") {
                        viewModel.clearAllPrintMarks()
                    }
                    .disabled(viewModel.printSelection.isEmpty)
                    if viewModel.isInSeries {
                        Button("Mark Whole Series for Print") {
                            viewModel.markWholeSeriesForPrint()
                        }
                    }
                    if viewModel.isMultiFrame {
                        Button("Mark All Frames for Print") {
                            viewModel.markAllFramesOfCurrentFileForPrint()
                        }
                    }
                } label: {
                    Image(systemName: viewModel.isCurrentFrameMarkedForPrint
                          ? "checkmark.rectangle.stack.fill"
                          : "checkmark.rectangle.stack")
                } primaryAction: {
                    viewModel.togglePrintMarkForCurrentFrame()
                }
                // A new menu whenever anything the items above read has changed.
                //
                // Not decoration: a toolbar `Menu` with a `primaryAction` is bridged
                // to an AppKit menu that is built once and then re-used, so the
                // items keep the enabled state they were *born* with. The menu is
                // first built with an empty film, and "Unselect All for Print" then
                // stayed greyed out with four images on the film — while the printer
                // button beside it, reading the same `printSelection.isEmpty` from
                // the same body, was correctly live. Changing the identity is what
                // makes SwiftUI build a fresh menu rather than hand back the stale
                // one; it also covers the two items that come and go below.
                .id(printMenuIdentity)
                .disabled(!viewModel.hasImage)
                .accessibilityLabel(viewModel.isCurrentFrameMarkedForPrint
                                    ? "Unmark image for print" : "Mark image for print")
                .help("Mark this image for print (M) — click to mark the image on screen; "
                      + "the menu marks a whole series or every frame at once")
                .keyboardShortcut("m", modifiers: [])

                Button {
                    viewModel.isPrintTrayVisible.toggle()
                } label: {
                    Image(systemName: viewModel.isPrintTrayVisible
                          ? "sidebar.trailing" : "sidebar.right")
                }
                .keyboardShortcut("t", modifiers: [])
                .accessibilityLabel(viewModel.isPrintTrayVisible
                                    ? "Hide selected images" : "Show selected images")
                .help("Selected-images tray (T) — the images marked for print, in film order")

                Button {
                    openPrintSheet()
                } label: {
                    Image(systemName: "printer")
                        .overlay(alignment: .topTrailing) {
                            if viewModel.printSelection.count > 0 {
                                Text("\(viewModel.printSelection.count)")
                                    .font(.system(size: 9).monospacedDigit())
                                    .padding(3)
                                    .background(.tint, in: Circle())
                                    .foregroundStyle(.white)
                                    .offset(x: 8, y: -8)
                            }
                        }
                }
                .disabled(viewModel.printSelection.isEmpty)
                .accessibilityLabel("Print marked images")
                .help("Print marked images (⌘P) — opens the print sheet with everything marked, "
                      + "laid onto film")
                .keyboardShortcut("p", modifiers: .command)
            }
        }

        // Tools — pan, windowing, zoom and rotate are click-and-drag tools,
        // exclusive of each other and highlighted while armed; invert, flip, fit
        // and reset are one-shot actions. Quarter turns stay in the Image menu
        // and the image's context menu, for when an exact 90° is what's wanted —
        // the toolbar icon arms the free-turn drag. No dropdown: every tool is a
        // single visible icon, and every one of them has a key.
        if showsImageTools {
            ToolbarItemGroup(placement: .automatic) {
                // The drag tools, in the order pan, windowing, zoom, rotate. Built
                // from the enum so the icon, the tooltip and the key can only ever
                // describe the tool the button actually arms.
                ForEach(ImageViewerDragTool.allCases) { tool in
                    toolButton(
                        systemImage: tool.symbolName,
                        isActive: activeTool == tool,
                        label: "\(tool.displayName) tool",
                        help: tool.help
                    ) {
                        arm(tool)
                    }
                }

                if viewModel.isMonochrome {
                    // The half-filled circle — the lightbox glyph every viewer
                    // uses for invert. It had to be a square while the windowing
                    // tool wore the other half-filled circle; windowing is the sun
                    // now, so the circle reads unambiguously as invert again.
                    Button {
                        viewModel.toggleInversion()
                    } label: {
                        Image(systemName: viewModel.isInverted
                              ? "circle.lefthalf.filled" : "circle.righthalf.filled")
                    }
                    .accessibilityLabel(viewModel.isInverted ? "Remove inversion" : "Invert grayscale")
                    // The key lives on the hidden button in `toolShortcuts`, not
                    // here: this button is only on the toolbar for monochrome
                    // images, and a key that vanishes with its button is worse than
                    // one that is always delivered. Same for the two flips below.
                    .help(viewModel.isInverted
                          ? "Remove grayscale inversion (V) — back to black-on-white as stored"
                          : "Invert grayscale (V) — swaps black and white, as on a lightbox")
                }

                // Pseudo-colour palette — the CLUT the image is read through. In
                // the tools group and next to inversion because it belongs to the
                // same question those two answer: how the stored values are turned
                // into what the reader sees. It is not a print setting; it only
                // reaches the film because a mark carries whatever was on screen.
                ViewerPalettePickerView(viewModel: viewModel)

                Button { viewModel.flipHorizontal() } label: {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                .accessibilityLabel("Flip horizontal")
                .help("Flip horizontally ([) — mirrors left to right; laterality markers move with it")

                Button { viewModel.flipVertical() } label: {
                    Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                }
                .accessibilityLabel("Flip vertical")
                .help("Flip vertically (]) — mirrors top to bottom")

                Button {
                    viewModel.fitToView(viewWidth: viewSize.width, viewHeight: viewSize.height)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("Fit image to view")
                .help("Fit image to view (F) — sizes it so the whole picture is on screen, and re-centres it")
                .keyboardShortcut("f", modifiers: [])

                Button { viewModel.resetView() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Reset to original image")
                .help("Reset to original image (R) — undoes zoom, pan, rotation, flip, "
                      + "windowing, inversion, colour, and drawn annotations")
                .keyboardShortcut("r", modifiers: [])
            }
        }

        // Overlays & Panels menu — collapses toggles and panels into one button
        if showsImageTools {
            ToolbarItem(placement: .automatic) {
                Menu {
                    // Both open a panel now, so both are buttons rather than
                    // toggles: a tick beside an item that raises a window claims
                    // the window is a state of the picture, which it is not.
                    Button {
                        viewModel.showMetadataOverlay = true
                    } label: {
                        Label("Image Metadata", systemImage: "info.circle")
                    }
                    .disabled(!viewModel.hasImage)
                    Divider()
                    Toggle(isOn: Bindable(viewModel).showDICOMInspector) {
                        Label("DICOM Tag Inspector", systemImage: "list.bullet.rectangle")
                    }
                    .disabled(viewModel.dicomFile == nil)
                } label: {
                    Image(systemName: "square.stack.3d.up")
                }
                .help("Panels — this image's pixel metadata, and the DICOM tag inspector")
            }
        }

        // Study download — the whole study out as one ZIP: every series' files
        // plus the saved presentation states. A standing tool of its own rather
        // than a row inside the saved-view picker: gathering a study is not a
        // reading of an image, and a control that comes and goes reads as
        // belonging to whatever appeared with it. It stays in place and greys
        // out when there is no single study to gather — loose files have no
        // Study Instance UID to gather by — so its absence is never mistaken
        // for the feature not existing.
        //
        // Fenced off on both sides. Two adjacent `ToolbarItem`s are separate
        // items to SwiftUI and one continuous run of icons to a reader, so
        // sitting it next to the shortcuts button made the two read as a pair —
        // and these two have nothing to do with each other: one gathers a
        // study, the other lists keys. The rules are what make it a tool on its
        // own rather than the first or last of someone else's group.
        //
        // The archive is built and measured first, and a prompt then states its
        // exact size; nothing is written anywhere of the reader's until they
        // confirm.
        ToolbarItem(placement: .automatic) {
            studyDownloadButton
        }

        // The keys, where they can be found.
        ToolbarItem(placement: .automatic) {
            KeyboardShortcutsButton(
                title: "Viewer Shortcuts",
                groups: KeyboardShortcutsLegendView.viewerGroups)
        }
    }
}

// MARK: - Study download

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
extension ImageViewerView {

    /// The download button with a rule on either side of it.
    ///
    /// Whether the picture tools belong on the toolbar for what is on screen.
    ///
    /// Windowing, zoom, rotation, the tile grid, print and the overlay panels
    /// all act on pixels the viewer has decoded. A clip, a report and a
    /// document have none, so the tools are absent rather than present and
    /// inert — a disabled row of icons invites the reader to wonder what is
    /// wrong with the study, and nothing is.
    ///
    /// Computed with no stored half on purpose: it is derived from whatever
    /// instance is loaded right now, so stepping from a clip back to an image
    /// restores the tools with no reset step that could be forgotten.
    private var showsImageTools: Bool {
        !viewModel.isNonImageContent && !viewModel.isWaveform
    }

    /// Extracted from the toolbar builder rather than written inline: the
    /// builder is long enough that adding the two rules as their own
    /// `ToolbarItem`s tipped it past what the type-checker will infer in one
    /// expression. One item holding all three also keeps them together — a
    /// rule that can be separated from the control it fences is not a fence.
    @ViewBuilder
    var studyDownloadButton: some View {
        HStack(spacing: 8) {
            Divider().frame(height: 16)

            Button {
                Task { await viewModel.prepareStudyDownload() }
            } label: {
                if viewModel.isPreparingStudyDownload {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle")
                }
            }
            // No `.buttonStyle` of its own. The toolbar's default style is what
            // sizes a glyph to the toolbar's control metric, and `.borderless`
            // opts out of it — which drew this icon at plain text size while
            // every tool beside it stayed at the larger toolbar size. A control
            // that is the odd one out by a few points reads as broken rather
            // than as distinct, and the rules either side already do the job of
            // setting it apart.
            .disabled(viewModel.isPreparingStudyDownload || !viewModel.canDownloadStudy)
            .accessibilityLabel("Download study")
            .help(viewModel.canDownloadStudy
                  ? "Download study — the study's images and saved presentation "
                    + "states as one ZIP. The ZIP's size is shown for confirmation "
                    + "before anything is saved."
                  : "Download study — unavailable until a study is open. Loose "
                    + "files have no study to gather.")

            Divider().frame(height: 16)
        }
    }
}

// MARK: - Tools

/// A click-and-drag tool armed from the toolbar.
///
/// `.pan` is the resting state — a drag with nothing else armed moves the
/// picture — so it is a case here rather than the `nil` it used to be. Making
/// it a case is what lets it carry a key, an icon and a pointer shape like the
/// rest, and lets the toolbar show that *something* is always armed.
///
/// Each case carries its own name, icon, key and one-line guide. Tooltips, the
/// hidden shortcut buttons and the ⌘/ legend are all built from these, so the
/// three cannot drift apart the way a hand-copied list does.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
enum ImageViewerDragTool: String, CaseIterable, Identifiable {
    case pan
    case windowing
    case zoom
    case rotate

    /// The one drawing tool: text and arrow merged, after Weasis's Annotation
    /// graphic. A click places words; pressing on the thing and dragging pulls
    /// a label out of it, arrow attached.
    case annotation

    var id: String { rawValue }

    /// Whether this tool draws annotations rather than arranging the picture —
    /// the same distinction the film's `CellTool.isDrawing` makes, and for the
    /// same reason: a drawing tool's clicks belong to the annotation overlay,
    /// not to the image underneath it.
    var isDrawing: Bool { self == .annotation }

    var displayName: String {
        switch self {
        case .pan:        return "Pan"
        case .windowing:  return "Window/Level"
        case .zoom:       return "Zoom"
        case .rotate:     return "Rotate"
        case .annotation: return "Annotation"
        }
    }

    var symbolName: String {
        switch self {
        case .pan:       return "hand.draw"
        // The brightness sun, not the half-filled circle: the circle is the
        // Invert button's glyph mirrored, and two near-identical shapes in one
        // toolbar made it hard to scan. Brightness is the thing a windowing
        // drag visibly changes, and the sun is the icon every platform already
        // uses for it.
        case .windowing: return "sun.max"
        case .zoom:      return "magnifyingglass"
        // A closed circle of arrows, not a quarter-turn glyph: this tool turns
        // the picture the whole way round, either way, and a "90°" icon
        // promises the quarter turns that live in the Image menu.
        case .rotate:    return "arrow.triangle.2.circlepath"
        // The letter A — annotation's initial and its shortcut key, so the
        // button, the pointer and the key all say the same thing.
        case .annotation: return "a.square"
        }
    }

    /// The key that arms it, with no modifier.
    ///
    /// R is the viewer's reset and T its print tray, so rotate takes E — the
    /// letter is arbitrary either way, and a key that already does something
    /// else is worse than one that has to be learnt. A is annotation, the one
    /// drawing tool since text and arrow merged into it.
    var shortcut: Character {
        switch self {
        case .pan:        return "h"
        case .windowing:  return "w"
        case .zoom:       return "z"
        case .rotate:     return "e"
        case .annotation: return "a"
        }
    }

    /// What a drag does with this armed — the tooltip's second line, and the
    /// whole of the tool's entry in the shortcut legend.
    var guidance: String {
        switch self {
        case .pan:
            return "Drag to move the image inside the tile."
        case .windowing:
            return "Drag across for window width, up and down for level — "
                 + "left/right widens or narrows the greys, up/down brightens or darkens."
        case .zoom:
            // Pinch only. The wheel is not a zoom gesture here: `ScrollWheelHandler`
            // reports no modifier flags and the viewer pages images on every scroll,
            // ⌘ held or not — so promising ⌘-scroll sent a reader to a key that
            // silently walks the stack instead, which is worse than not mentioning it.
            return "Drag up to enlarge, down to shrink. Pinch to zoom does the same."
        case .rotate:
            return "Drag around the centre of the picture and it follows the pointer, "
                 + "either way, through the full circle."
        case .annotation:
            return "Click on the picture to place text, then type — or press on "
                 + "the thing itself and drag the label out of it, arrow attached. "
                 + "Double-click a label to edit the words; drag the handles of a "
                 + "selected annotation to re-aim the arrow or move the label alone."
        }
    }

    /// Tooltip text: what it is, what the key is, and how to use it.
    var help: String {
        "\(displayName) (\(String(shortcut).uppercased())) — \(guidance)"
    }

    #if os(macOS)
    /// The pointer's shape while this tool is armed.
    ///
    /// The toolbar says which tool is armed, but the toolbar is at the top of
    /// the window and the hand is on the picture — and the cost of being wrong
    /// is a drag that has already windowed an image you meant to pan. The
    /// pointer is the one part of the screen guaranteed to be where the reader
    /// is looking when the drag starts, which is what makes it worth changing.
    /// Windowing, zoom and rotate draw their own toolbar glyph — read from
    /// ``symbolName``, so the pointer and the button cannot describe different
    /// tools. That is what the generic shapes could not do: the crosshair stood
    /// for windowing *and* rotate, so the pointer said "some tool" and left the
    /// reader to remember which.
    ///
    /// Pan keeps the system hand. It is the one tool the platform already has a
    /// universally-read pointer for, and the open/closed hand pair says something
    /// the icon cannot — whether the image is being carried right now.
    /// - Parameter isDragging: whether the tool's drag is running right now. The
    ///   pointer confirming mouse-down is what tells the reader the gesture took
    ///   — on a windowing drag the greys move visibly, but a rotate drag inside
    ///   its dead zone changes nothing at all, and a drag that has not started is
    ///   indistinguishable from one that has until something moves.
    @MainActor
    func cursor(isDragging: Bool = false) -> NSCursor {
        switch self {
        case .pan:
            // The system pair: open before the drag, closed while the image is
            // actually being carried.
            return isDragging ? .closedHand : .openHand
        case .windowing, .zoom, .rotate, .annotation:
            return ToolSymbolCursor.cursor(
                symbolName: isDragging ? activeSymbolName : symbolName,
                fallback: fallbackCursor)
        }
    }

    /// The glyph shown while the drag runs — the filled counterpart of the
    /// resting icon, so the pointer visibly commits without becoming a different
    /// picture. Tools whose symbol has no filled form keep the one they have.
    private var activeSymbolName: String {
        switch self {
        case .pan:        return symbolName
        case .windowing:  return "sun.max.fill"
        case .zoom:       return "magnifyingglass.circle.fill"
        case .rotate:     return "arrow.triangle.2.circlepath.circle.fill"
        // The same letter, filled — the committed counterpart of the
        // resting square, as the other tools' filled forms are.
        case .annotation: return "a.square.fill"
        }
    }

    /// The shape used if the symbol will not render — never seen in practice, but
    /// a pointer that failed to draw would be a pointer that is not there.
    private var fallbackCursor: NSCursor {
        switch self {
        case .pan:        return .openHand
        case .zoom:       return .zoomIn
        case .windowing:  return .crosshair
        case .rotate:     return .crosshair
        case .annotation: return .crosshair
        }
    }
    #endif
}

// MARK: - Layout shortcuts

/// Gives the square tile grids a digit each: ⌘1 is 1×1, ⌘4 is 4×4.
///
/// A modifier rather than an inline `if`, because `keyboardShortcut` has to be
/// absent — not merely unreachable — on the layouts that get no digit.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
private struct SquareLayoutShortcut: ViewModifier {
    let layout: ViewerTileLayout

    func body(content: Content) -> some View {
        if layout.rows == layout.columns, (1...4).contains(layout.rows),
           let key = KeyEquivalent(exactly: layout.rows) {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }
}

private extension KeyEquivalent {
    /// The digit key for a small number, or `nil` if there isn't one.
    init?(exactly number: Int) {
        guard let character = String(number).first else { return nil }
        self.init(character)
    }
}

// MARK: - Print Screen Presenter

/// Raises the print screen when the viewer asks for it.
///
/// On macOS it takes over the viewer's centre panel (see
/// `isPrintScreenEmbedded`): the film composes in the room the images had, and
/// closing it puts the columns back untouched — no separate window whose
/// closing or re-raising could reset the sheet. The film can still be held up
/// against the images on a second display through the print *window*
/// (`StudioWindowID.printPreview`), which the Print Center and the Window menu
/// keep reachable. Everywhere else there are no panels to take over, so it
/// stays a sheet.
///
/// The study-download confirmation and save dialog.
///
/// A modifier of its own rather than more lines on the viewer's body, which is
/// already at the edge of what the type-checker will take. The flow it carries:
/// the view model has built and measured the ZIP; the alert states the exact
/// size and asks; "Download" raises the `fileMover`, whose move takes the
/// temporary file to wherever the reader chose; every other way out — Cancel,
/// esc, a failed or abandoned save — deletes the temporary file instead.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
private struct StudyDownloadPresenter: ViewModifier {
    let viewModel: ImageViewerViewModel

    /// True between "Download" on the size prompt and the save dialog closing.
    @Binding var isMoving: Bool

    func body(content: Content) -> some View {
        content
            .alert(
                "Download This Study?",
                isPresented: Binding(
                    get: { viewModel.studyDownloadPrompt != nil && !isMoving },
                    set: { presented in
                        // Dismissal without "Download" — esc, or the Cancel
                        // button below — is a no; `isMoving` says otherwise.
                        if !presented && !isMoving {
                            viewModel.cancelStudyDownload()
                        }
                    }),
                presenting: viewModel.studyDownloadPrompt
            ) { _ in
                Button("Download") { isMoving = true }
                Button("Cancel", role: .cancel) { viewModel.cancelStudyDownload() }
            } message: { prompt in
                Text("The ZIP holds \(prompt.contentsLabel) and is "
                     + "\(prompt.zipSizeLabel). Download it?"
                     + (prompt.missingFilesLabel.isEmpty
                        ? "" : "\n\n" + prompt.missingFilesLabel))
            }
            .fileMover(
                isPresented: $isMoving,
                file: viewModel.studyDownloadPrompt?.zipURL
            ) { result in
                switch result {
                case .success:
                    viewModel.finishStudyDownload()
                case .failure:
                    viewModel.cancelStudyDownload()
                }
            }
            .alert(
                "Study Download",
                isPresented: Binding(
                    get: { viewModel.studyDownloadError != nil },
                    set: { if !$0 { viewModel.dismissStudyDownloadError() } })
            ) {
                Button("OK", role: .cancel) { viewModel.dismissStudyDownloadError() }
            } message: {
                Text(viewModel.studyDownloadError ?? "")
            }
    }
}

/// The request is a flag rather than a call because it also arrives from the
/// library's "Print…", which fires while the viewer is still being built —
/// hence `onAppear` as well as `onChange`.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
private struct PrintScreenPresenter<SheetContent: View>: ViewModifier {
    @Binding var isRequested: Bool
    let prepare: () -> Void
    /// Puts the print screen into the viewer's own panel (macOS). The shell
    /// owns the flag this raises; the presenter only asks. Unused where the
    /// screen is a sheet.
    let embed: () -> Void
    @ViewBuilder let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .onAppear { if isRequested { present() } }
            .onChange(of: isRequested) { _, requested in
                if requested { present() }
            }
        #else
        content
            .onChange(of: isRequested) { _, requested in
                if requested { prepare() }
            }
            .sheet(isPresented: $isRequested) { sheetContent() }
        #endif
    }

    #if os(macOS)
    /// Prepares the print state, then embeds the screen in the centre panel —
    /// and lowers the flag, which is a request, not the screen's state. Leaving
    /// it raised would make the next request no change at all, and nothing
    /// would happen. The separate print *window* stays reachable from the
    /// Print Center and the Window menu for reading the film beside the viewer
    /// or on a second display; this in-panel takeover is what the viewer's own
    /// print button asks for, and it cannot be reset by being re-raised — the
    /// film survives the round trip (see `resetForNewFilmIfNeeded`).
    private func present() {
        prepare()
        embed()
        isRequested = false
    }
    #endif
}

// MARK: - Print Sheet Host

/// Creates the print state on demand so the sheet works no matter who opened it
/// — the toolbar button, or "Print…" in the library before this view appeared.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
private struct PrintSheetHost: View {
    let selection: PrintSelectionModel
    @Binding var printViewModel: PrintViewModel?
    /// Size of the window the sheet was raised from, when it is known.
    var parentSize: CGSize?

    var body: some View {
        Group {
            if let printViewModel {
                PrintSettingsView(viewModel: printViewModel, parentSize: parentSize)
            } else {
                ProgressView()
                    .frame(minWidth: 480, minHeight: 300)
            }
        }
        .task {
            if printViewModel == nil {
                printViewModel = PrintViewModel(selection: selection)
            } else {
                // The held film may describe a previous visit's tray: if the
                // marks have changed, the range and the picked cells answer for
                // images no longer on the film. Same marks, though, and this is
                // the same film — the reset below skips, and the sheet reopens
                // on the work in progress.
                printViewModel?.selection = selection
                printViewModel?.loadPrinters()
            }
            printViewModel?.resetForNewFilmIfNeeded()
        }
    }
}

#endif
