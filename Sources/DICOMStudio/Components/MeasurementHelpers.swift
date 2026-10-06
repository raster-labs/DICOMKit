// MeasurementHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent measurement calculation helpers
// NEMA-verified: 2026a, checked 2026-10-05 — geometry only (PS3.3 2026a C.18.6 pixel coordinates; the physical distance uses the row and column spacing per axis as C.7.6.2 / 10.7.1.3 define them); formatLength prints the MeasurementUnit raw value, which for mm and cm is the PS3.16 2026a CID 7460 UCUM code (inches have no PS3.16 code); no coded concepts or defined terms

import Foundation

/// Platform-independent helpers for measurement geometry calculations.
///
/// Provides linear, angle, Cobb angle, and bidirectional measurement math
/// per DICOM PS3.3 C.18.6 (Spatial Coordinates) and PS3.16 TID 1500.
public enum MeasurementHelpers: Sendable {

    // MARK: - Length Measurement

    /// Computes the length between two points in pixels.
    ///
    /// - Parameters:
    ///   - start: Start point in image coordinates.
    ///   - end: End point in image coordinates.
    /// - Returns: Length in pixels.
    public static func lengthPixels(
        from start: AnnotationPoint,
        to end: AnnotationPoint
    ) -> Double {
        AnnotationHelpers.distance(from: start, to: end)
    }

    /// Computes the physical length between two points using calibration.
    ///
    /// - Parameters:
    ///   - start: Start point in image coordinates.
    ///   - end: End point in image coordinates.
    ///   - calibration: Pixel spacing calibration.
    /// - Returns: LinearMeasurementResult with pixel and physical distances.
    public static func measureLength(
        from start: AnnotationPoint,
        to end: AnnotationPoint,
        calibration: CalibrationModel
    ) -> LinearMeasurementResult {
        let pixels = lengthPixels(from: start, to: end)
        let mm: Double? = calibration.isCalibrated
            ? physicalDistance(pixelDistance: pixels, calibration: calibration, dx: end.x - start.x, dy: end.y - start.y)
            : nil
        return LinearMeasurementResult(
            lengthPixels: pixels,
            lengthMM: mm,
            startPoint: start,
            endPoint: end
        )
    }

    // MARK: - Angle Measurement

    /// Computes the angle at a vertex defined by three points.
    ///
    /// The angle is measured at `vertex` between rays to `point1` and `point2`.
    ///
    /// - Parameters:
    ///   - vertex: The vertex point.
    ///   - point1: First ray endpoint.
    ///   - point2: Second ray endpoint.
    /// - Returns: AngleMeasurementResult, or nil if degenerate.
    public static func measureAngle(
        vertex: AnnotationPoint,
        point1: AnnotationPoint,
        point2: AnnotationPoint
    ) -> AngleMeasurementResult? {
        let angle = angleBetweenRays(vertex: vertex, p1: point1, p2: point2)
        guard !angle.isNaN else { return nil }

        return AngleMeasurementResult(
            angleDegrees: angle,
            vertex: vertex,
            point1: point1,
            point2: point2
        )
    }

    /// Computes the angle between two rays emanating from a vertex.
    ///
    /// - Parameters:
    ///   - vertex: Common endpoint.
    ///   - p1: First ray endpoint.
    ///   - p2: Second ray endpoint.
    /// - Returns: Angle in degrees [0, 180].
    public static func angleBetweenRays(
        vertex: AnnotationPoint,
        p1: AnnotationPoint,
        p2: AnnotationPoint
    ) -> Double {
        let v1x = p1.x - vertex.x
        let v1y = p1.y - vertex.y
        let v2x = p2.x - vertex.x
        let v2y = p2.y - vertex.y

        let dot = v1x * v2x + v1y * v2y
        let mag1 = (v1x * v1x + v1y * v1y).squareRoot()
        let mag2 = (v2x * v2x + v2y * v2y).squareRoot()

        guard mag1 > 0 && mag2 > 0 else { return .nan }

        let cosAngle = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        return acos(cosAngle) * 180.0 / .pi
    }

    // MARK: - Cobb Angle

