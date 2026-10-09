import Testing
import Foundation
import DICOMCore
@testable import DICOMKit

// MARK: - Measurement Tests

@Suite("Measurement Tests")
struct MeasurementTests {
    
    @Test("Measurement from NumericContentItem with single value")
    func testMeasurementFromNumericContentItem() {
        let units = CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "millimeter")
        let concept = CodedConcept(codeValue: "12345", codingSchemeDesignator: "SCT", codeMeaning: "Length")
        
        let numericItem = NumericContentItem(
            conceptName: concept,
            value: 25.4,
            units: units,
            relationshipType: .contains
        )
        
        let measurement = Measurement(from: numericItem)
        
        #expect(measurement.value == 25.4)
        #expect(measurement.conceptName == concept)
        #expect(measurement.unit != nil)
        #expect(measurement.unit?.code == "mm")
        #expect(measurement.additionalValues.isEmpty)
        #expect(!measurement.isMultiValue)
    }
    
    @Test("Measurement from NumericContentItem with multiple values")
    func testMeasurementWithMultipleValues() {
        let units = CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "millimeter")
        
        let numericItem = NumericContentItem(
            conceptName: nil,
            values: [10.0, 20.0, 30.0],
            units: units
        )
        
        let measurement = Measurement(from: numericItem)
        
        #expect(measurement.value == 10.0)
        #expect(measurement.additionalValues == [20.0, 30.0])
        #expect(measurement.allValues == [10.0, 20.0, 30.0])
        #expect(measurement.isMultiValue)
    }
    
    @Test("Measurement with qualifier")
    func testMeasurementWithQualifier() {
        let numericItem = NumericContentItem(
            conceptName: nil,
            values: [Double.nan],
            units: nil,
            floatingPointValues: nil,
            qualifier: .notANumber
        )
        
        let measurement = Measurement(from: numericItem)
        
        #expect(measurement.qualifier == .notANumber)
    }
    
    @Test("Measurement unit conversion mm to cm")
    func testMeasurementUnitConversion() {
        let measurement = Measurement(
            conceptName: nil,
            value: 25.4,
            unit: .millimeter
        )
        
        let converted = measurement.converted(to: .centimeter)
        
        #expect(converted != nil)
        #expect(abs(converted!.value - 2.54) < 0.001)
        #expect(converted!.unit == .centimeter)
    }
    
    @Test("Measurement unit conversion with multiple values")
    func testMeasurementUnitConversionMultipleValues() {
        let measurement = Measurement(
            conceptName: nil,
            value: 10.0,
            additionalValues: [20.0, 30.0],
            unit: .millimeter
        )
        
        let converted = measurement.converted(to: .centimeter)
        
        #expect(converted != nil)
        #expect(abs(converted!.value - 1.0) < 0.001)
        #expect(converted!.additionalValues.count == 2)
        #expect(abs(converted!.additionalValues[0] - 2.0) < 0.001)
        #expect(abs(converted!.additionalValues[1] - 3.0) < 0.001)
    }
    
    @Test("Measurement unit conversion fails for incompatible units")
    func testMeasurementUnitConversionIncompatible() {
        let measurement = Measurement(
            conceptName: nil,
            value: 25.4,
            unit: .millimeter
        )
        
        let converted = measurement.converted(to: .second)
        
        #expect(converted == nil)
    }
    
    @Test("Measurement unit conversion without unit returns nil")
    func testMeasurementUnitConversionNoUnit() {
        let measurement = Measurement(
            conceptName: nil,
            value: 25.4,
            unit: nil
        )
        
        let converted = measurement.converted(to: .centimeter)
        
        #expect(converted == nil)
    }
    
    @Test("Measurement description")
    func testMeasurementDescription() {
        let concept = CodedConcept(codeValue: "LENGTH", codingSchemeDesignator: "TEST", codeMeaning: "Length")
        let measurement = Measurement(
            conceptName: concept,
            value: 25.4,
            unit: .millimeter
        )
        
        let desc = measurement.description
        #expect(desc.contains("Length"))
        #expect(desc.contains("25.4"))
        #expect(desc.contains("millimeter"))
    }
}

// MARK: - MeasurementQualifier Tests

@Suite("MeasurementQualifier Tests")
struct MeasurementQualifierTests {
    
