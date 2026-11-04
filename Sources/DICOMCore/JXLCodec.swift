import Foundation
import JXLSwift

/// JPEG XL codec backed by the JXLSwift pure-Swift package (ISO/IEC 18181).
///
/// Bridges DICOM pixel data to JXLSwift for the JPEG XL transfer syntaxes added
/// in Supplement 232 (DICOM 2024d). NEMA-verified: 2026a, checked 2026-09-24 — text-diffed
/// against PS3.6 2026a Table A-1 (the three UIDs) and PS3.5 2026a §10.19 / §A.4.12 (.110
/// lossless, .111 reversible JPEG transcoding, .112 any JPEG XL mode); see
/// ``TransferSyntax/jpegXL``. Encodes both **lossless** JPEG XL (Modular
/// mode, distance 0 → …4.110) and **lossy** JPEG XL (VarDCT, quality-driven
/// distance → …4.112), and decodes lossless (Modular), general/lossy (VarDCT),
/// and JPEG-recompressed JPEG XL back to pixels. The target transfer syntax
/// selects the encode mode (see ``encodingTransferSyntaxUID``). Also used by the
/// DICOMStudio codec bench to compare JXLSwift against other JPEG XL
/// implementations (libjxl `djxl`).
///
/// JXLSwift's lossy VarDCT encoder (v1.4.0) covers 8- or 16-bit grayscale,
/// grayscale+alpha, RGB and RGBA within its size limits; only inputs beyond the
/// writer's size cap transparently fall back to the lossless Modular path, so a
/// lossy (…4.112) encode always yields a valid JPEG XL codestream — which is
/// conformant, since the general JPEG XL syntax permits both lossy and lossless
/// bitstreams. Note a grayscale …4.112 encode is now a genuine lossy VarDCT encode
/// (earlier JXLSwift silently emitted lossless Modular for grayscale).
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
/// recompressed JXL is still a valid codestream — which is why …4.111 is listed in
/// ``supportedTransferSyntaxes`` but not in ``supportedEncodingTransferSyntaxes``.
///
/// Pixel bridging: JXLSwift's `ImageFrame.data` is channel-interleaved `[UInt8]`,
/// row-major, 16-bit samples little-endian — matching DICOM little-endian storage.
/// Signed 16-bit pixel data (Pixel Representation = 1, e.g. CT) maps to JXLSwift's
/// `PixelType.int16`, which level-shifts to unsigned offset-binary for the
/// codestream and un-shifts on decode via `JXLDecoder.decode(_:signedOutput:)`.
/// JPEG XL has no signed 8-bit sample type, so signed 8-bit is the one pixel
/// layout rejected here rather than silently mis-encoded.
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
    /// recompression, and general/lossy). A JPEG-recompressed JXL (…4.111) is a
    /// valid codestream, so the standard pixel decode below yields its pixels;
    /// byte-exact reconstruction of the *original JPEG* uses ``reconstructJPEGFragment(_:)``.
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.jpegXLLossless.uid,        // 1.2.840.10008.1.2.4.110
        TransferSyntax.jpegXLRecompression.uid,   // 1.2.840.10008.1.2.4.111
        TransferSyntax.jpegXL.uid                 // 1.2.840.10008.1.2.4.112
    ]

    /// JPEG XL transfer syntaxes this codec can produce *from pixels*: Lossless
    /// (…4.110, Modular) and general/lossy (…4.112, VarDCT — with a lossless Modular
    /// fallback for inputs VarDCT can't take). The target UID selects the mode via
    /// ``encodingTransferSyntaxUID``. JPEG Recompression (…4.111) is produced from a
    /// JPEG bitstream, not pixels, via ``recompressJPEGFragment(_:)`` — it is
    /// deliberately absent from this list.
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
    /// wiring time). It disambiguates the …4.111 JPEG-Recompression decode from the …4.110
    /// / …4.112 pixel decode: for a known …4.111 source a reconstruction failure is a hard
    /// error (we must not fall back to the VarDCT pixel path, which can desync the channel
    /// count from Samples per Pixel), and …4.110 / …4.112 skip the reconstruction probe
    /// entirely. `nil` (a bare `JXLCodec()`, e.g. in benches) auto-detects via the `jbrd`
    /// box and falls back to pixels — the legacy best-effort behaviour.
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
    /// general/lossy), set per-UID at registry wiring time. It selects the encode
    /// mode: …4.110 → lossless Modular (distance 0); …4.112 → lossy VarDCT at a
    /// quality-derived distance. Ignored when the instance is used as a decoder (the
    /// codestream drives the decoder). Defaults to Lossless so a bare `JXLCodec()`
    /// encodes bit-exactly (the bench / adapter-test contract).
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
    /// (…4.110) and any unexpected UID (fail-safe bit-exact). For the general …4.112 UID
    /// this is false, so the caller's intent (`preferLossless`) chooses lossless vs lossy —
    /// see ``encoderOptions(for:)``.
    private var encodesLossless: Bool {
        encodingTransferSyntaxUID != TransferSyntax.jpegXL.uid
    }

    // MARK: - Encoding capability

    /// Whether this encoder can compress the given pixel data: 8-bit unsigned or
    /// 16-bit (unsigned, or signed via JXLSwift's `int16` level shift) grayscale or
    /// RGB, for both the lossless (…4.110) and lossy (…4.112) targets. The gate is the
    /// same for both modes: JXLSwift's VarDCT encoder (v1.4.0) handles grayscale and
    /// RGB directly and only falls back to the lossless Modular path for inputs beyond
    /// its size cap — so a lossy encode of any accepted input still yields a valid JPEG
    /// XL codestream. Signed 8-bit is rejected because JPEG XL has no signed 8-bit
    /// sample type; signed 16-bit (e.g. CT, Pixel Representation = 1) is supported.
    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
            return false
        }
        guard descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3 else {
            return false
        }
        // Signed samples map to JXLSwift's 16-bit `int16` type; there is no signed
        // 8-bit JPEG XL sample type, so signed 8-bit is rejected.
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
            throw DICOMError.parsingFailed("JXLSwift: unsupported samplesPerPixel \(spp)")
        }
        guard descriptor.columns > 0, descriptor.rows > 0 else {
            throw DICOMError.parsingFailed("JXLSwift: invalid frame dimensions")
        }
        // 8-bit is always unsigned (JPEG XL has no signed 8-bit sample type); 16-bit
        // signed maps to `int16`, which JXLSwift level-shifts to unsigned offset-binary
        // for the codestream (recovered on decode via `decode(_:signedOutput:)`).
        let pixelType: PixelType
        if descriptor.bitsAllocated <= 8 {
            guard !descriptor.isSigned else {
                throw DICOMError.parsingFailed("JXLSwift: signed 8-bit pixel data not supported (no signed 8-bit JPEG XL sample type)")
            }
            pixelType = .uint8
        } else {
            pixelType = descriptor.isSigned ? .int16 : .uint16
        }
        let colorSpace: ColorSpace = spp == 1 ? .grayscale : .sRGB

        var frame = ImageFrame(width: descriptor.columns, height: descriptor.rows,
                               channels: spp, pixelType: pixelType,
                               colorSpace: colorSpace, alphaChannels: 0)
        frame.data = interleavedFrameBytes(from: frameData, descriptor: descriptor)

        do {
            return try JXLEncoder(options: encoderOptions(for: configuration)).encode(frame).data
        } catch {
            throw DICOMError.parsingFailed("JXLSwift encode failed: \(error)")
        }
    }

    // MARK: - Encoding configuration

    /// Builds the JXLSwift ``EncodingOptions`` for this instance's target syntax:
    /// …4.110 → lossless Modular (distance 0); …4.112 → lossy VarDCT at a distance
    /// derived from `configuration.quality`. As of JXLSwift 1.4.0 VarDCT handles
    /// grayscale as well as RGB, so a grayscale …4.112 request is a genuine lossy
    /// encode; only frames beyond VarDCT's size cap fall back to lossless Modular
    /// inside JXLSwift — still a valid, conformant general JPEG XL codestream.
    private func encoderOptions(for configuration: CompressionConfiguration) -> EncodingOptions {
        // …4.110 forces lossless. The general …4.112 UID may carry either, so the caller's
        // INTENT (preferLossless) decides — mirroring J2KSwiftCodec's `.both` branch. Note we
        // deliberately do NOT flip to lossless on `quality.isLossless`: a lossy-intent encode
        // at maximum quality must stay a (near-)lossy codestream so its Lossy Image Compression
        // provenance attributes are truthful (a `--quality maximum` lossy request otherwise
        // produced a bit-exact file falsely stamped 0028,2110="01").
        let lossless = encodesLossless || configuration.preferLossless
        if lossless {
            return .lossless
        }
        return EncodingOptions(mode: .lossy(quality: Self.jxlQuality(from: configuration.quality)),
                               effort: .squirrel)
    }

    /// Maps a DICOM ``CompressionQuality`` (0.0–1.0) to a JPEG XL quality score (1–100,
    /// where 90 is visually lossless and 100 is mathematically lossless). Mirrors
    /// ``JLICodec/jpegQuality(from:)`` so the `--quality` knob behaves consistently
    /// across the pure-Swift codecs.
    static func jxlQuality(from quality: CompressionQuality) -> Float {
        Float(max(1.0, min(100.0, quality.value * 100.0)))
    }

    // MARK: - Decoding

    private struct ValidatedJXLStream {
        let isJPEGRecompression: Bool
        let bitsPerSample: Int
        let trimmedLength: Int
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

        func tryInspect(length: Int) -> Result<(JXLInspection, Data), Error> {
            let view = Data(
                bytesNoCopy: UnsafeMutableRawPointer(mutating: base),
                count: length,
                deallocator: .none
            )
            do {
                let info = try JXLDecoder().inspect(view)
                return .success((info, view))
            } catch {
                return .failure(error)
            }
        }

        let inspection: JXLInspection
        let resolvedView: Data
        let resolvedLength: Int
        switch tryInspect(length: count) {
        case .success(let pair):
            inspection = pair.0
            resolvedView = pair.1
            resolvedLength = count
        case .failure:
            if count >= 2, count % 2 == 0, base[count - 1] == 0,
               case .success(let trimmedPair) = tryInspect(length: count - 1) {
                inspection = trimmedPair.0
                resolvedView = trimmedPair.1
                resolvedLength = count - 1
            } else {
                return .failure(DICOMManagedFailure(.malformed, 502))
            }
        }

        // Enforce codestream dimensions against descriptor BEFORE any pixel or jbrd allocation.
        guard Int(inspection.xsize) == descriptor.columns,
              Int(inspection.ysize) == descriptor.rows else {
            return .failure(DICOMManagedFailure(.codecResultMismatch, 506))
        }

        let hasJBRD = inspection.boxTypes.contains("jbrd")
        if syntaxRestriction == .recompression {
            guard hasJBRD else {
                return .failure(DICOMManagedFailure(.codecFailure, 503, domain: 0x0500))
            }
            return .success(ValidatedJXLStream(
                isJPEGRecompression: true,
                bitsPerSample: descriptor.bitsStored,
                trimmedLength: resolvedLength
            ))
        }
        if syntaxRestriction == .any && hasJBRD {
            return .success(ValidatedJXLStream(
                isJPEGRecompression: true,
                bitsPerSample: descriptor.bitsStored,
                trimmedLength: resolvedLength
            ))
        }
        if syntaxRestriction == .lossless && hasJBRD {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 508))
        }

        guard let metadata = inspection.metadata,
              !metadata.bitDepth.floatingPoint,
              metadata.extraChannels.isEmpty else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 508))
        }

        let codestreamChannels = (metadata.colorEncoding.colorSpace == .grayscale) ? 1 : 3
        guard codestreamChannels == descriptor.samplesPerPixel else {
            return .failure(DICOMManagedFailure(.codecResultMismatch, 506))
        }

        let b = Int(metadata.bitDepth.bitsPerSample)
        guard b == descriptor.bitsStored || b == descriptor.bitsAllocated else {
            return .failure(DICOMManagedFailure(.codecResultMismatch, 509))
        }

        if syntaxRestriction == .lossless {
            guard !metadata.xybEncoded else {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 510))
            }
            guard let frames = try? JXLDecoder().inspectFrames(resolvedView),
                  let firstFrame = frames.first,
                  firstFrame.encoding == .modular else {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 510))
            }
        }

        return .success(ValidatedJXLStream(
            isJPEGRecompression: false,
            bitsPerSample: b,
            trimmedLength: resolvedLength
        ))
    }

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
        let useJXLInt16Shift = descriptor.isSigned && (b == 16)
        let frame: ImageFrame
        do {
            frame = try JXLDecoder().decode(cleanData, signedOutput: useJXLInt16Shift)
        } catch {
            throw DICOMError.parsingFailed("JXLSwift decode failed: \(error)")
        }

        let rawBytesPerSample = (b <= 8) ? 1 : 2
        let expectedRawBytes = descriptor.rows * descriptor.columns * descriptor.samplesPerPixel * rawBytesPerSample
        guard frame.width == descriptor.columns,
              frame.height == descriptor.rows,
              frame.channels == descriptor.samplesPerPixel,
              frame.data.count == expectedRawBytes else {
            throw DICOMError.parsingFailed(
                "JXLSwift decoded frame (\(frame.width)x\(frame.height), \(frame.channels) ch, \(frame.data.count) B) does not match descriptor"
            )
        }

        if rawBytesPerSample == descriptor.bytesPerSample && !(descriptor.isSigned && b < 16) {
            return dicomFrameBytes(fromInterleaved: frame.data, descriptor: descriptor)
        }

        var normalizedInterleaved = [UInt8](repeating: 0, count: descriptor.bytesPerFrame)
        let totalSamples = descriptor.rows * descriptor.columns * descriptor.samplesPerPixel
        let maxUnsigned = Int32(1) << b
        let signedMidpoint = Int32(1) << (b - 1)
        try frame.data.withUnsafeBufferPointer { srcBuf in
            try normalizedInterleaved.withUnsafeMutableBufferPointer { dstBuf in
                let src = srcBuf.baseAddress!
                let dst = dstBuf.baseAddress!
                for i in 0..<totalSamples {
                    let u: Int32
                    if b <= 8 {
                        u = Int32(src[i])
                    } else {
                        u = Int32(UInt16(src[i * 2]) | (UInt16(src[i * 2 + 1]) << 8))
                    }
                    guard u >= 0, u < maxUnsigned else {
                        throw DICOMError.parsingFailed("JXLSwift sample exceeds \(b)-bit codestream precision")
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
            let useJXLInt16Shift = descriptor.isSigned && (b == 16)
            let decodedFrame: ImageFrame
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
                do {
                    decodedFrame = try JXLDecoder().decode(cleanData, signedOutput: useJXLInt16Shift)
                    staging.keepAlive()
                } catch {
                    staging.keepAlive()
                    return .failure(DICOMManagedFailure(.codecFailure, 505, domain: 0x0500))
                }
            }

            let rawBytesPerSample = (b <= 8) ? 1 : 2
            let expectedRawBytes = descriptor.rows * descriptor.columns * descriptor.samplesPerPixel * rawBytesPerSample
            guard decodedFrame.width == descriptor.columns,
                  decodedFrame.height == descriptor.rows,
                  decodedFrame.channels == descriptor.samplesPerPixel,
                  decodedFrame.data.count == expectedRawBytes else {
                return .failure(DICOMManagedFailure(.codecResultMismatch, 506))
            }

            let bytes: DICOMByteBuffer
            switch DICOMByteBuffer.admit(count: expectedBytes, budget: budget, resource: .decoded) {
            case .success(let value): bytes = value
            case .failure(let failure): return .failure(failure)
            }
            if let failure = cancellation.failure { return .failure(failure) }
            guard let dstBase = bytes.unsafeMutableBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return .failure(DICOMManagedFailure(.codecResultMismatch, 507))
            }

            let spp = descriptor.samplesPerPixel
            let pixels = descriptor.rows * descriptor.columns
            let requiresSampleConversion = (rawBytesPerSample != descriptor.bytesPerSample) || (descriptor.isSigned && b < 16)

            if !requiresSampleConversion {
                if spp == 1 || descriptor.planarConfiguration == 0 {
                    decodedFrame.data.withUnsafeBufferPointer { src in
                        if let base = src.baseAddress {
                            dstBase.update(from: base, count: expectedBytes)
                        }
                    }
                    bytes.keepAlive()
                } else {
                    let bps = descriptor.bitsAllocated <= 8 ? 1 : 2
                    for p in 0..<pixels {
                        if (p & 0xFFFF) == 0, let failure = cancellation.failure {
                            bytes.keepAlive()
                            return .failure(failure)
                        }
                        for c in 0..<spp {
                            let srcByte = (p * spp + c) * bps
                            let dstByte = (c * pixels + p) * bps
                            for byteOffset in 0..<bps {
                                dstBase[dstByte + byteOffset] = decodedFrame.data[srcByte + byteOffset]
                            }
                        }
                    }
                    bytes.keepAlive()
                }
            } else {
                let maxUnsigned = Int32(1) << b
                let signedMidpoint = Int32(1) << (b - 1)
                let planar = (spp > 1 && descriptor.planarConfiguration == 1)
                let convFailure: DICOMManagedFailure? = decodedFrame.data.withUnsafeBufferPointer { srcBuf in
                    guard let src = srcBuf.baseAddress else {
                        return DICOMManagedFailure(.codecResultMismatch, 507)
                    }
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
                bytes.keepAlive()
                if let convFailure { return .failure(convFailure) }
            }

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

    /// Forward JPEG recompression (DICOM transfer syntax 1.2.840.10008.1.2.4.111):
    /// losslessly wraps an existing JPEG bitstream in a JPEG XL ISOBMFF container
    /// (with the `jbrd` reconstruction box) from which the original JPEG can be
    /// recovered **byte-for-byte**.
    ///
    /// The input is the *compressed JPEG fragment* from a source file's encapsulated
    /// pixel data — not raw pixels — so this bypasses the pixel `ImageEncoder` path.
    /// Scope follows JXLSwift's `encodeLosslessJPEG`: baseline-DCT, 8-bit, 1- or
    /// 3-component JPEG (i.e. DICOM JPEG Baseline, …4.50). Any DICOM even-length pad
    /// byte after the JPEG End-Of-Image marker is trimmed first so the recompressor
    /// sees a clean bitstream.
    ///
    /// - Parameter jpegBytes: one encapsulated JPEG frame fragment.
    /// - Returns: the JPEG XL recompression bytes for that frame.
    /// - Throws: ``DICOMError/parsingFailed(_:)`` if the JPEG is outside the
    ///   supported recompression scope.
    public static func recompressJPEGFragment(_ jpegBytes: Data) throws -> Data {
        let clean = trimmedToJPEGEOI(jpegBytes)
        do {
            return try JXLEncoder().encodeLosslessJPEG(clean).data
        } catch {
            throw DICOMError.parsingFailed("JXLSwift JPEG recompression failed: \(error)")
        }
    }

    /// Reverse JPEG recompression: reconstructs the **byte-identical** original JPEG
    /// bitstream from a JPEG XL recompression fragment (…4.111). The symmetric mirror
    /// of ``recompressJPEGFragment(_:)`` — the round trip returns the source JPEG
    /// bit-for-bit (no generational loss).
    ///
    /// - Parameter jxlBytes: one encapsulated JPEG XL recompression frame fragment.
    /// - Returns: the reconstructed original JPEG frame bytes.
    /// - Throws: ``DICOMError/parsingFailed(_:)`` if the fragment carries no `jbrd`
    ///   reconstruction data (i.e. it is not a recompressed JPEG) or is otherwise
    ///   outside the supported reconstruction scope.
    public static func reconstructJPEGFragment(_ jxlBytes: Data) throws -> Data {
        func reverse(_ data: Data) throws -> Data {
            try JXLDecoder().decodeLosslessJPEG(data)
        }
        do {
            return try reverse(jxlBytes)
        } catch {
            // Retry once with a single trailing DICOM pad byte removed — the JXLSwift
            // container parser is strict about trailing bytes (mirrors `decodeFrame`).
            if jxlBytes.count % 2 == 0, jxlBytes.last == 0 {
                do {
                    return try reverse(Data(jxlBytes.dropLast()))
                } catch {
                    throw DICOMError.parsingFailed("JXLSwift JPEG reconstruction failed: \(error)")
                }
            }
            throw DICOMError.parsingFailed("JXLSwift JPEG reconstruction failed: \(error)")
        }
    }

    /// Trims any bytes trailing the final JPEG End-Of-Image marker (`FF D9`), removing
    /// a DICOM even-length pad byte so the JPEG bitstream handed to the recompressor is
    /// exactly the original image. A no-op when the fragment already ends at EOI.
    private static func trimmedToJPEGEOI(_ data: Data) -> Data {
        let bytes = Data(data)  // rebase to 0-based indices for safe subscripting
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
