// DICOMwebModelTests.swift
// DICOMStudioTests

import Testing
@testable import DICOMStudio
import Foundation

@Suite("DICOMweb Model Tests")
struct DICOMwebModelTests {

    // MARK: - DICOMwebTab

    @Test("DICOMwebTab all cases have non-empty display names")
    func testDICOMwebTabDisplayNames() {
        for tab in DICOMwebTab.allCases {
            #expect(!tab.displayName.isEmpty)
        }
    }

    @Test("DICOMwebTab all cases have non-empty SF symbols")
    func testDICOMwebTabSFSymbols() {
        for tab in DICOMwebTab.allCases {
            #expect(!tab.sfSymbol.isEmpty)
        }
    }

    @Test("DICOMwebTab has 7 cases")
    func testDICOMwebTabCaseCount() {
        #expect(DICOMwebTab.allCases.count == 7)
    }

    // MARK: - DICOMwebAuthMethod

    @Test("DICOMwebAuthMethod all cases have non-empty display names")
    func testDICOMwebAuthMethodDisplayNames() {
        for method in DICOMwebAuthMethod.allCases {
            #expect(!method.displayName.isEmpty)
        }
    }

    @Test("DICOMwebAuthMethod has 5 cases")
    func testDICOMwebAuthMethodCaseCount() {
        #expect(DICOMwebAuthMethod.allCases.count == 5)
    }

    // MARK: - DICOMwebTLSMode

    @Test("DICOMwebTLSMode none is not enabled")
    func testDICOMwebTLSModeNoneNotEnabled() {
        #expect(DICOMwebTLSMode.none.isEnabled == false)
    }

    @Test("DICOMwebTLSMode strict is enabled")
    func testDICOMwebTLSModeStrictEnabled() {
        #expect(DICOMwebTLSMode.strict.isEnabled == true)
    }

    @Test("DICOMwebTLSMode development allows self-signed")
    func testDICOMwebTLSModeDevelopmentAllowsSelfSigned() {
        #expect(DICOMwebTLSMode.development.allowsSelfSigned == true)
    }

    @Test("DICOMwebTLSMode compatible does not allow self-signed")
    func testDICOMwebTLSModeCompatibleNoSelfSigned() {
        #expect(DICOMwebTLSMode.compatible.allowsSelfSigned == false)
    }

    @Test("DICOMwebTLSMode strict does not allow self-signed")
    func testDICOMwebTLSModeStrictNoSelfSigned() {
        #expect(DICOMwebTLSMode.strict.allowsSelfSigned == false)
    }

    @Test("DICOMwebTLSMode none does not allow self-signed")
    func testDICOMwebTLSModeNoneNoSelfSigned() {
        #expect(DICOMwebTLSMode.none.allowsSelfSigned == false)
    }

    @Test("DICOMwebTLSMode has 4 cases")
    func testDICOMwebTLSModeCaseCount() {
        #expect(DICOMwebTLSMode.allCases.count == 4)
    }

    // MARK: - DICOMwebConnectionStatus

    @Test("DICOMwebConnectionStatus online isConnected")
    func testDICOMwebConnectionStatusOnlineIsConnected() {
        #expect(DICOMwebConnectionStatus.online.isConnected == true)
    }

    @Test("DICOMwebConnectionStatus offline is not connected")
    func testDICOMwebConnectionStatusOfflineNotConnected() {
        #expect(DICOMwebConnectionStatus.offline.isConnected == false)
    }

    @Test("DICOMwebConnectionStatus unknown is not connected")
    func testDICOMwebConnectionStatusUnknownNotConnected() {
        #expect(DICOMwebConnectionStatus.unknown.isConnected == false)
    }

    @Test("DICOMwebConnectionStatus all cases have non-empty display names and SF symbols")
    func testDICOMwebConnectionStatusDisplayNamesAndSymbols() {
        for status in DICOMwebConnectionStatus.allCases {
            #expect(!status.displayName.isEmpty)
            #expect(!status.sfSymbol.isEmpty)
        }
    }

    // MARK: - DICOMwebServiceType

    @Test("DICOMwebServiceType all cases have non-empty display names and abbreviations")
    func testDICOMwebServiceTypeDisplayNamesAndAbbreviations() {
        for type_ in DICOMwebServiceType.allCases {
            #expect(!type_.displayName.isEmpty)
            #expect(!type_.abbreviation.isEmpty)
        }
    }

    @Test("DICOMwebServiceType has 4 cases")
    func testDICOMwebServiceTypeCaseCount() {
        #expect(DICOMwebServiceType.allCases.count == 4)
    }

