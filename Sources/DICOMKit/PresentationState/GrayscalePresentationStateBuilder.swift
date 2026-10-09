// NEMA-verified: 2026a, checked 2026-09-29 — PS3.3 2026a Table A.33.1-1 modules: Modality LUT (C.11.1), LUT sequences (C.11.6, C.11.8), Display Shutter and Presentation State Shutter (Tables C.7-17a, C.11.12-1), Displayed Area 1C attributes (Table C.10-4), conditional Graphic Filled (Table C.10-5), CIELab layer colour (C.10.7.1.1), Content Creator's Name Type 3 (Table 10.9.3-1 via Table 10-12, written zero length when unknown; wording D222, 2026-10-01); Compound Graphic Sequence and Text/Line/Fill Style Sequence Macros written with their 1C conditions per Tables C.10-5, C.10-5a/5b/5c (D39, 2026-09-29); Unformatted Text Value control characters per Table C.10-5
// GrayscalePresentationStateBuilder.swift
// DICOMKit
//
// Writes a Grayscale Softcopy Presentation State (PS3.3 A.33.1) — the standard
// object that records *how* an image was being looked at, without touching the
// image itself.
//
// This is the write half of the pair whose read half is
// `GrayscalePresentationStateParser`. What one emits the other must be able to
// read back: the two are tested against each other, because a presentation
// state that cannot survive a round trip is not worth storing.
//
// Nothing here burns anything into pixels. A GSPS is a separate SOP Instance
// that *references* the image it describes, which is what lets one image carry
// several saved looks — a lung window and a bone window are two objects
// pointing at the same slice, not two copies of it.

import Foundation
import DICOMCore

/// Builds a conformant Grayscale Softcopy Presentation State data set.
///
/// The builder deliberately takes an already-composed
/// ``GrayscalePresentationState`` rather than loose parameters: composing the
/// model is the caller's job (and is testable without DICOM), while this type
/// is only responsible for turning it into tags.
public struct GrayscalePresentationStateBuilder: Sendable {

    /// SOP Class UID of the Grayscale Softcopy Presentation State Storage IOD.
    public static let sopClassUID = "1.2.840.10008.5.1.4.1.1.11.1"

    /// Modality of a presentation state series — fixed by PS3.3 C.11.10.
    public static let modality = Modality.pr.rawValue

    public init() {}

    // MARK: - Building

