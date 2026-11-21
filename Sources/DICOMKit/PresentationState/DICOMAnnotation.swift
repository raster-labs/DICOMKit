// NEMA-verified: 2026a, checked 2026-11-16 — PS3.3 2026a Table C.10-5 (Graphic Annotation Module), Table C.10-5a (Text Style Sequence), Table C.10-5b (Line Style Sequence), Table C.10-5c (Fill Style Sequence), Table C.10-7 (Graphic Layer Module), and C.10.5.1.3.1 (Compound Graphic Sequence alternate rendering requirement)
//
// DICOMAnnotation.swift
// DICOMKit
//
// High-level, DICOM-standard-conformant Annotation & Measurement API for
// Grayscale (GSPS), Color (CSPS), and Pseudo-Color (Pseudo-CSPS) Presentation States
// (PS3.3 Section C.10.5 Graphic Annotation Module & C.10.7 Graphic Layer Module).
//

import Foundation
import DICOMCore

/// Coordinate system used when specifying points on a `DICOMAnnotation`.
public enum DICOMAnnotationCoordinateSpace: String, Sendable, Hashable, Codable {
    /// Image pixel coordinates (`0...columns`, `0...rows`, PS3.3 Table C.10-5 `PIXEL`).
    case pixel
    /// Image-normalized coordinates (`0.0...1.0` across width and height).
    case normalized
}

/// 2D point in either pixel or normalized coordinate space.
public struct DICOMAnnotationPoint: Sendable, Hashable, Codable {
    /// Horizontal coordinate (column in pixel space, or 0...1 in normalized space).
    public var x: Double
    /// Vertical coordinate (row in pixel space, or 0...1 in normalized space).
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Converts this point to pixel coordinates `(column, row)` given image dimensions.
    public func toPixel(space: DICOMAnnotationCoordinateSpace, imageWidth: Int, imageHeight: Int) -> (column: Double, row: Double) {
        switch space {
        case .pixel:
            return (column: x, row: y)
        case .normalized:
            return (column: x * Double(imageWidth), row: y * Double(imageHeight))
        }
    }

    /// Creates a point from pixel coordinates `(column, row)`.
    public static func fromPixel(
        column: Double,
        row: Double,
        targetSpace: DICOMAnnotationCoordinateSpace,
        imageWidth: Int,
        imageHeight: Int
    ) -> DICOMAnnotationPoint {
        switch targetSpace {
        case .pixel:
            return DICOMAnnotationPoint(x: column, y: row)
        case .normalized:
            let w = max(1.0, Double(imageWidth))
            let h = max(1.0, Double(imageHeight))
            return DICOMAnnotationPoint(x: column / w, y: row / h)
        }
    }
}

/// sRGB color for an annotation (`0.0...1.0` per component), automatically converted to
/// DICOM PCS-Value CIELab (`(0070,0401)` / `(0070,0241)` / `(0070,0251)`) per PS3.3 C.10.7.1.1.
public struct DICOMAnnotationColor: Sendable, Hashable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
        self.opacity = min(1, max(0, opacity))
    }

    public static let yellow = DICOMAnnotationColor(red: 1.0, green: 0.92, blue: 0.23)
    public static let white  = DICOMAnnotationColor(red: 1.0, green: 1.0, blue: 1.0)
    public static let red    = DICOMAnnotationColor(red: 0.96, green: 0.26, blue: 0.21)
    public static let green  = DICOMAnnotationColor(red: 0.30, green: 0.85, blue: 0.39)
    public static let cyan    = DICOMAnnotationColor(red: 0.0, green: 0.84, blue: 1.0)
    public static let orange  = DICOMAnnotationColor(red: 1.0, green: 0.60, blue: 0.0)
    public static let magenta = DICOMAnnotationColor(red: 0.91, green: 0.12, blue: 0.39)

    /// Relative luminance for automatic halo/shadow contrast selection.
    public var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// Converts to DICOM `CIELabColor` (PS3.3 C.10.7.1.1).
    public var cieLab: CIELabColor {
        CIELabColor(sRGBRed: red, green: green, blue: blue)
    }

    /// Initializes from a DICOM `CIELabColor`.
    public init(cieLab: CIELabColor, opacity: Double = 1.0) {
        let rgb = cieLab.sRGB
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }
}

/// Quantitative measurement attached to a `DICOMAnnotation` (used both for text labels in PR
/// and for `NUM` + `SCOORD` items in DICOM SR / TID 1500 Measurement Reports).
public struct DICOMAnnotationMeasurement: Sendable, Hashable, Codable {
    /// Concept name of the measurement (e.g., Length, Area, Mean, Standard Deviation, Angle).
    public var concept: CodedConcept
    /// Numeric measurement value.
    public var value: Double
    /// Measurement units (UCUM coded concept, e.g., `mm`, `cm2`, `deg`, `HU`).
    public var units: CodedConcept

    public init(concept: CodedConcept, value: Double, units: CodedConcept) {
        self.concept = concept
        self.value = value
        self.units = units
    }

    // MARK: - Standard Measurement Factories (SNOMED-CT / DCM + UCUM)

    /// Linear distance / length measurement in millimeters.
    public static func lengthMM(_ value: Double) -> DICOMAnnotationMeasurement {
        DICOMAnnotationMeasurement(
            concept: CodedConcept(codeValue: "410668003", codingSchemeDesignator: "SCT", codeMeaning: "Length"),
            value: value,
            units: CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "millimeter")
        )
    }

    /// Area measurement in square millimeters.
    public static func areaMM2(_ value: Double) -> DICOMAnnotationMeasurement {
        DICOMAnnotationMeasurement(
            concept: CodedConcept(codeValue: "42798000", codingSchemeDesignator: "SCT", codeMeaning: "Area"),
            value: value,
            units: CodedConcept(codeValue: "mm2", codingSchemeDesignator: "UCUM", codeMeaning: "square millimeter")
        )
    }

    /// Angle measurement in degrees.
    public static func angleDegrees(_ value: Double) -> DICOMAnnotationMeasurement {
        DICOMAnnotationMeasurement(
            concept: CodedConcept(codeValue: "1483009", codingSchemeDesignator: "SCT", codeMeaning: "Angle"),
            value: value,
            units: CodedConcept(codeValue: "deg", codingSchemeDesignator: "UCUM", codeMeaning: "degree")
        )
    }

    /// Mean pixel/attenuation value (e.g., in Hounsfield Units).
    public static func meanHU(_ value: Double) -> DICOMAnnotationMeasurement {
        DICOMAnnotationMeasurement(
            concept: CodedConcept(codeValue: "373098007", codingSchemeDesignator: "SCT", codeMeaning: "Mean Value"),
            value: value,
            units: CodedConcept(codeValue: "[hnsf'U]", codingSchemeDesignator: "UCUM", codeMeaning: "Hounsfield unit")
        )
    }

    /// Standard deviation in Hounsfield Units.
    public static func standardDeviationHU(_ value: Double) -> DICOMAnnotationMeasurement {
        DICOMAnnotationMeasurement(
            concept: CodedConcept(codeValue: "386136009", codingSchemeDesignator: "SCT", codeMeaning: "Standard Deviation"),
            value: value,
            units: CodedConcept(codeValue: "[hnsf'U]", codingSchemeDesignator: "UCUM", codeMeaning: "Hounsfield unit")
        )
    }

    /// Formatted human-readable measurement string (e.g., `"24.5 mm"`).
    public var formattedString: String {
        let formattedValue = String(format: "%.2f", value)
        let unitLabel: String
        switch units.codeValue {
        case "[hnsf'U]": unitLabel = "HU"
        case "deg": unitLabel = "°"
        case "mm2": unitLabel = "mm²"
        case "cm2": unitLabel = "cm²"
        default: unitLabel = units.codeValue
        }
        return "\(formattedValue) \(unitLabel)"
    }
}

