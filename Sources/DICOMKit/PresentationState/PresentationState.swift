// NEMA-verified: 2026a, checked 2026-09-29 — the four presentation state SOP Class UIDs match PS3.6 2026a Table A-1; module sets per Tables A.33.1-1 to A.33.4-1; Shutter Presentation Color CIELab Value per Table C.11.12-1
//
// PresentationState.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-04.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Base protocol for DICOM Presentation State objects
///
/// Presentation States define how to display medical images with specific
/// window/level settings, annotations, shutters, and other display parameters.
///
/// Reference: PS3.3 Part 3 Section A.33 - Grayscale Softcopy Presentation State IOD
public protocol PresentationState {
    /// SOP Instance UID of the presentation state
    var sopInstanceUID: String { get }
    
    /// SOP Class UID of the presentation state
    var sopClassUID: String { get }
    
    /// Instance number
    var instanceNumber: Int? { get }
    
    /// Presentation label - human-readable name
    var presentationLabel: String? { get }
    
    /// Presentation description
    var presentationDescription: String? { get }
    
    /// Creation date of the presentation state
    var presentationCreationDate: DICOMDate? { get }
    
    /// Creation time of the presentation state
    var presentationCreationTime: DICOMTime? { get }
    
    /// Name of the person who created the presentation state
    var presentationCreatorsName: DICOMPersonName? { get }
    
    /// Referenced series that this presentation state applies to
    var referencedSeries: [ReferencedSeries] { get }
}

/// Referenced series in a presentation state
public struct ReferencedSeries: Sendable, Hashable {
    /// Series Instance UID
    public let seriesInstanceUID: String
    
    /// Referenced images in this series
    public let referencedImages: [ReferencedImage]
    
    /// Initialize a referenced series
    public init(seriesInstanceUID: String, referencedImages: [ReferencedImage]) {
        self.seriesInstanceUID = seriesInstanceUID
        self.referencedImages = referencedImages
    }
}

/// Referenced image in a presentation state
public struct ReferencedImage: Sendable, Hashable {
    /// Referenced SOP Class UID
    public let sopClassUID: String
    
    /// Referenced SOP Instance UID
    public let sopInstanceUID: String
    
    /// Referenced frame numbers (for multi-frame images)
    public let referencedFrameNumbers: [Int]?
    
    /// Initialize a referenced image
    public init(
        sopClassUID: String,
        sopInstanceUID: String,
        referencedFrameNumbers: [Int]? = nil
    ) {
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
        self.referencedFrameNumbers = referencedFrameNumbers
    }
}

/// One item of Softcopy VOI LUT Sequence (0028,3110) with optional per-image/per-frame scope (PS3.3 Section C.11.8).
public struct ScopedVOILUT: Sendable, Hashable {
    /// The VOI LUT transformation (window/level or lookup table).
    public let voiLUT: VOILUT

    /// Referenced images/frames this VOI LUT applies to; empty means all images/frames in `referencedSeries`.
    public let referencedImages: [ReferencedImage]

    public init(voiLUT: VOILUT, referencedImages: [ReferencedImage] = []) {
        self.voiLUT = voiLUT
        self.referencedImages = referencedImages
    }

    /// Whether this VOI LUT item applies to the given image SOP Instance UID and optional 1-based frame number.
    public func applies(toImage sopInstanceUID: String?, frameNumber: Int? = nil) -> Bool {
        guard !referencedImages.isEmpty else { return true }
        guard let sopInstanceUID else { return false }
        return referencedImages.contains { ref in
            guard ref.sopInstanceUID == sopInstanceUID else { return false }
            guard let frames = ref.referencedFrameNumbers, !frames.isEmpty else { return true }
            guard let frameNumber else { return true }
            return frames.contains(frameNumber)
        }
    }
}

/// One item of Displayed Area Selection Sequence (0070,005A) with optional per-image/per-frame scope (PS3.3 Section C.10.4).
public struct ScopedDisplayedArea: Sendable, Hashable {
    /// The displayed area selection.
    public let displayedArea: DisplayedArea

    /// Referenced images/frames this displayed area applies to; empty means all images/frames in `referencedSeries`.
    public let referencedImages: [ReferencedImage]

    public init(displayedArea: DisplayedArea, referencedImages: [ReferencedImage] = []) {
        self.displayedArea = displayedArea
        self.referencedImages = referencedImages
    }

    /// Whether this displayed area item applies to the given image SOP Instance UID and optional 1-based frame number.
    public func applies(toImage sopInstanceUID: String?, frameNumber: Int? = nil) -> Bool {
        guard !referencedImages.isEmpty else { return true }
        guard let sopInstanceUID else { return false }
        return referencedImages.contains { ref in
            guard ref.sopInstanceUID == sopInstanceUID else { return false }
            guard let frames = ref.referencedFrameNumbers, !frames.isEmpty else { return true }
            guard let frameNumber else { return true }
            return frames.contains(frameNumber)
        }
    }
}

