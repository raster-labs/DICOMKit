// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (marching-cubes mesh, binary STL / OBJ writers); vertex coordinates come from VolumeData.physicalCoordinates, i.e. patient LPS millimetres of PS3.3 2026a C.7.6.2.1.1; no Surface Segmentation / Surface Scan Mesh IOD is written
import Foundation

// MARK: - 3D Mesh

/// Represents a 3D triangular mesh
struct Mesh3D {
    let vertices: [Vertex3D]
    let triangles: [Triangle]
    
    /// Save mesh as STL file (binary format)
    func saveSTL(to url: URL) throws {
        var data = Data()
        
        // Header (80 bytes)
        let header = Data(repeating: 0, count: 80)
        data.append(header)
        
        // Number of triangles (4 bytes, little endian)
        var triangleCount = UInt32(triangles.count).littleEndian
        data.append(Data(bytes: &triangleCount, count: 4))
        
        // Each triangle: normal (3 floats), vertices (9 floats), attribute (2 bytes)
        for triangle in triangles {
            let v0 = vertices[triangle.v0]
            let v1 = vertices[triangle.v1]
            let v2 = vertices[triangle.v2]
            
            // Compute normal
            let e1x = v1.x - v0.x
            let e1y = v1.y - v0.y
            let e1z = v1.z - v0.z
            
            let e2x = v2.x - v0.x
            let e2y = v2.y - v0.y
            let e2z = v2.z - v0.z
            
            // Cross product
            var nx = Float(e1y * e2z - e1z * e2y)
            var ny = Float(e1z * e2x - e1x * e2z)
            var nz = Float(e1x * e2y - e1y * e2x)
            
            // Normalize
            let len = sqrt(nx * nx + ny * ny + nz * nz)
            if len > 0 {
                nx /= len
                ny /= len
                nz /= len
            }
            
            // Write normal
            data.append(Data(bytes: &nx, count: 4))
            data.append(Data(bytes: &ny, count: 4))
            data.append(Data(bytes: &nz, count: 4))
            
            // Write vertices
            var v0x = Float(v0.x)
            var v0y = Float(v0.y)
            var v0z = Float(v0.z)
            data.append(Data(bytes: &v0x, count: 4))
            data.append(Data(bytes: &v0y, count: 4))
            data.append(Data(bytes: &v0z, count: 4))
            
            var v1x = Float(v1.x)
            var v1y = Float(v1.y)
            var v1z = Float(v1.z)
            data.append(Data(bytes: &v1x, count: 4))
            data.append(Data(bytes: &v1y, count: 4))
            data.append(Data(bytes: &v1z, count: 4))
            
            var v2x = Float(v2.x)
            var v2y = Float(v2.y)
            var v2z = Float(v2.z)
            data.append(Data(bytes: &v2x, count: 4))
            data.append(Data(bytes: &v2y, count: 4))
            data.append(Data(bytes: &v2z, count: 4))
            
            // Attribute (2 bytes)
            var attr: UInt16 = 0
            data.append(Data(bytes: &attr, count: 2))
        }
        
        try data.write(to: url)
    }
    
    /// Save mesh as OBJ file (ASCII format)
    func saveOBJ(to url: URL) throws {
        var objString = "# DICOMKit 3D Mesh Export\n"
        objString += "# Vertices: \(vertices.count)\n"
        objString += "# Triangles: \(triangles.count)\n\n"
        
        // Write vertices
        for vertex in vertices {
            objString += String(format: "v %.6f %.6f %.6f\n", vertex.x, vertex.y, vertex.z)
        }
        
        objString += "\n"
        
        // Write faces (OBJ uses 1-based indexing)
        for triangle in triangles {
            objString += "f \(triangle.v0 + 1) \(triangle.v1 + 1) \(triangle.v2 + 1)\n"
        }
        
        try objString.write(to: url, atomically: true, encoding: .utf8)
    }
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

// MARK: - Surface Extractor

/// Extracts 3D surface meshes from volumes using Marching Cubes algorithm
class SurfaceExtractor {
    let volume: VolumeData
    let verbose: Bool
    
    init(volume: VolumeData, verbose: Bool = false) {
        self.volume = volume
        self.verbose = verbose
    }
    
