// NEMA-verified: 2026a, checked 2026-10-01 — PS3.3 2026a: C.11.2.1.2 window formula applied to the Modality LUT output (C.11.1 Rescale / Modality LUT Sequence), Window Width >= 1; output is a Derived Image (C.7.6.1.1.2 Image Type DERIVED + new SOP Instance UID; Table C.12-10 Derivation Description, Source Image Sequence with CID 7202 DCM 121322; CID 7203 has no code for these edits); crop moves Image Position (Patient) per Equation C.7.6.2.1-1 (top level + Plane Position Sequence) and Overlay Origin (C.9.2); samples clamped to Bits Stored / Pixel Representation (C.7.6.3.1); window/invert refused for PALETTE COLOR (C.7.6.3.1.5); Pixel Padding Value/Range Limit remapped or removed (C.7.5.1.1.2); Lossy Image Compression "01" + Method kept after decoding a lossy source (C.7.6.1.1.5); DS at most 16 bytes, ST 1024 chars (PS3.5 Table 6.2-1); PS3.10 Table 7.1-1 (0002,0003/0012/0013)
import Foundation
import DICOMCore
import DICOMDictionary

/// Pixel editing operations.
public enum PixelOperation: Sendable {
    case mask(x: Int, y: Int, width: Int, height: Int, fillValue: Int)
    case crop(x: Int, y: Int, width: Int, height: Int)
    case windowLevel(center: Double, width: Double)
    case invert
}

/// Image dimensions/format after a pixel-edit run (for adapter summaries).
public struct PixelEditInfo: Sendable {
    public let columns: Int
    public let rows: Int
    public let bitsAllocated: Int
    public let samplesPerPixel: Int
}

/// How `PixelEditor.processData` records that its output is a new image derived
/// from the input (PS3.3 2026a C.7.6.1.1.2, General Reference Module Table C.12-10).
public struct PixelEditDerivation: Sendable {
    /// SOP Instance UID of the edited image; nil mints a new one.
    public var sopInstanceUID: String?
    /// Text placed before the list of operations in Derivation Description (0008,2111),
    /// e.g. the name of the tool; empty for none.
    public var descriptionPrefix: String

    public init(sopInstanceUID: String? = nil, descriptionPrefix: String = "Pixel edit") {
        self.sopInstanceUID = sopInstanceUID
        self.descriptionPrefix = descriptionPrefix
    }
}

/// Internal descriptor holding pixel data metadata from the DICOM data set.
/// (Named to avoid colliding with the public `DICOMCore.PixelDataDescriptor`.)
struct PixelEditDescriptor {
    let rows: Int
    let columns: Int
    let bitsAllocated: Int
    let bitsStored: Int
    let highBit: Int
    let pixelRepresentation: Int
    let samplesPerPixel: Int
    let numberOfFrames: Int

    var bytesPerSample: Int { bitsAllocated / 8 }
    var bytesPerPixel: Int { bytesPerSample * samplesPerPixel }
    var maxValue: Int { (1 << bitsStored) - 1 }
    var isSigned: Bool { pixelRepresentation == 1 }

    /// Lowest representable stored value: 0 unsigned, −2^(bitsStored−1) signed.
    var storedMin: Int { isSigned ? -(1 << (bitsStored - 1)) : 0 }
    /// Highest representable stored value: 2^bitsStored−1 unsigned, 2^(bitsStored−1)−1 signed.
    var storedMax: Int { isSigned ? (1 << (bitsStored - 1)) - 1 : (1 << bitsStored) - 1 }

    /// Samples in a single frame (rows × columns × samples-per-pixel).
    var frameSampleCount: Int { rows * columns * samplesPerPixel }
    /// Bytes in a single frame.
    var frameByteCount: Int { frameSampleCount * bytesPerSample }
}

/// Pixel data editor for DICOM files.
///
/// Lives in the DICOMKit library so the `dicom-pixedit` CLI and DICOMStudio run
/// the exact same pixel algorithms. Verbose progress flows through the injected
/// `log` closure. Use `processData` for an in-memory transform (DICOMStudio writes
/// via its sandbox-aware path) or `processFile` for a direct read→write.
public struct PixelEditor {
    public let verbose: Bool
    private let log: (String) -> Void

    public init(verbose: Bool, log: @escaping (String) -> Void = { _ in }) {
        self.verbose = verbose
        self.log = log
    }

