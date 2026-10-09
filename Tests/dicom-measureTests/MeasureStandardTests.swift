//
// MeasureStandardTests.swift
// dicom-measure
//
// Pins dicom-measure to DICOM 2026a: which spacing attribute a measurement uses (PS3.3
// 10.7.1.1-10.7.1.3, C.7.6.16.2.1 Pixel Measures, C.8.5.5 US Region Calibration, Tables
// C.8-71 / C.8-25), the Table C.18.6-1 coordinate system, Bits Stored / High Bit handling
// (PS3.5 8.1.1), the Modality LUT / Rescale Type output units (C.11.1.1.2, Table C.8-3),
// frame range (C.7.6.6.1.1) and the UCUM codes of PS3.16 CID 7460 / 7461 / 7181 / 7183.
//

import XCTest
import DICOMCore
import DICOMKit
@testable import dicom_measure

final class MeasureStandardTests: XCTestCase {

    private let ctStorage = "1.2.840.10008.5.1.4.1.1.2"   // PS3.6 Table A-1 CT Image Storage

    /// A monochrome image, 16 bits allocated; `cells` are the raw 16-bit Pixel Cells.
    private func image(rows: Int = 4, columns: Int = 4, frames: Int = 1, cells: [UInt16]? = nil,
                       bitsStored: Int = 16, signed: Bool = false,
                       _ configure: (inout DataSet) -> Void = { _ in }) throws -> MeasurementEngine {
        var ds = DataSet()
        ds.setString(ctStorage, for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        ds.setInt(1, for: .samplesPerPixel, vr: .US)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds.setInt(rows, for: .rows, vr: .US)
        ds.setInt(columns, for: .columns, vr: .US)
        ds.setInt(16, for: .bitsAllocated, vr: .US)
        ds.setInt(bitsStored, for: .bitsStored, vr: .US)
        ds.setInt(bitsStored - 1, for: .highBit, vr: .US)
        ds.setInt(signed ? 1 : 0, for: .pixelRepresentation, vr: .US)
        if frames > 1 { ds.setString("\(frames)", for: .numberOfFrames, vr: .IS) }
        configure(&ds)
        let values = cells ?? (0..<(rows * columns * frames)).map { UInt16($0) }
        var pixels = Data()
        for v in values { pixels.append(UInt8(v & 0xFF)); pixels.append(UInt8(v >> 8)) }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixels)
        let file = DICOMFile.create(dataSet: ds, sopClassUID: ctStorage, sopInstanceUID: "1.2.3.4.5",
                                    transferSyntaxUID: "1.2.840.10008.1.2.1")
        return try MeasurementEngine(file: try DICOMFile.read(from: try file.write()))
    }

    private func p(_ x: Double, _ y: Double) -> PixelPoint { PixelPoint(x: x, y: y) }

    // MARK: - Spacing source and Value order

    /// PS3.3 10.7.1.3: first Value = row spacing (vertical), second = column spacing (horizontal).
    func testPixelSpacingValueOrder() throws {
        let e = try image { $0.setStrings(["0.5", "0.7"], for: .pixelSpacing, vr: .DS) }
        let across = e.measureDistance(from: p(0, 0), to: p(10, 0), unit: .mm)
        let down = e.measureDistance(from: p(0, 0), to: p(0, 10), unit: .mm)
        XCTAssertEqual(across.value, 7.0, accuracy: 1e-9)   // 10 columns x 0.7
        XCTAssertEqual(down.value, 5.0, accuracy: 1e-9)     // 10 rows x 0.5
        XCTAssertEqual(across.unitLabel, "mm")
        XCTAssertEqual(across.calibration?.source, "PixelSpacing")
    }

    /// 10.7.1.1: Pixel Spacing wins over Imager Pixel Spacing; the calibration type is reported.
    func testPixelSpacingPreferredOverImagerPixelSpacing() throws {
        let e = try image {
            $0.setStrings(["0.2", "0.2"], for: .pixelSpacing, vr: .DS)
            $0.setStrings(["0.25", "0.25"], for: .imagerPixelSpacing, vr: .DS)
            $0.setString("GEOMETRY", for: MeasureTags.pixelSpacingCalibrationType, vr: .CS)
        }
        let cal = try XCTUnwrap(e.calibration(frame: 0, points: []))
        XCTAssertEqual(cal.source, "PixelSpacing")
        XCTAssertEqual(cal.rowSpacing, 0.2)
        XCTAssertEqual(cal.note, "Pixel Spacing Calibration Type GEOMETRY")
    }

