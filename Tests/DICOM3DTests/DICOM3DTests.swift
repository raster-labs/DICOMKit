import XCTest
@testable import DICOMKit
@testable import DICOMCore

// Note: These tests use mock data structures since we can't directly import the dicom-3d executable target
// In a production setting, these would be part of a testable library target

final class DICOM3DTests: XCTestCase {
    
    // MARK: - Volume Data Tests
    
    func test_volumeDimensions_totalVoxels() {
        let dims = VolumeDimensions(width: 10, height: 20, depth: 30)
        XCTAssertEqual(dims.totalVoxels, 6000)
    }
    
    func test_volumeSpacing_initialization() {
        let spacing = VolumeSpacing(x: 1.0, y: 1.5, z: 2.0)
        XCTAssertEqual(spacing.x, 1.0)
        XCTAssertEqual(spacing.y, 1.5)
        XCTAssertEqual(spacing.z, 2.0)
    }
    
    func test_volumeOrientation_axial() {
        let orientation = VolumeOrientation.axial
        XCTAssertEqual(orientation.rowX, 1.0)
        XCTAssertEqual(orientation.rowY, 0.0)
        XCTAssertEqual(orientation.rowZ, 0.0)
        XCTAssertEqual(orientation.colX, 0.0)
        XCTAssertEqual(orientation.colY, 1.0)
        XCTAssertEqual(orientation.colZ, 0.0)
    }
    
    func test_volumeOrientation_sliceDirection() {
        let orientation = VolumeOrientation.axial
        let sliceDir = orientation.sliceDirection
        // For axial: slice direction should be [0, 0, 1]
        XCTAssertEqual(sliceDir.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(sliceDir.y, 0.0, accuracy: 0.001)
        XCTAssertEqual(sliceDir.z, 1.0, accuracy: 0.001)
    }
    
    func test_point3D_distance() {
        let p1 = Point3D(x: 0, y: 0, z: 0)
        let p2 = Point3D(x: 3, y: 4, z: 0)
        XCTAssertEqual(p1.distance(to: p2), 5.0, accuracy: 0.001)
    }
    
    func test_point3D_zero() {
        let zero = Point3D.zero
        XCTAssertEqual(zero.x, 0)
        XCTAssertEqual(zero.y, 0)
        XCTAssertEqual(zero.z, 0)
    }
    
    func test_volumeData_voxelAt_validCoordinates() {
        let dims = VolumeDimensions(width: 2, height: 2, depth: 2)
        let spacing = VolumeSpacing(x: 1.0, y: 1.0, z: 1.0)
        let orientation = VolumeOrientation.axial
        let origin = Point3D.zero
        
        // Create volume: 2x2x2 = 8 voxels
        let voxels: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]
        
        let volume = VolumeData(
            dimensions: dims,
            spacing: spacing,
            orientation: orientation,
            origin: origin,
            voxels: voxels
        )
        
        XCTAssertEqual(volume.voxelAt(x: 0, y: 0, z: 0), 1)
        XCTAssertEqual(volume.voxelAt(x: 1, y: 0, z: 0), 2)
        XCTAssertEqual(volume.voxelAt(x: 0, y: 1, z: 0), 3)
        XCTAssertEqual(volume.voxelAt(x: 1, y: 1, z: 0), 4)
        XCTAssertEqual(volume.voxelAt(x: 0, y: 0, z: 1), 5)
    }
    
    func test_volumeData_voxelAt_invalidCoordinates() {
        let dims = VolumeDimensions(width: 2, height: 2, depth: 2)
        let spacing = VolumeSpacing(x: 1.0, y: 1.0, z: 1.0)
        let orientation = VolumeOrientation.axial
        let origin = Point3D.zero
        let voxels: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]
        
        let volume = VolumeData(
            dimensions: dims,
            spacing: spacing,
            orientation: orientation,
            origin: origin,
            voxels: voxels
        )
        
