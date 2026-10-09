// NEMA-verified: 2026a, checked 2026-10-01 — UID prefixes and names checked against PS3.6 2026a Table A-1 (--statistics prints the Table A-1 name of the Transfer Syntax and SOP Class UIDs, D147); the .20x prefix also covers JPIP HTJ2K .204/.205 (recorded); --tag matches PS3.6 Table 6-1/7-1 keywords exactly (D148); Private Creator (gggg,0010-00FF) named per PS3.5 7.8.1 (D146)
import Foundation
import DICOMCore
import DICOMDictionary
import J2KCore
import J2KCodec

/// Output format for ``MetadataPresenter``.
///
/// Defined in the framework (rather than in the `dicom-info` CLI target) so the
/// CLI and DICOMStudio's in-app tool render through the exact same code path,
/// eliminating any chance of output drift between them.
public enum MetadataOutputFormat: String, Sendable, CaseIterable {
    case text
    case json
    case csv
}

/// Presents DICOM metadata in various output formats.
///
/// Shared by the `dicom-info` CLI and DICOMStudio's CLI Workshop so both produce
/// byte-identical output from the same parsed ``DICOMFile``.
public struct MetadataPresenter {
    public let file: DICOMFile
    public let filterTags: [String]
    public let includePrivate: Bool
    public let showStats: Bool

    public init(
        file: DICOMFile,
        filterTags: [String] = [],
        includePrivate: Bool = false,
        showStats: Bool = false
    ) {
        self.file = file
        self.filterTags = filterTags
        self.includePrivate = includePrivate
        self.showStats = showStats
    }

    public func render(format: MetadataOutputFormat) throws -> String {
        switch format {
        case .text:
            return renderPlainText()
        case .json:
            return try renderJSON()
        case .csv:
            return renderCSV()
        }
    }

    // MARK: - Plain Text Output

    private func renderPlainText() -> String {
        var output = ""

        if showStats {
            output += renderFileStatistics()
            output += "\n"

            let tsUID = file.fileMetaInformation.string(for: .transferSyntaxUID) ?? ""
            if isJ2KTransferSyntax(tsUID) {
                output += renderJ2KSection(tsUID: tsUID)
                output += "\n"
            }
        }

        output += "=== File Meta Information ===\n"
        output += renderDataSetAsText(file.fileMetaInformation)
        output += "\n=== Main Data Set ===\n"
        output += renderDataSetAsText(file.dataSet)

        return output
    }

    private func renderFileStatistics() -> String {
        var stats = "=== File Statistics ===\n"

        if let transferSyntax = file.fileMetaInformation.string(for: .transferSyntaxUID) {
            stats += "Transfer Syntax: \(Self.uidWithName(transferSyntax))\n"
        }

        if let sopClass = file.dataSet.string(for: .sopClassUID) {
            stats += "SOP Class: \(Self.uidWithName(sopClass))\n"
        }

        if let modality = file.dataSet.string(for: .modality) {
            stats += "Modality: \(modality)\n"
        }

        return stats
    }

    private func renderDataSetAsText(_ dataSet: DataSet) -> String {
        var lines: [String] = []
        let allTags = dataSet.tags

        for tag in allTags {
            guard let element = dataSet[tag] else { continue }

            // Skip private tags unless requested
            if tag.isPrivate && !includePrivate {
                continue
            }

            // Filter by keyword, tag or name if specified
            guard matchesFilter(tag) else { continue }

            let valueStr = Self.formatElementValue(element)
            let tagName = AttributeNames.name(for: tag) ?? "Unknown"
            let paddedName = tagName.padding(toLength: max(tagName.count, 40), withPad: " ", startingAt: 0)
            let line = "\(tag.description) \(paddedName) VR=\(element.vr.rawValue) \(valueStr)"
            lines.append(line)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - JSON Output

    private func renderJSON() throws -> String {
        var jsonDict: [String: Any] = [:]

        if showStats {
            jsonDict["statistics"] = buildStatisticsDict()
        }

        jsonDict["fileMetaInformation"] = buildDataSetDict(file.fileMetaInformation)
        jsonDict["dataSet"] = buildDataSetDict(file.dataSet)

        let jsonData = try JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys])
        return String(data: jsonData, encoding: .utf8) ?? ""
    }

