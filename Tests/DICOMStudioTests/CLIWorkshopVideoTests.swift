// CLIWorkshopVideoTests.swift
// DICOMStudio
//
// Pins the CLI Workshop's `dicom-video` form: that every subcommand exposes
// exactly the flags the `dicom-video` CLI declares, that the visibility rules
// keep one subcommand's flags out of another's form, and that the command
// preview the form builds is a command the CLI would accept.
//
// The executor itself runs DICOMKit's shared `VideoWorkflow` / `VideoConsole`,
// whose behaviour is pinned by `Tests/DICOMRoundTripTest/VideoConsoleParityTests`.
// What is app-specific — and therefore tested here — is the form.

import Testing
import Foundation
import DICOMKit
@testable import DICOMStudio

@Suite("CLI Workshop — dicom-video")
struct CLIWorkshopVideoTests {

    private var definitions: [CLIParameterDefinition] {
        ToolCatalogHelpers.parameterDefinitions(for: "dicom-video")
    }

    private func definition(_ id: String) -> CLIParameterDefinition? {
        definitions.first { $0.id == id }
    }

    /// The form values for one subcommand, with any extra fields the caller sets.
    private func values(
        operation: String, _ extra: [String: String] = [:]
    ) -> [CLIParameterValue] {
        var all = [CLIParameterValue(parameterID: "operation", stringValue: operation)]
        for (key, value) in extra.sorted(by: { $0.key < $1.key }) {
            all.append(CLIParameterValue(parameterID: key, stringValue: value))
        }
        return all
    }

    /// The parameter IDs the form shows for a subcommand.
    private func visibleIDs(operation: String, _ extra: [String: String] = [:]) -> Set<String> {
        let vals = values(operation: operation, extra)
        return Set(definitions.filter {
            CommandBuilderHelpers.isVisible(
                $0, parameterValues: vals, parameterDefinitions: definitions)
        }.map(\.id))
    }

    // MARK: - Catalog Registration

    @Test("dicom-video is in the tool catalog and declares subcommands")
    func toolIsRegistered() {
        let tool = ToolCatalogHelpers.allTools().first { $0.id == "dicom-video" }
        let video = try! #require(tool)
        #expect(video.name == "dicom-video")
        #expect(video.category == .dataExport)
        #expect(video.hasSubcommands)
        // The Workshop shows the standard reference next to the tool.
        #expect(video.dicomStandardRef == "PS3.3 A.32.5")
    }

    @Test("the tool carries a purpose description and capability bullets")
    func toolIsDocumented() {
        #expect(!ToolCatalogHelpers.toolPurposeDescription(for: "dicom-video").isEmpty)
        #expect(ToolCatalogHelpers.toolCapabilities(for: "dicom-video").count >= 5)
    }

    // MARK: - Subcommands

    @Test("the four CLI subcommands are offered, convert first")
    func subcommandsMatchTheCLI() {
        let operation = try! #require(definition("operation"))
        #expect(operation.parameterType == .subcommand)
        #expect(operation.allowedValues == ["convert", "probe", "extract", "batch"])
        #expect(operation.defaultValue == "convert")
        #expect(operation.isRequired)
    }

    // MARK: - Per-Subcommand Visibility

    /// convert takes a video in and writes a DICOM object out.
    @Test("convert shows its own inputs and no other subcommand's")
    func convertVisibility() {
        let visible = visibleIDs(operation: "convert")

        for id in ["input", "output", "type", "transferSyntax", "frameRate",
                   "instanceNumber", "seriesNumber", "dryRun", "trustInput", "force",
                   "patientName", "patientID", "seriesDescription"] {
            #expect(visible.contains(id), "convert should offer \(id)")
        }
        for id in ["dicomInput", "videoOutput", "inputDirectory", "outputDir",
                   "seriesMode", "recursive", "continueOnError"] {
            #expect(!visible.contains(id), "convert should not offer \(id)")
        }
    }

