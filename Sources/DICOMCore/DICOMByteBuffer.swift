// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (owned byte storage).

/// Immutable bytes retained by explicit move-only handles over mapped shared control state.
/// `share()` retains one backing and one charge; copying admits a second complete backing.
public struct DICOMByteBuffer: ~Copyable, @unchecked Sendable {
    let mappedOwner: UnsafeMutablePointer<DICOMMappedOwner>

    /// Logical bytes exposed by immutable borrows.
    public var count: Int { mappedOwner.pointee.count }
    /// Actual page-rounded payload capacity retained until the last handle is destroyed.
    public var capacity: Int { mappedOwner.pointee.payloadCapacity }
    /// Actual shared owner-header capacity, always charged as metadata even after payload transfer.
    public var controlByteCount: Int { mappedOwner.pointee.controlCapacity }
    /// Complete retained payload and owner-header capacity; excludes the ledger page shared by all owners.
    public var retainedByteCount: Int { capacity + controlByteCount }
    /// Actual shared control mapping capacity, charged separately as metadata.
    public static var controlCapacity: Int { DICOMMappedStorage.pageSize }

    /// Round a request to complete pages, including one page for an empty payload.
    /// - Parameter count: Nonnegative requested capacity.
    /// - Returns: Exact anonymous-mapping capacity admitted before allocation.
    public static func backingCapacity(for count: Int) throws(DICOMAllocationError) -> Int {
        try legacyAllocationValue(backingCapacityOutcome(for: count))
    }

    /// Admit and map zero-filled payload and control storage.
    /// Package code may initialize the unpublished payload through its unsafe borrow.
    /// - Parameters:
    ///   - count: Logical bytes visible after initialization.
    ///   - capacity: Reconstruction capacity; defaults to logical count.
    ///   - budget: Shared ledger, borrowed without an implicit alias.
    ///   - resource: Initial payload class; control storage is always metadata.
    public init(count: Int, capacity: Int? = nil, budget: borrowing DICOMAllocationBudget,
                resource: DICOMAllocationClass) throws(DICOMAllocationError) {
        self = try legacyAllocationValue(Self.allocate(count: count, capacity: capacity,
                                                       budget: budget, resource: resource))
    }

    private init(retained owner: UnsafeMutablePointer<DICOMMappedOwner>) { mappedOwner = owner }

    /// Aggregate admission token bound to this exact payload/control owner, if enabled.
    /// Aliases and resource transfers preserve this identity. Reading it neither transfers
    /// release authority nor permits early retirement; the registered release callback
    /// remains responsible for notification after actual final mapping retirement.
    public var externalAllocationToken: UInt64? {
        mappedOwner.pointee.ledger.pointee.externalAdmission == nil ? nil : mappedOwner.pointee.externalToken
    }

    /// Borrowed aggregate context identity associated with `externalAllocationToken`.
    /// No context retain, allocation, or ownership transfer occurs when reading it.
    public var externalAdmissionContext: UnsafeMutableRawPointer? {
        mappedOwner.pointee.ledger.pointee.externalAdmission?.context
    }

    /// Retain this exact backing without another allocation or charge.
    /// - Returns: Another owning handle to the same immutable bytes.
    public borrowing func share() throws(DICOMAllocationError) -> DICOMByteBuffer {
        try legacyAllocationValue(shareOutcome())
    }

    /// Test the ledger identity charged for this buffer.
    /// - Parameter budget: Expected owner of payload and control capacities.
    public borrowing func isOwned(by budget: borrowing DICOMAllocationBudget) -> Bool {
        mappedOwner.pointee.ledger == budget.mappedLedger
    }

    /// Compare live backing identity without allocating a token or exposing a raw pointer.
    /// - Parameter other: Another live owner; a shared alias has the same identity and one charge.
    public borrowing func sameBacking(as other: borrowing DICOMByteBuffer) -> Bool {
        mappedOwner == other.mappedOwner
    }

    /// Borrow logical bytes synchronously; the pointer must not escape or be mutated.
    /// - Parameter body: Nonescaping operation while this handle remains borrowed.
    /// - Returns: The operation result; retained storage requires an owning handle.
    public borrowing func withUnsafeBytes<Result: ~Copyable, Failure: Error>(
        _ body: (UnsafeRawBufferPointer) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try body(UnsafeRawBufferPointer(start: mappedOwner.pointee.payload, count: count))
    }

    /// Copy logical bytes while retaining both original and new capacities.
    /// - Parameters:
    ///   - budget: Ledger admitting the new storage.
    ///   - resource: Initial payload class for the copy.
    /// - Returns: Independent bytes without unused reconstruction capacity.
    public borrowing func copy(budget: borrowing DICOMAllocationBudget, resource: DICOMAllocationClass)
        throws(DICOMAllocationError) -> DICOMByteBuffer {
        try legacyAllocationValue(copyOutcome(budget: budget, resource: resource))
    }

    /// Transfer the complete payload capacity exactly once across all aliases.
    /// - Parameter resource: Destination class; refusal preserves the original charge.
    public borrowing func transfer(to resource: DICOMAllocationClass) throws(DICOMAllocationError) {
        try legacyAllocationValue(transferOutcome(to: resource))
    }

    /// Observe actual retirement once, after the last alias dies, both mappings are unmapped,
    /// and their capacities are debited. A failed unmap never reports retirement.
    /// Install once before the first `share()`. The synchronous callback runs on the last
    /// releasing thread outside the ledger lock, with the ledger still retained. It must not
    /// allocate, block, wait for an actor, or access this destroyed buffer. It may read the ledger.
    /// - Parameters:
    ///   - context: Caller-owned, externally accounted state valid until retirement completes.
    ///     It must not reside in this buffer or its payload finalizer's destroyed state.
    ///   - callback: Noncapturing notification for releasing the caller's aggregate capacity lease.
    public borrowing func installRetirementObserver(context: UnsafeMutableRawPointer? = nil,
        callback: @convention(c) (UnsafeMutableRawPointer?) -> Void) throws(DICOMAllocationError) {
        try legacyAllocationValue(installRetirementObserverOutcome(context: context, callback: callback))
    }

