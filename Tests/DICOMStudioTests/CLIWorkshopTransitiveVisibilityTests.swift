// CLIWorkshopTransitiveVisibilityTests.swift
// DICOMStudioTests
//
// Visibility conditions chain: a field gated on a controller (`method`) that is itself
// gated on `operation == create`. The original bug (found on dicom-mwl's former create
// form): `satisfies` falls back to a referenced parameter's `defaultValue` when unset, so
// under `operation == query` the hidden `create-method` still read as its default "hl7" and
// dragged the HL7 Port and MSH-3…MSH-6 fields into the query form. These tests assert
// visibility is transitive: a condition on a hidden controller cannot hold.
//
// Since 2026-10-06 (P-STUDIO-MWL-CREATE) dicom-mwl's create flow lives in the Networking
// panel (WorklistCreateView), so the chain is reproduced here with the same shape on a
// synthetic form, and the dicom-mwl form is pinned to the CLI's only subcommand (query).

import Testing
@testable import DICOMStudio
import DICOMCore
import DICOMKit
import Foundation

@Suite("CLI Workshop — transitive parameter visibility")
@MainActor
struct CLIWorkshopTransitiveVisibilityTests {

    /// The former dicom-mwl create chain: operation → create-method → HL7 / REST fields.
    private static let chainDefs: [CLIParameterDefinition] = [
        CLIParameterDefinition(
            id: "operation", flag: "", displayName: "Operation",
            parameterType: .subcommand, placeholder: "query", helpText: "",
            isRequired: true, defaultValue: "query", allowedValues: ["query", "create"]),
        CLIParameterDefinition(
            id: "patient", flag: "--patient", displayName: "Patient",
            parameterType: .textField, placeholder: "", helpText: "",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["query"])),
        CLIParameterDefinition(
            id: "create-method", flag: "", displayName: "Create Method",
            parameterType: .enumPicker, placeholder: "hl7", helpText: "",
            isInternal: true, defaultValue: "hl7", allowedValues: ["hl7", "rest"],
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "operation", values: ["create"])),
        CLIParameterDefinition(
            id: "hl7-port", flag: "--hl7-port", displayName: "HL7 Port",
            parameterType: .integerField, placeholder: "2575", helpText: "",
            isInternal: true, defaultValue: "2575",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "create-method", values: ["hl7"])),
        CLIParameterDefinition(
            id: "sending-application", flag: "--sending-app", displayName: "Sending Application",
            parameterType: .textField, placeholder: "", helpText: "",
            isAdvanced: true, isInternal: true, defaultValue: "DICOMSTUDIO",
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "create-method", values: ["hl7"])),
        CLIParameterDefinition(
            id: "rest-base-url", flag: "--rest-url", displayName: "REST Base URL",
            parameterType: .textField, placeholder: "", helpText: "",
            isAdvanced: true, isInternal: true,
            visibleWhen: CLIParameterVisibilityCondition(parameterId: "create-method", values: ["rest"])),
    ]

    private static let hl7OnlyIDs = ["hl7-port", "sending-application"]

    private func viewModel(operation: String, createMethod: String? = nil) -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel()
        vm.setParameterDefinitions(Self.chainDefs)
        vm.experienceMode = .advanced
        vm.updateParameterValue(parameterID: "operation", value: operation)
        if let createMethod {
            vm.updateParameterValue(parameterID: "create-method", value: createMethod)
        }
        return vm
    }

    private func isVisible(_ id: String, in vm: CLIWorkshopViewModel) -> Bool {
        vm.visibleParameters().contains { $0.id == id }
    }

    // MARK: - The regression

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("fields gated on a hidden controller stay hidden")
    func testChainedFieldsHiddenForQuery() {
        let vm = viewModel(operation: "query")
        #expect(isVisible("create-method", in: vm) == false)
        for id in Self.hl7OnlyIDs {
            #expect(isVisible(id, in: vm) == false, "\(id) leaked into the query form")
        }
        #expect(isVisible("patient", in: vm) == true)
        // A value set while on the other branch does not resurrect its dependents.
        let rest = viewModel(operation: "query", createMethod: "rest")
        #expect(isVisible("rest-base-url", in: rest) == false)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("chained fields follow a visible controller, including its default")
    func testChainedFieldsVisibleWhenControllerVisible() {
        let defaulted = viewModel(operation: "create")
        for id in Self.hl7OnlyIDs {
            #expect(isVisible(id, in: defaulted) == true, "\(id) should follow the hl7 default")
        }
        let rest = viewModel(operation: "create", createMethod: "rest")
        #expect(isVisible("rest-base-url", in: rest) == true)
        for id in Self.hl7OnlyIDs {
            #expect(isVisible(id, in: rest) == false, "\(id) should be hidden for REST")
        }
    }

    // MARK: - dicom-mwl mirrors the CLI (P-STUDIO-MWL-CREATE)

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("dicom-mwl offers only the CLI's query subcommand and no create field")
    func testDicomMWLHasNoCreateForm() throws {
        let defs = ToolCatalogHelpers.parameterDefinitions(for: "dicom-mwl")
        let op = try #require(defs.first { $0.id == "operation" })
        #expect(op.allowedValues == ["query"])
        #expect(op.defaultValue == "query")
        for gone in ["create-method", "hl7-port", "create-patient-name", "create-patient-id",
                     "rest-base-url", "sending-application", "receiving-facility", "create-modality"] {
            #expect(!defs.contains { $0.id == gone }, "\(gone)")
        }
        #expect(!defs.contains { $0.isInternal })
    }
}
