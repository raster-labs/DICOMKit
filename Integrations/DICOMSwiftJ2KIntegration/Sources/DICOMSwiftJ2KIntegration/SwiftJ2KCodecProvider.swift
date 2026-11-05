import Foundation
import DICOMCore
import SwiftJ2K

/// Lossless compressed-domain `J2K <-> HTJ2K` transcoder backed by `SwiftJ2K.Transcoder`.
///
/// `SwiftJ2K.Transcoder` transcodes single-component unsigned `1...16`-bit reversible codestreams
/// directly in the wavelet coefficient domain with `pixelAllocationCount == 0`. Profiles outside
/// that envelope (signed pixel data, 3-component RGB, or RPCL `.202` target) return `false` from
/// `canTranscode` before execution so `TransferSyntaxConverter` routes them through verified
/// pixel decode and encode.
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
        let validPair = (Self.part1UIDs.contains(sourceTransferSyntaxUID) && Self.htj2kTargetUIDs.contains(targetTransferSyntaxUID))
            || (Self.htj2kSourceUIDs.contains(sourceTransferSyntaxUID) && Self.part1UIDs.contains(targetTransferSyntaxUID))
        guard validPair, let descriptor else {
            return false
        }
        guard SwiftJ2KDICOMCodec.validateCommonGeometry(descriptor, options: options) != nil else {
            return false
        }
        return descriptor.samplesPerPixel == 1
            && !descriptor.isSigned
            && (descriptor.photometricInterpretation == .monochrome1
                || descriptor.photometricInterpretation == .monochrome2)
    }

    public func transcodeCodestream(
        _ codestream: Data,
        from sourceTransferSyntaxUID: String,
        to targetTransferSyntaxUID: String,
        descriptor: PixelDataDescriptor?
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
        if let part2Reason = J2KRoutePlanner.unsupportedDecodeReason(frameData: cleaned) {
            throw DICOMError.unsupportedTransferSyntax(part2Reason)
        }
        guard let header = J2KCodestreamInspector.imageHeader(in: cleaned) else {
            throw DICOMError.parsingFailed("Malformed JPEG 2000 codestream in compressed-domain transcode")
        }
        guard header.width == descriptor.columns,
              header.height == descriptor.rows,
              header.components.count == 1,
              let comp = header.components.first,
              comp.bitDepth == descriptor.bitsStored,
              !comp.isSigned,
              comp.subsamplingX == 1,
              comp.subsamplingY == 1 else {
            throw DICOMError.parsingFailed("JPEG 2000 codestream SIZ header conflicts with DICOM descriptor during transcode")
        }

        let sourceIsHT = Self.htj2kSourceUIDs.contains(sourceTransferSyntaxUID)
        if sourceIsHT && !header.hasCAPMarker {
            throw DICOMError.parsingFailed("HTJ2K source transfer syntax \(sourceTransferSyntaxUID) lacks CAP marker")
        }
        if !sourceIsHT && header.hasCAPMarker {
            throw DICOMError.parsingFailed("Part 1 JPEG 2000 source transfer syntax \(sourceTransferSyntaxUID) carries unexpected HTJ2K CAP marker")
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
        let transcoded = try SwiftJ2KSyncBridge.run(options: options) { [options] in
            let transcoder = try Transcoder()
            let transcodeOptions = TranscodeOptions(
                resourceLimits: options.resourceLimits,
                executionPolicy: .required(.scalarCPU),
                copyPolicy: .requireSharedStorage,
                metadataPolicy: .preserve
            )
            return try await transcoder.transcode(cleaned, to: target, options: transcodeOptions)
        }

        guard transcoded.report.backend == .scalarCPU,
              transcoded.report.fidelity == .exactSamples,
              transcoded.report.pixelAllocationCount == 0 else {
            throw DICOMError.parsingFailed(
                "SwiftJ2K transcoder report violated scalar zero-pixel-allocation contract: \(transcoded.report)"
            )
        }

        options.telemetryHandler?(SwiftJ2KOperationRecord(
            kind: .transcode,
            transferSyntaxUID: sourceTransferSyntaxUID,
            targetTransferSyntaxUID: targetTransferSyntaxUID,
            frameIndex: 0,
            report: transcoded.report
        ))

        return transcoded.data
    }
}
