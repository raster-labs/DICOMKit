// FilmPreviewView.swift
// DICOMStudio
//
// DICOM Studio — what the film will actually look like, and where it is fixed.
//
// NEMA-verified: 2026a, checked 2026-10-05 — Border Density (2010,0100) and Empty Image Density (2010,0110) are
// drawn for the three forms PS3.3 2026a Table C.13-3 defines — BLACK, WHITE, and i in hundredths of OD (read
// as FilmComposer reads it); the sheet's shape comes from DICOMPrintKit's FilmSheet for the job's Film Size ID
// and Film Orientation; Trim YES draws the composer's corner marks. No other standard literal is carried.
//
// The preview exists to make spillover obvious: images beyond one layout's
// cells land on additional films, and the count is easy to get wrong when the
// layout is chosen by hand.
//
// It is also where a cell is adjusted. Clicking a cell focuses it; dragging runs
// the selected tool over it — window/level, zoom or pan. The tools are on a rail
// down the left, along with the locks that hold an adjustment together across
// cells, and everything that can be done to one cell is also on the film's own
// right-click menu. A mode belongs on the rail rather than in the menu: which
// tool is armed and which cells are linked have to be answerable at a glance,
// and a menu that only exists while it is open cannot answer them. The locks are
// echoed on the cells themselves, which is the sole thing drawn over a picture
// that the film will not carry — see the cell's overlay for why it earns that.
// Every edit is written back into the mark, which is what the
// print path reads, so a cell that looks right here prints that way. What is
// rendered is ``PrintViewModel/previewItems`` rather than the raw marks:
// job-wide settings (an explicit window, raw pixels) override a mark's own
// arrangement, and a preview ignoring that would lie.
//
// Because the tools live here, the picture is drawn from a GPU texture: a cell's
// zoom, pan, rotation, flip and inversion are the display shader's transform, so a
// drag re-draws a quad instead of re-rendering the frame. The transform is built
// from the *film's* composition rather than the viewer's — see `PrintCellDisplay`
// — so what the shader draws is what the printer will lay down. The film itself is
// still composed on the CPU, and must be: the two are byte-identical only because
// neither invents anything the other does not. The one exception is a cell turned
// to a free angle: the shader would fill the corners the film leaves black with
// the neighbouring anatomy, so those cells are drawn by the film's own renderer.

