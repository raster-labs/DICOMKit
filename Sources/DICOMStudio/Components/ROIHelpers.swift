// ROIHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent ROI geometry and statistics helpers
// NEMA-verified: 2026a, checked 2026-10-05 — geometry and statistics only; area text now prints the PS3.16 2026a CID 7461 UCUM code with the symbol as dicom-measure does ("250.0 mm2 (mm²)", cm2; inches and pixels have no PS3.16 code and print the symbol alone); µm / um2 needs a MeasurementUnit case (P-STUDIO-MEASURE-UM)

import Foundation

/// Platform-independent helpers for ROI geometry calculations and pixel statistics.
///
/// Provides area, perimeter, and statistical computations for various ROI shapes
/// per DICOM PS3.3 C.18.6 (Spatial Coordinates).
public enum ROIHelpers: Sendable {

    // MARK: - Circular ROI

    /// Computes the area of a circular ROI in pixels².
    ///
    /// - Parameters:
    ///   - center: Circle center.
    ///   - edge: Point on the circumference.
    /// - Returns: Area in pixels².
    public static func circleAreaPixels(
        center: AnnotationPoint,
        edge: AnnotationPoint
    ) -> Double {
        let r = AnnotationHelpers.distance(from: center, to: edge)
        return .pi * r * r
    }

    /// Computes the perimeter of a circular ROI in pixels.
    ///
    /// - Parameters:
    ///   - center: Circle center.
    ///   - edge: Point on the circumference.
    /// - Returns: Perimeter in pixels.
    public static func circlePerimeterPixels(
        center: AnnotationPoint,
        edge: AnnotationPoint
    ) -> Double {
        let r = AnnotationHelpers.distance(from: center, to: edge)
        return 2.0 * .pi * r
    }

    // MARK: - Elliptical ROI

    /// Computes the area of an elliptical ROI in pixels².
    ///
    /// An ellipse is defined by four points: two pairs of diametrically
    /// opposite points on the major and minor axes.
    ///
    /// - Parameter points: Array of 4 points [majorP1, majorP2, minorP1, minorP2].
    /// - Returns: Area in pixels², or nil if invalid.
    public static func ellipseAreaPixels(points: [AnnotationPoint]) -> Double? {
        guard points.count == 4 else { return nil }
        let semiMajor = AnnotationHelpers.distance(from: points[0], to: points[1]) / 2.0
        let semiMinor = AnnotationHelpers.distance(from: points[2], to: points[3]) / 2.0
        return .pi * semiMajor * semiMinor
    }

    /// Computes the approximate perimeter of an ellipse (Ramanujan's approximation).
    ///
    /// - Parameter points: Array of 4 points [majorP1, majorP2, minorP1, minorP2].
    /// - Returns: Perimeter in pixels, or nil if invalid.
    public static func ellipsePerimeterPixels(points: [AnnotationPoint]) -> Double? {
        guard points.count == 4 else { return nil }
        let a = AnnotationHelpers.distance(from: points[0], to: points[1]) / 2.0
        let b = AnnotationHelpers.distance(from: points[2], to: points[3]) / 2.0
        // Ramanujan's approximation
        let h = ((a - b) * (a - b)) / ((a + b) * (a + b))
        return .pi * (a + b) * (1.0 + 3.0 * h / (10.0 + (4.0 - 3.0 * h).squareRoot()))
    }

    // MARK: - Rectangular ROI

    /// Computes the area of a rectangular ROI in pixels².
    ///
    /// - Parameters:
    ///   - topLeft: Top-left corner.
    ///   - bottomRight: Bottom-right corner.
    /// - Returns: Area in pixels².
    public static func rectangleAreaPixels(
        topLeft: AnnotationPoint,
        bottomRight: AnnotationPoint
    ) -> Double {
        let width = abs(bottomRight.x - topLeft.x)
        let height = abs(bottomRight.y - topLeft.y)
        return width * height
    }

    /// Computes the perimeter of a rectangular ROI in pixels.
    ///
    /// - Parameters:
    ///   - topLeft: Top-left corner.
    ///   - bottomRight: Bottom-right corner.
    /// - Returns: Perimeter in pixels.
    public static func rectanglePerimeterPixels(
        topLeft: AnnotationPoint,
        bottomRight: AnnotationPoint
    ) -> Double {
        let width = abs(bottomRight.x - topLeft.x)
        let height = abs(bottomRight.y - topLeft.y)
        return 2.0 * (width + height)
    }

    // MARK: - Polygon / Freehand ROI

