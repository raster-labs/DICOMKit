// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data beyond the CIELab maths used for C.10.7.1.1 encoding (D65 reference, recorded)
//
// ColorTransform.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Color transformation utilities for ICC profile-based color management
///
/// This provides color space conversions using ICC profiles and Core Graphics
/// on Apple platforms.
///
/// Reference: PS3.3 C.11.15 - ICC Profile Module
/// Reference: ICC.1:2004-10 - ICC Profile Format Specification
public struct ColorTransform: Sendable {
    
    #if canImport(CoreGraphics)
    
    /// Transform RGB color from one color space to another
    ///
    /// - Parameters:
    ///   - rgb: Input RGB components (0.0-1.0)
    ///   - sourceSpace: Source color space
    ///   - targetSpace: Target color space
    /// - Returns: Transformed RGB components (0.0-1.0)
    public static func transform(
        rgb: (red: Double, green: Double, blue: Double),
        from sourceSpace: CGColorSpace,
        to targetSpace: CGColorSpace
    ) -> (red: Double, green: Double, blue: Double) {
        // Create color in source space
        let components: [CGFloat] = [
            CGFloat(rgb.red),
            CGFloat(rgb.green),
            CGFloat(rgb.blue),
            1.0 // Alpha
        ]
        
        guard let sourceColor = CGColor(
            colorSpace: sourceSpace,
            components: components
        ) else {
            return rgb // Fallback: no transformation
        }
        
        // Convert to target space
        guard let targetColor = sourceColor.converted(
            to: targetSpace,
            intent: .defaultIntent,
            options: nil
        ) else {
            return rgb // Fallback: no transformation
        }
        
        // Extract components
        guard let targetComponents = targetColor.components,
              targetComponents.count >= 3 else {
            return rgb // Fallback: no transformation
        }
        
        return (
            red: Double(targetComponents[0]),
            green: Double(targetComponents[1]),
            blue: Double(targetComponents[2])
        )
    }
    
    /// Transform an array of RGB pixels from one color space to another
    ///
    /// - Parameters:
    ///   - pixels: Array of RGB pixel values (each in 0.0-1.0 range)
    ///   - sourceSpace: Source color space
    ///   - targetSpace: Target color space
    /// - Returns: Transformed RGB pixel values
    public static func transformPixels(
        _ pixels: [(red: Double, green: Double, blue: Double)],
        from sourceSpace: CGColorSpace,
        to targetSpace: CGColorSpace
    ) -> [(red: Double, green: Double, blue: Double)] {
        return pixels.map { pixel in
            transform(rgb: pixel, from: sourceSpace, to: targetSpace)
        }
    }
    
    /// Create a CGColorSpace from ICC profile data
    ///
    /// - Parameter iccData: ICC profile binary data
    /// - Returns: CGColorSpace or nil if creation fails
    public static func createColorSpace(from iccData: Data) -> CGColorSpace? {
        return CGColorSpace(iccData: iccData as CFData)
    }
    
    /// Convert sRGB to linear RGB
    ///
    /// Removes gamma correction for linear color calculations
    ///
    /// - Parameter component: sRGB component (0.0-1.0)
    /// - Returns: Linear RGB component (0.0-1.0)
    public static func sRGBToLinear(_ component: Double) -> Double {
        if component <= 0.04045 {
            return component / 12.92
        } else {
            return pow((component + 0.055) / 1.055, 2.4)
        }
    }
    
    /// Convert linear RGB to sRGB
    ///
    /// Applies gamma correction for display
    ///
    /// - Parameter component: Linear RGB component (0.0-1.0)
    /// - Returns: sRGB component (0.0-1.0)
    public static func linearToSRGB(_ component: Double) -> Double {
        if component <= 0.0031308 {
            return component * 12.92
        } else {
            return 1.055 * pow(component, 1.0 / 2.4) - 0.055
        }
    }
    
    /// Convert RGB to XYZ color space (using D65 illuminant)
    ///
    /// - Parameter rgb: Linear RGB components (0.0-1.0)
    /// - Returns: XYZ components
    public static func rgbToXYZ(
        _ rgb: (red: Double, green: Double, blue: Double)
    ) -> (x: Double, y: Double, z: Double) {
        // sRGB to XYZ matrix (D65 illuminant)
        let x = 0.4124564 * rgb.red + 0.3575761 * rgb.green + 0.1804375 * rgb.blue
        let y = 0.2126729 * rgb.red + 0.7151522 * rgb.green + 0.0721750 * rgb.blue
        let z = 0.0193339 * rgb.red + 0.1191920 * rgb.green + 0.9503041 * rgb.blue
        
        return (x: x, y: y, z: z)
    }
    
    /// Convert XYZ to RGB color space (using D65 illuminant)
    ///
    /// - Parameter xyz: XYZ components
    /// - Returns: Linear RGB components (0.0-1.0)
    public static func xyzToRGB(
        _ xyz: (x: Double, y: Double, z: Double)
    ) -> (red: Double, green: Double, blue: Double) {
        // XYZ to sRGB matrix (D65 illuminant)
        let r = 3.2404542 * xyz.x - 1.5371385 * xyz.y - 0.4985314 * xyz.z
        let g = -0.9692660 * xyz.x + 1.8760108 * xyz.y + 0.0415560 * xyz.z
        let b = 0.0556434 * xyz.x - 0.2040259 * xyz.y + 1.0572252 * xyz.z
        
        return (
            red: max(0, min(1, r)),
            green: max(0, min(1, g)),
            blue: max(0, min(1, b))
        )
    }
    