/// Kind of high-level DICOM annotation.
public enum DICOMAnnotationKind: String, Sendable, Hashable, CaseIterable, Codable {
    /// Unanchored text label (`TextObject` in `TextObjectSequence`).
    case text
    /// Arrow pointing from `points[0]` (tail) to `points[1]` (head/anchor)
    /// (`CompoundGraphic` `ARROW` + fallback `POLYLINE` shaft & head).
    case arrow
    /// Text callout with a visible leader line from the text box (`points[0]`) to the anchor (`points[1]`).
    case annotation
    /// Distance ruler between `points[0]` and `points[1]`
    /// (`CompoundGraphic` `RULER` + fallback `POLYLINE` + optional distance `TextObject`).
    case ruler
    /// Angle measurement defined by 3 points (`points[0]` -> vertex `points[1]` -> `points[2]`).
    case angle
    /// Axis-aligned or bounding rectangle between `points[0]` (top-left) and `points[1]` (bottom-right)
    /// (`CompoundGraphic` `RECTANGLE` + closed 5-point `POLYLINE` fallback).
    case rectangle
    /// Ellipse defined either by 2 bounding-box corners (`points[0]`, `points[1]`) or 4 axis endpoints
    /// (`GraphicObject` `ELLIPSE` with 4 major/minor axis points per PS3.3 C.10.5.1.2).
    case ellipse
    /// Circle defined by center (`points[0]`) and a point on the perimeter (`points[1]`)
    /// (`GraphicObject` `CIRCLE`).
    case circle
    /// Open or closed polyline / freehand ROI (`GraphicObject` `POLYLINE` or `INTERPOLATED`).
    case polyline
    /// Crosshair marker at `points[0]` (`CompoundGraphic` `CROSSHAIR` + 2 intersecting `POLYLINE` segments).
    case crosshair
    /// Single point marker at `points[0]` (`GraphicObject` `POINT`).
    case point
}

/// High-level, DICOM-standard-conformant annotation and ROI measurement model.
///
/// Can be serialized directly into:
/// - **Presentation State (PR)**: GSPS (`1.2.840.10008.5.1.4.1.1.11.1`), CSPS (`.11.2`), or Pseudo-CSPS (`.11.3`)
///   via `DICOMAnnotationConverter` / `PresentationStateManager`.
/// - **Structured Reporting (SR)**: TID 1500 Measurement Report, Comprehensive SR, or Key Object Selection
///   via `PresentationStateSRBridge`.
public struct DICOMAnnotation: Sendable, Hashable, Identifiable, Codable {
    /// Unique identifier for UI selection and tracking.
    public var id: UUID
    /// Annotation geometry/object kind.
    public var kind: DICOMAnnotationKind
    /// Coordinate space of `points` (`.pixel` or `.normalized`).
    public var coordinateSpace: DICOMAnnotationCoordinateSpace
    /// Defining points of the annotation.
    public var points: [DICOMAnnotationPoint]
    /// Text label or callout content (for `.text`, `.annotation`, `.ruler`, `.angle`, or ROI labels).
    public var text: String
    /// Stroke and text color.
    public var color: DICOMAnnotationColor
    /// Whether closed shapes (`.rectangle`, `.ellipse`, `.circle`, closed `.polyline`) are filled.
    public var filled: Bool
    /// Line thickness in pixels.
    public var lineThickness: Double
    /// Whether the line is dashed (`DASHED` vs `SOLID` in `LineStyleSequence`).
    public var isDashed: Bool
    /// Relative text/arrow scale factor (fraction of image height, default `0.028`).
    public var scale: Double
    /// Graphic layer name (`GraphicLayer (0070,0002)`), default `"ANNOTATIONS"`.
    public var layerName: String
    /// Optional target image SOP Class UID (when scoping inside a multi-image series PR).
    public var referencedSOPClassUID: String?
    /// Optional target image SOP Instance UID (when scoping inside a multi-image series PR).
    public var referencedSOPInstanceUID: String?
    /// Optional 1-based DICOM frame numbers (`ReferencedFrameNumber (0008,1160)`).
    /// `nil` or empty applies to all frames of the referenced image.
    public var referencedFrameNumbers: [Int]?
    /// Quantitative measurements associated with this annotation (e.g., length, area, mean HU, angle).
    public var measurements: [DICOMAnnotationMeasurement]
    /// Optional tracking identifier for TID 1500 planar ROI measurements.
    public var trackingIdentifier: String?
    /// Optional tracking UID for TID 1500 planar ROI measurements.
    public var trackingUID: String?

    public static let defaultLayerName = "ANNOTATIONS"
    public static let defaultScale: Double = 0.028

    public init(
        id: UUID = UUID(),
        kind: DICOMAnnotationKind,
        coordinateSpace: DICOMAnnotationCoordinateSpace = .pixel,
        points: [DICOMAnnotationPoint],
        text: String = "",
        color: DICOMAnnotationColor = .yellow,
        filled: Bool = false,
        lineThickness: Double = 2.0,
        isDashed: Bool = false,
        scale: Double = DICOMAnnotation.defaultScale,
        layerName: String = DICOMAnnotation.defaultLayerName,
        referencedSOPClassUID: String? = nil,
        referencedSOPInstanceUID: String? = nil,
        referencedFrameNumbers: [Int]? = nil,
        measurements: [DICOMAnnotationMeasurement] = [],
        trackingIdentifier: String? = nil,
        trackingUID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.coordinateSpace = coordinateSpace
        self.points = points
        self.text = text
        self.color = color
        self.filled = filled
        self.lineThickness = max(0.5, lineThickness)
        self.isDashed = isDashed
        self.scale = max(0.008, min(0.25, scale))
        self.layerName = layerName.isEmpty ? Self.defaultLayerName : layerName
        self.referencedSOPClassUID = referencedSOPClassUID
        self.referencedSOPInstanceUID = referencedSOPInstanceUID
        self.referencedFrameNumbers = referencedFrameNumbers
        self.measurements = measurements
        self.trackingIdentifier = trackingIdentifier
        self.trackingUID = trackingUID
    }

    /// Returns `true` when this annotation applies to the given image SOP Instance UID and optional 1-based frame number.
    public func appliesTo(sopInstanceUID: String?, frameNumber: Int? = nil) -> Bool {
        if let targetUID = referencedSOPInstanceUID, !targetUID.isEmpty {
            guard let sopInstanceUID, targetUID == sopInstanceUID else {
                return false
            }
        }
        if let targetFrames = referencedFrameNumbers, !targetFrames.isEmpty, let frameNumber {
            return targetFrames.contains(frameNumber)
        }
        return true
    }

    // MARK: - Convenience Initializers

