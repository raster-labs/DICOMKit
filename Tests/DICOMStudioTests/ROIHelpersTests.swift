// ROIHelpersTests.swift
// DICOMStudioTests
//
// Tests for ROIHelpers

import Testing
@testable import DICOMStudio
import Foundation

@Suite("ROIHelpers Circle Tests")
struct ROICircleTests {

    @Test("Circle area")
    func testCircleArea() {
        let area = ROIHelpers.circleAreaPixels(
            center: AnnotationPoint(x: 100, y: 100),
            edge: AnnotationPoint(x: 200, y: 100)
        )
        // radius = 100, area = π * 100² ≈ 31415.9
        #expect(abs(area - .pi * 10000) < 0.001)
    }

    @Test("Circle area with zero radius")
    func testCircleAreaZero() {
        let p = AnnotationPoint(x: 100, y: 100)
        let area = ROIHelpers.circleAreaPixels(center: p, edge: p)
        #expect(area == 0)
    }

    @Test("Circle perimeter")
    func testCirclePerimeter() {
        let perimeter = ROIHelpers.circlePerimeterPixels(
            center: AnnotationPoint(x: 100, y: 100),
            edge: AnnotationPoint(x: 200, y: 100)
        )
        // radius = 100, perimeter = 2π * 100 ≈ 628.318
        #expect(abs(perimeter - 2 * .pi * 100) < 0.001)
    }
}

@Suite("ROIHelpers Ellipse Tests")
struct ROIEllipseTests {

    @Test("Ellipse area")
    func testEllipseArea() {
        let points = [
            AnnotationPoint(x: 100, y: 200),
            AnnotationPoint(x: 300, y: 200),
            AnnotationPoint(x: 200, y: 150),
            AnnotationPoint(x: 200, y: 250)
        ]
        let area = ROIHelpers.ellipseAreaPixels(points: points)
        // semiMajor = 100, semiMinor = 50, area = π * 100 * 50 ≈ 15707.96
        #expect(area != nil)
        #expect(abs((area ?? 0) - .pi * 100 * 50) < 0.001)
    }

    @Test("Ellipse area with invalid points")
    func testEllipseAreaInvalid() {
        #expect(ROIHelpers.ellipseAreaPixels(points: []) == nil)
        #expect(ROIHelpers.ellipseAreaPixels(points: [AnnotationPoint(x: 0, y: 0)]) == nil)
    }

    @Test("Ellipse perimeter (Ramanujan)")
    func testEllipsePerimeter() {
        let points = [
            AnnotationPoint(x: 100, y: 200),
            AnnotationPoint(x: 300, y: 200),
            AnnotationPoint(x: 200, y: 150),
            AnnotationPoint(x: 200, y: 250)
        ]
        let perimeter = ROIHelpers.ellipsePerimeterPixels(points: points)
        #expect(perimeter != nil)
        // For a=100, b=50, approximate perimeter ≈ 482.8 (Ramanujan)
        #expect((perimeter ?? 0) > 400)
        #expect((perimeter ?? 0) < 600)
    }

    @Test("Ellipse perimeter invalid")
    func testEllipsePerimeterInvalid() {
        #expect(ROIHelpers.ellipsePerimeterPixels(points: []) == nil)
    }
}

@Suite("ROIHelpers Rectangle Tests")
struct ROIRectangleTests {

    @Test("Rectangle area")
    func testRectangleArea() {
        let area = ROIHelpers.rectangleAreaPixels(
            topLeft: AnnotationPoint(x: 10, y: 10),
            bottomRight: AnnotationPoint(x: 110, y: 60)
        )
        #expect(area == 5000) // 100 * 50
    }

    @Test("Rectangle area with reversed corners")
    func testRectangleAreaReversed() {
        let area = ROIHelpers.rectangleAreaPixels(
            topLeft: AnnotationPoint(x: 110, y: 60),
            bottomRight: AnnotationPoint(x: 10, y: 10)
        )
        #expect(area == 5000)
    }

