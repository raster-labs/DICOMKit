import Foundation
import SwiftJ2K

/// Selects which JPEG 2000 decode execution path the J2K Compare panel exercises.
/// The viewer's production decode path is unaffected — it uses `J2KSwiftCodec.decodeFrame`.
public enum J2KSwiftDecodeMode: String, Sendable, CaseIterable, Identifiable {
    /// CPU path (`.accelerate` SIMD when available, else `.scalar`).
    case cpu
    /// Metal GPU decode path when available on the host.
    case decodeGPU
    /// Full Metal GPU decode path when available on the host.
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

/// Selects which JPEG 2000 encode execution path the J2K Compare panel exercises.
public enum J2KSwiftEncodeMode: String, Sendable, CaseIterable, Identifiable {
    /// CPU encode path (`.accelerate` SIMD when available, else `.scalar`).
    case cpu
    /// Metal GPU encode path when available on the host.
    case gpu

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .cpu: return "CPU `encode`"
        case .gpu: return "`encodeGPU`"
        }
    }
}

/// JPEG 2000 Part 1 (`.90`/`.91`), Part 2 Multi-component (`.92`/`.93`), and Part 15 HTJ2K
/// (`.201`/`.202`/`.203`) DICOM codec adapter backed by `SwiftJ2K`.
///
/// NEMA-verified: 2026a, checked 2026-09-25 — JPEG 2000 / HTJ2K UIDs come from `TransferSyntax`
/// (PS3.6 2026a Table A-1); the lossless-only set (.90, .92, .201, .202) and the RPCL requirement
/// for .202 match PS3.5 2026a A.4.4.
public struct J2KSwiftCodec: ImageCodec, ImageEncoder, DecodeBackendConfigurableCodec, ProgressiveResolutionDecodableCodec, Sendable {
    /// Finite decode policy that does not construct or retain transfer-syntax Strings.
    public enum DecodingSyntax: UInt8, Sendable {
        /// Admit any JPEG 2000 Part 1, Part 2, or HTJ2K codestream supported by this codec.
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

    public static let supportedEncodingTransferSyntaxes: [String] = supportedTransferSyntaxes.filter {
        J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: $0) == nil
    }

    /// Transfer syntaxes whose definition promises exact sample reconstruction (PS3.5 A.4.4).
    public static let losslessOnlyTransferSyntaxes: Set<String> = [
        TransferSyntax.jpeg2000Lossless.uid,
        TransferSyntax.jpeg2000Part2Lossless.uid,
        TransferSyntax.htj2kLossless.uid,
        TransferSyntax.htj2kRPCLLossless.uid
    ]

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

        var resolvedTransferSyntaxUID: String? {
            switch self {
            case .any, .htj2kAny, .unsupported:
                return nil
            case .jpeg2000Lossless:
                return TransferSyntax.jpeg2000Lossless.uid
            case .jpeg2000:
                return TransferSyntax.jpeg2000.uid
            case .jpeg2000Part2Lossless:
                return TransferSyntax.jpeg2000Part2Lossless.uid
            case .jpeg2000Part2:
                return TransferSyntax.jpeg2000Part2.uid
            case .htj2kLossless:
                return TransferSyntax.htj2kLossless.uid
            case .htj2kRPCLLossless:
                return TransferSyntax.htj2kRPCLLossless.uid
            case .htj2kLossy:
                return TransferSyntax.htj2kLossy.uid
            }
        }