    /// Parse a region string in "x,y,width,height" format.
    public func parseRegion(_ regionString: String) throws -> (x: Int, y: Int, width: Int, height: Int) {
        let parts = regionString.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else {
            throw PixelEditError.invalidRegion(regionString)
        }
        guard parts[0] >= 0, parts[1] >= 0, parts[2] > 0, parts[3] > 0 else {
            throw PixelEditError.invalidRegion(regionString)
        }
        return (x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// Applies the operations to a DICOM file given as raw bytes, returning the
    /// edited DICOM bytes plus the resulting image info. No file I/O — the caller
    /// chooses how to persist the result (e.g. a sandbox-aware write).
    ///
    /// - `.windowLevel` center and width are in the output units of the Modality LUT
    ///   (Rescale Slope/Intercept or Modality LUT Sequence, e.g. HU for CT), as Window
    ///   Center/Width are (PS3.3 2026a C.11.2.1.2); the width shall be at least 1.
    /// - `.windowLevel` and `.invert` are refused for PALETTE COLOR, whose stored values
    ///   are palette indices (C.7.6.3.1.5); Pixel Padding Value / Range Limit follow the
    ///   remapped values or are removed when they would collide (C.7.5.1.1.2).
    /// - `.mask` fill values are clamped to the Bits Stored / Pixel Representation range
    ///   (C.7.6.3.1); `.crop` moves Image Position (Patient) (top level and the Plane
    ///   Position Sequence of the functional groups, C.7.6.2.1.1) and Overlay Origin (C.9.2).
    /// - Decoding a lossy compressed source sets Lossy Image Compression "01" and, when
    ///   absent, Lossy Image Compression Method (C.7.6.1.1.5).
    /// - With a `derivation` (the default) the output is a new Derived Image: new SOP
    ///   Instance UID, Image Type Value 1 DERIVED, Derivation Description and a Source
    ///   Image Sequence Item (C.7.6.1.1.2, Table C.12-10), stale Smallest/Largest Pixel
    ///   Values removed, and Implementation Class UID / Version Name of this library
    ///   (PS3.10 Table 7.1-1). Pass `nil` to keep the source identity (de-identification
    ///   pixel redaction does).
    @discardableResult
    public func processData(_ inputData: Data, operations: [PixelOperation],
                            derivation: PixelEditDerivation? = PixelEditDerivation()) throws -> (data: Data, info: PixelEditInfo) {
        let dicomFile = try DICOMFile.read(from: inputData)

        let source = dicomFile.dataSet
        var dataSet = dicomFile.dataSet
        var fileMeta = dicomFile.fileMetaInformation

        guard let pixelElement = dataSet[.pixelData] else {
            throw PixelEditError.noPixelData
        }

        // Window and invert remap stored values; for PALETTE COLOR those are indices into
        // the palette (PS3.3 C.7.6.3.1.5), so remapping them recolours the image at random.
        let photometric = Self.photometricInterpretation(of: dataSet)
        if photometric == "PALETTE COLOR" {
            for operation in operations {
                switch operation {
                case .windowLevel: throw PixelEditError.notApplicableToPaletteColor("window/level")
                case .invert: throw PixelEditError.notApplicableToPaletteColor("invert")
                case .mask, .crop: break
                }
            }
        }

        // Pixel-edit operations work on raw, uncompressed samples. If the source uses
        // an encapsulated (compressed) transfer syntax — RLE, JPEG, JPEG 2000, JPEG-LS,
        // JPEG XL — its Pixel Data element holds a fragmented/compressed bitstream, not a
        // flat pixel array. Editing those bytes in place corrupts the bitstream, and the
        // result (still tagged as the compressed syntax) can't be decoded by a viewer like
        // Horos, so the image fails to display. So decode the source to native pixels via
        // the shared codec path and emit uncompressed Explicit VR Little Endian — the same
        // representation every viewer/CLI expects after a pixel edit.
        let sourceSyntax = dicomFile.transferSyntaxUID.flatMap { TransferSyntax.from(uid: $0) }
        let isEncapsulated = (sourceSyntax?.isEncapsulated ?? false)
            || (pixelElement.encapsulatedFragments?.isEmpty == false)

        let descriptor: PixelEditDescriptor
        var pixelData: Data
        let pixelVR: VR

        if isEncapsulated {
            // Decodes every frame to native samples (and maps YBR JPEG/J2K to RGB).
            let decoded = try dicomFile.tryPixelData()
            let d = decoded.descriptor
            descriptor = PixelEditDescriptor(
                rows: d.rows, columns: d.columns,
                bitsAllocated: d.bitsAllocated, bitsStored: d.bitsStored,
                highBit: d.highBit, pixelRepresentation: d.isSigned ? 1 : 0,
                samplesPerPixel: d.samplesPerPixel, numberOfFrames: d.numberOfFrames
            )
            pixelData = decoded.data
            // Native Pixel Data VR: OW for >8-bit samples, OB for 8-bit.
            pixelVR = d.bitsAllocated > 8 ? .OW : .OB
            // Reflect the decoded format in the data set — decoding can change the
            // photometric interpretation and sample layout (e.g. a YBR JPEG becomes RGB).
            dataSet.setString(d.photometricInterpretation.rawValue, for: .photometricInterpretation, vr: .CS)
            dataSet.setUInt16(UInt16(d.samplesPerPixel), for: .samplesPerPixel)
            if d.samplesPerPixel > 1 {
                dataSet.setUInt16(UInt16(d.planarConfiguration), for: .planarConfiguration)
            } else {
                dataSet.remove(tag: .planarConfiguration)
            }
            // The decoded pixels keep the losses of a lossy codestream (C.7.6.1.1.5).
            if let sourceSyntax {
                recordLossyCompression(in: &dataSet, sourceSyntax: sourceSyntax,
                                       firstFragment: pixelElement.encapsulatedFragments?.first)
            }
            // Emit uncompressed Explicit VR Little Endian.
            fileMeta = uncompressedFileMeta(from: fileMeta)
            if verbose {
                log("Decoded compressed pixel data (\(sourceSyntax?.displayName ?? "compressed")) → Explicit VR Little Endian")
            }
        } else {
            descriptor = try extractDescriptor(from: dataSet)
            pixelData = pixelElement.valueData
            pixelVR = pixelElement.vr
        }

        if verbose {
            log("Image: \(descriptor.columns)x\(descriptor.rows), \(descriptor.bitsAllocated)-bit, \(descriptor.samplesPerPixel) sample(s)")
        }

        var currentRows = descriptor.rows
        var currentColumns = descriptor.columns
        var cropOffset = (x: 0, y: 0)
        var described: [String] = []

        for operation in operations {
            switch operation {
            case .mask(let x, let y, let width, let height, let fillValue):
                let currentDescriptor = descriptorWith(descriptor, rows: currentRows, columns: currentColumns)
                // A stored sample holds Bits Stored bits (PS3.3 C.7.6.3.1).
                let fill = Swift.min(Swift.max(fillValue, currentDescriptor.storedMin), currentDescriptor.storedMax)
                try applyMask(pixelData: &pixelData, descriptor: currentDescriptor,
                              region: (x: x, y: y, width: width, height: height), fillValue: fill)
                described.append("region x=\(x) y=\(y) \(width)x\(height) set to \(fill)")
                if verbose {
                    log("Applied mask: (\(x),\(y)) \(width)x\(height), fill=\(fill)")
                }

            case .crop(let x, let y, let width, let height):
                let currentDescriptor = descriptorWith(descriptor, rows: currentRows, columns: currentColumns)
                let (croppedData, newWidth, newHeight) = try applyCrop(
                    pixelData: pixelData, descriptor: currentDescriptor,
                    region: (x: x, y: y, width: width, height: height))
                pixelData = croppedData
                currentColumns = newWidth
                currentRows = newHeight
                cropOffset.x += Swift.max(x, 0)
                cropOffset.y += Swift.max(y, 0)
                described.append("cropped to x=\(x) y=\(y) \(width)x\(height)")
                if verbose {
                    log("Cropped to: \(newWidth)x\(newHeight)")
                }

            case .windowLevel(let center, let width):
                let currentDescriptor = descriptorWith(descriptor, rows: currentRows, columns: currentColumns)
                try applyWindowLevel(pixelData: &pixelData, descriptor: currentDescriptor,
                                     center: center, width: width, dataSet: &dataSet)
                // Baking a window remaps stored pixels across the full representable stored
                // range (signed-aware), so the file's old VOI Window Center/Width now
                // describes the pre-bake mapping and would clip the result. Re-point the
                // stored VOI window to that range so the baked contrast is what a viewer shows.
                resetVOIWindowAfterBake(in: &dataSet, descriptor: currentDescriptor)
                described.append("window center \(formatDS(center)) width \(formatDS(width)) baked into the stored values")
                if verbose {
                    log("Applied window/level: center=\(center), width=\(width)")
                }

            case .invert:
                let currentDescriptor = descriptorWith(descriptor, rows: currentRows, columns: currentColumns)
                try applyInvert(pixelData: &pixelData, descriptor: currentDescriptor)
                invertPixelPadding(in: &dataSet, descriptor: currentDescriptor)
                // Inverting stored pixel values without also inverting the file's VOI window
                // pushes every value to the far side of the (unchanged) Window Center, so a
                // viewer that honours the stored window — DICOMStudio's viewer, the image
                // exporter, Horos — renders the image solid white. Re-point the window so the
                // inverted pixels display as a true photographic negative.
                invertVOIWindow(in: &dataSet, descriptor: currentDescriptor)
                described.append("pixel values inverted")
                if verbose {
                    log("Inverted pixel values")
                }
            }
        }

        // Update pixel data element (native VR: as-read for native sources, OW/OB for
        // sources that were just decoded from a compressed transfer syntax).
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: pixelVR, data: pixelData)

        // Update rows/columns if changed by crop
        if currentRows != descriptor.rows {
            dataSet.setUInt16(UInt16(currentRows), for: .rows)
        }
        if currentColumns != descriptor.columns {
            dataSet.setUInt16(UInt16(currentColumns), for: .columns)
        }
        if cropOffset.x != 0 || cropOffset.y != 0 {
            moveGeometryAfterCrop(in: &dataSet, columnOffset: cropOffset.x, rowOffset: cropOffset.y)
        }

        if let derivation {
            markDerived(dataSet: &dataSet, fileMeta: &fileMeta, source: source,
                        steps: described, derivation: derivation)
        }

        let updatedFile = DICOMFile(fileMetaInformation: fileMeta, dataSet: dataSet)
        let outputData = try updatedFile.write()
        let info = PixelEditInfo(columns: currentColumns, rows: currentRows,
                                 bitsAllocated: descriptor.bitsAllocated, samplesPerPixel: descriptor.samplesPerPixel)
        return (outputData, info)
    }

    /// Reads a DICOM file, applies the operations, and writes the result to disk.
    public func processFile(inputPath: String, outputPath: String, operations: [PixelOperation],
                            derivation: PixelEditDerivation? = PixelEditDerivation()) throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: outputPath)

