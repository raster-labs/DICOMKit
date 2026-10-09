// NEMA-verified: 2026a, checked 2026-09-25 — all 16 value types of PS3.3 2026a Table C.17.3-7 are wrapped (TABLE added 2026-09-25, P8). Cites C.17.3 correctly. C1 classification confirmed.
// NEMA-verified: 2026a, checked 2026-09-29 — `contentItems` / `children` expose the Content Sequence (0040,A730) of every value type per PS3.3 2026a Table C.17-6 (D31).

/// Type-erased Content Item Wrapper
///
/// Provides a type-erased wrapper for content items to enable heterogeneous collections.
///
/// Reference: PS3.3 Section C.17.3 - SR Document Content Module

/// Type-erased wrapper for any content item
///
/// This allows storing different types of content items in a single collection,
/// which is necessary for the hierarchical structure of SR documents.
public struct AnyContentItem: Sendable, Equatable, Hashable {
    /// The underlying content item storage
    private let storage: Storage
    
    /// Private storage enum for type erasure
    private enum Storage: Sendable, Equatable, Hashable {
        case text(TextContentItem)
        case code(CodeContentItem)
        case numeric(NumericContentItem)
        case date(DateContentItem)
        case time(TimeContentItem)
        case dateTime(DateTimeContentItem)
        case personName(PersonNameContentItem)
        case uidRef(UIDRefContentItem)
        case composite(CompositeContentItem)
        case image(ImageContentItem)
        case waveform(WaveformContentItem)
        case scoord(SpatialCoordinatesContentItem)
        case scoord3D(SpatialCoordinates3DContentItem)
        case tcoord(TemporalCoordinatesContentItem)
        case container(ContainerContentItem)
        case table(TableContentItem)
    }
    
    // MARK: - Initialization
    
    /// Creates an AnyContentItem from a TextContentItem
    public init(_ item: TextContentItem) {
        self.storage = .text(item)
    }
    
    /// Creates an AnyContentItem from a CodeContentItem
    public init(_ item: CodeContentItem) {
        self.storage = .code(item)
    }
    
    /// Creates an AnyContentItem from a NumericContentItem
    public init(_ item: NumericContentItem) {
        self.storage = .numeric(item)
    }
    
    /// Creates an AnyContentItem from a DateContentItem
    public init(_ item: DateContentItem) {
        self.storage = .date(item)
    }
    
    /// Creates an AnyContentItem from a TimeContentItem
    public init(_ item: TimeContentItem) {
        self.storage = .time(item)
    }
    
    /// Creates an AnyContentItem from a DateTimeContentItem
    public init(_ item: DateTimeContentItem) {
        self.storage = .dateTime(item)
    }
    
    /// Creates an AnyContentItem from a PersonNameContentItem
    public init(_ item: PersonNameContentItem) {
        self.storage = .personName(item)
    }
    
    /// Creates an AnyContentItem from a UIDRefContentItem
    public init(_ item: UIDRefContentItem) {
        self.storage = .uidRef(item)
    }
    
    /// Creates an AnyContentItem from a CompositeContentItem
    public init(_ item: CompositeContentItem) {
        self.storage = .composite(item)
    }
    
    /// Creates an AnyContentItem from an ImageContentItem
    public init(_ item: ImageContentItem) {
        self.storage = .image(item)
    }
    
    /// Creates an AnyContentItem from a WaveformContentItem
    public init(_ item: WaveformContentItem) {
        self.storage = .waveform(item)
    }
    
    /// Creates an AnyContentItem from a SpatialCoordinatesContentItem
    public init(_ item: SpatialCoordinatesContentItem) {
        self.storage = .scoord(item)
    }
    
    /// Creates an AnyContentItem from a SpatialCoordinates3DContentItem
    public init(_ item: SpatialCoordinates3DContentItem) {
        self.storage = .scoord3D(item)
    }
    
