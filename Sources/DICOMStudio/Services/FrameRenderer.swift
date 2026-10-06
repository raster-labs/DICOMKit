// FrameRenderer.swift
// DICOMStudio
//
// DICOM Studio — rendering one frame of a file on disk, arranged.
//
// NEMA-verified: 2026a, checked 2026-10-06 — `resolvedWindow` (the seed of an unwindowed film cell) is DICOMKit `determineModalityWindow`, in modality units (PS3.3 C.11.2.1.2.1: the window applies after the Modality LUT / Rescale), and is stored with windowSpace .outputUnits so `resolvedPipeline` takes it as is (A6 / D65; the deprecated stored-unit `determineWindowSettings` is no longer called); tiles and film cells render through the PS3.4 2026a N.2 chain (D65, D68): `resolvedPipeline` puts a stored-unit window back into modality units (c·m+b, w·|m|) or takes an output-unit one as is, drops a LINEAR width under 1 (PS3.3 C.11.2.1.2.1: w ≥ 1) and asks DICOMKit's `determineDisplayPipeline` for the Modality LUT, VOI (window or VOI LUT Sequence, C.11.2) and Presentation LUT (MONOCHROME1 → INVERSE, C.7.6.3.1.2); `request` carries them with the ICC Profile (0028,2000) (C.11.15.1.1) to the renderer, which was given a stored-unit window; `photometricInterpretation(path:)` reads (0028,0004) for the bridge's Presentation LUT fold (N.2.1.4); the arrangement (crop, rotate, flip, invert) and the overlay burn-in carry no standard data of their own; checked by Scripts/diff_studio_g2_viewer.py
//
// Shared by the film preview and the viewer's unfocused tiles: both need "this
// frame, windowed and arranged the way the user left it, at a size that suits
// the box it goes in", and both must agree with what the printer will produce.

import Foundation
import DICOMKit
import DICOMCore
import DICOMPrintKit
import DICOMRenderKit

#if canImport(CoreGraphics)
import CoreGraphics

enum FrameRenderer {

    /// Identity of a rendered frame: everything that changes its pixels.
    ///
    /// Caches must key on this rather than on file and frame alone. Two marks of
    /// the same frame at different zooms are different pictures, and keying on
    /// identity alone silently serves the first one for both — which is exactly
    /// how a film preview ends up disagreeing with the viewer.
    ///
    /// `GPU_RENDERING_PLAN.md` M6 proposed dropping zoom, rotation, flip and invert
    /// from this key once those moved onto the GPU. They have **not** moved: they
    /// are still applied on the CPU by ``applying(_:to:)`` below, so they still
    /// change the pixels this key identifies and must stay in it. Removing them
    /// now would reintroduce exactly the bug the paragraph above describes. That
    /// rework is contingent on M5's display path, and is deferred with it.
    static func cacheKey(
        path: String,
        frameIndex: Int,
        windowCenter: Double?,
        windowWidth: Double?,
        windowSpace: PrintWindowSpace = .storedValues,
        presentation: ViewerPresentation?
    ) -> String {
        var parts: [String] = [path, String(frameIndex)]
        parts.append(windowCenter.map { String($0) } ?? "-")
        parts.append(windowWidth.map { String($0) } ?? "-")
        // The same pair of numbers is two different pictures depending on the
        // space, so it belongs in the key.
        if windowCenter != nil { parts.append(windowSpace.rawValue) }
        if let presentation {
            parts.append(contentsOf: [
                String(presentation.zoom),
                String(presentation.panX), String(presentation.panY),
                String(presentation.viewportWidth), String(presentation.viewportHeight),
                String(presentation.rotationDegrees),
                presentation.flipHorizontal ? "H" : "",
                presentation.flipVertical ? "V" : "",
                presentation.invert ? "I" : "",
                // The palette recolours every pixel, so two cells identical in
                // every other respect are still two different pictures.
                presentation.palette?.rawValue ?? ""
            ])
        }
        return parts.joined(separator: "|")
    }

