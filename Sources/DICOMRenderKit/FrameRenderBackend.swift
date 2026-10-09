// FrameRenderBackend.swift
// DICOMRenderKit — GPU_RENDERING_PLAN.md milestone M2
//
// The one interface the CPU and Metal renderers both satisfy, and the request
// type that describes a frame render without committing to how it happens.
//
// NEMA-verified: 2026a, checked 2026-09-30 — routing by Photometric Interpretation (MONOCHROME1/2 → monochrome, PALETTE COLOR → palette, others → colour) matches PS3.3 2026a C.7.6.3.1.2; the request carries the PS3.4 N.2 chain — Modality LUT (C.11.1), VOI window or LUT (C.11.2, applied after the Modality LUT per C.11.2.1.2.1), Presentation LUT (C.11.6; MONOCHROME1 → INVERSE) — and the ICC Profile (C.11.15.1.1) for colour output (P-PIPELINE, P-ICC, approved 2026-09-30). Scripts/diff_renderkit.py.

import Foundation
import DICOMCore
import DICOMKit

#if canImport(CoreGraphics)
import CoreGraphics

// MARK: - Request

/// Everything needed to turn one frame of decoded pixel data into a displayable
/// image.
///
/// Deliberately does **not** carry zoom, pan, rotation or flip. Those are
/// arrangement, applied after the frame is rendered, and folding them in here
/// would put them in every cache key — which is exactly the problem M6 exists to
/// undo.
public struct FrameRenderRequest: Sendable {
    /// The decoded pixels. When its ``PixelData/alignedStorage`` is non-nil the
    /// Metal backend can read it without a copy.
    public let pixelData: PixelData

    /// Zero-based frame index.
    public let frameIndex: Int

    /// The VOI window for monochrome frames.
    ///
    /// Required for monochrome; ignored otherwise. Resolving *which* window
    /// (explicit → the file's rescale-adjusted VOI → the frame's pixel range) is
    /// `DICOMImageExporter.determineWindowSettings`' job and stays there — this
    /// layer renders the window it is handed and makes no policy of its own. That
    /// separation is what keeps the CLI and the app agreeing on what an image
    /// looks like.
    ///
    /// Its units depend on ``usesDisplayPipeline``:
    ///
    /// - With none of ``modalityLUT``, ``voiLUT`` and ``presentationLUT`` set, it is in
    ///   **stored-value** units and is applied to the stored sample, as before
    ///   P-PIPELINE. A window converted to stored units by `(c − b) / m`, `w / |m|`
    ///   renders the standard's picture only for a slope of 1 (D65).
    /// - With any of them set, it is in **modality** units — the output of
    ///   ``modalityLUT`` — as PS3.3 C.11.2.1.2.1 defines it, and ``voiLUT`` takes
    ///   precedence over it.
    public let window: WindowSettings?

    /// Palette tables for PALETTE COLOR frames. Ignored otherwise.
    public let paletteLUT: PaletteColorLUT?

    /// A pseudo-colour palette the reader chose.
    ///
    /// Applied to a monochrome frame *after* the window, as part of the same
    /// table; applied to a frame that carries its own colours as a pass over its
    /// luminance. Either way it is a display choice and never a change to the
    /// stored pixels — the same measurement under two ramps is one measurement
    /// seen two ways.
    ///
    /// Not the same thing as ``paletteLUT``, and deliberately a separate field:
    /// that one is the file's own colour table, a property of the pixels, while
    /// this is the reader's. A palette-colour frame can carry both — the file's
    /// table makes the picture, and the reader's ramp then re-maps what that
    /// picture looks like — and keeping the two apart is what stops one being
    /// mistaken for the other.
    public let pseudoColorPalette: PseudoColorPalette?

    /// The Modality LUT (PS3.3 C.11.1): Rescale Slope / Intercept or the Modality LUT
    /// Sequence. `nil` is the identity. Monochrome only.
    public let modalityLUT: ModalityLUT?

    /// The VOI transformation in modality units (C.11.2): a window, or the VOI LUT
    /// Sequence table. Takes precedence over ``window``. Monochrome only.
    public let voiLUT: VOILUT?

    /// The Presentation LUT (C.11.6). `nil` means INVERSE for MONOCHROME1 (C.7.6.3.1.2)
    /// and IDENTITY otherwise; an explicit value is used as given (PS3.4 N.2: a
    /// presentation state's Presentation LUT replaces the image's polarity).
    public let presentationLUT: PresentationLUT?

    /// The image's ICC Profile (0028,2000) (C.11.15.1.1), for colour output. The
    /// rendered image is tagged with it, so Core Graphics / the display layer convert
    /// from the profile's device colours to the screen. Ignored for monochrome frames
    /// and when a reader's ramp replaces the colours; a profile that does not parse
    /// as an RGB colour space leaves the output Device RGB, as before P-ICC.
    public let iccProfile: Data?

    public init(
        pixelData: PixelData,
        frameIndex: Int = 0,
        window: WindowSettings? = nil,
        paletteLUT: PaletteColorLUT? = nil,
        pseudoColorPalette: PseudoColorPalette? = nil,
        modalityLUT: ModalityLUT? = nil,
        voiLUT: VOILUT? = nil,
        presentationLUT: PresentationLUT? = nil,
        iccProfile: Data? = nil
    ) {
        self.pixelData = pixelData
        self.frameIndex = frameIndex
        self.window = window
        self.paletteLUT = paletteLUT
        self.pseudoColorPalette = pseudoColorPalette
        self.modalityLUT = modalityLUT
        self.voiLUT = voiLUT
        self.presentationLUT = presentationLUT
        self.iccProfile = iccProfile
    }

