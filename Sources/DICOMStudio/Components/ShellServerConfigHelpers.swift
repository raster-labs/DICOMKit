// ShellServerConfigHelpers.swift
// DICOMStudio
//
// DICOM Studio — Helpers for Server Configuration Management (Milestone 19)
// NEMA-verified: 2026a, checked 2026-10-05 — AE Title validation compared with PS3.5 2026a Table 6.2-1 (AE:
// 16 bytes, Default Character Repertoire without backslash and control characters, not solely spaces) and
// PS3.8 Table 9-11: the alphanumerics-plus-" _-" rule admitted non-ASCII letters and refused valid punctuation,
// and now delegates to DICOMNetwork's AETitle; maxAETitleLength 16 matches. Default port 11112 is the PS3.8
// 2026a 9.1.1 registered port; the sample AE titles DICOMSTUDIO / ANY-SCP / ORTHANC / PACS_SCP are valid.
// The injected CLI flags are plumbing checked by the Workshop parity rows, not standard data.

import Foundation
import DICOMNetwork

// MARK: - Server Profile Helpers

/// Platform-independent helpers for server profile management.
public enum ServerProfileHelpers: Sendable {

    /// Maximum number of saved server profiles.
    public static let maxServers: Int = 20

    /// Keychain service prefix for credential storage.
    public static let keychainServicePrefix: String = "com.rasterlab.dicomstudio.server"

    /// Creates a default empty server profile.
    public static func defaultProfile() -> ShellServerProfile {
        ShellServerProfile(
            name: "New Server",
            type: .dicom,
            aeTitle: "DICOMSTUDIO",
            calledAET: "ANY-SCP",
            host: "localhost",
            port: 11112,
            timeout: 60
        )
    }

    /// Returns a set of sample server profiles for demonstration.
    public static func sampleProfiles() -> [ShellServerProfile] {
        [
            ShellServerProfile(
                name: "Local Orthanc",
                type: .dicom,
                aeTitle: "DICOMSTUDIO",
                calledAET: "ORTHANC",
                host: "localhost",
                port: 4242,
                timeout: 30,
                notes: "Local Orthanc DICOM server for development"
            ),
            ShellServerProfile(
                name: "Cloud DICOMweb",
                type: .dicomweb,
                host: "dicom.example.com",
                port: 443,
                baseURL: "https://dicom.example.com/dicomweb",
                authMethod: .bearer,
                tlsEnabled: true,
                notes: "Cloud-hosted DICOMweb endpoint"
            ),
            ShellServerProfile(
                name: "Hospital PACS",
                type: .dicom,
                aeTitle: "DICOMSTUDIO",
                calledAET: "PACS_SCP",
                host: "pacs.hospital.local",
                port: 11112,
                timeout: 120,
                notes: "Main hospital PACS archive"
            ),
        ]
    }

    /// Returns a one-line connection summary for a server profile.
    public static func connectionSummary(for profile: ShellServerProfile) -> String {
        switch profile.type {
        case .dicom:
            return "\(profile.aeTitle) → \(profile.calledAET)@\(profile.host):\(profile.port)"
        case .dicomweb:
            return profile.baseURL.isEmpty ? "\(profile.host):\(profile.port)" : profile.baseURL
        }
    }

    /// Returns a multi-line display string describing the server profile.
    public static func serverDisplayInfo(for profile: ShellServerProfile) -> String {
        var lines: [String] = []
        lines.append("Name: \(profile.name)")
        lines.append("Type: \(profile.type.displayName)")
        lines.append("Connection: \(connectionSummary(for: profile))")
        if profile.tlsEnabled {
            lines.append("TLS: Enabled")
        }
        if profile.authMethod != .none {
            lines.append("Auth: \(profile.authMethod.displayName)")
        }
        if !profile.notes.isEmpty {
            lines.append("Notes: \(profile.notes)")
        }
        return lines.joined(separator: "\n")
    }

    /// Creates a duplicate of a profile with a new ID and adjusted name.
    public static func duplicateProfile(_ profile: ShellServerProfile) -> ShellServerProfile {
        ShellServerProfile(
            id: UUID(),
            name: profile.name + " Copy",
            type: profile.type,
            aeTitle: profile.aeTitle,
            calledAET: profile.calledAET,
            host: profile.host,
            port: profile.port,
            timeout: profile.timeout,
            baseURL: profile.baseURL,
            authMethod: profile.authMethod,
            username: profile.username,
            tlsEnabled: profile.tlsEnabled,
            tlsCertificatePath: profile.tlsCertificatePath,
            isActive: false,
            createdAt: Date(),
            modifiedAt: Date(),
            notes: profile.notes
        )
    }
}