/// Grayscale Softcopy Presentation State
///
/// This IOD defines a presentation state for grayscale images with window/level settings,
/// graphic annotations, shutters, and spatial transformations.
///
/// Reference: PS3.3 Part 3 Section A.33 - Grayscale Softcopy Presentation State IOD
public struct GrayscalePresentationState: PresentationState, Sendable {
    // MARK: - Presentation State Identification
    
    public let sopInstanceUID: String
    public let sopClassUID: String
    public let instanceNumber: Int?
    public let presentationLabel: String?
    public let presentationDescription: String?
    public let presentationCreationDate: DICOMDate?
    public let presentationCreationTime: DICOMTime?
    public let presentationCreatorsName: DICOMPersonName?
    
    // MARK: - Presentation State Relationship
    
    public let referencedSeries: [ReferencedSeries]
    
    // MARK: - Display Transformations
    
    /// Modality LUT transformation (rescale slope/intercept or LUT)
    public let modalityLUT: ModalityLUT?
    
    /// Primary VOI LUT transformation (window/level or LUT).
    /// For multi-item or per-image/per-frame scoped Softcopy VOI LUTs, see ``scopedVOILUTs``
    /// and ``effectiveVOILUT(forImage:frameNumber:)``.
    public let voiLUT: VOILUT?

    /// All Softcopy VOI LUT Sequence (0028,3110) items, including per-image/per-frame scoped items (PS3.3 C.11.8).
    public let scopedVOILUTs: [ScopedVOILUT]
    
    /// Presentation LUT transformation (IDENTITY or INVERSE)
    public let presentationLUT: PresentationLUT?
    
    // MARK: - Spatial Transformations
    
    /// Spatial transformation (rotation and flip)
    public let spatialTransformation: SpatialTransformation?
    
    /// Displayed area selection (zoom and pan)
    ///
    /// The Displayed Area Module is M in every presentation state IOD (Tables
    /// A.33.1-1 to A.33.4-1) and its Displayed Area Selection Sequence is Type 1
    /// (Table C.10-4), so a conformant object always has one. The model keeps it
    /// optional on purpose: the parser reads files that omit it rather than
    /// losing their annotations, and a capturing viewer has no area to record
    /// when the whole image is shown. The builders close the gap on the way out —
    /// given the image size they write the full-image area — and
    /// ``GrayscalePresentationStateBuilder/validate(_:imageSize:)`` reports a
    /// state that would still go out without one.
    public let displayedArea: DisplayedArea?

    /// All Displayed Area Selection Sequence (0070,005A) items, including per-image/per-frame scoped items (PS3.3 C.10.4).
    public let scopedDisplayedAreas: [ScopedDisplayedArea]

    // MARK: - Annotations

    /// Graphic layers for organizing annotations
    public let graphicLayers: [GraphicLayer]

    /// Graphic annotations on the image
    public let graphicAnnotations: [GraphicAnnotation]

    // MARK: - Display Shutters

    /// Display shutters for masking regions
    public let shutters: [DisplayShutter]

    /// Shutter Presentation Color CIELab Value (0018,1624): the colour of the
    /// occluded pixels on a colour display. Table C.11.12-1 makes it Type 1C —
    /// required with a shutter in every presentation state SOP class other than
    /// Grayscale Softcopy; nil means none was recorded.
    public let shutterPresentationColor: CIELabColor?

    /// Initialize a grayscale presentation state
    public init(
        sopInstanceUID: String,
        sopClassUID: String = "1.2.840.10008.5.1.4.1.1.11.1", // Grayscale Softcopy Presentation State
        instanceNumber: Int? = nil,
        presentationLabel: String? = nil,
        presentationDescription: String? = nil,
        presentationCreationDate: DICOMDate? = nil,
        presentationCreationTime: DICOMTime? = nil,
        presentationCreatorsName: DICOMPersonName? = nil,
        referencedSeries: [ReferencedSeries],
        modalityLUT: ModalityLUT? = nil,
        voiLUT: VOILUT? = nil,
        scopedVOILUTs: [ScopedVOILUT]? = nil,
        presentationLUT: PresentationLUT? = nil,
        spatialTransformation: SpatialTransformation? = nil,
        displayedArea: DisplayedArea? = nil,
        scopedDisplayedAreas: [ScopedDisplayedArea]? = nil,
        graphicLayers: [GraphicLayer] = [],
        graphicAnnotations: [GraphicAnnotation] = [],
        shutters: [DisplayShutter] = [],
        shutterPresentationColor: CIELabColor? = nil
    ) {
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.instanceNumber = instanceNumber
        self.presentationLabel = presentationLabel
        self.presentationDescription = presentationDescription
        self.presentationCreationDate = presentationCreationDate
        self.presentationCreationTime = presentationCreationTime
        self.presentationCreatorsName = presentationCreatorsName
        self.referencedSeries = referencedSeries
        self.modalityLUT = modalityLUT
        let resolvedVOIs = scopedVOILUTs ?? (voiLUT.map { [ScopedVOILUT(voiLUT: $0)] } ?? [])
        self.scopedVOILUTs = resolvedVOIs
        self.voiLUT = voiLUT ?? resolvedVOIs.first(where: { $0.referencedImages.isEmpty })?.voiLUT ?? resolvedVOIs.first?.voiLUT
        self.presentationLUT = presentationLUT
        self.spatialTransformation = spatialTransformation
        let resolvedAreas = scopedDisplayedAreas ?? (displayedArea.map { [ScopedDisplayedArea(displayedArea: $0)] } ?? [])
        self.scopedDisplayedAreas = resolvedAreas
        self.displayedArea = displayedArea ?? resolvedAreas.first(where: { $0.referencedImages.isEmpty })?.displayedArea ?? resolvedAreas.first?.displayedArea
        self.graphicLayers = graphicLayers
        self.graphicAnnotations = graphicAnnotations
        self.shutters = shutters
        self.shutterPresentationColor = shutterPresentationColor
    }

