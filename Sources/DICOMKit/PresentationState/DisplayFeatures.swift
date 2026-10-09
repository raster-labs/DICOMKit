// NEMA-verified: 2026a, checked 2026-09-29 — IlluminationType strings are not DICOM terms (recorded); PS3.3 2026a citations checked
//
// DisplayFeatures.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - HDR and EDR Display Support

/// Extended Dynamic Range (EDR) and High Dynamic Range (HDR) display capabilities
///
/// EDR allows content to exceed the standard dynamic range on compatible displays.
/// This is particularly useful for medical imaging where highlight detail is critical.
///
/// Reference: Apple's Extended Dynamic Range documentation
/// Reference: PS3.14 - Grayscale Standard Display Function
@available(iOS 16.0, macOS 13.0, *)
public struct EDRDisplayCapabilities: Sendable, Hashable {
    /// Maximum EDR headroom available on the display
    ///
    /// Value of 1.0 means no EDR headroom (SDR only)
    /// Values > 1.0 indicate available EDR headroom
    public let maxEDRHeadroom: Double
    
    /// Current EDR headroom in use
    public let currentEDRHeadroom: Double
    
    /// Whether the display supports HDR
    public let supportsHDR: Bool
    
    /// Initialize EDR display capabilities
    public init(maxEDRHeadroom: Double, currentEDRHeadroom: Double, supportsHDR: Bool) {
        self.maxEDRHeadroom = maxEDRHeadroom
        self.currentEDRHeadroom = currentEDRHeadroom
        self.supportsHDR = supportsHDR
    }
    
    #if canImport(CoreGraphics)
    /// Get EDR capabilities from a CGDirectDisplayID (macOS only)
    #if os(macOS)
    @available(macOS 13.0, *)
    public static func capabilities(for displayID: CGDirectDisplayID) -> EDRDisplayCapabilities? {
        // Query display capabilities using Core Graphics
        // Note: This is a placeholder - actual implementation would use private APIs
        // or system preferences to determine EDR capabilities
        
        // For now, return default values
        return EDRDisplayCapabilities(
            maxEDRHeadroom: 1.0,
            currentEDRHeadroom: 1.0,
            supportsHDR: false
        )
    }
    #endif
    #endif
}

/// HDR tone mapping configuration for medical imaging
///
/// Tone mapping compresses high dynamic range content to fit display capabilities
/// while preserving diagnostic information.
@available(iOS 16.0, macOS 13.0, *)
public struct HDRToneMapping: Sendable, Hashable {
    /// Tone mapping method
    public let method: ToneMappingMethod
    
    /// Target peak luminance in nits (cd/m²)
    public let targetPeakLuminance: Double
    
    /// Preserve highlight detail during tone mapping
    public let preserveHighlights: Bool
    
    /// Initialize HDR tone mapping configuration
    public init(
        method: ToneMappingMethod = .perceptual,
        targetPeakLuminance: Double = 500.0,
        preserveHighlights: Bool = true
    ) {
        self.method = method
        self.targetPeakLuminance = targetPeakLuminance
        self.preserveHighlights = preserveHighlights
    }
    
    /// Apply tone mapping to a normalized pixel value
    ///
    /// - Parameter value: Input value (0.0-1.0 in SDR, can exceed 1.0 in HDR)
    /// - Returns: Tone-mapped value (0.0-1.0)
    public func apply(to value: Double) -> Double {
        switch method {
        case .linear:
            return min(value, 1.0)
            
        case .perceptual:
            // Perceptual tone mapping using a sigmoid-like curve
            // Preserves midtones while compressing highlights
            if value <= 1.0 {
                return value
            }
            let x = value - 1.0
            let compressed = 1.0 / (1.0 + x * x)
            return 1.0 - (compressed * 0.2) // Map HDR values above 1.0 to 0.8-1.0 range
            
        case .reinhard:
            // Reinhard tone mapping operator
            return value / (1.0 + value)
            
        case .aces:
            // ACES filmic tone mapping (simplified)
            let a = 2.51
            let b = 0.03
            let c = 2.43
            let d = 0.59
            let e = 0.14
            return ((value * (a * value + b)) / (value * (c * value + d) + e))
        }
    }
}

