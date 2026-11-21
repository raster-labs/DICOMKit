// NEMA-verified: 2026a, checked 2026-11-16 — Spatial Transformation per PS3.3 2026a C.10.6 (clockwise rotation 0/90/180/270 then horizontal flip), Displayed Area 1-based corners and SCALE TO FIT per Table C.10-4, Presentation LUT IDENTITY/INVERSE per C.11.6 with MONOCHROME1 folded per PS3.4 N.2, SOP Classes 11.1/11.2/11.3 per PS3.3 A.33.1–A.33.3
//
// PresentationStateViewportBridge.swift
// DICOMKit
//
// Common viewport-to-PresentationState capture and restore bridge for
// GSPS, CSPS, and Pseudo-CSPS usable by any application importing DICOMKit.
//

import Foundation
import DICOMCore

/// Live viewport parameters captured from an image viewer for encoding into a
/// DICOM Presentation State (GSPS, CSPS, or Pseudo-CSPS).
public struct PresentationStateViewportState: Sendable, Equatable {
    /// Window center in Modality LUT output units (nil for color images).
    public var windowCenter: Double?

    /// Window width in Modality LUT output units (nil for color images).
    public var windowWidth: Double?

    /// Optional window/level explanation label.
    public var windowExplanation: String?

    /// VOI LUT function (`LINEAR`, `LINEAR_EXACT`, or `SIGMOID`).
    public var voiLUTFunction: VOILUTFunction

    /// Modality LUT rescale slope (default `1.0`).
    public var rescaleSlope: Double

    /// Modality LUT rescale intercept (default `0.0`).
    public var rescaleIntercept: Double

    /// Modality LUT rescale type (e.g. `"HU"`, `"US"`, `"OD"`).
    public var rescaleType: String?

    /// Zoom factor (`1.0` = fit to viewport).
    public var zoom: Double

    /// Horizontal pan offset in normalized viewport coordinates.
    public var panX: Double

    /// Vertical pan offset in normalized viewport coordinates.
    public var panY: Double

    /// Explicit 0-based visible pixel region `(x, y, width, height)` if known.
    /// When nil, computed automatically from `zoom`, `panX`, `panY`, and image size.
    public var visiblePixelRegion: (x: Int, y: Int, width: Int, height: Int)?

    /// Rotation in degrees (normalized to 0, 90, 180, or 270 clockwise).
    public var rotationDegrees: Double

    /// Whether the image is flipped horizontally.
    public var flipHorizontal: Bool

    /// Whether the image is flipped vertically (encoded as 180° rotation + horizontal flip per PS3.3 C.10.6).
    public var flipVertical: Bool

    /// Whether the viewer display is inverted relative to the image's natural polarity.
    public var invert: Bool

    /// Optional pseudo-color palette applied to a monochrome image (triggers Pseudo-CSPS when non-grayscale).
    public var palette: PseudoColorPalette?

    /// Optional custom 256/16-bit Palette Color LUT (triggers Pseudo-CSPS for monochrome images).
    public var customPaletteColorLUT: PaletteColorLUT?

    /// Optional ICC profile for color management (CSPS / Pseudo-CSPS).
    public var iccProfile: ICCProfile?

    /// Display shutters applied to the viewport.
    public var shutters: [DisplayShutter]

    /// High-level annotations drawn on the viewport.
    public var annotations: [DICOMAnnotation]

    public init(
        windowCenter: Double? = nil,
        windowWidth: Double? = nil,
        windowExplanation: String? = nil,
        voiLUTFunction: VOILUTFunction = .linear,
        rescaleSlope: Double = 1.0,
        rescaleIntercept: Double = 0.0,
        rescaleType: String? = nil,
        zoom: Double = 1.0,
        panX: Double = 0.0,
        panY: Double = 0.0,
        visiblePixelRegion: (x: Int, y: Int, width: Int, height: Int)? = nil,
        rotationDegrees: Double = 0.0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        invert: Bool = false,
        palette: PseudoColorPalette? = nil,
        customPaletteColorLUT: PaletteColorLUT? = nil,
        iccProfile: ICCProfile? = nil,
        shutters: [DisplayShutter] = [],
        annotations: [DICOMAnnotation] = []
    ) {
        self.windowCenter = windowCenter
        self.windowWidth = windowWidth
        self.windowExplanation = windowExplanation
        self.voiLUTFunction = voiLUTFunction
        self.rescaleSlope = rescaleSlope
        self.rescaleIntercept = rescaleIntercept
        self.rescaleType = rescaleType
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.visiblePixelRegion = visiblePixelRegion
        self.rotationDegrees = rotationDegrees
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.invert = invert
        self.palette = palette
        self.customPaletteColorLUT = customPaletteColorLUT
        self.iccProfile = iccProfile
        self.shutters = shutters
        self.annotations = annotations
    }