    /// Creates a text annotation at `position`.
    public static func text(
        _ text: String,
        at position: DICOMAnnotationPoint,
        coordinateSpace: DICOMAnnotationCoordinateSpace = .pixel,
        color: DICOMAnnotationColor = .yellow,
        referencedSOPClassUID: String? = nil,
        referencedSOPInstanceUID: String? = nil,
        referencedFrameNumbers: [Int]? = nil
    ) -> DICOMAnnotation {
        DICOMAnnotation(
            kind: .text,
            coordinateSpace: coordinateSpace,
            points: [position],
            text: text,
            color: color,
            referencedSOPClassUID: referencedSOPClassUID,
            referencedSOPInstanceUID: referencedSOPInstanceUID,
            referencedFrameNumbers: referencedFrameNumbers
        )
    }

    /// Creates an arrow annotation from `tail` to `head`, with optional callout `text`.
    public static func arrow(
        from tail: DICOMAnnotationPoint,
        to head: DICOMAnnotationPoint,
        text: String = "",
        coordinateSpace: DICOMAnnotationCoordinateSpace = .pixel,
        color: DICOMAnnotationColor = .yellow,
        referencedSOPClassUID: String? = nil,
        referencedSOPInstanceUID: String? = nil,
        referencedFrameNumbers: [Int]? = nil
    ) -> DICOMAnnotation {
        DICOMAnnotation(
            kind: text.isEmpty ? .arrow : .annotation,
            coordinateSpace: coordinateSpace,
            points: [tail, head],
            text: text,
            color: color,
            referencedSOPClassUID: referencedSOPClassUID,
            referencedSOPInstanceUID: referencedSOPInstanceUID,
            referencedFrameNumbers: referencedFrameNumbers
        )
    }

    /// Creates a distance ruler annotation between `start` and `end`.
    public static func ruler(
        from start: DICOMAnnotationPoint,
        to end: DICOMAnnotationPoint,
        distanceMM: Double? = nil,
        coordinateSpace: DICOMAnnotationCoordinateSpace = .pixel,
        color: DICOMAnnotationColor = .yellow,
        referencedSOPClassUID: String? = nil,
        referencedSOPInstanceUID: String? = nil,
        referencedFrameNumbers: [Int]? = nil
    ) -> DICOMAnnotation {
        let measurements = distanceMM.map { [DICOMAnnotationMeasurement.lengthMM($0)] } ?? []
        let label = measurements.first?.formattedString ?? ""
        return DICOMAnnotation(
            kind: .ruler,
            coordinateSpace: coordinateSpace,
            points: [start, end],
            text: label,
            color: color,
            referencedSOPClassUID: referencedSOPClassUID,
            referencedSOPInstanceUID: referencedSOPInstanceUID,
            referencedFrameNumbers: referencedFrameNumbers,
            measurements: measurements
        )
    }

    /// Creates an angle measurement annotation defined by `start`, `vertex`, and `end`.
    public static func angle(
        start: DICOMAnnotationPoint,
        vertex: DICOMAnnotationPoint,
        end: DICOMAnnotationPoint,
        degrees: Double? = nil,
        coordinateSpace: DICOMAnnotationCoordinateSpace = .pixel,
        color: DICOMAnnotationColor = .yellow,
        referencedSOPClassUID: String? = nil,
        referencedSOPInstanceUID: String? = nil,
        referencedFrameNumbers: [Int]? = nil
    ) -> DICOMAnnotation {
        let measurements = degrees.map { [DICOMAnnotationMeasurement.angleDegrees($0)] } ?? []
        let label = measurements.first?.formattedString ?? ""
        return DICOMAnnotation(
            kind: .angle,
            coordinateSpace: coordinateSpace,
            points: [start, vertex, end],
            text: label,
            color: color,
            referencedSOPClassUID: referencedSOPClassUID,
            referencedSOPInstanceUID: referencedSOPInstanceUID,
            referencedFrameNumbers: referencedFrameNumbers,
            measurements: measurements
        )
    }

    /// Creates a rectangle ROI annotation between `topLeft` and `bottomRight`.
    public static func rectangle(
        topLeft: DICOMAnnotationPoint,
        bottomRight: DICOMAnnotationPoint,
        filled: Bool = false,
        coordinateSpace: DICOMAnnotationCoordinateSpace = .pixel,
        color: DICOMAnnotationColor = .yellow,
        measurements: [DICOMAnnotationMeasurement] = [],
        referencedSOPClassUID: String? = nil,
        referencedSOPInstanceUID: String? = nil,
        referencedFrameNumbers: [Int]? = nil
    ) -> DICOMAnnotation {
        DICOMAnnotation(
            kind: .rectangle,
            coordinateSpace: coordinateSpace,
            points: [topLeft, bottomRight],
            text: measurements.map(\.formattedString).joined(separator: " | "),
            color: color,
            filled: filled,
            referencedSOPClassUID: referencedSOPClassUID,
            referencedSOPInstanceUID: referencedSOPInstanceUID,
            referencedFrameNumbers: referencedFrameNumbers,
            measurements: measurements
        )
    }

    /// Creates an ellipse ROI annotation from bounding box corners `topLeft` and `bottomRight`.
    public static func ellipse(
        topLeft: DICOMAnnotationPoint,
        bottomRight: DICOMAnnotationPoint,
        filled: Bool = false,
        coordinateSpace: DICOMAnnotationCoordinateSpace = .pixel,
        color: DICOMAnnotationColor = .yellow,
        measurements: [DICOMAnnotationMeasurement] = [],
        referencedSOPClassUID: String? = nil,
        referencedSOPInstanceUID: String? = nil,
        referencedFrameNumbers: [Int]? = nil
    ) -> DICOMAnnotation {
        DICOMAnnotation(
            kind: .ellipse,
            coordinateSpace: coordinateSpace,
            points: [topLeft, bottomRight],
            text: measurements.map(\.formattedString).joined(separator: " | "),
            color: color,
            filled: filled,
            referencedSOPClassUID: referencedSOPClassUID,
            referencedSOPInstanceUID: referencedSOPInstanceUID,
            referencedFrameNumbers: referencedFrameNumbers,
            measurements: measurements
        )
    }

    /// Creates a circle ROI annotation from `center` and `perimeterPoint`.
    public static func circle(
        center: DICOMAnnotationPoint,
        perimeterPoint: DICOMAnnotationPoint,
        filled: Bool = false,
        coordinateSpace: DICOMAnnotationCoordinateSpace = .pixel,
        color: DICOMAnnotationColor = .yellow,
        measurements: [DICOMAnnotationMeasurement] = [],
        referencedSOPClassUID: String? = nil,
        referencedSOPInstanceUID: String? = nil,
        referencedFrameNumbers: [Int]? = nil
    ) -> DICOMAnnotation {
        DICOMAnnotation(
            kind: .circle,
            coordinateSpace: coordinateSpace,
            points: [center, perimeterPoint],
            text: measurements.map(\.formattedString).joined(separator: " | "),
            color: color,
            filled: filled,
            referencedSOPClassUID: referencedSOPClassUID,
            referencedSOPInstanceUID: referencedSOPInstanceUID,
            referencedFrameNumbers: referencedFrameNumbers,
            measurements: measurements
        )
    }
}

// MARK: - Bidirectional Converter (DICOMAnnotation <-> GraphicLayer & GraphicAnnotation)

