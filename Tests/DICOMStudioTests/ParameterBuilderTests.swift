// ParameterBuilderTests.swift
// DICOMStudioTests
//
// DICOM Studio — Tests for Dynamic GUI Controls & Parameter Builder (Milestone 21)

import Testing
@testable import DICOMStudio
import Foundation

// MARK: - Model Tests

@Suite("Parameter Builder Model Tests")
struct ParameterBuilderModelTests {

    // MARK: - PickerOption

    @Test("PickerOption initialiser sets id, displayName, cliValue")
    func test_pickerOption_init_setsFields() {
        let opt = PickerOption(id: "json", displayName: "JSON", cliValue: "json")
        #expect(opt.id == "json")
        #expect(opt.displayName == "JSON")
        #expect(opt.cliValue == "json")
    }

    @Test("PickerOption id is used for Identifiable conformance")
    func test_pickerOption_identifiable_usesId() {
        let opt = PickerOption(id: "xml", displayName: "XML", cliValue: "xml")
        #expect(opt.id == "xml")
    }

    // MARK: - ParameterValidation

    @Test("ParameterValidation.required displayName is 'Required'")
    func test_parameterValidation_required_displayName() {
        #expect(ParameterValidation.required.displayName == "Required")
    }

    @Test("ParameterValidation.maxLength displayName contains the length")
    func test_parameterValidation_maxLength_displayNameContainsLength() {
        let v = ParameterValidation.maxLength(16)
        #expect(v.displayName.contains("16"))
    }

    @Test("ParameterValidation.range displayName contains min and max")
    func test_parameterValidation_range_displayNameContainsMinMax() {
        let v = ParameterValidation.range(min: 1.0, max: 65535.0)
        #expect(v.displayName.contains("1"))
        #expect(v.displayName.contains("65535"))
    }

    @Test("ParameterValidation.regex displayName contains the pattern")
    func test_parameterValidation_regex_displayNameContainsPattern() {
        let v = ParameterValidation.regex("[A-Z]+")
        #expect(v.displayName.contains("[A-Z]+"))
    }

    @Test("ParameterValidation.custom displayName returns the given description")
    func test_parameterValidation_custom_displayNameEqualsDescription() {
        let v = ParameterValidation.custom(description: "Must be unique")
        #expect(v.displayName == "Must be unique")
    }

    // MARK: - ParameterType

    @Test("ParameterType.text displayName is 'Text'")
    func test_parameterType_text_displayName() {
        #expect(ParameterType.text(placeholder: "").displayName == "Text")
    }

    @Test("ParameterType.toggle displayName is 'Toggle'")
    func test_parameterType_toggle_displayName() {
        #expect(ParameterType.toggle.displayName == "Toggle")
    }

    @Test("ParameterType.picker displayName is 'Picker'")
    func test_parameterType_picker_displayName() {
        #expect(ParameterType.picker(options: []).displayName == "Picker")
    }

    @Test("ParameterType.aeTitle displayName is 'AE Title'")
    func test_parameterType_aeTitle_displayName() {
        #expect(ParameterType.aeTitle.displayName == "AE Title")
    }

    @Test("ParameterType.port displayName is 'Port'")
    func test_parameterType_port_displayName() {
        #expect(ParameterType.port.displayName == "Port")
    }

    @Test("ParameterType.host displayName is 'Hostname'")
    func test_parameterType_host_displayName() {
        #expect(ParameterType.host.displayName == "Hostname")
    }

    @Test("ParameterType.date displayName is 'Date'")
    func test_parameterType_date_displayName() {
        #expect(ParameterType.date.displayName == "Date")
    }

    @Test("ParameterType.multiText displayName is 'Multi-line Text'")
    func test_parameterType_multiText_displayName() {
        #expect(ParameterType.multiText.displayName == "Multi-line Text")
    }

    // MARK: - ParameterValue

    @Test("ParameterValue.string stringRepresentation returns the string")
    func test_parameterValue_string_stringRepresentation() {
        #expect(ParameterValue.string("hello").stringRepresentation == "hello")
    }

    @Test("ParameterValue.int stringRepresentation returns decimal string")
    func test_parameterValue_int_stringRepresentation() {
        #expect(ParameterValue.int(42).stringRepresentation == "42")
    }

    @Test("ParameterValue.double stringRepresentation is non-empty")
    func test_parameterValue_double_stringRepresentation() {
        #expect(!ParameterValue.double(3.14).stringRepresentation.isEmpty)
    }

    @Test("ParameterValue.bool true stringRepresentation is 'true'")
    func test_parameterValue_boolTrue_stringRepresentation() {
        #expect(ParameterValue.bool(true).stringRepresentation == "true")
    }

    @Test("ParameterValue.bool false stringRepresentation is 'false'")
    func test_parameterValue_boolFalse_stringRepresentation() {
        #expect(ParameterValue.bool(false).stringRepresentation == "false")
    }

    @Test("ParameterValue.filePath stringRepresentation returns the path string")
    func test_parameterValue_filePath_stringRepresentation() {
        #expect(ParameterValue.filePath("/tmp/file.dcm").stringRepresentation == "/tmp/file.dcm")
    }

    @Test("ParameterValue.directoryPath stringRepresentation returns the path string")
    func test_parameterValue_directoryPath_stringRepresentation() {
        #expect(ParameterValue.directoryPath("/tmp/out").stringRepresentation == "/tmp/out")
    }