    /// Resolves the effective VOI LUT for a specific image SOP Instance UID and optional 1-based frame number (PS3.3 C.11.8).
    public func effectiveVOILUT(forImage sopInstanceUID: String? = nil, frameNumber: Int? = nil) -> VOILUT? {
        if let sopInstanceUID {
            if let frameNumber,
               let frameMatch = scopedVOILUTs.first(where: {
                   !$0.referencedImages.isEmpty &&
                   $0.referencedImages.contains(where: {
                       $0.sopInstanceUID == sopInstanceUID &&
                       ($0.referencedFrameNumbers?.contains(frameNumber) == true)
                   })
               }) {
                return frameMatch.voiLUT
            }
            if let imageMatch = scopedVOILUTs.first(where: {
                !$0.referencedImages.isEmpty && $0.applies(toImage: sopInstanceUID, frameNumber: frameNumber)
            }) {
                return imageMatch.voiLUT
            }
        }
        return scopedVOILUTs.first(where: { $0.referencedImages.isEmpty })?.voiLUT ?? voiLUT
    }

    /// Resolves the effective Displayed Area for a specific image SOP Instance UID and optional 1-based frame number (PS3.3 C.10.4).
    public func effectiveDisplayedArea(forImage sopInstanceUID: String? = nil, frameNumber: Int? = nil) -> DisplayedArea? {
        if let sopInstanceUID {
            if let frameNumber,
               let frameMatch = scopedDisplayedAreas.first(where: {
                   !$0.referencedImages.isEmpty &&
                   $0.referencedImages.contains(where: {
                       $0.sopInstanceUID == sopInstanceUID &&
                       ($0.referencedFrameNumbers?.contains(frameNumber) == true)
                   })
               }) {
                return frameMatch.displayedArea
            }
            if let imageMatch = scopedDisplayedAreas.first(where: {
                !$0.referencedImages.isEmpty && $0.applies(toImage: sopInstanceUID, frameNumber: frameNumber)
            }) {
                return imageMatch.displayedArea
            }
        }
        return scopedDisplayedAreas.first(where: { $0.referencedImages.isEmpty })?.displayedArea ?? displayedArea
    }
}

/// Color Softcopy Presentation State
///
/// This IOD defines a presentation state for color images with ICC profile-based
/// color management, spatial transformations, and annotations.
///
/// Table A.33.2-1 (2026a) has no Modality LUT, Softcopy VOI LUT or Softcopy
/// Presentation LUT module — a colour image has no grey pipeline to record —
/// and makes the ICC Profile module (C.11.15) mandatory; hence no LUT fields
/// here and `iccProfile`, which ``ColorPresentationStateBuilder`` writes as
/// sRGB when nil. Written by ``ColorPresentationStateBuilder``; read through
/// `GrayscalePresentationStateParser` and ``init(parsed:iccProfile:)``.
///
/// Reference: PS3.3 Section A.33.2 - Color Softcopy Presentation State IOD
public struct ColorPresentationState: PresentationState, Sendable {
    // MARK: - Presentation State Identification
    
    public let sopInstanceUID: String
    public let sopClassUID: String
    public let instanceNumber: Int?
    public let presentationLabel: String?
    public let presentationDescription: String?
    public let presentationCreationDate: DICOMDate?
    public let presentationCreationTime: DICOMTime?
    public let presentationCreatorsName: DICOMPersonName?
    
    // MARK: - Presentation State Relationship
    
    public let referencedSeries: [ReferencedSeries]
    
    // MARK: - Color Management
    
