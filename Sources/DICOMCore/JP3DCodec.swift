// NEMA-verified: 2026a, checked 2026-09-25 — carries no DICOM-standard data. The two UIDs are private (1.2.826.0.1.3680043.10.511.x), not in PS3.6 2026a Table A-1; JP3D has no standard transfer syntax. C1 classification confirmed.

import Foundation
import Synchronization
import SwiftJ2K
import SwiftJ2K3D

/// JP3D volumetric JPEG 2000 codec for DICOM multi-frame data backed by `SwiftJ2K3D` Contract **API-13**.
///
/// `JP3DCodec` wraps `SwiftJ2K3D`'s `VolumeEncoder`, `VolumeDecoder`, and `VolumeTranscoder`
/// (`SwiftJ2K` 12.2.0+) to provide volumetric compression, decompression, bounded structural
/// inspection, 3D region-of-interest decoding, and wavelet-domain `J2K ↔ HTJ2K` transcoding
/// under experimental private JP3D transfer syntaxes.
///
/// ## Transfer Syntaxes
///
/// JP3D has **no standard DICOM transfer syntax**. This codec uses private
/// vendor extension UIDs:
/// - `1.2.826.0.1.3680043.10.511.1` — JP3D Lossless (experimental)
/// - `1.2.826.0.1.3680043.10.511.2` — JP3D Lossy (experimental)
public final class JP3DCodec: ImageCodec, ImageEncoder, DecodeBackendConfigurableCodec, Sendable {
    public static let engineName = "SwiftJ2K3D"
    public static let engineVersion = "12.2.0"

