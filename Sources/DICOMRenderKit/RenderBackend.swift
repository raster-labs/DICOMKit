// RenderBackend.swift
// DICOMRenderKit — GPU_RENDERING_PLAN.md milestone M2
//
// Backend selection for frame *display* rendering. Deliberately shaped like
// `DICOMCore/CodecBackend.swift`, which already establishes the house idiom for
// this: an enum with a `displayName` and an `isAvailable` check, an auto-selecting
// chain, and a `...Preference` with a `.forced` initialiser. Following it means the
// Studio settings UI, the benchmark harness and any future `--render-backend` flag
// all get a shape the codebase already knows.
//
// Note the deliberate difference from `CodecBackend`: there is no `.accelerate`
// rung. The CPU renderer is a table lookup per pixel (see `DICOMCore/WindowLUT`),
// which is memory-bound rather than arithmetic-bound, so a vectorised gather would
// add a dependency and a code path for no measurable gain.
//
// NEMA-verified: 2026a, checked 2026-09-30 — carries no DICOM-standard data (backend selection, environment override, display names). C1 classification confirmed.

import Foundation

#if canImport(Metal)
import Metal
#endif

// MARK: - RenderBackend

/// The engine a DICOM frame is rendered to a displayable image with.
public enum RenderBackend: String, Sendable, CaseIterable, CustomStringConvertible {
    /// Metal GPU compute. Selected automatically only on unified-memory devices.
    case metal

    /// `PixelDataRenderer` + `WindowLUT` on the CPU. Always available.
    case cpu

    public var description: String { rawValue }

    /// A more descriptive display string, including why Metal is unavailable when
    /// it is. Surfaced in Studio next to the codec backend.
    public var displayName: String {
        switch self {
        case .metal:
            #if canImport(Metal)
            guard let device = MetalRenderDevice.shared?.device else {
                return "Metal (no GPU)"
            }
            return device.hasUnifiedMemory
                ? "Metal (\(device.name), unified memory)"
                : "Metal (\(device.name), discrete — copies required)"
            #else
            return "Metal (not supported on this platform)"
            #endif
        case .cpu:
            return "CPU (WindowLUT)"
        }
    }

    /// Whether this backend can run at all on this machine.
    ///
    /// Note this is *availability*, not the automatic choice: Metal on a discrete
    /// GPU is available but is not what ``automatic()`` picks. See
    /// `GPU_RENDERING_PLAN.md`, design pillar 2.
    public var isAvailable: Bool {
        switch self {
        case .metal:
            #if canImport(Metal)
            return MetalRenderDevice.shared != nil
            #else
            return false
            #endif
        case .cpu:
            return true
        }
    }

    /// The backend chosen when the caller expresses no preference.
    ///
    /// `.metal` **only** on a unified-memory device. On Intel Macs with a discrete
    /// GPU the pixel data has to cross a bus in both directions, and the win over
    /// the LUT-accelerated CPU renderer does not survive those copies — so those
    /// machines get `.cpu`, and we do not build or maintain a staging-buffer Metal
    /// variant for them.
    ///
    /// Overridden by `DICOMKIT_RENDER_BACKEND=cpu|metal`, which exists so support
    /// and CI can pin the answer without a rebuild.
    public static func automatic() -> RenderBackend {
        if let override = environmentOverride {
            return override.isAvailable ? override : .cpu
        }
        #if canImport(Metal)
        if let device = MetalRenderDevice.shared?.device, device.hasUnifiedMemory {
            return .metal
        }
        #endif
        return .cpu
    }

    /// `DICOMKIT_RENDER_BACKEND`, parsed. `nil` when unset or unrecognised.
    ///
    /// Unrecognised rather than invalid on purpose: a typo in a support session
    /// should fall back to normal selection, not disable rendering.
    static var environmentOverride: RenderBackend? {
        guard let raw = ProcessInfo.processInfo.environment["DICOMKIT_RENDER_BACKEND"] else {
            return nil
        }
        return RenderBackend(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Every backend usable on this machine, best first.
    public static var availableBackends: [RenderBackend] {
        RenderBackend.allCases.filter(\.isAvailable)
    }
}

// MARK: - RenderBackendPreference

/// A caller's preference for a specific render backend.
///
/// `forced` is honoured when the backend is available, and falls back to `.cpu`
/// when it is not — `.cpu` always works, so a render never fails for want of a
/// backend.
public struct RenderBackendPreference: Sendable, Equatable {
    /// `nil` means "auto" — see ``RenderBackend/automatic()``.
    public var forced: RenderBackend?

    public init(forced: RenderBackend? = nil) {
        self.forced = forced
    }

    /// Auto: Metal on unified-memory hardware, CPU otherwise.
    public static let automatic = RenderBackendPreference()

    /// Force Metal. Honoured on non-unified-memory devices too — for diagnostics —
    /// in which case the input takes the pooled-copy route rather than
    /// `bytesNoCopy`.
    public static let metal = RenderBackendPreference(forced: .metal)

    /// Force the CPU renderer.
    public static let cpu = RenderBackendPreference(forced: .cpu)

    /// The backend this preference actually resolves to on this machine.
    ///
    /// `DICOMKIT_RENDER_BACKEND` outranks `forced`. That is the whole point of the
    /// variable: it exists so support can say "run with the GPU off" and have it
    /// actually happen. If a code path that hard-codes `.metal` could ignore it,
    /// the instruction would be useless exactly when it is needed.
    public var effective: RenderBackend {
        if let override = RenderBackend.environmentOverride {
            return override.isAvailable ? override : .cpu
        }
        guard let forced else { return RenderBackend.automatic() }
        return forced.isAvailable ? forced : .cpu
    }
}
