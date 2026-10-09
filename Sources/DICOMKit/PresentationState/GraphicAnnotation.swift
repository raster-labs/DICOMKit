// NEMA-verified: 2026a, checked 2026-09-29 — Graphic Type terms and the PIXEL/DISPLAY/MATRIX units match PS3.3 2026a Table C.10-5; ELLIPSE points per C.10.5.1.2; layer colours per Table C.10-7; Compound Graphic Sequence, Text/Line/Fill Style and Compound Graphic Instance ID / Graphic Group ID carried per Table C.10-5 (D39, see GraphicStyle.swift)
//
// GraphicAnnotation.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-04.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Graphic layer for organizing annotations
///
/// Layers are stacked in order, with higher order numbers displayed on top.
///
/// Reference: PS3.3 Section C.10.7 - Graphic Layer Module
public struct GraphicLayer: Sendable, Hashable {
    /// Layer name
    public let name: String
    
    /// Layer order (higher numbers are displayed on top)
    public let order: Int
    
    /// Description of the layer
    public let description: String?
    
    /// Recommended display grayscale value (0-65535)
    ///
    /// Graphic Layer Recommended Display Grayscale Value (0070,0066), Type 3, a P-Value.
    public let recommendedGrayscaleValue: Int?

    /// Recommended display colour, as 16-bit-per-channel sRGB.
    ///
    /// Table C.10-7 (2026a) carries the colour only as Graphic Layer Recommended
    /// Display CIELab Value (0070,0401); the RGB attribute (0070,0067) is not in
    /// the table any more. The builder converts this value to CIELab on the way
    /// out (C.10.7.1.1) and the parser converts (0070,0401) back, reading the
    /// retired RGB tag only for files that still carry it.
    public let recommendedRGBValue: (red: Int, green: Int, blue: Int)?
    
    /// Initialize a graphic layer
    public init(
        name: String,
        order: Int,
        description: String? = nil,
        recommendedGrayscaleValue: Int? = nil,
        recommendedRGBValue: (red: Int, green: Int, blue: Int)? = nil
    ) {
        self.name = name
        self.order = order
        self.description = description
        self.recommendedGrayscaleValue = recommendedGrayscaleValue
        self.recommendedRGBValue = recommendedRGBValue
    }
}

// MARK: - Hashable conformance for RGB tuple

extension GraphicLayer {
    public static func == (lhs: GraphicLayer, rhs: GraphicLayer) -> Bool {
        lhs.name == rhs.name &&
        lhs.order == rhs.order &&
        lhs.description == rhs.description &&
        lhs.recommendedGrayscaleValue == rhs.recommendedGrayscaleValue &&
        lhs.recommendedRGBValue?.red == rhs.recommendedRGBValue?.red &&
        lhs.recommendedRGBValue?.green == rhs.recommendedRGBValue?.green &&
        lhs.recommendedRGBValue?.blue == rhs.recommendedRGBValue?.blue
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(order)
        hasher.combine(description)
        hasher.combine(recommendedGrayscaleValue)
        hasher.combine(recommendedRGBValue?.red)
        hasher.combine(recommendedRGBValue?.green)
        hasher.combine(recommendedRGBValue?.blue)
    }
}

/// Graphic annotation
///
/// Contains graphic and text objects associated with referenced images.
///
/// Reference: PS3.3 Section C.10.5 - Graphic Annotation Module
public struct GraphicAnnotation: Sendable, Hashable {
    /// Layer this annotation belongs to
    public let layer: String
    
    /// Referenced images this annotation applies to
    public let referencedImages: [ReferencedImage]
    
    /// Graphic objects in this annotation
    public let graphicObjects: [GraphicObject]
    
    /// Text objects in this annotation
    public let textObjects: [TextObject]

    /// Compound Graphic Sequence (0070,0209), Type 3 (Table C.10-5): ARROW,
    /// RULER, RECTANGLE … drawn as themselves by viewers that can, with their
    /// alternate rendering in ``graphicObjects`` / ``textObjects`` under the
    /// same Compound Graphic Instance ID (C.10.5.1.3.1).
    public let compoundGraphics: [CompoundGraphic]
    
    /// Initialize a graphic annotation
    public init(
        layer: String,
        referencedImages: [ReferencedImage],
        graphicObjects: [GraphicObject] = [],
        textObjects: [TextObject] = [],
        compoundGraphics: [CompoundGraphic] = []
    ) {
        self.layer = layer
        self.referencedImages = referencedImages
        self.graphicObjects = graphicObjects
        self.textObjects = textObjects
        self.compoundGraphics = compoundGraphics
    }
}

