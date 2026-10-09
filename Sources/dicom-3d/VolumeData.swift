// NEMA-verified: 2026a, checked 2026-10-01 — volume assembly against PS3.3 2026a Table C.7-10 (Pixel Spacing value 1 = adjacent row spacing, value 2 = adjacent column spacing; Spacing Between Slices centre-to-centre; Slice Thickness nominal), C.7.6.2.1.1 Equation C.7.6.2.1-1 and LPS axes, C.7.4.1.1.1 (one Frame of Reference UID per series), Tables C.7.6.16-2/-4/-5 (Pixel Measures, Plane Position (Patient), Plane Orientation (Patient) per frame), C.7.6.6.1.1, C.11.1.1.2 (Rescale per instance): 6 geometry rules, 2 were wrong (spacing order, z offset off the normal) and 4 missing (FoR, orientation, per-frame geometry, per-slice rescale), all fixed; voxelCoordinates is the inverse of Equation C.7.6.2.1-1 for orthonormal row/column/normal; nearest-neighbour sampling clamps to the last voxel centre over the edge half voxel (D207)
import Foundation
import DICOMKit
import DICOMCore
import DICOMDictionary

// MARK: - Volume Data Structure

/// Represents a 3D medical imaging volume with associated metadata
struct VolumeData {
    /// Volume dimensions (width x height x depth)
    let dimensions: VolumeDimensions
    
    /// Physical spacing between voxels in mm
    let spacing: VolumeSpacing
    
    /// Volume orientation (Image Orientation Patient)
    let orientation: VolumeOrientation
    
    /// Volume origin (Image Position Patient of first slice)
    let origin: Point3D
    
    /// Raw voxel data (stored in row-major order: x varies fastest, then y, then z)
    let voxels: [Double]
    
    /// Bits allocated per voxel
    let bitsAllocated: Int
    
    /// Bits stored per voxel
    let bitsStored: Int
    
    /// Pixel representation (0 = unsigned, 1 = signed)
    let pixelRepresentation: Int
    
    /// Photometric interpretation
    let photometricInterpretation: String
    
    /// Window center (if specified)
    let windowCenter: Double?
    
    /// Window width (if specified)
    let windowWidth: Double?
    
    /// Rescale slope (for Hounsfield units in CT)
    let rescaleSlope: Double
    
    /// Rescale intercept (for Hounsfield units in CT)
    let rescaleIntercept: Double

    /// Attributes of the first plane (patient, study, equipment, Frame of Reference),
    /// used as the template of derived DICOM output. Empty for synthetic volumes.
    let template: DataSet

    /// SOP Class / SOP Instance UIDs of the source instances, in stack order.
    let sourceReferences: [(classUID: String, instanceUID: String)]
    
    /// Initialize a volume
    init(
        dimensions: VolumeDimensions,
        spacing: VolumeSpacing,
        orientation: VolumeOrientation,
        origin: Point3D,
        voxels: [Double],
        bitsAllocated: Int = 16,
        bitsStored: Int = 16,
        pixelRepresentation: Int = 0,
        photometricInterpretation: String = "MONOCHROME2",
        windowCenter: Double? = nil,
        windowWidth: Double? = nil,
        rescaleSlope: Double = 1.0,
        rescaleIntercept: Double = 0.0,
        template: DataSet = DataSet(),
        sourceReferences: [(classUID: String, instanceUID: String)] = []
    ) {
        self.dimensions = dimensions
        self.spacing = spacing
        self.orientation = orientation
        self.origin = origin
        self.voxels = voxels
        self.bitsAllocated = bitsAllocated
        self.bitsStored = bitsStored
        self.pixelRepresentation = pixelRepresentation
        self.photometricInterpretation = photometricInterpretation
        self.windowCenter = windowCenter
        self.windowWidth = windowWidth
        self.rescaleSlope = rescaleSlope
        self.rescaleIntercept = rescaleIntercept
        self.template = template
        self.sourceReferences = sourceReferences
    }
    
    /// Get voxel value at (x, y, z)
    func voxelAt(x: Int, y: Int, z: Int) -> Double? {
        guard x >= 0 && x < dimensions.width &&
              y >= 0 && y < dimensions.height &&
              z >= 0 && z < dimensions.depth else {
            return nil
        }
        
        let index = z * dimensions.width * dimensions.height + y * dimensions.width + x
        return voxels[index]
    }

