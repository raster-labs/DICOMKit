// NetworkingModelTests.swift
// DICOMStudioTests

import Testing
@testable import DICOMStudio
import DICOMNetwork
import Foundation

@Suite("Networking Model Tests")
struct NetworkingModelTests {

    // MARK: - NetworkingTab

    @Test("NetworkingTab all cases have non-empty display names")
    func testNetworkingTabDisplayNames() {
        for tab in NetworkingTab.allCases {
            #expect(!tab.displayName.isEmpty)
        }
    }

    @Test("NetworkingTab all cases have non-empty SF symbols")
    func testNetworkingTabSFSymbols() {
        for tab in NetworkingTab.allCases {
            #expect(!tab.sfSymbol.isEmpty)
        }
    }

    @Test("NetworkingTab has 9 cases")
    func testNetworkingTabCaseCount() {
        #expect(NetworkingTab.allCases.count == 9)
    }

    // MARK: - TLSMode

    @Test("TLSMode none is not enabled")
    func testTLSModeNoneNotEnabled() {
        #expect(TLSMode.none.isEnabled == false)
    }

    @Test("TLSMode bcp195 is enabled")
    func testTLSMode12Enabled() {
        #expect(TLSMode.bcp195.isEnabled == true)
    }

    @Test("TLSMode mtls requires client certificate")
    func testTLSModeMTLSRequiresCert() {
        #expect(TLSMode.mtls.requiresClientCertificate == true)
    }

    @Test("TLSMode modifiedBCP195 does not require client certificate")
    func testTLSModeTLS13NoCert() {
        #expect(TLSMode.modifiedBCP195.requiresClientCertificate == false)
    }

    @Test("TLSMode all cases have non-empty display names")
    func testTLSModeDisplayNames() {
        for mode in TLSMode.allCases {
            #expect(!mode.displayName.isEmpty)
        }
    }

    // MARK: - ServerConnectionStatus

    @Test("ServerConnectionStatus all cases have non-empty display names")
    func testServerConnectionStatusDisplayNames() {
        for status in [ServerConnectionStatus.unknown, .testing, .online, .offline, .error] {
            #expect(!status.displayName.isEmpty)
        }
    }

    @Test("ServerConnectionStatus all cases have non-empty SF symbols")
    func testServerConnectionStatusSFSymbols() {
        for status in [ServerConnectionStatus.unknown, .testing, .online, .offline, .error] {
            #expect(!status.sfSymbol.isEmpty)
        }
    }

    // MARK: - PACSServerProfile

    @Test("PACSServerProfile default port is 11112")
    func testPACSServerProfileDefaultPort() {
        let profile = PACSServerProfile(name: "Test", host: "localhost",
                                        remoteAETitle: "ORTHANC", localAETitle: "DS")
        #expect(profile.port == 11112)
    }

    @Test("PACSServerProfile default TLS mode is none")
    func testPACSServerProfileDefaultTLS() {
        let profile = PACSServerProfile(name: "Test", host: "localhost",
                                        remoteAETitle: "ORTHANC", localAETitle: "DS")
        #expect(profile.tlsMode == .none)
    }

    @Test("PACSServerProfile default status is unknown")
    func testPACSServerProfileDefaultStatus() {
        let profile = PACSServerProfile(name: "Test", host: "localhost",
                                        remoteAETitle: "ORTHANC", localAETitle: "DS")
        #expect(profile.status == .unknown)
    }

    @Test("PACSServerProfile isDefault flag is false by default")
    func testPACSServerProfileNotDefaultByDefault() {
        let profile = PACSServerProfile(name: "Test", host: "localhost",
                                        remoteAETitle: "ORTHANC", localAETitle: "DS")
        #expect(profile.isDefault == false)
    }

