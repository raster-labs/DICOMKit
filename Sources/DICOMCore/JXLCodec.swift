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

    /// The transfer syntax this instance is decoding, when known (set per-UID at registry
    /// wiring time). It disambiguates the …4.111 JPEG-Recompression decode from the …4.110
    /// / …4.112 pixel decode: for a known …4.111 source a reconstruction failure is a hard
    /// error (we must not fall back to the VarDCT pixel path, which can desync the channel
    /// count from Samples per Pixel), and …4.110 / …4.112 skip the reconstruction probe
    /// entirely. `nil` (a bare `JXLCodec()`, e.g. in benches) auto-detects via the `jbrd`
    /// box and falls back to pixels — the legacy best-effort behaviour.
    public let decodingTransferSyntaxUID: String?

    /// The transfer syntax this instance encodes *to* (…4.110 Lossless or …4.112
    /// general/lossy), set per-UID at registry wiring time. It selects the encode
    /// mode: …4.110 → lossless Modular (distance 0); …4.112 → lossy VarDCT at a
    /// quality-derived distance. Ignored when the instance is used as a decoder (the
    /// codestream drives the decoder). Defaults to Lossless so a bare `JXLCodec()`
    /// encodes bit-exactly (the bench / adapter-test contract).
    public let encodingTransferSyntaxUID: String

    public init(decodingTransferSyntaxUID: String? = nil,
                encodingTransferSyntaxUID: String = TransferSyntax.jpegXLLossless.uid) {
        self.decodingTransferSyntaxUID = decodingTransferSyntaxUID
        self.encodingTransferSyntaxUID = encodingTransferSyntaxUID
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

    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        guard !frameData.isEmpty else {
            throw DICOMError.parsingFailed("Empty JPEG XL data")
        }

        // JPEG Recompression (…4.111): a recompressed JXL carries a `jbrd` reconstruction
        // box. Its faithful pixel decode is to reconstruct the *exact original JPEG* and
        // decode THAT with the JPEG codec — this reproduces the wrapped JPEG's pixels with
        // the channel layout the DICOM descriptor declares (e.g. a 1-component grayscale
        // JPEG stays 1 sample/pixel), rather than the VarDCT bridge's own colour-space
        // representation (which can surface a grayscale source as 3 interleaved channels
        // and desync from Samples per Pixel).
        //
        // When the source syntax is KNOWN to be …4.111, a reconstruction failure is a hard
        // error: we must NOT fall back to the VarDCT pixel path (that is exactly the desync
        // this reroute exists to prevent). When the syntax is …4.110 / …4.112 we skip the
        // reconstruction probe entirely (they carry no `jbrd`, and probing every frame is
        // wasted work). Only a bare, syntax-less instance auto-detects and falls back.
        if decodingTransferSyntaxUID == TransferSyntax.jpegXLRecompression.uid {
            let reconstructedJPEG = try Self.reconstructJPEGFragment(frameData)
            return try JLICodec().decodeFrame(reconstructedJPEG, descriptor: descriptor, frameIndex: frameIndex)
        }
        if decodingTransferSyntaxUID == nil,
           let reconstructedJPEG = try? Self.reconstructJPEGFragment(frameData) {
            return try JLICodec().decodeFrame(reconstructedJPEG, descriptor: descriptor, frameIndex: frameIndex)
        }

        func decode(_ data: Data) throws -> Data {
            // `signedOutput` un-shifts a 16-bit decode back to two's-complement when the
            // DICOM descriptor declares signed samples (Pixel Representation = 1); it only
            // affects 16-bit results, so unsigned and 8-bit decodes are untouched.
            let frame = try JXLDecoder().decode(data, signedOutput: descriptor.isSigned)
            return dicomFrameBytes(fromInterleaved: frame.data, descriptor: descriptor)
        }

        do {
            return try decode(frameData)
        } catch {
            // PS3.5 §A.4 requires every encapsulated fragment to have an even length and
            // lets the last fragment of a frame be padded. It does not fix the pad byte
            // for JPEG XL, but writers commonly append a single 0x00. JXLSwift's container
            // parser is strict about trailing bytes and rejects that pad ("partial box
            // header"), so retry once with a single trailing null removed before giving up.
            if frameData.count % 2 == 0, frameData.last == 0 {
                do {
                    return try decode(Data(frameData.dropLast()))
                } catch {
                    throw DICOMError.parsingFailed("JXLSwift decode failed: \(error)")
                }
            }
            throw DICOMError.parsingFailed("JXLSwift decode failed: \(error)")
        }
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
