/// DICOM Structured Reporting Content Item Types
///
/// Concrete implementations of all DICOM SR content item value types.
///
/// Reference: PS3.3 Table C.17.3-7 - Value Type Definitions
///
/// NEMA-verified: 2026a, checked 2026-09-25 — each content item type maps to a PS3.3 2026a value macro (C.18.1-C.18.9) or a Table C.17-5 value attribute, and the value types are those of Table C.17.3-7 (TABLE, C.18.10, not modelled: P8). The 15 per-type citations pointed at C.17.3.2.1-C.17.3.2.15, of which only .1-.5 exist and none describes the type; all corrected.
/// NEMA-verified: 2026a, checked 2026-09-29 — every value type carries `contentItems`, the Content Sequence (0040,A730) that the Document Relationship Macro (PS3.3 2026a Table C.17-6) includes in every content item (D31); only CONTAINER did before.

// MARK: - Text Content Item

/// TEXT content item - contains unstructured free text
///
/// Reference: PS3.3 C.17.3 (Table C.17-5, Text Value (0040,A160))
public struct TextContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .text
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The text value (0040,A160)
    public let textValue: String
    
    /// Creates a text content item
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - textValue: The text content
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        textValue: String,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.textValue = textValue
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
}

// MARK: - Code Content Item

/// CODE content item - contains a coded concept value
///
/// Reference: PS3.3 C.18.2 - Code Macro
public struct CodeContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .code
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The coded concept value (0040,A168)
    public let conceptCode: CodedConcept
    
    /// Creates a code content item
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - conceptCode: The coded value
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        conceptCode: CodedConcept,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.conceptCode = conceptCode
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
}

// MARK: - Numeric Content Item

/// NUM content item - contains a numeric measurement with units
///
/// Reference: PS3.3 C.18.1 - Numeric Measurement Macro
public struct NumericContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .num
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The numeric value(s) (0040,A30A) as decimal strings
    public let numericValues: [Double]
    
    /// The measurement units (0040,08EA)
    public let measurementUnits: CodedConcept?
    
    /// Optional floating point values (0040,A161)
    public let floatingPointValues: [Double]?
    
    /// Optional qualifier for special values
    public let numericValueQualifier: NumericValueQualifier?
    
    /// Creates a numeric content item with a single value
    /// - Parameters:
    ///   - conceptName: The concept name describing this measurement
    ///   - value: The numeric value
    ///   - units: The measurement units
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        value: Double,
        units: CodedConcept? = nil,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.numericValues = [value]
        self.measurementUnits = units
        self.floatingPointValues = nil
        self.numericValueQualifier = nil
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
    
    /// Creates a numeric content item with multiple values
    /// - Parameters:
    ///   - conceptName: The concept name describing this measurement
    ///   - values: The numeric values
    ///   - units: The measurement units
    ///   - floatingPointValues: Optional high-precision floating point values
    ///   - qualifier: Optional qualifier for special values
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        values: [Double],
        units: CodedConcept? = nil,
        floatingPointValues: [Double]? = nil,
        qualifier: NumericValueQualifier? = nil,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.numericValues = values
        self.measurementUnits = units
        self.floatingPointValues = floatingPointValues
        self.numericValueQualifier = qualifier
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
    
    /// The primary numeric value (first value if multiple)
    public var value: Double? {
        numericValues.first
    }
}

// MARK: - Date Content Item

/// DATE content item - contains a date value
///
/// Reference: PS3.3 C.17.3 (Table C.17-5, Date (0040,A121))
public struct DateContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .date
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The date value (0040,A121) in DICOM DA format (YYYYMMDD)
    public let dateValue: String
    
    /// Creates a date content item
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - dateValue: The date value in DICOM DA format
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        dateValue: String,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.dateValue = dateValue
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
}

// MARK: - Time Content Item

/// TIME content item - contains a time value
///
/// Reference: PS3.3 C.17.3 (Table C.17-5, Time (0040,A122))
public struct TimeContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .time
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The time value (0040,A122) in DICOM TM format (HHMMSS.FFFFFF)
    public let timeValue: String
    
    /// Creates a time content item
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - timeValue: The time value in DICOM TM format
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        timeValue: String,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.timeValue = timeValue
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
}

// MARK: - DateTime Content Item

