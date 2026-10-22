import Testing
@testable import DICOMCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite("External aggregate allocation ownership")
struct DICOMExternalAllocationTests {
    private var page: Int { DICOMAllocationBudget.controlCapacity }
    private func destroy(_ budget: consuming DICOMAllocationBudget) {}
    private func destroy(_ buffer: consuming DICOMByteBuffer) {}
    private func destroy(_ lease: consuming DICOMAllocationLease) {}

    @Test("Local and aggregate bootstrap refusal acquire no dangling context or token")
    func bootstrapRefusal() {
        let state = ExternalAllocationFixture()
        switch DICOMAllocationBudget.make(limits: .init(total: page - 1), externalAdmission: state.callbacks) {
        case .success: Issue.record("Local bootstrap over limit")
        case .failure(let error): #expect(error == .totalLimitExceeded)
        }
        #expect(state.value.pointee.retains == 0)
        state.value.pointee.refuseRetain = 41
        switch DICOMAllocationBudget.make(externalAdmission: state.callbacks) {
        case .success: Issue.record("Context refusal ignored")
        case .failure(let error): #expect(error == .externalAdmissionRefused(41))
        }
        #expect(state.value.pointee.admits == 0)
        #expect(state.value.pointee.contextReleases == 0)
        state.value.pointee.refuseRetain = 0
        state.value.pointee.refuseAdmit = 42
        switch DICOMAllocationBudget.make(externalAdmission: state.callbacks) {
        case .success: Issue.record("Aggregate bootstrap refusal ignored")
        case .failure(let error): #expect(error == .externalAdmissionRefused(42))
        }
        #expect(state.value.pointee.contextReleases == 1)
        #expect(state.value.pointee.releases == 0)
        #expect(state.value.pointee.total == 0)
        #expect(state.value.pointee.contextOwners == 0)
        #expect(state.value.pointee.failures == 0)
    }

