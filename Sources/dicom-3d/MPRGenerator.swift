// NEMA-verified: 2026a, checked 2026-10-01 — plane names against the patient-based coordinate system of PS3.3 2026a C.7.6.2.1.1 (x to patient left, y to posterior, z to head; 3 planes mapped to the volume axis nearest each LPS axis, rows/columns oriented as row +x/+y and column +y/-z); reformatted-plane geometry by Equation C.7.6.2.1-1 with Pixel Spacing row\column order of Table C.7-10; window by the LINEAR function of C.11.2.1.2.1 (width >= 1) and MONOCHROME1 shown inverted (C.7.6.3.1.2); oblique planes sampled by Equation C.7.6.2.1-1 (P = S + X·Δi·i + Y·Δj·j, i column / j row index from zero, Δi column / Δj row spacing, as dumped from part03_2026a.xml) with orthonormal Image Orientation (Patient) in the plane
import Foundation
import DICOMKit
import DICOMCore

#if os(macOS) || os(iOS)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

// MARK: - Plane Types

enum PlaneType {
    case axial
    case sagittal
    case coronal
    case oblique(normal: Point3D, point: Point3D)

    /// Name used in file names, Series Description and Derivation Description.
    var name: String {
        switch self {
        case .axial: return "axial"
        case .sagittal: return "sagittal"
        case .coronal: return "coronal"
        case .oblique: return "oblique"
        }
    }
}

enum ProjectionType {
    case axial
    case sagittal
    case coronal
}

/// The three orthogonal planes, named in the patient-based coordinate system of
/// PS3.3 2026a C.7.6.2.1.1: "the x-axis is increasing to the left hand side of the
/// patient. The y-axis is increasing to the posterior side of the patient. The
/// z-axis is increasing toward the head of the patient."
///
/// - axial (transverse): perpendicular to z; rows run to patient left (+x), columns to posterior (+y)
/// - coronal: perpendicular to y; rows run to patient left (+x), columns toward the feet (−z)
/// - sagittal: perpendicular to x; rows run to posterior (+y), columns toward the feet (−z)
enum PatientPlane: String, CaseIterable {
    case axial
    case sagittal
    case coronal

    /// LPS axis the plane is perpendicular to.
    var normalAxis: Point3D {
        switch self {
        case .axial: return Point3D(x: 0, y: 0, z: 1)
        case .sagittal: return Point3D(x: 1, y: 0, z: 0)
        case .coronal: return Point3D(x: 0, y: 1, z: 0)
        }
    }

    /// Direction the image rows run (left to right on screen).
    var rowDirection: Point3D {
        switch self {
        case .axial, .coronal: return Point3D(x: 1, y: 0, z: 0)
        case .sagittal: return Point3D(x: 0, y: 1, z: 0)
        }
    }

    /// Direction the image columns run (top to bottom on screen).
    var columnDirection: Point3D {
        switch self {
        case .axial: return Point3D(x: 0, y: 1, z: 0)
        case .sagittal, .coronal: return Point3D(x: 0, y: 0, z: -1)
        }
    }

    init(_ plane: PlaneType) {
        switch plane {
        case .sagittal: self = .sagittal
        case .coronal: self = .coronal
        default: self = .axial
        }
    }

    init(_ projection: ProjectionType) {
        switch projection {
        case .axial: self = .axial
        case .sagittal: self = .sagittal
        case .coronal: self = .coronal
        }
    }
}

/// How a patient plane maps onto the volume's index axes (0 = columns, 1 = rows,
/// 2 = slices). The plane is cut perpendicular to the index axis closest to its
/// LPS normal, so a sagittal or coronal acquisition reformats correctly.
struct ReformatLayout: Equatable {
    let fixedAxis: Int
    let uAxis: Int        // runs along the output rows (output column index)
    let uReversed: Bool
    let vAxis: Int        // runs along the output columns (output row index)
    let vReversed: Bool

