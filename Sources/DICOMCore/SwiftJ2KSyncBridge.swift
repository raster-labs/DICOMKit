import Foundation
import Dispatch
import Synchronization
import SwiftJ2K

private final class SwiftJ2KTaskExecutor: TaskExecutor {
    static let shared = SwiftJ2KTaskExecutor()

    private let queue = DispatchQueue(
        label: "com.dicomkit.swiftj2k.task-executor",
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

enum SwiftJ2KSyncBridge {
    /// Bridges synchronous `DICOMCore` codec protocols onto `SwiftJ2K`'s `@concurrent` scalar operations
    /// using a dedicated GCD-backed `TaskExecutor` (preventing Swift cooperative thread-pool starvation
    /// when called from inside `TaskGroup`s) with cooperative cancellation propagation, finite wall-clock
    /// deadline enforcement, and bounded join.
    static func run<T: Sendable>(
        options: SwiftJ2KProviderOptions,
        operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        try Task.checkCancellation()

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = Mutex<Result<T, any Error>?>(nil)

        let worker = Task.detached(executorPreference: SwiftJ2KTaskExecutor.shared, priority: .userInitiated) {
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
        let totalBudgetSeconds = max(0.05, options.resourceLimits.deadlineSeconds + min(options.joinGraceSeconds, 2.0))
        let hardDeadline = clock.now.advanced(by: .milliseconds(Int((totalBudgetSeconds * 1_000.0).rounded(.up))))
        let joinTimeoutMs = max(50, Int((options.joinGraceSeconds * 1_000.0).rounded(.up)))

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
                    return try unwrapResult(settled)
                }
                throw DICOMError.limitExceeded(
                    "SwiftJ2K operation exceeded deadline (\(options.resourceLimits.deadlineSeconds)s)"
                )
            }
        }

        try Task.checkCancellation()
        guard let settled = resultBox.withLock({ $0 }) else {
            throw DICOMError.parsingFailed("SwiftJ2K synchronous bridge completed without a result")
        }
        return try unwrapResult(settled)
    }

    /// Scalar-outcome synchronous bridge for `DICOMAllocationBudget` / `ManagedDecodedPixelFrame` decoding.
    /// Propagates synchronous `DICOMCancellation` callbacks, cooperative `Task` cancellation, and finite
    /// wall-clock deadlines with bounded worker join.
    static func runManaged<T: Sendable>(
        options: SwiftJ2KProviderOptions,
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

        let worker = Task.detached(executorPreference: SwiftJ2KTaskExecutor.shared, priority: .userInitiated) {
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
        let totalBudgetSeconds = max(0.05, options.resourceLimits.deadlineSeconds + min(options.joinGraceSeconds, 2.0))
        let hardDeadline = clock.now.advanced(by: .milliseconds(Int((totalBudgetSeconds * 1_000.0).rounded(.up))))
        let joinTimeoutMs = max(50, Int((options.joinGraceSeconds * 1_000.0).rounded(.up)))

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
                    return translateManagedResult(settled)
                }
                return .failure(DICOMManagedFailure(.limitExceeded, 3, domain: 2))
            }
        }

        if let failure = cancellation.failure {
            return .failure(failure)
        }
        if Task.isCancelled {
            return .failure(DICOMManagedFailure(.cancelled))
        }
        guard let settled = resultBox.withLock({ $0 }) else {
            return .failure(DICOMManagedFailure(.codecFailure, 1, domain: 2))
        }
        return translateManagedResult(settled)
    }

    static func translateManagedError(_ error: any Error) -> DICOMManagedFailure {
        if error is CancellationError {
            return DICOMManagedFailure(.cancelled)
        }
        if let managed = error as? DICOMManagedFailure {
            return managed
        }
        if let codecError = error as? CodecError {
            switch codecError.category {
            case .resourceLimitExceeded:
                return DICOMManagedFailure(.limitExceeded, 4, domain: 2)
            case .unsupportedFeature, .unsupportedFormat, .backendUnavailable:
                return DICOMManagedFailure(.invalidTransferSyntax, 5, domain: 2)
            case .malformedInput, .invalidArgument, .incompatibleImageLayout:
                return DICOMManagedFailure(.malformed, 6, domain: 2)
            case .storageUnavailable, .ioFailure, .internalFailure:
                return DICOMManagedFailure(.codecFailure, 7, domain: 2)
            }
        }
        if let dicomError = error as? DICOMError {
            switch dicomError {
            case .limitExceeded:
                return DICOMManagedFailure(.limitExceeded, 8, domain: 2)
            case .unsupportedTransferSyntax:
                return DICOMManagedFailure(.invalidTransferSyntax, 9, domain: 2)
            default:
                return DICOMManagedFailure(.malformed, 10, domain: 2)
            }
        }
        return DICOMManagedFailure(.codecFailure, 11, domain: 2)
    }

    private static func translateManagedResult<T>(_ result: Result<T, any Error>) -> DICOMManagedOutcome<T> {
        switch result {
        case .success(let value):
            return .success(value)
        case .failure(let error):
            return .failure(translateManagedError(error))
        }
    }

    static func translateError(_ error: any Error) -> any Error {
        if error is CancellationError {
            return error
        }
        if let dicomError = error as? DICOMError {
            return dicomError
        }
        if let codecError = error as? CodecError {
            switch codecError.category {
            case .resourceLimitExceeded:
                return DICOMError.limitExceeded("SwiftJ2K resource limit exceeded: \(codecError.message)")
            case .unsupportedFeature, .unsupportedFormat, .backendUnavailable:
                return DICOMError.unsupportedTransferSyntax("SwiftJ2K unsupported capability: \(codecError.message)")
            case .malformedInput, .invalidArgument, .incompatibleImageLayout,
                 .storageUnavailable, .ioFailure, .internalFailure:
                return DICOMError.parsingFailed("SwiftJ2K \(codecError.category.rawValue): \(codecError.message)")
            }
        }
        return DICOMError.parsingFailed("SwiftJ2K operation failed: \(error)")
    }

    private static func unwrapResult<T>(_ result: Result<T, any Error>) throws -> T {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw translateError(error)
        }
    }
}
