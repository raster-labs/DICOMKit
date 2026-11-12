// CodecInspectorHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent helpers for the codec inspector panel.
//
// Lives outside any `#if canImport(SwiftUI)` guard so it can be
// unit-tested on Linux as well as all Apple platforms.
//
// NEMA-verified: 2026a, checked 2026-10-05 — codecDisplayName resolves the UID through DICOMCore TransferSyntax and names the codec family; JPEG XL, video, Deflated Image Frame Compression (PS3.5 2026a A.4.13) and Encapsulated Uncompressed (A.4.11) were "Unknown" and are now named; every non-retired PS3.6 2026a Table A-1 transfer syntax gets a name (CodecInspectorTests)

import Foundation
import DICOMCore
import DICOMKit

// MARK: - CodecInspectorHelpers

/// Platform-independent helpers for formatting codec inspector data.
public enum CodecInspectorHelpers: Sendable {

    // MARK: - Backend display

    /// Returns a short human-readable display name for a `CodecBackend`.
    ///
    /// Delegates to `backend.displayName` for the hardware-aware description.
    public static func backendDisplayName(_ backend: CodecBackend) -> String {
        backend.displayName
    }

    /// Returns an SF Symbol name appropriate for the given `CodecBackend`.
    public static func backendSFSymbol(_ backend: CodecBackend) -> String {
        switch backend {
        case .metal:        return "cpu"
        case .accelerate:   return "bolt.fill"
        case .scalar:       return "square.stack.3d.down.right"
        }
    }

    // MARK: - Timing

    /// Formats a decode duration in milliseconds for display.
    ///
    ///     formatDecodeTime(0.8)    → "< 1 ms"
    ///     formatDecodeTime(23.4)   → "23 ms"
    ///     formatDecodeTime(1234.0) → "1.2 s"
    public static func formatDecodeTime(_ ms: Double) -> String {
        if ms < 1.0    { return "< 1 ms" }
        if ms < 1000.0 { return "\(Int(ms.rounded())) ms" }
        return String(format: "%.1f s", ms / 1000.0)
    }

    // MARK: - Codec name

    /// Returns a short human-readable codec name for a transfer syntax UID.
    public static func codecDisplayName(for transferSyntaxUID: String) -> String {
        let ts = TransferSyntax.from(uid: transferSyntaxUID)
        guard let ts else { return "Unknown (\(transferSyntaxUID))" }

        if ts.isHTJ2K         { return "SwiftJ2K (HTJ2K)" }
        if ts.isJPEG2000Part2 { return "SwiftJ2K (JPEG 2000 Part 2)" }
        if ts.isJPEG2000      { return "SwiftJ2K (JPEG 2000)" }
        if ts.isJPEGLS        { return "SwiftJLS (JPEG-LS)" }
        if ts.isJPEG          { return "SwiftJLI (JPEG)" }
        if ts.isRLE           { return "SwiftRLE (RLE Lossless)" }
        if ts.isJP3D          { return "JP3D (Volumetric JPEG 2000)" }
        if ts.isJPIP          { return "JPIP (streaming)" }
        if ts.isJPEGXL        { return "SwiftJXL (JPEG XL)" }
        if ts.isVideo         { return "Video (\(ts.shortName))" }
        if ts.uid == TransferSyntax.deflatedImageFrameCompression.uid {
            return "Deflate (per-frame, PS3.5 A.4.13)"
        }

        // Uncompressed: the native syntaxes, the deflated data set (deflate wraps the
        // whole data set, not the samples) and Encapsulated Uncompressed (PS3.5 A.4.11).
        if !ts.isEncapsulated || ts.uid == TransferSyntax.encapsulatedUncompressedExplicitVRLittleEndian.uid {
            return "Uncompressed"
        }
        return "Unknown (\(transferSyntaxUID))"
    }

    /// Returns the pinned pure-Swift codec engine version for a transfer syntax UID,
    /// or `nil` when the syntax does not route through one of the 5 pure-Swift codec libraries.
    public static func codecEngineVersion(for transferSyntaxUID: String) -> String? {
        guard let ts = TransferSyntax.from(uid: transferSyntaxUID) else { return nil }
        if ts.isHTJ2K || ts.isJPEG2000Part2 || ts.isJPEG2000 {
            return SwiftJ2KDICOMCodec.engineVersion
        }
        if ts.isJP3D   { return JP3DCodec.engineVersion }
        if ts.isJPIP   { return DICOMJPIPClient.engineVersion }
        if ts.isJPEGLS { return JPEGLSCodec.engineVersion }
        if ts.isJPEG   { return JLICodec.engineVersion }
        if ts.isRLE    { return RLECodec.engineVersion }
        if ts.isJPEGXL { return JXLCodec.engineVersion }
        return nil
    }

    /// Returns a human-readable codec display name annotated with its library version
    /// when backed by one of the pure-Swift codec packages.
    public static func codecVersionedDisplayName(for transferSyntaxUID: String) -> String {
        guard let ts = TransferSyntax.from(uid: transferSyntaxUID) else {
            return "Unknown (\(transferSyntaxUID))"
        }
        if ts.isHTJ2K         { return "\(SwiftJ2KDICOMCodec.engineName) \(SwiftJ2KDICOMCodec.engineVersion) (HTJ2K)" }
        if ts.isJPEG2000Part2 { return "\(SwiftJ2KDICOMCodec.engineName) \(SwiftJ2KDICOMCodec.engineVersion) (JPEG 2000 Part 2)" }
        if ts.isJPEG2000      { return "\(SwiftJ2KDICOMCodec.engineName) \(SwiftJ2KDICOMCodec.engineVersion) (JPEG 2000)" }
        if ts.isJP3D          { return "\(JP3DCodec.engineName) \(JP3DCodec.engineVersion) (Volumetric JPEG 2000)" }
        if ts.isJPIP          { return "\(DICOMJPIPClient.engineName) \(DICOMJPIPClient.engineVersion) (JPIP Streaming)" }
        if ts.isJPEGLS        { return "\(JPEGLSCodec.engineName) \(JPEGLSCodec.engineVersion) (JPEG-LS)" }
        if ts.isJPEG          { return "\(JLICodec.engineName) \(JLICodec.engineVersion) (JPEG)" }
        if ts.isRLE           { return "\(RLECodec.engineName) \(RLECodec.engineVersion) (RLE Lossless)" }
        if ts.isJPEGXL        { return "\(JXLCodec.engineName) \(JXLCodec.engineVersion) (JPEG XL)" }
        return codecDisplayName(for: transferSyntaxUID)
    }

    // MARK: - Status summary

    /// Returns a single-line summary string for a `CodecInspectorStatus`.
    public static func statusSummary(_ status: CodecInspectorStatus) -> String {
        switch status {
        case .noImage:
            return "No image loaded"
        case .decoding:
            return "Decoding…"
        case .decoded(let entry):
            return "\(entry.codecName) · \(formatDecodeTime(entry.decodeTimeMs)) · \(backendDisplayName(entry.backend))"
        case .uncompressed(let desc):
            return "Uncompressed (\(desc))"
        case .unsupportedCodec(let uid):
            return "No codec for \(uid)"
        }
    }
}
