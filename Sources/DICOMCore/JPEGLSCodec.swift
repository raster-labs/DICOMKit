import Foundation
import JPEGLS

/// JPEG-LS codec backed by the JLSwift `JPEGLS` package.
///
/// Bridges DICOM pixel data (PS3.5 §A.4.3, JPEG-LS Image Compression) to JLSwift's pure-Swift JPEG-LS
/// implementation (ITU-T T.87 / ISO/IEC 14495-1) for both lossless and
/// near-lossless encode/decode. The previous in-tree JPEG-LS implementation
/// (markers, bit I/O, context modelling) was retired in favour of JLSwift.
///
/// Transfer syntaxes:
///   • 1.2.840.10008.1.2.4.80  JPEG-LS Lossless
///   • 1.2.840.10008.1.2.4.81  JPEG-LS Near-Lossless
/// NEMA-verified: 2026a, checked 2026-09-25 — the two JPEG-LS UIDs come from `TransferSyntax` (PS3.6 2026a Table A-1). `canEncode` (8 or 16 allocated, 2–16 stored, 1 or 3 samples) matches PS3.5 2026a Table 8.2.3-1. The header citation said §A.4.5 (MPEG2); corrected to §A.4.3. The codec implements ITU-T T.87, outside DICOM.
public struct JPEGLSCodec: ImageCodec, ImageEncoder, Sendable {
    /// Finite decode policy that does not construct or retain transfer-syntax Strings.
    public enum DecodingSyntax: UInt8, Sendable {
        /// Admit both existing lossless and near-lossless profiles.
        case any
        /// Enforce the JPEG-LS Lossless profile.
        case lossless
        /// Enforce the JPEG-LS Near-Lossless profile.
        case nearLossless
    }

    /// Controls precision recovery for descriptor-bearing inspection and decoding.
    public enum PrecisionPolicy: Sendable {
        /// Reject inconsistent source Bits Stored and encoded precision (the default).
        case requireSourceMatch
        /// Permit unsigned monochrome NEAR=0 streams with 16-bit precision in a
        /// source 16-bit container whose Bits Stored is smaller. Return all samples
        /// unchanged with an actual 16-bit descriptor and an explicit diagnostic.
        /// PS3.5 2026a 8.2.3 imports the receiver-recovery notes of 8.2.1.
        case useCodestreamForUnsignedMonochrome
    }

    /// Header-derived interpretation shared by indexing and sample decoding.
    /// Successful inspection does not qualify entropy data or decoded sample values.
    public struct FrameInfo: Sendable {
        /// Actual sample descriptor under the selected precision policy.
        public let descriptor: PixelDataDescriptor
        /// Zero-based index in the source object.
        public let sourceFrameIndex: Int
        /// Recovery diagnostics; source attributes remain unchanged.
        public var diagnostics: [PixelDecodeDiagnostic] {
            if let diagnostic { return [diagnostic] }
            return []
        }
        /// Scalar recovery diagnostic used by explicitly admitted decoding.
        public let diagnostic: PixelDecodeDiagnostic?
        fileprivate let expectedByteCount: Int
    }

