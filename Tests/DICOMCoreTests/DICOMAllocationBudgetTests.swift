import Testing
@testable import DICOMCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite("Mapped allocation ownership")
struct DICOMAllocationBudgetTests {
    private var page: Int { DICOMByteBuffer.controlCapacity }

    private func destroy(_ buffer: consuming DICOMByteBuffer) {}
    private func destroy(_ lease: consuming DICOMAllocationLease) {}
    private func destroy(_ execution: consuming DICOMExecutionReservation) {}

    @Test("Nonthrowing allocation entry points retain scalar failures and roll back admitted maps")
    func directAllocationOutcomes() {
        let make: (DICOMAllocationBudget.Limits) -> DICOMAllocationOutcome<DICOMAllocationBudget> =
            DICOMAllocationBudget.make
        let allocate: (Int, Int?, borrowing DICOMAllocationBudget, DICOMAllocationClass)
            -> DICOMAllocationOutcome<DICOMByteBuffer> = DICOMByteBuffer.allocate
        let rounding: (Int) -> DICOMAllocationOutcome<Int> = DICOMByteBuffer.backingCapacityOutcome
        switch make(.init(staging: page - 1)) {
        case .success: Issue.record("Ledger bootstrap exceeded its metadata cap")
        case .failure(let failure): #expect(failure == .limitExceeded(.metadata))
        }
        switch rounding(Int.max) {
        case .success: Issue.record("Overflowing capacity was accepted")
        case .failure(let failure): #expect(failure == .invalidSize)
        }
        let budget: DICOMAllocationBudget
        switch DICOMAllocationBudget.make(allocationFailureAfter: 1) {
        case .success(let value): budget = value
        case .failure: Issue.record("Test ledger creation failed"); return
        }
        switch allocate(7, nil, budget, .decoded) {
        case .success(let unexpected): destroy(unexpected); Issue.record("Injected payload-map failure was ignored")
        case .failure(let failure): #expect(failure == .allocationFailed)
        }
        #expect(budget.receipt.currentTotal == page)
        #expect(budget.receipt.current.decoded == 0)
        #expect(budget.receipt.liveAllocations == 1)
        #expect(budget.receipt.peakTotal == 3 * page)
    }

