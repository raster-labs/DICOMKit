// MeasurementModel.swift
// DICOMStudio
//
// DICOM Studio — Measurement and annotation tool models for Milestone 5
// NEMA-verified: 2026a, checked 2026-10-06 — MeasurementUnit raw values diffed against PS3.16 2026a CID 7460 Linear Measurement Unit: mm, cm, um are CID 7460 UCUM code values (um = "micrometer", P-STUDIO-MEASURE-UM); "in" has no PS3.16 code and is printed as a symbol only; the other enums in this file are the app's own tool model

import Foundation

// MARK: - Measurement Units

/// Unit of measurement for physical distances.
///
/// The raw values mm, cm and um are UCUM code values of PS3.16 2026a CID 7460 Linear Measurement
/// Unit (the matching area codes mm2, cm2 and um2 are CID 7461 Area Measurement Unit); "in" has
/// no PS3.16 code.
public enum MeasurementUnit: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Millimeters (UCUM: mm, PS3.16 2026a CID 7460 "millimeter").
    case millimeters = "mm"
    /// Centimeters (UCUM: cm, PS3.16 2026a CID 7460 "centimeter").
    case centimeters = "cm"
    /// Inches (no PS3.16 code; symbol only).
    case inches = "in"
    /// Micrometers (UCUM: um, PS3.16 2026a CID 7460 "micrometer"; area um2, CID 7461).
    case micrometers = "um"

    /// The symbol shown to the user ("µm" for micrometers; the raw value otherwise).
    public var displaySymbol: String {
        switch self {
        case .millimeters: return "mm"
        case .centimeters: return "cm"
        case .inches: return "in"
        case .micrometers: return "µm"
        }
    }
}

// MARK: - Measurement Tool Type

/// Types of interactive measurement tools.
public enum MeasurementToolType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Length measurement (line segment).
    case length = "LENGTH"
    /// Angle measurement (three points).
    case angle = "ANGLE"
    /// Cobb angle measurement (four points, two lines).
    case cobbAngle = "COBB_ANGLE"
    /// Bidirectional measurement (long axis + perpendicular short axis).
    case bidirectional = "BIDIRECTIONAL"
    /// Elliptical ROI.
    case ellipticalROI = "ELLIPTICAL_ROI"
    /// Rectangular ROI.
    case rectangularROI = "RECTANGULAR_ROI"
    /// Freehand ROI.
    case freehandROI = "FREEHAND_ROI"
    /// Polygonal ROI.
    case polygonalROI = "POLYGONAL_ROI"
    /// Circular ROI.
    case circularROI = "CIRCULAR_ROI"
    /// Text annotation.
    case textAnnotation = "TEXT_ANNOTATION"
    /// Arrow annotation.
    case arrowAnnotation = "ARROW_ANNOTATION"
    /// Marker/crosshair.
    case marker = "MARKER"
}

// MARK: - Calibration Source

/// Source of pixel spacing calibration.
public enum CalibrationSource: String, Sendable, Equatable, Hashable, CaseIterable {
    /// From DICOM Pixel Spacing (0028,0030).
    case pixelSpacing = "PIXEL_SPACING"
    /// From DICOM Imager Pixel Spacing (0018,1164).
    case imagerPixelSpacing = "IMAGER_PIXEL_SPACING"
    /// From Nominal Scanned Pixel Spacing (0018,2010).
    case nominalScannedPixelSpacing = "NOMINAL_SCANNED"
    /// User-defined manual calibration.
    case manual = "MANUAL"
    /// Unknown / uncalibrated.
    case unknown = "UNKNOWN"
}

// MARK: - Calibration Model

/// Pixel-to-physical space calibration data.
public struct CalibrationModel: Sendable, Equatable, Hashable {
    /// Pixel spacing in the row direction (mm/pixel).
    public let pixelSpacingRow: Double

    /// Pixel spacing in the column direction (mm/pixel).
    public let pixelSpacingColumn: Double

    /// Source of the calibration data.
    public let source: CalibrationSource

    /// Whether the calibration is valid (both spacings > 0).
    public var isCalibrated: Bool {
        pixelSpacingRow > 0 && pixelSpacingColumn > 0
    }

    /// Average pixel spacing (useful for isotropic calculations).
    public var averageSpacing: Double {
        (pixelSpacingRow + pixelSpacingColumn) / 2.0
    }

    /// Creates a new calibration model.
    public init(
        pixelSpacingRow: Double = 0.0,
        pixelSpacingColumn: Double = 0.0,
        source: CalibrationSource = .unknown
    ) {
        self.pixelSpacingRow = pixelSpacingRow
        self.pixelSpacingColumn = pixelSpacingColumn
        self.source = source
    }

