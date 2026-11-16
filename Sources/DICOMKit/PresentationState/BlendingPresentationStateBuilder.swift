// NEMA-verified: 2026a, checked 2026-11-16 — PS3.3 2026a Table A.33.4-1 (Blending Softcopy Presentation State IOD) and Table C.11.14-1 (Presentation State Blending Module): Blending Sequence (0070,0402) with UNDERLAY and OVERLAY items (0070,0405), Relative Opacity (0070,0403) FL, Palette Color LUT (C.7.9), and ICC Profile (C.11.15)
//
// BlendingPresentationStateBuilder.swift
// DICOMKit
//
// Builder and parser for Blending Softcopy Presentation State (1.2.840.10008.5.1.4.1.1.11.4).
//

import Foundation
import DICOMCore

/// Builds and parses a conformant Blending Softcopy Presentation State data set
/// (SOP Class UID `1.2.840.10008.5.1.4.1.1.11.4`, PS3.3 Section A.33.4 & C.11.14).
public struct BlendingPresentationStateBuilder: Sendable {

    /// SOP Class UID of the Blending Softcopy Presentation State Storage IOD.
    public static let sopClassUID = "1.2.840.10008.5.1.4.1.1.11.4"

    /// Modality of a presentation state series (`"PR"`).
    public static let modality = GrayscalePresentationStateBuilder.modality

    public init() {}

    // MARK: - Building

    /// Builds a `DataSet` for a `BlendingPresentationState` (PS3.3 A.33.4).
    public func buildDataSet(
        from state: BlendingPresentationState,
        patient: PresentationStatePatientContext,
        seriesInstanceUID: String,
        seriesNumber: Int = 9001,
        imageSize: (columns: Int, rows: Int)? = nil
    ) -> DataSet {
        let allReferencedSeries: [ReferencedSeries] = {
            if !state.referencedSeries.isEmpty {
                return state.referencedSeries
            }
            return state.underlaySeries + state.overlaySeries
        }()

        let proxy = GrayscalePresentationState(
            sopInstanceUID: state.sopInstanceUID,
            sopClassUID: Self.sopClassUID,
            instanceNumber: state.instanceNumber,
            presentationLabel: state.presentationLabel,
            presentationDescription: state.presentationDescription,
            presentationCreationDate: state.presentationCreationDate,
            presentationCreationTime: state.presentationCreationTime,
            presentationCreatorsName: state.presentationCreatorsName,
            referencedSeries: allReferencedSeries,
            spatialTransformation: state.spatialTransformation,
            displayedArea: state.displayedArea,
            scopedDisplayedAreas: state.scopedDisplayedAreas,
            graphicLayers: state.graphicLayers,
            graphicAnnotations: state.graphicAnnotations,
            shutters: state.shutters,
            shutterPresentationColor: state.shutterPresentationColor
        )

        var dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: proxy,
            patient: patient,
            seriesInstanceUID: seriesInstanceUID,
            seriesNumber: seriesNumber,
            imageSize: imageSize
        )

        // SOP Class UID -> Blending Softcopy Presentation State
        dataSet.setString(Self.sopClassUID, for: .sopClassUID, vr: .UI)
        dataSet[.presentationLUTShape] = nil

        // Shutter Presentation Color CIELab Value (Table C.11.12-1)
        GrayscalePresentationStateBuilder.applyShutterPresentationColor(
            state.shutterPresentationColor, to: &dataSet
        )

        // Presentation State Blending Module (PS3.3 Table C.11.14-1)
        let underlayItem = buildBlendingItem(
            position: "UNDERLAY",
            studyInstanceUID: patient.studyInstanceUID,
            series: state.underlaySeries,
            modalityLUT: state.underlayModalityLUT,
            voiLUT: state.underlayVOILUT
        )
        let overlayItem = buildBlendingItem(
            position: "OVERLAY",
            studyInstanceUID: patient.studyInstanceUID,
            series: state.overlaySeries,
            modalityLUT: state.overlayModalityLUT,
            voiLUT: state.overlayVOILUT
        )
        dataSet.setSequence([underlayItem, overlayItem], for: .blendingSequence)

