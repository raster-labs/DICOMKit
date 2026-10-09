import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (in-process event queue and dispatcher; no PS3.18 8.10 message format)
// MARK: - EventDeliveryService Protocol

/// Protocol for delivering UPS events to subscribers
///
/// Implementations provide different delivery mechanisms (WebSocket, long polling, etc.)
public protocol EventDeliveryService: Sendable {
    
    /// Delivers an event to a subscriber
    /// - Parameters:
    ///   - event: The event to deliver
    ///   - subscription: The subscription to deliver to
    /// - Throws: EventDeliveryError if delivery fails
    func deliverEvent(_ event: AnyUPSEvent, to subscription: Subscription) async throws
    
    /// Checks if the service can deliver to the given subscription
    /// - Parameter subscription: The subscription to check
    /// - Returns: True if this service can deliver to the subscription
    func canDeliver(to subscription: Subscription) -> Bool
    
    /// Starts the delivery service
    func start() async throws
    
    /// Stops the delivery service
    func stop() async throws
}

// MARK: - EventDeliveryError

/// Errors related to event delivery
public enum EventDeliveryError: Error, Sendable {
    case deliveryFailed(reason: String)
    case subscriberUnreachable(aeTitle: String)
    case invalidSubscription
    case serviceNotAvailable
    case timeout
}

extension EventDeliveryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .deliveryFailed(let reason):
            return "Event delivery failed: \(reason)"
        case .subscriberUnreachable(let aeTitle):
            return "Subscriber unreachable: \(aeTitle)"
        case .invalidSubscription:
            return "Invalid subscription"
        case .serviceNotAvailable:
            return "Event delivery service not available"
        case .timeout:
            return "Event delivery timeout"
        }
    }
}

// MARK: - EventQueue

/// Queue for managing pending events
public actor EventQueue {
    
    /// Queued event with metadata
    private struct QueuedEvent: Sendable {
        let event: AnyUPSEvent
        let subscriptions: [Subscription]
        let enqueuedAt: Date
        var deliveryAttempts: Int
        
        init(event: AnyUPSEvent, subscriptions: [Subscription]) {
            self.event = event
            self.subscriptions = subscriptions
            self.enqueuedAt = Date()
            self.deliveryAttempts = 0
        }
    }
    
    /// Pending events
    private var queue: [QueuedEvent] = []
    
    /// Maximum queue size
    private let maxQueueSize: Int
    
    /// Maximum delivery attempts
    private let maxDeliveryAttempts: Int
    
    /// Event retention time (seconds)
    private let eventRetentionTime: TimeInterval
    
    /// Creates an event queue
    /// - Parameters:
    ///   - maxQueueSize: Maximum number of events to queue (default: 1000)
    ///   - maxDeliveryAttempts: Maximum attempts to deliver an event (default: 3)
    ///   - eventRetentionTime: How long to keep events in seconds (default: 3600 = 1 hour)
    public init(
        maxQueueSize: Int = 1000,
        maxDeliveryAttempts: Int = 3,
        eventRetentionTime: TimeInterval = 3600
    ) {
        self.maxQueueSize = maxQueueSize
        self.maxDeliveryAttempts = maxDeliveryAttempts
        self.eventRetentionTime = eventRetentionTime
    }
    
    /// Enqueues an event for delivery
    /// - Parameters:
    ///   - event: The event to enqueue
    ///   - subscriptions: The subscriptions to deliver to
    public func enqueue(event: AnyUPSEvent, for subscriptions: [Subscription]) {
        guard !subscriptions.isEmpty else { return }
        
        // Remove old events if queue is full
        if queue.count >= maxQueueSize {
            queue.removeFirst()
        }
        
        let queuedEvent = QueuedEvent(event: event, subscriptions: subscriptions)
        queue.append(queuedEvent)
    }
    
    /// Dequeues the next event for delivery
    /// - Returns: The next event and its subscriptions, or nil if queue is empty
    public func dequeue() -> (event: AnyUPSEvent, subscriptions: [Subscription])? {
        guard !queue.isEmpty else { return nil }
        
        let queuedEvent = queue.removeFirst()
        return (queuedEvent.event, queuedEvent.subscriptions)
    }
    
    /// Marks an event delivery as failed and re-queues if attempts remain
    /// - Parameters:
    ///   - event: The event that failed
    ///   - subscriptions: The subscriptions that failed
    public func markDeliveryFailed(event: AnyUPSEvent, subscriptions: [Subscription]) {
        // Find if this event is already in queue
        if let index = queue.firstIndex(where: { $0.event.workitemUID == event.workitemUID && $0.event.timestamp == event.timestamp }) {
            var queuedEvent = queue[index]
            queuedEvent.deliveryAttempts += 1
            
            // Re-queue if attempts remain
            if queuedEvent.deliveryAttempts < maxDeliveryAttempts {
                queue[index] = queuedEvent
            } else {
                // Max attempts reached, remove from queue
                queue.remove(at: index)
            }
        } else {
            // First attempt, enqueue
            var queuedEvent = QueuedEvent(event: event, subscriptions: subscriptions)
            queuedEvent.deliveryAttempts = 1
            
            if queuedEvent.deliveryAttempts < maxDeliveryAttempts {
                queue.append(queuedEvent)
            }
        }
    }
    
    /// Cleans up old events
    public func cleanupOldEvents() {
        let now = Date()
        queue.removeAll { queuedEvent in
            now.timeIntervalSince(queuedEvent.enqueuedAt) > eventRetentionTime
        }
    }
    
    /// Gets the current queue size
    public func size() -> Int {
        return queue.count
    }
    
    /// Clears the queue
    public func clear() {
        queue.removeAll()
    }
}

