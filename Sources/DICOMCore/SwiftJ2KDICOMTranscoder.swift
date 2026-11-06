import Foundation
import SwiftJ2K

/// Lossless compressed-domain `J2K <-> HTJ2K` transcoder backed by `SwiftJ2K.Transcoder`.
///
/// `SwiftJ2K.Transcoder` transcodes lossless reversible 5/3 codestreams (1-component unsigned or canonical
/// signed monochrome, and 3-component lossless `RGB` / `YBR_RCT`) directly in the wavelet coefficient domain
/// with `pixelAllocationCount == 0`. Profiles outside that envelope (such as Part 2 MCT `.92`/`.93` or RPCL
/// `.202` targets) return `false` from `canTranscode` before execution so `TransferSyntaxConverter` routes
/// them through verified pixel decode and encode.
public struct SwiftJ2KDICOMTranscoder: J2KCompressedDomainTranscoder, Sendable {
    public let providerID: CodecProviderID = .swiftJ2K
    public let options: SwiftJ2KProviderOptions

    private static let part1UIDs: Set<String> = [
        TransferSyntax.jpeg2000Lossless.uid,
        TransferSyntax.jpeg2000.uid
    ]

    private static let htj2kSourceUIDs: Set<String> = [
        TransferSyntax.htj2kLossless.uid,
        TransferSyntax.htj2kRPCLLossless.uid,
        TransferSyntax.htj2kLossy.uid
    ]

    private static let htj2kTargetUIDs: Set<String> = [
        TransferSyntax.htj2kLossless.uid,
        TransferSyntax.htj2kLossy.uid
    ]

    public init(options: SwiftJ2KProviderOptions = .default) {
        self.options = options
    }

    public func canTranscode(
        from sourceTransferSyntaxUID: String,
        to targetTransferSyntaxUID: String,
        descriptor: PixelDataDescriptor?
    ) -> Bool {
        guard SwiftJ2KDICOMCodec.supportsBackend(options.defaultBackend) else {
            return false
        }
        // Part 1 EBCOT target block coding has CPU scalar/SIMD backends only; if the caller forced
        // Metal GPU at the provider level and the target is Part 1, route through pixel decode/encode
        // so Metal wavelet kernels execute truthfully on both halves rather than mislabelling CPU SIMD.
        if options.defaultBackend == .metal && !Self.htj2kTargetUIDs.contains(targetTransferSyntaxUID) {
            return false
        }
        let validPair = (Self.part1UIDs.contains(sourceTransferSyntaxUID) && Self.htj2kTargetUIDs.contains(targetTransferSyntaxUID))
            || (Self.htj2kSourceUIDs.contains(sourceTransferSyntaxUID) && Self.part1UIDs.contains(targetTransferSyntaxUID))
        guard validPair, let descriptor else {
            return false
        }
        guard SwiftJ2KDICOMCodec.validateCommonGeometry(descriptor, options: options) != nil else {
            return false
        }
        switch descriptor.samplesPerPixel {
        case 1:
            return descriptor.photometricInterpretation == .monochrome1
                || descriptor.photometricInterpretation == .monochrome2
        case 3:
            return descriptor.planarConfiguration == 0
                && (descriptor.photometricInterpretation == .rgb
                    || descriptor.photometricInterpretation == .ybrRCT)
        default:
            return false
        }
    }

    public func transcodeCodestream(
        _ codestream: Data,
        from sourceTransferSyntaxUID: String,
        to targetTransferSyntaxUID: String,
        descriptor: PixelDataDescriptor?
    ) throws -> Data {
        try transcodeCodestream(
            codestream,
            from: sourceTransferSyntaxUID,
            to: targetTransferSyntaxUID,
            descriptor: descriptor,
            frameIndex: 0
        )
    }

