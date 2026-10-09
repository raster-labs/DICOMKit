// VolumeVisualizationModel.swift
// DICOMStudio
//
// DICOM Studio — 3D Visualization and MPR models for Milestone 6
// Reference: DICOM PS3.3 C.7.6.2 (Image Plane Module), PS3.3 C.18.9 (3D Spatial Coordinates)
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (3D visualisation state: plane, interpolation, projection, preset and shading enums with app-private raw values); the PS3.3 C.7.6.2 and C.18.9 citations name the right 2026a clauses; InterpolationQuality.bicubic and ObliquePlaneConfiguration are stored settings only — no resampling kernel or oblique extraction exists in DICOMStudio

import Foundation

// MARK: - MPR Plane

/// Orientation plane for multi-planar reconstruction.
public enum MPRPlane: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Transverse / axial plane (XY).
    case axial = "AXIAL"
    /// Sagittal plane (YZ).
    case sagittal = "SAGITTAL"
    /// Coronal plane (XZ).
    case coronal = "CORONAL"
}

// MARK: - Interpolation Quality

/// Interpolation method for MPR reconstruction.
public enum InterpolationQuality: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Nearest-neighbor (fastest, lowest quality).
    case nearestNeighbor = "NEAREST"
    /// Bilinear interpolation (balanced).
    case bilinear = "BILINEAR"
    /// Bicubic interpolation (highest quality).
    case bicubic = "BICUBIC"
}

// MARK: - Projection Mode

/// Intensity projection mode.
public enum ProjectionMode: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Maximum Intensity Projection — shows brightest voxel along ray.
    case mip = "MIP"
    /// Minimum Intensity Projection — shows darkest voxel along ray.
    case minIP = "MinIP"
    /// Average Intensity Projection — averages voxels along ray.
    case avgIP = "AvgIP"
}

// MARK: - Transfer Function Preset

/// Preset transfer functions for volume rendering.
public enum TransferFunctionPreset: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Bone visualization (high HU values).
    case bone = "BONE"
    /// Skin / soft tissue visualization.
    case skin = "SKIN"
    /// Muscle tissue visualization.
    case muscle = "MUSCLE"
    /// Vascular structures (CT angiography).
    case vascular = "VASCULAR"
    /// Lung tissue visualization.
    case lung = "LUNG"
    /// Custom user-defined transfer function.
    case custom = "CUSTOM"
}

// MARK: - Shading Model

/// Lighting/shading model for volume rendering.
public enum ShadingModel: String, Sendable, Equatable, Hashable, CaseIterable {
    /// No shading (emission only).
    case none = "NONE"
    /// Flat shading per-face.
    case flat = "FLAT"
    /// Phong shading (ambient + diffuse + specular).
    case phong = "PHONG"
}

// MARK: - Surface Export Format

/// File format for surface mesh export.
public enum SurfaceExportFormat: String, Sendable, Equatable, Hashable, CaseIterable {
    /// STL binary format (3D printing).
    case stl = "STL"
    /// OBJ ASCII format.
    case obj = "OBJ"
}

// MARK: - Transfer Function Point

/// A single control point in a transfer function.
public struct TransferFunctionPoint: Sendable, Equatable, Hashable, Identifiable {
    /// Unique ID for the control point.
    public let id: UUID

    /// Hounsfield Unit value.
    public let huValue: Double

    /// Opacity at this HU value (0.0–1.0).
    public let opacity: Double

    /// Red component (0.0–1.0).
    public let red: Double

    /// Green component (0.0–1.0).
    public let green: Double

    /// Blue component (0.0–1.0).
    public let blue: Double

    /// Creates a transfer function control point.
    public init(
        id: UUID = UUID(),
        huValue: Double,
        opacity: Double,
        red: Double = 1.0,
        green: Double = 1.0,
        blue: Double = 1.0
    ) {
        self.id = id
        self.huValue = huValue
        self.opacity = max(0.0, min(1.0, opacity))
        self.red = max(0.0, min(1.0, red))
        self.green = max(0.0, min(1.0, green))
        self.blue = max(0.0, min(1.0, blue))
    }
}

