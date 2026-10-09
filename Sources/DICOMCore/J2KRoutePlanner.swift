// J2KRoutePlanner.swift
// DICOMCore — JPEG 2000 / HTJ2K / Part-2 encode+decode routing
//
// Single source of truth mapping the user's three independent choices —
// backend (CPU/GPU), intent (lossy/lossless/lossless-only), and compression
// type (Part-1 / HTJ2K / Part-2) — onto a concrete J2KSwift encode/decode plan.
//
// See J2K_ROUTING_ARCHITECTURE.md for the full design + verification matrix.
//
// This type has **no dependency on the J2KCodec module**: it produces a plan
// expressed in DICOMCore-native enums, and `J2KSwiftCodec` translates that plan
// into a `J2KEncodingConfiguration`. That keeps the routing policy testable on
// every platform (including builds without J2KSwift) and isolates the one place
// that must change as later phases widen GPU coverage and add real Part-2.
// NEMA-verified: 2026a, checked 2026-09-25 — the UID family groupings (.90/.91 JPEG 2000 Part 1, .92/.93 Part 2 Multi-component, .201/.202/.203 High-Throughput JPEG 2000, .202 with RPCL) match PS3.6 2026a Table A-1 and the lossless-only / general split of PS3.5 2026a A.4.4; no other standard data. C1 classification confirmed.

import Foundation

/// Resolves (transfer-syntax, intent, backend) into a concrete encode/decode plan.
public enum J2KRoutePlanner {

    // MARK: - Axes

    /// The JPEG 2000 family a transfer syntax belongs to.
    public enum CompressionType: String, Sendable, Hashable, CaseIterable {
        /// JPEG 2000 Part-1 (EBCOT) — UIDs `.90` / `.91`.
        case part1
        /// HTJ2K / JPEG 2000 Part-15 (FBCOT) — UIDs `.201` / `.202` / `.203`.
        case htj2k
        /// JPEG 2000 Part-2 Multi-component — UIDs `.92` / `.93`.
        case part2
    }

    /// The three distinct intent states (see architecture doc §4).
    ///
    /// `lossless` and `losslessOnly` produce identical codestream bytes for a
    /// given type — they differ only in the stamped transfer-syntax UID (and,
    /// for `.202`, the mandated RPCL progression). The distinction is preserved
    /// because a `.losslessOnly` UID *asserts* mathematical losslessness to the
    /// DICOM receiver, while a `.both` UID does not.
    public enum ResolvedIntent: String, Sendable, Hashable, CaseIterable {
        /// Irreversible, quality/rate driven — carried by a `.both`-capable UID.
        case lossy
        /// Reversible, carried by a `.both`-capable UID (`.91` / `.93` / `.203`).
        case lossless
        /// Reversible, carried by a dedicated lossless-only UID (`.90` / `.92` / `.201` / `.202`).
        case losslessOnly

        /// Whether this intent produces a reversible (lossless) codestream.
        public var isLossless: Bool { self != .lossy }
    }

    /// HTJ2K block-coding wire format (maps to `J2KCodec.HTBlockFormat`).
    public enum BlockFormatPlan: String, Sendable, Hashable {
        /// ISO/IEC 15444-15 conformant layout (OpenJPH-interoperable). Used for HTJ2K.
        case conformant
        /// J2KSwift private layout. Used for Part-1 / Part-2 (block format is irrelevant there).
        case custom
    }

    /// Codestream progression order (maps to `J2KCodec.J2KProgressionOrder`).
    public enum ProgressionPlan: String, Sendable, Hashable {
        case rpcl
        case lrcp
    }

    // MARK: - Encode plan

    /// A fully-resolved encode plan. `J2KSwiftCodec` translates this into a
    /// `J2KEncodingConfiguration` and picks the `encode` vs `encodeGPU` API.
    public struct EncodePlan: Sendable, Hashable {
        public let type: CompressionType
        public let intent: ResolvedIntent
        /// `true` for lossless / lossless-only.
        public let lossless: Bool
        /// Reversible 5/3 filter (true) vs irreversible 9/7 (false).
        public let useReversibleFilter: Bool
        /// Emit the Part-15 HTJ2K codestream (CAP+CPF markers).
        public let useHTJ2K: Bool
        /// HTJ2K block wire format.
        public let blockFormat: BlockFormatPlan
        /// Codestream progression order.
        public let progression: ProgressionPlan
        /// Whether to configure a Part-2 multi-component transform.
        /// **Phase 3** wires this; Phase 1 always emits `false` (behaviour parity).
        public let enablePart2MCT: Bool
        /// Quality value for lossy encodes; `1.0` for lossless.
        public let quality: Double
        /// Whether to dispatch the J2KSwift GPU encode path (`encodeGPU`).
        public let useGPU: Bool

