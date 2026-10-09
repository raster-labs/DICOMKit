// CodecInspectorViewModel.swift
// DICOMStudio
//
// DICOM Studio — Codec inspector ViewModel (Phase 8)
//
// NEMA-verified: 2026a, checked 2026-10-05 — transferSyntaxDescription is DICOMCore TransferSyntax.displayName (the PS3.6 2026a Table A-1 name); it was `description`, which spelled the VR/byte-order encoding for every compressed syntax

import Foundation
import Observation
import DICOMCore

// MARK: - CodecInspectorViewModel

/// ViewModel for the codec inspector panel.
///
/// Tracks which codec decoded the current image, the active hardware backend,
/// and how long decoding took. Designed to be stored as a property on
/// ``ImageViewerViewModel``.
///
/// Requires macOS 14+ / iOS 17+ for the `@Observable` macro.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
public final class CodecInspectorViewModel {

    // MARK: - State

    /// Current inspection status.
    public var status: CodecInspectorStatus = .noImage

    /// Whether the inspector panel is visible.
    public var isVisible: Bool = false

    // MARK: - Computed Helpers

    /// A single-line summary of the current codec status.
    public var statusSummary: String {
        CodecInspectorHelpers.statusSummary(status)
    }

    /// Whether a decoded entry is currently available.
    public var hasEntry: Bool {
        if case .decoded = status { return true }
        return false
    }

    /// The decoded entry if available, otherwise `nil`.
    public var entry: CodecInspectorEntry? {
        if case .decoded(let e) = status { return e }
        return nil
    }

    // MARK: - Mutation

    /// Updates the inspector from a completed `DecodedImageResult`.
    ///
    /// Call this after ``ImageDecodingService/decode(file:)`` succeeds.
    public func update(from result: DecodedImageResult, frameCount: Int) {
        // The PS3.6 Table A-1 name (`displayName`), not `description`, which spells
        // the VR/byte-order encoding ("Explicit VR Little Endian (…)") for every
        // encapsulated syntax and so misnamed each compressed file.
        let desc = TransferSyntax.from(uid: result.transferSyntaxUID)?.displayName
                    ?? result.transferSyntaxUID
        let entry = CodecInspectorEntry(
            transferSyntaxUID: result.transferSyntaxUID,
            transferSyntaxDescription: desc,
            codecName: result.codecName,
            backend: result.backend,
            decodeTimeMs: result.decodeTimeMs,
            frameCount: frameCount
        )
        status = .decoded(entry)
    }

    /// Sets status to `.decoding` while a decode is in progress.
    public func markDecoding() {
        status = .decoding
    }

    /// Resets to `.noImage` (when no file is loaded).
    public func clear() {
        status = .noImage
        isVisible = false
    }

    // MARK: - Init

    public init() {}
}
