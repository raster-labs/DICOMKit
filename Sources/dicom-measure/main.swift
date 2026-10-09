// NEMA-verified: 2026a, checked 2026-10-01 — option help and output keys diffed against PS3.3 2026a 10.7.1.3 (spacing Value order), Table C.18.6-1 (column,row; 0,0 = TLHC of the TLHC pixel), Table 10-3 (pixel --frame-number is 1-based, "The first Frame shall be denoted as Frame number 1"; --frame 0-based index deprecated, P-MEASURE-FRAME), C.11.1.1.2 (output units); spacing_source values are PS3.6 2026a Table 6-1 keywords (5); unit_ucum values per PS3.16 2026a CID 82 (UCUM), CID 7460 (3 of 3 incl. um), CID 7461 (3 of 3 incl. um2), CID 7181/7183, {pixels} as PS3.16 TID UNITS; text prints the UCUM code (P-MEASURE-UNIT)
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

struct DICOMMeasure: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-measure",
        abstract: "Perform precise medical imaging measurements on DICOM images",
        discussion: """
            Measure distances, areas, angles, and extract pixel statistics from DICOM images.

            Physical units come from, in this order: Pixel Spacing (0028,0030);
            the frame's Pixel Measures Sequence (0028,9110); the Sequence of
            Ultrasound Regions (0018,6011) region in cm holding the points;
            Imager Pixel Spacing (0018,1164), at the front plane of the detector
            housing; Nominal Scanned Pixel Spacing (0018,2010). Without any of
            them the result is in pixels. Spacing Values are row spacing, then
            column spacing (PS3.3 10.7.1.3).

            Points are x,y = column,row in the PS3.3 Table C.18.6-1 image
            coordinate system: 0,0 is the top-left corner of the top-left pixel
            and 1,1 its bottom-right corner, so a sampled point reads pixel
            floor(x),floor(y) and an ROI holds the pixels whose centres lie in it.

            Units: text output prints the UCUM code (PS3.16 CID 82; CID 7460
            cm, mm, um; CID 7461 cm2, mm2, um2; deg; [hnsf'U]; {pixels}) with
            the display symbol in parentheses when it differs, e.g.
            "Area: 12.0 mm2 (mm²)". JSON carries the UCUM code in unit_ucum /
            area_unit_ucum; the keys unit / area_unit (display symbols) are
            deprecated and kept unchanged. inches and px² have no UCUM code
            in PS3.16 and print the symbol only.

            Frames: pixel --frame-number N is 1-based (PS3.3 Table
            10-3: the first Frame is Frame number 1). --frame (0-based index)
            is deprecated.

            Examples:
              dicom-measure distance ct.dcm --p1 100,200 --p2 300,400
              dicom-measure area ct.dcm --polygon 100,100 150,200 200,200 180,120
              dicom-measure angle ct.dcm --vertex 200,200 --p1 100,100 --p2 300,100
              dicom-measure roi ct.dcm --rect 100,100,50,50 --statistics
              dicom-measure hu ct.dcm --point 200,200
              dicom-measure pixel ct.dcm --point 150,150 --frame-number 1
            """,
        version: "1.4.0",
        subcommands: [
            Distance.self,
            Area.self,
            Angle.self,
            ROI.self,
            HU.self,
            Pixel.self,
        ]
    )
}

// MARK: - Common Options

struct CommonOptions: ParsableArguments {
    @Argument(help: "Path to the DICOM file")
    var filePath: String

    @Option(name: .shortAndLong, help: "Output file path (prints to stdout if omitted)")
    var output: String?

    @Option(name: .shortAndLong, help: "Output format: text, json, csv")
    var format: OutputFormat = .text

    @Option(name: .long, help: "Unit for measurements: mm, cm, um, inches, pixels (physical units need a pixel spacing; see the overview)")
    var unit: MeasurementUnit = .mm

    @Flag(name: .long, help: "Force parsing of files without DICM prefix")
    var force: Bool = false

    @Flag(name: .long, help: "Verbose output for debugging")
    var verbose: Bool = false
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
    case text
    case json
    case csv
}

enum MeasurementUnit: String, ExpressibleByArgument, CaseIterable, Sendable {
    case mm
    case cm
    /// Micrometre, UCUM "um" (PS3.16 2026a CID 7460 / CID 7461)
    case um
    case inches
    case pixels
}

// MARK: - Distance Subcommand

