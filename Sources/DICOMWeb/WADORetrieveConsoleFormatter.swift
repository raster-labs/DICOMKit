import Foundation
import DICOMCore

// NEMA-verified: 2026a, checked 2026-09-28 — console text only; the mode names are the PS3.18 2026a Table 10.1-1 resource names; the WADO-URI protocol label corrected to Chapter 9
/// Console renderings shared by the `dicom-wado retrieve` CLI (WADO-RS / WADO-URI)
/// and DICOMStudio's in-app retrieve, so both produce identical text for the same
/// retrieval. This is the retrieve-side peer of `QIDOResultFormatter` (query) and
/// `UPSResultFormatter` (ups): a SINGLE formatter both sides call, so their output
/// pipelines cannot drift.
///
/// It owns three things:
///   1. The verbose preamble blocks (WADO-RS and WADO-URI).
///   2. Every per-mode status line (metadata / rendered / thumbnail / frames /
///      instances + the WADO-URI result line).
///   3. The metadata body rendering — JSON (pretty, sorted keys) and PS3.19 Native
///      DICOM Model XML — so a metadata retrieval renders identically on both sides.
///
/// Line/block methods return text WITHOUT a trailing newline; callers add line
/// termination (the CLI via `fprintln`, the app via `appendConsoleOutput(_ + "\n")`).
/// The CLI-parity comparator parses the byte count off the WADO-URI "Retrieved …"
/// line and counts metadata objects off the JSON array / `<NativeDicomModel xmlns>`
/// XML elements, so those formats are a contract (see `CLIParityWADOComparator`).
public struct WADORetrieveConsoleFormatter {
    public init() {}

    // MARK: - Verbose preamble

    /// WADO-RS verbose preamble (emitted only under `--verbose`), e.g.
    ///   DICOMweb Server: <baseURL>
    ///   Study UID: <studyUID>
    ///   Series UID: <seriesUID>     (when present)
    ///   Instance UID: <instanceUID> (when present)
    public func verbosePreambleRS(baseURL: String, studyUID: String,
                                  seriesUID: String?, instanceUID: String?) -> String {
        var lines = ["DICOMweb Server: \(baseURL)", "Study UID: \(studyUID)"]
        if let s = seriesUID, !s.isEmpty { lines.append("Series UID: \(s)") }
        if let i = instanceUID, !i.isEmpty { lines.append("Instance UID: \(i)") }
        return lines.joined(separator: "\n")
    }

    /// WADO-URI verbose preamble (emitted only under `--verbose`).
    public func verbosePreambleURI(baseURL: String, studyUID: String, seriesUID: String,
                                   instanceUID: String, contentType: String, frame: Int?) -> String {
        var lines = [
            "WADO-URI Server: \(baseURL)",
            "Protocol:     WADO-URI (PS3.18 §9)",
            "Study UID:    \(studyUID)",
            "Series UID:   \(seriesUID)",
            "Instance UID: \(instanceUID)",
            "Content-Type: \(contentType)"
        ]
        if let f = frame { lines.append("Frame:        \(f)") }
        return lines.joined(separator: "\n")
    }

    // MARK: - WADO-URI result

    /// Non-verbose WADO-URI result line: `Retrieved <bytes> bytes → <filename>`.
    public func uriRetrieved(bytes: Int, filename: String) -> String {
        "Retrieved \(bytes) bytes → \(filename)"
    }

    /// Verbose WADO-URI result line: `Retrieved <bytes> bytes via WADO-URI`.
    public func uriRetrievedVerbose(bytes: Int) -> String {
        "Retrieved \(bytes) bytes via WADO-URI"
    }

    /// Verbose "saved to" line (WADO-URI / rendered, etc.): `Saved to: <path>`.
    public func savedTo(path: String) -> String {
        "Saved to: \(path)"
    }

    // MARK: - Metadata

    public func metadataRetrieving() -> String { "Retrieving metadata..." }

    public func metadataCount(_ count: Int) -> String {
        "\nRetrieved metadata for \(count) instance(s)"
    }