    /// Supported JPEG-LS transfer syntaxes for decoding
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.jpegLSLossless.uid,      // 1.2.840.10008.1.2.4.80
        TransferSyntax.jpegLSNearLossless.uid    // 1.2.840.10008.1.2.4.81
    ]

    /// Supported JPEG-LS transfer syntaxes for encoding
    public static let supportedEncodingTransferSyntaxes: [String] = [
        TransferSyntax.jpegLSLossless.uid,      // 1.2.840.10008.1.2.4.80
        TransferSyntax.jpegLSNearLossless.uid    // 1.2.840.10008.1.2.4.81
    ]

    /// The transfer syntax this decoder instance serves, when known.
    ///
    /// The registry wires one instance per syntax. Under JPEG-LS Lossless
    /// (1.2.840.10008.1.2.4.80) a scan whose NEAR parameter is non-zero is a
    /// near-lossless scan and is refused: decoding it would return samples that
    /// differ from the encoder's input under a syntax that promises exactness.
    /// `nil` (the default) accepts both lossless and near-lossless scans.
    // Normalize caller-owned String configuration before any qualified operation.
    private enum SyntaxRestriction: Equatable, Sendable { case any, lossless, nearLossless, unsupported }
    private let syntaxRestriction: SyntaxRestriction

    private let decodingLimits: PixelDecodeLimits
    private let precisionPolicy: PrecisionPolicy

    /// Creates a decoder with optional syntax enforcement and caller-selected resource bounds.
    public init(decodingTransferSyntaxUID: String? = nil, decodingLimits: PixelDecodeLimits = .default,
                precisionPolicy: PrecisionPolicy = .requireSourceMatch) {
        switch decodingTransferSyntaxUID {
        case nil: self.syntaxRestriction = .any
        case TransferSyntax.jpegLSLossless.uid: self.syntaxRestriction = .lossless
        case TransferSyntax.jpegLSNearLossless.uid: self.syntaxRestriction = .nearLossless
        default: self.syntaxRestriction = .unsupported
        }
        self.decodingLimits = decodingLimits
        self.precisionPolicy = precisionPolicy
    }

    /// Create the same decoder from finite scalar policy without initializing UID Strings.
    /// - Parameters:
    ///   - decodingSyntax: Existing JPEG-LS profile restriction to enforce.
    ///   - decodingLimits: Bounds enforced before sample decoding.
    ///   - precisionPolicy: Existing explicit source/codestream precision policy.
    public init(decodingSyntax: DecodingSyntax, decodingLimits: PixelDecodeLimits = .init(),
                precisionPolicy: PrecisionPolicy = .requireSourceMatch) {
        switch decodingSyntax {
        case .any: syntaxRestriction = .any
        case .lossless: syntaxRestriction = .lossless
        case .nearLossless: syntaxRestriction = .nearLossless
        }
        self.decodingLimits = decodingLimits
        self.precisionPolicy = precisionPolicy
    }

    // MARK: - Decoding

    /// Decodes a JPEG-LS compressed frame strictly against `descriptor`.
    ///
    /// The decoded frame header must match the descriptor exactly: width and
    /// height equal Columns and Rows, the component count equals Samples per
    /// Pixel and the sample precision P equals Bits Stored; every component must be a full-size plane.
    /// This strict API policy implements the attribute-consistency requirement of
    /// PS3.5 2026a 8.2.3. Use `decodePixelFrame` with an explicit precision policy
    /// for bounded recovery under the receiver guidance imported from 8.2.1.
    /// Any mismatch throws. Previously a mis-sized frame was silently
    /// zero-filled or truncated to the descriptor's byte count and an
    /// over-precise frame was silently clamped.
    /// - Parameters:
    ///   - frameData: JPEG-LS compressed data
    ///   - descriptor: Pixel data descriptor
    ///   - frameIndex: Zero-based source frame index, validated against the descriptor
    /// - Returns: Uncompressed pixel data laid out per `descriptor`
    /// - Throws: `DICOMError` if decoding fails or the frame does not match `descriptor`
    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        // A Data-only caller cannot observe a corrected descriptor or diagnostics.
        try decodedPixelFrame(frameData, descriptor: descriptor, frameIndex: frameIndex,
                              precisionPolicy: .requireSourceMatch).data
    }

    /// Decodes using the selected precision policy, returning the actual sample descriptor.
    /// Original source attributes remain unchanged. Recovery never masks or clamps samples.
    /// - Parameters:
    ///   - frameData: One complete JPEG-LS codestream.
    ///   - descriptor: Original source attributes, retained unchanged by the caller.
    ///   - frameIndex: Zero-based source frame index.
    /// - Returns: Samples with their actual descriptor and recovery diagnostics.
    public func decodePixelFrame(_ frameData: Data, descriptor: PixelDataDescriptor,
                                 frameIndex: Int) throws -> DecodedPixelFrame {
        try decodedPixelFrame(frameData, descriptor: descriptor, frameIndex: frameIndex,
                              precisionPolicy: precisionPolicy)
    }

    /// Inspects the complete frame envelope and headers without decoding sample data.
    /// Uses the same policy, syntax, descriptor and allocation checks as `decodePixelFrame`.
    /// Entropy validity and sample ranges are checked only when decoding succeeds.
    /// - Parameters:
    ///   - frameData: One complete JPEG-LS codestream.
    ///   - descriptor: Original source attributes, retained unchanged by the caller.
    ///   - frameIndex: Zero-based source frame index.
    /// - Returns: Header-derived descriptor, frame identity and recovery diagnostics.
    public func inspectFrame(_ frameData: Data, descriptor: PixelDataDescriptor,
                             frameIndex: Int) throws -> FrameInfo {
        try preparedFrame(frameData, descriptor: descriptor, frameIndex: frameIndex,
                          precisionPolicy: precisionPolicy).info
    }

    private func preparedFrame(_ frameData: Data, descriptor: PixelDataDescriptor,
                               frameIndex: Int, precisionPolicy: PrecisionPolicy) throws -> (info: FrameInfo, data: Data) {
        // Reject oversized slices before rebasing can allocate a copy.
        _ = try decodingLimits.validate(frameData, descriptor: descriptor, frameIndex: frameIndex)
        let data = frameData.startIndex == 0 ? frameData : Data(frameData)
        _ = try JPEGFrameEnvelope.parse(data, jpegLS: true)
        let parsed = try JPEGLSParser(data: data).parse()
        // JLSwift applies LSE type 4 to the returned effective frame header.
        let header = parsed.frameHeader
        // Match the decoder's header-only MAXVAL guard (ITU-T T.87 C.2.4.1.1).
        let parameters = try parsed.presetParameters ?? JPEGLSPresetParameters.defaultParameters(
            bitsPerSample: header.bitsPerSample, near: parsed.scanHeaders.first?.near ?? 0)
        guard parameters.maxValue <= (1 << header.bitsPerSample) - 1 else {
            throw DICOMError.parsingFailed("JPEG-LS MAXVAL exceeds the encoded precision")
        }
        let info = try frameInfo(encodedByteCount: frameData.count, descriptor: descriptor, frameIndex: frameIndex,
            precisionPolicy: precisionPolicy, width: header.width, height: header.height,
            componentCount: header.componentCount, precision: header.bitsPerSample,
            hasNearLosslessScan: parsed.scanHeaders.contains { $0.near > 0 },
            recoveryFeaturesAllowed: parsed.scanHeaders.allSatisfy {
                $0.near == 0 && $0.pointTransform == 0 && $0.components.allSatisfy { $0.mappingTableID == 0 }
            } && parsed.mappingTables.isEmpty && parsed.colorTransformation == .none)
        let actualDescriptor = info.descriptor
        // Match the maintained decoder's Int-plane budget during header inspection,
        // before allocating samples. Descriptor validation above bounds dimensions.
        let (pixels, pixelOverflow) = actualDescriptor.rows.multipliedReportingOverflow(by: actualDescriptor.columns)
        let (samples, sampleOverflow) = pixels.multipliedReportingOverflow(by: actualDescriptor.samplesPerPixel)
        let (planeBytes, byteOverflow) = samples.multipliedReportingOverflow(by: MemoryLayout<Int>.stride)
        guard !pixelOverflow, !sampleOverflow, !byteOverflow,
              planeBytes > 0, planeBytes <= decodingLimits.maximumDecodedBytes else {
            throw DICOMError.limitExceeded("JPEG-LS intermediate sample planes exceed decoded byte budget")
        }
        return (info, data)
    }

    private func frameInfo(encodedByteCount: Int, descriptor: PixelDataDescriptor,
        frameIndex: Int, precisionPolicy: PrecisionPolicy, width: Int, height: Int,
        componentCount: Int, precision: Int, hasNearLosslessScan: Bool,
        recoveryFeaturesAllowed: Bool) throws -> FrameInfo {
        do {
            return try managedFrameInfo(encodedByteCount: encodedByteCount, descriptor: descriptor,
                frameIndex: frameIndex, precisionPolicy: precisionPolicy, width: width, height: height,
                componentCount: componentCount, precision: precision, hasNearLosslessScan: hasNearLosslessScan,
                recoveryFeaturesAllowed: recoveryFeaturesAllowed)
        } catch {
            switch error.operand1 {
            case 100: throw DICOMError.parsingFailed("JPEG-LS effective header does not match DICOM descriptor")
            case 101: throw DICOMError.parsingFailed("JPEG-LS precision mismatch is outside the selected recovery policy")
            case 102: throw DICOMError.parsingFailed("Unsupported JPEG-LS decoding transfer syntax")
            case 103: throw DICOMError.parsingFailed("JPEG-LS Lossless frame carries a near-lossless scan")
            case 0: throw DICOMError.limitExceeded("Compressed frame exceeds encoded byte budget or is empty")
            case 1: throw DICOMError.parsingFailed("Invalid compressed frame descriptor or frame index")
            default: throw DICOMError.limitExceeded("Compressed frame exceeds decoded pixel/byte budget")
            }
        }
    }

    private func managedFrameInfo(encodedByteCount: Int, descriptor: PixelDataDescriptor,
        frameIndex: Int, precisionPolicy: PrecisionPolicy, width: Int, height: Int,
        componentCount: Int, precision: Int, hasNearLosslessScan: Bool,
        recoveryFeaturesAllowed: Bool) throws(DICOMManagedFailure) -> FrameInfo {
        try managedFrameInfoOutcome(encodedByteCount: encodedByteCount, descriptor: descriptor,
            frameIndex: frameIndex, precisionPolicy: precisionPolicy, width: width, height: height,
            componentCount: componentCount, precision: precision, hasNearLosslessScan: hasNearLosslessScan,
            recoveryFeaturesAllowed: recoveryFeaturesAllowed).get()
    }

    private func managedFrameInfoOutcome(encodedByteCount: Int, descriptor: PixelDataDescriptor,
        frameIndex: Int, precisionPolicy: PrecisionPolicy, width: Int, height: Int,
        componentCount: Int, precision: Int, hasNearLosslessScan: Bool,
        recoveryFeaturesAllowed: Bool) -> DICOMManagedOutcome<FrameInfo> {
        guard width == descriptor.columns, height == descriptor.rows,
              componentCount == descriptor.samplesPerPixel else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 100))
        }

        var actualDescriptor = descriptor
        var diagnostic: PixelDecodeDiagnostic?
        if precision != descriptor.bitsStored {
            guard case .useCodestreamForUnsignedMonochrome = precisionPolicy,
                  !descriptor.isSigned, descriptor.samplesPerPixel == 1,
                  descriptor.photometricInterpretation == .monochrome1
                    || descriptor.photometricInterpretation == .monochrome2,
                  descriptor.bitsAllocated == 16, precision == 16,
                  descriptor.bitsStored < 16,
                  recoveryFeaturesAllowed,
                  syntaxRestriction == .any || syntaxRestriction == .lossless else {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 101))
            }
            actualDescriptor = PixelDataDescriptor(rows: descriptor.rows, columns: descriptor.columns,
                numberOfFrames: descriptor.numberOfFrames, bitsAllocated: 16, bitsStored: 16, highBit: 15,
                isSigned: false, samplesPerPixel: 1, photometricInterpretation: descriptor.photometricInterpretation,
                planarConfiguration: descriptor.planarConfiguration)
            diagnostic = .sourcePrecisionMismatch(sourceBitsStored: descriptor.bitsStored, encodedPrecision: precision)
        }
        let expectedBytes: Int
        switch decodingLimits.validateManagedOutcome(encodedByteCount: encodedByteCount,
            descriptor: actualDescriptor, frameIndex: frameIndex) {
        case .success(let value): expectedBytes = value
        case .failure(let failure): return .failure(failure)
        }
        guard syntaxRestriction != .unsupported else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 102))
        }
        if syntaxRestriction == .lossless, hasNearLosslessScan {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 103))
        }

        return .success(FrameInfo(descriptor: actualDescriptor, sourceFrameIndex: frameIndex,
                         diagnostic: diagnostic, expectedByteCount: expectedBytes))
    }

    /// Decode a monochrome 16-bit-container frame into explicitly admitted backing.
    /// Pixel/workspace capacities are charged before allocation. Runtime/control
    /// allocation qualification is separate; this API makes no aggregate heap claim.
    /// Other profiles must use their existing APIs; there is no uncharged fallback.
    /// - Parameters:
    ///   - frameData: Immutable encoded frame allocated using `budget`.
    ///   - descriptor: Source pixel interpretation to validate against the codestream.
    ///   - frameIndex: Zero-based source frame index.
    ///   - budget: The exact ledger instance owning `frameData`.
    ///   - cancellation: Borrowed synchronous cancellation observer.
    /// - Returns: Actual decoded descriptor, interpretation diagnostics and managed storage.
    public func decodeManagedPixelFrame(_ frameData: borrowing DICOMByteBuffer, descriptor: PixelDataDescriptor,
        frameIndex: Int, budget: borrowing DICOMAllocationBudget, cancellation: DICOMCancellation = .never)
        throws(DICOMManagedFailure) -> ManagedDecodedPixelFrame {
        try decodeManagedPixelFrameOutcome(frameData, descriptor: descriptor, frameIndex: frameIndex,
                                            budget: budget, cancellation: cancellation).get()
    }

    /// Throwing compatibility adapter for an admitted worker; use the outcome overload inside qualified work.
    @available(*, noasync, message: "Invoke on the synchronous worker owning the execution reservation")
    public func decodeManagedPixelFrame(_ frameData: borrowing DICOMByteBuffer, descriptor: PixelDataDescriptor,
        frameIndex: Int, budget: borrowing DICOMAllocationBudget,
        execution: borrowing DICOMExecutionReservation, cancellation: DICOMCancellation = .never)
        throws(DICOMManagedFailure) -> ManagedDecodedPixelFrame {
        try decodeManagedPixelFrameOutcome(frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, execution: execution, cancellation: cancellation).get()
    }

    /// Decode the admitted monochrome profile using scalar outcomes throughout the canonical path.
    /// This backing-only entry requires caller-owned execution storage; use the execution overload
    /// to validate an explicitly admitted worker. No throwing compatibility adapter is called.
    /// - Parameters:
    ///   - frameData: Immutable encoded owner retained by the same budget.
    ///   - descriptor: Source interpretation validated against the codestream.
    ///   - frameIndex: Zero-based source frame identity.
    ///   - budget: Ledger for input, workspace, decoded payload and control storage.
    ///   - cancellation: Caller-owned synchronous cancellation observer.
    /// - Returns: Complete managed output or a fixed scalar failure after temporary cleanup.
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
        guard descriptor.samplesPerPixel == 1, descriptor.bitsAllocated == 16 else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 104))
        }
        return frameData.withBorrowedBytes { encoded -> DICOMManagedOutcome<ManagedDecodedPixelFrame> in
            switch JPEGFrameEnvelope.parseOutcome(encoded, jpegLS: true, cancellation: cancellation) {
            case .success: break
            case .failure(let failure): return .failure(failure)
            }
            let decoder = JPEGLSDecoder(limits: .init(maximumEncodedBytes: decodingLimits.maximumEncodedBytes,
                maximumPixels: decodingLimits.maximumPixels, maximumDecodedBytes: decodingLimits.maximumDecodedBytes))
            let workspace: DICOMByteBuffer
            switch DICOMByteBuffer.admit(count: JPEGLSDecoder.monochromeWorkspaceByteCount,
                                         budget: budget, resource: .staging) {
            case .success(let value): workspace = value
            case .failure(let failure): return .failure(failure)
            }
            let codecCancellation = JPEGLSCancellation(check: cancellation.check, context: cancellation.context)
            let header: JPEGLSDecoder.MonochromeInfo
            switch decoder.inspectMonochromeQualified(encoded, workspace: workspace.unsafeMutableBytes,
                                                       cancellation: codecCancellation) {
            case .success(let value): header = value
            case .failure(let failure): return .failure(Self.managedFailure(failure))
            }
            let info: FrameInfo
            switch managedFrameInfoOutcome(encodedByteCount: encoded.count, descriptor: descriptor,
                frameIndex: frameIndex, precisionPolicy: precisionPolicy, width: header.width, height: header.height,
                componentCount: 1, precision: header.bitsPerSample, hasNearLosslessScan: header.near > 0,
                recoveryFeaturesAllowed: header.near == 0 && header.pointTransform == 0
                    && header.mappingTableID == 0 && !header.hasMappingTables && header.colorTransformation == .none) {
            case .success(let value): info = value
            case .failure(let failure): return .failure(failure)
            }
            let bytes: DICOMByteBuffer
            switch DICOMByteBuffer.admit(count: info.expectedByteCount, budget: budget, resource: .decoded) {
            case .success(let value): bytes = value
            case .failure(let failure): return .failure(failure)
            }
            let samples = bytes.unsafeMutableBytes.bindMemory(to: UInt16.self)
            samples.initialize(repeating: 0)
            let decoded: JPEGLSDecoder.MonochromeInfo
            switch decoder.decodeMonochromeQualified(encoded, into: samples,
                workspace: workspace.unsafeMutableBytes, cancellation: codecCancellation) {
            case .success(let value): decoded = value
            case .failure(let failure): return .failure(Self.managedFailure(failure))
            }
            guard decoded == header else { return .failure(DICOMManagedFailure(.codecResultMismatch)) }
            for index in samples.indices {
                if index & 0xFFFF == 0, let failure = cancellation.failure { return .failure(failure) }
                samples[index] = samples[index].littleEndian
            }
            if let failure = cancellation.failure { return .failure(failure) }
            return .success(ManagedDecodedPixelFrame(data: bytes, descriptor: info.descriptor,
                sourceFrameIndex: frameIndex, diagnostic: info.diagnostic))
        }
    }

    /// Decode on the original admitted worker with scalar identity/refusal status.
    /// - Parameters:
    ///   - frameData: Encoded backing retained by the operation ledger.
    ///   - descriptor: Source interpretation to validate.
    ///   - frameIndex: Source frame identity.
    ///   - budget: Shared admission ledger.
    ///   - execution: Whole-stack reservation retained until the synchronous worker returns.
    ///   - cancellation: Borrowed synchronous cancellation observer.
    /// - Returns: Managed output or scalar failure, without Swift throwing machinery.
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

    private static func managedFailure(_ error: JPEGLSManagedFailure) -> DICOMManagedFailure {
        if error.code == .cancelled { return DICOMManagedFailure(.cancelled) }
        // Domain 0x0100 is JPEGLS; preserve both numerical dependency operands.
        return DICOMManagedFailure(.codecFailure, Int(error.code.rawValue), error.operand0,
                                   operand3: error.operand1, domain: 0x0100)
    }

    private func decodedPixelFrame(_ frameData: Data, descriptor: PixelDataDescriptor,
                                   frameIndex: Int, precisionPolicy: PrecisionPolicy) throws -> DecodedPixelFrame {
        let (info, data) = try preparedFrame(frameData, descriptor: descriptor, frameIndex: frameIndex,
                                             precisionPolicy: precisionPolicy)
        let image: MultiComponentImageData
        do {
            image = try JPEGLSDecoder(limits: .init(maximumEncodedBytes: decodingLimits.maximumEncodedBytes,
                maximumPixels: decodingLimits.maximumPixels,
                maximumDecodedBytes: decodingLimits.maximumDecodedBytes)).decode(data)
        } catch {
            throw DICOMError.parsingFailed("JPEG-LS decode failed: \(error)")
        }

        try Self.validate(image, against: info.descriptor)
        let bytes = serialize(image, descriptor: info.descriptor)
        guard bytes.count == info.expectedByteCount else { throw DICOMError.parsingFailed("JPEG-LS output length mismatch") }
        return DecodedPixelFrame(data: bytes, descriptor: info.descriptor, sourceFrameIndex: info.sourceFrameIndex,
                                 diagnostics: info.diagnostics)
    }

    /// Verifies that the decoded image is exactly the frame `descriptor` declares.
    static func validate(_ image: MultiComponentImageData, against descriptor: PixelDataDescriptor) throws {
        let header = image.frameHeader
        guard header.width == descriptor.columns, header.height == descriptor.rows else {
            throw DICOMError.parsingFailed(
                "Decoded JPEG-LS dimensions (\(header.width)x\(header.height)) do not match expected "
                    + "(\(descriptor.columns)x\(descriptor.rows))"
            )
        }
        guard header.componentCount == descriptor.samplesPerPixel,
              image.components.count == descriptor.samplesPerPixel else {
            throw DICOMError.parsingFailed(
                "Decoded JPEG-LS component count \(image.components.count) (frame header "
                    + "\(header.componentCount)) does not match samples per pixel \(descriptor.samplesPerPixel)"
            )
        }
        guard header.bitsPerSample == descriptor.bitsStored, header.bitsPerSample <= descriptor.bitsAllocated else {
            throw DICOMError.parsingFailed(
                "Decoded JPEG-LS precision \(header.bitsPerSample) bits does not match Bits Stored "
                    + "\(descriptor.bitsStored) (Bits Allocated \(descriptor.bitsAllocated))"
            )
        }
        for component in image.components {
            guard component.pixels.count == descriptor.rows,
                  component.pixels.allSatisfy({ $0.count == descriptor.columns }) else {
                throw DICOMError.parsingFailed(
                    "Decoded JPEG-LS component \(component.id) is not a full \(descriptor.columns)x\(descriptor.rows) "
                        + "plane; sub-sampled components are not supported"
                )
            }
            let maximum = (1 << header.bitsPerSample) - 1
            guard component.pixels.allSatisfy({ $0.allSatisfy({ $0 >= 0 && $0 <= maximum }) }) else {
                throw DICOMError.parsingFailed("Decoded JPEG-LS samples exceed the encoded precision")
            }
        }
    }

    // MARK: - Encoding

    /// Whether this encoder supports the given configuration
    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
            return false
        }
        guard descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3 else {
            return false
        }
        return true
    }

    /// Encodes a single frame to JPEG-LS format
    /// - Parameters:
    ///   - frameData: Uncompressed frame data laid out per `descriptor`
    ///   - descriptor: Pixel data descriptor
    ///   - frameIndex: Zero-based frame index
    ///   - configuration: Compression configuration
    /// - Returns: JPEG-LS compressed frame data
    /// - Throws: `DICOMError` if encoding fails
    public func encodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int, configuration: CompressionConfiguration) throws -> Data {
        let near = nearParameter(for: configuration, descriptor: descriptor)
        // JLSwift expects sample values in [0, 2^bitsPerSample - 1]; track the
        // stored precision (Bits Stored) rather than the allocated container.
        let bitsPerSample = max(2, descriptor.bitsStored)
        let interleave: JPEGLSInterleaveMode = descriptor.samplesPerPixel > 1 ? .sample : .none

        do {
            let image = try buildImage(from: frameData, descriptor: descriptor, bitsPerSample: bitsPerSample)
            let config = try JPEGLSEncoder.Configuration(near: near, interleaveMode: interleave)
            return try JPEGLSEncoder().encode(image, configuration: config)
        } catch let error as DICOMError {
            throw error
        } catch {
            throw DICOMError.parsingFailed("JPEG-LS encode failed: \(error)")
        }
    }

    // MARK: - NEAR parameter

    /// Derives the JPEG-LS NEAR value from a DICOM compression configuration.
    /// Lossless (or lossless-preferring) configurations map to NEAR = 0.
    ///
    /// JLSwift's encoder caps NEAR at 255 regardless of sample precision
    /// (`JPEGLSEncoder.Configuration` rejects NEAR > 255), so the derived value
    /// is clamped to that range — otherwise a 16-bit source at, e.g., "high"
    /// quality would yield NEAR ≈ 655 and the encode would throw.
    private func nearParameter(for configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Int {
        if configuration.preferLossless || configuration.quality.isLossless {
            return 0
        }
        let maxVal = descriptor.bitsAllocated == 8 ? 255 : (1 << descriptor.bitsStored) - 1
        let scaled = Int(Double(maxVal) * (1.0 - configuration.quality.value) * 0.1)
        return min(Self.maxNear, max(0, scaled))
    }

    /// Largest NEAR value JLSwift's `JPEGLSEncoder.Configuration` accepts.
    private static let maxNear = 255

    // MARK: - Pixel (de)serialization

    /// Bytes per stored sample, derived from Bits Allocated (8 → 1, otherwise 2).
    private func bytesPerSample(_ descriptor: PixelDataDescriptor) -> Int {
        descriptor.bitsAllocated <= 8 ? 1 : 2
    }

    /// Linear pixel index for component `c` at (`x`, `y`), honouring Samples per
    /// Pixel and Planar Configuration (0 = sample-interleaved, 1 = planar).
    private func pixelIndex(component c: Int, x: Int, y: Int, width: Int, height: Int, samples: Int, planar: Bool) -> Int {
        if samples == 1 {
            return y * width + x
        } else if planar {
            return c * width * height + y * width + x
        } else {
            return (y * width + x) * samples + c
        }
    }

    /// Serializes JLSwift's row-major `[[Int]]` components into DICOM pixel bytes
    /// matching `descriptor` (Bits Allocated, Samples per Pixel, Planar
    /// Configuration). 16-bit samples are written little-endian per DICOM.
    /// Callers must `validate` first: every plane is exactly `columns` x `rows`.
    private func serialize(_ image: MultiComponentImageData, descriptor: PixelDataDescriptor) -> Data {
        let width = descriptor.columns
        let height = descriptor.rows
        let samples = descriptor.samplesPerPixel
        let bps = bytesPerSample(descriptor)
        let planar = descriptor.planarConfiguration == 1
        var output = Data(count: width * height * samples * bps)

        output.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let buffer = base.assumingMemoryBound(to: UInt8.self)
            for c in 0..<samples {
                let pixels = image.components[c].pixels
                for y in 0..<height {
                    let row = pixels[y]
                    for x in 0..<width {
                        let value = row[x]
                        let byteIndex = pixelIndex(component: c, x: x, y: y, width: width, height: height, samples: samples, planar: planar) * bps
                        if bps == 1 {
                            buffer[byteIndex] = UInt8(clamping: value)
                        } else {
                            buffer[byteIndex] = UInt8(value & 0xFF)
                            buffer[byteIndex + 1] = UInt8((value >> 8) & 0xFF)
                        }
                    }
                }
            }
        }
        return output
    }

    /// Builds a JLSwift `MultiComponentImageData` from DICOM pixel bytes.
    private func buildImage(from frameData: Data, descriptor: PixelDataDescriptor, bitsPerSample: Int) throws -> MultiComponentImageData {
        let width = descriptor.columns
        let height = descriptor.rows
        let samples = descriptor.samplesPerPixel
        let bps = bytesPerSample(descriptor)
        let planar = descriptor.planarConfiguration == 1
        let start = frameData.startIndex

        func sample(component c: Int, _ x: Int, _ y: Int) -> Int {
            let byteIndex = pixelIndex(component: c, x: x, y: y, width: width, height: height, samples: samples, planar: planar) * bps
            if bps == 1 {
                guard byteIndex < frameData.count else { return 0 }
                return Int(frameData[start + byteIndex])
            } else {
                guard byteIndex + 1 < frameData.count else { return 0 }
                return Int(frameData[start + byteIndex]) | (Int(frameData[start + byteIndex + 1]) << 8)
            }
        }

        func plane(component c: Int) -> [[Int]] {
            var rows = [[Int]]()
            rows.reserveCapacity(height)
            for y in 0..<height {
                var row = [Int](repeating: 0, count: width)
                for x in 0..<width {
                    row[x] = sample(component: c, x, y)
                }
                rows.append(row)
            }
            return rows
        }

        switch samples {
        case 1:
            return try MultiComponentImageData.grayscale(pixels: plane(component: 0), bitsPerSample: bitsPerSample)
        case 3:
            return try MultiComponentImageData.rgb(
                redPixels: plane(component: 0),
                greenPixels: plane(component: 1),
                bluePixels: plane(component: 2),
                bitsPerSample: bitsPerSample
            )
        default:
            throw DICOMError.parsingFailed("JPEG-LS encode: unsupported samplesPerPixel \(samples)")
        }
    }
}