        XCTAssertNil(volume.voxelAt(x: -1, y: 0, z: 0))
        XCTAssertNil(volume.voxelAt(x: 2, y: 0, z: 0))
        XCTAssertNil(volume.voxelAt(x: 0, y: 2, z: 0))
        XCTAssertNil(volume.voxelAt(x: 0, y: 0, z: 2))
    }
    
    func test_volumeData_interpolatedVoxel_nearest() {
        let dims = VolumeDimensions(width: 2, height: 2, depth: 2)
        let spacing = VolumeSpacing(x: 1.0, y: 1.0, z: 1.0)
        let orientation = VolumeOrientation.axial
        let origin = Point3D.zero
        let voxels: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]
        
        let volume = VolumeData(
            dimensions: dims,
            spacing: spacing,
            orientation: orientation,
            origin: origin,
            voxels: voxels
        )
        
        // Nearest neighbor interpolation
        let value = volume.interpolatedVoxelAt(x: 0.4, y: 0.4, z: 0.4, method: .nearest)
        XCTAssertNotNil(value)
        XCTAssertEqual(value!, 1.0, accuracy: 0.001)
    }
    
    func test_volumeData_interpolatedVoxel_linear() {
        let dims = VolumeDimensions(width: 2, height: 2, depth: 2)
        let spacing = VolumeSpacing(x: 1.0, y: 1.0, z: 1.0)
        let orientation = VolumeOrientation.axial
        let origin = Point3D.zero
        // Uniform values for predictable interpolation
        let voxels: [Double] = [0, 0, 0, 0, 8, 8, 8, 8]
        
        let volume = VolumeData(
            dimensions: dims,
            spacing: spacing,
            orientation: orientation,
            origin: origin,
            voxels: voxels
        )
        
        // Linear interpolation at midpoint in Z should give average
        let value = volume.interpolatedVoxelAt(x: 0.0, y: 0.0, z: 0.5, method: .linear)
        XCTAssertNotNil(value)
        XCTAssertEqual(value!, 4.0, accuracy: 0.1)
    }
    
    func test_volumeData_physicalCoordinates() {
        let dims = VolumeDimensions(width: 10, height: 10, depth: 10)
        let spacing = VolumeSpacing(x: 2.0, y: 2.0, z: 3.0)
        let orientation = VolumeOrientation.axial
        let origin = Point3D(x: 100, y: 200, z: 300)
        let voxels: [Double] = Array(repeating: 0, count: 1000)
        
        let volume = VolumeData(
            dimensions: dims,
            spacing: spacing,
            orientation: orientation,
            origin: origin,
            voxels: voxels
        )
        
        let physical = volume.physicalCoordinates(x: 1, y: 1, z: 1)
        // x = 100 + 1*2*1 + 1*2*0 = 102
        // y = 200 + 1*2*0 + 1*2*1 = 202
        // z = 300 + 1*3 = 303
        XCTAssertEqual(physical.x, 102, accuracy: 0.001)
        XCTAssertEqual(physical.y, 202, accuracy: 0.001)
        XCTAssertEqual(physical.z, 303, accuracy: 0.001)
    }
    
    // MARK: - Slice Image Tests
    
    func test_sliceImage_initialization() {
        let pixels: [Double] = Array(repeating: 100.0, count: 100)
        let slice = SliceImage(width: 10, height: 10, pixels: pixels)
        
        XCTAssertEqual(slice.width, 10)
        XCTAssertEqual(slice.height, 10)
        XCTAssertEqual(slice.pixels.count, 100)
    }
    
    // MARK: - Mesh Tests
    
    func test_mesh3D_initialization() {
        let vertices = [
            Vertex3D(x: 0, y: 0, z: 0),
            Vertex3D(x: 1, y: 0, z: 0),
            Vertex3D(x: 0, y: 1, z: 0)
        ]
        let triangles = [Triangle(v0: 0, v1: 1, v2: 2)]
        
        let mesh = Mesh3D(vertices: vertices, triangles: triangles)
        
        XCTAssertEqual(mesh.vertices.count, 3)
        XCTAssertEqual(mesh.triangles.count, 1)
    }
    
    func test_vertex3D_initialization() {
        let vertex = Vertex3D(x: 1.5, y: 2.5, z: 3.5)
        XCTAssertEqual(vertex.x, 1.5)
        XCTAssertEqual(vertex.y, 2.5)
        XCTAssertEqual(vertex.z, 3.5)
    }
    
    func test_triangle_initialization() {
        let triangle = Triangle(v0: 0, v1: 1, v2: 2)
        XCTAssertEqual(triangle.v0, 0)
        XCTAssertEqual(triangle.v1, 1)
        XCTAssertEqual(triangle.v2, 2)
    }
    
    // MARK: - Error Tests
    
    func test_volumeError_descriptions() {
        XCTAssertEqual(VolumeError.noSlices.description, "No DICOM slices found")
        XCTAssertEqual(VolumeError.missingMetadata("test").description, "Missing required metadata: test")
        XCTAssertEqual(VolumeError.invalidPixelData.description, "Invalid or missing pixel data")
        XCTAssertEqual(VolumeError.invalidDimensions.description, "Invalid volume dimensions")
        XCTAssertEqual(VolumeError.interpolationFailed.description, "Interpolation failed")
    }
    
    func test_sliceError_descriptions() {
        XCTAssertEqual(SliceError.imageCreationFailed.description, "Failed to create image")
        XCTAssertEqual(SliceError.fileWriteFailed.description, "Failed to write file")
        XCTAssertEqual(SliceError.unsupportedPlatform.description, "PNG export not supported on this platform")
    }
    
    // MARK: - Integration Tests (would require real DICOM files)
    
    func test_volumeLoader_requiresRealDICOMFiles() {
        // This test would require real DICOM files in the test bundle
        // For now, we just verify the loader can be instantiated
        let loader = VolumeLoader(verbose: false)
        XCTAssertNotNil(loader)
    }
    
    func test_mprGenerator_requiresValidVolume() {
        // Create a minimal valid volume for testing
        let dims = VolumeDimensions(width: 4, height: 4, depth: 4)
        let spacing = VolumeSpacing(x: 1.0, y: 1.0, z: 1.0)
        let orientation = VolumeOrientation.axial
        let origin = Point3D.zero
        let voxels: [Double] = Array(repeating: 100.0, count: 64)
        
        let volume = VolumeData(
            dimensions: dims,
            spacing: spacing,
            orientation: orientation,
            origin: origin,
            voxels: voxels
        )
        
        let generator = MPRGenerator(volume: volume, interpolation: .linear, verbose: false)
        XCTAssertNotNil(generator)
    }
    
    func test_projectionRenderer_initialization() {
        let dims = VolumeDimensions(width: 4, height: 4, depth: 4)
        let spacing = VolumeSpacing(x: 1.0, y: 1.0, z: 1.0)
        let orientation = VolumeOrientation.axial
        let origin = Point3D.zero
        let voxels: [Double] = Array(repeating: 100.0, count: 64)
        
        let volume = VolumeData(
            dimensions: dims,
            spacing: spacing,
            orientation: orientation,
            origin: origin,
            voxels: voxels
        )
        
        let renderer = ProjectionRenderer(volume: volume, verbose: false)
        XCTAssertNotNil(renderer)
    }
    
    func test_surfaceExtractor_initialization() {
        let dims = VolumeDimensions(width: 4, height: 4, depth: 4)
        let spacing = VolumeSpacing(x: 1.0, y: 1.0, z: 1.0)
        let orientation = VolumeOrientation.axial
        let origin = Point3D.zero
        let voxels: [Double] = Array(repeating: 100.0, count: 64)

        let volume = VolumeData(
            dimensions: dims,
            spacing: spacing,
            orientation: orientation,
            origin: origin,
            voxels: voxels
        )

        let extractor = SurfaceExtractor(volume: volume, verbose: false)
        XCTAssertNotNil(extractor)
    }

    // MARK: - JP3D Volume Document Round-Trip Tests (SwiftJ2K3D 12.2.0)

    func test_encodeVolume_losslessHTJ2K_roundTrip() async throws {
        let series = JP3DTestHelpers.makeSyntheticSeries(slices: 8, rows: 16, columns: 16)
        let doc = try await JP3DVolumeDocument.encode(series: series, compressionMode: .losslessHTJ2K)
        XCTAssertTrue(JP3DVolumeDocument.isJP3DVolumeDocument(doc))
        let decoded = try await JP3DVolumeDocument.decode(from: doc)
        XCTAssertEqual(decoded.count, 8)
        XCTAssertEqual(decoded[0].dataSet[.pixelData]?.valueData, series[0].dataSet[.pixelData]?.valueData)
    }

    func test_encodeVolume_lossy_roundTrip() async throws {
        let series = JP3DTestHelpers.makeSyntheticSeries(slices: 4, rows: 8, columns: 8)
        let doc = try await JP3DVolumeDocument.encode(series: series, compressionMode: .lossy(psnr: 40.0))
        XCTAssertTrue(JP3DVolumeDocument.isJP3DVolumeDocument(doc))
        let decoded = try await JP3DVolumeDocument.decode(from: doc)
        XCTAssertEqual(decoded.count, 4)
    }

    func test_encodeVolume_lossless_roundTrip() async throws {
        let series = JP3DTestHelpers.makeSyntheticSeries(slices: 4, rows: 16, columns: 16)
        let doc = try await JP3DVolumeDocument.encode(series: series, compressionMode: .lossless)
        XCTAssertTrue(JP3DVolumeDocument.isJP3DVolumeDocument(doc))
        let decoded = try await JP3DVolumeDocument.decode(from: doc)
        XCTAssertEqual(decoded.count, 4)
        for i in 0..<4 {
            XCTAssertEqual(decoded[i].dataSet[.pixelData]?.valueData, series[i].dataSet[.pixelData]?.valueData)
        }
    }

    func test_isJP3DDocument_returnsFalse_forNormalDICOM() throws {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI) // CT Image Storage
        ds.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        let fmi = FileMetaInformation(
            mediaStorageSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            mediaStorageSOPInstanceUID: "1.2.3.4.5",
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        )
        let normalFile = DICOMFile(fileMetaInformation: fmi, dataSet: ds)
        XCTAssertFalse(JP3DVolumeDocument.isJP3DVolumeDocument(normalFile))
    }
}

