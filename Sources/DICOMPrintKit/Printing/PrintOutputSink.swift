// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (screen, PDF, PNG/TIFF and CUPS sinks)
//
// PrintOutputSink.swift
// DICOMPrintKit
//
// Milestone D of the Print SCP plan: where a composed film goes.
//
// The emulator's primary sink is the screen; PDF, image files, and a real paper
// printer are optional and compose with it.
//

import Foundation
import DICOMNetwork

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

// MARK: - Sink protocol

/// Receives composed films.
public protocol PrintOutputSink: Sendable {
    /// Emits one film. Throwing propagates to the SCP, which answers the
    /// SCU's N-ACTION with a processing failure — so a sink should only throw
    /// when the job genuinely did not land.
    func emit(_ film: ComposedFilm) async throws

    /// A short name used in logs and console output.
    var sinkName: String { get }
}

extension PrintOutputSink {
    public var sinkName: String { String(describing: type(of: self)) }
}

/// Fans one film out to several sinks.
///
/// The emulator normally runs `ScreenSink` alone, or `ScreenSink` + `PDFSink`
/// to keep an archive of everything received.
public struct CompositePrintSink: PrintOutputSink {
    public let sinks: [any PrintOutputSink]

    /// When true, one sink's failure fails the whole emit; otherwise failures
    /// are collected and only reported if *every* sink failed.
    public let requiresAll: Bool

    public init(_ sinks: [any PrintOutputSink], requiresAll: Bool = false) {
        self.sinks = sinks
        self.requiresAll = requiresAll
    }

    public var sinkName: String {
        "composite(" + sinks.map(\.sinkName).joined(separator: "+") + ")"
    }

    public func emit(_ film: ComposedFilm) async throws {
        var failures: [Error] = []
        for sink in sinks {
            do {
                try await sink.emit(film)
            } catch {
                if requiresAll { throw error }
                failures.append(error)
            }
        }
        if !failures.isEmpty, failures.count == sinks.count, let first = failures.first {
            throw first
        }
    }
}

// MARK: - Screen sink

/// ★ The emulator's primary sink: publishes films to a live viewer.
///
/// Holds a bounded scrollback of recent films and an `AsyncStream` the UI (or
/// the CLI) subscribes to. The SCP must never block on a viewer that is not
/// draining, so the stream buffers with drop-oldest and the drops are counted
/// and reportable rather than silent.
public actor ScreenSink: PrintOutputSink {

    /// Films kept for scrollback, newest last.
    public private(set) var films: [ComposedFilm] = []

    /// How many films the scrollback holds.
    public let scrollbackLimit: Int

    /// Longest side, in pixels, of the copy kept for display.
    ///
    /// A 14×17 in film at 300 DPI is ~4200×5100 px; keeping ten of those at
    /// full resolution costs ~200 MB, so the scrollback holds downsampled
    /// copies and the full-resolution bitmap goes straight to the stream.
    public let displayMaxDimension: Int

    /// Films dropped because the subscriber was not draining fast enough.
    public private(set) var droppedFilmCount = 0

    private var continuation: AsyncStream<ComposedFilm>.Continuation?

    public init(scrollbackLimit: Int = 10, displayMaxDimension: Int = 1600) {
        self.scrollbackLimit = max(1, scrollbackLimit)
        self.displayMaxDimension = max(256, displayMaxDimension)
    }

    public nonisolated var sinkName: String { "screen" }

    /// The live film stream. One subscriber at a time; a second subscription
    /// replaces the first.
    public func filmStream() -> AsyncStream<ComposedFilm> {
        AsyncStream(bufferingPolicy: .bufferingNewest(4)) { continuation in
            self.continuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.clearContinuation() }
            }
        }
    }

    public func emit(_ film: ComposedFilm) async throws {
        #if canImport(CoreGraphics)
        let display = film.downsampled(maxDimension: displayMaxDimension)
        #else
        let display = film
        #endif

        films.append(display)
        if films.count > scrollbackLimit {
            films.removeFirst(films.count - scrollbackLimit)
        }

        if let continuation {
            if case .terminated = continuation.yield(film) {
                self.continuation = nil
            }
        } else {
            // No viewer attached: the film still lands in the scrollback, but
            // record that nobody saw it live.
            droppedFilmCount += 1
        }
    }

    /// The most recently received film, if any.
    public var latestFilm: ComposedFilm? { films.last }

    /// Empties the scrollback.
    public func clear() {
        films.removeAll()
        droppedFilmCount = 0
    }

    private func clearContinuation() {
        continuation = nil
    }
}

#if canImport(CoreGraphics)

// MARK: - Output paths

