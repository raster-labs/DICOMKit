// NEMA-verified: 2026a, checked 2026-10-01 — spacing sources diffed against PS3.3 2026a 10.7.1.1-10.7.1.3, Table 10-10, Table C.7.6.16-2, Tables C.8-2/C.8-71 (Imager Pixel Spacing), C.8-25 (Nominal Scanned Pixel Spacing), C.8-17 with C.8.5.5.1.14/.15/.17 (13 Physical Units values; cm used); 11 Tag literals match PS3.6 2026a Table 6-1 (name and keyword); output units per C.11.1.1.2 (9 Defined Terms) and Table C.8-3; coordinates per Table C.18.6-1; UCUM codes per PS3.16 2026a CID 7460 (3), CID 7461 (3), CID 7181/83 [hnsf'U], CID 7183 deg
/// Measurement engine for DICOM images
///
/// Provides coordinate transforms, distance, area, angle, ROI statistics,
/// and Hounsfield Unit extraction from DICOM pixel data.
///
/// Coordinates follow PS3.3 Table C.18.6-1 Graphic Data: x is the column, y the row,
/// the top-left corner of the top-left pixel is 0,0 and its bottom-right corner is
/// 1,1, so pixel (column c, row r) covers [c, c+1) x [r, r+1) and its centre is
/// (c+0.5, r+0.5).

import Foundation
import DICOMKit
import DICOMCore
import DICOMDictionary

/// Attributes the engine reads that DICOMCore has no constant for (PS3.6 2026a Table 6-1).
enum MeasureTags {
    static let pixelSpacingCalibrationType = Tag(group: 0x0028, element: 0x0A02)  // Pixel Spacing Calibration Type
    static let sequenceOfUltrasoundRegions = Tag(group: 0x0018, element: 0x6011)  // Sequence of Ultrasound Regions
    static let regionLocationMinX0 = Tag(group: 0x0018, element: 0x6018)          // Region Location Min X0
    static let regionLocationMinY0 = Tag(group: 0x0018, element: 0x601A)          // Region Location Min Y0
    static let regionLocationMaxX1 = Tag(group: 0x0018, element: 0x601C)          // Region Location Max X1
    static let regionLocationMaxY1 = Tag(group: 0x0018, element: 0x601E)          // Region Location Max Y1
    static let physicalUnitsXDirection = Tag(group: 0x0018, element: 0x6024)      // Physical Units X Direction
    static let physicalUnitsYDirection = Tag(group: 0x0018, element: 0x6026)      // Physical Units Y Direction
    static let physicalDeltaX = Tag(group: 0x0018, element: 0x602C)               // Physical Delta X
    static let physicalDeltaY = Tag(group: 0x0018, element: 0x602E)               // Physical Delta Y
    static let modalityLUTType = Tag(group: 0x0028, element: 0x3004)              // Modality LUT Type
}

/// Physical pixel spacing used for a measurement, and the attribute it came from
struct SpacingCalibration: Sendable, Equatable {
    /// Row spacing in mm (first Value, PS3.3 10.7.1.3: vertical spacing)
    let rowSpacing: Double
    /// Column spacing in mm (second Value, PS3.3 10.7.1.3: horizontal spacing)
    let columnSpacing: Double
    /// PS3.6 keyword of the attribute the spacing came from
    let source: String
    /// What plane the spacing applies to, when it is not the patient
    let note: String?
}

/// Output units of the Modality LUT / rescale (PS3.3 C.11.1.1.2)
struct OutputUnits: Sendable, Equatable {
    /// Rescale Type (0028,1054) or Modality LUT Type (0028,3004) value
    let type: String
    /// Where it came from
    let source: String
    var isHounsfield: Bool { type == "HU" }
}

/// Core measurement engine that reads pixel data and calibration from DICOM files
struct MeasurementEngine {
    let dicomFile: DICOMFile
    let dataSet: DataSet
    let rows: Int
    let columns: Int
    let numberOfFrames: Int
    let pixelData: PixelData?
    let verbose: Bool