        let fileData = try Data(contentsOf: inputURL)
        let (outputData, _) = try processData(fileData, operations: operations, derivation: derivation)
        try outputData.write(to: outputURL)

        if verbose {
            log(PixelEditConsole.writtenLine(path: outputURL.path))
        }
    }

    // MARK: - Pixel Operations

    func applyMask(pixelData: inout Data, descriptor: PixelEditDescriptor,
                   region: (x: Int, y: Int, width: Int, height: Int), fillValue: Int) throws {
        let endX = min(region.x + region.width, descriptor.columns)
        let endY = min(region.y + region.height, descriptor.rows)

        guard region.x < descriptor.columns, region.y < descriptor.rows else {
            throw PixelEditError.regionOutOfBounds
        }

        let startX = max(region.x, 0)
        let startY = max(region.y, 0)

        // Mask the same region on every frame.
        for frame in 0..<descriptor.numberOfFrames {
            let frameBase = frame * descriptor.frameSampleCount
            for y in startY..<endY {
                for x in startX..<endX {
                    let pixelOffset = y * descriptor.columns + x
                    for s in 0..<descriptor.samplesPerPixel {
                        let sampleIndex = frameBase + pixelOffset * descriptor.samplesPerPixel + s
                        setPixelValue(in: &pixelData, at: sampleIndex, value: fillValue, descriptor: descriptor)
                    }
                }
            }
        }
    }

    func applyCrop(pixelData: Data, descriptor: PixelEditDescriptor,
                   region: (x: Int, y: Int, width: Int, height: Int)) throws -> (Data, Int, Int) {
        let endX = min(region.x + region.width, descriptor.columns)
        let endY = min(region.y + region.height, descriptor.rows)

        guard region.x < descriptor.columns, region.y < descriptor.rows else {
            throw PixelEditError.regionOutOfBounds
        }

        let startX = max(region.x, 0)
        let startY = max(region.y, 0)
        let newWidth = endX - startX
        let newHeight = endY - startY

        let frameByteCount = descriptor.frameByteCount
        var croppedData = Data(capacity: newWidth * newHeight * descriptor.bytesPerPixel * descriptor.numberOfFrames)

        // Crop the same region out of every frame and concatenate.
        for frame in 0..<descriptor.numberOfFrames {
            let frameBase = frame * frameByteCount
            for y in startY..<endY {
                let srcRowStart = frameBase + (y * descriptor.columns + startX) * descriptor.bytesPerPixel
                let srcRowEnd = srcRowStart + newWidth * descriptor.bytesPerPixel

                guard srcRowEnd <= pixelData.count else {
                    throw PixelEditError.pixelDataTruncated
                }

                let lower = pixelData.index(pixelData.startIndex, offsetBy: srcRowStart)
                let upper = pixelData.index(pixelData.startIndex, offsetBy: srcRowEnd)
                croppedData.append(pixelData[lower..<upper])
            }
        }

        return (croppedData, newWidth, newHeight)
    }

    /// Bakes a VOI window into the stored values. `center` and `width` are in the output
    /// units of the Modality LUT (PS3.3 2026a C.11.2.1.2: "the input to the VOI LUT is the
    /// output of the Modality LUT"), so every stored value is first taken through Rescale
    /// Slope/Intercept (per frame for functional groups) or the Modality LUT Sequence.
    /// Pixel Padding Value / Range Limit in `dataSet` follow the remapped values, or are
    /// removed when padding would become indistinguishable from image pixels (C.7.5.1.1.2).
    func applyWindowLevel(pixelData: inout Data, descriptor: PixelEditDescriptor,
                          center: Double, width: Double, dataSet: inout DataSet) throws {
        // "Window Width (0028,1051) shall always be greater than or equal to 1".
        guard width >= 1 else {
            throw PixelEditError.invalidWindowWidth
        }

        let totalSamples = descriptor.frameSampleCount * descriptor.numberOfFrames
        // Bake into the FULL representable stored range: [0, maxValue] for unsigned,
        // [−2^(b−1), 2^(b−1)−1] for signed. Scaling to the unsigned max for signed data
        // would exceed the signed storage clamp, leaving the baked image in only half the
        // range → it renders ~2× too dark. For unsigned this is identical to the previous
        // [0, maxValue] mapping.
        let outMin = Double(descriptor.storedMin)
        let outMax = Double(descriptor.storedMax)
        let span = outMax - outMin

        // DICOM window/level formula (PS3.3 C.11.2.1.2.1), normalised to [0, 1], applied
        // to the Modality LUT output `x`.
        func windowed(_ x: Double) -> Int {
            let normalized: Double
            if width <= 1.0 {
                normalized = x <= center - 0.5 ? 0.0 : 1.0
            } else if x <= center - 0.5 - (width - 1.0) / 2.0 {
                normalized = 0.0
            } else if x > center - 0.5 + (width - 1.0) / 2.0 {
                normalized = 1.0
            } else {
                normalized = (x - (center - 0.5)) / (width - 1.0) + 0.5
            }
            return Int(Swift.max(outMin, Swift.min(outMax, outMin + normalized * span)))
        }

        let modality = modalityTransforms(for: dataSet, descriptor: descriptor)
        let padding = descriptor.samplesPerPixel == 1 ? pixelPaddingRange(in: dataSet, descriptor: descriptor) : nil
        // Output values taken by image (non-padding) samples, to detect a collision with
        // the remapped padding values.
        var nativeOutputs = padding == nil ? [] : [Bool](repeating: false, count: descriptor.storedMax - descriptor.storedMin + 1)

        for i in 0..<totalSamples {
            let rawValue = getPixelValue(from: pixelData, at: i, descriptor: descriptor)
            let frame = Swift.min(i / Swift.max(descriptor.frameSampleCount, 1), modality.count - 1)
            let output = windowed(modality[frame](rawValue))
            setPixelValue(in: &pixelData, at: i, value: output, descriptor: descriptor)
            if let padding, !padding.contains(rawValue) {
                nativeOutputs[output - descriptor.storedMin] = true
            }
        }

        guard let padding else { return }
        // Where the padding values land: Rescale is linear per frame, so its end points
        // bound the image of the range; a Modality LUT is evaluated value by value.
        var mapped: [Int] = []
        if dataSet.modalityLUTData() != nil {
            mapped = padding.map { windowed(modality[0]($0)) }
        } else {
            for transform in modality {
                mapped.append(windowed(transform(padding.lowerBound)))
                mapped.append(windowed(transform(padding.upperBound)))
            }
        }
        guard let low = mapped.min(), let high = mapped.max() else { return }
        let collides = (low...high).contains { nativeOutputs[$0 - descriptor.storedMin] }
        if collides {
            // "If modifying equipment changes the Pixel Padding Values in the image to
            // values present in the native image, the Attribute Pixel Padding Value
            // (0028,0120) and Pixel Padding Range Limit (0028,0121) shall be removed."
            dataSet.remove(tag: .pixelPaddingValue)
            dataSet.remove(tag: .pixelPaddingRangeLimit)
            if verbose {
                log("Removed Pixel Padding Value: the baked window maps padding onto image values")
            }
        } else {
            setPixelPadding(low: low, high: high, in: &dataSet, descriptor: descriptor)
        }
    }

    func applyInvert(pixelData: inout Data, descriptor: PixelEditDescriptor) throws {
        let totalSamples = descriptor.frameSampleCount * descriptor.numberOfFrames
        let pivot = invertPivot(for: descriptor)

        for i in 0..<totalSamples {
            let value = getPixelValue(from: pixelData, at: i, descriptor: descriptor)
            let inverted = pivot - value
            setPixelValue(in: &pixelData, at: i, value: inverted, descriptor: descriptor)
        }
    }

    // MARK: - Helpers

    private func extractDescriptor(from dataSet: DataSet) throws -> PixelEditDescriptor {
        guard let rows = dataSet.uint16(for: .rows) else {
            throw PixelEditError.missingTag("Rows")
        }
        guard let columns = dataSet.uint16(for: .columns) else {
            throw PixelEditError.missingTag("Columns")
        }

        let bitsAllocated = dataSet.uint16(for: .bitsAllocated) ?? 16
        let bitsStored = dataSet.uint16(for: .bitsStored) ?? bitsAllocated
        let highBit = dataSet.uint16(for: .highBit) ?? (bitsStored - 1)
        let pixelRep = dataSet.uint16(for: .pixelRepresentation) ?? 0
        let samplesPerPixel = dataSet.uint16(for: .samplesPerPixel) ?? 1
        let numberOfFrames = max(1, dataSet.numberOfFrames ?? 1)

        return PixelEditDescriptor(
            rows: Int(rows),
            columns: Int(columns),
            bitsAllocated: Int(bitsAllocated),
            bitsStored: Int(bitsStored),
            highBit: Int(highBit),
            pixelRepresentation: Int(pixelRep),
            samplesPerPixel: Int(samplesPerPixel),
            numberOfFrames: numberOfFrames
        )
    }

    /// Returns a copy of the File Meta Information re-pointed at Explicit VR Little
    /// Endian, with the group length (0002,0000) recomputed so the FMI stays
    /// self-consistent after the transfer-syntax change.
    private func uncompressedFileMeta(from meta: DataSet) -> DataSet {
        var fmi = meta
        fmi.setString(TransferSyntax.explicitVRLittleEndian.uid, for: .transferSyntaxUID, vr: .UI)
        // Recompute group length over everything that follows it.
        fmi.remove(tag: .fileMetaInformationGroupLength)
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        let bytes = fmi.write(using: writer)
        fmi[.fileMetaInformationGroupLength] = DataElement.uint32(
            tag: .fileMetaInformationGroupLength, value: UInt32(bytes.count))
        return fmi
    }

    private func descriptorWith(_ base: PixelEditDescriptor, rows: Int, columns: Int) -> PixelEditDescriptor {
        PixelEditDescriptor(
            rows: rows,
            columns: columns,
            bitsAllocated: base.bitsAllocated,
            bitsStored: base.bitsStored,
            highBit: base.highBit,
            pixelRepresentation: base.pixelRepresentation,
            samplesPerPixel: base.samplesPerPixel,
            numberOfFrames: base.numberOfFrames
        )
    }

    // MARK: - Modality LUT, padding, lossy flag

    static func photometricInterpretation(of dataSet: DataSet) -> String {
        (dataSet.string(for: .photometricInterpretation) ?? "")
            .trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// Stored value → Modality LUT output, one transform per frame (PS3.3 C.11.1): the
    /// Modality LUT Sequence when present, else Rescale Slope/Intercept (top level or the
    /// frame's Pixel Value Transformation Sequence). Identity for colour samples, which
    /// have no Modality LUT.
    private func modalityTransforms(for dataSet: DataSet, descriptor: PixelEditDescriptor) -> [(Int) -> Double] {
        guard descriptor.samplesPerPixel == 1 else { return [{ Double($0) }] }
        if let lut = dataSet.modalityLUTData() {
            return [{ lut.lookup($0) }]
        }
        return (0..<Swift.max(descriptor.numberOfFrames, 1)).map { frame in
            let slope = dataSet.rescaleSlope(frameIndex: frame)
            let intercept = dataSet.rescaleIntercept(frameIndex: frame)
            return { slope * Double($0) + intercept }
        }
    }

    /// A 16-bit US or SS value (Pixel Padding Value / Range Limit) read per Pixel
    /// Representation.
    private func paddingAttribute(_ tag: Tag, in dataSet: DataSet, descriptor: PixelEditDescriptor) -> Int? {
        guard let bytes = dataSet[tag]?.valueData, bytes.count >= 2 else { return nil }
        let raw = UInt16(bytes[bytes.startIndex]) | UInt16(bytes[bytes.startIndex + 1]) << 8
        return descriptor.isSigned ? Int(Int16(bitPattern: raw)) : Int(raw)
    }

    /// The stored values that are padding: Pixel Padding Value alone, or the inclusive
    /// range up to Pixel Padding Range Limit (PS3.3 2026a C.7.5.1.1.2).
    private func pixelPaddingRange(in dataSet: DataSet, descriptor: PixelEditDescriptor) -> ClosedRange<Int>? {
        guard let value = paddingAttribute(.pixelPaddingValue, in: dataSet, descriptor: descriptor) else { return nil }
        let limit = paddingAttribute(.pixelPaddingRangeLimit, in: dataSet, descriptor: descriptor) ?? value
        return Swift.min(value, limit)...Swift.max(value, limit)
    }

    /// Writes the padding range back: Pixel Padding Value is the end nearest the minimum
    /// for MONOCHROME2 / PALETTE COLOR and nearest the maximum for MONOCHROME1, and the
    /// Range Limit (only when the source had one) the other end (C.7.5.1.1.2).
    private func setPixelPadding(low: Int, high: Int, in dataSet: inout DataSet, descriptor: PixelEditDescriptor) {
        let hadLimit = dataSet[.pixelPaddingRangeLimit] != nil
        let monochrome1 = Self.photometricInterpretation(of: dataSet) == "MONOCHROME1"
        let value = monochrome1 ? high : low
        let limit = monochrome1 ? low : high
        func element(_ tag: Tag, _ v: Int) -> DataElement {
            descriptor.isSigned ? DataElement.int16(tag: tag, value: Int16(clamping: v))
                                : DataElement.uint16(tag: tag, value: UInt16(clamping: v))
        }
        dataSet[.pixelPaddingValue] = element(.pixelPaddingValue, value)
        if hadLimit {
            dataSet[.pixelPaddingRangeLimit] = element(.pixelPaddingRangeLimit, limit)
        }
    }

    /// Inversion maps every stored value v to pivot − v, so the padding range becomes
    /// [pivot − high, pivot − low]; "when modifying equipment changes the Pixel Padding
    /// Value in the image, it shall change the Values of Pixel Padding Value (0028,0120)
    /// and Pixel Padding Range Limit (0028,0121)" (C.7.5.1.1.2). Inversion is one-to-one,
    /// so padding stays distinct from image values.
    private func invertPixelPadding(in dataSet: inout DataSet, descriptor: PixelEditDescriptor) {
        guard descriptor.samplesPerPixel == 1,
              let range = pixelPaddingRange(in: dataSet, descriptor: descriptor) else { return }
        let pivot = invertPivot(for: descriptor)
        setPixelPadding(low: pivot - range.upperBound, high: pivot - range.lowerBound,
                        in: &dataSet, descriptor: descriptor)
    }

    /// Sets Lossy Image Compression (0028,2110) to "01" when the decoded source was
    /// lossy compressed ("Once this Attribute has been set to a Value of "01" it shall
    /// not be reset", "if the image is decompressed and transferred in uncompressed
    /// format, this Attribute Value remains "01"", PS3.3 2026a C.7.6.1.1.5), and Lossy
    /// Image Compression Method (0028,2114) when the source did not record one. For
    /// JPEG 2000 syntaxes that may carry either, the codestream's wavelet decides; a
    /// JPEG XL .112 codestream is not inspected and is left as it was.
    private func recordLossyCompression(in dataSet: inout DataSet, sourceSyntax: TransferSyntax, firstFragment: Data?) {
        let lossy: Bool
        switch sourceSyntax.losslessCapability {
        case .lossyOnly:
            lossy = true
        case .losslessOnly:
            lossy = false
        case .both:
            if sourceSyntax.isJPEG2000, let fragment = firstFragment {
                lossy = J2KCodestreamInspector.usesIrreversibleWavelet(in: fragment)
            } else {
                lossy = false
            }
        }
        guard lossy else { return }
        dataSet.setString("01", for: .lossyImageCompression, vr: .CS)
        if dataSet[.lossyImageCompressionMethod] == nil, let method = sourceSyntax.lossyImageCompressionMethod {
            dataSet.setString(method, for: .lossyImageCompressionMethod, vr: .CS)
        }
    }

    // MARK: - Geometry after a crop

    /// After a crop whose first kept pixel was at column `columnOffset`, row `rowOffset`
    /// of the source: Image Position (Patient) moves to that pixel, P = S + X·Δi·i + Y·Δj·j
    /// with Δi = Pixel Spacing Value 2 and Δj = Value 1 (PS3.3 2026a C.7.6.2.1.1, Equation
    /// C.7.6.2.1-1) — at the top level and in the Plane Position Sequence of the Shared /
    /// Per-Frame Functional Groups — and each Overlay Origin (60xx,0050), given "with
    /// respect to pixels in the image" as row\column (C.9.2), moves the other way. Overlay
    /// Rows/Columns are the overlay plane's own size and do not change.
    private func moveGeometryAfterCrop(in dataSet: inout DataSet, columnOffset: Int, rowOffset: Int) {
        func moved(_ position: [Double], _ orientation: [Double], _ spacing: [Double]) -> [Double]? {
            guard position.count == 3, orientation.count == 6, spacing.count == 2 else { return nil }
            return (0..<3).map {
                position[$0] + orientation[$0] * spacing[1] * Double(columnOffset)
                    + orientation[$0 + 3] * spacing[0] * Double(rowOffset)
            }
        }
        func values(_ tag: Tag, _ elements: [Tag: DataElement]) -> [Double]? {
            elements[tag]?.decimalStringValues?.map(\.value)
        }
        func nested(_ sequence: Tag, _ elements: [Tag: DataElement]?) -> [Tag: DataElement]? {
            elements?[sequence]?.sequenceItems?.first?.elements
        }

        // Top level (Image Plane Module).
        if let position = dataSet.decimalStrings(for: .imagePositionPatient)?.map(\.value),
           let orientation = dataSet.decimalStrings(for: .imageOrientationPatient)?.map(\.value),
           let spacing = dataSet.decimalStrings(for: .pixelSpacing)?.map(\.value),
           let newPosition = moved(position, orientation, spacing) {
            dataSet.setStrings(newPosition.map(formatDS), for: .imagePositionPatient, vr: .DS)
        }

        // Functional groups (Plane Position / Plane Orientation / Pixel Measures macros).
        let shared = dataSet.sequence(for: .sharedFunctionalGroupsSequence)?.first?.elements
        let perFrame = dataSet.sequence(for: .perFrameFunctionalGroupsSequence) ?? []
        func geometry(_ frame: [Tag: DataElement]?) -> (orientation: [Double], spacing: [Double])? {
            guard let orientation = (nested(.planeOrientationSequence, frame) ?? nested(.planeOrientationSequence, shared))
                    .flatMap({ values(.imageOrientationPatient, $0) }),
                  let spacing = (nested(.pixelMeasuresSequence, frame) ?? nested(.pixelMeasuresSequence, shared))
                    .flatMap({ values(.pixelSpacing, $0) }) else { return nil }
            return (orientation, spacing)
        }
        func withPosition(_ item: [Tag: DataElement], _ position: [Double]) -> SequenceItem {
            var plane = item[.planePositionSequence]?.sequenceItems?.first?.elements ?? [:]
            plane[.imagePositionPatient] = DataElement.strings(
                tag: .imagePositionPatient, vr: .DS, values: position.map(formatDS))
            var holder = DataSet()
            holder.setSequence([SequenceItem(elements: plane)], for: .planePositionSequence)
            var updated = item
            updated[.planePositionSequence] = holder[.planePositionSequence]
            return SequenceItem(elements: updated)
        }

        var newPerFrame = perFrame
        var perFrameChanged = false
        for (index, item) in perFrame.enumerated() {
            guard let plane = nested(.planePositionSequence, item.elements),
                  let position = values(.imagePositionPatient, plane),
                  let g = geometry(item.elements),
                  let newPosition = moved(position, g.orientation, g.spacing) else { continue }
            newPerFrame[index] = withPosition(item.elements, newPosition)
            perFrameChanged = true
        }
        if perFrameChanged {
            dataSet.setSequence(newPerFrame, for: .perFrameFunctionalGroupsSequence)
        }
        if let shared,
           let plane = nested(.planePositionSequence, shared),
           let position = values(.imagePositionPatient, plane),
           let g = geometry(perFrame.first?.elements),
           let newPosition = moved(position, g.orientation, g.spacing) {
            dataSet.setSequence([withPosition(shared, newPosition)], for: .sharedFunctionalGroupsSequence)
        }

        // Overlay planes (repeating group 60xx, even groups 6000-601E).
        for group in stride(from: UInt16(0x6000), through: UInt16(0x601E), by: 2) {
            let tag = Tag(group: group, element: 0x0050)
            guard let bytes = dataSet[tag]?.valueData, bytes.count >= 4 else { continue }
            let b = bytes.startIndex
            let row = Int(Int16(bitPattern: UInt16(bytes[b]) | UInt16(bytes[b + 1]) << 8))
            let column = Int(Int16(bitPattern: UInt16(bytes[b + 2]) | UInt16(bytes[b + 3]) << 8))
            var value = Data()
            for v in [row - rowOffset, column - columnOffset] {
                let u = UInt16(bitPattern: Int16(clamping: v))
                value.append(UInt8(u & 0xFF)); value.append(UInt8(u >> 8))
            }
            dataSet[tag] = DataElement(tag: tag, vr: .SS, length: UInt32(value.count), valueData: value)
        }
    }

    // MARK: - Derived Image

    /// PS3.16 2026a CID 7202 "Source Image Purpose of Reference": DCM 121322. CID 7203
    /// "Image Derivation" has no code for a region fill, crop, window bake or inversion
    /// (DCM 113047 "Pixel by pixel mask" is masking one image by another), so no
    /// Derivation Code Sequence (0008,9215, Type 3) is written.
    static let sourceImagePurpose = (value: "121322", scheme: "DCM",
                                     meaning: "Source image for image processing operation")

    /// ST holds at most 1024 characters (PS3.5 2026a Table 6.2-1).
    static let shortTextMaximumLength = 1024

    /// Marks the edited image as a new Derived Image of `source` (PS3.3 2026a
    /// C.7.6.1.1.2: Value 1 DERIVED; "if the pixel data … are different, then the SOP
    /// Instance UID shall be different"; General Reference Module, Table C.12-10).
    private func markDerived(dataSet: inout DataSet, fileMeta: inout DataSet, source: DataSet,
                             steps: [String], derivation: PixelEditDerivation) {
        let newUID = derivation.sopInstanceUID ?? UIDGenerator.generateUID().value
        dataSet.setString(newUID, for: .sopInstanceUID, vr: .UI)
        fileMeta.setString(newUID, for: .mediaStorageSOPInstanceUID, vr: .UI)
        // (0002,0012)/(0002,0013) identify the implementation that wrote the file
        // (PS3.10 Table 7.1-1), not the one that wrote the source.
        fileMeta.setString(DICOMFile.implementationClassUID, for: .implementationClassUID, vr: .UI)
        fileMeta.setString(DICOMFile.implementationVersionName, for: .implementationVersionName, vr: .SH)
        fileMeta.remove(tag: .fileMetaInformationGroupLength)   // recomputed by DICOMFile.write()

        var imageType = dataSet.strings(for: .imageType) ?? []
        if imageType.isEmpty {
            imageType = ["DERIVED", "SECONDARY"]
        } else {
            imageType[0] = "DERIVED"
        }
        dataSet.setStrings(imageType, for: .imageType, vr: .CS)

        var text = derivation.descriptionPrefix.isEmpty
            ? steps.joined(separator: "; ")
            : derivation.descriptionPrefix + ": " + steps.joined(separator: "; ")
        if let previous = dataSet.string(for: .derivationDescription)?
            .trimmingCharacters(in: .whitespaces), !previous.isEmpty {
            text = previous + "; " + text
        }
        dataSet.setString(String(text.prefix(Self.shortTextMaximumLength)), for: .derivationDescription, vr: .ST)

        if let sourceClass = source.string(for: .sopClassUID),
           let sourceInstance = source.string(for: .sopInstanceUID) {
            var purpose = DataSet()
            purpose.setSequence([SequenceItem(elements: [
                DataElement.string(tag: .codeValue, vr: .SH, value: Self.sourceImagePurpose.value),
                DataElement.string(tag: .codingSchemeDesignator, vr: .SH, value: Self.sourceImagePurpose.scheme),
                DataElement.string(tag: .codeMeaning, vr: .LO, value: Self.sourceImagePurpose.meaning),
            ])], for: .purposeOfReferenceCodeSequence)
            var elements = [
                DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: sourceClass),
                DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: sourceInstance),
            ]
            if let code = purpose[.purposeOfReferenceCodeSequence] { elements.append(code) }
            let existing = dataSet.sequence(for: .sourceImageSequence) ?? []
            dataSet.setSequence(existing + [SequenceItem(elements: elements)], for: .sourceImageSequence)
        }

        // The value range of the source no longer describes the edited pixels.
        for tag in [Tag.smallestImagePixelValue, .largestImagePixelValue,
                    .smallestPixelValueInSeries, .largestPixelValueInSeries] {
            dataSet.remove(tag: tag)
        }
    }

    // MARK: - VOI window (0028,1050/0028,1051) maintenance

    /// The stored value `p` such that `p − stored` reverses the stored-value range onto
    /// itself — the pivot both the pixel inversion and the VOI-window inversion use.
    ///
    /// - Unsigned: the highest stored value, `2^bitsStored − 1`.
    /// - Signed (two's complement): `min + max = −1`, independent of `bitsStored`
    ///   (e.g. 16-bit signed spans −32768…32767, whose sum is −1). Using the unsigned
    ///   `maxValue` here would push every signed sample past the positive clamp, i.e.
    ///   render the whole frame white — the very bug this fixes.
    private func invertPivot(for descriptor: PixelEditDescriptor) -> Int {
        descriptor.isSigned ? -1 : descriptor.maxValue
    }

    /// Re-points the VOI Window Center so an inverted image displays as a true negative.
    ///
    /// Viewers apply the VOI window in *stored* space after the Modality LUT, so a stored
    /// center `Cs` becomes `pivot − Cs` under the inversion `s' = pivot − s`. Window Center
    /// is persisted in *output* units (Rescale Slope·stored + Intercept); the equivalent
    /// output-space transform is `C' = slope·pivot + 2·intercept − C`. Window Width is a
    /// span and is unchanged. No stored window ⇒ nothing to do (viewers auto-window from the
    /// pixel range, which already tracks the inverted data). Reference: PS3.3 C.11.2.
    private func invertVOIWindow(in dataSet: inout DataSet, descriptor: PixelEditDescriptor) {
        guard let centers = dataSet.decimalStrings(for: .windowCenter), !centers.isEmpty else { return }
        let slope = dataSet.rescaleSlope()
        let intercept = dataSet.rescaleIntercept()
        let k = slope * Double(invertPivot(for: descriptor)) + 2.0 * intercept
        let newCenters = centers.map { formatDS(k - $0.value) }
        dataSet.setStrings(newCenters, for: .windowCenter, vr: .DS)
        if verbose {
            log("Inverted VOI window center(s) → \(newCenters.joined(separator: "\\")) so the negative displays correctly")
        }
    }

    /// Replaces the VOI window after a window/level bake, which has already flattened the
    /// chosen window across the full representable stored range (`[0, maxValue]` unsigned,
    /// `[−2^(b−1), 2^(b−1)−1]` signed). A viewer honouring the pre-bake window would re-clip
    /// the result, so set the stored window to that same full range — PS3.3 C.11.2.1.2.1's
    /// window over x1…x2, stored center `(storedMin+storedMax+1)/2`, width
    /// `storedMax−storedMin+1` (D66), rescaled to output units — exactly the baked
    /// contrast. Any per-window explanation no longer applies and is dropped.
    private func resetVOIWindowAfterBake(in dataSet: inout DataSet, descriptor: PixelEditDescriptor) {
        let slope = dataSet.rescaleSlope()
        let intercept = dataSet.rescaleIntercept()
        let storedCenter = Double(descriptor.storedMin + descriptor.storedMax + 1) / 2.0
        let storedWidth = Double(descriptor.storedMax - descriptor.storedMin + 1)
        let center = slope * storedCenter + intercept
        let width = Swift.max(1.0, abs(slope) * storedWidth)
        dataSet.setString(formatDS(center), for: .windowCenter, vr: .DS)
        dataSet.setString(formatDS(width), for: .windowWidth, vr: .DS)
        dataSet.remove(tag: .windowCenterWidthExplanation)
    }

    /// Formats a value as a DICOM Decimal String (DS, ≤ 16 bytes): integral values print
    /// without a fractional part, others with compact significant-digit precision. Non-finite
    /// values (only reachable from pathological rescale metadata) degrade to "0" rather than
    /// emit a non-conformant "nan"/"inf" token.
    private func formatDS(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value.rounded()))
        }
        var s = String(format: "%.10g", value)
        if s.count > 16 { s = String(format: "%.8g", value) }
        if s.count > 16 { s = String(s.prefix(16)) }
        return s
    }

    private func getPixelValue(from data: Data, at sampleIndex: Int, descriptor: PixelEditDescriptor) -> Int {
        let byteOffset = sampleIndex * descriptor.bytesPerSample

        if descriptor.bytesPerSample == 1 {
            guard byteOffset < data.count else { return 0 }
            let raw = data[data.startIndex + byteOffset]
            return descriptor.isSigned ? Int(Int8(bitPattern: raw)) : Int(raw)
        } else {
            let idx = data.startIndex + byteOffset
            guard idx + 1 < data.endIndex else { return 0 }
            let lo = UInt16(data[idx])
            let hi = UInt16(data[idx + 1])
            let raw = lo | (hi << 8)
            return descriptor.isSigned ? Int(Int16(bitPattern: raw)) : Int(raw)
        }
    }

    /// Writes one stored sample, clamped to the Bits Stored / Pixel Representation range
    /// (PS3.3 2026a C.7.6.3.1), not merely to the Bits Allocated container, so no value
    /// lands above High Bit.
    private func setPixelValue(in data: inout Data, at sampleIndex: Int, value requested: Int, descriptor: PixelEditDescriptor) {
        let value = Swift.min(Swift.max(requested, descriptor.storedMin), descriptor.storedMax)
        let byteOffset = sampleIndex * descriptor.bytesPerSample

        if descriptor.bytesPerSample == 1 {
            guard byteOffset < data.count else { return }
            if descriptor.isSigned {
                data[data.startIndex + byteOffset] = UInt8(bitPattern: Int8(clamping: value))
            } else {
                data[data.startIndex + byteOffset] = UInt8(clamping: value)
            }
        } else {
            let idx = data.startIndex + byteOffset
            guard idx + 1 < data.endIndex else { return }
            if descriptor.isSigned {
                let clamped = UInt16(bitPattern: Int16(clamping: value))
                data[idx] = UInt8(clamped & 0xFF)
                data[idx + 1] = UInt8(clamped >> 8)
            } else {
                let clamped = UInt16(clamping: value)
                data[idx] = UInt8(clamped & 0xFF)
                data[idx + 1] = UInt8(clamped >> 8)
            }
        }
    }
}