/// Converts high-level `DICOMAnnotation` objects to and from DICOM PS3.3 C.10.5 `GraphicAnnotation`
/// and C.10.7 `GraphicLayer` sequences for GSPS, CSPS, and Pseudo-CSPS.
public enum DICOMAnnotationConverter {

    /// Builds `GraphicLayer` items required for the given annotations (PS3.3 Section C.10.7).
    public static func graphicLayers(for annotations: [DICOMAnnotation]) -> [GraphicLayer] {
        var seenLayers: [String: DICOMAnnotationColor] = [:]
        var orderedNames: [String] = []
        for annotation in annotations {
            let name = annotation.layerName.isEmpty ? DICOMAnnotation.defaultLayerName : annotation.layerName
            if seenLayers[name] == nil {
                seenLayers[name] = annotation.color
                orderedNames.append(name)
            }
        }
        return orderedNames.enumerated().map { index, name in
            let color = seenLayers[name] ?? .yellow
            return GraphicLayer(
                name: name,
                order: index + 1,
                description: "DICOMKit Graphic Annotations",
                recommendedRGBValue: (
                    red: Int((color.red * 65535).rounded()),
                    green: Int((color.green * 65535).rounded()),
                    blue: Int((color.blue * 65535).rounded())
                )
            )
        }
    }

    /// Converts high-level `[DICOMAnnotation]` into DICOM `GraphicAnnotation` items (PS3.3 Table C.10-5),
    /// preserving per-image and per-frame scoping (`ReferencedImageSequence` and `ReferencedFrameNumber`).
    ///
    /// - Parameters:
    ///   - annotations: High-level annotations to convert.
    ///   - defaultReferencedImages: Default image references used when an annotation does not specify its own `referencedSOPInstanceUID`.
    ///   - imageWidth: Columns of the referenced image (used when converting `.normalized` coordinates).
    ///   - imageHeight: Rows of the referenced image (used when converting `.normalized` coordinates).
    /// - Returns: Conformant `[GraphicAnnotation]` items with unique `CompoundGraphicInstanceID` values.
    public static func graphicAnnotations(
        from annotations: [DICOMAnnotation],
        defaultReferencedImages: [ReferencedImage],
        imageWidth: Int,
        imageHeight: Int
    ) -> [GraphicAnnotation] {
        guard !annotations.isEmpty, imageWidth > 0, imageHeight > 0 else { return [] }

        struct ScopeKey: Hashable {
            let layer: String
            let referencedImages: [ReferencedImage]
        }

        let defaultClassUID = defaultReferencedImages.first?.sopClassUID ?? "1.2.840.10008.5.1.4.1.1.2"
        var grouped: [ScopeKey: [DICOMAnnotation]] = [:]
        var keyOrder: [ScopeKey] = []

        for annotation in annotations {
            let refs: [ReferencedImage]
            if let sopInstanceUID = annotation.referencedSOPInstanceUID {
                let sopClassUID = annotation.referencedSOPClassUID ?? defaultClassUID
                refs = [ReferencedImage(
                    sopClassUID: sopClassUID,
                    sopInstanceUID: sopInstanceUID,
                    referencedFrameNumbers: annotation.referencedFrameNumbers
                )]
            } else if let frameNumbers = annotation.referencedFrameNumbers, !frameNumbers.isEmpty {
                refs = defaultReferencedImages.map {
                    ReferencedImage(
                        sopClassUID: $0.sopClassUID,
                        sopInstanceUID: $0.sopInstanceUID,
                        referencedFrameNumbers: frameNumbers
                    )
                }
            } else {
                refs = defaultReferencedImages
            }

            let key = ScopeKey(
                layer: annotation.layerName.isEmpty ? DICOMAnnotation.defaultLayerName : annotation.layerName,
                referencedImages: refs
            )
            if grouped[key] == nil {
                keyOrder.append(key)
            }
            grouped[key, default: []].append(annotation)
        }

        var nextCompoundID = 1
        var result: [GraphicAnnotation] = []

        for key in keyOrder {
            guard let items = grouped[key] else { continue }
            var graphicObjects: [GraphicObject] = []
            var textObjects: [TextObject] = []
            var compoundGraphics: [CompoundGraphic] = []

            for annotation in items {
                let built = buildObjects(
                    for: annotation,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight,
                    compoundGraphicID: &nextCompoundID
                )
                graphicObjects.append(contentsOf: built.graphics)
                textObjects.append(contentsOf: built.texts)
                compoundGraphics.append(contentsOf: built.compounds)
            }

            guard !graphicObjects.isEmpty || !textObjects.isEmpty || !compoundGraphics.isEmpty else {
                continue
            }

            result.append(GraphicAnnotation(
                layer: key.layer,
                referencedImages: key.referencedImages,
                graphicObjects: graphicObjects,
                textObjects: textObjects,
                compoundGraphics: compoundGraphics
            ))
        }

        return result
    }

    /// Extracts high-level `[DICOMAnnotation]` from any `PresentationStateDocument` (GSPS, CSPS, or Pseudo-CSPS),
    /// optionally filtering by image SOP Instance UID and 1-based frame number.
    public static func annotations(
        from document: PresentationStateDocument,
        forImage sopInstanceUID: String? = nil,
        frameNumber: Int? = nil,
        imageWidth: Int,
        imageHeight: Int,
        targetCoordinateSpace: DICOMAnnotationCoordinateSpace = .pixel
    ) -> [DICOMAnnotation] {
        annotations(
            from: document.graphicAnnotations,
            layers: document.graphicLayers,
            forImage: sopInstanceUID,
            frameNumber: frameNumber,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            targetCoordinateSpace: targetCoordinateSpace
        )
    }