        public init(
            type: CompressionType,
            intent: ResolvedIntent,
            lossless: Bool,
            useReversibleFilter: Bool,
            useHTJ2K: Bool,
            blockFormat: BlockFormatPlan,
            progression: ProgressionPlan,
            enablePart2MCT: Bool,
            quality: Double,
            useGPU: Bool
        ) {
            self.type = type
            self.intent = intent
            self.lossless = lossless
            self.useReversibleFilter = useReversibleFilter
            self.useHTJ2K = useHTJ2K
            self.blockFormat = blockFormat
            self.progression = progression
            self.enablePart2MCT = enablePart2MCT
            self.quality = quality
            self.useGPU = useGPU
        }
    }

    // MARK: - Type / intent resolution

    /// The compression family a transfer-syntax UID belongs to. Unknown / nil UIDs
    /// default to Part-1 (the historical fallback in `makeEncodingConfiguration`).
    public static func compressionType(forUID uid: String?) -> CompressionType {
        guard let ts = uid.flatMap(TransferSyntax.from(uid:)) else { return .part1 }
        if ts.isHTJ2K { return .htj2k }
        if ts.isJPEG2000Part2 { return .part2 }
        return .part1
    }

    /// Resolves the three-state intent from the UID's lossless capability and the
    /// caller's configuration.
    ///
    /// - `.both` UID (`.91`/`.93`/`.203`): `preferLossless` picks `.lossless` vs `.lossy`.
    /// - `.losslessOnly` UID (`.90`/`.92`/`.201`/`.202`): always `.losslessOnly`.
    /// - `.lossyOnly` UID: always `.lossy`.
    /// - unknown / nil UID: falls back to the config flags (`.lossless` if either
    ///   `preferLossless` or `quality.isLossless`).
    public static func resolveIntent(
        uid: String?,
        configuration: CompressionConfiguration
    ) -> ResolvedIntent {
        let ts = uid.flatMap(TransferSyntax.from(uid:))
        switch ts?.losslessCapability {
        case .some(.both):
            return configuration.preferLossless ? .lossless : .lossy
        case .some(.losslessOnly):
            return .losslessOnly
        case .some(.lossyOnly):
            return .lossy
        case .none:
            return (configuration.preferLossless || configuration.quality.isLossless) ? .lossless : .lossy
        }
    }

    // MARK: - Part-2 capability

    /// Whether the pinned J2KSwift can **decode** a genuine JPEG 2000 Part-2
    /// codestream (multi-component transform / arbitrary wavelet) back to correct
    /// pixels via the stateless `J2KDecoder().decode(_:)` path DICOMKit uses.
    ///
    /// **Currently `false` for J2KSwift v11.0.2.** The library emits Part-2 CAP/MCT
    /// markers on encode but its decoder does not parse MCT/MCC/MCO/ADS markers and
    /// never self-configures the wavelet kernel from the codestream. An empirical
    /// probe (encode an RGB image with a non-identity array-based MCT, decode via
    /// `decode(_:)`) produced a **max abs pixel error of 253/255** — the forward MCT
    /// is applied on encode but never inverted on decode. A lossless Part-2 MCT
    /// encode therefore corrupts pixels and would (correctly) trip
    /// `J2KSwiftCodec.verifyEncodedRoundTrip`.
    ///
    /// Consequently, DICOMKit does **not** emit real Part-2 features: a `.92`/`.93`
    /// request is encoded as a valid, decodable Part-1-compatible codestream carrying
    /// the Part-2 UID (pixels are exact; the multi-component decorrelation is simply
    /// not applied). Flip this flag to `true` — and wire `mctConfiguration` in
    /// `planEncode` — only once a J2KSwift release lands a self-configuring Part-2
    /// decode path and a bit-exact round-trip test proves it.
    public static let part2MCTDecodeSupported = false

