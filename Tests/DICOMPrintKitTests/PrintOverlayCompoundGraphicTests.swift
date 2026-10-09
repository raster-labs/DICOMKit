//
// PrintOverlayCompoundGraphicTests.swift
// DICOMPrintKit
//
// D39 on the print side: a drawn arrow is written as a Compound Graphic of
// type ARROW with its polylines as the alternate rendering (PS3.3 2026a Table
// C.10-5, C.10.5.1.3.1, C.10.5.1.3.11), every object carries its own colour
// and halo in a Line or Text Style Sequence (Tables C.10-5a/5b), and a state
// read back shows one arrow in the object's colour.
//

import XCTest
import DICOMCore
import DICOMKit
@testable import DICOMPrintKit

final class PrintOverlayCompoundGraphicTests: XCTestCase {

    private let image = ReferencedImage(sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                                        sopInstanceUID: "1.2.3.4.5.6.1")

    private func arrow(color: PrintOverlayColor = .red) -> PrintOverlayAnnotation {
        PrintOverlayAnnotation(kind: .arrow,
                               start: PrintOverlayPoint(x: 0.2, y: 0.2),
                               end: PrintOverlayPoint(x: 0.6, y: 0.5),
                               color: color)
    }

    func test_arrowIsACompoundGraphicWithItsAlternateRendering() throws {
        let item = try XCTUnwrap(PrintOverlayAnnotationGSPS.graphicAnnotation(
            from: [arrow()], imageWidth: 100, imageHeight: 100, referencedImage: image))
        let compound = try XCTUnwrap(item.compoundGraphics.first)
        XCTAssertEqual(compound.type, .arrow)
        // Anchor (the head) first, then the foot (C.10.5.1.3.11).
        XCTAssertEqual(compound.points.first?.column ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(compound.points.first?.row ?? 0, 50, accuracy: 1e-9)
        XCTAssertEqual(compound.points.last?.column ?? 0, 20, accuracy: 1e-9)
        XCTAssertEqual(item.graphicObjects.count, 2)
        XCTAssertTrue(item.graphicObjects.allSatisfy { $0.compoundGraphicInstanceID == compound.instanceID })
        let state = GrayscalePresentationState(
            sopInstanceUID: "1.2.3",
            referencedSeries: [ReferencedSeries(seriesInstanceUID: "1.2.3.4", referencedImages: [image])],
            graphicAnnotations: [item])
        XCTAssertNoThrow(try GrayscalePresentationStateBuilder().validate(state, imageSize: (100, 100)))
    }

    func test_eachObjectCarriesItsOwnColour() throws {
        let words = PrintOverlayAnnotation(kind: .text, start: PrintOverlayPoint(x: 0.1, y: 0.1),
                                           text: "Lesion", color: .cyan)
        let item = try XCTUnwrap(PrintOverlayAnnotationGSPS.graphicAnnotation(
            from: [arrow(color: .red), words], imageWidth: 200, imageHeight: 200, referencedImage: image))
        let lineColour = try XCTUnwrap(item.graphicObjects.first?.lineStyle?.onColor)
        let textStyle = try XCTUnwrap(item.textObjects.first?.textStyle)
        XCTAssertEqual(lineColour, PrintOverlayAnnotationGSPS.cieLab(.red))
        XCTAssertEqual(textStyle.color, PrintOverlayAnnotationGSPS.cieLab(.cyan))
        XCTAssertEqual(textStyle.fontNameType, "ISO_32000")
        XCTAssertEqual(textStyle.shadow.style, .outlined, "the burner's halo")
        XCTAssertNotEqual(lineColour, textStyle.color)
    }

    /// Instance IDs are unique within the object across frames (C.10.5.1.3.1).
    func test_compoundIDsAreUniqueAcrossFrames() {
        let items = PrintOverlayAnnotationGSPS.graphicAnnotations(
            from: [0: [arrow()], 1: [arrow(), arrow()]],
            imageWidth: 100, imageHeight: 100, referencedImage: image, isMultiFrame: true)
        let ids = items.flatMap { $0.compoundGraphics.map(\.instanceID) }
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids).count, 3)
    }

    /// Read back: one arrow in its own colour, not the arrow plus its polylines.
    func test_readBackShowsOneArrowInItsColour() throws {
        let item = try XCTUnwrap(PrintOverlayAnnotationGSPS.graphicAnnotation(
            from: [arrow(color: .green)], imageWidth: 100, imageHeight: 100, referencedImage: image))
        let state = GrayscalePresentationState(
            sopInstanceUID: "1.2.3", referencedSeries: [],
            graphicLayers: [GraphicLayer(name: PrintOverlayAnnotationGSPS.layerName, order: 1,
                                         recommendedRGBValue: (65535, 65535, 65535))],
            graphicAnnotations: [item])
        let overlays = PrintOverlayAnnotationGSPS.overlays(
            from: state, forImage: image.sopInstanceUID, imageWidth: 100, imageHeight: 100)[0] ?? []
        XCTAssertEqual(overlays.count, 1)
        let drawn = try XCTUnwrap(overlays.first)
        XCTAssertEqual(drawn.kind, .arrow)
        XCTAssertEqual(drawn.end.x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(drawn.start.x, 0.2, accuracy: 1e-9)
        // The Line Style colour overrides the (white) layer's.
        XCTAssertEqual(drawn.color.green, PrintOverlayColor.green.green, accuracy: 0.01)
        XCTAssertEqual(drawn.color.red, PrintOverlayColor.green.red, accuracy: 0.01)
    }
}