// MARK: - Transfer Function

/// A complete transfer function mapping HU values to color and opacity.
public struct TransferFunction: Sendable, Equatable, Hashable {
    /// Control points sorted by HU value.
    public let points: [TransferFunctionPoint]

    /// Name of the transfer function.
    public let name: String

    /// Creates a transfer function.
    public init(name: String, points: [TransferFunctionPoint]) {
        self.name = name
        self.points = points.sorted { $0.huValue < $1.huValue }
    }

    /// Whether the transfer function has any points.
    public var isEmpty: Bool {
        points.isEmpty
    }

    /// HU range covered by the transfer function.
    public var huRange: ClosedRange<Double>? {
        guard let first = points.first, let last = points.last else { return nil }
        return first.huValue ... last.huValue
    }
}

// MARK: - Crosshair Position 3D

/// 3D crosshair position in physical (mm) and voxel coordinates.
public struct CrosshairPosition3D: Sendable, Equatable, Hashable {
    /// X coordinate in mm.
    public let x: Double
    /// Y coordinate in mm.
    public let y: Double
    /// Z coordinate in mm.
    public let z: Double

    /// Voxel X index (integer).
    public let voxelX: Int
    /// Voxel Y index (integer).
    public let voxelY: Int
    /// Voxel Z index (integer).
    public let voxelZ: Int

    /// Creates a 3D crosshair position.
    public init(x: Double, y: Double, z: Double, voxelX: Int, voxelY: Int, voxelZ: Int) {
        self.x = x
        self.y = y
        self.z = z
        self.voxelX = voxelX
        self.voxelY = voxelY
        self.voxelZ = voxelZ
    }

    /// Origin position.
    public static let origin = CrosshairPosition3D(x: 0, y: 0, z: 0, voxelX: 0, voxelY: 0, voxelZ: 0)

    /// Formatted string of physical coordinates.
    public var formattedPhysical: String {
        String(format: "(%.1f, %.1f, %.1f) mm", x, y, z)
    }

    /// Formatted string of voxel coordinates.
    public var formattedVoxel: String {
        "(\(voxelX), \(voxelY), \(voxelZ))"
    }
}

// MARK: - MPR Slice Configuration

/// Configuration for a single MPR slice.
public struct MPRSliceConfiguration: Sendable, Equatable, Hashable {
    /// Reconstruction plane.
    public let plane: MPRPlane

    /// Slice index within the plane.
    public let sliceIndex: Int

    /// Slice thickness in mm (nil = single pixel).
    public let sliceThickness: Double?

    /// Interpolation quality.
    public let interpolation: InterpolationQuality

    /// Creates an MPR slice configuration.
    public init(
        plane: MPRPlane,
        sliceIndex: Int = 0,
        sliceThickness: Double? = nil,
        interpolation: InterpolationQuality = .bilinear
    ) {
        self.plane = plane
        self.sliceIndex = max(0, sliceIndex)
        self.sliceThickness = sliceThickness
        self.interpolation = interpolation
    }

    /// Creates a copy with a new slice index.
    public func withSliceIndex(_ index: Int) -> MPRSliceConfiguration {
        MPRSliceConfiguration(plane: plane, sliceIndex: index, sliceThickness: sliceThickness, interpolation: interpolation)
    }

    /// Creates a copy with a new interpolation quality.
    public func withInterpolation(_ quality: InterpolationQuality) -> MPRSliceConfiguration {
        MPRSliceConfiguration(plane: plane, sliceIndex: sliceIndex, sliceThickness: sliceThickness, interpolation: quality)
    }

    /// Creates a copy with new slice thickness.
    public func withSliceThickness(_ thickness: Double?) -> MPRSliceConfiguration {
        MPRSliceConfiguration(plane: plane, sliceIndex: sliceIndex, sliceThickness: thickness, interpolation: interpolation)
    }
}