    /// probe writes nothing, so no output or overwrite field belongs on it.
    @Test("probe shows only an input and the trust-input flag")
    func probeVisibility() {
        let visible = visibleIDs(operation: "probe")

        #expect(visible.contains("input"))
        #expect(visible.contains("trustInput"))
        for id in ["output", "videoOutput", "outputDir", "force", "dryRun",
                   "type", "transferSyntax", "frameRate", "patientName"] {
            #expect(!visible.contains(id), "probe writes nothing, so \(id) is meaningless")
        }
    }

    /// extract reverses the conversion: DICOM in, video out.
    @Test("extract shows the DICOM input and the video output")
    func extractVisibility() {
        let visible = visibleIDs(operation: "extract")

        #expect(visible.contains("dicomInput"))
        #expect(visible.contains("videoOutput"))
        #expect(visible.contains("force"))
        for id in ["input", "output", "type", "transferSyntax", "frameRate",
                   "dryRun", "trustInput", "patientName", "seriesMode"] {
            #expect(!visible.contains(id), "extract should not offer \(id)")
        }
    }

    /// batch adds the grouping and traversal flags, and drops the per-object ones.
    @Test("batch shows grouping and traversal, not per-object numbering")
    func batchVisibility() {
        let visible = visibleIDs(operation: "batch")

        for id in ["inputDirectory", "outputDir", "seriesMode", "recursive",
                   "continueOnError", "dryRun", "force", "type", "transferSyntax",
                   "patientName", "seriesUID"] {
            #expect(visible.contains(id), "batch should offer \(id)")
        }
        for id in ["input", "output", "dicomInput", "videoOutput",
                   "frameRate", "instanceNumber", "seriesNumber", "trustInput"] {
            #expect(!visible.contains(id), "batch should not offer \(id)")
        }
    }

    // MARK: - Flags Match the CLI