    /// Extracts high-level `[DICOMAnnotation]` from DICOM `GraphicAnnotation` and `GraphicLayer` arrays.
    public static func annotations(
        from graphicAnnotations: [GraphicAnnotation],
        layers: [GraphicLayer],
        forImage sopInstanceUID: String? = nil,
        frameNumber: Int? = nil,
        imageWidth: Int,
        imageHeight: Int,
        targetCoordinateSpace: DICOMAnnotationCoordinateSpace = .pixel
    ) -> [DICOMAnnotation] {
        guard imageWidth > 0, imageHeight > 0 else { return [] }
        let layerColors: [String: DICOMAnnotationColor] = Dictionary(
            layers.map { ($0.name, colorFromLayer($0)) },
            uniquingKeysWith: { first, _ in first }
        )

        var extracted: [DICOMAnnotation] = []

        for item in graphicAnnotations {
            if let sopInstanceUID, !item.referencedImages.isEmpty {
                let matchingRefs = item.referencedImages.filter { $0.sopInstanceUID == sopInstanceUID }
                guard !matchingRefs.isEmpty else { continue }
                if let frameNumber {
                    let matchesFrame = matchingRefs.contains { ref in
                        guard let frames = ref.referencedFrameNumbers, !frames.isEmpty else { return true }
                        return frames.contains(frameNumber)
                    }
                    guard matchesFrame else { continue }
                }
            }

            let defaultColor = layerColors[item.layer] ?? .yellow
            let primaryRef = item.referencedImages.first
            var consumedCompoundIDs = Set<Int>()

            for compound in item.compoundGraphics {
                if let converted = annotationFromCompound(
                    compound,
                    companionTexts: item.textObjects.filter { $0.compoundGraphicInstanceID == compound.instanceID },
                    layer: item.layer,
                    defaultColor: defaultColor,
                    primaryRef: primaryRef,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight,
                    targetSpace: targetCoordinateSpace
                ) {
                    extracted.append(converted)
                    consumedCompoundIDs.insert(compound.instanceID)
                }
            }

            var consumedTextIndices = Set<Int>()
            for (idx, textObj) in item.textObjects.enumerated() {
                if let id = textObj.compoundGraphicInstanceID, consumedCompoundIDs.contains(id) {
                    consumedTextIndices.insert(idx)
                }
            }

            for object in item.graphicObjects {
                if let id = object.compoundGraphicInstanceID, consumedCompoundIDs.contains(id) {
                    continue
                }
                var matchedAngleText: String? = nil
                if object.type == .polyline, !object.filled, object.data.count == 6 {
                    let vx = object.data[2]
                    let vy = object.data[3]
                    if let textIdx = item.textObjects.enumerated().first(where: { idx, t in
                        !consumedTextIndices.contains(idx) &&
                        (t.text.contains("°") || t.text.lowercased().contains("deg")) &&
                        abs(t.boundingBoxTopLeft.column - vx) < 2.0 &&
                        abs(t.boundingBoxTopLeft.row - vy) < 2.0
                    })?.offset {
                        matchedAngleText = item.textObjects[textIdx].text
                        consumedTextIndices.insert(textIdx)
                    }
                }
                if let converted = annotationFromGraphicObject(
                    object,
                    matchedAngleText: matchedAngleText,
                    layer: item.layer,
                    defaultColor: defaultColor,
                    primaryRef: primaryRef,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight,
                    targetSpace: targetCoordinateSpace
                ) {
                    extracted.append(converted)
                }
            }

            for (idx, textObject) in item.textObjects.enumerated() {
                if consumedTextIndices.contains(idx) {
                    continue
                }
                if let converted = annotationFromTextObject(
                    textObject,
                    layer: item.layer,
                    defaultColor: defaultColor,
                    primaryRef: primaryRef,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight,
                    targetSpace: targetCoordinateSpace
                ) {
                    extracted.append(converted)
                }
            }
        }

        return extracted
    }

    // MARK: - Private Builders