    init(options: CommonOptions) throws {
        guard FileManager.default.fileExists(atPath: options.filePath) else {
            throw MeasureError.fileNotFound(options.filePath)
        }
        let fileData = try Data(contentsOf: URL(fileURLWithPath: options.filePath))
        try self.init(file: try DICOMFile.read(from: fileData, force: options.force), verbose: options.verbose)
    }

    init(file: DICOMFile, verbose: Bool = false) throws {
        self.dicomFile = file
        self.dataSet = file.dataSet
        self.verbose = verbose

        guard let r = dataSet.uint16(for: .rows), let c = dataSet.uint16(for: .columns) else {
            throw MeasureError.missingImageDimensions
        }
        self.rows = Int(r)
        self.columns = Int(c)
        self.numberOfFrames = max(1, dataSet.numberOfFrames ?? 1)
        // Native or decompressed pixel data; the descriptor carries Bits Stored, High Bit
        // and Pixel Representation (PS3.5 8.1.1).
        self.pixelData = file.pixelData()

        if verbose {
            let spacing = calibration(frame: 0, points: [])
            Self.warn("Image: \(columns)x\(rows), \(numberOfFrames) frame(s); spacing: "
                + (spacing.map { "\($0.rowSpacing)\\\($0.columnSpacing) mm from \($0.source)" } ?? "none"))
            if let d = pixelData?.descriptor {
                Self.warn("Bits: \(d.bitsAllocated) allocated, \(d.bitsStored) stored, high bit \(d.highBit), signed: \(d.isSigned)")
            }
            Self.warn("Rescale: slope=\(dataSet.rescaleSlope(frameIndex: 0)), intercept=\(dataSet.rescaleIntercept(frameIndex: 0))")
        }
    }

