// NEMA-verified: 2026a, checked 2026-10-01 — Printer SOP Instance UID (PS3.6 2026a Table A-1) and PS3.4 H.4.6 citation checked; otherwise carries no DICOM-standard data (listener lifecycle, console routing)
//
// ServeCommand.swift
// dicom-printscp
//
// `dicom-printscp serve` — bind a port and be a printer until interrupted.
//

import Foundation
import Dispatch
import ArgumentParser
import DICOMNetwork
import DICOMPrintKit

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Listen for Print SCUs and compose received film",
        discussion: """
            Runs until interrupted (Ctrl-C), or until --max-films films have been
            received, or until --duration seconds have passed. Received film is
            written to --output-dir; --output none receives and discards, which is
            useful when only the protocol trace matters.

            The listener answers N-GET on the Printer SOP Instance
            (1.2.840.10008.5.1.1.17, PS3.4 H.4.6) with the identity flags below, so an SCU sees exactly the printer described on
            the command line.
            """
    )

    @OptionGroup var transport: TransportOptions
    @OptionGroup var composition: CompositionOptions
    @OptionGroup var filmOutput: FilmOutputOptions
    @OptionGroup var configOptions: ConfigOptions

    @Option(name: .long, help: "Stop after this many films (default: run until interrupted)")
    var maxFilms: Int?

    @Option(name: .long, help: "Stop after this many seconds (default: run until interrupted)")
    var duration: Double?

    @Option(name: .long, help: "Output format: text, json (json writes one object per event to stdout)")
    var format: OutputFormat = .text

    @Flag(name: .shortAndLong, help: "Show each film's attributes as it arrives")
    var verbose: Bool = false

    @Flag(name: .long, help: "Suppress console output; only errors are reported")
    var quiet: Bool = false

    func run() async throws {
        var settings = configOptions.load()
        try transport.apply(to: &settings)
        try composition.apply(to: &settings)
        try filmOutput.apply(
            to: &settings,
            defaultOutput: "png",
            outputWasConfigured: configOptions.hasStoredSettings)

        let console = Console(format: format, quiet: quiet)

        if configOptions.saveConfig {
            try configOptions.save(settings)
            console.line("Wrote \(configOptions.url.path)")
            return
        }

        let service = PrintSCPService()
        // The screen sink is the emulator's live channel on every surface; here
        // it is what turns a received film into a console line.
        let screen = ScreenSink(scrollbackLimit: 1, displayMaxDimension: 256)
        let session = ServeSession(
            console: console, verbose: verbose, openFilms: filmOutput.open, maxFilms: maxFilms)

        let sink = try service.makeSink(
            settings: settings,
            screen: screen,
            onFileWritten: { url in Task { await session.recordFile(url) } },
            onSpool: { line in Task { await session.recordSpool(line) } })
        let handler = service.makeHandler(settings: settings, sink: sink)
        let server = try service.makeServer(settings: settings, delegate: handler)

        // Both streams are opened before the listener binds: `events` yields
        // `.started` from inside `start()`, and a film could in principle arrive
        // before a subscriber attached — an unsubscribed screen sink counts that
        // film as dropped rather than delivering it.
        let events = await server.events
        let filmStream = await screen.filmStream()

        do {
            try await server.start()
        } catch {
            throw PrintSCPCommandError(
                "Failed to start printer on port \(settings.port): "
                    + PrintSCPConsole.describe(error))
        }

        let boundPort = await server.boundPort
        switch format {
        case .text:
            console.lines(PrintSCPConsole.startupSummary(settings: settings, boundPort: boundPort))
            console.line("")
        case .json:
            console.event(PrintSCPLogEntry(
                level: .info,
                message: PrintSCPConsole.startedLine(settings: settings, boundPort: boundPort)))
        }

        // Ctrl-C stops the listener rather than killing the process, so open
        // associations are released and the totals still get reported.
        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        interrupt.setEventHandler { Task { await session.finish(reason: "interrupted") } }
        interrupt.resume()
        defer { interrupt.cancel() }

        let reason = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                for await event in events { await session.record(event) }
                return nil
            }
            group.addTask {
                for await film in filmStream { await session.record(film: film) }
                return nil
            }
            if let duration {
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
                    await session.finish(reason: "reached --duration \(Int(duration))s")
                    return nil
                }
            }
            group.addTask { await session.waitForFinish() }

            var stopReason = "stopped"
            for await result in group where result != nil {
                stopReason = result ?? stopReason
                break
            }
            group.cancelAll()
            return stopReason
        }

        await server.stop()
        let totals = await session.totals
        switch format {
        case .text:
            console.line("")
            console.line("\(PrintSCPConsole.stoppedLine(counters: totals)) (\(reason))")
        case .json:
            console.event(PrintSCPLogEntry(
                level: .info,
                message: "\(PrintSCPConsole.stoppedLine(counters: totals)) (\(reason))"))
        }
    }
}

