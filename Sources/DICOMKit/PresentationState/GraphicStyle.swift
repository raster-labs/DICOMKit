// NEMA-verified: 2026a, checked 2026-09-29 — Compound Graphic Sequence (Table C.10-5, C.10.5.1.3–C.10.5.1.3.11) and the Text, Line and Fill Style Sequence Macros (Tables C.10-5a, C.10-5b, C.10-5c): attributes, Types, Enumerated Values and 1C conditions text-diffed against PS3.3 2026a, tags/keywords/VRs against PS3.6 2026a Table 6-1 (Scripts/diff_kit.py) (D39)
//
// GraphicStyle.swift
// DICOMKit
//
// The parts of the Graphic Annotation Module (PS3.3 C.10.5) that say how an
// annotation looks rather than where it is: per-object colour, line weight,
// dashing, shadow and fill (the Text, Line and Fill Style Sequence Macros), and
// the Compound Graphics — ARROW, RULER, RECTANGLE and the rest — that a viewer
// may draw as themselves instead of as the polylines and text objects that
// carry their alternate rendering (C.10.5.1.3.1).

import Foundation
import DICOMCore

// MARK: - Enumerated Values

/// Shadow Style (0070,0244) — Tables C.10-5a/5b, C.10.5.1.3.13.2.
public enum GraphicShadowStyle: String, Sendable, Hashable, CaseIterable {
    case normal = "NORMAL"
    /// A filled outline around the object whose radius is the length of the
    /// offset vector — what a halo is.
    case outlined = "OUTLINED"
    case off = "OFF"
}

/// Horizontal Alignment (0070,0242) — Table C.10-5a.
public enum TextHorizontalAlignment: String, Sendable, Hashable, CaseIterable {
    case left = "LEFT"
    case center = "CENTER"
    case right = "RIGHT"
}

/// Vertical Alignment (0070,0243) — Table C.10-5a.
public enum TextVerticalAlignment: String, Sendable, Hashable, CaseIterable {
    case top = "TOP"
    case center = "CENTER"
    case bottom = "BOTTOM"
}

/// Line Dashing Style (0070,0254) — Table C.10-5b, C.10.5.1.3.13.1.
public enum LineDashingStyle: String, Sendable, Hashable, CaseIterable {
    case solid = "SOLID"
    case dashed = "DASHED"
}

/// Fill Mode (0070,0257) — Table C.10-5c, C.10.5.1.3.14.1. `STIPPELED` is the
/// standard's own spelling of the Enumerated Value.
public enum GraphicFillMode: String, Sendable, Hashable, CaseIterable {
    case solid = "SOLID"
    case stippled = "STIPPELED"
}

/// Compound Graphic Type (0070,0294) — Table C.10-5, C.10.5.1.3.3–C.10.5.1.3.11.
public enum CompoundGraphicType: String, Sendable, Hashable, CaseIterable {
    case multiline = "MULTILINE"
    case infiniteline = "INFINITELINE"
    case cutline = "CUTLINE"
    case rangeline = "RANGELINE"
    case ruler = "RULER"
    case axis = "AXIS"
    case crosshair = "CROSSHAIR"
    /// Two points: the anchor point (where the head is), then the foot point
    /// (C.10.5.1.3.11).
    case arrow = "ARROW"
    /// Two points: TLHC and BRHC of the rectangle (C.10.5.1.3.4).
    case rectangle = "RECTANGLE"
    /// Two points: TLHC and BRHC of the bounding rectangle (C.10.5.1.3.3).
    case ellipse = "ELLIPSE"

    /// How many points Graphic Data (0070,0022) carries, where C.10.5.1.3 fixes
    /// it; MULTILINE has any even number (start and end points).
    public var requiredPointCount: Int? {
        switch self {
        case .crosshair: return 1
        case .multiline: return nil
        default: return 2
        }
    }
}

/// Compound Graphic Units (0070,0282) — Table C.10-5 enumerates PIXEL and
/// DISPLAY only (no MATRIX).
public enum CompoundGraphicUnits: String, Sendable, Hashable, CaseIterable {
    case pixel = "PIXEL"
    case display = "DISPLAY"
}

