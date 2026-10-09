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
    /// Default implementation decodes all data at once
    public func decode(_ data: Data, descriptor: PixelDataDescriptor) throws -> Data {
        // Default implementation for single-frame or when all frames can be decoded together
        return try decodeFrame(data, descriptor: descriptor, frameIndex: 0)
    }
}

/// Registry for managing image codecs and encoders
///
/// Provides access to codecs for different transfer syntaxes.
/// Uses platform-native codecs when available.
/// NEMA-verified: 2026a, checked 2026-09-25 — every registry key is a `TransferSyntax` UID (PS3.6 2026a Table A-1); the lossless-only syntaxes get decoders that refuse lossy codestreams, as their PS3.5 2026a A.4 definitions require. Quality and configuration types carry no standard data.
public struct CodecRegistry: Sendable {
    /// Shared codec registry instance
    public static let shared = CodecRegistry()
    
    /// Registered codecs (for decoding)
    private let codecs: [String: any ImageCodec]
    
    /// Registered encoders (for encoding)
    private let encoders: [String: any ImageEncoder]
    
    /// Creates a codec registry with default codecs
    private init() {
        var decoderRegistry: [String: any ImageCodec] = [:]
        var encoderRegistry: [String: any ImageEncoder] = [:]
        
        // JPEG codec — JLISwift, the pure-Swift ITU-T T.81 implementation, covers
        // all four DICOM JPEG transfer syntaxes for both decode and encode. One
        // decoder serves every SOF mode (the marker drives it); encoders are
        // per-syntax — the target UID selects baseline/extended lossy DCT vs
        // lossless SOF3 — mirroring the J2KSwiftCodec wiring below. This replaces
        // the prior ImageIO-only path, so JPEG encode/decode now works identically
        // on every platform (and adds Extended/Lossless/SV1 *encoding*, which the
        // ImageIO path never supported). NativeJPEGCodec remains in the tree as a
        // standalone Apple codec, no longer wired into the registry.
        let jpegDecoder = JLICodec()
        for uid in JLICodec.supportedTransferSyntaxes {
            decoderRegistry[uid] = jpegDecoder
        }
        for uid in JLICodec.supportedEncodingTransferSyntaxes {
            encoderRegistry[uid] = JLICodec(encodingTransferSyntaxUID: uid)
        }

        // Register the preferred JPEG 2000 adapter.
        // Phase 1 uses J2KSwift directly; the native Apple codec remains available
        // as a separate platform codec, not as a runtime workaround path.
        // One decoder per syntax: lossless-only UIDs refuse irreversible codestreams.
        for uid in J2KSwiftCodec.supportedTransferSyntaxes {
            decoderRegistry[uid] = J2KSwiftCodec(decodingTransferSyntaxUID: uid)
        }
        for uid in J2KSwiftCodec.supportedEncodingTransferSyntaxes {
            encoderRegistry[uid] = J2KSwiftCodec(encodingTransferSyntaxUID: uid)
        }

        // Register the dedicated HTJ2K codec as the preferred handler for the
        // three HTJ2K transfer syntaxes, overriding the generic J2KSwiftCodec
        // entries with HTJ2K-specific configuration (RPCL ordering, etc.).
        for uid in HTJ2KCodec.supportedTransferSyntaxes {
            decoderRegistry[uid] = HTJ2KCodec(targetTransferSyntaxUID: uid)
        }
        for uid in HTJ2KCodec.supportedEncodingTransferSyntaxes {
            encoderRegistry[uid] = HTJ2KCodec(targetTransferSyntaxUID: uid)
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

        // JP3D volumetric codec (experimental — private transfer syntaxes)
        let jp3dCodec = JP3DCodec()
        for uid in JP3DCodec.supportedTransferSyntaxes {
            decoderRegistry[uid] = jp3dCodec
        }
        for uid in JP3DCodec.supportedEncodingTransferSyntaxes {
            encoderRegistry[uid] = JP3DCodec(compressionMode: uid == TransferSyntax.jp3dLossless.uid ? .lossless : .lossy())
        }

        // JPEG XL codec (JXLSwift pure-Swift — lossless + lossy encode, lossless + lossy decode).
        // Decoders are wired per-UID so the codec knows its source syntax: a …4.111 JPEG
        // Recompression instance reconstructs the wrapped JPEG (and treats a reconstruction
        // failure as a hard error), while …4.110 / …4.112 take the pixel path directly.
        for uid in JXLCodec.supportedTransferSyntaxes {
            decoderRegistry[uid] = JXLCodec(decodingTransferSyntaxUID: uid)
        }
        // Encoders are wired per-UID so the codec knows its target mode: …4.110 → lossless
        // Modular, …4.112 → lossy VarDCT (quality-driven). Mirrors the per-syntax encoder
        // wiring for JLISwift / J2KSwift above.
        for uid in JXLCodec.supportedEncodingTransferSyntaxes {
            encoderRegistry[uid] = JXLCodec(encodingTransferSyntaxUID: uid)
        }
        
        self.codecs = decoderRegistry
        self.encoders = encoderRegistry
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
