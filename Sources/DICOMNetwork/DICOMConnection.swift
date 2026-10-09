import Foundation

#if canImport(Network)
import Network
// NEMA-verified: 2026a, checked 2026-09-28 — PDU header read per PS3.8 2026a §9.3.1 (big-endian length); the negotiated maximum length applies to P-DATA-TF only (Annex D.1)

/// Thread-safe wrapper for continuation to handle one-shot resumption
private final class ContinuationResumeOnce<T: Sendable, E: Error>: @unchecked Sendable {
    private var resumed = false
    private var continuation: CheckedContinuation<T, E>?
    private let lock = NSLock()
    
    init(_ continuation: CheckedContinuation<T, E>) {
        self.continuation = continuation
    }
    
    var hasResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resumed
    }
    
    func resume(with result: Result<T, E>) {
        lock.lock()
        guard !resumed else {
            lock.unlock()
            return
        }
        guard let continuation = continuation else {
            lock.unlock()
            return
        }
        resumed = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

/// A throwing continuation gate that is safe when cancellation wins before the
/// continuation has been installed. Late transport callbacks are ignored, so a
/// cancel/result race can never resume the continuation twice.
private final class DeferredThrowingContinuationResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var pendingResult: Result<T, any Error>?
    private var completed = false

    /// Installs the continuation. Returns `false` when cancellation or another
    /// result already won the race and the continuation was resumed immediately.
    @discardableResult
    func install(_ continuation: CheckedContinuation<T, any Error>) -> Bool {
        lock.lock()
        if let pendingResult {
            self.pendingResult = nil
            lock.unlock()
            continuation.resume(with: pendingResult)
            return false
        }
        guard !completed else {
            lock.unlock()
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    /// Attempts to complete the operation. Returns `true` only for the winning
    /// result; all later callbacks are deliberately ignored.
    @discardableResult
    func resume(
        with result: Result<T, any Error>,
        beforeResuming: () -> Void = {}
    ) -> Bool {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return false
        }
        completed = true
        beforeResuming()
        guard let continuation else {
            pendingResult = result
            lock.unlock()
            return true
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
        return true
    }

    /// Serializes transport submission with cancellation. If cancellation won
    /// first, `operation` is not invoked. If submission won, cancellation waits
    /// until the transport has accepted the operation and then aborts it.
    @discardableResult
    func performIfIncomplete(_ operation: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        operation()
        return true
    }

    var hasCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }
}

/// Small internal transport boundary used to make cancellation deterministic and
/// to test connection races without opening a socket. It is not public API.
enum DICOMConnectionTransportState: Sendable {
    case ready
    case failed(String)
    case cancelled
    case waiting
    case other
}

protocol DICOMConnectionTransport: AnyObject, Sendable {
    func setStateUpdateHandler(_ handler: (@Sendable (DICOMConnectionTransportState) -> Void)?)
    func start()
    func send(content: Data, completion: @escaping @Sendable (String?) -> Void)
    func receive(
        minimumIncompleteLength: Int,
        maximumLength: Int,
        completion: @escaping @Sendable (Data?, Bool, String?) -> Void
    )
    func cancel()
    func forceCancel()
}

private final class NetworkFrameworkDICOMConnectionTransport: DICOMConnectionTransport,
    @unchecked Sendable
{
    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    func setStateUpdateHandler(_ handler: (@Sendable (DICOMConnectionTransportState) -> Void)?) {
        guard let handler else {
            connection.stateUpdateHandler = nil
            return
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                handler(.ready)
            case .failed(let error):
                handler(.failed(error.localizedDescription))
            case .cancelled:
                handler(.cancelled)
            case .waiting:
                handler(.waiting)
            default:
                handler(.other)
            }
        }
    }

    func start() {
        connection.start(queue: .global(qos: .userInitiated))
    }

    func send(content: Data, completion: @escaping @Sendable (String?) -> Void) {
        connection.send(
            content: content,
            completion: .contentProcessed { error in
                completion(error?.localizedDescription)
            })
    }

    func receive(
        minimumIncompleteLength: Int,
        maximumLength: Int,
        completion: @escaping @Sendable (Data?, Bool, String?) -> Void
    ) {
        connection.receive(
            minimumIncompleteLength: minimumIncompleteLength,
            maximumLength: maximumLength
        ) { data, _, isComplete, error in
            completion(data, isComplete, error?.localizedDescription)
        }
    }

    func cancel() {
        connection.cancel()
    }

    func forceCancel() {
        connection.forceCancel()
    }
}

