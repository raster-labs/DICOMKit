// MetalFrameRenderer.swift
// DICOMRenderKit — GPU_RENDERING_PLAN.md milestones M3 (monochrome) and M4 (colour)
//
// The GPU backend. Wraps the decoded frame without copying it, dispatches a
// compute kernel over a byte table built on the CPU, and hands the shader's own
// output memory straight to CoreGraphics — no upload, no readback.
//
// NEMA-verified: 2026a, checked 2026-09-30 — Pixel Cells wider than two bytes are declined (PS3.5 2026a 8.1.1; were read as their low 16 bits); tables are the CPU's own DICOMCore builders; planar offsets per C.7.6.3.1.3; YBR stays on the CPU (C.7.6.3.1.2); parameter blocks match the kernels field for field; monochrome frames index the request's grey table (the N.2 chain, P-PIPELINE) and colour output carries the ICC Profile's colour space (C.11.15.1.1, P-ICC) (Scripts/diff_renderkit.py).

import Foundation
import DICOMCore

#if canImport(Metal) && canImport(CoreGraphics)
import Metal
import CoreGraphics

/// Renders DICOM frames with Metal compute.
///
/// Returns `nil` for anything it cannot handle — an unsupported layout, a YBR
/// frame, a frame larger than the shader's 32-bit offsets, any Metal failure — and
/// ``FrameRenderService`` then renders it on the CPU. Every one of those is a
/// correctness-preserving fallback, never a blank image.
public final class MetalFrameRenderer: FrameRenderBackend, @unchecked Sendable {

    public var backend: RenderBackend { .metal }

    private let renderDevice: MetalRenderDevice
    private let pool: UnifiedMemoryPool

    /// Free table buffers, reused across renders.
    ///
    /// A window drag changes the table on every mouse delta, so these are written
    /// often — but they are allocated once. 64 KB written per drag step is the
    /// *entire* per-frame data movement in this design.
    ///
    /// A free list rather than one buffer per slot: a table is written by the CPU and
    /// then read by a dispatch that runs *after* the lock is released, so a buffer
    /// held across renders is shared mutable state between them. Concurrent renders —
    /// a pane of series thumbnails is a dozen of them at once — would then trample
    /// each other's window table and window a CT with an MR's LUT. Each dispatch
    /// borrows its tables for its own lifetime and returns them when it completes.
    private let lock = NSLock()
    private var freeTableBuffers: [MTLBuffer] = []

    /// How many table buffers to keep between renders. Above the peak concurrency a
    /// viewer actually reaches, so the steady state still allocates nothing.
    private static let retainedTableBuffers = 16

    /// Frames smaller than this render on the CPU instead. **Zero: no frame is
    /// declined for being small.**
    ///
    /// This was one megapixel, from a measurement that still holds: a dispatch —
    /// encode, commit, wait — costs about 0.24 ms whatever the image size, while
    /// the LUT-based CPU renderer runs at roughly 0.53 ms per megapixel, so below
    /// about half a megapixel the fixed cost dominates and the GPU loses on raw
    /// time. On an M4 a 512×512 CT takes 0.156 ms on the CPU and 0.254 ms on the GPU.
    ///
    /// It is nevertheless zero by project policy: the GPU renders every frame it
    /// can, and the CPU is a fallback for when there is no GPU — not a faster
    /// alternative to be selected into. The ~0.1 ms this concedes on small frames
    /// buys one rendering path to reason about instead of a size-dependent pair.
    /// Nothing about the *picture* changes either way: `MetalCPUEquivalenceTests`
    /// holds GPU and CPU output to byte-for-byte equality, so this is a pure
    /// scheduling decision.
    ///
    /// The constant and the `minimumPixelCount` parameter are kept rather than
    /// deleted so benchmarks can still measure the crossover, and so restoring a
    /// threshold is a one-line change if the concession ever stops being worth it.
    public static let minimumGPUPixelCount = 0

    /// The threshold this instance applies. Lowered to 0 by the equivalence tests,
    /// which must exercise the kernels on small synthetic frames — the shader's
    /// correctness does not depend on the frame being big enough to be worth
    /// dispatching, and the tests need to prove that on frames they can enumerate
    /// exhaustively.
    private let minimumPixelCount: Int

