// AnnotationTextureBuilder.swift
// DICOMStudio
//
// DICOM Studio — bridges a reader's drawn annotations (`DICOMPrintKit`) to
// the GPU texture the main viewer's Metal pipeline composites over a frame
// (`DICOMRenderKit`). Sibling to `PrintCellTextureCache`, which does the same
// kind of bridging for the frame texture itself: `DICOMRenderKit` and
// `DICOMPrintKit` do not depend on each other, so this lives in `DICOMStudio`,
// the one target that already depends on both.
//
// The actual drawing — halo, arrowhead geometry, text anchor — is
// `ImageAnnotationBurner`'s: this only turns its rasterized bytes into an
// `MTLTexture`. Keeping the drawing in one place is what makes the viewer's
// overlay a promise the print path can't quietly stop keeping.

import Foundation
import DICOMPrintKit
import DICOMRenderKit

#if canImport(Metal)
import Metal

public enum AnnotationTextureBuilder {

    /// Builds a texture of a mark's drawn annotations, the same pixel
    /// dimensions as the frame they overlay — so `PrintOverlayPoint`'s
    /// 0...1 image-normalized coordinates map onto it with no separate
    /// scale step at draw time.
    ///
    /// Never `nil` merely because `overlays` is empty or entirely blank: an
    /// all-transparent texture is still returned, so a caller does not need
    /// a separate "nothing to draw" branch before binding it to the shader.
    /// `nil` only on a genuine failure to allocate or rasterize.
    ///
    /// - Parameter orientation: the arrangement the display shader will apply
    ///   to this texture. It turns the overlay with the picture, which is what
    ///   keeps an annotation stuck to the anatomy it was drawn on — and also
    ///   what wrote the words backwards on a mirrored image, because the shader
    ///   cannot tell a note from the anatomy. Passing the arrangement here
    ///   turns the *lettering* back level; the anchor is left alone for the
    ///   shader to move. `nil` for an unarranged picture.
    public static func build(
        overlays: [PrintOverlayAnnotation],
        width: Int,
        height: Int,
        device: MTLDevice,
        orientation: PrintOverlayOrientation? = nil
    ) -> AnnotationOverlayTexture? {
        let scale = supersamplingFactor(width: width, height: height)
        let canvasWidth = width * scale
        let canvasHeight = height * scale

        guard let (bytes, bytesPerRow) = ImageAnnotationBurner.rasterizing(
            overlays: overlays, width: canvasWidth, height: canvasHeight,
            orientation: orientation) else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: canvasWidth, height: canvasHeight,
            mipmapped: false)
        descriptor.usage = [.shaderRead]
        // The default supports CPU uploads on both Intel (managed) and Apple
        // GPUs (shared); standalone shared textures are not portable to Intel.
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, canvasWidth, canvasHeight), mipmapLevel: 0,
            withBytes: bytes, bytesPerRow: bytesPerRow)
        return AnnotationOverlayTexture(texture: texture)
    }

    /// How many overlay texels to rasterize per frame pixel.
    ///
    /// The overlay is addressed in the same 0...1 texture coordinates as the
    /// frame, so a larger canvas costs nothing at draw time and changes no
    /// geometry: every size in the burner — type size, line weight, arrowhead,
    /// halo spread — is a fraction of the canvas height, so drawing on a canvas
    /// `n` times taller scales the whole annotation by exactly `n` and it lands
    /// in the same place.
    ///
    /// It is needed because the frame's pixel grid is the wrong resolution to
    /// draw *type* at. A 512×512 CT fills a Retina viewport at roughly six
    /// display pixels per frame pixel, so glyphs rasterized at frame resolution
    /// were magnified six-fold before they reached the screen — legible, but
    /// visibly soft and coarse next to every other piece of text in the app.
    /// The frame itself has no such problem: its pixels are the data, and
    /// magnifying them is exactly what a reader asked for.
    ///
    /// Capped by both a factor and an absolute canvas size, because this
    /// allocates: the cost is `(width * scale) * (height * scale) * 4` bytes,
    /// which grows quadratically. Small frames — the ones that actually needed
    /// this — get the full factor; a frame already large enough to out-resolve
    /// any display gets none, since magnification is not what it suffers from.
    static func supersamplingFactor(width: Int, height: Int) -> Int {
        guard width > 0, height > 0 else { return 1 }
        for factor in stride(from: maximumSupersampling, through: 2, by: -1)
        where max(width, height) * factor <= maximumCanvasDimension {
            return factor
        }
        return 1
    }

    /// Enough to cover a 2× Retina panel showing a small frame zoomed in, and
    /// past the point where more resolution is visible in antialiased type.
    private static let maximumSupersampling = 4

    /// 4096 is both a conservative floor for `MTLDevice` 2D texture limits and
    /// the point past which a frame is already out-resolving the display: a
    /// 4096-wide overlay costs 64 MB at RGBA8 and buys nothing on screen.
    private static let maximumCanvasDimension = 4096
}
#endif
