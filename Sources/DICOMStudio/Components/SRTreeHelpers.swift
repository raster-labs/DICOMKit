// SRTreeHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent SR tree navigation and display helpers
// Reference: DICOM PS3.3 C.17.3 (SR Document Content Module)
// NEMA-verified: 2026a, checked 2026-10-06 — switches over the 16 ContentItemValueType cases (TABLE included, P-STUDIO-SR-TABLE) and 7 SRRelationshipType cases are exhaustive over the model enums verified in StructuredReportModel.swift (PS3.3 2026a Tables C.17.3-7 / C.17.3-8); the rest is tree traversal, search and SF Symbol / colour mapping with no standard data

import Foundation

/// Platform-independent helpers for navigating and displaying SR document trees.
///
/// Provides tree traversal, searching, flattening, and display formatting
/// for the 15 content item value types the model carries.
public enum SRTreeHelpers: Sendable {

    // MARK: - Tree Traversal

    /// Flattens an SR content item tree into a depth-first list with indentation level.
    ///
    /// - Parameter root: The root content item.
    /// - Returns: Array of (item, depth) pairs.
    public static func flattenTree(_ root: SRContentItem) -> [(item: SRContentItem, depth: Int)] {
        var result: [(item: SRContentItem, depth: Int)] = []
        flattenRecursive(root, depth: 0, into: &result)
        return result
    }

    private static func flattenRecursive(
        _ item: SRContentItem,
        depth: Int,
        into result: inout [(item: SRContentItem, depth: Int)]
    ) {
        result.append((item: item, depth: depth))
        if item.isExpanded {
            for child in item.children {
                flattenRecursive(child, depth: depth + 1, into: &result)
            }
        }
    }

    /// Counts total items in the tree (including collapsed subtrees).
    ///
    /// - Parameter root: The root content item.
    /// - Returns: Total item count.
    public static func totalItemCount(_ root: SRContentItem) -> Int {
        root.totalItemCount
    }

    /// Returns maximum depth of the tree.
    ///
    /// - Parameter root: The root content item.
    /// - Returns: Maximum depth (root = 0).
    public static func maxDepth(_ root: SRContentItem) -> Int {
        maxDepthRecursive(root, currentDepth: 0)
    }

    private static func maxDepthRecursive(_ item: SRContentItem, currentDepth: Int) -> Int {
        if item.children.isEmpty {
            return currentDepth
        }
        return item.children.reduce(currentDepth) { maxSoFar, child in
            max(maxSoFar, maxDepthRecursive(child, currentDepth: currentDepth + 1))
        }
    }

    // MARK: - Search

    /// Searches the tree for items matching a query string.
    ///
    /// Matches against concept names, text values, code meanings, person names.
    ///
    /// - Parameters:
    ///   - root: The root content item.
    ///   - query: The search query (case-insensitive).
    /// - Returns: Array of matching item IDs.
    public static func searchTree(_ root: SRContentItem, query: String) -> [UUID] {
        guard !query.isEmpty else { return [] }
        var results: [UUID] = []
        let lowered = query.lowercased()
        searchRecursive(root, query: lowered, results: &results)
        return results
    }

    private static func searchRecursive(
        _ item: SRContentItem,
        query: String,
        results: inout [UUID]
    ) {
        if itemMatchesQuery(item, query: query) {
            results.append(item.id)
        }
        for child in item.children {
            searchRecursive(child, query: query, results: &results)
        }
    }

    /// Checks if a single item matches the search query.
    public static func itemMatchesQuery(_ item: SRContentItem, query: String) -> Bool {
        let lowered = query.lowercased()
        if let name = item.conceptName?.codeMeaning, name.lowercased().contains(lowered) {
            return true
        }
        if let text = item.textValue, text.lowercased().contains(lowered) {
            return true
        }
        if let code = item.codeValue?.codeMeaning, code.lowercased().contains(lowered) {
            return true
        }
        if let pname = item.personName, pname.lowercased().contains(lowered) {
            return true
        }
        if let uid = item.uidValue, uid.lowercased().contains(lowered) {
            return true
        }
        return false
    }

    // MARK: - Expand / Collapse

    /// Returns a new tree with all nodes expanded.
    ///
    /// - Parameter root: The root content item.
    /// - Returns: A copy with all nodes expanded.
    public static func expandAll(_ root: SRContentItem) -> SRContentItem {
        let expandedChildren = root.children.map { expandAll($0) }
        return root.withExpanded(true).withChildren(expandedChildren)
    }

    /// Returns a new tree with all nodes collapsed.
    ///
    /// - Parameter root: The root content item.
    /// - Returns: A copy with all nodes collapsed.
    public static func collapseAll(_ root: SRContentItem) -> SRContentItem {
        let collapsedChildren = root.children.map { collapseAll($0) }
        return root.withExpanded(false).withChildren(collapsedChildren)
    }

    /// Toggles expansion of a specific node by ID.
    ///
    /// - Parameters:
    ///   - root: The root content item.
    ///   - itemID: The ID of the item to toggle.
    /// - Returns: A copy with the specified node toggled.
    public static func toggleExpansion(_ root: SRContentItem, itemID: UUID) -> SRContentItem {
        if root.id == itemID {
            return root.withExpanded(!root.isExpanded)
        }
        let updatedChildren = root.children.map { toggleExpansion($0, itemID: itemID) }
        return root.withChildren(updatedChildren)
    }

    // MARK: - Display Formatting