    static func warn(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    // MARK: - Calibration

    /// Two positive DS values (PS3.3 10.7.1.3: "shall have positive non-zero Values")
    private static func spacingPair(_ values: [DICOMDecimalString]?) -> (Double, Double)? {
        guard let v = values, v.count >= 2, v[0].value > 0, v[1].value > 0 else { return nil }
        return (v[0].value, v[1].value)
    }

    /// Pixel Measures Sequence (0028,9110) item for a frame: Per-frame first, then Shared
    /// (PS3.3 C.7.6.16; a macro is in exactly one of the two sequences).
    private func pixelMeasuresItem(frame: Int) -> SequenceItem? {
        if let perFrame = dataSet.sequence(for: .perFrameFunctionalGroupsSequence),
           perFrame.indices.contains(frame),
           let item = perFrame[frame][.pixelMeasuresSequence]?.sequenceItems?.first {
            return item
        }
        if let shared = dataSet.sequence(for: .sharedFunctionalGroupsSequence)?.first,
           let item = shared[.pixelMeasuresSequence]?.sequenceItems?.first {
            return item
        }
        return nil
    }

    /// The Ultrasound Region whose Region Location (inclusive pixel indices, PS3.3
    /// C.8.5.5.1.14) holds every point and whose Physical Units X and Y Direction are
    /// both 0003H cm (C.8.5.5.1.15); Physical Delta X/Y are cm per pixel (C.8.5.5.1.17).
    private func ultrasoundCalibration(points: [PixelPoint]) -> SpacingCalibration? {
        guard let regions = dataSet.sequence(for: MeasureTags.sequenceOfUltrasoundRegions) else { return nil }
        let cm: UInt16 = 0x0003
        for region in regions {
            guard region[MeasureTags.physicalUnitsXDirection]?.uint16Values?.first == cm,
                  region[MeasureTags.physicalUnitsYDirection]?.uint16Values?.first == cm,
                  let dx = region[MeasureTags.physicalDeltaX]?.float64Values?.first,
                  let dy = region[MeasureTags.physicalDeltaY]?.float64Values?.first,
                  dx != 0, dy != 0 else { continue }
            if let x0 = region[MeasureTags.regionLocationMinX0]?.uint32Values?.first,
               let y0 = region[MeasureTags.regionLocationMinY0]?.uint32Values?.first,
               let x1 = region[MeasureTags.regionLocationMaxX1]?.uint32Values?.first,
               let y1 = region[MeasureTags.regionLocationMaxY1]?.uint32Values?.first {
                let inside = points.allSatisfy { p in
                    let c = floor(p.x), r = floor(p.y)
                    return c >= Double(x0) && c <= Double(x1) && r >= Double(y0) && r <= Double(y1)
                }
                guard inside else { continue }
            }
            return SpacingCalibration(rowSpacing: abs(dy) * 10, columnSpacing: abs(dx) * 10,
                                      source: "SequenceOfUltrasoundRegions",
                                      note: "Physical Delta Y\\X of the region holding the points, cm converted to mm")
        }
        return nil
    }

    /// Physical spacing for a measurement on `frame` through `points`, or nil when the
    /// object carries none. Order: Pixel Spacing (0028,0030) — calibrated or equal to the
    /// detector value (PS3.3 10.7.1.1); Pixel Measures functional group (C.7.6.16.2.1);
    /// Ultrasound Region calibration (C.8.5.5); Imager Pixel Spacing (0018,1164), measured
    /// at the front plane of the detector housing (Tables C.8-2, C.8-71); Nominal Scanned
    /// Pixel Spacing (0018,2010), on the scanned media (Table C.8-25).
    func calibration(frame: Int, points: [PixelPoint]) -> SpacingCalibration? {
        if let (r, c) = Self.spacingPair(dataSet.decimalStrings(for: .pixelSpacing)) {
            let type = dataSet.string(for: MeasureTags.pixelSpacingCalibrationType)?
                .trimmingCharacters(in: .whitespaces)
            return SpacingCalibration(rowSpacing: r, columnSpacing: c, source: "PixelSpacing",
                                      note: (type?.isEmpty == false) ? "Pixel Spacing Calibration Type \(type!)" : nil)
        }
        if let item = pixelMeasuresItem(frame: frame),
           let (r, c) = Self.spacingPair(item[.pixelSpacing]?.decimalStringValues) {
            return SpacingCalibration(rowSpacing: r, columnSpacing: c, source: "PixelMeasuresSequence", note: nil)
        }
        if let us = ultrasoundCalibration(points: points) {
            return us
        }
        if let (r, c) = Self.spacingPair(dataSet.decimalStrings(for: .imagerPixelSpacing)) {
            return SpacingCalibration(rowSpacing: r, columnSpacing: c, source: "ImagerPixelSpacing",
                                      note: "at the front plane of the detector housing, not corrected for geometric magnification")
        }
        if let (r, c) = Self.spacingPair(dataSet.decimalStrings(for: .nominalScannedPixelSpacing)) {
            return SpacingCalibration(rowSpacing: r, columnSpacing: c, source: "NominalScannedPixelSpacing",
                                      note: "on the scanned media")
        }
        return nil
    }

    /// The unit actually used: a physical unit needs a calibration, else pixels.
    func effectiveUnit(_ requested: MeasurementUnit, calibration: SpacingCalibration?) -> MeasurementUnit {
        if requested != .pixels && calibration == nil {
            Self.warn("Warning: no Pixel Spacing (0028,0030), Pixel Measures Sequence (0028,9110), "
                + "Sequence of Ultrasound Regions (0018,6011), Imager Pixel Spacing (0018,1164) or "
                + "Nominal Scanned Pixel Spacing (0018,2010); result is in pixels")
            return .pixels
        }
        return requested
    }

    // MARK: - Coordinate Conversion

    /// Convert pixel offsets (dx along columns, dy along rows) to a distance
    func pixelToPhysical(dx: Double, dy: Double, unit: MeasurementUnit, calibration: SpacingCalibration?) -> Double {
        guard unit != .pixels, let cal = calibration else { return sqrt(dx * dx + dy * dy) }
        let physicalDx = dx * cal.columnSpacing
        let physicalDy = dy * cal.rowSpacing
        let distanceMM = sqrt(physicalDx * physicalDx + physicalDy * physicalDy)
        switch unit {
        case .mm: return distanceMM
        case .cm: return distanceMM / 10.0
        case .um: return distanceMM * 1000.0
        case .inches: return distanceMM / 25.4
        case .pixels: return sqrt(dx * dx + dy * dy)
        }
    }

    /// Convert pixel area to physical area
    func pixelAreaToPhysical(pixelArea: Double, unit: MeasurementUnit, calibration: SpacingCalibration?) -> Double {
        guard unit != .pixels, let cal = calibration else { return pixelArea }
        let physicalArea = pixelArea * cal.columnSpacing * cal.rowSpacing
        switch unit {
        case .mm: return physicalArea
        case .cm: return physicalArea / 100.0
        case .um: return physicalArea * 1_000_000.0
        case .inches: return physicalArea / (25.4 * 25.4)
        case .pixels: return pixelArea
        }
    }

    /// Display label of an area unit
    static func areaUnitLabel(_ unit: MeasurementUnit) -> String {
        switch unit {
        case .mm: return "mm²"
        case .cm: return "cm²"
        case .um: return "µm²"
        case .inches: return "in²"
        case .pixels: return "px²"
        }
    }

    /// Display label of a distance unit
    static func distanceUnitLabel(_ unit: MeasurementUnit) -> String {
        switch unit {
        case .mm: return "mm"
        case .cm: return "cm"
        case .um: return "µm"
        case .inches: return "in"
        case .pixels: return "px"
        }
    }

    /// UCUM code of a distance unit, from PS3.16 2026a CID 7460 Linear Measurement Unit
    /// (cm, mm, um); pixels as PS3.16 2026a writes them in TID UNITS constraints
    /// ({pixels}, UCUM, "pixels"). Inches have no code in PS3.16.
    static func distanceUCUM(_ unit: MeasurementUnit) -> String? {
        switch unit {
        case .mm: return "mm"
        case .cm: return "cm"
        case .um: return "um"
        case .pixels: return "{pixels}"
        case .inches: return nil
        }
    }

    /// UCUM code of an area unit, from PS3.16 2026a CID 7461 Area Measurement Unit
    /// (cm2, mm2, um2).
    static func areaUCUM(_ unit: MeasurementUnit) -> String? {
        switch unit {
        case .mm: return "mm2"
        case .cm: return "cm2"
        case .um: return "um2"
        case .inches, .pixels: return nil
        }
    }

    /// UCUM code for degrees (PS3.16 2026a CID 7183: UCUM deg "Degree")
    static let angleUCUM = "deg"
    /// UCUM code for Hounsfield units (PS3.16 2026a CID 7181 / CID 83: UCUM [hnsf'U])
    static let hounsfieldUCUM = "[hnsf'U]"

    // MARK: - Distance Measurement

    /// Measure distance between two points
    func measureDistance(from p1: PixelPoint, to p2: PixelPoint, unit requested: MeasurementUnit) -> MeasurementResult {
        let cal = calibration(frame: 0, points: [p1, p2])
        let unit = effectiveUnit(requested, calibration: cal)
        let distance = pixelToPhysical(dx: p2.x - p1.x, dy: p2.y - p1.y, unit: unit, calibration: cal)
        return MeasurementResult(value: distance, unitLabel: Self.distanceUnitLabel(unit),
                                 description: "Distance", ucum: Self.distanceUCUM(unit), calibration: cal)
    }

    // MARK: - Area Measurement

    /// Measure polygon area using the Shoelace formula
    func measurePolygonArea(vertices: [PixelPoint], unit requested: MeasurementUnit) -> MeasurementResult {
        let cal = calibration(frame: 0, points: vertices)
        let unit = effectiveUnit(requested, calibration: cal)
        let area = pixelAreaToPhysical(pixelArea: Self.shoelaceArea(vertices: vertices), unit: unit, calibration: cal)
        return MeasurementResult(value: area, unitLabel: Self.areaUnitLabel(unit),
                                 description: "Polygon area (\(vertices.count) vertices)",
                                 ucum: Self.areaUCUM(unit), calibration: cal)
    }

    /// Measure ellipse area (radii along the column and row directions, in pixels)
    func measureEllipseArea(center: PixelPoint, radiusX: Double, radiusY: Double, unit requested: MeasurementUnit) -> MeasurementResult {
        let extent = [PixelPoint(x: center.x - radiusX, y: center.y - radiusY),
                      PixelPoint(x: center.x + radiusX, y: center.y + radiusY)]
        let cal = calibration(frame: 0, points: extent)
        let unit = effectiveUnit(requested, calibration: cal)
        let area = pixelAreaToPhysical(pixelArea: Double.pi * radiusX * radiusY, unit: unit, calibration: cal)
        return MeasurementResult(value: area, unitLabel: Self.areaUnitLabel(unit), description: "Ellipse area",
                                 ucum: Self.areaUCUM(unit), calibration: cal)
    }

    /// Shoelace formula for polygon area
    static func shoelaceArea(vertices: [PixelPoint]) -> Double {
        guard vertices.count >= 3 else { return 0.0 }
        var area = 0.0
        let n = vertices.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += vertices[i].x * vertices[j].y
            area -= vertices[j].x * vertices[i].y
        }
        return abs(area) / 2.0
    }

