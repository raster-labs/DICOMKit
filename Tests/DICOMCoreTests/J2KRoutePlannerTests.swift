// J2KRoutePlannerTests.swift
// DICOMCoreTests — JPEG 2000 / HTJ2K / Part-2 routing (Phase 1)
//
// Verifies the (type, intent, backend) → EncodePlan mapping that centralises all
// J2KSwift routing. Phase 1 asserts behaviour parity with the previous inline
// `makeEncodingConfiguration` + `encodeFrame` GPU gate. See
// J2K_ROUTING_ARCHITECTURE.md §5/§9 for the full matrix.

import Foundation
import Testing
@testable import DICOMCore

@Suite("J2KRoutePlanner Tests")
struct J2KRoutePlannerTests {

    // MARK: - Fixtures

    private func config(
        preferLossless: Bool = false,
        quality: CompressionQuality = .high,
        backend: CodecBackend? = nil
    ) -> CompressionConfiguration {
        CompressionConfiguration(
            quality: quality,
            preferLossless: preferLossless,
            forcedBackend: backend
        )
    }

    private typealias TS = TransferSyntax
    private typealias Planner = J2KRoutePlanner

    // MARK: - Compression type mapping

    @Test("compressionType maps every JPEG 2000 UID to its family")
    func test_compressionType_mapping() {
        #expect(Planner.compressionType(forUID: TS.jpeg2000Lossless.uid) == .part1)      // .90
        #expect(Planner.compressionType(forUID: TS.jpeg2000.uid) == .part1)              // .91
        #expect(Planner.compressionType(forUID: TS.jpeg2000Part2Lossless.uid) == .part2) // .92
        #expect(Planner.compressionType(forUID: TS.jpeg2000Part2.uid) == .part2)         // .93
        #expect(Planner.compressionType(forUID: TS.htj2kLossless.uid) == .htj2k)         // .201
        #expect(Planner.compressionType(forUID: TS.htj2kRPCLLossless.uid) == .htj2k)     // .202
        #expect(Planner.compressionType(forUID: TS.htj2kLossy.uid) == .htj2k)            // .203
    }

    @Test("compressionType defaults unknown / nil UIDs to Part-1")
    func test_compressionType_fallback() {
        #expect(Planner.compressionType(forUID: nil) == .part1)
        #expect(Planner.compressionType(forUID: "1.2.3.4.not.a.syntax") == .part1)
    }

    // MARK: - Three-state intent resolution

    @Test("both-capable UIDs honour preferLossless")
    func test_resolveIntent_bothCapable() {
        for uid in [TS.jpeg2000.uid, TS.jpeg2000Part2.uid, TS.htj2kLossy.uid] {
            #expect(Planner.resolveIntent(uid: uid, configuration: config(preferLossless: true)) == .lossless)
            #expect(Planner.resolveIntent(uid: uid, configuration: config(preferLossless: false)) == .lossy)
        }
    }

    @Test("dedicated lossless-only UIDs resolve to .losslessOnly regardless of config")
    func test_resolveIntent_losslessOnly() {
        for uid in [TS.jpeg2000Lossless.uid, TS.jpeg2000Part2Lossless.uid,
                    TS.htj2kLossless.uid, TS.htj2kRPCLLossless.uid] {
            #expect(Planner.resolveIntent(uid: uid, configuration: config(preferLossless: false)) == .losslessOnly)
            #expect(Planner.resolveIntent(uid: uid, configuration: config(preferLossless: true)) == .losslessOnly)
        }
    }

    @Test("unknown UID falls back to config flags")
    func test_resolveIntent_unknownUID() {
        #expect(Planner.resolveIntent(uid: nil, configuration: config(preferLossless: true)) == .lossless)
        #expect(Planner.resolveIntent(uid: nil, configuration: config(preferLossless: false, quality: .maximum)) == .lossless)
        #expect(Planner.resolveIntent(uid: nil, configuration: config(preferLossless: false, quality: .high)) == .lossy)
    }

    @Test("ResolvedIntent.isLossless is true for lossless and lossless-only")
    func test_intent_isLossless() {
        #expect(Planner.ResolvedIntent.lossy.isLossless == false)
        #expect(Planner.ResolvedIntent.lossless.isLossless == true)
        #expect(Planner.ResolvedIntent.losslessOnly.isLossless == true)
    }

    // MARK: - Structural flags (Phase-1 parity)

    @Test("HTJ2K syntaxes set useHTJ2K + conformant block format")
    func test_planEncode_htj2k_flags() {
        for uid in [TS.htj2kLossless.uid, TS.htj2kRPCLLossless.uid, TS.htj2kLossy.uid] {
            let plan = Planner.planEncode(transferSyntaxUID: uid, configuration: config())
            #expect(plan.useHTJ2K == true)
            #expect(plan.blockFormat == .conformant)
        }
    }

    @Test("Part-1 and Part-2 syntaxes do not use HTJ2K and use custom block format")
    func test_planEncode_part1_part2_flags() {
        for uid in [TS.jpeg2000Lossless.uid, TS.jpeg2000.uid,
                    TS.jpeg2000Part2Lossless.uid, TS.jpeg2000Part2.uid] {
            let plan = Planner.planEncode(transferSyntaxUID: uid, configuration: config())
            #expect(plan.useHTJ2K == false)
            #expect(plan.blockFormat == .custom)
        }
    }