        // Relative Opacity (0070,0403), VR FL
        var opacityBits = Float32(max(0.0, min(1.0, state.relativeOpacity))).bitPattern.littleEndian
        let opacityData = Data(bytes: &opacityBits, count: 4)
        dataSet[.relativeOpacity] = DataElement(
            tag: .relativeOpacity,
            vr: .FL,
            length: 4,
            valueData: opacityData
        )

        // Palette Color Lookup Table Module (C.7.9) for the superimposed (OVERLAY) image
        if let palette = state.palette {
            PseudoColorPresentationStateBuilder.applyPaletteColorLUT(
                palette,
                inverted: false,
                domain: nil,
                window: nil,
                to: &dataSet
            )
        } else if let lut = state.paletteColorLUT {
            PseudoColorPresentationStateBuilder.applyCustomPaletteColorLUT(
                lut,
                paletteUID: nil,
                isSigned: false,
                to: &dataSet
            )
        } else {
            PseudoColorPresentationStateBuilder.applyPaletteColorLUT(
                .hotIron,
                inverted: false,
                domain: nil,
                window: nil,
                to: &dataSet
            )
        }

        // ICC Profile Module (C.11.15)
        let profileData = state.iccProfile?.profileData ?? SRGBICCProfileWriter.profileData
        let colorSpaceString = state.colorSpace ?? SRGBICCProfileWriter.colorSpace
        dataSet[.iccProfile] = DataElement(
            tag: .iccProfile,
            vr: .OB,
            length: UInt32(profileData.count),
            valueData: profileData
        )
        dataSet.setString(colorSpaceString, for: .colorSpace, vr: .CS)