    // MARK: - Angle Measurement

    /// Measure the angle at `vertex`. With a calibration the vectors are scaled by the
    /// column and row spacing first, so the angle is the one in the patient (or detector)
    /// plane, not in the pixel grid (they differ when row spacing != column spacing).
    func measureAngle(vertex: PixelPoint, p1: PixelPoint, p2: PixelPoint) -> MeasurementResult {
        let cal = calibration(frame: 0, points: [vertex, p1, p2])
        let sx = cal?.columnSpacing ?? 1.0
        let sy = cal?.rowSpacing ?? 1.0
        let v1x = (p1.x - vertex.x) * sx, v1y = (p1.y - vertex.y) * sy
        let v2x = (p2.x - vertex.x) * sx, v2y = (p2.y - vertex.y) * sy
        let mag1 = sqrt(v1x * v1x + v1y * v1y)
        let mag2 = sqrt(v2x * v2x + v2y * v2y)
        guard mag1 > 0 && mag2 > 0 else {
            return MeasurementResult(value: 0.0, unitLabel: "°", description: "Angle", ucum: Self.angleUCUM, calibration: cal)
        }
        let cosAngle = max(-1.0, min(1.0, (v1x * v2x + v1y * v2y) / (mag1 * mag2)))
        return MeasurementResult(value: acos(cosAngle) * 180.0 / Double.pi, unitLabel: "°", description: "Angle",
                                 ucum: Self.angleUCUM, calibration: cal)
    }

