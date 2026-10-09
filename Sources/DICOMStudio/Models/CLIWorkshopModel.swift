// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (CLI Workshop data models: tool and parameter definitions, visibility conditions, history, presets, terminal/SCP log levels; grep for (gggg,eeee) tags, 1.2.840.10008 UIDs, STD-* profiles, VR codes and PS3 clauses found none); the standard-derived form content is in CLIWorkshopHelpers.swift and the executors in CLIWorkshopViewModel.swift
// CLIWorkshopModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for CLI Tools Workshop (Milestone 16)

import Foundation

// MARK: - Navigation Tab

/// Navigation tabs for the CLI Tools Workshop feature.
public enum CLIWorkshopTab: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case fileInspection    = "FILE_INSPECTION"
    case fileProcessing    = "FILE_PROCESSING"
    case fileOrganization  = "FILE_ORGANIZATION"
    case dataExport        = "DATA_EXPORT"
    case networkOperations = "NETWORK_OPERATIONS"
    case automation        = "AUTOMATION"
    case listener          = "LISTENER"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .fileInspection:    return "File Inspection"
        case .fileProcessing:    return "File Processing"
        case .fileOrganization:  return "File Organization"
        case .dataExport:        return "Data Export"
        case .networkOperations: return "Network Operations"
        case .automation:        return "Automation"
        case .listener:          return "Listener & Log"
        }
    }

    /// SF Symbol name for this tab.
    public var sfSymbol: String {
        switch self {
        case .fileInspection:    return "doc.text.magnifyingglass"
        case .fileProcessing:    return "gearshape.2"
        case .fileOrganization:  return "folder.badge.gearshape"
        case .dataExport:        return "square.and.arrow.up"
        case .networkOperations: return "network"
        case .automation:        return "terminal"
        case .listener:          return "antenna.radiowaves.left.and.right"
        }
    }

    /// Brief description of the tools in this tab.
    public var tabDescription: String {
        switch self {
        case .fileInspection:    return "Inspect, dump, tag-edit, and diff DICOM files"
        case .fileProcessing:    return "Convert, validate, anonymize, and compress DICOM files"
        case .fileOrganization:  return "Split, merge, create DICOMDIR, and archive files"
        case .dataExport:        return "Export to JSON, XML, PDF, images, and pixel editing"
        case .networkOperations: return "Echo, query, send, retrieve, and DICOMweb operations"
        case .automation:        return "Study workflows, UID tools, and scripting"
        case .listener:          return "Local SCP listener status and event log"
        }
    }
}

// MARK: - 16.1 Network Configuration

/// Protocol type for PACS connections.
public enum CLIProtocolType: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case dicom    = "DICOM"
    case dicomweb = "DICOMweb"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .dicom:    return "DICOM"
        case .dicomweb: return "DICOMweb"
        }
    }
}

/// A saved PACS network configuration profile.
public struct CLINetworkProfile: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var aeTitle: String
    public var calledAET: String
    public var host: String
    public var port: Int
    public var timeout: Int
    public var protocolType: CLIProtocolType
    public var isDefault: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        aeTitle: String = "DICOMSTUDIO",
        calledAET: String = "ANY-SCP",
        host: String = "localhost",
        port: Int = 11112,
        timeout: Int = 60,
        protocolType: CLIProtocolType = .dicom,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.aeTitle = aeTitle
        self.calledAET = calledAET
        self.host = host
        self.port = port
        self.timeout = timeout
        self.protocolType = protocolType
        self.isDefault = isDefault
    }
}

/// Connection test result status.
public enum CLIConnectionTestStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case untested  = "UNTESTED"
    case testing   = "TESTING"
    case success   = "SUCCESS"
    case failure   = "FAILURE"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .untested: return "Not Tested"
        case .testing:  return "Testing…"
        case .success:  return "Connected"
        case .failure:  return "Failed"
        }
    }

    /// SF Symbol for this status.
    public var sfSymbol: String {
        switch self {
        case .untested: return "questionmark.circle"
        case .testing:  return "arrow.triangle.2.circlepath"
        case .success:  return "checkmark.circle.fill"
        case .failure:  return "xmark.circle.fill"
        }
    }
}

// MARK: - 16.2 Tool Definitions

/// Grouping for network operation tools: DIMSE services vs DICOMweb.
public enum NetworkToolGroup: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case dimse    = "DIMSE"
    case dicomweb = "DICOMWEB"

    public var id: String { rawValue }

    /// Human-readable section header.
    public var displayName: String {
        switch self {
        case .dimse:    return "DIMSE Services"
        case .dicomweb: return "DICOMweb"
        }
    }

    /// SF Symbol for this group.
    public var sfSymbol: String {
        switch self {
        case .dimse:    return "server.rack"
        case .dicomweb: return "globe"
        }
    }
}

