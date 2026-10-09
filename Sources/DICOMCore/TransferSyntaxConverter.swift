import Foundation

/// Configuration for transfer syntax conversion
///
/// Specifies how DICOM data sets should be transcoded between transfer syntaxes.
/// Reference: DICOM PS3.5 Section 10 - Transfer Syntax Specification
public struct TranscodingConfiguration: Sendable, Hashable {
    /// Preferred transfer syntaxes in order of preference
    ///
    /// When transcoding, the converter will attempt to use these syntaxes
    /// in order, selecting the first one that is compatible with the data.
    public let preferredSyntaxes: [TransferSyntax]
    
    /// Whether to allow lossy compression during transcoding
    ///
    /// If false, only lossless transfer syntaxes will be considered.
    /// Default is false to preserve data fidelity.
    public let allowLossyCompression: Bool
    
    /// Whether to preserve pixel data fidelity
    ///
    /// When true, the converter will verify that transcoding maintains
    /// pixel data integrity for lossless conversions.
    public let preservePixelDataFidelity: Bool
    
    /// Default configuration preferring Explicit VR Little Endian
    public static let `default` = TranscodingConfiguration(
        preferredSyntaxes: [
            .explicitVRLittleEndian,
            .implicitVRLittleEndian
        ],
        allowLossyCompression: false,
        preservePixelDataFidelity: true
    )
    
    /// Configuration for maximum compression (allows lossy)
    public static let maxCompression = TranscodingConfiguration(
        preferredSyntaxes: [
            .htj2kLossy,
            .jpeg2000,
            .jpegBaseline,
            .explicitVRLittleEndian
        ],
        allowLossyCompression: true,
        preservePixelDataFidelity: false
    )
    
    /// Configuration for lossless compression only
    public static let losslessCompression = TranscodingConfiguration(
        preferredSyntaxes: [
            .htj2kLossless,
            .htj2kRPCLLossless,
            .jpeg2000Lossless,
            .jpegLosslessSV1,
            .rleLossless,
            .explicitVRLittleEndian
        ],
        allowLossyCompression: false,
        preservePixelDataFidelity: true
    )
    
    /// Creates a transcoding configuration
    ///
    /// - Parameters:
    ///   - preferredSyntaxes: Transfer syntaxes in order of preference
    ///   - allowLossyCompression: Whether lossy compression is allowed
    ///   - preservePixelDataFidelity: Whether to verify pixel data integrity
    public init(
        preferredSyntaxes: [TransferSyntax],
        allowLossyCompression: Bool = false,
        preservePixelDataFidelity: Bool = true
    ) {
        self.preferredSyntaxes = preferredSyntaxes
        self.allowLossyCompression = allowLossyCompression
        self.preservePixelDataFidelity = preservePixelDataFidelity
    }
}

/// Result of a transfer syntax conversion operation
public struct TranscodingResult: Sendable {
    /// The transcoded data set bytes
    public let data: Data
    
    /// The source transfer syntax
    public let sourceTransferSyntax: TransferSyntax
    
    /// The target transfer syntax
    public let targetTransferSyntax: TransferSyntax
    
    /// Whether transcoding was actually performed
    ///
    /// False if source and target syntaxes were the same.
    public let wasTranscoded: Bool
    
    /// Whether the conversion was lossless
    public let isLossless: Bool
    
    /// Creates a transcoding result
    public init(
        data: Data,
        sourceTransferSyntax: TransferSyntax,
        targetTransferSyntax: TransferSyntax,
        wasTranscoded: Bool,
        isLossless: Bool
    ) {
        self.data = data
        self.sourceTransferSyntax = sourceTransferSyntax
        self.targetTransferSyntax = targetTransferSyntax
        self.wasTranscoded = wasTranscoded
        self.isLossless = isLossless
    }
}

/// Errors that can occur during transfer syntax conversion
public enum TranscodingError: Error, Sendable, Equatable {
    /// The source transfer syntax is not supported for transcoding
    case unsupportedSourceSyntax(String)
    
    /// The target transfer syntax is not supported for transcoding
    case unsupportedTargetSyntax(String)
    
    /// No compatible target syntax found from preferred list
    case noCompatibleSyntax
    
    /// Pixel data extraction failed
    case pixelDataExtractionFailed(String)
    
    /// Pixel data encoding failed
    case encodingFailed(String)
    
    /// Data set parsing failed
    case parsingFailed(String)
    
    /// Transcoding would result in lossy compression but was not allowed
    case lossyCompressionNotAllowed
    
    /// Pixel data fidelity could not be preserved
    case fidelityLost
}

/// Surfaces the readable ``description`` through `localizedDescription`, so apps and
/// CLIs show the reason instead of Foundation's "TranscodingError error N" fallback.
extension TranscodingError: LocalizedError {
    public var errorDescription: String? { description }
}

extension TranscodingError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unsupportedSourceSyntax(let syntax):
            return "Unsupported source transfer syntax: \(syntax)"
        case .unsupportedTargetSyntax(let syntax):
            return "Unsupported target transfer syntax: \(syntax)"
        case .noCompatibleSyntax:
            return "No compatible target transfer syntax found from preferred list"
        case .pixelDataExtractionFailed(let reason):
            return "Pixel data extraction failed: \(reason)"
        case .encodingFailed(let reason):
            return "Encoding failed: \(reason)"
        case .parsingFailed(let reason):
            return "Data set parsing failed: \(reason)"
        case .lossyCompressionNotAllowed:
            return "Transcoding would result in lossy compression but was not allowed"
        case .fidelityLost:
            return "Pixel data fidelity could not be preserved"
        }
    }
}

/// Transfer Syntax Converter
///
/// Converts DICOM data sets between different transfer syntaxes.
/// Supports conversion between uncompressed syntaxes (Implicit VR, Explicit VR),
/// decompression (compressed to uncompressed), and compression (uncompressed to compressed).
///
/// Reference: DICOM PS3.5 Section 10 - Transfer Syntax Specification
/// NEMA-verified: 2026a, checked 2026-10-01 — YBR_FULL converted to RGB before a lossy J2K/HTJ2K encode and refused for a reversible one (PS3.5 2026a 8.2.4, Table 8.2.4-1; D-CORE-3); JPEG colour labelled YBR_FULL_422 from the frame header sampling (Table 8.2.1-1; D190); byte-order transcoded and parsed values are marked with their order, Big Endian samples are swapped before encoding (D206); defined-length SQ keep their Items (PS3.5 2026a 7.5.2, D-CORE-5); the byte-swap VR set (16-, 32- and 64-bit binary VRs incl. OV/SV/UV) follows PS3.5 2026a §7.3 and Table 6.2-1; the XYB to RGB relabel after JPEG XL decode follows PS3.3 2026a C.7.6.3.1.2 and PS3.5 Table 8.2.15-1 (fixed under P1/P3 on 2026-09-24). Re-checked for this marker on 2026-09-25.
public struct TransferSyntaxConverter: Sendable {
    
    /// Configuration for the converter
    public let configuration: TranscodingConfiguration
    
    /// Compression configuration for encoding operations
    public let compressionConfiguration: CompressionConfiguration
    
    /// Creates a transfer syntax converter with the specified configuration
    /// - Parameters:
    ///   - configuration: Transcoding configuration (default: `.default`)
    ///   - compressionConfiguration: Compression configuration for encoding (default: `.default`)
    public init(
        configuration: TranscodingConfiguration = .default,
        compressionConfiguration: CompressionConfiguration = .default
    ) {
        self.configuration = configuration
        self.compressionConfiguration = compressionConfiguration
    }
    
    // MARK: - Public API
    
    /// Checks if transcoding is supported between two transfer syntaxes
    ///
    /// - Parameters:
    ///   - source: Source transfer syntax
    ///   - target: Target transfer syntax
    /// - Returns: True if transcoding is supported
    public func canTranscode(from source: TransferSyntax, to target: TransferSyntax) -> Bool {
        // Same syntax - always supported (no-op)
        if source.uid == target.uid {
            return true
        }
        
        // Currently support uncompressed-to-uncompressed conversions
        let supportedUncompressed = [
            TransferSyntax.implicitVRLittleEndian.uid,
            TransferSyntax.explicitVRLittleEndian.uid,
            TransferSyntax.explicitVRBigEndian.uid
        ]
        
        // Check if both are uncompressed
        let sourceIsUncompressed = supportedUncompressed.contains(source.uid) && !source.isEncapsulated
        let targetIsUncompressed = supportedUncompressed.contains(target.uid) && !target.isEncapsulated
        
        if sourceIsUncompressed && targetIsUncompressed {
            return true
        }
        
        // Decompression: compressed to uncompressed
        if source.isEncapsulated && targetIsUncompressed {
            return CodecRegistry.shared.hasCodec(for: source.uid)
        }
        
        // Compression: uncompressed to compressed
        if sourceIsUncompressed && target.isEncapsulated {
            return CodecRegistry.shared.hasEncoder(for: target.uid)
        }

        // Recompression: compressed to compressed
        if source.isEncapsulated && target.isEncapsulated {
            // JPEG XL JPEG Recompression is a lossless bitstream wrap/unwrap, not a
            // pixel re-encode: JPEG Baseline / Extended ↔ …4.111. …4.111 has no pixel encoder, so
            // it is admitted here explicitly rather than via the encoder registry.
            if Self.isJXLRecompressionForward(from: source, to: target)
                || Self.isJXLRecompressionReverse(from: source, to: target) {
                return true
            }
            return CodecRegistry.shared.hasCodec(for: source.uid)
                && CodecRegistry.shared.hasEncoder(for: target.uid)
        }

        return false
    }
    
