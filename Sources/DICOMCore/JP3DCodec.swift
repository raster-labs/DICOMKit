// NEMA-verified: 2026a, checked 2026-09-25 — carries no DICOM-standard data. The two UIDs are private (1.2.826.0.1.3680043.10.511.x), not in PS3.6 2026a Table A-1; JP3D has no standard transfer syntax. C1 classification confirmed.

import Foundation

/// JP3D volumetric JPEG 2000 codec placeholder (deferred pending `SwiftJ2K` 12.2.0 `SwiftJ2K3D` qualification).
///
/// ## Deferral Notice
///
/// JP3D volumetric compression and decompression (`1.2.826.0.1.3680043.10.511.1` / `.2`) are
/// **deferred** in this release until `SwiftJ2K3D` completes qualification in `SwiftJ2K` 12.2.0.
/// All encode and decode entry points fail closed with `DICOMError.unsupportedTransferSyntax`,
/// and `CodecRegistry.shared` does not register JP3D transfer syntaxes.
public final class JP3DCodec: ImageCodec, ImageEncoder, Sendable {

    /// Private experimental JP3D transfer syntax UIDs (currently deferred).
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.jp3dLossless.uid,
        TransferSyntax.jp3dLossy.uid
    ]

    /// Private experimental JP3D encoding transfer syntax UIDs (currently deferred).
    public static let supportedEncodingTransferSyntaxes: [String] = supportedTransferSyntaxes

    /// Human-readable deferral explanation surfaced on any JP3D operation attempt.
    public static let deferralReason =
        "JP3D volumetric compression is deferred pending SwiftJ2K 12.2.0 (SwiftJ2K3D qualification)."

    /// The compression mode to use for encoding once `SwiftJ2K3D` is enabled.
    public enum CompressionMode: Sendable, Equatable {
        /// Lossless compression (bit-exact reconstruction).
        case lossless
        /// Lossless compression using HTJ2K block coder.
        case losslessHTJ2K
        /// Lossy compression with PSNR target.
        case lossy(psnr: Double = 40.0)
        /// Lossy HTJ2K compression with PSNR target.
        case lossyHTJ2K(psnr: Double = 40.0)

        var isLossless: Bool {
            switch self {
            case .lossless, .losslessHTJ2K: return true
            case .lossy, .lossyHTJ2K: return false
            }
        }
    }

    /// The compression mode configured on this codec instance.
    public let compressionMode: CompressionMode

    /// Creates a JP3D codec instance (deferred; operations fail closed).
    public init(compressionMode: CompressionMode = .lossless) {
        self.compressionMode = compressionMode
    }

    // MARK: - Volumetric API (Deferred — Fails Closed)

    public func encodeVolume(
        _ data: Data,
        descriptor: PixelDataDescriptor
    ) async throws -> Data {
        throw DICOMError.unsupportedTransferSyntax(Self.deferralReason)
    }

    public func decodeVolume(
        _ data: Data,
        descriptor: PixelDataDescriptor
    ) async throws -> Data {
        throw DICOMError.unsupportedTransferSyntax(Self.deferralReason)
    }

    // MARK: - ImageCodec Protocol (Deferred — Fails Closed)

    public func decode(_ data: Data, descriptor: PixelDataDescriptor) throws -> Data {
        throw DICOMError.unsupportedTransferSyntax(Self.deferralReason)
    }

    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        throw DICOMError.unsupportedTransferSyntax(Self.deferralReason)
    }

    // MARK: - ImageEncoder Protocol (Deferred — Fails Closed)

    public func canEncode(with configuration: DICOMCore.CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        false
    }

    public func encodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        configuration: DICOMCore.CompressionConfiguration
    ) throws -> Data {
        throw DICOMError.unsupportedTransferSyntax(Self.deferralReason)
    }
}
