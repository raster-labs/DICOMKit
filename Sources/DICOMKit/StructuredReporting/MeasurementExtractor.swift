// NEMA-verified: 2026a, checked 2026-09-29 — CID 42 qualifier meanings match PS3.16 2026a; closed POLYLINE handled per PS3.3 C.18.6.1.2; DerivationMethod is library-local; SCOORD image from its nested SELECTED FROM IMAGE and ROIs from a NUM's nested INFERRED FROM SCOORD per PS3.3 Table C.17-6 and PS3.16 2026a TID 320 rows 3-4 (D31)
/// Measurement and Coordinate Extraction for DICOM Structured Reporting
///
/// Provides types and APIs for extracting quantitative measurements and
/// spatial/temporal coordinates from SR documents.
///
/// Reference: PS3.3 C.17.3.2 - Numeric measurement encoding
/// Reference: PS3.3 C.18.6 - Spatial Coordinates Macro
/// Reference: PS3.3 C.18.7 - Temporal Coordinates Macro

import Foundation
import DICOMCore

// MARK: - Measurement

/// Represents a quantitative measurement extracted from an SR document
///
/// A measurement combines a numeric value with its units, the concept being measured,
/// and optional context information about how the measurement was obtained.
///
/// Example:
/// ```swift
/// let extractor = MeasurementExtractor()
/// let measurements = extractor.extractAllMeasurements(from: document)
/// for measurement in measurements {
///     print("\(measurement.conceptName): \(measurement.value) \(measurement.unit?.symbol ?? "")")
/// }
/// ```
public struct Measurement: Sendable, Equatable, Hashable {
    /// The concept name describing what is being measured
    public let conceptName: CodedConcept?
    
    /// The primary numeric value
    public let value: Double
    
    /// Additional numeric values (for multi-value measurements)
    public let additionalValues: [Double]
    
    /// The measurement unit
    public let unit: UCUMUnit?
    
    /// The original coded concept for the unit (if not a well-known UCUM unit)
    public let unitConcept: CodedConcept?
    
    /// Optional qualifier for special values (NaN, infinity, etc.)
    public let qualifier: MeasurementQualifier?
    
    /// Derivation method indicating how the measurement was obtained
    public let derivationMethod: DerivationMethod?
    
    /// Observation date/time when the measurement was made
    public let observationDateTime: String?
    
    /// Reference to the source content item (for tracing back to the SR tree)
    public let sourceItem: NumericContentItem?
    
    /// Creates a measurement from a numeric content item
    /// - Parameter item: The numeric content item
    public init(from item: NumericContentItem) {
        self.conceptName = item.conceptName
        self.value = item.numericValues.first ?? 0
        self.additionalValues = Array(item.numericValues.dropFirst())
        
        // Try to resolve unit from measurement units concept
        if let unitsConcept = item.measurementUnits {
            if let ucum = UCUMUnit.wellKnown(code: unitsConcept.codeValue) {
                self.unit = ucum
                self.unitConcept = unitsConcept
            } else {
                self.unit = UCUMUnit(concept: unitsConcept)
                self.unitConcept = unitsConcept
            }
        } else {
            self.unit = nil
            self.unitConcept = nil
        }
        
        // Map qualifier if present
        if let q = item.numericValueQualifier {
            self.qualifier = MeasurementQualifier(from: q)
        } else {
            self.qualifier = nil
        }
        
        self.derivationMethod = nil
        self.observationDateTime = item.observationDateTime
        self.sourceItem = item
    }
    
    /// Creates a measurement with explicit values
    /// - Parameters:
    ///   - conceptName: The concept name
    ///   - value: The numeric value
    ///   - additionalValues: Additional values for multi-value measurements
    ///   - unit: The UCUM unit
    ///   - unitConcept: The original unit concept
    ///   - qualifier: Optional qualifier
    ///   - derivationMethod: How the measurement was obtained
    ///   - observationDateTime: When the measurement was made
    public init(
        conceptName: CodedConcept? = nil,
        value: Double,
        additionalValues: [Double] = [],
        unit: UCUMUnit? = nil,
        unitConcept: CodedConcept? = nil,
        qualifier: MeasurementQualifier? = nil,
        derivationMethod: DerivationMethod? = nil,
        observationDateTime: String? = nil
    ) {
        self.conceptName = conceptName
        self.value = value
        self.additionalValues = additionalValues
        self.unit = unit
        self.unitConcept = unitConcept ?? unit?.concept
        self.qualifier = qualifier
        self.derivationMethod = derivationMethod
        self.observationDateTime = observationDateTime
        self.sourceItem = nil
    }
    