    /// Private experimental JP3D transfer syntax UIDs.
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.jp3dLossless.uid,
        TransferSyntax.jp3dLossy.uid
    ]

    /// Private experimental JP3D encoding transfer syntax UIDs.
    public static let supportedEncodingTransferSyntaxes: [String] = supportedTransferSyntaxes

    /// The compression mode to use for encoding.
    public enum CompressionMode: Sendable, Equatable {
        /// Lossless compression (bit-exact 5/3 reversible wavelet reconstruction).
        case lossless
        /// Lossless compression using the HTJ2K (Part 15) block coder.
        case losslessHTJ2K
        /// Lossy compression with target PSNR (dB).
        case lossy(psnr: Double = 40.0)
        /// Lossy HTJ2K compression with target PSNR (dB).
        case lossyHTJ2K(psnr: Double = 40.0)

        public var isLossless: Bool {
            switch self {
            case .lossless, .losslessHTJ2K: return true
            case .lossy, .lossyHTJ2K: return false
            }
        }

        public var isHTJ2K: Bool {
            switch self {
            case .losslessHTJ2K, .lossyHTJ2K: return true
            case .lossless, .lossy: return false
            }
        }

        var jp3dMode: JP3DCompressionMode {
            switch self {
            case .lossless: return .lossless
            case .losslessHTJ2K: return .losslessHTJ2K
            case .lossy(let psnr): return .lossy(psnr: psnr)
            case .lossyHTJ2K(let psnr): return .lossyHTJ2K(psnr: psnr)
            }
        }
    }

    /// The compression mode configured on this codec instance.
    public let compressionMode: CompressionMode

    /// Optional backend preference applied during volumetric decode.
    public let decodeBackend: CodecBackend?

    /// Bounded resource limits enforced across `VolumeEncoder`, `VolumeDecoder`, and `VolumeTranscoder`.
    public let resourceLimits: ResourceLimits

    /// Creates a JP3D codec with the specified compression mode, backend preference, and resource limits.
    public init(
        compressionMode: CompressionMode = .lossless,
        decodeBackend: CodecBackend? = nil,
        resourceLimits: ResourceLimits = .default
    ) {
        self.compressionMode = compressionMode
        self.decodeBackend = decodeBackend
        self.resourceLimits = resourceLimits
    }

    public func withDecodeBackend(_ decodeBackend: CodecBackend?) -> any ImageCodec {
        JP3DCodec(
            compressionMode: compressionMode,
            decodeBackend: decodeBackend,
            resourceLimits: resourceLimits
        )
    }

    // MARK: - Volumetric API (Contract API-13)

    /// Encodes a complete volume of multi-frame pixel data to a JP3D codestream.
    ///
    /// - Parameters:
    ///   - data: Concatenated pixel data for all frames (frame-major order, little-endian).
    ///   - descriptor: Pixel data descriptor describing the volume geometry.
    ///   - spacing: Optional voxel spacing `(x, y, z)` in mm preserved in JP3D volume geometry metadata.
    ///   - origin: Optional patient-space origin `(x, y, z)` in mm preserved in JP3D volume geometry metadata.
    /// - Returns: The JP3D compressed codestream.
    public func encodeVolume(
        _ data: Data,
        descriptor: PixelDataDescriptor,
        spacing: (x: Double, y: Double, z: Double)? = nil,
        origin: (x: Double, y: Double, z: Double)? = nil
    ) async throws -> Data {
        try await encodeVolumeWithReport(
            data,
            descriptor: descriptor,
            spacing: spacing,
            origin: origin
        ).data
    }

    /// Encodes a complete volume of multi-frame pixel data to a JP3D codestream and returns the full `EncodedVolume` telemetry report.
    public func encodeVolumeWithReport(
        _ data: Data,
        descriptor: PixelDataDescriptor,
        spacing: (x: Double, y: Double, z: Double)? = nil,
        origin: (x: Double, y: Double, z: Double)? = nil,
        forcedBackend: CodecBackend? = nil
    ) async throws -> EncodedVolume {
        do {
            let volume = try makeVolume(from: data, descriptor: descriptor, spacing: spacing, origin: origin)
            let config = try VolumeEncoderConfiguration(
                compressionMode: compressionMode.jp3dMode,
                tiling: .default,
                progressionOrder: .lrcps,
                qualityLayers: compressionMode.isLossless ? 1 : 3,
                levelsX: min(3, floorLog2(descriptor.columns)),
                levelsY: min(3, floorLog2(descriptor.rows)),
                levelsZ: min(1, floorLog2(descriptor.numberOfFrames)),
                zDelta: .disabled
            )
            let encoder = try VolumeEncoder(configuration: config)
            let options = VolumeEncodeOptions(
                resourceLimits: effectiveResourceLimits(forByteCount: data.count),
                executionPolicy: Self.executionPolicy(for: forcedBackend ?? decodeBackend),
                copyPolicy: .allowCopy,
                metadataPolicy: .preserve
            )
            return try await encoder.encode(volume, options: options)
        } catch {
            throw SwiftJ2KSyncBridge.translateError(error)
        }
    }

    /// Decodes a JP3D codestream back to concatenated multi-frame DICOM pixel data.
    public func decodeVolume(
        _ data: Data,
        descriptor: PixelDataDescriptor
    ) async throws -> Data {
        do {
            let decoder = try VolumeDecoder(configuration: VolumeDecoderConfiguration())
            let expectedDecoded = descriptor.bytesPerFrame * max(1, descriptor.numberOfFrames)
            let options = VolumeDecodeOptions(
                resourceLimits: effectiveResourceLimits(forByteCount: max(data.count, expectedDecoded)),
                executionPolicy: Self.executionPolicy(for: decodeBackend),
                copyPolicy: .allowCopy,
                metadataPolicy: .preserve
            )
            let decoded = try await decoder.decode(data, options: options)
            return extractPixelData(
                from: decoded.volume,
                bitsAllocated: descriptor.bitsAllocated,
                expectedFrameRows: descriptor.rows,
                expectedFrameColumns: descriptor.columns,
                expectedFrames: descriptor.numberOfFrames
            )
        } catch {
            throw SwiftJ2KSyncBridge.translateError(error)
        }
    }

    /// Decodes a 3D sub-region (`JP3DRegion`) from a JP3D codestream without reconstructing non-intersecting tiles.
    public func decodeVolumeRegion(
        _ data: Data,
        descriptor: PixelDataDescriptor,
        region: JP3DRegion,
        resolutionLevel: Int = 0,
        maxQualityLayers: Int = 0
    ) async throws -> (data: Data, width: Int, height: Int, depth: Int) {
        guard !region.isEmpty else {
            throw DICOMError.parsingFailed("JP3D ROI region must have positive width, height, and depth")
        }
        do {
            let config = try VolumeDecoderConfiguration(
                maxQualityLayers: maxQualityLayers,
                resolutionLevel: resolutionLevel,
                tolerateTruncation: false
            )
            let decoder = try VolumeDecoder(configuration: config)
            let expectedDecoded = region.voxelCount * max(1, descriptor.bitsAllocated / 8)
            let options = VolumeDecodeOptions(
                resourceLimits: effectiveResourceLimits(forByteCount: max(data.count, expectedDecoded)),
                executionPolicy: Self.executionPolicy(for: decodeBackend),
                copyPolicy: .allowCopy,
                metadataPolicy: .preserve,
                regionOfInterest: region
            )
            let decoded = try await decoder.decode(data, options: options)
            let vol = decoded.volume
            let extracted = extractPixelData(
                from: vol,
                bitsAllocated: descriptor.bitsAllocated,
                expectedFrameRows: vol.height,
                expectedFrameColumns: vol.width,
                expectedFrames: vol.depth
            )
            return (extracted, vol.width, vol.height, vol.depth)
        } catch {
            throw SwiftJ2KSyncBridge.translateError(error)
        }
    }

    /// Performs bounded structural header inspection of a JP3D codestream without decoding voxel payloads.
    public func inspectVolume(_ data: Data) throws -> VolumeInfo {
        do {
            let decoder = try VolumeDecoder()
            let options = VolumeDecodeOptions(
                resourceLimits: effectiveResourceLimits(forByteCount: data.count),
                executionPolicy: Self.executionPolicy(for: decodeBackend),
                copyPolicy: .allowCopy,
                metadataPolicy: .preserve
            )
            return try decoder.inspect(data, options: options)
        } catch {
            throw SwiftJ2KSyncBridge.translateError(error)
        }
    }

    /// Transcodes a JP3D volumetric codestream between Part 1 (EBCOT) and Part 15 (HTJ2K) in the wavelet domain.
    public func transcodeVolume(
        _ data: Data,
        toHTJ2K: Bool
    ) async throws -> Data {
        do {
            let transcoder = try VolumeTranscoder()
            let options = TranscodeOptions(
                resourceLimits: effectiveResourceLimits(forByteCount: data.count),
                executionPolicy: Self.executionPolicy(for: decodeBackend),
                copyPolicy: .allowCopy,
                metadataPolicy: .preserve
            )
            let result = try await transcoder.transcode(
                data,
                to: toHTJ2K ? .htj2k : .jpeg2000,
                options: options
            )
            return result.data
        } catch {
            throw SwiftJ2KSyncBridge.translateError(error)
        }
    }

    // MARK: - ImageCodec Protocol

    /// Decodes a complete JP3D codestream synchronously to concatenated multi-frame pixel data.
    public func decode(_ data: Data, descriptor: PixelDataDescriptor) throws -> Data {
        let bridgeOptions = SwiftJ2KProviderOptions(resourceLimits: resourceLimits)
        return try SwiftJ2KSyncBridge.run(options: bridgeOptions) { [self] in
            try await decodeVolume(data, descriptor: descriptor)
        }
    }

    /// Decodes a single frame from JP3D compressed data using 3D ROI slice extraction.
    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        guard frameIndex >= 0, frameIndex < descriptor.numberOfFrames else {
            throw DICOMError.parsingFailed(
                "Frame \(frameIndex) out of bounds in volume with \(descriptor.numberOfFrames) frame(s)"
            )
        }
        let bridgeOptions = SwiftJ2KProviderOptions(resourceLimits: resourceLimits)
        return try SwiftJ2KSyncBridge.run(options: bridgeOptions) { [self] in
            let info = try inspectVolume(frameData)
            guard frameIndex < info.depth else {
                throw DICOMError.parsingFailed(
                    "Frame \(frameIndex) out of bounds in decoded volume of depth \(info.depth)"
                )
            }
            let region = JP3DRegion(
                x: 0..<descriptor.columns,
                y: 0..<descriptor.rows,
                z: frameIndex..<(frameIndex + 1)
            )
            let slice = try await decodeVolumeRegion(
                frameData,
                descriptor: descriptor,
                region: region
            )
            return slice.data
        }
    }

    // MARK: - ImageEncoder Protocol

    /// Whether volumetric JP3D encoding is supported for the given configuration and descriptor.
    public func canEncode(with configuration: DICOMCore.CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        guard descriptor.samplesPerPixel == 1 else { return false }
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else { return false }
        guard descriptor.bitsStored >= 1 && descriptor.bitsStored <= descriptor.bitsAllocated else { return false }
        guard descriptor.numberOfFrames > 1 else { return false }
        guard descriptor.rows > 0 && descriptor.columns > 0 else { return false }
        return true
    }

    /// Encodes a complete multi-frame volume into a single encapsulated JP3D codestream fragment.
    public func encode(
        _ data: Data,
        descriptor: PixelDataDescriptor,
        configuration: DICOMCore.CompressionConfiguration
    ) throws -> [Data] {
        guard canEncode(with: configuration, descriptor: descriptor) else {
            throw DICOMError.unsupportedTransferSyntax(
                "JP3D requires multi-frame 8-bit or 16-bit single-component pixel data"
            )
        }
        let effectiveMode: CompressionMode
        if configuration.preferLossless && !compressionMode.isLossless {
            effectiveMode = compressionMode.isHTJ2K ? .losslessHTJ2K : .lossless
        } else {
            effectiveMode = compressionMode
        }
        let encoder = JP3DCodec(
            compressionMode: effectiveMode,
            decodeBackend: configuration.forcedBackend ?? decodeBackend,
            resourceLimits: resourceLimits
        )
        let bridgeOptions = SwiftJ2KProviderOptions(resourceLimits: resourceLimits)
        let codestream = try SwiftJ2KSyncBridge.run(options: bridgeOptions) {
            try await encoder.encodeVolumeWithReport(
                data,
                descriptor: descriptor,
                forcedBackend: configuration.forcedBackend
            ).data
        }
        return [codestream]
    }

    /// Encodes a single frame (returns the raw frame data unchanged because JP3D is inherently volumetric;
    /// use `encodeVolume(_:descriptor:)` or `encode(_:descriptor:configuration:)` for volumetric compression).
    public func encodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        configuration: DICOMCore.CompressionConfiguration
    ) throws -> Data {
        guard descriptor.samplesPerPixel == 1,
              (descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16) else {
            throw DICOMError.unsupportedTransferSyntax(
                "JP3D requires 8-bit or 16-bit single-component pixel data"
            )
        }
        return frameData
    }

    // MARK: - Private Helpers

    private static func executionPolicy(for backend: CodecBackend?) -> ExecutionPolicy {
        guard let backend else { return .automatic }
        switch backend {
        case .scalar:
            return .required(.scalarCPU)
        case .accelerate, .metal:
            return .preferred(.accelerated)
        }
    }

    private func effectiveResourceLimits(forByteCount byteCount: Int) -> ResourceLimits {
        let base = resourceLimits
        let neededDecoded = max(base.maximumDecodedBytes, byteCount * 2)
        let neededWorkspace = max(base.maximumWorkspaceBytes, byteCount * 4)
        let neededMemory = max(base.maximumMemoryBytes, neededDecoded + neededWorkspace)
        if neededDecoded == base.maximumDecodedBytes
            && neededWorkspace == base.maximumWorkspaceBytes
            && neededMemory == base.maximumMemoryBytes {
            return base
        }
        return (try? ResourceLimits(
            maximumCompressedBytes: max(base.maximumCompressedBytes, byteCount * 2),
            maximumDecodedBytes: neededDecoded,
            maximumWorkspaceBytes: neededWorkspace,
            maximumPixels: base.maximumPixels,
            maximumDimension: base.maximumDimension,
            maximumFrames: base.maximumFrames,
            maximumMetadataBytes: base.maximumMetadataBytes,
            maximumICCBytes: base.maximumICCBytes,
            maximumNestingDepth: base.maximumNestingDepth,
            maximumWorkers: base.maximumWorkers,
            deadlineSeconds: base.deadlineSeconds,
            maximumMemoryBytes: neededMemory
        )) ?? base
    }

    private func makeVolume(
        from data: Data,
        descriptor: PixelDataDescriptor,
        spacing: (x: Double, y: Double, z: Double)?,
        origin: (x: Double, y: Double, z: Double)?
    ) throws -> J2KVolume {
        guard descriptor.rows > 0, descriptor.columns > 0, descriptor.numberOfFrames > 0 else {
            throw DICOMError.parsingFailed(
                "Invalid JP3D volume dimensions: \(descriptor.columns)x\(descriptor.rows)x\(descriptor.numberOfFrames)"
            )
        }
        guard descriptor.samplesPerPixel == 1 else {
            throw DICOMError.unsupportedTransferSyntax(
                "JP3D currently supports single-component (grayscale) volumes, got \(descriptor.samplesPerPixel) samples/pixel"
            )
        }
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
            throw DICOMError.unsupportedTransferSyntax(
                "JP3D supports 8-bit or 16-bit allocated voxels, got \(descriptor.bitsAllocated)"
            )
        }

        let voxelCount = descriptor.columns * descriptor.rows * descriptor.numberOfFrames
        let dicomBytesPerSample = descriptor.bitsAllocated / 8
        let expectedDICOMBytes = voxelCount * dicomBytesPerSample
        guard data.count >= expectedDICOMBytes else {
            throw DICOMError.parsingFailed(
                "JP3D input pixel data too short: expected \(expectedDICOMBytes) bytes, got \(data.count)"
            )
        }

        let bitDepth = max(1, min(descriptor.bitsAllocated, descriptor.bitsStored))
        let componentBytesPerSample = (bitDepth + 7) / 8
        let componentData: Data
        if dicomBytesPerSample == 2 && componentBytesPerSample == 1 {
            // Narrow 16-bit DICOM words carrying <=8-bit samples into 1-byte component storage.
            var narrowed = Data(count: voxelCount)
            data.withUnsafeBytes { src in
                narrowed.withUnsafeMutableBytes { dst in
                    guard let s = src.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let d = dst.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    for i in 0..<voxelCount {
                        d[i] = s[i * 2]
                    }
                }
            }
            componentData = narrowed
        } else if data.count == expectedDICOMBytes {
            componentData = data
        } else {
            componentData = data.prefix(expectedDICOMBytes)
        }

        let component = J2KVolumeComponent(
            index: 0,
            bitDepth: bitDepth,
            signed: descriptor.isSigned,
            width: descriptor.columns,
            height: descriptor.rows,
            depth: descriptor.numberOfFrames,
            data: componentData
        )
        return J2KVolume(
            width: descriptor.columns,
            height: descriptor.rows,
            depth: descriptor.numberOfFrames,
            components: [component],
            spacingX: spacing?.x ?? 1.0,
            spacingY: spacing?.y ?? 1.0,
            spacingZ: spacing?.z ?? 1.0,
            originX: origin?.x ?? 0.0,
            originY: origin?.y ?? 0.0,
            originZ: origin?.z ?? 0.0
        )
    }

    private func extractPixelData(
        from volume: J2KVolume,
        bitsAllocated: Int,
        expectedFrameRows: Int,
        expectedFrameColumns: Int,
        expectedFrames: Int
    ) -> Data {
        guard let component = volume.components.first else { return Data() }

        let dicomBytesPerSample = max(1, bitsAllocated / 8)
        let compBytesPerSample = max(1, (component.bitDepth + 7) / 8)
        let voxelCount = expectedFrameRows * expectedFrameColumns * expectedFrames
        let expectedSize = voxelCount * dicomBytesPerSample

        if dicomBytesPerSample == 2 && compBytesPerSample == 1 {
            var widened = Data(count: expectedSize)
            component.data.withUnsafeBytes { src in
                widened.withUnsafeMutableBytes { dst in
                    guard let s = src.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let d = dst.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    let limit = min(voxelCount, src.count)
                    for i in 0..<limit {
                        if component.signed {
                            let signedVal = Int16(Int8(bitPattern: s[i]))
                            let raw = UInt16(bitPattern: signedVal)
                            d[i * 2] = UInt8(truncatingIfNeeded: raw)
                            d[i * 2 + 1] = UInt8(truncatingIfNeeded: raw >> 8)
                        } else {
                            d[i * 2] = s[i]
                            d[i * 2 + 1] = 0
                        }
                    }
                }
            }
            return widened
        }

        if component.data.count >= expectedSize {
            return Data(component.data.prefix(expectedSize))
        }

        var result = component.data
        result.append(Data(count: expectedSize - component.data.count))
        return result
    }

    private func floorLog2(_ n: Int) -> Int {
        guard n > 1 else { return 0 }
        return Int(log2(Double(n)))
    }
}
