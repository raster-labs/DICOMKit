// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (typed admission adapters).

extension DICOMByteBuffer {
    /// Admit without entering Swift's throwing runtime.
    public static func admit(count: Int, capacity: Int? = nil,
        budget: borrowing DICOMAllocationBudget, resource: DICOMAllocationClass)
        -> DICOMManagedOutcome<DICOMByteBuffer> {
        switch allocate(count: count, capacity: capacity, budget: budget, resource: resource) {
        case .success(let value): return .success(value)
        case .failure(let failure): return .failure(DICOMManagedFailure(allocation: failure))
        }
    }
    /// Admit, map, and initialize unpublished payload storage in one scoped non-escaping callback.
    /// If `initializingWith` returns a `DICOMManagedFailure`, the newly mapped buffer is destroyed
    /// and debited from `budget` before returning `.failure`. Once published, the buffer is immutable.
    public static func admitInitialized(
        count: Int,
        capacity: Int? = nil,
        budget: borrowing DICOMAllocationBudget,
        resource: DICOMAllocationClass,
        initializingWith body: (UnsafeMutableRawBufferPointer) -> DICOMManagedFailure?
    ) -> DICOMManagedOutcome<DICOMByteBuffer> {
        switch admit(count: count, capacity: capacity, budget: budget, resource: resource) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let buffer):
            let slice = UnsafeMutableRawBufferPointer(start: buffer.mappedOwner.pointee.payload, count: count)
            let failure = body(slice)
            buffer.keepAlive()
            if let failure {
                return .failure(failure)
            }
            return .success(buffer)
        }
    }
    /// Retain an explicit alias through a scalar outcome.
    public borrowing func managedShareOutcome() -> DICOMManagedOutcome<DICOMByteBuffer> {
        switch shareOutcome() {
        case .success(let value): return .success(value)
        case .failure(let failure): return .failure(DICOMManagedFailure(allocation: failure))
        }
    }
    /// Throwing compatibility adapter outside the qualified boundary.
    public static func admitted(count: Int, capacity: Int? = nil,
        budget: borrowing DICOMAllocationBudget, resource: DICOMAllocationClass)
        throws(DICOMManagedFailure) -> DICOMByteBuffer {
        do { return try DICOMByteBuffer(count: count, capacity: capacity, budget: budget, resource: resource) }
        catch { throw DICOMManagedFailure(allocation: error) }
    }
    /// Retain one explicit alias without allocating another ownership object.
    public borrowing func managedShare() throws(DICOMManagedFailure) -> DICOMByteBuffer {
        do { return try share() }
        catch { throw DICOMManagedFailure(allocation: error) }
    }
}

extension DICOMAllocationBudget {
    /// Retain the ledger through a scalar outcome.
    public borrowing func managedShareOutcome() -> DICOMManagedOutcome<DICOMAllocationBudget> {
        switch shareOutcome() {
        case .success(let value): return .success(value)
        case .failure(let failure): return .failure(DICOMManagedFailure(allocation: failure))
        }
    }
    /// Retain the mapped ledger without allocating an ARC wrapper.
    public borrowing func managedShare() throws(DICOMManagedFailure) -> DICOMAllocationBudget {
        do { return try share() }
        catch { throw DICOMManagedFailure(allocation: error) }
    }
}
