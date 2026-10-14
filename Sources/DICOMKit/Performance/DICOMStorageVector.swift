// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (controlled container).
import DICOMCore

/// Move-only growable slots; growth admits complete new storage while old storage remains live.
/// Nontrivial elements must separately own their payload capacity; this owner accounts for slots.
/// Kept beside its sole production consumer so optimized parsing specializes concrete records
/// without acquiring cross-module generic container metadata.
struct DICOMStorageVector<Element>: ~Copyable {
    private let budget: DICOMAllocationBudget
    private var storage: DICOMByteBuffer?
    private(set) var count = 0
    private(set) var capacity = 0
    private var pointer: UnsafeMutablePointer<Element>? {
        switch storage {
        case .some(let owner): return owner.unsafeMutableBytes.baseAddress?.assumingMemoryBound(to: Element.self)
        case .none: return nil
        }
    }

    init(budget: borrowing DICOMAllocationBudget) throws(DICOMAllocationError) {
        self.budget = try budget.shareOutcome().get()
    }

    private init(retainedBudget: consuming DICOMAllocationBudget) { budget = retainedBudget }

    static func make(budget: borrowing DICOMAllocationBudget) -> DICOMAllocationOutcome<Self> {
        switch budget.shareOutcome() {
        case .success(let owner): return .success(Self(retainedBudget: owner))
        case .failure(let error): return .failure(error)
        }
    }

    subscript(index: Int) -> Element {
        get {
            precondition(index >= 0 && index < count)
            guard let pointer else { preconditionFailure("Missing initialized storage") }
            return pointer[index]
        }
        set {
            precondition(index >= 0 && index < count)
            guard let pointer else { preconditionFailure("Missing initialized storage") }
            pointer[index] = newValue
        }
    }

    mutating func append(_ value: Element) throws(DICOMAllocationError) {
        try appendOutcome(value).get()
    }

    mutating func appendOutcome(_ value: Element) -> DICOMAllocationOutcome<Void> {
        if count == capacity {
            switch growOutcome() {
            case .success: break
            case .failure(let error): return .failure(error)
            }
        }
        pointer?.advanced(by: count).initialize(to: value)
        count += 1
        return .success(())
    }

    private mutating func growOutcome() -> DICOMAllocationOutcome<Void> {
        let stride = MemoryLayout<Element>.stride
        guard stride > 0, MemoryLayout<Element>.alignment <= DICOMByteBuffer.controlCapacity else {
            return .failure(.invalidSize)
        }
        let initial = max(1, DICOMByteBuffer.controlCapacity / stride)
        let (doubled, overflow) = max(initial, capacity).multipliedReportingOverflow(by: capacity == 0 ? 1 : 2)
        let (bytes, byteOverflow) = doubled.multipliedReportingOverflow(by: stride)
        guard !overflow, !byteOverflow else { return .failure(.invalidSize) }
        switch DICOMByteBuffer.allocate(count: bytes, budget: budget, resource: .metadata) {
        case .success(let newStorage):
            let newPointer = newStorage.unsafeMutableBytes.bindMemory(to: Element.self)
            if let pointer, count > 0, let destination = newPointer.baseAddress {
                destination.moveInitialize(from: pointer, count: count)
            }
            storage = consume newStorage
            capacity = doubled
            return .success(())
        case .failure(let error): return .failure(error)
        }
    }

    mutating func releaseStorage() {
        pointer?.deinitialize(count: count)
        count = 0; capacity = 0; storage = nil
    }

    borrowing func withUnsafeBufferPointer<Result: ~Copyable, Failure: Error>(
        _ body: (UnsafeBufferPointer<Element>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try body(UnsafeBufferPointer(start: pointer, count: count))
    }

    borrowing func withBorrowedBuffer<Result: ~Copyable>(
        _ body: (UnsafeBufferPointer<Element>) -> Result) -> Result {
        body(UnsafeBufferPointer(start: pointer, count: count))
    }

    deinit { pointer?.deinitialize(count: count) }
}
