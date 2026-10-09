// DICOMInspectorView.swift
// DICOMStudio
//
// DICOM Studio — DICOM tag inspector sheet
//
// NEMA-verified: 2026a, checked 2026-10-05 — the binary-VR set shown as bytes is now OB, OD, OF, OL, OV, OW and UN — the 6 'Other …' VRs of PS3.5 2026a Table 6.2-1 plus Unknown (OV was missing: corrected, D28); Pixel Data (7FE0,0010) and SQ handled separately; US/SS/UL/SL/IS decoded numerically; tag names from DICOMDictionary (PS3.6 Table 6-1); private creators in elements 0010–00FF of odd groups (PS3.5 7.8.1); checked by Scripts/diff_studio_g2_viewer.py

#if canImport(SwiftUI)
import SwiftUI
import DICOMKit
import DICOMCore
import DICOMDictionary

// MARK: - Platform-independent helpers

/// Converts a DICOM element to a display-ready value string.
/// Lives outside the SwiftUI guard so it can be unit-tested on Linux.
public enum DICOMInspectorHelpers: Sendable {

    /// Returns a human-readable value string for a DICOM data element.
    public static func displayValue(for element: DataElement) -> String {
        let tag = element.tag
        // Pixel data: show byte count rather than dumping bytes
        if tag.group == 0x7FE0 && tag.element == 0x0010 {
            let bytes = element.valueData.count
            if bytes > 0 {
                return "<\(bytes) bytes of pixel data>"
            }
            let fragments = element.encapsulatedFragments?.count ?? 0
            if fragments > 0 {
                return "<\(fragments) compressed fragment(s)>"
            }
            return "<no pixel data>"
        }

        // Sequence: show item count
        if element.vr == .SQ {
            let count = element.sequenceItems?.count ?? 0
            return "<\(count) sequence item(s)>"
        }

        // Binary VRs (PS3.5 Table 6.2-1: OB, OD, OF, OL, OV, OW and UN): show hex preview
        if [VR.OB, .OD, .OF, .OL, .OV, .OW, .UN].contains(element.vr) {
            let bytes = element.valueData
            if bytes.isEmpty { return "<empty>" }
            let preview = bytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
            if bytes.count > 8 {
                return "\(preview) … [\(bytes.count) bytes]"
            }
            return "\(preview) [\(bytes.count) bytes]"
        }

        // Numeric VRs: prefer explicit numeric decoding over stringValue.
        switch element.vr {
        case .US, .SS:
            if let values = element.uint16Values, !values.isEmpty {
                return values.map(String.init).joined(separator: "\\")
            }
            if let value = element.uint16Value {
                return String(value)
            }
        case .UL, .SL:
            if let values = element.uint32Values, !values.isEmpty {
                return values.map(String.init).joined(separator: "\\")
            }
            if let value = element.uint32Value {
                return String(value)
            }
        case .IS:
            if let values = element.stringValues, !values.isEmpty {
                return values.joined(separator: "\\")
            }
        default:
            break
        }

        // String-valued VRs
        return element.stringValue ?? "<\(element.valueData.count) bytes>"
    }

    /// Formats a tag as "(GGGG,EEEE)".
    public static func tagString(_ tag: Tag) -> String {
        String(format: "(%04X,%04X)", tag.group, tag.element)
    }

    /// Returns the tag name from the DICOM dictionary, or a fallback.
    /// For private tags, resolves the Private Creator element from the dataset.
    public static func tagName(_ tag: Tag, dataSet: DataSet? = nil) -> String {
        if let entry = DataElementDictionary.lookup(tag: tag) {
            return entry.name
        }
        // Private tags have odd group numbers
        if tag.group % 2 == 1 {
            if tag.element >= 0x0010 && tag.element <= 0x00FF {
                return "Private Creator"
            }
            // Look up private creator for this block
            let block = UInt16((tag.element >> 8) & 0xFF)
            if block >= 0x10, let ds = dataSet {
                let creatorTag = Tag(group: tag.group, element: block)
                if let creator = ds[creatorTag]?.stringValue {
                    return creator
                }
            }
            return String(format: "Private (%04X,%04X)", tag.group, tag.element)
        }
        return String(format: "Tag (%04X,%04X)", tag.group, tag.element)
    }
}

