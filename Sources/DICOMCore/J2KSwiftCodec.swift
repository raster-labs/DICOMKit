import Foundation

#if canImport(J2KCore) && canImport(J2KCodec)
import J2KCore
import J2KCodec
#endif

#if canImport(Accelerate)
import Accelerate
#endif

/// Selects which J2KSwift decode API the J2K Compare panel exercises.
/// The viewer's production decode path is unaffected — it always uses the
/// runtime size router via `J2KSwiftCodec.decodeFrame`.
public enum J2KSwiftDecodeMode: String, Sendable, CaseIterable, Identifiable {
    /// `J2KDecoder.decode(...)` — pure-CPU path. Matches the methodology of
    /// J2KSwift's `CROSS_HOST_*_inproc.md` benchmark reports.
    case cpu
    /// `J2KDecoder.decodeGPU(...)` — CPU HT entropy + GPU IDWT.
    case decodeGPU
    /// `J2KDecoder.decodeWithGPUHT(...)` — full GPU pipeline (HT entropy on GPU).
    case decodeWithGPUHT

    public var id: String { rawValue }

    /// Short label suitable for a Picker / row tag.
    public var label: String {
        switch self {
        case .cpu:              return "CPU `decode`"
        case .decodeGPU:        return "`decodeGPU`"
        case .decodeWithGPUHT:  return "`decodeWithGPUHT`"
        }
    }
}

/// Selects which J2KSwift encode API the J2K Compare panel exercises.
/// J2KSwift exposes no `recommendedEncodeAPI` router, so the choice is binary.
public enum J2KSwiftEncodeMode: String, Sendable, CaseIterable, Identifiable {
    /// `J2KEncoder.encode(...)` — CPU path. Matches the published bench.
    case cpu
    /// `J2KEncoder.encodeGPU(...)` — GPU-accelerated encode.
    case gpu

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .cpu: return "CPU `encode`"
        case .gpu: return "`encodeGPU`"
        }
    }
}

