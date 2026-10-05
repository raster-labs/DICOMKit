// ICCProfileHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent ICC color profile helpers
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data: parses the ICC.1 profile header (size, version, data colour space, PCS, rendering intent, 'acsp' at bytes 36–39, 'mntr' class), which PS3.3 2026a C.11.15.1.1 references but does not define; the Color Space (0028,2002) Defined Terms of C.11.15.1.2 (SRGB, ADOBERGB, ROMMRGB, DISPLAYP3) are not modelled here and ICCColorSpace's ICC signatures are not those terms

import Foundation

/// ICC profile color space classification.
public enum ICCColorSpace: String, Sendable, Equatable, Hashable, CaseIterable {
    case xyz = "XYZ"
    case lab = "Lab"
    case rgb = "RGB"
    case gray = "GRAY"
    case cmyk = "CMYK"
    case unknown = "UNKNOWN"
}

/// ICC profile rendering intent.
public enum ICCRenderingIntent: String, Sendable, Equatable, Hashable, CaseIterable {
    case perceptual = "PERCEPTUAL"
    case relativeColorimetric = "RELATIVE_COLORIMETRIC"
    case saturation = "SATURATION"
    case absoluteColorimetric = "ABSOLUTE_COLORIMETRIC"
}

/// ICC profile metadata.
public struct ICCProfileInfo: Sendable, Equatable, Hashable {
    /// Profile size in bytes.
    public let size: Int

    /// Profile version (e.g., "4.3.0").
    public let version: String

    /// Color space.
    public let colorSpace: ICCColorSpace

    /// Profile connection space.
    public let connectionSpace: ICCColorSpace

    /// Rendering intent.
    public let renderingIntent: ICCRenderingIntent

    /// Profile description text.
    public let description: String?

    /// Whether this is a display profile.
    public let isDisplayProfile: Bool

    /// Creates a new ICC profile info.
    public init(
        size: Int,
        version: String,
        colorSpace: ICCColorSpace,
        connectionSpace: ICCColorSpace = .xyz,
        renderingIntent: ICCRenderingIntent = .perceptual,
        description: String? = nil,
        isDisplayProfile: Bool = false
    ) {
        self.size = size
        self.version = version
        self.colorSpace = colorSpace
        self.connectionSpace = connectionSpace
        self.renderingIntent = renderingIntent
        self.description = description
        self.isDisplayProfile = isDisplayProfile
    }
}

/// Platform-independent helpers for ICC color profile management.
///
/// Provides ICC profile parsing, validation, and display support
/// for DICOM Color Presentation States.
public enum ICCProfileHelpers: Sendable {

    // MARK: - Profile Validation

    /// Validates ICC profile data by checking the header signature.
    ///
    /// A valid ICC profile starts with a 128-byte header where bytes
    /// 36-39 contain the signature 'acsp' (0x61637370).
    ///
    /// - Parameter data: ICC profile data.
    /// - Returns: True if the data appears to be a valid ICC profile.
    public static func isValidProfile(_ data: Data) -> Bool {
        guard data.count >= 128 else { return false }

        // Check 'acsp' signature at offset 36
        let sig0 = data[data.startIndex.advanced(by: 36)]
        let sig1 = data[data.startIndex.advanced(by: 37)]
        let sig2 = data[data.startIndex.advanced(by: 38)]
        let sig3 = data[data.startIndex.advanced(by: 39)]

        return sig0 == 0x61 && sig1 == 0x63 && sig2 == 0x73 && sig3 == 0x70
    }