    public init?(
        device: MetalRenderDevice? = MetalRenderDevice.shared,
        minimumPixelCount: Int = MetalFrameRenderer.minimumGPUPixelCount
    ) {
        guard let device else { return nil }
        self.renderDevice = device
        self.pool = UnifiedMemoryPool(device: device.device)
        self.minimumPixelCount = minimumPixelCount
    }

    // MARK: - Entry point

    public func renderFrame(_ request: FrameRenderRequest) -> CGImage? {
        render(request, as: .cgImage)?.image
    }

    /// Renders a frame to a texture for on-screen display (M5).
    ///
    /// Same kernels, same tables, same pixels as ``renderFrame(_:)`` — only the
    /// destination differs. The texture is a view onto the shared buffer the shader
    /// wrote, so this is no more copying than the `CGImage` path.
    ///
    /// This is what lets tool actions be cheap: once a frame is a texture, zoom,
    /// pan, rotation, flip and inversion are a matrix multiply in the display
    /// shader. Changing any of them redraws a quad and touches no pixel data.
    ///
    /// Unlike ``renderFrame(_:)`` this ignores ``minimumGPUPixelCount``: the
    /// threshold exists because a dispatch that ends in a `CGImage` costs more than
    /// a small CPU render. A frame already destined for a GPU texture has no cheaper
    /// route.
    public func renderDisplayTexture(_ request: FrameRenderRequest) -> DisplayFrameTexture? {
        renderForDisplay(request)?.texture
    }

    /// Renders once and returns both a display texture and a `CGImage` over the
    /// **same** output memory.
    ///
    /// The focused viewport needs both: the texture to draw, and the image for
    /// everything that still expects one. Rendering twice would double the dispatch
    /// for no reason — a texture view and a `CGImage` are both just interpretations
    /// of the bytes the shader wrote, and `CGImage` accepts the padded row stride a
    /// texture view requires.
    ///
    /// The output buffer returns to the pool only when **both** have been released;
    /// they share one owner. Recycling while either was still reading would corrupt
    /// whatever is on screen.
    public func renderForDisplay(
        _ request: FrameRenderRequest
    ) -> (texture: DisplayFrameTexture, image: CGImage)? {
        guard let output = render(request, as: .texture),
              let texture = output.texture,
              let image = output.image,
              let box = output.box else { return nil }
        return (DisplayFrameTexture(texture: texture,
                                    isGrayscale: output.isGrayscale,
                                    colorSpace: output.isGrayscale ? nil : request.outputColorSpace,
                                    retaining: box),
                image)
    }

    private func render(_ request: FrameRenderRequest, as destination: Destination) -> RenderOutput? {
        switch request.family {
        case .monochrome:
            // The table the CPU indexes too: the stored-unit window's `WindowLUT`, or
            // the PS3.4 N.2 chain's table (P-PIPELINE). No VOI means "auto-window from
            // this frame's pixel range", which requires a full scan of the pixels the
            // CPU renderer already does. Reproducing that scan here would be a second
            // implementation of a policy decision, so the CPU keeps it (`nil` here).
            guard let lut = request.greyTable else { return nil }
            // A pseudo-colour palette recolours the windowed level, so the two
            // tables fold into one raw-sample → RGB lookup and the frame goes
            // through the palette kernel instead. Same dispatch, same tables'
            // shape, four bytes out rather than one — which is what lets a grey
            // frame come off the GPU in colour without a shader that knows about
            // palettes.
            if let palette = request.effectivePseudoColorPalette {
                let colours = PaletteDisplayLUT.make(window: lut, entries: palette.entries())
                return renderPalette(request, lut: colours, destination: destination)
            }
            return renderMonochrome(request, lut: lut, destination: destination)
        case .palette:
            // A reader's ramp over a frame that already carries colours is a
            // pass over the finished frame's luminance, which no kernel here
            // does. Declining sends it to the CPU, which is exactly the
            // contract `FrameRenderService` is built on — the GPU path stays
            // narrow and exact rather than broad and approximate.
            guard request.readerPalette == nil else { return nil }
            guard let palette = request.paletteLUT else { return nil }
            return renderPalette(request, palette: palette, destination: destination)
        case .color:
            guard request.readerPalette == nil else { return nil }
            return renderColor(request, destination: destination)
        }
    }

