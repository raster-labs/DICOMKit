// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (allocation ownership).

/// Backing-storage classes. Metadata shares the staging limit.
public enum DICOMAllocationClass: Int, Sendable, CaseIterable {
    case encoded = 0, decoded = 1, staging = 2, resident = 3, preview = 4, metadata = 5
}

/// Scalar admission and storage failures carried by nonthrowing allocation outcomes.
/// Error conformance is used only by the compatibility throwing adapters.
public enum DICOMAllocationError: Error, Equatable, Sendable {
    case invalidSize
    case budgetMismatch
    case limitExceeded(DICOMAllocationClass)
    case totalLimitExceeded
    case allocationFailed
    case alreadyTransferred
    case referenceCountOverflow
    case synchronizationFailed
    case sharedMutation
    case finalizerAlreadyInstalled
    case retirementObserverAlreadyInstalled
    case stackUnavailable
    case threadMismatch
    case unsupportedPlatform
    /// Exact nonzero status returned by caller-owned aggregate admission or transfer.
    case externalAdmissionRefused(Int32)
}

/// Per-class live or peak capacities, including mapped control pages.
public struct DICOMAllocationUsage: Sendable, Equatable {
    /// Encoded-input capacity.
    public internal(set) var encoded = 0
    /// Decoded-output capacity.
    public internal(set) var decoded = 0
    /// Temporary payload capacity.
    public internal(set) var staging = 0
    /// Retained resident capacity.
    public internal(set) var resident = 0
    /// Retained preview capacity.
    public internal(set) var preview = 0
    /// Control and metadata capacity, sharing the staging limit.
    public internal(set) var metadata = 0
    /// Create a zero-usage value.
    public init() {}
    /// Read or update one class in this value snapshot.
    public subscript(_ resource: DICOMAllocationClass) -> Int {
        get {
            switch resource {
            case .encoded: encoded
            case .decoded: decoded
            case .staging: staging
            case .resident: resident
            case .preview: preview
            case .metadata: metadata
            }
        }
        set {
            switch resource {
            case .encoded: encoded = newValue
            case .decoded: decoded = newValue
            case .staging: staging = newValue
            case .resident: resident = newValue
            case .preview: preview = newValue
            case .metadata: metadata = newValue
            }
        }
    }
}

/// Atomic live and peak capacity snapshot; class peaks need not be simultaneous.
public struct DICOMAllocationReceipt: Sendable, Equatable {
    /// Simultaneously retained capacities by class.
    public let current: DICOMAllocationUsage
    /// Independent class peaks.
    public let peak: DICOMAllocationUsage
    /// Simultaneously retained aggregate capacity.
    public let currentTotal: Int
    /// Peak simultaneous aggregate capacity.
    public let peakTotal: Int
    /// Retained storage owners, including the ledger's own mapping.
    public let liveAllocations: Int
}

/// Explicitly shared ledger whose mutex, counters and limits occupy its admitted mapping.
///
/// A handle is move-only. `share()` creates another owning handle without allocating.
/// Storage owners retain the ledger independently, so destroying the caller's handle
/// cannot erase live charges. The ledger's own page is charged as metadata at creation.
public struct DICOMAllocationBudget: ~Copyable, @unchecked Sendable {
    /// Frozen byte limits for bounded workstation input.
    public struct Limits: Sendable {
        /// Encoded-input limit.
        public let encoded: Int
        /// Decoded-output limit.
        public let decoded: Int
        /// Combined staging and metadata limit.
        public let staging: Int
        /// Resident-storage limit.
        public let resident: Int
        /// Preview-storage limit.
        public let preview: Int
        /// Aggregate simultaneous limit.
        public let total: Int
        /// Configure byte limits; negative limits are rejected by the ledger initializer.
        public init(encoded: Int = 128 * 1024 * 1024, decoded: Int = 384 * 1024 * 1024,
                    staging: Int = 64 * 1024 * 1024, resident: Int = 384 * 1024 * 1024,
                    preview: Int = 32 * 1024 * 1024, total: Int = 1024 * 1024 * 1024) {
            self.encoded = encoded; self.decoded = decoded; self.staging = staging
            self.resident = resident; self.preview = preview; self.total = total
        }
        subscript(_ resource: DICOMAllocationClass) -> Int {
            switch resource {
            case .encoded: encoded
            case .decoded: decoded
            case .staging, .metadata: staging
            case .resident: resident
            case .preview: preview
            }
        }
    }

