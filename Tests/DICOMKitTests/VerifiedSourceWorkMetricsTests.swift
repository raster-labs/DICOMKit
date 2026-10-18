#if canImport(Darwin)
import Foundation
import Darwin
import Testing
import DICOMCore
@testable import DICOMKit

@Suite("Verified source work metrics")
struct VerifiedSourceWorkMetricsTests {
    @Test("A new metrics value is a valid, sendable zero snapshot")
    func zeroSnapshot() {
        let metrics = sendableMetrics(VerifiedSourceWorkMetrics())
        expectCounts(metrics, reads: 0, updates: 0, finalizations: 0, copies: 0,
                     readBytes: 0, copiedBytes: 0)
        #expect(metrics.readNanoseconds == 0)
        #expect(metrics.hashNanoseconds == 0)
        #expect(metrics.copyNanoseconds == 0)
        #expect(metrics == VerifiedSourceWorkMetrics())
    }

    @Test("Descriptor capture counts blocks, EOF, hashes and digest copies",
          arguments: [0, 17, VerifiedFileByteSource.blockBytes + 13])
    func descriptorCapture(size: Int) throws {
        let fixture = try MetricsFixture(size: size)
        defer { withExtendedLifetime(fixture) {} }
        let budget = try DICOMAllocationBudget()
        let source = try VerifiedFileByteSource(descriptor: fixture.descriptor, budget: budget)
        let blocks = UInt64((size + VerifiedFileByteSource.blockBytes - 1) / VerifiedFileByteSource.blockBytes)
        expectCounts(source.workMetrics, reads: blocks + 1, updates: blocks * 2,
                     finalizations: blocks + 1, copies: blocks,
                     readBytes: UInt64(size), copiedBytes: blocks * 32)
        let before = source.workMetrics
        try source.validate()
        let empty = try source.read(0..<0)
        #expect(empty.count == 0)
        #expect(source.workMetrics == before)
    }

    @Test("Path capture includes both retained path copies")
    func pathCapture() throws {
        let fixture = try MetricsFixture(size: 17)
        defer { withExtendedLifetime(fixture) {} }
        let budget = try DICOMAllocationBudget()
        let source = try VerifiedFileByteSource(url: fixture.url, budget: budget)
        let pathBytes = UInt64(fixture.url.path.utf8.count + 1)
        expectCounts(source.workMetrics, reads: 2, updates: 2, finalizations: 2, copies: 3,
                     readBytes: 17, copiedBytes: 32 + 2 * pathBytes)
    }

    @Test("Capture counts every short read, EINTR retry and EOF probe")
    func shortReadsAndRetry() throws {
        let fixture = try MetricsFixture(size: 19)
        let state = MetricsReadState()
        state.maximumRead = 7
        state.interrupts = 1
        defer { withExtendedLifetime((fixture, state)) {} }
        let budget = try DICOMAllocationBudget()
        let source = try hookedSource(fixture, budget: budget, state: state)
        expectCounts(source.workMetrics, reads: 5, updates: 2, finalizations: 2, copies: 1,
                     readBytes: 19, copiedBytes: 32)
        #expect(state.readCalls == 5)
    }