    @Test("lossless intents set reversible filter and quality 1.0")
    func test_planEncode_lossless_flags() {
        // lossless-only UID
        let onlyPlan = Planner.planEncode(transferSyntaxUID: TS.jpeg2000Lossless.uid, configuration: config())
        #expect(onlyPlan.intent == .losslessOnly)
        #expect(onlyPlan.lossless == true)
        #expect(onlyPlan.useReversibleFilter == true)
        #expect(onlyPlan.quality == 1.0)

        // both-capable UID with lossless intent
        let bothPlan = Planner.planEncode(transferSyntaxUID: TS.jpeg2000.uid, configuration: config(preferLossless: true))
        #expect(bothPlan.intent == .lossless)
        #expect(bothPlan.lossless == true)
        #expect(bothPlan.useReversibleFilter == true)
        #expect(bothPlan.quality == 1.0)
    }

    @Test("lossy intent uses irreversible filter and the config quality value")
    func test_planEncode_lossy_flags() {
        let cfg = config(preferLossless: false, quality: .high)
        let plan = Planner.planEncode(transferSyntaxUID: TS.jpeg2000.uid, configuration: cfg)
        #expect(plan.intent == .lossy)
        #expect(plan.lossless == false)
        #expect(plan.useReversibleFilter == false)
        #expect(plan.quality == cfg.quality.value)
    }

    @Test("Progression is RPCL across selectable syntaxes and Part-2 MCT is enabled only for Part-2 syntaxes")
    func test_planEncode_progression_and_part2_mct() {
        for uid in TS.selectableEncodings.map(\.uid) where TransferSyntax.from(uid: uid)?.isJPEG2000 == true {
            let plan = Planner.planEncode(transferSyntaxUID: uid, configuration: config(preferLossless: true))
            #expect(plan.progression == .rpcl)
            #expect(plan.enablePart2MCT == (plan.type == .part2))
        }
    }

    // MARK: - Part-2 capability (SwiftJ2K 12.1.0+)

    @Test("Part-2 MCT decode is supported on SwiftJ2K")
    func test_part2_decode_supported() {
        #expect(J2KRoutePlanner.part2MCTDecodeSupported == true)
    }

    @Test("Part-2, Part-1, and HTJ2K encode are all supported")
    func test_part2_encode_supported() {
        for uid in [TS.jpeg2000Part2Lossless.uid, TS.jpeg2000Part2.uid] {
            #expect(J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: uid) == nil)
            let plan = Planner.planEncode(transferSyntaxUID: uid, configuration: config(preferLossless: true))
            #expect(plan.type == .part2)
            #expect(plan.enablePart2MCT == true)
        }
        // Part-1 and HTJ2K remain fully supported (nil reason).
        for uid in [TS.jpeg2000Lossless.uid, TS.jpeg2000.uid,
                    TS.htj2kLossless.uid, TS.htj2kRPCLLossless.uid, TS.htj2kLossy.uid] {
            #expect(J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: uid) == nil)
        }
    }

    // MARK: - GPU backend gate

    @Test("GPU encode eligibility admits all intents (Phase-2 policy)")
    func test_gpuEncodeEligible_policy() {
        #expect(Planner.gpuEncodeEligible(intent: .lossy) == true)
        #expect(Planner.gpuEncodeEligible(intent: .lossless) == true)
        #expect(Planner.gpuEncodeEligible(intent: .losslessOnly) == true)
    }

    @Test("useGPU when Metal is forced, for lossy AND lossless (Phase-2)")
    func test_planEncode_useGPU_gate() {
        // Metal + lossy → GPU
        let lossyMetal = Planner.planEncode(
            transferSyntaxUID: TS.jpeg2000.uid,
            configuration: config(preferLossless: false, backend: .metal))
        #expect(lossyMetal.useGPU == true)

        // Metal + lossless (both-capable) → GPU (Phase-2: reversible GPU is bit-exact)
        let losslessMetal = Planner.planEncode(
            transferSyntaxUID: TS.jpeg2000.uid,
            configuration: config(preferLossless: true, backend: .metal))
        #expect(losslessMetal.useGPU == true)

        // Metal + lossless-only → GPU
        let losslessOnlyMetal = Planner.planEncode(
            transferSyntaxUID: TS.jpeg2000Lossless.uid,
            configuration: config(backend: .metal))
        #expect(losslessOnlyMetal.useGPU == true)

        // Auto (nil forced) → GPU iff Metal is available (Phase 5)
        let lossyAuto = Planner.planEncode(
            transferSyntaxUID: TS.jpeg2000.uid,
            configuration: config(preferLossless: false, backend: nil))
        #expect(lossyAuto.useGPU == CodecBackendProbe.isAvailable(.metal))

        // Accelerate / scalar forced → CPU regardless of intent
        for backend: CodecBackend in [.accelerate, .scalar] {
            let plan = Planner.planEncode(
                transferSyntaxUID: TS.jpeg2000.uid,
                configuration: config(preferLossless: false, backend: backend))
            #expect(plan.useGPU == false)
        }
    }

    // MARK: - Decode plan (Phase 4)

    @Test("planDecode honours backend and size band")
    func test_planDecode() {
        let metal = CodecBackendProbe.isAvailable(.metal)
        // Forced Metal → GPU decode when available, else CPU.
        #expect(Planner.planDecode(backend: .metal, pixelCount: 1_000_000) == (metal ? .gpu : .cpu))
        // Accelerate / scalar → always CPU.
        #expect(Planner.planDecode(backend: .accelerate, pixelCount: 1_000_000) == .cpu)
        #expect(Planner.planDecode(backend: .scalar, pixelCount: 4_000_000) == .cpu)
        // Auto → GPU only inside the 0.5–15 MP band, and only with Metal.
        #expect(Planner.planDecode(backend: nil, pixelCount: 100_000) == .cpu)          // too small
        #expect(Planner.planDecode(backend: nil, pixelCount: 20_000_000) == .cpu)       // too large
        #expect(Planner.planDecode(backend: nil, pixelCount: 4_000_000) == (metal ? .gpu : .cpu))
    }
}