    /// Where a dispatch puts its result.
    enum Destination {
        /// A `CGImage` over the output buffer — the type ~12 existing call sites want.
        /// Row stride is exactly the pixel width, so the equality tests can compare
        /// whole buffers.
        case cgImage
        /// A texture view over the output buffer, for the display path. Row stride is
        /// padded to `minimumLinearTextureAlignment`, which a texture view requires.
        case texture
    }

    struct RenderOutput {
        var image: CGImage?
        var texture: MTLTexture?
        var box: OutputBufferBox?
        var isGrayscale: Bool
    }

    // MARK: - Monochrome

    private struct MonochromeParams {
        var width: UInt32
        var height: UInt32
        var frameByteOffset: UInt32
        var bytesPerSample: UInt32
        var availablePixels: UInt32
        var outputRowStride: UInt32
    }

    private func renderMonochrome(
        _ request: FrameRenderRequest, lut: WindowLUT, destination: Destination
    ) -> RenderOutput? {
        let descriptor = request.pixelData.descriptor
        guard let geometry = FrameGeometry(
            request,
            minimumPixelCount: destination == .texture ? 0 : minimumPixelCount
        ) else { return nil }

        // The same table the CPU renderer uses — built by the same code, from the
        // same WindowSettings.apply (or the same GrayscaleDisplayPipeline). This is
        // what makes GPU output bit-identical rather than merely close.
        let stride = rowStride(pixelWidth: geometry.width, bytesPerPixel: 1, destination: destination)

        var params = MonochromeParams(
            width: UInt32(geometry.width),
            height: UInt32(geometry.height),
            frameByteOffset: UInt32(geometry.frameOffset),
            bytesPerSample: UInt32(descriptor.bytesPerSample),
            availablePixels: UInt32(geometry.availablePixels),
            outputRowStride: UInt32(stride)
        )

        return dispatch(
            request: request,
            geometry: geometry,
            kernel: MetalKernel.monochrome,
            bytesPerRow: stride,
            isGrayscale: true,
            destination: destination,
            configure: { encoder, input, output, lease in
                encoder.setBuffer(input, offset: 0, index: 0)
                encoder.setBytes(&params, length: MemoryLayout<MonochromeParams>.stride, index: 1)
                guard let table = self.tableBuffer(lut.table, lease: lease) else { return false }
                encoder.setBuffer(table, offset: 0, index: 2)
                encoder.setBuffer(output, offset: 0, index: 3)
                return true
            }
        )
    }

    // MARK: - Colour

    private struct ColorParams {
        var width: UInt32
        var height: UInt32
        var frameByteOffset: UInt32
        var bytesPerSample: UInt32
        var planarConfiguration: UInt32
        var frameByteCount: UInt32
        var planeSizeBytes: UInt32
        var outputRowStride: UInt32
    }

    private func renderColor(
        _ request: FrameRenderRequest, destination: Destination
    ) -> RenderOutput? {
        let descriptor = request.pixelData.descriptor
        guard descriptor.samplesPerPixel == 3 else { return nil }

        // YBR stays on the CPU — deliberately, and permanently.
        //
        // The plan required this decision to be made explicitly here rather than
        // discovered in review. The RGB and palette maps are pure functions of ONE
        // sample, so a table reproduces the CPU's Double arithmetic exactly. YBR is
        // not: green depends on all three of Y, Cb and Cr, so an exact table would
        // need 2^24 entries (16 MB, ~17 million Double evaluations to build), and
        // any smaller formulation means recomputing those coefficients in `float`
        // on the GPU. Float would diverge from the CPU's `Double` at truncation
        // boundaries — one grey level, on some pixels — and that is precisely the
        // divergence design pillar 1 exists to prevent.
        //
        // So: no tolerance is accepted for this path. YBR frames render on the CPU,
        // where they are already fast enough (ultrasound and secondary capture, not
        // mammograms), and remain bit-identical everywhere.
        guard !descriptor.photometricInterpretation.isYBR else { return nil }

        guard let geometry = FrameGeometry(
            request,
            minimumPixelCount: destination == .texture ? 0 : minimumPixelCount
        ) else { return nil }
        let lut = ColorSampleLUT.normalisation(for: descriptor)
        let stride = rowStride(pixelWidth: geometry.width, bytesPerPixel: 4, destination: destination)

        var params = ColorParams(
            width: UInt32(geometry.width),
            height: UInt32(geometry.height),
            frameByteOffset: UInt32(geometry.frameOffset),
            bytesPerSample: UInt32(descriptor.bytesPerSample),
            planarConfiguration: UInt32(descriptor.planarConfiguration),
            frameByteCount: UInt32(geometry.frameByteCount),
            planeSizeBytes: UInt32(geometry.pixelCount * descriptor.bytesPerSample),
            outputRowStride: UInt32(stride)
        )

        return dispatch(
            request: request,
            geometry: geometry,
            kernel: MetalKernel.color,
            bytesPerRow: stride,
            isGrayscale: false,
            destination: destination,
            configure: { encoder, input, output, lease in
                encoder.setBuffer(input, offset: 0, index: 0)
                encoder.setBytes(&params, length: MemoryLayout<ColorParams>.stride, index: 1)
                guard let table = self.tableBuffer(lut.table, lease: lease) else { return false }
                encoder.setBuffer(table, offset: 0, index: 2)
                encoder.setBuffer(output, offset: 0, index: 3)
                return true
            }
        )
    }

