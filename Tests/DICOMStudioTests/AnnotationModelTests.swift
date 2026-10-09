// AnnotationModelTests.swift
// DICOMStudioTests
//
// Tests for Annotation models

import Testing
@testable import DICOMStudio
import Foundation

@Suite("GraphicType Tests")
struct GraphicTypeTests {

    @Test("All graphic types have raw values")
    func testRawValues() {
        #expect(GraphicType.point.rawValue == "POINT")
        #expect(GraphicType.polyline.rawValue == "POLYLINE")
        #expect(GraphicType.interpolated.rawValue == "INTERPOLATED")
        #expect(GraphicType.circle.rawValue == "CIRCLE")
        #expect(GraphicType.ellipse.rawValue == "ELLIPSE")
    }

    @Test("GraphicType CaseIterable has 5 cases")
    func testCaseIterable() {
        #expect(GraphicType.allCases.count == 5)
    }
}

@Suite("AnnotationPoint Tests")
struct AnnotationPointTests {

    @Test("Point creation")
    func testCreation() {
        let point = AnnotationPoint(x: 100.5, y: 200.5)
        #expect(point.x == 100.5)
        #expect(point.y == 200.5)
    }

    @Test("Points are equatable")
    func testEquality() {
        let a = AnnotationPoint(x: 10, y: 20)
        let b = AnnotationPoint(x: 10, y: 20)
        #expect(a == b)
    }

    @Test("Points are hashable")
    func testHashable() {
        let point = AnnotationPoint(x: 5, y: 10)
        var set: Set<AnnotationPoint> = []
        set.insert(point)
        #expect(set.contains(point))
    }
}

@Suite("GraphicAnnotation Tests")
struct GraphicAnnotationTests {

    @Test("Point annotation creation")
    func testPointAnnotation() {
        let annotation = GraphicAnnotation(
            graphicType: .point,
            points: [AnnotationPoint(x: 100, y: 200)]
        )
        #expect(annotation.graphicType == .point)
        #expect(annotation.points.count == 1)
        #expect(annotation.filled == false)
        #expect(annotation.layerName == "LAYER0")
    }

    @Test("Circle annotation creation")
    func testCircleAnnotation() {
        let annotation = GraphicAnnotation(
            graphicType: .circle,
            points: [AnnotationPoint(x: 256, y: 256), AnnotationPoint(x: 356, y: 256)],
            filled: true
        )
        #expect(annotation.graphicType == .circle)
        #expect(annotation.points.count == 2)
        #expect(annotation.filled == true)
    }

    @Test("Annotations are identifiable")
    func testIdentifiable() {
        let a = GraphicAnnotation(graphicType: .point, points: [AnnotationPoint(x: 0, y: 0)])
        let b = GraphicAnnotation(graphicType: .point, points: [AnnotationPoint(x: 0, y: 0)])
        #expect(a.id != b.id)
    }

    @Test("Custom layer name")
    func testCustomLayer() {
        let annotation = GraphicAnnotation(
            graphicType: .polyline,
            points: [AnnotationPoint(x: 0, y: 0), AnnotationPoint(x: 100, y: 100)],
            layerName: "MEASUREMENTS"
        )
        #expect(annotation.layerName == "MEASUREMENTS")
    }
}

@Suite("TextAnchorType Tests")
struct TextAnchorTypeTests {

    // PS3.3 2026a C.10.5 Table C.10-5 Bounding Box / Anchor Point Annotation Units: PIXEL, DISPLAY, MATRIX
    @Test("Raw values are the Annotation Units Enumerated Values")
    func testRawValues() {
        #expect(TextAnchorType.imageRelative.rawValue == "PIXEL")
        #expect(TextAnchorType.displayRelative.rawValue == "DISPLAY")
        #expect(TextAnchorType.matrixRelative.rawValue == "MATRIX")
        #expect(TextAnchorType(rawValue: "PIXEL") == .imageRelative)
        #expect(TextAnchorType(rawValue: "DISPLAY") == .displayRelative)
        #expect(TextAnchorType(rawValue: "MATRIX") == .matrixRelative)
    }

    @Test("Legacy IMAGE still decodes as PIXEL")
    func testLegacyImage() {
        #expect(TextAnchorType(rawValue: "IMAGE") == .imageRelative)
        #expect(TextAnchorType(rawValue: "SCREEN") == nil)
    }
}

@Suite("TextAnnotation Tests")
struct TextAnnotationTests {

    @Test("Text annotation with anchor point")
    func testAnchorPoint() {
        let annotation = TextAnnotation(
            text: "Finding: Mass",
            anchorPoint: AnnotationPoint(x: 100, y: 200),
            anchorType: .imageRelative
        )
        #expect(annotation.text == "Finding: Mass")
        #expect(annotation.anchorPoint?.x == 100)
        #expect(annotation.anchorType == .imageRelative)
        #expect(annotation.anchorPointVisible == true)
    }

    @Test("Text annotation with bounding box")
    func testBoundingBox() {
        let annotation = TextAnnotation(
            text: "Report Text",
            boundingBoxTopLeft: AnnotationPoint(x: 10, y: 10),
            boundingBoxBottomRight: AnnotationPoint(x: 200, y: 50)
        )
        #expect(annotation.boundingBoxTopLeft != nil)
        #expect(annotation.boundingBoxBottomRight != nil)
    }

    @Test("Text annotation default layer")
    func testDefaultLayer() {
        let annotation = TextAnnotation(text: "Test")
        #expect(annotation.layerName == "LAYER0")
    }
}

@Suite("GraphicLayer Tests")
struct GraphicLayerTests {

    @Test("Layer id is name")
    func testId() {
        let layer = GraphicLayer(name: "LAYER0", order: 0)
        #expect(layer.id == "LAYER0")
    }

    @Test("Layer ordering")
    func testOrdering() {
        let front = GraphicLayer(name: "FRONT", order: 10)
        let back = GraphicLayer(name: "BACK", order: 0)
        #expect(front.order > back.order)
    }
}