    /// Formats a content item's value for display.
    ///
    /// - Parameter item: The content item.
    /// - Returns: A formatted string representation of the value.
    public static func formatItemValue(_ item: SRContentItem) -> String {
        switch item.valueType {
        case .container:
            return item.continuityOfContent?.rawValue ?? "CONTAINER"
        case .text:
            return item.textValue ?? ""
        case .code:
            if let code = item.codeValue {
                return "\(code.codeMeaning) (\(code.codingSchemeDesignator): \(code.codeValue))"
            }
            return ""
        case .numeric:
            if let value = item.numericValue {
                let unitStr = item.measurementUnit?.codeMeaning ?? ""
                return unitStr.isEmpty ? String(format: "%.4g", value) : "\(String(format: "%.4g", value)) \(unitStr)"
            }
            return ""
        case .date:
            return item.dateValue ?? ""
        case .time:
            return item.timeValue ?? ""
        case .dateTime:
            return item.dateTimeValue ?? ""
        case .personName:
            return item.personName ?? ""
        case .uidRef:
            return item.uidValue ?? ""
        case .spatialCoord:
            let typeStr = item.graphicType?.rawValue ?? "Unknown"
            let count = (item.graphicData?.count ?? 0) / 2
            return "\(typeStr) (\(count) points)"
        case .spatialCoord3D:
            let typeStr = item.graphicType3D?.rawValue ?? "Unknown"
            let count = (item.graphicData3D?.count ?? 0) / 3
            return "\(typeStr) (\(count) points)"
        case .temporalCoord:
            return item.temporalRangeType?.rawValue ?? "Temporal"
        case .composite:
            return item.referencedSOPInstanceUID ?? "Composite Reference"
        case .image:
            let uid = item.referencedSOPInstanceUID ?? "Unknown"
            if let frames = item.referencedFrameNumbers, !frames.isEmpty {
                return "Image \(uid) [frames: \(frames.map(String.init).joined(separator: ", "))]"
            }
            return "Image \(uid)"
        case .waveform:
            return item.referencedSOPInstanceUID ?? "Waveform Reference"
        case .table:
            return "Table"
        }
    }

    /// Returns the display label for a content item (concept name or value type).
    ///
    /// - Parameter item: The content item.
    /// - Returns: A label string for the item.
    public static func itemLabel(_ item: SRContentItem) -> String {
        if let name = item.conceptName {
            return name.codeMeaning
        }
        return item.valueType.displayName
    }

    /// Returns an SF Symbol name appropriate for the content item's value type.
    ///
    /// - Parameter valueType: The value type.
    /// - Returns: An SF Symbol name.
    public static func sfSymbolForValueType(_ valueType: ContentItemValueType) -> String {
        switch valueType {
        case .container: return "folder"
        case .text: return "doc.text"
        case .code: return "tag"
        case .numeric: return "number"
        case .date: return "calendar"
        case .time: return "clock"
        case .dateTime: return "calendar.badge.clock"
        case .personName: return "person"
        case .uidRef: return "link"
        case .spatialCoord: return "scope"
        case .spatialCoord3D: return "cube"
        case .temporalCoord: return "timer"
        case .composite: return "doc"
        case .image: return "photo"
        case .waveform: return "waveform.path.ecg"
        case .table: return "tablecells"
        }
    }

    /// Returns a display color name for a relationship type.
    ///
    /// - Parameter relationship: The relationship type.
    /// - Returns: A color name string.
    public static func colorForRelationship(_ relationship: SRRelationshipType) -> String {
        switch relationship {
        case .contains: return "blue"
        case .hasObsContext: return "green"
        case .hasAcqContext: return "orange"
        case .hasConceptMod: return "purple"
        case .hasProperties: return "teal"
        case .inferredFrom: return "red"
        case .selectedFrom: return "brown"
        }
    }

    // MARK: - Statistics

    /// Returns counts of each value type in the tree.
    ///
    /// - Parameter root: The root content item.
    /// - Returns: Dictionary mapping value types to counts.
    public static func valueTypeCounts(_ root: SRContentItem) -> [ContentItemValueType: Int] {
        var counts: [ContentItemValueType: Int] = [:]
        countValueTypes(root, counts: &counts)
        return counts
    }

    private static func countValueTypes(
        _ item: SRContentItem,
        counts: inout [ContentItemValueType: Int]
    ) {
        counts[item.valueType, default: 0] += 1
        for child in item.children {
            countValueTypes(child, counts: &counts)
        }
    }

    /// Collects all coded concepts used in the tree.
    ///
    /// - Parameter root: The root content item.
    /// - Returns: Array of unique coded concepts.
    public static func allCodedConcepts(_ root: SRContentItem) -> [CodedConcept] {
        var concepts: [CodedConcept] = []
        var seen = Set<String>()
        collectConcepts(root, concepts: &concepts, seen: &seen)
        return concepts
    }

    private static func collectConcepts(
        _ item: SRContentItem,
        concepts: inout [CodedConcept],
        seen: inout Set<String>
    ) {
        if let name = item.conceptName {
            let key = "\(name.codingSchemeDesignator):\(name.codeValue)"
            if !seen.contains(key) {
                seen.insert(key)
                concepts.append(name)
            }
        }
        if let code = item.codeValue {
            let key = "\(code.codingSchemeDesignator):\(code.codeValue)"
            if !seen.contains(key) {
                seen.insert(key)
                concepts.append(code)
            }
        }
        for child in item.children {
            collectConcepts(child, concepts: &concepts, seen: &seen)
        }
    }
}