    /// A user-facing reason string when encoding to `transferSyntaxUID` is **not
    /// supported**, or `nil` when it is. Currently the only unsupported target is
    /// JPEG 2000 Part-2 (`.92`/`.93`) while `part2MCTDecodeSupported` is `false`:
    /// the pinned decoder cannot invert the Part-2 multi-component transform, so a
    /// Part-2 codestream would not decode correctly and DICOMKit refuses to create
    /// one rather than emit an image that cannot be read back (see §14 of
    /// J2K_ROUTING_ARCHITECTURE.md).
    public static func unsupportedEncodeReason(transferSyntaxUID uid: String?) -> String? {
        guard compressionType(forUID: uid) == .part2, !part2MCTDecodeSupported else { return nil }
        let name = uid.flatMap(TransferSyntax.from(uid:))?.displayName ?? "JPEG 2000 Part 2"
        return "\(name) (\(uid ?? "unknown UID")) encoding is not supported: the JPEG 2000 "
            + "Part-2 multi-component transform cannot be inverted by the current decoder, so the "
            + "resulting codestream would not decode correctly. Use JPEG 2000 Part 1 "
            + "(lossless .90 / general .91) or HTJ2K (.201 / .202 / .203) instead."
    }

    /// A user-facing reason why `frameData` cannot be **decoded**, or `nil` when it
    /// can. Currently the only rejection is a codestream carrying a genuine Part-2
    /// multi-component transform while `part2MCTDecodeSupported` is `false`.
    ///
    /// This is the read-side counterpart to `unsupportedEncodeReason`. DICOMKit never
    /// *writes* such a codestream, but a third-party encoder (Kakadu, OpenJPEG, …)
    /// can, and the pinned decoder skips MCT/MCC/MCO markers outright rather than
    /// failing — it would hand back forward-transformed samples that were never
    /// inverted. For medical pixel data, a loud error is the only safe outcome:
    /// silently-wrong pixels are worse than no pixels.
    ///
    /// Part-2 codestreams *without* multi-component markers (including the
    /// Part-1-compatible ones DICOMKit itself writes under a `.92`/`.93` UID) decode
    /// correctly and are deliberately still accepted, so existing files keep opening.
    public static func unsupportedDecodeReason(frameData: Data) -> String? {
        guard !part2MCTDecodeSupported else { return nil }
        let markers = J2KCodestreamInspector.part2MultiComponentMarkers(in: frameData)
        guard !markers.isEmpty else { return nil }
        let names = markers.map(\.name).joined(separator: ", ")
        return "This JPEG 2000 codestream uses a Part-2 multi-component transform "
            + "(\(names) marker\(markers.count == 1 ? "" : "s") present), which the current decoder "
            + "cannot invert. Decoding would silently produce incorrect pixel values, so it has "
            + "been refused. Re-encode the source as JPEG 2000 Part 1 (lossless .90 / general .91) "
            + "or HTJ2K (.201 / .202 / .203)."
    }

    // MARK: - Backend policy

    /// Which intents are eligible for the J2KSwift **GPU encode** path.
    ///
    /// **Phase 2 policy: all intents eligible.** GPU encode is enabled for lossy,
    /// lossless, and lossless-only. The historical lossy-only gate existed because
    /// J2KSwift v11.0.0 shipped a corrupting reversible GPU encoder; that was fixed
    /// in v11.0.1 and the reversible GPU path is now bit-exact (proven by
    /// `J2KGPUEncodeCorrectnessTests` — lossless grayscale + RGB byte-identical to
    /// CPU). Two backstops remain regardless:
    ///
    /// 1. `J2KSwiftCodec.verifyEncodedRoundTrip` decodes every lossless encode and
    ///    byte-compares against the original — a non-bit-exact result throws rather
    ///    than emitting corrupt DICOM.
    /// 2. The dominant lossless GPU win (the forward 5/3 DWT) is a stage-level step
    ///    inside J2KSwift's shared wavelet transform, gated by `J2K_GPU_FORWARD_53`
    ///    (default-on, ≥ 3 MP). It already fires under the CPU `encode()` entry, so
    ///    routing lossless through `encodeGPU()` additionally moves the reversible
    ///    colour transform (RCT) to the GPU for multi-component images.
    public static func gpuEncodeEligible(intent: ResolvedIntent) -> Bool {
        // Intent no longer restricts GPU eligibility. Kept as a function so a
        // future phase can reintroduce a size/threshold gate here if needed.
        switch intent {
        case .lossy, .lossless, .losslessOnly:
            return true
        }
    }