// MARK: - Server Validation Helpers

/// Platform-independent helpers for validating server profile fields.
public enum ServerValidationHelpers: Sendable {

    /// Maximum allowed AE Title length: 16 bytes (PS3.5 Table 6.2-1; PS3.8 Table 9-11).
    public static let maxAETitleLength: Int = AETitle.maxLength

    /// Valid TCP port range.
    public static let validPortRange: ClosedRange<Int> = 1...65535

    /// Validates all fields of a server profile and returns any errors found.
    public static func validateProfile(_ profile: ShellServerProfile) -> [ServerValidationError] {
        var errors: [ServerValidationError] = []

        if profile.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(ServerValidationError(
                field: .name,
                message: "Server name is required"
            ))
        }

        if let error = validateHost(profile.host) {
            errors.append(error)
        }
        if let error = validatePort(profile.port) {
            errors.append(error)
        }
        if let error = validateTimeout(profile.timeout) {
            errors.append(error)
        }

        if profile.type == .dicom {
            if let error = validateAETitle(profile.aeTitle) {
                errors.append(error)
            }
            if let error = validateAETitle(profile.calledAET) {
                errors.append(error)
            }
        }

        if profile.type == .dicomweb {
            if let error = validateURL(profile.baseURL) {
                errors.append(error)
            }
        }

        if profile.authMethod == .certificate {
            if let path = profile.tlsCertificatePath, path.isEmpty {
                errors.append(ServerValidationError(
                    field: .certificate,
                    message: "Certificate path is required when using certificate authentication"
                ))
            } else if profile.tlsCertificatePath == nil {
                errors.append(ServerValidationError(
                    field: .certificate,
                    message: "Certificate path is required when using certificate authentication"
                ))
            }
        }

        return errors
    }

    /// Validates a DICOM AE Title string.
    ///
    /// The rule is PS3.5 Table 6.2-1 (VR AE) as DICOMNetwork's `AETitle`
    /// applies it on the wire: at most 16 bytes once the non-significant
    /// leading and trailing spaces are removed, characters of the Default
    /// Character Repertoire (20H–7EH) without the backslash, and not solely
    /// spaces. Lowercase letters and punctuation such as `-` are valid.
    public static func validateAETitle(_ title: String) -> ServerValidationError? {
        let trimmed = title.trimmingCharacters(in: CharacterSet(charactersIn: " "))
        if trimmed.isEmpty {
            return ServerValidationError(field: .aeTitle, message: "AE Title is required")
        }
        if trimmed.utf8.count > maxAETitleLength {
            return ServerValidationError(
                field: .aeTitle,
                message: "AE Title must be \(maxAETitleLength) characters or fewer"
            )
        }
        if (try? AETitle(title)) == nil {
            return ServerValidationError(
                field: .aeTitle,
                message: "AE Title may only contain printable ASCII characters (20H–7EH), and no backslash"
            )
        }
        return nil
    }

    /// Validates a hostname or IP address string.
    public static func validateHost(_ host: String) -> ServerValidationError? {
        if host.trimmingCharacters(in: .whitespaces).isEmpty {
            return ServerValidationError(field: .host, message: "Hostname is required")
        }
        let invalidChars = CharacterSet.whitespaces
        if host.unicodeScalars.contains(where: { invalidChars.contains($0) }) {
            return ServerValidationError(field: .host, message: "Hostname must not contain spaces")
        }
        return nil
    }

    /// Validates a TCP port number.
    public static func validatePort(_ port: Int) -> ServerValidationError? {
        if !validPortRange.contains(port) {
            return ServerValidationError(
                field: .port,
                message: "Port must be between \(validPortRange.lowerBound) and \(validPortRange.upperBound)"
            )
        }
        return nil
    }

    /// Validates a DICOMweb base URL.
    public static func validateURL(_ url: String) -> ServerValidationError? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return ServerValidationError(field: .baseURL, message: "Base URL is required for DICOMweb")
        }
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            return ServerValidationError(
                field: .baseURL,
                message: "Base URL must start with http:// or https://"
            )
        }
        return nil
    }

    /// Validates a connection timeout value.
    public static func validateTimeout(_ timeout: Int) -> ServerValidationError? {
        if timeout < 1 {
            return ServerValidationError(field: .timeout, message: "Timeout must be at least 1 second")
        }
        if timeout > 600 {
            return ServerValidationError(field: .timeout, message: "Timeout must be 600 seconds or fewer")
        }
        return nil
    }

    /// Returns true if the profile has no validation errors.
    public static func isValidProfile(_ profile: ShellServerProfile) -> Bool {
        validateProfile(profile).isEmpty
    }
}