    @Test("All qualifier cases exist")
    func testAllQualifierCases() {
        let cases = MeasurementQualifier.allCases
        #expect(cases.count == 12)
        #expect(cases.contains(.notANumber))
        #expect(cases.contains(.negativeInfinity))
        #expect(cases.contains(.positiveInfinity))
        #expect(cases.contains(.underflow))
        #expect(cases.contains(.overflow))
    }
    
    @Test("Qualifier from NumericValueQualifier")
    func testQualifierFromNumericValueQualifier() {
        #expect(MeasurementQualifier(from: .notANumber) == .notANumber)
        #expect(MeasurementQualifier(from: .negativeInfinity) == .negativeInfinity)
        #expect(MeasurementQualifier(from: .positiveInfinity) == .positiveInfinity)
        #expect(MeasurementQualifier(from: .underflow) == .underflow)
        #expect(MeasurementQualifier(from: .overflow) == .overflow)
    }
}

// MARK: - DerivationMethod Tests

@Suite("DerivationMethod Tests")
struct DerivationMethodTests {
    
    @Test("All derivation method cases exist")
    func testAllDerivationMethodCases() {
        let cases = DerivationMethod.allCases
        #expect(cases.count == 5)
        #expect(cases.contains(.manual))
        #expect(cases.contains(.automatic))
        #expect(cases.contains(.semiAutomatic))
        #expect(cases.contains(.calculated))
        #expect(cases.contains(.estimated))
    }
}

// MARK: - MeasurementGroup Tests

@Suite("MeasurementGroup Tests")
struct MeasurementGroupTests {
    
    @Test("MeasurementGroup creation and properties")
    func testMeasurementGroupBasics() {
        let concept = CodedConcept(codeValue: "LESION", codingSchemeDesignator: "TEST", codeMeaning: "Lesion Measurements")
        let location = CodedConcept(codeValue: "LIVER", codingSchemeDesignator: "SCT", codeMeaning: "Liver")
        
        let m1 = Measurement(conceptName: nil, value: 10.0, unit: .millimeter)
        let m2 = Measurement(conceptName: nil, value: 20.0, unit: .millimeter)
        let m3 = Measurement(conceptName: nil, value: 30.0, unit: .millimeter)
        
        let group = MeasurementGroup(
            conceptName: concept,
            measurements: [m1, m2, m3],
            anatomicalLocation: location
        )
        
        #expect(group.count == 3)
        #expect(!group.isEmpty)
        #expect(group.conceptName == concept)
        #expect(group.anatomicalLocation == location)
    }
    
    @Test("MeasurementGroup empty")
    func testMeasurementGroupEmpty() {
        let group = MeasurementGroup(measurements: [])
        
        #expect(group.isEmpty)
        #expect(group.count == 0)
    }
    
    @Test("MeasurementGroup find by concept")
    func testMeasurementGroupFindByConcept() {
        let lengthConcept = CodedConcept(codeValue: "LENGTH", codingSchemeDesignator: "TEST", codeMeaning: "Length")
        let widthConcept = CodedConcept(codeValue: "WIDTH", codingSchemeDesignator: "TEST", codeMeaning: "Width")
        
        let m1 = Measurement(conceptName: lengthConcept, value: 10.0, unit: .millimeter)
        let m2 = Measurement(conceptName: widthConcept, value: 20.0, unit: .millimeter)
        let m3 = Measurement(conceptName: lengthConcept, value: 30.0, unit: .millimeter)
        
        let group = MeasurementGroup(measurements: [m1, m2, m3])
        
        let lengths = group.measurements(forConcept: lengthConcept)
        #expect(lengths.count == 2)
        #expect(lengths[0].value == 10.0)
        #expect(lengths[1].value == 30.0)
        
        let widths = group.measurements(forConcept: widthConcept)
        #expect(widths.count == 1)
        #expect(widths[0].value == 20.0)
    }
    
    @Test("MeasurementGroup find by concept string")
    func testMeasurementGroupFindByConceptString() {
        let lengthConcept = CodedConcept(codeValue: "LENGTH", codingSchemeDesignator: "TEST", codeMeaning: "Length")
        let m1 = Measurement(conceptName: lengthConcept, value: 10.0)
        
        let group = MeasurementGroup(measurements: [m1])
        
        let byMeaning = group.measurements(forConceptString: "Length")
        #expect(byMeaning.count == 1)
        
        let byCode = group.measurements(forConceptString: "LENGTH")
        #expect(byCode.count == 1)
    }
    