// MARK: - CompositeEventDeliveryService

/// Composite event delivery service that tries multiple delivery mechanisms
public actor CompositeEventDeliveryService: EventDeliveryService {
    
    /// Available delivery services in priority order
    private var deliveryServices: [EventDeliveryService]
    
    /// Whether the service is running
    private var isRunning: Bool = false
    
    /// Creates a composite delivery service
    /// - Parameter deliveryServices: Available delivery services in priority order
    public init(deliveryServices: [EventDeliveryService]) {
        self.deliveryServices = deliveryServices
    }
    
    public func deliverEvent(_ event: AnyUPSEvent, to subscription: Subscription) async throws {
        guard isRunning else {
            throw EventDeliveryError.serviceNotAvailable
        }
        
        // Try each delivery service in order
        var lastError: Error?
        
        for service in deliveryServices {
            if service.canDeliver(to: subscription) {
                do {
                    try await service.deliverEvent(event, to: subscription)
                    return // Success
                } catch {
                    lastError = error
                    // Try next service
                }
            }
        }
        
        // All services failed
        if let error = lastError {
            throw error
        } else {
            throw EventDeliveryError.serviceNotAvailable
        }
    }
    
    public nonisolated func canDeliver(to subscription: Subscription) -> Bool {
        // Check if any service can deliver
        // Since this is nonisolated, we need to be careful not to access actor state
        // For now, return true optimistically - actual delivery will be attempted
        return true
    }
    
    public func start() async throws {
        for service in deliveryServices {
            try await service.start()
        }
        isRunning = true
    }
    
    public func stop() async throws {
        isRunning = false
        for service in deliveryServices {
            try await service.stop()
        }
    }
    
    /// Adds a delivery service
    public func addDeliveryService(_ service: EventDeliveryService) {
        deliveryServices.append(service)
    }
    
    /// Removes all delivery services
    public func removeAllDeliveryServices() {
        deliveryServices.removeAll()
    }
}

// MARK: - LoggingEventDeliveryService