    /// ICC Profile for device-independent color management
    public let iccProfile: ICCProfile?

    /// Color Space (0028,2002) Defined Term (e.g. "SRGB", "ADOBERGB", "ROMMRGB", "DISPLAYP3")
    public let colorSpace: String?
    
    // MARK: - Spatial Transformations
    
    /// Spatial transformation (rotation and flip)
    public let spatialTransformation: SpatialTransformation?
    
    /// Displayed area selection (zoom and pan)
    public let displayedArea: DisplayedArea?

    /// All Displayed Area Selection Sequence (0070,005A) items, including per-image/per-frame scoped items (PS3.3 C.10.4).
    public let scopedDisplayedAreas: [ScopedDisplayedArea]
    
    // MARK: - Annotations
    
    /// Graphic layers for organizing annotations
    public let graphicLayers: [GraphicLayer]
    
    /// Graphic annotations on the image
    public let graphicAnnotations: [GraphicAnnotation]
    
    // MARK: - Display Shutters
    
    /// Display shutters for masking regions
    public let shutters: [DisplayShutter]

    /// Shutter Presentation Color CIELab Value (0018,1624): the colour of the
    /// occluded pixels on a colour display. Table C.11.12-1 makes it Type 1C —
    /// required with a shutter in every presentation state SOP class other than
    /// Grayscale Softcopy; nil means none was recorded.
    public let shutterPresentationColor: CIELabColor?

    /// Initialize a color presentation state
    public init(
        sopInstanceUID: String,
        sopClassUID: String = "1.2.840.10008.5.1.4.1.1.11.2", // Color Softcopy Presentation State
        instanceNumber: Int? = nil,
        presentationLabel: String? = nil,
        presentationDescription: String? = nil,
        presentationCreationDate: DICOMDate? = nil,
        presentationCreationTime: DICOMTime? = nil,
        presentationCreatorsName: DICOMPersonName? = nil,
        referencedSeries: [ReferencedSeries],
        iccProfile: ICCProfile? = nil,
        colorSpace: String? = nil,
        spatialTransformation: SpatialTransformation? = nil,
        displayedArea: DisplayedArea? = nil,
        scopedDisplayedAreas: [ScopedDisplayedArea]? = nil,
        graphicLayers: [GraphicLayer] = [],
        graphicAnnotations: [GraphicAnnotation] = [],
        shutters: [DisplayShutter] = [],
        shutterPresentationColor: CIELabColor? = nil
    ) {
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.instanceNumber = instanceNumber
        self.presentationLabel = presentationLabel
        self.presentationDescription = presentationDescription
        self.presentationCreationDate = presentationCreationDate
        self.presentationCreationTime = presentationCreationTime
        self.presentationCreatorsName = presentationCreatorsName
        self.referencedSeries = referencedSeries
        self.iccProfile = iccProfile
        self.colorSpace = colorSpace
        self.spatialTransformation = spatialTransformation
        let resolvedAreas = scopedDisplayedAreas ?? (displayedArea.map { [ScopedDisplayedArea(displayedArea: $0)] } ?? [])
        self.scopedDisplayedAreas = resolvedAreas
        self.displayedArea = displayedArea ?? resolvedAreas.first(where: { $0.referencedImages.isEmpty })?.displayedArea ?? resolvedAreas.first?.displayedArea
        self.graphicLayers = graphicLayers
        self.graphicAnnotations = graphicAnnotations
        self.shutters = shutters
        self.shutterPresentationColor = shutterPresentationColor
    }

    /// Resolves the effective Displayed Area for a specific image SOP Instance UID and optional 1-based frame number (PS3.3 C.10.4).
    public func effectiveDisplayedArea(forImage sopInstanceUID: String? = nil, frameNumber: Int? = nil) -> DisplayedArea? {
        if let sopInstanceUID {
            if let frameNumber,
               let frameMatch = scopedDisplayedAreas.first(where: {
                   !$0.referencedImages.isEmpty &&
                   $0.referencedImages.contains(where: {
                       $0.sopInstanceUID == sopInstanceUID &&
                       ($0.referencedFrameNumbers?.contains(frameNumber) == true)
                   })
               }) {
                return frameMatch.displayedArea
            }
            if let imageMatch = scopedDisplayedAreas.first(where: {
                !$0.referencedImages.isEmpty && $0.applies(toImage: sopInstanceUID, frameNumber: frameNumber)
            }) {
                return imageMatch.displayedArea
            }
        }
        return scopedDisplayedAreas.first(where: { $0.referencedImages.isEmpty })?.displayedArea ?? displayedArea
    }
}

/// Pseudo-Color Softcopy Presentation State
///
/// This IOD defines a presentation state for grayscale images displayed with
/// pseudo-color (false color) mapping using RGB lookup tables.
///
/// Reference: PS3.3 Section A.33.3 - Pseudo-Color Softcopy Presentation State IOD
public struct PseudoColorPresentationState: PresentationState, Sendable {
    // MARK: - Presentation State Identification
    
