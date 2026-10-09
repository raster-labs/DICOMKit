// ShellServerConfigModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for Server Configuration Management (Milestone 19)
// NEMA-verified: 2026a, checked 2026-10-05 — the only standard-derived value is the default DICOM port 11112, the
// PS3.8 2026a 9.1.1 registered port; everything else is UI state (server types, auth methods, validation
// fields, tool names). AE titles are validated in ShellServerConfigHelpers.swift against PS3.5 Table 6.2-1.

import Foundation

// MARK: - 19.1 Server Configuration Model

/// The type of DICOM server connection.
public enum ShellServerType: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case dicom    = "DICOM"
    case dicomweb = "DICOMWEB"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .dicom:    return "DICOM (C-STORE/C-FIND)"
        case .dicomweb: return "DICOMweb (WADO-RS/STOW-RS)"
        }
    }

    /// SF Symbol name for the server type.
    public var sfSymbol: String {
        switch self {
        case .dicom:    return "server.rack"
        case .dicomweb: return "globe"
        }
    }
}

/// Authentication method for server connections.
public enum ShellAuthMethod: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case none        = "NONE"
    case basic       = "BASIC"
    case bearer      = "BEARER"
    case certificate = "CERTIFICATE"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .none:        return "None"
        case .basic:       return "Basic (Username/Password)"
        case .bearer:      return "Bearer Token"
        case .certificate: return "Client Certificate"
        }
    }
}

/// A saved server connection profile.
public struct ShellServerProfile: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// User-assigned display name for this server.
    public var name: String

    /// Server connection type.
    public var type: ShellServerType

    /// Local AE Title (calling AET).
    public var aeTitle: String

    /// Remote AE Title (called AET).
    public var calledAET: String

    /// Server hostname or IP address.
    public var host: String

    /// Server port number.
    public var port: Int

    /// Connection timeout in seconds.
    public var timeout: Int

    /// Base URL for DICOMweb connections.
    public var baseURL: String

    /// Authentication method.
    public var authMethod: ShellAuthMethod

    /// Username for basic authentication.
    public var username: String

    /// Whether TLS is enabled.
    public var tlsEnabled: Bool

    /// Path to the TLS client certificate, if any.
    public var tlsCertificatePath: String?

    /// Whether this is the currently active server.
    public var isActive: Bool

    /// Timestamp when this profile was created.
    public let createdAt: Date

    /// Timestamp when this profile was last modified.
    public var modifiedAt: Date

    /// User notes about this server.
    public var notes: String

    /// Creates a new server profile.
    public init(
        id: UUID = UUID(),
        name: String,
        type: ShellServerType,
        aeTitle: String = "",
        calledAET: String = "",
        host: String = "",
        port: Int = 11112,
        timeout: Int = 60,
        baseURL: String = "",
        authMethod: ShellAuthMethod = .none,
        username: String = "",
        tlsEnabled: Bool = false,
        tlsCertificatePath: String? = nil,
        isActive: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.aeTitle = aeTitle
        self.calledAET = calledAET
        self.host = host
        self.port = port
        self.timeout = timeout
        self.baseURL = baseURL
        self.authMethod = authMethod
        self.username = username
        self.tlsEnabled = tlsEnabled
        self.tlsCertificatePath = tlsCertificatePath
        self.isActive = isActive
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.notes = notes
    }
}

/// Connection status for a server profile in the shell configuration manager.
public enum ShellServerConnectionStatus: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case untested  = "UNTESTED"
    case testing   = "TESTING"
    case connected = "CONNECTED"
    case failed    = "FAILED"
    case timeout   = "TIMEOUT"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .untested:  return "Not Tested"
        case .testing:   return "Testing…"
        case .connected: return "Connected"
        case .failed:    return "Failed"
        case .timeout:   return "Timed Out"
        }
    }

    /// SF Symbol name for the connection status.
    public var sfSymbol: String {
        switch self {
        case .untested:  return "questionmark.circle"
        case .testing:   return "arrow.triangle.2.circlepath"
        case .connected: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        case .timeout:   return "clock.badge.exclamationmark"
        }
    }

    /// Color name representing this status.
    public var statusColor: String {
        switch self {
        case .untested:  return "gray"
        case .testing:   return "blue"
        case .connected: return "green"
        case .failed:    return "red"
        case .timeout:   return "orange"
        }
    }
}

