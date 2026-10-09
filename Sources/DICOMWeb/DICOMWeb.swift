// NEMA-verified: 2026a, checked 2026-09-28 — documentation only; the section citations checked against the PS3.18 2026a table of contents
/// DICOMWeb module
///
/// Provides DICOMweb functionality including DICOM JSON encoding/decoding,
/// multipart MIME handling, and HTTP client infrastructure.
///
/// This module implements the DICOMweb standard (PS3.18) for RESTful
/// DICOM communication over HTTP/HTTPS.
///
/// ## Key Components
///
/// - ``DICOMwebClient``: Client for WADO-RS, QIDO-RS, and STOW-RS operations
/// - ``DICOMJSONEncoder``: Encodes DICOM DataElements to JSON format
/// - ``DICOMJSONDecoder``: Decodes JSON to DICOM DataElements
/// - ``MultipartMIME``: Handles multipart/related messages
/// - ``HTTPClient``: HTTP client with retry and interceptor support
/// - ``DICOMwebConfiguration``: Configuration for DICOMweb clients
/// - ``DICOMwebURLBuilder``: URL construction utilities
/// - ``DICOMMediaType``: Media type definitions
/// - ``DICOMwebError``: Error types for DICOMweb operations
/// - ``STOWResponse``: Response type for STOW-RS store operations
///
/// ## Example Usage
///
/// ```swift
/// import DICOMWeb
/// import DICOMCore
///
/// // Configure client
/// let config = try DICOMwebConfiguration(
///     baseURLString: "https://pacs.example.com/dicom-web",
///     authentication: .bearer(token: "your-token")
/// )
///
/// // Create DICOMweb client
/// let client = DICOMwebClient(configuration: config)
///
/// // Retrieve a study (WADO-RS)
/// let result = try await client.retrieveStudy(studyUID: "1.2.3.4.5")
///
/// // Search for studies (QIDO-RS)
/// let query = QIDOQuery().modality("CT").studyDate(from: "20240101", to: "20241231")
/// let studies = try await client.searchStudies(query: query)
///
/// // Store instances (STOW-RS)
/// let response = try await client.storeInstances(instances: [dicomData1, dicomData2])
/// print("Stored: \(response.successCount), Failed: \(response.failureCount)")
///
/// // Encode data to JSON
/// let encoder = DICOMJSONEncoder()
/// let jsonData = try encoder.encode(elements)
///
/// // Decode JSON to elements
/// let decoder = DICOMJSONDecoder()
/// let elements = try decoder.decode(jsonData)
/// ```
///
/// ## References
///
/// - DICOM PS3.18 - Web Services
/// - DICOM PS3.18 Annex F - DICOM JSON Model
/// - DICOM PS3.18 Section 8.6.1.2 and 8.7.1 - Multipart payloads and media types
/// - DICOM PS3.18 Section 10.4 - Retrieve Transaction (WADO-RS)
/// - DICOM PS3.18 Section 10.5 - Store Transaction (STOW-RS)
/// - DICOM PS3.18 Section 10.6 - Search Transaction (QIDO-RS)
///
public enum DICOMWeb {
    /// The version of the DICOMWeb module
    public static let version = "0.8.4"
}

// Re-export DICOMCore types commonly used with DICOMWeb
@_exported import DICOMCore
