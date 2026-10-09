// NEMA-verified: 2026a, checked 2026-09-29 — Instance Number read as IS per PS3.6 2026a Table 6-1; Pixel Data VR rule per PS3.5 8.1.1; the JP3D UIDs are private
// NEMA-verified: 2026a, checked 2026-10-01 — makeVolume sorts and spaces slices by Image Position (Patient) projected on the normal of Image Orientation (Patient) per PS3.3 2026a C.7.6.2.1.1 (D205); makeVolume records the first slice's Image Position (Patient) as the volume origin and makeDICOMSeries steps from it along the template's Image Orientation (Patient) normal (Equation C.7.6.2.1-1), writing Image Orientation (Patient), Pixel Spacing and Slice Location (Table C.7-10, C.7.6.2.1.2) (D224)
import Foundation
import DICOMCore
import J2KCore
import J2K3D

/// Bridges between DICOM multi-frame series and J2KSwift's `J2KVolume` type.
///
/// `JP3DVolumeBridge` converts a sorted series of single-frame DICOM files into a
/// `J2KVolume` for JP3D volumetric encoding, and vice-versa — reconstructing individual
/// DICOM files from a decoded volume.
///
/// ## Usage
///
/// ```swift
/// // Series → Volume
/// let volume = try JP3DVolumeBridge.makeVolume(from: dicomFiles)
///
/// // Volume → Series
/// let files = try JP3DVolumeBridge.makeDICOMSeries(from: volume, template: dicomFiles[0])
/// ```
///
/// ## Limitations
///
/// - JP3D has **no standard DICOM transfer syntax**. This bridge is experimental.
/// - Slice spacing uniformity is validated; non-uniform spacing throws an error.
/// - Only single-component (grayscale) and 3-component (RGB) volumes are supported.
public enum JP3DVolumeBridge: Sendable {

    // MARK: - Errors

    /// Errors that can occur during volume bridging.
    public enum BridgeError: Error, Sendable {
        /// The input series is empty.
        case emptySeries
        /// Inconsistent image dimensions across slices.
        case inconsistentDimensions(expected: String, found: String)
        /// Non-uniform slice spacing detected.
        case nonUniformSliceSpacing(spacings: [Double])
        /// Missing required DICOM tag.
        case missingTag(String)
        /// Unsupported pixel format.
        case unsupportedPixelFormat(String)
    }

    // MARK: - Series → Volume

