import Foundation
import Testing
@testable import DICOMCore

@Suite("Explicit backing allocation ownership")
struct DICOMAllocationBudgetTests {
    @Test("Page capacity is checked before allocation", arguments: [0, 1, 16384, 16385])
    func capacity(_ count: Int) throws {
        let page = AlignedPixelBuffer.pageSize
        let expected = max(page, (count + page - 1) / page * page)
        #expect(try DICOMByteBuffer.backingCapacity(for: count) == expected)
        #expect(throws: DICOMAllocationError.invalidSize) { try DICOMByteBuffer.backingCapacity(for: -1) }
        #expect(throws: DICOMAllocationError.invalidSize) { try DICOMByteBuffer.backingCapacity(for: Int.max) }
        #expect(AlignedPixelBuffer(byteCount: Int.max) == nil)
    }
    @Test("Exact fit and one byte over class/aggregate caps")
    func caps() throws {
        let budget = try DICOMAllocationBudget(limits: .init(encoded: 10, decoded: 10, staging: 10, total: 15))
        let encoded = try budget.reserve(10, as: .encoded)
        #expect(throws: DICOMAllocationError.limitExceeded(.encoded)) { try budget.reserve(1, as: .encoded) }
        let staging = try budget.reserve(5, as: .metadata)
        #expect(throws: DICOMAllocationError.totalLimitExceeded) { try budget.reserve(1, as: .decoded) }
        #expect(budget.receipt.currentTotal == 15)
        withExtendedLifetime((encoded, staging)) {}
    }
    @Test("Metadata and staging share one cap")
    func metadataCap() throws {
        let budget = try DICOMAllocationBudget(limits: .init(staging: 9))
        let metadata = try budget.reserve(5, as: .metadata)
        let staging = try budget.reserve(4, as: .staging)
        #expect(throws: DICOMAllocationError.limitExceeded(.metadata)) { try budget.reserve(1, as: .metadata) }
        withExtendedLifetime((metadata, staging)) {}
    }
    @Test("Aliases share a charge; copying and transfer have independent ownership")
    func aliases() throws {
        let budget = try DICOMAllocationBudget()
        var owner: DICOMByteBuffer? = try DICOMByteBuffer(count: 17, budget: budget, resource: .decoded) {
            $0.initializeMemory(as: UInt8.self, repeating: 0x5a)
        }
        let charged = budget.receipt.currentTotal
        var alias = owner
        owner = nil
        #expect(budget.receipt.currentTotal == charged)
        var copy = try alias?.copy(budget: budget, resource: .encoded)
        #expect(budget.receipt.currentTotal == 2 * charged)
        #expect(copy?.withUnsafeBytes { $0.allSatisfy { $0 == 0x5a } } == true)
        try alias?.transfer(to: .resident)
        #expect(budget.receipt.current.decoded == 0)
        #expect(budget.receipt.current.resident == AlignedPixelBuffer.pageSize)
        #expect(throws: DICOMAllocationError.alreadyTransferred) { try alias?.transfer(to: .preview) }
        alias = nil
        #expect(budget.receipt.currentTotal == charged)
        copy = nil
        #expect(budget.receipt.currentTotal == 0)
        #expect(budget.receipt.liveAllocations == 0)
    }
    @Test("Failed transfer rolls back without consuming the transfer")
    func transferFailure() throws {
        let budget = try DICOMAllocationBudget(limits: .init(resident: 1))
        let lease = try budget.reserve(2, as: .decoded)
        let receipt = budget.receipt
        #expect(throws: DICOMAllocationError.limitExceeded(.resident)) { try lease.transfer(to: .resident) }
        #expect(budget.receipt == receipt)
        try lease.transfer(to: .encoded)
        #expect(budget.receipt.current.encoded == 2)
    }
    @Test("Allocation and initialization failures release all overlapping reservations")
    func failure() throws {
        let failed = try DICOMAllocationBudget(allocationFailureAfter: 0)
        #expect(throws: DICOMAllocationError.allocationFailed) {
            try DICOMByteBuffer(count: 1, budget: failed, resource: .encoded) { _ in }
        }
        #expect(failed.receipt.currentTotal == 0)
        let budget = try DICOMAllocationBudget()
        #expect(throws: CancellationError.self) {
            try DICOMByteBuffer(count: 1, budget: budget, resource: .encoded) { _ in throw CancellationError() }
        }
        #expect(budget.receipt.currentTotal == 0)
        #expect(budget.receipt.peakTotal == AlignedPixelBuffer.pageSize + DICOMByteBuffer.controlCapacity)
    }
    @Test("Concurrent reservations cannot oversubscribe one ledger")
    func concurrency() async throws {
        let budget = try DICOMAllocationBudget(limits: .init(encoded: 100, total: 100))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    let lease = try? budget.reserve(10, as: .encoded)
                    await Task.yield()
                    withExtendedLifetime(lease) { #expect(budget.receipt.currentTotal <= 100) }
                }
            }
        }
        #expect(budget.receipt.currentTotal == 0)
        #expect(budget.receipt.peakTotal <= 100)
    }
    @Test("Controlled container failure preserves old storage and destroys references once")
    func vectorFailure() throws {
        let budget = try DICOMAllocationBudget(allocationFailureAfter: 1)
        let counter = DestructionCounter()
        var initialized = 0
        do {
            let vector = try DICOMStorageVector<TrackedValue>(budget: budget)
            try vector.append(TrackedValue(counter))
            let capacity = vector.capacity
            initialized = capacity
            for _ in 1..<capacity { try vector.append(TrackedValue(counter)) }
            let before = budget.receipt.currentTotal
            #expect(throws: DICOMAllocationError.allocationFailed) { try vector.append(TrackedValue(counter)) }
            #expect(vector.count == capacity)
            #expect(budget.receipt.currentTotal == before)
            #expect(counter.value == 1) // rejected append value only
            #expect(vector[0].counter === counter)
        }
        #expect(budget.receipt.currentTotal == 0)
        #expect(counter.value == initialized + 1)
    }

    @Test("Container growth reports old and new capacity simultaneously")
    func vectorGrowth() throws {
        let budget = try DICOMAllocationBudget()
        do {
            let vector = try DICOMStorageVector<UInt64>(budget: budget)
            try vector.append(1)
            let initialCapacity = vector.capacity
            for value in 1...initialCapacity { try vector.append(UInt64(value)) }
            let page = AlignedPixelBuffer.pageSize
            #expect(vector.count == initialCapacity + 1)
            #expect(budget.receipt.current.metadata == DICOMByteBuffer.controlCapacity + 2 * page)
            #expect(budget.receipt.peak.metadata == DICOMByteBuffer.controlCapacity + 3 * page)
            #expect(vector[initialCapacity] == UInt64(initialCapacity))
        }
        #expect(budget.receipt.currentTotal == 0)
    }

    @Test("Concurrent transfer attempts transfer exactly once")
    func concurrentTransfer() async throws {
        let budget = try DICOMAllocationBudget()
        let lease = try budget.reserve(10, as: .decoded)
        let succeeded = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    do { try lease.transfer(to: .resident); return true }
                    catch { return false }
                }
            }
            var success = 0
            for await value in group { if value { success += 1 } }
            return success
        }
        #expect(succeeded == 1)
        #expect(budget.receipt.current.resident == 10)
        #expect(budget.receipt.currentTotal == 10)
        withExtendedLifetime(lease) {}
    }

    @Test("Cancelled workers and independent subscribers retain charges until actual late return")
    func workerLifetime() async throws {
        let budget = try DICOMAllocationBudget()
        let ready = AsyncStream<Void>.makeStream()
        let gate = WorkerGate()
        func launch() -> Task<DICOMByteBuffer, Error> {
            Task.detached {
                let frame = try DICOMByteBuffer(count: 10, budget: budget, resource: .decoded) { _ in }
                ready.continuation.yield(())
                await gate.wait() // models a synchronous backend that has not returned
                return frame
            }
        }
        var first: Task<DICOMByteBuffer, Error>? = launch()
        var second: Task<DICOMByteBuffer, Error>? = launch()
        var iterator = ready.stream.makeAsyncIterator()
        _ = await iterator.next(); _ = await iterator.next()
        let before = budget.receipt.currentTotal
        #expect(before == 2 * (AlignedPixelBuffer.pageSize + DICOMByteBuffer.controlCapacity))
        first?.cancel(); second?.cancel() // shutdown/cancellation does not release storage
        #expect(budget.receipt.currentTotal == before)
        await gate.open()
        var output = try await first?.value
        var otherOutput = try await second?.value
        first = nil; second = nil
        #expect(otherOutput?.count == 10)
        var subscriber = output
        output = nil
        #expect(budget.receipt.currentTotal == before)
        try subscriber?.transfer(to: .resident)
        otherOutput = nil
        #expect(budget.receipt.currentTotal == before / 2)
        subscriber = nil
        #expect(budget.receipt.currentTotal == 0)
        ready.continuation.finish()
        withExtendedLifetime(otherOutput) {}
    }

}


private actor WorkerGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}
private final class DestructionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
private final class TrackedValue {
    let counter: DestructionCounter
    init(_ counter: DestructionCounter) { self.counter = counter }
    deinit { counter.increment() }
}
