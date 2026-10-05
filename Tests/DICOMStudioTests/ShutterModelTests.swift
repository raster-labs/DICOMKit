// ShutterModelTests.swift
// DICOMStudioTests
//
// Tests for Shutter models

import Testing
@testable import DICOMStudio
import Foundation

@Suite("ShutterShape Tests")
struct ShutterShapeTests {

    @Test("All shutter shapes")
    func testCaseCount() {
        #expect(ShutterShape.allCases.count == 4)
    }

    @Test("Raw values")
    func testRawValues() {
        #expect(ShutterShape.rectangular.rawValue == "RECTANGULAR")
        #expect(ShutterShape.circular.rawValue == "CIRCULAR")
        #expect(ShutterShape.polygonal.rawValue == "POLYGONAL")
        #expect(ShutterShape.bitmap.rawValue == "BITMAP")
    }
}

@Suite("RectangularShutter Tests")
struct RectangularShutterTests {

    @Test("Valid rectangular shutter")
    func testValid() {
        let shutter = RectangularShutter(top: 50, bottom: 450, left: 50, right: 450)
        #expect(shutter.isValid)
        #expect(shutter.width == 400)
        #expect(shutter.height == 400)
    }

    @Test("Invalid rectangular shutter - inverted edges")
    func testInvalid() {
        let shutter = RectangularShutter(top: 450, bottom: 50, left: 50, right: 450)
        #expect(!shutter.isValid)
    }

    @Test("Width and height with zero-area")
    func testZeroArea() {
        let shutter = RectangularShutter(top: 100, bottom: 100, left: 50, right: 450)
        #expect(!shutter.isValid)
    }

    @Test("Negative coordinates")
    func testNegativeCoords() {
        let shutter = RectangularShutter(top: -10, bottom: 100, left: 0, right: 100)
        #expect(!shutter.isValid)
    }
}

@Suite("CircularShutter Tests")
struct CircularShutterTests {

    @Test("Valid circular shutter")
    func testValid() {
        let shutter = CircularShutter(centerRow: 256, centerColumn: 256, radius: 200)
        #expect(shutter.isValid)
    }

    @Test("Zero radius is invalid")
    func testZeroRadius() {
        let shutter = CircularShutter(centerRow: 256, centerColumn: 256, radius: 0)
        #expect(!shutter.isValid)
    }

    @Test("Negative center is invalid")
    func testNegativeCenter() {
        let shutter = CircularShutter(centerRow: -1, centerColumn: 256, radius: 100)
        #expect(!shutter.isValid)
    }
}

@Suite("PolygonalShutter Tests")
struct PolygonalShutterTests {

    @Test("Valid polygon with 3 vertices")
    func testTriangle() {
        let shutter = PolygonalShutter(vertices: [
            AnnotationPoint(x: 0, y: 0),
            AnnotationPoint(x: 512, y: 0),
            AnnotationPoint(x: 256, y: 512)
        ])
        #expect(shutter.isValid)
    }

    @Test("Invalid polygon with 2 vertices")
    func testTwoVertices() {
        let shutter = PolygonalShutter(vertices: [
            AnnotationPoint(x: 0, y: 0),
            AnnotationPoint(x: 512, y: 0)
        ])
        #expect(!shutter.isValid)
    }

    @Test("Empty polygon is invalid")
    func testEmpty() {
        let shutter = PolygonalShutter(vertices: [])
        #expect(!shutter.isValid)
    }
}

@Suite("BitmapShutter Tests")
struct BitmapShutterTests {

    @Test("Valid bitmap shutter")
    func testValid() {
        let shutter = BitmapShutter(overlayGroup: 0x6000, rows: 512, columns: 512)
        #expect(shutter.isValid)
    }

    @Test("Invalid overlay group")
    func testInvalidGroup() {
        let shutter = BitmapShutter(overlayGroup: 0x5000, rows: 512, columns: 512)
        #expect(!shutter.isValid)
    }

    /// PS3.5 2026a 7.6: "Repeating Groups shall only be allowed in the even
    /// numbered Groups 6000-601E"; 6001–601F are private groups.
    @Test("Overlay group must be an even Repeating Group 6000–601E (PS3.5 7.6)")
    func testEvenRepeatingGroupsOnly() {
        #expect(BitmapShutter(overlayGroup: 0x601E, rows: 1, columns: 1).isValid)
        #expect(!BitmapShutter(overlayGroup: 0x6001, rows: 1, columns: 1).isValid)
        #expect(!BitmapShutter(overlayGroup: 0x601F, rows: 1, columns: 1).isValid)
        #expect(!BitmapShutter(overlayGroup: 0x6020, rows: 1, columns: 1).isValid)
    }
}

@Suite("ShutterModel Tests")
struct ShutterModelTests {

    @Test("Model with no shutter")
    func testNoShutter() {
        let model = ShutterModel()
        #expect(!model.hasShutter)
    }

    @Test("Model with rectangular shutter")
    func testRectShutter() {
        let model = ShutterModel(
            shapes: [.rectangular],
            rectangular: RectangularShutter(top: 50, bottom: 450, left: 50, right: 450)
        )
        #expect(model.hasShutter)
        #expect(model.shapes.count == 1)
    }

    @Test("Model with multiple shutters")
    func testMultipleShutters() {
        let model = ShutterModel(
            shapes: [.rectangular, .circular],
            rectangular: RectangularShutter(top: 50, bottom: 450, left: 50, right: 450),
            circular: CircularShutter(centerRow: 256, centerColumn: 256, radius: 200)
        )
        #expect(model.shapes.count == 2)
    }

    @Test("Custom shutter presentation value")
    func testPresentationValue() {
        let model = ShutterModel(shutterPresentationValue: 32768)
        #expect(model.shutterPresentationValue == 32768)
    }
}