    @Test("Rectangle perimeter")
    func testRectanglePerimeter() {
        let perimeter = ROIHelpers.rectanglePerimeterPixels(
            topLeft: AnnotationPoint(x: 0, y: 0),
            bottomRight: AnnotationPoint(x: 100, y: 50)
        )
        #expect(perimeter == 300) // 2*(100+50)
    }
}

@Suite("ROIHelpers Polygon Tests")
struct ROIPolygonTests {

    @Test("Triangle area (shoelace)")
    func testTriangleArea() {
        let points = [
            AnnotationPoint(x: 0, y: 0),
            AnnotationPoint(x: 100, y: 0),
            AnnotationPoint(x: 0, y: 100)
        ]
        let area = ROIHelpers.polygonAreaPixels(points: points)
        #expect(area != nil)
        #expect(abs((area ?? 0) - 5000) < 0.001) // 0.5 * 100 * 100
    }

    @Test("Square area")
    func testSquareArea() {
        let points = [
            AnnotationPoint(x: 0, y: 0),
            AnnotationPoint(x: 100, y: 0),
            AnnotationPoint(x: 100, y: 100),
            AnnotationPoint(x: 0, y: 100)
        ]
        let area = ROIHelpers.polygonAreaPixels(points: points)
        #expect(abs((area ?? 0) - 10000) < 0.001)
    }

    @Test("Polygon area with < 3 points returns nil")
    func testTooFewPoints() {
        #expect(ROIHelpers.polygonAreaPixels(points: []) == nil)
        #expect(ROIHelpers.polygonAreaPixels(points: [AnnotationPoint(x: 0, y: 0)]) == nil)
        #expect(ROIHelpers.polygonAreaPixels(points: [
            AnnotationPoint(x: 0, y: 0),
            AnnotationPoint(x: 100, y: 0)
        ]) == nil)
    }

    @Test("Polygon perimeter")
    func testPolygonPerimeter() {
        let points = [
            AnnotationPoint(x: 0, y: 0),
            AnnotationPoint(x: 100, y: 0),
            AnnotationPoint(x: 100, y: 100),
            AnnotationPoint(x: 0, y: 100)
        ]
        let perimeter = ROIHelpers.polygonPerimeterPixels(points: points)
        #expect(abs((perimeter ?? 0) - 400) < 0.001)
    }

    @Test("Polygon perimeter with < 2 points returns nil")
    func testPerimeterTooFew() {
        #expect(ROIHelpers.polygonPerimeterPixels(points: []) == nil)
        #expect(ROIHelpers.polygonPerimeterPixels(points: [AnnotationPoint(x: 0, y: 0)]) == nil)
    }
}

@Suite("ROIHelpers Point-in-ROI Tests")
struct ROIPointInROITests {

    @Test("Point inside polygon")
    func testPointInPolygon() {
        let polygon = [
            AnnotationPoint(x: 0, y: 0),
            AnnotationPoint(x: 100, y: 0),
            AnnotationPoint(x: 100, y: 100),
            AnnotationPoint(x: 0, y: 100)
        ]
        #expect(ROIHelpers.isPointInPolygon(point: AnnotationPoint(x: 50, y: 50), polygon: polygon))
    }

    @Test("Point outside polygon")
    func testPointOutsidePolygon() {
        let polygon = [
            AnnotationPoint(x: 0, y: 0),
            AnnotationPoint(x: 100, y: 0),
            AnnotationPoint(x: 100, y: 100),
            AnnotationPoint(x: 0, y: 100)
        ]
        #expect(!ROIHelpers.isPointInPolygon(point: AnnotationPoint(x: 200, y: 200), polygon: polygon))
    }

    @Test("Point in polygon with < 3 vertices returns false")
    func testDegenerate() {
        #expect(!ROIHelpers.isPointInPolygon(point: AnnotationPoint(x: 0, y: 0), polygon: []))
    }