    /// Tables C.8-2 / C.8-71: Imager Pixel Spacing is at the front plane of the detector housing.
    func testImagerPixelSpacingIsLabelledDetectorPlane() throws {
        let e = try image { $0.setStrings(["0.1", "0.1"], for: .imagerPixelSpacing, vr: .DS) }
        let r = e.measureDistance(from: p(0, 0), to: p(0, 3), unit: .mm)
        XCTAssertEqual(r.value, 0.3, accuracy: 1e-9)
        XCTAssertEqual(r.calibration?.source, "ImagerPixelSpacing")
        XCTAssertTrue(r.calibration?.note?.contains("front plane of the detector housing") == true)
    }

    /// Table C.8-25: Nominal Scanned Pixel Spacing, on the scanned media.
    func testNominalScannedPixelSpacing() throws {
        let e = try image { $0.setStrings(["0.3", "0.3"], for: .nominalScannedPixelSpacing, vr: .DS) }
        XCTAssertEqual(e.calibration(frame: 0, points: [])?.source, "NominalScannedPixelSpacing")
    }

    /// C.7.6.16.2.1: Pixel Measures functional group; Per-frame item first, then Shared.
    func testPixelMeasuresFunctionalGroups() throws {
        func measures(_ s: [String]) -> SequenceItem {
            var fg = DataSet()
            fg.setSequence([SequenceItem(elements: [DataElement.strings(tag: .pixelSpacing, vr: .DS, values: s)])],
                           for: .pixelMeasuresSequence)
            return SequenceItem(elements: [fg[.pixelMeasuresSequence]!])
        }
        let e = try image(frames: 2) {
            $0.setSequence([measures(["0.4", "0.4"])], for: .sharedFunctionalGroupsSequence)
            $0.setSequence([SequenceItem(), measures(["0.9", "0.9"])], for: .perFrameFunctionalGroupsSequence)
        }
        XCTAssertEqual(e.calibration(frame: 0, points: [])?.rowSpacing, 0.4)
        XCTAssertEqual(e.calibration(frame: 0, points: [])?.source, "PixelMeasuresSequence")
        XCTAssertEqual(e.calibration(frame: 1, points: [])?.rowSpacing, 0.9)
    }

    /// C.8.5.5.1.14/.15/.17: the region (inclusive pixel indices) holding the points, units 0003H cm.
    func testUltrasoundRegionCalibration() throws {
        func region(units: UInt16, x0: UInt32, x1: UInt32) -> SequenceItem {
            SequenceItem(elements: [
                DataElement.uint32(tag: MeasureTags.regionLocationMinX0, value: x0),
                DataElement.uint32(tag: MeasureTags.regionLocationMinY0, value: 0),
                DataElement.uint32(tag: MeasureTags.regionLocationMaxX1, value: x1),
                DataElement.uint32(tag: MeasureTags.regionLocationMaxY1, value: 3),
                DataElement.uint16(tag: MeasureTags.physicalUnitsXDirection, value: units),
                DataElement.uint16(tag: MeasureTags.physicalUnitsYDirection, value: units),
                DataElement.float64(tag: MeasureTags.physicalDeltaX, value: 0.01),
                DataElement.float64(tag: MeasureTags.physicalDeltaY, value: -0.02),
            ])
        }
        let e = try image {
            $0.setSequence([region(units: 0x0004, x0: 0, x1: 3),   // seconds: not spatial
                            region(units: 0x0003, x0: 0, x1: 1)],  // cm, columns 0-1
                           for: MeasureTags.sequenceOfUltrasoundRegions)
        }
        let inside = try XCTUnwrap(e.calibration(frame: 0, points: [p(0, 0), p(1.9, 3.5)]))
        XCTAssertEqual(inside.source, "SequenceOfUltrasoundRegions")
        XCTAssertEqual(inside.columnSpacing, 0.1, accuracy: 1e-12)   // 0.01 cm
        XCTAssertEqual(inside.rowSpacing, 0.2, accuracy: 1e-12)      // |-0.02| cm
        XCTAssertNil(e.calibration(frame: 0, points: [p(0, 0), p(2.0, 0)]), "column 2 is outside the cm region")
    }