    // MARK: - DICOMwebServerProfile

    @Test("DICOMwebServerProfile default id is a UUID")
    func testDICOMwebServerProfileDefaultID() {
        let p1 = DICOMwebServerProfile()
        let p2 = DICOMwebServerProfile()
        #expect(p1.id != p2.id)
    }

    @Test("DICOMwebServerProfile isConfigured false for empty URL")
    func testDICOMwebServerProfileNotConfiguredWhenEmptyURL() {
        let profile = DICOMwebServerProfile(baseURL: "")
        #expect(profile.isConfigured == false)
    }

    @Test("DICOMwebServerProfile isConfigured true for valid URL")
    func testDICOMwebServerProfileConfiguredForValidURL() {
        let profile = DICOMwebServerProfile(baseURL: "https://example.com")
        #expect(profile.isConfigured == true)
    }

    @Test("DICOMwebServerProfile isDefault defaults to false")
    func testDICOMwebServerProfileIsDefaultFalse() {
        let profile = DICOMwebServerProfile()
        #expect(profile.isDefault == false)
    }

    @Test("DICOMwebServerProfile connection status defaults to unknown")
    func testDICOMwebServerProfileDefaultConnectionStatus() {
        let profile = DICOMwebServerProfile()
        #expect(profile.connectionStatus == .unknown)
    }

    @Test("DICOMwebServerProfile lastConnectionError defaults to nil")
    func testDICOMwebServerProfileLastConnectionErrorNil() {
        let profile = DICOMwebServerProfile()
        #expect(profile.lastConnectionError == nil)
    }

    // MARK: - QIDOQueryLevel

    @Test("QIDOQueryLevel all cases have non-empty display names")
    func testQIDOQueryLevelDisplayNames() {
        for level in QIDOQueryLevel.allCases {
            #expect(!level.displayName.isEmpty)
        }
    }

    @Test("QIDOQueryLevel has 3 cases")
    func testQIDOQueryLevelCaseCount() {
        #expect(QIDOQueryLevel.allCases.count == 3)
    }

    // MARK: - QIDOQueryParams

    @Test("QIDOQueryParams isEmpty true when all fields are blank")
    func testQIDOQueryParamsIsEmptyWhenAllBlank() {
        let params = QIDOQueryParams()
        #expect(params.isEmpty == true)
    }

    @Test("QIDOQueryParams isEmpty false when patientName is set")
    func testQIDOQueryParamsNotEmptyWithPatientName() {
        let params = QIDOQueryParams(patientName: "SMITH*")
        #expect(params.isEmpty == false)
    }

    @Test("QIDOQueryParams default limit is 100")
    func testQIDOQueryParamsDefaultLimit() {
        #expect(QIDOQueryParams().limit == 100)
    }

    @Test("QIDOQueryParams default offset is 0")
    func testQIDOQueryParamsDefaultOffset() {
        #expect(QIDOQueryParams().offset == 0)
    }

    @Test("QIDOQueryParams default fuzzyMatching is false")
    func testQIDOQueryParamsDefaultFuzzyMatching() {
        #expect(QIDOQueryParams().fuzzyMatching == false)
    }

    // MARK: - QIDOResultItem

    @Test("QIDOResultItem id is unique UUID per instance")
    func testQIDOResultItemUniqueID() {
        let r1 = QIDOResultItem()
        let r2 = QIDOResultItem()
        #expect(r1.id != r2.id)
    }

    // MARK: - WADOProtocol

    @Test("WADOProtocol has 2 cases")
    func testWADOProtocolCaseCount() {
        #expect(WADOProtocol.allCases.count == 2)
    }

    @Test("WADOProtocol raw values")
    func testWADOProtocolRawValues() {
        #expect(WADOProtocol.wadoRS.rawValue == "WADO_RS")
        #expect(WADOProtocol.wadoURI.rawValue == "WADO_URI")
    }

    @Test("WADOProtocol displayName non-empty")
    func testWADOProtocolDisplayNames() {
        for proto in WADOProtocol.allCases {
            #expect(!proto.displayName.isEmpty)
        }
    }

    @Test("WADOProtocol protocolDescription non-empty")
    func testWADOProtocolDescriptions() {
        for proto in WADOProtocol.allCases {
            #expect(!proto.protocolDescription.isEmpty)
        }
    }

    // MARK: - WADORetrieveMode

    @Test("WADORetrieveMode all cases have non-empty display names")
    func testWADORetrieveModeDisplayNames() {
        for mode in WADORetrieveMode.allCases {
            #expect(!mode.displayName.isEmpty)
        }
    }