    // MARK: - Pixel Value Access

    /// Pixel index (column, row) holding a C.18.6-1 coordinate
    static func pixelIndex(_ point: PixelPoint) -> (column: Int, row: Int) {
        (Int(floor(point.x)), Int(floor(point.y)))
    }

    private func checkFrame(_ frame: Int) throws {
        guard frame >= 0, frame < numberOfFrames else {
            throw MeasureError.frameOutOfRange(frame: frame, numberOfFrames: numberOfFrames)
        }
    }

    /// The stored Pixel Sample Value at a pixel index (masked to Bits Stored and
    /// sign-extended per PS3.5 8.1.1 by `PixelData.pixelValue`)
    func storedValue(column: Int, row: Int, frame: Int = 0) throws -> Double {
        guard let pd = pixelData else { throw MeasureError.noPixelData }
        guard pd.descriptor.samplesPerPixel == 1 else {
            throw MeasureError.notMonochrome(pd.descriptor.samplesPerPixel)
        }
        try checkFrame(frame)
        guard column >= 0, column < columns, row >= 0, row < rows else {
            throw MeasureError.pointOutOfBounds(x: column, y: row, columns: columns, rows: rows)
        }
        guard let v = pd.pixelValue(row: row, column: column, frame: frame) else {
            throw MeasureError.pixelDataTooShort
        }
        return Double(v)
    }