// MARK: - Mock Types for Testing
// These mirror the types defined in dicom-3d source files

struct VolumeDimensions: Equatable {
    let width: Int
    let height: Int
    let depth: Int
    
    var totalVoxels: Int {
        width * height * depth
    }
}

struct VolumeSpacing: Equatable {
    let x: Double
    let y: Double
    let z: Double
}

struct VolumeOrientation: Equatable {
    let rowX: Double
    let rowY: Double
    let rowZ: Double
    let colX: Double
    let colY: Double
    let colZ: Double
    
    init(imageOrientation: [Double]) {
        assert(imageOrientation.count == 6)
        rowX = imageOrientation[0]
        rowY = imageOrientation[1]
        rowZ = imageOrientation[2]
        colX = imageOrientation[3]
        colY = imageOrientation[4]
        colZ = imageOrientation[5]
    }
    
    static let axial = VolumeOrientation(imageOrientation: [1, 0, 0, 0, 1, 0])
    
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
}

struct VolumeData {
    let dimensions: VolumeDimensions
    let spacing: VolumeSpacing
    let orientation: VolumeOrientation
    let origin: Point3D
    let voxels: [Double]
    let bitsAllocated: Int
    let bitsStored: Int
    let pixelRepresentation: Int
    let photometricInterpretation: String
    let windowCenter: Double?
    let windowWidth: Double?
    let rescaleSlope: Double
    let rescaleIntercept: Double
    
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
        rescaleIntercept: Double = 0.0
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
    }
    
    func voxelAt(x: Int, y: Int, z: Int) -> Double? {
        guard x >= 0 && x < dimensions.width &&
              y >= 0 && y < dimensions.height &&
              z >= 0 && z < dimensions.depth else {
            return nil
        }
        
        let index = z * dimensions.width * dimensions.height + y * dimensions.width + x
        return voxels[index]
    }
    
    func interpolatedVoxelAt(x: Double, y: Double, z: Double, method: InterpolationMethod = .linear) -> Double? {
        guard x >= 0 && x < Double(dimensions.width) &&
              y >= 0 && y < Double(dimensions.height) &&
              z >= 0 && z < Double(dimensions.depth) else {
            return nil
        }
        
        switch method {
        case .nearest:
            return voxelAt(x: Int(round(x)), y: Int(round(y)), z: Int(round(z)))
        case .linear, .cubic:
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
            
            let v00 = v000 * (1 - fx) + v100 * fx
            let v01 = v001 * (1 - fx) + v101 * fx
            let v10 = v010 * (1 - fx) + v110 * fx
            let v11 = v011 * (1 - fx) + v111 * fx
            
            let v0 = v00 * (1 - fy) + v10 * fy
            let v1 = v01 * (1 - fy) + v11 * fy
            
            return v0 * (1 - fz) + v1 * fz
        }
    }
    
    func physicalCoordinates(x: Int, y: Int, z: Int) -> Point3D {
        let px = origin.x + Double(x) * spacing.x * orientation.rowX + Double(y) * spacing.y * orientation.colX
        let py = origin.y + Double(x) * spacing.x * orientation.rowY + Double(y) * spacing.y * orientation.colY
        let pz = origin.z + Double(x) * spacing.x * orientation.rowZ + Double(y) * spacing.y * orientation.colZ + Double(z) * spacing.z
        return Point3D(x: px, y: py, z: pz)
    }
}

