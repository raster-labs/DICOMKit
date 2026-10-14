import XCTest
import Foundation
import DICOMCore
@testable import DICOMKit
#if canImport(CoreGraphics)
import CoreGraphics
import CoreText
#endif

/// OCR region detection tests.
///
/// The coordinate transform is pinned first and independently of Vision: the worst
/// failure this feature can have is OCR correctly finding a name while a buggy
/// transform blanks the wrong pixels under an earned 113101. The Vision tests then
/// prove end-to-end that planted text on a synthetic frame lands inside a detected
/// region, and that the regions carry the safety dilation.
final class TextRegionDetectorTests: XCTestCase {

    typealias Region = PixelRedactionPlan.Region
    typealias Box = TextRegionDetector.NormalizedBox

    // MARK: - Coordinate transform (pre-integration)

    func testFlipYAndDenormalizeOnSquareFrame() {
        // Vision: box occupying the top 10% of a 100x100 frame, full width.
        // Bottom-left origin → y = 0.9, height = 0.1.
        let r = TextRegionDetector.pixelRegion(
            fromNormalized: Box(x: 0, y: 0.9, width: 1, height: 0.1),
            columns: 100, rows: 100, dilation: 0)
        XCTAssertEqual(r, Region(x: 0, y: 0, width: 100, height: 10))
    }

    func testNonSquareFrameScalesAxesIndependently() {
        // 640 columns x 480 rows. Box: x 25%..50%, from the bottom 10%..30%.
        let r = TextRegionDetector.pixelRegion(
            fromNormalized: Box(x: 0.25, y: 0.1, width: 0.25, height: 0.2),
            columns: 640, rows: 480, dilation: 0)
        // x: 160..320; y (top-left): (1 - 0.3) * 480 = 336 .. (1 - 0.1) * 480 = 432
        XCTAssertEqual(r, Region(x: 160, y: 336, width: 160, height: 96))
    }

    func testEdgesRoundOutwardNeverInward() {
        // 0.333 * 100 = 33.3 → floor 33; (0.333+0.1) * 100 = 43.3 → ceil 44.
        let r = TextRegionDetector.pixelRegion(
            fromNormalized: Box(x: 0.333, y: 0.5, width: 0.1, height: 0.1),
            columns: 100, rows: 100, dilation: 0)
        XCTAssertEqual(r?.x, 33)
        XCTAssertEqual(r?.width, 11, "the far edge rounds up so glyph fringes are covered")
    }

    func testDilationGrowsEverySideAndClampsToTheFrame() {
        let inner = TextRegionDetector.pixelRegion(
            fromNormalized: Box(x: 0.5, y: 0.5, width: 0.1, height: 0.1),
            columns: 100, rows: 100, dilation: 4)
        XCTAssertEqual(inner, Region(x: 46, y: 36, width: 18, height: 18))

        // Top-left corner box: dilation must clamp at 0, not go negative.
        let corner = TextRegionDetector.pixelRegion(
            fromNormalized: Box(x: 0, y: 0.9, width: 0.1, height: 0.1),
            columns: 100, rows: 100, dilation: 4)
        XCTAssertEqual(corner, Region(x: 0, y: 0, width: 14, height: 14))

        // Bottom-right corner box: dilation must clamp at Columns/Rows.
        let far = TextRegionDetector.pixelRegion(
            fromNormalized: Box(x: 0.9, y: 0, width: 0.1, height: 0.1),
            columns: 100, rows: 100, dilation: 4)
        XCTAssertEqual(far, Region(x: 86, y: 86, width: 14, height: 14))
    }

    func testDegenerateAndOutOfFrameBoxesYieldNothing() {
        XCTAssertNil(TextRegionDetector.pixelRegion(
            fromNormalized: Box(x: 0.5, y: 0.5, width: 0, height: 0.1),
            columns: 100, rows: 100, dilation: 4))
        XCTAssertNil(TextRegionDetector.pixelRegion(
            fromNormalized: Box(x: 1.5, y: 0.5, width: 0.1, height: 0.1),
            columns: 100, rows: 100, dilation: 0))
        XCTAssertNil(TextRegionDetector.pixelRegion(
            fromNormalized: Box(x: 0.5, y: 0.5, width: 0.1, height: 0.1),
            columns: 0, rows: 100, dilation: 0))
        XCTAssertNil(TextRegionDetector.pixelRegion(
            fromNormalized: Box(x: .nan, y: 0.5, width: 0.1, height: 0.1),
            columns: 100, rows: 100, dilation: 0))
    }

