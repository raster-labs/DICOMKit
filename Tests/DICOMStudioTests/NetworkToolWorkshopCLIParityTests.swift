// NetworkToolWorkshopCLIParityTests.swift
// DICOMStudioTests
//
// The DICOM tag/attribute and key-set audit (DICOM_TAG_AUDIT_PHASE2_FINDINGS.md §7)
// added matching keys and Type 1/2 attributes to the network services, and the
// `dicom-*` CLIs grew options for them. The CLI Workshop is meant to be the same
// tools with a form in front, so every one of those options needs a parameter in the
// Workshop spec — otherwise the app silently sends a less conformant data set than
// the CLI it is previewing (the MPPS Protocol Name / Referenced SOP Class case).
//
// These tests pin the option sets so the two surfaces cannot drift again. They assert
// the Workshop spec, not the network traffic: a parameter carrying the right flag,
// on the right operation, is what makes the pasted command and the in-app run agree.

import Testing
@testable import DICOMStudio
import DICOMCore
import DICOMKit
import DICOMNetwork
import Foundation

@Suite("Network tools — Workshop/CLI option parity")
@MainActor
struct NetworkToolWorkshopCLIParityTests {

    private func defs(_ tool: String) -> [CLIParameterDefinition] {
        ToolCatalogHelpers.parameterDefinitions(for: tool)
    }

    /// The parameter carrying `flag`, among those reachable in the given form.
    /// Two parameters may share a flag when their visibility is mutually exclusive
    /// (dicom-mpps' create/update split), so the lookup is scoped by operation.
    private func parameter(
        flag: String, in tool: String, operation: String? = nil
    ) -> CLIParameterDefinition? {
        defs(tool).first { def in
            guard def.flag == flag else { return false }
            guard let operation else { return true }
            let conditions = [def.visibleWhen].compactMap { $0 } + def.visibleWhenAll
            guard let opCondition = conditions.first(where: { $0.parameterId == "operation" })
            else { return true }
            return opCondition.values.contains(operation)
        }
    }