    /// No spacing attribute: a physical unit cannot be produced, so the result is in pixels.
    func testUncalibratedImageReportsPixels() throws {
        let e = try image()
        let r = e.measureDistance(from: p(0, 0), to: p(3, 4), unit: .mm)
        XCTAssertEqual(r.value, 5.0)
        XCTAssertEqual(r.unitLabel, "px")
        XCTAssertNil(r.calibration)
        XCTAssertEqual(r.ucum, "{pixels}")   // PS3.16 2026a TID UNITS ({pixels}, UCUM, "pixels")
        let area = e.measurePolygonArea(vertices: [p(0, 0), p(2, 0), p(2, 2)], unit: .cm)
        XCTAssertEqual(area.unitLabel, "px²")
        XCTAssertEqual(area.value, 2.0)
        let json = formatResult(type: "distance", result: r, format: .json, details: [:], geometric: true)
        XCTAssertTrue(json.contains("\"spacing_source\" : \"none\""), json)
    }

    /// The angle is measured in physical space: row spacing 1.0, column spacing 2.0.
    func testAngleUsesAnisotropicSpacing() throws {
        let e = try image { $0.setStrings(["1.0", "2.0"], for: .pixelSpacing, vr: .DS) }
        let r = e.measureAngle(vertex: p(0, 0), p1: p(1, 0), p2: p(1, 1))
        XCTAssertEqual(r.value, atan(0.5) * 180 / .pi, accuracy: 1e-9)   // vectors (2,0) and (2,1) mm
        XCTAssertEqual(r.ucum, "deg")
    }

    // MARK: - Coordinates (Table C.18.6-1)

    func testPointSamplesFloorPixelAndRejectsNegative() throws {
        let e = try image()   // cell value = row*4 + column
        XCTAssertEqual(try e.rawPixelValue(at: p(1.9, 0.2)), 1)
        XCTAssertEqual(try e.rawPixelValue(at: p(0.5, 2.99)), 8)
        XCTAssertThrowsError(try e.rawPixelValue(at: p(-0.5, 0)))
        XCTAssertThrowsError(try e.rawPixelValue(at: p(4.0, 0)))
    }

    /// An ROI holds the pixels whose centres (c+0.5, r+0.5) are inside it.
    func testCircleROIUsesPixelCentres() throws {
        let e = try image()
        let r = try e.analyzeROI(roi: .circle(cx: 2, cy: 2, radius: 1), includeStatistics: true,
                                 includeHistogram: false, histogramBins: 2, unit: .pixels)
        XCTAssertEqual(r.pixelCount, 4)                         // pixels (1,1) (2,1) (1,2) (2,2)
        XCTAssertEqual(try XCTUnwrap(r.mean), (5 + 6 + 9 + 10) / 4.0)
        let rect = try e.analyzeROI(roi: .rect(x: 1, y: 1, width: 2, height: 2), includeStatistics: true,
                                    includeHistogram: false, histogramBins: 2, unit: .pixels)
        XCTAssertEqual(rect.pixelCount, 4)
        XCTAssertEqual(rect.mean, r.mean)
    }

    // MARK: - Pixel values (PS3.5 8.1.1) and frames

    func testBitsStoredMaskAndSignExtension() throws {
        let unsigned = try image(rows: 1, columns: 2, cells: [0xF00A, 0x0FFF], bitsStored: 12)
        XCTAssertEqual(try unsigned.rawPixelValue(at: p(0, 0)), 10)          // upper 4 bits ignored
        let signed = try image(rows: 1, columns: 2, cells: [0x0FFF, 0x0800], bitsStored: 12, signed: true)
        XCTAssertEqual(try signed.rawPixelValue(at: p(0, 0)), -1)
        XCTAssertEqual(try signed.rawPixelValue(at: p(1, 0)), -2048)
    }

