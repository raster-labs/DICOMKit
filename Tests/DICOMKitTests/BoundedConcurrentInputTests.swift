#if canImport(Darwin)
import Foundation
import Darwin
import Testing
@testable import DICOMCore
@testable import DICOMKit

@Suite("Concurrent bounded input lifetime")
struct BoundedConcurrentInputTests {
    @Test("Subscriber cancellation and consumer shutdown retain backing until each worker returns")
    func independentCancellationAndLateReturn() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dcm")
        try concurrentInputFixture().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let descriptor = Darwin.open(url.path, O_RDONLY)
        #expect(descriptor >= 0)
        guard descriptor >= 0 else { return }
        defer { Darwin.close(descriptor) }

        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt
        let options = try BoundedParsingOptions(.strict)
        let firstControl = ConcurrentInputControl()
        let secondControl = ConcurrentInputControl()
        let first = UnsafeMutablePointer<ConcurrentInputWorker>.allocate(capacity: 1)
        let second = UnsafeMutablePointer<ConcurrentInputWorker>.allocate(capacity: 1)
        first.initialize(to: ConcurrentInputWorker(budget: try budget.share(), descriptor: descriptor,
                                                  options: options, control: firstControl))
        second.initialize(to: ConcurrentInputWorker(budget: try budget.share(), descriptor: descriptor,
                                                   options: options, control: secondControl))
        var firstThread: pthread_t?
        var secondThread: pthread_t?
        defer {
            firstControl.releaseAll(); secondControl.releaseAll()
            if let firstThread { pthread_join(firstThread, nil) }
            if let secondThread { pthread_join(secondThread, nil) }
            first.deinitialize(count: 1); first.deallocate()
            second.deinitialize(count: 1); second.deallocate()
        }
        let firstStarted = pthread_create(&firstThread, nil, { concurrentInputMain($0) }, first)
        #expect(firstStarted == 0)
        guard firstStarted == 0 else { return }
        let secondStarted = pthread_create(&secondThread, nil, { concurrentInputMain($0) }, second)
        #expect(secondStarted == 0)
        guard secondStarted == 0 else { return }
        #expect(firstControl.waitFor(.ready))
        #expect(secondControl.waitFor(.ready))
        guard firstControl.snapshot.ready, secondControl.snapshot.ready,
              !firstControl.snapshot.failed, !secondControl.snapshot.failed else { return }

        let retained = budget.receipt
        let stackBytes = firstControl.snapshot.stackBytes + secondControl.snapshot.stackBytes
        #expect(retained.current.metadata > stackBytes)
        #expect(retained.current.encoded == 2 * DICOMByteBuffer.controlCapacity)
        // These are explicit source, parsed-index and frame aliases published while both workers wait.
        // Dropping the subscriber's aliases cannot release the workers' identical backing.
        first.pointee.dropConsumers()
        #expect(budget.receipt.current == retained.current)
        firstControl.cancelAndCheck()
        secondControl.allowCheck()
        #expect(firstControl.waitFor(.checked))
        #expect(secondControl.waitFor(.checked))
        #expect(firstControl.snapshot.cancelledObserved)
        #expect(!secondControl.snapshot.cancelledObserved)
        #expect(secondControl.snapshot.readSucceeded)
        #expect(!firstControl.snapshot.failed && !secondControl.snapshot.failed)
        #expect(budget.receipt.current == retained.current)

        // Model shutdown of the remaining consumer while synchronous workers are still late.
        second.pointee.dropConsumers()
        secondControl.cancel()
        #expect(!firstControl.snapshot.finished && !secondControl.snapshot.finished)
        #expect(budget.receipt.current == retained.current)
        #expect(budget.receipt.liveAllocations == retained.liveAllocations)

        firstControl.allowReturn()
        if let thread = firstThread { pthread_join(thread, nil); firstThread = nil }
        #expect(firstControl.snapshot.finished && !firstControl.snapshot.failed)
        #expect(!secondControl.snapshot.finished)
        let oneWorker = budget.receipt
        #expect(oneWorker.currentTotal < retained.currentTotal)
        #expect(oneWorker.current.encoded == DICOMByteBuffer.controlCapacity)
        #expect(oneWorker.current.metadata > secondControl.snapshot.stackBytes)