    @Test("Point inside circle")
    func testPointInCircle() {
        #expect(ROIHelpers.isPointInCircle(
            point: AnnotationPoint(x: 110, y: 100),
            center: AnnotationPoint(x: 100, y: 100),
            edge: AnnotationPoint(x: 150, y: 100)
        ))
    }

    @Test("Point outside circle")
    func testPointOutsideCircle() {
        #expect(!ROIHelpers.isPointInCircle(
            point: AnnotationPoint(x: 200, y: 200),
            center: AnnotationPoint(x: 100, y: 100),
            edge: AnnotationPoint(x: 150, y: 100)
        ))
    }

    @Test("Point inside rectangle")
    func testPointInRectangle() {
        #expect(ROIHelpers.isPointInRectangle(
            point: AnnotationPoint(x: 50, y: 50),
            topLeft: AnnotationPoint(x: 0, y: 0),
            bottomRight: AnnotationPoint(x: 100, y: 100)
        ))
    }

    @Test("Point outside rectangle")
    func testPointOutsideRectangle() {
        #expect(!ROIHelpers.isPointInRectangle(
            point: AnnotationPoint(x: 200, y: 200),
            topLeft: AnnotationPoint(x: 0, y: 0),
            bottomRight: AnnotationPoint(x: 100, y: 100)
        ))
    }

    @Test("Point on rectangle boundary")
    func testPointOnRectangleBoundary() {
        #expect(ROIHelpers.isPointInRectangle(
            point: AnnotationPoint(x: 0, y: 0),
            topLeft: AnnotationPoint(x: 0, y: 0),
            bottomRight: AnnotationPoint(x: 100, y: 100)
        ))
    }

    @Test("Point inside ellipse")
    func testPointInEllipse() {
        let points = [
            AnnotationPoint(x: 100, y: 200),
            AnnotationPoint(x: 300, y: 200),
            AnnotationPoint(x: 200, y: 150),
            AnnotationPoint(x: 200, y: 250)
        ]
        #expect(ROIHelpers.isPointInEllipse(point: AnnotationPoint(x: 200, y: 200), ellipsePoints: points))
    }

    @Test("Point outside ellipse")
    func testPointOutsideEllipse() {
        let points = [
            AnnotationPoint(x: 100, y: 200),
            AnnotationPoint(x: 300, y: 200),
            AnnotationPoint(x: 200, y: 150),
            AnnotationPoint(x: 200, y: 250)
        ]
        #expect(!ROIHelpers.isPointInEllipse(point: AnnotationPoint(x: 500, y: 500), ellipsePoints: points))
    }

    @Test("Ellipse with invalid points returns false")
    func testEllipseInvalid() {
        #expect(!ROIHelpers.isPointInEllipse(point: AnnotationPoint(x: 0, y: 0), ellipsePoints: []))
    }
}

@Suite("ROIHelpers Pixel Statistics Tests")
struct ROIPixelStatisticsTests {

    @Test("Basic statistics")
    func testBasicStats() {
        let values = [10.0, 20.0, 30.0, 40.0, 50.0]
        let stats = ROIHelpers.computePixelStatistics(values: values)
        #expect(stats.mean == 30.0)
        #expect(stats.minimum == 10.0)
        #expect(stats.maximum == 50.0)
        #expect(abs(stats.stdDev - 14.142) < 0.01)
    }

    @Test("Single value statistics")
    func testSingleValue() {
        let stats = ROIHelpers.computePixelStatistics(values: [42.0])
        #expect(stats.mean == 42.0)
        #expect(stats.minimum == 42.0)
        #expect(stats.maximum == 42.0)
        #expect(stats.stdDev == 0.0)
    }

    @Test("Empty values statistics")
    func testEmptyStats() {
        let stats = ROIHelpers.computePixelStatistics(values: [])
        #expect(stats.mean == 0)
        #expect(stats.minimum == 0)
        #expect(stats.maximum == 0)
    }