    public let sopInstanceUID: String
    public let sopClassUID: String
    public let instanceNumber: Int?
    public let presentationLabel: String?
    public let presentationDescription: String?
    public let presentationCreationDate: DICOMDate?
    public let presentationCreationTime: DICOMTime?
    public let presentationCreatorsName: DICOMPersonName?
    
    // MARK: - Presentation State Relationship
    
    public let referencedSeries: [ReferencedSeries]
    
    // MARK: - Display Transformations
    
    /// Modality LUT transformation (rescale slope/intercept or LUT)
    public let modalityLUT: ModalityLUT?
    
    /// Primary VOI LUT transformation (window/level or LUT)
    public let voiLUT: VOILUT?

    /// All Softcopy VOI LUT Sequence (0028,3110) items, including per-image/per-frame scoped items (PS3.3 C.11.8).
    public let scopedVOILUTs: [ScopedVOILUT]
    
    /// Palette Color LUT for pseudo-color mapping
    public let paletteColorLUT: PaletteColorLUT

    /// Matched standard or preset pseudo-color palette, if known
    public let palette: PseudoColorPalette?

    /// Palette Color Lookup Table UID (0028,1199), if present (PS3.6 Annex B well-known UID)
    public let paletteColorLookupTableUID: String?

    /// ICC Profile (0028,2000) for device-independent color management (Mandatory in PS3.3 A.33.3)
    public let iccProfile: ICCProfile?

    /// Color Space (0028,2002) Defined Term (e.g. "SRGB")
    public let colorSpace: String?
    
    // MARK: - Spatial Transformations
    
    /// Spatial transformation (rotation and flip)
    public let spatialTransformation: SpatialTransformation?
    
    /// Displayed area selection (zoom and pan)
    public let displayedArea: DisplayedArea?

    /// All Displayed Area Selection Sequence (0070,005A) items, including per-image/per-frame scoped items (PS3.3 C.10.4).
    public let scopedDisplayedAreas: [ScopedDisplayedArea]
    
    // MARK: - Annotations
    
    /// Graphic layers for organizing annotations
    public let graphicLayers: [GraphicLayer]
    
    /// Graphic annotations on the image
    public let graphicAnnotations: [GraphicAnnotation]
    
    // MARK: - Display Shutters
    
    /// Display shutters for masking regions
    public let shutters: [DisplayShutter]

    /// Shutter Presentation Color CIELab Value (0018,1624): the colour of the
    /// occluded pixels on a colour display. Table C.11.12-1 makes it Type 1C —
    /// required with a shutter in every presentation state SOP class other than
    /// Grayscale Softcopy; nil means none was recorded.
    public let shutterPresentationColor: CIELabColor?

    /// Initialize a pseudo-color presentation state
    public init(
        sopInstanceUID: String,
        sopClassUID: String = "1.2.840.10008.5.1.4.1.1.11.3", // Pseudo-Color Softcopy Presentation State
        instanceNumber: Int? = nil,
        presentationLabel: String? = nil,
        presentationDescription: String? = nil,
        presentationCreationDate: DICOMDate? = nil,
        presentationCreationTime: DICOMTime? = nil,
        presentationCreatorsName: DICOMPersonName? = nil,
        referencedSeries: [ReferencedSeries],
        modalityLUT: ModalityLUT? = nil,
        voiLUT: VOILUT? = nil,
        scopedVOILUTs: [ScopedVOILUT]? = nil,
        paletteColorLUT: PaletteColorLUT,
        palette: PseudoColorPalette? = nil,
        paletteColorLookupTableUID: String? = nil,
        iccProfile: ICCProfile? = nil,
        colorSpace: String? = nil,
        spatialTransformation: SpatialTransformation? = nil,
        displayedArea: DisplayedArea? = nil,
        scopedDisplayedAreas: [ScopedDisplayedArea]? = nil,
        graphicLayers: [GraphicLayer] = [],
        graphicAnnotations: [GraphicAnnotation] = [],
        shutters: [DisplayShutter] = [],
        shutterPresentationColor: CIELabColor? = nil
    ) {
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.instanceNumber = instanceNumber
        self.presentationLabel = presentationLabel
        self.presentationDescription = presentationDescription
        self.presentationCreationDate = presentationCreationDate
        self.presentationCreationTime = presentationCreationTime
        self.presentationCreatorsName = presentationCreatorsName
        self.referencedSeries = referencedSeries
        self.modalityLUT = modalityLUT
        let resolvedVOIs = scopedVOILUTs ?? (voiLUT.map { [ScopedVOILUT(voiLUT: $0)] } ?? [])
        self.scopedVOILUTs = resolvedVOIs
        self.voiLUT = voiLUT ?? resolvedVOIs.first(where: { $0.referencedImages.isEmpty })?.voiLUT ?? resolvedVOIs.first?.voiLUT
        self.paletteColorLUT = paletteColorLUT
        self.palette = palette ?? PseudoColorPalette.matching(paletteColorLUT)?.palette
        self.paletteColorLookupTableUID = paletteColorLookupTableUID ?? self.palette?.wellKnownSOPInstanceUID
        self.iccProfile = iccProfile
        self.colorSpace = colorSpace
        self.spatialTransformation = spatialTransformation
        let resolvedAreas = scopedDisplayedAreas ?? (displayedArea.map { [ScopedDisplayedArea(displayedArea: $0)] } ?? [])
        self.scopedDisplayedAreas = resolvedAreas
        self.displayedArea = displayedArea ?? resolvedAreas.first(where: { $0.referencedImages.isEmpty })?.displayedArea ?? resolvedAreas.first?.displayedArea
        self.graphicLayers = graphicLayers
        self.graphicAnnotations = graphicAnnotations
        self.shutters = shutters
        self.shutterPresentationColor = shutterPresentationColor
    }

