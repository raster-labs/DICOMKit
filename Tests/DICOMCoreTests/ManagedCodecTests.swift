import Foundation
import Testing
@testable import DICOMCore

@Suite("Managed codec payload ownership")
struct ManagedCodecTests {
    private static let managedProfiles = [
        "ls", "lossless", "rgb", "rle", "j2k", "htj2k", "jxl", "jxl-recomp"
    ]

    private func descriptor(for profile: String, bits: Int = 12) -> PixelDataDescriptor {
        switch profile {
        case "rgb", "jxl-recomp":
            return PixelDataDescriptor(
                rows: 65, columns: 129, numberOfFrames: 2,
                bitsAllocated: 8, bitsStored: 8, highBit: 7,
                isSigned: false, samplesPerPixel: 3,
                photometricInterpretation: .ybrFull422, planarConfiguration: 0
            )
        default:
            return PixelDataDescriptor(
                rows: 65, columns: 129, numberOfFrames: 2,
                bitsAllocated: 16, bitsStored: bits, highBit: bits - 1,
                isSigned: false, samplesPerPixel: 1,
                photometricInterpretation: .monochrome2, planarConfiguration: 0
            )
        }
    }

    private func descriptor(rgb: Bool = false, bits: Int = 12) -> PixelDataDescriptor {
        descriptor(for: rgb ? "rgb" : "lossless", bits: bits)
    }

    private func expectedRetainedByteCount(for profile: String, descriptor d: PixelDataDescriptor) -> Int {
        d.bytesPerFrame
    }

