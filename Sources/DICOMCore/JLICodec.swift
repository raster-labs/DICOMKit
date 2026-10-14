import Foundation
import JLISwift

/// JPEG codec backed by the JLISwift native-Swift JPEG package.
///
/// Bridges DICOM pixel data (PS3.5 §A.4.1, JPEG Image Compression) to JLISwift's pure-Swift
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
/// Pixel bridging: `JLIImage.data` is channel-interleaved `[UInt8]`, row-major,
/// 16-bit samples little-endian — matching DICOM little-endian storage, so only
/// planar→interleaved reshuffling (handled by `interleavedFrameBytes`) is needed.
/// NEMA-verified: 2026a, checked 2026-10-01 — the four JPEG UIDs come from `TransferSyntax` (PS3.6 2026a Table A-1). `canEncode` admits a subset of PS3.5 2026a Tables 8.2.1-1/8.2.1-2: Baseline 8/8 (colour written YCbCr 4:2:2 = YBR_FULL_422, D190), Extended 8/8 or 16/12 monochrome only (Table 8.2.1-1 has no 3-sample .51 row), Lossless 8-or-16 allocated with 2–16 stored (the tables allow 1–16; 1 is a JLISwift limit), YBR_FULL_422 only with Baseline. The "§A.4.1–A.4.3" citation was narrowed to §A.4.1 (A.4.2 is RLE, A.4.3 JPEG-LS). The codec implements ITU-T T.81, outside DICOM.
public struct JLICodec: ImageCodec, ImageEncoder, Sendable {
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
    public let encodingTransferSyntaxUID: String

