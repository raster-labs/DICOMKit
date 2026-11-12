import Foundation
import Synchronization
import SwiftRLE

/// RLE Lossless codec backed by `SwiftRLE` (`1.2.840.10008.1.2.5`).
///
/// Delegates DICOM PS3.5 Annex G frame encoding/decoding and PackBits segment coding to
/// `SwiftRLE` with shared-storage zero-copy descriptors (`copyPolicy: .requireSharedStorage`)
/// and `Fidelity.exactSamples` verification while preserving `DICOMCore`'s public `ImageCodec`,
/// `ImageEncoder`, caller-owned destination buffer, and `DICOMAllocationBudget` managed APIs.
///
/// Reference: DICOM PS3.5 Annex G - RLE Transfer Syntax
///
/// NEMA-verified: 2026a, checked 2026-09-25 — byte-segment order (most significant byte of
/// the Composite Pixel Code first, G.2), the 64-byte header with up to 15 segment offsets
/// relative to the header (G.5), the decoder loop (G.3.2) and the encoder packet rules
/// (replicate 2–128, literal 1–128, -128 unused, G.3.1) match PS3.5 2026a.
public struct RLECodec: ImageCodec, ImageEncoder, Sendable {
    public static let engineName = "SwiftRLE"
    public static let engineVersion = "1.0.2"

