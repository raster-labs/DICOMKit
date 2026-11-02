// ClipboardHelper.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent clipboard formatting helper

import Foundation

/// Platform-independent helper for formatting DICOM tag data for clipboard operations.
///
/// Provides methods to format tag values, metadata rows, and complete element
/// information into clipboard-ready strings.
public enum ClipboardHelper: Sendable {

    /// Formats a single DICOM tag value for clipboard copy.
    ///
    /// - Parameters:
    ///   - tagString: The formatted tag string (e.g., "(0010,0010)").
    ///   - name: The tag name/keyword (e.g., "PatientName").
    ///   - value: The formatted display value.
    /// - Returns: A formatted string suitable for clipboard.
    public static func formatTagForClipboard(
        tagString: String,
        name: String,
        value: String
    ) -> String {
        "\(tagString) \(name) = \(value)"
    }

    /// Formats a complete metadata row for clipboard copy.
    ///
    /// - Parameters:
    ///   - tagString: The formatted tag string.
    ///   - vr: The Value Representation code.
    ///   - name: The tag name/keyword.
    ///   - value: The formatted display value.
    ///   - length: The formatted length string.
    /// - Returns: A tab-separated formatted string.
    public static func formatMetadataRowForClipboard(
        tagString: String,
        vr: String,
        name: String,
        value: String,
        length: String
    ) -> String {
        "\(tagString)\t\(vr)\t\(name)\t\(value)\t\(length)"
    }

    /// Formats just the value for simple clipboard copy.
    ///
    /// - Parameter value: The display value.
    /// - Returns: The trimmed value string.
    public static func formatValueForClipboard(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Formats a metadata tree node for clipboard copy.
    ///
    /// - Parameter node: The metadata tree node.
    /// - Returns: A formatted string with tag, VR, name, value, and length.
    public static func formatNodeForClipboard(_ node: MetadataTreeNode) -> String {
        formatMetadataRowForClipboard(
            tagString: node.tagString,
            vr: node.vr,
            name: node.name,
            value: node.copyValue,
            length: node.lengthString
        )
    }

    /// Formats multiple metadata tree nodes for clipboard copy (e.g., batch export).
    ///
    /// - Parameter nodes: The metadata tree nodes to format.
    /// - Returns: A newline-separated formatted string with header row.
    public static func formatNodesForClipboard(_ nodes: [MetadataTreeNode]) -> String {
        var lines: [String] = ["Tag\tVR\tName\tValue\tLength"]
        func append(_ nodes: [MetadataTreeNode], indent: String) {
            for node in nodes {
                lines.append(indent + formatNodeForClipboard(node))
                append(node.children, indent: indent + "  ")
            }
        }
        append(nodes, indent: "")
        return lines.joined(separator: "\n")
    }
}