    private func bytes(_ descriptor: PixelDataDescriptor) -> Data {
        if descriptor.samplesPerPixel == 3 {
            return Data((0..<(descriptor.rows * descriptor.columns * 3)).map { UInt8(($0 * 17) & 255) })
        }
        let maximum = (1 << descriptor.bitsStored) - 1
        return Data((0..<(descriptor.rows * descriptor.columns)).flatMap {
            let value = ($0 * 179) & maximum
            return [UInt8(value & 255), UInt8(value >> 8)]
        })
    }
    private func owned(_ data: Data, budget: borrowing DICOMAllocationBudget) throws -> DICOMByteBuffer {
        let result = try DICOMByteBuffer(count: data.count, budget: budget, resource: .encoded)
        data.withUnsafeBytes { result.unsafeMutableBytes.copyMemory(from: $0) }
        return result
    }
    private func destroy(_ buffer: consuming DICOMByteBuffer) {}
    private func destroy(_ frame: consuming ManagedDecodedPixelFrame) {}
    private func destroy(_ budget: consuming DICOMAllocationBudget) {}
    private func jpeg(_ profile: String) -> JLICodec {
        let uid = profile == "rgb" ? TransferSyntax.jpegBaseline.uid : TransferSyntax.jpegLosslessSV1.uid
        return JLICodec(encodingTransferSyntaxUID: uid, decodingTransferSyntaxUID: uid)
    }
    private func encoded(_ profile: String, descriptor: PixelDataDescriptor) throws -> Data {
        let source = bytes(descriptor)
        switch profile {
        case "ls":
            return try JPEGLSCodec().encodeFrame(source, descriptor: descriptor, frameIndex: 1, configuration: .lossless)
        case "rle":
            return try RLECodec().encodeFrame(source, descriptor: descriptor, frameIndex: 1, configuration: .lossless)
        case "j2k":
            return try J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid)
                .encodeFrame(source, descriptor: descriptor, frameIndex: 1, configuration: .lossless)
        case "htj2k":
            return try HTJ2KCodec(targetTransferSyntaxUID: TransferSyntax.htj2kRPCLLossless.uid)
                .encodeFrame(source, descriptor: descriptor, frameIndex: 1, configuration: .lossless)
        case "jxl":
            return try JXLCodec(encodingTransferSyntaxUID: TransferSyntax.jpegXLLossless.uid)
                .encodeFrame(source, descriptor: descriptor, frameIndex: 1, configuration: .lossless)
        case "jxl-recomp":
            let jpegBytes = try JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid)
                .encodeFrame(source, descriptor: descriptor, frameIndex: 1, configuration: .default)
            return try JXLCodec.recompressJPEGFragment(jpegBytes)
        default:
            return try jpeg(profile).encodeFrame(source, descriptor: descriptor, frameIndex: 1, configuration: .lossless)
        }
    }
    private func legacyDecodePixelFrame(_ profile: String, data: Data, descriptor: PixelDataDescriptor) throws -> DecodedPixelFrame {
        switch profile {
        case "ls":
            return try JPEGLSCodec(decodingTransferSyntaxUID: TransferSyntax.jpegLSLossless.uid)
                .decodePixelFrame(data, descriptor: descriptor, frameIndex: 1)
        case "rle":
            return try RLECodec().decodePixelFrame(data, descriptor: descriptor, frameIndex: 1)
        case "j2k":
            return try J2KSwiftCodec(decodingTransferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid)
                .decodePixelFrame(data, descriptor: descriptor, frameIndex: 1)
        case "htj2k":
            return try HTJ2KCodec(targetTransferSyntaxUID: TransferSyntax.htj2kRPCLLossless.uid)
                .decodePixelFrame(data, descriptor: descriptor, frameIndex: 1)
        case "jxl":
            return try JXLCodec(decodingTransferSyntaxUID: TransferSyntax.jpegXLLossless.uid)
                .decodePixelFrame(data, descriptor: descriptor, frameIndex: 1)
        case "jxl-recomp":
            return try JXLCodec(decodingTransferSyntaxUID: TransferSyntax.jpegXLRecompression.uid)
                .decodePixelFrame(data, descriptor: descriptor, frameIndex: 1)
        default:
            return try jpeg(profile).decodePixelFrame(data, descriptor: descriptor, frameIndex: 1)
        }
    }
    private func decode(_ profile: String, frame: borrowing DICOMByteBuffer, descriptor: PixelDataDescriptor,
                        budget: borrowing DICOMAllocationBudget, cancellation: DICOMCancellation = .never)
        throws(DICOMManagedFailure) -> ManagedDecodedPixelFrame {
        switch profile {
        case "ls":
            return try JPEGLSCodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget, cancellation: cancellation)
        case "rle":
            return try RLECodec()
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget, cancellation: cancellation)
        case "j2k":
            return try J2KSwiftCodec(decodingSyntax: .jpeg2000Lossless)
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget, cancellation: cancellation)
        case "htj2k":
            return try HTJ2KCodec(decodingSyntax: .rpclLossless)
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget, cancellation: cancellation)
        case "jxl":
            return try JXLCodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget, cancellation: cancellation)
        case "jxl-recomp":
            return try JXLCodec(decodingSyntax: .recompression)
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget, cancellation: cancellation)
        default:
            return try jpeg(profile).decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget, cancellation: cancellation)
        }
    }

    private func decodeQualified(_ profile: String, frame: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor, budget: borrowing DICOMAllocationBudget,
        cancellation: DICOMCancellation = .never) throws(DICOMManagedFailure) -> ManagedDecodedPixelFrame {
        let execution: DICOMExecutionReservation
        do throws(DICOMAllocationError) { execution = try DICOMExecutionReservation(budget: budget) }
        catch { throw DICOMManagedFailure(allocation: error) }
        switch profile {
        case "ls":
            return try JPEGLSCodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget,
                                         execution: execution, cancellation: cancellation)
        case "rle":
            return try RLECodec()
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget,
                                         execution: execution, cancellation: cancellation)
        case "j2k":
            return try J2KSwiftCodec(decodingSyntax: .jpeg2000Lossless)
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget,
                                         execution: execution, cancellation: cancellation)
        case "htj2k":
            return try HTJ2KCodec(decodingSyntax: .rpclLossless)
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget,
                                         execution: execution, cancellation: cancellation)
        case "jxl":
            return try JXLCodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget,
                                         execution: execution, cancellation: cancellation)
        case "jxl-recomp":
            return try JXLCodec(decodingSyntax: .recompression)
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget,
                                         execution: execution, cancellation: cancellation)
        default:
            return try jpeg(profile).decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1,
                budget: budget, execution: execution, cancellation: cancellation)
        }
    }

    // The harness prepares codecs, fixtures, callback storage and the worker outside
    // the qualified operation. These function types prove the selected entry cannot throw.
    private func decodeQualifiedOutcome(_ profile: String, frame: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor, budget: borrowing DICOMAllocationBudget,
        cancellation: DICOMCancellation = .never) -> DICOMManagedOutcome<ManagedDecodedPixelFrame> {
        let ls = JPEGLSCodec(decodingSyntax: .lossless)
        let jli = jpeg(profile)
        let rle = RLECodec()
        let j2k = J2KSwiftCodec(decodingSyntax: .jpeg2000Lossless)
        let htj2k = HTJ2KCodec(decodingSyntax: .rpclLossless)
        let jxl = JXLCodec(decodingSyntax: .lossless)
        let jxlRecomp = JXLCodec(decodingSyntax: .recompression)
        let execution: DICOMExecutionReservation
        switch DICOMExecutionReservation.reserve(budget: budget) {
        case .success(let value): execution = value
        case .failure(let failure): return .failure(DICOMManagedFailure(allocation: failure))
        }
        typealias QualifiedDecode = (borrowing DICOMByteBuffer, PixelDataDescriptor, Int,
            borrowing DICOMAllocationBudget, borrowing DICOMExecutionReservation,
            DICOMCancellation) -> DICOMManagedOutcome<ManagedDecodedPixelFrame>
        switch profile {
        case "ls":
            let operation: QualifiedDecode = ls.decodeManagedPixelFrameOutcome
            return operation(frame, descriptor, 1, budget, execution, cancellation)
        case "rle":
            let operation: QualifiedDecode = rle.decodeManagedPixelFrameOutcome
            return operation(frame, descriptor, 1, budget, execution, cancellation)
        case "j2k":
            let operation: QualifiedDecode = j2k.decodeManagedPixelFrameOutcome
            return operation(frame, descriptor, 1, budget, execution, cancellation)
        case "htj2k":
            let operation: QualifiedDecode = htj2k.decodeManagedPixelFrameOutcome
            return operation(frame, descriptor, 1, budget, execution, cancellation)
        case "jxl":
            let operation: QualifiedDecode = jxl.decodeManagedPixelFrameOutcome
            return operation(frame, descriptor, 1, budget, execution, cancellation)
        case "jxl-recomp":
            let operation: QualifiedDecode = jxlRecomp.decodeManagedPixelFrameOutcome
            return operation(frame, descriptor, 1, budget, execution, cancellation)
        default:
            let operation: QualifiedDecode = jli.decodeManagedPixelFrameOutcome
            return operation(frame, descriptor, 1, budget, execution, cancellation)
        }
    }

    private func expectEquivalent(_ legacy: consuming DICOMManagedOutcome<ManagedDecodedPixelFrame>,
        _ scalar: consuming DICOMManagedOutcome<ManagedDecodedPixelFrame>) {
        switch consume legacy {
        case .success(let expected):
            switch consume scalar {
            case .success(let actual):
                #expect(actual.descriptor == expected.descriptor)
                #expect(actual.sourceFrameIndex == expected.sourceFrameIndex)
                #expect(actual.diagnostic == expected.diagnostic)
                let expectedBytes = expected.data.withUnsafeBytes { Data($0) }
                #expect(actual.data.withUnsafeBytes { Data($0) } == expectedBytes)
            case .failure(let failure): Issue.record("Scalar constructor changed success to \(failure)")
            }
        case .failure(let expected):
            switch consume scalar {
            case .success: Issue.record("Scalar constructor bypassed the legacy refusal")
            case .failure(let actual): #expect(actual == expected)
            }
        }
    }

    @Test("Finite JPEG construction preserves process restrictions, pixels and resource refusals",
          arguments: [JLICodec.DecodingSyntax.any, .baseline, .extended, .lossless, .losslessSV1])
    func scalarJPEG(syntax: JLICodec.DecodingSyntax) throws {
        let uid: String?
        switch syntax {
        case .any: uid = nil
        case .baseline: uid = TransferSyntax.jpegBaseline.uid
        case .extended: uid = TransferSyntax.jpegExtended.uid
        case .lossless: uid = TransferSyntax.jpegLossless.uid
        case .losslessSV1: uid = TransferSyntax.jpegLosslessSV1.uid
        }
        for profile in ["lossless", "rgb"] {
            let d = descriptor(rgb: profile == "rgb")
            let data = try encoded(profile, descriptor: d)
            let budget = try DICOMAllocationBudget()
            let input = try owned(data, budget: budget)
            let execution = try DICOMExecutionReservation(budget: budget)
            for encodedLimit in [data.count, 0] {
                let limits = PixelDecodeLimits(maximumEncodedBytes: encodedLimit)
                let legacy = JLICodec(decodingTransferSyntaxUID: uid, decodingLimits: limits)
                let scalar = JLICodec(decodingSyntax: syntax, decodingLimits: limits)
                expectEquivalent(legacy.decodeManagedPixelFrameOutcome(input, descriptor: d,
                    frameIndex: 1, budget: budget, execution: execution),
                    scalar.decodeManagedPixelFrameOutcome(input, descriptor: d,
                    frameIndex: 1, budget: budget, execution: execution))
                #expect(scalar.encodingTransferSyntaxUID == TransferSyntax.jpegLosslessSV1.uid)
            }
        }
        let custom = "caller-specific-encoding-policy"
        #expect(JLICodec(encodingTransferSyntaxUID: custom).encodingTransferSyntaxUID == custom)
    }

    @Test("Finite JPEG-LS construction preserves precision recovery, pixels and refusals",
          arguments: [JPEGLSCodec.DecodingSyntax.any, .lossless, .nearLossless])
    func scalarJPEGLS(syntax: JPEGLSCodec.DecodingSyntax) throws {
        let uid: String?
        switch syntax {
        case .any: uid = nil
        case .lossless: uid = TransferSyntax.jpegLSLossless.uid
        case .nearLossless: uid = TransferSyntax.jpegLSNearLossless.uid
        }
        let encodedDescriptor = descriptor(bits: 16)
        let data = try encoded("ls", descriptor: encodedDescriptor)
        let budget = try DICOMAllocationBudget()
        let input = try owned(data, budget: budget)
        let execution = try DICOMExecutionReservation(budget: budget)
        for policy: JPEGLSCodec.PrecisionPolicy in [.requireSourceMatch, .useCodestreamForUnsignedMonochrome] {
            for encodedLimit in [data.count, 0] {
                let limits = PixelDecodeLimits(maximumEncodedBytes: encodedLimit)
                let legacy = JPEGLSCodec(decodingTransferSyntaxUID: uid, decodingLimits: limits,
                    precisionPolicy: policy)
                let scalar = JPEGLSCodec(decodingSyntax: syntax, decodingLimits: limits, precisionPolicy: policy)
                expectEquivalent(legacy.decodeManagedPixelFrameOutcome(input, descriptor: descriptor(bits: 12),
                    frameIndex: 1, budget: budget, execution: execution),
                    scalar.decodeManagedPixelFrameOutcome(input, descriptor: descriptor(bits: 12),
                    frameIndex: 1, budget: budget, execution: execution))
            }
        }
    }

    @Test("Every managed codec propagates aggregate refusal and retains admitted output identity",
          arguments: ManagedCodecTests.managedProfiles)
    func externalAggregateAdmission(profile: String) throws {
        let d = descriptor(for: profile)
        let data = try encoded(profile, descriptor: d)
        let state = ExternalAllocationFixture()
        let budget = try DICOMAllocationBudget.make(externalAdmission: state.callbacks).get()
        let input = try owned(data, budget: budget)
        let before = budget.receipt.currentTotal
        state.value.pointee.refuseResource = Int32(DICOMAllocationClass.decoded.rawValue)
        switch decodeQualifiedOutcome(profile, frame: input, descriptor: d, budget: budget) {
        case .success(let unexpected): destroy(unexpected); Issue.record("Aggregate decoded refusal ignored")
        case .failure(let failure):
            #expect(failure == DICOMManagedFailure(allocation: .externalAdmissionRefused(45)))
        }
        #expect(budget.receipt.currentTotal == before)
        #expect(state.value.pointee.total == before)
        state.value.pointee.refuseResource = -1
        let result = try decodeQualified(profile, frame: input, descriptor: d, budget: budget)
        #expect(result.sourceFrameIndex == 1)
        #expect(result.data.externalAllocationToken != nil)
        #expect(result.data.externalAdmissionContext == budget.externalAdmissionContext)
        #expect(state.value.pointee.total == budget.receipt.currentTotal)
        destroy(input)
        destroy(budget)
        #expect(state.value.pointee.contextReleases == 0)
        destroy(result)
        #expect(state.value.pointee.total == 0)
        #expect(state.value.pointee.contextReleases == 1)
        #expect(state.value.pointee.failures == 0)
    }

    @Test("Qualified outcomes expose cancellation, descriptor and admission failures directly",
          arguments: ManagedCodecTests.managedProfiles)
    func directOutcomeFailures(profile: String) throws {
        let d = descriptor(for: profile)
        let data = try encoded(profile, descriptor: d)
        let budget = try DICOMAllocationBudget(limits: .init(decoded: 0))
        let input = try owned(data, budget: budget)
        let before = budget.receipt.currentTotal
        switch decodeQualifiedOutcome(profile, frame: input, descriptor: d, budget: budget) {
        case .success(let unexpected): destroy(unexpected); Issue.record("Decoded capacity refusal was bypassed")
        case .failure(let failure): #expect(failure == DICOMManagedFailure(allocation: .limitExceeded(.decoded)))
        }
        #expect(budget.receipt.currentTotal == before)
        switch decodeQualifiedOutcome(profile, frame: input, descriptor: d, budget: budget,
            cancellation: DICOMCancellation(check: { _ in true })) {
        case .success(let unexpected): destroy(unexpected); Issue.record("Cancellation was ignored")
        case .failure(let failure): #expect(failure == DICOMManagedFailure(.cancelled))
        }
        let invalid = PixelDataDescriptor(rows: 0, columns: d.columns, numberOfFrames: 2,
            bitsAllocated: d.bitsAllocated, bitsStored: d.bitsStored, highBit: d.highBit,
            isSigned: false, samplesPerPixel: d.samplesPerPixel,
            photometricInterpretation: d.photometricInterpretation, planarConfiguration: 0)
        switch decodeQualifiedOutcome(profile, frame: input, descriptor: invalid, budget: budget) {
        case .success(let unexpected): destroy(unexpected); Issue.record("Invalid descriptor was accepted")
        case .failure(let failure): #expect(failure.code == .invalidDescriptor)
        }
        #expect(budget.receipt.current.decoded == 0)
        #expect(budget.receipt.current.staging == 0)
        #expect(budget.receipt.currentTotal == before)
    }

    @Test("Managed bytes retain policy, frame identity and complete backing ownership", arguments: ManagedCodecTests.managedProfiles)
    func parityAndLifetime(profile: String) throws {
        let d = descriptor(for: profile)
        let data = try encoded(profile, descriptor: d)
        let legacy = try legacyDecodePixelFrame(profile, data: data, descriptor: d)
        let budget = try DICOMAllocationBudget()
        let input = try owned(data, budget: budget)
        let result = try decodeQualified(profile, frame: input, descriptor: d, budget: budget)
        #expect(result.sourceFrameIndex == 1)
        #expect(result.descriptor.photometricInterpretation == legacy.descriptor.photometricInterpretation)
        let decodedData = result.data.withUnsafeBytes { Data($0) }
        #expect(decodedData == legacy.data)
        #expect(result.data.count == legacy.data.count)
        let capacity = result.data.capacity
        let expected = try DICOMByteBuffer.backingCapacity(for: expectedRetainedByteCount(for: profile, descriptor: d))
        #expect(capacity == expected)
        #expect(budget.receipt.current.decoded == capacity)
        #expect(budget.receipt.current.staging == 0)
        let alias = try result.data.share()
        try alias.transfer(to: .resident)
        destroy(result); destroy(input)
        #expect(budget.receipt.current.encoded == 0 && budget.receipt.current.decoded == 0)
        #expect(budget.receipt.current.resident == capacity)
        let retainedData = alias.withUnsafeBytes { Data($0) }
        #expect(retainedData == legacy.data)
        destroy(alias)
        #expect(budget.receipt.currentTotal == DICOMAllocationBudget.controlCapacity)
        #expect(budget.receipt.liveAllocations == 1)
    }

    @Test("Exact capacity succeeds and one-byte-short admission releases temporaries", arguments: ManagedCodecTests.managedProfiles)
    func capsAndFailures(profile: String) throws {
        let d = descriptor(for: profile)
        let data = try encoded(profile, descriptor: d)
        let capacity = try DICOMByteBuffer.backingCapacity(for: expectedRetainedByteCount(for: profile, descriptor: d))
        for delta in [0, -1] {
            let budget = try DICOMAllocationBudget(limits: .init(decoded: capacity + delta))
            let input = try owned(data, budget: budget)
            let before = budget.receipt.currentTotal
            if delta == 0 {
                do { let result = try decode(profile, frame: input, descriptor: d, budget: budget); #expect(result.data.capacity == capacity) }
            } else {
                #expect(throws: DICOMManagedFailure(allocation: .limitExceeded(.decoded))) { _ = try decode(profile, frame: input, descriptor: d, budget: budget) }
            }
            #expect(budget.receipt.currentTotal == before)
        }
        // Fail each controlled backing seam. Successful later seams also release.
        for failureAfter in 2...10 {
            let budget = try DICOMAllocationBudget(allocationFailureAfter: failureAfter)
            let input = try owned(data, budget: budget)
            let before = budget.receipt.currentTotal
            do { _ = try decode(profile, frame: input, descriptor: d, budget: budget) }
            catch { #expect(error == DICOMManagedFailure(allocation: .allocationFailed)) }
            #expect(budget.receipt.currentTotal == before)
        }
    }

    @Test("Precision recovery remains explicit and excludes all mapping tables")
    func recovery() throws {
        let source = descriptor(bits: 12), actual = descriptor(bits: 16)
        let data = try encoded("ls", descriptor: actual)
        let budget = try DICOMAllocationBudget()
        let input = try owned(data, budget: budget)
        #expect(throws: DICOMManagedFailure.self) {
            _ = try JPEGLSCodec().decodeManagedPixelFrame(input, descriptor: source, frameIndex: 1, budget: budget)
        }
        let codec = JPEGLSCodec(decodingTransferSyntaxUID: TransferSyntax.jpegLSLossless.uid,
            precisionPolicy: .useCodestreamForUnsignedMonochrome)
        let recovered = try codec.decodeManagedPixelFrame(input, descriptor: source, frameIndex: 1, budget: budget)
        #expect(recovered.descriptor.bitsStored == 16 && source.bitsStored == 12)
        #expect(recovered.diagnostic == .sourcePrecisionMismatch(sourceBitsStored: 12, encodedPrecision: 16))
        #expect(recovered.data.withUnsafeBytes { Data($0) } == bytes(actual))
        // Unselected, empty table still disqualifies precision recovery.
        var mapping = data
        mapping.insert(contentsOf: [0xff, 0xf8, 0, 5, 2, 5, 2], at: mapping.count - 2)
        let mapped = try owned(mapping, budget: budget)
        #expect(throws: DICOMManagedFailure.self) { _ = try codec.decodeManagedPixelFrame(mapped, descriptor: source, frameIndex: 1, budget: budget) }
        #expect(throws: DICOMError.self) { try codec.decodePixelFrame(mapping, descriptor: source, frameIndex: 1) }
    }

    @Test("Cancellation and malformed input do not transfer or retain partial output", arguments: ManagedCodecTests.managedProfiles)
    func cancellation(profile: String) throws {
        let d = descriptor(for: profile)
        let data = try encoded(profile, descriptor: d)
        let budget = try DICOMAllocationBudget()
        let input = try owned(data, budget: budget)
        let before = budget.receipt.currentTotal
        let unrelated = try DICOMAllocationBudget()
        #expect(throws: DICOMManagedFailure(allocation: .budgetMismatch)) {
            _ = try decode(profile, frame: input, descriptor: d, budget: unrelated)
        }
        #expect(unrelated.receipt.peakTotal == DICOMAllocationBudget.controlCapacity)
        #expect(throws: DICOMManagedFailure(.cancelled)) {
            _ = try decode(profile, frame: input, descriptor: d, budget: budget,
                           cancellation: DICOMCancellation(check: { _ in true }))
        }
        #expect(budget.receipt.currentTotal == before)
        let malformedBytes = (profile == "rle") ? Data(repeating: 0, count: 63) : Data(data.prefix(min(8, max(1, data.count / 4))))
        let malformed = try owned(malformedBytes, budget: budget)
        let retained = budget.receipt.currentTotal
        #expect(throws: DICOMManagedFailure.self) { _ = try decode(profile, frame: malformed, descriptor: d, budget: budget) }
        #expect(budget.receipt.currentTotal == retained)
    }

    @Test("Cancellation after output admission releases output, scratch and execution reservation",
          arguments: ManagedCodecTests.managedProfiles)
    func cancellationAfterAdmission(profile: String) throws {
        let d = descriptor(for: profile)
        let data = try encoded(profile, descriptor: d)
        let budget = try DICOMAllocationBudget()
        let input = try owned(data, budget: budget)
        let before = budget.receipt.currentTotal
        let retainedBudget = try budget.share()
        let context = UnsafeMutablePointer<ManagedCancellationState>.allocate(capacity: 1)
        context.initialize(to: ManagedCancellationState(budget: retainedBudget))
        defer { context.deinitialize(count: 1); context.deallocate() }
        switch decodeQualifiedOutcome(profile, frame: input, descriptor: d, budget: budget,
            cancellation: DICOMCancellation(check: cancelAfterOutputAdmission, context: context)) {
        case .success(let unexpected): destroy(unexpected); Issue.record("Partial decoded output escaped cancellation")
        case .failure(let failure): #expect(failure == DICOMManagedFailure(.cancelled))
        }
        let observedDecodedOwner = context.pointee.observedDecodedOwner
        #expect(observedDecodedOwner)
        #expect(budget.receipt.peak.decoded > 0)
        #expect(budget.receipt.current.decoded == 0)
        #expect(budget.receipt.current.staging == 0)
        #expect(budget.receipt.currentTotal == before)
    }

    @Test("RLE managed decode supports 8/16-bit monochrome, chunky/planar RGB and rejects overshoot segments")
    func rleManagedProfilesAndValidation() throws {
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal

        let descriptors: [PixelDataDescriptor] = [
            PixelDataDescriptor(rows: 16, columns: 16, bitsAllocated: 8, bitsStored: 8, highBit: 7,
                                isSigned: false, samplesPerPixel: 1, photometricInterpretation: .monochrome2),
            PixelDataDescriptor(rows: 16, columns: 16, bitsAllocated: 16, bitsStored: 16, highBit: 15,
                                isSigned: true, samplesPerPixel: 1, photometricInterpretation: .monochrome2),
            PixelDataDescriptor(rows: 12, columns: 14, bitsAllocated: 8, bitsStored: 8, highBit: 7,
                                isSigned: false, samplesPerPixel: 3, photometricInterpretation: .rgb, planarConfiguration: 0),
            PixelDataDescriptor(rows: 12, columns: 14, bitsAllocated: 16, bitsStored: 12, highBit: 11,
                                isSigned: false, samplesPerPixel: 3, photometricInterpretation: .rgb, planarConfiguration: 1)
        ]

        for d in descriptors {
            let expected = Data((0..<d.bytesPerFrame).map { UInt8(($0 * 29 + 7) & 0xFF) })
            let encoded = try RLECodec().encodeFrame(expected, descriptor: d, frameIndex: 0, configuration: .lossless)
            do {
                let input = try owned(encoded, budget: budget)
                let decoded = try RLECodec().decodeManagedPixelFrame(input, descriptor: d, frameIndex: 0, budget: budget)
                #expect(decoded.data.withUnsafeBytes { Data($0) } == expected)
                #expect(budget.receipt.current.staging == 0)
            }
            #expect(budget.receipt.currentTotal == baseline)
        }

        // Overshoot RLE packet (replicate 5 bytes into a 4-pixel 8-bit frame) must fail closed.
        let tiny = PixelDataDescriptor(rows: 2, columns: 2, bitsAllocated: 8, bitsStored: 8, highBit: 7,
                                       isSigned: false, samplesPerPixel: 1, photometricInterpretation: .monochrome2)
        var overshoot = Data(count: 64)
        overshoot[0] = 1
        overshoot[4] = 64
        overshoot.append(contentsOf: [UInt8(bitPattern: Int8(-4)), 0xAA]) // 5 replicated bytes > 4 pixels
        do {
            let badInput = try owned(overshoot, budget: budget)
            #expect(throws: DICOMManagedFailure.self) {
                _ = try RLECodec().decodeManagedPixelFrame(badInput, descriptor: tiny, frameIndex: 0, budget: budget)
            }
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("J2K and HTJ2K managed decode enforce lossless wavelet policy and map YBR_RCT/YBR_ICT to RGB")
    func j2kAndHTJ2KManagedSemantics() throws {
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal

        // Lossless RGB with YBR_RCT maps output descriptor to .rgb
        let rgbRCT = PixelDataDescriptor(
            rows: 16, columns: 16, bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 3, photometricInterpretation: .ybrRCT, planarConfiguration: 0
        )
        let rgbSource = Data((0..<rgbRCT.bytesPerFrame).map { UInt8(($0 * 13) & 0xFF) })
        let j2kLosslessRGB = try J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid)
            .encodeFrame(rgbSource, descriptor: rgbRCT, frameIndex: 0, configuration: .lossless)
        let htj2kLosslessRGB = try HTJ2KCodec(targetTransferSyntaxUID: TransferSyntax.htj2kLossless.uid)
            .encodeFrame(rgbSource, descriptor: rgbRCT, frameIndex: 0, configuration: .lossless)

        do {
            let inJ2K = try owned(j2kLosslessRGB, budget: budget)
            let outJ2K = try J2KSwiftCodec(decodingSyntax: .jpeg2000Lossless)
                .decodeManagedPixelFrame(inJ2K, descriptor: rgbRCT, frameIndex: 0, budget: budget)
            #expect(outJ2K.descriptor.photometricInterpretation == .rgb)
            #expect(outJ2K.data.withUnsafeBytes { Data($0) } == rgbSource)

            let inHT = try owned(htj2kLosslessRGB, budget: budget)
            let outHT = try HTJ2KCodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrame(inHT, descriptor: rgbRCT, frameIndex: 0, budget: budget)
            #expect(outHT.descriptor.photometricInterpretation == .rgb)
            #expect(outHT.data.withUnsafeBytes { Data($0) } == rgbSource)
        }
        #expect(budget.receipt.currentTotal == baseline)

        // Irreversible 9/7 codestream is refused under lossless-only J2K/HTJ2K syntaxes, accepted under general/lossy.
        let mono = PixelDataDescriptor(
            rows: 16, columns: 16, bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1, photometricInterpretation: .monochrome2
        )
        let monoSource = Data((0..<256).map { UInt8($0) })
        let lossyCfg = CompressionConfiguration(quality: .medium, speed: .balanced, progressive: false, preferLossless: false)
        let irreversible = try J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.jpeg2000.uid)
            .encodeFrame(monoSource, descriptor: mono, frameIndex: 0, configuration: lossyCfg)
        do {
            let input = try owned(irreversible, budget: budget)
            for losslessSyntax: J2KSwiftCodec.DecodingSyntax in [.jpeg2000Lossless, .htj2kLossless, .htj2kRPCLLossless] {
                switch J2KSwiftCodec(decodingSyntax: losslessSyntax)
                    .decodeManagedPixelFrameOutcome(input, descriptor: mono, frameIndex: 0, budget: budget) {
                case .success(let unexpected):
                    destroy(unexpected)
                    Issue.record("Irreversible 9/7 accepted under \(losslessSyntax)")
                case .failure(let failure):
                    #expect(failure.code == .invalidDescriptor)
                }
            }
            let accepted = try J2KSwiftCodec(decodingSyntax: .jpeg2000)
                .decodeManagedPixelFrame(input, descriptor: mono, frameIndex: 0, budget: budget)
            #expect(accepted.data.count == 256)
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("Extended JLI, JPEG-LS 8-bit/RGB and JPEG XL signed/XYB/recompression managed profiles")
    func extendedJLIJPEGLSAndJXLManagedProfiles() throws {
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal

        // 1. 8-bit lossless JLI & 8-bit lossless JPEG-LS monochrome
        let mono8 = PixelDataDescriptor(
            rows: 16, columns: 16, bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1, photometricInterpretation: .monochrome2
        )
        let mono8Bytes = Data((0..<256).map { UInt8(($0 * 31) & 0xFF) })
        let jli8 = try JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegLossless.uid)
            .encodeFrame(mono8Bytes, descriptor: mono8, frameIndex: 0, configuration: .lossless)
        let jls8 = try JPEGLSCodec().encodeFrame(mono8Bytes, descriptor: mono8, frameIndex: 0, configuration: .lossless)
        do {
            let inJLI = try owned(jli8, budget: budget)
            let outJLI = try JLICodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrame(inJLI, descriptor: mono8, frameIndex: 0, budget: budget)
            #expect(outJLI.data.withUnsafeBytes { Data($0) } == mono8Bytes)

            let inJLS = try owned(jls8, budget: budget)
            let outJLS = try JPEGLSCodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrame(inJLS, descriptor: mono8, frameIndex: 0, budget: budget)
            #expect(outJLS.data.withUnsafeBytes { Data($0) } == mono8Bytes)
        }
        #expect(budget.receipt.currentTotal == baseline)

        // 2. 3-sample lossless JLI & JPEG-LS RGB
        let rgb8 = PixelDataDescriptor(
            rows: 12, columns: 12, bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 3, photometricInterpretation: .rgb, planarConfiguration: 0
        )
        let rgb8Bytes = Data((0..<rgb8.bytesPerFrame).map { UInt8(($0 * 19 + 3) & 0xFF) })
        let jliRGB = try JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid)
            .encodeFrame(rgb8Bytes, descriptor: rgb8, frameIndex: 0, configuration: .lossless)
        let jlsRGB = try JPEGLSCodec().encodeFrame(rgb8Bytes, descriptor: rgb8, frameIndex: 0, configuration: .lossless)
        do {
            let inJLI = try owned(jliRGB, budget: budget)
            let outJLI = try JLICodec(decodingSyntax: .losslessSV1)
                .decodeManagedPixelFrame(inJLI, descriptor: rgb8, frameIndex: 0, budget: budget)
            #expect(outJLI.data.withUnsafeBytes { Data($0) } == rgb8Bytes)

            let inJLS = try owned(jlsRGB, budget: budget)
            let outJLS = try JPEGLSCodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrame(inJLS, descriptor: rgb8, frameIndex: 0, budget: budget)
            #expect(outJLS.data.withUnsafeBytes { Data($0) } == rgb8Bytes)
        }
        #expect(budget.receipt.currentTotal == baseline)

        // 3. JPEG XL signed 16-bit CT, XYB -> RGB descriptor, and .111 non-jbrd refusal
        let signedCT = PixelDataDescriptor(
            rows: 24, columns: 24, bitsAllocated: 16, bitsStored: 16, highBit: 15,
            isSigned: true, samplesPerPixel: 1, photometricInterpretation: .monochrome2
        )
        let signedBytes = Data((0..<(24 * 24)).flatMap { i -> [UInt8] in
            let s = Int16(truncatingIfNeeded: (i * 47) - 4096)
            let u = UInt16(bitPattern: s)
            return [UInt8(u & 0xFF), UInt8(u >> 8)]
        })
        let jxlSigned = try JXLCodec(encodingTransferSyntaxUID: TransferSyntax.jpegXLLossless.uid)
            .encodeFrame(signedBytes, descriptor: signedCT, frameIndex: 0, configuration: .lossless)
        do {
            let input = try owned(jxlSigned, budget: budget)
            let out = try JXLCodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrame(input, descriptor: signedCT, frameIndex: 0, budget: budget)
            #expect(out.data.withUnsafeBytes { Data($0) } == signedBytes)

            // .111 recompression decoder must refuse non-jbrd JXL input without fallback
            switch JXLCodec(decodingSyntax: .recompression)
                .decodeManagedPixelFrameOutcome(input, descriptor: signedCT, frameIndex: 0, budget: budget) {
            case .success(let unexpected):
                destroy(unexpected)
                Issue.record("Recompression decoder accepted non-jbrd JXL")
            case .failure(let failure):
                #expect(failure.code == .codecFailure)
            }
        }
        #expect(budget.receipt.currentTotal == baseline)

        let xybDesc = PixelDataDescriptor(
            rows: 16, columns: 16, bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 3, photometricInterpretation: .xyb, planarConfiguration: 0
        )
        let xybBytes = Data((0..<xybDesc.bytesPerFrame).map { UInt8(($0 * 7) & 0xFF) })
        let jxlXYB = try JXLCodec(encodingTransferSyntaxUID: TransferSyntax.jpegXLLossless.uid)
            .encodeFrame(xybBytes, descriptor: xybDesc, frameIndex: 0, configuration: .lossless)
        do {
            let input = try owned(jxlXYB, budget: budget)
            let out = try JXLCodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrame(input, descriptor: xybDesc, frameIndex: 0, budget: budget)
            #expect(out.descriptor.photometricInterpretation == .rgb)
            #expect(out.data.withUnsafeBytes { Data($0) } == xybBytes)
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("Pre-decode header bounds, lossless/family/RPCL enforcement, 8-in-16 widening and zero-staging refusal")
    func adversarialHeaderAndBudgetGuards() throws {
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal

        // 1. Staging admission refusal rejects every managed codec before materializing scratch/Data copies.
        for profile in ManagedCodecTests.managedProfiles {
            let d = descriptor(for: profile)
            let data = try encoded(profile, descriptor: d)
            let state = ExternalAllocationFixture()
            let zeroStagingBudget = try DICOMAllocationBudget.make(externalAdmission: state.callbacks).get()
            let input = try owned(data, budget: zeroStagingBudget)
            let before = zeroStagingBudget.receipt.currentTotal
            state.value.pointee.refuseResource = Int32(DICOMAllocationClass.staging.rawValue)
            #expect(throws: DICOMManagedFailure(allocation: .externalAdmissionRefused(45))) {
                _ = try decode(profile, frame: input, descriptor: d, budget: zeroStagingBudget)
            }
            #expect(zeroStagingBudget.receipt.peak.staging == 0)
            #expect(zeroStagingBudget.receipt.currentTotal == before)
        }

        // 2. Oversized codestream SIZ / SizeHeader rejected before staging admission (zero staging peak).
        let smallDesc = PixelDataDescriptor(
            rows: 8, columns: 8, bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1, photometricInterpretation: .monochrome2
        )
        let largerDesc = PixelDataDescriptor(
            rows: 32, columns: 32, bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1, photometricInterpretation: .monochrome2
        )
        let largerPixels = Data((0..<(32 * 32)).map { UInt8($0 & 0xFF) })
        let j2kOversized = try J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid)
            .encodeFrame(largerPixels, descriptor: largerDesc, frameIndex: 0, configuration: .lossless)
        let jxlOversized = try JXLCodec(encodingTransferSyntaxUID: TransferSyntax.jpegXLLossless.uid)
            .encodeFrame(largerPixels, descriptor: largerDesc, frameIndex: 0, configuration: .lossless)
        do {
            let state = ExternalAllocationFixture()
            let noStagingBudget = try DICOMAllocationBudget.make(externalAdmission: state.callbacks).get()
            let j2kIn = try owned(j2kOversized, budget: noStagingBudget)
            let jxlIn = try owned(jxlOversized, budget: noStagingBudget)
            state.value.pointee.refuseResource = Int32(DICOMAllocationClass.staging.rawValue)
            switch J2KSwiftCodec(decodingSyntax: .jpeg2000Lossless)
                .decodeManagedPixelFrameOutcome(j2kIn, descriptor: smallDesc, frameIndex: 0, budget: noStagingBudget) {
            case .success(let unexpected):
                destroy(unexpected)
                Issue.record("Mismatched SIZ dimensions bypassed pre-admission header check")
            case .failure(let failure):
                #expect(failure.code == .codecResultMismatch)
            }
            switch JXLCodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrameOutcome(jxlIn, descriptor: smallDesc, frameIndex: 0, budget: noStagingBudget) {
            case .success(let unexpected):
                destroy(unexpected)
                Issue.record("Mismatched JXL SizeHeader bypassed pre-admission header check")
            case .failure(let failure):
                #expect(failure.code == .codecResultMismatch)
            }
            #expect(noStagingBudget.receipt.peak.staging == 0)
        }

        // 3. JXL .110 lossless refuses VarDCT lossy streams; .112 accepts them.
        let rgb32 = PixelDataDescriptor(
            rows: 32, columns: 32, bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 3, photometricInterpretation: .rgb
        )
        let rgb32Pixels = Data((0..<rgb32.bytesPerFrame).map { UInt8(($0 * 13) & 0xFF) })
        let lossyCfg = CompressionConfiguration(quality: .medium, speed: .balanced, preferLossless: false)
        let jxlLossy = try JXLCodec(encodingTransferSyntaxUID: TransferSyntax.jpegXL.uid)
            .encodeFrame(rgb32Pixels, descriptor: rgb32, frameIndex: 0, configuration: lossyCfg)
        #expect(throws: DICOMError.self) {
            _ = try JXLCodec(decodingSyntax: .lossless).decodeFrame(jxlLossy, descriptor: rgb32, frameIndex: 0)
        }
        do {
            let input = try owned(jxlLossy, budget: budget)
            switch JXLCodec(decodingSyntax: .lossless)
                .decodeManagedPixelFrameOutcome(input, descriptor: rgb32, frameIndex: 0, budget: budget) {
            case .success(let unexpected):
                destroy(unexpected)
                Issue.record("JXL .110 lossless accepted VarDCT lossy codestream")
            case .failure(let failure):
                #expect(failure.code == .invalidDescriptor)
            }
            let ok = try JXLCodec(decodingSyntax: .general)
                .decodeManagedPixelFrame(input, descriptor: rgb32, frameIndex: 0, budget: budget)
            #expect(ok.data.count == rgb32.bytesPerFrame)
        }
        #expect(budget.receipt.currentTotal == baseline)

        // 4. J2K vs HTJ2K family CAP & .202 RPCL enforcement, Ssiz signedness/precision checks, and 8-in-16 widening.
        let gray8 = PixelDataDescriptor(
            rows: 16, columns: 16, bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1, photometricInterpretation: .monochrome2
        )
        let gray8Pixels = Data((0..<(16 * 16)).map { UInt8(($0 * 9) & 0xFF) })
        let part1Stream = try J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid)
            .encodeFrame(gray8Pixels, descriptor: gray8, frameIndex: 0, configuration: .lossless)
        let ht201Stream = try J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid)
            .encodeFrame(gray8Pixels, descriptor: gray8, frameIndex: 0, configuration: .lossless)
        let ht202Stream = try J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.htj2kRPCLLossless.uid)
            .encodeFrame(gray8Pixels, descriptor: gray8, frameIndex: 0, configuration: .lossless)
        do {
            let p1In = try owned(part1Stream, budget: budget)
            let ht201In = try owned(ht201Stream, budget: budget)
            let ht202In = try owned(ht202Stream, budget: budget)

            // Part-1 refused under HTJ2K; HTJ2K refused under Part-1
            #expect(throws: DICOMManagedFailure.self) {
                _ = try HTJ2KCodec(decodingSyntax: .lossless)
                    .decodeManagedPixelFrame(p1In, descriptor: gray8, frameIndex: 0, budget: budget)
            }
            #expect(throws: DICOMManagedFailure.self) {
                _ = try J2KSwiftCodec(decodingSyntax: .jpeg2000Lossless)
                    .decodeManagedPixelFrame(ht201In, descriptor: gray8, frameIndex: 0, budget: budget)
            }
            // Non-TLM/non-RPCL .201 refused under .202 rpclLossless; .202 succeeds
            #expect(throws: DICOMManagedFailure.self) {
                _ = try HTJ2KCodec(decodingSyntax: .rpclLossless)
                    .decodeManagedPixelFrame(ht201In, descriptor: gray8, frameIndex: 0, budget: budget)
            }
            let rpclOK = try HTJ2KCodec(decodingSyntax: .rpclLossless)
                .decodeManagedPixelFrame(ht202In, descriptor: gray8, frameIndex: 0, budget: budget)
            #expect(rpclOK.data.withUnsafeBytes { Data($0) } == gray8Pixels)

            // 8-bit codestream in 16-bit container (bitsAllocated=16, bitsStored=8) widens cleanly
            let wide8In16 = PixelDataDescriptor(
                rows: 16, columns: 16, bitsAllocated: 16, bitsStored: 8, highBit: 7,
                isSigned: false, samplesPerPixel: 1, photometricInterpretation: .monochrome2
            )
            let expectedWidened = Data(gray8Pixels.flatMap { [$0, 0] })
            let widenedJ2K = try J2KSwiftCodec(decodingSyntax: .jpeg2000Lossless)
                .decodeManagedPixelFrame(p1In, descriptor: wide8In16, frameIndex: 0, budget: budget)
            #expect(widenedJ2K.data.withUnsafeBytes { Data($0) } == expectedWidened)
            #expect(try J2KSwiftCodec(decodingSyntax: .jpeg2000Lossless)
                .decodeFrame(part1Stream, descriptor: wide8In16, frameIndex: 0) == expectedWidened)

            // Signedness mismatch (unsigned codestream under signed descriptor) refused
            let signedMismatch = PixelDataDescriptor(
                rows: 16, columns: 16, bitsAllocated: 16, bitsStored: 8, highBit: 7,
                isSigned: true, samplesPerPixel: 1, photometricInterpretation: .monochrome2
            )
            #expect(throws: DICOMManagedFailure.self) {
                _ = try J2KSwiftCodec(decodingSyntax: .jpeg2000Lossless)
                    .decodeManagedPixelFrame(p1In, descriptor: signedMismatch, frameIndex: 0, budget: budget)
            }
        }
        #expect(budget.receipt.currentTotal == baseline)

        // 5. RLE header slack bytes (offsets[0] > 64) or non-zero unused offset slots refused.
        var rleSlack = Data(count: 68)
        rleSlack[0] = 1
        rleSlack[4] = 68 // offsets[0] = 68 instead of 64
        rleSlack.append(contentsOf: [0x00, 0x2A])
        do {
            let rleDesc = PixelDataDescriptor(
                rows: 1, columns: 1, bitsAllocated: 8, bitsStored: 8, highBit: 7,
                isSigned: false, samplesPerPixel: 1, photometricInterpretation: .monochrome2
            )
            let inSlack = try owned(rleSlack, budget: budget)
            #expect(throws: DICOMManagedFailure.self) {
                _ = try RLECodec().decodeManagedPixelFrame(inSlack, descriptor: rleDesc, frameIndex: 0, budget: budget)
            }
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("Managed 16-bit legacy unclamped-MAXVAL JPEG-LS recovery releases staging and preserves tight-budget failures")
    func managedLegacyUnclampedJPEGLSRecoveryAndBudgetBounds() async throws {
        let width = 32
        let height = 32
        var pixels = Data(capacity: width * height * 2)
        for y in 0..<height {
            for x in 0..<width {
                let signedCT = Int16(truncatingIfNeeded: -1024 + ((x * 431 + y * 1307) % 3600))
                let word = UInt16(bitPattern: signedCT)
                pixels.append(UInt8(word & 0xFF))
                pixels.append(UInt8((word >> 8) & 0xFF))
            }
        }
        let desc = PixelDataDescriptor(
            rows: height,
            columns: width,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            isSigned: true,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let legacyStream = try await JPEGLSCodecStrictDecodingTests.makeLegacyUnclampedCodestream(
            pixels: pixels,
            width: width,
            height: height,
            bitsPerSample: 16
        )

        // 1. Managed decode recovers exact signed 16-bit CT samples (including DICOM PS3.5
        //    even-length 0x00 fragment padding) with zero retained staging.
        var variants: [Data] = [legacyStream]
        if legacyStream.count % 2 == 1 {
            var padded = legacyStream
            padded.append(0x00)
            variants.append(padded)
        } else {
            for seed in 1...32 {
                var altPixels = Data(capacity: width * height * 2)
                for i in 0..<(width * height) {
                    let signedCT = Int16(truncatingIfNeeded: -1024 + ((i * (331 + seed * 19) + seed * 53) % 3900))
                    let word = UInt16(bitPattern: signedCT)
                    altPixels.append(UInt8(word & 0xFF))
                    altPixels.append(UInt8((word >> 8) & 0xFF))
                }
                let altRaw = try await JPEGLSCodecStrictDecodingTests.makeLegacyUnclampedCodestream(
                    pixels: altPixels,
                    width: width,
                    height: height,
                    bitsPerSample: 16
                )
                if altRaw.count % 2 == 1 {
                    var padded = altRaw
                    padded.append(0x00)
                    let padBudget = try DICOMAllocationBudget()
                    let padBase = padBudget.receipt.currentTotal
                    do {
                        let padBuf = try owned(padded, budget: padBudget)
                        let padFrame = try JPEGLSCodec(decodingSyntax: .lossless, missingPresetPolicy: .allowLegacyUnclampedRecovery)
                            .decodeManagedPixelFrame(padBuf, descriptor: desc, frameIndex: 0, budget: padBudget)
                        #expect(padBudget.receipt.current.staging == 0)
                        #expect(padFrame.data.withUnsafeBytes { Data($0) } == altPixels)
                        destroy(padFrame)
                        destroy(padBuf)
                    }
                    #expect(padBudget.receipt.currentTotal == padBase)
                    break
                }
            }
        }
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal
        for streamVariant in variants {
            let encodedBuf = try owned(streamVariant, budget: budget)
            let frame = try JPEGLSCodec(decodingSyntax: .lossless, missingPresetPolicy: .allowLegacyUnclampedRecovery)
                .decodeManagedPixelFrame(encodedBuf, descriptor: desc, frameIndex: 0, budget: budget)
            #expect(budget.receipt.current.staging == 0)
            #expect(frame.data.count == desc.bytesPerFrame)
            #expect(budget.receipt.current.decoded == frame.data.capacity)
            #expect(frame.data.withUnsafeBytes { Data($0) } == pixels)
            destroy(frame)
            destroy(encodedBuf)
        }
        #expect(budget.receipt.currentTotal == baseline)

        // 2. Tight budget with zero room for fallback staging on a corrupt 16-bit stream
        //    preserves .codecFailure instead of turning into an allocation failure.
        let validStandard = try JPEGLSCodec().encodeFrame(pixels, descriptor: desc, frameIndex: 0, configuration: .lossless)
        var corrupt16 = Data(validStandard.prefix(max(24, validStandard.count / 2)))
        corrupt16.append(contentsOf: [0xFF, 0xD9])
        // Measure exact primary workspace + metadata ceiling using an explicit-LSE stream (no fallback).
        let sosRange = try #require(corrupt16.range(of: Data([0xFF, 0xDA])))
        var explicitLSECorrupt = Data()
        explicitLSECorrupt.append(corrupt16[..<sosRange.lowerBound])
        explicitLSECorrupt.append(contentsOf: [
            0xFF, 0xF8, 0x00, 0x0D, 0x01,
            0xFF, 0xFF, 0x00, 0x12, 0x00, 0x43, 0x01, 0x14, 0x00, 0x40
        ])
        explicitLSECorrupt.append(corrupt16[sosRange.lowerBound...])

        let probeBudget = try DICOMAllocationBudget()
        do {
            let probeIn = try owned(explicitLSECorrupt, budget: probeBudget)
            let probeOut = JPEGLSCodec(decodingSyntax: .lossless, missingPresetPolicy: .allowLegacyUnclampedRecovery)
                .decodeManagedPixelFrameOutcome(probeIn, descriptor: desc, frameIndex: 0, budget: probeBudget)
            switch probeOut {
            case .success:
                Issue.record("Corrupt 16-bit stream unexpectedly decoded")
            case .failure(let f):
                #expect(f.code == .codecFailure)
            }
        }
        let tightBudget = try DICOMAllocationBudget(limits: .init(total: probeBudget.receipt.peakTotal))
        let tightBaseline = tightBudget.receipt.currentTotal
        do {
            let tightIn = try owned(corrupt16, budget: tightBudget)
            let tightOut = JPEGLSCodec(decodingSyntax: .lossless, missingPresetPolicy: .allowLegacyUnclampedRecovery)
                .decodeManagedPixelFrameOutcome(tightIn, descriptor: desc, frameIndex: 0, budget: tightBudget)
            switch tightOut {
            case .success:
                Issue.record("Corrupt 16-bit stream unexpectedly decoded under tight budget")
            case .failure(let f):
                #expect(f.code == .codecFailure)
            }
        }
        #expect(tightBudget.receipt.currentTotal == tightBaseline)
    }
}

private struct ManagedCancellationState: ~Copyable {
    let budget: DICOMAllocationBudget
    var observedDecodedOwner = false
}

private func cancelAfterOutputAdmission(_ raw: UnsafeMutableRawPointer?) -> Bool {
    guard let raw else { return false }
    let state = raw.assumingMemoryBound(to: ManagedCancellationState.self)
    if state.pointee.budget.receipt.current.decoded > 0 {
        state.pointee.observedDecodedOwner = true
        return true
    }
    return false
}
