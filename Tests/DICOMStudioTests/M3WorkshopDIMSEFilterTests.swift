import Foundation
import Testing
import DICOMNetwork
@testable import DICOMStudio

@Suite("M3 Workshop DIMSE effective filters", .serialized)
@MainActor
struct M3WorkshopDIMSEFilterTests {
    private func model(level: String, filters: [String: String]) -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
        vm.selectTool(id: "dicom-query")
        var values = ["host": "host.invalid", "aet": "M3", "level": level, "verbose": "true"]
        values.merge(filters) { _, new in new }
        for (key, value) in values { vm.updateParameterValue(parameterID: key, value: value) }
        return vm
    }

    @Test("Unsupported filters refuse before a query header or network operation")
    func refuseDroppedFilters() async {
        let cases: [(String, [String: String], String)] = [
            ("image", ["study-uid": "1.2", "series-uid": "1.2.3", "modality": "CT"], "Modality (--modality)"),
            ("patient", ["study-date": "20260101-20260331"], "Study Date (--study-date)"),
            ("patient", ["study-description": "CHEST*"], "Study Description (--study-description)"),
            ("patient", ["study-uid": "1.2"], "Study Instance UID (--study-uid)"),
            ("series", ["study-uid": "1.2", "patient-name": "DOE*"], "Patient Name (--patient-name)")
        ]
        for (level, filters, name) in cases {
            let vm = model(level: level, filters: filters)
            await vm.executeCommand()
            #expect(vm.consoleStatus == .error)
            #expect(vm.commandHistory.first?.exitCode == 64)
            #expect(vm.consoleOutput.contains(name + " cannot be matched at " + level.uppercased() + " level"))
            #expect(vm.consoleOutput.contains("No query was sent"))
            #expect(!vm.consoleOutput.contains("will be ignored"))
            #expect(!vm.consoleOutput.contains("Modality:"))
        }
    }

    @Test("Changing levels keeps incompatible values visible and refuses them")
    func changingLevelDoesNotSilentlyBroadenQuery() async {
        let vm = model(level: "study", filters: ["study-date": "20260101-20260331", "study-description": "CHEST*"])
        vm.updateParameterValue(parameterID: "level", value: "patient")
        #expect(vm.commandPreview.contains("--study-date 20260101-20260331"))
        #expect(vm.commandPreview.contains("--study-description"))
        await vm.executeCommand()
        #expect(vm.commandHistory.first?.exitCode == 64)
        #expect(vm.consoleOutput.contains("Study Date (--study-date), Study Description (--study-description)"))
    }

    @Test("Accepted preview retains ranges and wildcard matching text")
    func acceptedPreviewPreservesMatchingValues() {
        let vm = model(level: "study", filters: ["study-date": "20260101-20260331", "patient-name": "DOE*", "modality": "CT"])
        #expect(vm.commandPreview.contains("--study-date 20260101-20260331"))
        #expect(vm.commandPreview.contains("DOE*"))
        #expect(vm.commandPreview.contains("--modality CT"))
    }
}
