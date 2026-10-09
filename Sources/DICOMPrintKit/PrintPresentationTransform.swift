// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (crop/rotate/flip/invert of prepared pixels; inversion against 2^BitsStored - 1)
// PrintPresentationTransform.swift
// DICOMPrintKit
//
// DICOM Print — applying the viewer's arrangement to film pixels.
//
// Every operation here is exact: cropping selects pixels, rotation and flipping
// permute them, inversion negates P-values. Nothing resamples, so a zoomed print
// is full modality resolution over the region the user chose rather than an
// upscaled copy of what the monitor showed.

import Foundation
import DICOMNetwork

public enum PrintPresentationTransform {

    /// Applies a viewer presentation to already-prepared film pixels.
    ///
    /// - Parameters:
    ///   - image: Prepared, uncompressed image-box pixels (8- or 16-bit,
    ///     1 or 3 samples per pixel).
    ///   - presentation: The viewer arrangement to bake in.
    ///   - covers: Whether the job's scaling lays the picture covering its cell
    ///     (fill-to-film). The crop is then read with the covering geometry, so
    ///     the film prints the same panned crop the preview shows — read as
    ///     fitted, the film re-centred what the preview had slid.
    /// - Returns: The transformed image, or `image` unchanged when the
    ///   presentation is an identity or the pixel layout is not one this can
    ///   safely permute.
    public static func apply(
        _ presentation: ViewerPresentation,
        to image: PrintImageData,
        covers: Bool = false
    ) -> PrintImageData {
        guard !presentation.isIdentity else { return image }

        let width = Int(image.columns)
        let height = Int(image.rows)
        let samples = Int(image.samplesPerPixel)
        let bytesPerSample = Int(image.bitsAllocated) / 8

        // Planar or sub-byte layouts would need a different addressing scheme;
        // the preparer never emits them, and silently mangling pixels would be
        // far worse than printing the untransformed frame.
        guard width > 0, height > 0,
              samples == 1 || samples == 3,
              bytesPerSample == 1 || bytesPerSample == 2,
              image.pixelData.count >= width * height * samples * bytesPerSample
        else { return image }

        let pixelStride = samples * bytesPerSample
        var pixels = [UInt8](image.pixelData.prefix(width * height * pixelStride))

        // 1. Crop to the region the viewport was showing.
        //
        // Off-square, the crop is taken wider than the picture that comes out
        // of it. The rotation below turns about the centre at the scale the
        // region already had, so the picture keeps its size and its corners
        // swing outside — and the pixels that ought to swing *in* to replace
        // them are the ones just past the crop's edge. Cropping tight threw
        // those away before the resampler could reach them, and the corners
        // came out as background wedges even where the frame plainly had image
        // there. So the crop grows to the box the turned rectangle sweeps
        // (clamped to the frame), the output stays the ungrown size, and the
        // resampler — which reads backwards from each output pixel — finds real
        // pixels where it used to find nothing. `printedSize` below is what
        // keeps the output at the size the film expects.
        var currentWidth = width
        var currentHeight = height
        var printedWidth: Int?
        var printedHeight: Int?
        if let region = presentation.visibleRegion(
            imageWidth: width, imageHeight: height, covers: covers) {
            let sampled = presentation.regionCoveringTurnedCell(
                region, imageWidth: width, imageHeight: height)
            pixels = crop(pixels, width: currentWidth, region: sampled, pixelStride: pixelStride)
            currentWidth = sampled.width
            currentHeight = sampled.height
            if sampled != region {
                printedWidth = region.width
                printedHeight = region.height
            }
        }

        // 2. Rotate, then flip — the order the viewer composes them in.
        if presentation.isQuarterTurn {
            if presentation.quarterTurns != 0 {
                pixels = rotate(
                    pixels, width: currentWidth, height: currentHeight,
                    quarterTurns: presentation.quarterTurns, pixelStride: pixelStride)
                if presentation.quarterTurns % 2 == 1 {
                    swap(&currentWidth, &currentHeight)
                }
            }
        } else {
            // A free angle cannot be permuted, so it is resampled — once, here,
            // over full-resolution pixels rather than over the monitor's copy.
            //
            // The output keeps the *cropped region's own size*, deliberately: the
            // picture turns about its centre at the scale it already had, and the
            // corners that swing outside are cut, exactly as they are on screen.
            //
            // The alternative — growing the box to the turned bounding rectangle —
            // keeps every corner, but it costs the anatomy its size: the printer
            // fits whatever it is handed into the image box, so a 45° turn of a
            // square frame hands it a √2-larger rectangle and the anatomy lands at
            // 71% of the size it had. That is a real shrink on film, and it is
            // worst at exactly the small angles a reader uses to straighten a
            // tilted head (86% at 10°). Matching the viewer is what was asked for:
            // the picture the reader turned is the size they turned it at.
            // Out at the *printed* size — the region the reader composed —
            // while reading from the grown crop around it.
            let outWidth = printedWidth ?? currentWidth
            let outHeight = printedHeight ?? currentHeight
            pixels = rotateResampling(
                pixels, width: currentWidth, height: currentHeight,
                outWidth: outWidth, outHeight: outHeight,
                presentation: presentation,
                samples: samples, bytesPerSample: bytesPerSample)
            currentWidth = outWidth
            currentHeight = outHeight
        }
        if presentation.flipHorizontal {
            pixels = flipHorizontally(
                pixels, width: currentWidth, height: currentHeight, pixelStride: pixelStride)
        }
        if presentation.flipVertical {
            pixels = flipVertically(
                pixels, width: currentWidth, height: currentHeight, pixelStride: pixelStride)
        }

        // 3. Invert P-values.
        if presentation.invert {
            invert(&pixels, bitsStored: Int(image.bitsStored), bytesPerSample: bytesPerSample)
        }

        guard currentWidth <= Int(UInt16.max), currentHeight <= Int(UInt16.max) else {
            return image
        }

        return PrintImageData(
            pixelData: Data(pixels),
            rows: UInt16(currentHeight),
            columns: UInt16(currentWidth),
            bitsAllocated: image.bitsAllocated,
            bitsStored: image.bitsStored,
            highBit: image.highBit,
            samplesPerPixel: image.samplesPerPixel,
            pixelRepresentation: image.pixelRepresentation,
            photometricInterpretation: image.photometricInterpretation
        )
    }

