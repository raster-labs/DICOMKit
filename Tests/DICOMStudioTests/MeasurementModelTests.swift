// MeasurementModelTests.swift
// DICOMStudioTests
//
// Tests for Measurement models

import Testing
@testable import DICOMStudio
import Foundation

@Suite("MeasurementUnit Tests")
struct MeasurementUnitTests {

    @Test("All units have raw values")
    func testRawValues() {
        #expect(MeasurementUnit.millimeters.rawValue == "mm")
        #expect(MeasurementUnit.centimeters.rawValue == "cm")
        #expect(MeasurementUnit.inches.rawValue == "in")
        #expect(MeasurementUnit.micrometers.rawValue == "um")
    }

    @Test("CaseIterable has 4 units")
    func testCaseIterable() {
        #expect(MeasurementUnit.allCases.count == 4)
    }

    // PS3.16 2026a CID 7460: (um, UCUM, "micrometer"); CID 7461: (um2, UCUM, "square micrometer")
    @Test("micrometers is the CID 7460 code um, displayed as µm; area code um2 (CID 7461)")
    func testMicrometers() {
        #expect(MeasurementUnit(rawValue: "um") == .micrometers)
        #expect(MeasurementUnit.micrometers.displaySymbol == "µm")
        #expect(MeasurementUnit.millimeters.displaySymbol == "mm")
        #expect(ROIHelpers.ucumAreaCode(for: .micrometers) == "um2")
        #expect(ROIHelpers.areaUnitText(for: .micrometers) == "um2 (µm²)")
        #expect(MeasurementHelpers.convert(mm: 1.5, to: .micrometers) == 1500)
        #expect(MeasurementHelpers.formatLength(pixels: 10, mm: 0.25, unit: .micrometers) == "250.0 µm")
        #expect(ROIHelpers.formatArea(pixelArea: 10, physicalArea: 0.5, unit: .micrometers) == "500000 um2 (µm²)")
    }
}

@Suite("MeasurementToolType Tests")
struct MeasurementToolTypeTests {

    @Test("All tool types have raw values")
    func testRawValues() {
        #expect(MeasurementToolType.length.rawValue == "LENGTH")
        #expect(MeasurementToolType.angle.rawValue == "ANGLE")
        #expect(MeasurementToolType.cobbAngle.rawValue == "COBB_ANGLE")
        #expect(MeasurementToolType.bidirectional.rawValue == "BIDIRECTIONAL")
        #expect(MeasurementToolType.ellipticalROI.rawValue == "ELLIPTICAL_ROI")
        #expect(MeasurementToolType.rectangularROI.rawValue == "RECTANGULAR_ROI")
        #expect(MeasurementToolType.freehandROI.rawValue == "FREEHAND_ROI")
        #expect(MeasurementToolType.polygonalROI.rawValue == "POLYGONAL_ROI")
        #expect(MeasurementToolType.circularROI.rawValue == "CIRCULAR_ROI")
        #expect(MeasurementToolType.textAnnotation.rawValue == "TEXT_ANNOTATION")
        #expect(MeasurementToolType.arrowAnnotation.rawValue == "ARROW_ANNOTATION")
        #expect(MeasurementToolType.marker.rawValue == "MARKER")
    }

    @Test("CaseIterable has 12 tool types")
    func testCaseIterable() {
        #expect(MeasurementToolType.allCases.count == 12)
    }
}

@Suite("CalibrationSource Tests")
struct CalibrationSourceTests {

    @Test("All sources have raw values")
    func testRawValues() {
        #expect(CalibrationSource.pixelSpacing.rawValue == "PIXEL_SPACING")
        #expect(CalibrationSource.imagerPixelSpacing.rawValue == "IMAGER_PIXEL_SPACING")
        #expect(CalibrationSource.manual.rawValue == "MANUAL")
        #expect(CalibrationSource.unknown.rawValue == "UNKNOWN")
    }

    @Test("CaseIterable has 5 sources")
    func testCaseIterable() {
        #expect(CalibrationSource.allCases.count == 5)
    }
}

@Suite("CalibrationModel Tests")
struct CalibrationModelTests {

    @Test("Default uncalibrated model")
    func testUncalibrated() {
        let cal = CalibrationModel.uncalibrated
        #expect(!cal.isCalibrated)
        #expect(cal.pixelSpacingRow == 0.0)
        #expect(cal.pixelSpacingColumn == 0.0)
        #expect(cal.source == .unknown)
    }

