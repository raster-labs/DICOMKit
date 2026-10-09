// NEMA-verified: 2026a, checked 2026-09-30 — Color Space terms of PS3.3 2026a C.11.15.1.2 are read (DISPLAYP3 added); the ColorSpace enum is a display model, not (0028,2002) terms; preset palette entries clamped to the full 16-bit range per C.7.6.3.1.6 (D38); BlendingMode is a rendering model, not Blending Mode (0070,1B06), whose Enumerated Values EQUAL and FOREGROUND are in PS3.3 2026a Table C.11.34.1-1 (A.33.7 only; not in C.11.14 / A.33.4), CS VM 1 per PS3.6 Table 6-1 (D49)
//
// ColorManagement.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - ICC Profile

/// ICC Profile for device-independent color management
///
/// ICC profiles define color transformations to ensure consistent color reproduction
/// across different devices (monitors, printers, etc.).
///
/// Reference: PS3.3 Section C.11.15 - ICC Profile Module
public struct ICCProfile: Sendable, Hashable {
    /// ICC profile data (binary blob)
    public let profileData: Data
    
    /// Color space name (e.g., "sRGB", "Adobe RGB", "Display P3")
    public let colorSpace: ColorSpace
    
    /// Profile description/name
    public let description: String?
    
    /// Parsed profile information (lazy parsing)
    private var parsedProfile: ParsedICCProfile?
    
    /// Initialize an ICC profile
    public init(
        profileData: Data,
        colorSpace: ColorSpace,
        description: String? = nil
    ) {
        self.profileData = profileData
        self.colorSpace = colorSpace
        self.description = description
        self.parsedProfile = nil
    }
    
    /// Initialize from parsed ICC profile
    public init(parsed: ParsedICCProfile, profileData: Data) {
        self.profileData = profileData
        self.parsedProfile = parsed
        
        // Infer color space from profile class and description
        if let desc = parsed.description.lowercased() as String? {
            if desc.contains("srgb") {
                self.colorSpace = .sRGB
            } else if desc.contains("adobe rgb") {
                self.colorSpace = .adobeRGB
            } else if desc.contains("display p3") || desc.contains("p3") {
                self.colorSpace = .displayP3
            } else if desc.contains("prophoto") {
                self.colorSpace = .proPhotoRGB
            } else if desc.contains("rec") && (desc.contains("2020") || desc.contains("bt.2020")) {
                self.colorSpace = .rec2020
            } else {
                self.colorSpace = .custom
            }
        } else {
            self.colorSpace = .custom
        }
        
        self.description = parsed.description
    }
    
    /// Parse the ICC profile data
    ///
    /// - Returns: Parsed ICC profile information
    /// - Throws: ICCProfileParser.ParseError if parsing fails
    public func parse() throws -> ParsedICCProfile {
        if let parsed = parsedProfile {
            return parsed
        }
        return try ICCProfileParser.parse(profileData)
    }
    
    #if canImport(CoreGraphics)
    /// Create a CGColorSpace from this ICC profile (Apple platforms only)
    public func createCGColorSpace() -> CGColorSpace? {
        return CGColorSpace(iccData: profileData as CFData)
    }
    #endif
    
    /// Extract ICC Profile from DICOM DataSet
    ///
    /// Reads ICC Profile from the ICC Profile Module (0028,2000)
    ///
    /// - Parameter dataSet: DICOM DataSet to extract from
    /// - Returns: ICC Profile if present, nil otherwise
    public static func extract(from dataSet: [Tag: DataElement]) -> ICCProfile? {
        // ICC Profile tag (0028,2000)
        let tag = Tag(group: 0x0028, element: 0x2000)
        guard let element = dataSet[tag] else {
            return nil
        }
        
        let profileData = element.valueData
        
        // Try to parse the profile to get description
        if let parsed = try? ICCProfileParser.parse(profileData) {
            return ICCProfile(parsed: parsed, profileData: profileData)
        }
        
        // Fallback: create with unknown color space
        return ICCProfile(profileData: profileData, colorSpace: .custom)
    }
    
