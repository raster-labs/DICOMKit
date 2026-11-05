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
        try pixelData(frame: frame, codecRegistry: .shared)
    }

    public func pixelData(frame: Int, codecRegistry: CodecRegistry) throws -> PixelData {
        let descriptor = try dataSet.tryPixelDataDescriptor()
        let source = try frameSource(descriptor: descriptor, frame: frame, registry: codecRegistry)
        return try readFrame(frame, descriptor: descriptor, source: source, aligned: false)
    }

    /// Decodes a single frame for page-aligned access, preserving the codec's output descriptor.
    public func alignedPixelData(frame: Int) throws -> PixelData {
        try alignedPixelData(frame: frame, codecRegistry: .shared)
    }

    public func alignedPixelData(frame: Int, codecRegistry: CodecRegistry) throws -> PixelData {
        let descriptor = try dataSet.tryPixelDataDescriptor()
        let source = try frameSource(descriptor: descriptor, frame: frame, registry: codecRegistry)
        return try readFrame(frame, descriptor: descriptor, source: source, aligned: true)
    }

    /// Captured once for a complete operation, including all parallel frames and previews.
    enum FrameSource: Sendable {
        case native(DataElement)
        case encapsulated(EncapsulatedPixelData, EncapsulatedPixelData.FrameIndex, any ImageCodec)
    }

    func frameSource(descriptor: PixelDataDescriptor, frame: Int, registry: CodecRegistry) throws -> FrameSource {
        guard frame >= 0, frame < descriptor.numberOfFrames else {
            throw PixelDataError.frameExtractionFailed(frameIndex: frame)
        }
        guard let element = dataSet[.pixelData] else { throw PixelDataError.missingPixelData }
        if !element.isEncapsulated {
            guard !element.valueData.isEmpty else { throw PixelDataError.missingPixelData }
            if let uid = transferSyntaxUID, TransferSyntax.from(uid: uid)?.isEncapsulated == true {
                throw PixelDataError.decodingFailed(frameIndex: frame, reason: "Compressed transfer syntax carries native Pixel Data")
            }
            return .native(element)
        }
        guard let uid = transferSyntaxUID else { throw PixelDataError.missingTransferSyntax }
        guard let resolved = registry.resolveDecoder(for: uid, descriptor: descriptor) else {
            throw PixelDataError.unsupportedTransferSyntax(uid)
        }
        guard let encapsulated = dataSet.encapsulatedPixelData(),
              let index = encapsulated.makeFrameIndex(
                extendedOffsetTableData: dataSet[.extendedOffsetTable]?.valueData,
                extendedOffsetTableLengthsData: dataSet[.extendedOffsetTableLengths]?.valueData
              ) else { throw PixelDataError.frameExtractionFailed(frameIndex: frame) }
        return .encapsulated(encapsulated, index, resolved.codec)
    }

    func readFrame(_ frame: Int, descriptor: PixelDataDescriptor, source: FrameSource, aligned: Bool) throws -> PixelData {
        guard frame >= 0, frame < descriptor.numberOfFrames else {
            throw PixelDataError.frameExtractionFailed(frameIndex: frame)
        }
        switch source {
        case .native(let element):
            return try nativeFrame(frame, element: element, descriptor: descriptor, aligned: aligned)
        case .encapsulated(let encapsulated, let index, let codec):
            guard let bytes = encapsulated.frameData(at: frame, using: index, maximumBytes: PixelDecodeLimits.default.maximumEncodedBytes) else {
                throw PixelDataError.frameExtractionFailed(frameIndex: frame)
            }
            do {
                if aligned, let rle = codec as? RLECodec, descriptor.bitsAllocated >= 8 {
                    let size = try descriptor.checkedNativeConversionFrameBytes()
                    if let buffer = AlignedPixelBuffer(byteCount: size) {
                        let written = try rle.decodeFrame(bytes, descriptor: descriptor, frameIndex: frame,
                            into: UnsafeMutableRawBufferPointer(start: buffer.baseAddress, count: size))
                        guard written == size else { throw DICOMError.parsingFailed("Unexpected decoded frame size") }
                        return PixelData(alignedStorage: buffer, descriptor: Self.singleFrame(descriptor))
                    }
                }
                let decoded = try codec.decodePixelFrame(bytes, descriptor: descriptor, frameIndex: frame)
                let result = PixelData(data: decoded.data, descriptor: Self.singleFrame(decoded.descriptor))
                return aligned ? result.pageAligned() : result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw PixelDataError.decodingFailed(frameIndex: frame, reason: error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    /// Geometry comes from the dataset. Reject integer overflow before reserving a buffer.
    static func checkedFrameBytes(_ descriptor: PixelDataDescriptor, frame: Int) throws -> Int {
        guard descriptor.rows > 0, descriptor.columns > 0, descriptor.samplesPerPixel > 0,
              descriptor.bitsAllocated > 0 else { throw PixelDataError.frameExtractionFailed(frameIndex: frame) }
        var size = descriptor.rows
        for factor in [descriptor.columns, descriptor.samplesPerPixel, max(1, descriptor.bitsAllocated / 8)] {
            let (product, overflow) = size.multipliedReportingOverflow(by: factor)
            guard !overflow else { throw PixelDataError.frameExtractionFailed(frameIndex: frame) }
            size = product
        }
        return size
    }

    private func nativeFrame(_ frame: Int, element: DataElement, descriptor: PixelDataDescriptor,
                             aligned: Bool) throws -> PixelData {
        guard descriptor.bitsAllocated >= 8 else {
            guard let all = dataSet.pixelData(), let frameBytes = all.frameData(at: frame) else {
                throw PixelDataError.frameExtractionFailed(frameIndex: frame)
            }
            let result = PixelData(data: frameBytes, descriptor: Self.singleFrame(descriptor))
            return aligned ? result.pageAligned() : result
        }
        let size = try Self.checkedFrameBytes(descriptor, frame: frame)
        let (offset, overflow) = frame.multipliedReportingOverflow(by: size)
        guard !overflow, size <= element.valueData.count, offset <= element.valueData.count - size else {
            throw PixelDataError.frameExtractionFailed(frameIndex: frame)
        }
        let start = element.valueData.startIndex + offset
        let slice = element.valueData[start..<(start + size)]
        if aligned, let buffer = AlignedPixelBuffer(byteCount: size) {
            slice.withUnsafeBytes { bytes in
                if let src = bytes.baseAddress { buffer.baseAddress.copyMemory(from: src, byteCount: size) }
            }
            if element.byteOrder == .bigEndian && descriptor.bitsAllocated == 16 {
                let words = buffer.baseAddress.assumingMemoryBound(to: UInt16.self)
                for i in 0..<(size / 2) { words[i] = words[i].byteSwapped }
            }
            return PixelData(alignedStorage: buffer, descriptor: Self.singleFrame(descriptor))
        }
        let bytes = DataSet.nativePixelBytesLittleEndian(Data(slice), byteOrder: element.byteOrder,
                                                          bitsAllocated: descriptor.bitsAllocated)
        return PixelData(data: bytes, descriptor: Self.singleFrame(descriptor))
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