    @Test("Calibrated model is valid")
    func testCalibrated() {
        let cal = CalibrationModel(pixelSpacingRow: 0.5, pixelSpacingColumn: 0.5, source: .pixelSpacing)
        #expect(cal.isCalibrated)
        #expect(cal.averageSpacing == 0.5)
    }

    @Test("Anisotropic spacing average")
    func testAnisotropicAverage() {
        let cal = CalibrationModel(pixelSpacingRow: 0.4, pixelSpacingColumn: 0.6, source: .pixelSpacing)
        #expect(abs(cal.averageSpacing - 0.5) < 0.001)
    }

    @Test("CalibrationModel is Equatable")
    func testEquatable() {
        let a = CalibrationModel(pixelSpacingRow: 0.5, pixelSpacingColumn: 0.5, source: .pixelSpacing)
        let b = CalibrationModel(pixelSpacingRow: 0.5, pixelSpacingColumn: 0.5, source: .pixelSpacing)
        #expect(a == b)
    }

    @Test("CalibrationModel is Hashable")
    func testHashable() {
        let cal = CalibrationModel(pixelSpacingRow: 0.5, pixelSpacingColumn: 0.5, source: .pixelSpacing)
        var set: Set<CalibrationModel> = []
        set.insert(cal)
        #expect(set.contains(cal))
    }
}

@Suite("AnnotationStyle Tests")
struct AnnotationStyleTests {

    @Test("Default style values")
    func testDefaultStyle() {
        let style = AnnotationStyle.defaultStyle
        #expect(style.lineWidth == 2.0)
        #expect(style.colorRed == 1.0)
        #expect(style.colorGreen == 1.0)
        #expect(style.colorBlue == 0.0)
        #expect(style.opacity == 1.0)
        #expect(style.fontSize == 12.0)
    }

    @Test("Active style is green")
    func testActiveStyle() {
        let style = AnnotationStyle.activeStyle
        #expect(style.colorGreen == 1.0)
        #expect(style.colorRed == 0.0)
    }

    @Test("Warning style is red")
    func testWarningStyle() {
        let style = AnnotationStyle.warningStyle
        #expect(style.colorRed == 1.0)
        #expect(style.colorGreen == 0.0)
    }

    @Test("Clamped values")
    func testClamping() {
        let style = AnnotationStyle(lineWidth: -1, colorRed: 2.0, colorGreen: -1.0, opacity: 5.0, fontSize: 1.0)
        #expect(style.lineWidth == 0.5)
        #expect(style.colorRed == 1.0)
        #expect(style.colorGreen == 0.0)
        #expect(style.opacity == 1.0)
        #expect(style.fontSize == 6.0)
    }

    @Test("AnnotationStyle is Equatable")
    func testEquatable() {
        let a = AnnotationStyle.defaultStyle
        let b = AnnotationStyle()
        #expect(a == b)
    }
}

@Suite("LinearMeasurementResult Tests")
struct LinearMeasurementResultTests {

    @Test("Result creation")
    func testCreation() {
        let result = LinearMeasurementResult(
            lengthPixels: 100,
            lengthMM: 50,
            startPoint: AnnotationPoint(x: 0, y: 0),
            endPoint: AnnotationPoint(x: 100, y: 0)
        )
        #expect(result.lengthPixels == 100)
        #expect(result.lengthMM == 50)
    }

    @Test("Result without physical distance")
    func testNilMM() {
        let result = LinearMeasurementResult(
            lengthPixels: 100,
            lengthMM: nil,
            startPoint: AnnotationPoint(x: 0, y: 0),
            endPoint: AnnotationPoint(x: 100, y: 0)
        )
        #expect(result.lengthMM == nil)
    }
}

@Suite("AngleMeasurementResult Tests")
struct AngleMeasurementResultTests {

    @Test("Result creation")
    func testCreation() {
        let result = AngleMeasurementResult(
            angleDegrees: 90,
            vertex: AnnotationPoint(x: 0, y: 0),
            point1: AnnotationPoint(x: 100, y: 0),
            point2: AnnotationPoint(x: 0, y: 100)
        )
        #expect(result.angleDegrees == 90)
    }
}

@Suite("CobbAngleMeasurementResult Tests")
struct CobbAngleMeasurementResultTests {