    /// Returns all numeric values including the primary value
    public var allValues: [Double] {
        [value] + additionalValues
    }
    
    /// Indicates whether this is a multi-value measurement
    public var isMultiValue: Bool {
        !additionalValues.isEmpty
    }
    
    /// Converts the measurement to a different unit
    /// - Parameter targetUnit: The target UCUM unit
    /// - Returns: A new measurement with converted value, or nil if conversion is not possible
    public func converted(to targetUnit: UCUMUnit) -> Measurement? {
        guard let currentUnit = unit,
              let convertedValue = currentUnit.convert(value, to: targetUnit) else {
            return nil
        }
        
        let convertedAdditional = additionalValues.compactMap { currentUnit.convert($0, to: targetUnit) }
        guard convertedAdditional.count == additionalValues.count else { return nil }
        
        return Measurement(
            conceptName: conceptName,
            value: convertedValue,
            additionalValues: convertedAdditional,
            unit: targetUnit,
            unitConcept: targetUnit.concept,
            qualifier: qualifier,
            derivationMethod: derivationMethod,
            observationDateTime: observationDateTime
        )
    }
}

// MARK: - MeasurementQualifier

/// Qualifier indicating special measurement values or states
public enum MeasurementQualifier: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Value is not a number (result of division by zero, etc.)
    case notANumber = "NOT A NUMBER"
    
    /// Value is negative infinity
    case negativeInfinity = "NEGATIVE INFINITY"
    
    /// Value is positive infinity
    case positiveInfinity = "POSITIVE INFINITY"
    
    /// Value underflows the representable range
    case underflow = "UNDERFLOW"
    
    /// Value overflows the representable range
    case overflow = "OVERFLOW"

    /// Division by zero
    case divideByZero = "DIVIDE BY ZERO"

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
    
    /// Creates from a NumericValueQualifier (same raw values, PS3.16 CID 42)
    init(from nvq: NumericValueQualifier) {
        self = MeasurementQualifier(rawValue: nvq.rawValue) ?? .valueIndeterminate
    }
}

// MARK: - DerivationMethod

/// Indicates how a measurement was obtained
public enum DerivationMethod: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Measured manually by a user
    case manual = "MANUAL"
    
    /// Automatically measured by software
    case automatic = "AUTOMATIC"
    
    /// Semi-automatic (user-initiated, software-refined)
    case semiAutomatic = "SEMI-AUTOMATIC"
    
    /// Calculated from other measurements
    case calculated = "CALCULATED"
    
    /// Estimated value
    case estimated = "ESTIMATED"
}

// MARK: - MeasurementGroup

/// Groups related measurements together
///
/// A measurement group typically represents measurements that belong together,
/// such as dimensions of a lesion (length, width, depth) or multiple measurements
/// at different time points.
public struct MeasurementGroup: Sendable, Equatable, Hashable {
    /// The concept describing this group
    public let conceptName: CodedConcept?
    
    /// The measurements in this group
    public let measurements: [Measurement]
    
    /// Anatomical location where measurements were taken
    public let anatomicalLocation: CodedConcept?
    
    /// Finding to which these measurements relate
    public let finding: CodedConcept?
    
    /// Reference to the source container
    public let sourceContainer: ContainerContentItem?
    
    /// Creates a measurement group
    /// - Parameters:
    ///   - conceptName: The concept describing this group
    ///   - measurements: The measurements in this group
    ///   - anatomicalLocation: Optional anatomical location
    ///   - finding: Optional finding
    ///   - sourceContainer: Optional source container
    public init(
        conceptName: CodedConcept? = nil,
        measurements: [Measurement],
        anatomicalLocation: CodedConcept? = nil,
        finding: CodedConcept? = nil,
        sourceContainer: ContainerContentItem? = nil
    ) {
        self.conceptName = conceptName
        self.measurements = measurements
        self.anatomicalLocation = anatomicalLocation
        self.finding = finding
        self.sourceContainer = sourceContainer
    }
    
    /// The number of measurements in this group
    public var count: Int {
        measurements.count
    }
    
    /// Returns whether this group is empty
    public var isEmpty: Bool {
        measurements.isEmpty
    }
    
