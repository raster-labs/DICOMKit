// ShutterModel.swift
// DICOMStudio
//
// DICOM Studio — Display shutter models per DICOM PS3.3 C.7.6.11 and C.7.6.15
//
// NEMA-verified: 2026a, checked 2026-10-05 — the 4 `ShutterShape` raw values are the Shutter Shape (0018,1600) Enumerated Values of PS3.3 2026a C.7.6.11 (RECTANGULAR, CIRCULAR, POLYGONAL) plus C.7.6.15's BITMAP, all 4 match; `shutterPresentationValue` 0 (black) … 0xFFFF (white) is Shutter Presentation Value (0018,1622) in P-Values; `BitmapShutter.isValid` now requires an even overlay group 6000–601E (PS3.5 7.6 Repeating Groups — odd groups were accepted: corrected); checked by Scripts/diff_studio_g2_viewer.py

import Foundation

/// Shutter shape type: the Enumerated Values of Shutter Shape (0018,1600).
///
/// RECTANGULAR, CIRCULAR and POLYGONAL are the Display Shutter Module's
/// (PS3.3 C.7.6.11); BITMAP is the Bitmap Display Shutter Module's (C.7.6.15).
/// When several are present "all of the shapes shall be combined and applied
/// simultaneously, that is, the least amount of image remaining shall be
/// visible" (C.7.6.11) — the visible region is their intersection.
public enum ShutterShape: String, Sendable, Equatable, Hashable, CaseIterable {
    case rectangular = "RECTANGULAR"
    case circular = "CIRCULAR"
    case polygonal = "POLYGONAL"
    case bitmap = "BITMAP"
}

/// Rectangular shutter defining a visible region.
///
/// Values are in image pixel coordinates.
public struct RectangularShutter: Sendable, Equatable, Hashable {
    /// Top edge (row).
    public let top: Int

    /// Bottom edge (row).
    public let bottom: Int

    /// Left edge (column).
    public let left: Int

    /// Right edge (column).
    public let right: Int

    /// Creates a new rectangular shutter.
    public init(top: Int, bottom: Int, left: Int, right: Int) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    /// Width of the visible region.
    public var width: Int {
        max(0, right - left)
    }

    /// Height of the visible region.
    public var height: Int {
        max(0, bottom - top)
    }

    /// Whether the region is valid (non-degenerate).
    public var isValid: Bool {
        top < bottom && left < right && top >= 0 && left >= 0
    }
}

/// Circular shutter defining a visible region.
public struct CircularShutter: Sendable, Equatable, Hashable {
    /// Center row.
    public let centerRow: Int

    /// Center column.
    public let centerColumn: Int

    /// Radius in pixels.
    public let radius: Int

    /// Creates a new circular shutter.
    public init(centerRow: Int, centerColumn: Int, radius: Int) {
        self.centerRow = centerRow
        self.centerColumn = centerColumn
        self.radius = radius
    }

    /// Whether the shutter is valid.
    public var isValid: Bool {
        radius > 0 && centerRow >= 0 && centerColumn >= 0
    }
}

/// Polygonal shutter defining a visible region via vertices.
public struct PolygonalShutter: Sendable, Equatable, Hashable {
    /// Vertices of the polygon (row, column pairs).
    public let vertices: [AnnotationPoint]

    /// Creates a new polygonal shutter.
    public init(vertices: [AnnotationPoint]) {
        self.vertices = vertices
    }

    /// Whether the polygon is valid (at least 3 vertices).
    public var isValid: Bool {
        vertices.count >= 3
    }
}

/// Bitmap shutter (overlay-based masking), PS3.3 C.7.6.15.
public struct BitmapShutter: Sendable, Equatable, Hashable {
    /// Overlay group number: Shutter Overlay Group (0018,1623), one of the
    /// even Repeating Groups 6000–601E (PS3.5 7.6).
    public let overlayGroup: Int

    /// Bitmap rows.
    public let rows: Int

    /// Bitmap columns.
    public let columns: Int

    /// Creates a new bitmap shutter.
    public init(overlayGroup: Int, rows: Int, columns: Int) {
        self.overlayGroup = overlayGroup
        self.rows = rows
        self.columns = columns
    }

    /// Whether the bitmap shutter is valid.
    ///
    /// "Repeating Groups shall only be allowed in the even numbered Groups
    /// 6000-601E" (PS3.5 7.6); an odd group in that range is a private group.
    public var isValid: Bool {
        rows > 0 && columns > 0
            && overlayGroup >= 0x6000 && overlayGroup <= 0x601E && overlayGroup % 2 == 0
    }
}

/// A display shutter composing one or more shutter shapes.
///
/// The shutter color defines what is shown in the masked (non-visible) regions.
public struct ShutterModel: Identifiable, Sendable, Equatable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Shutter shapes present.
    public let shapes: [ShutterShape]

    /// Rectangular shutter (if present).
    public let rectangular: RectangularShutter?

    /// Circular shutter (if present).
    public let circular: CircularShutter?

    /// Polygonal shutter (if present).
    public let polygonal: PolygonalShutter?

    /// Bitmap shutter (if present).
    public let bitmap: BitmapShutter?

    /// Shutter Presentation Value (0018,1622): the P-Value that replaces the
    /// occluded pixels, 0000H (black) to FFFFH (white) (PS3.3 C.7.6.11).
    public let shutterPresentationValue: Int

    /// Creates a new shutter model.
    public init(
        id: UUID = UUID(),
        shapes: [ShutterShape] = [],
        rectangular: RectangularShutter? = nil,
        circular: CircularShutter? = nil,
        polygonal: PolygonalShutter? = nil,
        bitmap: BitmapShutter? = nil,
        shutterPresentationValue: Int = 0
    ) {
        self.id = id
        self.shapes = shapes
        self.rectangular = rectangular
        self.circular = circular
        self.polygonal = polygonal
        self.bitmap = bitmap
        self.shutterPresentationValue = shutterPresentationValue
    }

    /// Whether any shutter shape is defined.
    public var hasShutter: Bool {
        !shapes.isEmpty
    }
}
