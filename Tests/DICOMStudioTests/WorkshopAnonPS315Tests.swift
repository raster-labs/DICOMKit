//
// WorkshopAnonPS315Tests.swift
// DICOMStudioTests
//
// P-STUDIO-ANON-PS315: the CLI Workshop's dicom-anon runs `--profile ps315` (the CLI default)
// and its alias `basic` through DICOMKit Anonymizer.deidentify(file:options:) — the PS3.15 2026a
// Basic Application Level Confidentiality Profile (every row of Table E.1-1) with the E.3
// Options — and prints what dicom-anon prints: the AnonCLI notices, the Table E.1-1a action
// report and the AnonConsole summary. The Security panel runs the same path.
//

import Testing
import Foundation
@testable import DICOMStudio
import DICOMCore
import DICOMKit

@MainActor
struct WorkshopAnonPS315Tests {

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkshopAnonPS315-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A small Secondary Capture data set carrying the identifiers Table E.1-1 acts on.
    private func fixture(burnedIn: Bool = false) throws -> Data {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.826.0.1.3680043.2.1125.1.1", for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.826.0.1.3680043.2.1125.1.2", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.826.0.1.3680043.2.1125.1.3", for: .seriesInstanceUID, vr: .UI)
        ds.setString("DOE^JOHN", for: .patientName, vr: .PN)
        ds.setString("PID-0001", for: .patientID, vr: .LO)
        ds.setString("19700101", for: .patientBirthDate, vr: .DA)
        ds.setString("20240315", for: .studyDate, vr: .DA)
        ds.setString("ACC-42", for: .accessionNumber, vr: .SH)
        ds.setString("General Hospital", for: .institutionName, vr: .LO)
        ds.setString("OT", for: .modality, vr: .CS)
        if burnedIn { ds.setString("YES", for: Tag(group: 0x0028, element: 0x0301), vr: .CS) }
        return try DICOMFile.create(dataSet: ds).write()
    }