    /// Computes the area of a polygon using the shoelace formula.
    ///
    /// - Parameter points: Polygon vertices (at least 3).
    /// - Returns: Area in pixels², or nil if fewer than 3 points.
    public static func polygonAreaPixels(points: [AnnotationPoint]) -> Double? {
        guard points.count >= 3 else { return nil }

        var area = 0.0
        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += points[i].x * points[j].y
            area -= points[j].x * points[i].y
        }
        return abs(area) / 2.0
    }

    /// Computes the perimeter of a polygon.
    ///
    /// - Parameter points: Polygon vertices (at least 2).
    /// - Returns: Perimeter in pixels, or nil if fewer than 2 points.
    public static func polygonPerimeterPixels(points: [AnnotationPoint]) -> Double? {
        guard points.count >= 2 else { return nil }

        var perimeter = 0.0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            perimeter += AnnotationHelpers.distance(from: points[i], to: points[j])
        }
        return perimeter
    }

    // MARK: - Point-in-ROI Tests

    /// Tests whether a point is inside a polygon (ray-casting algorithm).
    ///
    /// - Parameters:
    ///   - point: Test point.
    ///   - polygon: Polygon vertices.
    /// - Returns: True if inside.
    public static func isPointInPolygon(
        point: AnnotationPoint,
        polygon: [AnnotationPoint]
    ) -> Bool {
        guard polygon.count >= 3 else { return false }

        var inside = false
        let n = polygon.count
        var j = n - 1

        for i in 0..<n {
            let pi = polygon[i]
            let pj = polygon[j]

            if (pi.y > point.y) != (pj.y > point.y) {
                let intersectX = (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x
                if point.x < intersectX {
                    inside = !inside
                }
            }
            j = i
        }

        return inside
    }

    /// Tests whether a point is inside a circle.
    ///
    /// - Parameters:
    ///   - point: Test point.
    ///   - center: Circle center.
    ///   - edge: Point on circumference.
    /// - Returns: True if inside.
    public static func isPointInCircle(
        point: AnnotationPoint,
        center: AnnotationPoint,
        edge: AnnotationPoint
    ) -> Bool {
        let radius = AnnotationHelpers.distance(from: center, to: edge)
        let dist = AnnotationHelpers.distance(from: point, to: center)
        return dist <= radius
    }

    /// Tests whether a point is inside a rectangle.
    ///
    /// - Parameters:
    ///   - point: Test point.
    ///   - topLeft: Top-left corner.
    ///   - bottomRight: Bottom-right corner.
    /// - Returns: True if inside.
    public static func isPointInRectangle(
        point: AnnotationPoint,
        topLeft: AnnotationPoint,
        bottomRight: AnnotationPoint
    ) -> Bool {
        let minX = min(topLeft.x, bottomRight.x)
        let maxX = max(topLeft.x, bottomRight.x)
        let minY = min(topLeft.y, bottomRight.y)
        let maxY = max(topLeft.y, bottomRight.y)
        return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    /// Tests whether a point is inside an ellipse.
    ///
    /// - Parameters:
    ///   - point: Test point.
    ///   - ellipsePoints: 4-point ellipse definition.
    /// - Returns: True if inside.
    public static func isPointInEllipse(
        point: AnnotationPoint,
        ellipsePoints: [AnnotationPoint]
    ) -> Bool {
        guard ellipsePoints.count == 4 else { return false }

        let cx = (ellipsePoints[0].x + ellipsePoints[1].x) / 2.0
        let cy = (ellipsePoints[0].y + ellipsePoints[1].y) / 2.0
        let a = AnnotationHelpers.distance(from: ellipsePoints[0], to: ellipsePoints[1]) / 2.0
        let b = AnnotationHelpers.distance(from: ellipsePoints[2], to: ellipsePoints[3]) / 2.0

        guard a > 0 && b > 0 else { return false }

        // Rotation angle of major axis
        let dx = ellipsePoints[1].x - ellipsePoints[0].x
        let dy = ellipsePoints[1].y - ellipsePoints[0].y
        let angle = atan2(dy, dx)

        let cos_a = cos(-angle)
        let sin_a = sin(-angle)
        let px = point.x - cx
        let py = point.y - cy
        let rx = px * cos_a - py * sin_a
        let ry = px * sin_a + py * cos_a

        return (rx * rx) / (a * a) + (ry * ry) / (b * b) <= 1.0
    }

    // MARK: - Pixel Statistics

    /// Computes statistics for an array of pixel values.
    ///
    /// - Parameter values: Pixel values inside the ROI.
    /// - Returns: Tuple of (mean, stdDev, min, max).
    public static func computePixelStatistics(
        values: [Double]
    ) -> (mean: Double, stdDev: Double, minimum: Double, maximum: Double) {
        guard !values.isEmpty else { return (0, 0, 0, 0) }

        let count = Double(values.count)
        let sum = values.reduce(0, +)
        let mean = sum / count

        var minVal = Double.infinity
        var maxVal = -Double.infinity
        var sumSquaredDiff = 0.0

        for v in values {
            minVal = min(minVal, v)
            maxVal = max(maxVal, v)
            let diff = v - mean
            sumSquaredDiff += diff * diff
        }

        let stdDev = (sumSquaredDiff / count).squareRoot()
        return (mean, stdDev, minVal, maxVal)
    }

    // MARK: - Physical Conversions

    /// Converts a pixel area to physical area in mm².
    ///
    /// - Parameters:
    ///   - pixelArea: Area in pixels².
    ///   - calibration: Calibration model.
    /// - Returns: Area in mm², or nil if uncalibrated.
    public static func physicalArea(
        pixelArea: Double,
        calibration: CalibrationModel
    ) -> Double? {
        guard calibration.isCalibrated else { return nil }
        return pixelArea * calibration.pixelSpacingRow * calibration.pixelSpacingColumn
    }

    /// Converts a pixel perimeter to physical perimeter in mm.
    ///
    /// Uses average pixel spacing for an approximation.
    ///
    /// - Parameters:
    ///   - pixelPerimeter: Perimeter in pixels.
    ///   - calibration: Calibration model.
    /// - Returns: Perimeter in mm, or nil if uncalibrated.
    public static func physicalPerimeter(
        pixelPerimeter: Double,
        calibration: CalibrationModel
    ) -> Double? {
        guard calibration.isCalibrated else { return nil }
        return pixelPerimeter * calibration.averageSpacing
    }

    // MARK: - Display Formatting

    /// Returns a human-readable label for an ROI type.
    ///
    /// - Parameter roiType: The ROI type.
    /// - Returns: Display label.
    public static func roiTypeLabel(for roiType: ROIType) -> String {
        switch roiType {
        case .elliptical: return "Elliptical ROI"
        case .rectangular: return "Rectangular ROI"
        case .freehand: return "Freehand ROI"
        case .polygonal: return "Polygonal ROI"
        case .circular: return "Circular ROI"
        }
    }

    /// UCUM code for the area unit of a display unit (PS3.16 CID 7461), or nil when the
    /// standard has no code (inches).
    static func ucumAreaCode(for unit: MeasurementUnit) -> String? {
        switch unit {
        case .millimeters: return "mm2"
        case .centimeters: return "cm2"
        case .inches: return nil
        }
    }

    /// Area unit text as dicom-measure prints it: the UCUM code with the display symbol in
    /// parentheses ("mm2 (mm²)"), or the symbol alone when there is no code.
    static func areaUnitText(for unit: MeasurementUnit) -> String {
        let symbol: String
        switch unit {
        case .millimeters: symbol = "mm²"
        case .centimeters: symbol = "cm²"
        case .inches: symbol = "in²"
        }
        guard let code = ucumAreaCode(for: unit) else { return symbol }
        return "\(code) (\(symbol))"
    }

    /// Formats area for display.
    ///
    /// - Parameters:
    ///   - pixelArea: Area in pixels².
    ///   - physicalArea: Area in mm² (optional).
    ///   - unit: Display unit.
    /// - Returns: Formatted string, e.g. "250.0 mm2 (mm²)".
    public static func formatArea(
        pixelArea: Double,
        physicalArea: Double?,
        unit: MeasurementUnit = .millimeters
    ) -> String {
        if let phys = physicalArea {
            switch unit {
            case .millimeters:
                return String(format: "%.1f ", phys) + areaUnitText(for: unit)
            case .centimeters:
                return String(format: "%.2f ", phys / 100.0) + areaUnitText(for: unit)
            case .inches:
                return String(format: "%.3f ", phys / 645.16) + areaUnitText(for: unit)
            }
        }
        return String(format: "%.0f px²", pixelArea)
    }

    /// Formats ROI statistics for display.
    ///
    /// - Parameter statistics: The ROI statistics.
    /// - Returns: Multi-line summary string.
    public static func formatStatistics(_ statistics: ROIStatistics) -> String {
        var lines: [String] = []
        lines.append(String(format: "Mean: %.1f", statistics.mean))
        lines.append(String(format: "Std Dev: %.1f", statistics.standardDeviation))
        lines.append(String(format: "Min: %.1f", statistics.minimum))
        lines.append(String(format: "Max: %.1f", statistics.maximum))
        lines.append("Pixels: \(statistics.areaPixels)")
        if let area = statistics.areaMM2 {
            lines.append(String(format: "Area: %.1f ", area) + areaUnitText(for: .millimeters))
        }
        if let perimeter = statistics.perimeterMM {
            lines.append(String(format: "Perimeter: %.1f mm", perimeter))
        }
        return lines.joined(separator: "\n")
    }
}