    let mappedLedger: UnsafeMutablePointer<DICOMMappedLedger>

    /// Actual capacity of the ledger control mapping, admitted before mapping it.
    public static var controlCapacity: Int { DICOMMappedStorage.pageSize }
    /// Immutable limits shared by all aliases and retained storage owners.
    public var limits: Limits { mappedLedger.pointee.limits }
    /// Borrowed identity of the aggregate admission context, when supplied.
    /// This getter does not acquire context ownership or authorize its mutation.
    public var externalAdmissionContext: UnsafeMutableRawPointer? {
        mappedLedger.pointee.externalAdmission?.context
    }

    /// Create a ledger, admitting its own control page against staging and total limits.
    /// - Parameter limits: Complete per-instance limits, including control storage.
    public init(limits: Limits = Limits()) throws(DICOMAllocationError) {
        self = try legacyAllocationValue(Self.make(limits: limits))
    }

    // Per-instance deterministic mmap failure injection; the bootstrap ledger is not counted.
    init(limits: Limits = Limits(), allocationFailureAfter: Int) throws(DICOMAllocationError) {
        self = try legacyAllocationValue(Self.make(limits: limits, allocationFailureAfter: allocationFailureAfter))
    }

    private init(retained ledger: UnsafeMutablePointer<DICOMMappedLedger>) { mappedLedger = ledger }

    /// Create a ledger with scalar admission status and no throwing-runtime boundary.
    /// - Parameter limits: Complete limits including the ledger's own mapped page.
    /// - Returns: An admitted ledger or the exact refusal reason.
    public static func make(limits: Limits = Limits()) -> DICOMAllocationOutcome<Self> {
        makeInternal(limits: limits, failureAfter: -1)
    }
    /// Create a local ledger whose complete storage also requires aggregate admission.
    /// The callbacks cover the ledger page, mapped payload/control pairs, and external
    /// reservations. Local limits continue to apply. Context ownership lasts through
    /// actual final ledger unmap; any quarantined mapping retains that ownership.
    /// - Parameters:
    ///   - limits: Complete per-instance limits, including the ledger's own page.
    ///   - externalAdmission: Thin callbacks and an independently admitted context.
    /// - Returns: An admitted ledger or the exact local/aggregate refusal.
    public static func make(limits: Limits = Limits(), externalAdmission: DICOMExternalAllocationCallbacks)
        -> DICOMAllocationOutcome<Self> {
        makeInternal(limits: limits, failureAfter: -1, externalAdmission: externalAdmission)
    }
    static func make(limits: Limits = Limits(), allocationFailureAfter: Int) -> DICOMAllocationOutcome<Self> {
        guard allocationFailureAfter >= 0 else { return .failure(.invalidSize) }
        return makeInternal(limits: limits, failureAfter: allocationFailureAfter)
    }
    private static func makeInternal(limits: Limits, failureAfter: Int,
        externalAdmission: DICOMExternalAllocationCallbacks? = nil) -> DICOMAllocationOutcome<Self> {
        switch DICOMMappedStorage.makeLedger(limits: limits, failureAfter: failureAfter,
            externalAdmission: externalAdmission) {
        case .success(let ledger): return .success(Self(retained: ledger))
        case .failure(let error): return .failure(error)
        }
    }

    /// Retain the ledger using scalar status, without allocating or entering throwing runtime.
    /// - Returns: Another owner of the same ledger or a reference-count refusal.
    public borrowing func shareOutcome() -> DICOMAllocationOutcome<Self> {
        if let error = DICOMMappedStorage.retainLedger(mappedLedger) { return .failure(error) }
        return .success(Self(retained: mappedLedger))
    }


    /// Retain the same ledger without allocating any storage.
    /// - Returns: A separately owned handle to the same counters and mutex.
    public borrowing func share() throws(DICOMAllocationError) -> DICOMAllocationBudget {
        try legacyAllocationValue(shareOutcome())
    }

    /// Compare retained ledger identity without creating another handle.
    /// - Parameter other: Ledger whose identity is compared.
    public borrowing func isSameOwner(as other: borrowing DICOMAllocationBudget) -> Bool {
        mappedLedger == other.mappedLedger
    }

