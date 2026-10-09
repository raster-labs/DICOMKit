// NEMA-verified: 2026a, checked 2026-10-01 — the server, allowed, blocked and Move Destination AE titles are validated as VR AE per PS3.5 2026a Table 6.2-1 (D94); an unknown Move Destination resolves to nil for the A801 response of PS3.4 Table C.4-2 (D96); maxPDUSize is the PS3.8 D.1 Maximum Length the server announces; the rest (port, paths, connection limits, TLS switch) is plumbing
import Foundation

/// Configuration for the DICOM Server
public struct ServerConfiguration: Sendable, Codable {
    /// Application Entity Title
    public let aeTitle: String
    
    /// Port to listen on
    public let port: UInt16
    
    /// Data directory for storing DICOM files
    public let dataDirectory: String
    
    /// Database connection URL
    public let databaseURL: String
    
    /// Maximum concurrent connections
    public let maxConcurrentConnections: Int
    
    /// Maximum PDU size
    public let maxPDUSize: UInt32
    
    /// Allowed calling AE titles (whitelist)
    public let allowedCallingAETitles: Set<String>?
    
    /// Blocked calling AE titles (blacklist)
    public let blockedCallingAETitles: Set<String>?
    
    /// Enable TLS/SSL
    public let enableTLS: Bool
    
    /// Verbose logging
    public let verbose: Bool
    
    /// Known destination AE titles for C-MOVE operations
    /// Maps AE title to (host, port, aeTitle)
    public let knownDestinations: [String: DestinationAE]
    
    public init(
        aeTitle: String,
        port: UInt16,
        dataDirectory: String,
        databaseURL: String,
        maxConcurrentConnections: Int = 10,
        maxPDUSize: UInt32 = 16384,
        allowedCallingAETitles: Set<String>? = nil,
        blockedCallingAETitles: Set<String>? = nil,
        enableTLS: Bool = false,
        verbose: Bool = false,
        knownDestinations: [String: DestinationAE] = [:]
    ) {
        self.aeTitle = aeTitle
        self.port = port
        self.dataDirectory = dataDirectory
        self.databaseURL = databaseURL
        self.maxConcurrentConnections = maxConcurrentConnections
        self.maxPDUSize = maxPDUSize
        self.allowedCallingAETitles = allowedCallingAETitles
        self.blockedCallingAETitles = blockedCallingAETitles
        self.enableTLS = enableTLS
        self.verbose = verbose
        self.knownDestinations = knownDestinations
    }
    
    /// Load configuration from a JSON file
    public static func load(from path: String) throws -> ServerConfiguration {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        return try decoder.decode(ServerConfiguration.self, from: data)
    }
    
    /// The configuration with every AE title checked as VR AE (PS3.5 Table 6.2-1: at most 16
    /// characters, no backslash or control characters) and trimmed of non-significant spaces.
    ///
    /// - Throws: `ServerError.invalidConfiguration` naming the offending value
    public func validated() throws -> ServerConfiguration {
        let ae = try ServerProtocol.validatedAETitle(aeTitle, option: "--aet")
        let allowed = try allowedCallingAETitles.map { titles in
            Set(try titles.map { try ServerProtocol.validatedAETitle($0, option: "--allowed-ae") })
        }
        let blocked = try blockedCallingAETitles.map { titles in
            Set(try titles.map { try ServerProtocol.validatedAETitle($0, option: "--blocked-ae") })
        }
        var destinations: [String: DestinationAE] = [:]
        for (name, dest) in knownDestinations {
            let key = try ServerProtocol.validatedAETitle(name, option: "--move-destination")
            let title = try ServerProtocol.validatedAETitle(dest.aeTitle, option: "--move-destination")
            destinations[key] = DestinationAE(host: dest.host, port: dest.port, aeTitle: title)
        }
        return ServerConfiguration(
            aeTitle: ae,
            port: port,
            dataDirectory: dataDirectory,
            databaseURL: databaseURL,
            maxConcurrentConnections: maxConcurrentConnections,
            maxPDUSize: maxPDUSize,
            allowedCallingAETitles: allowed,
            blockedCallingAETitles: blocked,
            enableTLS: enableTLS,
            verbose: verbose,
            knownDestinations: destinations
        )
    }

    /// Resolves a C-MOVE Move Destination (0000,0600).
    ///
    /// A configured destination (`knownDestinations`, `--move-destination`) or, as before, a
    /// value of the form "host:port:AE"; nil when the AE is unknown, which the C-MOVE SCP
    /// answers with A801 "Refused: Move Destination unknown" (PS3.4 Table C.4-2).
    public func moveDestination(for destination: String) -> DestinationAE? {
        let trimmed = destination.trimmingCharacters(in: CharacterSet(charactersIn: " "))
        if let known = knownDestinations[trimmed] {
            return known
        }
        let components = trimmed.split(separator: ":")
        if components.count == 3, !components[0].isEmpty, let port = UInt16(components[1]), !components[2].isEmpty {
            return DestinationAE(host: String(components[0]), port: port, aeTitle: String(components[2]))
        }
        return nil
    }

    /// Parses a `--move-destination` value "AE=host:port".
    public static func parseDestination(_ spec: String) throws -> (String, DestinationAE) {
        let pair = spec.split(separator: "=", maxSplits: 1).map(String.init)
        let address = pair.count == 2 ? pair[1].split(separator: ":").map(String.init) : []
        guard pair.count == 2, address.count == 2, !address[0].isEmpty, let port = UInt16(address[1]) else {
            throw ServerError.invalidConfiguration("--move-destination '\(spec)' must be AE=host:port")
        }
        let ae = try ServerProtocol.validatedAETitle(pair[0], option: "--move-destination")
        return (ae, DestinationAE(host: address[0], port: port, aeTitle: ae))
    }
    
    /// Save configuration to a JSON file
    public func save(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: path))
    }
}

/// Destination AE configuration for C-MOVE operations
public struct DestinationAE: Sendable, Codable, Hashable {
    public let host: String
    public let port: UInt16
    public let aeTitle: String
    
    public init(host: String, port: UInt16, aeTitle: String) {
        self.host = host
        self.port = port
        self.aeTitle = aeTitle
    }
}

/// Errors that can occur during server operation
public enum ServerError: Error, CustomStringConvertible {
    case invalidConfiguration(String)
    case serverNotRunning
    case portInUse(UInt16)
    case databaseError(String)
    case storageError(String)
    
    public var description: String {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .serverNotRunning:
            return "Server is not running"
        case .portInUse(let port):
            return "Port \(port) is already in use"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .storageError(let message):
            return "Storage error: \(message)"
        }
    }
}