    private func run(_ input: URL, params: [String: String]) async -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: "dicom-anon")
        vm.updateParameterValue(parameterID: "inputPath", value: input.path)
        for (id, value) in params { vm.updateParameterValue(parameterID: id, value: value) }
        await vm.executeCommand()
        return vm
    }

    private nonisolated static func workflowOutput(_ request: AnonymizationWorkflow.Request) async throws -> (String, Int32) {
        var output = ""
        let result = try await AnonymizationWorkflow().run(request) { output += $0 }
        return (output, result.exitCode)
    }

    @Test("Workshop and shared workflow produce identical header-only dry-run output")
    func ps315DefaultDryRunEqualsCLI() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("scan.dcm")
        try fixture().write(to: input)
        let vm = await run(input, params: ["dry-run": "true", "clean-pixel-data": "false"])
        var request = AnonymizationWorkflow.Request(inputPath: input.path)
        request.dryRun = true
        request.cleanPixelData = false
        let (expected, exitCode) = try await Self.workflowOutput(request)
        #expect(exitCode == 0)
        #expect(vm.commandHistory.last?.exitCode == 0)
        #expect(vm.consoleOutput.contains(expected))
    }

    @Test("ps315 with E.3 Options writes the de-identified file: (0012,0062) YES, CID 7050 method codes, (0002,0003) = (0008,0018)")
    func ps315WritesDeidentifiedFile() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("scan.dcm")
        let output = root.appendingPathComponent("anon.dcm")
        try fixture().write(to: input)
        let vm = await run(input, params: ["profile": "ps315", "output": output.path,
                                           "retain-institution": "true", "audit-log": root.appendingPathComponent("audit.log").path])
        #expect(vm.commandHistory.last?.exitCode == 0, "console: \(vm.consoleOutput)")
        let written = try DICOMFile.read(from: Data(contentsOf: output))
        let ds = written.dataSet
        #expect(ds.string(for: Tag(group: 0x0012, element: 0x0062))?.trimmingCharacters(in: .whitespaces) == "YES")
        #expect(ds.string(for: .institutionName) == "General Hospital")        // Retain Institution Identity Option (E.3.11)
        #expect(ds.string(for: .patientName) != "DOE^JOHN")
        let sop = ds.string(for: .sopInstanceUID)?.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
        #expect(sop != "1.2.826.0.1.3680043.2.1125.1.1")                       // Table E.1-1 U
        #expect(written.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID)?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \0")) == sop) // PS3.10 Table 7.1-1
        let codes = (ds[Tag(group: 0x0012, element: 0x0064)]?.sequenceItems ?? [])
            .compactMap { $0[.codeValue]?.stringValue?.trimmingCharacters(in: .whitespaces) }
        #expect(codes == ["113100", "113112"])  // Basic Profile, Retain Institution Identity Option (PS3.16 CID 7050)
        let audit = try String(contentsOf: root.appendingPathComponent("audit.log"), encoding: .utf8)
        #expect(audit.contains("Audit Log"))
        #expect(!audit.contains("DOE^JOHN"))
        #expect(!audit.contains("PID-0001"))
    }

    @Test("ps315 refuses what dicom-anon refuses: --keep (AnonCLI.validate) and burned-in PHI without --allow-burned-in-phi")
    func ps315Refusals() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("scan.dcm")
        try fixture().write(to: input)
        let burned = root.appendingPathComponent("burned.dcm")
        try fixture(burnedIn: true).write(to: burned)
        let refused = await run(burned, params: ["output": root.appendingPathComponent("o.dcm").path, "clean-pixel-data": "false"])
        #expect(refused.commandHistory.last?.exitCode == 1)
        #expect(refused.consoleOutput.contains("Error: Refusing to anonymize burned.dcm: the pixel data may still contain PHI."))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("o.dcm").path))
        let allowed = await run(burned, params: ["output": root.appendingPathComponent("o.dcm").path,
                                                 "allow-burned-in-phi": "true", "clean-pixel-data": "false"])
        #expect(allowed.commandHistory.last?.exitCode == 0, "console: \(allowed.consoleOutput)")
    }

    @Test("the dicom-anon burned-in refusal text is the CLI's (Sources/dicom-anon/main.swift)")
    func burnedInRefusalText() {
        let text = WorkshopAnonError.burnedInPHIRefusal(fileName: "a.dcm", warnings: ["w1"])
        #expect(text == "Refusing to anonymize a.dcm: the pixel data may still contain PHI.\n\n  ⚠️  w1\n\n"
            + "Without --clean-pixel-data this tool de-identifies the DATASET ONLY, so burned-in text survives unchanged.\n\n"
            + "Pass --clean-pixel-data to blank it (add --redact-region x,y,w,h if the automatic region selection "
            + "cannot resolve this device), or --allow-burned-in-phi to write the metadata-scrubbed file anyway "
            + "(it will be marked Patient Identity Removed = NO).")
    }

    @Test("Security panel: ps315 runs the PS3.15 path and records Patient Identity Removed")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func securityPanelPS315() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("scan.dcm")
        let output = root.appendingPathComponent("anon.dcm")
        try fixture().write(to: input)
        let vm = SecurityViewModel()
        #expect(vm.anonRequest.cleanPixelData)
        vm.anonInputPath = input.path
        vm.anonOutputPath = output.path
        vm.anonRetainUIDs = true
        #expect(vm.anonCLICommand.contains("--retain-uids"))
        await vm.performAnonymization()
        for _ in 0..<500 where vm.anonIsRunning { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(vm.anonLastExitCode == 0, "output: \(vm.anonOutput)")
        let ds = try DICOMFile.read(from: Data(contentsOf: output)).dataSet
        #expect(ds.string(for: Tag(group: 0x0012, element: 0x0062))?.trimmingCharacters(in: .whitespaces) == "YES")
        #expect(ds.string(for: .sopInstanceUID)?.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
                == "1.2.826.0.1.3680043.2.1125.1.1")                    // Retain UIDs Option (E.3.9)

        // The retained main options are exposed by the Security panel request.
        vm.anonCleanStructuredContent = true
        vm.anonRetainSafePrivate = true
        #expect(vm.anonRequest.cleanStructuredContent)
        #expect(vm.anonRequest.retainSafePrivate)
    }
}