    /// Turns a presentation state into a data set ready to be written.
    ///
    /// - Parameters:
    ///   - state: What to record. Its `sopInstanceUID` becomes the object's own
    ///     identity, and its `referencedSeries` the images it describes.
    ///   - patient: Patient/study attributes copied from the image the state was
    ///     made from. A presentation state lives in the *same study* as its
    ///     images, so these must match the source or the object will not filed
    ///     alongside it.
    ///   - seriesInstanceUID: The series the object belongs to. Callers that
    ///     group several states together pass the same UID for each.
    ///   - seriesNumber: Series Number of that series.
    ///   - imageSize: Columns and rows of the referenced image. The Displayed
    ///     Area Module is mandatory (Table A.33.1-1) and its selection sequence
    ///     Type 1 (Table C.10-4); when the state records no area and the size
    ///     is known, the whole image (1\1 to columns\rows, SCALE TO FIT) is
    ///     written, which is what the absence meant to the viewer. Without
    ///     either, the sequence is left out and ``validate(_:imageSize:)``
    ///     says so.
    /// - Returns: A data set carrying the full GSPS IOD.
    public func buildDataSet(
        from state: GrayscalePresentationState,
        patient: PresentationStatePatientContext,
        seriesInstanceUID: String,
        seriesNumber: Int,
        imageSize: (columns: Int, rows: Int)? = nil
    ) -> DataSet {
        var dataSet = DataSet()

        // MARK: SOP Common
        dataSet.setString(Self.sopClassUID, for: .sopClassUID, vr: .UI)
        dataSet.setString(state.sopInstanceUID, for: .sopInstanceUID, vr: .UI)
        if let specificCharacterSet = patient.specificCharacterSet {
            dataSet.setString(specificCharacterSet, for: .specificCharacterSet, vr: .CS)
        }

        // MARK: Patient
        dataSet.setString(patient.patientName ?? "", for: .patientName, vr: .PN)
        dataSet.setString(patient.patientID ?? "", for: .patientID, vr: .LO)
        dataSet.setString(patient.patientBirthDate ?? "", for: .patientBirthDate, vr: .DA)
        dataSet.setString(patient.patientSex ?? "", for: .patientSex, vr: .CS)
        // Written only when the image has one: Issuer of Patient ID is part of
        // how a viewer keys the patient (Weasis: patientId + issuer + name), so
        // a PR that drops it while the image carries it files under a different
        // patient — badge on the series, no state on the image.
        if let issuerOfPatientID = patient.issuerOfPatientID {
            dataSet.setString(issuerOfPatientID, for: .issuerOfPatientID, vr: .LO)
        }

        // MARK: General Study
        //
        // Study-level identity is copied verbatim: the presentation state is a
        // new instance in an existing study, never a new study.
        dataSet.setString(patient.studyInstanceUID, for: .studyInstanceUID, vr: .UI)
        dataSet.setString(patient.studyDate ?? "", for: .studyDate, vr: .DA)
        dataSet.setString(patient.studyTime ?? "", for: .studyTime, vr: .TM)
        dataSet.setString(patient.referringPhysicianName ?? "", for: .referringPhysicianName, vr: .PN)
        dataSet.setString(patient.studyID ?? "", for: .studyID, vr: .SH)
        dataSet.setString(patient.accessionNumber ?? "", for: .accessionNumber, vr: .SH)

        // MARK: Presentation Series
        //
        // Modality is "PR" by definition — a viewer uses it to tell presentation
        // states apart from the images they describe.
        dataSet.setString(Self.modality, for: .modality, vr: .CS)
        dataSet.setString(seriesInstanceUID, for: .seriesInstanceUID, vr: .UI)
        dataSet.setString(String(seriesNumber), for: .seriesNumber, vr: .IS)
        if let seriesDescription = patient.seriesDescription {
            dataSet.setString(seriesDescription, for: .seriesDescription, vr: .LO)
        }

        // MARK: General Equipment
        dataSet.setString(patient.manufacturer ?? "", for: .manufacturer, vr: .LO)

        // MARK: Presentation State Identification
        if let instanceNumber = state.instanceNumber {
            dataSet.setString(String(instanceNumber), for: .instanceNumber, vr: .IS)
        }
        // Content Label is type 1 — it must be present and must be CS-legal, so
        // it is derived from the human label rather than trusted from it.
        dataSet.setString(
            Self.contentLabel(from: state.presentationLabel),
            for: .contentLabel, vr: .CS)
        if let label = state.presentationLabel {
            dataSet.setString(label, for: .contentDescription, vr: .LO)
        }
        if let creationDate = state.presentationCreationDate {
            dataSet.setString(creationDate.dicomString, for: .presentationCreationDate, vr: .DA)
        }
        if let creationTime = state.presentationCreationTime {
            dataSet.setString(creationTime.dicomString, for: .presentationCreationTime, vr: .TM)
        }
        // Content Creator's Name is Type 3 (PS3.3 2026a Table 10.9.3-1, included by Table 10-12);
        // written zero length when unknown, which PS3.5 2026a 7.4.5 permits for Type 3.
        dataSet.setString(state.presentationCreatorsName?.dicomString ?? "", for: .contentCreatorName, vr: .PN)

        // MARK: Presentation State Relationship
        dataSet[.referencedSeriesSequence] = Self.referencedSeriesElement(state.referencedSeries)

        // MARK: Modality LUT (C.11.1)
        //
        // PS3.4 N.2.1.1: a viewer applies only the Modality LUT carried by the
        // presentation state and never the image's own; a window written in
        // rescaled units without one is applied to stored values.
        switch state.modalityLUT {
        case .rescale(let slope, let intercept, let type)?:
            dataSet.setString(Self.decimalString(intercept), for: .rescaleIntercept, vr: .DS)
            dataSet.setString(Self.decimalString(slope), for: .rescaleSlope, vr: .DS)
            dataSet.setString(type ?? "US", for: .rescaleType, vr: .LO)   // Type 1C with the intercept
        case .lut(let lut)?:
            dataSet[.modalityLUTSequence] = Self.sequence(
                tag: .modalityLUTSequence,
                items: [Self.lutItem(lut, extra: [
                    // Modality LUT Type (0028,3004), Type 1; "US" is the unspecified type
                    DataElement.string(tag: Tag(group: 0x0028, element: 0x3004), vr: .LO, value: "US")
                ])])
        case nil:
            break
        }

        // MARK: Display transformations
        if let voiLUT = state.voiLUT {
            Self.applyVOILUT(voiLUT, to: &dataSet)
        }
        if let spatial = state.spatialTransformation {
            // The dictionary decides the encoding (US); the builder supplies
            // only the number.
            dataSet.setInteger(spatial.rotation, for: .imageRotation)
            dataSet.setString(spatial.horizontalFlip ? "Y" : "N", for: .imageHorizontalFlip, vr: .CS)
        }
        if let area = Self.displayedArea(of: state, imageSize: imageSize) {
            dataSet[.displayedAreaSelectionSequence] = Self.displayedAreaElement(area)
        }

        // MARK: Display Shutter (C.7.6.11, C.11.12)
        //
        // Shutter Presentation Color CIELab Value (0018,1624) is not written
        // here: Table C.11.12-1 requires it only "if the SOP Class is other
        // than Grayscale Softcopy Presentation State Storage", and a 1C
        // element whose condition fails shall be absent (PS3.5 7.4.2). The
        // Pseudo-Color and Color builders add it with
        // `applyShutterPresentationColor`.
        Self.applyShutters(state.shutters, to: &dataSet)

        // MARK: Annotations
        //
        // The reader's own text and arrows. A layer is required by C.10.5 for
        // every annotation, so states carrying annotations without layers would
        // be non-conformant — the caller composes both together.
        if !state.graphicLayers.isEmpty {
            dataSet[.graphicLayerSequence] = Self.graphicLayerElement(state.graphicLayers)
        }
        if !state.graphicAnnotations.isEmpty {
            dataSet[.graphicAnnotationSequence] =
                Self.graphicAnnotationElement(state.graphicAnnotations)
        }

        // MARK: Presentation LUT
        //
        // Written as a shape rather than a table: INVERSE is how a GSPS says
        // "this was being read inverted", which is the only case the viewer
        // produces.
        switch state.presentationLUT {
        case .inverse:
            dataSet.setString("INVERSE", for: .presentationLUTShape, vr: .CS)
        case .identity, .none:
            dataSet.setString("IDENTITY", for: .presentationLUTShape, vr: .CS)
        case .lut(let lut):
            // C.11.6: a table is carried in the Presentation LUT Sequence and
            // the Shape is then absent; replacing it with IDENTITY would change
            // what the state shows.
            dataSet[.presentationLUTSequence] = Self.sequence(
                tag: .presentationLUTSequence, items: [Self.lutItem(lut)])
        }

        return dataSet
    }

    // MARK: - Validation

    /// What keeps a state from being written as a conformant object.
    public enum ValidationError: Error, Sendable, Equatable, CustomStringConvertible {
        /// No Displayed Area and no image size to derive one from: the Type 1
        /// Displayed Area Selection Sequence (Table C.10-4) would be absent.
        case missingDisplayedArea
        /// The Displayed Area breaks a Table C.10-4 Type 1C condition.
        case displayedArea(DisplayedArea.ConformanceError)
        /// Presentation State Relationship (Table C.11.11-1b): Referenced Series
        /// Sequence and each item's Referenced Image Sequence are Type 1 with
        /// one or more items.
        case missingReferencedImages
        /// A Compound Graphic Sequence item that breaks Table C.10-5 /
        /// C.10.5.1.3 (D39).
        case compoundGraphic(String)

