// ParameterBuilderModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for Dynamic GUI Controls & Parameter Builder (Milestone 21)
// NEMA-verified: 2026a, checked 2026-10-05 — the only standard-derived values are the AE Title limit (16, PS3.5 2026a Table 6.2-1 VR AE "16 bytes maximum"; the old "uppercase" claim had no basis in the AE definition and is removed) and the port range 1–65535 with PS3.8 2026a 9.1.1 ports 104 / 11112 named; form, injection and subcommand state otherwise

import Foundation

// MARK: - 21.1 Parameter Definition Schema

/// A single selectable option for picker and radio parameter types.
public struct PickerOption: Sendable, Identifiable, Hashable, Codable {
    /// Unique identifier for this option.
    public let id: String

    /// Human-readable label shown in the UI.
    public var displayName: String

    /// Value passed to the CLI when this option is selected.
    public var cliValue: String

    /// Creates a new picker option.
    public init(id: String, displayName: String, cliValue: String) {
        self.id = id
        self.displayName = displayName
        self.cliValue = cliValue
    }
}

/// A validation rule that can be applied to a parameter value.
public enum ParameterValidation: Sendable, Equatable, Hashable {
    /// Value must match the given regular expression.
    case regex(String)
    /// Numeric value must fall within the given closed range.
    case range(min: Double, max: Double)
    /// String value must not exceed the given character count.
    case maxLength(Int)
    /// A value must be present (non-empty).
    case required
    /// A custom rule described by a human-readable string.
    case custom(description: String)

    /// Human-readable label describing this validation rule.
    public var displayName: String {
        switch self {
        case .regex(let pattern):         return "Must match pattern: \(pattern)"
        case .range(let min, let max):    return "Must be between \(min) and \(max)"
        case .maxLength(let length):      return "Maximum \(length) characters"
        case .required:                   return "Required"
        case .custom(let description):    return description
        }
    }
}

/// The UI control type and constraints for a CLI parameter.
public enum ParameterType: Sendable, Equatable, Hashable {
    /// Single-line text input with an optional placeholder.
    case text(placeholder: String)
    /// Integer spinner within a bounded range.
    case number(min: Int, max: Int, step: Int)
    /// Boolean on/off toggle.
    case toggle
    /// Drop-down list of predefined options.
    case picker(options: [PickerOption])
    /// Radio-button group of predefined options.
    case radio(options: [PickerOption])
    /// Continuous slider within a floating-point range.
    case slider(min: Double, max: Double, step: Double)
    /// File-open panel restricted to the given extensions.
    case filePath(allowedExtensions: [String])
    /// Directory-browse panel.
    case directoryPath
    /// Output path panel with a suggested file extension.
    case outputPath(defaultExtension: String)
    /// DICOM AE Title text field (PS3.5 Table 6.2-1, VR AE: 16 bytes maximum; not restricted to upper case).
    case aeTitle
    /// TCP port number field (1–65535; DICOM uses the well-known port 104 or the registered 11112, PS3.8 9.1.1).
    case port
    /// Hostname or IP address text field.
    case host
    /// Calendar date picker.
    case date
    /// Multi-line text area.
    case multiText

    /// Human-readable label for this control type.
    public var displayName: String {
        switch self {
        case .text:                   return "Text"
        case .number:                 return "Number"
        case .toggle:                 return "Toggle"
        case .picker:                 return "Picker"
        case .radio:                  return "Radio"
        case .slider:                 return "Slider"
        case .filePath:               return "File Path"
        case .directoryPath:          return "Directory Path"
        case .outputPath:             return "Output Path"
        case .aeTitle:                return "AE Title"
        case .port:                   return "Port"
        case .host:                   return "Hostname"
        case .date:                   return "Date"
        case .multiText:              return "Multi-line Text"
        }
    }
}

