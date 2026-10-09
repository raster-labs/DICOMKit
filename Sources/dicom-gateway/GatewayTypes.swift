// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (protocol, mode and error enums)
import Foundation

// MARK: - Protocol Types

enum ProtocolType: String, CaseIterable {
    case hl7v2 = "hl7"
    case fhir = "fhir"
    case dicom = "dicom"
}

// MARK: - Gateway Errors

enum GatewayError: Error, CustomStringConvertible {
    case invalidInput(String)
    case invalidProtocol(String)
    case parsingFailed(String)
    case conversionFailed(String)
    case networkError(String)
    case notImplemented(String)
    case invalidConfiguration(String)
    
    var description: String {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .invalidProtocol(let message):
            return "Invalid protocol: \(message)"
        case .parsingFailed(let message):
            return "Parsing failed: \(message)"
        case .conversionFailed(let message):
            return "Conversion failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .notImplemented(let message):
            return "Not implemented: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        }
    }
}

// MARK: - Gateway Mode

enum GatewayMode: String, CaseIterable {
    case convert = "convert"
    case listen = "listen"
    case forward = "forward"
    case bidirectional = "bidirectional"
    case batch = "batch"
}

// MARK: - Mapping Configuration

struct MappingConfiguration {
    var customMappings: [String: String]
    var includePrivateTags: Bool
    var handleMissingFields: MissingFieldBehavior
    
    enum MissingFieldBehavior: String, CaseIterable {
        case error = "error"
        case warn = "warn"
        case skip = "skip"
        case useDefault = "default"
    }
    
    init(
        customMappings: [String: String] = [:],
        includePrivateTags: Bool = false,
        handleMissingFields: MissingFieldBehavior = .useDefault
    ) {
        self.customMappings = customMappings
        self.includePrivateTags = includePrivateTags
        self.handleMissingFields = handleMissingFields
    }
}