struct Distance: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Measure distance between two points"
    )

    @OptionGroup var options: CommonOptions

    @Option(name: .long, help: "First point as x,y (e.g., 100,200)")
    var p1: String

    @Option(name: .long, help: "Second point as x,y (e.g., 300,400)")
    var p2: String

    mutating func run() throws {
        let point1 = try parsePoint(p1, name: "p1")
        let point2 = try parsePoint(p2, name: "p2")
        let engine = try MeasurementEngine(options: options)

        let result = engine.measureDistance(from: point1, to: point2, unit: options.unit)

        let output = formatResult(
            type: "distance",
            result: result,
            format: options.format,
            details: [
                "p1": "\(point1.x),\(point1.y)",
                "p2": "\(point2.x),\(point2.y)",
            ],
            geometric: true
        )
        try writeOutput(output, to: options.output)
    }
}

// MARK: - Area Subcommand

struct Area: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Measure area of a polygon or ellipse"
    )

    @OptionGroup var options: CommonOptions

    @Option(name: .long, parsing: .upToNextOption, help: "Polygon vertices as x,y pairs (e.g., 100,100 150,200 200,200)")
    var polygon: [String] = []

    @Option(name: .long, help: "Ellipse center and radii as cx,cy,rx,ry (e.g., 200,200,50,30)")
    var ellipse: String?

    mutating func validate() throws {
        guard !polygon.isEmpty || ellipse != nil else {
            throw ValidationError("Provide either --polygon or --ellipse")
        }
        if !polygon.isEmpty && polygon.count < 3 {
            throw ValidationError("Polygon requires at least 3 vertices")
        }
    }

    mutating func run() throws {
        let engine = try MeasurementEngine(options: options)

        let result: MeasurementResult
        var details: [String: String] = [:]

        if let ellipseStr = ellipse {
            let parts = ellipseStr.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 4 else {
                throw ValidationError("Ellipse requires 4 values: cx,cy,rx,ry")
            }
            result = engine.measureEllipseArea(
                center: PixelPoint(x: parts[0], y: parts[1]),
                radiusX: parts[2],
                radiusY: parts[3],
                unit: options.unit
            )
            details["shape"] = "ellipse"
            details["center"] = "\(parts[0]),\(parts[1])"
            details["radii"] = "\(parts[2]),\(parts[3])"
        } else {
            let points = try polygon.map { try parsePoint($0, name: "polygon vertex") }
            result = engine.measurePolygonArea(vertices: points, unit: options.unit)
            details["shape"] = "polygon"
            details["vertices"] = "\(points.count)"
        }

        let output = formatResult(type: "area", result: result, format: options.format, details: details, geometric: true)
        try writeOutput(output, to: options.output)
    }
}

// MARK: - Angle Subcommand

struct Angle: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Measure angle between two lines sharing a vertex"
    )

    @OptionGroup var options: CommonOptions

    @Option(name: .long, help: "Vertex point as x,y (e.g., 200,200)")
    var vertex: String

    @Option(name: .long, help: "First endpoint as x,y (e.g., 100,100)")
    var p1: String

    @Option(name: .long, help: "Second endpoint as x,y (e.g., 300,100)")
    var p2: String

    mutating func run() throws {
        let vertexPoint = try parsePoint(vertex, name: "vertex")
        let point1 = try parsePoint(p1, name: "p1")
        let point2 = try parsePoint(p2, name: "p2")
        let engine = try MeasurementEngine(options: options)

        let result = engine.measureAngle(vertex: vertexPoint, p1: point1, p2: point2)

        let output = formatResult(
            type: "angle",
            result: result,
            format: options.format,
            details: [
                "vertex": "\(vertexPoint.x),\(vertexPoint.y)",
                "p1": "\(point1.x),\(point1.y)",
                "p2": "\(point2.x),\(point2.y)",
            ],
            geometric: true
        )
        try writeOutput(output, to: options.output)
    }
}

// MARK: - ROI Subcommand

