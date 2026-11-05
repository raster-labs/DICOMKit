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
public struct J2KSwiftCodec: ImageCodec, ImageEncoder, DecodeBackendConfigurableCodec, Sendable {
    /// Finite decode policy that does not construct or retain transfer-syntax Strings.
    public enum DecodingSyntax: UInt8, Sendable {
        /// Admit any JPEG 2000 Part 1 or HTJ2K codestream supported by this codec.
        case any
        /// Admit any HTJ2K (ISO/IEC 15444-15) codestream (`.201`, `.202`, `.203`).
        case htj2kAny
        /// JPEG 2000 Image Compression (Lossless Only) — `1.2.840.10008.1.2.4.90`.
        case jpeg2000Lossless
        /// JPEG 2000 Image Compression — `1.2.840.10008.1.2.4.91`.
        case jpeg2000
        /// JPEG 2000 Part 2 Multi-component Image Compression (Lossless Only) — `1.2.840.10008.1.2.4.92`.
        case jpeg2000Part2Lossless
        /// JPEG 2000 Part 2 Multi-component Image Compression — `1.2.840.10008.1.2.4.93`.
        case jpeg2000Part2
        /// High-Throughput JPEG 2000 Image Compression (Lossless Only) — `1.2.840.10008.1.2.4.201`.
        case htj2kLossless
        /// High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only) — `1.2.840.10008.1.2.4.202`.
        case htj2kRPCLLossless
        /// High-Throughput JPEG 2000 Image Compression — `1.2.840.10008.1.2.4.203`.
        case htj2kLossy
    }

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

    private enum SyntaxRestriction: Equatable, Sendable {
        case any
        case htj2kAny
        case jpeg2000Lossless
        case jpeg2000
        case jpeg2000Part2Lossless
        case jpeg2000Part2
        case htj2kLossless
        case htj2kRPCLLossless
        case htj2kLossy
        case unsupported

        var isLosslessOnly: Bool {
            switch self {
            case .jpeg2000Lossless, .jpeg2000Part2Lossless, .htj2kLossless, .htj2kRPCLLossless:
                return true
            case .any, .htj2kAny, .jpeg2000, .jpeg2000Part2, .htj2kLossy, .unsupported:
                return false
            }
        }

        var requiresHTJ2KCAP: Bool? {
            switch self {
            case .htj2kAny, .htj2kLossless, .htj2kRPCLLossless, .htj2kLossy:
                return true
            case .jpeg2000Lossless, .jpeg2000:
                return false
            case .any, .jpeg2000Part2Lossless, .jpeg2000Part2, .unsupported:
                return nil
            }
        }

        var requiresRPCL: Bool {
            self == .htj2kRPCLLossless
        }
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
    private let syntaxRestriction: SyntaxRestriction
    private let decodingLimits: PixelDecodeLimits

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
        decodingTransferSyntaxUID: String? = nil,
        decodingLimits: PixelDecodeLimits = .default
    ) {
        self.encodingTransferSyntaxUID = encodingTransferSyntaxUID
        self.decodeBackend = decodeBackend
        self.decodingTransferSyntaxUID = decodingTransferSyntaxUID
        switch decodingTransferSyntaxUID {
        case nil: self.syntaxRestriction = .any
        case TransferSyntax.jpeg2000Lossless.uid: self.syntaxRestriction = .jpeg2000Lossless
        case TransferSyntax.jpeg2000.uid: self.syntaxRestriction = .jpeg2000
        case TransferSyntax.jpeg2000Part2Lossless.uid: self.syntaxRestriction = .jpeg2000Part2Lossless
        case TransferSyntax.jpeg2000Part2.uid: self.syntaxRestriction = .jpeg2000Part2
        case TransferSyntax.htj2kLossless.uid: self.syntaxRestriction = .htj2kLossless
        case TransferSyntax.htj2kRPCLLossless.uid: self.syntaxRestriction = .htj2kRPCLLossless
        case TransferSyntax.htj2kLossy.uid: self.syntaxRestriction = .htj2kLossy
        default: self.syntaxRestriction = .unsupported
        }
        self.decodingLimits = decodingLimits
    }