struct SliceImage {
    let width: Int
    let height: Int
    let pixels: [Double]
}

struct Mesh3D {
    let vertices: [Vertex3D]
    let triangles: [Triangle]
}

struct Vertex3D {
    let x: Double
    let y: Double
    let z: Double
}

struct Triangle {
    let v0: Int
    let v1: Int
    let v2: Int
}

enum InterpolationMethod {
    case nearest
    case linear
    case cubic
}

enum VolumeError: Error, CustomStringConvertible {
    case noSlices
    case missingMetadata(String)
    case invalidPixelData
    case invalidDimensions
    case interpolationFailed
    
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
        }
    }
}

enum SliceError: Error, CustomStringConvertible {
    case imageCreationFailed
    case fileWriteFailed
    case unsupportedPlatform
    
    var description: String {
        switch self {
        case .imageCreationFailed:
            return "Failed to create image"
        case .fileWriteFailed:
            return "Failed to write file"
        case .unsupportedPlatform:
            return "PNG export not supported on this platform"
        }
    }
}

class VolumeLoader {
    let verbose: Bool
    init(verbose: Bool) {
        self.verbose = verbose
    }
}

class MPRGenerator {
    let volume: VolumeData
    let interpolation: InterpolationMethod
    let verbose: Bool
    
    init(volume: VolumeData, interpolation: InterpolationMethod = .linear, verbose: Bool = false) {
        self.volume = volume
        self.interpolation = interpolation
        self.verbose = verbose
    }
}

