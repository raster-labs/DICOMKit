import XCTest
@testable import DICOMRenderKit
import DICOMCore

#if canImport(Metal)
import Metal
#endif
#if canImport(MetalKit)
import MetalKit
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Milestone M5 of `GPU_RENDERING_PLAN.md`: the frame stays on the GPU and the tool
/// actions — zoom, pan, rotate, flip, invert — are applied by the display shader.
///
/// The plan's stated caution for this milestone is a real prior incident, not a
/// hypothetical: a `Canvas`-based viewer in this app blanked **every**
/// progressively-decoded J2K file because the canvas resolved to zero size under
/// `.aspectRatio`. The decode was correct; the view drew nothing, silently. An
/// `MTKView` has the same hazard class, so a zero-sized drawable is tested for
/// explicitly here rather than trusted not to happen.
final class MetalDisplayPathTests: XCTestCase {

    #if canImport(Metal) && canImport(CoreGraphics)

    private func requireRenderer() throws -> MetalFrameRenderer {
        guard let renderer = MetalFrameRenderer(minimumPixelCount: 0) else {
            throw XCTSkip("No Metal device on this machine")
        }
        return renderer
    }

    private func monochromeRequest(
        rows: Int = 64, columns: Int = 64, value: UInt16 = 30_000
    ) -> FrameRenderRequest {
        let descriptor = PixelDataDescriptor(
            rows: rows, columns: columns,
            bitsAllocated: 16, bitsStored: 16, highBit: 15, isSigned: false,
            samplesPerPixel: 1, photometricInterpretation: .monochrome2)
        var bytes = Data(count: descriptor.bytesPerFrame)
        bytes.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: UInt16.self)
            for i in 0..<(rows * columns) { out[i] = value &+ UInt16(i % 1000) }
        }
        return FrameRenderRequest(
            pixelData: PixelData(data: bytes, descriptor: descriptor).pageAligned(),
            frameIndex: 0,
            window: WindowSettings(center: 32_768, width: 65_536))
    }

    // MARK: - Texture production

    func testDisplayTextureMatchesFrameDimensions() throws {
        let renderer = try requireRenderer()
        let texture = try XCTUnwrap(
            renderer.renderDisplayTexture(monochromeRequest(rows: 37, columns: 23)))
        XCTAssertEqual(texture.width, 23)
        XCTAssertEqual(texture.height, 37)
        XCTAssertTrue(texture.isGrayscale)
        XCTAssertEqual(texture.texture.pixelFormat, .r8Unorm)
    }

    /// The display texture is a *view* onto the compute output — the same bytes the
    /// `CGImage` path would return, at a padded row stride. Padding is why this
    /// compares row by row instead of whole buffers: the pad bytes are not pixels.
    func testDisplayTextureHoldsTheSamePixelsAsTheCGImagePath() throws {
        let renderer = try requireRenderer()
        let request = monochromeRequest(rows: 37, columns: 23)

        let image = try XCTUnwrap(renderer.renderFrame(request))
        let imageBytes = [UInt8](try XCTUnwrap(image.dataProvider?.data as Data?))

        let display = try XCTUnwrap(renderer.renderDisplayTexture(request))
        var textureBytes = [UInt8](repeating: 0, count: display.width * display.height)
        textureBytes.withUnsafeMutableBytes { raw in
            display.texture.getBytes(
                raw.baseAddress!, bytesPerRow: display.width,
                from: MTLRegionMake2D(0, 0, display.width, display.height), mipmapLevel: 0)
        }

        XCTAssertEqual(imageBytes.count, textureBytes.count)
        XCTAssertEqual(imageBytes, textureBytes,
                       "the display texture must carry exactly the CGImage path's pixels")
    }

    /// Colour frames become an RGBA texture, not a grey one.
    func testColorDisplayTextureIsRGBA() throws {
        let renderer = try requireRenderer()
        let descriptor = PixelDataDescriptor(
            rows: 16, columns: 16, bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 3,
            photometricInterpretation: .rgb, planarConfiguration: 0)
        let bytes = Data((0..<descriptor.bytesPerFrame).map { UInt8($0 % 256) })
        let request = FrameRenderRequest(
            pixelData: PixelData(data: bytes, descriptor: descriptor).pageAligned())

        let texture = try XCTUnwrap(renderer.renderDisplayTexture(request))
        XCTAssertFalse(texture.isGrayscale)
        XCTAssertEqual(texture.texture.pixelFormat, .rgba8Unorm)
    }

    /// The display path must not inherit the CPU-wins size threshold: a frame headed
    /// for a GPU texture has no cheaper route, whatever its size.
    ///
    /// The production threshold is zero by policy (`minimumGPUPixelCount`) — no
    /// frame is declined for being small — so the threshold behaviour is proved
    /// on a renderer given one explicitly.
    func testDisplayTextureIgnoresTheSizeThreshold() throws {
        let syntheticThreshold = 1_000_000
        guard let thresholded = MetalFrameRenderer(minimumPixelCount: syntheticThreshold) else {
            throw XCTSkip("No Metal device on this machine")
        }
        let request = monochromeRequest(rows: 64, columns: 64)
        XCTAssertNil(thresholded.renderFrame(request), "the CGImage path applies the threshold")
        XCTAssertNotNil(thresholded.renderDisplayTexture(request),
                        "the display path must not apply it")
    }

    // MARK: - The zero-drawable hazard

    /// A zero-sized drawable must be reported, not silently drawn into.
    ///
    /// This is the `Canvas` blanking bug's shape, transplanted to `MTKView`.
    func testZeroSizedDrawableIsRefusedAndFlagged() throws {
        guard let renderer = MetalImageRenderer() else {
            throw XCTSkip("No Metal device on this machine")
        }
        renderer.frame = try requireRenderer().renderDisplayTexture(monochromeRequest())

        let drew = renderer.render(size: .zero, descriptor: MTLRenderPassDescriptor(),
                                   drawable: nil)
        XCTAssertFalse(drew)
        XCTAssertTrue(renderer.lastDrawHadZeroSizedDrawable)
        XCTAssertEqual(renderer.drawCount, 0)
    }

    /// …and the same renderer must draw once the drawable has a size. Without this
    /// half, a renderer that never drew anything would pass the test above.
    func testNonZeroDrawableDraws() throws {
        guard let renderer = MetalImageRenderer(),
              let device = MetalRenderDevice.shared else {
            throw XCTSkip("No Metal device on this machine")
        }
        renderer.frame = try requireRenderer().renderDisplayTexture(monochromeRequest())

        let descriptor = MTLRenderPassDescriptor()
        let target = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalImageRenderer.colorPixelFormat,
            width: 128, height: 128, mipmapped: false)
        target.usage = [.renderTarget, .shaderRead]
        descriptor.colorAttachments[0].texture =
            try XCTUnwrap(device.device.makeTexture(descriptor: target))
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        try renderAndWait(renderer: renderer, device: device, descriptor: descriptor)
        XCTAssertFalse(renderer.lastDrawHadZeroSizedDrawable)
        XCTAssertEqual(renderer.drawCount, 1)
    }

    // MARK: - Annotation compositing

    /// A texture built directly with `MTLTexture.replace`, bypassing
    /// `AnnotationTextureBuilder` (which lives in `DICOMStudio`, above this
    /// module) — this suite only needs to prove the shader samples and
    /// blends whatever texture is bound at index 1.
    private func makeAnnotationTexture(
        device: MetalRenderDevice, width: Int, height: Int, rgba: [UInt8]
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = try XCTUnwrap(device.device.makeTexture(descriptor: descriptor))
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: rgba, bytesPerRow: width * 4)
        return texture
    }

    private struct RenderFailure: Error, CustomStringConvertible {
        let description: String
    }

    private func waitForCompletion(
        _ commandBuffer: any MTLCommandBuffer,
        device: MetalRenderDevice, texture: any MTLTexture, phase: String
    ) throws {
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw RenderFailure(description:
                "\(phase) failed: device=\(device.device.name), " +
                "storageMode=\(texture.storageMode.rawValue), " +
                "status=\(commandBuffer.status.rawValue), " +
                "error=\(String(describing: commandBuffer.error))")
        }
    }

    private func renderAndWait(
        renderer: MetalImageRenderer, device: MetalRenderDevice,
        descriptor: MTLRenderPassDescriptor
    ) throws {
        let texture = try XCTUnwrap(descriptor.colorAttachments[0].texture)
        let commandBuffer = try XCTUnwrap(renderer.submitRender(
            size: CGSize(width: texture.width, height: texture.height),
            descriptor: descriptor, drawable: nil),
            "render submission failed: device=\(device.device.name), " +
            "storageMode=\(texture.storageMode.rawValue)")
        try waitForCompletion(commandBuffer, device: device, texture: texture, phase: "render")
    }

    /// Wait for the actual draw, then make GPU writes visible to the CPU. The
    /// default managed textures on Intel Macs need explicit synchronization;
    /// waiting for an unrelated empty command buffer does not provide it.
    private func readRenderedPixels(
        renderer: MetalImageRenderer, device: MetalRenderDevice,
        descriptor: MTLRenderPassDescriptor
    ) throws -> [UInt8] {
        let texture = try XCTUnwrap(descriptor.colorAttachments[0].texture)
        try renderAndWait(renderer: renderer, device: device, descriptor: descriptor)
        #if os(macOS)
        if texture.storageMode == .managed {
            let synchronization = try XCTUnwrap(device.commandQueue.makeCommandBuffer())
            let blit = try XCTUnwrap(synchronization.makeBlitCommandEncoder())
            blit.synchronize(resource: texture)
            blit.endEncoding()
            synchronization.commit()
            try waitForCompletion(
                synchronization, device: device, texture: texture, phase: "readback synchronization")
        }
        #endif
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            texture.getBytes(buffer.baseAddress!, bytesPerRow: texture.width * 4,
                             from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                             mipmapLevel: 0)
        }
        return bytes
    }

    /// No annotation set: the renderer still draws (the placeholder texture
    /// stands in), and the frame is shown untouched.
    func testNoAnnotationOverlayLeavesTheFrameUntouched() throws {
        guard let renderer = MetalImageRenderer(), let device = MetalRenderDevice.shared else {
            throw XCTSkip("No Metal device on this machine")
        }
        renderer.frame = try requireRenderer().renderDisplayTexture(
            monochromeRequest(rows: 8, columns: 8, value: 30_000))
        XCTAssertNil(renderer.annotationOverlay)

        let target = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalImageRenderer.colorPixelFormat,
            width: 32, height: 32, mipmapped: false)
        target.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(device.device.makeTexture(descriptor: target))

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        let bytes = try readRenderedPixels(renderer: renderer, device: device, descriptor: descriptor)
        let centre = (16 * 32 + 16) * 4
        XCTAssertGreaterThan(bytes[centre], 20, "the placeholder must leave the frame's grey visible")
        XCTAssertEqual(bytes[centre], bytes[centre + 1])
        XCTAssertEqual(bytes[centre], bytes[centre + 2])
    }

    /// The overlay's colour and alpha reach the screen: a fully opaque red
    /// annotation texture composited over a bright frame must read back as
    /// red, not the frame's own grey.
    func testAnnotationOverlayIsComposited() throws {
        guard let renderer = MetalImageRenderer(), let device = MetalRenderDevice.shared else {
            throw XCTSkip("No Metal device on this machine")
        }
        renderer.frame = try requireRenderer().renderDisplayTexture(
            monochromeRequest(rows: 8, columns: 8, value: 30_000))

        // A fully opaque red texture, the frame's own dimensions.
        let overlayTexture = try makeAnnotationTexture(
            device: device, width: 8, height: 8,
            rgba: Array(repeating: [255, 0, 0, 255], count: 64).flatMap { $0 })
        renderer.annotationOverlay = AnnotationOverlayTexture(texture: overlayTexture)

        let target = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalImageRenderer.colorPixelFormat,
            width: 32, height: 32, mipmapped: false)
        target.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(device.device.makeTexture(descriptor: target))

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        let bytes = try readRenderedPixels(renderer: renderer, device: device, descriptor: descriptor)
        // BGRA: red shows as a high byte 2 (R), zero byte 0 (B).
        let centre = (16 * 32 + 16) * 4
        XCTAssertEqual(bytes[centre + 2], 255, "the annotation's red must reach the screen")
        XCTAssertEqual(bytes[centre], 0, "a fully opaque annotation must fully replace the frame's colour")
    }

    // MARK: - The film's crop mask

    /// Renders offscreen and reads the pixels back, so the fragment shader's
    /// masking can be asserted rather than trusted.
    private func renderedPixels(
        presentation: DisplayPresentation, size: Int = 128
    ) throws -> (bytes: [UInt8], width: Int) {
        guard let renderer = MetalImageRenderer(),
              let device = MetalRenderDevice.shared else {
            throw XCTSkip("No Metal device on this machine")
        }
        // A uniformly bright frame: any pixel the mask spares is visibly grey,
        // any pixel it paints is exactly black, and nothing else varies.
        renderer.frame = try requireRenderer().renderDisplayTexture(
            monochromeRequest(rows: 64, columns: 64, value: 30_000))
        renderer.presentation = presentation

        let target = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalImageRenderer.colorPixelFormat,
            width: size, height: size, mipmapped: false)
        target.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(device.device.makeTexture(descriptor: target))

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        let bytes = try readRenderedPixels(renderer: renderer, device: device, descriptor: descriptor)
        return (bytes, size)
    }

    /// The blue channel at a pixel — first byte of BGRA, and for these grey
    /// frames equal to the other channels.
    private func luminance(_ pixels: (bytes: [UInt8], width: Int), x: Int, y: Int) -> Int {
        Int(pixels.bytes[(y * pixels.width + x) * 4])
    }

    /// A cropped cell must not spill the rest of the frame into its letterbox.
    ///
    /// The quad is always the whole frame; before the mask, a fitted crop's
    /// surroundings showed the neighbouring anatomy the crop was meant to
    /// remove — which is why freely rotated and zoomed cells were exiled to the
    /// CPU renderer. A *wide* crop in a square view letterboxes above and
    /// below; the frame rows the quad carries there are outside the crop and
    /// must come back black, while the crop itself stays the frame's grey.
    func testMaskPaintsTheLetterboxBlack() throws {
        let pixels = try renderedPixels(presentation: DisplayPresentation(
            linearFiltering: true,
            sourceRegion: .init(x: 16, y: 24, width: 32, height: 16)))

        let centre = luminance(pixels, x: 64, y: 64)
        XCTAssertGreaterThan(centre, 20, "the crop itself must be the frame's grey")
        // 32×16 fitted to 128×128 spans the full width and rows 32..96; the
        // bands above and below are letterbox, and the quad has frame content
        // there — rows 8..24 and 40..56 of the source, all outside the crop.
        for (x, y) in [(4, 8), (64, 16), (123, 24), (4, 119), (64, 111), (123, 103)] {
            XCTAssertEqual(luminance(pixels, x: x, y: y), 0,
                           "letterbox (\(x),\(y)) is outside the crop — unexposed film, black")
        }
    }

    /// The corners a free rotation leaves empty are film background — the exact
    /// case that used to force those cells onto the CPU. At 45° the turned crop
    /// is a diamond; the view's corners lie outside it and must be black, while
    /// the diamond's centre is still the frame's grey.
    func testMaskBlacksTheCornersOfAFreelyRotatedCrop() throws {
        let pixels = try renderedPixels(presentation: DisplayPresentation(
            rotationDegrees: 45,
            linearFiltering: true,
            sourceRegion: .init(x: 16, y: 16, width: 32, height: 32)))

        XCTAssertGreaterThan(luminance(pixels, x: 64, y: 64), 20)
        for (x, y) in [(4, 4), (123, 4), (4, 123), (123, 123)] {
            XCTAssertEqual(luminance(pixels, x: x, y: y), 0,
                           "corner (\(x),\(y)) of a 45° cell is unexposed film")
        }
    }

    // MARK: - Magnification picks the sampler

    /// A small frame filling a large tile is magnified: bilinear, so a 154×192
    /// MR in a 1×1 reading area is not shown as ~4.6-pixel blocks.
    func testSmallFrameFillingTheViewIsMagnified() {
        let p = DisplayPresentation()
        XCTAssertTrue(p.magnifies(imageWidth: 154, imageHeight: 192, viewWidth: 1508, viewHeight: 887))
    }

    /// A frame larger than the drawable is minified: nearest, the reader sees
    /// actual pixels — and zooming in past 1:1 flips it to bilinear.
    func testLargeFrameIsNotMagnifiedUntilZoomedPastOneToOne() {
        var p = DisplayPresentation()
        XCTAssertFalse(p.magnifies(imageWidth: 2048, imageHeight: 2048, viewWidth: 1024, viewHeight: 1024))
        p.zoom = 2.0
        XCTAssertFalse(p.magnifies(imageWidth: 2048, imageHeight: 2048, viewWidth: 1024, viewHeight: 1024),
                       "fit 0.5 × zoom 2 is exactly 1:1 — still nearest")
        p.zoom = 2.5
        XCTAssertTrue(p.magnifies(imageWidth: 2048, imageHeight: 2048, viewWidth: 1024, viewHeight: 1024))
    }

    /// The film composes its own scale and sets `linearFiltering` itself; the
    /// magnification rule never second-guesses a crop.
    func testFilmCropIsNeverMagnifiedByTheRule() {
        let p = DisplayPresentation(sourceRegion: .init(x: 0, y: 0, width: 16, height: 16))
        XCTAssertFalse(p.magnifies(imageWidth: 64, imageHeight: 64, viewWidth: 1024, viewHeight: 1024))
    }

    func testDegenerateSizesAreNotMagnified() {
        let p = DisplayPresentation()
        XCTAssertFalse(p.magnifies(imageWidth: 0, imageHeight: 64, viewWidth: 128, viewHeight: 128))
        XCTAssertFalse(p.magnifies(imageWidth: 64, imageHeight: 64, viewWidth: 0, viewHeight: 128))
    }

    /// End to end: a 64×64 frame whose left half is black and right half white,
    /// drawn 2× into 128×128, has a blended pixel at the seam on the GPU — the
    /// magnified viewer no longer point-replicates. (At 2× the device pixel
    /// left of the seam samples texel 31.25: a quarter of the way into white.)
    func testMagnifiedFrameIsSampledBilinearlyOnScreen() throws {
        guard let renderer = MetalImageRenderer(),
              let device = MetalRenderDevice.shared else {
            throw XCTSkip("No Metal device on this machine")
        }
        let descriptor = PixelDataDescriptor(
            rows: 64, columns: 64,
            bitsAllocated: 16, bitsStored: 16, highBit: 15, isSigned: false,
            samplesPerPixel: 1, photometricInterpretation: .monochrome2)
        var bytes = Data(count: descriptor.bytesPerFrame)
        bytes.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: UInt16.self)
            for i in 0..<(64 * 64) { out[i] = (i % 64) < 32 ? 0 : 65_535 }
        }
        let request = FrameRenderRequest(
            pixelData: PixelData(data: bytes, descriptor: descriptor).pageAligned(),
            frameIndex: 0,
            window: WindowSettings(center: 32_768, width: 65_536))
        renderer.frame = try requireRenderer().renderDisplayTexture(request)
        renderer.presentation = DisplayPresentation()   // viewer defaults: no forced filtering

        let size = 128
        let target = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalImageRenderer.colorPixelFormat,
            width: size, height: size, mipmapped: false)
        target.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(device.device.makeTexture(descriptor: target))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let out = try readRenderedPixels(renderer: renderer, device: device, descriptor: pass)
        let row = (0..<size).map { Int(out[(64 * size + $0) * 4]) }
        XCTAssertEqual(row[8], 0, "deep in the black half")
        XCTAssertEqual(row[120], 255, "deep in the white half")
        let seam = row[60...67].filter { $0 > 8 && $0 < 247 }
        XCTAssertFalse(seam.isEmpty,
                       "a magnified seam must blend; nearest sampling leaves none: \(Array(row[56...71]))")
    }

    /// A renderer with no frame must not draw — and must not claim the drawable was
    /// the problem, or the zero-size flag would be useless for diagnosis.
    func testMissingFrameDoesNotDrawAndDoesNotBlameTheDrawable() throws {
        guard let renderer = MetalImageRenderer() else {
            throw XCTSkip("No Metal device on this machine")
        }
        renderer.frame = nil
        XCTAssertFalse(renderer.render(size: CGSize(width: 64, height: 64),
                                       descriptor: MTLRenderPassDescriptor(), drawable: nil))
        XCTAssertFalse(renderer.lastDrawHadZeroSizedDrawable)
    }

    #endif

    // MARK: - Presentation geometry
    //
    // Pure maths, no GPU — runs everywhere, including CI without a device.

    #if canImport(Metal)
    private func transform(
        _ presentation: DisplayPresentation,
        image: (Int, Int) = (100, 100), view: (Double, Double) = (200, 200)
    ) -> simd_float4x4? {
        presentation.transform(imageWidth: image.0, imageHeight: image.1,
                               viewWidth: view.0, viewHeight: view.1)
    }

    /// Degenerate inputs must return nil rather than divide by zero — the guard that
    /// makes the blanking case detectable.
    func testDegenerateGeometryReturnsNil() {
        XCTAssertNil(transform(.identity, image: (0, 100)))
        XCTAssertNil(transform(.identity, image: (100, 0)))
        XCTAssertNil(transform(.identity, view: (0, 200)))
        XCTAssertNil(transform(.identity, view: (200, 0)))
        XCTAssertNil(transform(DisplayPresentation(zoom: 0)))
    }

    /// A square image in a square view at zoom 1 fills it exactly.
    func testSquareImageFitsSquareView() throws {
        let matrix = try XCTUnwrap(transform(.identity))
        XCTAssertEqual(matrix.columns.0.x, 1, accuracy: 1e-6)
        XCTAssertEqual(matrix.columns.1.y, 1, accuracy: 1e-6)
    }

    /// A wide image in a square view is width-limited: full width, letterboxed.
    func testWideImageIsLetterboxed() throws {
        let matrix = try XCTUnwrap(transform(.identity, image: (200, 100)))
        XCTAssertEqual(matrix.columns.0.x, 1, accuracy: 1e-6)
        XCTAssertEqual(matrix.columns.1.y, 0.5, accuracy: 1e-6)
    }

    /// A tall image in a square view is height-limited: full height, pillarboxed.
    func testTallImageIsPillarboxed() throws {
        let matrix = try XCTUnwrap(transform(.identity, image: (100, 200)))
        XCTAssertEqual(matrix.columns.0.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(matrix.columns.1.y, 1, accuracy: 1e-6)
    }

    func testZoomScalesBothAxes() throws {
        let matrix = try XCTUnwrap(transform(DisplayPresentation(zoom: 2)))
        XCTAssertEqual(matrix.columns.0.x, 2, accuracy: 1e-6)
        XCTAssertEqual(matrix.columns.1.y, 2, accuracy: 1e-6)
    }

    func testFlipsNegateTheCorrespondingAxis() throws {
        let horizontal = try XCTUnwrap(transform(DisplayPresentation(flipHorizontal: true)))
        XCTAssertEqual(horizontal.columns.0.x, -1, accuracy: 1e-6)
        XCTAssertEqual(horizontal.columns.1.y, 1, accuracy: 1e-6)

        let vertical = try XCTUnwrap(transform(DisplayPresentation(flipVertical: true)))
        XCTAssertEqual(vertical.columns.0.x, 1, accuracy: 1e-6)
        XCTAssertEqual(vertical.columns.1.y, -1, accuracy: 1e-6)
    }

    /// The mirror is applied *after* the turn, which is what the film, the
    /// `CGContext` path and ``DisplayPresentation/sourceRegionTransform`` all do.
    ///
    /// Flip and rotation were each tested alone above, and both passed while the
    /// two together were wrong: the viewer folded the mirror into the fit scale,
    /// which put it *before* the rotation. The orders agree only at 0°, so
    /// nothing caught it until an image was turned and then flipped — on a
    /// quarter turn the two differ by a half turn, so the flip buttons appeared
    /// to rotate the image rather than mirror it, and the print preview, which
    /// composed in the other order, disagreed with the screen it was previewing.
    ///
    /// Checked against the composition directly rather than against copied-out
    /// numbers: `flip · rotate` is the claim, and it is what is asserted.
    func testFlipIsAppliedAfterRotation() throws {
        for (flipH, flipV) in [(true, false), (false, true), (true, true)] {
            for angle in [90.0, 180.0, 270.0, 45.0] {
                let combined = try XCTUnwrap(transform(DisplayPresentation(
                    rotationDegrees: angle,
                    flipHorizontal: flipH, flipVertical: flipV)))
                let turnOnly = try XCTUnwrap(transform(
                    DisplayPresentation(rotationDegrees: angle)))
                let mirror = simd_float4x4(diagonal: SIMD4<Float>(
                    flipH ? -1 : 1, flipV ? -1 : 1, 1, 1))
                let expected = mirror * turnOnly

                for column in 0..<4 {
                    for row in 0..<4 {
                        XCTAssertEqual(
                            combined[column][row], expected[column][row], accuracy: 1e-5,
                            "flipH=\(flipH) flipV=\(flipV) at \(angle)° — the mirror "
                            + "must come after the turn, not before it")
                    }
                }
            }
        }
    }

    /// The viewer and the film agree about a turned, flipped image.
    ///
    /// The two transforms are built by different code for different jobs — the
    /// viewer fits and pans, the film fits a region the way a printer does — but
    /// a preview that showed a different picture from the viewer is the bug the
    /// screenshots caught. Their *orientation* has to match even where their
    /// framing does not, so this compares what each does to the image's axes.
    func testViewerAndFilmOrientTurnedFlippedImagesAlike() throws {
        for (flipH, flipV) in [(true, false), (false, true), (true, true)] {
            for angle in [90.0, 180.0, 270.0] {
                let viewer = try XCTUnwrap(transform(DisplayPresentation(
                    rotationDegrees: angle,
                    flipHorizontal: flipH, flipVertical: flipV)))
                let film = try XCTUnwrap(DisplayPresentation(
                    rotationDegrees: angle,
                    flipHorizontal: flipH, flipVertical: flipV,
                    sourceRegion: .init(x: 0, y: 0, width: 100, height: 100)
                ).transform(imageWidth: 100, imageHeight: 100,
                            viewWidth: 200, viewHeight: 200))

                // Where each sends the image's own right-hand and downward axes.
                // Normalised, because the two scale differently by design.
                for axis in [SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 1, 0, 0)] {
                    let viewerAxis = viewer * axis
                    let filmAxis = film * axis
                    let v = simd_normalize(SIMD2<Float>(viewerAxis.x, viewerAxis.y))
                    let f = simd_normalize(SIMD2<Float>(filmAxis.x, filmAxis.y))
                    XCTAssertEqual(v.x, f.x, accuracy: 1e-4,
                                   "viewer and film disagree at \(angle)° "
                                   + "flipH=\(flipH) flipV=\(flipV)")
                    XCTAssertEqual(v.y, f.y, accuracy: 1e-4,
                                   "viewer and film disagree at \(angle)° "
                                   + "flipH=\(flipH) flipV=\(flipV)")
                }
            }
        }
    }

    /// A quarter turn swaps the axes. Sign matters: it fixes the rotation direction,
    /// and a viewer that turned images the wrong way would be a visible bug.
    func testQuarterTurnSwapsAxes() throws {
        let matrix = try XCTUnwrap(transform(DisplayPresentation(rotationDegrees: 90)))
        XCTAssertEqual(matrix.columns.0.x, 0, accuracy: 1e-6)
        XCTAssertEqual(matrix.columns.1.y, 0, accuracy: 1e-6)
        // Clockwise on screen, with NDC y running upward.
        XCTAssertEqual(matrix.columns.0.y, -1, accuracy: 1e-6)
        XCTAssertEqual(matrix.columns.1.x, 1, accuracy: 1e-6)
    }

    /// Four quarter turns return to the identity — cheap proof the rotation composes.
    func testFullTurnIsIdentity() throws {
        let matrix = try XCTUnwrap(transform(DisplayPresentation(rotationDegrees: 360)))
        XCTAssertEqual(matrix.columns.0.x, 1, accuracy: 1e-5)
        XCTAssertEqual(matrix.columns.1.y, 1, accuracy: 1e-5)
        XCTAssertEqual(matrix.columns.0.y, 0, accuracy: 1e-5)
    }

    /// A turned picture must keep its shape in a viewport that isn't square.
    ///
    /// Rotating in NDC alone would stretch it — the same two units span a wide view's
    /// long axis as its short one — so a square image would come out of a quarter turn
    /// as a rectangle, and would visibly breathe through the angles the rotate tool
    /// sweeps. Measured in screen points, where the image's own extents live.
    func testRotationPreservesShapeInNonSquareView() throws {
        let view = (800.0, 600.0)
        for angle in [0.0, 17.0, 45.0, 90.0, 213.5, 300.0] {
            let matrix = try XCTUnwrap(
                transform(DisplayPresentation(rotationDegrees: angle),
                          image: (100, 100), view: view))
            // Where the quad's own axes land, in points rather than NDC.
            let xAxis = SIMD2<Double>(Double(matrix.columns.0.x) * view.0 / 2,
                                     Double(matrix.columns.0.y) * view.1 / 2)
            let yAxis = SIMD2<Double>(Double(matrix.columns.1.x) * view.0 / 2,
                                     Double(matrix.columns.1.y) * view.1 / 2)
            // Equal lengths and still at right angles: a rotation, not a shear.
            // Tolerances are single-precision: the matrix is Float, as the shader
            // wants it, so exact equality is not on offer at these magnitudes.
            XCTAssertEqual(simd_length(xAxis), simd_length(yAxis), accuracy: 1e-3,
                           "axes differ in length at \(angle)°")
            XCTAssertEqual(simd_dot(xAxis, yAxis), 0, accuracy: 1e-2,
                           "axes are not perpendicular at \(angle)°")
            // And the same size as the unrotated fit — 600 points across.
            XCTAssertEqual(simd_length(xAxis), 300, accuracy: 1e-3,
                           "scale changed at \(angle)°")
        }
    }

    /// Pan is in view points and must land in NDC, where the view spans 2 units.
    /// Screen y grows downward while NDC y grows upward, so the sign flips.
    func testPanTranslatesInNormalisedDeviceCoordinates() throws {
        let matrix = try XCTUnwrap(
            transform(DisplayPresentation(panX: 50, panY: 50), view: (200, 200)))
        XCTAssertEqual(matrix.columns.3.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(matrix.columns.3.y, -0.5, accuracy: 1e-6)
    }

    /// Panning must move the picture across the screen, not through its own rotated
    /// frame — a hand tool that dragged sideways when the image was turned 90° would
    /// feel broken.
    func testPanIsAppliedInScreenSpaceAfterRotation() throws {
        let matrix = try XCTUnwrap(
            transform(DisplayPresentation(panX: 50, rotationDegrees: 90), view: (200, 200)))
        XCTAssertEqual(matrix.columns.3.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(matrix.columns.3.y, 0, accuracy: 1e-6)
    }

    /// Invert is not geometry and must leave the matrix alone — it is a fragment-stage
    /// operation.
    func testInvertDoesNotAffectGeometry() throws {
        let plain = try XCTUnwrap(transform(.identity))
        let inverted = try XCTUnwrap(transform(DisplayPresentation(invert: true)))
        XCTAssertEqual(plain, inverted)
    }
    #endif
}
