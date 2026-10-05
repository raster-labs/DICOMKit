// MPRHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent MPR calculation helpers
// Reference: DICOM PS3.3 C.7.6.2 (Image Plane Module)
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no transcribed DICOM-standard data — voxel-index slice, crosshair and reference-line arithmetic; the PS3.3 C.7.6.2 (Image Plane Module) citation names the right 2026a clause

import Foundation

/// Platform-independent helpers for multi-planar reconstruction calculations.
///
/// Provides crosshair synchronization, slice index clamping, coordinate
/// conversion, and reference line computation per DICOM PS3.3 C.7.6.2.
public enum MPRHelpers: Sendable {

    // MARK: - Slice Index

    /// Clamps a slice index to the valid range for the given plane.
    ///
    /// - Parameters:
    ///   - index: Requested slice index.
    ///   - plane: The MPR plane.
    ///   - dimensions: Volume dimensions.
    /// - Returns: Clamped slice index (≥ 0).
    public static func clampSliceIndex(
        _ index: Int,
        plane: MPRPlane,
        dimensions: VolumeDimensionsModel
    ) -> Int {
        let maxIndex = dimensions.maxSliceIndex(for: plane)
        return max(0, min(index, maxIndex))
    }

    /// Computes the physical position (mm) along the normal for a slice index.
    ///
    /// - Parameters:
    ///   - index: Slice index.
    ///   - plane: The MPR plane.
    ///   - dimensions: Volume dimensions.
    /// - Returns: Position in mm along the plane's normal axis.
    public static func slicePosition(
        index: Int,
        plane: MPRPlane,
        dimensions: VolumeDimensionsModel
    ) -> Double {
        switch plane {
        case .axial:
            return Double(index) * dimensions.spacingZ
        case .sagittal:
            return Double(index) * dimensions.spacingX
        case .coronal:
            return Double(index) * dimensions.spacingY
        }
    }

    /// Converts a physical position (mm) to a slice index.
    ///
    /// - Parameters:
    ///   - position: Physical position in mm.
    ///   - plane: The MPR plane.
    ///   - dimensions: Volume dimensions.
    /// - Returns: Nearest slice index (clamped).
    public static func sliceIndexFromPosition(
        _ position: Double,
        plane: MPRPlane,
        dimensions: VolumeDimensionsModel
    ) -> Int {
        let spacing: Double
        switch plane {
        case .axial: spacing = dimensions.spacingZ
        case .sagittal: spacing = dimensions.spacingX
        case .coronal: spacing = dimensions.spacingY
        }
        guard spacing > 0 else { return 0 }
        let raw = Int(round(position / spacing))
        return clampSliceIndex(raw, plane: plane, dimensions: dimensions)
    }

    // MARK: - Crosshair Synchronization

    /// Synchronizes a crosshair position across orthogonal MPR planes.
    ///
    /// Given a click in one plane, computes the crosshair's 3D voxel position
    /// and the corresponding slice indices for the other two planes.
    ///
    /// - Parameters:
    ///   - clickX: X pixel coordinate in the clicked plane's image.
    ///   - clickY: Y pixel coordinate in the clicked plane's image.
    ///   - plane: The plane that was clicked.
    ///   - currentSlice: The current slice index of the clicked plane.
    ///   - dimensions: Volume dimensions.
    /// - Returns: Tuple of (axialSlice, sagittalSlice, coronalSlice, crosshair).
    public static func synchronizeCrosshair(
        clickX: Int,
        clickY: Int,
        plane: MPRPlane,
        currentSlice: Int,
        dimensions: VolumeDimensionsModel
    ) -> (axialSlice: Int, sagittalSlice: Int, coronalSlice: Int, crosshair: CrosshairPosition3D) {
        let voxelX: Int
        let voxelY: Int
        let voxelZ: Int

        switch plane {
        case .axial:
            // Axial: image X = voxel X, image Y = voxel Y, slice = voxel Z
            voxelX = max(0, min(clickX, dimensions.width - 1))
            voxelY = max(0, min(clickY, dimensions.height - 1))
            voxelZ = currentSlice
        case .sagittal:
            // Sagittal: image X = voxel Y, image Y = voxel Z, slice = voxel X
            voxelY = max(0, min(clickX, dimensions.height - 1))
            voxelZ = max(0, min(clickY, dimensions.depth - 1))
            voxelX = currentSlice
        case .coronal:
            // Coronal: image X = voxel X, image Y = voxel Z, slice = voxel Y
            voxelX = max(0, min(clickX, dimensions.width - 1))
            voxelZ = max(0, min(clickY, dimensions.depth - 1))
            voxelY = currentSlice
        }

        let crosshair = CrosshairPosition3D(
            x: Double(voxelX) * dimensions.spacingX,
            y: Double(voxelY) * dimensions.spacingY,
            z: Double(voxelZ) * dimensions.spacingZ,
            voxelX: voxelX,
            voxelY: voxelY,
            voxelZ: voxelZ
        )

        return (
            axialSlice: clampSliceIndex(voxelZ, plane: .axial, dimensions: dimensions),
            sagittalSlice: clampSliceIndex(voxelX, plane: .sagittal, dimensions: dimensions),
            coronalSlice: clampSliceIndex(voxelY, plane: .coronal, dimensions: dimensions),
            crosshair: crosshair
        )
    }

    // MARK: - Reference Lines