    public static func == (lhs: PresentationStateViewportState, rhs: PresentationStateViewportState) -> Bool {
        lhs.windowCenter == rhs.windowCenter &&
        lhs.windowWidth == rhs.windowWidth &&
        lhs.windowExplanation == rhs.windowExplanation &&
        lhs.voiLUTFunction == rhs.voiLUTFunction &&
        lhs.rescaleSlope == rhs.rescaleSlope &&
        lhs.rescaleIntercept == rhs.rescaleIntercept &&
        lhs.rescaleType == rhs.rescaleType &&
        lhs.zoom == rhs.zoom &&
        lhs.panX == rhs.panX &&
        lhs.panY == rhs.panY &&
        lhs.visiblePixelRegion?.x == rhs.visiblePixelRegion?.x &&
        lhs.visiblePixelRegion?.y == rhs.visiblePixelRegion?.y &&
        lhs.visiblePixelRegion?.width == rhs.visiblePixelRegion?.width &&
        lhs.visiblePixelRegion?.height == rhs.visiblePixelRegion?.height &&
        lhs.rotationDegrees == rhs.rotationDegrees &&
        lhs.flipHorizontal == rhs.flipHorizontal &&
        lhs.flipVertical == rhs.flipVertical &&
        lhs.invert == rhs.invert &&
        lhs.palette == rhs.palette &&
        lhs.customPaletteColorLUT == rhs.customPaletteColorLUT &&
        lhs.iccProfile == rhs.iccProfile &&
        lhs.shutters == rhs.shutters &&
        lhs.annotations == rhs.annotations
    }
}

/// Restored viewport display parameters decoded from a `PresentationStateDocument`
/// (GSPS, CSPS, Pseudo-CSPS, or Blending).
public struct RestoredPresentationStateView: Sendable, Equatable {
    /// Presentation State kind (`.grayscale`, `.color`, `.pseudoColor`, or `.blending`).
    public var kind: PresentationStateKind

    /// Effective window center for the target image/frame.
    public var windowCenter: Double?

    /// Effective window width for the target image/frame.
    public var windowWidth: Double?

    /// Effective VOI LUT function.
    public var voiLUTFunction: VOILUTFunction?

    /// Effective Modality LUT rescale slope (nil means use the image's own).
    public var rescaleSlope: Double?

    /// Effective Modality LUT rescale intercept (nil means use the image's own).
    public var rescaleIntercept: Double?

    /// Effective Modality LUT rescale type.
    public var rescaleType: String?

    /// Restored zoom factor for the target viewport.
    public var zoom: Double

    /// Restored horizontal pan offset for the target viewport.
    public var panX: Double

    /// Restored vertical pan offset for the target viewport.
    public var panY: Double

    /// Effective 1-based Displayed Area from the Presentation State.
    public var displayedArea: DisplayedArea?

    /// Clockwise rotation in degrees (0, 90, 180, or 270).
    public var rotationDegrees: Double

    /// Horizontal flip applied after rotation.
    public var flipHorizontal: Bool

    /// Whether the display is inverted relative to the image's natural polarity.
    public var invert: Bool

    /// Restored well-known or matched pseudo-color palette (for Pseudo-CSPS).
    public var palette: PseudoColorPalette?

    /// Restored raw `PaletteColorLUT` (for Pseudo-CSPS).
    public var paletteColorLUT: PaletteColorLUT?

    /// Restored `ICCProfile` (for CSPS and Pseudo-CSPS).
    public var iccProfile: ICCProfile?

    /// Display shutters carried by the Presentation State.
    public var shutters: [DisplayShutter]

    /// Scoped annotations applicable to the requested image and frame.
    public var annotations: [DICOMAnnotation]

