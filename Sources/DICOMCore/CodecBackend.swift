// CodecBackend.swift
// DICOMCore — Phase 5: Hardware Acceleration
// NEMA-verified: 2026a, checked 2026-09-25 — carries no DICOM-standard data (hardware backend selection). C1 classification confirmed.

import Foundation

#if canImport(J2KMetal)
import J2KMetal
#endif

#if canImport(J2KAccelerate)
import J2KAccelerate
#endif

// MARK: - CodecBackend

/// Identifies the hardware acceleration backend used by a DICOM codec.
///
/// The backends form a priority chain: `metal` is fastest on Apple platforms,
/// `accelerate` (Accelerate framework + ARM NEON / SSE) is next, and `scalar`
/// is the universal fallback.
///
/// ## Backend Selection
///
/// At runtime DICOMKit probes hardware availability and picks the best backend
/// automatically.  Use ``CodecBackendProbe/bestAvailable`` to query the result,
/// or instantiate a ``CodecBackendPreference`` to force a specific backend when
/// running benchmarks or diagnostic tools.
///
/// ```swift
/// // Query runtime best backend
/// let backend = CodecBackendProbe.bestAvailable
/// print(backend.displayName)   // e.g. "Metal (Apple Silicon)"
///
/// // Force scalar for benchmarking
/// let prefs = CodecBackendPreference(forced: .scalar)
/// ```
public enum CodecBackend: String, Sendable, CaseIterable, CustomStringConvertible {
    /// Apple Metal GPU compute — fastest on Apple Silicon / Intel + discrete GPU.
    case metal

    /// Apple Accelerate / ARM NEON / x86 SSE — CPU vectorised path.
    case accelerate

    /// Pure scalar Swift — universal fallback, no hardware dependency.
    case scalar

    /// Human-readable name, suitable for `--backend` CLI option display.
    public var description: String { rawValue }

    /// A more descriptive display string including detected sub-capabilities.
    public var displayName: String {
        switch self {
        case .metal:
            #if canImport(Metal)
            return J2KMetalDevice.isAvailable ? "Metal (GPU)" : "Metal (unavailable)"
            #else
            return "Metal (not supported on this platform)"
            #endif
        case .accelerate:
            #if canImport(J2KAccelerate)
            let simd = HTSIMDCapability.detect()
            switch simd.family {
            case .neon:   return "Accelerate (ARM NEON \(simd.vectorWidth * 32)-bit)"
            case .avx2:   return "Accelerate (x86 AVX2 \(simd.vectorWidth * 32)-bit)"
            case .sse42:  return "Accelerate (x86 SSE4.2 \(simd.vectorWidth * 32)-bit)"
            case .scalar: return "Accelerate (scalar fallback)"
            }
            #elseif canImport(Accelerate)
            // J2KAccelerate (the SIMD-family probe) was removed in J2KSwift v11.0.0,
            // but the Apple Accelerate framework — which `isAvailable(.accelerate)`
            // keys off — is still present, so this backend IS available. Report a
            // plain CPU label rather than the old, now-contradictory "not available".
            return "Accelerate (CPU)"
            #else
            return "Accelerate (not available)"
            #endif
        case .scalar:
            return "Scalar (pure Swift)"
        }
    }
}

// MARK: - CodecBackendProbe

/// Probes the current platform for the best available codec backend.
///
/// Results are cached on first access.  The probe runs once per process; it does
/// not respond to hardware changes (e.g., eGPU hot-plug) after startup.
public struct CodecBackendProbe: Sendable {

    /// The best codec backend available on the current platform.
    ///
    /// Priority: `metal` → `accelerate` → `scalar`.
    public static let bestAvailable: CodecBackend = {
        #if canImport(Metal)
        if J2KMetalDevice.isAvailable {
            return .metal
        }
        #endif
        #if canImport(Accelerate)
        return .accelerate
        #else
        return .scalar
        #endif
    }()

    /// Returns `true` if the given backend is available on this platform.
    public static func isAvailable(_ backend: CodecBackend) -> Bool {
        switch backend {
        case .metal:
            #if canImport(Metal)
            return J2KMetalDevice.isAvailable
            #else
            return false
            #endif
        case .accelerate:
            #if canImport(Accelerate)
            return true
            #else
            return false
            #endif
        case .scalar:
            return true
        }
    }

    /// Ranked list of available backends (best first).
    public static var availableBackends: [CodecBackend] {
        CodecBackend.allCases.filter { isAvailable($0) }
    }
}

