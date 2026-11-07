import Foundation
import SwiftJ2K

/// Capability protocol for JPEG 2000 / HTJ2K decoders that produce coarse reduced-resolution previews.
package protocol ProgressiveResolutionDecodableCodec: ImageCodec {
    func decodeFrameAtResolution(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        level: Int
    ) async throws -> (data: Data, rows: Int, columns: Int)
}

/// 2D JPEG 2000 Part 1 (`.90`/`.91`), Part 2 Multi-component (`.92`/`.93`), and Part 15 HTJ2K
/// (`.201`/`.202`/`.203`) DICOM codec backed by `SwiftJ2K`.
///
/// Supports `auto` (`nil`), `.scalar`, `.accelerate` (CPU SIMD), and `.metal` (Metal GPU) backend
/// routing without mislabelling, preserves exact sample values, signedness, and bit depth without
/// implicit scaling or pointer escapes, and participates in `DICOMAllocationBudget` /
/// `ManagedDecodedPixelFrame` bounded admission alongside `SwiftJ2K.ResourceLimits`.
public struct SwiftJ2KDICOMCodec: ImageCodec, ImageEncoder, DecodeBackendConfigurableCodec, ProgressiveResolutionDecodableCodec, Sendable {
    public static let engineName = "SwiftJ2K"
    public static let engineVersion = "12.1.0"

    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.jpeg2000Lossless.uid,
        TransferSyntax.jpeg2000.uid,
        TransferSyntax.jpeg2000Part2Lossless.uid,
        TransferSyntax.jpeg2000Part2.uid,
        TransferSyntax.htj2kLossless.uid,
        TransferSyntax.htj2kRPCLLossless.uid,
        TransferSyntax.htj2kLossy.uid
    ]

    public static let supportedEncodingTransferSyntaxes: [String] = [
        TransferSyntax.jpeg2000Lossless.uid,
        TransferSyntax.jpeg2000.uid,
        TransferSyntax.jpeg2000Part2Lossless.uid,
        TransferSyntax.jpeg2000Part2.uid,
        TransferSyntax.htj2kLossless.uid,
        TransferSyntax.htj2kRPCLLossless.uid,
        TransferSyntax.htj2kLossy.uid
    ]

    public static let losslessOnlyTransferSyntaxes: Set<String> = [
        TransferSyntax.jpeg2000Lossless.uid,
        TransferSyntax.jpeg2000Part2Lossless.uid,
        TransferSyntax.htj2kLossless.uid,
        TransferSyntax.htj2kRPCLLossless.uid
    ]

    public let encodingTransferSyntaxUID: String?
    public let decodingTransferSyntaxUID: String?
    public let decodeBackend: CodecBackend?
    public let options: SwiftJ2KProviderOptions
    package let requiresHTJ2KCAPWhenUIDNil: Bool

    public init(
        encodingTransferSyntaxUID: String? = nil,
        decodingTransferSyntaxUID: String? = nil,
        decodeBackend: CodecBackend? = nil,
        options: SwiftJ2KProviderOptions = .default
    ) {
        self.encodingTransferSyntaxUID = encodingTransferSyntaxUID
        self.decodingTransferSyntaxUID = decodingTransferSyntaxUID
        self.decodeBackend = decodeBackend
        self.options = options
        self.requiresHTJ2KCAPWhenUIDNil = false
    }

    package init(
        encodingTransferSyntaxUID: String? = nil,
        decodingTransferSyntaxUID: String? = nil,
        decodeBackend: CodecBackend? = nil,
        options: SwiftJ2KProviderOptions = .default,
        requiresHTJ2KCAPWhenUIDNil: Bool
    ) {
        self.encodingTransferSyntaxUID = encodingTransferSyntaxUID
        self.decodingTransferSyntaxUID = decodingTransferSyntaxUID
        self.decodeBackend = decodeBackend
        self.options = options
        self.requiresHTJ2KCAPWhenUIDNil = requiresHTJ2KCAPWhenUIDNil
    }

    public func withDecodeBackend(_ decodeBackend: CodecBackend?) -> any ImageCodec {
        SwiftJ2KDICOMCodec(
            encodingTransferSyntaxUID: encodingTransferSyntaxUID,
            decodingTransferSyntaxUID: decodingTransferSyntaxUID,
            decodeBackend: decodeBackend,
            options: options,
            requiresHTJ2KCAPWhenUIDNil: requiresHTJ2KCAPWhenUIDNil
        )
    }

    // MARK: - Pre-Execution Capability & Backend Predicates

    /// Checks whether the requested `CodecBackend` (`nil`/`auto`, `.scalar`, `.accelerate`, `.metal`)
    /// is available on the current runtime without mislabelling CPU SIMD vs Metal GPU execution.
    public static func supportsBackend(_ backend: CodecBackend?) -> Bool {
        guard let backend else { return true }
        switch backend {
        case .scalar:
            return true
        case .accelerate:
            return CodecCapabilities.isSIMDAvailable
        case .metal:
            return CodecCapabilities.isMetalAvailable
        }
    }

    static func resolveExecution(
        for backend: CodecBackend?
    ) -> (policy: ExecutionPolicy, enginePreference: AcceleratedEnginePreference) {
        guard let backend else {
            return (.automatic, .automatic)
        }
        switch backend {
        case .scalar:
            return (.required(.scalarCPU), .automatic)
        case .accelerate:
            return (.required(.accelerated), .cpuSIMD)
        case .metal:
            return (.required(.accelerated), .metalGPU)
        }
    }

    static func verifyExecutedBackend(
        report: OperationReport,
        requested: CodecBackend?
    ) throws {
        guard let requested else { return }
        switch requested {
        case .scalar:
            guard report.backend == .scalarCPU && report.acceleratedEngine == .none else {
                throw DICOMError.parsingFailed(
                    "Requested scalar backend, but SwiftJ2K reported backend=\(report.backend) engine=\(report.acceleratedEngine)"
                )
            }
        case .accelerate:
            guard report.backend == .accelerated && report.acceleratedEngine == .cpuSIMD else {
                throw DICOMError.parsingFailed(
                    "Requested CPU SIMD (.accelerate) backend, but SwiftJ2K reported backend=\(report.backend) engine=\(report.acceleratedEngine)"
                )
            }
        case .metal:
            guard report.backend == .accelerated && report.acceleratedEngine == .metalGPU else {
                throw DICOMError.parsingFailed(
                    "Requested Metal GPU (.metal) backend, but SwiftJ2K reported backend=\(report.backend) engine=\(report.acceleratedEngine)"
                )
            }
        }
    }

    public static func supportsDecodeProfile(
        transferSyntaxUID: String?,
        descriptor: PixelDataDescriptor?,
        decodeBackend: CodecBackend?,
        options: SwiftJ2KProviderOptions = .default
    ) -> Bool {
        let effectiveBackend = decodeBackend ?? options.defaultBackend
        guard supportsBackend(effectiveBackend) else { return false }
        if let transferSyntaxUID, !supportedTransferSyntaxes.contains(transferSyntaxUID) {
            return false
        }
        guard let descriptor else { return true }
        guard validateCommonGeometry(descriptor, options: options) != nil else {
            return false
        }
        let isLosslessOnly = transferSyntaxUID.map(losslessOnlyTransferSyntaxes.contains) ?? false
        switch descriptor.samplesPerPixel {
        case 1:
            return descriptor.photometricInterpretation == .monochrome1
                || descriptor.photometricInterpretation == .monochrome2
        case 3:
            switch descriptor.photometricInterpretation {
            case .rgb, .ybrRCT:
                return true
            case .ybrICT:
                return !isLosslessOnly
            default:
                return false
            }
        default:
            return false
        }
    }

    public static func supportsEncodeProfile(
        transferSyntaxUID: String?,
        configuration: CompressionConfiguration,
        descriptor: PixelDataDescriptor,
        options: SwiftJ2KProviderOptions = .default
    ) -> Bool {
        let effectiveBackend = configuration.forcedBackend ?? options.defaultBackend
        guard supportsBackend(effectiveBackend) else { return false }
        if let transferSyntaxUID, !supportedEncodingTransferSyntaxes.contains(transferSyntaxUID) {
            return false
        }
        guard validateCommonGeometry(descriptor, options: options) != nil else {
            return false
        }
        if let maxBits = configuration.maxBitsPerSample, maxBits < descriptor.bitsStored {
            // Never silently reduce bit depth in the successor integration.
            return false
        }

        // Verify RPCL (.202) decomposition feasibility before execution (PS3.5 §10.18.1).
        if transferSyntaxUID == TransferSyntax.htj2kRPCLLossless.uid {
            let needed = J2KCodestreamInspector.minimumDecompositionLevelsForRPCL(
                rows: descriptor.rows,
                columns: descriptor.columns
            )
            let smallest = min(descriptor.rows, descriptor.columns)
            let deepest = Int.bitWidth - 1 - smallest.leadingZeroBitCount
            if min(10, deepest) < needed {
                return false
            }
        }

        switch descriptor.samplesPerPixel {
        case 1:
            return descriptor.photometricInterpretation == .monochrome1
                || descriptor.photometricInterpretation == .monochrome2
        case 3:
            return descriptor.photometricInterpretation == .rgb
                || descriptor.photometricInterpretation == .ybrRCT
                || descriptor.photometricInterpretation == .ybrICT
        default:
            return false
        }
    }

    public func canDecode(_ descriptor: PixelDataDescriptor) -> Bool {
        Self.supportsDecodeProfile(
            transferSyntaxUID: decodingTransferSyntaxUID,
            descriptor: descriptor,
            decodeBackend: decodeBackend,
            options: options
        )
    }

    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        Self.supportsEncodeProfile(
            transferSyntaxUID: encodingTransferSyntaxUID,
            configuration: configuration,
            descriptor: descriptor,
            options: options
        )
    }

    // MARK: - Decoding

    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        let prepared = try prepareDecode(frameData, descriptor: descriptor, frameIndex: frameIndex)
        let decoded = try SwiftJ2KSyncBridge.run(options: options) { [options] in
            try await Self.executeDecode(prepared: prepared, options: options)
        }
        try finishDecodeTelemetryAndChecks(decoded, prepared: prepared, frameIndex: frameIndex)

        let expectedBytes = prepared.expectedFrameBytes
        return try decoded.image.storage.withUnsafeBytes { rawBytes in
            guard rawBytes.count >= expectedBytes else {
                throw DICOMError.parsingFailed(
                    "SwiftJ2K decoded storage (\(rawBytes.count) bytes) shorter than expected frame (\(expectedBytes) bytes)"
                )
            }
            return Data(rawBytes.prefix(expectedBytes))
        }
    }

    public func decodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        into destination: UnsafeMutableRawBufferPointer
    ) throws -> Int {
        let prepared = try prepareDecode(frameData, descriptor: descriptor, frameIndex: frameIndex)
        guard destination.count >= prepared.expectedFrameBytes, let dstBase = destination.baseAddress else {
            throw DICOMError.limitExceeded(
                "Caller-owned destination too small: \(destination.count) bytes for \(prepared.expectedFrameBytes)-byte frame"
            )
        }
        let decoded = try SwiftJ2KSyncBridge.run(options: options) { [options] in
            try await Self.executeDecode(prepared: prepared, options: options)
        }
        try finishDecodeTelemetryAndChecks(decoded, prepared: prepared, frameIndex: frameIndex)

        let expectedBytes = prepared.expectedFrameBytes
        try decoded.image.storage.withUnsafeBytes { rawBytes in
            guard rawBytes.count >= expectedBytes, let srcBase = rawBytes.baseAddress else {
                throw DICOMError.parsingFailed("SwiftJ2K decoded storage capacity mismatch")
            }
            dstBase.copyMemory(from: srcBase, byteCount: expectedBytes)
        }
        return expectedBytes
    }

    public func decodePixelFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int
    ) throws -> DecodedPixelFrame {
        let decoded = try decodeFrame(frameData, descriptor: descriptor, frameIndex: frameIndex)
        return DecodedPixelFrame(
            data: decoded,
            descriptor: Self.outputDescriptor(for: descriptor),
            sourceFrameIndex: frameIndex
        )
    }

    /// Native async entry point for callers already executing inside Swift structured concurrency.
    public func decodeFrameAsync(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int
    ) async throws -> Data {
        try Task.checkCancellation()
        let prepared = try prepareDecode(frameData, descriptor: descriptor, frameIndex: frameIndex)
        let decoded: DecodedImage
        do {
            decoded = try await Self.executeDecode(prepared: prepared, options: options)
        } catch {
            throw SwiftJ2KSyncBridge.translateError(error)
        }
        try finishDecodeTelemetryAndChecks(decoded, prepared: prepared, frameIndex: frameIndex)
        let expectedBytes = prepared.expectedFrameBytes
        return try decoded.image.storage.withUnsafeBytes { rawBytes in
            guard rawBytes.count >= expectedBytes else {
                throw DICOMError.parsingFailed("SwiftJ2K decoded storage capacity mismatch")
            }
            return Data(rawBytes.prefix(expectedBytes))
        }
    }

    /// Decodes a coarse reduced-resolution preview (`level == 0` is full resolution; each level up halves both dimensions).
    public func decodeFrameAtResolution(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        level: Int
    ) async throws -> (data: Data, rows: Int, columns: Int) {
        try Task.checkCancellation()
        guard level >= 0 else {
            throw DICOMError.parsingFailed("Resolution level (\(level)) must be non-negative")
        }
        let fullBytes = try await decodeFrameAsync(frameData, descriptor: descriptor, frameIndex: 0)
        guard level > 0 else {
            return (fullBytes, descriptor.rows, descriptor.columns)
        }
        let factor = 1 << min(30, level)
        let newRows = max(1, (descriptor.rows + factor - 1) / factor)
        let newCols = max(1, (descriptor.columns + factor - 1) / factor)
        let downsampled = Self.downsamplePackedPixels(
            fullBytes,
            descriptor: descriptor,
            factor: factor,
            newRows: newRows,
            newCols: newCols
        )
        return (downsampled, newRows, newCols)
    }

    // MARK: - Managed Budget-Accounted Decoding

    /// Decode a JPEG 2000 Part 1 / Part 2 / HTJ2K frame into explicitly admitted `DICOMAllocationBudget` backing.
    @available(*, noasync, message: "Invoke on a synchronous worker thread outside Swift's cooperative pool")
    public func decodeManagedPixelFrame(
        _ frameData: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        budget: borrowing DICOMAllocationBudget,
        cancellation: DICOMCancellation = .never
    ) throws(DICOMManagedFailure) -> ManagedDecodedPixelFrame {
        try decodeManagedPixelFrameOutcome(
            frameData,
            descriptor: descriptor,
            frameIndex: frameIndex,
            budget: budget,
            cancellation: cancellation
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
            frameData,
            descriptor: descriptor,
            frameIndex: frameIndex,
            budget: budget,
            execution: execution,
            cancellation: cancellation
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
            frameData,
            descriptor: descriptor,
            frameIndex: frameIndex,
            budget: budget,
            cancellation: cancellation
        )
    }

    /// Decode a JPEG 2000 Part 1 / Part 2 / HTJ2K frame using scalar outcomes and budget-owned `.staging` / `.decoded` backing.
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

        let expectedBytes: Int
        switch options.decodingLimits.validateManagedOutcome(
            encodedByteCount: frameData.count,
            descriptor: descriptor,
            frameIndex: frameIndex
        ) {
        case .success(let value): expectedBytes = value
        case .failure(let failure): return .failure(failure)
        }

        let effectiveBackend = decodeBackend ?? options.defaultBackend
        guard Self.supportsBackend(effectiveBackend) else {
            return .failure(DICOMManagedFailure(.invalidTransferSyntax, 500, domain: 2))
        }
        if let uid = decodingTransferSyntaxUID, !Self.supportedTransferSyntaxes.contains(uid) {
            return .failure(DICOMManagedFailure(.invalidTransferSyntax, 501, domain: 2))
        }
        guard frameData.count <= options.resourceLimits.maximumCompressedBytes,
              descriptor.rows <= options.resourceLimits.maximumDimension,
              descriptor.columns <= options.resourceLimits.maximumDimension,
              descriptor.pixelsPerFrame <= options.resourceLimits.maximumPixels,
              expectedBytes <= options.resourceLimits.maximumDecodedBytes else {
            return .failure(DICOMManagedFailure(.limitExceeded, 502, domain: 2))
        }
        guard Self.supportsDecodeProfile(
            transferSyntaxUID: decodingTransferSyntaxUID,
            descriptor: descriptor,
            decodeBackend: decodeBackend,
            options: options
        ) else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 503, domain: 2))
        }

        let swiftDescriptor: ImageDescriptor
        do {
            swiftDescriptor = try Self.makeSwiftImageDescriptor(
                from: descriptor,
                limits: options.resourceLimits
            )
        } catch {
            return .failure(SwiftJ2KSyncBridge.translateManagedError(error))
        }

        return frameData.withBorrowedBytes { encoded -> DICOMManagedOutcome<ManagedDecodedPixelFrame> in
            guard let encodedBase = encoded.baseAddress?.assumingMemoryBound(to: UInt8.self),
                  encoded.count >= 2 else {
                return .failure(DICOMManagedFailure(.malformed, 504, domain: 2))
            }

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

            var resolvedCount = initialCount
            let initialView = Data(
                bytesNoCopy: UnsafeMutableRawPointer(mutating: encodedBase),
                count: initialCount,
                deallocator: .none
            )
            if let headerFailure = Self.validateCodestreamHeaderManaged(
                initialView,
                descriptor: descriptor,
                transferSyntaxUID: decodingTransferSyntaxUID,
                requiresHTJ2KCAPWhenUIDNil: requiresHTJ2KCAPWhenUIDNil
            ) {
                if !isBareCodestream,
                   initialCount == encoded.count,
                   encoded.count % 2 == 0,
                   encodedBase[encoded.count - 1] == 0x00 {
                    let unpaddedView = Data(
                        bytesNoCopy: UnsafeMutableRawPointer(mutating: encodedBase),
                        count: encoded.count - 1,
                        deallocator: .none
                    )
                    if Self.validateCodestreamHeaderManaged(
                        unpaddedView,
                        descriptor: descriptor,
                        transferSyntaxUID: decodingTransferSyntaxUID,
                        requiresHTJ2KCAPWhenUIDNil: requiresHTJ2KCAPWhenUIDNil
                    ) == nil {
                        resolvedCount = encoded.count - 1
                    } else {
                        return .failure(headerFailure)
                    }
                } else {
                    return .failure(headerFailure)
                }
            }

            let (stagingByteCount, stagingOverflow) = expectedBytes.addingReportingOverflow(resolvedCount)
            guard !stagingOverflow, stagingByteCount > 0 else {
                return .failure(DICOMManagedFailure(.limitExceeded, 505, domain: 2))
            }

            let isLosslessOnly = decodingTransferSyntaxUID.map(Self.losslessOnlyTransferSyntaxes.contains) ?? false
            let decoded: DecodedImage
            do {
                let staging: DICOMAllocationLease
                switch budget.reserveOutcome(stagingByteCount, as: .staging) {
                case .success(let value): staging = value
                case .failure(let error): return .failure(DICOMManagedFailure(allocation: error))
                }
                if let failure = cancellation.failure {
                    _ = staging.isOwned(by: budget)
                    return .failure(failure)
                }

                let rawCodestream = Data(bytes: encodedBase, count: resolvedCount)
                let codestream = Self.unwrapJP2IfWidened8In16(rawCodestream, descriptor: descriptor)
                let prepared = PreparedDecode(
                    codestream: codestream,
                    swiftDescriptor: swiftDescriptor,
                    expectedFrameBytes: expectedBytes,
                    transferSyntaxUID: decodingTransferSyntaxUID,
                    isLosslessOnly: isLosslessOnly,
                    requestedBackend: effectiveBackend
                )
                let decodeOutcome = SwiftJ2KSyncBridge.runManaged(
                    options: options,
                    cancellation: cancellation
                ) { [options] in
                    try await Self.executeDecode(prepared: prepared, options: options)
                }
                _ = staging.isOwned(by: budget)
                switch decodeOutcome {
                case .success(let value): decoded = value
                case .failure(let failure): return .failure(failure)
                }
            }

            do {
                try Self.verifyExecutedBackend(report: decoded.report, requested: effectiveBackend)
            } catch {
                return .failure(DICOMManagedFailure(.codecResultMismatch, 506, domain: 2))
            }
            if isLosslessOnly && decoded.report.fidelity != .exactSamples {
                return .failure(DICOMManagedFailure(.malformed, 507, domain: 2))
            }

            options.telemetryHandler?(SwiftJ2KOperationRecord(
                kind: .decode,
                transferSyntaxUID: decodingTransferSyntaxUID ?? "unknown",
                targetTransferSyntaxUID: nil,
                frameIndex: frameIndex,
                report: decoded.report
            ))

            switch DICOMByteBuffer.admitInitialized(
                count: expectedBytes,
                budget: budget,
                resource: .decoded,
                initializingWith: { dst in
                    if let failure = cancellation.failure {
                        return failure
                    }
                    do {
                        return try decoded.image.storage.withUnsafeBytes { rawBytes in
                            guard rawBytes.count >= expectedBytes,
                                  let srcBase = rawBytes.baseAddress,
                                  let dstBase = dst.baseAddress else {
                                return DICOMManagedFailure(.codecResultMismatch, 508, domain: 2)
                            }
                            dstBase.copyMemory(from: srcBase, byteCount: expectedBytes)
                            return nil
                        }
                    } catch {
                        return DICOMManagedFailure(.codecFailure, 509, domain: 2)
                    }
                }
            ) {
            case .failure(let failure):
                return .failure(failure)
            case .success(let outputBuffer):
                return .success(ManagedDecodedPixelFrame(
                    data: outputBuffer,
                    descriptor: Self.outputDescriptor(for: descriptor),
                    sourceFrameIndex: frameIndex
                ))
            }
        }
    }

    // MARK: - Encoding

    public func encodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        configuration: CompressionConfiguration
    ) throws -> Data {
        let prepared = try prepareEncode(
            frameData,
            descriptor: descriptor,
            frameIndex: frameIndex,
            configuration: configuration
        )
        let encoded = try SwiftJ2KSyncBridge.run(options: options) { [options] in
            try await Self.executeEncode(prepared: prepared, options: options)
        }
        return try finalizeEncodedFrame(encoded, prepared: prepared, descriptor: descriptor, frameIndex: frameIndex)
    }

    /// Native async entry point for callers already executing inside Swift structured concurrency.
    public func encodeFrameAsync(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        configuration: CompressionConfiguration
    ) async throws -> Data {
        try Task.checkCancellation()
        let prepared = try prepareEncode(
            frameData,
            descriptor: descriptor,
            frameIndex: frameIndex,
            configuration: configuration
        )
        let encoded: EncodedImage
        do {
            encoded = try await Self.executeEncode(prepared: prepared, options: options)
        } catch {
            throw SwiftJ2KSyncBridge.translateError(error)
        }
        return try finalizeEncodedFrame(encoded, prepared: prepared, descriptor: descriptor, frameIndex: frameIndex)
    }

    // MARK: - Internal Helpers

    struct PreparedDecode: Sendable {
        let codestream: Data
        let swiftDescriptor: ImageDescriptor
        let expectedFrameBytes: Int
        let transferSyntaxUID: String?
        let isLosslessOnly: Bool
        let requestedBackend: CodecBackend?
    }

    struct PreparedEncode: Sendable {
        let image: Image
        let encoderConfiguration: EncoderConfiguration
        let transferSyntaxUID: String
        let isLossless: Bool
        let requestedBackend: CodecBackend?
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

    static func stripTrailingEvenPadByteIfPresent(_ data: Data) -> Data {
        let rebased = data.startIndex == 0 ? data : Data(data)
        if rebased.count >= 4,
           rebased.count % 2 == 0,
           rebased[0] == 0xFF,
           rebased[1] == 0x4F,
           rebased[rebased.count - 3] == 0xFF,
           rebased[rebased.count - 2] == 0xD9,
           rebased[rebased.count - 1] == 0x00 {
            return Data(rebased.dropLast())
        }
        if rebased.count >= 12,
           rebased.count % 2 == 0,
           rebased[0] != 0xFF,
           rebased[rebased.count - 1] == 0x00,
           J2KCodestreamInspector.imageHeader(in: rebased) == nil {
            let unpadded = Data(rebased.dropLast())
            if J2KCodestreamInspector.imageHeader(in: unpadded) != nil {
                return unpadded
            }
        }
        return rebased
    }

    private static func unwrapJP2IfWidened8In16(_ data: Data, descriptor: PixelDataDescriptor) -> Data {
        guard descriptor.bitsAllocated == 16 && descriptor.bitsStored <= 8 else { return data }
        let rebased = data.startIndex == 0 ? data : Data(data)
        guard rebased.count >= 12, !(rebased[0] == 0xFF && rebased[1] == 0x4F) else { return rebased }
        return J2KCodestreamInspector.rawCodestreamPayload(in: rebased) ?? rebased
    }

    private static func downsamplePackedPixels(
        _ fullBytes: Data,
        descriptor: PixelDataDescriptor,
        factor: Int,
        newRows: Int,
        newCols: Int
    ) -> Data {
        let bps = descriptor.bytesPerSample
        let spp = descriptor.samplesPerPixel
        let outBytesPerFrame = newRows * newCols * spp * bps
        var out = Data(count: outBytesPerFrame)
        fullBytes.withUnsafeBytes { srcRaw in
            out.withUnsafeMutableBytes { dstRaw in
                guard let src = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let dst = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }
                if spp == 1 {
                    for y in 0..<newRows {
                        let srcY = min(descriptor.rows - 1, y * factor)
                        for x in 0..<newCols {
                            let srcX = min(descriptor.columns - 1, x * factor)
                            let srcOff = (srcY * descriptor.columns + srcX) * bps
                            let dstOff = (y * newCols + x) * bps
                            for b in 0..<bps {
                                dst[dstOff + b] = src[srcOff + b]
                            }
                        }
                    }
                } else if descriptor.planarConfiguration == 1 {
                    let srcPlaneBytes = descriptor.rows * descriptor.columns * bps
                    let dstPlaneBytes = newRows * newCols * bps
                    for c in 0..<spp {
                        let srcPlane = src.advanced(by: c * srcPlaneBytes)
                        let dstPlane = dst.advanced(by: c * dstPlaneBytes)
                        for y in 0..<newRows {
                            let srcY = min(descriptor.rows - 1, y * factor)
                            for x in 0..<newCols {
                                let srcX = min(descriptor.columns - 1, x * factor)
                                let srcOff = (srcY * descriptor.columns + srcX) * bps
                                let dstOff = (y * newCols + x) * bps
                                for b in 0..<bps {
                                    dstPlane[dstOff + b] = srcPlane[srcOff + b]
                                }
                            }
                        }
                    }
                } else {
                    let pixelBytes = spp * bps
                    for y in 0..<newRows {
                        let srcY = min(descriptor.rows - 1, y * factor)
                        for x in 0..<newCols {
                            let srcX = min(descriptor.columns - 1, x * factor)
                            let srcOff = (srcY * descriptor.columns + srcX) * pixelBytes
                            let dstOff = (y * newCols + x) * pixelBytes
                            for b in 0..<pixelBytes {
                                dst[dstOff + b] = src[srcOff + b]
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    static func validateCommonGeometry(
        _ d: PixelDataDescriptor,
        options: SwiftJ2KProviderOptions
    ) -> (pixels: Int, frameBytes: Int)? {
        guard d.rows > 0,
              d.columns > 0,
              d.rows <= options.resourceLimits.maximumDimension,
              d.columns <= options.resourceLimits.maximumDimension,
              d.numberOfFrames >= 1,
              (d.samplesPerPixel == 1 || d.samplesPerPixel == 3),
              (d.bitsAllocated == 8 || d.bitsAllocated == 16),
              (2...d.bitsAllocated).contains(d.bitsStored),
              d.highBit == d.bitsStored - 1,
              (d.planarConfiguration == 0 || d.planarConfiguration == 1) else {
            return nil
        }
        let (pixels, pixelOverflow) = d.rows.multipliedReportingOverflow(by: d.columns)
        let (samples, sampleOverflow) = pixels.multipliedReportingOverflow(by: d.samplesPerPixel)
        let (frameBytes, byteOverflow) = samples.multipliedReportingOverflow(by: d.bitsAllocated / 8)
        guard !pixelOverflow, !sampleOverflow, !byteOverflow,
              pixels > 0,
              pixels <= options.decodingLimits.maximumPixels,
              pixels <= options.resourceLimits.maximumPixels,
              frameBytes > 0,
              frameBytes <= options.decodingLimits.maximumDecodedBytes,
              frameBytes <= options.resourceLimits.maximumDecodedBytes else {
            return nil
        }
        return (pixels, frameBytes)
    }

    static func makeSwiftImageDescriptor(
        from d: PixelDataDescriptor,
        limits: ResourceLimits
    ) throws -> ImageDescriptor {
        switch d.samplesPerPixel {
        case 1:
            if d.bitsAllocated == 8 {
                return try ImageDescriptor.greyscale8(
                    width: d.columns,
                    height: d.rows,
                    meaningfulBits: d.bitsStored,
                    signed: d.isSigned,
                    limits: limits
                )
            } else if d.isSigned {
                return try ImageDescriptor.signedGreyscale16(
                    width: d.columns,
                    height: d.rows,
                    meaningfulBits: d.bitsStored,
                    byteOrder: .littleEndian,
                    limits: limits
                )
            } else {
                return try ImageDescriptor.greyscale16(
                    width: d.columns,
                    height: d.rows,
                    meaningfulBits: d.bitsStored,
                    limits: limits
                )
            }
        case 3:
            if d.planarConfiguration == 1 {
                return try ImageDescriptor.rgbPlanar(
                    width: d.columns,
                    height: d.rows,
                    storageBits: d.bitsAllocated,
                    meaningfulBits: d.bitsStored,
                    signed: d.isSigned,
                    byteOrder: .littleEndian,
                    limits: limits
                )
            } else {
                return try ImageDescriptor.rgbInterleaved(
                    width: d.columns,
                    height: d.rows,
                    storageBits: d.bitsAllocated,
                    meaningfulBits: d.bitsStored,
                    signed: d.isSigned,
                    byteOrder: .littleEndian,
                    limits: limits
                )
            }
        default:
            throw DICOMError.parsingFailed("Unsupported SamplesPerPixel \(d.samplesPerPixel) for SwiftJ2K")
        }
    }

    private static func validateCodestreamHeader(
        _ codestream: Data,
        descriptor: PixelDataDescriptor,
        transferSyntaxUID: String?,
        requiresHTJ2KCAPWhenUIDNil: Bool
    ) throws {
        if let managedFailure = validateCodestreamHeaderManaged(
            codestream,
            descriptor: descriptor,
            transferSyntaxUID: transferSyntaxUID,
            requiresHTJ2KCAPWhenUIDNil: requiresHTJ2KCAPWhenUIDNil
        ) {
            throw DICOMError.parsingFailed(
                "JPEG 2000 codestream header validation failed (\(managedFailure.code), \(managedFailure.operand1))"
            )
        }
    }

    private static func validateCodestreamHeaderManaged(
        _ codestream: Data,
        descriptor: PixelDataDescriptor,
        transferSyntaxUID: String?,
        requiresHTJ2KCAPWhenUIDNil: Bool
    ) -> DICOMManagedFailure? {
        guard let header = J2KCodestreamInspector.imageHeader(in: codestream) else {
            return DICOMManagedFailure(.malformed, 402)
        }
        guard header.width == descriptor.columns, header.height == descriptor.rows else {
            return DICOMManagedFailure(.codecResultMismatch, 406)
        }
        for sizComp in header.components {
            guard sizComp.subsamplingX == 1, sizComp.subsamplingY == 1 else {
                return DICOMManagedFailure(.invalidDescriptor, 414)
            }
        }
        let logicalComponents = header.logicalComponents
        guard logicalComponents.count == descriptor.samplesPerPixel else {
            return DICOMManagedFailure(.codecResultMismatch, 407)
        }
        for comp in logicalComponents {
            guard comp.bitDepth == descriptor.bitsStored,
                  comp.isSigned == descriptor.isSigned else {
                return DICOMManagedFailure(.codecResultMismatch, 408)
            }
        }

        let isLosslessOnly = transferSyntaxUID.map(Self.losslessOnlyTransferSyntaxes.contains) ?? false
        if isLosslessOnly, J2KCodestreamInspector.usesIrreversibleWavelet(in: codestream) {
            return DICOMManagedFailure(.invalidDescriptor, 404)
        }

        if let uid = transferSyntaxUID {
            let isHTSyntax = uid == TransferSyntax.htj2kLossless.uid
                || uid == TransferSyntax.htj2kRPCLLossless.uid
                || uid == TransferSyntax.htj2kLossy.uid
            let isPart1Syntax = uid == TransferSyntax.jpeg2000Lossless.uid
                || uid == TransferSyntax.jpeg2000.uid
            let isPart2Syntax = uid == TransferSyntax.jpeg2000Part2Lossless.uid
                || uid == TransferSyntax.jpeg2000Part2.uid
            let hasPart2Markers = J2KCodestreamInspector.containsPart2MultiComponentTransform(in: codestream)
                || header.cbdComponents != nil
                || header.hasPart2CAPMarker

            if isHTSyntax {
                if !header.hasPart15CAPMarker {
                    return DICOMManagedFailure(.invalidDescriptor, 412)
                }
                if hasPart2Markers {
                    return DICOMManagedFailure(.invalidDescriptor, 415)
                }
            }
            if isPart1Syntax {
                if header.hasCAPMarker {
                    return DICOMManagedFailure(.invalidDescriptor, 412)
                }
                if hasPart2Markers {
                    return DICOMManagedFailure(.invalidDescriptor, 415)
                }
            }
            if isPart2Syntax && header.hasPart15CAPMarker {
                return DICOMManagedFailure(.invalidDescriptor, 412)
            }
            if uid == TransferSyntax.htj2kRPCLLossless.uid {
                let violations = J2KCodestreamInspector.htj2kRPCLViolations(
                    in: codestream,
                    rows: descriptor.rows,
                    columns: descriptor.columns
                )
                if !violations.isEmpty {
                    return DICOMManagedFailure(.invalidDescriptor, 413)
                }
            }
        } else if requiresHTJ2KCAPWhenUIDNil {
            if !header.hasPart15CAPMarker {
                return DICOMManagedFailure(.invalidDescriptor, 412)
            }
        }

        return nil
    }

    private func prepareDecode(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int
    ) throws -> PreparedDecode {
        let effectiveBackend = decodeBackend ?? options.defaultBackend
        guard Self.supportsBackend(effectiveBackend) else {
            throw DICOMError.unsupportedTransferSyntax(
                "SwiftJ2K provider cannot satisfy forced decode backend '\(effectiveBackend?.rawValue ?? "unknown")' on this runtime"
            )
        }
        if let uid = decodingTransferSyntaxUID, !Self.supportedTransferSyntaxes.contains(uid) {
            throw DICOMError.unsupportedTransferSyntax("Unsupported JPEG 2000 transfer syntax: \(uid)")
        }
        guard !frameData.isEmpty else {
            throw DICOMError.parsingFailed("Empty JPEG 2000 frame data")
        }
        guard frameData.count <= options.decodingLimits.maximumEncodedBytes,
              frameData.count <= options.resourceLimits.maximumCompressedBytes else {
            throw DICOMError.limitExceeded(
                "Compressed JPEG 2000 frame (\(frameData.count) bytes) exceeds encoded byte budget"
            )
        }
        guard frameIndex >= 0, frameIndex < max(1, descriptor.numberOfFrames) else {
            throw DICOMError.parsingFailed("Invalid frame index \(frameIndex) for \(descriptor.numberOfFrames)-frame image")
        }
        guard Self.supportsDecodeProfile(
            transferSyntaxUID: decodingTransferSyntaxUID,
            descriptor: descriptor,
            decodeBackend: decodeBackend,
            options: options
        ), let geometry = Self.validateCommonGeometry(descriptor, options: options) else {
            if descriptor.rows <= 0 || descriptor.columns <= 0
                || !(descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3)
                || !(descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16)
                || !(2...descriptor.bitsAllocated).contains(descriptor.bitsStored)
                || descriptor.highBit != descriptor.bitsStored - 1
                || !(descriptor.planarConfiguration == 0 || descriptor.planarConfiguration == 1) {
                throw DICOMError.parsingFailed("Invalid or unsupported JPEG 2000 pixel descriptor")
            }
            let (pixels, pOv) = descriptor.rows.multipliedReportingOverflow(by: descriptor.columns)
            let (samples, sOv) = pixels.multipliedReportingOverflow(by: descriptor.samplesPerPixel)
            let (bytes, bOv) = samples.multipliedReportingOverflow(by: max(1, descriptor.bitsAllocated / 8))
            if pOv || sOv || bOv
                || descriptor.rows > options.resourceLimits.maximumDimension
                || descriptor.columns > options.resourceLimits.maximumDimension
                || pixels > options.decodingLimits.maximumPixels
                || pixels > options.resourceLimits.maximumPixels
                || bytes > options.decodingLimits.maximumDecodedBytes
                || bytes > options.resourceLimits.maximumDecodedBytes {
                throw DICOMError.limitExceeded("Decoded JPEG 2000 frame geometry exceeds pixel or byte budget")
            }
            throw DICOMError.unsupportedTransferSyntax(
                "Unsupported photometric interpretation \(descriptor.photometricInterpretation.rawValue) for SwiftJ2K decode"
            )
        }

        let stripped = Self.stripTrailingEvenPadByteIfPresent(frameData)
        try Self.validateCodestreamHeader(
            stripped,
            descriptor: descriptor,
            transferSyntaxUID: decodingTransferSyntaxUID,
            requiresHTJ2KCAPWhenUIDNil: requiresHTJ2KCAPWhenUIDNil
        )
        let codestream = Self.unwrapJP2IfWidened8In16(stripped, descriptor: descriptor)

        let swiftDescriptor: ImageDescriptor
        do {
            swiftDescriptor = try Self.makeSwiftImageDescriptor(
                from: descriptor,
                limits: options.resourceLimits
            )
        } catch {
            throw SwiftJ2KSyncBridge.translateError(error)
        }

        let isLosslessOnly = decodingTransferSyntaxUID.map(Self.losslessOnlyTransferSyntaxes.contains) ?? false
        return PreparedDecode(
            codestream: codestream,
            swiftDescriptor: swiftDescriptor,
            expectedFrameBytes: geometry.frameBytes,
            transferSyntaxUID: decodingTransferSyntaxUID,
            isLosslessOnly: isLosslessOnly,
            requestedBackend: effectiveBackend
        )
    }

    private static func executeDecode(
        prepared: PreparedDecode,
        options: SwiftJ2KProviderOptions
    ) async throws -> DecodedImage {
        let destination = try ImageDestination.allocate(
            descriptor: prepared.swiftDescriptor,
            limits: options.resourceLimits
        )
        let decoder = try Decoder()
        let execution = resolveExecution(for: prepared.requestedBackend)
        let decodeOptions = DecodeOptions(
            resourceLimits: options.resourceLimits,
            executionPolicy: execution.policy,
            acceleratedEnginePreference: execution.enginePreference,
            copyPolicy: .requireSharedStorage,
            metadataPolicy: .preserve
        )
        return try await decoder.decode(prepared.codestream, into: destination, options: decodeOptions)
    }

    private func finishDecodeTelemetryAndChecks(
        _ decoded: DecodedImage,
        prepared: PreparedDecode,
        frameIndex: Int
    ) throws {
        try Self.verifyExecutedBackend(report: decoded.report, requested: prepared.requestedBackend)
        if prepared.isLosslessOnly && decoded.report.fidelity != .exactSamples {
            throw DICOMError.parsingFailed(
                "Lossless-only transfer syntax \(prepared.transferSyntaxUID ?? "") produced non-exact fidelity (\(decoded.report.fidelity))"
            )
        }
        options.telemetryHandler?(SwiftJ2KOperationRecord(
            kind: .decode,
            transferSyntaxUID: prepared.transferSyntaxUID ?? "unknown",
            targetTransferSyntaxUID: nil,
            frameIndex: frameIndex,
            report: decoded.report
        ))
    }

    private func prepareEncode(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        configuration: CompressionConfiguration
    ) throws -> PreparedEncode {
        let effectiveBackend = configuration.forcedBackend ?? options.defaultBackend
        guard Self.supportsBackend(effectiveBackend) else {
            throw DICOMError.unsupportedTransferSyntax(
                "SwiftJ2K provider cannot satisfy forced encode backend '\(effectiveBackend?.rawValue ?? "unknown")' on this runtime"
            )
        }
        let intent = J2KRoutePlanner.resolveIntent(uid: encodingTransferSyntaxUID, configuration: configuration)
        let targetUID = encodingTransferSyntaxUID ?? (
            intent.isLossless ? TransferSyntax.jpeg2000Lossless.uid : TransferSyntax.jpeg2000.uid
        )
        guard Self.supportedEncodingTransferSyntaxes.contains(targetUID) else {
            throw DICOMError.unsupportedTransferSyntax("Unsupported JPEG 2000 encoding transfer syntax: \(targetUID)")
        }

        let family = J2KRoutePlanner.compressionType(forUID: targetUID)

        guard frameIndex >= 0, frameIndex < max(1, descriptor.numberOfFrames) else {
            throw DICOMError.parsingFailed("Invalid frame index \(frameIndex) for \(descriptor.numberOfFrames)-frame image")
        }
        guard let geometry = Self.validateCommonGeometry(descriptor, options: options) else {
            let (pixels, pOv) = descriptor.rows.multipliedReportingOverflow(by: descriptor.columns)
            let (samples, sOv) = pixels.multipliedReportingOverflow(by: max(1, descriptor.samplesPerPixel))
            let (bytes, bOv) = samples.multipliedReportingOverflow(by: max(1, descriptor.bitsAllocated / 8))
            if descriptor.rows > 0, descriptor.columns > 0,
               (descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3),
               (descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16),
               (2...descriptor.bitsAllocated).contains(descriptor.bitsStored),
               descriptor.highBit == descriptor.bitsStored - 1,
               (pOv || sOv || bOv
                || descriptor.rows > options.resourceLimits.maximumDimension
                || descriptor.columns > options.resourceLimits.maximumDimension
                || pixels > options.resourceLimits.maximumPixels
                || bytes > options.resourceLimits.maximumDecodedBytes) {
                throw DICOMError.limitExceeded("Input frame geometry exceeds SwiftJ2K encode pixel or byte budget")
            }
            throw DICOMError.parsingFailed("Unsupported or invalid pixel descriptor for SwiftJ2K encoding")
        }
        guard Self.supportsEncodeProfile(
            transferSyntaxUID: targetUID,
            configuration: configuration,
            descriptor: descriptor,
            options: options
        ) else {
            throw DICOMError.unsupportedTransferSyntax(
                "Unsupported JPEG 2000 encoding profile for \(targetUID) (photometric=\(descriptor.photometricInterpretation.rawValue), bitsStored=\(descriptor.bitsStored))"
            )
        }
        guard frameData.count >= geometry.frameBytes else {
            throw DICOMError.parsingFailed(
                "Frame data too short for SwiftJ2K encoding: expected \(geometry.frameBytes) bytes, got \(frameData.count)"
            )
        }

        let swiftDescriptor: ImageDescriptor
        let image: Image
        let encoderConfiguration: EncoderConfiguration
        do {
            swiftDescriptor = try Self.makeSwiftImageDescriptor(
                from: descriptor,
                limits: options.resourceLimits
            )
            let destination = try ImageDestination.allocate(
                descriptor: swiftDescriptor,
                limits: options.resourceLimits
            )
            let bytesPerSample = descriptor.bytesPerSample
            let columns = descriptor.columns
            let planePixels = geometry.pixels
            let samplesPerPixel = descriptor.samplesPerPixel
            let planarConfiguration = descriptor.planarConfiguration

            // Normalise every DICOM Pixel Cell via `storedValue(fromCell:)` (PS3.5 §8.1.1) so both
            // sign-extended and zero-cleared unused high bits in <16-in-16 frames yield exact logical samples.
            image = try frameData.withUnsafeBytes { rawFrame in
                guard rawFrame.count >= geometry.frameBytes else {
                    throw CodecError(.invalidArgument, "Frame buffer shorter than required byte count.")
                }
                return try destination.writeSamples { component, x, y in
                    let pixelIndex = y * columns + x
                    let byteOffset: Int
                    if samplesPerPixel == 1 {
                        byteOffset = pixelIndex * bytesPerSample
                    } else if planarConfiguration == 1 {
                        byteOffset = (component * planePixels + pixelIndex) * bytesPerSample
                    } else {
                        byteOffset = (pixelIndex * 3 + component) * bytesPerSample
                    }
                    let cell = descriptor.cellValue(in: rawFrame, at: byteOffset)
                    return descriptor.storedValue(fromCell: cell)
                }
            }

            let isLossless = intent.isLossless
            let isPart2 = (family == .part2)
            let blockCoding: CodecOptions.BlockCoding = (family == .htj2k) ? .htj2k : .part1
            let wavelet: CodecOptions.WaveletTransform = isLossless ? .reversible53 : .irreversible97
            let multiComponentTransform: CodecOptions.MultiComponentTransform = isPart2 ? .part2 : .automatic
            let colourTransform: CodecOptions.ColourTransform
            if isPart2 {
                colourTransform = (descriptor.samplesPerPixel == 3) ? .automatic : .none
            } else if descriptor.samplesPerPixel == 3 {
                colourTransform = isLossless ? .rct : .ict
            } else {
                colourTransform = .none
            }
            let isRPCL = (targetUID == TransferSyntax.htj2kRPCLLossless.uid)
            let progressionOrder: CodecOptions.ProgressionOrder = isRPCL ? .rpcl : .lrcp
            let smallestDim = min(descriptor.rows, descriptor.columns)
            let deepest = Int.bitWidth - 1 - smallestDim.leadingZeroBitCount
            let decompositionLevels: Int?
            if isRPCL {
                let needed = J2KCodestreamInspector.minimumDecompositionLevelsForRPCL(
                    rows: descriptor.rows,
                    columns: descriptor.columns
                )
                decompositionLevels = min(10, min(deepest, max(5, needed)))
            } else {
                decompositionLevels = nil
            }
            let codecOptions = try CodecOptions(
                decompositionLevels: decompositionLevels,
                blockCoding: blockCoding,
                wavelet: wavelet,
                colourTransform: colourTransform,
                progressionOrder: progressionOrder,
                quality: isLossless ? nil : configuration.quality.value,
                containerFormat: .codestream,
                multiComponentTransform: multiComponentTransform
            )
            encoderConfiguration = try EncoderConfiguration(
                mode: isLossless ? .lossless : .lossy,
                codecOptions: codecOptions
            )
        } catch {
            throw SwiftJ2KSyncBridge.translateError(error)
        }

        return PreparedEncode(
            image: image,
            encoderConfiguration: encoderConfiguration,
            transferSyntaxUID: targetUID,
            isLossless: intent.isLossless,
            requestedBackend: effectiveBackend
        )
    }

    private static func executeEncode(
        prepared: PreparedEncode,
        options: SwiftJ2KProviderOptions
    ) async throws -> EncodedImage {
        let encoder = try Encoder(configuration: prepared.encoderConfiguration)
        let execution = resolveExecution(for: prepared.requestedBackend)
        let encodeOptions = EncodeOptions(
            resourceLimits: options.resourceLimits,
            executionPolicy: execution.policy,
            acceleratedEnginePreference: execution.enginePreference,
            copyPolicy: .requireSharedStorage,
            metadataPolicy: .preserve
        )
        return try await encoder.encode(prepared.image, options: encodeOptions)
    }

    private func finalizeEncodedFrame(
        _ encoded: EncodedImage,
        prepared: PreparedEncode,
        descriptor: PixelDataDescriptor,
        frameIndex: Int
    ) throws -> Data {
        try Self.verifyExecutedBackend(report: encoded.report, requested: prepared.requestedBackend)
        let expectedFidelity: Fidelity = prepared.isLossless ? .exactSamples : .lossy
        guard encoded.report.fidelity == expectedFidelity else {
            throw DICOMError.parsingFailed(
                "SwiftJ2K encoder reported fidelity \(encoded.report.fidelity), expected \(expectedFidelity)"
            )
        }
        options.telemetryHandler?(SwiftJ2KOperationRecord(
            kind: .encode,
            transferSyntaxUID: prepared.transferSyntaxUID,
            targetTransferSyntaxUID: prepared.transferSyntaxUID,
            frameIndex: frameIndex,
            report: encoded.report
        ))

        if prepared.transferSyntaxUID == TransferSyntax.htj2kRPCLLossless.uid {
            let conformed = J2KCodestreamInspector.conformingToHTJ2KRPCL(encoded.data)
            let violations = J2KCodestreamInspector.htj2kRPCLViolations(
                in: conformed,
                rows: descriptor.rows,
                columns: descriptor.columns
            )
            guard violations.isEmpty else {
                throw DICOMError.parsingFailed(
                    "Generated HTJ2K RPCL (.202) codestream failed conformance check: \(violations.joined(separator: "; "))"
                )
            }
            return conformed
        }
        return encoded.data
    }
}
