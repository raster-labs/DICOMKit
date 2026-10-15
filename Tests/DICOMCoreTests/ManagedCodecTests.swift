import Foundation
import Testing
@testable import DICOMCore

@Suite("Managed codec payload ownership")
struct ManagedCodecTests {
    private func descriptor(rgb: Bool = false, bits: Int = 12) -> PixelDataDescriptor {
        PixelDataDescriptor(rows: 65, columns: 129, numberOfFrames: 2,
            bitsAllocated: rgb ? 8 : 16, bitsStored: rgb ? 8 : bits, highBit: rgb ? 7 : bits - 1,
            isSigned: false, samplesPerPixel: rgb ? 3 : 1,
            photometricInterpretation: rgb ? .ybrFull422 : .monochrome2, planarConfiguration: 0)
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
        if profile == "ls" { return try JPEGLSCodec().encodeFrame(source, descriptor: descriptor, frameIndex: 1, configuration: .lossless) }
        return try jpeg(profile).encodeFrame(source, descriptor: descriptor, frameIndex: 1, configuration: .lossless)
    }
    private func decode(_ profile: String, frame: borrowing DICOMByteBuffer, descriptor: PixelDataDescriptor,
                        budget: borrowing DICOMAllocationBudget, cancellation: DICOMCancellation = .never)
        throws(DICOMManagedFailure) -> ManagedDecodedPixelFrame {
        if profile == "ls" {
            return try JPEGLSCodec(decodingTransferSyntaxUID: TransferSyntax.jpegLSLossless.uid)
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget, cancellation: cancellation)
        }
        return try jpeg(profile).decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget, cancellation: cancellation)
    }

    private func decodeQualified(_ profile: String, frame: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor, budget: borrowing DICOMAllocationBudget,
        cancellation: DICOMCancellation = .never) throws(DICOMManagedFailure) -> ManagedDecodedPixelFrame {
        let execution: DICOMExecutionReservation
        do throws(DICOMAllocationError) { execution = try DICOMExecutionReservation(budget: budget) }
        catch { throw DICOMManagedFailure(allocation: error) }
        if profile == "ls" {
            return try JPEGLSCodec(decodingTransferSyntaxUID: TransferSyntax.jpegLSLossless.uid)
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget,
                                         execution: execution, cancellation: cancellation)
        }
        return try jpeg(profile).decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1,
            budget: budget, execution: execution, cancellation: cancellation)
    }

    // The harness prepares codecs, fixtures, callback storage and the worker outside
    // the qualified operation. These function types prove the selected entry cannot throw.
    private func decodeQualifiedOutcome(_ profile: String, frame: borrowing DICOMByteBuffer,
        descriptor: PixelDataDescriptor, budget: borrowing DICOMAllocationBudget,
        cancellation: DICOMCancellation = .never) -> DICOMManagedOutcome<ManagedDecodedPixelFrame> {
        let ls = JPEGLSCodec(decodingTransferSyntaxUID: TransferSyntax.jpegLSLossless.uid)
        let jli = jpeg(profile)
        let execution: DICOMExecutionReservation
        switch DICOMExecutionReservation.reserve(budget: budget) {
        case .success(let value): execution = value
        case .failure(let failure): return .failure(DICOMManagedFailure(allocation: failure))
        }
        typealias QualifiedDecode = (borrowing DICOMByteBuffer, PixelDataDescriptor, Int,
            borrowing DICOMAllocationBudget, borrowing DICOMExecutionReservation,
            DICOMCancellation) -> DICOMManagedOutcome<ManagedDecodedPixelFrame>
        if profile == "ls" {
            let operation: QualifiedDecode = ls.decodeManagedPixelFrameOutcome
            return operation(frame, descriptor, 1, budget, execution, cancellation)
        }
        let operation: QualifiedDecode = jli.decodeManagedPixelFrameOutcome
        return operation(frame, descriptor, 1, budget, execution, cancellation)
    }

    @Test("Every managed codec propagates aggregate refusal and retains admitted output identity",
          arguments: ["ls", "lossless", "rgb"])
    func externalAggregateAdmission(profile: String) throws {
        let d = descriptor(rgb: profile == "rgb")
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
          arguments: ["ls", "lossless", "rgb"])
    func directOutcomeFailures(profile: String) throws {
        let d = descriptor(rgb: profile == "rgb")
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

    @Test("Managed bytes retain policy, frame identity and complete backing ownership", arguments: ["ls", "lossless", "rgb"])
    func parityAndLifetime(profile: String) throws {
        let d = descriptor(rgb: profile == "rgb")
        let data = try encoded(profile, descriptor: d)
        let legacy = profile == "ls" ? try JPEGLSCodec().decodePixelFrame(data, descriptor: d, frameIndex: 1) :
            try jpeg(profile).decodePixelFrame(data, descriptor: d, frameIndex: 1)
        let budget = try DICOMAllocationBudget()
        let input = try owned(data, budget: budget)
        let result = try decodeQualified(profile, frame: input, descriptor: d, budget: budget)
        #expect(result.sourceFrameIndex == 1)
        #expect(result.descriptor.photometricInterpretation == legacy.descriptor.photometricInterpretation)
        let decodedData = result.data.withUnsafeBytes { Data($0) }
        #expect(decodedData == legacy.data)
        #expect(result.data.count == legacy.data.count)
        let capacity = result.data.capacity
        let expected = try DICOMByteBuffer.backingCapacity(for: d.rows * d.columns * (profile == "rgb" ? 12 : 2))
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

    @Test("Exact capacity succeeds and one-byte-short admission releases temporaries", arguments: ["ls", "lossless", "rgb"])
    func capsAndFailures(profile: String) throws {
        let d = descriptor(rgb: profile == "rgb")
        let data = try encoded(profile, descriptor: d)
        let capacity = try DICOMByteBuffer.backingCapacity(for: d.rows * d.columns * (profile == "rgb" ? 12 : 2))
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

    @Test("Cancellation and malformed input do not transfer or retain partial output", arguments: ["ls", "lossless", "rgb"])
    func cancellation(profile: String) throws {
        let d = descriptor(rgb: profile == "rgb")
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
        let malformed = try owned(Data(data.dropLast(2)), budget: budget)
        let retained = budget.receipt.currentTotal
        #expect(throws: DICOMManagedFailure.self) { _ = try decode(profile, frame: malformed, descriptor: d, budget: budget) }
        #expect(budget.receipt.currentTotal == retained)
    }

    @Test("Cancellation after output admission releases output, scratch and execution reservation",
          arguments: ["ls", "lossless", "rgb"])
    func cancellationAfterAdmission(profile: String) throws {
        let d = descriptor(rgb: profile == "rgb")
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
