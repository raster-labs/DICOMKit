// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (S3/GCS/Azure REST plumbing; objects are sent as application/octet-stream, not the PS3.18 application/dicom media type); Scripts/diff_cli.py: 0 UID, tag or code literals
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif
@preconcurrency import AWSS3
import AWSClientRuntime
import ClientRuntime
import Smithy

// MARK: - Cloud Provider Protocol
protocol CloudProviderProtocol: Actor {
    func upload(data: Data, to cloudURL: CloudURL, metadata: [String: String], encryption: EncryptionType) async throws
    func download(from cloudURL: CloudURL) async throws -> Data
    func list(cloudURL: CloudURL, recursive: Bool) async throws -> [CloudObject]
    func delete(cloudURL: CloudURL) async throws
    func exists(cloudURL: CloudURL) async throws -> Bool
}

// MARK: - Cloud Provider Factory
struct CloudProvider {
    static func create(for cloudURL: CloudURL, endpoint: String?, region: String?) async throws -> any CloudProviderProtocol {
        switch cloudURL.provider {
        case .s3:
            return try await S3Provider(endpoint: endpoint, region: region)
        case .gcs:
            return try await GCSProvider(endpoint: endpoint)
        case .azure:
            return try await AzureProvider(endpoint: endpoint)
        }
    }
}

// MARK: - S3 Provider
actor S3Provider: CloudProviderProtocol {
    private let client: S3Client
    
    init(endpoint: String?, region: String?) async throws {
        // Configure the S3 client
        do {
            let config = try await S3Client.S3ClientConfiguration(
                region: region
            )
            
            // If custom endpoint is provided, configure it
            if let endpoint = endpoint {
                config.endpoint = endpoint
            }
            
            self.client = S3Client(config: config)
        } catch {
            throw CloudError.authenticationFailed("Failed to create S3 client: \(error.localizedDescription)")
        }
    }
    
    func upload(data: Data, to cloudURL: CloudURL, metadata: [String: String], encryption: EncryptionType) async throws {
        do {
            // Convert Data to ByteStream
            let byteStream = ByteStream.data(data)
            
            // Build metadata for S3
            var s3Metadata: [String: String]?
            if !metadata.isEmpty {
                s3Metadata = metadata
            }
            
            // Configure encryption
            var serverSideEncryption: S3ClientTypes.ServerSideEncryption?
            if case .serverSide = encryption {
                serverSideEncryption = .aes256
            }
            
            // Create the PutObject request
            let input = PutObjectInput(
                body: byteStream,
                bucket: cloudURL.bucket,
                key: cloudURL.key,
                metadata: s3Metadata,
                serverSideEncryption: serverSideEncryption
            )
            
            _ = try await client.putObject(input: input)
        } catch let error as CloudError {
            throw error
        } catch {
            throw CloudError.operationFailed("Upload failed: \(error.localizedDescription)")
        }
    }
    
    func download(from cloudURL: CloudURL) async throws -> Data {
        do {
            let input = GetObjectInput(
                bucket: cloudURL.bucket,
                key: cloudURL.key
            )
            
            let output = try await client.getObject(input: input)
            
            guard let body = output.body else {
                throw CloudError.notFound("Object body is empty: \(cloudURL.key)")
            }
            
            // Convert ByteStream to Data
            guard let data = try await body.readData() else {
                throw CloudError.operationFailed("Failed to read object data: \(cloudURL.key)")
            }
            return data
        } catch let error as CloudError {
            throw error
        } catch {
            throw CloudError.operationFailed("Download failed: \(error.localizedDescription)")
        }
    }
    
    func list(cloudURL: CloudURL, recursive: Bool) async throws -> [CloudObject] {
        var objects: [CloudObject] = []
        var continuationToken: String?
        
        do {
            repeat {
                let input = ListObjectsV2Input(
                    bucket: cloudURL.bucket,
                    continuationToken: continuationToken,
                    delimiter: recursive ? nil : "/",
                    prefix: cloudURL.key.isEmpty ? nil : cloudURL.key
                )
                
                let output = try await client.listObjectsV2(input: input)
                
                if let contents = output.contents {
                    for s3Object in contents {
                        guard let key = s3Object.key else { continue }
                        
                        objects.append(CloudObject(
                            key: key,
                            size: Int(s3Object.size ?? 0),
                            lastModified: s3Object.lastModified ?? Date(),
                            metadata: [:]
                        ))
                    }
                }
                
                continuationToken = output.nextContinuationToken
            } while continuationToken != nil
            
            return objects
        } catch let error as CloudError {
            throw error
        } catch {
            throw CloudError.operationFailed("List failed: \(error.localizedDescription)")
        }
    }
    
    func delete(cloudURL: CloudURL) async throws {
        do {
            let input = DeleteObjectInput(
                bucket: cloudURL.bucket,
                key: cloudURL.key
            )
            
            _ = try await client.deleteObject(input: input)
        } catch let error as CloudError {
            throw error
        } catch {
            throw CloudError.operationFailed("Delete failed: \(error.localizedDescription)")
        }
    }
    
    func exists(cloudURL: CloudURL) async throws -> Bool {
        do {
            let input = HeadObjectInput(
                bucket: cloudURL.bucket,
                key: cloudURL.key
            )
            
            _ = try await client.headObject(input: input)
            return true
        } catch {
            // If HeadObject fails, the object doesn't exist
            return false
        }
    }
}

