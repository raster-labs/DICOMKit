// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (content tree traversal; relationship types are DICOMCore enums); traversal descends into the Content Sequence of every value type per PS3.3 2026a Table C.17-6 (D31)
/// Content Tree Navigation
///
/// Provides traversal, query, and navigation APIs for SR content trees.
///
/// Reference: PS3.3 Section C.17.3.2.4 - Content Sequence and Relationship Type

import Foundation
import DICOMCore

// MARK: - Content Tree Iterator (Depth-First)

/// Iterator for depth-first traversal of SR content trees
///
/// Provides iteration over all content items in a tree, visiting each item
/// before its children (pre-order traversal).
public struct ContentTreeIterator: IteratorProtocol, Sendable {
    /// Stack of items to visit, each with its depth
    private var stack: [(item: AnyContentItem, depth: Int)]
    
    /// Maximum depth to traverse (nil for unlimited)
    private let maxDepth: Int?
    
    /// Creates an iterator starting from a container
    /// - Parameters:
    ///   - container: The container to iterate
    ///   - maxDepth: Maximum depth to traverse (nil for unlimited)
    public init(container: ContainerContentItem, maxDepth: Int? = nil) {
        // Initialize stack with container's children in reverse order (for proper traversal order)
        self.stack = container.contentItems.reversed().map { ($0, 0) }
        self.maxDepth = maxDepth
    }
    
    /// Creates an iterator starting from an AnyContentItem
    /// - Parameters:
    ///   - root: The root item to iterate
    ///   - maxDepth: Maximum depth to traverse (nil for unlimited)
    public init(root: AnyContentItem, maxDepth: Int? = nil) {
        self.stack = [(root, 0)]
        self.maxDepth = maxDepth
    }
    
    /// Returns the next content item in depth-first order
    public mutating func next() -> AnyContentItem? {
        guard !stack.isEmpty else { return nil }
        
        let (item, depth) = stack.removeLast()
        
        // If this item has children and we haven't exceeded max depth, add them to the stack.
        // Any value type may have children (Content Sequence, PS3.3 Table C.17-6).
        let children = item.contentItems
        if !children.isEmpty {
            let withinDepth = maxDepth.map { depth < $0 } ?? true
            if withinDepth {
                // Add children in reverse order for proper traversal order
                for child in children.reversed() {
                    stack.append((child, depth + 1))
                }
            }
        }
        
        return item
    }
}

// MARK: - Breadth-First Iterator

/// Iterator for breadth-first traversal of SR content trees
///
/// Visits all items at a given depth before moving to the next level.
public struct BreadthFirstIterator: IteratorProtocol, Sendable {
    /// Queue of items to visit, each with its depth
    private var queue: [(item: AnyContentItem, depth: Int)]
    
    /// Current index in the queue
    private var currentIndex: Int = 0
    
    /// Maximum depth to traverse (nil for unlimited)
    private let maxDepth: Int?
    
    /// Creates an iterator starting from a container
    /// - Parameters:
    ///   - container: The container to iterate
    ///   - maxDepth: Maximum depth to traverse (nil for unlimited)
    public init(container: ContainerContentItem, maxDepth: Int? = nil) {
        self.queue = container.contentItems.map { ($0, 0) }
        self.maxDepth = maxDepth
    }
    
    /// Creates an iterator starting from an AnyContentItem
    /// - Parameters:
    ///   - root: The root item to iterate
    ///   - maxDepth: Maximum depth to traverse (nil for unlimited)
    public init(root: AnyContentItem, maxDepth: Int? = nil) {
        self.queue = [(root, 0)]
        self.maxDepth = maxDepth
    }
    
    /// Returns the next content item in breadth-first order
    public mutating func next() -> AnyContentItem? {
        guard currentIndex < queue.count else { return nil }
        
        let (item, depth) = queue[currentIndex]
        currentIndex += 1
        
        // If this item has children and we haven't exceeded max depth, add them to the queue.
        // Any value type may have children (Content Sequence, PS3.3 Table C.17-6).
        let children = item.contentItems
        if !children.isEmpty {
            let withinDepth = maxDepth.map { depth < $0 } ?? true
            if withinDepth {
                for child in children {
                    queue.append((child, depth + 1))
                }
            }
        }
        
        return item
    }
}

