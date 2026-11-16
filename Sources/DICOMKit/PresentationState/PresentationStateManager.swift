// NEMA-verified: 2026a, checked 2026-11-16 — PS3.3 2026a A.33.1 (GSPS), A.33.2 (CSPS), A.33.3 (Pseudo-CSPS), A.33.4 (Blending Softcopy PS), Table C.18.4-1 (Image Reference Macro nested PR reference), PS3.16 TID 1500 (Measurement Report), and TID 2010 (Key Object Selection)
// PresentationStateManager.swift
// DICOMKit
//
// High-level Study / Series / Image / Frame API for creating, saving, loading,
// discovering, and applying GSPS, CSPS, and Pseudo-CSPS Presentation States
// and companion Structured Reports (TID 1500 Measurement Report & TID 2010 KOS).
//
// Reference:
// - DICOM PS3.3 A.33.1 — Grayscale Softcopy Presentation State IOD (1.2.840.10008.5.1.4.1.1.11.1)
// - DICOM PS3.3 A.33.2 — Color Softcopy Presentation State IOD (1.2.840.10008.5.1.4.1.1.11.2)
// - DICOM PS3.3 A.33.3 — Pseudo-Color Softcopy Presentation State IOD (1.2.840.10008.5.1.4.1.1.11.3)
// - DICOM PS3.3 Table C.18.4-1 — IMAGE Content Item with nested Presentation State Reference
// - DICOM PS3.16 TID 1500 — Measurement Report
// - DICOM PS3.16 TID 2010 — Key Object Selection

import Foundation
import DICOMCore

// MARK: - Companion SR Generation Options

/// Controls whether companion DICOM Structured Report (SR) instances are generated alongside a Presentation State.
public struct CompanionSROptions: Sendable, Equatable {
    /// Generate a TID 1500 Measurement Report SR (`ComprehensiveSR`) with ROI measurements and nested PR reference.
    public var generateMeasurementReport: Bool

    /// Generate a TID 2010 Key Object Selection (KOS) document flagging the referenced images with nested PR reference.
    public var generateKeyObjectSelection: Bool

    /// Procedure reported concept for the TID 1500 Measurement Report.
    public var procedureReported: CodedConcept

    /// Key Object Selection document title (CID 7010).
    public var keyObjectSelectionPurpose: DocumentTitle

    /// Optional Key Object Selection description text.
    public var keyObjectDescription: String?

    public static let none = CompanionSROptions(
        generateMeasurementReport: false,
        generateKeyObjectSelection: false
    )

    public static let measurementReportOnly = CompanionSROptions(
        generateMeasurementReport: true,
        generateKeyObjectSelection: false
    )

    public static let keyObjectSelectionOnly = CompanionSROptions(
        generateMeasurementReport: false,
        generateKeyObjectSelection: true
    )

    public static let both = CompanionSROptions(
        generateMeasurementReport: true,
        generateKeyObjectSelection: true
    )

    public init(
        generateMeasurementReport: Bool = false,
        generateKeyObjectSelection: Bool = false,
        procedureReported: CodedConcept = CodedConcept(
            codeValue: "P5-00000",
            codingSchemeDesignator: "SRT",
            codeMeaning: "Diagnostic imaging procedure"
        ),
        keyObjectSelectionPurpose: DocumentTitle = .ofInterest,
        keyObjectDescription: String? = nil
    ) {
        self.generateMeasurementReport = generateMeasurementReport
        self.generateKeyObjectSelection = generateKeyObjectSelection
        self.procedureReported = procedureReported
        self.keyObjectSelectionPurpose = keyObjectSelectionPurpose
        self.keyObjectDescription = keyObjectDescription
    }
}

// MARK: - Presentation State Configuration

/// Configuration for building a GSPS, CSPS, or Pseudo-CSPS Presentation State for a Study, Series, Image, or Frame.
public struct PresentationStateConfiguration: Sendable {
    /// Explicit Presentation State kind override. When `nil`, automatically selected from image photometric interpretation and palette:
    /// - Color image (`!photometricInterpretation.isMonochrome`) -> `.color` (CSPS `.11.2`)
    /// - Monochrome image with non-grayscale palette or custom `PaletteColorLUT` -> `.pseudoColor` (Pseudo-CSPS `.11.3`)
    /// - Monochrome image without color palette -> `.grayscale` (GSPS `.11.1`)
    public var preferredKind: PresentationStateKind?

    /// Instance Number for the Presentation State (defaults to 1).
    public var instanceNumber: Int

    /// Series Number for the Presentation State series (defaults to 900).
    public var seriesNumber: Int

    /// Series Description for the Presentation State series.
    public var seriesDescription: String?

    /// Content Label `(0070,0080)` (CS VR, max 16 uppercase/digits/space/underscore).
    public var presentationLabel: String

    /// Content Description `(0070,0081)` (LO VR).
    public var presentationDescription: String?

    /// Content Creator's Name `(0070,0084)` (PN VR).
    public var presentationCreatorsName: DICOMPersonName?

    /// Presentation Creation Date `(0070,0082)`.
    public var presentationCreationDate: DICOMDate?

    /// Presentation Creation Time `(0070,0083)`.
    public var presentationCreationTime: DICOMTime?

    /// High-level annotations to encode into `GraphicAnnotationSequence` and `GraphicLayerSequence`.
    public var annotations: [DICOMAnnotation]

    /// Additional raw `GraphicAnnotation` items to include.
    public var additionalGraphicAnnotations: [GraphicAnnotation]

    /// Additional raw `GraphicLayer` definitions to include.
    public var additionalGraphicLayers: [GraphicLayer]

    /// Global VOI LUT (window/level or LUT) for GSPS and Pseudo-CSPS.
    public var voiLUT: VOILUT?

    /// Per-image / per-frame scoped VOI LUTs (PS3.3 C.11.8) for GSPS and Pseudo-CSPS.
    public var scopedVOILUTs: [ScopedVOILUT]

    /// Modality LUT (rescale slope/intercept or LUT) for GSPS and Pseudo-CSPS.
    public var modalityLUT: ModalityLUT?

    /// Presentation LUT (`IDENTITY`, `INVERSE`, or LUT data) for GSPS.
    public var presentationLUT: PresentationLUT

