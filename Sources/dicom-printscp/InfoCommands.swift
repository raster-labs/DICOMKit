// NEMA-verified: 2026a, checked 2026-10-01 — status names the N-GET attributes per PS3.3 2026a Table C.13-9 / PS3.6 Table 6-1 and the Printer SOP Instance UID per PS3.6 Table A-1; the text/JSON is DICOMPrintKit's PrintConsoleFormatter (labels reported as a deferred finding); queues carries no DICOM-standard data
//
// InfoCommands.swift
// dicom-printscp
//
// `status` and `queues` — the two questions that do not need a listener.
//

import Foundation
import ArgumentParser
import DICOMPrintKit

// MARK: - status

/// Reports what the emulator would answer an SCU's N-GET with, without binding
/// a port — so a configuration can be checked before a modality is pointed at it.
struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the printer identity and status the emulator would report",
        discussion: """
            Answers the same question `dicom-print status` asks over the network
            (N-GET on the Printer SOP Instance, 1.2.840.10008.5.1.1.17): Printer
            Status (2110,0010), Printer Status Info (2110,0020), Printer Name
            (2110,0030), Manufacturer and Manufacturer's Model Name — from the
            configuration alone. Useful for checking a --config file, and
            for confirming what --printer-status failure will make an SCU see.

            --format json keys each attribute by its PS3.6 keyword (PrinterStatus,
            PrinterStatusInfo, PrinterName, Manufacturer, ManufacturerModelName);
            the older keys status, statusInfo, name, manufacturer and model carry
            the same values and are deprecated.
            """
    )

    @OptionGroup var transport: TransportOptions
    @OptionGroup var composition: CompositionOptions
    @OptionGroup var filmOutput: FilmOutputOptions
    @OptionGroup var configOptions: ConfigOptions

    @Option(name: .long, help: "Output format: text, json")
    var format: OutputFormat = .text

    @Flag(name: .shortAndLong, help: "Show the full resolved configuration")
    var verbose: Bool = false

    func run() async throws {
        var settings = configOptions.load()
        try transport.apply(to: &settings)
        try composition.apply(to: &settings)
        try filmOutput.apply(to: &settings, outputWasConfigured: configOptions.hasStoredSettings)

        let console = Console(format: format, quiet: false)

        if configOptions.saveConfig {
            try configOptions.save(settings)
            console.line("Wrote \(configOptions.url.path)")
            return
        }

        switch format {
        case .text:
            console.lines(PrintSCPConsole.printerStatusText(settings: settings))
            if verbose {
                console.line("")
                console.lines(PrintSCPConsole.startupSummary(
                    settings: settings, boundPort: UInt16(clamping: settings.port)))
            }
        case .json:
            if verbose {
                let data = try PrintSCPSettingsFile.encode(settings)
                console.line(String(decoding: data, as: UTF8.self))
            } else if let json = PrintSCPConsole.printerStatusJSON(settings: settings) {
                console.line(json)
            }
        }
    }
}

// MARK: - queues

/// Lists the CUPS queues `--paper-queue` can name.
struct QueuesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "queues",
        abstract: "List the paper printer queues available for --paper-queue"
    )

    @Option(name: .long, help: "Output format: text, json")
    var format: OutputFormat = .text

    func run() async throws {
        let queues = PrintSCPService().availablePaperQueues()
        let console = Console(format: format, quiet: false)

        switch format {
        case .text:
            console.lines(PrintSCPConsole.queuesText(queues))
        case .json:
            if let json = PrintSCPConsole.queuesJSON(queues) { console.line(json) }
        }
    }
}
