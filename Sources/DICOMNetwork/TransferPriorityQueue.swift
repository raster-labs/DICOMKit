import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-09-28 — mapping to/from the three PS3.7 2026a Table E.1-1 Priority values checked; queue ranks are DICOMKit's own

// MARK: - Transfer Priority

/// Priority level for DICOM transfers
///
/// Higher priority transfers are processed before lower priority ones.
/// This allows urgent studies (e.g., STAT exams) to be transferred first.
///
/// ## Priority Levels
///
/// - **stat**: Highest priority for emergency/urgent cases
/// - **high**: High priority for time-sensitive transfers
/// - **normal**: Default priority for routine transfers
/// - **low**: Low priority for batch/background transfers
/// - **background**: Lowest priority for non-urgent transfers
///
/// Reference: DICOM PS3.7 - Priority (0000,0700), Table E.1-1 and Section 9.1
public enum TransferPriority: Int, Sendable, Comparable, CaseIterable, Codable {
    /// Highest priority - emergency/STAT cases
    case stat = 0
    
    /// High priority - time-sensitive transfers
    case high = 1
    
    /// Normal priority - routine transfers
    case normal = 2
    
    /// Low priority - batch transfers
    case low = 3
    
    /// Background priority - non-urgent transfers
    case background = 4
    
    public static func < (lhs: TransferPriority, rhs: TransferPriority) -> Bool {
        // Lower raw value = higher priority
        lhs.rawValue < rhs.rawValue
    }
    
    /// Converts from DIMSE priority
    public init(fromDIMSE priority: DIMSEPriority) {
        switch priority {
        case .high:
            self = .high
        case .medium:
            self = .normal
        case .low:
            self = .low
        }
    }
    
    /// Converts to DIMSE priority
    public var dimseValue: DIMSEPriority {
        switch self {
        case .stat, .high:
            return .high
        case .normal:
            return .medium
        case .low, .background:
            return .low
        }
    }
}

extension TransferPriority: CustomStringConvertible {
    public var description: String {
        switch self {
        case .stat: return "STAT"
        case .high: return "High"
        case .normal: return "Normal"
        case .low: return "Low"
        case .background: return "Background"
        }
    }
}

// MARK: - Prioritized Transfer Item

/// A transfer item with priority information
///
/// Wraps transfer data with priority and timing metadata
/// for queue management.
public struct PrioritizedTransferItem<T: Sendable>: Sendable, Identifiable {
    /// Unique identifier for this transfer
    public let id: UUID
    
    /// The transfer data
    public let data: T
    
    /// Priority level
    public let priority: TransferPriority
    
    /// When the item was queued
    public let queuedAt: Date
    
    /// Optional deadline for the transfer
    public let deadline: Date?
    
    /// Custom tag for grouping transfers
    public let tag: String?
    
    /// Whether this item should be removed on queue full
    ///
    /// When the queue is full, items with `droppable: true` may be
    /// removed to make room for higher priority items.
    public let droppable: Bool
    
    /// Creates a prioritized transfer item
    ///
    /// - Parameters:
    ///   - data: The transfer data
    ///   - priority: Priority level (default: normal)
    ///   - deadline: Optional deadline for the transfer
    ///   - tag: Optional tag for grouping
    ///   - droppable: Whether item can be dropped when queue is full
    public init(
        data: T,
        priority: TransferPriority = .normal,
        deadline: Date? = nil,
        tag: String? = nil,
        droppable: Bool = false
    ) {
        self.id = UUID()
        self.data = data
        self.priority = priority
        self.queuedAt = Date()
        self.deadline = deadline
        self.tag = tag
        self.droppable = droppable
    }
    
    /// Whether the deadline has passed
    public var isExpired: Bool {
        guard let deadline = deadline else { return false }
        return Date() > deadline
    }
    
    /// Time remaining until deadline (nil if no deadline)
    public var timeRemaining: TimeInterval? {
        guard let deadline = deadline else { return nil }
        return deadline.timeIntervalSinceNow
    }
}

extension PrioritizedTransferItem: Equatable where T: Equatable {
    public static func == (lhs: PrioritizedTransferItem<T>, rhs: PrioritizedTransferItem<T>) -> Bool {
        lhs.id == rhs.id
    }
}

