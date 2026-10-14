// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (worker stack admission).
#if canImport(Darwin)
import Darwin
#endif

/// Admission of the complete usable stack of an existing synchronous Darwin worker.
///
/// This value reserves the stack capacity reported by pthread, plus a real mapped lease
/// header. It does not create or own the worker. Its thread, TLS, runtime initialization,
/// inputs and cancellation contexts must already be caller-owned. Inaccessible guard VM
/// is not usable backing. This admission does not promise survival of process-wide OOM.
///
/// Create the reservation before entering qualified work, validate it against the operation's
/// ledger, and retain it until that worker actually returns, including cancellation/failure.
/// Never suspend asynchronously while using it. Low-level buffer APIs remain portable;
/// they do not implicitly reserve a stack or qualify arbitrary caller callbacks.
public struct DICOMExecutionReservation: ~Copyable, @unchecked Sendable {
    private let lease: DICOMAllocationLease
    private let threadID: UInt64
    private let stackTop: UInt
    /// Entire reported usable stack capacity, charged as metadata until destruction.
    public let stackByteCount: Int
    /// Actual mapped control capacity of the retained stack reservation.
    public var controlByteCount: Int { lease.controlCapacity }
    /// Stack plus reservation control capacity, excluding the shared ledger bootstrap page.
    public var retainedByteCount: Int { stackByteCount + controlByteCount }

    /// Admit the current thread's complete reported usable stack and a shared lease header.
    /// - Parameter budget: Ledger used by every operation inside this synchronous worker.
    /// - Throws: A scalar refusal, query failure, or unsupported-platform status before qualified work.
    @available(*, noasync, message: "Retain the reservation inside one synchronous worker; never across suspension")
    public init(budget: borrowing DICOMAllocationBudget) throws(DICOMAllocationError) {
        self = try legacyAllocationValue(Self.reserve(budget: budget))
    }

    private init(lease: consuming DICOMAllocationLease, threadID: UInt64, stackTop: UInt, stackByteCount: Int) {
        self.lease = lease; self.threadID = threadID; self.stackTop = stackTop; self.stackByteCount = stackByteCount
    }

    /// Admit the whole current worker stack using scalar status.
    /// - Parameter budget: Ledger retaining the stack and lease header through actual return.
    /// - Returns: A reservation or query/admission failure, without a throwing-runtime call.
    @available(*, noasync, message: "Retain inside one synchronous worker, never across suspension")
    public static func reserve(budget: borrowing DICOMAllocationBudget) -> DICOMAllocationOutcome<Self> {
        #if canImport(Darwin)
        let current = pthread_self()
        let address: UnsafeMutableRawPointer? = pthread_get_stackaddr_np(current)
        guard let address, let size = Int(exactly: pthread_get_stacksize_np(current)), size > 0,
              UInt(bitPattern: address) >= UInt(size) else { return .failure(.stackUnavailable) }
        var identifier: UInt64 = 0
        guard pthread_threadid_np(current, &identifier) == 0 else { return .failure(.stackUnavailable) }
        switch budget.reserveOutcome(size, as: .metadata) {
        case .success(let lease):
            return .success(Self(lease: lease, threadID: identifier,
                                 stackTop: UInt(bitPattern: address), stackByteCount: size))
        case .failure(let error): return .failure(error)
        }
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }

    /// Require the original worker, unchanged reported stack bounds and the original ledger.
    /// Call before the qualified synchronous operation; no thread may suspend or change stacks inside it.
    /// - Parameter budget: Ledger expected to retain all operation capacities.
    @available(*, noasync, message: "Validate on the same synchronous worker that owns the reservation")
    public borrowing func validate(budget: borrowing DICOMAllocationBudget) throws(DICOMAllocationError) {
        try legacyAllocationValue(validateOutcome(budget: budget))
    }

    /// Validate the retained worker, stack bounds and ledger with scalar status.
    /// - Parameter budget: Ledger expected to own this synchronous operation.
    /// - Returns: Success or a precise identity/query refusal.
    @available(*, noasync, message: "Validate on the original synchronous worker")
    public borrowing func validateOutcome(budget: borrowing DICOMAllocationBudget) -> DICOMAllocationOutcome<Void> {
        guard lease.isOwned(by: budget) else { return .failure(.budgetMismatch) }
        #if canImport(Darwin)
        let current = pthread_self()
        var identifier: UInt64 = 0
        guard pthread_threadid_np(current, &identifier) == 0 else { return .failure(.stackUnavailable) }
        guard identifier == threadID else { return .failure(.threadMismatch) }
        let address: UnsafeMutableRawPointer? = pthread_get_stackaddr_np(current)
        guard let address, UInt(bitPattern: address) == stackTop,
              Int(exactly: pthread_get_stacksize_np(current)) == stackByteCount else {
            return .failure(.threadMismatch)
        }
        return .success(())
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }
}