    /// Get the stored pixel value at a coordinate
    func rawPixelValue(at point: PixelPoint, frame: Int = 0) throws -> Double {
        let (c, r) = Self.pixelIndex(point)
        return try storedValue(column: c, row: r, frame: frame)
    }

    /// Modality LUT / rescale (PS3.3 C.11.1): the LUT when a Modality LUT Sequence is
    /// present, else Rescale Slope/Intercept of the frame (top level or Pixel Value
    /// Transformation functional group).
    func modalityValue(_ stored: Double, frame: Int = 0) -> Double {
        dataSet.rescale(stored, frameIndex: frame)
    }

    /// Whether a modality transform other than identity is present
    func hasModalityTransform(frame: Int = 0) -> Bool {
        dataSet.modalityLUTData() != nil
            || dataSet.rescaleSlope(frameIndex: frame) != 1.0
            || dataSet.rescaleIntercept(frameIndex: frame) != 0.0
    }

    /// Get rescaled pixel value
    func rescaledPixelValue(at point: PixelPoint, frame: Int = 0) throws -> Double {
        modalityValue(try rawPixelValue(at: point, frame: frame), frame: frame)
    }

    /// Output units of the modality transform (PS3.3 C.11.1.1.2): Modality LUT Type
    /// (0028,3004), else Rescale Type (0028,1054) at the top level or in the Pixel Value
    /// Transformation functional group, else HU for CT (Table C.8-3: Rescale Type is
    /// "Required if the Rescale Type is not HU"), else unknown.
    func outputUnits(frame: Int = 0) -> OutputUnits? {
        func clean(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
            return t
        }
        if let item = dataSet.sequence(for: .modalityLUTSequence)?.first {
            return clean(item.string(for: MeasureTags.modalityLUTType)).map { OutputUnits(type: $0, source: "ModalityLUTType") }
        }
        if let t = clean(dataSet.string(for: .rescaleType)) {
            return OutputUnits(type: t, source: "RescaleType")
        }
        let perFrame = dataSet.sequence(for: .perFrameFunctionalGroupsSequence)
        let fgItem = (perFrame?.indices.contains(frame) == true
                        ? perFrame?[frame][.pixelValueTransformationSequence]?.sequenceItems?.first : nil)
            ?? dataSet.sequence(for: .sharedFunctionalGroupsSequence)?.first?[.pixelValueTransformationSequence]?.sequenceItems?.first
        if let t = clean(fgItem?.string(for: .rescaleType)) {
            return OutputUnits(type: t, source: "PixelValueTransformationSequence")
        }
        if clean(dataSet.string(for: .modality)) == "CT", dataSet[.rescaleIntercept] != nil {
            return OutputUnits(type: "HU", source: "Modality CT, Rescale Type absent")
        }
        return nil
    }

    // MARK: - Pixel Value Extraction

    /// Measure the (modality-transformed) pixel value at a point
    func measurePixelValue(at point: PixelPoint, frame: Int = 0) throws -> MeasurementResult {
        let raw = try rawPixelValue(at: point, frame: frame)
        let value = modalityValue(raw, frame: frame)
        let transformed = hasModalityTransform(frame: frame)
        let units = transformed ? outputUnits(frame: frame) : nil
        return MeasurementResult(
            value: value,
            unitLabel: units?.type ?? "",
            description: transformed ? "Pixel value (raw=\(formatValue(raw)), rescaled)" : "Pixel value",
            ucum: units?.isHounsfield == true ? Self.hounsfieldUCUM : nil,
            calibration: nil
        )
    }

    // MARK: - Hounsfield Unit Measurement

