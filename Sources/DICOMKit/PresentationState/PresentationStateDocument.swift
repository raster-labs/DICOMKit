// NEMA-verified: 2026a, checked 2026-11-16 — PS3.3 2026a A.33.1 (GSPS 1.2.840.10008.5.1.4.1.1.11.1), A.33.2 (CSPS 1.2.840.10008.5.1.4.1.1.11.2), A.33.3 (Pseudo-CSPS 1.2.840.10008.5.1.4.1.1.11.3), and A.33.4 (Blending Softcopy PS 1.2.840.10008.5.1.4.1.1.11.4), plus C.7.9 Palette Color LUT, C.10.4 Displayed Area, C.11.8 Softcopy VOI LUT, C.11.15 ICC Profile, and Table C.18.4-1 Image Reference
//
// PresentationStateDocument.swift
// DICOMKit
//
// Unified Presentation State document, parser, and builder API for
// Grayscale (GSPS), Color (CSPS), Pseudo-Color (Pseudo-CSPS), and Blending
// Softcopy Presentation States (DICOM PS3.3 A.33.1–A.33.4).
//

import Foundation
import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Kind of Softcopy Presentation State IOD (PS3.3 Section A.33).
public enum PresentationStateKind: String, Sendable, Hashable, CaseIterable, Codable {
    /// Grayscale Softcopy Presentation State (`1.2.840.10008.5.1.4.1.1.11.1`, PS3.3 A.33.1)
    case grayscale = "1.2.840.10008.5.1.4.1.1.11.1"
    /// Color Softcopy Presentation State (`1.2.840.10008.5.1.4.1.1.11.2`, PS3.3 A.33.2)
    case color = "1.2.840.10008.5.1.4.1.1.11.2"
    /// Pseudo-Color Softcopy Presentation State (`1.2.840.10008.5.1.4.1.1.11.3`, PS3.3 A.33.3)
    case pseudoColor = "1.2.840.10008.5.1.4.1.1.11.3"
    /// Blending Softcopy Presentation State (`1.2.840.10008.5.1.4.1.1.11.4`, PS3.3 A.33.4)
    case blending = "1.2.840.10008.5.1.4.1.1.11.4"

    /// SOP Class UID for this presentation state kind.
    public var sopClassUID: String { rawValue }

    /// Initializes from a SOP Class UID string.
    public init?(sopClassUID: String) {
        self.init(rawValue: sopClassUID.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")))
    }
}

/// Unified sum type representing any parsed or constructed DICOM Softcopy Presentation State.
///
/// Reference: DICOM PS3.3 Section A.33.1 (GSPS), A.33.2 (CSPS), A.33.3 (Pseudo-CSPS), A.33.4 (Blending).
public enum PresentationStateDocument: PresentationState, Sendable {
    /// Grayscale Softcopy Presentation State (`1.2.840.10008.5.1.4.1.1.11.1`)
    case grayscale(GrayscalePresentationState)
    /// Color Softcopy Presentation State (`1.2.840.10008.5.1.4.1.1.11.2`)
    case color(ColorPresentationState)
    /// Pseudo-Color Softcopy Presentation State (`1.2.840.10008.5.1.4.1.1.11.3`)
    case pseudoColor(PseudoColorPresentationState)
    /// Blending Softcopy Presentation State (`1.2.840.10008.5.1.4.1.1.11.4`)
    case blending(BlendingPresentationState)

    /// The kind of presentation state IOD.
    public var kind: PresentationStateKind {
        switch self {
        case .grayscale: return .grayscale
        case .color: return .color
        case .pseudoColor: return .pseudoColor
        case .blending: return .blending
        }
    }

    /// `ReferencedSOP` suitable for attaching this presentation state to an SR `ImageReference`
    /// (`ReferencedSOPSequence (0008,1199)` in PS3.3 Table C.18.4-1) or `CompositeContentItem`.
    public var referencedSOP: ReferencedSOP {
        ReferencedSOP(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID)
    }

    // MARK: - PresentationState Protocol Conformance

    public var sopInstanceUID: String {
        switch self {
        case .grayscale(let s): return s.sopInstanceUID
        case .color(let s): return s.sopInstanceUID
        case .pseudoColor(let s): return s.sopInstanceUID
        case .blending(let s): return s.sopInstanceUID
        }
    }

