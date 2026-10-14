// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (mapped storage control).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// These concrete, scalar-only records live in admitted mappings, never in ARC objects.
struct DICOMMappedLedger {
    var mutex = pthread_mutex_t()
    let limits: DICOMAllocationBudget.Limits
    let capacity: Int
    var references = 1
    var current = DICOMAllocationUsage()
    var peak = DICOMAllocationUsage()
    var currentTotal = 0
    var peakTotal = 0
    var liveAllocations = 1
    var failureAfter: Int
}

struct DICOMMappedOwner {
    let ledger: UnsafeMutablePointer<DICOMMappedLedger>
    let controlCapacity: Int
    let count: Int
    let requestedCapacity: Int
    let payloadCapacity: Int
    var payload: UnsafeMutableRawPointer? = nil
    var references = 1
    var wasShared = false
    var resource: DICOMAllocationClass
    var transferred = false
    var finalizer: (@convention(c) (UnsafeMutableRawPointer?, Int) -> Void)? = nil
    var retirementContext: UnsafeMutableRawPointer? = nil
    var retirementObserver: (@convention(c) (UnsafeMutableRawPointer?) -> Void)? = nil
}

enum DICOMMappedStorage {
    static var pageSize: Int { Int(getpagesize()) }

    static func roundedCapacity(_ count: Int) -> DICOMAllocationOutcome<Int> {
        let page = pageSize
        guard page > 0, count >= 0, count <= Int.max - (page - 1) else { return .failure(.invalidSize) }
        return .success(max(page, ((count + page - 1) / page) * page))
    }

    static func makeLedger(limits: DICOMAllocationBudget.Limits, failureAfter: Int)
        -> DICOMAllocationOutcome<UnsafeMutablePointer<DICOMMappedLedger>> {
        let capacity = pageSize
        guard limits.encoded >= 0, limits.decoded >= 0, limits.staging >= 0,
              limits.resident >= 0, limits.preview >= 0, limits.total >= 0,
              capacity >= MemoryLayout<DICOMMappedLedger>.stride else { return .failure(.invalidSize) }
        guard capacity <= limits.staging else { return .failure(.limitExceeded(.metadata)) }
        guard capacity <= limits.total else { return .failure(.totalLimitExceeded) }
        let raw: UnsafeMutableRawPointer
        switch map(capacity) {
        case .success(let value): raw = value
        case .failure(let error): return .failure(error)
        }
        let ledger = raw.bindMemory(to: DICOMMappedLedger.self, capacity: 1)
        ledger.initialize(to: DICOMMappedLedger(limits: limits, capacity: capacity, failureAfter: failureAfter))
        guard pthread_mutex_init(&ledger.pointee.mutex, nil) == 0 else {
            _ = munmap(raw, capacity)
            return .failure(.synchronizationFailed)
        }
        ledger.pointee.current.metadata = capacity
        ledger.pointee.peak.metadata = capacity
        ledger.pointee.currentTotal = capacity
        ledger.pointee.peakTotal = capacity
        return .success(ledger)
    }

    static func retainLedger(_ ledger: UnsafeMutablePointer<DICOMMappedLedger>)
        -> DICOMAllocationError? {
        pthread_mutex_lock(&ledger.pointee.mutex)
        defer { pthread_mutex_unlock(&ledger.pointee.mutex) }
        guard ledger.pointee.references < Int.max else { return .referenceCountOverflow }
        ledger.pointee.references += 1
        return nil
    }

    static func releaseLedger(_ ledger: UnsafeMutablePointer<DICOMMappedLedger>) {
        pthread_mutex_lock(&ledger.pointee.mutex)
        ledger.pointee.references -= 1
        let last = ledger.pointee.references == 0
        let capacity = ledger.pointee.capacity
        pthread_mutex_unlock(&ledger.pointee.mutex)
        if last {
            // A kernel cleanup failure deliberately retains capacity rather than reporting a false release.
            guard pthread_mutex_destroy(&ledger.pointee.mutex) == 0 else { return }
            _ = munmap(UnsafeMutableRawPointer(ledger), capacity)
        }
    }

    static func receipt(_ ledger: UnsafeMutablePointer<DICOMMappedLedger>) -> DICOMAllocationReceipt {
        pthread_mutex_lock(&ledger.pointee.mutex)
        defer { pthread_mutex_unlock(&ledger.pointee.mutex) }
        return DICOMAllocationReceipt(current: ledger.pointee.current, peak: ledger.pointee.peak,
            currentTotal: ledger.pointee.currentTotal, peakTotal: ledger.pointee.peakTotal,
            liveAllocations: ledger.pointee.liveAllocations)
    }

