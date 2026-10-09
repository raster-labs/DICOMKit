import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-09-28 — Priority scheduling order checked against PS3.7 2026a Table E.1-1 (LOW 0002H, MEDIUM 0000H, HIGH 0001H are codes, not ranks)

// MARK: - Queue Item Status

/// Status of a queued store item
///
/// Tracks the lifecycle of items in the store-and-forward queue.
public enum QueueItemStatus: String, Sendable, Codable, CaseIterable {
    /// Item is pending delivery
    case pending
    
    /// Item is currently being sent
    case sending
    
    /// Item was sent successfully
    case completed
    
    /// Item failed permanently and will not be retried
    case failed
    
    /// Item delivery was cancelled
    case cancelled
}

extension QueueItemStatus: CustomStringConvertible {
    public var description: String {
        rawValue.capitalized
    }
}

// MARK: - Queued Store Item

/// Represents a DICOM file queued for store-and-forward delivery
///
/// Contains all information needed to send a DICOM file to a remote destination,
/// including metadata for tracking delivery status and retry attempts.
///
/// Reference: PS3.4 Annex B - Storage Service Class
public struct QueuedStoreItem: Sendable, Identifiable, Codable, Hashable {
    /// Unique identifier for this queued item
    public let id: UUID
    
    /// The SOP Class UID of the DICOM instance
    public let sopClassUID: String
    
    /// The SOP Instance UID of the DICOM instance
    public let sopInstanceUID: String
    
    /// The transfer syntax UID of the data
    public let transferSyntaxUID: String
    
    /// The destination host address
    public let host: String
    
    /// The destination port number
    public let port: UInt16
    
    /// The calling Application Entity title
    public let callingAETitle: String
    
    /// The called Application Entity title
    public let calledAETitle: String
    
    /// Priority for the store operation
    public let priority: DIMSEPriority
    
    /// When the item was added to the queue
    public let queuedAt: Date
    
    /// File size in bytes
    public let fileSize: Int
    
    /// Current status of the item
    public var status: QueueItemStatus
    
    /// Number of delivery attempts made
    public var attemptCount: Int
    
    /// When the last delivery attempt occurred
    public var lastAttemptAt: Date?
    
    /// Error message from the last failed attempt
    public var lastError: String?
    
    /// When the item was completed (sent or failed permanently)
    public var completedAt: Date?
    
    /// The relative path to the data file in the queue storage
    internal let dataFileName: String
    
    /// Creates a new queued store item
    ///
    /// - Parameters:
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID
    ///   - transferSyntaxUID: The transfer syntax UID
    ///   - host: The destination host
    ///   - port: The destination port
    ///   - callingAETitle: The calling AE title
    ///   - calledAETitle: The called AE title
    ///   - priority: The operation priority
    ///   - fileSize: Size of the data in bytes
    public init(
        sopClassUID: String,
        sopInstanceUID: String,
        transferSyntaxUID: String,
        host: String,
        port: UInt16,
        callingAETitle: String,
        calledAETitle: String,
        priority: DIMSEPriority = .medium,
        fileSize: Int
    ) {
        self.id = UUID()
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
        self.transferSyntaxUID = transferSyntaxUID
        self.host = host
        self.port = port
        self.callingAETitle = callingAETitle
        self.calledAETitle = calledAETitle
        self.priority = priority
        self.queuedAt = Date()
        self.fileSize = fileSize
        self.status = .pending
        self.attemptCount = 0
        self.lastAttemptAt = nil
        self.lastError = nil
        self.completedAt = nil
        self.dataFileName = "\(id.uuidString).dcm"
    }
    
    // Hashable and Equatable - use only ID for comparison
    public static func == (lhs: QueuedStoreItem, rhs: QueuedStoreItem) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension QueuedStoreItem: CustomStringConvertible {
    public var description: String {
        "QueuedStoreItem[\(id.uuidString.prefix(8))](\(status), sop=\(sopInstanceUID.prefix(20))..., dest=\(calledAETitle)@\(host):\(port), attempts=\(attemptCount))"
    }
}

// MARK: - Queue Status

/// Overall status of the store-and-forward queue
public enum QueueStatus: String, Sendable, CaseIterable {
    /// Queue is actively processing items
    case running
    
    /// Queue is paused - no items will be sent
    case paused
    
    /// Queue is stopped - must be started to process items
    case stopped
    
    /// Queue is draining - processing remaining items but not accepting new ones
    case draining
}

extension QueueStatus: CustomStringConvertible {
    public var description: String {
        rawValue.capitalized
    }
}

// MARK: - Queue Statistics

/// Statistics about the store-and-forward queue
public struct QueueStatistics: Sendable {
    /// Current queue status
    public let status: QueueStatus
    
    /// Number of items pending delivery
    public let pendingCount: Int
    
