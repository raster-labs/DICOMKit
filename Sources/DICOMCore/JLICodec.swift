import Foundation
import JLISwift

/// JPEG codec backed by the JLISwift native-Swift JPEG package.
///
/// Bridges DICOM pixel data (PS3.5 §A.4.1, JPEG Image Compression) to JLISwift's pure-Swift
/// implementation of ITU-T T.81 for all four DICOM JPEG transfer syntaxes —
/// **both lossy and lossless**:
///
///   • 1.2.840.10008.1.2.4.50  JPEG Baseline (Process 1)        — lossy DCT, 8-bit  (SOF0)
///   • 1.2.840.10008.1.2.4.51  JPEG Extended (Process 2 & 4)    — lossy DCT, ≤12-bit (SOF1)
///   • 1.2.840.10008.1.2.4.57  JPEG Lossless (Process 14)       — predictive       (SOF3)
///   • 1.2.840.10008.1.2.4.70  JPEG Lossless SV1 (Process 14,1) — predictive, P1   (SOF3)
///
/// **Decoding** is mode-agnostic: `JLIDecoder` auto-detects the SOF marker, so a
/// single decoder serves all four syntaxes (`encodingTransferSyntaxUID` is ignored
/// on the decode path).
///
/// **Encoding** is mode-specific: the JPEG process is selected from
/// `encodingTransferSyntaxUID`. The registry constructs one instance per encode
/// UID (mirroring `J2KSwiftCodec`/`HTJ2KCodec`). The default initialiser targets
/// lossless SV1, so a bare `JLICodec()` round-trips bit-exactly — the contract the
/// DICOMStudio codec bench and the multi-codec adapter tests rely on.
///
/// Pixel bridging: `JLIImage.data` is channel-interleaved `[UInt8]`, row-major,
/// 16-bit samples little-endian — matching DICOM little-endian storage, so only
/// planar→interleaved reshuffling (handled by `interleavedFrameBytes`) is needed.
/// NEMA-verified: 2026a, checked 2026-10-01 — the four JPEG UIDs come from `TransferSyntax` (PS3.6 2026a Table A-1). `canEncode` admits a subset of PS3.5 2026a Tables 8.2.1-1/8.2.1-2: Baseline 8/8 (colour written YCbCr 4:2:2 = YBR_FULL_422, D190), Extended 8/8 or 16/12 monochrome only (Table 8.2.1-1 has no 3-sample .51 row), Lossless 8-or-16 allocated with 2–16 stored (the tables allow 1–16; 1 is a JLISwift limit), YBR_FULL_422 only with Baseline. The "§A.4.1–A.4.3" citation was narrowed to §A.4.1 (A.4.2 is RLE, A.4.3 JPEG-LS). The codec implements ITU-T T.81, outside DICOM.
public struct JLICodec: ImageCodec, ImageEncoder, Sendable {
    /// All four DICOM JPEG transfer syntaxes can be decoded.
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.jpegBaseline.uid,     // 1.2.840.10008.1.2.4.50
        TransferSyntax.jpegExtended.uid,     // 1.2.840.10008.1.2.4.51
        TransferSyntax.jpegLossless.uid,     // 1.2.840.10008.1.2.4.57
        TransferSyntax.jpegLosslessSV1.uid   // 1.2.840.10008.1.2.4.70
    ]

    /// All four DICOM JPEG transfer syntaxes can be encoded.
    public static let supportedEncodingTransferSyntaxes: [String] = supportedTransferSyntaxes

    /// The transfer syntax this instance encodes to. Selects the JPEG process:
    /// baseline/extended → lossy DCT, lossless/SV1 → SOF3 predictive. Ignored when
    /// decoding (the SOF marker drives the decoder).
    public let encodingTransferSyntaxUID: String

    /// Creates a JPEG codec.
    /// - Parameter encodingTransferSyntaxUID: The target syntax for encoding.
    ///   Defaults to JPEG Lossless SV1 so a bare `JLICodec()` is bit-exact
    ///   (the bench / adapter-test contract).
    public init(encodingTransferSyntaxUID: String = TransferSyntax.jpegLosslessSV1.uid) {
        self.encodingTransferSyntaxUID = encodingTransferSyntaxUID
    }

    /// Whether the target syntax is one of the two lossless (SOF3) JPEG processes.
    private var encodesLossless: Bool {
        encodingTransferSyntaxUID == TransferSyntax.jpegLossless.uid
            || encodingTransferSyntaxUID == TransferSyntax.jpegLosslessSV1.uid
    }

    /// Whether the target syntax is JPEG Baseline (Process 1) — 8-bit only.
    private var encodesBaseline: Bool {
        encodingTransferSyntaxUID == TransferSyntax.jpegBaseline.uid
    }

    // MARK: - Decoding

    /// Decodes a JPEG-compressed frame (any SOF mode) to DICOM pixel bytes.
    /// - Parameters:
    ///   - frameData: A single JPEG codestream.
    ///   - descriptor: Pixel data descriptor (drives the planar reshuffle).
    ///   - frameIndex: Frame index (unused — one codestream per call).
    /// - Returns: Uncompressed pixel data laid out per `descriptor`.
    /// - Throws: `DICOMError` if decoding fails.
    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        guard !frameData.isEmpty else {
            throw DICOMError.parsingFailed("Empty JPEG data")
        }
        do {
            let image = try JLIDecoder().decode(from: [UInt8](frameData))
            return dicomFrameBytes(fromInterleaved: image.data, descriptor: descriptor)
        } catch {
            throw DICOMError.parsingFailed("JLISwift decode failed: \(error)")
        }
    }

    // MARK: - Encoding

    /// Whether this codec can encode the given configuration for its target syntax.
    ///
    /// Constraints follow each JPEG process plus JLISwift's input rules:
    ///   • samples per pixel must be 1 (grayscale) or 3 (RGB);
    ///   • Baseline (.50): 8-bit unsigned only;
    ///   • Extended (.51): ≤12-bit unsigned (the SOF1 precision ceiling), monochrome only;
    ///   • Lossless (.57/.70): 2–16 bit, signed or unsigned (bytes preserved exactly);
    ///   • the lossy DCT path rejects signed samples (undefined level shift).
    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        guard descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3 else {
            return false
        }

        if encodesLossless {
            // SOF3 predictive: 2–16 bit precision, sign-agnostic.
            guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
                return false
            }
            return descriptor.bitsStored >= 2 && descriptor.bitsStored <= 16
        }

        // Lossy DCT: JLISwift's level shift is defined only for unsigned samples.
        if descriptor.isSigned {
            return false
        }
        // Pre-converted YCbCr (YBR_FULL_422/YBR_FULL) input only has an 8-bit path
        // through JLIEncoder — see the `.yCbCr` colorModel branch in `encodeFrame`.
        if descriptor.samplesPerPixel == 3 && descriptor.photometricInterpretation.isYBR
            && descriptor.bitsAllocated > 8 {
            return false
        }
        if encodesBaseline {
            // Process 1 — 8-bit baseline sequential.
            return descriptor.bitsAllocated == 8 && descriptor.bitsStored <= 8
        }
        // Extended (Process 2 & 4) — up to 12-bit, monochrome only: PS3.5 2026a Table 8.2.1-1 has
        // no 3-sample row for 1.2.840.10008.1.2.4.51 ("No other Standard Photometric
        // Interpretation Values shall be used", 8.2.1).
        guard descriptor.samplesPerPixel == 1 else { return false }
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
            return false
        }
        return descriptor.bitsStored <= 12
    }

    /// Encodes a single frame to the JPEG process selected by `encodingTransferSyntaxUID`.
    /// - Parameters:
    ///   - frameData: Uncompressed frame bytes laid out per `descriptor`.
    ///   - descriptor: Pixel data descriptor.
    ///   - frameIndex: Zero-based frame index (unused — one codestream per frame).
    ///   - configuration: Compression configuration; for the lossy processes its
    ///     `quality` maps to the JPEG quality factor. Ignored for lossless.
    /// - Returns: The JPEG codestream for this frame.
    /// - Throws: `DICOMError` if encoding fails.
    public func encodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor,
                            frameIndex: Int, configuration: CompressionConfiguration) throws -> Data {
        let spp = descriptor.samplesPerPixel
        guard spp == 1 || spp == 3 else {
            throw DICOMError.parsingFailed("JLISwift: unsupported samplesPerPixel \(spp)")
        }
        let pixelFormat: JLIPixelFormat = descriptor.bitsAllocated <= 8 ? .uint8 : .uint16
        let colorModel: JLIColorModel
        if spp == 1 {
            colorModel = .grayscale
        } else if !encodesLossless && descriptor.photometricInterpretation.isYBR {
            // Samples are already YCbCr (e.g. YBR_FULL_422) — tell JLIEncoder not to
            // re-transform them on the lossy DCT path. Only valid for 8-bit input
            // (JLIEncoder's pre-converted YCbCr path is 8-bit only), which matches
            // Table 8.2.1-1: the DICOM JPEG processes only permit YBR_FULL_422/RGB
            // color on 8-bit Baseline, never on 12-bit Extended.
            //
            // The lossless (SOF3) path never transforms color regardless of this
            // label — JLIEncoder requires it to literally be `.rgb`/`.rgba` there
            // (a component-count marker, not a color-space claim), so YBR-tagged
            // lossless input keeps `.rgb` below and round-trips byte-exact either way.
            guard pixelFormat == .uint8 else {
                throw DICOMError.parsingFailed(
                    "JLISwift: \(descriptor.photometricInterpretation.rawValue) input requires "
                    + "8-bit samples (bitsAllocated=\(descriptor.bitsAllocated))")
            }
            colorModel = .yCbCr
        } else {
            colorModel = .rgb
        }
        let interleaved = interleavedFrameBytes(from: frameData, descriptor: descriptor)

        do {
            let image = try JLIImage(width: descriptor.columns, height: descriptor.rows,
                                     pixelFormat: pixelFormat, colorModel: colorModel,
                                     data: interleaved, isSigned: descriptor.isSigned)
            let cfg = encoderConfiguration(descriptor: descriptor, configuration: configuration,
                                           pixelFormat: pixelFormat)
            // JLISwift writes a JFIF APP0 segment; PS3.5 2026a 8.2.1 recommends it be absent (D190).
            return JPEGInterchangeFormat.removingJFIFSegments(Data(try JLIEncoder().encode(image, configuration: cfg)))
        } catch {
            throw DICOMError.parsingFailed("JLISwift encode failed: \(error)")
        }
    }

    // MARK: - Configuration mapping

    /// Builds the JLISwift encoder configuration for the target JPEG process.
    private func encoderConfiguration(descriptor: PixelDataDescriptor,
                                      configuration: CompressionConfiguration,
                                      pixelFormat: JLIPixelFormat) -> JLIEncoderConfiguration {
        if encodesLossless {
            // SOF3 predictor 1, point-transform 0 — bit-exact. Both .57 (Process 14)
            // and .70 (SV1) are valid with the left predictor; .70 *requires* it.
            var cfg = JLIEncoderConfiguration.diagnosticLossless
            cfg.losslessPredictor = 1
            cfg.losslessPointTransform = 0
            if pixelFormat == .uint16 {
                // Pin precision to the stored depth; otherwise JLISwift derives
                // 12-bit and drops the high bits of >12-bit sources.
                cfg.losslessPrecision = min(16, max(2, descriptor.bitsStored))
            }
            return cfg
        }

        // Lossy DCT — start from the tuned perceptual defaults, then force the
        // properties the DICOM JPEG processes mandate:
        //   • sequential, never progressive (Baseline/Extended are non-progressive);
        //   • colour as YCbCr 4:2:2 — PS3.5 2026a Table 8.2.1-1 allows a 3-sample JPEG Baseline
        //     stream only as YBR_FULL_422 or RGB (components stored as RGB). JLISwift's lossy
        //     path always applies the RGB → YCbCr transform, so the stream is written 4:2:2 and
        //     labelled YBR_FULL_422 by the transcoders (D190 / D-CORE-2). 4:4:4 YCbCr has no
        //     valid label.
        // Sample precision (SOF0 8-bit vs SOF1 12-bit) follows the pixel format.
        var cfg = JLIEncoderConfiguration.default
        cfg.lossless = false
        cfg.progressive = false
        cfg.chromaSubsampling = descriptor.samplesPerPixel == 3 ? .yuv422 : .yuv444
        cfg.distance = nil
        cfg.quality = Self.jpegQuality(from: configuration.quality)
        return cfg
    }

    /// Maps a DICOM `CompressionQuality` (0.0–1.0) to a JPEG quality factor (1–100).
    static func jpegQuality(from quality: CompressionQuality) -> Double {
        max(1.0, min(100.0, quality.value * 100.0))
    }
}