    // MARK: - Palette colour

    private struct PaletteParams {
        var width: UInt32
        var height: UInt32
        var frameByteOffset: UInt32
        var bytesPerSample: UInt32
        var availablePixels: UInt32
        var outputRowStride: UInt32
    }

    private func renderPalette(
        _ request: FrameRenderRequest, palette: PaletteColorLUT, destination: Destination
    ) -> RenderOutput? {
        let lut = PaletteDisplayLUT.make(
            descriptor: request.pixelData.descriptor, palette: palette)
        return renderPalette(request, lut: lut, destination: destination)
    }

    /// The palette kernel over tables that are already built.
    ///
    /// Shared by the two things that end in a raw-sample → RGB lookup: a
    /// PALETTE COLOR frame's own table, and a monochrome frame's window folded
    /// together with a reader's pseudo-colour ramp.
    private func renderPalette(
        _ request: FrameRenderRequest, lut: PaletteDisplayLUT, destination: Destination
    ) -> RenderOutput? {
        let descriptor = request.pixelData.descriptor
        guard let geometry = FrameGeometry(
            request,
            minimumPixelCount: destination == .texture ? 0 : minimumPixelCount
        ) else { return nil }

        let stride = rowStride(pixelWidth: geometry.width, bytesPerPixel: 4, destination: destination)

        var params = PaletteParams(
            width: UInt32(geometry.width),
            height: UInt32(geometry.height),
            frameByteOffset: UInt32(geometry.frameOffset),
            bytesPerSample: UInt32(descriptor.bytesPerSample),
            availablePixels: UInt32(geometry.availablePixels),
            outputRowStride: UInt32(stride)
        )

        return dispatch(
            request: request,
            geometry: geometry,
            kernel: MetalKernel.palette,
            bytesPerRow: stride,
            isGrayscale: false,
            destination: destination,
            configure: { encoder, input, output, lease in
                encoder.setBuffer(input, offset: 0, index: 0)
                encoder.setBytes(&params, length: MemoryLayout<PaletteParams>.stride, index: 1)
                guard let red = self.tableBuffer(lut.red, lease: lease),
                      let green = self.tableBuffer(lut.green, lease: lease),
                      let blue = self.tableBuffer(lut.blue, lease: lease) else { return false }
                encoder.setBuffer(red, offset: 0, index: 2)
                encoder.setBuffer(green, offset: 0, index: 3)
                encoder.setBuffer(blue, offset: 0, index: 4)
                encoder.setBuffer(output, offset: 0, index: 5)
                return true
            }
        )
    }

    // MARK: - Dispatch

    /// The shape of one frame within the wrapped pixel buffer.
    private struct FrameGeometry {
        let width: Int
        let height: Int
        let pixelCount: Int
        let frameOffset: Int
        let frameByteCount: Int
        let availablePixels: Int

