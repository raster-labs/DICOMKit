// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (cloud URL parsing, provider endpoints and error text); Scripts/diff_cli.py: 0 UID, tag or code literals
import Foundation

// MARK: - Cloud URL
struct CloudURL {
    let provider: CloudProviderType
    let bucket: String
    let key: String
    let endpoint: String?
    
    static func parse(_ urlString: String) throws -> CloudURL {
        guard let url = URL(string: urlString) else {
            throw CloudError.invalidURL("Invalid URL format: \(urlString)")
        }
        
        guard let scheme = url.scheme else {
            throw CloudError.invalidURL("Missing scheme in URL: \(urlString)")
        }
        
        let provider: CloudProviderType
        switch scheme {
        case "s3":
            provider = .s3
        case "gs":
            provider = .gcs
        case "azure":
            provider = .azure
        default:
            throw CloudError.unsupportedProvider("Unsupported URL scheme: \(scheme)")
        }
        
        guard let host = url.host else {
            throw CloudError.invalidURL("Missing bucket/container name in URL: \(urlString)")
        }
        
        let key = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        return CloudURL(provider: provider, bucket: host, key: key, endpoint: nil)
    }
    
    func with(key newKey: String) -> CloudURL {
        CloudURL(provider: provider, bucket: bucket, key: newKey, endpoint: endpoint)
    }
    
    var fullPath: String {
        "\(provider.schemePrefix)\(bucket)/\(key)"
    }
}

// MARK: - Cloud Provider Type
enum CloudProviderType: String {
    case s3
    case gcs
    case azure
    
    var schemePrefix: String {
        switch self {
        case .s3: return "s3://"
        case .gcs: return "gs://"
        case .azure: return "azure://"
        }
    }
    
    var defaultEndpoint: String {
        switch self {
        case .s3: return "s3.amazonaws.com"
        case .gcs: return "storage.googleapis.com"
        case .azure: return "blob.core.windows.net"
        }
    }
}

// MARK: - Cloud Object
struct CloudObject {
    let key: String
    let size: Int
    let lastModified: Date
    let metadata: [String: String]
}

// MARK: - Cloud Error
enum CloudError: Error, CustomStringConvertible {
    case invalidURL(String)
    case unsupportedProvider(String)
    case authenticationFailed(String)
    case networkError(String)
    case notFound(String)
    case permissionDenied(String)
    case operationFailed(String)
    case notImplemented(String)
    
    var description: String {
        switch self {
        case .invalidURL(let message):
            return "Invalid URL: \(message)"
        case .unsupportedProvider(let message):
            return "Unsupported provider: \(message)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .notFound(let message):
            return "Not found: \(message)"
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        case .operationFailed(let message):
            return "Operation failed: \(message)"
        case .notImplemented(let message):
            return "Not implemented: \(message)"
        }
    }
}
