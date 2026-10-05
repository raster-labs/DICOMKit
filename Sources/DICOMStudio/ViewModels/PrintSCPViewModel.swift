// PrintSCPViewModel.swift
// DICOMStudio
//
// DICOM Studio — state for the Print SCP screen: Studio acting as a DICOM
// printer that any Print SCU (modality, workstation, `dicom-print send`,
// DCMTK's `dcmprscu`) can send film to.
//
// The view model owns the listener's lifetime and turns its event stream into
// UI state. Everything else is shared code: `DICOMPrintServer` speaks the
// protocol, `FilmComposer` lays out the sheet, and the output sinks write it —
// so what appears on this screen is the same film a headless emulator produces.
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: the reported Printer Status
// and Status Info (PS3.3 2026a Table C.13-9 / C.13.9.1) are DICOMPrintKit's EmulatedPrinterStatus values,
// pushed to the handler unchanged, and every log line is worded by PrintSCPConsole.

import Foundation
import Observation
import DICOMNetwork
import DICOMPrintKit

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@MainActor
@Observable
public final class PrintSCPViewModel {

    // MARK: - Configuration

    /// The emulator's settings. Persisted on start and whenever the
    /// configuration sheet is committed.
    public var settings: PrintSCPSettings

    /// Whether the configuration sheet is showing.
    public var isConfiguring = false

    // MARK: - Listener state

    /// Whether the printer is listening.
    public private(set) var isRunning = false

    /// Whether a start or stop is in flight, so the button cannot be re-entered.
    public private(set) var isBusy = false

    /// The port actually bound (differs from the configured port only when 0).
    public private(set) var boundPort: UInt16 = 0

    /// One-line status shown beside the running indicator.
    public private(set) var statusMessage = "Printer stopped"

    /// The last start failure, shown inline so a port clash is not a log line
    /// the user has to go looking for.
    public private(set) var startErrorMessage: String?

    // MARK: - Received films

    /// Films received, newest first.
    public private(set) var films: [ReceivedFilmRecord] = []

    /// The film shown in the preview.
    public var selectedFilmID: ReceivedFilmRecord.ID?

    /// Bytes the retained films occupy.
    public private(set) var retainedBytes = 0

    /// Films evicted from the list to stay inside the retention limits.
    public private(set) var evictedFilmCount = 0

    // MARK: - Log and counters

    /// The event log, newest first.
    public private(set) var log: [PrintSCPLogEntry] = []

    /// Session totals, tallied by the shared counter the CLI also reports with.
    public private(set) var counters = PrintSCPSessionCounters()

    /// Associations accepted since the listener started.
    public var associationCount: Int { counters.associations }

    /// Films printed (N-ACTION) since the listener started.
    public var filmCount: Int { counters.films }

    /// Failed DIMSE requests and transport errors since the listener started.
    public var errorCount: Int { counters.errors }

    /// Files auto-saved since the listener started, newest first.
    public private(set) var savedFiles: [URL] = []

    /// Longest the log grows before the oldest lines are dropped. A modality
    /// left running overnight would otherwise fill memory with text.
    public static let logLimit = 500

    // MARK: - Collaborators

    private let service: PrintSCPService
    private let storage: PrintSCPSettingsStorageService

    private var server: DICOMPrintServer?
    private var handler: FilmComposingPrintHandler?
    private var screen: ScreenSink?
    private var eventTask: Task<Void, Never>?
    private var filmTask: Task<Void, Never>?

    public init(
        service: PrintSCPService = PrintSCPService(),
        storage: PrintSCPSettingsStorageService = PrintSCPSettingsStorageService()
    ) {
        self.service = service
        self.storage = storage
        self.settings = storage.load()
    }

    // MARK: - Derived state

    /// The selected film, if one is selected and still retained.
    public var selectedFilm: ReceivedFilmRecord? {
        guard let selectedFilmID else { return films.first }
        return films.first { $0.id == selectedFilmID } ?? films.first
    }

    /// "DCMPRINT @ 11113" — the address to configure on the sending device.
    public var endpointDescription: String {
        let port = isRunning && boundPort != 0 ? Int(boundPort) : settings.port
        return "\(settings.effectiveAETitle) : \(port)"
    }

