/// DICOM Content Item Protocol
///
/// Defines the common interface for all content items in DICOM Structured Reporting.
/// Content items form a tree structure representing the document content.
///
/// Reference: PS3.3 Section C.17.3 - SR Document Content Module
///
/// NEMA-verified: 2026a, checked 2026-09-25 — the enumerations below are text-diffed against
/// PS3.3 2026a C.18.6.1.2 (SCOORD Graphic Type), C.18.9.1.2 (SCOORD3D Graphic Type),
/// C.18.7.1.1 (TCOORD Temporal Range Type), Table C.18.8-1 (Continuity of Content) and
/// PS3.16 2026a CID 42 (Numeric Value Qualifier, with CIDs 43 and 44 included).
/// NEMA-verified: 2026a, checked 2026-09-29 — `contentItems` models Content Sequence (0040,A730)
/// of the Document Relationship Macro, PS3.3 2026a Table C.17-6, on every content item (D31).

/// Protocol defining common properties and behaviors for all SR content items
public protocol ContentItem: Sendable, Equatable {
    /// The value type of this content item
    var valueType: ContentItemValueType { get }
    
    /// The concept name that describes what this content item represents
    /// Encoded as Concept Name Code Sequence (0040,A043)
    var conceptName: CodedConcept? { get }
    
    /// The relationship type to the parent content item
    /// Encoded as Relationship Type (0040,A010)
    var relationshipType: RelationshipType? { get }
    
    /// Optional observation date/time for this content item
    /// Encoded as Observation DateTime (0040,A032)
    var observationDateTime: String? { get }
    
    /// Optional observation UID for unique identification
    /// Encoded as Observation UID (0040,A171)
    var observationUID: String? { get }
    
    /// Returns whether this content item can have children
    var canHaveChildren: Bool { get }

    /// The Target Content Items of this item's by-value relationships, each carrying its
    /// Relationship Type (0040,A010). Encoded as Content Sequence (0040,A730), which the
    /// Document Relationship Macro (PS3.3 Table C.17-6) gives every content item, not only
    /// CONTAINER: templates hang children under CODE, NUM, IMAGE and SCOORD items (e.g.
    /// PS3.16 TID 1204 row 2, TID 1501 rows 7 and 10d, TID 320 rows 3-4).
    var contentItems: [AnyContentItem] { get }
}

// MARK: - Default Implementations

extension ContentItem {
    public var canHaveChildren: Bool {
        valueType.canHaveChildren
    }

    /// No children, for conforming types that do not store any
    public var contentItems: [AnyContentItem] { [] }
}

// MARK: - Continuity of Content

/// Continuity of Content for CONTAINER content items
///
/// Specifies whether the content items within a CONTAINER form a continuous narrative
/// or are separate items.
public enum ContinuityOfContent: String, Sendable, Equatable, Hashable {
    /// SEPARATE - Items are logically separate (like a list)
    case separate = "SEPARATE"
    
    /// CONTINUOUS - Items form a continuous narrative
    case continuous = "CONTINUOUS"
}

// MARK: - Graphic Type for Spatial Coordinates

/// Graphic types for SCOORD spatial coordinates
///
/// Defines the shape described by 2D spatial coordinates.
/// Reference: PS3.3 Table C.18.6-1
public enum GraphicType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// A single point
    case point = "POINT"
    
    /// Multiple points connected by straight lines
    case polyline = "POLYLINE"
    
    /// Multiple points connected by straight lines forming a closed polygon
    /// Not a 2D SCOORD Graphic Type. PS3.3 C.18.6.1.2 defines POINT, MULTIPOINT, POLYLINE,
    /// CIRCLE and ELLIPSE; a closed shape is a POLYLINE whose first and last vertices are
    /// the same. POLYGON exists only for SCOORD3D (``GraphicType3D/polygon``).
    @available(*, deprecated, message: "POLYGON is not a 2D SCOORD Graphic Type (PS3.3 C.18.6.1.2); use .polyline with the first vertex repeated as the last")
    case polygon = "POLYGON"
    
    /// An ellipse defined by four points
    case ellipse = "ELLIPSE"
    
    /// A circle defined by center and a point on the circumference
    case circle = "CIRCLE"
    
    /// Multiple disconnected points
    case multipoint = "MULTIPOINT"
    
    /// The five Graphic Types PS3.3 C.18.6.1.2 defines for SCOORD. The deprecated `polygon`
    /// is excluded.
    public static let allCases: [GraphicType] = [.point, .multipoint, .polyline, .circle, .ellipse]

    /// Returns the minimum number of points required
    public var minimumPoints: Int {
        switch self {
        case .point: return 1
        case .multipoint: return 2
        case .polyline: return 2
        case .polygon: return 3
        case .circle: return 2
        case .ellipse: return 4
        }
    }
}

/// Graphic types for SCOORD3D spatial coordinates
///
/// Defines the shape described by 3D spatial coordinates.
/// Reference: PS3.3 Table C.18.9-1
public enum GraphicType3D: String, Sendable, Equatable, Hashable, CaseIterable {
    /// A single point
    case point = "POINT"
    