    @Test("WADORetrieveMode has 6 cases")
    func testWADORetrieveModeCaseCount() {
        #expect(WADORetrieveMode.allCases.count == 6)
    }

    // MARK: - WADORetrieveStatus

    @Test("WADORetrieveStatus queued is not terminal")
    func testWADORetrieveStatusQueuedNotTerminal() {
        #expect(WADORetrieveStatus.queued.isTerminal == false)
    }

    @Test("WADORetrieveStatus completed is terminal")
    func testWADORetrieveStatusCompletedIsTerminal() {
        #expect(WADORetrieveStatus.completed.isTerminal == true)
    }

    @Test("WADORetrieveStatus failed is terminal")
    func testWADORetrieveStatusFailedIsTerminal() {
        #expect(WADORetrieveStatus.failed.isTerminal == true)
    }

    @Test("WADORetrieveStatus cancelled is terminal")
    func testWADORetrieveStatusCancelledIsTerminal() {
        #expect(WADORetrieveStatus.cancelled.isTerminal == true)
    }

    @Test("WADORetrieveStatus inProgress is not terminal")
    func testWADORetrieveStatusInProgressNotTerminal() {
        #expect(WADORetrieveStatus.inProgress.isTerminal == false)
    }

    // MARK: - WADORetrieveJob

    @Test("WADORetrieveJob default status is queued")
    func testWADORetrieveJobDefaultStatus() {
        let job = WADORetrieveJob()
        #expect(job.status == .queued)
    }

    @Test("WADORetrieveJob progressFraction is nil when totalBytes nil")
    func testWADORetrieveJobProgressFractionNilWhenTotalBytesNil() {
        let job = WADORetrieveJob(totalBytes: nil)
        #expect(job.progressFraction == nil)
    }

    @Test("WADORetrieveJob progressFraction is 0.5 when half bytes received")
    func testWADORetrieveJobProgressFractionHalf() {
        let job = WADORetrieveJob(bytesReceived: 1, totalBytes: 2)
        #expect(job.progressFraction == 0.5)
    }

    // MARK: - STOWDuplicateHandling

    @Test("STOWDuplicateHandling all cases have non-empty display names")
    func testSTOWDuplicateHandlingDisplayNames() {
        for handling in STOWDuplicateHandling.allCases {
            #expect(!handling.displayName.isEmpty)
        }
    }

    @Test("STOWDuplicateHandling has 3 cases")
    func testSTOWDuplicateHandlingCaseCount() {
        #expect(STOWDuplicateHandling.allCases.count == 3)
    }

    // MARK: - STOWUploadStatus

    @Test("STOWUploadStatus queued is not terminal")
    func testSTOWUploadStatusQueuedNotTerminal() {
        #expect(STOWUploadStatus.queued.isTerminal == false)
    }

    @Test("STOWUploadStatus completed is terminal")
    func testSTOWUploadStatusCompletedIsTerminal() {
        #expect(STOWUploadStatus.completed.isTerminal == true)
    }

    @Test("STOWUploadStatus failed is terminal")
    func testSTOWUploadStatusFailedIsTerminal() {
        #expect(STOWUploadStatus.failed.isTerminal == true)
    }

    @Test("STOWUploadStatus rejected is terminal")
    func testSTOWUploadStatusRejectedIsTerminal() {
        #expect(STOWUploadStatus.rejected.isTerminal == true)
    }

    // MARK: - STOWUploadJob

    @Test("STOWUploadJob progressFraction is 0 when totalBytes is 0")
    func testSTOWUploadJobProgressFractionZeroWhenNoBytes() {
        let job = STOWUploadJob(bytesUploaded: 0, totalBytes: 0)
        #expect(job.progressFraction == 0)
    }

    @Test("STOWUploadJob progressFraction is 0.5 when half bytes uploaded")
    func testSTOWUploadJobProgressFractionHalf() {
        let job = STOWUploadJob(bytesUploaded: 500, totalBytes: 1000)
        #expect(abs(job.progressFraction - 0.5) < 0.001)
    }

    // MARK: - UPSState

    @Test("UPSState scheduled allowedTransitions contains inProgress")
    func testUPSStateScheduledAllowsInProgress() {
        #expect(WebUPSState.scheduled.allowedTransitions.contains(.inProgress))
    }

    @Test("UPSState inProgress allowedTransitions contains completed and cancelled")
    func testUPSStateInProgressAllowsCompletedAndCancelled() {
        #expect(WebUPSState.inProgress.allowedTransitions.contains(.completed))
        #expect(WebUPSState.inProgress.allowedTransitions.contains(.canceled))
    }

