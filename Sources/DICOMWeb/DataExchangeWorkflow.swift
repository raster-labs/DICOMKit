import Foundation
import DICOMCore
import DICOMKit
import DICOMDictionary

// NEMA-verified: 2026a, checked 2026-10-01 — metadataOnly leaves out (or, with a bulk data URL, references by BulkDataURI) every OB/OD/OF/OL/OV/OW/UN value at any depth, the Bulk Data of PS3.18 2026a 10.4.1.1.2 / PS3.19 Table A.1.5-2 (D111); decode resolves file: BulkData references and reports each unresolved one (PS3.18 F.2.6, D113); decode keeps group 0002 out of the data set (PS3.10 2026a 7.1, D-WEB-FILEMETA-1); checked 2026-09-28 — the default transfer syntax 1.2.840.10008.1.2.1 is registered in PS3.6 2026a Table A-1 and is the PS3.18 8.7.3.4 default; tag parsing only, no table data
/// Shared orchestration for `dicom-json` / `dicom-xml` — the single pipeline
/// (read → filter → metadata-only → encode → console lines, and the reverse
/// decode path) used by BOTH the CLIs and DICOMStudio's Workshop executors.
///
/// Before this existed, only the raw `DICOMJSONEncoder`/`DICOMXMLEncoder`
/// primitives were shared: each CLI hand-rolled the pipeline in `main.swift`
/// and the app re-hand-rolled it, so behavior (default output path, write-vs-
/// console) and verbose text had drifted. The CLI's behavior is canonical:
/// output ALWAYS goes to a file (default `<input>.json`/`.xml`/`.dcm`), never
/// to the console.
public enum DataExchangeWorkflow {

    // MARK: - Common options

    public struct Options: Sendable {
        public var reverse: Bool
        public var pretty: Bool
        public var includeEmpty: Bool
        public var inlineThreshold: Int
        public var bulkDataURL: String?
        public var metadataOnly: Bool
        public var filterTags: [String]
        public var verbose: Bool
        /// JSON only: sort keys alphabetically (CLI default; `--no-sort-keys` clears it).
        public var sortKeys: Bool
        /// XML only: include keyword attributes (CLI default; `--no-keywords` clears it).
        public var includeKeywords: Bool

        public init(
            reverse: Bool = false, pretty: Bool = false, includeEmpty: Bool = false,
            inlineThreshold: Int = 1024, bulkDataURL: String? = nil,
            metadataOnly: Bool = false, filterTags: [String] = [], verbose: Bool = false,
            sortKeys: Bool = true, includeKeywords: Bool = true
        ) {
            self.reverse = reverse; self.pretty = pretty; self.includeEmpty = includeEmpty
            self.inlineThreshold = inlineThreshold; self.bulkDataURL = bulkDataURL
            self.metadataOnly = metadataOnly; self.filterTags = filterTags; self.verbose = verbose
            self.sortKeys = sortKeys; self.includeKeywords = includeKeywords
        }
    }

    public enum Format: String, Sendable {
        case json
        case xml

        /// "JSON" / "XML" as spelled in the CLI's console lines.
        var label: String { rawValue.uppercased() }
        /// Default output extension for the forward (DICOM → text) direction.
        var textExtension: String { rawValue }
    }

    public enum WorkflowError: Error, LocalizedError {
        case invalidTag(String)
        case invalidTagFormat(String)

        public var errorDescription: String? {
            switch self {
            case .invalidTag(let s): return "Invalid tag: \(s)"
            case .invalidTagFormat(let s): return "Invalid tag format: \(s). Expected format: GGGG,EEEE"
            }
        }
    }

    // MARK: - Path + console (shared text, CLI-canonical)

