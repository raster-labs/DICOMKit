// PresentationStateService.swift
// DICOMStudio
//
// DICOM Studio — Service for loading and applying DICOM Presentation States
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: a GSPS Softcopy VOI LUT replaces the image's window (PS3.4 2026a N.2.1.3), rotation/flip come from PresentationStateHelpers (C.10.6), the default layer name LAYER0 is a free Graphic Layer (0070,0002) value

import Foundation
import DICOMCore
import DICOMKit

/// Service for managing DICOM Presentation States.
///
/// Handles loading, applying, and creating GSPS, Color, Pseudo-Color,
/// and Blending presentation states.
public final class PresentationStateService: Sendable {

    public init() {}

    // MARK: - GSPS Application

    /// Applies a GSPS to generate transformed window/level parameters.
    ///
    /// - Parameters:
    ///   - gsps: The GSPS model.
    ///   - currentCenter: Current window center.
    ///   - currentWidth: Current window width.
    /// - Returns: Tuple of (windowCenter, windowWidth) after GSPS override.
    public func applyGSPSWindowLevel(
        gsps: GSPSModel,
        currentCenter: Double,
        currentWidth: Double
    ) -> (center: Double, width: Double) {
        if let voiLUT = gsps.voiLUT {
            return (voiLUT.windowCenter, voiLUT.windowWidth)
        }
        return (currentCenter, currentWidth)
    }

    /// Checks if a GSPS references a specific SOP Instance UID.
    ///
    /// - Parameters:
    ///   - gsps: The GSPS model.
    ///   - sopInstanceUID: SOP Instance UID to check.
    /// - Returns: True if the GSPS references the given instance.
    public func gspsReferences(gsps: GSPSModel, sopInstanceUID: String) -> Bool {
        gsps.referencedImages.contains { $0.sopInstanceUID == sopInstanceUID }
    }

    /// Filters GSPS models that reference a specific image.
    ///
    /// - Parameters:
    ///   - allStates: All available GSPS models.
    ///   - sopInstanceUID: SOP Instance UID to filter by.
    /// - Returns: GSPS models that reference the given image.
    public func gspsForImage(
        allStates: [GSPSModel],
        sopInstanceUID: String
    ) -> [GSPSModel] {
        allStates.filter { gspsReferences(gsps: $0, sopInstanceUID: sopInstanceUID) }
    }

    // MARK: - Presentation State Creation

    /// Creates a new GSPS model from current viewer state.
    ///
    /// - Parameters:
    ///   - sopInstanceUID: SOP Instance UID of the referenced image.
    ///   - sopClassUID: SOP Class UID of the referenced image.
    ///   - windowCenter: Current window center.
    ///   - windowWidth: Current window width.
    ///   - annotations: Graphic annotations.
    ///   - textAnnotations: Text annotations.
    ///   - label: Presentation state label.
    /// - Returns: A new GSPS model.
    public func createGSPS(
        referencingSOP sopInstanceUID: String,
        sopClassUID: String,
        windowCenter: Double,
        windowWidth: Double,
        annotations: [GraphicAnnotation] = [],
        textAnnotations: [TextAnnotation] = [],
        label: String = "User Created"
    ) -> GSPSModel {
        GSPSModel(
            referencedImages: [
                ReferencedImage(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID)
            ],
            voiLUT: VOILUTTransform(windowCenter: windowCenter, windowWidth: windowWidth),
            graphicAnnotations: annotations,
            textAnnotations: textAnnotations,
            graphicLayers: [GraphicLayer(name: "LAYER0", order: 0)],
            label: label,
            creationDate: Date()
        )
    }

    // MARK: - Spatial Transformation

    /// Resolves the effective rotation angle for a GSPS.
    ///
    /// - Parameter gsps: The GSPS model.
    /// - Returns: Rotation angle in degrees.
    public func effectiveRotation(gsps: GSPSModel) -> Double {
        PresentationStateHelpers.rotationAngle(for: gsps.spatialTransformation)
    }

    /// Resolves whether the GSPS requires a horizontal flip.
    ///
    /// - Parameter gsps: The GSPS model.
    /// - Returns: True if flipped horizontally.
    public func effectiveFlipH(gsps: GSPSModel) -> Bool {
        PresentationStateHelpers.isFlippedHorizontally(gsps.spatialTransformation)
    }

    /// Resolves whether the GSPS requires a vertical flip.
    ///
    /// - Parameter gsps: The GSPS model.
    /// - Returns: True if flipped vertically.
    public func effectiveFlipV(gsps: GSPSModel) -> Bool {
        PresentationStateHelpers.isFlippedVertically(gsps.spatialTransformation)
    }