/// A CLI tool definition with metadata.
public struct CLIToolDefinition: Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var displayName: String
    public var category: CLIWorkshopTab
    public var sfSymbol: String
    public var briefDescription: String
    public var dicomStandardRef: String
    public var hasSubcommands: Bool
    public var requiresNetwork: Bool
    public var networkToolGroup: NetworkToolGroup?

    public init(
        id: String,
        name: String,
        displayName: String,
        category: CLIWorkshopTab,
        sfSymbol: String,
        briefDescription: String,
        dicomStandardRef: String = "",
        hasSubcommands: Bool = false,
        requiresNetwork: Bool = false,
        networkToolGroup: NetworkToolGroup? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.category = category
        self.sfSymbol = sfSymbol
        self.briefDescription = briefDescription
        self.dicomStandardRef = dicomStandardRef
        self.hasSubcommands = hasSubcommands
        self.requiresNetwork = requiresNetwork
        self.networkToolGroup = networkToolGroup
    }
}

// MARK: - 16.3 Parameter Configuration

/// Types of CLI parameter controls.
public enum CLIParameterType: String, Sendable, Equatable, Hashable, CaseIterable {
    case filePath      = "FILE_PATH"
    case outputPath    = "OUTPUT_PATH"
    case enumPicker    = "ENUM_PICKER"
    case textField     = "TEXT_FIELD"
    case integerField  = "INTEGER_FIELD"
    case booleanToggle = "BOOLEAN_TOGGLE"
    case arrayField    = "ARRAY_FIELD"
    case datePicker    = "DATE_PICKER"
    case slider        = "SLIDER"
    case secureField   = "SECURE_FIELD"
    case subcommand    = "SUBCOMMAND"
    case flagPicker    = "FLAG_PICKER"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .filePath:      return "File Path"
        case .outputPath:    return "Output Path"
        case .enumPicker:    return "Picker"
        case .textField:     return "Text Field"
        case .integerField:  return "Integer"
        case .booleanToggle: return "Toggle"
        case .arrayField:    return "List"
        case .datePicker:    return "Date"
        case .slider:        return "Slider"
        case .secureField:   return "Secure Field"
        case .subcommand:    return "Subcommand"
        case .flagPicker:    return "Flag Picker"
        }
    }
}

/// A single CLI parameter definition.
/// A condition that controls when a parameter is visible based on another parameter's value.
public struct CLIParameterVisibilityCondition: Sendable, Hashable {
    public let parameterId: String
    public let values: [String]

    public init(parameterId: String, values: [String]) {
        self.parameterId = parameterId
        self.values = values
    }
}

public struct CLIParameterDefinition: Sendable, Identifiable, Hashable {
    public let id: String
    public var flag: String
    public var displayName: String
    public var parameterType: CLIParameterType
    public var placeholder: String
    public var helpText: String
    public var isRequired: Bool
    public var isAdvanced: Bool
    /// When `true`, this parameter is used only by DICOMStudio's internal
    /// execution and does **not** correspond to an actual CLI flag.  It will
    /// still appear in the UI form but will be excluded from
    /// `buildCommand()` output.
    public var isInternal: Bool
    /// When `true`, this parameter maps to a **repeatable** CLI option that
    /// the real CLI declares as an array (e.g. `--tag`, `--set`, `--delete`,
    /// `--ignore-tag`).  The UI still presents a single comma-separated text
    /// field, but `buildCommand()` expands it into one `--flag value` token
    /// per value — matching how the CLI actually consumes the option — instead
    /// of emitting a single comma-joined flag (which the CLI would treat as one
    /// literal value).  Splitting is hex-tag aware via
    /// ``CommandBuilderHelpers/splitMultiValue(_:)`` so `GGGG,EEEE` tags stay
    /// intact.  Leave `false` for options the CLI itself comma-splits (e.g.
    /// `dicom-tags --tags`).
    public var isRepeatable: Bool
    /// The CLI token emitted when a ``CLIParameterType/booleanToggle`` is
    /// explicitly **off**.  Used for inverted flags declared with
    /// `@Flag(inversion: .prefixedNo)` and a `true` default (e.g.
    /// `dicom-dcmdir create --recursive/--no-recursive`): toggling OFF must
    /// emit the negated token (`--no-recursive`) — omitting it would make the
    /// pasted command silently re-enable the behavior the user disabled.
    /// `nil` (the default) keeps the standard emit-only-when-true behavior.
    public var negatedFlag: String?
    public var defaultValue: String
    public var allowedValues: [String]
    public var minValue: Int?
    public var maxValue: Int?
    /// When set, this parameter is only visible if the referenced parameter
    /// currently has one of the specified values.
    public var visibleWhen: CLIParameterVisibilityCondition?
    /// Additional conditions that must **all** hold (together with
    /// ``visibleWhen``) for this parameter to be visible. Use when one
    /// condition is not enough to pin the parameter down — e.g. dicom-compress'
    /// JPEG Engine picker needs `operation == compress` AND `codec == jpeg`,
    /// because the `codec` value persists across operations and would otherwise
    /// leak the picker into the decompress/batch/info forms.
    public var visibleWhenAll: [CLIParameterVisibilityCondition]
    /// Maps internal enum values to CLI argument strings for the command
    /// preview.  Used when ``isInternal`` is `true`, and also consulted by
    /// ``CLIParameterType/flagPicker`` parameters to override the literal
    /// `--<value>` token when the in-app state executes as a different CLI
    /// mode (e.g. dicom-qr `["interactive": "--auto"]`).  Each entry maps
    /// an ``allowedValues`` element to the literal CLI tokens that should
    /// appear in the preview (e.g. `["wado-uri": "--uri"]`).  Values
    /// that do not appear in the dictionary (or that map to an empty
    /// string) are silently omitted (for flag pickers, the literal
    /// `--<value>` is emitted instead).
    public var cliMapping: [String: String]

