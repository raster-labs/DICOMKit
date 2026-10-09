// NEMA-verified: 2026a, checked 2026-09-29 — Printer Status values FAILURE/WARNING compared against PS3.3 2026a Table C.13-9; Basic Grayscale/Colour image box Samples per Pixel 1/3 per Table C.13-5; DIMSE sequence lives in DICOMNetwork
// PrintWorkflow.swift
// DICOMPrintKit
//
// Outer orchestration of a print job: optional C-ECHO verification, optional
// printer-status pre-flight, retries with exponential backoff, and the call
// into the Print SCU. The DIMSE sequence itself (film session → film boxes →
// image boxes → print → cleanup, one association) lives in
// DICOMNetwork.DICOMPrintService and is NOT reimplemented here.

import Foundation
import DICOMNetwork

// MARK: - Diagnostics

/// A line the workflow wants to surface while it runs.
public enum PrintDiagnostic: Sendable {
    /// Detail shown only in verbose mode.
    case info(String)
    /// Something the user should always see.
    case notice(String)
    /// A problem that does not stop the job.
    case warning(String)
    /// An N-EVENT-REPORT pushed by the printer during the association.
    case event(PrintEvent)

    /// The text to display for this diagnostic.
    public var text: String {
        switch self {
        case .info(let message), .notice(let message), .warning(let message):
            return message
        case .event(let event):
            return event.summary
        }
    }
}

// MARK: - Errors

/// A failure raised by the workflow itself rather than by the SCU.
public enum PrintWorkflowError: Error, CustomStringConvertible, Sendable {
    /// The printer reported FAILURE during the pre-flight status check. The
    /// explanatory line has already been emitted as a diagnostic.
    case printerReportedFailure(String)

    public var description: String {
        switch self {
        case .printerReportedFailure(let info):
            return "Printer reports FAILURE\(info)"
        }
    }
}

// MARK: - Workflow

/// Runs a print job end to end.
public enum PrintWorkflow {

    /// Receives diagnostic lines as the job progresses.
    public typealias DiagnosticHandler = @Sendable (PrintDiagnostic) -> Void

    /// Receives progress updates from the SCU.
    public typealias ProgressHandler = @Sendable (PrintProgress) -> Void

    // MARK: Pre-flight

    /// Runs the request's optional pre-flight checks against the printer.
    ///
    /// - C-ECHO verification when ``PrintJobRequest/verifyFirst`` is set.
    /// - Printer status when ``PrintJobRequest/checkStatus`` is set: FAILURE
    ///   aborts the job, WARNING is reported and the job continues.
    public static func preflight(
        configuration: PrintConfiguration,
        request: PrintJobRequest,
        diagnostics: DiagnosticHandler? = nil
    ) async throws {
        if request.verifyFirst {
            let ok = try await DICOMVerificationService.verify(
                host: configuration.host,
                port: configuration.port,
                callingAE: configuration.callingAETitle,
                calledAE: configuration.calledAETitle,
                timeout: configuration.timeout
            )
            guard ok else {
                throw PrintRequestError(
                    "C-ECHO verification failed — printer AE is not responding correctly")
            }
            diagnostics?(.info("✓ C-ECHO verification succeeded"))
        }

        if request.checkStatus {
            let printerStatus = try await DICOMPrintService.getPrinterStatus(
                configuration: configuration)
            switch printerStatus.status {
            case "FAILURE":
                let info = printerStatus.statusInfo.map { " (\($0))" } ?? ""
                diagnostics?(.notice("✗ Printer reports FAILURE\(info) — aborting"))
                throw PrintWorkflowError.printerReportedFailure(info)
            case "WARNING":
                let info = printerStatus.statusInfo.map { " (\($0))" } ?? ""
                diagnostics?(.warning("⚠ Printer reports WARNING\(info) — continuing"))
            default:
                diagnostics?(.info("✓ Printer status: \(printerStatus.status)"))
            }
        }
    }

    /// Whether this printer can carry film-level annotation text.
    ///
    /// Asked before the frames are prepared, because the answer decides how they
    /// are prepared: a film footer travels as a Basic Annotation Box, and a
    /// printer that has none needs the caption burned into each image instead.
    /// Costs one short association; a printer that cannot be reached answers
    /// `false`, so the job falls back to burning rather than to nothing.
    public static func supportsAnnotationBoxes(
        configuration: PrintConfiguration
    ) async -> Bool {
        await DICOMPrintService.supportsAnnotationBoxes(configuration: configuration)
    }

    // MARK: Execute

