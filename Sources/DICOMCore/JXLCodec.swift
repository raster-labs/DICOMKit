import Foundation
import SwiftJXL

/// JPEG XL codec backed by the `SwiftJXL` pure-Swift package (ISO/IEC 18181).
///
/// Bridges DICOM pixel data to `SwiftJXL` for the JPEG XL transfer syntaxes added
/// in Supplement 232 (DICOM 2024d). NEMA-verified: 2026a, checked 2026-09-24 — text-diffed
/// against PS3.6 2026a Table A-1 (the three UIDs) and PS3.5 2026a §10.19 / §A.4.12 (.110
/// lossless, .111 reversible JPEG transcoding, .112 any JPEG XL mode); see
/// ``TransferSyntax/jpegXL``. Encodes both **lossless** JPEG XL (Modular
/// mode, distance 0 → …4.110) and **lossy** JPEG XL (VarDCT, quality-driven
/// distance → …4.112), and decodes lossless (Modular), general/lossy (VarDCT),
/// and JPEG-recompressed JPEG XL back to pixels. The target transfer syntax
/// selects the encode mode (see ``encodingTransferSyntaxUID``). Also used by the
/// DICOMStudio codec bench to compare `SwiftJXL` against other JPEG XL
/// implementations (libjxl `djxl`).
///
/// `SwiftJXL`'s lossy VarDCT encoder (v2.0.0+) covers 8–16-bit greyscale and RGB
/// within its bounded size limits (`<= 4096` per axis and `<= 4,194,304` pixels);
/// inputs beyond VarDCT's size cap transparently fall back to the lossless Modular
/// path, so a lossy (…4.112) encode always yields a valid, conformant JPEG XL
/// codestream.
///
/// Transfer syntaxes:
///   • 1.2.840.10008.1.2.4.110  JPEG XL Lossless             (encode + decode, pixel)
///   • 1.2.840.10008.1.2.4.111  JPEG XL JPEG Recompression   (decode to pixels; recompress/
///                                                            reconstruct at the JPEG-bitstream
///                                                            level via the static helpers below)
///   • 1.2.840.10008.1.2.4.112  JPEG XL (general / lossy)    (encode + decode, pixel)
///
/// JPEG Recompression (…4.111) is not a pixel codec: it losslessly *wraps* an
/// existing JPEG bitstream in a JXL container (and reconstructs it byte-for-byte),
/// so it cannot flow through the pixel `ImageEncoder`/`ImageCodec` protocols. The
/// forward wrap and reverse reconstruct are exposed as ``recompressJPEGFragment(_:)``
/// / ``reconstructJPEGFragment(_:)`` and driven by ``TransferSyntaxConverter`` at the
/// encapsulated-fragment level. Decoding a …4.111 file *to pixels* (for viewing, or to
/// transcode onward to any other syntax) does go through the standard pixel path — a
/// recompressed JXL reconstructs its original JPEG and decodes via ``JLICodec`` — which is
/// why …4.111 is listed in ``supportedTransferSyntaxes`` but not in
/// ``supportedEncodingTransferSyntaxes``.
///
/// Pixel bridging: `SwiftJXL` operates on explicit caller-allocated planar or interleaved
/// little-endian `UInt8` / `UInt16` buffers (`copyPolicy: .requireSharedStorage`).
/// Signed 16-bit pixel data (Pixel Representation = 1, e.g. CT) is level-shifted from
/// two's-complement `Int16` (`word ^ 0x8000`) to unsigned offset-binary for the JPEG XL
/// codestream and un-shifted on decode. JPEG XL has no signed 8-bit sample type, so
/// signed 8-bit is rejected rather than silently mis-encoded.
public struct JXLCodec: ImageCodec, ImageEncoder, Sendable {
    /// Finite decode policy that does not construct or retain transfer-syntax Strings.
    public enum DecodingSyntax: UInt8, Sendable {
        /// Auto-detect JPEG Recompression (`jbrd`) vs pixel JPEG XL.
        case any
        /// JPEG XL Lossless — `1.2.840.10008.1.2.4.110`.
        case lossless
        /// JPEG XL JPEG Recompression — `1.2.840.10008.1.2.4.111`.
        case recompression
        /// JPEG XL — `1.2.840.10008.1.2.4.112`.
        case general
    }

