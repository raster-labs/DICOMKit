import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// NEMA-verified: 2026a, checked 2026-09-28 — Event Type IDs 1-5 decoded per PS3.4 2026a Table CC.2.4-1; the /ws/subscribers path and the /rs stripping are dcm4chee conventions, PS3.18 8.10.4 leaves the WebSocket URL to the origin server
// MARK: - UPSWebSocketEvent

/// A parsed UPS event received over a WebSocket channel.
///
/// The DICOMweb UPS-RS WebSocket channel (PS3.18 §8.10 Notifications) delivers events
/// as DICOM JSON messages. This struct wraps the parsed result.
public struct UPSWebSocketEvent: Sendable, Equatable {
    /// The type of event
    public let eventType: UPSEventType
    
    /// The workitem UID this event relates to
    public let workitemUID: String
    
    /// Transaction UID (if applicable)
    public let transactionUID: String?
    
    /// The raw DICOM JSON payload as serialized Data
    public let rawJSON: Data
    
    /// Timestamp when event was received by the client
    public let receivedAt: Date
    
    /// Creates a WebSocket event from parsed values
    public init(
        eventType: UPSEventType,
        workitemUID: String,
        transactionUID: String? = nil,
        rawJSON: Data = Data(),
        receivedAt: Date = Date()
    ) {
        self.eventType = eventType
        self.workitemUID = workitemUID
        self.transactionUID = transactionUID
        self.rawJSON = rawJSON
        self.receivedAt = receivedAt
    }
    
    /// Deserializes the raw JSON payload into a dictionary
    public func decodedJSON() -> [String: Any]? {
        guard !rawJSON.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: rawJSON) as? [String: Any]
    }
}

// MARK: - UPSWebSocketError

/// Errors specific to WebSocket event channel operations
public enum UPSWebSocketError: Error, Sendable, LocalizedError {
    /// WebSocket connection failed
    case connectionFailed(reason: String)
    
    /// WebSocket was disconnected unexpectedly
    case disconnected(reason: String, code: UInt16)
    
    /// Received malformed event data
    case malformedEvent(reason: String)
    
    /// The server does not support WebSocket for UPS events
    case notSupported
    
    /// Authentication failed for the WebSocket connection
    case authenticationFailed
    
    /// Connection timed out
    case connectionTimeout
    
    /// The channel has been explicitly closed
    case channelClosed
    
    /// Maximum reconnection attempts exceeded
    case maxReconnectAttemptsExceeded(attempts: Int)
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "WebSocket connection failed: \(reason)"
        case .disconnected(let reason, let code):
            return "WebSocket disconnected (code \(code)): \(reason)"
        case .malformedEvent(let reason):
            return "Malformed UPS event: \(reason)"
        case .notSupported:
            return "Server does not support WebSocket UPS event channel"
        case .authenticationFailed:
            return "WebSocket authentication failed"
        case .connectionTimeout:
            return "WebSocket connection timed out"
        case .channelClosed:
            return "WebSocket event channel has been closed"
        case .maxReconnectAttemptsExceeded(let attempts):
            return "Maximum reconnection attempts (\(attempts)) exceeded"
        }
    }
}

// MARK: - UPSWebSocketDelegate

/// Delegate protocol for receiving UPS WebSocket event notifications
public protocol UPSWebSocketDelegate: AnyObject, Sendable {
    /// Called when a UPS event is received
    func upsWebSocket(_ client: UPSWebSocketClient, didReceiveEvent event: UPSWebSocketEvent)
    
    /// Called when the WebSocket connection state changes
    func upsWebSocket(_ client: UPSWebSocketClient, didChangeState state: UPSWebSocketClient.ConnectionState)
    
    /// Called when a WebSocket error occurs
    func upsWebSocket(_ client: UPSWebSocketClient, didEncounterError error: UPSWebSocketError)
}

// MARK: - UPSWebSocketConfiguration

/// Configuration for the UPS WebSocket event channel
public struct UPSWebSocketConfiguration: Sendable {
    /// Whether to automatically reconnect on disconnect
    public let autoReconnect: Bool
    
    /// Maximum number of reconnection attempts (0 = unlimited)
    public let maxReconnectAttempts: Int
    
    /// Initial reconnection delay in seconds
    public let reconnectDelay: TimeInterval
    
    /// Maximum reconnection delay in seconds (for exponential backoff)
    public let maxReconnectDelay: TimeInterval
    
    /// Ping interval in seconds to keep the connection alive
    public let pingInterval: TimeInterval
    
    /// Connection timeout in seconds
    public let connectionTimeout: TimeInterval
    