/// Tick Alignment (0070,0274) — Table C.10-5, C.10.5.1.3.8.
public enum TickAlignment: String, Sendable, Hashable, CaseIterable {
    case bottom = "BOTTOM"
    case center = "CENTER"
    case top = "TOP"
}

/// Tick Label Alignment (0070,0279) — Table C.10-5, C.10.5.1.3.8.
public enum TickLabelAlignment: String, Sendable, Hashable, CaseIterable {
    case bottom = "BOTTOM"
    case top = "TOP"
}

// MARK: - Values

/// A point in annotation units, column then row.
public struct GraphicPoint: Sendable, Hashable {
    public var column: Double
    public var row: Double

    public init(column: Double, row: Double) {
        self.column = column
        self.row = row
    }
}

/// A shadow (Shadow Style, Offset X/Y, Color CIELab Value, Opacity).
///
/// In a Text Style item the offset, colour and opacity are Type 1C, "required
/// if Shadow Style is not OFF"; in a Line Style item all five are Type 1.
public struct GraphicShadow: Sendable, Hashable {
    public var style: GraphicShadowStyle
    /// X extends to the right and Y downward, relative to the line; for
    /// OUTLINED the vector's length is the radius (C.10.5.1.3.13.2).
    public var offsetX: Double
    public var offsetY: Double
    /// Shadow Color CIELab Value (0070,0247), PCS-Values encoded per C.10.7.1.1.
    public var color: CIELabColor
    /// Shadow Opacity (0070,0258), 0.0…1.0.
    public var opacity: Double

    public init(
        style: GraphicShadowStyle,
        offsetX: Double = 0,
        offsetY: Double = 0,
        color: CIELabColor = GraphicShadow.black,
        opacity: Double = 1
    ) {
        self.style = style
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.color = color
        self.opacity = min(1, max(0, opacity))
    }

    /// No shadow.
    public static let off = GraphicShadow(style: .off)

    /// CIELab black (L* 0, a* b* 0: encoded 0, 0x8080, 0x8080).
    public static let black = CIELabColor(l: 0, a: 0x8080, b: 0x8080)
}

/// One item of the Text Style Sequence (0070,0231), Table C.10-5a.
public struct TextStyle: Sendable, Hashable {
    /// Font Name (0070,0227), Type 3.
    public var fontName: String?
    /// Font Name Type (0070,0228), Type 1C with Font Name. Defined Term ISO_32000.
    public var fontNameType: String?
    /// CSS Font Name (0070,0229), Type 1: the generic CSS family used when the
    /// named font cannot be rendered.
    public var cssFontName: String
    /// Text Color CIELab Value (0070,0241), Type 1; overrides the layer's colour.
    public var color: CIELabColor
    /// Horizontal/Vertical Alignment (0070,0242/0243): Type 1C, required when
    /// the text object has a bounding box; the builder writes LEFT/TOP there
    /// when these are nil.
    public var horizontalAlignment: TextHorizontalAlignment?
    public var verticalAlignment: TextVerticalAlignment?
    public var shadow: GraphicShadow
    public var underlined: Bool
    public var bold: Bool
    public var italic: Bool

    public init(
        fontName: String? = nil,
        fontNameType: String? = nil,
        cssFontName: String = "sans-serif",
        color: CIELabColor,
        horizontalAlignment: TextHorizontalAlignment? = nil,
        verticalAlignment: TextVerticalAlignment? = nil,
        shadow: GraphicShadow = .off,
        underlined: Bool = false,
        bold: Bool = false,
        italic: Bool = false
    ) {
        self.fontName = fontName
        self.fontNameType = fontName == nil ? nil : (fontNameType ?? "ISO_32000")
        self.cssFontName = cssFontName
        self.color = color
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.shadow = shadow
        self.underlined = underlined
        self.bold = bold
        self.italic = italic
    }
}