    /// Convenience initializer using a standard `PseudoColorPalette`
    public init(
        sopInstanceUID: String,
        sopClassUID: String = "1.2.840.10008.5.1.4.1.1.11.3",
        instanceNumber: Int? = nil,
        presentationLabel: String? = nil,
        presentationDescription: String? = nil,
        presentationCreationDate: DICOMDate? = nil,
        presentationCreationTime: DICOMTime? = nil,
        presentationCreatorsName: DICOMPersonName? = nil,
        referencedSeries: [ReferencedSeries],
        modalityLUT: ModalityLUT? = nil,
        voiLUT: VOILUT? = nil,
        scopedVOILUTs: [ScopedVOILUT]? = nil,
        palette: PseudoColorPalette,
        inverted: Bool = false,
        iccProfile: ICCProfile? = nil,
        colorSpace: String? = "SRGB",
        spatialTransformation: SpatialTransformation? = nil,
        displayedArea: DisplayedArea? = nil,
        scopedDisplayedAreas: [ScopedDisplayedArea]? = nil,
        graphicLayers: [GraphicLayer] = [],
        graphicAnnotations: [GraphicAnnotation] = [],
        shutters: [DisplayShutter] = [],
        shutterPresentationColor: CIELabColor? = nil
    ) {
        let lut = palette.paletteColorLUT(inverted: inverted)
        self.init(
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            instanceNumber: instanceNumber,
            presentationLabel: presentationLabel,
            presentationDescription: presentationDescription,
            presentationCreationDate: presentationCreationDate,
            presentationCreationTime: presentationCreationTime,
            presentationCreatorsName: presentationCreatorsName,
            referencedSeries: referencedSeries,
            modalityLUT: modalityLUT,
            voiLUT: voiLUT,
            scopedVOILUTs: scopedVOILUTs,
            paletteColorLUT: lut,
            palette: palette,
            paletteColorLookupTableUID: inverted ? nil : palette.wellKnownSOPInstanceUID,
            iccProfile: iccProfile,
            colorSpace: colorSpace,
            spatialTransformation: spatialTransformation,
            displayedArea: displayedArea,
            scopedDisplayedAreas: scopedDisplayedAreas,
            graphicLayers: graphicLayers,
            graphicAnnotations: graphicAnnotations,
            shutters: shutters,
            shutterPresentationColor: shutterPresentationColor
        )
    }

    /// Resolves the effective VOI LUT for a specific image SOP Instance UID and optional 1-based frame number (PS3.3 C.11.8).
    public func effectiveVOILUT(forImage sopInstanceUID: String? = nil, frameNumber: Int? = nil) -> VOILUT? {
        if let sopInstanceUID {
            if let frameNumber,
               let frameMatch = scopedVOILUTs.first(where: {
                   !$0.referencedImages.isEmpty &&
                   $0.referencedImages.contains(where: {
                       $0.sopInstanceUID == sopInstanceUID &&
                       ($0.referencedFrameNumbers?.contains(frameNumber) == true)
                   })
               }) {
                return frameMatch.voiLUT
            }
            if let imageMatch = scopedVOILUTs.first(where: {
                !$0.referencedImages.isEmpty && $0.applies(toImage: sopInstanceUID, frameNumber: frameNumber)
            }) {
                return imageMatch.voiLUT
            }
        }
        return scopedVOILUTs.first(where: { $0.referencedImages.isEmpty })?.voiLUT ?? voiLUT
    }