/// DICOM network connection for managing TCP connections to DICOM services
///
/// Provides a high-level abstraction for TCP socket communication using
/// the DICOM Upper Layer Protocol.
///
/// Reference: PS3.8 Section 9 - DICOM Upper Layer Protocol
///
/// ## Usage
///
/// ```swift
/// let connection = DICOMConnection(host: "pacs.hospital.com", port: 11112)
/// try await connection.connect()
/// try await connection.send(pdu: associateRequestPDU)
/// let response = try await connection.receivePDU()
/// try await connection.disconnect()
/// ```
public final class DICOMConnection: @unchecked Sendable {
    
    /// Connection states
    public enum State: Sendable, Hashable {
        /// Connection has not been established
        case idle
        /// Connection is being established
        case connecting
        /// Connection is established and ready for communication
        case connected
        /// Connection is being closed gracefully
        case disconnecting
        /// Connection has been closed
        case disconnected
        /// Connection failed with an error
        case failed(String)
    }
    
    /// The remote host address
    public let host: String
    
    /// The remote port number (default DICOM port is 104)
    public let port: UInt16
    
    /// Maximum PDU size for receiving data
    public let maxPDUSize: UInt32
    
    /// Connection timeout in seconds
    public let timeout: TimeInterval
    
    /// The TLS configuration (nil if TLS is not enabled)
    public let tlsConfiguration: TLSConfiguration?
    
    /// The underlying transport. Production uses Network.framework; tests can
    /// inject a deterministic transport through the internal initializer.
    private let transport: any DICOMConnectionTransport
    
    /// Current state of the connection
    public private(set) var state: State = .idle
    
    /// State change continuation for async state monitoring
    private var stateHandler: ((State) -> Void)?
    
    /// Creates a new DICOM connection
    ///
    /// - Parameters:
    ///   - host: The remote host address (IP or hostname)
    ///   - port: The remote port number (default: 104)
    ///   - maxPDUSize: Maximum PDU size for receiving (default: 64 KB (`defaultMaxPDUSize`))
    ///   - timeout: Connection timeout in seconds (default: 30)
    ///   - tlsEnabled: Whether to use TLS encryption (default: false)
    @available(
        *, deprecated, message: "Use init(host:port:maxPDUSize:timeout:tlsConfiguration:) instead"
    )
    public init(
        host: String,
        port: UInt16 = dicomDefaultPort,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        timeout: TimeInterval = 30,
        tlsEnabled: Bool = false
    ) {
        self.host = host
        self.port = port
        self.maxPDUSize = maxPDUSize
        self.timeout = timeout
        self.tlsConfiguration = tlsEnabled ? .default : nil
        
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        
        let parameters: NWParameters
        if tlsEnabled {
            parameters = NWParameters(tls: .init(), tcp: .init())
        } else {
            parameters = NWParameters.tcp
        }
        
        self.transport = NetworkFrameworkDICOMConnectionTransport(
            connection: NWConnection(host: nwHost, port: nwPort, using: parameters)
        )
    }
    