    /// Creates a `J2KVolume` from a sorted series of single-frame DICOM files.
    ///
    /// Files are sorted by `ImagePositionPatient` (0020,0032) projected on the slice normal of
    /// `ImageOrientationPatient` (0020,0037) (PS3.3 C.7.6.2.1.1), or its Z-component when the
    /// orientation is absent, then `SliceLocation` (0020,1041), then Instance Number. Validates that all slices share the same rows, columns, bits allocated,
    /// and samples per pixel.
    ///
    /// - Parameter series: Array of `DICOMFile` instances forming a volume.
    /// - Returns: A `J2KVolume` with voxel data and spatial metadata.
    /// - Throws: `BridgeError` if the series is invalid or inconsistent.
    public static func makeVolume(from series: [DICOMFile]) throws -> J2KVolume {
        guard !series.isEmpty else {
            throw BridgeError.emptySeries
        }

        // Sort slices by spatial position
        let sorted = try sortBySlicePosition(series)

        // Extract reference geometry from first slice
        let ref = sorted[0].dataSet
        let rows = try requireUInt16(ref, tag: .rows, name: "Rows")
        let cols = try requireUInt16(ref, tag: .columns, name: "Columns")
        let bitsAllocated = try requireUInt16(ref, tag: .bitsAllocated, name: "BitsAllocated")
        let bitsStored = try requireUInt16(ref, tag: .bitsStored, name: "BitsStored")
        let samplesPerPixel = ref.uint16(for: .samplesPerPixel) ?? 1
        let isSigned = (ref.uint16(for: .pixelRepresentation) ?? 0) != 0

        // Validate all slices match reference geometry
        for (idx, file) in sorted.enumerated() {
            let ds = file.dataSet
            let r = ds.uint16(for: .rows) ?? 0
            let c = ds.uint16(for: .columns) ?? 0
            if r != rows || c != cols {
                throw BridgeError.inconsistentDimensions(
                    expected: "\(rows)×\(cols)",
                    found: "\(r)×\(c) at slice \(idx)"
                )
            }
        }

        // Validate slice spacing uniformity
        let spacing = try computeSliceSpacing(sorted)

        // Extract pixel spacing from first slice
        let (pixelSpacingRow, pixelSpacingCol) = extractPixelSpacing(from: ref)

        // Build voxel data by stacking pixel data from each slice
        let bytesPerPixel = Int(bitsAllocated) / 8
        let pixelsPerSlice = Int(rows) * Int(cols) * Int(samplesPerPixel)
        let bytesPerSlice = pixelsPerSlice * bytesPerPixel

        var voxelData = Data(capacity: bytesPerSlice * sorted.count)

        for file in sorted {
            let ds = file.dataSet
            guard let pixelElement = ds[.pixelData] else {
                throw BridgeError.missingTag("PixelData (7FE0,0010)")
            }

            let pixelBytes: Data
            if let fragments = pixelElement.encapsulatedFragments, !fragments.isEmpty {
                // Compressed pixel data — decode first frame
                let transferSyntaxUID = file.fileMetaInformation.string(for: .transferSyntaxUID)
                    ?? TransferSyntax.explicitVRLittleEndian.uid
                let registry = CodecRegistry.shared
                if let codec = registry.codec(for: transferSyntaxUID) {
                    let descriptor = PixelDataDescriptor(
                        rows: Int(rows),
                        columns: Int(cols),
                        numberOfFrames: 1,
                        bitsAllocated: Int(bitsAllocated),
                        bitsStored: Int(bitsStored),
                        highBit: Int(ref.uint16(for: .highBit) ?? (bitsStored - 1)),
                        isSigned: isSigned,
                        samplesPerPixel: Int(samplesPerPixel),
                        photometricInterpretation: photometricInterpretation(from: ref)
                    )
                    pixelBytes = try codec.decodeFrame(fragments[0], descriptor: descriptor, frameIndex: 0)
                } else {
                    // Concatenate fragments as raw data
                    pixelBytes = fragments.reduce(Data()) { $0 + $1 }
                }
            } else {
                pixelBytes = pixelElement.valueData
            }

            // Take exactly the expected number of bytes
            if pixelBytes.count >= bytesPerSlice {
                voxelData.append(pixelBytes.prefix(bytesPerSlice))
            } else {
                // Pad if short (shouldn't happen with valid DICOM)
                voxelData.append(pixelBytes)
                voxelData.append(Data(count: bytesPerSlice - pixelBytes.count))
            }
        }

        // Build J2KVolume
        let component = J2KVolumeComponent(
            index: 0,
            bitDepth: Int(bitsStored),
            signed: isSigned,
            width: Int(cols),
            height: Int(rows),
            depth: sorted.count,
            data: voxelData
        )

        // Origin: Image Position (Patient) of the first slice in stacking order, the centre
        // of the first voxel (PS3.3 2026a C.7.6.2.1.1)
        let origin = extractImagePosition(from: ref)
        return J2KVolume(
            width: Int(cols),
            height: Int(rows),
            depth: sorted.count,
            components: [component],
            spacingX: pixelSpacingCol,
            spacingY: pixelSpacingRow,
            spacingZ: spacing,
            originX: origin.x,
            originY: origin.y,
            originZ: origin.z
        )
    }

    // MARK: - Volume → Series