    /// Voxel value by index triple (x, y, z) given as an array.
    func voxelAt(_ index: [Int]) -> Double? {
        voxelAt(x: index[0], y: index[1], z: index[2])
    }
    
    /// Get interpolated voxel value at continuous coordinates using trilinear interpolation
    func interpolatedVoxelAt(x: Double, y: Double, z: Double, method: InterpolationMethod = .linear) -> Double? {
        guard x >= 0 && x < Double(dimensions.width) &&
              y >= 0 && y < Double(dimensions.height) &&
              z >= 0 && z < Double(dimensions.depth) else {
            return nil
        }
        
        switch method {
        case .nearest:
            // Index i is the voxel centre (PS3.3 C.7.6.2.1.1). The accepted range
            // [0, n) reaches half a voxel past the last centre, which `round` would
            // carry to n; clamp so that edge half-voxel reads the last voxel (D207),
            // as the linear branch already does.
            return voxelAt(x: min(Int(x.rounded()), dimensions.width - 1),
                           y: min(Int(y.rounded()), dimensions.height - 1),
                           z: min(Int(z.rounded()), dimensions.depth - 1))
            
        case .linear, .cubic:
            // Trilinear interpolation
            let x0 = Int(floor(x))
            let y0 = Int(floor(y))
            let z0 = Int(floor(z))
            let x1 = min(x0 + 1, dimensions.width - 1)
            let y1 = min(y0 + 1, dimensions.height - 1)
            let z1 = min(z0 + 1, dimensions.depth - 1)
            
            let fx = x - Double(x0)
            let fy = y - Double(y0)
            let fz = z - Double(z0)
            
            guard let v000 = voxelAt(x: x0, y: y0, z: z0),
                  let v100 = voxelAt(x: x1, y: y0, z: z0),
                  let v010 = voxelAt(x: x0, y: y1, z: z0),
                  let v110 = voxelAt(x: x1, y: y1, z: z0),
                  let v001 = voxelAt(x: x0, y: y0, z: z1),
                  let v101 = voxelAt(x: x1, y: y0, z: z1),
                  let v011 = voxelAt(x: x0, y: y1, z: z1),
                  let v111 = voxelAt(x: x1, y: y1, z: z1) else {
                return nil
            }
            
            // Interpolate along x
            let v00 = v000 * (1 - fx) + v100 * fx
            let v01 = v001 * (1 - fx) + v101 * fx
            let v10 = v010 * (1 - fx) + v110 * fx
            let v11 = v011 * (1 - fx) + v111 * fx
            
            // Interpolate along y
            let v0 = v00 * (1 - fy) + v10 * fy
            let v1 = v01 * (1 - fy) + v11 * fy
            
            // Interpolate along z
            return v0 * (1 - fz) + v1 * fz
        }
    }
    
    /// Get physical coordinates from voxel indices
    ///
    /// PS3.3 2026a C.7.6.2.1.1 Equation C.7.6.2.1-1, extended along the stack:
    /// P = S + X·Δi·i + Y·Δj·j + N·Δk·k, where X/Y are the row/column direction
    /// cosines, N their cross product, Δi the column spacing (`spacing.x`, Pixel
    /// Spacing value 2), Δj the row spacing (`spacing.y`, value 1) and Δk the slice
    /// spacing. Coordinates are in the patient-based (LPS) system.
    func physicalCoordinates(x: Int, y: Int, z: Int) -> Point3D {
        physicalCoordinates(x: Double(x), y: Double(y), z: Double(z))
    }

    func physicalCoordinates(x: Double, y: Double, z: Double) -> Point3D {
        let n = orientation.normal
        let px = origin.x + x * spacing.x * orientation.rowX + y * spacing.y * orientation.colX + z * spacing.z * n.x
        let py = origin.y + x * spacing.x * orientation.rowY + y * spacing.y * orientation.colY + z * spacing.z * n.y
        let pz = origin.z + x * spacing.x * orientation.rowZ + y * spacing.y * orientation.colZ + z * spacing.z * n.z
        return Point3D(x: px, y: py, z: pz)
    }

    /// Patient-space direction of a volume index axis (0 = x/columns, 1 = y/rows, 2 = z/slices).
    func axisDirection(_ axis: Int) -> Point3D {
        switch axis {
        case 0: return Point3D(x: orientation.rowX, y: orientation.rowY, z: orientation.rowZ)
        case 1: return Point3D(x: orientation.colX, y: orientation.colY, z: orientation.colZ)
        default: return orientation.normal
        }
    }

