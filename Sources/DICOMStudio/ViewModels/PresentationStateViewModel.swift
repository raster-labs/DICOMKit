// PresentationStateViewModel.swift
// DICOMStudio
//
// DICOM Studio — Presentation State ViewModel
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (selection state over the GSPS, shutter, palette and blending models; defaults to IDENTITY Presentation LUT Shape when no GSPS is applied, PS3.3 2026a C.11.6)

import Foundation
import Observation

/// ViewModel for managing DICOM Presentation States.
///
/// Handles GSPS, Color, Pseudo-Color, and Blending presentation state
/// selection, application, and editing.
///
/// Requires macOS 14+ / iOS 17+ for the `@Observable` macro.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
public final class PresentationStateViewModel {

    // MARK: - Available States

    /// Available GSPS models for the current image.
    public var availableGSPS: [GSPSModel] = []

    /// Available pseudo-color palettes.
    public var availablePalettes: [PresentationStatePalette] = PresentationStatePalette.allCases

    // MARK: - Active State

    /// Currently selected GSPS (nil = no GSPS applied).
    public var activeGSPS: GSPSModel?

    /// Currently active presentation state type.
    public var activeStateType: PresentationStateType?

    /// Current pseudo-color palette.
    public var activePalette: PresentationStatePalette = .hotIron

    /// Current blending opacity.
    public var blendingOpacity: Double = BlendingHelpers.defaultOpacity

    /// Whether a GSPS is currently being applied.
    public var isGSPSActive: Bool {
        activeGSPS != nil
    }

    // MARK: - Shutter State

    /// Active shutter model (nil = no shutter).
    public var activeShutter: ShutterModel?

    /// Whether a shutter is active.
    public var isShutterActive: Bool {
        activeShutter?.hasShutter ?? false
    }

    // MARK: - Annotation Editing

    /// Whether annotation editing mode is active.
    public var isEditingAnnotations: Bool = false

    /// Graphic annotations being edited.
    public var editingAnnotations: [GraphicAnnotation] = []

    /// Text annotations being edited.
    public var editingTextAnnotations: [TextAnnotation] = []

    /// Currently selected annotation (for editing).
    public var selectedAnnotationID: UUID?

    // MARK: - Services

    /// Presentation state service.
    public let presentationStateService: PresentationStateService

    // MARK: - Initialization

    /// Creates a presentation state ViewModel.
    public init(presentationStateService: PresentationStateService = PresentationStateService()) {
        self.presentationStateService = presentationStateService
    }

    // MARK: - GSPS Management

    /// Loads available GSPS for a given SOP Instance UID.
    ///
    /// - Parameters:
    ///   - allStates: All GSPS models.
    ///   - sopInstanceUID: SOP Instance UID of the current image.
    public func loadGSPS(allStates: [GSPSModel], forImage sopInstanceUID: String) {
        availableGSPS = presentationStateService.gspsForImage(
            allStates: allStates,
            sopInstanceUID: sopInstanceUID
        )
        activeGSPS = nil
        activeStateType = nil
    }

    /// Applies a GSPS to the current image.
    ///
    /// - Parameter gsps: The GSPS to apply.
    public func applyGSPS(_ gsps: GSPSModel) {
        activeGSPS = gsps
        activeStateType = .grayscale
        editingAnnotations = gsps.graphicAnnotations
        editingTextAnnotations = gsps.textAnnotations
    }

    /// Removes the active GSPS.
    public func removeGSPS() {
        activeGSPS = nil
        activeStateType = nil
        editingAnnotations = []
        editingTextAnnotations = []
        selectedAnnotationID = nil
    }

    // MARK: - Window/Level from GSPS

    /// Returns window/level from the active GSPS, or the provided defaults.
    ///
    /// - Parameters:
    ///   - defaultCenter: Default window center.
    ///   - defaultWidth: Default window width.
    /// - Returns: Effective window center and width.
    public func effectiveWindowLevel(
        defaultCenter: Double,
        defaultWidth: Double
    ) -> (center: Double, width: Double) {
        guard let gsps = activeGSPS else {
            return (defaultCenter, defaultWidth)
        }
        return presentationStateService.applyGSPSWindowLevel(
            gsps: gsps,
            currentCenter: defaultCenter,
            currentWidth: defaultWidth
        )
    }

