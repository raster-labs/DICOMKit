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
    private func owned(_ data: Data, budget: DICOMAllocationBudget) throws -> DICOMByteBuffer {
        try DICOMByteBuffer(count: data.count, budget: budget, resource: .encoded) { output in
            data.withUnsafeBytes { output.copyMemory(from: $0) }
        }
    }
    private func jpeg(_ profile: String) -> JLICodec {
        let uid = profile == "rgb" ? TransferSyntax.jpegBaseline.uid : TransferSyntax.jpegLosslessSV1.uid
        return JLICodec(encodingTransferSyntaxUID: uid, decodingTransferSyntaxUID: uid)
    }
    private func encoded(_ profile: String, descriptor: PixelDataDescriptor) throws -> Data {
        let source = bytes(descriptor)
        if profile == "ls" { return try JPEGLSCodec().encodeFrame(source, descriptor: descriptor, frameIndex: 1, configuration: .lossless) }
        return try jpeg(profile).encodeFrame(source, descriptor: descriptor, frameIndex: 1, configuration: .lossless)
    }
    private func decode(_ profile: String, frame: DICOMByteBuffer, descriptor: PixelDataDescriptor,
                        budget: DICOMAllocationBudget) throws -> ManagedDecodedPixelFrame {
        if profile == "ls" {
            return try JPEGLSCodec(decodingTransferSyntaxUID: TransferSyntax.jpegLSLossless.uid)
                .decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget)
        }
        return try jpeg(profile).decodeManagedPixelFrame(frame, descriptor: descriptor, frameIndex: 1, budget: budget)
    }

    @Test("Managed bytes retain policy, frame identity and complete backing ownership", arguments: ["ls", "lossless", "rgb"])
    func parityAndLifetime(profile: String) throws {
        let d = descriptor(rgb: profile == "rgb")
        let data = try encoded(profile, descriptor: d)
        let legacy = profile == "ls" ? try JPEGLSCodec().decodePixelFrame(data, descriptor: d, frameIndex: 1) :
            try jpeg(profile).decodePixelFrame(data, descriptor: d, frameIndex: 1)
        let budget = try DICOMAllocationBudget()
        var input: DICOMByteBuffer? = try owned(data, budget: budget)
        var result: ManagedDecodedPixelFrame? = try decode(profile, frame: #require(input), descriptor: d, budget: budget)
        #expect(result?.sourceFrameIndex == 1)
        #expect(result?.descriptor.photometricInterpretation == legacy.descriptor.photometricInterpretation)
        #expect(result?.data.withUnsafeBytes { Data($0) } == legacy.data)
        #expect(result?.data.count == legacy.data.count)
        let capacity = try #require(result?.data.capacity)
        let expected = try DICOMByteBuffer.backingCapacity(for: d.rows * d.columns * (profile == "rgb" ? 12 : 2))
        #expect(capacity == expected)
        #expect(budget.receipt.current.decoded == capacity)
        #expect(budget.receipt.current.staging == 0)
        var alias = result?.data
        try alias?.transfer(to: .resident)
        result = nil; input = nil
        #expect(budget.receipt.current.encoded == 0 && budget.receipt.current.decoded == 0)
        #expect(budget.receipt.current.resident == capacity)
        #expect(alias?.withUnsafeBytes { Data($0) } == legacy.data)
        alias = nil
        #expect(budget.receipt.currentTotal == 0 && budget.receipt.liveAllocations == 0)
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
                #expect(throws: DICOMAllocationError.limitExceeded(.decoded)) { try decode(profile, frame: input, descriptor: d, budget: budget) }
            }
            #expect(budget.receipt.currentTotal == before)
        }
        // Fail each controlled backing seam. Successful later seams also release.
        for failureAfter in 1...4 {
            let budget = try DICOMAllocationBudget(allocationFailureAfter: failureAfter)
            let input = try owned(data, budget: budget)
            let before = budget.receipt.currentTotal
            do { _ = try decode(profile, frame: input, descriptor: d, budget: budget) }
            catch DICOMAllocationError.allocationFailed {}
            #expect(budget.receipt.currentTotal == before)
        }
    }

    @Test("Precision recovery remains explicit and excludes all mapping tables")
    func recovery() throws {
        let source = descriptor(bits: 12), actual = descriptor(bits: 16)
        let data = try encoded("ls", descriptor: actual)
        let budget = try DICOMAllocationBudget()
        let input = try owned(data, budget: budget)
        #expect(throws: DICOMError.self) {
            try JPEGLSCodec().decodeManagedPixelFrame(input, descriptor: source, frameIndex: 1, budget: budget)
        }
        let codec = JPEGLSCodec(decodingTransferSyntaxUID: TransferSyntax.jpegLSLossless.uid,
            precisionPolicy: .useCodestreamForUnsignedMonochrome)
        let recovered = try codec.decodeManagedPixelFrame(input, descriptor: source, frameIndex: 1, budget: budget)
        #expect(recovered.descriptor.bitsStored == 16 && source.bitsStored == 12)
        #expect(recovered.diagnostics == [.sourcePrecisionMismatch(sourceBitsStored: 12, encodedPrecision: 16)])
        #expect(recovered.data.withUnsafeBytes { Data($0) } == bytes(actual))
        // Unselected, empty table still disqualifies precision recovery.
        var mapping = data
        mapping.insert(contentsOf: [0xff, 0xf8, 0, 5, 2, 5, 2], at: mapping.count - 2)
        let mapped = try owned(mapping, budget: budget)
        #expect(throws: DICOMError.self) { try codec.decodeManagedPixelFrame(mapped, descriptor: source, frameIndex: 1, budget: budget) }
        #expect(throws: DICOMError.self) { try codec.decodePixelFrame(mapping, descriptor: source, frameIndex: 1) }
    }

    @Test("Cancellation and malformed input do not transfer or retain partial output", arguments: ["ls", "lossless", "rgb"])
    func cancellation(profile: String) async throws {
        let d = descriptor(rgb: profile == "rgb")
        let data = try encoded(profile, descriptor: d)
        let budget = try DICOMAllocationBudget()
        let input = try owned(data, budget: budget)
        let before = budget.receipt.currentTotal
        let unrelated = try DICOMAllocationBudget()
        #expect(throws: DICOMAllocationError.budgetMismatch) { try decode(profile, frame: input, descriptor: d, budget: unrelated) }
        #expect(unrelated.receipt.peakTotal == 0)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try decode(profile, frame: input, descriptor: d, budget: budget)
        }
        do { _ = try await task.value; Issue.record("Cancelled managed decode published output") }
        catch is CancellationError {}
        #expect(budget.receipt.currentTotal == before)
        let malformed = try owned(Data(data.dropLast(2)), budget: budget)
        let retained = budget.receipt.currentTotal
        #expect(throws: (any Error).self) { try decode(profile, frame: malformed, descriptor: d, budget: budget) }
        #expect(budget.receipt.currentTotal == retained)
    }
}