    @Test("Uniform values have zero std dev")
    func testUniformValues() {
        let values = [100.0, 100.0, 100.0, 100.0]
        let stats = ROIHelpers.computePixelStatistics(values: values)
        #expect(stats.mean == 100.0)
        #expect(stats.stdDev == 0.0)
    }
}

@Suite("ROIHelpers Physical Conversion Tests")
struct ROIPhysicalConversionTests {

    @Test("Physical area with calibration")
    func testPhysicalArea() {
        let cal = CalibrationModel(pixelSpacingRow: 0.5, pixelSpacingColumn: 0.5, source: .pixelSpacing)
        let area = ROIHelpers.physicalArea(pixelArea: 1000, calibration: cal)
        #expect(area != nil)
        #expect(abs((area ?? 0) - 250.0) < 0.001) // 1000 * 0.5 * 0.5
    }

    @Test("Physical area uncalibrated returns nil")
    func testPhysicalAreaUncalibrated() {
        #expect(ROIHelpers.physicalArea(pixelArea: 1000, calibration: .uncalibrated) == nil)
    }

    @Test("Physical perimeter with calibration")
    func testPhysicalPerimeter() {
        let cal = CalibrationModel(pixelSpacingRow: 0.5, pixelSpacingColumn: 0.5, source: .pixelSpacing)
        let perimeter = ROIHelpers.physicalPerimeter(pixelPerimeter: 100, calibration: cal)
        #expect(perimeter != nil)
        #expect(abs((perimeter ?? 0) - 50.0) < 0.001)
    }

    @Test("Physical perimeter uncalibrated returns nil")
    func testPhysicalPerimeterUncalibrated() {
        #expect(ROIHelpers.physicalPerimeter(pixelPerimeter: 100, calibration: .uncalibrated) == nil)
    }
}

@Suite("ROIHelpers Formatting Tests")
struct ROIFormattingTests {

    @Test("ROI type labels")
    func testROITypeLabels() {
        for roiType in ROIType.allCases {
            #expect(!ROIHelpers.roiTypeLabel(for: roiType).isEmpty)
        }
    }

    @Test("Format area mm²")
    func testFormatAreaMM() {
        let text = ROIHelpers.formatArea(pixelArea: 1000, physicalArea: 250.0, unit: .millimeters)
        #expect(text == "250.0 mm2 (mm²)")
        #expect(text.contains("250.0"))
        #expect(text.contains("mm²"))
    }

    @Test("Format area cm²")
    func testFormatAreaCM() {
        let text = ROIHelpers.formatArea(pixelArea: 1000, physicalArea: 250.0, unit: .centimeters)
        #expect(text == "2.50 cm2 (cm²)")
        #expect(text.contains("2.50"))
        #expect(text.contains("cm²"))
    }

    @Test("Format area uncalibrated")
    func testFormatAreaPixels() {
        let text = ROIHelpers.formatArea(pixelArea: 1000, physicalArea: nil)
        #expect(text.contains("1000"))
        #expect(text.contains("px²"))
    }

    @Test("Format statistics")
    func testFormatStatistics() {
        let stats = ROIStatistics(
            mean: 100.5,
            standardDeviation: 15.3,
            minimum: 50.0,
            maximum: 200.0,
            areaPixels: 1000,
            areaMM2: 250.0,
            perimeterMM: 28.0
        )
        let text = ROIHelpers.formatStatistics(stats)
        #expect(text.contains("Mean: 100.5"))
        #expect(text.contains("Std Dev: 15.3"))
        #expect(text.contains("Min: 50.0"))
        #expect(text.contains("Max: 200.0"))
        #expect(text.contains("Pixels: 1000"))
        #expect(text.contains("Area: 250.0 mm2 (mm²)"))   // UCUM code (PS3.16 2026a CID 7461) with the symbol, as dicom-measure prints it
        #expect(text.contains("Perimeter: 28.0 mm"))
    }
}