// MARK: - Content Tree Sequence

/// A sequence wrapper for iterating over SR content trees
public struct ContentTreeSequence: Sequence, Sendable {
    /// The root container
    private let container: ContainerContentItem
    
    /// Maximum depth to traverse
    private let maxDepth: Int?
    
    /// Traversal order
    public enum TraversalOrder: Sendable {
        case depthFirst
        case breadthFirst
    }
    
    private let order: TraversalOrder
    
    /// Creates a content tree sequence
    /// - Parameters:
    ///   - container: The root container
    ///   - order: Traversal order (default: depth-first)
    ///   - maxDepth: Maximum depth to traverse (nil for unlimited)
    public init(
        container: ContainerContentItem,
        order: TraversalOrder = .depthFirst,
        maxDepth: Int? = nil
    ) {
        self.container = container
        self.order = order
        self.maxDepth = maxDepth
    }
    
    public func makeIterator() -> AnyIterator<AnyContentItem> {
        switch order {
        case .depthFirst:
            var iterator = ContentTreeIterator(container: container, maxDepth: maxDepth)
            return AnyIterator { iterator.next() }
        case .breadthFirst:
            var iterator = BreadthFirstIterator(container: container, maxDepth: maxDepth)
            return AnyIterator { iterator.next() }
        }
    }
}

// MARK: - SRPath

/// Path for addressing content items in an SR document tree
///
/// Provides a way to navigate to specific content items using a path notation
/// similar to file system paths or XPath.
///
/// Example paths:
/// - "/" - root container
/// - "/Finding" - first item with concept meaning "Finding"
/// - "/Finding[0]" - first Finding item (explicit index)
/// - "/Finding[1]" - second Finding item
/// - "/Report/Finding/Measurement" - nested path
public struct SRPath: Sendable, Equatable, Hashable, CustomStringConvertible {
    /// Path component representing a single step in the path
    public struct Component: Sendable, Equatable, Hashable, CustomStringConvertible {
        /// The concept name to match (code meaning or code value)
        public let conceptName: String?
        
        /// The index when multiple items match (0-based)
        public let index: Int?
        
        /// Value type filter
        public let valueType: ContentItemValueType?
        
        /// Creates a path component matching by concept name
        /// - Parameters:
        ///   - conceptName: The concept name to match
        ///   - index: Optional index for disambiguation
        public init(conceptName: String, index: Int? = nil) {
            self.conceptName = conceptName
            self.index = index
            self.valueType = nil
        }
        
        /// Creates a path component matching by value type
        /// - Parameters:
        ///   - valueType: The value type to match
        ///   - index: Optional index for disambiguation
        public init(valueType: ContentItemValueType, index: Int? = nil) {
            self.conceptName = nil
            self.index = index
            self.valueType = valueType
        }
        
        /// Creates a path component matching by concept name and value type
        /// - Parameters:
        ///   - conceptName: The concept name to match
        ///   - valueType: The value type to match
        ///   - index: Optional index for disambiguation
        public init(conceptName: String, valueType: ContentItemValueType, index: Int? = nil) {
            self.conceptName = conceptName
            self.index = index
            self.valueType = valueType
        }
        
        /// Internal initializer for all fields
        internal init(conceptName: String?, valueType: ContentItemValueType?, index: Int?) {
            self.conceptName = conceptName
            self.valueType = valueType
            self.index = index
        }
        
        public var description: String {
            var result = ""
            if let conceptName = conceptName {
                result = conceptName
            } else if let valueType = valueType {
                result = "[\(valueType.rawValue)]"
            }
            if let index = index {
                result += "[\(index)]"
            }
            return result
        }
        
        /// Checks if this component matches a content item
        /// - Parameter item: The item to check
        /// - Returns: True if the item matches this component's criteria
        public func matches(_ item: AnyContentItem) -> Bool {
            // Check value type if specified
            if let valueType = valueType, item.valueType != valueType {
                return false
            }
            
            // Check concept name if specified
            if let conceptName = conceptName {
                guard let itemConcept = item.conceptName else { return false }
                // Match either code meaning or code value
                if itemConcept.codeMeaning != conceptName && itemConcept.codeValue != conceptName {
                    return false
                }
            }
            
            return true
        }
    }
    
