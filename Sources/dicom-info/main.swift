// NEMA-verified: 2026a, checked 2026-10-01 — --tag accepts PS3.6 2026a Table 6-1/7-1 keywords exactly, matched by the shared MetadataPresenter (D148; the CLI keyword workaround is gone), plus the name/tag substring match; printed (tag, name, VR) of a CT fixture match PS3.6 Table 6-1/7-1 31/31; date/time values print in their PS3.5 Table 6.2-1 VR form; output format vocabulary text/json/csv carries no DICOM-standard data
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

struct DICOMInfo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-info",
        abstract: "Display metadata from DICOM medical imaging files",
        discussion: """
            Extracts and displays metadata tags from DICOM Part 10 files.
            Supports multiple output formats for different use cases.
            
            Examples:
              dicom-info scan.dcm
              dicom-info --format json report.dcm
              dicom-info --bounded-summary --format json scan.dcm
              dicom-info --tag PatientName --tag StudyDate exam.dcm

            --tag takes a PS3.6 keyword (exact, e.g. PatientName), a tag (0010,0010), or
            any part of a PS3.6 Attribute name (case-insensitive, e.g. "Patient").
            """,
        version: DICOMKit.version
    )
    
    @Argument(help: "Path to the DICOM file")
    var filePath: String
    
    @Option(name: .shortAndLong, help: "Output format: text, json, csv")
    var format: OutputFormat = .text
    
    @Option(name: .shortAndLong, help: "Filter by keyword, tag (GGGG,EEEE) or part of the Attribute name (can be used multiple times)")
    var tag: [String] = []
    
    @Flag(name: .long, help: "Include private tags in output")
    var showPrivate: Bool = false
    
    @Flag(name: .long, help: "Show file statistics")
    var statistics: Bool = false
    
    @Flag(name: .long, help: "Force parsing of files without DICM prefix")
    var force: Bool = false
    
    @Flag(name: .long, help: "Strictly parse verified source windows and report source/index storage usage without displaying tag values")
    var boundedSummary: Bool = false

    mutating func validate() throws {
        if boundedSummary && (force || !tag.isEmpty || showPrivate || statistics || format == .csv) {
            throw ValidationError("--bounded-summary supports text or JSON and cannot be combined with --force, --tag, --show-private, or --statistics")
        }
    }

    mutating func run() throws {
        let fileURL = URL(fileURLWithPath: filePath)
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ValidationError("File not found: \(filePath)")
        }
        
        if boundedSummary {
            try renderBoundedSummary(fileURL)
            return
        }

        let fileData = try Data(contentsOf: fileURL)
        let dicomFile = try DICOMFile.read(from: fileData, force: force)
        
        let presenter = MetadataPresenter(
            file: dicomFile,
            filterTags: tag,
            includePrivate: showPrivate,
            showStats: statistics
        )
        
        let output = try presenter.render(format: MetadataOutputFormat(rawValue: format.rawValue) ?? .text)
        print(output, terminator: "")
    }

    private func renderBoundedSummary(_ url: URL) throws {
        #if canImport(Darwin) || canImport(Glibc)
        // CLI arguments, Foundation adapters and output formatting are outside
        // the managed source/index backing contract reported by this command.
        let budget = try DICOMAllocationBudget()
        let source = try VerifiedFileByteSource(url: url, budget: budget)
        let options = ParsingOptions(strictEncapsulation: true,
            maximumEncapsulatedBytes: 256 * 1024 * 1024,
            allowedTransferSyntaxUIDs: ["1.2.840.10008.1.2", "1.2.840.10008.1.2.1",
                "1.2.840.10008.1.2.4.50", "1.2.840.10008.1.2.4.70", "1.2.840.10008.1.2.4.80"],
            validationPolicy: .strict)
        let file = try DICOMFile.readBounded(from: source, options: options)
        let meta = try file.fileMetaInformation()
        let dataSet = try file.dataSet()
        try file.validateSource()
        let receipt = budget.receipt
        let report = BoundedSummary(sourceBytes: file.sourceByteCount,
            contentSHA256: file.contentIdentity.hexadecimal,
            transferSyntaxUID: file.transferSyntaxUID,
            fileMetaElements: meta.count, topLevelElements: dataSet.count,
            currentBackingBytes: receipt.currentTotal, peakBackingBytes: receipt.peakTotal,
            peakEncodedBytes: receipt.peak.encoded, peakMetadataBytes: receipt.peak.metadata)
        if format == .json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
        } else {
            print("Source bytes: \(report.sourceBytes)\nSHA-256: \(report.contentSHA256)\nTransfer syntax: \(report.transferSyntaxUID)")
            print("File meta elements: \(report.fileMetaElements)\nTop-level elements: \(report.topLevelElements)")
            print("Managed backing bytes: \(report.currentBackingBytes) current, \(report.peakBackingBytes) peak")
            print("Scope: source/index backing only; CLI formatting, runtime and stack are excluded.")
        }
        #else
        throw ValidationError("Bounded source inspection is unavailable on this platform")
        #endif
    }
}

private struct BoundedSummary: Encodable {
    let sourceBytes: Int
    let contentSHA256: String
    let transferSyntaxUID: String
    let fileMetaElements: Int
    let topLevelElements: Int
    let currentBackingBytes: Int
    let peakBackingBytes: Int
    let peakEncodedBytes: Int
    let peakMetadataBytes: Int
    let allocationScope = "source/index backing; excludes CLI formatting, runtime and stack"
}

enum OutputFormat: String, ExpressibleByArgument {
    case text
    case json
    case csv
    
    var defaultValueDescription: String {
        switch self {
        case .text: return "plain text (default)"
        case .json: return "JSON format"
        case .csv: return "CSV format"
        }
    }
}

DICOMInfo.main()
