// CPUFrameRenderer.swift
// DICOMRenderKit — GPU_RENDERING_PLAN.md milestone M2
//
// The always-available backend, and the reference implementation the Metal path is
// tested against. It is a thin adapter over `PixelDataRenderer`, which is *not*
// being replaced: it remains what `dicom-export`, `dicom-convert`, the print film
// burn and headless CI use, none of which the GPU will ever serve.
//
// NEMA-verified: 2026a, checked 2026-09-30 — delegates to DICOMKit PixelDataRenderer; its VOI chain (WindowSettings.apply = PS3.3 2026a C.11.2.1.2.1/C.11.2.1.3.1/C.11.2.1.3.2 evaluated by Scripts/diff_renderkit.py, MONOCHROME1 after the VOI per C.7.6.3.1.2) and the pseudo-colour fold match; the Rec. 709 luma of the reader ramp is ITU-R BT.709, not DICOM. The no-window auto rung is the C.11.2.1.2.1 full-range window (D66); requests with the N.2 chain and Bits Allocated 32 frames go through GrayscaleDisplayPipeline (P-PIPELINE, D67); colour output is tagged with the ICC Profile (C.11.15.1.1, P-ICC).

import Foundation
import DICOMCore
import DICOMKit

#if canImport(CoreGraphics)
import CoreGraphics

/// Renders frames with `PixelDataRenderer` on the CPU.
public struct CPUFrameRenderer: FrameRenderBackend {
    public var backend: RenderBackend { .cpu }

    public init() {}

    public func renderFrame(_ request: FrameRenderRequest) -> CGImage? {
        let renderer = PixelDataRenderer(
            pixelData: request.pixelData, paletteColorLUT: request.paletteLUT
        )
        switch request.family {
        case .monochrome:
            // The PS3.4 N.2 chain (P-PIPELINE), and any frame whose cells are too wide
            // for a table (Bits Allocated 32, D67): one call that folds the chain into
            // a table where it can and evaluates it per pixel where it cannot.
            if request.usesDisplayPipeline || !WindowLUT.canTabulate(request.pixelData.descriptor) {
                guard let pipeline = request.displayPipeline(scanningFrame: true) else { return nil }
                return renderer.renderMonochromeFrame(
                    request.frameIndex, pipeline: pipeline,
                    pseudoColor: request.effectivePseudoColorPalette?.entries())
            }
            // Without a window the renderer's own auto-window (the frame's pixel
            // range) applies — the same behaviour callers get from
            // `PixelDataRenderer.renderFrame`.
            guard let window = request.window else {
                return renderer.renderFrame(request.frameIndex)
            }
            // A pseudo-colour palette folds into the window as one raw-sample →
            // RGB table, exactly as the Metal path folds it, so the two backends
            // stay byte-identical in colour as they are in grey.
            if let palette = request.effectivePseudoColorPalette {
                let lut = PaletteDisplayLUT.make(
                    window: WindowLUT.grayscale(
                        descriptor: request.pixelData.descriptor, window: window),
                    entries: palette.entries())
                return renderer.renderMonochromeFrame(
                    request.frameIndex, displayLUT: lut)
            }
            return renderer.renderMonochromeFrame(request.frameIndex, window: window)
        case .palette:
            // A reader's ramp still applies here, over the luminance of the
            // colours the file's own table produced. See `recoloured`.
            return tagged(recoloured(
                renderer.renderPaletteColorFrame(request.frameIndex),
                through: request.readerPalette), request)
        case .color:
            return tagged(recoloured(
                renderer.renderColorFrame(request.frameIndex),
                through: request.readerPalette), request)
        }
    }

    /// The image in the request's ICC Profile colour space (PS3.3 C.11.15.1.1, P-ICC):
    /// the bytes are unchanged, only their meaning — which is what lets Core Graphics
    /// convert the device colours for the screen. Untouched when there is no profile.
    private func tagged(_ image: CGImage?, _ request: FrameRenderRequest) -> CGImage? {
        guard let image, let space = request.outputColorSpace else { return image }
        return image.copy(colorSpace: space) ?? image
    }

    /// Re-maps a rendered colour frame through a reader's pseudo-colour ramp.
    ///
    /// A ramp over a monochrome frame folds into the window as one raw-sample →
    /// RGB table, which is the cheap path the `.monochrome` case above takes. A
    /// frame that carries its own colours has no raw sample to fold into: an
    /// ultrasound is YBR, a palette-colour frame has already been through the
    /// file's table, and both arrive here as RGB. So the ramp is applied to what
    /// the frame *shows* — its luminance — rather than to what it stored.
    ///
    /// Rec. 709 luma is the weighting, the same one every display uses to answer
    /// "how bright is this colour", so a grey ultrasound recolours exactly as it
    /// would have if it had been stored MONOCHROME2, and the colour Doppler
    /// wedge over it maps by how bright each hue is. That is a *display* choice
    /// and not a measurement: the stored pixels are untouched, and the reader
    /// who wants the file's own colours back turns the ramp off.
    ///
    /// Returning the image unchanged when there is no ramp keeps the ordinary
    /// path free of a copy — this only ever costs a pass when the reader has
    /// actually asked for one.
    private func recoloured(
        _ image: CGImage?, through palette: PseudoColorPalette?
    ) -> CGImage? {
        guard let image, let palette else { return image }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return image }

        let entries = palette.entries()
        guard !entries.isEmpty else { return image }

        // Draw into a known layout first: the source may be any of the several
        // byte orders and alpha positions Core Graphics can hand back, and
        // reading one of those by hand is how a recolour comes out with the
        // channels swapped.
        //
        // The context owns its buffer rather than borrowing a Swift array's:
        // an array's storage is only guaranteed for the duration of the
        // `withUnsafeMutableBytes` call, and a context that outlived that call
        // would be writing into memory it no longer owns.
        let bytesPerRow = width * 4
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo),
              let base = context.data else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // A 256-entry ramp indexed by the 8-bit luma, so the per-pixel work is
        // three multiplies and a lookup rather than a palette evaluation.
        let lastEntry = entries.count - 1
        var ramp = [UInt8](repeating: 0, count: 256 * 3)
        for level in 0..<256 {
            let index = lastEntry == 0
                ? 0
                : (level * lastEntry) / 255
            let entry = entries[index]
            ramp[level * 3] = entry.red
            ramp[level * 3 + 1] = entry.green
            ramp[level * 3 + 2] = entry.blue
        }

        let pixels = base.bindMemory(
            to: UInt8.self, capacity: bytesPerRow * height)
        ramp.withUnsafeBufferPointer { ramp in
            var offset = 0
            let end = bytesPerRow * height
            while offset + 3 < end {
                // Rec. 709, in integer arithmetic: the coefficients are scaled
                // by 1024 and the sum shifted back, which keeps the whole pass
                // in registers.
                let luma = (218 * Int(pixels[offset])
                    + 732 * Int(pixels[offset + 1])
                    + 74 * Int(pixels[offset + 2])) >> 10
                let level = min(255, max(0, luma)) * 3
                pixels[offset] = ramp[level]
                pixels[offset + 1] = ramp[level + 1]
                pixels[offset + 2] = ramp[level + 2]
                offset += 4
            }
        }

        return context.makeImage() ?? image
    }
}
#endif