        secondControl.allowReturn()
        if let thread = secondThread { pthread_join(thread, nil); secondThread = nil }
        #expect(secondControl.snapshot.finished && !secondControl.snapshot.failed)
        #expect(budget.receipt.current == baseline.current)
        #expect(budget.receipt.currentTotal == baseline.currentTotal)
        #expect(budget.receipt.liveAllocations == baseline.liveAllocations)
    }
}

// Harness objects, synchronization, thread creation, fixture bytes and callback storage are
// caller-owned. This test checks library lifetime accounting, not harness/runtime allocations.
private final class ConcurrentInputControl: @unchecked Sendable {
    enum Phase: Equatable { case ready, checked }
    struct Snapshot {
        var ready = false
        var checked = false
        var finished = false
        var failed = false
        var cancelledObserved = false
        var readSucceeded = false
        var stackBytes = 0
    }
    private let condition = NSCondition()
    private var state = Snapshot()
    private var cancelled = false
    private var checkAllowed = false
    private var returnAllowed = false

    var snapshot: Snapshot {
        condition.lock(); defer { condition.unlock() }
        return state
    }
    var isCancelled: Bool {
        condition.lock(); defer { condition.unlock() }
        return cancelled
    }
    func waitFor(_ phase: Phase) -> Bool {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: 15)
        while !(phase == .ready ? state.ready : state.checked) && !state.finished {
            guard condition.wait(until: deadline) else { return false }
        }
        return phase == .ready ? state.ready : state.checked
    }
    func ready(stackBytes: Int) {
        condition.lock(); defer { condition.unlock() }
        state.ready = true; state.stackBytes = stackBytes; condition.broadcast()
    }
    func checked(cancelled: Bool, succeeded: Bool) {
        condition.lock(); defer { condition.unlock() }
        state.checked = true; state.cancelledObserved = cancelled; state.readSucceeded = succeeded
        condition.broadcast()
    }
    func finish(failed: Bool) {
        condition.lock(); defer { condition.unlock() }
        state.finished = true; state.failed = failed; condition.broadcast()
    }
    func waitForPermission(toReturn: Bool) -> Bool {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: 15)
        while !(toReturn ? returnAllowed : checkAllowed) {
            guard condition.wait(until: deadline) else { return false }
        }
        return true
    }
    func cancel() {
        condition.lock(); defer { condition.unlock() }; cancelled = true
    }
    func cancelAndCheck() {
        condition.lock(); defer { condition.unlock() }
        cancelled = true; checkAllowed = true; condition.broadcast()
    }
    func allowCheck() {
        condition.lock(); defer { condition.unlock() }; checkAllowed = true; condition.broadcast()
    }
    func allowReturn() {
        condition.lock(); defer { condition.unlock() }; returnAllowed = true; condition.broadcast()
    }
    func releaseAll() {
        condition.lock(); defer { condition.unlock() }
        checkAllowed = true; returnAllowed = true; condition.broadcast()
    }
}

private struct ConcurrentInputWorker: ~Copyable {
    let budget: DICOMAllocationBudget
    let descriptor: Int32
    let options: BoundedParsingOptions
    let control: ConcurrentInputControl
    var consumerSource: VerifiedFileByteSource?
    var consumerIndex: BoundedDICOMFile?
    var consumerFrame: DICOMByteBuffer?

    mutating func dropConsumers() {
        consumerFrame = nil; consumerIndex = nil; consumerSource = nil
    }
}

private enum ConcurrentInputFailure: Error { case missingPixel, wrongValue, permissionTimeout }