    // MARK: - Pseudo-Color

    /// Generates a color lookup table for a pseudo-color presentation state.
    ///
    /// - Parameter state: The pseudo-color presentation state.
    /// - Returns: Array of 256 color entries.
    public func colorLUT(for state: PseudoColorPresentationStateModel) -> [ColorEntry] {
        if let customLUT = state.customLUT, !customLUT.isEmpty {
            return customLUT
        }
        return ColorLUTHelpers.palette(for: state.palette)
    }

    // MARK: - Blending

    /// Computes blending parameters for a blending presentation state.
    ///
    /// - Parameter state: The blending presentation state.
    /// - Returns: Tuple of (opacity, overlayPalette) for rendering.
    public func blendingParameters(
        for state: BlendingPresentationStateModel
    ) -> (opacity: Double, palette: [ColorEntry]) {
        let palette: [ColorEntry]
        if let overlayPalette = state.overlayPalette {
            palette = ColorLUTHelpers.palette(for: overlayPalette)
        } else {
            palette = ColorLUTHelpers.grayscalePalette()
        }
        return (state.blendingOpacity, palette)
    }

    // MARK: - DICOMKit Common Presentation State API Integration

    /// Converts a `GSPSModel` into a `DICOMKit.PresentationStateDocument` (`.grayscale`).
    public func toDocument(
        from gsps: GSPSModel,
        seriesInstanceUID: String
    ) -> PresentationStateDocument {
        let sopInstanceUID = gsps.sopInstanceUID.isEmpty
            ? UIDGenerator.generateSOPInstanceUID().value
            : gsps.sopInstanceUID
        let refImages = gsps.referencedImages.map {
            DICOMKit.ReferencedImage(
                sopClassUID: $0.sopClassUID,
                sopInstanceUID: $0.sopInstanceUID,
                referencedFrameNumbers: $0.frameNumbers.isEmpty ? nil : $0.frameNumbers
            )
        }
        let voi: VOILUT? = gsps.voiLUT.map {
            let fn = VOILUTFunction(rawValue: $0.function) ?? .linear
            return .window(center: $0.windowCenter, width: $0.windowWidth, explanation: nil, function: fn)
        }
        let mod: ModalityLUT? = gsps.modalityLUT.map {
            .rescale(slope: $0.rescaleSlope, intercept: $0.rescaleIntercept, type: $0.rescaleType)
        }
        let pLUT: PresentationLUT = gsps.presentationLUTShape == .inverse ? .inverse : .identity
        let spatial = PresentationStateViewportBridge.encodeSpatialTransformation(
            rotationDegrees: effectiveRotation(gsps: gsps),
            flipHorizontal: effectiveFlipH(gsps: gsps),
            flipVertical: effectiveFlipV(gsps: gsps)
        )
        let area: DICOMKit.DisplayedArea? = gsps.displayedArea.map {
            let mode = PresentationSizeMode(rawValue: $0.presentationSizeMode) ?? .scaleToFit
            return DICOMKit.DisplayedArea(
                topLeft: (column: max(1, Int($0.topLeft.x.rounded())), row: max(1, Int($0.topLeft.y.rounded()))),
                bottomRight: (column: max(1, Int($0.bottomRight.x.rounded())), row: max(1, Int($0.bottomRight.y.rounded()))),
                sizeMode: mode,
                pixelSpacing: $0.pixelSpacing.map { (row: $0, column: $0) }
            )
        }
        let layers = gsps.graphicLayers.map {
            DICOMKit.GraphicLayer(
                name: $0.name,
                order: $0.order,
                description: $0.description,
                recommendedGrayscaleValue: $0.grayscaleValue
            )
        }
        let annotations = buildDICOMKitGraphicAnnotations(
            shapes: gsps.graphicAnnotations,
            texts: gsps.textAnnotations,
            referencedImages: refImages
        )
        return .grayscale(GrayscalePresentationState(
            sopInstanceUID: sopInstanceUID,
            presentationLabel: gsps.label,
            presentationDescription: gsps.stateDescription,
            referencedSeries: [ReferencedSeries(seriesInstanceUID: seriesInstanceUID, referencedImages: refImages)],
            modalityLUT: mod,
            voiLUT: voi,
            presentationLUT: pLUT,
            spatialTransformation: spatial,
            displayedArea: area,
            graphicLayers: layers.isEmpty ? [DICOMKit.GraphicLayer(name: "LAYER0", order: 0)] : layers,
            graphicAnnotations: annotations
        ))
    }

