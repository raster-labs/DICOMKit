import Foundation

extension J2KCodecProvider {
    /// Default 2D `SwiftJ2K` provider (`SwiftJ2KProviderOptions.default`).
    public static var swiftJ2K: J2KCodecProvider {
        swiftJ2K(options: .default)
    }

    /// Creates an immutable 2D `SwiftJ2K` provider with explicit admission, deadline, backend, and telemetry options.
    public static func swiftJ2K(options: SwiftJ2KProviderOptions) -> J2KCodecProvider {
        J2KCodecProvider(
            providerID: .swiftJ2K,
            supportedDecodingTransferSyntaxUIDs: SwiftJ2KDICOMCodec.supportedTransferSyntaxes,
            supportedEncodingTransferSyntaxUIDs: SwiftJ2KDICOMCodec.supportedEncodingTransferSyntaxes,
            makeDecoder: { uid in
                guard SwiftJ2KDICOMCodec.supportedTransferSyntaxes.contains(uid) else { return nil }
                return SwiftJ2KDICOMCodec(decodingTransferSyntaxUID: uid, options: options)
            },
            makeEncoder: { uid in
                guard SwiftJ2KDICOMCodec.supportedEncodingTransferSyntaxes.contains(uid) else { return nil }
                return SwiftJ2KDICOMCodec(encodingTransferSyntaxUID: uid, options: options)
            },
            canDecodeProfile: { uid, descriptor, decodeBackend in
                SwiftJ2KDICOMCodec.supportsDecodeProfile(
                    transferSyntaxUID: uid,
                    descriptor: descriptor,
                    decodeBackend: decodeBackend,
                    options: options
                )
            },
            canEncodeProfile: { uid, configuration, descriptor in
                SwiftJ2KDICOMCodec.supportsEncodeProfile(
                    transferSyntaxUID: uid,
                    configuration: configuration,
                    descriptor: descriptor,
                    options: options
                )
            },
            compressedDomainTranscoder: SwiftJ2KDICOMTranscoder(options: options)
        )
    }
}

extension CodecRegistry {
    /// Creates an immutable `CodecRegistry` wired to the 2D `SwiftJ2K` provider.
    ///
    /// - Parameters:
    ///   - options: Finite `SwiftJ2K` admission, deadline, backend, and telemetry configuration.
    ///   - fallbackPolicy: Pre-execution fallback policy (`.strict` by default, or
    ///     `.preselectPredecessorOnUnsupportedCapability` to preselect `.j2kSwift` before execution
    ///     when a custom primary `SwiftJ2KProviderOptions` profile rejects an operation).
    public static func swiftJ2K(
        options: SwiftJ2KProviderOptions = .default,
        fallbackPolicy: J2KProviderFallbackPolicy = .strict
    ) -> CodecRegistry {
        CodecRegistry(
            j2kProvider: .swiftJ2K(options: options),
            j2kFallbackPolicy: fallbackPolicy
        )
    }

    /// Compatibility alias returning a `CodecRegistry` bound to the `.j2kSwift` provider identifier.
    /// After the OS 26 `SwiftJ2K 12.1.0` cutover, `J2KSwiftCodec` itself delegates to `SwiftJ2KDICOMCodec`.
    public static var j2kSwiftRollback: CodecRegistry {
        CodecRegistry(j2kProvider: .j2kSwift, j2kFallbackPolicy: .strict)
    }
}