    /// Multiple points connected by straight lines
    case polyline = "POLYLINE"
    
    /// Multiple points connected by straight lines forming a closed polygon
    case polygon = "POLYGON"
    
    /// An ellipse defined by four points
    case ellipse = "ELLIPSE"
    
    /// An ellipsoid defined by six points
    case ellipsoid = "ELLIPSOID"
    
    /// Multiple disconnected points
    case multipoint = "MULTIPOINT"
    
    /// Returns the minimum number of points required
    public var minimumPoints: Int {
        switch self {
        case .point: return 1
        case .multipoint: return 2
        case .polyline: return 2
        case .polygon: return 3
        case .ellipse: return 4
        case .ellipsoid: return 6
        }
    }
}

/// Temporal range types for TCOORD temporal coordinates
///
/// Defines how temporal coordinates should be interpreted.
/// Reference: PS3.3 C.18.7.1.1 Temporal Range Type
public enum TemporalRangeType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// A single temporal point
    case point = "POINT"
    
    /// Multiple temporal points
    case multipoint = "MULTIPOINT"
    
    /// A range between two temporal points
    case segment = "SEGMENT"

    /// Multiple segments, each denoted by two temporal points
    case multisegment = "MULTISEGMENT"
    
    /// A range beginning at one temporal point, and extending beyond the end of the acquired data
    case beginSegment = "BEGIN"
    
    /// A range beginning before the start of the acquired data, and extending to (and
    /// including) the identified temporal point
    case endSegment = "END"
}

// MARK: - Numeric Value Qualifier

/// Qualifier for numeric content items indicating special values
///
/// Used when a measurement cannot be made normally. The cases are the concepts of PS3.16
/// CID 42 Numeric Value Qualifier (CID 43 Numeric Value Failure Qualifier and CID 44 Numeric
/// Value Unknown Qualifier); ``code`` gives the DCM code written in Numeric Value Qualifier
/// Code Sequence (0040,A301).
public enum NumericValueQualifier: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Value is not a number (result of division by zero, etc.)
    case notANumber = "NOT A NUMBER"
    
    /// Value is negative infinity
    case negativeInfinity = "NEGATIVE INFINITY"
    
    /// Value is positive infinity
    case positiveInfinity = "POSITIVE INFINITY"

    /// Division by zero
    case divideByZero = "DIVIDE BY ZERO"
    
    /// Value underflows the representable range
    case underflow = "UNDERFLOW"
    
    /// Value overflows the representable range
    case overflow = "OVERFLOW"

    /// The measurement failed
    case measurementFailure = "MEASUREMENT FAILURE"

    /// The measurement was not attempted
    case measurementNotAttempted = "MEASUREMENT NOT ATTEMPTED"

    /// The calculation failed
    case calculationFailure = "CALCULATION FAILURE"

    /// The value is out of range
    case valueOutOfRange = "VALUE OUT OF RANGE"

    /// The value is unknown
    case valueUnknown = "VALUE UNKNOWN"

    /// The value is indeterminate
    case valueIndeterminate = "VALUE INDETERMINATE"

    /// The DCM code for this qualifier (PS3.16 CID 43 and CID 44).
    public var code: DICOMCode {
        switch self {
        case .notANumber:              return DICOMCode(codeValue: "114000", codeMeaning: "Not a number")
        case .negativeInfinity:        return DICOMCode(codeValue: "114001", codeMeaning: "Negative Infinity")
        case .positiveInfinity:        return DICOMCode(codeValue: "114002", codeMeaning: "Positive Infinity")
        case .divideByZero:            return DICOMCode(codeValue: "114003", codeMeaning: "Divide by zero")
        case .underflow:               return DICOMCode(codeValue: "114004", codeMeaning: "Underflow")
        case .overflow:                return DICOMCode(codeValue: "114005", codeMeaning: "Overflow")
        case .measurementFailure:      return DICOMCode(codeValue: "114006", codeMeaning: "Measurement failure")
        case .measurementNotAttempted: return DICOMCode(codeValue: "114007", codeMeaning: "Measurement not attempted")
        case .calculationFailure:      return DICOMCode(codeValue: "114008", codeMeaning: "Calculation failure")
        case .valueOutOfRange:         return DICOMCode(codeValue: "114009", codeMeaning: "Value out of range")
        case .valueUnknown:            return DICOMCode(codeValue: "114010", codeMeaning: "Value unknown")
        case .valueIndeterminate:      return DICOMCode(codeValue: "114011", codeMeaning: "Value indeterminate")
        }
    }

    /// The qualifier for a DCM code from CID 42, or nil.
    public init?(code: CodedConcept) {
        guard code.isDICOMControlled,
              let match = Self.allCases.first(where: { $0.code.codeValue == code.codeValue }) else { return nil }
        self = match
    }
}

// MARK: - SOP Reference for SR