    /// Measure Hounsfield Unit at a point (CT images). When the output units are not HU
    /// the value is still returned, labelled with its Rescale Type, with a warning.
    func measureHU(at point: PixelPoint) throws -> MeasurementResult {
        let value = try rescaledPixelValue(at: point)
        let units = outputUnits()
        if units?.isHounsfield == true {
            return MeasurementResult(value: value, unitLabel: "HU", description: "Hounsfield Unit",
                                     ucum: Self.hounsfieldUCUM, calibration: nil)
        }
        let type = units?.type
        Self.warn("Warning: output units are \(type.map { "\"\($0)\"" } ?? "not specified") "
            + "(Rescale Type (0028,1054) / Modality LUT Type (0028,3004)), not HU")
        return MeasurementResult(value: value, unitLabel: type ?? "",
                                 description: "Rescaled value (not Hounsfield Units)", ucum: nil, calibration: nil)
    }

    // MARK: - ROI Analysis

    /// Analyze a region of interest
    func analyzeROI(
        roi: ROIDefinition,
        includeStatistics: Bool,
        includeHistogram: Bool,
        histogramBins: Int,
        unit requested: MeasurementUnit
    ) throws -> ROIAnalysisResult {
        let (values, pixelCount, pixelArea) = try collectROIValues(roi: roi)
        let cal = calibration(frame: 0, points: Self.extentPoints(roi))
        let unit = effectiveUnit(requested, calibration: cal)
        let physicalArea = pixelAreaToPhysical(pixelArea: pixelArea, unit: unit, calibration: cal)

        var mean: Double?
        var std: Double?
        var minVal: Double?
        var maxVal: Double?
        var histogram: [HistogramBin]?

        if includeStatistics && !values.isEmpty {
            let m = values.reduce(0.0, +) / Double(values.count)
            mean = m
            minVal = values.min()
            maxVal = values.max()
            std = sqrt(values.reduce(0.0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count))
        }
        if includeHistogram && !values.isEmpty {
            histogram = Self.generateHistogram(values: values, bins: histogramBins)
        }

        return ROIAnalysisResult(
            pixelCount: pixelCount,
            areaValue: physicalArea,
            areaUnit: Self.areaUnitLabel(unit),
            mean: mean,
            standardDeviation: std,
            minimum: minVal,
            maximum: maxVal,
            histogram: histogram,
            roiDescription: Self.roiDescription(roi),
            areaUCUM: Self.areaUCUM(unit),
            valueUnit: hasModalityTransform() ? outputUnits()?.type : nil,
            calibration: cal
        )
    }

    /// Bounding corners of a ROI, used to choose an Ultrasound Region
    static func extentPoints(_ roi: ROIDefinition) -> [PixelPoint] {
        switch roi {
        case .rect(let x, let y, let w, let h):
            return [PixelPoint(x: x, y: y), PixelPoint(x: x + w - 0.5, y: y + h - 0.5)]
        case .circle(let cx, let cy, let r):
            return [PixelPoint(x: cx - r, y: cy - r), PixelPoint(x: cx + r - 0.5, y: cy + r - 0.5)]
        case .polygon(let v):
            return v
        }
    }

    /// Whether pixel (c, r) is in the ROI: its centre (c+0.5, r+0.5) per Table C.18.6-1
    static func contains(_ roi: ROIDefinition, column c: Int, row r: Int) -> Bool {
        let px = Double(c) + 0.5, py = Double(r) + 0.5
        switch roi {
        case .rect(let x, let y, let w, let h):
            return px >= x && px < x + w && py >= y && py < y + h
        case .circle(let cx, let cy, let radius):
            let dx = px - cx, dy = py - cy
            return dx * dx + dy * dy <= radius * radius
        case .polygon(let vertices):
            return vertices.count >= 3 && isPointInPolygon(point: PixelPoint(x: px, y: py), polygon: vertices)
        }
    }

    /// Collect modality-transformed values of the pixels whose centres lie in the ROI
    private func collectROIValues(roi: ROIDefinition) throws -> (values: [Double], count: Int, pixelArea: Double) {
        guard pixelData != nil else { throw MeasureError.noPixelData }
        let ext = Self.extentPoints(roi)
        let minC = max(0, Int(floor(ext.map(\.x).min() ?? 0)))
        let minR = max(0, Int(floor(ext.map(\.y).min() ?? 0)))
        let maxC = min(columns - 1, Int(ceil(ext.map(\.x).max() ?? 0)))
        let maxR = min(rows - 1, Int(ceil(ext.map(\.y).max() ?? 0)))

        var values: [Double] = []
        if minC <= maxC && minR <= maxR {
            for r in minR...maxR {
                for c in minC...maxC where Self.contains(roi, column: c, row: r) {
                    values.append(modalityValue(try storedValue(column: c, row: r)))
                }
            }
        }
        let area: Double
        switch roi {
        case .rect: area = Double(values.count)
        case .circle(_, _, let radius): area = Double.pi * radius * radius
        case .polygon(let vertices): area = Self.shoelaceArea(vertices: vertices)
        }
        return (values, values.count, area)
    }

    /// Ray casting algorithm for point-in-polygon test
    static func isPointInPolygon(point: PixelPoint, polygon: [PixelPoint]) -> Bool {
        var inside = false
        let n = polygon.count
        var j = n - 1
        for i in 0..<n {
            let xi = polygon[i].x, yi = polygon[i].y
            let xj = polygon[j].x, yj = polygon[j].y
            if (yi > point.y) != (yj > point.y) {
                let intersectX = (xj - xi) * (point.y - yi) / (yj - yi) + xi
                if point.x < intersectX {
                    inside = !inside
                }
            }
            j = i
        }
        return inside
    }

    /// Generate a histogram from pixel values
    static func generateHistogram(values: [Double], bins: Int) -> [HistogramBin] {
        guard let minVal = values.min(), let maxVal = values.max(), minVal < maxVal else {
            return []
        }
        let binWidth = (maxVal - minVal) / Double(bins)
        var counts = [Int](repeating: 0, count: bins)
        for value in values {
            var binIndex = Int((value - minVal) / binWidth)
            if binIndex >= bins { binIndex = bins - 1 }
            counts[binIndex] += 1
        }
        return (0..<bins).map { i in
            HistogramBin(lowerBound: minVal + Double(i) * binWidth,
                         upperBound: minVal + Double(i + 1) * binWidth,
                         count: counts[i])
        }
    }

    /// Get a description of the ROI
    static func roiDescription(_ roi: ROIDefinition) -> String {
        switch roi {
        case .rect(let x, let y, let w, let h):
            return "Rectangle (\(Int(x)),\(Int(y)) \(Int(w))x\(Int(h)))"
        case .circle(let cx, let cy, let r):
            return "Circle (center=\(Int(cx)),\(Int(cy)) r=\(Int(r)))"
        case .polygon(let vertices):
            return "Polygon (\(vertices.count) vertices)"
        }
    }
}