    /// Extracts basic metadata from ICC profile data.
    ///
    /// - Parameter data: ICC profile data.
    /// - Returns: Profile info, or nil if invalid.
    public static func parseProfileInfo(_ data: Data) -> ICCProfileInfo? {
        guard isValidProfile(data) else { return nil }

        // Profile size (bytes 0-3, big-endian)
        let size = Int(data[data.startIndex]) << 24
            | Int(data[data.startIndex.advanced(by: 1)]) << 16
            | Int(data[data.startIndex.advanced(by: 2)]) << 8
            | Int(data[data.startIndex.advanced(by: 3)])

        // Version (bytes 8-11)
        let major = data[data.startIndex.advanced(by: 8)]
        let minor = data[data.startIndex.advanced(by: 9)]
        let version = "\(major).\(minor >> 4).\(minor & 0x0F)"

        // Color space (bytes 16-19)
        let colorSpace = parseColorSpace(
            data[data.startIndex.advanced(by: 16)],
            data[data.startIndex.advanced(by: 17)],
            data[data.startIndex.advanced(by: 18)],
            data[data.startIndex.advanced(by: 19)]
        )

        // Connection space (bytes 20-23)
        let connectionSpace = parseColorSpace(
            data[data.startIndex.advanced(by: 20)],
            data[data.startIndex.advanced(by: 21)],
            data[data.startIndex.advanced(by: 22)],
            data[data.startIndex.advanced(by: 23)]
        )

        // Rendering intent (bytes 64-67)
        let intentValue = Int(data[data.startIndex.advanced(by: 64)]) << 24
            | Int(data[data.startIndex.advanced(by: 65)]) << 16
            | Int(data[data.startIndex.advanced(by: 66)]) << 8
            | Int(data[data.startIndex.advanced(by: 67)])
        let intent = renderingIntent(from: intentValue)

        // Device class (bytes 12-15) — check for 'mntr' (monitor/display)
        let isDisplay = data[data.startIndex.advanced(by: 12)] == 0x6D
            && data[data.startIndex.advanced(by: 13)] == 0x6E
            && data[data.startIndex.advanced(by: 14)] == 0x74
            && data[data.startIndex.advanced(by: 15)] == 0x72

        return ICCProfileInfo(
            size: size,
            version: version,
            colorSpace: colorSpace,
            connectionSpace: connectionSpace,
            renderingIntent: intent,
            description: nil,
            isDisplayProfile: isDisplay
        )
    }

    // MARK: - Display Text

    /// Returns a display label for a color space.
    ///
    /// - Parameter colorSpace: ICC color space.
    /// - Returns: Human-readable label.
    public static func colorSpaceLabel(for colorSpace: ICCColorSpace) -> String {
        switch colorSpace {
        case .xyz: return "CIE XYZ"
        case .lab: return "CIE Lab"
        case .rgb: return "RGB"
        case .gray: return "Grayscale"
        case .cmyk: return "CMYK"
        case .unknown: return "Unknown"
        }
    }

    /// Returns a display label for a rendering intent.
    ///
    /// - Parameter intent: ICC rendering intent.
    /// - Returns: Human-readable label.
    public static func renderingIntentLabel(for intent: ICCRenderingIntent) -> String {
        switch intent {
        case .perceptual: return "Perceptual"
        case .relativeColorimetric: return "Relative Colorimetric"
        case .saturation: return "Saturation"
        case .absoluteColorimetric: return "Absolute Colorimetric"
        }
    }

    /// Returns a summary description for an ICC profile.
    ///
    /// - Parameter info: Profile info.
    /// - Returns: Summary string.
    public static func profileSummary(_ info: ICCProfileInfo) -> String {
        var parts: [String] = []
        parts.append(colorSpaceLabel(for: info.colorSpace))
        parts.append("v\(info.version)")
        if info.isDisplayProfile {
            parts.append("Display")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Private Helpers

    private static func parseColorSpace(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> ICCColorSpace {
        let sig = String(bytes: [b0, b1, b2, b3], encoding: .ascii) ?? ""
        switch sig.trimmingCharacters(in: .whitespaces) {
        case "XYZ": return .xyz
        case "Lab": return .lab
        case "RGB": return .rgb
        case "GRAY": return .gray
        case "CMYK": return .cmyk
        default: return .unknown
        }
    }

    private static func renderingIntent(from value: Int) -> ICCRenderingIntent {
        switch value {
        case 0: return .perceptual
        case 1: return .relativeColorimetric
        case 2: return .saturation
        case 3: return .absoluteColorimetric
        default: return .perceptual
        }
    }
}