// MARK: - GCS Provider
actor GCSProvider: CloudProviderProtocol {
    private let endpoint: String
    private let session: URLSession
    
    init(endpoint: String?) async throws {
        self.endpoint = endpoint ?? "https://storage.googleapis.com"
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes for large files
        config.timeoutIntervalForResource = 3600 // 1 hour for very large files
        self.session = URLSession(configuration: config)
        
        // Verify credentials are available
        guard let credentialsPath = ProcessInfo.processInfo.environment["GOOGLE_APPLICATION_CREDENTIALS"] ??
              ProcessInfo.processInfo.environment["GCS_CREDENTIALS_PATH"] else {
            throw CloudError.authenticationFailed("""
                Google Cloud Storage credentials not found.
                Set GOOGLE_APPLICATION_CREDENTIALS or GCS_CREDENTIALS_PATH environment variable to your service account JSON file path.
                
                Example:
                  export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
                """)
        }
        
        guard FileManager.default.fileExists(atPath: credentialsPath) else {
            throw CloudError.authenticationFailed("Credentials file not found at: \(credentialsPath)")
        }
    }
    
    // Helper: Get OAuth2 access token from service account credentials
    private func getAccessToken() async throws -> String {
        guard let credentialsPath = ProcessInfo.processInfo.environment["GOOGLE_APPLICATION_CREDENTIALS"] ??
              ProcessInfo.processInfo.environment["GCS_CREDENTIALS_PATH"] else {
            throw CloudError.authenticationFailed("GCS credentials not configured")
        }
        
        // Read service account JSON
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: credentialsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let _ = json["private_key"] as? String,
              let _ = json["client_email"] as? String else {
            throw CloudError.authenticationFailed("Failed to parse service account credentials")
        }
        
        // Create JWT token (simplified - in production use a JWT library)
        // For now, we'll use a placeholder that indicates the implementation needs external JWT support
        // In a real implementation, you would use a library like SwiftJWT
        throw CloudError.notImplemented("""
            GCS OAuth2 authentication requires JWT signing capability.
            
            To complete GCS integration, you need to:
            1. Add a JWT library dependency (e.g., SwiftJWT) to Package.swift
            2. Implement JWT signing with the service account private key
            3. Exchange the JWT for an OAuth2 access token
            
            For now, use gcloud CLI to obtain an access token and set GCS_ACCESS_TOKEN environment variable.
            """)
    }
    
    func upload(data: Data, to cloudURL: CloudURL, metadata: [String: String], encryption: EncryptionType) async throws {
        // For initial implementation, require manual access token
        guard let accessToken = ProcessInfo.processInfo.environment["GCS_ACCESS_TOKEN"] else {
            throw CloudError.authenticationFailed("""
                GCS_ACCESS_TOKEN environment variable not set.
                
                Obtain a token with: gcloud auth print-access-token
                Then: export GCS_ACCESS_TOKEN=$(gcloud auth print-access-token)
                """)
        }
        
        // Construct URL
        let urlString = "\(endpoint)/upload/storage/v1/b/\(cloudURL.bucket)/o?uploadType=media&name=\(cloudURL.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cloudURL.key)"
        
        guard let url = URL(string: urlString) else {
            throw CloudError.invalidURL("Failed to construct GCS upload URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        // Add metadata as custom headers
        for (key, value) in metadata {
            request.setValue(value, forHTTPHeaderField: "x-goog-meta-\(key)")
        }
        
        // Handle encryption
        if case .serverSide = encryption {
            request.setValue("AES256", forHTTPHeaderField: "x-goog-encryption-algorithm")
        }
        
        let (responseData, response) = try await session.upload(for: request, from: data)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudError.operationFailed("Invalid response type")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw CloudError.operationFailed("GCS upload failed (HTTP \(httpResponse.statusCode)): \(errorMessage)")
        }
    }
    
    func download(from cloudURL: CloudURL) async throws -> Data {
        guard let accessToken = ProcessInfo.processInfo.environment["GCS_ACCESS_TOKEN"] else {
            throw CloudError.authenticationFailed("GCS_ACCESS_TOKEN environment variable not set")
        }
        
        let urlString = "\(endpoint)/storage/v1/b/\(cloudURL.bucket)/o/\(cloudURL.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cloudURL.key)?alt=media"
        
        guard let url = URL(string: urlString) else {
            throw CloudError.invalidURL("Failed to construct GCS download URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudError.operationFailed("Invalid response type")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw CloudError.notFound("Object not found: \(cloudURL.key)")
            }
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudError.operationFailed("GCS download failed (HTTP \(httpResponse.statusCode)): \(errorMessage)")
        }
        
        return data
    }
    
    func list(cloudURL: CloudURL, recursive: Bool) async throws -> [CloudObject] {
        guard let accessToken = ProcessInfo.processInfo.environment["GCS_ACCESS_TOKEN"] else {
            throw CloudError.authenticationFailed("GCS_ACCESS_TOKEN environment variable not set")
        }
        
        var objects: [CloudObject] = []
        var pageToken: String?
        
        repeat {
            var urlComponents = URLComponents(string: "\(endpoint)/storage/v1/b/\(cloudURL.bucket)/o")!
            var queryItems = [URLQueryItem]()
            
            if !cloudURL.key.isEmpty {
                queryItems.append(URLQueryItem(name: "prefix", value: cloudURL.key))
            }
            
            if !recursive {
                queryItems.append(URLQueryItem(name: "delimiter", value: "/"))
            }
            
            if let token = pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: token))
            }
            
            urlComponents.queryItems = queryItems
            
            guard let url = urlComponents.url else {
                throw CloudError.invalidURL("Failed to construct GCS list URL")
            }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudError.operationFailed("Invalid response type")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw CloudError.operationFailed("GCS list failed (HTTP \(httpResponse.statusCode)): \(errorMessage)")
            }
            
            // Parse JSON response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CloudError.operationFailed("Failed to parse GCS response")
            }
            
            if let items = json["items"] as? [[String: Any]] {
                for item in items {
                    guard let name = item["name"] as? String else { continue }
                    
                    let size = (item["size"] as? String).flatMap { Int($0) } ?? 0
                    
                    var lastModified = Date()
                    if let timeCreated = item["timeCreated"] as? String {
                        let formatter = ISO8601DateFormatter()
                        lastModified = formatter.date(from: timeCreated) ?? Date()
                    }
                    
                    let metadata = item["metadata"] as? [String: String] ?? [:]
                    
                    objects.append(CloudObject(
                        key: name,
                        size: size,
                        lastModified: lastModified,
                        metadata: metadata
                    ))
                }
            }
            
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil
        
        return objects
    }
    
    func delete(cloudURL: CloudURL) async throws {
        guard let accessToken = ProcessInfo.processInfo.environment["GCS_ACCESS_TOKEN"] else {
            throw CloudError.authenticationFailed("GCS_ACCESS_TOKEN environment variable not set")
        }
        
        let urlString = "\(endpoint)/storage/v1/b/\(cloudURL.bucket)/o/\(cloudURL.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cloudURL.key)"
        
        guard let url = URL(string: urlString) else {
            throw CloudError.invalidURL("Failed to construct GCS delete URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudError.operationFailed("Invalid response type")
        }
        
        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudError.operationFailed("GCS delete failed (HTTP \(httpResponse.statusCode)): \(errorMessage)")
        }
    }
    
    func exists(cloudURL: CloudURL) async throws -> Bool {
        guard let accessToken = ProcessInfo.processInfo.environment["GCS_ACCESS_TOKEN"] else {
            throw CloudError.authenticationFailed("GCS_ACCESS_TOKEN environment variable not set")
        }
        
        let urlString = "\(endpoint)/storage/v1/b/\(cloudURL.bucket)/o/\(cloudURL.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cloudURL.key)"
        
        guard let url = URL(string: urlString) else {
            throw CloudError.invalidURL("Failed to construct GCS exists URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200...299).contains(httpResponse.statusCode)
    }
}

// MARK: - Azure Provider
actor AzureProvider: CloudProviderProtocol {
    private let endpoint: String
    private let session: URLSession
    private let accountName: String
    
    init(endpoint: String?) async throws {
        // Parse account name from environment or use default endpoint
        guard let accountName = ProcessInfo.processInfo.environment["AZURE_STORAGE_ACCOUNT"] else {
            throw CloudError.authenticationFailed("""
                Azure Storage account not configured.
                Set AZURE_STORAGE_ACCOUNT environment variable to your storage account name.
                
                Example:
                  export AZURE_STORAGE_ACCOUNT=mystorageaccount
                  export AZURE_STORAGE_KEY=your-access-key
                """)
        }
        
        self.accountName = accountName
        self.endpoint = endpoint ?? "https://\(accountName).blob.core.windows.net"
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: config)
        
        // Verify credentials
        guard ProcessInfo.processInfo.environment["AZURE_STORAGE_KEY"] != nil ||
              ProcessInfo.processInfo.environment["AZURE_STORAGE_SAS_TOKEN"] != nil else {
            throw CloudError.authenticationFailed("""
                Azure Storage credentials not found.
                Set either:
                - AZURE_STORAGE_KEY (access key) or
                - AZURE_STORAGE_SAS_TOKEN (SAS token)
                """)
        }
    }
    
    // Helper: Generate Azure Storage authorization header
    private func createAuthorizationHeader(method: String, url: URL, contentLength: Int, contentType: String?, date: String) throws -> String {
        guard ProcessInfo.processInfo.environment["AZURE_STORAGE_KEY"] != nil else {
            throw CloudError.authenticationFailed("AZURE_STORAGE_KEY not set")
        }
        
        // For simplicity, this is a basic implementation
        // Full Azure Blob Storage Shared Key authentication requires proper string-to-sign construction
        // This would need HMAC-SHA256 signing
        
        // For now, throw an error indicating SAS token usage is required
        throw CloudError.notImplemented("""
            Azure Shared Key authentication requires HMAC-SHA256 signing.
            
            For now, use SAS token authentication:
            1. Generate a SAS token in Azure Portal
            2. Set AZURE_STORAGE_SAS_TOKEN environment variable
            
            Example:
              export AZURE_STORAGE_SAS_TOKEN="?sv=2021-06-08&ss=b&srt=sco&sp=rwdlac..."
            """)
    }
    
    func upload(data: Data, to cloudURL: CloudURL, metadata: [String: String], encryption: EncryptionType) async throws {
        // Check for SAS token (simpler auth method)
        guard let sasToken = ProcessInfo.processInfo.environment["AZURE_STORAGE_SAS_TOKEN"] else {
            throw CloudError.authenticationFailed("""
                AZURE_STORAGE_SAS_TOKEN not set.
                
                Generate a SAS token and export it:
                  export AZURE_STORAGE_SAS_TOKEN="?sv=..."
                """)
        }
        
        // Construct URL with SAS token
        let urlString = "\(endpoint)/\(cloudURL.bucket)/\(cloudURL.key)\(sasToken)"
        
        guard let url = URL(string: urlString) else {
            throw CloudError.invalidURL("Failed to construct Azure upload URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        request.setValue(ISO8601DateFormatter().string(from: Date()), forHTTPHeaderField: "x-ms-date")
        request.setValue("2021-06-08", forHTTPHeaderField: "x-ms-version")
        
        // Add metadata
        for (key, value) in metadata {
            request.setValue(value, forHTTPHeaderField: "x-ms-meta-\(key)")
        }
        
        // Handle encryption
        if case .serverSide = encryption {
            request.setValue("AES256", forHTTPHeaderField: "x-ms-server-side-encryption")
        }
        
        let (responseData, response) = try await session.upload(for: request, from: data)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudError.operationFailed("Invalid response type")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw CloudError.operationFailed("Azure upload failed (HTTP \(httpResponse.statusCode)): \(errorMessage)")
        }
    }
    
    func download(from cloudURL: CloudURL) async throws -> Data {
        guard let sasToken = ProcessInfo.processInfo.environment["AZURE_STORAGE_SAS_TOKEN"] else {
            throw CloudError.authenticationFailed("AZURE_STORAGE_SAS_TOKEN not set")
        }
        
        let urlString = "\(endpoint)/\(cloudURL.bucket)/\(cloudURL.key)\(sasToken)"
        
        guard let url = URL(string: urlString) else {
            throw CloudError.invalidURL("Failed to construct Azure download URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue(ISO8601DateFormatter().string(from: Date()), forHTTPHeaderField: "x-ms-date")
        request.setValue("2021-06-08", forHTTPHeaderField: "x-ms-version")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudError.operationFailed("Invalid response type")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw CloudError.notFound("Blob not found: \(cloudURL.key)")
            }
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudError.operationFailed("Azure download failed (HTTP \(httpResponse.statusCode)): \(errorMessage)")
        }
        
        return data
    }
    
    func list(cloudURL: CloudURL, recursive: Bool) async throws -> [CloudObject] {
        guard let sasToken = ProcessInfo.processInfo.environment["AZURE_STORAGE_SAS_TOKEN"] else {
            throw CloudError.authenticationFailed("AZURE_STORAGE_SAS_TOKEN not set")
        }
        
        var objects: [CloudObject] = []
        var marker: String?
        
        repeat {
            var urlComponents = URLComponents(string: "\(endpoint)/\(cloudURL.bucket)")!
            urlComponents.query = "restype=container&comp=list\(sasToken.hasPrefix("&") ? sasToken : "&" + sasToken.dropFirst())"
            
            if !cloudURL.key.isEmpty {
                urlComponents.query! += "&prefix=\(cloudURL.key)"
            }
            
            if !recursive {
                urlComponents.query! += "&delimiter=/"
            }
            
            if let m = marker {
                urlComponents.query! += "&marker=\(m)"
            }
            
            guard let url = urlComponents.url else {
                throw CloudError.invalidURL("Failed to construct Azure list URL")
            }
            
            var request = URLRequest(url: url)
            request.setValue(ISO8601DateFormatter().string(from: Date()), forHTTPHeaderField: "x-ms-date")
            request.setValue("2021-06-08", forHTTPHeaderField: "x-ms-version")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudError.operationFailed("Invalid response type")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw CloudError.operationFailed("Azure list failed (HTTP \(httpResponse.statusCode)): \(errorMessage)")
            }
            
            // Parse XML response
            let parser = AzureXMLParser()
            if let result = parser.parse(data: data) {
                objects.append(contentsOf: result.blobs)
                marker = result.nextMarker
            } else {
                marker = nil
            }
        } while marker != nil
        
        return objects
    }
    
    func delete(cloudURL: CloudURL) async throws {
        guard let sasToken = ProcessInfo.processInfo.environment["AZURE_STORAGE_SAS_TOKEN"] else {
            throw CloudError.authenticationFailed("AZURE_STORAGE_SAS_TOKEN not set")
        }
        
        let urlString = "\(endpoint)/\(cloudURL.bucket)/\(cloudURL.key)\(sasToken)"
        
        guard let url = URL(string: urlString) else {
            throw CloudError.invalidURL("Failed to construct Azure delete URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(ISO8601DateFormatter().string(from: Date()), forHTTPHeaderField: "x-ms-date")
        request.setValue("2021-06-08", forHTTPHeaderField: "x-ms-version")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudError.operationFailed("Invalid response type")
        }
        
        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudError.operationFailed("Azure delete failed (HTTP \(httpResponse.statusCode)): \(errorMessage)")
        }
    }
    
    func exists(cloudURL: CloudURL) async throws -> Bool {
        guard let sasToken = ProcessInfo.processInfo.environment["AZURE_STORAGE_SAS_TOKEN"] else {
            throw CloudError.authenticationFailed("AZURE_STORAGE_SAS_TOKEN not set")
        }
        
        let urlString = "\(endpoint)/\(cloudURL.bucket)/\(cloudURL.key)\(sasToken)"
        
        guard let url = URL(string: urlString) else {
            throw CloudError.invalidURL("Failed to construct Azure exists URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(ISO8601DateFormatter().string(from: Date()), forHTTPHeaderField: "x-ms-date")
        request.setValue("2021-06-08", forHTTPHeaderField: "x-ms-version")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200...299).contains(httpResponse.statusCode)
    }
}

// MARK: - Azure XML Parser Helper
private class AzureXMLParser: NSObject, XMLParserDelegate {
    struct ParseResult {
        var blobs: [CloudObject]
        var nextMarker: String?
    }
    
    private var result = ParseResult(blobs: [], nextMarker: nil)
    private var currentElement: String = ""
    private var currentName: String?
    private var currentSize: Int = 0
    private var currentLastModified: Date = Date()
    
    func parse(data: Data) -> ParseResult? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            return nil
        }
        return result
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        switch currentElement {
        case "Name":
            currentName = trimmed
        case "Content-Length":
            currentSize = Int(trimmed) ?? 0
        case "Last-Modified":
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            currentLastModified = formatter.date(from: trimmed) ?? Date()
        case "NextMarker":
            result.nextMarker = trimmed
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Blob", let name = currentName {
            result.blobs.append(CloudObject(
                key: name,
                size: currentSize,
                lastModified: currentLastModified,
                metadata: [:]
            ))
            currentName = nil
            currentSize = 0
        }
    }
}