    init(fixedAxis: Int, uAxis: Int, uReversed: Bool, vAxis: Int, vReversed: Bool) {
        self.fixedAxis = fixedAxis
        self.uAxis = uAxis
        self.uReversed = uReversed
        self.vAxis = vAxis
        self.vReversed = vReversed
    }

    init(plane: PatientPlane, volume: VolumeData) {
        func alignment(_ axis: Int, _ target: Point3D) -> Double { volume.axisDirection(axis).dot(target) }
        let fixed = (0..<3).max { abs(alignment($0, plane.normalAxis)) < abs(alignment($1, plane.normalAxis)) }!
        let others = (0..<3).filter { $0 != fixed }
        let u = abs(alignment(others[0], plane.rowDirection)) >= abs(alignment(others[1], plane.rowDirection))
            ? others[0] : others[1]
        let v = others[0] == u ? others[1] : others[0]
        self.init(fixedAxis: fixed,
                  uAxis: u, uReversed: alignment(u, plane.rowDirection) < 0,
                  vAxis: v, vReversed: alignment(v, plane.columnDirection) < 0)
    }

    /// Volume index of output pixel (i, j) on fixed-axis position k.
    func index(i: Int, j: Int, k: Int, volume: VolumeData) -> [Int] {
        var idx = [0, 0, 0]
        idx[fixedAxis] = k
        idx[uAxis] = uReversed ? volume.axisCount(uAxis) - 1 - i : i
        idx[vAxis] = vReversed ? volume.axisCount(vAxis) - 1 - j : j
        return idx
    }

    func width(_ volume: VolumeData) -> Int { volume.axisCount(uAxis) }
    func height(_ volume: VolumeData) -> Int { volume.axisCount(vAxis) }

    /// Image Plane geometry of an output image whose fixed-axis position is `k`
    /// (fractional for a slab centre): PS3.3 C.7.6.2.1.1 Equation C.7.6.2.1-1.
    func geometry(k: Double, thickness: Double, volume: VolumeData) -> SliceGeometry {
        var first = [0.0, 0.0, 0.0]
        first[fixedAxis] = k
        first[uAxis] = uReversed ? Double(volume.axisCount(uAxis) - 1) : 0
        first[vAxis] = vReversed ? Double(volume.axisCount(vAxis) - 1) : 0
        let position = volume.physicalCoordinates(x: first[0], y: first[1], z: first[2])
        let row = volume.axisDirection(uAxis).scaled(uReversed ? -1 : 1)
        let column = volume.axisDirection(vAxis).scaled(vReversed ? -1 : 1)
        return SliceGeometry(imagePosition: position, rowCosines: row, columnCosines: column,
                             rowSpacing: volume.axisSpacing(vAxis), columnSpacing: volume.axisSpacing(uAxis),
                             sliceThickness: thickness)
    }
}

/// Image Plane attributes of a reformatted image (PS3.3 Table C.7-10).
struct SliceGeometry: Equatable {
    /// Image Position (Patient): centre of the first transmitted pixel.
    let imagePosition: Point3D
    /// Image Orientation (Patient) values 1-3 (row direction) and 4-6 (column direction).
    let rowCosines: Point3D
    let columnCosines: Point3D
    /// Pixel Spacing value 1 (between rows) and value 2 (between columns).
    let rowSpacing: Double
    let columnSpacing: Double
    /// Slice Thickness (0018,0050).
    let sliceThickness: Double
}

// MARK: - Slice Image

/// Represents a 2D slice extracted from a 3D volume
struct SliceImage {
    let width: Int
    let height: Int
    let pixels: [Double]
    var geometry: SliceGeometry? = nil

