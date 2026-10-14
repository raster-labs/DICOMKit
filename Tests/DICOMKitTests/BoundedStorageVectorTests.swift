import Testing
@testable import DICOMCore
@testable import DICOMKit

@Suite("Bounded parser storage vector")
struct BoundedStorageVectorTests {
    private var page: Int { DICOMByteBuffer.controlCapacity }

    @Test("Growth overlaps real old and new mappings; failed growth preserves elements")
    func vectorGrowth() throws {
        let budget = try DICOMAllocationBudget()
        var vector = try DICOMStorageVector<UInt64>(budget: budget)
        let initial = page / MemoryLayout<UInt64>.stride
        for index in 0...initial { try vector.append(UInt64(index)) }
        #expect(vector.count == initial + 1)
        #expect(vector[initial] == UInt64(initial))
        #expect(budget.receipt.current.metadata == 4 * page)
        #expect(budget.receipt.peak.metadata == 6 * page)
        vector.releaseStorage()
        #expect(budget.receipt.currentTotal == page)

        let failed = try DICOMAllocationBudget(allocationFailureAfter: 2)
        var retained = try DICOMStorageVector<UInt64>(budget: failed)
        for index in 0..<initial { try retained.append(UInt64(index)) }
        #expect(throws: DICOMAllocationError.allocationFailed) { try retained.append(99) }
        #expect(retained.count == initial)
        #expect(retained[initial - 1] == UInt64(initial - 1))
        #expect(failed.receipt.currentTotal == 3 * page)
    }

}