    /// Computes the Cobb angle between two line segments.
    ///
    /// The Cobb angle is the angle between the two lines (or their
    /// perpendiculars), commonly used for scoliosis measurement.
    ///
    /// - Parameters:
    ///   - line1Start: Start of first line.
    ///   - line1End: End of first line.
    ///   - line2Start: Start of second line.
    ///   - line2End: End of second line.
    /// - Returns: CobbAngleMeasurementResult, or nil if degenerate.
    public static func measureCobbAngle(
        line1Start: AnnotationPoint,
        line1End: AnnotationPoint,
        line2Start: AnnotationPoint,
        line2End: AnnotationPoint
    ) -> CobbAngleMeasurementResult? {
        let angle = cobbAngle(
            line1Start: line1Start, line1End: line1End,
            line2Start: line2Start, line2End: line2End
        )
        guard !angle.isNaN else { return nil }

        return CobbAngleMeasurementResult(
            angleDegrees: angle,
            line1Start: line1Start,
            line1End: line1End,
            line2Start: line2Start,
            line2End: line2End
        )
    }

    /// Computes the Cobb angle between two lines.
    ///
    /// - Returns: Angle in degrees [0, 90].
    public static func cobbAngle(
        line1Start: AnnotationPoint,
        line1End: AnnotationPoint,
        line2Start: AnnotationPoint,
        line2End: AnnotationPoint
    ) -> Double {
        let dx1 = line1End.x - line1Start.x
        let dy1 = line1End.y - line1Start.y
        let dx2 = line2End.x - line2Start.x
        let dy2 = line2End.y - line2Start.y

        let mag1 = (dx1 * dx1 + dy1 * dy1).squareRoot()
        let mag2 = (dx2 * dx2 + dy2 * dy2).squareRoot()

        guard mag1 > 0 && mag2 > 0 else { return .nan }

        let dot = dx1 * dx2 + dy1 * dy2
        let cosAngle = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        let angle = acos(cosAngle) * 180.0 / .pi

        // Cobb angle is the acute angle between the two lines
        return angle > 90 ? 180 - angle : angle
    }

    // MARK: - Bidirectional Measurement

    /// Computes a bidirectional measurement (long axis + perpendicular short axis).
    ///
    /// - Parameters:
    ///   - longStart: Long axis start point.
    ///   - longEnd: Long axis end point.
    ///   - shortStart: Short axis start point.
    ///   - shortEnd: Short axis end point.
    ///   - calibration: Pixel spacing calibration.
    /// - Returns: BidirectionalMeasurementResult.
    public static func measureBidirectional(
        longStart: AnnotationPoint,
        longEnd: AnnotationPoint,
        shortStart: AnnotationPoint,
        shortEnd: AnnotationPoint,
        calibration: CalibrationModel
    ) -> BidirectionalMeasurementResult {
        let longPixels = lengthPixels(from: longStart, to: longEnd)
        let shortPixels = lengthPixels(from: shortStart, to: shortEnd)

        let longMM: Double? = calibration.isCalibrated
            ? physicalDistance(pixelDistance: longPixels, calibration: calibration, dx: longEnd.x - longStart.x, dy: longEnd.y - longStart.y)
            : nil
        let shortMM: Double? = calibration.isCalibrated
            ? physicalDistance(pixelDistance: shortPixels, calibration: calibration, dx: shortEnd.x - shortStart.x, dy: shortEnd.y - shortStart.y)
            : nil

        return BidirectionalMeasurementResult(
            longAxisPixels: longPixels,
            shortAxisPixels: shortPixels,
            longAxisMM: longMM,
            shortAxisMM: shortMM,
            longAxisStart: longStart,
            longAxisEnd: longEnd,
            shortAxisStart: shortStart,
            shortAxisEnd: shortEnd
        )
    }

    // MARK: - Physical Distance

    /// Converts a pixel distance to physical distance in mm using anisotropic pixel spacing.
    ///
    /// - Parameters:
    ///   - pixelDistance: Distance in pixels.
    ///   - calibration: Calibration model.
    ///   - dx: Delta X in pixels (for direction-aware spacing).
    ///   - dy: Delta Y in pixels (for direction-aware spacing).
    /// - Returns: Distance in mm.
    public static func physicalDistance(
        pixelDistance: Double,
        calibration: CalibrationModel,
        dx: Double,
        dy: Double
    ) -> Double {
        guard calibration.isCalibrated else { return pixelDistance }

        // For anisotropic pixel spacing, compute direction-aware distance
        let physDx = dx * calibration.pixelSpacingColumn
        let physDy = dy * calibration.pixelSpacingRow
        return (physDx * physDx + physDy * physDy).squareRoot()
    }

