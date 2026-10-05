// ImageMetadataHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent image metadata formatting helpers
//
// NEMA-verified: 2026a, checked 2026-10-05 — photometricLabel's 11 `case` terms == the PS3.3 2026a C.7.6.3.1.2 Defined Terms less the three retired in PS3.3-2001 (HSV, ARGB, CMYK): 10 matched, XYB added (D11); transfer-syntax labels are DICOMCore shortName / displayName (PS3.6 2026a Table A-1 names) instead of a 29-row hand table (D9); planar configuration 0/1 wording per C.7.6.3.1.3

import Foundation
import DICOMCore

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
    /// One label per PS3.3 C.7.6.3.1.2 Defined Term that DICOMCore's
    /// ``PhotometricInterpretation`` carries (the 2001-retired HSV, ARGB and
    /// CMYK have none and fall through unchanged, as does any private value).
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
        case "XYB":
            return "XYB (JPEG XL)"
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

    /// Returns a short label for a DICOM transfer syntax UID, for overlays and
    /// corner annotations.
    ///
    /// The label is DICOMCore's ``TransferSyntax/shortName`` — "JPEG 2000",
    /// "HTJ2K Lossless Only", "JPEG Lossless SV1 (Process 14)" — which is a
    /// compact handle, not the registered name. The PS3.6 Table A-1 name is
    /// ``transferSyntaxStandardName(for:)``; show it wherever there is room
    /// (tooltips, detail panels). Every registered transfer syntax gets a label;
    /// an unknown UID is shown as is.
    ///
    /// - Parameter uid: Transfer syntax UID string.
    /// - Returns: Short transfer syntax label.
    public static func transferSyntaxLabel(for uid: String) -> String {
        guard !uid.isEmpty else { return "Unknown" }
        return TransferSyntax.from(uid: uid)?.shortName ?? uid
    }

    /// Returns the PS3.6 Table A-1 name of a transfer syntax UID
    /// (``TransferSyntax/displayName``), e.g. "JPEG 2000 Image Compression
    /// (Lossless Only)"; the UID itself when it is not registered.
    ///
    /// - Parameter uid: Transfer syntax UID string.
    /// - Returns: The registered name.
    public static func transferSyntaxStandardName(for uid: String) -> String {
        guard !uid.isEmpty else { return "Unknown" }
        return TransferSyntax.from(uid: uid)?.displayName ?? uid
    }

    /// Returns a human-readable memory size for a byte count.
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
