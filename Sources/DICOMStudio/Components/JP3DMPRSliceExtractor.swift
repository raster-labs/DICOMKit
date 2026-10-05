// JP3DMPRSliceExtractor.swift
// DICOMStudio
//
// Platform-independent slice extraction from DICOMVolume for JP3D MPR views.
// Supports axial, sagittal, and coronal orientations using the decoded
// voxel data produced by the J2K3D codec.
//
// NEMA-verified: 2026a, checked 2026-10-05 — applyWindowLevel is the PS3.3 2026a C.11.2.1.2.1 default LINEAR function (thresholds c − 0.5 ∓ (w−1)/2, slope 255/(w−1); was c ∓ w/2 with slope 255/w); slice extraction is voxel-index geometry, not Image Plane Module data

import Foundation
import DICOMKit

// MARK: - Raw Slice

/// A single extracted MPR slice: raw voxel bytes, dimensions, and spacing.
public struct JP3DMPRRawSlice: Sendable, Equatable {
    /// Width of the slice in pixels.
    public let pixelWidth: Int
    /// Height of the slice in pixels.
    public let pixelHeight: Int
    /// Pixel spacing along the horizontal display axis (mm).
    public let spacingX: Double
    /// Pixel spacing along the vertical display axis (mm).
    public let spacingY: Double
    /// Raw pixel data (same bit-depth as the source volume).
    public let data: Data
    /// Bits allocated per sample (8 or 16).
    public let bitsAllocated: Int
    /// Whether pixel values are signed.
    public let isSigned: Bool

    /// Total number of pixels (pixelWidth × pixelHeight).
    public var pixelCount: Int { pixelWidth * pixelHeight }
}

// MARK: - Slice Extractor

/// Platform-independent slice extractor for multi-planar reconstruction.
///
/// `JP3DMPRSliceExtractor` extracts axial, sagittal, and coronal slices from
/// a ``DICOMVolume`` that was decoded via the J2K3D volumetric codec.
///
/// ## Voxel layout (frame-major, Z-order)
/// ```
/// offset(x, y, z) = (z * height * width + y * width + x) * bytesPerVoxel
/// ```
///
/// ## Axial slice (z = const)
/// Consecutive `width × height` bytes starting at `z * bytesPerSlice`.
///
/// ## Sagittal slice (x = const)
/// Width: `height`, Height: `depth`.
/// For each z-row and y-column: voxel at `(x, y, z)`.
///
/// ## Coronal slice (y = const)
/// Width: `width`, Height: `depth`.
/// For each z-row and x-column: voxel at `(x, y, z)`.
public enum JP3DMPRSliceExtractor: Sendable {

    // MARK: - Public API

    /// Extracts a slice from a volume for the given plane and index.
    ///
    /// - Parameters:
    ///   - volume: The source ``DICOMVolume``.
    ///   - plane: The reconstruction plane (axial, sagittal, or coronal).
    ///   - sliceIndex: Zero-based index along the plane's axis.
    /// - Returns: A ``JP3DMPRRawSlice``, or `nil` if `sliceIndex` is out of range.
    public static func extractSlice(
        from volume: DICOMVolume,
        plane: MPRPlane,
        at sliceIndex: Int
    ) -> JP3DMPRRawSlice? {
        switch plane {
        case .axial:
            return extractAxialSlice(from: volume, at: sliceIndex)
        case .sagittal:
            return extractSagittalSlice(from: volume, at: sliceIndex)
        case .coronal:
            return extractCoronalSlice(from: volume, at: sliceIndex)
        }
    }

    /// Returns the valid range of slice indices for a given plane and volume.
    ///
    /// - Parameters:
    ///   - plane: The reconstruction plane.
    ///   - volume: The source ``DICOMVolume``.
    /// - Returns: A `ClosedRange<Int>` from `0` to the maximum slice index.
    public static func sliceRange(
        for plane: MPRPlane,
        in volume: DICOMVolume
    ) -> ClosedRange<Int> {
        switch plane {
        case .axial:    return 0...(max(0, volume.depth - 1))
        case .sagittal: return 0...(max(0, volume.width - 1))
        case .coronal:  return 0...(max(0, volume.height - 1))
        }
    }