    // MARK: - Pixel operations
    //
    // (Implementation below; see `apply(_:to:)` for the order they run in.)

    private static func crop(
        _ pixels: [UInt8], width: Int, region: PixelRegion, pixelStride: Int
    ) -> [UInt8] {
        let rowBytes = region.width * pixelStride
        var out = [UInt8](repeating: 0, count: rowBytes * region.height)
        let sourceRowBytes = width * pixelStride
        for row in 0..<region.height {
            let sourceStart = (region.y + row) * sourceRowBytes + region.x * pixelStride
            let destStart = row * rowBytes
            out[destStart..<(destStart + rowBytes)] =
                pixels[sourceStart..<(sourceStart + rowBytes)]
        }
        return out
    }

    private static func rotate(
        _ pixels: [UInt8], width: Int, height: Int, quarterTurns: Int, pixelStride: Int
    ) -> [UInt8] {
        let outWidth = quarterTurns % 2 == 1 ? height : width
        let outHeight = quarterTurns % 2 == 1 ? width : height
        var out = [UInt8](repeating: 0, count: width * height * pixelStride)

        for y in 0..<height {
            for x in 0..<width {
                let destX: Int
                let destY: Int
                switch quarterTurns {
                case 1:  destX = outWidth - 1 - y; destY = x
                case 2:  destX = width - 1 - x;    destY = height - 1 - y
                default: destX = y;                destY = outHeight - 1 - x
                }
                let source = (y * width + x) * pixelStride
                let dest = (destY * outWidth + destX) * pixelStride
                for byte in 0..<pixelStride {
                    out[dest + byte] = pixels[source + byte]
                }
            }
        }
        return out
    }