    /// Preset pseudo-color palette for Pseudo-CSPS (or automatic selection of Pseudo-CSPS).
    public var palette: PseudoColorPalette?

    /// Whether the preset pseudo-color palette should be inverted.
    public var invertedPalette: Bool

    /// Custom Palette Color LUT for Pseudo-CSPS (used if `palette` is `nil`).
    public var customPaletteColorLUT: PaletteColorLUT?

    /// Optional Palette Color Lookup Table UID `(0028,1199)` for Pseudo-CSPS.
    public var paletteColorLookupTableUID: String?

    /// Optional ICC Profile for CSPS and Pseudo-CSPS (when `nil`, the standard sRGB profile is written automatically).
    public var iccProfile: ICCProfile?

    /// Optional Color Space descriptor `(0028,2002)` (defaults to `"SRGB"` for CSPS / Pseudo-CSPS).
    public var colorSpace: String?

    /// Spatial transformation (rotation and horizontal flip).
    public var spatialTransformation: SpatialTransformation?

    /// Global Displayed Area selection. When `nil` and `scopedDisplayedAreas` is empty, automatically populated from the reference image dimensions.
    public var displayedArea: DisplayedArea?

    /// Per-image / per-frame scoped Displayed Area selections (PS3.3 C.10.4).
    public var scopedDisplayedAreas: [ScopedDisplayedArea]

    /// Display shutters (`RECTANGULAR`, `CIRCULAR`, `POLYGONAL`, `BITMAP`).
    public var shutters: [DisplayShutter]

    /// CIELab color for display shutters.
    public var shutterPresentationColor: CIELabColor?

    /// Companion Structured Report options (TID 1500 Measurement Report and/or TID 2010 Key Object Selection).
    public var companionSROptions: CompanionSROptions

    public init(
        preferredKind: PresentationStateKind? = nil,
        instanceNumber: Int = 1,
        seriesNumber: Int = 900,
        seriesDescription: String? = nil,
        presentationLabel: String = "ANNOTATIONS",
        presentationDescription: String? = "Presentation State with Annotations",
        presentationCreatorsName: DICOMPersonName? = nil,
        presentationCreationDate: DICOMDate? = nil,
        presentationCreationTime: DICOMTime? = nil,
        annotations: [DICOMAnnotation] = [],
        additionalGraphicAnnotations: [GraphicAnnotation] = [],
        additionalGraphicLayers: [GraphicLayer] = [],
        voiLUT: VOILUT? = nil,
        scopedVOILUTs: [ScopedVOILUT] = [],
        modalityLUT: ModalityLUT? = nil,
        presentationLUT: PresentationLUT = .identity,
        palette: PseudoColorPalette? = nil,
        invertedPalette: Bool = false,
        customPaletteColorLUT: PaletteColorLUT? = nil,
        paletteColorLookupTableUID: String? = nil,
        iccProfile: ICCProfile? = nil,
        colorSpace: String? = nil,
        spatialTransformation: SpatialTransformation? = nil,
        displayedArea: DisplayedArea? = nil,
        scopedDisplayedAreas: [ScopedDisplayedArea] = [],
        shutters: [DisplayShutter] = [],
        shutterPresentationColor: CIELabColor? = nil,
        companionSROptions: CompanionSROptions = .none
    ) {
        self.preferredKind = preferredKind
        self.instanceNumber = instanceNumber
        self.seriesNumber = seriesNumber
        self.seriesDescription = seriesDescription
        self.presentationLabel = presentationLabel
        self.presentationDescription = presentationDescription
        self.presentationCreatorsName = presentationCreatorsName
        self.presentationCreationDate = presentationCreationDate
        self.presentationCreationTime = presentationCreationTime
        self.annotations = annotations
        self.additionalGraphicAnnotations = additionalGraphicAnnotations
        self.additionalGraphicLayers = additionalGraphicLayers
        self.voiLUT = voiLUT
        self.scopedVOILUTs = scopedVOILUTs
        self.modalityLUT = modalityLUT
        self.presentationLUT = presentationLUT
        self.palette = palette
        self.invertedPalette = invertedPalette
        self.customPaletteColorLUT = customPaletteColorLUT
        self.paletteColorLookupTableUID = paletteColorLookupTableUID
        self.iccProfile = iccProfile
        self.colorSpace = colorSpace
        self.spatialTransformation = spatialTransformation
        self.displayedArea = displayedArea
        self.scopedDisplayedAreas = scopedDisplayedAreas
        self.shutters = shutters
        self.shutterPresentationColor = shutterPresentationColor
        self.companionSROptions = companionSROptions
    }
}

// MARK: - Output Package & Loaded Models

/// Complete output package produced by `PresentationStateManager.create(...)`.
public struct PresentationStatePackage: Sendable {
    /// The typed Presentation State document (`.grayscale`, `.color`, or `.pseudoColor`).
    public let document: PresentationStateDocument

    /// Serialized DICOM Presentation State `DataSet`.
    public let prDataSet: DataSet

    /// Complete Part 10 `DICOMFile` for the Presentation State.
    public let prFile: DICOMFile

    /// High-level annotations encoded in the Presentation State.
    public let annotations: [DICOMAnnotation]

    /// Companion TID 1500 Measurement Report SR document, if requested.
    public let measurementReport: SRDocument?

    /// Serialized `DataSet` for the companion Measurement Report SR, if requested.
    public let measurementReportDataSet: DataSet?

    /// Complete Part 10 `DICOMFile` for the companion Measurement Report SR, if requested.
    public let measurementReportFile: DICOMFile?

    /// Companion TID 2010 Key Object Selection SR document, if requested.
    public let keyObjectSelection: SRDocument?

    /// Serialized `DataSet` for the companion Key Object Selection SR, if requested.
    public let keyObjectSelectionDataSet: DataSet?

    /// Complete Part 10 `DICOMFile` for the companion Key Object Selection SR, if requested.
    public let keyObjectSelectionFile: DICOMFile?