    /// Finds measurements with a specific concept name
    /// - Parameter concept: The concept to search for
    /// - Returns: Array of matching measurements
    public func measurements(forConcept concept: CodedConcept) -> [Measurement] {
        measurements.filter { $0.conceptName == concept }
    }
    
    /// Finds measurements with concept matching a string
    /// - Parameter conceptString: The concept meaning or value to search for
    /// - Returns: Array of matching measurements
    public func measurements(forConceptString conceptString: String) -> [Measurement] {
        measurements.filter { measurement in
            guard let name = measurement.conceptName else { return false }
            return name.codeMeaning == conceptString || name.codeValue == conceptString
        }
    }
    
    /// Gets the first measurement value for a concept
    /// - Parameter concept: The concept to search for
    /// - Returns: The value if found, nil otherwise
    public func value(forConcept concept: CodedConcept) -> Double? {
        measurements(forConcept: concept).first?.value
    }
}

// MARK: - SpatialCoordinates

/// Extracted 2D spatial coordinates with computed properties
///
/// Wraps a SpatialCoordinatesContentItem and provides additional
/// computed properties for geometric analysis.
public struct SpatialCoordinates: Sendable, Equatable, Hashable {
    /// The underlying coordinate data
    public let contentItem: SpatialCoordinatesContentItem
    
    /// Optional reference to the image these coordinates apply to
    public let imageReference: ImageReference?
    
    /// Creates spatial coordinates from a content item
    /// - Parameters:
    ///   - contentItem: The spatial coordinates content item
    ///   - imageReference: Optional image reference
    public init(contentItem: SpatialCoordinatesContentItem, imageReference: ImageReference? = nil) {
        self.contentItem = contentItem
        self.imageReference = imageReference
    }
    
    /// The concept name describing these coordinates
    public var conceptName: CodedConcept? {
        contentItem.conceptName
    }
    
    /// The graphic type
    public var graphicType: GraphicType {
        contentItem.graphicType
    }
    
    /// The raw coordinate data
    public var graphicData: [Float] {
        contentItem.graphicData
    }
    
    /// Returns the coordinates as (column, row) tuples
    public var points: [(column: Float, row: Float)] {
        contentItem.points
    }
    
    /// Number of points in the coordinate data
    public var pointCount: Int {
        contentItem.pointCount
    }
    
    /// Computes the bounding box of the coordinates
    /// - Returns: A tuple of (minColumn, minRow, maxColumn, maxRow), or nil if no points
    public var boundingBox: (minColumn: Float, minRow: Float, maxColumn: Float, maxRow: Float)? {
        guard !points.isEmpty else { return nil }
        
        let columns = points.map { $0.column }
        let rows = points.map { $0.row }
        
        return (
            minColumn: columns.min()!,
            minRow: rows.min()!,
            maxColumn: columns.max()!,
            maxRow: rows.max()!
        )
    }
    
    /// Computes the centroid of the coordinates
    /// - Returns: The centroid as (column, row), or nil if no points
    public var centroid: (column: Float, row: Float)? {
        guard !points.isEmpty else { return nil }
        
        let sumColumn = points.reduce(Float(0)) { $0 + $1.column }
        let sumRow = points.reduce(Float(0)) { $0 + $1.row }
        let count = Float(points.count)
        
        return (column: sumColumn / count, row: sumRow / count)
    }
    
    /// Whether the shape is closed: a POLYLINE whose first and last vertices are the same
    /// (PS3.3 C.18.6.1.2), or the deprecated 2D POLYGON.
    public var isClosed: Bool {
        if graphicType == .polyline, points.count >= 4,
           let first = points.first, let last = points.last {
            return first.column == last.column && first.row == last.row
        }
        return graphicType == .polygon && points.count >= 3
    }

    /// The vertices of a closed shape, without the repeated closing vertex.
    private var closedVertices: [(column: Float, row: Float)] {
        graphicType == .polyline ? Array(points.dropLast()) : points
    }

    /// Computes the perimeter/length of the shape
    /// - Returns: The perimeter for closed shapes, length for open shapes
    public var perimeter: Float {
        guard points.count >= 2 else { return 0 }

        var total: Float = 0
        for i in 0..<(points.count - 1) {
            let dx = points[i + 1].column - points[i].column
            let dy = points[i + 1].row - points[i].row
            total += sqrt(dx * dx + dy * dy)
        }

        // A closed POLYLINE already carries its closing segment; POLYGON does not
        if graphicType == .polygon && points.count >= 3 {
            let dx = points[0].column - points[points.count - 1].column
            let dy = points[0].row - points[points.count - 1].row
            total += sqrt(dx * dx + dy * dy)
        }

        return total
    }