    @Test("Two independent local ledgers share one aggregate cap and refuse before mapping")
    func aggregateCap() throws {
        let state = ExternalAllocationFixture(limit: 4 * page)
        let first = try DICOMAllocationBudget.make(externalAdmission: state.callbacks).get()
        let second = try DICOMAllocationBudget.make(externalAdmission: state.callbacks).get()
        let buffer = try DICOMByteBuffer(count: 3, budget: first, resource: .decoded)
        let before = second.receipt
        #expect(state.value.pointee.total == 4 * page)
        #expect(throws: DICOMAllocationError.externalAdmissionRefused(43)) {
            _ = try DICOMByteBuffer(count: 3, budget: second, resource: .decoded)
        }
        #expect(second.receipt == before)
        destroy(buffer)
        let recovered = try DICOMByteBuffer(count: 3, budget: second, resource: .decoded)
        destroy(recovered)
        destroy(first)
        #expect(state.value.pointee.contextOwners == 1)
        destroy(second)
        #expect(state.value.pointee.total == 0)
        #expect(state.value.pointee.contextOwners == 0)
        #expect(state.value.pointee.failures == 0)
    }

    @Test("Both owner mapping failure sites roll back the complete external pair")
    func mappingRollback() throws {
        for failAfter in 0...1 {
            let state = ExternalAllocationFixture()
            let budget = try DICOMAllocationBudget.make(externalAdmission: state.callbacks).get()
            budget.mappedLedger.pointee.failureAfter = failAfter
            #expect(throws: DICOMAllocationError.allocationFailed) {
                _ = try DICOMByteBuffer(count: 1, budget: budget, resource: .encoded)
            }
            #expect(budget.receipt.currentTotal == page)
            #expect(state.value.pointee.total == page)
            #expect(state.value.pointee.admits == 2)
            #expect(state.value.pointee.releases == 1)
            destroy(budget)
            #expect(state.value.pointee.total == 0)
            #expect(state.value.pointee.contextReleases == 1)
            #expect(state.value.pointee.failures == 0)
        }
    }

    @Test("Transfer refusal preserves both ledgers and successful alias transfer happens once")
    func transferAndLocalLimits() throws {
        let state = ExternalAllocationFixture()
        let budget = try DICOMAllocationBudget.make(limits: .init(preview: page - 1),
            externalAdmission: state.callbacks).get()
        let buffer = try DICOMByteBuffer(count: 1, budget: budget, resource: .decoded)
        let alias = try buffer.share()
        let before = budget.receipt
        #expect(throws: DICOMAllocationError.limitExceeded(.preview)) { try buffer.transfer(to: .preview) }
        #expect(state.value.pointee.transfers == 0)
        state.value.pointee.refuseTransfer = 44
        #expect(throws: DICOMAllocationError.externalAdmissionRefused(44)) { try buffer.transfer(to: .resident) }
        #expect(budget.receipt == before)
        #expect(state.value.pointee.usage.decoded == page)
        #expect(state.value.pointee.usage.resident == 0)
        state.value.pointee.refuseTransfer = 0
        try alias.transfer(to: .resident)
        #expect(budget.receipt.current.resident == page)
        #expect(state.value.pointee.usage.resident == page)
        #expect(state.value.pointee.usage.decoded == 0)
        #expect(throws: DICOMAllocationError.alreadyTransferred) { try buffer.transfer(to: .staging) }
        #expect(state.value.pointee.transfers == 2)
        destroy(buffer)
        destroy(alias)
        destroy(budget)
        #expect(state.value.pointee.total == 0)
        #expect(state.value.pointee.failures == 0)
    }

    @Test("Copy admits a new pair while aliases and escaped owners retain the context")
    func copyAndFinalLedgerOrder() throws {
        let state = ExternalAllocationFixture()
        let budget = try DICOMAllocationBudget.make(externalAdmission: state.callbacks).get()
        let ledger = budget.mappedLedger
        let buffer = try DICOMByteBuffer(count: 1, capacity: page + 1, budget: budget, resource: .decoded)
        buffer.unsafeMutableBytes[0] = 123
        let alias = try buffer.share()
        let copy = try buffer.copy(budget: budget, resource: .preview)
        #expect(budget.externalAdmissionContext == UnsafeMutableRawPointer(state.value))
        #expect(buffer.externalAdmissionContext == budget.externalAdmissionContext)
        #expect(buffer.externalAllocationToken != nil)
        #expect(buffer.externalAllocationToken == alias.externalAllocationToken)
        #expect(buffer.externalAllocationToken != copy.externalAllocationToken)
        let copied = copy.withUnsafeBytes { $0[0] }
        #expect(copied == 123)
        #expect(state.value.pointee.total == 6 * page)
        #expect(state.value.pointee.admits == 3)
        state.value.pointee.ledgerToInspect = ledger
        state.value.pointee.ledgerToken = ledger.pointee.externalToken
        destroy(budget)
        destroy(buffer)
        #expect(state.value.pointee.contextReleases == 0)
        #expect(state.value.pointee.releases == 0)
        destroy(copy)
        #expect(state.value.pointee.total == 4 * page)
        #expect(state.value.pointee.contextReleases == 0)
        destroy(alias)
        #expect(state.value.pointee.total == 0)
        #expect(state.value.pointee.releases == 3)
        #expect(state.value.pointee.contextReleases == 1)
        #expect(state.value.pointee.contextOwners == 0)
        #expect(state.value.pointee.failures == 0)
        #expect(state.value.pointee.lastRelease == state.value.pointee.ledgerToken)
    }

    @Test("External reservations admit complete capacity plus a real control page")
    func externalReservation() throws {
        let state = ExternalAllocationFixture()
        let budget = try DICOMAllocationBudget.make(externalAdmission: state.callbacks).get()
        let lease = try budget.reserve(19, as: .metadata)
        let alias = try lease.share()
        #expect(state.value.pointee.total == 2 * page + 19)
        #expect(state.value.pointee.usage.metadata == 2 * page + 19)
        destroy(lease)
        #expect(state.value.pointee.releases == 0)
        destroy(alias)
        #expect(state.value.pointee.total == page)
        destroy(budget)
        #expect(state.value.pointee.total == 0)
        #expect(state.value.pointee.failures == 0)
    }

    @Test("Payload unmap refusal retains the entire external pair and context")
    func payloadQuarantine() throws {
        let state = ExternalAllocationFixture()
        let budget = try DICOMAllocationBudget.make(externalAdmission: state.callbacks).get()
        let buffer = try DICOMByteBuffer(count: 1, budget: budget, resource: .decoded)
        let owner = buffer.mappedOwner
        let payload = try #require(owner.pointee.payload)
        owner.pointee.payload = payload.advanced(by: 1) // Real kernel EINVAL; test-only corruption.
        destroy(buffer)
        destroy(budget)
        #expect(state.value.pointee.total == 3 * page)
        #expect(state.value.pointee.contextOwners == 1)
        #expect(state.value.pointee.releases == 0)
        // Restore this synthetic quarantine solely to avoid leaking the test's mappings.
        owner.pointee.payload = payload
        owner.pointee.references = 1
        DICOMMappedStorage.releaseOwner(owner)
        #expect(state.value.pointee.total == 0)
        #expect(state.value.pointee.contextReleases == 1)
        #expect(state.value.pointee.failures == 0)
    }

    @Test("Control unmap refusal conservatively retains even the retired external payload charge")
    func controlQuarantine() throws {
        let state = ExternalAllocationFixture()
        let budget = try DICOMAllocationBudget.make(externalAdmission: state.callbacks).get()
        let buffer = try DICOMByteBuffer(count: 1, budget: budget, resource: .decoded)
        let owner = buffer.mappedOwner
        let saved = owner.pointee
        // Preserve the real payload; a zero control length makes munmap fail after payload unmap.
        owner.pointee = DICOMMappedOwner(ledger: saved.ledger, controlCapacity: 0, count: saved.count,
            requestedCapacity: saved.requestedCapacity, payloadCapacity: saved.payloadCapacity,
            payload: saved.payload, resource: saved.resource, externalToken: saved.externalToken)
        destroy(buffer)
        #expect(budget.receipt.current.decoded == 0)
        #expect(state.value.pointee.total == 3 * page)
        #expect(state.value.pointee.releases == 0)
        destroy(budget)
        #expect(state.value.pointee.contextOwners == 1)
        // Finish only the test's synthetic quarantined control. Payload was already debited locally.
        #expect(munmap(UnsafeMutableRawPointer(owner), saved.controlCapacity) == 0)
        DICOMMappedStorage.releaseReservation(saved.ledger, payload: 0, control: saved.controlCapacity,
            resource: saved.resource, releasesOwner: true, externalToken: saved.externalToken)
        #expect(state.value.pointee.total == 0)
        #expect(state.value.pointee.contextReleases == 1)
        #expect(state.value.pointee.failures == 0)
    }

    @Test("Failed final ledger unmap never releases its token or context")
    func ledgerQuarantine() throws {
        let state = ExternalAllocationFixture()
        let budget = try DICOMAllocationBudget.make(externalAdmission: state.callbacks).get()
        let ledger = budget.mappedLedger
        let token = ledger.pointee.externalToken
        let offset = try #require(MemoryLayout<DICOMMappedLedger>.offset(of: \.capacity))
        // Test-only zero length causes real munmap EINVAL after mutex destruction.
        UnsafeMutableRawPointer(ledger).advanced(by: offset).storeBytes(of: 0, as: Int.self)
        destroy(budget)
        #expect(state.value.pointee.total == page)
        #expect(state.value.pointee.releases == 0)
        #expect(state.value.pointee.contextReleases == 0)
        #expect(state.value.pointee.contextOwners == 1)
        #expect(munmap(UnsafeMutableRawPointer(ledger), page) == 0)
        // Only the test owns this deliberately corrupted, unreachable quarantine.
        externalRelease(state.value, token)
        externalReleaseContext(state.value)
        #expect(state.value.pointee.total == 0)
        #expect(state.value.pointee.failures == 0)
    }
}