    /// Converts a `ColorPresentationStateModel` into a `DICOMKit.PresentationStateDocument` (`.color`).
    public func toDocument(
        from csps: ColorPresentationStateModel,
        seriesInstanceUID: String
    ) -> PresentationStateDocument {
        let sopInstanceUID = csps.sopInstanceUID.isEmpty
            ? UIDGenerator.generateSOPInstanceUID().value
            : csps.sopInstanceUID
        let refImages = csps.referencedImages.map {
            DICOMKit.ReferencedImage(
                sopClassUID: $0.sopClassUID,
                sopInstanceUID: $0.sopInstanceUID,
                referencedFrameNumbers: $0.frameNumbers.isEmpty ? nil : $0.frameNumbers
            )
        }
        let spatial = PresentationStateViewportBridge.encodeSpatialTransformation(
            rotationDegrees: PresentationStateHelpers.rotationAngle(for: csps.spatialTransformation),
            flipHorizontal: PresentationStateHelpers.isFlippedHorizontally(csps.spatialTransformation),
            flipVertical: PresentationStateHelpers.isFlippedVertically(csps.spatialTransformation)
        )
        let area: DICOMKit.DisplayedArea? = csps.displayedArea.map {
            let mode = PresentationSizeMode(rawValue: $0.presentationSizeMode) ?? .scaleToFit
            return DICOMKit.DisplayedArea(
                topLeft: (column: max(1, Int($0.topLeft.x.rounded())), row: max(1, Int($0.topLeft.y.rounded()))),
                bottomRight: (column: max(1, Int($0.bottomRight.x.rounded())), row: max(1, Int($0.bottomRight.y.rounded()))),
                sizeMode: mode,
                pixelSpacing: $0.pixelSpacing.map { (row: $0, column: $0) }
            )
        }
        let layers = csps.graphicLayers.map {
            DICOMKit.GraphicLayer(
                name: $0.name,
                order: $0.order,
                description: $0.description,
                recommendedGrayscaleValue: $0.grayscaleValue
            )
        }
        let annotations = buildDICOMKitGraphicAnnotations(
            shapes: csps.graphicAnnotations,
            texts: csps.textAnnotations,
            referencedImages: refImages
        )
        let icc = csps.iccProfile.map { ICCProfile(profileData: $0, colorSpace: .sRGB) }
        return .color(ColorPresentationState(
            sopInstanceUID: sopInstanceUID,
            presentationLabel: csps.label,
            referencedSeries: [ReferencedSeries(seriesInstanceUID: seriesInstanceUID, referencedImages: refImages)],
            iccProfile: icc,
            spatialTransformation: spatial,
            displayedArea: area,
            graphicLayers: layers.isEmpty ? [DICOMKit.GraphicLayer(name: "LAYER0", order: 0)] : layers,
            graphicAnnotations: annotations
        ))
    }

    /// Converts a `PseudoColorPresentationStateModel` into a `DICOMKit.PresentationStateDocument` (`.pseudoColor`).
    public func toDocument(
        from pcsps: PseudoColorPresentationStateModel,
        seriesInstanceUID: String
    ) -> PresentationStateDocument {
        let sopInstanceUID = pcsps.sopInstanceUID.isEmpty
            ? UIDGenerator.generateSOPInstanceUID().value
            : pcsps.sopInstanceUID
        let refImages = pcsps.referencedImages.map {
            DICOMKit.ReferencedImage(
                sopClassUID: $0.sopClassUID,
                sopInstanceUID: $0.sopInstanceUID,
                referencedFrameNumbers: $0.frameNumbers.isEmpty ? nil : $0.frameNumbers
            )
        }
        let voi: VOILUT? = pcsps.voiLUT.map {
            let fn = VOILUTFunction(rawValue: $0.function) ?? .linear
            return .window(center: $0.windowCenter, width: $0.windowWidth, explanation: nil, function: fn)
        }
        let mappedPalette: PseudoColorPalette = {
            switch pcsps.palette {
            case .hotIron: return .hotIron
            case .rainbow: return .rainbow
            case .hotMetal: return .hotMetalBlue
            case .pet: return .pet
            case .petTwentyStep: return .petTwentyStep
            case .grayscale: return .grayscale
            case .custom: return .hotIron
            }
        }()
        let annotations = buildDICOMKitGraphicAnnotations(
            shapes: pcsps.graphicAnnotations,
            texts: pcsps.textAnnotations,
            referencedImages: refImages
        )
        return .pseudoColor(PseudoColorPresentationState(
            sopInstanceUID: sopInstanceUID,
            presentationLabel: pcsps.label,
            referencedSeries: [ReferencedSeries(seriesInstanceUID: seriesInstanceUID, referencedImages: refImages)],
            voiLUT: voi,
            palette: mappedPalette,
            graphicLayers: annotations.isEmpty ? [] : [DICOMKit.GraphicLayer(name: "LAYER0", order: 0)],
            graphicAnnotations: annotations
        ))
    }

