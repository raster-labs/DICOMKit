// AnnotationModel.swift
// DICOMStudio
//
// DICOM Studio — GSPS graphic and text annotation models
//
// NEMA-verified: 2026a, checked 2026-10-06 — `GraphicType` raw values are the 5 Graphic Type (0070,0023) Enumerated Values of PS3.3 2026a C.10.5 (POINT, POLYLINE, INTERPOLATED, CIRCLE, ELLIPSE), all match; `GraphicLayer` field comments name (0070,0002) Graphic Layer, (0070,0062) Graphic Layer Order, (0070,0066) Graphic Layer Recommended Display Grayscale Value and (0070,0068) Graphic Layer Description as PS3.6 2026a Table 6-1 does; `TextAnchorType` raw values PIXEL, DISPLAY, MATRIX are the 3 Bounding Box / Anchor Point Annotation Units (0070,0003) / (0070,0004) Enumerated Values of PS3.3 2026a C.10.5 (Table C.10-5), 3/3 (P-STUDIO-ANNOTATION-UNITS: IMAGE → PIXEL with a decoding shim, MATRIX added); checked by Scripts/diff_studio_g2_viewer.py

import Foundation

/// Graphic Type (0070,0023) Enumerated Values, PS3.3 C.10.5 / C.10.5.1.2.
public enum GraphicType: String, Sendable, Equatable, Hashable, CaseIterable {
    case point = "POINT"
    case polyline = "POLYLINE"
    case interpolated = "INTERPOLATED"
    case circle = "CIRCLE"
    case ellipse = "ELLIPSE"
}

/// A 2D point in DICOM image coordinates.
public struct AnnotationPoint: Sendable, Equatable, Hashable {
    /// Column coordinate (X).
    public let x: Double

    /// Row coordinate (Y).
    public let y: Double

    /// Creates a new annotation point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Anchor point units for text annotations — Anchor Point Annotation Units
/// (0070,0004), PS3.3 C.10.5.
///
/// The raw values are the PS3.3 2026a Enumerated Values (Table C.10-5, the same for
/// Bounding Box Annotation Units (0070,0003)): PIXEL (image relative, sub-pixel), DISPLAY (a
/// fraction of the Specified Displayed Area) and MATRIX (Total Pixel Matrix relative, for tiled
/// images). `init(rawValue:)` also accepts IMAGE, the raw value `imageRelative` carried before
/// 2026-10-06 (P-STUDIO-ANNOTATION-UNITS).
public enum TextAnchorType: String, Sendable, Equatable, Hashable {
    /// Text is anchored to a specific image location (PIXEL units).
    case imageRelative = "PIXEL"
    /// Text is anchored relative to the display (DISPLAY units).
    case displayRelative = "DISPLAY"
    /// Text is anchored relative to the Total Pixel Matrix of a tiled image (MATRIX units).
    case matrixRelative = "MATRIX"

    /// Creates the units from an Annotation Units value, or from the legacy app value IMAGE.
    public init?(rawValue: String) {
        switch rawValue {
        case "PIXEL", "IMAGE": self = .imageRelative
        case "DISPLAY": self = .displayRelative
        case "MATRIX": self = .matrixRelative
        default: return nil
        }
    }
}

/// A graphic annotation object (polyline, circle, ellipse, point).
///
/// Corresponds to DICOM Graphic Object Sequence (0070,0009).
public struct GraphicAnnotation: Identifiable, Sendable, Equatable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// The type of graphic.
    public let graphicType: GraphicType

    /// Data points defining the graphic (image coordinates).
    public let points: [AnnotationPoint]

    /// Whether the graphic is filled.
    public let filled: Bool

    /// Layer name this annotation belongs to.
    public let layerName: String

    /// Creates a new graphic annotation.
    public init(
        id: UUID = UUID(),
        graphicType: GraphicType,
        points: [AnnotationPoint],
        filled: Bool = false,
        layerName: String = "LAYER0"
    ) {
        self.id = id
        self.graphicType = graphicType
        self.points = points
        self.filled = filled
        self.layerName = layerName
    }
}

/// A text annotation object.
///
/// Corresponds to DICOM Text Object Sequence (0070,0008).
public struct TextAnnotation: Identifiable, Sendable, Equatable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// The text string to display.
    public let text: String

    /// Bounding box top-left corner (display coordinates).
    public let boundingBoxTopLeft: AnnotationPoint?

    /// Bounding box bottom-right corner (display coordinates).
    public let boundingBoxBottomRight: AnnotationPoint?

    /// Anchor point (image or display coordinates).
    public let anchorPoint: AnnotationPoint?

    /// Type of anchor point reference.
    public let anchorType: TextAnchorType?

    /// Whether the anchor point is visible (e.g., arrow drawn).
    public let anchorPointVisible: Bool

    /// Layer name this annotation belongs to.
    public let layerName: String

    /// Creates a new text annotation.
    public init(
        id: UUID = UUID(),
        text: String,
        boundingBoxTopLeft: AnnotationPoint? = nil,
        boundingBoxBottomRight: AnnotationPoint? = nil,
        anchorPoint: AnnotationPoint? = nil,
        anchorType: TextAnchorType? = nil,
        anchorPointVisible: Bool = true,
        layerName: String = "LAYER0"
    ) {
        self.id = id
        self.text = text
        self.boundingBoxTopLeft = boundingBoxTopLeft
        self.boundingBoxBottomRight = boundingBoxBottomRight
        self.anchorPoint = anchorPoint
        self.anchorType = anchorType
        self.anchorPointVisible = anchorPointVisible
        self.layerName = layerName
    }
}

/// Graphic layer properties per DICOM PS3.3 C.10.7.
public struct GraphicLayer: Identifiable, Sendable, Equatable, Hashable {
    /// Unique identifier.
    public var id: String { name }

    /// Layer name (0070,0002).
    public let name: String

    /// Layer order (0070,0062), lower = behind.
    public let order: Int

    /// Layer description (0070,0068).
    public let description: String?

    /// Recommended display grayscale value (0070,0066).
    public let grayscaleValue: Int?

    /// Creates a new graphic layer.
    public init(
        name: String,
        order: Int = 0,
        description: String? = nil,
        grayscaleValue: Int? = nil
    ) {
        self.name = name
        self.order = order
        self.description = description
        self.grayscaleValue = grayscaleValue
    }
}