    /// Create the same decoder from finite scalar policy without initializing UID Strings.
    public init(
        encodingTransferSyntaxUID: String? = nil,
        decodingSyntax: DecodingSyntax,
        decodeBackend: CodecBackend? = nil,
        decodingLimits: PixelDecodeLimits = .init()
    ) {
        self.encodingTransferSyntaxUID = encodingTransferSyntaxUID
        self.decodeBackend = decodeBackend
        self.decodingTransferSyntaxUID = nil
        switch decodingSyntax {
        case .any: self.syntaxRestriction = .any
        case .htj2kAny: self.syntaxRestriction = .htj2kAny
        case .jpeg2000Lossless: self.syntaxRestriction = .jpeg2000Lossless
        case .jpeg2000: self.syntaxRestriction = .jpeg2000
        case .jpeg2000Part2Lossless: self.syntaxRestriction = .jpeg2000Part2Lossless
        case .jpeg2000Part2: self.syntaxRestriction = .jpeg2000Part2
        case .htj2kLossless: self.syntaxRestriction = .htj2kLossless
        case .htj2kRPCLLossless: self.syntaxRestriction = .htj2kRPCLLossless
        case .htj2kLossy: self.syntaxRestriction = .htj2kLossy
        }
        self.decodingLimits = decodingLimits
    }

    private init(
        encodingTransferSyntaxUID: String?,
        decodeBackend: CodecBackend?,
        decodingTransferSyntaxUID: String?,
        syntaxRestriction: SyntaxRestriction,
        decodingLimits: PixelDecodeLimits
    ) {
        self.encodingTransferSyntaxUID = encodingTransferSyntaxUID
        self.decodeBackend = decodeBackend
        self.decodingTransferSyntaxUID = decodingTransferSyntaxUID
        self.syntaxRestriction = syntaxRestriction
        self.decodingLimits = decodingLimits
    }

    public func withDecodeBackend(_ decodeBackend: CodecBackend?) -> any ImageCodec {
        J2KSwiftCodec(
            encodingTransferSyntaxUID: encodingTransferSyntaxUID,
            decodeBackend: decodeBackend,
            decodingTransferSyntaxUID: decodingTransferSyntaxUID,
            syntaxRestriction: syntaxRestriction,
            decodingLimits: decodingLimits
        )
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
        _ = try decodingLimits.validate(frameData, descriptor: descriptor, frameIndex: frameIndex)

        if let reason = Self.irreversibleWaveletRefusal(frameData: frameData, transferSyntaxUID: decodingTransferSyntaxUID) {
            throw DICOMError.parsingFailed(reason)
        }
        if decodingTransferSyntaxUID == nil, syntaxRestriction.isLosslessOnly,
           J2KCodestreamInspector.usesIrreversibleWavelet(in: frameData) {
            throw DICOMError.parsingFailed(
                "JPEG 2000 codestream selects the irreversible 9/7 wavelet under a lossless-only transfer syntax; refusing to decode inexact samples"
            )
        }

        let resolvedData = try resolveAndValidateCodestream(frameData, descriptor: descriptor)

        #if canImport(J2KCore) && canImport(J2KCodec)
        return try Self.decodeWithJ2KSwift(resolvedData, descriptor: descriptor, backend: decodeBackend)
        #else
        throw DICOMError.unsupportedTransferSyntax("JPEG 2000 requires J2KSwift support in this build")
        #endif
    }

    public func decodePixelFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> DecodedPixelFrame {
        let decoded = try decodeFrame(frameData, descriptor: descriptor, frameIndex: frameIndex)
        return DecodedPixelFrame(
            data: decoded,
            descriptor: Self.outputDescriptor(for: descriptor),
            sourceFrameIndex: frameIndex
        )
    }

