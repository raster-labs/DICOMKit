//
// GrayscalePresentationStateBuilderTests.swift
// DICOMKit
//
// The builder's contract is that the parser can read back what it writes. Most
// of these tests are therefore round trips rather than tag assertions: a tag
// written in a form the parser does not accept is a bug even when the tag
// itself is correct.
//

import XCTest
import DICOMCore
import DICOMDictionary
@testable import DICOMKit

final class GrayscalePresentationStateBuilderTests: XCTestCase {

    // MARK: - Fixtures

    private let imageSOPClassUID = "1.2.840.10008.5.1.4.1.1.2"

    private func context() -> PresentationStatePatientContext {
        PresentationStatePatientContext(
            patientName: "DOE^JANE",
            patientID: "12345",
            patientBirthDate: "19600101",
            patientSex: "F",
            studyInstanceUID: "1.2.3.4.5",
            studyDate: "20260101",
            studyTime: "120000",
            studyID: "S1",
            accessionNumber: "A1",
            seriesDescription: "Presentation States")
    }

    private func state(
        label: String? = "Lung window",
        voiLUT: VOILUT? = .window(center: -600, width: 1500, explanation: nil, function: .linear),
        spatial: SpatialTransformation? = SpatialTransformation(rotation: 90, horizontalFlip: true),
        area: DisplayedArea? = DisplayedArea(
            topLeft: (column: 10, row: 20),
            bottomRight: (column: 210, row: 220),
            sizeMode: .scaleToFit),
        presentationLUT: PresentationLUT? = .identity,
        images: [String] = ["1.2.3.4.5.6.1"]
    ) -> GrayscalePresentationState {
        GrayscalePresentationState(
            sopInstanceUID: "1.2.3.4.5.99.1",
            instanceNumber: 1,
            presentationLabel: label,
            presentationCreationDate: DICOMDate(year: 2026, month: 8, day: 18),
            presentationCreationTime: DICOMTime(hour: 14, minute: 30, second: 0),
            referencedSeries: [
                ReferencedSeries(
                    seriesInstanceUID: "1.2.3.4.5.6",
                    referencedImages: images.map {
                        ReferencedImage(sopClassUID: imageSOPClassUID, sopInstanceUID: $0)
                    })
            ],
            voiLUT: voiLUT,
            presentationLUT: presentationLUT,
            spatialTransformation: spatial,
            displayedArea: area)
    }