    @Test("Result creation")
    func testCreation() {
        let result = CobbAngleMeasurementResult(
            angleDegrees: 45,
            line1Start: AnnotationPoint(x: 0, y: 0),
            line1End: AnnotationPoint(x: 100, y: 0),
            line2Start: AnnotationPoint(x: 0, y: 100),
            line2End: AnnotationPoint(x: 100, y: 100)
        )
        #expect(result.angleDegrees == 45)
    }
}

@Suite("BidirectionalMeasurementResult Tests")
struct BidirectionalMeasurementResultTests {

    @Test("Result creation")
    func testCreation() {
        let result = BidirectionalMeasurementResult(
            longAxisPixels: 200,
            shortAxisPixels: 100,
            longAxisMM: 100.0,
            shortAxisMM: 50.0,
            longAxisStart: AnnotationPoint(x: 0, y: 100),
            longAxisEnd: AnnotationPoint(x: 200, y: 100),
            shortAxisStart: AnnotationPoint(x: 100, y: 50),
            shortAxisEnd: AnnotationPoint(x: 100, y: 150)
        )
        #expect(result.longAxisPixels == 200)
        #expect(result.shortAxisPixels == 100)
        #expect(result.longAxisMM == 100.0)
        #expect(result.shortAxisMM == 50.0)
    }
}

@Suite("MeasurementEntry Tests")
struct MeasurementEntryTests {

    @Test("Default creation")
    func testDefaults() {
        let entry = MeasurementEntry(
            toolType: .length,
            points: [AnnotationPoint(x: 0, y: 0), AnnotationPoint(x: 100, y: 0)]
        )
        #expect(entry.toolType == .length)
        #expect(entry.points.count == 2)
        #expect(entry.label == "")
        #expect(entry.isVisible == true)
        #expect(entry.isLocked == false)
    }

    @Test("Identifiable with unique IDs")
    func testIdentifiable() {
        let a = MeasurementEntry(toolType: .length, points: [])
        let b = MeasurementEntry(toolType: .length, points: [])
        #expect(a.id != b.id)
    }

    @Test("withVisibility creates new entry")
    func testWithVisibility() {
        let entry = MeasurementEntry(toolType: .length, points: [])
        let hidden = entry.withVisibility(false)
        #expect(hidden.isVisible == false)
        #expect(hidden.id == entry.id)
        #expect(entry.isVisible == true)
    }

    @Test("withLocked creates new entry")
    func testWithLocked() {
        let entry = MeasurementEntry(toolType: .angle, points: [])
        let locked = entry.withLocked(true)
        #expect(locked.isLocked == true)
        #expect(locked.id == entry.id)
    }

    @Test("withLabel creates new entry")
    func testWithLabel() {
        let entry = MeasurementEntry(toolType: .marker, points: [])
        let labeled = entry.withLabel("Test Label")
        #expect(labeled.label == "Test Label")
        #expect(labeled.id == entry.id)
    }

    @Test("withStyle creates new entry")
    func testWithStyle() {
        let entry = MeasurementEntry(toolType: .length, points: [])
        let styled = entry.withStyle(.activeStyle)
        #expect(styled.style == AnnotationStyle.activeStyle)
        #expect(styled.id == entry.id)
    }

    @Test("Equatable")
    func testEquatable() {
        let id = UUID()
        let date = Date()
        let a = MeasurementEntry(id: id, toolType: .length, points: [], createdAt: date)
        let b = MeasurementEntry(id: id, toolType: .length, points: [], createdAt: date)
        #expect(a == b)
    }
}

@Suite("MeasurementAction Tests")
struct MeasurementActionTests {

    @Test("Add action")
    func testAdd() {
        let entry = MeasurementEntry(toolType: .length, points: [])
        let action = MeasurementAction.add(entry)
        #expect(action == MeasurementAction.add(entry))
    }

    @Test("Remove action")
    func testRemove() {
        let entry = MeasurementEntry(toolType: .angle, points: [])
        let action = MeasurementAction.remove(entry)
        #expect(action == MeasurementAction.remove(entry))
    }

    @Test("Update action")
    func testUpdate() {
        let old = MeasurementEntry(toolType: .length, points: [])
        let new = old.withLabel("Updated")
        let action = MeasurementAction.update(old: old, new: new)
        #expect(action == MeasurementAction.update(old: old, new: new))
    }
}