    /// Selects the best target transfer syntax from the configuration's preferred list
    ///
    /// - Parameters:
    ///   - sourceData: The source data set bytes
    ///   - sourceSyntax: The source transfer syntax
    ///   - acceptedSyntaxes: List of syntaxes accepted by the target
    /// - Returns: The best compatible transfer syntax, or nil if none found
    public func selectTargetSyntax(
        for sourceData: Data,
        sourceSyntax: TransferSyntax,
        acceptedSyntaxes: [String]
    ) -> TransferSyntax? {
        for preferred in configuration.preferredSyntaxes {
            // Check if accepted by target
            guard acceptedSyntaxes.contains(preferred.uid) else {
                continue
            }
            
            // Check lossy constraint
            if !configuration.allowLossyCompression && !preferred.isLossless {
                continue
            }
            
            // Check if we can transcode to this syntax
            if canTranscode(from: sourceSyntax, to: preferred) {
                return preferred
            }
        }
        
        // If no preferred syntax works, try accepted syntaxes directly
        for acceptedUID in acceptedSyntaxes {
            guard let accepted = TransferSyntax.from(uid: acceptedUID) else {
                continue
            }
            
            if !configuration.allowLossyCompression && !accepted.isLossless {
                continue
            }
            
            if canTranscode(from: sourceSyntax, to: accepted) {
                return accepted
            }
        }
        
        return nil
    }
    
    /// Transcodes a DICOM data set to a different transfer syntax
    ///
    /// - Parameters:
    ///   - dataSetData: The source data set bytes (without File Meta Information)
    ///   - sourceSyntax: The source transfer syntax
    ///   - targetSyntax: The target transfer syntax
    /// - Returns: Transcoding result with the converted data
    /// - Throws: `TranscodingError` if transcoding fails
    public func transcode(
        dataSetData: Data,
        from sourceSyntax: TransferSyntax,
        to targetSyntax: TransferSyntax
    ) throws -> TranscodingResult {
        // Rebase sliced input once at the public boundary: the private element walkers
        // below index with 0-based offsets (`subdata(in:)`, `data[offset]`), which are
        // absolute in Data's index space — a slice with non-zero startIndex misreads or
        // traps (SliceIndependenceTests). Copies only when the input actually is a slice.
        let dataSetData = dataSetData.startIndex == 0 ? dataSetData : Data(dataSetData)
        // No transcoding needed if syntaxes match
        if sourceSyntax.uid == targetSyntax.uid {
            return TranscodingResult(
                data: dataSetData,
                sourceTransferSyntax: sourceSyntax,
                targetTransferSyntax: targetSyntax,
                wasTranscoded: false,
                isLossless: true
            )
        }
        
        // JPEG XL JPEG Recompression (…4.111) only wraps an 8-bit DCT JPEG. Explain a
        // wrong source instead of reporting a bare "unsupported target syntax".
        if targetSyntax.uid == TransferSyntax.jpegXLRecompression.uid,
           !Self.jxlRecompressibleJPEGSyntaxUIDs.contains(sourceSyntax.uid) {
            throw TranscodingError.unsupportedSourceSyntax(
                "\(sourceSyntax.uid) (\(sourceSyntax.displayName)). JPEG XL JPEG Recompression "
                + "(1.2.840.10008.1.2.4.111) needs an 8-bit JPEG Baseline (…4.50) or JPEG "
                + "Extended (…4.51) source. For lossless JPEG or non-JPEG sources use "
                + "JPEG XL Lossless (1.2.840.10008.1.2.4.110) instead")
        }

        // Check if transcoding is supported
        guard canTranscode(from: sourceSyntax, to: targetSyntax) else {
            throw TranscodingError.unsupportedTargetSyntax(targetSyntax.uid)
        }
        
        // Check lossy constraint. JPEG XL JPEG Recompression (…4.111) adds NO loss —
        // it losslessly rewraps an already-encoded JPEG bitstream (and reverses it
        // byte-for-byte) — so it counts as lossless even when the wrapped JPEG is a
        // lossy Baseline (whose `isLossless` is false). The gate is about loss *this*
        // transcode adds, so only a lossy target counts: decoding an already-lossy source
        // (e.g. JPEG Baseline → Implicit VR LE) stores its pixels exactly, adding none.
        let isRecompression = Self.isJXLRecompressionForward(from: sourceSyntax, to: targetSyntax)
            || Self.isJXLRecompressionReverse(from: sourceSyntax, to: targetSyntax)
        let isLossless = isRecompression || targetSyntax.isLossless
        if !configuration.allowLossyCompression && !isLossless {
            throw TranscodingError.lossyCompressionNotAllowed
        }
        
        // Perform the transcoding
        let transcodedData: Data
        
        // Determine transcoding direction
        let supportedUncompressed = [
            TransferSyntax.implicitVRLittleEndian.uid,
            TransferSyntax.explicitVRLittleEndian.uid,
            TransferSyntax.explicitVRBigEndian.uid
        ]
        let sourceIsUncompressed = supportedUncompressed.contains(sourceSyntax.uid) && !sourceSyntax.isEncapsulated
        
        if !sourceSyntax.isEncapsulated && !targetSyntax.isEncapsulated {
            // Uncompressed to uncompressed
            transcodedData = try transcodeUncompressed(
                dataSetData: dataSetData,
                from: sourceSyntax,
                to: targetSyntax
            )
        } else if sourceSyntax.isEncapsulated && !targetSyntax.isEncapsulated {
            // Compressed to uncompressed (decompression)
            transcodedData = try transcodeFromEncapsulated(
                dataSetData: dataSetData,
                from: sourceSyntax,
                to: targetSyntax
            )
        } else if sourceIsUncompressed && targetSyntax.isEncapsulated {
            // Uncompressed to compressed (compression)
            transcodedData = try transcodeToEncapsulated(
                dataSetData: dataSetData,
                from: sourceSyntax,
                to: targetSyntax
            )
        } else if sourceSyntax.isEncapsulated && targetSyntax.isEncapsulated {
            // Compressed to compressed
            if Self.canUseFastPathTranscode(from: sourceSyntax, to: targetSyntax) {
                // Fast-path: J2K ↔ HTJ2K via J2KTranscoder (coefficient re-encoding,
                // no full pixel decode/re-encode). Significantly faster.
                transcodedData = try transcodeFastPath(
                    dataSetData: dataSetData,
                    from: sourceSyntax,
                    to: targetSyntax
                )
            } else if isRecompression {
                // JPEG XL JPEG Recompression: wrap/unwrap the JPEG bitstream directly at
                // the encapsulated-fragment level (no pixel decode/re-encode). Forward =
                // JPEG Baseline → …4.111; reverse = …4.111 → JPEG Baseline (byte-exact).
                transcodedData = try transcodeJXLRecompression(
                    dataSetData: dataSetData,
                    from: sourceSyntax,
                    to: targetSyntax,
                    forward: Self.isJXLRecompressionForward(from: sourceSyntax, to: targetSyntax)
                )
            } else {
                // Slow path: full decode to uncompressed then re-encode
                let uncompressedSyntax = TransferSyntax.explicitVRLittleEndian
                let uncompressedData = try transcodeFromEncapsulated(
                    dataSetData: dataSetData,
                    from: sourceSyntax,
                    to: uncompressedSyntax
                )
                transcodedData = try transcodeToEncapsulated(
                    dataSetData: uncompressedData,
                    from: uncompressedSyntax,
                    to: targetSyntax
                )
            }
        } else {
            throw TranscodingError.unsupportedTargetSyntax(targetSyntax.uid)
        }
        
        return TranscodingResult(
            data: transcodedData,
            sourceTransferSyntax: sourceSyntax,
            targetTransferSyntax: targetSyntax,
            wasTranscoded: true,
            isLossless: isLossless
        )
    }
    
    // MARK: - HTJ2K Recommendation

    /// Recommends the best HTJ2K transfer syntax for a given pixel data descriptor.
    ///
    /// - Parameter descriptor: The pixel data characteristics.
    /// - Returns: The most appropriate HTJ2K transfer syntax.
    ///   Returns `.htj2kRPCLLossless` for multi-frame data (CT volumes, etc.) where
    ///   resolution-first ordering benefits progressive decoding, and `.htj2kLossless`
    ///   for single-frame data.
    public static func recommendHTJ2K(for descriptor: PixelDataDescriptor) -> TransferSyntax {
        // RPCL ordering benefits volumetric data (multi-frame, typically CT/MR)
        // where progressive resolution access is useful for streaming and preview.
        if descriptor.numberOfFrames > 1 {
            return .htj2kRPCLLossless
        }
        return .htj2kLossless
    }

    // MARK: - Fast-Path J2K ↔ HTJ2K Transcoding