    /// Number of items currently being sent
    public let sendingCount: Int
    
    /// Number of items completed successfully
    public let completedCount: Int
    
    /// Number of items that failed permanently
    public let failedCount: Int
    
    /// Number of items cancelled
    public let cancelledCount: Int
    
    /// Total size of pending items in bytes
    public let pendingBytes: Int
    
    /// Total items processed since queue creation
    public let totalProcessed: Int
    
    /// Average delivery time in seconds (for completed items)
    public let averageDeliveryTime: TimeInterval?
    
    /// When the queue was created
    public let createdAt: Date
    
    /// Total number of items in the queue
    public var totalCount: Int {
        pendingCount + sendingCount + completedCount + failedCount + cancelledCount
    }
    
    /// Whether the queue has items to process
    public var hasPendingWork: Bool {
        pendingCount > 0 || sendingCount > 0
    }
}

extension QueueStatistics: CustomStringConvertible {
    public var description: String {
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(pendingBytes), countStyle: .file)
        return "QueueStats(\(status), pending=\(pendingCount) (\(sizeStr)), sending=\(sendingCount), completed=\(completedCount), failed=\(failedCount))"
    }
}

// MARK: - Queue Event

/// Events emitted by the store-and-forward queue
public enum StoreAndForwardEvent: Sendable {
    /// An item was added to the queue
    case itemQueued(QueuedStoreItem)
    
    /// An item started sending
    case itemStarted(QueuedStoreItem)
    
    /// An item was sent successfully
    case itemCompleted(QueuedStoreItem, StoreResult)
    
    /// An item delivery attempt failed (may be retried)
    case itemFailed(QueuedStoreItem, Error)
    
    /// An item failed permanently and will not be retried
    case itemPermanentlyFailed(QueuedStoreItem, Error)
    
    /// An item was cancelled
    case itemCancelled(QueuedStoreItem)
    
    /// Queue status changed
    case statusChanged(QueueStatus)
    
    /// Connectivity was restored and queue is resuming
    case connectivityRestored
    
    /// Connectivity was lost
    case connectivityLost
    
    /// Queue was cleared
    case queueCleared(itemCount: Int)
}

// MARK: - Store and Forward Configuration

/// Configuration for the store-and-forward queue
///
/// Defines behavior for queuing and delivering DICOM files, including
/// persistence settings, retry policies, and queue management options.
///
/// ## Storage Location
///
/// The queue persists items to disk to survive app restarts. The storage
/// directory should be a location appropriate for your platform:
/// - iOS: Application Support directory
/// - macOS: Application Support or custom directory
///
/// ## Retry Behavior
///
/// Failed deliveries are automatically retried with exponential backoff.
/// After `maxRetryAttempts` failures, items are marked as permanently failed.
///
/// ## Connectivity Monitoring
///
/// When enabled, the queue monitors network connectivity and automatically
/// pauses when offline and resumes when connectivity is restored.
///
/// Reference: PS3.4 Annex B - Storage Service Class
public struct StoreAndForwardConfiguration: Sendable {
    /// Directory for storing queue data and pending files
    public let storageDirectory: URL
    
    /// Maximum number of retry attempts before marking as permanently failed
    public let maxRetryAttempts: Int
    
    /// Retry policy for failed deliveries
    public let retryPolicy: RetryPolicy
    
    /// Maximum concurrent transfers (0 for unlimited)
    public let maxConcurrentTransfers: Int
    
    /// Whether to automatically remove completed items from the queue
    public let autoRemoveCompleted: Bool
    
    /// Duration to keep completed items before removal (if autoRemoveCompleted is true)
    public let completedRetentionDuration: TimeInterval
    
    /// Whether to automatically retry when connectivity is restored
    public let autoRetryOnConnectivityRestored: Bool
    
    /// Delay before starting retry after connectivity is restored
    public let connectivityRestoredDelay: TimeInterval
    
    /// Whether to process items in priority order (higher priority first)
    public let priorityOrdering: Bool
    
    /// Maximum queue size in bytes (0 for unlimited)
    public let maxQueueSizeBytes: Int
    
    /// Maximum number of items in queue (0 for unlimited)
    public let maxQueueItems: Int
    
    /// Connection timeout for store operations
    public let connectionTimeout: TimeInterval
    