    /// Extract color space from DICOM Color Space tag (0028,2002)
    ///
    /// - Parameter dataSet: DICOM DataSet to extract from
    /// - Returns: ColorSpace if tag is present, nil otherwise
    public static func extractColorSpace(from dataSet: [Tag: DataElement]) -> ColorSpace? {
        // Color Space tag (0028,2002) - optional in DICOM
        let colorSpaceTag = Tag(group: 0x0028, element: 0x2002)
        guard let element = dataSet[colorSpaceTag],
              let colorSpaceString = element.stringValue else {
            return nil
        }
        
        // Map DICOM color space strings to ColorSpace enum
        switch colorSpaceString.trimmingCharacters(in: .whitespaces) {
        case "SRGB":
            return .sRGB
        case "ADOBERGB":
            return .adobeRGB
        case "ROMMRGB", "PROPHOTO":
            return .proPhotoRGB
        case "DISPLAYP3", "P3":
            return .displayP3
        case "REC2020", "BT2020":
            return .rec2020
        case "YBR_FULL":
            return .ybrFull
        case "YBR_FULL_422":
            return .ybrFull422
        case "YBR_PARTIAL_420":
            return .ybrPartial420
        default:
            return .custom
        }
    }
}

// MARK: - Color Space

/// Supported color spaces for presentation states
public enum ColorSpace: String, Sendable, Hashable, CaseIterable {
    /// sRGB (standard RGB) - most common for displays
    case sRGB
    
    /// Adobe RGB (1998) - wider gamut than sRGB
    case adobeRGB = "Adobe RGB"
    
    /// Display P3 - Apple's wide color gamut space
    case displayP3 = "Display P3"
    
    /// ProPhoto RGB - very wide gamut
    case proPhotoRGB = "ProPhoto RGB"
    
    /// Rec. 2020 (ITU-R BT.2020) - Ultra HD and HDR color space
    case rec2020 = "Rec. 2020"
    
    /// Generic RGB
    case genericRGB = "Generic RGB"
    
    /// YBR_FULL (DICOM color space)
    case ybrFull = "YBR_FULL"
    
    /// YBR_FULL_422 (DICOM color space)
    case ybrFull422 = "YBR_FULL_422"
    
    /// YBR_PARTIAL_420 (DICOM color space) 
    case ybrPartial420 = "YBR_PARTIAL_420"
    
    /// Custom color space (requires ICC profile)
    case custom
    
    #if canImport(CoreGraphics)
    /// Create a CGColorSpace for this color space (Apple platforms only)
    public func createCGColorSpace() -> CGColorSpace? {
        switch self {
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB)
        case .adobeRGB:
            return CGColorSpace(name: CGColorSpace.adobeRGB1998)
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.displayP3)
        case .proPhotoRGB:
            return CGColorSpace(name: CGColorSpace.rommrgb)
        case .rec2020:
            // Rec. 2020 color space (available on iOS 9.3+, macOS 10.11.2+)
            if #available(iOS 9.3, macOS 10.11.2, *) {
                return CGColorSpace(name: CGColorSpace.itur_2020)
            } else {
                return CGColorSpace(name: CGColorSpace.sRGB) // Fallback
            }
        case .genericRGB:
            return CGColorSpace(name: CGColorSpace.genericRGBLinear)
        case .ybrFull, .ybrFull422, .ybrPartial420:
            // YBR color spaces require conversion to RGB first
            return CGColorSpace(name: CGColorSpace.sRGB) // Default to sRGB after conversion
        case .custom:
            return nil // Requires ICC profile data
        }
    }
    #endif
}

// MARK: - Palette Color LUT Extensions

// Note: PaletteColorLUT is defined in DICOMCore
// This extension adds helper methods for pseudo-color presentation states

extension PaletteColorLUT {
    /// Apply the palette color LUT to a pixel value
    ///
    /// - Parameter value: Input grayscale pixel value
    /// - Returns: RGB color components (each in 0.0-1.0 range)
    public func applyNormalized(to value: Int) -> (red: Double, green: Double, blue: Double) {
        let (r, g, b) = lookup(value)
        return (
            Double(r) / 255.0,
            Double(g) / 255.0,
            Double(b) / 255.0
        )
    }
    
