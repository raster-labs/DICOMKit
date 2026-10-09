import Foundation

/// DICOM Sequence Item
///
/// Represents a single item within a DICOM Sequence (SQ) data element.
/// Each sequence item contains a collection of data elements and is delimited
/// by Item tags (FFFE,E000) and Item Delimitation Item tags (FFFE,E00D).
///
/// Reference: DICOM PS3.5 Section 7.5 - Nesting of Data Sets
///
/// NEMA-verified: 2026a, checked 2026-09-25 — the three delimiter tags (FFFE,E000), (FFFE,E00D) and (FFFE,E0DD) and their roles match PS3.5 2026a §7.5 and §7.5.1; no other standard data.
public struct SequenceItem: Sendable {
    /// Data elements contained within this sequence item
    public let elements: [Tag: DataElement]
    
    /// Creates an empty sequence item
    public init() {
        self.elements = [:]
    }
    
    /// Creates a sequence item with the given elements
    /// - Parameter elements: Dictionary of tag to data element mappings
    public init(elements: [Tag: DataElement]) {
        self.elements = elements
    }
    
    /// Creates a sequence item from an array of data elements
    /// - Parameter elements: Array of data elements
    public init(elements: [DataElement]) {
        // Tolerate malformed data with a duplicate tag inside one item:
        // uniquingKeysWith keeps the last occurrence instead of trapping.
        self.elements = Dictionary(elements.map { ($0.tag, $0) }, uniquingKeysWith: { _, last in last })
    }
    
    /// Accesses a data element by tag
    /// - Parameter tag: The tag to look up
    /// - Returns: The data element if found, nil otherwise
    public subscript(tag: Tag) -> DataElement? {
        return elements[tag]
    }
    
    /// Returns the string value for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: String value or nil
    public func string(for tag: Tag) -> String? {
        return elements[tag]?.stringValue
    }
    
    /// Returns the string values for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of string values or nil
    public func strings(for tag: Tag) -> [String]? {
        return elements[tag]?.stringValues
    }
    
    /// Number of elements in this sequence item
    public var count: Int {
        return elements.count
    }
    
    /// All tags in this sequence item, sorted
    public var tags: [Tag] {
        return Array(elements.keys).sorted()
    }
    
    /// All data elements in tag order
    public var allElements: [DataElement] {
        return tags.compactMap { elements[$0] }
    }
}

// MARK: - Sequence Delimiter Tags
extension Tag {
    /// Item tag (FFFE,E000)
    ///
    /// Marks the beginning of a sequence item.
    /// Reference: PS3.5 Section 7.5.1
    public static let item = Tag(group: 0xFFFE, element: 0xE000)
    
    /// Item Delimitation Item tag (FFFE,E00D)
    ///
    /// Marks the end of a sequence item with undefined length.
    /// Reference: PS3.5 Section 7.5.1
    public static let itemDelimitationItem = Tag(group: 0xFFFE, element: 0xE00D)
    
    /// Sequence Delimitation Item tag (FFFE,E0DD)
    ///
    /// Marks the end of a sequence with undefined length.
    /// Reference: PS3.5 Section 7.5.1
    public static let sequenceDelimitationItem = Tag(group: 0xFFFE, element: 0xE0DD)
}