    // MARK: - Unit Conversion

    /// Converts mm to the specified unit.
    ///
    /// - Parameters:
    ///   - mm: Value in millimeters.
    ///   - unit: Target unit.
    /// - Returns: Converted value.
    public static func convert(mm: Double, to unit: MeasurementUnit) -> Double {
        switch unit {
        case .millimeters:
            return mm
        case .centimeters:
            return mm / 10.0
        case .inches:
            return mm / 25.4
        case .micrometers:
            return mm * 1000.0
        }
    }

    // MARK: - Display Formatting

    /// Formats a length value for display.
    ///
    /// - Parameters:
    ///   - pixels: Length in pixels.
    ///   - mm: Length in mm (optional).
    ///   - unit: Display unit.
    /// - Returns: Formatted string.
    public static func formatLength(
        pixels: Double,
        mm: Double?,
        unit: MeasurementUnit = .millimeters
    ) -> String {
        if let mm = mm {
            let converted = convert(mm: mm, to: unit)
            return String(format: "%.1f ", converted) + unit.displaySymbol
        }
        return String(format: "%.1f px", pixels)
    }

    /// Formats an angle value for display.
    ///
    /// - Parameter degrees: Angle in degrees.
    /// - Returns: Formatted string.
    public static func formatAngle(_ degrees: Double) -> String {
        String(format: "%.1f°", degrees)
    }

    /// Returns the required number of points for a measurement tool.
    ///
    /// - Parameter toolType: The measurement tool type.
    /// - Returns: Number of points required, or nil for variable-point tools.
    public static func requiredPoints(for toolType: MeasurementToolType) -> Int? {
        switch toolType {
        case .length:
            return 2
        case .angle:
            return 3
        case .cobbAngle:
            return 4
        case .bidirectional:
            return 4
        case .marker:
            return 1
        case .arrowAnnotation:
            return 2
        case .textAnnotation:
            return 1
        case .circularROI:
            return 2
        case .ellipticalROI:
            return 4
        case .rectangularROI:
            return 2
        case .freehandROI, .polygonalROI:
            return nil  // variable
        }
    }

    /// Returns a human-readable label for a measurement tool type.
    ///
    /// - Parameter toolType: The tool type.
    /// - Returns: Display label.
    public static func toolLabel(for toolType: MeasurementToolType) -> String {
        switch toolType {
        case .length: return "Length"
        case .angle: return "Angle"
        case .cobbAngle: return "Cobb Angle"
        case .bidirectional: return "Bidirectional"
        case .ellipticalROI: return "Elliptical ROI"
        case .rectangularROI: return "Rectangular ROI"
        case .freehandROI: return "Freehand ROI"
        case .polygonalROI: return "Polygonal ROI"
        case .circularROI: return "Circular ROI"
        case .textAnnotation: return "Text"
        case .arrowAnnotation: return "Arrow"
        case .marker: return "Marker"
        }
    }

    /// Returns an SF Symbol name for a measurement tool type.
    ///
    /// - Parameter toolType: The tool type.
    /// - Returns: SF Symbol name.
    public static func toolSystemImage(for toolType: MeasurementToolType) -> String {
        switch toolType {
        case .length: return "ruler"
        case .angle: return "angle"
        case .cobbAngle: return "lines.measurement.horizontal"
        case .bidirectional: return "arrow.up.and.down.and.arrow.left.and.right"
        case .ellipticalROI: return "oval"
        case .rectangularROI: return "rectangle"
        case .freehandROI: return "scribble"
        case .polygonalROI: return "pentagon"
        case .circularROI: return "circle"
        case .textAnnotation: return "textformat"
        case .arrowAnnotation: return "arrow.right"
        case .marker: return "plus.circle"
        }
    }

    /// Computes the midpoint between two annotation points.
    ///
    /// - Parameters:
    ///   - p1: First point.
    ///   - p2: Second point.
    /// - Returns: Midpoint.
    public static func midpoint(
        _ p1: AnnotationPoint,
        _ p2: AnnotationPoint
    ) -> AnnotationPoint {
        AnnotationPoint(
            x: (p1.x + p2.x) / 2.0,
            y: (p1.y + p2.y) / 2.0
        )
    }
}
