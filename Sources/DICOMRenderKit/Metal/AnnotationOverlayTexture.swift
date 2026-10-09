// AnnotationOverlayTexture.swift
// DICOMRenderKit
//
// A reader's drawn text and arrows, rasterized to a texture the display
// shader composites over a `DisplayFrameTexture`.
//
// NEMA-verified: 2026a, checked 2026-09-30 — carries no DICOM-standard data (a texture wrapper). C1 classification confirmed.

import Foundation

#if canImport(Metal)
import Metal

/// A rasterized annotation layer, the same pixel dimensions as the frame it
/// overlays.
///
/// Kept as a sibling to `DisplayFrameTexture` rather than a field on it: the
/// two invalidate on entirely different triggers. A window/level or pan/zoom
/// change rebuilds the frame texture (a fresh decode/compute pass) and must
/// not touch this; an annotation being drawn, moved or edited rebuilds this
/// and must not force a frame re-decode. Coupling their lifetimes would pay
/// for a GPU compute dispatch on every annotation drag.
public struct AnnotationOverlayTexture: @unchecked Sendable {
    public let texture: MTLTexture

    public init(texture: MTLTexture) {
        self.texture = texture
    }

    public var width: Int { texture.width }
    public var height: Int { texture.height }
}
#endif