    @Test("ParameterValue.date stringRepresentation has yyyy-MM-dd format")
    func test_parameterValue_date_stringRepresentationHasCorrectFormat() {
        var components = DateComponents()
        components.year = 2024; components.month = 6; components.day = 15
        let date = Calendar.current.date(from: components)!
        let str = ParameterValue.date(date).stringRepresentation
        #expect(str == "2024-06-15")
    }

    // MARK: - ToolParameterDefinition

    @Test("ToolParameterDefinition id equals the name field")
    func test_toolParameterDefinition_id_equalsName() {
        let defn = ToolParameterDefinition(
            name: "--output",
            displayName: "Output",
            description: "Output path",
            type: .outputPath(defaultExtension: "dcm"),
            isRequired: false
        )
        #expect(defn.id == "--output")
    }

    @Test("ToolParameterDefinition default values are nil and empty when not provided")
    func test_toolParameterDefinition_defaults_nilAndEmpty() {
        let defn = ToolParameterDefinition(
            name: "--flag",
            displayName: "Flag",
            description: "A flag",
            type: .toggle,
            isRequired: false
        )
        #expect(defn.defaultValue == nil)
        #expect(defn.validations.isEmpty)
        #expect(defn.dependsOn == nil)
        #expect(defn.group == nil)
    }

    // MARK: - ToolParameterConfig

    @Test("ToolParameterConfig hasSubcommands is false when subcommands are empty")
    func test_toolParameterConfig_hasSubcommands_falseWhenEmpty() {
        let cfg = ToolParameterConfig(toolName: "dicom-info", parameters: [], subcommands: [])
        #expect(cfg.hasSubcommands == false)
    }

    @Test("ToolParameterConfig hasSubcommands is true when subcommands are non-empty")
    func test_toolParameterConfig_hasSubcommands_trueWhenNonEmpty() {
        let sub = ToolSubcommand(name: "compress", displayName: "Compress", description: "", parameters: [])
        let cfg = ToolParameterConfig(toolName: "dicom-compress", parameters: [], subcommands: [sub])
        #expect(cfg.hasSubcommands == true)
    }

    @Test("ToolParameterConfig parameterGroups returns unique ordered group labels")
    func test_toolParameterConfig_parameterGroups_uniqueOrdered() {
        let params: [ToolParameterDefinition] = [
            ToolParameterDefinition(name: "--a", displayName: "A", description: "", type: .toggle, isRequired: false, group: "Alpha"),
            ToolParameterDefinition(name: "--b", displayName: "B", description: "", type: .toggle, isRequired: false, group: "Beta"),
            ToolParameterDefinition(name: "--c", displayName: "C", description: "", type: .toggle, isRequired: false, group: "Alpha"),
        ]
        let cfg = ToolParameterConfig(toolName: "tool", parameters: params, subcommands: [])
        #expect(cfg.parameterGroups == ["Alpha", "Beta"])
    }

    @Test("ToolParameterConfig id equals toolName")
    func test_toolParameterConfig_id_equalsToolName() {
        let cfg = ToolParameterConfig(toolName: "dicom-echo", parameters: [], subcommands: [])
        #expect(cfg.id == "dicom-echo")
    }

    // MARK: - ParameterFormMode

    @Test("ParameterFormMode has exactly 2 cases")
    func test_parameterFormMode_allCases_has2Cases() {
        #expect(ParameterFormMode.allCases.count == 2)
    }

    @Test("ParameterFormMode all cases have non-empty displayNames")
    func test_parameterFormMode_allCases_nonEmptyDisplayNames() {
        for mode in ParameterFormMode.allCases {
            #expect(!mode.displayName.isEmpty)
        }
    }

    // MARK: - FormParameterSource

    @Test("FormParameterSource all cases have non-empty displayNames")
    func test_formParameterSource_allCases_nonEmptyDisplayNames() {
        for src in FormParameterSource.allCases {
            #expect(!src.displayName.isEmpty)
        }
    }

    @Test("FormParameterSource all cases have non-empty sfSymbols")
    func test_formParameterSource_allCases_nonEmptySfSymbols() {
        for src in FormParameterSource.allCases {
            #expect(!src.sfSymbol.isEmpty)
        }
    }

    // MARK: - ParameterFormEntry

    @Test("ParameterFormEntry isVisible returns true when dependsOn is nil")
    func test_parameterFormEntry_isVisible_trueWhenNoDependency() {
        let defn = ToolParameterDefinition(
            name: "--verbose", displayName: "Verbose", description: "", type: .toggle, isRequired: false
        )
        let entry = ParameterFormEntry(definition: defn)
        #expect(entry.isVisible(currentValues: [:]) == true)
    }

    @Test("ParameterFormEntry isVisible returns false when dependsOn param has no value")
    func test_parameterFormEntry_isVisible_falseWhenDependencyMissing() {
        let defn = ToolParameterDefinition(
            name: "--quality", displayName: "Quality", description: "", type: .slider(min: 0, max: 100, step: 1),
            isRequired: false, dependsOn: "--codec"
        )
        let entry = ParameterFormEntry(definition: defn)
        #expect(entry.isVisible(currentValues: [:]) == false)
    }

    @Test("ParameterFormEntry isVisible returns true when dependsOn param has a value")
    func test_parameterFormEntry_isVisible_trueWhenDependencyPresent() {
        let defn = ToolParameterDefinition(
            name: "--quality", displayName: "Quality", description: "", type: .slider(min: 0, max: 100, step: 1),
            isRequired: false, dependsOn: "--codec"
        )
        let entry = ParameterFormEntry(definition: defn)
        let values: [String: ParameterValue] = ["--codec": .string("jpeg")]
        #expect(entry.isVisible(currentValues: values) == true)
    }