    @Test("Aliases share completed work while earlier snapshots remain values")
    func aliasAccumulation() throws {
        let block = VerifiedFileByteSource.blockBytes
        let fixture = try MetricsFixture(size: block + 13)
        defer { withExtendedLifetime(fixture) {} }
        let budget = try DICOMAllocationBudget()
        let source = try VerifiedFileByteSource(descriptor: fixture.descriptor, budget: budget)
        let alias = try source.share()
        let initial = source.workMetrics
        let retained = budget.receipt.currentTotal
        do {
            let bytes = try alias.read((block - 2)..<(block + 3))
            #expect(bytes.withUnsafeBytes { Array($0) } == Array(repeating: UInt8(0x5a), count: 5))
        }
        let afterRead = source.workMetrics
        expectDelta(initial, afterRead, reads: 2, updates: 2, finalizations: 2, copies: 2,
                    readBytes: UInt64(block + 13), copiedBytes: 5)
        var destination = [UInt8](repeating: 0, count: 3)
        try destination.withUnsafeMutableBytes { try source.copy(1..<4, to: $0) }
        #expect(destination == [0x5a, 0x5a, 0x5a])
        expectDelta(afterRead, alias.workMetrics, reads: 1, updates: 1, finalizations: 1, copies: 1,
                    readBytes: UInt64(block), copiedBytes: 3)
        #expect(source.workMetrics == alias.workMetrics)
        expectCounts(initial, reads: 3, updates: 4, finalizations: 3, copies: 2,
                     readBytes: UInt64(block + 13), copiedBytes: 64)
        #expect(budget.receipt.currentTotal == retained)
        destroyMetricsOwner(alias)
        destroyMetricsOwner(source)
    }

    @Test("Failed later reads retain completed work without invalidating measurement",
          arguments: [MetricsReadFault.error, .eof, .corrupt])
    func failedLaterRead(fault: MetricsReadFault) throws {
        let block = VerifiedFileByteSource.blockBytes
        let fixture = try MetricsFixture(size: block + 7)
        let state = MetricsReadState()
        defer { withExtendedLifetime((fixture, state)) {} }
        let budget = try DICOMAllocationBudget()
        let source = try hookedSource(fixture, budget: budget, state: state)
        let alias = try source.share()
        let initial = source.workMetrics
        let retained = budget.receipt.currentTotal
        state.fault = fault
        state.faultOffset = block
        expectFailure(fault == .error ? .readFailed : .sourceChanged) {
            _ = try alias.read(0..<(block + 7))
        }
        let completed = source.workMetrics
        let hashed: UInt64 = fault == .corrupt ? 2 : 1
        expectDelta(initial, completed, reads: 2, updates: hashed, finalizations: hashed, copies: 1,
                    readBytes: UInt64(fault == .corrupt ? block + 7 : block), copiedBytes: UInt64(block))
        #expect(alias.workMetrics == completed)
        #expect(budget.receipt.currentTotal == retained)
        expectFailure(.sourceChanged) { try source.validate() }
        #expect(source.workMetrics == completed)
    }

    @Test("A partial block failure counts bytes read without hashing or copying them")
    func failedPartialBlock() throws {
        let fixture = try MetricsFixture(size: 19)
        let state = MetricsReadState()
        defer { withExtendedLifetime((fixture, state)) {} }
        let budget = try DICOMAllocationBudget()
        let source = try hookedSource(fixture, budget: budget, state: state)
        let initial = source.workMetrics
        state.maximumRead = 7
        state.fault = .error
        state.faultOffset = 7
        expectFailure(.readFailed) { _ = try source.read(0..<19) }
        expectDelta(initial, source.workMetrics, reads: 2, updates: 0, finalizations: 0, copies: 0,
                    readBytes: 7, copiedBytes: 0)
    }

    @Test("Cancellation publishes completed work, releases output and permits another read")
    func cancelledLaterRead() throws {
        let block = VerifiedFileByteSource.blockBytes
        let fixture = try MetricsFixture(size: block + 7)
        let state = MetricsReadState()
        defer { withExtendedLifetime((fixture, state)) {} }
        let budget = try DICOMAllocationBudget()
        let source = try hookedSource(fixture, budget: budget, state: state)
        let initial = source.workMetrics
        let retained = budget.receipt.currentTotal
        state.cancelStage = 2
        state.cancelBlock = 1
        expectFailure(.cancelled) {
            _ = try source.read(0..<(block + 7), cancellation: state.cancellation)
        }
        let cancelled = source.workMetrics
        expectDelta(initial, cancelled, reads: 2, updates: 2, finalizations: 2, copies: 1,
                    readBytes: UInt64(block + 7), copiedBytes: UInt64(block))
        #expect(budget.receipt.currentTotal == retained)
        expectFailure(.cancelled) { _ = try source.read(0..<1, cancellation: state.cancellation) }
        expectFailure(.invalidRange) { _ = try source.read(-1..<0) }
        #expect(source.workMetrics == cancelled)
        state.cancelled = false
        state.cancelStage = -1
        do {
            let bytes = try source.read(0..<1)
            #expect(bytes.withUnsafeBytes { $0[0] } == 0x5a)
        }
        expectDelta(cancelled, source.workMetrics, reads: 1, updates: 1, finalizations: 1, copies: 1,
                    readBytes: UInt64(block), copiedBytes: 1)
        #expect(budget.receipt.currentTotal == retained)
    }