    @Test("MeasurementGroup value for concept")
    func testMeasurementGroupValueForConcept() {
        let lengthConcept = CodedConcept(codeValue: "LENGTH", codingSchemeDesignator: "TEST", codeMeaning: "Length")
        let m1 = Measurement(conceptName: lengthConcept, value: 42.0)
        
        let group = MeasurementGroup(measurements: [m1])
        
        #expect(group.value(forConcept: lengthConcept) == 42.0)
        
        let otherConcept = CodedConcept(codeValue: "OTHER", codingSchemeDesignator: "TEST", codeMeaning: "Other")
        #expect(group.value(forConcept: otherConcept) == nil)
    }
    
    @Test("MeasurementGroup description")
    func testMeasurementGroupDescription() {
        let concept = CodedConcept(codeValue: "TEST", codingSchemeDesignator: "TEST", codeMeaning: "Test Group")
        let m1 = Measurement(conceptName: nil, value: 10.0)
        let m2 = Measurement(conceptName: nil, value: 20.0)
        
        let group = MeasurementGroup(conceptName: concept, measurements: [m1, m2])
        
        let desc = group.description
        #expect(desc.contains("Test Group"))
        #expect(desc.contains("2 measurements"))
    }
}

// MARK: - SpatialCoordinates Tests

@Suite("SpatialCoordinates Tests")
struct SpatialCoordinatesTests {
    
    @Test("SpatialCoordinates point")
    func testSpatialCoordinatesPoint() {
        let item = SpatialCoordinatesContentItem(
            graphicType: .point,
            graphicData: [100.0, 200.0]
        )
        
        let coords = SpatialCoordinates(contentItem: item)
        
        #expect(coords.graphicType == .point)
        #expect(coords.pointCount == 1)
        #expect(coords.points.count == 1)
        #expect(coords.points[0].column == 100.0)
        #expect(coords.points[0].row == 200.0)
    }
    
    @Test("SpatialCoordinates polygon")
    func testSpatialCoordinatesPolygon() {
        // Triangle
        let item = SpatialCoordinatesContentItem(
            graphicType: .polygon,
            graphicData: [0.0, 0.0, 100.0, 0.0, 50.0, 100.0]
        )
        
        let coords = SpatialCoordinates(contentItem: item)
        
        #expect(coords.graphicType == .polygon)
        #expect(coords.pointCount == 3)
    }
    
    @Test("SpatialCoordinates bounding box")
    func testSpatialCoordinatesBoundingBox() {
        let item = SpatialCoordinatesContentItem(
            graphicType: .polygon,
            graphicData: [10.0, 20.0, 50.0, 30.0, 30.0, 80.0]
        )
        
        let coords = SpatialCoordinates(contentItem: item)
        let bbox = coords.boundingBox
        
        #expect(bbox != nil)
        #expect(bbox!.minColumn == 10.0)
        #expect(bbox!.minRow == 20.0)
        #expect(bbox!.maxColumn == 50.0)
        #expect(bbox!.maxRow == 80.0)
    }
    
    @Test("SpatialCoordinates bounding box empty")
    func testSpatialCoordinatesBoundingBoxEmpty() {
        let item = SpatialCoordinatesContentItem(
            graphicType: .point,
            graphicData: []
        )
        
        let coords = SpatialCoordinates(contentItem: item)
        #expect(coords.boundingBox == nil)
    }
    
    @Test("SpatialCoordinates centroid")
    func testSpatialCoordinatesCentroid() {
        let item = SpatialCoordinatesContentItem(
            graphicType: .polygon,
            graphicData: [0.0, 0.0, 100.0, 0.0, 100.0, 100.0, 0.0, 100.0]
        )
        
        let coords = SpatialCoordinates(contentItem: item)
        let centroid = coords.centroid
        
        #expect(centroid != nil)
        #expect(centroid!.column == 50.0)
        #expect(centroid!.row == 50.0)
    }
    
    @Test("SpatialCoordinates centroid empty")
    func testSpatialCoordinatesCentroidEmpty() {
        let item = SpatialCoordinatesContentItem(
            graphicType: .point,
            graphicData: []
        )
        
        let coords = SpatialCoordinates(contentItem: item)
        #expect(coords.centroid == nil)
    }
    