// MARK: - Server Persistence Helpers

/// Platform-independent helpers for server configuration persistence.
public enum ServerPersistenceHelpers: Sendable {

    /// Directory name inside Application Support.
    public static let configDirectoryName: String = "DICOMStudio"

    /// Configuration file name.
    public static let configFileName: String = "servers.json"

    /// Returns the expected path for the server configuration file.
    public static func configFilePath() -> String {
        let home = NSHomeDirectory()
        return "\(home)/Library/Application Support/\(configDirectoryName)/\(configFileName)"
    }

    /// Returns the keychain service name for a specific server profile.
    public static func keychainServiceName(for serverID: UUID) -> String {
        "\(ServerProfileHelpers.keychainServicePrefix).\(serverID.uuidString)"
    }

    /// Exports server profiles to JSON data, excluding credentials.
    public static func exportServers(_ profiles: [ShellServerProfile]) -> Data? {
        struct ExportableProfile: Codable {
            let id: String
            let name: String
            let type: String
            let aeTitle: String
            let calledAET: String
            let host: String
            let port: Int
            let timeout: Int
            let baseURL: String
            let authMethod: String
            let tlsEnabled: Bool
            let tlsCertificatePath: String?
            let notes: String
        }

        let exportable = profiles.map { profile in
            ExportableProfile(
                id: profile.id.uuidString,
                name: profile.name,
                type: profile.type.rawValue,
                aeTitle: profile.aeTitle,
                calledAET: profile.calledAET,
                host: profile.host,
                port: profile.port,
                timeout: profile.timeout,
                baseURL: profile.baseURL,
                authMethod: profile.authMethod.rawValue,
                tlsEnabled: profile.tlsEnabled,
                tlsCertificatePath: profile.tlsCertificatePath,
                notes: profile.notes
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(exportable)
    }

    /// Imports server profiles from JSON data.
    public static func importServers(from data: Data) -> ServerImportResult {
        struct ImportableProfile: Codable {
            let id: String?
            let name: String
            let type: String?
            let aeTitle: String?
            let calledAET: String?
            let host: String?
            let port: Int?
            let timeout: Int?
            let baseURL: String?
            let authMethod: String?
            let tlsEnabled: Bool?
            let tlsCertificatePath: String?
            let notes: String?
        }

        let decoder = JSONDecoder()
        guard let imported = try? decoder.decode([ImportableProfile].self, from: data) else {
            return ServerImportResult(
                importedCount: 0,
                skippedCount: 0,
                errors: ["Failed to decode JSON data"]
            )
        }

        var importedCount = 0
        var skippedCount = 0
        var errors: [String] = []

        for entry in imported {
            if entry.name.trimmingCharacters(in: .whitespaces).isEmpty {
                skippedCount += 1
                errors.append("Skipped entry with empty name")
                continue
            }
            importedCount += 1
        }

        return ServerImportResult(
            importedCount: importedCount,
            skippedCount: skippedCount,
            errors: errors
        )
    }

    /// Merges imported profiles with existing ones, skipping duplicates by name.
    public static func mergeImported(
        _ imported: [ShellServerProfile],
        existing: [ShellServerProfile]
    ) -> [ShellServerProfile] {
        let existingNames = Set(existing.map { $0.name })
        var merged = existing
        for profile in imported {
            if !existingNames.contains(profile.name) {
                var newProfile = profile
                newProfile = ShellServerProfile(
                    id: UUID(),
                    name: profile.name,
                    type: profile.type,
                    aeTitle: profile.aeTitle,
                    calledAET: profile.calledAET,
                    host: profile.host,
                    port: profile.port,
                    timeout: profile.timeout,
                    baseURL: profile.baseURL,
                    authMethod: profile.authMethod,
                    username: profile.username,
                    tlsEnabled: profile.tlsEnabled,
                    tlsCertificatePath: profile.tlsCertificatePath,
                    isActive: false,
                    createdAt: Date(),
                    modifiedAt: Date(),
                    notes: profile.notes
                )
                merged.append(newProfile)
            }
        }
        return merged
    }
}

// MARK: - Network Injector Helpers

/// Platform-independent helpers for injecting server parameters into CLI tool invocations.
public enum NetworkInjectorHelpers: Sendable {

    /// All network-capable CLI tool executable names.
    public static let networkToolNames: [String] = [
        "dicom-echo",
        "dicom-query",
        "dicom-send",
        "dicom-retrieve",
        "dicom-qr",
        "dicom-wado",
        "dicom-mwl",
        "dicom-mpps",
        "dicom-print",
        "dicom-gateway",
        "dicom-server",
    ]

    /// Injects appropriate parameters from a server profile for a given tool type.
    public static func injectParameters(
        from server: ShellServerProfile,
        for toolType: NetworkToolType
    ) -> [InjectedParameter] {
        switch server.type {
        case .dicom:
            return dicomParameters(from: server)
        case .dicomweb:
            return dicomwebParameters(from: server)
        }
    }

    /// Builds DICOM protocol parameters from a server profile.
    public static func dicomParameters(from server: ShellServerProfile) -> [InjectedParameter] {
        var params: [InjectedParameter] = []

        if !server.host.isEmpty {
            params.append(InjectedParameter(
                flagName: "--host",
                value: server.host,
                source: .serverConfig
            ))
        }

        params.append(InjectedParameter(
            flagName: "--port",
            value: "\(server.port)",
            source: .serverConfig
        ))

        if !server.aeTitle.isEmpty {
            params.append(InjectedParameter(
                flagName: "--aet",
                value: server.aeTitle,
                source: .serverConfig
            ))
        }

        if !server.calledAET.isEmpty {
            params.append(InjectedParameter(
                flagName: "--called-aet",
                value: server.calledAET,
                source: .serverConfig
            ))
        }

        params.append(InjectedParameter(
            flagName: "--timeout",
            value: "\(server.timeout)",
            source: .serverConfig
        ))

        if server.tlsEnabled {
            params.append(InjectedParameter(
                flagName: "--tls",
                value: "true",
                source: .serverConfig
            ))

            if let certPath = server.tlsCertificatePath, !certPath.isEmpty {
                params.append(InjectedParameter(
                    flagName: "--tls-cert",
                    value: certPath,
                    source: .serverConfig
                ))
            }
        }

        return params
    }

    /// Builds DICOMweb parameters from a server profile.
    public static func dicomwebParameters(from server: ShellServerProfile) -> [InjectedParameter] {
        var params: [InjectedParameter] = []

        if !server.baseURL.isEmpty {
            params.append(InjectedParameter(
                flagName: "--url",
                value: server.baseURL,
                source: .serverConfig
            ))
        }

        switch server.authMethod {
        case .basic:
            if !server.username.isEmpty {
                params.append(InjectedParameter(
                    flagName: "--auth",
                    value: "basic:\(server.username)",
                    source: .serverConfig
                ))
            }
        case .bearer:
            params.append(InjectedParameter(
                flagName: "--auth",
                value: "bearer",
                source: .serverConfig
            ))
        case .certificate:
            if let certPath = server.tlsCertificatePath, !certPath.isEmpty {
                params.append(InjectedParameter(
                    flagName: "--auth",
                    value: "cert:\(certPath)",
                    source: .serverConfig
                ))
            }
        case .none:
            break
        }

        return params
    }

    /// Builds a complete injection result for a tool invocation.
    public static func buildInjectionResult(
        server: ShellServerProfile?,
        toolType: NetworkToolType
    ) -> InjectionResult {
        guard let server = server else {
            return InjectionResult(
                toolType: toolType,
                parameters: [],
                hasServerConfig: false
            )
        }
        let params = injectParameters(from: server, for: toolType)
        return InjectionResult(
            toolType: toolType,
            parameters: params,
            hasServerConfig: true
        )
    }

    /// Checks whether a given tool name requires network/server parameters.
    public static func isNetworkTool(_ toolName: String) -> Bool {
        networkToolNames.contains(toolName)
    }
}

// MARK: - Keychain Helpers

/// Stub helpers for keychain credential storage.
///
/// These are platform-independent stubs. Real keychain access
/// requires Security framework and is implemented in platform-specific code.
public enum ShellKeychainHelpers: Sendable {

    /// Returns a stub keychain query dictionary.
    public static func keychainQuery(service: String) -> [String: Any] {
        [
            "service": service,
            "class": "genericPassword",
        ]
    }

    /// Stores a credential in the keychain (stub — always returns true).
    public static func storeCredential(_ credential: String, service: String) -> Bool {
        // Stub: real implementation uses Security framework
        true
    }

    /// Retrieves a credential from the keychain (stub — always returns nil).
    public static func retrieveCredential(service: String) -> String? {
        // Stub: real implementation uses Security framework
        nil
    }

    /// Deletes a credential from the keychain (stub — always returns true).
    public static func deleteCredential(service: String) -> Bool {
        // Stub: real implementation uses Security framework
        true
    }

    /// Checks whether a credential exists in the keychain (stub — always returns false).
    public static func credentialExists(service: String) -> Bool {
        // Stub: real implementation uses Security framework
        false
    }
}