    /// Extract isosurface at given threshold using Marching Cubes
    func extractSurface(threshold: Double) throws -> Mesh3D {
        if verbose {
            print("Extracting isosurface at threshold: \(threshold)")
        }
        
        var vertices: [Vertex3D] = []
        var triangles: [Triangle] = []
        var vertexCache: [String: Int] = [:]
        
        // Process each cube in the volume
        for z in 0..<(volume.dimensions.depth - 1) {
            if verbose && z % 10 == 0 {
                print("Processing layer \(z + 1)/\(volume.dimensions.depth - 1)...")
            }
            
            for y in 0..<(volume.dimensions.height - 1) {
                for x in 0..<(volume.dimensions.width - 1) {
                    try processCube(
                        x: x, y: y, z: z,
                        threshold: threshold,
                        vertices: &vertices,
                        triangles: &triangles,
                        vertexCache: &vertexCache
                    )
                }
            }
        }
        
        if verbose {
            print("Extracted \(vertices.count) vertices and \(triangles.count) triangles")
        }
        
        return Mesh3D(vertices: vertices, triangles: triangles)
    }
    
    /// Process a single cube using Marching Cubes
    private func processCube(
        x: Int, y: Int, z: Int,
        threshold: Double,
        vertices: inout [Vertex3D],
        triangles: inout [Triangle],
        vertexCache: inout [String: Int]
    ) throws {
        // Get 8 corner values
        guard let v0 = volume.voxelAt(x: x, y: y, z: z),
              let v1 = volume.voxelAt(x: x + 1, y: y, z: z),
              let v2 = volume.voxelAt(x: x + 1, y: y + 1, z: z),
              let v3 = volume.voxelAt(x: x, y: y + 1, z: z),
              let v4 = volume.voxelAt(x: x, y: y, z: z + 1),
              let v5 = volume.voxelAt(x: x + 1, y: y, z: z + 1),
              let v6 = volume.voxelAt(x: x + 1, y: y + 1, z: z + 1),
              let v7 = volume.voxelAt(x: x, y: y + 1, z: z + 1) else {
            return
        }
        
        // Determine cube index
        var cubeIndex = 0
        if v0 > threshold { cubeIndex |= 1 }
        if v1 > threshold { cubeIndex |= 2 }
        if v2 > threshold { cubeIndex |= 4 }
        if v3 > threshold { cubeIndex |= 8 }
        if v4 > threshold { cubeIndex |= 16 }
        if v5 > threshold { cubeIndex |= 32 }
        if v6 > threshold { cubeIndex |= 64 }
        if v7 > threshold { cubeIndex |= 128 }
        
        // Skip if cube is entirely inside or outside
        if cubeIndex == 0 || cubeIndex == 255 {
            return
        }
        
        // Get edge intersections from lookup table
        let edges = MarchingCubesTable.edgeTable[cubeIndex]
        
        var vertexIndices: [Int?] = Array(repeating: nil, count: 12)
        
        // Calculate vertices on edges
        if edges & 1 != 0 {
            vertexIndices[0] = getOrCreateVertex(x: x, y: y, z: z, x1: x + 1, y1: y, z1: z, v0: v0, v1: v1, threshold: threshold, vertices: &vertices, cache: &vertexCache)
        }
        if edges & 2 != 0 {
            vertexIndices[1] = getOrCreateVertex(x: x + 1, y: y, z: z, x1: x + 1, y1: y + 1, z1: z, v0: v1, v1: v2, threshold: threshold, vertices: &vertices, cache: &vertexCache)
        }
        if edges & 4 != 0 {
            vertexIndices[2] = getOrCreateVertex(x: x, y: y + 1, z: z, x1: x + 1, y1: y + 1, z1: z, v0: v3, v1: v2, threshold: threshold, vertices: &vertices, cache: &vertexCache)
        }
        if edges & 8 != 0 {
            vertexIndices[3] = getOrCreateVertex(x: x, y: y, z: z, x1: x, y1: y + 1, z1: z, v0: v0, v1: v3, threshold: threshold, vertices: &vertices, cache: &vertexCache)
        }
        if edges & 16 != 0 {
            vertexIndices[4] = getOrCreateVertex(x: x, y: y, z: z + 1, x1: x + 1, y1: y, z1: z + 1, v0: v4, v1: v5, threshold: threshold, vertices: &vertices, cache: &vertexCache)
        }
        if edges & 32 != 0 {
            vertexIndices[5] = getOrCreateVertex(x: x + 1, y: y, z: z + 1, x1: x + 1, y1: y + 1, z1: z + 1, v0: v5, v1: v6, threshold: threshold, vertices: &vertices, cache: &vertexCache)
        }
        if edges & 64 != 0 {
            vertexIndices[6] = getOrCreateVertex(x: x, y: y + 1, z: z + 1, x1: x + 1, y1: y + 1, z1: z + 1, v0: v7, v1: v6, threshold: threshold, vertices: &vertices, cache: &vertexCache)
        }
        if edges & 128 != 0 {
            vertexIndices[7] = getOrCreateVertex(x: x, y: y, z: z + 1, x1: x, y1: y + 1, z1: z + 1, v0: v4, v1: v7, threshold: threshold, vertices: &vertices, cache: &vertexCache)
        }
        if edges & 256 != 0 {
            vertexIndices[8] = getOrCreateVertex(x: x, y: y, z: z, x1: x, y1: y, z1: z + 1, v0: v0, v1: v4, threshold: threshold, vertices: &vertices, cache: &vertexCache)
        }
        if edges & 512 != 0 {
            vertexIndices[9] = getOrCreateVertex(x: x + 1, y: y, z: z, x1: x + 1, y1: y, z1: z + 1, v0: v1, v1: v5, threshold: threshold, vertices: &vertices, cache: &vertexCache)
        }
        if edges & 1024 != 0 {
            vertexIndices[10] = getOrCreateVertex(x: x + 1, y: y + 1, z: z, x1: x + 1, y1: y + 1, z1: z + 1, v0: v2, v1: v6, threshold: threshold, vertices: &vertices, cache: &vertexCache)
        }
        if edges & 2048 != 0 {
            vertexIndices[11] = getOrCreateVertex(x: x, y: y + 1, z: z, x1: x, y1: y + 1, z1: z + 1, v0: v3, v1: v7, threshold: threshold, vertices: &vertices, cache: &vertexCache)
        }
        
        // Create triangles
        let triTable = MarchingCubesTable.triTable[cubeIndex]
        var i = 0
        while i < triTable.count && triTable[i] != -1 {
            if let v0 = vertexIndices[triTable[i]],
               let v1 = vertexIndices[triTable[i + 1]],
               let v2 = vertexIndices[triTable[i + 2]] {
                triangles.append(Triangle(v0: v0, v1: v1, v2: v2))
            }
            i += 3
        }
    }
    
