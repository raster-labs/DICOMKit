// ImageMetadataHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent image metadata formatting helpers

import Foundation

/// Platform-independent helpers for formatting DICOM image pixel metadata
/// for overlay display.
///
/// Provides human-readable formatting of pixel data descriptors, window settings,
/// and photometric interpretations.
public enum ImageMetadataHelpers: Sendable {

    /// Formats image dimensions as "columns × rows".
    ///
    /// - Parameters:
    ///   - columns: Number of pixel columns.
    ///   - rows: Number of pixel rows.
    /// - Returns: Formatted string, e.g., "512 × 512".
    public static func dimensionsText(columns: Int, rows: Int) -> String {
        "\(columns) × \(rows)"
    }

    /// Formats bit depth information.
    ///
    /// - Parameters:
    ///   - bitsAllocated: Bits allocated per sample.
    ///   - bitsStored: Bits stored per sample.
    ///   - highBit: Most significant bit position.
    /// - Returns: Formatted string, e.g., "16 / 12 / 11".
    public static func bitDepthText(bitsAllocated: Int, bitsStored: Int, highBit: Int) -> String {
        "\(bitsAllocated) / \(bitsStored) / \(highBit)"
    }

    /// Returns a human-readable pixel representation label.
    ///
    /// - Parameter isSigned: Whether pixel values are signed.
    /// - Returns: "Signed" or "Unsigned".
    public static func pixelRepresentationText(isSigned: Bool) -> String {
        isSigned ? "Signed" : "Unsigned"
    }

    /// Formats samples per pixel and planar configuration.
    ///
    /// - Parameters:
    ///   - samplesPerPixel: Number of samples per pixel.
    ///   - planarConfiguration: Planar configuration (0 = color-by-pixel, 1 = color-by-plane).
    /// - Returns: Formatted string, e.g., "3 (color-by-pixel)".
    public static func samplesText(samplesPerPixel: Int, planarConfiguration: Int) -> String {
        if samplesPerPixel == 1 {
            return "1"
        }
        let configLabel = planarConfiguration == 0 ? "color-by-pixel" : "color-by-plane"
        return "\(samplesPerPixel) (\(configLabel))"
    }

    /// Returns a human-readable photometric interpretation label.
    ///
    /// - Parameter interpretation: The photometric interpretation string.
    /// - Returns: Human-readable label.
    public static func photometricLabel(for interpretation: String) -> String {
        switch interpretation.uppercased() {
        case "MONOCHROME1":
            return "Monochrome 1 (inverted)"
        case "MONOCHROME2":
            return "Monochrome 2"
        case "RGB":
            return "RGB Color"
        case "PALETTE COLOR":
            return "Palette Color"
        case "YBR_FULL":
            return "YBR Full"
        case "YBR_FULL_422":
            return "YBR Full 4:2:2"
        case "YBR_PARTIAL_422":
            return "YBR Partial 4:2:2"
        case "YBR_PARTIAL_420":
            return "YBR Partial 4:2:0"
        case "YBR_ICT":
            return "YBR ICT (JPEG 2000)"
        case "YBR_RCT":
            return "YBR RCT (JPEG 2000 Lossless)"
        default:
            return interpretation
        }
    }

    /// Formats window center/width as a display string.
    ///
    /// - Parameters:
    ///   - center: Window center value.
    ///   - width: Window width value.
    /// - Returns: Formatted string, e.g., "C: 40 W: 400".
    public static func windowLevelText(center: Double, width: Double) -> String {
        let c = center.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", center)
            : String(format: "%.1f", center)
        let w = width.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", width)
            : String(format: "%.1f", width)
        return "C: \(c) W: \(w)"
    }

    /// Formats frame information.
    ///
    /// - Parameters:
    ///   - current: Current frame number (1-based for display).
    ///   - total: Total number of frames.
    /// - Returns: Formatted string, e.g., "Frame 1 / 120".
    public static func frameText(current: Int, total: Int) -> String {
        "Frame \(current) / \(total)"
    }

    /// Returns a human-readable label for a DICOM transfer syntax UID.
    ///
    /// - Parameter uid: Transfer syntax UID string.
    /// - Returns: Human-readable transfer syntax name.
    public static func transferSyntaxLabel(for uid: String) -> String {
        switch uid {
        case "1.2.840.10008.1.2":        return "Implicit VR Little Endian"
        case "1.2.840.10008.1.2.1":      return "Explicit VR Little Endian"
        case "1.2.840.10008.1.2.1.99":   return "Deflated Explicit VR LE"
        case "1.2.840.10008.1.2.2":      return "Explicit VR Big Endian"
        case "1.2.840.10008.1.2.4.50":   return "JPEG Baseline"
        case "1.2.840.10008.1.2.4.51":   return "JPEG Extended"
        case "1.2.840.10008.1.2.4.57":   return "JPEG Lossless"
        case "1.2.840.10008.1.2.4.70":   return "JPEG Lossless SV1"
        case "1.2.840.10008.1.2.4.80":   return "JPEG-LS Lossless"
        case "1.2.840.10008.1.2.4.81":   return "JPEG-LS Near-Lossless"
        case "1.2.840.10008.1.2.4.90":   return "JPEG 2000 Lossless Only"
        case "1.2.840.10008.1.2.4.91":   return "JPEG 2000"
        case "1.2.840.10008.1.2.5":      return "RLE Lossless"
        case "1.2.840.10008.1.2.4.100":  return "MPEG2 Main Profile"
        case "1.2.840.10008.1.2.4.101":  return "MPEG2 High Level"
        case "1.2.840.10008.1.2.4.102":  return "MPEG-4 AVC/H.264"
        case "1.2.840.10008.1.2.4.103":  return "MPEG-4 BD-Compatible"
        case "1.2.840.10008.1.2.4.107":  return "HEVC/H.265 Main"
        case "1.2.840.10008.1.2.4.104":  return "MPEG-4 AVC/H.264 4.2 2D"
        case "1.2.840.10008.1.2.4.105":  return "MPEG-4 AVC/H.264 4.2 3D"
        case "1.2.840.10008.1.2.4.106":  return "MPEG-4 AVC/H.264 Stereo 4.2"
        case "1.2.840.10008.1.2.4.108":  return "HEVC/H.265 Main 10"
        case "1.2.840.10008.1.2.4.100.1": return "MPEG2 Main Profile (fragmentable)"
        case "1.2.840.10008.1.2.4.101.1": return "MPEG2 High Level (fragmentable)"
        case "1.2.840.10008.1.2.4.102.1": return "MPEG-4 AVC/H.264 (fragmentable)"
        case "1.2.840.10008.1.2.4.103.1": return "MPEG-4 BD-Compatible (fragmentable)"
        case "1.2.840.10008.1.2.4.104.1": return "MPEG-4 AVC/H.264 4.2 2D (fragmentable)"
        case "1.2.840.10008.1.2.4.105.1": return "MPEG-4 AVC/H.264 4.2 3D (fragmentable)"
        case "1.2.840.10008.1.2.4.106.1": return "MPEG-4 AVC/H.264 Stereo 4.2 (fragmentable)"
        default:                          return uid.isEmpty ? "Unknown" : uid
        }
    }

    /// Returns a human-readable label for a DICOM transfer syntax UID.
    ///
    /// - Parameter totalBytes: Total bytes of pixel data.
    /// - Returns: Formatted string, e.g., "25.0 MB".
    public static func memorySizeText(totalBytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(totalBytes))
    }
}