        return dataSet
    }

    // MARK: - Parsing

    /// Parses a `BlendingPresentationState` from a `DataSet` (PS3.3 A.33.4 & C.11.14).
    public static func parse(dataSet: DataSet) throws -> BlendingPresentationState {
        let baseParser = GrayscalePresentationStateParser(allowScopedVOILUT: true)
        let base = try baseParser.parse(dataSet: dataSet)

        var underlaySeries: [ReferencedSeries] = []
        var overlaySeries: [ReferencedSeries] = []
        var underlayModalityLUT: ModalityLUT?
        var overlayModalityLUT: ModalityLUT?
        var underlayVOILUT: VOILUT?
        var overlayVOILUT: VOILUT?

        if let blendingItems = dataSet.sequence(for: .blendingSequence) {
            for item in blendingItems {
                let position = item.string(for: .blendingPosition)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased() ?? ""
                let series = parseReferencedSeries(from: item)
                let modality = parseModalityLUT(from: item)
                let voi = parseFirstVOILUT(from: item)

                if position == "UNDERLAY" {
                    underlaySeries = series
                    underlayModalityLUT = modality
                    underlayVOILUT = voi
                } else if position == "OVERLAY" {
                    overlaySeries = series
                    overlayModalityLUT = modality
                    overlayVOILUT = voi
                }
            }
        }

        let relativeOpacity: Double = {
            if let element = dataSet[.relativeOpacity] {
                if let f32 = element.float32Value {
                    return Double(f32)
                }
                if let f64 = element.float64Value {
                    return f64
                }
                if element.valueData.count >= 4 {
                    let bits = element.valueData.withUnsafeBytes { $0.load(as: UInt32.self) }
                    return Double(Float32(bitPattern: UInt32(littleEndian: bits)))
                }
            }
            return 0.5
        }()

        let lut = dataSet.paletteColorLUT()
        let paletteUID = dataSet.string(for: .paletteColorLookupTableUID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let matchedPalette: PseudoColorPalette? = {
            if let uid = paletteUID, let p = PseudoColorPalette(wellKnownSOPInstanceUID: uid) {
                return p
            }
            if let creator = dataSet.string(for: .contentCreatorName)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let p = PseudoColorPalette(rawValue: creator.lowercased()) {
                return p
            }
            if let lut, let match = PseudoColorPalette.matching(lut) {
                return match.palette
            }
            return nil
        }()

        let iccProfile = ICCProfile.extract(from: dataSet)
        let colorSpace = dataSet.string(for: .colorSpace)?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Also populate `blendingDisplaySets` for callers that read the display set model
        var displaySets: [BlendingDisplaySet] = []
        let underlayRefs = underlaySeries.flatMap { s in
            s.referencedImages.map { ReferencedImageForBlending(sopInstanceUID: $0.sopInstanceUID, frameNumber: $0.referencedFrameNumbers?.first) }
        }
        let overlayRefs = overlaySeries.flatMap { s in
            s.referencedImages.map { ReferencedImageForBlending(sopInstanceUID: $0.sopInstanceUID, frameNumber: $0.referencedFrameNumbers?.first) }
        }
        if !underlayRefs.isEmpty || !overlayRefs.isEmpty {
            displaySets.append(
                BlendingDisplaySet(
                    displaySetNumber: 1,
                    referencedImages: underlayRefs + overlayRefs,
                    blendingMode: .alpha,
                    relativeOpacities: [1.0 - relativeOpacity, relativeOpacity]
                )
            )
        }

        return BlendingPresentationState(
            sopInstanceUID: base.sopInstanceUID,
            sopClassUID: base.sopClassUID,
            instanceNumber: base.instanceNumber,
            presentationLabel: base.presentationLabel,
            presentationDescription: base.presentationDescription,
            presentationCreationDate: base.presentationCreationDate,
            presentationCreationTime: base.presentationCreationTime,
            presentationCreatorsName: base.presentationCreatorsName,
            referencedSeries: base.referencedSeries,
            blendingDisplaySets: displaySets,
            underlaySeries: underlaySeries,
            overlaySeries: overlaySeries,
            underlayModalityLUT: underlayModalityLUT,
            overlayModalityLUT: overlayModalityLUT,
            underlayVOILUT: underlayVOILUT,
            overlayVOILUT: overlayVOILUT,
            relativeOpacity: relativeOpacity,
            paletteColorLUT: lut,
            palette: matchedPalette,
            iccProfile: iccProfile,
            colorSpace: colorSpace,
            spatialTransformation: base.spatialTransformation,
            displayedArea: base.displayedArea,
            scopedDisplayedAreas: base.scopedDisplayedAreas,
            graphicLayers: base.graphicLayers,
            graphicAnnotations: base.graphicAnnotations,
            shutters: base.shutters,
            shutterPresentationColor: base.shutterPresentationColor
        )
    }

    // MARK: - Private Helpers

    private func buildBlendingItem(
        position: String,
        studyInstanceUID: String,
        series: [ReferencedSeries],
        modalityLUT: ModalityLUT?,
        voiLUT: VOILUT?
    ) -> SequenceItem {
        var elements: [DataElement] = []
        elements.append(DataElement.string(tag: .blendingPosition, vr: .CS, value: position))
        if !studyInstanceUID.isEmpty {
            elements.append(DataElement.string(tag: .studyInstanceUID, vr: .UI, value: studyInstanceUID))
        }

        if !series.isEmpty {
            let seriesItems: [SequenceItem] = series.map { s in
                var sElements: [DataElement] = [
                    DataElement.string(tag: .seriesInstanceUID, vr: .UI, value: s.seriesInstanceUID)
                ]
                if !s.referencedImages.isEmpty {
                    let imgItems: [SequenceItem] = s.referencedImages.map { img in
                        var imgElements: [DataElement] = [
                            DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: img.sopClassUID),
                            DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: img.sopInstanceUID)
                        ]
                        if let frames = img.referencedFrameNumbers, !frames.isEmpty {
                            let isValue = frames.map(String.init).joined(separator: "\\")
                            imgElements.append(DataElement.string(tag: .referencedFrameNumber, vr: .IS, value: isValue))
                        }
                        return SequenceItem(elements: imgElements)
                    }
                    sElements.append(DataElement(tag: .referencedImageSequence, vr: .SQ, length: 0, valueData: Data(), sequenceItems: imgItems))
                }
                return SequenceItem(elements: sElements)
            }
            elements.append(DataElement(tag: .referencedSeriesSequence, vr: .SQ, length: 0, valueData: Data(), sequenceItems: seriesItems))
        }

        if case .rescale(let slope, let intercept, let type)? = modalityLUT {
            elements.append(DataElement.string(tag: .rescaleIntercept, vr: .DS, value: String(intercept)))
            elements.append(DataElement.string(tag: .rescaleSlope, vr: .DS, value: String(slope)))
            elements.append(DataElement.string(tag: .rescaleType, vr: .LO, value: type ?? "US"))
        }

        if case .window(let center, let width, let explanation, let function)? = voiLUT {
            var voiElements: [DataElement] = [
                DataElement.string(tag: .windowCenter, vr: .DS, value: String(center)),
                DataElement.string(tag: .windowWidth, vr: .DS, value: String(width))
            ]
            if let explanation, !explanation.isEmpty {
                voiElements.append(DataElement.string(tag: .windowCenterWidthExplanation, vr: .LO, value: explanation))
            }
            voiElements.append(DataElement.string(tag: .voiLUTFunction, vr: .CS, value: function.rawValue))
            elements.append(DataElement(tag: .softcopyVOILUTSequence, vr: .SQ, length: 0, valueData: Data(), sequenceItems: [SequenceItem(elements: voiElements)]))
        }

        return SequenceItem(elements: elements)
    }

    private static func parseReferencedSeries(from item: SequenceItem) -> [ReferencedSeries] {
        guard let seriesItems = item[.referencedSeriesSequence]?.sequenceItems else { return [] }
        return seriesItems.compactMap { sItem -> ReferencedSeries? in
            guard let seriesUID = sItem.string(for: .seriesInstanceUID)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !seriesUID.isEmpty else { return nil }
            let images: [ReferencedImage] = (sItem[.referencedImageSequence]?.sequenceItems ?? []).compactMap { imgItem -> ReferencedImage? in
                guard let sopClass = imgItem.string(for: .referencedSOPClassUID)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      let sopInstance = imgItem.string(for: .referencedSOPInstanceUID)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
                let frames = imgItem[.referencedFrameNumber]?.integerStringValues?.map { $0.value }
                return ReferencedImage(
                    sopClassUID: sopClass,
                    sopInstanceUID: sopInstance,
                    referencedFrameNumbers: (frames?.isEmpty == false) ? frames : nil
                )
            }
            return ReferencedSeries(seriesInstanceUID: seriesUID, referencedImages: images)
        }
    }

    private static func parseModalityLUT(from item: SequenceItem) -> ModalityLUT? {
        guard let slopeStr = item.string(for: .rescaleSlope),
              let interceptStr = item.string(for: .rescaleIntercept),
              let slope = Double(slopeStr.trimmingCharacters(in: .whitespacesAndNewlines)),
              let intercept = Double(interceptStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let type = item.string(for: .rescaleType)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .rescale(slope: slope, intercept: intercept, type: type)
    }

    private static func parseFirstVOILUT(from item: SequenceItem) -> VOILUT? {
        guard let voiItem = item[.softcopyVOILUTSequence]?.sequenceItems?.first,
              let centerStr = voiItem.string(for: .windowCenter),
              let widthStr = voiItem.string(for: .windowWidth),
              let center = Double(centerStr.components(separatedBy: "\\").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
              let width = Double(widthStr.components(separatedBy: "\\").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") else {
            return nil
        }
        let explanation = voiItem.string(for: .windowCenterWidthExplanation)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let function = voiItem.string(for: .voiLUTFunction)
            .flatMap { VOILUTFunction(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? .linear
        return .window(center: center, width: width, explanation: explanation, function: function)
    }
}
