import Foundation

/// Caller-selected resource bounds for a single compressed frame, enforced before sample decoding.
/// These are application resource policies, not DICOM size limits.
public struct PixelDecodeLimits: Sendable {
    /// Maximum compressed bytes in one codestream.
    public let maximumEncodedBytes: Int
    /// Maximum unpacked output bytes in one frame.
    public let maximumDecodedBytes: Int
    /// Maximum pixels in one frame (bounds decoder intermediate planes as well).
    public let maximumPixels: Int
    /// Default per-frame limits: 64 MiB encoded/output and 16 million pixels.
    public static let `default` = PixelDecodeLimits()

    /// Creates per-frame resource bounds. Nonpositive limits refuse every frame.
    public init(maximumEncodedBytes: Int = 64 << 20, maximumDecodedBytes: Int = 64 << 20,
                maximumPixels: Int = 16 << 20) {
        self.maximumEncodedBytes = maximumEncodedBytes
        self.maximumDecodedBytes = maximumDecodedBytes
        self.maximumPixels = maximumPixels
    }

    func validate(_ data: Data, descriptor d: PixelDataDescriptor, frameIndex: Int) throws -> Int {
        guard !data.isEmpty, data.count <= maximumEncodedBytes else {
            throw DICOMError.limitExceeded("Compressed frame exceeds encoded byte budget or is empty")
        }
        guard frameIndex >= 0, frameIndex < d.numberOfFrames,
              d.rows > 0, d.columns > 0, d.samplesPerPixel == 1 || d.samplesPerPixel == 3,
              d.bitsAllocated == 8 || d.bitsAllocated == 16,
              (2...d.bitsAllocated).contains(d.bitsStored), d.highBit == d.bitsStored - 1,
              d.planarConfiguration == 0 || d.planarConfiguration == 1 else {
            throw DICOMError.parsingFailed("Invalid compressed frame descriptor or frame index")
        }
        let (pixels, pixelOverflow) = d.rows.multipliedReportingOverflow(by: d.columns)
        let (samples, sampleOverflow) = pixels.multipliedReportingOverflow(by: d.samplesPerPixel)
        let (bytes, byteOverflow) = samples.multipliedReportingOverflow(by: d.bitsAllocated / 8)
        guard !pixelOverflow, !sampleOverflow, !byteOverflow,
              pixels <= maximumPixels, bytes > 0, bytes <= maximumDecodedBytes else {
            throw DICOMError.limitExceeded("Compressed frame exceeds decoded pixel/byte budget")
        }
        return bytes
    }
}

/// A source inconsistency encountered during an explicitly enabled decoding recovery.
public enum PixelDecodeDiagnostic: Sendable, Equatable {
    /// The JPEG-LS stream has a wider precision than the source Bits Stored attribute.
    case sourcePrecisionMismatch(sourceBitsStored: Int, encodedPrecision: Int)
}

/// Decoded bytes and their actual color/layout, retaining the requested source frame identity.
/// The original DICOM descriptor remains available to the caller as source provenance.
public struct DecodedPixelFrame: Sendable {
    /// Uncompressed samples, little endian for multibyte samples.
    public let data: Data
    /// Describes the decoded bytes, including any codec color conversion.
    public let descriptor: PixelDataDescriptor
    /// Zero-based index of the frame in the source object.
    public let sourceFrameIndex: Int

    /// Explicit recovery diagnostics; source metadata is never rewritten by the decoder.
    public let diagnostics: [PixelDecodeDiagnostic]

    /// Creates a decoded result.
    public init(data: Data, descriptor: PixelDataDescriptor, sourceFrameIndex: Int,
                diagnostics: [PixelDecodeDiagnostic] = []) {
        self.data = data
        self.descriptor = descriptor
        self.sourceFrameIndex = sourceFrameIndex
        self.diagnostics = diagnostics
    }
}