extension PrioritizedTransferItem: Hashable where T: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Priority Queue Configuration

/// Configuration for the transfer priority queue
public struct TransferPriorityQueueConfiguration: Sendable {
    
    /// Maximum number of items in the queue (0 = unlimited)
    public let maxSize: Int
    
    /// Whether to allow dropping low-priority items when full
    public let allowDroppingOnFull: Bool
    
    /// Maximum age for items before auto-expiration (nil = no limit)
    public let maxAge: TimeInterval?
    
    /// Enable aging - gradually increase priority of old items
    public let enableAging: Bool
    
    /// Time interval after which items get a priority boost
    public let agingInterval: TimeInterval
    
    /// Creates a priority queue configuration
    ///
    /// - Parameters:
    ///   - maxSize: Maximum queue size (0 = unlimited)
    ///   - allowDroppingOnFull: Allow dropping low priority items when full
    ///   - maxAge: Maximum item age before expiration
    ///   - enableAging: Enable priority aging
    ///   - agingInterval: Interval for priority boost
    public init(
        maxSize: Int = 0,
        allowDroppingOnFull: Bool = true,
        maxAge: TimeInterval? = nil,
        enableAging: Bool = false,
        agingInterval: TimeInterval = 300 // 5 minutes
    ) {
        self.maxSize = max(0, maxSize)
        self.allowDroppingOnFull = allowDroppingOnFull
        self.maxAge = maxAge
        self.enableAging = enableAging
        self.agingInterval = max(1, agingInterval)
    }
    
    /// Default configuration
    public static let `default` = TransferPriorityQueueConfiguration()
    
    /// Strict configuration with size limits
    public static func limited(size: Int) -> TransferPriorityQueueConfiguration {
        TransferPriorityQueueConfiguration(
            maxSize: size,
            allowDroppingOnFull: true
        )
    }
}

// MARK: - Queue Statistics

/// Statistics about the priority queue
public struct TransferPriorityQueueStatistics: Sendable {
    /// Total items in queue by priority
    public let itemsByPriority: [TransferPriority: Int]
    
    /// Total items in the queue
    public let totalItems: Int
    
    /// Total items processed since creation
    public let totalProcessed: Int
    
    /// Total items dropped due to capacity
    public let totalDropped: Int
    
    /// Total items expired
    public let totalExpired: Int
    
    /// Average wait time in queue (seconds)
    public let averageWaitTime: TimeInterval
    
    /// Oldest item age in seconds
    public let oldestItemAge: TimeInterval?
}

// MARK: - Queue Event

/// Events emitted by the priority queue
public enum TransferPriorityQueueEvent<T: Sendable>: Sendable {
    /// Item was enqueued
    case itemEnqueued(PrioritizedTransferItem<T>)
    
    /// Item was dequeued for processing
    case itemDequeued(PrioritizedTransferItem<T>)
    
    /// Item was dropped due to capacity
    case itemDropped(PrioritizedTransferItem<T>)
    
    /// Item expired
    case itemExpired(PrioritizedTransferItem<T>)
    
    /// Item priority was boosted due to aging
    case priorityBoosted(id: UUID, from: TransferPriority, to: TransferPriority)
    
    /// Queue reached capacity
    case queueFull(size: Int)
    
    /// Queue was cleared
    case queueCleared(itemCount: Int)
}

// MARK: - Transfer Priority Queue