struct ROI: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Calculate statistics within a region of interest"
    )

    @OptionGroup var options: CommonOptions

    @Option(name: .long, help: "Rectangular ROI as x,y,width,height (e.g., 100,100,50,50)")
    var rect: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Polygon ROI vertices as x,y pairs")
    var polygon: [String] = []

    @Option(name: .long, help: "Circular ROI as cx,cy,radius (e.g., 200,200,25)")
    var circle: String?

    @Flag(name: .long, help: "Calculate extended statistics (mean, std, min, max)")
    var statistics: Bool = false

    @Flag(name: .long, help: "Generate pixel value histogram")
    var histogram: Bool = false

    @Option(name: .long, help: "Number of histogram bins")
    var bins: Int = 256

    mutating func validate() throws {
        guard rect != nil || !polygon.isEmpty || circle != nil else {
            throw ValidationError("Provide --rect, --polygon, or --circle to define the ROI")
        }
        if !polygon.isEmpty && polygon.count < 3 {
            throw ValidationError("Polygon ROI requires at least 3 vertices")
        }
        if bins < 2 || bins > 65536 {
            throw ValidationError("Number of bins must be between 2 and 65536")
        }
    }

    mutating func run() throws {
        let engine = try MeasurementEngine(options: options)

        let roi: ROIDefinition
        if let rectStr = rect {
            let parts = rectStr.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 4 else {
                throw ValidationError("Rectangle requires 4 values: x,y,width,height")
            }
            roi = .rect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        } else if let circleStr = circle {
            let parts = circleStr.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 3 else {
                throw ValidationError("Circle requires 3 values: cx,cy,radius")
            }
            roi = .circle(cx: parts[0], cy: parts[1], radius: parts[2])
        } else {
            let points = try polygon.map { try parsePoint($0, name: "polygon vertex") }
            roi = .polygon(vertices: points)
        }

        let result = try engine.analyzeROI(
            roi: roi,
            includeStatistics: statistics || histogram,
            includeHistogram: histogram,
            histogramBins: bins,
            unit: options.unit
        )

        let output = formatROIResult(result: result, format: options.format)
        try writeOutput(output, to: options.output)
    }
}

// MARK: - HU Subcommand

struct HU: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Extract Hounsfield Unit values from CT images"
    )

    @OptionGroup var options: CommonOptions

    @Option(name: .long, help: "Point to sample as x,y (e.g., 200,200)")
    var point: String?

    @Option(name: .long, help: "Rectangular ROI as x,y,width,height for averaging")
    var rect: String?

    @Flag(name: .long, help: "Calculate extended statistics for ROI")
    var statistics: Bool = false

    mutating func validate() throws {
        guard point != nil || rect != nil else {
            throw ValidationError("Provide either --point or --rect")
        }
    }

    mutating func run() throws {
        let engine = try MeasurementEngine(options: options)

        if let pointStr = point {
            let pt = try parsePoint(pointStr, name: "point")
            let result = try engine.measureHU(at: pt)
            let output = formatResult(
                type: "hu",
                result: result,
                format: options.format,
                details: ["point": "\(pt.x),\(pt.y)"]
            )
            try writeOutput(output, to: options.output)
        } else if let rectStr = rect {
            let parts = rectStr.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 4 else {
                throw ValidationError("Rectangle requires 4 values: x,y,width,height")
            }
            let roi = ROIDefinition.rect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            let result = try engine.analyzeROI(
                roi: roi,
                includeStatistics: statistics,
                includeHistogram: false,
                histogramBins: 256,
                unit: .pixels
            )
            let output = formatROIResult(result: result, format: options.format)
            try writeOutput(output, to: options.output)
        }
    }
}

// MARK: - Pixel Subcommand

struct Pixel: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Extract raw pixel values from DICOM images"
    )

    @OptionGroup var options: CommonOptions

    @Option(name: .long, help: "Point to sample as x,y (e.g., 150,150)")
    var point: String

    @Option(name: .long, help: "Frame number, 1-based (PS3.3 Table 10-3: the first Frame is Frame number 1); at most Number of Frames (0028,0008). Default 1")
    var frameNumber: Int?

    @Option(name: .long, help: "Deprecated: 0-based index; use --frame-number (index 0 is Frame number 1)")
    var frame: Int?

    mutating func validate() throws {
        if let n = frameNumber, n < 1 {
            throw ValidationError("--frame-number must be 1 or greater: the first Frame is Frame number 1 (PS3.3 Table 10-3)")
        }
    }

    /// 0-based frame index from --frame-number (1-based) or the deprecated --frame (0-based),
    /// with the deprecation note when --frame is used.
    static func frameIndex(frameNumber: Int?, frame: Int?) -> (index: Int, note: String?) {
        if let n = frameNumber { return (n - 1, nil) }
        if let i = frame {
            return (i, "Note: --frame is deprecated (0-based index); use --frame-number \(i + 1)")
        }
        return (0, nil)
    }

    mutating func run() throws {
        if frame != nil && frameNumber != nil {
            FileHandle.standardError.write(Data(
                "Error: --frame (deprecated 0-based index) and --frame-number both given; use --frame-number only\n".utf8))
            throw ExitCode.failure
        }
        let pt = try parsePoint(point, name: "point")
        let (index, note) = Self.frameIndex(frameNumber: frameNumber, frame: frame)
        if let note { FileHandle.standardError.write(Data((note + "\n").utf8)) }
        let engine = try MeasurementEngine(options: options)

        let result = try engine.measurePixelValue(at: pt, frame: index)

        let output = formatResult(
            type: "pixel",
            result: result,
            format: options.format,
            details: [
                "point": "\(pt.x),\(pt.y)",
                "frame": "\(index)",               // deprecated key: 0-based index
                "frame_number": "\(index + 1)",    // PS3.3 Table 10-3: 1-based
            ]
        )
        try writeOutput(output, to: options.output)
    }
}

