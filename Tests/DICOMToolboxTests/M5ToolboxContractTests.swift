import Foundation
import XCTest
@testable import DICOMToolbox

final class M5ToolboxContractTests: XCTestCase {
    private let anon = CommandBuilder(tool: ToolRegistry.dicomAnon)
    private let script = CommandBuilder(tool: ToolRegistry.dicomScript)

    func testProfilesMatchCurrentCLIAndDoNotImplySeparateRetentionPolicies() throws {
        let profile = try XCTUnwrap(ToolRegistry.dicomAnon.parameters.first { $0.id == "profile" })
        XCTAssertEqual(profile.defaultValue, "ps315")
        XCTAssertEqual(profile.enumValues?.map(\.value), ["ps315", "basic"])
        XCTAssertTrue(profile.enumValues?.last?.label.contains("alias") == true)
        XCTAssertTrue(ToolRegistry.dicomAnon.discussion.contains("does not certify"))
        for value in ["ps315", "basic"] {
            let invocation = try anon.validatedInvocation(values: ["inputPath": "scan.dcm", "profile": value])
            XCTAssertEqual(invocation.arguments, ["scan.dcm", "--profile", value])
        }
    }

    func testLegacyProfilesRefuseWithActionableRebuildInstructions() {
        for value in ["clinical-trial", "research", "unknown"] {
            let values = ["inputPath": "scan.dcm", "profile": value]
            XCTAssertFalse(anon.isValid(values: values))
            XCTAssertThrowsError(try anon.validatedInvocation(values: values)) { error in
                XCTAssertTrue(error.localizedDescription.contains("Select PS3.15"))
                XCTAssertTrue(error.localizedDescription.contains("not equivalent"))
            }
            XCTAssertTrue(anon.buildCommand(values: values).hasPrefix("# Cannot run:"))
        }
    }

    func testRemovedSettingsAreNotSilentlyDroppedEvenWhenFalse() {
        for (key, value) in [("keep", "0010,0040"), ("regenerate-uids", "true"), ("regenerate-uids", "false")] {
            let values = ["inputPath": "scan.dcm", key: value]
            XCTAssertFalse(anon.isValid(values: values))
            XCTAssertThrowsError(try anon.validatedInvocation(values: values)) { error in
                XCTAssertTrue(error.localizedDescription.lowercased().contains("discard"))
            }
        }
        XCTAssertFalse(ToolRegistry.dicomAnon.parameters.contains { ["--keep", "--regenerate-uids"].contains($0.cliFlag) })
    }

    func testUIDRegenerationIsDefaultAndRetentionIsExplicit() throws {
        for value in [nil, "", "false", "true"] as [String?] {
            var values = ["inputPath": "scan.dcm"]
            values["retain-uids"] = value
            let argv = try anon.validatedInvocation(values: values).arguments
            XCTAssertEqual(argv.contains("--retain-uids"), value == "true")
            XCTAssertFalse(argv.contains("--regenerate-uids"))
        }
    }

    func testCurrentAnonPresetsProduceValidatedCurrentArguments() throws {
        for preset in ExamplePresets.presets(for: "dicom-anon") {
            let invocation = try anon.validatedInvocation(values: preset.parameterValues, subcommand: preset.subcommand)
            XCTAssertNil(ToolboxCommandContract.replayIssue(invocation))
            XCTAssertEqual(preset.parameterValues["profile"], "ps315")
        }
    }