    @Test("Ledger bootstrap is real metadata, refused before mapping when it cannot fit")
    func bootstrap() throws {
        #expect(throws: DICOMAllocationError.limitExceeded(.metadata)) {
            _ = try DICOMAllocationBudget(limits: .init(staging: page - 1))
        }
        #expect(throws: DICOMAllocationError.totalLimitExceeded) {
            _ = try DICOMAllocationBudget(limits: .init(total: page - 1))
        }
        let budget = try DICOMAllocationBudget()
        let alias = try budget.share()
        let sameOwner = budget.isSameOwner(as: alias)
        #expect(sameOwner)
        let receipt = budget.receipt
        #expect(receipt.current.metadata == page)
        #expect(receipt.currentTotal == page)
        #expect(receipt.liveAllocations == 1)
        #expect(alias.receipt == receipt)
    }

    @Test("Rounding validates overflow and includes empty payload capacity")
    func rounding() throws {
        #expect(try DICOMByteBuffer.backingCapacity(for: 0) == page)
        #expect(try DICOMByteBuffer.backingCapacity(for: page) == page)
        #expect(try DICOMByteBuffer.backingCapacity(for: page + 1) == 2 * page)
        #expect(throws: DICOMAllocationError.invalidSize) { _ = try DICOMByteBuffer.backingCapacity(for: -1) }
        #expect(throws: DICOMAllocationError.invalidSize) { _ = try DICOMByteBuffer.backingCapacity(for: Int.max) }
    }

    @Test("Aliases retain complete reconstruction capacity and transfer once")
    func aliasAndTransfer() throws {
        let budget = try DICOMAllocationBudget()
        let buffer = try DICOMByteBuffer(count: 3, capacity: page + 1, budget: budget, resource: .decoded)
        buffer.unsafeMutableBytes[0] = 17
        let alias = try buffer.share()
        let sharesBacking = buffer.sameBacking(as: alias)
        #expect(sharesBacking)
        #expect(buffer.count == 3)
        #expect(buffer.capacity == 2 * page)
        #expect(buffer.controlByteCount == page)
        #expect(buffer.retainedByteCount == 3 * page)
        let hasExpectedOwner = buffer.isOwned(by: budget)
        #expect(hasExpectedOwner)
        let owned = budget.receipt
        #expect(owned.current.metadata == 2 * page)
        #expect(owned.current.decoded == 2 * page)
        #expect(owned.currentTotal == 4 * page)
        destroy(buffer)
        #expect(budget.receipt == owned)
        let retainedBytesMatch = alias.withUnsafeBytes { $0.count == 3 && $0[0] == 17 }
        #expect(retainedBytesMatch)
        try alias.transfer(to: .resident)
        #expect(budget.receipt.current.decoded == 0)
        #expect(budget.receipt.current.resident == 2 * page)
        #expect(throws: DICOMAllocationError.alreadyTransferred) { try alias.transfer(to: .preview) }
        destroy(alias)
        #expect(budget.receipt.currentTotal == page)
        #expect(budget.receipt.liveAllocations == 1)
    }

    @Test("Copy admits separate bytes while source and both control pages remain live")
    func copying() throws {
        let budget = try DICOMAllocationBudget()
        let source = try DICOMByteBuffer(count: 2, capacity: 2 * page, budget: budget, resource: .encoded)
        source.unsafeMutableBytes[0] = 71
        let copy = try source.copy(budget: budget, resource: .decoded)
        let sharesBacking = source.sameBacking(as: copy)
        #expect(!sharesBacking)
        #expect(copy.capacity == page)
        let copiedByteMatches = copy.withUnsafeBytes { $0[0] == 71 }
        #expect(copiedByteMatches)
        #expect(budget.receipt.currentTotal == 6 * page)
        #expect(budget.receipt.peakTotal == 6 * page)
        destroy(source)
        #expect(budget.receipt.currentTotal == 3 * page)
        destroy(copy)
        #expect(budget.receipt.currentTotal == page)
    }

    @Test("Admission and both mmap failure sites roll back without releasing other owners")
    func failures() throws {
        for failAfter in 0...1 {
            let budget = try DICOMAllocationBudget(allocationFailureAfter: failAfter)
            #expect(throws: DICOMAllocationError.allocationFailed) {
                _ = try DICOMByteBuffer(count: 7, budget: budget, resource: .encoded)
            }
            #expect(budget.receipt.currentTotal == page)
            #expect(budget.receipt.liveAllocations == 1)
            #expect(budget.receipt.peakTotal == 3 * page)
        }
        let budget = try DICOMAllocationBudget(limits: .init(encoded: page, resident: page - 1))
        let owner = try DICOMByteBuffer(count: 1, budget: budget, resource: .encoded)
        let before = budget.receipt
        #expect(throws: DICOMAllocationError.limitExceeded(.encoded)) {
            _ = try DICOMByteBuffer(count: 1, budget: budget, resource: .encoded)
        }
        #expect(throws: DICOMAllocationError.limitExceeded(.resident)) { try owner.transfer(to: .resident) }
        #expect(budget.receipt == before)
        try owner.transfer(to: .preview)
        #expect(budget.receipt.current.preview == page)
    }

    @Test("An owner keeps its ledger alive after all caller handles disappear")
    func retainedLedger() throws {
        func makeOwner() throws(DICOMAllocationError) -> DICOMByteBuffer {
            let ledger = try DICOMAllocationBudget()
            return try DICOMByteBuffer(count: 1, budget: ledger, resource: .encoded)
        }
        let owner = try makeOwner()
        let receipt = DICOMMappedStorage.receipt(owner.mappedOwner.pointee.ledger)
        #expect(receipt.current.encoded == page)
        #expect(receipt.current.metadata == 2 * page)
        let alias = try owner.share()
        destroy(owner)
        let zeroByteRetained = alias.withUnsafeBytes { $0[0] == 0 }
        #expect(zeroByteRetained)
        destroy(alias)
    }

    @Test("External leases map and retain their own shared control state")
    func externalLease() throws {
        let budget = try DICOMAllocationBudget()
        let lease = try budget.reserve(13, as: .staging)
        let alias = try lease.share()
        #expect(lease.bytes == 13)
        #expect(lease.controlCapacity == page)
        #expect(budget.receipt.currentTotal == 2 * page + 13)
        destroy(lease)
        try alias.transfer(to: .resident)
        #expect(budget.receipt.current.resident == 13)
        destroy(alias)
        #expect(budget.receipt.currentTotal == page)
    }

    @Test("Finalization runs once before unmap and may release nested ownership")
    func finalization() throws {
        var finalized = 0
        let budget = try DICOMAllocationBudget()
        try withUnsafeMutablePointer(to: &finalized) { counter in
            let slab = try DICOMByteBuffer(count: MemoryLayout<FinalizerState>.stride,
                                           budget: budget, resource: .metadata)
            let state = slab.unsafeMutableBytes.bindMemory(to: FinalizerState.self)
            state.baseAddress?.initialize(to: FinalizerState(budget: try budget.share(), counter: counter))
            try slab.installFinalizer(finalizeMappedState)
            #expect(throws: DICOMAllocationError.finalizerAlreadyInstalled) {
                try slab.installFinalizer(finalizeMappedState)
            }
            let alias = try slab.share()
            destroy(slab)
            #expect(counter.pointee == 0)
            destroy(alias)
            #expect(counter.pointee == 1)
        }
        #expect(finalized == 1)
        #expect(budget.receipt.currentTotal == page)
    }

    @Test("Retirement follows final alias, payload finalization, unmap and ledger debit exactly once")
    func retirementLifetime() throws {
        let budget = try DICOMAllocationBudget()
        let state = UnsafeMutablePointer<RetirementState>.allocate(capacity: 1)
        state.initialize(to: RetirementState(budget: try budget.share()))
        defer { state.deinitialize(count: 1); state.deallocate() }
        let buffer = try DICOMByteBuffer(count: MemoryLayout<UnsafeMutableRawPointer>.stride,
                                         budget: budget, resource: .decoded)
        let slot = buffer.unsafeMutableBytes.bindMemory(to: UnsafeMutableRawPointer.self)
        slot.baseAddress?.initialize(to: UnsafeMutableRawPointer(state))
        try buffer.installFinalizer(finalizeRetirementPayload)
        try buffer.installRetirementObserver(context: state, callback: recordRetirement)
        let alias = try buffer.share()
        let wrapper = RetirementWrapper(buffer: buffer)
        let retained = budget.receipt.currentTotal
        destroyRetirementWrapper(wrapper)
        let before = state.pointee.notifications
        #expect(before == 0)
        #expect(budget.receipt.currentTotal == retained)
        destroy(alias)
        let notifications = state.pointee.notifications
        let finalizations = state.pointee.finalizations
        let finalizationsAtRetirement = state.pointee.finalizationsAtRetirement
        let retiredTotal = state.pointee.totalAtRetirement
        let retiredAllocations = state.pointee.allocationsAtRetirement
        #expect(notifications == 1 && finalizations == 1 && finalizationsAtRetirement == 1)
        #expect(retiredTotal == page && retiredAllocations == 1)
        #expect(budget.receipt.currentTotal == page)
    }

    @Test("Retirement observer installs once and only before the first shared alias")
    func retirementRegistration() throws {
        let budget = try DICOMAllocationBudget()
        let registered = try DICOMByteBuffer(count: 1, budget: budget, resource: .decoded)
        try registered.installRetirementObserver(callback: { _ in })
        #expect(throws: DICOMAllocationError.retirementObserverAlreadyInstalled) {
            try registered.installRetirementObserver(callback: { _ in })
        }
        let owner = try DICOMByteBuffer(count: 1, budget: budget, resource: .decoded)
        let alias = try owner.share()
        #expect(throws: DICOMAllocationError.sharedMutation) {
            try owner.installRetirementObserver(callback: { _ in })
        }
        destroy(alias)
        #expect(throws: DICOMAllocationError.sharedMutation) {
            try owner.installRetirementObserver(callback: { _ in })
        }
    }

    @Test("A real unmap failure preserves the charge and never signals retirement")
    func failedUnmapDoesNotRetire() throws {
        let budget = try DICOMAllocationBudget()
        let state = UnsafeMutablePointer<RetirementState>.allocate(capacity: 1)
        state.initialize(to: RetirementState(budget: try budget.share()))
        defer { state.deinitialize(count: 1); state.deallocate() }
        let buffer = try DICOMByteBuffer(count: 1, budget: budget, resource: .decoded)
        try buffer.installRetirementObserver(context: state, callback: recordRetirement)
        let owner = buffer.mappedOwner
        guard let payload = owner.pointee.payload else { Issue.record("Missing mapped payload"); return }
        let retained = budget.receipt.currentTotal
        // Test-only internal corruption forces munmap's documented unaligned-address refusal;
        // restore the real mapping below so this test does not intentionally leak backing.
        owner.pointee.payload = payload.advanced(by: 1)
        destroy(buffer)
        let failedNotifications = state.pointee.notifications
        #expect(failedNotifications == 0)
        #expect(budget.receipt.currentTotal == retained)
        owner.pointee.payload = payload
        owner.pointee.references = 1
        DICOMMappedStorage.releaseOwner(owner)
        let notifications = state.pointee.notifications
        #expect(notifications == 1)
        #expect(budget.receipt.currentTotal == page)
    }

    @Test("Concurrent aliases serialize transfer and keep one retained charge")
    func concurrentTransfer() throws {
        let budget = try DICOMAllocationBudget()
        let owner = try DICOMByteBuffer(count: 1, budget: budget, resource: .decoded)
        let first = UnsafeMutablePointer<TransferWorker>.allocate(capacity: 1)
        let second = UnsafeMutablePointer<TransferWorker>.allocate(capacity: 1)
        first.initialize(to: TransferWorker(owner: try owner.share()))
        second.initialize(to: TransferWorker(owner: try owner.share()))
        defer {
            first.deinitialize(count: 1); first.deallocate()
            second.deinitialize(count: 1); second.deallocate()
        }
        #if canImport(Darwin)
        var firstThread: pthread_t?
        var secondThread: pthread_t?
        #else
        var firstThread = pthread_t()
        var secondThread = pthread_t()
        #endif
        let firstStarted = pthread_create(&firstThread, nil, { transferWorkerMain($0) }, first)
        #expect(firstStarted == 0)
        guard firstStarted == 0 else { return }
        let secondStarted = pthread_create(&secondThread, nil, { transferWorkerMain($0) }, second)
        #expect(secondStarted == 0)
        #if canImport(Darwin)
        if let firstThread { pthread_join(firstThread, nil) }
        if secondStarted == 0, let secondThread { pthread_join(secondThread, nil) }
        #else
        pthread_join(firstThread, nil)
        if secondStarted == 0 { pthread_join(secondThread, nil) }
        #endif
        guard secondStarted == 0 else { return }
        let combinedResult = first.pointee.result + second.pointee.result
        #expect(combinedResult == 3)
        #expect(budget.receipt.currentTotal == 3 * page)
        #expect(budget.receipt.current.decoded == 0)
        #expect(budget.receipt.current.resident == page)
    }

    #if canImport(Darwin)
    @Test("Whole reported worker stack is admitted at exact capacity and released on destruction")
    func executionCapacity() throws {
        let stack = Int(pthread_get_stacksize_np(pthread_self()))
        let total = stack + 2 * page // ledger page plus external-reservation control page
        let tooSmall = try DICOMAllocationBudget(limits: .init(staging: total - 1, total: total))
        #expect(throws: DICOMAllocationError.limitExceeded(.metadata)) {
            _ = try DICOMExecutionReservation(budget: tooSmall)
        }
        #expect(tooSmall.receipt.currentTotal == page)
        let budget = try DICOMAllocationBudget(limits: .init(staging: total, total: total))
        let execution = try DICOMExecutionReservation(budget: budget)
        try execution.validate(budget: budget)
        #expect(execution.stackByteCount == stack)
        #expect(execution.controlByteCount == page)
        #expect(execution.retainedByteCount == stack + page)
        #expect(budget.receipt.currentTotal == total)
        let unrelated = try DICOMAllocationBudget()
        #expect(throws: DICOMAllocationError.budgetMismatch) { try execution.validate(budget: unrelated) }
        destroy(execution)
        #expect(budget.receipt.currentTotal == page)
    }

    @Test("Execution reservation rejects another worker without releasing its stack charge")
    func executionThreadIdentity() throws {
        let budget = try DICOMAllocationBudget()
        let execution = try DICOMExecutionReservation(budget: budget)
        let retained = budget.receipt.currentTotal
        let context = UnsafeMutablePointer<ExecutionWorker>.allocate(capacity: 1)
        context.initialize(to: ExecutionWorker(execution: execution, budget: try budget.share()))
        var thread: pthread_t?
        let started = pthread_create(&thread, nil, { executionWorkerMain($0) }, context)
        #expect(started == 0)
        if started == 0, let thread { pthread_join(thread, nil) }
        if started == 0 {
            let result = context.pointee.result
            #expect(result == .threadMismatch)
        }
        #expect(budget.receipt.currentTotal == retained)
        context.deinitialize(count: 1); context.deallocate()
        #expect(budget.receipt.currentTotal == page)
    }
    #endif
}

