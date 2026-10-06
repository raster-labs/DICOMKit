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

    /// What dicom-anon `--profile ps315 --dry-run` prints for one file (Sources/dicom-anon/main.swift):
    /// the engine pass, the E.1-1a action lines, the summary — built from the same engine symbols.
    private func expectedDryRun(_ input: URL, flags: AnonCLI.PS315Flags = AnonCLI.PS315Flags()) throws -> String {
        let file = try DICOMFile.read(from: Data(contentsOf: input))
        let options = AnonCLI.options(flags: flags, shiftDates: nil)
        let anonymizer = Anonymizer(profile: .basic, shiftDates: nil, regenerateUIDs: false,
                                    preserveTags: [], customActions: [:])
        let (out, res, _) = anonymizer.deidentify(file: file, options: options)
        let actions = AnonCLI.attributeActions(before: file.dataSet, after: out.dataSet, options: options)
        return AnonCLI.actionLines(path: input.path, actions: actions)
            + AnonConsole.summary(totalFiles: 1, successful: res.success ? 1 : 0, failed: res.success ? 0 : 1,
                                  dryRun: true, warnings: res.warnings,
                                  modifiedTags: Set(res.changedTags.map { "\($0)" }), verbose: false)
    }

    @Test("the Workshop's dicom-anon defaults to ps315 and prints dicom-anon's dry-run output (PS3.15 2026a Table E.1-1 / E.1-1a)")
    func ps315DefaultDryRunEqualsCLI() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("scan.dcm")
        try fixture().write(to: input)
        let vm = await run(input, params: ["dry-run": "true"])   // --profile left at its default
        #expect(vm.commandHistory.last?.exitCode == 0, "console: \(vm.consoleOutput)")
        #expect(vm.consoleOutput.contains(try expectedDryRun(input)), "console: \(vm.consoleOutput)")
        #expect(!vm.consoleOutput.contains("cannot run yet"))
        #expect(!vm.consoleOutput.contains("Deprecated:"))
        // Table E.1-1 actions on the fixture: Patient's Name Z, Patient ID Z, SOP Instance UID U
        #expect(vm.consoleOutput.contains("U        (0008,0018) SOP Instance UID"))
        #expect(vm.consoleOutput.contains("Z        (0010,0010) Patient's Name"))
    }

    @Test("--profile basic is the ps315 alias: dicom-anon's note, then the same output")
    func basicAliasEqualsCLI() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("scan.dcm")
        try fixture().write(to: input)
        let vm = await run(input, params: ["profile": "basic", "dry-run": "true"])
        #expect(vm.commandHistory.last?.exitCode == 0, "console: \(vm.consoleOutput)")
        let note = try #require(AnonCLI.legacyProfileNotice("basic"))
        #expect(vm.consoleOutput.contains(note + "\n" + (try expectedDryRun(input))), "console: \(vm.consoleOutput)")
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
        #expect(audit.contains("Method: Basic Application Confidentiality Profile; Retain Institution Identity Option"))
    }

    @Test("ps315 refuses what dicom-anon refuses: --keep (AnonCLI.validate) and burned-in PHI without --allow-burned-in-phi")
    func ps315Refusals() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("scan.dcm")
        try fixture().write(to: input)
        let keep = await run(input, params: ["dry-run": "true", "keep": "0010,0010"])
        #expect(keep.consoleOutput.contains("--keep is not applied by --profile ps315"))
        #expect(keep.commandHistory.last?.exitCode == 1)   // dicom-anon exits 1 (its CLI-local ValidationError)

        let burned = root.appendingPathComponent("burned.dcm")
        try fixture(burnedIn: true).write(to: burned)
        let refused = await run(burned, params: ["output": root.appendingPathComponent("o.dcm").path])
        #expect(refused.commandHistory.last?.exitCode == 1)
        #expect(refused.consoleOutput.contains("Error: Refusing to anonymize burned.dcm: the pixel data may still contain PHI."))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("o.dcm").path))
        let allowed = await run(burned, params: ["output": root.appendingPathComponent("o.dcm").path,
                                                 "allow-burned-in-phi": "true"])
        #expect(allowed.commandHistory.last?.exitCode == 0, "console: \(allowed.consoleOutput)")
    }

    @Test("legacy lists still run and still refuse the E.3 Option flags with dicom-anon's text")
    func legacyStillRefusesOptions() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("scan.dcm")
        try fixture().write(to: input)
        let vm = await run(input, params: ["profile": "legacy-basic", "dry-run": "true", "retain-uids": "true"])
        #expect(vm.consoleOutput.contains("PS3.15 Annex E Option flags apply only to --profile ps315: --retain-uids"))
        let ok = await run(input, params: ["profile": "legacy-basic", "dry-run": "true"])
        #expect(ok.commandHistory.last?.exitCode == 0)
        #expect(ok.consoleOutput.contains(AnonCLI.legacyProfileNotice("legacy-basic")!))
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
        #expect(vm.anonProfile == .ps315)
        vm.anonInputPath = input.path
        vm.anonOutputPath = output.path
        vm.anonPS315Flags.retainUids = true
        #expect(vm.anonCLICommand.contains("--profile ps315 --retain-uids"))
        vm.runAnonymization()
        for _ in 0..<500 where vm.anonIsRunning { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(vm.anonLastExitCode == 0, "output: \(vm.anonOutput)")
        let ds = try DICOMFile.read(from: Data(contentsOf: output)).dataSet
        #expect(ds.string(for: Tag(group: 0x0012, element: 0x0062))?.trimmingCharacters(in: .whitespaces) == "YES")
        #expect(ds.string(for: .sopInstanceUID)?.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
                == "1.2.826.0.1.3680043.2.1125.1.1")                    // Retain UIDs Option (E.3.9)

        // --keep with ps315 is refused as dicom-anon refuses it
        vm.anonKeepTags = ["0010,0010"]
        vm.runAnonymization()
        for _ in 0..<500 where vm.anonIsRunning { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(vm.anonLastExitCode == 1)
        #expect(vm.anonOutput.contains("--keep is not applied by --profile ps315"))
    }
}
