import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data (in-memory subscription registry; the well-known UIDs and the PS3.4 CC.2.3-2 subscription state table are not modelled here, see the audit report)
// MARK: - Subscription

/// Represents a subscription to UPS workitem events
public struct Subscription: Sendable, Equatable, Codable {
    /// Unique identifier for this subscription
    public let subscriptionID: String
    
    /// Application Entity Title of the subscriber
    public let aeTitle: String
    
    /// Workitem UID this subscription is for (nil for global subscriptions)
    public let workitemUID: String?
    
    /// Whether this is a global subscription (subscribed to all workitems)
    public var isGlobal: Bool {
        workitemUID == nil
    }
    
    /// Deletion lock - prevents deletion of the workitem while subscribed
    public let deletionLock: Bool
    
    /// When the subscription was created
    public let createdAt: Date
    
    /// Whether the subscription is currently suspended
    public var isSuspended: Bool
    
    /// When the subscription was suspended (if applicable)
    public var suspendedAt: Date?
    
    /// Event types this subscription is interested in (nil = all events)
    public let eventTypes: Set<UPSEventType>?
    
    /// Creates a new subscription
    public init(
        subscriptionID: String = UUID().uuidString,
        aeTitle: String,
        workitemUID: String? = nil,
        deletionLock: Bool = false,
        createdAt: Date = Date(),
        isSuspended: Bool = false,
        suspendedAt: Date? = nil,
        eventTypes: Set<UPSEventType>? = nil
    ) {
        self.subscriptionID = subscriptionID
        self.aeTitle = aeTitle
        self.workitemUID = workitemUID
        self.deletionLock = deletionLock
        self.createdAt = createdAt
        self.isSuspended = isSuspended
        self.suspendedAt = suspendedAt
        self.eventTypes = eventTypes
    }
    
    /// Checks if this subscription is interested in the given event
    public func isInterestedIn(event: UPSEvent) -> Bool {
        // Check if suspended
        guard !isSuspended else { return false }
        
        // Check workitem match
        if let workitemUID = workitemUID, workitemUID != event.workitemUID {
            return false
        }
        
        // Check event type filter
        if let eventTypes = eventTypes, !eventTypes.contains(event.eventType) {
            return false
        }
        
        return true
    }
}

// MARK: - SubscriptionManager Protocol

/// Protocol for managing UPS event subscriptions
public protocol SubscriptionManager: Sendable {
    
    /// Subscribes an AE title to a specific workitem
    /// - Parameters:
    ///   - aeTitle: The Application Entity Title of the subscriber
    ///   - workitemUID: The UID of the workitem to subscribe to
    ///   - deletionLock: Whether to prevent deletion while subscribed
    ///   - eventTypes: Optional filter for specific event types (nil = all)
    /// - Returns: The created subscription
    func subscribe(
        aeTitle: String,
        workitemUID: String,
        deletionLock: Bool,
        eventTypes: Set<UPSEventType>?
    ) async throws -> Subscription
    
    /// Subscribes an AE title to all workitems (global subscription)
    /// - Parameters:
    ///   - aeTitle: The Application Entity Title of the subscriber
    ///   - deletionLock: Whether to prevent deletion while subscribed
    ///   - eventTypes: Optional filter for specific event types (nil = all)
    /// - Returns: The created subscription
    func subscribeGlobal(
        aeTitle: String,
        deletionLock: Bool,
        eventTypes: Set<UPSEventType>?
    ) async throws -> Subscription
    
    /// Unsubscribes an AE title from a specific workitem
    /// - Parameters:
    ///   - aeTitle: The Application Entity Title of the subscriber
    ///   - workitemUID: The UID of the workitem to unsubscribe from
    func unsubscribe(
        aeTitle: String,
        workitemUID: String
    ) async throws
    
    /// Unsubscribes an AE title from all workitems (global unsubscribe)
    /// - Parameter aeTitle: The Application Entity Title of the subscriber
    func unsubscribeGlobal(aeTitle: String) async throws
    
    /// Suspends a subscription
    /// - Parameters:
    ///   - aeTitle: The Application Entity Title of the subscriber
    ///   - workitemUID: The UID of the workitem subscription to suspend
    func suspendSubscription(
        aeTitle: String,
        workitemUID: String
    ) async throws
    
    /// Resumes a suspended subscription
    /// - Parameters:
    ///   - aeTitle: The Application Entity Title of the subscriber
    ///   - workitemUID: The UID of the workitem subscription to resume
    func resumeSubscription(
        aeTitle: String,
        workitemUID: String
    ) async throws
    