    /// Prints the prepared images, honoring the request's retry policy.
    ///
    /// Retries apply only to *thrown* connection/setup failures, i.e. before the
    /// print job is submitted. A returned ``PrintResult`` — success or failure —
    /// is never retried, so a submitted job is never duplicated.
    ///
    /// - Parameters:
    ///   - configuration: Printer connection settings.
    ///   - request: The validated job description.
    ///   - images: Frames from ``PrintImagePreparer``, in film-cell order.
    ///   - diagnostics: Receives retry notices and printer events.
    ///   - progress: Receives SCU progress updates (nil uses the non-streaming API).
    public static func execute(
        configuration: PrintConfiguration,
        request: PrintJobRequest,
        images: [PreparedPrintImage],
        diagnostics: DiagnosticHandler? = nil,
        progress: ProgressHandler? = nil
    ) async throws -> PrintResult {
        let payloads = images.pixelPayloads
        let descriptors = images.imageDescriptors

        // The colour mode has to match the pixels, not the intention.
        //
        // Two ways they drift apart. A raw job copies the source descriptor
        // verbatim (`PrintImagePreparer`), so an RGB ultrasound keeps Samples
        // per Pixel 3 while the request still says GRAYSCALE — and a Basic
        // Grayscale Image Box accepts only 1, so the printer rejects the job
        // outright (0x0106, "Samples per Pixel must be 1"). The other way round,
        // a colour-mode job whose frames all came back monochrome would open a
        // Basic Colour association to send greys.
        //
        // Whichever it is, the pixels are already made and the SOP class is not,
        // so the SOP class is what gives way. Said out loud rather than silently:
        // a film that comes out grey when colour was asked for is something the
        // reader has to know about.
        let configuration = Self.reconcilingColorMode(
            configuration, with: descriptors, diagnostics: diagnostics)

        var options = request.printOptions
        // FR-003: fill and true size travel as per-image-box attributes.
        let boxOptions = request.imageBoxOptions(for: images)
        if !boxOptions.isEmpty {
            options = options.withImageBoxOptions(boxOptions)
        }
        // True size is undefined without pixel spacing; those images fall back
        // to fit — audibly, never silently: a wrong-scale film is one a
        // clinician might measure against.
        let fallbacks = request.trueSizeFallbackCount(for: images)
        if fallbacks > 0 {
            diagnostics?(.warning(
                "⚠ \(fallbacks) image(s) record no pixel spacing — "
                + "printed fit-to-film instead of true size"))
        }
        let layout = request.resolvedLayout
        // Carries the band layouts a grid cannot state; nil lets the SCU size the
        // grid to the image count, as before.
        let displayFormat = request.resolvedDisplayFormat

        let eventHandler: PrintEventHandler? = diagnostics.map { handler -> PrintEventHandler in
            { (event: PrintEvent) in handler(.event(event)) }
        }

        let maxAttempts = max(1, request.retries + 1)
        let retryPolicy = PrintRetryPolicy(maxAttempts: request.retries)

        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await DICOMPrintService.printImages(
                    configuration: configuration,
                    images: payloads,
                    options: options,
                    imageDescriptors: descriptors,
                    layout: layout,
                    displayFormat: displayFormat,
                    eventHandler: eventHandler,
                    progressHandler: progress
                )
            } catch {
                // A cancelled job must not be retried.
                if error is CancellationError { throw error }
                lastError = error
                if attempt < maxAttempts - 1 {
                    let delay = retryPolicy.delay(for: attempt)
                    diagnostics?(.notice(
                        "Attempt \(attempt + 1)/\(maxAttempts) failed: \(error). "
                        + "Retrying in \(String(format: "%.1f", delay))s..."))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError ?? PrintRequestError("Print failed")
    }

    // MARK: Colour reconciliation

    /// The configuration to actually print with, given the pixels that were
    /// prepared.
    ///
    /// Basic Grayscale and Basic Colour are different SOP classes with different
    /// Image Box rules: grayscale accepts Samples per Pixel 1 only, colour
    /// accepts 1 or 3 (PS3.3 C.13.5). The prepared frames decide which is
    /// legal — a job carrying any 3-sample frame *must* go out as colour, and a
    /// job carrying none has nothing to gain from colour.
    ///
    /// Returns `configuration` untouched when it already agrees, so the common
    /// case allocates nothing and the diagnostics stay quiet.
    static func reconcilingColorMode(
        _ configuration: PrintConfiguration,
        with descriptors: [PrintImageData],
        diagnostics: DiagnosticHandler? = nil
    ) -> PrintConfiguration {
        guard !descriptors.isEmpty else { return configuration }
        let colorFrames = descriptors.filter { $0.samplesPerPixel > 1 }.count
        let needsColor = colorFrames > 0
        let hasColor = configuration.colorMode == .color
        guard needsColor != hasColor else { return configuration }

        if needsColor {
            diagnostics?(.notice(
                "\(colorFrames) of \(descriptors.count) image(s) carry colour pixels — "
                + "printing with Basic Colour Print Management instead of grayscale"))
        } else {
            diagnostics?(.notice(
                "No image carries colour pixels — printing with Basic Grayscale "
                + "Print Management instead of colour"))
        }

        return PrintConfiguration(
            host: configuration.host,
            port: configuration.port,
            callingAETitle: configuration.callingAETitle,
            calledAETitle: configuration.calledAETitle,
            timeout: configuration.timeout,
            colorMode: needsColor ? .color : .grayscale)
    }

    // MARK: Job status

    /// Queries the execution status of a submitted print job.
    public static func jobStatus(
        configuration: PrintConfiguration,
        printJobUID: String
    ) async throws -> PrintJobStatus {
        try await DICOMPrintService.getPrintJobStatus(
            configuration: configuration,
            printJobUID: printJobUID
        )
    }

    /// Queries printer status (N-GET) outside of a print job.
    public static func printerStatus(
        configuration: PrintConfiguration
    ) async throws -> PrinterStatus {
        try await DICOMPrintService.getPrinterStatus(configuration: configuration)
    }
}