    /// JPEG XL transfer syntaxes this codec can decode to pixels (lossless, JPEG
    /// recompression, and general/lossy).
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.jpegXLLossless.uid,        // 1.2.840.10008.1.2.4.110
        TransferSyntax.jpegXLRecompression.uid,   // 1.2.840.10008.1.2.4.111
        TransferSyntax.jpegXL.uid                 // 1.2.840.10008.1.2.4.112
    ]

    /// JPEG XL transfer syntaxes this codec can produce *from pixels*: Lossless
    /// (…4.110, Modular) and general/lossy (…4.112, VarDCT — with a lossless Modular
    /// fallback for inputs beyond VarDCT's dimension/pixel cap).
    public static let supportedEncodingTransferSyntaxes: [String] = [
        TransferSyntax.jpegXLLossless.uid,    // 1.2.840.10008.1.2.4.110
        TransferSyntax.jpegXL.uid             // 1.2.840.10008.1.2.4.112 (lossy)
    ]

    private enum SyntaxRestriction: Equatable, Sendable {
        case any
        case lossless
        case recompression
        case general
        case unsupported
    }

    private let explicitDecodingTransferSyntaxUID: String?
    private let explicitEncodingTransferSyntaxUID: String?
    private let syntaxRestriction: SyntaxRestriction
    private let decodingLimits: PixelDecodeLimits

    /// The transfer syntax this instance is decoding, when known (set per-UID at registry
    /// wiring time).
    public var decodingTransferSyntaxUID: String? {
        if let explicitDecodingTransferSyntaxUID {
            return explicitDecodingTransferSyntaxUID
        }
        switch syntaxRestriction {
        case .any, .unsupported: return nil
        case .lossless: return TransferSyntax.jpegXLLossless.uid
        case .recompression: return TransferSyntax.jpegXLRecompression.uid
        case .general: return TransferSyntax.jpegXL.uid
        }
    }

    /// The transfer syntax this instance encodes *to* (…4.110 Lossless or …4.112
    /// general/lossy), set per-UID at registry wiring time. Defaults to Lossless so a bare
    /// `JXLCodec()` encodes bit-exactly.
    public var encodingTransferSyntaxUID: String {
        explicitEncodingTransferSyntaxUID ?? TransferSyntax.jpegXLLossless.uid
    }

    public init(decodingTransferSyntaxUID: String? = nil,
                encodingTransferSyntaxUID: String = TransferSyntax.jpegXLLossless.uid,
                decodingLimits: PixelDecodeLimits = .default) {
        self.explicitDecodingTransferSyntaxUID = decodingTransferSyntaxUID
        self.explicitEncodingTransferSyntaxUID = encodingTransferSyntaxUID
        switch decodingTransferSyntaxUID {
        case nil: self.syntaxRestriction = .any
        case TransferSyntax.jpegXLLossless.uid: self.syntaxRestriction = .lossless
        case TransferSyntax.jpegXLRecompression.uid: self.syntaxRestriction = .recompression
        case TransferSyntax.jpegXL.uid: self.syntaxRestriction = .general
        default: self.syntaxRestriction = .unsupported
        }
        self.decodingLimits = decodingLimits
    }

    /// Create a JPEG XL decoder from finite scalar policy without initializing UID Strings.
    public init(decodingSyntax: DecodingSyntax, decodingLimits: PixelDecodeLimits = .init()) {
        self.explicitDecodingTransferSyntaxUID = nil
        self.explicitEncodingTransferSyntaxUID = nil
        switch decodingSyntax {
        case .any: self.syntaxRestriction = .any
        case .lossless: self.syntaxRestriction = .lossless
        case .recompression: self.syntaxRestriction = .recompression
        case .general: self.syntaxRestriction = .general
        }
        self.decodingLimits = decodingLimits
    }

    /// Whether the target UID *forces* reversible encoding. True for JPEG XL Lossless
    /// (…4.110) and any unexpected UID (fail-safe bit-exact).
    private var encodesLossless: Bool {
        encodingTransferSyntaxUID != TransferSyntax.jpegXL.uid
    }

    // MARK: - Encoding capability

    /// Whether this encoder can compress the given pixel data: 8-bit unsigned or
    /// 16-bit (unsigned, or signed via two's-complement offset-binary level shift)
    /// greyscale or RGB within `SwiftJXL`'s `16384 x 16384` dimension bound.
    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
            return false
        }
        guard descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3 else {
            return false
        }
        guard (1...16384).contains(descriptor.columns),
              (1...16384).contains(descriptor.rows) else {
            return false
        }
        if descriptor.isSigned && descriptor.bitsAllocated != 16 {
            return false
        }
        return true
    }

    // MARK: - Encoding

    public func encodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor,
                            frameIndex: Int, configuration: CompressionConfiguration) throws -> Data {
        let spp = descriptor.samplesPerPixel
        guard spp == 1 || spp == 3 else {
            throw DICOMError.parsingFailed("SwiftJXL: unsupported samplesPerPixel \(spp)")
        }
        let width = descriptor.columns
        let height = descriptor.rows
        guard (1...16384).contains(width), (1...16384).contains(height) else {
            throw DICOMError.parsingFailed("SwiftJXL: invalid frame dimensions \(width)x\(height)")
        }
        let storageBits: Int
        if descriptor.bitsAllocated <= 8 {
            guard !descriptor.isSigned else {
                throw DICOMError.parsingFailed(
                    "SwiftJXL: signed 8-bit pixel data not supported (no signed 8-bit JPEG XL sample type)"
                )
            }
            storageBits = 8
        } else {
            storageBits = 16
        }
        let bps = storageBits / 8
        let interleaved = interleavedFrameBytes(from: frameData, descriptor: descriptor)

        // …4.110 forces lossless. The general …4.112 UID honours `configuration.preferLossless`
        // (we deliberately do not flip to lossless on `quality.isLossless`, so lossy-intent
        // encodes at maximum quality remain VarDCT codestreams with truthful lossy provenance).
        // Frames exceeding VarDCT's 4096-axis / 4-megapixel bound transparently fall back to
        // lossless Modular, which remains a conformant …4.112 codestream.
        let (pixels, pixOver) = width.multipliedReportingOverflow(by: height)
        guard !pixOver, pixels > 0 else {
            throw DICOMError.parsingFailed("SwiftJXL: frame dimensions overflow")
        }
        let fitsVarDCT = width <= 4096 && height <= 4096 && pixels <= (4 * 1024 * 1024)
        let useLossless = encodesLossless || configuration.preferLossless || !fitsVarDCT

        do {
            let limits = try Self.makeEncodeResourceLimits(
                width: width,
                height: height,
                spp: spp,
                bps: bps
            )
            let image = try Self.buildEncodeImage(
                interleaved: interleaved,
                width: width,
                height: height,
                spp: spp,
                storageBits: storageBits,
                isSigned16: descriptor.isSigned && storageBits == 16,
                limits: limits
            )
            let encoderConfig = try Self.makeEncoderConfiguration(
                useLossless: useLossless,
                quality: configuration.quality
            )
            let encoder = try SwiftJXL.Encoder(configuration: encoderConfig)
            let encodeOptions = SwiftJXL.EncodeOptions(
                resourceLimits: limits,
                copyPolicy: .requireSharedStorage,
                metadataPolicy: .discardAncillary
            )
            let encoded = try CompressionSuiteSyncBridge.run(
                deadlineSeconds: 30.0,
                joinGraceSeconds: 1.0,
                codecName: "SwiftJXL"
            ) {
                try await encoder.encode(image, options: encodeOptions)
            }
            guard encoded.report.copyEvents.isEmpty else {
                throw DICOMError.parsingFailed("SwiftJXL encode violated requireSharedStorage copy policy")
            }
            if useLossless {
                guard encoded.report.fidelity == .exactSamples else {
                    throw DICOMError.parsingFailed(
                        "SwiftJXL lossless encode reported non-exact fidelity: \(encoded.report.fidelity)"
                    )
                }
            }
            return encoded.data
        } catch let error as CancellationError {
            throw error
        } catch let error as DICOMError {
            throw error
        } catch let error as SwiftJXL.CodecError {
            if error.category == .resourceLimitExceeded {
                throw DICOMError.limitExceeded("SwiftJXL encode exceeded resource limits: \(error.message)")
            }
            throw DICOMError.parsingFailed("SwiftJXL encode failed: \(error.message)")
        } catch {
            throw DICOMError.parsingFailed("SwiftJXL encode failed: \(error)")
        }
    }

    // MARK: - Encoding configuration & helpers

    /// Maps a DICOM ``CompressionQuality`` (0.0–1.0) to a JPEG XL quality score (1–100,
    /// where 90 is visually lossless and 100 is highest quality). Mirrors
    /// ``JLICodec/jpegQuality(from:)`` so the `--quality` knob behaves consistently.
    static func jxlQuality(from quality: CompressionQuality) -> Float {
        Float(max(1.0, min(100.0, quality.value * 100.0)))
    }

    /// Maps a JPEG XL quality score (`1...100`) to a positive finite VarDCT Butteraugli-style
    /// distance (`> 0`). Even at `q == 100`, lossy intent retains a small positive distance
    /// (`0.1`) so `.112` lossy requests emit a genuine VarDCT codestream.
    static func varDCTDistance(from quality: CompressionQuality) -> Float {
        let q = jxlQuality(from: quality)
        if q >= 30.0 {
            return max(0.05, 0.1 + (100.0 - q) * 0.09)
        }
        let scaled = 6.4 + Float(pow(2.5, Double((30.0 - q) / 5.0))) * 0.25
        return min(25.0, max(0.05, scaled))
    }

    private static func makeEncoderConfiguration(
        useLossless: Bool,
        quality: CompressionQuality
    ) throws -> SwiftJXL.EncoderConfiguration {
        if useLossless {
            return .default
        }
        let varDCT = try SwiftJXL.VarDCTEncodingOptions(distance: varDCTDistance(from: quality))
        return try SwiftJXL.EncoderConfiguration(
            mode: .lossy,
            codecOptions: SwiftJXL.CodecOptions(varDCT: varDCT, container: .codestream)
        )
    }

    private static func makeEncodeResourceLimits(
        width: Int,
        height: Int,
        spp: Int,
        bps: Int
    ) throws -> SwiftJXL.ResourceLimits {
        let (pixels, pOver) = width.multipliedReportingOverflow(by: height)
        let (samples, sOver) = pixels.multipliedReportingOverflow(by: spp)
        let (rawBytes, bOver) = samples.multipliedReportingOverflow(by: bps)
        guard !pOver, !sOver, !bOver, pixels > 0, rawBytes > 0 else {
            throw DICOMError.parsingFailed("SwiftJXL: frame geometry overflows addressable range")
        }
        let maxDecoded = max(512 * 1024 * 1024, rawBytes * 4)
        let maxCompressed = max(256 * 1024 * 1024, rawBytes * 2)
        return try SwiftJXL.ResourceLimits(
            maximumCompressedBytes: maxCompressed,
            maximumDecodedBytes: maxDecoded,
            maximumWorkspaceBytes: Int.max / 4,
            maximumPixels: max(64_000_000, pixels),
            maximumDimension: max(1_000_000, max(width, height)),
            deadlineSeconds: 30.0,
            maximumMemoryBytes: Int.max
        )
    }

    private static func buildEncodeImage(
        interleaved: [UInt8],
        width: Int,
        height: Int,
        spp: Int,
        storageBits: Int,
        isSigned16: Bool,
        limits: SwiftJXL.ResourceLimits
    ) throws -> SwiftJXL.Image {
        let bps = storageBits / 8
        let pixelStride = spp * bps
        let rowBytes = width * pixelStride
        let byteCount = rowBytes * height
        guard interleaved.count >= byteCount else {
            throw DICOMError.parsingFailed(
                "SwiftJXL: input frame truncated (expected \(byteCount) bytes, got \(interleaved.count))"
            )
        }
        let plane = try SwiftJXL.PlaneDescriptor(
            width: width,
            height: height,
            components: Array(0..<spp),
            offset: 0,
            sampleStride: bps,
            pixelStride: pixelStride,
            rowBytes: rowBytes,
            byteCount: byteCount
        )
        // Encode the full 8- or 16-bit cell width so unsigned sub-16-bit frames (e.g. 12-in-16)
        // interoperate with external PNM/PGM decoders (`djxl` MAXVAL 65535 without rescaling)
        // and signed 16-bit CT words preserve sign-extended upper bits bit-for-bit.
        let descriptor = try SwiftJXL.ImageDescriptor(
            width: width,
            height: height,
            sampleType: .unsignedInteger,
            storageBits: storageBits,
            meaningfulBits: storageBits,
            byteOrder: .littleEndian,
            components: spp == 1 ? [.grey] : [.red, .green, .blue],
            colour: spp == 1 ? .greyscale : .rgb,
            alpha: .absent,
            planes: [plane],
            iccProfile: nil,
            limits: limits
        )
        let destination = try SwiftJXL.ImageDestination.allocate(
            descriptor: descriptor,
            limits: limits
        )
        return try destination.write { dstRaw in
            guard let dst = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                  dstRaw.count >= byteCount else {
                throw DICOMError.parsingFailed("SwiftJXL: destination buffer unavailable")
            }
            if isSigned16 {
                // Shift little-endian Int16 two's-complement words to unsigned offset-binary
                // (`word ^ 0x8000`, i.e. flip bit 7 of the high byte).
                let sampleCount = byteCount / 2
                interleaved.withUnsafeBufferPointer { srcBuf in
                    guard let src = srcBuf.baseAddress else { return }
                    for idx in 0..<sampleCount {
                        dst[idx * 2] = src[idx * 2]
                        dst[idx * 2 + 1] = src[idx * 2 + 1] ^ 0x80
                    }
                }
            } else {
                interleaved.withUnsafeBufferPointer { srcBuf in
                    if let src = srcBuf.baseAddress {
                        dst.update(from: src, count: byteCount)
                    }
                }
            }
        }
    }

    // MARK: - Zero-Copy Pre-Admission Header & SizeHeader Inspection

    private struct ValidatedJXLStream {
        let isJPEGRecompression: Bool
        let bitsPerSample: Int
        let iccProfile: Data?
        let trimmedLength: Int
    }

    private struct ZeroCopyJXLEnvelope {
        let xsize: UInt32
        let ysize: UInt32
        let hasJBRD: Bool
    }

    /// Parses the JXL naked codestream or ISOBMFF container box structure and `SizeHeader`
    /// (`ISO/IEC 18181-1 §C.3.2` / `18181-2`) directly from a borrowed byte pointer with
    /// zero heap allocations.
    private static func parseZeroCopyEnvelope(
        base: UnsafePointer<UInt8>,
        length: Int
    ) -> ZeroCopyJXLEnvelope? {
        guard length >= 2 else { return nil }

        // Case 1: Naked codestream (`FF 0A`).
        if base[0] == 0xFF && base[1] == 0x0A {
            guard let dims = parseSizeHeader(codestreamAfterSig: base.advanced(by: 2), count: length - 2) else {
                return nil
            }
            return ZeroCopyJXLEnvelope(xsize: dims.xsize, ysize: dims.ysize, hasJBRD: false)
        }

        // Case 2: ISOBMFF container (`00 00 00 0C 4A 58 4C 20 0D 0A 87 0A`).
        let sig: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
            0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A
        )
        guard length >= 12,
              base[0] == sig.0, base[1] == sig.1, base[2] == sig.2, base[3] == sig.3,
              base[4] == sig.4, base[5] == sig.5, base[6] == sig.6, base[7] == sig.7,
              base[8] == sig.8, base[9] == sig.9, base[10] == sig.10, base[11] == sig.11 else {
            return nil
        }

        func readU32BE(_ p: Int) -> UInt32 {
            (UInt32(base[p]) << 24) | (UInt32(base[p + 1]) << 16)
                | (UInt32(base[p + 2]) << 8) | UInt32(base[p + 3])
        }
        func readU64BE(_ p: Int) -> UInt64 {
            var v: UInt64 = 0
            for i in 0..<8 { v = (v << 8) | UInt64(base[p + i]) }
            return v
        }
        func isBoxType(_ p: Int, _ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Bool {
            base[p] == a && base[p + 1] == b && base[p + 2] == c && base[p + 3] == d
        }

        var cursor = 12
        var boxCount = 0
        var ftypCount = 0
        var firstWasFTYP = false
        var hasJBRD = false
        var jxlcRange: Range<Int>?
        var sawJXLP = false

        while cursor < length {
            guard cursor + 8 <= length else { return nil }
            let sizeRaw = readU32BE(cursor)
            let typeOffset = cursor + 4
            for k in 0..<4 {
                let ch = base[typeOffset + k]
                guard ch >= 0x20 && ch <= 0x7E else { return nil }
            }
            let payloadStart: Int
            let boxEnd: Int
            switch sizeRaw {
            case 0:
                payloadStart = cursor + 8
                boxEnd = length
            case 1:
                guard cursor + 16 <= length else { return nil }
                let extSize = readU64BE(cursor + 8)
                guard extSize >= 16, extSize <= UInt64(length - cursor) else { return nil }
                payloadStart = cursor + 16
                boxEnd = cursor + Int(extSize)
            default:
                guard sizeRaw >= 8, UInt64(sizeRaw) <= UInt64(length - cursor) else { return nil }
                payloadStart = cursor + 8
                boxEnd = cursor + Int(sizeRaw)
            }
            boxCount += 1
            guard boxCount <= 4096 else { return nil }

            // 'ftyp' = 0x66 0x74 0x79 0x70
            if isBoxType(typeOffset, 0x66, 0x74, 0x79, 0x70) {
                if boxCount == 1 { firstWasFTYP = true }
                ftypCount += 1
            } else if isBoxType(typeOffset, 0x6A, 0x62, 0x72, 0x64) {
                // 'jbrd' = 0x6A 0x62 0x72 0x64
                hasJBRD = true
            } else if isBoxType(typeOffset, 0x6A, 0x78, 0x6C, 0x63) {
                // 'jxlc' = 0x6A 0x78 0x6C 0x63
                guard jxlcRange == nil && !sawJXLP else { return nil }
                jxlcRange = payloadStart..<boxEnd
            } else if isBoxType(typeOffset, 0x6A, 0x78, 0x6C, 0x70) {
                // 'jxlp' = 0x6A 0x78 0x6C 0x70
                guard jxlcRange == nil, boxEnd - payloadStart >= 4 else { return nil }
                sawJXLP = true
            }
            cursor = boxEnd
        }

        guard firstWasFTYP, ftypCount == 1 else { return nil }

        if let range = jxlcRange {
            guard range.count >= 2,
                  base[range.lowerBound] == 0xFF,
                  base[range.lowerBound + 1] == 0x0A,
                  let dims = parseSizeHeader(
                      codestreamAfterSig: base.advanced(by: range.lowerBound + 2),
                      count: range.count - 2
                  ) else {
                return nil
            }
            return ZeroCopyJXLEnvelope(xsize: dims.xsize, ysize: dims.ysize, hasJBRD: hasJBRD)
        }

        guard sawJXLP else { return nil }
        // Gather the first 16 bytes of the concatenated partial codestream (`jxlp` seq 0, 1, ...)
        // into a fixed-size stack tuple (`SizeHeader` requires at most 11 bytes including `FF 0A`).
        var head: (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        ) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        var headCount = 0
        var nextSeq: UInt32 = 0
        var reachedLast = false

        while headCount < 16 && !reachedLast {
            var foundSeq = false
            var scan = 12
            while scan < length {
                let sizeRaw = readU32BE(scan)
                let typeOffset = scan + 4
                let payloadStart: Int
                let boxEnd: Int
                if sizeRaw == 0 {
                    payloadStart = scan + 8; boxEnd = length
                } else if sizeRaw == 1 {
                    payloadStart = scan + 16; boxEnd = scan + Int(readU64BE(scan + 8))
                } else {
                    payloadStart = scan + 8; boxEnd = scan + Int(sizeRaw)
                }
                if isBoxType(typeOffset, 0x6A, 0x78, 0x6C, 0x70) {
                    let rawSeq = readU32BE(payloadStart)
                    if (rawSeq & 0x7FFF_FFFF) == nextSeq {
                        foundSeq = true
                        reachedLast = (rawSeq & 0x8000_0000) != 0
                        let chunkStart = payloadStart + 4
                        var idx = chunkStart
                        withUnsafeMutableBytes(of: &head) { headBuf in
                            while idx < boxEnd && headCount < 16 {
                                headBuf[headCount] = base[idx]
                                headCount += 1
                                idx += 1
                            }
                        }
                        break
                    }
                }
                scan = boxEnd
            }
            if !foundSeq { return nil }
            nextSeq &+= 1
        }

        return withUnsafeBytes(of: &head) { headBuf -> ZeroCopyJXLEnvelope? in
            guard headCount >= 2,
                  let ptr = headBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                  ptr[0] == 0xFF, ptr[1] == 0x0A,
                  let dims = parseSizeHeader(codestreamAfterSig: ptr.advanced(by: 2), count: headCount - 2) else {
                return nil
            }
            return ZeroCopyJXLEnvelope(xsize: dims.xsize, ysize: dims.ysize, hasJBRD: hasJBRD)
        }
    }

    /// Parses ISO/IEC 18181-1 §C.3.2 `SizeHeader` (LSB-first bit stream positioned right after `FF 0A`).
    private static func parseSizeHeader(
        codestreamAfterSig ptr: UnsafePointer<UInt8>,
        count: Int
    ) -> (xsize: UInt32, ysize: UInt32)? {
        let totalBits = count * 8
        var bitPos = 0

        func readBits(_ n: Int) -> UInt32? {
            guard n >= 0, n <= 32, bitPos + n <= totalBits else { return nil }
            var result: UInt32 = 0
            for i in 0..<n {
                let byteIdx = (bitPos + i) >> 3
                let bitIdx = (bitPos + i) & 7
                let bit = (UInt32(ptr[byteIdx]) >> UInt32(bitIdx)) & 1
                result |= (bit << UInt32(i))
            }
            bitPos += n
            return result
        }

        func readSizeField() -> UInt32? {
            guard let selector = readBits(2) else { return nil }
            let extraBits: Int
            switch selector {
            case 0: extraBits = 9
            case 1: extraBits = 13
            case 2: extraBits = 18
            case 3: extraBits = 30
            default: return nil
            }
            guard let extra = readBits(extraBits) else { return nil }
            return 1 &+ extra
        }

        func aspectXsize(ysize: UInt32, ratio: UInt32) -> UInt32? {
            let num: UInt64
            let den: UInt64
            switch ratio {
            case 1: num = 1; den = 1
            case 2: num = 12; den = 10
            case 3: num = 4; den = 3
            case 4: num = 3; den = 2
            case 5: num = 16; den = 9
            case 6: num = 5; den = 4
            case 7: num = 2; den = 1
            default: return nil
            }
            return UInt32((UInt64(ysize) &* num) / den)
        }

        guard let smallBit = readBits(1) else { return nil }
        let ysize: UInt32
        let xsize: UInt32
        if smallBit == 1 {
            guard let yDiv8 = readBits(5), let ratio = readBits(3) else { return nil }
            ysize = (yDiv8 + 1) &* 8
            if ratio == 0 {
                guard let xDiv8 = readBits(5) else { return nil }
                xsize = (xDiv8 + 1) &* 8
            } else {
                guard let derived = aspectXsize(ysize: ysize, ratio: ratio) else { return nil }
                xsize = derived
            }
        } else {
            guard let y = readSizeField(), let ratio = readBits(3) else { return nil }
            ysize = y
            if ratio == 0 {
                guard let x = readSizeField() else { return nil }
                xsize = x
            } else {
                guard let derived = aspectXsize(ysize: ysize, ratio: ratio) else { return nil }
                xsize = derived
            }
        }
        guard xsize > 0, ysize > 0 else { return nil }
        return (xsize, ysize)
    }

    private func inspectAndValidateJXLOutcome(
        base: UnsafePointer<UInt8>,
        count: Int,
        descriptor: PixelDataDescriptor
    ) -> Result<ValidatedJXLStream, DICOMManagedFailure> {
        guard syntaxRestriction != .unsupported else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 500))
        }
        guard count > 0 else {
            return .failure(DICOMManagedFailure(.malformed, 502))
        }

        let envelope: ZeroCopyJXLEnvelope
        var resolvedLength: Int
        if let parsed = Self.parseZeroCopyEnvelope(base: base, length: count) {
            envelope = parsed
            resolvedLength = count
        } else if count >= 2, count % 2 == 0, base[count - 1] == 0,
                  let trimmed = Self.parseZeroCopyEnvelope(base: base, length: count - 1) {
            envelope = trimmed
            resolvedLength = count - 1
        } else {
            return .failure(DICOMManagedFailure(.malformed, 502))
        }

        // Enforce codestream dimensions against descriptor BEFORE any pixel or jbrd allocation.
        guard Int(envelope.xsize) == descriptor.columns,
              Int(envelope.ysize) == descriptor.rows else {
            return .failure(DICOMManagedFailure(.codecResultMismatch, 506))
        }

        if syntaxRestriction == .recompression {
            guard envelope.hasJBRD else {
                return .failure(DICOMManagedFailure(.codecFailure, 503, domain: 0x0500))
            }
            return .success(ValidatedJXLStream(
                isJPEGRecompression: true,
                bitsPerSample: descriptor.bitsStored,
                iccProfile: nil,
                trimmedLength: resolvedLength
            ))
        }
        if (syntaxRestriction == .any || syntaxRestriction == .general) && envelope.hasJBRD {
            return .success(ValidatedJXLStream(
                isJPEGRecompression: true,
                bitsPerSample: descriptor.bitsStored,
                iccProfile: nil,
                trimmedLength: resolvedLength
            ))
        }
        if syntaxRestriction == .lossless && envelope.hasJBRD {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 508))
        }

        // Non-jbrd pixel codestream: inspect header via SwiftJXL.Decoder using a non-copying view.
        // Naked codestreams (`FF 0A ...`) pass `parseZeroCopyEnvelope` even when an odd-length
        // fragment has a DICOM even-length `0x00` pad byte appended at the end (PS3.5 §A.4);
        // retry `inspect` with `count - 1` when that trailing pad byte causes framing rejection.
        func inspectView(length: Int) throws -> SwiftJXL.ImageInfo {
            let view = Data(
                bytesNoCopy: UnsafeMutableRawPointer(mutating: base),
                count: length,
                deallocator: .none
            )
            let inspectLimits = try makeDecodeResourceLimits(
                encodedByteCount: length,
                width: descriptor.columns,
                height: descriptor.rows,
                spp: max(1, descriptor.samplesPerPixel),
                bps: 2
            )
            let decoder = try SwiftJXL.Decoder()
            let options = SwiftJXL.DecodeOptions(
                resourceLimits: inspectLimits,
                copyPolicy: .requireSharedStorage,
                metadataPolicy: .discardAncillary
            )
            return try decoder.inspect(view, options: options)
        }

        let info: SwiftJXL.ImageInfo
        do {
            info = try inspectView(length: resolvedLength)
        } catch let error as SwiftJXL.CodecError {
            if error.category == .resourceLimitExceeded {
                return .failure(DICOMManagedFailure(.limitExceeded, 508))
            }
            if error.category == .unsupportedFeature || error.category == .unsupportedFormat {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 508))
            }
            if resolvedLength == count, count >= 3, count % 2 == 0, base[count - 1] == 0,
               let trimmedInfo = try? inspectView(length: count - 1) {
                info = trimmedInfo
                resolvedLength = count - 1
            } else {
                return .failure(DICOMManagedFailure(.malformed, 502))
            }
        } catch {
            return .failure(DICOMManagedFailure(.malformed, 502))
        }

        guard info.descriptor.sampleType == .unsignedInteger,
              info.descriptor.alpha == .absent else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 508))
        }

        let codestreamChannels = (info.descriptor.colour == .greyscale) ? 1 : 3
        guard codestreamChannels == descriptor.samplesPerPixel else {
            return .failure(DICOMManagedFailure(.codecResultMismatch, 506))
        }

        let b = info.descriptor.meaningfulBits
        guard b == descriptor.bitsStored || b == descriptor.bitsAllocated else {
            return .failure(DICOMManagedFailure(.codecResultMismatch, 509))
        }

        return .success(ValidatedJXLStream(
            isJPEGRecompression: false,
            bitsPerSample: b,
            iccProfile: info.descriptor.iccProfile,
            trimmedLength: resolvedLength
        ))
    }

    private func makeDecodeResourceLimits(
        encodedByteCount: Int,
        width: Int,
        height: Int,
        spp: Int,
        bps: Int
    ) throws -> SwiftJXL.ResourceLimits {
        let (pixels, pOver) = width.multipliedReportingOverflow(by: height)
        let (samples, sOver) = pixels.multipliedReportingOverflow(by: max(1, spp))
        let (rawBytes, bOver) = samples.multipliedReportingOverflow(by: max(1, bps))
        let (quadRaw, qOver) = rawBytes.multipliedReportingOverflow(by: 4)
        guard !pOver, !sOver, !bOver, !qOver, pixels > 0, rawBytes > 0 else {
            throw DICOMError.parsingFailed("JPEG XL header dimensions overflow addressable range")
        }
        // Note: SwiftJXL.Decoder.decode(_:into:options:) reserves destination bytes in both
        // `prepare` and `finish`, so `maximumDecodedBytes` must cover at least `2 * rawBytes`.
        let maxCompressed = max(1, max(decodingLimits.maximumEncodedBytes, encodedByteCount))
        let maxPixels = max(1, max(decodingLimits.maximumPixels, pixels))
        let maxDecoded = max(1, max(decodingLimits.maximumDecodedBytes * 2, quadRaw))
        let maxDim = max(16384, max(width, height))
        return try SwiftJXL.ResourceLimits(
            maximumCompressedBytes: maxCompressed,
            maximumDecodedBytes: maxDecoded,
            maximumWorkspaceBytes: Int.max / 4,
            maximumPixels: maxPixels,
            maximumDimension: maxDim,
            deadlineSeconds: 30.0,
            maximumMemoryBytes: Int.max
        )
    }

    private static func decodeWithSwiftJXL(
        _ cleanData: Data,
        width: Int,
        height: Int,
        spp: Int,
        bitsPerSample: Int,
        iccProfile: Data?,
        limits: SwiftJXL.ResourceLimits
    ) async throws -> SwiftJXL.DecodedImage {
        let storageBits = bitsPerSample <= 8 ? 8 : 16
        let bps = storageBits / 8
        let pixelStride = spp * bps
        let rowBytes = width * pixelStride
        let byteCount = rowBytes * height
        let plane = try SwiftJXL.PlaneDescriptor(
            width: width,
            height: height,
            components: Array(0..<spp),
            offset: 0,
            sampleStride: bps,
            pixelStride: pixelStride,
            rowBytes: rowBytes,
            byteCount: byteCount
        )
        let dstDescriptor = try SwiftJXL.ImageDescriptor(
            width: width,
            height: height,
            sampleType: .unsignedInteger,
            storageBits: storageBits,
            meaningfulBits: bitsPerSample,
            byteOrder: .littleEndian,
            components: spp == 1 ? [.grey] : [.red, .green, .blue],
            colour: spp == 1 ? .greyscale : .rgb,
            alpha: .absent,
            planes: [plane],
            iccProfile: iccProfile,
            limits: limits
        )
        let destination = try SwiftJXL.ImageDestination.allocate(
            descriptor: dstDescriptor,
            limits: limits
        )
        let decoder = try SwiftJXL.Decoder()
        let decodeOptions = SwiftJXL.DecodeOptions(
            resourceLimits: limits,
            copyPolicy: .requireSharedStorage,
            metadataPolicy: .discardAncillary
        )
        let decoded = try await decoder.decode(cleanData, into: destination, options: decodeOptions)
        guard decoded.report.copyEvents.isEmpty else {
            throw DICOMError.parsingFailed("SwiftJXL decode violated requireSharedStorage copy policy")
        }
        return decoded
    }

    // MARK: - Decoding

    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        guard !frameData.isEmpty else {
            throw DICOMError.parsingFailed("Empty JPEG XL data")
        }
        _ = try decodingLimits.validate(frameData, descriptor: descriptor, frameIndex: frameIndex)
        guard !(descriptor.isSigned && descriptor.bitsAllocated <= 8) else {
            throw DICOMError.parsingFailed("Signed 8-bit JPEG XL pixel data is not supported")
        }

        let validated: ValidatedJXLStream = try frameData.withUnsafeBytes { raw -> ValidatedJXLStream in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw DICOMError.parsingFailed("Empty JPEG XL data")
            }
            switch inspectAndValidateJXLOutcome(base: base, count: raw.count, descriptor: descriptor) {
            case .success(let stream):
                return stream
            case .failure(let failure):
                throw DICOMError.parsingFailed("JPEG XL header validation failed (\(failure.code), \(failure.operand1))")
            }
        }

        let cleanData = validated.trimmedLength == frameData.count
            ? Data(frameData)
            : Data(frameData.prefix(validated.trimmedLength))

        if validated.isJPEGRecompression {
            do {
                let reconstructedJPEG = try Self.reconstructJPEGFragment(cleanData)
                return try JLICodec(decodingLimits: decodingLimits)
                    .decodeFrame(reconstructedJPEG, descriptor: descriptor, frameIndex: frameIndex)
            } catch {
                if syntaxRestriction == .any {
                    // Fall through only if an unpinned instance encountered a non-reconstructible jbrd container.
                } else {
                    throw error
                }
            }
        }

        let b = validated.bitsPerSample
        let rawBytesPerSample = (b <= 8) ? 1 : 2
        let expectedRawBytes = descriptor.rows * descriptor.columns * descriptor.samplesPerPixel * rawBytesPerSample

        let decoded: SwiftJXL.DecodedImage
        do {
            let limits = try makeDecodeResourceLimits(
                encodedByteCount: cleanData.count,
                width: descriptor.columns,
                height: descriptor.rows,
                spp: descriptor.samplesPerPixel,
                bps: rawBytesPerSample
            )
            let width = descriptor.columns
            let height = descriptor.rows
            let spp = descriptor.samplesPerPixel
            let iccProfile = validated.iccProfile
            decoded = try CompressionSuiteSyncBridge.run(
                deadlineSeconds: 30.0,
                joinGraceSeconds: 1.0,
                codecName: "SwiftJXL"
            ) {
                try await Self.decodeWithSwiftJXL(
                    cleanData,
                    width: width,
                    height: height,
                    spp: spp,
                    bitsPerSample: b,
                    iccProfile: iccProfile,
                    limits: limits
                )
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as DICOMError {
            throw error
        } catch let error as SwiftJXL.CodecError {
            if error.category == .resourceLimitExceeded {
                throw DICOMError.limitExceeded("SwiftJXL decode exceeded resource limits: \(error.message)")
            }
            throw DICOMError.parsingFailed("SwiftJXL decode failed: \(error.message)")
        } catch {
            throw DICOMError.parsingFailed("SwiftJXL decode failed: \(error)")
        }

        if syntaxRestriction == .lossless {
            guard decoded.report.fidelity == .exactSamples else {
                throw DICOMError.parsingFailed("JPEG XL Lossless (.110) rejected lossy VarDCT codestream")
            }
        }

        guard decoded.image.descriptor.width == descriptor.columns,
              decoded.image.descriptor.height == descriptor.rows,
              decoded.image.descriptor.components.count == descriptor.samplesPerPixel,
              decoded.image.storage.byteCount == expectedRawBytes else {
            throw DICOMError.parsingFailed("SwiftJXL decoded frame geometry does not match DICOM descriptor")
        }

        if rawBytesPerSample == descriptor.bytesPerSample && !(descriptor.isSigned && b < 16) {
            let interleaved: [UInt8] = try decoded.image.storage.withUnsafeBytes { raw in
                guard raw.count >= expectedRawBytes,
                      let src = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    throw DICOMError.parsingFailed("SwiftJXL decoded storage unavailable")
                }
                var copy = Array(UnsafeBufferPointer(start: src, count: expectedRawBytes))
                if descriptor.isSigned && b == 16 {
                    let sampleCount = expectedRawBytes / 2
                    for idx in 0..<sampleCount {
                        copy[idx * 2 + 1] ^= 0x80
                    }
                }
                return copy
            }
            return dicomFrameBytes(fromInterleaved: interleaved, descriptor: descriptor)
        }

        var normalizedInterleaved = [UInt8](repeating: 0, count: descriptor.bytesPerFrame)
        let totalSamples = descriptor.rows * descriptor.columns * descriptor.samplesPerPixel
        let maxUnsigned = Int32(1) << b
        let signedMidpoint = Int32(1) << (b - 1)
        try decoded.image.storage.withUnsafeBytes { raw in
            guard raw.count >= expectedRawBytes,
                  let src = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw DICOMError.parsingFailed("SwiftJXL decoded storage unavailable")
            }
            try normalizedInterleaved.withUnsafeMutableBufferPointer { dstBuf in
                guard let dst = dstBuf.baseAddress else { return }
                for i in 0..<totalSamples {
                    let u: Int32
                    if b <= 8 {
                        u = Int32(src[i])
                    } else {
                        u = Int32(UInt16(src[i * 2]) | (UInt16(src[i * 2 + 1]) << 8))
                    }
                    guard u >= 0, u < maxUnsigned else {
                        throw DICOMError.parsingFailed("SwiftJXL sample exceeds \(b)-bit codestream precision")
                    }
                    let word: UInt16
                    if descriptor.isSigned {
                        let signed = Int16(truncatingIfNeeded: u - signedMidpoint)
                        word = UInt16(bitPattern: signed)
                    } else {
                        word = UInt16(truncatingIfNeeded: u)
                    }
                    dst[i * 2] = UInt8(word & 0xFF)
                    dst[i * 2 + 1] = UInt8(word >> 8)
                }
            }
        }
        return dicomFrameBytes(fromInterleaved: normalizedInterleaved, descriptor: descriptor)
    }

    public func decodePixelFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> DecodedPixelFrame {
        guard !frameData.isEmpty else {
            throw DICOMError.parsingFailed("Empty JPEG XL data")
        }
        _ = try decodingLimits.validate(frameData, descriptor: descriptor, frameIndex: frameIndex)

        let validated: ValidatedJXLStream = try frameData.withUnsafeBytes { raw -> ValidatedJXLStream in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw DICOMError.parsingFailed("Empty JPEG XL data")
            }
            switch inspectAndValidateJXLOutcome(base: base, count: raw.count, descriptor: descriptor) {
            case .success(let stream):
                return stream
            case .failure(let failure):
                throw DICOMError.parsingFailed("JPEG XL header validation failed (\(failure.code), \(failure.operand1))")
            }
        }

        if validated.isJPEGRecompression {
            let cleanData = validated.trimmedLength == frameData.count
                ? Data(frameData)
                : Data(frameData.prefix(validated.trimmedLength))
            if syntaxRestriction == .recompression {
                let reconstructedJPEG = try Self.reconstructJPEGFragment(cleanData)
                return try JLICodec(decodingLimits: decodingLimits).decodePixelFrame(
                    reconstructedJPEG, descriptor: descriptor, frameIndex: frameIndex
                )
            }
            if let reconstructedJPEG = try? Self.reconstructJPEGFragment(cleanData) {
                return try JLICodec(decodingLimits: decodingLimits).decodePixelFrame(
                    reconstructedJPEG, descriptor: descriptor, frameIndex: frameIndex
                )
            }
        }

        let decoded = try decodeFrame(frameData, descriptor: descriptor, frameIndex: frameIndex)
        return DecodedPixelFrame(
            data: decoded,
            descriptor: Self.outputDescriptor(for: descriptor),
            sourceFrameIndex: frameIndex
        )
    }

    // MARK: - Managed Budget-Accounted Decoding

    public func decodeManagedPixelFrame(
        _ frameData: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        budget: borrowing DICOMAllocationBudget,
        cancellation: DICOMCancellation = .never
    ) throws(DICOMManagedFailure) -> ManagedDecodedPixelFrame {
        try decodeManagedPixelFrameOutcome(
            frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, cancellation: cancellation
        ).get()
    }

    @available(*, noasync, message: "Invoke on the synchronous worker owning the execution reservation")
    public func decodeManagedPixelFrame(
        _ frameData: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        budget: borrowing DICOMAllocationBudget,
        execution: borrowing DICOMExecutionReservation,
        cancellation: DICOMCancellation = .never
    ) throws(DICOMManagedFailure) -> ManagedDecodedPixelFrame {
        try decodeManagedPixelFrameOutcome(
            frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, execution: execution, cancellation: cancellation
        ).get()
    }

    @available(*, noasync, message: "Qualified decoding must remain on its admitted synchronous worker")
    public func decodeManagedPixelFrameOutcome(
        _ frameData: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        budget: borrowing DICOMAllocationBudget,
        execution: borrowing DICOMExecutionReservation,
        cancellation: DICOMCancellation = .never
    ) -> DICOMManagedOutcome<ManagedDecodedPixelFrame> {
        switch execution.validateOutcome(budget: budget) {
        case .success: break
        case .failure(let failure): return .failure(DICOMManagedFailure(allocation: failure))
        }
        return decodeManagedPixelFrameOutcome(
            frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, cancellation: cancellation
        )
    }

    public func decodeManagedPixelFrameOutcome(
        _ frameData: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        budget: borrowing DICOMAllocationBudget,
        cancellation: DICOMCancellation = .never
    ) -> DICOMManagedOutcome<ManagedDecodedPixelFrame> {
        if let failure = cancellation.failure { return .failure(failure) }
        guard frameData.isOwned(by: budget) else {
            return .failure(DICOMManagedFailure(allocation: .budgetMismatch))
        }
        let expectedBytes: Int
        switch decodingLimits.validateManagedOutcome(
            encodedByteCount: frameData.count,
            descriptor: descriptor,
            frameIndex: frameIndex
        ) {
        case .success(let value): expectedBytes = value
        case .failure(let failure): return .failure(failure)
        }
        guard syntaxRestriction != .unsupported else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 500))
        }
        guard (descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3),
              (descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16),
              !(descriptor.isSigned && descriptor.bitsAllocated <= 8) else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 501))
        }

        return frameData.withBorrowedBytes { encoded -> DICOMManagedOutcome<ManagedDecodedPixelFrame> in
            guard let encodedBase = encoded.baseAddress?.assumingMemoryBound(to: UInt8.self),
                  encoded.count > 0 else {
                return .failure(DICOMManagedFailure(.malformed, 502))
            }

            // Zero-copy pre-admission header & dimension validation before allocating Data or planes.
            let validated: ValidatedJXLStream
            switch inspectAndValidateJXLOutcome(
                base: encodedBase, count: encoded.count, descriptor: descriptor
            ) {
            case .success(let stream): validated = stream
            case .failure(let failure): return .failure(failure)
            }

            let (stagingByteCount, stOverflow) = expectedBytes.addingReportingOverflow(validated.trimmedLength)
            guard !stOverflow, stagingByteCount > 0 else {
                return .failure(DICOMManagedFailure(.limitExceeded, 2))
            }

            if validated.isJPEGRecompression {
                let reconstructedJPEG: Data?
                do {
                    let jbrdStaging: DICOMByteBuffer
                    switch DICOMByteBuffer.admit(count: stagingByteCount, budget: budget, resource: .staging) {
                    case .success(let value): jbrdStaging = value
                    case .failure(let failure): return .failure(failure)
                    }
                    if let failure = cancellation.failure {
                        jbrdStaging.keepAlive()
                        return .failure(failure)
                    }

                    let cleanData = Data(bytes: encodedBase, count: validated.trimmedLength)
                    do {
                        reconstructedJPEG = try Self.reconstructJPEGFragment(cleanData)
                        jbrdStaging.keepAlive()
                    } catch {
                        jbrdStaging.keepAlive()
                        if syntaxRestriction == .recompression {
                            return .failure(DICOMManagedFailure(.codecFailure, 503, domain: 0x0500))
                        }
                        reconstructedJPEG = nil
                    }
                }
                if let reconstructedJPEG {
                    if syntaxRestriction == .recompression ||
                        (!reconstructedJPEG.isEmpty && reconstructedJPEG.count <= decodingLimits.maximumEncodedBytes) {
                        return decodeReconstructedJPEGOutcome(
                            reconstructedJPEG,
                            descriptor: descriptor,
                            frameIndex: frameIndex,
                            budget: budget,
                            cancellation: cancellation
                        )
                    }
                }
            }

            let b = validated.bitsPerSample
            let rawBytesPerSample = (b <= 8) ? 1 : 2
            let expectedRawBytes = descriptor.rows * descriptor.columns * descriptor.samplesPerPixel * rawBytesPerSample

            let decoded: SwiftJXL.DecodedImage
            do {
                let staging: DICOMByteBuffer
                switch DICOMByteBuffer.admit(count: stagingByteCount, budget: budget, resource: .staging) {
                case .success(let value): staging = value
                case .failure(let failure): return .failure(failure)
                }
                if let failure = cancellation.failure {
                    staging.keepAlive()
                    return .failure(failure)
                }

                let cleanData = Data(bytes: encodedBase, count: validated.trimmedLength)
                let limits: SwiftJXL.ResourceLimits
                do {
                    limits = try makeDecodeResourceLimits(
                        encodedByteCount: cleanData.count,
                        width: descriptor.columns,
                        height: descriptor.rows,
                        spp: descriptor.samplesPerPixel,
                        bps: rawBytesPerSample
                    )
                } catch {
                    staging.keepAlive()
                    return .failure(DICOMManagedFailure(.limitExceeded, 508, domain: 0x0500))
                }

                let width = descriptor.columns
                let height = descriptor.rows
                let spp = descriptor.samplesPerPixel
                let iccProfile = validated.iccProfile
                let bridgeOutcome = CompressionSuiteSyncBridge.runManaged(
                    deadlineSeconds: 30.0,
                    joinGraceSeconds: 1.0,
                    domain: 0x0500,
                    cancellation: cancellation
                ) {
                    try await Self.decodeWithSwiftJXL(
                        cleanData,
                        width: width,
                        height: height,
                        spp: spp,
                        bitsPerSample: b,
                        iccProfile: iccProfile,
                        limits: limits
                    )
                }
                staging.keepAlive()
                switch bridgeOutcome {
                case .success(let value): decoded = value
                case .failure(let failure): return .failure(failure)
                }
            }

            if syntaxRestriction == .lossless && decoded.report.fidelity != .exactSamples {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 510))
            }

            guard decoded.image.descriptor.width == descriptor.columns,
                  decoded.image.descriptor.height == descriptor.rows,
                  decoded.image.descriptor.components.count == descriptor.samplesPerPixel,
                  decoded.image.storage.byteCount == expectedRawBytes else {
                return .failure(DICOMManagedFailure(.codecResultMismatch, 506))
            }

            let bytes: DICOMByteBuffer
            switch DICOMByteBuffer.admit(count: expectedBytes, budget: budget, resource: .decoded) {
            case .success(let value): bytes = value
            case .failure(let failure): return .failure(failure)
            }
            if let failure = cancellation.failure {
                bytes.keepAlive()
                return .failure(failure)
            }
            guard let dstBase = bytes.unsafeMutableBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                bytes.keepAlive()
                return .failure(DICOMManagedFailure(.codecResultMismatch, 507))
            }

            let spp = descriptor.samplesPerPixel
            let pixels = descriptor.rows * descriptor.columns
            let requiresSampleConversion = (rawBytesPerSample != descriptor.bytesPerSample) || (descriptor.isSigned && b < 16)
            let isSigned16 = descriptor.isSigned && (b == 16)

            let copyFailure: DICOMManagedFailure?
            do {
                copyFailure = try decoded.image.storage.withUnsafeBytes { raw -> DICOMManagedFailure? in
                    guard raw.count >= expectedRawBytes,
                          let src = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return DICOMManagedFailure(.codecResultMismatch, 507)
                    }
                    if !requiresSampleConversion {
                        if spp == 1 || descriptor.planarConfiguration == 0 {
                            if isSigned16 {
                                let sampleCount = expectedBytes / 2
                                for idx in 0..<sampleCount {
                                    if (idx & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                                    dstBase[idx * 2] = src[idx * 2]
                                    dstBase[idx * 2 + 1] = src[idx * 2 + 1] ^ 0x80
                                }
                            } else {
                                let chunk = 65_536
                                var offset = 0
                                while offset < expectedBytes {
                                    if let failure = cancellation.failure { return failure }
                                    let step = min(chunk, expectedBytes - offset)
                                    dstBase.advanced(by: offset).update(from: src.advanced(by: offset), count: step)
                                    offset += step
                                }
                            }
                        } else {
                            let bps = descriptor.bitsAllocated <= 8 ? 1 : 2
                            for p in 0..<pixels {
                                if (p & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                                for c in 0..<spp {
                                    let srcByte = (p * spp + c) * bps
                                    let dstByte = (c * pixels + p) * bps
                                    if isSigned16 {
                                        dstBase[dstByte] = src[srcByte]
                                        dstBase[dstByte + 1] = src[srcByte + 1] ^ 0x80
                                    } else {
                                        for byteOffset in 0..<bps {
                                            dstBase[dstByte + byteOffset] = src[srcByte + byteOffset]
                                        }
                                    }
                                }
                            }
                        }
                        return nil
                    }

                    let maxUnsigned = Int32(1) << b
                    let signedMidpoint = Int32(1) << (b - 1)
                    let planar = (spp > 1 && descriptor.planarConfiguration == 1)
                    for p in 0..<pixels {
                        if (p & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                        for c in 0..<spp {
                            let sampleIdx = p * spp + c
                            let u: Int32
                            if b <= 8 {
                                u = Int32(src[sampleIdx])
                            } else {
                                u = Int32(UInt16(src[sampleIdx * 2]) | (UInt16(src[sampleIdx * 2 + 1]) << 8))
                            }
                            guard u >= 0, u < maxUnsigned else {
                                return DICOMManagedFailure(.codecResultMismatch, 509)
                            }
                            let word: UInt16
                            if descriptor.isSigned {
                                let signed = Int16(truncatingIfNeeded: u - signedMidpoint)
                                word = UInt16(bitPattern: signed)
                            } else {
                                word = UInt16(truncatingIfNeeded: u)
                            }
                            let dstWordIndex = planar ? (c * pixels + p) : sampleIdx
                            dstBase[dstWordIndex * 2] = UInt8(word & 0xFF)
                            dstBase[dstWordIndex * 2 + 1] = UInt8(word >> 8)
                        }
                    }
                    return nil
                }
            } catch {
                bytes.keepAlive()
                return .failure(DICOMManagedFailure(.codecFailure, 507, domain: 0x0500))
            }

            bytes.keepAlive()
            if let copyFailure { return .failure(copyFailure) }

            if let failure = cancellation.failure {
                bytes.keepAlive()
                return .failure(failure)
            }
            return .success(ManagedDecodedPixelFrame(
                data: bytes,
                descriptor: Self.outputDescriptor(for: descriptor),
                sourceFrameIndex: frameIndex
            ))
        }
    }

    private func decodeReconstructedJPEGOutcome(
        _ reconstructedJPEG: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        budget: borrowing DICOMAllocationBudget,
        cancellation: DICOMCancellation
    ) -> DICOMManagedOutcome<ManagedDecodedPixelFrame> {
        guard !reconstructedJPEG.isEmpty,
              reconstructedJPEG.count <= decodingLimits.maximumEncodedBytes else {
            return .failure(DICOMManagedFailure(.limitExceeded, 504))
        }
        let jpegStaging: DICOMByteBuffer
        switch DICOMByteBuffer.admit(count: reconstructedJPEG.count, budget: budget, resource: .staging) {
        case .success(let value): jpegStaging = value
        case .failure(let failure): return .failure(failure)
        }
        let dst = jpegStaging.unsafeMutableBytes
        reconstructedJPEG.withUnsafeBytes { src in
            if let base = src.baseAddress {
                dst.copyMemory(from: UnsafeRawBufferPointer(start: base, count: reconstructedJPEG.count))
            }
        }
        jpegStaging.keepAlive()
        return JLICodec(decodingSyntax: .any, decodingLimits: decodingLimits)
            .decodeManagedPixelFrameOutcome(
                jpegStaging,
                descriptor: descriptor,
                frameIndex: frameIndex,
                budget: budget,
                cancellation: cancellation
            )
    }

    private static func outputDescriptor(for descriptor: PixelDataDescriptor) -> PixelDataDescriptor {
        guard descriptor.samplesPerPixel == 3,
              descriptor.photometricInterpretation == .xyb else {
            return descriptor
        }
        return PixelDataDescriptor(
            rows: descriptor.rows,
            columns: descriptor.columns,
            numberOfFrames: descriptor.numberOfFrames,
            bitsAllocated: descriptor.bitsAllocated,
            bitsStored: descriptor.bitsStored,
            highBit: descriptor.highBit,
            isSigned: descriptor.isSigned,
            samplesPerPixel: descriptor.samplesPerPixel,
            photometricInterpretation: .rgb,
            planarConfiguration: descriptor.planarConfiguration
        )
    }

    // MARK: - JPEG Recompression (TS …4.111 — bitstream level, not pixel level)

    private static func makeTranscodeOptions(inputByteCount: Int) throws -> SwiftJXL.TranscodeOptions {
        let maxCompressed = max(256 * 1024 * 1024, inputByteCount + 4 * 1024 * 1024)
        let limits = try SwiftJXL.ResourceLimits(
            maximumCompressedBytes: maxCompressed,
            maximumDecodedBytes: 512 * 1024 * 1024,
            maximumWorkspaceBytes: Int.max / 4,
            maximumPixels: 64_000_000,
            maximumDimension: 65_535,
            maximumMetadataBytes: 16 * 1024 * 1024,
            maximumICCBytes: 4 * 1024 * 1024,
            deadlineSeconds: 30.0,
            maximumMemoryBytes: Int.max
        )
        return SwiftJXL.TranscodeOptions(
            resourceLimits: limits,
            copyPolicy: .allowCopy,
            metadataPolicy: .preserve
        )
    }

    /// Forward JPEG recompression (DICOM transfer syntax 1.2.840.10008.1.2.4.111):
    /// losslessly wraps an existing JPEG bitstream in a JPEG XL ISOBMFF container
    /// (with the `jbrd` reconstruction box) from which the original JPEG can be
    /// recovered **byte-for-byte**.
    public static func recompressJPEGFragment(_ jpegBytes: Data) throws -> Data {
        let clean = trimmedToJPEGEOI(jpegBytes)
        do {
            let transcoder = try SwiftJXL.Transcoder()
            let options = try makeTranscodeOptions(inputByteCount: clean.count)
            let transcoded = try CompressionSuiteSyncBridge.run(
                deadlineSeconds: 30.0,
                joinGraceSeconds: 1.0,
                codecName: "SwiftJXL"
            ) {
                try await transcoder.transcode(clean, to: .jpegXL, options: options)
            }
            guard transcoded.report.fidelity == .originalBitstream else {
                throw DICOMError.parsingFailed(
                    "SwiftJXL JPEG recompression reported unexpected fidelity: \(transcoded.report.fidelity)"
                )
            }
            return transcoded.data
        } catch let error as CancellationError {
            throw error
        } catch let error as DICOMError {
            throw error
        } catch let error as SwiftJXL.CodecError {
            if error.category == .resourceLimitExceeded {
                throw DICOMError.limitExceeded("SwiftJXL JPEG recompression exceeded resource limits: \(error.message)")
            }
            throw DICOMError.parsingFailed("SwiftJXL JPEG recompression failed: \(error.message)")
        } catch {
            throw DICOMError.parsingFailed("SwiftJXL JPEG recompression failed: \(error)")
        }
    }

    /// Reverse JPEG recompression: reconstructs the **byte-identical** original JPEG
    /// bitstream from a JPEG XL recompression fragment (…4.111).
    public static func reconstructJPEGFragment(_ jxlBytes: Data) throws -> Data {
        func reverse(_ data: Data) throws -> Data {
            let transcoder = try SwiftJXL.Transcoder()
            let options = try makeTranscodeOptions(inputByteCount: data.count)
            let reconstructed = try CompressionSuiteSyncBridge.run(
                deadlineSeconds: 30.0,
                joinGraceSeconds: 1.0,
                codecName: "SwiftJXL"
            ) {
                try await transcoder.transcode(data, to: .jpeg, options: options)
            }
            guard reconstructed.report.fidelity == .originalBitstream else {
                throw DICOMError.parsingFailed(
                    "SwiftJXL JPEG reconstruction reported unexpected fidelity: \(reconstructed.report.fidelity)"
                )
            }
            return reconstructed.data
        }
        do {
            return try reverse(jxlBytes)
        } catch let error as CancellationError {
            throw error
        } catch {
            // Retry once with a single trailing DICOM pad byte removed — the SwiftJXL
            // container parser is strict about trailing bytes (mirrors `decodeFrame`).
            if jxlBytes.count % 2 == 0, jxlBytes.last == 0 {
                do {
                    return try reverse(Data(jxlBytes.dropLast()))
                } catch let cancel as CancellationError {
                    throw cancel
                } catch {
                    throw DICOMError.parsingFailed("SwiftJXL JPEG reconstruction failed: \(error)")
                }
            }
            throw DICOMError.parsingFailed("SwiftJXL JPEG reconstruction failed: \(error)")
        }
    }

    /// Trims any bytes trailing the final JPEG End-Of-Image marker (`FF D9`), removing
    /// a DICOM even-length pad byte so the JPEG bitstream handed to the recompressor is
    /// exactly the original image. A no-op when the fragment already ends at EOI.
    private static func trimmedToJPEGEOI(_ data: Data) -> Data {
        let bytes = Data(data)
        guard bytes.count >= 2 else { return bytes }
        var i = bytes.count - 2
        while i >= 0 {
            if bytes[i] == 0xFF, bytes[i + 1] == 0xD9 {
                return bytes.subdata(in: 0..<(i + 2))
            }
            i -= 1
        }
        return bytes
    }
}