    @Test("Rejected or cancelled capture returns only failure and drains its budget",
          arguments: [MetricsCaptureFailure.size, .preCancelled, .afterBlock, .eofRetry, .readError])
    func captureCleanup(failure: MetricsCaptureFailure) throws {
        let fixture = try MetricsFixture(size: 19)
        let state = MetricsReadState()
        defer { withExtendedLifetime((fixture, state)) {} }
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt
        switch failure {
        case .size: break
        case .preCancelled: state.cancelled = true
        case .afterBlock: state.cancelStage = 0; state.cancelBlock = 0
        case .eofRetry: state.cancelAtOffset = 19
        case .readError: state.fault = .error; state.faultOffset = 0
        }
        let result = VerifiedFileByteSource.capture(path: UnsafeBufferPointer(start: nil, count: 0),
            descriptor: fixture.descriptor, budget: budget, maximumBytes: failure == .size ? 18 : 19,
            cancellation: state.cancellation, hooks: state.hooks)
        switch consume result {
        case .success(let unexpected):
            destroyMetricsOwner(unexpected)
            Issue.record("Failed capture must not expose a source or a metrics snapshot")
        case .failure(let error):
            let expected: DICOMManagedFailure.Code = failure == .size ? .sizeLimit
                : failure == .readError ? .readFailed : .cancelled
            #expect(error.code == expected)
        }
        #expect(budget.receipt.current == baseline.current)
        #expect(budget.receipt.currentTotal == baseline.currentTotal)
        #expect(budget.receipt.liveAllocations == baseline.liveAllocations)
    }