        public var description: String {
            switch self {
            case .missingDisplayedArea:
                return "Displayed Area Selection Sequence (0070,005A) is Type 1 (PS3.3 Table C.10-4); give the state a displayedArea or the builder an imageSize"
            case .displayedArea(let error):
                return error.description
            case .missingReferencedImages:
                return "Referenced Series Sequence (0008,1115) needs at least one series with at least one image (PS3.3 Table C.11.11-1b)"
            case .compoundGraphic(let problem):
                return problem
            }
        }
    }

    /// Checks the conditions ``buildDataSet(from:patient:seriesInstanceUID:seriesNumber:imageSize:)``
    /// cannot satisfy on its own. The build itself never throws — the viewer's
    /// save path must not fail on a state it could show — so callers that want
    /// a conformance guarantee call this first.
    public func validate(
        _ state: GrayscalePresentationState,
        imageSize: (columns: Int, rows: Int)? = nil
    ) throws {
        guard let area = Self.displayedArea(of: state, imageSize: imageSize) else {
            throw ValidationError.missingDisplayedArea
        }
        do {
            try area.validate()
        } catch let error as DisplayedArea.ConformanceError {
            throw ValidationError.displayedArea(error)
        }
        guard state.referencedSeries.contains(where: { !$0.referencedImages.isEmpty }) else {
            throw ValidationError.missingReferencedImages
        }
        if let problem = Self.compoundGraphicProblems(state.graphicAnnotations).first {
            throw ValidationError.compoundGraphic(problem)
        }
    }

    /// Compound graphics that break Table C.10-5 / C.10.5.1.3: point counts,
    /// AXIS ticks, rotation range, duplicate Compound Graphic Instance IDs, and a
    /// compound graphic without its alternate rendering (C.10.5.1.3.1).
    static func compoundGraphicProblems(_ annotations: [GraphicAnnotation]) -> [String] {
        var problems: [String] = []
        var seen = Set<Int>()
        for annotation in annotations {
            let linked = Set(annotation.graphicObjects.compactMap(\.compoundGraphicInstanceID)
                + annotation.textObjects.compactMap(\.compoundGraphicInstanceID))
            for graphic in annotation.compoundGraphics {
                problems += graphic.conformanceProblems
                if !seen.insert(graphic.instanceID).inserted {
                    problems.append("Compound Graphic Instance ID \(graphic.instanceID) is not unique (C.10.5.1.3.1)")
                }
                if !linked.contains(graphic.instanceID) {
                    problems.append("Compound graphic \(graphic.instanceID) has no alternate rendering in the Graphic or Text Object Sequence (C.10.5.1.3.1)")
                }
            }
        }
        return problems
    }

    /// The area that goes out: the state's own, or the whole image when the
    /// state has none and the size is known.
    static func displayedArea(
        of state: GrayscalePresentationState,
        imageSize: (columns: Int, rows: Int)?
    ) -> DisplayedArea? {
        if let area = state.displayedArea { return area }
        guard let size = imageSize, size.columns > 0, size.rows > 0 else { return nil }
        // Table C.10-4: corners are column\row relative to the origin 1\1.
        return DisplayedArea(
            topLeft: (column: 1, row: 1),
            bottomRight: (column: size.columns, row: size.rows),
            sizeMode: .scaleToFit)
    }

    // MARK: - LUT and shutter encoding

    /// One item of a Modality, VOI or Presentation LUT Sequence: LUT Descriptor
    /// (entries, first mapped value, bits per entry; 65536 entries are written as 0
    /// per C.11.1.1), LUT Data as 16-bit words, and the explanation when there is one.
    private static func lutItem(_ lut: LUTData, extra: [DataElement] = []) -> SequenceItem {
        let entries = lut.numberOfEntries >= 65536 ? 0 : lut.numberOfEntries
        var words = Data(capacity: lut.data.count * 2)
        for value in lut.data {
            let word = UInt16(truncatingIfNeeded: value)
            words.append(UInt8(word & 0xFF))
            words.append(UInt8(word >> 8))
        }
        var elements: [DataElement] = [
            Self.integers([entries, lut.firstValueMapped & 0xFFFF, lut.bitsPerEntry], for: .lutDescriptor),
            DataElement(tag: .lutData, vr: .OW, length: UInt32(words.count), valueData: words),
        ]
        if let explanation = lut.explanation {
            elements.append(DataElement.string(tag: .lutExplanation, vr: .LO, value: explanation))
        }
        return SequenceItem(elements: elements + extra)
    }

    /// Display Shutter module (C.7.6.11): geometry is row/column with origin 1,1;
    /// (0018,1610) and (0018,1620) are written row first.
    private static func applyShutters(_ shutters: [DisplayShutter], to dataSet: inout DataSet) {
        var shapes: [String] = []
        for shutter in shutters {
            switch shutter {
            case .rectangular(let left, let right, let top, let bottom, _):
                shapes.append("RECTANGULAR")
                dataSet.setInteger(left, for: .shutterLeftVerticalEdge)
                dataSet.setInteger(right, for: .shutterRightVerticalEdge)
                dataSet.setInteger(top, for: .shutterUpperHorizontalEdge)
                dataSet.setInteger(bottom, for: .shutterLowerHorizontalEdge)
            case .circular(let column, let row, let radius, _):
                shapes.append("CIRCULAR")
                _ = dataSet.setIntegers([row, column], for: .centerOfCircularShutter)
                dataSet.setInteger(radius, for: .radiusOfCircularShutter)
            case .polygonal(let vertices, _):
                shapes.append("POLYGONAL")
                _ = dataSet.setIntegers(vertices.flatMap { [$0.row, $0.column] },
                                        for: .verticesOfThePolygonalShutter)
            case .bitmap:
                // Bitmap Display Shutter (C.7.6.15) needs the overlay plane as well
                continue
            }
        }
        guard !shapes.isEmpty else { return }
        dataSet.setString(shapes.joined(separator: "\\"), for: .shutterShape, vr: .CS)
        // Shutter Presentation Value (0018,1622) is Type 1C in C.11.12: a P-Value
        dataSet.setInteger(shutters.first?.presentationValue ?? 0, for: .shutterPresentationValue)
    }