    /// Common preset color maps
    public static func preset(_ type: ColorMapPreset) -> PaletteColorLUT {
        return type.createLUT()
    }
}

// MARK: - Color Map Presets

/// Predefined color map types for pseudo-color display
public enum ColorMapPreset: String, Sendable, CaseIterable {
    /// Grayscale (linear mapping)
    case grayscale
    
    /// Hot (black → red → yellow → white)
    case hot
    
    /// Cool (cyan → blue → magenta)
    case cool
    
    /// Jet (rainbow: blue → cyan → yellow → red)
    case jet
    
    /// Bone (grayscale with blue tint)
    case bone
    
    /// Copper (black → copper → yellow)
    case copper
    
    /// Create a palette color LUT for this preset
    func createLUT() -> PaletteColorLUT {
        let numberOfEntries = 256
        let bitsPerEntry = 16
        let maxValue = UInt16((1 << 16) - 1)
        
        var redData: [UInt16] = []
        var greenData: [UInt16] = []
        var blueData: [UInt16] = []
        
        redData.reserveCapacity(numberOfEntries)
        greenData.reserveCapacity(numberOfEntries)
        blueData.reserveCapacity(numberOfEntries)
        
        for i in 0..<numberOfEntries {
            let t = Double(i) / Double(numberOfEntries - 1)
            let (r, g, b) = colorForValue(t)
            
            // Scale 0.0-1.0 across the full 16-bit entry range (PS3.3 2026a
            // C.7.6.3.1.6). The piecewise ramps overshoot 1.0 at their segment
            // ends (hot's green reaches 1.01 at entry 170), and an unclamped
            // UInt16(_:) of a value above 65535 traps.
            redData.append(Self.entry(r, maxValue: maxValue))
            greenData.append(Self.entry(g, maxValue: maxValue))
            blueData.append(Self.entry(b, maxValue: maxValue))
        }
        
        let descriptor = PaletteColorLUT.Descriptor(
            numberOfEntries: numberOfEntries,
            firstMappedValue: 0,
            bitsPerEntry: bitsPerEntry
        )
        
        return PaletteColorLUT(
            redDescriptor: descriptor,
            greenDescriptor: descriptor,
            blueDescriptor: descriptor,
            redLUT: redData,
            greenLUT: greenData,
            blueLUT: blueData
        )
    }
    
    /// One 16-bit LUT entry for a normalised intensity, clamped to 0...1.
    private static func entry(_ value: Double, maxValue: UInt16) -> UInt16 {
        UInt16(min(max(value, 0.0), 1.0) * Double(maxValue))
    }

    /// Get RGB color for normalized value (0.0-1.0)
    private func colorForValue(_ t: Double) -> (Double, Double, Double) {
        switch self {
        case .grayscale:
            return (t, t, t)
            
        case .hot:
            // Black → Red → Yellow → White
            if t < 0.33 {
                return (t * 3.0, 0, 0)
            } else if t < 0.67 {
                return (1.0, (t - 0.33) * 3.0, 0)
            } else {
                return (1.0, 1.0, (t - 0.67) * 3.0)
            }
            
        case .cool:
            // Cyan → Blue → Magenta
            return (t, 1.0 - t, 1.0)
            
        case .jet:
            // Blue → Cyan → Yellow → Red
            if t < 0.25 {
                return (0, 0, 0.5 + t * 2.0)
            } else if t < 0.5 {
                return (0, (t - 0.25) * 4.0, 1.0)
            } else if t < 0.75 {
                return ((t - 0.5) * 4.0, 1.0, 1.0 - (t - 0.5) * 4.0)
            } else {
                return (1.0, 1.0 - (t - 0.75) * 4.0, 0)
            }
            
        case .bone:
            // Grayscale with blue tint
            if t < 0.75 {
                return (t * 0.875, t * 0.875, t * 1.125)
            } else {
                return (t * 0.875 + 0.125, t * 0.875 + 0.125, 1.0)
            }
            
        case .copper:
            // Black → Copper → Yellow
            let r = min(1.0, t * 1.25)
            let g = min(1.0, t * 0.78)
            let b = min(1.0, t * 0.5)
            return (r, g, b)
        }
    }
}