    /// 8-bit display values: the VOI LUT Function LINEAR of PS3.3 2026a C.11.2.1.2.1
    /// (the function that applies when VOI LUT Function (0028,1056) is absent),
    /// or the full pixel range when no window is given. MONOCHROME1 data are shown
    /// inverted: "The minimum sample value is intended to be displayed as white
    /// after any VOI gray scale transformations" (C.7.6.3.1.2).
    func displayValues(windowCenter: Double? = nil, windowWidth: Double? = nil,
                       monochrome1: Bool = false) -> [UInt8] {
        let window: WindowSettings
        if let wc = windowCenter, let ww = windowWidth {
            window = WindowSettings(center: wc, width: ww, function: .linear)
        } else {
            let minPixel = pixels.min() ?? 0
            let maxPixel = pixels.max() ?? 1
            window = WindowSettings(center: (minPixel + maxPixel) / 2, width: max(maxPixel - minPixel, 0),
                                    function: .linearExact)
        }
        return pixels.map { pixel in
            var normalized = window.apply(to: pixel)
            if monochrome1 { normalized = 1.0 - normalized }
            return UInt8(max(0, min(255, (normalized * 255.0).rounded())))
        }
    }
    
    /// Save as PNG with optional windowing
    func savePNG(to url: URL, windowCenter: Double? = nil, windowWidth: Double? = nil,
                 monochrome1: Bool = false) throws {
        #if os(macOS) || os(iOS)
        let displayPixels = displayValues(windowCenter: windowCenter, windowWidth: windowWidth,
                                          monochrome1: monochrome1)
        guard let providerRef = CGDataProvider(data: Data(displayPixels) as CFData) else {
            throw SliceError.imageCreationFailed
        }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: providerRef,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw SliceError.imageCreationFailed
        }
        
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw SliceError.fileWriteFailed
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        
        guard CGImageDestinationFinalize(destination) else {
            throw SliceError.fileWriteFailed
        }
        #else
        throw SliceError.unsupportedPlatform
        #endif
    }
}

// MARK: - MPR Generator

/// Generates Multi-Planar Reformation (MPR) images from a 3D volume
class MPRGenerator {
    let volume: VolumeData
    let interpolation: InterpolationMethod
    let verbose: Bool
    
    init(volume: VolumeData, interpolation: InterpolationMethod = .linear, verbose: Bool = false) {
        self.volume = volume
        self.interpolation = interpolation
        self.verbose = verbose
    }
    
    /// Generate MPR slices for a given plane type.
    ///
    /// With `sliceThickness`, consecutive planes are averaged into slabs of that
    /// thickness (rounded to whole voxels along the cut axis), one output image per slab.
    func generateMPR(plane: PlaneType, sliceThickness: Double? = nil) throws -> [SliceImage] {
        if case .oblique(let normal, let point) = plane {
            guard let oblique = ObliquePlane(normal: normal, point: point) else {
                throw MPRError.zeroObliqueNormal
            }
            return [generateObliqueSlice(plane: oblique, sliceThickness: sliceThickness)]
        }
        let layout = ReformatLayout(plane: PatientPlane(plane), volume: volume)
        let depth = volume.axisCount(layout.fixedAxis)
        let axisSpacing = volume.axisSpacing(layout.fixedAxis)
        let slab = max(1, Int((( sliceThickness ?? 0) / axisSpacing).rounded()))
        let width = layout.width(volume)
        let height = layout.height(volume)

        var slices: [SliceImage] = []
        var start = 0
        while start < depth {
            let end = min(start + slab, depth)
            var pixels = [Double](repeating: 0, count: width * height)
            for j in 0..<height {
                for i in 0..<width {
                    var sum = 0.0
                    for k in start..<end {
                        sum += volume.voxelAt(layout.index(i: i, j: j, k: k, volume: volume)) ?? 0
                    }
                    pixels[j * width + i] = sum / Double(end - start)
                }
            }
            let thickness: Double
            if end - start == 1, layout.fixedAxis == 2,
               let nominal = volume.template.decimalString(for: .sliceThickness)?.value, nominal > 0 {
                thickness = nominal
            } else {
                thickness = Double(end - start) * axisSpacing
            }
            let centre = Double(start) + Double(end - start - 1) / 2
            slices.append(SliceImage(width: width, height: height, pixels: pixels,
                                     geometry: layout.geometry(k: centre, thickness: thickness, volume: volume)))
            start = end
        }
        return slices
    }
    
