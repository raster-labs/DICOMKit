// ShutterHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent shutter geometry helpers
//
// NEMA-verified: 2026a, checked 2026-10-05 — geometry checked against PS3.3 2026a C.7.6.11: rectangle edges inclusive (left/right as column, upper/lower as row), circle by centre (row, column) and radius, polygon by vertices, several shapes ANDed so "the least amount of image remaining shall be visible" (isPixelVisible); normalizedShutterGray maps Shutter Presentation Value (0018,1622) 0000H–FFFFH to 0…1; the 4 shape labels are display text; bitmap shutters (C.7.6.15) need overlay data and are not tested here

import Foundation

/// Platform-independent helpers for display shutter geometry calculations.
///
/// Provides hit testing, overlap detection, and shutter region computation
/// per DICOM PS3.3 C.7.6.11.
public enum ShutterHelpers: Sendable {

    // MARK: - Point-in-Shutter

    /// Tests whether a pixel is inside the visible region of a rectangular shutter.
    ///
    /// - Parameters:
    ///   - row: Pixel row.
    ///   - column: Pixel column.
    ///   - shutter: The rectangular shutter.
    /// - Returns: True if the pixel is inside the visible region.
    public static func isInsideRectangular(row: Int, column: Int, shutter: RectangularShutter) -> Bool {
        row >= shutter.top && row <= shutter.bottom &&
        column >= shutter.left && column <= shutter.right
    }

    /// Tests whether a pixel is inside the visible region of a circular shutter.
    ///
    /// - Parameters:
    ///   - row: Pixel row.
    ///   - column: Pixel column.
    ///   - shutter: The circular shutter.
    /// - Returns: True if the pixel is inside the visible region.
    public static func isInsideCircular(row: Int, column: Int, shutter: CircularShutter) -> Bool {
        let dr = Double(row - shutter.centerRow)
        let dc = Double(column - shutter.centerColumn)
        let distSq = dr * dr + dc * dc
        let radiusSq = Double(shutter.radius * shutter.radius)
        return distSq <= radiusSq
    }

    /// Tests whether a pixel is inside a polygonal shutter using ray casting.
    ///
    /// - Parameters:
    ///   - row: Pixel row.
    ///   - column: Pixel column.
    ///   - shutter: The polygonal shutter.
    /// - Returns: True if the pixel is inside the visible region.
    public static func isInsidePolygonal(row: Int, column: Int, shutter: PolygonalShutter) -> Bool {
        let x = Double(column)
        let y = Double(row)
        return isPointInPolygon(x: x, y: y, vertices: shutter.vertices)
    }

    /// Point-in-polygon test using the ray casting algorithm.
    ///
    /// - Parameters:
    ///   - x: X coordinate (column).
    ///   - y: Y coordinate (row).
    ///   - vertices: Polygon vertices.
    /// - Returns: True if the point is inside the polygon.
    public static func isPointInPolygon(x: Double, y: Double, vertices: [AnnotationPoint]) -> Bool {
        guard vertices.count >= 3 else { return false }

        var inside = false
        var j = vertices.count - 1

        for i in 0..<vertices.count {
            let xi = vertices[i].x
            let yi = vertices[i].y
            let xj = vertices[j].x
            let yj = vertices[j].y

            let intersect = ((yi > y) != (yj > y)) &&
                (x < (xj - xi) * (y - yi) / (yj - yi) + xi)

            if intersect {
                inside = !inside
            }
            j = i
        }

        return inside
    }

    // MARK: - Combined Shutter Test

    /// Tests whether a pixel is visible through all shutters in a shutter model.
    ///
    /// All shutter shapes are ANDed together—a pixel is visible only if it
    /// passes all active shutter tests.
    ///
    /// - Parameters:
    ///   - row: Pixel row.
    ///   - column: Pixel column.
    ///   - shutter: The shutter model with all shapes.
    /// - Returns: True if the pixel is visible.
    public static func isPixelVisible(row: Int, column: Int, shutter: ShutterModel) -> Bool {
        guard shutter.hasShutter else { return true }

        for shape in shutter.shapes {
            switch shape {
            case .rectangular:
                if let rect = shutter.rectangular {
                    if !isInsideRectangular(row: row, column: column, shutter: rect) {
                        return false
                    }
                }
            case .circular:
                if let circ = shutter.circular {
                    if !isInsideCircular(row: row, column: column, shutter: circ) {
                        return false
                    }
                }
            case .polygonal:
                if let poly = shutter.polygonal {
                    if !isInsidePolygonal(row: row, column: column, shutter: poly) {
                        return false
                    }
                }
            case .bitmap:
                break // Bitmap shutters require overlay data, not testable from geometry alone
            }
        }

        return true
    }

    // MARK: - Shutter Validation

    /// Validates that a shutter model has consistent shapes and data.
    ///
    /// - Parameter shutter: The shutter model to validate.
    /// - Returns: True if valid.
    public static func isValid(_ shutter: ShutterModel) -> Bool {
        for shape in shutter.shapes {
            switch shape {
            case .rectangular:
                guard let rect = shutter.rectangular, rect.isValid else { return false }
            case .circular:
                guard let circ = shutter.circular, circ.isValid else { return false }
            case .polygonal:
                guard let poly = shutter.polygonal, poly.isValid else { return false }
            case .bitmap:
                guard let bmp = shutter.bitmap, bmp.isValid else { return false }
            }
        }
        return true
    }

    // MARK: - Shutter Info

    /// Returns a display label for a shutter shape.
    ///
    /// - Parameter shape: Shutter shape.
    /// - Returns: Human-readable label.
    public static func shapeLabel(for shape: ShutterShape) -> String {
        switch shape {
        case .rectangular: return "Rectangular"
        case .circular: return "Circular"
        case .polygonal: return "Polygonal"
        case .bitmap: return "Bitmap"
        }
    }

    /// Returns an SF Symbol name for a shutter shape.
    ///
    /// - Parameter shape: Shutter shape.
    /// - Returns: SF Symbol name.
    public static func shapeSystemImage(for shape: ShutterShape) -> String {
        switch shape {
        case .rectangular: return "rectangle"
        case .circular: return "circle"
        case .polygonal: return "pentagon"
        case .bitmap: return "square.grid.3x3"
        }
    }

    /// Returns a formatted description of a shutter model.
    ///
    /// - Parameter shutter: The shutter model.
    /// - Returns: Human-readable description string.
    public static func shutterDescription(_ shutter: ShutterModel) -> String {
        guard shutter.hasShutter else { return "No shutter" }
        let labels = shutter.shapes.map { shapeLabel(for: $0) }
        return labels.joined(separator: " + ")
    }

    /// Converts a shutter presentation value to a normalized gray level [0, 1].
    ///
    /// - Parameter value: Shutter presentation value (0-65535).
    /// - Returns: Normalized gray level.
    public static func normalizedShutterGray(_ value: Int) -> Double {
        let clamped = max(0, min(65535, value))
        return Double(clamped) / 65535.0
    }
}
