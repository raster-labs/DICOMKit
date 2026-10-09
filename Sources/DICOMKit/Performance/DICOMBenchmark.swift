// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (timing harness)
import Foundation

#if canImport(CoreFoundation)
import CoreFoundation
#endif

#if canImport(Darwin)
@preconcurrency import Darwin
#endif

/// Benchmark result for a single measurement
public struct BenchmarkResult: Sendable {
    /// Name of the benchmark
    public let name: String

    /// Duration in seconds
    public let duration: TimeInterval

    /// Peak memory usage in bytes
    ///
    /// Note: from the legacy API this is a resident-size *delta* sampled after
    /// each iteration returns. Prefer `peakResidentBytes` (true high-water,
    /// sampled concurrently) for memory claims.
    public let peakMemoryUsage: Int64?

    /// Number of iterations
    public let iterations: Int

    /// Per-iteration wall-clock samples in seconds (monotonic clock).
    ///
    /// Empty when produced by the legacy aggregate-only path.
    public let samples: [TimeInterval]

    /// True high-water resident set size in bytes over the measured region,
    /// captured by a concurrent sampler thread (nil when memory tracking was off
    /// or sampling unavailable). Unlike `peakMemoryUsage` this sees transient
    /// peaks inside an iteration, and is absolute, not a delta.
    public let peakResidentBytes: Int64?

    /// Resident set size in bytes immediately before the measured region.
    public let baselineResidentBytes: Int64?

    /// Duration of the very first (cold) invocation, before warm-up, when the
    /// measurement was configured to record it.
    public let coldDuration: TimeInterval?

    // MARK: Distribution statistics (empty-sample safe)

    private var sortedSamples: [TimeInterval] { samples.sorted() }

    /// Median (P50) per-iteration duration in seconds
    public var medianDuration: TimeInterval? { percentile(50) }

    /// Percentile of the per-iteration samples (nearest-rank), e.g. 90, 95.
    public func percentile(_ p: Double) -> TimeInterval? {
        let sorted = sortedSamples
        guard !sorted.isEmpty else { return nil }
        let rank = Int((p / 100.0 * Double(sorted.count)).rounded(.up))
        return sorted[Swift.max(0, Swift.min(sorted.count - 1, rank - 1))]
    }

    /// Minimum per-iteration duration in seconds
    public var minDuration: TimeInterval? { sortedSamples.first }

    /// Maximum per-iteration duration in seconds
    public var maxDuration: TimeInterval? { sortedSamples.last }

    /// Sample standard deviation of the per-iteration durations in seconds
    public var standardDeviation: TimeInterval? {
        guard samples.count > 1 else { return nil }
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            / Double(samples.count - 1)
        return variance.squareRoot()
    }

    /// Average duration per iteration in seconds
    public var averageDuration: TimeInterval {
        duration / Double(iterations)
    }
    
    /// Duration in milliseconds
    public var durationMs: Double {
        duration * 1000.0
    }
    
    /// Average duration per iteration in milliseconds
    public var averageDurationMs: Double {
        averageDuration * 1000.0
    }
    
    /// Peak memory usage in megabytes
    public var peakMemoryUsageMB: Double? {
        guard let bytes = peakMemoryUsage else { return nil }
        return Double(bytes) / (1024.0 * 1024.0)
    }
    
    public init(
        name: String,
        duration: TimeInterval,
        peakMemoryUsage: Int64? = nil,
        iterations: Int = 1,
        samples: [TimeInterval] = [],
        peakResidentBytes: Int64? = nil,
        baselineResidentBytes: Int64? = nil,
        coldDuration: TimeInterval? = nil
    ) {
        self.name = name
        self.duration = duration
        self.peakMemoryUsage = peakMemoryUsage
        self.iterations = iterations
        self.samples = samples
        self.peakResidentBytes = peakResidentBytes
        self.baselineResidentBytes = baselineResidentBytes
        self.coldDuration = coldDuration
    }
}