    // MARK: - ParameterFormState

    @Test("ParameterFormState requiredMissingEntries returns entries missing required values")
    func test_parameterFormState_requiredMissingEntries_returnsMissing() {
        let defn = ToolParameterDefinition(
            name: "--input", displayName: "Input", description: "", type: .filePath(allowedExtensions: ["dcm"]), isRequired: true
        )
        let entry = ParameterFormEntry(definition: defn, currentValue: nil, source: .userSet)
        let state = ParameterFormState(toolName: "dicom-info", entries: [entry])
        #expect(state.requiredMissingEntries.count == 1)
    }

    @Test("ParameterFormState requiredMissingEntries is empty when required field has a value")
    func test_parameterFormState_requiredMissingEntries_emptyWhenValueSet() {
        let defn = ToolParameterDefinition(
            name: "--input", displayName: "Input", description: "", type: .filePath(allowedExtensions: ["dcm"]), isRequired: true
        )
        let entry = ParameterFormEntry(definition: defn, currentValue: .filePath("/tmp/f.dcm"), source: .userSet)
        let state = ParameterFormState(toolName: "dicom-info", entries: [entry])
        #expect(state.requiredMissingEntries.isEmpty)
    }

    // MARK: - NetworkInjectionState

    @Test("NetworkInjectionState defaults: isServerConfigured false, injectedParams empty")
    func test_networkInjectionState_defaults() {
        let state = NetworkInjectionState()
        #expect(state.isServerConfigured == false)
        #expect(state.injectedParams.isEmpty)
        #expect(state.activeServerName == nil)
    }

    // MARK: - SubcommandState

    @Test("SubcommandState initialises with given subcommands")
    func test_subcommandState_init_storesSubcommands() {
        let sub = ToolSubcommand(name: "compress", displayName: "Compress", description: "desc", parameters: [])
        let state = SubcommandState(toolName: "dicom-compress", subcommands: [sub])
        #expect(state.subcommands.count == 1)
        #expect(state.subcommands[0].name == "compress")
    }

    // MARK: - ParameterBuilderState

    @Test("ParameterBuilderState initialises with nil subcommandState by default")
    func test_parameterBuilderState_init_nilSubcommandState() {
        let form = ParameterFormState(toolName: "dicom-info")
        let net  = NetworkInjectionState()
        let state = ParameterBuilderState(formState: form, networkInjection: net)
        #expect(state.subcommandState == nil)
    }
}

// MARK: - Helpers Tests

@Suite("Parameter Builder Helpers Tests")
struct ParameterBuilderHelpersTests {

    // MARK: - ParameterValidationHelpers.validate

    @Test("validate: .required fails when value is empty string")
    func test_validate_required_failsForEmptyString() {
        let error = ParameterValidationHelpers.validate(
            value: .string(""),
            against: [.required]
        )
        #expect(error != nil)
    }

    @Test("validate: .required passes when value is non-empty string")
    func test_validate_required_passesForNonEmptyString() {
        let error = ParameterValidationHelpers.validate(
            value: .string("hello"),
            against: [.required]
        )
        #expect(error == nil)
    }

    @Test("validate: .maxLength fails when string exceeds length")
    func test_validate_maxLength_failsWhenExceeded() {
        let error = ParameterValidationHelpers.validate(
            value: .string("TOOLONGAETITLE!!!"),   // 17 characters - exceeds maxLength(16)
            against: [.maxLength(16)]
        )
        #expect(error != nil)
    }

    @Test("validate: .maxLength passes when string is within length")
    func test_validate_maxLength_passesWhenWithin() {
        let error = ParameterValidationHelpers.validate(
            value: .string("MYAE"),
            against: [.maxLength(16)]
        )
        #expect(error == nil)
    }

    @Test("validate: .range fails for int below minimum")
    func test_validate_range_failsForIntBelowMin() {
        let error = ParameterValidationHelpers.validate(
            value: .int(0),
            against: [.range(min: 1, max: 65535)]
        )
        #expect(error != nil)
    }

    @Test("validate: .range passes for int within bounds")
    func test_validate_range_passesForIntWithinBounds() {
        let error = ParameterValidationHelpers.validate(
            value: .int(11112),
            against: [.range(min: 1, max: 65535)]
        )
        #expect(error == nil)
    }

    @Test("validate: .range fails for double above maximum")
    func test_validate_range_failsForDoubleAboveMax() {
        let error = ParameterValidationHelpers.validate(
            value: .double(101.0),
            against: [.range(min: 0, max: 100)]
        )
        #expect(error != nil)
    }

    @Test("validate: .regex passes for matching value")
    func test_validate_regex_passesForMatchingValue() {
        let error = ParameterValidationHelpers.validate(
            value: .string("ABC123"),
            against: [.regex("^[A-Z0-9]+$")]
        )
        #expect(error == nil)
    }

    @Test("validate: .regex fails for non-matching value")
    func test_validate_regex_failsForNonMatchingValue() {
        let error = ParameterValidationHelpers.validate(
            value: .string("abc!"),
            against: [.regex("^[A-Z0-9]+$")]
        )
        #expect(error != nil)
    }

    // MARK: - ParameterValidationHelpers.validateAETitle

    @Test("validateAETitle: empty string returns error")
    func test_validateAETitle_empty_returnsError() {
        #expect(ParameterValidationHelpers.validateAETitle("") != nil)
    }

    @Test("validateAETitle: 17-char title returns error")
    func test_validateAETitle_tooLong_returnsError() {
        #expect(ParameterValidationHelpers.validateAETitle("AAAAAAAAAAAAAAAAA") != nil) // 17 chars
    }

