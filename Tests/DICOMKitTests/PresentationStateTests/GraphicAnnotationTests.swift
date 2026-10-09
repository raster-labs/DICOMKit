//
// GraphicAnnotationTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class GraphicAnnotationTests: XCTestCase {
    
    // MARK: - GraphicLayer Tests
    
    func test_graphicLayer_minimal() {
        let layer = GraphicLayer(name: "Annotations", order: 1)
        
        XCTAssertEqual(layer.name, "Annotations")
        XCTAssertEqual(layer.order, 1)
        XCTAssertNil(layer.description)
        XCTAssertNil(layer.recommendedGrayscaleValue)
        XCTAssertNil(layer.recommendedRGBValue)
    }
    
    func test_graphicLayer_withDescription() {
        let layer = GraphicLayer(
            name: "Findings",
            order: 2,
            description: "Radiologist findings and annotations"
        )
        
        XCTAssertEqual(layer.description, "Radiologist findings and annotations")
    }
    
    func test_graphicLayer_withGrayscaleValue() {
        let layer = GraphicLayer(
            name: "Measurements",
            order: 1,
            recommendedGrayscaleValue: 65535
        )
        
        XCTAssertEqual(layer.recommendedGrayscaleValue, 65535)
    }
    
    func test_graphicLayer_withRGBValue() {
        let layer = GraphicLayer(
            name: "ColorAnnotations",
            order: 1,
            recommendedRGBValue: (red: 255, green: 0, blue: 0)
        )
        
        XCTAssertEqual(layer.recommendedRGBValue?.red, 255)
        XCTAssertEqual(layer.recommendedRGBValue?.green, 0)
        XCTAssertEqual(layer.recommendedRGBValue?.blue, 0)
    }
    
    func test_graphicLayer_equality() {
        let layer1 = GraphicLayer(name: "Layer1", order: 1)
        let layer2 = GraphicLayer(name: "Layer1", order: 1)
        let layer3 = GraphicLayer(name: "Layer2", order: 1)
        
        XCTAssertEqual(layer1, layer2)
        XCTAssertNotEqual(layer1, layer3)
    }
    
    func test_graphicLayer_hashable() {
        let layer1 = GraphicLayer(name: "Layer1", order: 1)
        let layer2 = GraphicLayer(name: "Layer1", order: 1)
        let layer3 = GraphicLayer(name: "Layer2", order: 2)
        
        let set: Set = [layer1, layer2, layer3]
        XCTAssertEqual(set.count, 2)
    }
    
    // MARK: - GraphicAnnotation Tests
    
    func test_graphicAnnotation_initialization() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        
        let annotation = GraphicAnnotation(
            layer: "Annotations",
            referencedImages: [image]
        )
        
        XCTAssertEqual(annotation.layer, "Annotations")
        XCTAssertEqual(annotation.referencedImages.count, 1)
        XCTAssertTrue(annotation.graphicObjects.isEmpty)
        XCTAssertTrue(annotation.textObjects.isEmpty)
    }
    
    func test_graphicAnnotation_withGraphicObjects() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        let graphic = GraphicObject(
            type: .point,
            data: [100.0, 200.0]
        )
        
        let annotation = GraphicAnnotation(
            layer: "Annotations",
            referencedImages: [image],
            graphicObjects: [graphic]
        )
        
        XCTAssertEqual(annotation.graphicObjects.count, 1)
        XCTAssertEqual(annotation.graphicObjects[0].type, .point)
    }
    
    func test_graphicAnnotation_withTextObjects() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5"
        )
        let text = TextObject(
            text: "Finding",
            boundingBoxTopLeft: (column: 100.0, row: 100.0),
            boundingBoxBottomRight: (column: 200.0, row: 120.0)
        )
        
        let annotation = GraphicAnnotation(
            layer: "Annotations",
            referencedImages: [image],
            textObjects: [text]
        )
        
        XCTAssertEqual(annotation.textObjects.count, 1)
        XCTAssertEqual(annotation.textObjects[0].text, "Finding")
    }
    
    // MARK: - GraphicObject Tests
    
    func test_graphicObject_point() {
        let graphic = GraphicObject(
            type: .point,
            data: [100.0, 200.0]
        )
        
        XCTAssertEqual(graphic.type, .point)
        XCTAssertEqual(graphic.data.count, 2)
        XCTAssertEqual(graphic.pointCount, 1)
        XCTAssertFalse(graphic.filled)
        XCTAssertEqual(graphic.units, .pixel)
    }
    
    func test_graphicObject_polyline() {
        let graphic = GraphicObject(
            type: .polyline,
            data: [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]
        )
        
        XCTAssertEqual(graphic.type, .polyline)
        XCTAssertEqual(graphic.pointCount, 3)
    }
    
    func test_graphicObject_circle() {
        // Circle: center point + radius point
        let graphic = GraphicObject(
            type: .circle,
            data: [100.0, 100.0, 150.0, 100.0]
        )
        
        XCTAssertEqual(graphic.type, .circle)
        XCTAssertEqual(graphic.pointCount, 2)
    }
    
    func test_graphicObject_ellipse() {
        // ELLIPSE: exactly four points, the endpoints of the major axis then the
        // endpoints of the minor axis (PS3.3 2026a C.10.5.1.2) — not the corners
        // of a bounding box. Column (X) precedes row (Y) in each point.
        let graphic = GraphicObject(
            type: .ellipse,
            data: [50.0, 75.0, 150.0, 75.0, 100.0, 50.0, 100.0, 100.0]
        )
        
        XCTAssertEqual(graphic.type, .ellipse)
        XCTAssertEqual(graphic.pointCount, 4)
        XCTAssertEqual(graphic.point(at: 0)?.column, 50.0)   // major axis
        XCTAssertEqual(graphic.point(at: 1)?.column, 150.0)
        XCTAssertEqual(graphic.point(at: 2)?.row, 50.0)      // minor axis
        XCTAssertEqual(graphic.point(at: 3)?.row, 100.0)
    }
    
    func test_graphicObject_filled() {
        let graphic = GraphicObject(
            type: .circle,
            data: [100.0, 100.0, 150.0, 100.0],
            filled: true
        )
        
        XCTAssertTrue(graphic.filled)
    }
    
    func test_graphicObject_displayUnits() {
        let graphic = GraphicObject(
            type: .point,
            data: [0.5, 0.5],
            units: .display
        )
        
        XCTAssertEqual(graphic.units, .display)
    }
    
    func test_graphicObject_pointAt() {
        let graphic = GraphicObject(
            type: .polyline,
            data: [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]
        )
        
        let point0 = graphic.point(at: 0)
        XCTAssertNotNil(point0)
        XCTAssertEqual(point0?.column, 10.0)
        XCTAssertEqual(point0?.row, 20.0)
        
        let point1 = graphic.point(at: 1)
        XCTAssertNotNil(point1)
        XCTAssertEqual(point1?.column, 30.0)
        XCTAssertEqual(point1?.row, 40.0)
        
        let point2 = graphic.point(at: 2)
        XCTAssertNotNil(point2)
        XCTAssertEqual(point2?.column, 50.0)
        XCTAssertEqual(point2?.row, 60.0)
    }
    
    func test_graphicObject_pointAt_invalidIndex() {
        let graphic = GraphicObject(
            type: .point,
            data: [100.0, 200.0]
        )
        
        XCTAssertNil(graphic.point(at: -1))
        XCTAssertNil(graphic.point(at: 1))
        XCTAssertNil(graphic.point(at: 100))
    }
    
    // MARK: - PresentationGraphicType Tests
    
    func test_presentationGraphicType_point() {
        XCTAssertEqual(PresentationGraphicType.point.rawValue, "POINT")
    }
    
    func test_presentationGraphicType_polyline() {
        XCTAssertEqual(PresentationGraphicType.polyline.rawValue, "POLYLINE")
    }
    
    func test_presentationGraphicType_interpolated() {
        XCTAssertEqual(PresentationGraphicType.interpolated.rawValue, "INTERPOLATED")
    }
    
    func test_presentationGraphicType_circle() {
        XCTAssertEqual(PresentationGraphicType.circle.rawValue, "CIRCLE")
    }
    
    func test_presentationGraphicType_ellipse() {
        XCTAssertEqual(PresentationGraphicType.ellipse.rawValue, "ELLIPSE")
    }
    
    // MARK: - TextObject Tests
    
    func test_textObject_minimal() {
        let text = TextObject(
            text: "Finding",
            boundingBoxTopLeft: (column: 100.0, row: 100.0),
            boundingBoxBottomRight: (column: 200.0, row: 120.0)
        )
        
        XCTAssertEqual(text.text, "Finding")
        XCTAssertEqual(text.boundingBoxTopLeft.column, 100.0)
        XCTAssertEqual(text.boundingBoxTopLeft.row, 100.0)
        XCTAssertEqual(text.boundingBoxBottomRight.column, 200.0)
        XCTAssertEqual(text.boundingBoxBottomRight.row, 120.0)
        XCTAssertNil(text.anchorPoint)
        XCTAssertFalse(text.anchorPointVisible)
        XCTAssertEqual(text.boundingBoxUnits, .pixel)
        XCTAssertEqual(text.anchorPointUnits, .pixel)
    }
    
    func test_textObject_withAnchorPoint() {
        let text = TextObject(
            text: "Measurement: 5.2 cm",
            boundingBoxTopLeft: (column: 100.0, row: 100.0),
            boundingBoxBottomRight: (column: 250.0, row: 120.0),
            anchorPoint: (column: 150.0, row: 200.0),
            anchorPointVisible: true
        )
        
        XCTAssertNotNil(text.anchorPoint)
        XCTAssertEqual(text.anchorPoint?.column, 150.0)
        XCTAssertEqual(text.anchorPoint?.row, 200.0)
        XCTAssertTrue(text.anchorPointVisible)
    }
    
    func test_textObject_displayUnits() {
        let text = TextObject(
            text: "Label",
            boundingBoxTopLeft: (column: 0.1, row: 0.1),
            boundingBoxBottomRight: (column: 0.3, row: 0.15),
            boundingBoxUnits: .display,
            anchorPointUnits: .display
        )
        
        XCTAssertEqual(text.boundingBoxUnits, .display)
        XCTAssertEqual(text.anchorPointUnits, .display)
    }
    
    func test_textObject_equality() {
        let text1 = TextObject(
            text: "Finding",
            boundingBoxTopLeft: (column: 100.0, row: 100.0),
            boundingBoxBottomRight: (column: 200.0, row: 120.0)
        )
        let text2 = TextObject(
            text: "Finding",
            boundingBoxTopLeft: (column: 100.0, row: 100.0),
            boundingBoxBottomRight: (column: 200.0, row: 120.0)
        )
        let text3 = TextObject(
            text: "Different",
            boundingBoxTopLeft: (column: 100.0, row: 100.0),
            boundingBoxBottomRight: (column: 200.0, row: 120.0)
        )
        
        XCTAssertEqual(text1, text2)
        XCTAssertNotEqual(text1, text3)
    }
    
    func test_textObject_hashable() {
        let text1 = TextObject(
            text: "Finding",
            boundingBoxTopLeft: (column: 100.0, row: 100.0),
            boundingBoxBottomRight: (column: 200.0, row: 120.0)
        )
        let text2 = TextObject(
            text: "Finding",
            boundingBoxTopLeft: (column: 100.0, row: 100.0),
            boundingBoxBottomRight: (column: 200.0, row: 120.0)
        )
        let text3 = TextObject(
            text: "Other",
            boundingBoxTopLeft: (column: 50.0, row: 50.0),
            boundingBoxBottomRight: (column: 150.0, row: 70.0)
        )
        
        let set: Set = [text1, text2, text3]
        XCTAssertEqual(set.count, 2)
    }
    
    // MARK: - AnnotationUnits Tests
    
    func test_annotationUnits_pixel() {
        XCTAssertEqual(AnnotationUnits.pixel.rawValue, "PIXEL")
    }
    
    func test_annotationUnits_display() {
        XCTAssertEqual(AnnotationUnits.display.rawValue, "DISPLAY")
    }
}