    /// Decodes, windows, arranges and scales one frame, off the main actor.
    ///
    /// A supplied window is normally in stored-value space — it comes from the
    /// live viewer, which holds the header VOI divided through the rescale pair
    /// — and is converted back to modality units through the same pair. A
    /// window declared in output units (the print sheet's job-wide window,
    /// which a user types in HU) is already in them. Either way the frame is
    /// rendered through the PS3.4 N.2 chain — the file's Modality LUT, then the
    /// window applied to its output (PS3.3 C.11.2.1.2.1) — by the shared export
    /// policy, ``DICOMImageExporter/determineDisplayPipeline``. Without a window
    /// at all the image's own VOI is resolved by that policy: the header window,
    /// else the VOI LUT Sequence, else the frame's range. That is the same
    /// resolution the focused viewport performs on load, so an un-windowed tile
    /// matches the image beside it.
    ///
    /// Note what must NOT be used here: ``DICOMFile/renderFrameWithStoredWindow``
    /// hands the raw Window Center straight to the renderer, which reads *stored*
    /// pixels. On a CT with a large Rescale Intercept (−1024, −8192) a −615 HU
    /// centre then sits far below every stored value and the frame washes out to
    /// white.
    ///
    /// Arranging happens on the full-resolution frame and scaling last, so a
    /// zoomed tile shows the detail it will print rather than a blow-up of a
    /// thumbnail.
    static func render(
        path: String,
        frameIndex: Int,
        windowCenter: Double?,
        windowWidth: Double?,
        windowSpace: PrintWindowSpace = .storedValues,
        presentation: ViewerPresentation?,
        maxDimension: Int
    ) async -> CGImage? {
        // Decoded pixels are shared and reused: re-windowing or re-cropping the
        // same frame must not re-read and re-decode the file, or a window/level
        // drag renders at the speed of the codec.
        guard let source = await FrameSourceCache.shared.source(forPath: path) else {
            return nil
        }

        return await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let file = source.file
            let isMonochrome = source.pixelData.descriptor
                .photometricInterpretation.isMonochrome

            let pipeline = resolvedPipeline(
                file: file, pixelData: source.pixelData, frameIndex: frameIndex,
                isMonochrome: isMonochrome,
                windowCenter: windowCenter, windowWidth: windowWidth,
                windowSpace: windowSpace)

            // GPU when it is available, exact and worth it; CPU otherwise. The
            // service decides, and its output is byte-identical either way, so a
            // tile rendered on the GPU and the film it is printed on — which stays
            // on the CPU — cannot disagree.
            let rendered = FrameRenderService.shared.renderFrame(
                request(source: source, frameIndex: frameIndex, pipeline: pipeline))
            guard var image = rendered else { return nil }

            // Colour before the overlays and the arrangement, matching the film:
            // the print path palettises the windowed level and *then* burns
            // overlays over it, so doing it in the other order here would tint
            // the burnt-in graphics on screen but not on paper.
            if let palette = presentation?.palette, !palette.isGrayscale {
                image = colorized(image, palette: palette) ?? image
            }

            // Overlay planes go on before the frame is cropped, turned or
            // scaled: they are defined against the image's own pixel matrix, so
            // burning them here means they travel with the picture instead of
            // having to be re-registered against every arrangement.
            image = OverlayPlaneRenderer.burningOverlays(
                of: file.dataSet, onto: image, frameIndex: frameIndex)

            if let presentation, !presentation.isIdentity {
                image = applying(presentation, to: image) ?? image
            }
            return downscaled(image, maxDimension: maxDimension) ?? image
        }.value
    }

    /// Which grayscale chain a frame gets, as one shared decision.
    ///
    /// VOI *resolution* is the policy `DICOMImageExporter` owns, and both the
    /// CLI and the app must reach the same answer. Only the per-pixel mapping
    /// varies by backend — each is handed the resolved chain and applies it.
    ///
    /// The chain is PS3.4 N.2's: this frame's Modality LUT (the Modality LUT
    /// Sequence, else its Rescale pair), then the VOI in modality units (PS3.3
    /// C.11.2.1.2.1), then the Presentation LUT the photometric implies. A
    /// window in stored values — the viewer's convention — is put back into
    /// modality units through the same rescale pair it was divided by, which
    /// is the identity when the file windows through a table LUT; one in
    /// output units is already there. `nil` for colour frames, which have no
    /// grayscale chain.
    ///
    /// Shared by the CPU tile path and the GPU texture path below so a tile cannot
    /// change window merely by changing which renderer drew it.
    static func resolvedPipeline(
        file: DICOMFile,
        pixelData: PixelData,
        frameIndex: Int,
        isMonochrome: Bool,
        windowCenter: Double?,
        windowWidth: Double?,
        windowSpace: PrintWindowSpace
    ) -> GrayscaleDisplayPipeline? {
        guard isMonochrome else { return nil }
        var center: Double? = nil
        var width: Double? = nil
        if let windowCenter, let windowWidth, windowWidth > 0 {
            switch windowSpace {
            case .storedValues:
                let slope = file.rescaleSlope(frameIndex: frameIndex)
                let intercept = file.rescaleIntercept(frameIndex: frameIndex)
                center = windowCenter * slope + intercept
                width = windowWidth * abs(slope)
            case .outputUnits:
                center = windowCenter
                width = windowWidth
            }
        }
        // A LINEAR window narrower than one modality unit is not a window the
        // standard defines (C.11.2.1.2.1: w ≥ 1); the file's own VOI stands in.
        if let w = width, w < 1 { center = nil; width = nil }
        return DICOMImageExporter.determineDisplayPipeline(
            from: file, pixelData: pixelData, frameIndex: frameIndex,
            windowCenter: center, windowWidth: width)
    }

    /// One frame's render request: the resolved chain for a monochrome frame,
    /// the file's palette and ICC Profile (0028,2000) for a colour one.
    static func request(
        source: FrameSource, frameIndex: Int, pipeline: GrayscaleDisplayPipeline?,
        palette: DICOMCore.PseudoColorPalette? = nil
    ) -> FrameRenderRequest {
        FrameRenderRequest(
            pixelData: source.pixelData,
            frameIndex: frameIndex,
            window: nil,
            paletteLUT: source.paletteLUT,
            pseudoColorPalette: palette,
            modalityLUT: pipeline?.modalityLUT,
            voiLUT: pipeline?.voiLUT,
            presentationLUT: pipeline?.presentationLUT,
            // The image's own profile, so colour-managed output shows the
            // file's gamut rather than the display's assumption (C.11.15.1.1).
            iccProfile: iccProfile(of: source.file.dataSet))
    }

    /// The ICC Profile (0028,2000) bytes a colour image carries, if any.
    static func iccProfile(of dataSet: DataSet) -> Data? {
        guard let data = dataSet[.iccProfile]?.valueData, !data.isEmpty else { return nil }
        return data
    }

    #if canImport(Metal)
    /// Renders one frame of a file on disk straight to a GPU texture.
    ///
    /// The tile equivalent of the focused viewport's display path. Everything the
    /// CPU sibling above bakes into pixels — zoom, pan, rotation, flip, inversion —
    /// is deliberately *absent* here: on this path the arrangement is the display
    /// shader's transform, so a tile keeps one texture for its frame and window and
    /// re-draws a quad when a tool moves. That is what makes a synchronised zoom or
    /// window drag across a grid cost one redraw per tile rather than one decode.
    ///
    /// Two things send a tile back to the CPU. Frames with drawable overlay planes
    /// are burned rather than drawn, exactly as the focused viewport refuses them —
    /// a Siemens Patient Protocol has all-zero pixels and its whole content in a
    /// 1-bit plane, so its texture would be a black square. And an unresolvable
    /// window leaves the monochrome kernel with nothing to map, which the CPU
    /// renderer handles by auto-windowing from the pixel range.
    static func renderDisplayTexture(
        path: String,
        frameIndex: Int,
        windowCenter: Double?,
        windowWidth: Double?,
        windowSpace: PrintWindowSpace = .storedValues,
        palette: DICOMCore.PseudoColorPalette? = nil
    ) async -> DisplayFrameTexture? {
        guard let renderer = FrameRenderService.shared.displayRenderer,
              let source = await FrameSourceCache.shared.source(forPath: path) else { return nil }

        return await Task.detached(priority: .userInitiated) { () -> DisplayFrameTexture? in
            let file = source.file
            guard !OverlayPlaneRenderer.hasOverlay(file.dataSet, forFrame: frameIndex) else {
                return nil
            }

            let isMonochrome = source.pixelData.descriptor
                .photometricInterpretation.isMonochrome
            let pipeline = resolvedPipeline(
                file: file, pixelData: source.pixelData, frameIndex: frameIndex,
                isMonochrome: isMonochrome,
                windowCenter: windowCenter, windowWidth: windowWidth,
                windowSpace: windowSpace)
            // The monochrome kernel has no auto-window: a chain with no VOI would
            // be rejected by the renderer anyway, so it falls to the CPU tile.
            if isMonochrome && pipeline?.voiLUT == nil { return nil }

            // The reader's pseudo-colour choice goes into the request, because
            // it is *pixels* and not an arrangement: the shader can turn, crop
            // and invert a cell but it cannot colour one, so unlike zoom and
            // rotation this has to be in the render. Without it the film
            // preview drew every cell grey while the film printed in colour.
            return renderer.renderDisplayTexture(
                request(source: source, frameIndex: frameIndex, pipeline: pipeline,
                        palette: palette))
        }.value
    }
    #endif

    /// The window a frame would be rendered with if none is supplied.
    ///
    /// Needed to seed an edit: a mark made without ever opening the file carries
    /// no window, and a window/level drag has to start from the values the cell
    /// is actually showing rather than from zero. Resolved by the same export
    /// policy ``render(path:frameIndex:windowCenter:windowWidth:presentation:maxDimension:)``
    /// falls back to, so seeding changes nothing on screen until the user drags.
    /// The window is in modality units (``DICOMImageExporter/determineModalityWindow``,
    /// A6 / D65): a caller stores it with ``windowSpace`` so the renderer takes it as is.
    static let resolvedWindowSpace: PrintWindowSpace = .outputUnits

    static func resolvedWindow(path: String, frameIndex: Int) async -> WindowSettings? {
        guard let source = await FrameSourceCache.shared.source(forPath: path) else { return nil }
        return DICOMImageExporter.determineModalityWindow(
            from: source.file, pixelData: source.pixelData, frameIndex: frameIndex,
            windowCenter: nil, windowWidth: nil)
    }

    /// The source frame's own pixel dimensions.
    ///
    /// Needed to restore a stored presentation state onto a film cell: Displayed
    /// Area is a rectangle of *source* pixels, so turning it back into a zoom
    /// and a pan takes the image's real size — guessing it from the cell would
    /// put the crop somewhere else on the anatomy. Read through the same cache
    /// the renderer uses, so a cell already on screen costs nothing.
    static func pixelSize(path: String) async -> CGSize? {
        guard let source = await FrameSourceCache.shared.source(forPath: path) else { return nil }
        let descriptor = source.pixelData.descriptor
        guard descriptor.columns > 0, descriptor.rows > 0 else { return nil }
        return CGSize(width: Double(descriptor.columns), height: Double(descriptor.rows))
    }

    /// The source frame's Photometric Interpretation (0028,0004), as the header
    /// spells it.
    ///
    /// Needed to restore a stored presentation state onto a film cell: a state's
    /// Presentation LUT is stated with the image's MONOCHROME1/2 ignored (PS3.4
    /// N.2), so INVERSE on a MONOCHROME1 image is its upright picture and the
    /// bridge has to know which it is looking at. Same cache as the renderer.
    static func photometricInterpretation(path: String) async -> String? {
        guard let source = await FrameSourceCache.shared.source(forPath: path) else { return nil }
        return source.file.dataSet.string(for: .photometricInterpretation)
            ?? source.pixelData.descriptor.photometricInterpretation.rawValue
    }

    // MARK: - Pseudo-colour

    /// Recolours a rendered grayscale frame through a palette.
    ///
    /// The preview's counterpart to `ImagePreprocessor.colorize`, and it has to
    /// stay its counterpart: this is the one screen whose whole job is to
    /// promise what the film will look like, so the two must index the same
    /// table the same way. Both take the displayed level — after the window,
    /// after polarity — and look it up directly.
    ///
    /// Returns `nil` if the frame is not the 8-bit grayscale the renderer
    /// produces for a monochrome source, in which case the caller keeps the
    /// original: a colour source has its own colours, and a palette has nothing
    /// to say about them.
    static func colorized(
        _ image: CGImage, palette: DICOMCore.PseudoColorPalette
    ) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        // Read the frame back as 8-bit grey regardless of how it was rendered,
        // so the lookup has one predictable input.
        var grey = [UInt8](repeating: 0, count: width * height)
        guard let greyContext = CGContext(
            data: &grey,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        greyContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let table = palette.entries()
        let lastIndex = table.count - 1
        // RGBX rather than packed RGB: CoreGraphics bitmap contexts do not
        // support 24 bits per pixel, which is the same reason `FilmComposer`
        // draws colour into a 32-bit buffer.
        var rgbx = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in 0..<(width * height) {
            let entry = table[min(lastIndex, Int(grey[pixel]))]
            let base = pixel * 4
            rgbx[base] = entry.red
            rgbx[base + 1] = entry.green
            rgbx[base + 2] = entry.blue
            rgbx[base + 3] = 255
        }

        return rgbx.withUnsafeMutableBytes { raw -> CGImage? in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
    }

    // MARK: - Arrangement

    /// Applies a presentation to a rendered frame: crop, rotate, flip, invert.
    ///
    /// The same `ViewerPresentation` the print path consumes, so what a preview
    /// or tile shows is what the film gets.
    static func applying(
        _ presentation: ViewerPresentation,
        to image: CGImage
    ) -> CGImage? {
        var result = image
        if let region = presentation.visibleRegion(
            imageWidth: image.width, imageHeight: image.height),
           let cropped = image.cropping(to: CGRect(
            x: region.x, y: region.y, width: region.width, height: region.height)) {
            result = cropped
        }

        let rotation = presentation.rotationDegrees
        let flipH = presentation.flipHorizontal
        let flipV = presentation.flipVertical

        if rotation != 0 || flipH || flipV {
            // A quarter turn swaps the sides; any other angle keeps the crop's
            // own rectangle and lets the corners fall outside it. The picture
            // turns about its centre at the size it already had — the way the
            // viewer turns one, and the way the film's resampler and the display
            // shader now compose one. Growing to the turned bounding box instead
            // would keep those corners by shrinking the anatomy (√2 at 45°).
            let odd = presentation.isQuarterTurn && presentation.quarterTurns % 2 == 1
            let outWidth = max(1, odd ? result.height : result.width)
            let outHeight = max(1, odd ? result.width : result.height)
            guard let context = CGContext(
                data: nil,
                width: outWidth,
                height: outHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return result }

            // CoreGraphics' origin is bottom-left while the viewer rotates in
            // screen space, so the clockwise turn is negated here — actually
            // negated, in the call. A positive `rotate(by:)` in a bottom-left
            // context comes out *counterclockwise* once the bitmap is shown
            // top-down: mirrors survive the flip between the two spaces, but a
            // rotation conjugated through it reverses. This line carried the
            // angle un-negated with only the comment claiming otherwise, and
            // every thumbnail and CPU-drawn cell turned its image the opposite
            // way from the viewer, twice the angle apart.
            context.translateBy(x: Double(outWidth) / 2, y: Double(outHeight) / 2)
            context.scaleBy(x: flipH ? -1 : 1, y: flipV ? -1 : 1)
            context.rotate(by: -rotation * .pi / 180)
            context.draw(result, in: CGRect(
                x: -Double(result.width) / 2,
                y: -Double(result.height) / 2,
                width: Double(result.width),
                height: Double(result.height)))
            result = context.makeImage() ?? result
        }

        if presentation.invert {
            result = ImageInversion.inverted(result) ?? result
        }
        return result
    }

    // MARK: - Scaling

    /// Scales an image down so its longest edge is at most `maxDimension`.
    ///
    /// Only ever downscales: enlarging here would waste memory and add nothing,
    /// since the view scales to its own box anyway.
    static func downscaled(_ image: CGImage, maxDimension: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxDimension, maxDimension > 0 else { return image }

        let scale = Double(maxDimension) / Double(longest)
        let targetWidth = max(1, Int((Double(image.width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(image.height) * scale).rounded()))

        // An 8-bit RGBA context: the source may be 16-bit grayscale or indexed,
        // and matching that exactly buys nothing for a scaled-down copy.
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }
}
#endif
