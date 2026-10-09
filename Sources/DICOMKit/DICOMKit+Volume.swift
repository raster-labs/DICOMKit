// NEMA-verified: 2026a, checked 2026-09-29 — PS3.3 2026a Table C.7-10 (Pixel Spacing row\column order, Image Position/Orientation (Patient), Slice Thickness nominal, Spacing Between Slices), C.7.6.2.1.1 normal, Table C.7-11c Image Pixel (Photometric Interpretation, Bits Stored, High Bit, Pixel Representation read from the source; High Bit default per PS3.5 8.1.1) (P-VOL); Photometric Interpretation and High Bit carried into DICOMVolume and required identical across slices (Table C.7-11c; C.7.6.3.1.2 MONOCHROME1 not inverted) (D33)
import Foundation
import DICOMCore
import J2KCore
import J2K3D

/// Volume loading entry points for DICOMKit.
///
/// These functions provide the high-level `openVolume` API that transparently
/// handles both conventional multi-frame DICOM series and JP3D Encapsulated Documents.
extension DICOMFile {

    /// Opens a volumetric DICOM data source and returns a decoded `DICOMVolume`.
    ///
    /// Automatically detects the source type:
    ///
    /// 1. **JP3D Encapsulated Document** — if `url` points to a single file whose
    ///    SOP class is the DICOMKit JP3D private class, decodes the JP3D codestream.
    /// 2. **Single multi-frame DICOM file** — concatenates all frames into a volume.
    /// 3. **Directory** — reads all `.dcm` files in the directory (non-recursively),
    ///    sorts them by slice position, and concatenates their pixel data.
    ///
    /// - Parameter url: A URL pointing to a single DICOM file or a directory of slices.
    /// - Returns: A `DICOMVolume` ready for display or processing.
    /// - Throws: `DICOMError` or `JP3DVolumeBridge.BridgeError` if loading fails.
    public static func openVolume(from url: URL) async throws -> DICOMVolume {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard exists else {
            throw DICOMError.parsingFailed("Path does not exist: \(url.path)")
        }

        if isDir.boolValue {
            return try await openVolumeFromDirectory(url)
        } else {
            return try await openVolumeFromFile(url)
        }
    }

    // MARK: - Single file

    private static func openVolumeFromFile(_ url: URL) async throws -> DICOMVolume {
        let file = try DICOMFile.read(from: url)

        // Check for JP3D encapsulated document first
        if JP3DVolumeDocument.isJP3DVolumeDocument(file) {
            return try await openVolumeFromJP3DDocument(file)
        }

        // Conventional multi-frame (or single-frame) DICOM
        return try openVolumeFromMultiframe(file)
    }

    // MARK: - JP3D document decode

    private static func openVolumeFromJP3DDocument(_ file: DICOMFile) async throws -> DICOMVolume {
        let slices = try await JP3DVolumeDocument.decode(from: file)
        guard !slices.isEmpty else {
            throw DICOMError.parsingFailed("JP3D document decoded to empty series")
        }

        // Concatenate decoded slice pixel data
        let refDS = slices[0].dataSet
        let rows = Int(refDS.uint16(for: .rows) ?? 0)
        let cols = Int(refDS.uint16(for: .columns) ?? 0)
        let pixel = try uniformPixelEncoding(of: slices, rows: rows, columns: cols)
        let bitsAlloc = pixel.bitsAllocated
        let depth = slices.count

        var allPixels = Data(capacity: rows * cols * (bitsAlloc / 8) * depth)
        for slice in slices {
            if let px = slice.dataSet[.pixelData]?.valueData {
                allPixels.append(px)
            }
        }

        let (spacing, origin) = extractSpatialMetadata(from: slices)
        let tsUID = file.fileMetaInformation.string(for: .transferSyntaxUID)

        return DICOMVolume(
            width: cols,
            height: rows,
            depth: depth,
            bitsAllocated: pixel.bitsAllocated,
            bitsStored: pixel.bitsStored,
            highBit: pixel.highBit,
            isSigned: pixel.isSigned,
            photometricInterpretation: pixel.photometricInterpretation,
            spacingX: spacing.x,
            spacingY: spacing.y,
            spacingZ: spacing.z,
            originX: origin.x,
            originY: origin.y,
            originZ: origin.z,
            pixelData: allPixels,
            sourceTransferSyntax: tsUID.flatMap { TransferSyntax.from(uid: $0) },
            modality: file.dataSet.string(for: .modality),
            seriesInstanceUID: file.dataSet.string(for: .seriesInstanceUID),
            studyInstanceUID: file.dataSet.string(for: .studyInstanceUID)
        )
    }

