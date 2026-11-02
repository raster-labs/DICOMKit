import XCTest
import Foundation
import DICOMCore
@testable import DICOMNetwork

#if canImport(Network)

/// Deterministic readiness-source tests exercise the same startup waiter used
/// by NWListener, including a source that never leaves `.waiting`. No public
/// timeout flags or network behavior overrides are added to the product.
final class M6PrintListenerStartupTests: XCTestCase {
    func testTimeoutCancelsAListenerThatNeverReportsReadiness() async {
        let effects = M6StartupEffects()
        let gate = PrintSCPListenerStartup { effects.cancel() }
        let started = Date()
        do {
            try await gate.wait(timeout: 0.02) { _ in effects.start() }
            XCTFail("A listener that never becomes ready must time out")
        } catch {
            guard case DICOMNetworkError.timeout = error else {
                return XCTFail("Expected timeout, got \(error)")
            }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        XCTAssertEqual(effects.counts.starts, 1)
        XCTAssertEqual(effects.counts.cancels, 1)
    }

    func testCancellationBeforeInstallationDoesNotStartListener() async {
        let effects = M6StartupEffects()
        let gate = PrintSCPListenerStartup { effects.cancel() }
        gate.cancel()
        do {
            try await gate.wait(timeout: 5) { _ in effects.start() }
            XCTFail("Cancelled startup must throw")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(effects.counts.starts, 0)
        XCTAssertEqual(effects.counts.cancels, 1)
    }

    func testTaskCancellationSettlesAnAlreadyWaitingListener() async {
        let effects = M6StartupEffects()
        let gate = PrintSCPListenerStartup { effects.cancel() }
        let started = expectation(description: "listener started")
        let finished = expectation(description: "cancelled wait finished")
        let task = Task {
            do {
                try await gate.wait(timeout: 5) { _ in
                    effects.start()
                    started.fulfill()
                }
                XCTFail("Cancelled startup must throw")
            } catch { XCTAssertTrue(error is CancellationError) }
            finished.fulfill()
        }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(effects.counts.cancels, 1)
    }

    func testFailureAndLateCallbacksCompleteExactlyOnce() async {
        let effects = M6StartupEffects()
        let gate = PrintSCPListenerStartup { effects.cancel() }
        do {
            try await gate.wait(timeout: 5) { completion in
                effects.start()
                completion(.failure(DICOMNetworkError.connectionFailed("synthetic bind failure")))
                completion(.success(()))
                completion(.failure(CancellationError()))
            }
            XCTFail("Bind failure must be preserved")
        } catch {
            guard case DICOMNetworkError.connectionFailed(let message) = error else {
                return XCTFail("Expected bind failure, got \(error)")
            }
            XCTAssertEqual(message, "synthetic bind failure")
        }
        XCTAssertEqual(effects.counts.cancels, 1)
    }

    func testReadyCancelsDeadlineAndIgnoresLateFailure() async throws {
        let effects = M6StartupEffects()
        let gate = PrintSCPListenerStartup { effects.cancel() }
        try await gate.wait(timeout: 0.01) { completion in
            effects.start()
            completion(.success(()))
            completion(.failure(CancellationError()))
        }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(effects.counts.starts, 1)
        XCTAssertEqual(effects.counts.cancels, 0)
    }

    func testAlreadyCancelledServerStartCanBeRetriedWithoutLeakingListener() async throws {
        let server = DICOMPrintServer(configuration: PrintSCPConfiguration(
            aeTitle: try AETitle("M6START"), port: 0), delegate: CollectingPrintHandler())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await server.start()
                XCTFail("Already-cancelled task must not bind")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        await task.value
        let cancelledRunning = await server.isRunning
        let cancelledPort = await server.boundPort
        XCTAssertFalse(cancelledRunning)
        XCTAssertEqual(cancelledPort, 0)
        try await server.start()
        let running = await server.isRunning
        let port = await server.boundPort
        XCTAssertTrue(running)
        XCTAssertGreaterThan(port, 0)
        await server.stop()
    }

    func testConcurrentStopsAndRestartSettleTheSameListener() async throws {
        let server = DICOMPrintServer(configuration: PrintSCPConfiguration(
            aeTitle: try AETitle("M6START"), port: 0), delegate: CollectingPrintHandler())
        for _ in 0..<3 {
            try await server.start()
            async let first: Void = server.stop()
            async let second: Void = server.stop()
            _ = await (first, second)
            let running = await server.isRunning
            let port = await server.boundPort
            let associations = await server.activeAssociationCount
            XCTAssertFalse(running)
            XCTAssertEqual(port, 0)
            XCTAssertEqual(associations, 0)
        }
    }
}

private final class M6StartupEffects: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var cancels = 0
    func start() { lock.lock(); starts += 1; lock.unlock() }
    func cancel() { lock.lock(); cancels += 1; lock.unlock() }
    var counts: (starts: Int, cancels: Int) {
        lock.lock(); defer { lock.unlock() }
        return (starts, cancels)
    }
}
#endif
