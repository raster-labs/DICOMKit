import Foundation
import DICOMCore
import DICOMDictionary
// NEMA-verified: 2026a, checked 2026-10-01 — the 18 table column labels are the PS3.6 2026a Table 6-1 Attribute Names of the attributes shown (19 rows dumped by Scripts/nema_docbook.py; Columns × Rows names two), P-QUERY-COLUMNS; --csv-keywords headers are Table 6-1 Keywords via DICOMDictionary; dicom-json builds the PS3.18 2026a F.2 element list (UTF-8 / ISO_IR 192 per F.2; VR as encoded in an Explicit VR response, else from Table 6-1; SQ decoded into item objects per F.2.2 / F.2.5, UN InlineBinary only when undecodable, D210) for DICOMWeb's encoder (P-QUERY-JSON)

/// Output renderings shared by the dicom-query CLI and DICOMStudio's in-app query,
/// so both produce identical text for the same C-FIND results.
public enum QueryOutputFormat: String, Sendable, CaseIterable {
    case table
    /// Tool summary: `{"(GGGG,EEEE)": "value"}` per result (not PS3.18).
    case json
    case csv
    case compact
    /// The PS3.18 F.2 DICOM JSON Model (`"00100010": {"vr": "PN", "Value": [...]}`).
    /// Rendering needs a DICOM JSON encoder (DICOMWeb's `DICOMJSONEncoder`), passed
    /// to ``DICOMQueryResultFormatter/init(format:level:csvHeader:dicomJSONEncoder:)``.
    case dicomJSON = "dicom-json"
}

/// What the CSV header row names each column by.
public enum QueryCSVHeader: String, Sendable, CaseIterable {
    /// `(GGGG,EEEE)` — the header written since the first release (default).
    case tag
    /// The PS3.6 Table 6-1 Keyword (e.g. `PatientName`); a tag without a
    /// keyword (private, unknown) keeps its `(GGGG,EEEE)` form.
    case keyword
}

/// Renders C-FIND results to text. This is the SINGLE formatter used by both the
/// `dicom-query` CLI and the DICOMStudio CLI Workshop, so their output pipelines
/// cannot drift.
public struct DICOMQueryResultFormatter {
    public let format: QueryOutputFormat
    public let level: QueryLevel
    /// CSV header style (``QueryCSVHeader/tag`` unless asked otherwise).
    public let csvHeader: QueryCSVHeader
    /// Encodes one element list per result as a PS3.18 F.2 JSON array; required
    /// for ``QueryOutputFormat/dicomJSON``. DICOMNetwork does not depend on
    /// DICOMWeb, so callers pass e.g.
    /// `{ try DICOMJSONEncoder(configuration: .init(prettyPrinted: true)).encodeMultiple($0) }`.
    public let dicomJSONEncoder: (([[DataElement]]) throws -> Data)?

    public init(format: QueryOutputFormat, level: QueryLevel) {
        self.init(format: format, level: level, csvHeader: .tag, dicomJSONEncoder: nil)
    }

    /// With a CSV header style and a DICOM JSON encoder (added 2026-10-01).
    public init(format: QueryOutputFormat, level: QueryLevel,
                csvHeader: QueryCSVHeader,
                dicomJSONEncoder: (([[DataElement]]) throws -> Data)? = nil) {
        self.format = format
        self.level = level
        self.csvHeader = csvHeader
        self.dicomJSONEncoder = dicomJSONEncoder
    }

    public func format(results: [GenericQueryResult]) -> String {
        switch format {
        case .table:     return formatTable(results)
        case .json:      return formatJSON(results)
        case .csv:       return formatCSV(results)
        case .compact:   return formatCompact(results)
        case .dicomJSON: return formatDICOMJSON(results)
        }
    }

    // MARK: - Table

    private func formatTable(_ results: [GenericQueryResult]) -> String {
        guard !results.isEmpty else { return "No results found.\n" }
        switch level {
        case .patient: return formatPatientTable(results)
        case .study:   return formatStudyTable(results)
        case .series:  return formatSeriesTable(results)
        case .image:   return formatInstanceTable(results)
        }
    }

