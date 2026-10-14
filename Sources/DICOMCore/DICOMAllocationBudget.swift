// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (allocation ownership).
import Foundation

/// Backing-storage classes. Metadata consumes the staging limit, but is reported separately.
public enum DICOMAllocationClass: Int, Sendable, CaseIterable {
    case encoded, decoded, staging, resident, preview, metadata
}

/// Failures are reported before allocation; cancellation never releases an existing lease.
public enum DICOMAllocationError: Error, Equatable, Sendable {
    case invalidSize
    case budgetMismatch
    case limitExceeded(DICOMAllocationClass)
    case totalLimitExceeded
    case allocationFailed
    case alreadyTransferred
}

/// Immutable per-class usage, including capacities rather than just logical lengths.
public struct DICOMAllocationUsage: Sendable, Equatable {
    /// Live encoded-input backing bytes.
    public internal(set) var encoded = 0
    /// Live decoded-output backing bytes before ownership transfer.
    public internal(set) var decoded = 0
    /// Live temporary payload backing bytes, excluding separately reported metadata.
    public internal(set) var staging = 0
    /// Live backing bytes transferred to resident ownership.
    public internal(set) var resident = 0
    /// Live backing bytes transferred to preview ownership.
    public internal(set) var preview = 0
    /// Live metadata charges, which share the staging limit.
    public internal(set) var metadata = 0
    /// Create a zero-usage snapshot.
    public init() {}
    /// Read usage for one allocation class.
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

/// A snapshot of live and peak admitted storage. Class peaks need not be simultaneous.
public struct DICOMAllocationReceipt: Sendable, Equatable {
    /// Simultaneously live charges by class at capture time.
    public let current: DICOMAllocationUsage
    /// Independent per-class peaks; these need not occur simultaneously.
    public let peak: DICOMAllocationUsage
    /// Sum of all simultaneously live charges at capture time.
    public let currentTotal: Int
    /// Maximum simultaneous total charge observed by this ledger.
    public let peakTotal: Int
    /// Number of retained allocation leases at capture time.
    public let liveAllocations: Int
}

/// A caller-owned, synchronous admission ledger for explicitly managed storage.
///
/// Share one instance across concurrent jobs to enforce their aggregate cap. Holding
/// a reference to a buffer retains its charge; cancelling a task or subscriber does
/// not change this ledger. This is not an interceptor for arbitrary Swift/Foundation
/// or codec allocations. Such operations require their own complete reservations.
public final class DICOMAllocationBudget: @unchecked Sendable {
    /// Frozen default class and aggregate limits for bounded workstation input.
    public struct Limits: Sendable {
        /// Maximum live encoded-input charge.
        public let encoded: Int
        /// Maximum live decoded-output charge.
        public let decoded: Int
        /// Maximum combined staging and metadata charge.
        public let staging: Int
        /// Maximum live resident charge.
        public let resident: Int
        /// Maximum live preview charge.
        public let preview: Int
        /// Maximum simultaneous charge across all classes.
        public let total: Int
        /// Configure byte limits; validation occurs when constructing the budget.
        /// - Parameters:
        ///   - encoded: Encoded-input limit in bytes.
        ///   - decoded: Decoded-output limit in bytes.
        ///   - staging: Shared staging/metadata limit in bytes.
        ///   - resident: Resident-storage limit in bytes.
        ///   - preview: Preview-storage limit in bytes.
        ///   - total: Aggregate simultaneous limit in bytes.
        public init(encoded: Int = 128 * 1024 * 1024,
                    decoded: Int = 384 * 1024 * 1024,
                    staging: Int = 64 * 1024 * 1024,
                    resident: Int = 384 * 1024 * 1024,
                    preview: Int = 32 * 1024 * 1024,
                    total: Int = 1024 * 1024 * 1024) {
            self.encoded = encoded; self.decoded = decoded; self.staging = staging
            self.resident = resident; self.preview = preview; self.total = total
        }
        fileprivate subscript(_ resource: DICOMAllocationClass) -> Int {
            switch resource {
            case .encoded: encoded
            case .decoded: decoded
            case .staging, .metadata: staging
            case .resident: resident
            case .preview: preview
            }
        }
    }
    /// Immutable class and aggregate limits enforced by this ledger.
    public let limits: Limits
    private let lock = NSLock()
    private var current = DICOMAllocationUsage()
    private var peak = DICOMAllocationUsage()
    private var currentTotal = 0
    private var peakTotal = 0
    private var liveAllocations = 0
    private var allocationFailureAfter: Int?