    /// Shutter Presentation Color CIELab Value (0018,1624), three US values
    /// encoded per C.10.7.1.1. Table C.11.12-1: Type 1C, "Required if the
    /// Display Shutter Module or Bitmap Display Shutter Module is present and
    /// the SOP Class is other than Grayscale Softcopy Presentation State
    /// Storage" — so the colour builders call this after the shutters are
    /// written, and it writes nothing when no shutter shape went out. A state
    /// with shutters but no colour gets ``CIELabColor/shutterBlack``, the
    /// colour of the P-Value 0 the monochrome attribute defaults to.
    static func applyShutterPresentationColor(
        _ color: CIELabColor?, to dataSet: inout DataSet
    ) {
        guard dataSet[.shutterShape] != nil else { return }
        _ = dataSet.setIntegers(
            (color ?? .shutterBlack).encodedValues,
            for: Tag(group: 0x0018, element: 0x1624))
    }

    // MARK: - Sequences

    private static func referencedSeriesElement(_ series: [ReferencedSeries]) -> DataElement {
        let items = series.map { entry -> SequenceItem in
            var elements: [DataElement] = [
                DataElement.string(tag: .seriesInstanceUID, vr: .UI, value: entry.seriesInstanceUID)
            ]

            if !entry.referencedImages.isEmpty {
                let imageItems = entry.referencedImages.map { image -> SequenceItem in
                    var imageElements: [DataElement] = [
                        DataElement.string(
                            tag: .referencedSOPClassUID, vr: .UI, value: image.sopClassUID),
                        DataElement.string(
                            tag: .referencedSOPInstanceUID, vr: .UI, value: image.sopInstanceUID)
                    ]
                    // Frame numbers are written only for the multi-frame case;
                    // an absent value means "the whole instance".
                    if let frames = image.referencedFrameNumbers, !frames.isEmpty {
                        imageElements.append(DataElement.string(
                            tag: .referencedFrameNumber, vr: .IS,
                            value: frames.map(String.init).joined(separator: "\\")))
                    }
                    return SequenceItem(elements: imageElements)
                }
                elements.append(sequence(tag: .referencedImageSequence, items: imageItems))
            }

            return SequenceItem(elements: elements)
        }

        return sequence(tag: .referencedSeriesSequence, items: items)
    }

    /// One Displayed Area Selection Sequence item per Table C.10-4.
    ///
    /// The Type 1C attributes follow the table's conditions exactly, and PS3.5
    /// 7.4.2 (a 1C element whose condition is not met shall be absent):
    /// * Presentation Pixel Spacing (0070,0101) — required for TRUE SIZE, may be
    ///   present otherwise; written whenever the state has it.
    /// * Presentation Pixel Aspect Ratio (0070,0102) — required if the spacing
    ///   is not present; then the state's ratio or 1\1, the square pixels the
    ///   viewer assumes. Not written next to a spacing.
    /// * Presentation Pixel Magnification Ratio (0070,0103) — required for
    ///   MAGNIFY; written whenever the state has it.
    /// A TRUE SIZE area without a spacing, or a MAGNIFY area without a ratio,
    /// cannot be written truthfully — the required value does not exist — so
    /// the mode goes out as SCALE TO FIT, the mode whose meaning needs neither.
    /// ``validate(_:imageSize:)`` reports that downgrade before it happens.
    private static func displayedAreaElement(_ area: DisplayedArea) -> DataElement {
        // Encodings come from the dictionary (SL for the corners, DS, IS, FL).
        // The parser accepts the IS corners older builds wrote.
        let sizeMode: PresentationSizeMode = (try? area.validate()) == nil
            ? .scaleToFit : area.sizeMode
        var elements: [DataElement] = [
            Self.integers([area.topLeft.column, area.topLeft.row],
                          for: .displayedAreaTopLeftHandCorner),
            Self.integers([area.bottomRight.column, area.bottomRight.row],
                          for: .displayedAreaBottomRightHandCorner),
            DataElement.string(
                tag: .presentationSizeMode, vr: .CS, value: sizeMode.rawValue),
        ]
        if let spacing = area.pixelSpacing {
            // Row spacing then column spacing (Table C.10-4, 10.7.1.3)
            elements.append(Self.reals([spacing.row, spacing.column],
                                       for: .presentationPixelSpacing))
        } else {
            let ratio = area.pixelAspectRatio ?? (vertical: 1, horizontal: 1)
            elements.append(Self.integers([ratio.vertical, ratio.horizontal],
                                          for: .presentationPixelAspectRatio))
        }
        if let magnification = area.magnificationRatio {
            elements.append(Self.reals([magnification],
                                       for: .presentationPixelMagnificationRatio))
        }
        return sequence(tag: .displayedAreaSelectionSequence, items: [SequenceItem(elements: elements)])
    }

    private static func applyVOILUT(_ voiLUT: VOILUT, to dataSet: inout DataSet) {
        switch voiLUT {
        case .window(let center, let width, let explanation, let function):
            // The window lives in the Softcopy VOI LUT Sequence (C.11.8) —
            // the module the presentation state IODs actually contain. Viewers
            // read a PR's window from inside this sequence only; the years
            // this builder wrote the values top-level, every conforming viewer
            // displayed the state with no window at all.
            var itemElements: [DataElement] = [
                DataElement.string(
                    tag: .windowCenter, vr: .DS, value: Self.decimalString(center)),
                DataElement.string(
                    tag: .windowWidth, vr: .DS, value: Self.decimalString(width)),
            ]
            if let explanation {
                itemElements.append(DataElement.string(
                    tag: .windowCenterWidthExplanation, vr: .LO, value: explanation))
            }
            // LINEAR is the default and is left implicit, matching what the
            // parser assumes when the tag is absent.
            if function != .linear {
                itemElements.append(DataElement.string(
                    tag: .voiLUTFunction, vr: .CS, value: function.rawValue))
            }
            // No Referenced Image Sequence in the item: absent, the window
            // applies to every referenced image (C.11.8.1), which is exactly
            // this object's meaning — one state per image.
            dataSet[.softcopyVOILUTSequence] = sequence(
                tag: .softcopyVOILUTSequence,
                items: [SequenceItem(elements: itemElements)])

            // The same values top-level as well. Not part of the IOD, but a
            // legal extension — and it is what our own parser read before the
            // sequence existed, so files written now stay readable by builds
            // from before it.
            dataSet.setString(Self.decimalString(center), for: .windowCenter, vr: .DS)
            dataSet.setString(Self.decimalString(width), for: .windowWidth, vr: .DS)
            if let explanation {
                dataSet.setString(explanation, for: .windowCenterWidthExplanation, vr: .LO)
            }
            if function != .linear {
                dataSet.setString(function.rawValue, for: .voiLUTFunction, vr: .CS)
            }
        case .lut(let lut):
            // A table lives in the VOI LUT Sequence inside the Softcopy VOI LUT
            // Sequence item (C.11.8); dropping it would change the shown contrast.
            let item = SequenceItem(elements: [
                sequence(tag: .voiLUTSequence, items: [Self.lutItem(lut)])
            ])
            dataSet[.softcopyVOILUTSequence] = sequence(
                tag: .softcopyVOILUTSequence, items: [item])
        }
    }