    // Only unpublished construction or an explicitly synchronized control slab may use this pointer.
    // It exposes requested reconstruction capacity, not merely the published logical length.
    package var unsafeMutableBytes: UnsafeMutableRawBufferPointer {
        UnsafeMutableRawBufferPointer(start: mappedOwner.pointee.payload, count: mappedOwner.pointee.requestedCapacity)
    }

    // Install after successful payload construction, before publication/share. The noncapturing C
    // callback runs once outside the ledger lock, before unmap, with requested capacity. It destroys
    // in-place values/locks/descriptors and must not retain this owner or throw.
    package borrowing func installFinalizer(
        _ callback: @convention(c) (UnsafeMutableRawPointer?, Int) -> Void
    ) throws(DICOMAllocationError) {
        try legacyAllocationValue(installFinalizerOutcome(callback))
    }


    /// Determine exact payload capacity using scalar validation status.
    /// - Parameter count: Nonnegative requested bytes.
    /// - Returns: Page-rounded capacity or an overflow/size refusal.
    public static func backingCapacityOutcome(for count: Int) -> DICOMAllocationOutcome<Int> {
        DICOMMappedStorage.roundedCapacity(count)
    }

    /// Admit and allocate storage without entering Swift's throwing runtime.
    /// - Parameters:
    ///   - count: Logical immutable byte count.
    ///   - capacity: Complete requested reconstruction capacity, defaulting to count.
    ///   - budget: Ledger retaining all new payload and control capacity.
    ///   - resource: Payload allocation class.
    /// - Returns: Zero-filled storage or a scalar refusal with rollback completed.
    public static func allocate(count: Int, capacity: Int? = nil, budget: borrowing DICOMAllocationBudget,
        resource: DICOMAllocationClass) -> DICOMAllocationOutcome<Self> {
        switch DICOMMappedStorage.makeOwner(ledger: budget.mappedLedger, count: count,
            capacity: capacity ?? count, resource: resource, mapsPayload: true) {
        case .success(let owner): return .success(Self(retained: owner))
        case .failure(let error): return .failure(error)
        }
    }

    /// Retain the same immutable backing with scalar refusal status.
    /// - Returns: Another handle sharing one backing charge, or a refcount refusal.
    public borrowing func shareOutcome() -> DICOMAllocationOutcome<Self> {
        if let error = DICOMMappedStorage.retainOwner(mappedOwner) { return .failure(error) }
        return .success(Self(retained: mappedOwner))
    }

    /// Borrow logical bytes without an Error-constrained generic callback.
    /// - Parameter body: Synchronous nonthrowing callback; the pointer must not escape.
    /// - Returns: The callback's value, which may itself be a scalar outcome.
    public borrowing func withBorrowedBytes<Result: ~Copyable>(_ body: (UnsafeRawBufferPointer) -> Result) -> Result {
        body(UnsafeRawBufferPointer(start: mappedOwner.pointee.payload, count: count))
    }

    /// Copy while source and new backing overlap in the ledger.
    /// - Parameters:
    ///   - budget: Ledger admitting the independent copy.
    ///   - resource: New payload class.
    /// - Returns: Independent logical bytes or scalar refusal.
    public borrowing func copyOutcome(budget: borrowing DICOMAllocationBudget, resource: DICOMAllocationClass)
        -> DICOMAllocationOutcome<Self> {
        switch Self.allocate(count: count, budget: budget, resource: resource) {
        case .success(let result):
            result.unsafeMutableBytes.copyMemory(from:
                UnsafeRawBufferPointer(start: mappedOwner.pointee.payload, count: count))
            return .success(result)
        case .failure(let error): return .failure(error)
        }
    }

    /// Transfer the full payload once with scalar refusal status.
    /// - Parameter resource: Destination class; failed admission preserves the original class.
    /// - Returns: Success or scalar refusal.
    public borrowing func transferOutcome(to resource: DICOMAllocationClass) -> DICOMAllocationOutcome<Void> {
        if let error = DICOMMappedStorage.transfer(mappedOwner, to: resource) { return .failure(error) }
        return .success(())
    }

    /// Register the same final-retirement notification using scalar status.
    /// All lifetime and nonblocking obligations of `installRetirementObserver` apply.
    /// - Parameters:
    ///   - context: Externally accounted caller state, valid through retirement.
    ///   - callback: Thin notification after successful unmapping and ledger debit.
    /// - Returns: Success or duplicate/shared-registration refusal.
    public borrowing func installRetirementObserverOutcome(context: UnsafeMutableRawPointer? = nil,
        callback: @convention(c) (UnsafeMutableRawPointer?) -> Void) -> DICOMAllocationOutcome<Void> {
        if let error = DICOMMappedStorage.installRetirementObserver(mappedOwner, context: context, callback: callback) {
            return .failure(error)
        }
        return .success(())
    }

    package borrowing func installFinalizerOutcome(
        _ callback: @convention(c) (UnsafeMutableRawPointer?, Int) -> Void) -> DICOMAllocationOutcome<Void> {
        if let error = DICOMMappedStorage.installFinalizer(mappedOwner, callback) { return .failure(error) }
        return .success(())
    }

    deinit { DICOMMappedStorage.releaseOwner(mappedOwner) }
}
