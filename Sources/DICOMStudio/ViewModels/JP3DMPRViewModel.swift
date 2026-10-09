// JP3DMPRViewModel.swift
// DICOMStudio
//
// ViewModel for the JP3D MPR three-panel view.
// Manages slice indices, crosshair synchronisation, window/level,
// and slice image generation using JP3DMPRSliceExtractor.
//
// NEMA-verified: 2026a, checked 2026-10-05 — MONOCHROME1 is inverted after windowing, as PS3.3 2026a C.7.6.3.1.2 requires ("displayed as white after any VOI gray scale transformations"; quote text-checked); the rest is MPR view state

import Foundation
import Observation
import DICOMKit

// MARK: - JP3DMPRViewModel

/// ViewModel for the JP3D Multi-Planar Reconstruction view.
///
/// Loads a ``DICOMVolume`` decoded via the J2K3D codec and exposes per-plane
/// 8-bit display buffers updated whenever the slice index or window/level
/// changes. Crosshair synchronisation is delegated to ``MPRHelpers``.
///
/// ## Usage
///
/// ```swift
/// let vm = JP3DMPRViewModel()
/// try await vm.loadVolume(from: jp3dFileURL)
///
/// // Navigate
/// vm.setSliceIndex(64, for: .axial)
///
/// // Click-to-crosshair sync
/// vm.handleClick(x: 120, y: 80, in: .axial)
/// ```
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
public final class JP3DMPRViewModel {

    // MARK: - Volume State

    /// The loaded DICOM volume (nil before `loadVolume` completes).
    public private(set) var volume: DICOMVolume?

    /// Volume geometry derived from the loaded volume.
    public private(set) var dimensions: VolumeDimensionsModel?

    // MARK: - Slice Indices

    /// Current axial (Z) slice index.
    public private(set) var axialIndex: Int = 0

    /// Current sagittal (X) slice index.
    public private(set) var sagittalIndex: Int = 0

    /// Current coronal (Y) slice index.
    public private(set) var coronalIndex: Int = 0

    // MARK: - Crosshair

    /// Current 3D crosshair position in patient coordinates.
    public private(set) var crosshair: CrosshairPosition3D = .origin

    /// Whether crosshair synchronisation is enabled.
    public var crosshairLinkingEnabled: Bool = true

    /// Whether reference lines are visible.
    public var showReferenceLines: Bool = true

    // MARK: - Window / Level

    /// Window center in voxel value units (e.g. Hounsfield for CT).
    public var windowCenter: Double = 40.0

    /// Window width. Must be > 0.
    public var windowWidth: Double = 400.0

    // MARK: - Display Buffers (8-bit grayscale)

    /// 8-bit display buffer for the axial plane, or `nil` if no volume.
    public private(set) var axialBuffer: Data?

    /// 8-bit display buffer for the sagittal plane, or `nil` if no volume.
    public private(set) var sagittalBuffer: Data?

    /// 8-bit display buffer for the coronal plane, or `nil` if no volume.
    public private(set) var coronalBuffer: Data?

    // MARK: - Status

    /// True while loading the volume.
    public private(set) var isLoading: Bool = false

    /// Error string from the last failed operation, or `nil`.
    public private(set) var errorMessage: String?

    // MARK: - Initialisation

    /// Creates a JP3D MPR ViewModel.
    public init() {}

    // MARK: - Volume Loading

