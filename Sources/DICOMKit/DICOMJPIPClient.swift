// NEMA-verified: 2026a, checked 2026-09-29 — JPIP Referenced transfer syntax UIDs match PS3.6 2026a Table A-1; the JPIP URI is read from Pixel Data Provider URL (0028,7FE0), VR UR (PS3.6 Table 6-1), and Pixel Data is treated as absent per PS3.5 2026a A.6/A.7 (P-JPIP)
// DICOMJPIPClient.swift
// DICOMKit — Phase 6: JPIP Streaming (SwiftJ2KJPIP Contract API-13)

import Foundation
import DICOMCore
import SwiftJ2K
import SwiftJ2KJPIP

// MARK: - DICOMJPIPRegion

/// A rectangular region of interest for JPIP decoding.
public struct DICOMJPIPRegion: Sendable, Equatable {
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
public enum DICOMJPIPQuality: Sendable, Equatable {
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
    /// The JPIP server returned an unexpected response or transport error.
    case serverError(Int, String)
    /// JPIP module is not available (compiled without JPIP support).
    case jpipModuleUnavailable
    /// Retained compatibility error case when a JPIP endpoint refuses retrieval.
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
            return "JPIP retrieval is unavailable from the target endpoint"
        }
    }
}

// MARK: - DICOMJPIPImage

/// A decoded DICOM image retrieved via JPIP.
public struct DICOMJPIPImage: Sendable {
    /// Raw pixel bytes (decoded from the JPEG 2000 / HTJ2K codestream, little-endian).
    public let pixelData: Data
    /// Image width in pixels.
    public let width: Int
    /// Image height in pixels.
    public let height: Int
    /// Number of components (channels).
    public let components: Int
    /// Bits per component.
    public let bitDepth: Int
    /// Whether component samples are signed two's-complement integers.
    public let isSigned: Bool
    /// JPIP URI that was used to retrieve this image.
    public let sourceURI: URL
    /// The number of quality layers that were fetched (0 = all / unspecified).
    public let qualityLayers: Int

    public init(
        pixelData: Data,
        width: Int,
        height: Int,
        components: Int,
        bitDepth: Int,
        isSigned: Bool = false,
        sourceURI: URL,
        qualityLayers: Int
    ) {
        self.pixelData = pixelData
        self.width = width
        self.height = height
        self.components = components
        self.bitDepth = bitDepth
        self.isSigned = isSigned
        self.sourceURI = sourceURI
        self.qualityLayers = qualityLayers
    }
}

// MARK: - J2KImage → DICOMJPIPImage Conversion

extension J2KImage {
    /// Converts a decoded `J2KImage` into a ``DICOMJPIPImage`` by interleaving
    /// component planes into a packed little-endian sample buffer.
    func toDICOMJPIPImage(sourceURI: URL, qualityLayers: Int) -> DICOMJPIPImage {
        let componentCount = components.count
        let bitDepth = components.first?.bitDepth ?? 8
        let bytesPerSample = max(1, (bitDepth + 7) / 8)
        let pixelCount = width * height
        let pixelData: Data

        if componentCount <= 1 {
            pixelData = components.first?.data ?? Data()
        } else {
            var buffer = Data(count: pixelCount * componentCount * bytesPerSample)
            buffer.withUnsafeMutableBytes { dstRaw in
                guard let dst = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                for (compIdx, component) in components.enumerated() {
                    component.data.withUnsafeBytes { srcRaw in
                        guard let src = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                        let availablePixels = min(pixelCount, srcRaw.count / bytesPerSample)
                        for p in 0..<availablePixels {
                            let dstOffset = (p * componentCount + compIdx) * bytesPerSample
                            let srcOffset = p * bytesPerSample
                            for b in 0..<bytesPerSample {
                                dst[dstOffset + b] = src[srcOffset + b]
                            }
                        }
                    }
                }
            }
            pixelData = buffer
        }

        return DICOMJPIPImage(
            pixelData: pixelData,
            width: width,
            height: height,
            components: componentCount,
            bitDepth: bitDepth,
            isSigned: components.first?.signed ?? false,
            sourceURI: sourceURI,
            qualityLayers: qualityLayers
        )
    }
}

// MARK: - DICOMJPIPClient

