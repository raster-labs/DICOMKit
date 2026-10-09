// NEMA-verified: 2026a, checked 2026-09-29 — JPIP Referenced transfer syntax UIDs match PS3.6 2026a Table A-1; the JPIP URI is read from Pixel Data Provider URL (0028,7FE0), VR UR (PS3.6 Table 6-1), and Pixel Data is treated as absent per PS3.5 2026a A.6/A.7 (P-JPIP)
// DICOMJPIPClient.swift
// DICOMKit — Phase 6: JPIP Streaming

import Foundation
import DICOMCore

#if canImport(JPIP)
import JPIP
import J2KCore
#endif

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
    /// JPIP retrieval is not implemented in the pinned upstream codec module.
    ///
    /// Distinct from ``jpipModuleUnavailable``: the module *is* present and linked,
    /// but every request entry point in J2KSwift's `JPIP` (11.0.2) throws
    /// `notImplemented`, so no bytes can be retrieved. See `RESEARCH_ADOPTION_PLAN.md`
    /// finding F1.
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
                JPIP retrieval is not available: the pinned J2KSwift JPIP module (11.0.2) \
                has no implemented request path. Transfer-syntax detection and JPIP URI \
                extraction work; fetching pixel data does not.
                """
        }
    }
}

// MARK: - J2KImage → DICOMJPIPImage conversion

#if canImport(JPIP)
extension J2KImage {
    /// Converts a decoded J2KImage into a ``DICOMJPIPImage`` by interleaving
    /// component data into a single flat pixel buffer.
    ///
    /// For a single-component (grayscale) image the component's `data` bytes
    /// are used directly.  For multi-component images the component planes are
    /// interleaved sample-by-sample (RGBRGB… ordering).
    func toDICOMJPIPImage(sourceURI: URL, qualityLayers: Int) -> DICOMJPIPImage {
        let componentCount = components.count
        let pixelData: Data
        if componentCount == 1 {
            pixelData = components[0].data
        } else {
            // Interleave component planes into a packed pixel buffer.
            let samplesPerComponent = components.first.map { $0.data.count } ?? 0
            var buffer = Data(capacity: samplesPerComponent * componentCount)
            for sampleIndex in 0..<samplesPerComponent {
                for component in components {
                    if sampleIndex < component.data.count {
                        buffer.append(component.data[sampleIndex])
                    }
                }
            }
            pixelData = buffer
        }
        let bitDepth = components.first?.bitDepth ?? 8
        return DICOMJPIPImage(
            pixelData: pixelData,
            width: width,
            height: height,
            components: componentCount,
            bitDepth: bitDepth,
            sourceURI: sourceURI,
            qualityLayers: qualityLayers
        )
    }
}
#endif

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
/// ``DICOMJPIPClient`` wraps J2KSwift's ``JPIPClient`` and maps DICOM WADO-URI
/// JPIP reference transfer syntaxes (`1.2.840.10008.1.2.4.94` and `.4.95`) to
/// interactive progressive image requests.
///
/// ## Retrieval is currently unavailable
///
/// > Warning: The four retrieval methods (`fetchImage`, `fetchRegion`,
/// > `fetchProgressiveQuality`, `fetchResolutionLevel`) are marked
/// > `@available(*, unavailable)`. Every request entry point in the pinned upstream
/// > J2KSwift `JPIP` module (11.0.2) throws `notImplemented`, so no pixel data can be
/// > retrieved. They are annotated rather than deleted so the API shape survives for
/// > when upstream lands. Tracked as finding F1 in `RESEARCH_ADOPTION_PLAN.md`.
///
/// ## What does work
///
/// Recognising the JPIP transfer syntaxes and extracting the target URI from
/// Pixel Data Provider URL (0028,7FE0) — PS3.5 A.6 forbids Pixel Data itself:
///
/// ```swift
/// let uri = try DICOMJPIPClient.jpipURI(
///     from: file.dataSet,
///     transferSyntaxUID: file.fileMetaInformation.string(for: .transferSyntaxUID) ?? ""
/// )
/// ```
///
/// ## JPIP Transfer Syntaxes
///
/// | UID | Name |
/// |-----|------|
/// | `1.2.840.10008.1.2.4.94` | JPIP Referenced |
/// | `1.2.840.10008.1.2.4.95` | JPIP Referenced Deflate |
public actor DICOMJPIPClient {

    /// The JPIP server base URL.
    public nonisolated let serverURL: URL

    #if canImport(JPIP)
    private let jpipClient: JPIPClient
    #endif

    /// Creates a new DICOM JPIP client.
    ///
    /// - Parameter serverURL: The base URL of the JPIP server (e.g., `http://pacs.example.com:8080`).
    public init(serverURL: URL) {
        self.serverURL = serverURL
        #if canImport(JPIP)
        self.jpipClient = JPIPClient(serverURL: serverURL)
        #endif
    }

    // MARK: - Image Retrieval

    /// Fetches the full DICOM image from a JPIP server.
    ///
    /// - Parameter jpipURI: The JPIP target URI extracted from the DICOM Pixel Data element.
    /// - Returns: A ``DICOMJPIPImage`` containing decoded pixel data.
    /// - Throws: ``DICOMJPIPError`` if retrieval or decoding fails.
    @available(*, unavailable, message: "JPIP retrieval is not implemented in the pinned J2KSwift JPIP module (11.0.2) — every upstream request path throws notImplemented. Transfer-syntax detection and DICOMJPIPClient.jpipURI(from:transferSyntaxUID:) still work. Tracked as F1 in RESEARCH_ADOPTION_PLAN.md.")
    public func fetchImage(jpipURI: URL) async throws -> DICOMJPIPImage {
        #if canImport(JPIP)
        let imageID = jpipURI.lastPathComponent
        let j2kImage = try await jpipClient.requestImage(imageID: imageID)
        return j2kImage.toDICOMJPIPImage(sourceURI: jpipURI, qualityLayers: 0)
        #else
        throw DICOMJPIPError.jpipModuleUnavailable
        #endif
    }

    /// Fetches a region of interest from a JPIP server.
    ///
    /// - Parameters:
    ///   - jpipURI: The JPIP target URI.
    ///   - region: The rectangular region to retrieve.
    ///   - quality: How many quality layers to fetch. Defaults to `.full`.
    /// - Returns: A ``DICOMJPIPImage`` for the requested region.
    @available(*, unavailable, message: "JPIP retrieval is not implemented in the pinned J2KSwift JPIP module (11.0.2) — every upstream request path throws notImplemented. Transfer-syntax detection and DICOMJPIPClient.jpipURI(from:transferSyntaxUID:) still work. Tracked as F1 in RESEARCH_ADOPTION_PLAN.md.")
    public func fetchRegion(
        jpipURI: URL,
        region: DICOMJPIPRegion,
        quality: DICOMJPIPQuality = .full
    ) async throws -> DICOMJPIPImage {
        #if canImport(JPIP)
        let imageID = jpipURI.lastPathComponent
        // NOTE: the upstream `requestRegion` takes no quality argument, so `quality` is
        // not yet honoured on the wire. Reporting `quality`'s layer count here would
        // label the result with a fidelity that was never requested — §12 requires the
        // refinement state to be truthful, so report 0 ("unknown") until the upstream
        // API carries the layer limit.
        let j2kImage = try await jpipClient.requestRegion(
            imageID: imageID,
            region: (x: region.x, y: region.y, width: region.width, height: region.height)
        )
        return j2kImage.toDICOMJPIPImage(sourceURI: jpipURI, qualityLayers: 0)
        #else
        throw DICOMJPIPError.jpipModuleUnavailable
        #endif
    }

    /// Fetches a progressive quality preview.
    ///
    /// Use this to quickly display a low-quality thumbnail before fetching higher quality layers.
    ///
    /// - Parameters:
    ///   - jpipURI: The JPIP target URI.
    ///   - layers: Number of quality layers to retrieve (1 = fastest/lowest quality).
    /// - Returns: A ``DICOMJPIPImage`` at the requested quality level.
    @available(*, unavailable, message: "JPIP retrieval is not implemented in the pinned J2KSwift JPIP module (11.0.2) — every upstream request path throws notImplemented. Transfer-syntax detection and DICOMJPIPClient.jpipURI(from:transferSyntaxUID:) still work. Tracked as F1 in RESEARCH_ADOPTION_PLAN.md.")
    public func fetchProgressiveQuality(jpipURI: URL, layers: Int) async throws -> DICOMJPIPImage {
        #if canImport(JPIP)
        let imageID = jpipURI.lastPathComponent
        let j2kImage = try await jpipClient.requestProgressiveQuality(imageID: imageID, upToLayers: layers)
        return j2kImage.toDICOMJPIPImage(sourceURI: jpipURI, qualityLayers: layers)
        #else
        throw DICOMJPIPError.jpipModuleUnavailable
        #endif
    }

    /// Fetches the image at a specific resolution level.
    ///
    /// Level 0 is full resolution; each subsequent level halves the resolution.
    ///
    /// - Parameters:
    ///   - jpipURI: The JPIP target URI.
    ///   - level: Resolution level (0 = full).
    ///   - layers: Optional quality layer limit.
    /// - Returns: A ``DICOMJPIPImage`` at the requested resolution.
    @available(*, unavailable, message: "JPIP retrieval is not implemented in the pinned J2KSwift JPIP module (11.0.2) — every upstream request path throws notImplemented. Transfer-syntax detection and DICOMJPIPClient.jpipURI(from:transferSyntaxUID:) still work. Tracked as F1 in RESEARCH_ADOPTION_PLAN.md.")
    public func fetchResolutionLevel(jpipURI: URL, level: Int, layers: Int? = nil) async throws -> DICOMJPIPImage {
        #if canImport(JPIP)
        let imageID = jpipURI.lastPathComponent
        let j2kImage = try await jpipClient.requestResolutionLevel(imageID: imageID, level: level, layers: layers)
        return j2kImage.toDICOMJPIPImage(sourceURI: jpipURI, qualityLayers: layers ?? 0)
        #else
        throw DICOMJPIPError.jpipModuleUnavailable
        #endif
    }

    /// Closes the JPIP connection and frees server-side resources.
    public func close() async throws {
        #if canImport(JPIP)
        try await jpipClient.close()
        #endif
    }

    // MARK: - DICOM Integration

    /// Extracts the JPIP URI from a DICOM dataset's Pixel Data Provider URL (0028,7FE0).
    ///
    /// PS3.5 A.6 (JPIP Referenced) and A.7 (JPIP Referenced Deflate): "Pixel Data
    /// (7FE0,0010) shall not be present, but rather Pixel Data shall be referenced
    /// via Data Element (0028,7FE0) Pixel Data Provider URL". The element has VR UR
    /// (PS3.6 Table 6-1). A Pixel Data element, if one is nevertheless present, is
    /// treated as absent: it is never read for the URI and never reported as one.
    ///
    /// - Parameters:
    ///   - dataset: The DICOM dataset.
    ///   - transferSyntaxUID: The transfer syntax UID of the dataset.
    /// - Returns: The parsed JPIP server URI.
    /// - Throws: ``DICOMJPIPError/notAJPIPTransferSyntax(_:)`` if the transfer syntax is
    ///   not JPIP, ``DICOMJPIPError/missingPixelDataProviderURL`` if (0028,7FE0) is absent
    ///   or empty, ``DICOMJPIPError/invalidJPIPURI(_:)`` if it is not a URL.
    public static func jpipURI(from dataset: DataSet, transferSyntaxUID: String) throws -> URL {
        guard TransferSyntax.from(uid: transferSyntaxUID)?.isJPIP == true else {
            throw DICOMJPIPError.notAJPIPTransferSyntax(transferSyntaxUID)
        }
        guard let providerElement = dataset[Tag.pixelDataProviderURL] else {
            throw DICOMJPIPError.missingPixelDataProviderURL
        }
        // UR values are UTF-8/ASCII strings; trailing space padding is permitted.
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