    public init(
        id: String,
        flag: String,
        displayName: String,
        parameterType: CLIParameterType,
        placeholder: String = "",
        helpText: String = "",
        isRequired: Bool = false,
        isAdvanced: Bool = false,
        isInternal: Bool = false,
        isRepeatable: Bool = false,
        negatedFlag: String? = nil,
        defaultValue: String = "",
        allowedValues: [String] = [],
        minValue: Int? = nil,
        maxValue: Int? = nil,
        visibleWhen: CLIParameterVisibilityCondition? = nil,
        visibleWhenAll: [CLIParameterVisibilityCondition] = [],
        cliMapping: [String: String] = [:]
    ) {
        self.id = id
        self.flag = flag
        self.displayName = displayName
        self.parameterType = parameterType
        self.placeholder = placeholder
        self.helpText = helpText
        self.isRequired = isRequired
        self.isAdvanced = isAdvanced
        self.isInternal = isInternal
        self.isRepeatable = isRepeatable
        self.negatedFlag = negatedFlag
        self.defaultValue = defaultValue
        self.allowedValues = allowedValues
        self.minValue = minValue
        self.maxValue = maxValue
        self.visibleWhen = visibleWhen
        self.visibleWhenAll = visibleWhenAll
        self.cliMapping = cliMapping
    }
}

/// A user-provided value for a CLI parameter.
public struct CLIParameterValue: Sendable, Identifiable, Hashable {
    public let id: String
    public var parameterID: String
    public var stringValue: String

    public init(
        id: String = UUID().uuidString,
        parameterID: String,
        stringValue: String = ""
    ) {
        self.id = id
        self.parameterID = parameterID
        self.stringValue = stringValue
    }
}

// MARK: - 16.4 File Drop Zone

/// Visual state of the file drop zone.
public enum CLIFileDropState: String, Sendable, Equatable, Hashable, CaseIterable {
    case empty     = "EMPTY"
    case selected  = "SELECTED"
    case dragHover = "DRAG_HOVER"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .empty:     return "Empty"
        case .selected:  return "File Selected"
        case .dragHover: return "Drop Here"
        }
    }
}

/// A file entry selected for a CLI tool.
public struct CLIFileEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var path: String
    public var filename: String
    public var fileSize: Int64
    public var isDICOM: Bool

    public init(
        id: UUID = UUID(),
        path: String,
        filename: String,
        fileSize: Int64 = 0,
        isDICOM: Bool = true
    ) {
        self.id = id
        self.path = path
        self.filename = filename
        self.fileSize = fileSize
        self.isDICOM = isDICOM
    }
}

// MARK: - 16.5 Console

/// Status of the CLI console.
public enum CLIConsoleStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case idle    = "IDLE"
    case running = "RUNNING"
    case success = "SUCCESS"
    case error   = "ERROR"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .idle:    return "Idle"
        case .running: return "Running"
        case .success: return "Success"
        case .error:   return "Error"
        }
    }

    /// SF Symbol for this status.
    public var sfSymbol: String {
        switch self {
        case .idle:    return "circle"
        case .running: return "progress.indicator"
        case .success: return "checkmark.circle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }
}

/// Syntax highlight token types for command preview.
public enum CLISyntaxTokenType: String, Sendable, Equatable, Hashable, CaseIterable {
    case toolName = "TOOL_NAME"
    case flag     = "FLAG"
    case value    = "VALUE"
    case path     = "PATH"
    case plain    = "PLAIN"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .toolName: return "Tool Name"
        case .flag:     return "Flag"
        case .value:    return "Value"
        case .path:     return "Path"
        case .plain:    return "Plain"
        }
    }
}