// MARK: - 19.2 Server Persistence

/// State of server configuration persistence operations.
public enum ServerPersistenceState: Sendable, Equatable {
    case idle
    case loading
    case saving
    case error(String)
}

/// Result of a server configuration import operation.
public struct ServerImportResult: Sendable, Identifiable, Hashable {
    /// Unique identifier for this import result.
    public let id: UUID

    /// Number of profiles successfully imported.
    public let importedCount: Int

    /// Number of profiles skipped (duplicates).
    public let skippedCount: Int

    /// Error messages encountered during import.
    public let errors: [String]

    /// Timestamp of the import.
    public let timestamp: Date

    /// Creates a new import result.
    public init(
        id: UUID = UUID(),
        importedCount: Int,
        skippedCount: Int,
        errors: [String] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.errors = errors
        self.timestamp = timestamp
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: ServerImportResult, rhs: ServerImportResult) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 19.3 Server Configuration UI

/// Mode for the server profile editor.
public enum ServerEditorMode: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case add       = "ADD"
    case edit      = "EDIT"
    case duplicate = "DUPLICATE"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .add:       return "Add Server"
        case .edit:      return "Edit Server"
        case .duplicate: return "Duplicate Server"
        }
    }
}

/// Actions available in the server manager.
public enum ServerManagerAction: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case add            = "ADD"
    case edit           = "EDIT"
    case duplicate      = "DUPLICATE"
    case delete         = "DELETE"
    case setActive      = "SET_ACTIVE"
    case testConnection = "TEST_CONNECTION"
    case importConfig   = "IMPORT_CONFIG"
    case exportConfig   = "EXPORT_CONFIG"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .add:            return "Add Server"
        case .edit:           return "Edit Server"
        case .duplicate:      return "Duplicate Server"
        case .delete:         return "Delete Server"
        case .setActive:      return "Set as Active"
        case .testConnection: return "Test Connection"
        case .importConfig:   return "Import Configuration"
        case .exportConfig:   return "Export Configuration"
        }
    }

    /// SF Symbol name for the action.
    public var sfSymbol: String {
        switch self {
        case .add:            return "plus.circle"
        case .edit:           return "pencil.circle"
        case .duplicate:      return "doc.on.doc"
        case .delete:         return "trash"
        case .setActive:      return "checkmark.circle"
        case .testConnection: return "antenna.radiowaves.left.and.right"
        case .importConfig:   return "square.and.arrow.down"
        case .exportConfig:   return "square.and.arrow.up"
        }
    }
}

/// Fields that can be validated in a server profile.
public enum ServerValidationField: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case name        = "NAME"
    case host        = "HOST"
    case port        = "PORT"
    case aeTitle     = "AE_TITLE"
    case calledAET   = "CALLED_AET"
    case baseURL     = "BASE_URL"
    case timeout     = "TIMEOUT"
    case certificate = "CERTIFICATE"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .name:        return "Server Name"
        case .host:        return "Hostname"
        case .port:        return "Port"
        case .aeTitle:     return "AE Title"
        case .calledAET:   return "Called AE Title"
        case .baseURL:     return "Base URL"
        case .timeout:     return "Timeout"
        case .certificate: return "Certificate"
        }
    }
}

/// A validation error for a specific field.
public struct ServerValidationError: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// The field that failed validation.
    public let field: ServerValidationField

    /// Human-readable error message.
    public let message: String

    /// Creates a new validation error.
    public init(
        id: UUID = UUID(),
        field: ServerValidationField,
        message: String
    ) {
        self.id = id
        self.field = field
        self.message = message
    }
}