    @Test("SpatialCoordinates perimeter polyline")
    func testSpatialCoordinatesPerimeterPolyline() {
        // Horizontal line of length 100
        let item = SpatialCoordinatesContentItem(
            graphicType: .polyline,
            graphicData: [0.0, 0.0, 100.0, 0.0]
        )
        
        let coords = SpatialCoordinates(contentItem: item)
        
        #expect(abs(coords.perimeter - 100.0) < 0.001)
    }
    
    @Test("SpatialCoordinates perimeter polygon")
    func testSpatialCoordinatesPerimeterPolygon() {
        // Square with side 100
        let item = SpatialCoordinatesContentItem(
            graphicType: .polygon,
            graphicData: [0.0, 0.0, 100.0, 0.0, 100.0, 100.0, 0.0, 100.0]
        )
        
        let coords = SpatialCoordinates(contentItem: item)
        
        #expect(abs(coords.perimeter - 400.0) < 0.001)
    }
    
    @Test("SpatialCoordinates area polygon")
    func testSpatialCoordinatesAreaPolygon() {
        // Square with side 100 (area = 10000)
        let item = SpatialCoordinatesContentItem(
            graphicType: .polygon,
            graphicData: [0.0, 0.0, 100.0, 0.0, 100.0, 100.0, 0.0, 100.0]
        )
        
        let coords = SpatialCoordinates(contentItem: item)
        
        #expect(coords.area != nil)
        #expect(abs(coords.area! - 10000.0) < 0.001)
    }
    
    @Test("SpatialCoordinates area non-polygon returns nil")
    func testSpatialCoordinatesAreaNonPolygon() {
        let item = SpatialCoordinatesContentItem(
            graphicType: .polyline,
            graphicData: [0.0, 0.0, 100.0, 0.0]
        )
        
        let coords = SpatialCoordinates(contentItem: item)
        
        #expect(coords.area == nil)
    }
    
    @Test("SpatialCoordinates circle radius")
    func testSpatialCoordinatesCircleRadius() {
        // Circle with center at (50, 50) and edge at (100, 50) - radius = 50
        let item = SpatialCoordinatesContentItem(
            graphicType: .circle,
            graphicData: [50.0, 50.0, 100.0, 50.0]
        )
        
        let coords = SpatialCoordinates(contentItem: item)
        
        #expect(coords.radius != nil)
        #expect(coords.radius! == 50.0)
    }
    
    @Test("SpatialCoordinates circle area")
    func testSpatialCoordinatesCircleArea() {
        // Circle with radius 50
        let item = SpatialCoordinatesContentItem(
            graphicType: .circle,
            graphicData: [50.0, 50.0, 100.0, 50.0]
        )
        
        let coords = SpatialCoordinates(contentItem: item)
        let expectedArea = Float.pi * 50.0 * 50.0
        
        #expect(coords.circleArea != nil)
        #expect(abs(coords.circleArea! - expectedArea) < 0.001)
    }
    
    @Test("SpatialCoordinates ellipse area")
    func testSpatialCoordinatesEllipseArea() {
        // Ellipse with semi-major axis 50, semi-minor axis 25
        // Points: major axis endpoints (0, 50), (100, 50), minor axis endpoints (50, 25), (50, 75)
        let item = SpatialCoordinatesContentItem(
            graphicType: .ellipse,
            graphicData: [0.0, 50.0, 100.0, 50.0, 50.0, 25.0, 50.0, 75.0]
        )
        
        let coords = SpatialCoordinates(contentItem: item)
        let expectedArea = Float.pi * 50.0 * 25.0
        
        #expect(coords.ellipseArea != nil)
        #expect(abs(coords.ellipseArea! - expectedArea) < 0.1)
    }
    
    @Test("SpatialCoordinates with image reference")
    func testSpatialCoordinatesWithImageReference() {
        let item = SpatialCoordinatesContentItem(
            graphicType: .point,
            graphicData: [100.0, 200.0]
        )
        
        let imageRef = ImageReference(sopClassUID: "1.2.3", sopInstanceUID: "4.5.6")
        let coords = SpatialCoordinates(contentItem: item, imageReference: imageRef)
        
        #expect(coords.imageReference != nil)
        #expect(coords.imageReference?.sopReference.sopInstanceUID == "4.5.6")
    }
}

