// NEMA-verified: 2026a, checked 2026-09-29 — PS3.5 2026a A.4 Basic and Extended Offset Table frame location; (7FE0,0001) is OV (D19); Extended Offset Table Lengths are not read (recorded)
import Foundation
import DICOMCore

/// Selected-frame pixel access (RESEARCH_ADOPTION_PLAN.md M2)
///
/// `pixelData()` decodes every frame of a multi-frame object into one buffer;
/// this extension decodes exactly one frame, touching only that frame's bytes
/// (native path) or fragments (encapsulated path, via a validated
/// frame/fragment index). For the M1 baseline instance this is the difference
/// between decoding 40 frames and decoding 1.
extension DICOMFile {

    /// Number of frames in the Pixel Data, from the image pixel attributes
    /// (nil when the file has no pixel-data descriptor).
    public var pixelFrameCount: Int? {
        dataSet.pixelDataDescriptor()?.numberOfFrames
    }

    /// Decodes exactly one frame of pixel data
    ///
    /// - Native (uncompressed) syntaxes: slices the frame's byte range out of
    ///   the Pixel Data value (normalising retired big-endian 16-bit samples),
    ///   without materialising the other frames.
    /// - Encapsulated syntaxes: locates the frame's fragments through a
    ///   validated index (Extended Offset Table → Basic Offset Table →
    ///   one-fragment-per-frame → single-frame) and decodes only those.
    ///   Inconsistent offset tables fail closed rather than risk decoding the
    ///   wrong frame.
    ///
    /// The returned `PixelData` describes a single-frame image
    /// (`descriptor.numberOfFrames == 1`).
    ///
    /// - Parameter frame: Zero-based frame index.
    /// - Throws: `PixelDataError` when the frame cannot be located or decoded.
    public func pixelData(frame: Int) throws -> PixelData {
        let descriptor = try dataSet.tryPixelDataDescriptor()
        guard frame >= 0, frame < descriptor.numberOfFrames else {
            throw PixelDataError.frameExtractionFailed(frameIndex: frame)
        }

        guard let element = dataSet[.pixelData] else {
            throw PixelDataError.missingPixelData
        }

        // --- Native (uncompressed) path ---------------------------------
        if !element.valueData.isEmpty {
            return try nativeFrame(frame, element: element, descriptor: descriptor)
        }

        // --- Encapsulated path -------------------------------------------
        guard let encapsulated = dataSet.encapsulatedPixelData() else {
            throw PixelDataError.missingPixelData
        }
        guard let tsUID = transferSyntaxUID else {
            throw PixelDataError.missingTransferSyntax
        }
        guard let codec = CodecRegistry.shared.codec(for: tsUID) else {
            throw PixelDataError.unsupportedTransferSyntax(tsUID)
        }

        guard let index = encapsulated.makeFrameIndex(extendedOffsets: extendedOffsetTableValues()),
              let frameBytes = encapsulated.frameData(at: frame, using: index) else {
            throw PixelDataError.frameExtractionFailed(frameIndex: frame)
        }

        let decoded: Data
        do {
            decoded = try codec.decodeFrame(frameBytes, descriptor: descriptor, frameIndex: frame)
        } catch {
            throw PixelDataError.decodingFailed(frameIndex: frame, reason: error.localizedDescription)
        }

        let corrected = Self.correctedDescriptorForDecodedBytes(descriptor, transferSyntaxUID: tsUID)
        return PixelData(data: decoded, descriptor: Self.singleFrame(corrected))
    }