    /// Whether this request carries the PS3.4 N.2 chain (``window`` then in modality units).
    public var usesDisplayPipeline: Bool {
        modalityLUT != nil || voiLUT != nil || presentationLUT != nil
    }

    /// The grayscale chain for this monochrome request.
    ///
    /// The VOI is ``voiLUT``, else ``window`` (in modality units when
    /// ``usesDisplayPipeline``, else in stored units with no Modality LUT — the same
    /// thing), else, only when `scanningFrame` is allowed, a window over the frame's
    /// own modality range (`GrayscaleDisplayPipeline.fullRangeWindow`). `nil` when no
    /// VOI can be resolved without a scan — the GPU declines those, as it always has
    /// the auto window.
    public func displayPipeline(scanningFrame: Bool) -> GrayscaleDisplayPipeline? {
        let descriptor = pixelData.descriptor
        guard descriptor.photometricInterpretation.isMonochrome else { return nil }
        let modality = usesDisplayPipeline ? modalityLUT : nil
        let voi: VOILUT
        if let voiLUT {
            voi = voiLUT
        } else if let window {
            voi = VOILUT(window)
        } else {
            guard scanningFrame, let range = pixelData.pixelRange(forFrame: frameIndex) else { return nil }
            voi = GrayscaleDisplayPipeline.fullRangeWindow(modalityLUT: modality, storedRange: range)
        }
        return .standard(for: descriptor.photometricInterpretation,
                         modalityLUT: modality, voiLUT: voi, presentationLUT: presentationLUT)
    }

    /// The raw-cell → grey byte table both backends index for a monochrome frame, or
    /// `nil` when there is no window to resolve without a scan or the cells are wider
    /// than two bytes. Without the chain it is the cached `WindowLUT` of ``window``
    /// (stored units); with it, the chain's own table.
    public var greyTable: WindowLUT? {
        let descriptor = pixelData.descriptor
        guard descriptor.photometricInterpretation.isMonochrome,
              WindowLUT.canTabulate(descriptor) else { return nil }
        if !usesDisplayPipeline {
            guard let window else { return nil }
            return WindowLUT.grayscale(descriptor: descriptor, window: window)
        }
        return displayPipeline(scanningFrame: false)?.table(for: descriptor)
    }

    /// The colour space for this request's colour output: the ICC Profile's when one
    /// is given, parses, is RGB, and the frame's own colours are shown; else `nil`
    /// (Device RGB).
    public var outputColorSpace: CGColorSpace? {
        guard let iccProfile, family != .monochrome, readerPalette == nil,
              let space = CGColorSpace(iccData: iccProfile as CFData),
              space.model == .rgb else { return nil }
        return space
    }

    /// The pseudo-colour palette that actually recolours this frame, if any.
    ///
    /// Monochrome only: for a grey frame the ramp folds into the window as one
    /// raw-sample → RGB table, which is the cheap single-pass path both backends
    /// take. Grey is not a recolouring, so a grayscale ramp resolves to `nil`
    /// and the plain monochrome kernel keeps its cheaper single-channel output.
    ///
    /// A frame that carries its own colours has no raw sample to fold a ramp
    /// into and is handled by ``readerPalette`` instead — see there for why the
    /// reader still gets to apply one.
    public var effectivePseudoColorPalette: PseudoColorPalette? {
        guard pixelData.descriptor.photometricInterpretation.isMonochrome,
              let palette = pseudoColorPalette,
              !palette.isGrayscale else { return nil }
        return palette
    }

    /// The reader's ramp for a frame that already carries colours, if any.
    ///
    /// The colour and palette-colour families arrive at the backend as RGB — the
    /// file's own colours, whether they came from YBR samples or from the file's
    /// palette table. There is no raw sample left to fold a ramp into, so the
    /// ramp is applied to what the frame *shows*: its luminance. That is the
    /// same display choice a ramp always is — the stored pixels are untouched,
    /// and turning the ramp off brings the file's own colours straight back.
    ///
    /// Kept apart from ``effectivePseudoColorPalette`` because the two are
    /// applied at different points and cost different amounts: one is a table
    /// the window is already building, the other is a pass over the finished
    /// frame. Exactly one of them is ever non-nil for a given request.
    public var readerPalette: PseudoColorPalette? {
        guard !pixelData.descriptor.photometricInterpretation.isMonochrome,
              let palette = pseudoColorPalette,
              !palette.isGrayscale else { return nil }
        return palette
    }

    /// Which kernel family this frame needs.
    public var family: FrameRenderFamily {
        let photometric = pixelData.descriptor.photometricInterpretation
        if photometric.isMonochrome { return .monochrome }
        if photometric.isPaletteColor { return .palette }
        return .color
    }
}

/// The three shapes a DICOM frame render takes.
public enum FrameRenderFamily: String, Sendable {
    case monochrome
    case palette
    case color
}

// MARK: - Backend

/// A thing that can render a frame to a `CGImage`.
///
/// `CGImage` is the return type on purpose: roughly a dozen call sites already
/// consume one (viewer, tiles, thumbnails, film composition, export, the CLIs), so
/// a GPU backend that produces one changes no call site at all. Under unified
/// memory it costs nothing either — the image is backed by the very buffer the
/// shader wrote.
public protocol FrameRenderBackend: Sendable {
    /// Which backend this is, for reporting.
    var backend: RenderBackend { get }

    /// Renders one frame, or returns `nil` if this backend cannot.
    ///
    /// `nil` means "not rendered" and is a legitimate answer — an unsupported
    /// pixel layout, a missing palette, a Metal failure. Callers route through
    /// ``FrameRenderService``, which falls back to the CPU rather than showing
    /// the user nothing.
    func renderFrame(_ request: FrameRenderRequest) -> CGImage?
}
#endif
