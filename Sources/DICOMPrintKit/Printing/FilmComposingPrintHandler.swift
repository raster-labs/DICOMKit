// NEMA-verified: 2026a, checked 2026-09-29 — default Printer Status NORMAL checked against PS3.3 2026a Table C.13-9; otherwise SCP-to-composer glue
//
// FilmComposingPrintHandler.swift
// DICOMPrintKit
//
// The join between the Print SCP and the film pipeline: every film the SCP
// receives is composed and handed to the configured sinks.
//
// This is what makes the emulator an emulator — point any Print SCU at the
// server, and the finished film appears wherever the sinks send it.
//

import Foundation
import DICOMNetwork

/// Composes every received film and emits it to a sink.
///
/// ```swift
/// let screen = ScreenSink()
/// let handler = FilmComposingPrintHandler(sink: screen)
/// let server = DICOMPrintServer(
///     configuration: PrintSCPConfiguration(aeTitle: try AETitle("DCMPRINT"), port: 11112),
///     delegate: handler)
/// try await server.start()
///
/// for await film in await screen.filmStream() {
///     display(film)
/// }
/// ```
public actor FilmComposingPrintHandler: PrintSCPDelegate {

    /// The composer used for every film.
    public let composer: FilmComposer

    /// Where composed films go.
    public let sink: any PrintOutputSink

    /// The printer status reported to N-GET.
    private var status: PrinterStatus

    /// Films composed since the handler was created.
    public private(set) var composedFilmCount = 0

    /// The most recent composition failure, if any (the SCP already reported it
    /// to the SCU; this is for the UI's event log).
    public private(set) var lastError: String?

    /// Called for each composed film, before it reaches the sink — the console
    /// and event-log hook.
    private let onCompose: (@Sendable (ComposedFilm) -> Void)?

    public init(
        composer: FilmComposer = FilmComposer(),
        sink: any PrintOutputSink,
        status: PrinterStatus = PrinterStatus(status: "NORMAL"),
        onCompose: (@Sendable (ComposedFilm) -> Void)? = nil
    ) {
        self.composer = composer
        self.sink = sink
        self.status = status
        self.onCompose = onCompose
    }

    // MARK: PrintSCPDelegate

    public func didReceiveFilm(_ film: ReceivedFilm) async throws {
        do {
            let composed = try composer.compose(film)
            composedFilmCount += 1
            onCompose?(composed)
            try await sink.emit(composed)
        } catch {
            // Surfacing the reason matters: the SCP puts it in the N-ACTION
            // response's Error Comment, which is often the only diagnostic an
            // SCU developer gets.
            lastError = String(describing: error)
            throw error
        }
    }

    public func printerStatus() async -> PrinterStatus { status }

    public func didFail(error: Error, forPrintJob printJobUID: String?) async {
        lastError = "\(printJobUID ?? "unknown job"): \(error)"
    }

    // MARK: Control

    /// Replaces the reported printer status (e.g. to simulate a fault so an
    /// SCU's error handling can be exercised).
    public func setStatus(_ newStatus: PrinterStatus) {
        status = newStatus
    }
}
