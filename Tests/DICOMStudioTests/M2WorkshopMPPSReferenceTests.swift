import Foundation
import Testing
import DICOMNetwork
@testable import DICOMStudio

@Suite("M2 Workshop MPPS reference preflight", .serialized)
@MainActor
struct M2WorkshopMPPSReferenceTests {
    private func model(classUID: String?) -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
        vm.selectTool(id: "dicom-mpps")
        var values = ["operation": "update", "host": "host.invalid", "aet": "M2", "mpps-uid": "2.25.1",
            "status-update": "COMPLETED", "study-uid": "2.25.2", "series-uid": "2.25.3", "image-uid": "2.25.4"]
        if let classUID { values["sop-class-uid"] = classUID }
        for (key, value) in values { vm.updateParameterValue(parameterID: key, value: value) }
        return vm
    }

    @Test("Missing and malformed image classes refuse before an MPPS network operation")
    func refuseAmbiguousReferences() async {
        for value in [nil, "", "1..2"] as [String?] {
            let vm = model(classUID: value)
            await vm.executeCommand()
            #expect(vm.consoleStatus == .error)
            #expect(vm.commandHistory.first?.exitCode == 64)
            let expected = DICOMMPPSService.imageReferenceInputError(imageUIDs: ["2.25.4"],
                studyUID: "2.25.2", seriesUID: "2.25.3", sopClassUID: value)
            #expect(expected != nil)
            #expect(vm.consoleOutput.contains(expected ?? "MISSING DIAGNOSTIC"))
            #expect(!vm.consoleOutput.contains("defaults to Secondary Capture"))
        }
    }

    @Test("Explicit CT, MR and SC classes survive the Workshop preview and shared preflight")
    func preserveExplicitClasses() {
        for value in ["1.2.840.10008.5.1.4.1.1.2", "1.2.840.10008.5.1.4.1.1.4", "1.2.840.10008.5.1.4.1.1.7"] {
            let vm = model(classUID: value)
            #expect(vm.commandPreview.contains("--sop-class-uid " + value))
            #expect(DICOMMPPSService.imageReferenceInputError(imageUIDs: ["2.25.4"],
                studyUID: "2.25.2", seriesUID: "2.25.3", sopClassUID: value) == nil)
        }
    }
}