    /// Computes the area of a closed shape using the Shoelace formula
    /// - Returns: The area, or nil if the shape is not closed
    public var area: Float? {
        guard isClosed else { return nil }
        let vertices = closedVertices

        var sum: Float = 0
        for i in 0..<vertices.count {
            let j = (i + 1) % vertices.count
            sum += vertices[i].column * vertices[j].row
            sum -= vertices[j].column * vertices[i].row
        }

        return abs(sum) / 2
    }
    
    /// For CIRCLE type, returns the radius
    /// - Returns: The radius, or nil if not a circle
    public var radius: Float? {
        guard graphicType == .circle && points.count >= 2 else { return nil }
        
        let center = points[0]
        let edge = points[1]
        let dx = edge.column - center.column
        let dy = edge.row - center.row
        
        return sqrt(dx * dx + dy * dy)
    }
    
    /// For CIRCLE type, computes the area
    /// - Returns: The circle area, or nil if not a circle
    public var circleArea: Float? {
        guard let r = radius else { return nil }
        return Float.pi * r * r
    }
    
    /// For ELLIPSE type, computes the area
    /// The four points define the major and minor axes endpoints
    /// - Returns: The ellipse area, or nil if not an ellipse
    public var ellipseArea: Float? {
        guard graphicType == .ellipse && points.count >= 4 else { return nil }
        
        // Compute semi-major and semi-minor axes from the four points
        // Points are: major axis point 1, major axis point 2, minor axis point 1, minor axis point 2
        let dx1 = points[1].column - points[0].column
        let dy1 = points[1].row - points[0].row
        let a = sqrt(dx1 * dx1 + dy1 * dy1) / 2 // semi-major axis
        
        let dx2 = points[3].column - points[2].column
        let dy2 = points[3].row - points[2].row
        let b = sqrt(dx2 * dx2 + dy2 * dy2) / 2 // semi-minor axis
        
        return Float.pi * a * b
    }
}

// MARK: - SpatialCoordinates3D

/// Extracted 3D spatial coordinates with computed properties
public struct SpatialCoordinates3D: Sendable, Equatable, Hashable {
    /// The underlying coordinate data
    public let contentItem: SpatialCoordinates3DContentItem
    
    /// Creates 3D spatial coordinates from a content item
    /// - Parameter contentItem: The 3D spatial coordinates content item
    public init(contentItem: SpatialCoordinates3DContentItem) {
        self.contentItem = contentItem
    }
    
    /// The concept name describing these coordinates
    public var conceptName: CodedConcept? {
        contentItem.conceptName
    }
    
    /// The graphic type
    public var graphicType: GraphicType3D {
        contentItem.graphicType
    }
    
    /// The raw coordinate data
    public var graphicData: [Float] {
        contentItem.graphicData
    }
    
    /// Frame of Reference UID
    public var frameOfReferenceUID: String? {
        contentItem.frameOfReferenceUID
    }
    
    /// Returns the coordinates as (x, y, z) tuples
    public var points: [(x: Float, y: Float, z: Float)] {
        contentItem.points
    }
    
    /// Number of points
    public var pointCount: Int {
        contentItem.pointCount
    }
    
    /// Computes the 3D bounding box
    /// - Returns: A tuple of (minX, minY, minZ, maxX, maxY, maxZ), or nil if no points
    public var boundingBox: (minX: Float, minY: Float, minZ: Float, maxX: Float, maxY: Float, maxZ: Float)? {
        guard !points.isEmpty else { return nil }
        
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        let zs = points.map { $0.z }
        
        return (
            minX: xs.min()!,
            minY: ys.min()!,
            minZ: zs.min()!,
            maxX: xs.max()!,
            maxY: ys.max()!,
            maxZ: zs.max()!
        )
    }
    
    /// Computes the 3D centroid
    /// - Returns: The centroid as (x, y, z), or nil if no points
    public var centroid: (x: Float, y: Float, z: Float)? {
        guard !points.isEmpty else { return nil }
        
        let sumX = points.reduce(Float(0)) { $0 + $1.x }
        let sumY = points.reduce(Float(0)) { $0 + $1.y }
        let sumZ = points.reduce(Float(0)) { $0 + $1.z }
        let count = Float(points.count)
        
        return (x: sumX / count, y: sumY / count, z: sumZ / count)
    }
    
