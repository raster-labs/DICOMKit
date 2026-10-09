// NEMA-verified: 2026a, checked 2026-09-29 — Spatial Transformation per PS3.3 2026a C.10.6 (rotate then horizontal flip; citation corrected from C.10.10), Displayed Area 1-based corners and SCALE TO FIT per Table C.10-4, Presentation LUT IDENTITY/INVERSE per C.11.6 with MONOCHROME1 folded per PS3.4 N.2
// ViewerPresentationStateBridge.swift
// DICOMPrintKit
//
// Turns what a reader was looking at into a presentation state, and back.
//
// The viewer holds its state as window/level plus zoom, pan, rotation, flips
// and inversion. GSPS holds the same facts in the standard's vocabulary: a VOI
// LUT, a Displayed Area, a Spatial Transformation and a Presentation LUT shape.
// This file is the only place that translation lives, so a state saved by the
// viewer and one restored into it cannot drift apart.
//
// Two mismatches between the two vocabularies are worth stating, because they
// decide what a restored view can promise:
//
//   * GSPS rotation is one of 0/90/180/270 and its flip is *horizontal only*
//     (PS3.3 C.10.6: rotate clockwise first, then flip). The viewer allows a
//     free angle and both flips, so a vertical flip is written as a 180°
//     rotation plus a horizontal one, which is the same picture.
//   * The viewer's "inverted" is relative to how the image's own Photometric
//     Interpretation displays it; a presentation state's Presentation LUT is
//     not, because PS3.4 N.2 has the viewer ignore MONOCHROME1/MONOCHROME2 in
//     the referenced image. So for a MONOCHROME1 image the upright view is
//     INVERSE and the inverted one IDENTITY — both directions fold it.
//   * Displayed Area is a rectangle of source pixels, not a zoom factor. It is
//     therefore independent of the viewport it was saved from — the same state
//     restores correctly into a different window size, which is the behaviour
//     that makes a saved state portable.

import Foundation
import DICOMCore
import DICOMKit

/// Translates between a viewer's live display state and a GSPS.
public enum ViewerPresentationStateBridge {

    // MARK: - Capture

    /// The display parameters of a saved view, in the standard's terms.
    ///
    /// Kept separate from ``GrayscalePresentationState`` so a caller can compose
    /// one without yet knowing the UIDs it will be stored under.
    public struct CapturedDisplay: Sendable, Equatable {
        public var voiLUT: VOILUT?
        public var spatialTransformation: SpatialTransformation?
        public var displayedArea: DisplayedArea?
        public var presentationLUT: PresentationLUT

        public init(
            voiLUT: VOILUT? = nil,
            spatialTransformation: SpatialTransformation? = nil,
            displayedArea: DisplayedArea? = nil,
            presentationLUT: PresentationLUT = .identity
        ) {
            self.voiLUT = voiLUT
            self.spatialTransformation = spatialTransformation
            self.displayedArea = displayedArea
            self.presentationLUT = presentationLUT
        }

        /// `DisplayedArea` holds tuples, which blocks synthesized equality.
        public static func == (lhs: CapturedDisplay, rhs: CapturedDisplay) -> Bool {
            lhs.voiLUT == rhs.voiLUT
                && lhs.spatialTransformation == rhs.spatialTransformation
                && lhs.presentationLUT == rhs.presentationLUT
                && lhs.displayedArea?.topLeft.column == rhs.displayedArea?.topLeft.column
                && lhs.displayedArea?.topLeft.row == rhs.displayedArea?.topLeft.row
                && lhs.displayedArea?.bottomRight.column == rhs.displayedArea?.bottomRight.column
                && lhs.displayedArea?.bottomRight.row == rhs.displayedArea?.bottomRight.row
                && lhs.displayedArea?.sizeMode == rhs.displayedArea?.sizeMode
        }
    }

