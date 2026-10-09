import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// NEMA-verified: 2026a, checked 2026-09-28 — the payload is the PS3.4 2026a Table CC.2.4-1 Event Report (Event Type ID (0000,1002) from UPSEvent) plus Affected SOP Instance UID (0000,1000); the Transaction UID is not sent (CC.2.7.3); tags checked against PS3.6 Table 6-1
// MARK: - WebSocketEventDeliveryService

/// Event delivery service that delivers UPS events via WebSocket connections
///
/// This service acts as a server-side component that pushes events to connected
/// WebSocket clients. It integrates with the `EventDispatcher` via the
/// `EventDeliveryService` protocol.
///
/// For client-side event reception, use `UPSWebSocketClient` instead.
///
/// Reference: PS3.18 §8.10.4 - Open Notification Connection Transaction
#if canImport(FoundationNetworking) || os(macOS) || os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
public actor WebSocketEventDeliveryService: EventDeliveryService {
    
    // MARK: - Types
    
    /// Represents a connected WebSocket subscriber
    private struct ConnectedSubscriber: Sendable {
        let aeTitle: String
        let sendHandler: @Sendable (Data) async throws -> Void
        let connectedAt: Date
    }
    
    // MARK: - Properties
    
    /// Connected subscribers indexed by AE Title
    private var subscribers: [String: ConnectedSubscriber] = [:]
    
    /// Whether the service is running
    private var isRunning: Bool = false
    
    /// Event delivery statistics
    private var deliveredCount: Int = 0
    private var failedCount: Int = 0
    
    // MARK: - Init
    
    public init() {}
    
    // MARK: - EventDeliveryService Protocol
    
    public func deliverEvent(_ event: AnyUPSEvent, to subscription: Subscription) async throws {
        guard isRunning else {
            throw EventDeliveryError.serviceNotAvailable
        }
        
        guard let subscriber = subscribers[subscription.aeTitle] else {
            throw EventDeliveryError.subscriberUnreachable(aeTitle: subscription.aeTitle)
        }
        
        // PS3.18 8.10.5 Send Event Report: the Event Report Information of PS3.4 Table CC.2.4-1
        // (which carries the Event Type ID (0000,1002)) plus the Affected SOP Instance UID
        // (0000,1000) that names the UPS instance (CC.2.4.3). The Transaction UID is the
        // access lock and is not sent.
        var payload = event.toDICOMJSON()
        payload["00001000"] = ["vr": "UI", "Value": [event.workitemUID]]
        
        guard let data = try? DICOMJSONWriter().data(with: payload) else {
            throw EventDeliveryError.deliveryFailed(reason: "Failed to serialize event to JSON")
        }
        
        do {
            try await subscriber.sendHandler(data)
            deliveredCount += 1
        } catch {
            failedCount += 1
            throw EventDeliveryError.deliveryFailed(reason: error.localizedDescription)
        }
    }
    
    public nonisolated func canDeliver(to subscription: Subscription) -> Bool {
        // Optimistically return true; actual delivery checks subscriber availability
        return true
    }
    
    public func start() async throws {
        isRunning = true
    }
    
    public func stop() async throws {
        isRunning = false
        subscribers.removeAll()
    }
    
    // MARK: - Subscriber Management
    
    /// Registers a connected WebSocket subscriber
    ///
    /// - Parameters:
    ///   - aeTitle: The subscriber's AE Title
    ///   - sendHandler: Closure to send data to the subscriber's WebSocket
    public func registerSubscriber(
        aeTitle: String,
        sendHandler: @escaping @Sendable (Data) async throws -> Void
    ) {
        subscribers[aeTitle] = ConnectedSubscriber(
            aeTitle: aeTitle,
            sendHandler: sendHandler,
            connectedAt: Date()
        )
    }
    
    /// Removes a connected subscriber
    /// - Parameter aeTitle: The subscriber's AE Title
    public func removeSubscriber(aeTitle: String) {
        subscribers.removeValue(forKey: aeTitle)
    }
    
    /// Returns whether a subscriber is connected
    /// - Parameter aeTitle: The subscriber's AE Title
    public func isSubscriberConnected(aeTitle: String) -> Bool {
        return subscribers[aeTitle] != nil
    }
    
    /// Gets the count of connected subscribers
    public func connectedSubscriberCount() -> Int {
        return subscribers.count
    }
    
    /// Gets delivery statistics
    public func statistics() -> (delivered: Int, failed: Int) {
        return (deliveredCount, failedCount)
    }
}
#endif