    /// The path components
    public let components: [Component]
    
    /// Creates an empty path (representing root)
    public init() {
        self.components = []
    }
    
    /// Creates a path from components
    /// - Parameter components: The path components
    public init(components: [Component]) {
        self.components = components
    }
    
    /// Creates a path from a string representation
    /// - Parameter pathString: The path string (e.g., "/Finding/Measurement[0]")
    public init(pathString: String) throws {
        // Parse the path string
        var components: [Component] = []
        
        // Split by "/" and filter empty components
        let parts = pathString.split(separator: "/").map(String.init)
        
        for part in parts {
            if part.isEmpty { continue }
            
            // Parse index if present: "Name[0]" -> ("Name", 0)
            if let bracketStart = part.firstIndex(of: "["),
               let bracketEnd = part.firstIndex(of: "]"),
               bracketStart < bracketEnd {
                let name = String(part[..<bracketStart])
                let indexStr = String(part[part.index(after: bracketStart)..<bracketEnd])
                
                if let index = Int(indexStr) {
                    if name.isEmpty {
                        // Just an index: [0]
                        components.append(Component(conceptName: nil, valueType: nil, index: index))
                    } else {
                        components.append(Component(conceptName: name, index: index))
                    }
                } else {
                    // Invalid index format
                    throw SRPathError.invalidPathFormat(pathString)
                }
            } else {
                // No index
                components.append(Component(conceptName: part, index: nil))
            }
        }
        
        self.components = components
    }
    
    /// Returns a new path with an additional component
    /// - Parameter component: The component to append
    /// - Returns: A new path with the component appended
    public func appending(_ component: Component) -> SRPath {
        SRPath(components: components + [component])
    }
    
    /// Returns a new path with a concept name component
    /// - Parameters:
    ///   - conceptName: The concept name
    ///   - index: Optional index
    /// - Returns: A new path with the component appended
    public func appending(conceptName: String, index: Int? = nil) -> SRPath {
        appending(Component(conceptName: conceptName, index: index))
    }
    
    /// Returns the parent path, or nil if this is the root
    public var parent: SRPath? {
        guard !components.isEmpty else { return nil }
        return SRPath(components: Array(components.dropLast()))
    }
    
    /// Returns whether this is the root path
    public var isRoot: Bool {
        components.isEmpty
    }
    
    /// The depth of this path (number of components)
    public var depth: Int {
        components.count
    }
    
    public var description: String {
        "/" + components.map(\.description).joined(separator: "/")
    }
}

/// Errors for SRPath operations
public enum SRPathError: Error, Sendable, Equatable {
    case invalidPathFormat(String)
    case pathNotFound(SRPath)
    case indexOutOfBounds(index: Int, count: Int)
}

// MARK: - ContainerContentItem Extensions

extension ContainerContentItem {
    /// Returns a sequence for iterating over all content items in this container's tree
    /// - Parameters:
    ///   - order: Traversal order (default: depth-first)
    ///   - maxDepth: Maximum depth to traverse (nil for unlimited)
    /// - Returns: A sequence of content items
    public func contentTreeSequence(
        order: ContentTreeSequence.TraversalOrder = .depthFirst,
        maxDepth: Int? = nil
    ) -> ContentTreeSequence {
        ContentTreeSequence(container: self, order: order, maxDepth: maxDepth)
    }
    
    /// Returns the content item at the specified path
    /// - Parameter path: The path to navigate
    /// - Returns: The content item at the path, or nil if not found
    public func item(at path: SRPath) -> AnyContentItem? {
        guard !path.isRoot else {
            // Return self wrapped in AnyContentItem
            return AnyContentItem(self)
        }
        
        return Self.navigate(in: contentItems, components: path.components[...])
    }
    
