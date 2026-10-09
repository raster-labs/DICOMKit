//
// ColorPresentationStateBuilderTests.swift
// DICOMKit
//
// The Color Softcopy Presentation State builder writes exactly the modules of
// PS3.3 Table A.33.2-1: what the grayscale IOD has minus its three LUT modules,
// plus a mandatory ICC Profile. These tests pin the SOP class, the presence of
// every Type 1 attribute, the absence of the modules the table omits, and the
// round trip through the shared parser.
//

import XCTest
import DICOMCore
import DICOMDictionary
@testable import DICOMKit

final class ColorPresentationStateBuilderTests: XCTestCase {

    // MARK: - Fixtures

    /// Ultrasound Image Storage: a colour image class.
    private let imageSOPClassUID = "1.2.840.10008.5.1.4.1.1.6.1"

    private func context() -> PresentationStatePatientContext {
        PresentationStatePatientContext(
            patientName: "DOE^JANE",
            patientID: "12345",
            studyInstanceUID: "1.2.3.4.5",
            studyDate: "20260101")
    }

    private func state(
        iccProfile: ICCProfile? = nil,
        shutters: [DisplayShutter] = [],
        shutterColour: CIELabColor? = nil,
        area: DisplayedArea? = DisplayedArea(
            topLeft: (column: 10, row: 20), bottomRight: (column: 210, row: 220))
    ) -> ColorPresentationState {
        ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.99.2",
            instanceNumber: 1,
            presentationLabel: "Doppler view",
            presentationCreationDate: DICOMDate(year: 2026, month: 9, day: 29),
            presentationCreationTime: DICOMTime(hour: 9, minute: 0, second: 0),
            referencedSeries: [
                ReferencedSeries(
                    seriesInstanceUID: "1.2.3.4.5.6",
                    referencedImages: [
                        ReferencedImage(sopClassUID: imageSOPClassUID, sopInstanceUID: "1.2.3.4.5.6.1")
                    ])
            ],
            iccProfile: iccProfile,
            spatialTransformation: SpatialTransformation(rotation: 90, horizontalFlip: false),
            displayedArea: area,
            graphicLayers: [
                GraphicLayer(name: "MEASURE", order: 1,
                             recommendedRGBValue: (red: 0, green: 65535, blue: 0))
            ],
            graphicAnnotations: [
                GraphicAnnotation(
                    layer: "MEASURE",
                    referencedImages: [
                        ReferencedImage(sopClassUID: imageSOPClassUID, sopInstanceUID: "1.2.3.4.5.6.1")
                    ],
                    graphicObjects: [
                        GraphicObject(type: .polyline, data: [10, 10, 50, 60], units: .pixel)
                    ])
            ],
            shutters: shutters,
            shutterPresentationColor: shutterColour)
    }

    private func build(_ state: ColorPresentationState) -> DataSet {
        ColorPresentationStateBuilder().buildDataSet(
            from: state,
            patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900",
            seriesNumber: 900)
    }

    // MARK: - Identity

    /// PS3.6 Table A-1: Color Softcopy Presentation State Storage.
    func test_sopClassUID_isPinned() {
        XCTAssertEqual(ColorPresentationStateBuilder.sopClassUID, "1.2.840.10008.5.1.4.1.1.11.2")
        XCTAssertEqual(ColorPresentationStateBuilder.sopClassUID, .colorSoftcopyPresentationStateStorage)
        XCTAssertEqual(ColorPresentationStateBuilder.modality, "PR")
    }

    func test_build_writesCSPSSOPClassAndPRModality() {
        let dataSet = build(state())
        XCTAssertEqual(dataSet.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.11.2")
        XCTAssertEqual(dataSet.string(for: .sopInstanceUID), "1.2.3.4.5.99.2")
        XCTAssertEqual(dataSet.string(for: .modality), "PR")
        XCTAssertEqual(dataSet.string(for: .seriesInstanceUID), "1.2.3.4.5.900")
        XCTAssertEqual(dataSet.string(for: .studyInstanceUID), "1.2.3.4.5")
    }

    // MARK: - Table A.33.2-1 module set

    /// Every Type 1 attribute of the mandatory modules: Presentation State
    /// Identification (Table C.11.10-1 and 10-12), Relationship (Table
    /// C.11.11-1b), Displayed Area (Table C.10-4), ICC Profile (Table C.11.15-1).
    func test_build_writesEveryType1AttributeOfTheMandatoryModules() throws {
        let dataSet = build(state())

        XCTAssertNotNil(dataSet[.presentationCreationDate])
        XCTAssertNotNil(dataSet[.presentationCreationTime])
        XCTAssertEqual(dataSet.string(for: .contentLabel), "DOPPLER VIEW")
        XCTAssertNotNil(dataSet[.contentCreatorName], "Type 3 (Table 10.9.3-1 via Table 10-12), written zero length when unknown")

        let series = try XCTUnwrap(dataSet[.referencedSeriesSequence]?.sequenceItems?.first)
        XCTAssertEqual(series.string(for: .seriesInstanceUID), "1.2.3.4.5.6")
        let image = try XCTUnwrap(series[.referencedImageSequence]?.sequenceItems?.first)
        XCTAssertEqual(image.string(for: .referencedSOPClassUID), imageSOPClassUID)

        let area = try XCTUnwrap(dataSet[.displayedAreaSelectionSequence]?.sequenceItems?.first)
        XCTAssertEqual(area[.displayedAreaTopLeftHandCorner]?.int32Values, [10, 20])
        XCTAssertEqual(area[.displayedAreaBottomRightHandCorner]?.int32Values, [210, 220])
        XCTAssertEqual(area.string(for: .presentationSizeMode), "SCALE TO FIT")
        XCTAssertNotNil(area[.presentationPixelAspectRatio])

        let profile = try XCTUnwrap(dataSet[.iccProfile])
        XCTAssertEqual(profile.vr, .OB)
        XCTAssertFalse(profile.valueData.isEmpty)
        XCTAssertEqual(dataSet.string(for: .colorSpace), "SRGB")
        XCTAssertNoThrow(try ICCProfileParser.parse(profile.valueData))

        XCTAssertEqual(dataSet[.imageRotation]?.uint16Value, 90)
        XCTAssertEqual(dataSet.string(for: .imageHorizontalFlip), "N")
        XCTAssertNotNil(dataSet[.graphicLayerSequence])
        XCTAssertNotNil(dataSet[.graphicAnnotationSequence])
    }

    /// Table A.33.2-1 has no Modality LUT, Softcopy VOI LUT or Softcopy
    /// Presentation LUT module, so none of their attributes may appear.
    func test_build_omitsTheLUTModulesTheIODDoesNotHave() {
        let dataSet = build(state())
        for tag: Tag in [.presentationLUTShape, .presentationLUTSequence,
                         .modalityLUTSequence, .rescaleIntercept, .rescaleSlope, .rescaleType,
                         .softcopyVOILUTSequence, .windowCenter, .windowWidth, .voiLUTSequence] {
            XCTAssertNil(dataSet[tag], "\(tag) belongs to a module Table A.33.2-1 omits")
        }
    }

    /// A supplied profile is written as given; its Color Space term follows
    /// C.11.15.1.2 and is left out for a space the terms do not name.
    func test_build_writesSuppliedICCProfileAndItsColorSpaceTerm() {
        let adobe = ICCProfile(profileData: Data([0xAA, 0xBB, 0xCC]), colorSpace: .adobeRGB)
        let dataSet = build(state(iccProfile: adobe))
        XCTAssertEqual(dataSet[.iccProfile]?.valueData, Data([0xAA, 0xBB, 0xCC]))
        XCTAssertEqual(dataSet.string(for: .colorSpace), "ADOBERGB")

        let custom = ICCProfile(profileData: Data([0x01]), colorSpace: .custom)
        XCTAssertNil(build(state(iccProfile: custom))[.colorSpace])
        XCTAssertEqual(ColorPresentationStateBuilder.colorSpaceTerm(for:
            ICCProfile(profileData: Data(), colorSpace: .proPhotoRGB)), "ROMMRGB")
        XCTAssertEqual(ColorPresentationStateBuilder.colorSpaceTerm(for:
            ICCProfile(profileData: Data(), colorSpace: .displayP3)), "DISPLAYP3")
    }

    /// Graphic Layer colours go out as CIELab (Table C.10-7 lists only the
    /// CIELab value); the retired RGB tag is never written.
    func test_build_writesLayerColourAsCIELab() throws {
        let layer = try XCTUnwrap(build(state())[.graphicLayerSequence]?.sequenceItems?.first)
        XCTAssertNotNil(layer[Tag(group: 0x0070, element: 0x0401)])
        XCTAssertNil(layer[.graphicLayerRecommendedDisplayRGBValue])
    }

    // MARK: - Shutter (Tables C.7-17a, C.11.12-1)

    /// In a class other than GSPS the Shutter Presentation Color CIELab Value
    /// is Type 1C with a shutter: written with the state's colour, black when
    /// none was named, absent without a shutter.
    func test_build_writesShutterColourWhenShuttered() throws {
        let colourTag = Tag(group: 0x0018, element: 0x1624)
        let rectangle: DisplayShutter = .rectangular(
            left: 20, right: 400, top: 30, bottom: 300, presentationValue: 0)

        XCTAssertNil(build(state())[colourTag])

        let black = build(state(shutters: [rectangle]))
        XCTAssertEqual(black.string(for: .shutterShape), "RECTANGULAR")
        XCTAssertEqual(black[colourTag]?.uint16Values, [0, 0x8080, 0x8080])
        XCTAssertNotNil(black[.shutterPresentationValue], "1C with a shutter (Table C.11.12-1)")

        let green = CIELabColor(sRGB: 0, green: 65535, blue: 0)
        let dataSet = build(state(shutters: [rectangle], shutterColour: green))
        XCTAssertEqual(dataSet[colourTag]?.vr, .US)
        XCTAssertEqual(dataSet[colourTag]?.uint16Values?.map(Int.init), green.encodedValues)
    }

    // MARK: - Round trip

    /// The shared parser accepts the class; the colour model is rebuilt from
    /// its result plus the ICC profile read from the same data set.
    func test_roundTrip_throughGrayscaleParser() throws {
        let circle: DisplayShutter = .circular(
            centerColumn: 100, centerRow: 120, radius: 50, presentationValue: 0)
        let colour = CIELabColor(l: 30000, a: 0x8080, b: 0x9000)
        let original = state(shutters: [circle], shutterColour: colour)
        let dataSet = build(original)

        let parsed = try GrayscalePresentationStateParser().parse(dataSet: dataSet)
        XCTAssertEqual(parsed.sopClassUID, .colorSoftcopyPresentationStateStorage)
        XCTAssertNil(parsed.voiLUT)
        XCTAssertNil(parsed.modalityLUT)
        XCTAssertNil(parsed.presentationLUT)

        var elements: [Tag: DataElement] = [:]
        for element in dataSet.allElements { elements[element.tag] = element }
        let colourState = ColorPresentationState(
            parsed: parsed, iccProfile: ICCProfile.extract(from: elements))

        XCTAssertEqual(colourState.sopInstanceUID, original.sopInstanceUID)
        // Content Label (0070,0080) is CS, folded from the label; the label
        // itself travels in Content Description (0070,0081).
        XCTAssertEqual(colourState.presentationLabel, "DOPPLER VIEW")
        XCTAssertEqual(colourState.presentationDescription, "Doppler view")
        XCTAssertEqual(colourState.referencedSeries, original.referencedSeries)
        XCTAssertEqual(colourState.spatialTransformation, original.spatialTransformation)
        // The 1\1 aspect ratio the builder supplies (Table C.10-4 1C) comes back.
        XCTAssertEqual(colourState.displayedArea?.topLeft.column, 10)
        XCTAssertEqual(colourState.displayedArea?.bottomRight.row, 220)
        XCTAssertEqual(colourState.displayedArea?.sizeMode, .scaleToFit)
        XCTAssertEqual(colourState.displayedArea?.pixelAspectRatio?.vertical, 1)
        XCTAssertEqual(colourState.displayedArea?.pixelAspectRatio?.horizontal, 1)
        XCTAssertEqual(colourState.graphicLayers.map(\.name), ["MEASURE"])
        XCTAssertEqual(colourState.graphicAnnotations.first?.graphicObjects.first?.data, [10, 10, 50, 60])
        XCTAssertEqual(colourState.shutters, [circle])
        XCTAssertEqual(colourState.shutterPresentationColor, colour)
        XCTAssertEqual(colourState.iccProfile?.colorSpace, .sRGB)
    }

    /// Every element carries the VR the standard dictionary gives its tag.
    func test_build_writesEveryElementWithItsDictionaryVR() {
        var offenders: [String] = []
        func check(_ elements: [DataElement], path: String) {
            for element in elements {
                guard element.tag.element != 0x0000, !element.tag.isPrivate,
                      let entry = DataElementDictionary.lookup(tag: element.tag)
                else { continue }
                if element.vr == .SQ {
                    for (index, item) in (element.sequenceItems ?? []).enumerated() {
                        check(Array(item.elements.values), path: "\(path)\(entry.keyword)[\(index)]/")
                    }
                    continue
                }
                if !entry.vr.contains(element.vr) {
                    offenders.append("\(path)\(entry.keyword) \(element.tag) is \(element.vr)")
                }
            }
        }
        let dataSet = build(state(
            shutters: [.polygonal(vertices: [(column: 1, row: 1), (column: 100, row: 1), (column: 50, row: 80)],
                                  presentationValue: 0)],
            shutterColour: .shutterBlack,
            area: DisplayedArea(
                topLeft: (column: 1, row: 1), bottomRight: (column: 200, row: 200),
                sizeMode: .trueSize, pixelSpacing: (row: 0.1, column: 0.1), magnificationRatio: 2)))
        check(Array(dataSet.allElements), path: "")
        XCTAssertEqual(offenders, [])
    }

    // MARK: - Validation

    func test_validate_requiresADisplayedAreaOrAnImageSize() {
        let builder = ColorPresentationStateBuilder()
        XCTAssertThrowsError(try builder.validate(state(area: nil)))
        XCTAssertNoThrow(try builder.validate(state(area: nil), imageSize: (columns: 800, rows: 600)))
        XCTAssertNoThrow(try builder.validate(state()))

        let dataSet = builder.buildDataSet(
            from: state(area: nil), patient: context(),
            seriesInstanceUID: "1.2.3.4.5.900", seriesNumber: 900,
            imageSize: (columns: 800, rows: 600))
        let area = dataSet[.displayedAreaSelectionSequence]?.sequenceItems?.first
        XCTAssertEqual(area?[.displayedAreaBottomRightHandCorner]?.int32Values, [800, 600])
    }
}