    /// Returns the effective spatial rotation angle.
    public var effectiveRotation: Double {
        guard let gsps = activeGSPS else { return 0.0 }
        return presentationStateService.effectiveRotation(gsps: gsps)
    }

    /// Returns whether the image should be flipped horizontally.
    public var effectiveFlipH: Bool {
        guard let gsps = activeGSPS else { return false }
        return presentationStateService.effectiveFlipH(gsps: gsps)
    }

    /// Returns the effective presentation LUT shape.
    public var effectivePresentationLUT: PresentationLUTShape {
        activeGSPS?.presentationLUTShape ?? .identity
    }

    // MARK: - Shutter Management

    /// Applies a shutter to the display.
    ///
    /// - Parameter shutter: The shutter to apply.
    public func applyShutter(_ shutter: ShutterModel) {
        activeShutter = shutter
    }

    /// Removes the active shutter.
    public func removeShutter() {
        activeShutter = nil
    }

    // MARK: - Pseudo-Color

    /// Sets the active pseudo-color palette.
    ///
    /// - Parameter palette: Palette to activate.
    public func setPalette(_ palette: PresentationStatePalette) {
        activePalette = palette
        activeStateType = .pseudoColor
    }

    // MARK: - Blending

    /// Sets the blending opacity.
    ///
    /// - Parameter opacity: Opacity value in [0, 1].
    public func setBlendingOpacity(_ opacity: Double) {
        blendingOpacity = BlendingHelpers.clampOpacity(opacity)
        if activeStateType != .blending {
            activeStateType = .blending
        }
    }

    // MARK: - Annotation Editing

    /// Starts annotation editing mode.
    public func startAnnotationEditing() {
        isEditingAnnotations = true
    }

    /// Stops annotation editing mode.
    public func stopAnnotationEditing() {
        isEditingAnnotations = false
        selectedAnnotationID = nil
    }

    /// Selects an annotation for editing.
    ///
    /// - Parameter id: Annotation ID.
    public func selectAnnotation(_ id: UUID?) {
        selectedAnnotationID = id
    }

    /// Adds a graphic annotation.
    ///
    /// - Parameter annotation: The annotation to add.
    public func addAnnotation(_ annotation: GraphicAnnotation) {
        editingAnnotations.append(annotation)
    }

    /// Adds a text annotation.
    ///
    /// - Parameter annotation: The text annotation to add.
    public func addTextAnnotation(_ annotation: TextAnnotation) {
        editingTextAnnotations.append(annotation)
    }

    /// Removes a graphic annotation by ID.
    ///
    /// - Parameter id: Annotation ID.
    public func removeAnnotation(_ id: UUID) {
        editingAnnotations.removeAll { $0.id == id }
        if selectedAnnotationID == id {
            selectedAnnotationID = nil
        }
    }

    /// Removes a text annotation by ID.
    ///
    /// - Parameter id: Text annotation ID.
    public func removeTextAnnotation(_ id: UUID) {
        editingTextAnnotations.removeAll { $0.id == id }
    }

    // MARK: - Display Text

    /// Returns a label for the active presentation state.
    public var activeStateLabel: String {
        guard let type = activeStateType else { return "None" }
        return PresentationStateHelpers.typeLabel(for: type)
    }

    /// Returns the number of graphic annotations.
    public var annotationCount: Int {
        editingAnnotations.count + editingTextAnnotations.count
    }

    /// Returns the blending opacity as a formatted percentage.
    public var blendingOpacityLabel: String {
        BlendingHelpers.opacityLabel(blendingOpacity)
    }

    /// Returns the palette label.
    public var paletteLabel: String {
        ColorLUTHelpers.paletteLabel(for: activePalette)
    }
}