    /// Internal navigation helper
    private static func navigate(in contentItems: [AnyContentItem], components: ArraySlice<SRPath.Component>) -> AnyContentItem? {
        guard let firstComponent = components.first else {
            return nil
        }
        
        let remaining = components.dropFirst()
        
        // Find matching items at this level
        let matchingItems = contentItems.filter { firstComponent.matches($0) }
        
        // Get the item at the specified index (default to 0)
        let targetIndex = firstComponent.index ?? 0
        guard targetIndex < matchingItems.count else { return nil }
        
        let targetItem = matchingItems[targetIndex]
        
        // If no more components, return this item
        if remaining.isEmpty {
            return targetItem
        }
        
        // Otherwise, continue into its children: a container's, or the Content Sequence of
        // any other value type (PS3.3 Table C.17-6)
        return navigate(in: targetItem.contentItems, components: remaining)
    }
    
    // MARK: - Subscript Access
    
    /// Access child content items by index
    /// - Parameter index: The index of the child
    /// - Returns: The child at the index, or nil if out of bounds
    public subscript(index: Int) -> AnyContentItem? {
        guard index >= 0 && index < contentItems.count else { return nil }
        return contentItems[index]
    }
    
    /// Access child content items by concept name
    /// - Parameter conceptName: The concept to search for
    /// - Returns: The first child with matching concept name, or nil if not found
    public subscript(concept conceptName: String) -> AnyContentItem? {
        contentItems.first { item in
            guard let concept = item.conceptName else { return false }
            return concept.codeMeaning == conceptName || concept.codeValue == conceptName
        }
    }
    
    /// Access child content items by coded concept
    /// - Parameter concept: The coded concept to search for
    /// - Returns: The first child with matching concept, or nil if not found
    public subscript(concept concept: CodedConcept) -> AnyContentItem? {
        contentItems.first { $0.conceptName == concept }
    }
    
    /// Access all children with a specific concept name
    /// - Parameter conceptName: The concept name to search for
    /// - Returns: Array of children with matching concept name
    public func children(withConcept conceptName: String) -> [AnyContentItem] {
        contentItems.filter { item in
            guard let concept = item.conceptName else { return false }
            return concept.codeMeaning == conceptName || concept.codeValue == conceptName
        }
    }
    
    /// Access all children of a specific value type
    /// - Parameter valueType: The value type to filter by
    /// - Returns: Array of children with matching value type
    public func children(ofType valueType: ContentItemValueType) -> [AnyContentItem] {
        contentItems.filter { $0.valueType == valueType }
    }
    
    // MARK: - Query Methods
    
    /// Finds all content items matching the predicate
    /// - Parameters:
    ///   - recursive: Whether to search recursively (default: true)
    ///   - predicate: The predicate to match
    /// - Returns: Array of matching content items
    public func findItems(recursive: Bool = true, matching predicate: (AnyContentItem) -> Bool) -> [AnyContentItem] {
        if recursive {
            return contentTreeSequence().filter(predicate)
        } else {
            return contentItems.filter(predicate)
        }
    }
    
    /// Finds all content items with the specified concept name
    /// - Parameters:
    ///   - conceptName: The coded concept to search for
    ///   - recursive: Whether to search recursively (default: true)
    /// - Returns: Array of matching content items
    public func findItems(byConceptName conceptName: CodedConcept, recursive: Bool = true) -> [AnyContentItem] {
        findItems(recursive: recursive) { $0.conceptName == conceptName }
    }
    
    /// Finds all content items with concept name matching the string
    /// - Parameters:
    ///   - conceptString: The concept meaning or value to search for
    ///   - recursive: Whether to search recursively (default: true)
    /// - Returns: Array of matching content items
    public func findItems(byConceptString conceptString: String, recursive: Bool = true) -> [AnyContentItem] {
        findItems(recursive: recursive) { item in
            guard let concept = item.conceptName else { return false }
            return concept.codeMeaning == conceptString || concept.codeValue == conceptString
        }
    }
    
    /// Finds all content items of the specified value type
    /// - Parameters:
    ///   - valueType: The value type to search for
    ///   - recursive: Whether to search recursively (default: true)
    /// - Returns: Array of matching content items
    public func findItems(byValueType valueType: ContentItemValueType, recursive: Bool = true) -> [AnyContentItem] {
        findItems(recursive: recursive) { $0.valueType == valueType }
    }
    
