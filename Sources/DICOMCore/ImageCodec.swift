import Foundation

// MARK: - Compression Configuration

/// Quality preset for image compression
///
/// Controls the tradeoff between compression ratio and image quality.
/// Higher quality results in larger file sizes but better visual fidelity.
public enum CompressionQuality: Sendable, Hashable, Codable {
    /// Maximum quality, minimal compression (quality 0.98)
    case maximum
    
    /// High quality with good compression (quality 0.90)
    case high
    
    /// Medium quality for balanced results (quality 0.75)
    case medium
    
    /// Lower quality for maximum compression (quality 0.60)
    case low
    
    /// Custom quality value (0.0 to 1.0, where 1.0 is highest quality)
    case custom(Double)
    
    /// The numeric quality value (0.0 to 1.0)
    public var value: Double {
        switch self {
        case .maximum:
            return 0.98
        case .high:
            return 0.90
        case .medium:
            return 0.75
        case .low:
            return 0.60
        case .custom(let value):
            return max(0.0, min(1.0, value))
        }
    }
    
    /// Whether this quality setting produces lossless output (only for maximum with compatible formats)
    public var isLossless: Bool {
        switch self {
        case .maximum:
            return true
        case .custom(let value):
            return value >= 1.0
        default:
            return false
        }
    }

    /// A conservative minimum PSNR (dB) that a lossy reconstruction produced at
    /// this quality preset is expected to comfortably clear on typical 16-bit
    /// medical images.
    ///
    /// A pass/fail bar for lossy compression must be derived from the encode
    /// preset that produced the codestream, not pinned to a single fixed value:
    /// a preset tuned for high compression (`.medium`) simply cannot reach the
    /// PSNR of a near-lossless one (`.maximum`/`.high`), so a flat threshold
    /// fails perfectly good output. Each value carries roughly a 5 dB margin
    /// below the PSNR its preset achieves in practice (e.g. `.medium` reaches
    /// ~40 dB, so its bar is 35 dB). `.custom` interpolates across the same
    /// control points.
    public var expectedMinPSNRDb: Double {
        switch self {
        case .maximum: return 48.0
        case .high:    return 42.0
        case .medium:  return 35.0
        case .low:     return 28.0
        case .custom(let value):
            let points: [(q: Double, psnr: Double)] = [
                (0.60, 28.0), (0.75, 35.0), (0.90, 42.0), (0.98, 48.0)
            ]
            let q = max(0.0, min(1.0, value))
            if q <= points.first!.q { return points.first!.psnr }
            if q >= points.last!.q { return points.last!.psnr }
            for i in 1..<points.count where q <= points[i].q {
                let lo = points[i - 1], hi = points[i]
                let t = (q - lo.q) / (hi.q - lo.q)
                return lo.psnr + t * (hi.psnr - lo.psnr)
            }
            return points.last!.psnr
        }
    }
}

extension CompressionQuality: CustomStringConvertible {
    public var description: String {
        switch self {
        case .maximum:
            return "Maximum (lossless where supported)"
        case .high:
            return "High (~90%)"
        case .medium:
            return "Medium (~75%)"
        case .low:
            return "Low (~60%)"
        case .custom(let value):
            return "Custom (\(Int(value * 100))%)"
        }
    }
}

/// Speed preset for compression
///
/// Controls the tradeoff between compression speed and compression ratio.
/// Faster speeds may result in slightly larger file sizes.
public enum CompressionSpeed: Sendable, Hashable, Codable {
    /// Fastest compression, may sacrifice some compression ratio
    case fast
    
    /// Balanced speed and compression ratio
    case balanced
    
    /// Maximum compression ratio, slower processing
    case optimal
}

extension CompressionSpeed: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fast:
            return "Fast"
        case .balanced:
            return "Balanced"
        case .optimal:
            return "Optimal"
        }
    }
}

/// Configuration for image compression operations
///
/// Specifies quality, speed, and format-specific options for encoding pixel data.
/// Reference: DICOM PS3.5 Annex A - Transfer Syntax Specifications
public struct CompressionConfiguration: Sendable, Hashable {
    /// Quality preset for compression
    public let quality: CompressionQuality
    
    /// Speed preset for compression
    public let speed: CompressionSpeed
    