/// A typed value that a CLI parameter can hold.
public enum ParameterValue: Sendable, Equatable, Hashable {
    /// A string value.
    case string(String)
    /// An integer value.
    case int(Int)
    /// A double-precision floating-point value.
    case double(Double)
    /// A boolean flag value.
    case bool(Bool)
    /// A date value.
    case date(Date)
    /// An absolute path to a file.
    case filePath(String)
    /// An absolute path to a directory.
    case directoryPath(String)

    /// The CLI string representation of this value.
    public var stringRepresentation: String {
        switch self {
        case .string(let v):        return v
        case .int(let v):           return String(v)
        case .double(let v):        return String(v)
        case .bool(let v):          return v ? "true" : "false"
        case .date(let v):
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: v)
        case .filePath(let v):      return v
        case .directoryPath(let v): return v
        }
    }
}

/// The definition of a single CLI parameter, including its UI control type and validation rules.
public struct ToolParameterDefinition: Sendable, Identifiable, Hashable {
    /// CLI flag name used when constructing the command (e.g. `--output-format`).
    public let name: String

    /// Human-readable label displayed in the form.
    public var displayName: String

    /// Description of what this parameter controls.
    public var description: String

    /// UI control type and associated constraints.
    public var type: ParameterType

    /// Whether the parameter must be provided before the command can run.
    public var isRequired: Bool

    /// Pre-populated value used when no explicit value has been set.
    public var defaultValue: ParameterValue?

    /// Validation rules applied to the user-supplied value.
    public var validations: [ParameterValidation]

    /// Name of another parameter (`name` field) that must have a value for this one to appear.
    public var dependsOn: String?

    /// Optional grouping label used to organise related parameters in the form.
    public var group: String?

    /// `Identifiable` conformance — uses the CLI flag name.
    public var id: String { name }

    /// Creates a new parameter definition.
    public init(
        name: String,
        displayName: String,
        description: String,
        type: ParameterType,
        isRequired: Bool,
        defaultValue: ParameterValue? = nil,
        validations: [ParameterValidation] = [],
        dependsOn: String? = nil,
        group: String? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.type = type
        self.isRequired = isRequired
        self.defaultValue = defaultValue
        self.validations = validations
        self.dependsOn = dependsOn
        self.group = group
    }
}

// MARK: - 21.2 Tool Configuration

/// A named subcommand exposed by a CLI tool (e.g. `dicom-compress jpeg`).
public struct ToolSubcommand: Sendable, Identifiable, Hashable {
    /// Subcommand token as passed on the command line (e.g. `"compress"`).
    public let name: String

    /// Human-readable label for the subcommand.
    public var displayName: String

    /// Description of what this subcommand does.
    public var description: String

    /// Parameters accepted by this subcommand.
    public var parameters: [ToolParameterDefinition]

    /// `Identifiable` conformance — uses the subcommand token.
    public var id: String { name }

    /// Creates a new subcommand descriptor.
    public init(
        name: String,
        displayName: String,
        description: String,
        parameters: [ToolParameterDefinition]
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.parameters = parameters
    }
}

/// The complete parameter schema for a CLI tool, including top-level parameters and subcommands.
public struct ToolParameterConfig: Sendable, Identifiable, Hashable {
    /// Name of the CLI tool executable (e.g. `"dicom-compress"`).
    public let toolName: String

    /// Top-level parameters accepted by the tool regardless of subcommand.
    public var parameters: [ToolParameterDefinition]

    /// Subcommands provided by this tool.
    public var subcommands: [ToolSubcommand]

    /// `Identifiable` conformance — uses the tool name.
    public var id: String { toolName }

    /// Whether the tool uses subcommands.
    public var hasSubcommands: Bool { !subcommands.isEmpty }

    /// Ordered, deduplicated list of group labels from the top-level parameters.
    public var parameterGroups: [String] {
        var seen = Set<String>()
        return parameters.compactMap { $0.group }.filter { seen.insert($0).inserted }
    }