private struct FinalizerState: ~Copyable {
    let budget: DICOMAllocationBudget
    let counter: UnsafeMutablePointer<Int>
}

private struct RetirementWrapper: ~Copyable { let buffer: DICOMByteBuffer }
private func destroyRetirementWrapper(_ wrapper: consuming RetirementWrapper) {}

private struct RetirementState: ~Copyable {
    let budget: DICOMAllocationBudget
    var notifications = 0
    var finalizations = 0
    var finalizationsAtRetirement = -1
    var totalAtRetirement = -1
    var allocationsAtRetirement = -1
}

private func finalizeRetirementPayload(_ raw: UnsafeMutableRawPointer?, _ count: Int) {
    guard let raw, count == MemoryLayout<UnsafeMutableRawPointer>.stride else { return }
    let slot = raw.assumingMemoryBound(to: UnsafeMutableRawPointer.self)
    let state = slot.pointee.assumingMemoryBound(to: RetirementState.self)
    state.pointee.finalizations += 1
    slot.deinitialize(count: 1)
}

private func recordRetirement(_ raw: UnsafeMutableRawPointer?) {
    guard let raw else { return }
    let state = raw.assumingMemoryBound(to: RetirementState.self)
    state.pointee.notifications += 1
    state.pointee.finalizationsAtRetirement = state.pointee.finalizations
    let receipt = state.pointee.budget.receipt // Reentrant: observer must run outside the ledger mutex.
    state.pointee.totalAtRetirement = receipt.currentTotal
    state.pointee.allocationsAtRetirement = receipt.liveAllocations
}