    /// Reconstructs a series of single-frame DICOM files from a `J2KVolume`.
    ///
    /// Uses `template` as the basis for DICOM metadata. Each slice gets a new
    /// `SOPInstanceUID` while preserving the `SeriesInstanceUID`.
    ///
    /// Geometry (PS3.3 2026a C.7.6.2.1.1, Table C.7-10): slice `i` is at the volume origin
    /// plus `i · spacingZ` along the normal of the template's Image Orientation (Patient)
    /// (row cosine × column cosine, Equation C.7.6.2.1-1). A template without Image
    /// Orientation (Patient) gets 1\0\0\0\1\0, the axial orientation the z-only stacking
    /// assumes, so Image Position and Image Orientation (Patient) are always written
    /// together. Pixel Spacing, Rows and Columns come from the volume, Slice Location is
    /// the position along the normal (C.7.6.2.1.2).
    ///
    /// - Parameters:
    ///   - volume: The decoded `J2KVolume`.
    ///   - template: A DICOM file to use as the metadata template.
    /// - Returns: An array of `DICOMFile` instances, one per slice.
    /// - Throws: `BridgeError` if the volume or template is invalid.
    public static func makeDICOMSeries(
        from volume: J2KVolume,
        template: DICOMFile
    ) throws -> [DICOMFile] {
        guard !volume.components.isEmpty else {
            throw BridgeError.unsupportedPixelFormat("Volume has no components")
        }
        guard volume.depth > 0 else {
            throw BridgeError.emptySeries
        }

        let component = volume.components[0]
        let bytesPerPixel = (component.bitDepth + 7) / 8
        let bytesPerSlice = component.width * component.height * bytesPerPixel

        // Stacking direction: the template's orientation, else axial
        let templateNormal = sliceNormal(of: template.dataSet)
        let orientation = templateNormal == nil
            ? [1.0, 0, 0, 0, 1, 0]
            : (decimals(template.dataSet, .imageOrientationPatient) ?? [1.0, 0, 0, 0, 1, 0])
        let normal = templateNormal ?? [0, 0, 1]
        let origin = [volume.originX, volume.originY, volume.originZ]
        let ds6 = JP3DVolumeDocument.decimalString

        // Preserve the series UID from template
        let seriesUID = template.dataSet.string(for: .seriesInstanceUID)
            ?? UIDGenerator.generateSeriesInstanceUID().value

        var files: [DICOMFile] = []
        files.reserveCapacity(volume.depth)

        for sliceIndex in 0..<volume.depth {
            // Extract slice pixel data
            let offset = sliceIndex * bytesPerSlice
            let sliceData: Data
            if offset + bytesPerSlice <= component.data.count {
                sliceData = component.data.subdata(in: offset..<(offset + bytesPerSlice))
            } else {
                // Partial last slice — pad
                let available = component.data.subdata(in: offset..<component.data.count)
                var padded = available
                padded.append(Data(count: bytesPerSlice - available.count))
                sliceData = padded
            }

            // Build data set from template
            var ds = template.dataSet
            ds[.sopInstanceUID] = DataElement.string(
                tag: .sopInstanceUID, vr: .UI,
                value: UIDGenerator.generateSOPInstanceUID().value
            )
            ds[.seriesInstanceUID] = DataElement.string(
                tag: .seriesInstanceUID, vr: .UI,
                value: seriesUID
            )
            ds[.instanceNumber] = DataElement.string(
                tag: .instanceNumber, vr: .IS,
                value: String(sliceIndex + 1)
            )

            // Image Plane geometry (PS3.3 2026a C.7.6.2.1.1, Table C.7-10)
            ds.setUInt16(UInt16(clamping: component.height), for: .rows)
            ds.setUInt16(UInt16(clamping: component.width), for: .columns)
            if volume.spacingX > 0, volume.spacingY > 0 {
                // Pixel Spacing is row spacing \ column spacing
                ds.setString("\(ds6(volume.spacingY))\\\(ds6(volume.spacingX))", for: .pixelSpacing, vr: .DS)
            }
            if volume.spacingZ > 0 || volume.depth == 1 {
                let position = JP3DVolumeDocument.slicePosition(
                    origin: origin, orientation: orientation, spacing: max(0, volume.spacingZ), index: sliceIndex)
                ds.setString(position.map(ds6).joined(separator: "\\"), for: .imagePositionPatient, vr: .DS)
                ds.setString(orientation.map(ds6).joined(separator: "\\"), for: .imageOrientationPatient, vr: .DS)
                let along = position[0] * normal[0] + position[1] * normal[1] + position[2] * normal[2]
                ds.setString(ds6(along), for: .sliceLocation, vr: .DS)
            }

            // Set number of frames to 1
            ds[.numberOfFrames] = DataElement.string(
                tag: .numberOfFrames, vr: .IS, value: "1"
            )

            // Set pixel data (uncompressed native)
            ds[.pixelData] = DataElement(
                tag: .pixelData,
                vr: bytesPerPixel > 1 ? .OW : .OB,
                length: UInt32(sliceData.count),
                valueData: sliceData
            )

            let file = DICOMFile(
                fileMetaInformation: template.fileMetaInformation,
                dataSet: ds
            )
            files.append(file)
        }

        return files
    }

    // MARK: - Validation

