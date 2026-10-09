import Foundation
import DICOMCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// NEMA-verified: 2026a, checked 2026-09-28 — methods and resources diffed against PS3.18 2026a Table 11.3-1; Deletion Lock per 11.10.1-2; Transaction UID rule per PS3.4 CC.2.1.2; status handling per Tables 11.4.3-1, 11.7.3-1, 11.8.3-1
/// UPS-RS client for managing UPS workitems over HTTP
///
/// Implements the UPS-RS (Unified Procedure Step - RESTful Services)
/// specification for creating, querying, and managing workitems.
///
/// Reference: PS3.18 Section 11 - UPS-RS
///
/// ## Example Usage
///
/// ```swift
/// let config = try DICOMwebConfiguration(
///     baseURLString: "https://pacs.example.com/dicom-web",
///     authentication: .bearer(token: "your-token")
/// )
/// let client = UPSClient(configuration: config)
///
/// // Search workitems
/// let results = try await client.searchWorkitems(query: .scheduled())
///
/// // Retrieve a specific workitem
/// let workitem = try await client.retrieveWorkitem(uid: "1.2.3.4.5")
///
/// // Create a new workitem
/// let response = try await client.createWorkitem(workitem: myWorkitem)
///
/// // Change workitem state
/// let stateResponse = try await client.changeState(
///     uid: "1.2.3.4.5",
///     state: .inProgress
/// )
/// ```
#if canImport(FoundationNetworking) || os(macOS) || os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
public final class UPSClient: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// The underlying HTTP client
    public let httpClient: HTTPClient
    
    /// The configuration for this client
    public var configuration: DICOMwebConfiguration {
        return httpClient.configuration
    }
    
    /// URL builder for this client
    public var urlBuilder: DICOMwebURLBuilder {
        return configuration.urlBuilder
    }
    
    // MARK: - Initialization
    
    /// Creates a UPS client with the specified configuration
    /// - Parameter configuration: The DICOMweb configuration
    public init(configuration: DICOMwebConfiguration) {
        self.httpClient = HTTPClient(configuration: configuration)
    }
    
    /// Creates a UPS client with the specified HTTP client
    /// - Parameter httpClient: The HTTP client to use
    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }
    
    // MARK: - Search Workitems (GET /workitems)
    
    /// Searches for workitems matching the query
    ///
    /// - Parameter query: The UPS query parameters
    /// - Returns: Query results with matching workitems
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 11.9 - Search Transaction
    public func searchWorkitems(query: UPSQuery) async throws -> UPSQueryResult {
        let url = urlBuilder.searchWorkitemsURL(parameters: query.toParameters())
        
        let request = HTTPClient.Request(
            url: url,
            method: .get,
            headers: ["Accept": DICOMMediaType.dicomJSON.description]
        )
        
        let response: HTTPClient.Response
        do {
            response = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            // Re-map 404 to empty result for search
            if case .notFound = error {
                return UPSQueryResult.empty
            }
            throw error
        }
        
        // Parse JSON response
        guard let jsonArray = try? JSONSerialization.jsonObject(with: response.body) as? [[String: Any]] else {
            // Empty result
            if response.body.isEmpty || String(data: response.body, encoding: .utf8) == "[]" {
                return UPSQueryResult.empty
            }
            throw DICOMwebError.invalidJSON(reason: "Expected JSON array of workitem objects")
        }
        
        // Extract pagination info from headers
        let totalCount = response.header("X-Total-Count").flatMap { Int($0) }
        let queryParams = query.toParameters()
        let offset = queryParams["offset"].flatMap { Int($0) } ?? 0
        let limit = queryParams["limit"].flatMap { Int($0) }
        
        return UPSQueryResult.parse(
            jsonArray: jsonArray,
            totalCount: totalCount,
            offset: offset,
            limit: limit
        )
    }
    
    // MARK: - Retrieve Workitem (GET /workitems/{uid})
    
    /// Retrieves a specific workitem by its UID
    ///
    /// - Parameter uid: The workitem's SOP Instance UID
    /// - Returns: The workitem data as DICOM JSON
    /// - Throws: DICOMwebError on failure, UPSError.workitemNotFound if not found
    ///
    /// Reference: PS3.18 Section 11.5 - Retrieve Workitem Transaction
    public func retrieveWorkitem(uid: String) async throws -> [String: Any] {
        let url = urlBuilder.workitemURL(workitemUID: uid)
        
        let request = HTTPClient.Request(
            url: url,
            method: .get,
            headers: ["Accept": DICOMMediaType.dicomJSON.description]
        )
        
        let response: HTTPClient.Response
        do {
            response = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            if case .notFound = error {
                throw UPSError.workitemNotFound(uid: uid)
            }
            throw error
        }
        
        // Parse JSON response — handle both object {…} and array [{…}] formats
        let parsed = try? JSONSerialization.jsonObject(with: response.body)
        let json: [String: Any]
        if let array = parsed as? [[String: Any]], let first = array.first {
            json = first
        } else if let object = parsed as? [String: Any] {
            json = object
        } else {
            throw DICOMwebError.invalidJSON(reason: "Expected JSON object or array for workitem")
        }
        
        return json
    }
    
    /// Retrieves a specific workitem and parses it to WorkitemResult
    ///
    /// - Parameter uid: The workitem's SOP Instance UID
    /// - Returns: Parsed workitem result
    /// - Throws: DICOMwebError on failure, UPSError.workitemNotFound if not found
    public func retrieveWorkitemResult(uid: String) async throws -> WorkitemResult {
        let json = try await retrieveWorkitem(uid: uid)
        guard let result = WorkitemResult.parse(json: json, requestedUID: uid) else {
            throw DICOMwebError.invalidJSON(reason: "Failed to parse workitem JSON")
        }
        return result
    }
    
    // MARK: - Create Workitem (POST /workitems or POST /workitems?workitem={uid}, PS3.18 11.4.1)
    
    /// Creates a new workitem
    ///
    /// - Parameters:
    ///   - workitem: The workitem data as DICOM JSON
    ///   - uid: Optional specific UID to use (if nil, server will generate)
    /// - Returns: Response with the created workitem UID
    /// - Throws: DICOMwebError on failure, UPSError.workitemAlreadyExists if UID conflicts
    ///
    /// Reference: PS3.18 Section 11.4 - Create Transaction
    public func createWorkitem(
        workitem: [String: Any],
        uid: String? = nil
    ) async throws -> UPSCreateResponse {
        // Per PS3.18 §11.4: POST /workitems?workitem={uid} for client-specified UID,
        // POST /workitems for server-generated UID.
        // NOTE: POST /workitems/{uid} is the UPDATE endpoint (§11.5), not CREATE.
        let url: URL
        if let uid = uid {
            url = urlBuilder.createWorkitemURL(workitemUID: uid)
        } else {
            url = urlBuilder.workitemsURL
        }
        
        // Per PS3.18 Section 11.4 and PS3.4 Table CC.2.5-3, enforce attributes
        // for UPS-RS Create request body
        var filteredWorkitem = workitem
        filteredWorkitem.removeValue(forKey: UPSTag.sopInstanceUID)       // (0008,0018) in URL
        // Procedure Step State (0074,1000) MUST be SCHEDULED for N-CREATE per PS3.4 CC.2.5-3
        filteredWorkitem[UPSTag.procedureStepState] = ["vr": "CS", "Value": ["SCHEDULED"]]
        
        // Serialize workitem to JSON
        let body = try JSONSerialization.data(withJSONObject: filteredWorkitem)
        
        let request = HTTPClient.Request(
            url: url,
            method: .post,
            headers: [
                "Content-Type": DICOMMediaType.dicomJSON.description,
                "Accept": DICOMMediaType.dicomJSON.description
            ],
            body: body
        )
        
        let response: HTTPClient.Response
        do {
            response = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            if case .httpError(let statusCode, _) = error, statusCode == 409 {
                let existingUID = uid ?? "unknown"
                throw UPSError.workitemAlreadyExists(uid: existingUID)
            }
            throw error
        }
        
        // Extract workitem UID from Location header or response
        let locationHeader = response.header("Location")
        let workitemUID = extractWorkitemUID(from: locationHeader) ?? uid ?? ""
        
        // Check for warnings
        let warnings = extractWarnings(from: response)
        
        return UPSCreateResponse(
            workitemUID: workitemUID,
            retrieveURL: locationHeader,
            warnings: warnings
        )
    }
    
    /// Creates a new workitem from a Workitem struct
    ///
    /// - Parameters:
    ///   - workitem: The workitem to create
    /// - Returns: Response with the created workitem UID
    /// - Throws: DICOMwebError on failure
    public func createWorkitem(_ workitem: Workitem) async throws -> UPSCreateResponse {
        let json = workitem.toDICOMJSONForCreate()
        return try await createWorkitem(workitem: json, uid: workitem.workitemUID)
    }
    
    // MARK: - Update Workitem (POST /workitems/{uid}?00081195={transactionUID})
    
    /// Updates an existing workitem
    ///
    /// Per PS3.18 §11.6, the Update Workitem Transaction uses **POST** (not PUT)
    /// with the Transaction UID conveyed as a query parameter.
    ///
    /// - Parameters:
    ///   - uid: The workitem's SOP Instance UID
    ///   - updates: The updates to apply as DICOM JSON
    ///   - transactionUID: Transaction UID of the claimed workitem (required when workitem is IN PROGRESS)
    /// - Throws: DICOMwebError on failure, UPSError.workitemNotFound if not found
    ///
    /// Reference: PS3.18 Section 11.6 - Update Workitem Transaction
    public func updateWorkitem(uid: String, updates: [String: Any], transactionUID: String? = nil) async throws {
        let url: URL
        if let txUID = transactionUID {
            url = urlBuilder.updateWorkitemURL(workitemUID: uid, transactionUID: txUID)
        } else {
            url = urlBuilder.workitemURL(workitemUID: uid)
        }
        
        // Serialize updates to JSON
        let body = try JSONSerialization.data(withJSONObject: updates)
        
        let request = HTTPClient.Request(
            url: url,
            method: .post,
            headers: ["Content-Type": DICOMMediaType.dicomJSON.description],
            body: body
        )
        
        do {
            _ = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            if case .notFound = error {
                throw UPSError.workitemNotFound(uid: uid)
            }
            throw error
        }
    }
    
    // MARK: - Change State (PUT /workitems/{uid}/state)
    
    /// Changes the state of a workitem
    ///
    /// - Parameters:
    ///   - uid: The workitem's SOP Instance UID
    ///   - state: The target state
    ///   - transactionUID: Transaction UID (required when completing/canceling from IN PROGRESS)
    /// - Returns: Response with the new state and transaction UID if applicable
    /// - Throws: DICOMwebError on failure, UPSError for invalid state transitions
    ///
    /// Reference: PS3.18 Section 11.7 - Change Workitem State Transaction
    public func changeState(
        uid: String,
        state: UPSState,
        transactionUID: String? = nil
    ) async throws -> UPSStateChangeResponse {
        // Per PS3.18 §11.7, Transaction UID for state change goes in the
        // request body only — NOT as a URL query parameter.
        let url = urlBuilder.workitemStateURL(workitemUID: uid)
        
        // PS3.4 CC.2.1.2: to claim a SCHEDULED UPS the SCU generates the Transaction UID and
        // sends it with the change to IN PROGRESS; PS3.18 11.7.1.4: the payload shall include it
        let transactionUID = transactionUID ?? (state == .inProgress ? UIDGenerator.generateUID().value : nil)
        
        // Build state change JSON
        let stateChangeJSON = buildStateChangeJSON(state: state, transactionUID: transactionUID)
        let body = try JSONSerialization.data(withJSONObject: stateChangeJSON)
        
        let request = HTTPClient.Request(
            url: url,
            method: .put,
            headers: [
                "Content-Type": DICOMMediaType.dicomJSON.description,
                "Accept": DICOMMediaType.dicomJSON.description
            ],
            body: body
        )
        
        let response: HTTPClient.Response
        do {
            response = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            if case .notFound = error {
                throw UPSError.workitemNotFound(uid: uid)
            }
            if case .httpError(let statusCode, let message) = error, statusCode == 409 {
                // Could be invalid state transition or transaction UID mismatch
                if let message = message, message.lowercased().contains("transaction") {
                    throw UPSError.transactionUIDMismatch
                }
            }
            throw error
        }
        
        // Parse response to get transaction UID if transitioning to IN PROGRESS
        var responseTransactionUID: String? = nil
        if state == .inProgress, !response.body.isEmpty {
            if let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] {
                responseTransactionUID = extractTransactionUID(from: json)
            }
        }
        
        // Check for warnings
        let warnings = extractWarnings(from: response)
        
        return UPSStateChangeResponse(
            workitemUID: uid,
            newState: state,
            transactionUID: responseTransactionUID ?? transactionUID,
            warnings: warnings
        )
    }
    
    // MARK: - Request Cancellation (POST /workitems/{uid}/cancelrequest, PS3.18 11.8.1)
    
    /// Requests cancellation of a workitem
    ///
    /// - Parameters:
    ///   - uid: The workitem's SOP Instance UID
    ///   - reason: Optional reason for cancellation
    ///   - contactDisplayName: Optional contact display name
    ///   - contactURI: Optional contact URI
    /// - Returns: Response indicating if cancellation was accepted
    /// - Throws: DICOMwebError on failure, UPSError.workitemNotFound if not found
    ///
    /// Reference: PS3.18 Section 11.8 - Request Cancellation Transaction
    public func requestCancellation(
        uid: String,
        reason: String? = nil,
        contactDisplayName: String? = nil,
        contactURI: String? = nil
    ) async throws -> UPSCancellationResponse {
        let url = urlBuilder.workitemCancelRequestURL(workitemUID: uid)
        
        // Build cancellation request JSON
        let cancellationJSON = buildCancellationJSON(
            reason: reason,
            contactDisplayName: contactDisplayName,
            contactURI: contactURI
        )
        let body = try JSONSerialization.data(withJSONObject: cancellationJSON)
        
        // PS3.18 Table 11.3-1 / 11.8.1: POST /workitems/{workitem}/cancelrequest
        let request = HTTPClient.Request(
            url: url,
            method: .post,
            headers: [
                "Content-Type": DICOMMediaType.dicomJSON.description,
                "Accept": DICOMMediaType.dicomJSON.description
            ],
            body: body
        )
        
        let response: HTTPClient.Response
        var rejectionReason: String? = nil
        var accepted = false
        
        do {
            response = try await httpClient.execute(request)
            // 2xx means cancellation was accepted
            accepted = true
        } catch let error as DICOMwebError {
            if case .notFound = error {
                throw UPSError.workitemNotFound(uid: uid)
            }
            if case .httpError(let statusCode, let message) = error, statusCode == 409 {
                // 409 Conflict means cancellation was rejected
                rejectionReason = message
                response = HTTPClient.Response(
                    statusCode: statusCode,
                    headers: [:],
                    body: Data()
                )
            } else {
                throw error
            }
        }
        
        // Check for warnings
        let warnings = extractWarnings(from: response)
        
        return UPSCancellationResponse(
            workitemUID: uid,
            accepted: accepted,
            rejectionReason: rejectionReason,
            warnings: warnings
        )
    }
    
    /// Requests cancellation using a cancellation request struct
    ///
    /// - Parameter cancellationRequest: The cancellation request
    /// - Returns: Response indicating if cancellation was accepted
    /// - Throws: DICOMwebError on failure
    public func requestCancellation(_ cancellationRequest: UPSCancellationRequest) async throws -> UPSCancellationResponse {
        return try await requestCancellation(
            uid: cancellationRequest.workitemUID,
            reason: cancellationRequest.reason,
            contactDisplayName: cancellationRequest.contactDisplayName,
            contactURI: cancellationRequest.contactURI
        )
    }
    
    // MARK: - Subscribe (POST /workitems/{uid}/subscribers/{aeTitle})
    
    /// Subscribes to workitem events
    ///
    /// - Parameters:
    ///   - uid: The workitem's SOP Instance UID (or nil for global subscription)
    ///   - aeTitle: The subscribing AE Title
    ///   - deletionLock: Whether to lock the workitem from deletion while subscribed
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 11.10 - Subscribe Transaction
    public func subscribe(
        uid: String?,
        aeTitle: String,
        deletionLock: Bool = false
    ) async throws {
        var url: URL
        if let uid = uid {
            url = urlBuilder.workitemSubscriptionURL(workitemUID: uid, aeTitle: aeTitle)
        } else {
            url = urlBuilder.globalWorkitemSubscriptionURL(aeTitle: aeTitle)
        }
        
        // PS3.18 11.10.1.2: the Deletion Lock is the query parameter deletionlock=true
        if deletionLock {
            url = DICOMwebURLBuilder.appendQueryParameters(
                to: url, parameters: [DICOMwebURLBuilder.QueryParameter.deletionlock: "true"])
        }
        
        let request = HTTPClient.Request(
            url: url,
            method: .post,
            headers: [:]
        )
        
        do {
            _ = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            if case .notFound = error {
                if let uid = uid {
                    throw UPSError.workitemNotFound(uid: uid)
                }
            }
            throw error
        }
    }
    
    /// Subscribes globally to all workitem events
    ///
    /// - Parameters:
    ///   - aeTitle: The subscribing AE Title
    ///   - deletionLock: Whether to lock workitems from deletion while subscribed
    /// - Throws: DICOMwebError on failure
    public func subscribeGlobally(aeTitle: String, deletionLock: Bool = false) async throws {
        try await subscribe(uid: nil, aeTitle: aeTitle, deletionLock: deletionLock)
    }
    
    // MARK: - Unsubscribe (DELETE /workitems/{uid}/subscribers/{aeTitle})
    
    /// Unsubscribes from workitem events
    ///
    /// - Parameters:
    ///   - uid: The workitem's SOP Instance UID (or nil for global subscription)
    ///   - aeTitle: The subscribing AE Title
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 11.11 - Unsubscribe Transaction
    public func unsubscribe(uid: String?, aeTitle: String) async throws {
        let url: URL
        if let uid = uid {
            url = urlBuilder.workitemSubscriptionURL(workitemUID: uid, aeTitle: aeTitle)
        } else {
            url = urlBuilder.globalWorkitemSubscriptionURL(aeTitle: aeTitle)
        }
        
        let request = HTTPClient.Request(
            url: url,
            method: .delete,
            headers: [:]
        )
        
        do {
            _ = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            // Subscription may not exist, but that's okay for unsubscribe
            if case .notFound = error {
                return
            }
            throw error
        }
    }
    
    /// Unsubscribes from global workitem events
    ///
    /// - Parameter aeTitle: The subscribing AE Title
    /// - Throws: DICOMwebError on failure
    public func unsubscribeGlobally(aeTitle: String) async throws {
        try await unsubscribe(uid: nil, aeTitle: aeTitle)
    }
    
    // MARK: - Suspend Subscription (POST /workitems/{uid}/subscribers/{aeTitle}/suspend)
    
    /// Suspends a workitem subscription
    ///
    /// - Parameters:
    ///   - uid: The workitem's SOP Instance UID
    ///   - aeTitle: The subscribing AE Title
    /// - Throws: DICOMwebError on failure
    ///
    /// Reference: PS3.18 Section 11.12 - Suspend Global Subscription Transaction
    public func suspendSubscription(uid: String, aeTitle: String) async throws {
        let url = urlBuilder.workitemSubscriptionSuspendURL(workitemUID: uid, aeTitle: aeTitle)
        
        let request = HTTPClient.Request(
            url: url,
            method: .post,
            headers: [:]
        )
        
        do {
            _ = try await httpClient.execute(request)
        } catch let error as DICOMwebError {
            if case .notFound = error {
                throw UPSError.workitemNotFound(uid: uid)
            }
            throw error
        }
    }
    
    // MARK: - Event Channel (PS3.18 §11.11)
    
    /// Creates a WebSocket event channel manager for receiving UPS event notifications
    ///
    /// The event channel manager handles both subscription management and
    /// WebSocket event delivery. Subscribe to workitems via the manager,
    /// then listen for events through the AsyncStream.
    ///
    /// ```swift
    /// let manager = upsClient.createEventChannelManager(aeTitle: "MY_AE")
    /// try await manager.subscribeToWorkitem(uid: "1.2.3.4.5")
    /// for await event in manager.events {
    ///     print("State changed: \(event.eventType)")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - aeTitle: The subscriber's AE Title
    ///   - wsConfiguration: WebSocket configuration (auto-reconnect, timeouts, etc.)
    /// - Returns: A configured `UPSEventChannelManager`
    ///
    /// Reference: PS3.18 §8.10.4 - Open Notification Connection Transaction
    public func createEventChannelManager(
        aeTitle: String,
        wsConfiguration: UPSWebSocketConfiguration = .default
    ) -> UPSEventChannelManager {
        return UPSEventChannelManager(
            configuration: configuration,
            aeTitle: aeTitle,
            wsConfiguration: wsConfiguration
        )
    }
    
    /// Creates a standalone WebSocket client for receiving UPS event notifications
    ///
    /// Use this when you manage subscriptions separately and only need the
    /// WebSocket event stream. For integrated subscription + event management,
    /// use `createEventChannelManager` instead.
    ///
    /// - Parameters:
    ///   - aeTitle: The subscriber's AE Title
    ///   - wsConfiguration: WebSocket configuration
    /// - Returns: A configured `UPSWebSocketClient`
    ///
    /// Reference: PS3.18 §8.10.4 - Open Notification Connection Transaction
    public func createWebSocketClient(
        aeTitle: String,
        wsConfiguration: UPSWebSocketConfiguration = .default
    ) -> UPSWebSocketClient {
        return UPSWebSocketClient(
            configuration: configuration,
            aeTitle: aeTitle,
            wsConfiguration: wsConfiguration
        )
    }
    
    // MARK: - Private Helpers
    
    /// Extracts workitem UID from a Location header URL
    private func extractWorkitemUID(from location: String?) -> String? {
        guard let location = location,
              let url = URL(string: location) else {
            return nil
        }
        
        // The UID should be the last path component
        let components = url.pathComponents.filter { $0 != "/" }
        return components.last
    }
    
    /// Extracts warnings from HTTP response headers
    private func extractWarnings(from response: HTTPClient.Response) -> [String] {
        var warnings: [String] = []
        
        if let warning = response.header("Warning") {
            warnings.append(warning)
        }
        
        return warnings
    }
    
    /// Extracts transaction UID from response JSON
    private func extractTransactionUID(from json: [String: Any]) -> String? {
        // Transaction UID is at tag 0008,1195
        if let element = json[UPSTag.transactionUID] as? [String: Any],
           let values = element["Value"] as? [String],
           let uid = values.first {
            return uid
        }
        return nil
    }
    
    /// Builds state change JSON payload
    private func buildStateChangeJSON(state: UPSState, transactionUID: String?) -> [String: Any] {
        var json: [String: Any] = [
            // Procedure Step State (0074,1000)
            UPSTag.procedureStepState: [
                "vr": "CS",
                "Value": [state.rawValue]
            ]
        ]
        
        if let txUID = transactionUID {
            // Transaction UID (0008,1195)
            json[UPSTag.transactionUID] = [
                "vr": "UI",
                "Value": [txUID]
            ]
        }
        
        return json
    }
    
    /// Builds cancellation request JSON payload
    private func buildCancellationJSON(
        reason: String?,
        contactDisplayName: String?,
        contactURI: String?
    ) -> [String: Any] {
        var json: [String: Any] = [:]
        
        if let reason = reason {
            // Reason For Cancellation (0074,1238)
            json[UPSTag.reasonForCancellation] = [
                "vr": "LT",
                "Value": [reason]
            ]
        }
        
        // If contact info provided, add Communication URI sequence
        if contactDisplayName != nil || contactURI != nil {
            var contactItem: [String: Any] = [:]
            
            if let name = contactDisplayName {
                // Contact Display Name
                contactItem["0074100C"] = [
                    "vr": "LO",
                    "Value": [name]
                ]
            }
            
            if let uri = contactURI {
                // Contact URI
                contactItem["0074100A"] = [
                    "vr": "UR",
                    "Value": [uri]
                ]
            }
            
            // Procedure Step Communication URI Sequence
            json["00741008"] = [
                "vr": "SQ",
                "Value": [contactItem]
            ]
        }
        
        return json
    }
    
    /// Converts a Workitem struct to DICOM JSON
    ///
    /// Delegates to `Workitem.toDICOMJSON()` for consistent serialization.
    private func workitemToJSON(_ workitem: Workitem) -> [String: Any] {
        return workitem.toDICOMJSON()
    }
}
#endif