// MARK: - Shared Helpers

/// A point in pixel coordinates
struct PixelPoint: Sendable {
    let x: Double
    let y: Double
}

/// Measurement result with value and unit label
struct MeasurementResult: Sendable {
    let value: Double
    let unitLabel: String
    let description: String
    /// UCUM code of the unit when PS3.16 lists one (CID 7460, 7461, 7181, 7183)
    var ucum: String? = nil
    /// Spacing used, for geometric measurements
    var calibration: SpacingCalibration? = nil
}

/// ROI definition
enum ROIDefinition: Sendable {
    case rect(x: Double, y: Double, width: Double, height: Double)
    case circle(cx: Double, cy: Double, radius: Double)
    case polygon(vertices: [PixelPoint])
}

/// ROI analysis result
struct ROIAnalysisResult: Sendable {
    let pixelCount: Int
    let areaValue: Double
    let areaUnit: String
    let mean: Double?
    let standardDeviation: Double?
    let minimum: Double?
    let maximum: Double?
    let histogram: [HistogramBin]?
    let roiDescription: String
    /// UCUM code of the area unit (PS3.16 CID 7461)
    var areaUCUM: String? = nil
    /// Output units of the statistics: Rescale Type / Modality LUT Type (PS3.3 C.11.1.1.2)
    var valueUnit: String? = nil
    /// Spacing used for the area
    var calibration: SpacingCalibration? = nil
}

/// Detail rows describing the spacing a result used (keys spacing_source, spacing_mm, spacing_note)
func calibrationDetails(_ cal: SpacingCalibration?) -> [String: String] {
    guard let cal else { return ["spacing_source": "none"] }
    var d = ["spacing_source": cal.source,
             "spacing_mm": "\(formatValue(cal.rowSpacing))\\\(formatValue(cal.columnSpacing))"]
    if let note = cal.note { d["spacing_note"] = note }
    return d
}

/// Histogram bin
struct HistogramBin: Sendable {
    let lowerBound: Double
    let upperBound: Double
    let count: Int
}

/// Parse a point string "x,y" into a PixelPoint
func parsePoint(_ str: String, name: String) throws -> PixelPoint {
    let parts = str.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 2 else {
        throw ValidationError("\(name) must be specified as x,y (e.g., 100,200)")
    }
    return PixelPoint(x: parts[0], y: parts[1])
}

/// Format a single measurement result
func formatResult(type: String, result: MeasurementResult, format: OutputFormat, details: [String: String],
                  geometric: Bool = false) -> String {
    var details = details
    if geometric {
        details.merge(calibrationDetails(result.calibration)) { a, _ in a }
    }
    switch format {
    case .text:
        var output = "\(result.description): \(formatValue(result.value)) \(textUnit(ucum: result.ucum, symbol: result.unitLabel))\n"
        for (key, value) in details.sorted(by: { $0.key < $1.key }) {
            switch key {
            case "frame": continue                                   // 0-based index: JSON only (deprecated)
            case "frame_number": output += "  Frame number: \(value)\n"
            default: output += "  \(key): \(value)\n"
            }
        }
        return output

    case .json:
        var dict: [String: Any] = [
            "type": type,
            "value": result.value,
            "unit": result.unitLabel,
            "description": result.description,
        ]
        if let ucum = result.ucum { dict["unit_ucum"] = ucum }
        for (key, value) in details {
            dict[key] = value
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString + "\n"
        }
        return "{}\n"

    case .csv:
        let escapedDesc = result.description.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(type)\",\"\(escapedDesc)\",\(formatValue(result.value)),\"\(result.unitLabel)\"\n"
    }
}