    /// Creates a new tool parameter configuration.
    public init(
        toolName: String,
        parameters: [ToolParameterDefinition],
        subcommands: [ToolSubcommand]
    ) {
        self.toolName = toolName
        self.parameters = parameters
        self.subcommands = subcommands
    }
}

// MARK: - 21.3 Dynamic Form State

/// The operational mode of the parameter builder form.
public enum ParameterFormMode: Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    /// Form operates with values entered entirely by the user.
    case standalone
    /// Form pre-fills network parameters from the active server profile.
    case withServerInjection

    /// `Identifiable` conformance — uses the display name.
    public var id: String { displayName }

    /// Human-readable label for this mode.
    public var displayName: String {
        switch self {
        case .standalone:          return "Standalone"
        case .withServerInjection: return "With Server Injection"
        }
    }
}

/// Describes how a parameter entry's current value was populated.
public enum FormParameterSource: Sendable, Equatable, Hashable, CaseIterable {
    /// The value was explicitly set by the user.
    case userSet
    /// The value was derived from the parameter's default.
    case defaultValue
    /// The value was injected from the active server profile.
    case serverInjected

    /// Human-readable label for this source.
    public var displayName: String {
        switch self {
        case .userSet:        return "User Set"
        case .defaultValue:   return "Default Value"
        case .serverInjected: return "Server Injected"
        }
    }

    /// SF Symbol name representing this source.
    public var sfSymbol: String {
        switch self {
        case .userSet:        return "person.fill"
        case .defaultValue:   return "gearshape"
        case .serverInjected: return "server.rack"
        }
    }
}

/// A single parameter entry in the dynamic form, combining its definition with runtime state.
public struct ParameterFormEntry: Sendable, Hashable {
    /// Static definition for this parameter.
    public var definition: ToolParameterDefinition

    /// The value currently held in the form field, or `nil` if unset.
    public var currentValue: ParameterValue?

    /// How `currentValue` was populated.
    public var source: FormParameterSource

    /// A localised validation error message, or `nil` when the value is valid.
    public var validationError: String?

    /// Creates a new form entry.
    public init(
        definition: ToolParameterDefinition,
        currentValue: ParameterValue? = nil,
        source: FormParameterSource = .defaultValue,
        validationError: String? = nil
    ) {
        self.definition = definition
        self.currentValue = currentValue
        self.source = source
        self.validationError = validationError
    }

    /// Whether this entry should be visible given the current set of form values.
    ///
    /// The entry is visible when it has no dependency, or when the parameter it
    /// depends on already has a non-`nil` value in `currentValues`.
    public func isVisible(currentValues: [String: ParameterValue]) -> Bool {
        guard let dependsOn = definition.dependsOn else { return true }
        return currentValues[dependsOn] != nil
    }
}

/// The complete runtime state of the parameter builder form for a single tool invocation.
public struct ParameterFormState: Sendable, Hashable {
    /// Name of the CLI tool whose parameters are being built.
    public var toolName: String

    /// Currently selected subcommand token, or `nil` for top-level usage.
    public var selectedSubcommand: String?

    /// All parameter entries for the current tool / subcommand combination.
    public var entries: [ParameterFormEntry]

    /// Current form operating mode.
    public var mode: ParameterFormMode

    /// Whether every required parameter has a valid value.
    public var isValid: Bool

    /// The CLI command string derived from the current form values.
    public var generatedCommand: String

    /// Timestamp of the most recent command regeneration.
    public var lastCommandUpdate: Date

    /// Whether the form is currently reverting all entries to their defaults.
    public var isResettingToDefaults: Bool

    /// Entries for required parameters that have no current value and no default.
    public var requiredMissingEntries: [ParameterFormEntry] {
        entries.filter {
            $0.definition.isRequired
                && $0.currentValue == nil
                && $0.source != .defaultValue
        }
    }

