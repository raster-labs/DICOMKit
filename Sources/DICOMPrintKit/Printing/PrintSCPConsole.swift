// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (event log text; status codes come from DICOMNetwork)
//
// PrintSCPConsole.swift
// DICOMPrintKit
//
// One formatter for everything the printer emulator says.
//
// `dicom-printscp` writes these lines to a terminal and DICOM Studio's Print SCP
// screen shows them in its event log; both call the functions below rather than
// phrasing events themselves, so a terminal-vs-app comparison stays clean (the
// same rule `NetworkConsole` enforces for the query/send/retrieve tools).
//

import Foundation
import DICOMNetwork

// MARK: - Log model

/// Severity of a Print SCP event line.
public enum PrintSCPLogLevel: String, Sendable, CaseIterable, Codable {
    case info
    case connection
    case filmReceived
    case warning
    case error
}

/// One line of the Print SCP event log.
public struct PrintSCPLogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let level: PrintSCPLogLevel
    public let message: String
    public let remoteAETitle: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: PrintSCPLogLevel,
        message: String,
        remoteAETitle: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.remoteAETitle = remoteAETitle
    }
}

// MARK: - Counters

/// Running totals a listener reports while it runs and when it stops.
public struct PrintSCPSessionCounters: Sendable, Equatable {
    /// Associations accepted since the listener started.
    public var associations = 0
    /// Films printed (N-ACTION) since the listener started.
    public var films = 0
    /// Failed DIMSE requests and transport errors since the listener started.
    public var errors = 0

    public init(associations: Int = 0, films: Int = 0, errors: Int = 0) {
        self.associations = associations
        self.films = films
        self.errors = errors
    }

    /// Folds one event into the totals.
    public mutating func record(_ event: PrintServerEvent) {
        switch event {
        case .associationEstablished: associations += 1
        case .filmPrinted:            films += 1
        case .requestFailed, .error:  errors += 1
        default:                      break
        }
    }

    /// "3 associations, 5 films, 0 errors".
    public var summary: String {
        "\(associations) association\(associations == 1 ? "" : "s"), "
            + "\(films) film\(films == 1 ? "" : "s"), "
            + "\(errors) error\(errors == 1 ? "" : "s")"
    }
}

// MARK: - Console

/// Text and JSON for every line the printer emulator emits.
public enum PrintSCPConsole {

    // MARK: Events

    /// The log entry for a server event, or `nil` when the event carries no line
    /// of its own (`.started`, whose bound port the surface reports itself with
    /// ``startedLine(settings:boundPort:)``).
    public static func logEntry(for event: PrintServerEvent) -> PrintSCPLogEntry? {
        switch event {
        case .started:
            return nil

        case .stopped:
            return entry(.info, "Listener stopped")

        case .associationEstablished(let info):
            return entry(.connection,
                         "Association from \(info.callingAETitle) (\(endpoint(of: info)))",
                         ae: info.callingAETitle)

        case .associationReleased(let callingAE):
            return entry(.connection, "Association released by \(callingAE)", ae: callingAE)

        case .associationRejected(let callingAE, let reason):
            return entry(.warning, "Rejected \(callingAE): \(reason)", ae: callingAE)

        case .associationTimedOut(let callingAE, let seconds):
            return entry(.warning,
                         "Association from \(callingAE) timed out after \(Int(seconds))s",
                         ae: callingAE)

        case .filmSessionCreated(let uid, let callingAE):
            return entry(.info, "Film session created \(uid)", ae: callingAE)

        case .filmBoxCreated(let uid, let layout, let imageBoxUIDs):
            return entry(.info,
                         "Film box \(uid) — \(layout.rows)×\(layout.columns), "
                            + "\(imageBoxUIDs.count) image box\(imageBoxUIDs.count == 1 ? "" : "es")")

        case .imageBoxReceived(_, let position, let rows, let columns):
            return entry(.info, "Image box \(position) filled — \(columns)×\(rows) px")

        case .imageBoxCorrected(_, let position, let detail):
            // A warning rather than a notice: the film prints, but the sender
            // is non-conformant and whoever runs the printer should know.
            return entry(.warning, "Image box \(position) corrected — \(detail)")

        case .filmPrinted(let film):
            return entry(.filmReceived,
                         "Film printed — \(film.layout.rows)×\(film.layout.columns), "
                            + "\(film.filledImageBoxes.count)/\(film.imageBoxes.count) images",
                         ae: film.callingAETitle)

        case .deleted(let uid):
            return entry(.info, "Deleted \(uid)")

        case .requestFailed(let command, let status, let detail):
            let reason = detail ?? status.explanation
            return entry(.warning,
                         "\(command) failed (0x\(String(format: "%04X", status.rawValue))): \(reason)")

        case .error(let error):
            return entry(.error, "Printer error: \(describe(error))")
        }
    }