    /// Finds all content items with the specified relationship type
    /// - Parameters:
    ///   - relationshipType: The relationship type to search for
    ///   - recursive: Whether to search recursively (default: true)
    /// - Returns: Array of matching content items
    public func findItems(byRelationship relationshipType: RelationshipType, recursive: Bool = true) -> [AnyContentItem] {
        findItems(recursive: recursive) { $0.relationshipType == relationshipType }
    }
    
    // MARK: - Relationship Navigation
    
    /// Returns all items that are properties of this container
    /// (i.e., children with HAS PROPERTIES relationship)
    public var propertyItems: [AnyContentItem] {
        contentItems.filter { $0.relationshipType == .hasProperties }
    }
    
    /// Returns all items that are contained within this container
    /// (i.e., children with CONTAINS relationship)
    public var containedItems: [AnyContentItem] {
        contentItems.filter { $0.relationshipType == .contains }
    }
    
    /// Returns all items that were inferred from this container
    /// (i.e., children with INFERRED FROM relationship)
    public var inferredFromItems: [AnyContentItem] {
        contentItems.filter { $0.relationshipType == .inferredFrom }
    }
    
    /// Returns all items that are acquisition context for this container
    /// (i.e., children with HAS ACQ CONTEXT relationship)
    public var acquisitionContextItems: [AnyContentItem] {
        contentItems.filter { $0.relationshipType == .hasAcqContext }
    }
    
    /// Returns all items that are observation context for this container
    /// (i.e., children with HAS OBS CONTEXT relationship)
    public var observationContextItems: [AnyContentItem] {
        contentItems.filter { $0.relationshipType == .hasObsContext }
    }
    
    /// Returns all items selected from this container
    /// (i.e., children with SELECTED FROM relationship)
    public var selectedFromItems: [AnyContentItem] {
        contentItems.filter { $0.relationshipType == .selectedFrom }
    }
    
    // MARK: - Measurement Navigation
    
    /// Finds all numeric content items (measurements)
    /// - Parameter recursive: Whether to search recursively (default: true)
    /// - Returns: Array of numeric content items
    public func findMeasurements(recursive: Bool = true) -> [NumericContentItem] {
        findItems(byValueType: .num, recursive: recursive).compactMap { $0.asNumeric }
    }
    
    /// Finds all measurements with the specified concept name
    /// - Parameters:
    ///   - conceptName: The concept name to search for
    ///   - recursive: Whether to search recursively (default: true)
    /// - Returns: Array of numeric content items with matching concept
    public func findMeasurements(forConcept conceptName: CodedConcept, recursive: Bool = true) -> [NumericContentItem] {
        findItems(recursive: recursive) {
            $0.valueType == .num && $0.conceptName == conceptName
        }.compactMap { $0.asNumeric }
    }
    
    /// Finds all measurements with concept matching the string
    /// - Parameters:
    ///   - conceptString: The concept meaning or value to search for
    ///   - recursive: Whether to search recursively (default: true)
    /// - Returns: Array of numeric content items with matching concept
    public func findMeasurements(forConceptString conceptString: String, recursive: Bool = true) -> [NumericContentItem] {
        findItems(recursive: recursive) { item in
            guard item.valueType == .num,
                  let concept = item.conceptName else { return false }
            return concept.codeMeaning == conceptString || concept.codeValue == conceptString
        }.compactMap { $0.asNumeric }
    }
    
    /// Finds all measurement groups (containers that contain measurements)
    /// - Parameter recursive: Whether to search recursively (default: true)
    /// - Returns: Array of container content items that contain measurements
    public func findMeasurementGroups(recursive: Bool = true) -> [ContainerContentItem] {
        findItems(byValueType: .container, recursive: recursive).compactMap { item -> ContainerContentItem? in
            guard let container = item.asContainer else { return nil }
            // A measurement group contains at least one numeric item
            let hasMeasurements = container.contentItems.contains { $0.valueType == .num }
            return hasMeasurements ? container : nil
        }
    }
    
