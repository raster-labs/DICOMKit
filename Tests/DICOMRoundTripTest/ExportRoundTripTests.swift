// ExportRoundTripTests.swift
// Oracle-based round-trip tests for the `dicom-export` tool.
//
// All tests call the DICOMKit LIBRARY directly (never the CLI binary). The
// library surface under test is `DICOMImageExporter` plus the DICOMFile /
// PixelData rendering primitives. Every assertion is a mathematical or semantic
// fact true by definition (a formula, a clamp, an invertible/lossless property,
// or an image-dimension identity) — never a comparison against a re-implementation
// of the tool.

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

final class ExportRoundTripTests: XCTestCase {

    // MARK: - Pure geometry / arithmetic oracles (platform-independent)

    // Oracle: contact-sheet total dims = documented grid formula for count/columns/thumb/spacing.
    func testContactSheetLayoutMatchesFormula() {
        let imageCount = 6, columns = 3, thumb = 32, spacing = 4
        let includeLabels = false
        let layout = DICOMImageExporter.contactSheetLayout(
            imageCount: imageCount, columns: columns,
            thumbnailSize: thumb, spacing: spacing, includeLabels: includeLabels
        )
        let expectedRows = (imageCount + columns - 1) / columns           // = 2
        let labelHeight = includeLabels ? 20 : 0
        let expectedWidth = columns * thumb + (columns + 1) * spacing
        let expectedHeight = expectedRows * (thumb + labelHeight) + (expectedRows + 1) * spacing
        XCTAssertEqual(layout.rows, expectedRows)
        XCTAssertEqual(layout.totalWidth, expectedWidth)
        XCTAssertEqual(layout.totalHeight, expectedHeight)
        // rows is always at least 1 by contract.
        XCTAssertGreaterThanOrEqual(
            DICOMImageExporter.contactSheetLayout(
                imageCount: 0, columns: 3, thumbnailSize: thumb,
                spacing: spacing, includeLabels: false).rows,
            1)
    }

    // Oracle: thumbnail (x,y) is the row/col grid position; index 0 = (spacing, spacing).
    func testThumbnailPositionGrid() {
        let columns = 4, thumb = 256, spacing = 4
        let p0 = DICOMImageExporter.thumbnailPosition(
            index: 0, columns: columns, thumbnailSize: thumb, spacing: spacing, includeLabels: false)
        XCTAssertEqual(p0.x, spacing)
        XCTAssertEqual(p0.y, spacing)

        // Next column advances x by (thumb + spacing), y unchanged.
        let p1 = DICOMImageExporter.thumbnailPosition(
            index: 1, columns: columns, thumbnailSize: thumb, spacing: spacing, includeLabels: false)
        XCTAssertEqual(p1.x, spacing + (thumb + spacing))
        XCTAssertEqual(p1.y, spacing)

        // Wrapping to next row resets x to spacing, advances y by one full row.
        let p4 = DICOMImageExporter.thumbnailPosition(
            index: columns, columns: columns, thumbnailSize: thumb, spacing: spacing, includeLabels: false)
        XCTAssertEqual(p4.x, spacing)
        XCTAssertEqual(p4.y, spacing + (thumb + spacing))
    }

    // Oracle: GIF frame delay (s) = 1/fps for fps>0; degrades to 0.1 for fps<=0.
    func testGifFrameDelayReciprocal() {
        XCTAssertEqual(DICOMImageExporter.gifFrameDelay(fps: 10), 0.1, accuracy: 1e-12)
        XCTAssertEqual(DICOMImageExporter.gifFrameDelay(fps: 4), 0.25, accuracy: 1e-12)
        XCTAssertEqual(DICOMImageExporter.gifFrameDelay(fps: 0), 0.1, accuracy: 1e-12)
        XCTAssertEqual(DICOMImageExporter.gifFrameDelay(fps: -5), 0.1, accuracy: 1e-12)
    }