    /// Creates an AnyContentItem from a TemporalCoordinatesContentItem
    public init(_ item: TemporalCoordinatesContentItem) {
        self.storage = .tcoord(item)
    }
    
    /// Creates an AnyContentItem from a ContainerContentItem
    public init(_ item: ContainerContentItem) {
        self.storage = .container(item)
    }

    /// Creates an AnyContentItem from a TableContentItem
    public init(_ item: TableContentItem) {
        self.storage = .table(item)
    }
    
    // MARK: - Common Properties
    
    /// The value type of the wrapped content item
    public var valueType: ContentItemValueType {
        switch storage {
        case .text: return .text
        case .code: return .code
        case .numeric: return .num
        case .date: return .date
        case .time: return .time
        case .dateTime: return .datetime
        case .personName: return .pname
        case .uidRef: return .uidref
        case .composite: return .composite
        case .image: return .image
        case .waveform: return .waveform
        case .scoord: return .scoord
        case .scoord3D: return .scoord3D
        case .tcoord: return .tcoord
        case .container: return .container
        case .table: return .table
        }
    }
    
    /// The concept name of the wrapped content item
    public var conceptName: CodedConcept? {
        switch storage {
        case .text(let item): return item.conceptName
        case .code(let item): return item.conceptName
        case .numeric(let item): return item.conceptName
        case .date(let item): return item.conceptName
        case .time(let item): return item.conceptName
        case .dateTime(let item): return item.conceptName
        case .personName(let item): return item.conceptName
        case .uidRef(let item): return item.conceptName
        case .composite(let item): return item.conceptName
        case .image(let item): return item.conceptName
        case .waveform(let item): return item.conceptName
        case .scoord(let item): return item.conceptName
        case .scoord3D(let item): return item.conceptName
        case .tcoord(let item): return item.conceptName
        case .container(let item): return item.conceptName
        case .table(let item): return item.conceptName
        }
    }
    
    /// The relationship type of the wrapped content item
    public var relationshipType: RelationshipType? {
        switch storage {
        case .text(let item): return item.relationshipType
        case .code(let item): return item.relationshipType
        case .numeric(let item): return item.relationshipType
        case .date(let item): return item.relationshipType
        case .time(let item): return item.relationshipType
        case .dateTime(let item): return item.relationshipType
        case .personName(let item): return item.relationshipType
        case .uidRef(let item): return item.relationshipType
        case .composite(let item): return item.relationshipType
        case .image(let item): return item.relationshipType
        case .waveform(let item): return item.relationshipType
        case .scoord(let item): return item.relationshipType
        case .scoord3D(let item): return item.relationshipType
        case .tcoord(let item): return item.relationshipType
        case .container(let item): return item.relationshipType
        case .table(let item): return item.relationshipType
        }
    }
    
    /// The observation date/time of the wrapped content item
    public var observationDateTime: String? {
        switch storage {
        case .text(let item): return item.observationDateTime
        case .code(let item): return item.observationDateTime
        case .numeric(let item): return item.observationDateTime
        case .date(let item): return item.observationDateTime
        case .time(let item): return item.observationDateTime
        case .dateTime(let item): return item.observationDateTime
        case .personName(let item): return item.observationDateTime
        case .uidRef(let item): return item.observationDateTime
        case .composite(let item): return item.observationDateTime
        case .image(let item): return item.observationDateTime
        case .waveform(let item): return item.observationDateTime
        case .scoord(let item): return item.observationDateTime
        case .scoord3D(let item): return item.observationDateTime
        case .tcoord(let item): return item.observationDateTime
        case .container(let item): return item.observationDateTime
        case .table(let item): return item.observationDateTime
        }
    }
    
    // MARK: - Type-Specific Access
    