    // MARK: - Multi-frame DICOM

    private static func openVolumeFromMultiframe(_ file: DICOMFile) throws -> DICOMVolume {
        let ds = file.dataSet
        let rows = Int(ds.uint16(for: .rows) ?? 0)
        let cols = Int(ds.uint16(for: .columns) ?? 0)
        let frames = Int(ds.string(for: .numberOfFrames).flatMap(Int.init) ?? 1)

        guard rows > 0, cols > 0 else {
            throw DICOMError.parsingFailed("Multi-frame volume has no valid image dimensions")
        }

        // Decode pixel data through CodecRegistry if compressed
        let tsUID = file.fileMetaInformation.string(for: .transferSyntaxUID)
            ?? TransferSyntax.explicitVRLittleEndian.uid
        let descriptor = sourceDescriptor(from: ds, rows: rows, columns: cols, numberOfFrames: frames)
        let pixel = VolumePixelEncoding(descriptor)

        let rawPixelData: Data
        if let element = ds[.pixelData] {
            let compressed = element.valueData
            if let codec = CodecRegistry.shared.codec(for: tsUID) {
                rawPixelData = try codec.decode(compressed, descriptor: descriptor)
            } else {
                rawPixelData = compressed
            }
        } else {
            rawPixelData = Data()
        }

        let pixelSpacing = extractPixelSpacing(from: ds)
        // Slice spacing of a single multi-frame object: Spacing Between Slices
        // (0018,0088), "measured from the center-to-center of each slice", when
        // present; otherwise Slice Thickness (0018,0050), which is only the
        // "Nominal slice thickness" (PS3.3 Table C.7-10) and is used as a fallback
        // because a single object carries no second Image Position (Patient).
        let sliceSpacing = ds.string(for: .spacingBetweenSlices).flatMap(Double.init)
            ?? ds.string(for: .sliceThickness).flatMap(Double.init)
            ?? 1.0
        let origin = extractOriginFromDataSet(ds)

        return DICOMVolume(
            width: cols,
            height: rows,
            depth: frames,
            bitsAllocated: pixel.bitsAllocated,
            bitsStored: pixel.bitsStored,
            highBit: pixel.highBit,
            isSigned: pixel.isSigned,
            photometricInterpretation: pixel.photometricInterpretation,
            spacingX: pixelSpacing.x,
            spacingY: pixelSpacing.y,
            spacingZ: sliceSpacing,
            originX: origin.x,
            originY: origin.y,
            originZ: origin.z,
            pixelData: rawPixelData,
            sourceTransferSyntax: TransferSyntax.from(uid: tsUID),
            modality: ds.string(for: .modality),
            seriesInstanceUID: ds.string(for: .seriesInstanceUID),
            studyInstanceUID: ds.string(for: .studyInstanceUID)
        )
    }

    // MARK: - Directory of slice files