        init?(_ request: FrameRenderRequest, minimumPixelCount: Int) {
            let descriptor = request.pixelData.descriptor
            let width = descriptor.columns
            let height = descriptor.rows
            // The kernels assemble a sample from one or two bytes, and the tables
            // have 256 or 65,536 entries. A Pixel Cell is Bits Allocated wide
            // (PS3.5 8.1.1), so a 32-bit cell read as its low two bytes would be a
            // different value. Declined: such frames go to the CPU.
            guard width > 0, height > 0,
                  (1...2).contains(descriptor.bytesPerSample) else { return nil }

            let pixelCount = width * height
            let frameByteCount = descriptor.bytesPerFrame
            let frameOffset = request.frameIndex * frameByteCount

            // Mirrors `PixelData.frameData(at:)`, which returns nil — and so
            // renders nothing — when the frame is not wholly present.
            guard request.frameIndex >= 0,
                  request.frameIndex < descriptor.numberOfFrames,
                  frameOffset + frameByteCount <= request.pixelData.data.count else {
                return nil
            }

            // The shader addresses bytes with 32-bit offsets. A frame beyond 4 GB
            // is not something to silently mis-render.
            guard frameOffset + frameByteCount <= Int(UInt32.max),
                  pixelCount * 4 <= Int(UInt32.max) else {
                return nil
            }

            // Too small to be worth a dispatch — the CPU is measurably faster.
            guard pixelCount >= minimumPixelCount else { return nil }

            self.width = width
            self.height = height
            self.pixelCount = pixelCount
            self.frameOffset = frameOffset
            self.frameByteCount = frameByteCount
            self.availablePixels = min(pixelCount, frameByteCount / descriptor.bytesPerSample)
        }
    }

    /// Bytes per output row.
    ///
    /// The `CGImage` path uses exactly the pixel width, which keeps the output a
    /// dense buffer that equality tests can compare whole. A texture view over a
    /// buffer must honour `minimumLinearTextureAlignment`, so the display path pads
    /// — and the kernels take the stride as a parameter rather than assuming either.
    private func rowStride(pixelWidth: Int, bytesPerPixel: Int, destination: Destination) -> Int {
        let dense = pixelWidth * bytesPerPixel
        guard destination == .texture else { return dense }
        let format: MTLPixelFormat = bytesPerPixel == 1 ? .r8Unorm : .rgba8Unorm
        let alignment = max(1, renderDevice.device.minimumLinearTextureAlignment(for: format))
        return ((dense + alignment - 1) / alignment) * alignment
    }

    private func dispatch(
        request: FrameRenderRequest,
        geometry: FrameGeometry,
        kernel: String,
        bytesPerRow: Int,
        isGrayscale: Bool,
        destination: Destination,
        configure: (MTLComputeCommandEncoder, MTLBuffer, MTLBuffer, TableLease) -> Bool
    ) -> RenderOutput? {
        let outputByteCount = bytesPerRow * geometry.height
        guard let pipeline = renderDevice.pipelineState(for: kernel),
              let (input, _) = pool.inputBuffer(for: request.pixelData, frameIndex: request.frameIndex),
              let output = pool.outputBuffer(byteCount: outputByteCount),
              let commandBuffer = renderDevice.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        // Tables belong to this dispatch alone until the GPU is done reading them.
        let lease = TableLease()
        defer { returnTables(lease) }

        encoder.setComputePipelineState(pipeline)
        guard configure(encoder, input, output, lease) else {
            encoder.endEncoding()
            pool.recycle(output)
            return nil
        }

        // Uniform threadgroups with an in-kernel bounds check, rather than
        // `dispatchThreads`: it works on every Metal device without a
        // non-uniform-threadgroup capability check, and the guard clause the
        // kernels already carry makes the rounded-up grid harmless.
        let executionWidth = pipeline.threadExecutionWidth
        let groupHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / executionWidth)
        let threadsPerGroup = MTLSize(width: executionWidth, height: groupHeight, depth: 1)
        let groups = MTLSize(
            width: (geometry.width + executionWidth - 1) / executionWidth,
            height: (geometry.height + groupHeight - 1) / groupHeight,
            depth: 1
        )
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard commandBuffer.error == nil else {
            pool.recycle(output)
            return nil
        }

        // One owner for the output buffer, shared by every view onto it. The buffer
        // returns to the pool when the last of them is released.
        let box = OutputBufferBox(buffer: output, pool: pool)

        guard let image = makeImage(
            box: box, byteCount: outputByteCount,
            width: geometry.width, height: geometry.height,
            bytesPerRow: bytesPerRow, isGrayscale: isGrayscale,
            colorSpace: isGrayscale ? nil : request.outputColorSpace
        ) else {
            return nil
        }

        guard destination == .texture else {
            return RenderOutput(image: image, texture: nil, box: box,
                                isGrayscale: isGrayscale)
        }

