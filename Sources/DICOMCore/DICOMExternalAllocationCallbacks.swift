// NEMA-verified: 2026a, checked 2026-10-15 — no DICOM-standard data (aggregate allocation admission).

/// Thin C callbacks connecting a local budget to a caller-owned aggregate ledger.
/// No Swift object or capturing closure is created by this value.
///
/// Status zero means success. Other statuses are preserved in
/// `DICOMAllocationError.externalAdmissionRefused`. Successful admission writes a
/// nonzero, unique live token; refusal writes zero and retains no reservation.
/// The resource argument is `Int32(DICOMAllocationClass.rawValue)`.
///
/// Callbacks must be thread-safe, nonallocating and nonblocking. Admission and
/// transfer run under the local budget mutex and must not reenter that budget.
/// Do not hold an aggregate lock while calling into a budget that may acquire it.
/// Release and context callbacks run outside the budget mutex.
public struct DICOMExternalAllocationCallbacks: @unchecked Sendable {
    /// Caller-owned state; its storage and the callbacks themselves require independent admission.
    public let context: UnsafeMutableRawPointer?
    /// Acquire one context lifetime before bootstrap admission. Refusal acquires no ownership.
    public let retainContext: @convention(c) (UnsafeMutableRawPointer?) -> Int32
    /// Atomically admit complete payload and metadata/control capacities before any mapping.
    /// Payload zero with one control page is the budget's own bootstrap allocation.
    public let admit: @convention(c) (
        UnsafeMutableRawPointer?, Int32, Int, Int, UnsafeMutablePointer<UInt64>?
    ) -> Int32
    /// Retire the entire token exactly once after every backing mapping has been unmapped,
    /// or after admission rollback when no backing remains. A partial unmap failure
    /// conservatively retains the entire token, including successfully unmapped components.
    public let release: @convention(c) (UnsafeMutableRawPointer?, UInt64) -> Void
    /// Atomically reclassify the token's complete payload. Control remains metadata.
    /// A nonzero result must leave the token and all aggregate charges unchanged.
    public let transfer: @convention(c) (UnsafeMutableRawPointer?, UInt64, Int32) -> Int32
    /// Release the acquired context lifetime after the ledger's successful final unmap
    /// and token release, or complete bootstrap rollback. Never called for quarantine.
    /// No callback or context access occurs after this returns.
    public let releaseContext: @convention(c) (UnsafeMutableRawPointer?) -> Void

    /// Construct callbacks without allocating storage or taking context ownership.
    /// `DICOMAllocationBudget.make(limits:externalAdmission:)` takes ownership by
    /// calling `retainContext`; the caller must keep the context valid until then.
    public init(
        context: UnsafeMutableRawPointer? = nil,
        retainContext: @escaping @convention(c) (UnsafeMutableRawPointer?) -> Int32,
        admit: @escaping @convention(c) (
            UnsafeMutableRawPointer?, Int32, Int, Int, UnsafeMutablePointer<UInt64>?
        ) -> Int32,
        release: @escaping @convention(c) (UnsafeMutableRawPointer?, UInt64) -> Void,
        transfer: @escaping @convention(c) (UnsafeMutableRawPointer?, UInt64, Int32) -> Int32,
        releaseContext: @escaping @convention(c) (UnsafeMutableRawPointer?) -> Void
    ) {
        self.context = context
        self.retainContext = retainContext
        self.admit = admit
        self.release = release
        self.transfer = transfer
        self.releaseContext = releaseContext
    }
}
