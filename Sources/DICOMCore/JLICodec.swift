import Foundation
import SwiftJLI

/// JPEG codec backed by the `SwiftJLI` pure-Swift JPEG package.
///
/// Bridges DICOM pixel data (PS3.5 §A.4.1, JPEG Image Compression) to `SwiftJLI`'s pure-Swift
/// implementation of ITU-T T.81 for all four DICOM JPEG transfer syntaxes —
/// **both lossy and lossless**:
///
///   • 1.2.840.10008.1.2.4.50  JPEG Baseline (Process 1)        — lossy DCT, 8-bit  (SOF0)
///   • 1.2.840.10008.1.2.4.51  JPEG Extended (Process 2 & 4)    — lossy DCT, ≤12-bit (SOF1)
///   • 1.2.840.10008.1.2.4.57  JPEG Lossless (Process 14)       — predictive       (SOF3)
///   • 1.2.840.10008.1.2.4.70  JPEG Lossless SV1 (Process 14,1) — predictive, P1   (SOF3)
///
/// **Decoding** validates the codestream process and descriptor before allocating samples.
/// The registry constructs a decoder per transfer syntax; direct callers may omit that restriction.
///
/// **Encoding** is mode-specific: the JPEG process is selected from
/// `encodingTransferSyntaxUID`. The registry constructs one instance per encode
/// UID (mirroring `J2KSwiftCodec`/`HTJ2KCodec`). The default initialiser targets
/// lossless SV1, so a bare `JLICodec()` round-trips bit-exactly — the contract the
/// DICOMStudio codec bench and the multi-codec adapter tests rely on.
///
/// Pixel bridging: `SwiftJLI` operates on caller-allocated `ImageDestination` storage in
/// channel-interleaved little-endian layout (`copyPolicy: .requireSharedStorage`), with
/// `Fidelity.exactSamples` verified on lossless `.57` and `.70` paths.
/// NEMA-verified: 2026a, checked 2026-10-01 — the four JPEG UIDs come from `TransferSyntax` (PS3.6 2026a Table A-1). `canEncode` admits a subset of PS3.5 2026a Tables 8.2.1-1/8.2.1-2: Baseline 8/8 (colour written YCbCr 4:2:2 = YBR_FULL_422, D190), Extended 8/8 or 16/12 monochrome only (Table 8.2.1-1 has no 3-sample .51 row), Lossless 8-or-16 allocated with 2–16 stored (the tables allow 1–16; 1 is a SwiftJLI/ITU-T T.81 SOF3 precision limit), YBR_FULL_422 only with Baseline. The "§A.4.1–A.4.3" citation was narrowed to §A.4.1 (A.4.2 is RLE, A.4.3 JPEG-LS). The codec implements ITU-T T.81, outside DICOM.
public struct JLICodec: ImageCodec, ImageEncoder, Sendable {
    /// Finite decode policy that does not construct or retain transfer-syntax Strings.
    public enum DecodingSyntax: UInt8, Sendable {
        /// Admit any JPEG process already supported by this codec.
        case any
        /// JPEG Baseline, Process 1.
        case baseline
        /// JPEG Extended, Processes 2 and 4.
        case extended
        /// JPEG Lossless, Process 14.
        case lossless
        /// JPEG Lossless, Selection Value 1.
        case losslessSV1
    }