    /// Convert RGB to LAB color space
    ///
    /// - Parameter rgb: Linear RGB components (0.0-1.0)
    /// - Returns: LAB components (L: 0-100, a: -128 to 127, b: -128 to 127)
    public static func rgbToLAB(
        _ rgb: (red: Double, green: Double, blue: Double)
    ) -> (l: Double, a: Double, b: Double) {
        // Convert RGB → XYZ → LAB
        let xyz = rgbToXYZ(rgb)
        return xyzToLAB(xyz)
    }
    
    /// Convert XYZ to LAB color space
    ///
    /// - Parameter xyz: XYZ components
    /// - Returns: LAB components (L: 0-100, a: -128 to 127, b: -128 to 127)
    public static func xyzToLAB(
        _ xyz: (x: Double, y: Double, z: Double)
    ) -> (l: Double, a: Double, b: Double) {
        // D65 white point
        let xn = 0.95047
        let yn = 1.00000
        let zn = 1.08883
        
        func f(_ t: Double) -> Double {
            let delta = 6.0 / 29.0
            if t > pow(delta, 3) {
                return pow(t, 1.0 / 3.0)
            } else {
                return t / (3.0 * delta * delta) + 4.0 / 29.0
            }
        }
        
        let fx = f(xyz.x / xn)
        let fy = f(xyz.y / yn)
        let fz = f(xyz.z / zn)
        
        let l = 116.0 * fy - 16.0
        let a = 500.0 * (fx - fy)
        let b = 200.0 * (fy - fz)
        
        return (l: l, a: a, b: b)
    }
    
    /// Convert LAB to XYZ color space
    ///
    /// - Parameter lab: LAB components (L: 0-100, a: -128 to 127, b: -128 to 127)
    /// - Returns: XYZ components
    public static func labToXYZ(
        _ lab: (l: Double, a: Double, b: Double)
    ) -> (x: Double, y: Double, z: Double) {
        // D65 white point
        let xn = 0.95047
        let yn = 1.00000
        let zn = 1.08883
        
        func f_inv(_ t: Double) -> Double {
            let delta = 6.0 / 29.0
            if t > delta {
                return pow(t, 3.0)
            } else {
                return 3.0 * delta * delta * (t - 4.0 / 29.0)
            }
        }
        
        let fy = (lab.l + 16.0) / 116.0
        let fx = lab.a / 500.0 + fy
        let fz = fy - lab.b / 200.0
        
        let x = xn * f_inv(fx)
        let y = yn * f_inv(fy)
        let z = zn * f_inv(fz)
        
        return (x: x, y: y, z: z)
    }
    
    /// Convert LAB to RGB color space
    ///
    /// - Parameter lab: LAB components (L: 0-100, a: -128 to 127, b: -128 to 127)
    /// - Returns: Linear RGB components (0.0-1.0)
    public static func labToRGB(
        _ lab: (l: Double, a: Double, b: Double)
    ) -> (red: Double, green: Double, blue: Double) {
        // Convert LAB → XYZ → RGB
        let xyz = labToXYZ(lab)
        return xyzToRGB(xyz)
    }
    
    #endif
}

/// Matrix-based color transformation for manual ICC profile processing
public struct ColorMatrix: Sendable, Hashable {
    /// 3x3 transformation matrix
    public let matrix: [[Double]]
    
    /// Initialize with a 3x3 matrix
    public init(matrix: [[Double]]) {
        precondition(matrix.count == 3 && matrix.allSatisfy { $0.count == 3 },
                     "Matrix must be 3x3")
        self.matrix = matrix
    }
    
    /// Apply matrix transformation to RGB color
    ///
    /// - Parameter rgb: Input RGB components
    /// - Returns: Transformed RGB components
    public func apply(to rgb: (red: Double, green: Double, blue: Double)) -> (red: Double, green: Double, blue: Double) {
        let r = matrix[0][0] * rgb.red + matrix[0][1] * rgb.green + matrix[0][2] * rgb.blue
        let g = matrix[1][0] * rgb.red + matrix[1][1] * rgb.green + matrix[1][2] * rgb.blue
        let b = matrix[2][0] * rgb.red + matrix[2][1] * rgb.green + matrix[2][2] * rgb.blue
        
        return (
            red: max(0, min(1, r)),
            green: max(0, min(1, g)),
            blue: max(0, min(1, b))
        )
    }
    
    /// sRGB to XYZ transformation matrix (D65)
    public static let sRGBToXYZ = ColorMatrix(matrix: [
        [0.4124564, 0.3575761, 0.1804375],
        [0.2126729, 0.7151522, 0.0721750],
        [0.0193339, 0.1191920, 0.9503041]
    ])
    
    /// XYZ to sRGB transformation matrix (D65)
    public static let xyzToSRGB = ColorMatrix(matrix: [
        [3.2404542, -1.5371385, -0.4985314],
        [-0.9692660, 1.8760108, 0.0415560],
        [0.0556434, -0.2040259, 1.0572252]
    ])
    
    /// Identity matrix (no transformation)
    public static let identity = ColorMatrix(matrix: [
        [1, 0, 0],
        [0, 1, 0],
        [0, 0, 1]
    ])
}