// MARK: - UPSEventChannelManager

/// Manages the complete UPS event notification lifecycle
///
/// Coordinates between subscription management, event generation, and
/// WebSocket event delivery. This is the primary entry point for applications
/// that want to both subscribe to workitem events and receive notifications.
///
/// ## Usage
///
/// ```swift
/// let config = try DICOMwebConfiguration(
///     baseURLString: "https://pacs.example.com/dicom-web",
///     authentication: .bearer(token: "token")
/// )
///
/// let manager = UPSEventChannelManager(configuration: config, aeTitle: "MY_AE")
///
/// // Subscribe and start listening
/// try await manager.subscribeToWorkitem(uid: "1.2.3.4.5")
/// try await manager.openEventChannel()
///
/// // Process events
/// for await event in manager.events {
///     print("Event: \(event.eventType) for workitem \(event.workitemUID)")
/// }
/// ```
///
/// Reference: PS3.18 §11.10 (Subscribe) and §8.10 (Notifications)
#if canImport(FoundationNetworking) || os(macOS) || os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
public final class UPSEventChannelManager: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// The UPS REST client for subscribe/unsubscribe operations
    public let upsClient: UPSClient
    
    /// The WebSocket client for event channel
    public let webSocketClient: UPSWebSocketClient
    
    /// AE Title for subscriptions
    public let aeTitle: String
    
    /// Internal actor for thread-safe mutable state
    private let state = ChannelState()
    
    /// Actor that manages mutable subscription state
    private actor ChannelState {
        var subscribedWorkitems: Set<String> = []
        var isGloballySubscribed: Bool = false
        
        func addWorkitem(_ uid: String) { subscribedWorkitems.insert(uid) }
        func removeWorkitem(_ uid: String) { subscribedWorkitems.remove(uid) }
        func setGlobal(_ value: Bool) { isGloballySubscribed = value }
        func getWorkitems() -> Set<String> { subscribedWorkitems }
        func getIsGlobal() -> Bool { isGloballySubscribed }
        func isEmpty() -> Bool { subscribedWorkitems.isEmpty && !isGloballySubscribed }
        func clear() { subscribedWorkitems.removeAll(); isGloballySubscribed = false }
    }
    
    // MARK: - Init
    
    /// Creates a UPS event channel manager
    ///
    /// - Parameters:
    ///   - configuration: DICOMweb server configuration
    ///   - aeTitle: The subscriber's AE Title
    ///   - wsConfiguration: WebSocket configuration
    ///   - maxHistorySize: Maximum number of events to retain in history
    public init(
        configuration: DICOMwebConfiguration,
        aeTitle: String,
        wsConfiguration: UPSWebSocketConfiguration = .default,
        maxHistorySize: Int = 500
    ) {
        self.upsClient = UPSClient(configuration: configuration)
        self.webSocketClient = UPSWebSocketClient(
            configuration: configuration,
            aeTitle: aeTitle,
            wsConfiguration: wsConfiguration
        )
        self.aeTitle = aeTitle
    }
    
    // MARK: - Subscription Operations
    
    /// Subscribes to events for a specific workitem and opens the event channel
    ///
    /// This performs a two-step process:
    /// 1. Sends a REST subscribe request (PS3.18 §11.10)
    /// 2. Opens the WebSocket event channel if not already open (PS3.18 §8.10.4)
    ///
    /// - Parameters:
    ///   - uid: The workitem's SOP Instance UID
    ///   - deletionLock: Whether to lock the workitem from deletion
    ///   - autoConnect: Whether to automatically open the WebSocket channel
    /// - Throws: DICOMwebError on subscription failure
    public func subscribeToWorkitem(
        uid: String,
        deletionLock: Bool = false,
        autoConnect: Bool = true
    ) async throws {
        // Step 1: REST subscribe
        try await upsClient.subscribe(uid: uid, aeTitle: aeTitle, deletionLock: deletionLock)
        
        await state.addWorkitem(uid)
        
        // Step 2: Open event channel if needed
        if autoConnect && webSocketClient.connectionState == .disconnected {
            try await openEventChannel()
        }
    }
    
    /// Subscribes globally to all workitem events
    ///
    /// - Parameters:
    ///   - deletionLock: Whether to lock workitems from deletion
    ///   - autoConnect: Whether to automatically open the WebSocket channel
    /// - Throws: DICOMwebError on subscription failure
    public func subscribeGlobally(
        deletionLock: Bool = false,
        autoConnect: Bool = true
    ) async throws {
        try await upsClient.subscribeGlobally(aeTitle: aeTitle, deletionLock: deletionLock)
        
        await state.setGlobal(true)
        
        if autoConnect && webSocketClient.connectionState == .disconnected {
            try await openEventChannel()
        }
    }
    
    /// Unsubscribes from a specific workitem
    ///
    /// - Parameter uid: The workitem's SOP Instance UID
    /// - Throws: DICOMwebError on failure
    public func unsubscribeFromWorkitem(uid: String) async throws {
        try await upsClient.unsubscribe(uid: uid, aeTitle: aeTitle)
        
        await state.removeWorkitem(uid)
        
        // Close channel if no subscriptions remain
        if await state.isEmpty() {
            closeEventChannel()
        }
    }
    
    /// Unsubscribes from global subscription
    ///
    /// - Throws: DICOMwebError on failure
    public func unsubscribeGlobally() async throws {
        try await upsClient.unsubscribeGlobally(aeTitle: aeTitle)
        
        await state.setGlobal(false)
        
        if await state.isEmpty() {
            closeEventChannel()
        }
    }
    
    // MARK: - Event Channel Operations
    
    /// Opens the WebSocket event channel
    ///
    /// - Throws: UPSWebSocketError on connection failure
    public func openEventChannel() async throws {
        try await webSocketClient.connect()
    }
    
    /// Closes the WebSocket event channel
    public func closeEventChannel() {
        webSocketClient.close()
    }
    
    /// AsyncStream of received UPS events
    ///
    /// Events from all subscribed workitems are delivered through this stream.
    public var events: AsyncStream<UPSWebSocketEvent> {
        return webSocketClient.events
    }
    
    /// Current connection state of the event channel
    public var channelState: UPSWebSocketClient.ConnectionState {
        return webSocketClient.connectionState
    }
    
    // MARK: - Query
    
    /// Returns the set of workitem UIDs currently subscribed to
    public var activeSubscriptions: Set<String> {
        get async {
            return await state.getWorkitems()
        }
    }
    
    /// Whether a global subscription is active
    public var hasGlobalSubscription: Bool {
        get async {
            return await state.getIsGlobal()
        }
    }
    
    /// Returns the total count of active subscriptions
    public var subscriptionCount: Int {
        get async {
            let workitems = await state.getWorkitems()
            let isGlobal = await state.getIsGlobal()
            return workitems.count + (isGlobal ? 1 : 0)
        }
    }
    
    // MARK: - Cleanup
    
    /// Unsubscribes from all workitems and closes the event channel
    public func closeAll() async throws {
        let workitems = await state.getWorkitems()
        let isGlobal = await state.getIsGlobal()
        
        for uid in workitems {
            try? await upsClient.unsubscribe(uid: uid, aeTitle: aeTitle)
        }
        
        if isGlobal {
            try? await upsClient.unsubscribeGlobally(aeTitle: aeTitle)
        }
        
        await state.clear()
        
        closeEventChannel()
    }
}
#endif