/// DATETIME content item - contains a combined date/time value
///
/// Reference: PS3.3 C.17.3 (Table C.17-5, DateTime (0040,A120))
public struct DateTimeContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .datetime
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The datetime value (0040,A120) in DICOM DT format
    public let dateTimeValue: String
    
    /// Creates a datetime content item
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - dateTimeValue: The datetime value in DICOM DT format
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        dateTimeValue: String,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.dateTimeValue = dateTimeValue
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
}

// MARK: - Person Name Content Item

/// PNAME content item - contains a person name value
///
/// Reference: PS3.3 C.17.3 (Table C.17-5, Person Name (0040,A123))
public struct PersonNameContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .pname
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The person name value (0040,A123) in DICOM PN format
    public let personName: String
    
    /// Creates a person name content item
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - personName: The person name in DICOM PN format
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        personName: String,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.personName = personName
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
}

// MARK: - UID Reference Content Item

/// UIDREF content item - contains a DICOM UID reference
///
/// Reference: PS3.3 C.17.3 (Table C.17-5, UID (0040,A124))
public struct UIDRefContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .uidref
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The UID value (0040,A124)
    public let uidValue: String
    
    /// Creates a UID reference content item
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - uidValue: The UID value
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        uidValue: String,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.uidValue = uidValue
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
}

// MARK: - Composite Content Item

/// COMPOSITE content item - references a DICOM composite SOP instance
///
/// Reference: PS3.3 C.18.3 - Composite Object Reference Macro
public struct CompositeContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .composite
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The referenced SOP instance
    public let referencedSOPSequence: ReferencedSOP
    
    /// Creates a composite content item
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - referencedSOPSequence: The SOP reference
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        referencedSOPSequence: ReferencedSOP,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.referencedSOPSequence = referencedSOPSequence
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
    
    /// Convenience initializer with UIDs
    public init(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String,
        relationshipType: RelationshipType? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.referencedSOPSequence = ReferencedSOP(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID
        )
        self.relationshipType = relationshipType
        self.observationDateTime = nil
        self.observationUID = nil
    }
}

// MARK: - Image Content Item

/// IMAGE content item - references a DICOM image, optionally with frames
///
/// Reference: PS3.3 C.18.4 - Image Reference Macro
public struct ImageContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .image
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The image reference
    public let imageReference: ImageReference
    
    /// Creates an image content item
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - imageReference: The image reference
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        imageReference: ImageReference,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.imageReference = imageReference
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
    
    /// Convenience initializer with UIDs
    public init(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String,
        frameNumbers: [Int]? = nil,
        relationshipType: RelationshipType? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.imageReference = ImageReference(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            frameNumbers: frameNumbers
        )
        self.relationshipType = relationshipType
        self.observationDateTime = nil
        self.observationUID = nil
    }
}

// MARK: - Waveform Content Item

/// WAVEFORM content item - references waveform data
///
/// Reference: PS3.3 C.18.5 - Waveform Reference Macro
public struct WaveformContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .waveform
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The waveform reference
    public let waveformReference: WaveformReference
    
    /// Creates a waveform content item
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - waveformReference: The waveform reference
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        waveformReference: WaveformReference,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.waveformReference = waveformReference
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
}

// MARK: - Spatial Coordinates Content Item (2D)

/// SCOORD content item - contains 2D spatial coordinates
///
/// Reference: PS3.3 C.18.6 - Spatial Coordinates Macro
public struct SpatialCoordinatesContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .scoord
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The graphic type defining the shape
    public let graphicType: GraphicType
    
    /// The coordinate data as pairs of (column, row)
    /// Encoded as Graphic Data (0070,0022)
    public let graphicData: [Float]
    
    /// Creates a spatial coordinates content item
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - graphicType: The type of graphic (point, polyline, etc.)
    ///   - graphicData: The coordinate data as [col1, row1, col2, row2, ...]
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        graphicType: GraphicType,
        graphicData: [Float],
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.graphicType = graphicType
        self.graphicData = graphicData
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
    
    /// Returns the number of points in the coordinate data
    public var pointCount: Int {
        graphicData.count / 2
    }
    
    /// Returns the coordinates as an array of (column, row) tuples
    public var points: [(column: Float, row: Float)] {
        stride(from: 0, to: graphicData.count, by: 2).map { i in
            (column: graphicData[i], row: graphicData[i + 1])
        }
    }
}

