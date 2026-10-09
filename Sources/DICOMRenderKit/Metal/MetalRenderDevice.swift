// MetalRenderDevice.swift
// DICOMRenderKit — GPU_RENDERING_PLAN.md milestone M2
//
// The process-wide Metal device, command queue, shader library and pipeline-state
// cache. One of these, created lazily, `nil` when the machine has no GPU.
//
// NEMA-verified: 2026a, checked 2026-09-30 — carries no DICOM-standard data (device, queue, shader library, pipeline cache, kernel names). C1 classification confirmed.

import Foundation

#if canImport(Metal)
import Metal

/// Owns the Metal objects the frame renderer needs, for the life of the process.
///
/// Everything here is expensive to create and safe to share: `MTLDevice` and
/// `MTLCommandQueue` are thread-safe, and compiled pipeline states are immutable.
/// The only mutable state is the pipeline cache, which is lock-guarded.
public final class MetalRenderDevice: @unchecked Sendable {

    /// The shared device, or `nil` on a machine with no Metal GPU (CI containers,
    /// some VMs). Every caller must handle `nil` — that is what makes `.cpu` the
    /// guaranteed fallback rather than a nice-to-have.
    public static let shared: MetalRenderDevice? = MetalRenderDevice()

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let library: MTLLibrary

    /// The shader resource, as named in `Package.swift`. See `loadLibrary` for why
    /// it is not called `FrameRender.metal`.
    static let shaderResourceName = "FrameRender.metal"
    static let shaderResourceExtension = "txt"

    /// Where the shader source actually lives. Resolved here rather than at the
    /// call site because `Bundle.module` is per-target: from a test file it would
    /// mean the *test* bundle, which has no resources.
    static var shaderResourceURL: URL? {
        Bundle.module.url(forResource: shaderResourceName,
                          withExtension: shaderResourceExtension)
    }

    private let lock = NSLock()
    private var pipelineStates: [String: MTLComputePipelineState] = [:]

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        guard let library = Self.loadLibrary(device: device) else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        self.library = library
    }

    /// Loads the shader library — once, at first use, by compiling the shader
    /// source shipped in `Bundle.module`.
    ///
    /// The plan assumed SwiftPM would compile the target's `.metal` file into a
    /// `default.metallib` in its resource bundle, to be loaded with
    /// `makeDefaultLibrary(bundle:)`. **It does not.** Command-line SwiftPM
    /// silently ignores a `.metal` file in a target's sources: no metallib, no
    /// resource bundle, no warning. Verified with a minimal probe package before
    /// changing course, because the failure is invisible — everything builds and
    /// only the GPU path goes missing.
    ///
    /// Xcode's build system, by contrast, is *not* indifferent to the extension:
    /// it matches its CompileMetalFile rule on `.metal` alone — even for a file
    /// declared as a resource rather than a source — and hard-fails the build when
    /// the optional Metal Toolchain component is not installed. So the shader
    /// ships as `FrameRender.metal.txt`, which no build rule claims, and is
    /// compiled here once per process.
    ///
    /// That is a deliberate choice of one path over two. Ahead-of-time compilation
    /// would be marginally faster to first render, but only under Xcode and only
    /// with an extra multi-gigabyte download — meaning the shipping app would run
    /// a shader binary that `swift test` and CI never exercise. One runtime-compiled
    /// library everywhere is worth more here than a first-render saving, since the
    /// GPU output has to stay bit-identical to the CPU's.
    private static func loadLibrary(device: MTLDevice) -> MTLLibrary? {
        guard let url = shaderResourceURL,
              let source = try? String(contentsOf: url, encoding: .utf8),
              let library = try? device.makeLibrary(source: source, options: nil) else {
            return nil
        }
        return library
    }

    /// A compute pipeline state for a kernel, compiled once and reused.
    ///
    /// There are no function constants to key on: the per-pixel decisions the plan
    /// proposed specialising (`isSigned`, `bitShift`) are folded into the window
    /// table before the shader ever sees them, and the two that remain
    /// (`bytesPerSample`, `planarConfiguration`) are uniform branches — free on
    /// Apple GPUs, where every thread in a dispatch takes the same side. So the
    /// cache is keyed on the function name alone.
    public func pipelineState(for functionName: String) -> MTLComputePipelineState? {
        lock.lock()
        if let cached = pipelineStates[functionName] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let function = library.makeFunction(name: functionName),
              let state = try? device.makeComputePipelineState(function: function) else {
            return nil
        }

        lock.lock()
        pipelineStates[functionName] = state
        lock.unlock()
        return state
    }

    /// Whether this device addresses one pool of memory with the CPU.
    ///
    /// The condition the whole zero-copy design rests on. False on Intel Macs with
    /// a discrete GPU, where `RenderBackend.automatic()` therefore chooses `.cpu`.
    public var hasUnifiedMemory: Bool { device.hasUnifiedMemory }
}

/// Kernel function names, in one place so Swift and the smoke test cannot drift
/// from the `.metal` file.
public enum MetalKernel {
    public static let monochrome = "render_monochrome"
    public static let color = "render_color"
    public static let palette = "render_palette"

    /// Display pipeline (M5) — geometry only; these do not decide pixel values.
    public static let displayVertex = "display_vertex"
    public static let displayFragment = "display_fragment"

    /// Compute kernels. `pipelineState(for:)` builds *compute* states, so the
    /// display functions — which are vertex/fragment stages — are deliberately not
    /// in this list.
    public static let all = [monochrome, color, palette]

    /// Every function the library must contain, compute and display alike.
    public static let allFunctions = [monochrome, color, palette,
                                      displayVertex, displayFragment]
}
#endif
