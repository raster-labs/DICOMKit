// ThumbnailHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent thumbnail generation helpers
//
// NEMA-verified: 2026a, checked 2026-10-05 — supportedPhotometricInterpretations is built from DICOMCore PhotometricInterpretation == the 11 PS3.3 2026a C.7.6.3.1.2 Defined Terms less the three retired in PS3.3-2001 (was 7: YBR_PARTIAL_420, YBR_ICT, YBR_RCT, XYB missing — D10); default window presets are not standard data

import Foundation
import DICOMCore

/// Platform-independent helpers for thumbnail generation sizing and metadata.
///
/// Provides calculations for thumbnail dimensions, default window/level settings
/// for common modalities, and thumbnail cache key generation.
public enum ThumbnailHelpers: Sendable {

    /// Calculates the scaled thumbnail dimensions maintaining aspect ratio.
    ///
    /// - Parameters:
    ///   - imageWidth: Original image width in pixels.
    ///   - imageHeight: Original image height in pixels.
    ///   - maxSize: Maximum width or height of the thumbnail.
    /// - Returns: A tuple of (width, height) for the thumbnail, or nil if input is invalid.
    public static func thumbnailDimensions(
        imageWidth: Int,
        imageHeight: Int,
        maxSize: Int
    ) -> (width: Int, height: Int)? {
        guard imageWidth > 0, imageHeight > 0, maxSize > 0 else { return nil }

        if imageWidth <= maxSize && imageHeight <= maxSize {
            return (imageWidth, imageHeight)
        }

        let widthRatio = Double(maxSize) / Double(imageWidth)
        let heightRatio = Double(maxSize) / Double(imageHeight)
        let scale = min(widthRatio, heightRatio)

        let newWidth = max(1, Int(Double(imageWidth) * scale))
        let newHeight = max(1, Int(Double(imageHeight) * scale))
        return (newWidth, newHeight)
    }

    /// Returns default window center and width for a given modality.
    ///
    /// These defaults are used when no window/level is specified in the DICOM header,
    /// providing reasonable visibility for thumbnail generation.
    ///
    /// - Parameter modality: The DICOM modality code (e.g., "CT", "MR", "CR").
    /// - Returns: A tuple of (center, width) values.
    public static func defaultWindowSettings(for modality: String) -> (center: Double, width: Double) {
        // Display-ready 8-bit frames (US, endoscopy, visible light) and anything
        // unrecognized share the neutral 128/256 default.
        let fallback = (center: 128.0, width: 256.0)
        guard let resolved = Modality.normalized(modality) else { return fallback }
        switch resolved {
        case .ct:
            return (center: 40.0, width: 400.0) // Soft tissue
        case .mr:
            return (center: 500.0, width: 1000.0)
        case .mg:
            return (center: 3000.0, width: 6000.0)
        case .nm, .pt:
            return (center: 500.0, width: 1000.0)
        default:
            // Projection X-ray is wide-latitude; everything else is display-ready.
            // XA/RF are 8-bit in practice, so they keep the neutral default.
            if resolved.category == .radiography, resolved != .xa, resolved != .rf {
                return (center: 2048.0, width: 4096.0)
            }
            return fallback
        }
    }

    /// Generates a cache key for a thumbnail.
    ///
    /// - Parameters:
    ///   - sopInstanceUID: The SOP Instance UID.
    ///   - frameNumber: The frame number (0-based).
    /// - Returns: A cache key string safe for file naming.
    public static func cacheKey(sopInstanceUID: String, frameNumber: Int = 0) -> String {
        let sanitized = sopInstanceUID.replacingOccurrences(of: ".", with: "_")
        if frameNumber > 0 {
            return "\(sanitized)_f\(frameNumber)"
        }
        return sanitized
    }

    /// Determines whether a thumbnail should be generated for the given instance.
    ///
    /// - Parameters:
    ///   - rows: Number of pixel rows (may be nil if no pixel data).
    ///   - columns: Number of pixel columns (may be nil if no pixel data).
    ///   - photometricInterpretation: Photometric interpretation string.
    /// - Returns: `true` if the instance contains renderable pixel data.
    public static func shouldGenerateThumbnail(
        rows: Int?,
        columns: Int?,
        photometricInterpretation: String?
    ) -> Bool {
        guard let r = rows, let c = columns else { return false }
        guard r > 0, c > 0 else { return false }
        // Must have a photometric interpretation to render
        guard let pi = photometricInterpretation, !pi.isEmpty else { return false }
        return true
    }

    /// The photometric interpretations a thumbnail can be rendered from.
    ///
    /// Every ``DICOMCore/PhotometricInterpretation`` the decoders produce — the
    /// PS3.3 C.7.6.3.1.2 Defined Terms except HSV, ARGB and CMYK, retired in
    /// PS3.3-2001 and absent from DICOMCore. The compressed-domain terms
    /// (YBR_ICT, YBR_RCT, XYB) and the video term YBR_PARTIAL_420 are included
    /// because the decode path hands the viewer RGB samples for them; leaving
    /// them out left every JPEG 2000 / JPEG XL colour file without a thumbnail.
    public static let supportedPhotometricInterpretations: Set<String> = Set(
        renderablePhotometricInterpretations.map(\.rawValue))

    /// ``supportedPhotometricInterpretations`` as DICOMCore values, so a new
    /// case in DICOMCore is a compile-time nudge rather than a silent gap.
    static let renderablePhotometricInterpretations: [PhotometricInterpretation] = [
        .monochrome1, .monochrome2, .paletteColor, .rgb,
        .ybrFull, .ybrFull422, .ybrPartial422, .ybrPartial420,
        .ybrICT, .ybrRCT, .xyb,
    ]

    /// Checks if a photometric interpretation is supported for thumbnail rendering.
    ///
    /// - Parameter interpretation: The photometric interpretation string.
    /// - Returns: `true` if thumbnails can be generated for this interpretation.
    public static func isSupportedPhotometricInterpretation(_ interpretation: String) -> Bool {
        supportedPhotometricInterpretations.contains(interpretation.uppercased())
    }
}