    /// Gets the first measurement value for a concept
    /// - Parameter conceptName: The concept name to search for
    /// - Returns: The numeric value if found, nil otherwise
    public func getMeasurementValue(forConcept conceptName: CodedConcept) -> Double? {
        findMeasurements(forConcept: conceptName, recursive: true).first?.value
    }
    
    /// Gets the first measurement value for a concept string
    /// - Parameter conceptString: The concept meaning or value to search for
    /// - Returns: The numeric value if found, nil otherwise
    public func getMeasurementValue(forConceptString conceptString: String) -> Double? {
        findMeasurements(forConceptString: conceptString, recursive: true).first?.value
    }
}

// MARK: - SRDocument Extensions

extension SRDocument {
    /// Returns a sequence for iterating over all content items in this document
    /// - Parameters:
    ///   - order: Traversal order (default: depth-first)
    ///   - maxDepth: Maximum depth to traverse (nil for unlimited)
    /// - Returns: A sequence of content items
    public func contentTreeSequence(
        order: ContentTreeSequence.TraversalOrder = .depthFirst,
        maxDepth: Int? = nil
    ) -> ContentTreeSequence {
        rootContent.contentTreeSequence(order: order, maxDepth: maxDepth)
    }
    
    /// Returns the content item at the specified path
    /// - Parameter path: The path to navigate
    /// - Returns: The content item at the path, or nil if not found
    public func item(at path: SRPath) -> AnyContentItem? {
        rootContent.item(at: path)
    }
    
    /// Returns the content item at the specified path string
    /// - Parameter pathString: The path string (e.g., "/Finding/Measurement[0]")
    /// - Returns: The content item at the path, or nil if not found or invalid path
    public func item(at pathString: String) -> AnyContentItem? {
        guard let path = try? SRPath(pathString: pathString) else { return nil }
        return item(at: path)
    }
    
    // MARK: - Extended Query Methods
    
    /// Finds all content items matching the predicate
    /// - Parameter predicate: The predicate to match
    /// - Returns: Array of matching content items
    public func findItems(matching predicate: (AnyContentItem) -> Bool) -> [AnyContentItem] {
        rootContent.findItems(matching: predicate)
    }
    
    /// Finds all content items with the specified concept name (recursive)
    /// - Parameter conceptName: The coded concept to search for
    /// - Returns: Array of matching content items
    public func findItems(byConceptName conceptName: CodedConcept) -> [AnyContentItem] {
        rootContent.findItems(byConceptName: conceptName)
    }
    
    /// Finds all content items with concept name matching the string
    /// - Parameter conceptString: The concept meaning or value to search for
    /// - Returns: Array of matching content items
    public func findItems(byConceptString conceptString: String) -> [AnyContentItem] {
        rootContent.findItems(byConceptString: conceptString)
    }
    
    /// Finds all content items with the specified relationship type
    /// - Parameter relationshipType: The relationship type to search for
    /// - Returns: Array of matching content items
    public func findItems(byRelationship relationshipType: RelationshipType) -> [AnyContentItem] {
        rootContent.findItems(byRelationship: relationshipType)
    }
    
    // MARK: - Extended Measurement Navigation
    
    /// Finds all measurements in the document
    /// - Returns: Array of numeric content items
    public func findAllMeasurements() -> [NumericContentItem] {
        rootContent.findMeasurements()
    }
    
    /// Finds all measurements with the specified concept name
    /// - Parameter conceptName: The concept name to search for
    /// - Returns: Array of numeric content items with matching concept
    public func findMeasurements(forConcept conceptName: CodedConcept) -> [NumericContentItem] {
        rootContent.findMeasurements(forConcept: conceptName)
    }
    
    /// Finds all measurements with concept matching the string
    /// - Parameter conceptString: The concept meaning or value to search for
    /// - Returns: Array of numeric content items with matching concept
    public func findMeasurements(forConceptString conceptString: String) -> [NumericContentItem] {
        rootContent.findMeasurements(forConceptString: conceptString)
    }
    