    public init(
        document: PresentationStateDocument,
        prDataSet: DataSet,
        prFile: DICOMFile,
        annotations: [DICOMAnnotation],
        measurementReport: SRDocument? = nil,
        measurementReportDataSet: DataSet? = nil,
        measurementReportFile: DICOMFile? = nil,
        keyObjectSelection: SRDocument? = nil,
        keyObjectSelectionDataSet: DataSet? = nil,
        keyObjectSelectionFile: DICOMFile? = nil
    ) {
        self.document = document
        self.prDataSet = prDataSet
        self.prFile = prFile
        self.annotations = annotations
        self.measurementReport = measurementReport
        self.measurementReportDataSet = measurementReportDataSet
        self.measurementReportFile = measurementReportFile
        self.keyObjectSelection = keyObjectSelection
        self.keyObjectSelectionDataSet = keyObjectSelectionDataSet
        self.keyObjectSelectionFile = keyObjectSelectionFile
    }
}

/// File URLs written by `PresentationStateManager.save(...)`.
public struct SavedPresentationStateFiles: Sendable, Equatable {
    /// URL of the saved Presentation State `.dcm` file.
    public let presentationStateURL: URL

    /// URL of the saved companion TID 1500 Measurement Report `.dcm` file, if generated.
    public let measurementReportURL: URL?

    /// URL of the saved companion TID 2010 Key Object Selection `.dcm` file, if generated.
    public let keyObjectSelectionURL: URL?

    public init(
        presentationStateURL: URL,
        measurementReportURL: URL? = nil,
        keyObjectSelectionURL: URL? = nil
    ) {
        self.presentationStateURL = presentationStateURL
        self.measurementReportURL = measurementReportURL
        self.keyObjectSelectionURL = keyObjectSelectionURL
    }
}

/// A parsed Presentation State along with its extracted high-level `DICOMAnnotation`s and study/series/image scoping metadata.
public struct LoadedPresentationState: Sendable {
    /// The parsed Presentation State document (`.grayscale`, `.color`, `.pseudoColor`, or `.blending`).
    public let document: PresentationStateDocument

    /// High-level annotations extracted from the Presentation State's `GraphicAnnotationSequence`.
    public let annotations: [DICOMAnnotation]

    /// Study Instance UID `(0020,000D)` from the Presentation State dataset, if present.
    public let studyInstanceUID: String?

    /// Source file URL when loaded from disk.
    public let sourceURL: URL?

    public init(
        document: PresentationStateDocument,
        annotations: [DICOMAnnotation],
        studyInstanceUID: String? = nil,
        sourceURL: URL? = nil
    ) {
        self.document = document
        self.annotations = annotations
        self.studyInstanceUID = studyInstanceUID
        self.sourceURL = sourceURL
    }

    /// All Series Instance UIDs referenced by this Presentation State.
    public var referencedSeriesInstanceUIDs: Set<String> {
        Set(document.referencedSeries.map(\.seriesInstanceUID))
    }

    /// All Image SOP Instance UIDs referenced by this Presentation State.
    public var referencedImageSOPInstanceUIDs: Set<String> {
        var uids = Set<String>()
        for series in document.referencedSeries {
            for image in series.referencedImages {
                uids.insert(image.sopInstanceUID)
            }
        }
        return uids
    }

    /// Returns `true` if this Presentation State applies to the given image SOP Instance UID and optional 1-based frame number.
    public func appliesTo(
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        sopInstanceUID: String? = nil,
        frameNumber: Int? = nil
    ) -> Bool {
        if let studyUID = studyInstanceUID,
           let docStudyUID = self.studyInstanceUID,
           !docStudyUID.isEmpty,
           docStudyUID != studyUID {
            return false
        }
        if let seriesUID = seriesInstanceUID,
           !document.referencedSeries.isEmpty,
           !referencedSeriesInstanceUIDs.contains(seriesUID) {
            return false
        }
        if let imageUID = sopInstanceUID {
            let matchingImages = document.referencedSeries
                .flatMap(\.referencedImages)
                .filter { $0.sopInstanceUID == imageUID }
            guard !matchingImages.isEmpty else { return false }
            if let frame = frameNumber {
                return matchingImages.contains { ref in
                    guard let frames = ref.referencedFrameNumbers, !frames.isEmpty else {
                        return true
                    }
                    return frames.contains(frame)
                }
            }
        }
        return true
    }

    /// Returns the high-level annotations that apply to the specified image SOP Instance UID and optional 1-based frame number.
    public func annotations(forImage sopInstanceUID: String, frameNumber: Int? = nil) -> [DICOMAnnotation] {
        annotations.filter { $0.appliesTo(sopInstanceUID: sopInstanceUID, frameNumber: frameNumber) }
    }
}

/// Collection of Presentation States and SR annotations discovered for a Study or Directory.
public struct StudyPresentationStateCollection: Sendable {
    /// All parsed Presentation States (`GSPS`, `CSPS`, `Pseudo-CSPS`, `Blending`).
    public let presentationStates: [LoadedPresentationState]

    /// All parsed Structured Report annotation sets (`TID 1500`, `Comprehensive SR`, `KOS`).
    public let srAnnotationSets: [ExtractedSRAnnotations]

    public init(
        presentationStates: [LoadedPresentationState] = [],
        srAnnotationSets: [ExtractedSRAnnotations] = []
    ) {
        self.presentationStates = presentationStates
        self.srAnnotationSets = srAnnotationSets
    }

    /// Returns all Presentation States applicable to a specific Study / Series / Image / Frame.
    public func presentationStates(
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        sopInstanceUID: String? = nil,
        frameNumber: Int? = nil
    ) -> [LoadedPresentationState] {
        presentationStates.filter {
            $0.appliesTo(
                studyInstanceUID: studyInstanceUID,
                seriesInstanceUID: seriesInstanceUID,
                sopInstanceUID: sopInstanceUID,
                frameNumber: frameNumber
            )
        }
    }

    /// Returns all combined `DICOMAnnotation`s (from both PR and SR instances) applicable to a specific image SOP Instance UID and optional 1-based frame number.
    public func allAnnotations(
        forImage sopInstanceUID: String,
        frameNumber: Int? = nil
    ) -> [DICOMAnnotation] {
        var result: [DICOMAnnotation] = []
        for state in presentationStates where state.appliesTo(sopInstanceUID: sopInstanceUID, frameNumber: frameNumber) {
            result.append(contentsOf: state.annotations(forImage: sopInstanceUID, frameNumber: frameNumber))
        }
        for srSet in srAnnotationSets {
            result.append(contentsOf: srSet.annotations.filter {
                $0.appliesTo(sopInstanceUID: sopInstanceUID, frameNumber: frameNumber)
            })
        }
        return result
    }
}

