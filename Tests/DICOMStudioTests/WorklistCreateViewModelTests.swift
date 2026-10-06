//
// WorklistCreateViewModelTests.swift
// DICOMStudioTests
//
// P-STUDIO-MWL-CREATE: the worklist-item create flow (HL7 ORM^O01 over MLLP, or the archive's
// REST API) moved from the CLI Workshop's dicom-mwl tool to the Networking panel's worklist area.
// Owner decision: it stays in the app only; dicom-mwl has no create subcommand. The defaults,
// refusals and console lines are the former Workshop flow's, unchanged.
//

import Testing
import Foundation
@testable import DICOMStudio
import DICOMNetwork

@MainActor
struct WorklistCreateViewModelTests {

    @Test("defaults are the former Workshop create form's")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func defaults() {
        let vm = WorklistCreateViewModel()
        #expect(vm.method == .hl7)
        #expect(vm.port == "11112")
        #expect(vm.hl7Port == "2575")
        #expect(vm.callingAET == "DICOMSTUDIO")
        #expect(vm.calledAET == "ANY-SCP")
        #expect(vm.timeout == "60")
        #expect(vm.modality == "CT")
        #expect([vm.sendingApplication, vm.sendingFacility, vm.receivingApplication, vm.receivingFacility]
                == ["DICOMSTUDIO", "IMAGING", "DCM4CHEE", "HOSPITAL"])
        #expect(WorklistCreateMethod.allCases.map(\.rawValue) == ["hl7", "rest"])
        // Patient's Sex (0010,0040): the PS3.3 2026a Enumerated Values M, F, O (plus "not given")
        #expect(WorklistCreateViewModel.patientSexValues == ["", "M", "F", "O"])
        #expect(WorklistCreateViewModel.modalityValues.contains("CT"))
    }

    @Test("refusals: host, Patient's Name (0010,0010) and Patient ID (0010,0020) are required (exit 1)")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func refusals() async {
        let vm = WorklistCreateViewModel()
        await vm.run()
        #expect(vm.lastExitCode == 1)
        #expect(vm.output == "Error: A valid host is required (e.g. hostname or hostname:11112).\n")
        vm.clearOutput()
        vm.host = "127.0.0.1"
        await vm.run()
        #expect(vm.output == "Error: Patient Name is required for worklist creation.\n")
        vm.clearOutput()
        vm.patientName = "DOE^JOHN"
        await vm.run()
        #expect(vm.output == "Error: Patient ID is required for worklist creation.\n")
        #expect(vm.isRunning == false)
    }

    @Test("a REST create against a closed port prints the REST header, the item block and the failure hints (exit 1)")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func restFailure() async {
        let vm = WorklistCreateViewModel()
        vm.method = .rest
        vm.host = "127.0.0.1"
        vm.restBaseURL = "http://127.0.0.1:1/dcm4chee-arc"
        vm.timeout = "2"
        vm.patientName = "DOE^JOHN"
        vm.patientID = "PID-1"
        vm.scheduledDate = "20260101"
        await vm.run()
        #expect(vm.lastExitCode == 1)
        #expect(vm.output.hasPrefix("DICOM Modality Worklist (REST API)\n===================================\n"))
        #expect(vm.output.contains("  REST Endpoint:    http://127.0.0.1:1/dcm4chee-arc/aets/ANY-SCP/rs/mwlitems\n"))
        #expect(vm.output.contains(NetworkConsole.mwlCreateDetailBlock(
            patientName: "DOE^JOHN", patientID: "PID-1", patientDOB: "", patientSex: "",
            accessionNumber: "", referringPhysician: "", modality: "CT", scheduledDate: "20260101",
            scheduledTime: "", stationAET: "", stationName: "", spsID: "", spsDescription: "",
            procedureID: "", procedureDescription: "", performingPhysician: "")))
        #expect(vm.output.contains("❌ Worklist create failed: "))
        #expect(vm.output.contains("  💡 Hint: REST requires the patient to exist first on the server.\n"))
    }

    @Test("host parsing and the scheduled date are the Workshop's")
    func helpers() {
        #expect(WorklistCreateViewModel.resolveHostPort("pacs://h:4242", explicitPort: nil)! == ("h", 4242))
        #expect(WorklistCreateViewModel.resolveHostPort("h:4242", explicitPort: "104")! == ("h", 104))
        #expect(WorklistCreateViewModel.resolveHostPort("", explicitPort: nil) == nil)
        #expect(WorklistCreateViewModel.resolvedWorklistDate("20260101") == "20260101")
        #expect(WorklistCreateViewModel.resolvedWorklistDate("today").count == 8)
    }

    @Test("the Workshop's dicom-mwl refuses a create operation restored from saved state, pointing to the Networking panel")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func workshopRefusesCreate() async {
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: "dicom-mwl")
        vm.updateParameterValue(parameterID: "operation", value: "create")
        vm.updateParameterValue(parameterID: "host", value: "127.0.0.1")
        await vm.executeCommand()
        #expect(vm.commandHistory.last?.exitCode == 64)
        #expect(vm.consoleOutput.contains("Error: " + CLIWorkshopViewModel.mwlCreateMovedMessage(operation: "create")))
        #expect(vm.commandPreview.hasPrefix("#"))   // never a paste-runnable `dicom-mwl create`
    }
}