    /// Default output path when `--output` is omitted: the input path with its
    /// extension swapped to `.json`/`.xml` (forward) or `.dcm` (reverse).
    public static func defaultOutputPath(input: String, reverse: Bool, format: Format) -> String {
        let inputURL = URL(fileURLWithPath: input)
        let ext = reverse ? "dcm" : format.textExtension
        return inputURL.deletingPathExtension().appendingPathExtension(ext).path
    }

    /// Verbose run header ("Input:/Output:/Mode:" + blank line); empty when not verbose.
    public static func headerLines(
        input: String, output: String, reverse: Bool, format: Format, verbose: Bool
    ) -> [String] {
        guard verbose else { return [] }
        let mode = reverse ? "\(format.label) → DICOM" : "DICOM → \(format.label)"
        return ["Input:  \(input)", "Output: \(output)", "Mode:   \(mode)", ""]
    }

    /// Verbose completion block (blank + "✓ Conversion complete" + size); empty when not verbose.
    public static func completionLines(outputSize: Int64, verbose: Bool) -> [String] {
        guard verbose else { return [] }
        return ["", "✓ Conversion complete", "  Output size: \(formatFileSize(outputSize))"]
    }

    /// The CLIs' shared file-size wording (KB/MB with two decimals, bytes below 1 KB).
    public static func formatFileSize(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 { return String(format: "%.2f MB", mb) }
        if kb >= 1 { return String(format: "%.2f KB", kb) }
        return "\(bytes) bytes"
    }

    // MARK: - Filter-tag resolution

    /// Resolves `--filter-tag` specifiers (dictionary keyword or `GGGG,EEEE` hex)
    /// to tags; throws the CLI's exact error on an unresolvable entry.
    public static func resolveFilterTags(_ specs: [String]) throws -> Set<Tag> {
        var tagSet = Set<Tag>()
        for tagString in specs {
            if let entry = DataElementDictionary.lookup(keyword: tagString) {
                tagSet.insert(entry.tag)
            } else if let tag = parseTagString(tagString) {
                tagSet.insert(tag)
            } else {
                throw WorkflowError.invalidTag(tagString)
            }
        }
        return tagSet
    }

    private static func parseTagString(_ string: String) -> Tag? {
        let components = string.split(separator: ",")
        guard components.count == 2,
              let group = UInt16(components[0], radix: 16),
              let element = UInt16(components[1], radix: 16) else { return nil }
        return Tag(group: group, element: element)
    }

    // MARK: - Forward: DICOM → JSON/XML