// MARK: - PresentationStateManager

/// High-level API for creating, saving, loading, and discovering GSPS, CSPS, and Pseudo-CSPS Presentation States
/// and companion Structured Reports across Studies, Series, Images, and Multi-Frame instances.
public enum PresentationStateManager {

    public enum ManagerError: Error, Sendable, Equatable {
        case emptyReferenceImages
        case missingSOPInstanceUID
        case unsupportedKind(PresentationStateKind)
    }

    // MARK: - Automatic Kind Selection

    /// Determines the appropriate DICOM Presentation State kind (`GSPS`, `CSPS`, or `Pseudo-CSPS`)
    /// for an image based on its `PhotometricInterpretation` and optional pseudo-color palette / LUT.
    ///
    /// - Parameters:
    ///   - photometricInterpretation: The image's Photometric Interpretation `(0028,0004)`.
    ///   - palette: Optional preset pseudo-color palette.
    ///   - customPaletteColorLUT: Optional custom `PaletteColorLUT`.
    /// - Returns: `.color` for color images, `.pseudoColor` for monochrome images with a color palette, or `.grayscale` for standard monochrome images.
    public static func recommendedKind(
        for photometricInterpretation: PhotometricInterpretation?,
        palette: PseudoColorPalette? = nil,
        customPaletteColorLUT: PaletteColorLUT? = nil
    ) -> PresentationStateKind {
        if let pi = photometricInterpretation, !pi.isMonochrome {
            return .color
        }
        if customPaletteColorLUT != nil {
            return .pseudoColor
        }
        if let palette, !palette.isGrayscale {
            return .pseudoColor
        }
        return .grayscale
    }

    /// String-based convenience overload for `recommendedKind`.
    public static func recommendedKind(
        forPhotometricInterpretation photometricInterpretation: String?,
        hasPseudoColorPalette: Bool = false
    ) -> PresentationStateKind {
        let trimmed = photometricInterpretation?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
            .uppercased() ?? ""
        if !trimmed.isEmpty && trimmed != "MONOCHROME1" && trimmed != "MONOCHROME2" {
            return .color
        }
        return hasPseudoColorPalette ? .pseudoColor : .grayscale
    }

    // MARK: - Create Presentation State from Explicit UIDs

    /// Creates a `PresentationStateDocument` (`GSPS`, `CSPS`, or `Pseudo-CSPS`) directly from explicit
    /// image/series UIDs without requiring an in-memory `DataSet`.
    public static func create(
        forImage sopInstanceUID: String,
        sopClassUID: String = "1.2.840.10008.5.1.4.1.1.2",
        seriesInstanceUID: String,
        frameNumbers: [Int]? = nil,
        photometricInterpretation: String? = nil,
        imageWidth: Int = 512,
        imageHeight: Int = 512,
        presentationLabel: String = "ANNOTATIONS",
        presentationDescription: String? = nil,
        creatorName: DICOMPersonName? = nil,
        voiLUT: VOILUT? = nil,
        scopedVOILUTs: [ScopedVOILUT]? = nil,
        modalityLUT: ModalityLUT? = nil,
        presentationLUT: PresentationLUT = .identity,
        palette: PseudoColorPalette? = nil,
        invertedPalette: Bool = false,
        customPaletteColorLUT: PaletteColorLUT? = nil,
        iccProfile: ICCProfile? = nil,
        spatialTransformation: SpatialTransformation? = nil,
        displayedArea: DisplayedArea? = nil,
        scopedDisplayedAreas: [ScopedDisplayedArea]? = nil,
        shutters: [DisplayShutter] = [],
        shutterPresentationColor: CIELabColor? = nil,
        annotations: [DICOMAnnotation] = []
    ) -> PresentationStateDocument {
        let hasPseudoColor = (palette != nil && palette?.isGrayscale == false) || customPaletteColorLUT != nil
        let kind = recommendedKind(
            forPhotometricInterpretation: photometricInterpretation,
            hasPseudoColorPalette: hasPseudoColor
        )
        let refImage = ReferencedImage(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            referencedFrameNumbers: (frameNumbers?.isEmpty == false) ? frameNumbers : nil
        )
        let refSeries = [ReferencedSeries(seriesInstanceUID: seriesInstanceUID, referencedImages: [refImage])]
        let effectiveArea = displayedArea ?? DisplayedArea(
            topLeft: (column: 1, row: 1),
            bottomRight: (column: max(1, imageWidth), row: max(1, imageHeight)),
            sizeMode: .scaleToFit
        )
        let graphicAnnotations = DICOMAnnotationConverter.graphicAnnotations(
            from: annotations,
            defaultReferencedImages: [refImage],
            imageWidth: max(1, imageWidth),
            imageHeight: max(1, imageHeight)
        )
        let graphicLayers = DICOMAnnotationConverter.graphicLayers(for: annotations)
        let prSOPInstanceUID = UIDGenerator.generateSOPInstanceUID().value

        switch kind {
        case .grayscale, .blending:
            return .grayscale(GrayscalePresentationState(
                sopInstanceUID: prSOPInstanceUID,
                instanceNumber: 1,
                presentationLabel: presentationLabel,
                presentationDescription: presentationDescription,
                presentationCreatorsName: creatorName,
                referencedSeries: refSeries,
                modalityLUT: modalityLUT,
                voiLUT: voiLUT,
                scopedVOILUTs: scopedVOILUTs,
                presentationLUT: presentationLUT,
                spatialTransformation: spatialTransformation,
                displayedArea: effectiveArea,
                scopedDisplayedAreas: scopedDisplayedAreas,
                graphicLayers: graphicLayers,
                graphicAnnotations: graphicAnnotations,
                shutters: shutters,
                shutterPresentationColor: shutterPresentationColor
            ))
        case .color:
            return .color(ColorPresentationState(
                sopInstanceUID: prSOPInstanceUID,
                instanceNumber: 1,
                presentationLabel: presentationLabel,
                presentationDescription: presentationDescription,
                presentationCreatorsName: creatorName,
                referencedSeries: refSeries,
                iccProfile: iccProfile,
                spatialTransformation: spatialTransformation,
                displayedArea: effectiveArea,
                scopedDisplayedAreas: scopedDisplayedAreas,
                graphicLayers: graphicLayers,
                graphicAnnotations: graphicAnnotations,
                shutters: shutters,
                shutterPresentationColor: shutterPresentationColor
            ))
        case .pseudoColor:
            let lut = customPaletteColorLUT ?? (palette ?? .hotIron).paletteColorLUT(inverted: invertedPalette)
            return .pseudoColor(PseudoColorPresentationState(
                sopInstanceUID: prSOPInstanceUID,
                instanceNumber: 1,
                presentationLabel: presentationLabel,
                presentationDescription: presentationDescription,
                presentationCreatorsName: creatorName,
                referencedSeries: refSeries,
                modalityLUT: modalityLUT,
                voiLUT: voiLUT,
                scopedVOILUTs: scopedVOILUTs,
                paletteColorLUT: lut,
                palette: palette,
                iccProfile: iccProfile,
                spatialTransformation: spatialTransformation,
                displayedArea: effectiveArea,
                scopedDisplayedAreas: scopedDisplayedAreas,
                graphicLayers: graphicLayers,
                graphicAnnotations: graphicAnnotations,
                shutters: shutters,
                shutterPresentationColor: shutterPresentationColor
            ))
        }
    }