/// Thread-safe priority queue for DICOM transfers
///
/// Manages transfers with priority ordering, ensuring that urgent transfers
/// are processed before routine ones. Supports deadline tracking, aging,
/// and capacity management.
///
/// ## Priority Ordering
///
/// Items are processed in priority order (stat > high > normal > low > background).
/// Within the same priority level, items are processed in FIFO order.
///
/// ## Aging
///
/// Optional aging support gradually increases the priority of waiting items,
/// preventing starvation of low-priority transfers.
///
/// ## Usage
///
/// ```swift
/// let queue = TransferPriorityQueue<Data>(
///     configuration: .limited(size: 1000)
/// )
///
/// // Enqueue with priority
/// try await queue.enqueue(imageData, priority: .stat)
/// try await queue.enqueue(reportData, priority: .normal)
///
/// // Dequeue highest priority item
/// if let item = await queue.dequeue() {
///     // Process item.data
/// }
/// ```
public actor TransferPriorityQueue<T: Sendable> {
    
    // MARK: - Properties
    
    /// Configuration
    public let configuration: TransferPriorityQueueConfiguration
    
    /// Items by priority level
    private var buckets: [TransferPriority: [PrioritizedTransferItem<T>]]
    
    /// Total items processed
    private var totalProcessed: Int = 0
    
    /// Total items dropped
    private var totalDropped: Int = 0
    
    /// Total items expired
    private var totalExpired: Int = 0
    
    /// Sum of wait times for average calculation
    private var totalWaitTime: TimeInterval = 0
    
    /// Event continuation for streaming events
    private var eventContinuation: AsyncStream<TransferPriorityQueueEvent<T>>.Continuation?
    
    /// Event stream
    private var _events: AsyncStream<TransferPriorityQueueEvent<T>>?
    
    // MARK: - Initialization
    
    /// Creates a transfer priority queue
    ///
    /// - Parameter configuration: Queue configuration
    public init(configuration: TransferPriorityQueueConfiguration = .default) {
        self.configuration = configuration
        self.buckets = Dictionary(uniqueKeysWithValues: TransferPriority.allCases.map { ($0, []) })
    }
    
    // MARK: - Event Stream
    
    /// Stream of queue events
    public var events: AsyncStream<TransferPriorityQueueEvent<T>> {
        if let existing = _events {
            return existing
        }
        
        let stream = AsyncStream<TransferPriorityQueueEvent<T>> { continuation in
            self.eventContinuation = continuation
        }
        _events = stream
        return stream
    }
    
    // MARK: - Enqueue Methods
    
    /// Enqueues an item with the specified priority
    ///
    /// - Parameters:
    ///   - data: The data to enqueue
    ///   - priority: Priority level
    ///   - deadline: Optional deadline
    ///   - tag: Optional grouping tag
    ///   - droppable: Whether item can be dropped when full
    /// - Returns: The created transfer item
    /// - Throws: Error if queue is full and cannot make room
    @discardableResult
    public func enqueue(
        _ data: T,
        priority: TransferPriority = .normal,
        deadline: Date? = nil,
        tag: String? = nil,
        droppable: Bool = false
    ) throws -> PrioritizedTransferItem<T> {
        let item = PrioritizedTransferItem(
            data: data,
            priority: priority,
            deadline: deadline,
            tag: tag,
            droppable: droppable
        )
        
        try enqueue(item)
        return item
    }
    
    /// Enqueues a pre-created item
    ///
    /// - Parameter item: The item to enqueue
    /// - Throws: Error if queue is full and cannot make room
    public func enqueue(_ item: PrioritizedTransferItem<T>) throws {
        // Remove expired items first
        removeExpiredItems()
        
        // Check capacity
        let currentCount = totalCount
        if configuration.maxSize > 0 && currentCount >= configuration.maxSize {
            if configuration.allowDroppingOnFull {
                // Try to drop a lower priority droppable item
                if !dropLowestPriorityDroppable(below: item.priority) {
                    throw TransferPriorityQueueError.queueFull(
                        capacity: configuration.maxSize,
                        requestedPriority: item.priority
                    )
                }
            } else {
                eventContinuation?.yield(.queueFull(size: currentCount))
                throw TransferPriorityQueueError.queueFull(
                    capacity: configuration.maxSize,
                    requestedPriority: item.priority
                )
            }
        }
        
        // Add to appropriate bucket
        buckets[item.priority]?.append(item)
        
        eventContinuation?.yield(.itemEnqueued(item))
    }
    
    // MARK: - Dequeue Methods
    
    /// Dequeues the highest priority item
    ///
    /// - Returns: The highest priority item, or nil if queue is empty
    public func dequeue() -> PrioritizedTransferItem<T>? {
        // Apply aging if enabled
        if configuration.enableAging {
            applyAging()
        }
        
        // Remove expired items
        removeExpiredItems()
        
        // Find highest priority non-empty bucket
        for priority in TransferPriority.allCases {
            if var bucket = buckets[priority], !bucket.isEmpty {
                let item = bucket.removeFirst()
                buckets[priority] = bucket
                
                // Update statistics
                totalProcessed += 1
                totalWaitTime += Date().timeIntervalSince(item.queuedAt)
                
                eventContinuation?.yield(.itemDequeued(item))
                return item
            }
        }
        
        return nil
    }
    
    /// Dequeues an item with a specific ID
    ///
    /// - Parameter id: The item ID to dequeue
    /// - Returns: The item if found, nil otherwise
    public func dequeue(id: UUID) -> PrioritizedTransferItem<T>? {
        for priority in TransferPriority.allCases {
            if var bucket = buckets[priority],
               let index = bucket.firstIndex(where: { $0.id == id }) {
                let item = bucket.remove(at: index)
                buckets[priority] = bucket
                
                totalProcessed += 1
                totalWaitTime += Date().timeIntervalSince(item.queuedAt)
                
                eventContinuation?.yield(.itemDequeued(item))
                return item
            }
        }
        return nil
    }
    
    /// Dequeues items with a specific tag
    ///
    /// - Parameters:
    ///   - tag: The tag to match
    ///   - limit: Maximum items to dequeue (nil = all)
    /// - Returns: Array of matching items
    public func dequeue(tag: String, limit: Int? = nil) -> [PrioritizedTransferItem<T>] {
        var result: [PrioritizedTransferItem<T>] = []
        let maxItems = limit ?? Int.max
        
        for priority in TransferPriority.allCases {
            if result.count >= maxItems { break }
            
            if let bucket = buckets[priority] {
                var remaining: [PrioritizedTransferItem<T>] = []
                
                for item in bucket {
                    if item.tag == tag && result.count < maxItems {
                        result.append(item)
                        totalProcessed += 1
                        totalWaitTime += Date().timeIntervalSince(item.queuedAt)
                        eventContinuation?.yield(.itemDequeued(item))
                    } else {
                        remaining.append(item)
                    }
                }
                
                buckets[priority] = remaining
            }
        }
        
        return result
    }
    
    // MARK: - Peek Methods
    
    /// Peeks at the highest priority item without removing it
    ///
    /// - Returns: The highest priority item, or nil if queue is empty
    public func peek() -> PrioritizedTransferItem<T>? {
        for priority in TransferPriority.allCases {
            if let bucket = buckets[priority], !bucket.isEmpty {
                return bucket.first
            }
        }
        return nil
    }
    
    /// Peeks at an item with a specific ID
    ///
    /// - Parameter id: The item ID to find
    /// - Returns: The item if found, nil otherwise
    public func peek(id: UUID) -> PrioritizedTransferItem<T>? {
        for priority in TransferPriority.allCases {
            if let bucket = buckets[priority],
               let item = bucket.first(where: { $0.id == id }) {
                return item
            }
        }
        return nil
    }
    
    // MARK: - Queue Management
    
    /// Total number of items in the queue
    public var totalCount: Int {
        buckets.values.reduce(0) { $0 + $1.count }
    }
    
    /// Count of items for a specific priority
    ///
    /// - Parameter priority: The priority to count
    /// - Returns: Number of items with that priority
    public func count(for priority: TransferPriority) -> Int {
        buckets[priority]?.count ?? 0
    }
    
    /// Whether the queue is empty
    public var isEmpty: Bool {
        totalCount == 0
    }
    
    /// Clears all items from the queue
    ///
    /// - Returns: Number of items cleared
    @discardableResult
    public func clear() -> Int {
        let count = totalCount
        buckets = Dictionary(uniqueKeysWithValues: TransferPriority.allCases.map { ($0, []) })
        eventContinuation?.yield(.queueCleared(itemCount: count))
        return count
    }
    
    /// Gets current statistics
    ///
    /// - Returns: Queue statistics
    public func statistics() -> TransferPriorityQueueStatistics {
        var itemsByPriority: [TransferPriority: Int] = [:]
        var oldestAge: TimeInterval?
        
        for (priority, bucket) in buckets {
            itemsByPriority[priority] = bucket.count
            
            if let first = bucket.first {
                let age = Date().timeIntervalSince(first.queuedAt)
                if oldestAge == nil || age > (oldestAge ?? 0) {
                    oldestAge = age
                }
            }
        }
        
        let averageWait = totalProcessed > 0 ? totalWaitTime / Double(totalProcessed) : 0
        
        return TransferPriorityQueueStatistics(
            itemsByPriority: itemsByPriority,
            totalItems: totalCount,
            totalProcessed: totalProcessed,
            totalDropped: totalDropped,
            totalExpired: totalExpired,
            averageWaitTime: averageWait,
            oldestItemAge: oldestAge
        )
    }
    
    // MARK: - Private Methods
    
    /// Drops the lowest priority droppable item below the given priority
    private func dropLowestPriorityDroppable(below priority: TransferPriority) -> Bool {
        // Search from lowest to highest priority
        for searchPriority in TransferPriority.allCases.reversed() {
            // Only consider items with lower priority than the incoming item
            guard searchPriority > priority else { continue }
            
            if var bucket = buckets[searchPriority] {
                // Find a droppable item
                if let index = bucket.lastIndex(where: { $0.droppable }) {
                    let dropped = bucket.remove(at: index)
                    buckets[searchPriority] = bucket
                    totalDropped += 1
                    eventContinuation?.yield(.itemDropped(dropped))
                    return true
                }
            }
        }
        return false
    }
    
    /// Removes expired items from all buckets
    private func removeExpiredItems() {
        guard configuration.maxAge != nil else { return }
        
        let now = Date()
        
        for priority in TransferPriority.allCases {
            if let bucket = buckets[priority] {
                let (valid, expired) = bucket.partition { item in
                    if item.isExpired { return false }
                    if let maxAge = configuration.maxAge {
                        return now.timeIntervalSince(item.queuedAt) < maxAge
                    }
                    return true
                }
                
                buckets[priority] = valid
                
                for item in expired {
                    totalExpired += 1
                    eventContinuation?.yield(.itemExpired(item))
                }
            }
        }
    }
    
    /// Applies aging to boost priority of waiting items
    private func applyAging() {
        let now = Date()
        
        // Process from lowest to highest priority (skip stat - can't boost higher)
        for priority in [TransferPriority.background, .low, .normal, .high] {
            guard let nextPriority = boostTarget(for: priority) else { continue }
            
            if let bucket = buckets[priority] {
                var remaining: [PrioritizedTransferItem<T>] = []
                
                for item in bucket {
                    let age = now.timeIntervalSince(item.queuedAt)
                    
                    if age >= configuration.agingInterval {
                        // Boost priority
                        let boosted = PrioritizedTransferItem(
                            data: item.data,
                            priority: nextPriority,
                            deadline: item.deadline,
                            tag: item.tag,
                            droppable: item.droppable
                        )
                        buckets[nextPriority]?.append(boosted)
                        eventContinuation?.yield(.priorityBoosted(
                            id: item.id,
                            from: priority,
                            to: nextPriority
                        ))
                    } else {
                        remaining.append(item)
                    }
                }
                
                buckets[priority] = remaining
            }
        }
    }
    
    /// Gets the next higher priority level
    private func boostTarget(for priority: TransferPriority) -> TransferPriority? {
        switch priority {
        case .stat: return nil
        case .high: return .stat
        case .normal: return .high
        case .low: return .normal
        case .background: return .low
        }
    }
}

// MARK: - Queue Errors

/// Errors that can occur with the priority queue
public enum TransferPriorityQueueError: Error, Sendable {
    /// Queue is full and cannot accept more items
    case queueFull(capacity: Int, requestedPriority: TransferPriority)
    
    /// Item not found in queue
    case itemNotFound(id: UUID)
}

extension TransferPriorityQueueError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .queueFull(let capacity, let priority):
            return "Queue is full (capacity: \(capacity)). Cannot enqueue item with priority: \(priority)"
        case .itemNotFound(let id):
            return "Item not found in queue: \(id)"
        }
    }
}

// MARK: - Array Extension

extension Array {
    /// Partitions the array into two arrays based on a predicate
    fileprivate func partition(by isIncluded: (Element) -> Bool) -> (included: [Element], excluded: [Element]) {
        var included: [Element] = []
        var excluded: [Element] = []
        
        for element in self {
            if isIncluded(element) {
                included.append(element)
            } else {
                excluded.append(element)
            }
        }
        
        return (included, excluded)
    }
}