    public func transcodeCodestream(
        _ codestream: Data,
        from sourceTransferSyntaxUID: String,
        to targetTransferSyntaxUID: String,
        descriptor: PixelDataDescriptor?,
        frameIndex: Int
    ) throws -> Data {
        guard canTranscode(from: sourceTransferSyntaxUID, to: targetTransferSyntaxUID, descriptor: descriptor),
              let descriptor else {
            throw DICOMError.unsupportedTransferSyntax(
                "SwiftJ2K compressed-domain transcoder does not support \(sourceTransferSyntaxUID) -> \(targetTransferSyntaxUID) for the given descriptor"
            )
        }
        guard !codestream.isEmpty else {
            throw DICOMError.parsingFailed("Empty JPEG 2000 codestream for compressed-domain transcoding")
        }
        guard codestream.count <= options.decodingLimits.maximumEncodedBytes,
              codestream.count <= options.resourceLimits.maximumCompressedBytes else {
            throw DICOMError.limitExceeded(
                "Compressed JPEG 2000 frame (\(codestream.count) bytes) exceeds transcode input byte budget"
            )
        }

        let cleaned = SwiftJ2KDICOMCodec.stripTrailingEvenPadByteIfPresent(codestream)
        if J2KCodestreamInspector.containsPart2MultiComponentTransform(in: cleaned) {
            throw DICOMError.unsupportedTransferSyntax(
                "Part 1 <-> HTJ2K compressed-domain transcoding does not accept Part 2 MCT markers"
            )
        }
        guard let header = J2KCodestreamInspector.imageHeader(in: cleaned),
              header.cbdComponents == nil else {
            throw DICOMError.parsingFailed("Malformed JPEG 2000 codestream in compressed-domain transcode")
        }
        guard header.width == descriptor.columns,
              header.height == descriptor.rows,
              header.components.count == descriptor.samplesPerPixel else {
            throw DICOMError.parsingFailed("JPEG 2000 codestream SIZ header conflicts with DICOM descriptor during transcode")
        }
        for comp in header.components {
            guard comp.bitDepth == descriptor.bitsStored,
                  comp.isSigned == descriptor.isSigned,
                  comp.subsamplingX == 1,
                  comp.subsamplingY == 1 else {
                throw DICOMError.parsingFailed(
                    "JPEG 2000 component header (bitDepth=\(comp.bitDepth), signed=\(comp.isSigned), subsampling=\(comp.subsamplingX)x\(comp.subsamplingY)) conflicts with DICOM descriptor during transcode"
                )
            }
        }

        let sourceIsHT = Self.htj2kSourceUIDs.contains(sourceTransferSyntaxUID)
        if sourceIsHT && !header.hasPart15CAPMarker {
            throw DICOMError.parsingFailed("HTJ2K source transfer syntax \(sourceTransferSyntaxUID) lacks Part 15 CAP marker")
        }
        if !sourceIsHT && header.hasCAPMarker {
            throw DICOMError.parsingFailed("Part 1 JPEG 2000 source transfer syntax \(sourceTransferSyntaxUID) carries unexpected CAP marker")
        }
        if sourceTransferSyntaxUID == TransferSyntax.htj2kRPCLLossless.uid {
            let violations = J2KCodestreamInspector.htj2kRPCLViolations(
                in: cleaned,
                rows: descriptor.rows,
                columns: descriptor.columns
            )
            if !violations.isEmpty {
                throw DICOMError.parsingFailed(
                    "HTJ2K RPCL Lossless (.202) source violation: \(violations.joined(separator: "; "))"
                )
            }
        }
        if J2KCodestreamInspector.usesIrreversibleWavelet(in: cleaned) {
            throw DICOMError.parsingFailed(
                "Compressed-domain lossless transcoding refuses irreversible 9/7 codestream under \(sourceTransferSyntaxUID)"
            )
        }

        let target: TranscodeTarget = Self.htj2kTargetUIDs.contains(targetTransferSyntaxUID) ? .htj2k : .jpeg2000
        let execution = SwiftJ2KDICOMCodec.resolveExecution(for: options.defaultBackend)
        let transcoded = try SwiftJ2KSyncBridge.run(options: options) { [options] in
            let transcoder = try Transcoder()
            let transcodeOptions = TranscodeOptions(
                resourceLimits: options.resourceLimits,
                executionPolicy: execution.policy,
                acceleratedEnginePreference: execution.enginePreference,
                copyPolicy: .requireSharedStorage,
                metadataPolicy: .preserve
            )
            return try await transcoder.transcode(cleaned, to: target, options: transcodeOptions)
        }

        try SwiftJ2KDICOMCodec.verifyExecutedBackend(report: transcoded.report, requested: options.defaultBackend)
        guard transcoded.report.fidelity == .exactSamples,
              transcoded.report.pixelAllocationCount == 0 else {
            throw DICOMError.parsingFailed(
                "SwiftJ2K transcoder report violated lossless zero-pixel-allocation contract: \(transcoded.report)"
            )
        }

        options.telemetryHandler?(SwiftJ2KOperationRecord(
            kind: .transcode,
            transferSyntaxUID: sourceTransferSyntaxUID,
            targetTransferSyntaxUID: targetTransferSyntaxUID,
            frameIndex: frameIndex,
            report: transcoded.report
        ))

        return transcoded.data
    }
}