    @Test("PACSServerProfile equality reflects all fields")
    func testPACSServerProfileEquality() {
        let id = UUID()
        let p1 = PACSServerProfile(id: id, name: "A", host: "host1",
                                   remoteAETitle: "AE1", localAETitle: "DS")
        let p2 = PACSServerProfile(id: id, name: "A", host: "host1",
                                   remoteAETitle: "AE1", localAETitle: "DS")
        #expect(p1 == p2)
    }

    // MARK: - EchoResult

    @Test("EchoResult success stores latency")
    func testEchoResultSuccessStoresLatency() {
        let id = UUID()
        let result = EchoResult(serverProfileID: id, serverName: "Server",
                                success: true, latencyMs: 42.5)
        #expect(result.success == true)
        #expect(result.latencyMs == 42.5)
        #expect(result.errorMessage == nil)
    }

    @Test("EchoResult failure stores error message")
    func testEchoResultFailureStoresError() {
        let id = UUID()
        let result = EchoResult(serverProfileID: id, serverName: "Server",
                                success: false, latencyMs: nil, errorMessage: "Refused")
        #expect(result.success == false)
        #expect(result.latencyMs == nil)
        #expect(result.errorMessage == "Refused")
    }

    // MARK: - NetworkQueryLevel

    @Test("NetworkQueryLevel all cases have non-empty display names")
    func testNetworkQueryLevelDisplayNames() {
        for level in NetworkQueryLevel.allCases {
            #expect(!level.displayName.isEmpty)
        }
    }

    @Test("NetworkQueryLevel all cases have non-empty SF symbols")
    func testNetworkQueryLevelSFSymbols() {
        for level in NetworkQueryLevel.allCases {
            #expect(!level.sfSymbol.isEmpty)
        }
    }

    @Test("NetworkQueryLevel has 4 cases")
    func testNetworkQueryLevelCaseCount() {
        #expect(NetworkQueryLevel.allCases.count == 4)
    }

    // MARK: - QueryFilter

    @Test("QueryFilter default has no active filter")
    func testQueryFilterDefaultNoActiveFilter() {
        let filter = QueryFilter()
        #expect(filter.hasActiveFilter == false)
    }

    @Test("QueryFilter with patientName has active filter")
    func testQueryFilterWithPatientNameIsActive() {
        let filter = QueryFilter(patientName: "SMITH^JOHN")
        #expect(filter.hasActiveFilter == true)
    }

    @Test("QueryFilter default level is study")
    func testQueryFilterDefaultLevelIsStudy() {
        #expect(QueryFilter().level == .study)
    }

    // MARK: - TransferStatus

    @Test("TransferStatus pending can cancel")
    func testTransferStatusPendingCanCancel() {
        #expect(TransferStatus.pending.canCancel == true)
    }

    @Test("TransferStatus inProgress can pause")
    func testTransferStatusInProgressCanPause() {
        #expect(TransferStatus.inProgress.canPause == true)
    }

    @Test("TransferStatus paused can resume")
    func testTransferStatusPausedCanResume() {
        #expect(TransferStatus.paused.canResume == true)
    }

    @Test("TransferStatus failed can retry")
    func testTransferStatusFailedCanRetry() {
        #expect(TransferStatus.failed.canRetry == true)
    }

    @Test("TransferStatus completed cannot cancel")
    func testTransferStatusCompletedCannotCancel() {
        #expect(TransferStatus.completed.canCancel == false)
    }

    @Test("TransferStatus all cases have non-empty display names")
    func testTransferStatusDisplayNames() {
        for status in [TransferStatus.pending, .inProgress, .paused, .completed, .failed, .cancelled] {
            #expect(!status.displayName.isEmpty)
        }
    }

    // MARK: - DICOMStudio.TransferPriority

    @Test("DICOMStudio.TransferPriority ordering is low < normal < high")
    func testTransferPriorityOrdering() {
        #expect(DICOMStudio.TransferPriority.low < DICOMStudio.TransferPriority.normal)
        #expect(DICOMStudio.TransferPriority.normal < DICOMStudio.TransferPriority.high)
    }

