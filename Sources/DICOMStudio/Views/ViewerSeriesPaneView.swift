// ViewerSeriesPaneView.swift
// DICOMStudio
//
// DICOM Studio — the viewer's series pane.
//
// Who the patient is at the top, then every series of the open study as a card:
// a thumbnail, what it is, how much of it there is, and whether it has been
// looked at yet. Clicking a card shows that series; dragging it onto a tile
// hangs it there.
//
// Not every series is pictures. Reports, encapsulated documents and presentation
// states are listed too, with the symbol for what they hold in place of a
// thumbnail that could never be rendered.

#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct ViewerSeriesPaneView: View {
    @Bindable var viewModel: ImageViewerViewModel

    #if canImport(CoreGraphics)
    /// One thumbnail per series — the series' first instance, unarranged.
    @State private var thumbnails = FrameImageStore(maxDimension: 256)

    /// The series whose presentation-state list is open, by Series Instance
    /// UID. One at a time — the badges are small and adjacent, and two open
    /// popovers over a scrolling pane cannot be told apart.
    @State private var savedViewListSeriesUID: String?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            ViewerPaneHeader("Series",
                             systemImage: "rectangle.stack",
                             count: viewModel.studySeries.count)

            patientBanner

            seriesList
        }
        // The pane surface, a step lighter than the gutter and seamed against
        // it on the right: the picture beside it is the pure black on screen,
        // and a pane at the gutter's tone would read as part of the mount.
        .viewerPaneSurface(imageEdge: .trailing)
    }

    // MARK: - Who this is

    /// Patient and study identification, above the series.
    ///
    /// The pane is the one part of the viewer that is always on screen while
    /// reading, so it is where "whose study am I in?" belongs — the image
    /// overlay answers it per picture, this answers it for the session.
    @ViewBuilder
    private var patientBanner: some View {
        let text = viewModel.patientOverlayText
        if text.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 3) {
                // Who this is and what made the pictures, in the largest type in
                // the pane: it is the one thing a reader must never have to
                // squint at, and it is checked far more often than any series
                // description.
                if !viewModel.patientIdentityLine.isEmpty {
                    Text(viewModel.patientIdentityLine)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                // Description then date, each on its own line and each in the
                // same lit type as the name: run together on one line they read
                // as a caption, which is not what identification is for.
                if let description = viewModel.studyDescriptionSanitizedForOverlay {
                    Text(description)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                if let date = viewModel.studyDateTimeForOverlay {
                    Text(date)
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                if let protocolLine = viewModel.protocolLineForOverlay {
                    Text(protocolLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            // A plate under the identification separates whose study this is
            // from the list of series below it at a glance, without a rule that
            // would read as another divider. Neutral, not accented: in the
            // viewer the accent means "this is what prints", and a blue block
            // in the corner of the left-hand pane was the loudest thing on a
            // screen whose subject is the images in the middle.
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            )
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Patient: \(viewModel.patientIdentityLine). "
                + [viewModel.studyDescriptionSanitizedForOverlay, viewModel.studyDateTimeForOverlay]
                    .compactMap { $0 }.joined(separator: ". "))
        }
    }

    private var seriesList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.studySeries) { entry in
                    card(entry)
                }
            }
            .padding(8)
        }
        #if canImport(CoreGraphics)
        .onAppear { refreshThumbnails() }
        .onChange(of: viewModel.studySeries) { _, _ in refreshThumbnails() }
        #endif
    }

    // MARK: - Saved-view badge

    /// The badge saying this series' images carry presentation states, and the
    /// list it opens.
    ///
    /// The glyph and the purple are the toolbar picker's, so a reader who has
    /// met either recognises the other; it sits in the corner opposite the
    /// series number so the two badges never crowd each other.
    ///
    /// A button rather than a label now: the badge answered "are there any?",
    /// and the reader also wants "which images, and which objects?". Clicking
    /// it opens that list; it does not change what is on screen.
    @ViewBuilder
    private func savedViewBadge(_ entry: ViewerSeriesEntry) -> some View {
        let references = viewModel.savedViewReferences(forSeries: entry.seriesInstanceUID)

        Button {
            savedViewListSeriesUID =
                savedViewListSeriesUID == entry.seriesInstanceUID
                    ? nil : entry.seriesInstanceUID
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "slider.horizontal.below.rectangle")
                // The count, so the pane answers "how many" without being
                // opened. Suppressed at one: "PR 1" reads as an identifier.
                if references.count > 1 {
                    Text("\(references.count)")
                        .font(.caption2.monospacedDigit().bold())
                }
            }
            .font(.caption2.bold())
            .foregroundStyle(Color.purple)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.black.opacity(0.6), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(4)
        .help("Presentation states on this series' images — click to list them")
        .accessibilityLabel("\(references.count) presentation states. Show the list.")
        .popover(isPresented: Binding(
            get: { savedViewListSeriesUID == entry.seriesInstanceUID },
            set: { if !$0 { savedViewListSeriesUID = nil } }
        )) {
            ViewerSeriesSavedViewList(entry: entry, references: references)
        }
    }

    // MARK: - One series

    /// Ring around the card of the series on screen.
    ///
    /// White, not accent. In the viewer the accent means "this is what prints" —
    /// it is on the marked tiles, the film chip and the tray — and spending it
    /// on "this is what you are looking at" as well left the reader with one
    /// colour answering two questions. Which series is up is already obvious
    /// from the images in the middle of the screen; the pane only has to confirm
    /// it, which a neutral ring does without lighting up the corner of the
    /// screen furthest from the picture.
    private static let currentCardRingWidth: CGFloat = 1.5

    @ViewBuilder
    private func card(_ entry: ViewerSeriesEntry) -> some View {
        let isCurrent = viewModel.isCurrentSeries(entry.seriesInstanceUID)

        VStack(spacing: 6) {
            thumbnail(entry)
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                // Nothing is drawn on the picture. A ring around the thumbnail
                // framed the letterboxing rather than the image — most series
                // sit in a black box wider than they are — so it read as a frame
                // around empty black. The card carries the selection instead.
                .overlay(alignment: .topLeading) {
                    // The series number, which is how the pane is ordered and how
                    // a reader refers to a series aloud.
                    if let number = entry.seriesNumberLabel {
                        Text(number)
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(4)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    // Saved views exist for this series' images. The glyph and
                    // the purple are the toolbar picker's, so a reader who has
                    // met either recognises the other; the corner opposite the
                    // series number, so the two badges never crowd each other.
                    if viewModel.seriesHasSavedViews(entry.seriesInstanceUID) {
                        savedViewBadge(entry)
                    }
                }

            if isCurrent {
                Label("Current series", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }

            Text(entry.title)
                .font(.callout.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(entry.countsLabel)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))

            Text(entry.orientationLabel)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))

        }
        .padding(8)
        .frame(maxWidth: .infinity)
        // One cue, on the card: a neutral ring and a surface lifted off the pane.
        // The card is what the ring belongs on — it is the whole entry, picture
        // and description together, and it is the thing being chosen.
        .background(isCurrent ? Color.white.opacity(0.12) : Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isCurrent ? Color.white.opacity(0.85) : .clear,
                              lineWidth: Self.currentCardRingWidth)
        }
        .contentShape(Rectangle())
        // Hover, outside the card's own surface and ring: the ring says which
        // series is *shown*, this says which one the pointer is on. Two
        // different questions, so two different cues.
        //
        // Hover only — no press tracking. The card is `.draggable`, so the
        // pointer-down window already belongs to a drag recogniser, and a
        // second zero-distance `DragGesture` layered under it claimed the
        // sequence and swallowed the tap: clicking a card stopped hanging its
        // series. The press cue is not worth the click.
        // And the card keeps its own `contentShape(Rectangle())` above: the
        // whole card is the click target, corners included, which a rounded
        // shape stamped over it would trim.
        .interactiveControl(cornerRadius: 7, horizontal: 0, vertical: 0,
                            tracksPress: false, extendsHitArea: false)
        // A click shows the series, from its first image. Reading is a matter of
        // moving between series constantly, so it is one click, not two; the
        // double-click and the drag still work for anyone expecting them.
        .onTapGesture {
            viewModel.selectSeries(entry.seriesInstanceUID)
        }
        .onTapGesture(count: 2) {
            viewModel.selectSeries(entry.seriesInstanceUID)
        }
        // The drag payload is the Series Instance UID, which is all a tile needs
        // to look the series up again.
        .draggable(entry.seriesInstanceUID) {
            Text(entry.title)
                .font(.caption)
                .padding(6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
        }
        .contextMenu {
            Button("Open in Selected Tile") {
                viewModel.assignSeriesToFocusedCell(entry.seriesInstanceUID)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.spokenLabel), \(entry.countsLabel), \(entry.orientationLabel)"
            + (isCurrent ? ", current series" : ""))
        .accessibilityHint("Click to show this series in the selected tile")
    }

    @ViewBuilder
    private func thumbnail(_ entry: ViewerSeriesEntry) -> some View {
        // Several objects come first, even when none of them can be drawn: a
        // three-clip video series that falls straight to the placeholder shows
        // one film icon for three recordings, and the reader has no way to ask
        // for the second. The strip handles the undrawable case itself.
        if entry.objectPreviews.count > 1 {
            objectStrip(entry)
        } else if !entry.isImageSeries {
            // A report or a document has no frame to render, so the card shows
            // what it holds instead of spinning forever on a thumbnail that
            // cannot exist.
            VStack(spacing: 4) {
                Image(systemName: entry.contentKind.symbolName)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.75))
                Text(entry.contentKind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
        } else {
            imageThumbnail(entry)
        }
    }

    @ViewBuilder
    private func imageThumbnail(_ entry: ViewerSeriesEntry) -> some View {
        if let path = entry.firstFilePath {
            frameThumbnail(path)
        } else {
            Image(systemName: "square.dashed")
                .foregroundStyle(.white.opacity(0.2))
        }
    }

    @ViewBuilder
    private func frameThumbnail(_ path: String) -> some View {
        #if canImport(CoreGraphics)
        let key = FrameImageStore.Request(path: path).key
        if let image = thumbnails.image(forKey: key) {
            Image(decorative: image, scale: 1.0, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if thumbnails.didFail(key) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else {
            ProgressView().controlSize(.small)
        }
        #else
        Color.black
        #endif
    }

    // MARK: - Per-object previews

    /// Previews drawn on a multi-cine card before the strip resorts to a
    /// "+N" tile. Three keeps each preview wide enough to read; a series with
    /// more objects shows two and says how many the card cannot fit — the
    /// remaining loops are one click away, through the series itself.
    private static let objectStripCapacity = 3

    /// One preview per multi-frame object, side by side.
    @ViewBuilder
    private func objectStrip(_ entry: ViewerSeriesEntry) -> some View {
        let previews = entry.objectPreviews
        let shown = previews.count > Self.objectStripCapacity
            ? Array(previews.prefix(Self.objectStripCapacity - 1))
            : previews
        let hidden = previews.count - shown.count

        HStack(spacing: 4) {
            ForEach(shown) { preview in
                objectPreviewTile(entry, preview: preview)
            }
            if hidden > 0 {
                overflowTile(entry, hidden: hidden)
            }
        }
        .padding(4)
    }

    /// One object: its first frame over its loop length, opening that object.
    ///
    /// A button of its own, above the card's tap: clicking the 92-frame loop
    /// is a request to read that recording, and landing the reader on the
    /// series' first object instead would show them the other one.
    private func objectPreviewTile(
        _ entry: ViewerSeriesEntry, preview: SeriesObjectPreview
    ) -> some View {
        Button {
            viewModel.selectSeries(
                entry.seriesInstanceUID, startingAtFile: preview.filePath)
        } label: {
            VStack(spacing: 2) {
                Group {
                    // A clip's pixels are an encoded bit stream the still
                    // decoder cannot open, so its tile is the kind's own
                    // symbol. The frame count below still tells the two
                    // recordings apart, which is what the strip is for.
                    if entry.canRenderThumbnails {
                        frameThumbnail(preview.filePath)
                    } else {
                        Image(systemName: entry.contentKind.symbolName)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(preview.frameCountLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Object with \(preview.frameCountLabel). Show it in the selected tile.")
    }

    /// The objects the strip has no room for, still one click from view.
    private func overflowTile(_ entry: ViewerSeriesEntry, hidden: Int) -> some View {
        Button {
            viewModel.selectSeries(entry.seriesInstanceUID)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "square.stack")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                Text("+\(hidden)")
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(hidden) more objects. Show the series.")
    }

    #if canImport(CoreGraphics)
    private func refreshThumbnails() {
        thumbnails.refresh(viewModel.studySeries.flatMap { entry -> [FrameImageStore.Request] in
            // Only series whose objects the still decoder can actually open:
            // a video series draws film tiles and would otherwise queue one
            // doomed decode per clip.
            guard entry.canRenderThumbnails else { return [] }
            let previews = entry.objectPreviews
            if previews.count > 1 {
                // Only the strip's visible tiles: decoding every loop of a
                // long echo study for tiles that draw as "+N" is wasted disk.
                let shown = previews.count > Self.objectStripCapacity
                    ? previews.prefix(Self.objectStripCapacity - 1)
                    : previews.prefix(previews.count)
                return shown.map { FrameImageStore.Request(path: $0.filePath) }
            }
            return entry.firstFilePath.map { [FrameImageStore.Request(path: $0)] } ?? []
        })
    }
    #endif
}
#endif
