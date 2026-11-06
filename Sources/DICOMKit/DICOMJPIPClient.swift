// NEMA-verified: 2026a, checked 2026-09-29 — JPIP Referenced transfer syntax UIDs match PS3.6 2026a Table A-1; the JPIP URI is read from Pixel Data Provider URL (0028,7FE0), VR UR (PS3.6 Table 6-1), and Pixel Data is treated as absent per PS3.5 2026a A.6/A.7 (P-JPIP)
// DICOMJPIPClient.swift
// DICOMKit — Phase 6: JPIP Streaming

import Foundation
import DICOMCore

// MARK: - DICOMJPIPRegion

/// A rectangular region of interest for JPIP decoding.
public struct DICOMJPIPRegion: Sendable {
    /// X offset in pixels from the top-left corner.
    public var x: Int
    /// Y offset in pixels from the top-left corner.
    public var y: Int
    /// Region width in pixels.
    public var width: Int
    /// Region height in pixels.
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - DICOMJPIPQuality

/// Describes how much of a JPIP image has been retrieved.
public enum DICOMJPIPQuality: Sendable {
    /// Retrieve all quality layers (full quality).
    case full
    /// Retrieve only the first N quality layers.
    case layers(Int)
    /// Retrieve up to a specified resolution level (0 = full, higher = lower res).
    case resolutionLevel(Int)
}

// MARK: - DICOMJPIPError

/// Errors thrown by ``DICOMJPIPClient``.
public enum DICOMJPIPError: Error, Sendable, CustomStringConvertible {
    /// The transfer syntax stored in the DICOM dataset is not a JPIP reference.
    case notAJPIPTransferSyntax(String)
    /// Pixel Data Provider URL (0028,7FE0) is missing or empty.
    ///
    /// PS3.5 A.6: "Pixel Data (7FE0,0010) shall not be present, but rather Pixel
    /// Data shall be referenced via Data Element (0028,7FE0) Pixel Data Provider URL".
    case missingPixelDataProviderURL
    /// Superseded: JPIP objects never carried the URI in Pixel Data (7FE0,0010).
    @available(*, deprecated, renamed: "missingPixelDataProviderURL")
    case missingPixelData
    /// Pixel Data Provider URL (0028,7FE0) does not contain a valid URI string.
    case invalidJPIPURI(String)
    /// The JPIP server returned an unexpected response.
    case serverError(Int, String)
    /// JPIP module is not available (compiled without JPIP support).
    case jpipModuleUnavailable
    /// JPIP retrieval is deferred pending `SwiftJ2K` 12.2.0 (`SwiftJ2KJPIP` qualification).
    case retrievalUnavailable

    public var description: String {
        switch self {
        case .notAJPIPTransferSyntax(let uid):
            return "Transfer syntax \(uid) is not a JPIP reference syntax"
        case .missingPixelDataProviderURL, .missingPixelData:
            return "DICOM dataset has no Pixel Data Provider URL (0028,7FE0) element"
        case .invalidJPIPURI(let raw):
            return "Pixel Data Provider URL (0028,7FE0) does not contain a valid JPIP URI: \(raw)"
        case .serverError(let code, let detail):
            return "JPIP server error \(code): \(detail)"
        case .jpipModuleUnavailable:
            return "JPIP module is not available in this build"
        case .retrievalUnavailable:
            return """
                JPIP retrieval is deferred pending SwiftJ2K 12.2.0 (SwiftJ2KJPIP qualification). \
                Transfer-syntax detection and JPIP URI extraction work; fetching pixel data is deferred.
                """
        }
    }
}

// MARK: - DICOMJPIPImage

/// A decoded DICOM image retrieved via JPIP.
public struct DICOMJPIPImage: Sendable {
    /// Raw pixel bytes (decoded from the JPEG 2000 codestream).
    public let pixelData: Data
    /// Image width in pixels.
    public let width: Int
    /// Image height in pixels.
    public let height: Int
    /// Number of components (channels).
    public let components: Int
    /// Bits per component.
    public let bitDepth: Int
    /// JPIP URI that was used to retrieve this image.
    public let sourceURI: URL
    /// The number of quality layers that were fetched (0 = unknown).
    public let qualityLayers: Int

