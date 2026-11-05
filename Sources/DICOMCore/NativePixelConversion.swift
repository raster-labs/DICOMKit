// Shared by DICOMKit's materialized conversion paths. The managed codec entry points
// have their own admission and storage contracts.
import Foundation

extension EncapsulatedPixelData {
    /// The index is validated before this call. Reject an oversized codestream
    /// before frameData allocates space to join multiple fragments.
    package func conversionCodestream(at frame: Int, using index: FrameIndex) throws -> Data {
        let limit = PixelDecodeLimits.default.maximumEncodedBytes
        guard let bytes = frameData(at: frame, using: index, maximumBytes: limit) else {
            throw DICOMError.limitExceeded("Compressed frame exceeds the conversion byte limit")
        }
        return bytes
    }

    /// Decode in frame order, keeping at most one assembled codestream in addition
    /// to the original fragments. The native Value Length excludes undefined length.
    package func decodedNativeValue(
        using codec: any ImageCodec,
        extendedOffsets: Data?,
        extendedLengths: Data?
    ) throws -> Data {
        let frameBytes = try descriptor.checkedNativeConversionFrameBytes()
        let index = try resolveFrameIndex(
            extendedOffsetTableData: extendedOffsets,
            extendedOffsetTableLengthsData: extendedLengths
        )
        var result = Data()
        for frame in 0..<descriptor.numberOfFrames {
            try Task.checkCancellation()
            let bytes = try conversionCodestream(at: frame, using: index)
            let samples = try codec.decodeFrame(bytes, descriptor: descriptor, frameIndex: frame)
            guard samples.count == frameBytes else {
                throw DICOMError.parsingFailed("Decoded frame byte count disagrees with the native pixel attributes")
            }
            result.append(samples)
        }
        if !result.count.isMultiple(of: 2) { result.append(0) }
        return result
    }
}

extension PixelDataDescriptor {
    /// Checks the native value before endian conversion, colour conversion or codec allocation.
    /// One final zero padding byte is legal only when the logical byte count is odd.
    package func nativeBytesForEncoding(_ element: DataElement) throws -> Data {
        guard !element.isEncapsulated, element.length != UInt32.max else {
            throw DICOMError.parsingFailed("Native transfer syntax carries encapsulated Pixel Data")
        }
        let frameBytes = try checkedNativeConversionFrameBytes()
        let length = frameBytes * numberOfFrames // product checked by checkedNativeConversionFrameBytes()
        let count = element.valueData.count
        guard Int(element.length) == count,
              count == length || (!length.isMultiple(of: 2) && count == length + 1) else {
            throw DICOMError.parsingFailed("Native Pixel Data length disagrees with its frame attributes")
        }
        let bytes = DICOMWriter.value(element.valueData, vr: element.vr, from: element.byteOrder, to: .littleEndian)
        if count != length {
            guard bytes.last == 0 else { throw DICOMError.parsingFailed("Invalid native Pixel Data padding") }
            return bytes.prefix(length)
        }
        return bytes
    }

    /// Validate the single-frame budget and complete native DICOM Value Length
    /// before codec execution. Compressed hospital frame conversion uses byte-aligned samples.
    package func checkedNativeConversionFrameBytes() throws -> Int {
        guard rows > 0, columns > 0, samplesPerPixel > 0, numberOfFrames > 0,
              bitsAllocated >= 8, bitsAllocated.isMultiple(of: 8) else {
            throw DICOMError.parsingFailed("Invalid dimensions or sample width for native pixel conversion")
        }
        let (pixels, pOverflow) = rows.multipliedReportingOverflow(by: columns)
        let (samples, sOverflow) = pixels.multipliedReportingOverflow(by: samplesPerPixel)
        let (frameBytes, fOverflow) = samples.multipliedReportingOverflow(by: bitsAllocated / 8)
        let (total, tOverflow) = frameBytes.multipliedReportingOverflow(by: numberOfFrames)
        guard !pOverflow, !sOverflow, !fOverflow, !tOverflow,
              pixels <= PixelDecodeLimits.default.maximumPixels,
              frameBytes <= PixelDecodeLimits.default.maximumDecodedBytes,
              total <= Int(UInt32.max) - 1 else {
            throw DICOMError.limitExceeded("Native pixel geometry exceeds the frame budget or DICOM Value Length")
        }
        return frameBytes
    }
}