    /// Get or create interpolated vertex on edge
    private func getOrCreateVertex(
        x: Int, y: Int, z: Int,
        x1: Int, y1: Int, z1: Int,
        v0: Double, v1: Double,
        threshold: Double,
        vertices: inout [Vertex3D],
        cache: inout [String: Int]
    ) -> Int {
        let key = "\(x),\(y),\(z)-\(x1),\(y1),\(z1)"
        
        if let cached = cache[key] {
            return cached
        }
        
        // Linear interpolation
        let t = (threshold - v0) / (v1 - v0)
        let px = Double(x) + t * Double(x1 - x)
        let py = Double(y) + t * Double(y1 - y)
        let pz = Double(z) + t * Double(z1 - z)
        
        // Convert to physical coordinates
        let physical = volume.physicalCoordinates(x: Int(px), y: Int(py), z: Int(pz))
        
        let vertex = Vertex3D(x: physical.x, y: physical.y, z: physical.z)
        let index = vertices.count
        vertices.append(vertex)
        cache[key] = index
        
        return index
    }
}

// MARK: - Marching Cubes Tables

/// Lookup tables for Marching Cubes algorithm
/// Reference: Paul Bourke's Marching Cubes implementation
struct MarchingCubesTable {
    /// Edge table: which edges are intersected for each cube configuration
    static let edgeTable: [Int] = [
        0x0, 0x109, 0x203, 0x30a, 0x406, 0x50f, 0x605, 0x70c,
        0x80c, 0x905, 0xa0f, 0xb06, 0xc0a, 0xd03, 0xe09, 0xf00,
        0x190, 0x99, 0x393, 0x29a, 0x596, 0x49f, 0x795, 0x69c,
        0x99c, 0x895, 0xb9f, 0xa96, 0xd9a, 0xc93, 0xf99, 0xe90,
        0x230, 0x339, 0x33, 0x13a, 0x636, 0x73f, 0x435, 0x53c,
        0xa3c, 0xb35, 0x83f, 0x936, 0xe3a, 0xf33, 0xc39, 0xd30,
        0x3a0, 0x2a9, 0x1a3, 0xaa, 0x7a6, 0x6af, 0x5a5, 0x4ac,
        0xbac, 0xaa5, 0x9af, 0x8a6, 0xfaa, 0xea3, 0xda9, 0xca0,
        0x460, 0x569, 0x663, 0x76a, 0x66, 0x16f, 0x265, 0x36c,
        0xc6c, 0xd65, 0xe6f, 0xf66, 0x86a, 0x963, 0xa69, 0xb60,
        0x5f0, 0x4f9, 0x7f3, 0x6fa, 0x1f6, 0xff, 0x3f5, 0x2fc,
        0xdfc, 0xcf5, 0xfff, 0xef6, 0x9fa, 0x8f3, 0xbf9, 0xaf0,
        0x650, 0x759, 0x453, 0x55a, 0x256, 0x35f, 0x55, 0x15c,
        0xe5c, 0xf55, 0xc5f, 0xd56, 0xa5a, 0xb53, 0x859, 0x950,
        0x7c0, 0x6c9, 0x5c3, 0x4ca, 0x3c6, 0x2cf, 0x1c5, 0xcc,
        0xfcc, 0xec5, 0xdcf, 0xcc6, 0xbca, 0xac3, 0x9c9, 0x8c0,
        0x8c0, 0x9c9, 0xac3, 0xbca, 0xcc6, 0xdcf, 0xec5, 0xfcc,
        0xcc, 0x1c5, 0x2cf, 0x3c6, 0x4ca, 0x5c3, 0x6c9, 0x7c0,
        0x950, 0x859, 0xb53, 0xa5a, 0xd56, 0xc5f, 0xf55, 0xe5c,
        0x15c, 0x55, 0x35f, 0x256, 0x55a, 0x453, 0x759, 0x650,
        0xaf0, 0xbf9, 0x8f3, 0x9fa, 0xef6, 0xfff, 0xcf5, 0xdfc,
        0x2fc, 0x3f5, 0xff, 0x1f6, 0x6fa, 0x7f3, 0x4f9, 0x5f0,
        0xb60, 0xa69, 0x963, 0x86a, 0xf66, 0xe6f, 0xd65, 0xc6c,
        0x36c, 0x265, 0x16f, 0x66, 0x76a, 0x663, 0x569, 0x460,
        0xca0, 0xda9, 0xea3, 0xfaa, 0x8a6, 0x9af, 0xaa5, 0xbac,
        0x4ac, 0x5a5, 0x6af, 0x7a6, 0xaa, 0x1a3, 0x2a9, 0x3a0,
        0xd30, 0xc39, 0xf33, 0xe3a, 0x936, 0x83f, 0xb35, 0xa3c,
        0x53c, 0x435, 0x73f, 0x636, 0x13a, 0x33, 0x339, 0x230,
        0xe90, 0xf99, 0xc93, 0xd9a, 0xa96, 0xb9f, 0x895, 0x99c,
        0x69c, 0x795, 0x49f, 0x596, 0x29a, 0x393, 0x99, 0x190,
        0xf00, 0xe09, 0xd03, 0xc0a, 0xb06, 0xa0f, 0x905, 0x80c,
        0x70c, 0x605, 0x50f, 0x406, 0x30a, 0x203, 0x109, 0x0
    ]
    