    /// Returns the wrapped item as TextContentItem if applicable
    public var asText: TextContentItem? {
        if case .text(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as CodeContentItem if applicable
    public var asCode: CodeContentItem? {
        if case .code(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as NumericContentItem if applicable
    public var asNumeric: NumericContentItem? {
        if case .numeric(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as DateContentItem if applicable
    public var asDate: DateContentItem? {
        if case .date(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as TimeContentItem if applicable
    public var asTime: TimeContentItem? {
        if case .time(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as DateTimeContentItem if applicable
    public var asDateTime: DateTimeContentItem? {
        if case .dateTime(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as PersonNameContentItem if applicable
    public var asPersonName: PersonNameContentItem? {
        if case .personName(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as UIDRefContentItem if applicable
    public var asUIDRef: UIDRefContentItem? {
        if case .uidRef(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as CompositeContentItem if applicable
    public var asComposite: CompositeContentItem? {
        if case .composite(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as ImageContentItem if applicable
    public var asImage: ImageContentItem? {
        if case .image(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as WaveformContentItem if applicable
    public var asWaveform: WaveformContentItem? {
        if case .waveform(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as SpatialCoordinatesContentItem if applicable
    public var asSpatialCoordinates: SpatialCoordinatesContentItem? {
        if case .scoord(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as SpatialCoordinates3DContentItem if applicable
    public var asSpatialCoordinates3D: SpatialCoordinates3DContentItem? {
        if case .scoord3D(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as TemporalCoordinatesContentItem if applicable
    public var asTemporalCoordinates: TemporalCoordinatesContentItem? {
        if case .tcoord(let item) = storage { return item }
        return nil
    }
    
    /// Returns the wrapped item as ContainerContentItem if applicable
    public var asContainer: ContainerContentItem? {
        if case .container(let item) = storage { return item }
        return nil
    }

    /// Returns the wrapped item as TableContentItem if applicable
    public var asTable: TableContentItem? {
        if case .table(let item) = storage { return item }
        return nil
    }
    
    // MARK: - Utility Properties
    
    /// Returns whether this is a container item
    public var isContainer: Bool {
        if case .container = storage { return true }
        return false
    }
    
    /// Returns whether this is a reference type (COMPOSITE, IMAGE, or WAVEFORM)
    public var isReference: Bool {
        switch storage {
        case .composite, .image, .waveform:
            return true
        default:
            return false
        }
    }
    
    /// Returns whether this is a coordinate type (SCOORD, SCOORD3D, or TCOORD)
    public var isCoordinate: Bool {
        switch storage {
        case .scoord, .scoord3D, .tcoord:
            return true
        default:
            return false
        }
    }
    
    /// Returns the child items: a container's contents (possibly empty), or the Content
    /// Sequence of any other item that has one. Nil for a non-container item without
    /// children, as before non-container items could carry them.
    public var children: [AnyContentItem]? {
        if let container = asContainer { return container.contentItems }
        let items = contentItems
        return items.isEmpty ? nil : items
    }

    /// The Target Content Items of the wrapped item's by-value relationships: its Content
    /// Sequence (0040,A730), which PS3.3 Table C.17-6 gives every value type. Empty when
    /// the item has none.
    public var contentItems: [AnyContentItem] {
        switch storage {
        case .text(let item): return item.contentItems
        case .code(let item): return item.contentItems
        case .numeric(let item): return item.contentItems
        case .date(let item): return item.contentItems
        case .time(let item): return item.contentItems
        case .dateTime(let item): return item.contentItems
        case .personName(let item): return item.contentItems
        case .uidRef(let item): return item.contentItems
        case .composite(let item): return item.contentItems
        case .image(let item): return item.contentItems
        case .waveform(let item): return item.contentItems
        case .scoord(let item): return item.contentItems
        case .scoord3D(let item): return item.contentItems
        case .tcoord(let item): return item.contentItems
        case .container(let item): return item.contentItems
        case .table(let item): return item.contentItems
        }
    }

    /// Returns a copy of the wrapped item with `items` as its Content Sequence (0040,A730),
    /// replacing any children it had (PS3.3 Table C.17-6).
    public func withContentItems(_ items: [AnyContentItem]) -> AnyContentItem {
        func set<T>(_ item: T, _ path: WritableKeyPath<T, [AnyContentItem]>) -> T {
            var copy = item
            copy[keyPath: path] = items
            return copy
        }
        switch storage {
        case .text(let item): return AnyContentItem(set(item, \.contentItems))
        case .code(let item): return AnyContentItem(set(item, \.contentItems))
        case .numeric(let item): return AnyContentItem(set(item, \.contentItems))
        case .date(let item): return AnyContentItem(set(item, \.contentItems))
        case .time(let item): return AnyContentItem(set(item, \.contentItems))
        case .dateTime(let item): return AnyContentItem(set(item, \.contentItems))
        case .personName(let item): return AnyContentItem(set(item, \.contentItems))
        case .uidRef(let item): return AnyContentItem(set(item, \.contentItems))
        case .composite(let item): return AnyContentItem(set(item, \.contentItems))
        case .image(let item): return AnyContentItem(set(item, \.contentItems))
        case .waveform(let item): return AnyContentItem(set(item, \.contentItems))
        case .scoord(let item): return AnyContentItem(set(item, \.contentItems))
        case .scoord3D(let item): return AnyContentItem(set(item, \.contentItems))
        case .tcoord(let item): return AnyContentItem(set(item, \.contentItems))
        case .table(let item): return AnyContentItem(set(item, \.contentItems))
        case .container(let item):
            return AnyContentItem(ContainerContentItem(
                conceptName: item.conceptName,
                continuityOfContent: item.continuityOfContent,
                contentItems: items,
                templateIdentifier: item.templateIdentifier,
                mappingResource: item.mappingResource,
                relationshipType: item.relationshipType,
                observationDateTime: item.observationDateTime,
                observationUID: item.observationUID
            ))
        }
    }

    /// Returns a copy of the wrapped item with `items` appended to its Content Sequence
    public func addingContentItems(_ items: [AnyContentItem]) -> AnyContentItem {
        items.isEmpty ? self : withContentItems(contentItems + items)
    }
}

// MARK: - CustomStringConvertible

extension AnyContentItem: CustomStringConvertible {
    public var description: String {
        let conceptStr = conceptName?.codeMeaning ?? "unnamed"
        return "\(valueType.rawValue): \(conceptStr)"
    }
}

// MARK: - Convenience Initializers for Common Use Cases

extension AnyContentItem {
    /// Creates a text content item
    public static func text(
        conceptName: CodedConcept? = nil,
        value: String,
        relationshipType: RelationshipType? = nil
    ) -> AnyContentItem {
        AnyContentItem(TextContentItem(
            conceptName: conceptName,
            textValue: value,
            relationshipType: relationshipType
        ))
    }
    
    /// Creates a code content item
    public static func code(
        conceptName: CodedConcept? = nil,
        value: CodedConcept,
        relationshipType: RelationshipType? = nil
    ) -> AnyContentItem {
        AnyContentItem(CodeContentItem(
            conceptName: conceptName,
            conceptCode: value,
            relationshipType: relationshipType
        ))
    }
    
    /// Creates a numeric content item
    public static func numeric(
        conceptName: CodedConcept? = nil,
        value: Double,
        units: CodedConcept? = nil,
        relationshipType: RelationshipType? = nil
    ) -> AnyContentItem {
        AnyContentItem(NumericContentItem(
            conceptName: conceptName,
            value: value,
            units: units,
            relationshipType: relationshipType
        ))
    }
    
    /// Creates a container content item
    public static func container(
        conceptName: CodedConcept? = nil,
        continuityOfContent: ContinuityOfContent = .separate,
        items: [AnyContentItem] = [],
        relationshipType: RelationshipType? = nil
    ) -> AnyContentItem {
        AnyContentItem(ContainerContentItem(
            conceptName: conceptName,
            continuityOfContent: continuityOfContent,
            contentItems: items,
            relationshipType: relationshipType
        ))
    }
}