/// One item of the Line Style Sequence (0070,0232), Table C.10-5b.
public struct LineStyle: Sendable, Hashable {
    /// Pattern On Color CIELab Value (0070,0251), Type 1; overrides the layer's colour.
    public var onColor: CIELabColor
    /// Pattern Off Color CIELab Value (0070,0252), Type 3.
    public var offColor: CIELabColor?
    /// Pattern On Opacity (0070,0284), Type 1, 0.0…1.0.
    public var onOpacity: Double
    /// Pattern Off Opacity (0070,0285), Type 3.
    public var offOpacity: Double?
    /// Line Thickness (0070,0253), Type 1, in the object's annotation units.
    public var thickness: Double
    public var dashing: LineDashingStyle
    /// Line Pattern (0070,0255): 32 bits, 1 = foreground; Type 1C, required
    /// when dashing is DASHED (the builder writes 0xFF00FF00 when it is nil).
    public var pattern: UInt32?
    /// Shadow Style and its four companions, all Type 1 in this macro.
    public var shadow: GraphicShadow

    public init(
        onColor: CIELabColor,
        offColor: CIELabColor? = nil,
        onOpacity: Double = 1,
        offOpacity: Double? = nil,
        thickness: Double,
        dashing: LineDashingStyle = .solid,
        pattern: UInt32? = nil,
        shadow: GraphicShadow = .off
    ) {
        self.onColor = onColor
        self.offColor = offColor
        self.onOpacity = min(1, max(0, onOpacity))
        self.offOpacity = offOpacity.map { min(1, max(0, $0)) }
        self.thickness = thickness
        self.dashing = dashing
        self.pattern = pattern
        self.shadow = shadow
    }
}

/// One item of the Fill Style Sequence (0070,0233), Table C.10-5c.
public struct FillStyle: Sendable, Hashable {
    public var onColor: CIELabColor
    public var offColor: CIELabColor?
    public var onOpacity: Double
    /// Pattern Off Opacity (0070,0285) — Type 1 in this macro.
    public var offOpacity: Double
    public var mode: GraphicFillMode
    /// Fill Pattern (0070,0256): 128 bytes, a 32×32 1-bit matrix; Type 1C,
    /// required when the mode is STIPPELED.
    public var pattern: Data?

    public init(
        onColor: CIELabColor,
        offColor: CIELabColor? = nil,
        onOpacity: Double = 1,
        offOpacity: Double = 0,
        mode: GraphicFillMode = .solid,
        pattern: Data? = nil
    ) {
        self.onColor = onColor
        self.offColor = offColor
        self.onOpacity = min(1, max(0, onOpacity))
        self.offOpacity = min(1, max(0, offOpacity))
        self.mode = mode
        self.pattern = pattern
    }
}

/// One item of the Major Ticks Sequence (0070,0287).
public struct MajorTick: Sendable, Hashable {
    /// Tick Position (0070,0288), 0.0 (start point) … 1.0 (end point).
    public var position: Double
    /// Tick Label (0070,0289), SH.
    public var label: String

    public init(position: Double, label: String) {
        self.position = position
        self.label = label
    }
}

/// One item of the Compound Graphic Sequence (0070,0209), Table C.10-5.
///
/// C.10.5.1.3.1: every Compound Graphic needs an alternate rendering — one or
/// more items of the Graphic Object or Text Object Sequence carrying the same
/// ``instanceID`` — for viewers that do not draw compound graphics.
/// ``GrayscalePresentationStateBuilder/validate(_:imageSize:)`` checks it.
public struct CompoundGraphic: Sendable, Hashable {
    /// Compound Graphic Instance ID (0070,0226), UL, unique within the instance.
    public var instanceID: Int
    public var type: CompoundGraphicType
    public var units: CompoundGraphicUnits
    /// Graphic Data (0070,0022): column, row pairs.
    public var data: [Double]
    public var textStyle: TextStyle?
    public var lineStyle: LineStyle?
    /// Rotation Angle (0070,0230), degrees counterclockwise, 0…360.
    public var rotationAngle: Double?
    /// Rotation Point (0070,0273): 1C, required with an angle or for CUTLINE /
    /// INFINITELINE.
    public var rotationPoint: GraphicPoint?
    /// Gap Length (0070,0261), in DISPLAY units: 1C for CUTLINE, INFINITELINE, CROSSHAIR.
    public var gapLength: Double?
    /// Diameter of Visibility (0070,0262), DISPLAY units: 1C for CROSSHAIR.
    public var diameterOfVisibility: Double?
    /// Major Ticks Sequence: 1C for AXIS, two or more items.
    public var majorTicks: [MajorTick]
    /// Tick Alignment, Tick Label Alignment, Show Tick Label: 1C for RULER,
    /// AXIS, CROSSHAIR (the builder writes CENTER / BOTTOM / Y when nil).
    public var tickAlignment: TickAlignment?
    public var tickLabelAlignment: TickLabelAlignment?
    public var showTickLabel: Bool?
    /// Graphic Filled (0070,0024): 1C for RECTANGLE and ELLIPSE.
    public var filled: Bool
    /// Fill Style Sequence: 1C, required when filled.
    public var fillStyle: FillStyle?
    /// Graphic Group ID (0070,0295), Type 3.
    public var graphicGroupID: Int?