    public var sopClassUID: String {
        switch self {
        case .grayscale(let s): return s.sopClassUID
        case .color(let s): return s.sopClassUID
        case .pseudoColor(let s): return s.sopClassUID
        case .blending(let s): return s.sopClassUID
        }
    }

    public var instanceNumber: Int? {
        switch self {
        case .grayscale(let s): return s.instanceNumber
        case .color(let s): return s.instanceNumber
        case .pseudoColor(let s): return s.instanceNumber
        case .blending(let s): return s.instanceNumber
        }
    }

    public var presentationLabel: String? {
        switch self {
        case .grayscale(let s): return s.presentationLabel
        case .color(let s): return s.presentationLabel
        case .pseudoColor(let s): return s.presentationLabel
        case .blending(let s): return s.presentationLabel
        }
    }

    public var presentationDescription: String? {
        switch self {
        case .grayscale(let s): return s.presentationDescription
        case .color(let s): return s.presentationDescription
        case .pseudoColor(let s): return s.presentationDescription
        case .blending(let s): return s.presentationDescription
        }
    }

    public var presentationCreationDate: DICOMDate? {
        switch self {
        case .grayscale(let s): return s.presentationCreationDate
        case .color(let s): return s.presentationCreationDate
        case .pseudoColor(let s): return s.presentationCreationDate
        case .blending(let s): return s.presentationCreationDate
        }
    }

    public var presentationCreationTime: DICOMTime? {
        switch self {
        case .grayscale(let s): return s.presentationCreationTime
        case .color(let s): return s.presentationCreationTime
        case .pseudoColor(let s): return s.presentationCreationTime
        case .blending(let s): return s.presentationCreationTime
        }
    }

    public var presentationCreatorsName: DICOMPersonName? {
        switch self {
        case .grayscale(let s): return s.presentationCreatorsName
        case .color(let s): return s.presentationCreatorsName
        case .pseudoColor(let s): return s.presentationCreatorsName
        case .blending(let s): return s.presentationCreatorsName
        }
    }

    public var referencedSeries: [ReferencedSeries] {
        switch self {
        case .grayscale(let s): return s.referencedSeries
        case .color(let s): return s.referencedSeries
        case .pseudoColor(let s): return s.referencedSeries
        case .blending(let s): return s.referencedSeries
        }
    }

    // MARK: - Common Module Accessors

    public var spatialTransformation: SpatialTransformation? {
        switch self {
        case .grayscale(let s): return s.spatialTransformation
        case .color(let s): return s.spatialTransformation
        case .pseudoColor(let s): return s.spatialTransformation
        case .blending(let s): return s.spatialTransformation
        }
    }

    public var displayedArea: DisplayedArea? {
        switch self {
        case .grayscale(let s): return s.displayedArea
        case .color(let s): return s.displayedArea
        case .pseudoColor(let s): return s.displayedArea
        case .blending(let s): return s.displayedArea
        }
    }

    public var scopedDisplayedAreas: [ScopedDisplayedArea] {
        switch self {
        case .grayscale(let s): return s.scopedDisplayedAreas
        case .color(let s): return s.scopedDisplayedAreas
        case .pseudoColor(let s): return s.scopedDisplayedAreas
        case .blending(let s): return s.scopedDisplayedAreas
        }
    }

    public var modalityLUT: ModalityLUT? {
        switch self {
        case .grayscale(let s): return s.modalityLUT
        case .pseudoColor(let s): return s.modalityLUT
        case .blending(let s): return s.underlayModalityLUT
        case .color: return nil
        }
    }

    public var graphicLayers: [GraphicLayer] {
        switch self {
        case .grayscale(let s): return s.graphicLayers
        case .color(let s): return s.graphicLayers
        case .pseudoColor(let s): return s.graphicLayers
        case .blending(let s): return s.graphicLayers
        }
    }

    public var graphicAnnotations: [GraphicAnnotation] {
        switch self {
        case .grayscale(let s): return s.graphicAnnotations
        case .color(let s): return s.graphicAnnotations
        case .pseudoColor(let s): return s.graphicAnnotations
        case .blending(let s): return s.graphicAnnotations
        }
    }

    public var shutters: [DisplayShutter] {
        switch self {
        case .grayscale(let s): return s.shutters
        case .color(let s): return s.shutters
        case .pseudoColor(let s): return s.shutters
        case .blending(let s): return s.shutters
        }
    }

