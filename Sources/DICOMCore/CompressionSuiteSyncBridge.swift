import Foundation
import Dispatch
import Synchronization

private final class CompressionSuiteTaskExecutor: TaskExecutor {
    static let shared = CompressionSuiteTaskExecutor()

    private let queue = DispatchQueue(
        label: "com.dicomkit.compression-suite.task-executor",
        qos: .userInitiated,
        attributes: .concurrent
    )

    func enqueue(_ job: consuming ExecutorJob) {
        let unownedJob = UnownedJob(job)
        let unownedExecutor = asUnownedTaskExecutor()
        queue.async {
            unownedJob.runSynchronously(on: unownedExecutor)
        }
    }
}

/// Shared synchronous bridge for `SwiftJLS`, `SwiftJLI`, and `SwiftJXL` `@concurrent` operations.
///
/// Executes async codec operations on a dedicated GCD-backed `TaskExecutor` (avoiding Swift
/// cooperative thread-pool starvation when called inside `TaskGroup`s), propagating cooperative
/// cancellation, `DICOMCancellation` callbacks, and finite wall-clock deadlines with bounded join.
enum CompressionSuiteSyncBridge {
    static func run<T: Sendable>(
        deadlineSeconds: Double = 30.0,
        joinGraceSeconds: Double = 1.0,
        codecName: String,
        operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        try Task.checkCancellation()

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = Mutex<Result<T, any Error>?>(nil)

        let worker = Task.detached(
            executorPreference: CompressionSuiteTaskExecutor.shared,
            priority: .userInitiated
        ) {
            let outcome: Result<T, any Error>
            do {
                outcome = .success(try await operation())
            } catch {
                outcome = .failure(error)
            }
            resultBox.withLock { $0 = outcome }
            semaphore.signal()
        }

        let clock = ContinuousClock()
        let totalBudgetSeconds = max(0.05, deadlineSeconds + min(joinGraceSeconds, 2.0))
        let hardDeadline = clock.now.advanced(
            by: .milliseconds(Int((totalBudgetSeconds * 1_000.0).rounded(.up)))
        )
        let joinTimeoutMs = max(50, Int((joinGraceSeconds * 1_000.0).rounded(.up)))

        while semaphore.wait(timeout: .now() + .milliseconds(5)) == .timedOut {
            if Task.isCancelled {
                worker.cancel()
                _ = semaphore.wait(timeout: .now() + .milliseconds(joinTimeoutMs))
                throw CancellationError()
            }
            if clock.now >= hardDeadline {
                worker.cancel()
                _ = semaphore.wait(timeout: .now() + .milliseconds(joinTimeoutMs))
                if let settled = resultBox.withLock({ $0 }) {
                    return try settled.get()
                }
                throw DICOMError.limitExceeded(
                    "\(codecName) operation exceeded deadline (\(deadlineSeconds)s)"
                )
            }
        }

        try Task.checkCancellation()
        guard let settled = resultBox.withLock({ $0 }) else {
            throw DICOMError.parsingFailed("\(codecName) synchronous bridge completed without a result")
        }
        return try settled.get()
    }

    static func runManaged<T: Sendable>(
        deadlineSeconds: Double = 30.0,
        joinGraceSeconds: Double = 1.0,
        domain: UInt16,
        cancellation: DICOMCancellation,
        operation: @escaping @Sendable () async throws -> T
    ) -> DICOMManagedOutcome<T> {
        if let failure = cancellation.failure {
            return .failure(failure)
        }
        if Task.isCancelled {
            return .failure(DICOMManagedFailure(.cancelled))
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = Mutex<Result<T, any Error>?>(nil)

        let worker = Task.detached(
            executorPreference: CompressionSuiteTaskExecutor.shared,
            priority: .userInitiated
        ) {
            let outcome: Result<T, any Error>
            do {
                outcome = .success(try await operation())
            } catch {
                outcome = .failure(error)
            }
            resultBox.withLock { $0 = outcome }
            semaphore.signal()
        }

        let clock = ContinuousClock()
        let totalBudgetSeconds = max(0.05, deadlineSeconds + min(joinGraceSeconds, 2.0))
        let hardDeadline = clock.now.advanced(
            by: .milliseconds(Int((totalBudgetSeconds * 1_000.0).rounded(.up)))
        )
        let joinTimeoutMs = max(50, Int((joinGraceSeconds * 1_000.0).rounded(.up)))

        while semaphore.wait(timeout: .now() + .milliseconds(5)) == .timedOut {
            if let failure = cancellation.failure {
                worker.cancel()
                _ = semaphore.wait(timeout: .now() + .milliseconds(joinTimeoutMs))
                return .failure(failure)
            }
            if Task.isCancelled {
                worker.cancel()
                _ = semaphore.wait(timeout: .now() + .milliseconds(joinTimeoutMs))
                return .failure(DICOMManagedFailure(.cancelled))
            }
            if clock.now >= hardDeadline {
                worker.cancel()
                _ = semaphore.wait(timeout: .now() + .milliseconds(joinTimeoutMs))
                if let settled = resultBox.withLock({ $0 }) {
                    return translateManagedResult(settled, domain: domain)
                }
                return .failure(DICOMManagedFailure(.limitExceeded, 3, domain: domain))
            }
        }

        if let failure = cancellation.failure {
            return .failure(failure)
        }
        if Task.isCancelled {
            return .failure(DICOMManagedFailure(.cancelled))
        }
        guard let settled = resultBox.withLock({ $0 }) else {
            return .failure(DICOMManagedFailure(.codecFailure, 1, domain: domain))
        }
        return translateManagedResult(settled, domain: domain)
    }

    private static func translateManagedResult<T>(
        _ result: Result<T, any Error>,
        domain: UInt16
    ) -> DICOMManagedOutcome<T> {
        switch result {
        case .success(let value):
            return .success(value)
        case .failure(let error):
            if error is CancellationError {
                return .failure(DICOMManagedFailure(.cancelled))
            }
            if let managed = error as? DICOMManagedFailure {
                return .failure(managed)
            }
            if let dicomError = error as? DICOMError {
                switch dicomError {
                case .limitExceeded:
                    return .failure(DICOMManagedFailure(.limitExceeded, 8, domain: domain))
                case .unsupportedTransferSyntax:
                    return .failure(DICOMManagedFailure(.invalidTransferSyntax, 9, domain: domain))
                default:
                    return .failure(DICOMManagedFailure(.malformed, 10, domain: domain))
                }
            }
            return .failure(DICOMManagedFailure(.codecFailure, 107, domain: domain))
        }
    }
}