    // MARK: - TransferItem

    @Test("TransferItem progress is clamped to 0-1")
    func testTransferItemProgressClamped() {
        let id = UUID()
        let item = TransferItem(
            label: "Test", studyInstanceUID: "1.2.3",
            serverProfileID: id, progress: 1.5)
        #expect(item.progress <= 1.0)
        let item2 = TransferItem(
            label: "Test", studyInstanceUID: "1.2.3",
            serverProfileID: id, progress: -0.5)
        #expect(item2.progress >= 0.0)
    }

    // MARK: - RetrieveMethod

    @Test("RetrieveMethod all cases have non-empty display names")
    func testRetrieveMethodDisplayNames() {
        for method in RetrieveMethod.allCases {
            #expect(!method.displayName.isEmpty)
        }
    }

    // MARK: - SendRetryConfig

    @Test("SendRetryConfig clamps maxRetries to 0")
    func testSendRetryConfigClampsNegativeRetries() {
        let config = SendRetryConfig(maxRetries: -1)
        #expect(config.maxRetries == 0)
    }

    @Test("SendRetryConfig default values are sensible")
    func testSendRetryConfigDefaults() {
        let config = SendRetryConfig.default
        #expect(config.maxRetries >= 0)
        #expect(config.initialDelaySeconds > 0)
        #expect(config.maxDelaySeconds >= config.initialDelaySeconds)
    }

    // MARK: - CircuitBreakerDisplayState

    @Test("CircuitBreakerDisplayState open blocks sending")
    func testCircuitBreakerOpenBlocks() {
        #expect(CircuitBreakerDisplayState.open.isBlocked == true)
    }

    @Test("CircuitBreakerDisplayState closed does not block")
    func testCircuitBreakerClosedDoesNotBlock() {
        #expect(CircuitBreakerDisplayState.closed.isBlocked == false)
    }

    @Test("CircuitBreakerDisplayState all cases have non-empty display names and SF symbols")
    func testCircuitBreakerDisplayNamesAndSymbols() {
        for state in CircuitBreakerDisplayState.allCases {
            #expect(!state.displayName.isEmpty)
            #expect(!state.sfSymbol.isEmpty)
        }
    }

    // MARK: - SendStatus

    @Test("SendStatus failed can retry")
    func testSendStatusFailedCanRetry() {
        #expect(SendStatus.failed.canRetry == true)
    }

    @Test("SendStatus completed cannot retry")
    func testSendStatusCompletedCannotRetry() {
        #expect(SendStatus.completed.canRetry == false)
    }

    // MARK: - DICOMStudio.ValidationLevel

    @Test("DICOMStudio.ValidationLevel all cases have non-empty display names and descriptions")
    func testValidationLevelDisplayNamesAndDescriptions() {
        for level in DICOMStudio.ValidationLevel.allCases {
            #expect(!level.displayName.isEmpty)
            #expect(!level.description.isEmpty)
        }
    }

    // MARK: - MWLWorklistItem

    @Test("MWLWorklistItem stores all required fields")
    func testMWLWorklistItemFields() {
        let item = MWLWorklistItem(
            patientName: "DOE^JOHN",
            patientID: "P001",
            accessionNumber: "ACC001",
            requestedProcedureID: "RP001",
            requestedProcedureDescription: "Chest CT",
            scheduledStationAETitle: "CT1",
            scheduledProcedureStepStartDate: "20260101",
            modality: "CT"
        )
        #expect(item.patientName == "DOE^JOHN")
        #expect(item.modality == "CT")
        #expect(item.scheduledStationAETitle == "CT1")
    }

    // MARK: - DICOMStudio.MPPSStatus

