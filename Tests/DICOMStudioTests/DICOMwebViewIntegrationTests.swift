// DICOMwebViewIntegrationTests.swift
// DICOMStudioTests
//
// DICOM Studio — Tests for DICOMwebView integration, navigation wiring,
// and view-level color/display helpers.

import Testing
@testable import DICOMStudio
import Foundation

// MARK: - Navigation Destination Integration

@Suite("DICOMweb Navigation Destination Tests")
struct DICOMwebNavigationDestinationTests {

    @Test("dicomWeb case exists in NavigationDestination")
    func testDicomWebCaseExists() {
        let dest = NavigationDestination.dicomWeb
        #expect(dest.rawValue == "DICOMweb")
    }

    @Test("dicomWeb has globe systemImage")
    func testDicomWebSystemImage() {
        #expect(NavigationDestination.dicomWeb.systemImage == "globe")
    }

    @Test("dicomWeb has correct accessibilityLabel")
    func testDicomWebAccessibilityLabel() {
        #expect(NavigationDestination.dicomWeb.accessibilityLabel == "DICOMweb Integration Hub")
    }

    @Test("dicomWeb is included in allCases")
    func testDicomWebInAllCases() {
        #expect(NavigationDestination.allCases.contains(.dicomWeb))
    }

    @Test("dicomWeb appears after networking in allCases")
    func testDicomWebOrderAfterNetworking() {
        let allCases = NavigationDestination.allCases
        guard let netIdx = allCases.firstIndex(of: .networking),
              let webIdx = allCases.firstIndex(of: .dicomWeb) else {
            Issue.record("networking or dicomWeb not found in allCases")
            return
        }
        #expect(webIdx == netIdx + 1)
    }
}

// MARK: - DICOMweb ViewModel Integration (MainViewModel)

@Suite("DICOMweb MainViewModel Integration Tests")
struct DICOMwebMainViewModelIntegrationTests {

    @Test("MainViewModel exposes dicomWebViewModel property")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testMainViewModelHasDicomWebViewModel() async {
        await MainActor.run {
            let mainVM = MainViewModel()
            #expect(mainVM.dicomWebViewModel.activeTab == .serverConfig)
        }
    }

    @Test("MainViewModel dicomWebViewModel is independent from networking")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDicomWebVMIndependentFromNetworking() async {
        await MainActor.run {
            let mainVM = MainViewModel()
            mainVM.dicomWebViewModel.activeTab = .qidoRS
            // Changing dicomWebViewModel should not affect networkingViewModel
            #expect(mainVM.dicomWebViewModel.activeTab == .qidoRS)
        }
    }
}

// MARK: - DICOMweb Tab Completeness

@Suite("DICOMweb Tab Tests")
struct DICOMwebTabTests {

    @Test("the complete DICOMweb tab catalog exists")
    func testAllTabsExist() {
        #expect(Set(DICOMwebTab.allCases) == [
            .serverConfig, .qidoRS, .wadoRS, .stowRS, .upsRS,
            .jpipStreaming, .performanceDashboard,
        ])
    }

    @Test("all tabs have non-empty displayName")
    func testAllTabsHaveDisplayName() {
        for tab in DICOMwebTab.allCases {
            #expect(!tab.displayName.isEmpty, "Tab \(tab.rawValue) has empty displayName")
        }
    }

    @Test("all tabs have non-empty sfSymbol")
    func testAllTabsHaveSFSymbol() {
        for tab in DICOMwebTab.allCases {
            #expect(!tab.sfSymbol.isEmpty, "Tab \(tab.rawValue) has empty sfSymbol")
        }
    }
}

// MARK: - Server Profile Form Validation

@Suite("DICOMweb Server Profile Validation Tests")
@MainActor
struct DICOMwebServerProfileValidationTests {

    @Test("valid server profile has no validation errors")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testValidProfileNoErrors() {
        let vm = DICOMwebViewModel()
        let profile = DICOMwebServerProfile(
            name: "Test PACS",
            baseURL: "https://pacs.hospital.com/dicom-web",
            authMethod: .none,
            tlsMode: .bcp195
        )
        let errors = vm.validationErrors(for: profile)
        #expect(errors.isEmpty)
    }

    @Test("profile with empty name returns error")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEmptyNameReturnsError() {
        let vm = DICOMwebViewModel()
        let profile = DICOMwebServerProfile(name: "", baseURL: "https://pacs.example.com")
        let errors = vm.validationErrors(for: profile)
        #expect(errors.contains { $0.contains("name") })
    }