    private let decodingTransferSyntaxUID: String?
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
        self.encodingTransferSyntaxUID = encodingTransferSyntaxUID
        self.decodingTransferSyntaxUID = decodingTransferSyntaxUID
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
        let plan = try prepare(encodedByteCount: frameData.count, header: header, descriptor: descriptor, frameIndex: frameIndex)
        let expectedBytes = plan.expectedBytes
        let configuration = plan.configuration
        let lossless = header.process == 0xc3
        do {
            let image = try JLIDecoder().decode(from: [UInt8](frameData), configuration: configuration)
            // JLISwift chooses its container from encoded precision, whereas DICOM may allocate 16 bits for 8 stored.
            var bytes = image.data
            if header.precision <= 8 && descriptor.bitsAllocated == 16 {
                bytes = bytes.flatMap { [$0, 0] }
            }
            guard image.width == descriptor.columns, image.height == descriptor.rows, bytes.count == expectedBytes else {
                throw DICOMError.parsingFailed("JPEG decoder returned a mismatched frame")
            }
            let outputPI: PhotometricInterpretation
            if lossless { outputPI = descriptor.photometricInterpretation }
            else {
                switch image.colorModel {
                case .rgb: outputPI = .rgb
                case .grayscale: outputPI = descriptor.photometricInterpretation
                default: throw DICOMError.parsingFailed("Unexpected JPEG decoder output color model")
                }
            }
            let output = PixelDataDescriptor(rows: descriptor.rows, columns: descriptor.columns,
                numberOfFrames: descriptor.numberOfFrames, bitsAllocated: descriptor.bitsAllocated,
                bitsStored: descriptor.bitsStored, highBit: descriptor.highBit, isSigned: descriptor.isSigned,
                samplesPerPixel: descriptor.samplesPerPixel, photometricInterpretation: outputPI,
                planarConfiguration: descriptor.planarConfiguration)
            return DecodedPixelFrame(data: dicomFrameBytes(fromInterleaved: bytes, descriptor: output),
                                     descriptor: output, sourceFrameIndex: frameIndex)
        } catch {
            throw DICOMError.parsingFailed("JLISwift decode failed: \(error)")
        }
    }

    private func prepare(encodedByteCount: Int, header: JPEGFrameEnvelope, descriptor: PixelDataDescriptor,
        frameIndex: Int) throws -> (expectedBytes: Int, configuration: JLIDecoderConfiguration) {
        do { return try prepareManaged(encodedByteCount: encodedByteCount, header: header,
                                        descriptor: descriptor, frameIndex: frameIndex) }
        catch {
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
        frameIndex: Int) throws(DICOMManagedFailure) -> (expectedBytes: Int, configuration: JLIDecoderConfiguration) {
        try prepareManagedOutcome(encodedByteCount: encodedByteCount, header: header,
                                  descriptor: descriptor, frameIndex: frameIndex).get()
    }

    private func prepareManagedOutcome(encodedByteCount: Int, header: JPEGFrameEnvelope,
        descriptor: PixelDataDescriptor, frameIndex: Int) -> DICOMManagedOutcome<(expectedBytes: Int, configuration: JLIDecoderConfiguration)> {
        let expectedBytes: Int
        switch decodingLimits.validateManagedOutcome(encodedByteCount: encodedByteCount,
            descriptor: descriptor, frameIndex: frameIndex) {
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
            case .baseline: expected = 0xc0
            case .extended: expected = 0xc1
            case .lossless, .losslessSV1: expected = 0xc3
            case .any, .unsupported: return .failure(DICOMManagedFailure(.invalidDescriptor, 201))
            }
            guard header.process == expected else {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 202))
            }
        }
        let lossless = header.process == 0xc3
        if lossless {
            guard header.components.hasUnitSampling,
                  header.scanParameters.allSatisfy({ (1...7).contains($0.first) && $0.last == 0
                      && $0.approximation == 0
                      && (syntaxRestriction != .losslessSV1 || $0.first == 1) }) else {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 203))
            }
        } else {
            guard !descriptor.isSigned,
                  (header.process == 0xc0 ? header.precision == 8 : (header.precision == 8 || header.precision == 12)),
                  header.scanParameters.allSatisfy({ $0.first == 0 && $0.last == 63 && $0.approximation == 0 }) else {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 204))
            }
            if descriptor.samplesPerPixel == 3, let transform = header.adobeTransform,
               transform != 0 && transform != 1 {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 205))
            }
        }
        let sourceColor: JLIColorModel?
        if lossless || descriptor.samplesPerPixel == 1 { sourceColor = nil }
        else if header.adobeTransform == 0 || header.components.hasRGBIdentifiers { sourceColor = .rgb }
        else if header.jfif || header.adobeTransform == 1 || descriptor.photometricInterpretation.isYBR {
            sourceColor = .yCbCr
        } else { sourceColor = .rgb }
        let configuration = JLIDecoderConfiguration(sourceColorModel: sourceColor,
            maximumEncodedBytes: decodingLimits.maximumEncodedBytes,
            maximumPixels: decodingLimits.maximumPixels,
            maximumDecodedBytes: decodingLimits.maximumDecodedBytes)
        return .success((expectedBytes, configuration))
    }

    /// Managed payload decoding for monochrome lossless UInt16 and baseline RGB8
    /// interleaved output. Full retained capacity is charged before allocation;
    /// baseline RGB retains its larger reconstruction arena. Other profiles throw
    /// without falling back. Runtime/control heap qualification remains separate.
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

    /// Decode admitted lossless mono or baseline RGB through scalar canonical outcomes.
    /// This backing-only entry requires caller-owned execution storage; the execution overload
    /// additionally validates the admitted worker. Baseline RGB retains the complete arena.
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
        guard frameData.isOwned(by: budget) else { return .failure(DICOMManagedFailure(allocation: .budgetMismatch)) }
        switch decodingLimits.validateManagedOutcome(encodedByteCount: frameData.count,
            descriptor: descriptor, frameIndex: frameIndex) {
        case .success: break
        case .failure(let failure): return .failure(failure)
        }
        return withUnsafePointer(to: cancellation) { token -> DICOMManagedOutcome<ManagedDecodedPixelFrame> in
            let codecCancellation = JLICancellation(context: UnsafeRawPointer(token),
                                                     isCancelled: managedJLICancellation)
            return frameData.withBorrowedBytes { encoded -> DICOMManagedOutcome<ManagedDecodedPixelFrame> in
                let header: JPEGFrameEnvelope
                switch JPEGFrameEnvelope.parseOutcome(encoded, jpegLS: false, cancellation: cancellation) {
                case .success(let value): header = value
                case .failure(let failure): return .failure(failure)
                }
                let plan: (expectedBytes: Int, configuration: JLIDecoderConfiguration)
                switch prepareManagedOutcome(encodedByteCount: encoded.count, header: header,
                                              descriptor: descriptor, frameIndex: frameIndex) {
                case .success(let value): plan = value
                case .failure(let failure): return .failure(failure)
                }
                let decoder = JLIDecoder()
                if header.process == 0xc3 && descriptor.samplesPerPixel == 1 && descriptor.bitsAllocated == 16 {
                    let workspace: DICOMByteBuffer
                    switch DICOMByteBuffer.admit(count: JLIDecoder.losslessMonochromeWorkspaceByteCount,
                                                 budget: budget, resource: .staging) {
                    case .success(let value): workspace = value
                    case .failure(let failure): return .failure(failure)
                    }
                    let info: JLIDecoder.LosslessMonochromeInfo
                    switch decoder.inspectLosslessMonochromeCore(encoded, workspace: workspace.unsafeMutableBytes,
                        configuration: plan.configuration, cancellation: codecCancellation) {
                    case .success(let value): info = value
                    case .failure(let failure): return .failure(Self.managedFailure(failure))
                    }
                    guard info.outputByteCount == plan.expectedBytes else {
                        return .failure(DICOMManagedFailure(.codecResultMismatch))
                    }
                    let bytes: DICOMByteBuffer
                    switch DICOMByteBuffer.admit(count: info.outputByteCount, budget: budget, resource: .decoded) {
                    case .success(let value): bytes = value
                    case .failure(let failure): return .failure(failure)
                    }
                    let decoded: JLIDecoder.LosslessMonochromeInfo
                    switch decoder.decodeLosslessMonochromeCore(encoded, into: bytes.unsafeMutableBytes,
                        workspace: workspace.unsafeMutableBytes, configuration: plan.configuration,
                        cancellation: codecCancellation) {
                    case .success(let value): decoded = value
                    case .failure(let failure): return .failure(Self.managedFailure(failure))
                    }
                    guard decoded == info else { return .failure(DICOMManagedFailure(.codecResultMismatch)) }
                    if let failure = cancellation.failure { return .failure(failure) }
                    return .success(ManagedDecodedPixelFrame(data: bytes, descriptor: descriptor,
                                                              sourceFrameIndex: frameIndex))
                }
                guard header.process == 0xc0, descriptor.samplesPerPixel == 3,
                      descriptor.bitsAllocated == 8, descriptor.planarConfiguration == 0 else {
                    return .failure(DICOMManagedFailure(.invalidDescriptor, 206))
                }
                let info: JLIDecoder.BaselineRGBInfo
                do {
                    let inspection: DICOMByteBuffer
                    switch DICOMByteBuffer.admit(count: JLIDecoder.baselineHeaderWorkspaceByteCount,
                                                 budget: budget, resource: .staging) {
                    case .success(let value): inspection = value
                    case .failure(let failure): return .failure(failure)
                    }
                    switch decoder.inspectBaselineRGBCore(encoded, headerWorkspace: inspection.unsafeMutableBytes,
                        configuration: plan.configuration, cancellation: codecCancellation) {
                    case .success(let value): info = value
                    case .failure(let failure): return .failure(Self.managedFailure(failure))
                    }
                }
                guard info.outputByteCount == plan.expectedBytes else {
                    return .failure(DICOMManagedFailure(.codecResultMismatch))
                }
                let workspace: DICOMByteBuffer
                switch DICOMByteBuffer.admit(count: info.workspaceByteCount, budget: budget, resource: .staging) {
                case .success(let value): workspace = value
                case .failure(let failure): return .failure(failure)
                }
                let bytes: DICOMByteBuffer
                switch DICOMByteBuffer.admit(count: info.outputByteCount, capacity: info.arenaByteCount,
                                             budget: budget, resource: .decoded) {
                case .success(let value): bytes = value
                case .failure(let failure): return .failure(failure)
                }
                let decoded: JLIDecoder.BaselineRGBInfo
                switch decoder.decodeBaselineRGBCore(encoded, arena: bytes.unsafeMutableBytes,
                    workspace: workspace.unsafeMutableBytes, configuration: plan.configuration,
                    cancellation: codecCancellation) {
                case .success(let value): decoded = value
                case .failure(let failure): return .failure(Self.managedFailure(failure))
                }
                guard decoded == info else { return .failure(DICOMManagedFailure(.codecResultMismatch)) }
                if let failure = cancellation.failure { return .failure(failure) }
                let output = PixelDataDescriptor(rows: descriptor.rows, columns: descriptor.columns,
                    numberOfFrames: descriptor.numberOfFrames, bitsAllocated: descriptor.bitsAllocated,
                    bitsStored: descriptor.bitsStored, highBit: descriptor.highBit, isSigned: descriptor.isSigned,
                    samplesPerPixel: 3, photometricInterpretation: .rgb, planarConfiguration: 0)
                return .success(ManagedDecodedPixelFrame(data: bytes, descriptor: output, sourceFrameIndex: frameIndex))
            }
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

    private static func managedFailure(_ error: JLICoreFailure) -> DICOMManagedFailure {
        if error.kind == .cancelled { return DICOMManagedFailure(.cancelled) }
        // Domain 0x0200 identifies JLI; its low byte preserves the dependency's failure kind.
        return DICOMManagedFailure(.codecFailure, Int(error.code), error.detail0,
            operand3: error.detail1, operand4: error.detail2, domain: 0x0200 | UInt16(error.kind.rawValue))
    }

    // MARK: - Encoding

    /// Whether this codec can encode the given configuration for its target syntax.
    ///
    /// Constraints follow each JPEG process plus JLISwift's input rules:
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

        // Lossy DCT: JLISwift's level shift is defined only for unsigned samples.
        if descriptor.isSigned {
            return false
        }
        // Pre-converted YCbCr (YBR_FULL_422/YBR_FULL) input only has an 8-bit path
        // through JLIEncoder — see the `.yCbCr` colorModel branch in `encodeFrame`.
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
            throw DICOMError.parsingFailed("JLISwift: unsupported samplesPerPixel \(spp)")
        }
        let pixelFormat: JLIPixelFormat = descriptor.bitsAllocated <= 8 ? .uint8 : .uint16
        let colorModel: JLIColorModel
        if spp == 1 {
            colorModel = .grayscale
        } else if !encodesLossless && descriptor.photometricInterpretation.isYBR {
            // Samples are already YCbCr (e.g. YBR_FULL_422) — tell JLIEncoder not to
            // re-transform them on the lossy DCT path. Only valid for 8-bit input
            // (JLIEncoder's pre-converted YCbCr path is 8-bit only), which matches
            // Table 8.2.1-1: the DICOM JPEG processes only permit YBR_FULL_422/RGB
            // color on 8-bit Baseline, never on 12-bit Extended.
            //
            // The lossless (SOF3) path never transforms color regardless of this
            // label — JLIEncoder requires it to literally be `.rgb`/`.rgba` there
            // (a component-count marker, not a color-space claim), so YBR-tagged
            // lossless input keeps `.rgb` below and round-trips byte-exact either way.
            guard pixelFormat == .uint8 else {
                throw DICOMError.parsingFailed(
                    "JLISwift: \(descriptor.photometricInterpretation.rawValue) input requires "
                    + "8-bit samples (bitsAllocated=\(descriptor.bitsAllocated))")
            }
            colorModel = .yCbCr
        } else {
            colorModel = .rgb
        }
        let interleaved = interleavedFrameBytes(from: frameData, descriptor: descriptor)

        do {
            let image = try JLIImage(width: descriptor.columns, height: descriptor.rows,
                                     pixelFormat: pixelFormat, colorModel: colorModel,
                                     data: interleaved, isSigned: descriptor.isSigned)
            let cfg = encoderConfiguration(descriptor: descriptor, configuration: configuration,
                                           pixelFormat: pixelFormat)
            // JLISwift writes a JFIF APP0 segment; PS3.5 2026a 8.2.1 recommends it be absent (D190).
            return JPEGInterchangeFormat.removingJFIFSegments(Data(try JLIEncoder().encode(image, configuration: cfg)))
        } catch {
            throw DICOMError.parsingFailed("JLISwift encode failed: \(error)")
        }
    }

    // MARK: - Configuration mapping

    /// Builds the JLISwift encoder configuration for the target JPEG process.
    private func encoderConfiguration(descriptor: PixelDataDescriptor,
                                      configuration: CompressionConfiguration,
                                      pixelFormat: JLIPixelFormat) -> JLIEncoderConfiguration {
        if encodesLossless {
            // SOF3 predictor 1, point-transform 0 — bit-exact. Both .57 (Process 14)
            // and .70 (SV1) are valid with the left predictor; .70 *requires* it.
            var cfg = JLIEncoderConfiguration.diagnosticLossless
            cfg.losslessPredictor = 1
            cfg.losslessPointTransform = 0
            if pixelFormat == .uint16 {
                // Pin precision to the stored depth; otherwise JLISwift derives
                // 12-bit and drops the high bits of >12-bit sources.
                cfg.losslessPrecision = min(16, max(2, descriptor.bitsStored))
            }
            return cfg
        }

        // Lossy DCT — start from the tuned perceptual defaults, then force the
        // properties the DICOM JPEG processes mandate:
        //   • sequential, never progressive (Baseline/Extended are non-progressive);
        //   • colour as YCbCr 4:2:2 — PS3.5 2026a Table 8.2.1-1 allows a 3-sample JPEG Baseline
        //     stream only as YBR_FULL_422 or RGB (components stored as RGB). JLISwift's lossy
        //     path always applies the RGB → YCbCr transform, so the stream is written 4:2:2 and
        //     labelled YBR_FULL_422 by the transcoders (D190 / D-CORE-2). 4:4:4 YCbCr has no
        //     valid label.
        // Sample precision (SOF0 8-bit vs SOF1 12-bit) follows the pixel format.
        var cfg = JLIEncoderConfiguration.default
        cfg.lossless = false
        cfg.progressive = false
        cfg.chromaSubsampling = descriptor.samplesPerPixel == 3 ? .yuv422 : .yuv444
        cfg.distance = nil
        cfg.quality = Self.jpegQuality(from: configuration.quality)
        return cfg
    }

    /// Maps a DICOM `CompressionQuality` (0.0–1.0) to a JPEG quality factor (1–100).
    static func jpegQuality(from quality: CompressionQuality) -> Double {
        max(1.0, min(100.0, quality.value * 100.0))
    }
}

// The context is a borrowed stack value for the entire synchronous JLI call.
private func managedJLICancellation(_ context: UnsafeRawPointer?) -> Bool {
    guard let context else { return false }
    let token = context.assumingMemoryBound(to: DICOMCancellation.self).pointee
    return token.check?(token.context) == true
}
