// NEMA-verified: 2026a, checked 2026-09-29 — PS3.3 2026a Table C.7-17a: the shape is the visible region, origin 1,1; Shutter Presentation Color CIELab Value (0018,1624) per Table C.11.12-1 and C.10.7.1.1
//
// DisplayShutter.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-04.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Display shutter for masking image regions
///
/// A shutter shape marks the part of the image that stays visible; the pixels
/// outside it are neutralised with the Shutter Presentation Value (PS3.3 C.7.6.11).
/// Geometry is in row/column image coordinates with origin 1,1.
///
/// Reference: PS3.3 Section C.7.6.11 - Display Shutter Module
public enum DisplayShutter: Sendable, Hashable {
    /// Rectangular shutter
    case rectangular(left: Int, right: Int, top: Int, bottom: Int, presentationValue: Int?)
    
    /// Circular shutter
    case circular(centerColumn: Int, centerRow: Int, radius: Int, presentationValue: Int?)
    
    /// Polygonal shutter
    case polygonal(vertices: [(column: Int, row: Int)], presentationValue: Int?)
    
    /// Bitmap shutter (overlay group)
    case bitmap(overlayGroup: Int, presentationValue: Int?)
    
    /// Presentation value to use for shuttered area (grayscale value)
    public var presentationValue: Int? {
        switch self {
        case .rectangular(_, _, _, _, let value),
             .circular(_, _, _, let value),
             .polygonal(_, let value),
             .bitmap(_, let value):
            return value
        }
    }
    
    /// Check if a point is inside the shutter shape (the visible region)
    ///
    /// - Parameters:
    ///   - column: Column coordinate (1-based)
    ///   - row: Row coordinate (1-based)
    /// - Returns: true if the point is inside the shape and therefore stays visible
    public func contains(column: Int, row: Int) -> Bool {
        switch self {
        case .rectangular(let left, let right, let top, let bottom, _):
            // Inside if within bounds
            return column >= left && column <= right && row >= top && row <= bottom
            
        case .circular(let centerColumn, let centerRow, let radius, _):
            // Inside if distance from center is less than radius
            let dx = Double(column - centerColumn)
            let dy = Double(row - centerRow)
            let distance = sqrt(dx * dx + dy * dy)
            return distance <= Double(radius)
            
        case .polygonal(let vertices, _):
            // Use ray casting algorithm to determine if point is inside polygon
            return isPointInPolygon(column: column, row: row, vertices: vertices)
            
        case .bitmap:
            // Bitmap shutter requires overlay data to determine
            // This would need to be evaluated with the actual overlay
            return false
        }
    }
    
    /// Ray casting algorithm to determine if a point is inside a polygon
    private func isPointInPolygon(column: Int, row: Int, vertices: [(column: Int, row: Int)]) -> Bool {
        guard vertices.count >= 3 else {
            return false
        }
        
        var inside = false
        let x = Double(column)
        let y = Double(row)
        
        var j = vertices.count - 1
        for i in 0..<vertices.count {
            let xi = Double(vertices[i].column)
            let yi = Double(vertices[i].row)
            let xj = Double(vertices[j].column)
            let yj = Double(vertices[j].row)
            
            let intersect = ((yi > y) != (yj > y)) &&
                           (x < (xj - xi) * (y - yi) / (yj - yi) + xi)
            
            if intersect {
                inside.toggle()
            }
            
            j = i
        }
        
        return inside
    }
}

// MARK: - Hashable conformance for vertex tuples