    /// Creates a new form state.
    public init(
        toolName: String,
        selectedSubcommand: String? = nil,
        entries: [ParameterFormEntry] = [],
        mode: ParameterFormMode = .standalone,
        isValid: Bool = false,
        generatedCommand: String = "",
        lastCommandUpdate: Date = Date(),
        isResettingToDefaults: Bool = false
    ) {
        self.toolName = toolName
        self.selectedSubcommand = selectedSubcommand
        self.entries = entries
        self.mode = mode
        self.isValid = isValid
        self.generatedCommand = generatedCommand
        self.lastCommandUpdate = lastCommandUpdate
        self.isResettingToDefaults = isResettingToDefaults
    }
}

// MARK: - 21.4 Network Parameter Injection

/// A single network-related parameter automatically injected from the active server profile.
public struct InjectedNetworkParam: Sendable, Hashable {
    /// Name of the `ToolParameterDefinition` this injection targets.
    public var parameterName: String

    /// CLI flag written into the command string (e.g. `"--host"`).
    public var cliFlag: String

    /// The injected value.
    public var value: ParameterValue

    /// Display name of the server profile that provided the value.
    public var serverProfileName: String

    /// Creates a new injected network parameter.
    public init(
        parameterName: String,
        cliFlag: String,
        value: ParameterValue,
        serverProfileName: String
    ) {
        self.parameterName = parameterName
        self.cliFlag = cliFlag
        self.value = value
        self.serverProfileName = serverProfileName
    }
}

/// The runtime state of network parameter injection for the active server profile.
public struct NetworkInjectionState: Sendable, Hashable {
    /// All parameters injected from the active server profile.
    public var injectedParams: [InjectedNetworkParam]

    /// Whether a server profile is currently configured and active.
    public var isServerConfigured: Bool

    /// Display name of the currently active server, or `nil` when none is configured.
    public var activeServerName: String?

    /// Whether any injected value has a warning (e.g. an override is in effect).
    public var hasWarnings: Bool

    /// Creates a new network injection state.
    public init(
        injectedParams: [InjectedNetworkParam] = [],
        isServerConfigured: Bool = false,
        activeServerName: String? = nil,
        hasWarnings: Bool = false
    ) {
        self.injectedParams = injectedParams
        self.isServerConfigured = isServerConfigured
        self.activeServerName = activeServerName
        self.hasWarnings = hasWarnings
    }
}

// MARK: - 21.5 Subcommand Handling

/// Runtime state for subcommand selection and the parameters it exposes.
public struct SubcommandState: Sendable, Hashable {
    /// Name of the CLI tool that owns these subcommands.
    public var toolName: String

    /// All subcommands available for this tool.
    public var subcommands: [ToolSubcommand]

    /// Token of the currently selected subcommand, or `nil` when none is chosen.
    public var selectedSubcommand: String?

    /// Parameters active for the current subcommand selection.
    public var activeParameters: [ToolParameterDefinition]

    /// Creates a new subcommand state.
    public init(
        toolName: String,
        subcommands: [ToolSubcommand],
        selectedSubcommand: String? = nil,
        activeParameters: [ToolParameterDefinition] = []
    ) {
        self.toolName = toolName
        self.subcommands = subcommands
        self.selectedSubcommand = selectedSubcommand
        self.activeParameters = activeParameters
    }
}

// MARK: - Overall Form State

/// The aggregated state for the entire Dynamic GUI Controls & Parameter Builder feature.
public struct ParameterBuilderState: Sendable, Hashable {
    /// Current state of the parameter form.
    public var formState: ParameterFormState

    /// Current state of network parameter injection.
    public var networkInjection: NetworkInjectionState

    /// Subcommand selection state, or `nil` when the tool has no subcommands.
    public var subcommandState: SubcommandState?

    /// Creates a new parameter builder state.
    public init(
        formState: ParameterFormState,
        networkInjection: NetworkInjectionState,
        subcommandState: SubcommandState? = nil
    ) {
        self.formState = formState
        self.networkInjection = networkInjection
        self.subcommandState = subcommandState
    }
}