    // MARK: - Create Presentation State for Image / Frame / Series / Study

    /// Creates a Presentation State (`GSPS`, `CSPS`, or `Pseudo-CSPS`) and optional companion SR documents
    /// for a single image `DataSet` (optionally scoped to specific 1-based `frameNumbers`).
    public static func create(
        forImage imageDataSet: DataSet,
        frameNumbers: [Int]? = nil,
        configuration: PresentationStateConfiguration = PresentationStateConfiguration()
    ) throws -> PresentationStatePackage {
        let framesMap: [String: [Int]]
        if let frameNumbers, !frameNumbers.isEmpty,
           let sopUID = imageDataSet.string(for: .sopInstanceUID)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            framesMap = [sopUID: frameNumbers]
        } else {
            framesMap = [:]
        }
        return try create(
            forImages: [imageDataSet],
            referencedFramesBySOPInstanceUID: framesMap,
            configuration: configuration
        )
    }

    /// Creates a Presentation State (`GSPS`, `CSPS`, or `Pseudo-CSPS`) and optional companion SR documents
    /// for one or more image `DataSet`s belonging to a Series or Study (supporting multi-series Study-wide PR).
    ///
    /// - Parameters:
    ///   - imageDataSets: One or more reference image `DataSet`s in the study/series.
    ///   - referencedFramesBySOPInstanceUID: Optional map of Image SOP Instance UID -> 1-based frame numbers.
    ///   - configuration: Presentation State configuration (annotations, VOI LUT, palette, displayed area, companion SR options).
    /// - Returns: A `PresentationStatePackage` containing the `PresentationStateDocument`, `DataSet`, `DICOMFile`, and optional companion SR documents.
    public static func create(
        forImages imageDataSets: [DataSet],
        referencedFramesBySOPInstanceUID: [String: [Int]] = [:],
        configuration: PresentationStateConfiguration = PresentationStateConfiguration()
    ) throws -> PresentationStatePackage {
        guard let primaryDataSet = imageDataSets.first else {
            throw ManagerError.emptyReferenceImages
        }

        // 1. Group images by Series Instance UID into [ReferencedSeries]
        var seriesOrder: [String] = []
        var imagesBySeries: [String: [ReferencedImage]] = [:]
        let defaultSeriesUID = primaryDataSet.string(for: .seriesInstanceUID)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? UIDGenerator.generateSeriesInstanceUID().value

        for ds in imageDataSets {
            guard let sopInstanceUID = ds.string(for: .sopInstanceUID)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sopInstanceUID.isEmpty else {
                throw ManagerError.missingSOPInstanceUID
            }
            let sopClassUID = ds.string(for: .sopClassUID)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "1.2.840.10008.5.1.4.1.1.2"
            let seriesUID = ds.string(for: .seriesInstanceUID)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? defaultSeriesUID
            let frames = referencedFramesBySOPInstanceUID[sopInstanceUID]

            let refImage = ReferencedImage(
                sopClassUID: sopClassUID,
                sopInstanceUID: sopInstanceUID,
                referencedFrameNumbers: frames
            )
            if imagesBySeries[seriesUID] == nil {
                seriesOrder.append(seriesUID)
                imagesBySeries[seriesUID] = []
            }
            if !(imagesBySeries[seriesUID]?.contains(refImage) ?? false) {
                imagesBySeries[seriesUID]?.append(refImage)
            }
        }

        let referencedSeries: [ReferencedSeries] = seriesOrder.compactMap { uid in
            guard let imgs = imagesBySeries[uid], !imgs.isEmpty else { return nil }
            return ReferencedSeries(seriesInstanceUID: uid, referencedImages: imgs)
        }

        // 2. Determine Presentation State Kind
        let photometric = primaryDataSet.string(for: .photometricInterpretation)
            .flatMap { PhotometricInterpretation(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let kind = configuration.preferredKind ?? recommendedKind(
            for: photometric,
            palette: configuration.palette,
            customPaletteColorLUT: configuration.customPaletteColorLUT
        )

        // 3. Determine default DisplayedArea from primary image dimensions if not explicitly supplied
        let cols = max(1, Int(primaryDataSet.uint16(for: .columns) ?? 512))
        let rows = max(1, Int(primaryDataSet.uint16(for: .rows) ?? 512))
        let effectiveDisplayedArea: DisplayedArea = configuration.displayedArea
            ?? configuration.scopedDisplayedAreas.first?.displayedArea
            ?? DisplayedArea(
                topLeft: (column: 1, row: 1),
                bottomRight: (column: cols, row: rows),
                sizeMode: .scaleToFit
            )

        // 4. Convert high-level DICOMAnnotations into GraphicAnnotationSequence & GraphicLayerSequence
        let allReferredImages = referencedSeries.flatMap(\.referencedImages)
        let convertedAnnotations = DICOMAnnotationConverter.graphicAnnotations(
            from: configuration.annotations,
            defaultReferencedImages: allReferredImages,
            imageWidth: cols,
            imageHeight: rows
        )
        let convertedLayers = DICOMAnnotationConverter.graphicLayers(for: configuration.annotations)
        let combinedGraphicAnnotations = convertedAnnotations + configuration.additionalGraphicAnnotations
        var combinedLayers: [GraphicLayer] = convertedLayers
        let existingLayerNames = Set(combinedLayers.map { $0.name })
        for extraLayer in configuration.additionalGraphicLayers where !existingLayerNames.contains(extraLayer.name) {
            combinedLayers.append(extraLayer)
        }

        // 5. Generate Presentation State SOP Instance UID & Document
        let prSOPInstanceUID = UIDGenerator.generateSOPInstanceUID().value
        let document: PresentationStateDocument

        switch kind {
        case .grayscale:
            let gsps = GrayscalePresentationState(
                sopInstanceUID: prSOPInstanceUID,
                sopClassUID: .grayscaleSoftcopyPresentationStateStorage,
                instanceNumber: configuration.instanceNumber,
                presentationLabel: configuration.presentationLabel,
                presentationDescription: configuration.presentationDescription,
                presentationCreationDate: configuration.presentationCreationDate,
                presentationCreationTime: configuration.presentationCreationTime,
                presentationCreatorsName: configuration.presentationCreatorsName,
                referencedSeries: referencedSeries,
                modalityLUT: configuration.modalityLUT,
                voiLUT: configuration.voiLUT,
                scopedVOILUTs: configuration.scopedVOILUTs.isEmpty ? nil : configuration.scopedVOILUTs,
                presentationLUT: configuration.presentationLUT,
                spatialTransformation: configuration.spatialTransformation,
                displayedArea: effectiveDisplayedArea,
                scopedDisplayedAreas: configuration.scopedDisplayedAreas.isEmpty ? nil : configuration.scopedDisplayedAreas,
                graphicLayers: combinedLayers,
                graphicAnnotations: combinedGraphicAnnotations,
                shutters: configuration.shutters,
                shutterPresentationColor: configuration.shutterPresentationColor
            )
            document = .grayscale(gsps)

        case .color:
            let csps = ColorPresentationState(
                sopInstanceUID: prSOPInstanceUID,
                instanceNumber: configuration.instanceNumber,
                presentationLabel: configuration.presentationLabel,
                presentationDescription: configuration.presentationDescription,
                presentationCreationDate: configuration.presentationCreationDate,
                presentationCreationTime: configuration.presentationCreationTime,
                presentationCreatorsName: configuration.presentationCreatorsName,
                referencedSeries: referencedSeries,
                iccProfile: configuration.iccProfile,
                colorSpace: configuration.colorSpace ?? "SRGB",
                spatialTransformation: configuration.spatialTransformation,
                displayedArea: effectiveDisplayedArea,
                scopedDisplayedAreas: configuration.scopedDisplayedAreas.isEmpty ? nil : configuration.scopedDisplayedAreas,
                graphicLayers: combinedLayers,
                graphicAnnotations: combinedGraphicAnnotations,
                shutters: configuration.shutters,
                shutterPresentationColor: configuration.shutterPresentationColor
            )
            document = .color(csps)

        case .pseudoColor:
            let lut: PaletteColorLUT
            if let customLUT = configuration.customPaletteColorLUT {
                lut = customLUT
            } else {
                let chosenPalette = configuration.palette ?? .hotIron
                lut = chosenPalette.paletteColorLUT(inverted: configuration.invertedPalette)
            }
            let pcsps = PseudoColorPresentationState(
                sopInstanceUID: prSOPInstanceUID,
                instanceNumber: configuration.instanceNumber,
                presentationLabel: configuration.presentationLabel,
                presentationDescription: configuration.presentationDescription,
                presentationCreationDate: configuration.presentationCreationDate,
                presentationCreationTime: configuration.presentationCreationTime,
                presentationCreatorsName: configuration.presentationCreatorsName,
                referencedSeries: referencedSeries,
                modalityLUT: configuration.modalityLUT,
                voiLUT: configuration.voiLUT,
                scopedVOILUTs: configuration.scopedVOILUTs.isEmpty ? nil : configuration.scopedVOILUTs,
                paletteColorLUT: lut,
                palette: configuration.palette,
                paletteColorLookupTableUID: configuration.paletteColorLookupTableUID ?? (configuration.invertedPalette ? nil : configuration.palette?.wellKnownSOPInstanceUID),
                iccProfile: configuration.iccProfile,
                colorSpace: configuration.colorSpace ?? "SRGB",
                spatialTransformation: configuration.spatialTransformation,
                displayedArea: effectiveDisplayedArea,
                scopedDisplayedAreas: configuration.scopedDisplayedAreas.isEmpty ? nil : configuration.scopedDisplayedAreas,
                graphicLayers: combinedLayers,
                graphicAnnotations: combinedGraphicAnnotations,
                shutters: configuration.shutters,
                shutterPresentationColor: configuration.shutterPresentationColor
            )
            document = .pseudoColor(pcsps)

        case .blending:
            let underlaySeries = referencedSeries.first.map { [$0] } ?? []
            let overlaySeries = referencedSeries.count > 1 ? Array(referencedSeries.dropFirst()) : underlaySeries
            let chosenPalette = configuration.palette ?? .hotIron
            let lut = configuration.customPaletteColorLUT ?? chosenPalette.paletteColorLUT(inverted: configuration.invertedPalette)
            let blending = BlendingPresentationState(
                sopInstanceUID: prSOPInstanceUID,
                instanceNumber: configuration.instanceNumber,
                presentationLabel: configuration.presentationLabel,
                presentationDescription: configuration.presentationDescription,
                presentationCreationDate: configuration.presentationCreationDate,
                presentationCreationTime: configuration.presentationCreationTime,
                presentationCreatorsName: configuration.presentationCreatorsName,
                referencedSeries: referencedSeries,
                underlaySeries: underlaySeries,
                overlaySeries: overlaySeries,
                underlayModalityLUT: configuration.modalityLUT,
                overlayModalityLUT: configuration.modalityLUT,
                underlayVOILUT: configuration.voiLUT,
                overlayVOILUT: configuration.scopedVOILUTs.first?.voiLUT ?? configuration.voiLUT,
                relativeOpacity: 0.5,
                paletteColorLUT: lut,
                palette: configuration.palette ?? .hotIron,
                iccProfile: configuration.iccProfile,
                colorSpace: configuration.colorSpace ?? "SRGB",
                spatialTransformation: configuration.spatialTransformation,
                displayedArea: effectiveDisplayedArea,
                scopedDisplayedAreas: configuration.scopedDisplayedAreas.isEmpty ? nil : configuration.scopedDisplayedAreas,
                graphicLayers: combinedLayers,
                graphicAnnotations: combinedGraphicAnnotations,
                shutters: configuration.shutters,
                shutterPresentationColor: configuration.shutterPresentationColor
            )
            document = .blending(blending)
        }

        // 6. Build Presentation State DataSet & Part 10 DICOMFile
        let prSeriesUID = UIDGenerator.generateSeriesInstanceUID().value
        let defaultSeriesDesc: String
        switch kind {
        case .grayscale: defaultSeriesDesc = "Grayscale Softcopy Presentation State"
        case .color: defaultSeriesDesc = "Color Softcopy Presentation State"
        case .pseudoColor: defaultSeriesDesc = "Pseudo-Color Softcopy Presentation State"
        case .blending: defaultSeriesDesc = "Blending Softcopy Presentation State"
        }

        var patientContext = PresentationStatePatientContext.make(from: primaryDataSet)
        if patientContext.studyInstanceUID.isEmpty {
            patientContext.studyInstanceUID = UIDGenerator.generateStudyInstanceUID().value
        }
        patientContext.seriesDescription = configuration.seriesDescription ?? defaultSeriesDesc

        let pixelDomain: PseudoColorPresentationStateBuilder.PixelDomain?
        if let bitsStored = primaryDataSet.uint16(for: .bitsStored),
           let pixelRep = primaryDataSet.uint16(for: .pixelRepresentation) {
            pixelDomain = PseudoColorPresentationStateBuilder.PixelDomain(
                bitsStored: Int(bitsStored),
                isSigned: pixelRep != 0
            )
        } else {
            pixelDomain = nil
        }

        let prDataSet = PresentationStateBuilder().buildDataSet(
            from: document,
            pixelDomain: pixelDomain,
            patient: patientContext,
            seriesInstanceUID: prSeriesUID,
            seriesNumber: configuration.seriesNumber,
            imageSize: (columns: cols, rows: rows)
        )
        let prFile = DICOMFile.create(
            dataSet: prDataSet,
            sopClassUID: document.sopClassUID,
            sopInstanceUID: document.sopInstanceUID
        )

        // 7. Build optional Companion Structured Reports (TID 1500 Measurement Report / TID 2010 KOS)
        var measurementReport: SRDocument? = nil
        var measurementReportDataSet: DataSet? = nil
        var measurementReportFile: DICOMFile? = nil

        if configuration.companionSROptions.generateMeasurementReport {
            let srDoc = try PresentationStateSRBridge.buildMeasurementReport(
                from: document,
                annotations: configuration.annotations,
                patient: patientContext,
                imageWidth: cols,
                imageHeight: rows,
                seriesNumber: configuration.seriesNumber + 1,
                procedureReported: configuration.companionSROptions.procedureReported
            )
            let srDataSet = try SRDocumentSerializer().serialize(document: srDoc)
            let srFile = DICOMFile.create(
                dataSet: srDataSet,
                sopClassUID: srDoc.sopClassUID,
                sopInstanceUID: srDoc.sopInstanceUID
            )
            measurementReport = srDoc
            measurementReportDataSet = srFile.dataSet
            measurementReportFile = srFile
        }

        var keyObjectSelection: SRDocument? = nil
        var keyObjectSelectionDataSet: DataSet? = nil
        var keyObjectSelectionFile: DICOMFile? = nil

        if configuration.companionSROptions.generateKeyObjectSelection {
            let kosDoc = try PresentationStateSRBridge.buildKeyObjectSelection(
                from: document,
                patient: patientContext,
                purpose: configuration.companionSROptions.keyObjectSelectionPurpose,
                description: configuration.companionSROptions.keyObjectDescription,
                seriesNumber: configuration.seriesNumber + 2
            )
            let kosDataSet = try SRDocumentSerializer().serialize(document: kosDoc)
            let kosFile = DICOMFile.create(
                dataSet: kosDataSet,
                sopClassUID: kosDoc.sopClassUID,
                sopInstanceUID: kosDoc.sopInstanceUID
            )
            keyObjectSelection = kosDoc
            keyObjectSelectionDataSet = kosFile.dataSet
            keyObjectSelectionFile = kosFile
        }

        return PresentationStatePackage(
            document: document,
            prDataSet: prFile.dataSet,
            prFile: prFile,
            annotations: configuration.annotations,
            measurementReport: measurementReport,
            measurementReportDataSet: measurementReportDataSet,
            measurementReportFile: measurementReportFile,
            keyObjectSelection: keyObjectSelection,
            keyObjectSelectionDataSet: keyObjectSelectionDataSet,
            keyObjectSelectionFile: keyObjectSelectionFile
        )
    }

    // MARK: - Save Presentation State Package to Disk

    /// Writes a `PresentationStatePackage` (PR `.dcm` file and any companion SR / KOS `.dcm` files) to disk.
    ///
    /// - Parameters:
    ///   - package: The `PresentationStatePackage` created by `PresentationStateManager.create(...)`.
    ///   - directoryURL: Target directory URL (created automatically if it does not exist).
    ///   - filePrefix: Filename prefix (defaults to `"PR"`).
    /// - Returns: `SavedPresentationStateFiles` containing the written file URLs.
    @discardableResult
    public static func save(
        _ package: PresentationStatePackage,
        to directoryURL: URL,
        filePrefix: String = "PR"
    ) throws -> SavedPresentationStateFiles {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let prFilename = "\(filePrefix)_\(package.document.sopInstanceUID).dcm"
        let prURL = directoryURL.appendingPathComponent(prFilename)
        let prBytes = try package.prFile.write()
        try prBytes.write(to: prURL, options: .atomic)

        var srURL: URL? = nil
        if let srFile = package.measurementReportFile, let srDoc = package.measurementReport {
            let srFilename = "SR_\(srDoc.sopInstanceUID).dcm"
            let url = directoryURL.appendingPathComponent(srFilename)
            let srBytes = try srFile.write()
            try srBytes.write(to: url, options: .atomic)
            srURL = url
        }

        var kosURL: URL? = nil
        if let kosFile = package.keyObjectSelectionFile, let kosDoc = package.keyObjectSelection {
            let kosFilename = "KO_\(kosDoc.sopInstanceUID).dcm"
            let url = directoryURL.appendingPathComponent(kosFilename)
            let kosBytes = try kosFile.write()
            try kosBytes.write(to: url, options: .atomic)
            kosURL = url
        }

        return SavedPresentationStateFiles(
            presentationStateURL: prURL,
            measurementReportURL: srURL,
            keyObjectSelectionURL: kosURL
        )
    }

    // MARK: - Parse / Load Presentation State

    /// Parses a `LoadedPresentationState` (including its `PresentationStateDocument` and high-level `[DICOMAnnotation]`s)
    /// from a DICOM `DataSet`.
    public static func load(
        from dataSet: DataSet,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        targetCoordinateSpace: DICOMAnnotationCoordinateSpace = .pixel,
        sourceURL: URL? = nil
    ) throws -> LoadedPresentationState {
        let document = try PresentationStateParser(allowScopedVOILUT: true).parse(dataSet: dataSet)
        let resolvedWidth = imageWidth
            ?? document.displayedArea.map { max(1, $0.bottomRight.column - $0.topLeft.column + 1) }
            ?? 512
        let resolvedHeight = imageHeight
            ?? document.displayedArea.map { max(1, $0.bottomRight.row - $0.topLeft.row + 1) }
            ?? 512
        let annotations = DICOMAnnotationConverter.annotations(
            from: document,
            imageWidth: resolvedWidth,
            imageHeight: resolvedHeight,
            targetCoordinateSpace: targetCoordinateSpace
        )
        let studyUID = dataSet.string(for: .studyInstanceUID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LoadedPresentationState(
            document: document,
            annotations: annotations,
            studyInstanceUID: studyUID,
            sourceURL: sourceURL
        )
    }

    /// Reads and parses a `LoadedPresentationState` from a DICOM file on disk.
    public static func load(
        from fileURL: URL,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        targetCoordinateSpace: DICOMAnnotationCoordinateSpace = .pixel
    ) throws -> LoadedPresentationState {
        let dicomFile = try DICOMFile.read(from: fileURL, force: true)
        return try load(
            from: dicomFile.dataSet,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            targetCoordinateSpace: targetCoordinateSpace,
            sourceURL: fileURL
        )
    }

    // MARK: - Study / Series Discovery (In-Memory & Disk)

    /// Discovers and parses all Presentation States (`GSPS`, `CSPS`, `Pseudo-CSPS`, `Blending`) and
    /// Structured Report annotation documents (`TID 1500`, `Comprehensive SR`, `KOS`) from an array of `DataSet`s.
    public static func discover(
        in dataSets: [DataSet],
        imageWidth: Int = 512,
        imageHeight: Int = 512,
        targetCoordinateSpace: DICOMAnnotationCoordinateSpace = .pixel
    ) -> StudyPresentationStateCollection {
        var states: [LoadedPresentationState] = []
        var srSets: [ExtractedSRAnnotations] = []

        for dataSet in dataSets {
            let sopClassUID = dataSet.string(for: .sopClassUID)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let modality = dataSet.string(for: .modality)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if PresentationStateKind(sopClassUID: sopClassUID) != nil || modality == "PR" {
                if let loaded = try? load(
                    from: dataSet,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight,
                    targetCoordinateSpace: targetCoordinateSpace
                ) {
                    states.append(loaded)
                }
            } else if modality == "SR" || modality == "KO" || sopClassUID.hasPrefix("1.2.840.10008.5.1.4.1.1.88.") {
                if let srDoc = try? SRDocumentParser().parse(dataSet: dataSet) {
                    let extracted = PresentationStateSRBridge.extract(
                        from: srDoc,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight,
                        targetCoordinateSpace: targetCoordinateSpace
                    )
                    if !extracted.annotations.isEmpty || !extracted.presentationStateReferences.isEmpty {
                        srSets.append(extracted)
                    }
                }
            }
        }

        return StudyPresentationStateCollection(
            presentationStates: states,
            srAnnotationSets: srSets
        )
    }

    /// Scans a directory on disk (optionally recursively) and discovers all Presentation States and SR annotation files.
    public static func discover(
        in directoryURL: URL,
        recursive: Bool = true,
        imageWidth: Int = 512,
        imageHeight: Int = 512,
        targetCoordinateSpace: DICOMAnnotationCoordinateSpace = .pixel
    ) throws -> StudyPresentationStateCollection {
        var states: [LoadedPresentationState] = []
        var srSets: [ExtractedSRAnnotations] = []

        let options: FileManager.DirectoryEnumerationOptions = recursive
            ? [.skipsHiddenFiles]
            : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]

        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: options
        ) else {
            return StudyPresentationStateCollection()
        }

        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            guard let dicomFile = try? DICOMFile.read(from: fileURL, force: true, options: .metadataOnly) else {
                continue
            }
            let dataSet = dicomFile.dataSet
            let sopClassUID = dataSet.string(for: .sopClassUID)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let modality = dataSet.string(for: .modality)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if PresentationStateKind(sopClassUID: sopClassUID) != nil || modality == "PR" {
                if let fullFile = try? DICOMFile.read(from: fileURL, force: true),
                   let loaded = try? load(
                       from: fullFile.dataSet,
                       imageWidth: imageWidth,
                       imageHeight: imageHeight,
                       targetCoordinateSpace: targetCoordinateSpace,
                       sourceURL: fileURL
                   ) {
                    states.append(loaded)
                }
            } else if modality == "SR" || modality == "KO" || sopClassUID.hasPrefix("1.2.840.10008.5.1.4.1.1.88.") {
                if let fullFile = try? DICOMFile.read(from: fileURL, force: true),
                   let srDoc = try? SRDocumentParser().parse(dataSet: fullFile.dataSet) {
                    let extracted = PresentationStateSRBridge.extract(
                        from: srDoc,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight,
                        targetCoordinateSpace: targetCoordinateSpace
                    )
                    if !extracted.annotations.isEmpty || !extracted.presentationStateReferences.isEmpty {
                        srSets.append(extracted)
                    }
                }
            }
        }

        return StudyPresentationStateCollection(
            presentationStates: states,
            srAnnotationSets: srSets
        )
    }
}