    private func buildStatisticsDict() -> [String: String] {
        var stats: [String: String] = [:]

        // The UID values stay as they were; the PS3.6 Table A-1 names are added beside them.
        if let transferSyntax = file.fileMetaInformation.string(for: .transferSyntaxUID) {
            stats["transferSyntax"] = transferSyntax
            if let name = Self.uidName(transferSyntax) { stats["transferSyntaxName"] = name }
        }

        if let sopClass = file.dataSet.string(for: .sopClassUID) {
            stats["sopClass"] = sopClass
            if let name = Self.uidName(sopClass) { stats["sopClassName"] = name }
        }

        if let modality = file.dataSet.string(for: .modality) {
            stats["modality"] = modality
        }

        // Add J2K metadata when transfer syntax is JPEG 2000
        let tsUID = file.fileMetaInformation.string(for: .transferSyntaxUID) ?? ""
        if isJ2KTransferSyntax(tsUID) {
            let j2kInfo = buildJ2KMetadataDict(tsUID: tsUID)
            for (key, value) in j2kInfo {
                stats["j2k_\(key)"] = value
            }
        }

        return stats
    }

    private func buildDataSetDict(_ dataSet: DataSet) -> [[String: Any]] {
        var elements: [[String: Any]] = []
        let allTags = dataSet.tags

        for tag in allTags {
            guard let element = dataSet[tag] else { continue }

            if tag.isPrivate && !includePrivate {
                continue
            }

            guard matchesFilter(tag) else { continue }

            var elementDict: [String: Any] = [
                "tag": tag.description,
                "name": AttributeNames.name(for: tag) ?? "Unknown",
                "vr": element.vr.rawValue
            ]

            // This JSON is the tool's own model (tag / name / vr / value), not the PS3.18
            // Annex F DICOM JSON Model. Character VRs carry their full value; every other
            // VR carries the same rendering as the text and CSV output (numbers of US, SS,
            // UL, SL, FL, FD, AT tags, a hex preview of the Other VRs), so no element is
            // left without a value (D149).
            if let stringValue = element.stringValue {
                elementDict["value"] = stringValue
            } else {
                let rendered = Self.formatElementValue(element)
                if !rendered.isEmpty { elementDict["value"] = rendered }
            }

            elements.append(elementDict)
        }

        return elements
    }

    // MARK: - CSV Output

    private func renderCSV() -> String {
        var csv = "Tag,Name,VR,Value\n"

        let allElements = collectAllElements()

        for (tag, element) in allElements {
            let valueStr = Self.formatElementValue(element).replacingOccurrences(of: "\"", with: "\"\"")
            let tagName = AttributeNames.name(for: tag) ?? "Unknown"
            let line = "\"\(tag.description)\",\"\(tagName)\",\"\(element.vr.rawValue)\",\"\(valueStr)\"\n"
            csv += line
        }

        return csv
    }

    // MARK: - Helper Methods

    private func collectAllElements() -> [(Tag, DataElement)] {
        var results: [(Tag, DataElement)] = []

        for tag in file.fileMetaInformation.tags {
            guard let element = file.fileMetaInformation[tag] else { continue }
            if shouldIncludeElement(tag: tag) {
                results.append((tag, element))
            }
        }

        for tag in file.dataSet.tags {
            guard let element = file.dataSet[tag] else { continue }
            if shouldIncludeElement(tag: tag) {
                results.append((tag, element))
            }
        }

        return results
    }

    private func shouldIncludeElement(tag: Tag) -> Bool {
        if tag.isPrivate && !includePrivate {
            return false
        }

        return matchesFilter(tag)
    }

