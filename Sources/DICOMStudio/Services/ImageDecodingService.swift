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
            backend: CodecRegistry.shared.activeBackend,
            decodeTimeMs: max(0, elapsedMs)
        )
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
    /// The stream yields three frames in order:
    /// 1. **Quarter resolution** (1/4 scale) — fast visual preview.
    /// 2. **Half resolution** (1/2 scale) — intermediate refinement.
    /// 3. **Full resolution** — final, highest-quality image.
    ///
    /// Since `J2KDecoder.decodeResolution` is not yet available upstream
    /// (see `J2KSWIFT_BUG_REPORT.md`), this method decodes to full resolution
    /// once and then post-processes downscaled previews via `CGContext`.
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
            Task.detached {
                let start = Date()
                // Decode the full-resolution CGImage once, through the PS3.4
                // N.2 chain shared with export and the viewer: the Modality
                // LUT, then the window applied to its output.
                let fullImage: CGImage?
                if let pixelData = file.pixelData() {
                    let explicit = windowCenter != nil && windowWidth != nil
                    fullImage = try? DICOMImageExporter.renderFrameForExport(
                        file: file, pixelData: pixelData, frameIndex: 0,
                        applyWindow: explicit, windowCenter: windowCenter, windowWidth: windowWidth)
                } else {
                    fullImage = nil
                }
                let decodeMs = Date().timeIntervalSince(start) * 1000.0

                guard let full = fullImage else {
                    continuation.finish()
                    return
                }

                let fullW = full.width
                let fullH = full.height

                // Yield quarter and half resolution previews by downscaling via CGContext.
                for level in [ProgressiveDecodeLevel.quarter, .half] {
                    if let scaled = Self.scale(image: full,
                                               toWidth: max(1, Int(Double(fullW) * level.scaleFactor)),
                                               height:  max(1, Int(Double(fullH) * level.scaleFactor))) {
                        continuation.yield((level, scaled, decodeMs))
                    }
                }

                // Yield full-resolution last.
                continuation.yield((.full, full, decodeMs))
                continuation.finish()
            }
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