        var isLosslessOnly: Bool {
            switch self {
            case .jpeg2000Lossless, .jpeg2000Part2Lossless, .htj2kLossless, .htj2kRPCLLossless:
                return true
            case .any, .htj2kAny, .jpeg2000, .jpeg2000Part2, .htj2kLossy, .unsupported:
                return false
            }
        }
    }

    private let encodingTransferSyntaxUID: String?
    private let decodeBackend: CodecBackend?
    private let decodingTransferSyntaxUID: String?
    private let syntaxRestriction: SyntaxRestriction
    private let decodingLimits: PixelDecodeLimits

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

    // MARK: - Explicit Mode & Benchmark Entry Points (DICOMStudio J2K Compare / Test Bench)

    public static func decode(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        mode: J2KSwiftDecodeMode
    ) throws -> Data {
        if let reason = J2KRoutePlanner.unsupportedDecodeReason(frameData: frameData) {
            throw DICOMError.unsupportedTransferSyntax(reason)
        }
        let backend = Self.resolvedBackend(for: mode)
        let codec = SwiftJ2KDICOMCodec(
            decodingTransferSyntaxUID: nil,
            decodeBackend: backend,
            options: .default
        )
        return try codec.decodeFrame(
            frameData,
            descriptor: Self.normalizedDecodeDescriptor(descriptor),
            frameIndex: 0
        )
    }

    public static func encode(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        transferSyntaxUID: String,
        configuration: CompressionConfiguration,
        mode: J2KSwiftEncodeMode
    ) throws -> Data {
        if let reason = J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: transferSyntaxUID) {
            throw DICOMError.unsupportedTransferSyntax(reason)
        }
        let backend = Self.resolvedBackend(for: mode)
        let adjustedConfig = CompressionConfiguration(
            quality: configuration.quality,
            speed: configuration.speed,
            progressive: configuration.progressive,
            preferLossless: configuration.preferLossless,
            maxBitsPerSample: configuration.maxBitsPerSample,
            forcedBackend: backend
        )
        let codec = SwiftJ2KDICOMCodec(
            encodingTransferSyntaxUID: transferSyntaxUID,
            options: .default
        )
        return try codec.encodeFrame(
            frameData,
            descriptor: Self.normalizedEncodeDescriptor(descriptor),
            frameIndex: 0,
            configuration: adjustedConfig
        )
    }

    public static func benchEncode(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        transferSyntaxUID: String,
        configuration: CompressionConfiguration,
        mode: J2KSwiftEncodeMode,
        warmups: Int,
        runs: Int
    ) -> (data: Data?, samples: [Double], error: String?) {
        if let reason = J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: transferSyntaxUID) {
            return (nil, [], reason)
        }
        let backend = Self.resolvedBackend(for: mode)
        let adjustedConfig = CompressionConfiguration(
            quality: configuration.quality,
            speed: configuration.speed,
            progressive: configuration.progressive,
            preferLossless: configuration.preferLossless,
            maxBitsPerSample: configuration.maxBitsPerSample,
            forcedBackend: backend
        )
        let codec = SwiftJ2KDICOMCodec(
            encodingTransferSyntaxUID: transferSyntaxUID,
            options: .default
        )
        let normDescriptor = Self.normalizedEncodeDescriptor(descriptor)
        do {
            var lastOut: Data?
            for _ in 0..<max(0, warmups) {
                lastOut = try codec.encodeFrame(frameData, descriptor: normDescriptor, frameIndex: 0, configuration: adjustedConfig)
            }
            var samples: [Double] = []
            samples.reserveCapacity(max(0, runs))
            for _ in 0..<max(0, runs) {
                let t0 = DispatchTime.now()
                lastOut = try codec.encodeFrame(frameData, descriptor: normDescriptor, frameIndex: 0, configuration: adjustedConfig)
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
                samples.append(elapsedMs)
            }
            return (lastOut, samples, nil)
        } catch {
            return (nil, [], error.localizedDescription)
        }
    }

    public static func benchDecode(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        mode: J2KSwiftDecodeMode,
        warmups: Int,
        runs: Int
    ) -> (data: Data?, samples: [Double], error: String?) {
        if let reason = J2KRoutePlanner.unsupportedDecodeReason(frameData: frameData) {
            return (nil, [], reason)
        }
        let backend = Self.resolvedBackend(for: mode)
        let codec = SwiftJ2KDICOMCodec(
            decodingTransferSyntaxUID: nil,
            decodeBackend: backend,
            options: .default
        )
        let normDescriptor = Self.normalizedDecodeDescriptor(descriptor)
        do {
            var lastOut: Data?
            for _ in 0..<max(0, warmups) {
                lastOut = try codec.decodeFrame(frameData, descriptor: normDescriptor, frameIndex: 0)
            }
            var samples: [Double] = []
            samples.reserveCapacity(max(0, runs))
            for _ in 0..<max(0, runs) {
                let t0 = DispatchTime.now()
                lastOut = try codec.decodeFrame(frameData, descriptor: normDescriptor, frameIndex: 0)
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
                samples.append(elapsedMs)
            }
            return (lastOut, samples, nil)
        } catch {
            return (nil, [], error.localizedDescription)
        }
    }

    // MARK: - ImageCodec

    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        guard !frameData.isEmpty else {
            throw DICOMError.parsingFailed("Empty JPEG 2000 data")
        }
        _ = try decodingLimits.validate(frameData, descriptor: descriptor, frameIndex: frameIndex)
        guard syntaxRestriction != .unsupported else {
            throw DICOMError.unsupportedTransferSyntax("Unsupported JPEG 2000 decoding transfer syntax")
        }
        if let reason = Self.irreversibleWaveletRefusal(frameData: frameData, transferSyntaxUID: decodingTransferSyntaxUID) {
            throw DICOMError.parsingFailed(reason)
        }
        if decodingTransferSyntaxUID == nil, syntaxRestriction.isLosslessOnly,
           J2KCodestreamInspector.usesIrreversibleWavelet(in: frameData) {
            throw DICOMError.parsingFailed(
                "JPEG 2000 codestream selects the irreversible 9/7 wavelet under a lossless-only transfer syntax; refusing to decode inexact samples"
            )
        }
        if let reason = J2KRoutePlanner.unsupportedDecodeReason(frameData: frameData) {
            throw DICOMError.unsupportedTransferSyntax(reason)
        }

        let delegate = makeBackingDecoder()
        return try delegate.decodeFrame(
            frameData,
            descriptor: Self.normalizedDecodeDescriptor(descriptor),
            frameIndex: frameIndex
        )
    }

    public func decodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        into destination: UnsafeMutableRawBufferPointer
    ) throws -> Int {
        guard !frameData.isEmpty else {
            throw DICOMError.parsingFailed("Empty JPEG 2000 data")
        }
        let expectedBytes = try decodingLimits.validate(frameData, descriptor: descriptor, frameIndex: frameIndex)
        guard destination.count >= expectedBytes, destination.baseAddress != nil else {
            throw DICOMError.limitExceeded(
                "Caller-owned destination too small: \(destination.count) bytes for \(expectedBytes)-byte frame"
            )
        }
        guard syntaxRestriction != .unsupported else {
            throw DICOMError.unsupportedTransferSyntax("Unsupported JPEG 2000 decoding transfer syntax")
        }
        if let reason = Self.irreversibleWaveletRefusal(frameData: frameData, transferSyntaxUID: decodingTransferSyntaxUID) {
            throw DICOMError.parsingFailed(reason)
        }
        if decodingTransferSyntaxUID == nil, syntaxRestriction.isLosslessOnly,
           J2KCodestreamInspector.usesIrreversibleWavelet(in: frameData) {
            throw DICOMError.parsingFailed(
                "JPEG 2000 codestream selects the irreversible 9/7 wavelet under a lossless-only transfer syntax; refusing to decode inexact samples"
            )
        }
        if let reason = J2KRoutePlanner.unsupportedDecodeReason(frameData: frameData) {
            throw DICOMError.unsupportedTransferSyntax(reason)
        }

        let delegate = makeBackingDecoder()
        return try delegate.decodeFrame(
            frameData,
            descriptor: Self.normalizedDecodeDescriptor(descriptor),
            frameIndex: frameIndex,
            into: destination
        )
    }

    public func decodePixelFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> DecodedPixelFrame {
        let decoded = try decodeFrame(frameData, descriptor: descriptor, frameIndex: frameIndex)
        return DecodedPixelFrame(
            data: decoded,
            descriptor: Self.outputDescriptor(for: descriptor),
            sourceFrameIndex: frameIndex
        )
    }

    // MARK: - Managed Budget-Accounted Decoding

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

    @available(*, noasync, message: "Invoke on a synchronous worker thread outside Swift's cooperative pool")
    public func decodeManagedPixelFrameOutcome(
        _ frameData: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        budget: borrowing DICOMAllocationBudget,
        cancellation: DICOMCancellation = .never
    ) -> DICOMManagedOutcome<ManagedDecodedPixelFrame> {
        if let failure = cancellation.failure { return .failure(failure) }
        if Task.isCancelled { return .failure(DICOMManagedFailure(.cancelled)) }
        guard frameData.isOwned(by: budget) else {
            return .failure(DICOMManagedFailure(allocation: .budgetMismatch))
        }
        switch decodingLimits.validateManagedOutcome(
            encodedByteCount: frameData.count,
            descriptor: descriptor,
            frameIndex: frameIndex
        ) {
        case .success: break
        case .failure(let failure): return .failure(failure)
        }
        guard syntaxRestriction != .unsupported else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 400))
        }

        let delegate = makeBackingDecoder()
        let normDescriptor = Self.normalizedDecodeDescriptor(descriptor)
        switch delegate.decodeManagedPixelFrameOutcome(
            frameData,
            descriptor: normDescriptor,
            frameIndex: frameIndex,
            budget: budget,
            cancellation: cancellation
        ) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let decoded):
            return .success(ManagedDecodedPixelFrame(
                data: decoded.data,
                descriptor: Self.outputDescriptor(for: descriptor),
                sourceFrameIndex: decoded.sourceFrameIndex
            ))
        }
    }

    package static func outputDescriptor(for descriptor: PixelDataDescriptor) -> PixelDataDescriptor {
        SwiftJ2KDICOMCodec.outputDescriptor(for: descriptor)
    }

    // MARK: - ImageEncoder

    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        guard J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: encodingTransferSyntaxUID) == nil else {
            return false
        }
        guard descriptor.rows > 0, descriptor.columns > 0, descriptor.numberOfFrames >= 1 else {
            return false
        }
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
            return false
        }
        guard (2...descriptor.bitsAllocated).contains(descriptor.bitsStored),
              descriptor.highBit == descriptor.bitsStored - 1 else {
            return false
        }
        guard descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3 else {
            return false
        }
        if descriptor.samplesPerPixel == 3 {
            switch descriptor.photometricInterpretation {
            case .ybrFull422, .ybrPartial422, .ybrPartial420:
                return false
            default:
                break
            }
        }
        return true
    }

    public func encodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        configuration: CompressionConfiguration
    ) throws -> Data {
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

        // Fall back cleanly if a forced hardware backend is absent on this host (e.g. virtualised CI VMs).
        let effectiveForced = Self.effectiveAvailableBackend(configuration.forcedBackend)
        let effectiveConfiguration: CompressionConfiguration
        if effectiveForced == configuration.forcedBackend {
            effectiveConfiguration = configuration
        } else {
            effectiveConfiguration = CompressionConfiguration(
                quality: configuration.quality,
                speed: configuration.speed,
                progressive: configuration.progressive,
                preferLossless: configuration.preferLossless,
                maxBitsPerSample: configuration.maxBitsPerSample,
                forcedBackend: effectiveForced
            )
        }

        let delegate = SwiftJ2KDICOMCodec(
            encodingTransferSyntaxUID: encodingTransferSyntaxUID,
            options: .from(decodingLimits: decodingLimits)
        )
        return try delegate.encodeFrame(
            frameData,
            descriptor: Self.normalizedEncodeDescriptor(descriptor),
            frameIndex: frameIndex,
            configuration: effectiveConfiguration
        )
    }

    // MARK: - Progressive Resolution Preview

    public func decodeFrameAtResolution(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        level: Int
    ) async throws -> (data: Data, rows: Int, columns: Int) {
        try Task.checkCancellation()
        guard !frameData.isEmpty else {
            throw DICOMError.parsingFailed("Empty JPEG 2000 data")
        }
        _ = try decodingLimits.validate(frameData, descriptor: descriptor, frameIndex: 0)
        guard syntaxRestriction != .unsupported else {
            throw DICOMError.unsupportedTransferSyntax("Unsupported JPEG 2000 decoding transfer syntax")
        }
        if let reason = Self.irreversibleWaveletRefusal(frameData: frameData, transferSyntaxUID: decodingTransferSyntaxUID) {
            throw DICOMError.parsingFailed(reason)
        }
        if decodingTransferSyntaxUID == nil, syntaxRestriction.isLosslessOnly,
           J2KCodestreamInspector.usesIrreversibleWavelet(in: frameData) {
            throw DICOMError.parsingFailed(
                "JPEG 2000 codestream selects the irreversible 9/7 wavelet under a lossless-only transfer syntax; refusing to decode inexact samples"
            )
        }
        let delegate = makeBackingDecoder()
        return try await delegate.decodeFrameAtResolution(
            frameData,
            descriptor: Self.normalizedDecodeDescriptor(descriptor),
            level: level
        )
    }

    // MARK: - Private Helpers

    private func makeBackingDecoder() -> SwiftJ2KDICOMCodec {
        let effectiveBackend = Self.effectiveAvailableBackend(decodeBackend)
        return SwiftJ2KDICOMCodec(
            encodingTransferSyntaxUID: encodingTransferSyntaxUID,
            decodingTransferSyntaxUID: decodingTransferSyntaxUID ?? syntaxRestriction.resolvedTransferSyntaxUID,
            decodeBackend: effectiveBackend,
            options: .from(decodingLimits: decodingLimits),
            requiresHTJ2KCAPWhenUIDNil: syntaxRestriction == .htj2kAny
        )
    }

    private static func effectiveAvailableBackend(_ requested: CodecBackend?) -> CodecBackend? {
        guard let requested else { return nil }
        if SwiftJ2KDICOMCodec.supportsBackend(requested) {
            return requested
        }
        return CodecBackendPreference(forced: requested).effective
    }

    private static func resolvedBackend(for mode: J2KSwiftDecodeMode) -> CodecBackend {
        switch mode {
        case .cpu:
            return CodecCapabilities.isSIMDAvailable ? .accelerate : .scalar
        case .decodeGPU, .decodeWithGPUHT:
            if CodecCapabilities.isMetalAvailable {
                return .metal
            }
            return CodecCapabilities.isSIMDAvailable ? .accelerate : .scalar
        }
    }

    private static func resolvedBackend(for mode: J2KSwiftEncodeMode) -> CodecBackend {
        switch mode {
        case .cpu:
            return CodecCapabilities.isSIMDAvailable ? .accelerate : .scalar
        case .gpu:
            if CodecCapabilities.isMetalAvailable {
                return .metal
            }
            return CodecCapabilities.isSIMDAvailable ? .accelerate : .scalar
        }
    }

    private static func normalizedDecodeDescriptor(_ descriptor: PixelDataDescriptor) -> PixelDataDescriptor {
        if descriptor.samplesPerPixel == 1,
           descriptor.photometricInterpretation != .monochrome1,
           descriptor.photometricInterpretation != .monochrome2 {
            return PixelDataDescriptor(
                rows: descriptor.rows,
                columns: descriptor.columns,
                numberOfFrames: descriptor.numberOfFrames,
                bitsAllocated: descriptor.bitsAllocated,
                bitsStored: descriptor.bitsStored,
                highBit: descriptor.highBit,
                isSigned: descriptor.isSigned,
                samplesPerPixel: 1,
                photometricInterpretation: .monochrome2,
                planarConfiguration: descriptor.planarConfiguration
            )
        }
        if descriptor.samplesPerPixel == 3 {
            switch descriptor.photometricInterpretation {
            case .rgb, .ybrRCT, .ybrICT, .ybrFull422, .ybrPartial422, .ybrPartial420:
                return descriptor
            default:
                return PixelDataDescriptor(
                    rows: descriptor.rows,
                    columns: descriptor.columns,
                    numberOfFrames: descriptor.numberOfFrames,
                    bitsAllocated: descriptor.bitsAllocated,
                    bitsStored: descriptor.bitsStored,
                    highBit: descriptor.highBit,
                    isSigned: descriptor.isSigned,
                    samplesPerPixel: 3,
                    photometricInterpretation: .rgb,
                    planarConfiguration: descriptor.planarConfiguration
                )
            }
        }
        return descriptor
    }

    private static func normalizedEncodeDescriptor(_ descriptor: PixelDataDescriptor) -> PixelDataDescriptor {
        if descriptor.samplesPerPixel == 1,
           descriptor.photometricInterpretation != .monochrome1,
           descriptor.photometricInterpretation != .monochrome2 {
            return PixelDataDescriptor(
                rows: descriptor.rows,
                columns: descriptor.columns,
                numberOfFrames: descriptor.numberOfFrames,
                bitsAllocated: descriptor.bitsAllocated,
                bitsStored: descriptor.bitsStored,
                highBit: descriptor.highBit,
                isSigned: descriptor.isSigned,
                samplesPerPixel: 1,
                photometricInterpretation: .monochrome2,
                planarConfiguration: descriptor.planarConfiguration
            )
        }
        if descriptor.samplesPerPixel == 3 {
            switch descriptor.photometricInterpretation {
            case .rgb, .ybrFull422, .ybrPartial422, .ybrPartial420:
                return descriptor
            default:
                return PixelDataDescriptor(
                    rows: descriptor.rows,
                    columns: descriptor.columns,
                    numberOfFrames: descriptor.numberOfFrames,
                    bitsAllocated: descriptor.bitsAllocated,
                    bitsStored: descriptor.bitsStored,
                    highBit: descriptor.highBit,
                    isSigned: descriptor.isSigned,
                    samplesPerPixel: 3,
                    photometricInterpretation: .rgb,
                    planarConfiguration: descriptor.planarConfiguration
                )
            }
        }
        return descriptor
    }
}