    /// Supported RLE transfer syntax
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.rleLossless.uid  // 1.2.840.10008.1.2.5
    ]

    /// Supported RLE transfer syntax for encoding (RLE Lossless only)
    public static let supportedEncodingTransferSyntaxes: [String] = [
        TransferSyntax.rleLossless.uid  // 1.2.840.10008.1.2.5
    ]

    private let decodingLimits: PixelDecodeLimits

    public init(decodingLimits: PixelDecodeLimits = .default) {
        self.decodingLimits = decodingLimits
    }

    // MARK: - Managed Budget-Accounted Decoding

    /// Decode an RLE-compressed frame into explicitly admitted backing.
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
            frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, execution: execution, cancellation: cancellation
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
            frameData, descriptor: descriptor, frameIndex: frameIndex,
            budget: budget, cancellation: cancellation
        )
    }

    /// Decode an RLE frame using scalar outcomes and budget-owned `.staging` / `.decoded` backing,
    /// delegating decompression to `SwiftRLE` with `copyPolicy: .requireSharedStorage` and
    /// `Fidelity.exactSamples` verification.
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
        switch decodingLimits.validateManagedOutcome(
            encodedByteCount: frameData.count,
            descriptor: descriptor,
            frameIndex: frameIndex
        ) {
        case .success(let value): expectedBytes = value
        case .failure(let failure): return .failure(failure)
        }

        return frameData.withBorrowedBytes { encoded -> DICOMManagedOutcome<ManagedDecodedPixelFrame> in
            let geometry: ValidatedRLEGeometry
            switch Self.validateGeometryManaged(descriptor) {
            case .success(let value): geometry = value
            case .failure(let failure): return .failure(failure)
            }

            let segmentRanges: [Range<Int>]
            switch Self.validateRLEHeaderManaged(encoded, expectedSegments: geometry.expectedSegments) {
            case .success(let value): segmentRanges = value
            case .failure(let failure): return .failure(failure)
            }

            guard let encodedBase = encoded.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return .failure(DICOMManagedFailure(.malformed, 300))
            }

            let (stagingByteCount, stagingOverflow) = expectedBytes.addingReportingOverflow(encoded.count)
            guard !stagingOverflow, stagingByteCount > 0 else {
                return .failure(DICOMManagedFailure(.limitExceeded, 307))
            }

            let rleLimits = Self.makeResourceLimits(
                encodedByteCount: encoded.count,
                decodedByteCount: expectedBytes,
                pixelsPerFrame: geometry.pixelsPerFrame,
                rows: descriptor.rows,
                columns: descriptor.columns
            )

            switch DICOMByteBuffer.admitInitialized(
                count: expectedBytes,
                budget: budget,
                resource: .decoded,
                initializingWith: { dst in
                    if let failure = cancellation.failure { return failure }
                    if Task.isCancelled { return DICOMManagedFailure(.cancelled) }

                    let stagingLease: DICOMAllocationLease
                    switch budget.reserveOutcome(stagingByteCount, as: .staging) {
                    case .success(let lease): stagingLease = lease
                    case .failure(let error): return DICOMManagedFailure(allocation: error)
                    }

                    if let failure = cancellation.failure {
                        _ = stagingLease.isOwned(by: budget)
                        return failure
                    }

                    var decodeFailure: DICOMManagedFailure?
                    do {
                        try Self.decodeValidatedBuffer(
                            encodedBase: encodedBase,
                            encodedCount: encoded.count,
                            segmentRanges: segmentRanges,
                            geometry: geometry,
                            descriptor: descriptor,
                            limits: rleLimits,
                            into: dst,
                            cancellation: cancellation
                        )
                    } catch let managed as DICOMManagedFailure {
                        decodeFailure = managed
                    } catch is CancellationError {
                        decodeFailure = DICOMManagedFailure(.cancelled)
                    } catch let codecError as SwiftRLE.CodecError {
                        decodeFailure = Self.translateManagedError(codecError)
                    } catch {
                        decodeFailure = DICOMManagedFailure(.malformed, 308)
                    }
                    _ = stagingLease.isOwned(by: budget)
                    if let decodeFailure {
                        return decodeFailure
                    }

                    if let failure = cancellation.failure { return failure }
                    if Task.isCancelled { return DICOMManagedFailure(.cancelled) }
                    return nil
                }
            ) {
            case .failure(let failure):
                return .failure(failure)
            case .success(let outputBuffer):
                return .success(ManagedDecodedPixelFrame(
                    data: outputBuffer,
                    descriptor: descriptor,
                    sourceFrameIndex: frameIndex
                ))
            }
        }
    }

    // MARK: - Unmanaged & Caller-Owned Decoding

    /// Decodes an RLE-compressed frame via `SwiftRLE`.
    /// - Parameters:
    ///   - frameData: RLE compressed data (contiguous or sliced `Data`)
    ///   - descriptor: Pixel data descriptor
    ///   - frameIndex: Frame index
    /// - Returns: Uncompressed pixel data
    /// - Throws: `DICOMError` if decoding fails
    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        let expectedBytes = try decodingLimits.validate(frameData, descriptor: descriptor, frameIndex: frameIndex)
        var output = Data(count: expectedBytes)
        let written = try output.withUnsafeMutableBytes { dstBuffer in
            try decodeFrame(frameData, descriptor: descriptor, frameIndex: frameIndex, into: dstBuffer)
        }
        guard written == expectedBytes else {
            throw DICOMError.parsingFailed("RLE decoded byte count (\(written)) did not match expected (\(expectedBytes))")
        }
        return output
    }

    /// Caller-owned decode: scatters or interleaves `SwiftRLE`-decoded segments directly into `destination`.
    public func decodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        into destination: UnsafeMutableRawBufferPointer
    ) throws -> Int {
        try Task.checkCancellation()
        let expectedBytes = try decodingLimits.validate(frameData, descriptor: descriptor, frameIndex: frameIndex)
        guard destination.count >= expectedBytes, destination.baseAddress != nil else {
            throw DICOMError.limitExceeded(
                "Caller-owned destination too small: \(destination.count) bytes for \(expectedBytes)-byte frame"
            )
        }

        let geometry = try Self.validateGeometry(descriptor)
        guard geometry.bytesPerFrame == expectedBytes else {
            throw DICOMError.parsingFailed("RLE frame geometry byte count mismatch")
        }

        let rleLimits = Self.makeResourceLimits(
            encodedByteCount: frameData.count,
            decodedByteCount: expectedBytes,
            pixelsPerFrame: geometry.pixelsPerFrame,
            rows: descriptor.rows,
            columns: descriptor.columns
        )

        try frameData.withUnsafeBytes { rawEncoded in
            let segmentRanges = try Self.validateRLEHeader(rawEncoded, expectedSegments: geometry.expectedSegments)
            guard let encodedBase = rawEncoded.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw DICOMError.parsingFailed("RLE frame buffer has no base address")
            }
            do {
                try Self.decodeValidatedBuffer(
                    encodedBase: encodedBase,
                    encodedCount: rawEncoded.count,
                    segmentRanges: segmentRanges,
                    geometry: geometry,
                    descriptor: descriptor,
                    limits: rleLimits,
                    into: destination,
                    cancellation: .never
                )
            } catch let dicomError as DICOMError {
                throw dicomError
            } catch is CancellationError {
                throw CancellationError()
            } catch let codecError as SwiftRLE.CodecError {
                throw Self.translateError(codecError)
            } catch {
                throw DICOMError.parsingFailed("SwiftRLE decode failed: \(error)")
            }
        }

        return expectedBytes
    }

    // MARK: - Encoding

    /// Whether this encoder can produce RLE Lossless for the given pixel layout.
    ///
    /// RLE Lossless allows up to 15 segments (`bytesPerSample * samplesPerPixel`)
    /// and 8- or 16-bit samples. RLE is always lossless, so the quality setting
    /// is irrelevant. Reference: DICOM PS3.5 Annex G.
    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        guard descriptor.rows > 0, descriptor.columns > 0 else { return false }
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else { return false }
        let (segments, segOverflow) = descriptor.bytesPerSample.multipliedReportingOverflow(by: descriptor.samplesPerPixel)
        guard !segOverflow, (1...15).contains(segments) else { return false }
        let (pixels, pixOverflow) = descriptor.rows.multipliedReportingOverflow(by: descriptor.columns)
        guard !pixOverflow, pixels > 0 else { return false }
        let (_, bytesOverflow) = pixels.multipliedReportingOverflow(by: segments)
        return !bytesOverflow
    }

    /// Encodes a single frame to RLE Lossless via `SwiftRLE`.
    ///
    /// Uses `SwiftRLE.Encoder` directly over shared source storage (`copyPolicy: .requireSharedStorage`)
    /// for canonical 1- and 3-component DICOM layouts, falling back to `SwiftRLE.PackBitsEncoder`
    /// per MSB-to-LSB byte plane (row-bounded per PS3.5 G.3.1) for arbitrary `1...15`-segment layouts.
    public func encodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        configuration: CompressionConfiguration
    ) throws -> Data {
        try Task.checkCancellation()
        let geometry = try Self.validateGeometry(descriptor)
        let rleLimits = Self.makeEncodeResourceLimits(
            decodedByteCount: max(frameData.count, geometry.bytesPerFrame),
            pixelsPerFrame: geometry.pixelsPerFrame,
            rows: descriptor.rows,
            columns: descriptor.columns,
            expectedSegments: geometry.expectedSegments
        )

        // Primary zero-copy path: SwiftRLE.Encoder over borrowed ReadOnlyImageStorage.
        if frameData.count >= geometry.bytesPerFrame,
           let rleDescriptor = try? Self.makeSwiftRLEFrameDescriptor(descriptor: descriptor, limits: rleLimits) {
            do {
                let sourceSlice = frameData.count == geometry.bytesPerFrame
                    ? frameData
                    : frameData.prefix(geometry.bytesPerFrame)
                let sourceStorage = BorrowedSourceImageStorage(data: sourceSlice)
                let image = try SwiftRLE.Image(
                    descriptor: rleDescriptor.imageDescriptor,
                    storage: sourceStorage,
                    limits: rleLimits
                )
                let codecOptions = try SwiftRLE.CodecOptions(
                    profile: .dicomRLEFrame,
                    frameDescriptor: rleDescriptor
                )
                let encoderConfig = try SwiftRLE.EncoderConfiguration(
                    mode: .lossless,
                    codecOptions: codecOptions
                )
                let encodeOptions = SwiftRLE.EncodeOptions(
                    resourceLimits: rleLimits,
                    executionPolicy: .automatic,
                    copyPolicy: .requireSharedStorage
                )
                let encoded = try SwiftRLE.Encoder(configuration: encoderConfig)
                    .encodeSynchronously(image, options: encodeOptions)
                guard encoded.report.fidelity == .exactSamples,
                      encoded.report.copyEvents.isEmpty else {
                    throw DICOMError.parsingFailed("SwiftRLE encode violated exact-sample or shared-storage contract")
                }
                return encoded.data
            } catch let dicomError as DICOMError {
                throw dicomError
            } catch is CancellationError {
                throw CancellationError()
            } catch let codecError as SwiftRLE.CodecError {
                throw Self.translateError(codecError)
            }
        }

        // General 1...15-segment path: MSB-to-LSB byte planes encoded row-by-row via SwiftRLE.PackBitsEncoder.
        let planes = Self.deinterleaveSegments(frameData, descriptor: descriptor, geometry: geometry)
        let packBitsEncoder: SwiftRLE.PackBitsEncoder
        do {
            packBitsEncoder = try SwiftRLE.PackBitsEncoder(configuration: .packBits)
        } catch let codecError as SwiftRLE.CodecError {
            throw Self.translateError(codecError)
        }
        let encodeOptions = SwiftRLE.EncodeOptions(
            resourceLimits: rleLimits,
            executionPolicy: .automatic,
            copyPolicy: .requireSharedStorage
        )

        var encodedSegments: [Data] = []
        encodedSegments.reserveCapacity(geometry.expectedSegments)
        for plane in planes {
            let encodedPlane: SwiftRLE.EncodedBytes
            do {
                encodedPlane = try packBitsEncoder.encodeSynchronously(
                    plane,
                    rowBytes: descriptor.columns,
                    rowCount: descriptor.rows,
                    options: encodeOptions
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let codecError as SwiftRLE.CodecError {
                throw Self.translateError(codecError)
            }
            guard encodedPlane.report.fidelity == .exactSamples,
                  encodedPlane.report.copyEvents.isEmpty else {
                throw DICOMError.parsingFailed("SwiftRLE PackBits encode violated exact-sample or shared-storage contract")
            }
            var segmentBytes = encodedPlane.data
            if segmentBytes.count % 2 != 0 {
                segmentBytes.append(0)
            }
            encodedSegments.append(segmentBytes)
        }

        var frame = Data(count: 64)
        Self.writeUInt32LE(UInt32(geometry.expectedSegments), into: &frame, at: 0)
        var offset = 64
        for (i, seg) in encodedSegments.enumerated() {
            let (nextOffset, overflow) = offset.addingReportingOverflow(seg.count)
            guard !overflow, let offsetWord = UInt32(exactly: offset), UInt64(nextOffset) <= UInt64(UInt32.max) else {
                throw DICOMError.limitExceeded("RLE encoded frame exceeds 32-bit segment offset range")
            }
            Self.writeUInt32LE(offsetWord, into: &frame, at: 4 + i * 4)
            offset = nextOffset
        }
        for seg in encodedSegments {
            frame.append(seg)
        }
        return frame
    }

    // MARK: - Internal SwiftRLE Delegation Helpers

    private struct ValidatedRLEGeometry: Sendable {
        let bytesPerSample: Int
        let samplesPerPixel: Int
        let pixelsPerFrame: Int
        let expectedSegments: Int
        let bytesPerFrame: Int
    }

    private static func validateGeometry(_ descriptor: PixelDataDescriptor) throws -> ValidatedRLEGeometry {
        guard descriptor.rows > 0, descriptor.columns > 0 else {
            throw DICOMError.parsingFailed("RLE frame dimensions must be positive (\(descriptor.columns)x\(descriptor.rows))")
        }
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
            throw DICOMError.parsingFailed("RLE requires 8- or 16-bit allocated samples (got \(descriptor.bitsAllocated))")
        }
        let bytesPerSample = descriptor.bitsAllocated / 8
        let samplesPerPixel = descriptor.samplesPerPixel
        let (expectedSegments, segOverflow) = bytesPerSample.multipliedReportingOverflow(by: samplesPerPixel)
        guard !segOverflow, (1...15).contains(expectedSegments) else {
            throw DICOMError.parsingFailed("RLE cannot represent \(expectedSegments) segments (must be 1...15)")
        }
        let (pixelsPerFrame, pixOverflow) = descriptor.rows.multipliedReportingOverflow(by: descriptor.columns)
        guard !pixOverflow, pixelsPerFrame > 0 else {
            throw DICOMError.limitExceeded("RLE pixel count overflow")
        }
        let (bytesPerFrame, bytesOverflow) = pixelsPerFrame.multipliedReportingOverflow(by: expectedSegments)
        guard !bytesOverflow, bytesPerFrame > 0 else {
            throw DICOMError.limitExceeded("RLE frame byte count overflow")
        }
        return ValidatedRLEGeometry(
            bytesPerSample: bytesPerSample,
            samplesPerPixel: samplesPerPixel,
            pixelsPerFrame: pixelsPerFrame,
            expectedSegments: expectedSegments,
            bytesPerFrame: bytesPerFrame
        )
    }

    private static func validateGeometryManaged(
        _ descriptor: PixelDataDescriptor
    ) -> DICOMManagedOutcome<ValidatedRLEGeometry> {
        guard descriptor.rows > 0, descriptor.columns > 0,
              descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 301))
        }
        let bytesPerSample = descriptor.bitsAllocated / 8
        let samplesPerPixel = descriptor.samplesPerPixel
        let (expectedSegments, segOverflow) = bytesPerSample.multipliedReportingOverflow(by: samplesPerPixel)
        guard !segOverflow, (1...15).contains(expectedSegments) else {
            return .failure(DICOMManagedFailure(.invalidDescriptor, 301, expectedSegments))
        }
        let (pixelsPerFrame, pixOverflow) = descriptor.rows.multipliedReportingOverflow(by: descriptor.columns)
        guard !pixOverflow, pixelsPerFrame > 0 else {
            return .failure(DICOMManagedFailure(.limitExceeded, 301))
        }
        let (bytesPerFrame, bytesOverflow) = pixelsPerFrame.multipliedReportingOverflow(by: expectedSegments)
        guard !bytesOverflow, bytesPerFrame > 0 else {
            return .failure(DICOMManagedFailure(.limitExceeded, 301))
        }
        return .success(ValidatedRLEGeometry(
            bytesPerSample: bytesPerSample,
            samplesPerPixel: samplesPerPixel,
            pixelsPerFrame: pixelsPerFrame,
            expectedSegments: expectedSegments,
            bytesPerFrame: bytesPerFrame
        ))
    }

    private static func validateRLEHeader(
        _ encoded: UnsafeRawBufferPointer,
        expectedSegments: Int
    ) throws -> [Range<Int>] {
        switch validateRLEHeaderManaged(encoded, expectedSegments: expectedSegments) {
        case .success(let ranges):
            return ranges
        case .failure(let managed):
            if managed.operand1 == 300 {
                throw DICOMError.parsingFailed("RLE data too short for 64-byte header (\(encoded.count) bytes)")
            } else if managed.operand1 == 301 {
                throw DICOMError.parsingFailed(
                    "Unexpected number of RLE segments: \(managed.operand2), expected \(expectedSegments)"
                )
            } else {
                throw DICOMError.parsingFailed("Invalid RLE segment boundaries in 64-byte header")
            }
        }
    }

    private static func validateRLEHeaderManaged(
        _ encoded: UnsafeRawBufferPointer,
        expectedSegments: Int
    ) -> DICOMManagedOutcome<[Range<Int>]> {
        guard encoded.count >= 64 else {
            return .failure(DICOMManagedFailure(.malformed, 300))
        }
        let numberOfSegments = readUInt32LE(encoded, at: 0)
        guard (1...15).contains(expectedSegments),
              numberOfSegments == UInt32(expectedSegments) else {
            let reported = Int(exactly: numberOfSegments) ?? Int.max
            return .failure(DICOMManagedFailure(
                .invalidDescriptor, 301, reported, operand3: expectedSegments
            ))
        }

        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(expectedSegments)
        for segIdx in 0..<expectedSegments {
            guard let segStart = Int(exactly: readUInt32LE(encoded, at: 4 + segIdx * 4)) else {
                return .failure(DICOMManagedFailure(.malformed, 302, segIdx))
            }
            let segEnd: Int
            if segIdx + 1 < expectedSegments {
                guard let nextStart = Int(exactly: readUInt32LE(encoded, at: 4 + (segIdx + 1) * 4)) else {
                    return .failure(DICOMManagedFailure(.malformed, 302, segIdx))
                }
                segEnd = nextStart
            } else {
                segEnd = encoded.count
            }
            let validStart = (segIdx == 0) ? (segStart == 64) : (segStart >= 64)
            guard validStart, segStart < segEnd, segEnd <= encoded.count else {
                return .failure(DICOMManagedFailure(.malformed, 302, segIdx))
            }
            ranges.append(segStart..<segEnd)
        }

        for unusedIdx in expectedSegments..<15 {
            guard readUInt32LE(encoded, at: 4 + unusedIdx * 4) == 0 else {
                return .failure(DICOMManagedFailure(.malformed, 302, unusedIdx))
            }
        }
        return .success(ranges)
    }

    private static func decodeValidatedBuffer(
        encodedBase: UnsafePointer<UInt8>,
        encodedCount: Int,
        segmentRanges: [Range<Int>],
        geometry: ValidatedRLEGeometry,
        descriptor: PixelDataDescriptor,
        limits: SwiftRLE.ResourceLimits,
        into destination: UnsafeMutableRawBufferPointer,
        cancellation: DICOMCancellation
    ) throws {
        if let failure = cancellation.failure { throw failure }

        let canTryDirectFrameKernel = segmentRanges.allSatisfy { range in
            range.count % 2 == 0 &&
            !(range.count >= 2 && encodedBase[range.upperBound - 1] == 0x80 && encodedBase[range.upperBound - 2] == 0x80)
        }

        if canTryDirectFrameKernel,
           let rleDescriptor = try? makeSwiftRLEFrameDescriptor(descriptor: descriptor, limits: limits) {
            let contiguousFrame = Data(bytes: encodedBase, count: encodedCount)
            let dstStorage = BorrowedDestinationImageStorage(
                pointer: UnsafeMutableRawBufferPointer(start: destination.baseAddress, count: geometry.bytesPerFrame)
            )
            defer { dstStorage.invalidateScope() }

            do {
                let imageDestination = try SwiftRLE.ImageDestination(
                    descriptor: rleDescriptor.imageDescriptor,
                    storage: dstStorage,
                    limits: limits
                )
                let codecOptions = try SwiftRLE.CodecOptions(
                    profile: .dicomRLEFrame,
                    frameDescriptor: rleDescriptor
                )
                let decoder = try SwiftRLE.Decoder(
                    configuration: SwiftRLE.DecoderConfiguration(codecOptions: codecOptions)
                )
                let decodeOptions = SwiftRLE.DecodeOptions(
                    resourceLimits: limits,
                    executionPolicy: .automatic,
                    copyPolicy: .requireSharedStorage
                )
                let decoded = try decoder.decodeSynchronously(
                    contiguousFrame,
                    into: imageDestination,
                    options: decodeOptions
                )
                guard decoded.report.fidelity == .exactSamples,
                      decoded.report.copyEvents.isEmpty else {
                    throw DICOMError.parsingFailed("SwiftRLE decode violated exact-sample or shared-storage contract")
                }
                return
            } catch let error as SwiftRLE.CodecError where error.category == .malformedInput {
                // Legacy RLE streams in the wild (and conformance unit tests) occasionally emit
                // PackBits runs that cross row boundaries; PS3.5 G.3.2 permits linear segment
                // decoding. Fall through to SwiftRLE.PackBitsDecoder per segment.
            }
        }

        if let failure = cancellation.failure { throw failure }
        try decodeSegmentsViaSwiftRLEPackBits(
            encodedBase: encodedBase,
            segmentRanges: segmentRanges,
            geometry: geometry,
            descriptor: descriptor,
            limits: limits,
            into: destination,
            cancellation: cancellation
        )
    }

    private static func decodeSegmentsViaSwiftRLEPackBits(
        encodedBase: UnsafePointer<UInt8>,
        segmentRanges: [Range<Int>],
        geometry: ValidatedRLEGeometry,
        descriptor: PixelDataDescriptor,
        limits: SwiftRLE.ResourceLimits,
        into destination: UnsafeMutableRawBufferPointer,
        cancellation: DICOMCancellation
    ) throws {
        guard let dstBase = destination.baseAddress?.assumingMemoryBound(to: UInt8.self),
              destination.count >= geometry.bytesPerFrame else {
            throw DICOMError.limitExceeded("RLE destination buffer too small")
        }

        let packBitsDecoder = try SwiftRLE.PackBitsDecoder(configuration: .packBits)
        let decodeOptions = SwiftRLE.DecodeOptions(
            resourceLimits: limits,
            executionPolicy: .automatic,
            copyPolicy: .requireSharedStorage
        )

        let bytesPerSample = geometry.bytesPerSample
        let samplesPerPixel = geometry.samplesPerPixel
        let pixelsPerFrame = geometry.pixelsPerFrame
        let byPlane = descriptor.planarConfiguration != 0 && samplesPerPixel > 1
        let planeSize = pixelsPerFrame * bytesPerSample

        for (segIdx, range) in segmentRanges.enumerated() {
            if let failure = cancellation.failure { throw failure }
            try Task.checkCancellation()

            let segPtr = encodedBase.advanced(by: range.lowerBound)
            let segCount = range.count
            let decodedPlane = try decodeSingleSegmentWithPadCheck(
                decoder: packBitsDecoder,
                segmentBase: segPtr,
                segmentLength: segCount,
                expectedLength: pixelsPerFrame,
                options: decodeOptions
            )

            if let failure = cancellation.failure { throw failure }

            let sampleIndex = segIdx / bytesPerSample
            let byteIndex = bytesPerSample - 1 - (segIdx % bytesPerSample)

            try decodedPlane.withUnsafeBytes { planeRaw in
                guard planeRaw.count == pixelsPerFrame,
                      let planeBase = planeRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    throw DICOMError.parsingFailed("SwiftRLE PackBits decoded plane length mismatch")
                }

                if samplesPerPixel == 1 && bytesPerSample == 1 {
                    dstBase.update(from: planeBase, count: pixelsPerFrame)
                } else if samplesPerPixel == 1 && bytesPerSample == 2 {
                    for p in 0..<pixelsPerFrame {
                        if (p & 0xFFFF) == 0, let failure = cancellation.failure { throw failure }
                        dstBase[p * 2 + byteIndex] = planeBase[p]
                    }
                } else if !byPlane {
                    let pixelStride = samplesPerPixel * bytesPerSample
                    let baseComponentOffset = sampleIndex * bytesPerSample + byteIndex
                    for p in 0..<pixelsPerFrame {
                        if (p & 0xFFFF) == 0, let failure = cancellation.failure { throw failure }
                        dstBase[p * pixelStride + baseComponentOffset] = planeBase[p]
                    }
                } else {
                    let planeOffset = sampleIndex * planeSize + byteIndex
                    for p in 0..<pixelsPerFrame {
                        if (p & 0xFFFF) == 0, let failure = cancellation.failure { throw failure }
                        dstBase[planeOffset + p * bytesPerSample] = planeBase[p]
                    }
                }
            }
        }
    }

    /// Decodes a single RLE byte-plane segment via `SwiftRLE.PackBitsDecoder`, allowing at most
    /// one trailing PS3.5 G.3.2 even-length pad byte (`0x00` or `0x80`) after `expectedLength`
    /// output bytes have been produced, and rejecting `>= 2` trailing bytes.
    private static func decodeSingleSegmentWithPadCheck(
        decoder: SwiftRLE.PackBitsDecoder,
        segmentBase: UnsafePointer<UInt8>,
        segmentLength: Int,
        expectedLength: Int,
        options: SwiftRLE.DecodeOptions
    ) throws -> Data {
        guard segmentLength > 0 else {
            throw SwiftRLE.CodecError(.malformedInput, "Empty RLE segment.")
        }

        // Reject >= 2 trailing bytes when the penultimate byte is a 0x80 NOP: because the final
        // byte of any literal or repeat packet is always a required payload byte, `segmentLength - 2`
        // can decode to `expectedLength` if and only if at least two trailing bytes follow the end
        // of the final data-producing packet.
        if segmentLength >= 2, segmentBase[segmentLength - 2] == 0x80 {
            let trimmedTwo = Data(bytes: segmentBase, count: segmentLength - 2)
            if (try? decoder.decodeSynchronously(trimmedTwo, expectedByteCount: expectedLength, options: options)) != nil {
                throw SwiftRLE.CodecError(
                    .malformedInput,
                    "RLE segment carries more than one trailing byte beyond declared length \(expectedLength)."
                )
            }
        }

        let fullSegment = Data(bytes: segmentBase, count: segmentLength)
        do {
            let result = try decoder.decodeSynchronously(
                fullSegment,
                expectedByteCount: expectedLength,
                options: options
            )
            guard result.report.fidelity == .exactSamples,
                  result.report.copyEvents.isEmpty else {
                throw SwiftRLE.CodecError(.internalFailure, "SwiftRLE PackBits report invariant failed.")
            }
            return result.data
        } catch let primaryError as SwiftRLE.CodecError where primaryError.category == .malformedInput && segmentLength >= 2 {
            // A single trailing pad byte (commonly 0x00 per PS3.5 G.3.2) appears as an incomplete
            // 1-byte literal control packet at the end of an even-padded segment. Retry without the
            // single trailing pad byte; if that still fails, rethrow the original malformedInput error.
            let withoutPad = Data(bytes: segmentBase, count: segmentLength - 1)
            guard let strippedResult = try? decoder.decodeSynchronously(
                withoutPad,
                expectedByteCount: expectedLength,
                options: options
            ) else {
                throw primaryError
            }
            guard strippedResult.report.fidelity == .exactSamples,
                  strippedResult.report.copyEvents.isEmpty else {
                throw SwiftRLE.CodecError(.internalFailure, "SwiftRLE PackBits report invariant failed.")
            }
            return strippedResult.data
        }
    }

    /// Maps a `PixelDataDescriptor` to a `SwiftRLE.RLEFrameDescriptor` over the full allocated
    /// sample width (`meaningfulBits == storageBits`) so RLE byte-plane coding preserves all
    /// allocated bits verbatim per DICOM PS3.5 Annex G.2 without masking or display transforms.
    private static func makeSwiftRLEFrameDescriptor(
        descriptor: PixelDataDescriptor,
        limits: SwiftRLE.ResourceLimits
    ) throws -> SwiftRLE.RLEFrameDescriptor {
        let components: [SwiftRLE.ComponentRole]
        let colour: SwiftRLE.ColourInterpretation
        let sampleType: SwiftRLE.SampleType
        let planar: Int

        switch descriptor.samplesPerPixel {
        case 1:
            components = [.grey]
            colour = .greyscale
            sampleType = descriptor.isSigned ? .signedInteger : .unsignedInteger
            planar = 0
        case 3:
            if descriptor.photometricInterpretation == .rgb {
                components = [.red, .green, .blue]
                colour = .rgb
            } else {
                components = [.uninterpreted("Y"), .uninterpreted("Cb"), .uninterpreted("Cr")]
                colour = .unknown
            }
            sampleType = .unsignedInteger
            planar = (descriptor.planarConfiguration == 0) ? 0 : 1
        default:
            throw SwiftRLE.CodecError(.unsupportedFeature, "Component count \(descriptor.samplesPerPixel) uses PackBits plane fallback.")
        }

        return try SwiftRLE.RLEFrameDescriptor(
            width: descriptor.columns,
            height: descriptor.rows,
            sampleType: sampleType,
            storageBits: descriptor.bitsAllocated,
            meaningfulBits: descriptor.bitsAllocated,
            byteOrder: SwiftRLE.ByteOrder.littleEndian,
            components: components,
            colour: colour,
            planarConfiguration: planar,
            limits: limits
        )
    }

    private static func makeResourceLimits(
        encodedByteCount: Int,
        decodedByteCount: Int,
        pixelsPerFrame: Int,
        rows: Int,
        columns: Int
    ) -> SwiftRLE.ResourceLimits {
        let defaults = SwiftRLE.ResourceLimits.general
        let maxCompressed = max(defaults.maximumCompressedBytes, max(1, encodedByteCount))
        let maxDecoded = max(defaults.maximumDecodedBytes, max(1, decodedByteCount))
        let maxPixels = max(defaults.maximumPixels, max(1, pixelsPerFrame))
        let maxDim = max(defaults.maximumDimension, max(1, max(rows, columns)))
        let combined = maxCompressed.addingReportingOverflow(maxDecoded)
        let safeCombined = combined.overflow ? Int.max / 2 : combined.partialValue
        let withMeta = safeCombined.addingReportingOverflow(32 * 1024 * 1024)
        let maxMemory = max(defaults.maximumMemoryBytes, withMeta.overflow ? Int.max / 2 : withMeta.partialValue)

        return (try? SwiftRLE.ResourceLimits(
            maximumCompressedBytes: maxCompressed,
            maximumDecodedBytes: maxDecoded,
            maximumWorkspaceBytes: max(defaults.maximumWorkspaceBytes, maxDecoded),
            maximumPixels: maxPixels,
            maximumDimension: maxDim,
            maximumFrames: defaults.maximumFrames,
            maximumMetadataBytes: defaults.maximumMetadataBytes,
            maximumICCBytes: defaults.maximumICCBytes,
            maximumNestingDepth: defaults.maximumNestingDepth,
            maximumWorkers: defaults.maximumWorkers,
            deadlineSeconds: 30.0,
            maximumMemoryBytes: maxMemory
        )) ?? defaults
    }

    private static func makeEncodeResourceLimits(
        decodedByteCount: Int,
        pixelsPerFrame: Int,
        rows: Int,
        columns: Int,
        expectedSegments: Int
    ) -> SwiftRLE.ResourceLimits {
        let rowBound = columns + (columns + 2) / 3
        let segBound = rowBound.multipliedReportingOverflow(by: rows)
        let worstSegment = segBound.overflow ? decodedByteCount * 2 : (segBound.partialValue + 1)
        let totalWorst = worstSegment.multipliedReportingOverflow(by: expectedSegments)
        let estimatedMaxCompressed = totalWorst.overflow ? decodedByteCount * 2 : (64 + totalWorst.partialValue)
        return makeResourceLimits(
            encodedByteCount: estimatedMaxCompressed,
            decodedByteCount: decodedByteCount,
            pixelsPerFrame: pixelsPerFrame,
            rows: rows,
            columns: columns
        )
    }

    private static func deinterleaveSegments(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        geometry: ValidatedRLEGeometry
    ) -> [Data] {
        let bytesPerSample = geometry.bytesPerSample
        let samplesPerPixel = geometry.samplesPerPixel
        let pixelsPerFrame = geometry.pixelsPerFrame
        let numberOfSegments = geometry.expectedSegments
        let byPlane = descriptor.planarConfiguration != 0 && samplesPerPixel > 1
        let planeSize = pixelsPerFrame * bytesPerSample

        var segments = [Data](repeating: Data(count: pixelsPerFrame), count: numberOfSegments)
        frameData.withUnsafeBytes { srcRaw in
            let srcCount = srcRaw.count
            let srcBase = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self)
            for segIdx in 0..<numberOfSegments {
                let sampleIndex = segIdx / bytesPerSample
                let byteIndex = bytesPerSample - 1 - (segIdx % bytesPerSample)
                segments[segIdx].withUnsafeMutableBytes { dstRaw in
                    guard let dstBase = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    guard let srcBase else { return }
                    for pixelIndex in 0..<pixelsPerFrame {
                        let inputOffset: Int
                        if byPlane {
                            inputOffset = sampleIndex * planeSize + pixelIndex * bytesPerSample + byteIndex
                        } else {
                            inputOffset = (pixelIndex * samplesPerPixel + sampleIndex) * bytesPerSample + byteIndex
                        }
                        dstBase[pixelIndex] = inputOffset < srcCount ? srcBase[inputOffset] : 0
                    }
                }
            }
        }
        return segments
    }

    private static func translateError(_ error: SwiftRLE.CodecError) -> DICOMError {
        switch error.category {
        case .resourceLimitExceeded:
            return .limitExceeded("SwiftRLE resource limit exceeded: \(error.message)")
        case .unsupportedFeature, .unsupportedFormat, .backendUnavailable:
            return .unsupportedTransferSyntax("SwiftRLE unsupported capability: \(error.message)")
        case .malformedInput, .invalidArgument, .incompatibleImageLayout,
             .storageUnavailable, .ioFailure, .internalFailure:
            return .parsingFailed("SwiftRLE \(error.category.rawValue): \(error.message)")
        }
    }

    private static func translateManagedError(_ error: SwiftRLE.CodecError) -> DICOMManagedFailure {
        switch error.category {
        case .resourceLimitExceeded:
            return DICOMManagedFailure(.limitExceeded, 307)
        case .unsupportedFeature, .unsupportedFormat, .backendUnavailable:
            return DICOMManagedFailure(.invalidTransferSyntax, 309)
        case .invalidArgument, .incompatibleImageLayout:
            return DICOMManagedFailure(.invalidDescriptor, 301)
        case .malformedInput:
            return DICOMManagedFailure(.malformed, 304)
        case .storageUnavailable, .ioFailure, .internalFailure:
            return DICOMManagedFailure(.codecFailure, 310)
        }
    }

    @inline(__always)
    private static func readUInt32LE(_ buffer: UnsafeRawBufferPointer, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= buffer.count, let base = buffer.baseAddress else { return 0 }
        let p = base.assumingMemoryBound(to: UInt8.self).advanced(by: offset)
        return UInt32(p[0])
            | (UInt32(p[1]) << 8)
            | (UInt32(p[2]) << 16)
            | (UInt32(p[3]) << 24)
    }

    private static func writeUInt32LE(_ value: UInt32, into data: inout Data, at offset: Int) {
        let base = data.startIndex + offset
        data[base]     = UInt8(value & 0xFF)
        data[base + 1] = UInt8((value >> 8) & 0xFF)
        data[base + 2] = UInt8((value >> 16) & 0xFF)
        data[base + 3] = UInt8((value >> 24) & 0xFF)
    }
}