    /// Reads a viewer's state into the display parameters a GSPS carries.
    ///
    /// - Parameters:
    ///   - presentation: Zoom, pan, rotation, flips and inversion as the viewer
    ///     holds them.
    ///   - windowCenter: The window actually applied, if the reader set one.
    ///   - windowWidth: Ditto.
    ///   - windowExplanation: The preset's name, when the window came from one.
    ///   - imageWidth: Source frame size, needed to turn zoom and pan into the
    ///     pixel rectangle Displayed Area is defined as.
    ///   - imageHeight: Ditto.
    ///   - covers: Whether the picture is drawn covering the viewport.
    ///   - photometricInterpretation: The image's Photometric Interpretation
    ///     (0028,0004). MONOCHROME1 turns the viewer's inversion into the
    ///     Presentation LUT that shows the same picture once the viewer ignores
    ///     the photometric (PS3.4 N.2). `nil` keeps the MONOCHROME2 reading.
    public static func capture(
        presentation: ViewerPresentation,
        windowCenter: Double?,
        windowWidth: Double?,
        windowExplanation: String? = nil,
        imageWidth: Int,
        imageHeight: Int,
        covers: Bool = false,
        photometricInterpretation: String? = nil
    ) -> CapturedDisplay {
        var captured = CapturedDisplay()

        if let windowCenter, let windowWidth, windowWidth > 0 {
            captured.voiLUT = .window(
                center: windowCenter, width: windowWidth,
                explanation: windowExplanation, function: .linear)
        }

        captured.spatialTransformation = spatialTransformation(from: presentation)

        // A view that shows the whole image has no Displayed Area worth storing:
        // `visibleRegion` returns nil for it, and the absence restores as "fit
        // the image", which is what the default view does anyway.
        if let region = presentation.visibleRegion(
            imageWidth: imageWidth, imageHeight: imageHeight, covers: covers) {
            captured.displayedArea = DisplayedArea(
                // DICOM pixel coordinates are 1-based (PS3.3 C.10.4); the
                // viewer's regions are 0-based.
                topLeft: (column: region.x + 1, row: region.y + 1),
                bottomRight: (column: region.x + region.width,
                              row: region.y + region.height),
                sizeMode: .scaleToFit)
        }

        // PS3.4 N.2: the image's MONOCHROME1 is ignored under a presentation
        // state, so a MONOCHROME1 image shown the way its photometric says
        // (lowest value white) is an INVERSE state, and inverting it again on
        // screen is IDENTITY.
        let inverse = presentation.invert != isMonochrome1(photometricInterpretation)
        captured.presentationLUT = inverse ? .inverse : .identity

        return captured
    }

    /// Whether a Photometric Interpretation is MONOCHROME1 (lowest value white).
    static func isMonochrome1(_ photometricInterpretation: String?) -> Bool {
        photometricInterpretation?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")).uppercased() == "MONOCHROME1"
    }

    /// Folds the viewer's free rotation and two flips into what GSPS can say.
    ///
    /// A vertical flip has no GSPS attribute of its own; mirroring vertically is
    /// the same picture as mirroring horizontally and turning half a circle, so
    /// that is what gets written.
    static func spatialTransformation(
        from presentation: ViewerPresentation
    ) -> SpatialTransformation? {
        var quarterTurns = presentation.quarterTurns
        var horizontalFlip = presentation.flipHorizontal

        if presentation.flipVertical {
            horizontalFlip.toggle()
            quarterTurns = (quarterTurns + 2) % 4
        }

        // Stated even when it is upright and unmirrored. A saved view is a
        // complete description of how to show the image, and "no Spatial
        // Transformation" is not the same claim as "rotation 0": the first
        // leaves whatever the reader last did to the image in place, so an
        // upright view applied to a turned image left it turned. Writing the
        // identity is what lets a view put an image back the right way up.
        //
        // Rotation 0 with no flip is a well-formed Spatial Transformation:
        // Image Rotation (0070,0042) is US, Type 1, enumerated 0/90/180/270
        // (PS3.3 C.10.6), and 0 is one of its values; Image Horizontal Flip
        // (0070,0041) is Type 1 and "N".
        //
        // The module's usage in the GSPS IOD is Conditional — "required if
        // rotation or flipping are to be applied" — so writing the identity is
        // writing it where it is not strictly required. That is the deliberate
        // trade: both attributes are present and correctly valued, so any
        // reader takes it, and it buys the one thing the condition's literal
        // reading cannot express — a saved view that restores an image the
        // reader has since turned. Omitting it is indistinguishable from "this
        // view says nothing about orientation", which is what left an upright
        // view unable to put a rotated image back.
        //
        // Note 360° cannot be stored: it is not an enumerated value, which is
        // why the angle is normalised to a quarter turn before it gets here.
        return SpatialTransformation(
            rotation: quarterTurns * 90, horizontalFlip: horizontalFlip)
    }

    // MARK: - Restore

    /// What a restored state asks the viewer to do.
    ///
    /// Zoom and pan are returned for a *specific* viewport, because Displayed
    /// Area is a pixel rectangle: the same state yields different zoom values in
    /// different window sizes, and that is the point.
    public struct RestoredDisplay: Sendable, Equatable {
        public var windowCenter: Double?
        public var windowWidth: Double?
        public var zoom: Double
        public var panX: Double
        public var panY: Double
        public var rotationDegrees: Double
        public var flipHorizontal: Bool
        public var invert: Bool

        /// The state's own Modality LUT, as a rescale, when it carries one.
        ///
        /// A presentation state's window is stated in the units its Modality
        /// LUT produces; a state that brings its own rescale means its window
        /// in *those* units, not the image's. Nil means the image's own.
        public var rescaleSlope: Double?
        public var rescaleIntercept: Double?

        public init(
            windowCenter: Double? = nil,
            windowWidth: Double? = nil,
            zoom: Double = 1,
            panX: Double = 0,
            panY: Double = 0,
            rotationDegrees: Double = 0,
            flipHorizontal: Bool = false,
            invert: Bool = false,
            rescaleSlope: Double? = nil,
            rescaleIntercept: Double? = nil
        ) {
            self.windowCenter = windowCenter
            self.windowWidth = windowWidth
            self.zoom = zoom
            self.panX = panX
            self.panY = panY
            self.rotationDegrees = rotationDegrees
            self.flipHorizontal = flipHorizontal
            self.invert = invert
            self.rescaleSlope = rescaleSlope
            self.rescaleIntercept = rescaleIntercept
        }
    }