    private func validateCodestreamHeaderOutcome(
        _ codestream: Data,
        descriptor: PixelDataDescriptor
    ) -> DICOMManagedFailure? {
        guard let header = J2KCodestreamInspector.imageHeader(in: codestream) else {
            return DICOMManagedFailure(.malformed, 402)
        }
        guard header.width == descriptor.columns, header.height == descriptor.rows else {
            return DICOMManagedFailure(.codecResultMismatch, 406)
        }
        guard header.components.count == descriptor.samplesPerPixel else {
            return DICOMManagedFailure(.codecResultMismatch, 407)
        }
        for component in header.components {
            guard component.bitDepth == descriptor.bitsStored,
                  component.isSigned == descriptor.isSigned else {
                return DICOMManagedFailure(.codecResultMismatch, 408)
            }
        }
        if !J2KRoutePlanner.part2MCTDecodeSupported,
           J2KCodestreamInspector.containsPart2MultiComponentTransform(in: codestream) {
            return DICOMManagedFailure(.invalidDescriptor, 403)
        }
        if syntaxRestriction.isLosslessOnly,
           J2KCodestreamInspector.usesIrreversibleWavelet(in: codestream) {
            return DICOMManagedFailure(.invalidDescriptor, 404)
        }
        if let expectedCAP = syntaxRestriction.requiresHTJ2KCAP,
           header.hasCAPMarker != expectedCAP {
            return DICOMManagedFailure(.invalidDescriptor, 412)
        }
        if syntaxRestriction.requiresRPCL,
           !J2KCodestreamInspector.htj2kRPCLViolations(
               in: codestream, rows: descriptor.rows, columns: descriptor.columns
           ).isEmpty {
            return DICOMManagedFailure(.invalidDescriptor, 413)
        }
        return nil
    }

    private func resolveAndValidateCodestream(
        _ frameData: Data,
        descriptor: PixelDataDescriptor
    ) throws -> Data {
        guard syntaxRestriction != .unsupported else {
            throw DICOMError.unsupportedTransferSyntax("Unsupported JPEG 2000 decoding transfer syntax")
        }
        let isBare = frameData.count >= 2
            && frameData[frameData.startIndex] == 0xFF
            && frameData[frameData.index(after: frameData.startIndex)] == 0x4F
        let candidate: Data
        if isBare,
           frameData.count >= 4,
           frameData.count % 2 == 0,
           frameData[frameData.index(frameData.endIndex, offsetBy: -3)] == 0xFF,
           frameData[frameData.index(frameData.endIndex, offsetBy: -2)] == 0xD9,
           frameData[frameData.index(frameData.endIndex, offsetBy: -1)] == 0x00 {
            candidate = frameData.dropLast()
        } else {
            candidate = frameData
        }

        if let failure = validateCodestreamHeaderOutcome(Data(candidate), descriptor: descriptor) {
            if !isBare,
               candidate.count == frameData.count,
               frameData.count % 2 == 0,
               frameData.last == 0x00 {
                let unpadded = Data(frameData.dropLast())
                if validateCodestreamHeaderOutcome(unpadded, descriptor: descriptor) == nil {
                    return unpadded
                }
            }
            if failure.operand1 == 403,
               let reason = J2KRoutePlanner.unsupportedDecodeReason(frameData: Data(candidate)) {
                throw DICOMError.unsupportedTransferSyntax(reason)
            }
            throw DICOMError.parsingFailed("JPEG 2000 header validation failed (\(failure.code), \(failure.operand1))")
        }
        return Data(candidate)
    }

    // MARK: - Managed Budget-Accounted Decoding

    /// Decode a JPEG 2000 / HTJ2K frame into explicitly admitted backing.
    @available(*, noasync, message: "Invoke on a synchronous worker thread outside Swift's cooperative pool")
    public func decodeManagedPixelFrame(
        _ frameData: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        budget: borrowing DICOMAllocationBudget,
        cancellation: DICOMCancellation = .never
    ) throws(DICOMManagedFailure) -> ManagedDecodedPixelFrame {
        try decodeManagedPixelFrameOutcome(
            frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, cancellation: cancellation
        ).get()
    }

    /// Throwing compatibility adapter for an admitted worker; use the outcome overload inside qualified work.
    @available(*, noasync, message: "Invoke on the synchronous worker owning the execution reservation")
    public func decodeManagedPixelFrame(
        _ frameData: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        budget: borrowing DICOMAllocationBudget,
        execution: borrowing DICOMExecutionReservation,
        cancellation: DICOMCancellation = .never
    ) throws(DICOMManagedFailure) -> ManagedDecodedPixelFrame {
        try decodeManagedPixelFrameOutcome(
            frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, execution: execution, cancellation: cancellation
        ).get()
    }