// MARK: - SpatialCoordinates3D Tests

@Suite("SpatialCoordinates3D Tests")
struct SpatialCoordinates3DTests {
    
    @Test("SpatialCoordinates3D point")
    func testSpatialCoordinates3DPoint() {
        let item = SpatialCoordinates3DContentItem(
            graphicType: .point,
            graphicData: [10.0, 20.0, 30.0],
            frameOfReferenceUID: "1.2.3.4.5"
        )
        
        let coords = SpatialCoordinates3D(contentItem: item)
        
        #expect(coords.graphicType == .point)
        #expect(coords.pointCount == 1)
        #expect(coords.frameOfReferenceUID == "1.2.3.4.5")
        #expect(coords.points[0].x == 10.0)
        #expect(coords.points[0].y == 20.0)
        #expect(coords.points[0].z == 30.0)
    }
    
    @Test("SpatialCoordinates3D bounding box")
    func testSpatialCoordinates3DBoundingBox() {
        let item = SpatialCoordinates3DContentItem(
            graphicType: .polyline,
            graphicData: [0.0, 0.0, 0.0, 100.0, 50.0, 25.0, 50.0, 100.0, 75.0]
        )
        
        let coords = SpatialCoordinates3D(contentItem: item)
        let bbox = coords.boundingBox
        
        #expect(bbox != nil)
        #expect(bbox!.minX == 0.0)
        #expect(bbox!.minY == 0.0)
        #expect(bbox!.minZ == 0.0)
        #expect(bbox!.maxX == 100.0)
        #expect(bbox!.maxY == 100.0)
        #expect(bbox!.maxZ == 75.0)
    }
    
    @Test("SpatialCoordinates3D centroid")
    func testSpatialCoordinates3DCentroid() {
        let item = SpatialCoordinates3DContentItem(
            graphicType: .polygon,
            graphicData: [0.0, 0.0, 0.0, 100.0, 0.0, 0.0, 100.0, 100.0, 0.0, 0.0, 100.0, 0.0]
        )
        
        let coords = SpatialCoordinates3D(contentItem: item)
        let centroid = coords.centroid
        
        #expect(centroid != nil)
        #expect(centroid!.x == 50.0)
        #expect(centroid!.y == 50.0)
        #expect(centroid!.z == 0.0)
    }
    
    @Test("SpatialCoordinates3D path length")
    func testSpatialCoordinates3DPathLength() {
        // Straight line along X axis of length 100
        let item = SpatialCoordinates3DContentItem(
            graphicType: .polyline,
            graphicData: [0.0, 0.0, 0.0, 100.0, 0.0, 0.0]
        )
        
        let coords = SpatialCoordinates3D(contentItem: item)
        
        #expect(abs(coords.pathLength - 100.0) < 0.001)
    }
}

// MARK: - TemporalCoordinates Tests

@Suite("TemporalCoordinates Tests")
struct TemporalCoordinatesTests {
    
    @Test("TemporalCoordinates with sample positions")
    func testTemporalCoordinatesSamplePositions() {
        let item = TemporalCoordinatesContentItem(
            temporalRangeType: .point,
            samplePositions: [100, 200, 300]
        )
        
        let coords = TemporalCoordinates(contentItem: item)
        
        #expect(coords.rangeType == .point)
        #expect(coords.samplePositions == [100, 200, 300])
        #expect(coords.timeOffsets == nil)
        #expect(coords.dateTimes == nil)
        #expect(coords.isPoint)
        #expect(!coords.isRange)
    }
    
    @Test("TemporalCoordinates with time offsets")
    func testTemporalCoordinatesTimeOffsets() {
        let item = TemporalCoordinatesContentItem(
            temporalRangeType: .segment,
            timeOffsets: [0.0, 10.5, 20.0]
        )
        
        let coords = TemporalCoordinates(contentItem: item)
        
        #expect(coords.rangeType == .segment)
        #expect(coords.timeOffsets == [0.0, 10.5, 20.0])
        #expect(coords.isRange)
        #expect(!coords.isPoint)
    }
    
    @Test("TemporalCoordinates with datetimes")
    func testTemporalCoordinatesDateTimes() {
        let item = TemporalCoordinatesContentItem(
            temporalRangeType: .multipoint,
            dateTimes: ["20240101120000", "20240101130000"]
        )
        
        let coords = TemporalCoordinates(contentItem: item)
        
        #expect(coords.dateTimes == ["20240101120000", "20240101130000"])
    }
    