    @Test("UPSState completed allowedTransitions is empty")
    func testUPSStateCompletedNoTransitions() {
        #expect(WebUPSState.completed.allowedTransitions.isEmpty)
    }

    @Test("UPSState cancelled allowedTransitions is empty")
    func testUPSStateCancelledNoTransitions() {
        #expect(WebUPSState.canceled.allowedTransitions.isEmpty)
    }

    @Test("UPSState all cases have non-empty display names")
    func testUPSStateDisplayNames() {
        for state in WebUPSState.allCases {
            #expect(!state.displayName.isEmpty)
        }
    }

    // MARK: - UPSPriority

    @Test("UPSPriority all cases have non-empty display names and SF symbols")
    func testUPSPriorityDisplayNamesAndSymbols() {
        for priority in UPSPriority.allCases {
            #expect(!priority.displayName.isEmpty)
            #expect(!priority.sfSymbol.isEmpty)
        }
    }

    @Test("UPSPriority has 3 cases")
    func testUPSPriorityCaseCount() {
        #expect(UPSPriority.allCases.count == 3)
    }

    // MARK: - UPSEventType

    @Test("UPSEventType all cases have non-empty display names")
    func testUPSEventTypeDisplayNames() {
        for eventType in UPSEventType.allCases {
            #expect(!eventType.displayName.isEmpty)
        }
    }

    @Test("UPSEventType has 4 cases")
    func testUPSEventTypeCaseCount() {
        #expect(UPSEventType.allCases.count == 4)
    }

    // MARK: - UPSEventSubscription

    @Test("UPSEventSubscription isGlobal true when workitemUID is nil")
    func testUPSEventSubscriptionIsGlobalWhenNil() {
        let sub = UPSEventSubscription(workitemUID: nil)
        #expect(sub.isGlobal == true)
    }

    @Test("UPSEventSubscription isGlobal false when workitemUID is set")
    func testUPSEventSubscriptionNotGlobalWhenSet() {
        let sub = UPSEventSubscription(workitemUID: "1.2.3.4")
        #expect(sub.isGlobal == false)
    }

    @Test("UPSEventSubscription isActive defaults to false")
    func testUPSEventSubscriptionIsActiveDefaultFalse() {
        let sub = UPSEventSubscription()
        #expect(sub.isActive == false)
    }

    // MARK: - UPSWorkitem

    @Test("UPSWorkitem completionPercentage is 0 when default")
    func testUPSWorkitemCompletionPercentageDefaultZero() {
        let item = UPSWorkitem()
        #expect(item.completionPercentage == 0)
    }

    // MARK: - DICOMwebCacheStats

    @Test("DICOMwebCacheStats hitRate is 0.0 when no hits or misses")
    func testDICOMwebCacheStatsHitRateZeroWhenEmpty() {
        let stats = DICOMwebCacheStats()
        #expect(stats.hitRate == 0.0)
    }

    @Test("DICOMwebCacheStats hitRate is 0.75 for 3 hits and 1 miss")
    func testDICOMwebCacheStatsHitRate75() {
        let stats = DICOMwebCacheStats(hitCount: 3, missCount: 1)
        #expect(abs(stats.hitRate - 0.75) < 0.001)
    }

    @Test("DICOMwebCacheStats utilizationFraction is 0.5 for half capacity")
    func testDICOMwebCacheStatsUtilizationHalf() {
        let stats = DICOMwebCacheStats(
            currentSizeBytes: 50 * 1024 * 1024,
            maxSizeBytes: 100 * 1024 * 1024
        )
        #expect(abs(stats.utilizationFraction - 0.5) < 0.001)
    }

    // MARK: - DICOMwebPerformanceStats

    @Test("DICOMwebPerformanceStats prefetchHitRate is 0 when no hits or misses")
    func testDICOMwebPerformanceStatsPrefetchHitRateZero() {
        let stats = DICOMwebPerformanceStats()
        #expect(stats.prefetchHitRate == 0)
    }

    @Test("DICOMwebPerformanceStats errorRate is 0 when no errors")
    func testDICOMwebPerformanceStatsErrorRateZero() {
        let stats = DICOMwebPerformanceStats(totalRequestCount: 10, errorCount: 0)
        #expect(stats.errorRate == 0)
    }

    @Test("DICOMwebPerformanceStats errorRate is 0.1 for 1 error in 10 requests")
    func testDICOMwebPerformanceStatsErrorRateTenPercent() {
        let stats = DICOMwebPerformanceStats(totalRequestCount: 10, errorCount: 1)
        #expect(abs(stats.errorRate - 0.1) < 0.001)
    }