    @Test("DICOMStudio.MPPSStatus inProgress can complete and discontinue")
    func testMPPSStatusInProgressTransitions() {
        #expect(DICOMStudio.MPPSStatus.inProgress.canComplete == true)
        #expect(DICOMStudio.MPPSStatus.inProgress.canDiscontinue == true)
    }

    @Test("DICOMStudio.MPPSStatus completed cannot complete again")
    func testMPPSStatusCompletedCannotTransition() {
        #expect(DICOMStudio.MPPSStatus.completed.canComplete == false)
        #expect(DICOMStudio.MPPSStatus.completed.canDiscontinue == false)
    }

    @Test("DICOMStudio.MPPSStatus all cases have non-empty display names and SF symbols")
    func testMPPSStatusDisplayNamesAndSymbols() {
        for status in DICOMStudio.MPPSStatus.allCases {
            #expect(!status.displayName.isEmpty)
            #expect(!status.sfSymbol.isEmpty)
        }
    }

    // MARK: - MPPSItem

    @Test("MPPSItem numberOfSeries clamped to 0")
    func testMPPSItemNumberOfSeriesClamped() {
        let item = MPPSItem(
            patientName: "SMITH^JANE", patientID: "P002",
            performedProcedureStepID: "PPS1",
            performedProcedureStepDescription: "Chest CT",
            performedStationAETitle: "CT1", modality: "CT",
            numberOfSeries: -5, numberOfInstances: -10
        )
        #expect(item.numberOfSeries == 0)
        #expect(item.numberOfInstances == 0)
    }

    // MARK: - Print Priority / Medium Type / Film Size (DICOMNetwork's, P-STUDIO-PRINT-ENUMS)

    @Test("DICOMNetwork.PrintPriority all cases have non-empty display names")
    func testPrintPriorityDisplayNames() {
        for p in DICOMNetwork.PrintPriority.allCases { #expect(!p.displayName.isEmpty) }
    }

    @Test("DICOMNetwork.MediumType all cases have non-empty display names")
    func testPrintMediumTypeDisplayNames() {
        for m in DICOMNetwork.MediumType.allCases { #expect(!m.displayName.isEmpty) }
    }

    @Test("Medium Type picker values are the 5 PS3.3 2026a Table C.13-1 Defined Terms, MAMMO included (D22)")
    func testPrintMediumTypeTerms() {
        #expect(DICOMNetwork.MediumType.paper.rawValue == "PAPER")
        #expect(DICOMNetwork.MediumType.clearFilm.rawValue == "CLEAR FILM")
        #expect(DICOMNetwork.MediumType.blueFilm.rawValue == "BLUE FILM")
        #expect(DICOMNetwork.MediumType.blueFilm.displayName == "Blue Film")
        #expect(DICOMNetwork.MediumType.mammoClearFilm.displayName == "Mammo Clear Film")
        #expect(DICOMNetwork.MediumType.mammoBlueFilm.displayName == "Mammo Blue Film")
        let terms = ["PAPER", "CLEAR FILM", "BLUE FILM", "MAMMO CLEAR FILM", "MAMMO BLUE FILM"]
        #expect(DICOMNetwork.MediumType.allCases.map(\.rawValue) == terms)
    }

    @Test("Print Priority values are the Table C.13-1 Print Priority terms")
    func testPrintPriorityTerms() {
        #expect(DICOMNetwork.PrintPriority.allCases.map(\.rawValue) == ["HIGH", "MED", "LOW"])
        #expect(DICOMNetwork.PrintPriority.medium.displayName == "Medium")
    }

    @Test("Film Size values are the 12 Table C.13-3 Film Size ID terms, each with a display name")
    func testPrintFilmSizeTerms() {
        #expect(DICOMNetwork.FilmSize.allCases.map(\.rawValue) == [
            "8INX10IN", "8_5INX11IN", "10INX12IN", "10INX14IN", "11INX14IN", "11INX17IN",
            "14INX14IN", "14INX17IN", "24CMX24CM", "24CMX30CM", "A4", "A3"])
        #expect(DICOMNetwork.FilmSize.size14InX17In.displayName == "14\" × 17\"")
        #expect(Set(DICOMNetwork.FilmSize.allCases.map(\.displayName)).count == 12)
    }

