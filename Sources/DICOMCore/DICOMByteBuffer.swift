// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (owned byte storage).
import Foundation

/// Immutable, explicitly admitted bytes. Sharing this reference shares one backing
/// and one charge. A copy requires a second allocation. Borrowed pointers must not
/// escape their closure or be mutated. No implicit `Data`/Array bridge is provided.
public final class DICOMByteBuffer: @unchecked Sendable {
    private let storage: AlignedPixelBuffer
    let ownerBudget: DICOMAllocationBudget
    private let controlLease: DICOMAllocationLease
    /// Logical byte count exposed by immutable borrows.
    public let count: Int
    /// Complete page-rounded backing capacity charged for this buffer's lifetime.
    public var capacity: Int { storage.allocatedByteCount }

    /// Reserved allowance for the fixed-size buffer, storage and lease objects.
    /// It does not cover arbitrary allocations made by a caller's initialization
    /// or borrowing closure. Variable-sized payloads always have separate leases.
    public static var controlCapacity: Int { AlignedPixelBuffer.pageSize }

    /// Checked page rounding, including a physical page for an empty buffer.
    /// - Parameter count: Requested backing length, which must be nonnegative.
    /// - Returns: Capacity reserved before allocating the anonymous mapping.
    public static func backingCapacity(for count: Int) throws -> Int {
        let page = AlignedPixelBuffer.pageSize
        guard count >= 0, count <= Int.max - (page - 1) else {
            throw DICOMAllocationError.invalidSize
        }
        return max(page, ((count + page - 1) / page) * page)
    }

    /// The initializer owns the sole mutable borrow. If it throws, the mapping is
    /// destroyed before its reservations are released. `capacity` may exceed the
    /// visible `count` when reconstruction compacts a larger arena in place. The
    /// initializer receives the requested capacity; later borrows expose only count.
    /// The entire page-rounded capacity remains charged until backing destruction.
    /// - Parameters:
    ///   - count: Logical bytes exposed after initialization.
    ///   - capacity: Requested reconstruction capacity; defaults to `count`.
    ///   - budget: Shared admission ledger.
    ///   - resource: Initial class for the payload charge.
    ///   - initialize: Sole mutable borrow; its pointer must not escape the closure.
    public init(count: Int, capacity: Int? = nil, budget: DICOMAllocationBudget, resource: DICOMAllocationClass,
                initialize: (UnsafeMutableRawBufferPointer) throws -> Void) throws {
        let capacity = capacity ?? count
        guard count >= 0, capacity >= count else { throw DICOMAllocationError.invalidSize }
        _ = try Self.backingCapacity(for: capacity)
        self.count = count
        self.ownerBudget = budget
        self.controlLease = try budget.reserve(Self.controlCapacity, as: .metadata)
        self.storage = try AlignedPixelBuffer(byteCount: capacity, budget: budget, resource: resource)
        try initialize(UnsafeMutableRawBufferPointer(start: storage.baseAddress, count: capacity))
    }

    /// Borrow the logical bytes synchronously. The pointer must not escape or be mutated.
    /// - Parameter body: Called while the owner and its allocation charge remain alive.
    /// - Returns: The closure's result, which must not retain the borrowed pointer.
    public func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        try withExtendedLifetime(self) {
            try body(UnsafeRawBufferPointer(start: storage.baseAddress, count: count))
        }
    }

    /// An independently admitted copy. Unlike a Swift value alias, this has a new
    /// backing and remains charged while both original and copy exist.
    /// - Parameters:
    ///   - budget: Ledger admitting the new backing.
    ///   - resource: Initial class for the copy's payload charge.
    /// - Returns: An immutable copy of the logical bytes, without unused reconstruction capacity.
    public func copy(budget: DICOMAllocationBudget, resource: DICOMAllocationClass) throws -> DICOMByteBuffer {
        try DICOMByteBuffer(count: count, budget: budget, resource: resource) { destination in
            withUnsafeBytes { source in destination.copyMemory(from: source) }
        }
    }

    /// Move this backing's charge to retained output exactly once. Aliases still
    /// share the same backing, so destroying any one alias cannot release it.
    /// - Parameter resource: Destination allocation class.
    public func transfer(to resource: DICOMAllocationClass) throws {
        try storage.transferAllocation(to: resource)
    }
}
