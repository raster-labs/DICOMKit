// AnnotationHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent annotation geometry helpers
//
// NEMA-verified: 2026a, checked 2026-10-05 — point counts and geometry checked against PS3.3 2026a C.10.5.1.2: POINT one point, POLYLINE/INTERPOLATED n ≥ 2 end points, CIRCLE exactly two (centre, then a point on the circumference), ELLIPSE exactly four (major-axis end points, then minor-axis end points); the 5 labels and symbols are display text; hit testing is this app's own

import Foundation

/// Platform-independent helpers for GSPS annotation geometry calculations.
///
/// Provides geometric computations for rendering graphic and text annotations
/// per DICOM PS3.3 C.10.5.
public enum AnnotationHelpers: Sendable {

    // MARK: - Graphic Validation

    /// Validates that a graphic annotation has the correct number of points.
    ///
    /// - Parameter annotation: The graphic annotation to validate.
    /// - Returns: True if valid.
    public static func isValid(_ annotation: GraphicAnnotation) -> Bool {
        switch annotation.graphicType {
        case .point:
            return annotation.points.count == 1
        case .polyline, .interpolated:
            return annotation.points.count >= 2
        case .circle:
            return annotation.points.count == 2
        case .ellipse:
            return annotation.points.count == 4
        }
    }

    // MARK: - Circle Geometry

    /// Computes the center and radius for a circle annotation.
    ///
    /// A DICOM circle is defined by two points: center and a point on the circumference.
    ///
    /// - Parameter annotation: A circle graphic annotation.
    /// - Returns: Tuple of (center, radius), or nil if invalid.
    public static func circleParameters(_ annotation: GraphicAnnotation) -> (center: AnnotationPoint, radius: Double)? {
        guard annotation.graphicType == .circle, annotation.points.count == 2 else {
            return nil
        }
        let center = annotation.points[0]
        let edge = annotation.points[1]
        let radius = distance(from: center, to: edge)
        return (center, radius)
    }