    /// Continuous volume index (x = column, y = row, z = slice) of a patient (LPS) point:
    /// the inverse of `physicalCoordinates` (row, column and normal are orthonormal,
    /// PS3.3 2026a C.7.6.2.1.1).
    func voxelCoordinates(of p: Point3D) -> (x: Double, y: Double, z: Double) {
        let d = p - origin
        return (d.dot(axisDirection(0)) / spacing.x, d.dot(axisDirection(1)) / spacing.y,
                d.dot(axisDirection(2)) / spacing.z)
    }

    /// Spacing along a volume index axis, in mm.
    func axisSpacing(_ axis: Int) -> Double {
        switch axis {
        case 0: return spacing.x
        case 1: return spacing.y
        default: return spacing.z
        }
    }

    /// Number of voxels along a volume index axis.
    func axisCount(_ axis: Int) -> Int {
        switch axis {
        case 0: return dimensions.width
        case 1: return dimensions.height
        default: return dimensions.depth
        }
    }
}

// MARK: - Supporting Types

struct VolumeDimensions: Equatable {
    let width: Int
    let height: Int
    let depth: Int
    
    var totalVoxels: Int {
        width * height * depth
    }
}

/// Voxel spacing in mm. `x` is the distance between adjacent columns (Pixel
/// Spacing (0028,0030) value 2), `y` the distance between adjacent rows (value 1),
/// `z` the distance between slice centres along the normal (PS3.3 Table C.7-10).
struct VolumeSpacing: Equatable {
    let x: Double  // mm
    let y: Double  // mm
    let z: Double  // mm
}

struct VolumeOrientation: Equatable {
    // Row direction cosines (x, y, z)
    let rowX: Double
    let rowY: Double
    let rowZ: Double
    
    // Column direction cosines (x, y, z)
    let colX: Double
    let colY: Double
    let colZ: Double
    
    /// Initialize from Image Orientation Patient tag
    init(imageOrientation: [Double]) {
        assert(imageOrientation.count == 6)
        rowX = imageOrientation[0]
        rowY = imageOrientation[1]
        rowZ = imageOrientation[2]
        colX = imageOrientation[3]
        colY = imageOrientation[4]
        colZ = imageOrientation[5]
    }
    
    /// Default axial orientation
    static let axial = VolumeOrientation(imageOrientation: [1, 0, 0, 0, 1, 0])

    /// Unit normal of the image plane, row × column (PS3.3 C.7.6.2.1.1; the
    /// patient-based coordinate system is right handed).
    var normal: Point3D {
        let d = sliceDirection
        let length = sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
        guard length > 0 else { return Point3D(x: 0, y: 0, z: 1) }
        return Point3D(x: d.x / length, y: d.y / length, z: d.z / length)
    }
    
    /// Compute slice direction (cross product of row and column)
    var sliceDirection: Point3D {
        let x = rowY * colZ - rowZ * colY
        let y = rowZ * colX - rowX * colZ
        let z = rowX * colY - rowY * colX
        return Point3D(x: x, y: y, z: z)
    }
}

struct Point3D: Equatable {
    let x: Double
    let y: Double
    let z: Double
    
    static let zero = Point3D(x: 0, y: 0, z: 0)
    
    func distance(to other: Point3D) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        let dz = z - other.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    func dot(_ other: Point3D) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    func scaled(_ factor: Double) -> Point3D {
        Point3D(x: x * factor, y: y * factor, z: z * factor)
    }

    static func + (a: Point3D, b: Point3D) -> Point3D {
        Point3D(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)
    }