// MARK: - Spatial Coordinates 3D Content Item

/// SCOORD3D content item - contains 3D spatial coordinates
///
/// Reference: PS3.3 C.18.9 - 3D Spatial Coordinates Macro
public struct SpatialCoordinates3DContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .scoord3D
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The graphic type defining the shape
    public let graphicType: GraphicType3D
    
    /// The coordinate data as triplets of (x, y, z) in patient coordinates
    /// Encoded as Graphic Data (0070,0022)
    public let graphicData: [Float]
    
    /// Frame of Reference UID for the coordinate system
    public let frameOfReferenceUID: String?
    
    /// Creates a 3D spatial coordinates content item
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - graphicType: The type of graphic (point, polyline, etc.)
    ///   - graphicData: The coordinate data as [x1, y1, z1, x2, y2, z2, ...]
    ///   - frameOfReferenceUID: Optional Frame of Reference UID
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        graphicType: GraphicType3D,
        graphicData: [Float],
        frameOfReferenceUID: String? = nil,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.graphicType = graphicType
        self.graphicData = graphicData
        self.frameOfReferenceUID = frameOfReferenceUID
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
    
    /// Returns the number of points in the coordinate data
    public var pointCount: Int {
        graphicData.count / 3
    }
    
    /// Returns the coordinates as an array of (x, y, z) tuples
    public var points: [(x: Float, y: Float, z: Float)] {
        stride(from: 0, to: graphicData.count, by: 3).map { i in
            (x: graphicData[i], y: graphicData[i + 1], z: graphicData[i + 2])
        }
    }
}

// MARK: - Temporal Coordinates Content Item

/// TCOORD content item - contains temporal coordinates
///
/// Reference: PS3.3 C.18.7 - Temporal Coordinates Macro
public struct TemporalCoordinatesContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .tcoord
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []
    
    /// The temporal range type
    public let temporalRangeType: TemporalRangeType
    
    /// Sample positions (for waveform data)
    public let referencedSamplePositions: [UInt32]?
    
    /// Time offsets in seconds
    public let referencedTimeOffsets: [Double]?
    
    /// DateTime values
    public let referencedDateTime: [String]?
    
    /// Creates a temporal coordinates content item with sample positions
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - temporalRangeType: The type of temporal range
    ///   - samplePositions: Sample positions for waveform data
    ///   - relationshipType: Relationship to parent
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        temporalRangeType: TemporalRangeType,
        samplePositions: [UInt32],
        relationshipType: RelationshipType? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.temporalRangeType = temporalRangeType
        self.referencedSamplePositions = samplePositions
        self.referencedTimeOffsets = nil
        self.referencedDateTime = nil
        self.relationshipType = relationshipType
        self.observationDateTime = nil
        self.observationUID = nil
    }
    
    /// Creates a temporal coordinates content item with time offsets
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - temporalRangeType: The type of temporal range
    ///   - timeOffsets: Time offsets in seconds
    ///   - relationshipType: Relationship to parent
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        temporalRangeType: TemporalRangeType,
        timeOffsets: [Double],
        relationshipType: RelationshipType? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.temporalRangeType = temporalRangeType
        self.referencedSamplePositions = nil
        self.referencedTimeOffsets = timeOffsets
        self.referencedDateTime = nil
        self.relationshipType = relationshipType
        self.observationDateTime = nil
        self.observationUID = nil
    }
    
    /// Creates a temporal coordinates content item with datetime values
    /// - Parameters:
    ///   - conceptName: The concept name describing this item
    ///   - temporalRangeType: The type of temporal range
    ///   - dateTimes: DateTime values in DICOM DT format
    ///   - relationshipType: Relationship to parent
    ///   - contentItems: Child content items, written as Content Sequence (0040,A730)
    public init(
        conceptName: CodedConcept? = nil,
        temporalRangeType: TemporalRangeType,
        dateTimes: [String],
        relationshipType: RelationshipType? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.temporalRangeType = temporalRangeType
        self.referencedSamplePositions = nil
        self.referencedTimeOffsets = nil
        self.referencedDateTime = dateTimes
        self.relationshipType = relationshipType
        self.observationDateTime = nil
        self.observationUID = nil
    }
}

