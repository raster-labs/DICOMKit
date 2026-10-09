// PresentationStateService.swift
// DICOMStudio
//
// DICOM Studio — Service for loading and applying DICOM Presentation States
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own: a GSPS Softcopy VOI LUT replaces the image's window (PS3.4 2026a N.2.1.3), rotation/flip come from PresentationStateHelpers (C.10.6), the default layer name LAYER0 is a free Graphic Layer (0070,0002) value

import Foundation

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
}