    private static func buildObjects(
        for annotation: DICOMAnnotation,
        imageWidth: Int,
        imageHeight: Int,
        compoundGraphicID: inout Int
    ) -> (graphics: [GraphicObject], texts: [TextObject], compounds: [CompoundGraphic]) {
        let pixelPoints = annotation.points.map {
            $0.toPixel(space: annotation.coordinateSpace, imageWidth: imageWidth, imageHeight: imageHeight)
        }
        let lineStyle = makeLineStyle(for: annotation)
        let textStyle = makeTextStyle(for: annotation, imageHeight: imageHeight)
        let fillStyle: FillStyle? = annotation.filled
            ? FillStyle(onColor: annotation.color.cieLab, onOpacity: annotation.color.opacity, mode: .solid)
            : nil

        switch annotation.kind {
        case .text:
            guard let first = pixelPoints.first, !annotation.text.isEmpty else { return ([], [], []) }
            let textObj = makeTextObject(
                text: annotation.text,
                topLeft: first,
                anchor: nil,
                scale: annotation.scale,
                textStyle: textStyle,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                compoundGraphicID: nil
            )
            return ([], [textObj], [])

        case .annotation:
            guard pixelPoints.count >= 2 else {
                if let first = pixelPoints.first, !annotation.text.isEmpty {
                    let textObj = makeTextObject(
                        text: annotation.text,
                        topLeft: first,
                        anchor: nil,
                        scale: annotation.scale,
                        textStyle: textStyle,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight,
                        compoundGraphicID: nil
                    )
                    return ([], [textObj], [])
                }
                return ([], [], [])
            }
            let boxCorner = pixelPoints[0]
            let anchor = pixelPoints[1]
            if !annotation.text.isEmpty {
                let textObj = makeTextObject(
                    text: annotation.text,
                    topLeft: boxCorner,
                    anchor: anchor,
                    scale: annotation.scale,
                    textStyle: textStyle,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight,
                    compoundGraphicID: nil
                )
                return ([], [textObj], [])
            } else {
                return buildArrow(
                    tail: boxCorner,
                    head: anchor,
                    lineStyle: lineStyle,
                    imageHeight: imageHeight,
                    scale: annotation.scale,
                    compoundGraphicID: &compoundGraphicID
                )
            }

        case .arrow:
            guard pixelPoints.count >= 2 else { return ([], [], []) }
            return buildArrow(
                tail: pixelPoints[0],
                head: pixelPoints[1],
                lineStyle: lineStyle,
                imageHeight: imageHeight,
                scale: annotation.scale,
                compoundGraphicID: &compoundGraphicID
            )

        case .ruler:
            guard pixelPoints.count >= 2 else { return ([], [], []) }
            let p1 = pixelPoints[0]
            let p2 = pixelPoints[1]
            let id = compoundGraphicID
            compoundGraphicID += 1

            let fallbackLine = GraphicObject(
                type: .polyline,
                data: [p1.column, p1.row, p2.column, p2.row],
                filled: false,
                units: .pixel,
                lineStyle: lineStyle,
                compoundGraphicInstanceID: id
            )
            var texts: [TextObject] = []
            let label = !annotation.text.isEmpty
                ? annotation.text
                : (annotation.measurements.first?.formattedString ?? "")
            if !label.isEmpty {
                let mid = (column: (p1.column + p2.column) / 2.0, row: (p1.row + p2.row) / 2.0)
                texts.append(makeTextObject(
                    text: label,
                    topLeft: mid,
                    anchor: nil,
                    scale: annotation.scale,
                    textStyle: textStyle,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight,
                    compoundGraphicID: id
                ))
            }
            let compound = CompoundGraphic(
                instanceID: id,
                type: .ruler,
                units: .pixel,
                data: [p1.column, p1.row, p2.column, p2.row],
                textStyle: textStyle,
                lineStyle: lineStyle,
                tickAlignment: .center,
                tickLabelAlignment: .bottom,
                showTickLabel: true
            )
            return ([fallbackLine], texts, [compound])

        case .angle:
            guard pixelPoints.count >= 3 else { return ([], [], []) }
            let p1 = pixelPoints[0]
            let vertex = pixelPoints[1]
            let p2 = pixelPoints[2]
            let polyline = GraphicObject(
                type: .polyline,
                data: [p1.column, p1.row, vertex.column, vertex.row, p2.column, p2.row],
                filled: false,
                units: .pixel,
                lineStyle: lineStyle
            )
            var texts: [TextObject] = []
            let computedDeg: Double = {
                let v1x = p1.column - vertex.column
                let v1y = p1.row - vertex.row
                let v2x = p2.column - vertex.column
                let v2y = p2.row - vertex.row
                let denom = (v1x * v1x + v1y * v1y).squareRoot() * (v2x * v2x + v2y * v2y).squareRoot()
                guard denom > 0 else { return 0 }
                let cosTheta = max(-1.0, min(1.0, (v1x * v2x + v1y * v2y) / denom))
                return acos(cosTheta) * 180.0 / Double.pi
            }()
            let label = !annotation.text.isEmpty
                ? annotation.text
                : (annotation.measurements.first?.formattedString ?? String(format: "%.1f °", computedDeg))
            if !label.isEmpty {
                texts.append(makeTextObject(
                    text: label,
                    topLeft: vertex,
                    anchor: nil,
                    scale: annotation.scale,
                    textStyle: textStyle,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight,
                    compoundGraphicID: nil
                ))
            }
            return ([polyline], texts, [])

        case .rectangle:
            guard pixelPoints.count >= 2 else { return ([], [], []) }
            let tl = (column: min(pixelPoints[0].column, pixelPoints[1].column),
                      row: min(pixelPoints[0].row, pixelPoints[1].row))
            let br = (column: max(pixelPoints[0].column, pixelPoints[1].column),
                      row: max(pixelPoints[0].row, pixelPoints[1].row))
            let id = compoundGraphicID
            compoundGraphicID += 1

            let closedOutline = GraphicObject(
                type: .polyline,
                data: [
                    tl.column, tl.row,
                    br.column, tl.row,
                    br.column, br.row,
                    tl.column, br.row,
                    tl.column, tl.row
                ],
                filled: annotation.filled,
                units: .pixel,
                lineStyle: lineStyle,
                fillStyle: fillStyle,
                compoundGraphicInstanceID: id
            )
            let compound = CompoundGraphic(
                instanceID: id,
                type: .rectangle,
                units: .pixel,
                data: [tl.column, tl.row, br.column, br.row],
                textStyle: textStyle,
                lineStyle: lineStyle,
                filled: annotation.filled,
                fillStyle: fillStyle
            )
            return ([closedOutline], [], [compound])

        case .ellipse:
            // PS3.3 C.10.5.1.2: ELLIPSE in GraphicObject has 4 points (major axis endpoints, then minor axis endpoints)
            let ellipseData: [Double]
            if pixelPoints.count >= 4 {
                ellipseData = pixelPoints.prefix(4).flatMap { [$0.column, $0.row] }
            } else if pixelPoints.count >= 2 {
                let minCol = min(pixelPoints[0].column, pixelPoints[1].column)
                let maxCol = max(pixelPoints[0].column, pixelPoints[1].column)
                let minRow = min(pixelPoints[0].row, pixelPoints[1].row)
                let maxRow = max(pixelPoints[0].row, pixelPoints[1].row)
                let midCol = (minCol + maxCol) / 2.0
                let midRow = (minRow + maxRow) / 2.0
                if (maxCol - minCol) >= (maxRow - minRow) {
                    ellipseData = [minCol, midRow, maxCol, midRow, midCol, minRow, midCol, maxRow]
                } else {
                    ellipseData = [midCol, minRow, midCol, maxRow, minCol, midRow, maxCol, midRow]
                }
            } else {
                return ([], [], [])
            }
            let obj = GraphicObject(
                type: .ellipse,
                data: ellipseData,
                filled: annotation.filled,
                units: .pixel,
                lineStyle: lineStyle,
                fillStyle: fillStyle
            )
            return ([obj], [], [])

        case .circle:
            guard pixelPoints.count >= 2 else { return ([], [], []) }
            let center = pixelPoints[0]
            let perimeter = pixelPoints[1]
            let obj = GraphicObject(
                type: .circle,
                data: [center.column, center.row, perimeter.column, perimeter.row],
                filled: annotation.filled,
                units: .pixel,
                lineStyle: lineStyle,
                fillStyle: fillStyle
            )
            return ([obj], [], [])

        case .polyline:
            guard pixelPoints.count >= 2 else { return ([], [], []) }
            var data = pixelPoints.flatMap { [$0.column, $0.row] }
            if annotation.filled,
               let first = pixelPoints.first,
               let last = pixelPoints.last,
               (first.column != last.column || first.row != last.row) {
                data.append(contentsOf: [first.column, first.row])
            }
            let obj = GraphicObject(
                type: .polyline,
                data: data,
                filled: annotation.filled,
                units: .pixel,
                lineStyle: lineStyle,
                fillStyle: fillStyle
            )
            return ([obj], [], [])

        case .crosshair:
            guard let center = pixelPoints.first else { return ([], [], []) }
            let id = compoundGraphicID
            compoundGraphicID += 1
            let arm = max(8.0, Double(min(imageWidth, imageHeight)) * 0.025)
            let horizontal = GraphicObject(
                type: .polyline,
                data: [center.column - arm, center.row, center.column + arm, center.row],
                filled: false,
                units: .pixel,
                lineStyle: lineStyle,
                compoundGraphicInstanceID: id
            )
            let vertical = GraphicObject(
                type: .polyline,
                data: [center.column, center.row - arm, center.column, center.row + arm],
                filled: false,
                units: .pixel,
                lineStyle: lineStyle,
                compoundGraphicInstanceID: id
            )
            let compound = CompoundGraphic(
                instanceID: id,
                type: .crosshair,
                units: .pixel,
                data: [center.column, center.row],
                lineStyle: lineStyle,
                gapLength: 0.005,
                diameterOfVisibility: 0.05,
                tickAlignment: .center,
                tickLabelAlignment: .bottom,
                showTickLabel: false
            )
            return ([horizontal, vertical], [], [compound])

        case .point:
            guard let pt = pixelPoints.first else { return ([], [], []) }
            let obj = GraphicObject(
                type: .point,
                data: [pt.column, pt.row],
                filled: false,
                units: .pixel,
                lineStyle: lineStyle
            )
            return ([obj], [], [])
        }
    }

    private static func buildArrow(
        tail: (column: Double, row: Double),
        head: (column: Double, row: Double),
        lineStyle: LineStyle,
        imageHeight: Int,
        scale: Double,
        compoundGraphicID: inout Int
    ) -> (graphics: [GraphicObject], texts: [TextObject], compounds: [CompoundGraphic]) {
        let dx = head.column - tail.column
        let dy = head.row - tail.row
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return ([], [], []) }

        let id = compoundGraphicID
        compoundGraphicID += 1

        let wingLength = max(8.0, min(length * 0.35, Double(imageHeight) * scale * 0.9))
        let angle = atan2(dy, dx)
        let wingAngle = Double.pi / 6.0
        let leftWing = (
            column: head.column - wingLength * cos(angle - wingAngle),
            row: head.row - wingLength * sin(angle - wingAngle)
        )
        let rightWing = (
            column: head.column - wingLength * cos(angle + wingAngle),
            row: head.row - wingLength * sin(angle + wingAngle)
        )