    public init(
        kind: PresentationStateKind,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil,
        voiLUTFunction: VOILUTFunction? = nil,
        rescaleSlope: Double? = nil,
        rescaleIntercept: Double? = nil,
        rescaleType: String? = nil,
        zoom: Double = 1.0,
        panX: Double = 0.0,
        panY: Double = 0.0,
        displayedArea: DisplayedArea? = nil,
        rotationDegrees: Double = 0.0,
        flipHorizontal: Bool = false,
        invert: Bool = false,
        palette: PseudoColorPalette? = nil,
        paletteColorLUT: PaletteColorLUT? = nil,
        iccProfile: ICCProfile? = nil,
        shutters: [DisplayShutter] = [],
        annotations: [DICOMAnnotation] = []
    ) {
        self.kind = kind
        self.windowCenter = windowCenter
        self.windowWidth = windowWidth
        self.voiLUTFunction = voiLUTFunction
        self.rescaleSlope = rescaleSlope
        self.rescaleIntercept = rescaleIntercept
        self.rescaleType = rescaleType
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.displayedArea = displayedArea
        self.rotationDegrees = rotationDegrees
        self.flipHorizontal = flipHorizontal
        self.invert = invert
        self.palette = palette
        self.paletteColorLUT = paletteColorLUT
        self.iccProfile = iccProfile
        self.shutters = shutters
        self.annotations = annotations
    }

    public static func == (lhs: RestoredPresentationStateView, rhs: RestoredPresentationStateView) -> Bool {
        lhs.kind == rhs.kind &&
        lhs.windowCenter == rhs.windowCenter &&
        lhs.windowWidth == rhs.windowWidth &&
        lhs.voiLUTFunction == rhs.voiLUTFunction &&
        lhs.rescaleSlope == rhs.rescaleSlope &&
        lhs.rescaleIntercept == rhs.rescaleIntercept &&
        lhs.rescaleType == rhs.rescaleType &&
        lhs.zoom == rhs.zoom &&
        lhs.panX == rhs.panX &&
        lhs.panY == rhs.panY &&
        lhs.displayedArea?.topLeft.column == rhs.displayedArea?.topLeft.column &&
        lhs.displayedArea?.topLeft.row == rhs.displayedArea?.topLeft.row &&
        lhs.displayedArea?.bottomRight.column == rhs.displayedArea?.bottomRight.column &&
        lhs.displayedArea?.bottomRight.row == rhs.displayedArea?.bottomRight.row &&
        lhs.rotationDegrees == rhs.rotationDegrees &&
        lhs.flipHorizontal == rhs.flipHorizontal &&
        lhs.invert == rhs.invert &&
        lhs.palette == rhs.palette &&
        lhs.paletteColorLUT == rhs.paletteColorLUT &&
        lhs.iccProfile == rhs.iccProfile &&
        lhs.shutters == rhs.shutters &&
        lhs.annotations == rhs.annotations
    }
}

/// Common bridge translating between an application's viewport state and a
/// DICOM Presentation State (`PresentationStateDocument` — GSPS, CSPS, or Pseudo-CSPS).
public enum PresentationStateViewportBridge {

    // MARK: - Capture Viewport -> PresentationStateDocument