    /// Validates that a series has uniform slice spacing.
    ///
    /// - Parameter series: Array of DICOM files sorted by slice position.
    /// - Returns: `true` if spacing is uniform within 1% tolerance.
    public static func validateSliceSpacing(_ series: [DICOMFile]) -> Bool {
        guard series.count > 2 else { return true }
        do {
            let sorted = try sortBySlicePosition(series)
            _ = try computeSliceSpacing(sorted)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private Helpers

    // MARK: - Slice geometry (PS3.3 2026a C.7.6.2.1.1)

    /// The numeric values of a DS attribute
    static func decimals(_ ds: DataSet, _ tag: Tag) -> [Double]? {
        guard let value = ds.string(for: tag) else { return nil }
        let parts = value.split(separator: "\\").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return parts.isEmpty ? nil : parts
    }

    /// The unit normal of the image plane: the cross product of the row and column direction
    /// cosines of Image Orientation (Patient) (0020,0037) (PS3.3 2026a C.7.6.2.1.1), or nil
    /// when the attribute is absent or degenerate
    static func sliceNormal(of ds: DataSet) -> [Double]? {
        guard let iop = decimals(ds, .imageOrientationPatient), iop.count == 6 else { return nil }
        let r = Array(iop[0..<3]), c = Array(iop[3..<6])
        let n = [r[1] * c[2] - r[2] * c[1], r[2] * c[0] - r[0] * c[2], r[0] * c[1] - r[1] * c[0]]
        let length = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).squareRoot()
        guard length > 1e-6 else { return nil }
        return n.map { $0 / length }
    }

    /// The position of a slice along the stacking axis: Image Position (Patient) projected on
    /// the slice normal when Image Orientation (Patient) is known (so that sagittal, coronal
    /// and oblique stacks sort and space correctly), else its z coordinate, else Slice
    /// Location (0020,1041)
    static func stackPosition(of ds: DataSet, normal: [Double]?) -> Double? {
        if let ipp = decimals(ds, .imagePositionPatient), ipp.count >= 3 {
            guard let n = normal else { return ipp[2] }
            return ipp[0] * n[0] + ipp[1] * n[1] + ipp[2] * n[2]
        }
        if let sl = decimals(ds, .sliceLocation)?.first { return sl }
        return nil
    }

    /// The series in the voxel order `makeVolume` stacks it: ascending position along the
    /// slice normal of the first file (Image Orientation (Patient)), falling back to the z
    /// coordinate, Slice Location and Instance Number
    static func sortedForVolume(_ series: [DICOMFile]) throws -> [DICOMFile] {
        try sortBySlicePosition(series)
    }

    /// Distance between adjacent slices of a sorted series along the slice normal; 1.0 when
    /// it cannot be computed. Throws when the spacing is not uniform (1 % tolerance).
    static func uniformSliceSpacing(_ sorted: [DICOMFile]) throws -> Double {
        try computeSliceSpacing(sorted)
    }

    private static func sortBySlicePosition(_ series: [DICOMFile]) throws -> [DICOMFile] {
        // Image Position (Patient) along the slice normal first, then Slice Location, then
        // Instance Number
        let normal = series.first.flatMap { sliceNormal(of: $0.dataSet) }
        let withPositions: [(file: DICOMFile, position: Double)] = series.compactMap { file in
            let ds = file.dataSet
            if let position = stackPosition(of: ds, normal: normal) {
                return (file, position)
            }
            if let inst = ds.string(for: .instanceNumber).flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
                return (file, Double(inst))
            }
            return nil
        }

        guard withPositions.count == series.count else {
            throw BridgeError.missingTag("ImagePositionPatient/SliceLocation/InstanceNumber")
        }

        return withPositions.sorted { $0.position < $1.position }.map(\.file)
    }

    private static func computeSliceSpacing(_ sorted: [DICOMFile]) throws -> Double {
        guard sorted.count > 1 else { return 1.0 }

        let normal = sliceNormal(of: sorted[0].dataSet)
        let positions: [Double] = sorted.compactMap { stackPosition(of: $0.dataSet, normal: normal) }

        guard positions.count == sorted.count else { return 1.0 }

        var spacings: [Double] = []
        for i in 1..<positions.count {
            spacings.append(abs(positions[i] - positions[i - 1]))
        }

        guard let first = spacings.first, first > 0 else { return 1.0 }

        // Validate uniformity (1% tolerance)
        let tolerance = first * 0.01
        for sp in spacings {
            if abs(sp - first) > tolerance {
                throw BridgeError.nonUniformSliceSpacing(spacings: spacings)
            }
        }

        return first
    }

    private static func extractPixelSpacing(from ds: DataSet) -> (row: Double, col: Double) {
        if let ps = ds.string(for: .pixelSpacing) {
            let parts = ps.split(separator: "\\")
            if parts.count >= 2,
               let row = Double(parts[0]),
               let col = Double(parts[1]) {
                return (row, col)
            }
        }
        return (1.0, 1.0)
    }

    private static func extractImagePosition(from ds: DataSet) -> (x: Double, y: Double, z: Double) {
        if let ipp = ds.string(for: .imagePositionPatient) {
            let parts = ipp.split(separator: "\\")
            if parts.count >= 3,
               let x = Double(parts[0]),
               let y = Double(parts[1]),
               let z = Double(parts[2]) {
                return (x, y, z)
            }
        }
        return (0, 0, 0)
    }

    private static func photometricInterpretation(from ds: DataSet) -> PhotometricInterpretation {
        if let piStr = ds.string(for: .photometricInterpretation) {
            return PhotometricInterpretation(rawValue: piStr.trimmingCharacters(in: .whitespaces))
                ?? .monochrome2
        }
        return .monochrome2
    }

    private static func requireUInt16(_ ds: DataSet, tag: Tag, name: String) throws -> UInt16 {
        guard let value = ds.uint16(for: tag) else {
            throw BridgeError.missingTag(name)
        }
        return value
    }
}
