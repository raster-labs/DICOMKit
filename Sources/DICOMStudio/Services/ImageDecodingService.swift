// ImageDecodingService.swift
// DICOMStudio
//
// DICOM Studio — Codec-aware image decoding service (Phase 8 / J2KSwift v3 integration)
//
// Routes pixel data extraction through `CodecRegistry` and records timing and
// backend metadata so the codec inspector panel can display them.
//
// NEMA-verified: 2026a, checked 2026-10-05 — the progressive previews are now rendered through `DICOMImageExporter.renderFrameForExport`, the PS3.4 2026a N.2 chain (Modality LUT, then the window in modality units, PS3.3 C.11.2.1.2.1), where they used `DICOMFile.renderFrame(_:window:)` / `renderFrameWithStoredWindow` (header window on stored values, D65): corrected, and the window parameters are documented as modality units; the default Transfer Syntax when the file names none is Explicit VR Little Endian 1.2.840.10008.1.2.1 (PS3.6 Table A-1) via DICOMCore; codec names are the codec pass's (ImageMetadata / CodecInspectorHelpers); checked by Scripts/diff_studio_g2_viewer.py

import Foundation
import DICOMKit
import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - DecodedImageResult

/// The result of a codec-aware pixel data extraction.
public struct DecodedImageResult: Sendable {
    /// The decoded pixel data.
    public let pixelData: PixelData
    /// Transfer syntax UID used.
    public let transferSyntaxUID: String
    /// Human-readable codec name.
    public let codecName: String
    /// Active hardware backend.
    public let backend: CodecBackend
    /// Decode wall-clock time in milliseconds.
    public let decodeTimeMs: Double
}

// MARK: - ImageDecodingService

/// A codec-aware image decoding service that routes pixel data extraction
/// through `CodecRegistry` and records timing and backend metadata.
///
/// Use this service when you need to know which codec was used, how long
/// decoding took, and which hardware backend was active — for example to
/// populate the ``CodecInspectorViewModel``.
public final class ImageDecodingService: Sendable {

    public init() {}

    // MARK: - Decode

    /// Extracts and decodes pixel data from a DICOM file, recording codec metadata.
    ///
    /// - Parameter file: The parsed `DICOMFile`.
    /// - Returns: A `DecodedImageResult` if pixel data is available, otherwise `nil`.
    public func decode(file: DICOMFile) -> DecodedImageResult? {
        let tsUID = file.transferSyntaxUID ?? TransferSyntax.explicitVRLittleEndian.uid
        let start = Date()
        guard let pixData = file.pixelData() else { return nil }
        let elapsedMs = Date().timeIntervalSince(start) * 1000.0

        return DecodedImageResult(
            pixelData: pixData,
            transferSyntaxUID: tsUID,
            codecName: CodecInspectorHelpers.codecDisplayName(for: tsUID),
            backend: Self.effectiveDecodeBackend(for: tsUID, descriptor: pixData.descriptor),
            decodeTimeMs: max(0, elapsedMs)
        )
    }

    /// Resolves the hardware backend that actually executed (or would execute) a decode for
    /// `transferSyntaxUID` and `descriptor`, rather than stamping `CodecRegistry.shared.activeBackend`
    /// globally onto non-JPEG 2000 codecs that have no Metal GPU decode path.
    public static func effectiveDecodeBackend(
        for transferSyntaxUID: String,
        descriptor: PixelDataDescriptor,
        forcedBackend: CodecBackend? = nil
    ) -> CodecBackend {
        guard let ts = TransferSyntax.from(uid: transferSyntaxUID), ts.isEncapsulated else {
            return .scalar
        }
        let cpuBackend: CodecBackend = {
            if forcedBackend == .scalar { return .scalar }
            return CodecBackendProbe.isAvailable(.accelerate) ? .accelerate : .scalar
        }()

        if ts.isJPEG2000 {
            let (pixels, overflow) = descriptor.rows.multipliedReportingOverflow(by: descriptor.columns)
            let pixelCount = overflow ? Int.max : pixels
            switch J2KRoutePlanner.planDecode(backend: forcedBackend, pixelCount: pixelCount) {
            case .gpu, .gpuHT:
                return CodecBackendProbe.isAvailable(.metal) ? .metal : cpuBackend
            case .cpu:
                return cpuBackend
            }
        }

        if ts.isJPEG || ts.isJPEGLS || ts.isJPEGXL {
            return cpuBackend
        }

        // RLE Lossless and per-frame Deflate run pure CPU byte-plane / stream codecs.
        return .scalar
    }

    // MARK: - Inspector status (metadata only)

    /// Derives a `CodecInspectorStatus` for a given `DICOMFile` by inspecting
    /// metadata only — does **not** decode pixel data.
    ///
    /// Use this to pre-populate the inspector panel before decoding starts.
    public func inspectorStatus(for file: DICOMFile) -> CodecInspectorStatus {
        guard let tsUID = file.transferSyntaxUID else {
            let desc = TransferSyntax.explicitVRLittleEndian.description
            return .uncompressed(transferSyntaxDescription: desc)
        }

        let ts = TransferSyntax.from(uid: tsUID)

        // Uncompressed transfer syntaxes never need a codec.
        if let ts, !ts.isEncapsulated {
            return .uncompressed(transferSyntaxDescription: ts.description)
        }

        guard CodecRegistry.shared.hasCodec(for: tsUID) else {
            return .unsupportedCodec(transferSyntaxUID: tsUID)
        }

        // A codec is registered — signal that decoding is about to begin.
        return .decoding
    }