    @Test("TemporalCoordinates duration")
    func testTemporalCoordinatesDuration() {
        let item = TemporalCoordinatesContentItem(
            temporalRangeType: .segment,
            timeOffsets: [5.0, 15.0, 10.0]
        )
        
        let coords = TemporalCoordinates(contentItem: item)
        
        #expect(coords.duration == 10.0) // 15 - 5
    }
    
    @Test("TemporalCoordinates duration with single value returns nil")
    func testTemporalCoordinatesDurationSingleValue() {
        let item = TemporalCoordinatesContentItem(
            temporalRangeType: .point,
            timeOffsets: [5.0]
        )
        
        let coords = TemporalCoordinates(contentItem: item)
        
        #expect(coords.duration == nil)
    }
}

// MARK: - ROI Tests

@Suite("ROI Tests")
struct ROITests {
    
    @Test("ROI from 2D coordinates")
    func testROIFrom2DCoordinates() {
        let scoordItem = SpatialCoordinatesContentItem(
            graphicType: .polygon,
            graphicData: [0.0, 0.0, 100.0, 0.0, 100.0, 100.0, 0.0, 100.0]
        )
        
        let coords = SpatialCoordinates(contentItem: scoordItem)
        let concept = CodedConcept(codeValue: "LESION", codingSchemeDesignator: "TEST", codeMeaning: "Lesion")
        
        let roi = ROI(
            identifier: "ROI-001",
            conceptName: concept,
            spatialCoordinates: coords,
            measurements: []
        )
        
        #expect(roi.has2DCoordinates)
        #expect(!roi.has3DCoordinates)
        #expect(roi.graphicType == "POLYGON")
        #expect(roi.identifier == "ROI-001")
        #expect(roi.conceptName == concept)
    }
    
    @Test("ROI from 3D coordinates")
    func testROIFrom3DCoordinates() {
        let scoord3DItem = SpatialCoordinates3DContentItem(
            graphicType: .polygon,
            graphicData: [0.0, 0.0, 0.0, 100.0, 0.0, 0.0, 100.0, 100.0, 0.0]
        )
        
        let coords = SpatialCoordinates3D(contentItem: scoord3DItem)
        
        let roi = ROI(spatialCoordinates3D: coords)
        
        #expect(!roi.has2DCoordinates)
        #expect(roi.has3DCoordinates)
        #expect(roi.graphicType == "POLYGON")
    }
    
    @Test("ROI with measurements")
    func testROIWithMeasurements() {
        let scoordItem = SpatialCoordinatesContentItem(
            graphicType: .circle,
            graphicData: [50.0, 50.0, 100.0, 50.0]
        )
        let coords = SpatialCoordinates(contentItem: scoordItem)
        
        let m1 = Measurement(conceptName: nil, value: 50.0, unit: .millimeter)
        let m2 = Measurement(conceptName: nil, value: 100.0, unit: .squareMillimeter)
        
        let roi = ROI(
            spatialCoordinates: coords,
            measurements: [m1, m2]
        )
        
        #expect(roi.measurements.count == 2)
    }
    
    @Test("ROI bounding box 2D")
    func testROIBoundingBox2D() {
        let scoordItem = SpatialCoordinatesContentItem(
            graphicType: .polygon,
            graphicData: [10.0, 20.0, 100.0, 20.0, 100.0, 80.0, 10.0, 80.0]
        )
        let coords = SpatialCoordinates(contentItem: scoordItem)
        let roi = ROI(spatialCoordinates: coords)
        
        let bbox = roi.boundingBox2D
        #expect(bbox != nil)
        #expect(bbox!.minColumn == 10.0)
        #expect(bbox!.minRow == 20.0)
        #expect(bbox!.maxColumn == 100.0)
        #expect(bbox!.maxRow == 80.0)
    }
    
    @Test("ROI centroid 2D")
    func testROICentroid2D() {
        let scoordItem = SpatialCoordinatesContentItem(
            graphicType: .polygon,
            graphicData: [0.0, 0.0, 100.0, 0.0, 100.0, 100.0, 0.0, 100.0]
        )
        let coords = SpatialCoordinates(contentItem: scoordItem)
        let roi = ROI(spatialCoordinates: coords)
        
        let centroid = roi.centroid2D
        #expect(centroid != nil)
        #expect(centroid!.column == 50.0)
        #expect(centroid!.row == 50.0)
    }
    