    /// Computes the total path length through all points
    /// - Returns: The path length
    public var pathLength: Float {
        guard points.count >= 2 else { return 0 }
        
        var total: Float = 0
        for i in 0..<(points.count - 1) {
            let dx = points[i + 1].x - points[i].x
            let dy = points[i + 1].y - points[i].y
            let dz = points[i + 1].z - points[i].z
            total += sqrt(dx * dx + dy * dy + dz * dz)
        }
        
        // Close the polygon if it's a polygon type
        if graphicType == .polygon && points.count >= 3 {
            let dx = points[0].x - points[points.count - 1].x
            let dy = points[0].y - points[points.count - 1].y
            let dz = points[0].z - points[points.count - 1].z
            total += sqrt(dx * dx + dy * dy + dz * dz)
        }
        
        return total
    }
}

// MARK: - TemporalCoordinates

/// Extracted temporal coordinates with computed properties
public struct TemporalCoordinates: Sendable, Equatable, Hashable {
    /// The underlying content item
    public let contentItem: TemporalCoordinatesContentItem
    
    /// Creates temporal coordinates from a content item
    /// - Parameter contentItem: The temporal coordinates content item
    public init(contentItem: TemporalCoordinatesContentItem) {
        self.contentItem = contentItem
    }
    
    /// The concept name
    public var conceptName: CodedConcept? {
        contentItem.conceptName
    }
    
    /// The temporal range type
    public var rangeType: TemporalRangeType {
        contentItem.temporalRangeType
    }
    
    /// Sample positions for waveform data
    public var samplePositions: [UInt32]? {
        contentItem.referencedSamplePositions
    }
    
    /// Time offsets in seconds
    public var timeOffsets: [Double]? {
        contentItem.referencedTimeOffsets
    }
    
    /// DateTime values
    public var dateTimes: [String]? {
        contentItem.referencedDateTime
    }
    
    /// Whether this represents a point in time
    public var isPoint: Bool {
        rangeType == .point
    }
    
    /// Whether this represents a range/segment
    public var isRange: Bool {
        rangeType == .segment || rangeType == .beginSegment || rangeType == .endSegment
    }
    
    /// The duration of the temporal range (for time offsets)
    /// - Returns: The duration in seconds, or nil if not applicable
    public var duration: Double? {
        guard let offsets = timeOffsets, offsets.count >= 2 else { return nil }
        guard let min = offsets.min(), let max = offsets.max() else { return nil }
        return max - min
    }
}

// MARK: - ROI (Region of Interest)

/// Represents a Region of Interest combining coordinates with associated measurements
///
/// An ROI typically consists of spatial coordinates defining a region along with
/// measurements taken within or about that region (e.g., a tumor outline with its volume).
public struct ROI: Sendable, Equatable, Hashable {
    /// Unique identifier for this ROI
    public let identifier: String?
    
    /// The concept name describing this ROI
    public let conceptName: CodedConcept?
    
    /// 2D spatial coordinates (if available)
    public let spatialCoordinates: SpatialCoordinates?
    
    /// 3D spatial coordinates (if available)
    public let spatialCoordinates3D: SpatialCoordinates3D?
    
    /// Associated measurements
    public let measurements: [Measurement]
    
    /// Reference to the associated image
    public let imageReference: ImageReference?
    
    /// Anatomical location of the ROI
    public let anatomicalLocation: CodedConcept?
    
    /// Creates an ROI from 2D coordinates
    /// - Parameters:
    ///   - identifier: Optional identifier
    ///   - conceptName: The concept name
    ///   - spatialCoordinates: The 2D coordinates
    ///   - measurements: Associated measurements
    ///   - imageReference: Optional image reference
    ///   - anatomicalLocation: Optional anatomical location
    public init(
        identifier: String? = nil,
        conceptName: CodedConcept? = nil,
        spatialCoordinates: SpatialCoordinates,
        measurements: [Measurement] = [],
        imageReference: ImageReference? = nil,
        anatomicalLocation: CodedConcept? = nil
    ) {
        self.identifier = identifier
        self.conceptName = conceptName
        self.spatialCoordinates = spatialCoordinates
        self.spatialCoordinates3D = nil
        self.measurements = measurements
        self.imageReference = imageReference ?? spatialCoordinates.imageReference
        self.anatomicalLocation = anatomicalLocation
    }
    