// MARK: - CodecBackendPreference

/// Expresses a caller's preference for a specific codec backend.
///
/// When `forced` is non-nil the codec registry will attempt to honour it;
/// if the requested backend is unavailable the chain falls through to the
/// next available backend.  When `forced` is `nil` the best available
/// backend is used (default behaviour).
public struct CodecBackendPreference: Sendable {
    /// The backend preference.  `nil` means "auto" (best available).
    public var forced: CodecBackend?

    public init(forced: CodecBackend? = nil) {
        self.forced = forced
    }

    /// Auto: use the best available backend.
    public static let auto = CodecBackendPreference(forced: nil)

    /// Force Metal (falls back if unavailable).
    public static let metal = CodecBackendPreference(forced: .metal)

    /// Force Accelerate (falls back if unavailable).
    public static let accelerate = CodecBackendPreference(forced: .accelerate)

    /// Force scalar (always available).
    public static let scalar = CodecBackendPreference(forced: .scalar)

    /// Resolves the effective backend given the available options.
    ///
    /// If `forced` is set but unavailable, returns `bestAvailable`.
    ///
    /// - Note: This reports the best *available* hardware, not the backend a
    ///   particular encode will actually run on. Use
    ///   ``effectiveEncodeBackend(isLossless:isJPEG2000Family:)`` to account for
    ///   codec-family routing and automatic GPU selection.
    public var effective: CodecBackend {
        guard let f = forced else { return CodecBackendProbe.bestAvailable }
        return CodecBackendProbe.isAvailable(f) ? f : CodecBackendProbe.bestAvailable
    }

    /// The backend the JPEG 2000 / HTJ2K encoder will **actually** dispatch to —
    /// as opposed to ``effective``, which only reports the best *available*
    /// hardware.
    ///
    /// DICOMKit's encoder (`J2KSwiftCodec.encodeFrame`) dispatches to the Metal GPU
    /// for a JPEG 2000 / HTJ2K encode of **any** intent (lossy or lossless — the
    /// reversible GPU path is bit-exact since J2KSwift v11.0.1) when Metal is
    /// available AND the backend is either forced `.metal` **or** `auto` (Phase 5:
    /// `auto` now picks the GPU on Apple Silicon). `accelerate` / `scalar`, and every
    /// non-J2K codec, run on the CPU. The GPU dispatch policy is owned by
    /// `J2KRoutePlanner.shouldUseGPUEncode`, so the console-reported backend can
    /// never diverge from the encoder's actual choice.
    ///
    /// - Parameters:
    ///   - isLossless: Whether this encode is reversible (lossless).
    ///   - isJPEG2000Family: Whether the target syntax is JPEG 2000 / HTJ2K (the
    ///     only family with a GPU encode path).
    public func effectiveEncodeBackend(isLossless: Bool, isJPEG2000Family: Bool) -> CodecBackend {
        // The CPU path the encoder actually runs (`encoder.encode`): the best
        // available non-Metal backend, or an explicit accelerate/scalar choice.
        let cpuBackend = CodecBackendProbe.availableBackends.first { $0 != .metal } ?? .scalar
        let intent: J2KRoutePlanner.ResolvedIntent = isLossless ? .lossless : .lossy
        if isJPEG2000Family && J2KRoutePlanner.shouldUseGPUEncode(forced: forced, intent: intent) {
            // `shouldUseGPUEncode` honours a forced `.metal` request without checking
            // availability (the encoder falls back internally); the console must report
            // the *actual* backend, so downgrade to CPU when Metal is truly absent.
            return CodecBackendProbe.isAvailable(.metal) ? .metal : cpuBackend
        }
        // CPU path: an explicit accelerate/scalar keeps its identity; auto and a
        // Metal-absent forced-metal both resolve to the best available CPU backend.
        switch forced {
        case .accelerate, .scalar: return forced ?? cpuBackend
        default:                   return cpuBackend
        }
    }
}

// MARK: - CodecRegistry backend query extension

extension CodecRegistry {
    /// The best codec backend available on the current platform.
    public var activeBackend: CodecBackend {
        CodecBackendProbe.bestAvailable
    }

    /// Returns all backends available on this platform, best first.
    public var availableBackends: [CodecBackend] {
        CodecBackendProbe.availableBackends
    }

    /// Human-readable summary of the active hardware backend.
    public var backendDescription: String {
        activeBackend.displayName
    }
}
