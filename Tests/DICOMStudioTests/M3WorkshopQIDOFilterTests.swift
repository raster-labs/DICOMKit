import Foundation
import Testing
import ArgumentParser
import DICOMWeb
@testable import DICOMStudio
@testable import dicom_wado

@Suite("M3 Workshop QIDO effective filters", .serialized)
@MainActor
struct M3WorkshopQIDOFilterTests {
    private func model(_ values: [String: String]) -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
        vm.selectTool(id: "dicom-qido")
        vm.experienceMode = .advanced
        vm.updateParameterValue(parameterID: "url", value: "http://127.0.0.1:1/dicom-web")
        for (key, value) in values { vm.updateParameterValue(parameterID: key, value: value) }
        return vm
    }

    #if os(macOS) || os(Linux)
    /// Shell expands only the capture builtin, never the displayed executable.
    private func previewRequest(_ preview: String) throws -> QIDORequest {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "capture() { printf '%s\\0' \"$@\"; }\ncapture " + preview]
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(String(decoding: errors, as: UTF8.self))")
        let argv = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        #expect(Array(argv.prefix(2)) == ["dicom-wado", "query"])
        return try QueryCommand.parse(Array(argv.dropFirst(2))).buildRequest()
    }

    private func assertPreviewParity(_ vm: CLIWorkshopViewModel) throws {
        #expect(try previewRequest(vm.commandPreview) == vm.effectiveQIDORequest(), "\(vm.commandPreview)")
    }

    @Test("All six forms expose and preview exactly their effective request")
    func sixResources() throws {
        let cases: [([String: String], String, [String: String])] = [
            (["level": "study", "study-date": "-20261024", "modality": "CT"], "/studies", ["00080020": "-20261024", "00080061": "CT"]),
            (["level": "series", "study-date": "20261024-", "pps-start-time": "-120000", "modality": "CT"], "/series", ["00080020": "20261024-", "00400245": "-120000", "00080060": "CT"]),
            (["level": "series", "study-uid": "2.25.1", "pps-start-date": "20260101-20261231"], "/studies/2.25.1/series", ["00400244": "20260101-20261231"]),
            (["level": "instance", "study-date": "20261024", "qido-sps-id": "SPS*", "modality": "MR"], "/instances", ["00080020": "20261024", "00400275.00400009": "SPS*", "00080060": "MR"]),
            (["level": "instance", "study-uid": "2.25.1", "qido-requested-procedure-id": "RP?", "modality": "MR"], "/studies/2.25.1/instances", ["00400275.00401001": "RP?", "00080060": "MR"]),
            (["level": "instance", "study-uid": "2.25.1", "series-uid": "2.25.2"], "/studies/2.25.1/series/2.25.2/instances", [:]),
        ]
        for (values, path, filters) in cases {
            var values = values
            values["patient-name"] = "Müller^*"
            values["patient-id"] = "PAT?"
            let vm = model(values)
            let request = try vm.effectiveQIDORequest()
            var expected = filters
            expected.merge(["00100010": "Müller^*", "00100020": "PAT?", "limit": "100", "offset": "0"]) { _, new in new }
            #expect(request.path == path)
            #expect(request.query.toParameters() == expected)
            try assertPreviewParity(vm)
        }
    }

    @Test("Series study instance transitions hide, retain and restore all four PPS fields")
    func retainedSeriesFilters() throws {
        let fields = ["pps-start-date": "-20261024", "pps-start-time": "080000-", "qido-sps-id": "SPS*", "qido-requested-procedure-id": "RP?"]
        let vm = model(fields.merging(["level": "series"]) { _, new in new })
        let original = try vm.effectiveQIDORequest()
        vm.updateParameterValue(parameterID: "level", value: "study")
        for id in fields.keys { #expect(!vm.visibleParameters().contains { $0.id == id }) }
        #expect(try vm.effectiveQIDORequest().query.toParameters() == ["limit": "100", "offset": "0"])
        for flag in ["--pps-start-date", "--pps-start-time", "--sps-id", "--requested-procedure-id"] { #expect(!vm.commandPreview.contains(flag)) }
        try assertPreviewParity(vm)
        vm.updateParameterValue(parameterID: "level", value: "series")
        #expect(try vm.effectiveQIDORequest() == original)
        for id in fields.keys { #expect(vm.visibleParameters().contains { $0.id == id }) }
        try assertPreviewParity(vm)
        // Both relational instance forms keep series attributes visible and sent.
        vm.updateParameterValue(parameterID: "level", value: "instance")
        for study in ["", "2.25.1"] {
            vm.updateParameterValue(parameterID: "study-uid", value: study)
            for id in fields.keys { #expect(vm.visibleParameters().contains { $0.id == id }) }
            #expect(try vm.effectiveQIDORequest().query.toParameters() == original.query.toParameters())
            try assertPreviewParity(vm)
        }
        vm.updateParameterValue(parameterID: "series-uid", value: "2.25.2")
        for id in fields.keys { #expect(!vm.visibleParameters().contains { $0.id == id }) }
        #expect(try vm.effectiveQIDORequest().query.toParameters() == ["limit": "100", "offset": "0"])
        try assertPreviewParity(vm)
        vm.updateParameterValue(parameterID: "series-uid", value: "")
        #expect(try vm.effectiveQIDORequest().query.toParameters() == original.query.toParameters())
        try assertPreviewParity(vm)
    }

    @Test("Scoped parent filters and modality are excluded, then restored; tool changes clear them")
    func scopeAndToolTransitions() throws {
        let vm = model(["level": "instance", "study-date": "20260101-20261231", "accession": "A*",
                        "study-description": "CHEST*", "modality": "CT", "pps-start-date": "20261024"])
        let original = try vm.effectiveQIDORequest()
        vm.updateParameterValue(parameterID: "study-uid", value: "2.25.1")
        for id in ["study-date", "accession", "study-description"] { #expect(!vm.visibleParameters().contains { $0.id == id }) }
        #expect(try vm.effectiveQIDORequest().query.toParameters() == ["limit": "100", "offset": "0", "00080060": "CT", "00400244": "20261024"])
        try assertPreviewParity(vm)
        vm.updateParameterValue(parameterID: "series-uid", value: "2.25.2")
        #expect(!vm.visibleParameters().contains { $0.id == "modality" })
        #expect(!vm.commandPreview.contains("--modality"))
        #expect(try vm.effectiveQIDORequest().query.toParameters() == ["limit": "100", "offset": "0"])
        try assertPreviewParity(vm)
        vm.updateParameterValue(parameterID: "series-uid", value: "")
        vm.updateParameterValue(parameterID: "study-uid", value: "")
        #expect(try vm.effectiveQIDORequest() == original)
        try assertPreviewParity(vm)
        vm.selectTool(id: "dicom-info")
        vm.selectTool(id: "dicom-qido")
        #expect(try vm.effectiveQIDORequest().query.toParameters() == ["limit": "100", "offset": "0"])
        for id in ["study-date", "modality", "pps-start-date", "accession", "study-description"] {
            #expect(!vm.parameterValues.contains { $0.parameterID == id && !$0.stringValue.isEmpty })
        }
    }

    @Test("UID-list scopes and a transitioned form equal fresh equivalent state")
    func freshAndTransitionedParity() throws {
        let values = ["level": "instance", "study-uid": "2.25.1,2.25.2", "series-uid": "2.25.3,2.25.4",
                      "pps-start-date": "-20261024", "study-date": "20261024-", "modality": "CT"]
        let transitioned = model(values)
        transitioned.updateParameterValue(parameterID: "level", value: "study")
        try assertPreviewParity(transitioned)
        transitioned.updateParameterValue(parameterID: "level", value: "instance")
        #expect(try transitioned.effectiveQIDORequest() == model(values).effectiveQIDORequest())
        #expect(try transitioned.effectiveQIDORequest().path == "/instances")
        try assertPreviewParity(transitioned)
    }
    #endif

    @Test("Actual Workshop execution refuses malformed UID and pagination before networking")
    func actualExecutionPreflight() async throws {
        for values in [["level": "series", "study-uid": "1..2"], ["limit": "NaN"], ["offset": "-1"]] {
            let vm = model(values)
            // An unusable URL proves request validation precedes client creation.
            vm.updateParameterValue(parameterID: "url", value: "http://[")
            await vm.executeCommand()
            #expect(vm.consoleStatus == .error)
            #expect(vm.commandHistory.first?.exitCode == 64)
            #expect(vm.consoleOutput.contains("DICOM UID") || vm.consoleOutput.contains("nonnegative") || vm.consoleOutput.contains("unsigned"))
        }
    }
}