    @Test("validateAETitle: 16-char title returns nil")
    func test_validateAETitle_16Chars_returnsNil() {
        #expect(ParameterValidationHelpers.validateAETitle("MYSCU           ") == nil)
    }

    @Test("validateAETitle: typical AE title 'ORTHANC' returns nil")
    func test_validateAETitle_orthanc_returnsNil() {
        #expect(ParameterValidationHelpers.validateAETitle("ORTHANC") == nil)
    }

    // MARK: - ParameterValidationHelpers.validatePort

    @Test("validatePort: 0 returns error")
    func test_validatePort_zero_returnsError() {
        #expect(ParameterValidationHelpers.validatePort(0) != nil)
    }

    @Test("validatePort: 65536 returns error")
    func test_validatePort_tooHigh_returnsError() {
        #expect(ParameterValidationHelpers.validatePort(65536) != nil)
    }

    @Test("validatePort: 11112 returns nil")
    func test_validatePort_valid_returnsNil() {
        #expect(ParameterValidationHelpers.validatePort(11112) == nil)
    }

    @Test("validatePort: 1 returns nil")
    func test_validatePort_minBound_returnsNil() {
        #expect(ParameterValidationHelpers.validatePort(1) == nil)
    }

    @Test("validatePort: 65535 returns nil")
    func test_validatePort_maxBound_returnsNil() {
        #expect(ParameterValidationHelpers.validatePort(65535) == nil)
    }

    // MARK: - ParameterValidationHelpers.validateHost

    @Test("validateHost: empty string returns error")
    func test_validateHost_empty_returnsError() {
        #expect(ParameterValidationHelpers.validateHost("") != nil)
    }

    @Test("validateHost: whitespace-only string returns error")
    func test_validateHost_whitespace_returnsError() {
        #expect(ParameterValidationHelpers.validateHost("   ") != nil)
    }

    @Test("validateHost: valid hostname returns nil")
    func test_validateHost_valid_returnsNil() {
        #expect(ParameterValidationHelpers.validateHost("pacs.hospital.org") == nil)
    }

    // MARK: - ParameterCatalogHelpers

    @Test("allToolNames contains 'dicom-info'")
    func test_allToolNames_containsDicomInfo() {
        #expect(ParameterCatalogHelpers.allToolNames.contains("dicom-info"))
    }

    @Test("allToolNames contains 'dicom-compress'")
    func test_allToolNames_containsDicomCompress() {
        #expect(ParameterCatalogHelpers.allToolNames.contains("dicom-compress"))
    }

    @Test("config(for:) returns non-nil for 'dicom-info'")
    func test_config_forDicomInfo_returnsNonNil() {
        #expect(ParameterCatalogHelpers.config(for: "dicom-info") != nil)
    }

    @Test("config(for:) returns nil for unknown tool")
    func test_config_forUnknownTool_returnsNil() {
        #expect(ParameterCatalogHelpers.config(for: "dicom-nonexistent") == nil)
    }

    @Test("allToolConfigs returns 12 configurations")
    func test_allToolConfigs_returns12Configs() {
        #expect(ParameterCatalogHelpers.allToolConfigs().count == 12)
    }

    @Test("dicom-compress config has 3 subcommands")
    func test_dicomCompress_config_has3Subcommands() {
        let cfg = ParameterCatalogHelpers.config(for: "dicom-compress")
        #expect(cfg?.subcommands.count == 3)
    }

    @Test("dicom-uid config has 3 subcommands")
    func test_dicomUID_config_has3Subcommands() {
        let cfg = ParameterCatalogHelpers.config(for: "dicom-uid")
        #expect(cfg?.subcommands.count == 3)
    }

    @Test("dicom-info config has no subcommands")
    func test_dicomInfo_config_hasNoSubcommands() {
        let cfg = ParameterCatalogHelpers.config(for: "dicom-info")
        #expect(cfg?.hasSubcommands == false)
    }

    @Test("dicom-info config has at least one required parameter (<file-path>)")
    func test_dicomInfo_config_hasRequiredInputParam() {
        let cfg = ParameterCatalogHelpers.config(for: "dicom-info")!
        let inputParam = cfg.parameters.first { $0.name == "<file-path>" }
        #expect(inputParam != nil)
        #expect(inputParam?.isRequired == true)
    }

    // MARK: - FormRenderingHelpers.generateCommand

    @Test("generateCommand: tool name alone produces just the tool name")
    func test_generateCommand_noEntries_returnsToolName() {
        let cmd = FormRenderingHelpers.generateCommand(toolName: "dicom-echo", subcommand: nil, entries: [])
        #expect(cmd == "dicom-echo")
    }

    @Test("generateCommand: includes subcommand when provided")
    func test_generateCommand_withSubcommand_includesSubcommand() {
        let cmd = FormRenderingHelpers.generateCommand(toolName: "dicom-compress", subcommand: "compress", entries: [])
        #expect(cmd == "dicom-compress compress")
    }

    @Test("generateCommand: appends flag and value for string entry")
    func test_generateCommand_stringEntry_appendsFlagAndValue() {
        let defn = ToolParameterDefinition(name: "--host", displayName: "Host", description: "", type: .host, isRequired: true)
        let entry = ParameterFormEntry(definition: defn, currentValue: .string("10.0.0.1"), source: .userSet)
        let cmd = FormRenderingHelpers.generateCommand(toolName: "dicom-echo", subcommand: nil, entries: [entry])
        #expect(cmd == "dicom-echo --host 10.0.0.1")
    }