    /// Whether the source and target form a J2K ↔ HTJ2K pair eligible for
    /// coefficient-level transcoding (no pixel decode/re-encode needed).
    static func canUseFastPathTranscode(from source: TransferSyntax, to target: TransferSyntax) -> Bool {
        let j2kPart1UIDs: Set<String> = [
            TransferSyntax.jpeg2000Lossless.uid,
            TransferSyntax.jpeg2000.uid
        ]
        let htj2kUIDs: Set<String> = [
            TransferSyntax.htj2kLossless.uid,
            TransferSyntax.htj2kRPCLLossless.uid,
            TransferSyntax.htj2kLossy.uid
        ]

        // J2K Part 1 → HTJ2K. Not to HTJ2K Lossless RPCL (.202): the coefficient re-encode keeps
        // the source's progression, layers and decomposition levels, which PS3.5 2026a 10.18.1
        // constrains (RPCL, base resolution ≤ 64, TLM), so .202 is always written by the encoder.
        if j2kPart1UIDs.contains(source.uid) && htj2kUIDs.contains(target.uid)
            && target.uid != TransferSyntax.htj2kRPCLLossless.uid {
            return true
        }
        // HTJ2K → J2K Part 1
        if htj2kUIDs.contains(source.uid) && j2kPart1UIDs.contains(target.uid) {
            return true
        }
        return false
    }

    /// Transcodes between J2K Part 1 and HTJ2K using J2KTranscoder's fast coefficient path.
    ///
    /// Operates on encapsulated pixel data fragments directly — each codestream
    /// fragment is transcoded individually without decoding to pixels.
    private func transcodeFastPath(
        dataSetData: Data,
        from source: TransferSyntax,
        to target: TransferSyntax
    ) throws -> Data {
        let direction: HTJ2KCodec.TranscodeDirection = source.isHTJ2K ? .htj2kToJ2K : .j2kToHTJ2K

        // Parse elements including the encapsulated pixel data
        let elements = try parseDataElements(from: dataSetData, transferSyntax: source)

        var outputElements: [DataElement] = []

        for element in elements {
            if element.tag == .pixelData && element.isEncapsulated,
               let fragments = element.encapsulatedFragments {
                // Transcode each codestream fragment using J2KTranscoder
                var transcodedFragments: [Data] = []
                for fragment in fragments {
                    let transcoded: Data
                    switch direction {
                    case .j2kToHTJ2K:
                        transcoded = try HTJ2KCodec.transcodeToHTJ2K(fragment)
                    case .htj2kToJ2K:
                        transcoded = try HTJ2KCodec.transcodeFromHTJ2K(fragment)
                    }
                    transcodedFragments.append(transcoded)
                }

                // Build new encapsulated pixel data element
                let newElement = DataElement(
                    tag: element.tag,
                    vr: element.vr,
                    length: 0xFFFFFFFF,
                    valueData: Data(),
                    encapsulatedFragments: transcodedFragments,
                    encapsulatedOffsetTable: element.encapsulatedOffsetTable ?? []
                )
                outputElements.append(newElement)
            } else if element.tag == Tag.transferSyntaxUID {
                // Update Transfer Syntax UID in File Meta
                let uidData = Data(target.uid.utf8)
                let newElement = DataElement(
                    tag: element.tag,
                    vr: .UI,
                    length: UInt32(uidData.count),
                    valueData: uidData
                )
                outputElements.append(newElement)
            } else {
                outputElements.append(element)
            }
        }

        // Write elements in target transfer syntax (all HTJ2K/J2K use Explicit VR LE)
        let writer = DICOMWriter(byteOrder: target.byteOrder, explicitVR: target.isExplicitVR)
        var outputData = Data()
        for element in outputElements {
            outputData.append(writer.serializeElement(element))
        }
        return outputData
    }

    // MARK: - JPEG XL JPEG Recompression (…4.111)

    /// DICOM JPEG transfer syntaxes whose DCT bitstream can be losslessly recompressed
    /// into JPEG XL (…4.111): JPEG Baseline (…4.50, process 1) and JPEG Extended
    /// (…4.51, processes 2 & 4).
    ///
    /// JXLSwift's `encodeLosslessJPEG` bridges any 8-bit Huffman DCT JPEG — baseline
    /// (SOF0), extended-sequential (SOF1) and progressive (SOF2). Progressive has no
    /// active DICOM UID, so it is only met inside …4.50 / …4.51 fragments, which this
    /// covers. 12-bit Extended is rejected before any fragment is touched, because
    /// PS3.5 Table 8.2.15-1 limits …4.111 to 8-bit unsigned pixel data and the JPEG XL
    /// `jbrd` reconstruction box cannot carry 12-bit JPEG. Lossless JPEG (…4.57 /
    /// …4.70, SOF3) has no DCT coefficients to carry over and stays on the pixel path.
    public static let jxlRecompressibleJPEGSyntaxUIDs: Set<String> = [
        TransferSyntax.jpegBaseline.uid,
        TransferSyntax.jpegExtended.uid
    ]

    /// Whether this is a forward JPEG → JPEG XL JPEG Recompression (…4.111) transcode.
    /// Sources outside ``jxlRecompressibleJPEGSyntaxUIDs`` fall through to the generic
    /// (encoder-registry) path, which correctly rejects …4.111 as a target.
    static func isJXLRecompressionForward(from source: TransferSyntax, to target: TransferSyntax) -> Bool {
        jxlRecompressibleJPEGSyntaxUIDs.contains(source.uid)
            && target.uid == TransferSyntax.jpegXLRecompression.uid
    }

    /// Whether this is a reverse JPEG XL JPEG Recompression (…4.111) → JPEG transcode,
    /// reconstructing the byte-identical original JPEG bitstream into JPEG Baseline
    /// (…4.50) or JPEG Extended (…4.51). The rebuilt JPEG's frame type is checked
    /// against the chosen UID in ``transcodeJXLRecompression(dataSetData:from:to:forward:)``.
    static func isJXLRecompressionReverse(from source: TransferSyntax, to target: TransferSyntax) -> Bool {
        source.uid == TransferSyntax.jpegXLRecompression.uid
            && jxlRecompressibleJPEGSyntaxUIDs.contains(target.uid)
    }

    /// The Start-Of-Frame marker (`0xC0`…`0xCF`, excluding DHT `C4`, JPG `C8` and DAC
    /// `CC`) of a JPEG bitstream, or `nil` when none is found before the first scan.
    static func jpegStartOfFrameMarker(in jpeg: Data) -> UInt8? {
        let b = Data(jpeg)  // rebase to 0-based indices
        guard b.count >= 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var i = 2
        while i + 3 < b.count {
            guard b[i] == 0xFF else { return nil }
            let marker = b[i + 1]
            if marker == 0xFF { i += 1; continue }          // fill byte
            if marker == 0xDA || marker == 0xD9 { return nil } // scan / EOI before SOF
            if (0xD0...0xD7).contains(marker) || marker == 0x01 { i += 2; continue }
            if (0xC0...0xCF).contains(marker), marker != 0xC4, marker != 0xC8, marker != 0xCC {
                return marker
            }
            let length = Int(b[i + 2]) << 8 | Int(b[i + 3])
            guard length >= 2 else { return nil }
            i += 2 + length
        }
        return nil
    }

    /// Whether a reconstructed JPEG with Start-Of-Frame `sof` may be labelled with the
    /// JPEG transfer syntax `target`. JPEG Baseline (…4.50) is process 1 only (SOF0).
    /// JPEG Extended (…4.51) also admits SOF0 (baseline is a subset of the extended
    /// process), SOF1, and SOF2 — progressive has no active DICOM UID, and …4.51 is the
    /// DCT syntax such files are found under, so the original bytes are restored as-is.
    static func jpegFrame(_ sof: UInt8, isAllowedIn target: TransferSyntax) -> Bool {
        switch target.uid {
        case TransferSyntax.jpegBaseline.uid: return sof == 0xC0
        case TransferSyntax.jpegExtended.uid: return sof == 0xC0 || sof == 0xC1 || sof == 0xC2
        default: return false
        }
    }