    /// One console line for an event, timestamped and tagged: `12:04:31  [warn]  …`.
    public static func consoleLine(for entry: PrintSCPLogEntry) -> String {
        "\(clockTime(entry.timestamp))  \(tag(entry.level))  \(entry.message)"
    }

    /// One JSON object for an event, for `--format json`.
    ///
    /// Written on a single line: an event stream is consumed line by line
    /// (`| jq -c`, `while read`), unlike the one-off result objects the other
    /// print tools pretty-print.
    public static func jsonLine(for entry: PrintSCPLogEntry) -> String? {
        var object: [String: Any] = [
            "time": iso8601(entry.timestamp),
            "level": entry.level.rawValue,
            "message": entry.message
        ]
        if let ae = entry.remoteAETitle { object["callingAE"] = ae }
        return json(object, pretty: false)
    }

    // MARK: Lifecycle lines

    /// "Listening on port 11113 as DCMPRINT" — the address to configure on the
    /// sending device.
    public static func startedLine(settings: PrintSCPSettings, boundPort: UInt16) -> String {
        "Listening on port \(boundPort) as \(settings.effectiveAETitle)"
    }

    /// The configuration echo printed when the listener starts.
    public static func startupSummary(settings: PrintSCPSettings, boundPort: UInt16) -> [String] {
        var lines = [
            startedLine(settings: settings, boundPort: boundPort),
            "  Printer:      \(settings.printerName) (\(settings.manufacturer) "
                + "\(settings.manufacturerModelName))",
            "  Status:       \(settings.printerStatus.rawValue) "
                + "(\(settings.effectivePrinterStatusInfo))",
            "  Composition:  \(Int(settings.dpi)) DPI, "
                + "\(densityLabel(settings.densityMapping))"
                + "\(settings.drawAnnotations ? ", annotations" : "")"
                + "\(settings.drawTrimMarks ? ", trim boxes" : "")",
            "  Capability:   \(settings.supportsColor ? "color + grayscale" : "grayscale only")"
                + "\(settings.acceptPresentationLUT ? ", presentation LUT" : "")"
                + "\(settings.acceptAnnotationBox ? ", annotation boxes" : "")"
                + "\(settings.pushPrintJobEvents ? ", job events" : "")"
        ]
        if let allowed = settings.callingAEWhitelist {
            lines.append("  Accepting:    \(allowed.sorted().joined(separator: ", "))")
        }
        if let denied = settings.callingAEBlacklist {
            lines.append("  Refusing:     \(denied.sorted().joined(separator: ", "))")
        }
        lines.append("  Output:       \(outputSummary(settings: settings))")
        return lines
    }

    /// "PNG + PDF → ~/Films" / "screen only" — where received films go.
    public static func outputSummary(settings: PrintSCPSettings) -> String {
        var targets: [String] = []
        if settings.saveImage { targets.append(settings.imageFormat.displayName) }
        if settings.savePDF { targets.append("PDF") }

        var text: String
        if targets.isEmpty {
            text = "none (films are received and discarded)"
        } else {
            text = targets.joined(separator: " + ") + " → " + settings.outputDirectoryURL.path
        }
        if settings.sendToPaperQueue {
            let queue = settings.paperQueue.trimmingCharacters(in: .whitespaces)
            text += ", paper queue \(queue.isEmpty ? "(system default)" : queue)"
        }
        return text
    }

    /// "Stopped — 3 associations, 5 films, 0 errors".
    public static func stoppedLine(counters: PrintSCPSessionCounters) -> String {
        "Stopped — \(counters.summary)"
    }

    // MARK: Films

    /// A one-line description of a composed film.
    public static func filmLine(_ film: ComposedFilm) -> String {
        let info = film.info
        return "Film from \(info.callingAETitle) — \(info.filmSize), "
            + "\(info.rows)×\(info.columns), \(info.filledImageBoxCount)/\(info.imageBoxCount) images, "
            + "\(film.width)×\(film.height) px at \(Int(info.dpi)) DPI"
    }

