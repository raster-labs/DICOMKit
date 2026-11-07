import Foundation
import SwiftJLS

/// JPEG-LS codec backed by the `SwiftJLS` package.
///
/// Bridges DICOM pixel data (PS3.5 §A.4.3, JPEG-LS Image Compression) to `SwiftJLS`'s pure-Swift
/// JPEG-LS implementation (ITU-T T.87 / ISO/IEC 14495-1) for both lossless and near-lossless
/// encode/decode, caller-destination shared storage (`copyPolicy: .requireSharedStorage`),
/// explicit `Fidelity` verification, and `DICOMAllocationBudget` managed monochrome/component decoding.
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

    /// JPEG-LS scan interleave mode (`ILV` parameter in SOS, ITU-T T.87 C.2.3).
    public enum InterleaveMode: Sendable, Equatable {
        /// `.none` (`ILV = 0`) for monochrome, `.sample` (`ILV = 2`) for multi-component.
        case automatic
        /// Non-interleaved (`ILV = 0`, one scan per component).
        case none
        /// Line-interleaved (`ILV = 1`, multi-component single scan).
        case line
        /// Sample-interleaved (`ILV = 2`, multi-component single scan).
        case sample
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
        TransferSyntax.jpegLSNearLossless.uid   // 1.2.840.10008.1.2.4.81
    ]

    /// Supported JPEG-LS transfer syntaxes for encoding
    public static let supportedEncodingTransferSyntaxes: [String] = [
        TransferSyntax.jpegLSLossless.uid,      // 1.2.840.10008.1.2.4.80
        TransferSyntax.jpegLSNearLossless.uid   // 1.2.840.10008.1.2.4.81
    ]

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
    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        // A Data-only caller cannot observe a corrected descriptor or diagnostics.
        try decodedPixelFrame(frameData, descriptor: descriptor, frameIndex: frameIndex,
                              precisionPolicy: .requireSourceMatch).data
    }

    /// Decodes using the selected precision policy, returning the actual sample descriptor.
    /// Original source attributes remain unchanged. Recovery never masks or clamps samples.
    public func decodePixelFrame(_ frameData: Data, descriptor: PixelDataDescriptor,
                                 frameIndex: Int) throws -> DecodedPixelFrame {
        try decodedPixelFrame(frameData, descriptor: descriptor, frameIndex: frameIndex,
                              precisionPolicy: precisionPolicy)
    }

    /// Inspects the complete frame envelope and headers without decoding sample data.
    /// Uses the same policy, syntax, descriptor and allocation checks as `decodePixelFrame`.
    public func inspectFrame(_ frameData: Data, descriptor: PixelDataDescriptor,
                             frameIndex: Int) throws -> FrameInfo {
        try preparedFrame(frameData, descriptor: descriptor, frameIndex: frameIndex,
                          precisionPolicy: precisionPolicy).info
    }

    private struct ParsedJPEGLSSummary: Sendable {
        let width: Int
        let height: Int
        let componentCount: Int
        let bitsPerSample: Int
        let hasUniformSampling: Bool
        let hasNearLosslessScan: Bool
        let hasPointTransform: Bool
        let hasMappingSelector: Bool
        let hasMappingTables: Bool
        let hasColorTransform: Bool

        var recoveryFeaturesAllowed: Bool {
            !hasNearLosslessScan && !hasPointTransform && !hasMappingSelector
                && !hasMappingTables && !hasColorTransform
        }
    }

    private static func parseJPEGLSMarkerSummary(_ data: Data) throws -> ParsedJPEGLSSummary {
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> ParsedJPEGLSSummary in
            func malformed(_ message: String = "Invalid or truncated JPEG-LS header") -> DICOMError {
                .parsingFailed(message)
            }
            func word(_ offset: Int) -> Int {
                (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
            }

            guard bytes.count >= 4, bytes[0] == 0xFF else {
                throw malformed()
            }
            var cursor = 1
            while cursor < bytes.count && bytes[cursor] == 0xFF {
                cursor += 1
            }
            guard cursor < bytes.count, bytes[cursor] == 0xD8 else {
                throw malformed()
            }
            cursor += 1

            var frameBits: Int?
            var frameWidth: Int?
            var frameHeight: Int?
            var frameComponents: Int?
            var uniformSampling = true
            var extendedDimensions: (width: Int, height: Int)?
            var presetMaxValues: [Int] = []
            var scanCount = 0
            var hasNearLosslessScan = false
            var hasPointTransform = false
            var hasMappingSelector = false
            var hasMappingTables = false
            var hasColorTransform = false

            while cursor < bytes.count {
                guard bytes[cursor] == 0xFF else { throw malformed() }
                while cursor < bytes.count && bytes[cursor] == 0xFF {
                    cursor += 1
                }
                guard cursor < bytes.count else { throw malformed() }
                let marker = bytes[cursor]
                cursor += 1

                if marker == 0xD9 {
                    guard let bits = frameBits,
                          let width = frameWidth,
                          let height = frameHeight,
                          let componentCount = frameComponents,
                          width > 0, height > 0,
                          scanCount > 0 else {
                        throw malformed()
                    }
                    let maxAllowed = (1 << bits) - 1
                    for maxVal in presetMaxValues where maxVal > maxAllowed {
                        throw DICOMError.parsingFailed("JPEG-LS MAXVAL exceeds the encoded precision")
                    }
                    guard uniformSampling else {
                        throw DICOMError.parsingFailed(
                            "Decoded JPEG-LS component has sub-sampled factors; sub-sampled components are not supported"
                        )
                    }
                    return ParsedJPEGLSSummary(
                        width: width,
                        height: height,
                        componentCount: componentCount,
                        bitsPerSample: bits,
                        hasUniformSampling: uniformSampling,
                        hasNearLosslessScan: hasNearLosslessScan,
                        hasPointTransform: hasPointTransform,
                        hasMappingSelector: hasMappingSelector,
                        hasMappingTables: hasMappingTables,
                        hasColorTransform: hasColorTransform
                    )
                }

                guard bytes.count - cursor >= 2 else { throw malformed() }
                let length = word(cursor)
                guard length >= 2, length <= bytes.count - cursor else { throw malformed() }
                let payload = cursor + 2
                let end = cursor + length

                switch marker {
                case 0xF7:
                    guard frameBits == nil, length >= 8 else { throw malformed() }
                    let bits = Int(bytes[payload])
                    let codedHeight = word(payload + 1)
                    let codedWidth = word(payload + 3)
                    let count = Int(bytes[payload + 5])
                    guard (2...16).contains(bits), (1...4).contains(count), length == 8 + 3 * count else {
                        throw malformed()
                    }
                    let resolvedHeight = codedHeight == 0 ? (extendedDimensions?.height ?? 0) : codedHeight
                    let resolvedWidth = codedWidth == 0 ? (extendedDimensions?.width ?? 0) : codedWidth
                    if let ext = extendedDimensions {
                        guard ext.width == resolvedWidth, ext.height == resolvedHeight else {
                            throw malformed()
                        }
                    }
                    var firstSampling: UInt8?
                    var seenIDs = Set<UInt8>()
                    for i in 0..<count {
                        let at = payload + 6 + 3 * i
                        let cid = bytes[at]
                        let hv = bytes[at + 1]
                        let tq = bytes[at + 2]
                        guard (1...4).contains(hv >> 4), (1...4).contains(hv & 0x0F), tq == 0,
                              seenIDs.insert(cid).inserted else {
                            throw malformed()
                        }
                        if let first = firstSampling {
                            if hv != first { uniformSampling = false }
                        } else {
                            firstSampling = hv
                        }
                    }
                    frameBits = bits
                    frameWidth = resolvedWidth
                    frameHeight = resolvedHeight
                    frameComponents = count

                case 0xF8:
                    guard length >= 3 else { throw malformed() }
                    let id = bytes[payload]
                    if id == 1 {
                        guard length == 13 else { throw malformed() }
                        let maxVal = word(payload + 1)
                        presetMaxValues.append(maxVal)
                        if let bits = frameBits, maxVal > (1 << bits) - 1 {
                            throw DICOMError.parsingFailed("JPEG-LS MAXVAL exceeds the encoded precision")
                        }
                    } else if id == 2 || id == 3 {
                        hasMappingTables = true
                    } else if id == 4 {
                        guard length >= 8, scanCount == 0, extendedDimensions == nil else { throw malformed() }
                        let size = Int(bytes[payload + 1])
                        guard (2...4).contains(size), length == 4 + 2 * size else { throw malformed() }
                        func readDim(_ start: Int) throws -> Int {
                            var value: UInt32 = 0
                            for off in 0..<size {
                                value = (value << 8) | UInt32(bytes[start + off])
                            }
                            guard let exact = Int(exactly: value) else {
                                throw DICOMError.limitExceeded("JPEG-LS extended dimensions exceed addressable range")
                            }
                            return exact
                        }
                        let height = try readDim(payload + 2)
                        let width = try readDim(payload + 2 + size)
                        extendedDimensions = (width: width, height: height)
                        if let existingW = frameWidth, let existingH = frameHeight {
                            guard (existingW == 0 || existingW == width),
                                  (existingH == 0 || existingH == height) else {
                                throw malformed()
                            }
                            frameWidth = width
                            frameHeight = height
                        }
                    }

                case 0xE8:
                    if length == 7,
                       bytes[payload] == 109, bytes[payload + 1] == 114,
                       bytes[payload + 2] == 102, bytes[payload + 3] == 120 {
                        if bytes[payload + 4] != 0 {
                            hasColorTransform = true
                        }
                    }

                case 0xDA:
                    guard frameBits != nil, length >= 6 else { throw malformed() }
                    let ns = Int(bytes[payload])
                    guard (1...4).contains(ns), length == 6 + 2 * ns else { throw malformed() }
                    for i in 0..<ns {
                        let tmi = bytes[payload + 2 + 2 * i]
                        if tmi != 0 { hasMappingSelector = true }
                    }
                    let near = Int(bytes[payload + 1 + 2 * ns])
                    if near > 0 { hasNearLosslessScan = true }
                    let ahal = bytes[payload + 3 + 2 * ns]
                    if ahal != 0 { hasPointTransform = true }
                    scanCount += 1

                    var scanCursor = end
                    while scanCursor + 1 < bytes.count {
                        if bytes[scanCursor] == 0xFF {
                            let next = bytes[scanCursor + 1]
                            if next < 0x80 {
                                scanCursor += 2
                                continue
                            }
                            var markerPos = scanCursor
                            while markerPos < bytes.count && bytes[markerPos] == 0xFF {
                                markerPos += 1
                            }
                            guard markerPos < bytes.count else { throw malformed() }
                            let scanMarker = bytes[markerPos]
                            if (0xD0...0xD7).contains(scanMarker) {
                                scanCursor = markerPos + 1
                                continue
                            }
                            break
                        }
                        scanCursor += 1
                    }
                    cursor = scanCursor
                    continue

                default:
                    break
                }

                cursor = end
            }

            throw malformed()
        }
    }

    private func makeSwiftJLSResourceLimits(extraDecodedMinimum: Int = 0) throws -> SwiftJLS.ResourceLimits {
        let maxEncoded = max(1, decodingLimits.maximumEncodedBytes)
        let maxPixels = max(1, decodingLimits.maximumPixels)
        let maxDecoded = max(1, max(decodingLimits.maximumDecodedBytes, extraDecodedMinimum))
        let defaultWorkspace = 512 * 1024 * 1024
        let (sum1, over1) = maxEncoded.addingReportingOverflow(maxDecoded)
        let maxWorkspace = over1 ? Int.max : max(defaultWorkspace, sum1)
        return try SwiftJLS.ResourceLimits(
            maximumCompressedBytes: maxEncoded,
            maximumDecodedBytes: maxDecoded,
            maximumWorkspaceBytes: maxWorkspace,
            maximumPixels: maxPixels,
            deadlineSeconds: 30.0,
            maximumMemoryBytes: Int.max
        )
    }

    private func preparedFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        precisionPolicy: PrecisionPolicy
    ) throws -> (info: FrameInfo, data: Data, summary: ParsedJPEGLSSummary, inspected: SwiftJLS.ImageInfo) {
        // Reject oversized slices before rebasing can allocate a copy.
        _ = try decodingLimits.validate(frameData, descriptor: descriptor, frameIndex: frameIndex)
        let data = frameData.startIndex == 0 ? frameData : Data(frameData)
        _ = try JPEGFrameEnvelope.parse(data, jpegLS: true)
        let summary = try Self.parseJPEGLSMarkerSummary(data)

        let info = try frameInfo(
            encodedByteCount: frameData.count,
            descriptor: descriptor,
            frameIndex: frameIndex,
            precisionPolicy: precisionPolicy,
            width: summary.width,
            height: summary.height,
            componentCount: summary.componentCount,
            precision: summary.bitsPerSample,
            hasNearLosslessScan: summary.hasNearLosslessScan,
            recoveryFeaturesAllowed: summary.recoveryFeaturesAllowed
        )

        let actualDescriptor = info.descriptor
        // Preserve the intermediate sample-plane budget check during header inspection,
        // before allocating samples. Descriptor validation above bounds dimensions.
        let (pixels, pixelOverflow) = actualDescriptor.rows.multipliedReportingOverflow(by: actualDescriptor.columns)
        let (samples, sampleOverflow) = pixels.multipliedReportingOverflow(by: actualDescriptor.samplesPerPixel)
        let (planeBytes, byteOverflow) = samples.multipliedReportingOverflow(by: MemoryLayout<Int>.stride)
        guard !pixelOverflow, !sampleOverflow, !byteOverflow,
              planeBytes > 0, planeBytes <= decodingLimits.maximumDecodedBytes else {
            throw DICOMError.limitExceeded("JPEG-LS intermediate sample planes exceed decoded byte budget")
        }

        let wideComponentBytes = samples * MemoryLayout<UInt16>.stride
        let inspected: SwiftJLS.ImageInfo
        do {
            let limits = try makeSwiftJLSResourceLimits(extraDecodedMinimum: wideComponentBytes)
            let codecOptions = try SwiftJLS.CodecOptions(
                restartIntervalLines: 0,
                mappingOutputPrecision: summary.hasMappingSelector ? actualDescriptor.bitsStored : nil
            )
            let decoder = try SwiftJLS.Decoder(configuration: .init(codecOptions: codecOptions))
            inspected = try decoder.inspect(
                data,
                options: .init(
                    resourceLimits: limits,
                    copyPolicy: .requireSharedStorage,
                    metadataPolicy: .discardAncillary
                )
            )
        } catch let error as DICOMError {
            throw error
        } catch let error as SwiftJLS.CodecError {
            if error.category == .resourceLimitExceeded {
                throw DICOMError.limitExceeded("JPEG-LS inspection exceeded resource limits: \(error.message)")
            }
            throw DICOMError.parsingFailed("JPEG-LS inspection failed: \(error.message)")
        } catch {
            throw DICOMError.parsingFailed("JPEG-LS inspection failed: \(error)")
        }

        return (info, data, summary, inspected)
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

    private func makeQualifiedMonochromeLimits(maximumDecodedBytes: Int) -> QualifiedMonochromeDecoder.Limits {
        let workspaceCeiling = max(1 << 20, QualifiedMonochromeDecoder.workspaceByteCount)
        return QualifiedMonochromeDecoder.Limits(
            maximumEncodedBytes: max(1, decodingLimits.maximumEncodedBytes),
            maximumPixels: max(1, decodingLimits.maximumPixels),
            maximumDecodedBytes: max(1, maximumDecodedBytes),
            maximumDimension: 1_000_000,
            maximumWorkspaceBytes: workspaceCeiling,
            maximumMemoryBytes: Int.max,
            deadlineSeconds: 30.0
        )
    }

    /// Decode a monochrome 16-bit-container frame into explicitly admitted backing.
    /// Pixel/workspace capacities are charged before allocation.
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

    /// Decode the admitted monochrome or 3-component profile using scalar outcomes throughout the canonical path.
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
            switch JPEGFrameEnvelope.parseOutcome(encoded, jpegLS: true, cancellation: cancellation) {
            case .success: break
            case .failure(let failure): return .failure(failure)
            }
            if descriptor.samplesPerPixel == 1 && descriptor.bitsAllocated == 16 {
                let decoder = QualifiedMonochromeDecoder(
                    profile: .jlswift0101,
                    limits: makeQualifiedMonochromeLimits(maximumDecodedBytes: decodingLimits.maximumDecodedBytes)
                )
                let workspace: DICOMByteBuffer
                switch DICOMByteBuffer.admit(count: QualifiedMonochromeDecoder.workspaceByteCount,
                                             budget: budget, resource: .staging) {
                case .success(let value): workspace = value
                case .failure(let failure): return .failure(failure)
                }
                let codecCancellation = QualifiedCancellation(check: cancellation.check, context: cancellation.context)
                let inspectResult = decoder.inspect(
                    encoded, workspace: workspace.unsafeMutableBytes, cancellation: codecCancellation
                )
                let header: QualifiedMonochromeDecoder.MonochromeInfo
                switch inspectResult {
                case .success(let value): header = value
                case .failure(let failure): workspace.keepAlive(); return .failure(Self.managedFailure(failure))
                }
                let info: FrameInfo
                switch managedFrameInfoOutcome(encodedByteCount: encoded.count, descriptor: descriptor,
                    frameIndex: frameIndex, precisionPolicy: precisionPolicy, width: header.width, height: header.height,
                    componentCount: 1, precision: header.bitsPerSample, hasNearLosslessScan: header.near > 0,
                    recoveryFeaturesAllowed: header.near == 0 && header.pointTransform == 0
                        && header.mappingTableID == 0 && !header.hasMappingTables && header.colorTransformation == 0) {
                case .success(let value): info = value
                case .failure(let failure): workspace.keepAlive(); return .failure(failure)
                }
                let bytes: DICOMByteBuffer
                switch DICOMByteBuffer.admit(count: info.expectedByteCount, budget: budget, resource: .decoded) {
                case .success(let value): bytes = value
                case .failure(let failure): workspace.keepAlive(); return .failure(failure)
                }
                let samples = bytes.unsafeMutableBytes.bindMemory(to: UInt16.self)
                samples.initialize(repeating: 0)
                let decodeResult = decoder.decode(
                    encoded, into: samples, workspace: workspace.unsafeMutableBytes, cancellation: codecCancellation
                )
                workspace.keepAlive()
                let decoded: QualifiedMonochromeDecoder.MonochromeInfo
                switch decodeResult {
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

            if descriptor.samplesPerPixel == 1 && descriptor.bitsAllocated == 8 {
                let wideByteCount = descriptor.rows * descriptor.columns * 2
                let decoder = QualifiedMonochromeDecoder(
                    profile: .jlswift0101,
                    limits: makeQualifiedMonochromeLimits(
                        maximumDecodedBytes: max(decodingLimits.maximumDecodedBytes, wideByteCount)
                    )
                )
                let workspace: DICOMByteBuffer
                switch DICOMByteBuffer.admit(count: QualifiedMonochromeDecoder.workspaceByteCount,
                                             budget: budget, resource: .staging) {
                case .success(let value): workspace = value
                case .failure(let failure): return .failure(failure)
                }
                let codecCancellation = QualifiedCancellation(check: cancellation.check, context: cancellation.context)
                let inspectResult = decoder.inspect(
                    encoded, workspace: workspace.unsafeMutableBytes, cancellation: codecCancellation
                )
                let header: QualifiedMonochromeDecoder.MonochromeInfo
                switch inspectResult {
                case .success(let value): header = value
                case .failure(let failure): workspace.keepAlive(); return .failure(Self.managedFailure(failure))
                }
                let info: FrameInfo
                switch managedFrameInfoOutcome(encodedByteCount: encoded.count, descriptor: descriptor,
                    frameIndex: frameIndex, precisionPolicy: precisionPolicy, width: header.width, height: header.height,
                    componentCount: 1, precision: header.bitsPerSample, hasNearLosslessScan: header.near > 0,
                    recoveryFeaturesAllowed: false) {
                case .success(let value): info = value
                case .failure(let failure): workspace.keepAlive(); return .failure(failure)
                }
                let wideStaging: DICOMByteBuffer
                switch DICOMByteBuffer.admit(count: wideByteCount, budget: budget, resource: .staging) {
                case .success(let value): wideStaging = value
                case .failure(let failure): workspace.keepAlive(); return .failure(failure)
                }
                let samples = wideStaging.unsafeMutableBytes.bindMemory(to: UInt16.self)
                samples.initialize(repeating: 0)
                let decodeResult = decoder.decode(
                    encoded, into: samples, workspace: workspace.unsafeMutableBytes, cancellation: codecCancellation
                )
                workspace.keepAlive()
                let decoded: QualifiedMonochromeDecoder.MonochromeInfo
                switch decodeResult {
                case .success(let value): decoded = value
                case .failure(let failure): wideStaging.keepAlive(); return .failure(Self.managedFailure(failure))
                }
                guard decoded == header else {
                    wideStaging.keepAlive()
                    return .failure(DICOMManagedFailure(.codecResultMismatch))
                }
                let bytes: DICOMByteBuffer
                switch DICOMByteBuffer.admit(count: info.expectedByteCount, budget: budget, resource: .decoded) {
                case .success(let value): bytes = value
                case .failure(let failure): wideStaging.keepAlive(); return .failure(failure)
                }
                if let failure = cancellation.failure { wideStaging.keepAlive(); return .failure(failure) }
                let maxSample = UInt16((1 << info.descriptor.bitsStored) - 1)
                guard let dst8 = bytes.unsafeMutableBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    wideStaging.keepAlive()
                    return .failure(DICOMManagedFailure(.codecResultMismatch))
                }
                for index in 0..<info.expectedByteCount {
                    if (index & 0xFFFF) == 0, let failure = cancellation.failure {
                        wideStaging.keepAlive()
                        return .failure(failure)
                    }
                    let sample = samples[index]
                    guard sample <= maxSample else {
                        wideStaging.keepAlive()
                        return .failure(DICOMManagedFailure(.codecResultMismatch))
                    }
                    dst8[index] = UInt8(truncatingIfNeeded: sample)
                }
                wideStaging.keepAlive()
                if let failure = cancellation.failure { return .failure(failure) }
                return .success(ManagedDecodedPixelFrame(data: bytes, descriptor: info.descriptor,
                    sourceFrameIndex: frameIndex, diagnostic: info.diagnostic))
            }

            guard descriptor.samplesPerPixel == 3 else {
                return .failure(DICOMManagedFailure(.invalidDescriptor, 104))
            }

            let (prePixels, prePixelOverflow) = descriptor.rows.multipliedReportingOverflow(by: descriptor.columns)
            let (preSamples, preSampleOverflow) = prePixels.multipliedReportingOverflow(by: 3)
            let (planeBytes, byteOverflow) = preSamples.multipliedReportingOverflow(by: MemoryLayout<Int>.stride)
            let (stagingBytes, stOverflow) = planeBytes.addingReportingOverflow(encoded.count)
            guard !prePixelOverflow, !preSampleOverflow, !byteOverflow, !stOverflow,
                  planeBytes > 0 else {
                return .failure(DICOMManagedFailure(.limitExceeded, 2))
            }

            let info: FrameInfo
            let decodedPayload: Data
            do {
                let staging: DICOMByteBuffer
                switch DICOMByteBuffer.admit(count: stagingBytes, budget: budget, resource: .staging) {
                case .success(let value): staging = value
                case .failure(let failure): return .failure(failure)
                }
                if let failure = cancellation.failure { staging.keepAlive(); return .failure(failure) }

                let data = Data(encoded)
                let summary: ParsedJPEGLSSummary
                do {
                    summary = try Self.parseJPEGLSMarkerSummary(data)
                } catch {
                    staging.keepAlive()
                    return .failure(DICOMManagedFailure(.malformed, 106, domain: 0x0100))
                }

                switch managedFrameInfoOutcome(
                    encodedByteCount: encoded.count, descriptor: descriptor, frameIndex: frameIndex,
                    precisionPolicy: precisionPolicy, width: summary.width, height: summary.height,
                    componentCount: summary.componentCount, precision: summary.bitsPerSample,
                    hasNearLosslessScan: summary.hasNearLosslessScan,
                    recoveryFeaturesAllowed: false
                ) {
                case .success(let value): info = value
                case .failure(let failure): staging.keepAlive(); return .failure(failure)
                }

                let targetDescriptor = info.descriptor
                let wideComponentBytes = preSamples * MemoryLayout<UInt16>.stride
                let limits: SwiftJLS.ResourceLimits
                let decoder: SwiftJLS.Decoder
                let inspected: SwiftJLS.ImageInfo
                do {
                    limits = try makeSwiftJLSResourceLimits(extraDecodedMinimum: wideComponentBytes)
                    let codecOptions = try SwiftJLS.CodecOptions(
                        restartIntervalLines: 0,
                        mappingOutputPrecision: summary.hasMappingSelector ? targetDescriptor.bitsStored : nil
                    )
                    decoder = try SwiftJLS.Decoder(configuration: .init(codecOptions: codecOptions))
                    inspected = try decoder.inspect(
                        data,
                        options: .init(
                            resourceLimits: limits,
                            copyPolicy: .requireSharedStorage,
                            metadataPolicy: .discardAncillary
                        )
                    )
                } catch {
                    staging.keepAlive()
                    return .failure(DICOMManagedFailure(.malformed, 106, domain: 0x0100))
                }

                let losslessExpected = (syntaxRestriction == .lossless) || !summary.hasNearLosslessScan
                let expectedByteCount = info.expectedByteCount
                let decodeOutcome = CompressionSuiteSyncBridge.runManaged(
                    deadlineSeconds: 30.0,
                    joinGraceSeconds: 1.0,
                    domain: 0x0100,
                    cancellation: cancellation
                ) {
                    try await Self.decodeToDICOMBytes(
                        data: data,
                        decoder: decoder,
                        inspected: inspected,
                        descriptor: targetDescriptor,
                        expectedByteCount: expectedByteCount,
                        limits: limits,
                        requireExactFidelity: losslessExpected
                    )
                }
                staging.keepAlive()
                switch decodeOutcome {
                case .success(let payload): decodedPayload = payload
                case .failure(let failure): return .failure(failure)
                }
            }

            let bytes: DICOMByteBuffer
            switch DICOMByteBuffer.admit(count: info.expectedByteCount, budget: budget, resource: .decoded) {
            case .success(let value): bytes = value
            case .failure(let failure): return .failure(failure)
            }
            if let failure = cancellation.failure { return .failure(failure) }
            guard decodedPayload.count == info.expectedByteCount,
                  let dst = bytes.unsafeMutableBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return .failure(DICOMManagedFailure(.codecResultMismatch))
            }
            decodedPayload.withUnsafeBytes { src in
                if let srcBase = src.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                    dst.update(from: srcBase, count: info.expectedByteCount)
                }
            }
            bytes.keepAlive()
            if let failure = cancellation.failure { return .failure(failure) }
            return .success(ManagedDecodedPixelFrame(
                data: bytes, descriptor: info.descriptor,
                sourceFrameIndex: frameIndex, diagnostic: info.diagnostic
            ))
        }
    }

    /// Decode on the original admitted worker with scalar identity/refusal status.
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

    private static func managedFailure(_ error: QualifiedFailure) -> DICOMManagedFailure {
        if error.code == .cancelled { return DICOMManagedFailure(.cancelled) }
        // Domain 0x0100 is JPEGLS; preserve both numerical dependency operands.
        return DICOMManagedFailure(.codecFailure, Int(error.code.rawValue), error.operand0,
                                   operand3: error.operand1, domain: 0x0100)
    }

    private func decodedPixelFrame(_ frameData: Data, descriptor: PixelDataDescriptor,
                                   frameIndex: Int, precisionPolicy: PrecisionPolicy) throws -> DecodedPixelFrame {
        let (info, data, summary, inspected) = try preparedFrame(
            frameData, descriptor: descriptor, frameIndex: frameIndex, precisionPolicy: precisionPolicy
        )
        let targetDescriptor = info.descriptor
        let wideComponentBytes = targetDescriptor.rows * targetDescriptor.columns
            * targetDescriptor.samplesPerPixel * MemoryLayout<UInt16>.stride
        let limits = try makeSwiftJLSResourceLimits(extraDecodedMinimum: wideComponentBytes)
        let codecOptions = try SwiftJLS.CodecOptions(
            restartIntervalLines: 0,
            mappingOutputPrecision: summary.hasMappingSelector ? targetDescriptor.bitsStored : nil
        )
        let decoder = try SwiftJLS.Decoder(configuration: .init(codecOptions: codecOptions))
        let losslessExpected = (syntaxRestriction == .lossless) || !summary.hasNearLosslessScan
        let expectedByteCount = info.expectedByteCount

        let bytes: Data
        do {
            bytes = try CompressionSuiteSyncBridge.run(
                deadlineSeconds: 30.0,
                joinGraceSeconds: 1.0,
                codecName: "SwiftJLS"
            ) {
                try await Self.decodeToDICOMBytes(
                    data: data,
                    decoder: decoder,
                    inspected: inspected,
                    descriptor: targetDescriptor,
                    expectedByteCount: expectedByteCount,
                    limits: limits,
                    requireExactFidelity: losslessExpected
                )
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as DICOMError {
            throw error
        } catch let error as SwiftJLS.CodecError {
            if error.category == .resourceLimitExceeded {
                throw DICOMError.limitExceeded("JPEG-LS decode exceeded resource limits: \(error.message)")
            }
            throw DICOMError.parsingFailed("JPEG-LS decode failed: \(error.message)")
        } catch {
            throw DICOMError.parsingFailed("JPEG-LS decode failed: \(error)")
        }

        guard bytes.count == info.expectedByteCount else {
            throw DICOMError.parsingFailed("JPEG-LS output length mismatch")
        }
        return DecodedPixelFrame(
            data: bytes, descriptor: info.descriptor,
            sourceFrameIndex: info.sourceFrameIndex, diagnostics: info.diagnostics
        )
    }

    private static func decodeToDICOMBytes(
        data: Data,
        decoder: SwiftJLS.Decoder,
        inspected: SwiftJLS.ImageInfo,
        descriptor: PixelDataDescriptor,
        expectedByteCount: Int,
        limits: SwiftJLS.ResourceLimits,
        requireExactFidelity: Bool
    ) async throws -> Data {
        let dstDescriptor = try makeDecodeDestinationDescriptor(
            from: descriptor,
            inspected: inspected,
            limits: limits
        )
        let destination = try SwiftJLS.ImageDestination.allocate(
            descriptor: dstDescriptor,
            limits: limits
        )
        let decodeOptions = SwiftJLS.DecodeOptions(
            resourceLimits: limits,
            copyPolicy: .requireSharedStorage,
            metadataPolicy: .discardAncillary
        )
        let decoded = try await decoder.decode(data, into: destination, options: decodeOptions)
        guard decoded.report.copyEvents.isEmpty else {
            throw DICOMError.parsingFailed("JPEG-LS decode violated requireSharedStorage copy policy")
        }
        if requireExactFidelity {
            guard decoded.report.fidelity == .exactSamples else {
                throw DICOMError.parsingFailed(
                    "JPEG-LS lossless decode reported non-exact fidelity: \(decoded.report.fidelity)"
                )
            }
        }

        let storageBits = dstDescriptor.storageBits
        let meaningfulBits = dstDescriptor.meaningfulBits
        let maxSample = UInt16((1 << meaningfulBits) - 1)

        return try decoded.image.storage.withUnsafeBytes { raw in
            guard raw.count >= expectedByteCount else {
                throw DICOMError.parsingFailed("JPEG-LS decoded storage shorter than expected")
            }
            if meaningfulBits < storageBits {
                if storageBits == 8 {
                    let max8 = UInt8(truncatingIfNeeded: maxSample)
                    for i in 0..<expectedByteCount {
                        if raw[i] > max8 {
                            throw DICOMError.parsingFailed("Decoded JPEG-LS samples exceed the encoded precision")
                        }
                    }
                } else {
                    let sampleCount = expectedByteCount / 2
                    for i in 0..<sampleCount {
                        let word = UInt16(raw[i * 2]) | (UInt16(raw[i * 2 + 1]) << 8)
                        if word > maxSample {
                            throw DICOMError.parsingFailed("Decoded JPEG-LS samples exceed the encoded precision")
                        }
                    }
                }
            }
            guard let base = raw.baseAddress else {
                return Data()
            }
            return Data(bytes: base, count: expectedByteCount)
        }
    }

    private static func makeDecodeDestinationDescriptor(
        from d: PixelDataDescriptor,
        inspected: SwiftJLS.ImageInfo,
        limits: SwiftJLS.ResourceLimits
    ) throws -> SwiftJLS.ImageDescriptor {
        let width = d.columns
        let height = d.rows
        let storageBits = d.bitsAllocated <= 8 ? 8 : 16
        let bps = storageBits / 8
        let meaningfulBits = d.bitsStored
        guard (2...16).contains(meaningfulBits), meaningfulBits <= storageBits else {
            throw DICOMError.parsingFailed(
                "Decoded JPEG-LS precision \(meaningfulBits) bits is invalid for Bits Allocated \(storageBits)"
            )
        }

        let components = inspected.descriptor.components
        let colour = inspected.descriptor.colour
        guard components.count == d.samplesPerPixel else {
            throw DICOMError.parsingFailed(
                "Decoded JPEG-LS component count \(components.count) does not match samples per pixel \(d.samplesPerPixel)"
            )
        }

        let planes: [SwiftJLS.PlaneDescriptor]
        switch d.samplesPerPixel {
        case 1:
            let rowBytes = width * bps
            planes = [
                try SwiftJLS.PlaneDescriptor(
                    width: width,
                    height: height,
                    components: [0],
                    offset: 0,
                    sampleStride: bps,
                    pixelStride: bps,
                    rowBytes: rowBytes,
                    byteCount: rowBytes * height
                )
            ]
        case 3:
            if d.planarConfiguration == 1 {
                let rowBytes = width * bps
                let planeBytes = rowBytes * height
                planes = [
                    try SwiftJLS.PlaneDescriptor(
                        width: width, height: height, components: [0],
                        offset: 0, sampleStride: bps, pixelStride: bps,
                        rowBytes: rowBytes, byteCount: planeBytes
                    ),
                    try SwiftJLS.PlaneDescriptor(
                        width: width, height: height, components: [1],
                        offset: planeBytes, sampleStride: bps, pixelStride: bps,
                        rowBytes: rowBytes, byteCount: planeBytes * 2
                    ),
                    try SwiftJLS.PlaneDescriptor(
                        width: width, height: height, components: [2],
                        offset: planeBytes * 2, sampleStride: bps, pixelStride: bps,
                        rowBytes: rowBytes, byteCount: planeBytes * 3
                    )
                ]
            } else {
                let pixelStride = 3 * bps
                let rowBytes = width * pixelStride
                planes = [
                    try SwiftJLS.PlaneDescriptor(
                        width: width,
                        height: height,
                        components: [0, 1, 2],
                        offset: 0,
                        sampleStride: bps,
                        pixelStride: pixelStride,
                        rowBytes: rowBytes,
                        byteCount: rowBytes * height
                    )
                ]
            }
        default:
            throw DICOMError.parsingFailed("Unsupported JPEG-LS samplesPerPixel \(d.samplesPerPixel)")
        }

        return try SwiftJLS.ImageDescriptor(
            width: width,
            height: height,
            sampleType: .unsignedInteger,
            storageBits: storageBits,
            meaningfulBits: meaningfulBits,
            byteOrder: .littleEndian,
            components: components,
            colour: colour,
            alpha: .absent,
            planes: planes,
            limits: limits
        )
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

    /// Encodes a single frame to JPEG-LS format.
    public func encodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        configuration: CompressionConfiguration
    ) throws -> Data {
        try encodeFrame(
            frameData,
            descriptor: descriptor,
            frameIndex: frameIndex,
            configuration: configuration,
            interleaveMode: .automatic
        )
    }

    /// Encodes a single frame to JPEG-LS format with explicit scan interleave selection (`ILV`).
    public func encodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        configuration: CompressionConfiguration,
        interleaveMode: InterleaveMode
    ) throws -> Data {
        let bitsPerSample = max(2, min(16, descriptor.bitsStored))
        let near = nearParameter(for: configuration, descriptor: descriptor, bitsPerSample: bitsPerSample)
        let swiftInterleave: SwiftJLS.CodecOptions.InterleaveMode
        switch interleaveMode {
        case .automatic:
            swiftInterleave = descriptor.samplesPerPixel > 1 ? .sample : .none
        case .none:
            swiftInterleave = .none
        case .line:
            swiftInterleave = .line
        case .sample:
            swiftInterleave = .sample
        }

        do {
            let limits = try makeEncodeResourceLimits(descriptor: descriptor)
            let image = try Self.buildEncodeImage(
                from: frameData,
                descriptor: descriptor,
                bitsPerSample: bitsPerSample,
                limits: limits
            )
            let mode: SwiftJLS.CompressionMode = near == 0
                ? .lossless
                : .nearLossless(maximumAbsoluteError: near)
            let codecOptions = try SwiftJLS.CodecOptions(
                restartIntervalLines: 0,
                interleaveMode: swiftInterleave,
                colourTransform: .none
            )
            let encoderConfig = try SwiftJLS.EncoderConfiguration(mode: mode, codecOptions: codecOptions)
            let encoder = try SwiftJLS.Encoder(configuration: encoderConfig)
            let encodeOptions = SwiftJLS.EncodeOptions(
                resourceLimits: limits,
                copyPolicy: .requireSharedStorage,
                metadataPolicy: .discardAncillary
            )
            let encoded = try CompressionSuiteSyncBridge.run(
                deadlineSeconds: 30.0,
                joinGraceSeconds: 1.0,
                codecName: "SwiftJLS"
            ) {
                try await encoder.encode(image, options: encodeOptions)
            }
            guard encoded.report.copyEvents.isEmpty else {
                throw DICOMError.parsingFailed("JPEG-LS encode violated requireSharedStorage copy policy")
            }
            if near == 0 {
                guard encoded.report.fidelity == .exactSamples else {
                    throw DICOMError.parsingFailed(
                        "JPEG-LS lossless encode reported non-exact fidelity: \(encoded.report.fidelity)"
                    )
                }
            }
            return encoded.data
        } catch let error as CancellationError {
            throw error
        } catch let error as DICOMError {
            throw error
        } catch let error as SwiftJLS.CodecError {
            if error.category == .resourceLimitExceeded {
                throw DICOMError.limitExceeded("JPEG-LS encode exceeded resource limits: \(error.message)")
            }
            throw DICOMError.parsingFailed("JPEG-LS encode failed: \(error.message)")
        } catch {
            throw DICOMError.parsingFailed("JPEG-LS encode failed: \(error)")
        }
    }

    private func makeEncodeResourceLimits(descriptor: PixelDataDescriptor) throws -> SwiftJLS.ResourceLimits {
        let (pixels, pOver) = descriptor.rows.multipliedReportingOverflow(by: descriptor.columns)
        let (samples, sOver) = pixels.multipliedReportingOverflow(by: max(1, descriptor.samplesPerPixel))
        let (decodedBytes, bOver) = samples.multipliedReportingOverflow(by: bytesPerSample(descriptor))
        guard !pOver, !sOver, !bOver, pixels > 0, decodedBytes > 0 else {
            throw DICOMError.parsingFailed("JPEG-LS encode: invalid frame dimensions")
        }
        let maxPixels = max(64_000_000, pixels)
        let maxDecoded = max(512 * 1024 * 1024, decodedBytes)
        let (worstCompressed, cOver) = samples.multipliedReportingOverflow(by: 12)
        let maxCompressed = cOver ? Int.max : max(256 * 1024 * 1024, worstCompressed + 4096)
        return try SwiftJLS.ResourceLimits(
            maximumCompressedBytes: maxCompressed,
            maximumDecodedBytes: maxDecoded,
            maximumWorkspaceBytes: Int.max / 4,
            maximumPixels: maxPixels,
            deadlineSeconds: 30.0,
            maximumMemoryBytes: Int.max
        )
    }

    private static func buildEncodeImage(
        from frameData: Data,
        descriptor: PixelDataDescriptor,
        bitsPerSample: Int,
        limits: SwiftJLS.ResourceLimits
    ) throws -> SwiftJLS.Image {
        let width = descriptor.columns
        let height = descriptor.rows
        let samples = descriptor.samplesPerPixel
        let storageBits = descriptor.bitsAllocated <= 8 ? 8 : 16
        let bps = storageBits / 8
        guard width > 0, height > 0, (2...16).contains(bitsPerSample), bitsPerSample <= storageBits else {
            throw DICOMError.parsingFailed("JPEG-LS encode: invalid frame geometry or precision")
        }

        let components: [SwiftJLS.ComponentRole]
        let colour: SwiftJLS.ColourInterpretation
        let planes: [SwiftJLS.PlaneDescriptor]
        switch samples {
        case 1:
            components = [.grey]
            colour = .greyscale
            let rowBytes = width * bps
            planes = [
                try SwiftJLS.PlaneDescriptor(
                    width: width,
                    height: height,
                    components: [0],
                    offset: 0,
                    sampleStride: bps,
                    pixelStride: bps,
                    rowBytes: rowBytes,
                    byteCount: rowBytes * height
                )
            ]
        case 3:
            // Use durable uninterpreted component IDs (1, 2, 3) with `.unknown` colour so
            // SwiftJLS emits pure ISO/IEC 14495-1 `SOI + SOF55 + SOS + ... + EOI` without a
            // SPIFF APP8 wrapper (whose directory-end embeds an inner `FF D8` rejected by DICOM
            // single-frame JPEG-LS encapsulation rules and DCMTK/CharLS).
            components = [
                .uninterpreted("JPEG-LS:1"),
                .uninterpreted("JPEG-LS:2"),
                .uninterpreted("JPEG-LS:3")
            ]
            colour = .unknown
            if descriptor.planarConfiguration == 1 {
                let rowBytes = width * bps
                let planeBytes = rowBytes * height
                planes = [
                    try SwiftJLS.PlaneDescriptor(
                        width: width, height: height, components: [0],
                        offset: 0, sampleStride: bps, pixelStride: bps,
                        rowBytes: rowBytes, byteCount: planeBytes
                    ),
                    try SwiftJLS.PlaneDescriptor(
                        width: width, height: height, components: [1],
                        offset: planeBytes, sampleStride: bps, pixelStride: bps,
                        rowBytes: rowBytes, byteCount: planeBytes * 2
                    ),
                    try SwiftJLS.PlaneDescriptor(
                        width: width, height: height, components: [2],
                        offset: planeBytes * 2, sampleStride: bps, pixelStride: bps,
                        rowBytes: rowBytes, byteCount: planeBytes * 3
                    )
                ]
            } else {
                let pixelStride = 3 * bps
                let rowBytes = width * pixelStride
                planes = [
                    try SwiftJLS.PlaneDescriptor(
                        width: width,
                        height: height,
                        components: [0, 1, 2],
                        offset: 0,
                        sampleStride: bps,
                        pixelStride: pixelStride,
                        rowBytes: rowBytes,
                        byteCount: rowBytes * height
                    )
                ]
            }
        default:
            throw DICOMError.parsingFailed("JPEG-LS encode: unsupported samplesPerPixel \(samples)")
        }

        let swiftDescriptor = try SwiftJLS.ImageDescriptor(
            width: width,
            height: height,
            sampleType: .unsignedInteger,
            storageBits: storageBits,
            meaningfulBits: bitsPerSample,
            byteOrder: .littleEndian,
            components: components,
            colour: colour,
            alpha: .absent,
            planes: planes,
            limits: limits
        )

        let destination = try SwiftJLS.ImageDestination.allocate(
            descriptor: swiftDescriptor,
            limits: limits
        )
        let requiredBytes = swiftDescriptor.requiredByteCount
        let needsSignedSubwordMask = descriptor.isSigned && bitsPerSample < storageBits

        return try destination.write { dstRaw in
            guard let dst = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            let copyCount = min(frameData.count, requiredBytes)
            frameData.withUnsafeBytes { srcRaw in
                if let src = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self), copyCount > 0 {
                    dst.update(from: src, count: copyCount)
                }
            }
            if needsSignedSubwordMask {
                let totalCells = requiredBytes / bps
                let storedMask = UInt16((1 << bitsPerSample) - 1)
                let signBit = UInt16(1 << (bitsPerSample - 1))
                let containerMask: UInt16 = storageBits == 8 ? 0x00FF : 0xFFFF
                let upperMask = containerMask ^ storedMask
                for i in 0..<totalCells {
                    if bps == 1 {
                        let word = UInt16(dst[i])
                        let upper = word & upperMask
                        guard upper == 0 || (upper == upperMask && (word & signBit) != 0) else {
                            throw DICOMError.parsingFailed("Signed 8-bit sample exceeds \(bitsPerSample)-bit precision")
                        }
                        dst[i] = UInt8(truncatingIfNeeded: word & storedMask)
                    } else {
                        let word = UInt16(dst[i * 2]) | (UInt16(dst[i * 2 + 1]) << 8)
                        let upper = word & upperMask
                        guard upper == 0 || (upper == upperMask && (word & signBit) != 0) else {
                            throw DICOMError.parsingFailed("Signed 16-bit sample exceeds \(bitsPerSample)-bit precision")
                        }
                        let masked = word & storedMask
                        dst[i * 2] = UInt8(masked & 0xFF)
                        dst[i * 2 + 1] = UInt8((masked >> 8) & 0xFF)
                    }
                }
            }
        }
    }

    // MARK: - NEAR parameter

    /// Derives the JPEG-LS NEAR value from a DICOM compression configuration.
    /// Lossless (or lossless-preferring) configurations map to NEAR = 0.
    private func nearParameter(
        for configuration: CompressionConfiguration,
        descriptor: PixelDataDescriptor,
        bitsPerSample: Int
    ) -> Int {
        if configuration.preferLossless || configuration.quality.isLossless {
            return 0
        }
        let maxVal = descriptor.bitsAllocated == 8 ? 255 : (1 << descriptor.bitsStored) - 1
        let scaled = Int(Double(maxVal) * (1.0 - configuration.quality.value) * 0.1)
        let precisionNearCap = min(Self.maxNear, max(1, ((1 << bitsPerSample) - 1) / 2))
        return min(precisionNearCap, max(0, scaled))
    }

    /// Largest NEAR value JPEG-LS permits in an 8-bit SOS field (ITU-T T.87 C.2.3).
    private static let maxNear = 255

    private func bytesPerSample(_ descriptor: PixelDataDescriptor) -> Int {
        descriptor.bitsAllocated <= 8 ? 1 : 2
    }
}