    public init(
        instanceID: Int,
        type: CompoundGraphicType,
        units: CompoundGraphicUnits = .pixel,
        data: [Double],
        textStyle: TextStyle? = nil,
        lineStyle: LineStyle? = nil,
        rotationAngle: Double? = nil,
        rotationPoint: GraphicPoint? = nil,
        gapLength: Double? = nil,
        diameterOfVisibility: Double? = nil,
        majorTicks: [MajorTick] = [],
        tickAlignment: TickAlignment? = nil,
        tickLabelAlignment: TickLabelAlignment? = nil,
        showTickLabel: Bool? = nil,
        filled: Bool = false,
        fillStyle: FillStyle? = nil,
        graphicGroupID: Int? = nil
    ) {
        self.instanceID = instanceID
        self.type = type
        self.units = units
        self.data = data
        self.textStyle = textStyle
        self.lineStyle = lineStyle
        self.rotationAngle = rotationAngle
        self.rotationPoint = rotationPoint
        self.gapLength = gapLength
        self.diameterOfVisibility = diameterOfVisibility
        self.majorTicks = majorTicks
        self.tickAlignment = tickAlignment
        self.tickLabelAlignment = tickLabelAlignment
        self.showTickLabel = showTickLabel
        self.filled = filled
        self.fillStyle = fillStyle
        self.graphicGroupID = graphicGroupID
    }

    /// The points of Graphic Data.
    public var points: [GraphicPoint] {
        stride(from: 0, to: data.count - 1, by: 2).map {
            GraphicPoint(column: data[$0], row: data[$0 + 1])
        }
    }

    /// What PS3.3 Table C.10-5 and C.10.5.1.3 require of this item and it does
    /// not have; empty when conformant.
    public var conformanceProblems: [String] {
        var problems: [String] = []
        let count = data.count / 2
        if data.count % 2 != 0 {
            problems.append("Graphic Data (0070,0022) of compound graphic \(instanceID) is not column\\row pairs")
        }
        if let required = type.requiredPointCount, count != required {
            problems.append("\(type.rawValue) compound graphic \(instanceID) needs \(required) point(s), has \(count) (C.10.5.1.3)")
        }
        if type == .multiline, count == 0 || count % 2 != 0 {
            problems.append("MULTILINE compound graphic \(instanceID) needs start and end point pairs (C.10.5.1.3.5)")
        }
        if type == .axis, majorTicks.count < 2 {
            problems.append("AXIS compound graphic \(instanceID): Major Ticks Sequence (0070,0287) needs two or more items (Table C.10-5)")
        }
        if let angle = rotationAngle, !(0...360).contains(angle) {
            problems.append("Rotation Angle (0070,0230) of compound graphic \(instanceID) is outside 0…360")
        }
        return problems
    }
}

// MARK: - sRGB conversion

public extension CIELabColor {
    /// The PCS-Value encoding of an sRGB colour (components 0…1), per C.10.7.1.1
    /// (L* over 0…0xFFFF, a* and b* offset so 0x8080 is 0) — the same
    /// conversion the builder applies to a layer's recommended colour.
    init(sRGBRed red: Double, green: Double, blue: Double) {
        let encoded = GrayscalePresentationStateBuilder.cieLabEncoded(from: (
            red: Int((min(1, max(0, red)) * 65535).rounded()),
            green: Int((min(1, max(0, green)) * 65535).rounded()),
            blue: Int((min(1, max(0, blue)) * 65535).rounded())))
        self.init(l: encoded[0], a: encoded[1], b: encoded[2])
    }

