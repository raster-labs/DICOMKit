// PrintSettingsView.swift
// DICOMStudio
//
// DICOM Studio — the print screen: pick a printer and a grid, check the film,
// and send the marked images to the DICOM printer.
//
// The film is the thing being judged, so the film gets the window. Two slim rows
// of chrome across the top — what is being printed and the actions, then the
// printer, sheet, orientation, copies and grid — and everything below them is
// the picture. The tools that adjust a cell are on the film's own right-click
// menu rather than in a rail beside it, and the rest of what the print SCU can
// send is behind "More", in a column that is closed until it is wanted.
//
// Top row: title, plan summary, console toggle, shortcuts, recent jobs, actions.
// Options row: printer, film size, orientation, copies, layout gallery, More.
// Behind More: printer tests, the marked images, everything the CLI exposes,
// and the focused cell's own window and annotation controls.
//
// NEMA-verified: 2026a, checked 2026-10-06 — every print term offered here comes from DICOMPrintKit's
// PrintOptionCatalog over DICOMNetwork's enums (verified in those modules against PS3.3 2026a Tables C.13-1,
// C.13-3, C.13-5 and C.11-4); this file adds no literal of its own. Film Destination (2000,0040) offers
// BIN_i for any i ≥ 1 — Table C.13-1 puts no maximum on the number of sorter bins and the catalogue lists only
// BIN_1 and BIN_2 — and since 2026-10-06 the bin field goes through DICOMPrintKit FilmDestination(catalogToken:)
// and shows catalogToken / catalogTokenList, the dicom-print --film-destination spelling (D242). The bit-depth help cited Table C.13-3 for the Bits
// Stored 8/12 rule; the rule is in the Image Box Pixel Presentation Module, Table C.13-5 (D23's sibling).