    static func check(_ bytes: Int, resource: DICOMAllocationClass, current: DICOMAllocationUsage,
                      total: Int, limits: DICOMAllocationBudget.Limits) -> DICOMAllocationError? {
        guard bytes >= 0 else { return .invalidSize }
        let used = resource == .metadata || resource == .staging
            ? current.metadata + current.staging : current[resource]
        guard used <= limits[resource], bytes <= limits[resource] - used else {
            return .limitExceeded(resource)
        }
        guard total <= limits.total, bytes <= limits.total - total else { return .totalLimitExceeded }
        return nil
    }

    // Admit the metadata page and payload together; no partial admission is observable.
    static func admit(_ ledger: UnsafeMutablePointer<DICOMMappedLedger>, payload: Int,
                      control: Int, resource: DICOMAllocationClass) -> DICOMAllocationError? {
        pthread_mutex_lock(&ledger.pointee.mutex)
        defer { pthread_mutex_unlock(&ledger.pointee.mutex) }
        guard ledger.pointee.references < Int.max, ledger.pointee.liveAllocations < Int.max else {
            return .referenceCountOverflow
        }
        var next = ledger.pointee.current
        var total = ledger.pointee.currentTotal
        if let error = check(control, resource: .metadata, current: next, total: total, limits: ledger.pointee.limits) {
            return error
        }
        next.metadata += control; total += control
        if let error = check(payload, resource: resource, current: next, total: total, limits: ledger.pointee.limits) {
            return error
        }
        next[resource] += payload; total += payload
        ledger.pointee.current = next
        ledger.pointee.currentTotal = total
        ledger.pointee.peak.metadata = max(ledger.pointee.peak.metadata, next.metadata)
        ledger.pointee.peak[resource] = max(ledger.pointee.peak[resource], next[resource])
        ledger.pointee.peakTotal = max(ledger.pointee.peakTotal, total)
        ledger.pointee.liveAllocations += 1
        ledger.pointee.references += 1
        return nil
    }

    static func makeOwner(ledger: UnsafeMutablePointer<DICOMMappedLedger>, count: Int,
                          capacity: Int, resource: DICOMAllocationClass, mapsPayload: Bool)
        -> DICOMAllocationOutcome<UnsafeMutablePointer<DICOMMappedOwner>> {
        guard count >= 0, capacity >= count else { return .failure(.invalidSize) }
        let payloadCapacity: Int
        if mapsPayload {
            switch roundedCapacity(capacity) {
            case .success(let value): payloadCapacity = value
            case .failure(let error): return .failure(error)
            }
        } else { payloadCapacity = capacity }
        let control = pageSize
        guard control >= MemoryLayout<DICOMMappedOwner>.stride else { return .failure(.invalidSize) }
        if let error = admit(ledger, payload: payloadCapacity, control: control, resource: resource) {
            return .failure(error)
        }
        let raw: UnsafeMutableRawPointer
        switch mapForLedger(control, ledger: ledger) {
        case .success(let value): raw = value
        case .failure(let error):
            releaseReservation(ledger, payload: payloadCapacity, control: control, resource: resource,
                               releasesOwner: true)
            return .failure(error)
        }
        let owner = raw.bindMemory(to: DICOMMappedOwner.self, capacity: 1)
        owner.initialize(to: DICOMMappedOwner(ledger: ledger, controlCapacity: control, count: count,
            requestedCapacity: capacity, payloadCapacity: payloadCapacity, resource: resource))
        if mapsPayload {
            switch mapForLedger(payloadCapacity, ledger: ledger) {
            case .success(let value): owner.pointee.payload = value
            case .failure(let error): releaseOwner(owner); return .failure(error)
            }
        }
        return .success(owner)
    }

    static func map(_ capacity: Int) -> DICOMAllocationOutcome<UnsafeMutableRawPointer> {
        let raw = mmap(nil, capacity, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)
        guard let raw, raw != MAP_FAILED else { return .failure(.allocationFailed) }
        return .success(raw)
    }

    static func mapForLedger(_ capacity: Int, ledger: UnsafeMutablePointer<DICOMMappedLedger>)
        -> DICOMAllocationOutcome<UnsafeMutableRawPointer> {
        pthread_mutex_lock(&ledger.pointee.mutex)
        let remaining = ledger.pointee.failureAfter
        if remaining > 0 { ledger.pointee.failureAfter -= 1 }
        pthread_mutex_unlock(&ledger.pointee.mutex)
        guard remaining != 0 else { return .failure(.allocationFailed) }
        return map(capacity)
    }

    static func retainOwner(_ owner: UnsafeMutablePointer<DICOMMappedOwner>) -> DICOMAllocationError? {
        let ledger = owner.pointee.ledger
        pthread_mutex_lock(&ledger.pointee.mutex)
        defer { pthread_mutex_unlock(&ledger.pointee.mutex) }
        guard owner.pointee.references < Int.max else { return .referenceCountOverflow }
        owner.pointee.references += 1
        owner.pointee.wasShared = true
        return nil
    }

