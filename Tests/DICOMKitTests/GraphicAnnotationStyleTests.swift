//
// GraphicAnnotationStyleTests.swift
// DICOMKit
//
// D39: the Compound Graphic Sequence and the Text, Line and Fill Style
// Sequence Macros of the Graphic Annotation Module, held against PS3.3 2026a
// Tables C.10-5, C.10-5a, C.10-5b, C.10-5c and C.10.5.1.3, and against the
// VRs of PS3.6 Table 6-1. Round trips first: what the builder writes, the
// parser must read back.
//

import XCTest
import DICOMCore
import DICOMDictionary
@testable import DICOMKit

final class GraphicAnnotationStyleTests: XCTestCase {

    private let image = ReferencedImage(sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                                        sopInstanceUID: "1.2.3.4.5.6.1")
    private let yellow = CIELabColor(l: 60000, a: 0x7000, b: 0xE000)
    private let white = CIELabColor(l: 65535, a: 0x8080, b: 0x8080)

    private func context() -> PresentationStatePatientContext {
        PresentationStatePatientContext(patientName: "DOE^JANE", patientID: "1",
                                        studyInstanceUID: "1.2.3.4.5")
    }

    private func state(_ annotation: GraphicAnnotation) -> GrayscalePresentationState {
        GrayscalePresentationState(
            sopInstanceUID: "1.2.3.4.5.99.1",
            referencedSeries: [ReferencedSeries(seriesInstanceUID: "1.2.3.4.5.6", referencedImages: [image])],
            presentationLUT: .identity,
            graphicLayers: [GraphicLayer(name: "L", order: 1)],
            graphicAnnotations: [annotation])
    }

    /// An arrow as C.10.5.1.3.11 states it (anchor, then foot), with its
    /// alternate rendering as a polyline sharing the instance ID.
    private func arrowAnnotation() -> GraphicAnnotation {
        let line = LineStyle(
            onColor: yellow, thickness: 2.5,
            shadow: GraphicShadow(style: .outlined, offsetX: 1.5, color: GraphicShadow.black, opacity: 0.8))
        return GraphicAnnotation(
            layer: "L", referencedImages: [image],
            graphicObjects: [
                GraphicObject(type: .polyline, data: [100, 100, 20, 30], lineStyle: line,
                              compoundGraphicInstanceID: 7, graphicGroupID: 3),
                GraphicObject(type: .circle, data: [50, 50, 60, 50], filled: true,
                              fillStyle: FillStyle(onColor: white, offOpacity: 0.25, mode: .stippled))
            ],
            textObjects: [
                TextObject(text: "Lesion\tA", boundingBoxTopLeft: (10, 10), boundingBoxBottomRight: (60, 20),
                           textStyle: TextStyle(fontName: "Helvetica-Bold", color: yellow,
                                                horizontalAlignment: .center,
                                                shadow: GraphicShadow(style: .outlined, offsetX: 1),
                                                bold: true))
            ],
            compoundGraphics: [
                CompoundGraphic(instanceID: 7, type: .arrow, data: [100, 100, 20, 30],
                                lineStyle: line, graphicGroupID: 3)
            ])
    }