    private static func graphicLayerElement(_ layers: [GraphicLayer]) -> DataElement {
        let items = layers.map { layer -> SequenceItem in
            var elements: [DataElement] = [
                DataElement.string(tag: .graphicLayer, vr: .CS, value: layer.name),
                DataElement.string(
                    tag: .graphicLayerOrder, vr: .IS, value: String(layer.order))
            ]
            if let description = layer.description {
                elements.append(DataElement.string(
                    tag: .graphicLayerDescription, vr: .LO, value: description))
            }
            if let grayscale = layer.recommendedGrayscaleValue {
                elements.append(Self.integers(
                    [grayscale], for: .graphicLayerRecommendedDisplayGrayscaleValue))
            }
            if let rgb = layer.recommendedRGBValue {
                // (0070,0067) Graphic Layer Recommended Display RGB Value is retired;
                // C.10.7 replaced it with the CIELab value (0070,0401), encoded per
                // C.10.7.1.1: L* over 0...0xFFFF, a* and b* offset so 0x8080 is 0.
                elements.append(Self.integers(
                    Self.cieLabEncoded(from: rgb),
                    for: Tag(group: 0x0070, element: 0x0401)))
            }
            return SequenceItem(elements: elements)
        }
        return sequence(tag: .graphicLayerSequence, items: items)
    }

    /// The three unsigned shorts of a Graphic Layer Recommended Display CIELab
    /// Value (C.10.7.1.1) for a 16-bit-per-channel sRGB colour.
    static func cieLabEncoded(from rgb: (red: Int, green: Int, blue: Int)) -> [Int] {
        let linear = (
            red: ColorTransform.sRGBToLinear(Double(rgb.red) / 65535),
            green: ColorTransform.sRGBToLinear(Double(rgb.green) / 65535),
            blue: ColorTransform.sRGBToLinear(Double(rgb.blue) / 65535))
        let lab = ColorTransform.rgbToLAB(linear)
        return [lab.l / 100 * 65535, (lab.a + 128) * 257, (lab.b + 128) * 257]
            .map { min(65535, max(0, Int($0.rounded()))) }
    }

    /// The inverse of ``cieLabEncoded(from:)``, for reading (0070,0401) back.
    static func rgb(fromCIELabEncoded encoded: [Int]) -> (red: Int, green: Int, blue: Int)? {
        guard encoded.count == 3 else { return nil }
        let l = Double(encoded[0]) / 65535 * 100
        let a = Double(encoded[1]) / 257 - 128
        let b = Double(encoded[2]) / 257 - 128
        // CIELab -> XYZ (same D65 reference as ColorTransform.xyzToLAB) -> linear RGB -> sRGB
        let fy = (l + 16) / 116
        let fx = fy + a / 500
        let fz = fy - b / 200
        func finv(_ t: Double) -> Double {
            let delta = 6.0 / 29.0
            return t > delta ? t * t * t : 3 * delta * delta * (t - 4.0 / 29.0)
        }
        let xyz = (x: 0.95047 * finv(fx), y: 1.0 * finv(fy), z: 1.08883 * finv(fz))
        let linear = ColorTransform.xyzToRGB(xyz)
        func channel(_ v: Double) -> Int {
            min(65535, max(0, Int((ColorTransform.linearToSRGB(v) * 65535).rounded())))
        }
        return (red: channel(linear.red), green: channel(linear.green), blue: channel(linear.blue))
    }

    private static func graphicAnnotationElement(
        _ annotations: [GraphicAnnotation]
    ) -> DataElement {
        let items = annotations.map { annotation -> SequenceItem in
            var elements: [DataElement] = [
                DataElement.string(tag: .graphicLayer, vr: .CS, value: annotation.layer)
            ]

            if !annotation.referencedImages.isEmpty {
                let imageItems = annotation.referencedImages.map { image -> SequenceItem in
                    var imageElements: [DataElement] = [
                        DataElement.string(
                            tag: .referencedSOPClassUID, vr: .UI, value: image.sopClassUID),
                        DataElement.string(
                            tag: .referencedSOPInstanceUID, vr: .UI,
                            value: image.sopInstanceUID)
                    ]
                    if let frames = image.referencedFrameNumbers, !frames.isEmpty {
                        imageElements.append(DataElement.string(
                            tag: .referencedFrameNumber, vr: .IS,
                            value: frames.map(String.init).joined(separator: "\\")))
                    }
                    return SequenceItem(elements: imageElements)
                }
                elements.append(sequence(tag: .referencedImageSequence, items: imageItems))
            }

            if !annotation.graphicObjects.isEmpty {
                let graphicItems = annotation.graphicObjects.map(graphicObjectItem)
                elements.append(sequence(tag: .graphicObjectSequence, items: graphicItems))
            }
            if !annotation.textObjects.isEmpty {
                let textItems = annotation.textObjects.map(textObjectItem)
                elements.append(sequence(tag: .textObjectSequence, items: textItems))
            }
            if !annotation.compoundGraphics.isEmpty {
                let compoundItems = annotation.compoundGraphics.map(compoundGraphicItem)
                elements.append(sequence(tag: .compoundGraphicSequence, items: compoundItems))
            }

            return SequenceItem(elements: elements)
        }
        return sequence(tag: .graphicAnnotationSequence, items: items)
    }