    /// Whether to use progressive encoding (JPEG only)
    ///
    /// Progressive images load in multiple passes, showing a low-resolution
    /// version first then refining. Better for network streaming.
    public let progressive: Bool
    
    /// Whether to prefer lossless compression when available
    ///
    /// If true and the target format supports lossless mode, lossless
    /// compression will be used regardless of quality setting.
    public let preferLossless: Bool
    
    /// Maximum number of bits per sample (for formats that support variable bit depth)
    public let maxBitsPerSample: Int?

    /// Backend the encoder should prefer (`nil` = auto / best available).
    /// Only meaningful for codecs with multiple execution paths (J2K/HTJ2K
    /// Metal GPU encode); codecs without a matching path ignore it and run
    /// their default (CPU) implementation.
    public let forcedBackend: CodecBackend?

    /// Default configuration with high quality and balanced speed
    public static let `default` = CompressionConfiguration(
        quality: .high,
        speed: .balanced,
        progressive: false,
        preferLossless: false
    )
    
    /// Configuration optimized for network transfer (smaller files)
    public static let network = CompressionConfiguration(
        quality: .medium,
        speed: .fast,
        progressive: true,
        preferLossless: false
    )
    
    /// Configuration for archival (maximum quality, lossless when possible)
    public static let archival = CompressionConfiguration(
        quality: .maximum,
        speed: .optimal,
        progressive: false,
        preferLossless: true
    )
    
    /// Configuration for lossless compression
    public static let lossless = CompressionConfiguration(
        quality: .maximum,
        speed: .balanced,
        progressive: false,
        preferLossless: true
    )
    
    /// Creates a compression configuration
    ///
    /// - Parameters:
    ///   - quality: Quality preset (default: .high)
    ///   - speed: Speed preset (default: .balanced)
    ///   - progressive: Use progressive encoding for JPEG (default: false)
    ///   - preferLossless: Prefer lossless when available (default: false)
    ///   - maxBitsPerSample: Maximum bits per sample (default: nil, use source)
    public init(
        quality: CompressionQuality = .high,
        speed: CompressionSpeed = .balanced,
        progressive: Bool = false,
        preferLossless: Bool = false,
        maxBitsPerSample: Int? = nil,
        forcedBackend: CodecBackend? = nil
    ) {
        self.quality = quality
        self.speed = speed
        self.progressive = progressive
        self.preferLossless = preferLossless
        self.maxBitsPerSample = maxBitsPerSample
        self.forcedBackend = forcedBackend
    }
}

extension CompressionConfiguration: CustomStringConvertible {
    public var description: String {
        var parts = ["quality=\(quality)", "speed=\(speed)"]
        if progressive { parts.append("progressive") }
        if preferLossless { parts.append("preferLossless") }
        if let maxBits = maxBitsPerSample { parts.append("maxBits=\(maxBits)") }
        if let backend = forcedBackend { parts.append("backend=\(backend.rawValue)") }
        return "CompressionConfiguration(\(parts.joined(separator: ", ")))"
    }
}

// MARK: - Image Codec Protocol

/// Protocol for DICOM image compression codecs
///
/// Codecs decode compressed pixel data to uncompressed format.
/// Reference: DICOM PS3.5 Annex A - Transfer Syntax Specifications
public protocol ImageCodec: Sendable {
    /// The transfer syntax UIDs this codec supports
    static var supportedTransferSyntaxes: [String] { get }
    
    /// Decodes compressed pixel data to uncompressed format
    /// - Parameters:
    ///   - data: Compressed pixel data
    ///   - descriptor: Pixel data descriptor
    /// - Returns: Uncompressed pixel data
    /// - Throws: DICOMError if decoding fails
    func decode(_ data: Data, descriptor: PixelDataDescriptor) throws -> Data
    
    /// Decodes a single frame from compressed pixel data
    /// - Parameters:
    ///   - frameData: Compressed frame data
    ///   - descriptor: Pixel data descriptor
    ///   - frameIndex: Zero-based frame index
    /// - Returns: Uncompressed frame data
    /// - Throws: DICOMError if decoding fails
    func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data

    /// Decodes a frame and reports the actual output photometric interpretation and layout.
    func decodePixelFrame(_ frameData: Data, descriptor: PixelDataDescriptor,
                          frameIndex: Int) throws -> DecodedPixelFrame
}