    private func roundTrip(
        _ state: GrayscalePresentationState
    ) throws -> GrayscalePresentationState {
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state,
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)
        return try GrayscalePresentationStateParser().parse(dataSet: dataSet)
    }

    // MARK: - Identity and series attributes

    func test_build_writesGSPSSOPClassAndPRModality() {
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        XCTAssertEqual(
            dataSet.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.11.1")
        XCTAssertEqual(dataSet.string(for: .modality), "PR")
        XCTAssertEqual(dataSet.string(for: .seriesInstanceUID), "1.2.3.4.5.900")
        XCTAssertEqual(dataSet.string(for: .seriesNumber), "900")
    }

    /// A presentation state is filed into the study it describes, so study-level
    /// identity must be copied, not regenerated.
    func test_build_keepsStudyIdentityOfSourceImage() {
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        XCTAssertEqual(dataSet.string(for: .studyInstanceUID), "1.2.3.4.5")
        XCTAssertEqual(dataSet.string(for: .patientID), "12345")
        XCTAssertEqual(dataSet.string(for: .accessionNumber), "A1")
    }

    /// Issuer of Patient ID is part of how viewers key the patient (Weasis:
    /// patientId + issuer + name), so a PR that drops it while the image has it
    /// files under a different patient — series badge, but no state on the
    /// image. It must be copied when present, and stay absent when not: an
    /// empty element and a missing one read back the same, but only absence
    /// keeps issuer-less exports byte-identical to what they always were.
    func test_build_copiesIssuerOfPatientIDWhenPresent() {
        var patient = context()
        patient.issuerOfPatientID = "HOSP_A"

        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(),
            patient: patient,
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        XCTAssertEqual(dataSet.string(for: .issuerOfPatientID), "HOSP_A")
    }

    func test_build_omitsIssuerOfPatientIDWhenAbsent() {
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        XCTAssertNil(dataSet[.issuerOfPatientID])
    }

    /// The context reader is the other half: the viewer's save path copies the
    /// image's attributes through `make(from:)`, so an issuer the image carries
    /// has to survive that read or the write above never sees it.
    func test_makeContext_readsIssuerOfPatientID() {
        var imageDataSet = DataSet()
        imageDataSet.setString("1.2.3.4.5", for: .studyInstanceUID, vr: .UI)
        imageDataSet.setString("HOSP_A", for: .issuerOfPatientID, vr: .LO)

        let context = PresentationStatePatientContext.make(from: imageDataSet)

        XCTAssertEqual(context.issuerOfPatientID, "HOSP_A")
    }

    // MARK: - Round trips

    func test_roundTrip_preservesWindow() throws {
        let parsed = try roundTrip(state())

        guard case .window(let center, let width, _, let function)? = parsed.voiLUT else {
            return XCTFail("expected a window VOI LUT, got \(String(describing: parsed.voiLUT))")
        }
        XCTAssertEqual(center, -600)
        XCTAssertEqual(width, 1500)
        XCTAssertEqual(function, .linear)
    }

    func test_roundTrip_preservesRotationAndFlip() throws {
        let parsed = try roundTrip(state())

        XCTAssertEqual(parsed.spatialTransformation?.rotation, 90)
        XCTAssertEqual(parsed.spatialTransformation?.horizontalFlip, true)
    }

    func test_roundTrip_preservesDisplayedArea() throws {
        let parsed = try roundTrip(state())

        XCTAssertEqual(parsed.displayedArea?.topLeft.column, 10)
        XCTAssertEqual(parsed.displayedArea?.topLeft.row, 20)
        XCTAssertEqual(parsed.displayedArea?.bottomRight.column, 210)
        XCTAssertEqual(parsed.displayedArea?.bottomRight.row, 220)
        XCTAssertEqual(parsed.displayedArea?.sizeMode, .scaleToFit)
    }

    func test_roundTrip_preservesReferencedImages() throws {
        let parsed = try roundTrip(state(images: ["1.2.3.4.5.6.1", "1.2.3.4.5.6.2"]))

        XCTAssertEqual(parsed.referencedSeries.count, 1)
        XCTAssertEqual(parsed.referencedSeries.first?.seriesInstanceUID, "1.2.3.4.5.6")
        XCTAssertEqual(
            parsed.referencedSeries.first?.referencedImages.map(\.sopInstanceUID),
            ["1.2.3.4.5.6.1", "1.2.3.4.5.6.2"])
    }

    /// A state that changes nothing spatially must not invent a transformation:
    /// the parser reports nil, and the viewer restores the default view.
    func test_roundTrip_omitsSpatialTransformationWhenUnchanged() throws {
        let parsed = try roundTrip(state(spatial: nil, area: nil))

        XCTAssertNil(parsed.spatialTransformation)
        XCTAssertNil(parsed.displayedArea)
    }

    func test_roundTrip_preservesInvertedPolarity() throws {
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(presentationLUT: .inverse),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        XCTAssertEqual(dataSet.string(for: .presentationLUTShape), "INVERSE")
    }

    func test_roundTrip_sigmoidFunctionSurvives() throws {
        let parsed = try roundTrip(state(
            voiLUT: .window(center: 40, width: 400, explanation: "Soft tissue", function: .sigmoid)))

        guard case .window(_, _, let explanation, let function)? = parsed.voiLUT else {
            return XCTFail("expected a window VOI LUT")
        }
        XCTAssertEqual(function, .sigmoid)
        XCTAssertEqual(explanation, "Soft tissue")
    }

    // MARK: - Annotations

    private func annotatedState() -> GrayscalePresentationState {
        GrayscalePresentationState(
            sopInstanceUID: "1.2.3.4.5.99.2",
            presentationLabel: "Marked up",
            referencedSeries: [
                ReferencedSeries(
                    seriesInstanceUID: "1.2.3.4.5.6",
                    referencedImages: [
                        ReferencedImage(
                            sopClassUID: imageSOPClassUID,
                            sopInstanceUID: "1.2.3.4.5.6.1")
                    ])
            ],
            graphicLayers: [
                GraphicLayer(
                    name: "DRAWINGS", order: 1,
                    description: "Reader-drawn text and arrows",
                    recommendedRGBValue: (red: 65535, green: 65535, blue: 0))
            ],
            graphicAnnotations: [
                GraphicAnnotation(
                    layer: "DRAWINGS",
                    referencedImages: [
                        ReferencedImage(
                            sopClassUID: imageSOPClassUID,
                            sopInstanceUID: "1.2.3.4.5.6.1")
                    ],
                    graphicObjects: [
                        GraphicObject(
                            type: .polyline,
                            data: [10.5, 20.5, 100, 200],
                            filled: false,
                            units: .pixel)
                    ],
                    textObjects: [
                        TextObject(
                            text: "Nodule",
                            boundingBoxTopLeft: (column: 30, row: 40),
                            boundingBoxBottomRight: (column: 130, row: 60),
                            anchorPoint: (column: 30, row: 40),
                            anchorPointVisible: false,
                            boundingBoxUnits: .pixel,
                            anchorPointUnits: .pixel)
                    ])
            ])
    }

    func test_roundTrip_preservesGraphicLayer() throws {
        let parsed = try roundTrip(annotatedState())

        XCTAssertEqual(parsed.graphicLayers.count, 1)
        let layer = try XCTUnwrap(parsed.graphicLayers.first)
        XCTAssertEqual(layer.name, "DRAWINGS")
        XCTAssertEqual(layer.order, 1)
        XCTAssertEqual(layer.description, "Reader-drawn text and arrows")
        XCTAssertEqual(layer.recommendedRGBValue?.red, 65535)
        XCTAssertEqual(layer.recommendedRGBValue?.blue, 0)
    }

    func test_roundTrip_preservesGraphicObject() throws {
        let parsed = try roundTrip(annotatedState())

        let annotation = try XCTUnwrap(parsed.graphicAnnotations.first)
        XCTAssertEqual(annotation.layer, "DRAWINGS")
        XCTAssertEqual(annotation.referencedImages.map(\.sopInstanceUID), ["1.2.3.4.5.6.1"])
        let graphic = try XCTUnwrap(annotation.graphicObjects.first)
        XCTAssertEqual(graphic.type, .polyline)
        XCTAssertEqual(graphic.data, [10.5, 20.5, 100, 200])
        XCTAssertEqual(graphic.units, .pixel)
        XCTAssertFalse(graphic.filled)
    }

    func test_roundTrip_preservesTextObject() throws {
        let parsed = try roundTrip(annotatedState())

        let text = try XCTUnwrap(parsed.graphicAnnotations.first?.textObjects.first)
        XCTAssertEqual(text.text, "Nodule")
        XCTAssertEqual(text.boundingBoxTopLeft.column, 30)
        XCTAssertEqual(text.boundingBoxBottomRight.row, 60)
        XCTAssertEqual(text.anchorPoint?.column, 30)
        XCTAssertFalse(text.anchorPointVisible)
        XCTAssertEqual(text.boundingBoxUnits, .pixel)
    }

    /// The words are written to the Text Object's own tag (0070,0006), not
    /// SR's Text Value — but files written while the parser read the wrong tag
    /// must keep parsing.
    func test_parse_fallsBackToLegacyTextValueTag() throws {
        var dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: annotatedState(),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)
        XCTAssertNotNil(dataSet[.graphicAnnotationSequence])

        // Rewrite the annotation's text object with the legacy tag only.
        let annotationItems = try XCTUnwrap(dataSet[.graphicAnnotationSequence]?.sequenceItems)
        let rebuilt = annotationItems.map { item -> SequenceItem in
            var elements = item.elements.values.filter { $0.tag != .textObjectSequence }
            elements.append(DataElement(
                tag: .textObjectSequence, vr: .SQ, length: 0, valueData: Data(),
                sequenceItems: [SequenceItem(elements: [
                    DataElement.string(tag: .textValue, vr: .ST, value: "Legacy"),
                    DataElement.string(
                        tag: .boundingBoxTopLeftHandCorner, vr: .DS, value: "1\\2"),
                    DataElement.string(
                        tag: .boundingBoxBottomRightHandCorner, vr: .DS, value: "3\\4")
                ])]))
            return SequenceItem(elements: elements)
        }
        dataSet[.graphicAnnotationSequence] = DataElement(
            tag: .graphicAnnotationSequence, vr: .SQ, length: 0, valueData: Data(),
            sequenceItems: rebuilt)

        let parsed = try GrayscalePresentationStateParser().parse(dataSet: dataSet)
        XCTAssertEqual(parsed.graphicAnnotations.first?.textObjects.first?.text, "Legacy")
    }

    // MARK: - Value Representation conformance
    //
    // The builder passes a VR by hand at every call site and nothing checked
    // those against the dictionary, so it wrote these binary attributes as
    // IS/DS text. The round trip still passed — the parser read the same wrong
    // form back — while `dcmpschk` rejected the file at the first one:
    //
    //     Error: Unexpected Value Representation.
    //        Affected VR       : [IS], should be [US] according to data dictionary.
    //        Affected attribute: (0070,0042) ImageRotation
    //
    // `test_build_writesEveryElementWithItsDictionaryVR` is the general guard:
    // it walks everything written, nested sequences included, and compares each
    // VR against DICOMKit's own DataElementDictionary. The tests after it pin
    // the specific attributes that were wrong, with their values.

    private func annotatedDataSet() -> DataSet {
        GrayscalePresentationStateBuilder().buildDataSet(
            from: annotatedState(),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)
    }

    /// Every element the builder writes must carry the VR the standard
    /// dictionary gives its tag. This is the test that would have caught the
    /// original `dcmpschk` failure, and it catches the next one for free.
    func test_build_writesEveryElementWithItsDictionaryVR() throws {
        var offenders: [String] = []

        func check(_ elements: [DataElement], path: String) {
            for element in elements {
                // Group-length and private tags are not in the dictionary.
                guard element.tag.element != 0x0000, !element.tag.isPrivate,
                      let entry = DataElementDictionary.lookup(tag: element.tag)
                else { continue }

                // Sequences carry SQ regardless; recurse into their items.
                if element.vr == .SQ {
                    for (index, item) in (element.sequenceItems ?? []).enumerated() {
                        check(Array(item.elements.values),
                              path: "\(path)\(entry.keyword)[\(index)]/")
                    }
                    continue
                }

                // `xs`-style tags list more than one legal VR (US or SS, keyed
                // to Pixel Representation); any of the listed ones is correct.
                if !entry.vr.contains(element.vr) {
                    offenders.append(
                        "\(path)\(entry.keyword) \(element.tag) is \(element.vr), "
                        + "should be \(entry.vr.map(String.init(describing:)).joined(separator: " or "))")
                }
            }
        }

        // A state exercising every module the builder writes.
        var annotated = annotatedState()
        annotated = GrayscalePresentationState(
            sopInstanceUID: annotated.sopInstanceUID,
            instanceNumber: 1,
            presentationLabel: annotated.presentationLabel,
            presentationCreationDate: DICOMDate(year: 2026, month: 8, day: 18),
            presentationCreationTime: DICOMTime(hour: 14, minute: 30, second: 0),
            referencedSeries: annotated.referencedSeries,
            voiLUT: .window(center: -600, width: 1500, explanation: "Lung", function: .sigmoid),
            presentationLUT: .inverse,
            spatialTransformation: SpatialTransformation(rotation: 270, horizontalFlip: true),
            displayedArea: DisplayedArea(
                topLeft: (column: 10, row: 20),
                bottomRight: (column: 210, row: 220),
                sizeMode: .scaleToFit),
            graphicLayers: annotated.graphicLayers,
            graphicAnnotations: annotated.graphicAnnotations)

        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: annotated,
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        check(Array(dataSet.allElements), path: "")
        XCTAssertEqual(offenders, [], "VRs disagreeing with the data dictionary")
    }

    /// C.10.4 makes Presentation Pixel Spacing / Aspect Ratio Type 1C: one of
    /// them must appear in every Displayed Area item. With neither, dcmpschk
    /// rejects the object even though every VR is right.
    func test_build_writesPresentationPixelAspectRatioInDisplayedArea() throws {
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        let item = try XCTUnwrap(dataSet[.displayedAreaSelectionSequence]?.sequenceItems?.first)
        let hasSpacing = item[.presentationPixelSpacing] != nil
        let ratio = item[.presentationPixelAspectRatio]
        XCTAssertTrue(hasSpacing || ratio != nil,
                      "one of (0070,0101) or (0070,0102) is required")
        XCTAssertEqual(ratio?.vr, .IS)
        XCTAssertEqual(ratio?.integerStringValues?.map(\.value), [1, 1])
    }

    // MARK: - Displayed Area (PS3.3 Table C.10-4)

    /// Every Type 1 attribute of the Displayed Area item: the two corners and
    /// Presentation Size Mode, plus the 1C aspect ratio that stands in for a
    /// spacing the builder does not know.
    func test_build_writesDisplayedAreaType1Attributes() throws {
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        let item = try XCTUnwrap(dataSet[.displayedAreaSelectionSequence]?.sequenceItems?.first)
        XCTAssertEqual(item[.displayedAreaTopLeftHandCorner]?.int32Values, [10, 20])
        XCTAssertEqual(item[.displayedAreaBottomRightHandCorner]?.int32Values, [210, 220])
        XCTAssertEqual(item.string(for: .presentationSizeMode), "SCALE TO FIT")
        XCTAssertNotNil(item[.presentationPixelAspectRatio])
        XCTAssertNil(item[.presentationPixelSpacing])
        XCTAssertNil(item[.presentationPixelMagnificationRatio],
                     "(0070,0103) is 1C on MAGNIFY only")
    }

    /// TRUE SIZE: Presentation Pixel Spacing (0070,0101) is required, row
    /// spacing then column spacing, and the aspect ratio — "required if
    /// Presentation Pixel Spacing is not present" — must then be absent.
    func test_roundTrip_trueSize_carriesPixelSpacing() throws {
        let area = DisplayedArea(
            topLeft: (column: 1, row: 1), bottomRight: (column: 512, row: 512),
            sizeMode: .trueSize, pixelSpacing: (row: 0.5, column: 0.25))
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(area: area),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        let item = try XCTUnwrap(dataSet[.displayedAreaSelectionSequence]?.sequenceItems?.first)
        XCTAssertEqual(item.string(for: .presentationSizeMode), "TRUE SIZE")
        let spacing = try XCTUnwrap(item[.presentationPixelSpacing])
        XCTAssertEqual(spacing.vr, .DS)
        XCTAssertEqual(spacing.decimalStringValues?.map(\.value), [0.5, 0.25])
        XCTAssertNil(item[.presentationPixelAspectRatio])

        let parsed = try GrayscalePresentationStateParser().parse(dataSet: dataSet)
        XCTAssertEqual(parsed.displayedArea?.sizeMode, .trueSize)
        XCTAssertEqual(parsed.displayedArea?.pixelSpacing?.row, 0.5)
        XCTAssertEqual(parsed.displayedArea?.pixelSpacing?.column, 0.25)
        XCTAssertEqual(parsed.displayedArea?.verticalToHorizontalAspect, 2)
    }

    /// MAGNIFY: Presentation Pixel Magnification Ratio (0070,0103), FL, is
    /// required; the aspect ratio the state names goes out as IS.
    func test_roundTrip_magnify_carriesMagnificationRatioAndAspectRatio() throws {
        let area = DisplayedArea(
            topLeft: (column: 100, row: 100), bottomRight: (column: 300, row: 200),
            sizeMode: .magnify, pixelAspectRatio: (vertical: 2, horizontal: 1),
            magnificationRatio: 2.5)
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(area: area),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        let item = try XCTUnwrap(dataSet[.displayedAreaSelectionSequence]?.sequenceItems?.first)
        XCTAssertEqual(item.string(for: .presentationSizeMode), "MAGNIFY")
        let ratio = try XCTUnwrap(item[.presentationPixelMagnificationRatio])
        XCTAssertEqual(ratio.vr, .FL)
        XCTAssertEqual(item[.presentationPixelAspectRatio]?.integerStringValues?.map(\.value), [2, 1])

        let parsed = try GrayscalePresentationStateParser().parse(dataSet: dataSet)
        XCTAssertEqual(parsed.displayedArea?.sizeMode, .magnify)
        XCTAssertEqual(parsed.displayedArea?.magnificationRatio, 2.5)
        XCTAssertEqual(parsed.displayedArea?.pixelAspectRatio?.vertical, 2)
        XCTAssertEqual(parsed.displayedArea?.pixelAspectRatio?.horizontal, 1)
    }

    /// A TRUE SIZE area without a spacing cannot be written as TRUE SIZE — the
    /// Type 1C value it requires does not exist — so the builder writes the
    /// mode that needs nothing, and `validate` names the reason first.
    func test_build_downgradesTrueSizeWithoutSpacingAndValidateSaysWhy() throws {
        let area = DisplayedArea(
            topLeft: (column: 1, row: 1), bottomRight: (column: 512, row: 512),
            sizeMode: .trueSize)
        XCTAssertThrowsError(try GrayscalePresentationStateBuilder().validate(state(area: area))) {
            XCTAssertEqual(
                $0 as? GrayscalePresentationStateBuilder.ValidationError,
                .displayedArea(.trueSizeWithoutPixelSpacing))
        }
        XCTAssertThrowsError(try DisplayedArea(
            topLeft: (column: 1, row: 1), bottomRight: (column: 2, row: 2),
            sizeMode: .magnify).validate())

        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(area: area),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)
        let item = try XCTUnwrap(dataSet[.displayedAreaSelectionSequence]?.sequenceItems?.first)
        XCTAssertEqual(item.string(for: .presentationSizeMode), "SCALE TO FIT")
    }

    /// Displayed Area Selection Sequence is Type 1. A state with no area still
    /// produces one when the builder is told the image size — the whole image,
    /// which is what the absence meant — and `validate` refuses when it is not.
    func test_build_writesWholeImageDisplayedAreaFromImageSize() throws {
        let builder = GrayscalePresentationStateBuilder()
        XCTAssertThrowsError(try builder.validate(state(area: nil))) {
            XCTAssertEqual(
                $0 as? GrayscalePresentationStateBuilder.ValidationError, .missingDisplayedArea)
        }
        XCTAssertNoThrow(try builder.validate(state(area: nil), imageSize: (columns: 640, rows: 480)))

        let dataSet = builder.buildDataSet(
            from: state(area: nil),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900,
            imageSize: (columns: 640, rows: 480))
        let parsed = try GrayscalePresentationStateParser().parse(dataSet: dataSet)
        XCTAssertEqual(parsed.displayedArea?.topLeft.column, 1)
        XCTAssertEqual(parsed.displayedArea?.topLeft.row, 1)
        XCTAssertEqual(parsed.displayedArea?.bottomRight.column, 640)
        XCTAssertEqual(parsed.displayedArea?.bottomRight.row, 480)
        XCTAssertEqual(parsed.displayedArea?.sizeMode, .scaleToFit)
    }

    // MARK: - Graphic Annotation Units (PS3.3 Table C.10-5)

    /// MATRIX is the third Enumerated Value of the units attributes; a graphic
    /// and a text object drawn in Total Pixel Matrix space round trip as such.
    func test_roundTrip_preservesMatrixUnits() throws {
        XCTAssertEqual(AnnotationUnits.matrix.rawValue, "MATRIX")
        XCTAssertEqual(AnnotationUnits.allCases.map(\.rawValue), ["PIXEL", "DISPLAY", "MATRIX"])

        let wsiSOPClass = "1.2.840.10008.5.1.4.1.1.77.1.6"
        let base = annotatedState()
        let annotated = GrayscalePresentationState(
            sopInstanceUID: base.sopInstanceUID,
            referencedSeries: [
                ReferencedSeries(
                    seriesInstanceUID: "1.2.3.4.5.6",
                    referencedImages: [ReferencedImage(sopClassUID: wsiSOPClass, sopInstanceUID: "1.2.3.4.5.6.1")])
            ],
            graphicLayers: base.graphicLayers,
            graphicAnnotations: [
                GraphicAnnotation(
                    layer: "DRAWINGS",
                    referencedImages: [ReferencedImage(sopClassUID: wsiSOPClass, sopInstanceUID: "1.2.3.4.5.6.1")],
                    graphicObjects: [
                        GraphicObject(type: .point, data: [40000.5, 30000.5], units: .matrix)
                    ],
                    textObjects: [
                        TextObject(
                            text: "Tumour",
                            boundingBoxTopLeft: (column: 40000, row: 30000),
                            boundingBoxBottomRight: (column: 41000, row: 30500),
                            anchorPoint: (column: 40000.5, row: 30000.5),
                            anchorPointVisible: true,
                            boundingBoxUnits: .matrix,
                            anchorPointUnits: .matrix)
                    ])
            ])

        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: annotated,
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)
        let graphicItem = try XCTUnwrap(
            dataSet[.graphicAnnotationSequence]?.sequenceItems?.first?[.graphicObjectSequence]?.sequenceItems?.first)
        XCTAssertEqual(graphicItem.string(for: .graphicAnnotationUnits), "MATRIX")

        let parsed = try GrayscalePresentationStateParser().parse(dataSet: dataSet)
        let annotation = try XCTUnwrap(parsed.graphicAnnotations.first)
        XCTAssertEqual(annotation.graphicObjects.first?.units, .matrix)
        XCTAssertEqual(annotation.graphicObjects.first?.data, [40000.5, 30000.5])
        XCTAssertEqual(annotation.textObjects.first?.boundingBoxUnits, .matrix)
        XCTAssertEqual(annotation.textObjects.first?.anchorPointUnits, .matrix)
        XCTAssertTrue(AnnotationUnits.matrix.isImageRelative)
        XCTAssertFalse(AnnotationUnits.display.isImageRelative)
    }

    // MARK: - Shutter colour (PS3.3 Tables C.7-17a, C.11.12-1)

    /// Shutter Presentation Color CIELab Value (0018,1624) is Type 1C only for
    /// classes other than GSPS, so the grayscale builder leaves it out even
    /// when the state names one; the parser still reads it from files that
    /// carry it, three US values per C.10.7.1.1.
    func test_gsps_omitsShutterColourButParserReadsIt() throws {
        let colour = CIELabColor(sRGB: 65535, green: 0, blue: 0)
        let shuttered = GrayscalePresentationState(
            sopInstanceUID: "1.2.3.4.5.99.1",
            referencedSeries: state().referencedSeries,
            displayedArea: state().displayedArea,
            shutters: [.rectangular(left: 10, right: 100, top: 10, bottom: 100, presentationValue: 0)],
            shutterPresentationColor: colour)
        var dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: shuttered,
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)
        let colourTag = Tag(group: 0x0018, element: 0x1624)
        XCTAssertNil(dataSet[colourTag])
        XCTAssertNil(try GrayscalePresentationStateParser().parse(dataSet: dataSet).shutterPresentationColor)

        _ = dataSet.setIntegers(colour.encodedValues, for: colourTag)
        XCTAssertEqual(dataSet[colourTag]?.vr, .US)
        let parsed = try GrayscalePresentationStateParser().parse(dataSet: dataSet)
        XCTAssertEqual(parsed.shutterPresentationColor, colour)
        XCTAssertEqual(parsed.shutterPresentationColor?.sRGBValue.red, 65535)
        XCTAssertLessThan(parsed.shutterPresentationColor?.sRGBValue.green ?? 65535, 300)
    }

    /// C.10.7.1.1: 0x8080 is a* = b* = 0 and L* scales over the full 16 bits.
    func test_cieLabColor_encoding() {
        XCTAssertEqual(CIELabColor.shutterBlack.encodedValues, [0, 0x8080, 0x8080])
        XCTAssertEqual(CIELabColor(encodedValues: [65535, 0x8080, 0x8080]),
                       CIELabColor(l: 65535, a: 0x8080, b: 0x8080))
        XCTAssertNil(CIELabColor(encodedValues: [1, 2]))
        let white = CIELabColor(sRGB: 65535, green: 65535, blue: 65535)
        XCTAssertEqual(white.l, 65535)
        XCTAssertEqual(white.a, 0x8080, accuracy: 2)
        XCTAssertEqual(white.b, 0x8080, accuracy: 2)
    }

    func test_build_writesImageRotationAsUS() throws {
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(spatial: SpatialTransformation(rotation: 90, horizontalFlip: false)),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        let element = try XCTUnwrap(dataSet[.imageRotation])
        XCTAssertEqual(element.vr, .US, "(0070,0042) Image Rotation is US")
        XCTAssertEqual(element.uint16Value, 90)
    }

    func test_build_writesDisplayedAreaCornersAsSL() throws {
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        let item = try XCTUnwrap(dataSet[.displayedAreaSelectionSequence]?.sequenceItems?.first)
        let topLeft = try XCTUnwrap(item[.displayedAreaTopLeftHandCorner])
        let bottomRight = try XCTUnwrap(item[.displayedAreaBottomRightHandCorner])

        XCTAssertEqual(topLeft.vr, .SL, "(0070,0052) is SL")
        XCTAssertEqual(bottomRight.vr, .SL, "(0070,0053) is SL")
        XCTAssertEqual(topLeft.int32Values, [10, 20])
        XCTAssertEqual(bottomRight.int32Values, [210, 220])
    }

    func test_build_writesGraphicLayerRecommendedValuesAsUS() throws {
        let item = try XCTUnwrap(annotatedDataSet()[.graphicLayerSequence]?.sequenceItems?.first)

        // (0070,0067) Graphic Layer Recommended Display RGB Value is retired (PS3.6);
        // the colour is written as (0070,0401) CIELab per PS3.3 C.10.7.1.1
        XCTAssertNil(item[.graphicLayerRecommendedDisplayRGBValue])
        let lab = try XCTUnwrap(item[DICOMCore.Tag(group: 0x0070, element: 0x0401)])
        XCTAssertEqual(lab.vr, .US, "(0070,0401) is US")
        let encoded = try XCTUnwrap(lab.uint16Values?.map(Int.init))
        XCTAssertEqual(encoded.count, 3)

        // The yellow the state carries comes back within 16-bit rounding
        let rgb = try XCTUnwrap(GrayscalePresentationStateBuilder.rgb(fromCIELabEncoded: encoded))
        XCTAssertEqual(rgb.red, 65535, accuracy: 300)
        XCTAssertEqual(rgb.green, 65535, accuracy: 300)
        XCTAssertEqual(rgb.blue, 0, accuracy: 300)
    }

    func test_cieLabEncoding_followsC10711() {
        // C.10.7.1.1: L = 100 is 0xFFFF; a* = b* = 0 is 0x8080
        XCTAssertEqual(GrayscalePresentationStateBuilder.cieLabEncoded(from: (red: 65535, green: 65535, blue: 65535)),
                       [65535, 32896, 32896])
        XCTAssertEqual(GrayscalePresentationStateBuilder.cieLabEncoded(from: (red: 0, green: 0, blue: 0)),
                       [0, 32896, 32896])
    }

    func test_build_writesGraphicDataAsFL() throws {
        let annotation = try XCTUnwrap(
            annotatedDataSet()[.graphicAnnotationSequence]?.sequenceItems?.first)
        let graphic = try XCTUnwrap(
            annotation[.graphicObjectSequence]?.sequenceItems?.first)
        // `Tag.graphicData` is declared in both DICOMCore and SRDocumentSerializer;
        // name the tag outright rather than depend on which one resolves.
        let data = try XCTUnwrap(graphic[DICOMCore.Tag(group: 0x0070, element: 0x0022)])

        XCTAssertEqual(data.vr, .FL, "(0070,0022) Graphic Data is FL")
        XCTAssertEqual(data.float32Values, [10.5, 20.5, 100, 200])
        // Both are Type 1 whenever Graphic Data is present.
        XCTAssertEqual(graphic[.graphicDimensions]?.uint16Value, 2)
        XCTAssertEqual(graphic[.numberOfGraphicPoints]?.uint16Value, 2)
    }

    func test_build_writesTextObjectCoordinatesAsFL() throws {
        let annotation = try XCTUnwrap(
            annotatedDataSet()[.graphicAnnotationSequence]?.sequenceItems?.first)
        let text = try XCTUnwrap(annotation[.textObjectSequence]?.sequenceItems?.first)

        let topLeft = try XCTUnwrap(text[.boundingBoxTopLeftHandCorner])
        let bottomRight = try XCTUnwrap(text[.boundingBoxBottomRightHandCorner])
        let anchor = try XCTUnwrap(text[.anchorPoint])

        XCTAssertEqual(topLeft.vr, .FL, "(0070,0010) is FL")
        XCTAssertEqual(bottomRight.vr, .FL, "(0070,0011) is FL")
        XCTAssertEqual(anchor.vr, .FL, "(0070,0014) is FL")
        XCTAssertEqual(topLeft.float32Values, [30, 40])
        XCTAssertEqual(bottomRight.float32Values, [130, 60])
        XCTAssertEqual(anchor.float32Values, [30, 40])
    }

    /// States written before the VRs were corrected carry IS/DS text in these
    /// same tags. The parser reads either form, so a reader's saved zoom, pan,
    /// and layer colour survive the change.
    func test_parse_acceptsLegacyStringVRs() throws {
        var dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(spatial: SpatialTransformation(rotation: 270, horizontalFlip: false)),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        // Rewrite rotation and the displayed area the way older builds did.
        dataSet.setString("270", for: .imageRotation, vr: .IS)
        dataSet[.displayedAreaSelectionSequence] = DataElement(
            tag: .displayedAreaSelectionSequence, vr: .SQ, length: 0, valueData: Data(),
            sequenceItems: [SequenceItem(elements: [
                DataElement.string(
                    tag: .displayedAreaTopLeftHandCorner, vr: .IS, value: "11\\22"),
                DataElement.string(
                    tag: .displayedAreaBottomRightHandCorner, vr: .IS, value: "211\\222"),
                DataElement.string(
                    tag: .presentationSizeMode, vr: .CS, value: "SCALE TO FIT")
            ])])

        let parsed = try GrayscalePresentationStateParser().parse(dataSet: dataSet)
        XCTAssertEqual(parsed.spatialTransformation?.rotation, 270)
        XCTAssertEqual(parsed.displayedArea?.topLeft.column, 11)
        XCTAssertEqual(parsed.displayedArea?.topLeft.row, 22)
        XCTAssertEqual(parsed.displayedArea?.bottomRight.column, 211)
        XCTAssertEqual(parsed.displayedArea?.bottomRight.row, 222)
    }

    func test_build_omitsAnnotationSequencesWhenNothingIsDrawn() {
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        XCTAssertNil(dataSet[.graphicLayerSequence])
        XCTAssertNil(dataSet[.graphicAnnotationSequence])
    }

    // MARK: - Content Label

    /// Content Label is type 1 and CS-valued. A reader typing an ordinary name
    /// must still produce a conformant object.
    func test_contentLabel_foldsUserTextToLegalCS() {
        XCTAssertEqual(
            GrayscalePresentationStateBuilder.contentLabel(from: "Lung window"),
            "LUNG WINDOW")
        XCTAssertEqual(
            GrayscalePresentationStateBuilder.contentLabel(from: "bone+zoom"),
            "BONE_ZOOM")
    }

    func test_contentLabel_truncatesToSixteenCharacters() {
        let label = GrayscalePresentationStateBuilder.contentLabel(
            from: "A very long presentation state name")
        XCTAssertLessThanOrEqual(label.count, 16)
    }

    func test_contentLabel_fallsBackWhenEmpty() {
        XCTAssertEqual(
            GrayscalePresentationStateBuilder.contentLabel(from: nil), "PRESENTATION")
        XCTAssertEqual(
            GrayscalePresentationStateBuilder.contentLabel(from: ""), "PRESENTATION")
        // Folds to underscores only, which would be a meaningless label.
        XCTAssertEqual(
            GrayscalePresentationStateBuilder.contentLabel(from: "   "), "PRESENTATION")
    }

    /// The human-readable name survives in full even when Content Label had to
    /// be folded, which is what the picker shows.
    func test_build_keepsUnfoldedLabelInContentDescription() {
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(label: "Lung window (thin)"),
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)

        XCTAssertEqual(dataSet.string(for: .contentDescription), "Lung window (thin)")
    }

    // MARK: - Decimal formatting

    func test_decimalString_writesWholeNumbersWithoutDecimalPoint() {
        XCTAssertEqual(GrayscalePresentationStateBuilder.decimalString(-600), "-600")
        XCTAssertEqual(GrayscalePresentationStateBuilder.decimalString(1500), "1500")
    }

    func test_decimalString_staysWithinDSLengthLimit() {
        let value = GrayscalePresentationStateBuilder.decimalString(1234.56789012345)
        XCTAssertLessThanOrEqual(value.count, 16)
    }
}