    /// Computes the distance between two annotation points.
    ///
    /// - Parameters:
    ///   - p1: First point.
    ///   - p2: Second point.
    /// - Returns: Euclidean distance.
    public static func distance(from p1: AnnotationPoint, to p2: AnnotationPoint) -> Double {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Ellipse Geometry

    /// Computes the bounding box center and semi-axes for an ellipse annotation.
    ///
    /// A DICOM ellipse is defined by four points: two pairs of diametrically
    /// opposite points on the major and minor axes.
    ///
    /// - Parameter annotation: An ellipse graphic annotation.
    /// - Returns: Tuple of (center, semiMajor, semiMinor, rotationDegrees), or nil if invalid.
    public static func ellipseParameters(_ annotation: GraphicAnnotation) -> (center: AnnotationPoint, semiMajor: Double, semiMinor: Double, rotationDegrees: Double)? {
        guard annotation.graphicType == .ellipse, annotation.points.count == 4 else {
            return nil
        }

        // Points 0-1 define the major axis endpoints
        // Points 2-3 define the minor axis endpoints
        let majorP1 = annotation.points[0]
        let majorP2 = annotation.points[1]
        let minorP1 = annotation.points[2]
        let minorP2 = annotation.points[3]

        let center = AnnotationPoint(
            x: (majorP1.x + majorP2.x) / 2.0,
            y: (majorP1.y + majorP2.y) / 2.0
        )

        let semiMajor = distance(from: majorP1, to: majorP2) / 2.0
        let semiMinor = distance(from: minorP1, to: minorP2) / 2.0

        // Rotation angle of major axis from horizontal
        let dx = majorP2.x - majorP1.x
        let dy = majorP2.y - majorP1.y
        let radians = atan2(dy, dx)
        let degrees = radians * 180.0 / .pi

        return (center, semiMajor, semiMinor, degrees)
    }

    // MARK: - Polyline Geometry

    /// Computes the total length of a polyline annotation.
    ///
    /// - Parameter annotation: A polyline graphic annotation.
    /// - Returns: Total length, or nil if invalid.
    public static func polylineLength(_ annotation: GraphicAnnotation) -> Double? {
        guard annotation.graphicType == .polyline || annotation.graphicType == .interpolated else {
            return nil
        }
        guard annotation.points.count >= 2 else { return nil }

        var totalLength = 0.0
        for i in 1..<annotation.points.count {
            totalLength += distance(from: annotation.points[i - 1], to: annotation.points[i])
        }
        return totalLength
    }

    /// Computes the bounding box of a set of annotation points.
    ///
    /// - Parameter points: Array of annotation points.
    /// - Returns: Tuple of (minX, minY, maxX, maxY), or nil if empty.
    public static func boundingBox(of points: [AnnotationPoint]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        guard !points.isEmpty else { return nil }

        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity

        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        return (minX, minY, maxX, maxY)
    }

    // MARK: - Point Hit Testing

    /// Tests whether a point is within a given distance of a graphic annotation.
    ///
    /// - Parameters:
    ///   - point: The test point.
    ///   - annotation: The graphic annotation.
    ///   - tolerance: Hit test tolerance in pixels.
    /// - Returns: True if the point is near the annotation.
    public static func hitTest(
        point: AnnotationPoint,
        annotation: GraphicAnnotation,
        tolerance: Double = 5.0
    ) -> Bool {
        switch annotation.graphicType {
        case .point:
            guard let annotPoint = annotation.points.first else { return false }
            return distance(from: point, to: annotPoint) <= tolerance

        case .circle:
            guard let params = circleParameters(annotation) else { return false }
            let dist = distance(from: point, to: params.center)
            if annotation.filled {
                return dist <= params.radius + tolerance
            }
            return abs(dist - params.radius) <= tolerance

        case .polyline, .interpolated:
            return isNearPolyline(point: point, polylinePoints: annotation.points, tolerance: tolerance)

        case .ellipse:
            guard let params = ellipseParameters(annotation) else { return false }
            let dx = point.x - params.center.x
            let dy = point.y - params.center.y
            let radians = params.rotationDegrees * .pi / 180.0
            let cos_a = cos(-radians)
            let sin_a = sin(-radians)
            let rx = dx * cos_a - dy * sin_a
            let ry = dx * sin_a + dy * cos_a
            let a = params.semiMajor > 0 ? params.semiMajor : 1.0
            let b = params.semiMinor > 0 ? params.semiMinor : 1.0
            let normalizedDist = (rx * rx) / (a * a) + (ry * ry) / (b * b)
            if annotation.filled {
                return normalizedDist <= 1.0 + tolerance / max(a, b)
            }
            return abs(normalizedDist - 1.0) <= tolerance / max(a, b)
        }
    }

    /// Tests whether a point is near any segment of a polyline.
    ///
    /// - Parameters:
    ///   - point: The test point.
    ///   - polylinePoints: The polyline vertices.
    ///   - tolerance: Hit test tolerance.
    /// - Returns: True if near.
    public static func isNearPolyline(
        point: AnnotationPoint,
        polylinePoints: [AnnotationPoint],
        tolerance: Double
    ) -> Bool {
        guard polylinePoints.count >= 2 else { return false }

        for i in 1..<polylinePoints.count {
            let dist = distanceToSegment(
                point: point,
                segStart: polylinePoints[i - 1],
                segEnd: polylinePoints[i]
            )
            if dist <= tolerance {
                return true
            }
        }
        return false
    }

    /// Computes the distance from a point to a line segment.
    ///
    /// - Parameters:
    ///   - point: The query point.
    ///   - segStart: Segment start.
    ///   - segEnd: Segment end.
    /// - Returns: Minimum distance.
    public static func distanceToSegment(
        point: AnnotationPoint,
        segStart: AnnotationPoint,
        segEnd: AnnotationPoint
    ) -> Double {
        let dx = segEnd.x - segStart.x
        let dy = segEnd.y - segStart.y
        let lengthSq = dx * dx + dy * dy

        if lengthSq == 0 {
            return distance(from: point, to: segStart)
        }

        var t = ((point.x - segStart.x) * dx + (point.y - segStart.y) * dy) / lengthSq
        t = max(0.0, min(1.0, t))

        let projX = segStart.x + t * dx
        let projY = segStart.y + t * dy

        return distance(from: point, to: AnnotationPoint(x: projX, y: projY))
    }

    // MARK: - Text Annotation

    /// Computes the bounding box size for a text annotation.
    ///
    /// - Parameter annotation: The text annotation.
    /// - Returns: Tuple of (width, height) if bounding box is defined, nil otherwise.
    public static func textBoundingBoxSize(_ annotation: TextAnnotation) -> (width: Double, height: Double)? {
        guard let tl = annotation.boundingBoxTopLeft,
              let br = annotation.boundingBoxBottomRight else {
            return nil
        }
        return (abs(br.x - tl.x), abs(br.y - tl.y))
    }

    /// Returns a display label for a graphic type.
    ///
    /// - Parameter type: Graphic type.
    /// - Returns: Human-readable label.
    public static func graphicTypeLabel(for type: GraphicType) -> String {
        switch type {
        case .point: return "Point"
        case .polyline: return "Polyline"
        case .interpolated: return "Interpolated"
        case .circle: return "Circle"
        case .ellipse: return "Ellipse"
        }
    }

    /// Returns an SF Symbol name for a graphic type.
    ///
    /// - Parameter type: Graphic type.
    /// - Returns: SF Symbol name.
    public static func graphicTypeSystemImage(for type: GraphicType) -> String {
        switch type {
        case .point: return "circle.fill"
        case .polyline: return "line.diagonal"
        case .interpolated: return "waveform.path.ecg"
        case .circle: return "circle"
        case .ellipse: return "oval"
        }
    }
}