    private static func graphicObjectItem(_ object: GraphicObject) -> SequenceItem {
        var elements: [DataElement] = [
            DataElement.string(
                tag: .graphicAnnotationUnits, vr: .CS, value: object.units.rawValue),
            // Always 2: Graphic Data here is (column, row) pairs.
            Self.integers([2], for: .graphicDimensions),
            Self.integers([object.pointCount], for: .numberOfGraphicPoints),
            Self.reals(object.data, for: .graphicData),
            DataElement.string(tag: .graphicType, vr: .CS, value: object.type.rawValue),
        ]
        // Graphic Filled (0070,0024) is Type 1C (C.10.5): only for CIRCLE, ELLIPSE, or
        // a POLYLINE / INTERPOLATED whose first point is also its last. PS3.5 7.4.2:
        // a 1C element whose condition is not met shall not be present.
        let d = object.data
        let closed = object.type == .circle || object.type == .ellipse
            || ((object.type == .polyline || object.type == .interpolated)
                && d.count >= 4 && d[0] == d[d.count - 2] && d[1] == d[d.count - 1])
        if closed {
            elements.append(DataElement.string(
                tag: .graphicFilled, vr: .CS, value: object.filled ? "Y" : "N"))
        }
        if let lineStyle = object.lineStyle {
            elements.append(Self.lineStyleElement(lineStyle))
        }
        if let fillStyle = object.fillStyle {
            elements.append(Self.fillStyleElement(fillStyle))
        }
        if let id = object.compoundGraphicInstanceID {
            elements.append(Self.integers([id], for: .compoundGraphicInstanceID))
        }
        if let group = object.graphicGroupID {
            elements.append(Self.integers([group], for: .graphicGroupID))
        }
        return SequenceItem(elements: elements)
    }

    // MARK: Compound graphics and styles (Tables C.10-5, C.10-5a/5b/5c; D39)

    private static func compoundGraphicItem(_ graphic: CompoundGraphic) -> SequenceItem {
        var elements: [DataElement] = [
            Self.integers([graphic.instanceID], for: .compoundGraphicInstanceID),
            DataElement.string(tag: .compoundGraphicUnits, vr: .CS, value: graphic.units.rawValue),
            Self.integers([2], for: .graphicDimensions),
            Self.integers([graphic.data.count / 2], for: .numberOfGraphicPoints),
            Self.reals(graphic.data, for: .graphicData),
            DataElement.string(tag: .compoundGraphicType, vr: .CS, value: graphic.type.rawValue),
        ]
        if let textStyle = graphic.textStyle {
            elements.append(Self.textStyleElement(textStyle, hasBoundingBox: false))
        }
        if let lineStyle = graphic.lineStyle {
            elements.append(Self.lineStyleElement(lineStyle))
        }
        if let angle = graphic.rotationAngle {
            elements.append(Self.reals([angle], for: .rotationAngle))
        }
        // Rotation Point: 1C with a Rotation Angle, or for CUTLINE / INFINITELINE.
        let needsRotationPoint = graphic.rotationAngle != nil
            || graphic.type == .cutline || graphic.type == .infiniteline
        if needsRotationPoint {
            let point = graphic.rotationPoint ?? graphic.points.first ?? GraphicPoint(column: 0, row: 0)
            elements.append(Self.reals([point.column, point.row], for: .rotationPoint))
        }
        // Gap Length: 1C for CUTLINE, INFINITELINE and CROSSHAIR (DISPLAY units).
        if [.cutline, .infiniteline, .crosshair].contains(graphic.type) {
            elements.append(Self.reals([graphic.gapLength ?? 0], for: .gapLength))
        }
        // Diameter of Visibility: 1C for CROSSHAIR.
        if graphic.type == .crosshair {
            elements.append(Self.reals([graphic.diameterOfVisibility ?? 1], for: .diameterOfVisibility))
        }
        // Major Ticks Sequence: 1C for AXIS (validate() reports fewer than two).
        if graphic.type == .axis {
            let ticks = graphic.majorTicks.map { tick in
                SequenceItem(elements: [
                    Self.reals([tick.position], for: .tickPosition),
                    DataElement.string(tag: .tickLabel, vr: .SH, value: tick.label)
                ])
            }
            elements.append(sequence(tag: .majorTicksSequence, items: ticks))
        }
        // Tick Alignment, Tick Label Alignment, Show Tick Label: 1C for RULER,
        // AXIS and CROSSHAIR.
        if [.ruler, .axis, .crosshair].contains(graphic.type) {
            elements.append(DataElement.string(
                tag: .tickAlignment, vr: .CS, value: (graphic.tickAlignment ?? .center).rawValue))
            elements.append(DataElement.string(
                tag: .tickLabelAlignment, vr: .CS, value: (graphic.tickLabelAlignment ?? .bottom).rawValue))
            elements.append(DataElement.string(
                tag: .showTickLabel, vr: .CS, value: (graphic.showTickLabel ?? true) ? "Y" : "N"))
        }
        // Graphic Filled: 1C for RECTANGLE and ELLIPSE; Fill Style 1C when filled.
        if graphic.type == .rectangle || graphic.type == .ellipse {
            elements.append(DataElement.string(
                tag: .graphicFilled, vr: .CS, value: graphic.filled ? "Y" : "N"))
            if graphic.filled {
                let fill = graphic.fillStyle
                    ?? FillStyle(onColor: graphic.lineStyle?.onColor ?? GraphicShadow.black)
                elements.append(Self.fillStyleElement(fill))
            }
        }
        if let group = graphic.graphicGroupID {
            elements.append(Self.integers([group], for: .graphicGroupID))
        }
        return SequenceItem(elements: elements)
    }

    private static func cieLab(_ color: CIELabColor, for tag: Tag) -> DataElement {
        Self.integers([color.l, color.a, color.b], for: tag)
    }

