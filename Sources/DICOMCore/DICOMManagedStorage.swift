// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (typed admission adapters).

extension DICOMByteBuffer {
    /// Admit without entering Swift's throwing runtime.
    package static func admit(count: Int, capacity: Int? = nil,
        budget: borrowing DICOMAllocationBudget, resource: DICOMAllocationClass)
        -> DICOMManagedOutcome<DICOMByteBuffer> {
        switch allocate(count: count, capacity: capacity, budget: budget, resource: resource) {
        case .success(let value): return .success(value)
        case .failure(let failure): return .failure(DICOMManagedFailure(allocation: failure))
        }
    }
    /// Retain an explicit alias through a scalar outcome.
    package borrowing func managedShareOutcome() -> DICOMManagedOutcome<DICOMByteBuffer> {
        switch shareOutcome() {
        case .success(let value): return .success(value)
        case .failure(let failure): return .failure(DICOMManagedFailure(allocation: failure))
        }
    }
    /// Throwing compatibility adapter outside the qualified boundary.
    package static func admitted(count: Int, capacity: Int? = nil,
        budget: borrowing DICOMAllocationBudget, resource: DICOMAllocationClass)
        throws(DICOMManagedFailure) -> DICOMByteBuffer {
        do { return try DICOMByteBuffer(count: count, capacity: capacity, budget: budget, resource: resource) }
        catch { throw DICOMManagedFailure(allocation: error) }
    }
    /// Retain one explicit alias without allocating another ownership object.
    package borrowing func managedShare() throws(DICOMManagedFailure) -> DICOMByteBuffer {
        do { return try share() }
        catch { throw DICOMManagedFailure(allocation: error) }
    }
}

extension DICOMAllocationBudget {
    /// Retain the ledger through a scalar outcome.
    package borrowing func managedShareOutcome() -> DICOMManagedOutcome<DICOMAllocationBudget> {
        switch shareOutcome() {
        case .success(let value): return .success(value)
        case .failure(let failure): return .failure(DICOMManagedFailure(allocation: failure))
        }
    }
    /// Retain the mapped ledger without allocating an ARC wrapper.
    package borrowing func managedShare() throws(DICOMManagedFailure) -> DICOMAllocationBudget {
        do { return try share() }
        catch { throw DICOMManagedFailure(allocation: error) }
    }
}