// MARK: - Errors

public enum PixelEditError: Error, LocalizedError {
    case invalidRegion(String)
    case noPixelData
    case regionOutOfBounds
    case pixelDataTruncated
    case missingTag(String)
    case invalidWindowWidth
    /// Window/level or invert asked of a PALETTE COLOR image, whose stored values are
    /// palette indices (PS3.3 2026a C.7.6.3.1.5).
    case notApplicableToPaletteColor(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRegion(let str):
            return "Invalid region format '\(str)'. Expected x,y,width,height with positive width/height"
        case .noPixelData:
            return "DICOM file contains no pixel data"
        case .regionOutOfBounds:
            return "Region is entirely outside the image bounds"
        case .pixelDataTruncated:
            return "Pixel data is shorter than expected for the given image dimensions"
        case .missingTag(let name):
            return "Required DICOM tag missing: \(name)"
        case .invalidWindowWidth:
            return "Window Width (0028,1051) shall be greater than or equal to 1 (PS3.3 C.11.2.1.2)"
        case .notApplicableToPaletteColor(let operation):
            return "\(operation) does not apply to PALETTE COLOR: its stored values are palette indices (PS3.3 C.7.6.3.1.5)"
        }
    }
}

// MARK: - Shared console output (dicom-pixedit CLI ⇄ Workshop executor)

/// Builds the console lines `dicom-pixedit` prints around the engine's own
/// verbose log (which is shared already via the `PixelEditor` log closure).
/// The CLI text is canonical; the Workshop executor renders identical strings.
/// All lines are verbose-gated on both surfaces — a non-verbose run is silent.
public enum PixelEditConsole {
    /// Verbose run header (input path, output path, operation count).
    public static func headerLines(input: String, output: String, operationCount: Int) -> [String] {
        ["Input: \(input)", "Output: \(output)", "Operations: \(operationCount)"]
    }

    /// Verbose confirmation after the output file is written.
    public static func writtenLine(path: String) -> String {
        "Written: \(path)"
    }

    /// Verbose end-of-run line.
    public static func doneLine() -> String {
        "Done."
    }
}