    /// All four DICOM JPEG transfer syntaxes can be decoded.
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.jpegBaseline.uid,     // 1.2.840.10008.1.2.4.50
        TransferSyntax.jpegExtended.uid,     // 1.2.840.10008.1.2.4.51
        TransferSyntax.jpegLossless.uid,     // 1.2.840.10008.1.2.4.57
        TransferSyntax.jpegLosslessSV1.uid   // 1.2.840.10008.1.2.4.70
    ]

    /// All four DICOM JPEG transfer syntaxes can be encoded.
    public static let supportedEncodingTransferSyntaxes: [String] = supportedTransferSyntaxes

    /// The transfer syntax this instance encodes to. Selects the JPEG process:
    /// baseline/extended → lossy DCT, lossless/SV1 → SOF3 predictive. Ignored when
    /// decoding (the SOF marker drives the decoder).
    public var encodingTransferSyntaxUID: String {
        explicitEncodingTransferSyntaxUID ?? TransferSyntax.jpegLosslessSV1.uid
    }

    // Scalar decoding construction leaves this nil. Compatibility encoding materializes
    // the historical default only when the public getter or an encoding operation uses it.
    private let explicitEncodingTransferSyntaxUID: String?
    // Interpret caller-owned String configuration before any qualified operation.
    private enum SyntaxRestriction: Equatable, Sendable {
        case any, baseline, extended, lossless, losslessSV1, unsupported
    }
    private let syntaxRestriction: SyntaxRestriction
    private let decodingLimits: PixelDecodeLimits

    /// Creates a JPEG codec.
    /// - Parameters:
    ///   - encodingTransferSyntaxUID: The target syntax; defaults to JPEG Lossless SV1.
    ///   - decodingTransferSyntaxUID: Optional syntax to enforce against the encoded JPEG process.
    ///   - decodingLimits: Bounds enforced before sample decoding.
    public init(encodingTransferSyntaxUID: String = TransferSyntax.jpegLosslessSV1.uid,
                decodingTransferSyntaxUID: String? = nil, decodingLimits: PixelDecodeLimits = .default) {
        self.explicitEncodingTransferSyntaxUID = encodingTransferSyntaxUID
        switch decodingTransferSyntaxUID {
        case nil: self.syntaxRestriction = .any
        case TransferSyntax.jpegBaseline.uid: self.syntaxRestriction = .baseline
        case TransferSyntax.jpegExtended.uid: self.syntaxRestriction = .extended
        case TransferSyntax.jpegLossless.uid: self.syntaxRestriction = .lossless
        case TransferSyntax.jpegLosslessSV1.uid: self.syntaxRestriction = .losslessSV1
        default: self.syntaxRestriction = .unsupported
        }
        self.decodingLimits = decodingLimits
    }

    /// Create the same decoder from finite scalar policy without initializing UID Strings.
    /// Encoding remains available with the historical JPEG Lossless SV1 default, whose
    /// String is materialized only when encoding or reading `encodingTransferSyntaxUID`.
    /// - Parameters:
    ///   - decodingSyntax: Existing JPEG process restriction to enforce.
    ///   - decodingLimits: Bounds enforced before sample decoding.
    public init(decodingSyntax: DecodingSyntax, decodingLimits: PixelDecodeLimits = .init()) {
        explicitEncodingTransferSyntaxUID = nil
        switch decodingSyntax {
        case .any: syntaxRestriction = .any
        case .baseline: syntaxRestriction = .baseline
        case .extended: syntaxRestriction = .extended
        case .lossless: syntaxRestriction = .lossless
        case .losslessSV1: syntaxRestriction = .losslessSV1
        }
        self.decodingLimits = decodingLimits
    }

    /// Whether the target syntax is one of the two lossless (SOF3) JPEG processes.
    private var encodesLossless: Bool {
        encodingTransferSyntaxUID == TransferSyntax.jpegLossless.uid
            || encodingTransferSyntaxUID == TransferSyntax.jpegLosslessSV1.uid
    }

    /// Whether the target syntax is JPEG Baseline (Process 1) — 8-bit only.
    private var encodesBaseline: Bool {
        encodingTransferSyntaxUID == TransferSyntax.jpegBaseline.uid
    }

    // MARK: - Decoding

    private struct DecodePlan: Sendable {
        let expectedBytes: Int
        let sourceColourModel: SwiftJLI.JPEGSourceColourModel?
        let normalizeLosslessRGBIDs: Bool
    }

    /// Decodes a supported JPEG frame to DICOM pixel bytes.
    /// - Parameters:
    ///   - frameData: A single JPEG codestream.
    ///   - descriptor: Pixel data descriptor (drives the planar reshuffle).
    ///   - frameIndex: Zero-based source frame index, validated against the descriptor.
    /// - Returns: Uncompressed pixels; use `decodePixelFrame` to obtain the actual output color descriptor.
    /// - Throws: `DICOMError` if decoding fails.
    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        try decodePixelFrame(frameData, descriptor: descriptor, frameIndex: frameIndex).data
    }

    /// Returns the actual decoded color interpretation, without altering the source descriptor.
    public func decodePixelFrame(_ frameData: Data, descriptor: PixelDataDescriptor,
                                 frameIndex: Int) throws -> DecodedPixelFrame {
        _ = try decodingLimits.validate(frameData, descriptor: descriptor, frameIndex: frameIndex)
        let header = try JPEGFrameEnvelope.parse(frameData, jpegLS: false)
        let plan = try prepare(
            encodedByteCount: frameData.count,
            header: header,
            descriptor: descriptor,
            frameIndex: frameIndex
        )
        let expectedBytes = plan.expectedBytes
        let lossless = header.process == 0xC3
        let strippedData = JPEGInterchangeFormat.removingAncillaryMetadataSegments(frameData)
        let inputData = plan.normalizeLosslessRGBIDs
            ? JPEGInterchangeFormat.normalizingLosslessRGBComponentIDs(strippedData)
            : strippedData

        do {
            let jliLimits = try makeDecodeResourceLimits(encodedByteCount: inputData.count, header: header)
            let decoded = try CompressionSuiteSyncBridge.run(
                deadlineSeconds: 30.0,
                joinGraceSeconds: 1.0,
                codecName: "SwiftJLI"
            ) {
                try await Self.decodeWithSwiftJLI(
                    inputData,
                    header: header,
                    sourceColourModel: plan.sourceColourModel,
                    limits: jliLimits
                )
            }

            let rawBps = header.precision <= 8 ? 1 : 2
            let widen8To16 = header.precision <= 8 && descriptor.bitsAllocated == 16
            let expectedRawCount = widen8To16 ? (expectedBytes / 2) : expectedBytes

            let interleaved: [UInt8] = try decoded.image.storage.withUnsafeBytes { raw in
                guard raw.count >= expectedRawCount else {
                    throw DICOMError.parsingFailed("JPEG decoder returned truncated pixel storage")
                }
                if widen8To16 {
                    var widened = [UInt8](repeating: 0, count: expectedBytes)
                    for idx in 0..<expectedRawCount {
                        widened[idx * 2] = raw[idx]
                    }
                    return widened
                }
                if let base = raw.baseAddress {
                    return Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: expectedBytes))
                }
                return []
            }

            guard decoded.image.descriptor.width == descriptor.columns,
                  decoded.image.descriptor.height == descriptor.rows,
                  rawBps == (decoded.image.descriptor.storageBits / 8),
                  interleaved.count == expectedBytes else {
                throw DICOMError.parsingFailed("JPEG decoder returned a mismatched frame")
            }

            let outputPI: PhotometricInterpretation
            if lossless {
                outputPI = descriptor.photometricInterpretation
            } else {
                switch decoded.image.descriptor.colour {
                case .rgb: outputPI = .rgb
                case .greyscale: outputPI = descriptor.photometricInterpretation
                default: throw DICOMError.parsingFailed("Unexpected JPEG decoder output color model")
                }
            }
            let output = PixelDataDescriptor(
                rows: descriptor.rows,
                columns: descriptor.columns,
                numberOfFrames: descriptor.numberOfFrames,
                bitsAllocated: descriptor.bitsAllocated,
                bitsStored: descriptor.bitsStored,
                highBit: descriptor.highBit,
                isSigned: descriptor.isSigned,
                samplesPerPixel: descriptor.samplesPerPixel,
                photometricInterpretation: outputPI,
                planarConfiguration: descriptor.planarConfiguration
            )
            return DecodedPixelFrame(
                data: dicomFrameBytes(fromInterleaved: interleaved, descriptor: output),
                descriptor: output,
                sourceFrameIndex: frameIndex
            )
        } catch let error as CancellationError {
            throw error
        } catch let error as DICOMError {
            throw error
        } catch let error as SwiftJLI.CodecError {
            if error.category == .resourceLimitExceeded {
                throw DICOMError.limitExceeded("SwiftJLI decode exceeded resource limits: \(error.message)")
            }
            throw DICOMError.parsingFailed("SwiftJLI decode failed: \(error.message)")
        } catch {
            throw DICOMError.parsingFailed("SwiftJLI decode failed: \(error)")
        }
    }

    private func prepare(encodedByteCount: Int, header: JPEGFrameEnvelope, descriptor: PixelDataDescriptor,
                         frameIndex: Int) throws -> DecodePlan {
        do {
            return try prepareManaged(
                encodedByteCount: encodedByteCount,
                header: header,
                descriptor: descriptor,
                frameIndex: frameIndex
            )
        } catch {
            switch error.operand1 {
            case 200: throw DICOMError.parsingFailed("JPEG header does not match DICOM dimensions, components or precision")
            case 201: throw DICOMError.parsingFailed("Unsupported JPEG decoding transfer syntax")
            case 202: throw DICOMError.parsingFailed("JPEG process does not match transfer syntax")
            case 203: throw DICOMError.parsingFailed("Unsupported JPEG lossless sampling, predictor or point transform")
            case 204: throw DICOMError.parsingFailed("Unsupported JPEG DCT precision or scan parameters")
            case 205: throw DICOMError.parsingFailed("Unsupported Adobe JPEG color transform")
            case 0: throw DICOMError.limitExceeded("Compressed frame exceeds encoded byte budget or is empty")
            case 1: throw DICOMError.parsingFailed("Invalid compressed frame descriptor or frame index")
            default: throw DICOMError.limitExceeded("Compressed frame exceeds decoded pixel/byte budget")
            }
        }
    }

    private func prepareManaged(encodedByteCount: Int, header: JPEGFrameEnvelope, descriptor: PixelDataDescriptor,
                                frameIndex: Int) throws(DICOMManagedFailure) -> DecodePlan {
        try prepareManagedOutcome(
            encodedByteCount: encodedByteCount,
            header: header,
            descriptor: descriptor,
            frameIndex: frameIndex
        ).get()
    }

    private func prepareManagedOutcome(encodedByteCount: Int, header: JPEGFrameEnvelope,
                                       descriptor: PixelDataDescriptor,
                                       frameIndex: Int) -> DICOMManagedOutcome<DecodePlan> {
        let expectedBytes: Int
        switch decodingLimits.validateManagedOutcome(
            encodedByteCount: encodedByteCount,
            descriptor: descriptor,
            frameIndex: frameIndex
        ) {
        case .success(let value): expectedBytes = value
        case .failure(let failure): return .failure(failure)
        }
        guard header.width == descriptor.columns, header.height == descriptor.rows,
              header.precision == descriptor.bitsStored, header.components.count == descriptor.samplesPerPixel else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 200))
        }
        if syntaxRestriction != .any {
            let expected: UInt8
            switch syntaxRestriction {
            case .baseline: expected = 0xC0
            case .extended: expected = 0xC1
            case .lossless, .losslessSV1: expected = 0xC3
            case .any, .unsupported: return .failure(DICOMManagedFailure(.invalidDescriptor, 201))
            }
            guard header.process == expected else {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 202))
            }
        }
        let lossless = header.process == 0xC3
        if lossless {
            guard header.components.hasUnitSampling,
                  header.scanParameters.allSatisfy({ (1...7).contains($0.first) && $0.last == 0
                      && $0.approximation == 0
                      && (syntaxRestriction != .losslessSV1 || $0.first == 1) }) else {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 203))
            }
        } else {
            guard !descriptor.isSigned,
                  (header.process == 0xC0 ? header.precision == 8 : (header.precision == 8 || header.precision == 12)),
                  header.scanParameters.allSatisfy({ $0.first == 0 && $0.last == 63 && $0.approximation == 0 }) else {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 204))
            }
            if descriptor.samplesPerPixel == 3, let transform = header.adobeTransform,
               transform != 0 && transform != 1 {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 205))
            }
        }
        // JPEGFrameEnvelope has already recorded any JFIF (APP0) and Adobe (APP14) markers;
        // ancillary APPn/COM segments are stripped before SwiftJLI envelope validation so
        // external encoders (e.g. Apple ImageIO XMP/ICC/COM segments) never fail metadata admission.
        let sourceColourModel: SwiftJLI.JPEGSourceColourModel?
        if lossless || descriptor.samplesPerPixel == 1 {
            sourceColourModel = nil
        } else if let adobe = header.adobeTransform {
            sourceColourModel = (adobe == 0) ? .rgb : .yCbCr
        } else if header.components.hasRGBIdentifiers {
            sourceColourModel = .rgb
        } else if header.jfif || descriptor.photometricInterpretation.isYBR {
            sourceColourModel = .yCbCr
        } else {
            sourceColourModel = .rgb
        }
        let normalizeLosslessRGBIDs = lossless
            && descriptor.samplesPerPixel == 3
            && !header.components.hasRGBIdentifiers
        return .success(DecodePlan(
            expectedBytes: expectedBytes,
            sourceColourModel: sourceColourModel,
            normalizeLosslessRGBIDs: normalizeLosslessRGBIDs
        ))
    }

    private func makeDecodeResourceLimits(
        encodedByteCount: Int,
        header: JPEGFrameEnvelope
    ) throws -> SwiftJLI.ResourceLimits {
        let rawBps = header.precision <= 8 ? 1 : 2
        let (pixels, pOver) = header.width.multipliedReportingOverflow(by: header.height)
        let (samples, sOver) = pixels.multipliedReportingOverflow(by: max(1, header.components.count))
        let (rawBytes, bOver) = samples.multipliedReportingOverflow(by: rawBps)
        guard !pOver, !sOver, !bOver, pixels > 0, rawBytes > 0 else {
            throw DICOMError.parsingFailed("JPEG header dimensions overflow addressable range")
        }
        let maxCompressed = max(1, max(decodingLimits.maximumEncodedBytes, encodedByteCount))
        let maxPixels = max(1, max(decodingLimits.maximumPixels, pixels))
        let maxDecoded = max(1, max(decodingLimits.maximumDecodedBytes, rawBytes))
        let maxDim = max(65535, max(header.width, header.height))
        return try SwiftJLI.ResourceLimits(
            maximumCompressedBytes: maxCompressed,
            maximumDecodedBytes: maxDecoded,
            maximumWorkspaceBytes: Int.max / 4,
            maximumPixels: maxPixels,
            maximumDimension: maxDim,
            deadlineSeconds: 30.0,
            maximumMemoryBytes: Int.max
        )
    }

    private static func decodeWithSwiftJLI(
        _ inputData: Data,
        header: JPEGFrameEnvelope,
        sourceColourModel: SwiftJLI.JPEGSourceColourModel?,
        limits: SwiftJLI.ResourceLimits
    ) async throws -> SwiftJLI.DecodedImage {
        let width = header.width
        let height = header.height
        let nc = header.components.count
        let bps = header.precision <= 8 ? 1 : 2
        let pixelStride = nc * bps
        let rowBytes = width * pixelStride
        let byteCount = rowBytes * height
        let plane = try SwiftJLI.PlaneDescriptor(
            width: width,
            height: height,
            components: Array(0..<nc),
            offset: 0,
            sampleStride: bps,
            pixelStride: pixelStride,
            rowBytes: rowBytes,
            byteCount: byteCount
        )
        let dstDescriptor = try SwiftJLI.ImageDescriptor(
            width: width,
            height: height,
            sampleType: .unsignedInteger,
            storageBits: bps * 8,
            meaningfulBits: header.precision,
            byteOrder: .littleEndian,
            components: nc == 1 ? [.grey] : [.red, .green, .blue],
            colour: nc == 1 ? .greyscale : .rgb,
            alpha: .absent,
            planes: [plane],
            iccProfile: nil,
            limits: limits
        )
        let destination = try SwiftJLI.ImageDestination.allocate(
            descriptor: dstDescriptor,
            limits: limits
        )
        let decoderConfig = SwiftJLI.DecoderConfiguration(
            scale: 1,
            sampleFormat: .nativeInteger,
            sourceColourModel: sourceColourModel
        )
        let decoder = try SwiftJLI.Decoder(configuration: decoderConfig)
        let decodeOptions = SwiftJLI.DecodeOptions(
            resourceLimits: limits,
            copyPolicy: .requireSharedStorage,
            metadataPolicy: .discardAncillary
        )
        let decoded = try await decoder.decode(inputData, into: destination, options: decodeOptions)
        guard decoded.report.copyEvents.isEmpty else {
            throw DICOMError.parsingFailed("SwiftJLI decode violated requireSharedStorage copy policy")
        }
        if header.process == 0xC3 {
            guard decoded.report.fidelity == .exactSamples else {
                throw DICOMError.parsingFailed(
                    "SwiftJLI lossless decode reported non-exact fidelity: \(decoded.report.fidelity)"
                )
            }
        }
        return decoded
    }

    /// Managed payload decoding for validated DICOM JPEG profiles using caller-governed
    /// `DICOMAllocationBudget` admission.
    /// - Parameters:
    ///   - frameData: Immutable encoded frame allocated using `budget`.
    ///   - descriptor: Source pixel interpretation to validate against the codestream.
    ///   - frameIndex: Zero-based source frame index.
    ///   - budget: The exact ledger instance owning `frameData`.
    ///   - cancellation: Borrowed synchronous cancellation observer.
    /// - Returns: Actual decoded descriptor and managed storage, ready for one ownership transfer.
    public func decodeManagedPixelFrame(_ frameData: borrowing DICOMByteBuffer, descriptor: PixelDataDescriptor,
        frameIndex: Int, budget: borrowing DICOMAllocationBudget, cancellation: DICOMCancellation = .never)
        throws(DICOMManagedFailure) -> ManagedDecodedPixelFrame {
        try decodeManagedPixelFrameOutcome(frameData, descriptor: descriptor, frameIndex: frameIndex,
                                            budget: budget, cancellation: cancellation).get()
    }

    /// Throwing compatibility adapter; use the outcome overload inside qualified work.
    @available(*, noasync, message: "Invoke on the synchronous worker owning the execution reservation")
    public func decodeManagedPixelFrame(_ frameData: borrowing DICOMByteBuffer, descriptor: PixelDataDescriptor,
        frameIndex: Int, budget: borrowing DICOMAllocationBudget,
        execution: borrowing DICOMExecutionReservation, cancellation: DICOMCancellation = .never)
        throws(DICOMManagedFailure) -> ManagedDecodedPixelFrame {
        try decodeManagedPixelFrameOutcome(frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, execution: execution, cancellation: cancellation).get()
    }

    /// Decode admitted JPEG frames through scalar canonical outcomes.
    /// This backing-only entry requires caller-owned execution storage; the execution overload
    /// additionally validates the admitted worker.
    /// - Parameters:
    ///   - frameData: Immutable encoded backing owned by the same ledger.
    ///   - descriptor: Source interpretation to validate against the codestream.
    ///   - frameIndex: Zero-based source frame identity.
    ///   - budget: Ledger admitting encoded, workspace, decoded and control capacities.
    ///   - cancellation: Caller-owned synchronous cancellation observer.
    /// - Returns: Complete output or scalar failure after temporary ownership cleanup.
    public func decodeManagedPixelFrameOutcome(_ frameData: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor, frameIndex: Int, budget: borrowing DICOMAllocationBudget,
        cancellation: DICOMCancellation = .never) -> DICOMManagedOutcome<ManagedDecodedPixelFrame> {
        if let failure = cancellation.failure { return .failure(failure) }
        if Task.isCancelled { return .failure(DICOMManagedFailure(.cancelled)) }
        guard frameData.isOwned(by: budget) else { return .failure(DICOMManagedFailure(allocation: .budgetMismatch)) }
        switch decodingLimits.validateManagedOutcome(encodedByteCount: frameData.count,
            descriptor: descriptor, frameIndex: frameIndex) {
        case .success: break
        case .failure(let failure): return .failure(failure)
        }
        return frameData.withBorrowedBytes { encoded -> DICOMManagedOutcome<ManagedDecodedPixelFrame> in
            let header: JPEGFrameEnvelope
            switch JPEGFrameEnvelope.parseOutcome(encoded, jpegLS: false, cancellation: cancellation) {
            case .success(let value): header = value
            case .failure(let failure): return .failure(failure)
            }
            let plan: DecodePlan
            switch prepareManagedOutcome(encodedByteCount: encoded.count, header: header,
                                         descriptor: descriptor, frameIndex: frameIndex) {
            case .success(let value): plan = value
            case .failure(let failure): return .failure(failure)
            }

            let (pixels, pOver) = descriptor.rows.multipliedReportingOverflow(by: descriptor.columns)
            let (samples, sOver) = pixels.multipliedReportingOverflow(by: descriptor.samplesPerPixel)
            let (twoByteSamples, tOver) = samples.multipliedReportingOverflow(by: 2)
            guard !pOver, !sOver, !tOver else {
                return .failure(DICOMManagedFailure(.limitExceeded, 2))
            }
            let basePlaneCount = max(plan.expectedBytes, twoByteSamples)
            let (stagingCount, stOverflow) = basePlaneCount.addingReportingOverflow(encoded.count)
            guard !stOverflow, stagingCount > 0 else {
                return .failure(DICOMManagedFailure(.limitExceeded, 2))
            }

            let decoded: SwiftJLI.DecodedImage
            do {
                let staging: DICOMByteBuffer
                switch DICOMByteBuffer.admit(count: stagingCount, budget: budget, resource: .staging) {
                case .success(let value): staging = value
                case .failure(let failure): return .failure(failure)
                }
                if let failure = cancellation.failure {
                    staging.keepAlive()
                    return .failure(failure)
                }

                guard let encodedBase = encoded.baseAddress else {
                    staging.keepAlive()
                    return .failure(DICOMManagedFailure(.malformed, 10, domain: 0x0200))
                }
                let rawEncoded = Data(bytes: encodedBase, count: encoded.count)
                let strippedData = JPEGInterchangeFormat.removingAncillaryMetadataSegments(rawEncoded)
                let inputData = plan.normalizeLosslessRGBIDs
                    ? JPEGInterchangeFormat.normalizingLosslessRGBComponentIDs(strippedData)
                    : strippedData

                let jliLimits: SwiftJLI.ResourceLimits
                do {
                    jliLimits = try makeDecodeResourceLimits(encodedByteCount: inputData.count, header: header)
                } catch {
                    staging.keepAlive()
                    return .failure(DICOMManagedFailure(.limitExceeded, 8, domain: 0x0200))
                }

                let bridgeOutcome = CompressionSuiteSyncBridge.runManaged(
                    deadlineSeconds: 30.0,
                    joinGraceSeconds: 1.0,
                    domain: 0x0200,
                    cancellation: cancellation
                ) {
                    try await Self.decodeWithSwiftJLI(
                        inputData,
                        header: header,
                        sourceColourModel: plan.sourceColourModel,
                        limits: jliLimits
                    )
                }
                staging.keepAlive()
                switch bridgeOutcome {
                case .success(let value): decoded = value
                case .failure(let failure): return .failure(failure)
                }
            }

            guard decoded.image.descriptor.width == descriptor.columns,
                  decoded.image.descriptor.height == descriptor.rows else {
                return .failure(DICOMManagedFailure(.codecResultMismatch))
            }

            let lossless = header.process == 0xC3
            let outputPI: PhotometricInterpretation
            if lossless {
                outputPI = descriptor.photometricInterpretation
            } else {
                switch decoded.image.descriptor.colour {
                case .rgb: outputPI = .rgb
                case .greyscale: outputPI = descriptor.photometricInterpretation
                default: return .failure(DICOMManagedFailure(.codecResultMismatch))
                }
            }

            let widen8To16 = header.precision <= 8 && descriptor.bitsAllocated == 16
            let expectedRawCount = widen8To16 ? (plan.expectedBytes / 2) : plan.expectedBytes
            guard decoded.image.storage.byteCount == expectedRawCount else {
                return .failure(DICOMManagedFailure(.codecResultMismatch))
            }

            let bytes: DICOMByteBuffer
            switch DICOMByteBuffer.admit(count: plan.expectedBytes, budget: budget, resource: .decoded) {
            case .success(let value): bytes = value
            case .failure(let failure): return .failure(failure)
            }
            if let failure = cancellation.failure {
                bytes.keepAlive()
                return .failure(failure)
            }

            guard let dst = bytes.unsafeMutableBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                bytes.keepAlive()
                return .failure(DICOMManagedFailure(.codecResultMismatch))
            }

            let spp = descriptor.samplesPerPixel
            let bps = descriptor.bitsAllocated <= 8 ? 1 : 2
            let maxSample = UInt16((1 << min(16, max(1, descriptor.bitsStored))) - 1)
            let checkSubwordBounds = lossless && descriptor.bitsStored < descriptor.bitsAllocated

            let copyFailure: DICOMManagedFailure?
            do {
                copyFailure = try decoded.image.storage.withUnsafeBytes { raw -> DICOMManagedFailure? in
                    guard raw.count >= expectedRawCount,
                          let src = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return DICOMManagedFailure(.codecResultMismatch)
                    }
                    if checkSubwordBounds {
                        if header.precision <= 8 {
                            let max8 = UInt8(truncatingIfNeeded: maxSample)
                            for idx in 0..<expectedRawCount {
                                if (idx & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                                if src[idx] > max8 { return DICOMManagedFailure(.codecResultMismatch) }
                            }
                        } else {
                            let sampleCount = expectedRawCount / 2
                            for idx in 0..<sampleCount {
                                if (idx & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                                let val = UInt16(src[idx * 2]) | (UInt16(src[idx * 2 + 1]) << 8)
                                if val > maxSample { return DICOMManagedFailure(.codecResultMismatch) }
                            }
                        }
                    }

                    if spp == 1 || descriptor.planarConfiguration == 0 {
                        if widen8To16 {
                            for idx in 0..<expectedRawCount {
                                if (idx & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                                dst[idx * 2] = src[idx]
                                dst[idx * 2 + 1] = 0
                            }
                        } else {
                            let chunk = 65_536
                            var offset = 0
                            while offset < plan.expectedBytes {
                                if let failure = cancellation.failure { return failure }
                                let step = min(chunk, plan.expectedBytes - offset)
                                (dst + offset).update(from: src + offset, count: step)
                                offset += step
                            }
                        }
                    } else {
                        for p in 0..<pixels {
                            if (p & 0xFFFF) == 0, let failure = cancellation.failure { return failure }
                            for c in 0..<spp {
                                let dstByte = (c * pixels + p) * bps
                                if widen8To16 {
                                    let srcIdx = p * spp + c
                                    dst[dstByte] = src[srcIdx]
                                    dst[dstByte + 1] = 0
                                } else {
                                    let srcByte = (p * spp + c) * bps
                                    for b in 0..<bps {
                                        dst[dstByte + b] = src[srcByte + b]
                                    }
                                }
                            }
                        }
                    }
                    return nil
                }
            } catch {
                bytes.keepAlive()
                return .failure(DICOMManagedFailure(.codecResultMismatch))
            }
            bytes.keepAlive()
            if let copyFailure { return .failure(copyFailure) }
            if let failure = cancellation.failure {
                bytes.keepAlive()
                return .failure(failure)
            }
            let output = PixelDataDescriptor(
                rows: descriptor.rows,
                columns: descriptor.columns,
                numberOfFrames: descriptor.numberOfFrames,
                bitsAllocated: descriptor.bitsAllocated,
                bitsStored: descriptor.bitsStored,
                highBit: descriptor.highBit,
                isSigned: descriptor.isSigned,
                samplesPerPixel: spp,
                photometricInterpretation: outputPI,
                planarConfiguration: descriptor.planarConfiguration
            )
            return .success(ManagedDecodedPixelFrame(data: bytes, descriptor: output, sourceFrameIndex: frameIndex))
        }
    }

    /// Decode on the original admitted worker with scalar identity/refusal status.
    /// - Parameters:
    ///   - frameData: Encoded backing owned by the shared ledger.
    ///   - descriptor: Source interpretation to validate.
    ///   - frameIndex: Source frame identity.
    ///   - budget: Shared admission ledger.
    ///   - execution: Whole-stack reservation retained through actual synchronous return.
    ///   - cancellation: Borrowed synchronous cancellation observer.
    /// - Returns: Output or fixed failure, without a throwing-runtime call.
    @available(*, noasync, message: "Qualified decoding must remain on its admitted synchronous worker")
    public func decodeManagedPixelFrameOutcome(_ frameData: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor, frameIndex: Int, budget: borrowing DICOMAllocationBudget,
        execution: borrowing DICOMExecutionReservation, cancellation: DICOMCancellation = .never)
        -> DICOMManagedOutcome<ManagedDecodedPixelFrame> {
        switch execution.validateOutcome(budget: budget) {
        case .success: break
        case .failure(let failure): return .failure(DICOMManagedFailure(allocation: failure))
        }
        return decodeManagedPixelFrameOutcome(frameData, descriptor: descriptor, frameIndex: frameIndex,
                                               budget: budget, cancellation: cancellation)
    }

    // MARK: - Encoding

    /// Whether this codec can encode the given configuration for its target syntax.
    ///
    /// Constraints follow each JPEG process plus `SwiftJLI`'s input rules:
    ///   • samples per pixel must be 1 (grayscale) or 3 (RGB);
    ///   • Baseline (.50): 8-bit unsigned only;
    ///   • Extended (.51): ≤12-bit unsigned (the SOF1 precision ceiling), monochrome only;
    ///   • Lossless (.57/.70): 2–16 bit, signed or unsigned (bytes preserved exactly);
    ///   • the lossy DCT path rejects signed samples (undefined level shift).
    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        guard descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3 else {
            return false
        }

        if encodesLossless {
            // SOF3 predictive: 2–16 bit precision, sign-agnostic.
            guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
                return false
            }
            return descriptor.bitsStored >= 2 && descriptor.bitsStored <= 16
        }

        // Lossy DCT: ITU-T T.81 level shift is defined only for unsigned samples.
        if descriptor.isSigned {
            return false
        }
        // Pre-converted YCbCr (YBR_FULL_422/YBR_FULL) input only has an 8-bit path
        // through SwiftJLI — see the `.yCbCr` sourceColourSpace branch in `encodeFrame`.
        if descriptor.samplesPerPixel == 3 && descriptor.photometricInterpretation.isYBR
            && descriptor.bitsAllocated > 8 {
            return false
        }
        if encodesBaseline {
            // Process 1 — 8-bit baseline sequential.
            return descriptor.bitsAllocated == 8 && descriptor.bitsStored <= 8
        }
        // Extended (Process 2 & 4) — up to 12-bit, monochrome only: PS3.5 2026a Table 8.2.1-1 has
        // no 3-sample row for 1.2.840.10008.1.2.4.51 ("No other Standard Photometric
        // Interpretation Values shall be used", 8.2.1).
        guard descriptor.samplesPerPixel == 1 else { return false }
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
            return false
        }
        return descriptor.bitsStored <= 12
    }

    /// Encodes a single frame to the JPEG process selected by `encodingTransferSyntaxUID`.
    /// - Parameters:
    ///   - frameData: Uncompressed frame bytes laid out per `descriptor`.
    ///   - descriptor: Pixel data descriptor.
    ///   - frameIndex: Zero-based frame index (unused — one codestream per frame).
    ///   - configuration: Compression configuration; for the lossy processes its
    ///     `quality` maps to the JPEG quality factor. Ignored for lossless.
    /// - Returns: The JPEG codestream for this frame.
    /// - Throws: `DICOMError` if encoding fails.
    public func encodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor,
                            frameIndex: Int, configuration: CompressionConfiguration) throws -> Data {
        let spp = descriptor.samplesPerPixel
        guard spp == 1 || spp == 3 else {
            throw DICOMError.parsingFailed("SwiftJLI: unsupported samplesPerPixel \(spp)")
        }
        let width = descriptor.columns
        let height = descriptor.rows
        guard (1...65535).contains(width), (1...65535).contains(height) else {
            throw DICOMError.parsingFailed("SwiftJLI: invalid frame dimensions \(width)x\(height)")
        }

        let storageBits = descriptor.bitsAllocated <= 8 ? 8 : 16
        let bps = storageBits / 8
        let lossless = encodesLossless
        if !lossless && descriptor.isSigned {
            throw DICOMError.parsingFailed("SwiftJLI: lossy DCT encoding rejects signed pixel data")
        }

        let isPreconvertedYBR = !lossless && spp == 3 && descriptor.photometricInterpretation.isYBR
        if isPreconvertedYBR && storageBits != 8 {
            throw DICOMError.parsingFailed(
                "SwiftJLI: \(descriptor.photometricInterpretation.rawValue) input requires "
                + "8-bit samples (bitsAllocated=\(descriptor.bitsAllocated))"
            )
        }

        let meaningfulBits: Int
        if lossless {
            guard descriptor.bitsStored >= 2 && descriptor.bitsStored <= 16 else {
                throw DICOMError.parsingFailed("SwiftJLI: lossless precision \(descriptor.bitsStored) outside 2...16")
            }
            meaningfulBits = min(storageBits, max(2, descriptor.bitsStored))
        } else {
            if storageBits == 8 {
                guard descriptor.bitsStored <= 8 else {
                    throw DICOMError.parsingFailed("SwiftJLI: 8-bit DCT requires bitsStored <= 8")
                }
                meaningfulBits = 8
            } else {
                guard descriptor.bitsStored <= 12 else {
                    throw DICOMError.parsingFailed("SwiftJLI: Extended DCT requires bitsStored <= 12")
                }
                meaningfulBits = 12
            }
        }

        let interleaved = interleavedFrameBytes(from: frameData, descriptor: descriptor)

        do {
            let limits = try makeEncodeResourceLimits(
                width: width,
                height: height,
                spp: spp,
                bps: bps
            )
            let image = try Self.buildEncodeImage(
                interleaved: interleaved,
                width: width,
                height: height,
                spp: spp,
                storageBits: storageBits,
                meaningfulBits: meaningfulBits,
                isSigned: descriptor.isSigned,
                lossless: lossless,
                isPreconvertedYBR: isPreconvertedYBR,
                limits: limits
            )
            let encoderConfig = try encoderConfiguration(
                descriptor: descriptor,
                configuration: configuration,
                isPreconvertedYBR: isPreconvertedYBR
            )
            let encoder = try SwiftJLI.Encoder(configuration: encoderConfig)
            let encodeOptions = SwiftJLI.EncodeOptions(
                resourceLimits: limits,
                copyPolicy: .requireSharedStorage,
                metadataPolicy: .discardAncillary
            )
            let encoded = try CompressionSuiteSyncBridge.run(
                deadlineSeconds: 30.0,
                joinGraceSeconds: 1.0,
                codecName: "SwiftJLI"
            ) {
                try await encoder.encode(image, options: encodeOptions)
            }
            guard encoded.report.copyEvents.isEmpty else {
                throw DICOMError.parsingFailed("SwiftJLI encode violated requireSharedStorage copy policy")
            }
            if lossless {
                guard encoded.report.fidelity == .exactSamples else {
                    throw DICOMError.parsingFailed(
                        "SwiftJLI lossless encode reported non-exact fidelity: \(encoded.report.fidelity)"
                    )
                }
            }

            // SwiftJLI writes a JFIF APP0 segment; PS3.5 2026a 8.2.1 recommends it be absent (D190).
            var stream = JPEGInterchangeFormat.removingJFIFSegments(encoded.data)
            if encodingTransferSyntaxUID == TransferSyntax.jpegExtended.uid, storageBits == 8 {
                // SwiftJLI selects SOF0 for 8-bit DCT input. Its baseline sequential
                // coding is also a valid subset of extended sequential coding, but
                // PS3.5 A.4.1 requires SOF1 when the negotiated syntax is .51.
                stream = try JPEGInterchangeFormat.promotingEightBitBaselineToExtended(stream)
            }
            return stream
        } catch let error as CancellationError {
            throw error
        } catch let error as DICOMError {
            throw error
        } catch let error as SwiftJLI.CodecError {
            if error.category == .resourceLimitExceeded {
                throw DICOMError.limitExceeded("SwiftJLI encode exceeded resource limits: \(error.message)")
            }
            throw DICOMError.parsingFailed("SwiftJLI encode failed: \(error.message)")
        } catch {
            throw DICOMError.parsingFailed("SwiftJLI encode failed: \(error)")
        }
    }

    // MARK: - Configuration & Storage Mapping

    private func makeEncodeResourceLimits(
        width: Int,
        height: Int,
        spp: Int,
        bps: Int
    ) throws -> SwiftJLI.ResourceLimits {
        let (pixels, pOver) = width.multipliedReportingOverflow(by: height)
        let (samples, sOver) = pixels.multipliedReportingOverflow(by: spp)
        let (decodedBytes, bOver) = samples.multipliedReportingOverflow(by: bps)
        guard !pOver, !sOver, !bOver, pixels > 0, decodedBytes > 0 else {
            throw DICOMError.parsingFailed("SwiftJLI encode: invalid frame dimensions")
        }
        let maxPixels = max(64_000_000, pixels)
        let maxDecoded = max(512 * 1024 * 1024, decodedBytes)
        let (worstCompressed, cOver) = samples.multipliedReportingOverflow(by: 12)
        let maxCompressed = cOver ? Int.max : max(256 * 1024 * 1024, worstCompressed + 8192)
        return try SwiftJLI.ResourceLimits(
            maximumCompressedBytes: maxCompressed,
            maximumDecodedBytes: maxDecoded,
            maximumWorkspaceBytes: Int.max / 4,
            maximumPixels: maxPixels,
            deadlineSeconds: 30.0,
            maximumMemoryBytes: Int.max
        )
    }

    private static func buildEncodeImage(
        interleaved: [UInt8],
        width: Int,
        height: Int,
        spp: Int,
        storageBits: Int,
        meaningfulBits: Int,
        isSigned: Bool,
        lossless: Bool,
        isPreconvertedYBR: Bool,
        limits: SwiftJLI.ResourceLimits
    ) throws -> SwiftJLI.Image {
        let bps = storageBits / 8
        let pixelStride = spp * bps
        let rowBytes = width * pixelStride
        let requiredBytes = rowBytes * height
        guard interleaved.count >= requiredBytes else {
            throw DICOMError.parsingFailed(
                "SwiftJLI encode: pixel buffer length \(interleaved.count) shorter than required \(requiredBytes)"
            )
        }

        let components: [SwiftJLI.ComponentRole]
        let colour: SwiftJLI.ColourInterpretation
        if spp == 1 {
            components = [.grey]
            colour = .greyscale
        } else if isPreconvertedYBR {
            // Samples are already YCbCr (e.g. YBR_FULL_422) — declare uninterpreted Y/Cb/Cr
            // components with `.unknown` colour so SwiftJLI skips RGB -> YCbCr conversion.
            components = [.uninterpreted("Y"), .uninterpreted("Cb"), .uninterpreted("Cr")]
            colour = .unknown
        } else {
            // Lossless SOF3 never applies a colour transform; SwiftJLI requires explicit RGB
            // component roles (`'R','G','B'` component IDs) for 3-sample lossless streams.
            components = [.red, .green, .blue]
            colour = .rgb
        }

        let plane = try SwiftJLI.PlaneDescriptor(
            width: width,
            height: height,
            components: Array(0..<spp),
            offset: 0,
            sampleStride: bps,
            pixelStride: pixelStride,
            rowBytes: rowBytes,
            byteCount: requiredBytes
        )
        let imageDescriptor = try SwiftJLI.ImageDescriptor(
            width: width,
            height: height,
            sampleType: .unsignedInteger,
            storageBits: storageBits,
            meaningfulBits: meaningfulBits,
            byteOrder: .littleEndian,
            components: components,
            colour: colour,
            alpha: .absent,
            planes: [plane],
            iccProfile: nil,
            limits: limits
        )
        let destination = try SwiftJLI.ImageDestination.allocate(
            descriptor: imageDescriptor,
            limits: limits
        )
        let needsSignedSubwordMask = lossless && isSigned && meaningfulBits < storageBits

        return try destination.write { dstRaw in
            guard let dst = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            interleaved.withUnsafeBufferPointer { src in
                if let base = src.baseAddress, requiredBytes > 0 {
                    dst.update(from: base, count: requiredBytes)
                }
            }
            if needsSignedSubwordMask {
                let totalCells = requiredBytes / bps
                let storedMask = UInt16((1 << meaningfulBits) - 1)
                let signBit = UInt16(1 << (meaningfulBits - 1))
                let containerMask: UInt16 = storageBits == 8 ? 0x00FF : 0xFFFF
                let upperMask = containerMask ^ storedMask
                for i in 0..<totalCells {
                    if bps == 1 {
                        let word = UInt16(dst[i])
                        let upper = word & upperMask
                        guard upper == 0 || (upper == upperMask && (word & signBit) != 0) else {
                            throw DICOMError.parsingFailed("Signed 8-bit sample exceeds \(meaningfulBits)-bit precision")
                        }
                        dst[i] = UInt8(truncatingIfNeeded: word & storedMask)
                    } else {
                        let word = UInt16(dst[i * 2]) | (UInt16(dst[i * 2 + 1]) << 8)
                        let upper = word & upperMask
                        guard upper == 0 || (upper == upperMask && (word & signBit) != 0) else {
                            throw DICOMError.parsingFailed("Signed 16-bit sample exceeds \(meaningfulBits)-bit precision")
                        }
                        let masked = word & storedMask
                        dst[i * 2] = UInt8(masked & 0xFF)
                        dst[i * 2 + 1] = UInt8((masked >> 8) & 0xFF)
                    }
                }
            }
        }
    }

    /// Builds the `SwiftJLI` encoder configuration for the target JPEG process.
    private func encoderConfiguration(
        descriptor: PixelDataDescriptor,
        configuration: CompressionConfiguration,
        isPreconvertedYBR: Bool
    ) throws -> SwiftJLI.EncoderConfiguration {
        if encodesLossless {
            // SOF3 predictor 1, point-transform 0 — bit-exact. Both .57 (Process 14)
            // and .70 (SV1) are valid with the left predictor; .70 *requires* it.
            return try SwiftJLI.EncoderConfiguration(
                mode: .lossless,
                codecOptions: SwiftJLI.CodecOptions(predictor: 1, restartInterval: 0)
            )
        }

        // Lossy DCT — force the properties the DICOM JPEG processes mandate:
        //   • sequential, never progressive (Baseline/Extended are non-progressive);
        //   • colour as YCbCr 4:2:2 — PS3.5 2026a Table 8.2.1-1 allows a 3-sample JPEG Baseline
        //     stream only as YBR_FULL_422 or RGB (components stored as RGB). SwiftJLI's lossy
        //     path writes 4:2:2 YCbCr, labelled YBR_FULL_422 by the transcoders (D190 / D-CORE-2).
        let dctOptions = SwiftJLI.DCTOptions(
            quality: Self.jpegQuality(from: configuration.quality),
            distance: nil,
            chromaSubsampling: descriptor.samplesPerPixel == 3 ? .yuv422 : .yuv444,
            progressiveMode: .sequential,
            colourSpace: .yCbCr,
            sourceColourSpace: isPreconvertedYBR ? .yCbCr : .fromDescriptor
        )
        return try SwiftJLI.EncoderConfiguration(
            mode: .lossy,
            codecOptions: SwiftJLI.CodecOptions(predictor: 1, restartInterval: 0, dct: dctOptions)
        )
    }

    /// Maps a DICOM `CompressionQuality` (0.0–1.0) to a JPEG quality factor (1–100).
    static func jpegQuality(from quality: CompressionQuality) -> Double {
        max(1.0, min(100.0, quality.value * 100.0))
    }
}