        // A view onto the buffer the shader just wrote — no copy, no upload.
        let format: MTLPixelFormat = isGrayscale ? .r8Unorm : .rgba8Unorm
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: geometry.width, height: geometry.height,
            mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = output.makeTexture(
            descriptor: descriptor, offset: 0, bytesPerRow: bytesPerRow
        ) else {
            return nil
        }
        return RenderOutput(image: image, texture: texture, box: box,
                            isGrayscale: isGrayscale)
    }

    /// Builds a `CGImage` over the shader's own output memory.
    ///
    /// This is the half of design pillar 2 that removes the readback: there is no
    /// `getBytes`, no second allocation, no copy. CoreGraphics reads the shared
    /// buffer the GPU just wrote, and the buffer returns to the pool when the image
    /// is released — which is the only moment it is provably safe to reuse.
    private func makeImage(
        box: OutputBufferBox, byteCount: Int,
        width: Int, height: Int, bytesPerRow: Int, isGrayscale: Bool,
        colorSpace: CGColorSpace? = nil
    ) -> CGImage? {
        let info = Unmanaged.passRetained(box).toOpaque()

        guard let provider = CGDataProvider(
            dataInfo: info,
            data: box.buffer.contents(),
            size: byteCount,
            releaseData: { info, _, _ in
                guard let info else { return }
                Unmanaged<OutputBufferBox>.fromOpaque(info).release()
            }
        ) else {
            Unmanaged<OutputBufferBox>.fromOpaque(info).release()
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: isGrayscale ? 8 : 32,
            bytesPerRow: bytesPerRow,
            // The ICC Profile's space for colour output when the request has one
            // (PS3.3 C.11.15.1.1, P-ICC); Device RGB / Gray otherwise.
            space: isGrayscale ? CGColorSpaceCreateDeviceGray() : (colorSpace ?? CGColorSpaceCreateDeviceRGB()),
            bitmapInfo: CGBitmapInfo(rawValue: isGrayscale
                                     ? CGImageAlphaInfo.none.rawValue
                                     : CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// The table buffers one dispatch has borrowed — the palette kernel takes three,
    /// live simultaneously — held until that dispatch completes.
    final class TableLease {
        fileprivate var buffers: [MTLBuffer] = []
    }

    /// Writes a byte table into a shared buffer borrowed for this dispatch.
    ///
    /// The buffer is the dispatch's own until ``returnTables(_:)`` hands it back, so
    /// a render running concurrently cannot overwrite the table this one is about to
    /// read.
    private func tableBuffer(_ table: [UInt8], lease: TableLease) -> MTLBuffer? {
        lock.lock()
        let reused = freeTableBuffers.popLast()
        lock.unlock()

        let buffer: MTLBuffer
        if let reused, reused.length >= table.count {
            buffer = reused
        } else {
            // Always allocate the largest table size so a switch between 8- and
            // 16-bit images does not reallocate.
            guard let created = renderDevice.device.makeBuffer(
                length: 65_536,
                options: [.storageModeShared, .hazardTrackingModeUntracked]
            ) else { return nil }
            buffer = created
        }

        table.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            buffer.contents().copyMemory(from: base, byteCount: table.count)
        }
        lease.buffers.append(buffer)
        return buffer
    }

    /// Returns a completed dispatch's tables for the next render to borrow.
    private func returnTables(_ lease: TableLease) {
        guard !lease.buffers.isEmpty else { return }
        lock.lock()
        for buffer in lease.buffers where freeTableBuffers.count < Self.retainedTableBuffers {
            freeTableBuffers.append(buffer)
        }
        lock.unlock()
        lease.buffers.removeAll()
    }

    // MARK: - Diagnostics

    /// Buffer allocation / pixel copy counters, so the zero-copy claim can be
    /// asserted by a test rather than trusted.
    var memoryCounters: UnifiedMemoryPool.Counters { pool.counters }

    /// Releases pooled GPU memory.
    public func purgeCaches() {
        lock.lock()
        freeTableBuffers.removeAll()
        lock.unlock()
        pool.purge()
    }
}

/// Keeps an output buffer alive for exactly as long as the `CGImage` reading it,
/// then returns it to the pool.
final class OutputBufferBox {
    let buffer: MTLBuffer
    let pool: UnifiedMemoryPool

    init(buffer: MTLBuffer, pool: UnifiedMemoryPool) {
        self.buffer = buffer
        self.pool = pool
    }

    deinit {
        pool.recycle(buffer)
    }
}
#endif