// MARK: - Zero-Copy Shared Storage Adapters for SwiftRLE

/// Immutable `ReadOnlyImageStorage` retaining a `Data` slice across synchronous `SwiftRLE.Encoder` execution.
private final class BorrowedSourceImageStorage: SwiftRLE.ReadOnlyImageStorage, Sendable {
    private let data: Data
    let allocationID = UUID()

    var byteCount: Int { data.count }

    init(data: Data) {
        self.data = data
    }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
        try data.withUnsafeBytes(body)
    }
}

/// Scoped `WritableImageStorage` adapter writing directly into a caller-owned or
/// `DICOMByteBuffer`-admitted destination buffer during synchronous `SwiftRLE.Decoder` execution.
/// Invalidated via `invalidateScope()` before the destination pointer's lexical scope exits.
private final class BorrowedDestinationImageStorage: SwiftRLE.WritableImageStorage, @unchecked Sendable {
    let byteCount: Int
    let allocationID = UUID()

    private enum Phase: Sendable {
        case available
        case writing(SwiftRLE.StorageWriteLease)
        case sealed
        case invalid
    }

    private struct ScopeState: @unchecked Sendable {
        var pointer: UnsafeMutableRawBufferPointer?
        var phase: Phase = .available
    }

    private let state: Mutex<ScopeState>
    private let engaged = Atomic<Bool>(false)