    /// Captures live viewport state for a single image (or multi-frame image) into a
    /// standard-compliant `PresentationStateDocument` (GSPS, CSPS, or Pseudo-CSPS).
    public static func capture(
        viewport: PresentationStateViewportState,
        seriesInstanceUID: String,
        sopClassUID: String,
        sopInstanceUID: String,
        photometricInterpretation: String? = nil,
        imageWidth: Int,
        imageHeight: Int,
        presentationLabel: String = "SAVED_VIEW",
        presentationDescription: String? = nil,
        creatorName: DICOMPersonName? = nil
    ) -> PresentationStateDocument {
        let hasPseudoColor = (viewport.palette != nil && viewport.palette?.isGrayscale == false)
            || viewport.customPaletteColorLUT != nil
        let kind = PresentationStateManager.recommendedKind(
            forPhotometricInterpretation: photometricInterpretation,
            hasPseudoColorPalette: hasPseudoColor
        )

        let voiLUT: VOILUT? = {
            guard kind != .color,
                  let center = viewport.windowCenter,
                  let width = viewport.windowWidth,
                  width > 0 else { return nil }
            return .window(
                center: center,
                width: width,
                explanation: viewport.windowExplanation,
                function: viewport.voiLUTFunction
            )
        }()

        let modalityLUT: ModalityLUT? = {
            guard kind != .color,
                  viewport.rescaleSlope != 0,
                  viewport.rescaleSlope != 1.0 || viewport.rescaleIntercept != 0.0 else {
                return nil
            }
            return .rescale(
                slope: viewport.rescaleSlope,
                intercept: viewport.rescaleIntercept,
                type: viewport.rescaleType
            )
        }()

        let spatial = encodeSpatialTransformation(
            rotationDegrees: viewport.rotationDegrees,
            flipHorizontal: viewport.flipHorizontal,
            flipVertical: viewport.flipVertical
        )

        let displayedArea = encodeDisplayedArea(
            viewport: viewport,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )

        // PS3.4 N.2: MONOCHROME1 polarity is folded into the Presentation LUT
        let inverse = viewport.invert != isMonochrome1(photometricInterpretation)
        let presentationLUT: PresentationLUT = inverse ? .inverse : .identity

        return PresentationStateManager.create(
            forImage: sopInstanceUID,
            sopClassUID: sopClassUID,
            seriesInstanceUID: seriesInstanceUID,
            photometricInterpretation: photometricInterpretation,
            presentationLabel: presentationLabel,
            presentationDescription: presentationDescription,
            creatorName: creatorName,
            voiLUT: voiLUT,
            modalityLUT: modalityLUT,
            presentationLUT: presentationLUT,
            palette: viewport.palette,
            customPaletteColorLUT: viewport.customPaletteColorLUT,
            iccProfile: viewport.iccProfile,
            spatialTransformation: spatial,
            displayedArea: displayedArea,
            shutters: viewport.shutters,
            annotations: viewport.annotations
        )
    }

    // MARK: - Restore PresentationStateDocument -> Viewport

    /// Restores a `PresentationStateDocument` (GSPS, CSPS, Pseudo-CSPS, or Blending) into
    /// viewport parameters for a target image, frame, and viewport size.
    public static func restore(
        _ document: PresentationStateDocument,
        forImage sopInstanceUID: String? = nil,
        frameNumber: Int? = nil,
        imageWidth: Int,
        imageHeight: Int,
        viewportWidth: Double = 0,
        viewportHeight: Double = 0,
        photometricInterpretation: String? = nil
    ) -> RestoredPresentationStateView {
        var view = RestoredPresentationStateView(kind: document.kind)

        // 1. Effective VOI LUT (per-frame -> per-image -> global)
        if let voi = document.effectiveVOILUT(forImage: sopInstanceUID, frameNumber: frameNumber),
           case .window(let center, let width, _, let function) = voi {
            view.windowCenter = center
            view.windowWidth = width
            view.voiLUTFunction = function
        }

        // 2. Modality LUT
        if case .rescale(let slope, let intercept, let type)? = document.modalityLUT, slope != 0 {
            view.rescaleSlope = slope
            view.rescaleIntercept = intercept
            view.rescaleType = type
        }

        // 3. Spatial Transformation
        if let spatial = document.spatialTransformation {
            view.rotationDegrees = Double(spatial.rotation)
            view.flipHorizontal = spatial.horizontalFlip
        }

        // 4. Presentation LUT / Polarity & Palette
        var stateInverse = false
        switch document {
        case .grayscale(let gsps):
            if case .inverse? = gsps.presentationLUT {
                stateInverse = true
            }
        case .pseudoColor(let pcsps):
            view.palette = pcsps.palette
            view.paletteColorLUT = pcsps.paletteColorLUT
            view.iccProfile = pcsps.iccProfile
            if let match = PseudoColorPalette.matching(pcsps.paletteColorLUT) {
                view.palette = view.palette ?? match.palette
                stateInverse = match.inverted
            }
        case .color(let csps):
            view.iccProfile = csps.iccProfile
        case .blending:
            break
        }
        view.invert = stateInverse != isMonochrome1(photometricInterpretation)

        // 5. Effective Displayed Area -> Zoom & Pan
        if let area = document.effectiveDisplayedArea(forImage: sopInstanceUID, frameNumber: frameNumber) {
            view.displayedArea = area
            if imageWidth > 0, imageHeight > 0 {
                let (zoom, panX, panY) = decodeZoomAndPan(
                    from: area,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight,
                    viewportWidth: viewportWidth,
                    viewportHeight: viewportHeight
                )
                view.zoom = zoom
                view.panX = panX
                view.panY = panY
            }
        }

        // 6. Shutters & Scoped Annotations
        view.shutters = document.shutters
        view.annotations = document.annotations(forImage: sopInstanceUID, frameNumber: frameNumber)

        return view
    }