/// JPEG 2000 codec adapter backed directly by J2KSwift.
///
/// This provides the Phase 1 pure-Swift JPEG 2000 path for DICOMKit and establishes
/// the foundation for HTJ2K and Part 2 expansion without masking upstream codec issues.
/// NEMA-verified: 2026a, checked 2026-09-25 — JPEG 2000 / HTJ2K UIDs come from `TransferSyntax` (PS3.6 2026a Table A-1); the lossless-only set (.90, .92, .201, .202) and the RPCL requirement for .202 match PS3.5 2026a A.4.4. One citation said A.4.6 (MPEG-4); corrected. The codec itself implements ISO/IEC 15444, outside DICOM.
public struct J2KSwiftCodec: ImageCodec, ImageEncoder, Sendable {
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.jpeg2000Lossless.uid,
        TransferSyntax.jpeg2000.uid,
        TransferSyntax.jpeg2000Part2Lossless.uid,
        TransferSyntax.jpeg2000Part2.uid,
        TransferSyntax.htj2kLossless.uid,
        TransferSyntax.htj2kRPCLLossless.uid,
        TransferSyntax.htj2kLossy.uid
    ]

    /// Encoding targets DICOMKit can actually produce. Part-2 (`.92`/`.93`) is
    /// **excluded** while the library cannot decode it (see
    /// `J2KRoutePlanner.unsupportedEncodeReason`); decoding of Part-2 remains in
    /// `supportedTransferSyntaxes` so previously-written files can still be read.
    ///
    /// That read path is UID-level only. A `.92`/`.93` frame whose codestream carries
    /// a real multi-component transform is rejected at decode time by
    /// `J2KRoutePlanner.unsupportedDecodeReason`, since the pinned decoder ignores
    /// MCT/MCC/MCO rather than inverting them.
    public static let supportedEncodingTransferSyntaxes: [String] = supportedTransferSyntaxes.filter {
        J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: $0) == nil
    }

    private let encodingTransferSyntaxUID: String?

    /// Backend preference applied on **decode** (Phase 4). `nil` → auto (the size
    /// router picks GPU inverse-DWT on Metal hardware for mid-size frames, else CPU);
    /// `.metal` → GPU decode; `.accelerate` / `.scalar` → CPU.
    private let decodeBackend: CodecBackend?

    /// The transfer syntax this decoder instance serves, when known.
    ///
    /// The registry wires one instance per syntax. Under a lossless-only syntax
    /// (`losslessOnlyTransferSyntaxes`) a codestream whose COD/COC selects the
    /// irreversible 9/7 wavelet is refused before decoding: its samples are not
    /// the encoder's input, which the syntax promises. `nil` (the default)
    /// decodes any Part-1 / HTJ2K codestream.
    private let decodingTransferSyntaxUID: String?

    /// Transfer syntaxes whose name promises exact reconstruction (PS3.5 A.4.4,
    /// A.4.6). A reversible 5/3 codestream that was rate-truncated is still
    /// undetectable here; only the wavelet kernel is checked.
    public static let losslessOnlyTransferSyntaxes: Set<String> = [
        TransferSyntax.jpeg2000Lossless.uid,
        TransferSyntax.jpeg2000Part2Lossless.uid,
        TransferSyntax.htj2kLossless.uid,
        TransferSyntax.htj2kRPCLLossless.uid
    ]

    public init(
        encodingTransferSyntaxUID: String? = nil,
        decodeBackend: CodecBackend? = nil,
        decodingTransferSyntaxUID: String? = nil
    ) {
        self.encodingTransferSyntaxUID = encodingTransferSyntaxUID
        self.decodeBackend = decodeBackend
        self.decodingTransferSyntaxUID = decodingTransferSyntaxUID
    }

    /// The refusal for an irreversible codestream under a lossless-only syntax,
    /// or `nil` when `transferSyntaxUID` is not lossless-only or the codestream
    /// uses the reversible 5/3 wavelet throughout.
    public static func irreversibleWaveletRefusal(frameData: Data, transferSyntaxUID: String?) -> String? {
        guard let uid = transferSyntaxUID, losslessOnlyTransferSyntaxes.contains(uid),
              J2KCodestreamInspector.usesIrreversibleWavelet(in: frameData) else { return nil }
        return "JPEG 2000 codestream selects the irreversible 9/7 wavelet under lossless-only transfer syntax "
            + "\(uid); refusing to decode inexact samples"
    }

    /// Explicit J2KSwift decode entry point selectable by mode. Bypasses the
    /// size-based router used by `decodeFrame`. Used by the J2K Compare panel
    /// to switch between the CPU `decode(...)`, `decodeGPU(...)`, and
    /// `decodeWithGPUHT(...)` APIs, or to fall back to the runtime auto-router.
    /// Production decode in the viewer should continue using `decodeFrame`.
    public static func decode(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        mode: J2KSwiftDecodeMode
    ) throws -> Data {
        #if canImport(J2KCore) && canImport(J2KCodec)
        // Mirrors the guard in `decodeWithJ2KSwift`: no J2KSwift decode API inverts a
        // Part-2 multi-component transform, so pinning one here doesn't make it safe.
        if let reason = J2KRoutePlanner.unsupportedDecodeReason(frameData: frameData) {
            throw DICOMError.unsupportedTransferSyntax(reason)
        }

        let decoder = J2KDecoder()
        let image: J2KImage
        do {
            image = try Self.awaitJ2KResult {
                switch mode {
                case .cpu:             return try await decoder.decode(frameData)
                case .decodeGPU:       return try await decoder.decodeGPU(frameData)
                case .decodeWithGPUHT: return try await decoder.decodeWithGPUHT(frameData)
                }
            }
        } catch {
            throw DICOMError.parsingFailed("J2KSwift decode failed: \(error)")
        }
        guard image.width == descriptor.columns, image.height == descriptor.rows else {
            throw DICOMError.parsingFailed(
                "Decoded image dimensions (\(image.width)x\(image.height)) do not match expected (\(descriptor.columns)x\(descriptor.rows))"
            )
        }
        return try packPixels(from: image, descriptor: descriptor)
        #else
        throw DICOMError.unsupportedTransferSyntax("JPEG 2000 requires J2KSwift support in this build")
        #endif
    }

    /// Explicit J2KSwift encode entry point selectable by mode. Mirrors the
    /// `J2KEncoder.encode(...)` (CPU) and `J2KEncoder.encodeGPU(...)` APIs.
    /// Used by the J2K Compare panel; production encode in DICOMKit still goes
    /// through `encodeFrame` on a `J2KSwiftCodec` instance.
    public static func encode(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        transferSyntaxUID: String,
        configuration: CompressionConfiguration,
        mode: J2KSwiftEncodeMode
    ) throws -> Data {
        #if canImport(J2KCore) && canImport(J2KCodec)
        let image = try Self.makeJ2KImage(from: frameData, descriptor: descriptor)
        let encoder = J2KEncoder(
            encodingConfiguration: Self.makeEncodingConfiguration(
                from: configuration,
                transferSyntaxUID: transferSyntaxUID,
                descriptor: descriptor
            )
        )
        let encoded = try Self.awaitJ2KResult {
            switch mode {
            case .cpu: return try await encoder.encode(image)
            case .gpu: return try await encoder.encodeGPU(image)
            }
        }
        return Self.conformingCodestream(encoded, transferSyntaxUID: transferSyntaxUID)
        #else
        throw DICOMError.unsupportedTransferSyntax("JPEG 2000 encoding requires J2KSwift support in this build")
        #endif
    }

    /// Benchmark-style encode: holds **one** `J2KEncoder` and image across all
    /// warmups + timed iterations, mirroring `J2KSwift/Sources/J2KCLI/InProcBench.swift`.
    /// Creating a fresh encoder per iteration can race against
    /// `HTBlockEncoderConformant.useNEONHotPath`'s `dispatch_once` init under
    /// HT-J2K configs and crash inside `applyEntropyCodingHTJ2KFused`.
    ///
    /// Returns the encoded payload (last iteration), all timed-sample ms, and
    /// an optional error string. `samples` has `runs` entries on success.
    public static func benchEncode(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        transferSyntaxUID: String,
        configuration: CompressionConfiguration,
        mode: J2KSwiftEncodeMode,
        warmups: Int,
        runs: Int
    ) -> (data: Data?, samples: [Double], error: String?) {
        #if canImport(J2KCore) && canImport(J2KCodec)
        // Honour the same block `encodeFrame` enforces. Benchmarking a target the
        // library cannot produce would otherwise silently measure a *substitute*
        // codestream: `planEncode` downgrades a Part-2 UID to a Part-1-compatible
        // stream, which round-trips bit-exactly and reads as a pass for a feature
        // that is in fact switched off.
        if let reason = J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: transferSyntaxUID) {
            return (nil, [], reason)
        }

        let image: J2KImage
        do {
            image = try Self.makeJ2KImage(from: frameData, descriptor: descriptor)
        } catch {
            return (nil, [], error.localizedDescription)
        }
        let encoder = J2KEncoder(
            encodingConfiguration: Self.makeEncodingConfiguration(
                from: configuration,
                transferSyntaxUID: transferSyntaxUID,
                descriptor: descriptor
            )
        )
        do {
            let output = try Self.awaitJ2KResult { () -> (Data?, [Double]) in
                var lastOut: Data? = nil
                var samples: [Double] = []
                samples.reserveCapacity(runs)
                for _ in 0..<warmups {
                    switch mode {
                    case .cpu: lastOut = try await encoder.encode(image)
                    case .gpu: lastOut = try await encoder.encodeGPU(image)
                    }
                }
                for _ in 0..<runs {
                    let t0 = DispatchTime.now()
                    switch mode {
                    case .cpu: lastOut = try await encoder.encode(image)
                    case .gpu: lastOut = try await encoder.encodeGPU(image)
                    }
                    samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0)
                }
                return (lastOut, samples)
            }
            return (output.0, output.1, nil)
        } catch {
            return (nil, [], error.localizedDescription)
        }
        #else
        return (nil, [], "JPEG 2000 encoding requires J2KSwift support in this build")
        #endif
    }

    /// Benchmark-style decode: holds **one** `J2KDecoder` across all warmups
    /// + timed iterations. `mode` selects the decode API explicitly.
    public static func benchDecode(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        mode: J2KSwiftDecodeMode,
        warmups: Int,
        runs: Int
    ) -> (data: Data?, samples: [Double], error: String?) {
        #if canImport(J2KCore) && canImport(J2KCodec)
        // Same guard as the production decode paths: a Part-2 multi-component
        // transform is skipped rather than inverted, so timing it would report a
        // throughput number for pixels that are silently wrong.
        if let reason = J2KRoutePlanner.unsupportedDecodeReason(frameData: frameData) {
            return (nil, [], reason)
        }

        let decoder = J2KDecoder()
        let output: (J2KImage?, [Double])
        do {
            output = try Self.awaitJ2KResult { () -> (J2KImage?, [Double]) in
                @inline(__always) func runOne() async throws -> J2KImage {
                    switch mode {
                    case .cpu:             return try await decoder.decode(frameData)
                    case .decodeGPU:       return try await decoder.decodeGPU(frameData)
                    case .decodeWithGPUHT: return try await decoder.decodeWithGPUHT(frameData)
                    }
                }
                var lastImage: J2KImage? = nil
                var samples: [Double] = []
                samples.reserveCapacity(runs)
                for _ in 0..<warmups { lastImage = try await runOne() }
                for _ in 0..<runs {
                    let t0 = DispatchTime.now()
                    lastImage = try await runOne()
                    samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0)
                }
                return (lastImage, samples)
            }
        } catch {
            return (nil, [], error.localizedDescription)
        }
        guard let image = output.0 else { return (nil, [], "no decode produced") }
        guard image.width == descriptor.columns, image.height == descriptor.rows else {
            return (nil, [], "decoded \(image.width)x\(image.height) ≠ expected \(descriptor.columns)x\(descriptor.rows)")
        }
        do {
            return (try Self.packPixels(from: image, descriptor: descriptor), output.1, nil)
        } catch {
            return (nil, [], error.localizedDescription)
        }
        #else
        return (nil, [], "JPEG 2000 requires J2KSwift support in this build")
        #endif
    }

    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        guard !frameData.isEmpty else {
            throw DICOMError.parsingFailed("Empty JPEG 2000 data")
        }

        if let reason = Self.irreversibleWaveletRefusal(frameData: frameData, transferSyntaxUID: decodingTransferSyntaxUID) {
            throw DICOMError.parsingFailed(reason)
        }

        #if canImport(J2KCore) && canImport(J2KCodec)
        return try Self.decodeWithJ2KSwift(frameData, descriptor: descriptor, backend: decodeBackend)
        #else
        throw DICOMError.unsupportedTransferSyntax("JPEG 2000 requires J2KSwift support in this build")
        #endif
    }

    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        // Honestly report Part-2 as un-encodable while the library cannot decode it
        // (see `J2KRoutePlanner.unsupportedEncodeReason`) so capability probes and
        // negotiation don't advertise a target that would produce unreadable images.
        guard J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: encodingTransferSyntaxUID) == nil else {
            return false
        }

        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
            return false
        }

        guard descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3 else {
            return false
        }

        return true
    }

    public func encodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int, configuration: CompressionConfiguration) throws -> Data {
        // Reject unsupported target syntaxes (currently Part-2) with a clear,
        // specific message before the generic layout check.
        if let reason = J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: encodingTransferSyntaxUID) {
            throw DICOMError.unsupportedTransferSyntax(reason)
        }
        guard canEncode(with: configuration, descriptor: descriptor) else {
            throw DICOMError.parsingFailed(
                "Unsupported JPEG 2000 encoding layout: bitsAllocated=\(descriptor.bitsAllocated), samplesPerPixel=\(descriptor.samplesPerPixel)"
            )
        }

        guard frameData.count >= descriptor.bytesPerFrame else {
            throw DICOMError.parsingFailed(
                "Frame data too short for JPEG 2000 encoding: expected at least \(descriptor.bytesPerFrame) bytes, got \(frameData.count)"
            )
        }

        #if canImport(J2KCore) && canImport(J2KCodec)
        let image = try Self.makeJ2KImage(from: frameData, descriptor: descriptor)
        // `J2KRoutePlanner` resolves type + intent + backend once; `encodeFrame`
        // and `makeEncodingConfiguration` share the same plan so the config and
        // the encode API can never disagree (see J2K_ROUTING_ARCHITECTURE.md).
        //
        // --backend metal, or auto when Metal is available, selects the J2KSwift
        // GPU encode path; accelerate/scalar select the CPU path. The planner's
        // GPU policy (`gpuEncodeEligible`) permits lossy AND lossless — the reversible
        // GPU path is bit-exact since J2KSwift v11.0.1 (verified by the library's own
        // lossless byte-identity tests). The `verifyEncodedRoundTrip` guard below
        // stays as an unconditional backstop for every lossless encode.
        let plan = J2KRoutePlanner.planEncode(
            transferSyntaxUID: encodingTransferSyntaxUID,
            configuration: configuration
        )
        let encoder = J2KEncoder(
            encodingConfiguration: Self.makeEncodingConfiguration(
                from: configuration,
                transferSyntaxUID: encodingTransferSyntaxUID,
                descriptor: descriptor
            )
        )
        let raw = try Self.awaitJ2KResult {
            plan.useGPU ? try await encoder.encodeGPU(image)
                        : try await encoder.encode(image)
        }
        // PS3.5 2026a 10.18.1 markers for .202 (RPCL label, TLM); verified by the round trip below.
        let encoded = Self.conformingCodestream(raw, transferSyntaxUID: encodingTransferSyntaxUID)
        try Self.verifyEncodedRoundTrip(encoded, original: frameData, descriptor: descriptor, requireExact: plan.lossless)
        return encoded
        #else
        throw DICOMError.unsupportedTransferSyntax("JPEG 2000 encoding requires J2KSwift support in this build")
        #endif
    }

    #if canImport(J2KCore) && canImport(J2KCodec)
    /// Decodes one frame at a reduced resolution level (WP-H, plan M5)
    ///
    /// Uses J2KSwift's true partial-resolution decode (code-block filtering +
    /// truncated inverse DWT), so a coarse preview costs a fraction of the full
    /// decode. `level` 0 is full resolution; each level halves both dimensions.
    /// Returns the packed samples plus the reduced dimensions.
    ///
    /// This is a *preview* product: measurements, exports and AI inputs must
    /// use the full-fidelity decode.
    public func decodeFrameAtResolution(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        level: Int
    ) async throws -> (data: Data, rows: Int, columns: Int) {
        // Reduced-resolution previews must fail closed for the same Part-2
        // transforms as every full-resolution decode path. J2KSwift skips these
        // markers instead of inverting them, which would otherwise emit a
        // silently incorrect preview before the exact decode fails.
        if let reason = J2KRoutePlanner.unsupportedDecodeReason(frameData: frameData) {
            throw DICOMError.unsupportedTransferSyntax(reason)
        }

        let image = try await J2KDecoder().decodeResolution(
            frameData,
            options: J2KResolutionDecodingOptions(level: level))
        guard image.width > 0, image.height > 0 else {
            throw DICOMError.parsingFailed("Reduced-resolution decode returned empty image")
        }
        let reducedDescriptor = PixelDataDescriptor(
            rows: image.height,
            columns: image.width,
            numberOfFrames: 1,
            bitsAllocated: descriptor.bitsAllocated,
            bitsStored: descriptor.bitsStored,
            highBit: descriptor.highBit,
            isSigned: descriptor.isSigned,
            samplesPerPixel: descriptor.samplesPerPixel,
            photometricInterpretation: descriptor.photometricInterpretation,
            planarConfiguration: descriptor.planarConfiguration)
        let packed = try Self.packPixels(from: image, descriptor: reducedDescriptor)
        return (packed, image.height, image.width)
    }
    #endif
}