    func testBoxPartlyOutsideTheFrameIsClippedNotDropped() {
        let r = TextRegionDetector.pixelRegion(
            fromNormalized: Box(x: 0.95, y: -0.05, width: 0.2, height: 0.2),
            columns: 100, rows: 100, dilation: 0)
        XCTAssertEqual(r, Region(x: 95, y: 85, width: 5, height: 15))
    }

    // MARK: - Frame sampling

    func testSamplingPicksFirstMiddleLast() {
        XCTAssertEqual(TextRegionDetector.sampledFrameIndices(frameCount: 1, allFrames: false), [0])
        XCTAssertEqual(TextRegionDetector.sampledFrameIndices(frameCount: 2, allFrames: false), [0, 1])
        XCTAssertEqual(TextRegionDetector.sampledFrameIndices(frameCount: 3, allFrames: false), [0, 1, 2])
        XCTAssertEqual(TextRegionDetector.sampledFrameIndices(frameCount: 40, allFrames: false), [0, 19, 39])
        XCTAssertEqual(TextRegionDetector.sampledFrameIndices(frameCount: 0, allFrames: false), [0])
    }

    func testAllFramesSamplesEveryFrame() {
        XCTAssertEqual(TextRegionDetector.sampledFrameIndices(frameCount: 5, allFrames: true), [0, 1, 2, 3, 4])
    }

    func testUnionDeduplicatesAcrossFrames() {
        let r = Region(x: 1, y: 2, width: 3, height: 4)
        let s = Region(x: 5, y: 6, width: 7, height: 8)
        let detections = [
            TextRegionDetector.Detection(text: "A", region: r, confidence: 1, frameIndex: 0),
            TextRegionDetector.Detection(text: "A", region: r, confidence: 1, frameIndex: 19),
            TextRegionDetector.Detection(text: "B", region: s, confidence: 1, frameIndex: 39),
        ]
        XCTAssertEqual(TextRegionDetector.unionedRegions(detections), [r, s])
    }

    func testAuditRenderingNeverCarriesTheFullString() {
        let d = TextRegionDetector.Detection(
            text: "SMITH^JOHN", region: Region(x: 0, y: 0, width: 1, height: 1),
            confidence: 0.9, frameIndex: 0)
        XCTAssertFalse(d.redactedForAudit.contains("SMITH"))
        XCTAssertTrue(d.redactedForAudit.contains("10 chars"))
    }

    // MARK: - Vision integration (Apple platforms)

    #if canImport(Vision) && canImport(CoreGraphics)
    /// 8-bit grayscale bitmap (row-major, top-down) with `text` drawn near the top.
    /// Background 0.2 gray (51), glyphs white (255).
    private func bannerBitmap(
        text: String, columns: Int, rows: Int, textOrigin: (x: Int, y: Int), fontSize: CGFloat
    ) throws -> (bytes: Data, drawn: Region) {
        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: columns, height: rows, bitsPerComponent: 8,
            bytesPerRow: columns, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { throw XCTSkip("no bitmap context") }
        ctx.setFillColor(gray: 0.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: columns, height: rows))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: CGColor(gray: 1, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let baselineY = CGFloat(rows) - CGFloat(textOrigin.y) - bounds.maxY
        ctx.textPosition = CGPoint(x: CGFloat(textOrigin.x), y: baselineY)
        CTLineDraw(line, ctx)
        guard let raw = ctx.data else { throw XCTSkip("no bitmap data") }
        let drawn = Region(
            x: textOrigin.x + Int(bounds.minX.rounded(.down)), y: textOrigin.y,
            width: Int(bounds.width.rounded(.up)) + 1, height: Int(bounds.height.rounded(.up)) + 1)
        return (Data(bytes: raw, count: columns * rows), drawn)
    }

    private func fileMeta() -> DataSet {
        var meta = DataSet()
        meta.setString("1.2.840.10008.1.2.1", for: Tag(group: 0x0002, element: 0x0010), vr: .UI)
        return meta
    }

    private func seq(_ tag: Tag, _ elements: [DataElement]) -> DataElement {
        FunctionalGroupBuilder.sequenceElement(tag, items: [SequenceItem(elements: elements)], writer: DICOMWriter())
    }