    static func - (a: Point3D, b: Point3D) -> Point3D {
        Point3D(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
    }

    var length: Double { sqrt(dot(self)) }

    /// Unit vector in the same direction (the zero vector stays zero).
    var normalized: Point3D {
        let l = length
        return l > 0 ? scaled(1 / l) : self
    }

    func cross(_ o: Point3D) -> Point3D {
        Point3D(x: y * o.z - z * o.y, y: z * o.x - x * o.z, z: x * o.y - y * o.x)
    }

    /// Parses "x,y,z" (mm, LPS) as used by --oblique-normal / --oblique-point.
    static func parse(_ text: String) -> Point3D? {
        let parts = text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3, let x = parts[0], let y = parts[1], let z = parts[2],
              x.isFinite, y.isFinite, z.isFinite else { return nil }
        return Point3D(x: x, y: y, z: z)
    }
}

// MARK: - Volume Loader

/// One image plane that goes into the volume: a single-frame instance, or one
/// frame of an Enhanced multi-frame instance with its functional groups promoted
/// (PS3.3 Tables C.7.6.16-2, -4, -5: Pixel Measures, Plane Position (Patient),
/// Plane Orientation (Patient) Macros).
struct VolumeSliceSource {
    /// Geometry and pixel-description attributes for this plane (top level).
    let dataSet: DataSet
    /// The file the pixel values are read from.
    let file: DICOMFile
    /// 0-based frame index inside `file`.
    let frameIndex: Int
}

/// Loads multi-slice DICOM series into a 3D volume
///
/// Geometry follows PS3.3 2026a C.7.6.2.1.1 (Equation C.7.6.2.1-1): Image Position
/// (Patient) is the centre of the first pixel, Image Orientation (Patient) the row
/// then column direction cosines, and Pixel Spacing (0028,0030) is "adjacent row
/// spacing (delimiter) adjacent column spacing" (Table C.7-10), i.e. value 1 is the
/// spacing between rows (Δj, along the column direction) and value 2 the spacing
/// between columns (Δi, along the row direction). Slices are ordered by their
/// position along the normal (row × column), not by Instance Number.
class VolumeLoader {
    let verbose: Bool
    
    init(verbose: Bool = false) {
        self.verbose = verbose
    }
    
    /// Load volume from a list of DICOM file paths
    func loadVolume(from paths: [String]) throws -> VolumeData {
        if verbose {
            print("Loading \(paths.count) DICOM files...")
        }
        var files: [DICOMFile] = []
        for path in paths {
            let fileData = try Data(contentsOf: URL(fileURLWithPath: path))
            files.append(try DICOMFile.read(from: fileData))
        }
        return try loadVolume(files: files)
    }

    /// Expands the files into image planes: one per single-frame instance, one per
    /// frame of an Enhanced multi-frame instance (Per-frame / Shared Functional Groups).
    static func sliceSources(of files: [DICOMFile]) throws -> [VolumeSliceSource] {
        var sources: [VolumeSliceSource] = []
        for file in files {
            let ds = file.dataSet
            let frames = ds.numberOfFrames ?? 1
            let hasFunctionalGroups = ds[.perFrameFunctionalGroupsSequence] != nil
                || ds[.sharedFunctionalGroupsSequence] != nil
            if frames > 1 {
                guard hasFunctionalGroups else {
                    // A classic multi-frame image relates its Image Plane attributes to
                    // the first Frame only (C.7.6.6.1.1), so its frames cannot be placed.
                    throw VolumeError.missingMetadata(
                        "Plane Position Sequence (0020,9113) per frame (multi-frame image without functional groups)")
                }
                for i in 0..<frames {
                    sources.append(VolumeSliceSource(dataSet: ds.flattenedFrame(i), file: file, frameIndex: i))
                }
            } else {
                let flat = hasFunctionalGroups ? ds.flattenedFrame(0) : ds
                sources.append(VolumeSliceSource(dataSet: flat, file: file, frameIndex: 0))
            }
        }
        return sources
    }

    /// Position of a plane along the stack normal (PS3.3 C.7.6.2.1.1).
    static func stackCoordinate(_ position: Point3D, normal: Point3D) -> Double {
        position.dot(normal)
    }

    /// Sorts files by Image Position (Patient) projected onto the normal of the
    /// first file's Image Orientation (Patient); without that geometry the order is kept.
    static func sortedByPosition(_ files: [DICOMFile]) -> [DICOMFile] {
        guard let first = files.first,
              let iop = first.dataSet.decimalStrings(for: .imageOrientationPatient)?.map({ $0.value }),
              iop.count == 6 else { return files }
        let normal = VolumeOrientation(imageOrientation: iop).normal
        var keyed: [(index: Int, key: Double, file: DICOMFile)] = []
        for (index, file) in files.enumerated() {
            guard let ipp = file.dataSet.decimalStrings(for: .imagePositionPatient)?.map({ $0.value }),
                  ipp.count == 3 else { return files }
            keyed.append((index, stackCoordinate(Point3D(x: ipp[0], y: ipp[1], z: ipp[2]), normal: normal), file))
        }
        return keyed.sorted { $0.key != $1.key ? $0.key < $1.key : $0.index < $1.index }.map { $0.file }
    }