private extension J2KSwiftCodec {
    final class AsyncResultBox<T>: @unchecked Sendable {
        var result: Result<T, Error>?
    }

    #if canImport(J2KCore) && canImport(J2KCodec)
    // Every J2K encode/decode call (CPU or GPU) bridges through this synchronous
    // DispatchSemaphore.wait(), which would otherwise block forever if
    // `operation()` never completes. Confirmed on CI: the GPU forward 5/3 DWT
    // path (`encodeGPU`) never returns on a virtualized macOS runner without a
    // functional GPU, hanging the whole process (see
    // J2KGPUEncodeRoundTripTests.part1_lossless_gray16_large, gated off CI). The
    // same risk exists on any real machine where Metal/the GPU driver stalls
    // mid-operation, so this bounds the wait and cancels the underlying task on
    // expiry rather than blocking indefinitely with no way to recover.
    static func awaitJ2KResult<T: Sendable>(
        timeout: TimeInterval = 60,
        _ operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = AsyncResultBox<T>()

        let task = Task.detached(priority: .userInitiated) {
            do {
                box.result = .success(try await operation())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            throw DICOMError.parsingFailed(
                "J2KSwift async bridge timed out after \(timeout)s — the GPU or codec backend may be unresponsive")
        }

        guard let result = box.result else {
            throw DICOMError.parsingFailed("J2KSwift async bridge returned no result")
        }

        return try result.get()
    }

    static func makeEncodingConfiguration(
        from configuration: CompressionConfiguration,
        transferSyntaxUID: String?,
        descriptor: PixelDataDescriptor? = nil
    ) -> J2KEncodingConfiguration {
        // All (type, intent, backend) routing lives in `J2KRoutePlanner` — the
        // single source of truth (see J2K_ROUTING_ARCHITECTURE.md). This method
        // only translates the resolved plan into a `J2KEncodingConfiguration`.
        //
        // Match J2KSwift library / CLI lossless defaults: 5 decomposition levels,
        // 5 quality layers, RPCL progression. The previous (0, 1, .lrcp) tuple
        // crippled compression — single-resolution wavelet means no multi-band
        // refinement, and HTJ2K in particular collapsed to ~1.24× ratios on
        // 16-bit MG mammograms vs ~6× from the same library via its CLI. RPCL
        // is required for `htj2kRPCLLossless` (PS3.5 §A.4.4) and is what
        // J2KSwift's CLI uses everywhere else.
        let plan = J2KRoutePlanner.planEncode(
            transferSyntaxUID: transferSyntaxUID,
            configuration: configuration
        )
        return J2KEncodingConfiguration(
            quality: plan.quality,
            lossless: plan.lossless,
            decompositionLevels: decompositionLevels(transferSyntaxUID: transferSyntaxUID, descriptor: descriptor),
            progressionOrder: progressionOrder(for: plan.progression),
            useHTJ2K: plan.useHTJ2K,
            useReversibleFilter: plan.useReversibleFilter,
            htj2kBlockFormat: blockFormat(for: plan.blockFormat)
        )
    }

    /// The library default of 5 decomposition levels, raised for HTJ2K Lossless RPCL (.202) to
    /// what PS3.5 2026a 10.18.1 requires: "The number of decompositions shall be sufficient for
    /// the width or height of the base resolution to be <= 64" (J2KSwift allows up to 10).
    static func decompositionLevels(transferSyntaxUID: String?, descriptor: PixelDataDescriptor?) -> Int {
        guard transferSyntaxUID == TransferSyntax.htj2kRPCLLossless.uid, let descriptor else { return 5 }
        let need = J2KCodestreamInspector.minimumDecompositionLevelsForRPCL(
            rows: descriptor.rows, columns: descriptor.columns)
        return min(10, max(5, need))
    }

    /// J2KSwift writes SGcod progression LRCP whatever `progressionOrder` says and no TLM
    /// (D187). For .202 the codestream is brought to PS3.5 2026a 10.18.1 by
    /// ``J2KCodestreamInspector/conformingToHTJ2KRPCL(_:)``; other syntaxes are returned as is.
    static func conformingCodestream(_ codestream: Data, transferSyntaxUID: String?) -> Data {
        guard transferSyntaxUID == TransferSyntax.htj2kRPCLLossless.uid else { return codestream }
        return J2KCodestreamInspector.conformingToHTJ2KRPCL(codestream)
    }

    /// Translates a planner progression choice into the J2KCodec enum.
    static func progressionOrder(for plan: J2KRoutePlanner.ProgressionPlan) -> J2KProgressionOrder {
        switch plan {
        case .rpcl: return .rpcl
        case .lrcp: return .lrcp
        }
    }

    /// Translates a planner block-format choice into the J2KCodec enum.
    static func blockFormat(for plan: J2KRoutePlanner.BlockFormatPlan) -> HTBlockFormat {
        switch plan {
        case .conformant: return .conformant
        case .custom:     return .custom
        }
    }

    /// Decodes the encoded frame and checks its size; when the planned encode is reversible
    /// (`J2KRoutePlanner.EncodePlan.lossless`, the 5-3 filter of PS3.5 2026a 8.2.4) the decoded
    /// samples must equal the source exactly. An irreversible 9-7 encode is lossy by definition,
    /// so it is not held to bit-exactness even when the quality preset is "maximum" (D234).
    static func verifyEncodedRoundTrip(
        _ encoded: Data,
        original: Data,
        descriptor: PixelDataDescriptor,
        requireExact: Bool
    ) throws {
        let decoded = try decodeWithJ2KSwift(encoded, descriptor: descriptor)
        guard decoded.count == descriptor.bytesPerFrame else {
            throw DICOMError.parsingFailed(
                "Decoded byte count \(decoded.count) does not match expected \(descriptor.bytesPerFrame)"
            )
        }

        if requireExact {
            guard decoded == original else {
                throw DICOMError.parsingFailed("J2KSwift lossless round-trip validation failed")
            }
        }
    }

    static func decodeWithJ2KSwift(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        backend: CodecBackend? = nil
    ) throws -> Data {
        // A Part-2 multi-component transform is skipped, not inverted, by every
        // J2KSwift decode API — refuse rather than return corrupt pixels.
        if let reason = J2KRoutePlanner.unsupportedDecodeReason(frameData: frameData) {
            throw DICOMError.unsupportedTransferSyntax(reason)
        }

        // Phase 4: the decode API follows the backend preference + frame size via
        // `J2KRoutePlanner.planDecode`. `auto`/CPU on small or very large frames uses
        // the CPU `decode`; a Metal request (or auto on a mid-size frame with Metal)
        // uses `decodeGPU` (GPU inverse DWT). All paths auto-detect the Part-1 vs
        // HTJ2K codestream family, so no codec-type branching is needed — but note
        // they do *not* self-configure from Part-2 markers, hence the guard above.
        // The J2K Compare panel still pins a specific API via `decode(...,mode:)`.
        let pixelCount = descriptor.rows * descriptor.columns
        let api = J2KRoutePlanner.planDecode(backend: backend, pixelCount: pixelCount)
        let image: J2KImage
        do {
            image = try Self.awaitJ2KResult {
                let decoder = J2KDecoder()
                switch api {
                case .cpu:   return try await decoder.decode(frameData)
                case .gpu:   return try await decoder.decodeGPU(frameData)
                case .gpuHT: return try await decoder.decodeWithGPUHT(frameData)
                }
            }
        } catch {
            throw DICOMError.parsingFailed("J2KSwift decode failed: \(error)")
        }

        guard image.width == descriptor.columns, image.height == descriptor.rows else {
            throw DICOMError.parsingFailed(
                "Decoded image dimensions (\(image.width)x\(image.height)) do not match expected (\(descriptor.columns)x\(descriptor.rows))"
            )
        }

        return try packPixels(from: image, descriptor: descriptor)
    }

    static func makeJ2KImage(from frameData: Data, descriptor: PixelDataDescriptor) throws -> J2KImage {
        let expectedBytes = descriptor.bytesPerFrame
        let bytesPerSample = descriptor.bytesPerSample
        let componentPixelCount = descriptor.rows * descriptor.columns
        let componentByteCount = componentPixelCount * bytesPerSample

        guard frameData.count >= expectedBytes else {
            throw DICOMError.parsingFailed("Frame data too short for JPEG 2000 encoding")
        }

        // DICOM Explicit VR LE pixel data is already little-endian. Pass it to
        // J2KSwift verbatim and signal the byte order so the encoder does not
        // run its statistical inference — this also saves us the O(N) manual
        // swap we used to do before v4.0's `sampleByteOrder` hint existed.
        let byteOrderHint: J2KComponent.ByteOrder? = (bytesPerSample == 2) ? .littleEndian : nil

        let colorSpace: J2KColorSpace = descriptor.samplesPerPixel == 1 ? .grayscale : .sRGB
        let components: [J2KComponent]

        switch descriptor.samplesPerPixel {
        case 1:
            let componentData: Data
            if frameData.count == expectedBytes {
                componentData = frameData
            } else {
                componentData = frameData.subdata(in: frameData.startIndex..<frameData.startIndex + expectedBytes)
            }
            components = [
                J2KComponent(
                    index: 0,
                    bitDepth: descriptor.bitsStored,
                    signed: descriptor.isSigned,
                    width: descriptor.columns,
                    height: descriptor.rows,
                    data: componentData,
                    sampleByteOrder: byteOrderHint
                )
            ]

        case 3:
            let planes: [Data]
            if descriptor.planarConfiguration == 1 {
                guard frameData.count >= componentByteCount * 3 else {
                    throw DICOMError.parsingFailed("Planar RGB frame data too short for JPEG 2000 encoding")
                }
                planes = (0..<3).map { componentIndex in
                    let start = frameData.startIndex + componentIndex * componentByteCount
                    let end = start + componentByteCount
                    return frameData.subdata(in: start..<end)
                }
            } else {
                planes = try deinterleaveRGB(
                    frameData: frameData,
                    bytesPerSample: bytesPerSample,
                    componentPixelCount: componentPixelCount,
                    componentByteCount: componentByteCount
                )
            }

            components = (0..<3).map { componentIndex in
                J2KComponent(
                    index: componentIndex,
                    bitDepth: descriptor.bitsStored,
                    signed: descriptor.isSigned,
                    width: descriptor.columns,
                    height: descriptor.rows,
                    data: planes[componentIndex],
                    sampleByteOrder: byteOrderHint
                )
            }

        default:
            throw DICOMError.parsingFailed("Unsupported samples per pixel for JPEG 2000 encoding: \(descriptor.samplesPerPixel)")
        }

        return J2KImage(
            width: descriptor.columns,
            height: descriptor.rows,
            components: components,
            colorSpace: colorSpace
        )
    }

    /// De-interleaves a chunky RGB buffer into three planar Data components.
    /// Faster than the previous iterator-based build because it preallocates
    /// each plane and writes bytes via UnsafeMutableBufferPointer.
    static func deinterleaveRGB(
        frameData: Data,
        bytesPerSample: Int,
        componentPixelCount: Int,
        componentByteCount: Int
    ) throws -> [Data] {
        let bytesPerPixel = bytesPerSample * 3
        guard frameData.count >= componentPixelCount * bytesPerPixel else {
            throw DICOMError.parsingFailed("RGB frame data ended unexpectedly while building J2K components")
        }
        var r = Data(count: componentByteCount)
        var g = Data(count: componentByteCount)
        var b = Data(count: componentByteCount)
        frameData.withUnsafeBytes { src in
            let srcBase = src.baseAddress!.assumingMemoryBound(to: UInt8.self)
            r.withUnsafeMutableBytes { rBuf in
                g.withUnsafeMutableBytes { gBuf in
                    b.withUnsafeMutableBytes { bBuf in
                        let rp = rBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let gp = gBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let bp = bBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        var srcOff = 0
                        var dstOff = 0
                        for _ in 0..<componentPixelCount {
                            for k in 0..<bytesPerSample {
                                rp[dstOff + k] = srcBase[srcOff + k]
                                gp[dstOff + k] = srcBase[srcOff + bytesPerSample + k]
                                bp[dstOff + k] = srcBase[srcOff + 2 * bytesPerSample + k]
                            }
                            srcOff += bytesPerPixel
                            dstOff += bytesPerSample
                        }
                    }
                }
            }
        }
        return [r, g, b]
    }

    /// Packs the decoded components into DICOM pixel bytes, strictly.
    ///
    /// The component count must equal Samples per Pixel, every component's
    /// precision must fit Bits Allocated and every component's sample buffer
    /// must be exactly the declared frame's byte count. Previously a surplus
    /// component was ignored and an over-long buffer (for example a 16-bit
    /// codestream under an 8-bit descriptor) was silently truncated.
    static func packPixels(from image: J2KImage, descriptor: PixelDataDescriptor) throws -> Data {
        let bytesPerSample = descriptor.bytesPerSample
        let expectedComponentByteCount = descriptor.rows * descriptor.columns * bytesPerSample

        guard image.components.count == descriptor.samplesPerPixel else {
            throw DICOMError.parsingFailed(
                "Decoded component count \(image.components.count) does not match samples per pixel \(descriptor.samplesPerPixel)"
            )
        }

        var components: [Data] = []
        components.reserveCapacity(descriptor.samplesPerPixel)
        for component in image.components {
            guard component.bitDepth <= descriptor.bitsAllocated else {
                throw DICOMError.parsingFailed(
                    "Decoded JPEG 2000 component \(component.index) precision \(component.bitDepth) bits exceeds "
                        + "Bits Allocated \(descriptor.bitsAllocated)"
                )
            }
            guard component.data.count == expectedComponentByteCount else {
                throw DICOMError.parsingFailed(
                    "Decoded JPEG 2000 component \(component.index) has \(component.data.count) bytes, expected exactly "
                        + "\(expectedComponentByteCount) for \(descriptor.columns)x\(descriptor.rows) at "
                        + "\(descriptor.bitsAllocated) bits allocated"
                )
            }
            var plane = component.data
            swapBytesInPlaceIfNeeded(&plane, bytesPerSample: bytesPerSample)
            components.append(plane)
        }

        if descriptor.samplesPerPixel == 1 {
            return components[0]
        }

        if descriptor.planarConfiguration == 1 {
            var packed = Data(capacity: expectedComponentByteCount * descriptor.samplesPerPixel)
            for plane in components { packed.append(plane) }
            return packed
        }

        return interleaveRGB(
            planes: components,
            bytesPerSample: bytesPerSample,
            pixelCount: descriptor.rows * descriptor.columns
        )
    }

    /// Interleaves R/G/B planar buffers back into chunky RGB layout.
    static func interleaveRGB(planes: [Data], bytesPerSample: Int, pixelCount: Int) -> Data {
        let totalBytes = pixelCount * bytesPerSample * 3
        var packed = Data(count: totalBytes)
        packed.withUnsafeMutableBytes { dst in
            let dstBase = dst.baseAddress!.assumingMemoryBound(to: UInt8.self)
            planes[0].withUnsafeBytes { r in
                planes[1].withUnsafeBytes { g in
                    planes[2].withUnsafeBytes { b in
                        let rp = r.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let gp = g.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let bp = b.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        var srcOff = 0
                        var dstOff = 0
                        for _ in 0..<pixelCount {
                            for k in 0..<bytesPerSample {
                                dstBase[dstOff + k] = rp[srcOff + k]
                                dstBase[dstOff + bytesPerSample + k] = gp[srcOff + k]
                                dstBase[dstOff + 2 * bytesPerSample + k] = bp[srcOff + k]
                            }
                            srcOff += bytesPerSample
                            dstOff += bytesPerSample * 3
                        }
                    }
                }
            }
        }
        return packed
    }
    #endif

    /// In-place 16-bit byte swap using Accelerate's vImage (NEON on Apple Silicon,
    /// SSE on x86). Falls back to a UInt16 `.byteSwapped` loop when Accelerate is
    /// unavailable; that loop autovectorizes with the ARM REV16 instruction at -O.
    /// No-op for bytesPerSample != 2.
    @inline(__always)
    static func swapBytesInPlaceIfNeeded(_ data: inout Data, bytesPerSample: Int) {
        guard bytesPerSample == 2 else { return }
        let byteCount = data.count
        guard byteCount >= 2, byteCount % 2 == 0 else { return }
        data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            #if canImport(Accelerate)
            var src = vImage_Buffer(
                data: base,
                height: 1,
                width: vImagePixelCount(byteCount / 2),
                rowBytes: byteCount
            )
            var dst = src  // in-place
            _ = vImageByteSwap_Planar16U(&src, &dst, vImage_Flags(kvImageNoFlags))
            #else
            let ptr = base.assumingMemoryBound(to: UInt16.self)
            let count = byteCount / 2
            for i in 0..<count { ptr[i] = ptr[i].byteSwapped }
            #endif
        }
    }
}