// MARK: - Oblique Plane Configuration

/// Configuration for an oblique (arbitrary angle) MPR plane.
public struct ObliquePlaneConfiguration: Sendable, Equatable, Hashable {
    /// Normal vector X.
    public let normalX: Double
    /// Normal vector Y.
    public let normalY: Double
    /// Normal vector Z.
    public let normalZ: Double

    /// Center point X in mm.
    public let centerX: Double
    /// Center point Y in mm.
    public let centerY: Double
    /// Center point Z in mm.
    public let centerZ: Double

    /// Rotation angle in degrees around the normal.
    public let rotationDegrees: Double

    /// Creates an oblique plane configuration.
    public init(
        normalX: Double, normalY: Double, normalZ: Double,
        centerX: Double, centerY: Double, centerZ: Double,
        rotationDegrees: Double = 0.0
    ) {
        self.normalX = normalX
        self.normalY = normalY
        self.normalZ = normalZ
        self.centerX = centerX
        self.centerY = centerY
        self.centerZ = centerZ
        self.rotationDegrees = rotationDegrees
    }

    /// Whether the normal vector is valid (non-zero).
    public var isValid: Bool {
        let length = sqrt(normalX * normalX + normalY * normalY + normalZ * normalZ)
        return length > 1e-10
    }
}

// MARK: - Projection Configuration

/// Configuration for an intensity projection.
public struct ProjectionConfiguration: Sendable, Equatable, Hashable {
    /// Projection mode (MIP, MinIP, AvgIP).
    public let mode: ProjectionMode

    /// Projection direction.
    public let direction: MPRPlane

    /// Slab thickness in mm (nil = full volume).
    public let slabThickness: Double?

    /// Start slice for the slab range.
    public let startSlice: Int?

    /// End slice for the slab range.
    public let endSlice: Int?

    /// Creates a projection configuration.
    public init(
        mode: ProjectionMode,
        direction: MPRPlane = .axial,
        slabThickness: Double? = nil,
        startSlice: Int? = nil,
        endSlice: Int? = nil
    ) {
        self.mode = mode
        self.direction = direction
        self.slabThickness = slabThickness
        self.startSlice = startSlice
        self.endSlice = endSlice
    }

    /// Whether this is a slab projection (limited range).
    public var isSlab: Bool {
        slabThickness != nil || (startSlice != nil && endSlice != nil)
    }
}

// MARK: - Clip Plane

/// A clipping plane for volume rendering.
public struct ClipPlane: Sendable, Equatable, Hashable, Identifiable {
    /// Unique ID.
    public let id: UUID

    /// Normal vector X.
    public let normalX: Double
    /// Normal vector Y.
    public let normalY: Double
    /// Normal vector Z.
    public let normalZ: Double

    /// Distance from origin along the normal (mm).
    public let distance: Double

    /// Whether the clip plane is enabled.
    public let isEnabled: Bool

    /// Creates a clip plane.
    public init(
        id: UUID = UUID(),
        normalX: Double, normalY: Double, normalZ: Double,
        distance: Double,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.normalX = normalX
        self.normalY = normalY
        self.normalZ = normalZ
        self.distance = distance
        self.isEnabled = isEnabled
    }

    /// Creates a copy with toggled enabled state.
    public func withEnabled(_ enabled: Bool) -> ClipPlane {
        ClipPlane(id: id, normalX: normalX, normalY: normalY, normalZ: normalZ, distance: distance, isEnabled: enabled)
    }

    /// Creates a copy with a new distance.
    public func withDistance(_ dist: Double) -> ClipPlane {
        ClipPlane(id: id, normalX: normalX, normalY: normalY, normalZ: normalZ, distance: dist, isEnabled: isEnabled)
    }
}

// MARK: - Surface Configuration