#if canImport(SwiftUI)
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import DICOMCore
import DICOMNetwork
import DICOMPrintKit
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// How the print screen is on screen.
///
/// A sheet has to be told its size — given only a minimum it settles on the
/// smallest thing its content will accept, and the film ends up a square in the
/// middle of a clipped options band. A window is sized by the user and
/// remembered by the system, so there only a floor is imposed.
public enum PrintScreenPresentation: Sendable {
    /// Raised over the viewer as a modal sheet.
    case sheet
    /// A window of its own, beside the viewer.
    case window
    /// In the viewer's own column, in place of the images.
    ///
    /// The shell hands the print screen the whole centre panel and takes it
    /// back when the film is printed or put away — there is no presentation to
    /// lower, so an embedded screen closes through `onClose` rather than
    /// `dismiss()`. Sized like a window: the panel is whatever the reader made
    /// it, and only the floor the options band needs is imposed.
    case embedded
}

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct PrintSettingsView: View {
    @Bindable var viewModel: PrintViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showAdvanced = false

    /// Whether the advanced settings column is showing.
    ///
    /// Closed to begin with. What a reading room changes per film — the printer,
    /// the sheet, how many copies, the grid — is in the bar across the top, and
    /// everything else is a setting that is chosen once and then left alone. A
    /// column of those permanently open is width the film cannot use.
    @State private var showOptions = false

    /// Whether the console log panel is showing on the right, alongside the film.
    ///
    /// Closed while the film is being composed: there is nothing in the log yet,
    /// and its column is width the film can use to be judged. It opens by itself
    /// the moment a job starts — that is when the log has something to say, and
    /// it says it beside the film rather than in place of it, which is what the
    /// old full-screen log took away. The header toggle overrides either way.
    @State private var showConsole = false
    @State private var showPrinterManagement = false
    @State private var showImageList = false

    /// How wide the console column is, as the reader last left it. Kept across
    /// jobs and launches: a log column is sized once for the paths and UIDs a
    /// site's printers emit, not re-dragged every print.
    @AppStorage("print.consoleWidth") private var storedConsoleWidth: Double = Double(
        PrintSettingsView.defaultConsoleWidth)

    /// The console's width when the splitter was picked up, so the drag applies
    /// a delta rather than jumping the panel to the pointer.
    @State private var splitterAnchor: CGFloat?

    /// Keyboard focus for the annotation's text field, so text placed on a cell
    /// can be typed straight away rather than clicked into first.
    @FocusState private var isAnnotationTextFocused: Bool

    /// Size of the window the sheet was raised from. The print screen opens at
    /// the same size as the screen behind it. Unused when it *is* a window.
    private let parentSize: CGSize?

    /// Whether this is a sheet over the viewer, a window of its own, or the
    /// viewer's centre panel — which decides how the screen is sized and how
    /// it closes; the contents are the same every way.
    private let presentation: PrintScreenPresentation

    /// How an embedded screen is put away. A sheet or a window has a
    /// presentation for `dismiss()` to lower; a screen sitting in the shell's
    /// own panel does not, so the shell hands in the way back instead — see
    /// ``close()``.
    private let onClose: (() -> Void)?

    public init(
        viewModel: PrintViewModel,
        parentSize: CGSize? = nil,
        presentation: PrintScreenPresentation = .sheet,
        onClose: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.parentSize = parentSize
        self.presentation = presentation
        self.onClose = onClose
    }

    /// Puts the screen away, however it is on screen: through the shell's
    /// hand-back when embedded, through `dismiss()` when presented.
    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if viewModel.isRunning || viewModel.phase != .configuring {
                runLayout
            } else {
                configurationForm
            }
        }
        // The log follows the job: it appears when printing starts and is put
        // away again when the screen goes back to composing a film ("Print
        // Again"), where its column is better spent on the picture.
        .onChange(of: viewModel.phase) { _, phase in
            showConsole = (phase != .configuring)
        }
        // The screen can be opened onto a job already running — the window
        // outlives any one visit to it — and then the log is wanted at once.
        .onAppear {
            showConsole = (viewModel.phase != .configuring)
            // Every visit starts with the same tool armed and no locks shut.
            // The caller that opened the screen normally resets it too, but the
            // window can be reopened from the Print Center and by ⌘-tabbing back
            // to one that was closed, and neither goes through that path — while
            // an armed pan tool is invisible until the first drag has already
            // moved the wrong thing. Cheap enough to do twice; not doing it once
            // is what costs.
            if viewModel.phase == .configuring { viewModel.resetPreviewTools() }
        }
        // Whether the marked images carry colour decides the SOP class the job
        // goes out on, and it can only be known by reading the files. Keyed to
        // the marks so it runs when the screen opens and again whenever the
        // selection changes; already-read files are skipped inside.
        .task(id: viewModel.selection.items.map(\.filePath)) {
            await viewModel.refreshSourceColor()
        }
        // Text placed on a cell opens its own editor on the cell — typing lands
        // there, not in this sidebar (which may not even be open). Grabbing
        // focus here as well would fight the inline box for the keyboard.
        // A fixed size, not a range: given only a range, the sheet settles on
        // whatever its content asks for — which is the minimum — and the options
        // band ends up clipped with the film in a small square in the middle.
        // A window is sized by the user, so there the same numbers are a floor.
        .modifier(PrintScreenSizing(presentation: presentation, sheetSize: sheetSize))
        .sheet(isPresented: $showPrinterManagement) {
            PrinterManagementView(viewModel: viewModel)
        }
    }

    /// The size the sheet opens at.
    ///
    /// The size of the window it was raised from. The film and the print log are
    /// both read the way images are read in the viewer, so the print screen gets
    /// the same room the viewer had rather than a smaller card floating on it.
    /// Never below the size the options band needs, and never past the display
    /// it sits on.
    private var sheetSize: CGSize {
        let parentWidth = parentSize?.width ?? Self.fallbackWidth
        let parentHeight = parentSize?.height ?? Self.fallbackHeight

        var width = max(Self.minimumWidth, parentWidth * Self.parentFraction)
        var height = max(Self.minimumHeight, parentHeight * Self.parentFraction)

        // Never larger than the window behind it, or its edges fall outside.
        width = min(width, parentWidth)
        height = min(height, parentHeight)

        #if canImport(AppKit)
        // A sheet is presented on its parent's screen, and the visible frame
        // already excludes the menu bar and Dock.
        if let visible = (NSApplication.shared.keyWindow?.screen ?? NSScreen.main)?.visibleFrame {
            width = min(width, visible.width)
            height = min(height, visible.height)
        }
        #endif

        return CGSize(width: width, height: height)
    }

    /// How much of the parent window the sheet takes — all of it.
    private static let parentFraction: CGFloat = 1.0

    /// Below these the options row wraps and the film stops being judgeable.
    ///
    /// Smaller than they were: the settings no longer hold a column open beside
    /// the film, so the window only has to fit one row of controls and a sheet.
    fileprivate static let minimumWidth: CGFloat = 960
    fileprivate static let minimumHeight: CGFloat = 620

    /// Used when the sheet was raised without a window size to match.
    private static let fallbackWidth: CGFloat = 1100
    private static let fallbackHeight: CGFloat = 760

    // MARK: - Header

    /// The one strip of chrome on this screen: what is being printed, the panel
    /// toggles, and the actions.
    ///
    /// A single row rather than a title block above and a button bar below. Both
    /// bands were height the film could not use, and the film is the thing being
    /// judged here — so the title is one line beside its summary and Print and
    /// Cancel sit at the end of the same row.
    private var header: some View {
        HStack(spacing: 10) {
            Text("Print")
                .font(.headline)
            Text(viewModel.planSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let message = viewModel.validationMessage, !viewModel.isRunning {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(2)
                    .frame(maxWidth: 240, alignment: .trailing)
            }

            #if os(macOS)
            // The film as a file. Composed by the same `FilmComposer` the
            // emulator composes a received film with, from the same prepared
            // images the SCU would have sent — so what lands on disk is the
            // sheet the printer would have laid down, not a screenshot of the
            // preview.
            Menu {
                Button("PNG…")  { saveFilm(extension: "png") }
                Button("TIFF…") { saveFilm(extension: "tiff") }
                Button("PDF…")  { saveFilm(extension: "pdf") }
            } label: {
                if viewModel.isSavingFilm {
                    ProgressView().controlSize(.mini)
                } else {
                    Label("Save Film", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                }
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(viewModel.selection.isEmpty || viewModel.isSavingFilm)
            .help("Save the composed film as an image or a PDF")
            #endif

            Button {
                showConsole.toggle()
            } label: {
                Label(showConsole ? "Hide Console" : "Show Console",
                      systemImage: showConsole ? "sidebar.trailing" : "sidebar.right")
                    .labelStyle(.iconOnly)
            }
            .help("Show or hide the print console and give the film more room")

            if viewModel.phase == .configuring {
                KeyboardShortcutsButton(
                    title: "Print Preview Shortcuts",
                    groups: KeyboardShortcutsLegendView.printPreviewGroups)

                // The settings column is opened from "More" in the options bar,
                // beside the settings it belongs to — not from up here.

                if !viewModel.history.isEmpty {
                    Menu {
                        ForEach(viewModel.history.prefix(10)) { entry in
                            Text("\(entry.success ? "✓" : "✗") \(entry.summary)")
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Recent jobs")
                }
            }

            actions
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    /// Print and Cancel — in the top panel, beside everything else that acts on
    /// the job rather than on a cell.
    @ViewBuilder
    private var actions: some View {
        switch viewModel.phase {
        case .configuring:
            Button("Cancel") { close() }
                .keyboardShortcut(.cancelAction)
            Button(viewModel.dryRun ? "Dry Run" : "Print") {
                viewModel.print()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canPrint)
        case .preparing, .printing:
            Button("Cancel Job", role: .destructive) { viewModel.cancel() }
            // A queued job runs whether or not this sheet is open, so closing is
            // not the same as cancelling and must not be the only way out.
            if viewModel.isWaitingOnQueue {
                Button("Close") { close() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
                    .help("Leave the job in the queue and close this window")
            }
        case .finished:
            Button("Print Again") { viewModel.reset() }
            Button("Done") { close() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - While the job runs

    /// The film large, the console beside it, and the console toggleable away.
    ///
    /// A print is judged by what went on the film, so the film stays on screen
    /// for the whole job and afterwards — at the same size the preview gave it.
    /// The console is a side panel rather than something stacked under the
    /// film, so hiding it hands its width back to the film without touching
    /// the film's height.
    private var runLayout: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                previewSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showConsole {
                    consoleSplitter(containerWidth: geo.size.width)
                    consolePanel(containerWidth: geo.size.width)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Configuration

    /// Settings left, film centre, console right.
    ///
    /// The preview gets the whole middle column at full sheet height. The
    /// settings scroll in their own column instead of banding across the top,
    /// where they capped how tall the film could be drawn. Per-cell window and
    /// annotation controls live in the settings column too (below Advanced),
    /// so the right edge is dedicated to the console.
    private var configurationForm: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if showOptions {
                    optionsSidebar
                    Divider()
                }

                VStack(spacing: 0) {
                    // What a film is actually composed of — where it goes, what it
                    // is printed on, and how it is divided — rides above the picture
                    // as one slim row. Everything else is behind "More".
                    optionsBar
                    Divider()

                    previewSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showConsole {
                    consoleSplitter(containerWidth: geo.size.width)
                    consolePanel(containerWidth: geo.size.width)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// The console log panel, permanently on the right — reset each time the
    /// preview is opened (see `PrintViewModel.resetConsole()`), not just when
    /// a job finishes.
    ///
    /// Its width is the reader's, not ours: paths, UIDs and printer messages are
    /// long lines, and a column narrow enough to wrap every one of them into four
    /// is a log that has to be re-read rather than read. The width is kept across
    /// jobs and launches, and the film takes whatever is left.
    private func consolePanel(containerWidth: CGFloat) -> some View {
        PrintProgressView(viewModel: viewModel)
            .frame(width: consoleWidth(in: containerWidth))
    }

    /// The grab handle between the film and the log.
    private func consoleSplitter(containerWidth: CGFloat) -> some View {
        Divider()
            .padding(.horizontal, 3)
            .frame(width: Self.splitterWidth)
            .contentShape(Rectangle())
            #if os(macOS)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            #endif
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        // Dragging left widens the log, which is the direction
                        // it has to grow in — the film is on the other side.
                        let anchor = splitterAnchor ?? consoleWidth(in: containerWidth)
                        if splitterAnchor == nil { splitterAnchor = anchor }
                        storedConsoleWidth = Double(Self.clampConsoleWidth(
                            anchor - value.translation.width, in: containerWidth))
                    }
                    .onEnded { _ in splitterAnchor = nil }
            )
            .accessibilityLabel("Resize the console")
    }

    /// The console's width for a panel this wide: what was chosen, held inside
    /// what the window can actually give it.
    private func consoleWidth(in containerWidth: CGFloat) -> CGFloat {
        Self.clampConsoleWidth(CGFloat(storedConsoleWidth), in: containerWidth)
    }

    /// Never narrower than a readable log, and never so wide that the film it
    /// is reporting on is squeezed off the screen.
    private static func clampConsoleWidth(_ width: CGFloat, in containerWidth: CGFloat) -> CGFloat {
        guard containerWidth > 0 else { return max(minimumConsoleWidth, width) }
        let ceiling = max(minimumConsoleWidth, containerWidth * maximumConsoleFraction)
        return min(max(width, minimumConsoleWidth), ceiling)
    }

    /// Default width of the console column on the right.
    ///
    /// Wide enough for a file path and a print job UID to arrive on one or two
    /// lines rather than five, which is what 300 points made of them.
    static let defaultConsoleWidth: CGFloat = 460

    private static let minimumConsoleWidth: CGFloat = 260

    /// The most of the panel the log may take: past this the film stops being
    /// judgeable, which is what the screen is for.
    private static let maximumConsoleFraction: CGFloat = 0.6

    /// Width of the drag handle between the two panels.
    private static let splitterWidth: CGFloat = 7

    // MARK: - Saving the film

    #if os(macOS)
    /// Asks where to put the film and composes it there.
    ///
    /// The log is opened first: composing re-reads and re-renders every marked
    /// frame, so where the file went — or why it did not — is said in the same
    /// place a print says it.
    private func saveFilm(extension ext: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(viewModel.suggestedFilmFileName).\(ext)"
        #if canImport(UniformTypeIdentifiers)
        if let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        }
        #endif
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        showConsole = true
        Task { await viewModel.saveFilm(to: url) }
    }
    #endif

    /// The column of settings down the left edge.
    ///
    /// One card per subject — where the film goes, what the film is, what is on
    /// it — rather than a single run of controls under rules. A card is what makes
    /// "film size" obviously a property of the film and not of the printer, which
    /// a flat list of pickers cannot say.
    private var optionsSidebar: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                // The printer's picker, the sheet and the grid are in the bar
                // above the film; what is left here is what a film is checked
                // against rather than composed from.
                card { printerSection }
                card { marksSection }
                card { advancedSection }
                card { cellAndAnnotationSection }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: Self.sidebarWidth, alignment: .leading)
        }
        .frame(width: Self.sidebarWidth)
    }

    /// One section of the settings column.
    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    /// Width of the settings column — enough for a picker and its caption.
    private static let sidebarWidth: CGFloat = 320

    /// The film's own settings, in one row above the picture.
    ///
    /// Printer, sheet, orientation, copies, grid — the five things that change
    /// from film to film. They are here rather than in a column beside the film
    /// because every point of width that column takes is width the picture is
    /// judged without; the rest of what the print SCU can send is a setting, not
    /// a decision, and lives behind "More".
    private var optionsBar: some View {
        HStack(spacing: 12) {
            labeledControl("Printer") {
                if viewModel.printers.isEmpty {
                    Button("Add Printer…") { showPrinterManagement = true }
                } else {
                    Picker("Printer", selection: $viewModel.selectedPrinterID) {
                        ForEach(viewModel.printers) { printer in
                            Text(printer.summary).tag(Optional(printer.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .help("Which printer the film is sent to. Manage the list under "
                          + "More ▸ Printers.")
                }
            }

            // "Film Size", spelled out in front of the menu. "Film" alone read
            // as a heading for the whole bar — everything here is about the film
            // — and left the menu's own numbers ("14in x 17in") to say what the
            // control was for, which they only do if you already know sheets are
            // named by their inches.
            labeledControl("Film Size") {
                Picker("Film size", selection: $viewModel.filmSize) {
                    ForEach(PrintOptionCatalog.filmSizes, id: \.cliToken) { entry in
                        Text(entry.label).tag(entry.value)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .disabled(viewModel.layoutMode == .template)
                .help(viewModel.layoutMode == .template
                      ? "The template sets the sheet size — switch off the template to choose it."
                      : "Size of the sheet the printer loads. Must match the film in the "
                      + "printer's magazine, or the printer refuses the job.")
            }

            Picker("Orientation", selection: $viewModel.filmOrientation) {
                ForEach(PrintOptionCatalog.orientations, id: \.cliToken) { entry in
                    Text(entry.label).tag(entry.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
            .disabled(viewModel.layoutMode == .template)
            .help(viewModel.layoutMode == .template
                  ? "The template sets the orientation — switch off the template to choose it."
                  : "Which way round the sheet is used. Portrait is taller than wide; "
                  + "landscape turns it, and the layout's cells turn with it.")

            labeledControl("Copies") {
                Stepper(value: $viewModel.copies, in: 1...99) {
                    Text("\(viewModel.copies)")
                        .monospacedDigit()
                        .frame(minWidth: 18, alignment: .trailing)
                }
                .help("How many identical sets of film to print, 1 to 99. "
                      + "The printer makes the copies; the job is sent once.")
            }

            Button {
                showLayoutGallery.toggle()
            } label: {
                Label("Layout: \(layoutButtonTitle)", systemImage: "square.grid.2x2")
            }
            .help("Choose the film's layout — how many cells the sheet is divided into")
            .popover(isPresented: $showLayoutGallery, arrowEdge: .bottom) {
                FilmLayoutGalleryView(viewModel: viewModel, isPresented: $showLayoutGallery)
            }

            imageRangeControl

            Spacer(minLength: 4)

            Text(layoutCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button {
                showOptions.toggle()
            } label: {
                Label(showOptions ? "Less" : "More", systemImage: "slider.horizontal.3")
            }
            .help("Show or hide the rest of the print settings")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Whether the layout gallery popover is up.
    @State private var showLayoutGallery = false

    /// Whether the image-range popover is up.
    @State private var showImageRange = false

    /// What the popover's fields hold before "Apply" — a draft per series,
    /// keyed by series key, so typing does not filter the film mid-keystroke.
    @State private var imageRangeDraftStarts: [String: Int] = [:]
    @State private var imageRangeDraftEnds: [String: Int] = [:]

    /// Printing a run of each series rather than all of it — "images 60 to 140".
    ///
    /// A filter, not an edit: the marks it holds back keep their windowing and
    /// come straight back when the range is widened or "Load All" is pressed.
    /// Image numbers restart in every series, so the popover offers one range
    /// per marked series — a single-series film gets the one row it always had.
    @ViewBuilder
    private var imageRangeControl: some View {
        if viewModel.canRangeImages {
            Button {
                showImageRange.toggle()
            } label: {
                Label(imageRangeButtonTitle, systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Filter the film by image number — print only a run of each series, "
                  + "with the rest still marked")
            .popover(isPresented: $showImageRange, arrowEdge: .bottom) {
                imageRangePopover
                    // The numbers are read from the files, once, when the
                    // control is actually opened: a reader who never ranges the
                    // film should not pay a header read per mark for it.
                    .task {
                        await viewModel.loadImageNumbers()
                        seedImageRangeDrafts()
                    }
            }
        }
    }

    /// What the control says it does, not what it holds.
    ///
    /// "Images: 1–25" reads as a count of what is on the film; the control is a
    /// filter over the marked images, and the title has to say so before it is
    /// opened. Once a range is set the useful part is what is printing — the
    /// run itself for one series, and the count of what survives when several
    /// series each have their own run.
    private var imageRangeButtonTitle: String {
        guard viewModel.isImageRangeActive else { return "Filter Images" }
        let series = viewModel.markedSeriesRanges
        if series.count == 1, let sole = series.first,
           let range = viewModel.imageRange(forSeries: sole.key) {
            return "Filter: \(range.lowerBound)–\(range.upperBound)"
        }
        return "Filter: \(viewModel.printedItems.count) of \(viewModel.selection.count)"
    }

    private var imageRangePopover: some View {
        let series = viewModel.markedSeriesRanges

        return VStack(alignment: .leading, spacing: 10) {
            Text("Filter Images by Number")
                .font(.headline)

            if viewModel.imageNumbers.isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Reading image numbers…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(series.count == 1
                     ? "Image numbers \(series.first.map { "\($0.bounds.lowerBound)–\($0.bounds.upperBound)" } ?? "") are marked. "
                       + "Narrowing this prints only that run; the rest stay marked and keep "
                       + "their windowing."
                     : "Each series filters by its own image numbers. Narrowing a range "
                       + "prints only that run of the series; the rest stay marked and keep "
                       + "their windowing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 280, alignment: .leading)
            }

            ForEach(series) { entry in
                imageRangeRow(for: entry, showsLabel: series.count > 1)
            }
            // Typing a range against half-read numbers would filter against the
            // fallback and print a run nobody asked for.
            .disabled(viewModel.imageNumbers.isLoading)

            if viewModel.isImageRangeActive {
                Text("\(viewModel.imagesHeldBackByRange) of \(viewModel.selection.count) "
                     + "marked images are held back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Clear Filter") {
                    viewModel.loadAllImages()
                    seedImageRangeDrafts()
                    showImageRange = false
                }
                .disabled(!viewModel.isImageRangeActive)

                Spacer()

                Button("Apply") { applyImageRange(); showImageRange = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 330)
    }

    /// One series' row: its name and marked run, and the fields for its range.
    private func imageRangeRow(
        for entry: PrintViewModel.MarkedSeriesRange,
        showsLabel: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsLabel {
                Text("\(entry.label) (\(entry.bounds.lowerBound)–\(entry.bounds.upperBound))")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 8) {
                Text("From")
                TextField("", value: imageRangeDraftBinding($imageRangeDraftStarts,
                                                            key: entry.key,
                                                            fallback: entry.bounds.lowerBound),
                          format: .number)
                    .frame(width: 60)
                    .onSubmit { applyImageRange() }
                Text("to")
                TextField("", value: imageRangeDraftBinding($imageRangeDraftEnds,
                                                            key: entry.key,
                                                            fallback: entry.bounds.upperBound),
                          format: .number)
                    .frame(width: 60)
                    .onSubmit { applyImageRange() }
                if showsLabel {
                    Button("All") {
                        imageRangeDraftStarts[entry.key] = entry.bounds.lowerBound
                        imageRangeDraftEnds[entry.key] = entry.bounds.upperBound
                        viewModel.loadAllImages(forSeries: entry.key)
                    }
                    .controlSize(.small)
                    .disabled(!viewModel.isImageRangeActive(forSeries: entry.key))
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    /// A field binding into the draft dictionaries, reading the series' own
    /// bound until the reader types something.
    private func imageRangeDraftBinding(
        _ drafts: Binding<[String: Int]>,
        key: String,
        fallback: Int
    ) -> Binding<Int> {
        Binding(
            get: { drafts.wrappedValue[key] ?? fallback },
            set: { drafts.wrappedValue[key] = $0 }
        )
    }

    /// Fills the drafts from what is actually in force, so the popover opens
    /// saying what the film is doing.
    private func seedImageRangeDrafts() {
        var starts: [String: Int] = [:]
        var ends: [String: Int] = [:]
        for entry in viewModel.markedSeriesRanges {
            let range = viewModel.imageRange(forSeries: entry.key) ?? entry.bounds
            starts[entry.key] = range.lowerBound
            ends[entry.key] = range.upperBound
        }
        imageRangeDraftStarts = starts
        imageRangeDraftEnds = ends
    }

    private func applyImageRange() {
        for entry in viewModel.markedSeriesRanges {
            viewModel.setImageRange(
                from: imageRangeDraftStarts[entry.key] ?? entry.bounds.lowerBound,
                to: imageRangeDraftEnds[entry.key] ?? entry.bounds.upperBound,
                forSeries: entry.key)
        }
        // The model clamps typos back inside each series; the fields should
        // show what was actually applied.
        seedImageRangeDrafts()
    }

    /// What the layout button says it will do — the layout actually in force.
    private var layoutButtonTitle: String {
        let layout = viewModel.plan.layout
        switch viewModel.layoutMode {
        case .matchViewer: return "Viewer \(layout.rows)×\(layout.columns)"
        case .automatic:   return "Auto \(layout.rows)×\(layout.columns)"
        case .explicit:    return "\(layout.rows)×\(layout.columns)"
        case .template:    return viewModel.templatePreset.displayName
        // The format string itself: a band layout has no grid to name it by.
        case .custom:      return viewModel.customLayoutFormat?.raw ?? "Custom"
        }
    }

    // MARK: Printer

    private var printerSection: some View {
        bandGroup("Printer") {
            if viewModel.printers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No printers configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Add Printer…") { showPrinterManagement = true }
                        .controlSize(.small)
                }
            } else {
                // Which printer is chosen is settled in the bar above the film;
                // this card is what is done *to* that printer.
                if let printer = viewModel.selectedPrinter {
                    Text(printer.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // One row of equal buttons, so the column reads as a column
                // rather than as three differently-sized things.
                HStack(spacing: 6) {
                    Button("Manage…") { showPrinterManagement = true }
                        .frame(maxWidth: .infinity)
                        .help("Add, edit, or remove printers")

                    Button("Test") {
                        Task { await viewModel.testConnection() }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.isQueryingPrinter)
                    .help("C-ECHO the printer AE")

                    Button("Status") {
                        Task { await viewModel.queryPrinterStatus() }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.isQueryingPrinter)
                    .help("Query printer status (N-GET)")
                }
                .controlSize(.small)

                if viewModel.isQueryingPrinter {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Querying the printer…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let status = viewModel.printerStatus {
                    Label(
                        "Printer status: \(PrinterStatusPresentation.summary(for: status))",
                        systemImage: PrinterStatusPresentation.symbol(for: status.severity)
                    )
                    .font(.caption)
                    .foregroundStyle(PrinterStatusPresentation.color(for: status.severity))
                    .lineLimit(2)
                } else if let message = viewModel.printerQueryMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// One line explaining what the chosen layout mode will do.
    private var layoutCaption: String {
        switch viewModel.layoutMode {
        case .matchViewer:
            if let viewerLayout = viewModel.viewerLayout {
                return "Matching the viewer's \(viewerLayout.rows)×\(viewerLayout.columns) grid"
            }
            return "No viewer grid — falling back to automatic"
        case .automatic:
            return "Grid chosen to fit \(viewModel.selection.count) image(s)"
        case .explicit:
            return "Fixed grid"
        case .template:
            return "Film size and orientation are set by the preset."
        case .custom:
            guard let format = viewModel.customLayoutFormat else {
                return "\(viewModel.customLayoutText) is not an Image Display Format"
            }
            return format.summary
        }
    }

    /// A caption beside its control, sized so a row of them lines up.
    @ViewBuilder
    private func labeledControl<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            // The caption must neither wrap nor be crushed when the bar runs
            // out of width — a wrapped "Printer" reads as three words.
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            // No maxWidth clamp here: each caller sets its control's own
            // width, and a clamp narrower than that width does not shrink the
            // control — SwiftUI frames don't clip — it just lets the control
            // spill under the next caption.
            content()
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// A titled cluster of controls: the section's name, then its controls.
    @ViewBuilder
    private func bandGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    /// A titled block inside the Advanced disclosure.
    ///
    /// A plain header rather than a `GroupBox`: the disclosure already sits inside
    /// a card, and a box inside a box inside a card is three borders deep for one
    /// row of pickers.
    @ViewBuilder
    private func subsection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: Preview

    private var previewSection: some View {
        FilmPreviewView(viewModel: viewModel)
            // Tight to the panel: the film is the thing being judged, and every
            // point of padding is a point it cannot use. Its own aspect ratio
            // still decides its shape.
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
    }

    // MARK: Cell inspector

    /// Window/level, arrangement, and annotations of the cell picked in the
    /// preview — a card in the settings column, below Advanced, rather than a
    /// column of its own: the right edge is dedicated to the console, and
    /// these controls are no less at home scrolling with the rest of the
    /// settings. Every control here writes into the mark, so what it changes
    /// is what prints.
    private var cellAndAnnotationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            bandGroup("Cell") { cellInspector }
            Divider()
            bandGroup(annotationSectionTitle) { annotationInspector }
        }
    }

    /// The annotation section says whether it is editing something or setting up
    /// the next thing drawn — the controls are the same either way, and without
    /// the distinction it is unclear what a change is about to affect.
    private var annotationSectionTitle: String {
        viewModel.selectedAnnotation == nil ? "New annotations" : "Annotation"
    }

    // MARK: Annotations

    /// Text, size and colour of the selected annotation — or, with nothing
    /// selected, of the next one drawn.
    @ViewBuilder
    private var annotationInspector: some View {
        let selected = viewModel.selectedAnnotation

        VStack(alignment: .leading, spacing: 8) {
            if let selected, selected.annotation.kind != .arrow {
                stackedControl("Text") {
                    TextField("Type the annotation", text: annotationTextBinding(selected))
                        .focused($isAnnotationTextFocused)
                        .onSubmit { isAnnotationTextFocused = false }
                }
            }

            stackedControl("Size") {
                HStack(spacing: 6) {
                    Slider(
                        value: annotationScaleBinding(selected),
                        in: PrintOverlayAnnotation.minimumScale...PrintOverlayAnnotation.maximumScale)
                    Text(annotationSizeLabel(selected))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            stackedControl("Colour") {
                HStack(spacing: 6) {
                    ForEach(Self.annotationSwatches, id: \.name) { swatch in
                        swatchButton(swatch, selected: selected)
                    }
                    Spacer(minLength: 0)
                    ColorPicker("Colour", selection: annotationColorBinding(selected))
                        .labelsHidden()
                }
            }

            if viewModel.resolvedColorMode == .grayscale {
                Text("This printer prints in greys — a colour is burned in at its "
                     + "own brightness, not as a colour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let selected {
                HStack(spacing: 6) {
                    Button("Delete") {
                        viewModel.removeAnnotation(selected.annotation.id,
                                                   forItemID: selected.itemID)
                    }
                    .frame(maxWidth: .infinity)
                    .help("Remove this annotation (⌫)")

                    Button("Clear Cell") {
                        viewModel.clearAnnotations(forItemID: selected.itemID)
                    }
                    .frame(maxWidth: .infinity)
                    .help("Remove every annotation from this cell")
                }
                .controlSize(.small)
            } else {
                Text(viewModel.cellTool.isDrawing
                     ? (viewModel.cellTool == .text
                        ? "Click a cell to place text."
                        : "Drag on a cell to draw an arrow.")
                     : "Pick the text (T) or arrow (R) tool, then draw on a cell.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.hasAnnotations {
                    Button("Clear All Annotations", role: .destructive) {
                        viewModel.clearAllAnnotations()
                    }
                    .controlSize(.small)
                }
            }

            if viewModel.hasAnnotations {
                Divider()
                burnAnnotationsControl
            }
        }
    }

    /// Whether the drawn marks travel with the film.
    ///
    /// Only shown once something has been drawn: it is a decision about the
    /// annotations on this film, and offering it over an unmarked film is
    /// offering a choice about nothing.
    ///
    /// On screen the marks are a layer over the picture either way — this is
    /// about the pixels that leave. Film has nothing to carry a layer in, so a
    /// mark either becomes pixels here or does not reach the reader holding
    /// the sheet.
    @ViewBuilder
    private var burnAnnotationsControl: some View {
        Toggle("Include annotations on film", isOn: $viewModel.burnDrawnAnnotations)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .help("Burn the drawn text and arrows into the printed and saved "
                  + "pixels. Off sends the picture without them.")

        Text(viewModel.burnDrawnAnnotations
             ? "The film and any saved file carry the marks as drawn."
             : "The marks stay on screen only — the film carries the picture "
               + "without them.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if viewModel.burnDrawnAnnotations, viewModel.request.raw {
            Text("Raw pixels are being sent, so nothing can be burned in — "
                 + "the film will not carry the marks.")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One colour swatch. The reading-room set: yellow reads over lung and over
    /// mediastinum, and the rest are there for telling two arrows apart.
    private func swatchButton(
        _ swatch: (name: String, color: PrintOverlayColor),
        selected: (itemID: String, annotation: PrintOverlayAnnotation)?
    ) -> some View {
        let current = selected?.annotation.color ?? viewModel.annotationColor
        let isCurrent = current == swatch.color
        return Button {
            apply(color: swatch.color, to: selected)
        } label: {
            Circle()
                .fill(Color(red: swatch.color.red,
                            green: swatch.color.green,
                            blue: swatch.color.blue))
                .frame(width: 16, height: 16)
                .overlay(
                    Circle().strokeBorder(isCurrent ? Color.accentColor : .secondary.opacity(0.4),
                                          lineWidth: isCurrent ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .interactiveControl(cornerRadius: 12, horizontal: 3, vertical: 3)
        .accessibilityLabel(swatch.name)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        // `.railTooltip`, not `.help`: a `.plain` button's tooltip lands on a
        // wrapper the pointer never enters, so it stays silent until some
        // bordered button elsewhere in the window has shown one.
        .railTooltip(swatch.name)
    }

    private static let annotationSwatches: [(name: String, color: PrintOverlayColor)] = [
        ("Yellow", .yellow), ("White", .white), ("Red", .red),
        ("Green", .green), ("Cyan", .cyan)
    ]

    /// Writes a colour to the selected annotation, or to the next one drawn.
    private func apply(
        color: PrintOverlayColor,
        to selected: (itemID: String, annotation: PrintOverlayAnnotation)?
    ) {
        if let selected {
            viewModel.setAnnotationColor(color, id: selected.annotation.id,
                                         forItemID: selected.itemID)
        } else {
            viewModel.annotationColor = color
        }
    }

    private func annotationTextBinding(
        _ selected: (itemID: String, annotation: PrintOverlayAnnotation)
    ) -> Binding<String> {
        Binding(
            get: {
                viewModel.annotations(forItemID: selected.itemID)
                    .first { $0.id == selected.annotation.id }?.text ?? ""
            },
            set: { newValue in
                viewModel.setAnnotationText(newValue, id: selected.annotation.id,
                                            forItemID: selected.itemID)
            }
        )
    }

    /// Size of the selected annotation, or the size the next one will be drawn at.
    private func annotationScaleBinding(
        _ selected: (itemID: String, annotation: PrintOverlayAnnotation)?
    ) -> Binding<Double> {
        Binding(
            get: {
                guard let selected else { return viewModel.annotationScale }
                return viewModel.annotations(forItemID: selected.itemID)
                    .first { $0.id == selected.annotation.id }?.scale ?? viewModel.annotationScale
            },
            set: { newValue in
                guard let selected else {
                    viewModel.annotationScale = PrintOverlayAnnotation.clampScale(newValue)
                    return
                }
                viewModel.setAnnotationScale(newValue, id: selected.annotation.id,
                                             forItemID: selected.itemID)
            }
        )
    }

    private func annotationColorBinding(
        _ selected: (itemID: String, annotation: PrintOverlayAnnotation)?
    ) -> Binding<Color> {
        Binding(
            get: {
                let color = selected?.annotation.color ?? viewModel.annotationColor
                return Color(red: color.red, green: color.green, blue: color.blue)
            },
            set: { newValue in
                guard let overlayColor = PrintOverlayColor(newValue) else { return }
                apply(color: overlayColor, to: selected)
            }
        )
    }

    /// Size as a percentage of the image's height — the unit it is actually
    /// stored in, so what the slider says is what gets burned in.
    private func annotationSizeLabel(
        _ selected: (itemID: String, annotation: PrintOverlayAnnotation)?
    ) -> String {
        let scale = annotationScaleBinding(selected).wrappedValue
        return "\(Int((scale * 100).rounded()))%"
    }

    @ViewBuilder
    private var cellInspector: some View {
        if let focused = viewModel.focusedItem {
            VStack(alignment: .leading, spacing: 8) {
                Text(focused.displayLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    labeledControl("Center") {
                        TextField("Center", value: windowCenterBinding(focused), format: .number)
                            .frame(width: 80)
                            .monospacedDigit()
                    }
                    labeledControl("Width") {
                        TextField("Width", value: windowWidthBinding(focused), format: .number)
                            .frame(width: 80)
                            .monospacedDigit()
                    }

                    Menu("Presets") {
                        presetMenuItems(for: focused)
                    }
                    .frame(maxWidth: .infinity)

                    Button("Apply to All") { viewModel.applyFocusedWindowToAllCells() }
                        .help("Give every cell on this film the same window — "
                              + "other films are left as they are")
                        .disabled(viewModel.window(forItemID: focused.id) == nil)

                    Button("Revert") { viewModel.revertCell(forItemID: focused.id) }
                        .help("Undo the adjustments made here, back to how the viewer left it")
                        .disabled(!viewModel.isCellAdjusted(focused.id))

                    Button("Reset Cell") { viewModel.resetCell(forItemID: focused.id) }
                        .help("Back to the untouched frame: the file's own window, no crop")
                        .disabled(!viewModel.isCellEdited(focused))
                }
                .controlSize(.small)
                .disabled(viewModel.isCellWindowingOverridden)

                savedViewPicker(for: focused)

                if let reason = viewModel.cellWindowingBlockedReason {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if viewModel.useExplicitWindow && !viewModel.sendRawPixels {
                        Button("Use Per-Image Windows") {
                            viewModel.useExplicitWindow = false
                        }
                        .controlSize(.small)
                    }
                } else {
                    Text("Drag on a cell to \(viewModel.cellTool.displayName.lowercased()) it."
                         + (viewModel.isCellAdjusted(focused.id)
                            ? " This cell no longer follows the viewer." : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                arrangementToggle
                identificationControls
            }
            // The preset menu offers this cell's modality first, and the
            // modality comes off the file — a mark made without opening the
            // file does not carry one. Header-only, once per file, kept in the
            // same cache the range control reads.
            .task(id: focused.id) {
                await viewModel.imageNumbers.load(paths: [focused.filePath])
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Click a film cell to window or arrange it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                arrangementToggle
                identificationControls
            }
        }
    }

    /// The saved views one cell can be given, if its image has any.
    ///
    /// Shown per cell as well as job-wide because the two answer different
    /// questions: the job-wide control says how the sheet should generally
    /// relate to what was saved, and this says what *this* slice should show —
    /// a reader comparing a lung window against a bone window on one film needs
    /// to set them cell by cell.
    ///
    /// Placed outside the windowing group's `.disabled`: a saved view is not
    /// only a window, and an explicit job-wide window does not stop it carrying
    /// the zoom, rotation and inversion that were saved with it.
    @ViewBuilder
    private func savedViewPicker(for item: PrintSelectionItem) -> some View {
        let views = viewModel.savedViews(for: item)
        if !views.isEmpty {
            Divider()

            labeledControl("View") {
                Picker("View", selection: Binding(
                    get: { viewModel.savedViewSelectionLabel(forItemID: item.id) },
                    set: { label in
                        if label == PrintViewModel.defaultViewLabel {
                            viewModel.clearSavedView(forItemID: item.id)
                        } else {
                            Task {
                                // The cell the preview is drawing, so the
                                // stored Displayed Area is restored against the
                                // shape it will print in rather than against
                                // the viewer tile the mark was made in.
                                await viewModel.applySavedView(
                                    label: label, toItemID: item.id,
                                    cellSize: viewModel.lastCellSize)
                            }
                        }
                    }
                )) {
                    Text(PrintViewModel.defaultViewLabel)
                        .tag(PrintViewModel.defaultViewLabel)
                    ForEach(views) { view in
                        Text(view.label).tag(view.label)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 140)
            }
            .controlSize(.small)
            .disabled(!viewModel.savedViewsCanReachTheFilm)
            .help("Print this image with a view saved for it in the viewer")

            // A view can be applied in full and still be discarded by a
            // job-wide setting before it reaches a pixel. Said out loud, or
            // picking one is indistinguishable from a dead control.
            if let reason = viewModel.savedViewBlockedReason {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The preset menu's rows for one cell.
    ///
    /// The cell's own modality first, flat, because those are the presets a
    /// reader printing a CT actually reaches for — a CT "Lung" applied to an MR
    /// names a tissue the numbers cannot find. Every other modality stays
    /// reachable behind one submenu, for the file whose header lied or was
    /// never read.
    @ViewBuilder
    private func presetMenuItems(for focused: PrintSelectionItem) -> some View {
        let matched = viewModel.imageNumbers.modality(forPath: focused.filePath)
            .map { WindowLevelPresets.presets(for: $0) } ?? []
        if matched.isEmpty {
            // Modality unknown (not read yet, or one with no presets): offer
            // everything, grouped so "Bone" says which Bone it is.
            presetGroups(excludingModality: nil, for: focused)
        } else {
            ForEach(matched) { preset in
                presetButton(preset, showModality: false, for: focused)
            }
            Divider()
            Menu("Other Modalities") {
                presetGroups(excludingModality: matched.first?.modality, for: focused)
            }
        }
    }

    /// One submenu per modality, minus the one already shown flat.
    @ViewBuilder
    private func presetGroups(
        excludingModality excluded: String?, for focused: PrintSelectionItem
    ) -> some View {
        ForEach(WindowLevelPresets.presetsByModality.filter { $0.modality != excluded },
                id: \.modality) { group in
            Menu(group.modality) {
                ForEach(group.presets) { preset in
                    presetButton(preset, showModality: false, for: focused)
                }
            }
        }
    }

    private func presetButton(
        _ preset: WindowLevelPreset, showModality: Bool, for focused: PrintSelectionItem
    ) -> some View {
        Button((showModality ? "\(preset.modality) " : "") + preset.name
               + "  \(Int(preset.center))/\(Int(preset.width))") {
            viewModel.applyWindowPreset(preset, toItemID: focused.id)
        }
    }

    /// Whether the film names its patient.
    ///
    /// One switch, because there is one answer: the caption goes under the image
    /// it belongs to. It carries what made that picture as well as who it is of
    /// — modality, image number, slice thickness on a CT — and those differ from
    /// cell to cell, so there is nothing a single line at the foot of the sheet
    /// could say for all of them.
    @ViewBuilder
    private var identificationControls: some View {
        Toggle("Patient identification", isOn: $viewModel.showPatientIdentification)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .help("Print the patient, ID, study date, description and technique "
                  + "under each image")

        Text("A caption under each image: patient, ID and study date, the study "
             + "description, then what made the picture.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if viewModel.showPatientIdentification {
            identificationFieldToggles
            identificationTypography
        }
    }

    /// FR-006's optional fields. Each off by default: the standard caption is
    /// the caption today's films carry, and every extra line is a line of type
    /// over the picture.
    @ViewBuilder
    private var identificationFieldToggles: some View {
        identificationFieldToggle(
            "Birth date", .birthDate,
            help: "Burned into the pixels, a birth date survives later "
                + "de-identification of the file. For clinical film only.")
        identificationFieldToggle(
            "Accession number", .accessionNumber,
            help: "\"Acc:\" under the study description")
        identificationFieldToggle(
            "Institution", .institutionName,
            help: "Under the study date")
        identificationFieldToggle(
            "Series description", .seriesDescription,
            help: "Under the study description")
    }

    private func identificationFieldToggle(
        _ title: String,
        _ field: PrintIdentificationFields,
        help: String
    ) -> some View {
        Toggle(title, isOn: Binding(
            get: { viewModel.identificationFields.contains(field) },
            set: { on in
                if on { viewModel.identificationFields.insert(field) }
                else { viewModel.identificationFields.remove(field) }
            }
        ))
        .toggleStyle(.checkbox)
        .controlSize(.mini)
        .padding(.leading, 16)
        .help(help)
    }

    /// FR-006 typography. Automatic is the default and stays the
    /// recommendation — it sizes to the frame and flips for MONOCHROME1;
    /// the overrides exist for sites whose protocol dictates a look.
    @ViewBuilder
    private var identificationTypography: some View {
        Toggle("Custom caption size", isOn: $viewModel.identificationUsesCustomSize)
            .toggleStyle(.checkbox)
            .controlSize(.mini)
            .padding(.leading, 16)
            .help("Size as a percentage of the image height, "
                  + "instead of the automatic size")
        if viewModel.identificationUsesCustomSize {
            HStack(spacing: 6) {
                Slider(value: $viewModel.identificationSizePercent, in: 2...10)
                    .frame(width: 110)
                Text(String(format: "%.1f%%", viewModel.identificationSizePercent))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 32)
        }
        HStack(spacing: 6) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Caption color", selection: $viewModel.identificationForeground) {
                Text("Auto").tag(PrintAnnotationStyle.Foreground.automatic)
                Text("White").tag(PrintAnnotationStyle.Foreground.white)
                Text("Black").tag(PrintAnnotationStyle.Foreground.black)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 140)
        }
        .padding(.leading, 16)
    }

    /// Arrangement is a job-wide switch, not a windowing control, so a window
    /// override must not grey it out — and it stays reachable with no cell
    /// focused.
    private var arrangementToggle: some View {
        Toggle("Viewer arrangement", isOn: $viewModel.useViewerPresentation)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .help("Print each image zoomed, rotated and flipped as the viewer showed it")
    }

    /// Editing binding for the focused cell's window centre.
    ///
    /// Reads the mark and writes straight back to it — there is no separate
    /// editing copy that could drift from what prints.
    private func windowCenterBinding(_ item: PrintSelectionItem) -> Binding<Double> {
        Binding(
            get: { viewModel.window(forItemID: item.id)?.center ?? 0 },
            set: { newValue in
                let width = viewModel.window(forItemID: item.id)?.width ?? 400
                viewModel.setWindow(forItemID: item.id, center: newValue, width: width)
            }
        )
    }

    private func windowWidthBinding(_ item: PrintSelectionItem) -> Binding<Double> {
        Binding(
            get: { viewModel.window(forItemID: item.id)?.width ?? 0 },
            set: { newValue in
                let center = viewModel.window(forItemID: item.id)?.center ?? 0
                viewModel.setWindow(forItemID: item.id, center: center, width: newValue)
            }
        )
    }

    // MARK: Film destination

    /// The destination picker's selection: magazine, processor, or "a bin" —
    /// every BIN_i reads as the one bin choice, so changing the bin number does
    /// not deselect the picker and picking "Sorter bin" keeps the number already
    /// set rather than resetting it to 1.
    private var filmDestinationKindBinding: Binding<FilmDestination> {
        Binding(
            get: { FilmDestinationPicker.choice(for: viewModel.filmDestination) },
            set: { viewModel.filmDestination =
                FilmDestinationPicker.destination(choosing: $0, current: viewModel.filmDestination) }
        )
    }

    /// The bin number, when the destination is a bin. Held at 1 or more.
    private var filmDestinationBinBinding: Binding<Int> {
        Binding(
            get: { viewModel.filmDestination.binNumber ?? 1 },
            set: { viewModel.filmDestination = FilmDestinationPicker.bin($0) }
        )
    }

    // MARK: Marks

    /// The marked images. Film order is the viewer's order, so it is reported
    /// here rather than edited — reordering happens on screen, by arranging the
    /// tiles the film is meant to reproduce.
    private var marksSection: some View {
        bandGroup("Images (\(viewModel.selection.count))") {
            if viewModel.selection.isEmpty {
                Text("Mark images in the viewer, then return here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Button("Show List…") { showImageList = true }
                        .frame(maxWidth: .infinity)
                        .popover(isPresented: $showImageList, arrowEdge: .bottom) {
                            imageListPopover
                        }
                    Button("Clear All", role: .destructive) {
                        viewModel.selection.clear()
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.small)

                Text("In viewer order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var imageListPopover: some View {
        List {
            ForEach(Array(viewModel.selection.items.enumerated()), id: \.element.id) { index, item in
                HStack {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(item.displayLabel)
                        .lineLimit(1)
                    Spacer()
                }
            }
            .onDelete { offsets in
                viewModel.selection.remove(atOffsets: offsets)
            }
        }
        .frame(width: 320, height: 240)
    }

    // MARK: Advanced

    private var advancedSection: some View {
        DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
            // Stacked in the settings column: it is already scrolling, so
            // expanding these can never push the film out of the centre.
            VStack(alignment: .leading, spacing: 10) {
                filmAdvanced
                Divider()
                imageAdvanced
                Divider()
                renderingAdvanced
                Divider()
                executionAdvanced
            }
            .padding(.top, 8)
        }
        .font(.caption)
    }

    private var filmAdvanced: some View {
        subsection("Film session") {
            VStack(alignment: .leading, spacing: 8) {
                stackedControl("Priority") {
                    Picker("Priority", selection: $viewModel.priority) {
                        ForEach(PrintOptionCatalog.priorities, id: \.cliToken) { entry in
                            Text(entry.label).tag(entry.value)
                        }
                    }.labelsHidden()
                }
                stackedControl("Medium") {
                    Picker("Medium", selection: $viewModel.mediumType) {
                        ForEach(PrintOptionCatalog.mediumTypes, id: \.cliToken) { entry in
                            Text(entry.label).tag(entry.value)
                        }
                    }.labelsHidden()
                }
                stackedControl("Destination") {
                    // Magazine, processor, or a sorter bin. The bins are one
                    // choice with a number beside it rather than a fixed pair:
                    // PS3.3 Table C.13-1 defines BIN_i with no maximum, and a
                    // sorter with twelve bins is not served by BIN_1 and BIN_2.
                    Picker("Destination", selection: filmDestinationKindBinding) {
                        ForEach(FilmDestinationPicker.choices, id: \.label) { choice in
                            Text(choice.label).tag(choice.value)
                        }
                    }.labelsHidden()
                    if let bin = viewModel.filmDestination.binNumber {
                        HStack(spacing: 6) {
                            TextField("Bin", value: filmDestinationBinBinding, format: .number)
                                .frame(width: 60)
                                .monospacedDigit()
                            Stepper("", value: filmDestinationBinBinding,
                                    in: 1...FilmDestinationPicker.maximumOfferedBin)
                                .labelsHidden()
                            Text(FilmDestinationPicker.termAndToken(FilmDestination.bin(bin)))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .help("Film sorter bin number, 1 or more (Film Destination BIN_i, "
                              + "PS3.3 Table C.13-1). dicom-print --film-destination: "
                              + FilmDestination.catalogTokenList)
                    }
                }
                stackedControl("Session label") {
                    TextField("Optional", text: $viewModel.sessionLabel)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var imageAdvanced: some View {
        subsection("Film box & image box") {
            VStack(alignment: .leading, spacing: 8) {
                stackedControl("Scaling") {
                    Picker("Scaling", selection: $viewModel.scalingMode) {
                        ForEach(PrintScalingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }.labelsHidden()
                }
                if viewModel.scalingMode == .trueSize {
                    Text("Prints at physical size from the image's pixel spacing. "
                         + "Images without spacing fall back to Fit, with a warning. "
                         + "For projection X-ray this is detector-plane size, not anatomy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if viewModel.scalingMode == .stretch {
                    Text("Stretch distorts anatomy — not for diagnostic use. "
                         + "Applies to composed film only; a DICOM printer will fit instead.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if viewModel.scalingMode != .stretch {
                    stackedControl("Position in cell") {
                        alignmentGrid
                    }
                    if viewModel.cellAlignment != .center {
                        // Not silent: the live preview composes every cell
                        // centred (its GPU transform has no anchor), so an
                        // off-centre choice shows on the composed film — save,
                        // emulator — and not on the sheet being edited here. A
                        // real DICOM printer centres regardless.
                        Text("Applies to saved and emulator film. The preview "
                             + "shows cells centred, and a real DICOM printer "
                             + "centres regardless.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                stackedControl("Magnification") {
                    Picker("Magnification", selection: $viewModel.magnificationType) {
                        ForEach(PrintOptionCatalog.magnificationTypes, id: \.cliToken) { entry in
                            Text(entry.label).tag(entry.value)
                        }
                    }.labelsHidden()
                }
                stackedControl("Trim") {
                    Picker("Trim", selection: $viewModel.trimOption) {
                        ForEach(PrintOptionCatalog.trimOptions, id: \.cliToken) { entry in
                            Text(entry.label).tag(entry.value)
                        }
                    }.labelsHidden()
                }
                stackedControl("Border density") {
                    Picker("Border density", selection: $viewModel.borderDensity) {
                        ForEach(PrintOptionCatalog.densities, id: \.self) { density in
                            Text(density.capitalized).tag(density)
                        }
                    }.labelsHidden()
                }
                stackedControl("Empty cells") {
                    Picker("Empty image density", selection: $viewModel.emptyImageDensity) {
                        ForEach(PrintOptionCatalog.densities, id: \.self) { density in
                            Text(density.capitalized).tag(density)
                        }
                    }.labelsHidden()
                }
                stackedControl("Polarity") {
                    Picker("Polarity", selection: $viewModel.polarity) {
                        ForEach(PrintOptionCatalog.polarities, id: \.cliToken) { entry in
                            Text(entry.label).tag(entry.value)
                        }
                    }.labelsHidden()
                }
                stackedControl("Configuration info") {
                    TextField("Printer-specific", text: $viewModel.configurationInformation)
                }
                stackedControl("Annotation format ID") {
                    TextField("Required for annotations", text: $viewModel.annotationDisplayFormatID)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A 3×3 grid of anchors — reads as the cell it positions within, where a
    /// nine-item dropdown reads as a list of words (SRS FR-003).
    private var alignmentGrid: some View {
        let rows: [[PrintCellAlignment]] = [
            [.topLeft, .topCenter, .topRight],
            [.centerLeft, .center, .centerRight],
            [.bottomLeft, .bottomCenter, .bottomRight],
        ]
        return VStack(spacing: 2) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(row, id: \.self) { alignment in
                        Button {
                            viewModel.cellAlignment = alignment
                        } label: {
                            Image(systemName: viewModel.cellAlignment == alignment
                                  ? "circle.inset.filled" : "circle")
                                .font(.system(size: 9))
                                .frame(width: 22, height: 18)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(viewModel.cellAlignment == alignment
                                         ? Color.accentColor : Color.secondary)
                        .interactiveControl(cornerRadius: 5, horizontal: 1, vertical: 1)
                        .railTooltip(alignment.displayName)
                        .accessibilityLabel(alignment.displayName)
                    }
                }
            }
        }
        .padding(3)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
        .fixedSize()
    }

    /// A caption above its control, for the settings column — a label beside the
    /// control needs width the column does not have.
    @ViewBuilder
    private func stackedControl<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity)
        }
    }

    private var renderingAdvanced: some View {
        subsection("Rendering") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto-detect colour mode", isOn: $viewModel.autoDetectColorMode)
                    .help("Prints in colour when the marked images carry colour "
                          + "pixels and the printer is set up to accept them.")
                if !viewModel.autoDetectColorMode {
                    stackedControl("Color mode") {
                        Picker("Color mode", selection: $viewModel.colorMode) {
                            ForEach(PrintOptionCatalog.colorModes, id: \.cliToken) { entry in
                                Text(entry.label).tag(entry.value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                // Offered only when there is colour to lose. Colour sources
                // now keep their colour by default, so this is the switch that
                // deliberately gives it up — for monochrome film stock, where a
                // flattened grey is what the sheet can actually show.
                if viewModel.selectionHasColorImages {
                    Toggle("Print colour images as greys",
                           isOn: Binding(
                            get: { !viewModel.preservesSourceColor },
                            set: { viewModel.preservesSourceColor = !$0 }))
                        .help("Flattens colour images to greys before sending. "
                              + "Off, they print in colour.")

                    if let notice = viewModel.colorDowngradeNotice {
                        Label(notice, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Toggle("Match the viewer's window/level", isOn: $viewModel.useViewerWindow)
                Toggle("Match the viewer's zoom, rotation and flip",
                       isOn: $viewModel.useViewerPresentation)
                    .help("Prints the region and orientation you arranged on screen, "
                          + "cropped from the full-resolution frame.")
                    .disabled(viewModel.sendRawPixels || viewModel.useExplicitWindow)
                    .help("Prints what is on screen rather than the file's stored window")

                Toggle("Use an explicit window", isOn: $viewModel.useExplicitWindow)
                    .disabled(viewModel.sendRawPixels)
                if viewModel.useExplicitWindow && !viewModel.sendRawPixels {
                    HStack {
                        TextField("Center", value: $viewModel.explicitWindowCenter, format: .number)
                            .frame(width: 100)
                        TextField("Width", value: $viewModel.explicitWindowWidth, format: .number)
                            .frame(width: 100)
                    }
                }

                stackedControl("Grayscale bit depth") {
                    Picker("Grayscale bit depth", selection: $viewModel.bitDepth) {
                        ForEach(PrintOptionCatalog.bitDepths, id: \.self) { depth in
                            Text(PrintOptionCatalog.bitDepthLabel(depth)).tag(depth)
                        }
                    }
                    .labelsHidden()
                    .disabled(viewModel.sendRawPixels)
                    .help("PS3.3 Table C.13-5 allows Bits Stored of 8 or 12 on the "
                        + "Basic Grayscale Image Box. 12-bit shows smoother gradients "
                        + "on film, but only where the printer supports it.")
                }

                stackedControl("Colour palette") {
                    Picker("Colour palette", selection: Binding(
                        get: { viewModel.filmPalette },
                        set: { viewModel.applyFilmPalette($0) }
                    )) {
                        Text("None (grayscale)")
                            .tag(DICOMCore.PseudoColorPalette?.none)
                        // Grouped, because the list is long and the groups are
                        // the part that matters: the DICOM heading is a promise
                        // that those eight mean the same thing on any conforming
                        // system, which none of the others can make.
                        ForEach(DICOMCore.PseudoColorPalette.catalog, id: \.group) { entry in
                            Section(entry.group.title) {
                                ForEach(entry.palettes, id: \.self) { palette in
                                    Text(palette.displayName)
                                        .tag(DICOMCore.PseudoColorPalette?.some(palette))
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .disabled(viewModel.sendRawPixels)
                    .help("Recolours the film. Cells that were given their own "
                        + "palette keep it.")
                }

                // What colour costs, said before the job is sent rather than
                // discovered afterwards. Both of these are the standard's rules,
                // not ours: PS3.3 Table C.13-5 fixes the colour image box at
                // 8 bits per sample and allows only RGB in it, so a coloured
                // film has no deeper form and no density curve to apply.
                if viewModel.filmPalette?.isGrayscale == false, !viewModel.sendRawPixels {
                    VStack(alignment: .leading, spacing: 2) {
                        if viewModel.bitDepth > 8 {
                            Label(
                                "Colour prints at 8-bit; the \(viewModel.bitDepth)-bit "
                                + "depth applies to grayscale film only.",
                                systemImage: "info.circle")
                        }
                        if viewModel.presentationLUTShape == .linearOpticalDensity {
                            Label(
                                "Linear optical density applies to grayscale film "
                                + "only and is not applied to colour.",
                                systemImage: "info.circle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                stackedControl("Presentation LUT") {
                    Picker("Presentation LUT", selection: $viewModel.presentationLUTShape) {
                        Text("None").tag(DICOMNetwork.PresentationLUTShape?.none)
                        ForEach(PrintOptionCatalog.presentationLUTShapes, id: \.cliToken) { entry in
                            Text(entry.label).tag(Optional(entry.value))
                        }
                    }
                    .labelsHidden()
                }

                // What the rendered inverse will visibly not do — a colour cell
                // keeping its polarity, or a raw job it cannot touch at all —
                // said here rather than discovered on the film.
                if let notice = viewModel.presentationLUTNotice {
                    Label(notice, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                savedPresentationStateControls

                Toggle("Send stored pixels unprocessed (raw)", isOn: $viewModel.sendRawPixels)
                    .help("No rescale, window, or inversion. Compressed sources are still decoded.")
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The job-wide saved-view controls.
    ///
    /// Hidden entirely when the study has nothing saved for any marked image: a
    /// toggle that cannot change the film is worse than no toggle, because it
    /// invites the reader to look for an effect that was never possible.
    @ViewBuilder
    private var savedPresentationStateControls: some View {
        if viewModel.hasSavedViewsForAnyCell {
            Divider()

            Toggle("Apply saved presentation state (PR)",
                   isOn: $viewModel.applySavedPresentationStates)
                .help("Each image prints with the view saved for it in the viewer")

            if viewModel.applySavedPresentationStates {
                stackedControl("Saved view") {
                    Picker("Saved view", selection: $viewModel.defaultSavedViewLabel) {
                        Text("Most recent").tag(String?.none)
                        // The count says how many cells the label can reach. A
                        // label saved over part of a series is still worth
                        // offering, but a reader who picks it must be able to
                        // see that it lands on four cells of twenty rather than
                        // discovering it by staring at the other sixteen.
                        ForEach(viewModel.savedViewLabelsOnFilm, id: \.self) { label in
                            let covered = viewModel.cellCountCovered(byLabel: label)
                            Text("\(label) — \(covered) "
                                 + (covered == 1 ? "cell" : "cells"))
                                .tag(Optional(label))
                        }
                    }
                    .labelsHidden()
                }

                let withViews = viewModel.cellCountWithSavedViews
                let total = viewModel.printedItems.count
                Text(withViews == total
                     ? "Cells you have adjusted here keep your changes."
                     : "\(withViews) of \(total) cells have a saved view; the rest print "
                       + "as marked. Cells you have adjusted here keep your changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let reason = viewModel.savedViewBlockedReason {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var executionAdvanced: some View {
        subsection("Execution") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Check printer status before printing", isOn: $viewModel.checkStatusBeforePrinting)
                    .help("Aborts on FAILURE, warns on WARNING")
                Toggle("Verify with C-ECHO before printing", isOn: $viewModel.verifyBeforePrinting)
                Toggle("Dry run (build the film plan, send nothing)", isOn: $viewModel.dryRun)
                Stepper(value: $viewModel.retries, in: 0...5) {
                    Text("Retries: \(viewModel.retries)")
                }
                .help("Retries on connection failure")
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}

/// How the destination picker maps Film Destination (2000,0040) onto three
/// choices.
///
/// PS3.3 2026a Table C.13-1 defines MAGAZINE, PROCESSOR and BIN_i, "numbered
/// sequentially starting from 1 and no maximum is placed on the number of
/// BINs". The picker shows the two named terms and one "Sorter bin" row; the
/// bin number is a field beside it. Kept apart from the view so the mapping can
/// be tested without SwiftUI.
enum FilmDestinationPicker {

    /// The row that stands for every BIN_i in the picker.
    static let binChoice = FilmDestination.bin(1)

    /// The picker's rows: the catalogue's named terms, then one bin row.
    static let choices: [(value: FilmDestination, label: String)] = {
        var rows = PrintOptionCatalog.filmDestinations
            .filter { $0.value.binNumber == nil }
            .map { (value: $0.value, label: $0.label) }
        rows.append((value: binChoice, label: "Sorter bin"))
        return rows
    }()

    /// The stepper's ceiling. Table C.13-1 sets none; a sorter with more than
    /// this many bins is not a thing, and the field accepts any valid number.
    static let maximumOfferedBin = 999

    /// The picker row a destination is shown as: itself for the named terms,
    /// the one bin row for any BIN_i.
    static func choice(for destination: FilmDestination) -> FilmDestination {
        destination.binNumber == nil ? destination : binChoice
    }

    /// The destination a picker choice means. Choosing the bin row keeps the
    /// bin number already in force, if there is one.
    static func destination(choosing choice: FilmDestination,
                            current: FilmDestination) -> FilmDestination {
        guard choice.binNumber != nil else { return choice }
        return current.binNumber != nil ? current : binChoice
    }

    /// BIN_n for a typed number, held to the range the term allows: 1 or more,
    /// and small enough for the 16-character CS value (PS3.5 Table 6.2-1). The
    /// value goes through DICOMPrintKit's `FilmDestination(catalogToken:)` — the
    /// parser of dicom-print `--film-destination` (D242) — so the field accepts
    /// exactly the bins the CLI does.
    static func bin(_ number: Int) -> FilmDestination {
        let clamped = min(max(1, number), FilmDestination.maximumBinNumber)
        return FilmDestination(catalogToken: "bin-\(clamped)") ?? binChoice
    }

    /// The Defined Term and the dicom-print token it is spelt with, e.g.
    /// `BIN_12 (bin-12)` — DICOMPrintKit's `catalogToken` (D242).
    static func termAndToken(_ destination: FilmDestination) -> String {
        "\(destination.rawValue) (\(destination.catalogToken))"
    }
}

/// Sizes the print screen for the way it is being shown.
///
/// A modifier rather than an inline `if`: the two branches pass *different*
/// frame arguments, and `frame(width: nil, height: nil)` is not the same as no
/// frame at all — it still centres the content in a frame the window would
/// otherwise let it fill.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
private struct PrintScreenSizing: ViewModifier {
    let presentation: PrintScreenPresentation
    let sheetSize: CGSize

    func body(content: Content) -> some View {
        switch presentation {
        case .sheet:
            content.frame(width: sheetSize.width, height: sheetSize.height)
        case .window, .embedded:
            // A window is sized by the user; an embedded screen by the panel
            // it sits in. Either way only the floor is imposed — in the
            // embedded case it flows up into the shell window's minimum size.
            content.frame(
                minWidth: PrintSettingsView.minimumWidth,
                minHeight: PrintSettingsView.minimumHeight)
        }
    }
}
#endif