    /// Creates a new DICOM connection with TLS configuration
    ///
    /// - Parameters:
    ///   - host: The remote host address (IP or hostname)
    ///   - port: The remote port number (default: 104)
    ///   - maxPDUSize: Maximum PDU size for receiving (default: 64 KB (`defaultMaxPDUSize`))
    ///   - timeout: Connection timeout in seconds (default: 30)
    ///   - tlsConfiguration: TLS configuration for secure connections (nil for plain TCP)
    /// - Throws: `TLSConfigurationError` if TLS configuration is invalid
    public init(
        host: String,
        port: UInt16 = dicomDefaultPort,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        timeout: TimeInterval = 30,
        tlsConfiguration: TLSConfiguration?
    ) throws {
        self.host = host
        self.port = port
        self.maxPDUSize = maxPDUSize
        self.timeout = timeout
        self.tlsConfiguration = tlsConfiguration
        
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        
        let parameters: NWParameters
        if let tlsConfig = tlsConfiguration {
            let tlsOptions = try tlsConfig.makeNWProtocolTLSOptions()
            parameters = NWParameters(tls: tlsOptions, tcp: .init())
        } else {
            parameters = NWParameters.tcp
        }
        
        self.transport = NetworkFrameworkDICOMConnectionTransport(
            connection: NWConnection(host: nwHost, port: nwPort, using: parameters)
        )
    }
    
    /// Internal test seam for deterministic transport cancellation tests.
    init(
        host: String,
        port: UInt16 = dicomDefaultPort,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        timeout: TimeInterval = 30,
        tlsConfiguration: TLSConfiguration? = nil,
        transport: any DICOMConnectionTransport
    ) {
        self.host = host
        self.port = port
        self.maxPDUSize = maxPDUSize
        self.timeout = timeout
        self.tlsConfiguration = tlsConfiguration
        self.transport = transport
    }

    /// Establishes the TCP connection
    ///
    /// - Throws: `DICOMNetworkError.connectionFailed` if connection cannot be established
    /// - Throws: `DICOMNetworkError.timeout` if connection times out
    public func connect() async throws {
        guard state == .idle || state == .disconnected else {
            throw DICOMNetworkError.invalidState("Cannot connect: current state is \(state)")
        }
        
        state = .connecting

        // A zero, negative, infinite, or NaN deadline has already elapsed. Do
        // not race transport startup against an immediately-expiring sleeper:
        // task scheduling could otherwise let a credential-bearing association
        // request escape before the timeout child is selected.
        guard timeout.isFinite, timeout > 0 else {
            transport.setStateUpdateHandler(nil)
            transport.forceCancel()
            state = .failed("Connection timed out")
            throw DICOMNetworkError.timeout
        }
        
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.waitForTransportReady()
                }
                group.addTask { [timeout] in
                    try await Task.sleep(for: .seconds(timeout))
                    throw DICOMNetworkError.timeout
                }
                