    public var shutterPresentationColor: CIELabColor? {
        switch self {
        case .grayscale(let s): return s.shutterPresentationColor
        case .color(let s): return s.shutterPresentationColor
        case .pseudoColor(let s): return s.shutterPresentationColor
        case .blending(let s): return s.shutterPresentationColor
        }
    }

    /// Resolves the effective VOI LUT for a given image and optional 1-based frame number (GSPS, Pseudo-CSPS, and Blending).
    public func effectiveVOILUT(forImage sopInstanceUID: String? = nil, frameNumber: Int? = nil) -> VOILUT? {
        switch self {
        case .grayscale(let s):
            return s.effectiveVOILUT(forImage: sopInstanceUID, frameNumber: frameNumber)
        case .pseudoColor(let s):
            return s.effectiveVOILUT(forImage: sopInstanceUID, frameNumber: frameNumber)
        case .blending(let s):
            if let sopInstanceUID,
               s.overlaySeries.contains(where: { $0.referencedImages.contains(where: { $0.sopInstanceUID == sopInstanceUID }) }) {
                return s.overlayVOILUT
            }
            return s.underlayVOILUT
        case .color:
            return nil
        }
    }

    /// Resolves the effective Displayed Area for a given image and optional 1-based frame number.
    public func effectiveDisplayedArea(forImage sopInstanceUID: String? = nil, frameNumber: Int? = nil) -> DisplayedArea? {
        switch self {
        case .grayscale(let s):
            return s.effectiveDisplayedArea(forImage: sopInstanceUID, frameNumber: frameNumber)
        case .color(let s):
            return s.effectiveDisplayedArea(forImage: sopInstanceUID, frameNumber: frameNumber)
        case .pseudoColor(let s):
            return s.effectiveDisplayedArea(forImage: sopInstanceUID, frameNumber: frameNumber)
        case .blending(let s):
            return s.effectiveDisplayedArea(forImage: sopInstanceUID, frameNumber: frameNumber)
        }
    }

    /// Projects this document as a `GrayscalePresentationState` for shared spatial/annotation operations.
    public var asGrayscaleModel: GrayscalePresentationState {
        switch self {
        case .grayscale(let s):
            return s
        case .color(let s):
            return ColorPresentationStateBuilder.grayscaleModel(of: s)
        case .pseudoColor(let s):
            return PseudoColorPresentationStateBuilder.grayscaleModel(of: s)
        case .blending(let s):
            return GrayscalePresentationState(
                sopInstanceUID: s.sopInstanceUID,
                sopClassUID: s.sopClassUID,
                instanceNumber: s.instanceNumber,
                presentationLabel: s.presentationLabel,
                presentationDescription: s.presentationDescription,
                presentationCreationDate: s.presentationCreationDate,
                presentationCreationTime: s.presentationCreationTime,
                presentationCreatorsName: s.presentationCreatorsName,
                referencedSeries: s.referencedSeries,
                spatialTransformation: s.spatialTransformation,
                displayedArea: s.displayedArea,
                graphicLayers: s.graphicLayers,
                graphicAnnotations: s.graphicAnnotations,
                shutters: s.shutters,
                shutterPresentationColor: s.shutterPresentationColor
            )
        }
    }
}

// MARK: - Unified Presentation State Parser

/// Unified parser for Grayscale (GSPS), Color (CSPS), and Pseudo-Color (Pseudo-CSPS)
/// Softcopy Presentation State datasets and files.
public struct PresentationStateParser: Sendable {
    /// Whether to allow multi-item and per-image/per-frame scoped Softcopy VOI LUT Sequence items.
    public let allowScopedVOILUT: Bool

    public init(allowScopedVOILUT: Bool = true) {
        self.allowScopedVOILUT = allowScopedVOILUT
    }