private func concurrentInputMain(_ raw: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    let context = raw.assumingMemoryBound(to: ConcurrentInputWorker.self)
    let control = context.pointee.control
    let cancellation = DICOMCancellation(check: { pointer in
        guard let pointer else { return false }
        return pointer.assumingMemoryBound(to: ConcurrentInputWorker.self).pointee.control.isCancelled
    }, context: raw)
    do {
        let execution = try DICOMExecutionReservation(budget: context.pointee.budget)
        let source = try VerifiedFileByteSource(descriptor: context.pointee.descriptor,
            budget: context.pointee.budget, execution: execution, cancellation: cancellation)
        let parsed = try DICOMFile.readBounded(from: source, options: context.pointee.options,
                                               execution: execution, cancellation: cancellation)
        let dataSet = try parsed.dataSet()
        guard let pixel = try dataSet.element(for: .pixelData) else { throw ConcurrentInputFailure.missingPixel }
        let frame = try pixel.readValueRange(0..<4, cancellation: cancellation)
        context.pointee.consumerSource = try source.share()
        context.pointee.consumerIndex = try parsed.share()
        context.pointee.consumerFrame = try frame.share()
        control.ready(stackBytes: execution.stackByteCount)
        guard control.waitForPermission(toReturn: false) else { throw ConcurrentInputFailure.permissionTimeout }
        var cancelled = false
        var readSucceeded = false
        do throws(DICOMManagedFailure) {
            try execution.validateManagedForTest(budget: context.pointee.budget)
            let again = try pixel.readValueRange(0..<4, cancellation: cancellation)
            readSucceeded = concurrentFrameMatches(again)
        } catch {
            guard error.code == .cancelled else { throw error }
            cancelled = true
        }
        control.checked(cancelled: cancelled, succeeded: readSucceeded)
        guard control.waitForPermission(toReturn: true) else { throw ConcurrentInputFailure.permissionTimeout }
        guard concurrentFrameMatches(frame) else { throw ConcurrentInputFailure.wrongValue }
        // Explicit final consumption prevents either the optimizer or a dropped consumer from
        // ending these owners before the actual late-return barrier.
        destroyConcurrentOwner(frame); destroyConcurrentOwner(pixel); destroyConcurrentOwner(dataSet)
        destroyConcurrentOwner(parsed); destroyConcurrentOwner(source); destroyConcurrentOwner(execution)
    } catch {
        control.finish(failed: true)
        return nil
    }
    control.finish(failed: false)
    return nil
}

private extension DICOMExecutionReservation {
    borrowing func validateManagedForTest(budget: borrowing DICOMAllocationBudget) throws(DICOMManagedFailure) {
        do throws(DICOMAllocationError) { try validate(budget: budget) }
        catch { throw DICOMManagedFailure(allocation: error) }
    }
}

private func destroyConcurrentOwner<T: ~Copyable>(_ owner: consuming T) {}

private func concurrentFrameMatches(_ frame: borrowing DICOMByteBuffer) -> Bool {
    frame.withUnsafeBytes { $0.count == 4 && $0[0] == 42 && $0[1] == 0 && $0[2] == 99 && $0[3] == 0 }
}

private func concurrentInputFixture() -> Data {
    func u16(_ value: UInt16) -> Data { Data([UInt8(truncatingIfNeeded: value), UInt8(value >> 8)]) }
    func u32(_ value: UInt32) -> Data {
        Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    func element(_ tag: DICOMCore.Tag, _ vr: String, _ value: Data) -> Data {
        var bytes = u16(tag.group) + u16(tag.element) + Data(vr.utf8)
        bytes += vr == "OW" ? u16(0) + u32(UInt32(value.count)) : u16(UInt16(value.count))
        return bytes + value
    }
    var uid = Data("1.2.840.10008.1.2.1".utf8)
    if uid.count % 2 != 0 { uid.append(0) }
    let meta = element(.transferSyntaxUID, "UI", uid)
    return Data(repeating: 0, count: 128) + Data("DICM".utf8)
        + element(.fileMetaInformationGroupLength, "UL", u32(UInt32(meta.count))) + meta
        + element(.rows, "US", u16(1)) + element(.columns, "US", u16(2))
        + element(.pixelData, "OW", u16(42) + u16(99))
}
#endif