// MARK: - SwiftUI Views

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct DICOMInspectorView: View {
    public let dicomFile: DICOMFile

    @State private var searchText: String = ""
    @State private var showFMI: Bool = true
    @Environment(\.dismiss) private var dismiss

    public init(dicomFile: DICOMFile) {
        self.dicomFile = dicomFile
    }

    // Flattened list of rows to display, including sequence children
    private var rows: [InspectorRow] {
        let query = searchText.lowercased()

        var result: [InspectorRow] = []

        let ds = dicomFile.dataSet

        // File Meta Information
        let fmiElements = dicomFile.fileMetaInformation.allElements
            .sorted { $0.tag < $1.tag }
        if !fmiElements.isEmpty {
            result.append(.sectionHeader("File Meta Information (\(fmiElements.count) elements)"))
            if showFMI {
                for elem in fmiElements {
                    Self.flattenElement(elem, depth: 0, query: query, dataSet: ds, into: &result)
                }
            }
        }

        // Dataset
        let dsElements = ds.allElements
            .sorted { $0.tag < $1.tag }
        result.append(.sectionHeader("Dataset (\(dsElements.count) elements)"))
        for elem in dsElements {
            Self.flattenElement(elem, depth: 0, query: query, dataSet: ds, into: &result)
        }

        return result
    }

    /// Recursively flattens a data element and its sequence children into rows.
    private static func flattenElement(_ element: DataElement, depth: Int, query: String, dataSet: DataSet, into rows: inout [InspectorRow]) {
        let row = InspectorRow.element(from: element, depth: depth, dataSet: dataSet)
        let matchesQuery = query.isEmpty || "\(row.tagString) \(row.name) \(row.value)".lowercased().contains(query)

        if matchesQuery {
            rows.append(row)
        }

        // Recurse into sequence items
        if element.vr == .SQ, let items = element.sequenceItems {
            for (index, item) in items.enumerated() {
                let itemRow = InspectorRow.sequenceItem(index: index, itemCount: item.elements.count, depth: depth + 1)
                if query.isEmpty || matchesQuery {
                    rows.append(itemRow)
                }
                for child in item.elements.values.sorted(by: { $0.tag < $1.tag }) {
                    flattenElement(child, depth: depth + 2, query: query, dataSet: dataSet, into: &rows)
                }
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("DICOM Inspector")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tags…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            // Element list
            List(rows) { row in
                switch row.kind {
                case .sectionHeader(let title):
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.secondary.opacity(0.12))
                case .element, .sequenceItem:
                    InspectorElementRow(row: row)
                        .padding(.leading, CGFloat(row.depth) * 16)
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 540, minHeight: 440)
        .accessibilityLabel("DICOM tag inspector")
    }
}

// MARK: - Row Model

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct InspectorRow: Identifiable {
    let id: String
    let tagString: String
    let vr: String
    let name: String
    let value: String
    let depth: Int
    let kind: Kind

    enum Kind {
        case sectionHeader(String)
        case element
        case sequenceItem
    }

    static func sectionHeader(_ text: String) -> InspectorRow {
        InspectorRow(id: "header:\(text)", tagString: "", vr: "", name: text, value: "", depth: 0, kind: .sectionHeader(text))
    }

    static func element(from element: DataElement, depth: Int = 0, dataSet: DataSet? = nil) -> InspectorRow {
        let tagStr = DICOMInspectorHelpers.tagString(element.tag)
        let name = DICOMInspectorHelpers.tagName(element.tag, dataSet: dataSet)
        let value = DICOMInspectorHelpers.displayValue(for: element)
        return InspectorRow(
            id: "\(tagStr)_d\(depth)_\(UUID().uuidString.prefix(8))",
            tagString: tagStr,
            vr: element.vr.rawValue,
            name: name,
            value: value,
            depth: depth,
            kind: .element
        )
    }

    static func sequenceItem(index: Int, itemCount: Int, depth: Int) -> InspectorRow {
        InspectorRow(
            id: "item_\(index)_d\(depth)_\(UUID().uuidString.prefix(8))",
            tagString: "(FFFE,E000)",
            vr: "--",
            name: "Item #\(index + 1)",
            value: "\(itemCount) element\(itemCount == 1 ? "" : "s")",
            depth: depth,
            kind: .sequenceItem
        )
    }
}

// MARK: - Element Row View

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct InspectorElementRow: View {
    let row: InspectorRow

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Tag + VR
            VStack(alignment: .leading, spacing: 2) {
                Text(row.tagString)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(row.vr)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(width: 104, alignment: .leading)

            // Name + Value
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(row.value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), tag \(row.tagString), \(row.vr), value: \(row.value)")
    }
}

#endif