    /// Transcodes between JPEG Baseline / Extended and JPEG XL JPEG Recompression (…4.111) at the
    /// encapsulated-fragment level — each JPEG frame is wrapped (`forward`) or the
    /// original JPEG frame is reconstructed byte-for-byte (`!forward`) without any pixel
    /// decode/re-encode. Structurally mirrors ``transcodeFastPath(dataSetData:from:to:)``.
    private func transcodeJXLRecompression(
        dataSetData: Data,
        from source: TransferSyntax,
        to target: TransferSyntax,
        forward: Bool
    ) throws -> Data {
        // Parse elements including the encapsulated pixel data.
        let elements = try parseDataElements(from: dataSetData, transferSyntax: source)

        // PS3.5 Table 8.2.15-1: …4.111 carries only 8-bit unsigned pixel data. Reject a
        // 12-bit JPEG Extended (or signed) source up front with a clear message.
        if forward {
            func value(_ tag: Tag) -> UInt16? { elements.first { $0.tag == tag }?.uint16Value }
            let bitsAllocated = value(.bitsAllocated)
            let bitsStored = value(.bitsStored)
            let pixelRepresentation = value(.pixelRepresentation) ?? 0
            if bitsAllocated != 8 || (bitsStored ?? 8) != 8 || pixelRepresentation != 0 {
                throw TranscodingError.encodingFailed(
                    "JPEG XL JPEG Recompression (…4.111) requires 8-bit unsigned pixel data "
                    + "(Bits Allocated \(bitsAllocated.map(String.init) ?? "absent"), "
                    + "Bits Stored \(bitsStored.map(String.init) ?? "absent"), "
                    + "Pixel Representation \(pixelRepresentation)); 12-bit JPEG cannot be "
                    + "recompressed — transcode to JPEG XL Lossless (…4.110) instead")
            }
        }

        var outputElements: [DataElement] = []

        for element in elements {
            if element.tag == .pixelData && element.isEncapsulated,
               let fragments = element.encapsulatedFragments {
                // Wrap / unwrap each JPEG ↔ JXL frame fragment.
                var transcodedFragments: [Data] = []
                for fragment in fragments {
                    let transcoded: Data
                    do {
                        transcoded = forward
                            ? try JXLCodec.recompressJPEGFragment(fragment)
                            : try JXLCodec.reconstructJPEGFragment(fragment)
                    } catch {
                        throw TranscodingError.encodingFailed(
                            "JPEG XL JPEG recompression \(forward ? "wrap" : "reconstruct") "
                            + "failed: \(error)")
                    }
                    // Reverse: the rebuilt JPEG must be a frame type the chosen JPEG
                    // UID allows (e.g. an Extended/progressive JPEG is never labelled
                    // Baseline …4.50).
                    if !forward {
                        guard let sof = Self.jpegStartOfFrameMarker(in: transcoded) else {
                            throw TranscodingError.encodingFailed(
                                "JPEG XL JPEG reconstruct: rebuilt JPEG has no Start-Of-Frame marker")
                        }
                        guard Self.jpegFrame(sof, isAllowedIn: target) else {
                            throw TranscodingError.encodingFailed(
                                "JPEG XL JPEG reconstruct: rebuilt JPEG is SOF\(sof - 0xC0), "
                                + "which \(target.uid) does not allow — reconstruct to JPEG "
                                + "Extended (1.2.840.10008.1.2.4.51) instead")
                        }
                    }
                    transcodedFragments.append(transcoded)
                }

                // Build new encapsulated pixel data element.
                let newElement = DataElement(
                    tag: element.tag,
                    vr: element.vr,
                    length: 0xFFFFFFFF,
                    valueData: Data(),
                    encapsulatedFragments: transcodedFragments,
                    encapsulatedOffsetTable: buildOffsetTable(for: transcodedFragments)
                )
                outputElements.append(newElement)
            } else if element.tag == Tag.transferSyntaxUID {
                // Update Transfer Syntax UID in File Meta.
                let uidData = Data(target.uid.utf8)
                let newElement = DataElement(
                    tag: element.tag,
                    vr: .UI,
                    length: UInt32(uidData.count),
                    valueData: uidData
                )
                outputElements.append(newElement)
            } else {
                outputElements.append(element)
            }
        }

        // Write elements in target transfer syntax (…4.50, …4.51 and …4.111 all use Explicit VR LE).
        let writer = DICOMWriter(byteOrder: target.byteOrder, explicitVR: target.isExplicitVR)
        var outputData = Data()
        for element in outputElements {
            outputData.append(writer.serializeElement(element))
        }
        return outputData
    }

    // MARK: - Private Methods
    
    /// Transcodes between uncompressed transfer syntaxes
    private func transcodeUncompressed(
        dataSetData: Data,
        from source: TransferSyntax,
        to target: TransferSyntax
    ) throws -> Data {
        // Parse the source data elements
        let elements = try parseDataElements(from: dataSetData, transferSyntax: source)
        
        // Write elements in target transfer syntax
        let writer = DICOMWriter(byteOrder: target.byteOrder, explicitVR: target.isExplicitVR)
        var outputData = Data()
        
        for element in elements {
            // Re-encode numeric values if byte order changes
            let transcodedElement: DataElement
            if source.byteOrder != target.byteOrder {
                transcodedElement = try transcodeElementByteOrder(element, from: source.byteOrder, to: target.byteOrder)
            } else {
                transcodedElement = element
            }
            
            outputData.append(writer.serializeElement(transcodedElement))
        }
        
        return outputData
    }
    
    /// Transcodes from encapsulated (compressed) to uncompressed
    private func transcodeFromEncapsulated(
        dataSetData: Data,
        from source: TransferSyntax,
        to target: TransferSyntax
    ) throws -> Data {
        // For encapsulated data, we need a codec to decompress
        guard let codec = CodecRegistry.shared.codec(for: source.uid) else {
            throw TranscodingError.unsupportedSourceSyntax(source.uid)
        }
        
        // Parse elements including the encapsulated pixel data
        let elements = try parseDataElements(from: dataSetData, transferSyntax: source)
        
        // Find pixel data element and decompress if present
        var outputElements: [DataElement] = []
        var decodedXYB = false
        
        for element in elements {
            if element.tag == .pixelData && element.isEncapsulated,
               let fragments = element.encapsulatedFragments {
                // Get pixel data descriptor from surrounding elements
                let descriptor = try extractPixelDataDescriptor(from: elements)
                decodedXYB = source.isJPEGXL && descriptor.photometricInterpretation == .xyb
                
                // Decompress each frame
                var decompressedData = Data()
                for (index, fragment) in fragments.enumerated() {
                    let frameData = try codec.decodeFrame(fragment, descriptor: descriptor, frameIndex: index)
                    decompressedData.append(frameData)
                }
                
                // Create new uncompressed pixel data element
                let newElement = DataElement(
                    tag: element.tag,
                    vr: element.vr,
                    length: UInt32(decompressedData.count),
                    valueData: decompressedData
                )
                outputElements.append(newElement)
            } else {
                outputElements.append(element)
            }
        }

        // The JPEG XL decoder applies the inverse XYB transform and yields RGB samples, and
        // "Images in XYB transcoded to other Transfer Syntaxes will use RGB" (PS3.3 2026a
        // C.7.6.3.1.2). Relabel so the tag matches the decoded bytes.
        if decodedXYB {
            outputElements = outputElements.map { element in
                guard element.tag == .photometricInterpretation else { return element }
                let rgb = Data("RGB ".utf8)
                return DataElement(tag: element.tag, vr: .CS, length: UInt32(rgb.count), valueData: rgb)
            }
        }
        
        // JPEG 2000 / HTJ2K decoders invert the Part 1 multi-component transformation, so the
        // native samples are RGB: "If color components are converted from YBR_ICT or YBR_RCT to
        // RGB during decompression and Native re-encoding, the Photometric Interpretation will be
        // changed to RGB" (PS3.5 2026a 8.2.4; 8.2.14 for HTJ2K). YBR_RCT / YBR_ICT are not valid
        // for native Pixel Data (PS3.3 C.7.6.3.1.2).
        if source.isJPEG2000 {
            outputElements = Self.replacingPhotometricInterpretation(
                in: outputElements, when: ["YBR_RCT", "YBR_ICT"], with: "RGB")
        }

        // The JPEG (ImageIO) decoder converts YCbCr to RGB, so a decoded JPEG Baseline /
        // Extended colour image must be relabelled. YBR_FULL_422 in particular is only
        // valid for encapsulated JPEG and must never label native pixel data
        // (PS3.3 C.7.6.3.1.2).
        if Self.jxlRecompressibleJPEGSyntaxUIDs.contains(source.uid) {
            outputElements = outputElements.map { element in
                guard element.tag == .photometricInterpretation,
                      let value = String(data: element.valueData, encoding: .ascii)?
                          .trimmingCharacters(in: .whitespaces.union(.controlCharacters)),
                      value == "YBR_FULL_422" || value == "YBR_FULL" else {
                    return element
                }
                let rgb = Data("RGB ".utf8)
                return DataElement(tag: element.tag, vr: element.vr, length: UInt32(rgb.count), valueData: rgb)
            }
        }

        // Write elements in target transfer syntax
        let writer = DICOMWriter(byteOrder: target.byteOrder, explicitVR: target.isExplicitVR)
        var outputData = Data()

        for element in outputElements {
            outputData.append(writer.serializeElement(element))
        }

        return outputData
    }