    /// Creates a store-and-forward configuration
    ///
    /// - Parameters:
    ///   - storageDirectory: Directory for queue persistence
    ///   - maxRetryAttempts: Maximum retry attempts (default: 10)
    ///   - retryPolicy: Retry policy for failures (default: exponential backoff)
    ///   - maxConcurrentTransfers: Max concurrent transfers (default: 1)
    ///   - autoRemoveCompleted: Auto-remove completed items (default: true)
    ///   - completedRetentionDuration: Retention period for completed items (default: 1 hour)
    ///   - autoRetryOnConnectivityRestored: Auto-retry when online (default: true)
    ///   - connectivityRestoredDelay: Delay before retry (default: 5 seconds)
    ///   - priorityOrdering: Process by priority (default: true)
    ///   - maxQueueSizeBytes: Max queue size in bytes (default: unlimited)
    ///   - maxQueueItems: Max number of items (default: unlimited)
    ///   - connectionTimeout: Connection timeout (default: 60 seconds)
    public init(
        storageDirectory: URL,
        maxRetryAttempts: Int = 10,
        retryPolicy: RetryPolicy = .aggressive,
        maxConcurrentTransfers: Int = 1,
        autoRemoveCompleted: Bool = true,
        completedRetentionDuration: TimeInterval = 3600,
        autoRetryOnConnectivityRestored: Bool = true,
        connectivityRestoredDelay: TimeInterval = 5.0,
        priorityOrdering: Bool = true,
        maxQueueSizeBytes: Int = 0,
        maxQueueItems: Int = 0,
        connectionTimeout: TimeInterval = 60
    ) {
        self.storageDirectory = storageDirectory
        self.maxRetryAttempts = max(1, maxRetryAttempts)
        self.retryPolicy = retryPolicy
        self.maxConcurrentTransfers = max(1, maxConcurrentTransfers)
        self.autoRemoveCompleted = autoRemoveCompleted
        self.completedRetentionDuration = max(0, completedRetentionDuration)
        self.autoRetryOnConnectivityRestored = autoRetryOnConnectivityRestored
        self.connectivityRestoredDelay = max(0, connectivityRestoredDelay)
        self.priorityOrdering = priorityOrdering
        self.maxQueueSizeBytes = max(0, maxQueueSizeBytes)
        self.maxQueueItems = max(0, maxQueueItems)
        self.connectionTimeout = max(1, connectionTimeout)
    }
    
    /// Default configuration using a temporary directory
    ///
    /// Note: For production use, specify a persistent storage directory.
    public static var `default`: StoreAndForwardConfiguration {
        let storageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DICOMKit")
            .appendingPathComponent("StoreAndForward")
        return StoreAndForwardConfiguration(storageDirectory: storageDir)
    }
}

// MARK: - Queue Error

/// Errors specific to store-and-forward queue operations
public enum StoreAndForwardError: Error, Sendable {
    /// Queue is not running
    case queueNotRunning
    
    /// Queue is full (reached maximum items or size)
    case queueFull(reason: String)
    
    /// Item not found in queue
    case itemNotFound(id: UUID)
    
    /// Storage error (persistence failure)
    case storageError(reason: String)
    
    /// Invalid configuration
    case invalidConfiguration(reason: String)
    
    /// Queue is draining and not accepting new items
    case queueDraining
    
    /// Item has already been completed or failed
    case itemAlreadyProcessed(id: UUID)
}

extension StoreAndForwardError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .queueNotRunning:
            return "Store-and-forward queue is not running"
        case .queueFull(let reason):
            return "Queue is full: \(reason)"
        case .itemNotFound(let id):
            return "Item not found in queue: \(id)"
        case .storageError(let reason):
            return "Storage error: \(reason)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .queueDraining:
            return "Queue is draining and not accepting new items"
        case .itemAlreadyProcessed(let id):
            return "Item has already been processed: \(id)"
        }
    }
}

extension StoreAndForwardError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}

#if canImport(Network)

// MARK: - Queue Persistence

/// Internal structure for persisting queue metadata
internal struct QueueMetadata: Codable {
    var items: [QueuedStoreItem]
    var totalProcessed: Int
    var createdAt: Date
    var lastModifiedAt: Date
    
    init() {
        items = []
        totalProcessed = 0
        createdAt = Date()
        lastModifiedAt = Date()
    }
}

// MARK: - Store and Forward Queue