    @Test("generateCommand: toggle true appends only the flag")
    func test_generateCommand_toggleTrue_appendsOnlyFlag() {
        let defn = ToolParameterDefinition(name: "--verbose", displayName: "Verbose", description: "", type: .toggle, isRequired: false)
        let entry = ParameterFormEntry(definition: defn, currentValue: .bool(true), source: .userSet)
        let cmd = FormRenderingHelpers.generateCommand(toolName: "dicom-info", subcommand: nil, entries: [entry])
        #expect(cmd == "dicom-info --verbose")
    }

    @Test("generateCommand: toggle false omits the flag")
    func test_generateCommand_toggleFalse_omitsFlag() {
        let defn = ToolParameterDefinition(name: "--verbose", displayName: "Verbose", description: "", type: .toggle, isRequired: false)
        let entry = ParameterFormEntry(definition: defn, currentValue: .bool(false), source: .userSet)
        let cmd = FormRenderingHelpers.generateCommand(toolName: "dicom-info", subcommand: nil, entries: [entry])
        #expect(cmd == "dicom-info")
    }

    @Test("generateCommand: path with spaces is quoted")
    func test_generateCommand_pathWithSpaces_isQuoted() {
        let defn = ToolParameterDefinition(name: "--input", displayName: "Input", description: "", type: .filePath(allowedExtensions: ["dcm"]), isRequired: true)
        let entry = ParameterFormEntry(definition: defn, currentValue: .filePath("/path with spaces/file.dcm"), source: .userSet)
        let cmd = FormRenderingHelpers.generateCommand(toolName: "dicom-info", subcommand: nil, entries: [entry])
        #expect(cmd.contains("\"/path with spaces/file.dcm\""))
    }

    @Test("generateCommand: nil value entry is omitted")
    func test_generateCommand_nilValue_omitsEntry() {
        let defn = ToolParameterDefinition(name: "--output", displayName: "Output", description: "", type: .outputPath(defaultExtension: "dcm"), isRequired: false)
        let entry = ParameterFormEntry(definition: defn, currentValue: nil, source: .userSet)
        let cmd = FormRenderingHelpers.generateCommand(toolName: "dicom-info", subcommand: nil, entries: [entry])
        #expect(cmd == "dicom-info")
    }

    // MARK: - FormRenderingHelpers.resetToDefaults

    @Test("resetToDefaults: entries without defaults become nil")
    func test_resetToDefaults_noDefault_becomesNil() {
        let defn = ToolParameterDefinition(name: "--host", displayName: "Host", description: "", type: .host, isRequired: true)
        let entry = ParameterFormEntry(definition: defn, currentValue: .string("pacs.example.com"), source: .userSet)
        let reset = FormRenderingHelpers.resetToDefaults(entries: [entry])
        #expect(reset[0].currentValue == nil)
        #expect(reset[0].source == .defaultValue)
    }

    @Test("resetToDefaults: entries with defaults revert to default value")
    func test_resetToDefaults_withDefault_revertsToDefault() {
        let defn = ToolParameterDefinition(name: "--port", displayName: "Port", description: "", type: .port, isRequired: false, defaultValue: .int(11112))
        let entry = ParameterFormEntry(definition: defn, currentValue: .int(104), source: .userSet)
        let reset = FormRenderingHelpers.resetToDefaults(entries: [entry])
        #expect(reset[0].currentValue == .int(11112))
        #expect(reset[0].source == .defaultValue)
    }

    @Test("resetToDefaults: clears validation errors")
    func test_resetToDefaults_clearsValidationErrors() {
        let defn = ToolParameterDefinition(name: "--port", displayName: "Port", description: "", type: .port, isRequired: true)
        var entry = ParameterFormEntry(definition: defn, currentValue: .int(0), source: .userSet)
        entry.validationError = "Must be between 1 and 65535."
        let reset = FormRenderingHelpers.resetToDefaults(entries: [entry])
        #expect(reset[0].validationError == nil)
    }

    // MARK: - FormRenderingHelpers.applyNetworkInjection

    @Test("applyNetworkInjection: returns entries unchanged when server not configured")
    func test_applyNetworkInjection_notConfigured_returnsUnchanged() {
        let defn = ToolParameterDefinition(name: "--host", displayName: "Host", description: "", type: .host, isRequired: true)
        let entry = ParameterFormEntry(definition: defn, currentValue: .string("old"), source: .userSet)
        let injection = NetworkInjectionState(isServerConfigured: false)
        let result = FormRenderingHelpers.applyNetworkInjection(to: [entry], injection: injection)
        #expect(result[0].currentValue == .string("old"))
        #expect(result[0].source == .userSet)
    }

    @Test("applyNetworkInjection: injects matching parameter when server is configured")
    func test_applyNetworkInjection_configured_injectsMatchingParam() {
        let defn = ToolParameterDefinition(name: "<host>", displayName: "Host", description: "", type: .host, isRequired: true)
        let entry = ParameterFormEntry(definition: defn, currentValue: nil, source: .userSet)
        let injected = InjectedNetworkParam(
            parameterName: "<host>",
            cliFlag: "<host>",
            value: .string("pacs.hospital.org"),
            serverProfileName: "Main PACS"
        )
        let injection = NetworkInjectionState(
            injectedParams: [injected],
            isServerConfigured: true,
            activeServerName: "Main PACS"
        )
        let result = FormRenderingHelpers.applyNetworkInjection(to: [entry], injection: injection)
        #expect(result[0].currentValue == .string("pacs.hospital.org"))
        #expect(result[0].source == .serverInjected)
    }

    // MARK: - FormRenderingHelpers.isVisible