    @Test("ROI area")
    func testROIArea() {
        let scoordItem = SpatialCoordinatesContentItem(
            graphicType: .polygon,
            graphicData: [0.0, 0.0, 100.0, 0.0, 100.0, 100.0, 0.0, 100.0]
        )
        let coords = SpatialCoordinates(contentItem: scoordItem)
        let roi = ROI(spatialCoordinates: coords)
        
        #expect(roi.area != nil)
        #expect(abs(roi.area! - 10000.0) < 0.001)
    }
    
    @Test("ROI perimeter")
    func testROIPerimeter() {
        let scoordItem = SpatialCoordinatesContentItem(
            graphicType: .polygon,
            graphicData: [0.0, 0.0, 100.0, 0.0, 100.0, 100.0, 0.0, 100.0]
        )
        let coords = SpatialCoordinates(contentItem: scoordItem)
        let roi = ROI(spatialCoordinates: coords)
        
        #expect(roi.perimeter != nil)
        #expect(abs(roi.perimeter! - 400.0) < 0.001)
    }
    
    @Test("ROI description")
    func testROIDescription() {
        let scoordItem = SpatialCoordinatesContentItem(
            graphicType: .polygon,
            graphicData: [0.0, 0.0, 100.0, 0.0, 100.0, 100.0]
        )
        let coords = SpatialCoordinates(contentItem: scoordItem)
        let concept = CodedConcept(codeValue: "TEST", codingSchemeDesignator: "TEST", codeMeaning: "Test ROI")
        let roi = ROI(conceptName: concept, spatialCoordinates: coords)
        
        let desc = roi.description
        #expect(desc.contains("Test ROI"))
        #expect(desc.contains("2D"))
    }
}

// MARK: - MeasurementExtractor Tests

@Suite("MeasurementExtractor Tests")
struct MeasurementExtractorTests {
    
    private func createTestDocument() -> SRDocument {
        // Create a test SR document with measurements
        let lengthConcept = CodedConcept(codeValue: "LENGTH", codingSchemeDesignator: "TEST", codeMeaning: "Length")
        let widthConcept = CodedConcept(codeValue: "WIDTH", codingSchemeDesignator: "TEST", codeMeaning: "Width")
        let mmUnits = CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "millimeter")
        
        let numericItem1 = NumericContentItem(
            conceptName: lengthConcept,
            value: 25.4,
            units: mmUnits,
            relationshipType: .contains
        )
        
        let numericItem2 = NumericContentItem(
            conceptName: widthConcept,
            value: 12.7,
            units: mmUnits,
            relationshipType: .contains
        )
        
        let scoordItem = SpatialCoordinatesContentItem(
            conceptName: CodedConcept(codeValue: "ROI", codingSchemeDesignator: "TEST", codeMeaning: "Region"),
            graphicType: .polygon,
            graphicData: [0.0, 0.0, 100.0, 0.0, 100.0, 100.0, 0.0, 100.0],
            relationshipType: .contains
        )
        
        let measurementContainer = ContainerContentItem(
            conceptName: CodedConcept(codeValue: "MEAS", codingSchemeDesignator: "TEST", codeMeaning: "Measurements"),
            continuityOfContent: .separate,
            contentItems: [
                AnyContentItem(numericItem1),
                AnyContentItem(numericItem2),
                AnyContentItem(scoordItem)
            ],
            relationshipType: .contains
        )
        
        let rootContainer = ContainerContentItem(
            conceptName: CodedConcept(codeValue: "ROOT", codingSchemeDesignator: "TEST", codeMeaning: "Report"),
            continuityOfContent: .separate,
            contentItems: [AnyContentItem(measurementContainer)]
        )
        