    /// Creates an ROI from 3D coordinates
    /// - Parameters:
    ///   - identifier: Optional identifier
    ///   - conceptName: The concept name
    ///   - spatialCoordinates3D: The 3D coordinates
    ///   - measurements: Associated measurements
    ///   - anatomicalLocation: Optional anatomical location
    public init(
        identifier: String? = nil,
        conceptName: CodedConcept? = nil,
        spatialCoordinates3D: SpatialCoordinates3D,
        measurements: [Measurement] = [],
        anatomicalLocation: CodedConcept? = nil
    ) {
        self.identifier = identifier
        self.conceptName = conceptName
        self.spatialCoordinates = nil
        self.spatialCoordinates3D = spatialCoordinates3D
        self.measurements = measurements
        self.imageReference = nil
        self.anatomicalLocation = anatomicalLocation
    }
    
    /// Whether this ROI has 2D coordinates
    public var has2DCoordinates: Bool {
        spatialCoordinates != nil
    }
    
    /// Whether this ROI has 3D coordinates
    public var has3DCoordinates: Bool {
        spatialCoordinates3D != nil
    }
    
    /// The graphic type (from 2D or 3D coordinates)
    public var graphicType: String? {
        if let scoord = spatialCoordinates {
            return scoord.graphicType.rawValue
        }
        if let scoord3d = spatialCoordinates3D {
            return scoord3d.graphicType.rawValue
        }
        return nil
    }
    
    /// The bounding box for 2D coordinates
    public var boundingBox2D: (minColumn: Float, minRow: Float, maxColumn: Float, maxRow: Float)? {
        spatialCoordinates?.boundingBox
    }
    
    /// The bounding box for 3D coordinates
    public var boundingBox3D: (minX: Float, minY: Float, minZ: Float, maxX: Float, maxY: Float, maxZ: Float)? {
        spatialCoordinates3D?.boundingBox
    }
    
    /// The centroid (2D)
    public var centroid2D: (column: Float, row: Float)? {
        spatialCoordinates?.centroid
    }
    
    /// The centroid (3D)
    public var centroid3D: (x: Float, y: Float, z: Float)? {
        spatialCoordinates3D?.centroid
    }
    
    /// The area (for 2D polygon, circle, or ellipse)
    public var area: Float? {
        guard let scoord = spatialCoordinates else { return nil }
        return scoord.area ?? scoord.circleArea ?? scoord.ellipseArea
    }
    
    /// The perimeter (for 2D coordinates)
    public var perimeter: Float? {
        spatialCoordinates?.perimeter
    }
}

// MARK: - MeasurementExtractor

/// Extracts measurements and coordinates from SR documents
///
/// The MeasurementExtractor provides a high-level API for extracting quantitative data
/// from DICOM Structured Reports, including numeric measurements, spatial coordinates,
/// temporal coordinates, and regions of interest.
///
/// Example:
/// ```swift
/// let extractor = MeasurementExtractor()
/// let measurements = extractor.extractAllMeasurements(from: document)
/// let rois = extractor.extractROIs(from: document)
/// ```
public struct MeasurementExtractor: Sendable {
    /// Creates a new measurement extractor
    public init() {}
    
    // MARK: - Measurement Extraction
    
    /// Extracts all measurements from an SR document
    /// - Parameter document: The SR document
    /// - Returns: Array of extracted measurements
    public func extractAllMeasurements(from document: SRDocument) -> [Measurement] {
        document.findAllMeasurements().map { Measurement(from: $0) }
    }
    
    /// Extracts measurements for a specific concept
    /// - Parameters:
    ///   - concept: The concept to search for
    ///   - document: The SR document
    /// - Returns: Array of measurements with matching concept
    public func extractMeasurements(forConcept concept: CodedConcept, from document: SRDocument) -> [Measurement] {
        document.findMeasurements(forConcept: concept).map { Measurement(from: $0) }
    }
    
    /// Extracts measurements for a concept string
    /// - Parameters:
    ///   - conceptString: The concept meaning or value to search for
    ///   - document: The SR document
    /// - Returns: Array of measurements with matching concept
    public func extractMeasurements(forConceptString conceptString: String, from document: SRDocument) -> [Measurement] {
        document.findMeasurements(forConceptString: conceptString).map { Measurement(from: $0) }
    }
    