private func finalizeMappedState(_ raw: UnsafeMutableRawPointer?, _ count: Int) {
    guard let raw, count == MemoryLayout<FinalizerState>.stride else { return }
    let state = raw.assumingMemoryBound(to: FinalizerState.self)
    state.pointee.counter.pointee += 1
    state.deinitialize(count: 1)
}

private struct TransferWorker: ~Copyable {
    let owner: DICOMByteBuffer
    var result = 0
}

private func transferWorkerMain(_ raw: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let raw else { return nil }
    let context = raw.assumingMemoryBound(to: TransferWorker.self)
    do {
        try context.pointee.owner.transfer(to: .resident)
        context.pointee.result = 1
    } catch {
        context.pointee.result = error == .alreadyTransferred ? 2 : -100
    }
    return nil
}

#if canImport(Darwin)
private struct ExecutionWorker: ~Copyable {
    let execution: DICOMExecutionReservation
    let budget: DICOMAllocationBudget
    var result: DICOMAllocationError?
}

private func executionWorkerMain(_ raw: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let raw else { return nil }
    let context = raw.assumingMemoryBound(to: ExecutionWorker.self)
    do { try context.pointee.execution.validate(budget: context.pointee.budget) }
    catch { context.pointee.result = error }
    return nil
}
#endif