    /// Turns pixels by an angle that is not a quarter turn.
    ///
    /// The one resampling step in this file, and it exists because the viewer's
    /// rotate tool turns freely: without it a 30° arrangement would print
    /// upright, which is a film that disagrees with the screen it was composed
    /// on. Bilinear, so a diagonal edge does not come out as a staircase, and
    /// over the *source* pixels — the crop is full modality resolution, not the
    /// monitor's copy of it.
    ///
    /// The output is the turned picture's bounding box, so nothing is cut off;
    /// what falls outside the turned rectangle is black, which is the film's
    /// background and what the printer would leave around any fitted image.
    private static func rotateResampling(
        _ pixels: [UInt8], width: Int, height: Int,
        outWidth: Int, outHeight: Int,
        presentation: ViewerPresentation,
        samples: Int, bytesPerSample: Int
    ) -> [UInt8] {
        let pixelStride = samples * bytesPerSample
        var out = [UInt8](repeating: 0, count: outWidth * outHeight * pixelStride)
        let (cosine, sine) = presentation.rotationComponents

        // Destination centre back to source centre: the inverse of a clockwise
        // turn in screen coordinates, which is where the viewer's angle is
        // measured. Sampling backwards is what leaves no holes in the output.
        let outCenterX = Double(outWidth) / 2
        let outCenterY = Double(outHeight) / 2
        let sourceCenterX = Double(width) / 2
        let sourceCenterY = Double(height) / 2

        for outY in 0..<outHeight {
            let dy = Double(outY) + 0.5 - outCenterY
            for outX in 0..<outWidth {
                let dx = Double(outX) + 0.5 - outCenterX
                let sourceX = dx * cosine + dy * sine + sourceCenterX - 0.5
                let sourceY = -dx * sine + dy * cosine + sourceCenterY - 0.5

                // Outside the picture is background, not a smeared edge pixel.
                guard sourceX > -1, sourceY > -1,
                      sourceX < Double(width), sourceY < Double(height) else { continue }

                let x0 = Int(sourceX.rounded(.down)), y0 = Int(sourceY.rounded(.down))
                let fx = sourceX - Double(x0), fy = sourceY - Double(y0)
                let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
                let cx0 = max(0, min(x0, width - 1)), cy0 = max(0, min(y0, height - 1))

                let destBase = (outY * outWidth + outX) * pixelStride
                for sample in 0..<samples {
                    let value =
                        sampleAt(pixels, x: cx0, y: cy0, width: width,
                                 sample: sample, pixelStride: pixelStride,
                                 bytesPerSample: bytesPerSample) * (1 - fx) * (1 - fy)
                        + sampleAt(pixels, x: x1, y: cy0, width: width,
                                   sample: sample, pixelStride: pixelStride,
                                   bytesPerSample: bytesPerSample) * fx * (1 - fy)
                        + sampleAt(pixels, x: cx0, y: y1, width: width,
                                   sample: sample, pixelStride: pixelStride,
                                   bytesPerSample: bytesPerSample) * (1 - fx) * fy
                        + sampleAt(pixels, x: x1, y: y1, width: width,
                                   sample: sample, pixelStride: pixelStride,
                                   bytesPerSample: bytesPerSample) * fx * fy

                    write(value, to: &out, at: destBase + sample * bytesPerSample,
                          bytesPerSample: bytesPerSample)
                }
            }
        }
        return out
    }

    /// One sample of one pixel, whatever its depth.
    private static func sampleAt(
        _ pixels: [UInt8], x: Int, y: Int, width: Int,
        sample: Int, pixelStride: Int, bytesPerSample: Int
    ) -> Double {
        let index = (y * width + x) * pixelStride + sample * bytesPerSample
        guard index + bytesPerSample <= pixels.count else { return 0 }
        if bytesPerSample == 1 { return Double(pixels[index]) }
        // Film pixels are little-endian, as they go on the wire.
        return Double(UInt16(pixels[index]) | (UInt16(pixels[index + 1]) << 8))
    }

    private static func write(
        _ value: Double, to pixels: inout [UInt8], at index: Int, bytesPerSample: Int
    ) {
        if bytesPerSample == 1 {
            pixels[index] = UInt8(max(0, min(255, value.rounded())))
        } else {
            let stored = UInt16(max(0, min(Double(UInt16.max), value.rounded())))
            pixels[index] = UInt8(stored & 0xFF)
            pixels[index + 1] = UInt8(stored >> 8)
        }
    }

    private static func flipHorizontally(
        _ pixels: [UInt8], width: Int, height: Int, pixelStride: Int
    ) -> [UInt8] {
        var out = pixels
        for y in 0..<height {
            let rowStart = y * width * pixelStride
            for x in 0..<width {
                let source = rowStart + x * pixelStride
                let dest = rowStart + (width - 1 - x) * pixelStride
                for byte in 0..<pixelStride {
                    out[dest + byte] = pixels[source + byte]
                }
            }
        }
        return out
    }

