// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (assembly of server, composer and sinks)
//
// PrintSCPService.swift
// DICOMPrintKit
//
// Assembly of the printer emulator: settings in, running parts out.
//
// The mirror image of `PrintWorkflow`, which drives a printer — this one *is*
// one. No DIMSE logic and no rasterization live here; the server, the film
// composer and the output sinks all come from this target and `DICOMNetwork`,
// so a film received by DICOM Studio and a film received by `dicom-printscp`
// are negotiated, composed and written by identical code.
//

import Foundation
import DICOMNetwork

/// Builds the pieces of the printer emulator from ``PrintSCPSettings``.
///
/// Stateless by design: the caller owns the lifetime of the server, the sink and
/// the delegate, and this type only knows how to construct them. Studio's view
/// model and the CLI's `serve` command each own their own run loop, and share
/// everything below it.
public struct PrintSCPService: Sendable {

    /// Receives a file path each time a film is auto-saved.
    public typealias FileWrittenHandler = @Sendable (URL) -> Void

    /// Receives the `lp` output line each time a film is spooled to paper.
    public typealias SpoolHandler = @Sendable (String) -> Void

    /// Longest side, in pixels, of the copy kept for a film list.
    public static let thumbnailMaxDimension = 240

    public init() {}

    // MARK: - Sinks

    /// Builds the output sink for a set of settings.
    ///
    /// The screen sink is always present — it is what carries films to the live
    /// surface, whether that is Studio's film list or the CLI's console — and the
    /// file and paper sinks compose onto it when enabled. Failures are not fatal
    /// unless every sink fails: a full disk should not make the printer reject a
    /// job the operator can still see.
    ///
    /// - Throws: When auto-saving is enabled and the output directory cannot be
    ///   created. Discovering that after the first film has been printed is
    ///   worse than refusing to start.
    public func makeSink(
        settings: PrintSCPSettings,
        screen: ScreenSink,
        onFileWritten: FileWrittenHandler? = nil,
        onSpool: SpoolHandler? = nil
    ) throws -> any PrintOutputSink {
        var sinks: [any PrintOutputSink] = [screen]

        #if canImport(CoreGraphics)
        let naming = FilmOutputNaming(pattern: settings.fileNamePattern.isEmpty
            ? "film-{timestamp}-{index}"
            : settings.fileNamePattern)

        if settings.savePDF || settings.saveImage {
            try FileManager.default.createDirectory(
                at: settings.outputDirectoryURL, withIntermediateDirectories: true)
        }
        if settings.savePDF {
            sinks.append(PDFSink(
                directory: settings.outputDirectoryURL,
                naming: naming,
                onWrite: onFileWritten))
        }
        if settings.saveImage {
            sinks.append(ImageSink(
                directory: settings.outputDirectoryURL,
                format: settings.imageFormat == .tiff ? .tiff : .png,
                naming: naming,
                onWrite: onFileWritten))
        }
        // PaperPrinterSink spools through `lp`, so it exists only where a
        // subprocess can be launched. Elsewhere the setting simply has no sink
        // to add — the screen/PDF/image sinks still compose as usual.
        #if os(macOS) || os(Linux)
        if settings.sendToPaperQueue {
            let queue = settings.paperQueue.trimmingCharacters(in: .whitespaces)
            sinks.append(PaperPrinterSink(
                queue: queue.isEmpty ? nil : queue,
                allowPaper: true,
                onSpool: onSpool))
        }
        #endif
        #endif

        return sinks.count == 1 ? screen : CompositePrintSink(sinks)
    }

    // MARK: - Server

    /// Builds the delegate that composes each received film and emits it.
    public func makeHandler(
        settings: PrintSCPSettings,
        sink: any PrintOutputSink,
        onCompose: (@Sendable (ComposedFilm) -> Void)? = nil
    ) -> FilmComposingPrintHandler {
        FilmComposingPrintHandler(
            composer: FilmComposer(configuration: settings.makeComposerConfiguration()),
            sink: sink,
            status: settings.reportedPrinterStatus,
            onCompose: onCompose)
    }

    /// Builds the print server.
    ///
    /// - Throws: When the AE title is not a legal DICOM AE title.
    public func makeServer(
        settings: PrintSCPSettings,
        delegate: any PrintSCPDelegate
    ) throws -> DICOMPrintServer {
        DICOMPrintServer(configuration: try settings.makeConfiguration(), delegate: delegate)
    }

    // MARK: - Paper queues

    /// The CUPS queues available on this machine, for the paper-output picker
    /// and for `dicom-printscp queues`.
    ///
    /// Returns an empty list rather than throwing: no printers configured is a
    /// normal state, not an error to report.
    public func availablePaperQueues() -> [String] {
        #if canImport(CoreGraphics) && os(macOS)
        return (try? PaperPrinterSink.availableQueues()) ?? []
        #else
        return []
        #endif
    }

    // MARK: - Film helpers

    /// A small copy of a composed film for a film list.
    public func makeThumbnail(of film: ComposedFilm) -> ComposedFilm {
        #if canImport(CoreGraphics)
        return film.downsampled(maxDimension: Self.thumbnailMaxDimension)
        #else
        return film
        #endif
    }

    /// Writes one composed film to a file, choosing the writer from the
    /// destination's path extension (`pdf`, `tiff`/`tif`, anything else → PNG).
    public func write(film: ComposedFilm, to url: URL) throws {
        #if canImport(CoreGraphics)
        switch url.pathExtension.lowercased() {
        case "pdf":
            try PDFSink.write(films: [film], to: url)
        case "tif", "tiff":
            try ImageSink.write(film: film, to: url, format: .tiff)
        default:
            try ImageSink.write(film: film, to: url, format: .png)
        }
        #else
        throw PrintSCPServiceError.imageOutputUnavailable
        #endif
    }
}

/// Failures raised by ``PrintSCPService``.
public enum PrintSCPServiceError: Error, Sendable, CustomStringConvertible {
    /// Film output requires CoreGraphics, which this platform does not have.
    case imageOutputUnavailable

    public var description: String {
        switch self {
        case .imageOutputUnavailable:
            return "Film output is not available on this platform"
        }
    }
}
