// MetadataTreeNode.swift
// DICOMStudio
//
// DICOM Studio — Tree node model for DICOM metadata display
//
// NEMA-verified: 2026a, checked 2026-10-05 — `isSequence` keys on VR SQ and `lengthString` names 0xFFFFFFFF
// Undefined Length (PS3.5 2026a 7.1.2, 7.5); otherwise display plumbing with no standard values.

import Foundation

/// Represents a node in the DICOM metadata tree view.
///
/// Supports nested sequence (SQ) elements with recursive children,
/// enabling a tree-based display of DICOM data elements.
public struct MetadataTreeNode: Identifiable, Sendable {
    /// Unique identifier for this node.
    public let id: UUID

    /// Tag group number (e.g., 0x0008).
    public let group: UInt16

    /// Tag element number (e.g., 0x0010).
    public let element: UInt16

    /// Value Representation code (e.g., "PN", "DA", "SQ").
    public let vr: String

    /// Tag name/keyword from the DICOM dictionary (e.g., "PatientName").
    public let name: String

    /// Formatted display value.
    public let value: String

    /// Raw byte length of the element.
    public let length: UInt32

    /// Whether this is a private tag.
    public let isPrivate: Bool

    /// Private creator identification string, if applicable.
    public let privateCreator: String?

    /// Child nodes for sequence (SQ) elements.
    public let children: [MetadataTreeNode]

    /// Whether this node is a sequence with children.
    public var isSequence: Bool { vr == "SQ" }

    /// Whether this node has children.
    public var hasChildren: Bool { !children.isEmpty }

    /// Formatted tag string (e.g., "(0008,0010)").
    public var tagString: String {
        String(format: "(%04X,%04X)", group, element)
    }

    /// Formatted length string.
    public var lengthString: String {
        if length == 0xFFFFFFFF {
            return "Undefined"
        }
        if length < 1024 {
            return "\(length) bytes"
        }
        return String(format: "%.1f KB", Double(length) / 1024.0)
    }

    /// Creates a metadata tree node.
    public init(
        id: UUID = UUID(),
        group: UInt16,
        element: UInt16,
        vr: String,
        name: String,
        value: String,
        length: UInt32 = 0,
        isPrivate: Bool = false,
        privateCreator: String? = nil,
        children: [MetadataTreeNode] = []
    ) {
        self.id = id
        self.group = group
        self.element = element
        self.vr = vr
        self.name = name
        self.value = value
        self.length = length
        self.isPrivate = isPrivate
        self.privateCreator = privateCreator
        self.children = children
    }

    /// Total number of nodes in this subtree (including this node).
    public var totalNodeCount: Int {
        1 + children.reduce(0) { $0 + $1.totalNodeCount }
    }
}

/// Helper for building metadata tree nodes.
public enum MetadataTreeBuilder: Sendable {

    /// Filters tree nodes by search text, matching tag string, name, or value.
    ///
    /// - Parameters:
    ///   - nodes: The nodes to filter.
    ///   - searchText: The search text.
    /// - Returns: Filtered nodes (including parents of matching children).
    public static func filter(nodes: [MetadataTreeNode], searchText: String) -> [MetadataTreeNode] {
        guard !searchText.isEmpty else { return nodes }
        let query = searchText.lowercased()

        return nodes.compactMap { node in
            let directMatch = matchesSearch(node: node, query: query)
            let filteredChildren = filter(nodes: node.children, searchText: searchText)

            if directMatch || !filteredChildren.isEmpty {
                return MetadataTreeNode(
                    id: node.id,
                    group: node.group,
                    element: node.element,
                    vr: node.vr,
                    name: node.name,
                    value: node.value,
                    length: node.length,
                    isPrivate: node.isPrivate,
                    privateCreator: node.privateCreator,
                    children: filteredChildren
                )
            }
            return nil
        }
    }

    /// Checks if a node matches a search query.
    private static func matchesSearch(node: MetadataTreeNode, query: String) -> Bool {
        node.tagString.lowercased().contains(query) ||
        node.name.lowercased().contains(query) ||
        node.value.lowercased().contains(query) ||
        node.vr.lowercased().contains(query) ||
        (node.privateCreator?.lowercased().contains(query) ?? false)
    }
}