    /// Parses a DICOM `DataSet` into a typed `PresentationStateDocument` (`.grayscale`, `.color`, or `.pseudoColor`).
    public func parse(dataSet: DataSet) throws -> PresentationStateDocument {
        let baseParser = GrayscalePresentationStateParser(allowScopedVOILUT: allowScopedVOILUT)
        let baseState = try baseParser.parse(dataSet: dataSet)

        switch baseState.sopClassUID {
        case .grayscaleSoftcopyPresentationStateStorage:
            return .grayscale(baseState)

        case .colorSoftcopyPresentationStateStorage:
            let iccProfile = ICCProfile.extract(from: dataSet)
            let colorSpace = dataSet.string(for: .colorSpace)
            return .color(ColorPresentationState(
                parsed: baseState,
                iccProfile: iccProfile,
                colorSpace: colorSpace
            ))

        case .pseudoColorSoftcopyPresentationStateStorage:
            let paletteUID = dataSet.string(for: .paletteColorLookupTableUID)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            let wellKnownPalette = paletteUID.flatMap(PseudoColorPalette.init(wellKnownSOPInstanceUID:))
            let extractedLUT = dataSet.paletteColorLUT()
            guard let lut = extractedLUT ?? wellKnownPalette?.paletteColorLUT() else {
                throw GrayscalePresentationStateParser.ParseError.invalidLUTDescriptor(
                    "Pseudo-Color Softcopy Presentation State is missing Palette Color Lookup Table Module (PS3.3 C.7.9)"
                )
            }
            let matchedPalette = wellKnownPalette ?? PseudoColorPalette.matching(lut)?.palette
            let iccProfile = ICCProfile.extract(from: dataSet)
            let colorSpace = dataSet.string(for: .colorSpace)
            return .pseudoColor(PseudoColorPresentationState(
                parsed: baseState,
                paletteColorLUT: lut,
                palette: matchedPalette,
                paletteColorLookupTableUID: paletteUID,
                iccProfile: iccProfile,
                colorSpace: colorSpace
            ))

        case .blendingSoftcopyPresentationStateStorage:
            let blendingState = try BlendingPresentationStateBuilder.parse(dataSet: dataSet)
            return .blending(blendingState)

        default:
            throw GrayscalePresentationStateParser.ParseError.invalidSOPClassUID(baseState.sopClassUID)
        }
    }

    /// Parses a `DICOMFile` into a `PresentationStateDocument`.
    public func parse(file: DICOMFile) throws -> PresentationStateDocument {
        try parse(dataSet: file.dataSet)
    }

    /// Reads and parses a DICOM file at `url` into a `PresentationStateDocument`.
    public func parse(contentsOf url: URL) throws -> PresentationStateDocument {
        let data = try Data(contentsOf: url)
        let file = try DICOMFile.read(from: data)
        return try parse(file: file)
    }

    /// Parses a `DataSet` specifically as a `GrayscalePresentationState` (GSPS).
    public func parseGrayscale(dataSet: DataSet) throws -> GrayscalePresentationState {
        guard case .grayscale(let gsps) = try parse(dataSet: dataSet) else {
            throw GrayscalePresentationStateParser.ParseError.invalidSOPClassUID(
                dataSet.string(for: .sopClassUID) ?? ""
            )
        }
        return gsps
    }

    /// Parses a `DataSet` specifically as a `ColorPresentationState` (CSPS).
    public func parseColor(dataSet: DataSet) throws -> ColorPresentationState {
        guard case .color(let csps) = try parse(dataSet: dataSet) else {
            throw GrayscalePresentationStateParser.ParseError.invalidSOPClassUID(
                dataSet.string(for: .sopClassUID) ?? ""
            )
        }
        return csps
    }

    /// Parses a `DataSet` specifically as a `PseudoColorPresentationState` (Pseudo-CSPS).
    public func parsePseudoColor(dataSet: DataSet) throws -> PseudoColorPresentationState {
        guard case .pseudoColor(let pcsps) = try parse(dataSet: dataSet) else {
            throw GrayscalePresentationStateParser.ParseError.invalidSOPClassUID(
                dataSet.string(for: .sopClassUID) ?? ""
            )
        }
        return pcsps
    }

    /// Parses a `DataSet` specifically as a `BlendingPresentationState`.
    public func parseBlending(dataSet: DataSet) throws -> BlendingPresentationState {
        guard case .blending(let blending) = try parse(dataSet: dataSet) else {
            throw GrayscalePresentationStateParser.ParseError.invalidSOPClassUID(
                dataSet.string(for: .sopClassUID) ?? ""
            )
        }
        return blending
    }
}

// MARK: - Unified Presentation State Builder

/// Unified builder that serializes any `PresentationStateDocument` (GSPS, CSPS, Pseudo-CSPS, or Blending)
/// into a conformant DICOM `DataSet` or `DICOMFile`.
public struct PresentationStateBuilder: Sendable {
    public init() {}