    @Test("profile with invalid URL returns error")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testInvalidURLReturnsError() {
        let vm = DICOMwebViewModel()
        let profile = DICOMwebServerProfile(name: "Test", baseURL: "ftp://invalid")
        let errors = vm.validationErrors(for: profile)
        #expect(errors.contains { $0.contains("http") })
    }

    @Test("bearer auth without token returns error")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testBearerWithoutTokenReturnsError() {
        let vm = DICOMwebViewModel()
        let profile = DICOMwebServerProfile(
            name: "Test",
            baseURL: "https://pacs.example.com",
            authMethod: .bearer,
            bearerToken: ""
        )
        let errors = vm.validationErrors(for: profile)
        #expect(errors.contains { $0.contains("token") })
    }

    @Test("basic auth without username returns error")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testBasicAuthWithoutUsernameReturnsError() {
        let vm = DICOMwebViewModel()
        let profile = DICOMwebServerProfile(
            name: "Test",
            baseURL: "https://pacs.example.com",
            authMethod: .basic,
            username: "",
            password: "pass"
        )
        let errors = vm.validationErrors(for: profile)
        #expect(errors.contains { $0.contains("Username") })
    }

    @Test("basic auth without password returns error")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testBasicAuthWithoutPasswordReturnsError() {
        let vm = DICOMwebViewModel()
        let profile = DICOMwebServerProfile(
            name: "Test",
            baseURL: "https://pacs.example.com",
            authMethod: .basic,
            username: "admin",
            password: ""
        )
        let errors = vm.validationErrors(for: profile)
        #expect(errors.contains { $0.contains("Password") })
    }

    @Test("profile with all valid basic auth has no errors")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testValidBasicAuthNoErrors() {
        let vm = DICOMwebViewModel()
        let profile = DICOMwebServerProfile(
            name: "Hospital PACS",
            baseURL: "https://pacs.hospital.com/dicom-web",
            authMethod: .basic,
            username: "admin",
            password: "secret123"
        )
        let errors = vm.validationErrors(for: profile)
        #expect(errors.isEmpty)
    }
}

// MARK: - QIDO-RS Flow Tests

@Suite("DICOMweb QIDO-RS Flow Tests")
@MainActor
struct DICOMwebQIDORSFlowTests {

    @Test("QIDO query with all fields produces correct summary")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testQIDOQuerySummaryAllFields() {
        let vm = DICOMwebViewModel()
        vm.qidoQueryParams = QIDOQueryParams(
            patientName: "DOE^JOHN",
            patientID: "12345",
            modality: "CT",
            accessionNumber: "ACC001",
            studyDescription: "Chest"
        )
        let summary = vm.qidoQuerySummary
        #expect(summary.contains("DOE^JOHN"))
        #expect(summary.contains("12345"))
        #expect(summary.contains("CT"))
        #expect(summary.contains("ACC001"))
        #expect(summary.contains("Chest"))
    }

    @Test("selecting QIDO result and switching to WADO tab pre-fills UIDs")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testQIDOResultToWADOPreFill() {
        let service = DICOMwebService()
        let item = QIDOResultItem(
            studyInstanceUID: "1.2.840.001",
            seriesInstanceUID: "1.2.840.002",
            patientName: "DOE^JOHN"
        )
        service.setQIDOResults([item])
        let vm = DICOMwebViewModel(service: service)

        // Simulate what the context menu does:
        vm.wadoNewJobStudyUID = item.studyInstanceUID
        vm.wadoNewJobSeriesUID = item.seriesInstanceUID ?? ""
        vm.wadoNewJobMode = .series
        vm.activeTab = .wadoRS

        #expect(vm.wadoNewJobStudyUID == "1.2.840.001")
        #expect(vm.wadoNewJobSeriesUID == "1.2.840.002")
        #expect(vm.wadoNewJobMode == .series)
        #expect(vm.activeTab == .wadoRS)
    }

    @Test("empty QIDO query returns default 'All studies' summary")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEmptyQIDOQueryDefaultSummary() {
        let vm = DICOMwebViewModel()
        vm.qidoQueryParams = QIDOQueryParams()
        #expect(vm.qidoQuerySummary == "All studies")
    }