    init(pointer: UnsafeMutableRawBufferPointer) {
        self.byteCount = pointer.count
        self.state = Mutex(ScopeState(pointer: pointer))
    }

    func invalidateScope() {
        state.withLock { scope in
            scope.pointer = nil
            scope.phase = .invalid
        }
    }

    func reserveWrite() throws -> SwiftRLE.StorageWriteLease {
        try withNonReentrantLock { scope in
            guard case .available = scope.phase, scope.pointer != nil else {
                throw SwiftRLE.CodecError(.storageUnavailable, "Destination storage is unavailable or already reserved.")
            }
            let lease = SwiftRLE.StorageWriteLease()
            scope.phase = .writing(lease)
            return lease
        }
    }

    func withUnsafeMutableBytes<R>(
        lease: SwiftRLE.StorageWriteLease,
        _ body: (UnsafeMutableRawBufferPointer) throws -> R
    ) throws -> R {
        try withNonReentrantLock { scope in
            guard case .writing(let activeLease) = scope.phase,
                  activeLease == lease,
                  let ptr = scope.pointer else {
                throw SwiftRLE.CodecError(.storageUnavailable, "Write lease is stale, foreign, or out of scope.")
            }
            return try body(ptr)
        }
    }

    func finishAndSeal(lease: SwiftRLE.StorageWriteLease) throws -> any SwiftRLE.ReadOnlyImageStorage {
        try withNonReentrantLock { scope in
            guard case .writing(let activeLease) = scope.phase,
                  activeLease == lease,
                  scope.pointer != nil else {
                throw SwiftRLE.CodecError(.storageUnavailable, "Cannot seal stale or invalidated write lease.")
            }
            scope.phase = .sealed
            return SealedBorrowedDestinationStorage(
                byteCount: byteCount,
                allocationID: allocationID,
                owner: self
            )
        }
    }