    /// Turns a parsed presentation state back into viewer settings.
    ///
    /// - Parameters:
    ///   - state: The state to apply.
    ///   - imageWidth: Source frame size.
    ///   - imageHeight: Ditto.
    ///   - viewportWidth: The viewport the state is being restored into — which
    ///     need not be the one it was saved from.
    ///   - viewportHeight: Ditto.
    ///   - covers: Whether the picture is drawn covering the viewport.
    ///   - photometricInterpretation: The image's Photometric Interpretation,
    ///     folded back out of the Presentation LUT exactly as ``capture`` folds
    ///     it in. `nil` keeps the MONOCHROME2 reading.
    public static func restore(
        _ state: GrayscalePresentationState,
        imageWidth: Int,
        imageHeight: Int,
        viewportWidth: Double,
        viewportHeight: Double,
        covers: Bool = false,
        photometricInterpretation: String? = nil
    ) -> RestoredDisplay {
        var restored = RestoredDisplay()

        if case .window(let center, let width, _, _)? = state.voiLUT {
            restored.windowCenter = center
            restored.windowWidth = width
        }

        if case .rescale(let slope, let intercept, _)? = state.modalityLUT, slope != 0 {
            restored.rescaleSlope = slope
            restored.rescaleIntercept = intercept
        }

        if let spatial = state.spatialTransformation {
            restored.rotationDegrees = Double(spatial.rotation)
            restored.flipHorizontal = spatial.horizontalFlip
        }

        // An absent Presentation LUT is IDENTITY (the module is M in GSPS and
        // its shape defaults to no translation); the photometric folds out as
        // it folded in.
        var inverse = false
        if case .inverse? = state.presentationLUT { inverse = true }
        restored.invert = inverse != isMonochrome1(photometricInterpretation)

        if let area = state.displayedArea {
            let (zoom, panX, panY) = zoomAndPan(
                for: area,
                imageWidth: imageWidth, imageHeight: imageHeight,
                viewportWidth: viewportWidth, viewportHeight: viewportHeight,
                rotationDegrees: restored.rotationDegrees,
                covers: covers)
            restored.zoom = zoom
            restored.panX = panX
            restored.panY = panY
        }

        return restored
    }

    /// Inverts ``ViewerPresentation/visibleRegion(imageWidth:imageHeight:covers:)``:
    /// given the rectangle that was visible, work out the zoom and pan that
    /// bring it back into the viewport.
    static func zoomAndPan(
        for area: DisplayedArea,
        imageWidth: Int,
        imageHeight: Int,
        viewportWidth: Double,
        viewportHeight: Double,
        rotationDegrees: Double,
        covers: Bool
    ) -> (zoom: Double, panX: Double, panY: Double) {
        guard imageWidth > 0, imageHeight > 0,
              viewportWidth > 0, viewportHeight > 0,
              area.width > 0, area.height > 0 else { return (1, 0, 0) }

        let baseScale = covers
            ? max(viewportWidth / Double(imageWidth),
                  viewportHeight / Double(imageHeight))
            : min(viewportWidth / Double(imageWidth),
                  viewportHeight / Double(imageHeight))
        guard baseScale > 0 else { return (1, 0, 0) }

        // The region is stated in image pixels; a quarter turn means the
        // viewport's width is spent on the region's height.
        let turns = ViewerPresentation.quarterTurns(fromDegrees: rotationDegrees)
        let quarterTurned = turns % 2 == 1
        let spanAcross = quarterTurned ? Double(area.height) : Double(area.width)
        let spanDown = quarterTurned ? Double(area.width) : Double(area.height)

        // Fit the whole region in: the smaller of the two scales is the one that
        // leaves nothing outside.
        let scale = min(viewportWidth / spanAcross, viewportHeight / spanDown)
        let zoom = scale / baseScale

        // Undo the centring `visibleRegion` applies. Back to 0-based pixels
        // first — Displayed Area is 1-based.
        let centerX = (Double(area.topLeft.column - 1) + Double(area.bottomRight.column)) / 2
        let centerY = (Double(area.topLeft.row - 1) + Double(area.bottomRight.row)) / 2
        let offsetX = (Double(imageWidth) / 2 - centerX) * scale
        let offsetY = (Double(imageHeight) / 2 - centerY) * scale

        // `visibleRegion` reads the pan in view space and un-rotates it, so the
        // inverse has to rotate back into view space.
        let presentation = ViewerPresentation(rotationDegrees: rotationDegrees)
        let (panX, panY) = presentation.imageToView(x: offsetX, y: offsetY)

        return (zoom.isFinite && zoom > 0 ? zoom : 1, panX, panY)
    }
}
