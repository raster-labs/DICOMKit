import Foundation
import JPEGLS

/// JPEG-LS codec backed by the JLSwift `JPEGLS` package.
///
/// Bridges DICOM pixel data (PS3.5 §A.4.3, JPEG-LS Image Compression) to JLSwift's pure-Swift JPEG-LS
/// implementation (ITU-T T.87 / ISO/IEC 14495-1) for both lossless and
/// near-lossless encode/decode. The previous in-tree JPEG-LS implementation
/// (markers, bit I/O, context modelling) was retired in favour of JLSwift.
///
/// Transfer syntaxes:
///   • 1.2.840.10008.1.2.4.80  JPEG-LS Lossless
///   • 1.2.840.10008.1.2.4.81  JPEG-LS Near-Lossless
/// NEMA-verified: 2026a, checked 2026-09-25 — the two JPEG-LS UIDs come from `TransferSyntax` (PS3.6 2026a Table A-1). `canEncode` (8 or 16 allocated, 2–16 stored, 1 or 3 samples) matches PS3.5 2026a Table 8.2.3-1. The header citation said §A.4.5 (MPEG2); corrected to §A.4.3. The codec implements ITU-T T.87, outside DICOM.
public struct JPEGLSCodec: ImageCodec, ImageEncoder, Sendable {
    /// Supported JPEG-LS transfer syntaxes for decoding
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.jpegLSLossless.uid,      // 1.2.840.10008.1.2.4.80
        TransferSyntax.jpegLSNearLossless.uid    // 1.2.840.10008.1.2.4.81
    ]

    /// Supported JPEG-LS transfer syntaxes for encoding
    public static let supportedEncodingTransferSyntaxes: [String] = [
        TransferSyntax.jpegLSLossless.uid,      // 1.2.840.10008.1.2.4.80
        TransferSyntax.jpegLSNearLossless.uid    // 1.2.840.10008.1.2.4.81
    ]

    /// The transfer syntax this decoder instance serves, when known.
    ///
    /// The registry wires one instance per syntax. Under JPEG-LS Lossless
    /// (1.2.840.10008.1.2.4.80) a scan whose NEAR parameter is non-zero is a
    /// near-lossless scan and is refused: decoding it would return samples that
    /// differ from the encoder's input under a syntax that promises exactness.
    /// `nil` (the default) accepts both lossless and near-lossless scans.
    private let decodingTransferSyntaxUID: String?

    public init(decodingTransferSyntaxUID: String? = nil) {
        self.decodingTransferSyntaxUID = decodingTransferSyntaxUID
    }

    // MARK: - Decoding

    /// Decodes a JPEG-LS compressed frame strictly against `descriptor`.
    ///
    /// The decoded frame header must match the descriptor exactly: width and
    /// height equal Columns and Rows, the component count equals Samples per
    /// Pixel and the sample precision P equals Bits Stored (PS3.5 A.4.3; DCMTK
    /// refuses the same mismatch); every component must be a full-size plane.
    /// Any mismatch throws. Previously a mis-sized frame was silently
    /// zero-filled or truncated to the descriptor's byte count and an
    /// over-precise frame was silently clamped.
    /// - Parameters:
    ///   - frameData: JPEG-LS compressed data
    ///   - descriptor: Pixel data descriptor
    ///   - frameIndex: Frame index (unused for single frame decode)
    /// - Returns: Uncompressed pixel data laid out per `descriptor`
    /// - Throws: `DICOMError` if decoding fails or the frame does not match `descriptor`
    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        guard !frameData.isEmpty else {
            throw DICOMError.parsingFailed("Empty JPEG-LS data")
        }

        if decodingTransferSyntaxUID == TransferSyntax.jpegLSLossless.uid {
            try Self.requireLosslessScans(in: frameData)
        }

        let image: MultiComponentImageData
        do {
            image = try JPEGLSDecoder().decode(frameData)
        } catch {
            throw DICOMError.parsingFailed("JPEG-LS decode failed: \(error)")
        }

        try Self.validate(image, against: descriptor)
        return serialize(image, descriptor: descriptor)
    }

    /// Throws when any scan in `frameData` carries NEAR > 0 (ITU-T T.87 C.2.4.1.1).
    ///
    /// Only the marker structure is parsed; no sample is decoded.
    static func requireLosslessScans(in frameData: Data) throws {
        // JLSwift's parser walks zero-based offsets; rebase a slice first.
        let data = frameData.startIndex == 0 ? frameData : Data(frameData)
        let parsed: JPEGLSParseResult
        do {
            parsed = try JPEGLSParser(data: data).parse()
        } catch {
            throw DICOMError.parsingFailed("JPEG-LS decode failed: \(error)")
        }
        if let scan = parsed.scanHeaders.first(where: { $0.near > 0 }) {
            throw DICOMError.parsingFailed(
                "JPEG-LS Lossless (\(TransferSyntax.jpegLSLossless.uid)) frame carries a near-lossless scan "
                    + "(NEAR = \(scan.near)); refusing to decode inexact samples under a lossless transfer syntax"
            )
        }
    }

    /// Verifies that the decoded image is exactly the frame `descriptor` declares.
    static func validate(_ image: MultiComponentImageData, against descriptor: PixelDataDescriptor) throws {
        let header = image.frameHeader
        guard header.width == descriptor.columns, header.height == descriptor.rows else {
            throw DICOMError.parsingFailed(
                "Decoded JPEG-LS dimensions (\(header.width)x\(header.height)) do not match expected "
                    + "(\(descriptor.columns)x\(descriptor.rows))"
            )
        }
        guard header.componentCount == descriptor.samplesPerPixel,
              image.components.count == descriptor.samplesPerPixel else {
            throw DICOMError.parsingFailed(
                "Decoded JPEG-LS component count \(image.components.count) (frame header "
                    + "\(header.componentCount)) does not match samples per pixel \(descriptor.samplesPerPixel)"
            )
        }
        guard header.bitsPerSample == descriptor.bitsStored, header.bitsPerSample <= descriptor.bitsAllocated else {
            throw DICOMError.parsingFailed(
                "Decoded JPEG-LS precision \(header.bitsPerSample) bits does not match Bits Stored "
                    + "\(descriptor.bitsStored) (Bits Allocated \(descriptor.bitsAllocated))"
            )
        }
        for component in image.components {
            guard component.pixels.count == descriptor.rows,
                  component.pixels.allSatisfy({ $0.count == descriptor.columns }) else {
                throw DICOMError.parsingFailed(
                    "Decoded JPEG-LS component \(component.id) is not a full \(descriptor.columns)x\(descriptor.rows) "
                        + "plane; sub-sampled components are not supported"
                )
            }
        }
    }

    // MARK: - Encoding

    /// Whether this encoder supports the given configuration
    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
            return false
        }
        guard descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3 else {
            return false
        }
        return true
    }

    /// Encodes a single frame to JPEG-LS format
    /// - Parameters:
    ///   - frameData: Uncompressed frame data laid out per `descriptor`
    ///   - descriptor: Pixel data descriptor
    ///   - frameIndex: Zero-based frame index
    ///   - configuration: Compression configuration
    /// - Returns: JPEG-LS compressed frame data
    /// - Throws: `DICOMError` if encoding fails
    public func encodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int, configuration: CompressionConfiguration) throws -> Data {
        let near = nearParameter(for: configuration, descriptor: descriptor)
        // JLSwift expects sample values in [0, 2^bitsPerSample - 1]; track the
        // stored precision (Bits Stored) rather than the allocated container.
        let bitsPerSample = max(2, descriptor.bitsStored)
        let interleave: JPEGLSInterleaveMode = descriptor.samplesPerPixel > 1 ? .sample : .none

        do {
            let image = try buildImage(from: frameData, descriptor: descriptor, bitsPerSample: bitsPerSample)
            let config = try JPEGLSEncoder.Configuration(near: near, interleaveMode: interleave)
            return try JPEGLSEncoder().encode(image, configuration: config)
        } catch let error as DICOMError {
            throw error
        } catch {
            throw DICOMError.parsingFailed("JPEG-LS encode failed: \(error)")
        }
    }

    // MARK: - NEAR parameter

    /// Derives the JPEG-LS NEAR value from a DICOM compression configuration.
    /// Lossless (or lossless-preferring) configurations map to NEAR = 0.
    ///
    /// JLSwift's encoder caps NEAR at 255 regardless of sample precision
    /// (`JPEGLSEncoder.Configuration` rejects NEAR > 255), so the derived value
    /// is clamped to that range — otherwise a 16-bit source at, e.g., "high"
    /// quality would yield NEAR ≈ 655 and the encode would throw.
    private func nearParameter(for configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Int {
        if configuration.preferLossless || configuration.quality.isLossless {
            return 0
        }
        let maxVal = descriptor.bitsAllocated == 8 ? 255 : (1 << descriptor.bitsStored) - 1
        let scaled = Int(Double(maxVal) * (1.0 - configuration.quality.value) * 0.1)
        return min(Self.maxNear, max(0, scaled))
    }

    /// Largest NEAR value JLSwift's `JPEGLSEncoder.Configuration` accepts.
    private static let maxNear = 255

    // MARK: - Pixel (de)serialization

    /// Bytes per stored sample, derived from Bits Allocated (8 → 1, otherwise 2).
    private func bytesPerSample(_ descriptor: PixelDataDescriptor) -> Int {
        descriptor.bitsAllocated <= 8 ? 1 : 2
    }

    /// Linear pixel index for component `c` at (`x`, `y`), honouring Samples per
    /// Pixel and Planar Configuration (0 = sample-interleaved, 1 = planar).
    private func pixelIndex(component c: Int, x: Int, y: Int, width: Int, height: Int, samples: Int, planar: Bool) -> Int {
        if samples == 1 {
            return y * width + x
        } else if planar {
            return c * width * height + y * width + x
        } else {
            return (y * width + x) * samples + c
        }
    }

    /// Serializes JLSwift's row-major `[[Int]]` components into DICOM pixel bytes
    /// matching `descriptor` (Bits Allocated, Samples per Pixel, Planar
    /// Configuration). 16-bit samples are written little-endian per DICOM.
    /// Callers must `validate` first: every plane is exactly `columns` x `rows`.
    private func serialize(_ image: MultiComponentImageData, descriptor: PixelDataDescriptor) -> Data {
        let width = descriptor.columns
        let height = descriptor.rows
        let samples = descriptor.samplesPerPixel
        let bps = bytesPerSample(descriptor)
        let planar = descriptor.planarConfiguration == 1
        var output = Data(count: width * height * samples * bps)

        output.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let buffer = base.assumingMemoryBound(to: UInt8.self)
            for c in 0..<samples {
                let pixels = image.components[c].pixels
                for y in 0..<height {
                    let row = pixels[y]
                    for x in 0..<width {
                        let value = row[x]
                        let byteIndex = pixelIndex(component: c, x: x, y: y, width: width, height: height, samples: samples, planar: planar) * bps
                        if bps == 1 {
                            buffer[byteIndex] = UInt8(clamping: value)
                        } else {
                            buffer[byteIndex] = UInt8(value & 0xFF)
                            buffer[byteIndex + 1] = UInt8((value >> 8) & 0xFF)
                        }
                    }
                }
            }
        }
        return output
    }

    /// Builds a JLSwift `MultiComponentImageData` from DICOM pixel bytes.
    private func buildImage(from frameData: Data, descriptor: PixelDataDescriptor, bitsPerSample: Int) throws -> MultiComponentImageData {
        let width = descriptor.columns
        let height = descriptor.rows
        let samples = descriptor.samplesPerPixel
        let bps = bytesPerSample(descriptor)
        let planar = descriptor.planarConfiguration == 1
        let start = frameData.startIndex

        func sample(component c: Int, _ x: Int, _ y: Int) -> Int {
            let byteIndex = pixelIndex(component: c, x: x, y: y, width: width, height: height, samples: samples, planar: planar) * bps
            if bps == 1 {
                guard byteIndex < frameData.count else { return 0 }
                return Int(frameData[start + byteIndex])
            } else {
                guard byteIndex + 1 < frameData.count else { return 0 }
                return Int(frameData[start + byteIndex]) | (Int(frameData[start + byteIndex + 1]) << 8)
            }
        }

        func plane(component c: Int) -> [[Int]] {
            var rows = [[Int]]()
            rows.reserveCapacity(height)
            for y in 0..<height {
                var row = [Int](repeating: 0, count: width)
                for x in 0..<width {
                    row[x] = sample(component: c, x, y)
                }
                rows.append(row)
            }
            return rows
        }

        switch samples {
        case 1:
            return try MultiComponentImageData.grayscale(pixels: plane(component: 0), bitsPerSample: bitsPerSample)
        case 3:
            return try MultiComponentImageData.rgb(
                redPixels: plane(component: 0),
                greenPixels: plane(component: 1),
                bluePixels: plane(component: 2),
                bitsPerSample: bitsPerSample
            )
        default:
            throw DICOMError.parsingFailed("JPEG-LS encode: unsupported samplesPerPixel \(samples)")
        }
    }
}