    /// Converts a ``DICOMVolume`` to a ``VolumeDimensionsModel`` for use with
    /// ``MPRHelpers``.
    ///
    /// - Parameter volume: The source volume.
    /// - Returns: A `VolumeDimensionsModel` matching the volume's geometry.
    public static func dimensionsModel(for volume: DICOMVolume) -> VolumeDimensionsModel {
        VolumeDimensionsModel(
            width: volume.width,
            height: volume.height,
            depth: volume.depth,
            spacingX: volume.spacingX,
            spacingY: volume.spacingY,
            spacingZ: volume.spacingZ
        )
    }

    // MARK: - Axial Extraction

    /// Extracts an axial (transverse) slice at `z = sliceIndex`.
    ///
    /// The resulting slice has dimensions `(width × height)` and uses the
    /// volume's X and Y pixel spacings.
    private static func extractAxialSlice(
        from volume: DICOMVolume,
        at sliceIndex: Int
    ) -> JP3DMPRRawSlice? {
        guard sliceIndex >= 0, sliceIndex < volume.depth else { return nil }

        let start = sliceIndex * volume.bytesPerSlice
        guard start + volume.bytesPerSlice <= volume.pixelData.count else { return nil }

        let data = volume.pixelData.subdata(in: start..<(start + volume.bytesPerSlice))

        return JP3DMPRRawSlice(
            pixelWidth: volume.width,
            pixelHeight: volume.height,
            spacingX: volume.spacingX,
            spacingY: volume.spacingY,
            data: data,
            bitsAllocated: volume.bitsAllocated,
            isSigned: volume.isSigned
        )
    }

    // MARK: - Sagittal Extraction

    /// Extracts a sagittal slice at `x = sliceIndex`.
    ///
    /// Slice dimensions: `height` (columns) × `depth` (rows).
    /// For each row `z` and column `y`, the voxel is at `(sliceIndex, y, z)`.
    /// The display axes use Y-spacing (horizontal) and Z-spacing (vertical).
    private static func extractSagittalSlice(
        from volume: DICOMVolume,
        at sliceIndex: Int
    ) -> JP3DMPRRawSlice? {
        guard sliceIndex >= 0, sliceIndex < volume.width else { return nil }
        guard !volume.pixelData.isEmpty else { return nil }

        let bytesPerVoxel = volume.bytesPerVoxel
        let sliceWidth = volume.height
        let sliceHeight = volume.depth
        var data = Data(count: sliceWidth * sliceHeight * bytesPerVoxel)

        data.withUnsafeMutableBytes { rawDst in
            volume.pixelData.withUnsafeBytes { rawSrc in
                guard let dst = rawDst.baseAddress,
                      let src = rawSrc.baseAddress else { return }

                for z in 0..<sliceHeight {
                    for y in 0..<sliceWidth {
                        let srcOffset = (z * volume.height * volume.width
                                         + y * volume.width
                                         + sliceIndex) * bytesPerVoxel
                        let dstOffset = (z * sliceWidth + y) * bytesPerVoxel
                        if srcOffset + bytesPerVoxel <= rawSrc.count {
                            (dst + dstOffset).copyMemory(
                                from: src + srcOffset,
                                byteCount: bytesPerVoxel
                            )
                        }
                    }
                }
            }
        }

        return JP3DMPRRawSlice(
            pixelWidth: sliceWidth,
            pixelHeight: sliceHeight,
            spacingX: volume.spacingY,
            spacingY: volume.spacingZ,
            data: data,
            bitsAllocated: volume.bitsAllocated,
            isSigned: volume.isSigned
        )
    }

    // MARK: - Coronal Extraction