        return SRDocument(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.88.11",
            sopInstanceUID: "1.2.3.4.5.6.7.8",
            rootContent: rootContainer
        )
    }
    
    @Test("Extract all measurements")
    func testExtractAllMeasurements() {
        let document = createTestDocument()
        let extractor = MeasurementExtractor()
        
        let measurements = extractor.extractAllMeasurements(from: document)
        
        #expect(measurements.count == 2)
        #expect(measurements[0].value == 25.4)
        #expect(measurements[1].value == 12.7)
    }
    
    @Test("Extract measurements for concept")
    func testExtractMeasurementsForConcept() {
        let document = createTestDocument()
        let extractor = MeasurementExtractor()
        
        let lengthConcept = CodedConcept(codeValue: "LENGTH", codingSchemeDesignator: "TEST", codeMeaning: "Length")
        let measurements = extractor.extractMeasurements(forConcept: lengthConcept, from: document)
        
        #expect(measurements.count == 1)
        #expect(measurements[0].value == 25.4)
    }
    
    @Test("Extract measurements for concept string")
    func testExtractMeasurementsForConceptString() {
        let document = createTestDocument()
        let extractor = MeasurementExtractor()
        
        let measurements = extractor.extractMeasurements(forConceptString: "Width", from: document)
        
        #expect(measurements.count == 1)
        #expect(measurements[0].value == 12.7)
    }
    
    @Test("Extract measurement groups")
    func testExtractMeasurementGroups() {
        let document = createTestDocument()
        let extractor = MeasurementExtractor()
        
        let groups = extractor.extractMeasurementGroups(from: document)
        
        #expect(groups.count == 1)
        #expect(groups[0].measurements.count == 2)
        #expect(groups[0].conceptName?.codeMeaning == "Measurements")
    }
    
    @Test("Extract spatial coordinates")
    func testExtractSpatialCoordinates() {
        let document = createTestDocument()
        let extractor = MeasurementExtractor()
        
        let coords = extractor.extractSpatialCoordinates(from: document)
        
        #expect(coords.count == 1)
        #expect(coords[0].graphicType == .polygon)
        #expect(coords[0].pointCount == 4)
    }
    
    @Test("Extract ROIs")
    func testExtractROIs() {
        let document = createTestDocument()
        let extractor = MeasurementExtractor()
        
        let rois = extractor.extractROIs(from: document)
        
        #expect(!rois.isEmpty)
    }
    
    @Test("Compute statistics")
    func testComputeStatistics() {
        let extractor = MeasurementExtractor()
        
        let measurements = [
            Measurement(value: 10.0),
            Measurement(value: 20.0),
            Measurement(value: 30.0),
            Measurement(value: 40.0),
            Measurement(value: 50.0)
        ]
        
        let stats = extractor.computeStatistics(measurements)
        
        #expect(stats != nil)
        #expect(stats!.count == 5)
        #expect(stats!.mean == 30.0)
        #expect(stats!.min == 10.0)
        #expect(stats!.max == 50.0)
        #expect(stats!.sum == 150.0)
        #expect(stats!.range == 40.0)
        
        // Standard deviation for [10, 20, 30, 40, 50] is sqrt(200) ≈ 14.14
        #expect(abs(stats!.standardDeviation - 14.142) < 0.01)
    }
    
    @Test("Compute statistics empty returns nil")
    func testComputeStatisticsEmpty() {
        let extractor = MeasurementExtractor()
        
        let stats = extractor.computeStatistics([])
        
        #expect(stats == nil)
    }
    
    @Test("Group measurements by location")
    func testGroupByLocation() {
        let extractor = MeasurementExtractor()
        
        let concept1 = CodedConcept(codeValue: "A", codingSchemeDesignator: "TEST", codeMeaning: "Measurement A")
        let concept2 = CodedConcept(codeValue: "B", codingSchemeDesignator: "TEST", codeMeaning: "Measurement B")
        
        let measurements = [
            Measurement(conceptName: concept1, value: 10.0),
            Measurement(conceptName: concept2, value: 20.0),
            Measurement(conceptName: concept1, value: 30.0)
        ]
        
        let grouped = extractor.groupByLocation(measurements)
        
        #expect(grouped.count == 2)
        #expect(grouped[concept1]?.count == 2)
        #expect(grouped[concept2]?.count == 1)
    }
}

// MARK: - MeasurementStatistics Tests

@Suite("MeasurementStatistics Tests")
struct MeasurementStatisticsTests {
    
    @Test("Statistics range calculation")
    func testStatisticsRange() {
        let stats = MeasurementStatistics(
            count: 5,
            mean: 30.0,
            min: 10.0,
            max: 50.0,
            standardDeviation: 14.14,
            sum: 150.0
        )
        
        #expect(stats.range == 40.0)
    }
}
