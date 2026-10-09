import XCTest
@testable import DICOMWeb

/// Thread-safe test collector for captured data in Sendable closures
private actor TestDataCollector {
    var items: [Data] = []
    var latestItem: Data?

    func append(_ data: Data) {
        items.append(data)
        latestItem = data
    }
}

/// Tests for UPS WebSocket event channel client and delivery
@available(macOS 14, iOS 17, *)
final class UPSWebSocketTests: XCTestCase {
    
    // MARK: - UPSWebSocketEvent Tests
    
    func test_webSocketEvent_creation() {
        let event = UPSWebSocketEvent(
            eventType: .stateReport,
            workitemUID: "1.2.3.4.5",
            transactionUID: "1.2.3.4.6",
            rawJSON: Data(),
            receivedAt: Date()
        )
        
        XCTAssertEqual(event.eventType, .stateReport)
        XCTAssertEqual(event.workitemUID, "1.2.3.4.5")
        XCTAssertEqual(event.transactionUID, "1.2.3.4.6")
    }
    
    func test_webSocketEvent_equality() {
        let date = Date()
        let event1 = UPSWebSocketEvent(
            eventType: .stateReport,
            workitemUID: "1.2.3.4.5",
            transactionUID: "tx1",
            receivedAt: date
        )
        let event2 = UPSWebSocketEvent(
            eventType: .stateReport,
            workitemUID: "1.2.3.4.5",
            transactionUID: "tx1",
            receivedAt: date
        )
        let event3 = UPSWebSocketEvent(
            eventType: .progressReport,
            workitemUID: "1.2.3.4.5",
            transactionUID: "tx1",
            receivedAt: date
        )
        
        XCTAssertEqual(event1, event2)
        XCTAssertNotEqual(event1, event3)
    }
    
    func test_webSocketEvent_defaultValues() {
        let event = UPSWebSocketEvent(
            eventType: .completed,
            workitemUID: "1.2.3.4.5"
        )
        
        XCTAssertNil(event.transactionUID)
        XCTAssertTrue(event.rawJSON.isEmpty)
        XCTAssertNotNil(event.receivedAt)
    }
    