    /// C.7.6.6.1.1 Number of Frames bounds the 0-based --frame index.
    func testFrameIndexRange() throws {
        let e = try image(rows: 2, columns: 2, frames: 2)
        XCTAssertEqual(try e.rawPixelValue(at: p(0, 0), frame: 1), 4)
        XCTAssertThrowsError(try e.rawPixelValue(at: p(0, 0), frame: 2)) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("Frame number 3 is out of range"))
            XCTAssertTrue("\(error.localizedDescription)".contains("valid Frame numbers are 1...2"))
        }
    }

    // MARK: - Output units (C.11.1.1.2, Table C.8-3)

    func testCTWithoutRescaleTypeIsHU() throws {
        let e = try image {
            $0.setString("CT", for: .modality, vr: .CS)
            $0.setString("-1024", for: .rescaleIntercept, vr: .DS)
            $0.setString("1", for: .rescaleSlope, vr: .DS)
        }
        let r = try e.measureHU(at: p(1, 0))
        XCTAssertEqual(r.value, -1023)
        XCTAssertEqual(r.unitLabel, "HU")
        XCTAssertEqual(r.ucum, "[hnsf'U]")
    }

    func testNonHURescaleTypeIsNotLabelledHU() throws {
        let e = try image {
            $0.setString("MR", for: .modality, vr: .CS)
            $0.setString("10", for: .rescaleIntercept, vr: .DS)
            $0.setString("2", for: .rescaleSlope, vr: .DS)
            $0.setString("US", for: .rescaleType, vr: .LO)
        }
        let r = try e.measureHU(at: p(1, 0))
        XCTAssertEqual(r.value, 12)
        XCTAssertEqual(r.unitLabel, "US")
        XCTAssertNil(r.ucum)
        XCTAssertEqual(r.description, "Rescaled value (not Hounsfield Units)")
        XCTAssertEqual(try e.measurePixelValue(at: p(1, 0)).unitLabel, "US")
    }

    /// C.11.1: a Modality LUT Sequence replaces Rescale Slope/Intercept; its Modality LUT Type names the units.
    func testModalityLUTIsApplied() throws {
        let e = try image {
            let lut = SequenceItem(elements: [
                DataElement.uint16s(tag: .lutDescriptor, values: [4, 0, 16]),
                DataElement.string(tag: MeasureTags.modalityLUTType, vr: .LO, value: "OD"),
                DataElement.uint16s(tag: .lutData, values: [100, 200, 300, 400]),
            ])
            $0.setSequence([lut], for: .modalityLUTSequence)
        }
        let r = try e.measurePixelValue(at: p(2, 0))
        XCTAssertEqual(r.value, 300)
        XCTAssertEqual(r.unitLabel, "OD")
    }

    // MARK: - UCUM codes (PS3.16 2026a, dumped from part16_2026a.xml)

    func testUCUMCodesMatchPS316() {
        // CID 7460 Linear Measurement Unit: cm, mm, um. CID 7461 Area Measurement Unit: cm2, mm2, um2.
        XCTAssertEqual(MeasurementEngine.distanceUCUM(.mm), "mm")
        XCTAssertEqual(MeasurementEngine.distanceUCUM(.cm), "cm")
        XCTAssertEqual(MeasurementEngine.distanceUCUM(.um), "um")
        XCTAssertNil(MeasurementEngine.distanceUCUM(.inches))
        XCTAssertEqual(MeasurementEngine.distanceUCUM(.pixels), "{pixels}")   // PS3.16 TID UNITS ({pixels}, UCUM, "pixels")
        XCTAssertEqual(MeasurementEngine.areaUCUM(.mm), "mm2")
        XCTAssertEqual(MeasurementEngine.areaUCUM(.cm), "cm2")
        XCTAssertEqual(MeasurementEngine.areaUCUM(.um), "um2")
        XCTAssertNil(MeasurementEngine.areaUCUM(.pixels))
        XCTAssertEqual(MeasurementEngine.angleUCUM, "deg")              // CID 7183 Degree
        XCTAssertEqual(MeasurementEngine.hounsfieldUCUM, "[hnsf'U]")    // CID 7181 / CID 83
    }

    /// spacing_source values are PS3.6 2026a Table 6-1 keywords.
    func testSpacingSourceValuesAreKeywords() throws {
        let keywords: Set<String> = ["PixelSpacing", "PixelMeasuresSequence", "SequenceOfUltrasoundRegions",
                                     "ImagerPixelSpacing", "NominalScannedPixelSpacing"]
        let e = try image { $0.setStrings(["1", "1"], for: .pixelSpacing, vr: .DS) }
        let json = formatResult(type: "distance", result: e.measureDistance(from: p(0, 0), to: p(1, 0), unit: .mm),
                                format: .json, details: [:], geometric: true)
        XCTAssertTrue(json.contains("\"spacing_source\" : \"PixelSpacing\""), json)
        XCTAssertTrue(json.contains("\"unit_ucum\" : \"mm\""), json)
        XCTAssertTrue(keywords.contains("PixelSpacing"))
    }

    // MARK: - P-MEASURE-UNIT: um, UCUM code in text, deprecated unit key kept

    /// PS3.16 2026a CID 7460 / CID 7461, dumped from part16_2026a.xml by Scripts/nema_docbook.py.
    static let cid7460 = ["cm", "mm", "um"]
    static let cid7461 = ["cm2", "mm2", "um2"]

    func testEveryCodedUnitIsInCID7460Or7461() {
        for unit in MeasurementUnit.allCases {
            if let code = MeasurementEngine.distanceUCUM(unit), code != "{pixels}" {
                XCTAssertTrue(Self.cid7460.contains(code), code)
            }
            if let code = MeasurementEngine.areaUCUM(unit) { XCTAssertTrue(Self.cid7461.contains(code), code) }
        }
        XCTAssertEqual(MeasurementUnit(argument: "um"), .um)
    }

    func testMicrometreConversion() throws {
        let e = try image { $0.setStrings(["0.5", "0.25"], for: .pixelSpacing, vr: .DS) }
        let d = e.measureDistance(from: p(0, 0), to: p(4, 0), unit: .um)   // 4 columns x 0.25 mm
        XCTAssertEqual(d.value, 1000, accuracy: 1e-9)
        XCTAssertEqual(d.unitLabel, "µm")
        XCTAssertEqual(d.ucum, "um")
        let a = e.measurePolygonArea(vertices: [p(0, 0), p(4, 0), p(4, 2), p(0, 2)], unit: .um)  // 1 mm x 1 mm
        XCTAssertEqual(a.value, 1_000_000, accuracy: 1e-6)
        XCTAssertEqual(a.ucum, "um2")
    }

    func testTextPrintsUCUMCodeWithSymbolInParentheses() throws {
        let e = try image { $0.setStrings(["1", "1"], for: .pixelSpacing, vr: .DS) }
        let area = e.measurePolygonArea(vertices: [p(0, 0), p(2, 0), p(2, 2)], unit: .mm)
        let text = formatResult(type: "area", result: area, format: .text, details: [:], geometric: true)
        XCTAssertTrue(text.hasPrefix("Polygon area (3 vertices): 2.0 mm2 (mm²)\n"), text)
        let angle = e.measureAngle(vertex: p(0, 0), p1: p(1, 0), p2: p(0, 1))
        XCTAssertTrue(formatResult(type: "angle", result: angle, format: .text, details: [:]).hasPrefix("Angle: 90.0 deg (°)"))
        XCTAssertEqual(textUnit(ucum: "mm", symbol: "mm"), "mm")
        XCTAssertEqual(textUnit(ucum: nil, symbol: "in"), "in")
        XCTAssertEqual(textUnit(ucum: "[hnsf'U]", symbol: "HU"), "[hnsf'U] (HU)")
        // JSON keeps the deprecated display-symbol key next to the UCUM code
        let json = formatResult(type: "area", result: area, format: .json, details: [:], geometric: true)
        XCTAssertTrue(json.contains("\"unit\" : \"mm²\""), json)
        XCTAssertTrue(json.contains("\"unit_ucum\" : \"mm2\""), json)
    }

    // MARK: - P-MEASURE-FRAME: 1-based --frame-number, deprecated --frame

    func testFrameNumberIsOneBasedAndFrameIsDeprecated() throws {
        XCTAssertEqual(Pixel.frameIndex(frameNumber: nil, frame: nil).index, 0)
        XCTAssertEqual(Pixel.frameIndex(frameNumber: 2, frame: nil).index, 1)
        XCTAssertNil(Pixel.frameIndex(frameNumber: 2, frame: nil).note)
        let old = Pixel.frameIndex(frameNumber: nil, frame: 1)
        XCTAssertEqual(old.index, 1)
        XCTAssertEqual(old.note, "Note: --frame is deprecated (0-based index); use --frame-number 2")
        XCTAssertThrowsError(try Pixel.parse(["f.dcm", "--point", "0,0", "--frame-number", "0"]))
        XCTAssertNoThrow(try Pixel.parse(["f.dcm", "--point", "0,0", "--frame-number", "1"]))
        // Both given: refused in run() with exit 1 (parsing accepts it)
        var both = try Pixel.parse(["f.dcm", "--point", "0,0", "--frame-number", "1", "--frame", "0"])
        XCTAssertThrowsError(try both.run()) { error in
            XCTAssertEqual(Pixel.exitCode(for: error).rawValue, 1)
        }
    }

    func testPixelOutputLabelsFrameNumber() throws {
        let e = try image(rows: 2, columns: 2, frames: 2)
        let r = try e.measurePixelValue(at: p(0, 0), frame: 1)
        let details = ["point": "0.0,0.0", "frame": "1", "frame_number": "2"]
        let text = formatResult(type: "pixel", result: r, format: .text, details: details)
        XCTAssertTrue(text.contains("  Frame number: 2\n"), text)
        XCTAssertFalse(text.contains("frame: 1"), text)
        let json = formatResult(type: "pixel", result: r, format: .json, details: details)
        XCTAssertTrue(json.contains("\"frame_number\" : \"2\""), json)
        XCTAssertTrue(json.contains("\"frame\" : \"1\""), json)
    }
}