    /// Column labels are the PS3.6 2026a Table 6-1 Attribute Names of the
    /// attributes shown (P-QUERY-COLUMNS); a column is at least as wide as its
    /// label, and the rules span the whole row.
    private func renderTable(_ columns: [(label: String, width: Int)], rows: [[String]], total: String) -> String {
        let widths = columns.map { max($0.width, $0.label.count) }
        let ruleWidth = widths.reduce(0, +) + widths.count - 1
        let rule = String(repeating: "─", count: ruleWidth) + "\n"
        func line(_ cells: [String]) -> String {
            zip(cells, widths).map { padRight($0.0, $0.1) }.joined(separator: " ") + "\n"
        }
        var output = rule
        output += line(columns.map(\.label))
        output += rule
        for row in rows { output += line(row) }
        output += rule
        output += total + "\n"
        return output
    }

    private func formatPatientTable(_ results: [GenericQueryResult]) -> String {
        let rows = results.map { result -> [String] in
            let patient = result.toPatientResult()
            return [patient.patientName ?? "", patient.patientID ?? "", formatDate(patient.patientBirthDate),
                    patient.patientSex ?? "", patient.numberOfPatientRelatedStudies.map(String.init) ?? ""]
        }
        return renderTable([("Patient's Name", 30), ("Patient ID", 15), ("Patient's Birth Date", 12),
                            ("Patient's Sex", 5), ("Number of Patient Related Studies", 8)],
                           rows: rows, total: "Total: \(results.count) patient(s)")
    }

    private func formatStudyTable(_ results: [GenericQueryResult]) -> String {
        let rows = results.map { result -> [String] in
            let study = result.toStudyResult()
            return [study.patientName ?? "", study.patientID ?? "", formatDate(study.studyDate),
                    study.studyDescription ?? "", study.modalitiesInStudy ?? "",
                    study.numberOfStudyRelatedSeries.map(String.init) ?? ""]
        }
        return renderTable([("Patient's Name", 25), ("Patient ID", 12), ("Study Date", 12),
                            ("Study Description", 30), ("Modalities in Study", 12),
                            ("Number of Study Related Series", 8)],
                           rows: rows, total: "Total: \(results.count) study(ies)")
    }

    private func formatSeriesTable(_ results: [GenericQueryResult]) -> String {
        let rows = results.map { result -> [String] in
            let series = result.toSeriesResult()
            return [series.seriesNumber.map(String.init) ?? "", series.modality ?? "",
                    series.seriesDescription ?? "", formatDate(series.seriesDate),
                    series.numberOfSeriesRelatedInstances.map(String.init) ?? ""]
        }
        return renderTable([("Series Number", 15), ("Modality", 10), ("Series Description", 40),
                            ("Series Date", 12), ("Number of Series Related Instances", 10)],
                           rows: rows, total: "Total: \(results.count) series")
    }

    private func formatInstanceTable(_ results: [GenericQueryResult]) -> String {
        let rows = results.map { result -> [String] in
            let instance = result.toInstanceResult()
            let dimensions: String
            if let rows = instance.rows, let cols = instance.columns {
                dimensions = "\(cols)×\(rows)"
            } else {
                dimensions = ""
            }
            return [instance.instanceNumber.map(String.init) ?? "", shortenUID(instance.sopClassUID),
                    dimensions, instance.numberOfFrames.map(String.init) ?? "1"]
        }
        // "Columns × Rows": the value is printed columns first (width × height).
        return renderTable([("Instance Number", 17), ("SOP Class UID", 30), ("Columns × Rows", 15),
                            ("Number of Frames", 8)],
                           rows: rows, total: "Total: \(results.count) instance(s)")
    }

    // MARK: - JSON