    @Test("The last source alias owns storage while detached metrics retain no charge")
    func snapshotAndAliasLifetime() throws {
        let fixture = try MetricsFixture(size: 19)
        defer { withExtendedLifetime(fixture) {} }
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt
        let alias: VerifiedFileByteSource
        let snapshot: VerifiedSourceWorkMetrics
        do {
            let source = try VerifiedFileByteSource(descriptor: fixture.descriptor, budget: budget)
            alias = try source.share()
            snapshot = source.workMetrics
        }
        #expect(budget.receipt.currentTotal > baseline.currentTotal)
        #expect(alias.workMetrics == snapshot)
        do { let bytes = try alias.read(0..<1); #expect(bytes.count == 1) }
        destroyMetricsOwner(alias)
        #expect(budget.receipt.current == baseline.current)
        #expect(budget.receipt.liveAllocations == baseline.liveAllocations)
        expectCounts(snapshot, reads: 2, updates: 2, finalizations: 2, copies: 1,
                     readBytes: 19, copiedBytes: 32)
    }

    @Test("Concurrent aliases merge every completed delta without lost updates")
    func concurrentAliases() throws {
        let fixture = try MetricsFixture(size: 31)
        defer { withExtendedLifetime(fixture) {} }
        let budget = try DICOMAllocationBudget()
        let source = try VerifiedFileByteSource(descriptor: fixture.descriptor, budget: budget)
        let initial = source.workMetrics
        let firstAlias = try source.share(), secondAlias = try source.share()
        let gate = MetricsStartGate()
        let first = UnsafeMutablePointer<MetricsWorker>.allocate(capacity: 1)
        let second = UnsafeMutablePointer<MetricsWorker>.allocate(capacity: 1)
        first.initialize(to: MetricsWorker(source: firstAlias, gate: gate))
        second.initialize(to: MetricsWorker(source: secondAlias, gate: gate))
        var firstThread: pthread_t?, secondThread: pthread_t?
        defer {
            gate.release()
            if let firstThread { pthread_join(firstThread, nil) }
            if let secondThread { pthread_join(secondThread, nil) }
            first.deinitialize(count: 1); first.deallocate()
            second.deinitialize(count: 1); second.deallocate()
        }
        let firstStatus = pthread_create(&firstThread, nil, { metricsWorkerMain($0) }, first)
        #expect(firstStatus == 0)
        guard firstStatus == 0 else { return }
        let secondStatus = pthread_create(&secondThread, nil, { metricsWorkerMain($0) }, second)
        #expect(secondStatus == 0)
        guard secondStatus == 0 else { return }
        #expect(gate.waitForBoth())
        gate.release()
        if let thread = firstThread { pthread_join(thread, nil); firstThread = nil }
        if let thread = secondThread { pthread_join(thread, nil); secondThread = nil }
        #expect(first.pointee.succeeded && second.pointee.succeeded)
        expectDelta(initial, source.workMetrics, reads: 32, updates: 32, finalizations: 32, copies: 32,
                    readBytes: 32 * 31, copiedBytes: 32)
        #expect(first.pointee.source.workMetrics == source.workMetrics)
        #expect(second.pointee.source.workMetrics == source.workMetrics)
    }

    @Test("Missing and backward clock values invalidate measurement permanently", arguments: [0, 1, 2])
    func invalidClock(kind: Int) {
        var metrics = VerifiedSourceWorkMetrics()
        metrics.recordRead(start: kind == 0 ? nil : 7, end: kind == 1 ? nil : 6, bytes: 2)
        #expect(!metrics.isValid)
        #expect(metrics.readNanoseconds == 0)
        metrics.recordRead(start: 10, end: 14, bytes: 3)
        metrics.recordCopy(start: 20, end: 20, bytes: 1)
        #expect(!metrics.isValid)
        #expect(metrics.readCalls == 2 && metrics.bytesRead == 5 && metrics.readNanoseconds == 4)
        #expect(metrics.copyCalls == 1 && metrics.bytesCopied == 1 && metrics.copyNanoseconds == 0)
        var merged = VerifiedSourceWorkMetrics()
        merged.merge(metrics)
        #expect(merged == metrics)
        var copy = VerifiedSourceWorkMetrics()
        copy.recordCopy(start: kind == 0 ? nil : 7, end: kind == 1 ? nil : 6, bytes: 2)
        #expect(!copy.isValid)
        #expect(copy.copyNanoseconds == 0 && copy.copyCalls == 1 && copy.bytesCopied == 2)
    }

    @Test("Duration overflow saturates without losing later counters")
    func durationOverflow() {
        var metrics = VerifiedSourceWorkMetrics()
        metrics.recordRead(start: 0, end: UInt64.max, bytes: 1)
        metrics.recordCopy(start: 0, end: UInt64.max, bytes: 1)
        #expect(metrics.isValid)
        metrics.recordRead(start: 0, end: 1, bytes: -1)
        metrics.recordCopy(start: 0, end: 1, bytes: 2)
        #expect(!metrics.isValid)
        #expect(metrics.readNanoseconds == UInt64.max && metrics.copyNanoseconds == UInt64.max)
        #expect(metrics.readCalls == 2 && metrics.bytesRead == 1)
        #expect(metrics.copyCalls == 2 && metrics.bytesCopied == 3)
    }

    @Test("Merging overflowing counters saturates every field and stays invalid")
    func counterOverflow() {
        var metrics = VerifiedSourceWorkMetrics()
        metrics.recordRead(start: 0, end: 0, bytes: 1)
        metrics.recordCopy(start: 0, end: 0, bytes: 1)
        var hash = BoundedSHA256()
        metrics.update(&hash, UnsafeRawBufferPointer(start: nil, count: 0))
        _ = metrics.finalize(&hash)
        for _ in 0..<64 { let increment = metrics; metrics.merge(increment) }
        #expect(!metrics.isValid)
        #expect(metrics.readCalls == UInt64.max && metrics.hashUpdates == UInt64.max)
        #expect(metrics.hashFinalizations == UInt64.max && metrics.copyCalls == UInt64.max)
        #expect(metrics.bytesRead == UInt64.max && metrics.bytesCopied == UInt64.max)
        let saturated = metrics
        metrics.merge(VerifiedSourceWorkMetrics())
        #expect(metrics == saturated)
        metrics.recordRead(start: 0, end: 0, bytes: 1)
        #expect(metrics == saturated)
    }

    @Test("Sampling the clock preserves the caller's errno")
    func timestampPreservesErrno() {
        let saved = errno
        defer { errno = saved }
        errno = EINTR
        let timestamp = VerifiedSourceWorkMetrics.timestamp()
        let observed = errno
        #expect(timestamp != nil)
        #expect(observed == EINTR)
    }

    @Test("Header and digest capacity is fully admitted before source reads")
    func headerAdmissionBoundary() throws {
        let fixture = try MetricsFixture(size: 0)
        defer { withExtendedLifetime(fixture) {} }
        let page = DICOMAllocationBudget.controlCapacity
        let admission = MetricsAdmissionState()
        defer { withExtendedLifetime(admission) {} }
        let budget = try DICOMAllocationBudget.make(externalAdmission: admission.callbacks).get()
        let baseline = budget.receipt.currentTotal
        do {
            let source = try VerifiedFileByteSource(descriptor: fixture.descriptor, budget: budget)
            // Empty paths still own a temporary minimum-capacity payload.
            #expect(admission.metadataPayloads == [page, page])
            #expect(admission.total == budget.receipt.currentTotal)
            #expect(admission.total == baseline + 2 * page)
            #expect(source.workMetrics.readCalls == 1)
        }
        #expect(admission.total == baseline)
        // Exactly one page of digests plus the nonempty source header needs two
        // payload pages. Refuse that pair before capture can hash the sparse file.
        let file = try FileHandle(forWritingTo: fixture.url)
        try file.truncate(atOffset: UInt64(page / 32 * VerifiedFileByteSource.blockBytes))
        try file.close()
        admission.refuseMetadataAbove = page
        let before = budget.receipt
        let readState = MetricsReadState()
        defer { withExtendedLifetime(readState) {} }
        do {
            _ = try hookedSource(fixture, budget: budget, state: readState)
            Issue.record("Expected two-page source metadata refusal")
        } catch let error as DICOMManagedFailure {
            #expect(error.allocation == .externalAdmissionRefused(79))
        }
        #expect(admission.metadataPayloads == [page, page, page, 2 * page])
        #expect(readState.readCalls == 0)
        #expect(admission.total == baseline)
        #expect(budget.receipt.currentTotal == before.currentTotal)
        #expect(budget.receipt.liveAllocations == before.liveAllocations)
        destroyMetricsOwner(budget)
        #expect(admission.total == 0 && admission.tokens.isEmpty && admission.contextOwners == 0)
    }
}

private func sendableMetrics<T: Sendable>(_ value: T) -> T { value }
private func destroyMetricsOwner<T: ~Copyable>(_ value: consuming T) {}

private func expectCounts(_ value: VerifiedSourceWorkMetrics, reads: UInt64, updates: UInt64,
                         finalizations: UInt64, copies: UInt64, readBytes: UInt64, copiedBytes: UInt64) {
    #expect(value.isValid)
    #expect(value.readCalls == reads)
    #expect(value.hashUpdates == updates)
    #expect(value.hashFinalizations == finalizations)
    #expect(value.copyCalls == copies)
    #expect(value.bytesRead == readBytes)
    #expect(value.bytesCopied == copiedBytes)
}

private func expectDelta(_ before: VerifiedSourceWorkMetrics, _ after: VerifiedSourceWorkMetrics,
                         reads: UInt64, updates: UInt64, finalizations: UInt64,
                         copies: UInt64, readBytes: UInt64, copiedBytes: UInt64) {
    expectCounts(after, reads: before.readCalls + reads, updates: before.hashUpdates + updates,
                 finalizations: before.hashFinalizations + finalizations, copies: before.copyCalls + copies,
                 readBytes: before.bytesRead + readBytes, copiedBytes: before.bytesCopied + copiedBytes)
    #expect(after.readNanoseconds >= before.readNanoseconds)
    #expect(after.hashNanoseconds >= before.hashNanoseconds)
    #expect(after.copyNanoseconds >= before.copyNanoseconds)
}

private func expectFailure(_ code: DICOMManagedFailure.Code, _ body: () throws -> Void) {
    do { try body(); Issue.record("Expected source failure: \(code)") }
    catch let error as DICOMManagedFailure { #expect(error.code == code) }
    catch { Issue.record("Unexpected error: \(error)") }
}

private final class MetricsFixture {
    let url: URL
    let descriptor: Int32
    init(size: Int) throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".metrics")
        try Data(repeating: 0x5a, count: size).write(to: location)
        let opened = Darwin.open(location.path, O_RDONLY)
        guard opened >= 0 else {
            try? FileManager.default.removeItem(at: location)
            throw DICOMManagedFailure(.readFailed)
        }
        url = location
        descriptor = opened
    }
    deinit { _ = Darwin.close(descriptor); try? FileManager.default.removeItem(at: url) }
}