class ProjectionRenderer {
    let volume: VolumeData
    let verbose: Bool
    
    init(volume: VolumeData, verbose: Bool = false) {
        self.volume = volume
        self.verbose = verbose
    }
}

class SurfaceExtractor {
    let volume: VolumeData
    let verbose: Bool

    init(volume: VolumeData, verbose: Bool = false) {
        self.volume = volume
        self.verbose = verbose
    }
}

// MARK: - JP3D Test Helpers

enum JP3DTestHelpers {
    static func makeSyntheticSeries(slices: Int, rows: Int, columns: Int) -> [DICOMFile] {
        let studyUID = "1.2.3.4.5.6"
        let seriesUID = "1.2.3.4.5.7"
        return (0..<slices).compactMap { i in
            try? makeSlice(rows: rows, columns: columns, index: i, studyUID: studyUID, seriesUID: seriesUID)
        }
    }

    private static func makeSlice(
        rows: Int, columns: Int, index: Int,
        studyUID: String, seriesUID: String
    ) throws -> DICOMFile {
        var pixelData = Data(capacity: rows * columns * 2)
        for r in 0..<rows {
            for c in 0..<columns {
                var v = UInt16((index * 256 + r * 16 + c) & 0x0FFF).littleEndian
                pixelData.append(Data(bytes: &v, count: 2))
            }
        }
        var ds = DataSet()
        ds.setUInt16(UInt16(rows),    for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(12, for: .bitsStored)
        ds.setUInt16(11, for: .highBit)
        ds.setUInt16(0,  for: .pixelRepresentation)
        ds.setUInt16(1,  for: .samplesPerPixel)
        ds.setString("MONOCHROME2",                   for: .photometricInterpretation, vr: .CS)
        ds.setString("CT",                            for: .modality,                  vr: .CS)
        ds.setString(studyUID,                        for: .studyInstanceUID,          vr: .UI)
        ds.setString(seriesUID,                       for: .seriesInstanceUID,         vr: .UI)
        ds.setString(UIDGenerator.generateUID().value, for: .sopInstanceUID,            vr: .UI)
        ds.setString("1.2.840.10008.5.1.4.1.1.2",    for: .sopClassUID,               vr: .UI)
        ds.setInt(index + 1,                          for: .instanceNumber,            vr: .IS)
        let z = Double(index) * 2.5
        ds.setString("0.0\\0.0\\\(z)", for: .imagePositionPatient, vr: .DS)
        ds.setString(String(z),        for: .sliceLocation,        vr: .DS)
        ds.setString("0.8\\0.8",       for: .pixelSpacing,         vr: .DS)
        ds.setString("2.5",            for: .sliceThickness,       vr: .DS)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixelData)
        return try DICOMFile.create(
            dataSet: ds,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: ds.string(for: .sopInstanceUID)!,
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        )
    }
}