    /// Retained-film footprint, formatted for the list header.
    public var retainedSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(retainedBytes), countStyle: .memory)
    }

    /// CUPS queues available for the paper-output picker.
    public func availablePaperQueues() -> [String] {
        service.availablePaperQueues()
    }

    // MARK: - Settings

    /// Persists the settings. Silent on failure — a settings file that cannot
    /// be written must not stop the printer from running this session.
    public func saveSettings() {
        try? storage.save(settings)
    }

    /// Pushes a changed printer status to a running listener, so an SCU's N-GET
    /// sees the new state without a restart.
    public func applyPrinterStatus() {
        saveSettings()
        guard let handler else { return }
        let status = settings.reportedPrinterStatus
        Task { await handler.setStatus(status) }
        append(.info, "Printer status set to \(status.status) (\(settings.effectivePrinterStatusInfo))")
    }

    // MARK: - Lifecycle

    /// Starts or stops the listener.
    public func toggle() async {
        if isRunning {
            await stop()
        } else {
            await start()
        }
    }

    /// Starts listening for Print SCUs.
    public func start() async {
        guard !isRunning, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        startErrorMessage = nil
        saveSettings()

        // The screen sink is used for its live stream only; the scrollback this
        // view model keeps is the one the UI shows, so the sink's own copy is
        // held at the smallest size it allows rather than duplicating every
        // retained sheet.
        let screen = ScreenSink(scrollbackLimit: 1, displayMaxDimension: 256)
        do {
            let sink = try service.makeSink(
                settings: settings,
                screen: screen,
                onFileWritten: { [weak self] url in
                    Task { @MainActor in self?.recordSavedFile(url) }
                },
                onSpool: { [weak self] line in
                    Task { @MainActor in self?.append(.info, "Spooled to paper: \(line)") }
                })
            let handler = service.makeHandler(settings: settings, sink: sink)
            let server = try service.makeServer(settings: settings, delegate: handler)

            // Both streams are opened before the listener binds: `events` yields
            // `.started` from inside `start()`, and a film could in principle
            // arrive before a subscriber attached — an unsubscribed screen sink
            // counts that film as dropped rather than delivering it.
            let events = await server.events
            let filmStream = await screen.filmStream()

            try await server.start()

            self.screen = screen
            self.handler = handler
            self.server = server
            self.boundPort = await server.boundPort
            self.isRunning = true
            self.statusMessage =
                PrintSCPConsole.startedLine(settings: settings, boundPort: boundPort)
            append(.info, statusMessage)
            append(.info, "Output: \(PrintSCPConsole.outputSummary(settings: settings))")

            // Two streams: the server's protocol events drive the log and the
            // counters, the sink's film stream delivers the composed sheets.
            eventTask = Task { [weak self] in
                for await event in events {
                    await MainActor.run { self?.handle(event) }
                }
            }
            filmTask = Task { [weak self] in
                for await film in filmStream {
                    await MainActor.run { self?.retain(film) }
                }
            }
        } catch {
            let message = describe(error)
            statusMessage = "Failed to start"
            startErrorMessage = message
            append(.error, "Failed to start printer: \(message)")
        }
    }

    /// Stops listening and closes every open association.
    public func stop() async {
        guard isRunning, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        eventTask?.cancel()
        filmTask?.cancel()
        eventTask = nil
        filmTask = nil
        if let server { await server.stop() }
        server = nil
        handler = nil
        screen = nil
        isRunning = false
        boundPort = 0
        statusMessage = "Printer stopped"
        append(.info, PrintSCPConsole.stoppedLine(counters: counters))
    }

    // MARK: - Films

    /// Retains a composed film for review, evicting the oldest films once
    /// either retention limit is exceeded.
    ///
    /// Internal rather than private so the retention rules can be tested
    /// without standing up a listener and a real SCU.
    func retain(_ film: ComposedFilm) {
        let record = ReceivedFilmRecord(film: film, thumbnail: service.makeThumbnail(of: film))
        films.insert(record, at: 0)
        if selectedFilmID == nil { selectedFilmID = record.id }
        enforceRetentionLimits()
    }

    /// Drops the oldest films until both the count and the memory budget hold.
    /// At least one film is always kept — the one just received.
    private func enforceRetentionLimits() {
        let countLimit = max(1, settings.retainedFilmLimit)
        while films.count > countLimit {
            evict()
        }
        var total = films.reduce(0) { $0 + $1.byteCount }
        while films.count > 1, total > settings.retainedMemoryBudgetBytes {
            total -= films[films.count - 1].byteCount
            evict()
        }
        retainedBytes = films.reduce(0) { $0 + $1.byteCount }
    }

    private func evict() {
        guard let dropped = films.popLast() else { return }
        evictedFilmCount += 1
        if selectedFilmID == dropped.id { selectedFilmID = films.first?.id }
    }

    /// Writes the selected film to `url`; the extension chooses the format.
    ///
    /// - Returns: An error message on failure, `nil` on success.
    @discardableResult
    public func saveSelectedFilm(to url: URL) -> String? {
        guard let record = selectedFilm else { return "No film selected" }
        do {
            try service.write(film: record.film, to: url)
            // This save *is* attributable — the record is in hand — so the film
            // carries its own list of where it has been written.
            if let index = films.firstIndex(where: { $0.id == record.id }) {
                films[index].savedFiles.append(url)
            }
            append(.info, "Saved film to \(url.lastPathComponent)")
            return nil
        } catch {
            let message = describe(error)
            append(.error, "Failed to save film: \(message)")
            return message
        }
    }

    /// The selected film's attributes as pretty-printed JSON, for "Copy".
    public func selectedFilmAttributesJSON() -> String? {
        guard let record = selectedFilm else { return nil }
        return try? record.film.info.jsonRepresentation()
    }

    /// Forgets every retained film.
    public func clearFilms() {
        films.removeAll()
        selectedFilmID = nil
        retainedBytes = 0
    }

    /// Clears the event log and the session counters.
    public func clearLog() {
        log.removeAll()
        counters = PrintSCPSessionCounters()
    }

    /// Records an auto-saved file.
    ///
    /// Deliberately not attributed to a film in the list: the sink's callback
    /// carries only a path, and the film it belongs to may not have reached the
    /// list yet — it arrives over the sink's stream, which the UI drains
    /// asynchronously. Guessing "the newest one" would put the wrong badge on
    /// the wrong film under load. The file name carries the job's own tokens,
    /// so the log line is the reliable record.
    private func recordSavedFile(_ url: URL) {
        savedFiles.insert(url, at: 0)
        if savedFiles.count > Self.logLimit {
            savedFiles.removeLast(savedFiles.count - Self.logLimit)
        }
        append(.info, "Wrote \(url.lastPathComponent)")
    }

    // MARK: - Events

    /// Folds one server event into the screen's state.
    ///
    /// The wording and the counting are both shared: `PrintSCPConsole` phrases
    /// every line and `PrintSCPSessionCounters` tallies them, so this log and
    /// `dicom-printscp`'s console say the same thing about the same event. Only
    /// the listener's own lifecycle — which drives buttons, not text — is
    /// handled here.
    private func handle(_ event: PrintServerEvent) {
        switch event {
        case .started(let port):
            boundPort = port
        case .stopped:
            if isRunning {
                isRunning = false
                statusMessage = "Printer stopped"
            }
        default:
            break
        }

        counters.record(event)
        if let entry = PrintSCPConsole.logEntry(for: event) {
            append(entry)
        }
    }

    private func append(_ level: PrintSCPLogLevel, _ message: String, ae: String? = nil) {
        append(PrintSCPLogEntry(level: level, message: message, remoteAETitle: ae))
    }

    private func append(_ entry: PrintSCPLogEntry) {
        log.insert(entry, at: 0)
        if log.count > Self.logLimit {
            log.removeLast(log.count - Self.logLimit)
        }
    }

    /// A message worth showing, phrased by the shared console.
    private func describe(_ error: Error) -> String {
        PrintSCPConsole.describe(error)
    }
}
