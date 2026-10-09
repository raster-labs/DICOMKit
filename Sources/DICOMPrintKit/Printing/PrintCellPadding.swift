// NEMA-verified: 2026a, checked 2026-09-29 — MONOCHROME1 background (maximum value black) per PS3.3 2026a C.7.6.3.1.2; 8-bit image box pixels per Table C.13-5; no other standard data
// PrintCellPadding.swift
// DICOMPrintKit
//
// Letterboxing a prepared frame to the shape of the film cell it will occupy.
//
// The preview holds the corner identification to the corners of the *cell* —
// where the eye goes on a light box — but on the wire the image box is all
// there is to draw into. A fitted picture of a different shape than its cell is
// centred by the printer inside a letterbox, and a caption burned into the
// picture's corners floats against that margin instead of sitting at the
// cell's. Widening the frame to the cell's own shape first — with the same
// black the printer letterboxes with — puts the picture exactly where the
// printer would have put it and gives the caption the cell's corners to land
// in, so the film reads as the preview promised.
//
// Only meaningful under fit scaling. Fill and stretch cover the cell, so there
// is no letterbox to cross; padding a true-size frame would change the
// physical size the film was asked to hold. The caller owns that decision.

import Foundation
import DICOMNetwork

public extension PreparedPrintImage {

    /// A copy widened (or deepened) with background to the given cell shape,
    /// the original pixels centred — the placement a printer letterboxes a
    /// fitted image into, done here so burned corner text lands at the cell's
    /// corners rather than the picture's.
    ///
    /// The padding is film background: minimum stored value for MONOCHROME2 and
    /// RGB, maximum for MONOCHROME1 — black on the film either way, and exactly
    /// what the letterbox the printer no longer needs to add would have shown.
    ///
    /// Returns the frame unchanged when there is nothing to do (the frame is
    /// already at least as wide as the cell's shape on both axes' proportion),
    /// or when the pixels are not the 8-bit grayscale or RGB an image box is
    /// prepared into — the same quiet refusal ``ImageAnnotationBurner`` makes,
    /// for the same reason: an unexpected format is a reason to print the
    /// picture as it is, never a reason to fail the job.
    ///
    /// - Parameter aspectRatio: the cell's width divided by its height.
    func padded(toCellAspectRatio aspectRatio: Double) -> PreparedPrintImage {
        let descriptor = self.descriptor
        guard aspectRatio.isFinite, aspectRatio > 0,
              descriptor.bitsAllocated == 8,
              descriptor.rows > 0, descriptor.columns > 0 else { return self }

        let width = Int(descriptor.columns)
        let height = Int(descriptor.rows)
        let samples = Int(descriptor.samplesPerPixel)
        guard samples == 1 || samples == 3 else { return self }
        guard descriptor.pixelData.count >= width * height * samples else { return self }

        // Grow exactly one axis to the cell's proportion; the picture is never
        // shrunk and never cropped — padding is all this does.
        let imageAspect = Double(width) / Double(height)
        var paddedWidth = width
        var paddedHeight = height
        if imageAspect < aspectRatio {
            paddedWidth = Int((Double(height) * aspectRatio).rounded())
        } else {
            paddedHeight = Int((Double(width) / aspectRatio).rounded())
        }
        guard paddedWidth > width || paddedHeight > height else { return self }
        guard paddedWidth <= Int(UInt16.max), paddedHeight <= Int(UInt16.max) else {
            return self
        }

        // Film background, as these pixels express it: MONOCHROME1's maximum
        // stored value is black.
        let isInverted = descriptor.photometricInterpretation
            .uppercased().hasPrefix("MONOCHROME1")
        let background: UInt8 = isInverted
            ? UInt8(clamping: (1 << max(1, min(8, Int(descriptor.bitsStored)))) - 1)
            : 0

        let sourceRowBytes = width * samples
        let paddedRowBytes = paddedWidth * samples
        let offsetX = ((paddedWidth - width) / 2) * samples
        let offsetY = (paddedHeight - height) / 2

        var padded = [UInt8](repeating: background,
                             count: paddedRowBytes * paddedHeight)
        descriptor.pixelData.withUnsafeBytes { raw in
            guard let source = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            padded.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                let destination = base.assumingMemoryBound(to: UInt8.self)
                for row in 0..<height {
                    (destination + (offsetY + row) * paddedRowBytes + offsetX)
                        .update(from: source + row * sourceRowBytes,
                                count: sourceRowBytes)
                }
            }
        }

        // The padding is more pixels of the same physical size, so the spacing
        // rides along unchanged — a padded frame's physical width grows with
        // its columns, which is what keeps the anatomy true.
        return PreparedPrintImage(
            descriptor: PrintImageData(
                pixelData: Data(padded),
                rows: UInt16(paddedHeight),
                columns: UInt16(paddedWidth),
                bitsAllocated: descriptor.bitsAllocated,
                bitsStored: descriptor.bitsStored,
                highBit: descriptor.highBit,
                samplesPerPixel: descriptor.samplesPerPixel,
                pixelRepresentation: descriptor.pixelRepresentation,
                photometricInterpretation: descriptor.photometricInterpretation
            ),
            sourcePath: sourcePath,
            frameIndex: frameIndex,
            rowSpacingMillimeters: rowSpacingMillimeters,
            columnSpacingMillimeters: columnSpacingMillimeters
        )
    }
}