// MARK: - Container Content Item

/// CONTAINER content item - groups other content items
///
/// Reference: PS3.3 C.18.8 - Container Macro
public struct ContainerContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .container
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?
    
    /// Continuity of content within this container
    public let continuityOfContent: ContinuityOfContent
    
    /// Child content items contained in this container
    public let contentItems: [AnyContentItem]
    
    /// Optional template identifier for this container
    public let templateIdentifier: String?
    
    /// Optional mapping resource for template
    public let mappingResource: String?
    
    /// Creates a container content item
    /// - Parameters:
    ///   - conceptName: The concept name describing this container
    ///   - continuityOfContent: Whether items are separate or continuous
    ///   - contentItems: Child content items
    ///   - templateIdentifier: Optional TID
    ///   - mappingResource: Optional mapping resource
    ///   - relationshipType: Relationship to parent
    ///   - observationDateTime: Optional observation date/time
    ///   - observationUID: Optional observation UID
    public init(
        conceptName: CodedConcept? = nil,
        continuityOfContent: ContinuityOfContent = .separate,
        contentItems: [AnyContentItem] = [],
        templateIdentifier: String? = nil,
        mappingResource: String? = nil,
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil
    ) {
        self.conceptName = conceptName
        self.continuityOfContent = continuityOfContent
        self.contentItems = contentItems
        self.templateIdentifier = templateIdentifier
        self.mappingResource = mappingResource
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }
    
    /// Creates a new container with additional content items
    public func adding(_ items: [AnyContentItem]) -> ContainerContentItem {
        ContainerContentItem(
            conceptName: conceptName,
            continuityOfContent: continuityOfContent,
            contentItems: contentItems + items,
            templateIdentifier: templateIdentifier,
            mappingResource: mappingResource,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        )
    }
    
    /// Returns whether this container is empty
    public var isEmpty: Bool {
        contentItems.isEmpty
    }
    
    /// Returns the count of direct children
    public var childCount: Int {
        contentItems.count
    }
}

// MARK: - Table Content Item

/// A TABLE content item: a two-dimensional tabulation of text, numeric, coded or
/// date-time values (Table Content Item Macro, PS3.3 2026a C.18.10, Table C.18.10-1).
///
/// The table has `rows` × `columns` cells, numbered from 1. Cells may be given one at a
/// time (row and column set), as a whole row (column nil) or as a whole column (row nil),
/// and may be sparse. Row and column definitions carry the concept (and, for numeric
/// data, the units) that describe an axis; a definition with `index == nil` applies to
/// every row or column.
///
/// Added 2026-09-25 (P8). Permitted in Extensible SR (A.35.15) and Enhanced X-Ray
/// Radiation Dose SR (A.35.22).
public struct TableContentItem: ContentItem, Sendable, Equatable, Hashable {
    public let valueType: ContentItemValueType = .table
    public let conceptName: CodedConcept?
    public let relationshipType: RelationshipType?
    public let observationDateTime: String?
    public let observationUID: String?

    /// Content Sequence (0040,A730): the items this one is the source of by-value
    /// relationships to (Document Relationship Macro, PS3.3 Table C.17-6). See
    /// ``ContentItem/contentItems``.
    public internal(set) var contentItems: [AnyContentItem] = []

    /// Number of Table Rows (0040,A802)
    public let rows: Int

    /// Number of Table Columns (0040,A803)
    public let columns: Int

    /// Table Row Definition Sequence (0040,A806), sorted by row number
    public let rowDefinitions: [TableAxisDefinition]

    /// Table Column Definition Sequence (0040,A807), sorted by column number
    public let columnDefinitions: [TableAxisDefinition]

    /// Cell Values Sequence (0040,A808)
    public let cells: [TableCell]

    /// Describes the meaning of one row or column, or of all of them when `index` is nil.
    public struct TableAxisDefinition: Sendable, Equatable, Hashable {
        /// Table Row Number (0040,A804) or Table Column Number (0040,A805), from 1; nil = applies to all
        public let index: Int?
        /// Concept Name Code Sequence (0040,A043)
        public let concept: CodedConcept
        /// Measurement Units Code Sequence (0040,08EA), when every value on this axis shares units
        public let units: CodedConcept?