    // MARK: - FilmLayout

    @Test("FilmLayout standard1x1 has cellCount 1")
    func testFilmLayout1x1CellCount() {
        #expect(FilmLayout.standard1x1.cellCount == 1)
    }

    @Test("FilmLayout standard2x2 has cellCount 4")
    func testFilmLayout2x2CellCount() {
        #expect(FilmLayout.standard2x2.cellCount == 4)
    }

    @Test("FilmLayout standard4x5 has cellCount 20")
    func testFilmLayout4x5CellCount() {
        #expect(FilmLayout.standard4x5.cellCount == 20)
    }

    @Test("FilmLayout all cases have non-empty display names and raw values")
    func testFilmLayoutDisplayNames() {
        for layout in FilmLayout.allCases {
            #expect(!layout.displayName.isEmpty)
            #expect(!layout.rawValue.isEmpty)
        }
    }

    @Test("FilmLayout raw values are Image Display Format STANDARD\\C,R — columns first (PS3.3 C.13.3) — and agree with PrintLayout")
    func testFilmLayoutImageDisplayFormat() {
        for layout in FilmLayout.allCases {
            #expect(layout.rawValue == "STANDARD\\\(layout.columns),\(layout.rows)")
            #expect(layout.cellCount == layout.rows * layout.columns)
            // What the Networking panel now hands to DICOMPrintService.printImages(layout:).
            let network = PrintLayout(rows: layout.rows, columns: layout.columns)
            #expect(network.imageDisplayFormat == layout.rawValue)
        }
    }

    // MARK: - NetworkPrintJobState

    @Test("NetworkPrintJobState all cases have non-empty display names and SF symbols")
    func testPrintJobStatusDisplayNamesAndSymbols() {
        for status in [NetworkPrintJobState.pending, .printing, .completed, .failed] {
            #expect(!status.displayName.isEmpty)
            #expect(!status.sfSymbol.isEmpty)
        }
    }

    @Test("NetworkPrintJobState raw values are the PS3.3 Table C.13-8 Execution Status terms (D22)")
    func testPrintJobStatusExecutionStatusTerms() {
        #expect(NetworkPrintJobState.pending.rawValue == "PENDING")
        #expect(NetworkPrintJobState.printing.rawValue == "PRINTING")
        #expect(NetworkPrintJobState.completed.rawValue == "DONE")
        #expect(NetworkPrintJobState.failed.rawValue == "FAILURE")
    }

    @Test("DICOMStudio.MPPSStatus raw values are the PS3.3 C.4.14 Performed Procedure Step Status terms, as DICOMNetwork spells them")
    func testMPPSStatusTerms() {
        #expect(DICOMStudio.MPPSStatus.inProgress.rawValue == "IN PROGRESS")
        #expect(DICOMStudio.MPPSStatus.completed.rawValue == "COMPLETED")
        #expect(DICOMStudio.MPPSStatus.discontinued.rawValue == "DISCONTINUED")
        for status in DICOMStudio.MPPSStatus.allCases {
            #expect(DICOMNetwork.MPPSStatus(rawValue: status.rawValue) != nil)
        }
    }

    @Test("NetworkQueryLevel raw values are the PS3.4 Table C.6.1-1 Query/Retrieve Level values")
    func testQueryLevelTerms() {
        #expect(NetworkQueryLevel.allCases.map(\.rawValue) == ["PATIENT", "STUDY", "SERIES", "IMAGE"])
    }

    // MARK: - PrintJob

    @Test("PrintJob numberOfCopies clamped to 1")
    func testPrintJobCopiesClamped() {
        let job = PrintJob(label: "Test", printerServerProfileID: UUID(),
                           numberOfCopies: 0)
        #expect(job.numberOfCopies == 1)
    }