    /// Resolves the effective Displayed Area for a specific image SOP Instance UID and optional 1-based frame number (PS3.3 C.10.4).
    public func effectiveDisplayedArea(forImage sopInstanceUID: String? = nil, frameNumber: Int? = nil) -> DisplayedArea? {
        if let sopInstanceUID {
            if let frameNumber,
               let frameMatch = scopedDisplayedAreas.first(where: {
                   !$0.referencedImages.isEmpty &&
                   $0.referencedImages.contains(where: {
                       $0.sopInstanceUID == sopInstanceUID &&
                       ($0.referencedFrameNumbers?.contains(frameNumber) == true)
                   })
               }) {
                return frameMatch.displayedArea
            }
            if let imageMatch = scopedDisplayedAreas.first(where: {
                !$0.referencedImages.isEmpty && $0.applies(toImage: sopInstanceUID, frameNumber: frameNumber)
            }) {
                return imageMatch.displayedArea
            }
        }
        return scopedDisplayedAreas.first(where: { $0.referencedImages.isEmpty })?.displayedArea ?? displayedArea
    }
}

/// Blending Softcopy Presentation State
///
/// This IOD defines a presentation state for blending multiple images together,
/// typically used for multi-modality fusion (e.g., PET/CT, PET/MR).
///
/// Reference: PS3.3 Section A.33.4 - Blending Softcopy Presentation State IOD
/// Reference: PS3.3 Section C.11.14 - Presentation State Blending Module
public struct BlendingPresentationState: PresentationState, Sendable {
    // MARK: - Presentation State Identification
    
    public let sopInstanceUID: String
    public let sopClassUID: String
    public let instanceNumber: Int?
    public let presentationLabel: String?
    public let presentationDescription: String?
    public let presentationCreationDate: DICOMDate?
    public let presentationCreationTime: DICOMTime?
    public let presentationCreatorsName: DICOMPersonName?
    
    // MARK: - Presentation State Relationship
    
    public let referencedSeries: [ReferencedSeries]
    
    // MARK: - Blending Configuration (PS3.3 C.11.14)
    
    /// Blending display sets defining how images are blended
    public let blendingDisplaySets: [BlendingDisplaySet]

    /// Underlay referenced series (`BlendingPosition = "UNDERLAY"` in `BlendingSequence (0070,0402)`)
    public let underlaySeries: [ReferencedSeries]

    /// Overlay referenced series (`BlendingPosition = "OVERLAY"` in `BlendingSequence (0070,0402)`)
    public let overlaySeries: [ReferencedSeries]

    /// Underlay Modality LUT transformation
    public let underlayModalityLUT: ModalityLUT?

    /// Overlay Modality LUT transformation
    public let overlayModalityLUT: ModalityLUT?

    /// Underlay VOI LUT transformation
    public let underlayVOILUT: VOILUT?

    /// Overlay VOI LUT transformation
    public let overlayVOILUT: VOILUT?

    /// Relative Opacity `(0070,0403)` of the superimposed (`OVERLAY`) image (`0.0...1.0`)
    public let relativeOpacity: Double

    /// Palette Color LUT applied to the superimposed (`OVERLAY`) image (PS3.3 Table A.33.4-1)
    public let paletteColorLUT: PaletteColorLUT?

    /// Well-known or matched pseudo-color palette for the overlay
    public let palette: PseudoColorPalette?

    /// Optional ICC Profile (PS3.3 C.11.15)
    public let iccProfile: ICCProfile?

    /// Optional Color Space `(0028,2002)`
    public let colorSpace: String?
    
    // MARK: - Spatial Transformations
    
    /// Spatial transformation (rotation and flip)
    public let spatialTransformation: SpatialTransformation?
    
    /// Displayed area selection (zoom and pan)
    public let displayedArea: DisplayedArea?

    /// Per-image / per-frame scoped displayed area items (PS3.3 C.10.4)
    public let scopedDisplayedAreas: [ScopedDisplayedArea]
    
    // MARK: - Annotations
    
    /// Graphic layers for organizing annotations
    public let graphicLayers: [GraphicLayer]
    
    /// Graphic annotations on the image
    public let graphicAnnotations: [GraphicAnnotation]
    
    // MARK: - Display Shutters
    
    /// Display shutters for masking regions
    public let shutters: [DisplayShutter]

    /// Shutter Presentation Color CIELab Value (0018,1624): the colour of the
    /// occluded pixels on a colour display. Table C.11.12-1 makes it Type 1C —
    /// required with a shutter in every presentation state SOP class other than
    /// Grayscale Softcopy; nil means none was recorded.
    public let shutterPresentationColor: CIELabColor?