    /// Converts DICOM bytes to JSON or XML, returning the encoded bytes plus the
    /// CLI's verbose progress lines (empty when not verbose). No file I/O — the
    /// caller reads/writes (the CLI directly; the app via its sandbox-aware
    /// OutputAccess path) and passes its measured read duration so the verbose
    /// text keeps the CLI's exact line shapes.
    public static func encode(
        dicomData: Data, format: Format, options: Options, readSeconds: TimeInterval = 0
    ) throws -> (data: Data, console: [String]) {
        var console: [String] = []
        func vlog(_ line: String) { if options.verbose { console.append(line) } }

        vlog("Read DICOM file: \(formatFileSize(Int64(dicomData.count))) in \(String(format: "%.2f", readSeconds))s")
        let parseStart = Date()
        let dicomFile = try DICOMFile.read(from: dicomData)
        vlog("Parsed DICOM: \(dicomFile.dataSet.allElements.count) elements in \(String(format: "%.2f", Date().timeIntervalSince(parseStart)))s")

        var elements = dicomFile.dataSet.allElements
        if !options.filterTags.isEmpty {
            let tagSet = try resolveFilterTags(options.filterTags)
            elements = elements.filter { tagSet.contains($0.tag) }
            vlog("Filtered to \(elements.count) elements")
        }
        let bulkDataBaseURL = options.bulkDataURL.flatMap { URL(string: $0) }
        var threshold = options.inlineThreshold > 0 ? options.inlineThreshold : nil

        // PS3.18 10.4.1.1.2: Metadata is the Data Set without Bulk Data. Every OB, OD, OF,
        // OL, OV, OW and UN value at any depth (Pixel Data, Float / Double Float Pixel Data,
        // Encapsulated Document, Waveform and Overlay Data, LUTs, ...) is replaced by a
        // BulkDataURI when a bulk data URL is given (10.4.3.3.2), else left out (D111).
        if options.metadataOnly {
            if bulkDataBaseURL != nil {
                threshold = nil
            } else {
                let before = countElements(elements)
                elements = removingBulkData(elements)
                vlog("Metadata only: left out \(before - countElements(elements)) Bulk Data element(s)")
            }
        }

        let encodeStart = Date()
        let encoded: Data
        switch format {
        case .json:
            let encoder = DICOMJSONEncoder(configuration: .init(
                includeEmptyValues: options.includeEmpty,
                inlineBinaryThreshold: threshold,
                bulkDataBaseURL: bulkDataBaseURL,
                prettyPrinted: options.pretty,
                sortedKeys: options.sortKeys
            ))
            encoded = try encoder.encode(elements)
        case .xml:
            let encoder = DICOMXMLEncoder(configuration: .init(
                includeEmptyValues: options.includeEmpty,
                inlineBinaryThreshold: threshold,
                bulkDataBaseURL: bulkDataBaseURL,
                prettyPrinted: options.pretty,
                includeKeywords: options.includeKeywords
            ))
            encoded = try encoder.encode(elements)
        }
        vlog("Encoded to \(format.label): \(formatFileSize(Int64(encoded.count))) in \(String(format: "%.2f", Date().timeIntervalSince(encodeStart)))s")

        return (encoded, console)
    }

    // MARK: - Reverse: JSON/XML → DICOM

    /// Decodes JSON or XML bytes back to a Part-10 DICOM file, returning the
    /// DICOM bytes plus the CLI's verbose progress lines.
    public static func decode(
        textData: Data, format: Format, options: Options, readSeconds: TimeInterval = 0
    ) throws -> (data: Data, console: [String]) {
        var console: [String] = []
        func vlog(_ line: String) { if options.verbose { console.append(line) } }

        vlog("Read \(format.label) file: \(formatFileSize(Int64(textData.count))) in \(String(format: "%.2f", readSeconds))s")

        let decodeStart = Date()
        let elements: [DataElement]
        // PS3.18 F.2.6 / PS3.19 Table A.1.5-2: a BulkDataURI / BulkData names a Value Field
        // that is retrievable, not empty. A file: URI (or absolute path) is read; any other
        // reference cannot be fetched here and is reported below (D113).
        let bulkData = BulkDataLog()
        let resolver: @Sendable (String, Tag) -> Data? = { reference, tag in
            if let data = Self.readLocalBulkData(reference) { return data }
            bulkData.unresolved(reference, tag)
            return nil
        }
        switch format {
        case .json:
            let decoder = DICOMJSONDecoder(configuration: .init(
                allowMissingVR: true, fetchBulkData: false, bulkDataHandler: nil, bulkDataResolver: resolver))
            elements = try decoder.decode(textData)
        case .xml:
            let decoder = DICOMXMLDecoder(configuration: .init(
                allowMissingVR: true, fetchBulkData: false, bulkDataHandler: nil, bulkDataResolver: resolver))
            elements = try decoder.decode(textData)
        }
        vlog("Decoded \(format.label): \(elements.count) elements in \(String(format: "%.2f", Date().timeIntervalSince(decodeStart)))s")
        for (reference, tag) in bulkData.entries {
            console.append("Warning: \(tag) \(format == .json ? "BulkDataURI" : "BulkData") \(reference) could not be "
                + "retrieved; the attribute is written with an empty Value Field (PS3.18 F.2.6, PS3.19 Table A.1.5-2)")
        }

        let createStart = Date()
        // PS3.10 7.1: group 0002 is File Meta Information only, never part of the Data Set.
        // A JSON / XML input that carries it (e.g. Transfer Syntax UID) supplies the File
        // Meta's Transfer Syntax and is otherwise left out of the data set (D-WEB-FILEMETA-1).
        let fileMetaElements = elements.filter { $0.tag.group == 0x0002 }
        let dataSet = DataSet(elements: elements.filter { $0.tag.group != 0x0002 })
        let transferSyntaxUID = fileMetaElements.first { $0.tag == Tag.transferSyntaxUID }?.stringValue?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \0")) ?? "1.2.840.10008.1.2.1"
        if !fileMetaElements.isEmpty {
            vlog("Group 0002: \(fileMetaElements.count) File Meta element(s) kept out of the data set (PS3.10 7.1)")
        }
        let dicomFile = DICOMFile.create(dataSet: dataSet, transferSyntaxUID: transferSyntaxUID.isEmpty ? "1.2.840.10008.1.2.1" : transferSyntaxUID)
        vlog("Created DICOM file in \(String(format: "%.2f", Date().timeIntervalSince(createStart)))s")

        let dicomData = try dicomFile.write()

        return (dicomData, console)
    }