    func abortAndInvalidate(lease: SwiftRLE.StorageWriteLease) throws {
        try withNonReentrantLock { scope in
            guard case .writing(let activeLease) = scope.phase, activeLease == lease else {
                throw SwiftRLE.CodecError(.storageUnavailable, "Cannot abort stale or foreign write lease.")
            }
            scope.pointer = nil
            scope.phase = .invalid
        }
    }

    fileprivate func withSealedBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
        try withNonReentrantLock { scope in
            guard case .sealed = scope.phase, let ptr = scope.pointer else {
                throw SwiftRLE.CodecError(.storageUnavailable, "Sealed destination borrow has exited scope.")
            }
            return try body(UnsafeRawBufferPointer(ptr))
        }
    }

    private func withNonReentrantLock<R>(_ body: (inout ScopeState) throws -> R) throws -> R {
        guard !engaged.load(ordering: .acquiring) else {
            throw SwiftRLE.CodecError(.storageUnavailable, "Reentrant storage borrow rejected.")
        }
        guard let result = try state.withLockIfAvailable({ scope -> R in
            engaged.store(true, ordering: .releasing)
            defer { engaged.store(false, ordering: .releasing) }
            return try body(&scope)
        }) else {
            throw SwiftRLE.CodecError(.storageUnavailable, "Concurrent storage borrow rejected.")
        }
        return result
    }
}

private final class SealedBorrowedDestinationStorage: SwiftRLE.ReadOnlyImageStorage, Sendable {
    let byteCount: Int
    let allocationID: UUID
    private let owner: BorrowedDestinationImageStorage

    init(byteCount: Int, allocationID: UUID, owner: BorrowedDestinationImageStorage) {
        self.byteCount = byteCount
        self.allocationID = allocationID
        self.owner = owner
    }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
        try owner.withSealedBytes(body)
    }
}