    /// The shadow attributes. In the Text Style macro the four companions are
    /// 1C "Required if Shadow Style is not OFF"; in the Line Style macro they
    /// are Type 1 (`always`).
    private static func shadowElements(_ shadow: GraphicShadow, always: Bool) -> [DataElement] {
        var elements = [DataElement.string(tag: .shadowStyle, vr: .CS, value: shadow.style.rawValue)]
        if always || shadow.style != .off {
            elements.append(Self.reals([shadow.offsetX], for: .shadowOffsetX))
            elements.append(Self.reals([shadow.offsetY], for: .shadowOffsetY))
            elements.append(Self.cieLab(shadow.color, for: .shadowColorCIELabValue))
            elements.append(Self.reals([shadow.opacity], for: .shadowOpacity))
        }
        return elements
    }

    private static func textStyleElement(_ style: TextStyle, hasBoundingBox: Bool) -> DataElement {
        var elements: [DataElement] = []
        if let font = style.fontName {
            elements.append(DataElement.string(tag: .fontName, vr: .LO, value: font))
            elements.append(DataElement.string(
                tag: .fontNameType, vr: .CS, value: style.fontNameType ?? "ISO_32000"))
        }
        elements.append(DataElement.string(tag: .cssFontName, vr: .LO, value: style.cssFontName))
        elements.append(Self.cieLab(style.color, for: .textColorCIELabValue))
        // Horizontal/Vertical Alignment: 1C, required with a bounding box.
        if hasBoundingBox || style.horizontalAlignment != nil {
            elements.append(DataElement.string(
                tag: .horizontalAlignment, vr: .CS,
                value: (style.horizontalAlignment ?? .left).rawValue))
        }
        if hasBoundingBox || style.verticalAlignment != nil {
            elements.append(DataElement.string(
                tag: .verticalAlignment, vr: .CS,
                value: (style.verticalAlignment ?? .top).rawValue))
        }
        elements += Self.shadowElements(style.shadow, always: false)
        elements.append(DataElement.string(tag: .underlined, vr: .CS, value: style.underlined ? "Y" : "N"))
        elements.append(DataElement.string(tag: .bold, vr: .CS, value: style.bold ? "Y" : "N"))
        elements.append(DataElement.string(tag: .italic, vr: .CS, value: style.italic ? "Y" : "N"))
        return sequence(tag: .textStyleSequence, items: [SequenceItem(elements: elements)])
    }

    private static func lineStyleElement(_ style: LineStyle) -> DataElement {
        var elements: [DataElement] = [Self.cieLab(style.onColor, for: .patternOnColorCIELabValue)]
        if let off = style.offColor {
            elements.append(Self.cieLab(off, for: .patternOffColorCIELabValue))
        }
        elements.append(Self.reals([style.onOpacity], for: .patternOnOpacity))
        if let offOpacity = style.offOpacity {
            elements.append(Self.reals([offOpacity], for: .patternOffOpacity))
        }
        elements.append(Self.reals([style.thickness], for: .lineThickness))
        elements.append(DataElement.string(tag: .lineDashingStyle, vr: .CS, value: style.dashing.rawValue))
        // Line Pattern: 1C, required when DASHED.
        if style.dashing == .dashed {
            elements.append(Self.integers([Int(style.pattern ?? 0xFF00_FF00)], for: .linePattern))
        }
        elements += Self.shadowElements(style.shadow, always: true)
        return sequence(tag: .lineStyleSequence, items: [SequenceItem(elements: elements)])
    }

    private static func fillStyleElement(_ style: FillStyle) -> DataElement {
        var elements: [DataElement] = [Self.cieLab(style.onColor, for: .patternOnColorCIELabValue)]
        if let off = style.offColor {
            elements.append(Self.cieLab(off, for: .patternOffColorCIELabValue))
        }
        elements.append(Self.reals([style.onOpacity], for: .patternOnOpacity))
        elements.append(Self.reals([style.offOpacity], for: .patternOffOpacity))
        elements.append(DataElement.string(tag: .fillMode, vr: .CS, value: style.mode.rawValue))
        // Fill Pattern: 1C, 128 bytes, required when STIPPELED.
        if style.mode == .stippled {
            var pattern = style.pattern ?? Data(repeating: 0xAA, count: 128)
            if pattern.count != 128 {
                pattern = Data(pattern.prefix(128)) + Data(repeating: 0, count: max(0, 128 - pattern.count))
            }
            elements.append(DataElement(
                tag: .fillPattern, vr: .OB, length: UInt32(pattern.count), valueData: pattern))
        }
        return sequence(tag: .fillStyleSequence, items: [SequenceItem(elements: elements)])
    }

    /// Unformatted Text Value (0070,0006): "multiple lines separated by CR LF,
    /// but otherwise no format control characters (such as horizontal or
    /// vertical tab and form feed)" (Table C.10-5). Other control characters
    /// become spaces; a bare LF or CR becomes CR LF.
    static func unformattedText(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { line in
            String(line.map { character -> Character in
                character.unicodeScalars.contains { $0.properties.generalCategory == .control }
                    ? " " : character
            })
        }.joined(separator: "\r\n")
    }

    private static func textObjectItem(_ text: TextObject) -> SequenceItem {
        var elements: [DataElement] = [
            DataElement.string(
                tag: .boundingBoxAnnotationUnits, vr: .CS,
                value: text.boundingBoxUnits.rawValue),
            DataElement.string(
                tag: .unformattedTextValue, vr: .ST, value: Self.unformattedText(text.text)),
            Self.reals([text.boundingBoxTopLeft.column, text.boundingBoxTopLeft.row],
                       for: .boundingBoxTopLeftHandCorner),
            Self.reals([text.boundingBoxBottomRight.column, text.boundingBoxBottomRight.row],
                       for: .boundingBoxBottomRightHandCorner),
            // Type 1C once a bounding box is present. LEFT because that is how
            // every renderer of this model draws — the anchor is the top-left.
            DataElement.string(
                tag: .boundingBoxTextHorizontalJustification, vr: .CS, value: "LEFT")
        ]
        if let anchor = text.anchorPoint {
            elements.append(Self.reals([anchor.column, anchor.row], for: .anchorPoint))
            elements.append(DataElement.string(
                tag: .anchorPointVisibility, vr: .CS,
                value: text.anchorPointVisible ? "Y" : "N"))
            elements.append(DataElement.string(
                tag: .anchorPointAnnotationUnits, vr: .CS,
                value: text.anchorPointUnits.rawValue))
        }
        if let style = text.textStyle {
            // Horizontal Alignment overrides Bounding Box Text Horizontal
            // Justification (Table C.10-5a), so the two are kept equal.
            if let horizontal = style.horizontalAlignment,
               let index = elements.firstIndex(where: { $0.tag == .boundingBoxTextHorizontalJustification }) {
                elements[index] = DataElement.string(
                    tag: .boundingBoxTextHorizontalJustification, vr: .CS, value: horizontal.rawValue)
            }
            elements.append(Self.textStyleElement(style, hasBoundingBox: true))
        }
        if let id = text.compoundGraphicInstanceID {
            elements.append(Self.integers([id], for: .compoundGraphicInstanceID))
        }
        if let group = text.graphicGroupID {
            elements.append(Self.integers([group], for: .graphicGroupID))
        }
        return SequenceItem(elements: elements)
    }