        let shaft = GraphicObject(
            type: .polyline,
            data: [tail.column, tail.row, head.column, head.row],
            filled: false,
            units: .pixel,
            lineStyle: lineStyle,
            compoundGraphicInstanceID: id
        )
        let headPolyline = GraphicObject(
            type: .polyline,
            data: [leftWing.column, leftWing.row, head.column, head.row, rightWing.column, rightWing.row],
            filled: false,
            units: .pixel,
            lineStyle: lineStyle,
            compoundGraphicInstanceID: id
        )
        // PS3.3 C.10.5.1.3.11: ARROW Graphic Data has 2 points: anchor (head) first, then foot (tail)
        let compound = CompoundGraphic(
            instanceID: id,
            type: .arrow,
            units: .pixel,
            data: [head.column, head.row, tail.column, tail.row],
            lineStyle: lineStyle
        )
        return ([shaft, headPolyline], [], [compound])
    }

    private static func makeLineStyle(for annotation: DICOMAnnotation) -> LineStyle {
        let darkHalo = annotation.color.luminance > 0.45
        let shadow = GraphicShadow(
            style: .outlined,
            offsetX: max(1.0, annotation.lineThickness * 0.5),
            offsetY: 0,
            color: darkHalo ? GraphicShadow.black : CIELabColor(l: 65535, a: 0x8080, b: 0x8080),
            opacity: 1.0
        )
        return LineStyle(
            onColor: annotation.color.cieLab,
            onOpacity: annotation.color.opacity,
            thickness: annotation.lineThickness,
            dashing: annotation.isDashed ? .dashed : .solid,
            pattern: annotation.isDashed ? 0xFF00FF00 : nil,
            shadow: shadow
        )
    }

    private static func makeTextStyle(for annotation: DICOMAnnotation, imageHeight: Int) -> TextStyle {
        let fontSize = max(10.0, Double(imageHeight) * annotation.scale)
        let darkHalo = annotation.color.luminance > 0.45
        let shadow = GraphicShadow(
            style: .outlined,
            offsetX: max(1.0, fontSize * 0.06),
            offsetY: 0,
            color: darkHalo ? GraphicShadow.black : CIELabColor(l: 65535, a: 0x8080, b: 0x8080),
            opacity: 1.0
        )
        return TextStyle(
            fontName: "Helvetica-Bold",
            fontNameType: "ISO_32000",
            cssFontName: "sans-serif",
            color: annotation.color.cieLab,
            horizontalAlignment: .left,
            verticalAlignment: .top,
            shadow: shadow,
            bold: true
        )
    }

    private static func makeTextObject(
        text: String,
        topLeft: (column: Double, row: Double),
        anchor: (column: Double, row: Double)?,
        scale: Double,
        textStyle: TextStyle,
        imageWidth: Int,
        imageHeight: Int,
        compoundGraphicID: Int?
    ) -> TextObject {
        let boxHeight = max(12.0, Double(imageHeight) * scale)
        let boxWidth = max(boxHeight, boxHeight * 0.6 * Double(max(1, text.count)))
        let brColumn = min(Double(imageWidth), topLeft.column + boxWidth)
        let brRow = min(Double(imageHeight), topLeft.row + boxHeight)

        return TextObject(
            text: text,
            boundingBoxTopLeft: topLeft,
            boundingBoxBottomRight: (column: brColumn, row: brRow),
            anchorPoint: anchor ?? topLeft,
            anchorPointVisible: anchor != nil,
            boundingBoxUnits: .pixel,
            anchorPointUnits: .pixel,
            textStyle: textStyle,
            compoundGraphicInstanceID: compoundGraphicID
        )
    }

    // MARK: - Private Readers

    private static func colorFromLayer(_ layer: GraphicLayer) -> DICOMAnnotationColor {
        if let rgb = layer.recommendedRGBValue {
            return DICOMAnnotationColor(
                red: Double(rgb.red) / 65535.0,
                green: Double(rgb.green) / 65535.0,
                blue: Double(rgb.blue) / 65535.0
            )
        }
        if let gray = layer.recommendedGrayscaleValue {
            let v = Double(gray) / 65535.0
            return DICOMAnnotationColor(red: v, green: v, blue: v)
        }
        return .yellow
    }

    private static func convertPoints(
        _ data: [Double],
        units: AnnotationUnits,
        imageWidth: Int,
        imageHeight: Int,
        targetSpace: DICOMAnnotationCoordinateSpace
    ) -> [DICOMAnnotationPoint] {
        guard data.count >= 2 else { return [] }
        var result: [DICOMAnnotationPoint] = []
        for idx in stride(from: 0, to: data.count - 1, by: 2) {
            let rawX = data[idx]
            let rawY = data[idx + 1]
            let pixelCol: Double
            let pixelRow: Double
            switch units {
            case .pixel, .matrix:
                pixelCol = rawX
                pixelRow = rawY
            case .display:
                pixelCol = rawX * Double(imageWidth)
                pixelRow = rawY * Double(imageHeight)
            }
            result.append(.fromPixel(
                column: pixelCol,
                row: pixelRow,
                targetSpace: targetSpace,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            ))
        }
        return result
    }

    private static func annotationFromCompound(
        _ compound: CompoundGraphic,
        companionTexts: [TextObject],
        layer: String,
        defaultColor: DICOMAnnotationColor,
        primaryRef: ReferencedImage?,
        imageWidth: Int,
        imageHeight: Int,
        targetSpace: DICOMAnnotationCoordinateSpace
    ) -> DICOMAnnotation? {
        let units: AnnotationUnits = compound.units == .display ? .display : .pixel
        let pts = convertPoints(
            compound.data,
            units: units,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            targetSpace: targetSpace
        )
        let color = compound.lineStyle.map { DICOMAnnotationColor(cieLab: $0.onColor, opacity: $0.onOpacity) }
            ?? defaultColor
        let thickness = compound.lineStyle?.thickness ?? 2.0
        let dashed = compound.lineStyle?.dashing == .dashed
        let label = companionTexts.first?.text ?? ""

        switch compound.type {
        case .arrow:
            guard pts.count >= 2 else { return nil }
            // PS3.3 C.10.5.1.3.11: point 0 is head (anchor), point 1 is foot (tail)
            return DICOMAnnotation(
                kind: .arrow,
                coordinateSpace: targetSpace,
                points: [pts[1], pts[0]],
                text: label,
                color: color,
                lineThickness: thickness,
                isDashed: dashed,
                layerName: layer,
                referencedSOPClassUID: primaryRef?.sopClassUID,
                referencedSOPInstanceUID: primaryRef?.sopInstanceUID,
                referencedFrameNumbers: primaryRef?.referencedFrameNumbers
            )
        case .ruler, .axis, .rangeline:
            guard pts.count >= 2 else { return nil }
            return DICOMAnnotation(
                kind: .ruler,
                coordinateSpace: targetSpace,
                points: [pts[0], pts[1]],
                text: label,
                color: color,
                lineThickness: thickness,
                isDashed: dashed,
                layerName: layer,
                referencedSOPClassUID: primaryRef?.sopClassUID,
                referencedSOPInstanceUID: primaryRef?.sopInstanceUID,
                referencedFrameNumbers: primaryRef?.referencedFrameNumbers
            )
        case .rectangle:
            guard pts.count >= 2 else { return nil }
            return DICOMAnnotation(
                kind: .rectangle,
                coordinateSpace: targetSpace,
                points: [pts[0], pts[1]],
                text: label,
                color: color,
                filled: compound.filled,
                lineThickness: thickness,
                isDashed: dashed,
                layerName: layer,
                referencedSOPClassUID: primaryRef?.sopClassUID,
                referencedSOPInstanceUID: primaryRef?.sopInstanceUID,
                referencedFrameNumbers: primaryRef?.referencedFrameNumbers
            )
        case .ellipse:
            guard pts.count >= 2 else { return nil }
            return DICOMAnnotation(
                kind: .ellipse,
                coordinateSpace: targetSpace,
                points: [pts[0], pts[1]],
                text: label,
                color: color,
                filled: compound.filled,
                lineThickness: thickness,
                isDashed: dashed,
                layerName: layer,
                referencedSOPClassUID: primaryRef?.sopClassUID,
                referencedSOPInstanceUID: primaryRef?.sopInstanceUID,
                referencedFrameNumbers: primaryRef?.referencedFrameNumbers
            )
        case .crosshair:
            guard let first = pts.first else { return nil }
            return DICOMAnnotation(
                kind: .crosshair,
                coordinateSpace: targetSpace,
                points: [first],
                text: label,
                color: color,
                lineThickness: thickness,
                isDashed: dashed,
                layerName: layer,
                referencedSOPClassUID: primaryRef?.sopClassUID,
                referencedSOPInstanceUID: primaryRef?.sopInstanceUID,
                referencedFrameNumbers: primaryRef?.referencedFrameNumbers
            )
        case .cutline, .infiniteline, .multiline:
            guard pts.count >= 2 else { return nil }
            return DICOMAnnotation(
                kind: .polyline,
                coordinateSpace: targetSpace,
                points: pts,
                text: label,
                color: color,
                lineThickness: thickness,
                isDashed: dashed,
                layerName: layer,
                referencedSOPClassUID: primaryRef?.sopClassUID,
                referencedSOPInstanceUID: primaryRef?.sopInstanceUID,
                referencedFrameNumbers: primaryRef?.referencedFrameNumbers
            )
        }
    }

    private static func annotationFromGraphicObject(
        _ object: GraphicObject,
        matchedAngleText: String? = nil,
        layer: String,
        defaultColor: DICOMAnnotationColor,
        primaryRef: ReferencedImage?,
        imageWidth: Int,
        imageHeight: Int,
        targetSpace: DICOMAnnotationCoordinateSpace
    ) -> DICOMAnnotation? {
        let pts = convertPoints(
            object.data,
            units: object.units,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            targetSpace: targetSpace
        )
        guard !pts.isEmpty else { return nil }

        let color = object.lineStyle.map { DICOMAnnotationColor(cieLab: $0.onColor, opacity: $0.onOpacity) }
            ?? defaultColor
        let thickness = object.lineStyle?.thickness ?? 2.0
        let dashed = object.lineStyle?.dashing == .dashed

        let kind: DICOMAnnotationKind
        switch object.type {
        case .point:
            kind = .point
        case .polyline, .interpolated:
            kind = (matchedAngleText != nil && pts.count == 3) ? .angle : .polyline
        case .circle:
            kind = .circle
        case .ellipse:
            kind = .ellipse
        }

        return DICOMAnnotation(
            kind: kind,
            coordinateSpace: targetSpace,
            points: pts,
            text: matchedAngleText ?? "",
            color: color,
            filled: object.filled,
            lineThickness: thickness,
            isDashed: dashed,
            layerName: layer,
            referencedSOPClassUID: primaryRef?.sopClassUID,
            referencedSOPInstanceUID: primaryRef?.sopInstanceUID,
            referencedFrameNumbers: primaryRef?.referencedFrameNumbers
        )
    }

    private static func annotationFromTextObject(
        _ textObject: TextObject,
        layer: String,
        defaultColor: DICOMAnnotationColor,
        primaryRef: ReferencedImage?,
        imageWidth: Int,
        imageHeight: Int,
        targetSpace: DICOMAnnotationCoordinateSpace
    ) -> DICOMAnnotation? {
        let trimmed = textObject.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let topLeftPts = convertPoints(
            [textObject.boundingBoxTopLeft.column, textObject.boundingBoxTopLeft.row],
            units: textObject.boundingBoxUnits,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            targetSpace: targetSpace
        )
        let bottomRightPts = convertPoints(
            [textObject.boundingBoxBottomRight.column, textObject.boundingBoxBottomRight.row],
            units: textObject.boundingBoxUnits,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            targetSpace: targetSpace
        )
        guard let tl = topLeftPts.first else { return nil }
        let br = bottomRightPts.first ?? tl

        let start = DICOMAnnotationPoint(x: min(tl.x, br.x), y: min(tl.y, br.y))
        let color = textObject.textStyle.map { DICOMAnnotationColor(cieLab: $0.color) } ?? defaultColor

        let boxHeightPixels: Double
        if textObject.boundingBoxUnits == .display {
            boxHeightPixels = abs(textObject.boundingBoxBottomRight.row - textObject.boundingBoxTopLeft.row) * Double(imageHeight)
        } else {
            boxHeightPixels = abs(textObject.boundingBoxBottomRight.row - textObject.boundingBoxTopLeft.row)
        }
        let scale = boxHeightPixels > 1.0
            ? boxHeightPixels / Double(max(1, imageHeight))
            : DICOMAnnotation.defaultScale

        if textObject.anchorPointVisible, let anchorRaw = textObject.anchorPoint {
            let anchorPts = convertPoints(
                [anchorRaw.column, anchorRaw.row],
                units: textObject.anchorPointUnits,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                targetSpace: targetSpace
            )
            if let anchor = anchorPts.first {
                return DICOMAnnotation(
                    kind: .annotation,
                    coordinateSpace: targetSpace,
                    points: [start, anchor],
                    text: trimmed,
                    color: color,
                    scale: scale,
                    layerName: layer,
                    referencedSOPClassUID: primaryRef?.sopClassUID,
                    referencedSOPInstanceUID: primaryRef?.sopInstanceUID,
                    referencedFrameNumbers: primaryRef?.referencedFrameNumbers
                )
            }
        }

        return DICOMAnnotation(
            kind: .text,
            coordinateSpace: targetSpace,
            points: [start],
            text: trimmed,
            color: color,
            scale: scale,
            layerName: layer,
            referencedSOPClassUID: primaryRef?.sopClassUID,
            referencedSOPInstanceUID: primaryRef?.sopInstanceUID,
            referencedFrameNumbers: primaryRef?.referencedFrameNumbers
        )
    }
}

