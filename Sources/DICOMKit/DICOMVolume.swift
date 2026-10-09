// NEMA-verified: 2026a, checked 2026-09-29 — PS3.3 2026a Table C.7-11c (High Bit "shall be one less than Bits Stored"; Photometric Interpretation) and C.7.6.3.1.2 (MONOCHROME1 "minimum sample value is intended to be displayed as white after any VOI gray scale transformations"): carried as fields, voxel() masks to Bits Stored and sign-extends from High Bit (D33); other defaults are API defaults, not standard claims
import Foundation
import DICOMCore
import J2KCore
import J2K3D

/// A decoded, in-memory representation of a DICOM volumetric image.
///
/// `DICOMVolume` holds the voxel data and spatial metadata for a multi-frame
/// DICOM series, whether loaded from a conventional multi-frame file, an
/// array of single-frame slices, or a JP3D Encapsulated Document.
///
/// ## Usage
///
/// Use `DICOMFile.openVolume(from:)` to load and decode a volume:
///
/// ```swift
/// // From a directory of DICOM slice files
/// let volume = try await DICOMFile.openVolume(from: seriesDirectoryURL)
///
/// // From a single JP3D encapsulated document
/// let volume = try await DICOMFile.openVolume(from: jp3dDocumentURL)
///
/// // From a JPIP-referenced DICOM file (fetches pixels from server)
/// let volume = try await DICOMFile.openVolume(from: jpipFileURL, jpipServerURL: serverURL)
///
/// // Progressive quality streaming for huge CT/MR studies
/// for await update in DICOMFile.openVolumeProgressively(
///     serverURL: serverURL, sliceJPIPURIs: jpipURIs, qualityLayers: 4
/// ) {
///     renderSlice(update.sliceData, at: update.sliceIndex)
///     if update.isVolumeComplete { print("All slices at full quality") }
/// }
///
/// // Access pixel data
/// let sliceData = volume.slice(at: 42)
/// print("Dimensions: \(volume.width)×\(volume.height)×\(volume.depth)")
/// ```
public struct DICOMVolume: Sendable {

    // MARK: - Dimensions

    /// Number of columns (voxels along X).
    public let width: Int

    /// Number of rows (voxels along Y).
    public let height: Int

    /// Number of slices (voxels along Z).
    public let depth: Int

    // MARK: - Pixel Encoding

    /// Bits allocated per voxel (8 or 16 for standard DICOM).
    public let bitsAllocated: Int

    /// Bits actually stored per voxel.
    public let bitsStored: Int

    /// High Bit (0028,0102) of the source: the most significant bit of each stored
    /// sample. PS3.3 Table C.7-11c: "High Bit (0028,0102) shall be one less than
    /// Bits Stored (0028,0101)", so stored values occupy bits `0...highBit` of each
    /// voxel and bit `highBit` is the sign bit when ``isSigned`` is `true`.
    public let highBit: Int

    /// Whether voxel values are signed integers.
    public let isSigned: Bool

    /// Photometric Interpretation (0028,0004) of the source (PS3.3 C.7.6.3.1.2).
    ///
    /// The stored voxel values are never inverted when a volume is built, so a
    /// ``PhotometricInterpretation/monochrome1`` volume holds the source values
    /// as written and any Window Center/Width read from the source stays valid.
    /// C.7.6.3.1.2 defines MONOCHROME1 as "The minimum sample value is intended to
    /// be displayed as white after any VOI gray scale transformations have been
    /// performed": whatever renders the volume inverts the gray scale *after*
    /// windowing. See ``isMonochrome1``.
    public let photometricInterpretation: PhotometricInterpretation

    // MARK: - Voxel Spacing (mm)

    /// Voxel size along X (column spacing, mm).
    public let spacingX: Double

    /// Voxel size along Y (row spacing, mm).
    public let spacingY: Double

    /// Voxel size along Z (slice thickness / spacing, mm).
    public let spacingZ: Double

    // MARK: - Image Origin (mm in DICOM patient coordinates)

