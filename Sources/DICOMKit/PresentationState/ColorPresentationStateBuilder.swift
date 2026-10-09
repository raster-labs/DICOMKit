// NEMA-verified: 2026a, checked 2026-09-29 — PS3.3 2026a Table A.33.2-1 module set (no Modality/VOI/Presentation LUT; ICC Profile M), Table C.11.15-1, Table C.11.12-1 (0018,1624); SOP Class UID per PS3.6 Table A-1
// ColorPresentationStateBuilder.swift
// DICOMKit
//
// Writes a Color Softcopy Presentation State (PS3.3 A.33.2) — the standard
// object for "this colour image was being looked at like this": the crop,
// rotation, shutters and the reader's annotations, without a grey pipeline.
//
// Table A.33.2-1 is the grayscale IOD's module table with the three LUT
// modules taken out and the ICC Profile module (C.11.15) put in as M. A colour
// image has no Modality LUT, no VOI window and no Presentation LUT to record,
// so the IOD does not have the modules — and an object that carried them would
// be non-conformant, not merely redundant.
//
// The composition strategy is the same as the Pseudo-Color builder's: the
// grayscale builder writes everything the two IODs share (patient, study,
// series, identification, references, spatial transformation, displayed area,
// shutters, layers, annotations), and this builder removes what Table
// A.33.2-1 omits and adds what it requires. The model it takes is
// `ColorPresentationState`, which has no LUT fields at all, so nothing has to
// be stripped that the caller could have set; only the Presentation LUT Shape
// the grayscale builder always writes comes out.
//
// The read half is `GrayscalePresentationStateParser`, which accepts this SOP
// class; `ColorPresentationState.init(parsed:iccProfile:)` turns its result
// back into the colour model.

import Foundation
import DICOMCore

/// Builds a conformant Color Softcopy Presentation State data set.
public struct ColorPresentationStateBuilder: Sendable {

    /// SOP Class UID of the Color Softcopy Presentation State Storage IOD
    /// (PS3.6 Table A-1).
    public static let sopClassUID = "1.2.840.10008.5.1.4.1.1.11.2"

    /// Modality of a presentation state series — "PR", the same for every
    /// presentation state IOD (PS3.3 C.11.9 / C.7.3.1.1.1).
    public static let modality = GrayscalePresentationStateBuilder.modality

    public init() {}

    // MARK: - Building

    /// Turns a colour presentation state into a data set ready to be written.
    ///
    /// - Parameters:
    ///   - state: What to record. Its `iccProfile` fills the mandatory ICC
    ///     Profile module; when nil, the fixed sRGB profile is written —
    ///     A.33.4.3 says of the same module that "an ICC Input Profile
    ///     specifying a well-known space (such as sRGB) may be specified" when
    ///     no device profile is available.
    ///   - patient: Patient/study attributes copied from the source image.
    ///   - seriesInstanceUID: The presentation-state series this object joins.
    ///   - seriesNumber: Series Number of that series.
    ///   - imageSize: Columns and rows of the referenced image, used to write
    ///     the mandatory Displayed Area when the state records none.
    /// - Returns: A data set carrying the full Color Softcopy Presentation
    ///   State IOD.
    public func buildDataSet(
        from state: ColorPresentationState,
        patient: PresentationStatePatientContext,
        seriesInstanceUID: String,
        seriesNumber: Int,
        imageSize: (columns: Int, rows: Int)? = nil
    ) -> DataSet {
        // Everything shared is written by the builder that owns it. The
        // grayscale model is built without any LUT, so no Modality LUT, Softcopy
        // VOI LUT or Presentation LUT Sequence is written.
        var dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: Self.grayscaleModel(of: state),
            patient: patient,
            seriesInstanceUID: seriesInstanceUID,
            seriesNumber: seriesNumber,
            imageSize: imageSize)

        // MARK: SOP Common — this is a different SOP class.
        dataSet.setString(Self.sopClassUID, for: .sopClassUID, vr: .UI)

        // MARK: Modules Table A.33.2-1 does not have.
        //
        // The grayscale builder always writes a Presentation LUT Shape (Table
        // C.11.6-1 makes it Type 1C in the Softcopy Presentation LUT module,
        // which is M in GSPS). That module is not in this IOD, so the shape
        // comes out; the others were never written because the model carries
        // no LUT.
        dataSet[.presentationLUTShape] = nil
        dataSet[.presentationLUTSequence] = nil
        dataSet[.modalityLUTSequence] = nil
        dataSet[.rescaleIntercept] = nil
        dataSet[.rescaleSlope] = nil
        dataSet[.rescaleType] = nil
        dataSet[.softcopyVOILUTSequence] = nil
        dataSet[.windowCenter] = nil
        dataSet[.windowWidth] = nil
        dataSet[.windowCenterWidthExplanation] = nil
        dataSet[.voiLUTFunction] = nil