enum MetricsReadFault: Sendable, Equatable { case none, error, eof, corrupt }
enum MetricsCaptureFailure: Sendable, Equatable { case size, preCancelled, afterBlock, eofRetry, readError }

// Caller-owned, synchronous fault context. Concurrent alias tests use no hooks.
private final class MetricsReadState {
    var maximumRead = Int.max, interrupts = 0, readCalls = 0
    var fault = MetricsReadFault.none, faultOffset = -1
    var cancelled = false, cancelStage = -1, cancelBlock = -1, cancelAtOffset = -1
    var cancellation: DICOMCancellation {
        DICOMCancellation(check: { raw in
            guard let raw else { return false }
            return Unmanaged<MetricsReadState>.fromOpaque(raw).takeUnretainedValue().cancelled
        }, context: Unmanaged.passUnretained(self).toOpaque())
    }
    var hooks: VerifiedFileByteSource.Hooks {
        VerifiedFileByteSource.Hooks(context: Unmanaged.passUnretained(self).toOpaque(),
            stage: { raw, stage, block in
                guard let raw else { return 0 }
                let state = Unmanaged<MetricsReadState>.fromOpaque(raw).takeUnretainedValue()
                if state.cancelStage == stage && state.cancelBlock == block { state.cancelled = true }
                return 0
            }, read: { raw, fd, bytes, count, offset in
                guard let raw else { errno = EIO; return -1 }
                let state = Unmanaged<MetricsReadState>.fromOpaque(raw).takeUnretainedValue()
                state.readCalls += 1
                if state.cancelAtOffset == Int(offset) { state.cancelled = true; errno = EINTR; return -1 }
                if state.interrupts > 0 { state.interrupts -= 1; errno = EINTR; return -1 }
                if state.faultOffset == Int(offset) {
                    if state.fault == .error { errno = EIO; return -1 }
                    if state.fault == .eof { return 0 }
                }
                let amount = Darwin.pread(fd, bytes, min(count, state.maximumRead), offset)
                if state.fault == .corrupt && state.faultOffset == Int(offset) && amount > 0 {
                    bytes?.assumingMemoryBound(to: UInt8.self).pointee ^= 1
                }
                return amount
            })
    }
}

