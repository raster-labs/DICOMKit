// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (inference timing and memory metrics)
import Foundation

#if canImport(CoreML)
import CoreML
#endif

// MARK: - Performance Metrics

/// Performance metrics for AI model inference
@available(macOS 14.0, iOS 17.0, *)
struct PerformanceMetrics: Sendable {
    /// Inference time in seconds
    let inferenceTime: Double
    
    /// Preprocessing time in seconds
    let preprocessingTime: Double?
    
    /// Postprocessing time in seconds
    let postprocessingTime: Double?
    
    /// Total time (preprocessing + inference + postprocessing)
    var totalTime: Double {
        return (preprocessingTime ?? 0.0) + inferenceTime + (postprocessingTime ?? 0.0)
    }
    
    /// Memory usage in bytes (if available)
    let memoryUsage: Int64?
    
    /// Model name
    let modelName: String?
    
    /// Timestamp when metrics were recorded
    let timestamp: Date
    
    init(
        inferenceTime: Double,
        preprocessingTime: Double? = nil,
        postprocessingTime: Double? = nil,
        memoryUsage: Int64? = nil,
        modelName: String? = nil,
        timestamp: Date = Date()
    ) {
        self.inferenceTime = inferenceTime
        self.preprocessingTime = preprocessingTime
        self.postprocessingTime = postprocessingTime
        self.memoryUsage = memoryUsage
        self.modelName = modelName
        self.timestamp = timestamp
    }
    
