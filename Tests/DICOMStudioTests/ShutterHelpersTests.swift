// ShutterHelpersTests.swift
// DICOMStudioTests
//
// Tests for ShutterHelpers

import Testing
@testable import DICOMStudio
import Foundation

@Suite("ShutterHelpers Rectangular Tests")
struct ShutterRectangularTests {

    @Test("Point inside rectangular shutter")
    func testInside() {
        let shutter = RectangularShutter(top: 50, bottom: 450, left: 50, right: 450)
        #expect(ShutterHelpers.isInsideRectangular(row: 100, column: 100, shutter: shutter))
        #expect(ShutterHelpers.isInsideRectangular(row: 50, column: 50, shutter: shutter))
        #expect(ShutterHelpers.isInsideRectangular(row: 450, column: 450, shutter: shutter))
    }

    @Test("Point outside rectangular shutter")
    func testOutside() {
        let shutter = RectangularShutter(top: 50, bottom: 450, left: 50, right: 450)
        #expect(!ShutterHelpers.isInsideRectangular(row: 0, column: 0, shutter: shutter))
        #expect(!ShutterHelpers.isInsideRectangular(row: 49, column: 100, shutter: shutter))
        #expect(!ShutterHelpers.isInsideRectangular(row: 100, column: 49, shutter: shutter))
    }
}

@Suite("ShutterHelpers Circular Tests")
struct ShutterCircularTests {

    @Test("Point inside circular shutter")
    func testInside() {
        let shutter = CircularShutter(centerRow: 256, centerColumn: 256, radius: 200)
        #expect(ShutterHelpers.isInsideCircular(row: 256, column: 256, shutter: shutter))
        #expect(ShutterHelpers.isInsideCircular(row: 256, column: 456, shutter: shutter))
    }

    @Test("Point outside circular shutter")
    func testOutside() {
        let shutter = CircularShutter(centerRow: 256, centerColumn: 256, radius: 200)
        #expect(!ShutterHelpers.isInsideCircular(row: 0, column: 0, shutter: shutter))
        #expect(!ShutterHelpers.isInsideCircular(row: 256, column: 500, shutter: shutter))
    }
}

@Suite("ShutterHelpers Polygonal Tests")
struct ShutterPolygonalTests {

    @Test("Point inside triangle")
    func testInsideTriangle() {
        let shutter = PolygonalShutter(vertices: [
            AnnotationPoint(x: 0, y: 0),
            AnnotationPoint(x: 100, y: 0),
            AnnotationPoint(x: 50, y: 100)
        ])
        #expect(ShutterHelpers.isInsidePolygonal(row: 10, column: 50, shutter: shutter))
    }

    @Test("Point outside triangle")
    func testOutsideTriangle() {
        let shutter = PolygonalShutter(vertices: [
            AnnotationPoint(x: 0, y: 0),
            AnnotationPoint(x: 100, y: 0),
            AnnotationPoint(x: 50, y: 100)
        ])
        #expect(!ShutterHelpers.isInsidePolygonal(row: 200, column: 200, shutter: shutter))
    }

    @Test("Point in polygon - square")
    func testInsideSquare() {
        let vertices = [
            AnnotationPoint(x: 0, y: 0),
            AnnotationPoint(x: 100, y: 0),
            AnnotationPoint(x: 100, y: 100),
            AnnotationPoint(x: 0, y: 100)
        ]
        #expect(ShutterHelpers.isPointInPolygon(x: 50, y: 50, vertices: vertices))
        #expect(!ShutterHelpers.isPointInPolygon(x: 200, y: 200, vertices: vertices))
    }
}

@Suite("ShutterHelpers Combined Tests")
struct ShutterCombinedTests {

    @Test("No shutter - pixel always visible")
    func testNoShutter() {
        let model = ShutterModel()
        #expect(ShutterHelpers.isPixelVisible(row: 0, column: 0, shutter: model))
    }

    @Test("Rectangular shutter visibility")
    func testRectVisibility() {
        let model = ShutterModel(
            shapes: [.rectangular],
            rectangular: RectangularShutter(top: 50, bottom: 450, left: 50, right: 450)
        )
        #expect(ShutterHelpers.isPixelVisible(row: 100, column: 100, shutter: model))
        #expect(!ShutterHelpers.isPixelVisible(row: 0, column: 0, shutter: model))
    }