    private func formatJSON(_ results: [GenericQueryResult]) -> String {
        var jsonArray: [[String: String]] = []
        for result in results {
            var jsonObject: [String: String] = [:]
            // Decode with the response's declared (0008,0005), like QueryResult.string(for:).
            let characterSet = result.specificCharacterSet
            for (tag, data) in result.attributes {
                let key = tag.description
                let trimmed = QueryResultDecoding.decodeString(data, specificCharacterSet: characterSet)
                if !trimmed.isEmpty { jsonObject[key] = trimmed }
            }
            jsonArray.append(jsonObject)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let jsonData = try? encoder.encode(jsonArray),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString + "\n"
        }
        return "[]\n"
    }

    // MARK: - CSV

    private func formatCSV(_ results: [GenericQueryResult]) -> String {
        guard !results.isEmpty else { return "" }
        var output = ""
        let columns = results[0].attributes.keys.sorted { $0.description < $1.description }
        output += columns.map { escapeCSV(csvHeaderName($0)) }.joined(separator: ",") + "\n"
        for result in results {
            let characterSet = result.specificCharacterSet
            let row = columns.map { tag -> String in
                if let data = result.attributes[tag] {
                    return escapeCSV(QueryResultDecoding.decodeString(data, specificCharacterSet: characterSet))
                }
                return ""
            }
            output += row.joined(separator: ",") + "\n"
        }
        return output
    }

    /// `(GGGG,EEEE)`, or the PS3.6 Table 6-1 Keyword with `.keyword`.
    private func csvHeaderName(_ tag: Tag) -> String {
        guard csvHeader == .keyword,
              let keyword = DataElementDictionary.lookup(tag: tag)?.keyword, !keyword.isEmpty else {
            return tag.description
        }
        return keyword
    }

    // MARK: - DICOM JSON (PS3.18 F.2)

    private func formatDICOMJSON(_ results: [GenericQueryResult]) -> String {
        guard let encoder = dicomJSONEncoder else {
            return "error: --format dicom-json needs a DICOM JSON encoder (DICOMWeb.DICOMJSONEncoder)\n"
        }
        do {
            let data = try encoder(results.map { $0.dicomJSONElements() })
            return (String(data: data, encoding: .utf8) ?? "[]") + "\n"
        } catch {
            return "error: DICOM JSON encoding failed: \(error)\n"
        }
    }

    // MARK: - Compact

    private func formatCompact(_ results: [GenericQueryResult]) -> String {
        var output = ""
        for result in results {
            var fields: [String] = []
            switch level {
            case .patient:
                let patient = result.toPatientResult()
                fields.append(patient.patientName ?? "")
                fields.append(patient.patientID ?? "")
                fields.append(patient.patientBirthDate ?? "")
            case .study:
                let study = result.toStudyResult()
                fields.append(study.patientName ?? "")
                fields.append(study.patientID ?? "")
                fields.append(study.studyDate ?? "")
                fields.append(study.studyDescription ?? "")
                fields.append(study.studyInstanceUID ?? "")
            case .series:
                let series = result.toSeriesResult()
                fields.append(series.seriesNumber.map(String.init) ?? "")
                fields.append(series.modality ?? "")
                fields.append(series.seriesDescription ?? "")
                fields.append(series.seriesInstanceUID ?? "")
            case .image:
                let instance = result.toInstanceResult()
                fields.append(instance.instanceNumber.map(String.init) ?? "")
                fields.append(instance.sopInstanceUID ?? "")
            }
            output += fields.joined(separator: " | ") + "\n"
        }
        return output
    }

    // MARK: - Utilities

