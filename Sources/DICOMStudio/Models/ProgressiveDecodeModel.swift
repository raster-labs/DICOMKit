// ProgressiveDecodeModel.swift
// DICOMStudio
//
// DICOM Studio — Progressive JPEG 2000 decode model (Phase 8)
//
// Models the multi-level progressive display that shows a low-resolution
// preview first, then refines to half resolution, and finally full resolution.
// This simulates J2K multi-resolution progressive display since
// `J2KDecoder.decodeResolution` is not yet available upstream (see J2KSWIFT_BUG_REPORT.md).
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no transcribed DICOM-standard data — isJ2KTransferSyntax is the 7 PS3.6 2026a Table A-1 JPEG 2000 / HTJ2K rows (.90 .91 .92 .93 .201 .202 .203) resolved through DICOMCore TransferSyntax.isJPEG2000; resolution levels are codec, not DICOM, concepts

import Foundation
import DICOMCore

// MARK: - ProgressiveDecodeLevel

/// Represents a progressive resolution level for JPEG 2000 image display.
///
/// Levels correspond to typical J2K decomposition levels rendered in sequence:
/// `quarter` is the fastest preview and `full` is the final, highest-quality image.
public enum ProgressiveDecodeLevel: Int, Sendable, Equatable, CaseIterable {
    /// 1/4 resolution — fast preview, displayed immediately.
    case quarter = 0
    /// 1/2 resolution — intermediate refinement pass.
    case half = 1
    /// Full resolution — final, highest-quality image.
    case full = 2

    /// The scale factor relative to full resolution.
    ///
    /// Quarter → `0.25`, half → `0.5`, full → `1.0`.
    public var scaleFactor: Double {
        switch self {
        case .quarter: return 0.25
        case .half:    return 0.5
        case .full:    return 1.0
        }
    }

    /// Short display label shown in the progressive quality badge.
    public var shortLabel: String {
        switch self {
        case .quarter: return "25%"
        case .half:    return "50%"
        case .full:    return "100%"
        }
    }

    /// Whether this is the final (full-quality) level.
    public var isFinal: Bool { self == .full }
}

// MARK: - ProgressiveDecodeState

/// Describes the lifecycle of a progressive JPEG 2000 decode operation in the viewer.
///
/// The state machine transitions:
/// `idle` → `decoding(.quarter)` → `decoding(.half)` → `decoding(.full)` → `complete(_:)`
///
/// For non-J2K files (or uncompressed data), the state remains `.unavailable`
/// and the normal synchronous decode path is used instead.
public enum ProgressiveDecodeState: Sendable, Equatable {
    /// No progressive decode has been started for the current file.
    case idle
    /// Decoding is in progress; `level` is the most recently rendered quality level.
    case decoding(level: ProgressiveDecodeLevel)
    /// All levels have been rendered. `totalDecodeMs` is the wall-clock time for the
    /// full-resolution decode pass.
    case complete(totalDecodeMs: Double)
    /// Progressive decode is not applicable (uncompressed or non-J2K/HTJ2K file).
    case unavailable
}

// MARK: - ProgressiveDecodeHelpers

/// Helpers for progressive decode UI — all pure functions, testable on all platforms.
public enum ProgressiveDecodeHelpers: Sendable {

    /// Returns the accessibility label describing the current progressive decode state.
    public static func accessibilityLabel(for state: ProgressiveDecodeState) -> String {
        switch state {
        case .idle:
            return "Image not yet loaded"
        case .decoding(let level):
            return "Progressive decode in progress at \(level.shortLabel) quality"
        case .complete(let ms):
            return String(format: "Image fully decoded in %.0f ms", ms)
        case .unavailable:
            return "Standard decode mode"
        }
    }

    /// Returns a short status string suitable for a progress badge overlay.
    ///
    /// - Returns: `nil` when no badge should be shown (idle, unavailable, or complete).
    public static func badgeText(for state: ProgressiveDecodeState) -> String? {
        switch state {
        case .decoding(let level) where !level.isFinal:
            return "Refining… \(level.shortLabel)"
        case .decoding:
            return "Refining… 100%"
        default:
            return nil
        }
    }

    /// Returns `true` when the progressive overlay spinner should be visible.
    public static func isProgressSpinnerVisible(for state: ProgressiveDecodeState) -> Bool {
        switch state {
        case .decoding: return true
        default: return false
        }
    }

    /// Returns `true` for JPEG 2000 and HTJ2K transfer syntax UIDs that benefit from
    /// progressive display. Used to decide whether to engage the progressive decode path.
    public static func isJ2KTransferSyntax(_ uid: String) -> Bool {
        // Decode-only: enumerate the distinct J2K / HTJ2K UIDs from the shared
        // catalog (intent is irrelevant here, so dedupe by UID).
        j2kUIDs.contains(uid)
    }

    /// Distinct JPEG 2000 / HTJ2K transfer-syntax UIDs, sourced from the shared
    /// catalog so this stays in sync with the canonical list.
    private static let j2kUIDs: Set<String> = Set(
        TransferSyntax.selectableEncodings
            .filter { $0.transferSyntax.isJPEG2000 }
            .map { $0.uid }
    )
}