    /// Format metrics as a human-readable string
    func formatted() -> String {
        var lines: [String] = []
        
        if let name = modelName {
            lines.append("Model: \(name)")
        }
        
        if let prep = preprocessingTime {
            lines.append("Preprocessing: \(String(format: "%.3f", prep))s")
        }
        
        lines.append("Inference: \(String(format: "%.3f", inferenceTime))s")
        
        if let post = postprocessingTime {
            lines.append("Postprocessing: \(String(format: "%.3f", post))s")
        }
        
        lines.append("Total: \(String(format: "%.3f", totalTime))s")
        
        if let mem = memoryUsage {
            let memMB = Double(mem) / (1024.0 * 1024.0)
            lines.append("Memory: \(String(format: "%.2f", memMB)) MB")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Format metrics as JSON
    func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let dict: [String: Any] = [
            "model_name": modelName ?? "unknown",
            "inference_time_seconds": inferenceTime,
            "preprocessing_time_seconds": preprocessingTime ?? NSNull(),
            "postprocessing_time_seconds": postprocessingTime ?? NSNull(),
            "total_time_seconds": totalTime,
            "memory_usage_bytes": memoryUsage ?? NSNull(),
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Performance Profiler

/// Profiler for tracking AI model performance
@available(macOS 14.0, iOS 17.0, *)
class PerformanceProfiler {
    private var startTime: Date?
    private var preprocessingStart: Date?
    private var preprocessingEnd: Date?
    private var inferenceStart: Date?
    private var inferenceEnd: Date?
    private var postprocessingStart: Date?
    private var postprocessingEnd: Date?
    
    private let modelName: String?
    private let verbose: Bool
    
    init(modelName: String? = nil, verbose: Bool = false) {
        self.modelName = modelName
        self.verbose = verbose
    }
    
    /// Start overall timing
    func start() {
        startTime = Date()
        if verbose {
            print("Performance profiling started")
        }
    }
    
    /// Start preprocessing phase
    func startPreprocessing() {
        preprocessingStart = Date()
        if verbose {
            print("Preprocessing started")
        }
    }
    
    /// End preprocessing phase
    func endPreprocessing() {
        preprocessingEnd = Date()
        if verbose, let start = preprocessingStart, let end = preprocessingEnd {
            let duration = end.timeIntervalSince(start)
            print("Preprocessing completed in \(String(format: "%.3f", duration))s")
        }
    }
    
    /// Start inference phase
    func startInference() {
        inferenceStart = Date()
        if verbose {
            print("Inference started")
        }
    }
    
    /// End inference phase
    func endInference() {
        inferenceEnd = Date()
        if verbose, let start = inferenceStart, let end = inferenceEnd {
            let duration = end.timeIntervalSince(start)
            print("Inference completed in \(String(format: "%.3f", duration))s")
        }
    }
    
    /// Start postprocessing phase
    func startPostprocessing() {
        postprocessingStart = Date()
        if verbose {
            print("Postprocessing started")
        }
    }
    
    /// End postprocessing phase
    func endPostprocessing() {
        postprocessingEnd = Date()
        if verbose, let start = postprocessingStart, let end = postprocessingEnd {
            let duration = end.timeIntervalSince(start)
            print("Postprocessing completed in \(String(format: "%.3f", duration))s")
        }
    }
    
    /// Get the collected metrics
    /// - Returns: Performance metrics
    func getMetrics() -> PerformanceMetrics? {
        guard let infStart = inferenceStart, let infEnd = inferenceEnd else {
            return nil
        }
        
        let inferenceTime = infEnd.timeIntervalSince(infStart)
        
        let preprocessingTime: Double?
        if let prepStart = preprocessingStart, let prepEnd = preprocessingEnd {
            preprocessingTime = prepEnd.timeIntervalSince(prepStart)
        } else {
            preprocessingTime = nil
        }
        
        let postprocessingTime: Double?
        if let postStart = postprocessingStart, let postEnd = postprocessingEnd {
            postprocessingTime = postEnd.timeIntervalSince(postStart)
        } else {
            postprocessingTime = nil
        }
        
        // Get memory usage (current process memory)
        let memoryUsage = getMemoryUsage()
        
        return PerformanceMetrics(
            inferenceTime: inferenceTime,
            preprocessingTime: preprocessingTime,
            postprocessingTime: postprocessingTime,
            memoryUsage: memoryUsage,
            modelName: modelName
        )
    }
    
    /// Reset the profiler
    func reset() {
        startTime = nil
        preprocessingStart = nil
        preprocessingEnd = nil
        inferenceStart = nil
        inferenceEnd = nil
        postprocessingStart = nil
        postprocessingEnd = nil
    }
    
    /// Get current memory usage in bytes
    private func getMemoryUsage() -> Int64? {
        #if os(macOS) || os(iOS)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int64(info.resident_size)
        }
        #endif
        
        return nil
    }
}

// MARK: - Model Cache

/// Cache for compiled CoreML models to improve load times
@available(macOS 14.0, iOS 17.0, *)
class ModelCache {
    private let maxCacheSize: Int
    private let verbose: Bool
    
    #if canImport(CoreML)
    private var cache: [String: MLModel] = [:]
    private var accessTimes: [String: Date] = [:]
    
    init(maxCacheSize: Int = 5, verbose: Bool = false) {
        self.maxCacheSize = maxCacheSize
        self.verbose = verbose
    }
    
    /// Get a model from cache or load it
    func getOrLoad(url: URL) throws -> MLModel {
        let key = url.path
        
        // Check if model is in cache
        if let cachedModel = cache[key] {
            accessTimes[key] = Date()
            if verbose {
                print("Model loaded from cache: \(url.lastPathComponent)")
            }
            return cachedModel
        }
        
        // Load the model
        if verbose {
            print("Loading model: \(url.lastPathComponent)")
        }
        
        let compiledURL: URL
        if url.pathExtension == "mlmodelc" {
            compiledURL = url
        } else if url.pathExtension == "mlmodel" {
            compiledURL = try MLModel.compileModel(at: url)
        } else {
            throw AIError.invalidModelFormat("Model must be .mlmodel or .mlmodelc")
        }
        
        let configuration = MLModelConfiguration()
        #if os(macOS) || os(iOS)
        configuration.computeUnits = .all
        #endif
        
        let model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        
        // Add to cache
        cache[key] = model
        accessTimes[key] = Date()
        
        // Evict old entries if cache is full
        if cache.count > maxCacheSize {
            evictLeastRecentlyUsed()
        }
        
        if verbose {
            print("Model cached: \(url.lastPathComponent) (cache size: \(cache.count)/\(maxCacheSize))")
        }
        
        return model
    }
    
    /// Clear the cache
    func clear() {
        cache.removeAll()
        accessTimes.removeAll()
        if verbose {
            print("Model cache cleared")
        }
    }
    
    /// Remove a specific model from cache
    func remove(url: URL) {
        let key = url.path
        cache.removeValue(forKey: key)
        accessTimes.removeValue(forKey: key)
        if verbose {
            print("Removed from cache: \(url.lastPathComponent)")
        }
    }
    
    /// Evict the least recently used model
    private func evictLeastRecentlyUsed() {
        guard let lruKey = accessTimes.min(by: { $0.value < $1.value })?.key else {
            return
        }
        
        cache.removeValue(forKey: lruKey)
        accessTimes.removeValue(forKey: lruKey)
        
        if verbose {
            print("Evicted LRU model from cache: \(lruKey)")
        }
    }
    #else
    // Non-CoreML platforms
    init(maxCacheSize: Int = 5, verbose: Bool = false) {
        self.maxCacheSize = maxCacheSize
        self.verbose = verbose
    }
    
    func clear() {}
    #endif
}
