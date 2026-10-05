// PrintViewModel.swift
// DICOMStudio
//
// DICOM Studio — state for the print settings sheet, printer management, and
// job execution. All print behavior comes from DICOMPrintKit; this type only
// holds UI state and sequences the calls.
//
// NEMA-verified: 2026a, checked 2026-10-05 — the job settings are DICOMNetwork enums (PrintPriority, MediumType,
// FilmDestination, FilmSize, FilmOrientation, MagnificationType, TrimOption, ImagePolarity, PresentationLUTShape),
// whose raw values were verified against PS3.3 2026a Tables C.13-1 / C.13-3 / C.13-5 / C.11-4 in DICOMNetwork; the
// two density literals BLACK are Table C.13-3 Border / Empty Image Density terms, and the hand-typed Image Display
// Format (default ROW\1,2) is validated by DICOMPrintKit's PrintImageDisplayFormat against C.13.3 before it is sent.
// The execution-status re-query shows the printer's own Execution Status (C.13-8) string unchanged.

import Foundation
import Observation
import DICOMCore
import DICOMKit
import DICOMNetwork
import DICOMPrintKit

#if canImport(CoreGraphics)
import CoreGraphics
#endif

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@MainActor
@Observable
public final class PrintViewModel {

    // MARK: - Job phase

    /// Where the sheet is in the print flow.
    public enum Phase: Sendable, Equatable {
        case configuring
        case preparing
        case printing
        case finished(success: Bool)
    }

    // MARK: - Selection

    /// The frames to print, in film-cell order.
    public var selection: PrintSelectionModel

    // MARK: - Preview editing

    /// The film cell the preview's tools act on. See
    /// `PrintViewModel+CellEditing.swift`.
    public var focusedItemID: String?

    /// The size the preview last drew a cell at, in points.
    ///
    /// The viewport for controls that live outside the preview and so have no
    /// cell geometry of their own — the sidebar's saved-view picker, which has
    /// to restore a Displayed Area against the cell the picture will print in.
    /// Every cell on a sheet is the same size, so one value serves them all.
    /// Nil until the preview has laid out. See ``recordCellSize(_:)``.
    ///
    /// `@ObservationIgnored`: this is written during layout, and observing it
    /// would feed a layout pass back into the view that produced it.
    @ObservationIgnored public internal(set) var lastCellSize: CGSize?

    /// The run of image numbers each series carries on film, keyed by
    /// ``PrintSelectionItem/seriesKey``. A series with no entry prints whole.
    /// See `PrintViewModel+ImageRange.swift`.
    public var imageRanges: [String: ClosedRange<Int>] = [:]

    /// Instance Numbers of the marked files, read on demand — what the image
    /// range matches against.
    public let imageNumbers = PrintImageNumberCache()

    /// The window each mark was *seeded* with, keyed by mark ID — the file's own
    /// resolved values, written into a mark the first time its cell is picked up
    /// so a window drag has concrete numbers to start from. See
    /// ``seedWindowIfNeeded(forItemID:)``.
    ///
    /// Kept so ``isCellEdited(_:)`` can tell a seeded window from an edited one.
    /// Seeding writes the values already on screen, so it must not count as an
    /// edit — without this baseline, merely clicking a cell lit "Reset Cell",
    /// and a seed landing *after* a reset (the file read is asynchronous)
    /// re-lit it, which read as the reset not having taken.
    var seededWindows: [String: WindowSettings] = [:]

    // MARK: - Saved presentation states (PR)

    /// Where the study's saved views are read from. See
    /// `PrintViewModel+PresentationStates.swift`.
    ///
    /// Nil keeps the controls hidden rather than offering a picker with nothing
    /// behind it — which is what a standalone print sheet or a preview gets.
    public var presentationStateStore: PresentationStateStore?

    /// The study the marks belong to, which is what saved views are filed under.
    ///
    /// Set by whoever opens the print screen, because a mark carries its series
    /// but not its study. Without it nothing can be looked up, and the sheet
    /// behaves exactly as it did before saved views existed.
    public var presentationStateStudyUID: String?

    /// Whether film cells adopt their image's saved view as the sheet is composed.
    ///
    /// **Off by default.** A saved view is a reading decision — a window dialled
    /// in to look at one thing — and the film is a different artefact from the
    /// screen it was read on. Opening the print screen with those states already
    /// baked in meant a reader who never asked for them had to notice the cells
    /// were not the plain frames, work out which of several job-wide switches was
    /// responsible, and turn it off; the film opens on the images as marked, and
    /// adopting the saved views is the deliberate act.
    ///
    /// Cells adjusted by hand on the print screen are never overwritten — see
    /// ``adoptSavedViewsWhereUntouched()``.
    public var applySavedPresentationStates: Bool = false {
        didSet {
            guard applySavedPresentationStates != oldValue else { return }
            if applySavedPresentationStates {
                adoptSavedViews()
            } else {
                clearAllSavedViews()
            }
        }
    }

    /// The adoption pass currently running, so a second request replaces it
    /// rather than racing it.
    ///
    /// Adoption writes into the marks, and every write is observed by the film
    /// preview, which reacts to a changed mark list by asking for adoption
    /// again. Left unmanaged those requests pile up: each one re-walks every
    /// cell, awaits a pixel size per cell, and hops back to the main actor
    /// after each await — so toggling the switch on a sixteen-cell film left a
    /// crowd of interleaved passes writing marks between one another's
    /// suspensions, and the tools stopped answering because the main actor was
    /// never idle. One pass at a time, newest wins.
    @ObservationIgnored var savedViewAdoptionTask: Task<Void, Never>?

    /// Starts an adoption pass, cancelling any pass already running.
    ///
    /// The cancellation is what keeps the reader in control: a switch toggled
    /// twice in a second does the work once, for the state it finished in.
    func adoptSavedViews() {
        savedViewAdoptionTask?.cancel()
        savedViewAdoptionTask = Task { [weak self] in
            await self?.adoptSavedViewsWhereUntouched()
        }
    }

    /// Which saved view the cells adopt, by name, or nil for each image's most
    /// recent. Only consulted while ``applySavedPresentationStates`` is on.
    public var defaultSavedViewLabel: String? {
        didSet {
            guard defaultSavedViewLabel != oldValue else { return }
            adoptSavedViews()
        }
    }

    /// The saved view each cell is currently showing, by mark ID.
    ///
    /// Names the view rather than holding it: the store is the authority, and a
    /// label survives the list being reloaded after a save or a delete — the
    /// same reasoning as the viewer's ``ImageViewerViewModel/selectedPresentationStateLabel``.
    var appliedSavedViews: [String: String] = [:]

    /// Source frame sizes by file path, read once and kept. Restoring a stored
    /// Displayed Area needs the image's real pixel dimensions.
    var pixelSizes: [String: CGSize] = [:]

    /// Cells picked out by hand, by mark ID. See
    /// `PrintViewModel+CellSelection.swift`.
    ///
    /// While this holds two or more, a tool acts on exactly these and the sync
    /// locks stand aside: an explicit selection is a statement the reader has
    /// just made, and a rule quietly widening it would undo the point of making
    /// it.
    public var selectedItemIDs: Set<String> = []

    /// Which cell edits are carried to the other cells as they are made.
    /// See `PrintViewModel+CellSync.swift`.
    public var cellSync: PrintCellSyncOptions = []

    /// How far a synchronised edit reaches.
    public var cellSyncScope: PrintCellSyncScope = .sameSeries