    /// Load a volume from already-parsed files.
    func loadVolume(files: [DICOMFile]) throws -> VolumeData {
        let sources = try VolumeLoader.sliceSources(of: files)
        guard !sources.isEmpty else {
            throw VolumeError.noSlices
        }

        var slices: [(source: VolumeSliceSource, position: Point3D)] = []
        for source in sources {
            guard let positionValues = source.dataSet.decimalStrings(for: .imagePositionPatient)?.map({ $0.value }),
                  positionValues.count == 3 else {
                throw VolumeError.missingMetadata("Image Position (Patient) (0020,0032)")
            }
            slices.append((source, Point3D(x: positionValues[0], y: positionValues[1], z: positionValues[2])))
        }

        let first = slices[0].source.dataSet
        guard let orientationValues = first.decimalStrings(for: .imageOrientationPatient)?.map({ $0.value }),
              orientationValues.count == 6 else {
            throw VolumeError.missingMetadata("Image Orientation (Patient) (0020,0037)")
        }
        let orientation = VolumeOrientation(imageOrientation: orientationValues)
        let normal = orientation.normal

        // "Each Series shall have a single Frame of Reference UID" and only images
        // sharing it are spatially related (PS3.3 C.7.4.1.1.1).
        let frameOfReferenceUIDs = Set(slices.compactMap {
            $0.source.dataSet.string(for: .frameOfReferenceUID)?.trimmingCharacters(in: .whitespaces)
        })
        if frameOfReferenceUIDs.count > 1 {
            throw VolumeError.inconsistentGeometry(
                "slices have \(frameOfReferenceUIDs.count) different Frame of Reference UIDs (0020,0052)")
        }

        // Every plane must share the orientation to form one stack.
        for slice in slices {
            if let iop = slice.source.dataSet.decimalStrings(for: .imageOrientationPatient)?.map({ $0.value }),
               iop.count == 6 {
                let o = VolumeOrientation(imageOrientation: iop)
                let rowDot = o.rowX * orientation.rowX + o.rowY * orientation.rowY + o.rowZ * orientation.rowZ
                let colDot = o.colX * orientation.colX + o.colY * orientation.colY + o.colZ * orientation.colZ
                if rowDot < 0.999 || colDot < 0.999 {
                    throw VolumeError.inconsistentGeometry(
                        "slices have different Image Orientation (Patient) (0020,0037)")
                }
            }
        }

        // Sort by position along the normal, not by Instance Number.
        slices.sort {
            VolumeLoader.stackCoordinate($0.position, normal: normal)
                < VolumeLoader.stackCoordinate($1.position, normal: normal)
        }

        guard let columns = first.uint16(for: .columns),
              let rows = first.uint16(for: .rows) else {
            throw VolumeError.missingMetadata("Columns (0028,0011) or Rows (0028,0010)")
        }
        for slice in slices {
            if slice.source.dataSet.uint16(for: .rows) != rows || slice.source.dataSet.uint16(for: .columns) != columns {
                throw VolumeError.inconsistentGeometry("slices have different Rows (0028,0010) / Columns (0028,0011)")
            }
        }
        let dimensions = VolumeDimensions(width: Int(columns), height: Int(rows), depth: slices.count)

        guard let pixelSpacingValues = first.decimalStrings(for: .pixelSpacing)?.map({ $0.value }),
              pixelSpacingValues.count == 2 else {
            throw VolumeError.missingMetadata("Pixel Spacing (0028,0030)")
        }
        // Value 1 = adjacent row spacing (Δj), value 2 = adjacent column spacing (Δi).
        let rowSpacing = pixelSpacingValues[0]
        let columnSpacing = pixelSpacingValues[1]

        // Slice spacing: centre-to-centre distance along the normal. With one slice,
        // Spacing Between Slices (0018,0088), "measured from the center-to-center of
        // each slice", is preferred over the nominal Slice Thickness (0018,0050).
        let sliceSpacing: Double
        if slices.count > 1 {
            let firstZ = VolumeLoader.stackCoordinate(slices[0].position, normal: normal)
            let lastZ = VolumeLoader.stackCoordinate(slices[slices.count - 1].position, normal: normal)
            sliceSpacing = (lastZ - firstZ) / Double(slices.count - 1)
            guard sliceSpacing > 0 else {
                throw VolumeError.inconsistentGeometry("all slices have the same Image Position (Patient) along the normal")
            }
        } else if let spacing = first.decimalString(for: .spacingBetweenSlices)?.value, spacing > 0 {
            sliceSpacing = spacing
        } else if let thickness = first.decimalString(for: .sliceThickness)?.value, thickness > 0 {
            sliceSpacing = thickness
        } else {
            sliceSpacing = 1.0
        }

        let spacing = VolumeSpacing(x: columnSpacing, y: rowSpacing, z: sliceSpacing)
        
        guard let bitsAllocatedValue = first.uint16(for: .bitsAllocated),
              let bitsStoredValue = first.uint16(for: .bitsStored),
              let pixelRepValue = first.uint16(for: .pixelRepresentation) else {
            throw VolumeError.missingMetadata("Bits Allocated, Bits Stored, or Pixel Representation")
        }
        let photometricInterpretation = first.string(for: .photometricInterpretation)?
            .trimmingCharacters(in: .whitespaces) ?? "MONOCHROME2"

        let windowCenter = first.decimalString(for: .windowCenter)
        let windowWidth = first.decimalString(for: .windowWidth)

        if verbose {
            print("Volume dimensions: \(dimensions.width)x\(dimensions.height)x\(dimensions.depth)")
            print("Voxel spacing (column x row x slice): \(spacing.x)x\(spacing.y)x\(spacing.z) mm")
        }
        
        // Voxels hold Modality LUT output values; Rescale Slope/Intercept are taken
        // from each instance or frame (PS3.3 C.11.1.1.2).
        var voxels: [Double] = []
        voxels.reserveCapacity(dimensions.totalVoxels)
        let planeSize = dimensions.width * dimensions.height
        for (index, slice) in slices.enumerated() {
            if verbose && (index % 10 == 0 || index == slices.count - 1) {
                print("Loading slice \(index + 1)/\(slices.count)...")
            }
            guard let pixelData = slice.source.file.pixelData() ?? slice.source.file.dataSet.pixelData(),
                  let pixels = pixelData.pixelValues(forFrame: slice.source.frameIndex),
                  pixels.count >= planeSize else {
                throw VolumeError.invalidPixelData
            }
            let slope = slice.source.dataSet.rescaleSlope()
            let intercept = slice.source.dataSet.rescaleIntercept()
            for pixel in pixels.prefix(planeSize) {
                voxels.append(Double(pixel) * slope + intercept)
            }
        }

        var references: [(classUID: String, instanceUID: String)] = []
        var seen = Set<String>()
        for slice in slices {
            let ds = slice.source.file.dataSet
            if let c = ds.string(for: .sopClassUID), let i = ds.string(for: .sopInstanceUID), !seen.contains(i) {
                seen.insert(i)
                references.append((c, i))
            }
        }
        
        return VolumeData(
            dimensions: dimensions,
            spacing: spacing,
            orientation: orientation,
            origin: slices[0].position,
            voxels: voxels,
            bitsAllocated: Int(bitsAllocatedValue),
            bitsStored: Int(bitsStoredValue),
            pixelRepresentation: Int(pixelRepValue),
            photometricInterpretation: photometricInterpretation,
            windowCenter: windowCenter?.value,
            windowWidth: windowWidth?.value,
            rescaleSlope: first.rescaleSlope(),
            rescaleIntercept: first.rescaleIntercept(),
            template: slices[0].source.file.dataSet,
            sourceReferences: references
        )
    }
}

// MARK: - Errors

enum VolumeError: Error, CustomStringConvertible {
    case noSlices
    case missingMetadata(String)
    case invalidPixelData
    case invalidDimensions
    case interpolationFailed
    case inconsistentGeometry(String)
    
    var description: String {
        switch self {
        case .noSlices:
            return "No DICOM slices found"
        case .missingMetadata(let tag):
            return "Missing required metadata: \(tag)"
        case .invalidPixelData:
            return "Invalid or missing pixel data"
        case .invalidDimensions:
            return "Invalid volume dimensions"
        case .interpolationFailed:
            return "Interpolation failed"
        case .inconsistentGeometry(let detail):
            return "Slices do not form one volume: \(detail)"
        }
    }
}