    /// Maximum message size in bytes
    public let maxMessageSize: Int
    
    /// Creates a WebSocket configuration
    public init(
        autoReconnect: Bool = true,
        maxReconnectAttempts: Int = 10,
        reconnectDelay: TimeInterval = 1.0,
        maxReconnectDelay: TimeInterval = 60.0,
        pingInterval: TimeInterval = 30.0,
        connectionTimeout: TimeInterval = 30.0,
        maxMessageSize: Int = 1_048_576 // 1 MB
    ) {
        self.autoReconnect = autoReconnect
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectDelay = reconnectDelay
        self.maxReconnectDelay = maxReconnectDelay
        self.pingInterval = pingInterval
        self.connectionTimeout = connectionTimeout
        self.maxMessageSize = maxMessageSize
    }
    
    /// Default configuration
    public static let `default` = UPSWebSocketConfiguration()
}

// MARK: - UPSWebSocketClient

/// Client for receiving UPS event notifications over WebSocket
///
/// Implements the client side of the UPS-RS WebSocket event channel
/// as specified in DICOM PS3.18 §8.10.4 (Open Notification Connection).
///
/// After subscribing to workitem events via the REST API (UPSClient.subscribe),
/// open a WebSocket channel to receive real-time event notifications when
/// subscribed workitems change state.
///
/// ## Usage
///
/// ```swift
/// let config = try DICOMwebConfiguration(
///     baseURLString: "https://pacs.example.com/dicom-web",
///     authentication: .bearer(token: "your-token")
/// )
///
/// let wsClient = UPSWebSocketClient(configuration: config, aeTitle: "MY_AE")
///
/// // Listen via AsyncSequence
/// try await wsClient.connect()
///
/// for await event in wsClient.events {
///     switch event.eventType {
///     case .stateReport:
///         print("Workitem \(event.workitemUID) state changed")
///     case .progressReport:
///         print("Workitem \(event.workitemUID) progress updated")
///     default:
///         break
///     }
/// }
/// ```
///
/// Reference: DICOM PS3.18 §8.10.4 - Open Notification Connection Transaction
#if canImport(FoundationNetworking) || os(macOS) || os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
public final class UPSWebSocketClient: @unchecked Sendable {
    
    // MARK: - Connection State
    
    /// WebSocket connection state
    public enum ConnectionState: String, Sendable, Equatable {
        /// Not connected
        case disconnected
        
        /// Attempting to connect
        case connecting
        
        /// Connected and receiving events
        case connected
        
        /// Reconnecting after a disconnect
        case reconnecting
        
        /// Permanently closed (explicit close or max retries)
        case closed
    }
    
    // MARK: - Properties
    
    /// DICOMweb server configuration
    public let serverConfiguration: DICOMwebConfiguration
    
    /// AE Title of this subscriber
    public let aeTitle: String
    
    /// WebSocket-specific configuration
    public let wsConfiguration: UPSWebSocketConfiguration
    
    /// Current connection state
    public private(set) var connectionState: ConnectionState = .disconnected
    
    /// Delegate for event callbacks
    public weak var delegate: UPSWebSocketDelegate?
    
    /// The underlying URLSessionWebSocketTask
    private var webSocketTask: URLSessionWebSocketTask?
    
    /// URLSession for WebSocket connections
    private let urlSession: URLSession
    
    /// URL builder from server configuration
    private let urlBuilder: DICOMwebURLBuilder
    
    /// Continuation for the AsyncStream of events
    private var eventContinuation: AsyncStream<UPSWebSocketEvent>.Continuation?
    
    /// The AsyncStream of received events
    private var _events: AsyncStream<UPSWebSocketEvent>?
    
    /// Current reconnection attempt count
    private var reconnectAttempts: Int = 0
    
    /// Whether the client has been explicitly closed
    private var isClosed: Bool = false
    
    /// Ping task for keepalive
    private var pingTask: Task<Void, Never>?
    
    /// Receive task for incoming messages
    private var receiveTask: Task<Void, Never>?
    
    /// Lock for thread-safe state updates
    private let stateLock = NSLock()
    
    // MARK: - Init
    
    /// Creates a UPS WebSocket client
    ///
    /// - Parameters:
    ///   - configuration: DICOMweb server configuration (base URL, auth, etc.)
    ///   - aeTitle: The Application Entity Title for this subscriber
    ///   - wsConfiguration: WebSocket-specific configuration
    public init(
        configuration: DICOMwebConfiguration,
        aeTitle: String,
        wsConfiguration: UPSWebSocketConfiguration = .default
    ) {
        self.serverConfiguration = configuration
        self.aeTitle = aeTitle
        self.wsConfiguration = wsConfiguration
        self.urlBuilder = configuration.urlBuilder
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = wsConfiguration.connectionTimeout
        self.urlSession = URLSession(configuration: sessionConfig)
    }
    