    /// Builds a DICOM `DataSet` from a `PresentationStateDocument`.
    public func buildDataSet(
        from document: PresentationStateDocument,
        pixelDomain: PseudoColorPresentationStateBuilder.PixelDomain? = nil,
        patient: PresentationStatePatientContext,
        seriesInstanceUID: String,
        seriesNumber: Int = 9001,
        imageSize: (columns: Int, rows: Int)? = nil
    ) -> DataSet {
        switch document {
        case .grayscale(let gsps):
            return GrayscalePresentationStateBuilder().buildDataSet(
                from: gsps,
                patient: patient,
                seriesInstanceUID: seriesInstanceUID,
                seriesNumber: seriesNumber,
                imageSize: imageSize
            )
        case .color(let csps):
            return ColorPresentationStateBuilder().buildDataSet(
                from: csps,
                patient: patient,
                seriesInstanceUID: seriesInstanceUID,
                seriesNumber: seriesNumber,
                imageSize: imageSize
            )
        case .pseudoColor(let pcsps):
            return PseudoColorPresentationStateBuilder().buildDataSet(
                from: pcsps,
                pixelDomain: pixelDomain,
                patient: patient,
                seriesInstanceUID: seriesInstanceUID,
                seriesNumber: seriesNumber,
                imageSize: imageSize
            )
        case .blending(let blending):
            return BlendingPresentationStateBuilder().buildDataSet(
                from: blending,
                patient: patient,
                seriesInstanceUID: seriesInstanceUID,
                seriesNumber: seriesNumber,
                imageSize: imageSize
            )
        }
    }

    /// Builds a Part 10 `DICOMFile` from a `PresentationStateDocument`.
    public func buildFile(
        from document: PresentationStateDocument,
        pixelDomain: PseudoColorPresentationStateBuilder.PixelDomain? = nil,
        patient: PresentationStatePatientContext,
        seriesInstanceUID: String,
        seriesNumber: Int = 9001,
        imageSize: (columns: Int, rows: Int)? = nil,
        transferSyntaxUID: String = "1.2.840.10008.1.2.1"
    ) -> DICOMFile {
        let dataSet = buildDataSet(
            from: document,
            pixelDomain: pixelDomain,
            patient: patient,
            seriesInstanceUID: seriesInstanceUID,
            seriesNumber: seriesNumber,
            imageSize: imageSize
        )
        return DICOMFile.create(dataSet: dataSet, transferSyntaxUID: transferSyntaxUID)
    }

    /// Validates a `PresentationStateDocument` against PS3.3 conformance rules.
    public func validate(
        _ document: PresentationStateDocument,
        imageSize: (columns: Int, rows: Int)? = nil
    ) throws {
        switch document {
        case .grayscale(let gsps):
            try GrayscalePresentationStateBuilder().validate(gsps, imageSize: imageSize)
        case .color(let csps):
            try ColorPresentationStateBuilder().validate(csps, imageSize: imageSize)
        case .pseudoColor(let pcsps):
            try PseudoColorPresentationStateBuilder().validate(pcsps, imageSize: imageSize)
        case .blending:
            try GrayscalePresentationStateBuilder().validate(document.asGrayscaleModel, imageSize: imageSize)
        }
    }
}

private extension DataSet {
    func settingSOPClassUID(_ uid: String) -> DataSet {
        var copy = self
        copy.setString(uid, for: .sopClassUID, vr: .UI)
        return copy
    }
}

#if canImport(CoreGraphics)
public extension PresentationStateApplicator {
    /// Applies any `PresentationStateDocument` (GSPS, CSPS, or Pseudo-CSPS) to `PixelData`.
    static func apply(
        _ document: PresentationStateDocument,
        to pixelData: PixelData,
        frameIndex: Int = 0,
        sopInstanceUID: String? = nil
    ) -> CGImage? {
        switch document {
        case .grayscale(let gsps):
            return apply(gsps, to: pixelData, frameIndex: frameIndex, sopInstanceUID: sopInstanceUID)
        case .color(let csps):
            return apply(csps, to: pixelData, frameIndex: frameIndex)
        case .pseudoColor(let pcsps):
            return apply(pcsps, to: pixelData, frameIndex: frameIndex, sopInstanceUID: sopInstanceUID)
        case .blending:
            return apply(document.asGrayscaleModel, to: pixelData, frameIndex: frameIndex, sopInstanceUID: sopInstanceUID)
        }
    }
}
#endif