// MARK: - Caller-Owned Frame Decoding (WP-F, plan M3)

extension ImageCodec {
    /// Decodes a single frame into caller-owned storage, returning bytes written
    ///
    /// This default decodes into a codec-owned buffer and copies once into
    /// `destination`; codecs that can assemble output in place (e.g. RLE)
    /// override it to skip that intermediate full-frame buffer. `destination`
    /// must hold at least `descriptor.bytesPerFrame` bytes. Used by
    /// `DICOMFile.alignedPixelData(frame:)` so decoded samples land directly in
    /// page-aligned storage that Metal reads via `makeBuffer(bytesNoCopy:)`.
    public func decodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        into destination: UnsafeMutableRawBufferPointer
    ) throws -> Int {
        let decoded = try decodeFrame(frameData, descriptor: descriptor, frameIndex: frameIndex)
        guard decoded.count <= destination.count, let base = destination.baseAddress else {
            throw DICOMError.limitExceeded(
                "Caller-owned destination too small: \(destination.count) bytes for \(decoded.count)-byte frame")
        }
        decoded.withUnsafeBytes { source in
            if let src = source.baseAddress {
                base.copyMemory(from: src, byteCount: decoded.count)
            }
        }
        return decoded.count
    }
}

// MARK: - Image Encoder Protocol

/// Protocol for DICOM image compression encoders
///
/// Encoders compress uncompressed pixel data to a specific format.
/// Not all codecs support encoding - only those that implement this protocol.
/// Reference: DICOM PS3.5 Annex A - Transfer Syntax Specifications
public protocol ImageEncoder: Sendable {
    /// The transfer syntax UIDs this encoder can produce
    static var supportedEncodingTransferSyntaxes: [String] { get }
    
    /// Whether this encoder supports the given configuration
    /// - Parameters:
    ///   - configuration: Compression configuration
    ///   - descriptor: Pixel data descriptor
    /// - Returns: True if encoding is supported with these parameters
    func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool
    
    /// Encodes uncompressed pixel data to compressed format
    /// - Parameters:
    ///   - data: Uncompressed pixel data
    ///   - descriptor: Pixel data descriptor
    ///   - configuration: Compression configuration
    /// - Returns: Compressed pixel data as encapsulated fragments (one per frame)
    /// - Throws: DICOMError if encoding fails
    func encode(_ data: Data, descriptor: PixelDataDescriptor, configuration: CompressionConfiguration) throws -> [Data]
    
    /// Encodes a single frame to compressed format
    /// - Parameters:
    ///   - frameData: Uncompressed frame data
    ///   - descriptor: Pixel data descriptor
    ///   - frameIndex: Zero-based frame index
    ///   - configuration: Compression configuration
    /// - Returns: Compressed frame data
    /// - Throws: DICOMError if encoding fails
    func encodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int, configuration: CompressionConfiguration) throws -> Data
}

// MARK: - Default Encoder Implementation

extension ImageEncoder {
    /// Default implementation encodes each frame individually
    public func encode(_ data: Data, descriptor: PixelDataDescriptor, configuration: CompressionConfiguration) throws -> [Data] {
        let bytesPerFrame = descriptor.bytesPerFrame
        let numberOfFrames = descriptor.numberOfFrames
        
        var compressedFrames: [Data] = []
        compressedFrames.reserveCapacity(numberOfFrames)
        
        for frameIndex in 0..<numberOfFrames {
            let frameStart = frameIndex * bytesPerFrame
            let frameEnd = min(frameStart + bytesPerFrame, data.count)
            
            guard frameStart < data.count else {
                throw DICOMError.parsingFailed("Frame \(frameIndex) starts beyond data bounds")
            }
            
            let frameData = data.subdata(in: frameStart..<frameEnd)
            let compressedFrame = try encodeFrame(frameData, descriptor: descriptor, frameIndex: frameIndex, configuration: configuration)
            compressedFrames.append(compressedFrame)
        }
        
        return compressedFrames
    }
}

// MARK: - Default Implementation