    private func assertFlags(
        _ flags: [String], in tool: String, operation: String? = nil,
        _ comment: Comment
    ) {
        for flag in flags {
            #expect(parameter(flag: flag, in: tool, operation: operation) != nil,
                    "\(tool) Workshop spec is missing \(flag) — \(comment)")
        }
    }

    // MARK: - dicom-mpps (audit #P7–#P13)

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("N-CREATE exposes the Type 1/2 attributes the CLI gained")
    func testMPPSCreateOptions() {
        assertFlags([
            "--modality",                          // Type 1 (0008,0060)
            "--patient-birth-date",                // #P7 (0010,0030)
            "--patient-sex",                       // #P7 (0010,0040)
            "--study-id",                          // #P7 (0020,0010)
            "--station-name",                      // (0040,0242)
            "--performed-location",                // #P7 (0040,0243)
            "--procedure-step-id",                 // Type 1 (0040,0253)
            "--procedure-step-description",        // (0040,0254)
            "--performing-physician",              // (0008,1050)
            "--requested-procedure-id",            // #P7 (0040,1001)
            "--requested-procedure-description",   // #P8 (0032,1060)
            "--sps-description",                   // #P8 (0040,0007)
            "--referenced-study-uid",              // #P3 (0008,1155)
        ], in: "dicom-mpps", operation: "create", "added by audit #P7/#P8")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("N-SET exposes the Performed Series attributes the CLI gained")
    func testMPPSUpdateOptions() {
        assertFlags([
            "--sop-class-uid",                     // #P10 — the SC placeholder bug
            "--protocol-name",                     // #P9 Type 1 (0018,1030)
            "--series-description",                // #P9 (0008,103E)
            "--operator-name",                     // #P9 (0008,1070)
            "--performing-physician",              // #P9 (0008,1050)
            "--discontinuation-reason",            // (0040,0281)
            "--legacy-nset-scheduled-attributes",  // #P13
        ], in: "dicom-mpps", operation: "update", "added by audit #P9/#P10/#P13")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("Requested Procedure ID is its own field, not the Performed Step ID")
    func testMPPSRequestedProcedureIDIsDistinct() throws {
        // #P7: the two were conflated — both were sent as the PPS ID. They are
        // separate attributes (0040,1001) and (0040,0253) and need separate fields.
        let requested = try #require(parameter(flag: "--requested-procedure-id",
                                               in: "dicom-mpps", operation: "create"))
        let step = try #require(parameter(flag: "--procedure-step-id",
                                          in: "dicom-mpps", operation: "create"))
        #expect(requested.id != step.id)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("the two --performing-physician fields never appear together")
    func testMPPSPerformingPhysicianIsOperationScoped() throws {
        // Create and update both take --performing-physician, so the spec carries two
        // parameters on one flag. The command preview gates on visibility, so exactly
        // one must be reachable per operation or the pasted command would repeat it.
        let sharing = defs("dicom-mpps").filter { $0.flag == "--performing-physician" }
        #expect(sharing.count == 2)
        for def in sharing {
            let condition = try #require(def.visibleWhen, "\(def.id) has no visibleWhen")
            #expect(condition.parameterId == "operation")
        }
        #expect(Set(sharing.flatMap { $0.visibleWhen?.values ?? [] }) == ["create", "update"])
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("the discontinuation reason is gated on the DISCONTINUED status")
    func testMPPSDiscontinuationReasonGating() throws {
        // The CLI rejects --discontinuation-reason unless --status DISCONTINUED;
        // the Workshop hides it instead, which needs both conditions to hold.
        let def = try #require(parameter(flag: "--discontinuation-reason",
                                         in: "dicom-mpps", operation: "update"))
        let ids = Set(def.visibleWhenAll.map { $0.parameterId })
        #expect(ids == ["operation", "status-update"])
        let status = try #require(def.visibleWhenAll.first { $0.parameterId == "status-update" })
        #expect(status.values == ["DISCONTINUED"])
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("the discontinuation reason field is hidden for a COMPLETED update")
    func testMPPSDiscontinuationReasonHiddenWhenCompleted() {
        let vm = CLIWorkshopViewModel()
        vm.setParameterDefinitions(defs("dicom-mpps"))
        vm.experienceMode = .advanced
        vm.updateParameterValue(parameterID: "operation", value: "update")
        vm.updateParameterValue(parameterID: "status-update", value: "COMPLETED")
        #expect(vm.visibleParameters().contains { $0.id == "discontinuation-reason" } == false)

        vm.updateParameterValue(parameterID: "status-update", value: "DISCONTINUED")
        #expect(vm.visibleParameters().contains { $0.id == "discontinuation-reason" })
    }

    // MARK: - The shared coded-entry grammar

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("CODE|SCHEME|MEANING parses the same for the CLI and the Workshop")
    func testCodedEntryParsing() throws {
        // Real CID 9301 pairs (PS3.16 2026a Table D-1): 110513 is "Discontinued for unspecified reason",
        // 110501 is "Equipment failure" (D88).
        let entry = try #require(MPPSCodedEntry.parse("110513|DCM|Discontinued for unspecified reason"))
        #expect(entry.codeValue == "110513")
        #expect(entry.codingSchemeDesignator == "DCM")
        #expect(entry.codeMeaning == "Discontinued for unspecified reason")

        // Whitespace around the parts is trimmed; a meaning may contain '|'.
        let spaced = try #require(MPPSCodedEntry.parse(" 110501 | DCM | Equipment failure "))
        #expect(spaced.codeValue == "110501")
        #expect(spaced.codeMeaning == "Equipment failure")
        let piped = try #require(MPPSCodedEntry.parse("1|DCM|a|b"))
        #expect(piped.codeMeaning == "a|b")

        // Too few parts, or an empty part, is not a coded entry.
        #expect(MPPSCodedEntry.parse("110513|DCM") == nil)
        #expect(MPPSCodedEntry.parse("110513||Meaning") == nil)
        #expect(MPPSCodedEntry.parse("") == nil)
    }

    // MARK: - dicom-mwl (audit #P1–#P5)

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("the worklist query exposes the Performing Physician matching key")
    func testMWLPerformingPhysician() throws {
        // K.6-1 required matching key (0040,0006), added 09-17.
        let def = try #require(parameter(flag: "--performing-physician", in: "dicom-mwl"))
        #expect(def.helpText.contains("0040,0006"))
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("corrected tag numbers appear in the worklist help text")
    func testMWLHelpTextTags() throws {
        // The audit corrected these three in the Workshop help; they are what a user
        // reads to know which attribute a filter maps to.
        let modality = try #require(parameter(flag: "--modality", in: "dicom-mwl"))
        #expect(modality.helpText.contains("0008,0060"))
        let status = try #require(parameter(flag: "--sps-status", in: "dicom-mwl"))
        #expect(status.helpText.contains("0040,0020"))
        let desc = try #require(defs("dicom-mwl").first { $0.id == "procedure-desc" })
        #expect(desc.helpText.contains("0032,1060"))
    }

    // MARK: - dicom-query (audit #P15)

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("the parent-key opt-out is offered at series and instance level")
    func testQueryIncludeParentKeys() throws {
        let def = try #require(parameter(flag: "--include-parent-keys", in: "dicom-query"))
        let condition = try #require(def.visibleWhen)
        #expect(condition.parameterId == "level")
        // Parent keys only exist below the study level; PATIENT/STUDY queries already
        // request every key at their own level.
        #expect(Set(condition.values) == ["series", "instance"])
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("the parent-key toggle is hidden for a study-level query")
    func testQueryIncludeParentKeysHiddenAtStudyLevel() {
        let vm = CLIWorkshopViewModel()
        vm.setParameterDefinitions(defs("dicom-query"))
        vm.experienceMode = .advanced
        vm.updateParameterValue(parameterID: "level", value: "study")
        #expect(vm.visibleParameters().contains { $0.id == "include-parent-keys" } == false)

        vm.updateParameterValue(parameterID: "level", value: "series")
        #expect(vm.visibleParameters().contains { $0.id == "include-parent-keys" })
    }

    // MARK: - dicom-qido (audit #P20)

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("the series-level QIDO matching keys are exposed")
    func testQIDOSeriesLevelFilters() throws {
        // PS3.18 Table 10.6.1-5 series keys added to QIDOQuery by #P20.
        for flag in ["--pps-start-date", "--pps-start-time",
                     "--sps-id", "--requested-procedure-id"] {
            let def = try #require(parameter(flag: flag, in: "dicom-qido"),
                                   "dicom-qido Workshop spec is missing \(flag)")
            // They only match at the series level, so the form must scope them there
            // rather than letting a study query send a key the server will ignore.
            let condition = try #require(def.visibleWhen, "\(flag) has no visibleWhen")
            #expect(condition.parameterId == "level")
            #expect(condition.values == ["series"])
        }
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("QIDO series filters are hidden for a study-level search")
    func testQIDOSeriesFiltersHiddenAtStudyLevel() {
        let vm = CLIWorkshopViewModel()
        vm.setParameterDefinitions(defs("dicom-qido"))
        vm.experienceMode = .advanced
        vm.updateParameterValue(parameterID: "level", value: "study")
        for id in ["pps-start-date", "pps-start-time",
                   "qido-sps-id", "qido-requested-procedure-id"] {
            #expect(vm.visibleParameters().contains { $0.id == id } == false,
                    "\(id) leaked into the study-level form")
        }

        vm.updateParameterValue(parameterID: "level", value: "series")
        for id in ["pps-start-date", "pps-start-time",
                   "qido-sps-id", "qido-requested-procedure-id"] {
            #expect(vm.visibleParameters().contains { $0.id == id }, "\(id) missing at series level")
        }
    }

    // MARK: - Spec hygiene

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("no network tool has a duplicate parameter id")
    func testNoDuplicateParameterIDs() {
        for tool in ["dicom-mpps", "dicom-mwl", "dicom-query", "dicom-qido", "dicom-retrieve"] {
            let ids = defs(tool).map { $0.id }
            #expect(ids.count == Set(ids).count, "\(tool) has a duplicate parameter id")
        }
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("a flag shared by two parameters is always operation-scoped")
    func testSharedFlagsAreDisambiguated() {
        // A repeated flag is legitimate only when visibility keeps the two apart;
        // otherwise the command preview would emit it twice.
        for tool in ["dicom-mpps", "dicom-mwl", "dicom-query", "dicom-qido"] {
            let emitting = defs(tool).filter { !$0.flag.isEmpty && !$0.isInternal }
            for (flag, group) in Dictionary(grouping: emitting, by: { $0.flag }) where group.count > 1 {
                for def in group {
                    let conditions = [def.visibleWhen].compactMap { $0 } + def.visibleWhenAll
                    #expect(conditions.isEmpty == false,
                            "\(tool) \(flag) is on \(group.count) parameters but \(def.id) is unconditional")
                }
            }
        }
    }
}