    /// Whether the encode should dispatch to the J2KSwift GPU path for the given
    /// backend preference + intent.
    ///
    /// - `forced == .metal`: GPU whenever the intent is eligible (all intents since
    ///   Phase 2). Honours the explicit request regardless of frame size — J2KSwift's
    ///   `encodeGPU` / forward-5/3 stages fall back to CPU internally below their own
    ///   thresholds, so small frames stay correct and merely skip the GPU win.
    /// - `forced == nil` (**auto**, Phase 5): GPU when Metal is actually available on
    ///   this platform (Apple Silicon / eligible GPU) and the intent is eligible.
    /// - `.accelerate` / `.scalar`: never GPU.
    public static func shouldUseGPUEncode(forced: CodecBackend?, intent: ResolvedIntent) -> Bool {
        guard gpuEncodeEligible(intent: intent) else { return false }
        switch forced {
        case .metal:
            return true
        case nil:
            return CodecBackendProbe.isAvailable(.metal)
        case .accelerate, .scalar:
            return false
        }
    }

    // MARK: - Decode plan

    /// The J2KSwift decode API to dispatch to.
    public enum DecodeAPI: String, Sendable, Hashable {
        /// `J2KDecoder.decode(_:)` — full CPU pipeline.
        case cpu
        /// `J2KDecoder.decodeGPU(_:)` — GPU inverse DWT + colour + quant, CPU HT entropy.
        case gpu
        /// `J2KDecoder.decodeWithGPUHT(_:)` — additionally GPU HT entropy.
        case gpuHT
    }

    /// Chooses the decode API for a backend preference + image size.
    ///
    /// Mirrors J2KSwift's own `recommendedDecodeAPI` size band (GPU wins roughly
    /// between 0.5 MP and 15 MP; outside that CPU is faster). `gpuHT` is not selected
    /// automatically — GPU HT-entropy decode is default-off upstream for performance
    /// on current Apple silicon and is left as an explicit future opt-in.
    ///
    /// - `forced == .metal`: honour the request → `.gpu` when Metal is available.
    /// - `forced == nil` (**auto**): `.gpu` inside the size band when Metal is
    ///   available, else `.cpu`.
    /// - `.accelerate` / `.scalar`: always `.cpu`.
    public static func planDecode(backend: CodecBackend?, pixelCount: Int) -> DecodeAPI {
        let metalAvailable = CodecBackendProbe.isAvailable(.metal)
        switch backend {
        case .metal:
            return metalAvailable ? .gpu : .cpu
        case nil:
            guard metalAvailable else { return .cpu }
            return (pixelCount >= 500_000 && pixelCount < 15_000_000) ? .gpu : .cpu
        case .accelerate, .scalar:
            return .cpu
        }
    }

    // MARK: - Plan

    /// Builds the full encode plan for a transfer syntax + configuration.
    ///
    /// Structural flags follow the §5 routing matrix: RPCL progression, conformant
    /// block format for HTJ2K, Part-2 MCT gated by `part2MCTDecodeSupported`. GPU
    /// dispatch follows `shouldUseGPUEncode` (forced Metal, or auto on Metal HW).
    public static func planEncode(
        transferSyntaxUID uid: String?,
        configuration: CompressionConfiguration
    ) -> EncodePlan {
        let type = compressionType(forUID: uid)
        let intent = resolveIntent(uid: uid, configuration: configuration)
        let lossless = intent.isLossless
        let useHTJ2K = (type == .htj2k)

        // DICOM HTJ2K syntaxes reference ISO/IEC 15444-15 — emit the conformant
        // block layout so codestreams interoperate with OpenJPH / Part-15 PACS.
        let blockFormat: BlockFormatPlan = useHTJ2K ? .conformant : .custom

        // Phase 1: RPCL everywhere (matches prior behaviour and satisfies the
        // `.202` RPCL requirement). Per-route progression lands in a later phase.
        let progression: ProgressionPlan = .rpcl

        // Real Part-2 multi-component transform is gated on the pinned library
        // being able to DECODE it (see `part2MCTDecodeSupported`). Until then a
        // Part-2 UID is encoded as a Part-1-compatible codestream — pixels are
        // exact and decodable; only the (currently un-decodable) MCT is skipped.
        let enablePart2MCT = (type == .part2) && part2MCTDecodeSupported

        let quality = lossless ? 1.0 : configuration.quality.value

        let useGPU = shouldUseGPUEncode(forced: configuration.forcedBackend, intent: intent)

        return EncodePlan(
            type: type,
            intent: intent,
            lossless: lossless,
            useReversibleFilter: lossless,
            useHTJ2K: useHTJ2K,
            blockFormat: blockFormat,
            progression: progression,
            enablePart2MCT: enablePart2MCT,
            quality: quality,
            useGPU: useGPU
        )
    }
}