/// A high-level client for retrieving DICOM images from a JPIP server (`SwiftJ2KJPIP` Contract **API-13**).
///
/// ``DICOMJPIPClient`` wraps `SwiftJ2KJPIP`'s ``JPIPStreamingSession`` (`SwiftJ2K` 12.2.0+) and maps
/// all four standard DICOM JPIP reference transfer syntaxes (`1.2.840.10008.1.2.4.94`, `.95`, `.204`,
/// and `.205` per PS3.6 2026a Table A-1 and PS3.5 A.6, A.7, A.11, A.12) to progressive image,
/// spatial ROI, quality-layer, and resolution-level JPIP streaming requests over HTTP/HTTPS or WebSocket.
public actor DICOMJPIPClient {
    public static let engineName = "SwiftJ2KJPIP"
    public static let engineVersion = "12.2.0"

    /// The JPIP server base URL.
    public nonisolated let serverURL: URL

    /// Negotiated block-coding preference (`htj2k` automatically selected for `.204`/`.205`).
    public nonisolated let codingPreference: JPIPCodingPreference

    private let session: JPIPStreamingSession
    private let resourceLimits: ResourceLimits

    /// Creates a new DICOM JPIP client connected to a remote or loopback JPIP server URL.
    public init(
        serverURL: URL,
        codingPreference: JPIPCodingPreference = .none,
        deliveryMode: JPIPDeliveryMode = .incremental,
        resourceLimits: ResourceLimits = .default
    ) {
        let normalizedURL = Self.normalizeTransportScheme(of: serverURL)
        self.serverURL = serverURL
        self.codingPreference = codingPreference
        self.resourceLimits = resourceLimits
        let config = (try? JPIPSessionConfiguration(
            codingPreference: codingPreference,
            deliveryMode: deliveryMode
        )) ?? (try! JPIPSessionConfiguration())
        self.session = JPIPStreamingSession(serverURL: normalizedURL, configuration: config)
    }

    /// Creates a new DICOM JPIP client configured for a specific DICOM JPIP transfer syntax UID,
    /// automatically negotiating `JPIPCodingPreference.htj2k` for `.204` and `.205`.
    public init(
        serverURL: URL,
        transferSyntaxUID: String,
        deliveryMode: JPIPDeliveryMode = .incremental,
        resourceLimits: ResourceLimits = .default
    ) {
        self.init(
            serverURL: serverURL,
            codingPreference: Self.codingPreference(forTransferSyntaxUID: transferSyntaxUID),
            deliveryMode: deliveryMode,
            resourceLimits: resourceLimits
        )
    }

    /// Creates a DICOM JPIP client bound directly to an in-process `SwiftJ2KJPIP.JPIPServer` instance.
    public init(
        server: JPIPServer,
        port: Int = 8080,
        codingPreference: JPIPCodingPreference = .none,
        deliveryMode: JPIPDeliveryMode = .incremental,
        resourceLimits: ResourceLimits = .default
    ) {
        let url = URL(string: "http://localhost:\(port)")!
        self.serverURL = url
        self.codingPreference = codingPreference
        self.resourceLimits = resourceLimits
        let config = (try? JPIPSessionConfiguration(
            codingPreference: codingPreference,
            deliveryMode: deliveryMode
        )) ?? (try! JPIPSessionConfiguration())
        self.session = JPIPStreamingSession(server: server, port: port, configuration: config)
    }

    // MARK: - Image Retrieval

    /// Fetches the full DICOM image from a JPIP server.
    public func fetchImage(jpipURI: URL) async throws -> DICOMJPIPImage {
        let imageID = try Self.requireTargetID(from: jpipURI)
        let delivered = try await deliver(imageID: imageID, viewWindow: nil)
        return delivered.legacyImage.toDICOMJPIPImage(sourceURI: jpipURI, qualityLayers: 0)
    }

    /// Fetches a spatial region of interest from a JPIP server.
    public func fetchRegion(
        jpipURI: URL,
        region: DICOMJPIPRegion,
        quality: DICOMJPIPQuality = .full
    ) async throws -> DICOMJPIPImage {
        let imageID = try Self.requireTargetID(from: jpipURI)
        let layers: Int?
        let resolutionLevel: Int?
        switch quality {
        case .full:
            layers = nil
            resolutionLevel = nil
        case .layers(let n):
            layers = max(1, n)
            resolutionLevel = nil
        case .resolutionLevel(let lvl):
            layers = nil
            resolutionLevel = max(0, lvl)
        }
        let window: JPIPViewWindow
        do {
            window = try JPIPViewWindow(
                region: (x: region.x, y: region.y, width: region.width, height: region.height),
                resolutionLevel: resolutionLevel,
                maxQualityLayers: layers
            )
        } catch {
            throw Self.mapError(error)
        }
        let delivered = try await deliver(imageID: imageID, viewWindow: window)
        return delivered.legacyImage.toDICOMJPIPImage(sourceURI: jpipURI, qualityLayers: layers ?? 0)
    }

    /// Fetches a progressive quality preview up to `layers` quality layers.
    public func fetchProgressiveQuality(jpipURI: URL, layers: Int) async throws -> DICOMJPIPImage {
        let imageID = try Self.requireTargetID(from: jpipURI)
        let clampedLayers = max(1, layers)
        let window: JPIPViewWindow
        do {
            window = try JPIPViewWindow(maxQualityLayers: clampedLayers)
        } catch {
            throw Self.mapError(error)
        }
        let delivered = try await deliver(imageID: imageID, viewWindow: window)
        return delivered.legacyImage.toDICOMJPIPImage(sourceURI: jpipURI, qualityLayers: clampedLayers)
    }

    /// Fetches the image at a specific resolution reduction level (`0` = full resolution, `1` = half, etc.).
    public func fetchResolutionLevel(
        jpipURI: URL,
        level: Int,
        layers: Int? = nil
    ) async throws -> DICOMJPIPImage {
        let imageID = try Self.requireTargetID(from: jpipURI)
        let window: JPIPViewWindow
        do {
            window = try JPIPViewWindow(
                resolutionLevel: level,
                maxQualityLayers: layers.map { max(1, $0) }
            )
        } catch {
            throw Self.mapError(error)
        }
        let delivered = try await deliver(imageID: imageID, viewWindow: window)
        return delivered.legacyImage.toDICOMJPIPImage(sourceURI: jpipURI, qualityLayers: layers ?? 0)
    }

    /// Closes the JPIP session and releases transport resources.
    public func close() async throws {
        do {
            try await session.close()
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - DICOM Integration

    /// Returns the preferred JPIP block-coding format for a DICOM transfer syntax UID.
    ///
    /// Maps PS3.5 A.11 (`1.2.840.10008.1.2.4.204`) and A.12 (`1.2.840.10008.1.2.4.205`)
    /// to `.htj2k`, and `.94` / `.95` (or other syntaxes) to `.none`.
    public static func codingPreference(forTransferSyntaxUID transferSyntaxUID: String) -> JPIPCodingPreference {
        switch transferSyntaxUID {
        case TransferSyntax.jpipHTJ2KReferenced.uid,
             TransferSyntax.jpipHTJ2KReferencedDeflate.uid:
            return .htj2k
        default:
            return .none
        }
    }

    /// Extracts the server base URL (`scheme://host[:port]`) from a full JPIP target URI.
    public static func serverBaseURL(from jpipURI: URL) -> URL {
        var comps = URLComponents(url: Self.normalizeTransportScheme(of: jpipURI), resolvingAgainstBaseURL: false)
        comps?.path = ""
        comps?.query = nil
        comps?.fragment = nil
        return comps?.url ?? Self.normalizeTransportScheme(of: jpipURI)
    }

    /// Extracts the target image identifier (`target=` query parameter or last path component) from a JPIP URI.
    public static func targetID(from jpipURI: URL) -> String? {
        if let comps = URLComponents(url: jpipURI, resolvingAgainstBaseURL: false),
           let targetItem = comps.queryItems?.first(where: { $0.name.lowercased() == "target" })?.value,
           !targetItem.isEmpty {
            return targetItem
        }
        let last = jpipURI.lastPathComponent
        if !last.isEmpty && last != "/" {
            return last
        }
        return nil
    }

    /// Extracts the JPIP URI from a DICOM dataset's Pixel Data Provider URL (0028,7FE0).
    ///
    /// PS3.5 A.6 (JPIP Referenced), A.7 (JPIP Referenced Deflate), A.11 (JPIP HTJ2K Referenced),
    /// and A.12 (JPIP HTJ2K Referenced Deflate): "Pixel Data (7FE0,0010) shall not be present,
    /// but rather Pixel Data shall be referenced via Data Element (0028,7FE0) Pixel Data Provider URL".
    /// The element has VR UR (PS3.6 Table 6-1). A Pixel Data element, if one is nevertheless present,
    /// is treated as absent: it is never read for the URI and never reported as one.
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

    // MARK: - Private Helpers

    private func deliver(
        imageID: String,
        viewWindow: JPIPViewWindow?
    ) async throws -> JPIPDeliveredImage {
        let options = JPIPStreamingOptions(
            resourceLimits: resourceLimits,
            executionPolicy: .automatic,
            copyPolicy: .allowCopy,
            metadataPolicy: .preserve
        )
        do {
            return try await session.deliverImage(
                imageID: imageID,
                viewWindow: viewWindow,
                options: options
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    private static func requireTargetID(from jpipURI: URL) throws -> String {
        guard let id = targetID(from: jpipURI) else {
            throw DICOMJPIPError.invalidJPIPURI(jpipURI.absoluteString)
        }
        return id
    }

    private static func normalizeTransportScheme(of url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = comps.scheme?.lowercased() else {
            return url
        }
        switch scheme {
        case "jpip":
            comps.scheme = "http"
            return comps.url ?? url
        case "jpips":
            comps.scheme = "https"
            return comps.url ?? url
        default:
            return url
        }
    }

    private static func mapError(_ error: any Error) -> DICOMJPIPError {
        if let jpipError = error as? DICOMJPIPError {
            return jpipError
        }
        if let codecError = error as? CodecError {
            return .serverError(codecError.category == .invalidArgument ? 400 : 502, codecError.message)
        }
        return .serverError(502, error.localizedDescription)
    }
}
