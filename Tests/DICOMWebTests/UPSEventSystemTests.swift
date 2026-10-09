import XCTest
@testable import DICOMWeb

/// Tests for UPS Event System (events, subscriptions, delivery)
@available(macOS 14, iOS 17, *)
final class UPSEventSystemTests: XCTestCase {
    
    // MARK: - Event Type Tests
    
    func testUPSEventTypeRawValues() {
        XCTAssertEqual(UPSEventType.stateReport.rawValue, "StateReport")
        XCTAssertEqual(UPSEventType.progressReport.rawValue, "ProgressReport")
        XCTAssertEqual(UPSEventType.cancelRequested.rawValue, "CancelRequested")
        XCTAssertEqual(UPSEventType.assigned.rawValue, "Assigned")
        XCTAssertEqual(UPSEventType.completed.rawValue, "Completed")
        XCTAssertEqual(UPSEventType.canceled.rawValue, "Canceled")
    }
    
    func testUPSEventTypeCaseIterable() {
        let allTypes = UPSEventType.allCases
        XCTAssertEqual(allTypes.count, 7)
        XCTAssertTrue(allTypes.contains(.scpStatusChange))
        // PS3.4 Table CC.2.4-1 Event Type IDs
        XCTAssertEqual(UPSEventType.stateReport.eventTypeID, 1)
        XCTAssertEqual(UPSEventType.cancelRequested.eventTypeID, 2)
        XCTAssertEqual(UPSEventType.progressReport.eventTypeID, 3)
        XCTAssertEqual(UPSEventType.scpStatusChange.eventTypeID, 4)
        XCTAssertEqual(UPSEventType.assigned.eventTypeID, 5)
        XCTAssertEqual(UPSEventType.completed.eventTypeID, 1)
        XCTAssertEqual(UPSEventType(eventTypeID: 5), .assigned)
        XCTAssertTrue(allTypes.contains(.stateReport))
        XCTAssertTrue(allTypes.contains(.progressReport))
        XCTAssertTrue(allTypes.contains(.cancelRequested))
        XCTAssertTrue(allTypes.contains(.assigned))
        XCTAssertTrue(allTypes.contains(.completed))
        XCTAssertTrue(allTypes.contains(.canceled))
    }
    
    // MARK: - UPSStateReportEvent Tests
    
    func testStateReportEventCreation() {
        let event = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            transactionUID: "1.2.3.4.6",
            previousState: .scheduled,
            newState: .inProgress
        )
        