extension ImageCodec {
    /// Default for codecs that preserve the source sample meaning and layout.
    public func decodePixelFrame(_ frameData: Data, descriptor: PixelDataDescriptor,
                                 frameIndex: Int) throws -> DecodedPixelFrame {
        DecodedPixelFrame(data: try decodeFrame(frameData, descriptor: descriptor, frameIndex: frameIndex),
                          descriptor: descriptor, sourceFrameIndex: frameIndex)
    }

    /// Default implementation decodes all data at once
    public func decode(_ data: Data, descriptor: PixelDataDescriptor) throws -> Data {
        // Default implementation for single-frame or when all frames can be decoded together
        return try decodeFrame(data, descriptor: descriptor, frameIndex: 0)
    }
}

/// Identifies the codec provider selected for a decode, encode, or compressed-domain transcode operation.
public struct CodecProviderID: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Predecessor J2KSwift-backed JPEG 2000 / HTJ2K provider.
    public static let j2kSwift = CodecProviderID(rawValue: "j2kswift")

    /// Successor SwiftJ2K-backed JPEG 2000 / HTJ2K provider (for the OS 26 integration package).
    public static let swiftJ2K = CodecProviderID(rawValue: "swiftj2k")

    /// Non-J2K codecs registered in `CodecRegistry` (JPEG, JPEG-LS, RLE, JXL, JP3D, or ImageIO).
    public static let defaultRegistry = CodecProviderID(rawValue: "default-registry")

    public var description: String { rawValue }
}

/// Optional capability for codecs that accept an explicit `CodecBackend` override on decode.
public protocol DecodeBackendConfigurableCodec: ImageCodec {
    func withDecodeBackend(_ decodeBackend: CodecBackend?) -> any ImageCodec
}

/// Bounded capability for compressed-domain transcoding between JPEG 2000 Part 1 and HTJ2K codestreams.
public protocol J2KCompressedDomainTranscoder: Sendable {
    var providerID: CodecProviderID { get }

    /// Reports before execution whether this transcoder supports the source -> target transfer syntax pair and descriptor.
    func canTranscode(
        from sourceTransferSyntaxUID: String,
        to targetTransferSyntaxUID: String,
        descriptor: PixelDataDescriptor?
    ) -> Bool

    /// Transcodes a single frame's complete codestream in the compressed domain.
    func transcodeCodestream(
        _ codestream: Data,
        from sourceTransferSyntaxUID: String,
        to targetTransferSyntaxUID: String,
        descriptor: PixelDataDescriptor?
    ) throws -> Data

    /// Transcodes a single frame's complete codestream in the compressed domain, recording its zero-based frame index.
    func transcodeCodestream(
        _ codestream: Data,
        from sourceTransferSyntaxUID: String,
        to targetTransferSyntaxUID: String,
        descriptor: PixelDataDescriptor?,
        frameIndex: Int
    ) throws -> Data
}

extension J2KCompressedDomainTranscoder {
    public func transcodeCodestream(
        _ codestream: Data,
        from sourceTransferSyntaxUID: String,
        to targetTransferSyntaxUID: String,
        descriptor: PixelDataDescriptor?,
        frameIndex: Int
    ) throws -> Data {
        try transcodeCodestream(
            codestream,
            from: sourceTransferSyntaxUID,
            to: targetTransferSyntaxUID,
            descriptor: descriptor
        )
    }
}

/// Policy governing finite pre-execution fallback when a primary J2K provider does not support
/// a requested transfer syntax, descriptor, configuration, or decode backend.
///
/// Once the selected provider starts executing, any thrown error (malformed input, resource limit
/// refusal, cancellation, or contract error) is propagated directly and never retried on another provider.
public enum J2KProviderFallbackPolicy: Sendable, Hashable {
    /// Use only the configured `J2KCodecProvider`; if it does not support a profile, resolution returns `nil`.
    case strict
    /// Before execution starts, if the configured primary `J2KCodecProvider` reports that it does not support
    /// the requested transfer syntax / descriptor / configuration / decode backend, preselect the predecessor
    /// `J2KCodecProvider.j2kSwift` provider and record `.j2kSwift` as the resolved provider ID.
    case preselectPredecessorOnUnsupportedCapability
}