    /// Extracts a coronal slice at `y = sliceIndex`.
    ///
    /// Slice dimensions: `width` (columns) × `depth` (rows).
    /// For each row `z` and column `x`, the voxel is at `(x, sliceIndex, z)`.
    /// The display axes use X-spacing (horizontal) and Z-spacing (vertical).
    private static func extractCoronalSlice(
        from volume: DICOMVolume,
        at sliceIndex: Int
    ) -> JP3DMPRRawSlice? {
        guard sliceIndex >= 0, sliceIndex < volume.height else { return nil }
        guard !volume.pixelData.isEmpty else { return nil }

        let bytesPerVoxel = volume.bytesPerVoxel
        let sliceWidth = volume.width
        let sliceHeight = volume.depth
        var data = Data(count: sliceWidth * sliceHeight * bytesPerVoxel)

        data.withUnsafeMutableBytes { rawDst in
            volume.pixelData.withUnsafeBytes { rawSrc in
                guard let dst = rawDst.baseAddress,
                      let src = rawSrc.baseAddress else { return }

                for z in 0..<sliceHeight {
                    let srcRowBase = (z * volume.height * volume.width
                                      + sliceIndex * volume.width)
                    let dstRowBase = z * sliceWidth

                    let srcStart = srcRowBase * bytesPerVoxel
                    let srcEnd = srcStart + sliceWidth * bytesPerVoxel

                    if srcEnd <= rawSrc.count {
                        (dst + dstRowBase * bytesPerVoxel)
                            .copyMemory(from: src + srcStart, byteCount: sliceWidth * bytesPerVoxel)
                    }
                }
            }
        }

        return JP3DMPRRawSlice(
            pixelWidth: sliceWidth,
            pixelHeight: sliceHeight,
            spacingX: volume.spacingX,
            spacingY: volume.spacingZ,
            data: data,
            bitsAllocated: volume.bitsAllocated,
            isSigned: volume.isSigned
        )
    }

    // MARK: - Window / Level

    /// Applies window/level to produce a 8-bit display buffer.
    ///
    /// The default LINEAR VOI function of PS3.3 C.11.2.1.2.1, with ymin = 0 and
    /// ymax = 255: `x <= c - 0.5 - (w-1)/2` → 0, `x > c - 0.5 + (w-1)/2` → 255,
    /// otherwise `((x - (c - 0.5)) / (w-1) + 0.5) * 255`. A width of 1 is the
    /// threshold the standard describes (the continuous segment is never reached);
    /// a width below 1 is forbidden by the standard and gives a flat mid-grey.
    ///
    /// - Parameters:
    ///   - slice: The extracted raw slice.
    ///   - windowCenter: Window center in the same units as the voxel values.
    ///   - windowWidth: Window width (must be > 0).
    /// - Returns: 8-bit grayscale `Data`, one byte per pixel.
    public static func applyWindowLevel(
        to slice: JP3DMPRRawSlice,
        windowCenter: Double,
        windowWidth: Double
    ) -> Data {
        guard windowWidth >= 1 else {
            return Data(repeating: 128, count: slice.pixelCount)
        }

        // PS3.3 C.11.2.1.2.1: the window spans (c - 0.5) ± (w - 1)/2.
        let halfSpan = (windowWidth - 1) * 0.5
        let lowerEdge = windowCenter - 0.5 - halfSpan
        let upperEdge = windowCenter - 0.5 + halfSpan
        let centreOffset = windowCenter - 0.5
        let span = max(windowWidth - 1, Double.leastNonzeroMagnitude)
        let bytesPerVoxel = (slice.bitsAllocated + 7) / 8
        var output = Data(count: slice.pixelCount)

        slice.data.withUnsafeBytes { rawSrc in
            guard let src = rawSrc.baseAddress else { return }

            for i in 0..<slice.pixelCount {
                let offset = i * bytesPerVoxel
                guard offset + bytesPerVoxel <= rawSrc.count else { continue }

                let rawVal: Int
                if bytesPerVoxel == 2 {
                    let raw = (src + offset).loadUnaligned(as: UInt16.self)
                        .littleEndian
                    rawVal = slice.isSigned ? Int(Int16(bitPattern: raw)) : Int(raw)
                } else {
                    rawVal = Int((src + offset).loadUnaligned(as: UInt8.self))
                }

                let x = Double(rawVal)
                if x <= lowerEdge {
                    output[i] = 0
                } else if x > upperEdge {
                    output[i] = 255
                } else {
                    let y = ((x - centreOffset) / span + 0.5) * 255.0
                    output[i] = UInt8(max(0, min(255, Int(y.rounded()))))
                }
            }
        }

        return output
    }
}