    /// Extracts measurement groups from an SR document
    /// - Parameter document: The SR document
    /// - Returns: Array of measurement groups
    public func extractMeasurementGroups(from document: SRDocument) -> [MeasurementGroup] {
        document.findMeasurementGroups().map { container in
            let measurements = container.findMeasurements().map { Measurement(from: $0) }
            return MeasurementGroup(
                conceptName: container.conceptName,
                measurements: measurements,
                sourceContainer: container
            )
        }
    }
    
    // MARK: - Coordinate Extraction
    
    /// Extracts all 2D spatial coordinates from an SR document
    /// - Parameter document: The SR document
    /// - Returns: Array of spatial coordinates
    public func extractSpatialCoordinates(from document: SRDocument) -> [SpatialCoordinates] {
        document.findSpatialCoordinateItems().map { item in
            // Try to find associated image reference
            let imageRef = findImageReference(near: item, in: document)
            return SpatialCoordinates(contentItem: item, imageReference: imageRef)
        }
    }
    
    /// Extracts all 3D spatial coordinates from an SR document
    /// - Parameter document: The SR document
    /// - Returns: Array of 3D spatial coordinates
    public func extractSpatialCoordinates3D(from document: SRDocument) -> [SpatialCoordinates3D] {
        document.allContentItems.compactMap { $0.asSpatialCoordinates3D }.map { SpatialCoordinates3D(contentItem: $0) }
    }
    
    /// Extracts all temporal coordinates from an SR document
    /// - Parameter document: The SR document
    /// - Returns: Array of temporal coordinates
    public func extractTemporalCoordinates(from document: SRDocument) -> [TemporalCoordinates] {
        document.allContentItems.compactMap { $0.asTemporalCoordinates }.map { TemporalCoordinates(contentItem: $0) }
    }
    
    // MARK: - ROI Extraction
    
    /// Extracts all regions of interest from an SR document
    /// - Parameter document: The SR document
    /// - Returns: Array of ROIs
    public func extractROIs(from document: SRDocument) -> [ROI] {
        var rois: [ROI] = []
        
        // Find containers that have spatial coordinates
        for container in document.findContainerItems() {
            // Look for SCOORD or SCOORD3D children with associated measurements
            let scoordItems = container.contentItems.compactMap { $0.asSpatialCoordinates }
            let scoord3DItems = container.contentItems.compactMap { $0.asSpatialCoordinates3D }
            let numericItems = container.contentItems.compactMap { $0.asNumeric }
            let imageItems = container.contentItems.compactMap { $0.asImage }
            
            // Create ROIs from 2D coordinates
            for item in scoordItems {
                let imageRef = selectedFromImage(of: item) ?? imageItems.first?.imageReference
                let measurements = numericItems.map { Measurement(from: $0) }
                let roi = ROI(
                    conceptName: container.conceptName ?? item.conceptName,
                    spatialCoordinates: SpatialCoordinates(contentItem: item, imageReference: imageRef),
                    measurements: measurements,
                    imageReference: imageRef
                )
                rois.append(roi)
            }
            
            // Create ROIs from 3D coordinates
            for item in scoord3DItems {
                let measurements = numericItems.map { Measurement(from: $0) }
                let roi = ROI(
                    conceptName: container.conceptName ?? item.conceptName,
                    spatialCoordinates3D: SpatialCoordinates3D(contentItem: item),
                    measurements: measurements
                )
                rois.append(roi)
            }
        }
        
        // A NUM INFERRED FROM a SCOORD in its Content Sequence (PS3.16 TID 300 row 1b →
        // TID 301 row 13 → TID 320 row 3): the SCOORD is the region the value was measured on
        for numeric in document.findNumericItems() {
            for child in numeric.contentItems where child.relationshipType == .inferredFrom {
                guard let scoord = child.asSpatialCoordinates,
                      !rois.contains(where: { $0.spatialCoordinates?.contentItem == scoord }) else { continue }
                let imageRef = selectedFromImage(of: scoord)
                rois.append(ROI(
                    conceptName: numeric.conceptName ?? scoord.conceptName,
                    spatialCoordinates: SpatialCoordinates(contentItem: scoord, imageReference: imageRef),
                    measurements: [Measurement(from: numeric)],
                    imageReference: imageRef
                ))
            }
        }

        // Also check for standalone SCOORD items that might be ROIs
        let standaloneScoords = document.findSpatialCoordinateItems()
        for item in standaloneScoords {
            // Skip if already captured in a container-based ROI
            if !rois.contains(where: { $0.spatialCoordinates?.contentItem == item }) {
                let imageRef = findImageReference(near: item, in: document)
                let roi = ROI(
                    conceptName: item.conceptName,
                    spatialCoordinates: SpatialCoordinates(contentItem: item, imageReference: imageRef),
                    measurements: []
                )
                rois.append(roi)
            }
        }
        
        return rois
    }
    