    func test_webSocketEvent_decodedJSON() throws {
        let json: [String: Any] = ["key": "value"]
        let data = try JSONSerialization.data(withJSONObject: json)
        let event = UPSWebSocketEvent(
            eventType: .stateReport,
            workitemUID: "1.2.3.4.5",
            rawJSON: data
        )
        
        let decoded = event.decodedJSON()
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?["key"] as? String, "value")
    }
    
    // MARK: - UPSWebSocketError Tests
    
    func test_webSocketError_connectionFailed() {
        let error = UPSWebSocketError.connectionFailed(reason: "Network unreachable")
        XCTAssertTrue(error.errorDescription?.contains("Network unreachable") ?? false)
    }
    
    func test_webSocketError_disconnected() {
        let error = UPSWebSocketError.disconnected(reason: "Server closed", code: 1000)
        XCTAssertTrue(error.errorDescription?.contains("1000") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("Server closed") ?? false)
    }
    
    func test_webSocketError_malformedEvent() {
        let error = UPSWebSocketError.malformedEvent(reason: "Invalid JSON")
        XCTAssertTrue(error.errorDescription?.contains("Invalid JSON") ?? false)
    }
    
    func test_webSocketError_notSupported() {
        let error = UPSWebSocketError.notSupported
        XCTAssertNotNil(error.errorDescription)
    }
    
    func test_webSocketError_authenticationFailed() {
        let error = UPSWebSocketError.authenticationFailed
        XCTAssertNotNil(error.errorDescription)
    }
    
    func test_webSocketError_connectionTimeout() {
        let error = UPSWebSocketError.connectionTimeout
        XCTAssertNotNil(error.errorDescription)
    }
    
    func test_webSocketError_channelClosed() {
        let error = UPSWebSocketError.channelClosed
        XCTAssertNotNil(error.errorDescription)
    }
    
    func test_webSocketError_maxReconnect() {
        let error = UPSWebSocketError.maxReconnectAttemptsExceeded(attempts: 10)
        XCTAssertTrue(error.errorDescription?.contains("10") ?? false)
    }
    
    // MARK: - UPSWebSocketConfiguration Tests
    
    func test_configuration_defaults() {
        let config = UPSWebSocketConfiguration.default
        
        XCTAssertTrue(config.autoReconnect)
        XCTAssertEqual(config.maxReconnectAttempts, 10)
        XCTAssertEqual(config.reconnectDelay, 1.0, accuracy: 0.01)
        XCTAssertEqual(config.maxReconnectDelay, 60.0, accuracy: 0.01)
        XCTAssertEqual(config.pingInterval, 30.0, accuracy: 0.01)
        XCTAssertEqual(config.connectionTimeout, 30.0, accuracy: 0.01)
        XCTAssertEqual(config.maxMessageSize, 1_048_576)
    }
    
    func test_configuration_custom() {
        let config = UPSWebSocketConfiguration(
            autoReconnect: false,
            maxReconnectAttempts: 5,
            reconnectDelay: 2.0,
            maxReconnectDelay: 30.0,
            pingInterval: 15.0,
            connectionTimeout: 10.0,
            maxMessageSize: 512_000
        )
        
        XCTAssertFalse(config.autoReconnect)
        XCTAssertEqual(config.maxReconnectAttempts, 5)
        XCTAssertEqual(config.reconnectDelay, 2.0, accuracy: 0.01)
        XCTAssertEqual(config.maxReconnectDelay, 30.0, accuracy: 0.01)
        XCTAssertEqual(config.pingInterval, 15.0, accuracy: 0.01)
        XCTAssertEqual(config.connectionTimeout, 10.0, accuracy: 0.01)
        XCTAssertEqual(config.maxMessageSize, 512_000)
    }
    
    // MARK: - UPSWebSocketClient Tests
    
    func test_client_initialState() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        XCTAssertEqual(client.connectionState, .disconnected)
        XCTAssertEqual(client.aeTitle, "TEST_AE")
    }
    
    func test_client_buildWebSocketURL_https() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "MY_AE"
        )
        
        let url = try client.buildWebSocketURL()
        XCTAssertEqual(url.scheme, "wss")
        XCTAssertEqual(url.host, "pacs.example.com")
        XCTAssertTrue(url.path.contains("/ws/subscribers/MY_AE"))
    }
    
    func test_client_buildWebSocketURL_http() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "http://localhost:8080/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "LOCAL_AE"
        )
        
        let url = try client.buildWebSocketURL()
        XCTAssertEqual(url.scheme, "ws")
        XCTAssertEqual(url.host, "localhost")
        XCTAssertEqual(url.port, 8080)
        XCTAssertTrue(url.path.contains("/ws/subscribers/LOCAL_AE"))
    }
    
    func test_client_buildWebSocketURL_preservesBasePath() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/api/v2/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "AE1"
        )
        
        let url = try client.buildWebSocketURL()
        XCTAssertEqual(url.scheme, "wss")
        XCTAssertTrue(url.path.hasPrefix("/api/v2/dicom-web"))
        XCTAssertTrue(url.path.hasSuffix("/ws/subscribers/AE1"))
    }

    func test_client_buildWebSocketURL_stripsRsSuffix() throws {
        // dcm4chee-arc style: REST is at /dcm4chee-arc/aets/DCM4CHEE/rs
        // WebSocket should be at     /dcm4chee-arc/aets/DCM4CHEE/ws/subscribers/{ae}
        let config = try DICOMwebConfiguration(
            baseURLString: "http://172.17.1.111:8080/dcm4chee-arc/aets/DCM4CHEE/rs"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "DICOM_STUDIO"
        )

        let url = try client.buildWebSocketURL()
        XCTAssertEqual(url.scheme, "ws")
        XCTAssertEqual(url.path, "/dcm4chee-arc/aets/DCM4CHEE/ws/subscribers/DICOM_STUDIO")
        // The /rs must NOT appear in the WebSocket path
        XCTAssertFalse(url.path.contains("/rs/"))
    }
    
    func test_client_close_setsStateToClosed() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        client.close()
        XCTAssertEqual(client.connectionState, .closed)
    }
    
    func test_client_connectAfterClose_throwsError() async throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        client.close()
        
        do {
            try await client.connect()
            XCTFail("Expected channelClosed error")
        } catch let error as UPSWebSocketError {
            if case .channelClosed = error {
                // Expected
            } else {
                XCTFail("Expected channelClosed, got \(error)")
            }
        }
    }
    
    func test_client_disconnect_setsStateToDisconnected() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        client.disconnect()
        XCTAssertEqual(client.connectionState, .disconnected)
    }
    
    func test_client_eventsStream_isAvailable() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        // Should return an AsyncStream
        let _ = client.events
        // Just verify it doesn't crash
    }
    
    // MARK: - Event Parsing Tests
    
    func test_parseEvent_dicomJsonFormat_stateReport() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        let json: [String: Any] = [
            "00001000": ["vr": "UI", "Value": ["1.2.3.4.5"]],
            "00081195": ["vr": "UI", "Value": ["1.2.3.4.6"]],
            "00001002": ["vr": "US", "Value": [1]],    // Event Type ID = 1 → stateReport
            "00741000": ["vr": "CS", "Value": ["IN PROGRESS"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let event = try client.parseEvent(from: data)
        XCTAssertEqual(event.eventType, .stateReport)
        XCTAssertEqual(event.workitemUID, "1.2.3.4.5")
        XCTAssertEqual(event.transactionUID, "1.2.3.4.6")
    }
    
    func test_parseEvent_dicomJsonFormat_cancelRequested() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        let json: [String: Any] = [
            "00001000": ["vr": "UI", "Value": ["1.2.3.4.5"]],
            "00001002": ["vr": "US", "Value": [2]]    // Event Type ID = 2 → cancelRequested
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let event = try client.parseEvent(from: data)
        XCTAssertEqual(event.eventType, .cancelRequested)
        XCTAssertEqual(event.workitemUID, "1.2.3.4.5")
    }
    
    func test_parseEvent_dicomJsonFormat_progressReport() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        let json: [String: Any] = [
            "00001000": ["vr": "UI", "Value": ["1.2.3.4.5"]],
            "00001002": ["vr": "US", "Value": [3]]    // Event Type ID = 3 → progressReport
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let event = try client.parseEvent(from: data)
        XCTAssertEqual(event.eventType, .progressReport)
    }
    
    func test_parseEvent_stringBasedEventType() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        let json: [String: Any] = [
            "00001000": ["vr": "UI", "Value": ["1.2.3.4.5"]],
            "EventType": ["vr": "CS", "Value": ["Completed"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let event = try client.parseEvent(from: data)
        XCTAssertEqual(event.eventType, .completed)
    }
    
    func test_parseEvent_directJsonEventType() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        let json: [String: Any] = [
            "workitemUID": "1.2.3.4.5",
            "eventType": "Assigned"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let event = try client.parseEvent(from: data)
        XCTAssertEqual(event.eventType, .assigned)
        XCTAssertEqual(event.workitemUID, "1.2.3.4.5")
    }
    
    func test_parseEvent_inferredFromState() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        // Has Procedure Step State but no explicit event type
        let json: [String: Any] = [
            "00001000": ["vr": "UI", "Value": ["1.2.3.4.5"]],
            "00741000": ["vr": "CS", "Value": ["COMPLETED"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let event = try client.parseEvent(from: data)
        XCTAssertEqual(event.eventType, .stateReport)
    }
    
    func test_parseEvent_inferredFromProgress() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        // Has Progress Information Sequence but no explicit event type
        let json: [String: Any] = [
            "00001000": ["vr": "UI", "Value": ["1.2.3.4.5"]],
            "00741004": ["vr": "SQ", "Value": []]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let event = try client.parseEvent(from: data)
        XCTAssertEqual(event.eventType, .progressReport)
    }
    
    func test_parseEvent_invalidJson_throws() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        let data = "not json".data(using: .utf8)!
        
        XCTAssertThrowsError(try client.parseEvent(from: data)) { error in
            guard let wsError = error as? UPSWebSocketError else {
                XCTFail("Expected UPSWebSocketError"); return
            }
            if case .malformedEvent = wsError {
                // Expected
            } else {
                XCTFail("Expected malformedEvent, got \(wsError)")
            }
        }
    }
    
    func test_parseEvent_missingWorkitemUID_throws() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        let json: [String: Any] = [
            "00001002": ["vr": "US", "Value": [1]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        XCTAssertThrowsError(try client.parseEvent(from: data)) { error in
            guard let wsError = error as? UPSWebSocketError else {
                XCTFail("Expected UPSWebSocketError"); return
            }
            if case .malformedEvent = wsError {
                // Expected
            } else {
                XCTFail("Expected malformedEvent, got \(wsError)")
            }
        }
    }
    
    func test_parseEvent_unknownEventType_throws() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        // Has workitem UID but no recognizable event type
        let json: [String: Any] = [
            "00001000": ["vr": "UI", "Value": ["1.2.3.4.5"]],
            "someOtherTag": "value"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        XCTAssertThrowsError(try client.parseEvent(from: data)) { error in
            guard let wsError = error as? UPSWebSocketError else {
                XCTFail("Expected UPSWebSocketError"); return
            }
            if case .malformedEvent = wsError {
                // Expected
            } else {
                XCTFail("Expected malformedEvent, got \(wsError)")
            }
        }
    }
    
    func test_parseEvent_withTransactionUID() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        let json: [String: Any] = [
            "workitemUID": "1.2.3.4.5",
            "transactionUID": "1.2.3.99",
            "eventType": "StateReport"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let event = try client.parseEvent(from: data)
        XCTAssertEqual(event.transactionUID, "1.2.3.99")
    }
    
    func test_parseEvent_withoutTransactionUID() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let client = UPSWebSocketClient(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        let json: [String: Any] = [
            "workitemUID": "1.2.3.4.5",
            "eventType": "Canceled"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        
        let event = try client.parseEvent(from: data)
        XCTAssertNil(event.transactionUID)
        XCTAssertEqual(event.eventType, .canceled)
    }
    
    // MARK: - WebSocketEventDeliveryService Tests
    
    func test_deliveryService_startStop() async throws {
        let service = WebSocketEventDeliveryService()
        
        try await service.start()
        try await service.stop()
    }
    
    func test_deliveryService_registerSubscriber() async throws {
        let service = WebSocketEventDeliveryService()
        try await service.start()
        
        await service.registerSubscriber(aeTitle: "AE1") { _ in }
        
        let isConnected = await service.isSubscriberConnected(aeTitle: "AE1")
        XCTAssertTrue(isConnected)
        
        let count = await service.connectedSubscriberCount()
        XCTAssertEqual(count, 1)
        
        try await service.stop()
    }
    
    func test_deliveryService_removeSubscriber() async throws {
        let service = WebSocketEventDeliveryService()
        try await service.start()
        
        await service.registerSubscriber(aeTitle: "AE1") { _ in }
        await service.removeSubscriber(aeTitle: "AE1")
        
        let isConnected = await service.isSubscriberConnected(aeTitle: "AE1")
        XCTAssertFalse(isConnected)
        
        try await service.stop()
    }
    
    func test_deliveryService_deliverEvent() async throws {
        let service = WebSocketEventDeliveryService()
        try await service.start()
        
        let collector = TestDataCollector()
        await service.registerSubscriber(aeTitle: "AE1") { data in
            await collector.append(data)
        }
        
        let stateEvent = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        let anyEvent = AnyUPSEvent(stateEvent)
        
        let subscription = Subscription(
            aeTitle: "AE1",
            workitemUID: "1.2.3.4.5"
        )
        
        try await service.deliverEvent(anyEvent, to: subscription)
        
        let receivedData = await collector.latestItem
        XCTAssertNotNil(receivedData)
        
        // Verify the data is valid JSON
        if let data = receivedData {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertNotNil(json)
            
            // Should contain workitem UID
            if let uidElement = json?["00001000"] as? [String: Any],
               let values = uidElement["Value"] as? [String] {
                XCTAssertEqual(values.first, "1.2.3.4.5")
            }
        }
        
        let stats = await service.statistics()
        XCTAssertEqual(stats.delivered, 1)
        XCTAssertEqual(stats.failed, 0)
        
        try await service.stop()
    }
    
    func test_deliveryService_unreachableSubscriber() async throws {
        let service = WebSocketEventDeliveryService()
        try await service.start()
        
        // No subscriber registered for "UNKNOWN_AE"
        let stateEvent = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        let anyEvent = AnyUPSEvent(stateEvent)
        
        let subscription = Subscription(
            aeTitle: "UNKNOWN_AE",
            workitemUID: "1.2.3.4.5"
        )
        
        do {
            try await service.deliverEvent(anyEvent, to: subscription)
            XCTFail("Expected error for unreachable subscriber")
        } catch let error as EventDeliveryError {
            if case .subscriberUnreachable(let ae) = error {
                XCTAssertEqual(ae, "UNKNOWN_AE")
            } else {
                XCTFail("Expected subscriberUnreachable, got \(error)")
            }
        }
        
        try await service.stop()
    }
    
    func test_deliveryService_notRunning() async throws {
        let service = WebSocketEventDeliveryService()
        // Not started
        
        let stateEvent = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        let anyEvent = AnyUPSEvent(stateEvent)
        
        let subscription = Subscription(aeTitle: "AE1", workitemUID: "1.2.3.4.5")
        
        do {
            try await service.deliverEvent(anyEvent, to: subscription)
            XCTFail("Expected service not available error")
        } catch let error as EventDeliveryError {
            if case .serviceNotAvailable = error {
                // Expected
            } else {
                XCTFail("Expected serviceNotAvailable, got \(error)")
            }
        }
    }
    
    func test_deliveryService_canDeliver() {
        let service = WebSocketEventDeliveryService()
        let subscription = Subscription(aeTitle: "AE1", workitemUID: "1.2.3.4.5")
        
        // Should return true optimistically
        XCTAssertTrue(service.canDeliver(to: subscription))
    }
    
    func test_deliveryService_statistics() async throws {
        let service = WebSocketEventDeliveryService()
        try await service.start()
        
        await service.registerSubscriber(aeTitle: "AE1") { _ in }
        
        let stateEvent = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        let anyEvent = AnyUPSEvent(stateEvent)
        let subscription = Subscription(aeTitle: "AE1", workitemUID: "1.2.3.4.5")
        
        try await service.deliverEvent(anyEvent, to: subscription)
        try await service.deliverEvent(anyEvent, to: subscription)
        
        let stats = await service.statistics()
        XCTAssertEqual(stats.delivered, 2)
        XCTAssertEqual(stats.failed, 0)
        
        try await service.stop()
    }
    
    func test_deliveryService_failedDeliveryCountsStatistic() async throws {
        let service = WebSocketEventDeliveryService()
        try await service.start()
        
        // Register subscriber that throws
        await service.registerSubscriber(aeTitle: "BAD_AE") { _ in
            throw NSError(domain: "test", code: 1, userInfo: nil)
        }
        
        let stateEvent = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        let anyEvent = AnyUPSEvent(stateEvent)
        let subscription = Subscription(aeTitle: "BAD_AE", workitemUID: "1.2.3.4.5")
        
        do {
            try await service.deliverEvent(anyEvent, to: subscription)
            XCTFail("Expected delivery failure")
        } catch {
            // Expected
        }
        
        let stats = await service.statistics()
        XCTAssertEqual(stats.delivered, 0)
        XCTAssertEqual(stats.failed, 1)
        
        try await service.stop()
    }
    
    // MARK: - UPSEventChannelManager Tests
    
    func test_eventChannelManager_initialState() async throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let manager = UPSEventChannelManager(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        XCTAssertEqual(manager.aeTitle, "TEST_AE")
        let subs = await manager.activeSubscriptions
        XCTAssertTrue(subs.isEmpty)
        let hasGlobal = await manager.hasGlobalSubscription
        XCTAssertFalse(hasGlobal)
        let count = await manager.subscriptionCount
        XCTAssertEqual(count, 0)
        XCTAssertEqual(manager.channelState, .disconnected)
    }
    
    func test_eventChannelManager_closeAll() async throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let manager = UPSEventChannelManager(
            configuration: config,
            aeTitle: "TEST_AE"
        )
        
        try await manager.closeAll()
        
        let subs = await manager.activeSubscriptions
        XCTAssertTrue(subs.isEmpty)
        let hasGlobal = await manager.hasGlobalSubscription
        XCTAssertFalse(hasGlobal)
        let count = await manager.subscriptionCount
        XCTAssertEqual(count, 0)
    }
    
    // MARK: - UPSClient Integration Tests
    
    func test_client_createEventChannelManager() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let upsClient = UPSClient(configuration: config)
        
        let manager = upsClient.createEventChannelManager(aeTitle: "MY_AE")
        XCTAssertEqual(manager.aeTitle, "MY_AE")
        XCTAssertEqual(manager.channelState, .disconnected)
    }
    
    func test_client_createWebSocketClient() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let upsClient = UPSClient(configuration: config)
        
        let wsClient = upsClient.createWebSocketClient(
            aeTitle: "MY_AE",
            wsConfiguration: UPSWebSocketConfiguration(
                autoReconnect: false,
                maxReconnectAttempts: 3
            )
        )
        
        XCTAssertEqual(wsClient.aeTitle, "MY_AE")
        XCTAssertEqual(wsClient.connectionState, .disconnected)
    }
    
    // MARK: - URL Builder Tests
    
    func test_urlBuilder_webSocketEventChannelURL_https() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "https://pacs.example.com/dicom-web"
        )
        let urlBuilder = config.urlBuilder
        
        let url = urlBuilder.webSocketEventChannelURL(aeTitle: "MY_AE")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "wss")
        XCTAssertEqual(url?.host, "pacs.example.com")
        XCTAssertTrue(url?.path.contains("/ws/subscribers/MY_AE") ?? false)
    }
    
    func test_urlBuilder_webSocketEventChannelURL_http() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "http://localhost:8042/dicom-web"
        )
        let urlBuilder = config.urlBuilder
        
        let url = urlBuilder.webSocketEventChannelURL(aeTitle: "LOCAL_AE")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "ws")
        XCTAssertEqual(url?.host, "localhost")
        XCTAssertEqual(url?.port, 8042)
        XCTAssertTrue(url?.path.contains("/ws/subscribers/LOCAL_AE") ?? false)
    }

    func test_urlBuilder_webSocketEventChannelURL_stripsRsSuffix() throws {
        let config = try DICOMwebConfiguration(
            baseURLString: "http://172.17.1.111:8080/dcm4chee-arc/aets/DCM4CHEE/rs"
        )
        let urlBuilder = config.urlBuilder

        let url = urlBuilder.webSocketEventChannelURL(aeTitle: "DICOM_STUDIO")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "ws")
        XCTAssertEqual(url?.path, "/dcm4chee-arc/aets/DCM4CHEE/ws/subscribers/DICOM_STUDIO")
        XCTAssertFalse(url?.path.contains("/rs/") ?? true)
    }
    
    // MARK: - Integration: WebSocket Delivery with Event Dispatcher
    
    func test_webSocketDelivery_withEventDispatcher() async throws {
        let subscriptionManager = InMemorySubscriptionManager()
        let wsDeliveryService = WebSocketEventDeliveryService()
        let dispatcher = EventDispatcher(
            subscriptionManager: subscriptionManager,
            deliveryService: wsDeliveryService
        )
        
        try await dispatcher.start()
        
        // Register a subscriber
        let collector = TestDataCollector()
        await wsDeliveryService.registerSubscriber(aeTitle: "VIEWER_AE") { data in
            await collector.append(data)
        }
        
        // Create a subscription
        _ = try await subscriptionManager.subscribe(
            aeTitle: "VIEWER_AE",
            workitemUID: "1.2.3.4.5",
            deletionLock: false,
            eventTypes: nil
        )
        
        // Dispatch an event
        let stateEvent = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        await dispatcher.dispatch(stateEvent)
        
        // Give the delivery loop time to process
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        let items = await collector.items
        XCTAssertFalse(items.isEmpty, "Expected at least one delivered event")
        
        try await dispatcher.stop()
    }
    
    func test_webSocketDelivery_globalSubscription() async throws {
        let subscriptionManager = InMemorySubscriptionManager()
        let wsDeliveryService = WebSocketEventDeliveryService()
        let dispatcher = EventDispatcher(
            subscriptionManager: subscriptionManager,
            deliveryService: wsDeliveryService
        )
        
        try await dispatcher.start()
        
        let collector = TestDataCollector()
        await wsDeliveryService.registerSubscriber(aeTitle: "GLOBAL_AE") { data in
            await collector.append(data)
        }
        
        // Global subscription — receives events from all workitems
        _ = try await subscriptionManager.subscribeGlobal(
            aeTitle: "GLOBAL_AE",
            deletionLock: false,
            eventTypes: nil
        )
        
        // Dispatch events for different workitems
        let event1 = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        let event2 = UPSStateReportEvent(
            workitemUID: "9.8.7.6.5",
            previousState: .inProgress,
            newState: .completed
        )
        
        await dispatcher.dispatch(event1)
        await dispatcher.dispatch(event2)
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let items = await collector.items
        XCTAssertGreaterThanOrEqual(items.count, 2, "Expected events from both workitems")
        
        try await dispatcher.stop()
    }
    
    func test_webSocketDelivery_eventTypeFiltering() async throws {
        let subscriptionManager = InMemorySubscriptionManager()
        let wsDeliveryService = WebSocketEventDeliveryService()
        let dispatcher = EventDispatcher(
            subscriptionManager: subscriptionManager,
            deliveryService: wsDeliveryService
        )
        
        try await dispatcher.start()
        
        let collector = TestDataCollector()
        await wsDeliveryService.registerSubscriber(aeTitle: "FILTER_AE") { data in
            await collector.append(data)
        }
        
        // Subscribe only for state reports
        _ = try await subscriptionManager.subscribe(
            aeTitle: "FILTER_AE",
            workitemUID: "1.2.3.4.5",
            deletionLock: false,
            eventTypes: [.stateReport]
        )
        
        // Dispatch a state report and a progress report
        let stateEvent = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        let progressEvent = UPSProgressReportEvent(
            workitemUID: "1.2.3.4.5",
            progressInformation: ProgressInformation(
                progressPercentage: 50,
                progressDescription: "Half done"
            )
        )
        
        await dispatcher.dispatch(stateEvent)
        await dispatcher.dispatch(progressEvent)
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Should only receive the state report, not the progress report
        let items = await collector.items
        XCTAssertEqual(items.count, 1, "Only state report should be delivered")
        
        try await dispatcher.stop()
    }
    
    func test_webSocketDelivery_suspendedSubscription_noDelivery() async throws {
        let subscriptionManager = InMemorySubscriptionManager()
        let wsDeliveryService = WebSocketEventDeliveryService()
        let dispatcher = EventDispatcher(
            subscriptionManager: subscriptionManager,
            deliveryService: wsDeliveryService
        )
        
        try await dispatcher.start()
        
        let collector = TestDataCollector()
        await wsDeliveryService.registerSubscriber(aeTitle: "SUSPEND_AE") { data in
            await collector.append(data)
        }
        
        _ = try await subscriptionManager.subscribe(
            aeTitle: "SUSPEND_AE",
            workitemUID: "1.2.3.4.5",
            deletionLock: false,
            eventTypes: nil
        )
        
        // Suspend the subscription
        try await subscriptionManager.suspendSubscription(aeTitle: "SUSPEND_AE", workitemUID: "1.2.3.4.5")
        
        let stateEvent = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        await dispatcher.dispatch(stateEvent)
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let items = await collector.items
        XCTAssertTrue(items.isEmpty, "Suspended subscription should not receive events")
        
        try await dispatcher.stop()
    }
    
    // MARK: - Composite Delivery with WebSocket
    
    func test_compositeDelivery_webSocketAsPrimary() async throws {
        let wsService = WebSocketEventDeliveryService()
        let loggingService = LoggingEventDeliveryService()
        let composite = CompositeEventDeliveryService(
            deliveryServices: [wsService, loggingService]
        )
        
        try await composite.start()
        
        await wsService.registerSubscriber(aeTitle: "AE1") { _ in }
        
        let stateEvent = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        let anyEvent = AnyUPSEvent(stateEvent)
        let subscription = Subscription(aeTitle: "AE1", workitemUID: "1.2.3.4.5")
        
        try await composite.deliverEvent(anyEvent, to: subscription)
        
        // WebSocket succeeded, so logging should NOT have received it
        let loggingEvents = await loggingService.getDeliveredEvents()
        XCTAssertTrue(loggingEvents.isEmpty, "Logging service should not be used when WebSocket succeeds")
        
        let wsStats = await wsService.statistics()
        XCTAssertEqual(wsStats.delivered, 1)
        
        try await composite.stop()
    }
}