/// Graphic object in an annotation
///
/// Represents geometric shapes like points, lines, circles, etc.
///
/// Reference: PS3.3 Section C.10.5.1.2 - Graphic Object Sequence
public struct GraphicObject: Sendable, Hashable {
    /// Type of graphic
    public let type: PresentationGraphicType
    
    /// Graphic data points (column, row pairs)
    public let data: [Double]
    
    /// Whether the graphic is filled
    public let filled: Bool
    
    /// Units for the graphic data
    public let units: AnnotationUnits

    /// Line Style Sequence (0070,0232), Table C.10-5b: colour, thickness,
    /// dashing and shadow of this object; its colour overrides the layer's.
    public let lineStyle: LineStyle?

    /// Fill Style Sequence (0070,0233), Table C.10-5c, for a filled object.
    public let fillStyle: FillStyle?

    /// Compound Graphic Instance ID (0070,0226): the compound graphic this
    /// object is (part of) the alternate rendering of (C.10.5.1.3.1).
    public let compoundGraphicInstanceID: Int?

    /// Graphic Group ID (0070,0295), Type 3.
    public let graphicGroupID: Int?
    
    /// Initialize a graphic object
    public init(
        type: PresentationGraphicType,
        data: [Double],
        filled: Bool = false,
        units: AnnotationUnits = .pixel,
        lineStyle: LineStyle? = nil,
        fillStyle: FillStyle? = nil,
        compoundGraphicInstanceID: Int? = nil,
        graphicGroupID: Int? = nil
    ) {
        self.type = type
        self.data = data
        self.filled = filled
        self.units = units
        self.lineStyle = lineStyle
        self.fillStyle = fillStyle
        self.compoundGraphicInstanceID = compoundGraphicInstanceID
        self.graphicGroupID = graphicGroupID
    }
    
    /// Number of points in the graphic
    public var pointCount: Int {
        data.count / 2
    }
    
    /// Get a specific point from the graphic data
    ///
    /// - Parameter index: Point index (0-based)
    /// - Returns: (column, row) coordinate, or nil if index is invalid
    public func point(at index: Int) -> (column: Double, row: Double)? {
        guard index >= 0 && index < pointCount else {
            return nil
        }
        
        let offset = index * 2
        return (data[offset], data[offset + 1])
    }
}

/// Type of graphic object for presentation state annotations
///
/// Reference: PS3.3 Section C.10.5.1.2.1 - Graphic Type
public enum PresentationGraphicType: String, Sendable, Hashable {
    /// Single point
    case point = "POINT"
    
    /// Polyline (multiple connected line segments)
    case polyline = "POLYLINE"
    
    /// Interpolated smooth curve
    case interpolated = "INTERPOLATED"
    
    /// Circle (center + radius point)
    case circle = "CIRCLE"
    
    /// Ellipse: four points, the endpoints of the major axis then of the minor axis (C.10.5.1.2)
    case ellipse = "ELLIPSE"
}

/// Text object in an annotation
///
/// Represents text labels with positioning information.
///
/// Reference: PS3.3 Section C.10.5.1.3 - Text Object Sequence
public struct TextObject: Sendable, Hashable {
    /// Text to display
    public let text: String
    
    /// Bounding box top-left corner (column, row)
    public let boundingBoxTopLeft: (column: Double, row: Double)
    
    /// Bounding box bottom-right corner (column, row)
    public let boundingBoxBottomRight: (column: Double, row: Double)
    
    /// Anchor point for the text (column, row)
    public let anchorPoint: (column: Double, row: Double)?
    
    /// Whether the anchor point is visible
    public let anchorPointVisible: Bool
    
    /// Units for bounding box coordinates
    public let boundingBoxUnits: AnnotationUnits
    
    /// Units for anchor point coordinates
    public let anchorPointUnits: AnnotationUnits

    /// Text Style Sequence (0070,0231), Table C.10-5a: font, colour (which
    /// overrides the layer's), alignment and shadow.
    public let textStyle: TextStyle?

    /// Compound Graphic Instance ID (0070,0226) — see ``GraphicObject``.
    public let compoundGraphicInstanceID: Int?

    /// Graphic Group ID (0070,0295), Type 3.
    public let graphicGroupID: Int?
    
