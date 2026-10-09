// NEMA-verified: 2026a, checked 2026-10-01 — --ignore-tag accepts the Tag notation of PS3.6 2026a Table 6-1 ((gggg,eeee), also gggg,eeee / ggggeeee; PS3.5 7.1.1) and Table 6-1 keywords; --ignore-private is the odd-group rule of PS3.5 7.1/7.8, at every nesting level (D152); --compare-pixels/--tolerance are per Pixel Sample Value, PS3.5 8.1.1 (D153); the 10 options otherwise carry no DICOM-standard data (comparison engine verified in DICOMKit/Comparison)
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

// The comparison engine (`DICOMComparer`), its result types, the report renderer
// (`ComparisonReport`), and `ComparisonOutputFormat` now live in the DICOMKit
// library so the CLI and DICOMStudio run the exact same code. ArgumentParser
// stays out of the library, so the CLI supplies the command-line conformance here.
extension ComparisonOutputFormat: ExpressibleByArgument {}

struct DICOMDiff: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-diff",
        abstract: "Compare two DICOM files and report differences",
        discussion: """
            Compares metadata tags and optionally pixel data between two DICOM files.
            Supports filtering, tolerance settings, and multiple output formats.

            Exit status: 0 identical, 1 different, 2 a file is missing or cannot be
            read as DICOM (64: invalid arguments).

            Examples:
              dicom-diff file1.dcm file2.dcm
              dicom-diff --compare-pixels --tolerance 5 original.dcm processed.dcm
              dicom-diff --ignore-tag 0008,0012 --format json file1.dcm file2.dcm
            """,
        version: "1.0.0"
    )

    @Argument(help: "First DICOM file to compare")
    var file1: String

    @Argument(help: "Second DICOM file to compare")
    var file2: String

    @Option(name: .shortAndLong, help: "Output format: text, json, summary")
    var format: ComparisonOutputFormat = .text

    @Option(name: .long, help: "Tag to ignore, repeatable: (gggg,eeee), gggg,eeee, ggggeeee or a PS3.6 keyword (e.g. '(0008,0018)' or 'SOPInstanceUID')")
    var ignoreTag: [String] = []

    @Flag(name: .long, help: "Ignore private data elements (odd group number, PS3.5 7.1), also inside sequence items")
    var ignorePrivate: Bool = false

    @Flag(name: .long, help: "Compare Pixel Data (7FE0,0010) sample by sample (decoded; PS3.5 8.1.1) instead of as one element")
    var comparePixels: Bool = false

    @Option(name: .long, help: "Largest Pixel Sample Value difference (PS3.5 8.1.1) in Pixel Data (7FE0,0010) still treated as identical (default: 0)")
    var tolerance: Double = 0.0

    @Flag(name: .long, help: "Quick mode: metadata only, overrides --compare-pixels")
    var quick: Bool = false

    @Flag(name: .long, help: "Show identical tags in detailed mode")
    var showIdentical: Bool = false

    @Flag(name: .long, help: "Verbose output with detailed information")
    var verbose: Bool = false

    /// Exit status (P-DIFF-1, approved 2026-10-01; the diff(1)/cmp(1) convention):
    /// 0 the files are identical, 1 they differ, 2 a file is missing or cannot be read or parsed
    /// as DICOM, or the comparison fails; 64 stays the ArgumentParser usage error.
    static let exitIdentical: Int32 = 0
    static let exitDifferent: Int32 = 1
    static let exitTrouble: Int32 = 2

    /// Reads and parses one input; any failure is reported on stderr and ends with exit 2.
    static func load(_ path: String) throws -> DICOMFile {
        guard FileManager.default.fileExists(atPath: path) else {
            throw trouble("File not found: \(path)")
        }
        do {
            return try DICOMFile.read(from: try Data(contentsOf: URL(fileURLWithPath: path)))
        } catch {
            throw trouble("Cannot read \(path) as DICOM: \(error)")
        }
    }

    static func trouble(_ message: String) -> ExitCode {
        FileHandle.standardError.write(Data("dicom-diff: error: \(message)\n".utf8))
        return ExitCode(exitTrouble)
    }

    mutating func run() throws {
        let dicomFile1 = try Self.load(file1)
        let dicomFile2 = try Self.load(file2)

        if verbose {
            print("Comparing: \(URL(fileURLWithPath: file1).lastPathComponent)")
            print("     with: \(URL(fileURLWithPath: file2).lastPathComponent)")
            print()
        }

        // Parse ignore tags
        let tagsToIgnore = try parseIgnoreTags(ignoreTag)

        // Perform comparison via the shared DICOMKit engine
        let comparer = DICOMComparer(
            file1: dicomFile1,
            file2: dicomFile2,
            tagsToIgnore: tagsToIgnore,
            ignorePrivate: ignorePrivate,
            comparePixels: comparePixels && !quick,
            pixelTolerance: tolerance,
            showIdentical: showIdentical
        )

        let result: DICOMKit.ComparisonResult
        do {
            result = try comparer.compare()
        } catch {
            throw Self.trouble("Comparison failed: \(error)")
        }

        // Output results via the shared DICOMKit renderer
        let report = ComparisonReport(
            result: result,
            file1Name: URL(fileURLWithPath: file1).lastPathComponent,
            file2Name: URL(fileURLWithPath: file2).lastPathComponent,
            showIdentical: showIdentical
        )
        let output = try report.render(format: format)
        print(output)

        // Exit with appropriate code
        if result.hasDifferences {
            throw ExitCode(Self.exitDifferent)
        }
    }

    private func parseIgnoreTags(_ tags: [String]) throws -> Set<Tag> {
        var result = Set<Tag>()

        for tagStr in tags {
            if let tag = Self.parseTag(tagStr) {
                result.insert(tag)
            } else {
                throw ValidationError("Invalid tag format: \(tagStr). Use (gggg,eeee), gggg,eeee, ggggeeee or a PS3.6 keyword like 'SOPInstanceUID'")
            }
        }

        return result
    }

    /// Parses an `--ignore-tag` value: the PS3.6 Table 6-1 Tag notation `(gggg,eeee)` that the
    /// report itself prints, `gggg,eeee`, the 8-digit `ggggeeee` form, or a PS3.6
    /// Table 6-1 keyword.
    static func parseTag(_ input: String) -> Tag? {
        var str = input.trimmingCharacters(in: .whitespaces)
        if str.hasPrefix("("), str.hasSuffix(")") {
            str = String(str.dropFirst().dropLast())
        }
        let isHex4: (String) -> Bool = { (1...4).contains($0.count) && $0.allSatisfy(\.isHexDigit) }

        // gggg,eeee
        let components = str.components(separatedBy: ",")
        if components.count == 2, isHex4(components[0]), isHex4(components[1]),
           let group = UInt16(components[0], radix: 16),
           let element = UInt16(components[1], radix: 16) {
            return Tag(group: group, element: element)
        }

        // ggggeeee
        if str.count == 8, str.allSatisfy(\.isHexDigit), let value = UInt32(str, radix: 16) {
            return Tag(group: UInt16(value >> 16), element: UInt16(value & 0xFFFF))
        }

        // PS3.6 keyword
        return DataElementDictionary.lookup(keyword: str)?.tag
    }
}

DICOMDiff.main()