    // MARK: - UPSEventChannelState

    @Test("UPSEventChannelState all cases have display names")
    func testUPSEventChannelStateDisplayNames() {
        for state in UPSEventChannelState.allCases {
            #expect(!state.displayName.isEmpty)
        }
    }

    @Test("UPSEventChannelState raw values match expected strings")
    func testUPSEventChannelStateRawValues() {
        #expect(UPSEventChannelState.disconnected.rawValue == "DISCONNECTED")
        #expect(UPSEventChannelState.connecting.rawValue == "CONNECTING")
        #expect(UPSEventChannelState.connected.rawValue == "CONNECTED")
        #expect(UPSEventChannelState.reconnecting.rawValue == "RECONNECTING")
        #expect(UPSEventChannelState.closed.rawValue == "CLOSED")
    }

    // MARK: - UPSReceivedEvent

    @Test("UPSReceivedEvent defaults are sensible")
    func testUPSReceivedEventDefaults() {
        let event = UPSReceivedEvent()
        #expect(event.eventType == .stateChange)
        #expect(event.workitemUID.isEmpty)
        #expect(event.transactionUID == nil)
        #expect(event.summary.isEmpty)
    }

    @Test("UPSReceivedEvent stores all properties")
    func testUPSReceivedEventProperties() {
        let date = Date()
        let event = UPSReceivedEvent(
            eventType: .progressChange,
            workitemUID: "1.2.3.4.5",
            transactionUID: "tx-123",
            receivedAt: date,
            summary: "Progress updated to 50%"
        )
        #expect(event.eventType == .progressChange)
        #expect(event.workitemUID == "1.2.3.4.5")
        #expect(event.transactionUID == "tx-123")
        #expect(event.receivedAt == date)
        #expect(event.summary == "Progress updated to 50%")
    }

    @Test("UPSReceivedEvent conforms to Identifiable")
    func testUPSReceivedEventIdentifiable() {
        let event1 = UPSReceivedEvent()
        let event2 = UPSReceivedEvent()
        #expect(event1.id != event2.id)
    }


    // MARK: - UPSState vs PS3.4 2026a Table CC.1.1-2 / PS3.3 C.30.1 (NEMA pins)

    @Test("WebUPSState.scheduled allows only IN PROGRESS as a Change State target (PS3.4 Table CC.1.1-2: CANCELED from SCHEDULED is C310H)")
    func testUPSStateScheduledChangeStateTargets() {
        #expect(WebUPSState.scheduled.allowedTransitions == [.inProgress])
        #expect(!WebUPSState.scheduled.allowedTransitions.contains(.canceled))
    }

    @Test("WebUPSState.inProgress allows exactly COMPLETED and CANCELED (PS3.4 Table CC.1.1-2)")
    func testUPSStateInProgressChangeStateTargets() {
        #expect(Set(WebUPSState.inProgress.allowedTransitions) == Set([.completed, .canceled]))
    }

    @Test("UPSState is never a target for SCHEDULED (PS3.4 Table CC.1.1-2 C303H; PS3.18 11.7.1.4)")
    func testUPSStateScheduledIsNeverATarget() {
        for state in WebUPSState.allCases {
            #expect(!state.allowedTransitions.contains(.scheduled))
        }
    }

    @Test("WebUPSState.dicomTerm is the PS3.3 C.30.1 Procedure Step State term")
    func testUPSStateDicomTerms() {
        #expect(WebUPSState.scheduled.dicomTerm == "SCHEDULED")
        #expect(WebUPSState.inProgress.dicomTerm == "IN PROGRESS")
        #expect(WebUPSState.completed.dicomTerm == "COMPLETED")
        #expect(WebUPSState.canceled.dicomTerm == "CANCELED")
        #expect(Set(WebUPSState.allCases.map(\.dicomTerm)) == Set(["SCHEDULED", "IN PROGRESS", "CANCELED", "COMPLETED"]))
    }

    @Test("WebUPSState.canceled displays the standard's spelling CANCELED (PS3.3 C.30.1)")
    func testUPSStateCanceledDisplayName() {
        #expect(WebUPSState.canceled.displayName == "Canceled")
    }

    @Test("UPSPriority raw values are the PS3.3 C.30.2 Scheduled Procedure Step Priority terms")
    func testUPSPriorityTerms() {
        #expect(Set(UPSPriority.allCases.map(\.rawValue)) == Set(["HIGH", "MEDIUM", "LOW"]))
    }
}