    /// Initialize a blending presentation state
    public init(
        sopInstanceUID: String,
        sopClassUID: String = "1.2.840.10008.5.1.4.1.1.11.4", // Blending Softcopy Presentation State
        instanceNumber: Int? = nil,
        presentationLabel: String? = nil,
        presentationDescription: String? = nil,
        presentationCreationDate: DICOMDate? = nil,
        presentationCreationTime: DICOMTime? = nil,
        presentationCreatorsName: DICOMPersonName? = nil,
        referencedSeries: [ReferencedSeries],
        blendingDisplaySets: [BlendingDisplaySet] = [],
        underlaySeries: [ReferencedSeries] = [],
        overlaySeries: [ReferencedSeries] = [],
        underlayModalityLUT: ModalityLUT? = nil,
        overlayModalityLUT: ModalityLUT? = nil,
        underlayVOILUT: VOILUT? = nil,
        overlayVOILUT: VOILUT? = nil,
        relativeOpacity: Double = 0.5,
        paletteColorLUT: PaletteColorLUT? = nil,
        palette: PseudoColorPalette? = nil,
        iccProfile: ICCProfile? = nil,
        colorSpace: String? = "SRGB",
        spatialTransformation: SpatialTransformation? = nil,
        displayedArea: DisplayedArea? = nil,
        scopedDisplayedAreas: [ScopedDisplayedArea]? = nil,
        graphicLayers: [GraphicLayer] = [],
        graphicAnnotations: [GraphicAnnotation] = [],
        shutters: [DisplayShutter] = [],
        shutterPresentationColor: CIELabColor? = nil
    ) {
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.instanceNumber = instanceNumber
        self.presentationLabel = presentationLabel
        self.presentationDescription = presentationDescription
        self.presentationCreationDate = presentationCreationDate
        self.presentationCreationTime = presentationCreationTime
        self.presentationCreatorsName = presentationCreatorsName
        self.referencedSeries = referencedSeries
        self.blendingDisplaySets = blendingDisplaySets
        self.underlaySeries = underlaySeries
        self.overlaySeries = overlaySeries
        self.underlayModalityLUT = underlayModalityLUT
        self.overlayModalityLUT = overlayModalityLUT
        self.underlayVOILUT = underlayVOILUT
        self.overlayVOILUT = overlayVOILUT
        self.relativeOpacity = max(0.0, min(1.0, relativeOpacity))
        self.palette = palette ?? (paletteColorLUT.flatMap { PseudoColorPalette.matching($0)?.palette })
        self.paletteColorLUT = paletteColorLUT ?? self.palette?.paletteColorLUT()
        self.iccProfile = iccProfile
        self.colorSpace = colorSpace
        self.spatialTransformation = spatialTransformation
        let resolvedAreas = scopedDisplayedAreas ?? (displayedArea.map { [ScopedDisplayedArea(displayedArea: $0)] } ?? [])
        self.scopedDisplayedAreas = resolvedAreas
        self.displayedArea = displayedArea ?? resolvedAreas.first(where: { $0.referencedImages.isEmpty })?.displayedArea ?? resolvedAreas.first?.displayedArea
        self.graphicLayers = graphicLayers
        self.graphicAnnotations = graphicAnnotations
        self.shutters = shutters
        self.shutterPresentationColor = shutterPresentationColor
    }

    /// Resolves the effective Displayed Area for a specific image SOP Instance UID and optional 1-based frame number (PS3.3 C.10.4).
    public func effectiveDisplayedArea(forImage sopInstanceUID: String? = nil, frameNumber: Int? = nil) -> DisplayedArea? {
        if let sopInstanceUID {
            if let frameNumber,
               let frameMatch = scopedDisplayedAreas.first(where: {
                   !$0.referencedImages.isEmpty &&
                   $0.referencedImages.contains(where: {
                       $0.sopInstanceUID == sopInstanceUID &&
                       ($0.referencedFrameNumbers?.contains(frameNumber) == true)
                   })
               }) {
                return frameMatch.displayedArea
            }
            if let imageMatch = scopedDisplayedAreas.first(where: {
                !$0.referencedImages.isEmpty && $0.applies(toImage: sopInstanceUID, frameNumber: frameNumber)
            }) {
                return imageMatch.displayedArea
            }
        }
        return scopedDisplayedAreas.first(where: { $0.referencedImages.isEmpty })?.displayedArea ?? displayedArea
    }
}

/// SOP Class UIDs for Presentation State IODs
public extension String {
    /// Grayscale Softcopy Presentation State Storage SOP Class UID
    static let grayscaleSoftcopyPresentationStateStorage = "1.2.840.10008.5.1.4.1.1.11.1"
    
    /// Color Softcopy Presentation State Storage SOP Class UID
    static let colorSoftcopyPresentationStateStorage = "1.2.840.10008.5.1.4.1.1.11.2"
    
    /// Pseudo-Color Softcopy Presentation State Storage SOP Class UID
    static let pseudoColorSoftcopyPresentationStateStorage = "1.2.840.10008.5.1.4.1.1.11.3"
    
    /// Blending Softcopy Presentation State Storage SOP Class UID
    static let blendingSoftcopyPresentationStateStorage = "1.2.840.10008.5.1.4.1.1.11.4"
}