    private func written(_ annotation: GraphicAnnotation) throws -> DataSet {
        let dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state(annotation), patient: context(),
            seriesInstanceUID: "1.2.3.4.5.9", seriesNumber: 9,
            imageSize: (columns: 512, rows: 512))
        // Through bytes, so the VRs are the ones on disk.
        let file = DICOMFile.create(dataSet: dataSet, sopClassUID: GrayscalePresentationStateBuilder.sopClassUID,
                                    sopInstanceUID: "1.2.3.4.5.99.1", transferSyntaxUID: "1.2.840.10008.1.2.1")
        return try DICOMFile.read(from: file.write()).dataSet
    }

    // MARK: - Round trip

    func test_compoundArrowAndStylesRoundTrip() throws {
        let dataSet = try written(arrowAnnotation())
        let parsed = try GrayscalePresentationStateParser().parse(dataSet: dataSet)
        let annotation = try XCTUnwrap(parsed.graphicAnnotations.first)

        let arrow = try XCTUnwrap(annotation.compoundGraphics.first)
        XCTAssertEqual(arrow.instanceID, 7)
        XCTAssertEqual(arrow.type, .arrow)
        XCTAssertEqual(arrow.units, .pixel)
        XCTAssertEqual(arrow.points, [GraphicPoint(column: 100, row: 100), GraphicPoint(column: 20, row: 30)])
        XCTAssertEqual(arrow.lineStyle?.onColor, yellow)
        XCTAssertEqual(arrow.lineStyle?.shadow.style, .outlined)
        XCTAssertEqual(arrow.graphicGroupID, 3)

        let polyline = try XCTUnwrap(annotation.graphicObjects.first)
        XCTAssertEqual(polyline.compoundGraphicInstanceID, 7, "alternate rendering linked (C.10.5.1.3.1)")
        XCTAssertEqual(try XCTUnwrap(polyline.lineStyle?.thickness), 2.5, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(polyline.lineStyle?.shadow.opacity), 0.8, accuracy: 1e-6)

        let circle = annotation.graphicObjects[1]
        XCTAssertEqual(circle.fillStyle?.mode, .stippled)
        XCTAssertEqual(circle.fillStyle?.pattern?.count, 128, "Fill Pattern is 128 bytes (Table C.10-5c)")

        let text = try XCTUnwrap(annotation.textObjects.first)
        XCTAssertEqual(text.textStyle?.color, yellow)
        XCTAssertEqual(text.textStyle?.fontName, "Helvetica-Bold")
        XCTAssertEqual(text.textStyle?.fontNameType, "ISO_32000")
        XCTAssertEqual(text.textStyle?.bold, true)
        XCTAssertEqual(text.textStyle?.horizontalAlignment, .center)
        XCTAssertEqual(text.textStyle?.verticalAlignment, .top, "1C with a bounding box; defaulted")
        XCTAssertEqual(text.text, "Lesion A", "no tab in Unformatted Text Value (Table C.10-5)")
    }

    /// The VR of every new element, as PS3.6 Table 6-1 states it.
    func test_elementsCarryTheDictionaryVRs() throws {
        let dataSet = try written(arrowAnnotation())
        let annotation = try XCTUnwrap(dataSet[.graphicAnnotationSequence]?.sequenceItems?.first)
        let compound = try XCTUnwrap(annotation[.compoundGraphicSequence]?.sequenceItems?.first)
        let line = try XCTUnwrap(compound[.lineStyleSequence]?.sequenceItems?.first)
        let text = try XCTUnwrap(annotation[.textObjectSequence]?.sequenceItems?.first)
        let style = try XCTUnwrap(text[.textStyleSequence]?.sequenceItems?.first)
        let expected: [(SequenceItem, Tag, VR)] = [
            (compound, .compoundGraphicInstanceID, .UL), (compound, .compoundGraphicUnits, .CS),
            (compound, .compoundGraphicType, .CS), (compound, .graphicData, .FL),
            (compound, .graphicGroupID, .UL),
            (line, .patternOnColorCIELabValue, .US), (line, .patternOnOpacity, .FL),
            (line, .lineThickness, .FL), (line, .lineDashingStyle, .CS), (line, .shadowStyle, .CS),
            (line, .shadowOffsetX, .FL), (line, .shadowColorCIELabValue, .US), (line, .shadowOpacity, .FL),
            (style, .fontName, .LO), (style, .fontNameType, .CS), (style, .cssFontName, .LO),
            (style, .textColorCIELabValue, .US), (style, .horizontalAlignment, .CS),
            (style, .verticalAlignment, .CS), (style, .bold, .CS),
        ]
        for (item, tag, vr) in expected {
            XCTAssertEqual(item[tag]?.vr, vr, "\(tag)")
            XCTAssertEqual(DataElementDictionary.lookup(tag: tag)?.vr.first, vr, "dictionary \(tag)")
        }
        // Text Style: Shadow Offset etc. are 1C "not OFF"; OUTLINED here, so present.
        XCTAssertNotNil(style[.shadowOffsetX])
        // Line Style: shadow companions are Type 1 even with OFF.
        let plain = try written(GraphicAnnotation(
            layer: "L", referencedImages: [image],
            graphicObjects: [GraphicObject(type: .polyline, data: [0, 0, 1, 1],
                                           lineStyle: LineStyle(onColor: white, thickness: 1))]))
        let object = try XCTUnwrap(plain[.graphicAnnotationSequence]?.sequenceItems?.first?[.graphicObjectSequence]?.sequenceItems?.first)
        let plainLine = try XCTUnwrap(object[.lineStyleSequence]?.sequenceItems?.first)
        XCTAssertEqual(plainLine.string(for: .shadowStyle), "OFF")
        XCTAssertNotNil(plainLine[.shadowOpacity])
        XCTAssertNil(plainLine[.linePattern], "Line Pattern is 1C, DASHED only")
    }

    // MARK: - 1C conditions of the Compound Graphic Sequence

    func test_conditionalAttributesFollowTheType() throws {
        let graphics: [CompoundGraphic] = [
            CompoundGraphic(instanceID: 1, type: .cutline, data: [0, 0, 10, 10]),
            CompoundGraphic(instanceID: 2, type: .crosshair, data: [5, 5]),
            CompoundGraphic(instanceID: 3, type: .axis, data: [0, 0, 10, 0],
                            majorTicks: [MajorTick(position: 0, label: "0"), MajorTick(position: 1, label: "10")]),
            CompoundGraphic(instanceID: 4, type: .rectangle, data: [0, 0, 10, 10], filled: true),
        ]
        let annotation = GraphicAnnotation(
            layer: "L", referencedImages: [image],
            graphicObjects: graphics.map {
                GraphicObject(type: .polyline, data: $0.data.count >= 4 ? $0.data : [5, 5, 5, 5],
                              compoundGraphicInstanceID: $0.instanceID)
            },
            compoundGraphics: graphics)
        let dataSet = try written(annotation)
        let items = try XCTUnwrap(dataSet[.graphicAnnotationSequence]?.sequenceItems?.first?[.compoundGraphicSequence]?.sequenceItems)
        XCTAssertNotNil(items[0][.rotationPoint], "CUTLINE: Rotation Point 1C")
        XCTAssertNotNil(items[0][.gapLength], "CUTLINE: Gap Length 1C")
        XCTAssertNotNil(items[1][.diameterOfVisibility], "CROSSHAIR: Diameter of Visibility 1C")
        XCTAssertNotNil(items[1][.tickAlignment], "CROSSHAIR: Tick Alignment 1C")
        XCTAssertEqual(items[2][.majorTicksSequence]?.sequenceItems?.count, 2, "AXIS: Major Ticks 1C")
        XCTAssertEqual(items[3].string(for: .graphicFilled), "Y", "RECTANGLE: Graphic Filled 1C")
        XCTAssertNotNil(items[3][.fillStyleSequence], "filled: Fill Style Sequence 1C")
        XCTAssertNil(items[3][.gapLength])
        XCTAssertNil(items[3][.rotationPoint])
        XCTAssertNoThrow(try GrayscalePresentationStateBuilder().validate(
            state(annotation), imageSize: (512, 512)))
    }

    func test_validateReportsCompoundGraphicProblems() {
        let noAlternate = GraphicAnnotation(
            layer: "L", referencedImages: [image],
            textObjects: [TextObject(text: "x", boundingBoxTopLeft: (0, 0), boundingBoxBottomRight: (1, 1))],
            compoundGraphics: [CompoundGraphic(instanceID: 1, type: .arrow, data: [0, 0, 5, 5])])
        XCTAssertThrowsError(try GrayscalePresentationStateBuilder().validate(
            state(noAlternate), imageSize: (512, 512)))
        XCTAssertEqual(CompoundGraphic(instanceID: 2, type: .arrow, data: [0, 0]).conformanceProblems.count, 1,
                       "ARROW needs two points (C.10.5.1.3.11)")
        XCTAssertFalse(CompoundGraphic(instanceID: 3, type: .axis, data: [0, 0, 1, 1]).conformanceProblems.isEmpty,
                       "AXIS needs two or more major ticks")
    }

    // MARK: - Text objects

    /// Table C.10-5: the bounding box is required only when there is no anchor.
    func test_anchorOnlyTextObjectIsRead() throws {
        var dataSet = try written(arrowAnnotation())
        let item = SequenceItem(elements: [
            DataElement.string(tag: .anchorPointAnnotationUnits, vr: .CS, value: "PIXEL"),
            DataElement.string(tag: .unformattedTextValue, vr: .ST, value: "Anchored"),
            DataElement.float32s(tag: .anchorPoint, values: [40, 50]),
            DataElement.string(tag: .anchorPointVisibility, vr: .CS, value: "Y"),
        ])
        let annotation = SequenceItem(elements: [
            DataElement.string(tag: .graphicLayer, vr: .CS, value: "L"),
            DataElement(tag: .textObjectSequence, vr: .SQ, length: 0, valueData: Data(), sequenceItems: [item]),
        ])
        dataSet[.graphicAnnotationSequence] = DataElement(
            tag: .graphicAnnotationSequence, vr: .SQ, length: 0, valueData: Data(), sequenceItems: [annotation])
        let parsed = try GrayscalePresentationStateParser().parse(dataSet: dataSet)
        let text = try XCTUnwrap(parsed.graphicAnnotations.first?.textObjects.first)
        XCTAssertEqual(text.text, "Anchored")
        XCTAssertEqual(text.anchorPoint?.column, 40)
        XCTAssertEqual(text.boundingBoxTopLeft.row, 50)
    }

    func test_unformattedTextKeepsLinesAsCRLF() {
        XCTAssertEqual(GrayscalePresentationStateBuilder.unformattedText("a\nb\tc\u{0C}"), "a\r\nb c ")
    }
}