/// Reference to a DICOM SOP Instance for Structured Reporting
///
/// Used by COMPOSITE, IMAGE, and WAVEFORM content items to reference DICOM objects.
/// Named differently from DICOMNetwork.SOPReference to avoid ambiguity.
public struct ReferencedSOP: Sendable, Equatable, Hashable {
    /// SOP Class UID of the referenced instance
    public let sopClassUID: String
    
    /// SOP Instance UID of the referenced instance
    public let sopInstanceUID: String
    
    /// Creates a SOP reference
    /// - Parameters:
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID
    public init(sopClassUID: String, sopInstanceUID: String) {
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
    }
}

/// Reference to a DICOM image with optional frame specification
public struct ImageReference: Sendable, Equatable, Hashable {
    /// The SOP reference
    public let sopReference: ReferencedSOP
    
    /// Optional frame numbers (for multi-frame images)
    public let frameNumbers: [Int]?
    
    /// Optional segment numbers (for segmentation objects)
    public let segmentNumbers: [Int]?
    
    /// Optional purpose of reference
    public let purposeOfReference: CodedConcept?
    
    /// Creates an image reference
    /// - Parameters:
    ///   - sopReference: The SOP reference
    ///   - frameNumbers: Optional frame numbers
    ///   - segmentNumbers: Optional segment numbers
    ///   - purposeOfReference: Optional purpose of reference
    public init(
        sopReference: ReferencedSOP,
        frameNumbers: [Int]? = nil,
        segmentNumbers: [Int]? = nil,
        purposeOfReference: CodedConcept? = nil
    ) {
        self.sopReference = sopReference
        self.frameNumbers = frameNumbers
        self.segmentNumbers = segmentNumbers
        self.purposeOfReference = purposeOfReference
    }
    
    /// Creates an image reference with just UIDs
    public init(
        sopClassUID: String,
        sopInstanceUID: String,
        frameNumbers: [Int]? = nil
    ) {
        self.sopReference = ReferencedSOP(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID)
        self.frameNumbers = frameNumbers
        self.segmentNumbers = nil
        self.purposeOfReference = nil
    }
}

/// One (M,C) pair of Referenced Waveform Channels (0040,A0B0) (PS3.3 2026a C.18.5.1.1):
/// the Item number of Waveform Sequence (5400,0100) in the referenced object (the Multiplex
/// Group Number) and the Item number of Channel Definition Sequence (003A,0200) within that
/// group (the Channel Number). Channel 0 means all channels of the multiplex group.
public struct WaveformChannelReference: Sendable, Equatable, Hashable {
    /// Multiplex Group Number (1-based Item number of Waveform Sequence (5400,0100))
    public let multiplexGroup: Int

    /// Channel Number (1-based Item number of Channel Definition Sequence (003A,0200)), or
    /// 0 for every channel of the multiplex group
    public let channel: Int

    public init(multiplexGroup: Int, channel: Int) {
        self.multiplexGroup = multiplexGroup
        self.channel = channel
    }
}

/// Reference to waveform data with optional channel specification
/// (Waveform Reference Macro, PS3.3 2026a Table C.18.5-1)
public struct WaveformReference: Sendable, Equatable, Hashable {
    /// The SOP reference
    public let sopReference: ReferencedSOP
    
    /// The Channel Numbers (the C halves) of `referencedChannels`, or the channel numbers
    /// given to ``init(sopReference:channelNumbers:)``
    public let channelNumbers: [Int]?

    /// Referenced Waveform Channels (0040,A0B0) as (M,C) pairs (C.18.5.1.1), Type 1C:
    /// "Required if the Referenced SOP Instance is a Waveform that contains multiple Channels
    /// and the reference does not apply to all Channels of all Multiplex Groups". When the
    /// reference was made with ``init(sopReference:channelNumbers:)`` the pairs are in
    /// multiplex group 1.
    public let referencedChannels: [WaveformChannelReference]?
    
    /// Creates a waveform reference
    /// - Parameters:
    ///   - sopReference: The SOP reference
    ///   - channelNumbers: Optional channel numbers, all in multiplex group 1
    public init(sopReference: ReferencedSOP, channelNumbers: [Int]? = nil) {
        self.sopReference = sopReference
        self.channelNumbers = channelNumbers
        self.referencedChannels = channelNumbers.map { $0.map { WaveformChannelReference(multiplexGroup: 1, channel: $0) } }
    }

    /// Creates a waveform reference with (M,C) channel pairs (PS3.3 2026a C.18.5.1.1)
    /// - Parameters:
    ///   - sopReference: The SOP reference
    ///   - referencedChannels: Referenced Waveform Channels (0040,A0B0) pairs, or nil when
    ///     the reference applies to all channels of all multiplex groups
    public init(sopReference: ReferencedSOP, referencedChannels: [WaveformChannelReference]?) {
        self.sopReference = sopReference
        self.channelNumbers = referencedChannels.map { $0.map(\.channel) }
        self.referencedChannels = referencedChannels
    }
}