    /// One image on an oblique plane (`--planes oblique`), sampled with Equation
    /// C.7.6.2.1-1 of PS3.3 2026a: output pixel (i, j) lies at P = S + X·Δi·i + Y·Δj·j,
    /// where S is the Image Position (Patient) of the first pixel, X / Y the row / column
    /// direction cosines of `plane` and Δi = Δj the output spacing (the smaller in-plane
    /// source spacing). Each P is mapped back to a continuous voxel index and read with
    /// `interpolation` (nearest or trilinear). The image covers the projection of the
    /// volume onto the plane, on a grid that has a pixel centre on `plane.point`; samples
    /// outside the volume take the volume's minimum value. With `sliceThickness`, samples
    /// at Δ-spaced offsets along the normal are averaged into a slab of that thickness.
    func generateObliqueSlice(plane: ObliquePlane, sliceThickness: Double? = nil) -> SliceImage {
        let step = min(volume.spacing.x, volume.spacing.y)
        let X = plane.rowDirection, Y = plane.columnDirection, n = plane.normal

        var us: [Double] = [], vs: [Double] = []
        for cx in [0, volume.dimensions.width - 1] {
            for cy in [0, volume.dimensions.height - 1] {
                for cz in [0, volume.dimensions.depth - 1] {
                    let rel = volume.physicalCoordinates(x: cx, y: cy, z: cz) - plane.point
                    us.append(rel.dot(X)); vs.append(rel.dot(Y))
                }
            }
        }
        let tolerance = 1e-9
        let iMin = floor(us.min()! / step + tolerance), iMax = ceil(us.max()! / step - tolerance)
        let jMin = floor(vs.min()! / step + tolerance), jMax = ceil(vs.max()! / step - tolerance)
        let width = Int(iMax - iMin) + 1
        let height = Int(jMax - jMin) + 1
        let first = plane.point + X.scaled(iMin * step) + Y.scaled(jMin * step)   // S

        let samples = max(1, Int(((sliceThickness ?? 0) / step).rounded()))
        let offsets = (0..<samples).map { (Double($0) - Double(samples - 1) / 2) * step }
        let padding = volume.voxels.min() ?? 0

        var pixels = [Double](repeating: padding, count: width * height)
        for j in 0..<height {
            for i in 0..<width {
                let p = first + X.scaled(step * Double(i)) + Y.scaled(step * Double(j))
                var sum = 0.0, count = 0
                for offset in offsets {
                    if let value = sample(at: p + n.scaled(offset)) { sum += value; count += 1 }
                }
                if count > 0 { pixels[j * width + i] = sum / Double(count) }
            }
        }
        let geometry = SliceGeometry(imagePosition: first, rowCosines: X, columnCosines: Y,
                                     rowSpacing: step, columnSpacing: step,
                                     sliceThickness: sliceThickness ?? step)
        return SliceImage(width: width, height: height, pixels: pixels, geometry: geometry)
    }

    /// Voxel value at a patient (LPS) point, or nil outside the volume's voxel centres.
    func sample(at p: Point3D) -> Double? {
        let c = volume.voxelCoordinates(of: p)
        func snap(_ v: Double, _ count: Int) -> Double? {
            let upper = Double(count - 1), eps = 1e-6
            if v < -eps || v > upper + eps { return nil }
            return min(max(v, 0), upper)
        }
        guard let x = snap(c.x, volume.dimensions.width), let y = snap(c.y, volume.dimensions.height),
              let z = snap(c.z, volume.dimensions.depth) else { return nil }
        return volume.interpolatedVoxelAt(x: x, y: y, z: z, method: interpolation)
    }
}

