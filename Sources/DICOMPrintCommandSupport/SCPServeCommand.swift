// NEMA-verified: 2026a, checked 2026-10-01 — Printer SOP Instance UID (PS3.6 2026a Table A-1) and PS3.4 H.4.6 citation checked; otherwise carries no DICOM-standard data (listener lifecycle, console routing)
//
// SCPServeCommand.swift
// dicom-printscp
//
// `dicom-printscp serve` — bind a port and be a printer until interrupted.
//

import Foundation
import Dispatch
import ArgumentParser
import DICOMNetwork
import DICOMPrintKit

struct SCPServeCommand: PrintExecutableCommand {
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

    @OptionGroup var transport: SCPTransportOptions
    @OptionGroup var composition: SCPCompositionOptions
    @OptionGroup var filmOutput: SCPFilmOutputOptions
    @OptionGroup var configOptions: SCPConfigOptions

    @Option(name: .long, help: "Stop after this many films (default: run until interrupted)")
    var maxFilms: Int?

    @Option(name: .long, help: "Stop after this many seconds (default: run until interrupted)")
    var duration: Double?

    @Option(name: .long, help: "Output format: text, json (json writes one object per event to stdout)")
    var format: SCPOutputFormat = .text

    @Flag(name: .shortAndLong, help: "Show each film's attributes as it arrives")
    var verbose: Bool = false

    @Flag(name: .long, help: "Suppress console output; only errors are reported")
    var quiet: Bool = false

    func validate() throws {
        if let maxFilms, maxFilms < 1 {
            throw ValidationError("--max-films must be 1 or greater")
        }
        if let duration, !SCPSettingsChecks.validSleepInterval(duration) {
            throw ValidationError("--duration must be finite, greater than zero, and less than 18446744073 seconds")
        }
    }

    func execute(context: PrintCommandContext) async throws {
        try validate()
        try Task.checkCancellation()
        var settings = configOptions.load(context: context)
        try transport.apply(to: &settings)
        try composition.apply(to: &settings)
        try filmOutput.apply(
            to: &settings,
            defaultOutput: "png",
            outputWasConfigured: configOptions.hasStoredSettings(context: context))

        try SCPSettingsChecks.validate(settings, transport: true)

        let console = SCPConsole(format: format, quiet: quiet, context: context)

        if configOptions.saveConfig {
            try configOptions.save(settings, context: context)
            console.line("Wrote \(configOptions.url(context: context).path)")
            return
        }

        let service = PrintSCPService()
        // The screen sink is the emulator's live channel on every surface; here
        // it is what turns a received film into a console line.
        let screen = ScreenSink(scrollbackLimit: 1, displayMaxDimension: 256)
        let session = SCPServeSession(
            console: console, verbose: verbose, maxFilms: maxFilms)

        let openFilms = filmOutput.open
        let sink = try service.makeSink(
            settings: settings,
            screen: screen,
            onFileWritten: { url in
                console.event(PrintSCPLogEntry(level: .info, message: "Wrote \(url.path)"))
                if openFilms { context.openFile(url) }
            },
            onSpool: { line in console.event(PrintSCPLogEntry(level: .info, message: "Spooled to paper: \(line)")) },
            onFailure: { sink, error in console.error("Output failed (\(sink)): \(error)") })
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
            await server.stop()
            context.listenerState(nil)
            throw PrintSCPCommandError(
                "Failed to start printer on port \(settings.port): "
                    + PrintSCPConsole.describe(error))
        }

        if Task.isCancelled {
            await server.stop()
            context.listenerState(nil)
            throw CancellationError()
        }
        let boundPort = await server.boundPort
        context.listenerState(boundPort)
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
        var interrupt: DispatchSourceSignal?
        if context.handlesProcessSignals {
            signal(SIGINT, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            source.setEventHandler { Task { await session.finish(reason: "interrupted") } }
            source.resume()
            interrupt = source
        }
        defer { interrupt?.cancel() }

        let reason = await withTaskCancellationHandler {
            await withTaskGroup(of: String?.self) { group in
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
                        do { try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000)) }
                        catch { return nil }
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
        } onCancel: {
            Task { await session.finish(reason: "cancelled") }
        }

        await server.stop()
        context.listenerState(nil)
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
        try Task.checkCancellation()
    }
}

// MARK: - Session state

/// The listener's console state: totals, film count, and the stop signal.
///
/// An actor because three producers write to it — the event stream, the film
/// stream and the signal handler.
actor SCPServeSession {
    private let console: SCPConsole
    private let verbose: Bool
    private let maxFilms: Int?

    private var counters = PrintSCPSessionCounters()
    private var filmsReceived = 0
    private var finishReason: String?
    private var pendingReason: String?
    private var waiter: CheckedContinuation<String, Never>?
    private var releaseGraceTask: Task<Void, Never>?

    /// How long a satisfied `--max-films` run waits for the association to
    /// release before stopping anyway.
    private static let releaseGraceSeconds: UInt64 = 5

    init(console: SCPConsole, verbose: Bool, maxFilms: Int?) {
        self.console = console
        self.verbose = verbose
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

    /// Arms the stop, but lets the current association finish first.
    ///
    /// The SCU still has an N-ACTION response and an N-DELETE to exchange when
    /// the last film lands; tearing the listener down at that moment reports a
    /// failed print for a job that actually succeeded.
    private func beginFinishing(reason: String) {
        guard pendingReason == nil, finishReason == nil else { return }
        pendingReason = reason
        releaseGraceTask = Task { [weak self, reason] in
            do { try await Task.sleep(nanoseconds: Self.releaseGraceSeconds * 1_000_000_000) }
            catch { return }
            await self?.finish(reason: reason)
        }
    }

    /// Signals that the listener should stop, with the reason to report.
    func finish(reason: String) {
        guard finishReason == nil else { return }
        finishReason = reason
        releaseGraceTask?.cancel()
        releaseGraceTask = nil
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