    private func padRight(_ string: String, _ width: Int) -> String {
        let truncated = String(string.prefix(width))
        return truncated.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    private func formatDate(_ dateString: String?) -> String {
        guard let dateString = dateString, dateString.count == 8 else { return dateString ?? "" }
        let year = dateString.prefix(4)
        let month = dateString.dropFirst(4).prefix(2)
        let day = dateString.dropFirst(6)
        return "\(year)-\(month)-\(day)"
    }

    private func shortenUID(_ uid: String?) -> String {
        guard let uid = uid else { return "" }
        let components = uid.split(separator: ".")
        if components.count > 5 {
            return "..." + components.suffix(3).joined(separator: ".")
        }
        return uid
    }

    private func escapeCSV(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"" + string.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return string
    }
}

// MARK: - DICOM JSON element list

public extension GenericQueryResult {
    /// The response attributes as data elements for a PS3.18 F.2 DICOM JSON
    /// encoder (DICOMWeb's `DICOMJSONEncoder`).
    ///
    /// - VR: the VR the response was encoded with (``vrs``, Explicit VR); for an
    ///   Implicit VR response, the first VR of the attribute's PS3.6 Table 6-1 row;
    ///   attributes the dictionary does not know (private, unknown) are UN.
    /// - Text values are decoded with the response's Specific Character Set
    ///   (0008,0005) and re-encoded as UTF-8, and (0008,0005) is written as
    ///   `ISO_IR 192`: "The default character repertoire shall be UTF-8 /
    ///   ISO_IR 192" (PS3.18 F.2).
    /// - A sequence (SQ) is decoded into its items when the response's transfer
    ///   syntax is known (``transferSyntaxUID``, Explicit or Implicit VR Little
    ///   Endian), so the encoder writes "Value" as an array of DICOM JSON objects
    ///   (PS3.18 F.2.2 / F.2.5) with the items' own VRs; only when it cannot be
    ///   decoded is it kept as raw bytes under VR UN (InlineBinary, F.2.7). Before
    ///   2026-10-01 every sequence was written as UN (D210).
    /// - Group Length (gggg,0000) is left to the encoder, which omits it.
    func dicomJSONElements() -> [DataElement] {
        let characterSet = specificCharacterSet
        let reader = transferSyntaxUID.flatMap(Self.sequenceReader(transferSyntaxUID:))
        return attributes.keys.sorted().map { tag -> DataElement in
            let raw = attributes[tag] ?? Data()
            let vr = vrs[tag] ?? DataElementDictionary.lookup(tag: tag)?.vr.first ?? .UN
            if vr == .SQ {
                if let reader, let items = try? reader.parseSequenceValue(raw, tag: tag) {
                    return DataElement(tag: tag, vr: .SQ, length: UInt32(raw.count), valueData: Data(),
                                       sequenceItems: items.map { Self.jsonItem($0, characterSet: characterSet) })
                }
                return DataElement(tag: tag, vr: .UN, length: UInt32(raw.count), valueData: raw)
            }
            return Self.jsonElement(tag: tag, vr: vr, raw: raw, characterSet: characterSet)
        }
    }

    /// The Little Endian reader for a response transfer syntax, or nil when the
    /// syntax is neither Explicit nor Implicit VR Little Endian.
    private static func sequenceReader(transferSyntaxUID: String) -> PrintDatasetReader? {
        switch transferSyntaxUID {
        case explicitVRLittleEndianTransferSyntaxUID: return PrintDatasetReader(explicitVR: true)
        case implicitVRLittleEndianTransferSyntaxUID: return PrintDatasetReader(explicitVR: false)
        default: return nil
        }
    }

    /// One non-sequence element for the DICOM JSON encoder: text transcoded to UTF-8.
    private static func jsonElement(tag: Tag, vr: VR, raw: Data, characterSet: String?) -> DataElement {
        var value = raw
        if tag == .specificCharacterSet {
            value = Data("ISO_IR 192".utf8)
        } else if vr.characterRepertoire != nil {
            value = Data(QueryResultDecoding.decodeString(raw, specificCharacterSet: characterSet).utf8)
        }
        return DataElement(tag: tag, vr: vr, length: UInt32(value.count), valueData: value)
    }

    /// One sequence item, its nested sequences decoded recursively.
    private static func jsonItem(_ set: PrintAttributeSet, characterSet: String?) -> SequenceItem {
        var elements: [DataElement] = set.elements.values.map {
            jsonElement(tag: $0.tag, vr: $0.vr, raw: $0.valueData, characterSet: characterSet)
        }
        for (tag, items) in set.sequences {
            elements.append(DataElement(tag: tag, vr: .SQ, length: 0, valueData: Data(),
                                        sequenceItems: items.map { jsonItem($0, characterSet: characterSet) }))
        }
        return SequenceItem(elements: elements)
    }
}