/// Immutable, `Sendable` descriptor of a JPEG 2000 / HTJ2K codec provider.
public struct J2KCodecProvider: Sendable {
    public let providerID: CodecProviderID
    public let supportedDecodingTransferSyntaxUIDs: [String]
    public let supportedEncodingTransferSyntaxUIDs: [String]
    private let makeDecoderClosure: @Sendable (String) -> (any ImageCodec)?
    private let makeEncoderClosure: @Sendable (String) -> (any ImageEncoder)?
    private let canDecodeProfileClosure: @Sendable (String, PixelDataDescriptor?, CodecBackend?) -> Bool
    private let canEncodeProfileClosure: @Sendable (String, CompressionConfiguration, PixelDataDescriptor) -> Bool
    public let compressedDomainTranscoder: (any J2KCompressedDomainTranscoder)?

    public init(
        providerID: CodecProviderID,
        supportedDecodingTransferSyntaxUIDs: [String],
        supportedEncodingTransferSyntaxUIDs: [String],
        makeDecoder: @escaping @Sendable (String) -> (any ImageCodec)?,
        makeEncoder: @escaping @Sendable (String) -> (any ImageEncoder)?,
        canDecodeProfile: (@Sendable (String, PixelDataDescriptor?, CodecBackend?) -> Bool)? = nil,
        canEncodeProfile: (@Sendable (String, CompressionConfiguration, PixelDataDescriptor) -> Bool)? = nil,
        compressedDomainTranscoder: (any J2KCompressedDomainTranscoder)? = nil
    ) {
        self.providerID = providerID
        // A J2K provider cannot intercept an unrelated codec through its declared UIDs.
        self.supportedDecodingTransferSyntaxUIDs = supportedDecodingTransferSyntaxUIDs.filter(CodecRegistry.j2kFamilyTransferSyntaxUIDs.contains)
        self.supportedEncodingTransferSyntaxUIDs = supportedEncodingTransferSyntaxUIDs.filter(CodecRegistry.j2kFamilyTransferSyntaxUIDs.contains)
        self.makeDecoderClosure = makeDecoder
        self.makeEncoderClosure = makeEncoder
        self.canDecodeProfileClosure = canDecodeProfile ?? { uid, _, _ in
            supportedDecodingTransferSyntaxUIDs.contains(uid)
        }
        self.canEncodeProfileClosure = canEncodeProfile ?? { uid, config, descriptor in
            guard supportedEncodingTransferSyntaxUIDs.contains(uid),
                  let encoder = makeEncoder(uid) else {
                return false
            }
            return encoder.canEncode(with: config, descriptor: descriptor)
        }
        self.compressedDomainTranscoder = compressedDomainTranscoder
    }

    public func decoder(for transferSyntaxUID: String, decodeBackend: CodecBackend? = nil) -> (any ImageCodec)? {
        guard supportedDecodingTransferSyntaxUIDs.contains(transferSyntaxUID),
              let base = makeDecoderClosure(transferSyntaxUID) else { return nil }
        guard let decodeBackend else { return base }
        guard let configurable = base as? any DecodeBackendConfigurableCodec else { return nil }
        return configurable.withDecodeBackend(decodeBackend)
    }

    public func encoder(for transferSyntaxUID: String) -> (any ImageEncoder)? {
        guard supportedEncodingTransferSyntaxUIDs.contains(transferSyntaxUID) else { return nil }
        return makeEncoderClosure(transferSyntaxUID)
    }

    public func canDecode(
        transferSyntaxUID: String,
        descriptor: PixelDataDescriptor? = nil,
        decodeBackend: CodecBackend? = nil
    ) -> Bool {
        guard supportedDecodingTransferSyntaxUIDs.contains(transferSyntaxUID) else { return false }
        return canDecodeProfileClosure(transferSyntaxUID, descriptor, decodeBackend)
    }

    public func canEncode(
        transferSyntaxUID: String,
        configuration: CompressionConfiguration,
        descriptor: PixelDataDescriptor
    ) -> Bool {
        guard supportedEncodingTransferSyntaxUIDs.contains(transferSyntaxUID) else { return false }
        return canEncodeProfileClosure(transferSyntaxUID, configuration, descriptor)
    }