/// Tone mapping method for HDR content
@available(iOS 16.0, macOS 13.0, *)
public enum ToneMappingMethod: String, Sendable, Hashable, CaseIterable {
    /// Linear clipping (simple, not recommended for medical imaging)
    case linear
    
    /// Perceptual tone mapping (preserves diagnostic detail)
    case perceptual
    
    /// Reinhard tone mapping operator
    case reinhard
    
    /// ACES filmic tone mapping
    case aces
}

// MARK: - Optical Path Color Support (Whole Slide Imaging)

/// Optical path information for Whole Slide Imaging (WSI) color management
///
/// Optical paths define the illumination and color properties of microscope slides.
/// This is critical for accurate color reproduction in digital pathology.
///
/// Reference: PS3.3 C.8.12.7 - Optical Path Identification Module
/// Reference: PS3.3 C.8.12.8 - Optical Path Module
public struct OpticalPathColor: Sendable, Hashable {
    /// Optical path identifier
    public let opticalPathIdentifier: String
    
    /// Illumination type code (e.g., "Brightfield", "Fluorescence")
    public let illuminationType: IlluminationType
    
    /// Illumination color (for fluorescence imaging)
    public let illuminationColor: RGBColor?
    
    /// Illumination wavelength in nanometers (for specific wavelength illumination)
    public let illuminationWavelength: Int?
    
    /// ICC profile specific to this optical path
    public let iccProfile: Data?
    
    /// Color space for this optical path
    public let colorSpace: ColorSpace
    
    /// Initialize optical path color information
    public init(
        opticalPathIdentifier: String,
        illuminationType: IlluminationType,
        illuminationColor: RGBColor? = nil,
        illuminationWavelength: Int? = nil,
        iccProfile: Data? = nil,
        colorSpace: ColorSpace = .sRGB
    ) {
        self.opticalPathIdentifier = opticalPathIdentifier
        self.illuminationType = illuminationType
        self.illuminationColor = illuminationColor
        self.illuminationWavelength = illuminationWavelength
        self.iccProfile = iccProfile
        self.colorSpace = colorSpace
    }
}

/// Illumination type for optical paths
public enum IlluminationType: String, Sendable, Hashable, CaseIterable {
    /// Brightfield illumination (standard light microscopy)
    case brightfield = "BRIGHTFIELD"
    
    /// Darkfield illumination
    case darkfield = "DARKFIELD"
    
    /// Phase contrast
    case phaseContrast = "PHASE_CONTRAST"
    
    /// Differential interference contrast (DIC)
    case differentialInterferenceContrast = "DIC"
    
    /// Fluorescence illumination
    case fluorescence = "FLUORESCENCE"
    
    /// Transmitted light
    case transmittedLight = "TRANSMITTED"
    
    /// Reflected light
    case reflectedLight = "REFLECTED"
}

/// RGB color with 0-255 component values
public struct RGBColor: Sendable, Hashable {
    /// Red component (0-255)
    public let red: UInt8
    
    /// Green component (0-255)
    public let green: UInt8
    
    /// Blue component (0-255)
    public let blue: UInt8
    
    /// Initialize RGB color
    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
    
    /// Create from normalized components (0.0-1.0)
    public init(normalizedRed: Double, normalizedGreen: Double, normalizedBlue: Double) {
        self.red = UInt8(max(0, min(255, normalizedRed * 255.0)))
        self.green = UInt8(max(0, min(255, normalizedGreen * 255.0)))
        self.blue = UInt8(max(0, min(255, normalizedBlue * 255.0)))
    }
    
    /// Convert to normalized components (0.0-1.0)
    public var normalized: (red: Double, green: Double, blue: Double) {
        (
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0
        )
    }
}