        XCTAssertEqual(event.eventType, .stateReport)
        XCTAssertEqual(event.workitemUID, "1.2.3.4.5")
        XCTAssertEqual(event.transactionUID, "1.2.3.4.6")
        XCTAssertEqual(event.previousState, .scheduled)
        XCTAssertEqual(event.newState, .inProgress)
    }
    
    func testStateReportEventToDICOMJSON() {
        let event = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            transactionUID: "1.2.3.4.6",
            previousState: .scheduled,
            newState: .inProgress,
            reason: "Start processing"
        )
        
        let json = event.toDICOMJSON()
        
        // PS3.4 CC.2.7.3: the Transaction UID is the access lock and is never in an Event Report
        XCTAssertNil(json["00081195"])
        
        // Check state
        if let state = json["00741000"] as? [String: Any],
           let value = state["Value"] as? [String] {
            XCTAssertEqual(value.first, "IN PROGRESS")
        } else {
            XCTFail("State not found in JSON")
        }
        
        // PS3.4 Table CC.2.4-1: Event Type ID (0000,1002) = 1, Input Readiness State (0040,4041) Type 1
        XCTAssertEqual(((json["00001002"] as? [String: Any])?["Value"] as? [Int])?.first, 1)
        XCTAssertEqual(((json["00404041"] as? [String: Any])?["Value"] as? [String])?.first, "READY")
        XCTAssertEqual(((json["00741238"] as? [String: Any])?["Value"] as? [String])?.first, "Start processing")
        XCTAssertNil(json["EventType"], "no bare-name keys in a DICOM JSON Event Report")
    }
    
    // MARK: - UPSProgressReportEvent Tests
    
    func testProgressReportEventCreation() {
        let progress = ProgressInformation(
            progressPercentage: 50,
            progressDescription: "Halfway complete"
        )
        
        let event = UPSProgressReportEvent(
            workitemUID: "1.2.3.4.5",
            transactionUID: "1.2.3.4.6",
            progressInformation: progress
        )
        
        XCTAssertEqual(event.eventType, .progressReport)
        XCTAssertEqual(event.workitemUID, "1.2.3.4.5")
        XCTAssertEqual(event.progressInformation.progressPercentage, 50)
        XCTAssertEqual(event.progressInformation.progressDescription, "Halfway complete")
    }
    
    func testProgressReportEventToDICOMJSON() {
        let progress = ProgressInformation(
            progressPercentage: 75,
            progressDescription: "Nearly done",
            contactDisplayName: "Dr. Smith",
            contactURI: "https://example.com/contact"
        )
        
        let event = UPSProgressReportEvent(
            workitemUID: "1.2.3.4.5",
            progressInformation: progress
        )
        
        let json = event.toDICOMJSON()
        
        // PS3.4 Table CC.2.4-1: Event Type ID 3; the progress attributes sit inside the
        // Procedure Step Progress Information Sequence (0074,1002)
        XCTAssertEqual(((json["00001002"] as? [String: Any])?["Value"] as? [Int])?.first, 3)
        guard let item = ((json["00741002"] as? [String: Any])?["Value"] as? [[String: Any]])?.first else {
            return XCTFail("Procedure Step Progress Information Sequence not found in JSON")
        }
        XCTAssertEqual(((item["00741004"] as? [String: Any])?["Value"] as? [String])?.first, "75")
        XCTAssertEqual(((item["00741006"] as? [String: Any])?["Value"] as? [String])?.first, "Nearly done")
        let contact = ((item["00741008"] as? [String: Any])?["Value"] as? [[String: Any]])?.first
        XCTAssertEqual(((contact?["0074100A"] as? [String: Any])?["Value"] as? [String])?.first, "https://example.com/contact")
        XCTAssertEqual(((contact?["0074100C"] as? [String: Any])?["Value"] as? [String])?.first, "Dr. Smith")
        XCTAssertNil(json["00741004"], "progress is not a top-level attribute")
    }
    
    // MARK: - UPSCancelRequestedEvent Tests
    
    func testCancelRequestedEventCreation() {
        let event = UPSCancelRequestedEvent(
            workitemUID: "1.2.3.4.5",
            reason: "Patient request",
            contactDisplayName: "Dr. Jones"
        )
        
        XCTAssertEqual(event.eventType, .cancelRequested)
        XCTAssertEqual(event.workitemUID, "1.2.3.4.5")
        XCTAssertEqual(event.reason, "Patient request")
        XCTAssertEqual(event.contactDisplayName, "Dr. Jones")
    }
    
    // MARK: - UPSAssignedEvent Tests
    
    func testAssignedEventCreation() {
        let performer = HumanPerformer(
            performerName: "Dr. Smith",
            performerOrganization: "General Hospital"
        )
        
        let event = UPSAssignedEvent(
            workitemUID: "1.2.3.4.5",
            performer: performer
        )
        
        XCTAssertEqual(event.eventType, .assigned)
        XCTAssertEqual(event.performer.performerName, "Dr. Smith")
        XCTAssertEqual(event.performer.performerOrganization, "General Hospital")
    }
    
    // MARK: - UPSCompletedEvent Tests
    
    func testCompletedEventCreation() {
        let event = UPSCompletedEvent(
            workitemUID: "1.2.3.4.5",
            transactionUID: "1.2.3.4.6",
            completionNotes: "Successfully completed"
        )
        
        XCTAssertEqual(event.eventType, .completed)
        XCTAssertEqual(event.completionNotes, "Successfully completed")
    }
    
    // MARK: - UPSCanceledEvent Tests
    
    func testCanceledEventCreation() {
        let event = UPSCanceledEvent(
            workitemUID: "1.2.3.4.5",
            transactionUID: "1.2.3.4.6",
            reason: "Patient cancelled appointment"
        )
        
        XCTAssertEqual(event.eventType, .canceled)
        XCTAssertEqual(event.reason, "Patient cancelled appointment")
    }
    
    // MARK: - AnyUPSEvent Tests
    
    func testAnyUPSEventWrapper() {
        let stateEvent = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        
        let anyEvent = AnyUPSEvent(stateEvent)
        
        XCTAssertEqual(anyEvent.eventType, .stateReport)
        XCTAssertEqual(anyEvent.workitemUID, "1.2.3.4.5")
        
        let json = anyEvent.toDICOMJSON()
        XCTAssertNotNil(json["00001002"], "Event Type ID (0000,1002)")
    }
    
    // MARK: - Subscription Tests
    
    func testSubscriptionCreation() {
        let subscription = Subscription(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5",
            deletionLock: true
        )
        
        XCTAssertEqual(subscription.aeTitle, "SCU1")
        XCTAssertEqual(subscription.workitemUID, "1.2.3.4.5")
        XCTAssertTrue(subscription.deletionLock)
        XCTAssertFalse(subscription.isGlobal)
        XCTAssertFalse(subscription.isSuspended)
    }
    
    func testGlobalSubscription() {
        let subscription = Subscription(
            aeTitle: "SCU1",
            workitemUID: nil,
            deletionLock: false
        )
        
        XCTAssertTrue(subscription.isGlobal)
    }
    
    func testSubscriptionInterest() {
        // Subscription interested in all events for a workitem
        let subscription = Subscription(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5"
        )
        
        let event = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        
        XCTAssertTrue(subscription.isInterestedIn(event: event))
        
        // Different workitem
        let otherEvent = UPSStateReportEvent(
            workitemUID: "9.8.7.6.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        
        XCTAssertFalse(subscription.isInterestedIn(event: otherEvent))
    }
    
    func testSubscriptionEventTypeFilter() {
        // Subscription interested only in progress reports
        let subscription = Subscription(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5",
            eventTypes: [.progressReport]
        )
        
        let progressEvent = UPSProgressReportEvent(
            workitemUID: "1.2.3.4.5",
            progressInformation: ProgressInformation(progressPercentage: 50)
        )
        
        XCTAssertTrue(subscription.isInterestedIn(event: progressEvent))
        
        let stateEvent = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        
        XCTAssertFalse(subscription.isInterestedIn(event: stateEvent))
    }
    
    func testSubscriptionSuspended() {
        var subscription = Subscription(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5"
        )
        subscription.isSuspended = true
        
        let event = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        
        XCTAssertFalse(subscription.isInterestedIn(event: event))
    }
    
    // MARK: - SubscriptionManager Tests
    
    func testSubscriptionManagerSubscribe() async throws {
        let manager = InMemorySubscriptionManager()
        
        let subscription = try await manager.subscribe(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5",
            deletionLock: true,
            eventTypes: nil
        )
        
        XCTAssertEqual(subscription.aeTitle, "SCU1")
        XCTAssertEqual(subscription.workitemUID, "1.2.3.4.5")
        XCTAssertTrue(subscription.deletionLock)
    }
    
    func testSubscriptionManagerGlobalSubscribe() async throws {
        let manager = InMemorySubscriptionManager()
        
        let subscription = try await manager.subscribeGlobal(
            aeTitle: "SCU1",
            deletionLock: false,
            eventTypes: nil
        )
        
        XCTAssertEqual(subscription.aeTitle, "SCU1")
        XCTAssertNil(subscription.workitemUID)
        XCTAssertTrue(subscription.isGlobal)
    }
    
    func testSubscriptionManagerUnsubscribe() async throws {
        let manager = InMemorySubscriptionManager()
        
        _ = try await manager.subscribe(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5",
            deletionLock: false,
            eventTypes: nil
        )
        
        // Unsubscribe should be idempotent
        try await manager.unsubscribe(aeTitle: "SCU1", workitemUID: "1.2.3.4.5")
        try await manager.unsubscribe(aeTitle: "SCU1", workitemUID: "1.2.3.4.5")
        
        let subscriptions = try await manager.getSubscriptions(forWorkitem: "1.2.3.4.5")
        XCTAssertTrue(subscriptions.isEmpty)
    }
    
    func testSubscriptionManagerGetSubscriptions() async throws {
        let manager = InMemorySubscriptionManager()
        
        _ = try await manager.subscribe(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5",
            deletionLock: false,
            eventTypes: nil
        )
        
        _ = try await manager.subscribe(
            aeTitle: "SCU2",
            workitemUID: "1.2.3.4.5",
            deletionLock: true,
            eventTypes: nil
        )
        
        let workitemSubs = try await manager.getSubscriptions(forWorkitem: "1.2.3.4.5")
        XCTAssertEqual(workitemSubs.count, 2)
        
        let aeTitle1Subs = try await manager.getSubscriptions(forAETitle: "SCU1")
        XCTAssertEqual(aeTitle1Subs.count, 1)
    }
    
    func testSubscriptionManagerDeleteLock() async throws {
        let manager = InMemorySubscriptionManager()
        
        _ = try await manager.subscribe(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5",
            deletionLock: true,
            eventTypes: nil
        )
        
        let hasLock = try await manager.hasDeleteLock(forWorkitem: "1.2.3.4.5")
        XCTAssertTrue(hasLock)
        
        try await manager.unsubscribe(aeTitle: "SCU1", workitemUID: "1.2.3.4.5")
        
        let hasLockAfter = try await manager.hasDeleteLock(forWorkitem: "1.2.3.4.5")
        XCTAssertFalse(hasLockAfter)
    }
    
    func testSubscriptionManagerSuspend() async throws {
        let manager = InMemorySubscriptionManager()
        
        _ = try await manager.subscribe(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5",
            deletionLock: false,
            eventTypes: nil
        )
        
        try await manager.suspendSubscription(aeTitle: "SCU1", workitemUID: "1.2.3.4.5")
        
        let subscriptions = try await manager.getSubscriptions(forWorkitem: "1.2.3.4.5")
        XCTAssertEqual(subscriptions.count, 1)
        XCTAssertTrue(subscriptions[0].isSuspended)
    }
    
    func testSubscriptionManagerResume() async throws {
        let manager = InMemorySubscriptionManager()
        
        _ = try await manager.subscribe(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5",
            deletionLock: false,
            eventTypes: nil
        )
        
        try await manager.suspendSubscription(aeTitle: "SCU1", workitemUID: "1.2.3.4.5")
        try await manager.resumeSubscription(aeTitle: "SCU1", workitemUID: "1.2.3.4.5")
        
        let subscriptions = try await manager.getSubscriptions(forWorkitem: "1.2.3.4.5")
        XCTAssertEqual(subscriptions.count, 1)
        XCTAssertFalse(subscriptions[0].isSuspended)
    }
    
    func testSubscriptionManagerGetSubscriptionsForEvent() async throws {
        let manager = InMemorySubscriptionManager()
        
        // Workitem-specific subscription
        _ = try await manager.subscribe(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5",
            deletionLock: false,
            eventTypes: nil
        )
        
        // Global subscription
        _ = try await manager.subscribeGlobal(
            aeTitle: "SCU2",
            deletionLock: false,
            eventTypes: nil
        )
        
        let event = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        
        let subscriptions = await manager.getSubscriptionsForEvent(event)
        XCTAssertEqual(subscriptions.count, 2) // Both workitem-specific and global
    }
    
    // MARK: - Event Queue Tests
    
    func testEventQueueEnqueueDequeue() async throws {
        let queue = EventQueue(maxQueueSize: 10)
        
        let event = AnyUPSEvent(UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        ))
        
        let subscription = Subscription(aeTitle: "SCU1", workitemUID: "1.2.3.4.5")
        
        await queue.enqueue(event: event, for: [subscription])
        
        let size = await queue.size()
        XCTAssertEqual(size, 1)
        
        let dequeued = await queue.dequeue()
        XCTAssertNotNil(dequeued)
        XCTAssertEqual(dequeued?.event.workitemUID, "1.2.3.4.5")
        
        let sizeAfter = await queue.size()
        XCTAssertEqual(sizeAfter, 0)
    }
    
    func testEventQueueMaxSize() async throws {
        let queue = EventQueue(maxQueueSize: 3)
        
        let subscription = Subscription(aeTitle: "SCU1", workitemUID: "1.2.3.4.5")
        
        // Enqueue 5 events
        for i in 1...5 {
            let event = AnyUPSEvent(UPSStateReportEvent(
                workitemUID: "1.2.3.4.\(i)",
                previousState: .scheduled,
                newState: .inProgress
            ))
            await queue.enqueue(event: event, for: [subscription])
        }
        
        // Queue should only have 3 events (oldest removed)
        let size = await queue.size()
        XCTAssertEqual(size, 3)
        
        // First event should be "1.2.3.4.3" (oldest two removed)
        let dequeued = await queue.dequeue()
        XCTAssertEqual(dequeued?.event.workitemUID, "1.2.3.4.3")
    }
    
    // MARK: - LoggingEventDeliveryService Tests
    
    func testLoggingDeliveryService() async throws {
        let service = LoggingEventDeliveryService()
        
        try await service.start()
        
        let event = AnyUPSEvent(UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        ))
        
        let subscription = Subscription(aeTitle: "SCU1", workitemUID: "1.2.3.4.5")
        
        try await service.deliverEvent(event, to: subscription)
        
        let delivered = await service.getDeliveredEvents()
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered[0].event.workitemUID, "1.2.3.4.5")
        XCTAssertEqual(delivered[0].subscription.aeTitle, "SCU1")
        
        try await service.stop()
    }
    
    // MARK: - EventDispatcher Tests
    
    func testEventDispatcherIntegration() async throws {
        let subscriptionManager = InMemorySubscriptionManager()
        let deliveryService = LoggingEventDeliveryService()
        let dispatcher = EventDispatcher(
            subscriptionManager: subscriptionManager,
            deliveryService: deliveryService
        )
        
        try await dispatcher.start()
        
        // Subscribe
        _ = try await subscriptionManager.subscribe(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5",
            deletionLock: false,
            eventTypes: nil
        )
        
        // Dispatch event
        let event = UPSStateReportEvent(
            workitemUID: "1.2.3.4.5",
            previousState: .scheduled,
            newState: .inProgress
        )
        await dispatcher.dispatch(event)
        
        // Give dispatcher time to process
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Check delivery
        let delivered = await deliveryService.getDeliveredEvents()
        XCTAssertGreaterThanOrEqual(delivered.count, 1)
        
        try await dispatcher.stop()
    }
    
    // MARK: - Integration with Storage Provider Tests
    
    func testStorageProviderEventGeneration() async throws {
        let storage = InMemoryUPSStorageProvider()
        let subscriptionManager = InMemorySubscriptionManager()
        let deliveryService = LoggingEventDeliveryService()
        let dispatcher = EventDispatcher(
            subscriptionManager: subscriptionManager,
            deliveryService: deliveryService
        )
        
        await storage.setEventDispatcher(dispatcher)
        try await dispatcher.start()
        
        // Subscribe to workitem
        _ = try await subscriptionManager.subscribe(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5",
            deletionLock: false,
            eventTypes: nil
        )
        
        // Create workitem
        let workitem = Workitem(workitemUID: "1.2.3.4.5", state: .scheduled)
        try await storage.createWorkitem(workitem)
        
        // Change state
        try await storage.changeWorkitemState(
            workitemUID: "1.2.3.4.5",
            newState: .inProgress,
            transactionUID: nil
        )
        
        // Give dispatcher time to process
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Check that events were generated
        let delivered = await deliveryService.getDeliveredEvents()
        XCTAssertGreaterThanOrEqual(delivered.count, 1)
        
        // Find state report event
        let stateEvents = delivered.filter { $0.event.eventType == .stateReport }
        XCTAssertGreaterThanOrEqual(stateEvents.count, 1)
        
        try await dispatcher.stop()
    }
    
    func testStorageProviderProgressEventGeneration() async throws {
        let storage = InMemoryUPSStorageProvider()
        let subscriptionManager = InMemorySubscriptionManager()
        let deliveryService = LoggingEventDeliveryService()
        let dispatcher = EventDispatcher(
            subscriptionManager: subscriptionManager,
            deliveryService: deliveryService
        )
        
        await storage.setEventDispatcher(dispatcher)
        try await dispatcher.start()
        
        // Subscribe
        _ = try await subscriptionManager.subscribe(
            aeTitle: "SCU1",
            workitemUID: "1.2.3.4.5",
            deletionLock: false,
            eventTypes: [.progressReport]
        )
        
        // Create workitem
        let workitem = Workitem(workitemUID: "1.2.3.4.5", state: .scheduled)
        try await storage.createWorkitem(workitem)
        
        // Update progress
        let progress = ProgressInformation(progressPercentage: 50)
        try await storage.updateProgress(workitemUID: "1.2.3.4.5", progress: progress)
        
        // Give dispatcher time to process
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Check that progress event was generated
        let delivered = await deliveryService.getDeliveredEvents()
        let progressEvents = delivered.filter { $0.event.eventType == .progressReport }
        XCTAssertGreaterThanOrEqual(progressEvents.count, 1)
        
        try await dispatcher.stop()
    }
}