// MARK: - 19.4 Network Parameter Injection

/// A single parameter injected into a CLI tool invocation.
public struct InjectedParameter: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// CLI flag name (e.g. "--host").
    public let flagName: String

    /// Parameter value.
    public let value: String

    /// Where this parameter value came from.
    public let source: ParameterSource

    /// Whether the user has overridden the server-provided value.
    public var isOverridden: Bool

    /// Creates a new injected parameter.
    public init(
        id: UUID = UUID(),
        flagName: String,
        value: String,
        source: ParameterSource,
        isOverridden: Bool = false
    ) {
        self.id = id
        self.flagName = flagName
        self.value = value
        self.source = source
        self.isOverridden = isOverridden
    }
}

/// Source of an injected parameter value.
public enum ParameterSource: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case serverConfig = "SERVER_CONFIG"
    case userOverride = "USER_OVERRIDE"
    case defaultValue = "DEFAULT_VALUE"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .serverConfig: return "Server Configuration"
        case .userOverride: return "User Override"
        case .defaultValue: return "Default Value"
        }
    }

    /// SF Symbol name for the parameter source.
    public var sfSymbol: String {
        switch self {
        case .serverConfig: return "server.rack"
        case .userOverride: return "person.fill"
        case .defaultValue: return "gearshape"
        }
    }
}

/// Network-capable CLI tools that accept server parameters.
public enum NetworkToolType: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case dicomEcho     = "DICOM_ECHO"
    case dicomQuery    = "DICOM_QUERY"
    case dicomSend     = "DICOM_SEND"
    case dicomRetrieve = "DICOM_RETRIEVE"
    case dicomQR       = "DICOM_QR"
    case dicomWado     = "DICOM_WADO"
    case dicomMWL      = "DICOM_MWL"
    case dicomMPPS     = "DICOM_MPPS"
    case dicomPrint    = "DICOM_PRINT"
    case dicomGateway  = "DICOM_GATEWAY"
    case dicomServer   = "DICOM_SERVER"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .dicomEcho:     return "DICOM Echo"
        case .dicomQuery:    return "DICOM Query"
        case .dicomSend:     return "DICOM Send"
        case .dicomRetrieve: return "DICOM Retrieve"
        case .dicomQR:       return "DICOM Q/R"
        case .dicomWado:     return "DICOMweb WADO"
        case .dicomMWL:      return "Modality Worklist"
        case .dicomMPPS:     return "MPPS"
        case .dicomPrint:    return "DICOM Print"
        case .dicomGateway:  return "DICOM Gateway"
        case .dicomServer:   return "DICOM Server"
        }
    }

    /// CLI tool executable name.
    public var toolName: String {
        switch self {
        case .dicomEcho:     return "dicom-echo"
        case .dicomQuery:    return "dicom-query"
        case .dicomSend:     return "dicom-send"
        case .dicomRetrieve: return "dicom-retrieve"
        case .dicomQR:       return "dicom-qr"
        case .dicomWado:     return "dicom-wado"
        case .dicomMWL:      return "dicom-mwl"
        case .dicomMPPS:     return "dicom-mpps"
        case .dicomPrint:    return "dicom-print"
        case .dicomGateway:  return "dicom-gateway"
        case .dicomServer:   return "dicom-server"
        }
    }
}

/// Result of injecting server parameters into a CLI tool invocation.
public struct InjectionResult: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// The target CLI tool type.
    public let toolType: NetworkToolType

    /// Parameters injected for this invocation.
    public let parameters: [InjectedParameter]

    /// Whether a server configuration was available.
    public let hasServerConfig: Bool

    /// Creates a new injection result.
    public init(
        id: UUID = UUID(),
        toolType: NetworkToolType,
        parameters: [InjectedParameter],
        hasServerConfig: Bool
    ) {
        self.id = id
        self.toolType = toolType
        self.parameters = parameters
        self.hasServerConfig = hasServerConfig
    }
}