    /// The default predecessor-backed J2KSwift / HTJ2K provider.
    public static let j2kSwift: J2KCodecProvider = {
        let htj2kSet = Set(HTJ2KCodec.supportedTransferSyntaxes)
        let htj2kEncodeSet = Set(HTJ2KCodec.supportedEncodingTransferSyntaxes)
        return J2KCodecProvider(
            providerID: .j2kSwift,
            supportedDecodingTransferSyntaxUIDs: J2KSwiftCodec.supportedTransferSyntaxes,
            supportedEncodingTransferSyntaxUIDs: J2KSwiftCodec.supportedEncodingTransferSyntaxes,
            makeDecoder: { uid in
                if htj2kSet.contains(uid) {
                    return HTJ2KCodec(targetTransferSyntaxUID: uid)
                }
                guard J2KSwiftCodec.supportedTransferSyntaxes.contains(uid) else { return nil }
                return J2KSwiftCodec(decodingTransferSyntaxUID: uid)
            },
            makeEncoder: { uid in
                if htj2kEncodeSet.contains(uid) {
                    return HTJ2KCodec(targetTransferSyntaxUID: uid)
                }
                guard J2KSwiftCodec.supportedEncodingTransferSyntaxes.contains(uid) else { return nil }
                return J2KSwiftCodec(encodingTransferSyntaxUID: uid)
            },
            // J2KSwift 11.0.3 can emit changed samples on coefficient conversion.
            // Its default lossless route uses verified pixel decode and encode.
            compressedDomainTranscoder: nil
        )
    }()
}

/// Registry for managing image codecs and encoders
///
/// Provides access to codecs for different transfer syntaxes.
/// Uses platform-native codecs when available.
/// NEMA-verified: 2026a, checked 2026-09-25 — every registry key is a `TransferSyntax` UID (PS3.6 2026a Table A-1); the lossless-only syntaxes get decoders that refuse lossy codestreams, as their PS3.5 2026a A.4 definitions require. Quality and configuration types carry no standard data.
public struct CodecRegistry: Sendable {
    /// Shared codec registry instance
    public static let shared = CodecRegistry()

    /// All standard JPEG 2000 and HTJ2K transfer syntax UIDs managed by `j2kProvider`.
    public static let j2kFamilyTransferSyntaxUIDs: Set<String> = Set(J2KSwiftCodec.supportedTransferSyntaxes)

    /// The immutable J2K / HTJ2K provider configured for this registry instance.
    public let j2kProvider: J2KCodecProvider

    /// The pre-execution fallback policy for unsupported J2K / HTJ2K capabilities.
    public let j2kFallbackPolicy: J2KProviderFallbackPolicy

    private let fallbackJ2KProvider: J2KCodecProvider?

    /// Registered codecs (for decoding)
    private let codecs: [String: any ImageCodec]
    
    /// Registered encoders (for encoding)
    private let encoders: [String: any ImageEncoder]
    