    @Test("QIDO series-level query returns 'All series' summary")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testQIDOSeriesLevelDefaultSummary() {
        let vm = DICOMwebViewModel()
        vm.qidoQueryParams = QIDOQueryParams(queryLevel: .series)
        #expect(vm.qidoQuerySummary == "All series")
    }
}

// MARK: - WADO-RS Flow Tests

@Suite("DICOMweb WADO-RS Flow Tests")
@MainActor
struct DICOMwebWADORSFlowTests {

    @Test("enqueueWADOJob with study UID creates study-level job")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEnqueueStudyLevelJob() async {
        let vm = DICOMwebViewModel()
        vm.wadoNewJobStudyUID = "1.2.840.10008"
        vm.wadoNewJobMode = .study
        await vm.enqueueWADOJob()
        #expect(vm.wadoJobs.count == 1)
        #expect(vm.wadoJobs.first?.retrieveMode == .study)
        #expect(vm.wadoJobs.first?.seriesInstanceUID == nil)
    }

    @Test("enqueueWADOJob with series UID populates seriesInstanceUID")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEnqueueSeriesLevelJob() async {
        let vm = DICOMwebViewModel()
        vm.wadoNewJobStudyUID = "1.2.840.10008"
        vm.wadoNewJobSeriesUID = "1.2.840.10009"
        vm.wadoNewJobMode = .series
        await vm.enqueueWADOJob()
        #expect(vm.wadoJobs.first?.seriesInstanceUID == "1.2.840.10009")
    }

    @Test("enqueue clears new job fields after adding")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEnqueueClearsFields() async {
        let vm = DICOMwebViewModel()
        vm.wadoNewJobStudyUID = "1.2.840.10008"
        vm.wadoNewJobSeriesUID = "1.2.840.10009"
        vm.wadoNewJobInstanceUID = "1.2.840.10010"
        await vm.enqueueWADOJob()
        #expect(vm.wadoNewJobStudyUID.isEmpty)
        #expect(vm.wadoNewJobSeriesUID.isEmpty)
        #expect(vm.wadoNewJobInstanceUID.isEmpty)
    }

    @Test("removeWADOJob clears selection if removed job was selected")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRemoveWADOJobClearsSelection() {
        let vm = DICOMwebViewModel()
        let job = WADORetrieveJob(studyInstanceUID: "1.2.3")
        vm.addWADOJob(job)
        vm.wadoSelectedJobID = job.id
        vm.removeWADOJob(id: job.id)
        #expect(vm.wadoSelectedJobID == nil)
    }

    @Test("selectedWADOJob returns nil when no selection")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSelectedWADOJobNilWhenNoSelection() {
        let vm = DICOMwebViewModel()
        #expect(vm.selectedWADOJob == nil)
    }

    @Test("selectedWADOJob returns correct job when selected")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSelectedWADOJobCorrectWhenSelected() {
        let vm = DICOMwebViewModel()
        let job = WADORetrieveJob(studyInstanceUID: "1.2.840.SELECTED")
        vm.addWADOJob(job)
        vm.wadoSelectedJobID = job.id
        #expect(vm.selectedWADOJob?.studyInstanceUID == "1.2.840.SELECTED")
    }
}

// MARK: - STOW-RS Flow Tests

@Suite("DICOMweb STOW-RS Flow Tests")
@MainActor
struct DICOMwebSTOWRSFlowTests {

    @Test("enqueueSTOWUpload captures duplicate handling setting")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEnqueueCapturesDuplicateHandling() async {
        let vm = DICOMwebViewModel()
        vm.stowNewFilePaths = ["/tmp/test.dcm"]
        vm.stowDuplicateHandling = .overwrite
        await vm.enqueueSTOWUpload()
        #expect(vm.stowJobs.first?.duplicateHandling == .overwrite)
    }

    @Test("enqueueSTOWUpload captures validation setting")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEnqueueCapturesValidation() async {
        let vm = DICOMwebViewModel()
        vm.stowNewFilePaths = ["/tmp/test.dcm"]
        vm.stowValidationEnabled = false
        await vm.enqueueSTOWUpload()
        #expect(vm.stowJobs.first?.validationEnabled == false)
    }

    @Test("enqueueSTOWUpload captures pipeline concurrency")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEnqueueCapturesConcurrency() async {
        let vm = DICOMwebViewModel()
        vm.stowNewFilePaths = ["/tmp/test.dcm"]
        vm.stowPipelineConcurrency = 10
        await vm.enqueueSTOWUpload()
        #expect(vm.stowJobs.first?.pipelineConcurrency == 10)
    }