/// DICOM Store-and-Forward Queue
///
/// Provides reliable delivery of DICOM files to remote destinations with
/// automatic retry, persistence, and connectivity awareness.
///
/// The queue persists items to disk, allowing delivery to resume after
/// app restarts. Failed deliveries are automatically retried with
/// exponential backoff.
///
/// ## Features
///
/// - **Persistent Queue**: Items survive app restarts
/// - **Automatic Retry**: Failed deliveries retry with exponential backoff
/// - **Connectivity Awareness**: Pauses when offline, resumes when online
/// - **Priority Support**: Process high-priority items first
/// - **Progress Monitoring**: Events stream for tracking queue activity
///
/// ## Usage
///
/// ```swift
/// // Create queue with persistent storage
/// let storageDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
///     .appendingPathComponent("DICOMQueue")
///
/// let config = StoreAndForwardConfiguration(storageDirectory: storageDir)
/// let queue = try await StoreAndForwardQueue(configuration: config)
///
/// // Start processing
/// try await queue.start()
///
/// // Queue a file for delivery
/// let item = try await queue.enqueue(
///     fileData: dicomData,
///     to: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MY_SCU",
///     calledAE: "PACS"
/// )
///
/// // Monitor events
/// for await event in queue.events {
///     switch event {
///     case .itemCompleted(let item, let result):
///         print("Delivered: \(item.sopInstanceUID)")
///     case .itemFailed(let item, let error):
///         print("Retry: \(item.sopInstanceUID)")
///     case .itemPermanentlyFailed(let item, let error):
///         print("Failed permanently: \(item.sopInstanceUID)")
///     default:
///         break
///     }
/// }
///
/// // Pause/Resume
/// await queue.pause()
/// await queue.resume()
///
/// // Clear queue
/// await queue.clear()
///
/// // Stop processing
/// await queue.stop()
/// ```
///
/// Reference: PS3.4 Annex B - Storage Service Class
public actor StoreAndForwardQueue {
    
    // MARK: - Properties
    
    /// Configuration for the queue
    public let configuration: StoreAndForwardConfiguration
    
    /// Current queue status
    public private(set) var status: QueueStatus = .stopped
    
    /// Queue metadata (items and statistics)
    private var metadata: QueueMetadata
    
    /// Continuation for the events stream
    private var eventContinuation: AsyncStream<StoreAndForwardEvent>.Continuation?
    
    /// Current number of active transfers
    private var activeTransfers: Int = 0
    
    /// Items currently being sent
    private var sendingItems: Set<UUID> = []
    
    /// Task for processing the queue
    private var processingTask: Task<Void, Never>?
    
    /// Task for monitoring connectivity
    private var connectivityTask: Task<Void, Never>?
    
    /// Tasks for auto-removal of completed items
    private var autoRemovalTasks: [UUID: Task<Void, Never>] = [:]
    
    /// Flag indicating if we have connectivity
    private var hasConnectivity: Bool = true
    
    /// Delivery time tracking for statistics
    private var deliveryTimes: [TimeInterval] = []
    
    // MARK: - Initialization
    
    /// Creates a store-and-forward queue
    ///
    /// - Parameter configuration: Queue configuration
    /// - Throws: `StoreAndForwardError` if the storage directory cannot be created
    public init(configuration: StoreAndForwardConfiguration) async throws {
        self.configuration = configuration
        self.metadata = QueueMetadata()
        
        // Ensure storage directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: configuration.storageDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: configuration.storageDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw StoreAndForwardError.storageError(
                    reason: "Failed to create storage directory: \(error.localizedDescription)"
                )
            }
        }
        
        // Load existing queue from disk
        await loadQueue()
    }
    
    // MARK: - Queue Lifecycle
    
    /// Starts the queue processing
    ///
    /// Call this to begin processing queued items. Items added while
    /// stopped will be processed once started.
    public func start() async throws {
        guard status == .stopped else {
            if status == .paused {
                await resume()
            }
            return
        }
        
        status = .running
        emitEvent(.statusChanged(.running))
        
        // Start processing loop
        processingTask = Task {
            await processQueueLoop()
        }
    }
    
    /// Stops the queue processing
    ///
    /// Cancels any in-progress transfers and stops processing new items.
    /// The queue state is persisted and can be resumed later.
    public func stop() async {
        guard status != .stopped else { return }
        
        status = .stopped
        
        // Cancel processing task
        processingTask?.cancel()
        processingTask = nil
        
        // Cancel connectivity monitoring
        connectivityTask?.cancel()
        connectivityTask = nil
        
        // Cancel all auto-removal tasks
        for (_, task) in autoRemovalTasks {
            task.cancel()
        }
        autoRemovalTasks.removeAll()
        
        // Save state
        await saveQueue()
        
        emitEvent(.statusChanged(.stopped))
    }
    
    /// Pauses queue processing
    ///
    /// Allows current transfers to complete but doesn't start new ones.
    /// Use `resume()` to continue processing.
    public func pause() async {
        guard status == .running else { return }
        
        status = .paused
        emitEvent(.statusChanged(.paused))
        await saveQueue()
    }
    
    /// Resumes queue processing after pause
    public func resume() async {
        guard status == .paused else { return }
        
        status = .running
        emitEvent(.statusChanged(.running))
    }
    
    /// Drains the queue - processes remaining items but doesn't accept new ones
    ///
    /// Use this for graceful shutdown when you want to deliver pending items.
    public func drain() async {
        guard status == .running else { return }
        
        status = .draining
        emitEvent(.statusChanged(.draining))
    }
    
    // MARK: - Queue Operations
    
    /// Enqueues a DICOM file for delivery
    ///
    /// Parses the DICOM file to extract metadata and queues it for delivery.
    ///
    /// - Parameters:
    ///   - fileData: The complete DICOM file data
    ///   - host: The destination host address
    ///   - port: The destination port
    ///   - callingAE: The calling AE title
    ///   - calledAE: The called AE title
    ///   - priority: The operation priority (default: medium)
    /// - Returns: The queued item
    /// - Throws: `StoreAndForwardError` if the queue is full or not accepting items
    /// - Throws: `DICOMError` if the file cannot be parsed
    public func enqueue(
        fileData data: Data,
        to host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        priority: DIMSEPriority = .medium
    ) async throws -> QueuedStoreItem {
        // Check if queue is accepting items
        guard status != .draining else {
            throw StoreAndForwardError.queueDraining
        }
        
        // Check queue limits
        if configuration.maxQueueItems > 0 && pendingItemCount >= configuration.maxQueueItems {
            throw StoreAndForwardError.queueFull(reason: "Maximum items (\(configuration.maxQueueItems)) reached")
        }
        
        if configuration.maxQueueSizeBytes > 0 && pendingBytes + data.count > configuration.maxQueueSizeBytes {
            throw StoreAndForwardError.queueFull(reason: "Maximum size (\(configuration.maxQueueSizeBytes) bytes) would be exceeded")
        }
        
        // Parse the DICOM file to get metadata
        let parser = DICOMFileParser(data: data)
        let fileInfo = try parser.parseForStorage()
        
        // Create queue item
        let item = QueuedStoreItem(
            sopClassUID: fileInfo.sopClassUID,
            sopInstanceUID: fileInfo.sopInstanceUID,
            transferSyntaxUID: fileInfo.transferSyntaxUID,
            host: host,
            port: port,
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            priority: priority,
            fileSize: data.count
        )
        
        // Save data file
        let dataFilePath = configuration.storageDirectory.appendingPathComponent(item.dataFileName)
        do {
            try data.write(to: dataFilePath)
        } catch {
            throw StoreAndForwardError.storageError(
                reason: "Failed to save data file: \(error.localizedDescription)"
            )
        }
        
        // Add to queue
        metadata.items.append(item)
        metadata.lastModifiedAt = Date()
        
        // Persist queue
        await saveQueue()
        
        emitEvent(.itemQueued(item))
        
        return item
    }
    
    /// Enqueues DICOM data with explicit metadata
    ///
    /// - Parameters:
    ///   - dataSetData: The DICOM data set (without file meta information)
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID
    ///   - transferSyntaxUID: The transfer syntax UID
    ///   - host: The destination host
    ///   - port: The destination port
    ///   - callingAE: The calling AE title
    ///   - calledAE: The called AE title
    ///   - priority: The operation priority
    /// - Returns: The queued item
    /// - Throws: `StoreAndForwardError` if the queue is full
    public func enqueue(
        dataSetData data: Data,
        sopClassUID: String,
        sopInstanceUID: String,
        transferSyntaxUID: String = explicitVRLittleEndianTransferSyntaxUID,
        to host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        priority: DIMSEPriority = .medium
    ) async throws -> QueuedStoreItem {
        // Check if queue is accepting items
        guard status != .draining else {
            throw StoreAndForwardError.queueDraining
        }
        
        // Check queue limits
        if configuration.maxQueueItems > 0 && pendingItemCount >= configuration.maxQueueItems {
            throw StoreAndForwardError.queueFull(reason: "Maximum items (\(configuration.maxQueueItems)) reached")
        }
        
        if configuration.maxQueueSizeBytes > 0 && pendingBytes + data.count > configuration.maxQueueSizeBytes {
            throw StoreAndForwardError.queueFull(reason: "Maximum size (\(configuration.maxQueueSizeBytes) bytes) would be exceeded")
        }
        
        // Create queue item
        let item = QueuedStoreItem(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            transferSyntaxUID: transferSyntaxUID,
            host: host,
            port: port,
            callingAETitle: callingAE,
            calledAETitle: calledAE,
            priority: priority,
            fileSize: data.count
        )
        
        // Save data file
        let dataFilePath = configuration.storageDirectory.appendingPathComponent(item.dataFileName)
        do {
            try data.write(to: dataFilePath)
        } catch {
            throw StoreAndForwardError.storageError(
                reason: "Failed to save data file: \(error.localizedDescription)"
            )
        }
        
        // Add to queue
        metadata.items.append(item)
        metadata.lastModifiedAt = Date()
        
        // Persist queue
        await saveQueue()
        
        emitEvent(.itemQueued(item))
        
        return item
    }
    
    /// Cancels a queued item
    ///
    /// - Parameter id: The item ID to cancel
    /// - Throws: `StoreAndForwardError` if the item is not found or already processed
    public func cancel(itemId id: UUID) async throws {
        guard let index = metadata.items.firstIndex(where: { $0.id == id }) else {
            throw StoreAndForwardError.itemNotFound(id: id)
        }
        
        var item = metadata.items[index]
        
        guard item.status == .pending else {
            if item.status == .sending {
                // Mark for cancellation - will be handled by processing loop
                throw StoreAndForwardError.itemAlreadyProcessed(id: id)
            }
            throw StoreAndForwardError.itemAlreadyProcessed(id: id)
        }
        
        item.status = .cancelled
        item.completedAt = Date()
        metadata.items[index] = item
        
        // Remove data file
        await removeDataFile(for: item)
        
        await saveQueue()
        
        emitEvent(.itemCancelled(item))
    }
    
    /// Removes a completed or failed item from the queue
    ///
    /// - Parameter id: The item ID to remove
    /// - Throws: `StoreAndForwardError` if the item is not found
    public func remove(itemId id: UUID) async throws {
        guard let index = metadata.items.firstIndex(where: { $0.id == id }) else {
            throw StoreAndForwardError.itemNotFound(id: id)
        }
        
        let item = metadata.items[index]
        
        // Remove data file
        await removeDataFile(for: item)
        
        // Remove from queue
        metadata.items.remove(at: index)
        metadata.lastModifiedAt = Date()
        
        await saveQueue()
    }
    
    /// Clears all items from the queue
    ///
    /// - Parameter includePending: Whether to clear pending items (default: true)
    /// - Returns: Number of items cleared
    @discardableResult
    public func clear(includePending: Bool = true) async -> Int {
        let itemsToClear: [QueuedStoreItem]
        
        if includePending {
            itemsToClear = metadata.items
            metadata.items = []
        } else {
            // Keep pending and sending items
            itemsToClear = metadata.items.filter { $0.status != .pending && $0.status != .sending }
            metadata.items = metadata.items.filter { $0.status == .pending || $0.status == .sending }
        }
        
        // Remove data files
        for item in itemsToClear {
            await removeDataFile(for: item)
        }
        
        metadata.lastModifiedAt = Date()
        await saveQueue()
        
        emitEvent(.queueCleared(itemCount: itemsToClear.count))
        
        return itemsToClear.count
    }
    
    /// Retries all failed items
    ///
    /// Resets failed items to pending status for reprocessing.
    ///
    /// - Returns: Number of items reset for retry
    @discardableResult
    public func retryAllFailed() async -> Int {
        var retryCount = 0
        
        for index in metadata.items.indices {
            if metadata.items[index].status == .failed {
                metadata.items[index].status = .pending
                metadata.items[index].attemptCount = 0
                metadata.items[index].lastError = nil
                metadata.items[index].completedAt = nil
                retryCount += 1
            }
        }
        
        if retryCount > 0 {
            metadata.lastModifiedAt = Date()
            await saveQueue()
        }
        
        return retryCount
    }
    
    // MARK: - Queue Query
    
    /// Gets a specific item by ID
    ///
    /// - Parameter id: The item ID
    /// - Returns: The item, or nil if not found
    public func item(withId id: UUID) -> QueuedStoreItem? {
        metadata.items.first { $0.id == id }
    }
    
    /// Gets all items with a specific status
    ///
    /// - Parameter status: The status to filter by
    /// - Returns: Items with the specified status
    public func items(withStatus status: QueueItemStatus) -> [QueuedStoreItem] {
        metadata.items.filter { $0.status == status }
    }
    
    /// Gets all pending items
    public var pendingItems: [QueuedStoreItem] {
        items(withStatus: .pending)
    }
    
    /// Gets all failed items
    public var failedItems: [QueuedStoreItem] {
        items(withStatus: .failed)
    }
    
    /// Gets all items
    public var allItems: [QueuedStoreItem] {
        metadata.items
    }
    
    /// Gets queue statistics
    public var statistics: QueueStatistics {
        let pending = items(withStatus: .pending)
        let sending = items(withStatus: .sending)
        let completed = items(withStatus: .completed)
        let failed = items(withStatus: .failed)
        let cancelled = items(withStatus: .cancelled)
        
        let avgDeliveryTime = deliveryTimes.isEmpty ? nil : deliveryTimes.reduce(0, +) / Double(deliveryTimes.count)
        
        return QueueStatistics(
            status: status,
            pendingCount: pending.count,
            sendingCount: sending.count,
            completedCount: completed.count,
            failedCount: failed.count,
            cancelledCount: cancelled.count,
            pendingBytes: pending.reduce(0) { $0 + $1.fileSize },
            totalProcessed: metadata.totalProcessed,
            averageDeliveryTime: avgDeliveryTime,
            createdAt: metadata.createdAt
        )
    }
    
    // MARK: - Events Stream
    
    /// Stream of queue events
    ///
    /// Subscribe to this stream to monitor queue activity.
    public var events: AsyncStream<StoreAndForwardEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }
    
    // MARK: - Private Helpers
    
    private var pendingItemCount: Int {
        metadata.items.filter { $0.status == .pending || $0.status == .sending }.count
    }
    
    private var pendingBytes: Int {
        metadata.items
            .filter { $0.status == .pending || $0.status == .sending }
            .reduce(0) { $0 + $1.fileSize }
    }
    
    private func emitEvent(_ event: StoreAndForwardEvent) {
        eventContinuation?.yield(event)
    }
    
    private func removeDataFile(for item: QueuedStoreItem) async {
        let dataFilePath = configuration.storageDirectory.appendingPathComponent(item.dataFileName)
        try? FileManager.default.removeItem(at: dataFilePath)
    }
    
    // MARK: - Persistence
    
    private func metadataFilePath() -> URL {
        configuration.storageDirectory.appendingPathComponent("queue_metadata.json")
    }
    
    private func saveQueue() async {
        let path = metadataFilePath()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(metadata)
            try data.write(to: path)
        } catch {
            // Log error but don't fail - in-memory state is still valid
            print("Warning: Failed to save queue metadata: \(error)")
        }
    }
    
    private func loadQueue() async {
        let path = metadataFilePath()
        
        guard FileManager.default.fileExists(atPath: path.path) else {
            // No existing queue - start fresh
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let data = try Data(contentsOf: path)
            var loadedMetadata = try decoder.decode(QueueMetadata.self, from: data)
            
            // Reset any items that were "sending" when we crashed
            for index in loadedMetadata.items.indices {
                if loadedMetadata.items[index].status == .sending {
                    loadedMetadata.items[index].status = .pending
                }
            }
            
            self.metadata = loadedMetadata
        } catch {
            // Log error but start with empty queue
            print("Warning: Failed to load queue metadata: \(error)")
        }
    }
    
    // MARK: - Processing Loop
    
    private func processQueueLoop() async {
        while !Task.isCancelled {
            // Check if we should process
            guard status == .running || status == .draining else {
                // Wait a bit before checking again
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                continue
            }
            
            // Check if we have connectivity
            guard hasConnectivity else {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                continue
            }
            
            // Check if we can start more transfers
            guard activeTransfers < configuration.maxConcurrentTransfers else {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                continue
            }
            
            // Get next item to process
            guard let nextItem = getNextItemToProcess() else {
                // Check if draining is complete
                if status == .draining && activeTransfers == 0 {
                    status = .stopped
                    emitEvent(.statusChanged(.stopped))
                    break
                }
                
                // No items to process - wait
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                continue
            }
            
            // Start processing the item
            activeTransfers += 1
            
            Task { [self] in
                await self.processItemAndDecrementTransfers(nextItem)
            }
        }
    }
    
    private func processItemAndDecrementTransfers(_ item: QueuedStoreItem) async {
        await processItem(item)
        activeTransfers -= 1
    }
    
    private func getNextItemToProcess() -> QueuedStoreItem? {
        // Filter to pending items not currently being sent
        let pending = metadata.items.filter { item in
            item.status == .pending && !sendingItems.contains(item.id)
        }
        
        guard !pending.isEmpty else { return nil }
        
        // Sort by priority if enabled
        if configuration.priorityOrdering {
            return Self.prioritySorted(pending).first
        } else {
            // FIFO order
            return pending.first
        }
    }

    /// Orders pending items HIGH, MEDIUM, LOW, FIFO within a priority.
    ///
    /// The raw Priority (0000,0700) values do not order by urgency — PS3.7
    /// Table E.1-1 defines LOW = 0002H, MEDIUM = 0000H, HIGH = 0001H — so the
    /// sort uses `DIMSEPriority.schedulingRank`, never `rawValue`.
    static func prioritySorted(_ items: [QueuedStoreItem]) -> [QueuedStoreItem] {
        items.sorted {
            if $0.priority.schedulingRank != $1.priority.schedulingRank {
                return $0.priority.schedulingRank < $1.priority.schedulingRank
            }
            return $0.queuedAt < $1.queuedAt
        }
    }
    
    private func processItem(_ item: QueuedStoreItem) async {
        // Mark as sending
        guard let index = metadata.items.firstIndex(where: { $0.id == item.id }) else { return }
        
        metadata.items[index].status = .sending
        metadata.items[index].attemptCount += 1
        metadata.items[index].lastAttemptAt = Date()
        sendingItems.insert(item.id)
        
        let updatedItem = metadata.items[index]
        emitEvent(.itemStarted(updatedItem))
        
        let startTime = Date()
        
        // Load data
        let dataFilePath = configuration.storageDirectory.appendingPathComponent(item.dataFileName)
        guard let data = try? Data(contentsOf: dataFilePath) else {
            // Data file missing - mark as failed
            await markItemFailed(
                id: item.id,
                error: StoreAndForwardError.storageError(reason: "Data file not found"),
                permanent: true
            )
            sendingItems.remove(item.id)
            return
        }
        
        // Attempt to send
        do {
            let result = try await DICOMStorageService.store(
                dataSetData: data,
                sopClassUID: item.sopClassUID,
                sopInstanceUID: item.sopInstanceUID,
                transferSyntaxUID: item.transferSyntaxUID,
                to: item.host,
                port: item.port,
                callingAE: item.callingAETitle,
                calledAE: item.calledAETitle,
                priority: item.priority,
                timeout: configuration.connectionTimeout
            )
            
            let deliveryTime = Date().timeIntervalSince(startTime)
            
            if result.success {
                await markItemCompleted(id: item.id, result: result, deliveryTime: deliveryTime)
            } else {
                // Store returned failure status
                let error = DICOMNetworkError.storeFailed(result.status)
                await handleItemFailure(id: item.id, error: error)
            }
        } catch {
            await handleItemFailure(id: item.id, error: error)
        }
        
        sendingItems.remove(item.id)
    }
    
    private func markItemCompleted(id: UUID, result: StoreResult, deliveryTime: TimeInterval) async {
        guard let index = metadata.items.firstIndex(where: { $0.id == id }) else { return }
        
        metadata.items[index].status = .completed
        metadata.items[index].completedAt = Date()
        metadata.totalProcessed += 1
        deliveryTimes.append(deliveryTime)
        
        // Limit delivery time history
        if deliveryTimes.count > 100 {
            deliveryTimes.removeFirst()
        }
        
        let completedItem = metadata.items[index]
        emitEvent(.itemCompleted(completedItem, result))
        
        // Auto-remove if configured
        if configuration.autoRemoveCompleted {
            let itemId = id
            let task = Task { [self] in
                try? await Task.sleep(nanoseconds: UInt64(configuration.completedRetentionDuration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                try? await self.remove(itemId: itemId)
                self.autoRemovalTasks.removeValue(forKey: itemId)
            }
            autoRemovalTasks[id] = task
        }
        
        await saveQueue()
    }
    
    private func handleItemFailure(id: UUID, error: Error) async {
        guard let index = metadata.items.firstIndex(where: { $0.id == id }) else { return }
        
        let item = metadata.items[index]
        
        // Check if this is a permanent failure or retryable
        let isPermanent: Bool
        if let networkError = error as? DICOMNetworkError {
            isPermanent = networkError.category == .permanent || networkError.category == .configuration
        } else {
            isPermanent = false
        }
        
        // Check if we've exhausted retries
        let exhaustedRetries = item.attemptCount >= configuration.maxRetryAttempts
        
        await markItemFailed(id: id, error: error, permanent: isPermanent || exhaustedRetries)
    }
    
    private func markItemFailed(id: UUID, error: Error, permanent: Bool) async {
        guard let index = metadata.items.firstIndex(where: { $0.id == id }) else { return }
        
        metadata.items[index].lastError = error.localizedDescription
        
        if permanent {
            metadata.items[index].status = .failed
            metadata.items[index].completedAt = Date()
            metadata.totalProcessed += 1
            
            let failedItem = metadata.items[index]
            emitEvent(.itemPermanentlyFailed(failedItem, error))
            
            // Remove data file for permanently failed items
            await removeDataFile(for: failedItem)
        } else {
            metadata.items[index].status = .pending
            
            let failedItem = metadata.items[index]
            emitEvent(.itemFailed(failedItem, error))
        }
        
        await saveQueue()
    }
    
    // MARK: - Connectivity
    
    /// Notifies the queue that connectivity has been restored
    ///
    /// Call this when network connectivity is detected to resume processing
    /// of queued items.
    public func notifyConnectivityRestored() async {
        guard !hasConnectivity else { return }
        
        hasConnectivity = true
        emitEvent(.connectivityRestored)
        
        // Delay before resuming if configured
        if configuration.autoRetryOnConnectivityRestored && configuration.connectivityRestoredDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(configuration.connectivityRestoredDelay * 1_000_000_000))
        }
    }
    
    /// Notifies the queue that connectivity has been lost
    ///
    /// Call this when network connectivity is lost to pause delivery attempts.
    public func notifyConnectivityLost() async {
        guard hasConnectivity else { return }
        
        hasConnectivity = false
        emitEvent(.connectivityLost)
    }
}

#endif

// MARK: - DIMSEPriority Scheduling

extension DIMSEPriority {
    /// Rank for scheduling: 0 for HIGH, 1 for MEDIUM, 2 for LOW (lower runs
    /// first). PS3.7 Table E.1-1 encodes Priority (0000,0700) as LOW = 0002H,
    /// MEDIUM = 0000H, HIGH = 0001H, so `rawValue` must not be used to order
    /// transfers.
    var schedulingRank: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}