    public init(pixelData: Data, width: Int, height: Int, components: Int, bitDepth: Int,
                sourceURI: URL, qualityLayers: Int) {
        self.pixelData = pixelData
        self.width = width
        self.height = height
        self.components = components
        self.bitDepth = bitDepth
        self.sourceURI = sourceURI
        self.qualityLayers = qualityLayers
    }
}

// MARK: - DICOMJPIPClient

/// A high-level client for retrieving DICOM images from a JPIP server.
///
/// ## Retrieval is currently deferred
///
/// > Warning: The four retrieval methods (`fetchImage`, `fetchRegion`,
/// > `fetchProgressiveQuality`, `fetchResolutionLevel`) are marked
/// > `@available(*, unavailable)` pending `SwiftJ2K` 12.2.0 (`SwiftJ2KJPIP` qualification).
/// > Transfer-syntax detection and extracting the target URI from
/// > Pixel Data Provider URL (0028,7FE0) remain active.
public actor DICOMJPIPClient {

    /// The JPIP server base URL.
    public nonisolated let serverURL: URL

    /// Creates a new DICOM JPIP client.
    ///
    /// - Parameter serverURL: The base URL of the JPIP server (e.g., `http://pacs.example.com:8080`).
    public init(serverURL: URL) {
        self.serverURL = serverURL
    }

    // MARK: - Image Retrieval (Deferred)

    /// Fetches the full DICOM image from a JPIP server.
    @available(*, unavailable, message: "JPIP retrieval is deferred pending SwiftJ2K 12.2.0 (SwiftJ2KJPIP qualification). Transfer-syntax detection and DICOMJPIPClient.jpipURI(from:transferSyntaxUID:) still work.")
    public func fetchImage(jpipURI: URL) async throws -> DICOMJPIPImage {
        throw DICOMJPIPError.retrievalUnavailable
    }

    /// Fetches a region of interest from a JPIP server.
    @available(*, unavailable, message: "JPIP retrieval is deferred pending SwiftJ2K 12.2.0 (SwiftJ2KJPIP qualification). Transfer-syntax detection and DICOMJPIPClient.jpipURI(from:transferSyntaxUID:) still work.")
    public func fetchRegion(
        jpipURI: URL,
        region: DICOMJPIPRegion,
        quality: DICOMJPIPQuality = .full
    ) async throws -> DICOMJPIPImage {
        throw DICOMJPIPError.retrievalUnavailable
    }

    /// Fetches a progressive quality preview.
    @available(*, unavailable, message: "JPIP retrieval is deferred pending SwiftJ2K 12.2.0 (SwiftJ2KJPIP qualification). Transfer-syntax detection and DICOMJPIPClient.jpipURI(from:transferSyntaxUID:) still work.")
    public func fetchProgressiveQuality(jpipURI: URL, layers: Int) async throws -> DICOMJPIPImage {
        throw DICOMJPIPError.retrievalUnavailable
    }

    /// Fetches the image at a specific resolution level.
    @available(*, unavailable, message: "JPIP retrieval is deferred pending SwiftJ2K 12.2.0 (SwiftJ2KJPIP qualification). Transfer-syntax detection and DICOMJPIPClient.jpipURI(from:transferSyntaxUID:) still work.")
    public func fetchResolutionLevel(jpipURI: URL, level: Int, layers: Int? = nil) async throws -> DICOMJPIPImage {
        throw DICOMJPIPError.retrievalUnavailable
    }

    /// Closes the JPIP connection and frees server-side resources.
    public func close() async throws {}

    // MARK: - DICOM Integration

    /// Extracts the JPIP URI from a DICOM dataset's Pixel Data Provider URL (0028,7FE0).
    ///
    /// PS3.5 A.6 (JPIP Referenced) and A.7 (JPIP Referenced Deflate): "Pixel Data
    /// (7FE0,0010) shall not be present, but rather Pixel Data shall be referenced
    /// via Data Element (0028,7FE0) Pixel Data Provider URL". The element has VR UR
    /// (PS3.6 Table 6-1). A Pixel Data element, if one is nevertheless present, is
    /// treated as absent: it is never read for the URI and never reported as one.
    public static func jpipURI(from dataset: DataSet, transferSyntaxUID: String) throws -> URL {
        guard TransferSyntax.from(uid: transferSyntaxUID)?.isJPIP == true else {
            throw DICOMJPIPError.notAJPIPTransferSyntax(transferSyntaxUID)
        }
        guard let providerElement = dataset[Tag.pixelDataProviderURL] else {
            throw DICOMJPIPError.missingPixelDataProviderURL
        }
        let rawBytes = providerElement.valueData
        guard let uriString = String(data: rawBytes, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw DICOMJPIPError.invalidJPIPURI("<binary>")
        }
        guard !uriString.isEmpty else {
            throw DICOMJPIPError.missingPixelDataProviderURL
        }
        guard let url = URL(string: uriString) else {
            throw DICOMJPIPError.invalidJPIPURI(uriString)
        }
        return url
    }
}