    private static func openVolumeFromDirectory(_ url: URL) async throws -> DICOMVolume {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        let dcmURLs = contents.filter {
            $0.pathExtension.lowercased() == "dcm"
                || isDICOMFile($0)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !dcmURLs.isEmpty else {
            throw DICOMError.parsingFailed("No DICOM files found in directory: \(url.path)")
        }

        var files: [DICOMFile] = []
        for fileURL in dcmURLs {
            if let f = try? DICOMFile.read(from: fileURL) {
                files.append(f)
            }
        }
        guard !files.isEmpty else {
            throw DICOMError.parsingFailed("Failed to read any DICOM files in directory: \(url.path)")
        }

        // If the directory contains a single JP3D document, decode it
        if files.count == 1 && JP3DVolumeDocument.isJP3DVolumeDocument(files[0]) {
            return try await openVolumeFromJP3DDocument(files[0])
        }

        return try openVolumeFromSliceSeries(files)
    }

    // MARK: - Series of individual slices

    private static func openVolumeFromSliceSeries(_ files: [DICOMFile]) throws -> DICOMVolume {
        // Sort by ImagePositionPatient Z or SliceLocation
        let sorted = sortSlicesByPosition(files)

        let refDS = sorted[0].dataSet
        let rows = Int(refDS.uint16(for: .rows) ?? 0)
        let cols = Int(refDS.uint16(for: .columns) ?? 0)
        let depth = sorted.count

        guard rows > 0, cols > 0 else {
            throw DICOMError.parsingFailed("Slice series has no valid image dimensions")
        }
        let pixel = try uniformPixelEncoding(of: sorted, rows: rows, columns: cols)
        let bitsAlloc = pixel.bitsAllocated

        var allPixels = Data(capacity: rows * cols * (bitsAlloc / 8) * depth)
        let tsUID = sorted[0].fileMetaInformation.string(for: .transferSyntaxUID)
            ?? TransferSyntax.explicitVRLittleEndian.uid

        for file in sorted {
            guard let element = file.dataSet[.pixelData] else { continue }
            let raw = element.valueData
            if let codec = CodecRegistry.shared.codec(for: tsUID) {
                // Each slice is described by its own Image Pixel Module; the
                // reference slice's values are not assumed for the others.
                let descriptor = sourceDescriptor(
                    from: file.dataSet, rows: rows, columns: cols, numberOfFrames: 1)
                let decoded = try codec.decode(raw, descriptor: descriptor)
                allPixels.append(decoded)
            } else {
                allPixels.append(raw)
            }
        }

        let (spacing, origin) = extractSpatialMetadata(from: sorted)

        return DICOMVolume(
            width: cols,
            height: rows,
            depth: depth,
            bitsAllocated: pixel.bitsAllocated,
            bitsStored: pixel.bitsStored,
            highBit: pixel.highBit,
            isSigned: pixel.isSigned,
            photometricInterpretation: pixel.photometricInterpretation,
            spacingX: spacing.x,
            spacingY: spacing.y,
            spacingZ: spacing.z,
            originX: origin.x,
            originY: origin.y,
            originZ: origin.z,
            pixelData: allPixels,
            sourceTransferSyntax: TransferSyntax.from(uid: tsUID),
            modality: refDS.string(for: .modality),
            seriesInstanceUID: refDS.string(for: .seriesInstanceUID),
            studyInstanceUID: refDS.string(for: .studyInstanceUID)
        )
    }

    // MARK: - Image Pixel Module

    /// The Image Pixel Module attributes a `DICOMVolume` carries (PS3.3 C.7.6.3,
    /// Table C.7-11c), as the source states them.
    struct VolumePixelEncoding: Equatable {
        var rows: Int
        var columns: Int
        var bitsAllocated: Int
        var bitsStored: Int
        var highBit: Int
        var isSigned: Bool
        var samplesPerPixel: Int
        var photometricInterpretation: PhotometricInterpretation

        init(_ d: PixelDataDescriptor) {
            rows = d.rows
            columns = d.columns
            bitsAllocated = d.bitsAllocated
            bitsStored = d.bitsStored
            highBit = d.highBit
            isSigned = d.isSigned
            samplesPerPixel = d.samplesPerPixel
            photometricInterpretation = d.photometricInterpretation
        }
    }

    /// The pixel encoding shared by every slice, or an error naming the first slice
    /// that differs.
    ///
    /// A volume is one array of voxels with one interpretation, so every slice must
    /// agree on Rows, Columns, Bits Allocated, Bits Stored, High Bit, Pixel
    /// Representation, Samples per Pixel and Photometric Interpretation (PS3.3 Table
    /// C.7-11c). A MONOCHROME1 slice among MONOCHROME2 slices would display inverted
    /// relative to its neighbours (C.7.6.3.1.2), and a different High Bit would put
    /// its samples in different bits, so neither is silently merged.
    static func uniformPixelEncoding(
        of slices: [DICOMFile], rows: Int, columns: Int
    ) throws -> VolumePixelEncoding {
        let reference = VolumePixelEncoding(
            sourceDescriptor(from: slices[0].dataSet, rows: rows, columns: columns, numberOfFrames: 1))
        for (index, slice) in slices.enumerated().dropFirst() {
            let ds = slice.dataSet
            let encoding = VolumePixelEncoding(sourceDescriptor(
                from: ds,
                rows: Int(ds.uint16(for: .rows) ?? 0),
                columns: Int(ds.uint16(for: .columns) ?? 0),
                numberOfFrames: 1))
            guard encoding == reference else {
                throw DICOMError.parsingFailed(
                    "Slice \(index) Image Pixel Module differs from slice 0 "
                    + "(\(describe(encoding)) vs \(describe(reference))); a volume needs one pixel encoding")
            }
        }
        return reference
    }

    private static func describe(_ e: VolumePixelEncoding) -> String {
        "\(e.columns)x\(e.rows), \(e.photometricInterpretation.rawValue), "
            + "allocated \(e.bitsAllocated), stored \(e.bitsStored), high bit \(e.highBit), "
            + "\(e.isSigned ? "signed" : "unsigned"), \(e.samplesPerPixel) sample(s)"
    }

    /// The pixel-encoding descriptor exactly as the source Image Pixel Module
    /// (PS3.3 C.7.6.3, Table C.7-11c) states it — nothing is assumed.
    ///
    /// - Photometric Interpretation (0028,0004) is carried through as written. A
    ///   MONOCHROME1 source is **not** inverted: PS3.3 C.7.6.3.1.2 defines it as
    ///   "The minimum sample value is intended to be displayed as white after any
    ///   VOI gray scale transformations have been performed" — a display-stage
    ///   rule applied *after* windowing, so the stored sample values are preserved
    ///   untouched and any Window Center/Width read from the object stays valid.
    ///   The interpretation is carried in ``DICOMVolume/photometricInterpretation``
    ///   so that renderers invert after windowing (D33).
    /// - High Bit (0028,0102) is read from the object; when absent it defaults to
    ///   Bits Stored − 1, the only value PS3.5 8.1.1 permits ("High Bit (0028,0102)
    ///   shall be one less than Bits Stored (0028,0101)").
    /// - Pixel Representation (0028,0103) and Samples per Pixel (0028,0002) are read
    ///   from the object.
    static func sourceDescriptor(
        from ds: DataSet, rows: Int, columns: Int, numberOfFrames: Int
    ) -> PixelDataDescriptor {
        let bitsAlloc = Int(ds.uint16(for: .bitsAllocated) ?? 16)
        let bitsStored = ds.uint16(for: .bitsStored).map(Int.init) ?? bitsAlloc
        let highBit = ds.uint16(for: .highBit).map(Int.init) ?? max(0, bitsStored - 1)
        let isSigned = (ds.uint16(for: .pixelRepresentation) ?? 0) != 0
        let samplesPerPixel = Int(ds.uint16(for: .samplesPerPixel) ?? 1)
        let photometric = ds.string(for: .photometricInterpretation)
            .flatMap { PhotometricInterpretation(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
            ?? .monochrome2
        return PixelDataDescriptor(
            rows: rows,
            columns: columns,
            numberOfFrames: numberOfFrames,
            bitsAllocated: bitsAlloc,
            bitsStored: bitsStored,
            highBit: highBit,
            isSigned: isSigned,
            samplesPerPixel: samplesPerPixel,
            photometricInterpretation: photometric,
            planarConfiguration: Int(ds.uint16(for: .planarConfiguration) ?? 0)
        )
    }

    // MARK: - Spatial helpers

    private typealias Vec3 = (x: Double, y: Double, z: Double)

    private static func extractSpatialMetadata(from slices: [DICOMFile]) -> (spacing: Vec3, origin: Vec3) {
        let refDS = slices[0].dataSet

        // Pixel spacing (row spacing, column spacing in mm)
        let ps = extractPixelSpacing(from: refDS)

        let origin = extractOriginFromDataSet(refDS)
        return (Vec3(ps.x, ps.y, sliceSpacing(of: slices)), origin)
    }

    /// Centre-to-centre distance between adjacent slices, in mm.
    ///
    /// Slice Thickness (0018,0050) is *not* used when anything better exists: PS3.3
    /// Table C.7-10 defines it as the "Nominal slice thickness, in mm", which says
    /// nothing about how far apart the slices were acquired (gaps and overlaps are
    /// both common). In order of preference:
    ///
    /// 1. The distance between consecutive Image Position (Patient) (0020,0032)
    ///    values — "the x, y, and z coordinates of the upper left hand corner
    ///    (center of the first voxel transmitted) of the image, in mm" — projected
    ///    onto the slice normal, the cross product of the row and column direction
    ///    cosines of Image Orientation (Patient) (0020,0037) (PS3.3 C.7.6.2.1.1).
    ///    Without an orientation the Euclidean distance between the positions is used.
    /// 2. Spacing Between Slices (0018,0088): "Spacing between adjacent slices, in
    ///    mm. The spacing is measured from the center-to-center of each slice."
    /// 3. The difference of consecutive Slice Location (0020,1041) values.
    /// 4. Slice Thickness (0018,0050), nominal, as a last resort.
    static func sliceSpacing(of slices: [DICOMFile]) -> Double {
        let refDS = slices[0].dataSet
        if slices.count > 1,
           let p0 = imagePosition(refDS),
           let p1 = imagePosition(slices[1].dataSet) {
            let delta = Vec3(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z)
            if let normal = sliceNormal(refDS) {
                let projected = abs(delta.x * normal.x + delta.y * normal.y + delta.z * normal.z)
                if projected > 0 { return projected }
            }
            let distance = (delta.x * delta.x + delta.y * delta.y + delta.z * delta.z).squareRoot()
            if distance > 0 { return distance }
        }
        if let between = refDS.string(for: .spacingBetweenSlices).flatMap(Double.init), between > 0 {
            return between
        }
        if slices.count > 1,
           let l0 = refDS.string(for: .sliceLocation).flatMap(Double.init),
           let l1 = slices[1].dataSet.string(for: .sliceLocation).flatMap(Double.init),
           abs(l1 - l0) > 0 {
            return abs(l1 - l0)
        }
        return refDS.string(for: .sliceThickness).flatMap(Double.init) ?? 1.0
    }

    private static func extractPixelSpacing(from ds: DataSet) -> Vec3 {
        if let psStr = ds.string(for: .pixelSpacing) {
            let parts = psStr.split(separator: "\\").compactMap { Double($0) }
            if parts.count >= 2 {
                // Pixel Spacing (0028,0030) is "adjacent row spacing (delimiter)
                // adjacent column spacing in mm" (PS3.3 Table C.7-10): value 1 is
                // the Y (row) spacing, value 2 the X (column) spacing.
                return Vec3(parts[1], parts[0], 1.0)
            }
        }
        return Vec3(1.0, 1.0, 1.0)
    }

    private static func extractOriginFromDataSet(_ ds: DataSet) -> Vec3 {
        imagePosition(ds) ?? Vec3(0.0, 0.0, 0.0)
    }

    private static func imagePosition(_ ds: DataSet) -> Vec3? {
        guard let posStr = ds.string(for: .imagePositionPatient) else { return nil }
        let parts = posStr.split(separator: "\\").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return Vec3(parts[0], parts[1], parts[2])
    }

    /// The unit normal of the image plane: row cosines × column cosines from Image
    /// Orientation (Patient) (0020,0037), "Row value for the x, y, and z axes
    /// respectively followed by the Column value for the x, y, and z axes
    /// respectively" (PS3.3 C.7.6.2.1.1).
    private static func sliceNormal(_ ds: DataSet) -> Vec3? {
        guard let str = ds.string(for: .imageOrientationPatient) else { return nil }
        let c = str.split(separator: "\\").compactMap { Double($0) }
        guard c.count == 6 else { return nil }
        let n = Vec3(
            c[1] * c[5] - c[2] * c[4],
            c[2] * c[3] - c[0] * c[5],
            c[0] * c[4] - c[1] * c[3]
        )
        let length = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
        guard length > 0 else { return nil }
        return Vec3(n.x / length, n.y / length, n.z / length)
    }

    /// The slice's position along the stack: the Image Position (Patient) projected
    /// onto the slice normal when an orientation is present, else its z coordinate,
    /// else Slice Location (0020,1041).
    private static func stackCoordinate(of ds: DataSet) -> Double? {
        if let p = imagePosition(ds) {
            if let n = sliceNormal(ds) {
                return p.x * n.x + p.y * n.y + p.z * n.z
            }
            return p.z
        }
        return ds.string(for: .sliceLocation).flatMap(Double.init)
    }

    private static func sortSlicesByPosition(_ files: [DICOMFile]) -> [DICOMFile] {
        files.sorted { a, b in
            let zA = stackCoordinate(of: a.dataSet) ?? 0
            let zB = stackCoordinate(of: b.dataSet) ?? 0
            if zA != zB { return zA < zB }
            let ia = a.dataSet.string(for: .instanceNumber).flatMap(Int.init) ?? 0
            let ib = b.dataSet.string(for: .instanceNumber).flatMap(Int.init) ?? 0
            return ia < ib
        }
    }

    private static func isDICOMFile(_ url: URL) -> Bool {
        // Heuristic: try reading the first 132 bytes for the "DICM" magic
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        let header = handle.readData(ofLength: 132)
        try? handle.close()
        guard header.count == 132 else { return false }
        return header[128] == 0x44 && header[129] == 0x49
            && header[130] == 0x43 && header[131] == 0x4D
    }
}

// MARK: - JPIP Progressive Volume Loading

extension DICOMFile {

    /// Opens a JPIP-referenced DICOM file and fetches its full pixel data from the server.
    ///
    /// Use this overload when you have a DICOM file whose transfer syntax is
    /// ``TransferSyntax/jpipReferenced`` or ``TransferSyntax/jpipReferencedDeflate``
    /// and whose Pixel Data element contains a JPIP target URI.
    ///
    /// For a more memory-efficient approach on large studies, see
    /// ``openVolumeProgressively(serverURL:sliceJPIPURIs:qualityLayers:)``.
    ///
    /// - Parameters:
    ///   - url: Path to the JPIP-referenced DICOM file.
    ///   - jpipServerURL: Base URL of the JPIP server.
    /// - Returns: A ``DICOMVolume`` containing the fully fetched image as a single slice.
    /// - Throws: ``DICOMError`` if the file cannot be read, ``DICOMJPIPError`` if retrieval fails.
    @available(*, unavailable, message: "JPIP retrieval is not implemented in the pinned J2KSwift JPIP module (11.0.2), so this cannot return data. Tracked as F1 in RESEARCH_ADOPTION_PLAN.md.")
    public static func openVolume(from url: URL, jpipServerURL: URL) async throws -> DICOMVolume {
        // Unreachable: this API is @available(*, unavailable). The body is stubbed
        // because Swift does not permit an unavailable function to call the
        // (also unavailable) DICOMJPIPClient.fetchImage. The original implementation
        // is recoverable from git history at de67c39 and should be restored when the
        // upstream JPIP request path lands. F1 in RESEARCH_ADOPTION_PLAN.md.
        throw DICOMJPIPError.retrievalUnavailable
    }

    /// Streams a multi-slice DICOM volume from a JPIP server progressively.
    ///
    /// This API is designed for huge CT/MR studies where loading all slices at full quality
    /// up-front is too slow or memory-intensive. Each slice is fetched at quality layer 1
    /// first (fast, low-fidelity overview), then iteratively refined up to `qualityLayers`.
    ///
    /// The caller receives a ``DICOMVolumeProgressiveUpdate`` for every (slice, layer) pair
    /// as data arrives, allowing the UI to render each slice as soon as its first quality
    /// layer is available and then replace it as higher layers arrive.
    ///
    /// ## Example
    ///
    /// ```swift
    /// for await update in DICOMFile.openVolumeProgressively(
    ///     serverURL: URL(string: "http://pacs.example.com:8080")!,
    ///     sliceJPIPURIs: jpipURIs,
    ///     qualityLayers: 4
    /// ) {
    ///     viewer.updateSlice(
    ///         update.sliceData,
    ///         at: update.sliceIndex,
    ///         size: CGSize(width: update.width, height: update.height)
    ///     )
    ///     if update.isVolumeComplete {
    ///         print("CT volume fully loaded at full quality")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - serverURL: Base URL of the JPIP server (e.g., `http://pacs.example.com:8080`).
    ///   - sliceJPIPURIs: Ordered JPIP target URIs, one per slice, in Z order.
    ///   - qualityLayers: Number of progressive quality passes (default 4; 1 = single full fetch).
    /// - Returns: An `AsyncStream` of ``DICOMVolumeProgressiveUpdate`` values.
    @available(*, unavailable, message: "JPIP retrieval is not implemented in the pinned J2KSwift JPIP module (11.0.2), so this cannot return data. Tracked as F1 in RESEARCH_ADOPTION_PLAN.md.")
    public static func openVolumeProgressively(
        serverURL: URL,
        sliceJPIPURIs: [URL],
        qualityLayers: Int = 4
    ) -> AsyncStream<DICOMVolumeProgressiveUpdate> {
        // Unreachable: this API is @available(*, unavailable). Stubbed for the same
        // reason as openVolume(from:jpipServerURL:) above — an unavailable function
        // may not call the unavailable fetchProgressiveQuality. Original body at
        // git de67c39; restore when upstream JPIP retrieval lands.
        AsyncStream { $0.finish() }
    }
}