    // MARK: - NetworkMonitoringStats

    @Test("NetworkMonitoringStats successRate is 1.0 with no operations")
    func testMonitoringStatsSuccessRateEmpty() {
        let stats = NetworkMonitoringStats()
        #expect(stats.successRate == 1.0)
    }

    @Test("NetworkMonitoringStats successRate is 0.5 with half failed")
    func testMonitoringStatsSuccessRateHalf() {
        let stats = NetworkMonitoringStats(totalOperations: 10, totalFailedOperations: 5)
        #expect(abs(stats.successRate - 0.5) < 0.001)
    }

    // MARK: - AuditEventOutcome

    @Test("AuditEventOutcome all cases have non-empty display names and SF symbols")
    func testAuditEventOutcomeDisplayNamesAndSymbols() {
        for outcome in AuditEventOutcome.allCases {
            #expect(!outcome.displayName.isEmpty)
            #expect(!outcome.sfSymbol.isEmpty)
        }
    }

    // MARK: - AuditNetworkEventType

    @Test("AuditNetworkEventType all cases have non-empty display names")
    func testAuditNetworkEventTypeDisplayNames() {
        for eventType in AuditNetworkEventType.allCases {
            #expect(!eventType.displayName.isEmpty)
        }
    }

    // MARK: - AuditLogEntry

    @Test("AuditLogEntry stores all fields")
    func testAuditLogEntryFields() {
        let entry = AuditLogEntry(
            eventType: .echo,
            outcome: .success,
            remoteEntity: "PACS",
            localAETitle: "DS",
            detail: "Latency 10 ms"
        )
        #expect(entry.eventType == .echo)
        #expect(entry.outcome == .success)
        #expect(entry.remoteEntity == "PACS")
        #expect(entry.localAETitle == "DS")
        #expect(entry.detail == "Latency 10 ms")
    }

    // MARK: - NetworkErrorCategory

    @Test("NetworkErrorCategory transient is retryable")
    func testNetworkErrorCategoryTransientIsRetryable() {
        #expect(NetworkErrorCategory.transient.isRetryable == true)
    }

    @Test("NetworkErrorCategory permanent is not retryable")
    func testNetworkErrorCategoryPermanentNotRetryable() {
        #expect(NetworkErrorCategory.permanent.isRetryable == false)
    }

    @Test("NetworkErrorCategory all cases have non-empty recovery suggestions")
    func testNetworkErrorCategoryRecoverySuggestions() {
        for cat in NetworkErrorCategory.allCases {
            #expect(!cat.recoverySuggestion.isEmpty)
        }
    }

    // MARK: - BandwidthLimit

    @Test("BandwidthLimit disabled has nil effective limit")
    func testBandwidthLimitDisabledNil() {
        let limit = BandwidthLimit(isEnabled: false, maxBytesPerSecond: 1_000_000)
        #expect(limit.effectiveLimit == nil)
    }

    @Test("BandwidthLimit enabled with value returns that value")
    func testBandwidthLimitEnabledReturnsValue() {
        let limit = BandwidthLimit(isEnabled: true, maxBytesPerSecond: 1_000_000)
        #expect(limit.effectiveLimit == 1_000_000)
    }

    @Test("BandwidthLimit enabled with zero bytes has nil effective limit")
    func testBandwidthLimitEnabledZeroIsNil() {
        let limit = BandwidthLimit(isEnabled: true, maxBytesPerSecond: 0)
        #expect(limit.effectiveLimit == nil)
    }

    @Test("BandwidthLimit clamps negative bytes to 0")
    func testBandwidthLimitClampsNegative() {
        let limit = BandwidthLimit(isEnabled: true, maxBytesPerSecond: -100)
        #expect(limit.maxBytesPerSecond == 0)
    }
}