    /// Decode on the original admitted worker with scalar identity/refusal status.
    @available(*, noasync, message: "Qualified decoding must remain on its admitted synchronous worker")
    public func decodeManagedPixelFrameOutcome(
        _ frameData: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        budget: borrowing DICOMAllocationBudget,
        execution: borrowing DICOMExecutionReservation,
        cancellation: DICOMCancellation = .never
    ) -> DICOMManagedOutcome<ManagedDecodedPixelFrame> {
        switch execution.validateOutcome(budget: budget) {
        case .success: break
        case .failure(let failure): return .failure(DICOMManagedFailure(allocation: failure))
        }
        return decodeManagedPixelFrameOutcome(
            frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, cancellation: cancellation
        )
    }

    /// Decode a JPEG 2000 / HTJ2K frame using scalar outcomes and budget-owned `.staging` / `.decoded` backing.
    @available(*, noasync, message: "Invoke on a synchronous worker thread outside Swift's cooperative pool")
    public func decodeManagedPixelFrameOutcome(
        _ frameData: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        budget: borrowing DICOMAllocationBudget,
        cancellation: DICOMCancellation = .never
    ) -> DICOMManagedOutcome<ManagedDecodedPixelFrame> {
        if let failure = cancellation.failure { return .failure(failure) }
        guard frameData.isOwned(by: budget) else {
            return .failure(DICOMManagedFailure(allocation: .budgetMismatch))
        }
        let expectedBytes: Int
        switch decodingLimits.validateManagedOutcome(
            encodedByteCount: frameData.count,
            descriptor: descriptor,
            frameIndex: frameIndex
        ) {
        case .success(let value): expectedBytes = value
        case .failure(let failure): return .failure(failure)
        }
        guard syntaxRestriction != .unsupported else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 400))
        }
        guard (descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3),
              (descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16) else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 401))
        }

        #if canImport(J2KCore) && canImport(J2KCodec)
        return frameData.withBorrowedBytes { encoded -> DICOMManagedOutcome<ManagedDecodedPixelFrame> in
            guard let encodedBase = encoded.baseAddress?.assumingMemoryBound(to: UInt8.self),
                  encoded.count >= 2 else {
                return .failure(DICOMManagedFailure(.malformed, 402))
            }

            // Strip a single DICOM even-length fragment pad byte (0x00) after bare SOC...EOC.
            let isBareCodestream = encodedBase[0] == 0xFF && encodedBase[1] == 0x4F
            let initialCount: Int
            if isBareCodestream,
               encoded.count >= 4,
               encoded.count % 2 == 0,
               encodedBase[encoded.count - 3] == 0xFF,
               encodedBase[encoded.count - 2] == 0xD9,
               encodedBase[encoded.count - 1] == 0x00 {
                initialCount = encoded.count - 1
            } else {
                initialCount = encoded.count
            }

            // Zero-copy pre-admission header validation (no heap Data copy before .staging admission).
            var resolvedCount = initialCount
            let initialView = Data(
                bytesNoCopy: UnsafeMutableRawPointer(mutating: encodedBase),
                count: initialCount,
                deallocator: .none
            )
            if let headerFailure = validateCodestreamHeaderOutcome(initialView, descriptor: descriptor) {
                if !isBareCodestream,
                   initialCount == encoded.count,
                   encoded.count % 2 == 0,
                   encodedBase[encoded.count - 1] == 0x00 {
                    let unpaddedView = Data(
                        bytesNoCopy: UnsafeMutableRawPointer(mutating: encodedBase),
                        count: encoded.count - 1,
                        deallocator: .none
                    )
                    if validateCodestreamHeaderOutcome(unpaddedView, descriptor: descriptor) == nil {
                        resolvedCount = encoded.count - 1
                    } else {
                        return .failure(headerFailure)
                    }
                } else {
                    return .failure(headerFailure)
                }
            }

            let pixelCount = descriptor.rows * descriptor.columns
            let useMetalBackend = (decodeBackend == .metal)
            let api = useMetalBackend
                ? J2KRoutePlanner.planDecode(backend: .metal, pixelCount: pixelCount)
                : .cpu

            let (stagingByteCount, stagingOverflow) = expectedBytes.addingReportingOverflow(resolvedCount)
            guard !stagingOverflow, stagingByteCount > 0 else {
                return .failure(DICOMManagedFailure(.limitExceeded, 2))
            }

            let image: J2KImage
            do {
                let staging: DICOMByteBuffer
                switch DICOMByteBuffer.admit(count: stagingByteCount, budget: budget, resource: .staging) {
                case .success(let value): staging = value
                case .failure(let failure): return .failure(failure)
                }
                if let failure = cancellation.failure {
                    staging.keepAlive()
                    return .failure(failure)
                }

                let codestreamData = Data(bytes: encodedBase, count: resolvedCount)
                let decodeResult = Self.awaitJ2KManagedResult(cancellation: cancellation) {
                    let decoder = J2KDecoder()
                    switch api {
                    case .cpu:   return try await decoder.decode(codestreamData)
                    case .gpu:   return try await decoder.decodeGPU(codestreamData)
                    case .gpuHT: return try await decoder.decodeWithGPUHT(codestreamData)
                    }
                }
                staging.keepAlive()
                switch decodeResult {
                case .success(let decoded): image = decoded
                case .failure(let failure): return .failure(failure)
                }
            }

            guard image.width == descriptor.columns, image.height == descriptor.rows else {
                return .failure(DICOMManagedFailure(.codecResultMismatch, 406))
            }
            guard image.components.count == descriptor.samplesPerPixel else {
                return .failure(DICOMManagedFailure(.codecResultMismatch, 407))
            }

            let bytesPerSample = descriptor.bytesPerSample
            let widen8To16 = (bytesPerSample == 2 && descriptor.bitsStored <= 8)
            let expectedRawComponentBytes = widen8To16 ? pixelCount : (pixelCount * bytesPerSample)
            let expectedComponentByteCount = pixelCount * bytesPerSample
            for component in image.components {
                guard component.bitDepth == descriptor.bitsStored,
                      component.signed == descriptor.isSigned else {
                    return .failure(DICOMManagedFailure(.codecResultMismatch, 408))
                }
                guard component.data.count == expectedRawComponentBytes else {
                    return .failure(DICOMManagedFailure(.codecResultMismatch, 409))
                }
            }

            let bytes: DICOMByteBuffer
            switch DICOMByteBuffer.admit(count: expectedBytes, budget: budget, resource: .decoded) {
            case .success(let value): bytes = value
            case .failure(let failure): return .failure(failure)
            }
            if let failure = cancellation.failure { return .failure(failure) }
            guard let dstBase = bytes.unsafeMutableBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return .failure(DICOMManagedFailure(.codecResultMismatch, 410))
            }

            let isSigned8In16 = widen8To16 && descriptor.isSigned
            if descriptor.samplesPerPixel == 1 {
                let copyFailure: DICOMManagedFailure? = image.components[0].data.withUnsafeBytes { raw0 in
                    guard let src0 = raw0.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return DICOMManagedFailure(.codecResultMismatch, 410)
                    }
                    if bytesPerSample == 1 {
                        dstBase.update(from: src0, count: expectedComponentByteCount)
                    } else if widen8To16 {
                        for p in 0..<pixelCount {
                            if (p & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                            let u = src0[p]
                            dstBase[p * 2] = u
                            dstBase[p * 2 + 1] = (isSigned8In16 && (u & 0x80) != 0) ? 0xFF : 0x00
                        }
                    } else {
                        for p in 0..<pixelCount {
                            if (p & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                            dstBase[p * 2] = src0[p * 2 + 1]
                            dstBase[p * 2 + 1] = src0[p * 2]
                        }
                    }
                    return nil
                }
                bytes.keepAlive()
                if let copyFailure { return .failure(copyFailure) }
            } else if descriptor.planarConfiguration == 1 {
                for c in 0..<3 {
                    let dstPlane = dstBase.advanced(by: c * expectedComponentByteCount)
                    let copyFailure: DICOMManagedFailure? = image.components[c].data.withUnsafeBytes { rawC in
                        guard let srcC = rawC.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                            return DICOMManagedFailure(.codecResultMismatch, 410)
                        }
                        if bytesPerSample == 1 {
                            dstPlane.update(from: srcC, count: expectedComponentByteCount)
                        } else if widen8To16 {
                            for p in 0..<pixelCount {
                                if (p & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                                let u = srcC[p]
                                dstPlane[p * 2] = u
                                dstPlane[p * 2 + 1] = (isSigned8In16 && (u & 0x80) != 0) ? 0xFF : 0x00
                            }
                        } else {
                            for p in 0..<pixelCount {
                                if (p & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                                dstPlane[p * 2] = srcC[p * 2 + 1]
                                dstPlane[p * 2 + 1] = srcC[p * 2]
                            }
                        }
                        return nil
                    }
                    bytes.keepAlive()
                    if let copyFailure { return .failure(copyFailure) }
                }
            } else {
                let copyFailure: DICOMManagedFailure? = image.components[0].data.withUnsafeBytes { rRaw in
                    image.components[1].data.withUnsafeBytes { gRaw in
                        image.components[2].data.withUnsafeBytes { bRaw in
                            guard let rp = rRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                                  let gp = gRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                                  let bp = bRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                                return DICOMManagedFailure(.codecResultMismatch, 410)
                            }
                            if bytesPerSample == 1 {
                                for p in 0..<pixelCount {
                                    if (p & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                                    let dstOff = p * 3
                                    dstBase[dstOff] = rp[p]
                                    dstBase[dstOff + 1] = gp[p]
                                    dstBase[dstOff + 2] = bp[p]
                                }
                            } else if widen8To16 {
                                for p in 0..<pixelCount {
                                    if (p & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                                    let rVal = rp[p], gVal = gp[p], bVal = bp[p]
                                    let dstOff = p * 6
                                    dstBase[dstOff] = rVal
                                    dstBase[dstOff + 1] = (isSigned8In16 && (rVal & 0x80) != 0) ? 0xFF : 0x00
                                    dstBase[dstOff + 2] = gVal
                                    dstBase[dstOff + 3] = (isSigned8In16 && (gVal & 0x80) != 0) ? 0xFF : 0x00
                                    dstBase[dstOff + 4] = bVal
                                    dstBase[dstOff + 5] = (isSigned8In16 && (bVal & 0x80) != 0) ? 0xFF : 0x00
                                }
                            } else {
                                for p in 0..<pixelCount {
                                    if (p & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                                    let srcOff = p * 2
                                    let dstOff = p * 6
                                    dstBase[dstOff] = rp[srcOff + 1]
                                    dstBase[dstOff + 1] = rp[srcOff]
                                    dstBase[dstOff + 2] = gp[srcOff + 1]
                                    dstBase[dstOff + 3] = gp[srcOff]
                                    dstBase[dstOff + 4] = bp[srcOff + 1]
                                    dstBase[dstOff + 5] = bp[srcOff]
                                }
                            }
                            return nil
                        }
                    }
                }
                bytes.keepAlive()
                if let copyFailure { return .failure(copyFailure) }
            }

            if let failure = cancellation.failure { return .failure(failure) }
            return .success(ManagedDecodedPixelFrame(
                data: bytes,
                descriptor: Self.outputDescriptor(for: descriptor),
                sourceFrameIndex: frameIndex
            ))
        }
        #else
        return .failure(DICOMManagedFailure(.invalidTransferSyntax, 411))
        #endif
    }

    package static func outputDescriptor(for descriptor: PixelDataDescriptor) -> PixelDataDescriptor {
        guard descriptor.samplesPerPixel == 3,
              descriptor.photometricInterpretation == .ybrRCT
                || descriptor.photometricInterpretation == .ybrICT else {
            return descriptor
        }
        return PixelDataDescriptor(
            rows: descriptor.rows,
            columns: descriptor.columns,
            numberOfFrames: descriptor.numberOfFrames,
            bitsAllocated: descriptor.bitsAllocated,
            bitsStored: descriptor.bitsStored,
            highBit: descriptor.highBit,
            isSigned: descriptor.isSigned,
            samplesPerPixel: descriptor.samplesPerPixel,
            photometricInterpretation: .rgb,
            planarConfiguration: descriptor.planarConfiguration
        )
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
        try Task.checkCancellation()
        _ = try decodingLimits.validate(frameData, descriptor: descriptor, frameIndex: 0)
        // Preview pixels carry the same syntax and header guarantees as the full decode.
        let codestream = try resolveAndValidateCodestream(frameData, descriptor: descriptor)
        let image = try await J2KDecoder().decodeResolution(
            codestream,
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

    /// Cancellation-polling synchronous bridge for managed J2K decode.
    /// Waits for cooperative task unwind on cancellation so `.staging` remains live while the task exits.
    static func awaitJ2KManagedResult<T: Sendable>(
        cancellation: DICOMCancellation,
        timeout: TimeInterval = 60,
        _ operation: @escaping @Sendable () async throws -> T
    ) -> Result<T, DICOMManagedFailure> {
        if let failure = cancellation.failure { return .failure(failure) }
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

        let deadline = Date().addingTimeInterval(timeout)
        while semaphore.wait(timeout: .now() + .milliseconds(5)) == .timedOut {
            if let failure = cancellation.failure {
                task.cancel()
                _ = semaphore.wait(timeout: .now() + .seconds(10))
                return .failure(failure)
            }
            if Date() >= deadline {
                task.cancel()
                _ = semaphore.wait(timeout: .now() + .seconds(5))
                return .failure(DICOMManagedFailure(.codecFailure, 405, domain: 0x0400))
            }
        }

        if let failure = cancellation.failure { return .failure(failure) }
        guard let result = box.result else {
            return .failure(DICOMManagedFailure(.codecFailure, 405, domain: 0x0400))
        }
        switch result {
        case .success(let value):
            return .success(value)
        case .failure:
            return .failure(DICOMManagedFailure(.codecFailure, 405, domain: 0x0400))
        }
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

    /// J2KSwift writes SGcod progression LRCP whatever `progressionOrder` says, no TLM (D187),
    /// and a hardcoded `CAP` `Ccap^15 = 0x0020` (`HTIRV = 1, MAGB = 0`) even on reversible 5/3
    /// HTJ2K encodes. Repairs reversible `CAP` Table A.3 flags on HTJ2K outputs and brings `.202`
    /// codestreams to PS3.5 2026a 10.18.1 via ``J2KCodestreamInspector/conformingToHTJ2KRPCL(_:)``.
    static func conformingCodestream(_ codestream: Data, transferSyntaxUID: String?) -> Data {
        let capRepaired = J2KCodestreamInspector.conformingToReversibleHTJ2KCAP(codestream)
        guard transferSyntaxUID == TransferSyntax.htj2kRPCLLossless.uid else { return capRepaired }
        return J2KCodestreamInspector.conformingToHTJ2KRPCL(capRepaired)
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
        let pixelCount = descriptor.rows * descriptor.columns
        let widen8To16 = (bytesPerSample == 2 && descriptor.bitsStored <= 8)
        let expectedRawByteCount = widen8To16 ? pixelCount : (pixelCount * bytesPerSample)
        let expectedComponentByteCount = pixelCount * bytesPerSample

        guard image.components.count == descriptor.samplesPerPixel else {
            throw DICOMError.parsingFailed(
                "Decoded component count \(image.components.count) does not match samples per pixel \(descriptor.samplesPerPixel)"
            )
        }

        var components: [Data] = []
        components.reserveCapacity(descriptor.samplesPerPixel)
        for component in image.components {
            guard component.bitDepth == descriptor.bitsStored,
                  component.signed == descriptor.isSigned else {
                throw DICOMError.parsingFailed(
                    "Decoded JPEG 2000 component \(component.index) precision/signedness (\(component.bitDepth)-bit, signed=\(component.signed)) "
                        + "does not match descriptor (\(descriptor.bitsStored)-bit, signed=\(descriptor.isSigned))"
                )
            }
            guard component.data.count == expectedRawByteCount else {
                throw DICOMError.parsingFailed(
                    "Decoded JPEG 2000 component \(component.index) has \(component.data.count) bytes, expected exactly "
                        + "\(expectedRawByteCount) for \(descriptor.columns)x\(descriptor.rows) at "
                        + "\(descriptor.bitsAllocated) bits allocated"
                )
            }
            if widen8To16 {
                var widened = Data(count: expectedComponentByteCount)
                let isSigned8 = descriptor.isSigned
                component.data.withUnsafeBytes { srcRaw in
                    widened.withUnsafeMutableBytes { dstRaw in
                        let src = srcRaw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let dst = dstRaw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        for p in 0..<pixelCount {
                            let u = src[p]
                            dst[p * 2] = u
                            dst[p * 2 + 1] = (isSigned8 && (u & 0x80) != 0) ? 0xFF : 0x00
                        }
                    }
                }
                components.append(widened)
            } else {
                var plane = component.data
                swapBytesInPlaceIfNeeded(&plane, bytesPerSample: bytesPerSample)
                components.append(plane)
            }
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