    /// X-component of the image position of the first slice.
    public let originX: Double

    /// Y-component of the image position of the first slice.
    public let originY: Double

    /// Z-component of the image position of the first slice.
    public let originZ: Double

    // MARK: - Pixel Data

    /// Complete voxel data in frame-major order (all slices concatenated).
    ///
    /// Total size = `width × height × depth × (bitsAllocated / 8)` bytes.
    /// Frames are stored in Z-order (first slice first).
    public let pixelData: Data

    // MARK: - Source Information

    /// Transfer syntax the pixel data was loaded from.
    public let sourceTransferSyntax: TransferSyntax?

    /// Modality (e.g., "CT", "MR", "PT").
    public let modality: String?

    /// Series Instance UID of the source data.
    public let seriesInstanceUID: String?

    /// Study Instance UID.
    public let studyInstanceUID: String?

    // MARK: - Computed Properties

    /// Bytes per voxel (all samples).
    public var bytesPerVoxel: Int { (bitsAllocated + 7) / 8 }

    /// Bytes per slice plane.
    public var bytesPerSlice: Int { width * height * bytesPerVoxel }

    /// Total number of voxels.
    public var voxelCount: Int { width * height * depth }

    /// `true` when the volume is ``PhotometricInterpretation/monochrome1``: after
    /// the VOI (window) transformation the gray scale is displayed inverted, the
    /// minimum value as white (PS3.3 C.7.6.3.1.2). Renderers of the volume check
    /// this flag; the voxel values themselves are the stored values.
    public var isMonochrome1: Bool { photometricInterpretation == .monochrome1 }

    // MARK: - Slice Access

    /// Returns the pixel data for a single slice.
    ///
    /// - Parameter index: Zero-based slice index (0..<depth).
    /// - Returns: Data containing the slice's pixel values, or `nil` if out of range.
    public func slice(at index: Int) -> Data? {
        guard index >= 0, index < depth else { return nil }
        let start = index * bytesPerSlice
        guard start + bytesPerSlice <= pixelData.count else { return nil }
        return pixelData.subdata(in: start..<(start + bytesPerSlice))
    }