private func hookedSource(_ fixture: MetricsFixture, budget: borrowing DICOMAllocationBudget,
                          state: MetricsReadState) throws(DICOMManagedFailure) -> VerifiedFileByteSource {
    try VerifiedFileByteSource(path: UnsafeBufferPointer(start: nil, count: 0), descriptor: fixture.descriptor,
        budget: budget, maximumBytes: VerifiedFileByteSource.maximumSourceBytes,
        cancellation: state.cancellation, hooks: state.hooks)
}

private final class MetricsStartGate {
    private let condition = NSCondition()
    private var ready = 0, released = false
    func arrive() -> Bool {
        condition.lock(); defer { condition.unlock() }
        ready += 1; condition.broadcast()
        let deadline = Date(timeIntervalSinceNow: 15)
        while !released { if !condition.wait(until: deadline) { return false } }
        return true
    }
    func waitForBoth() -> Bool {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: 15)
        while ready < 2 { if !condition.wait(until: deadline) { return false } }
        return true
    }
    func release() {
        condition.lock(); defer { condition.unlock() }
        released = true; condition.broadcast()
    }
}

private struct MetricsWorker: ~Copyable {
    let source: VerifiedFileByteSource
    let gate: MetricsStartGate
    var succeeded = false
}

private func metricsWorkerMain(_ raw: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    let context = raw.assumingMemoryBound(to: MetricsWorker.self)
    guard context.pointee.gate.arrive() else { return nil }
    do {
        var previous = context.pointee.source.workMetrics
        for _ in 0..<16 {
            let bytes = try context.pointee.source.read(0..<1)
            guard bytes.withUnsafeBytes({ $0.count == 1 && $0[0] == 0x5a }) else { return nil }
            let current = context.pointee.source.workMetrics
            guard current.isValid, current.readCalls >= previous.readCalls,
                  current.hashUpdates >= previous.hashUpdates,
                  current.hashFinalizations >= previous.hashFinalizations,
                  current.copyCalls >= previous.copyCalls,
                  current.bytesRead >= previous.bytesRead, current.bytesCopied >= previous.bytesCopied,
                  current.readNanoseconds >= previous.readNanoseconds,
                  current.hashNanoseconds >= previous.hashNanoseconds,
                  current.copyNanoseconds >= previous.copyNanoseconds else { return nil }
            previous = current
        }
        context.pointee.succeeded = true
    } catch { return nil }
    return nil
}

