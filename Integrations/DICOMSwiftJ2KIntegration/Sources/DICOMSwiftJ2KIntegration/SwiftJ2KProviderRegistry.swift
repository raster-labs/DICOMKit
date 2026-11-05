import Foundation
import DICOMCore

extension J2KCodecProvider {
    /// Default OS 26 scalar 2D `SwiftJ2K` provider (`SwiftJ2KProviderOptions.default`).
    public static var swiftJ2K: J2KCodecProvider {
        swiftJ2K(options: .default)
    }

    /// Creates an immutable OS 26 scalar 2D `SwiftJ2K` provider with explicit admission, deadline, and telemetry options.
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
    /// Creates an immutable `CodecRegistry` wired to the OS 26 scalar 2D `SwiftJ2K` provider.
    ///
    /// - Parameters:
    ///   - options: Finite `SwiftJ2K` admission, deadline, and telemetry configuration.
    ///   - fallbackPolicy: Pre-execution fallback policy (`.strict` by default, or
    ///     `.preselectPredecessorOnUnsupportedCapability` to preselect `J2KSwift` before execution
    ///     for capabilities outside the scalar `SwiftJ2K` slice such as lossy HTJ2K `.203` or forced Metal/Accelerate).
    public static func swiftJ2K(
        options: SwiftJ2KProviderOptions = .default,
        fallbackPolicy: J2KProviderFallbackPolicy = .strict
    ) -> CodecRegistry {
        CodecRegistry(
            j2kProvider: .swiftJ2K(options: options),
            j2kFallbackPolicy: fallbackPolicy
        )
    }

    /// Explicit immutable rollback registry selecting the pinned predecessor `J2KSwift` provider
    /// for subsequent operations without mutating any in-flight `SwiftJ2K` operation.
    public static var j2kSwiftRollback: CodecRegistry {
        CodecRegistry(j2kProvider: .j2kSwift, j2kFallbackPolicy: .strict)
    }
}