    @Test("isVisible: entry with no dependsOn is always visible")
    func test_isVisible_noDependency_isVisible() {
        let defn = ToolParameterDefinition(name: "--verbose", displayName: "Verbose", description: "", type: .toggle, isRequired: false)
        let entry = ParameterFormEntry(definition: defn)
        #expect(FormRenderingHelpers.isVisible(entry: entry, currentValues: [:]) == true)
    }

    @Test("isVisible: entry with dependsOn is hidden when dependency has no value")
    func test_isVisible_withDependency_hiddenWhenMissing() {
        let defn = ToolParameterDefinition(name: "--quality", displayName: "Quality", description: "", type: .slider(min: 0, max: 100, step: 1), isRequired: false, dependsOn: "--codec")
        let entry = ParameterFormEntry(definition: defn)
        #expect(FormRenderingHelpers.isVisible(entry: entry, currentValues: [:]) == false)
    }

    @Test("isVisible: entry with dependsOn is shown when dependency has a value")
    func test_isVisible_withDependency_shownWhenPresent() {
        let defn = ToolParameterDefinition(name: "--quality", displayName: "Quality", description: "", type: .slider(min: 0, max: 100, step: 1), isRequired: false, dependsOn: "--codec")
        let entry = ParameterFormEntry(definition: defn)
        #expect(FormRenderingHelpers.isVisible(entry: entry, currentValues: ["--codec": .string("jpeg")]) == true)
    }

    // MARK: - SubcommandHelpers

    @Test("subcommandNames: returns empty array for tool without subcommands")
    func test_subcommandNames_noSubcommands_returnsEmpty() {
        let cfg = ToolParameterConfig(toolName: "dicom-info", parameters: [], subcommands: [])
        #expect(SubcommandHelpers.subcommandNames(for: cfg).isEmpty)
    }

    @Test("subcommandNames: returns subcommand tokens in order")
    func test_subcommandNames_withSubcommands_returnsTokens() {
        let subs = [
            ToolSubcommand(name: "compress", displayName: "Compress", description: "", parameters: []),
            ToolSubcommand(name: "decompress", displayName: "Decompress", description: "", parameters: [])
        ]
        let cfg = ToolParameterConfig(toolName: "dicom-compress", parameters: [], subcommands: subs)
        #expect(SubcommandHelpers.subcommandNames(for: cfg) == ["compress", "decompress"])
    }

    @Test("activeParameters: returns top-level params when tool has no subcommands")
    func test_activeParameters_noSubcommands_returnsTopLevel() {
        let params = [
            ToolParameterDefinition(name: "--input", displayName: "Input", description: "", type: .filePath(allowedExtensions: ["dcm"]), isRequired: true)
        ]
        let cfg = ToolParameterConfig(toolName: "dicom-info", parameters: params, subcommands: [])
        let active = SubcommandHelpers.activeParameters(for: cfg, subcommand: nil)
        #expect(active.count == 1)
        #expect(active[0].name == "--input")
    }

    @Test("activeParameters: returns subcommand params when subcommand is selected")
    func test_activeParameters_withSubcommand_returnsSubcommandParams() {
        let subParams = [
            ToolParameterDefinition(name: "--codec", displayName: "Codec", description: "", type: .picker(options: []), isRequired: false)
        ]
        let sub = ToolSubcommand(name: "compress", displayName: "Compress", description: "", parameters: subParams)
        let cfg = ToolParameterConfig(toolName: "dicom-compress", parameters: [], subcommands: [sub])
        let active = SubcommandHelpers.activeParameters(for: cfg, subcommand: "compress")
        #expect(active.count == 1)
        #expect(active[0].name == "--codec")
    }
}

// MARK: - Service Tests

@Suite("Parameter Builder Service Tests")
struct ParameterBuilderServiceTests {

    // MARK: - Initialization

    @Test("Service initialises with empty form state")
    func test_init_formState_isEmpty() {
        let service = ParameterBuilderService()
        #expect(service.getFormState().toolName == "")
        #expect(service.getFormState().entries.isEmpty)
    }

    @Test("Service initialises with unconfigured network injection")
    func test_init_networkInjection_notConfigured() {
        let service = ParameterBuilderService()
        #expect(service.getNetworkInjection().isServerConfigured == false)
    }

    @Test("Service initialises with nil subcommand state")
    func test_init_subcommandState_isNil() {
        let service = ParameterBuilderService()
        #expect(service.getSubcommandState() == nil)
    }

    // MARK: - 21.2 Tool Loading