    /// Decodes one frame directly into page-aligned, GPU-ready storage (plan M3)
    ///
    /// Same semantics as `pixelData(frame:)`, but the decoded samples land in an
    /// `AlignedPixelBuffer` that Metal can wrap with `makeBuffer(bytesNoCopy:)` —
    /// removing the separate `pageAligned()` re-copy the render path otherwise
    /// pays, and (for codecs with a caller-owned override, e.g. RLE) the codec's
    /// own intermediate output buffer as well.
    public func alignedPixelData(frame: Int) throws -> PixelData {
        let descriptor = try dataSet.tryPixelDataDescriptor()
        guard frame >= 0, frame < descriptor.numberOfFrames else {
            throw PixelDataError.frameExtractionFailed(frameIndex: frame)
        }
        guard let element = dataSet[.pixelData] else {
            throw PixelDataError.missingPixelData
        }

        let bytesPerFrame = descriptor.rows * descriptor.columns
            * descriptor.samplesPerPixel * (descriptor.bitsAllocated / 8)
        guard descriptor.bitsAllocated >= 8, bytesPerFrame > 0,
              let buffer = AlignedPixelBuffer(byteCount: bytesPerFrame) else {
            // Sub-byte layouts or allocation failure: unaligned path still works.
            return try pixelData(frame: frame)
        }

        // Native: copy the frame's byte range straight into aligned storage.
        if !element.valueData.isEmpty {
            let start = element.valueData.startIndex + frame * bytesPerFrame
            let end = start + bytesPerFrame
            guard end <= element.valueData.endIndex else {
                throw PixelDataError.frameExtractionFailed(frameIndex: frame)
            }
            element.valueData[start..<end].withUnsafeBytes { source in
                if let src = source.baseAddress {
                    buffer.baseAddress.copyMemory(from: src, byteCount: bytesPerFrame)
                }
            }
            if element.byteOrder == .bigEndian && descriptor.bitsAllocated == 16 {
                let words = buffer.baseAddress.assumingMemoryBound(to: UInt16.self)
                for i in 0..<(bytesPerFrame / 2) { words[i] = words[i].byteSwapped }
            }
            return PixelData(alignedStorage: buffer, descriptor: Self.singleFrame(descriptor))
        }

        // Encapsulated: codec writes into the aligned buffer (directly for
        // caller-owned codecs; via one bounded copy otherwise).
        guard let encapsulated = dataSet.encapsulatedPixelData() else {
            throw PixelDataError.missingPixelData
        }
        guard let tsUID = transferSyntaxUID else {
            throw PixelDataError.missingTransferSyntax
        }
        guard let codec = CodecRegistry.shared.codec(for: tsUID) else {
            throw PixelDataError.unsupportedTransferSyntax(tsUID)
        }
        guard let index = encapsulated.makeFrameIndex(extendedOffsets: extendedOffsetTableValues()),
              let frameBytes = encapsulated.frameData(at: frame, using: index) else {
            throw PixelDataError.frameExtractionFailed(frameIndex: frame)
        }

        let written: Int
        do {
            written = try codec.decodeFrame(
                frameBytes, descriptor: descriptor, frameIndex: frame,
                into: UnsafeMutableRawBufferPointer(start: buffer.baseAddress,
                                                    count: buffer.byteCount))
        } catch {
            throw PixelDataError.decodingFailed(frameIndex: frame, reason: error.localizedDescription)
        }
        guard written == bytesPerFrame else {
            // Codec produced an unexpected size (e.g. photometric conversion
            // changed the layout) — fall back to the Data-returning path rather
            // than hand out a partially filled buffer.
            return try pixelData(frame: frame)
        }

        let corrected = Self.correctedDescriptorForDecodedBytes(descriptor, transferSyntaxUID: tsUID)
        return PixelData(alignedStorage: buffer, descriptor: Self.singleFrame(corrected))
    }

    // MARK: - Helpers

    private func nativeFrame(_ frame: Int, element: DataElement,
                             descriptor: PixelDataDescriptor) throws -> PixelData {
        // Packed sub-byte samples (e.g. 1-bit segmentation masks) don't have
        // byte-aligned frame boundaries in general; take the safe whole-decode
        // route for those rather than slice mid-byte.
        guard descriptor.bitsAllocated >= 8 else {
            guard let all = dataSet.pixelData(),
                  let frameBytes = all.frameData(at: frame) else {
                throw PixelDataError.frameExtractionFailed(frameIndex: frame)
            }
            return PixelData(data: frameBytes, descriptor: Self.singleFrame(descriptor))
        }

        let bytesPerFrame = descriptor.rows * descriptor.columns
            * descriptor.samplesPerPixel * (descriptor.bitsAllocated / 8)
        let start = element.valueData.startIndex + frame * bytesPerFrame
        let end = start + bytesPerFrame
        guard bytesPerFrame > 0, end <= element.valueData.endIndex else {
            throw PixelDataError.frameExtractionFailed(frameIndex: frame)
        }

        let slice = Data(element.valueData[start..<end])
        let bytes = DataSet.nativePixelBytesLittleEndian(
            slice, byteOrder: element.byteOrder, bitsAllocated: descriptor.bitsAllocated)
        return PixelData(data: bytes, descriptor: Self.singleFrame(descriptor))
    }

    /// Reads (7FE0,0001) Extended Offset Table values (64-bit LE), when present.
    ///
    /// The element is OV (PS3.5 Table 6.2-1); a file that carries it as UN has the
    /// same value layout, so `valueData` holds the table either way.
    func extendedOffsetTableValues() -> [UInt64]? {
        guard let element = dataSet[Tag.extendedOffsetTable],
              !element.valueData.isEmpty,
              element.valueData.count % 8 == 0 else {
            return nil
        }
        let data = element.valueData
        var offsets: [UInt64] = []
        offsets.reserveCapacity(data.count / 8)
        var i = data.startIndex
        while i + 8 <= data.endIndex {
            var value: UInt64 = 0
            for b in 0..<8 {
                value |= UInt64(data[i + b]) << (8 * b)
            }
            offsets.append(value)
            i += 8
        }
        return offsets
    }

    private static func singleFrame(_ d: PixelDataDescriptor) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: d.rows,
            columns: d.columns,
            numberOfFrames: 1,
            bitsAllocated: d.bitsAllocated,
            bitsStored: d.bitsStored,
            highBit: d.highBit,
            isSigned: d.isSigned,
            samplesPerPixel: d.samplesPerPixel,
            photometricInterpretation: d.photometricInterpretation,
            planarConfiguration: d.planarConfiguration
        )
    }
}