    /// Create an empty ledger, rejecting any negative limit.
    /// - Parameter limits: Byte capacities shared by all storage using this instance.
    public init(limits: Limits = Limits()) throws {
        guard limits.total >= 0,
              DICOMAllocationClass.allCases.allSatisfy({ limits[$0] >= 0 }) else {
            throw DICOMAllocationError.invalidSize
        }
        self.limits = limits
    }

    // Per-ledger deterministic allocator failure hook, available only to tests.
    convenience init(limits: Limits = Limits(), allocationFailureAfter: Int) throws {
        try self.init(limits: limits)
        self.allocationFailureAfter = allocationFailureAfter
    }
    package func willAllocateBacking() throws {
        lock.lock(); defer { lock.unlock() }
        if let remaining = allocationFailureAfter {
            guard remaining > 0 else { throw DICOMAllocationError.allocationFailed }
            allocationFailureAfter = remaining - 1
        }
    }

    /// Capture current usage and peaks atomically under the ledger lock.
    public var receipt: DICOMAllocationReceipt {
        lock.lock(); defer { lock.unlock() }
        return DICOMAllocationReceipt(current: current, peak: peak,
            currentTotal: currentTotal, peakTotal: peakTotal, liveAllocations: liveAllocations)
    }

    /// Reserve a proven capacity before its allocation. The returned lease must be
    /// retained by the storage owner until destruction, including all error paths.
    /// - Parameters:
    ///   - bytes: Complete capacity to charge, including allocation rounding.
    ///   - resource: Initial allocation class.
    /// - Returns: A lease that releases the charge on destruction.
    public func reserve(_ bytes: Int, as resource: DICOMAllocationClass) throws -> DICOMAllocationLease {
        lock.lock(); defer { lock.unlock() }
        try check(bytes, as: resource)
        add(bytes, as: resource)
        liveAllocations += 1
        return DICOMAllocationLease(budget: self, bytes: bytes, resource: resource)
    }

    private func check(_ bytes: Int, as resource: DICOMAllocationClass) throws {
        guard bytes >= 0 else { throw DICOMAllocationError.invalidSize }
        let used = resource == .metadata || resource == .staging
            ? current.metadata + current.staging : current[resource]
        guard used <= limits[resource], bytes <= limits[resource] - used else {
            throw DICOMAllocationError.limitExceeded(resource)
        }
        guard currentTotal <= limits.total, bytes <= limits.total - currentTotal else {
            throw DICOMAllocationError.totalLimitExceeded
        }
    }
    private func add(_ bytes: Int, as resource: DICOMAllocationClass) {
        current[resource] += bytes
        currentTotal += bytes
        peak[resource] = max(peak[resource], current[resource])
        peakTotal = max(peakTotal, currentTotal)
    }
    fileprivate func release(_ bytes: Int, as resource: DICOMAllocationClass) {
        lock.lock(); defer { lock.unlock() }
        current[resource] -= bytes; currentTotal -= bytes; liveAllocations -= 1
    }
    fileprivate func transfer(_ lease: DICOMAllocationLease, to resource: DICOMAllocationClass) throws {
        lock.lock(); defer { lock.unlock() }
        guard !lease.transferred else { throw DICOMAllocationError.alreadyTransferred }
        // Remove the old class only while holding the lock. Failure restores it;
        // readers never see an uncharged allocation or transient double charge.
        current[lease.resource] -= lease.bytes; currentTotal -= lease.bytes
        do { try check(lease.bytes, as: resource) }
        catch {
            current[lease.resource] += lease.bytes; currentTotal += lease.bytes
            throw error
        }
        add(lease.bytes, as: resource)
        lease.resource = resource; lease.transferred = true
    }
}

/// A single backing allocation's ARC lifetime. Aliases share this lease.
public final class DICOMAllocationLease: @unchecked Sendable {
    private let budget: DICOMAllocationBudget
    /// Complete charge retained until this lease is destroyed.
    public let bytes: Int
    fileprivate var resource: DICOMAllocationClass
    fileprivate var transferred = false
    fileprivate init(budget: DICOMAllocationBudget, bytes: Int, resource: DICOMAllocationClass) {
        self.budget = budget; self.bytes = bytes; self.resource = resource
    }
    /// Transfer retained output into its destination class exactly once.
    /// - Parameter resource: Destination allocation class; failed admission leaves ownership unchanged.
    public func transfer(to resource: DICOMAllocationClass) throws {
        try budget.transfer(self, to: resource)
    }
    deinit { budget.release(bytes, as: resource) }
}