/// Format ROI analysis result
func formatROIResult(result: ROIAnalysisResult, format: OutputFormat) -> String {
    switch format {
    case .text:
        var output = "ROI Analysis: \(result.roiDescription)\n"
        output += "  Pixel count: \(result.pixelCount)\n"
        output += "  Area: \(formatValue(result.areaValue)) \(textUnit(ucum: result.areaUCUM, symbol: result.areaUnit))\n"
        if let cal = result.calibration {
            output += "  Spacing: \(formatValue(cal.rowSpacing))\\\(formatValue(cal.columnSpacing)) mm (\(cal.source)\(cal.note.map { "; \($0)" } ?? ""))\n"
        } else {
            output += "  Spacing: none\n"
        }
        if let unit = result.valueUnit {
            output += "  Value units: \(unit)\n"
        }
        if let mean = result.mean {
            output += "  Mean: \(formatValue(mean))\n"
        }
        if let std = result.standardDeviation {
            output += "  Std Dev: \(formatValue(std))\n"
        }
        if let min = result.minimum {
            output += "  Min: \(formatValue(min))\n"
        }
        if let max = result.maximum {
            output += "  Max: \(formatValue(max))\n"
        }
        if let bins = result.histogram {
            output += "  Histogram (\(bins.count) bins):\n"
            let maxCount = bins.map(\.count).max() ?? 1
            for bin in bins where bin.count > 0 {
                let barLength = max(1, bin.count * 40 / maxCount)
                let bar = String(repeating: "█", count: barLength)
                output += "    [\(formatValue(bin.lowerBound))-\(formatValue(bin.upperBound))]: \(bar) \(bin.count)\n"
            }
        }
        return output

    case .json:
        var dict: [String: Any] = [
            "roi": result.roiDescription,
            "pixel_count": result.pixelCount,
            "area": result.areaValue,
            "area_unit": result.areaUnit,
        ]
        if let ucum = result.areaUCUM { dict["area_unit_ucum"] = ucum }
        if let unit = result.valueUnit { dict["value_unit"] = unit }
        for (key, value) in calibrationDetails(result.calibration) { dict[key] = value }
        if let mean = result.mean { dict["mean"] = mean }
        if let std = result.standardDeviation { dict["std_dev"] = std }
        if let min = result.minimum { dict["min"] = min }
        if let max = result.maximum { dict["max"] = max }
        if let bins = result.histogram {
            dict["histogram"] = bins.map { bin in
                ["lower": bin.lowerBound, "upper": bin.upperBound, "count": bin.count] as [String: Any]
            }
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString + "\n"
        }
        return "{}\n"

    case .csv:
        var parts = ["\"\(result.roiDescription)\"", "\(result.pixelCount)", "\(formatValue(result.areaValue))", "\"\(result.areaUnit)\""]
        if let mean = result.mean { parts.append(formatValue(mean)) }
        if let std = result.standardDeviation { parts.append(formatValue(std)) }
        if let min = result.minimum { parts.append(formatValue(min)) }
        if let max = result.maximum { parts.append(formatValue(max)) }
        return parts.joined(separator: ",") + "\n"
    }
}

/// Unit as printed in text output: the UCUM code (PS3.16 2026a CID 82) with the display symbol
/// in parentheses when it differs ("mm2 (mm²)", "deg (°)"); the symbol alone without a code.
func textUnit(ucum: String?, symbol: String) -> String {
    guard let ucum, !ucum.isEmpty else { return symbol }
    if symbol.isEmpty || symbol == ucum { return ucum }
    return "\(ucum) (\(symbol))"
}

/// Format a double value for display
func formatValue(_ value: Double) -> String {
    if value == value.rounded() && abs(value) < 1e10 {
        return String(format: "%.1f", value)
    }
    return String(format: "%.4f", value)
}

/// Write output to file or stdout
func writeOutput(_ text: String, to path: String?) throws {
    if let outputPath = path {
        let outputURL = URL(fileURLWithPath: outputPath)
        let outputDir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: outputURL)
        print("✓ Output written to: \(outputPath)")
    } else {
        print(text, terminator: "")
    }
}

DICOMMeasure.main()