    /// Converts a `BlendingPresentationStateModel` into a `DICOMKit.PresentationStateDocument` (`.blending`).
    public func toDocument(
        from blending: BlendingPresentationStateModel,
        underlaySeriesInstanceUID: String,
        overlaySeriesInstanceUID: String
    ) -> PresentationStateDocument {
        let sopInstanceUID = blending.sopInstanceUID.isEmpty
            ? UIDGenerator.generateSOPInstanceUID().value
            : blending.sopInstanceUID
        let uImages = blending.underlayImages.map {
            DICOMKit.ReferencedImage(
                sopClassUID: $0.sopClassUID,
                sopInstanceUID: $0.sopInstanceUID,
                referencedFrameNumbers: $0.frameNumbers.isEmpty ? nil : $0.frameNumbers
            )
        }
        let oImages = blending.overlayImages.map {
            DICOMKit.ReferencedImage(
                sopClassUID: $0.sopClassUID,
                sopInstanceUID: $0.sopInstanceUID,
                referencedFrameNumbers: $0.frameNumbers.isEmpty ? nil : $0.frameNumbers
            )
        }
        let uVOI: VOILUT? = blending.underlayVOILUT.map {
            .window(center: $0.windowCenter, width: $0.windowWidth, explanation: nil, function: VOILUTFunction(rawValue: $0.function) ?? .linear)
        }
        let oVOI: VOILUT? = blending.overlayVOILUT.map {
            .window(center: $0.windowCenter, width: $0.windowWidth, explanation: nil, function: VOILUTFunction(rawValue: $0.function) ?? .linear)
        }
        let uSeries = [ReferencedSeries(seriesInstanceUID: underlaySeriesInstanceUID, referencedImages: uImages)]
        let oSeries = [ReferencedSeries(seriesInstanceUID: overlaySeriesInstanceUID, referencedImages: oImages)]
        return .blending(BlendingPresentationState(
            sopInstanceUID: sopInstanceUID,
            presentationLabel: blending.label,
            referencedSeries: uSeries + oSeries,
            underlaySeries: uSeries,
            overlaySeries: oSeries,
            underlayVOILUT: uVOI,
            overlayVOILUT: oVOI,
            relativeOpacity: blending.blendingOpacity,
            palette: .hotIron
        ))
    }

    private func buildDICOMKitGraphicAnnotations(
        shapes: [GraphicAnnotation],
        texts: [TextAnnotation],
        referencedImages: [DICOMKit.ReferencedImage]
    ) -> [DICOMKit.GraphicAnnotation] {
        guard !shapes.isEmpty || !texts.isEmpty else { return [] }
        let gObjects: [GraphicObject] = shapes.map { s in
            let gType = PresentationGraphicType(rawValue: s.graphicType.rawValue) ?? .polyline
            var data: [Double] = []
            for pt in s.points {
                data.append(pt.x)
                data.append(pt.y)
            }
            return GraphicObject(type: gType, data: data, filled: s.filled, units: .pixel)
        }
        let tObjects: [TextObject] = texts.map { t in
            let tl = t.boundingBoxTopLeft ?? t.anchorPoint ?? AnnotationPoint(x: 0, y: 0)
            let br = t.boundingBoxBottomRight ?? AnnotationPoint(x: tl.x + 100, y: tl.y + 20)
            return TextObject(
                text: t.text,
                boundingBoxTopLeft: (column: tl.x, row: tl.y),
                boundingBoxBottomRight: (column: br.x, row: br.y),
                anchorPoint: t.anchorPoint.map { (column: $0.x, row: $0.y) },
                anchorPointVisible: t.anchorPointVisible,
                boundingBoxUnits: .pixel,
                anchorPointUnits: .pixel
            )
        }
        let layerName = shapes.first?.layerName ?? texts.first?.layerName ?? "LAYER0"
        return [
            DICOMKit.GraphicAnnotation(
                layer: layerName,
                referencedImages: referencedImages,
                graphicObjects: gObjects,
                textObjects: tObjects
            )
        ]
    }
}
