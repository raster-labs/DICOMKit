// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (controlled container).
import Foundation

/// Internal growable storage with explicit backing capacity. Growth admits the new
/// allocation while the old one is still charged. Nontrivial element payloads must
/// have their own owner/charge; this container accounts for its slots only.
package final class DICOMStorageVector<Element> {
    private let budget: DICOMAllocationBudget
    private let controlLease: DICOMAllocationLease
    private var storage: AlignedPixelBuffer?
    package private(set) var count = 0
    package private(set) var capacity = 0
    private var pointer: UnsafeMutablePointer<Element>? {
        storage?.baseAddress.assumingMemoryBound(to: Element.self)
    }
    package init(budget: DICOMAllocationBudget) throws {
        self.budget = budget
        self.controlLease = try budget.reserve(DICOMByteBuffer.controlCapacity, as: .metadata)
    }
    package subscript(index: Int) -> Element {
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
    package func append(_ value: Element) throws {
        if count == capacity { try grow() }
        pointer?.advanced(by: count).initialize(to: value)
        count += 1
    }
    private func grow() throws {
        let stride = MemoryLayout<Element>.stride
        let initial = max(1, AlignedPixelBuffer.pageSize / stride)
        let (doubled, overflow) = max(initial, capacity).multipliedReportingOverflow(by: capacity == 0 ? 1 : 2)
        let (bytes, byteOverflow) = doubled.multipliedReportingOverflow(by: stride)
        guard !overflow, !byteOverflow else { throw DICOMAllocationError.invalidSize }
        let newStorage = try AlignedPixelBuffer(byteCount: bytes, budget: budget, resource: .metadata)
        let newPointer = newStorage.baseAddress.bindMemory(to: Element.self, capacity: doubled)
        if let pointer, count > 0 { newPointer.moveInitialize(from: pointer, count: count) }
        storage = newStorage
        capacity = doubled
    }
    package func releaseStorage() {
        pointer?.deinitialize(count: count)
        count = 0; capacity = 0; storage = nil
    }
    deinit { pointer?.deinitialize(count: count) }
}
