import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMWeb
import DICOMDictionary

// NEMA-verified: 2026a, checked 2026-10-01 — options read against PS3.18 2026a F.2.2 (ascending attribute order,
// 8-hex attribute names), F.2.5 (empty attribute kept as "vr" only), F.2.6 / F.2.7 (BulkDataURI, InlineBinary),
// 10.4.1.1.2 / 10.4.3.3.2 (Metadata resource: all Bulk Data left out or referenced, D111; 2026-10-01 D110 item-path
// BulkDataURIs, D113 stderr warning for an unresolved BulkDataURI on --reverse); 11 options; output validated by script against Table F.2.3-1 (34 VRs)

struct DICOMJson: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-json",
        abstract: "Convert between DICOM and JSON formats",
        discussion: """
            Converts DICOM files to JSON format (DICOM JSON Model, PS3.18 Annex F)
            and vice versa, with bulk data handling. Attribute objects are named by
            the eight-character uppercase hexadecimal tag and ordered by it (F.2.2);
            an attribute with an empty Value Field is kept as {"vr": ...} (F.2.5).

            Examples:
              dicom-json file.dcm --output file.json
              dicom-json file.json --output file.dcm --reverse
              dicom-json file.dcm --pretty
            """,
        version: "1.1.4"
    )

    @Argument(help: "Input file (DICOM or JSON)")
    var input: String

    @Option(name: .shortAndLong, help: "Output file path")
    var output: String?

    @Flag(name: .shortAndLong, help: "Convert from JSON to DICOM")
    var reverse: Bool = false

    @Flag(name: .shortAndLong, help: "Pretty-print JSON output")
    var pretty: Bool = false

    // PS3.18 F.2.2: "Attribute objects ... shall be ordered by their property name in ascending
    // lexicographic (alphabetic) order", so output written with this flag is not conformant.
    // P-JSON-NO-SORT-KEYS (approved 2026-10-01): deprecated; still works, stderr note on use.
    @Flag(name: .long, help: "Deprecated: don't order attribute objects by tag (the output then breaks the PS3.18 F.2.2 ascending order; will be removed)")
    var noSortKeys: Bool = false

    /// One-line stderr notes for deprecated options in use (P-JSON-NO-SORT-KEYS).
    var deprecationNotes: [String] {
        noSortKeys
            ? ["dicom-json: warning: --no-sort-keys is deprecated and will be removed: PS3.18 2026a F.2.2 requires attribute objects in ascending tag order"]
            : []
    }

    // NOTE: the former --format standard|dicomweb and --stream flags were
    // removed: both were declared but never read (the encoder always emits the
    // DICOMweb PS3.18 JSON model, and no streaming path exists), so they were
    // silently inert on every surface.

    // PS3.18 F.2.5: an attribute present but empty "shall be preserved" with no Value,
    // BulkDataURI or InlineBinary, so keeping it is the default; --no-include-empty drops it.
    @Flag(name: .long, inversion: .prefixedNo,
          help: "Keep attributes with an empty Value Field as {\"vr\": ...} (PS3.18 F.2.5)")
    var includeEmpty: Bool = true

    @Option(name: .long, help: "With --bulk-data-url: OB/OD/OF/OL/OV/OW/UN values longer than this many bytes become a BulkDataURI (0: all of them); without it every such value is InlineBinary (PS3.18 F.2.6, F.2.7)")
    var inlineThreshold: Int = 1024

    @Option(name: .long, help: "Base URL for BulkDataURI values (PS3.18 F.2.6); the URI is <url>/<GGGGEEEE>, inside sequence items <url>/<SQ tag>/<item n>/<GGGGEEEE>")
    var bulkDataURL: String?

    @Flag(name: .long, help: "Metadata only (PS3.18 10.4.1.1.2): leave out every OB/OD/OF/OL/OV/OW/UN value at any depth (Pixel Data, Float Pixel Data, Encapsulated Document, Waveform, Overlay, LUTs); with --bulk-data-url each becomes a BulkDataURI instead")
    var metadataOnly: Bool = false

    @Option(name: .long, help: "Keep only this attribute: PS3.6 keyword, GGGG,EEEE or GGGGEEEE (can be used multiple times)")
    var filterTag: [String] = []

    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false

    mutating func run() throws {
        guard FileManager.default.fileExists(atPath: input) else {
            throw ValidationError("File not found: \(input)")
        }
        for note in deprecationNotes {
            FileHandle.standardError.write(Data((note + "\n").utf8))
        }

        // Entire pipeline via the SHARED DataExchangeWorkflow (DICOMWeb) — the
        // same code DICOMStudio's Workshop executor runs, so behavior (default
        // output path, always-write-file) and verbose text cannot drift.
        let outputPath = output ?? DataExchangeWorkflow.defaultOutputPath(
            input: input, reverse: reverse, format: .json)

        let options = DataExchangeWorkflow.Options(
            reverse: reverse, pretty: pretty, includeEmpty: includeEmpty,
            inlineThreshold: inlineThreshold, bulkDataURL: bulkDataURL,
            metadataOnly: metadataOnly, filterTags: Self.normalizedFilterTags(filterTag), verbose: verbose,
            sortKeys: !noSortKeys
        )

        for line in DataExchangeWorkflow.headerLines(
            input: input, output: outputPath, reverse: reverse, format: .json, verbose: verbose) {
            print(line)
        }

        let readStart = Date()
        let inputData = try Data(contentsOf: URL(fileURLWithPath: input))
        let readSeconds = Date().timeIntervalSince(readStart)

        let result: (data: Data, console: [String])
        do {
            result = reverse
                ? try DataExchangeWorkflow.decode(textData: inputData, format: .json, options: options, readSeconds: readSeconds)
                : try DataExchangeWorkflow.encode(dicomData: inputData, format: .json, options: options, readSeconds: readSeconds)
        } catch let e as DataExchangeWorkflow.WorkflowError {
            throw ValidationError(e.errorDescription ?? "\(e)")
        }
        // Warnings (an unresolved BulkData reference on --reverse, PS3.18 F.2.6) go to stderr
        for line in result.console {
            if line.hasPrefix("Warning:") {
                FileHandle.standardError.write(Data(("dicom-json: " + line + "\n").utf8))
            } else {
                print(line)
            }
        }

        let writeStart = Date()
        try result.data.write(to: URL(fileURLWithPath: outputPath))
        let writeSeconds = Date().timeIntervalSince(writeStart)
        let writeLines = reverse
            ? DataExchangeWorkflow.reverseWriteLine(size: Int64(result.data.count), seconds: writeSeconds, verbose: verbose)
            : DataExchangeWorkflow.forwardWriteLine(seconds: writeSeconds, verbose: verbose)
        for line in writeLines { print(line) }

        for line in DataExchangeWorkflow.completionLines(
            outputSize: Int64(result.data.count), verbose: verbose) {
            print(line)
        }
    }

    /// Accepts the eight-character tag (the F.2.2 attribute name, e.g. `00100020`) and
    /// `(GGGG,EEEE)` besides the keyword and `GGGG,EEEE` forms the shared workflow resolves.
    static func normalizedFilterTags(_ specs: [String]) -> [String] {
        specs.map { spec in
            var s = spec.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("("), s.hasSuffix(")") { s = String(s.dropFirst().dropLast()) }
            if s.count == 8, s.allSatisfy(\.isHexDigit) {
                return "\(s.prefix(4)),\(s.suffix(4))"
            }
            return s.contains(",") ? s : spec
        }
    }
}

DICOMJson.main()