    /// The colour as sRGB components 0…1.
    var sRGB: (red: Double, green: Double, blue: Double) {
        let rgb = GrayscalePresentationStateBuilder.rgb(fromCIELabEncoded: [l, a, b])
            ?? (red: 0, green: 0, blue: 0)
        return (Double(rgb.red) / 65535, Double(rgb.green) / 65535, Double(rgb.blue) / 65535)
    }
}

// MARK: - Tags (PS3.6 2026a Table 6-1)

extension Tag {
    static let compoundGraphicSequence = Tag(group: 0x0070, element: 0x0209)
    static let compoundGraphicInstanceID = Tag(group: 0x0070, element: 0x0226)
    static let fontName = Tag(group: 0x0070, element: 0x0227)
    static let fontNameType = Tag(group: 0x0070, element: 0x0228)
    static let cssFontName = Tag(group: 0x0070, element: 0x0229)
    static let rotationAngle = Tag(group: 0x0070, element: 0x0230)
    static let textStyleSequence = Tag(group: 0x0070, element: 0x0231)
    static let lineStyleSequence = Tag(group: 0x0070, element: 0x0232)
    static let fillStyleSequence = Tag(group: 0x0070, element: 0x0233)
    static let textColorCIELabValue = Tag(group: 0x0070, element: 0x0241)
    static let horizontalAlignment = Tag(group: 0x0070, element: 0x0242)
    static let verticalAlignment = Tag(group: 0x0070, element: 0x0243)
    static let shadowStyle = Tag(group: 0x0070, element: 0x0244)
    static let shadowOffsetX = Tag(group: 0x0070, element: 0x0245)
    static let shadowOffsetY = Tag(group: 0x0070, element: 0x0246)
    static let shadowColorCIELabValue = Tag(group: 0x0070, element: 0x0247)
    static let underlined = Tag(group: 0x0070, element: 0x0248)
    static let bold = Tag(group: 0x0070, element: 0x0249)
    static let italic = Tag(group: 0x0070, element: 0x0250)
    static let patternOnColorCIELabValue = Tag(group: 0x0070, element: 0x0251)
    static let patternOffColorCIELabValue = Tag(group: 0x0070, element: 0x0252)
    static let lineThickness = Tag(group: 0x0070, element: 0x0253)
    static let lineDashingStyle = Tag(group: 0x0070, element: 0x0254)
    static let linePattern = Tag(group: 0x0070, element: 0x0255)
    static let fillPattern = Tag(group: 0x0070, element: 0x0256)
    static let fillMode = Tag(group: 0x0070, element: 0x0257)
    static let shadowOpacity = Tag(group: 0x0070, element: 0x0258)
    static let gapLength = Tag(group: 0x0070, element: 0x0261)
    static let diameterOfVisibility = Tag(group: 0x0070, element: 0x0262)
    static let rotationPoint = Tag(group: 0x0070, element: 0x0273)
    static let tickAlignment = Tag(group: 0x0070, element: 0x0274)
    static let showTickLabel = Tag(group: 0x0070, element: 0x0278)
    static let tickLabelAlignment = Tag(group: 0x0070, element: 0x0279)
    static let compoundGraphicUnits = Tag(group: 0x0070, element: 0x0282)
    static let patternOnOpacity = Tag(group: 0x0070, element: 0x0284)
    static let patternOffOpacity = Tag(group: 0x0070, element: 0x0285)
    static let majorTicksSequence = Tag(group: 0x0070, element: 0x0287)
    static let tickPosition = Tag(group: 0x0070, element: 0x0288)
    static let tickLabel = Tag(group: 0x0070, element: 0x0289)
    static let compoundGraphicType = Tag(group: 0x0070, element: 0x0294)
    static let graphicGroupID = Tag(group: 0x0070, element: 0x0295)
}