    /// Gets all active subscriptions for a workitem
    /// - Parameter workitemUID: The UID of the workitem
    /// - Returns: Array of active subscriptions
    func getSubscriptions(forWorkitem workitemUID: String) async throws -> [Subscription]
    
    /// Gets all active subscriptions for an AE title
    /// - Parameter aeTitle: The Application Entity Title
    /// - Returns: Array of active subscriptions
    func getSubscriptions(forAETitle aeTitle: String) async throws -> [Subscription]
    
    /// Gets all global subscriptions
    /// - Returns: Array of global subscriptions
    func getGlobalSubscriptions() async throws -> [Subscription]
    
    /// Checks if a workitem has deletion lock from any subscription
    /// - Parameter workitemUID: The UID of the workitem
    /// - Returns: True if deletion is locked
    func hasDeleteLock(forWorkitem workitemUID: String) async throws -> Bool
    
    /// Gets all subscriptions interested in an event
    /// - Parameter event: The event to check interest for
    /// - Returns: Array of subscriptions interested in the event
    func getSubscriptionsForEvent(_ event: UPSEvent) async -> [Subscription]
}

// MARK: - InMemorySubscriptionManager

/// In-memory implementation of SubscriptionManager for testing and development
public actor InMemorySubscriptionManager: SubscriptionManager {
    
    /// All subscriptions keyed by subscription ID
    private var subscriptions: [String: Subscription] = [:]
    
    /// Index: workitemUID -> [subscriptionID]
    private var workitemSubscriptions: [String: Set<String>] = [:]
    
    /// Index: aeTitle -> [subscriptionID]
    private var aeTitleSubscriptions: [String: Set<String>] = [:]
    
    /// Index: global subscriptions [subscriptionID]
    private var globalSubscriptions: Set<String> = []
    
    /// Creates an empty subscription manager
    public init() {}
    
    // MARK: - SubscriptionManager Implementation
    
    public func subscribe(
        aeTitle: String,
        workitemUID: String,
        deletionLock: Bool,
        eventTypes: Set<UPSEventType>?
    ) async throws -> Subscription {
        // Check if already subscribed
        if let existing = try await findSubscription(aeTitle: aeTitle, workitemUID: workitemUID) {
            // Return existing subscription (deletion lock can't be changed)
            return existing
        }
        
        let subscription = Subscription(
            aeTitle: aeTitle,
            workitemUID: workitemUID,
            deletionLock: deletionLock,
            eventTypes: eventTypes
        )
        
        subscriptions[subscription.subscriptionID] = subscription
        
        // Update indexes
        workitemSubscriptions[workitemUID, default: []].insert(subscription.subscriptionID)
        aeTitleSubscriptions[aeTitle, default: []].insert(subscription.subscriptionID)
        
        return subscription
    }
    
    public func subscribeGlobal(
        aeTitle: String,
        deletionLock: Bool,
        eventTypes: Set<UPSEventType>?
    ) async throws -> Subscription {
        // Check if already subscribed globally
        if let existing = try await findGlobalSubscription(aeTitle: aeTitle) {
            return existing
        }
        
        let subscription = Subscription(
            aeTitle: aeTitle,
            workitemUID: nil,
            deletionLock: deletionLock,
            eventTypes: eventTypes
        )
        
        subscriptions[subscription.subscriptionID] = subscription
        
        // Update indexes
        globalSubscriptions.insert(subscription.subscriptionID)
        aeTitleSubscriptions[aeTitle, default: []].insert(subscription.subscriptionID)
        
        return subscription
    }
    
    public func unsubscribe(
        aeTitle: String,
        workitemUID: String
    ) async throws {
        guard let subscription = try await findSubscription(aeTitle: aeTitle, workitemUID: workitemUID) else {
            // Idempotent - no error if not subscribed
            return
        }
        
        // Remove from indexes
        subscriptions.removeValue(forKey: subscription.subscriptionID)
        workitemSubscriptions[workitemUID]?.remove(subscription.subscriptionID)
        aeTitleSubscriptions[aeTitle]?.remove(subscription.subscriptionID)
    }
    
    public func unsubscribeGlobal(aeTitle: String) async throws {
        guard let subscription = try await findGlobalSubscription(aeTitle: aeTitle) else {
            // Idempotent - no error if not subscribed
            return
        }
        
        // Remove from indexes
        subscriptions.removeValue(forKey: subscription.subscriptionID)
        globalSubscriptions.remove(subscription.subscriptionID)
        aeTitleSubscriptions[aeTitle]?.remove(subscription.subscriptionID)
    }
    
    public func suspendSubscription(
        aeTitle: String,
        workitemUID: String
    ) async throws {
        guard let subscription = try await findSubscription(aeTitle: aeTitle, workitemUID: workitemUID) else {
            throw SubscriptionError.subscriptionNotFound(aeTitle: aeTitle, workitemUID: workitemUID)
        }
        
        subscriptions[subscription.subscriptionID]?.isSuspended = true
        subscriptions[subscription.subscriptionID]?.suspendedAt = Date()
    }
    
    public func resumeSubscription(
        aeTitle: String,
        workitemUID: String
    ) async throws {
        guard let subscription = try await findSubscription(aeTitle: aeTitle, workitemUID: workitemUID) else {
            throw SubscriptionError.subscriptionNotFound(aeTitle: aeTitle, workitemUID: workitemUID)
        }
        
        subscriptions[subscription.subscriptionID]?.isSuspended = false
        subscriptions[subscription.subscriptionID]?.suspendedAt = nil
    }
    
    public func getSubscriptions(forWorkitem workitemUID: String) async throws -> [Subscription] {
        guard let subIDs = workitemSubscriptions[workitemUID] else {
            return []
        }
        
        return subIDs.compactMap { subscriptions[$0] }
    }
    
    public func getSubscriptions(forAETitle aeTitle: String) async throws -> [Subscription] {
        guard let subIDs = aeTitleSubscriptions[aeTitle] else {
            return []
        }
        
        return subIDs.compactMap { subscriptions[$0] }
    }
    
    public func getGlobalSubscriptions() async throws -> [Subscription] {
        return globalSubscriptions.compactMap { subscriptions[$0] }
    }
    
    public func hasDeleteLock(forWorkitem workitemUID: String) async throws -> Bool {
        // Check workitem-specific subscriptions
        if let subIDs = workitemSubscriptions[workitemUID] {
            for subID in subIDs {
                if let sub = subscriptions[subID], sub.deletionLock {
                    return true
                }
            }
        }
        
        // Check global subscriptions
        for subID in globalSubscriptions {
            if let sub = subscriptions[subID], sub.deletionLock {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Helper Methods
    
    /// Finds a subscription by AE title and workitem UID
    private func findSubscription(aeTitle: String, workitemUID: String) async throws -> Subscription? {
        guard let subIDs = workitemSubscriptions[workitemUID] else {
            return nil
        }
        
        for subID in subIDs {
            if let sub = subscriptions[subID], sub.aeTitle == aeTitle {
                return sub
            }
        }
        
        return nil
    }
    
    /// Finds a global subscription by AE title
    private func findGlobalSubscription(aeTitle: String) async throws -> Subscription? {
        for subID in globalSubscriptions {
            if let sub = subscriptions[subID], sub.aeTitle == aeTitle {
                return sub
            }
        }
        
        return nil
    }
    
    /// Gets all subscriptions that should receive an event
    public func getSubscriptionsForEvent(_ event: UPSEvent) async -> [Subscription] {
        var interestedSubscriptions: [Subscription] = []
        
        // Check workitem-specific subscriptions
        if let subIDs = workitemSubscriptions[event.workitemUID] {
            for subID in subIDs {
                if let sub = subscriptions[subID], sub.isInterestedIn(event: event) {
                    interestedSubscriptions.append(sub)
                }
            }
        }
        
        // Check global subscriptions
        for subID in globalSubscriptions {
            if let sub = subscriptions[subID], sub.isInterestedIn(event: event) {
                interestedSubscriptions.append(sub)
            }
        }
        
        return interestedSubscriptions
    }
    
    /// Clears all subscriptions (for testing)
    public func clear() async {
        subscriptions.removeAll()
        workitemSubscriptions.removeAll()
        aeTitleSubscriptions.removeAll()
        globalSubscriptions.removeAll()
    }
    
    /// Gets all subscriptions (for testing)
    public func getAllSubscriptions() async -> [Subscription] {
        return Array(subscriptions.values)
    }
}

// MARK: - SubscriptionError

/// Errors related to subscription management
public enum SubscriptionError: Error, Sendable {
    case subscriptionNotFound(aeTitle: String, workitemUID: String)
    case globalSubscriptionNotFound(aeTitle: String)
    case invalidSubscription(reason: String)
}

extension SubscriptionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .subscriptionNotFound(let aeTitle, let workitemUID):
            return "Subscription not found for AE Title '\(aeTitle)' and workitem '\(workitemUID)'"
        case .globalSubscriptionNotFound(let aeTitle):
            return "Global subscription not found for AE Title '\(aeTitle)'"
        case .invalidSubscription(let reason):
            return "Invalid subscription: \(reason)"
        }
    }
}
