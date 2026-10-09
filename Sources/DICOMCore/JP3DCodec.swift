// NEMA-verified: 2026a, checked 2026-09-25 — carries no DICOM-standard data. The two UIDs are private (1.2.826.0.1.3680043.10.511.x), not in PS3.6 2026a Table A-1; JP3D has no standard transfer syntax. C1 classification confirmed.

import Foundation
import J2KCore
import J2K3D

/// JP3D volumetric JPEG 2000 codec for DICOM multi-frame data.
///
/// `JP3DCodec` wraps J2KSwift's `JP3DEncoder` and `JP3DDecoder` to provide
/// volumetric compression of multi-frame pixel data under the experimental
/// JP3D transfer syntaxes.
///
/// ## Transfer Syntaxes
///
/// JP3D has **no standard DICOM transfer syntax**. This codec uses private
/// vendor extension UIDs:
/// - `1.2.826.0.1.3680043.10.511.1` — JP3D Lossless (experimental)
/// - `1.2.826.0.1.3680043.10.511.2` — JP3D Lossy (experimental)
///
/// ## Usage
///
/// ```swift
/// let codec = JP3DCodec()
///
/// // Encode an entire volume (all frames concatenated)
/// let compressed = try await codec.encodeVolume(pixelData, descriptor: desc)
///
/// // Decode back
/// let decoded = try await codec.decodeVolume(compressed, descriptor: desc)
/// ```
///
/// ## Limitations
///
/// - Experimental: not for interoperability with other DICOM implementations.
/// - Only grayscale (1 sample/pixel) volumes are currently supported.
/// - The `ImageCodec` frame-level API wraps the volumetric codec internally.
public final class JP3DCodec: ImageCodec, ImageEncoder, @unchecked Sendable {