extension DisplayShutter {
    public static func == (lhs: DisplayShutter, rhs: DisplayShutter) -> Bool {
        switch (lhs, rhs) {
        case (.rectangular(let l1, let r1, let t1, let b1, let v1),
              .rectangular(let l2, let r2, let t2, let b2, let v2)):
            return l1 == l2 && r1 == r2 && t1 == t2 && b1 == b2 && v1 == v2
            
        case (.circular(let c1, let r1, let rad1, let v1),
              .circular(let c2, let r2, let rad2, let v2)):
            return c1 == c2 && r1 == r2 && rad1 == rad2 && v1 == v2
            
        case (.polygonal(let v1, let pv1), .polygonal(let v2, let pv2)):
            guard v1.count == v2.count && pv1 == pv2 else {
                return false
            }
            for i in 0..<v1.count {
                if v1[i].column != v2[i].column || v1[i].row != v2[i].row {
                    return false
                }
            }
            return true
            
        case (.bitmap(let g1, let v1), .bitmap(let g2, let v2)):
            return g1 == g2 && v1 == v2
            
        default:
            return false
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .rectangular(let left, let right, let top, let bottom, let value):
            hasher.combine("rectangular")
            hasher.combine(left)
            hasher.combine(right)
            hasher.combine(top)
            hasher.combine(bottom)
            hasher.combine(value)
            
        case .circular(let centerColumn, let centerRow, let radius, let value):
            hasher.combine("circular")
            hasher.combine(centerColumn)
            hasher.combine(centerRow)
            hasher.combine(radius)
            hasher.combine(value)
            
        case .polygonal(let vertices, let value):
            hasher.combine("polygonal")
            for vertex in vertices {
                hasher.combine(vertex.column)
                hasher.combine(vertex.row)
            }
            hasher.combine(value)
            
        case .bitmap(let overlayGroup, let value):
            hasher.combine("bitmap")
            hasher.combine(overlayGroup)
            hasher.combine(value)
        }
    }
}

// MARK: - Shutter Presentation Color CIELab Value

/// The colour a shutter paints the occluded pixels with on a colour display.
///
/// Shutter Presentation Color CIELab Value (0018,1624) is one attribute of the
/// data set, not of each shape, so it lives on the presentation state next to
/// the `shutters` array rather than inside ``DisplayShutter``. It is Type 3 in
/// the Display Shutter Macro (Table C.7-17a) and the Presentation State Shutter
/// Module (Table C.11.12-1) makes it Type 1C: "Required if the Display Shutter
/// Module or Bitmap Display Shutter Module is present and the SOP Class is other
/// than Grayscale Softcopy Presentation State Storage". The three values are
/// encoded per C.10.7.1.1 — the same encoding ``CIELabColor`` already holds.
extension CIELabColor {

    /// The three unsigned shorts as they are written to (0018,1624) or
    /// (0070,0401): L* over 0x0000...0xFFFF, a* and b* offset so 0x8080 is 0.0
    /// (C.10.7.1.1).
    public var encodedValues: [Int] {
        [l, a, b]
    }

    /// The colour read back from the three encoded values of (0018,1624) or
    /// (0070,0401); nil when there are not exactly three.
    public init?(encodedValues values: [Int]) {
        guard values.count == 3 else { return nil }
        self.init(
            l: min(65535, max(0, values[0])),
            a: min(65535, max(0, values[1])),
            b: min(65535, max(0, values[2])))
    }

    /// A colour from 16-bit-per-channel sRGB, encoded per C.10.7.1.1.
    public init(sRGB red: Int, green: Int, blue: Int) {
        let encoded = GrayscalePresentationStateBuilder.cieLabEncoded(
            from: (red: red, green: green, blue: blue))
        self.init(l: encoded[0], a: encoded[1], b: encoded[2])
    }

    /// The 16-bit-per-channel sRGB colour this value renders as.
    public var sRGBValue: (red: Int, green: Int, blue: Int) {
        GrayscalePresentationStateBuilder.rgb(fromCIELabEncoded: [l, a, b])
            ?? (red: 0, green: 0, blue: 0)
    }

    /// L* = 0, a* = b* = 0: what a monochrome Shutter Presentation Value of
    /// 0000H (black, Table C.7-17a) means on a colour display. The colour
    /// builders write it when a state has shutters but names no colour, because
    /// Table C.11.12-1 leaves them no choice about the attribute's presence.
    public static let shutterBlack = CIELabColor(l: 0, a: 0x8080, b: 0x8080)
}

/// Shutter shape enumeration
///
/// Used in the Shutter Shape (0018,1600) element.
public enum ShutterShape: String, Sendable, Hashable {
    /// Rectangular shutter
    case rectangular = "RECTANGULAR"
    
    /// Circular shutter
    case circular = "CIRCULAR"
    
    /// Polygonal shutter
    case polygonal = "POLYGONAL"
    
    /// Bitmap shutter
    case bitmap = "BITMAP"
}
