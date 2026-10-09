import Foundation

#if canImport(J2KCore) && canImport(J2KCodec)
import J2KCore
import J2KCodec
#endif

/// Dedicated HTJ2K (ISO/IEC 15444-15) codec adapter for DICOMKit.
///
/// Wraps `J2KSwiftCodec` with HTJ2K-specific configuration, including
/// RPCL progression ordering for `.htj2kRPCLLossless` (1.2.840.10008.1.2.4.202).
///
/// Reference: DICOM PS3.5 Section A.4.4 — JPEG 2000 Image Compression (the HTJ2K syntaxes .201/.202/.203 are defined there)
///
/// NEMA-verified: 2026a, checked 2026-09-25 — the three HTJ2K UIDs come from `TransferSyntax` (PS3.6 2026a Table A-1) and the RPCL requirement for .202 is in PS3.5 2026a A.4.4. The citation said A.4.6, which is MPEG-4 AVC/H.264; corrected.
public struct HTJ2KCodec: ImageCodec, ImageEncoder, Sendable {
    /// The three DICOM HTJ2K transfer syntax UIDs.
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.htj2kLossless.uid,
        TransferSyntax.htj2kRPCLLossless.uid,
        TransferSyntax.htj2kLossy.uid
    ]

    /// Encoding is supported for all three HTJ2K syntaxes.
    public static let supportedEncodingTransferSyntaxes: [String] = supportedTransferSyntaxes

    /// The specific transfer syntax this codec instance targets for encoding.
    private let targetTransferSyntaxUID: String?

    /// The underlying J2KSwiftCodec that performs the actual work.
    private let backing: J2KSwiftCodec

    /// Creates an HTJ2K codec, optionally pinned to a specific transfer syntax for encoding.
    ///
    /// - Parameter targetTransferSyntaxUID: The HTJ2K transfer syntax UID to target during encoding.
    ///   When `nil`, defaults to HTJ2K Lossless.
    public init(targetTransferSyntaxUID: String? = nil) {
        self.targetTransferSyntaxUID = targetTransferSyntaxUID
        let uid = targetTransferSyntaxUID ?? TransferSyntax.htj2kLossless.uid
        self.backing = J2KSwiftCodec(encodingTransferSyntaxUID: uid, decodingTransferSyntaxUID: uid)
    }

    // MARK: - ImageCodec

    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        try backing.decodeFrame(frameData, descriptor: descriptor, frameIndex: frameIndex)
    }

    // MARK: - ImageEncoder

    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        backing.canEncode(with: configuration, descriptor: descriptor)
    }

    public func encodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        configuration: CompressionConfiguration
    ) throws -> Data {
        try backing.encodeFrame(frameData, descriptor: descriptor, frameIndex: frameIndex, configuration: configuration)
    }

    // MARK: - Fast-Path Transcoding

    /// Transcodes a J2K codestream to HTJ2K without full pixel decode/re-encode.
    ///
    /// Uses J2KTranscoder's coefficient-level re-encoding for bit-exact results
    /// and significantly faster throughput compared to decode+encode.
    ///
    /// - Parameter codestreamData: A standard JPEG 2000 (Part 1) codestream.
    /// - Returns: The HTJ2K codestream.
    /// - Throws: `DICOMError` if the input is not valid J2K or transcoding fails.
    public static func transcodeToHTJ2K(_ codestreamData: Data) throws -> Data {
        #if canImport(J2KCore) && canImport(J2KCodec)
        let transcoder = J2KTranscoder()
        let result = try transcoder.transcode(codestreamData, direction: .legacyToHT)
        return result.data
        #else
        throw DICOMError.unsupportedTransferSyntax("HTJ2K transcoding requires J2KSwift")
        #endif
    }

    /// Transcodes an HTJ2K codestream back to standard JPEG 2000.
    ///
    /// - Parameter codestreamData: An HTJ2K codestream.
    /// - Returns: The standard JPEG 2000 codestream.
    /// - Throws: `DICOMError` if the input is not valid HTJ2K or transcoding fails.
    public static func transcodeFromHTJ2K(_ codestreamData: Data) throws -> Data {
        #if canImport(J2KCore) && canImport(J2KCodec)
        let transcoder = J2KTranscoder()
        let result = try transcoder.transcode(codestreamData, direction: .htToLegacy)
        return result.data
        #else
        throw DICOMError.unsupportedTransferSyntax("HTJ2K transcoding requires J2KSwift")
        #endif
    }

    /// Detects whether a codestream uses HTJ2K encoding.
    ///
    /// - Parameter codestreamData: A JPEG 2000 codestream.
    /// - Returns: `true` when the codestream is HTJ2K-encoded.
    public static func isHTJ2K(_ codestreamData: Data) -> Bool {
        #if canImport(J2KCore) && canImport(J2KCodec)
        return (try? J2KTranscoder().isHTJ2K(codestreamData)) ?? false
        #else
        return false
        #endif
    }

    /// Direction for fast-path codestream transcoding.
    enum TranscodeDirection {
        case j2kToHTJ2K
        case htj2kToJ2K
    }
}