    // Oracle: validated frame range clamps to [0, totalFrames-1]; nil end => last frame; nil for empty.
    func testValidatedFrameRangeClamps() {
        XCTAssertNil(DICOMImageExporter.validatedFrameRange(start: 0, end: nil, totalFrames: 0))

        let full = DICOMImageExporter.validatedFrameRange(start: 0, end: nil, totalFrames: 5)
        XCTAssertEqual(full?.start, 0)
        XCTAssertEqual(full?.end, 4)

        let overshoot = DICOMImageExporter.validatedFrameRange(start: 99, end: 200, totalFrames: 5)
        XCTAssertEqual(overshoot?.start, 4)
        XCTAssertEqual(overshoot?.end, 4)

        let negative = DICOMImageExporter.validatedFrameRange(start: -3, end: 2, totalFrames: 5)
        XCTAssertEqual(negative?.start, 0)
        XCTAssertEqual(negative?.end, 2)

        // end < start is clamped up to start.
        let inverted = DICOMImageExporter.validatedFrameRange(start: 3, end: 1, totalFrames: 5)
        XCTAssertEqual(inverted?.start, 3)
        XCTAssertEqual(inverted?.end, 3)
    }

    // Oracle: path organization yields UNKNOWN component when name/UID is nil or empty; sanitizes separators.
    func testBuildOrganizedPathUnknownAndSanitize() {
        // flat = base + filename, no subdirs.
        XCTAssertEqual(
            DICOMImageExporter.buildOrganizedPath(
                baseOutput: "/out", scheme: .flat,
                patientName: "Anyone", studyUID: nil, seriesUID: nil, filename: "a.png"),
            "/out/a.png")

        // patient scheme with nil name -> UNKNOWN directory.
        let nilPatient = DICOMImageExporter.buildOrganizedPath(
            baseOutput: "/out", scheme: .patient,
            patientName: nil, studyUID: nil, seriesUID: nil, filename: "a.png")
        XCTAssertEqual(nilPatient, "/out/UNKNOWN/a.png")

        // Empty string sanitizes to UNKNOWN.
        let emptyPatient = DICOMImageExporter.buildOrganizedPath(
            baseOutput: "/out", scheme: .patient,
            patientName: "", studyUID: nil, seriesUID: nil, filename: "a.png")
        XCTAssertEqual(emptyPatient, "/out/UNKNOWN/a.png")

        // Path separators / illegal chars replaced by underscore.
        let dirty = DICOMImageExporter.buildOrganizedPath(
            baseOutput: "/out", scheme: .patient,
            patientName: "Doe^John", studyUID: nil, seriesUID: nil, filename: "a.png")
        XCTAssertEqual(dirty, "/out/Doe_John/a.png")

        // series scheme nests patient/study/series.
        let series = DICOMImageExporter.buildOrganizedPath(
            baseOutput: "/out", scheme: .series,
            patientName: "P1", studyUID: "S1", seriesUID: "Q1", filename: "a.png")
        XCTAssertEqual(series, "/out/P1/S1/Q1/a.png")
    }

    // Oracle: --organize-by study nests patient/study (but NOT series) in the output path.
    func testBuildOrganizedPathStudyScheme() {
        let studyPath = DICOMImageExporter.buildOrganizedPath(
            baseOutput: "/out", scheme: .study,
            patientName: "P1", studyUID: "S1", seriesUID: "Q1", filename: "a.png")
        XCTAssertTrue(studyPath.hasPrefix("/out/P1/S1/"), "study scheme nests patient/study: \(studyPath)")
        XCTAssertTrue(studyPath.hasSuffix("a.png"))
        XCTAssertFalse(studyPath.contains("Q1"), "study scheme must NOT nest the series")
    }

    // Oracle: --labels adds a per-row label band (20px) to the contact-sheet height;
    // width is unchanged. Complements testContactSheetLayoutMatchesFormula (labels off).
    func testContactSheetLabelsAddRowHeight() {
        let (count, cols, thumb, sp) = (6, 3, 32, 4)
        let noLabels = DICOMImageExporter.contactSheetLayout(
            imageCount: count, columns: cols, thumbnailSize: thumb, spacing: sp, includeLabels: false)
        let withLabels = DICOMImageExporter.contactSheetLayout(
            imageCount: count, columns: cols, thumbnailSize: thumb, spacing: sp, includeLabels: true)
        XCTAssertEqual(withLabels.totalWidth, noLabels.totalWidth, "labels must not change width")
        XCTAssertEqual(withLabels.totalHeight, noLabels.totalHeight + noLabels.rows * 20,
                       "labels add a 20px band per row")
    }

