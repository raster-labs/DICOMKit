// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (ArgumentParser shell, output-format enum, console routing, error type)
//
// DICOMPrintSCPCommand.swift
// dicom-printscp
//
// The headless printer emulator: the receiving half of `dicom-print`.
//
// This file is an ArgumentParser shell and nothing more. The settings type, the
// server/sink/composer assembly, the console wording and the local composer are
// all `DICOMPrintKit` — the same code DICOM Studio's Print SCP screen runs — so
// a film received here and a film received in the app are negotiated, composed
// and described identically.
//

import Foundation
import ArgumentParser
import DICOMPrintKit

/// Tool version — used in both `CommandConfiguration` and verbose output.
let scpToolVersion = "1.0.0"

public struct PrintSCPCommand: AsyncParsableCommand {
    public init() {}

    /// Parses the same command surface used by the executable without starting
    /// a listener, touching a settings file, or producing output.
    public static func validate(arguments: [String]) throws {
        _ = try parseAsRoot(arguments)
    }

    /// Executes in the caller's environment. The app supplies callbacks and
    /// cancellation; only a process context installs signal handling.
    public static func execute(arguments: [String], context: PrintCommandContext) async throws {
        let command = try parseAsRoot(arguments)
        guard let executable = command as? any PrintExecutableCommand else {
            throw PrintSCPCommandError("Choose serve, simulate, status, or queues")
        }
        try await executable.execute(context: context)
    }
    public static let configuration = CommandConfiguration(
        commandName: "dicom-printscp",
        abstract: "DICOM Print SCP - emulate a DICOM printer and compose received film",
        discussion: """
            Listens for Print SCUs (modalities, workstations, `dicom-print send`,
            DCMTK's `dcmprscu`), answers the Print Management N-services, and
            composes every printed film onto a sheet that can be written as PNG,
            TIFF or PDF, or spooled to a real paper queue.

            Because the printer is emulated, it can be made to misbehave on
            purpose: `--printer-status failure` exercises an SCU's error path,
            `--no-accept-color` and `--film-size` narrow what is negotiated.

            Examples:
              # Receive film and write each sheet as a PNG
              dicom-printscp serve --port 11113 --ae-title DCMPRINT \\
                  --output png --output-dir ~/Films

              # A printer that says it is out of film
              dicom-printscp serve --printer-status failure

              # Accept only two modalities, keep a PDF archive
              dicom-printscp serve --allow-ae CT1 --allow-ae MR1 \\
                  --output pdf --output-dir ~/Films

              # Spool received film to a real printer
              dicom-printscp serve --paper-queue HP_LaserJet --allow-paper

              # Compose a sheet locally, no network involved
              dicom-printscp simulate scan.dcm --layout 2x2 --output png

              # What the emulator would report to an SCU's N-GET
              dicom-printscp status --printer-status warning

              # Paper queues available for --paper-queue
              dicom-printscp queues
            """,
        version: scpToolVersion,
        subcommands: [
            SCPServeCommand.self,
            SCPSimulateCommand.self,
            SCPStatusCommand.self,
            SCPQueuesCommand.self
        ],
        defaultSubcommand: SCPServeCommand.self
    )
}

// MARK: - Output format

/// How a subcommand reports.
enum SCPOutputFormat: String, ExpressibleByArgument, CaseIterable {
    case text
    case json
}

// MARK: - SCPConsole

/// Routes console output: results to stdout, diagnostics to stderr.
///
/// Matches `dicom-print`'s contract so the two tools can be piped in the same
/// script — `--format json` keeps stdout parseable.
struct SCPConsole: Sendable {
    let format: SCPOutputFormat
    let quiet: Bool
    let context: PrintCommandContext

    func line(_ text: String) {
        guard !quiet else { return }
        context.output(text)
    }

    func lines(_ texts: [String]) {
        texts.forEach { line($0) }
    }

    /// Writes one event, in whichever shape `--format` asked for.
    func event(_ entry: PrintSCPLogEntry) {
        guard !quiet else { return }
        switch format {
        case .text:
            context.output(PrintSCPConsole.consoleLine(for: entry))
        case .json:
            if let json = PrintSCPConsole.jsonLine(for: entry) { context.output(json) }
        }
    }

    /// Diagnostics and failures always go to stderr, quiet or not.
    func error(_ text: String) {
        context.diagnostic(text)
    }
}

// MARK: - Errors

/// A failure with a message already fit for the terminal.
struct PrintSCPCommandError: Error, CustomStringConvertible, LocalizedError {
    let description: String
    var errorDescription: String? { description }

    init(_ description: String) {
        self.description = description
    }
}