    /// Computes the position of a reference line for a plane displayed in another plane.
    ///
    /// For example, displays where the sagittal slice is in the axial view.
    ///
    /// - Parameters:
    ///   - referencePlane: The plane whose position to show.
    ///   - referenceSlice: The slice index of the reference plane.
    ///   - displayPlane: The plane in which the line is drawn.
    ///   - dimensions: Volume dimensions.
    /// - Returns: Normalized position (0.0–1.0) in the display plane, or nil if same plane.
    public static func referenceLinePosition(
        referencePlane: MPRPlane,
        referenceSlice: Int,
        displayPlane: MPRPlane,
        dimensions: VolumeDimensionsModel
    ) -> Double? {
        guard referencePlane != displayPlane else { return nil }

        switch (displayPlane, referencePlane) {
        case (.axial, .sagittal):
            // Sagittal slice → vertical line in axial (X axis)
            let maxX = max(1, dimensions.width - 1)
            return Double(min(referenceSlice, maxX)) / Double(maxX)
        case (.axial, .coronal):
            // Coronal slice → horizontal line in axial (Y axis)
            let maxY = max(1, dimensions.height - 1)
            return Double(min(referenceSlice, maxY)) / Double(maxY)
        case (.sagittal, .axial):
            // Axial slice → horizontal line in sagittal (Z axis)
            let maxZ = max(1, dimensions.depth - 1)
            return Double(min(referenceSlice, maxZ)) / Double(maxZ)
        case (.sagittal, .coronal):
            // Coronal slice → vertical line in sagittal (Y axis)
            let maxY = max(1, dimensions.height - 1)
            return Double(min(referenceSlice, maxY)) / Double(maxY)
        case (.coronal, .axial):
            // Axial slice → horizontal line in coronal (Z axis)
            let maxZ = max(1, dimensions.depth - 1)
            return Double(min(referenceSlice, maxZ)) / Double(maxZ)
        case (.coronal, .sagittal):
            // Sagittal slice → vertical line in coronal (X axis)
            let maxX = max(1, dimensions.width - 1)
            return Double(min(referenceSlice, maxX)) / Double(maxX)
        default:
            return nil
        }
    }

    // MARK: - Slab Thickness

    /// Computes the slice range for a thick slab centered on a slice index.
    ///
    /// - Parameters:
    ///   - centerSlice: Center slice index.
    ///   - thicknessMM: Slab thickness in mm.
    ///   - plane: The MPR plane.
    ///   - dimensions: Volume dimensions.
    /// - Returns: Clamped (start, end) slice range.
    public static func slabRange(
        centerSlice: Int,
        thicknessMM: Double,
        plane: MPRPlane,
        dimensions: VolumeDimensionsModel
    ) -> (start: Int, end: Int) {
        let spacing: Double
        let maxSlice: Int
        switch plane {
        case .axial:
            spacing = dimensions.spacingZ
            maxSlice = dimensions.depth - 1
        case .sagittal:
            spacing = dimensions.spacingX
            maxSlice = dimensions.width - 1
        case .coronal:
            spacing = dimensions.spacingY
            maxSlice = dimensions.height - 1
        }

        guard spacing > 0 else { return (centerSlice, centerSlice) }

        let halfSlices = Int(ceil(thicknessMM / spacing / 2.0))
        let start = max(0, centerSlice - halfSlices)
        let end = min(maxSlice, centerSlice + halfSlices)
        return (start, end)
    }

    // MARK: - Slice Dimensions

    /// Returns the pixel dimensions of a reconstructed slice for a given plane.
    ///
    /// - Parameters:
    ///   - plane: The MPR plane.
    ///   - dimensions: Volume dimensions.
    /// - Returns: (width, height) of the slice in pixels.
    public static func sliceDimensions(
        plane: MPRPlane,
        dimensions: VolumeDimensionsModel
    ) -> (width: Int, height: Int) {
        switch plane {
        case .axial:
            return (dimensions.width, dimensions.height)
        case .sagittal:
            return (dimensions.height, dimensions.depth)
        case .coronal:
            return (dimensions.width, dimensions.depth)
        }
    }

    // MARK: - Pixel Spacing for Plane

    /// Returns the pixel spacing for a reconstructed slice in a given plane.
    ///
    /// - Parameters:
    ///   - plane: The MPR plane.
    ///   - dimensions: Volume dimensions.
    /// - Returns: (spacingX, spacingY) in mm.
    public static func slicePixelSpacing(
        plane: MPRPlane,
        dimensions: VolumeDimensionsModel
    ) -> (spacingX: Double, spacingY: Double) {
        switch plane {
        case .axial:
            return (dimensions.spacingX, dimensions.spacingY)
        case .sagittal:
            return (dimensions.spacingY, dimensions.spacingZ)
        case .coronal:
            return (dimensions.spacingX, dimensions.spacingZ)
        }
    }

    // MARK: - Display Labels

    /// Returns a user-facing label for an MPR plane.
    ///
    /// - Parameter plane: The MPR plane.
    /// - Returns: Display string.
    public static func planeLabel(_ plane: MPRPlane) -> String {
        switch plane {
        case .axial: return "Axial"
        case .sagittal: return "Sagittal"
        case .coronal: return "Coronal"
        }
    }

    /// Returns an SF Symbol name for an MPR plane.
    ///
    /// - Parameter plane: The MPR plane.
    /// - Returns: SF Symbol name.
    public static func planeSymbol(_ plane: MPRPlane) -> String {
        switch plane {
        case .axial: return "square.split.1x2"
        case .sagittal: return "square.split.2x1"
        case .coronal: return "square.split.2x2"
        }
    }
}