    /// Transcodes from uncompressed to encapsulated (compressed)
    private func transcodeToEncapsulated(
        dataSetData: Data,
        from source: TransferSyntax,
        to target: TransferSyntax
    ) throws -> Data {
        // Get encoder for target syntax
        guard let encoder = CodecRegistry.shared.encoder(for: target.uid) else {
            throw TranscodingError.unsupportedTargetSyntax(target.uid)
        }
        
        // Parse elements from source
        let elements = try parseDataElements(from: dataSetData, transferSyntax: source)
        
        // Pre-scan: determine if bit-depth reduction will be needed.
        // This must happen before the output element loop because the bit-depth
        // metadata tags (group 0x0028) precede pixel data (group 0x7FE0) in tag
        // order. Without pre-scanning, the metadata tags would be emitted before
        // we know whether reduction is required.
        var needsBitReduction = false
        if elements.contains(where: { $0.tag == .pixelData && !$0.isEncapsulated }) {
            let descriptor = try extractPixelDataDescriptor(from: elements)
            if !encoder.canEncode(with: compressionConfiguration, descriptor: descriptor) {
                if descriptor.bitsAllocated == 16 && descriptor.samplesPerPixel <= 3 {
                    let test8Descriptor = PixelDataDescriptor(
                        rows: descriptor.rows,
                        columns: descriptor.columns,
                        numberOfFrames: descriptor.numberOfFrames,
                        bitsAllocated: 8,
                        bitsStored: 8,
                        highBit: 7,
                        isSigned: false,
                        samplesPerPixel: descriptor.samplesPerPixel,
                        photometricInterpretation: descriptor.photometricInterpretation,
                        planarConfiguration: descriptor.planarConfiguration
                    )
                    if encoder.canEncode(with: compressionConfiguration, descriptor: test8Descriptor) {
                        needsBitReduction = true
                    }
                }
            }
        }
        
        // Build output elements, applying bit-depth reduction when necessary
        var outputElements: [DataElement] = []
        var firstCodestream: Data?
        
        for element in elements {
            if element.tag == .pixelData && !element.isEncapsulated {
                // Get pixel data descriptor from surrounding elements
                var descriptor = try extractPixelDataDescriptor(from: elements)
                // Encoders take little-endian samples; OW from a Big Endian source is swapped (D206).
                var pixelBytes = DICOMWriter.value(element.valueData, vr: element.vr,
                                                   from: element.byteOrder, to: .littleEndian)
                
                // Apply bit-depth reduction if pre-scan determined it's needed
                if needsBitReduction {
                    pixelBytes = rescalePixelData16To8(
                        pixelBytes,
                        descriptor: descriptor,
                        elements: elements
                    )
                    descriptor = PixelDataDescriptor(
                        rows: descriptor.rows,
                        columns: descriptor.columns,
                        numberOfFrames: descriptor.numberOfFrames,
                        bitsAllocated: 8,
                        bitsStored: 8,
                        highBit: 7,
                        isSigned: false,
                        samplesPerPixel: descriptor.samplesPerPixel,
                        photometricInterpretation: descriptor.photometricInterpretation,
                        planarConfiguration: descriptor.planarConfiguration
                    )
                }
                
                // Verify the encoder can handle the (possibly reduced) configuration
                if !encoder.canEncode(with: compressionConfiguration, descriptor: descriptor) {
                    throw TranscodingError.encodingFailed(
                        "Encoder does not support the given pixel data configuration "
                        + "(bitsAllocated=\(descriptor.bitsAllocated), "
                        + "samplesPerPixel=\(descriptor.samplesPerPixel))"
                    )
                }
                
                // Compress the pixel data
                let effectiveCompressionConfiguration = target.isLossless ? .lossless : compressionConfiguration

                // J2KSwift applies the Part 1 colour transform to every 3-component image, and
                // "No other Value of Photometric Interpretation than YBR_RCT or YBR_ICT is permitted
                // when SGcod Multiple component transformation type is 1" (PS3.5 2026a 8.2.4; 8.2.14).
                // YBR_FULL needs MCT 0, so its samples are converted to RGB first and the output is
                // labelled YBR_RCT / YBR_ICT below (D-CORE-3).
                if target.isJPEG2000, descriptor.photometricInterpretation == .ybrFull {
                    (pixelBytes, descriptor) = try Self.rgbForJPEG2000Encode(
                        pixelBytes, descriptor: descriptor,
                        lossless: effectiveCompressionConfiguration.preferLossless)
                }

                let compressedFrames = try encoder.encode(
                    pixelBytes,
                    descriptor: descriptor,
                    configuration: effectiveCompressionConfiguration
                )
                
                firstCodestream = compressedFrames.first
                
                // Create new encapsulated pixel data element
                let newElement = DataElement(
                    tag: element.tag,
                    vr: .OB, // Encapsulated pixel data is always OB
                    length: 0xFFFFFFFF, // Undefined length for encapsulated data
                    valueData: Data(),
                    encapsulatedFragments: compressedFrames,
                    encapsulatedOffsetTable: buildOffsetTable(for: compressedFrames)
                )
                outputElements.append(newElement)
            } else if needsBitReduction && (element.tag == .bitsAllocated || element.tag == .bitsStored
                                        || element.tag == .highBit || element.tag == .pixelRepresentation) {
                // Rewrite pixel attribute tags to reflect 8-bit encoding
                let newValue: UInt16
                switch element.tag {
                case .bitsAllocated:          newValue = 8
                case .bitsStored:             newValue = 8
                case .highBit:                newValue = 7
                case .pixelRepresentation:    newValue = 0  // unsigned
                default:                      newValue = 0
                }
                var leBytes = newValue.littleEndian
                let valData = Data(bytes: &leBytes, count: 2)
                outputElements.append(DataElement(tag: element.tag, vr: element.vr,
                                                  length: UInt32(valData.count), valueData: valData))
            } else if needsBitReduction && (element.tag == .windowCenter
                                        || element.tag == .windowWidth
                                        || element.tag == .windowCenterWidthExplanation
                                        || element.tag == .voiLUTFunction
                                        || element.tag == .rescaleIntercept
                                        || element.tag == .rescaleSlope
                                        || element.tag == .rescaleType) {
                // After 16->8 mapping, original modality/VOI attributes may no longer
                // represent the encoded pixel range and can cause over-bright rendering
                // in strict viewers (for example Horos). Omit them so viewers auto-window.
                continue
            } else {
                outputElements.append(element)
            }
        }
        
        // JPEG 2000 / HTJ2K: the codestream decides Photometric Interpretation. With the Part 1
        // multi-component transformation (COD SGcod MCT = 1) "the DICOM Attribute Photometric
        // Interpretation (0028,0004) shall be YBR_RCT" (reversible) or "YBR_ICT" (irreversible),
        // and Planar Configuration "shall be set to 0" (PS3.5 2026a 8.2.4, Table 8.2.4-1; 8.2.14,
        // Table 8.2.14-1 for HTJ2K).
        if target.isJPEG2000, let codestream = firstCodestream,
           let style = J2KCodestreamInspector.codingStyle(in: codestream), style.componentCount == 3 {
            // RGB samples, and YBR_FULL samples converted to RGB before the encode above, are
            // relabelled: the transformation is defined on RGB (ISO/IEC 15444-1 Annex G).
            if style.multipleComponentTransform == 1 {
                outputElements = Self.replacingPhotometricInterpretation(
                    in: outputElements, when: ["RGB", "YBR_FULL"],
                    with: style.reversibleWavelet ? "YBR_RCT" : "YBR_ICT")
            }
            outputElements = outputElements.map { element in
                guard element.tag == .planarConfiguration else { return element }
                var zero = UInt16(0).littleEndian
                let value = Data(bytes: &zero, count: 2)
                return DataElement(tag: element.tag, vr: .US, length: 2, valueData: value)
            }
        }

        // JPEG lossy colour: the encoder writes YCbCr with chrominance at half the horizontal
        // rate; Table 8.2.1-1 allows a 3-sample JPEG Baseline stream only as YBR_FULL_422 or RGB,
        // and "JPEG compressed data streams are always color-by-pixel" (Planar Configuration 0)
        // (PS3.5 2026a 8.2.1; D190 / D-CORE-2).
        if target.uid == TransferSyntax.jpegBaseline.uid || target.uid == TransferSyntax.jpegExtended.uid,
           let codestream = firstCodestream, JPEGInterchangeFormat.isHorizontally422(codestream) {
            outputElements = Self.replacingPhotometricInterpretation(
                in: outputElements, when: nil, with: "YBR_FULL_422")
            outputElements = outputElements.map { element in
                guard element.tag == .planarConfiguration else { return element }
                var zero = UInt16(0).littleEndian
                let value = Data(bytes: &zero, count: 2)
                return DataElement(tag: element.tag, vr: .US, length: 2, valueData: value)
            }
        }

        // Write elements in target transfer syntax (Explicit VR Little Endian for encapsulated)
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        var outputData = Data()
        
        for element in outputElements {
            if element.tag == .pixelData && element.isEncapsulated {
                // Write encapsulated pixel data specially
                outputData.append(serializeEncapsulatedPixelData(element))
            } else {
                outputData.append(writer.serializeElement(element))
            }
        }
        
        return outputData
    }
    
    /// Native YBR_FULL samples → RGB for a JPEG 2000 / HTJ2K encode (PS3.5 2026a 8.2.4, Table
    /// 8.2.4-1: SGcod MCT = 1, which J2KSwift always writes for 3 components, is permitted only
    /// under YBR_RCT / YBR_ICT; YBR_FULL needs MCT 0). The conversion (PS3.3 2026a C.7.6.3.1.2)
    /// rounds, so it is refused for a reversible encode, whose pixels must be preserved bit for
    /// bit: the caller must convert to RGB first, or pick a lossy target.
    public static func rgbForJPEG2000Encode(
        _ pixelBytes: Data, descriptor: PixelDataDescriptor, lossless: Bool
    ) throws -> (Data, PixelDataDescriptor) {
        guard !lossless else {
            throw TranscodingError.encodingFailed(
                "YBR_FULL Pixel Data cannot be encoded reversibly to JPEG 2000 / HTJ2K: the encoder "
                + "always applies the multi-component transformation (SGcod MCT = 1), which PS3.5 "
                + "2026a 8.2.4 permits only under YBR_RCT / YBR_ICT, and converting YBR_FULL to RGB "
                + "first is not bit-preserving. Convert the image to RGB, or use a lossy target.")
        }
        guard let rgb = YBRFullConversion.rgb(fromYBRFull: pixelBytes, descriptor: descriptor) else {
            throw TranscodingError.encodingFailed(
                "YBR_FULL Pixel Data (Bits Allocated \(descriptor.bitsAllocated), Pixel Representation "
                + "\(descriptor.isSigned ? 1 : 0)) cannot be converted to RGB for a JPEG 2000 / HTJ2K encode")
        }
        return (rgb, YBRFullConversion.rgbDescriptor(for: descriptor))
    }