// MARK: - Errors

enum MeasureError: LocalizedError {
    case fileNotFound(String)
    case missingImageDimensions
    case noPixelData
    case pointOutOfBounds(x: Int, y: Int, columns: Int, rows: Int)
    case pixelDataTooShort
    case unsupportedBitDepth(Int)
    case frameOutOfRange(frame: Int, numberOfFrames: Int)
    case notMonochrome(Int)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .missingImageDimensions:
            return "DICOM file does not contain image dimensions (Rows/Columns tags)"
        case .noPixelData:
            return "DICOM file does not contain pixel data (or it could not be decoded)"
        case .pointOutOfBounds(let x, let y, let columns, let rows):
            return "Point (\(x),\(y)) is outside image bounds (\(columns)x\(rows))"
        case .pixelDataTooShort:
            return "Pixel data is shorter than expected for the given coordinates"
        case .unsupportedBitDepth(let bits):
            return "Unsupported bit depth: \(bits) bits allocated"
        case .frameOutOfRange(let frame, let n):
            return "Frame number \(frame + 1) is out of range: Number of Frames (0028,0008) is \(n); "
                + "valid Frame numbers are 1...\(n) (deprecated --frame index 0...\(n - 1))"
        case .notMonochrome(let spp):
            return "Pixel values need Samples per Pixel (0028,0002) = 1; this image has \(spp)"
        }
    }
}