struct ExternalAllocationRecord {
    var payload = 0
    var control = 0
    var resource: DICOMAllocationClass = .metadata
    var live = false
}

struct ExternalAllocationState {
    var mutex = pthread_mutex_t()
    let records: UnsafeMutablePointer<ExternalAllocationRecord>
    let limit: Int
    var usage = DICOMAllocationUsage()
    var total = 0
    var nextToken: UInt64 = 1
    var retains = 0
    var contextOwners = 0
    var contextReleases = 0
    var admits = 0
    var releases = 0
    var transfers = 0
    var refuseRetain: Int32 = 0
    var refuseAdmit: Int32 = 0
    var refuseTransfer: Int32 = 0
    var refuseResource: Int32 = -1
    var failures = 0
    var lastRelease: UInt64 = 0
    var ledgerToken: UInt64 = 0
    var ledgerToInspect: UnsafeMutablePointer<DICOMMappedLedger>?
}

// All fixture storage is prepared before callback entry. Callback bodies never allocate.
struct ExternalAllocationFixture: ~Copyable {
    let value: UnsafeMutablePointer<ExternalAllocationState>
    init(limit: Int = Int.max) {
        let records = UnsafeMutablePointer<ExternalAllocationRecord>.allocate(capacity: 128)
        records.initialize(repeating: ExternalAllocationRecord(), count: 128)
        value = .allocate(capacity: 1)
        value.initialize(to: ExternalAllocationState(records: records, limit: limit))
        #expect(pthread_mutex_init(&value.pointee.mutex, nil) == 0)
    }
    var callbacks: DICOMExternalAllocationCallbacks {
        DICOMExternalAllocationCallbacks(context: value, retainContext: externalRetainContext,
            admit: externalAdmit, release: externalRelease, transfer: externalTransfer,
            releaseContext: externalReleaseContext)
    }
    deinit {
        #expect(value.pointee.contextOwners == 0)
        #expect(pthread_mutex_destroy(&value.pointee.mutex) == 0)
        value.pointee.records.deinitialize(count: 128)
        value.pointee.records.deallocate()
        value.deinitialize(count: 1)
        value.deallocate()
    }
}