    // MARK: Phase 2 — classic multiframe sampling

    /// A banner that appears ONLY mid-loop is missed by first/middle/last sampling
    /// (by design — banners are static) and caught by `--ocr-all-frames`.
    func testMidLoopOnlyTextNeedsAllFramesSampling() async throws {
        let columns = 512, rows = 256, frames = 7
        let blank = Data(repeating: 51, count: columns * rows)
        let (banner, _) = try bannerBitmap(text: "STAGE PEAK", columns: columns, rows: rows,
                                           textOrigin: (24, 20), fontSize: 28)
        var pixels = Data()
        for f in 0..<frames { pixels += (f == 1 || f == 5) ? banner : blank }   // never on 0, 3, 6

        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.6.1", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.7", for: .sopInstanceUID, vr: .UI)
        ds.setString("US", for: .modality, vr: .CS)
        ds.setUInt16(UInt16(rows), for: .rows); ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(8, for: .bitsAllocated); ds.setUInt16(8, for: .bitsStored); ds.setUInt16(7, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation); ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds.setString("\(frames)", for: .numberOfFrames, vr: .IS)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: pixels)
        let file = try DICOMFile.read(from: try DICOMFile(fileMetaInformation: fileMeta(), dataSet: ds).write())

        let sampled = try await TextRegionDetector().detect(in: file)
        XCTAssertTrue(sampled.isEmpty, "sampling scans 0/3/6 only: \(sampled.map(\.frameIndex))")
        let all = try await TextRegionDetector().detect(in: file, allFrames: true)
        XCTAssertEqual(Set(all.map(\.frameIndex)), [1, 5])

        // And once found, the region is blanked on EVERY frame, not just where it was seen.
        let regions = TextRegionDetector.unionedRegions(all)
        let plan = PixelRedactionPlan.plan(for: file.dataSet, detectedRegions: regions)
        let (out, outcome) = try XCTUnwrap(PixelRedactor().redact(fileData: try file.write(), plan: plan))
        XCTAssertEqual(outcome.frameCount, frames)
        let ocrLeftover0 = try await TextRegionDetector().detect(in: DICOMFile.read(from: out), allFrames: true)
        XCTAssertTrue(ocrLeftover0.isEmpty)
    }

    // MARK: Phase 2 — enhanced multiframe per-frame VOI

    /// 16-bit Enhanced MR: background 1000, glyphs 1100, NO top-level window. Each
    /// frame's own Frame VOI LUT item decides whether the text is visible at all:
    /// frames 0 and 2 window 1050/200 (text visible), frame 1 windows 3000/100 (all black).
    private func enhancedMRFixture(text: String = "DOE JANE", blindFrame: Int = 1, frames: Int = 3)
        throws -> (data: Data, drawn: Region) {
        let columns = 512, rows = 256
        let (bitmap, drawn) = try bannerBitmap(text: text, columns: columns, rows: rows,
                                               textOrigin: (24, 20), fontSize: 28)
        var frame = Data(capacity: columns * rows * 2)
        for b in bitmap {
            let v: UInt16 = b > 127 ? 1100 : 1000
            frame.append(UInt8(v & 0xFF)); frame.append(UInt8(v >> 8))
        }
        var pixels = Data()
        for _ in 0..<frames { pixels += frame }

        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.4.1", for: .sopClassUID, vr: .UI)   // Enhanced MR
        ds.setString("1.2.3.4.5.8", for: .sopInstanceUID, vr: .UI)
        ds.setString("MR", for: .modality, vr: .CS)
        ds.setUInt16(UInt16(rows), for: .rows); ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(16, for: .bitsAllocated); ds.setUInt16(12, for: .bitsStored); ds.setUInt16(11, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation); ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds.setString("\(frames)", for: .numberOfFrames, vr: .IS)
        ds.setSequence([SequenceItem(elements: [
            seq(.pixelMeasuresSequence, [DataElement.string(tag: .pixelSpacing, vr: .DS, value: "0.5\\0.5")]),
        ])], for: .sharedFunctionalGroupsSequence)
        var perFrame: [SequenceItem] = []
        for f in 0..<frames {
            let center = f == blindFrame ? "3000" : "1050"
            let width = f == blindFrame ? "100" : "200"
            perFrame.append(SequenceItem(elements: [
                seq(.frameContentSequence, [DataElement.uint32(tag: .inStackPositionNumber, value: UInt32(f + 1))]),
                seq(.frameVOILUTSequence, [
                    DataElement.string(tag: .windowCenter, vr: .DS, value: center),
                    DataElement.string(tag: .windowWidth, vr: .DS, value: width),
                ]),
            ]))
        }
        ds.setSequence(perFrame, for: .perFrameFunctionalGroupsSequence)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixels)
        return (try DICOMFile(fileMetaInformation: fileMeta(), dataSet: ds).write(), drawn)
    }

    func testEnhancedMultiframeOCRHonoursEachFramesOwnVOI() async throws {
        let (data, drawn) = try enhancedMRFixture()
        let file = try DICOMFile.read(from: data)
        let detections = try await TextRegionDetector().detect(in: file, allFrames: true)
        // Frames 0 and 2 render the text under their own window; frame 1's window
        // blacks everything out. Seeing text on frame 1 would mean frame 0's (or a
        // pixel-range) window was reused — the bug §4.3 forbids.
        XCTAssertEqual(Set(detections.map(\.frameIndex)), [0, 2], "\(detections.map { ($0.frameIndex, $0.text) })")
        let union = TextRegionDetector.unionedRegions(detections)
        XCTAssertTrue(union.contains { covers($0, drawn) }, "detected \(union) must cover \(drawn)")
    }

    func testEnhancedMultiframeRedactionKeepsFunctionalGroupsByteStable() async throws {
        let (data, _) = try enhancedMRFixture()
        let file = try DICOMFile.read(from: data)
        let regions = TextRegionDetector.unionedRegions(try await TextRegionDetector().detect(in: file))
        XCTAssertFalse(regions.isEmpty)
        let plan = PixelRedactionPlan.plan(for: file.dataSet, detectedRegions: regions)
        let (out, outcome) = try XCTUnwrap(PixelRedactor().redact(fileData: data, plan: plan))
        XCTAssertEqual(outcome.frameCount, 3)

        let cleaned = try DICOMFile.read(from: out)
        let perFrame = try XCTUnwrap(cleaned.dataSet.sequence(for: .perFrameFunctionalGroupsSequence))
        XCTAssertEqual(perFrame.count, 3, "NumberOfFrames == per-frame FG count")
        XCTAssertEqual(cleaned.dataSet.numberOfFrames, 3)
        // Byte-stable functional groups.
        let srcPerFrame = try XCTUnwrap(file.dataSet.sequence(for: .perFrameFunctionalGroupsSequence))
        for (a, b) in zip(srcPerFrame, perFrame) {
            XCTAssertEqual(a.allElements.map(\.tag), b.allElements.map(\.tag))
            XCTAssertEqual(a.allElements.map(\.valueData), b.allElements.map(\.valueData))
        }
        XCTAssertEqual(
            file.dataSet.sequence(for: .sharedFunctionalGroupsSequence)?.first?.allElements.map(\.valueData),
            cleaned.dataSet.sequence(for: .sharedFunctionalGroupsSequence)?.first?.allElements.map(\.valueData))
        // 16-bit samples inside the region are the fill on every frame; outside untouched.
        let px = try XCTUnwrap(cleaned.dataSet[.pixelData]?.valueData)
        let frameBytes = 512 * 256 * 2
        for f in 0..<3 {
            let i = f * frameBytes + (30 * 512 + 40) * 2
            XCTAssertEqual(UInt16(px[i]) | UInt16(px[i + 1]) << 8, 0, "frame \(f) banner")
            let j = f * frameBytes + (200 * 512 + 40) * 2
            XCTAssertEqual(UInt16(px[j]) | UInt16(px[j + 1]) << 8, 1000, "frame \(f) anatomy")
        }
        // No detectable text remains, under any frame's window.
        let ocrLeftover1 = try await TextRegionDetector().detect(in: cleaned, allFrames: true)
        XCTAssertTrue(ocrLeftover1.isEmpty)
    }

    func testFunctionalGroupInvariantRefusesAMismatch() throws {
        let (data, _) = try enhancedMRFixture()
        var ds = try DICOMFile.read(from: data).dataSet
        var broken = ds
        // Simulate a rewrite that dropped a per-frame item.
        var items = try XCTUnwrap(ds.sequence(for: .perFrameFunctionalGroupsSequence))
        items.removeLast()
        broken.setSequence(items, for: .perFrameFunctionalGroupsSequence)
        XCTAssertThrowsError(try PixelRedactor.checkFunctionalGroupInvariant(source: ds, result: broken)) {
            guard case PixelRedactionError.functionalGroupMismatch(let frames, let n) = $0 else {
                return XCTFail("\($0)")
            }
            XCTAssertEqual(frames, 3); XCTAssertEqual(n, 2)
        }
        // And altered content (same count) is refused too.
        var altered = ds
        var items2 = try XCTUnwrap(ds.sequence(for: .perFrameFunctionalGroupsSequence))
        items2[0] = SequenceItem(elements: [seq(.frameContentSequence, [DataElement.uint32(tag: .inStackPositionNumber, value: 99)])])
        altered.setSequence(items2, for: .perFrameFunctionalGroupsSequence)
        XCTAssertThrowsError(try PixelRedactor.checkFunctionalGroupInvariant(source: ds, result: altered))
        // Untouched passes.
        XCTAssertNoThrow(try PixelRedactor.checkFunctionalGroupInvariant(source: ds, result: ds))
        _ = ds
    }

    /// Draws `text` at the top of an 8-bit grayscale frame and returns the DICOM bytes
    /// plus the rectangle the glyphs were drawn into (top-left pixel coordinates).
    private func fixture(
        text: String, columns: Int = 512, rows: Int = 256, frames: Int = 1,
        textOrigin: (x: Int, y: Int) = (24, 20), fontSize: CGFloat = 28
    ) throws -> (data: Data, drawn: Region) {
        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: columns, height: rows, bitsPerComponent: 8,
            bytesPerRow: columns, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { throw XCTSkip("no bitmap context") }
        ctx.setFillColor(gray: 0.2, alpha: 1)      // dark background like an US frame
        ctx.fill(CGRect(x: 0, y: 0, width: columns, height: rows))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: CGColor(gray: 1, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        // CG origin is bottom-left; place the glyph box at (textOrigin) from the top.
        let baselineY = CGFloat(rows) - CGFloat(textOrigin.y) - bounds.maxY
        ctx.textPosition = CGPoint(x: CGFloat(textOrigin.x), y: baselineY)
        CTLineDraw(line, ctx)

        guard let raw = ctx.data else { throw XCTSkip("no bitmap data") }
        let frame = Data(bytes: raw, count: columns * rows)
        var pixels = Data()
        for _ in 0..<frames { pixels += frame }

        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6", for: .sopInstanceUID, vr: .UI)
        ds.setString("OT", for: .modality, vr: .CS)
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(8, for: .bitsAllocated)
        ds.setUInt16(8, for: .bitsStored)
        ds.setUInt16(7, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        if frames > 1 { ds.setString("\(frames)", for: .numberOfFrames, vr: .IS) }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: pixels)

        var meta = DataSet()
        meta.setString("1.2.840.10008.1.2.1", for: Tag(group: 0x0002, element: 0x0010), vr: .UI)
        let data = try DICOMFile(fileMetaInformation: meta, dataSet: ds).write()

        let drawn = Region(
            x: textOrigin.x + Int(bounds.minX.rounded(.down)), y: textOrigin.y,
            width: Int(bounds.width.rounded(.up)) + 1, height: Int(bounds.height.rounded(.up)) + 1)
        return (data, drawn)
    }

    private func covers(_ outer: Region, _ inner: Region) -> Bool {
        outer.x <= inner.x && outer.y <= inner.y
            && outer.x + outer.width >= inner.x + inner.width
            && outer.y + outer.height >= inner.y + inner.height
    }

    func testVisionFindsPlantedTextAndTheRegionCoversTheGlyphsWithDilation() async throws {
        let (data, drawn) = try fixture(text: "SMITH JOHN 12/03/1961")
        let file = try DICOMFile.read(from: data)
        let detections = try await TextRegionDetector(dilation: 4).detect(in: file)
        XCTAssertFalse(detections.isEmpty, "Vision must detect the planted banner")

        // The union of detected regions must cover the drawn glyph box with the margin.
        let union = detections.map(\.region).reduce(into: (minX: Int.max, minY: Int.max, maxX: 0, maxY: 0)) {
            $0.minX = min($0.minX, $1.x); $0.minY = min($0.minY, $1.y)
            $0.maxX = max($0.maxX, $1.x + $1.width); $0.maxY = max($0.maxY, $1.y + $1.height)
        }
        let box = Region(x: union.minX, y: union.minY, width: union.maxX - union.minX, height: union.maxY - union.minY)
        XCTAssertTrue(covers(box, drawn), "detected \(box) must cover drawn \(drawn)")
        // Dilation: at least 4 px of margin on each side beyond the drawn box.
        XCTAssertLessThanOrEqual(box.x, drawn.x - 4)
        XCTAssertLessThanOrEqual(box.y, drawn.y - 4)
        XCTAssertGreaterThanOrEqual(box.x + box.width, drawn.x + drawn.width + 4)
        XCTAssertGreaterThanOrEqual(box.y + box.height, drawn.y + drawn.height + 4)
        // And it is still a banner, not the whole frame (the transform is not just "everything").
        XCTAssertLessThan(box.height, 256 / 2)
        XCTAssertTrue(detections.contains { $0.text.uppercased().contains("SMITH") }, "\(detections.map(\.text))")
    }

    func testDetectionsCarryTheFrameIndexOfTheSampledFrame() async throws {
        let (data, _) = try fixture(text: "ACC 00123456", frames: 5)
        let file = try DICOMFile.read(from: data)
        let detections = try await TextRegionDetector().detect(in: file)
        let frames = Set(detections.map(\.frameIndex))
        XCTAssertEqual(frames, [0, 2, 4], "first/middle/last of 5 frames")
        // The same banner on every frame collapses to one region set.
        let regions = TextRegionDetector.unionedRegions(detections)
        XCTAssertEqual(regions.count, Set(detections.filter { $0.frameIndex == 0 }.map(\.region)).count)
    }

    func testExplicitFrameIndicesAreHonouredAndOutOfRangeIgnored() async throws {
        let (data, _) = try fixture(text: "MRN 777", frames: 3)
        let file = try DICOMFile.read(from: data)
        let detections = try await TextRegionDetector().detect(in: file, frameIndices: [1, 9])
        XCTAssertEqual(Set(detections.map(\.frameIndex)), [1])
    }

    func testBlankFrameYieldsNoRegions() async throws {
        let (data, _) = try fixture(text: "")
        let file = try DICOMFile.read(from: data)
        let ocrLeftover2 = try await TextRegionDetector().detect(in: file)
        XCTAssertTrue(ocrLeftover2.isEmpty)
    }

    /// End-to-end: detect → plan → redact, then the redacted output has no detectable text.
    func testDetectPlanRedactRemovesTheTextFromEveryFrame() async throws {
        let (data, drawn) = try fixture(text: "DOE JANE", frames: 3)
        let file = try DICOMFile.read(from: data)
        let regions = TextRegionDetector.unionedRegions(try await TextRegionDetector().detect(in: file))
        XCTAssertFalse(regions.isEmpty)
        let plan = PixelRedactionPlan.plan(for: file.dataSet, detectedRegions: regions)
        let (out, outcome) = try XCTUnwrap(PixelRedactor().redact(fileData: data, plan: plan))
        XCTAssertEqual(outcome.basis, .textDetection)
        XCTAssertEqual(outcome.frameCount, 3)

        let cleaned = try DICOMFile.read(from: out)
        // Oracle 2: OCR of the output finds nothing.
        let after = try await TextRegionDetector().detect(in: cleaned, allFrames: true)
        XCTAssertTrue(after.isEmpty, "text survived: \(after.map(\.text))")
        // Oracle 1: drawn glyph pixels are the fill value on every frame.
        let pixels = try XCTUnwrap(cleaned.dataSet[.pixelData]?.valueData)
        let frameSize = 512 * 256
        for f in 0..<3 {
            let i = f * frameSize + (drawn.y + drawn.height / 2) * 512 + drawn.x + drawn.width / 2
            XCTAssertEqual(pixels[i], 0, "frame \(f) centre of the banner must be blank")
        }
        XCTAssertEqual(cleaned.dataSet.string(for: .burnedInAnnotation)?.trimmingCharacters(in: .whitespaces), "NO")
    }
    #else
    func testDetectionIsAHardErrorWithoutVision() throws {
        XCTAssertFalse(TextRegionDetector.isAvailable)
    }
    #endif
}