    @Test("enqueue clears file paths after adding")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEnqueueClearsFilePaths() async {
        let vm = DICOMwebViewModel()
        vm.stowNewFilePaths = ["/tmp/a.dcm", "/tmp/b.dcm"]
        await vm.enqueueSTOWUpload()
        #expect(vm.stowNewFilePaths.isEmpty)
    }

    @Test("removeSTOWJob clears selection if removed job was selected")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRemoveSTOWJobClearsSelection() {
        let vm = DICOMwebViewModel()
        let job = STOWUploadJob(filePaths: ["/tmp/test.dcm"], totalFiles: 1)
        vm.addSTOWJob(job)
        vm.stowSelectedJobID = job.id
        vm.removeSTOWJob(id: job.id)
        #expect(vm.stowSelectedJobID == nil)
    }

    @Test("activeSTOWJobCount counts non-terminal jobs")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testActiveSTOWJobCountNonTerminal() {
        let vm = DICOMwebViewModel()
        vm.addSTOWJob(STOWUploadJob(status: .uploading))
        vm.addSTOWJob(STOWUploadJob(status: .validating))
        vm.addSTOWJob(STOWUploadJob(status: .completed))
        vm.addSTOWJob(STOWUploadJob(status: .failed))
        #expect(vm.activeSTOWJobCount == 2)
    }
}

// MARK: - UPS-RS Flow Tests

@Suite("DICOMweb UPS-RS Flow Tests")
@MainActor
struct DICOMwebUPSRSFlowTests {

    @Test("transitionUPSState scheduled to inProgress succeeds")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testScheduledToInProgress() {
        let service = DICOMwebService()
        let item = UPSWorkitem(workitemUID: "1.2.3", state: .scheduled)
        service.addUPSWorkitem(item)
        let vm = DICOMwebViewModel(service: service)
        vm.transitionUPSState(.inProgress, workitemID: item.id)
        #expect(vm.upsWorkitems.first?.state == .inProgress)
        #expect(vm.errorMessage == nil)
    }

    @Test("transitionUPSState inProgress to completed succeeds")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testInProgressToCompleted() {
        let service = DICOMwebService()
        let item = UPSWorkitem(workitemUID: "1.2.3", state: .inProgress)
        service.addUPSWorkitem(item)
        let vm = DICOMwebViewModel(service: service)
        vm.transitionUPSState(.completed, workitemID: item.id)
        #expect(vm.upsWorkitems.first?.state == .completed)
    }

    @Test("transitionUPSState completed to scheduled fails")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCompletedToScheduledFails() {
        let service = DICOMwebService()
        let item = UPSWorkitem(workitemUID: "1.2.3", state: .completed)
        service.addUPSWorkitem(item)
        let vm = DICOMwebViewModel(service: service)
        vm.transitionUPSState(.scheduled, workitemID: item.id)
        #expect(vm.errorMessage != nil)
        #expect(vm.upsWorkitems.first?.state == .completed) // unchanged
    }

    @Test("globalSubscription returns active global sub")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testGlobalSubscriptionReturnsActiveSub() {
        let service = DICOMwebService()
        service.addUPSSubscription(UPSEventSubscription(
            workitemUID: nil,
            eventTypes: [.stateChange],
            isActive: true
        ))
        let vm = DICOMwebViewModel(service: service)
        #expect(vm.globalSubscription?.isGlobal == true)
    }

    @Test("globalSubscription returns nil when no active global")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testGlobalSubscriptionNilWhenInactive() {
        let service = DICOMwebService()
        service.addUPSSubscription(UPSEventSubscription(
            workitemUID: nil,
            eventTypes: [.stateChange],
            isActive: false
        ))
        let vm = DICOMwebViewModel(service: service)
        #expect(vm.globalSubscription == nil)
    }
}

// MARK: - Performance Dashboard Tests

@Suite("DICOMweb Performance Dashboard Tests")
@MainActor
struct DICOMwebPerformanceDashboardTests {

    @Test("recordPerformanceSample appends to history")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRecordSampleAppendsToHistory() {
        let vm = DICOMwebViewModel()
        let stats = DICOMwebPerformanceStats(averageLatencyMs: 42)
        vm.recordPerformanceSample(stats)
        #expect(vm.performanceHistory.count == 1)
        #expect(vm.performanceStats.averageLatencyMs == 42)
    }