#if canImport(SwiftUI)
import SwiftUI
import DICOMCore
import DICOMPrintKit
import DICOMRenderKit

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct FilmPreviewView: View {
    @Bindable var viewModel: PrintViewModel

    #if canImport(CoreGraphics)
    /// Thumbnails of the marked frames. Owned here so the preview is
    /// self-contained, and keyed by mark so changing the layout — which
    /// re-renders this view constantly — never re-decodes a frame.
    ///
    /// The CPU path: what a cell shows when the GPU will not take it, and what
    /// fills the cell for the moment before its texture arrives.
    @State private var thumbnails = PrintThumbnailCache()
    #endif

    #if canImport(Metal)
    /// GPU textures for the cells of the film on screen.
    ///
    /// The preview is where the tools are used, so the picture is drawn from a
    /// texture and every tool step is the display shader's transform: a zoom, pan,
    /// rotation, flip or invert re-draws a quad and renders nothing. Only a
    /// window/level change produces a new texture, and that is one GPU dispatch.
    @State private var cellTextures = PrintCellTextureCache()
    #endif

    /// Live drag state, so a gesture applies deltas rather than absolutes.
    @State private var dragAnchor: CGSize = .zero

    /// The arrow being dragged out right now, if any.
    @State private var draftArrowID: UUID?

    /// The film on screen. One film is shown at a time and paged through, so the
    /// sheet being judged is drawn as large as the panel allows — a row of films
    /// side by side makes every one of them too small to judge.
    @State private var visibleFilm: Int = 0

    /// Patient identification for the marked files, for the annotation toggle.
    @State private var overlayTexts = PatientOverlayTextCache()

    private var plan: PrintPlan { viewModel.plan }
    private var items: [PrintSelectionItem] { viewModel.previewItems }

    /// The sentence over the film when a job-wide setting has taken the cell
    /// tools away, or `nil` while they all work.
    ///
    /// Raw pixels disable every adjustment (the film carries stored pixels by
    /// definition); the job-wide window disables only windowing. Drawing —
    /// text and arrows — survives both, so the notice says what still works
    /// rather than leaving the reader to find out drag by drag.
    private var toolsBlockedNotice: String? {
        if viewModel.sendRawPixels {
            return "Raw pixels are being sent: window/level, zoom, pan and invert "
                 + "are off for this job. Text and arrows still work. "
                 + "Switch off \u{201C}Send stored pixels unprocessed\u{201D} under More to edit cells."
        }
        if viewModel.useExplicitWindow {
            return "One window is set for the whole job, so cells cannot be "
                 + "windowed one by one. Zoom, pan, invert and drawing still work."
        }
        return nil
    }

    /// Why the armed pan tool is about to do nothing, said before the drag.
    ///
    /// A pan on film chooses which hidden part of the picture shows in the
    /// cell; a fitted, unzoomed cell hides nothing, so the drag has nowhere to
    /// go — the printer lays a fitted crop down centred, and the preview must
    /// not show an arrangement the film cannot carry. That is correct and
    /// utterly indistinguishable from a broken tool unless it is said out
    /// loud: the viewer's pan works unzoomed because it only scrolls the
    /// screen, so a reader arriving from the viewer has every reason to expect
    /// the same here. Shown only while pan is armed and *no* visible cell has
    /// travel; once any cell is zoomed — or the scaling crops — the tool works
    /// and the line would be noise.
    private var panHasNoTravelNotice: String? {
        guard viewModel.cellTool == .pan,
              toolsBlockedNotice == nil,
              !visibleItems.isEmpty,
              !visibleItems.contains(where: { viewModel.cellHasPanTravel($0) })
        else { return nil }
        return "Pan has nowhere to go yet: every cell is showing its whole image, "
             + "and film prints a fitted cell centred. Zoom into a cell first — "
             + "pan then chooses which part of the picture fills it. "
             + "(Fill scaling crops every cell, so there pan works unzoomed.)"
    }

    var body: some View {
        VStack(spacing: 0) {
            if plan.filmCount == 0 {
                ContentUnavailableView(
                    "Nothing marked",
                    systemImage: "square.dashed",
                    description: Text("Mark images in the viewer to place them on film.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Why a drag is about to do nothing, said before it is made.
                // Raw pixels and the job-wide window both turn cell edits into
                // writes the film ignores, and the tools then look broken —
                // "none of them work" — with the switch that did it sitting
                // folded away under More. The film must not accept drags it is
                // going to discard without saying which setting is discarding
                // them.
                if let notice = toolsBlockedNotice {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                        Text(notice)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12))
                }
                // Guidance, not a block — the tool is armed and healthy, it
                // just has nothing to act on yet — so it wears the quiet grey
                // of an explanation rather than the orange of a setting that
                // is discarding the reader's work.
                if let notice = panHasNoTravelNotice {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                        Text(notice)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.08))
                }
                // The rail is back beside the film. The right-click menu is a
                // fine place for the occasional command but a poor place for a
                // mode: it costs a click and a read to find out which tool is
                // armed and whether the cells are linked, and both are things
                // the eye should be able to answer while dragging. The menu
                // keeps everything it had, for the hand already on a cell.
                HStack(spacing: 0) {
                    toolRail
                    // The rail's own edge, not a hairline: it divides the
                    // controls from the picture being judged, which is the
                    // strongest boundary on the screen.
                    Rectangle()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 1)
                    filmStrip
                        // The film takes focus so the arrow keys walk cells and
                        // the tool shortcuts land here rather than in whatever
                        // text field was last touched.
                        .focusable()
                        .focusEffectDisabled()
                        // One handler for every key rather than one per key: the
                        // arrows mean two different things depending on ⌥, and
                        // separate per-key handlers cannot tell them apart — both
                        // would fire and the page would fight the focus.
                        .onKeyPress(phases: .down) { press in handleKeyPress(press) }
                        // The keys the rail's buttons also carry. Hidden buttons
                        // rather than `.keyboardShortcut` on the menu items,
                        // because a context menu only exists while it is open.
                        .background(toolShortcuts)
                }
            }

            // The plan summary is in the sheet's header; repeating it here cost
            // the film a line of height it can use for the picture.
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshOverlayTexts()
            // The range's fields start out saying what is marked, so opening the
            // control shows the run it covers rather than two zeroes.
            viewModel.clampImageRange()
        }
        .onChange(of: viewModel.showPatientIdentification) { _, _ in refreshOverlayTexts() }
        // Marks added or taken off move the bounds under the range: left
        // pointing outside them it would either print nothing or claim to be
        // filtering when it is not.
        .onChange(of: viewModel.selection.count) { _, _ in viewModel.clampImageRange() }
        // A film that no longer exists must not stay on screen: changing the
        // layout or clearing marks can drop the film being looked at.
        .onChange(of: plan.filmCount) { _, count in
            visibleFilm = min(visibleFilm, max(0, count - 1))
        }
        // Walking cells with the arrow keys runs off the end of a film, so the
        // page follows the focus rather than making the reader page by hand.
        .onChange(of: viewModel.focusedItemID) { _, _ in showFilmOfFocusedCell() }
        #if canImport(CoreGraphics)
        .onAppear { refreshCells() }
        // The cells the film is showing, whatever changed them: a page turn, a
        // mark added or adjusted — or a new layout, which is the one this used to
        // miss. Watching the film index and the mark list left a 2×2 turned into
        // a 4×4 with four pictures and twelve spinners: the same film index, the
        // same marks, twelve cells nobody had asked to render, and no way out of
        // it until some later event happened to refresh them.
        .onChange(of: visibleItems) { _, _ in
            refreshCells()
            // Identification is read per film for the same reason the textures
            // are: only what is on screen.
            refreshOverlayTexts()
        }
        // Every scaling mode draws from the GPU now — stretch included — so a
        // mode switch changes only the per-draw transform, not which cache
        // holds the cell. The refresh stays for the cells that are CPU-drawn
        // regardless (overlay planes, no Metal): their thumbnails follow the
        // mode, and this is what re-requests them.
        .onChange(of: viewModel.scalingMode) { _, _ in refreshCells() }
        .onChange(of: items) { _, _ in
            viewModel.pruneFocus()
            viewModel.pruneCellSelection()
            // Annotations belong to marks; a mark that has been taken off the film
            // must not leave its arrows behind to reappear on a later one.
            viewModel.pruneAnnotations()
            // Likewise the adopted saved views: a mark taken off the film must
            // not leave the inspector naming a view for a cell that is gone.
            viewModel.pruneAppliedSavedViews()
            refreshOverlayTexts()
            // Marks added since the sheet opened have not been offered their
            // images' saved views yet. Untouched cells only — see
            // `adoptSavedViewsWhereUntouched()`.
            //
            // Through `adoptSavedViews()` so this replaces any pass already
            // running instead of racing it. Adoption writes marks, a written
            // mark changes `items`, and a changed `items` arrives back here —
            // so a bare `Task` per change spawned a pass per cell per pass, and
            // the film preview locked up on a job of any size.
            viewModel.adoptSavedViews()
        }
        #endif
    }

    // MARK: - The tool rail

    /// Everything a cell can be worked on with, down the left of the film.
    ///
    /// Icon-only and narrow: the sheet is what the reader is judging, and every
    /// point the rail takes is a point the picture does not get. Names and keys
    /// live in the tooltips.
    private var toolRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(PrintViewModel.CellTool.allCases) { tool in
                    railButton(
                        symbol: tool.symbolName,
                        caption: Self.railCaption(for: tool),
                        isOn: viewModel.cellTool == tool,
                        help: Self.toolHelp(for: tool, viewModel: viewModel)
                    ) {
                        viewModel.cellTool = tool
                    }
                }

                // Straighten: the way back from a free-angle drag, on the
                // focused cell. Beside Invert rather than among the tools
                // because it arms nothing — it is one act on one cell, like
                // Invert, and the rail's first group is what a *drag* does.
                // Lit while the cell it would act on is actually askew, which is
                // also the only time it does anything.
                railButton(
                    // The straightening glyph the platform already uses for
                    // exactly this — not a half-filled square, which belongs to
                    // the invert family sitting right underneath it.
                    symbol: "rotate.left",
                    caption: "Straighten",
                    isOn: viewModel.focusedItemID.map { viewModel.isCellSkewed($0) } ?? false,
                    help: viewModel.focusedItemID == nil
                        ? "Straighten — squares a cell up to the nearest quarter turn. "
                        + "Click a cell first to choose which."
                        : "Straighten — squares the focused cell up to the nearest "
                        + "quarter turn, keeping its window and its crop.  (.)\n\n"
                        + "Worth doing before printing: a quarter turn is taken by moving "
                        + "pixels, while any other angle is resampled and leaves the "
                        + "corners of the picture outside the film's rectangle."
                ) {
                    if let id = viewModel.focusedItemID {
                        viewModel.straightenCell(forItemID: id)
                    }
                }
                .disabled(viewModel.focusedItemID.map { !viewModel.isCellSkewed($0) } ?? true)

                // Invert is a switch on the focused cell, not a drag, so it does
                // not arm anything — its lit state is the cell's, which is what
                // "is this picture inverted" is asking. The film's own polarity
                // is a job setting and lives in the settings column; this is one
                // picture being read the other way round.
                railButton(
                    symbol: "circle.righthalf.filled",
                    caption: "Invert",
                    isOn: viewModel.focusedItem?.presentation?.invert ?? false,
                    help: viewModel.focusedItem == nil
                        ? "Invert — swaps black and white in one cell. "
                        + "Click a cell first to choose which.\n\n"
                        + "For the whole film's polarity, use Medium under More."
                        : "Invert — swaps black and white in the focused cell, the way a "
                        + "chest film is read either way round.  (V)\n\n"
                        + (viewModel.cellSync.contains(.invert)
                           ? "The Lock Invert chip is shut, so the other cells turn with it."
                           : "Acts on this cell alone — shut Lock Invert to turn them together.")
                ) {
                    if let id = viewModel.focusedItemID {
                        viewModel.toggleCellInversion(forItemID: id)
                    }
                }
                .disabled(viewModel.focusedItemID == nil)

                // Headed, not a bare rule: the five chips below say only what
                // each lock holds, so the heading is what says they are locks.
                Self.railGroupHeader("Lock")

                // The locks. A closed one says this adjustment is held together
                // across the cells; an open one says each cell keeps its own.
                ForEach(PrintCellSyncOptions.catalog, id: \.title) { entry in
                    let isOn = viewModel.cellSync.contains(entry.option)
                    let blocked = entry.option == .window && viewModel.isCellWindowingOverridden
                    railButton(
                        symbol: isOn ? "lock.fill" : "lock.open",
                        caption: Self.railCaption(for: entry.option),
                        isOn: isOn && !blocked,
                        help: blocked
                            ? (viewModel.cellWindowingBlockedReason ?? "")
                            : Self.lockHelp(for: entry.option, title: entry.title,
                                            isOn: isOn, viewModel: viewModel)
                    ) {
                        viewModel.toggleSyncFromUI(entry.option)
                    }
                    .disabled(blocked)
                }

                // How far a locked adjustment reaches. Under the locks because
                // it is meaningless without one.
                Menu {
                    ForEach(PrintCellSyncScope.allCases) { scope in
                        Button {
                            viewModel.cellSyncScope = scope
                        } label: {
                            Label(scope.title,
                                  systemImage: viewModel.cellSyncScope == scope ? "checkmark" : "")
                        }
                    }
                } label: {
                    // Dressed as a lit rail chip while a lock is shut: the
                    // scope then governs what the next drag reaches, and that
                    // has to read as loudly as the tool itself. Flat and grey
                    // only while no lock gives it anything to govern.
                    let scopeActive = viewModel.isCellSyncActive
                    VStack(spacing: 3) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right.square")
                            .font(.system(size: 17, weight: scopeActive ? .semibold : .regular))
                        Text(Self.scopeCaption(viewModel.cellSyncScope))
                            .font(.system(size: 10, weight: scopeActive ? .semibold : .regular))
                    }
                    .frame(width: Self.railWidth - 8, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(scopeActive ? Color.accentColor : Color.clear)
                            .shadow(color: scopeActive ? Color.accentColor.opacity(0.35) : .clear,
                                    radius: 3, y: 1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(scopeActive ? Color.accentColor : Color.clear, lineWidth: 1))
                    .contentShape(Rectangle())
                    .foregroundStyle(scopeActive ? Color.white : Color.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: Self.railWidth - 8)
                .disabled(!viewModel.isCellSyncActive)
                // Disabled until a lock is shut, which is precisely the state
                // the second half of this string explains. See `railTooltip`.
                .railTooltip(viewModel.isCellSyncActive
                      ? "How far a shut lock reaches — now: \(viewModel.cellSyncScope.title).  (S)\n\n"
                      + "Series keeps a locked adjustment to cells from the same series, "
                      + "so a film mixing two studies does not re-window both at once. "
                      + "Film reaches every cell on the sheet.\n\n"
                      + "Never past the sheet you are looking at, either way."
                      : "How far a shut lock reaches. Shut a lock above to use it.")

                Self.railSeparator()

                // Picking cells by hand, beside the locks that are its
                // alternative — and showing the count, because how many cells
                // the next drag moves is the thing a selection has to answer at
                // a glance. Lit while a selection is in force, since that is
                // also when the locks are standing aside.
                railButton(
                    symbol: viewModel.hasCellSelection
                    ? "checkmark.circle.fill" : "checkmark.circle",
                    caption: viewModel.hasCellSelection
                    ? "\(viewModel.selectedItemIDs.count) Cells" : "Pick",
                    isOn: viewModel.hasCellSelection,
                    help: viewModel.hasCellSelection
                    ? "Picked cells — tools act on exactly these "
                    + "\(viewModel.selectedItemIDs.count), and the locks stand aside "
                    + "while they are picked.\n\n"
                    + "⌘-click a cell to add or remove it. Click this, press A or ⎋, or "
                    + "click any unpicked cell to clear the lot.  (A, ⎋)"
                    : "Pick cells out by hand, for when you want a few adjusted together "
                    + "but not the whole series.\n\n"
                    + "⌘-click cells to pick them, or press A to take the focused cell "
                    + "and every cell after it on this sheet. A picked set outranks the "
                    + "locks.  (A)"
                ) {
                    if viewModel.hasCellSelection {
                        viewModel.clearCellSelection()
                    } else {
                        viewModel.selectSucceedingCellsOnFilm()
                    }
                }
                .disabled(!viewModel.hasCellSelection && viewModel.focusedItemID == nil)

            }
            .padding(.vertical, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The undo group is pinned below the scroll rather than carried along at
        // the end of it. It was the last thing in a rail of nineteen chips, so on
        // any window short of full height it sat below the fold: a reader looking
        // for the way back out of an arrangement found the rail's *tools*, which
        // is the opposite of reassuring. What undoes the work is the one group
        // that must never need scrolling to.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                // Headed for the same reason the locks are: the four chips
                // below distinguish themselves by scope — this cell or all of
                // them — and the heading carries the word they would otherwise
                // each repeat.
                Self.railGroupHeader("Undo")
                undoRail
            }
            .padding(.bottom, 8)
            .background(.bar)
        }
        .frame(width: Self.railWidth)
    }

    /// The way back out: revert to what the viewer showed, or reset to the
    /// untouched frame — each in both scopes, this cell and the whole film.
    ///
    /// The unscoped chip is the focused cell, and only the sheet-wide one says
    /// "All". Captioning the pair "Revert Cell" / "Revert All" made "Cell" and
    /// "All" the words the eye had to compare, which are equally short and
    /// equally unremarkable; leaving the common case bare makes "All" the only
    /// mark in the group, which is the thing worth being sure about before
    /// clicking. The tooltips name both scopes in full.
    ///
    /// Revert first, and it is the one a reader usually wants. The print screen
    /// is where a film is *composed*, and the thing that goes wrong is the
    /// composing: a lock shut by accident carries one drag across every cell.
    /// Revert takes back exactly that, leaving the window and arrangement the
    /// reader set up in the viewer — which they did not do here, and did not ask
    /// to lose. Reset goes further and throws that away too, which is right only
    /// when the viewer's own arrangement is what is unwanted.
    @ViewBuilder
    private var undoRail: some View {
        railButton(symbol: "arrow.uturn.backward", caption: "Revert",
                   isOn: false,
                   help: "Revert Cell — puts the focused cell back to the image as it "
                   + "came from the viewer: the window, zoom, rotation and flip you "
                   + "had set on screen.\n\n"
                   + "Takes back only what was done here on the print screen. Text and "
                   + "arrows drawn on the image are left alone. To go further and drop "
                   + "the viewer's arrangement as well, use Reset Cell.") {
            viewModel.revertFocusedCell()
        }
        .disabled(viewModel.focusedItemID.map { !viewModel.isCellAdjusted($0) } ?? true)

        railButton(symbol: "arrow.uturn.backward.circle", caption: "Revert All",
                   isOn: false,
                   help: "Revert All — puts every cell on every sheet back to the images "
                   + "as they came from the viewer.\n\n"
                   + "The way out when a shut lock has carried one drag across the whole "
                   + "film. Job settings — printer, film size, layout — and anything "
                   + "drawn are left alone.") {
            viewModel.revertAllCells()
        }
        .disabled(!viewModel.hasAdjustedCells)

        railButton(symbol: "arrow.counterclockwise", caption: "Reset",
                   isOn: false,
                   help: "Reset Cell — puts the focused cell back to the untouched "
                   + "frame: the image's own window, no zoom, no pan, not "
                   + "inverted.  (0)\n\n"
                   + "Text and arrows drawn on it are left alone. To keep the window and "
                   + "arrangement you had set in the viewer and undo only what was done "
                   + "here, use Revert Cell.") {
            viewModel.resetFocusedCell()
        }
        .disabled(viewModel.focusedItem.map { !viewModel.isCellEdited($0) } ?? true)

        railButton(symbol: "arrow.counterclockwise.circle", caption: "Reset All",
                   isOn: false,
                   help: "Reset All — puts every cell on every sheet back to the "
                   + "untouched frame, dropping the viewer's window and arrangement "
                   + "too.  (\u{21E7}0)\n\n"
                   + "Job settings — printer, film size, layout — and anything drawn are "
                   + "left alone.") {
            viewModel.resetAllCells()
        }
        .disabled(!viewModel.hasEditedCells)
    }

    /// One rail button: a glyph, a word under it, and a tinted background when
    /// it is the one in force.
    private func railButton(
        symbol: String, caption: String, isOn: Bool, help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: isOn ? .semibold : .regular))
                // Up to two lines, for the few captions that need a second —
                // the rest are one word and are unaffected. The leading used to
                // be set to -2 to fit "Lock" over a noun inside the 44-point
                // chip, which crushed the two lines into each other; now that
                // the repeated word lives on the group heading instead, the
                // captions that remain fit at natural leading.
                Text(caption)
                    .font(.system(size: 10, weight: isOn ? .semibold : .regular))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: Self.railWidth - 8, height: 44)
            // The armed tool is filled, not merely tinted. A wash of accent
            // behind one of six glyphs is easy to miss on a bright sheet, and
            // "which tool is this drag about to run" is the question the rail
            // exists to answer — so the selected one reads as a solid chip with
            // the film's own contrast, the way a pressed key looks pressed.
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOn ? Color.accentColor : Color.clear)
                    .shadow(color: isOn ? Color.accentColor.opacity(0.35) : .clear,
                            radius: 3, y: 1))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isOn ? Color.accentColor : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? Color.white : Color.secondary)
        // Outside the chip's own armed fill, so hover reads on an armed chip
        // as well as an idle one.
        .interactiveControl(cornerRadius: 7, horizontal: 2, vertical: 2)
        .railTooltip(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// A tool's tooltip: the gesture, what it changes, its key — and, last, how
    /// many cells the next drag will actually move.
    ///
    /// The reach is the part worth spelling out. Which tool is armed is on the
    /// rail and now on the pointer, but "and it will do that to six cells,
    /// because the W/L lock is shut" is nowhere on screen except as three small
    /// badges, and it is the half of the sentence that ruins a film. It is read
    /// from the same rules the drag itself uses, so it cannot drift from them.
    private static func toolHelp(
        for tool: PrintViewModel.CellTool, viewModel: PrintViewModel
    ) -> String {
        let key = shortcut(for: tool).uppercased()
        let body: String
        switch tool {
        case .window:
            body = "Window/Level — drag across a cell to widen or narrow the greys, "
                 + "up and down to brighten or darken."
        case .zoom:
            body = "Zoom — drag up a cell to enlarge, down to shrink. "
                 + "The scroll wheel zooms the cell under the pointer with any tool armed."
        case .pan:
            body = "Pan — drag to move the picture inside its cell. "
                 + "Only travels as far as there is image hidden outside the cell, "
                 + "so on a fitted film zoom in first; under Fill scaling it "
                 + "works unzoomed."
        case .rotate:
            body = "Rotate — drag around the middle of a cell and the picture "
                 + "follows the pointer, either way, through the full circle. "
                 + "Straighten on the rail squares a cell back up to the nearest "
                 + "quarter turn."
        case .text:
            body = "Text — click a cell where the note should go, then type. "
                 + "Drag its handle to move it; Delete removes the selected note."
        case .arrow:
            body = "Arrow — drag across a cell from the tail to the head. "
                 + "Too short a drag is treated as a slip and no arrow is left."
        }
        return "\(body)  (\(key))\n\n\(reachSentence(for: tool, viewModel: viewModel))"
    }

    /// A lock's tooltip: what it holds together, which way it is now, and — for
    /// the two that are not copied the same way — how the value travels.
    ///
    /// The last part earns its line because the difference is visible and
    /// otherwise inexplicable: shut the zoom lock and every cell shows the same
    /// magnification, shut the window lock and they keep different windows that
    /// all widen together. A reader who expects the first and gets the second
    /// concludes the lock is broken.
    private static func lockHelp(
        for option: PrintCellSyncOptions, title: String,
        isOn: Bool, viewModel: PrintViewModel
    ) -> String {
        let scope = viewModel.cellSyncScope == .sameSeries
            ? "in the same series" : "on this film"
        let what: String
        switch option {
        case .window:
            what = "Windowing travels as a change, not as a value: every cell widens or "
                 + "brightens by the same amount and keeps its own window, so a film "
                 + "mixing CT and ultrasound stays readable."
        case .zoomPan:
            what = "Zoom and pan travel as values: the cells end up at the same "
                 + "magnification over the same part of the picture."
        case .rotate:
            what = "The angle travels as a value, not as a turn: the cells end up "
                 + "standing the same way round, whatever angle each of them "
                 + "started at. Flip is never carried — which side of the patient "
                 + "is which is a fact about the image, not a way of looking at "
                 + "the film."
        default:
            what = "Inverting one cell inverts the others."
        }
        let key = "\u{21E7}\(String(shortcut(for: option)).uppercased())"
        let state = isOn
            ? "Shut: adjusting one cell also adjusts the cells \(scope). Click to open it "
            + "and work on one cell alone."
            : "Open: each cell keeps its own. Click to shut it."
        return "Lock \(title).  (\(key))\n\n\(state)\n\n\(what)"
    }

    /// What the next drag with this tool reaches, in plain words.
    private static func reachSentence(
        for tool: PrintViewModel.CellTool, viewModel: PrintViewModel
    ) -> String {
        // Drawing lands on the cell it is drawn on, whatever is locked: a note
        // is about one picture.
        if tool.isDrawing { return "Draws on the one cell you click, always." }

        if tool == .window, viewModel.isCellWindowingOverridden {
            return viewModel.cellWindowingBlockedReason
                ?? "Windowing is set for the whole film, so cells cannot be windowed one by one."
        }

        if viewModel.hasCellSelection {
            let count = viewModel.selectedItemIDs.count
            return "Acts on the \(count) picked \(count == 1 ? "cell" : "cells"); "
                 + "the locks stand aside while a selection is in force."
        }

        // Each tool asks about its own lock. Zoom and pan share one, so the
        // remaining geometry tools fall to it.
        let option: PrintCellSyncOptions
        switch tool {
        case .window: option = .window
        case .rotate: option = .rotate
        default:      option = .zoomPan
        }
        guard viewModel.cellSync.contains(option) else {
            return "Acts on the one cell you drag — its lock is open."
        }
        return "Its lock is shut, so it also moves the other cells "
             + "\(viewModel.cellSyncScope == .sameSeries ? "in the same series" : "on this film")."
    }

    #if os(macOS)
    /// The pointer's shape over a film cell, for the tool that is armed.
    ///
    /// The rail says which tool is armed, but the rail is at the edge of the
    /// screen and the hand is on the film — and the cost of being wrong is a
    /// drag that has already windowed a cell you meant to pan. The pointer is
    /// the one part of the screen that is guaranteed to be where the reader is
    /// looking when the drag starts, which is what makes it worth changing.
    ///
    /// Only over a cell with a picture in it: an empty cell has nothing for any
    /// of these to act on, and a magnifier over it promises otherwise.
    /// - Parameter isDragging: whether the tool's drag is running, so the pointer
    ///   can confirm that the gesture took hold. The pan drag sets its own closed
    ///   hand from inside `CellInteraction`, where the gesture lives; this
    ///   parameter is what the other tools would use, and the resting shapes are
    ///   what the overlay asks for.
    @MainActor
    private static func toolCursor(
        for tool: PrintViewModel.CellTool, isDragging: Bool = false
    ) -> NSCursor {
        switch tool {
        case .window, .zoom, .rotate:
            // The tool's own glyph, drawn as the pointer — the same symbol the
            // rail button and the viewer's toolbar carry, so the pointer, the
            // rail and the viewer all name the armed tool with one picture.
            // Windowing a cell and windowing an image are the same act, so
            // they show the same shape on both screens.
            return ToolSymbolCursor.cursor(
                symbolName: symbolName(for: tool, isDragging: isDragging),
                fallback: tool == .zoom ? .zoomIn : .crosshair)
        case .pan:
            // The system pair: open before the drag, closed while the cell's
            // picture is actually being carried.
            return isDragging ? .closedHand : .openHand
        case .text:
            return .iBeam
        case .arrow:
            // Drawing a new arrow, not adjusting the picture — the crosshair is
            // the shape for placing a thing at a point, and it is what every
            // other drawing tool on the platform uses.
            return .crosshair
        }
    }

    /// The symbol a cell tool's pointer draws, resting and mid-drag.
    private static func symbolName(
        for tool: PrintViewModel.CellTool, isDragging: Bool
    ) -> String {
        switch tool {
        case .window:
            return isDragging ? "sun.max.fill" : "sun.max"
        case .zoom:
            return isDragging ? "magnifyingglass.circle.fill" : "magnifyingglass"
        case .rotate:
            return isDragging
                ? "arrow.triangle.2.circlepath.circle.fill"
                : "arrow.triangle.2.circlepath"
        default:
            return tool.symbolName
        }
    }
    #endif

    /// A rule between two groups of rail buttons.
    ///
    /// Heavier than a plain `Divider`, which at one hairline of separator colour
    /// all but vanishes against the rail — and the rail's groups are the thing
    /// that makes it readable: what a drag does, what travels to the other
    /// cells, what the tools act on, what puts it all back. Without a rule the
    /// eye reads eleven buttons in a column and has to remember the grouping
    /// instead of seeing it.
    private static func railSeparator() -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.45))
            .frame(height: 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
    }

    /// A rule with the group's name on it.
    ///
    /// For the groups whose chips would otherwise each repeat the same word.
    /// The locks are the case that forced it: five chips reading "Lock W/L",
    /// "Lock Zoom+Pan", "Lock Rotate", "Lock Invert" spend their
    /// wide first line on the word that is identical down the column and their
    /// narrow second line on the noun that actually distinguishes them — so
    /// "Zoom+Pan", the longest string in the rail, was the one being shrunk.
    ///
    /// Saying "Lock" once, as a heading, buys every chip its full width for the
    /// noun. The prefix was there to stop the reader confusing the lock chips
    /// with the tool chips a few points above (two saying "Invert", two saying
    /// "W/L"); a heading over the group does that job better than a prefix on
    /// each, because it also says the five belong together.
    private static func railGroupHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.secondary.opacity(0.45))
                .frame(height: 1)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle()
                .fill(Color.secondary.opacity(0.45))
                .frame(height: 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .accessibilityElement()
        .accessibilityLabel("\(title) group")
    }

    /// The word under a tool's glyph — short enough for the rail's width.
    private static func railCaption(for tool: PrintViewModel.CellTool) -> String {
        switch tool {
        case .window: return "W/L"
        case .zoom:   return "Zoom"
        case .pan:    return "Pan"
        case .rotate: return "Rotate"
        case .text:   return "Text"
        case .arrow:  return "Arrow"
        }
    }

    /// The word under a lock.
    ///
    /// The noun alone: what the lock holds together. The word "Lock" is said
    /// once, on the group's heading rule (see ``railGroupHeader(_:)``), rather
    /// than five times down the column.
    ///
    /// It used to be prefixed on each chip and wrapped to two lines, to stop a
    /// reader confusing these with the tool chips a few points above — two
    /// reading "Invert", two reading "W/L". That reasoning holds; the execution
    /// was what failed. The prefix took the chip's wide first line and left the
    /// distinguishing noun on the narrow second, so "Zoom+Pan" — the longest
    /// caption in the rail — shrank to near-illegibility while the identical
    /// word above it sat at full size. One line, full width, under a heading
    /// that names the group.
    ///
    /// "Zoom + Pan" with spaces: the chip has the width for it now, and the
    /// spaced form breaks across the pair cleanly if it ever has to wrap.
    private static func railCaption(for option: PrintCellSyncOptions) -> String {
        if option == .zoomPan { return "Zoom + Pan" }
        if option == .window { return "W/L" }
        if option == .rotate { return "Rotate" }
        return "Invert"
    }

    private static func scopeCaption(_ scope: PrintCellSyncScope) -> String {
        switch scope {
        case .sameSeries: return "Series"
        case .thisFilm: return "Film"
        }
    }

    /// Wide enough for the longest caption at the rail's type size — "Zoom+Pan"
    /// — without it shrinking to fit, which is what a caption too small to read
    /// at a glance costs the rail its point.
    private static let railWidth: CGFloat = 68

    private var filmStrip: some View {
        // The film is sized from the space actually available rather than a
        // fixed thumbnail size, so the preview reads as a sheet of film instead
        // of a row of stamps.
        GeometryReader { geo in
            let sheet = sheetGeometry(in: geo.size)

            ZStack {
                filmSheet(filmIndex: currentFilm, width: sheet.width, height: sheet.height)

                // The arrows float over the slack beside the sheet rather than
                // taking a column out of it. A portrait sheet in a wide panel
                // has that slack to spare, and charging the film 68 points for
                // two chevrons standing in empty space made the picture smaller
                // for nothing. When the panel is tight enough that there is no
                // slack, `sheetGeometry` gives them their gutter back and the
                // sheet fits in what is left — the arrows never sit over a cell.
                if plan.filmCount > 1 {
                    HStack(spacing: 0) {
                        pagingButton(step: -1, symbol: "chevron.left")
                        Spacer(minLength: 0)
                        pagingButton(step: 1, symbol: "chevron.right")
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// How big the sheet is drawn, and whether the page arrows need a gutter of
    /// their own.
    ///
    /// One fit against the whole panel first: the sheet takes whichever of the
    /// two dimensions runs out first, so it fills the space in *both* directions
    /// rather than being sized by height alone and leaving the width empty. Only
    /// if that leaves the arrows nowhere to stand is it fitted again inside a
    /// narrower width.
    private func sheetGeometry(in panel: CGSize) -> (width: CGFloat, height: CGFloat) {
        let aspect = max(sheetAspect, 0.01)
        let availableHeight = panel.height - captionAllowance
        let fullWidth = max(0, panel.width - Self.sideAllowance)

        func fitted(inWidth width: CGFloat) -> (width: CGFloat, height: CGFloat) {
            let height = max(Self.minimumSheetHeight, min(availableHeight, width / aspect))
            return (height * aspect, height)
        }

        let full = fitted(inWidth: fullWidth)
        guard plan.filmCount > 1, fullWidth - full.width < pagingAllowance else { return full }
        return fitted(inWidth: max(0, fullWidth - pagingAllowance))
    }

    /// The film currently on screen, clamped to the plan — the count can shrink
    /// under us between a page turn and the next redraw.
    private var currentFilm: Int {
        min(max(0, visibleFilm), max(0, plan.filmCount - 1))
    }

    /// The marks on the film being shown.
    private var visibleItems: [PrintSelectionItem] {
        guard plan.filmCount > 0 else { return [] }
        let range = plan.imageIndices(onFilm: currentFilm)
        return range.compactMap { items.indices.contains($0) ? items[$0] : nil }
    }

    #if canImport(CoreGraphics)
    /// Marks that still need a CPU thumbnail: the ones the GPU is not drawing.
    ///
    /// A cell with a texture is deliberately excluded, and so is dropped from the
    /// thumbnail cache. That is what makes a tool drag free here — the CPU key
    /// includes the arrangement, so leaving a GPU-drawn cell in that cache would
    /// re-render it on every mouse delta the shader was about to handle for
    /// nothing, which is the cost this path exists to remove.
    private var itemsNeedingThumbnail: [PrintSelectionItem] {
        #if canImport(Metal)
        guard PrintCellTextureCache.isAvailable else { return visibleItems }
        return visibleItems.filter { drawnTexture(for: $0) == nil }
        #else
        return visibleItems
        #endif
    }

    #if canImport(Metal)
    /// The texture a cell is actually drawn from, if it is drawn from one.
    ///
    /// Every arrangement takes the GPU now. Freely rotated cells used to fall
    /// back to the CPU — the shader drew the whole frame, so the corners the
    /// film leaves black came out as neighbouring anatomy — but the fragment
    /// shader masks outside the film's crop today, so a rotate drag on any cell
    /// is one matrix update rather than a CPU re-render per mouse delta. Stretch
    /// likewise: the transform stretches the composed picture to the cell.
    /// What still says no is the texture cache itself — overlay-plane frames
    /// and machines without Metal — and those cells keep the CPU thumbnail.
    private func drawnTexture(for item: PrintSelectionItem) -> DisplayFrameTexture? {
        cellTextures.texture(for: item)
    }
    #endif

    /// Brings both cell caches up to date with the film on screen.
    private func refreshCells() {
        #if canImport(Metal)
        cellTextures.refresh(for: visibleItems)
        #endif
        thumbnails.refresh(for: itemsNeedingThumbnail)
    }
    #endif

    /// One page turn: an arrow either side of the film, disabled at the ends.
    ///
    /// Shown only when there is more than one film — an invisible gutter kept for
    /// symmetry is width the single film being judged could have used.
    @ViewBuilder
    private func pagingButton(step: Int, symbol: String) -> some View {
        let isEnabled = canTurnPage(by: step)
        Button {
            turnPage(by: step)
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: Self.pagingButtonWidth, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.3))
        .interactiveControl(cornerRadius: 6, horizontal: 0, vertical: 0,
                            isEnabled: isEnabled)
        .disabled(!isEnabled)
        .railTooltip(step < 0 ? "Previous film (⌥←)" : "Next film (⌥→)")
        .accessibilityLabel(step < 0 ? "Previous film" : "Next film")
    }

    private func canTurnPage(by step: Int) -> Bool {
        let target = currentFilm + step
        return plan.filmCount > 1 && target >= 0 && target < plan.filmCount
    }

    /// Turns to the next or previous film, if there is one.
    @discardableResult
    private func turnPage(by step: Int) -> Bool {
        guard canTurnPage(by: step) else { return false }
        let target = currentFilm + step
        visibleFilm = target
        // The focus belongs to a cell on the film that was showing, and a ring on
        // a film nobody can see is a lie about what the next drag will hit.
        if let focusedID = viewModel.focusedItemID, film(ofItemID: focusedID) != target {
            viewModel.focusCell(nil)
        }
        return true
    }

    /// Which film a mark sits on, by its position in film order.
    ///
    /// Position in `items` — the marks the films actually carry — not in the
    /// raw selection: an active image range filters marks out of the layout
    /// while leaving them in the selection, and an index into the wrong list
    /// paged the preview to the wrong sheet.
    private func film(ofItemID itemID: String) -> Int? {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              plan.cellsPerFilm > 0 else { return nil }
        return index / plan.cellsPerFilm
    }

    /// Brings the film holding the focused cell on screen.
    private func showFilmOfFocusedCell() {
        guard let focusedID = viewModel.focusedItemID,
              let film = film(ofItemID: focusedID), film != visibleFilm else { return }
        visibleFilm = film
    }

    /// Reads identification for the film on screen, and only while it is shown.
    ///
    /// The film on screen rather than the whole selection: a hundred marks is a
    /// hundred files read and parsed in full, and they compete for the same disk
    /// and the same cores as the decodes the cells are waiting on. The next film
    /// is read when it is turned to, which is the moment its text is needed.
    private func refreshOverlayTexts() {
        overlayTexts.refresh(
            for: viewModel.showPatientIdentification ? visibleItems.map(\.filePath) : [])
    }

    /// The film's own keys: arrows walk cells, ⌥-arrows turn the page, esc lets
    /// the cell go. Everything else is left for the tool buttons' own shortcuts.
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let key = press.key.character
        let isOption = press.modifiers.contains(.option)

        switch key {
        case KeyEquivalent.leftArrow.character:
            if isOption { return turnPage(by: -1) ? .handled : .ignored }
            return moveFocus(by: -1) ? .handled : .ignored
        case KeyEquivalent.rightArrow.character:
            if isOption { return turnPage(by: 1) ? .handled : .ignored }
            return moveFocus(by: 1) ? .handled : .ignored
        case KeyEquivalent.upArrow.character:
            return moveFocusVertically(-1) ? .handled : .ignored
        case KeyEquivalent.downArrow.character:
            return moveFocusVertically(1) ? .handled : .ignored
        case KeyEquivalent.delete.character:
            // Innermost first, as esc does below: an annotation is a thing drawn
            // *on* a cell, so delete takes that before it takes the cell it was
            // drawn on. With nothing drawn selected, the cells go — the picked
            // ones, or the focused one — and the rest of the film shuffles up.
            if viewModel.removeSelectedAnnotation() { return .handled }
            return viewModel.removeSelectedCells() > 0 ? .handled : .ignored
        case KeyEquivalent.escape.character:
            // The annotation, then the hand-picked cells, then the focus — esc
            // lets go of one thing at a time, innermost first, as it does
            // everywhere else. The selection outranks the focus because losing
            // it silently is what makes the next drag reach cells nobody meant.
            if viewModel.selectedAnnotationID != nil {
                viewModel.selectAnnotation(nil)
                return .handled
            }
            if viewModel.hasCellSelection {
                viewModel.clearCellSelection()
                return .handled
            }
            guard viewModel.focusedItemID != nil else { return .ignored }
            viewModel.focusCell(nil)
            return .handled
        default:
            return .ignored
        }
    }

    /// Moves the focus along the film by a number of cells.
    ///
    /// Cells are film order, so ±1 steps along a row and ±columns steps down a
    /// column, across film boundaries — which is how the marks are ordered
    /// anyway. Nothing focused yet means "start at the first cell".
    @discardableResult
    private func moveFocus(by offset: Int) -> Bool {
        // Walked over the marks the films actually carry: with an image range
        // in force the raw selection still holds the filtered-out marks, and
        // stepping through those focused cells that are not on any sheet.
        let all = items
        guard !all.isEmpty else { return false }
        guard let focusedID = viewModel.focusedItemID,
              let current = all.firstIndex(where: { $0.id == focusedID }) else {
            viewModel.focusCell(all[0].id)
            return true
        }
        let target = current + offset
        guard all.indices.contains(target) else { return false }
        viewModel.focusCell(all[target].id)
        return true
    }

    /// Moves the focus one cell up or down, by where the cells actually are.
    ///
    /// A film's rows need not hold the same number of images — `ROW\1,2` is one
    /// over two — so "the cell above" is a question about geometry and not
    /// arithmetic on a column count. Off the top or bottom of a film the walk
    /// carries on to the next one, entering the band the eye would come to.
    @discardableResult
    private func moveFocusVertically(_ direction: Int) -> Bool {
        // A nominal sheet: only the proportions of the cells matter here.
        let cells = sheetCells(width: 1000 * sheetAspect, height: 1000)
        guard let current = focusedCell(among: cells) else {
            return moveFocus(by: direction)
        }
        let centerX = current.x + current.width / 2
        let centerY = current.y + current.height / 2

        /// The cell nearest this one in the direction travelled: the closest band
        /// first, then the cell in it whose horizontal centre is nearest.
        func nearest(_ pool: [FilmCell]) -> FilmCell? {
            pool.min { a, b in
                let dyA = abs((a.y + a.height / 2) - centerY)
                let dyB = abs((b.y + b.height / 2) - centerY)
                if abs(dyA - dyB) > 0.5 { return dyA < dyB }
                return abs((a.x + a.width / 2) - centerX) < abs((b.x + b.width / 2) - centerX)
            }
        }

        let ahead = cells.filter { cell in
            let y = cell.y + cell.height / 2
            return direction > 0 ? y > centerY + 0.5 : y < centerY - 0.5
        }
        if let target = nearest(ahead) {
            return moveFocus(by: target.position - current.position)
        }

        // At the edge of this film: onto the next one, entering from its far side.
        guard let edge = direction > 0
                ? cells.map({ $0.y + $0.height / 2 }).min()
                : cells.map({ $0.y + $0.height / 2 }).max() else { return false }
        let entryBand = cells.filter { abs(($0.y + $0.height / 2) - edge) < 0.5 }
        guard let target = entryBand.min(by: {
            abs(($0.x + $0.width / 2) - centerX) < abs(($1.x + $1.width / 2) - centerX)
        }) else { return false }
        return moveFocus(by: direction * plan.cellsPerFilm + target.position - current.position)
    }

    /// The cell the focused mark sits in, by its position on its own film.
    private func focusedCell(among cells: [FilmCell]) -> FilmCell? {
        guard plan.cellsPerFilm > 0,
              let focusedID = viewModel.focusedItemID,
              let index = items.firstIndex(where: { $0.id == focusedID })
        else { return nil }
        let position = index % plan.cellsPerFilm + 1
        return cells.first { $0.position == position }
    }

    // MARK: - Tools

    /// A key for every control on the tool rail.
    ///
    /// Zero-sized buttons behind the film: a context menu only exists while it
    /// is open, so its items cannot own the keys, and a shortcut is delivered
    /// wherever the print screen has focus rather than only while the film
    /// holds it.
    ///
    /// The whole rail, in one place:
    ///
    /// | Key | Does |
    /// |-----|------|
    /// | `W` `Z` `P` `E` `T` `R` | arm W/L, Zoom, Pan, Rotate, Text, Arrow |
    /// | `⇧W` `⇧Z` `⇧E` `⇧V` | shut or open the W/L, Zoom & Pan, Rotate, Invert locks |
    /// | `S` | swap a shut lock's reach between Series and Film |
    /// | `A` | pick the run of cells from the focused one, or let a picked set go |
    /// | `V` `.` | invert the focused cell, straighten it back to square |
    /// | `[` `]` | mirror the focused cell left-to-right, top-to-bottom |
    /// | `I` | show or hide the identification caption |
    /// | `0` `⇧0` | reset the focused cell, reset every cell |
    /// | `⌫` | delete the selected annotation, else the selected cells |
    ///
    /// A lock's key is its tool's key shifted, which is the same pairing the
    /// rail shows by ordering the locks to match the tools.
    ///
    /// Arrow keys, `⌥`-arrows and `⎋` are the film's own — they need to know
    /// where the focus is, so they are handled in ``handleKeyPress(_:)``.
    private var toolShortcuts: some View {
        ZStack {
            ForEach(PrintViewModel.CellTool.allCases) { tool in
                Button("") { viewModel.cellTool = tool }
                    .keyboardShortcut(KeyEquivalent(Self.shortcut(for: tool)), modifiers: [])
            }
            // The locks, on their tool's own key shifted. Every control on the
            // rail carries a key now: the rail is worked from the keyboard
            // precisely while the other hand is on the film, and a control that
            // needs a trip to the edge of the screen is one that gets skipped.
            ForEach(PrintCellSyncOptions.catalog, id: \.title) { entry in
                Button("") { viewModel.toggleSyncFromUI(entry.option) }
                    .keyboardShortcut(KeyEquivalent(Self.shortcut(for: entry.option)),
                                      modifiers: [.shift])
            }

            // How far a shut lock reaches, cycled rather than picked: there are
            // two scopes, so a key that swaps them is the whole menu.
            Button("") {
                guard viewModel.isCellSyncActive else { return }
                viewModel.cellSyncScope =
                    viewModel.cellSyncScope == .sameSeries ? .thisFilm : .sameSeries
            }
            .keyboardShortcut("s", modifiers: [])

            // Pick: the same button the rail shows — take the run of cells from
            // the focused one, or let a picked set go.
            Button("") {
                if viewModel.hasCellSelection {
                    viewModel.clearCellSelection()
                } else {
                    viewModel.selectSucceedingCellsOnFilm()
                }
            }
            .keyboardShortcut("a", modifiers: [])

            Button("") { viewModel.showPatientIdentification.toggle() }
                .keyboardShortcut("i", modifiers: [])
            Button("") {
                if let id = viewModel.focusedItemID {
                    viewModel.toggleCellInversion(forItemID: id)
                }
            }
            .keyboardShortcut("v", modifiers: [])
            // Straighten, on its own key rather than the rotate lock's: ⇧E
            // shuts that lock, and the rail's pairing — a lock is its tool's key
            // shifted — is worth more than putting two rotation acts on one
            // letter. The full stop reads as squaring up, and nothing else here
            // wants it.
            Button("") {
                if let id = viewModel.focusedItemID {
                    viewModel.straightenCell(forItemID: id)
                }
            }
            .keyboardShortcut(".", modifiers: [])

            Button("") { viewModel.resetFocusedCell() }
                .keyboardShortcut("0", modifiers: [])
            // The sheet-wide way out, shifted: linked cells make a bad
            // arrangement easy to spread, and undoing it cell by cell is the
            // work the link just saved.
            Button("") { viewModel.resetAllCells() }
                .keyboardShortcut("0", modifiers: [.shift])

            // Delete, as a shortcut rather than only as a key the film handles
            // itself. `onKeyPress` needs the film to hold keyboard focus, and
            // after a click in the settings column — or the range popover — it
            // does not, so the key did nothing where a reader most expected it
            // to work. A shortcut is delivered wherever the print screen is.
            //
            // Same order as the film's own handler: the annotation drawn *on* a
            // cell goes before the cell it was drawn on.
            Button("") {
                if viewModel.removeSelectedAnnotation() { return }
                viewModel.removeSelectedCells()
            }
            .keyboardShortcut(.delete, modifiers: [])
            Button("") {
                if viewModel.removeSelectedAnnotation() { return }
                viewModel.removeSelectedCells()
            }
            .keyboardShortcut(.deleteForward, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// The film's own menu: what a drag will do, and what can be done to the
    /// cell under the pointer.
    ///
    /// On the film rather than beside it. A tool is chosen for the cell being
    /// worked on, and the right-click is already over that cell — so the menu
    /// costs the picture no width at all, which is what the rail cost it.
    @ViewBuilder
    private func cellMenu(for item: PrintSelectionItem?) -> some View {
        ForEach(PrintViewModel.CellTool.allCases) { tool in
            Button {
                viewModel.cellTool = tool
            } label: {
                Label("\(tool.displayName)  (\(String(Self.shortcut(for: tool)).uppercased()))",
                      systemImage: viewModel.cellTool == tool ? "checkmark" : tool.symbolName)
            }
        }

        Divider()

        // Picking out cells by hand. Above the locks deliberately: this is the
        // answer when the cells wanted are "these", and the locks are the answer
        // when they are "all of a kind" — and the reader who right-clicked a
        // particular cell is usually after the first.
        Menu {
            Button {
                viewModel.selectSucceedingCellsOnFilm()
            } label: {
                Label("Succeeding Cells on This Film", systemImage: "arrow.down.to.line")
            }
            .disabled(viewModel.focusedItemID == nil)

            Button {
                viewModel.selectAllCellsOnFilm()
            } label: {
                Label("All Cells on This Film", systemImage: "square.grid.3x3.fill")
            }
            .disabled(viewModel.focusedItemID == nil)

            Divider()

            Button {
                viewModel.clearCellSelection()
            } label: {
                Label("Clear Selection  (⎋)", systemImage: "xmark.circle")
            }
            .disabled(!viewModel.hasCellSelection)

            Divider()

            // Taking cells off the film, where the cells were picked. The rest
            // shuffle up into the holes, so this is how a sheet is thinned out
            // rather than re-marked.
            Button(role: .destructive) {
                viewModel.removeSelectedCells()
            } label: {
                Label(viewModel.removableCellCount > 1
                      ? "Take These \(viewModel.removableCellCount) Cells Off the Film  (⌫)"
                      : "Take This Cell Off the Film  (⌫)",
                      systemImage: "trash")
            }
            .disabled(viewModel.removableCellCount == 0)
        } label: {
            Label(viewModel.hasCellSelection
                  ? "Select  (\(viewModel.selectedItemIDs.count) cells)" : "Select",
                  systemImage: "checkmark.circle")
        }

        Divider()

        Button {
            viewModel.showPatientIdentification.toggle()
        } label: {
            Label(viewModel.showPatientIdentification
                  ? "Hide Patient ID Caption  (I)" : "Show Patient ID Caption  (I)",
                  systemImage: "person.text.rectangle")
        }

        // Whether the film carries the viewer's zoom and pan at all. Here as
        // well as in the settings column, because "why is this cell showing a
        // close-up" is asked of the cell, not of a checkbox two panels away:
        // switching it off puts every whole image back on the film.
        Button {
            viewModel.useViewerPresentation.toggle()
        } label: {
            Label(viewModel.useViewerPresentation
                  ? "Fit the Whole Image in Every Cell"
                  : "Use the Viewer's Zoom and Pan",
                  systemImage: viewModel.useViewerPresentation
                  ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        }
        .disabled(viewModel.sendRawPixels)

        Divider()

        // The same switches as the strip above the film, for the hand that is
        // already on the cell.
        Menu {
            ForEach(PrintCellSyncOptions.catalog, id: \.title) { entry in
                Button {
                    viewModel.toggleSyncFromUI(entry.option)
                } label: {
                    Label(entry.title,
                          systemImage: viewModel.cellSync.contains(entry.option)
                          ? "lock.fill" : "lock.open")
                }
                .disabled(entry.option == .window && viewModel.isCellWindowingOverridden)
            }
            Divider()
            ForEach(PrintCellSyncScope.allCases) { scope in
                Button {
                    viewModel.cellSyncScope = scope
                } label: {
                    Label(scope.title,
                          systemImage: viewModel.cellSyncScope == scope ? "checkmark" : "")
                }
            }
        } label: {
            Label("Lock Cells Together",
                  systemImage: viewModel.isCellSyncActive ? "lock.fill" : "lock.open")
        }

        if let item {
            Divider()

            Button("Apply This Window to Every Cell on This Film") {
                viewModel.focusCell(item.id)
                viewModel.applyFocusedWindowToAllCells()
            }
            .disabled(viewModel.window(forItemID: item.id) == nil)

            Button("Revert to the Viewer's Arrangement") {
                viewModel.focusCell(item.id)
                viewModel.revertCell(forItemID: item.id)
            }
            .disabled(!viewModel.isCellAdjusted(item.id))

            Button("Revert Every Cell to the Viewer's Arrangement") {
                viewModel.revertAllCells()
            }
            .disabled(!viewModel.hasAdjustedCells)

            // Only where it can do something: a square cell has nothing to
            // straighten, and an item that never does anything is an item the
            // reader has to test to learn that about.
            if viewModel.isCellSkewed(item.id) {
                Button("Straighten This Cell  (.)") {
                    viewModel.focusCell(item.id)
                    viewModel.straightenCell(forItemID: item.id)
                }
            }

            Button(item.presentation?.invert == true
                   ? "Show This Cell the Right Way Round  (V)"
                   : "Invert This Cell's Greys  (V)") {
                viewModel.focusCell(item.id)
                viewModel.toggleCellInversion(forItemID: item.id)
            }

            Button("Reset This Cell  (0)") {
                viewModel.focusCell(item.id)
                viewModel.resetCell(forItemID: item.id)
            }
            .disabled(!viewModel.isCellEdited(item))

            if let focused = viewModel.focusedItem, focused.id != item.id {
                Button("Reset the Focused Cell") {
                    viewModel.resetFocusedCell()
                }
                .disabled(!viewModel.isCellEdited(focused))
            }

            Button("Reset All Cells  (⇧0)", role: .destructive) {
                viewModel.resetAllCells()
            }
            .disabled(!viewModel.hasEditedCells)

            if !viewModel.annotations(forItemID: item.id).isEmpty {
                Divider()
                Button("Clear This Cell's Annotations", role: .destructive) {
                    viewModel.clearAnnotations(forItemID: item.id)
                }
            }

            Divider()

            Button("Take Off the Film", role: .destructive) {
                viewModel.selection.remove(
                    filePath: item.filePath, frameIndex: item.frameIndex)
            }
        }
    }

    // MARK: - One film

    /// The cells of the film on screen, in Image Box Position order.
    ///
    /// Laid out by ``FilmCellLayout`` — the film composer's own geometry — rather
    /// than by a SwiftUI `Grid`, because a grid can only draw the layouts whose
    /// rows all hold the same number of images. `ROW\1,2` holds one over two, and
    /// the preview has to be able to show the film that is going to be printed.
    private func sheetCells(width: CGFloat, height: CGFloat) -> [FilmCell] {
        plan.cells(onSheetOfWidth: Double(width), height: Double(height),
                   margin: Double(Self.sheetMargin), spacing: Double(Self.cellSpacing))
    }

    /// How the film being drawn states its identification.
    ///
    /// Under every picture, or not at all. Each caption now carries what made
    /// *that* image — modality, image number, slice thickness or kV — which no
    /// single line at the foot of a sheet can state for four different slices.
    /// The rule still comes from ``FilmIdentificationPlanner``, shared with the
    /// print run and the composer, so the strip the reader approves is the strip
    /// the film carries.
    private func identification(onFilm filmIndex: Int) -> FilmIdentification {
        guard viewModel.showPatientIdentification, plan.filmCount > 0 else { return .none }
        var sources: [FilmIdentificationSource] = []
        for index in plan.imageIndices(onFilm: filmIndex) {
            guard items.indices.contains(index) else { continue }
            let item = items[index]
            guard let text = overlayTexts.text(forPath: item.filePath) else { return .none }
            sources.append(FilmIdentificationSource(
                key: item.id, studyKey: text.studyInstanceUID, lines: text.lines))
        }
        return FilmIdentificationPlanner.identification(for: sources, placement: .perImage)
    }

    @ViewBuilder
    private func filmSheet(filmIndex: Int, width: CGFloat, height: CGFloat) -> some View {
        let range = plan.imageIndices(onFilm: filmIndex)
        let identification = identification(onFilm: filmIndex)
        VStack(spacing: 3) {
            ZStack(alignment: .topLeading) {
                // The sheet's own ground is Border Density (2010,0100): the
                // area between and around the image boxes, which the printer
                // exposes to the chosen density. BLACK is the radiology
                // default; WHITE is paper-like — and the preview showing it is
                // what makes the picker under More visibly do something.
                borderColor
                ForEach(sheetCells(width: width, height: height),
                        id: \.position) { filmCell in
                    cell(filmCell: filmCell, range: range, identification: identification)
                        .frame(width: CGFloat(filmCell.width), height: CGFloat(filmCell.height))
                        .offset(x: CGFloat(filmCell.x), y: CGFloat(filmCell.y))
                }
                // Trim YES asks the printer for cut marks along the film's
                // edge; the composer draws them on the emulator's sheet, so
                // the preview shows the same corner ticks in the contrast
                // colour, where NO leaves the border clean.
                if viewModel.trimOption == .yes {
                    trimMarks(width: width, height: height)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.secondary.opacity(0.35), lineWidth: 1)
            )

            // Only worth naming when there is more than one film to tell apart —
            // and the hand-picked cells are named beside it, because a selection
            // decides where the next drag lands and a reader must not have to
            // count checkmarks to know how many cells are about to move.
            if plan.filmCount > 1 || viewModel.hasCellSelection {
                Text([plan.filmCount > 1 ? "Film \(filmIndex + 1) of \(plan.filmCount)" : nil,
                      viewModel.cellSelectionSummary].compactMap { $0 }.joined(separator: "  ·  "))
                    .font(.caption)
                    .foregroundStyle(viewModel.hasCellSelection ? Color.accentColor : .secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Film \(filmIndex + 1) of \(plan.filmCount), "
            + "\(range.count) of \(plan.cellsPerFilm) cells filled")
    }

    @ViewBuilder
    private func cell(
        filmCell: FilmCell,
        range: Range<Int>,
        identification: FilmIdentification = .perImage
    ) -> some View {
        let itemIndex = range.lowerBound + filmCell.position - 1
        let isFilled = itemIndex < range.upperBound
        let item = items.indices.contains(itemIndex) ? items[itemIndex] : nil
        let isFocused = item != nil && item?.id == viewModel.focusedItemID
        // The cell's own size, from the layout rather than measured: under a band
        // layout the cells differ, and every tool that works in cell points —
        // zoom, pan, annotation anchors, the corner text — has to be told about
        // *this* cell rather than about a film-wide average.
        let cellSize = CGSize(width: CGFloat(filmCell.width), height: CGFloat(filmCell.height))
        // The picture gets the whole cell: identification is drawn in the corners
        // of the frame, over background rather than in a strip cut out of it.
        let picture = cellSize

        // Nothing is drawn over the image that the film will not carry: the cell
        // shows the frame, the corner identification and the reader's own
        // annotations, all of which are burned in. Position and labels live in the
        // marks list beside it, and in the accessibility label here. The focus
        // ring is chrome around the cell, not over it.
        RoundedRectangle(cornerRadius: 2)
            // Empty Image Density (2010,0110): what an unfilled image box — and
            // the letterbox beside a fitted picture — is exposed to, exactly as
            // the composer fills both. An unfilled slot keeps a faint ring so
            // it still reads as a place a drag can land, whatever its density.
            .fill(emptyCellColor)
            .overlay {
                if !isFilled {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                }
            }
            .overlay {
                if isFilled {
                    cellImage(item, in: picture)
                        // Held to the picture's own rectangle. The shader draws
                        // the whole frame and lets the view clip it, so without
                        // this the margins either side of a crop would fill with
                        // the neighbouring anatomy — the cell would show more
                        // than the film prints, and read as an enlarged image
                        // spilling past its edges.
                        //
                        // The view itself always fills the cell: its size must
                        // not change with the arrangement, or every zoom step
                        // would resize (and reallocate) a Metal drawable that
                        // exists precisely so a tool step costs one quad redraw.
                        .mask(alignment: .center) {
                            let rect = item.map { imageRect(for: $0, in: picture) }
                                ?? CGRect(origin: .zero, size: picture)
                            Rectangle().frame(width: rect.width, height: rect.height)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            // The reader's own text and arrows, over the picture and under the
            // focus ring — and under the identification, which is the one thing
            // on the film that must stay legible.
            .overlay {
                if isFilled, let item {
                    FilmCellAnnotationLayer(
                        viewModel: viewModel,
                        itemID: item.id,
                        imageRect: imageRect(for: item, in: picture),
                        orientation: annotationOrientation(for: item),
                        isInteractive: viewModel.cellTool.isDrawing
                            || !viewModel.annotations(forItemID: item.id).isEmpty)
                }
            }
            // Identification in the corners of the cell, where the print run
            // burns it: the corners of a fitted image are background, and the
            // reader keeps every pixel of anatomy. Pushed right into the cell's
            // corners rather than the picture's — a frame whose shape is not the
            // cell's leaves a letterbox margin, and text held to the picture
            // reads as floating in the middle of the sheet.
            .overlay {
                if isFilled, identification.isPerImage, let item,
                   let text = overlayTexts.text(forPath: item.filePath), !text.isEmpty {
                    PatientIdentificationOverlayView(
                        corners: text.corners(including: viewModel.identificationFields),
                        cellSize: cellSize,
                        // The same style the run hands the burner, so a job that
                        // sets its own caption face or size is previewed in it
                        // rather than in the default.
                        style: viewModel.identificationStyle)
                    .allowsHitTesting(false)
                }
            }
            // The focus ring, and the thinner ring on a hand-picked cell. Both
            // are chrome around the cell rather than over it, and a selected
            // cell that is also focused shows the focus ring alone — two rings
            // in the same place read as one thick one.
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                } else if isFilled, let item, viewModel.isCellSelected(item.id) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1)
                }
            }
            // The lock, on the picture itself. The one thing here that is not
            // burned into the film — the rule this file otherwise holds to — and
            // it earns the exception: it says this cell is about to move when
            // its neighbour is dragged, which is the fact a reader most needs
            // *before* dragging, and it costs a right-click to find anywhere
            // else. It never takes a click — the rail is where locks are opened
            // and shut, and the ⌘-click that selects a cell must not be caught
            // by a badge sitting over it.
            //
            // Top left: the identification's own corners are the top right and
            // the two along the bottom, and a badge over a patient's name is a
            // badge over the one thing on the film that must stay legible.
            .overlay(alignment: .topLeading) {
                if isFilled, let item, viewModel.movesWithFocus(item.id) {
                    Image(systemName: viewModel.isCellSelected(item.id)
                          ? "checkmark.circle.fill" : "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                        .padding(2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.black.opacity(0.55)))
                        .padding(3)
                        .allowsHitTesting(false)
                        .accessibilityLabel(
                            viewModel.isCellSelected(item.id)
                            ? "Selected: tools act on this cell"
                            : isFocused
                            ? "Linked: adjusting this cell adjusts the others"
                            : "Linked to the focused cell")
                }
            }
            .contentShape(Rectangle())
            #if os(macOS)
            // Scroll zooms the cell under the cursor, as it does in the viewer.
            // The handler scopes itself to this view in this window, so scrolling
            // the film strip sideways does not zoom whatever is behind it.
            .background(
                Group {
                    if isFilled, let item {
                        ScrollWheelHandler { delta in
                            guard delta.y != 0 else { return }
                            if viewModel.focusedItemID != item.id {
                                viewModel.focusCell(item.id)
                            }
                            // A notch is a fixed zoom step; a trackpad scales
                            // with how far it was actually swiped.
                            let amount = delta.isPrecise ? Double(delta.y) : (delta.y > 0 ? 4 : -4)
                            viewModel.adjustZoom(
                                forItemID: item.id,
                                factor: 1.0 + amount * Self.scrollZoomSensitivity,
                                cellSize: picture,
                                pixelSize: sourcePixelSize(for: item))
                        }
                    }
                }
            )
            // The pointer says what the next drag on this cell will do.
            //
            // Not `.allowsHitTesting(false)`: SwiftUI's exclusion can detach
            // the view from the window's tracking altogether, and the pointer
            // then never changes at all. It is a zero-content NSView with no
            // gestures of its own, so leaving it hit-testable costs nothing —
            // the taps and drags are on the cell *behind* it, and SwiftUI still
            // delivers those because this overlay never consumes an event.
            .overlay(
                Group {
                    if isFilled {
                        ToolCursor(cursor: Self.toolCursor(for: viewModel.cellTool))
                    }
                }
            )
            #endif
            .modifier(CellInteraction(
                enabled: isFilled,
                item: item,
                viewModel: viewModel,
                dragAnchor: $dragAnchor,
                draftArrowID: $draftArrowID,
                cellSize: picture,
                pixelSize: item.flatMap { sourcePixelSize(for: $0) },
                imageRect: item.map { imageRect(for: $0, in: picture) } ?? .zero))
            // The focused cell reports its size, so the sidebar's saved-view
            // picker — which has no cell geometry of its own — can restore a
            // Displayed Area against the cell the picture will really print in.
            // The focused one specifically: under a band layout the cells
            // differ, and the inspector is always about the focused cell.
            .modifier(FocusedCellSizeReporter(
                isFocused: isFocused, cellSize: picture, viewModel: viewModel))
            // The tools live here now. Each item acts on the cell that was
            // right-clicked — it takes the cell first — so the menu is about the
            // picture under the pointer rather than about whichever cell
            // happened to be focused before.
            .contextMenu { cellMenu(for: item) }
            .accessibilityLabel(
                isFilled
                ? "Cell \(itemIndex + 1): \(item?.displayLabel ?? "image")"
                : "Empty cell")
            .accessibilityAddTraits(isFocused ? [.isSelected] : [])
    }

    /// Where the image is actually drawn inside a cell.
    ///
    /// For fit — the default — the frame is fitted and centred, so unless it
    /// happens to be the cell's shape there are margins either side of it or
    /// above and below. Fill and stretch cover the whole cell (SRS FR-003):
    /// the fill crop is composed into the shader's source region, and stretch
    /// is drawn by the CPU path. True size draws as fit here — a preview sheet
    /// is scaled to the panel, so absolute physical size has no meaning on it;
    /// the composed film and the printer place it exactly. A non-centre
    /// alignment likewise shows in the composed film, not here: the live cell
    /// centres, because the shader does, and a mask that moved without the
    /// picture would clip anatomy.
    ///
    /// Annotations are anchored to this rect, not to the cell: the margin is
    /// not part of the picture and the printer has no pixels there.
    /// How a cell's arrangement bears on the annotations drawn over it.
    ///
    /// The cell's own presentation, resolved the way the *film* resolves it —
    /// through `previewItem(for:)`, so a job with the viewer's arrangement
    /// switched off, or sending raw pixels, gets the identity here exactly as
    /// it gets an unarranged picture. Measured against the source frame, which
    /// is the space the annotations' fractions are in.
    private func annotationOrientation(for item: PrintSelectionItem) -> PrintOverlayOrientation {
        let resolved = viewModel.previewItem(for: item)
        let pixels = sourcePixelSize(for: item)
        return PrintOverlayOrientation(
            presentation: resolved.presentation ?? ViewerPresentation(),
            imageWidth: Int(pixels?.width ?? 0),
            imageHeight: Int(pixels?.height ?? 0),
            covers: viewModel.scalingMode == .fillToFilm)
    }

    private func imageRect(for item: PrintSelectionItem, in cellSize: CGSize) -> CGRect {
        let cell = CGRect(origin: .zero, size: cellSize)
        // Fill and stretch put pixels in every point of the cell.
        if viewModel.scalingMode == .fillToFilm || viewModel.scalingMode == .stretch {
            return cell
        }
        #if canImport(CoreGraphics)
        guard let pixels = arrangedPixelSize(for: item),
              pixels.width > 0, pixels.height > 0,
              cellSize.width > 0, cellSize.height > 0 else { return cell }
        let imageAspect = CGFloat(pixels.width) / CGFloat(pixels.height)
        let cellAspect = cellSize.width / cellSize.height
        if imageAspect > cellAspect {
            // Wider than the cell: full width, margins top and bottom.
            let height = cellSize.width / imageAspect
            return CGRect(x: 0, y: (cellSize.height - height) / 2,
                          width: cellSize.width, height: height)
        }
        let width = cellSize.height * imageAspect
        return CGRect(x: (cellSize.width - width) / 2, y: 0,
                      width: width, height: cellSize.height)
        #else
        return cell
        #endif
    }

    /// The size of the *source* frame behind a cell, when it is known.
    ///
    /// The zoom and pan tools need it to know how much of the image is hidden
    /// outside the cell, which is how far they are allowed to travel. Only the
    /// GPU path can answer: its texture is the whole frame, whereas the CPU
    /// thumbnail is already the arranged crop.
    private func sourcePixelSize(for item: PrintSelectionItem) -> CGSize? {
        #if canImport(Metal)
        if let texture = cellTextures.texture(for: item) {
            return CGSize(width: texture.width, height: texture.height)
        }
        #endif
        return nil
    }

    #if canImport(CoreGraphics)
    /// The size of the picture this cell prints, in source pixels.
    ///
    /// Whichever path drew the cell, this is the same number: the CPU thumbnail
    /// *is* the arranged picture, so its own dimensions say it, and on the GPU the
    /// arrangement is a transform over a full-frame texture, so it is worked out
    /// from the visible region instead. Getting the two to agree is what keeps an
    /// annotation in the same place when a cell's texture arrives.
    private func arrangedPixelSize(for item: PrintSelectionItem) -> (width: Int, height: Int)? {
        #if canImport(Metal)
        if let texture = drawnTexture(for: item) {
            return PrintCellDisplay.arrangedPixelSize(
                for: item, imageWidth: texture.width, imageHeight: texture.height)
        }
        #endif
        guard let image = thumbnails.image(for: item) else { return nil }
        return (image.width, image.height)
    }
    #endif

    /// The marked frame itself, or a placeholder while it loads or if it cannot
    /// be rendered.
    ///
    /// From the GPU when the frame is there — which is where the tools want it,
    /// since every drag then costs a redraw of a quad rather than a re-render —
    /// and from the CPU thumbnail otherwise. The two compose the same geometry:
    /// the shader is given the film's own composition (see ``PrintCellDisplay``),
    /// not the viewer's, so a cell does not change shape when its texture lands.
    @ViewBuilder
    private func cellImage(_ item: PrintSelectionItem?, in cellSize: CGSize) -> some View {
        #if canImport(Metal)
        if let item, let texture = drawnTexture(for: item) {
            MetalImageView(
                frame: texture,
                presentation: PrintCellDisplay.presentation(
                    for: item,
                    imageWidth: texture.width,
                    imageHeight: texture.height,
                    // Fill composes its crop into the shader's source region,
                    // so the cell fills without the view changing size — the
                    // view's size never follows the arrangement (see the mask
                    // comment above).
                    fillingCellOfSize: viewModel.scalingMode == .fillToFilm
                        ? cellSize : nil,
                    // Stretch keeps the fitted crop and pulls the composed
                    // picture to the cell's edges in the transform instead.
                    stretchingToCell: viewModel.scalingMode == .stretch,
                    // The film-wide Presentation LUT, so the preview shows the
                    // polarity the sheet will actually come out with — but only
                    // for cells leaving as greys: the preparer's rendered
                    // inverse skips colour pixels (and never runs on raw), so
                    // the preview must not invert what the film will not.
                    presentationLUTShape: !viewModel.sendRawPixels
                        && !viewModel.cellPrintsInColor(item)
                        ? viewModel.presentationLUTShape : nil,
                    // Polarity REVERSE flips every image box on the printer.
                    polarityInverted: viewModel.polarity == .reverse,
                    // "Print colour images as greys" shows the Rec.601 greys
                    // the film will carry, and comes straight back on uncheck.
                    desaturated: viewModel.cellIsFlattenedToGrey(item)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            cellCPUImage(item)
        }
        #else
        cellCPUImage(item)
        #endif
    }

    /// A cell drawn from a CPU-rendered still — the fallback: the moment before
    /// a texture arrives, frames with overlay planes, and machines without
    /// Metal. It composes every scaling mode the GPU path does, because a cell
    /// must look the same whichever renderer answered.
    @ViewBuilder
    private func cellCPUImage(_ item: PrintSelectionItem?) -> some View {
        #if canImport(CoreGraphics)
        if let item, let image = thumbnails.image(for: item) {
            // Aspect ratio intact for fit and fill — the same placement the
            // printer performs — and deliberately ignored for stretch, which is
            // that mode's whole (non-diagnostic) point. Fill's overflow is cut
            // by the cell's own clip shape.
            //
            // The film-wide switches the GPU path composes in its shader are
            // composed here as view effects, because a cell must look the same
            // whichever renderer answered: "print colour images as greys" shows
            // the flattened greys (the thumbnail itself stays colour — the
            // effect reverts with the switch), and Polarity REVERSE / the
            // rendered-inverse Presentation LUT flip the picture over the
            // thumbnail's own baked-in cell invert — `contrast(-1)` is exactly
            // `1 − x` per channel, the shader's own negation. Saturation before
            // inversion, the wire's own order: flatten first, then the LUT.
            let base = Image(decorative: image, scale: 1.0, orientation: .up)
                .resizable()
                .saturation(viewModel.cellIsFlattenedToGrey(item) ? 0 : 1)
                .contrast(viewModel.filmWideInversion(for: item) ? -1 : 1)
            switch viewModel.scalingMode {
            case .stretch:
                base.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .fillToFilm:
                base.aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .fitToFilm, .trueSize:
                base.aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let item, thumbnails.didFail(item) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            ProgressView()
                .controlSize(.mini)
        }
        #else
        Color.gray.opacity(0.35)
        #endif
    }

    // MARK: - Film box densities

    /// Border Density (2010,0100) as the preview's sheet ground.
    private var borderColor: Color {
        Self.densityColor(viewModel.borderDensity)
    }

    /// Empty Image Density (2010,0110) as the unfilled-box and letterbox fill.
    private var emptyCellColor: Color {
        Self.densityColor(viewModel.emptyImageDensity)
    }

    /// A density value as the grey it prints: `BLACK`, `WHITE`, or a numeric
    /// optical density in hundredths, interpolated over ordinary film stock's
    /// 0.2–3.0 OD exactly as `FilmComposer.luminance(forDensity:)` reads it.
    private static func densityColor(_ value: String) -> Color {
        let text = value.trimmingCharacters(in: .whitespaces).uppercased()
        switch text {
        case "BLACK": return .black
        case "WHITE": return .white
        default:
            guard let density = Double(text) else { return .black }
            let normalized = max(0, min(1, (density - 20) / (300 - 20)))
            // Higher optical density = darker on film.
            return Color(white: 1 - normalized)
        }
    }

    /// The four corner cut marks Trim YES asks the printer for, as the
    /// composer draws them: L-shaped ticks inset from the sheet's corners, in
    /// whichever of black or white contrasts with the border.
    private func trimMarks(width: CGFloat, height: CGFloat) -> some View {
        let inset: CGFloat = 6
        let length: CGFloat = min(18, width * 0.04)
        let contrast: Color = viewModel.borderDensity.uppercased() == "WHITE" ? .black : .white
        return Path { path in
            for (x, y, dx, dy): (CGFloat, CGFloat, CGFloat, CGFloat) in [
                (inset, inset, 1, 1),
                (width - inset, inset, -1, 1),
                (inset, height - inset, 1, -1),
                (width - inset, height - inset, -1, -1)
            ] {
                path.move(to: CGPoint(x: x + dx * length, y: y))
                path.addLine(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y + dy * length))
            }
        }
        .stroke(contrast, lineWidth: 1)
        .allowsHitTesting(false)
    }

    // MARK: - Geometry

    /// Width over height, from the physical sheet the job will actually print on.
    ///
    /// Taken from ``FilmSheet`` rather than assumed: 8×10, 14×17 and A4 are
    /// visibly different shapes, and a preview drawn at a nominal 3:4 gives its
    /// cells the wrong aspect — which is the aspect the user judges the crop by.
    /// The dpi is irrelevant here; only the ratio is used.
    private var sheetAspect: CGFloat {
        let sheet = FilmSheet(
            filmSize: plan.filmSize, orientation: plan.filmOrientation, dpi: 150)
        guard sheet.heightMillimeters > 0 else { return 3.0 / 4.0 }
        return CGFloat(sheet.widthMillimeters / sheet.heightMillimeters)
    }

    /// The printed sheet's height in millimetres — what the footer's type is
    /// scaled against, so the strip on screen is the strip on film.
    private var sheetHeightMillimeters: CGFloat {
        let sheet = FilmSheet(
            filmSize: plan.filmSize, orientation: plan.filmOrientation, dpi: 150)
        return CGFloat(sheet.heightMillimeters)
    }

    /// Zoom fraction per unit of scroll.
    private static let scrollZoomSensitivity: Double = 0.02

    /// The key that picks a tool. Single letters, no modifier: the film has
    /// keyboard focus while it is being worked on.
    private static func shortcut(for tool: PrintViewModel.CellTool) -> Character {
        switch tool {
        case .window: return "w"
        case .zoom:   return "z"
        case .pan:    return "p"
        // E, as in the viewer: R is the arrow tool here and rotate needed a key
        // that was not already spoken for. The letter is arbitrary either way,
        // and one that means rotate on both screens is worth more than one that
        // reads better on this screen alone.
        case .rotate: return "e"
        case .text:   return "t"
        case .arrow:  return "r"
        }
    }

    /// The key that shuts or opens a lock — the tool's own key, shifted.
    ///
    /// ⇧W for the window lock next to W for the window tool, and so on. A lock
    /// is reached for in the middle of working with the tool it belongs to
    /// ("now do that to all of them"), so the hand is already on that key, and
    /// a second unrelated letter to memorise per lock is the thing that stops
    /// shortcuts being used at all. Invert borrows ⇧V from the invert command
    /// for the same reason.
    ///
    /// The pairing is not decorative: the locks are ordered to match the tools
    /// on the rail, and this is that same correspondence expressed on the
    /// keyboard.
    private static func shortcut(for option: PrintCellSyncOptions) -> Character {
        if option == .window { return "w" }
        if option == .zoomPan { return "z" }
        if option == .rotate { return "e" }
        return "v"
    }

    /// Room reserved under the film, and only when there is something to put
    /// there: with one film there is no caption, so the film takes that height.
    private var captionAllowance: CGFloat {
        plan.filmCount > 1 || viewModel.hasCellSelection ? 18 : 0
    }

    /// Room left either side of a single film, so it does not touch the panel
    /// edges.
    private static let sideAllowance: CGFloat = 4

    /// Width of one page-turn arrow.
    private static let pagingButtonWidth: CGFloat = 34

    /// Width the two arrows take from the film — none at all on a single film,
    /// where the picture gets it instead.
    private var pagingAllowance: CGFloat {
        plan.filmCount > 1 ? Self.pagingButtonWidth * 2 : 0
    }

    /// Below this the cells stop being readable, so the preview scrolls instead.
    private static let minimumSheetHeight: CGFloat = 160

    /// The unprinted edge of the sheet, and the gutter between two cells.
    private static let sheetMargin: CGFloat = 6
    private static let cellSpacing: CGFloat = 4
}

// MARK: - Focused cell geometry

/// Reports the focused cell's drawn size to the view model.
///
/// The sidebar's saved-view picker has no cell geometry of its own, and a
/// stored Displayed Area only becomes a zoom against a viewport — so it has to
/// be told the cell the picture will print in, or the crop comes back the shape
/// of the viewer tile the mark was made in.
///
/// A modifier rather than three `onChange`s inline: the cell body is already at
/// the limit of what the type-checker will take in one expression.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
private struct FocusedCellSizeReporter: ViewModifier {
    let isFocused: Bool
    let cellSize: CGSize
    let viewModel: PrintViewModel

    func body(content: Content) -> some View {
        content
            .onAppear(perform: report)
            .onChange(of: isFocused) { _, _ in report() }
            .onChange(of: cellSize) { _, _ in report() }
    }

    private func report() {
        guard isFocused else { return }
        viewModel.recordCellSize(cellSize)
    }
}

// MARK: - Cell interaction

/// Click-to-focus and drag-to-adjust on one film cell.
///
/// Split out as a modifier so the cell body stays a description of the film
/// rather than a pile of gesture plumbing.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
private struct CellInteraction: ViewModifier {
    let enabled: Bool
    let item: PrintSelectionItem?
    @Bindable var viewModel: PrintViewModel
    @Binding var dragAnchor: CGSize

    /// The arrow currently being dragged out, so the drag lengthens that arrow
    /// rather than starting a new one on every mouse event.
    @Binding var draftArrowID: UUID?

    /// Whether a pan drag is in progress, so the hand closes once at its start
    /// rather than on every mouse event it delivers.
    @State private var isPanning = false

    /// The bearing the rotate drag last saw, around the centre of the picture.
    ///
    /// The tool turns the cell by the *arc the pointer sweeps*, not by where it
    /// is, so each event needs the one before it. Cleared when the drag ends, so
    /// the next drag anchors afresh wherever it starts rather than snapping the
    /// picture to the angle the last one finished at.
    @State private var rotateBearing: Double?

    let cellSize: CGSize

    /// The source frame's own size, when the cell knows it — what bounds how far
    /// the zoom and pan tools may travel.
    let pixelSize: CGSize?

    /// Where the picture is inside the cell, for placing what gets drawn on it.
    let imageRect: CGRect

    func body(content: Content) -> some View {
        guard enabled, let item else { return AnyView(content) }
        return AnyView(
            content
                // The location matters for the drawing tools — text lands where
                // it was clicked — and is harmless to the rest. The ⌘ that turns
                // a click into "add this cell to the picked set" is read off the
                // event inside the handler rather than expressed as a second,
                // modified `TapGesture`: two tap gestures on one view are
                // resolved by SwiftUI's own priority rules, and the modified one
                // lost — every ⌘-click arrived as a plain click, so the picked
                // set never grew past the cell last clicked and Delete took only
                // that one.
                .onTapGesture { location in handleTap(at: location, on: item) }
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if viewModel.cellTool == .arrow {
                                dragArrow(from: value.startLocation,
                                          to: value.location, on: item)
                                return
                            }
                            if viewModel.focusedItemID != item.id { focus(item) }
                            #if os(macOS)
                            // The hand closes on the picture it has taken hold
                            // of, and opens again when it is let go — the one
                            // cursor change that reports the drag rather than
                            // what a drag would do.
                            if viewModel.cellTool == .pan, !isPanning {
                                isPanning = true
                                NSCursor.closedHand.set()
                            }
                            #endif
                            // Rotate works in absolute locations rather than
                            // in the running translation: the arc swept around
                            // the picture's centre is what turns it, and a
                            // translation says nothing about where the pointer
                            // is relative to that centre.
                            if viewModel.cellTool == .rotate {
                                rotate(to: value.location, on: item)
                                return
                            }
                            apply(value.translation, to: item)
                        }
                        .onEnded { value in
                            if viewModel.cellTool == .rotate {
                                rotate(to: value.location, on: item)
                            }
                            dragAnchor = .zero
                            rotateBearing = nil
                            finishArrow(on: item)
                            #if os(macOS)
                            if isPanning {
                                isPanning = false
                                NSCursor.openHand.set()
                            }
                            #endif
                        }
                )
        )
    }

    /// Whether ⌘ is down as this click is handled.
    ///
    /// Read from the event rather than carried by the gesture: SwiftUI's tap
    /// gesture does not report its modifiers, and expressing the modified click
    /// as a second gesture puts the two in a priority contest the modified one
    /// loses. On a platform with no such notion, there is no ⌘ to hold.
    private static var isCommandHeld: Bool {
        #if canImport(AppKit)
        return NSEvent.modifierFlags.contains(.command)
        #else
        return false
        #endif
    }

    private func focus(_ item: PrintSelectionItem) {
        viewModel.focusCell(item.id)
        // Windowing needs concrete values to start from; resolving them costs a
        // file read, so it happens once, when a cell is first picked up.
        Task { await viewModel.seedWindowIfNeeded(forItemID: item.id) }
    }

    // MARK: - Drawing

    /// A click: pick the cell out with ⌘ held, place text with the text tool,
    /// otherwise just take the cell.
    private func handleTap(at location: CGPoint, on item: PrintSelectionItem) {
        // ⌘ rather than ctrl: on this platform ctrl-click *is* the right-click
        // that opens the cell's own menu, and a shortcut that also opens a menu
        // is a shortcut nobody can use.
        if Self.isCommandHeld {
            viewModel.toggleCellSelection(item.id)
            return
        }
        // A plain click on the film is a fresh start: it takes one cell, so the
        // picked set — which outranks the locks and decides what the next drag
        // and the next Delete reach — must not outlive the click that replaces
        // it. Escape and the rail's button say the same thing explicitly.
        if viewModel.hasCellSelection, !viewModel.isCellSelected(item.id) {
            viewModel.clearCellSelection()
        }
        focus(item)
        guard viewModel.cellTool == .text, let point = normalized(location) else {
            // Clicking the picture with no drawing tool active lets go of
            // whatever annotation was selected — the inspector then talks about
            // the cell again rather than about text nobody is editing.
            if !viewModel.cellTool.isDrawing { viewModel.selectAnnotation(nil) }
            return
        }
        viewModel.addTextAnnotation(forItemID: item.id, at: point)
    }

    /// Drags an arrow out from where the drag began.
    private func dragArrow(from start: CGPoint, to end: CGPoint, on item: PrintSelectionItem) {
        guard let tail = normalized(start), let head = normalized(end) else { return }
        if viewModel.focusedItemID != item.id { focus(item) }

        guard let draftArrowID else {
            draftArrowID = viewModel.addArrowAnnotation(
                forItemID: item.id, from: tail, to: head)
            return
        }
        viewModel.moveArrowEnd(draftArrowID, forItemID: item.id, isHead: true, to: head)
    }

    /// Ends an arrow drag, dropping an arrow too short to be a drawing rather
    /// than a slip of the mouse.
    private func finishArrow(on item: PrintSelectionItem) {
        guard let draftArrowID else { return }
        self.draftArrowID = nil
        if let drawn = viewModel.annotations(forItemID: item.id)
            .first(where: { $0.id == draftArrowID }), drawn.isBlank {
            viewModel.removeAnnotation(draftArrowID, forItemID: item.id)
        }
    }

    /// A point in the cell as a fraction of the image, or `nil` when the click
    /// landed in the letterbox margin, where the film has no pixels.
    private func normalized(_ location: CGPoint) -> PrintOverlayPoint? {
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }
        let x = (location.x - imageRect.minX) / imageRect.width
        let y = (location.y - imageRect.minY) / imageRect.height
        guard x >= 0, x <= 1, y >= 0, y <= 1 else { return nil }
        return PrintOverlayPoint(x: Double(x), y: Double(y))
    }

    /// Turns the cell by the arc the pointer just swept around its picture.
    ///
    /// The pointer is a handle on the picture: drag round clockwise and the cell
    /// follows clockwise, drag back and it unwinds, all the way round in either
    /// direction with no quarter-turn snapping — the same gesture the viewer's
    /// rotate tool answers to, so the act means one thing on both screens.
    ///
    /// The pivot is the centre of the *picture*, not of the cell. On a fitted
    /// film the two differ by the letterbox margin, and turning about the cell's
    /// centre would swing a picture that is not centred in it — the anatomy
    /// would orbit rather than turn on the spot.
    ///
    /// Near the pivot a bearing is noise — a pixel of jitter there swings it
    /// wildly — so ``GestureHelpers/dragBearing(x:y:pivotX:pivotY:minimumRadius:)``
    /// stays silent until the pointer is far enough out, and the first bearing
    /// after that only anchors the drag.
    private func rotate(to location: CGPoint, on item: PrintSelectionItem) {
        let pivot = imageRect.isEmpty
            ? CGPoint(x: cellSize.width / 2, y: cellSize.height / 2)
            : CGPoint(x: imageRect.midX, y: imageRect.midY)
        guard let bearing = GestureHelpers.dragBearing(
            x: Double(location.x), y: Double(location.y),
            pivotX: Double(pivot.x), pivotY: Double(pivot.y)
        ) else { return }
        defer { rotateBearing = bearing }
        guard let previous = rotateBearing else { return }
        viewModel.rotateCell(
            forItemID: item.id,
            byDegrees: GestureHelpers.shortestAngleDelta(from: previous, to: bearing),
            cellSize: cellSize)
    }

    /// Turns the running translation into a per-frame delta and applies the tool.
    private func apply(_ translation: CGSize, to item: PrintSelectionItem) {
        let dx = translation.width - dragAnchor.width
        let dy = translation.height - dragAnchor.height
        dragAnchor = translation

        switch viewModel.cellTool {
        case .text, .arrow:
            // Handled by the tap and the arrow drag; a drawing tool must not also
            // window the cell under it.
            return
        case .rotate:
            // Handled by `rotate(to:on:)`, which needs where the pointer is
            // rather than how far it has come.
            return
        case .window:
            // Horizontal widens, vertical raises the centre — the viewer's own
            // convention, so the gesture means the same thing on both screens.
            guard !viewModel.isCellWindowingOverridden else { return }
            // A mark can be windowless while its cell stays focused — revert
            // took the numbers away, or a seed is still being read — and a
            // drag with no starting values adjusts nothing. Seed here so the
            // drag comes alive the moment the values land.
            guard viewModel.window(forItemID: item.id) != nil else {
                Task { await viewModel.seedWindowIfNeeded(forItemID: item.id) }
                return
            }
            viewModel.adjustWindow(
                forItemID: item.id,
                deltaCenter: -Double(dy) * Self.windowSensitivity,
                deltaWidth: Double(dx) * Self.windowSensitivity)
        case .zoom:
            // Dragging up enlarges, as a zoom slider pushed away from you does.
            let factor = 1.0 - Double(dy) * Self.zoomSensitivity
            viewModel.adjustZoom(forItemID: item.id, factor: factor,
                                 cellSize: cellSize, pixelSize: pixelSize)
        case .pan:
            viewModel.panCell(
                forItemID: item.id, dx: Double(dx), dy: Double(dy),
                cellSize: cellSize, pixelSize: pixelSize)
        }
    }

    /// Window units per point dragged. The window is in the viewer's space, so
    /// a CT drag moves in HU here exactly as it does in the viewer.
    private static let windowSensitivity: Double = 2.0

    /// Zoom fraction per point dragged.
    private static let zoomSensitivity: Double = 0.005
}

#endif