    /// Creates an immutable codec registry with the specified JPEG 2000 / HTJ2K provider and fallback policy.
    public init(
        j2kProvider: J2KCodecProvider = .swiftJ2K,
        j2kFallbackPolicy: J2KProviderFallbackPolicy = .strict
    ) {
        self.j2kProvider = j2kProvider
        self.j2kFallbackPolicy = j2kFallbackPolicy
        let fallbackProvider: J2KCodecProvider? = (
            j2kFallbackPolicy == .preselectPredecessorOnUnsupportedCapability
            && j2kProvider.providerID != .j2kSwift
        ) ? .j2kSwift : nil
        self.fallbackJ2KProvider = fallbackProvider

        var decoderRegistry: [String: any ImageCodec] = [:]
        var encoderRegistry: [String: any ImageEncoder] = [:]
        
        // Each JPEG decoder enforces its negotiated DICOM process. Encoders
        // likewise select their target process per syntax.
        for uid in JLICodec.supportedTransferSyntaxes {
            decoderRegistry[uid] = JLICodec(decodingTransferSyntaxUID: uid)
        }
        for uid in JLICodec.supportedEncodingTransferSyntaxes {
            encoderRegistry[uid] = JLICodec(encodingTransferSyntaxUID: uid)
        }

        // Register J2K / HTJ2K codecs from the configured provider (and pre-execution
        // fallback provider for syntaxes the primary does not claim).
        if let fallbackProvider {
            for uid in fallbackProvider.supportedDecodingTransferSyntaxUIDs {
                if let decoder = fallbackProvider.decoder(for: uid) {
                    decoderRegistry[uid] = decoder
                }
            }
            for uid in fallbackProvider.supportedEncodingTransferSyntaxUIDs {
                if let encoder = fallbackProvider.encoder(for: uid) {
                    encoderRegistry[uid] = encoder
                }
            }
        }
        for uid in j2kProvider.supportedDecodingTransferSyntaxUIDs {
            if let decoder = j2kProvider.decoder(for: uid) {
                decoderRegistry[uid] = decoder
            }
        }
        for uid in j2kProvider.supportedEncodingTransferSyntaxUIDs {
            if let encoder = j2kProvider.encoder(for: uid) {
                encoderRegistry[uid] = encoder
            }
        }
        
        // RLE codec (pure Swift implementation - encode and decode)
        let rleCodec = RLECodec()
        for uid in RLECodec.supportedTransferSyntaxes {
            decoderRegistry[uid] = rleCodec
        }
        for uid in RLECodec.supportedEncodingTransferSyntaxes {
            encoderRegistry[uid] = rleCodec
        }
        
        // JPEG-LS codec (pure Swift implementation - encode and decode).
        // One decoder per syntax: the lossless UID refuses near-lossless scans.
        let jpegLSCodec = JPEGLSCodec()
        for uid in JPEGLSCodec.supportedTransferSyntaxes {
            decoderRegistry[uid] = JPEGLSCodec(decodingTransferSyntaxUID: uid)
        }
        for uid in JPEGLSCodec.supportedEncodingTransferSyntaxes {
            encoderRegistry[uid] = jpegLSCodec
        }

        // JP3D volumetric codec is deferred pending SwiftJ2K 12.2.0 (SwiftJ2K3D qualification).
        // Do not register experimental JP3D transfer syntaxes in the active registry.

        // JPEG XL codec (JXLSwift pure-Swift — lossless + lossy encode, lossless + lossy decode).
        for uid in JXLCodec.supportedTransferSyntaxes {
            decoderRegistry[uid] = JXLCodec(decodingTransferSyntaxUID: uid)
        }
        for uid in JXLCodec.supportedEncodingTransferSyntaxes {
            encoderRegistry[uid] = JXLCodec(encodingTransferSyntaxUID: uid)
        }
        
        self.codecs = decoderRegistry
        self.encoders = encoderRegistry
    }

    /// Preselects a decoder and records its `CodecProviderID` before execution starts.
    ///
    /// When `j2kFallbackPolicy == .preselectPredecessorOnUnsupportedCapability` and the
    /// primary `j2kProvider` does not support the transfer syntax, descriptor, or decode backend,
    /// preselects `.j2kSwift` before execution. Never retries after execution begins.
    public func resolveDecoder(
        for transferSyntaxUID: String,
        descriptor: PixelDataDescriptor? = nil,
        decodeBackend: CodecBackend? = nil
    ) -> (codec: any ImageCodec, providerID: CodecProviderID)? {
        if Self.j2kFamilyTransferSyntaxUIDs.contains(transferSyntaxUID) {
            if j2kProvider.canDecode(
                transferSyntaxUID: transferSyntaxUID,
                descriptor: descriptor,
                decodeBackend: decodeBackend
            ), let decoder = j2kProvider.decoder(for: transferSyntaxUID, decodeBackend: decodeBackend) {
                return (decoder, j2kProvider.providerID)
            }
            if let fallback = fallbackJ2KProvider,
               fallback.canDecode(
                   transferSyntaxUID: transferSyntaxUID,
                   descriptor: descriptor,
                   decodeBackend: decodeBackend
               ),
               let decoder = fallback.decoder(for: transferSyntaxUID, decodeBackend: decodeBackend) {
                return (decoder, fallback.providerID)
            }
            return nil
        }

        guard let base = codecs[transferSyntaxUID] else { return nil }
        if let decodeBackend, let configurable = base as? any DecodeBackendConfigurableCodec {
            return (configurable.withDecodeBackend(decodeBackend), .defaultRegistry)
        }
        return (base, .defaultRegistry)
    }

