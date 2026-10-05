// WholeSlideImagingHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent whole-slide imaging (WSI) multi-resolution helpers
// Reference: DICOM PS3.3 A.32.8 (VL Whole Slide Microscopy Image IOD), C.8.12.4 (Whole Slide Microscopy Image Module)
// NEMA-verified: 2026a, checked 2026-10-05 — citation checked against the PS3.3 2026a section title; carries no DICOM-standard data (the 40x base magnification, pyramid level mapping, tile ranges, optical-path colours and cache sizing are app conventions; Image Type flavors VOLUME / LABEL / OVERVIEW / THUMBNAIL of Table C.8.12.4-2 are not modelled here)

import Foundation

/// Platform-independent helpers for whole-slide imaging pyramid navigation and display.
public enum WholeSlideImagingHelpers: Sendable {

    // MARK: - Zoom / Magnification

    /// Maps an objective magnification value to a pyramid level index.
    ///
    /// - 40× → 0, 20× → 1, 10× → 2, 5× → 3, 2.5× → 4.
    /// - For non-standard values: `max(0, Int(log2(40 / magnification)))`.
    public static func zoomLevelForMagnification(_ magnification: Double) -> Int {
        guard magnification > 0 else { return 0 }
        return Swift.max(0, Int(log2(40.0 / magnification)))
    }

    /// Returns the objective magnification for a given pyramid level.
    ///
    /// Level 0 = 40×, level 1 = 20×, etc.
    public static func magnificationForZoomLevel(_ level: Int) -> Double {
        40.0 / pow(2.0, Double(level))
    }

    // MARK: - Tile Range

    /// Calculates the range of tile indices visible within a viewport.
    ///
    /// - Parameters:
    ///   - viewportX: Left edge of the viewport in pixel coordinates.
    ///   - viewportY: Top edge of the viewport in pixel coordinates.
    ///   - viewportWidth: Viewport width in pixels.
    ///   - viewportHeight: Viewport height in pixels.
    ///   - tileLevel: The tile level descriptor for the current pyramid level.
    /// - Returns: Min/max tile indices in both axes.
    public static func visibleTileRange(
        viewportX: Double, viewportY: Double,
        viewportWidth: Double, viewportHeight: Double,
        tileLevel: WSITileLevel
    ) -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        let tW = Double(tileLevel.tileWidth)
        let tH = Double(tileLevel.tileHeight)
        let minX = Int(viewportX / tW)
        let minY = Int(viewportY / tH)
        let maxX = Int((viewportX + viewportWidth)  / tW)
        let maxY = Int((viewportY + viewportHeight) / tH)
        return (
            minX: Swift.max(0, minX),
            maxX: Swift.min(tileLevel.tileCountX - 1, maxX),
            minY: Swift.max(0, minY),
            maxY: Swift.min(tileLevel.tileCountY - 1, maxY)
        )
    }

    // MARK: - Tile Cache Key

    /// Returns a string cache key for a tile at the given pyramid level and coordinates.
    public static func tileKey(level: Int, tileX: Int, tileY: Int) -> String {
        "\(level)/\(tileX)/\(tileY)"
    }

    // MARK: - Formatting

    /// Formats a magnification value for display, e.g. `"40x"` or `"2.5x"`.
    public static func formatMagnification(_ magnification: Double) -> String {
        let rounded = magnification.rounded()
        if magnification == rounded {
            return "\(Int(magnification))x"
        }
        return "\(magnification)x"
    }

    // MARK: - Optical Path Colors

    /// Returns a default color for an optical path at the given index.
    ///
    /// - 0 = white (brightfield), 1 = red (DAPI/nucleus), 2 = green (FITC),
    ///   3 = blue (Cy5), 4 = yellow (Cy3).  Wraps modulo 5.
    public static func defaultOpticalPathColor(index: Int) -> RTColor {
        let palette: [RTColor] = [
            .white,   // 0 – brightfield
            .red,     // 1 – DAPI / nucleus
            .green,   // 2 – FITC
            .blue,    // 3 – Cy5
            .yellow,  // 4 – Cy3
        ]
        return palette[index % palette.count]
    }

    // MARK: - Memory

    /// Returns the maximum number of RGBA tiles that fit within the given memory limit.
    ///
    /// Assumes 4 bytes per pixel (RGBA8).
    public static func tileCacheCapacity(
        for memoryLimitMB: Int,
        tileWidth: Int,
        tileHeight: Int
    ) -> Int {
        let bytesPerTile = tileWidth * tileHeight * 4
        guard bytesPerTile > 0 else { return 0 }
        let totalBytes = memoryLimitMB * 1_024 * 1_024
        return totalBytes / bytesPerTile
    }
}
