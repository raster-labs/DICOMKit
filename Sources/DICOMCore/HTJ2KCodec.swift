import Foundation

/// Dedicated HTJ2K (ISO/IEC 15444-15) codec adapter for DICOMKit.
///
/// Wraps `J2KSwiftCodec` (backed by `SwiftJ2K`) with HTJ2K-specific configuration, including
/// RPCL progression ordering for `.htj2kRPCLLossless` (1.2.840.10008.1.2.4.202).
///
/// Reference: DICOM PS3.5 Section A.4.4 — JPEG 2000 Image Compression (the HTJ2K syntaxes .201/.202/.203 are defined there)
///
/// NEMA-verified: 2026a, checked 2026-09-25 — the three HTJ2K UIDs come from `TransferSyntax` (PS3.6 2026a Table A-1) and the RPCL requirement for .202 is in PS3.5 2026a A.4.4. The citation said A.4.6, which is MPEG-4 AVC/H.264; corrected.
public struct HTJ2KCodec: ImageCodec, ImageEncoder, DecodeBackendConfigurableCodec, ProgressiveResolutionDecodableCodec, Sendable {
    /// Finite decode policy that does not construct or retain transfer-syntax Strings.
    public enum DecodingSyntax: UInt8, Sendable {
        /// Admit any HTJ2K codestream.
        case any
        /// High-Throughput JPEG 2000 Image Compression (Lossless Only) — `1.2.840.10008.1.2.4.201`.
        case lossless
        /// High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only) — `1.2.840.10008.1.2.4.202`.
        case rpclLossless
        /// High-Throughput JPEG 2000 Image Compression — `1.2.840.10008.1.2.4.203`.
        case lossy
    }

    /// The three DICOM HTJ2K transfer syntax UIDs.
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.htj2kLossless.uid,
        TransferSyntax.htj2kRPCLLossless.uid,
        TransferSyntax.htj2kLossy.uid
    ]

    /// Encoding is supported for all three HTJ2K syntaxes.
    public static let supportedEncodingTransferSyntaxes: [String] = supportedTransferSyntaxes

    /// The specific transfer syntax this codec instance targets for encoding.
    private let targetTransferSyntaxUID: String?

    /// The underlying J2KSwiftCodec that performs the actual work.
    private let backing: J2KSwiftCodec

    /// Creates an HTJ2K codec, optionally pinned to a specific transfer syntax for encoding.
    ///
    /// - Parameters:
    ///   - targetTransferSyntaxUID: The HTJ2K transfer syntax UID to target during encoding.
    ///     When `nil`, defaults to HTJ2K Lossless.
    ///   - decodingLimits: Bounds enforced before sample decoding.
    public init(targetTransferSyntaxUID: String? = nil, decodingLimits: PixelDecodeLimits = .default) {
        self.targetTransferSyntaxUID = targetTransferSyntaxUID
        if let targetTransferSyntaxUID {
            self.backing = J2KSwiftCodec(
                encodingTransferSyntaxUID: targetTransferSyntaxUID,
                decodingTransferSyntaxUID: targetTransferSyntaxUID,
                decodingLimits: decodingLimits
            )
        } else {
            self.backing = J2KSwiftCodec(
                encodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid,
                decodingSyntax: .htj2kAny,
                decodingLimits: decodingLimits
            )
        }
    }

    /// Create an HTJ2K decoder from finite scalar policy without initializing UID Strings.
    public init(decodingSyntax: DecodingSyntax, decodingLimits: PixelDecodeLimits = .init()) {
        self.targetTransferSyntaxUID = nil
        let j2kSyntax: J2KSwiftCodec.DecodingSyntax
        switch decodingSyntax {
        case .any: j2kSyntax = .htj2kAny
        case .lossless: j2kSyntax = .htj2kLossless
        case .rpclLossless: j2kSyntax = .htj2kRPCLLossless
        case .lossy: j2kSyntax = .htj2kLossy
        }
        self.backing = J2KSwiftCodec(decodingSyntax: j2kSyntax, decodingLimits: decodingLimits)
    }

    private init(targetTransferSyntaxUID: String?, backing: J2KSwiftCodec) {
        self.targetTransferSyntaxUID = targetTransferSyntaxUID
        self.backing = backing
    }

    public func withDecodeBackend(_ decodeBackend: CodecBackend?) -> any ImageCodec {
        guard let reconfigured = backing.withDecodeBackend(decodeBackend) as? J2KSwiftCodec else {
            return self
        }
        return HTJ2KCodec(targetTransferSyntaxUID: targetTransferSyntaxUID, backing: reconfigured)
    }

    // The DICOMKit progressive stream uses this same syntax-restricted decoder
    // for its reduced-resolution previews and its final frame.
    package var progressiveDecoder: J2KSwiftCodec { backing }

    // MARK: - ImageCodec

    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        try backing.decodeFrame(frameData, descriptor: descriptor, frameIndex: frameIndex)
    }

    public func decodePixelFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> DecodedPixelFrame {
        try backing.decodePixelFrame(frameData, descriptor: descriptor, frameIndex: frameIndex)
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
        try backing.decodeManagedPixelFrame(
            frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, cancellation: cancellation
        )
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
        try backing.decodeManagedPixelFrame(
            frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, execution: execution, cancellation: cancellation
        )
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
        backing.decodeManagedPixelFrameOutcome(
            frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, execution: execution, cancellation: cancellation
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
        backing.decodeManagedPixelFrameOutcome(
            frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, cancellation: cancellation
        )
    }

    // MARK: - ImageEncoder

    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        backing.canEncode(with: configuration, descriptor: descriptor)
    }

    public func encodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        configuration: CompressionConfiguration
    ) throws -> Data {
        try backing.encodeFrame(frameData, descriptor: descriptor, frameIndex: frameIndex, configuration: configuration)
    }

    // MARK: - Progressive Resolution Preview

    public func decodeFrameAtResolution(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        level: Int
    ) async throws -> (data: Data, rows: Int, columns: Int) {
        try await backing.decodeFrameAtResolution(frameData, descriptor: descriptor, level: level)
    }

    // MARK: - Fast-Path Transcoding

    /// Unscoped raw-codestream transcoding without DICOM descriptor and budget admission is disabled.
    /// Use `TransferSyntaxConverter` or `CodecRegistry.shared.resolveJ2KTranscoder` for
    /// descriptor-validated, budget-accounted compressed-domain lossless `J2K <-> HTJ2K` transcoding.
    public static func transcodeToHTJ2K(_ codestreamData: Data) throws -> Data {
        throw DICOMError.unsupportedTransferSyntax(
            "Use TransferSyntaxConverter or CodecRegistry.shared.resolveJ2KTranscoder for descriptor-validated J2K <-> HTJ2K transcoding"
        )
    }

    /// See `transcodeToHTJ2K(_:)` for the qualified alternative.
    public static func transcodeFromHTJ2K(_ codestreamData: Data) throws -> Data {
        throw DICOMError.unsupportedTransferSyntax(
            "Use TransferSyntaxConverter or CodecRegistry.shared.resolveJ2KTranscoder for descriptor-validated J2K <-> HTJ2K transcoding"
        )
    }

    /// Detects whether a codestream uses HTJ2K encoding (`CAP` `Pcap^15` marker).
    ///
    /// - Parameter codestreamData: A JPEG 2000 codestream.
    /// - Returns: `true` when the codestream carries ISO/IEC 15444-15 capability signalling.
    public static func isHTJ2K(_ codestreamData: Data) -> Bool {
        J2KCodestreamInspector.imageHeader(in: codestreamData)?.hasPart15CAPMarker ?? false
    }
}