    /// Renders DICOMweb metadata as pretty, sorted-key JSON — the body the CLI prints
    /// for `--metadata --format json`. The CLI-parity comparator counts the objects in
    /// this array.
    public func metadataJSON(_ metadata: [[String: Any]]) throws -> String {
        let jsonData = try JSONSerialization.data(withJSONObject: metadata,
                                                  options: [.prettyPrinted, .sortedKeys])
        return String(data: jsonData, encoding: .utf8) ?? ""
    }

    /// Renders DICOMweb metadata as PS3.19 Native DICOM Model XML using the shared
    /// `DICOMXMLEncoder`. A single instance produces one `<NativeDicomModel>` document;
    /// multiple instances are wrapped in a `<NativeDicomModelList>` so the combined
    /// output stays one well-formed document with a single XML prolog. Zero instances
    /// yields an empty `<NativeDicomModelList>` (zero `<NativeDicomModel>` elements),
    /// so the comparator's object count stays 0.
    public func metadataXML(_ instances: [[DataElement]]) throws -> String {
        let encoder = DICOMXMLEncoder(
            configuration: DICOMXMLEncoder.Configuration(prettyPrinted: true)
        )
        if instances.count == 1 {
            return try encoder.encodeToString(instances[0])
        }
        let xmlProlog = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        var xml = xmlProlog + "<NativeDicomModelList>\n"
        for elements in instances {
            let single = try encoder.encodeToString(elements)
            xml += single.replacingOccurrences(of: xmlProlog, with: "")
        }
        xml += "</NativeDicomModelList>\n"
        return xml
    }

    // MARK: - Rendered

    public func renderedRetrieving() -> String { "Retrieving rendered image..." }

    public func renderedSaved(bytes: Int) -> String { "Saved rendered image (\(bytes) bytes)" }

    // MARK: - Thumbnail

    public func thumbnailRetrieving() -> String { "Retrieving thumbnail..." }

    public func thumbnailSaved(bytes: Int) -> String { "Saved thumbnail (\(bytes) bytes)" }

    // MARK: - Frames

    public func framesRetrieving(_ numbers: [Int]) -> String {
        "Retrieving frames: \(numbers.map(String.init).joined(separator: ", "))..."
    }

    public func frameSaved(number: Int, bytes: Int) -> String {
        "Saved frame \(number) (\(bytes) bytes)"
    }

    public func framesCount(_ count: Int) -> String {
        "\nRetrieved \(count) frame(s)"
    }

    // MARK: - Instances

    public func instancesRetrieving() -> String { "Retrieving DICOM instances..." }

    /// Single-instance verbose saved line: `Saved instance (<bytes> bytes)`.
    public func instanceSaved(bytes: Int) -> String { "Saved instance (\(bytes) bytes)" }

    /// Series/study verbose per-instance saved line: `Saved instance <index> (<bytes> bytes)`.
    public func instanceSaved(index: Int, bytes: Int) -> String {
        "Saved instance \(index) (\(bytes) bytes)"
    }

    public func instancesCount(_ count: Int) -> String {
        "\nRetrieved \(count) instance(s)"
    }

    // MARK: - Frame number parsing (shared so both sides accept the same input)

    /// Parses a comma-separated 1-based frame list (e.g. "1,2,3"), trimming whitespace
    /// and rejecting non-positive / non-numeric entries — the single source of truth the
    /// CLI and app both use so `--frames` is interpreted identically.
    public func parseFrameNumbers(_ framesString: String) throws -> [Int] {
        try framesString.split(separator: ",").map { component in
            guard let number = Int(component.trimmingCharacters(in: .whitespaces)) else {
                throw WADOFrameParseError.notANumber(String(component))
            }
            guard number > 0 else {
                throw WADOFrameParseError.notPositive(number)
            }
            return number
        }
    }
}

/// Errors thrown by `WADORetrieveConsoleFormatter.parseFrameNumbers`.
public enum WADOFrameParseError: Error, CustomStringConvertible {
    case notANumber(String)
    case notPositive(Int)

    public var description: String {
        switch self {
        case .notANumber(let s): return "Invalid frame number: \(s)"
        case .notPositive(let n): return "Frame numbers must be positive: \(n)"
        }
    }
}