    /// An integer-valued element encoded the way the data dictionary says.
    ///
    /// The builder names the tag and the numbers; DICOMKit's own
    /// `DataElementDictionary` supplies the VR, so a call site cannot pick one
    /// that disagrees with the standard. `.UN` is unreachable for these tags —
    /// every one is in the dictionary — and only guards the lookup.
    private static func integers(_ values: [Int], for tag: Tag) -> DataElement {
        var holder = DataSet()
        guard holder.setIntegers(values, for: tag), let element = holder[tag] else {
            return DataElement.strings(
                tag: tag, vr: .UN, values: values.map(String.init))
        }
        return element
    }

    /// A real-valued element encoded the way the data dictionary says.
    /// See ``integers(_:for:)``.
    private static func reals(_ values: [Double], for tag: Tag) -> DataElement {
        var holder = DataSet()
        guard holder.setReals(values, for: tag, decimalStringFormatter: decimalString),
              let element = holder[tag] else {
            return DataElement.strings(
                tag: tag, vr: .UN, values: values.map(decimalString))
        }
        return element
    }

    private static func sequence(tag: Tag, items: [SequenceItem]) -> DataElement {
        DataElement(tag: tag, vr: .SQ, length: 0, valueData: Data(), sequenceItems: items)
    }

    // MARK: - Value formatting

    /// A DS value has 16 bytes to work with, so window values are written in the
    /// shortest form that keeps them exact.
    static func decimalString(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(format: "%.6g", value)
    }

    /// Derives a CS-legal Content Label from a user-typed name.
    ///
    /// CS permits uppercase letters, digits, space and underscore, up to 16
    /// characters. A reader typing "Lung window" must not produce a
    /// non-conformant object, so the label is folded rather than rejected.
    public static func contentLabel(from label: String?) -> String {
        let fallback = "PRESENTATION"
        guard let label, !label.isEmpty else { return fallback }

        let folded = label.uppercased().map { character -> Character in
            if character.isLetter, character.isASCII { return character }
            if character.isNumber, character.isASCII { return character }
            if character == " " || character == "_" { return character }
            return "_"
        }

        let trimmed = String(folded.prefix(16))
            .trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

/// The patient, study and equipment attributes a presentation state must repeat
/// from the image it describes.
///
/// A GSPS is filed into an existing study, so these are copied from the source
/// image rather than invented — a mismatch here is what makes a saved state
/// vanish from the study it belongs to.
public struct PresentationStatePatientContext: Sendable, Equatable {

    public var patientName: String?
    public var patientID: String?
    public var patientBirthDate: String?
    public var patientSex: String?
    /// Issuer of Patient ID (0010,0021). Copied because viewers fold it into
    /// the patient's identity key; see the write site for the failure it stops.
    public var issuerOfPatientID: String?

    public var studyInstanceUID: String
    public var studyDate: String?
    public var studyTime: String?
    public var studyID: String?
    public var accessionNumber: String?
    public var referringPhysicianName: String?

    public var specificCharacterSet: String?
    public var manufacturer: String?
    public var seriesDescription: String?

    public init(
        patientName: String? = nil,
        patientID: String? = nil,
        patientBirthDate: String? = nil,
        patientSex: String? = nil,
        issuerOfPatientID: String? = nil,
        studyInstanceUID: String,
        studyDate: String? = nil,
        studyTime: String? = nil,
        studyID: String? = nil,
        accessionNumber: String? = nil,
        referringPhysicianName: String? = nil,
        specificCharacterSet: String? = nil,
        manufacturer: String? = nil,
        seriesDescription: String? = nil
    ) {
        self.patientName = patientName
        self.patientID = patientID
        self.patientBirthDate = patientBirthDate
        self.patientSex = patientSex
        self.issuerOfPatientID = issuerOfPatientID
        self.studyInstanceUID = studyInstanceUID
        self.studyDate = studyDate
        self.studyTime = studyTime
        self.studyID = studyID
        self.accessionNumber = accessionNumber
        self.referringPhysicianName = referringPhysicianName
        self.specificCharacterSet = specificCharacterSet
        self.manufacturer = manufacturer
        self.seriesDescription = seriesDescription
    }

    /// Reads the context out of the image the state is being made from.
    public static func make(from dataSet: DataSet) -> PresentationStatePatientContext {
        func string(_ tag: Tag) -> String? {
            guard let value = dataSet.string(for: tag)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }

        return PresentationStatePatientContext(
            patientName: string(.patientName),
            patientID: string(.patientID),
            patientBirthDate: string(.patientBirthDate),
            patientSex: string(.patientSex),
            issuerOfPatientID: string(.issuerOfPatientID),
            studyInstanceUID: string(.studyInstanceUID) ?? "",
            studyDate: string(.studyDate),
            studyTime: string(.studyTime),
            studyID: string(.studyID),
            accessionNumber: string(.accessionNumber),
            referringPhysicianName: string(.referringPhysicianName),
            specificCharacterSet: string(.specificCharacterSet),
            manufacturer: string(.manufacturer))
    }
}