    @Test("Multiple shutters AND together")
    func testMultipleShutters() {
        let model = ShutterModel(
            shapes: [.rectangular, .circular],
            rectangular: RectangularShutter(top: 0, bottom: 512, left: 0, right: 512),
            circular: CircularShutter(centerRow: 256, centerColumn: 256, radius: 100)
        )
        // Center should be visible (inside both)
        #expect(ShutterHelpers.isPixelVisible(row: 256, column: 256, shutter: model))
        // Corner should not be visible (outside circular)
        #expect(!ShutterHelpers.isPixelVisible(row: 0, column: 0, shutter: model))
    }
}

@Suite("ShutterHelpers Validation Tests")
struct ShutterValidationTests {

    @Test("Valid rectangular shutter model")
    func testValidRect() {
        let model = ShutterModel(
            shapes: [.rectangular],
            rectangular: RectangularShutter(top: 50, bottom: 450, left: 50, right: 450)
        )
        #expect(ShutterHelpers.isValid(model))
    }

    @Test("Invalid rectangular shutter model")
    func testInvalidRect() {
        let model = ShutterModel(
            shapes: [.rectangular],
            rectangular: RectangularShutter(top: 450, bottom: 50, left: 50, right: 450)
        )
        #expect(!ShutterHelpers.isValid(model))
    }

    @Test("Missing shutter data is invalid")
    func testMissingData() {
        let model = ShutterModel(shapes: [.rectangular])
        #expect(!ShutterHelpers.isValid(model))
    }
}

@Suite("ShutterHelpers Display Tests")
struct ShutterDisplayTests {

    @Test("Shape labels")
    func testLabels() {
        #expect(ShutterHelpers.shapeLabel(for: .rectangular) == "Rectangular")
        #expect(ShutterHelpers.shapeLabel(for: .circular) == "Circular")
        #expect(ShutterHelpers.shapeLabel(for: .polygonal) == "Polygonal")
        #expect(ShutterHelpers.shapeLabel(for: .bitmap) == "Bitmap")
    }

    @Test("Shutter description")
    func testDescription() {
        let model = ShutterModel(shapes: [.rectangular, .circular])
        #expect(ShutterHelpers.shutterDescription(model) == "Rectangular + Circular")
    }

    @Test("No shutter description")
    func testNoShutterDesc() {
        let model = ShutterModel()
        #expect(ShutterHelpers.shutterDescription(model) == "No shutter")
    }

    @Test("Normalized shutter gray")
    func testNormalizedGray() {
        #expect(ShutterHelpers.normalizedShutterGray(0) == 0.0)
        #expect(ShutterHelpers.normalizedShutterGray(65535) == 1.0)
        #expect(abs(ShutterHelpers.normalizedShutterGray(32768) - 0.5) < 0.01)
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// PS3.3 2026a C.7.6.11, Shutter Shape (0018,1600): "When multiple Values are
/// present … all of the shapes shall be combined and applied simultaneously,
/// that is, the least amount of image remaining shall be visible" — the
/// cut-out drawn over the image is the intersection of the shapes, which is
/// also what `ShutterHelpers.isPixelVisible` answers pixel by pixel.
@Suite("ShutterOverlayView cut-out")
struct ShutterOverlayCutoutTests {

    @Test("Several shapes cut out their intersection, not their union (PS3.3 C.7.6.11)")
    func cutoutIsTheIntersection() {
        let model = ShutterModel(
            shapes: [.rectangular, .circular],
            rectangular: RectangularShutter(top: 0, bottom: 100, left: 0, right: 100),
            circular: CircularShutter(centerRow: 100, centerColumn: 100, radius: 50))
        let path = ShutterCutoutShape(shutter: model, scaleX: 1, scaleY: 1)
            .path(in: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Inside the rectangle only: occluded by the circle, so not cut out.
        #expect(!path.contains(CGPoint(x: 10, y: 10)))
        #expect(!ShutterHelpers.isPixelVisible(row: 10, column: 10, shutter: model))
        // Inside the circle only: occluded by the rectangle.
        #expect(!path.contains(CGPoint(x: 120, y: 120)))
        #expect(!ShutterHelpers.isPixelVisible(row: 120, column: 120, shutter: model))
        // Inside both: visible.
        #expect(path.contains(CGPoint(x: 90, y: 90)))
        #expect(ShutterHelpers.isPixelVisible(row: 90, column: 90, shutter: model))
    }

    @Test("A single shape cuts out exactly itself")
    func singleShape() {
        let model = ShutterModel(
            shapes: [.circular],
            circular: CircularShutter(centerRow: 50, centerColumn: 50, radius: 10))
        let path = ShutterCutoutShape(shutter: model, scaleX: 1, scaleY: 1)
            .path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(path.contains(CGPoint(x: 50, y: 50)))
        #expect(!path.contains(CGPoint(x: 80, y: 80)))
    }
}
#endif