        // MARK: Presentation State Shutter (C.11.12)
        //
        // Table C.11.12-1: Shutter Presentation Color CIELab Value (0018,1624)
        // is required with a shutter in every class but GSPS.
        GrayscalePresentationStateBuilder.applyShutterPresentationColor(
            state.shutterPresentationColor, to: &dataSet)

        // MARK: ICC Profile module (C.11.15) — M in Table A.33.2-1.
        //
        // ICC Profile (0028,2000) is Type 1; Color Space (0028,2002) Type 3 and
        // "shall be consistent with any ICC Profile" — so it is written only
        // for the sRGB profile this builder supplies itself, or when the
        // state's profile names one of the C.11.15.1.2 Defined Terms.
        let profileData = state.iccProfile?.profileData ?? SRGBICCProfileWriter.profileData
        dataSet[.iccProfile] = DataElement(
            tag: .iccProfile, vr: .OB,
            length: UInt32(profileData.count), valueData: profileData)
        if let colorSpace = Self.colorSpaceTerm(for: state.iccProfile) {
            dataSet.setString(colorSpace, for: .colorSpace, vr: .CS)
        }

        return dataSet
    }

    // MARK: - Model conversion

    /// The colour state as the grayscale builder's input: every shared module
    /// carried across, no LUT of any kind.
    static func grayscaleModel(of state: ColorPresentationState) -> GrayscalePresentationState {
        GrayscalePresentationState(
            sopInstanceUID: state.sopInstanceUID,
            sopClassUID: Self.sopClassUID,
            instanceNumber: state.instanceNumber,
            presentationLabel: state.presentationLabel,
            presentationDescription: state.presentationDescription,
            presentationCreationDate: state.presentationCreationDate,
            presentationCreationTime: state.presentationCreationTime,
            presentationCreatorsName: state.presentationCreatorsName,
            referencedSeries: state.referencedSeries,
            spatialTransformation: state.spatialTransformation,
            displayedArea: state.displayedArea,
            graphicLayers: state.graphicLayers,
            graphicAnnotations: state.graphicAnnotations,
            shutters: state.shutters,
            shutterPresentationColor: state.shutterPresentationColor)
    }

    /// The Color Space (0028,2002) Defined Term (PS3.3 C.11.15.1.2) for the
    /// profile going out, or nil when the profile is not one of the well-known
    /// spaces the terms name.
    static func colorSpaceTerm(for profile: ICCProfile?) -> String? {
        guard let profile else { return SRGBICCProfileWriter.colorSpace }
        switch profile.colorSpace {
        case .sRGB: return "SRGB"
        case .adobeRGB: return "ADOBERGB"
        case .proPhotoRGB: return "ROMMRGB"
        case .displayP3: return "DISPLAYP3"
        default: return nil
        }
    }

    /// Checks what the build cannot satisfy on its own; see
    /// ``GrayscalePresentationStateBuilder/validate(_:imageSize:)``.
    public func validate(
        _ state: ColorPresentationState,
        imageSize: (columns: Int, rows: Int)? = nil
    ) throws {
        try GrayscalePresentationStateBuilder().validate(
            Self.grayscaleModel(of: state), imageSize: imageSize)
    }
}

extension ColorPresentationState {

    /// The colour model of a Color Softcopy Presentation State the grayscale
    /// parser read: every shared module carried across, the ICC profile taken
    /// from the same data set through ``ICCProfile/extract(from:)``.
    ///
    /// - Parameters:
    ///   - parsed: What `GrayscalePresentationStateParser` returned for the object.
    ///   - iccProfile: The object's ICC Profile module, when the caller read it.
    public init(parsed: GrayscalePresentationState, iccProfile: ICCProfile? = nil) {
        self.init(
            sopInstanceUID: parsed.sopInstanceUID,
            sopClassUID: parsed.sopClassUID,
            instanceNumber: parsed.instanceNumber,
            presentationLabel: parsed.presentationLabel,
            presentationDescription: parsed.presentationDescription,
            presentationCreationDate: parsed.presentationCreationDate,
            presentationCreationTime: parsed.presentationCreationTime,
            presentationCreatorsName: parsed.presentationCreatorsName,
            referencedSeries: parsed.referencedSeries,
            iccProfile: iccProfile,
            spatialTransformation: parsed.spatialTransformation,
            displayedArea: parsed.displayedArea,
            graphicLayers: parsed.graphicLayers,
            graphicAnnotations: parsed.graphicAnnotations,
            shutters: parsed.shutters,
            shutterPresentationColor: parsed.shutterPresentationColor)
    }
}
