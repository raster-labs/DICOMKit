// SegmentationHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent segmentation overlay display helpers
// Reference: DICOM PS3.3 C.8.20 (Segmentation), A.51 (Segmentation IOD)
// NEMA-verified: 2026a, checked 2026-10-05 — switches over SegmentAlgorithmType are exhaustive over the 3 Segment Algorithm Type (0062,0008) Defined Terms of PS3.3 2026a Table C.8.20-4 (verified in SpecializedModalityModel.swift); colours, blending and labels carry no standard data; Segmentation Type (BINARY / FRACTIONAL / LABELMAP / HEIGHTMAP, Table C.8.20-2) and the CID 7150 / 7151 category and type codes are not modelled here (SegmentOverlay carries them as free strings)

import Foundation

/// Platform-independent helpers for segmentation overlay display.
public enum SegmentationHelpers: Sendable {

    // MARK: - Color

    /// Returns a default color for a segment, cycling through 8 distinct colors.
    ///
    /// Segment numbers start at 1 and wrap around modulo 8.
    public static func defaultColor(for segmentNumber: Int) -> RTColor {
        let palette: [RTColor] = [
            .red, .blue, .green, .yellow,
            .orange, .purple, .cyan, .pink,
        ]
        let index = (segmentNumber - 1) % palette.count
        return palette[max(0, index)]
    }

    // MARK: - Algorithm Type Helpers

    /// Returns an SF Symbol name for the given segmentation algorithm type.
    public static func sfSymbolForAlgorithmType(_ type: SegmentAlgorithmType) -> String {
        switch type {
        case .manual:        return "hand.draw"
        case .semiautomatic: return "wand.and.rays"
        case .automatic:     return "cpu"
        }
    }

    /// Returns a color name string for the given segmentation algorithm type.
    public static func colorForAlgorithmType(_ type: SegmentAlgorithmType) -> String {
        switch type {
        case .manual:        return "blue"
        case .semiautomatic: return "orange"
        case .automatic:     return "green"
        }
    }

    // MARK: - Display

    /// Returns a human-readable description for a segment overlay.
    public static func overlayDescription(for overlay: SegmentOverlay) -> String {
        "\(overlay.label) (\(overlay.algorithmType.displayName))"
    }

    /// Returns the count of currently visible segment overlays.
    public static func visibleSegmentCount(in state: SegmentOverlayState) -> Int {
        state.overlays.filter(\.isVisible).count
    }

    // MARK: - Building

    /// Creates an array of default `SegmentOverlay` values for the given count.
    ///
    /// Labels are formatted as `"Segment N"` (1-indexed) with default cycle colors.
    public static func buildOverlays(segmentCount: Int) -> [SegmentOverlay] {
        (1...max(1, segmentCount)).map { n in
            SegmentOverlay(
                segmentNumber: n,
                label: "Segment \(n)",
                algorithmType: .manual,
                color: defaultColor(for: n)
            )
        }
    }

    // MARK: - Compositing

    /// Alpha-blends `overlay` onto `base` using standard porter-duff source-over.
    ///
    /// `opacity` scales the overlay alpha (0 = transparent, 1 = fully opaque).
    public static func alphaBlend(base: RTColor, overlay: RTColor, opacity: Double) -> RTColor {
        let a = min(max(opacity * overlay.alpha, 0.0), 1.0)
        let r = base.red   * (1 - a) + overlay.red   * a
        let g = base.green * (1 - a) + overlay.green * a
        let b = base.blue  * (1 - a) + overlay.blue  * a
        return RTColor(
            red:   min(max(r, 0.0), 1.0),
            green: min(max(g, 0.0), 1.0),
            blue:  min(max(b, 0.0), 1.0)
        )
    }
}