    @Test("loadTool('dicom-info') sets formState.toolName to 'dicom-info'")
    func test_loadTool_dicomInfo_setsToolName() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-info")
        #expect(service.getFormState().toolName == "dicom-info")
    }

    @Test("loadTool('dicom-info') populates form entries from catalog")
    func test_loadTool_dicomInfo_populatesEntries() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-info")
        #expect(!service.getFormState().entries.isEmpty)
    }

    @Test("loadTool('dicom-info') generates a command string starting with 'dicom-info'")
    func test_loadTool_dicomInfo_generatesCommandWithToolName() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-info")
        #expect(service.getFormState().generatedCommand.hasPrefix("dicom-info"))
    }

    @Test("loadTool with unknown tool name does not change formState")
    func test_loadTool_unknownTool_noChange() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-nonexistent")
        #expect(service.getFormState().toolName == "")
    }

    @Test("loadTool('dicom-compress') creates subcommand state with 3 subcommands")
    func test_loadTool_dicomCompress_createsSubcommandState() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-compress")
        let subcmdState = service.getSubcommandState()
        #expect(subcmdState != nil)
        #expect(subcmdState?.subcommands.count == 3)
    }

    @Test("loadTool('dicom-info') sets subcommand state to nil")
    func test_loadTool_dicomInfo_nilSubcommandState() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-info")
        #expect(service.getSubcommandState() == nil)
    }

    // MARK: - 21.3 Form State Updates

    @Test("updateValue sets the value for the named parameter")
    func test_updateValue_setsValue() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-echo")
        service.updateValue(.string("pacs.local"), for: "<host>")
        let entry = service.getFormState().entries.first { $0.definition.name == "<host>" }
        #expect(entry?.currentValue == .string("pacs.local"))
    }

    @Test("updateValue marks the entry source as .userSet")
    func test_updateValue_setsSourceToUserSet() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-echo")
        service.updateValue(.string("pacs.local"), for: "<host>")
        let entry = service.getFormState().entries.first { $0.definition.name == "<host>" }
        #expect(entry?.source == .userSet)
    }

    @Test("updateValue regenerates the command string")
    func test_updateValue_regeneratesCommand() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-echo")
        service.updateValue(.string("pacs.local"), for: "<host>")
        #expect(service.getFormState().generatedCommand.contains("pacs.local"))
    }

    @Test("resetToDefaults reverts user-set values to defaults")
    func test_resetToDefaults_revertsValues() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-echo")
        service.updateValue(.string("pacs.local"), for: "<host>")
        service.resetToDefaults()
        let entry = service.getFormState().entries.first { $0.definition.name == "<host>" }
        // <host> has no default, so value should be nil after reset
        #expect(entry?.currentValue == nil)
    }

    @Test("resetToDefaults sets isResettingToDefaults back to false after completion")
    func test_resetToDefaults_isResettingToDefaults_falseAfterCompletion() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-echo")
        service.resetToDefaults()
        #expect(service.getFormState().isResettingToDefaults == false)
    }

    // MARK: - 21.4 Network Injection

    @Test("setNetworkInjection: switches form mode to .withServerInjection")
    func test_setNetworkInjection_switchesToServerInjectionMode() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-echo")
        let injection = NetworkInjectionState(isServerConfigured: true, activeServerName: "Main")
        service.setNetworkInjection(injection)
        #expect(service.getFormState().mode == .withServerInjection)
    }

    @Test("clearNetworkInjection: switches form mode to .standalone")
    func test_clearNetworkInjection_switchesToStandaloneMode() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-echo")
        let injection = NetworkInjectionState(isServerConfigured: true, activeServerName: "Main")
        service.setNetworkInjection(injection)
        service.clearNetworkInjection()
        #expect(service.getFormState().mode == .standalone)
    }

    @Test("setNetworkInjection: applies injected values to matching entries")
    func test_setNetworkInjection_appliesInjectedValues() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-echo")
        let injectedParam = InjectedNetworkParam(
            parameterName: "<host>",
            cliFlag: "--host",
            value: .string("injected-host"),
            serverProfileName: "Test"
        )
        let injection = NetworkInjectionState(
            injectedParams: [injectedParam],
            isServerConfigured: true,
            activeServerName: "Test"
        )
        service.setNetworkInjection(injection)
        let entry = service.getFormState().entries.first { $0.definition.name == "<host>" }
        #expect(entry?.currentValue == .string("injected-host"))
        #expect(entry?.source == .serverInjected)
    }

    @Test("clearNetworkInjection: reverts injected entries to default source")
    func test_clearNetworkInjection_revertsInjectedEntries() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-echo")
        let injectedParam = InjectedNetworkParam(
            parameterName: "<host>",
            cliFlag: "--host",
            value: .string("injected-host"),
            serverProfileName: "Test"
        )
        let injection = NetworkInjectionState(
            injectedParams: [injectedParam],
            isServerConfigured: true
        )
        service.setNetworkInjection(injection)
        service.clearNetworkInjection()
        let entry = service.getFormState().entries.first { $0.definition.name == "<host>" }
        #expect(entry?.source != .serverInjected)
    }

    // MARK: - 21.5 Subcommand Handling

    @Test("selectSubcommand: switches active parameters to subcommand parameters")
    func test_selectSubcommand_switchesParameters() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-compress")
        service.selectSubcommand("decompress")
        let state = service.getSubcommandState()
        #expect(state?.selectedSubcommand == "decompress")
    }

    @Test("selectSubcommand: regenerates command with new subcommand token")
    func test_selectSubcommand_regeneratesCommand() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-compress")
        service.selectSubcommand("decompress")
        let cmd = service.getFormState().generatedCommand
        #expect(cmd.hasPrefix("dicom-compress decompress"))
    }

    @Test("selectSubcommand: updates formState.selectedSubcommand")
    func test_selectSubcommand_updatesFormStateSelectedSubcommand() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-compress")
        service.selectSubcommand("info")
        #expect(service.getFormState().selectedSubcommand == "info")
    }

    @Test("selectSubcommand on tool without subcommands has no effect")
    func test_selectSubcommand_noSubcommands_noEffect() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-info")
        service.selectSubcommand("nonexistent")
        #expect(service.getFormState().selectedSubcommand == nil)
    }

    // MARK: - Validation

    @Test("isValid is false when a required parameter has no value")
    func test_isValid_falseWhenRequiredParamMissing() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-info")
        // <file-path> is required and has no default; form is loaded with nil value
        #expect(service.getFormState().isValid == false)
    }

    @Test("isValid becomes true when required parameter is provided")
    func test_isValid_trueWhenRequiredParamProvided() {
        let service = ParameterBuilderService()
        service.loadTool("dicom-info")
        service.updateValue(.filePath("/tmp/sample.dcm"), for: "<file-path>")
        #expect(service.getFormState().isValid == true)
    }
}

