// CodecInspectorModel.swift
// DICOMStudio
//
// DICOM Studio — Codec inspector models for the J2KSwift v3 integration (Phase 8)
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (inspector state; transferSyntaxDescription is filled by CodecInspectorViewModel with the Table A-1 name)

import Foundation
import DICOMCore

// MARK: - CodecInspectorEntry

/// Describes the codec used to decode a single DICOM image.
public struct CodecInspectorEntry: Sendable, Equatable {
    /// Transfer syntax UID used during decode.
    public let transferSyntaxUID: String
    /// Human-readable transfer syntax description.
    public let transferSyntaxDescription: String
    /// Name of the codec that handled decompression.
    public let codecName: String
    /// Hardware/software backend active during decoding.
    public let backend: CodecBackend
    /// Approximate decode duration in milliseconds.
    public let decodeTimeMs: Double
    /// Number of frames decoded.
    public let frameCount: Int

    public init(
        transferSyntaxUID: String,
        transferSyntaxDescription: String,
        codecName: String,
        backend: CodecBackend,
        decodeTimeMs: Double,
        frameCount: Int
    ) {
        self.transferSyntaxUID = transferSyntaxUID
        self.transferSyntaxDescription = transferSyntaxDescription
        self.codecName = codecName
        self.backend = backend
        self.decodeTimeMs = decodeTimeMs
        self.frameCount = frameCount
    }
}

// MARK: - CodecInspectorStatus

/// Describes the current state of the codec inspector panel.
public enum CodecInspectorStatus: Sendable, Equatable {
    /// No image has been loaded yet.
    case noImage
    /// Codec inspection is in progress (decoding underway).
    case decoding
    /// Decode completed successfully; `entry` contains codec info.
    case decoded(CodecInspectorEntry)
    /// The transfer syntax is uncompressed; no codec was needed.
    case uncompressed(transferSyntaxDescription: String)
    /// No codec is registered for the file's transfer syntax.
    case unsupportedCodec(transferSyntaxUID: String)
}

// MARK: - JPIPLoadingState

/// Describes the JPIP stream loading state in the image viewer.
public enum JPIPLoadingState: Sendable, Equatable {
    /// Not loading; no JPIP session active.
    case idle
    /// Fetching initial preview (quality layer 1).
    case fetchingPreview
    /// Refining quality (fetching more layers).
    case refining(layers: Int)
    /// Load failed with a reason string.
    case failed(reason: String)
    /// Loaded successfully at the given quality layer count.
    case loaded(layers: Int)
}
