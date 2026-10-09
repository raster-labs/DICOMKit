// JPEGCodecEngine.swift
// DICOMCore
// NEMA-verified: 2026a, checked 2026-09-25 — the four JPEG transfer syntaxes named below (.50 Baseline Process 1, .51 Extended, .57 Lossless, .70 Lossless SV1) match PS3.6 2026a Table A-1; the file holds no other standard data. C1 classification confirmed.

import Foundation

/// Selects which implementation *encodes* JPEG Baseline
/// (1.2.840.10008.1.2.4.50) pixel data.
///
/// JPEG Baseline is the only JPEG transfer syntax this library can encode two
/// different ways: ``JLICodec`` — the pure-Swift ITU-T T.81 implementation the
/// ``CodecRegistry`` wires up for all four JPEG syntaxes — and
/// ``NativeJPEGCodec``, Apple's ImageIO encoder. The other three JPEG syntaxes
/// (Extended .51, Lossless .57, Lossless SV1 .70) have no second encoder:
/// ImageIO ships no SOF1/SOF3 encoder, which is why
/// `NativeJPEGCodec.supportedEncodingTransferSyntaxes` lists Baseline alone.
/// Selecting ``native`` for any other syntax is therefore a no-op — the
/// registry keeps returning the JLICodec encoder.
///
/// This exists so DICOMStudio's CLI Workshop can benchmark the two Baseline
/// encoders against each other. The `dicom-compress` CLI never sets it, so it
/// always runs the ``jli`` default and its output is unchanged.
public enum JPEGCodecEngine: String, Sendable, CaseIterable, CustomStringConvertible {
    /// JLISwift — pure-Swift ITU-T T.81. The default, and the only engine for
    /// every JPEG transfer syntax other than Baseline.
    case jli

    /// Apple ImageIO / CoreGraphics. Honoured for JPEG Baseline only.
    case native

    public var description: String { rawValue }

    /// Human-readable label for console / UI display.
    public var displayName: String {
        switch self {
        case .jli:    return "JLICodec (pure Swift)"
        case .native: return "Native (Apple ImageIO)"
        }
    }
}

extension CodecRegistry {
    /// The one transfer syntax for which ``JPEGCodecEngine`` selects between two
    /// encoders. See ``JPEGCodecEngine`` for why the other JPEG syntaxes are excluded.
    public static let jpegEngineSelectableUID: String = TransferSyntax.jpegBaseline.uid

    /// Returns an encoder for `transferSyntaxUID`, honouring `engine` **only** for
    /// JPEG Baseline. Every other transfer syntax — including JPEG Extended,
    /// Lossless, and Lossless SV1 — resolves exactly as ``encoder(for:)`` does,
    /// whatever `engine` says, because no alternate encoder exists for them.
    public func encoder(for transferSyntaxUID: String, engine: JPEGCodecEngine) -> (any ImageEncoder)? {
        guard engine == .native, transferSyntaxUID == Self.jpegEngineSelectableUID else {
            return encoder(for: transferSyntaxUID)
        }
        #if canImport(ImageIO)
        return NativeJPEGCodec()
        #else
        // No ImageIO on this platform — the native engine does not exist, so fall
        // back to the registered (JLICodec) encoder rather than failing the encode.
        return encoder(for: transferSyntaxUID)
        #endif
    }
}