// MARK: - Session state

/// The listener's console state: totals, film count, and the stop signal.
///
/// An actor because three producers write to it — the event stream, the film
/// stream and the signal handler.
actor ServeSession {
    private let console: Console
    private let verbose: Bool
    private let openFilms: Bool
    private let maxFilms: Int?

    private var counters = PrintSCPSessionCounters()
    private var filmsReceived = 0
    private var finishReason: String?
    private var pendingReason: String?
    private var waiter: CheckedContinuation<String, Never>?

    /// How long a satisfied `--max-films` run waits for the association to
    /// release before stopping anyway.
    private static let releaseGraceSeconds: UInt64 = 5

    init(console: Console, verbose: Bool, openFilms: Bool, maxFilms: Int?) {
        self.console = console
        self.verbose = verbose
        self.openFilms = openFilms
        self.maxFilms = maxFilms
    }

    var totals: PrintSCPSessionCounters { counters }

    /// Folds one protocol event into the totals and the console.
    ///
    /// `--max-films` is counted on `.filmPrinted` — which the SCP emits *after*
    /// the sinks have written — rather than on the film stream, which delivers
    /// the sheet the moment it is composed. Stopping on the earlier signal
    /// aborted the association mid-N-ACTION and lost the file the run was
    /// started to produce.
    func record(_ event: PrintServerEvent) {
        counters.record(event)
        if let entry = PrintSCPConsole.logEntry(for: event) {
            console.event(entry)
        }

        switch event {
        case .filmPrinted:
            if let maxFilms, counters.films >= maxFilms {
                beginFinishing(reason: "reached --max-films \(maxFilms)")
            }
        case .associationReleased, .associationTimedOut:
            // The SCU has its responses; stopping now costs nothing.
            if let pendingReason { finish(reason: pendingReason) }
        default:
            break
        }
    }

    /// Reports one composed film.
    func record(film: ComposedFilm) {
        filmsReceived += 1
        switch console.format {
        case .text:
            console.event(PrintSCPLogEntry(
                level: .filmReceived,
                message: PrintSCPConsole.filmLine(film),
                remoteAETitle: film.info.callingAETitle))
            if verbose { console.lines(PrintSCPConsole.filmDetail(film)) }
        case .json:
            if let json = PrintSCPConsole.filmJSON(film) { console.line(json) }
        }

    }

    /// Reports an auto-saved file, and opens it when asked.
    func recordFile(_ url: URL) {
        console.event(PrintSCPLogEntry(level: .info, message: "Wrote \(url.path)"))
        guard openFilms else { return }
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.path]
        try? process.run()
        #endif
    }

    /// Reports an `lp` spool line.
    func recordSpool(_ line: String) {
        console.event(PrintSCPLogEntry(level: .info, message: "Spooled to paper: \(line)"))
    }

    /// Arms the stop, but lets the current association finish first.
    ///
    /// The SCU still has an N-ACTION response and an N-DELETE to exchange when
    /// the last film lands; tearing the listener down at that moment reports a
    /// failed print for a job that actually succeeded.
    private func beginFinishing(reason: String) {
        guard pendingReason == nil, finishReason == nil else { return }
        pendingReason = reason
        Task { [reason] in
            try? await Task.sleep(nanoseconds: Self.releaseGraceSeconds * 1_000_000_000)
            self.finish(reason: reason)
        }
    }

    /// Signals that the listener should stop, with the reason to report.
    func finish(reason: String) {
        guard finishReason == nil else { return }
        finishReason = reason
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: reason)
        }
    }

    /// Suspends until ``finish(reason:)`` is called.
    func waitForFinish() async -> String {
        if let finishReason { return finishReason }
        return await withCheckedContinuation { continuation in
            self.waiter = continuation
        }
    }
}