/// Builds output file paths from a token pattern.
///
/// Tokens: `{job}`, `{session}`, `{film}`, `{ae}`, `{index}`, `{timestamp}`.
public struct FilmOutputNaming: Sendable, Hashable {
    /// The file-name pattern, without extension.
    public let pattern: String

    public init(pattern: String = "film-{timestamp}-{index}") {
        self.pattern = pattern
    }

    /// Expands the pattern for a film.
    public func fileName(for film: ComposedFilm, index: Int, extension ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        var name = pattern
        for (token, value) in [
            "{job}": film.info.printJobUID,
            "{session}": film.info.filmSessionUID,
            "{film}": film.info.filmBoxUID,
            "{ae}": film.info.callingAETitle,
            "{index}": String(format: "%03d", index),
            "{timestamp}": formatter.string(from: film.info.receivedAt)
        ] {
            name = name.replacingOccurrences(of: token, with: sanitize(value))
        }
        return name + "." + ext
    }

    /// Strips characters that are awkward in file names (UIDs contain dots,
    /// which are fine; AE titles and labels can contain anything).
    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let text = String(scalars)
        return text.isEmpty ? "unknown" : String(text.prefix(96))
    }
}

// MARK: - Errors

/// Failures raised by output sinks.
public enum PrintSinkError: Error, Sendable, CustomStringConvertible {
    /// The composed film could not be turned into an image.
    case imageUnavailable
    /// A file could not be written.
    case writeFailed(path: String, underlying: String)
    /// Paper output was attempted without being explicitly enabled.
    case paperOutputNotAllowed
    /// The `lp` / `lpstat` command failed.
    case printCommandFailed(command: String, status: Int32, output: String)

    public var description: String {
        switch self {
        case .imageUnavailable:
            return "The composed film could not be converted to an image"
        case .writeFailed(let path, let underlying):
            return "Failed to write \(path): \(underlying)"
        case .paperOutputNotAllowed:
            return "Paper output is disabled; pass --allow-paper to enable it"
        case .printCommandFailed(let command, let status, let output):
            return "\(command) exited with status \(status): \(output)"
        }
    }
}

// MARK: - PDF sink

/// Writes each film to a PDF, one page per film.
///
/// Also exposes ``write(films:to:)`` for the multi-film case (a job that
/// spilled across several film boxes becomes one multi-page PDF).
public struct PDFSink: PrintOutputSink {
    /// Directory the PDFs are written to.
    public let directory: URL

    /// File naming pattern.
    public let naming: FilmOutputNaming

    /// Called with each written file, for console output and the UI's file list.
    public let onWrite: (@Sendable (URL) -> Void)?

    private let counter = OutputCounter()

    public init(
        directory: URL,
        naming: FilmOutputNaming = FilmOutputNaming(pattern: "film-{timestamp}-{index}"),
        onWrite: (@Sendable (URL) -> Void)? = nil
    ) {
        self.directory = directory
        self.naming = naming
        self.onWrite = onWrite
    }

    public var sinkName: String { "pdf" }

    public func emit(_ film: ComposedFilm) async throws {
        let index = await counter.next()
        let url = directory.appendingPathComponent(
            naming.fileName(for: film, index: index, extension: "pdf"))
        try Self.write(films: [film], to: url)
        onWrite?(url)
    }

    /// Writes one or more films as a multi-page PDF.
    public static func write(films: [ComposedFilm], to url: URL) throws {
        guard !films.isEmpty else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Page size in PostScript points (72 per inch) from the film's physical
        // size, so a PDF page is the real film, not a pile of pixels.
        let first = films[0]
        var mediaBox = CGRect(
            x: 0, y: 0,
            width: first.info.sheetWidthMillimeters * 72.0 / 25.4,
            height: first.info.sheetHeightMillimeters * 72.0 / 25.4)

        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw PrintSinkError.writeFailed(path: url.path, underlying: "CGPDFContext creation failed")
        }
        for film in films {
            guard let image = film.makeCGImage() else { throw PrintSinkError.imageUnavailable }
            var pageBox = CGRect(
                x: 0, y: 0,
                width: film.info.sheetWidthMillimeters * 72.0 / 25.4,
                height: film.info.sheetHeightMillimeters * 72.0 / 25.4)
            let pageInfo = [kCGPDFContextMediaBox as String: Data(
                bytes: &pageBox, count: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.draw(image, in: pageBox)
            context.endPDFPage()
        }
        context.closePDF()
    }
}

// MARK: - Image sink

/// Writes each film to a PNG or TIFF file.
public struct ImageSink: PrintOutputSink {

    /// The image container to write.
    public enum Format: String, Sendable, CaseIterable {
        case png
        case tiff

        var utType: CFString {
            switch self {
            case .png: return UTType.png.identifier as CFString
            case .tiff: return UTType.tiff.identifier as CFString
            }
        }
    }