/// Configuration for isosurface extraction and rendering.
public struct SurfaceConfiguration: Sendable, Equatable, Hashable, Identifiable {
    /// Unique ID.
    public let id: UUID

    /// Label for the surface.
    public let label: String

    /// Isosurface threshold (HU value).
    public let threshold: Double

    /// Surface red (0.0–1.0).
    public let red: Double
    /// Surface green (0.0–1.0).
    public let green: Double
    /// Surface blue (0.0–1.0).
    public let blue: Double

    /// Surface opacity (0.0–1.0).
    public let opacity: Double

    /// Whether the surface is visible.
    public let isVisible: Bool

    /// Creates a surface configuration.
    public init(
        id: UUID = UUID(),
        label: String,
        threshold: Double,
        red: Double = 1.0,
        green: Double = 1.0,
        blue: Double = 1.0,
        opacity: Double = 1.0,
        isVisible: Bool = true
    ) {
        self.id = id
        self.label = label
        self.threshold = threshold
        self.red = max(0.0, min(1.0, red))
        self.green = max(0.0, min(1.0, green))
        self.blue = max(0.0, min(1.0, blue))
        self.opacity = max(0.0, min(1.0, opacity))
        self.isVisible = isVisible
    }

    /// Creates a copy with visibility toggled.
    public func withVisible(_ visible: Bool) -> SurfaceConfiguration {
        SurfaceConfiguration(id: id, label: label, threshold: threshold, red: red, green: green, blue: blue, opacity: opacity, isVisible: visible)
    }

    /// Creates a copy with new opacity.
    public func withOpacity(_ newOpacity: Double) -> SurfaceConfiguration {
        SurfaceConfiguration(id: id, label: label, threshold: threshold, red: red, green: green, blue: blue, opacity: newOpacity, isVisible: isVisible)
    }

    /// Creates a copy with new threshold.
    public func withThreshold(_ newThreshold: Double) -> SurfaceConfiguration {
        SurfaceConfiguration(id: id, label: label, threshold: newThreshold, red: red, green: green, blue: blue, opacity: opacity, isVisible: isVisible)
    }
}

// MARK: - Volume Rendering Configuration

/// Configuration for GPU-accelerated volume rendering.
public struct VolumeRenderingConfiguration: Sendable, Equatable, Hashable {
    /// Active transfer function.
    public let transferFunction: TransferFunction

    /// Preset being used (nil if custom).
    public let preset: TransferFunctionPreset?

    /// Shading model.
    public let shadingModel: ShadingModel

    /// Ambient lighting coefficient (0.0–1.0).
    public let ambientCoefficient: Double

    /// Diffuse lighting coefficient (0.0–1.0).
    public let diffuseCoefficient: Double

    /// Specular lighting coefficient (0.0–1.0).
    public let specularCoefficient: Double

    /// Specular exponent (shininess).
    public let specularExponent: Double

    /// Rotation around X axis in degrees.
    public let rotationX: Double

    /// Rotation around Y axis in degrees.
    public let rotationY: Double

    /// Rotation around Z axis in degrees.
    public let rotationZ: Double

    /// Zoom level (1.0 = default).
    public let zoom: Double

    /// Clip planes.
    public let clipPlanes: [ClipPlane]

    /// Whether rendering is enabled.
    public let isEnabled: Bool

    /// Creates a volume rendering configuration.
    public init(
        transferFunction: TransferFunction = TransferFunction(name: "Default", points: []),
        preset: TransferFunctionPreset? = nil,
        shadingModel: ShadingModel = .phong,
        ambientCoefficient: Double = 0.2,
        diffuseCoefficient: Double = 0.7,
        specularCoefficient: Double = 0.3,
        specularExponent: Double = 20.0,
        rotationX: Double = 0.0,
        rotationY: Double = 0.0,
        rotationZ: Double = 0.0,
        zoom: Double = 1.0,
        clipPlanes: [ClipPlane] = [],
        isEnabled: Bool = false
    ) {
        self.transferFunction = transferFunction
        self.preset = preset
        self.shadingModel = shadingModel
        self.ambientCoefficient = max(0.0, min(1.0, ambientCoefficient))
        self.diffuseCoefficient = max(0.0, min(1.0, diffuseCoefficient))
        self.specularCoefficient = max(0.0, min(1.0, specularCoefficient))
        self.specularExponent = max(1.0, specularExponent)
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.rotationZ = rotationZ
        self.zoom = max(0.1, zoom)
        self.clipPlanes = clipPlanes
        self.isEnabled = isEnabled
    }