    // MARK: - Bulk Data helpers

    /// The number of elements at every depth.
    private static func countElements(_ elements: [DataElement]) -> Int {
        elements.reduce(0) { $0 + 1 + ($1.sequenceItems ?? []).reduce(0) { $0 + countElements($1.allElements) } }
    }

    /// Bulk Data VRs: the "Base64 encoded octet-stream" VRs of PS3.18 Table F.2.3-1.
    private static func isBulkDataVR(_ vr: VR) -> Bool {
        switch vr {
        case .OB, .OD, .OF, .OL, .OV, .OW, .UN: return true
        default: return false
        }
    }

    /// The elements without any Bulk Data element, at every depth (sequence items included).
    static func removingBulkData(_ elements: [DataElement]) -> [DataElement] {
        elements.compactMap { element in
            if element.tag == Tag.pixelData || isBulkDataVR(element.vr) { return nil }
            guard element.vr == .SQ, let items = element.sequenceItems else { return element }
            let stripped = items.map { SequenceItem(elements: removingBulkData($0.allElements)) }
            return DataElement(tag: element.tag, vr: .SQ, length: element.length, valueData: element.valueData,
                               sequenceItems: stripped, byteOrder: element.byteOrder)
        }
    }

    /// Reads a BulkData reference that names a local file (`file:` URL or absolute path).
    static func readLocalBulkData(_ reference: String) -> Data? {
        let url: URL
        if let parsed = URL(string: reference), parsed.isFileURL {
            url = parsed
        } else if reference.hasPrefix("/") {
            url = URL(fileURLWithPath: reference)
        } else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// Collects the BulkData references the decoders could not resolve, in input order.
    private final class BulkDataLog: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(String, Tag)] = []
        func unresolved(_ reference: String, _ tag: Tag) {
            lock.lock(); items.append((reference, tag)); lock.unlock()
        }
        var entries: [(String, Tag)] {
            lock.lock(); defer { lock.unlock() }
            return items
        }
    }

    // MARK: - Write-stage verbose lines (emitted by the caller after persisting)

    /// Forward direction: "Wrote output file in X.XXs" (empty when not verbose).
    public static func forwardWriteLine(seconds: TimeInterval, verbose: Bool) -> [String] {
        verbose ? ["Wrote output file in \(String(format: "%.2f", seconds))s"] : []
    }

    /// Reverse direction: "Wrote DICOM file: SIZE in X.XXs" (empty when not verbose).
    public static func reverseWriteLine(size: Int64, seconds: TimeInterval, verbose: Bool) -> [String] {
        verbose ? ["Wrote DICOM file: \(formatFileSize(size)) in \(String(format: "%.2f", seconds))s"] : []
    }
}