    /// The film's attributes, one per line, for verbose output and the app's
    /// film inspector.
    public static func filmDetail(_ film: ComposedFilm) -> [String] {
        let info = film.info
        var lines = [
            "  Job:          \(info.printJobUID)",
            "  Session:      \(info.filmSessionUID)",
            "  Film box:     \(info.filmBoxUID)",
            "  Layout:       \(info.imageDisplayFormat) (\(info.rows)×\(info.columns))",
            "  Film:         \(info.filmSize), \(info.filmOrientation), \(info.mediumType)",
            "  Sheet:        \(format(info.sheetWidthMillimeters))×"
                + "\(format(info.sheetHeightMillimeters)) mm at \(Int(info.dpi)) DPI",
            "  Copies:       \(info.numberOfCopies)",
            "  Magnify:      \(info.magnificationType)",
            "  Density:      border \(info.borderDensity), empty \(info.emptyImageDensity), "
                + "mapping \(densityLabel(info.densityMapping))",
            "  Trim:         \(info.trim)"
        ]
        if let min = info.minDensity { lines.append("  Min density:  \(min)") }
        if let max = info.maxDensity { lines.append("  Max density:  \(max)") }
        if let shape = info.presentationLUTShape { lines.append("  LUT shape:    \(shape)") }
        if !info.annotations.isEmpty {
            lines.append("  Annotations:  \(info.annotations.joined(separator: " | "))")
        }
        if !info.skippedImageBoxes.isEmpty {
            lines.append("  Skipped:      \(info.skippedImageBoxes.joined(separator: " | "))")
        }
        return lines
    }

    /// The film's attributes as pretty-printed JSON (the app's "Copy attributes"
    /// and the CLI's `--format json` film record).
    public static func filmJSON(_ film: ComposedFilm) -> String? {
        try? film.info.jsonRepresentation()
    }

    // MARK: Printer status

    /// The emulated printer's reported status, as `dicom-print status` would
    /// receive it.
    public static func printerStatusText(settings: PrintSCPSettings) -> [String] {
        PrintConsoleFormatter.printerStatusText(settings.reportedPrinterStatus)
    }

    /// The same, as JSON.
    public static func printerStatusJSON(settings: PrintSCPSettings) -> String? {
        PrintConsoleFormatter.printerStatusJSON(settings.reportedPrinterStatus)
    }

    // MARK: Paper queues

    /// The paper-queue list.
    public static func queuesText(_ queues: [String]) -> [String] {
        guard !queues.isEmpty else {
            return ["No paper printer queues found"]
        }
        return ["Paper printer queues (\(queues.count)):"] + queues.map { "  \($0)" }
    }

    /// The same, as JSON.
    public static func queuesJSON(_ queues: [String]) -> String? {
        json(["queues": queues, "count": queues.count])
    }

    // MARK: Errors

    /// A message worth showing.
    ///
    /// A bare `localizedDescription` on the library's own error enums degrades to
    /// "The operation couldn't be completed", which hides exactly the detail a
    /// port clash or a bad AE title needs. `String(describing:)` picks up a
    /// type's own `CustomStringConvertible` text instead.
    public static func describe(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription { return localized }
        return String(describing: error)
    }

    // MARK: - Helpers

    private static func entry(
        _ level: PrintSCPLogLevel, _ message: String, ae: String? = nil
    ) -> PrintSCPLogEntry {
        PrintSCPLogEntry(level: level, message: message, remoteAETitle: ae)
    }

    /// The remote endpoint as one string.
    ///
    /// The Print SCP reports the peer as a whole endpoint description in
    /// `remoteHost` and leaves `remotePort` at 0, so appending the port blindly
    /// renders "127.0.0.1:53167:0".
    private static func endpoint(of info: AssociationInfo) -> String {
        info.remotePort == 0 ? info.remoteHost : "\(info.remoteHost):\(info.remotePort)"
    }

    private static func tag(_ level: PrintSCPLogLevel) -> String {
        switch level {
        case .info:         return "[info]"
        case .connection:   return "[conn]"
        case .filmReceived: return "[film]"
        case .warning:      return "[warn]"
        case .error:        return "[fail]"
        }
    }

    /// The human label for a density mapping, from the shared option catalog.
    public static func densityLabel(_ mapping: DensityMapping) -> String {
        PrintOptionCatalog.densityMappings.first { $0.value == mapping }?.label ?? mapping.rawValue
    }

    private static func format(_ value: Double) -> String {
        String(format: value == value.rounded() ? "%.0f" : "%.1f", value)
    }

    private static func json(_ object: [String: Any], pretty: Bool = true) -> String? {
        let options: JSONSerialization.WritingOptions = pretty
            ? [.prettyPrinted, .sortedKeys]
            : [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: options) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Built per call rather than cached: `DateFormatter` is not `Sendable`, and
    /// a console line is not on any hot path.
    private static func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