    /// Finds all measurement groups in the document
    /// - Returns: Array of container content items that contain measurements
    public func findMeasurementGroups() -> [ContainerContentItem] {
        rootContent.findMeasurementGroups()
    }
    
    /// Gets the first measurement value for a concept
    /// - Parameter conceptName: The concept name to search for
    /// - Returns: The numeric value if found, nil otherwise
    public func getMeasurementValue(forConcept conceptName: CodedConcept) -> Double? {
        rootContent.getMeasurementValue(forConcept: conceptName)
    }
    
    /// Gets the first measurement value for a concept string
    /// - Parameter conceptString: The concept meaning or value to search for
    /// - Returns: The numeric value if found, nil otherwise
    public func getMeasurementValue(forConceptString conceptString: String) -> Double? {
        rootContent.getMeasurementValue(forConceptString: conceptString)
    }
    
    // MARK: - Relationship-Based Navigation
    
    /// Returns all items that are properties (HAS PROPERTIES relationship)
    public var propertyItems: [AnyContentItem] {
        rootContent.findItems(byRelationship: .hasProperties)
    }
    
    /// Returns all items that are contained (CONTAINS relationship)
    public var containedItems: [AnyContentItem] {
        rootContent.findItems(byRelationship: .contains)
    }
    
    /// Returns all items that were inferred from (INFERRED FROM relationship)
    public var inferredFromItems: [AnyContentItem] {
        rootContent.findItems(byRelationship: .inferredFrom)
    }
    
    /// Returns all observation context items
    public var observationContextItems: [AnyContentItem] {
        rootContent.findItems(byRelationship: .hasObsContext)
    }
    
    /// Returns all acquisition context items
    public var acquisitionContextItems: [AnyContentItem] {
        rootContent.findItems(byRelationship: .hasAcqContext)
    }
    
    // MARK: - Subscript Access
    
    /// Access content items by path string
    /// - Parameter pathString: The path string
    /// - Returns: The content item at the path, or nil if not found
    public subscript(path pathString: String) -> AnyContentItem? {
        item(at: pathString)
    }
    
    /// Access content items by SRPath
    /// - Parameter path: The path
    /// - Returns: The content item at the path, or nil if not found
    public subscript(path path: SRPath) -> AnyContentItem? {
        item(at: path)
    }
    
    /// Access root's children by index
    /// - Parameter index: The index
    /// - Returns: The child at the index, or nil if out of bounds
    public subscript(index: Int) -> AnyContentItem? {
        rootContent[index]
    }
    
    /// Access root's children by concept name
    /// - Parameter conceptName: The concept name to search for
    /// - Returns: The first child with matching concept name, or nil if not found
    public subscript(concept conceptName: String) -> AnyContentItem? {
        rootContent[concept: conceptName]
    }
}

// MARK: - AnyContentItem Navigation Extensions

extension AnyContentItem {
    /// Returns a sequence for iterating if this is a container
    /// - Parameters:
    ///   - order: Traversal order (default: depth-first)
    ///   - maxDepth: Maximum depth to traverse (nil for unlimited)
    /// - Returns: A sequence of content items, or nil if not a container
    public func contentTreeSequence(
        order: ContentTreeSequence.TraversalOrder = .depthFirst,
        maxDepth: Int? = nil
    ) -> ContentTreeSequence? {
        guard let container = asContainer else { return nil }
        return container.contentTreeSequence(order: order, maxDepth: maxDepth)
    }
    
    /// Access children by index (a container's, or the Content Sequence of any other item)
    /// - Parameter index: The index
    /// - Returns: The child at the index, or nil if out of bounds
    public subscript(index: Int) -> AnyContentItem? {
        let children = contentItems
        guard index >= 0 && index < children.count else { return nil }
        return children[index]
    }
    
    /// Access children by concept name (a container's, or the Content Sequence of any other item)
    /// - Parameter conceptName: The concept name to search for
    /// - Returns: The first child with matching concept name, or nil if not found
    public subscript(concept conceptName: String) -> AnyContentItem? {
        contentItems.first { item in
            guard let concept = item.conceptName else { return false }
            return concept.codeMeaning == conceptName || concept.codeValue == conceptName
        }
    }
}