    /// Replaces the value of Photometric Interpretation (0028,0004) with `newValue` (padded to an
    /// even length) when its current value is in `values` (`nil`: whatever it is).
    static func replacingPhotometricInterpretation(
        in elements: [DataElement], when values: Set<String>?, with newValue: String
    ) -> [DataElement] {
        elements.map { element in
            guard element.tag == .photometricInterpretation else { return element }
            let current = String(data: element.valueData, encoding: .ascii)?
                .trimmingCharacters(in: .whitespaces.union(.controlCharacters)) ?? ""
            if let values, !values.contains(current) { return element }
            guard current != newValue else { return element }
            let padded = newValue.count % 2 == 0 ? newValue : newValue + " "
            let data = Data(padded.utf8)
            return DataElement(tag: element.tag, vr: .CS, length: UInt32(data.count), valueData: data)
        }
    }

    /// Rescales 16-bit pixel data to 8-bit using window/level from the dataset.
    ///
    /// Applies the Rescale Slope/Intercept and Window Center/Width from the dataset
    /// to map the 16-bit dynamic range into 0–255.  Falls back to min/max mapping
    /// when no window information is present.
    private func rescalePixelData16To8(
        _ data: Data,
        descriptor: PixelDataDescriptor,
        elements: [DataElement]
    ) -> Data {
        // Extract optional window/level and rescale values from the dataset
        var windowCenter: Double?
        var windowWidth: Double?
        var rescaleSlope: Double = 1.0
        var rescaleIntercept: Double = 0.0

        for element in elements {
            switch element.tag {
            case Tag(group: 0x0028, element: 0x1050):   // Window Center
                if let s = element.stringValue, let v = Double(s.trimmingCharacters(in: .whitespaces).split(separator: "\\").first ?? "") {
                    windowCenter = v
                }
            case Tag(group: 0x0028, element: 0x1051):   // Window Width
                if let s = element.stringValue, let v = Double(s.trimmingCharacters(in: .whitespaces).split(separator: "\\").first ?? "") {
                    windowWidth = v
                }
            case Tag(group: 0x0028, element: 0x1052):   // Rescale Intercept
                if let s = element.stringValue, let v = Double(s.trimmingCharacters(in: .whitespaces)) {
                    rescaleIntercept = v
                }
            case Tag(group: 0x0028, element: 0x1053):   // Rescale Slope
                if let s = element.stringValue, let v = Double(s.trimmingCharacters(in: .whitespaces)) {
                    rescaleSlope = v
                }
            default: break
            }
        }

        let pixelCount = descriptor.rows * descriptor.columns * descriptor.samplesPerPixel * descriptor.numberOfFrames
        let isSigned = descriptor.isSigned
        let mask = (1 << descriptor.bitsStored) - 1

        // Read all 16-bit samples
        var rawValues = [Int](repeating: 0, count: pixelCount)
        data.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for i in 0..<min(pixelCount, data.count / 2) {
                let lo = Int(ptr[i * 2])
                let hi = Int(ptr[i * 2 + 1])
                var val = lo | (hi << 8)
                val &= mask
                if isSigned && (val & (1 << (descriptor.bitsStored - 1))) != 0 {
                    val -= (1 << descriptor.bitsStored)
                }
                rawValues[i] = val
            }
        }

        // Determine 8-bit mapping range
        let lower: Double
        let upper: Double

        if let wc = windowCenter, let ww = windowWidth, ww > 0 {
            // Apply rescale then window
            lower = (wc - ww / 2.0 - rescaleIntercept) / rescaleSlope
            upper = (wc + ww / 2.0 - rescaleIntercept) / rescaleSlope
        } else {
            // Fallback: use actual pixel min/max
            let minVal = rawValues.min() ?? 0
            let maxVal = rawValues.max() ?? 1
            lower = Double(minVal)
            upper = Double(max(maxVal, minVal + 1))
        }