    static func installFinalizer(_ owner: UnsafeMutablePointer<DICOMMappedOwner>,
                                _ finalizer: @convention(c) (UnsafeMutableRawPointer?, Int) -> Void)
        -> DICOMAllocationError? {
        let ledger = owner.pointee.ledger
        pthread_mutex_lock(&ledger.pointee.mutex)
        defer { pthread_mutex_unlock(&ledger.pointee.mutex) }
        guard owner.pointee.references == 1 else { return .sharedMutation }
        guard owner.pointee.finalizer == nil else { return .finalizerAlreadyInstalled }
        owner.pointee.finalizer = finalizer
        return nil
    }

    static func installRetirementObserver(_ owner: UnsafeMutablePointer<DICOMMappedOwner>,
        context: UnsafeMutableRawPointer?, callback: @convention(c) (UnsafeMutableRawPointer?) -> Void)
        -> DICOMAllocationError? {
        let ledger = owner.pointee.ledger
        pthread_mutex_lock(&ledger.pointee.mutex)
        defer { pthread_mutex_unlock(&ledger.pointee.mutex) }
        guard owner.pointee.references == 1, !owner.pointee.wasShared else { return .sharedMutation }
        guard owner.pointee.retirementObserver == nil else { return .retirementObserverAlreadyInstalled }
        owner.pointee.retirementContext = context
        owner.pointee.retirementObserver = callback
        return nil
    }

    static func transfer(_ owner: UnsafeMutablePointer<DICOMMappedOwner>, to resource: DICOMAllocationClass)
        -> DICOMAllocationError? {
        let ledger = owner.pointee.ledger
        pthread_mutex_lock(&ledger.pointee.mutex)
        defer { pthread_mutex_unlock(&ledger.pointee.mutex) }
        guard !owner.pointee.transferred else { return .alreadyTransferred }
        let bytes = owner.pointee.payloadCapacity
        var next = ledger.pointee.current
        next[owner.pointee.resource] -= bytes
        let total = ledger.pointee.currentTotal - bytes
        if let error = check(bytes, resource: resource, current: next, total: total, limits: ledger.pointee.limits) {
            return error
        }
        next[resource] += bytes
        ledger.pointee.current = next
        ledger.pointee.peak[resource] = max(ledger.pointee.peak[resource], next[resource])
        owner.pointee.resource = resource
        owner.pointee.transferred = true
        return nil
    }

    static func releaseOwner(_ owner: UnsafeMutablePointer<DICOMMappedOwner>) {
        let ledger = owner.pointee.ledger
        pthread_mutex_lock(&ledger.pointee.mutex)
        owner.pointee.references -= 1
        let last = owner.pointee.references == 0
        pthread_mutex_unlock(&ledger.pointee.mutex)
        guard last else { return }
        // This owner holds a ledger reference throughout cleanup, including reentrant finalizers.
        let payload = owner.pointee.payload
        let bytes = owner.pointee.payloadCapacity
        let control = owner.pointee.controlCapacity
        let resource = owner.pointee.resource
        let retirementContext = owner.pointee.retirementContext
        let retirementObserver = owner.pointee.retirementObserver
        owner.pointee.finalizer?(payload, owner.pointee.requestedCapacity)
        if let payload {
            guard munmap(payload, bytes) == 0 else { return }
        }
        let unmappedControl = munmap(UnsafeMutableRawPointer(owner), control) == 0
        // If unmapping the header fails, keep its capacity and ledger reference charged.
        releaseReservation(ledger, payload: bytes, control: unmappedControl ? control : 0,
                           resource: resource, releasesOwner: unmappedControl,
                           retirementContext: retirementContext, retirementObserver: retirementObserver)
    }

    static func releaseReservation(_ ledger: UnsafeMutablePointer<DICOMMappedLedger>, payload: Int,
        control: Int, resource: DICOMAllocationClass, releasesOwner: Bool,
        retirementContext: UnsafeMutableRawPointer? = nil,
        retirementObserver: (@convention(c) (UnsafeMutableRawPointer?) -> Void)? = nil) {
        pthread_mutex_lock(&ledger.pointee.mutex)
        ledger.pointee.current[resource] -= payload
        ledger.pointee.current.metadata -= control
        ledger.pointee.currentTotal -= payload
        ledger.pointee.currentTotal -= control
        if releasesOwner { ledger.pointee.liveAllocations -= 1 }
        pthread_mutex_unlock(&ledger.pointee.mutex)
        if releasesOwner {
            // Both mappings are already gone and counters debited. The former owner's
            // ledger reference remains live throughout this external, nonblocking callback.
            retirementObserver?(retirementContext)
            releaseLedger(ledger)
        }
    }
}