    /// Capture live and peak capacities while holding the in-place mutex.
    public var receipt: DICOMAllocationReceipt { DICOMMappedStorage.receipt(mappedLedger) }

    /// Reserve external storage capacity plus a real page for this lease's shared control state.
    /// The caller must independently prove the external allocation's complete capacity.
    /// - Parameters:
    ///   - bytes: External capacity retained by this lease, with allocator rounding included.
    ///   - resource: Class charged for that external capacity.
    /// - Returns: Move-only lease; aliases require `share()` and keep one charge alive.
    public borrowing func reserve(_ bytes: Int, as resource: DICOMAllocationClass)
        throws(DICOMAllocationError) -> DICOMAllocationLease {
        try legacyAllocationValue(reserveOutcome(bytes, as: resource))
    }


    /// Admit external capacity and a mapped lease header using only scalar status.
    /// - Parameters:
    ///   - bytes: Proven complete caller-owned external capacity.
    ///   - resource: Class retaining that capacity.
    /// - Returns: An owning lease or an unchanged-ledger refusal.
    public borrowing func reserveOutcome(_ bytes: Int, as resource: DICOMAllocationClass)
        -> DICOMAllocationOutcome<DICOMAllocationLease> {
        switch DICOMMappedStorage.makeOwner(ledger: mappedLedger, count: bytes,
            capacity: bytes, resource: resource, mapsPayload: false) {
        case .success(let owner): return .success(DICOMAllocationLease(retained: owner))
        case .failure(let error): return .failure(error)
        }
    }

    deinit { DICOMMappedStorage.releaseLedger(mappedLedger) }
}

/// Move-only owner of an external reservation and its mapped shared control page.
public struct DICOMAllocationLease: ~Copyable, @unchecked Sendable {
    let mappedOwner: UnsafeMutablePointer<DICOMMappedOwner>
    init(retained owner: UnsafeMutablePointer<DICOMMappedOwner>) { mappedOwner = owner }

    /// External capacity retained by this lease, excluding its metadata control page.
    public var bytes: Int { mappedOwner.pointee.payloadCapacity }
    /// Actual mapped capacity of the shared lease control state.
    public var controlCapacity: Int { mappedOwner.pointee.controlCapacity }

    /// Compare the ledger retaining this reservation without creating another handle.
    /// - Parameter budget: Expected admission ledger.
    public borrowing func isOwned(by budget: borrowing DICOMAllocationBudget) -> Bool {
        mappedOwner.pointee.ledger == budget.mappedLedger
    }

    /// Retain the existing reservation without allocating or double charging it.
    /// - Returns: Another independently owned handle to the same lease.
    public borrowing func share() throws(DICOMAllocationError) -> DICOMAllocationLease {
        try legacyAllocationValue(shareOutcome())
    }

    /// Move the external capacity to another class exactly once across all aliases.
    /// - Parameter resource: Destination class; failed admission leaves the original charge intact.
    public borrowing func transfer(to resource: DICOMAllocationClass) throws(DICOMAllocationError) {
        try legacyAllocationValue(transferOutcome(to: resource))
    }


    /// Retain the same reservation using a scalar result.
    /// - Returns: An alias or a reference-count refusal, without a throwing-runtime call.
    public borrowing func shareOutcome() -> DICOMAllocationOutcome<Self> {
        if let error = DICOMMappedStorage.retainOwner(mappedOwner) { return .failure(error) }
        return .success(Self(retained: mappedOwner))
    }

    /// Transfer this reservation once with scalar refusal status.
    /// - Parameter resource: Destination allocation class.
    /// - Returns: Success or the original charge-preserving refusal.
    public borrowing func transferOutcome(to resource: DICOMAllocationClass) -> DICOMAllocationOutcome<Void> {
        if let error = DICOMMappedStorage.transfer(mappedOwner, to: resource) { return .failure(error) }
        return .success(())
    }

    deinit { DICOMMappedStorage.releaseOwner(mappedOwner) }
}

// Compatibility boundary only. Qualified operations switch on outcomes directly.
func legacyAllocationValue<Value: ~Copyable>(_ outcome: consuming DICOMAllocationOutcome<Value>)
    throws(DICOMAllocationError) -> Value {
    switch consume outcome {
    case .success(let value): return value
    case .failure(let error): throw error
    }
}