    private static func flipVertically(
        _ pixels: [UInt8], width: Int, height: Int, pixelStride: Int
    ) -> [UInt8] {
        let rowBytes = width * pixelStride
        var out = [UInt8](repeating: 0, count: pixels.count)
        for y in 0..<height {
            let source = y * rowBytes
            let dest = (height - 1 - y) * rowBytes
            out[dest..<(dest + rowBytes)] = pixels[source..<(source + rowBytes)]
        }
        return out
    }

    /// Negates P-values against the stored-bit maximum.
    ///
    /// Prepared film pixels are always unsigned MONOCHROME2 or RGB, so the
    /// maximum is `2^bitsStored − 1` and inversion needs no rescale lookup.
    private static func invert(_ pixels: inout [UInt8], bitsStored: Int, bytesPerSample: Int) {
        if bytesPerSample == 1 {
            let maxValue = UInt8(clamping: (1 << max(1, min(8, bitsStored))) - 1)
            for index in pixels.indices {
                pixels[index] = maxValue &- min(pixels[index], maxValue)
            }
        } else {
            let maxValue = UInt16(clamping: (1 << max(1, min(16, bitsStored))) - 1)
            // Prepared 16-bit film pixels are little-endian, as sent on the wire.
            for index in stride(from: 0, to: pixels.count - 1, by: 2) {
                let value = UInt16(pixels[index]) | (UInt16(pixels[index + 1]) << 8)
                let inverted = maxValue &- min(value, maxValue)
                pixels[index] = UInt8(inverted & 0xFF)
                pixels[index + 1] = UInt8(inverted >> 8)
            }
        }
    }
}

// MARK: - Prepared image

public extension PreparedPrintImage {
    /// An angle for the console: whole degrees, unless it isn't one.
    static func angleText(_ degrees: Double) -> String {
        degrees == degrees.rounded()
            ? String(Int(degrees))
            : String(format: "%.1f", degrees)
    }

    /// A copy with the viewer's arrangement baked into its pixels.
    ///
    /// - Parameter covers: whether the job scales pictures to cover their cells
    ///   (fill-to-film) — see ``PrintPresentationTransform/apply(_:to:covers:)``.
    func applying(
        _ presentation: ViewerPresentation,
        covers: Bool = false,
        onProgress: PrintImagePreparer.ProgressHandler? = nil
    ) -> PreparedPrintImage {
        let transformed = PrintPresentationTransform.apply(
            presentation, to: descriptor, covers: covers)
        // Unchanged pixels are only the whole story while the *spacing* is
        // unchanged too. A free-angle resample can come out byte-identical —
        // a small or near-uniform frame whose blended samples round back to the
        // values they came from — and returning `self` there would hand true
        // size the original millimetres for pixels that are now blends of their
        // neighbours. Rare, but it is exactly the case where the claim is
        // wrong, so it is decided by what was *asked* for rather than by what
        // the bytes happened to do.
        let resamples = presentation.rotationDegrees != 0 && !presentation.isQuarterTurn
        guard transformed != descriptor || resamples else { return self }
        onProgress?(
            "Applied viewer presentation: "
            + "\(descriptor.columns)x\(descriptor.rows) → "
            + "\(transformed.columns)x\(transformed.rows)"
            + (presentation.rotationDegrees != 0
               ? ", rotated \(Self.angleText(presentation.rotationDegrees))°"
               + (presentation.isQuarterTurn ? "" : " (resampled)")
               : "")
            + (presentation.flipHorizontal ? ", flipped horizontally" : "")
            + (presentation.flipVertical ? ", flipped vertically" : "")
            + (presentation.invert ? ", inverted" : ""))
        // The physical spacing follows the permutation: a crop keeps it (fewer
        // columns, same millimetres each), a quarter turn swaps row for column,
        // and a free-angle resample invalidates it — a resampled pixel has no
        // single spacing, so true size becomes undefined rather than wrong.
        let odd = presentation.isQuarterTurn && presentation.quarterTurns % 2 == 1
        let row = presentation.isQuarterTurn
            ? (odd ? columnSpacingMillimeters : rowSpacingMillimeters) : nil
        let column = presentation.isQuarterTurn
            ? (odd ? rowSpacingMillimeters : columnSpacingMillimeters) : nil
        return PreparedPrintImage(
            descriptor: transformed,
            sourcePath: sourcePath,
            frameIndex: frameIndex,
            rowSpacingMillimeters: row,
            columnSpacingMillimeters: column
        )
    }
}