/// A single token in the syntax-highlighted command preview.
public struct CLISyntaxToken: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var text: String
    public var tokenType: CLISyntaxTokenType

    public init(
        id: UUID = UUID(),
        text: String,
        tokenType: CLISyntaxTokenType
    ) {
        self.id = id
        self.text = text
        self.tokenType = tokenType
    }
}

// MARK: - 16.6 Command Builder & Execution

/// Execution state of a command.
public enum CLIExecutionState: String, Sendable, Equatable, Hashable, CaseIterable {
    case idle      = "IDLE"
    case running   = "RUNNING"
    case completed = "COMPLETED"
    case failed    = "FAILED"
    case cancelled = "CANCELLED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .idle:      return "Idle"
        case .running:   return "Running"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    /// SF Symbol for this state.
    public var sfSymbol: String {
        switch self {
        case .idle:      return "circle"
        case .running:   return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }
}

/// A command history entry with PHI redaction.
public struct CLICommandHistoryEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var toolName: String
    public var rawCommand: String
    public var redactedCommand: String
    public var executionState: CLIExecutionState
    public var exitCode: Int?
    public var timestamp: Date
    public var outputSnippet: String

    public init(
        id: UUID = UUID(),
        toolName: String,
        rawCommand: String,
        redactedCommand: String,
        executionState: CLIExecutionState = .completed,
        exitCode: Int? = nil,
        timestamp: Date = Date(),
        outputSnippet: String = ""
    ) {
        self.id = id
        self.toolName = toolName
        self.rawCommand = rawCommand
        self.redactedCommand = redactedCommand
        self.executionState = executionState
        self.exitCode = exitCode
        self.timestamp = timestamp
        self.outputSnippet = outputSnippet
    }
}

// MARK: - 16.8 Educational Features

/// Experience mode controlling parameter visibility.
public enum CLIExperienceMode: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case beginner = "BEGINNER"
    case advanced = "ADVANCED"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .advanced: return "Advanced"
        }
    }

    /// SF Symbol for this mode.
    public var sfSymbol: String {
        switch self {
        case .beginner: return "graduationcap"
        case .advanced: return "gearshape.2"
        }
    }

    /// Brief description of what this mode shows.
    public var modeDescription: String {
        switch self {
        case .beginner: return "Shows essential parameters only. Advanced options like force-parse and byte-order are hidden."
        case .advanced: return "Shows all available parameters including advanced and rarely-used options."
        }
    }
}

/// A DICOM glossary entry for the educational sidebar.
public struct CLIGlossaryEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var term: String
    public var definition: String
    public var standardReference: String

    public init(
        id: UUID = UUID(),
        term: String,
        definition: String,
        standardReference: String = ""
    ) {
        self.id = id
        self.term = term
        self.definition = definition
        self.standardReference = standardReference
    }
}

/// An example command preset for a CLI tool.
public struct CLIExamplePreset: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var toolID: String
    public var title: String
    public var presetDescription: String
    public var commandString: String

    public init(
        id: UUID = UUID(),
        toolID: String,
        title: String,
        presetDescription: String,
        commandString: String
    ) {
        self.id = id
        self.toolID = toolID
        self.title = title
        self.presetDescription = presetDescription
        self.commandString = commandString
    }
}

// MARK: - Listener & Log models

/// Severity level of a local SCP log event.
public enum SCPLogLevel: String, Sendable, Equatable, Hashable, CaseIterable {
    case info         = "INFO"
    case connection   = "CONNECTION"
    case fileReceived = "FILE_RECEIVED"
    case warning      = "WARNING"
    case error        = "ERROR"

    /// SF Symbol for this level.
    public var sfSymbol: String {
        switch self {
        case .info:         return "info.circle"
        case .connection:   return "link.circle"
        case .fileReceived: return "tray.and.arrow.down"
        case .warning:      return "exclamationmark.triangle"
        case .error:        return "xmark.circle"
        }
    }

    /// Foreground color name usable in SwiftUI `.foregroundStyle(Color(<name>))`.
    public var colorName: String {
        switch self {
        case .info:         return "secondary"
        case .connection:   return "blue"
        case .fileReceived: return "green"
        case .warning:      return "orange"
        case .error:        return "red"
        }
    }
}

/// A single structured event entry in the local SCP event log.
public struct SCPLogEntry: Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: SCPLogLevel
    public let message: String
    /// Calling AE title of the remote peer, if applicable.
    public let remoteAETitle: String?
    /// IP address or hostname of the remote peer, if applicable.
    public let remoteHost: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: SCPLogLevel,
        message: String,
        remoteAETitle: String? = nil,
        remoteHost: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.remoteAETitle = remoteAETitle
        self.remoteHost = remoteHost
    }
}