    /// Transfer syntax UIDs this codec supports.
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.jp3dLossless.uid,
        TransferSyntax.jp3dLossy.uid
    ]

    /// Transfer syntax UIDs this encoder can produce.
    public static let supportedEncodingTransferSyntaxes: [String] = supportedTransferSyntaxes

    /// The compression mode to use for encoding.
    public enum CompressionMode: Sendable {
        /// Lossless compression (bit-exact reconstruction).
        case lossless
        /// Lossless compression using HTJ2K block coder.
        case losslessHTJ2K
        /// Lossy compression with PSNR target.
        case lossy(psnr: Double = 40.0)
        /// Lossy HTJ2K compression with PSNR target.
        case lossyHTJ2K(psnr: Double = 40.0)

        var jp3dMode: JP3DCompressionMode {
            switch self {
            case .lossless: return .lossless
            case .losslessHTJ2K: return .losslessHTJ2K
            case .lossy(let psnr): return .lossy(psnr: psnr)
            case .lossyHTJ2K(let psnr): return .lossyHTJ2K(psnr: psnr)
            }
        }

        var isLossless: Bool {
            switch self {
            case .lossless, .losslessHTJ2K: return true
            case .lossy, .lossyHTJ2K: return false
            }
        }
    }

    /// The compression mode used when encoding.
    public let compressionMode: CompressionMode

    /// Creates a JP3D codec with the specified compression mode.
    ///
    /// - Parameter compressionMode: Compression mode (default: `.lossless`).
    public init(compressionMode: CompressionMode = .lossless) {
        self.compressionMode = compressionMode
    }

    // MARK: - Volumetric API

    /// Encodes a complete volume of multi-frame pixel data to a JP3D codestream.
    ///
    /// - Parameters:
    ///   - data: Concatenated pixel data for all frames (frame-major order).
    ///   - descriptor: Pixel data descriptor describing the volume geometry.
    /// - Returns: The JP3D compressed codestream.
    /// - Throws: `DICOMError` if encoding fails.
    public func encodeVolume(
        _ data: Data,
        descriptor: PixelDataDescriptor
    ) async throws -> Data {
        let volume = try makeVolume(from: data, descriptor: descriptor)
        let config = JP3DEncoderConfiguration(
            compressionMode: compressionMode.jp3dMode,
            tiling: .default,
            progressionOrder: .lrcps,
            qualityLayers: compressionMode.isLossless ? 1 : 3,
            levelsX: min(3, floorLog2(descriptor.columns)),
            levelsY: min(3, floorLog2(descriptor.rows)),
            levelsZ: min(1, floorLog2(descriptor.numberOfFrames))
        )
        let encoder = JP3DEncoder(configuration: config)
        let result = try await encoder.encode(volume)
        return result.data
    }

    /// Decodes a JP3D codestream back to multi-frame pixel data.
    ///
    /// - Parameters:
    ///   - data: The JP3D compressed codestream.
    ///   - descriptor: Pixel data descriptor for the expected output.
    /// - Returns: Concatenated decompressed pixel data for all frames.
    /// - Throws: `DICOMError` if decoding fails.
    public func decodeVolume(
        _ data: Data,
        descriptor: PixelDataDescriptor
    ) async throws -> Data {
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        return extractPixelData(from: result.volume, descriptor: descriptor)
    }

    // MARK: - ImageCodec Protocol

    /// Decodes compressed pixel data to uncompressed format.
    ///
    /// For JP3D, this expects the full codestream and returns all frames concatenated.
    /// Bridges from the async volumetric decode using a blocking continuation.
    public func decode(_ data: Data, descriptor: PixelDataDescriptor) throws -> Data {
        let capturedData = data
        let capturedDescriptor = descriptor
        let codec = self

        // Use an unsafe continuation to bridge async → sync safely under strict concurrency.
        // Bounded like J2KSwiftCodec.awaitJ2KResult: an unbounded semaphore.wait()
        // here would hang the caller forever if decodeVolume's underlying codec
        // work (potentially GPU-backed) never completes.
        let box = UnsafeSendableBox<Result<Data, Error>>()
        let semaphore = DispatchSemaphore(value: 0)

        let task = Task {
            do {
                let decoded = try await codec.decodeVolume(capturedData, descriptor: capturedDescriptor)
                box.value = .success(decoded)
            } catch {
                box.value = .failure(error)
            }
            semaphore.signal()
        }

        let timeout: TimeInterval = 60
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            throw DICOMError.parsingFailed(
                "JP3D async bridge timed out after \(timeout)s — the codec backend may be unresponsive")
        }
        guard let result = box.value else {
            throw DICOMError.parsingFailed("JP3D decode did not produce a result")
        }
        return try result.get()
    }

    /// Decodes a single frame from JP3D compressed data.
    ///
    /// Decodes the entire volume and extracts the requested frame.
    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        let allFrames = try decode(frameData, descriptor: descriptor)
        let bytesPerFrame = descriptor.bytesPerFrame
        let start = frameIndex * bytesPerFrame
        guard start + bytesPerFrame <= allFrames.count else {
            throw DICOMError.parsingFailed("Frame \(frameIndex) out of bounds in decoded volume")
        }
        return allFrames.subdata(in: start..<(start + bytesPerFrame))
    }

    // MARK: - ImageEncoder Protocol

    /// Whether encoding is supported for the given configuration and descriptor.
    public func canEncode(with configuration: DICOMCore.CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        // Support grayscale 8/16-bit volumes
        guard descriptor.samplesPerPixel == 1 else { return false }
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else { return false }
        guard descriptor.numberOfFrames > 1 else { return false }
        return true
    }

    /// Encodes a single frame (returns the frame data unchanged since JP3D is volumetric).
    ///
    /// JP3D requires all frames to be encoded together. This method stores the raw frame.
    /// Use `encodeVolume` for actual volumetric compression.
    public func encodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        configuration: DICOMCore.CompressionConfiguration
    ) throws -> Data {
        // JP3D is inherently volumetric — single-frame encoding isn't meaningful.
        // Return raw frame data; callers should use encodeVolume() instead.
        return frameData
    }

    // MARK: - Private Helpers

    private func makeVolume(from data: Data, descriptor: PixelDataDescriptor) throws -> J2KVolume {
        let component = J2KVolumeComponent(
            index: 0,
            bitDepth: descriptor.bitsStored,
            signed: descriptor.isSigned,
            width: descriptor.columns,
            height: descriptor.rows,
            depth: descriptor.numberOfFrames,
            data: data
        )
        return J2KVolume(
            width: descriptor.columns,
            height: descriptor.rows,
            depth: descriptor.numberOfFrames,
            components: [component]
        )
    }

    private func extractPixelData(from volume: J2KVolume, descriptor: PixelDataDescriptor) -> Data {
        guard let component = volume.components.first else { return Data() }

        let bytesPerPixel = descriptor.bitsAllocated / 8
        let expectedSize = descriptor.rows * descriptor.columns * descriptor.numberOfFrames * bytesPerPixel

        if component.data.count >= expectedSize {
            return component.data.prefix(expectedSize)
        }

        // Pad if needed
        var result = component.data
        result.append(Data(count: expectedSize - component.data.count))
        return result
    }

    private func floorLog2(_ n: Int) -> Int {
        guard n > 1 else { return 0 }
        return Int(log2(Double(n)))
    }
}

// MARK: - Thread-safe box for async→sync bridging

/// A mutable box that can be sent across concurrency domains.
/// Used internally to bridge `JP3DEncoder`/`JP3DDecoder` async APIs
/// to the synchronous `ImageCodec` protocol.
private final class UnsafeSendableBox<T>: @unchecked Sendable {
    var value: T?
}