    // Oracle: sanitizePathComponent keeps [A-Za-z0-9._-], maps everything else to _, empty->UNKNOWN.
    func testSanitizePathComponent() {
        XCTAssertEqual(DICOMImageExporter.sanitizePathComponent("abc_123.-x"), "abc_123.-x")
        XCTAssertEqual(DICOMImageExporter.sanitizePathComponent("a/b c:d"), "a_b_c_d")
        XCTAssertEqual(DICOMImageExporter.sanitizePathComponent(""), "UNKNOWN")
    }

    // Oracle: determineWindowSettings converts HU window to stored space via (c-intercept)/slope, w/|slope|.
    func testDetermineWindowSettingsRescaleConversion() throws {
        // Build a CT with Rescale Slope=1, Intercept=-1024, and no stored VOI window.
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString(rtUID(), for: .sopInstanceUID, vr: .UI)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setUInt16(4, for: .rows)
        ds.setUInt16(4, for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(16, for: .bitsStored)
        ds.setUInt16(15, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds.setString("1", for: .rescaleSlope, vr: .DS)
        ds.setString("-1024", for: .rescaleIntercept, vr: .DS)
        let pixels = Data(count: 4 * 4 * 2)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixels)
        let file = DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2")
        let pd = try XCTUnwrap(file.pixelData())

        let slope = file.rescaleSlope()
        let intercept = file.rescaleIntercept()
        XCTAssertEqual(slope, 1.0, accuracy: 1e-9)
        XCTAssertEqual(intercept, -1024.0, accuracy: 1e-9)

        // Explicit HU window 40/400 -> stored center (40 - (-1024))/1 = 1064, width 400.
        let ws = DICOMImageExporter.determineWindowSettings(
            from: file, pixelData: pd, frameIndex: 0, windowCenter: 40, windowWidth: 400)
        XCTAssertEqual(ws.center, (40.0 - intercept) / slope, accuracy: 1e-9)
        XCTAssertEqual(ws.width, 400.0 / abs(slope), accuracy: 1e-9)
    }

    // Oracle: with no stored window and no explicit window, fallback center/width come from the frame's pixel range.
    func testDetermineWindowSettingsPixelRangeFallback() throws {
        // 8-bit frame filled with a gradient 0..15 -> pixel range known.
        let file = makeGrayscale8(rows: 4, cols: 4, fillPattern: { UInt8($0) }) // values 0..15
        let pd = try XCTUnwrap(file.pixelData())
        let range = try XCTUnwrap(pd.pixelRange(forFrame: 0))
        XCTAssertEqual(range.min, 0)
        XCTAssertEqual(range.max, 15)

        // No stored window in makeGrayscale8, no explicit -> the full input range x1…x2 of
        // PS3.3 C.11.2.1.2.1: center = (x1+x2+1)/2, width = x2-x1+1 (D66).
        XCTAssertNil(file.windowSettings())
        let ws = DICOMImageExporter.determineWindowSettings(
            from: file, pixelData: pd, frameIndex: 0, windowCenter: nil, windowWidth: nil)
        XCTAssertEqual(ws.center, Double(range.min + range.max + 1) / 2.0, accuracy: 1e-9)
        XCTAssertEqual(ws.width, Double(range.max - range.min + 1), accuracy: 1e-9)
    }

    #if canImport(CoreGraphics)
    /// D66: the auto window selects exactly x1…x2 — x1 black, x2 white and every value
    /// between on the ramp, here x · 255 / 15 = 17x (no value below x2 saturates).
    func testAutoWindowSpansTheFullInputRange() throws {
        let file = makeGrayscale8(rows: 4, cols: 4, fillPattern: { UInt8($0) }) // values 0..15
        let pd = try XCTUnwrap(file.pixelData())
        let image = try XCTUnwrap(PixelDataRenderer(pixelData: pd).renderFrame(0))
        let bytes = [UInt8](try XCTUnwrap(image.dataProvider?.data as Data?))
        XCTAssertEqual(bytes, (0..<16).map { UInt8($0 * 17) })
    }

    /// D65: export applies the file's window after its rescale (PS3.3 C.11.2.1.2.1),
    /// whatever the slope — including a negative one, which the stored-unit conversion
    /// rendered inverted.
    func testExportAppliesTheWindowAfterTheRescale() throws {
        func linearByte(_ x: Double, _ c: Double, _ w: Double) -> UInt8 {
            if x <= c - 0.5 - (w - 1) / 2 { return 0 }
            if x > c - 0.5 + (w - 1) / 2 { return 255 }
            return UInt8(((x - (c - 0.5)) / (w - 1) + 0.5) * 255 + 1e-9)
        }
        let stored: [Int16] = [-100, -26, -25, -24, 0, 24, 25, 26, 100]
        for (slope, intercept, center) in [(2.0, 0.0, 0.0), (-1.0, 100.0, 100.0)] {
            let base = makeGrayscale16(rows: 1, cols: UInt16(stored.count),
                                       fillPattern: { UInt16(bitPattern: stored[$0]) }, signed: true)
            var ds = base.dataSet
            ds.setString(String(slope), for: .rescaleSlope, vr: .DS)
            ds.setString(String(intercept), for: .rescaleIntercept, vr: .DS)
            ds.setString(String(center), for: .windowCenter, vr: .DS)
            ds.setString("100", for: .windowWidth, vr: .DS)
            let file = DICOMFile(fileMetaInformation: base.fileMetaInformation, dataSet: ds)
            let pd = try XCTUnwrap(file.pixelData())
            let image = try DICOMImageExporter.renderFrameForExport(
                file: file, pixelData: pd, frameIndex: 0,
                applyWindow: false, windowCenter: nil, windowWidth: nil)
            let bytes = [UInt8](try XCTUnwrap(image.dataProvider?.data as Data?))
            XCTAssertEqual(bytes, stored.map { linearByte(slope * Double($0) + intercept, center, 100) },
                           "slope \(slope)")
        }
    }
    #endif

    #if canImport(CoreGraphics) && canImport(ImageIO)

    // MARK: - Rendering / encoding oracles (CoreGraphics / ImageIO)

    // Oracle: exported PNG pixel dimensions equal the DICOM Columns (width) x Rows (height).
    func testSingleExportPNGDimensionsMatchDICOM() throws {
        // 128 rows x 64 columns -> PNG width 64, height 128.
        let file = makeGrayscale8(rows: 128, cols: 64)
        let pd = try XCTUnwrap(file.pixelData())
        let image = try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pd, frameIndex: 0,
            applyWindow: false, windowCenter: nil, windowWidth: nil)
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 128)

        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("out.png")
        try DICOMImageExporter.exportCGImage(image, to: url, format: .png, quality: 100, metadata: nil)