    /// Every flag in the form has to be one `dicom-video` actually declares —
    /// a typo here produces a copy-pasteable command the CLI would reject.
    @Test("every flag the form emits is one the CLI declares")
    func flagsMatchTheCLI() {
        let declared: Set<String> = [
            "--output", "--output-dir", "--type", "--transfer-syntax", "--frame-rate",
            "--instance-number", "--series-number", "--series-mode", "--dry-run",
            "--trust-input", "--force", "--recursive", "--continue-on-error",
            "--patient-name", "--patient-id", "--patient-birth-date", "--patient-sex",
            "--study-uid", "--series-uid", "--accession-number", "--study-id",
            "--referring-physician", "--series-description", "--modality", "--strict-modality",
            "--manufacturer", "--institution-name", "--audio-channel-source", "--verbose",
        ]

        for def in definitions where !def.flag.isEmpty {
            #expect(declared.contains(def.flag),
                    "\(def.id) emits \(def.flag), which dicom-video does not declare")
        }
    }

    /// The positional arguments carry no flag, because the CLI takes them by
    /// position: `dicom-video convert <input> --output …`.
    @Test("inputs are positional, as the CLI takes them")
    func inputsArePositional() {
        for id in ["input", "dicomInput", "inputDirectory"] {
            let def = try! #require(definition(id))
            #expect(def.flag.isEmpty, "\(id) is a positional argument")
            #expect(def.isRequired)
        }
    }

    /// The enum pickers offer exactly the values the shared argument types
    /// accept, so a picked value always parses.
    @Test("pickers offer exactly the shared enums' raw values")
    func pickersMatchTheSharedEnums() {
        let type = try! #require(definition("type"))
        // A leading empty entry means "let the tool default and say so".
        #expect(type.allowedValues == ["", "endoscopic", "microscopic", "photographic"])
        #expect(type.allowedValues.dropFirst().allSatisfy {
            VideoConsole.TypeArgument(rawValue: $0) != nil
        })

        let seriesMode = try! #require(definition("seriesMode"))
        #expect(seriesMode.allowedValues == ["single", "per-file"])
        #expect(seriesMode.defaultValue == "single")
        #expect(seriesMode.allowedValues.allSatisfy {
            VideoConsole.SeriesMode(rawValue: $0) != nil
        })

        // Patient's Sex is a CS with a fixed set of values.
        let sex = try! #require(definition("patientSex"))
        #expect(sex.allowedValues == ["", "M", "F", "O"])
    }

    /// The form's help comes from the shared console, so the field help and the
    /// CLI's `--help` cannot drift apart.
    @Test("help text is sourced from the shared VideoConsole")
    func helpTextIsShared() {
        #expect(definition("input")?.helpText == VideoConsole.Help.input)
        #expect(definition("output")?.helpText == VideoConsole.Help.output)
        #expect(definition("dicomInput")?.helpText == VideoConsole.Help.extractInput)
        #expect(definition("videoOutput")?.helpText == VideoConsole.Help.extractOutput)
        #expect(definition("inputDirectory")?.helpText == VideoConsole.Help.batchInput)
        #expect(definition("outputDir")?.helpText == VideoConsole.Help.batchOutputDir)
        #expect(definition("recursive")?.helpText == VideoConsole.Help.recursive)
        #expect(definition("dryRun")?.helpText == VideoConsole.Help.dryRun)
        #expect(definition("force")?.helpText == VideoConsole.Help.force)
    }

    // MARK: - Command Preview

    @Test("convert previews the command the CLI would run")
    func convertPreview() {
        let vals = values(operation: "convert", [
            "input": "clip.mp4", "output": "clip.dcm", "type": "endoscopic",
        ])
        let cmd = CommandBuilderHelpers.buildCommand(
            toolName: "dicom-video", parameterValues: vals,
            parameterDefinitions: definitions)
        #expect(cmd == "dicom-video convert clip.mp4 --output clip.dcm --type endoscopic")
    }

    @Test("boolean flags appear only when switched on")
    func booleanFlagsPreview() {
        let off = CommandBuilderHelpers.buildCommand(
            toolName: "dicom-video",
            parameterValues: values(operation: "convert", [
                "input": "clip.mp4", "output": "clip.dcm",
                "dryRun": "false", "force": "false",
            ]),
            parameterDefinitions: definitions)
        #expect(!off.contains("--dry-run"))
        #expect(!off.contains("--force"))

        let on = CommandBuilderHelpers.buildCommand(
            toolName: "dicom-video",
            parameterValues: values(operation: "convert", [
                "input": "clip.mp4", "output": "clip.dcm",
                "dryRun": "true", "force": "true",
            ]),
            parameterDefinitions: definitions)
        #expect(on.contains("--dry-run"))
        #expect(on.contains("--force"))
    }

    @Test("probe previews without an output flag")
    func probePreview() {
        let cmd = CommandBuilderHelpers.buildCommand(
            toolName: "dicom-video",
            parameterValues: values(operation: "probe", [
                "input": "clip.mp4", "trustInput": "true",
                // A value left over from a previous convert must not leak in.
                "output": "stale.dcm",
            ]),
            parameterDefinitions: definitions)
        #expect(cmd == "dicom-video probe clip.mp4 --trust-input")
        #expect(!cmd.contains("stale.dcm"))
    }

    @Test("extract previews the DICOM input and video output")
    func extractPreview() {
        let cmd = CommandBuilderHelpers.buildCommand(
            toolName: "dicom-video",
            parameterValues: values(operation: "extract", [
                "dicomInput": "clip.dcm", "videoOutput": "clip.mp4",
            ]),
            parameterDefinitions: definitions)
        #expect(cmd == "dicom-video extract clip.dcm --output clip.mp4")
    }

    @Test("batch previews grouping and traversal flags")
    func batchPreview() {
        let cmd = CommandBuilderHelpers.buildCommand(
            toolName: "dicom-video",
            parameterValues: values(operation: "batch", [
                "inputDirectory": "clips", "outputDir": "out",
                "seriesMode": "per-file", "recursive": "true",
                "continueOnError": "true",
            ]),
            parameterDefinitions: definitions)
        #expect(cmd == "dicom-video batch clips --output-dir out "
                + "--series-mode per-file --recursive --continue-on-error")
    }

    @Test("paths with spaces are escaped for pasting")
    func pathsAreEscaped() {
        let cmd = CommandBuilderHelpers.buildCommand(
            toolName: "dicom-video",
            parameterValues: values(operation: "convert", [
                "input": "my clips/scope 1.mp4", "output": "out dir/scope.dcm",
            ]),
            parameterDefinitions: definitions)
        // A bare space would split the token when pasted into a shell.
        #expect(!cmd.contains("my clips/scope 1.mp4 "))
        #expect(cmd.contains("scope"))
    }

    /// Metadata reaches the preview with the CLI's own flag spellings.
    @Test("metadata flags preview with their CLI spellings")
    func metadataPreview() {
        let cmd = CommandBuilderHelpers.buildCommand(
            toolName: "dicom-video",
            parameterValues: values(operation: "convert", [
                "input": "clip.mp4", "output": "clip.dcm",
                "patientName": "Doe^Jane", "patientID": "P123",
                "patientBirthDate": "19800101", "patientSex": "F",
                "accessionNumber": "A99", "studyID": "S1",
                "referringPhysician": "Ref^Dr", "modality": "ES",
                "manufacturer": "Acme", "institutionName": "General Hospital",
            ]),
            parameterDefinitions: definitions)

        for fragment in ["--patient-name Doe^Jane", "--patient-id P123",
                         "--patient-birth-date 19800101", "--patient-sex F",
                         "--accession-number A99", "--study-id S1",
                         "--referring-physician Ref^Dr", "--modality ES",
                         "--manufacturer Acme"] {
            #expect(cmd.contains(fragment), "expected \(fragment) in: \(cmd)")
        }
    }

    // MARK: - Verbose

    /// `--verbose` applies to all four subcommands, so unlike every other flag
    /// it carries no visibility condition.
    @Test("verbose is offered on every subcommand")
    func verboseIsAlwaysVisible() {
        for operation in ["convert", "probe", "extract", "batch"] {
            #expect(visibleIDs(operation: operation).contains("verbose"),
                    "\(operation) should offer verbose")
        }
    }

    /// It is a toggle that defaults off, so a form left alone runs exactly as
    /// it did before the flag existed.
    @Test("verbose is a toggle that defaults off")
    func verboseDefaultsOff() {
        let def = try! #require(definition("verbose"))
        #expect(def.parameterType == .booleanToggle)
        #expect(def.defaultValue == "false")
        #expect(def.flag == "--verbose")
    }

    /// The toggle's help opens with the CLI's own `--help` wording, so the two
    /// surfaces describe the flag the same way.
    @Test("verbose help comes from the shared VideoConsole")
    func verboseHelpIsShared() {
        let def = try! #require(definition("verbose"))
        #expect(def.helpText.hasPrefix(VideoConsole.Help.verbose))
    }

    /// Switched on, it previews as the flag the CLI accepts; left off it adds
    /// nothing to the command.
    @Test("verbose previews as --verbose only when switched on")
    func verbosePreviews() {
        let on = CommandBuilderHelpers.buildCommand(
            toolName: "dicom-video",
            parameterValues: values(operation: "probe",
                                    ["input": "clip.mp4", "verbose": "true"]),
            parameterDefinitions: definitions)
        #expect(on.contains("--verbose"))

        let off = CommandBuilderHelpers.buildCommand(
            toolName: "dicom-video",
            parameterValues: values(operation: "probe",
                                    ["input": "clip.mp4", "verbose": "false"]),
            parameterDefinitions: definitions)
        #expect(!off.contains("--verbose"))
    }
}