    /// Loads and decodes a DICOM volume from the given URL, then refreshes
    /// all three display planes.
    ///
    /// The URL may point to:
    /// - A directory of single-frame DICOM slices.
    /// - A single JP3D Encapsulated Document file.
    ///
    /// - Parameter url: File URL to load from.
    /// - Throws: `DICOMError` on parse / decode failure.
    @MainActor
    public func loadVolume(from url: URL) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let loaded = try await DICOMFile.openVolume(from: url)
        applyVolume(loaded)
    }

    /// Directly sets a pre-loaded ``DICOMVolume`` (useful for testing and
    /// cases where loading is handled externally).
    ///
    /// - Parameter loaded: A fully decoded ``DICOMVolume``.
    @MainActor
    public func setVolume(_ loaded: DICOMVolume) {
        applyVolume(loaded)
    }

    // MARK: - Slice Navigation

    /// Sets the slice index for a given plane, clamping to valid range.
    ///
    /// - Parameters:
    ///   - index: New slice index (will be clamped).
    ///   - plane: The reconstruction plane to update.
    @MainActor
    public func setSliceIndex(_ index: Int, for plane: MPRPlane) {
        guard let dims = dimensions else { return }
        let clamped = MPRHelpers.clampSliceIndex(index, plane: plane, dimensions: dims)
        applySliceIndex(clamped, plane: plane)
    }

    /// Scrolls a plane by a relative delta.
    ///
    /// - Parameters:
    ///   - delta: Number of slices to scroll (positive = forward).
    ///   - plane: The reconstruction plane.
    @MainActor
    public func scroll(delta: Int, in plane: MPRPlane) {
        let current: Int
        switch plane {
        case .axial:    current = axialIndex
        case .sagittal: current = sagittalIndex
        case .coronal:  current = coronalIndex
        }
        setSliceIndex(current + delta, for: plane)
    }

    // MARK: - Crosshair Click

    /// Handles a click at the given pixel position within a plane, updating
    /// the crosshair and synchronising all three slice indices if linking is on.
    ///
    /// - Parameters:
    ///   - x: Horizontal pixel coordinate within the plane's image.
    ///   - y: Vertical pixel coordinate within the plane's image.
    ///   - plane: The plane that was clicked.
    @MainActor
    public func handleClick(x: Int, y: Int, in plane: MPRPlane) {
        guard crosshairLinkingEnabled, let dims = dimensions else { return }

        let result = MPRHelpers.synchronizeCrosshair(
            clickX: x,
            clickY: y,
            plane: plane,
            currentSlice: currentSliceIndex(for: plane),
            dimensions: dims
        )

        axialIndex = result.axialSlice
        sagittalIndex = result.sagittalSlice
        coronalIndex = result.coronalSlice
        crosshair = result.crosshair

        refreshAllBuffers()
    }

    // MARK: - Window / Level

    /// Updates the window/level and refreshes display buffers.
    ///
    /// - Parameters:
    ///   - center: New window center.
    ///   - width: New window width (must be > 0; negative values are ignored).
    @MainActor
    public func setWindowLevel(center: Double, width: Double) {
        guard width > 0 else { return }
        windowCenter = center
        windowWidth = width
        refreshAllBuffers()
    }

    // MARK: - Reference Line Helpers

    /// Returns the normalised (0…1) position of a reference line for display.
    ///
    /// - Parameters:
    ///   - referencePlane: The plane whose position is being indicated.
    ///   - displayPlane: The plane on which to draw the line.
    /// - Returns: Normalised fractional position (0…1), or `nil` if not applicable.
    public func referenceLinePosition(
        referencePlane: MPRPlane,
        displayPlane: MPRPlane
    ) -> Double? {
        guard showReferenceLines, let dims = dimensions else { return nil }
        let referenceSlice = currentSliceIndex(for: referencePlane)
        return MPRHelpers.referenceLinePosition(
            referencePlane: referencePlane,
            referenceSlice: referenceSlice,
            displayPlane: displayPlane,
            dimensions: dims
        )
    }

    // MARK: - Private Helpers

    /// Applies a freshly decoded volume to the ViewModel state.
    private func applyVolume(_ loaded: DICOMVolume) {
        volume = loaded
        let dims = JP3DMPRSliceExtractor.dimensionsModel(for: loaded)
        dimensions = dims

        // Centre all three planes
        axialIndex = dims.depth / 2
        sagittalIndex = dims.width / 2
        coronalIndex = dims.height / 2

        crosshair = CrosshairPosition3D(
            x: Double(sagittalIndex) * dims.spacingX,
            y: Double(coronalIndex) * dims.spacingY,
            z: Double(axialIndex) * dims.spacingZ,
            voxelX: sagittalIndex,
            voxelY: coronalIndex,
            voxelZ: axialIndex
        )

        refreshAllBuffers()
    }

    /// Sets a slice index and regenerates the affected buffer.
    private func applySliceIndex(_ index: Int, plane: MPRPlane) {
        switch plane {
        case .axial:
            axialIndex = index
            axialBuffer = makeBuffer(plane: .axial, index: index)
        case .sagittal:
            sagittalIndex = index
            sagittalBuffer = makeBuffer(plane: .sagittal, index: index)
        case .coronal:
            coronalIndex = index
            coronalBuffer = makeBuffer(plane: .coronal, index: index)
        }
    }

    /// Rebuilds display buffers for all three planes.
    private func refreshAllBuffers() {
        axialBuffer    = makeBuffer(plane: .axial,    index: axialIndex)
        sagittalBuffer = makeBuffer(plane: .sagittal, index: sagittalIndex)
        coronalBuffer  = makeBuffer(plane: .coronal,  index: coronalIndex)
    }

    /// Extracts a raw slice and applies window/level to produce an 8-bit buffer.
    private func makeBuffer(plane: MPRPlane, index: Int) -> Data? {
        guard let vol = volume else { return nil }
        guard let raw = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: plane, at: index) else {
            return nil
        }
        let windowed = JP3DMPRSliceExtractor.applyWindowLevel(
            to: raw,
            windowCenter: windowCenter,
            windowWidth: windowWidth
        )
        // MONOCHROME1: "The minimum sample value is intended to be displayed as
        // white after any VOI gray scale transformations have been performed"
        // (PS3.3 C.7.6.3.1.2) — invert after windowing, never the stored values.
        return vol.isMonochrome1 ? EnterpriseRenderHelpers.invertBuffer(windowed) : windowed
    }

    /// Returns the current slice index for a given plane.
    private func currentSliceIndex(for plane: MPRPlane) -> Int {
        switch plane {
        case .axial:    return axialIndex
        case .sagittal: return sagittalIndex
        case .coronal:  return coronalIndex
        }
    }
}