                defer { group.cancelAll() }
                guard try await group.next() != nil else {
                    throw DICOMNetworkError.connectionFailed("Connection operation ended unexpectedly")
                }
            }
        } catch DICOMNetworkError.timeout {
            // The ready and timeout children may finish together. Even if the
            // ready continuation already won internally, a timeout selected by
            // the task group must tear down that transport before returning.
            transport.setStateUpdateHandler(nil)
            transport.forceCancel()
            state = .failed("Connection timed out")
            throw DICOMNetworkError.timeout
        } catch is CancellationError {
            if state != .disconnected {
                transport.setStateUpdateHandler(nil)
                transport.forceCancel()
            }
            state = .disconnected
            throw CancellationError()
        } catch {
            throw error
        }
    }

    /// Waits for the transport to become ready and cooperatively tears it down
    /// when the caller or timeout race cancels this task.
    private func waitForTransportReady() async throws {
        let resumeOnce = DeferredThrowingContinuationResumeOnce<Void>()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard resumeOnce.install(continuation) else { return }

                if Task.isCancelled {
                    resumeOnce.resume(
                        with: .failure(CancellationError()),
                        beforeResuming: {
                            self.state = .disconnected
                            self.transport.setStateUpdateHandler(nil)
                            self.transport.cancel()
                        }
                    )
                    return
                }

                resumeOnce.performIfIncomplete {
                    self.transport.setStateUpdateHandler { [weak self] newState in
                        guard let self else { return }

                        switch newState {
                        case .ready:
                            resumeOnce.resume(
                                with: .success(()),
                                beforeResuming: {
                                    self.state = .connected
                                }
                            )

                        case .failed(let message):
                            let completedConnect = resumeOnce.resume(
                                with: .failure(DICOMNetworkError.connectionFailed(message)),
                                beforeResuming: {
                                    self.state = .failed(message)
                                    self.transport.setStateUpdateHandler(nil)
                                }
                            )
                            if !completedConnect, self.state == .connected {
                                self.state = .failed(message)
                                self.transport.setStateUpdateHandler(nil)
                            }

                        case .cancelled:
                            let completedConnect = resumeOnce.resume(
                                with: .failure(DICOMNetworkError.connectionClosed),
                                beforeResuming: {
                                    self.state = .disconnected
                                    self.transport.setStateUpdateHandler(nil)
                                }
                            )
                            if !completedConnect, self.state == .connected {
                                self.state = .disconnected
                                self.transport.setStateUpdateHandler(nil)
                            }

                        case .waiting:
                            // Waiting is transient (for example, the Local Network
                            // permission prompt). The timeout task remains authoritative.
                            if !resumeOnce.hasCompleted {
                                self.state = .connecting
                            }

                        case .other:
                            break
                        }
                    }
                    self.transport.start()
                }
            }
        } onCancel: {
            resumeOnce.resume(
                with: .failure(CancellationError()),
                beforeResuming: {
                    self.state = .disconnected
                    self.transport.setStateUpdateHandler(nil)
                    self.transport.cancel()
                }
            )
        }
    }
    
    /// Sends a PDU over the connection
    ///
    /// - Parameter pdu: The PDU to send
    /// - Throws: `DICOMNetworkError.connectionClosed` if connection is not established
    /// - Throws: `DICOMNetworkError.encodingFailed` if PDU encoding fails
    public func send(pdu: any PDU) async throws {
        guard state == .connected else {
            throw DICOMNetworkError.invalidState("Cannot send: connection not established")
        }
        
        let data = try pdu.encode()
        try await send(data: data)
    }
    
    /// Sends raw data over the connection
    ///
    /// - Parameter data: The data to send
    /// - Throws: `DICOMNetworkError.connectionClosed` if connection is closed
    public func send(data: Data) async throws {
        guard state == .connected else {
            throw DICOMNetworkError.invalidState("Cannot send: connection not established")
        }
        
        let resumeOnce = DeferredThrowingContinuationResumeOnce<Void>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard resumeOnce.install(continuation) else { return }

                if Task.isCancelled {
                    resumeOnce.resume(
                        with: .failure(CancellationError()),
                        beforeResuming: {
                            self.state = .disconnected
                            self.transport.setStateUpdateHandler(nil)
                            self.transport.forceCancel()
                        }
                    )
                    return
                }

                resumeOnce.performIfIncomplete {
                    self.transport.send(content: data) { errorMessage in
                        if let errorMessage {
                            resumeOnce.resume(
                                with: .failure(
                                    DICOMNetworkError.connectionFailed("Send failed: \(errorMessage)")
                                ))
                        } else {
                            resumeOnce.resume(with: .success(()))
                        }
                    }
                }
            }
        } onCancel: {
            resumeOnce.resume(
                with: .failure(CancellationError()),
                beforeResuming: {
                    self.state = .disconnected
                    self.transport.setStateUpdateHandler(nil)
                    self.transport.forceCancel()
                }
            )
        }
    }
    
    /// Receives a PDU from the connection
    ///
    /// - Returns: The received PDU
    /// - Throws: `DICOMNetworkError.connectionClosed` if connection is closed
    /// - Throws: `DICOMNetworkError.decodingFailed` if PDU decoding fails
    public func receivePDU() async throws -> any PDU {
        guard state == .connected else {
            throw DICOMNetworkError.invalidState("Cannot receive: connection not established")
        }
        
        // First, read the PDU header (6 bytes)
        let headerData = try await receive(length: 6)
        let (pduType, pduLength) = try PDUDecoder.readHeader(from: headerData)
        
        // Validate PDU length (PS3.8 Annex D.1: the limit applies to P-DATA-TF only)
        try checkPDULength(type: pduType, length: pduLength, maxPDUSize: maxPDUSize)
        
        // Read the remaining PDU data
        let bodyData = try await receive(length: Int(pduLength))
        
        // Combine header and body for decoding
        var fullPDU = headerData
        fullPDU.append(bodyData)
        
        return try PDUDecoder.decode(from: fullPDU)
    }
    
    /// Receives a specific number of bytes from the connection
    ///
    /// - Parameter length: The number of bytes to receive
    /// - Returns: The received data
    /// - Throws: `DICOMNetworkError.connectionClosed` if connection is closed
    public func receive(length: Int) async throws -> Data {
        guard state == .connected else {
            throw DICOMNetworkError.invalidState("Cannot receive: connection not established")
        }
        
        // NWConnection.receive has no read deadline, and its completion handler never
        // fires if the peer holds the socket open while sending nothing — a silent PACS
        // (one that accepts the association but never answers a DIMSE request) would block
        // this read forever. There is no ARTIM/timeout wrapper on DIMSE-response reads, so
        // bound it cooperatively instead: honor task cancellation by tearing the socket
        // down. Cancelling the NWConnection makes Network.framework deliver a terminal
        // state to the completion handler, which resumes the continuation.
        let resumeOnce = DeferredThrowingContinuationResumeOnce<Data>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard resumeOnce.install(continuation) else { return }

                // Already cancelled before the receive was even posted — bail immediately.
                if Task.isCancelled {
                    resumeOnce.resume(
                        with: .failure(CancellationError()),
                        beforeResuming: {
                            self.state = .disconnected
                            self.transport.setStateUpdateHandler(nil)
                            self.transport.cancel()
                        }
                    )
                    return
                }

                resumeOnce.performIfIncomplete {
                    self.transport.receive(
                        minimumIncompleteLength: length,
                        maximumLength: length
                    ) { data, isComplete, errorMessage in
                        if let errorMessage {
                            resumeOnce.resume(
                                with: .failure(
                                    DICOMNetworkError.connectionFailed("Receive failed: \(errorMessage)")
                                ))
                        } else if let data, data.count >= length {
                            resumeOnce.resume(with: .success(data))
                        } else if isComplete {
                            resumeOnce.resume(with: .failure(DICOMNetworkError.connectionClosed))
                        } else {
                            resumeOnce.resume(
                                with: .failure(
                                    DICOMNetworkError.decodingFailed("Incomplete data received")
                                ))
                        }
                    }
                }
            }
        } onCancel: {
            resumeOnce.resume(
                with: .failure(CancellationError()),
                beforeResuming: {
                    self.state = .disconnected
                    self.transport.setStateUpdateHandler(nil)
                    self.transport.cancel()
                }
            )
        }
    }
    
    /// Disconnects gracefully
    ///
    /// Sends any pending data before closing the connection.
    public func disconnect() async {
        guard state == .connected else {
            return
        }
        
        state = .disconnecting
        
        return await withCheckedContinuation { continuation in
            let resumeOnce = ContinuationResumeOnce(continuation)
            transport.setStateUpdateHandler { [weak self] newState in
                if case .cancelled = newState {
                    self?.state = .disconnected
                    self?.transport.setStateUpdateHandler(nil)
                    resumeOnce.resume(with: .success(()))
                }
            }
            transport.cancel()
        }
    }
    
    /// Forcefully aborts the connection
    ///
    /// Immediately closes the connection without waiting for pending data.
    public func abort() {
        transport.setStateUpdateHandler(nil)
        transport.forceCancel()
        state = .disconnected
    }
}

// MARK: - CustomStringConvertible
extension DICOMConnection: CustomStringConvertible {
    public var description: String {
        "DICOMConnection(host: \(host), port: \(port), state: \(state))"
    }
}

#endif