// MARK: - ViewModel Tests

@Suite("Parameter Builder ViewModel Tests")
struct ParameterBuilderViewModelTests {

    // MARK: - Initialization

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel initialises with empty toolName")
    func test_init_formState_toolNameEmpty() {
        let vm = ParameterBuilderViewModel()
        #expect(vm.formState.toolName == "")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel initialises with isValid false")
    func test_init_isValid_false() {
        let vm = ParameterBuilderViewModel()
        #expect(vm.isValid == false)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel initialises with empty generatedCommand")
    func test_init_generatedCommand_empty() {
        let vm = ParameterBuilderViewModel()
        #expect(vm.generatedCommand == "")
    }

    // MARK: - 21.2 Tool Loading

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("allToolConfigs returns 12 tool configurations")
    func test_allToolConfigs_returns12() {
        let vm = ParameterBuilderViewModel()
        #expect(vm.allToolConfigs().count == 12)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("loadTool('dicom-info') sets formState.toolName to 'dicom-info'")
    func test_loadTool_setsToolName() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-info")
        #expect(vm.formState.toolName == "dicom-info")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("loadTool('dicom-info') populates toolConfig")
    func test_loadTool_populatesToolConfig() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-info")
        #expect(vm.toolConfig != nil)
        #expect(vm.toolConfig?.toolName == "dicom-info")
    }

    // MARK: - 21.3 Form Renderer

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("updateValue reflects new value in formState entries")
    func test_updateValue_reflectsInFormState() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-echo")
        vm.updateValue(.string("myhost"), for: "<host>")
        let entry = vm.formState.entries.first { $0.definition.name == "<host>" }
        #expect(entry?.currentValue == .string("myhost"))
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("generatedCommand includes updated value after updateValue")
    func test_generatedCommand_includesUpdatedValue() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-echo")
        vm.updateValue(.string("myhost"), for: "<host>")
        #expect(vm.generatedCommand.contains("myhost"))
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("resetToDefaults clears user-set values")
    func test_resetToDefaults_clearsUserSetValues() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-echo")
        vm.updateValue(.string("myhost"), for: "<host>")
        vm.resetToDefaults()
        let entry = vm.formState.entries.first { $0.definition.name == "<host>" }
        #expect(entry?.currentValue == nil)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("visibleEntries is non-empty after loading dicom-info")
    func test_visibleEntries_nonEmptyAfterLoad() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-info")
        #expect(!vm.visibleEntries.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("entriesByGroup returns at least one group after loading dicom-info")
    func test_entriesByGroup_nonEmptyAfterLoad() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-info")
        #expect(!vm.entriesByGroup.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("isValid becomes true after required parameter is provided")
    func test_isValid_trueAfterRequiredParamSet() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-info")
        vm.updateValue(.filePath("/tmp/sample.dcm"), for: "<file-path>")
        #expect(vm.isValid == true)
    }

    // MARK: - 21.4 Network Injection

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("setNetworkInjection: switches form mode to .withServerInjection")
    func test_setNetworkInjection_switchesFormMode() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-echo")
        let injection = NetworkInjectionState(isServerConfigured: true, activeServerName: "Main")
        vm.setNetworkInjection(injection)
        #expect(vm.formState.mode == .withServerInjection)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("clearNetworkInjection: switches form mode to .standalone")
    func test_clearNetworkInjection_switchesFormMode() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-echo")
        let injection = NetworkInjectionState(isServerConfigured: true, activeServerName: "Main")
        vm.setNetworkInjection(injection)
        vm.clearNetworkInjection()
        #expect(vm.formState.mode == .standalone)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("networkInjection is reflected in ViewModel after setNetworkInjection")
    func test_networkInjection_reflectedAfterSet() {
        let vm = ParameterBuilderViewModel()
        let injection = NetworkInjectionState(isServerConfigured: true, activeServerName: "PACS")
        vm.setNetworkInjection(injection)
        #expect(vm.networkInjection.isServerConfigured == true)
        #expect(vm.networkInjection.activeServerName == "PACS")
    }

    // MARK: - 21.5 Subcommand Handling

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("subcommandNames returns 3 names after loading dicom-compress")
    func test_subcommandNames_dicomCompress_returns3() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-compress")
        #expect(vm.subcommandNames.count == 3)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("subcommandNames is empty after loading dicom-info")
    func test_subcommandNames_dicomInfo_isEmpty() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-info")
        #expect(vm.subcommandNames.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("selectSubcommand updates selectedSubcommand in ViewModel")
    func test_selectSubcommand_updatesSelectedSubcommand() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-compress")
        vm.selectSubcommand("decompress")
        #expect(vm.selectedSubcommand == "decompress")
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("selectSubcommand regenerates command with new subcommand")
    func test_selectSubcommand_regeneratesCommand() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-compress")
        vm.selectSubcommand("decompress")
        #expect(vm.generatedCommand.hasPrefix("dicom-compress decompress"))
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("subcommandState is nil after loading tool without subcommands")
    func test_subcommandState_nilForToolWithoutSubcommands() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-info")
        #expect(vm.subcommandState == nil)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("subcommandState is non-nil after loading dicom-compress")
    func test_subcommandState_nonNilForDicomCompress() {
        let vm = ParameterBuilderViewModel()
        vm.loadTool("dicom-compress")
        #expect(vm.subcommandState != nil)
    }
}