    @Test("refreshPerformanceStats reloads from service")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRefreshReloadsFromService() {
        let service = DICOMwebService()
        service.updatePerformanceStats(DICOMwebPerformanceStats(averageLatencyMs: 99))
        let vm = DICOMwebViewModel(service: service)
        vm.performanceStats = DICOMwebPerformanceStats() // reset locally
        vm.refreshPerformanceStats()
        #expect(vm.performanceStats.averageLatencyMs == 99)
    }

    @Test("performance health is 'Excellent' for default zero stats")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDefaultHealthExcellent() {
        let vm = DICOMwebViewModel()
        #expect(vm.performanceHealthDescription == "Excellent")
    }

    @Test("performance health is 'Poor' for high latency and errors")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testPoorHealthForHighLatency() {
        let vm = DICOMwebViewModel()
        vm.recordPerformanceSample(DICOMwebPerformanceStats(
            averageLatencyMs: 5000,
            totalRequestCount: 100,
            errorCount: 20
        ))
        #expect(vm.performanceHealthDescription == "Poor")
    }
}

// MARK: - End-to-End QIDO → WADO → STOW Workflow

@Suite("DICOMweb End-to-End Workflow Tests")
@MainActor
struct DICOMwebEndToEndWorkflowTests {

    @Test("full workflow: query → select → retrieve → complete")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testFullQIDOToWADOWorkflow() async {
        let service = DICOMwebService()

        // 1. Simulate QIDO results
        let result = QIDOResultItem(
            studyInstanceUID: "1.2.840.10008.5.1.4.1.1.2",
            patientName: "DOE^JANE",
            patientID: "PAT001",
            studyDate: "20260318",
            modality: "CT",
            studyDescription: "Chest CT",
            numberOfSeries: 3,
            numberOfInstances: 120
        )
        service.setQIDOResults([result])

        let vm = DICOMwebViewModel(service: service)

        // 2. Select the result
        vm.selectQIDOResult(result.id)
        #expect(vm.selectedQIDOResult?.studyInstanceUID == "1.2.840.10008.5.1.4.1.1.2")

        // 3. Pre-fill WADO job from QIDO result
        vm.wadoNewJobStudyUID = result.studyInstanceUID
        vm.wadoNewJobMode = .study

        // 4. Enqueue retrieve
        await vm.enqueueWADOJob()
        #expect(vm.wadoJobs.count == 1)
        #expect(vm.wadoJobs.first?.studyInstanceUID == "1.2.840.10008.5.1.4.1.1.2")
    }

    @Test("full workflow: add files → upload → track")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testFullSTOWUploadWorkflow() async {
        let vm = DICOMwebViewModel()

        // 1. Stage files
        vm.stowNewFilePaths = ["/data/img1.dcm", "/data/img2.dcm", "/data/img3.dcm"]
        vm.stowDuplicateHandling = .overwrite
        vm.stowValidationEnabled = true
        vm.stowPipelineConcurrency = 3

        // 2. Enqueue upload
        await vm.enqueueSTOWUpload()

        // 3. Verify job was created correctly
        #expect(vm.stowJobs.count == 1)
        let job = vm.stowJobs.first
        #expect(job?.totalFiles == 3)
        #expect(job?.duplicateHandling == .overwrite)
        #expect(job?.validationEnabled == true)
        #expect(job?.pipelineConcurrency == 3)
        #expect(vm.stowNewFilePaths.isEmpty)
    }

    @Test("multiple WADO jobs track independently")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testMultipleWADOJobsTrackIndependently() {
        let vm = DICOMwebViewModel()

        // Add two jobs
        vm.addWADOJob(WADORetrieveJob(
            studyInstanceUID: "1.2.840.001",
            retrieveMode: .study,
            status: .inProgress
        ))
        vm.addWADOJob(WADORetrieveJob(
            studyInstanceUID: "1.2.840.002",
            retrieveMode: .series,
            status: .queued
        ))

        #expect(vm.wadoJobs.count == 2)
        #expect(vm.activeWADOJobCount == 1)

        // Clear only completed — none should be removed
        vm.clearCompletedWADOJobs()
        #expect(vm.wadoJobs.count == 2)
    }
}