    /// Returns the voxel value at the given position.
    ///
    /// For 16-bit signed images, the returned value will be negative for values
    /// above the high bit (e.g., Hounsfield units).
    ///
    /// - Parameters:
    ///   - x: Column index (0..<width).
    ///   - y: Row index (0..<height).
    ///   - z: Slice index (0..<depth).
    /// - Returns: Voxel value as an `Int`, or `nil` if out of bounds.
    public func voxel(x: Int, y: Int, z: Int) -> Int? {
        guard x >= 0, x < width,
              y >= 0, y < height,
              z >= 0, z < depth else { return nil }

        let byteOffset = (z * height * width + y * width + x) * bytesPerVoxel
        guard byteOffset + bytesPerVoxel <= pixelData.count else { return nil }

        let raw: UInt32
        if bytesPerVoxel == 2 {
            raw = UInt32(pixelData.subdata(in: byteOffset..<(byteOffset + 2))
                .withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).littleEndian })
        } else {
            raw = UInt32(pixelData[pixelData.startIndex + byteOffset])
        }
        return Self.sampleValue(raw, bitsStored: bitsStored, highBit: highBit, isSigned: isSigned)
    }

    /// The stored sample in `raw`: bits `(highBit − bitsStored + 1)...highBit`, with
    /// bit `highBit` as the sign bit for two's complement data (PS3.3 Table C.7-11c
    /// High Bit and Pixel Representation; PS3.5 8.1.1). Bits above High Bit are not
    /// part of the sample and are ignored.
    static func sampleValue(_ raw: UInt32, bitsStored: Int, highBit: Int, isSigned: Bool) -> Int {
        let stored = max(1, min(32, bitsStored))
        let lowBit = max(0, highBit - stored + 1)
        let mask: UInt32 = stored >= 32 ? .max : (UInt32(1) << UInt32(stored)) - 1
        let value = (raw >> UInt32(lowBit)) & mask
        if isSigned && stored < 32 && (value & (UInt32(1) << UInt32(stored - 1))) != 0 {
            return Int(value) - (1 << stored)
        }
        return Int(value)
    }

    // MARK: - Initialiser

    /// Creates a `DICOMVolume` with the given parameters.
    ///
    /// `highBit` defaults to `bitsStored − 1`, the only value PS3.3 Table C.7-11c
    /// permits; `photometricInterpretation` defaults to MONOCHROME2.
    public init(
        width: Int,
        height: Int,
        depth: Int,
        bitsAllocated: Int = 16,
        bitsStored: Int = 12,
        highBit: Int? = nil,
        isSigned: Bool = false,
        photometricInterpretation: PhotometricInterpretation = .monochrome2,
        spacingX: Double = 1.0,
        spacingY: Double = 1.0,
        spacingZ: Double = 1.0,
        originX: Double = 0.0,
        originY: Double = 0.0,
        originZ: Double = 0.0,
        pixelData: Data,
        sourceTransferSyntax: TransferSyntax? = nil,
        modality: String? = nil,
        seriesInstanceUID: String? = nil,
        studyInstanceUID: String? = nil
    ) {
        self.width = width
        self.height = height
        self.depth = depth
        self.bitsAllocated = bitsAllocated
        self.bitsStored = bitsStored
        // PS3.3 Table C.7-11c: High Bit shall be one less than Bits Stored.
        self.highBit = highBit ?? max(0, bitsStored - 1)
        self.isSigned = isSigned
        self.photometricInterpretation = photometricInterpretation
        self.spacingX = spacingX
        self.spacingY = spacingY
        self.spacingZ = spacingZ
        self.originX = originX
        self.originY = originY
        self.originZ = originZ
        self.pixelData = pixelData
        self.sourceTransferSyntax = sourceTransferSyntax
        self.modality = modality
        self.seriesInstanceUID = seriesInstanceUID
        self.studyInstanceUID = studyInstanceUID
    }
}

// MARK: - DICOMVolumeProgressiveUpdate

/// A progressive quality update for a single slice retrieved via JPIP.
///
/// Emitted by ``DICOMFile/openVolumeProgressively(serverURL:sliceJPIPURIs:qualityLayers:)``
/// as successive quality layers arrive from the JPIP server.
///
/// The typical rendering pattern is:
///
/// ```swift
/// for await update in DICOMFile.openVolumeProgressively(
///     serverURL: serverURL,
///     sliceJPIPURIs: jpipURIs,
///     qualityLayers: 4
/// ) {
///     renderSlice(update.sliceData, at: update.sliceIndex)
///     if update.isVolumeComplete { print("Volume fully loaded") }
/// }
/// ```
public struct DICOMVolumeProgressiveUpdate: Sendable {

    /// Zero-based index of the slice within the volume.
    public let sliceIndex: Int

    /// Quality layer that was just fetched (1 = lowest, `totalLayers` = full quality).
    public let qualityLayer: Int

    /// Total number of quality layers being fetched.
    public let totalLayers: Int

    /// Decoded pixel bytes for this slice at the current quality level.
    public let sliceData: Data

    /// Slice width in pixels.
    public let width: Int

    /// Slice height in pixels.
    public let height: Int

    /// `true` when this update is the final full-quality delivery for the entire volume.
    public let isVolumeComplete: Bool

    /// Creates a ``DICOMVolumeProgressiveUpdate``.
    public init(
        sliceIndex: Int,
        qualityLayer: Int,
        totalLayers: Int,
        sliceData: Data,
        width: Int,
        height: Int,
        isVolumeComplete: Bool
    ) {
        self.sliceIndex = sliceIndex
        self.qualityLayer = qualityLayer
        self.totalLayers = totalLayers
        self.sliceData = sliceData
        self.width = width
        self.height = height
        self.isVolumeComplete = isVolumeComplete
    }
}