    // MARK: - Aggregation
    
    /// Groups measurements by their concept name
    ///
    /// This is a simplified grouping that uses the measurement's concept name as the key.
    /// For true anatomical location-based grouping, you would need to traverse the SR tree
    /// to find the anatomical location context associated with each measurement.
    ///
    /// - Parameter measurements: The measurements to group
    /// - Returns: Dictionary mapping concept to measurements
    /// - Note: This groups by concept name, not by anatomical location context.
    ///         Future versions may add support for SR tree traversal to find location context.
    public func groupByLocation(_ measurements: [Measurement]) -> [CodedConcept: [Measurement]] {
        var result: [CodedConcept: [Measurement]] = [:]
        for measurement in measurements {
            if let concept = measurement.conceptName {
                result[concept, default: []].append(measurement)
            }
        }
        return result
    }
    
    /// Computes statistics for a set of measurements
    /// - Parameter measurements: The measurements to analyze
    /// - Returns: Statistics including mean, min, max, std dev
    public func computeStatistics(_ measurements: [Measurement]) -> MeasurementStatistics? {
        guard !measurements.isEmpty else { return nil }
        
        let values = measurements.map { $0.value }
        let count = Double(values.count)
        let sum = values.reduce(0, +)
        let mean = sum / count
        
        let min = values.min()!
        let max = values.max()!
        
        let squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
        let variance = squaredDiffs.reduce(0, +) / count
        let stdDev = sqrt(variance)
        
        return MeasurementStatistics(
            count: values.count,
            mean: mean,
            min: min,
            max: max,
            standardDeviation: stdDev,
            sum: sum
        )
    }
    
    // MARK: - Private Helpers
    
    /// Tries to find an image reference associated with a spatial coordinate item
    private func findImageReference(near item: SpatialCoordinatesContentItem, in document: SRDocument) -> ImageReference? {
        // The IMAGE the SCOORD is SELECTED FROM, when nested under it; otherwise the first
        // IMAGE of the document (a simplified fallback that does not traverse the parent chain)
        if let selected = selectedFromImage(of: item) { return selected }
        let imageItems = document.findImageItems()
        return imageItems.first?.imageReference
    }

    /// The IMAGE a SCOORD is SELECTED FROM: a child in its Content Sequence (PS3.3 Table
    /// C.17-6; PS3.16 TID 320 row 4, TID 1501 row 10d, TID 4021/4107 row 2)
    private func selectedFromImage(of item: SpatialCoordinatesContentItem) -> ImageReference? {
        item.contentItems.lazy
            .filter { $0.relationshipType == .selectedFrom }
            .compactMap { $0.asImage?.imageReference }
            .first
    }
}

// MARK: - MeasurementStatistics

/// Statistical summary of a set of measurements
public struct MeasurementStatistics: Sendable, Equatable {
    /// Number of measurements
    public let count: Int
    
    /// Mean value
    public let mean: Double
    
    /// Minimum value
    public let min: Double
    
    /// Maximum value
    public let max: Double
    
    /// Standard deviation
    public let standardDeviation: Double
    
    /// Sum of all values
    public let sum: Double
    
    /// Range (max - min)
    public var range: Double {
        max - min
    }
}

// MARK: - CustomStringConvertible Extensions

extension Measurement: CustomStringConvertible {
    public var description: String {
        let conceptStr = conceptName?.codeMeaning ?? "unnamed"
        let unitStr = unit?.symbol ?? unitConcept?.codeValue ?? ""
        if unitStr.isEmpty {
            return "\(conceptStr): \(value)"
        } else {
            return "\(conceptStr): \(value) \(unitStr)"
        }
    }
}

extension MeasurementGroup: CustomStringConvertible {
    public var description: String {
        let conceptStr = conceptName?.codeMeaning ?? "unnamed group"
        return "\(conceptStr) (\(measurements.count) measurements)"
    }
}

extension ROI: CustomStringConvertible {
    public var description: String {
        let conceptStr = conceptName?.codeMeaning ?? "unnamed"
        let coordType = has2DCoordinates ? "2D" : (has3DCoordinates ? "3D" : "no coords")
        return "ROI: \(conceptStr) [\(coordType), \(measurements.count) measurements]"
    }
}