    /// Preselects an encoder and records its `CodecProviderID` before execution starts.
    ///
    /// When `j2kFallbackPolicy == .preselectPredecessorOnUnsupportedCapability` and the
    /// primary `j2kProvider` does not support the transfer syntax, configuration, or descriptor,
    /// preselects `.j2kSwift` before execution. Never retries after execution begins.
    public func resolveEncoder(
        for transferSyntaxUID: String,
        configuration: CompressionConfiguration,
        descriptor: PixelDataDescriptor,
        engine: JPEGCodecEngine = .jli
    ) -> (encoder: any ImageEncoder, providerID: CodecProviderID)? {
        if Self.j2kFamilyTransferSyntaxUIDs.contains(transferSyntaxUID) {
            if j2kProvider.canEncode(
                transferSyntaxUID: transferSyntaxUID,
                configuration: configuration,
                descriptor: descriptor
            ), let encoder = j2kProvider.encoder(for: transferSyntaxUID) {
                return (encoder, j2kProvider.providerID)
            }
            if let fallback = fallbackJ2KProvider,
               fallback.canEncode(
                   transferSyntaxUID: transferSyntaxUID,
                   configuration: configuration,
                   descriptor: descriptor
               ),
               let encoder = fallback.encoder(for: transferSyntaxUID) {
                return (encoder, fallback.providerID)
            }
            return nil
        }

        guard let enc = encoder(for: transferSyntaxUID, engine: engine) else { return nil }
        return (enc, .defaultRegistry)
    }

    /// Preselects a compressed-domain J2K <-> HTJ2K transcoder and records its `CodecProviderID` before execution starts.
    public func resolveJ2KTranscoder(
        from sourceTransferSyntaxUID: String,
        to targetTransferSyntaxUID: String,
        descriptor: PixelDataDescriptor? = nil
    ) -> (transcoder: any J2KCompressedDomainTranscoder, providerID: CodecProviderID)? {
        guard Self.j2kFamilyTransferSyntaxUIDs.contains(sourceTransferSyntaxUID),
              Self.j2kFamilyTransferSyntaxUIDs.contains(targetTransferSyntaxUID) else { return nil }
        if let primary = j2kProvider.compressedDomainTranscoder,
           primary.canTranscode(
               from: sourceTransferSyntaxUID,
               to: targetTransferSyntaxUID,
               descriptor: descriptor
           ) {
            return (primary, primary.providerID)
        }
        if let fallback = fallbackJ2KProvider?.compressedDomainTranscoder,
           fallback.canTranscode(
               from: sourceTransferSyntaxUID,
               to: targetTransferSyntaxUID,
               descriptor: descriptor
           ) {
            return (fallback, fallback.providerID)
        }
        return nil
    }
    
    /// Returns a codec for the specified transfer syntax
    /// - Parameter transferSyntaxUID: Transfer syntax UID
    /// - Returns: Codec if available, nil otherwise
    public func codec(for transferSyntaxUID: String) -> (any ImageCodec)? {
        return codecs[transferSyntaxUID]
    }
    
    /// Checks if a codec is available for the specified transfer syntax
    /// - Parameter transferSyntaxUID: Transfer syntax UID
    /// - Returns: True if a codec is available
    public func hasCodec(for transferSyntaxUID: String) -> Bool {
        return codecs[transferSyntaxUID] != nil
    }
    
    /// Returns an encoder for the specified transfer syntax
    /// - Parameter transferSyntaxUID: Transfer syntax UID
    /// - Returns: Encoder if available, nil otherwise
    public func encoder(for transferSyntaxUID: String) -> (any ImageEncoder)? {
        return encoders[transferSyntaxUID]
    }
    
    /// Checks if an encoder is available for the specified transfer syntax
    /// - Parameter transferSyntaxUID: Transfer syntax UID
    /// - Returns: True if an encoder is available
    public func hasEncoder(for transferSyntaxUID: String) -> Bool {
        return encoders[transferSyntaxUID] != nil
    }
    
    /// All supported transfer syntax UIDs for decoding
    public var supportedTransferSyntaxes: [String] {
        Array(codecs.keys)
    }
    
    /// All supported transfer syntax UIDs for encoding
    public var supportedEncodingTransferSyntaxes: [String] {
        Array(encoders.keys)
    }
}