    /// Initialize a text object
    public init(
        text: String,
        boundingBoxTopLeft: (column: Double, row: Double),
        boundingBoxBottomRight: (column: Double, row: Double),
        anchorPoint: (column: Double, row: Double)? = nil,
        anchorPointVisible: Bool = false,
        boundingBoxUnits: AnnotationUnits = .pixel,
        anchorPointUnits: AnnotationUnits = .pixel,
        textStyle: TextStyle? = nil,
        compoundGraphicInstanceID: Int? = nil,
        graphicGroupID: Int? = nil
    ) {
        self.textStyle = textStyle
        self.compoundGraphicInstanceID = compoundGraphicInstanceID
        self.graphicGroupID = graphicGroupID
        self.text = text
        self.boundingBoxTopLeft = boundingBoxTopLeft
        self.boundingBoxBottomRight = boundingBoxBottomRight
        self.anchorPoint = anchorPoint
        self.anchorPointVisible = anchorPointVisible
        self.boundingBoxUnits = boundingBoxUnits
        self.anchorPointUnits = anchorPointUnits
    }
}

// MARK: - Hashable conformance for tuples

extension TextObject {
    public static func == (lhs: TextObject, rhs: TextObject) -> Bool {
        lhs.text == rhs.text &&
        lhs.boundingBoxTopLeft.column == rhs.boundingBoxTopLeft.column &&
        lhs.boundingBoxTopLeft.row == rhs.boundingBoxTopLeft.row &&
        lhs.boundingBoxBottomRight.column == rhs.boundingBoxBottomRight.column &&
        lhs.boundingBoxBottomRight.row == rhs.boundingBoxBottomRight.row &&
        lhs.anchorPoint?.column == rhs.anchorPoint?.column &&
        lhs.anchorPoint?.row == rhs.anchorPoint?.row &&
        lhs.anchorPointVisible == rhs.anchorPointVisible &&
        lhs.boundingBoxUnits == rhs.boundingBoxUnits &&
        lhs.anchorPointUnits == rhs.anchorPointUnits &&
        lhs.textStyle == rhs.textStyle &&
        lhs.compoundGraphicInstanceID == rhs.compoundGraphicInstanceID &&
        lhs.graphicGroupID == rhs.graphicGroupID
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(boundingBoxTopLeft.column)
        hasher.combine(boundingBoxTopLeft.row)
        hasher.combine(boundingBoxBottomRight.column)
        hasher.combine(boundingBoxBottomRight.row)
        hasher.combine(anchorPoint?.column)
        hasher.combine(anchorPoint?.row)
        hasher.combine(anchorPointVisible)
        hasher.combine(boundingBoxUnits)
        hasher.combine(anchorPointUnits)
        hasher.combine(textStyle)
        hasher.combine(compoundGraphicInstanceID)
        hasher.combine(graphicGroupID)
    }
}

/// Units for annotation coordinates
///
/// The Enumerated Values of Bounding Box Annotation Units (0070,0003), which
/// Anchor Point Annotation Units (0070,0004) and Graphic Annotation Units
/// (0070,0005) share (PS3.3 Table C.10-5).
///
/// Reference: PS3.3 Section C.10.5 - Graphic Annotation Module
public enum AnnotationUnits: String, Sendable, Hashable, CaseIterable {
    /// Image relative, sub-pixel: the TLHC of the TLHC pixel is 0.0\0.0, the BRHC
    /// of the BRHC pixel is Columns\Rows (Table C.10-5, Figure C.10.5-1).
    case pixel = "PIXEL"

    /// Fraction of the Specified Displayed Area: 0.0\0.0 is its TLHC and 1.0\1.0
    /// its BRHC (Table C.10-5).
    case display = "DISPLAY"

    /// Total Pixel Matrix relative, sub-pixel: the origin is the TLHC of the TLHC
    /// pixel of the Total Pixel Matrix and the BRHC of its BRHC pixel is Total
    /// Pixel Matrix Columns\Total Pixel Matrix Rows (Table C.10-5, Figure
    /// C.10.5-1b). Table C.10-5: "MATRIX may be used only if the instance
    /// referenced by Referenced Image Sequence (0008,1140) is tiled (i.e.,
    /// contains Total Pixel Matrix Columns (0048,0006) and Total Pixel Matrix
    /// Rows (0048,0007))" — whole slide images (A.32.8). Every presentation
    /// state IOD that includes C.10.5 may carry it; a renderer of an untiled
    /// image has no matrix to place it in and treats it like `pixel`.
    case matrix = "MATRIX"

    /// Whether the coordinates are relative to the image's own pixels (`pixel`,
    /// `matrix`) rather than to the Specified Displayed Area (`display`).
    public var isImageRelative: Bool {
        self != .display
    }
}