// Test-only accounting oracle. Calls in this test are synchronous; the threaded
// tests exercise the source's mutex with its production local ledger instead.
private final class MetricsAdmissionState {
    var total = 0, contextOwners = 0, refuseMetadataAbove = Int.max
    var next: UInt64 = 1
    var tokens: [UInt64: Int] = [:]
    var metadataPayloads: [Int] = []
    var callbacks: DICOMExternalAllocationCallbacks {
        DICOMExternalAllocationCallbacks(context: Unmanaged.passUnretained(self).toOpaque(),
            retainContext: { raw in
                guard let raw else { return 80 }
                Unmanaged<MetricsAdmissionState>.fromOpaque(raw).takeUnretainedValue().contextOwners += 1
                return 0
            }, admit: { raw, resource, payload, control, token in
                guard let raw, let token else { return 80 }
                let state = Unmanaged<MetricsAdmissionState>.fromOpaque(raw).takeUnretainedValue()
                token.pointee = 0
                if resource == Int32(DICOMAllocationClass.metadata.rawValue), payload > 0 {
                    state.metadataPayloads.append(payload)
                    if payload > state.refuseMetadataAbove { return 79 }
                }
                let id = state.next; state.next += 1
                state.tokens[id] = payload + control; state.total += payload + control
                token.pointee = id
                return 0
            }, release: { raw, token in
                guard let raw else { return }
                let state = Unmanaged<MetricsAdmissionState>.fromOpaque(raw).takeUnretainedValue()
                if let bytes = state.tokens.removeValue(forKey: token) { state.total -= bytes }
                else { Issue.record("Unknown admission token") }
            }, transfer: { _, _, _ in 80 }, releaseContext: { raw in
                guard let raw else { return }
                Unmanaged<MetricsAdmissionState>.fromOpaque(raw).takeUnretainedValue().contextOwners -= 1
            })
    }
}
#endif