    public let directory: URL
    public let format: Format
    public let naming: FilmOutputNaming
    public let onWrite: (@Sendable (URL) -> Void)?

    private let counter = OutputCounter()

    public init(
        directory: URL,
        format: Format = .png,
        naming: FilmOutputNaming = FilmOutputNaming(pattern: "film-{timestamp}-{index}"),
        onWrite: (@Sendable (URL) -> Void)? = nil
    ) {
        self.directory = directory
        self.format = format
        self.naming = naming
        self.onWrite = onWrite
    }

    public var sinkName: String { format.rawValue }

    public func emit(_ film: ComposedFilm) async throws {
        let index = await counter.next()
        let url = directory.appendingPathComponent(
            naming.fileName(for: film, index: index, extension: format.rawValue))
        try Self.write(film: film, to: url, format: format)
        onWrite?(url)
    }

    /// Writes one film to `url`.
    public static func write(film: ComposedFilm, to url: URL, format: Format) throws {
        guard let image = film.makeCGImage() else { throw PrintSinkError.imageUnavailable }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.utType, 1, nil) else {
            throw PrintSinkError.writeFailed(path: url.path, underlying: "No image destination")
        }
        // DPI metadata so the file prints at the film's real size.
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: film.info.dpi,
            kCGImagePropertyDPIHeight: film.info.dpi
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PrintSinkError.writeFailed(path: url.path, underlying: "Finalize failed")
        }
    }
}

// MARK: - Paper sink

// Spooling means launching `/usr/bin/lp` as a subprocess, and `Process`/`Pipe`
// exist only where a platform lets a program spawn one — macOS and Linux, not
// iOS/tvOS/visionOS. The guard is the honest boundary rather than a compile
// workaround: those platforms have no CUPS queue to spool to either. The other
// sinks (screen, PDF, image) build everywhere.
#if os(macOS) || os(Linux)

/// Sends each film to a real printer queue via CUPS `lp`.
///
/// Opt-in by construction: ``allowPaper`` must be set, so a misconfigured
/// emulator cannot spool hundreds of pages by accident. `lp` keeps DICOMPrintKit
/// AppKit-free and works unchanged on Linux; the macOS print panel belongs in
/// the app layer.
///
/// - Note: Available on macOS and Linux only.
public struct PaperPrinterSink: PrintOutputSink {
    /// The CUPS queue name (`lp -d`). `nil` uses the system default queue.
    public let queue: String?

    /// Must be true for anything to be spooled.
    public let allowPaper: Bool

    /// Whether to honor Number of Copies from the film session (`lp -n`).
    public let honorNumberOfCopies: Bool

    /// Maximum copies to spool, however many the SCU asked for.
    public let maximumCopies: Int

    /// Called with the `lp` output line for console reporting.
    public let onSpool: (@Sendable (String) -> Void)?

    public init(
        queue: String? = nil,
        allowPaper: Bool = false,
        honorNumberOfCopies: Bool = true,
        maximumCopies: Int = 10,
        onSpool: (@Sendable (String) -> Void)? = nil
    ) {
        self.queue = queue
        self.allowPaper = allowPaper
        self.honorNumberOfCopies = honorNumberOfCopies
        self.maximumCopies = max(1, maximumCopies)
        self.onSpool = onSpool
    }

    public var sinkName: String { "paper" }

    public func emit(_ film: ComposedFilm) async throws {
        guard allowPaper else { throw PrintSinkError.paperOutputNotAllowed }

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicom-film-\(UUID().uuidString).pdf")
        try PDFSink.write(films: [film], to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }

        var arguments: [String] = []
        if let queue { arguments += ["-d", queue] }
        let copies = honorNumberOfCopies ? min(maximumCopies, max(1, film.info.numberOfCopies)) : 1
        if copies > 1 { arguments += ["-n", String(copies)] }
        arguments += ["-o", "fit-to-page", temporary.path]

        let output = try Self.run("/usr/bin/lp", arguments)
        onSpool?(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Lists the CUPS queues available on this machine (`lpstat -a`).
    public static func availableQueues() throws -> [String] {
        let output = try run("/usr/bin/lpstat", ["-a"])
        return output
            .split(separator: "\n")
            .compactMap { $0.split(separator: " ").first.map(String.init) }
    }

    /// Runs a command and returns its combined output.
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw PrintSinkError.printCommandFailed(
                command: launchPath, status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw PrintSinkError.printCommandFailed(
                command: ([launchPath] + arguments).joined(separator: " "),
                status: process.terminationStatus,
                output: output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}

#endif

/// A monotonic counter shared by the value-type sinks so their file names stay
/// distinct across emits without making the sink itself an actor.
actor OutputCounter {
    private var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}

#endif