        let range = upper - lower
        var output = Data(count: pixelCount)
        output.withUnsafeMutableBytes { buf in
            guard let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for i in 0..<pixelCount {
                let normalized = (Double(rawValues[i]) - lower) / range
                let clamped = Swift.max(0.0, Swift.min(1.0, normalized))
                ptr[i] = UInt8(clamped * 255.0)
            }
        }
        return output
    }
    
    /// Builds the Basic Offset Table for encapsulated pixel data
    private func buildOffsetTable(for frames: [Data]) -> [UInt32] {
        guard frames.count > 1 else {
            // Single frame - offset table can be empty per DICOM spec
            return []
        }
        
        var offsets: [UInt32] = []
        var currentOffset: UInt32 = 0
        
        for frame in frames {
            offsets.append(currentOffset)
            // Each fragment is preceded by item tag (4 bytes) and length (4 bytes)
            currentOffset += 8 + UInt32(frame.count)
            // Pad to even length if needed
            if frame.count % 2 != 0 {
                currentOffset += 1
            }
        }
        
        return offsets
    }
    
    /// Builds the complete encapsulated pixel data bytes
    private func buildEncapsulatedPixelData(frames: [Data]) -> Data {
        var data = Data()
        
        // Build offset table
        let offsets = buildOffsetTable(for: frames)
        
        // Write offset table item (Item tag + length + offset values)
        // Item tag: FFFE,E000
        data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        
        let offsetTableLength = UInt32(offsets.count * 4)
        data.append(contentsOf: withUnsafeBytes(of: offsetTableLength.littleEndian) { Array($0) })
        
        for offset in offsets {
            data.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Array($0) })
        }
        
        // Write each frame as a fragment
        for frame in frames {
            // Item tag: FFFE,E000
            data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
            
            // Item length
            var frameLength = UInt32(frame.count)
            // Pad to even length
            if frame.count % 2 != 0 {
                frameLength += 1
            }
            data.append(contentsOf: withUnsafeBytes(of: frameLength.littleEndian) { Array($0) })
            
            // Frame data
            data.append(frame)
            
            // Add padding byte if needed
            if frame.count % 2 != 0 {
                data.append(0x00)
            }
        }
        
        // Sequence Delimitation Item: FFFE,E0DD with zero length
        data.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        
        return data
    }
    
    /// Serializes an encapsulated pixel data element
    private func serializeEncapsulatedPixelData(_ element: DataElement) -> Data {
        var data = Data()
        
        // Write tag (7FE0,0010)
        data.append(contentsOf: [0xE0, 0x7F, 0x10, 0x00])
        
        // Write VR (OB) + 2 reserved bytes
        data.append(contentsOf: [0x4F, 0x42, 0x00, 0x00])
        
        // Write undefined length (FFFFFFFF)
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        
        // Write the encapsulated data (offset table + fragments + delimiter)
        if let fragments = element.encapsulatedFragments {
            data.append(buildEncapsulatedPixelData(frames: fragments))
        }
        
        return data
    }
    
    /// Parses data elements from raw bytes
    private func parseDataElements(from data: Data, transferSyntax: TransferSyntax) throws -> [DataElement] {
        var elements: [DataElement] = []
        var offset = 0
        
        while offset < data.count {
            guard let element = try parseDataElement(from: data, at: &offset, transferSyntax: transferSyntax) else {
                break
            }
            elements.append(element)
        }
        
        return elements
    }
    
    /// Parses a single data element
    private func parseDataElement(from data: Data, at offset: inout Int, transferSyntax: TransferSyntax) throws -> DataElement? {
        guard offset + 4 <= data.count else {
            return nil
        }
        
        // Read tag
        let group = transferSyntax.byteOrder == .littleEndian
            ? data.readUInt16LE(at: offset)
            : data.readUInt16BE(at: offset)
        let element = transferSyntax.byteOrder == .littleEndian
            ? data.readUInt16LE(at: offset + 2)
            : data.readUInt16BE(at: offset + 2)
        
        guard let group = group, let element = element else {
            return nil
        }
        
        let tag = Tag(group: group, element: element)
        offset += 4
        
        // Parse based on VR encoding
        let vr: VR
        let length: UInt32
        
        if transferSyntax.isExplicitVR {
            guard offset + 2 <= data.count else {
                return nil
            }
            
            // Read VR as 2 ASCII characters
            let vrBytes = data.subdata(in: offset..<offset+2)
            let vrString = String(data: vrBytes, encoding: .ascii) ?? "UN"
            vr = VR(rawValue: vrString) ?? .UN
            offset += 2
            
            if vr.uses32BitLength {
                // Skip 2 reserved bytes
                offset += 2
                guard offset + 4 <= data.count else {
                    return nil
                }
                length = transferSyntax.byteOrder == .littleEndian
                    ? (data.readUInt32LE(at: offset) ?? 0)
                    : (data.readUInt32BE(at: offset) ?? 0)
                offset += 4
            } else {
                guard offset + 2 <= data.count else {
                    return nil
                }
                let len16 = transferSyntax.byteOrder == .littleEndian
                    ? (data.readUInt16LE(at: offset) ?? 0)
                    : (data.readUInt16BE(at: offset) ?? 0)
                length = UInt32(len16)
                offset += 2
            }
        } else {
            // Implicit VR - use UN (Unknown) as default per DICOM PS3.5 Section 6.2.2
            // A proper implementation would look up VR from the Data Element Dictionary,
            // but since DICOMCore doesn't have access to DICOMDictionary, we use UN.
            // For common tags, we can infer the VR.
            vr = inferVRForTag(tag)
            guard offset + 4 <= data.count else {
                return nil
            }
            length = transferSyntax.byteOrder == .littleEndian
                ? (data.readUInt32LE(at: offset) ?? 0)
                : (data.readUInt32BE(at: offset) ?? 0)
            offset += 4
        }
        
        // Handle undefined length (sequence or encapsulated pixel data)
        if length == 0xFFFFFFFF {
            if vr == .SQ {
                // Parse sequence
                let (items, newOffset) = try parseSequence(from: data, at: offset, transferSyntax: transferSyntax)
                offset = newOffset
                return DataElement(tag: tag, vr: vr, length: length, valueData: Data(), sequenceItems: items,
                                   byteOrder: transferSyntax.byteOrder)
            } else if tag == .pixelData {
                // Parse encapsulated pixel data
                let (fragments, offsetTable, newOffset) = try parseEncapsulatedPixelData(from: data, at: offset, transferSyntax: transferSyntax)
                offset = newOffset
                return DataElement(
                    tag: tag,
                    vr: vr,
                    length: length,
                    valueData: Data(),
                    encapsulatedFragments: fragments,
                    encapsulatedOffsetTable: offsetTable,
                    byteOrder: transferSyntax.byteOrder
                )
            }
        }
        
        // Read value data
        let intLength = Int(length)
        guard offset + intLength <= data.count else {
            // Handle truncated data gracefully
            // This can occur when parsing partial data or when the source file was truncated.
            // We read what's available to allow processing to continue, which is acceptable
            // for transcoding scenarios where the goal is to convert existing (possibly
            // partial) data rather than strictly validate completeness.
            // The caller can detect truncation by comparing the returned element's length
            // with the original length if strict validation is needed.
            let availableLength = data.count - offset
            let valueData = data.subdata(in: offset..<offset+availableLength)
            offset = data.count
            return DataElement(tag: tag, vr: vr, length: UInt32(availableLength), valueData: valueData,
                               byteOrder: transferSyntax.byteOrder)
        }
        
        let valueData = data.subdata(in: offset..<offset+intLength)
        offset += intLength

        // A defined-length Sequence (PS3.5 2026a 7.5.2, "Explicit Length") keeps its Items:
        // DICOMWriter re-encodes an SQ from its Items, so an SQ element without them was written
        // as an empty sequence, dropping every defined-length sequence on a transcode (D-CORE-5).
        if vr == .SQ {
            let (items, _) = try parseSequence(from: valueData, at: 0, transferSyntax: transferSyntax)
            return DataElement(tag: tag, vr: vr, length: length, valueData: valueData, sequenceItems: items,
                               byteOrder: transferSyntax.byteOrder)
        }

        // Values are marked with the byte order they were read in, so DICOMWriter swaps them
        // when the target order differs (PS3.5 2026a 7.3; D206).
        return DataElement(tag: tag, vr: vr, length: length, valueData: valueData,
                           byteOrder: transferSyntax.byteOrder)
    }
    
    /// Parses a sequence with undefined length
    private func parseSequence(from data: Data, at offset: Int, transferSyntax: TransferSyntax) throws -> ([SequenceItem], Int) {
        var items: [SequenceItem] = []
        var currentOffset = offset
        
        while currentOffset + 8 <= data.count {
            let group = transferSyntax.byteOrder == .littleEndian
                ? (data.readUInt16LE(at: currentOffset) ?? 0)
                : (data.readUInt16BE(at: currentOffset) ?? 0)
            let element = transferSyntax.byteOrder == .littleEndian
                ? (data.readUInt16LE(at: currentOffset + 2) ?? 0)
                : (data.readUInt16BE(at: currentOffset + 2) ?? 0)
            
            // Check for Sequence Delimitation Item
            if group == 0xFFFE && element == 0xE0DD {
                currentOffset += 8 // Skip tag and length
                break
            }
            
            // Check for Item tag
            guard group == 0xFFFE && element == 0xE000 else {
                break
            }
            
            let itemLength = transferSyntax.byteOrder == .littleEndian
                ? (data.readUInt32LE(at: currentOffset + 4) ?? 0)
                : (data.readUInt32BE(at: currentOffset + 4) ?? 0)
            currentOffset += 8
            
            if itemLength == 0xFFFFFFFF {
                // Parse item with undefined length
                var itemElements: [DataElement] = []
                while currentOffset + 8 <= data.count {
                    let delimGroup = transferSyntax.byteOrder == .littleEndian
                        ? (data.readUInt16LE(at: currentOffset) ?? 0)
                        : (data.readUInt16BE(at: currentOffset) ?? 0)
                    let delimElement = transferSyntax.byteOrder == .littleEndian
                        ? (data.readUInt16LE(at: currentOffset + 2) ?? 0)
                        : (data.readUInt16BE(at: currentOffset + 2) ?? 0)
                    
                    // Check for Item Delimitation Item
                    if delimGroup == 0xFFFE && delimElement == 0xE00D {
                        currentOffset += 8
                        break
                    }
                    
                    if let elem = try parseDataElement(from: data, at: &currentOffset, transferSyntax: transferSyntax) {
                        itemElements.append(elem)
                    } else {
                        break
                    }
                }
                items.append(SequenceItem(elements: itemElements))
            } else {
                // Parse item with explicit length
                let itemEndOffset = currentOffset + Int(itemLength)
                var itemElements: [DataElement] = []
                while currentOffset < itemEndOffset && currentOffset < data.count {
                    if let elem = try parseDataElement(from: data, at: &currentOffset, transferSyntax: transferSyntax) {
                        itemElements.append(elem)
                    } else {
                        break
                    }
                }
                currentOffset = itemEndOffset
                items.append(SequenceItem(elements: itemElements))
            }
        }
        
        return (items, currentOffset)
    }
    
    /// Parses encapsulated pixel data
    private func parseEncapsulatedPixelData(from data: Data, at offset: Int, transferSyntax: TransferSyntax) throws -> ([Data], [UInt32], Int) {
        var fragments: [Data] = []
        var offsetTable: [UInt32] = []
        var currentOffset = offset
        var isFirstItem = true
        
        while currentOffset + 8 <= data.count {
            let group = transferSyntax.byteOrder == .littleEndian
                ? (data.readUInt16LE(at: currentOffset) ?? 0)
                : (data.readUInt16BE(at: currentOffset) ?? 0)
            let element = transferSyntax.byteOrder == .littleEndian
                ? (data.readUInt16LE(at: currentOffset + 2) ?? 0)
                : (data.readUInt16BE(at: currentOffset + 2) ?? 0)
            
            // Check for Sequence Delimitation Item
            if group == 0xFFFE && element == 0xE0DD {
                currentOffset += 8
                break
            }
            
            // Check for Item tag
            guard group == 0xFFFE && element == 0xE000 else {
                break
            }
            
            let itemLength = transferSyntax.byteOrder == .littleEndian
                ? (data.readUInt32LE(at: currentOffset + 4) ?? 0)
                : (data.readUInt32BE(at: currentOffset + 4) ?? 0)
            currentOffset += 8

            // Guard against a corrupt/truncated fragment length that exceeds the
            // bytes remaining (e.g. a stray 0xFFFFFFFF). subdata(in:) traps on an
            // out-of-range upper bound, so stop best-effort parsing here instead.
            guard currentOffset + Int(itemLength) <= data.count else {
                break
            }
            let fragmentData = data.subdata(in: currentOffset..<currentOffset+Int(itemLength))
            
            if isFirstItem {
                // First item is the basic offset table
                isFirstItem = false
                // Parse offset table (UInt32 values)
                // Per DICOM PS3.5 A.4, the offset table may be empty (0 length)
                // or contain one offset per frame. We parse what's available.
                if fragmentData.count % 4 != 0 && fragmentData.count > 0 {
                    // Offset table should be a multiple of 4 bytes (UInt32 values)
                    // A malformed table may indicate corrupted data, but we continue
                    // to allow best-effort processing of the pixel data fragments
                }
                for i in stride(from: 0, to: fragmentData.count - 3, by: 4) {
                    if let value = fragmentData.readUInt32LE(at: i) {
                        offsetTable.append(value)
                    }
                }
            } else {
                fragments.append(fragmentData)
            }
            
            currentOffset += Int(itemLength)
        }
        
        return (fragments, offsetTable, currentOffset)
    }
    
    /// Transcodes a data element's value for byte order change
    private func transcodeElementByteOrder(_ element: DataElement, from source: ByteOrder, to target: ByteOrder) throws -> DataElement {
        guard source != target else {
            return element
        }
        
        // Only transcode numeric VRs
        // PS3.5 §7.3 lists every multi-byte binary VR: 2-byte US SS OW (and each AT
        // component), 4-byte OF OL UL SL FL, 8-byte OD OV FD SV UV.
        let numericVRs: [VR] = [.US, .SS, .UL, .SL, .FL, .FD, .AT, .OW, .OF, .OL, .OD, .OV, .SV, .UV]

        guard numericVRs.contains(element.vr) else {
            return element
        }

        var newData = Data()
        let valueData = element.valueData

        switch element.vr {
        case .US, .SS, .OW, .AT:
            // 16-bit values. AT is an ordered pair of two independent UInt16
            // (group, then element), so each 16-bit unit is byte-swapped in
            // place while their order is preserved — exactly the 16-bit path.
            for i in stride(from: 0, to: valueData.count, by: 2) {
                if i + 2 <= valueData.count {
                    let value = source == .littleEndian
                        ? (valueData.readUInt16LE(at: i) ?? 0)
                        : (valueData.readUInt16BE(at: i) ?? 0)
                    if target == .littleEndian {
                        newData.append(UInt8(value & 0xFF))
                        newData.append(UInt8((value >> 8) & 0xFF))
                    } else {
                        newData.append(UInt8((value >> 8) & 0xFF))
                        newData.append(UInt8(value & 0xFF))
                    }
                }
            }
            
        case .UL, .SL, .FL, .OF, .OL:
            // 32-bit values
            for i in stride(from: 0, to: valueData.count, by: 4) {
                if i + 4 <= valueData.count {
                    let value = source == .littleEndian
                        ? (valueData.readUInt32LE(at: i) ?? 0)
                        : (valueData.readUInt32BE(at: i) ?? 0)
                    if target == .littleEndian {
                        newData.append(UInt8(value & 0xFF))
                        newData.append(UInt8((value >> 8) & 0xFF))
                        newData.append(UInt8((value >> 16) & 0xFF))
                        newData.append(UInt8((value >> 24) & 0xFF))
                    } else {
                        newData.append(UInt8((value >> 24) & 0xFF))
                        newData.append(UInt8((value >> 16) & 0xFF))
                        newData.append(UInt8((value >> 8) & 0xFF))
                        newData.append(UInt8(value & 0xFF))
                    }
                }
            }
            
        case .FD, .OD, .OV, .SV, .UV:
            // 64-bit values
            for i in stride(from: 0, to: valueData.count, by: 8) {
                if i + 8 <= valueData.count {
                    let value = source == .littleEndian
                        ? (valueData.readUInt64LE(at: i) ?? 0)
                        : (valueData.readUInt64BE(at: i) ?? 0)
                    if target == .littleEndian {
                        for j in 0..<8 {
                            newData.append(UInt8((value >> (j * 8)) & 0xFF))
                        }
                    } else {
                        for j in stride(from: 7, through: 0, by: -1) {
                            newData.append(UInt8((value >> (j * 8)) & 0xFF))
                        }
                    }
                }
            }
            
        default:
            return element
        }
        
        // Use the appropriate DataElement constructor based on whether there are sequence items.
        // The value is now in `target` order, and says so: DICOMWriter byte-swaps a value whose
        // order differs from its own (D206), so an unmarked value would be swapped twice.
        if let seqItems = element.sequenceItems {
            return DataElement(
                tag: element.tag,
                vr: element.vr,
                length: UInt32(newData.count),
                valueData: newData,
                sequenceItems: seqItems,
                byteOrder: target
            )
        } else {
            return DataElement(
                tag: element.tag,
                vr: element.vr,
                length: UInt32(newData.count),
                valueData: newData,
                byteOrder: target
            )
        }
    }
    
    /// Extracts pixel data descriptor from surrounding elements
    private func extractPixelDataDescriptor(from elements: [DataElement]) throws -> PixelDataDescriptor {
        var rows: Int?
        var columns: Int?
        var numberOfFrames: Int = 1
        var bitsAllocated: Int?
        var bitsStored: Int?
        var highBit: Int?
        var pixelRepresentation: Int = 0
        var samplesPerPixel: Int = 1
        var photometricInterpretation: PhotometricInterpretation = .monochrome2
        var planarConfiguration: Int = 0
        
        for element in elements {
            switch element.tag {
            case .rows:
                rows = element.uint16Value.map { Int($0) }
            case .columns:
                columns = element.uint16Value.map { Int($0) }
            case .numberOfFrames:
                if let str = element.stringValue, let val = Int(str) {
                    numberOfFrames = val
                }
            case .bitsAllocated:
                bitsAllocated = element.uint16Value.map { Int($0) }
            case .bitsStored:
                bitsStored = element.uint16Value.map { Int($0) }
            case .highBit:
                highBit = element.uint16Value.map { Int($0) }
            case .pixelRepresentation:
                pixelRepresentation = element.uint16Value.map { Int($0) } ?? 0
            case .samplesPerPixel:
                samplesPerPixel = element.uint16Value.map { Int($0) } ?? 1
            case .photometricInterpretation:
                if let str = element.stringValue {
                    photometricInterpretation = PhotometricInterpretation(rawValue: str.trimmingCharacters(in: .whitespaces)) ?? .monochrome2
                }
            case .planarConfiguration:
                planarConfiguration = element.uint16Value.map { Int($0) } ?? 0
            default:
                break
            }
        }
        
        guard let r = rows, let c = columns, let ba = bitsAllocated, let bs = bitsStored, let hb = highBit else {
            throw TranscodingError.pixelDataExtractionFailed("Missing required pixel data attributes")
        }
        
        return PixelDataDescriptor(
            rows: r,
            columns: c,
            numberOfFrames: numberOfFrames,
            bitsAllocated: ba,
            bitsStored: bs,
            highBit: hb,
            isSigned: pixelRepresentation == 1,
            samplesPerPixel: samplesPerPixel,
            photometricInterpretation: photometricInterpretation,
            planarConfiguration: planarConfiguration
        )
    }
    
    /// Infers the VR for common tags when parsing Implicit VR data
    ///
    /// Since DICOMCore doesn't have access to the full Data Element Dictionary,
    /// this function provides VR inference for commonly used tags only.
    /// For unknown tags, returns UN (Unknown) per DICOM PS3.5 Section 6.2.2.
    ///
    /// - Important: This is a limited implementation that only covers standard DICOM tags
    ///   commonly used in medical imaging workflows. Private tags and less common
    ///   standard tags will be assigned VR=UN, which may result in incorrect
    ///   interpretation of string vs. numeric data. For full VR support, use the
    ///   DICOMParser from DICOMKit which has access to the complete Data Element Dictionary.
    ///
    /// - Note: When transcoding Implicit VR data with non-standard tags, the resulting
    ///   Explicit VR output will use UN VR for unknown tags, which is valid DICOM
    ///   but may not preserve the original semantic meaning.
    ///
    /// - Parameter tag: The DICOM tag to infer VR for
    /// - Returns: The inferred VR, or UN if the tag is not recognized
    private func inferVRForTag(_ tag: Tag) -> VR {
        // File Meta Information (Group 0002) - always Explicit VR, but handle anyway
        switch tag {
        case .fileMetaInformationGroupLength:
            return .UL
        case .fileMetaInformationVersion:
            return .OB
        case .mediaStorageSOPClassUID, .mediaStorageSOPInstanceUID,
             .transferSyntaxUID, .implementationClassUID:
            return .UI
        case .implementationVersionName:
            return .SH
            
        // SOP Common (0008,xxxx)
        case .sopClassUID, .sopInstanceUID:
            return .UI
        case .studyDate, .seriesDate, .contentDate:
            return .DA
        case .studyTime, .seriesTime, .contentTime:
            return .TM
        case .accessionNumber:
            return .SH
        case .modality:
            return .CS
        case .referringPhysicianName:
            return .PN
        case .studyDescription:
            return .LO
        case .seriesDescription:
            return .LO
        case .manufacturer:
            return .LO
        case .institutionName:
            return .LO
        case .stationName:
            return .SH
            
        // Patient (0010,xxxx)
        case .patientName:
            return .PN
        case .patientID:
            return .LO
        case .patientBirthDate:
            return .DA
        case .patientSex:
            return .CS
        case .patientAge:
            return .AS
        case .patientSize:
            return .DS
        case .patientWeight:
            return .DS
            
        // Study (0020,xxxx)
        case .studyInstanceUID, .seriesInstanceUID:
            return .UI
        case .studyID:
            return .SH
        case .seriesNumber, .instanceNumber:
            return .IS
        case .patientPosition:
            return .CS
        case .imagePositionPatient, .imageOrientationPatient:
            return .DS
        case .frameOfReferenceUID:
            return .UI
        case .sliceLocation:
            return .DS
        case .numberOfFrames:
            return .IS
            
        // Image Pixel Module (0028,xxxx)
        case .rows, .columns:
            return .US
        case .bitsAllocated, .bitsStored, .highBit:
            return .US
        case .pixelRepresentation:
            return .US
        case .samplesPerPixel:
            return .US
        case .photometricInterpretation:
            return .CS
        case .planarConfiguration:
            return .US
        case .windowCenter, .windowWidth:
            return .DS
        case .rescaleIntercept, .rescaleSlope:
            return .DS
        case .rescaleType:
            return .LO
        case .pixelSpacing:
            return .DS
        case .sliceThickness:
            return .DS
            
        // Pixel Data
        case .pixelData:
            return .OW
            
        default:
            // For unknown tags, return UN (Unknown)
            return .UN
        }
    }
}