    // MARK: - Helpers

    /// Returns true if `photometricInterpretation` is `MONOCHROME1`.
    public static func isMonochrome1(_ photometricInterpretation: String?) -> Bool {
        photometricInterpretation?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
            .uppercased() == "MONOCHROME1"
    }

    /// Encodes rotation and horizontal/vertical flip into a PS3.3 C.10.6 `SpatialTransformation`.
    public static func encodeSpatialTransformation(
        rotationDegrees: Double,
        flipHorizontal: Bool,
        flipVertical: Bool
    ) -> SpatialTransformation {
        let normalizedDegrees = ((Int(rotationDegrees.rounded()) % 360) + 360) % 360
        var quarterTurns = (normalizedDegrees / 90) % 4
        var hFlip = flipHorizontal
        if flipVertical {
            hFlip.toggle()
            quarterTurns = (quarterTurns + 2) % 4
        }
        return SpatialTransformation(rotation: quarterTurns * 90, horizontalFlip: hFlip)
    }

    /// Encodes zoom/pan or an explicit pixel region into a 1-based PS3.3 C.10.4 `DisplayedArea`.
    public static func encodeDisplayedArea(
        viewport: PresentationStateViewportState,
        imageWidth: Int,
        imageHeight: Int
    ) -> DisplayedArea? {
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        if let region = viewport.visiblePixelRegion {
            let left = max(1, min(imageWidth, region.x + 1))
            let top = max(1, min(imageHeight, region.y + 1))
            let right = max(left, min(imageWidth, region.x + region.width))
            let bottom = max(top, min(imageHeight, region.y + region.height))
            return DisplayedArea(
                topLeft: (column: left, row: top),
                bottomRight: (column: right, row: bottom),
                sizeMode: .scaleToFit
            )
        }
        let zoom = max(1.0, viewport.zoom)
        if zoom <= 1.0001 && abs(viewport.panX) < 0.0001 && abs(viewport.panY) < 0.0001 {
            return DisplayedArea(
                topLeft: (column: 1, row: 1),
                bottomRight: (column: imageWidth, row: imageHeight),
                sizeMode: .scaleToFit
            )
        }
        let visibleW = max(1.0, Double(imageWidth) / zoom)
        let visibleH = max(1.0, Double(imageHeight) / zoom)
        let centerX = Double(imageWidth) * 0.5 - viewport.panX * Double(imageWidth)
        let centerY = Double(imageHeight) * 0.5 - viewport.panY * Double(imageHeight)
        let left = max(1, min(imageWidth, Int((centerX - visibleW * 0.5).rounded()) + 1))
        let top = max(1, min(imageHeight, Int((centerY - visibleH * 0.5).rounded()) + 1))
        let right = max(left, min(imageWidth, Int((centerX + visibleW * 0.5).rounded())))
        let bottom = max(top, min(imageHeight, Int((centerY + visibleH * 0.5).rounded())))
        return DisplayedArea(
            topLeft: (column: left, row: top),
            bottomRight: (column: right, row: bottom),
            sizeMode: .scaleToFit
        )
    }

    /// Computes normalized zoom and pan from a 1-based `DisplayedArea`.
    public static func decodeZoomAndPan(
        from area: DisplayedArea,
        imageWidth: Int,
        imageHeight: Int,
        viewportWidth: Double = 0,
        viewportHeight: Double = 0
    ) -> (zoom: Double, panX: Double, panY: Double) {
        guard imageWidth > 0, imageHeight > 0 else { return (1.0, 0.0, 0.0) }
        let areaW = Double(max(1, area.bottomRight.column - area.topLeft.column + 1))
        let areaH = Double(max(1, area.bottomRight.row - area.topLeft.row + 1))
        let zoomX = Double(imageWidth) / areaW
        let zoomY = Double(imageHeight) / areaH
        let zoom = max(1.0, min(zoomX, zoomY))
        let areaCenterX = Double(area.topLeft.column - 1) + areaW * 0.5
        let areaCenterY = Double(area.topLeft.row - 1) + areaH * 0.5
        let panX = (Double(imageWidth) * 0.5 - areaCenterX) / Double(imageWidth)
        let panY = (Double(imageHeight) * 0.5 - areaCenterY) / Double(imageHeight)
        return (zoom, panX, panY)
    }
}