    /// What a drag on a film cell does.
    public enum CellTool: String, CaseIterable, Sendable, Identifiable {
        case window
        case zoom
        case pan
        case rotate
        case text
        case arrow

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .window: return "Window/Level"
            case .zoom:   return "Zoom"
            case .pan:    return "Pan"
            case .rotate: return "Rotate"
            case .text:   return "Text Annotation"
            case .arrow:  return "Arrow"
            }
        }

        public var symbolName: String {
            switch self {
            // The brightness sun, not the half-filled circle. The circle is
            // the same glyph the Invert button carries, mirrored — and two
            // buttons a few points apart showing the same shape is what made
            // the rail hard to scan. The sun collides with nothing on the
            // rail, says what the drag changes, and matches the viewer's W/L
            // button, so the same act shows the same icon on both screens.
            case .window: return "sun.max"
            case .zoom:   return "magnifyingglass"
            case .pan:    return "hand.draw"
            // A closed circle of arrows, not a quarter-turn glyph: the drag
            // turns the cell the whole way round, either way, and a "90°" icon
            // would promise the quarter turns the Image menu offers. The same
            // glyph the viewer's rotate tool carries, so one act shows one
            // picture on both screens.
            case .rotate: return "arrow.triangle.2.circlepath"
            case .text:   return "character.textbox"
            case .arrow:  return "arrow.up.left"
            }
        }

        /// Whether this tool draws something new rather than adjusting the picture.
        public var isDrawing: Bool {
            self == .text || self == .arrow
        }
    }

    /// The active preview tool. Windowing by default — it is the adjustment a
    /// film is actually rejected over.
    public var cellTool: CellTool = .window

    // MARK: - Drawn annotations
    //
    // Storage lives on `selection` (a `PrintSelectionModel`) rather than here,
    // keyed by image identity rather than mark ID — that is what lets the main
    // viewer show an image's annotations without ever opening this print
    // sheet. `PrintViewModel+Annotations.swift` forwards the tray's calls
    // there. See `PrintSelectionModel+Annotations.swift`.

    /// The annotation the inspector is editing, if any.
    public var selectedAnnotationID: UUID? {
        get { selection.selectedAnnotationID }
        set { selection.selectedAnnotationID = newValue }
    }

    /// Size the next annotation is drawn at, as a fraction of the image's height.
    /// Changing a selected annotation's size adopts it here too.
    public var annotationScale: Double {
        get { selection.annotationScale }
        set { selection.annotationScale = newValue }
    }

    /// Colour the next annotation is drawn in.
    public var annotationColor: PrintOverlayColor {
        get { selection.annotationColor }
        set { selection.annotationColor = newValue }
    }

    /// Whether patient identification is drawn over each image and burned into
    /// the film.
    ///
    /// One setting for both halves of the same intent: the preview overlays the
    /// text (cheap, and it moves with the cell as it is windowed and zoomed) and
    /// the print run burns those same lines into the pixels it sends. Burning is
    /// what makes it reliable — a DICOM printer draws annotation boxes to its own
    /// layout and many ignore them — and it costs one bitmap pass per film cell.
    ///
    /// On by default: film that cannot be tied to a patient is not useful film.
    public var showPatientIdentification: Bool = true

    /// Whether the reader's drawn text and arrows are burned into the film and
    /// into a saved file.
    ///
    /// On screen they are always a layer over the picture, never pixels — that
    /// is what lets them be moved, retyped and deleted. Film has no layer to
    /// carry them in, so on the way out they have to become pixels or not
    /// travel at all.
    ///
    /// On by default: a reader who drew an arrow at a finding drew it for
    /// whoever reads the film, and film that silently drops it is film that
    /// disagrees with the screen it was approved on. Off is for the case where
    /// the marks were working notes — a second read, a teaching file — and the
    /// film wanted is the clean picture.
    public var burnDrawnAnnotations: Bool = true

    // MARK: - Printers

    /// Configured printers.
    public private(set) var printers: [PrinterProfile] = []

    /// The printer the job goes to.
    public var selectedPrinterID: UUID?

    /// The selected printer, if any.
    public var selectedPrinter: PrinterProfile? {
        guard let selectedPrinterID else { return printers.first { $0.isDefault } ?? printers.first }
        return printers.first { $0.id == selectedPrinterID }
    }

    /// Last printer status query result, for the status pill.
    public private(set) var printerStatus: PrinterStatus?

    /// Whether a printer query (echo/status) is in flight.
    public private(set) var isQueryingPrinter = false

    /// Result text of the last Test Connection / Query Status action.
    public private(set) var printerQueryMessage: String?

    // MARK: - Job settings

    /// Basic settings, shown in the sheet's visible zone.
    public var copies: Int = 1
    public var layoutMode: LayoutMode = .automatic

    /// The viewer's tile grid, when the sheet was raised from a viewer showing
    /// one. Lets the film mirror the arrangement on screen cell for cell.
    public var viewerLayout: PrintLayout?
    public var layoutOption: PrintLayoutOption = .layout2x2
    public var templatePreset: PrintTemplatePreset = .grid

    /// An Image Display Format (2010,0010) typed by hand, for the films a grid
    /// cannot describe: `ROW\2,1,2` puts two images over one over two.
    ///
    /// Held as text, not as a parsed value, because it is edited a character at a
    /// time and "ROW\2," is not a layout yet — the film keeps the last one that
    /// was while the rest is typed.
    public var customLayoutText: String = "ROW\\1,2"
    public var filmSize: FilmSize = .size14InX17In
    public var filmOrientation: FilmOrientation = .portrait

    /// How images are scaled to their cells (SRS FR-003).
    public var scalingMode: PrintScalingMode = .fitToFilm

    /// Where an image sits in a cell it does not fill (SRS FR-003). Applies to
    /// composed film (preview, save, the emulator); a real printer centres.
    public var cellAlignment: PrintCellAlignment = .center

    /// Advanced settings.
    public var priority: DICOMNetwork.PrintPriority = .medium
    // Department defaults, chosen for the common radiology setup: blue-base
    // film out of the magazine, smoothed on the printer's side. Not persisted —
    // every launch starts from these, and `resetForNewFilm()` keeps a session's
    // own changes only between films, not between launches.
    public var mediumType: MediumType = .blueFilm
    public var filmDestination: FilmDestination = .magazine
    public var magnificationType: MagnificationType = .bilinear
    public var trimOption: TrimOption = .no
    public var borderDensity: String = "BLACK"
    public var emptyImageDensity: String = "BLACK"
    public var polarity: ImagePolarity = .normal
    public var colorMode: DICOMNetwork.PrintColorMode = .grayscale
    public var autoDetectColorMode: Bool = true

    /// Keep colour sources in colour when preparing the pixels.
    ///
    /// On by default. Off renders colour images as greys before they are sent,
    /// which is what a monochrome film stock wants — and the only way to get
    /// greys now that the colour mode alone no longer flattens them.
    public var preservesSourceColor: Bool = true

    /// Whether each marked file's pixels are colour, keyed by path.
    ///
    /// Filled in by ``refreshSourceColor()`` as marks arrive, because deciding
    /// the colour mode means reading Samples per Pixel (0028,0002) out of every
    /// source — file I/O that must not happen inside a computed property the
    /// view layer reads on every redraw. A path missing from the map has not
    /// been read yet and counts as monochrome until it has.
    public private(set) var sourceIsColorByPath: [String: Bool] = [:]
    public var bitDepth: Int = 8

    /// The film's pseudo-colour palette: the one every cell takes unless it has
    /// chosen its own.
    ///
    /// `nil` — the default — is a grey film. This is deliberately *not* the same
    /// control as ``presentationLUTShape``: that one is the DICOM grayscale
    /// transfer function the printer is asked to apply (PS3.3 C.11.4), while
    /// this recolours the pixels before they are ever sent. Print Management has
    /// no way to carry a palette by reference, so the colours are baked in and
    /// the printer never learns which palette produced them.
    ///
    /// Setting this writes through to every cell that has not chosen for itself,
    /// so the film and its cells never disagree about what is about to print —
    /// see ``applyFilmPalette(_:)``.
    public internal(set) var filmPalette: DICOMCore.PseudoColorPalette?

    /// The cells that chose a palette of their own, by mark ID.
    ///
    /// Which cells the film-wide picker must leave alone. Held as explicit
    /// bookkeeping rather than inferred by comparing each cell's palette against
    /// the film's previous value: that inference is only sound while nothing
    /// else can move a cell's palette, and reset, revert and saved-view adoption
    /// all can. Once a cell drifted off the film's last value it was read as
    /// having chosen for itself, and the film-wide picker went permanently dead
    /// on it.
    ///
    /// Cleared with the rest of the per-film bookkeeping in
    /// ``resetForNewFilm()``; a cell also leaves the set when it is reset,
    /// reverted, or handed back to the film default.
    var selfPalettedItemIDs: Set<String> = []

    public var presentationLUTShape: DICOMNetwork.PresentationLUTShape?
    public var sessionLabel: String = ""
    public var configurationInformation: String = ""
    public var annotationTexts: [String] = []
    public var annotationDisplayFormatID: String = ""

    /// The optional identification fields this job burns (SRS FR-006).
    ///
    /// Birth date and institution on by default — a deliberate choice, since
    /// both are burned into pixels and survive later header de-identification;
    /// film that reaches another hospital is expected to say who it is about
    /// and where it was made. Accession number and series description stay off
    /// unless asked for.
    public var identificationFields: PrintIdentificationFields = [.birthDate, .institutionName]

    /// Typography of the burned identification (SRS FR-006). Custom values
    /// feed ``identificationStyle``; the defaults are the automatic behaviour.
    public var identificationFontFamily: String = PrintAnnotationStyle.defaultFontFamily
    public var identificationUsesCustomSize: Bool = false
    public var identificationSizePercent: Double = 3.5
    public var identificationForeground: PrintAnnotationStyle.Foreground = .automatic

    /// The style the burner is handed for this job.
    ///
    /// Carries the layout as well as the typography: on a sheet cut into one
    /// cell the caption is tapered (see ``PrintAnnotationStyle/singleImageFilm``),
    /// and the flag has to be on the style so the burner and the preview — which
    /// are both handed this same value — set the caption at one size.
    public var identificationStyle: PrintAnnotationStyle {
        PrintAnnotationStyle(
            fontFamily: identificationFontFamily.trimmingCharacters(in: .whitespaces)
                .isEmpty ? PrintAnnotationStyle.defaultFontFamily : identificationFontFamily,
            sizeFraction: identificationUsesCustomSize
                ? identificationSizePercent / 100 : nil,
            foreground: identificationForeground)
        .on(cellCount: plan.cellsPerFilm)
    }

    public var useViewerWindow: Bool = true
    /// Bake each mark's zoom, pan, rotation, flip and inversion into the film.
    ///
    /// On by default: the user composed the image on screen, and the film should
    /// be that image. Turn it off to print whole, unrotated frames.
    public var useViewerPresentation: Bool = true
    public var useExplicitWindow: Bool = false
    public var explicitWindowCenter: Double = 40
    public var explicitWindowWidth: Double = 400
    public var sendRawPixels: Bool = false
    public var checkStatusBeforePrinting: Bool = true
    public var verifyBeforePrinting: Bool = false
    public var retries: Int = 0
    public var timeoutSeconds: Double = 60
    public var dryRun: Bool = false

    /// How the layout is chosen.
    public enum LayoutMode: String, CaseIterable, Sendable, Identifiable {
        case matchViewer
        case automatic
        case explicit
        case template
        /// A hand-written Image Display Format — see ``customLayoutText``.
        case custom

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .matchViewer: return "Viewer"
            case .automatic:   return "Automatic"
            case .explicit:    return "Layout"
            case .template:    return "Preset"
            case .custom:      return "Custom"
            }
        }
    }

    /// The typed format, if what is in the field is one.
    ///
    /// `nil` while the text is not a valid Image Display Format, which is what
    /// the field shows as a warning and what makes the film fall back to the
    /// automatic grid rather than silently printing 1×1.
    public var customLayoutFormat: PrintImageDisplayFormat? {
        PrintImageDisplayFormat.validated(customLayoutText)
    }

    // MARK: - Run state

    /// Current phase of the flow. The setter is internal, not private, so
    /// tests can stand a finished job up without running one.
    public internal(set) var phase: Phase = .configuring

    /// Console lines, oldest first, rendered by the shared formatter.
    public private(set) var consoleLines: [ConsoleLine] = []

    /// Fraction complete, 0...1, while printing.
    public private(set) var progress: Double = 0

    /// The most recent progress message.
    public private(set) var progressMessage: String = ""

    /// Result of the last completed job.
    public private(set) var result: PrintResult?

    /// Status of a queried print job.
    public private(set) var jobStatus: DICOMNetwork.PrintJobStatus?

    /// Submitted jobs, newest first.
    public private(set) var history: [PrintJobHistoryEntry] = []

    /// Results of re-querying past jobs from the history pane, keyed by entry.
    ///
    /// In-memory only: an execution status is what the printer says right now,
    /// so a stale answer from a previous launch would mislead.
    public private(set) var historyStatusChecks: [PrintJobHistoryEntry.ID: HistoryStatusCheck] = [:]

    /// One re-query of a past job, as the history pane renders it.
    public enum HistoryStatusCheck: Sendable, Equatable {
        case running
        /// One line per film, plus whether any film failed or errored.
        case checked(lines: [HistoryJobStatusLine], anyFailed: Bool)
        /// The entry cannot be queried — printer removed, for instance.
        case unavailable(String)
    }

    /// One film's execution status within a history re-query.
    public struct HistoryJobStatusLine: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case completed, inProgress, failed }
        public let text: String
        public let kind: Kind
    }

    /// A console line with a severity, so the view can style it.
    public struct ConsoleLine: Identifiable, Sendable, Equatable {
        public enum Level: Sendable { case info, notice, warning, failure, success }
        public let id = UUID()
        public let level: Level
        public let text: String
    }

    /// Whether a job is currently running.
    public var isRunning: Bool {
        phase == .preparing || phase == .printing
    }

    /// Whether the submitted job is sitting in the queue rather than printing.
    ///
    /// The sheet is showing progress, but nothing is happening and nothing will
    /// until the queue is resumed — so the job outlives the sheet, and the user
    /// can close it without cancelling anything.
    public var isWaitingOnQueue: Bool {
        guard let id = submittedJobID, isRunning else { return false }
        return queue.runningJobID != id
    }

    // MARK: - Dependencies

    /// The print queue every submitted job goes through. Serial: one job's
    /// association finishes before the next opens.
    public let queue: PrintQueueService

    /// The app-side audit trail: every queue action and job outcome, recorded
    /// with a timestamp and persisted locally. No user accounts are involved.
    public let auditTrail: PrintAuditTrail

    private let service: PrintService
    private let jobStatusQuerier: any PrintJobStatusQuerying
    private let printerStorage: PrinterProfileStorageService
    private let historyStorage: PrintJobHistoryStorageService
    private let statusMonitor: PrinterStatusMonitor
    private var runTask: Task<Void, Never>?
    private var monitorObservationTask: Task<Void, Never>?
    /// Whether the print screen is open and claiming full-roster polling.
    /// The queue holds its own, narrower claim — see ``reconcileMonitoring()``.
    private var isPrintScreenMonitoring = false

    /// The queue job the print sheet is currently mirroring, if any.
    private var submittedJobID: UUID?

    public init(
        selection: PrintSelectionModel = PrintSelectionModel(),
        service: PrintService = PrintService(),
        printerStorage: PrinterProfileStorageService = PrinterProfileStorageService(),
        historyStorage: PrintJobHistoryStorageService = PrintJobHistoryStorageService(),
        auditStorage: PrintAuditTrailStorageService = PrintAuditTrailStorageService(),
        statusMonitor: PrinterStatusMonitor? = nil,
        jobStatusQuerier: (any PrintJobStatusQuerying)? = nil,
        queueStorage: PrintQueueStorageService? = nil
    ) {
        self.selection = selection
        self.service = service
        self.jobStatusQuerier = jobStatusQuerier ?? service
        self.printerStorage = printerStorage
        self.historyStorage = historyStorage
        self.statusMonitor = statusMonitor ?? PrinterStatusMonitor(probe: service)
        let trail = PrintAuditTrail(storage: auditStorage)
        self.auditTrail = trail
        // `nil` storage keeps stray instances (previews, standalone viewers) and
        // tests off the real queue file; the app's shared instance passes one.
        self.queue = PrintQueueService(service: service, audit: trail, storage: queueStorage)
        loadPrinters()
        history = historyStorage.load()
        // History is recorded off the queue, not the sheet, so a job resent
        // from the queue screen lands in history like any other.
        queue.onJobFinished = { [weak self] job, outcome in
            self?.recordFinishedJob(job, outcome: outcome)
        }
        // The FR-012 offline auto-queue: a job whose printer's last monitored
        // status is offline stays queued instead of failing against a dead
        // socket. Only a monitored printer holds jobs — an unmonitored one has
        // no live status to trust, so its jobs run and fail honestly.
        queue.isPrinterReady = { [weak self] profile in
            guard let self,
                  let current = self.printers.first(where: { $0.id == profile.id }),
                  current.isMonitoringEnabled else { return true }
            return current.status != .offline
        }
        // The monitor's lifecycle follows the queue as well as the screen: a
        // waiting job keeps its printer polled even with no print screen open,
        // or nothing would ever call `reevaluate()` and release it.
        queue.onQueueChanged = { [weak self] in self?.reconcileMonitoring() }
    }

    // MARK: - Background status monitoring (FR-012)

    /// Starts full-roster polling for the print screen. Called when it appears.
    /// Safe to call repeatedly.
    public func startMonitoring() {
        isPrintScreenMonitoring = true
        reconcileMonitoring()
    }

    /// Ends the print screen's claim on polling. Called when it goes away.
    ///
    /// Not necessarily the end of polling: a printer the queue is waiting on
    /// stays watched — see ``reconcileMonitoring()``.
    public func stopMonitoring() {
        isPrintScreenMonitoring = false
        reconcileMonitoring()
    }

    /// Reconciles background polling with who actually needs it.
    ///
    /// Two things want printers watched. The print screen shows live status
    /// for every monitored printer while it is open. The queue needs the
    /// printer of a waiting job watched regardless of any screen: the FR-012
    /// offline auto-queue holds such a job until a poll reports the printer
    /// back, so polling that stopped with the screen would leave the job
    /// waiting forever. The monitor therefore covers the full roster while
    /// the screen is up, the waiting jobs' printers when only the queue needs
    /// answers, and nothing otherwise — a backgrounded app must not hold
    /// associations open on hospital printers no job is waiting for.
    ///
    /// A printer the queue is *newly* waiting on is probed immediately rather
    /// than on the poll loop's own jittered schedule: submission is when the
    /// held-or-sent decision is made, and it should be made on a fresh answer,
    /// not on whatever status was left behind when polling last stopped.
    func reconcileMonitoring() {
        // Demand is resolved against the live roster: a job's payload carries
        // the profile as it was at submission, and edits since then — host,
        // interval, monitoring switched off — belong to the current profile.
        // A deleted printer resolves to nothing; the readiness gate treats it
        // as unmonitored, so its job runs and fails honestly rather than
        // waiting on a poll that can never come.
        let demanded = queue.printersAwaitingJobs
            .compactMap { snapshot in printers.first { $0.id == snapshot.id } }
            .filter(\.isMonitoringEnabled)
        let wanted = isPrintScreenMonitoring ? printers : demanded

        guard !wanted.isEmpty else {
            monitorObservationTask?.cancel()
            monitorObservationTask = nil
            Task { [statusMonitor] in await statusMonitor.stopAll() }
            return
        }

        observeMonitorUpdates()
        Task { [weak self, statusMonitor] in
            let alreadyPolled = await statusMonitor.monitoredPrinterIDs
            await statusMonitor.sync(profiles: wanted)
            guard let self else { return }
            // Demand can shrink between the announcement and this probe —
            // enqueue announces before `processNext` runs, so a job that
            // started in the meantime needs no probe.
            let still = Set(self.queue.printersAwaitingJobs.map(\.id))
            for profile in demanded
            where still.contains(profile.id) && !alreadyPolled.contains(profile.id) {
                await statusMonitor.pollOnce(profile: profile)
            }
        }
    }

    /// Starts observing the monitor's update stream. Safe to call repeatedly —
    /// the observation task is only created once.
    private func observeMonitorUpdates() {
        guard monitorObservationTask == nil else { return }
        let monitor = statusMonitor
        monitorObservationTask = Task { [weak self] in
            for await update in await monitor.updates() {
                guard !Task.isCancelled else { return }
                self?.apply(update)
            }
        }
    }

    /// Folds one poll result into the printer list.
    func apply(_ update: PrinterStatusUpdate) {
        guard let index = printers.firstIndex(where: { $0.id == update.printerID }) else { return }
        printers[index].status = update.connectionStatus
        printers[index].lastStatusCheckDate = update.checkedAt
        printers[index].lastStatusDetail = update.detail
        // Only a printer that actually answered counts as verified.
        if update.errorDescription == nil {
            printers[index].lastVerifiedDate = update.checkedAt
        }
        // Deliberately not persisted: status is observed state, and writing
        // printer-profiles.json on every poll would rewrite the file every few
        // seconds per printer for data that is meaningless after a restart.
        if update.printerID == selectedPrinterID, let status = update.status {
            printerStatus = status
        }
        // A printer coming back is the signal a held job has been waiting for.
        if update.connectionStatus != .offline {
            queue.reevaluate()
        }
    }

    // MARK: - Printer management

    /// Reloads printers from storage and re-resolves the selected one.
    public func loadPrinters() {
        printers = printerStorage.load()
        if selectedPrinterID == nil || !printers.contains(where: { $0.id == selectedPrinterID }) {
            selectedPrinterID = (printers.first { $0.isDefault } ?? printers.first)?.id
        }
    }

    /// Adds or updates a printer, enforcing a single default.
    public func save(_ profile: PrinterProfile) {
        var updated = printers
        if profile.isDefault {
            for index in updated.indices { updated[index].isDefault = false }
        }
        if let index = updated.firstIndex(where: { $0.id == profile.id }) {
            updated[index] = profile
        } else {
            updated.append(profile)
        }
        // The first printer added is the default — otherwise nothing is selected.
        if !updated.contains(where: { $0.isDefault }), !updated.isEmpty {
            updated[0].isDefault = true
        }
        persist(updated)
        selectedPrinterID = profile.id
    }

    /// Removes a printer.
    public func delete(_ profile: PrinterProfile) {
        var updated = printers.filter { $0.id != profile.id }
        if !updated.contains(where: { $0.isDefault }), !updated.isEmpty {
            updated[0].isDefault = true
        }
        persist(updated)
        if selectedPrinterID == profile.id {
            selectedPrinterID = (updated.first { $0.isDefault } ?? updated.first)?.id
        }
    }

    /// Makes a printer the default.
    public func makeDefault(_ profile: PrinterProfile) {
        var updated = printers
        for index in updated.indices {
            updated[index].isDefault = (updated[index].id == profile.id)
        }
        persist(updated)
    }

    private func persist(_ profiles: [PrinterProfile]) {
        printers = profiles
        do {
            try printerStorage.save(profiles)
        } catch {
            append(.warning, "Could not save printers: \(error.localizedDescription)")
        }
        // Every printer edit funnels through here, so this is the one place
        // that has to tell the monitor about an added, removed or re-timed
        // printer. Reconciling (rather than syncing the roster directly) keeps
        // the queue's narrower claim intact when the print screen is closed,
        // and covers monitoring being switched on for a printer whose job is
        // already waiting. With no screen and no waiting jobs it is a no-op.
        reconcileMonitoring()
    }

    /// C-ECHO the selected printer.
    public func testConnection() async {
        guard let printer = selectedPrinter else { return }
        isQueryingPrinter = true
        printerQueryMessage = nil
        // A C-ECHO says nothing about printer status, so leaving the previous
        // N-GET result on screen would caption this probe with stale detail.
        printerStatus = nil
        defer { isQueryingPrinter = false }
        do {
            let ok = try await service.verify(profile: printer)
            printerQueryMessage = ok
                ? "✓ C-ECHO succeeded"
                : "✗ C-ECHO failed — printer AE is not responding correctly"
            updateStatus(of: printer, to: ok ? .online : .error, verified: ok)
        } catch {
            printerQueryMessage = "✗ C-ECHO failed: \(error.localizedDescription)"
            updateStatus(of: printer, to: .error, verified: false)
        }
    }

    /// N-GET the selected printer's status.
    public func queryPrinterStatus() async {
        guard let printer = selectedPrinter else { return }
        isQueryingPrinter = true
        printerQueryMessage = nil
        defer { isQueryingPrinter = false }
        do {
            let status = try await service.printerStatus(profile: printer)
            printerStatus = status
            printerQueryMessage = PrintConsoleFormatter.printerStatusText(status)
                .joined(separator: "\n")
            updateStatus(
                of: printer,
                to: Self.connectionStatus(for: status.severity),
                // A WARNING printer answered the N-GET, so the association is
                // verified even though the printer is telling us about a problem.
                verified: status.severity.acceptsJobs
            )
        } catch {
            printerStatus = nil
            printerQueryMessage = "✗ Status query failed: \(error.localizedDescription)"
            updateStatus(of: printer, to: .error, verified: false)
        }
    }

    /// Drops the last probe result.
    ///
    /// Nothing expires `printerQueryMessage` on its own, so without this the
    /// text from a probe run minutes ago reappears the next time the sheet is
    /// opened, reading as a fresh answer about the printer's current state.
    public func clearPrinterProbeResult() {
        printerQueryMessage = nil
        printerStatus = nil
    }

    /// Maps a printer's reported severity onto the shared connection-status enum.
    ///
    /// WARNING stays distinct from FAILURE: a printer low on film still prints,
    /// and collapsing the two would either hide a real fault or block usable work.
    nonisolated static func connectionStatus(for severity: PrinterStatusSeverity) -> ServerConnectionStatus {
        switch severity {
        case .normal:  return .online
        case .warning: return .warning
        case .failure: return .error
        case .unknown: return .unknown
        }
    }

    private func updateStatus(of printer: PrinterProfile, to status: ServerConnectionStatus, verified: Bool) {
        guard let index = printers.firstIndex(where: { $0.id == printer.id }) else { return }
        printers[index].status = status
        if verified { printers[index].lastVerifiedDate = Date() }
    }

    // MARK: - Request

    /// The print job the current settings describe.
    public var request: PrintJobRequest {
        let annotations = annotationTexts
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .enumerated()
            .map { DICOMNetwork.PrintAnnotation(position: UInt16($0.offset + 1), text: $0.element) }

        let layoutSelection: PrintLayoutSelection
        switch layoutMode {
        case .matchViewer:
            // Falls back to automatic if the sheet was opened without a viewer
            // grid behind it (e.g. "Print…" straight from the library).
            layoutSelection = viewerLayout.map { .custom($0) } ?? .automatic
        case .automatic: layoutSelection = .automatic
        case .explicit:  layoutSelection = .explicit(layoutOption)
        case .template:  layoutSelection = .template(templatePreset)
        case .custom:
            // Half-typed text is not a layout; the film waits rather than
            // printing the 1×1 a lenient parse would have made of it.
            layoutSelection = customLayoutFormat.map { .displayFormat($0) } ?? .automatic
        }

        let trimmedFormatID = annotationDisplayFormatID.trimmingCharacters(in: .whitespaces)
        let trimmedLabel = sessionLabel.trimmingCharacters(in: .whitespaces)
        let trimmedConfig = configurationInformation.trimmingCharacters(in: .whitespaces)

        return PrintJobRequest(
            copies: copies,
            priority: priority,
            mediumType: mediumType,
            filmDestination: filmDestination,
            sessionLabel: trimmedLabel.isEmpty ? nil : trimmedLabel,
            layoutSelection: layoutSelection,
            filmSize: filmSize,
            filmOrientation: filmOrientation,
            magnificationType: magnificationType,
            borderDensity: borderDensity,
            emptyImageDensity: emptyImageDensity,
            trimOption: trimOption,
            configurationInformation: trimmedConfig.isEmpty ? nil : trimmedConfig,
            scalingMode: scalingMode,
            cellAlignment: cellAlignment,
            polarity: polarity,
            presentationLUTShape: presentationLUTShape,
            annotations: annotations,
            annotationDisplayFormatID: trimmedFormatID.isEmpty ? nil : trimmedFormatID,
            colorMode: resolvedColorMode,
            preservesSourceColor: preservesSourceColor,
            frameSelection: .first,     // per-mark frames are applied by PrintService
            raw: sendRawPixels,
            windowSettings: (useExplicitWindow && !sendRawPixels)
                ? WindowSettings(center: explicitWindowCenter, width: explicitWindowWidth)
                : nil,
            bitDepth: sendRawPixels ? 8 : bitDepth,
            verifyFirst: verifyBeforePrinting,
            checkStatus: checkStatusBeforePrinting,
            retries: retries,
            dryRun: dryRun
        )
    }

    /// The color mode actually used.
    ///
    /// Auto-detect means detect *from the images*, with the printer as the
    /// constraint: colour is used when the marked frames actually carry colour
    /// pixels and the printer is configured to accept them. A grayscale-only
    /// printer stays grayscale however colourful the source is — it has no
    /// Basic Colour SOP class to send to — and a monochrome study stays
    /// grayscale on a colour printer, since widening greys to RGB triples the
    /// bytes on the wire and changes nothing on the film.
    ///
    /// Without auto-detect the user's own choice stands, unexamined.
    public var resolvedColorMode: DICOMNetwork.PrintColorMode {
        guard autoDetectColorMode, let printer = selectedPrinter else { return colorMode }
        guard printer.colorMode == .color else { return .grayscale }
        return selectionHasColorImages ? .color : .grayscale
    }

    /// Why this job will print in greys despite carrying colour images, if it
    /// will.
    ///
    /// Only the case worth warning about: colour pixels marked, and a printer
    /// that will not be sent them. The reverse (greys on a colour printer) costs
    /// the reader nothing, and a job with no colour in it has nothing to lose.
    public var colorDowngradeNotice: String? {
        guard selectionHasColorImages, !preservesSourceColor else { return nil }
        // Raw sends stored pixels untouched, so the flatten never runs — say
        // so rather than promising greys the film will not show.
        if sendRawPixels {
            return "Raw pixels are being sent, so these colour images keep "
                + "their colour despite \"Print colour images as greys\"."
        }
        var notice = "\"Print colour images as greys\" is on, so these colour "
            + "images will print as greys."
        // The greys are the picture's own: an explicit ask for greys outranks
        // a film palette on colour images (monochrome cells keep theirs).
        if filmPalette != nil {
            notice += " The colour palette still applies to monochrome images only."
        }
        return notice
    }

    /// What the chosen Presentation LUT will visibly not do, if anything.
    ///
    /// The rendered inverse is realised in the pixels and only for cells that
    /// leave as greys — inverting just the luminance of a colour cell would
    /// change its hue — and it cannot be rendered into a raw job's stored
    /// pixels at all. Both cases used to be silent; the film simply came out
    /// unchanged and the picker looked dead.
    public var presentationLUTNotice: String? {
        guard presentationLUTShape?.invertsPixels == true else { return nil }
        if sendRawPixels {
            return "Raw pixels are being sent, so the rendered inverse cannot "
                + "be applied. Cells will print with their stored polarity."
        }
        guard printedItems.contains(where: { cellPrintsInColor($0) }) else { return nil }
        return "The rendered inverse applies to grayscale cells only — cells "
            + "printing in colour keep their polarity, as inverting only their "
            + "luminance would change their hue."
    }

    /// Whether this job will print colour images in colour.
    ///
    /// Colour survives whenever the source has it and it is not deliberately
    /// flattened: the SOP class follows the pixels on the wire
    /// (``PrintWorkflow/execute``), so the printer's configured colour mode no
    /// longer decides this on its own.
    public var willPrintInColor: Bool {
        selectionHasColorImages && (preservesSourceColor || sendRawPixels)
    }

    /// Records what ``refreshSourceColor()`` read for one file.
    func setSourceIsColor(_ isColor: Bool, forPath path: String) {
        sourceIsColorByPath[path] = isColor
    }

    /// Whether any marked frame carries colour pixels.
    ///
    /// Read off the cached per-file photometric interpretations
    /// (``sourceIsColorByPath``), which the sheet fills in as it loads marks.
    /// Unknown files count as monochrome: a job that guessed colour and was
    /// wrong opens a Basic Colour association a grayscale printer will refuse,
    /// which is a worse failure than a grey film.
    public var selectionHasColorImages: Bool {
        printedItems.contains { sourceIsColorByPath[$0.filePath] == true }
    }

    /// The film-by-film plan for the current selection and settings.
    public var plan: PrintPlan {
        // Counted from what the films actually carry, not from every mark: an
        // image range narrows the job to a run of the series, and a plan
        // counting the marks it is holding back would report films nobody asked
        // for and page the preview past the end of the sheet.
        request.plan(forImageCount: printedItems.count)
    }

    /// One-line plan summary for the sheet header.
    public var planSummary: String {
        PrintConsoleFormatter.planSummary(plan)
    }

    /// Whether the current settings can start a job.
    public var canPrint: Bool {
        selectedPrinter != nil && !selection.isEmpty && !isRunning && validationMessage == nil
    }

    /// The first validation problem with the current settings, if any.
    public var validationMessage: String? {
        do {
            try request.validate()
            return nil
        } catch let error as PrintRequestError {
            return error.message
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Running a job

    /// Submits the current selection to the print queue.
    ///
    /// The sheet's phase, console and progress mirror the queue's execution of
    /// this job through the handlers passed at enqueue — the run itself belongs
    /// to ``queue``, which serializes it against anything else waiting.
    public func print() {
        guard let printer = selectedPrinter, !selection.isEmpty else { return }
        guard validationMessage == nil else { return }

        let items = printedItems
        let jobRequest = request
        let useViewerWindow = self.useViewerWindow
        let useViewerPresentation = self.useViewerPresentation
        let burnIdentification = self.showPatientIdentification
        // Captured now, with the rest of the job: the queue may hold this job
        // while the reader goes on drawing, and what prints is what was on the
        // film when Print was pressed.
        let drawnAnnotations = burnDrawnAnnotations ? self.annotationsForPrinting : [:]

        consoleLines = []
        result = nil
        jobStatus = nil
        progress = 0
        progressMessage = ""
        phase = .preparing

        runTask = Task { [weak self] in
            guard let self else { return }

            let plan = jobRequest.plan(forImageCount: items.count)
            self.append(.info, PrintConsoleFormatter.planSummary(plan))
            if plan.filmCount > 1 {
                for line in PrintConsoleFormatter.planDetail(plan) {
                    self.append(.info, line)
                }
            }

            if jobRequest.dryRun {
                self.append(.notice, "Dry run — nothing was sent to the printer.")
                self.phase = .finished(success: true)
                return
            }

            // Read from the files themselves, so what is burned in does not
            // depend on the preview having been opened. Captured now, before
            // enqueueing: the queue may hold the job while the sheet moves on,
            // and the job must print what was on the film when it was submitted.
            let texts = burnIdentification
                ? await self.identificationTexts(for: items) : [:]
            let identifications = self.filmIdentifications(
                for: items, texts: texts, plan: plan)

            // Burned into the pixels rather than sent as annotation boxes:
            // the caption names the image it sits under — its number, its
            // slice thickness — so it has to travel with that image, and a
            // printer lays annotation boxes out to its own configured
            // format wherever it likes.
            let annotationLines = self.identificationBurns(
                for: items, texts: texts, identifications: identifications, plan: plan)
            if !annotationLines.isEmpty {
                self.append(.info, "Burning patient identification into \(annotationLines.count) image(s)")
            }
            if !drawnAnnotations.isEmpty {
                let count = drawnAnnotations.values.reduce(0) { $0 + $1.count }
                self.append(.info,
                            "Burning \(count) drawn annotation(s) into "
                            + "\(drawnAnnotations.count) image(s)")
            }
            if !drawnAnnotations.isEmpty, jobRequest.raw {
                self.append(.warning,
                            "Raw pixels are being sent — drawn annotations are not burned in.")
            }
            // Said once, where it is decided rather than where it is skipped:
            // a film that silently arrives without the arrows the preview
            // showed is the failure this line exists to prevent.
            if !self.burnDrawnAnnotations, self.hasAnnotations {
                self.append(.notice,
                            "Drawn annotations are turned off for this job — "
                            + "the film carries the picture without them.")
            }
            if Task.isCancelled {
                self.append(.notice, "Print cancelled.")
                self.phase = .configuring
                return
            }

            let payload = PrintQueuePayload(
                items: items,
                request: jobRequest,
                profile: printer,
                useViewerWindow: useViewerWindow,
                useViewerPresentation: useViewerPresentation,
                annotations: annotationLines,
                annotationStyle: self.identificationStyle,
                drawnAnnotations: drawnAnnotations
            )

            let handlers = PrintQueueJobHandlers(
                onDiagnostic: { [weak self] diagnostic in self?.appendDiagnostic(diagnostic) },
                onConsole: { [weak self] line in self?.append(.info, line) },
                onPhase: { [weak self] printing in
                    self?.phase = printing ? .printing : .preparing
                },
                onProgress: { [weak self] fraction, message in
                    self?.progress = fraction
                    self?.progressMessage = message
                },
                onFinish: { [weak self] outcome in self?.applySheetOutcome(outcome) }
            )

            let layoutText = plan.displayFormat.isUniformGrid
                ? "\(plan.layout.rows)×\(plan.layout.columns)"
                : plan.displayFormat.raw
            self.submittedJobID = self.queue.enqueue(
                payload: payload,
                imageCount: items.count,
                filmCount: plan.filmCount,
                copies: plan.copies,
                layout: layoutText,
                handlers: handlers
            )
            if self.queue.isPaused {
                self.append(.notice, "The print queue is paused — the job starts when the queue is resumed.")
            } else if self.queue.runningJobID != self.submittedJobID {
                self.append(.info, "Queued behind the job currently printing.")
            }
        }
    }

    /// Folds the queue's outcome for the sheet-submitted job back into the
    /// sheet's own state.
    private func applySheetOutcome(_ outcome: PrintQueueOutcome) {
        submittedJobID = nil
        switch outcome {
        case .finished(let printResult, _):
            result = printResult
            progress = 1.0
            for line in PrintConsoleFormatter.printResultText(printResult) {
                append(printResult.success ? .success : .failure, line)
            }
            if printResult.printJobUIDs.count > 1 {
                append(.info, "Print job UIDs: \(printResult.printJobUIDs.joined(separator: ", "))")
            }
            phase = .finished(success: printResult.success)
        case .failed(let message):
            append(.failure, "✗ Print failed")
            append(.failure, "  Error: \(message)")
            phase = .finished(success: false)
        case .cancelled:
            append(.notice, "Print cancelled.")
            phase = .configuring
        }
    }

    // MARK: - Saving the film

    /// Whether a film is being composed for a file right now.
    ///
    /// Composing re-reads and re-renders every marked frame, so it is not
    /// instant on a full sheet — the button says so rather than looking dead.
    public private(set) var isSavingFilm = false

    /// A file name for the composed film, taken from what is on it.
    public var suggestedFilmFileName: String {
        let label = selection.items.first?.displayLabel ?? "film"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(label.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return cleaned.isEmpty ? "film" : cleaned
    }

    /// Composes the marked images into film sheets and writes them to `url`.
    ///
    /// Not a picture of the preview: the images go through the same
    /// ``PrintService/prepare(items:request:useViewerWindow:applyViewerPresentation:annotations:drawnAnnotations:onProgress:)``
    /// an actual print sends them through, and the sheet comes out of the same
    /// ``FilmComposer`` the printer emulator composes a received film with. What
    /// lands on disk is therefore the film the printer would have laid down,
    /// identification band, annotations, spillover and all.
    ///
    /// A PDF holds every film of the job as one page each; PNG and TIFF hold one
    /// sheet apiece, so a job spilling onto a second film writes two files.
    ///
    /// - Returns: `nil` on success, or the reason it failed.
    @discardableResult
    public func saveFilm(to url: URL) async -> String? {
        guard !selection.isEmpty else { return "Nothing is marked." }
        guard !isSavingFilm else { return nil }

        isSavingFilm = true
        defer { isSavingFilm = false }

        let items = printedItems
        let jobRequest = request
        let plan = jobRequest.plan(forImageCount: items.count)
        append(.info, "Composing \(items.count) image(s) into "
               + "\(plan.filmCount) film(s) for \(url.lastPathComponent)…")

        do {
            let texts = showPatientIdentification
                ? await identificationTexts(for: items) : [:]
            let identifications = filmIdentifications(for: items, texts: texts, plan: plan)
            let annotationLines = identificationBurns(
                for: items, texts: texts, identifications: identifications, plan: plan)
            let images = try await service.prepare(
                items: items,
                request: jobRequest,
                useViewerWindow: useViewerWindow,
                applyViewerPresentation: useViewerPresentation,
                annotations: annotationLines,
                annotationStyle: identificationStyle,
                drawnAnnotations: burnDrawnAnnotations ? annotationsForPrinting : [:])

            // Rasterizing a 14×17 sheet at 300 dpi is tens of megapixels of
            // drawing; done on the main actor it stalls the film it is drawing.
            let composeRequest = jobRequest
            let written = try await Task.detached(priority: .userInitiated) {
                let films = try PrintSCPSimulator().composeFilms(
                    images: images,
                    request: composeRequest,
                    settings: PrintSCPSettings(),
                    callingAETitle: "DICOMSTUDIO")
                return try Self.writeFilms(films, to: url)
            }.value

            for name in written { append(.success, "Saved film to \(name)") }
            return nil
        } catch {
            let message: String
            switch error {
            case let error as PrintRequestError:      message = error.message
            case let error as FilmCompositionError:   message = error.description
            case let error as PrintSinkError:         message = error.description
            default:                                  message = error.localizedDescription
            }
            append(.failure, "Failed to save the film: \(message)")
            return message
        }
    }

    /// Writes composed sheets to `url`, in the format its extension names.
    ///
    /// - Returns: the names of the files written.
    nonisolated private static func writeFilms(
        _ films: [ComposedFilm], to url: URL
    ) throws -> [String] {
        guard !films.isEmpty else { return [] }

        // A PDF is a document, so every sheet of the job is a page of it.
        if url.pathExtension.lowercased() == "pdf" {
            try PDFSink.write(films: films, to: url)
            return [url.lastPathComponent]
        }

        let format: ImageSink.Format =
            ["tif", "tiff"].contains(url.pathExtension.lowercased()) ? .tiff : .png
        guard films.count > 1 else {
            try ImageSink.write(film: films[0], to: url, format: format)
            return [url.lastPathComponent]
        }

        // An image file holds one picture and a film is one sheet, so a job that
        // spilled writes one file per sheet, numbered as the films are.
        let base = url.deletingPathExtension()
        let ext = url.pathExtension
        return try films.enumerated().map { index, film in
            let target = URL(fileURLWithPath: "\(base.path)-\(index + 1)")
                .appendingPathExtension(ext)
            try ImageSink.write(film: film, to: target, format: format)
            return target.lastPathComponent
        }
    }

    /// Cancels the sheet's job — still-preparing, waiting in the queue, or
    /// mid-print.
    ///
    /// The SCU tears the association down on cancellation and issues a
    /// best-effort Film Session N-DELETE, so a cancelled job does not leave the
    /// printer holding a session.
    public func cancel() {
        runTask?.cancel()
        runTask = nil
        if let id = submittedJobID {
            queue.stop(id)
        }
    }

    /// Queries the status of a print job from the last result.
    public func refreshJobStatus(printJobUID: String) async {
        guard let printer = selectedPrinter else { return }
        do {
            jobStatus = try await jobStatusQuerier.jobStatus(profile: printer, printJobUID: printJobUID)
            for line in PrintConsoleFormatter.jobStatusText(jobStatus!) {
                append(.info, line)
            }
        } catch {
            append(.failure, "Job status query failed: \(error.localizedDescription)")
        }
    }

    // MARK: - History

    /// Re-queries the execution status of a past job from the history pane.
    ///
    /// The entry stores its Print Job UIDs precisely so "did that print?" can
    /// be asked again later. The printer is found by name — the profile the
    /// job was sent to may have been edited or removed since.
    public func refreshHistoryStatus(for entry: PrintJobHistoryEntry) async {
        guard !entry.printJobUIDs.isEmpty else {
            historyStatusChecks[entry.id] = .unavailable(
                "The printer did not return job UIDs for this job, so it cannot be queried.")
            return
        }
        guard let printer = printers.first(where: { $0.name == entry.printerName }) else {
            historyStatusChecks[entry.id] = .unavailable(
                "Printer “\(entry.printerName)” is no longer configured.")
            return
        }
        historyStatusChecks[entry.id] = .running
        var lines: [HistoryJobStatusLine] = []
        var anyFailed = false
        for (index, uid) in entry.printJobUIDs.enumerated() {
            // Multi-film jobs label each line; a single film speaks for the job.
            let prefix = entry.printJobUIDs.count > 1 ? "Film \(index + 1): " : ""
            do {
                let status = try await jobStatusQuerier.jobStatus(profile: printer, printJobUID: uid)
                let info = status.executionStatusInfo.map { " (\($0))" } ?? ""
                let kind: HistoryJobStatusLine.Kind = status.isFailed ? .failed
                    : (status.isCompleted ? .completed : .inProgress)
                lines.append(HistoryJobStatusLine(
                    text: "\(prefix)\(status.executionStatus)\(info)", kind: kind))
                if status.isFailed { anyFailed = true }
            } catch {
                lines.append(HistoryJobStatusLine(
                    text: "\(prefix)Query failed — \(error.localizedDescription)", kind: .failed))
                anyFailed = true
            }
        }
        historyStatusChecks[entry.id] = .checked(lines: lines, anyFailed: anyFailed)
    }

    /// Removes all history entries, on disk as well. The removal itself is
    /// recorded in the audit trail — a wiped history should not be silent.
    public func clearHistory() {
        let removed = history.count
        history = []
        historyStatusChecks = [:]
        try? historyStorage.save(history)
        auditTrail.record(.historyCleared, detail: "\(removed) entr\(removed == 1 ? "y" : "ies") removed")
    }

    /// The history in its on-disk JSON form, for "Export…".
    public func historyExportData() throws -> Data {
        try PrintJobHistoryStorageService.exportData(history)
    }

    /// The history as CSV, one row per job.
    public func historyCSVData() -> Data {
        var lines = ["date,printer,images,films,copies,layout,success,print_job_uids,film_session_uid,error"]
        let formatter = ISO8601DateFormatter()
        for entry in history {
            lines.append([
                formatter.string(from: entry.date),
                entry.printerName,
                String(entry.imageCount),
                String(entry.filmCount),
                String(entry.copies),
                entry.layout,
                entry.success ? "true" : "false",
                entry.printJobUIDs.joined(separator: " "),
                entry.filmSessionUID ?? "",
                entry.errorMessage ?? ""
            ].map { field -> String in
                guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
                return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
            }.joined(separator: ","))
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    #if canImport(CoreGraphics) && canImport(CoreText)
    /// The history as a paginated PDF report — the form a job record is asked
    /// for when it has to be filed or handed to someone.
    public func historyPDFData() throws -> Data {
        try PrintReportPDF.historyReport(history)
    }
    #endif

    // MARK: - Completion

    /// Records a finished queue job in the history — called by the queue for
    /// every job it finishes, whether the sheet or the queue screen sent it.
    private func recordFinishedJob(_ job: PrintQueueJob, outcome: PrintQueueOutcome) {
        let entry: PrintJobHistoryEntry
        switch outcome {
        case .finished(let result, let preparedCount):
            entry = PrintJobHistoryEntry(
                printerName: job.printerName,
                // The prepared count is what actually left; the planned count
                // stands in only if preparation never got that far.
                imageCount: preparedCount > 0 ? preparedCount : job.imageCount,
                filmCount: job.filmCount,
                copies: job.copies,
                layout: job.layout,
                success: result.success,
                printJobUIDs: result.printJobUIDs,
                filmSessionUID: result.filmSessionUID,
                errorMessage: result.errorMessage
            )
        case .failed(let message):
            entry = PrintJobHistoryEntry(
                printerName: job.printerName,
                imageCount: job.imageCount,
                filmCount: job.filmCount,
                copies: job.copies,
                layout: job.layout,
                success: false,
                errorMessage: message
            )
        case .cancelled:
            // A cancelled job never reached the printer; the audit trail keeps
            // the stop, and history stays a record of jobs that were sent.
            return
        }
        history.insert(entry, at: 0)
        try? historyStorage.save(history)
    }

    // MARK: - Console

    private func appendDiagnostic(_ diagnostic: PrintDiagnostic) {
        switch diagnostic {
        case .info(let text):    append(.info, text)
        case .notice(let text):  append(.notice, text)
        case .warning(let text): append(.warning, text)
        case .event(let event):  append(event.isFault ? .warning : .info, event.summary)
        }
    }

    private func append(_ level: ConsoleLine.Level, _ text: String) {
        consoleLines.append(ConsoleLine(level: level, text: text))
    }

    /// Resets the sheet to configuring after a finished job.
    public func reset() {
        phase = .configuring
        progress = 0
        progressMessage = ""
        result = nil
        jobStatus = nil
    }

    /// Clears the console log — called when the print preview is (re)opened, so
    /// a prior job's lines don't linger on the next look at the film.
    public func resetConsole() {
        consoleLines = []
    }

    /// The marks the film was last put back to a fresh sheet for, as
    /// ``PrintSelectionItem/id``s in film order. What
    /// ``resetForNewFilmIfNeeded()`` compares against; nil until the first
    /// reset, so the first visit always starts clean.
    ///
    /// `@ObservationIgnored`: bookkeeping between visits, not screen state —
    /// nothing draws from it.
    @ObservationIgnored private var freshFilmMarkIDs: [String]?

    /// Puts the film back to a fresh sheet — unless it is the *same* film.
    ///
    /// Opening the print screen is a request to see the film, not an order to
    /// tear it up: a reader who half-composes a sheet, steps back to the viewer
    /// to check something, and opens the screen again is returning to work in
    /// progress, and wiping it on the way in is the "reset issue" — a film
    /// lost to a click that meant only "show me the film".
    ///
    /// So the reset runs only when this visit is genuinely a *new* film:
    ///
    /// - The marks changed — images added, removed, or reordered since the
    ///   sheet was last cut. The film described the old tray; tool work, ranges
    ///   and cached numbers on it answer for images that are no longer there
    ///   (or are there differently), which is exactly what
    ///   ``resetForNewFilm()`` exists to take off.
    /// - The last job finished. A printed film is done — its outcome is not
    ///   the next film's outcome, and coming back to the screen after "Done"
    ///   means starting the next sheet, not re-reading the old run.
    ///
    /// A job still on the wire is left alone either way when the marks stand:
    /// reopening the screen mid-print shows the run, it does not tear it down.
    public func resetForNewFilmIfNeeded() {
        let markIDs = selection.items.map(\.id)
        if case .finished = phase {
            // Printed (or failed): the next visit is the next film.
        } else if markIDs == freshFilmMarkIDs {
            return
        }
        resetForNewFilm()
    }

    /// Puts the film back to a fresh sheet, for a new set of marks.
    ///
    /// Every launch of the print screen starts from the tray as it stands: all
    /// the marked images, each one as it was picked, with the tool work of
    /// previous visits taken off. Composing a film is a job of work, and the
    /// film screen is where it is done and where it stays — a zoom or a window
    /// applied on one visit is not a property of the image, and finding it
    /// still on the cell next time is finding a film half-composed by a session
    /// nobody remembers. What is *drawn* on an image is different in kind: a
    /// reader marking a finding with an arrow means the finding, not the sheet,
    /// so annotations survive the reset and travel with the image — see
    /// ``resetCellToolsForNewFilm()``.
    ///
    /// The print screen is kept alive between visits so that reopening it is
    /// instant and so the printer stays chosen — but everything that describes
    /// *this film* is about how the last sheet was composed. A range reading
    /// "60 to 140" filters a series that may no longer be marked; image numbers
    /// cached from the old paths answer for files that are not on the film.
    /// Carried over, each of them silently prints something other than what was
    /// ticked.
    ///
    /// What survives is the printer: which device is selected, the profiles
    /// themselves, and the connection settings that describe how to reach it.
    /// That is infrastructure — the reader configured it once and would have to
    /// re-pick it on every visit otherwise. *Everything else* goes back to its
    /// default, including the film's own description (size, orientation, medium,
    /// layout) and every rendering choice (palette, presentation LUT, window
    /// switches, bit depth) — see ``resetJobSettingsToDefaults()``. A palette or
    /// a LUT left over from the last visit recolours a film nobody asked to have
    /// recoloured, and reads as the screen having remembered a decision that was
    /// only ever about the previous sheet. The tools and the locks do not
    /// survive either; see ``resetPreviewTools()``.
    public func resetForNewFilm() {
        // The marks this fresh sheet is being cut for — what
        // ``resetForNewFilmIfNeeded()`` compares the next visit against.
        freshFilmMarkIDs = selection.items.map(\.id)

        resetPreviewTools()
        resetJobSettingsToDefaults()
        // The ranges filter by numbers from the previous series.
        imageRanges = [:]
        imageNumbers.clear()

        // Drawn text and arrows are keyed by image identity, not by mark, so
        // they are not cleared here purely because the marks are new — an
        // image carried over into the next film keeps what was drawn on it.
        // `pruneAnnotations()` (called when marks change) drops annotations
        // for images no mark points at anymore. Only the editing selection
        // goes: nothing is being edited on a film just opened.
        selectedAnnotationID = nil

        // Hand adjustments defend a cell from the viewer while a film is being
        // composed; they must not defend it from the *next* film. Left set, the
        // flag is permanent — the screen outlives a visit — so a cell windowed
        // in the preview once would ignore every later zoom, turn and window the
        // reader applied in the viewer, and reopening the screen would show the
        // stale arrangement with no way back short of "reset cell". Reverted,
        // not just unflagged: the viewer's re-sync only reaches marks on
        // screen, and the rest must not keep a cancelled visit's edits.
        selection.revertAllAdjustments()

        // …and then the marks are put back to the untouched frame. Reverting
        // only undoes what *this screen* did; a mark also carries the window
        // and arrangement it was made with in the viewer, and the film opens
        // showing the images plainly rather than wearing a reading session's
        // zooms.
        resetCellToolsForNewFilm()

        // Nothing on this film has been picked out or focused yet.
        selectedItemIDs = []
        focusedItemID = nil

        // An adoption pass from the previous visit is writing into marks this
        // reset has just put back. Cancelled *before* the bookkeeping is cleared,
        // so it cannot land after and leave cells wearing states the film no
        // longer claims to have applied — which is what made a reopened screen
        // show the last visit's arrangement.
        savedViewAdoptionTask?.cancel()
        savedViewAdoptionTask = nil

        // The previous film's adopted views describe cells that no longer exist,
        // and the reset above has just put every mark back to how it was made.
        appliedSavedViews = [:]

        // The switch is a per-visit decision, not a habit: the film opens on the
        // images as marked, whatever the reader turned on last time.
        //
        // Through the property, not the stored `_` backing: an `@Observable`
        // underscore write skips the observation registrar, so the Toggle bound
        // to this would keep drawing itself on while the model read off. The
        // `didSet` it fires is harmless and in fact wanted — `clearAllSavedViews`
        // over the emptied bookkeeping is a no-op, and going through the property
        // is what keeps a reopened screen's switch honest.
        applySavedPresentationStates = false

        // Nothing is adopted as the screen opens. A reader who wants the saved
        // views on the film asks for them with the switch, and that is what
        // starts the pass — see ``applySavedPresentationStates``.

        // A finished job's outcome is not this film's outcome.
        reset()
        resetConsole()
    }

    /// Puts every basic and advanced job setting back to its default.
    ///
    /// The film screen is kept alive between visits, so each of these is a
    /// value the *previous* visit chose. Carried over they are invisible
    /// decisions: the reader opens the screen on a new study, sees a coloured
    /// or inverted film, and has no reason to suspect a setting three
    /// disclosure groups down is responsible — the images look wrong rather
    /// than the settings looking changed. A launch is therefore a clean sheet.
    ///
    /// The printer is deliberately *not* reset — neither the selection, the
    /// stored profiles, nor the connection settings. Which device the film goes
    /// to is infrastructure the department configured, not a description of
    /// this film, and clearing it would make every launch begin by re-picking a
    /// printer. ``timeoutSeconds`` and ``retries`` belong to that same
    /// connection story and stay with it.
    ///
    /// Values are written literally rather than by assigning a fresh
    /// `PrintViewModel`: the screen's identity, its selection model and its
    /// printer list all have to survive, and a property added later should show
    /// up here as a deliberate decision about whether it describes the film or
    /// the department.
    func resetJobSettingsToDefaults() {
        // Film description — what sheet this is.
        copies = 1
        // "Match the viewer" is not a preference the reader set on the last
        // film — it is the launcher saying this film mirrors the grid on
        // screen, and ``viewerLayout`` is that grid. Clearing the mode while
        // the grid stands would throw away the arrangement the film was opened
        // *for*. With no grid there is nothing to match, so it falls back.
        if viewerLayout == nil {
            layoutMode = .automatic
        }
        layoutOption = .layout2x2
        templatePreset = .grid
        customLayoutText = "ROW\\1,2"
        filmSize = .size14InX17In
        filmOrientation = .portrait
        scalingMode = .fitToFilm
        cellAlignment = .center

        // Film session and image box.
        priority = .medium
        mediumType = .blueFilm
        filmDestination = .magazine
        magnificationType = .bilinear
        trimOption = .no
        borderDensity = "BLACK"
        emptyImageDensity = "BLACK"
        polarity = .normal
        sessionLabel = ""
        configurationInformation = ""
        annotationTexts = []
        annotationDisplayFormatID = ""

        // Rendering. The palette and the presentation LUT are the two that
        // prompted this: both silently restyle every cell on the sheet.
        //
        // The palette goes through ``applyFilmPalette(_:)`` so the cells are
        // carried back with it. Ordering matters — this runs before
        // `resetCellToolsForNewFilm()`, which clears the cell presentations and
        // then re-reads `filmPalette` to decide what the fresh film claims.
        applyFilmPalette(nil)
        presentationLUTShape = nil
        colorMode = .grayscale
        autoDetectColorMode = true
        preservesSourceColor = true
        bitDepth = 8
        useViewerWindow = true
        useViewerPresentation = true
        useExplicitWindow = false
        explicitWindowCenter = 40
        explicitWindowWidth = 400
        sendRawPixels = false

        // Identification: what gets burned into the film's corners.
        showPatientIdentification = true
        burnDrawnAnnotations = true
        identificationFields = [.birthDate, .institutionName]
        identificationFontFamily = PrintAnnotationStyle.defaultFontFamily
        identificationUsesCustomSize = false
        identificationSizePercent = 3.5
        identificationForeground = .automatic

        // Execution guards. Not the printer's connection settings — these say
        // how carefully to approach a job, which is a per-film decision.
        checkStatusBeforePrinting = true
        verifyBeforePrinting = false
        dryRun = false

        // A previous visit's status reading describes a query made then, and
        // the message beside it names an action nobody on this film took.
        printerStatus = nil
        printerQueryMessage = nil

        // Colour detection is a cache keyed by file path, and the paths on the
        // next film may not be these. Re-read on demand.
        sourceIsColorByPath = [:]
    }

    /// Puts the preview's tools and locks back to how the screen opens.
    ///
    /// A mode is only safe to leave lying around while the thing it acts on is
    /// still on screen. The preview is opened, worked in and closed, and the
    /// state it leaves behind is invisible from the viewer — so a reader who
    /// closed the screen with the pan tool armed and every lock shut comes back,
    /// drags a cell to window it, and instead slides all four cells sideways.
    /// The first drag of a visit is the one that has to behave, and there is no
    /// way to see what is armed before making it.
    ///
    /// So the screen always opens the same way: windowing, nothing locked,
    /// nothing picked out, scope back to the series. Habits that outlive a visit
    /// belong to the job settings — printer, film size, medium — not here.
    public func resetPreviewTools() {
        cellTool = .window
        cellSync = []
        cellSyncScope = .sameSeries
        selectedItemIDs = []
        focusedItemID = nil
        selectedAnnotationID = nil
        annotationScale = PrintOverlayAnnotation.defaultScale
        annotationColor = .yellow
    }
}