        public init(index: Int? = nil, concept: CodedConcept, units: CodedConcept? = nil) {
            self.index = index
            self.concept = concept
            self.units = units
        }
    }

    /// The value(s) of one Item of the Cell Values Sequence.
    public enum TableCellValue: Sendable, Equatable, Hashable {
        /// Selector UC Value (0072,006F)
        case text([String])
        /// Selector DS Value (0072,0072)
        case decimal([Double])
        /// Selector FD Value (0072,0074) (also used when reading FL)
        case floatingPoint([Double])
        /// Selector IS Value (0072,0064) (also used when reading SL, SS, UL, US, SV, UV)
        case integer([Int64])
        /// Selector DT Value (0072,0063)
        case dateTime([String])
        /// Concept Code Sequence (0040,A168)
        case code([CodedConcept])
        /// Referenced Content Item Identifier (0040,DB73): the value is another content item
        case contentItemReference([Int])
        /// No value; `TableCell.qualifier` says why (Numeric Value Qualifier Code Sequence)
        case absent

        /// The Selector Attribute VR (0072,0050) written for this value, if any.
        public var selectorVR: VR? {
            switch self {
            case .text: return .UC
            case .decimal: return .DS
            case .floatingPoint: return .FD
            case .integer: return .IS
            case .dateTime: return .DT
            case .code, .contentItemReference, .absent: return nil
            }
        }
    }

    /// One Item of the Cell Values Sequence: a single cell, a whole row or a whole column.
    public struct TableCell: Sendable, Equatable, Hashable {
        /// Table Row Number (0040,A804), from 1; nil when the item spans a whole column
        public let row: Int?
        /// Table Column Number (0040,A805), from 1; nil when the item spans a whole row
        public let column: Int?
        public let value: TableCellValue
        /// Measurement Units Code Sequence (0040,08EA) for numeric cells with units
        public let units: CodedConcept?
        /// Numeric Value Qualifier Code Sequence (0040,A301): why a numeric value is absent
        public let qualifier: CodedConcept?

        public init(row: Int? = nil, column: Int? = nil, value: TableCellValue,
                    units: CodedConcept? = nil, qualifier: CodedConcept? = nil) {
            self.row = row
            self.column = column
            self.value = value
            self.units = units
            self.qualifier = qualifier
        }
    }

    /// Creates a table content item
    public init(
        conceptName: CodedConcept? = nil,
        rows: Int,
        columns: Int,
        rowDefinitions: [TableAxisDefinition] = [],
        columnDefinitions: [TableAxisDefinition] = [],
        cells: [TableCell],
        relationshipType: RelationshipType? = nil,
        observationDateTime: String? = nil,
        observationUID: String? = nil,
        contentItems: [AnyContentItem] = []
    ) {
        self.contentItems = contentItems
        self.conceptName = conceptName
        self.rows = rows
        self.columns = columns
        self.rowDefinitions = rowDefinitions.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        self.columnDefinitions = columnDefinitions.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        self.cells = cells
        self.relationshipType = relationshipType
        self.observationDateTime = observationDateTime
        self.observationUID = observationUID
    }

    /// The value at (row, column), from 1, resolved through whole-row and whole-column items.
    public func value(row: Int, column: Int) -> TableCellValue? {
        if let exact = cells.first(where: { $0.row == row && $0.column == column }) { return exact.value }
        if let wholeRow = cells.first(where: { $0.row == row && $0.column == nil }) { return element(wholeRow.value, at: column - 1) }
        if let wholeColumn = cells.first(where: { $0.column == column && $0.row == nil }) { return element(wholeColumn.value, at: row - 1) }
        return nil
    }

    private func element(_ value: TableCellValue, at i: Int) -> TableCellValue? {
        func pick<T>(_ a: [T]) -> [T]? { a.indices.contains(i) ? [a[i]] : nil }
        switch value {
        case .text(let a): return pick(a).map(TableCellValue.text)
        case .decimal(let a): return pick(a).map(TableCellValue.decimal)
        case .floatingPoint(let a): return pick(a).map(TableCellValue.floatingPoint)
        case .integer(let a): return pick(a).map(TableCellValue.integer)
        case .dateTime(let a): return pick(a).map(TableCellValue.dateTime)
        case .code(let a): return pick(a).map(TableCellValue.code)
        case .contentItemReference: return value
        case .absent: return .absent
        }
    }
}