    /// Active (enabled) clip planes.
    public var activeClipPlanes: [ClipPlane] {
        clipPlanes.filter(\.isEnabled)
    }
}

// MARK: - Volume Dimensions Model

/// Volume dimension and spacing metadata for display.
public struct VolumeDimensionsModel: Sendable, Equatable, Hashable {
    /// Width in voxels.
    public let width: Int
    /// Height in voxels.
    public let height: Int
    /// Depth in slices.
    public let depth: Int

    /// Pixel spacing X in mm.
    public let spacingX: Double
    /// Pixel spacing Y in mm.
    public let spacingY: Double
    /// Slice spacing in mm.
    public let spacingZ: Double

    /// Creates volume dimensions.
    public init(width: Int, height: Int, depth: Int, spacingX: Double, spacingY: Double, spacingZ: Double) {
        self.width = width
        self.height = height
        self.depth = depth
        self.spacingX = spacingX
        self.spacingY = spacingY
        self.spacingZ = spacingZ
    }

    /// Total number of voxels.
    public var totalVoxels: Int {
        width * height * depth
    }

    /// Physical size X in mm.
    public var physicalWidth: Double {
        Double(width) * spacingX
    }

    /// Physical size Y in mm.
    public var physicalHeight: Double {
        Double(height) * spacingY
    }

    /// Physical size Z in mm.
    public var physicalDepth: Double {
        Double(depth) * spacingZ
    }

    /// Maximum slice index for a given plane.
    public func maxSliceIndex(for plane: MPRPlane) -> Int {
        switch plane {
        case .axial: return max(0, depth - 1)
        case .sagittal: return max(0, width - 1)
        case .coronal: return max(0, height - 1)
        }
    }

    /// Formatted dimensions string.
    public var formattedDimensions: String {
        "\(width) × \(height) × \(depth)"
    }

    /// Formatted spacing string.
    public var formattedSpacing: String {
        String(format: "%.2f × %.2f × %.2f mm", spacingX, spacingY, spacingZ)
    }

    /// Whether spacing is isotropic (equal in all directions).
    public var isIsotropic: Bool {
        abs(spacingX - spacingY) < 1e-6 && abs(spacingY - spacingZ) < 1e-6
    }
}

// MARK: - Mesh Statistics

/// Statistics about an extracted surface mesh.
public struct MeshStatistics: Sendable, Equatable, Hashable {
    /// Number of vertices.
    public let vertexCount: Int
    /// Number of triangles.
    public let triangleCount: Int
    /// Threshold used for extraction.
    public let threshold: Double
    /// Whether the mesh is non-empty.
    public var isValid: Bool { vertexCount > 0 && triangleCount > 0 }

    /// Creates mesh statistics.
    public init(vertexCount: Int, triangleCount: Int, threshold: Double) {
        self.vertexCount = vertexCount
        self.triangleCount = triangleCount
        self.threshold = threshold
    }
}

// MARK: - Visualization Mode

/// Active 3D visualization mode.
public enum VisualizationMode: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Multi-planar reconstruction (axial + sagittal + coronal).
    case mpr = "MPR"
    /// Intensity projection (MIP/MinIP/AvgIP).
    case projection = "PROJECTION"
    /// Volume rendering (ray casting).
    case volumeRendering = "VOLUME_RENDERING"
    /// Surface rendering (isosurface).
    case surfaceRendering = "SURFACE_RENDERING"
}