    /// An uncalibrated instance.
    public static let uncalibrated = CalibrationModel()
}

// MARK: - Annotation Style

/// Visual styling for measurements and annotations.
public struct AnnotationStyle: Sendable, Equatable, Hashable {
    /// Line width in points.
    public let lineWidth: Double

    /// Red component (0.0-1.0).
    public let colorRed: Double

    /// Green component (0.0-1.0).
    public let colorGreen: Double

    /// Blue component (0.0-1.0).
    public let colorBlue: Double

    /// Opacity (0.0-1.0).
    public let opacity: Double

    /// Font size for labels (points).
    public let fontSize: Double

    /// Creates a new annotation style.
    public init(
        lineWidth: Double = 2.0,
        colorRed: Double = 1.0,
        colorGreen: Double = 1.0,
        colorBlue: Double = 0.0,
        opacity: Double = 1.0,
        fontSize: Double = 12.0
    ) {
        self.lineWidth = max(0.5, lineWidth)
        self.colorRed = max(0.0, min(1.0, colorRed))
        self.colorGreen = max(0.0, min(1.0, colorGreen))
        self.colorBlue = max(0.0, min(1.0, colorBlue))
        self.opacity = max(0.0, min(1.0, opacity))
        self.fontSize = max(6.0, fontSize)
    }

    /// Default yellow style.
    public static let defaultStyle = AnnotationStyle()

    /// Green style for active/selected measurements.
    public static let activeStyle = AnnotationStyle(
        lineWidth: 2.5,
        colorRed: 0.0,
        colorGreen: 1.0,
        colorBlue: 0.0
    )

    /// Red style for error/warning.
    public static let warningStyle = AnnotationStyle(
        colorRed: 1.0,
        colorGreen: 0.0,
        colorBlue: 0.0
    )
}

// MARK: - Measurement Result

/// Result of a linear measurement.
public struct LinearMeasurementResult: Sendable, Equatable, Hashable {
    /// Length in pixels.
    public let lengthPixels: Double

    /// Length in physical units (mm).
    public let lengthMM: Double?

    /// Start point (image coordinates).
    public let startPoint: AnnotationPoint

    /// End point (image coordinates).
    public let endPoint: AnnotationPoint

    /// Creates a new linear measurement result.
    public init(
        lengthPixels: Double,
        lengthMM: Double?,
        startPoint: AnnotationPoint,
        endPoint: AnnotationPoint
    ) {
        self.lengthPixels = lengthPixels
        self.lengthMM = lengthMM
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
}

/// Result of an angle measurement.
public struct AngleMeasurementResult: Sendable, Equatable, Hashable {
    /// Angle in degrees.
    public let angleDegrees: Double

    /// Vertex point.
    public let vertex: AnnotationPoint

    /// First ray endpoint.
    public let point1: AnnotationPoint

    /// Second ray endpoint.
    public let point2: AnnotationPoint

    /// Creates a new angle measurement result.
    public init(
        angleDegrees: Double,
        vertex: AnnotationPoint,
        point1: AnnotationPoint,
        point2: AnnotationPoint
    ) {
        self.angleDegrees = angleDegrees
        self.vertex = vertex
        self.point1 = point1
        self.point2 = point2
    }
}

/// Result of a Cobb angle measurement.
public struct CobbAngleMeasurementResult: Sendable, Equatable, Hashable {
    /// Cobb angle in degrees.
    public let angleDegrees: Double

    /// First line start point.
    public let line1Start: AnnotationPoint

    /// First line end point.
    public let line1End: AnnotationPoint

    /// Second line start point.
    public let line2Start: AnnotationPoint

    /// Second line end point.
    public let line2End: AnnotationPoint

    /// Creates a new Cobb angle measurement result.
    public init(
        angleDegrees: Double,
        line1Start: AnnotationPoint,
        line1End: AnnotationPoint,
        line2Start: AnnotationPoint,
        line2End: AnnotationPoint
    ) {
        self.angleDegrees = angleDegrees
        self.line1Start = line1Start
        self.line1End = line1End
        self.line2Start = line2Start
        self.line2End = line2End
    }
}

/// Result of a bidirectional measurement.
public struct BidirectionalMeasurementResult: Sendable, Equatable, Hashable {
    /// Long axis length in pixels.
    public let longAxisPixels: Double

    /// Short axis length in pixels.
    public let shortAxisPixels: Double