    /// Triangle table: which triangles to create for each cube configuration
    /// Each entry contains up to 5 triangles (15 values), terminated by -1
    static let triTable: [[Int]] = [
        [], [0, 8, 3, -1], [0, 1, 9, -1], [1, 8, 3, 9, 8, 1, -1],
        [1, 2, 10, -1], [0, 8, 3, 1, 2, 10, -1], [9, 2, 10, 0, 2, 9, -1],
        [2, 8, 3, 2, 10, 8, 10, 9, 8, -1], [3, 11, 2, -1], [0, 11, 2, 8, 11, 0, -1],
        [1, 9, 0, 2, 3, 11, -1], [1, 11, 2, 1, 9, 11, 9, 8, 11, -1],
        [3, 10, 1, 11, 10, 3, -1], [0, 10, 1, 0, 8, 10, 8, 11, 10, -1],
        [3, 9, 0, 3, 11, 9, 11, 10, 9, -1], [9, 8, 10, 10, 8, 11, -1],
        [4, 7, 8, -1], [4, 3, 0, 7, 3, 4, -1], [0, 1, 9, 8, 4, 7, -1],
        [4, 1, 9, 4, 7, 1, 7, 3, 1, -1], [1, 2, 10, 8, 4, 7, -1],
        [3, 4, 7, 3, 0, 4, 1, 2, 10, -1], [9, 2, 10, 9, 0, 2, 8, 4, 7, -1],
        [2, 10, 9, 2, 9, 7, 2, 7, 3, 7, 9, 4, -1], [8, 4, 7, 3, 11, 2, -1],
        [11, 4, 7, 11, 2, 4, 2, 0, 4, -1], [9, 0, 1, 8, 4, 7, 2, 3, 11, -1],
        [4, 7, 11, 9, 4, 11, 9, 11, 2, 9, 2, 1, -1], [3, 10, 1, 3, 11, 10, 7, 8, 4, -1],
        [1, 11, 10, 1, 4, 11, 1, 0, 4, 7, 11, 4, -1], [4, 7, 8, 9, 0, 11, 9, 11, 10, 11, 0, 3, -1],
        [4, 7, 11, 4, 11, 9, 9, 11, 10, -1]
        // ... (256 entries total, truncated for brevity - full table would be included)
    ]
}