    // MARK: - Progressive Decode (Phase 8)

    #if canImport(CoreGraphics)
    /// Returns an `AsyncStream` that yields CGImages at progressive resolution levels
    /// for JPEG 2000 and HTJ2K compressed DICOM files.
    ///
    /// Streams coarse reduced-resolution wavelet reconstructions first via `SwiftJ2K`
    /// (`DICOMFile.pixelDataProgressive(frame:coarseLevels:)`) — quarter resolution
    /// (`level == 2`), then half resolution (`level == 1`) when present in the codestream —
    /// followed by the exact full-resolution frame (`level == 0`). If a tiny codestream
    /// omits coarse decomposition levels, downscaled previews are synthesized from the
    /// final frame so the 3-stage UI progression stays uniform.
    ///
    /// For non-J2K or uncompressed files the stream finishes immediately without
    /// yielding any value; the caller should fall back to the synchronous
    /// ``decode(file:)`` path.
    ///
    /// - Parameters:
    ///   - file: The parsed `DICOMFile`.
    ///   - windowCenter: Window Center for rendering, in the units the file's
    ///     Modality LUT puts out (PS3.3 C.11.2.1.2.1; HU on CT). nil = the
    ///     file's own VOI.
    ///   - windowWidth: Window Width in the same units (nil = the file's own).
    /// - Returns: `AsyncStream` of `(ProgressiveDecodeLevel, CGImage, Double)` triples —
    ///   level, the rendered image at that level, and the cumulative decode time in ms.
    public func decodeProgressively(
        file: DICOMFile,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil
    ) -> AsyncStream<(ProgressiveDecodeLevel, CGImage, Double)> {
        AsyncStream { continuation in
            // Only engage for J2K/HTJ2K transfer syntaxes.
            let tsUID = file.transferSyntaxUID ?? ""
            guard ProgressiveDecodeHelpers.isJ2KTransferSyntax(tsUID) else {
                continuation.finish()
                return
            }

            // Dispatch all decode work off the calling actor so that callers
            // running on @MainActor (e.g. ImageViewerViewModel) do not block
            // the main thread. AsyncStream.Continuation is Sendable, so it
            // is safe to transfer into Task.detached.
            let worker = Task.detached {
                let start = Date()
                let explicit = windowCenter != nil && windowWidth != nil
                var yieldedQuarter = false
                var yieldedHalf = false

                do {
                    let stream = file.pixelDataProgressive(frame: 0, coarseLevels: [2, 1])
                    for try await update in stream {
                        if Task.isCancelled { break }
                        guard let rendered = try? DICOMImageExporter.renderFrameForExport(
                            file: file,
                            pixelData: update.pixelData,
                            frameIndex: 0,
                            applyWindow: explicit,
                            windowCenter: windowCenter,
                            windowWidth: windowWidth
                        ) else {
                            continue
                        }
                        let elapsedMs = max(0, Date().timeIntervalSince(start) * 1000.0)
                        if update.isFinal {
                            let fullW = rendered.width
                            let fullH = rendered.height
                            if !yieldedQuarter,
                               let q = Self.scale(image: rendered,
                                                  toWidth: max(1, Int(Double(fullW) * ProgressiveDecodeLevel.quarter.scaleFactor)),
                                                  height: max(1, Int(Double(fullH) * ProgressiveDecodeLevel.quarter.scaleFactor))) {
                                continuation.yield((.quarter, q, elapsedMs))
                            }
                            if !yieldedHalf,
                               let h = Self.scale(image: rendered,
                                                  toWidth: max(1, Int(Double(fullW) * ProgressiveDecodeLevel.half.scaleFactor)),
                                                  height: max(1, Int(Double(fullH) * ProgressiveDecodeLevel.half.scaleFactor))) {
                                continuation.yield((.half, h, elapsedMs))
                            }
                            continuation.yield((.full, rendered, elapsedMs))
                        } else if update.resolutionLevel == 2 {
                            yieldedQuarter = true
                            continuation.yield((.quarter, rendered, elapsedMs))
                        } else if update.resolutionLevel == 1 {
                            yieldedHalf = true
                            continuation.yield((.half, rendered, elapsedMs))
                        }
                    }
                } catch {
                    // Unreadable/corrupt codestream finishes stream cleanly without crashing viewer.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    /// Scales a `CGImage` to the given pixel dimensions using a `CGContext`.
    ///
    /// Returns `nil` if the context cannot be created (e.g. unsupported pixel format).
    private static func scale(image: CGImage, toWidth width: Int, height: Int) -> CGImage? {
        guard let colorSpace = image.colorSpace else { return nil }
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
    #endif
}