// MARK: - Blending Configuration

/// Blending display set configuration
///
/// Defines how multiple images are blended together for multi-modality fusion.
///
/// A display model, not an encoding of the module: PS3.3 2026a C.11.14
/// (Presentation State Blending Module) carries a single Relative Opacity
/// (0070,0403) for the superimposed set. (Earlier text cited C.11.13, which is
/// the Presentation State Mask Module.)
public struct BlendingDisplaySet: Sendable, Hashable {
    /// Display set number
    public let displaySetNumber: Int
    
    /// Referenced images to blend
    public let referencedImages: [ReferencedImageForBlending]
    
    /// Blending mode (a rendering model, not Blending Mode (0070,1B06); see ``BlendingMode``)
    public let blendingMode: BlendingMode
    
    /// Relative opacity (0.0-1.0) for each image in the blend
    public let relativeOpacities: [Double]
    
    /// Initialize a blending display set
    public init(
        displaySetNumber: Int,
        referencedImages: [ReferencedImageForBlending],
        blendingMode: BlendingMode = .alpha,
        relativeOpacities: [Double]
    ) {
        self.displaySetNumber = displaySetNumber
        self.referencedImages = referencedImages
        self.blendingMode = blendingMode
        self.relativeOpacities = relativeOpacities
    }
}

/// Referenced image with blending-specific information
public struct ReferencedImageForBlending: Sendable, Hashable {
    /// Referenced SOP Instance UID
    public let sopInstanceUID: String
    
    /// Referenced frame number (for multi-frame images)
    public let frameNumber: Int?
    
    /// Presentation state to apply before blending
    public let presentationStateUID: String?
    
    /// Initialize a referenced image for blending
    public init(
        sopInstanceUID: String,
        frameNumber: Int? = nil,
        presentationStateUID: String? = nil
    ) {
        self.sopInstanceUID = sopInstanceUID
        self.frameNumber = frameNumber
        self.presentationStateUID = presentationStateUID
    }
}

/// Blending mode for combining images: a rendering model, not the DICOM attribute
///
/// These cases describe how a viewer might combine images on screen. They are not
/// DICOM terms and are never written to or read from a data set; the raw values
/// ("ALPHA", "MIP", "MinIP", "AVERAGE", "ADD", "SUBTRACT") are DICOMKit's own labels.
///
/// The DICOM attribute of the same name, Blending Mode (0070,1B06), CS, VM 1
/// (PS3.6 2026a Table 6-1), is a different thing: it appears only in the Blending
/// Display Sequence (0070,1B04) of the Advanced Blending Presentation State Display
/// Module (PS3.3 2026a C.11.34, Table C.11.34.1-1), used by the Advanced Blending
/// Presentation State IOD (A.33.7, SOP Class 1.2.840.10008.5.1.4.1.1.11.8). Its
/// Enumerated Values are EQUAL and FOREGROUND (blending per PS3.4 N.2.6). The
/// Blending Softcopy Presentation State IOD (A.33.4) and its Presentation State
/// Blending Module (C.11.14) have no blending-mode attribute: they carry one Relative
/// Opacity (0070,0403) for the superimposed image set. DICOMKit does not read or write
/// (0070,1B06).
public enum BlendingMode: String, Sendable, Hashable, CaseIterable {
    /// Alpha blending (weighted average)
    case alpha = "ALPHA"
    
    /// Maximum intensity projection
    case maximumIntensity = "MIP"
    
    /// Minimum intensity projection
    case minimumIntensity = "MinIP"
    
    /// Average intensity
    case average = "AVERAGE"
    
    /// Additive blending
    case additive = "ADD"
    
    /// Subtractive blending
    case subtractive = "SUBTRACT"
}
