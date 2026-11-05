import Foundation
import DICOMCore
import SwiftJ2K

/// OS 26 scalar 2D JPEG 2000 Part 1 and HTJ2K (Part 15) DICOM codec backed by `SwiftJ2K`.
///
/// Executes exclusively on `SwiftJ2K`'s verified `.scalarCPU` backend (`ExecutionPolicy.required(.scalarCPU)`),
/// preserving exact sample values, signedness, and bit depth without implicit scaling or pointer escapes.
public struct SwiftJ2KDICOMCodec: ImageCodec, ImageEncoder, DecodeBackendConfigurableCodec, Sendable {
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
    }

    public func withDecodeBackend(_ decodeBackend: CodecBackend?) -> any ImageCodec {
        SwiftJ2KDICOMCodec(
            encodingTransferSyntaxUID: encodingTransferSyntaxUID,
            decodingTransferSyntaxUID: decodingTransferSyntaxUID,
            decodeBackend: decodeBackend,
            options: options
        )
    }

    // MARK: - Pre-Execution Capability Predicates

    /// This first OS 26 integration slice executes on `.scalarCPU` only; explicit `.metal` or `.accelerate`
    /// forced backend requests are refused before execution rather than mislabelled.
    public static func supportsBackend(_ backend: CodecBackend?) -> Bool {
        guard let backend else { return true }
        return backend == .scalar
    }

    public static func supportsDecodeProfile(
        transferSyntaxUID: String?,
        descriptor: PixelDataDescriptor?,
        decodeBackend: CodecBackend?,
        options: SwiftJ2KProviderOptions = .default
    ) -> Bool {
        guard supportsBackend(decodeBackend) else { return false }
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
        guard supportsBackend(configuration.forcedBackend) else { return false }
        if let reason = J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: transferSyntaxUID) {
            _ = reason
            return false
        }
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

        let intent = J2KRoutePlanner.resolveIntent(uid: transferSyntaxUID, configuration: configuration)
        let family = J2KRoutePlanner.compressionType(forUID: transferSyntaxUID)

        // SwiftJ2K 76850bc supports lossless HTJ2K (Part 15) only; refuse lossy .203 before execution.
        if family == .htj2k && !intent.isLossless {
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
        default:
            return false
        }
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
    }

    struct PreparedEncode: Sendable {
        let image: Image
        let encoderConfiguration: EncoderConfiguration
        let transferSyntaxUID: String
        let isLossless: Bool
    }

    static func outputDescriptor(for descriptor: PixelDataDescriptor) -> PixelDataDescriptor {
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

    private func prepareDecode(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int
    ) throws -> PreparedDecode {
        guard Self.supportsBackend(decodeBackend) else {
            throw DICOMError.unsupportedTransferSyntax(
                "SwiftJ2K scalar OS 26 provider does not support forced decode backend '\(decodeBackend?.rawValue ?? "unknown")'"
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
        guard frameIndex >= 0, frameIndex < descriptor.numberOfFrames else {
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

        let codestream = Self.stripTrailingEvenPadByteIfPresent(frameData)
        if let part2Reason = J2KRoutePlanner.unsupportedDecodeReason(frameData: codestream) {
            throw DICOMError.unsupportedTransferSyntax(part2Reason)
        }
        guard let header = J2KCodestreamInspector.imageHeader(in: codestream) else {
            throw DICOMError.parsingFailed("Malformed JPEG 2000 codestream: missing valid SOC/SIZ header")
        }
        guard header.width == descriptor.columns, header.height == descriptor.rows else {
            throw DICOMError.parsingFailed(
                "JPEG 2000 SIZ dimensions (\(header.width)x\(header.height)) do not match DICOM descriptor (\(descriptor.columns)x\(descriptor.rows))"
            )
        }
        guard header.components.count == descriptor.samplesPerPixel else {
            throw DICOMError.parsingFailed(
                "JPEG 2000 component count (\(header.components.count)) does not match SamplesPerPixel (\(descriptor.samplesPerPixel))"
            )
        }
        for comp in header.components {
            guard comp.bitDepth == descriptor.bitsStored,
                  comp.isSigned == descriptor.isSigned,
                  comp.subsamplingX == 1,
                  comp.subsamplingY == 1 else {
                throw DICOMError.parsingFailed(
                    "JPEG 2000 component header (bitDepth=\(comp.bitDepth), signed=\(comp.isSigned), subsampling=\(comp.subsamplingX)x\(comp.subsamplingY)) conflicts with DICOM descriptor"
                )
            }
        }

        let isLosslessOnly = decodingTransferSyntaxUID.map(Self.losslessOnlyTransferSyntaxes.contains) ?? false
        if isLosslessOnly, J2KCodestreamInspector.usesIrreversibleWavelet(in: codestream) {
            throw DICOMError.parsingFailed(
                "JPEG 2000 codestream selects the irreversible 9/7 wavelet under lossless-only transfer syntax \(decodingTransferSyntaxUID ?? "")"
            )
        }

        if let uid = decodingTransferSyntaxUID {
            let isHTSyntax = uid == TransferSyntax.htj2kLossless.uid
                || uid == TransferSyntax.htj2kRPCLLossless.uid
                || uid == TransferSyntax.htj2kLossy.uid
            let isPart1Syntax = uid == TransferSyntax.jpeg2000Lossless.uid
                || uid == TransferSyntax.jpeg2000.uid
            if isHTSyntax && !header.hasCAPMarker {
                throw DICOMError.parsingFailed("HTJ2K transfer syntax \(uid) requires an ISO/IEC 15444-15 CAP marker")
            }
            if isPart1Syntax && header.hasCAPMarker {
                throw DICOMError.parsingFailed("Part 1 JPEG 2000 transfer syntax \(uid) must not carry an HTJ2K CAP marker")
            }
            if uid == TransferSyntax.htj2kRPCLLossless.uid {
                let violations = J2KCodestreamInspector.htj2kRPCLViolations(
                    in: codestream,
                    rows: descriptor.rows,
                    columns: descriptor.columns
                )
                if !violations.isEmpty {
                    throw DICOMError.parsingFailed(
                        "HTJ2K RPCL Lossless (.202) violation: \(violations.joined(separator: "; "))"
                    )
                }
            }
        }

        let swiftDescriptor: ImageDescriptor
        do {
            swiftDescriptor = try Self.makeSwiftImageDescriptor(
                from: descriptor,
                limits: options.resourceLimits
            )
        } catch {
            throw SwiftJ2KSyncBridge.translateError(error)
        }

        return PreparedDecode(
            codestream: codestream,
            swiftDescriptor: swiftDescriptor,
            expectedFrameBytes: geometry.frameBytes,
            transferSyntaxUID: decodingTransferSyntaxUID,
            isLosslessOnly: isLosslessOnly
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
        let decodeOptions = DecodeOptions(
            resourceLimits: options.resourceLimits,
            executionPolicy: .required(.scalarCPU),
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
        guard decoded.report.backend == .scalarCPU else {
            throw DICOMError.parsingFailed("Unexpected non-scalar SwiftJ2K backend reported in scalar provider")
        }
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
        if let reason = J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: encodingTransferSyntaxUID) {
            throw DICOMError.unsupportedTransferSyntax(reason)
        }
        guard Self.supportsBackend(configuration.forcedBackend) else {
            throw DICOMError.unsupportedTransferSyntax(
                "SwiftJ2K scalar OS 26 provider does not support forced encode backend '\(configuration.forcedBackend?.rawValue ?? "unknown")'"
            )
        }
        let targetUID = encodingTransferSyntaxUID ?? TransferSyntax.jpeg2000Lossless.uid
        guard Self.supportedEncodingTransferSyntaxes.contains(targetUID) else {
            throw DICOMError.unsupportedTransferSyntax("Unsupported JPEG 2000 encoding transfer syntax: \(targetUID)")
        }

        let intent = J2KRoutePlanner.resolveIntent(uid: targetUID, configuration: configuration)
        let family = J2KRoutePlanner.compressionType(forUID: targetUID)
        if family == .htj2k && !intent.isLossless {
            throw DICOMError.unsupportedTransferSyntax(
                "SwiftJ2K 76850bc supports lossless HTJ2K encoding only; lossy HTJ2K (\(targetUID)) is not supported"
            )
        }
        guard frameIndex >= 0, frameIndex < descriptor.numberOfFrames else {
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
            let blockCoding: CodecOptions.BlockCoding = (family == .htj2k) ? .htj2k : .part1
            let wavelet: CodecOptions.WaveletTransform = isLossless ? .reversible53 : .irreversible97
            let colourTransform: CodecOptions.ColourTransform
            if descriptor.samplesPerPixel == 3 {
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
                containerFormat: .codestream
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
            isLossless: intent.isLossless
        )
    }

    private static func executeEncode(
        prepared: PreparedEncode,
        options: SwiftJ2KProviderOptions
    ) async throws -> EncodedImage {
        let encoder = try Encoder(configuration: prepared.encoderConfiguration)
        let encodeOptions = EncodeOptions(
            resourceLimits: options.resourceLimits,
            executionPolicy: .required(.scalarCPU),
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
        guard encoded.report.backend == .scalarCPU else {
            throw DICOMError.parsingFailed("Unexpected non-scalar SwiftJ2K backend reported in scalar provider")
        }
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