    /// Whether `tag` is selected by `filterTags` (always, when there are none). A filter
    /// selects a tag when it is the tag's PS3.6 Table 6-1/7-1 keyword (exact, e.g.
    /// "PatientName"; D148), or occurs case-insensitively in its name or "(GGGG,EEEE)".
    func matchesFilter(_ tag: Tag) -> Bool {
        guard !filterTags.isEmpty else { return true }
        let entry = DataElementDictionary.lookup(tag: tag)
        let tagName = AttributeNames.name(for: tag) ?? ""
        return filterTags.contains { filter in
            (entry.map { !$0.keyword.isEmpty && $0.keyword == filter } ?? false) ||
            tagName.localizedCaseInsensitiveContains(filter) ||
            tag.description.localizedCaseInsensitiveContains(filter)
        }
    }

    /// The PS3.6 2026a Table A-1 name of a UID, if registered (D147).
    static func uidName(_ uid: String) -> String? {
        let trimmed = uid.trimmingCharacters(in: CharacterSet(charactersIn: " \u{0}"))
        return UIDDictionary.lookup(uid: trimmed)?.name
    }

    /// "uid (Table A-1 name)", or the bare UID when it is not registered.
    static func uidWithName(_ uid: String) -> String {
        uidName(uid).map { "\(uid) (\($0))" } ?? uid
    }