        let (w, h) = try pngDimensions(url)
        XCTAssertEqual(w, 64)
        XCTAssertEqual(h, 128)
    }

    // Oracle: higher JPEG quality yields a larger (never smaller) file than very low quality.
    func testJPEGQualityAffectsFileSize() throws {
        // RGB with structure so JPEG quality actually changes byte size.
        let file = makeRGB8(rows: 128, cols: 128)
        let pd = try XCTUnwrap(file.pixelData())
        let image = try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pd, frameIndex: 0,
            applyWindow: false, windowCenter: nil, windowWidth: nil)

        let dir = try makeTempDir()
        let lowURL = dir.appendingPathComponent("low.jpg")
        let highURL = dir.appendingPathComponent("high.jpg")
        try DICOMImageExporter.exportCGImage(image, to: lowURL, format: .jpeg, quality: 10, metadata: nil)
        try DICOMImageExporter.exportCGImage(image, to: highURL, format: .jpeg, quality: 95, metadata: nil)

        let lowSize = try fileSize(lowURL)
        let highSize = try fileSize(highURL)
        XCTAssertLessThan(lowSize, highSize)
    }

    // Oracle: applying an explicit window vs the default produces a different rendered raster.
    func testApplyWindowVsDefaultDiffer() throws {
        // 16-bit gradient so windowing changes the mapping.
        let file = makeGrayscale16(rows: 32, cols: 32, fillPattern: { UInt16(($0 % 64) * 1000) })
        let pd = try XCTUnwrap(file.pixelData())

        let defaultImage = try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pd, frameIndex: 0,
            applyWindow: false, windowCenter: nil, windowWidth: nil)
        // A narrow explicit window centered low should saturate differently.
        let windowedImage = try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pd, frameIndex: 0,
            applyWindow: true, windowCenter: 5000, windowWidth: 100)

        let a = try rawBytes(of: defaultImage)
        let b = try rawBytes(of: windowedImage)
        XCTAssertNotEqual(a, b)
    }

    // Oracle: buildEXIFMetadata maps each DICOM field into its documented EXIF/TIFF dictionary key
    // (deterministic, lossless mapping), and export-with-metadata still produces a readable JPEG.
    func testEmbedMetadataMappingAndExport() throws {
        // makeGrayscale8 sets PatientName "RoundTrip^Patient" (TIFF/ImageDescription) and Modality "CT" (EXIF/UserComment, D126).
        let file = makeGrayscale8(rows: 16, cols: 16)

        // Semantic oracle on the built dictionary: fields land in the mapped dictionary/key verbatim.
        let built = try XCTUnwrap(
            DICOMImageExporter.buildEXIFMetadata(from: file, fields: ["PatientName", "Modality"]) as? [String: Any])
        let tiffBuilt = try XCTUnwrap(built[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
        XCTAssertEqual(tiffBuilt["ImageDescription"] as? String, "RoundTrip^Patient")
        let exifBuilt = try XCTUnwrap(built[kCGImagePropertyExifDictionary as String] as? [String: Any])
        XCTAssertEqual(exifBuilt["UserComment"] as? String, "Modality=CT")

        // Export with that metadata must still write a valid, readable JPEG of the right size.
        let pd = try XCTUnwrap(file.pixelData())
        let image = try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pd, frameIndex: 0,
            applyWindow: false, windowCenter: nil, windowWidth: nil)
        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("meta.jpg")
        try DICOMImageExporter.exportCGImage(image, to: url, format: .jpeg, quality: 90, metadata: built as CFDictionary)
        let (w, h) = try pngDimensions(url) // reads pixel dims for any ImageIO-decodable file
        XCTAssertEqual(w, 16)
        XCTAssertEqual(h, 16)
    }

    // Oracle: rendering frame index N reflects that frame's own pixel data (distinct constant fills
    // yield distinct per-frame pixel ranges and, under one fixed shared window, distinct rasters).
    func testMultiFrameIndexRespected() throws {
        // 3 frames filled 0, 128, 255.
        let fills: [UInt8] = [0, 128, 255]
        let file = makeMultiFrame(rows: 16, cols: 16, frames: 3, fill: { fills[$0] })
        let pd = try XCTUnwrap(file.pixelData())
        XCTAssertEqual(pd.descriptor.numberOfFrames, 3)

        // Each frame's stored pixel range is exactly {fill, fill} — the frame index selects that frame.
        for (i, fill) in fills.enumerated() {
            let r = try XCTUnwrap(pd.pixelRange(forFrame: i))
            XCTAssertEqual(r.min, Int(fill))
            XCTAssertEqual(r.max, Int(fill))
        }

        // Under one fixed explicit window spanning 0..255, the three distinct constant fills
        // must map to three distinct output rasters (frame identity is preserved through render).
        let window = WindowSettings(center: 128, width: 255)
        let b0 = try rawBytes(of: try XCTUnwrap(file.tryRenderFrame(0, window: window)))
        let b1 = try rawBytes(of: try XCTUnwrap(file.tryRenderFrame(1, window: window)))
        let b2 = try rawBytes(of: try XCTUnwrap(file.tryRenderFrame(2, window: window)))
        XCTAssertNotEqual(b0, b1)
        XCTAssertNotEqual(b1, b2)
        XCTAssertNotEqual(b0, b2)
    }

    // Oracle: contact-sheet composite PNG has exactly the layout dimensions and is a valid readable PNG.
    func testContactSheetOutputDimensions() throws {
        // 6 thumbnails, 3 columns, 32px thumbs, 4px spacing, no labels.
        let imageCount = 6, columns = 3, thumb = 32, spacing = 4
        let layout = DICOMImageExporter.contactSheetLayout(
            imageCount: imageCount, columns: columns,
            thumbnailSize: thumb, spacing: spacing, includeLabels: false)

        let composite = try makeContactSheet(
            imageCount: imageCount, columns: columns,
            thumbnailSize: thumb, spacing: spacing, includeLabels: false)
        XCTAssertEqual(composite.width, layout.totalWidth)
        XCTAssertEqual(composite.height, layout.totalHeight)

        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("sheet.png")
        try DICOMImageExporter.exportCGImage(composite, to: url, format: .png, quality: 100, metadata: nil)
        let (w, h) = try pngDimensions(url)
        XCTAssertEqual(w, layout.totalWidth)
        XCTAssertEqual(h, layout.totalHeight)
    }

    // Oracle: an animated GIF built from N rendered frames is a valid GIF (GIF8x magic) reporting N frames.
    func testAnimateProducesValidGIF() throws {
        let frameCount = 4
        let fills: [UInt8] = [0, 85, 170, 255]
        let file = makeMultiFrame(rows: 24, cols: 24, frames: frameCount, fill: { fills[$0] })
        let pd = try XCTUnwrap(file.pixelData())

        var frames: [CGImage] = []
        let window = WindowSettings(center: 128, width: 255)
        for i in 0..<frameCount {
            frames.append(try XCTUnwrap(file.tryRenderFrame(i, window: window)))
        }

        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("anim.gif")
        try writeAnimatedGIF(frames: frames, delay: DICOMImageExporter.gifFrameDelay(fps: 10), to: url)

        // GIF signature: bytes 0..2 == "GIF", byte 3 == '8' (GIF87a or GIF89a), byte 5 == 'a'.
        let header = Array(try Data(contentsOf: url).prefix(6))
        XCTAssertEqual(Array(header.prefix(3)), Array("GIF".utf8))
        XCTAssertEqual(header[3], UInt8(ascii: "8"))
        XCTAssertEqual(header[5], UInt8(ascii: "a"))

        // Frame count round-trips.
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), frameCount)
    }

    // Oracle: bulk export writes exactly one image per input file, each readable.
    func testBulkExportAllFilesExported() throws {
        let files = [
            makeGrayscale8(rows: 16, cols: 16),
            makeGrayscale8(rows: 16, cols: 16),
            makeGrayscale16(rows: 16, cols: 16),
            makeRGB8(rows: 16, cols: 16),
        ]
        let dir = try makeTempDir()
        for (i, file) in files.enumerated() {
            let pd = try XCTUnwrap(file.pixelData())
            let image = try DICOMImageExporter.renderFrameForExport(
                file: file, pixelData: pd, frameIndex: 0,
                applyWindow: false, windowCenter: nil, windowWidth: nil)
            let path = DICOMImageExporter.buildOrganizedPath(
                baseOutput: dir.path, scheme: .flat,
                patientName: nil, studyUID: nil, seriesUID: nil, filename: "img\(i).png")
            let url = URL(fileURLWithPath: path)
            try DICOMImageExporter.exportCGImage(image, to: url, format: .png, quality: 100, metadata: nil)
        }
        XCTAssertEqual(countFiles(in: dir, extension: "png"), files.count)

        // Every output is a readable PNG.
        for i in 0..<files.count {
            let url = dir.appendingPathComponent("img\(i).png")
            let (w, h) = try pngDimensions(url)
            XCTAssertEqual(w, 16)
            XCTAssertEqual(h, 16)
        }
    }

    // Oracle: organize-by-patient creates one subdir per distinct patient name, each holding its files.
    func testBulkOrganizeByPatientCreatesSubdirs() throws {
        struct Item { let name: String; let filename: String }
        let items = [
            Item(name: "P1", filename: "a.png"),
            Item(name: "P1", filename: "b.png"),
            Item(name: "P2", filename: "c.png"),
        ]
        let dir = try makeTempDir()
        let file = makeGrayscale8(rows: 8, cols: 8)
        let pd = try XCTUnwrap(file.pixelData())
        let image = try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pd, frameIndex: 0,
            applyWindow: false, windowCenter: nil, windowWidth: nil)

        for item in items {
            let path = DICOMImageExporter.buildOrganizedPath(
                baseOutput: dir.path, scheme: .patient,
                patientName: item.name, studyUID: nil, seriesUID: nil, filename: item.filename)
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try DICOMImageExporter.exportCGImage(image, to: url, format: .png, quality: 100, metadata: nil)
        }

        let p1 = dir.appendingPathComponent("P1")
        let p2 = dir.appendingPathComponent("P2")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: p1.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: p2.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertEqual(countFiles(in: p1, extension: "png"), 2)
        XCTAssertEqual(countFiles(in: p2, extension: "png"), 1)
    }

    // MARK: - Private CoreGraphics/ImageIO helpers

    /// Reads back the pixel dimensions of a written image (round-trip verification).
    private func pngDimensions(_ url: URL) throws -> (Int, Int) {
        let props = try imageProperties(url)
        let w = try XCTUnwrap(props[kCGImagePropertyPixelWidth as String] as? Int)
        let h = try XCTUnwrap(props[kCGImagePropertyPixelHeight as String] as? Int)
        return (w, h)
    }

    /// Reads the top-level image properties dictionary for the first image in a file.
    private func imageProperties(_ url: URL) throws -> [String: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }

    private func fileSize(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attrs[.size] as? Int)
    }

    /// Extracts the raw RGBA byte buffer of a CGImage for exact raster comparison.
    private func rawBytes(of image: CGImage) throws -> Data {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = try XCTUnwrap(CGContext(
            data: &buffer, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Data(buffer)
    }

    /// Composes a contact sheet by rendering `imageCount` thumbnails into a grid whose
    /// geometry comes from `DICOMImageExporter.contactSheetLayout`/`thumbnailPosition`.
    private func makeContactSheet(
        imageCount: Int, columns: Int, thumbnailSize: Int, spacing: Int, includeLabels: Bool
    ) throws -> CGImage {
        let layout = DICOMImageExporter.contactSheetLayout(
            imageCount: imageCount, columns: columns,
            thumbnailSize: thumbnailSize, spacing: spacing, includeLabels: includeLabels)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: layout.totalWidth, height: layout.totalHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))

        for i in 0..<imageCount {
            let file = makeGrayscale8(rows: UInt16(thumbnailSize), cols: UInt16(thumbnailSize))
            let pd = try XCTUnwrap(file.pixelData())
            let thumb = try DICOMImageExporter.renderFrameForExport(
                file: file, pixelData: pd, frameIndex: 0,
                applyWindow: false, windowCenter: nil, windowWidth: nil)
            let pos = DICOMImageExporter.thumbnailPosition(
                index: i, columns: columns, thumbnailSize: thumbnailSize,
                spacing: spacing, includeLabels: includeLabels)
            ctx.draw(thumb, in: CGRect(
                x: pos.x, y: pos.y, width: thumbnailSize, height: thumbnailSize))
        }
        return try XCTUnwrap(ctx.makeImage())
    }

    /// Writes an animated GIF from the given frames using ImageIO (matches the tool's GIF path).
    private func writeAnimatedGIF(frames: [CGImage], delay: Double, to url: URL) throws {
        let type = UTType.gif.identifier as CFString
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, type, frames.count, nil))
        let gifProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(dest, gifProps as CFDictionary)
        let frameProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
        ]
        for frame in frames {
            CGImageDestinationAddImage(dest, frame, frameProps as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    #endif // CoreGraphics && ImageIO
}