    func testRetiredPersistedArgvCannotReplayCopyOrExportAsExecutableText() throws {
        for arguments in [["scan.dcm", "--keep", "0010,0040"], ["scan.dcm", "--keep=0010,0040"],
                          ["scan.dcm", "--regenerate-uids"], ["scan.dcm", "--profile=research"]] {
            let invocation = CommandInvocation(executable: "dicom-anon", arguments: arguments)
            let entry = CommandHistoryEntry(toolID: "dicom-anon", parameterValues: [:], commandString: "ignored", invocation: invocation)
            let restored = try JSONDecoder().decode(CommandHistoryEntry.self, from: JSONEncoder().encode(entry))
            XCTAssertNil(restored.replayInvocation)
            XCTAssertNotNil(restored.replayRefusalReason)
            XCTAssertTrue(restored.copyableCommand.components(separatedBy: .newlines).allSatisfy { $0.hasPrefix("# ") })
            let executableLines = CommandHistory.exportAsShellScript([restored]).components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("#") }
            XCTAssertTrue(executableLines.isEmpty)
        }
    }

    func testPersistedLegacyParameterDictionaryCannotHideBehindCurrentArgv() {
        let entry = CommandHistoryEntry(toolID: "dicom-anon", parameterValues: ["keep": "0010,0040"], commandString: "ignored",
            invocation: .init(executable: "dicom-anon", arguments: ["scan.dcm"]))
        XCTAssertNil(entry.replayInvocation)
        XCTAssertTrue(entry.replayRefusalReason?.contains("--keep") == true)
    }

    func testTemplateNameIsRequiredAndAllFiveNamesArePositional() throws {
        XCTAssertFalse(script.isValid(values: [:], subcommand: "template"))
        XCTAssertThrowsError(try script.validatedInvocation(values: [:], subcommand: "template"))
        XCTAssertEqual(script.missingRequiredParameters(values: [:], subcommand: "template"), ["Template Name"])
        let template = try XCTUnwrap(ToolRegistry.dicomScript.subcommands?.first { $0.id == "template" })
        XCTAssertEqual(template.parameters.count, 1)
        XCTAssertEqual(template.parameters.first?.enumValues?.map(\.value), ["workflow", "pipeline", "query", "archive", "anonymize"])
        for name in ToolboxCommandContract.scriptTemplates {
            let invocation = try script.validatedInvocation(values: ["template-name": name], subcommand: "template")
            XCTAssertEqual(invocation.arguments, ["template", name])
            XCTAssertFalse(invocation.arguments.contains("--output"))
        }
        XCTAssertThrowsError(try script.validatedInvocation(values: ["template-name": "unknown"], subcommand: "template"))
    }

    func testSavedTemplateOutputRefusesWithConsoleCopyGuidance() {
        let values = ["template-name": "workflow", "output": "/tmp/template.dscript"]
        XCTAssertThrowsError(try script.validatedInvocation(values: values, subcommand: "template")) { error in
            XCTAssertTrue(error.localizedDescription.contains("copy the generated script"))
        }
        for arguments in [["template"], ["template", "--output", "/tmp/template"], ["template", "workflow", "--output=/tmp/template"]] {
            let entry = CommandHistoryEntry(toolID: "dicom-script", subcommand: "template", parameterValues: [:], commandString: "ignored",
                invocation: .init(executable: "dicom-script", arguments: arguments))
            XCTAssertNil(entry.replayInvocation)
            XCTAssertTrue(entry.copyableCommand.hasPrefix("# "))
        }
    }

    func testValidatedArgumentsStillPreserveLiteralDataAndNegativeDateShift() throws {
        let input = "space path/$(touch sentinel); O'Neil.dcm"
        let invocation = try anon.validatedInvocation(values: ["inputPath": input, "shift-dates": "-30", "replace": "0010,0010=DOE*\\PRIMARY"])
        XCTAssertEqual(invocation.arguments, [input, "--shift-dates=-30", "--replace", "0010,0010=DOE*\\PRIMARY"])
    }

    /// Exports *actual library-built* argv for the parent's independent CLI oracle.
    /// No subprocess or file processing occurs in this XCTest method.
    func testExportCurrentCLIInvocationsForIndependentProcessGate() throws {
        guard let path = ProcessInfo.processInfo.environment["DICOMKIT_M5_TOOLBOX_EXPORT_DIR"] else {
            throw XCTSkip("Set DICOMKIT_M5_TOOLBOX_EXPORT_DIR to export the real Toolbox argv for the independent CLI gate")
        }
        let root = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var cases: [[String: Any]] = []
        func addAnon(_ name: String, values extra: [String: String], uidPolicy: String, dryRun: Bool = false, directory: Bool = false) throws {
            var values = ["inputPath": root.appendingPathComponent(directory ? "input-directory" : "input.dcm").path,
                          "output": root.appendingPathComponent(directory ? name : name + ".dcm").path]
            values.merge(extra) { _, new in new }
            let invocation = try anon.validatedInvocation(values: values)
            cases.append(["id": name, "tool": invocation.executable, "arguments": invocation.arguments,
                          "values": values, "expectedUIDPolicy": uidPolicy, "dryRun": dryRun, "directory": directory])
        }
        for profile in ToolboxCommandContract.anonymizationProfiles {
            try addAnon("anon-" + profile, values: ["profile": profile], uidPolicy: "regenerate")
            try addAnon("anon-" + profile + "-retain", values: ["profile": profile, "retain-uids": "true"], uidPolicy: "retain")
        }
        try addAnon("anon-all-current-controls", values: ["profile": "ps315", "shift-dates": "-30", "retain-uids": "true",
            "remove": "0008,0050", "replace": "0008,1030=SYNTHETIC", "backup": "true", "audit-log": root.appendingPathComponent("audit.log").path], uidPolicy: "retain")
        try addAnon("anon-dry-run", values: ["profile": "ps315", "dry-run": "true"], uidPolicy: "no-output", dryRun: true)
        try addAnon("anon-recursive", values: ["profile": "ps315", "recursive": "true"], uidPolicy: "regenerate", directory: true)
        for name in ToolboxCommandContract.scriptTemplates {
            let invocation = try script.validatedInvocation(values: ["template-name": name], subcommand: "template")
            cases.append(["id": "template-" + name, "tool": invocation.executable, "arguments": invocation.arguments,
                          "stdoutFile": root.appendingPathComponent(name + ".dscript").path])
        }
        let manifest: [String: Any] = ["schemaVersion": 1, "cases": cases,
            "fixtureRequirements": "Create input.dcm and input-directory/nested/input.dcm from synthetic Part 10 data with Study/Series/SOP Instance UIDs, StudyDate=20260115, AccessionNumber=TEST-ACCESSION, StudyDescription=BEFORE. Use no Pixel Data to avoid unqualified OCR, or a known safe synthetic pixel fixture. Never use patient data.",
            "oracle": "Run each argv with the current CLI. Check exit 0, unchanged inputs, default UID replacement vs --retain-uids equality and valid output meta/dataset identities. All-controls must remove AccessionNumber, replace StudyDescription, shift StudyDate to 20251216, write audit log and a byte-identical original-input backup at outputURL.appendingPathExtension(backup), namely anon-all-current-controls.dcm.backup. Dry-run writes no output. Recursive discovers nested input. Save template stdout as app/test action then run dicom-script validate on all five outputs.",
            "scope": "DICOMToolbox library is not packaged into DICOMStudio in this repository; no packaged Toolbox UI claim."]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("toolbox-cli-manifest.json"))
        XCTAssertEqual(cases.count, 12)
    }
}