    /// Long axis length in mm.
    public let longAxisMM: Double?

    /// Short axis length in mm.
    public let shortAxisMM: Double?

    /// Long axis start point.
    public let longAxisStart: AnnotationPoint

    /// Long axis end point.
    public let longAxisEnd: AnnotationPoint

    /// Short axis start point.
    public let shortAxisStart: AnnotationPoint

    /// Short axis end point.
    public let shortAxisEnd: AnnotationPoint

    /// Creates a new bidirectional measurement result.
    public init(
        longAxisPixels: Double,
        shortAxisPixels: Double,
        longAxisMM: Double?,
        shortAxisMM: Double?,
        longAxisStart: AnnotationPoint,
        longAxisEnd: AnnotationPoint,
        shortAxisStart: AnnotationPoint,
        shortAxisEnd: AnnotationPoint
    ) {
        self.longAxisPixels = longAxisPixels
        self.shortAxisPixels = shortAxisPixels
        self.longAxisMM = longAxisMM
        self.shortAxisMM = shortAxisMM
        self.longAxisStart = longAxisStart
        self.longAxisEnd = longAxisEnd
        self.shortAxisStart = shortAxisStart
        self.shortAxisEnd = shortAxisEnd
    }
}

// MARK: - Measurement Entry

/// A persisted measurement with metadata.
public struct MeasurementEntry: Identifiable, Sendable, Equatable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Type of measurement tool used.
    public let toolType: MeasurementToolType

    /// Points defining the measurement (image coordinates).
    public let points: [AnnotationPoint]

    /// Display label or description.
    public let label: String

    /// Visual style.
    public let style: AnnotationStyle

    /// Whether this measurement is visible.
    public let isVisible: Bool

    /// Whether this measurement is locked (non-editable).
    public let isLocked: Bool

    /// SOP Instance UID of the image this measurement belongs to.
    public let sopInstanceUID: String

    /// Frame number (for multi-frame images).
    public let frameNumber: Int

    /// Creation timestamp.
    public let createdAt: Date

    /// Creates a new measurement entry.
    public init(
        id: UUID = UUID(),
        toolType: MeasurementToolType,
        points: [AnnotationPoint],
        label: String = "",
        style: AnnotationStyle = .defaultStyle,
        isVisible: Bool = true,
        isLocked: Bool = false,
        sopInstanceUID: String = "",
        frameNumber: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.toolType = toolType
        self.points = points
        self.label = label
        self.style = style
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.sopInstanceUID = sopInstanceUID
        self.frameNumber = frameNumber
        self.createdAt = createdAt
    }

    /// Returns a copy with updated visibility.
    public func withVisibility(_ visible: Bool) -> MeasurementEntry {
        MeasurementEntry(
            id: id, toolType: toolType, points: points, label: label,
            style: style, isVisible: visible, isLocked: isLocked,
            sopInstanceUID: sopInstanceUID, frameNumber: frameNumber, createdAt: createdAt
        )
    }

    /// Returns a copy with updated lock state.
    public func withLocked(_ locked: Bool) -> MeasurementEntry {
        MeasurementEntry(
            id: id, toolType: toolType, points: points, label: label,
            style: style, isVisible: isVisible, isLocked: locked,
            sopInstanceUID: sopInstanceUID, frameNumber: frameNumber, createdAt: createdAt
        )
    }

    /// Returns a copy with updated label.
    public func withLabel(_ newLabel: String) -> MeasurementEntry {
        MeasurementEntry(
            id: id, toolType: toolType, points: points, label: newLabel,
            style: style, isVisible: isVisible, isLocked: isLocked,
            sopInstanceUID: sopInstanceUID, frameNumber: frameNumber, createdAt: createdAt
        )
    }

    /// Returns a copy with updated style.
    public func withStyle(_ newStyle: AnnotationStyle) -> MeasurementEntry {
        MeasurementEntry(
            id: id, toolType: toolType, points: points, label: label,
            style: newStyle, isVisible: isVisible, isLocked: isLocked,
            sopInstanceUID: sopInstanceUID, frameNumber: frameNumber, createdAt: createdAt
        )
    }
}

// MARK: - Undo Action

/// An undoable measurement action.
public enum MeasurementAction: Sendable, Equatable, Hashable {
    /// A measurement was added.
    case add(MeasurementEntry)
    /// A measurement was removed.
    case remove(MeasurementEntry)
    /// A measurement was updated (old → new).
    case update(old: MeasurementEntry, new: MeasurementEntry)
}