    deinit {
        close()
    }
    
    // MARK: - Public API
    
    /// AsyncStream of UPS events received over the WebSocket channel
    ///
    /// Events are yielded as they arrive from the server. The stream ends
    /// when the connection is closed or an unrecoverable error occurs.
    public var events: AsyncStream<UPSWebSocketEvent> {
        if let existing = _events {
            return existing
        }
        
        let stream = AsyncStream<UPSWebSocketEvent> { [weak self] continuation in
            self?.eventContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                // Stream was terminated
            }
        }
        _events = stream
        return stream
    }
    
    /// Connects to the UPS WebSocket event channel
    ///
    /// Opens a WebSocket connection to the DICOMweb server's UPS event
    /// channel endpoint. After connecting, events for subscribed workitems
    /// will be delivered through the `events` AsyncStream.
    ///
    /// You must subscribe to workitem events via `UPSClient.subscribe()`
    /// before opening the event channel, or subscribe globally.
    ///
    /// Reference: PS3.18 §8.10.4 - Open Notification Connection Transaction
    ///
    /// - Throws: UPSWebSocketError if connection fails
    public func connect() async throws {
        guard !isClosed else {
            throw UPSWebSocketError.channelClosed
        }
        
        updateState(.connecting)
        reconnectAttempts = 0
        
        try await establishConnection()
    }
    
    /// Closes the WebSocket event channel
    ///
    /// Sends a close frame and terminates the connection. After closing,
    /// the `events` stream will end and no further events will be received.
    public func close() {
        stateLock.lock()
        isClosed = true
        stateLock.unlock()
        
        cancelTasks()
        
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        
        eventContinuation?.finish()
        eventContinuation = nil
        _events = nil
        
        updateState(.closed)
    }
    
    /// Disconnects without permanently closing (allows reconnect)
    public func disconnect() {
        cancelTasks()
        
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        
        updateState(.disconnected)
    }
    
    // MARK: - WebSocket URL Construction
    
    /// Builds the WebSocket URL for the UPS event channel
    ///
    /// PS3.18 §8.10.4 leaves the WebSocket URL to the origin server; dcm4chee's is built by changing
    /// the HTTP scheme to WS (or HTTPS to WSS) on the subscriber's
    /// subscription URL.
    ///
    /// Format: `ws[s]://<server>/ws/subscribers/<aeTitle>`
    internal func buildWebSocketURL() throws -> URL {
        let baseURL = serverConfiguration.baseURL
        
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw UPSWebSocketError.connectionFailed(reason: "Invalid base URL: \(baseURL)")
        }
        
        // Convert HTTP(S) scheme to WS(S) (RFC 6455)
        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        case "wss", "ws":
            break // Already WebSocket scheme
        default:
            throw UPSWebSocketError.connectionFailed(reason: "Unsupported URL scheme: \(components.scheme ?? "nil")")
        }
        
        // Build the WebSocket event channel path
        // dcm4chee convention: /ws/subscribers/{aeTitle} (not a PS3.18 template)
        // The WebSocket endpoint is a sibling of the REST endpoint, not a child.
        // For example, dcm4chee-arc uses:
        //   REST:      /dcm4chee-arc/aets/DCM4CHEE/rs
        //   WebSocket: /dcm4chee-arc/aets/DCM4CHEE/ws
        // So we strip the trailing /rs (or similar DICOMweb service suffix) before appending /ws.
        var basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let serviceSuffixes = ["/rs", "/wado-rs", "/stow-rs"]
        for suffix in serviceSuffixes {
            if basePath.lowercased().hasSuffix(suffix) {
                basePath = String(basePath.dropLast(suffix.count))
                break
            }
        }
        components.path = "\(basePath)/ws/subscribers/\(aeTitle)"
        
        guard let url = components.url else {
            throw UPSWebSocketError.connectionFailed(reason: "Failed to construct WebSocket URL")
        }
        
        return url
    }
    
    // MARK: - Connection Management
    
    /// Establishes the WebSocket connection
    private func establishConnection() async throws {
        let url = try buildWebSocketURL()
        
        var request = URLRequest(url: url)
        request.timeoutInterval = wsConfiguration.connectionTimeout
        
        // Add authentication headers
        if let auth = serverConfiguration.authentication {
            let header = auth.authorizationHeader
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        
        // NOTE: Do NOT set a custom Sec-WebSocket-Protocol header here.
        // The DICOM standard (PS3.18 §8.10.4) does not mandate a subprotocol,
        // and dcm4chee-arc rejects connections with unknown subprotocols.
        // The subscriber identity is conveyed via the AE Title in the URL path.
        
        let task = urlSession.webSocketTask(with: request)
        task.maximumMessageSize = wsConfiguration.maxMessageSize
        
        webSocketTask = task
        task.resume()
        
        // Per PS3.18 Table 11.1.1-1 the subscriber is identified by the AE Title
        // embedded in the WebSocket URL path (/ws/subscribers/{aeTitle}).
        // No additional handshake message is required or expected.
        
        updateState(.connected)
        reconnectAttempts = 0
        
        // Start receiving messages
        startReceiving()
        
        // Start ping keepalive
        startPingLoop()
    }
    
    // Subscriber identification is conveyed by the AE Title in the
    // WebSocket URL path per dcm4chee (PS3.18 §8.10.4 does not fix it).  No post-connect message
    // is sent — dcm4chee-arc (and the standard) do not define one,
    // and unexpected data frames cause a Connection reset.
    
    /// Starts the message receiving loop
    private func startReceiving() {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }
    
    /// Main receive loop — reads WebSocket messages continuously
    private func receiveLoop() async {
        while !Task.isCancelled && connectionState == .connected {
            guard let task = webSocketTask else { break }
            
            do {
                let message = try await task.receive()
                await handleMessage(message)
            } catch {
                if Task.isCancelled || isClosed { break }
                
                let wsError = mapToWebSocketError(error)
                delegate?.upsWebSocket(self, didEncounterError: wsError)
                
                // Attempt reconnection if configured
                if wsConfiguration.autoReconnect && !isClosed {
                    await attemptReconnect()
                } else {
                    updateState(.disconnected)
                    eventContinuation?.finish()
                }
                break
            }
        }
    }
    
    /// Handles an incoming WebSocket message
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        let data: Data
        
        switch message {
        case .data(let messageData):
            data = messageData
        case .string(let text):
            guard let textData = text.data(using: .utf8) else {
                let error = UPSWebSocketError.malformedEvent(reason: "Invalid UTF-8 text message")
                delegate?.upsWebSocket(self, didEncounterError: error)
                return
            }
            data = textData
        @unknown default:
            return
        }
        
        // Parse DICOM JSON event
        do {
            let event = try parseEvent(from: data)
            
            // Deliver via AsyncStream
            eventContinuation?.yield(event)
            
            // Deliver via delegate
            delegate?.upsWebSocket(self, didReceiveEvent: event)
        } catch let error as UPSWebSocketError {
            delegate?.upsWebSocket(self, didEncounterError: error)
        } catch {
            let wsError = UPSWebSocketError.malformedEvent(reason: error.localizedDescription)
            delegate?.upsWebSocket(self, didEncounterError: wsError)
        }
    }
    
    // MARK: - Event Parsing
    
    /// Parses a DICOM JSON event message from the server
    ///
    /// UPS event messages are delivered as DICOM JSON objects per PS3.18 §F.2.
    /// The event contains:
    /// - Event Type ID (00001002) or EventType attribute
    /// - Affected SOP Instance UID (00001000) — the workitem UID
    /// - Transaction UID (00081195)
    /// - Procedure Step State (00741000) for state reports
    /// - Progress information for progress reports
    ///
    /// Reference: PS3.18 §8.10.5 and PS3.4 Table CC.2.4-1
    internal func parseEvent(from data: Data) throws -> UPSWebSocketEvent {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UPSWebSocketError.malformedEvent(reason: "Invalid JSON data")
        }
        
        // Extract workitem UID
        // PS3.18: Affected SOP Instance UID (0000,1000) or workitem UID field
        let workitemUID: String
        if let element = json["00001000"] as? [String: Any],
           let values = element["Value"] as? [String],
           let uid = values.first {
            workitemUID = uid
        } else if let uid = json["workitemUID"] as? String {
            // Alternative JSON format used by some servers
            workitemUID = uid
        } else {
            throw UPSWebSocketError.malformedEvent(reason: "Missing workitem UID in event")
        }
        
        // Extract transaction UID
        let transactionUID: String?
        if let element = json["00081195"] as? [String: Any],
           let values = element["Value"] as? [String],
           let uid = values.first {
            transactionUID = uid
        } else if let uid = json["transactionUID"] as? String {
            transactionUID = uid
        } else {
            transactionUID = nil
        }
        
        // Determine event type
        let eventType = try parseEventType(from: json)
        
        // Re-serialize the parsed JSON as Data for Sendable storage
        let rawData = (try? JSONSerialization.data(withJSONObject: json, options: [])) ?? data
        
        return UPSWebSocketEvent(
            eventType: eventType,
            workitemUID: workitemUID,
            transactionUID: transactionUID,
            rawJSON: rawData,
            receivedAt: Date()
        )
    }
    
    /// Parses the event type from DICOM JSON
    ///
    /// PS3.4 Table CC.2.4-1 defines Event Type IDs:
    ///   1 = UPS State Report
    ///   2 = UPS Cancel Request
    ///   3 = UPS Progress Report
    ///   4 = SCP Status Change
    ///   5 = UPS Assigned
    /// The string-based EventType field is a DICOMKit convention, not PS3.18.
    private func parseEventType(from json: [String: Any]) throws -> UPSEventType {
        // Try DICOM Event Type ID (0000,1002). (0000,0100) is Command Field.
        if let element = json["00001002"] as? [String: Any],
           let values = element["Value"] as? [Int],
           let typeID = values.first {
            if let type = UPSEventType(eventTypeID: typeID) {
                return type
            }
        }
        
        // Try string-based EventType field (DICOMKit convention)
        if let element = json["EventType"] as? [String: Any],
           let values = element["Value"] as? [String],
           let typeString = values.first,
           let eventType = UPSEventType(rawValue: typeString) {
            return eventType
        }
        
        // Try event type from direct JSON field
        if let typeString = json["eventType"] as? String,
           let eventType = UPSEventType(rawValue: typeString) {
            return eventType
        }
        
        // Infer from content
        if let stateElement = json["00741000"] as? [String: Any],
           let _ = stateElement["Value"] as? [String] {
            // Has Procedure Step State → state report
            return .stateReport
        }
        
        if json["00741002"] != nil || json["00741004"] != nil {
            // Has Procedure Step Progress Information Sequence → progress report
            return .progressReport
        }
        
        throw UPSWebSocketError.malformedEvent(reason: "Unable to determine event type")
    }
    
    // MARK: - Reconnection
    
    /// Attempts to reconnect with exponential backoff
    private func attemptReconnect() async {
        guard !isClosed else { return }
        
        if wsConfiguration.maxReconnectAttempts > 0 &&
            reconnectAttempts >= wsConfiguration.maxReconnectAttempts {
            let error = UPSWebSocketError.maxReconnectAttemptsExceeded(attempts: reconnectAttempts)
            delegate?.upsWebSocket(self, didEncounterError: error)
            eventContinuation?.finish()
            updateState(.closed)
            return
        }
        
        reconnectAttempts += 1
        updateState(.reconnecting)
        
        // Exponential backoff: delay * 2^(attempts-1), capped at maxReconnectDelay
        let backoff = min(
            wsConfiguration.reconnectDelay * pow(2.0, Double(reconnectAttempts - 1)),
            wsConfiguration.maxReconnectDelay
        )
        
        let delayNanoseconds = UInt64(backoff * 1_000_000_000)
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        
        guard !isClosed && !Task.isCancelled else { return }
        
        do {
            try await establishConnection()
        } catch {
            // Retry again
            await attemptReconnect()
        }
    }
    
    // MARK: - Ping / Keepalive
    
    /// Starts the periodic ping loop for connection keepalive
    private func startPingLoop() {
        pingTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled && self.connectionState == .connected {
                let intervalNanos = UInt64(self.wsConfiguration.pingInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: intervalNanos)
                
                guard !Task.isCancelled && self.connectionState == .connected else { break }
                
                self.webSocketTask?.sendPing { error in
                    if let error = error {
                        let wsError = UPSWebSocketError.disconnected(
                            reason: "Ping failed: \(error.localizedDescription)",
                            code: 1001
                        )
                        self.delegate?.upsWebSocket(self, didEncounterError: wsError)
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Cancels background tasks
    private func cancelTasks() {
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
    }
    
    /// Updates the connection state and notifies the delegate
    private func updateState(_ newState: ConnectionState) {
        stateLock.lock()
        connectionState = newState
        stateLock.unlock()
        
        delegate?.upsWebSocket(self, didChangeState: newState)
    }
    
    /// Maps a generic error to a UPSWebSocketError
    private func mapToWebSocketError(_ error: Error) -> UPSWebSocketError {
        let nsError = error as NSError
        
        switch nsError.code {
        case NSURLErrorTimedOut:
            return .connectionTimeout
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return .disconnected(reason: error.localizedDescription, code: 1006)
        case NSURLErrorUserAuthenticationRequired:
            return .authenticationFailed
        default:
            return .connectionFailed(reason: error.localizedDescription)
        }
    }
}
#endif