/// Concurrent resident-memory high-water sampler
///
/// Polls the task's resident set size on a detached thread (~1 ms cadence) so
/// transient allocation peaks *inside* an operation are captured — the shared
/// benchmark baseline (§6.9) requires high-water marks over the complete
/// operation, not point samples after it returns.
final class ResidentMemorySampler: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var peak: Int64 = 0

    /// Resident size at `start()`.
    private(set) var baseline: Int64 = 0

    func start() {
        baseline = DICOMBenchmark.residentMemoryBytes()
        lock.lock()
        peak = baseline
        running = true
        lock.unlock()
        Thread.detachNewThread { [weak self] in
            while true {
                guard let self else { return }
                let current = DICOMBenchmark.residentMemoryBytes()
                self.lock.lock()
                if !self.running { self.lock.unlock(); return }
                if current > self.peak { self.peak = current }
                self.lock.unlock()
                usleep(1000)
            }
        }
    }

    /// Stops sampling and returns the observed high-water mark (absolute bytes).
    func stop() -> Int64 {
        lock.lock()
        running = false
        let result = max(peak, DICOMBenchmark.residentMemoryBytes())
        lock.unlock()
        return result
    }
}

/// Benchmark harness for measuring DICOM operations performance
public struct DICOMBenchmark {
    /// Measures an operation with per-iteration samples, a monotonic clock,
    /// concurrent high-water memory sampling, and optional cold-run capture.
    ///
    /// This is the M1 measurement path (RESEARCH_ADOPTION_PLAN.md): report
    /// median and tail statistics from `BenchmarkResult.samples`, never only
    /// the mean; use `peakResidentBytes` for memory claims.
    ///
    /// - Parameters:
    ///   - name: Name of the benchmark
    ///   - iterations: Number of measured iterations (default: 10)
    ///   - warmup: Warm-up iterations before measurement (default: 3)
    ///   - trackMemory: Run the concurrent resident-memory sampler (default: true)
    ///   - recordCold: Time the very first invocation separately, before
    ///     warm-up, as the cold-start figure (default: false)
    ///   - operation: The operation to benchmark
    public static func measureDetailed<T>(
        name: String,
        iterations: Int = 10,
        warmup: Int = 3,
        trackMemory: Bool = true,
        recordCold: Bool = false,
        operation: () throws -> T
    ) rethrows -> BenchmarkResult {
        var coldDuration: TimeInterval?
        if recordCold {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = try operation()
            coldDuration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        }

        for _ in 0..<warmup {
            _ = try operation()
        }

        let sampler: ResidentMemorySampler? = trackMemory ? ResidentMemorySampler() : nil
        sampler?.start()

        var samples: [TimeInterval] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = try operation()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9)
        }

        let peakResident = sampler?.stop()

        return BenchmarkResult(
            name: name,
            duration: samples.reduce(0, +),
            peakMemoryUsage: peakResident.map { $0 - (sampler?.baseline ?? 0) },
            iterations: iterations,
            samples: samples,
            peakResidentBytes: peakResident,
            baselineResidentBytes: sampler?.baseline,
            coldDuration: coldDuration
        )
    }

    /// Current resident set size in bytes (0 where unavailable).
    static func residentMemoryBytes() -> Int64 {
        currentMemoryUsage()
    }

    /// Measures the execution time of a synchronous operation
    ///
    /// - Parameters:
    ///   - name: Name of the benchmark
    ///   - iterations: Number of times to run the operation (default: 1)
    ///   - warmup: Number of warmup iterations before measurement (default: 0)
    ///   - trackMemory: Whether to track peak memory usage (default: false)
    ///   - operation: The operation to benchmark
    /// - Returns: Benchmark result with timing information
    public static func measure<T>(
        name: String,
        iterations: Int = 1,
        warmup: Int = 0,
        trackMemory: Bool = false,
        operation: () throws -> T
    ) rethrows -> BenchmarkResult {
        // Warmup runs
        for _ in 0..<warmup {
            _ = try operation()
        }
        
        // Memory tracking setup
        var initialMemory: Int64 = 0
        var peakMemory: Int64 = 0
        if trackMemory {
            initialMemory = currentMemoryUsage()
        }
        
        // Measure iterations
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            _ = try operation()
            
            if trackMemory {
                let currentMemory = currentMemoryUsage()
                peakMemory = max(peakMemory, currentMemory)
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        let memoryDelta = trackMemory ? (peakMemory - initialMemory) : nil
        
        return BenchmarkResult(
            name: name,
            duration: duration,
            peakMemoryUsage: memoryDelta,
            iterations: iterations
        )
    }
    
    /// Measures the execution time of an asynchronous operation
    ///
    /// - Parameters:
    ///   - name: Name of the benchmark
    ///   - iterations: Number of times to run the operation (default: 1)
    ///   - warmup: Number of warmup iterations before measurement (default: 0)
    ///   - trackMemory: Whether to track peak memory usage (default: false)
    ///   - operation: The async operation to benchmark
    /// - Returns: Benchmark result with timing information
    public static func measureAsync<T>(
        name: String,
        iterations: Int = 1,
        warmup: Int = 0,
        trackMemory: Bool = false,
        operation: () async throws -> T
    ) async rethrows -> BenchmarkResult {
        // Warmup runs
        for _ in 0..<warmup {
            _ = try await operation()
        }
        
        // Memory tracking setup
        var initialMemory: Int64 = 0
        var peakMemory: Int64 = 0
        if trackMemory {
            initialMemory = currentMemoryUsage()
        }
        
        // Measure iterations
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            _ = try await operation()
            
            if trackMemory {
                let currentMemory = currentMemoryUsage()
                peakMemory = max(peakMemory, currentMemory)
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        let memoryDelta = trackMemory ? (peakMemory - initialMemory) : nil
        
        return BenchmarkResult(
            name: name,
            duration: duration,
            peakMemoryUsage: memoryDelta,
            iterations: iterations
        )
    }
    
    /// Gets the current memory usage of the process
    ///
    /// - Returns: Memory usage in bytes
    private static func currentMemoryUsage() -> Int64 {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let taskPort = mach_task_self_
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    taskPort,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        
        guard kerr == KERN_SUCCESS else {
            return 0
        }
        
        return Int64(info.resident_size)
        #else
        // Memory tracking not available on this platform
        return 0
        #endif
    }
}

/// Comparison result between two benchmarks
public struct BenchmarkComparison: Sendable {
    /// Baseline result
    public let baseline: BenchmarkResult
    
    /// Optimized result
    public let optimized: BenchmarkResult
    
    /// Speed improvement factor (positive = faster, negative = slower)
    public var speedImprovement: Double {
        baseline.averageDuration / optimized.averageDuration
    }
    
    /// Speed improvement percentage
    public var speedImprovementPercent: Double {
        (speedImprovement - 1.0) * 100.0
    }
    
    /// Memory improvement factor (positive = less memory, negative = more memory)
    public var memoryImprovement: Double? {
        guard let baselineMem = baseline.peakMemoryUsage,
              let optimizedMem = optimized.peakMemoryUsage else {
            return nil
        }
        return Double(baselineMem) / Double(optimizedMem)
    }
    
    /// Memory improvement percentage
    public var memoryImprovementPercent: Double? {
        guard let improvement = memoryImprovement else {
            return nil
        }
        return (improvement - 1.0) * 100.0
    }
    
    public init(baseline: BenchmarkResult, optimized: BenchmarkResult) {
        self.baseline = baseline
        self.optimized = optimized
    }
    
    /// Formats the comparison as a human-readable string
    public var description: String {
        var result = "Benchmark Comparison: \(baseline.name)\n"
        result += "  Baseline: \(String(format: "%.2f", baseline.averageDurationMs))ms"
        if let mem = baseline.peakMemoryUsageMB {
            result += " (\(String(format: "%.2f", mem))MB)"
        }
        result += "\n"
        result += "  Optimized: \(String(format: "%.2f", optimized.averageDurationMs))ms"
        if let mem = optimized.peakMemoryUsageMB {
            result += " (\(String(format: "%.2f", mem))MB)"
        }
        result += "\n"
        result += "  Speed: \(String(format: "%.1f", speedImprovementPercent))% improvement"
        if let memImp = memoryImprovementPercent {
            result += "\n"
            result += "  Memory: \(String(format: "%.1f", memImp))% reduction"
        }
        return result
    }
}