    public static func formatElementValue(_ element: DataElement) -> String {
        if let stringValue = element.stringValue {
            let s = stringValue
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            return s.count > 80 ? String(s.prefix(77)) + "..." : s
        }

        // Numeric VRs — decode to human-readable form
        switch element.vr {
        case .US:
            if let vals = element.uint16Values, !vals.isEmpty {
                return vals.map { String($0) }.joined(separator: "\\")
            }
        case .SS:
            if let vals = element.int16Values, !vals.isEmpty {
                return vals.map { String($0) }.joined(separator: "\\")
            }
        case .UL:
            if let vals = element.uint32Values, !vals.isEmpty {
                return vals.map { String($0) }.joined(separator: "\\")
            }
        case .SL:
            if let vals = element.int32Values, !vals.isEmpty {
                return vals.map { String($0) }.joined(separator: "\\")
            }
        case .FL:
            if let vals = element.float32Values, !vals.isEmpty {
                return vals.map { String($0) }.joined(separator: "\\")
            }
        case .FD:
            if let vals = element.float64Values, !vals.isEmpty {
                return vals.map { String($0) }.joined(separator: "\\")
            }
        case .AT:
            // Attribute Tag: pairs of UInt16 groups/elements
            if element.length >= 4 {
                let data = element.valueData
                var tags: [String] = []
                var offset = data.startIndex
                while data.distance(from: offset, to: data.endIndex) >= 4 {
                    let g = UInt16(data[offset]) | (UInt16(data[data.index(offset, offsetBy: 1)]) << 8)
                    let e = UInt16(data[data.index(offset, offsetBy: 2)]) | (UInt16(data[data.index(offset, offsetBy: 3)]) << 8)
                    tags.append(String(format: "(%04X,%04X)", g, e))
                    offset = data.index(offset, offsetBy: 4)
                }
                if !tags.isEmpty { return tags.joined(separator: "\\") }
            }
        default:
            break
        }

        // Otherwise show the raw value itself: readable text when the bytes are
        // printable, else a hex preview — always a single, truncated line.
        let data = element.valueData
        let len = data.count
        if len == 0 { return "" }
        let sample = Data(data.prefix(4096))
        let printable = sample.filter { ($0 >= 0x20 && $0 <= 0x7E) || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }.count
        if !sample.isEmpty, Double(printable) / Double(sample.count) >= 0.85,
           let text = String(data: Data(data.prefix(256)), encoding: .utf8)
                   ?? String(data: Data(data.prefix(256)), encoding: .isoLatin1) {
            let collapsed = text
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\u{0}", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !collapsed.isEmpty {
                return collapsed.count > 80 ? String(collapsed.prefix(77)) + "..." : collapsed
            }
        }
        let hexBytes = 24
        let hex = data.prefix(hexBytes).map { String(format: "%02X", $0) }.joined(separator: " ")
        return len > hexBytes ? "\(hex) ... (\(len) bytes)" : hex
    }

    // MARK: - JPEG 2000 Metadata

    /// Whether the UID is a JPEG 2000 / HTJ2K transfer syntax, per the shared
    /// `TransferSyntax` source of truth (covers .90/.91/.92/.93 and HTJ2K .201/.202/.203).
    private func isJ2KTransferSyntax(_ uid: String) -> Bool {
        TransferSyntax.from(uid: uid)?.isJPEG2000 ?? false
    }

    /// Canonical display label for a JPEG 2000 / HTJ2K transfer syntax, sourced from the
    /// shared `TransferSyntax.displayName` so it never drifts from the rest of the library.
    private func j2kTransferSyntaxLabel(_ uid: String) -> String {
        TransferSyntax.from(uid: uid)?.displayName ?? "JPEG 2000 (unknown variant)"
    }

    private func firstEncapsulatedFragment() -> Data? {
        guard let pixelElement = file.dataSet[.pixelData],
              let fragments = pixelElement.encapsulatedFragments,
              let first = fragments.first else {
            return nil
        }
        return first
    }

    private func renderJ2KSection(tsUID: String) -> String {
        var lines = ["=== JPEG 2000 Codestream Info ==="]
        lines.append("Transfer Syntax : \(j2kTransferSyntaxLabel(tsUID))")
        lines.append("UID             : \(tsUID)")

        let isHTJ2K = tsUID.hasPrefix("1.2.840.10008.1.2.4.20")
        lines.append("HTJ2K           : \(isHTJ2K ? "Yes" : "No")")

        if let fragment = firstEncapsulatedFragment() {
            lines.append("First fragment  : \(fragment.count) bytes")

            // Quick HTJ2K capability check via marker inspection
            let capResult = J2KHTInteroperabilityValidator()
                .validateCapabilitySignaling(codestream: fragment)
            lines.append("HTJ2K (CAP mrk) : \(capResult.isHTJ2K ? "Yes" : "No")")
            if capResult.isMixedMode {
                lines.append("Mixed mode      : Yes")
            }
            if !capResult.warnings.isEmpty {
                lines.append("Warnings        : \(capResult.warnings.joined(separator: "; "))")
            }
        } else {
            lines.append("Pixel data      : Not found or uncompressed")
        }

        if let frameStr = file.dataSet.string(for: .numberOfFrames) {
            lines.append("Frames          : \(frameStr)")
        }
        if let rows = file.dataSet.string(for: .rows) {
            lines.append("Rows            : \(rows)")
        }
        if let cols = file.dataSet.string(for: .columns) {
            lines.append("Columns         : \(cols)")
        }
        if let bitsAlloc = file.dataSet.string(for: .bitsAllocated) {
            lines.append("Bits Allocated  : \(bitsAlloc)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func buildJ2KMetadataDict(tsUID: String) -> [String: String] {
        var info: [String: String] = [:]
        info["transferSyntaxLabel"] = j2kTransferSyntaxLabel(tsUID)
        info["isHTJ2K"] = tsUID.hasPrefix("1.2.840.10008.1.2.4.20") ? "true" : "false"

        if let fragment = firstEncapsulatedFragment() {
            let capResult = J2KHTInteroperabilityValidator()
                .validateCapabilitySignaling(codestream: fragment)
            info["capMarkerHTJ2K"] = capResult.isHTJ2K ? "true" : "false"
            info["isMixedMode"] = capResult.isMixedMode ? "true" : "false"
            info["firstFragmentBytes"] = "\(fragment.count)"
        }

        return info
    }
}
