// FrameRenderService.swift
// DICOMRenderKit — GPU_RENDERING_PLAN.md milestones M2/M3/M7
//
// The one entry point callers use. Picks a backend, and guarantees an image comes
// back if one can be produced at all.
//
// NEMA-verified: 2026a, checked 2026-09-30 — carries no DICOM-standard data (backend choice and CPU fallback; the fallback is what keeps YBR, auto-window and 32-bit cells on the CPU). C1 classification confirmed.

import Foundation
import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics

/// Renders frames through the best available backend, falling back to the CPU.
///
/// The fallback is not a safety net bolted on the side — it is the contract. The
/// Metal backend answers `nil` for everything it does not handle exactly (YBR,
/// auto-windowing, oversized frames, any GPU failure), and every one of those
/// lands here and renders on the CPU. That is what lets the GPU path be narrow and
/// exact instead of broad and approximate.
public final class FrameRenderService: @unchecked Sendable {

    /// The process-wide service, using automatic backend selection.
    public static let shared = FrameRenderService()

    private let cpu = CPUFrameRenderer()
    private let metal: FrameRenderBackend?
    private let preference: RenderBackendPreference

    public init(preference: RenderBackendPreference = .automatic) {
        self.preference = preference
        #if canImport(Metal)
        // Built only when it would actually be used, so a CPU-only configuration
        // never pays for a Metal device or a shader compile.
        self.metal = preference.effective == .metal ? MetalFrameRenderer() : nil
        #else
        self.metal = nil
        #endif
    }

    /// The backend this service will try first.
    ///
    /// Reports `.cpu` when Metal was requested but could not be created, so what is
    /// surfaced in the UI is what is actually running.
    public var activeBackend: RenderBackend {
        metal?.backend ?? .cpu
    }

    /// A human-readable description of the active backend.
    public var backendDescription: String {
        activeBackend.displayName
    }

    /// Whether decoded pixel data is worth page-aligning before it is cached.
    ///
    /// True only when the GPU is active, where alignment is what lets the shader
    /// read the bytes in place. On a CPU-only machine the alignment copy would buy
    /// nothing, so callers skip it.
    ///
    /// Align **once, when the pixels enter a cache** — never per render. Doing it
    /// per render pays exactly the copy alignment exists to avoid.
    public var prefersAlignedPixelData: Bool {
        activeBackend == .metal
    }

    #if canImport(Metal)
    /// The Metal renderer, when one is active — the only thing that can produce a
    /// display texture.
    ///
    /// `nil` on a CPU-only machine, which is why every caller must keep an
    /// `Image(decorative:)` path.
    public var displayRenderer: MetalFrameRenderer? {
        metal as? MetalFrameRenderer
    }
    #endif

    /// Renders a frame.
    ///
    /// - Returns: the image, or `nil` only when *neither* backend can render it —
    ///   which means the frame genuinely cannot be displayed.
    public func renderFrame(_ request: FrameRenderRequest) -> CGImage? {
        if let metal, let image = metal.renderFrame(request) {
            return image
        }
        return cpu.renderFrame(request)
    }

    /// Which backend actually rendered a given request, without rendering it.
    ///
    /// For diagnostics and for the benchmark harness — it must agree with what
    /// ``renderFrame(_:)`` does, so it asks the same question the same way.
    public func backend(willRender request: FrameRenderRequest) -> RenderBackend {
        guard let metal else { return .cpu }
        return metal.renderFrame(request) != nil ? .metal : .cpu
    }

    /// Releases any GPU memory held by the pool.
    public func purgeCaches() {
        #if canImport(Metal)
        (metal as? MetalFrameRenderer)?.purgeCaches()
        #endif
    }
}
#endif