private func externalRetainContext(_ raw: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = raw?.assumingMemoryBound(to: ExternalAllocationState.self) else { return 40 }
    pthread_mutex_lock(&state.pointee.mutex)
    defer { pthread_mutex_unlock(&state.pointee.mutex) }
    state.pointee.retains += 1
    if state.pointee.refuseRetain != 0 { return state.pointee.refuseRetain }
    state.pointee.contextOwners += 1
    return 0
}

private func externalAdmit(_ raw: UnsafeMutableRawPointer?, _ resource: Int32, _ payload: Int,
                          _ control: Int, _ output: UnsafeMutablePointer<UInt64>?) -> Int32 {
    guard let state = raw?.assumingMemoryBound(to: ExternalAllocationState.self), let output,
          let kind = DICOMAllocationClass(rawValue: Int(resource)) else { return 40 }
    output.pointee = 0
    pthread_mutex_lock(&state.pointee.mutex)
    defer { pthread_mutex_unlock(&state.pointee.mutex) }
    state.pointee.admits += 1
    if state.pointee.refuseAdmit != 0 { return state.pointee.refuseAdmit }
    if state.pointee.refuseResource == resource { return 45 }
    guard payload <= state.pointee.limit - state.pointee.total,
          control <= state.pointee.limit - state.pointee.total - payload,
          state.pointee.nextToken < 128 else { return 43 }
    let token = state.pointee.nextToken
    state.pointee.nextToken += 1
    state.pointee.records[Int(token)] = ExternalAllocationRecord(payload: payload, control: control,
        resource: kind, live: true)
    state.pointee.usage[kind] += payload
    state.pointee.usage.metadata += control
    state.pointee.total += payload + control
    output.pointee = token
    return 0
}

private func externalTransfer(_ raw: UnsafeMutableRawPointer?, _ token: UInt64, _ destination: Int32) -> Int32 {
    guard let state = raw?.assumingMemoryBound(to: ExternalAllocationState.self), token > 0, token < 128,
          let kind = DICOMAllocationClass(rawValue: Int(destination)) else { return 40 }
    pthread_mutex_lock(&state.pointee.mutex)
    defer { pthread_mutex_unlock(&state.pointee.mutex) }
    state.pointee.transfers += 1
    if state.pointee.refuseTransfer != 0 { return state.pointee.refuseTransfer }
    let previous = state.pointee.records[Int(token)]
    guard previous.live else { state.pointee.failures += 1; return 40 }
    state.pointee.usage[previous.resource] -= previous.payload
    state.pointee.usage[kind] += previous.payload
    state.pointee.records[Int(token)].resource = kind
    return 0
}

private func externalRelease(_ raw: UnsafeMutableRawPointer?, _ token: UInt64) {
    guard let state = raw?.assumingMemoryBound(to: ExternalAllocationState.self) else { return }
    // The ledger is pinned through owner release, and its mutex must already be unlocked.
    var localReceipt: DICOMAllocationReceipt?
    if token != state.pointee.ledgerToken, let ledger = state.pointee.ledgerToInspect {
        localReceipt = DICOMMappedStorage.receipt(ledger)
    }
    pthread_mutex_lock(&state.pointee.mutex)
    defer { pthread_mutex_unlock(&state.pointee.mutex) }
    guard token > 0, token < 128, state.pointee.records[Int(token)].live else {
        state.pointee.failures += 1; return
    }
    let record = state.pointee.records[Int(token)]
    if let localReceipt {
        // A retired address can immediately belong to another allocation. Inspect
        // this still-live ledger's accounting instead of querying global VM state.
        // The real munmap-failure tests above separately require charges and tokens
        // to remain live when payload, owner or ledger retirement fails.
        var expected = state.pointee.usage
        expected[record.resource] -= record.payload
        expected.metadata -= record.control
        if localReceipt.current != expected
            || localReceipt.currentTotal != state.pointee.total - record.payload - record.control {
            state.pointee.failures += 1
        }
    }
    state.pointee.usage[record.resource] -= record.payload
    state.pointee.usage.metadata -= record.control
    state.pointee.total -= record.payload + record.control
    state.pointee.records[Int(token)].live = false
    state.pointee.releases += 1
    state.pointee.lastRelease = token
}

private func externalReleaseContext(_ raw: UnsafeMutableRawPointer?) {
    guard let state = raw?.assumingMemoryBound(to: ExternalAllocationState.self) else { return }
    pthread_mutex_lock(&state.pointee.mutex)
    defer { pthread_mutex_unlock(&state.pointee.mutex) }
    if state.pointee.contextOwners <= 0 { state.pointee.failures += 1 }
    state.pointee.contextOwners -= 1
    state.pointee.contextReleases += 1
    if state.pointee.contextOwners == 0, state.pointee.total != 0 { state.pointee.failures += 1 }
    if state.pointee.contextOwners == 0, state.pointee.ledgerToken != 0,
       state.pointee.lastRelease != state.pointee.ledgerToken {
        state.pointee.failures += 1
    }
}