public extension PresentationStateDocument {
    /// Extracts high-level `DICOMAnnotation` objects from this document, optionally filtered
    /// by image SOP Instance UID and 1-based frame number.
    func annotations(
        forImage sopInstanceUID: String? = nil,
        frameNumber: Int? = nil,
        imageWidth: Int = 512,
        imageHeight: Int = 512,
        targetCoordinateSpace: DICOMAnnotationCoordinateSpace = .pixel
    ) -> [DICOMAnnotation] {
        let resolvedW = effectiveDisplayedArea(forImage: sopInstanceUID, frameNumber: frameNumber)
            .map { max(1, $0.bottomRight.column - $0.topLeft.column + 1) } ?? imageWidth
        let resolvedH = effectiveDisplayedArea(forImage: sopInstanceUID, frameNumber: frameNumber)
            .map { max(1, $0.bottomRight.row - $0.topLeft.row + 1) } ?? imageHeight
        let all = DICOMAnnotationConverter.annotations(
            from: self,
            imageWidth: resolvedW,
            imageHeight: resolvedH,
            targetCoordinateSpace: targetCoordinateSpace
        )
        guard let sopInstanceUID else {
            return all
        }
        return all.filter { $0.appliesTo(sopInstanceUID: sopInstanceUID, frameNumber: frameNumber) }
    }
}