/// An oblique plane given by `--oblique-normal` and `--oblique-point` (LPS mm, PS3.3
/// 2026a C.7.6.2.1.1). The row (X) and column (Y) directions are those of the patient
/// plane (axial, coronal or sagittal) whose normal is closest to the given normal,
/// projected into the oblique plane and made orthonormal, so an oblique plane close to
/// coronal is displayed like a coronal image. X and Y are the Image Orientation (Patient)
/// of the output.
struct ObliquePlane: Equatable {
    let normal: Point3D
    let point: Point3D
    let rowDirection: Point3D
    let columnDirection: Point3D

    init?(normal given: Point3D, point: Point3D) {
        guard given.length > 1e-9 else { return nil }
        let n = given.normalized
        var reference = PatientPlane.axial
        for candidate in PatientPlane.allCases where abs(candidate.normalAxis.dot(n)) > abs(reference.normalAxis.dot(n)) + 1e-12 {
            reference = candidate
        }
        func reject(_ v: Point3D, from a: Point3D) -> Point3D { v - a.scaled(v.dot(a)) }
        let x = reject(reference.rowDirection, from: n).normalized
        let y = reject(reject(reference.columnDirection, from: n), from: x).normalized
        self.normal = n
        self.point = point
        self.rowDirection = x
        self.columnDirection = y
    }
}

// MARK: - Projection Renderer

/// Renders intensity projection images (MIP, MinIP, Average)
class ProjectionRenderer {
    let volume: VolumeData
    let verbose: Bool
    
    init(volume: VolumeData, verbose: Bool = false) {
        self.volume = volume
        self.verbose = verbose
    }
    
    /// Generate Maximum Intensity Projection
    func maximumIntensityProjection(direction: ProjectionType, slabThickness: Double? = nil) throws -> SliceImage {
        try project(direction, slabThickness: slabThickness) { $0.max() ?? 0 }
    }
    
    /// Generate Minimum Intensity Projection
    func minimumIntensityProjection(direction: ProjectionType, slabThickness: Double? = nil) throws -> SliceImage {
        try project(direction, slabThickness: slabThickness) { $0.min() ?? 0 }
    }
    
    /// Generate Average Intensity Projection
    func averageIntensityProjection(direction: ProjectionType, slabThickness: Double? = nil) throws -> SliceImage {
        try project(direction, slabThickness: slabThickness) { values in
            values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
    }

    /// Project along the volume axis closest to the plane's LPS normal. A slab
    /// thickness limits the projection to that many millimetres centred on the
    /// middle of the volume; nil or 0 projects the whole volume.
    func project(_ direction: ProjectionType, slabThickness: Double? = nil,
                 operation: ([Double]) -> Double) throws -> SliceImage {
        let layout = ReformatLayout(plane: PatientPlane(direction), volume: volume)
        let depth = volume.axisCount(layout.fixedAxis)
        let axisSpacing = volume.axisSpacing(layout.fixedAxis)
        var count = depth
        if let slab = slabThickness, slab > 0 {
            count = min(depth, max(1, Int((slab / axisSpacing).rounded())))
        }
        let start = (depth - count) / 2
        let width = layout.width(volume)
        let height = layout.height(volume)
        var pixels: [Double] = []
        pixels.reserveCapacity(width * height)
        var values: [Double] = []
        values.reserveCapacity(count)
        for j in 0..<height {
            for i in 0..<width {
                values.removeAll(keepingCapacity: true)
                for k in start..<(start + count) {
                    if let value = volume.voxelAt(layout.index(i: i, j: j, k: k, volume: volume)) {
                        values.append(value)
                    }
                }
                pixels.append(operation(values))
            }
        }
        let centre = Double(start) + Double(count - 1) / 2
        return SliceImage(width: width, height: height, pixels: pixels,
                          geometry: layout.geometry(k: centre, thickness: Double(count) * axisSpacing, volume: volume))
    }
}

// MARK: - Errors

enum MPRError: Error, CustomStringConvertible {
    case zeroObliqueNormal

    var description: String {
        switch self {
        case .zeroObliqueNormal: return "--oblique-normal must not be the zero vector"
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