/// Event delivery service that logs events for testing/debugging
public actor LoggingEventDeliveryService: EventDeliveryService {
    
    /// Logged events
    private(set) var deliveredEvents: [(event: AnyUPSEvent, subscription: Subscription)] = []
    
    /// Whether the service is running
    private var isRunning: Bool = false
    
    /// Maximum number of events to log
    private let maxLogSize: Int
    
    /// Creates a logging delivery service
    /// - Parameter maxLogSize: Maximum number of events to log (default: 1000)
    public init(maxLogSize: Int = 1000) {
        self.maxLogSize = maxLogSize
    }
    
    public func deliverEvent(_ event: AnyUPSEvent, to subscription: Subscription) async throws {
        guard isRunning else {
            throw EventDeliveryError.serviceNotAvailable
        }
        
        // Log the event
        if deliveredEvents.count >= maxLogSize {
            deliveredEvents.removeFirst()
        }
        deliveredEvents.append((event, subscription))
        
        // Simulate some processing time
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
    }
    
    public nonisolated func canDeliver(to subscription: Subscription) -> Bool {
        return true // Can deliver to any subscription for testing
    }
    
    public func start() async throws {
        isRunning = true
    }
    
    public func stop() async throws {
        isRunning = false
    }
    
    /// Gets all delivered events
    public func getDeliveredEvents() -> [(event: AnyUPSEvent, subscription: Subscription)] {
        return deliveredEvents
    }
    
    /// Clears the log
    public func clear() {
        deliveredEvents.removeAll()
    }
}

// MARK: - EventDispatcher

/// Coordinates event generation, queuing, and delivery
public actor EventDispatcher {
    
    /// Subscription manager
    private let subscriptionManager: SubscriptionManager
    
    /// Event delivery service
    private let deliveryService: EventDeliveryService
    
    /// Event queue
    private let eventQueue: EventQueue
    
    /// Whether the dispatcher is running
    private var isRunning: Bool = false
    
    /// Delivery task
    private var deliveryTask: Task<Void, Never>?
    
    /// Creates an event dispatcher
    /// - Parameters:
    ///   - subscriptionManager: The subscription manager
    ///   - deliveryService: The event delivery service
    ///   - eventQueue: The event queue (default: new queue)
    public init(
        subscriptionManager: SubscriptionManager,
        deliveryService: EventDeliveryService,
        eventQueue: EventQueue = EventQueue()
    ) {
        self.subscriptionManager = subscriptionManager
        self.deliveryService = deliveryService
        self.eventQueue = eventQueue
    }
    
    /// Starts the event dispatcher
    public func start() async throws {
        guard !isRunning else { return }
        
        try await deliveryService.start()
        isRunning = true
        
        // Start delivery loop
        deliveryTask = Task {
            await deliveryLoop()
        }
    }
    
    /// Stops the event dispatcher
    public func stop() async throws {
        guard isRunning else { return }
        
        isRunning = false
        deliveryTask?.cancel()
        deliveryTask = nil
        
        try await deliveryService.stop()
    }
    
    /// Dispatches an event to subscribers
    /// - Parameter event: The event to dispatch
    public func dispatch<E: UPSEvent>(_ event: E) async {
        let anyEvent = AnyUPSEvent(event)
        
        // Get interested subscriptions
        let subscriptions = await getInterestedSubscriptions(for: event)
        
        guard !subscriptions.isEmpty else { return }
        
        // Enqueue for delivery
        await eventQueue.enqueue(event: anyEvent, for: subscriptions)
    }
    
    /// Delivery loop that processes queued events
    private func deliveryLoop() async {
        while isRunning {
            // Process one event
            if let (event, subscriptions) = await eventQueue.dequeue() {
                await deliverToSubscribers(event: event, subscriptions: subscriptions)
            } else {
                // No events, sleep briefly
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            
            // Cleanup old events periodically
            await eventQueue.cleanupOldEvents()
        }
    }
    
    /// Delivers an event to all subscriptions
    private func deliverToSubscribers(event: AnyUPSEvent, subscriptions: [Subscription]) async {
        var failedSubscriptions: [Subscription] = []
        
        for subscription in subscriptions {
            do {
                try await deliveryService.deliverEvent(event, to: subscription)
            } catch {
                // Mark for retry
                failedSubscriptions.append(subscription)
            }
        }
        
        // Re-queue failed deliveries
        if !failedSubscriptions.isEmpty {
            await eventQueue.markDeliveryFailed(event: event, subscriptions: failedSubscriptions)
        }
    }
    
    /// Gets subscriptions interested in an event
    private func getInterestedSubscriptions(for event: UPSEvent) async -> [Subscription] {
        return await subscriptionManager.getSubscriptionsForEvent(event)
    }
}
