import XCTest
import Foundation
import DICOMCore
@testable import DICOMKit

/// `XCTAssertThrowsError` for an `async` expression: its autoclosure cannot `await`,
/// so the call is made here and the error handed to `verify`.
func assertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath, line: UInt = #line,
    _ verify: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("expected an error, but the call succeeded", file: file, line: line)
    } catch {
        verify(error)
    }
}
#if canImport(CoreGraphics)
import CoreGraphics
import CoreText
#endif

/// Pins the option semantics of PIXEL_ANONYMIZATION_PIPELINE.md §2.1 as implemented by
/// ``PixelCleaningWorkflow`` — the contract `dicom-anon` runs, tested at the library so
/// the CLI stays a thin adapter.
final class PixelCleaningWorkflowTests: XCTestCase {

    typealias Region = PixelRedactionPlan.Region
    typealias Options = PixelCleaningWorkflow.Options

    // MARK: - Fixtures

    private func plainImage(rows: Int = 20, columns: Int = 10, frames: Int = 1, modality: String = "XA") throws -> Data {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        ds.setString(modality, for: .modality, vr: .CS)
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(8, for: .bitsAllocated)
        ds.setUInt16(8, for: .bitsStored)
        ds.setUInt16(7, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        if frames > 1 { ds.setString("\(frames)", for: .numberOfFrames, vr: .IS) }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB,
                                          data: Data(repeating: 200, count: rows * columns * frames))
        var meta = DataSet()
        meta.setString("1.2.840.10008.1.2.1", for: Tag(group: 0x0002, element: 0x0010), vr: .UI)
        return try DICOMFile(fileMetaInformation: meta, dataSet: ds).write()
    }

    // MARK: - Option semantics (no OCR needed)

    func testRedactRegionImpliesCleaning() {
        XCTAssertTrue(Options(explicitRegions: [Region(x: 0, y: 0, width: 1, height: 1)]).cleaningRequested)
        XCTAssertTrue(Options(cleanPixelData: true).cleaningRequested)
    }

    func testDetectTextDoesNotImplyCleaning() {
        let o = Options(detectText: .classify)
        XCTAssertFalse(o.cleaningRequested)
        XCTAssertTrue(o.isActive)
        XCTAssertFalse(Options().isActive)
    }

    func testModeParsing() {
        XCTAssertEqual(PixelCleaningWorkflow.TextDetectionMode.parse(nil), .classify)
        XCTAssertEqual(PixelCleaningWorkflow.TextDetectionMode.parse(""), .classify)
        XCTAssertEqual(PixelCleaningWorkflow.TextDetectionMode.parse("CLASSIFY"), .classify)
        XCTAssertEqual(PixelCleaningWorkflow.TextDetectionMode.parse(" header "), .header)
        XCTAssertNil(PixelCleaningWorkflow.TextDetectionMode.parse("fuzzy"))
        // `all` was removed: past the closed allowlist the remaining text is provably
        // clinical, so blanking it bought no privacy. --redact-region covers that intent.
        XCTAssertNil(PixelCleaningWorkflow.TextDetectionMode.parse("all"))
        // Subset order is the documented contract (header ⊆ classify).
        XCTAssertEqual(PixelCleaningWorkflow.TextDetectionMode.names, ["header", "classify"])
        XCTAssertFalse(PixelCleaningWorkflow.TextDetectionMode.header.blanksOutsideDeclaredRegions)
        XCTAssertTrue(PixelCleaningWorkflow.TextDetectionMode.classify.blanksOutsideDeclaredRegions)
        XCTAssertTrue(PixelCleaningWorkflow.TextDetectionMode.header.isFailOpen)
        XCTAssertFalse(PixelCleaningWorkflow.TextDetectionMode.classify.isFailOpen)
    }

    func testFillParsing() {
        typealias Fill = PixelCleaningWorkflow.RedactFill
        XCTAssertEqual(Fill.parse(nil), .black)
        XCTAssertEqual(Fill.parse(""), .black)
        XCTAssertEqual(Fill.parse("Black"), .black)
        XCTAssertEqual(Fill.parse(" white"), .white)
        XCTAssertEqual(Fill.parse("255"), .value(255))
        XCTAssertNil(Fill.parse("-1"))
        XCTAssertNil(Fill.parse("grey"))
        for f in [Fill.black, .white, .value(4095)] { XCTAssertEqual(Fill.parse(f.flagValue), f) }

        var ds = DataSet()
        ds.setUInt16(8, for: .bitsAllocated); ds.setUInt16(8, for: .bitsStored); ds.setUInt16(0, for: .pixelRepresentation)
        XCTAssertEqual(Fill.white.resolve(for: ds), 255)
        XCTAssertEqual(Fill.black.resolve(for: ds), 0)
        ds.setUInt16(16, for: .bitsAllocated); ds.setUInt16(12, for: .bitsStored)
        XCTAssertEqual(Fill.white.resolve(for: ds), 4095)
        ds.setUInt16(1, for: .pixelRepresentation)
        XCTAssertEqual(Fill.white.resolve(for: ds), 2047, "signed: largest positive stored value")
    }

    func testRetainedDetectedTextIsNeverAttestedAsIdentityRemoved() throws {
        var ds = try DICOMFile.read(from: plainImage()).dataSet
        ds.setString("YES", for: Tag(group: 0x0012, element: 0x0062), vr: .CS)
        PixelCleaningWorkflow.markDetectedTextRetained(in: &ds)
        XCTAssertEqual(ds.string(for: Tag(group: 0x0012, element: 0x0062))?.trimmingCharacters(in: .whitespaces), "NO")
        XCTAssertEqual(ds.string(for: .burnedInAnnotation)?.trimmingCharacters(in: .whitespaces), "YES")
    }

    func testNoPixelOptionsPassesBytesThroughUntouched() async throws {
        let data = try plainImage()
        let report = try await PixelCleaningWorkflow().run(fileData: data, options: Options(), dryRun: false)
        XCTAssertNil(report.plan)
        XCTAssertNil(report.outcome)
        XCTAssertEqual(report.data, data)
        XCTAssertTrue(report.residualWarnings.isEmpty)
    }

    func testExplicitRegionRedactsAndReportsOutcome() async throws {
        let data = try plainImage(frames: 3)
        let report = try await PixelCleaningWorkflow().run(
            fileData: data,
            options: Options(explicitRegions: [Region(x: 0, y: 0, width: 10, height: 2)]),
            dryRun: false)
        let outcome = try XCTUnwrap(report.outcome)
        XCTAssertEqual(outcome.basis, .explicit)
        XCTAssertEqual(outcome.frameCount, 3)
        XCTAssertNotEqual(report.data, data)
        let cleaned = try DICOMFile.read(from: report.data)
        XCTAssertEqual(cleaned.dataSet.string(for: .burnedInAnnotation)?.trimmingCharacters(in: .whitespaces), "NO")
    }

    func testDryRunBuildsThePlanButNeverModifies() async throws {
        let data = try plainImage()
        let report = try await PixelCleaningWorkflow().run(
            fileData: data,
            options: Options(explicitRegions: [Region(x: 0, y: 0, width: 10, height: 2)]),
            dryRun: true)
        XCTAssertNotNil(report.plan)
        XCTAssertNil(report.outcome, "a dry run must not blank anything")
        XCTAssertEqual(report.data, data, "a dry run must hand the input through unchanged")
        let table = AnonConsole.pixelPlanTable(report: report, showText: true)
        XCTAssertTrue(table.contains("1 explicit region = 1 unioned region"), table)
        XCTAssertTrue(table.contains("Pixel modification: YES"), table)
        XCTAssertTrue(table.contains("Frames affected: all (1)"), table)
    }

    func testDryRunStillSurfacesAnUnresolvedRefusal() async throws {
        var ds = try DICOMFile.read(from: plainImage()).dataSet
        ds.setString("YES", for: .burnedInAnnotation, vr: .CS)
        var meta = DataSet()
        meta.setString("1.2.840.10008.1.2.1", for: Tag(group: 0x0002, element: 0x0010), vr: .UI)
        let data = try DICOMFile(fileMetaInformation: meta, dataSet: ds).write()
        await assertThrowsErrorAsync(try await PixelCleaningWorkflow().run(
            fileData: data, options: Options(cleanPixelData: true), dryRun: true)) { error in
            guard case PixelRedactionError.unresolvedRegion = error else {
                return XCTFail("expected unresolvedRegion, got \(error)")
            }
        }
    }

    func testCleanWithNothingDeclaredIsAPassThroughWithoutAttestation() async throws {
        let data = try plainImage()
        let report = try await PixelCleaningWorkflow().run(
            fileData: data, options: Options(cleanPixelData: true), dryRun: false)
        guard case .nothingToDo = try XCTUnwrap(report.plan).decision else {
            return XCTFail("expected nothingToDo")
        }
        XCTAssertNil(report.outcome)
        XCTAssertEqual(report.data, data)
        let table = AnonConsole.pixelPlanTable(report: report, showText: true)
        XCTAssertTrue(table.contains("Pixel modification: NO"), table)
    }

    // MARK: - OCR-driven semantics (Apple platforms)

    #if canImport(Vision) && canImport(CoreGraphics)
    /// 8-bit frame with a white banner drawn at the top.
    private func bannerImage(text: String, frames: Int = 1, columns: Int = 512, rows: Int = 256) throws -> Data {
        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: columns, height: rows, bitsPerComponent: 8,
            bytesPerRow: columns, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { throw XCTSkip("no bitmap context") }
        ctx.setFillColor(gray: 0.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: columns, height: rows))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 28, nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(gray: 1, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        ctx.textPosition = CGPoint(x: 24, y: CGFloat(rows) - 50)
        CTLineDraw(line, ctx)
        guard let raw = ctx.data else { throw XCTSkip("no bitmap data") }
        let frame = Data(bytes: raw, count: columns * rows)
        var pixels = Data()
        for _ in 0..<frames { pixels += frame }

        var ds = try DICOMFile.read(from: plainImage(rows: rows, columns: columns, frames: frames, modality: "OT")).dataSet
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: pixels)
        var meta = DataSet()
        meta.setString("1.2.840.10008.1.2.1", for: Tag(group: 0x0002, element: 0x0010), vr: .UI)
        return try DICOMFile(fileMetaInformation: meta, dataSet: ds).write()
    }

    /// Two text lines on one frame, with a header naming SMITH^JOHN / 0012345.
    private func twoLineImage(top: String, bottom: String, columns: Int = 512, rows: Int = 256) throws -> Data {
        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: columns, height: rows, bitsPerComponent: 8,
            bytesPerRow: columns, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { throw XCTSkip("no bitmap context") }
        ctx.setFillColor(gray: 0.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: columns, height: rows))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 28, nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(gray: 1, alpha: 1)]
        for (text, y) in [(top, CGFloat(rows) - 50), (bottom, CGFloat(40))] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
            ctx.textPosition = CGPoint(x: 24, y: y)
            CTLineDraw(line, ctx)
        }
        guard let raw = ctx.data else { throw XCTSkip("no bitmap data") }
        var ds = try DICOMFile.read(from: plainImage(rows: rows, columns: columns, modality: "OT")).dataSet
        ds.setString("SMITH^JOHN", for: .patientName, vr: .PN)
        ds.setString("0012345", for: .patientID, vr: .LO)
        ds.setString("19611203", for: .patientBirthDate, vr: .DA)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: Data(bytes: raw, count: columns * rows))
        var meta = DataSet()
        meta.setString("1.2.840.10008.1.2.1", for: Tag(group: 0x0002, element: 0x0010), vr: .UI)
        return try DICOMFile(fileMetaInformation: meta, dataSet: ds).write()
    }

    /// `--detect-text` alone: report, modify nothing, and flag the leftover text so the
    /// caller refuses to write.
    func testDetectionOnlyReportsAndFlagsUnredactedText() async throws {
        let data = try bannerImage(text: "SMITH JOHN")
        let report = try await PixelCleaningWorkflow().run(
            fileData: data, options: Options(detectText: .classify), dryRun: false)
        XCTAssertFalse(report.detections.isEmpty)
        XCTAssertNil(report.plan)
        XCTAssertNil(report.outcome)
        XCTAssertEqual(report.data, data, "detection must never modify pixels")
        XCTAssertEqual(report.detectedButUnredacted.count, report.detections.count)
        XCTAssertEqual(report.residualWarnings.count, 1)
        XCTAssertTrue(report.residualWarnings[0].contains("will not be redacted"), report.residualWarnings[0])

        let line = AnonConsole.textDetectionLine(report: report)
        XCTAssertTrue(line.hasPrefix("OCR: "), line)
        XCTAssertTrue(line.contains("0 selected for redaction across 1 sampled frame."), line)
        XCTAssertFalse(line.lowercased().contains("clean"), "must not claim cleanliness")

        let table = AnonConsole.pixelPlanTable(report: report, showText: false)
        XCTAssertTrue(table.contains("verdict=detected"), table)
        XCTAssertFalse(table.contains("SMITH"), "audit-safe table must not carry the string")
        XCTAssertTrue(table.contains("Pixel modification: NO"), table)
    }

    /// `--clean-pixel-data --detect-text`: every detected region is blanked (interim
    /// `all` semantics) on every frame and nothing is left flagged.
    func testCleanWithDetectionRedactsEverythingDetectedOnEveryFrame() async throws {
        let data = try bannerImage(text: "DOE JANE 1961", frames: 4)
        let report = try await PixelCleaningWorkflow().run(
            fileData: data, options: Options(cleanPixelData: true, detectText: .classify), dryRun: false)
        XCTAssertFalse(report.detections.isEmpty)
        XCTAssertEqual(report.scannedFrames, [0, 1, 3])
        let outcome = try XCTUnwrap(report.outcome)
        XCTAssertEqual(outcome.basis, .textDetection)
        XCTAssertEqual(outcome.frameCount, 4)
        XCTAssertTrue(report.detectedButUnredacted.isEmpty)
        XCTAssertTrue(report.residualWarnings.isEmpty)

        let line = AnonConsole.textDetectionLine(report: report)
        XCTAssertTrue(line.contains("\(report.detections.count) selected for redaction across 3 sampled frames."), line)

        // Oracle: OCR of the output finds nothing on any frame.
        let cleaned = try DICOMFile.read(from: report.data)
        let ocrLeftover3 = try await TextRegionDetector().detect(in: cleaned, allFrames: true)
        XCTAssertTrue(ocrLeftover3.isEmpty)
    }

    /// `--text-only` blanks the flagged text and nothing else, says so on every run,
    /// and refuses with a text-only reason when OCR flagged nothing on a declared
    /// burned-in image. Requires OCR (pinned in the workflow resolve tests).
    func testTextOnlyBlanksOnlyTheFlaggedTextAndSaysSo() async throws {
        let data = try bannerImage(text: "DOE JANE 1961", frames: 1)
        let report = try await PixelCleaningWorkflow().run(
            fileData: data, options: Options(cleanPixelData: true, detectText: .classify, textOnly: true), dryRun: false)
        let plan = try XCTUnwrap(report.plan)
        XCTAssertEqual(plan.sources.map(\.basis), [.textDetection], "no derived band may contribute")
        let outcome = try XCTUnwrap(report.outcome)
        XCTAssertEqual(outcome.basis, .textDetection)
        XCTAssertEqual(Set(outcome.regions), Set(report.detections.map(\.region)))
        XCTAssertTrue(report.warnings.contains { $0.hasPrefix("Text-only:") && $0.contains("Verify visually") },
                      "\(report.warnings)")

        // The same file with OCR that flags nothing: the band was the safety net, and it
        // is gone — an honest text-only refusal, not a silent pass.
        var ds = try DICOMFile.read(from: plainImage()).dataSet
        ds.setString("YES", for: .burnedInAnnotation, vr: .CS)
        var meta = DataSet()
        meta.setString("1.2.840.10008.1.2.1", for: Tag(group: 0x0002, element: 0x0010), vr: .UI)
        let declared = try DICOMFile(fileMetaInformation: meta, dataSet: ds).write()
        await assertThrowsErrorAsync(try await PixelCleaningWorkflow().run(
            fileData: declared, options: Options(cleanPixelData: true, detectText: .classify, textOnly: true), dryRun: true)) {
            guard case PixelRedactionError.unresolvedRegion(let reason) = $0 else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.hasPrefix("--text-only: OCR flagged no text to redact"), reason)
        }
    }

    /// Classify keeps allowlisted clinical text and redacts PHI; `all` blanks both.
    func testClassifyKeepsLateralityWhileRedactingTheBanner() async throws {
        // Two lines: a PHI banner at the top and a laterality/scale label lower down.
        let data = try twoLineImage(top: "SMITH JOHN 0012345", bottom: "R 10 cm")
        let c = try await PixelCleaningWorkflow().run(
            fileData: data, options: Options(cleanPixelData: true, detectText: .classify), dryRun: false)
        XCTAssertEqual(c.detections.count, 2, "\(c.detections.map(\.text))")
        XCTAssertEqual(c.verdicts.filter(\.isRedact).count, 1, "\(zip(c.detections, c.verdicts).map { ($0.text, $1) })")
        XCTAssertEqual(c.outcome?.regions.count, 1)
        XCTAssertTrue(c.detectedButUnredacted.isEmpty, "a kept region is not a leftover")
        XCTAssertTrue(c.residualWarnings.isEmpty)
        let line = AnonConsole.textDetectionLine(report: c)
        XCTAssertTrue(line.contains("1 selected for redaction; 1 kept"), line)
        let after = try await TextRegionDetector().detect(in: DICOMFile.read(from: c.data)).map { $0.text.uppercased() }
        XCTAssertFalse(after.contains { $0.contains("SMITH") }, "\(after)")
        XCTAssertTrue(after.contains { $0.contains("CM") }, "clinical label must survive: \(after)")

        // Dry-run table shows both verdicts; audit lines never carry the string.
        let table = AnonConsole.pixelPlanTable(report: c, showText: true)
        XCTAssertTrue(table.contains("verdict=keep"), table)
        XCTAssertTrue(table.contains("verdict=redact"), table)
        XCTAssertEqual(c.auditLines.first, "OCR mode=classify", "the mode is part of the audit trail")
        for l in c.auditLines.dropFirst() {
            XCTAssertFalse(l.contains("SMITH"), l)
            XCTAssertTrue(l.contains("verdict="), l)
        }
    }

    /// Classify harvests the ORIGINAL header: a name that is only PHI because the header
    /// says so is redacted; the same word with a different header is uncertain → still redacted.
    func testClassifyUsesTheFilesOwnHeaderTerms() async throws {
        let data = try twoLineImage(top: "Patient SMITH", bottom: "R")
        let report = try await PixelCleaningWorkflow().run(
            fileData: data, options: Options(detectText: .classify), dryRun: false)
        let byText = Dictionary(uniqueKeysWithValues: zip(report.detections.map { $0.text.uppercased() }, report.verdicts))
        XCTAssertTrue(byText.first { $0.key.contains("SMITH") }?.value.isRedact ?? false)
        XCTAssertTrue(byText.first { $0.key.contains("SMITH") }?.value.reason.contains("identifier") ?? false, "\(byText)")
        XCTAssertFalse(byText["R"]?.isRedact ?? true, "\(byText)")
    }

    func testOcrAllFramesScansEveryFrame() async throws {
        let data = try bannerImage(text: "MRN 9", frames: 4)
        let report = try await PixelCleaningWorkflow().run(
            fileData: data, options: Options(detectText: .classify, ocrAllFrames: true), dryRun: false)
        XCTAssertEqual(report.scannedFrames, [0, 1, 2, 3])
    }

    func testDryRunWithDetectionPrintsTheTableAndWritesNothing() async throws {
        let data = try bannerImage(text: "SMITH JOHN")
        let report = try await PixelCleaningWorkflow().run(
            fileData: data,
            options: Options(cleanPixelData: true, explicitRegions: [Region(x: 0, y: 250, width: 512, height: 6)],
                             detectText: .classify),
            dryRun: true)
        XCTAssertNil(report.outcome)
        XCTAssertEqual(report.data, data)
        let table = AnonConsole.pixelPlanTable(report: report, showText: true)
        XCTAssertTrue(table.contains("Frame 0:"), table)
        XCTAssertTrue(table.contains("verdict=redact"), table)
        XCTAssertTrue(table.contains("1 explicit region + "), table)
        XCTAssertTrue(table.contains("OCR region"), table)
        XCTAssertTrue(table.contains("Pixel modification: YES"), table)
    }

    /// `label` style end-to-end: OCR of the output finds the stamp and none of the
    /// original strings — the original is 100% gone regardless of style.
    func testLabelStyleOutputReadsAsTheStampAndNeverTheOriginal() async throws {
        let data = try bannerImage(text: "SMITH JOHN 0012345")
        let report = try await PixelCleaningWorkflow().run(
            fileData: data,
            options: Options(cleanPixelData: true, detectText: .classify, style: .label("REDACTED")),
            dryRun: false)
        let outcome = try XCTUnwrap(report.outcome)
        XCTAssertEqual(outcome.style, .label("REDACTED"))
        let cleaned = try DICOMFile.read(from: report.data)
        let after = try await TextRegionDetector().detect(in: cleaned)
        let texts = after.map { $0.text.uppercased() }
        XCTAssertTrue(texts.contains { $0.contains("REDACTED") }, "stamp should be legible: \(texts)")
        XCTAssertFalse(texts.contains { $0.contains("SMITH") || $0.contains("0012345") }, "\(texts)")
    }

    // MARK: Phase 5 — --recompress

    private func tsUID(_ data: Data) throws -> String {
        try DICOMFile.read(from: data).transferSyntaxUID?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
    }

    func testRecompressParsing() {
        XCTAssertEqual(PixelCleaningWorkflow.Recompress.parse("source"), .source)
        XCTAssertEqual(PixelCleaningWorkflow.Recompress.parse("JPEG-LS"), .codec("jpeg-ls"))
        XCTAssertNil(PixelCleaningWorkflow.Recompress.parse("h264"))
        XCTAssertNil(PixelCleaningWorkflow.Recompress.parse(""))
    }

    /// `--recompress source` on a lossless source: same UID out, redacted rects still
    /// blank after the codec round-trip, pixels outside byte-identical to the clean
    /// uncompressed output, attestation intact.
    func testRecompressSourceMirrorsALosslessSourceExactly() async throws {
        let native = try bannerImage(text: "SMITH JOHN", frames: 3)
        let rle = try CompressionManager().compressData(native, codec: "rle", quality: nil)
        XCTAssertEqual(try tsUID(rle), TransferSyntax.rleLossless.uid)

        let plain = try await PixelCleaningWorkflow().run(
            fileData: rle, options: Options(cleanPixelData: true, detectText: .classify), dryRun: false)
        let parity = try await PixelCleaningWorkflow().run(
            fileData: rle, options: Options(cleanPixelData: true, detectText: .classify, recompress: .source), dryRun: false)
        let r = try XCTUnwrap(parity.recompression)
        XCTAssertEqual(r.codec, "rle")
        XCTAssertFalse(r.lossy)
        XCTAssertTrue(r.notes.isEmpty, "\(r.notes)")
        XCTAssertEqual(try tsUID(parity.data), TransferSyntax.rleLossless.uid, "output syntax equals the source's")
        XCTAssertEqual(try tsUID(plain.data), TransferSyntax.explicitVRLittleEndian.uid, "default stays Explicit VR LE")

        // Decode both and compare: identical pixels (lossless), so the rects are blank
        // and anatomy untouched — byte-different bitstream, identical image.
        let (decodedParity, _) = try PixelEditor(verbose: false).processData(parity.data, operations: [])
        XCTAssertEqual(try DICOMFile.read(from: decodedParity).dataSet[.pixelData]?.valueData,
                       try DICOMFile.read(from: plain.data).dataSet[.pixelData]?.valueData)
        XCTAssertNotEqual(parity.data, plain.data)
        let out = try DICOMFile.read(from: parity.data)
        XCTAssertEqual(out.dataSet.string(for: .burnedInAnnotation)?.trimmingCharacters(in: .whitespaces), "NO")
        let ocrLeftover5 = try await TextRegionDetector().detect(in: out, allFrames: true)
        XCTAssertTrue(ocrLeftover5.isEmpty)
        XCTAssertTrue(parity.auditLines.last?.contains("re-encoded to \(TransferSyntax.rleLossless.uid)") ?? false, "\(parity.auditLines)")
        XCTAssertTrue(AnonConsole.recompressionLines(r).hasPrefix("Re-encoded to source syntax"), AnonConsole.recompressionLines(r))
    }

    /// A named lossy codec: warns about second-generation loss, updates the lossy
    /// attributes for the new generation, and the rects survive as flat black.
    func testRecompressLossyCodecWarnsAndKeepsRectsBlank() async throws {
        let native = try bannerImage(text: "DOE JANE 0012345", frames: 2)
        let report = try await PixelCleaningWorkflow().run(
            fileData: native,
            options: Options(cleanPixelData: true, detectText: .classify, recompress: .codec("jpeg-baseline")), dryRun: false)
        let r = try XCTUnwrap(report.recompression)
        XCTAssertTrue(r.lossy)
        XCTAssertEqual(try tsUID(report.data), TransferSyntax.jpegBaseline.uid)
        XCTAssertTrue(r.notes.contains { $0.contains("second-generation") }, "\(r.notes)")
        let ds = try DICOMFile.read(from: report.data).dataSet
        XCTAssertEqual(ds.string(for: .lossyImageCompression)?.trimmingCharacters(in: .whitespaces), "01")
        XCTAssertEqual(ds.strings(for: .lossyImageCompressionMethod)?.count, 1)
        XCTAssertEqual(ds.strings(for: .lossyImageCompressionRatio)?.count, 1)
        XCTAssertEqual(ds.string(for: .burnedInAnnotation)?.trimmingCharacters(in: .whitespaces), "NO")
        let ocrLeftover6 = try await TextRegionDetector().detect(in: DICOMFile.read(from: report.data), allFrames: true)
        XCTAssertTrue(ocrLeftover6.isEmpty)
        // The console line carries the warning.
        XCTAssertTrue(AnonConsole.recompressionLines(r).contains("⚠️"), AnonConsole.recompressionLines(r))
    }

    /// `source` on a lossy JPEG source re-targets the same syntax with a lossy warning
    /// and appends a second generation to the lossy history.
    func testRecompressSourceOnALossySourceIsSecondGeneration() async throws {
        let native = try bannerImage(text: "SMITH JOHN")
        let jpeg = try CompressionManager().compressData(native, codec: "jpeg-baseline", quality: nil)
        XCTAssertEqual(try DICOMFile.read(from: jpeg).dataSet.strings(for: .lossyImageCompressionMethod)?.count, 1)
        let report = try await PixelCleaningWorkflow().run(
            fileData: jpeg, options: Options(cleanPixelData: true, detectText: .classify, recompress: .source), dryRun: false)
        let r = try XCTUnwrap(report.recompression)
        XCTAssertEqual(r.codec, "jpeg", "the codec map's canonical name for JPEG baseline")
        XCTAssertTrue(r.lossy)
        XCTAssertEqual(try tsUID(report.data), TransferSyntax.jpegBaseline.uid)
        XCTAssertEqual(try DICOMFile.read(from: report.data).dataSet.strings(for: .lossyImageCompressionMethod)?.count, 2,
                       "a second generation is recorded, the header stays honest")
    }

    /// Uncompressed sources: `source` keeps them uncompressed (implicit stays implicit).
    func testRecompressSourceOnUncompressedSourcesIsParity() async throws {
        let native = try bannerImage(text: "SMITH JOHN")
        let implicit = try CompressionManager().compressData(native, codec: "implicit-le", quality: nil)
        let report = try await PixelCleaningWorkflow().run(
            fileData: implicit, options: Options(cleanPixelData: true, detectText: .classify, recompress: .source), dryRun: false)
        XCTAssertEqual(try tsUID(report.data), TransferSyntax.implicitVRLittleEndian.uid)
        XCTAssertEqual(report.recompression?.codec, "implicit-le")
        let deflated = try CompressionManager().compressData(native, codec: "deflate", quality: nil)
        let d = try await PixelCleaningWorkflow().run(
            fileData: deflated, options: Options(cleanPixelData: true, detectText: .classify, recompress: .source), dryRun: false)
        XCTAssertEqual(try tsUID(d.data), TransferSyntax.deflatedExplicitVRLittleEndian.uid)
        let ocrLeftover7 = try await TextRegionDetector().detect(in: DICOMFile.read(from: d.data))
        XCTAssertTrue(ocrLeftover7.isEmpty)
    }

    /// A source syntax the toolkit cannot encode falls back to Explicit VR LE with a
    /// note — never a silent substitution, never a refusal to redact.
    func testRecompressSourceFallsBackForNonEncodableSyntax() throws {
        var ds = DataSet()   // any data set; only the resolver is under test here
        let (codec, notes) = PixelCleaningWorkflow.resolveRecompressCodec(
            .source, sourceTransferSyntaxUID: "1.2.840.10008.1.2.4.102", sourceDataSet: ds)   // MPEG-4
        XCTAssertEqual(codec, "explicit-le")
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].contains("cannot be re-encoded"), notes[0])
        // Intent follows the source's declared lossy state for the general J2K UID.
        ds.setString("01", for: .lossyImageCompression, vr: .CS)
        XCTAssertEqual(PixelCleaningWorkflow.resolveRecompressCodec(.source, sourceTransferSyntaxUID: TransferSyntax.jpeg2000.uid, sourceDataSet: ds).codec, "jpeg2000")
        ds.setString("00", for: .lossyImageCompression, vr: .CS)
        XCTAssertEqual(PixelCleaningWorkflow.resolveRecompressCodec(.source, sourceTransferSyntaxUID: TransferSyntax.jpeg2000.uid, sourceDataSet: ds).codec, "jpeg2000-lossless")
    }

    /// The post-recompress oracle refuses when a rect is not flat fill any more.
    func testRecompressVerificationRefusesANonBlankRect() throws {
        let native = try bannerImage(text: "SMITH JOHN")   // untouched: banner still there
        XCTAssertThrowsError(try PixelCleaningWorkflow.verifyBlankAfterRecompression(
            native, regions: [Region(x: 0, y: 0, width: 512, height: 60)], fillValue: 0, lossy: false)) { error in
            guard case PixelRedactionError.recompressVerificationFailed = error else { return XCTFail("\(error)") }
        }
        XCTAssertNoThrow(try PixelCleaningWorkflow.verifyBlankAfterRecompression(
            native, regions: [Region(x: 0, y: 200, width: 10, height: 10)], fillValue: 51, lossy: false),
            "a region that is already the fill passes")
    }

    // MARK: Phase 4 — replace style

    /// Pixels and header tell ONE story: a burned date is replaced with the header
    /// engine's own shifted value for the same file (Modified Dates). Name and ID are
    /// zeroed by the Basic Profile, so they honestly have no replacement.
    func testReplaceStyleUsesTheHeaderEnginesOwnValues() async throws {
        let data = try twoLineImage(top: "DOB 12/03/1961", bottom: "R 10 cm")
        let file = try DICOMFile.read(from: data)
        // Main clears DOB even when longitudinal dates are shifted.
        let header = Anonymizer(options: .init(retainLongitudinalTemporal: true, dateOffsetDays: 30))
            .preview(file: file).dataSet
        let mapping = PixelCleaningWorkflow.ReplacementMapping.derive(original: file.dataSet, deidentified: header)
        XCTAssertNil(mapping.values[.patientName], "PS3.15 Basic zeroes the name: nothing truthful to draw")
        XCTAssertNil(mapping.values[.patientID])
        XCTAssertNil(mapping.values[.patientBirthDate], "A cleared birth date must never be restored into pixels")

        let report = try await PixelCleaningWorkflow().run(
            fileData: data,
            options: Options(cleanPixelData: true, detectText: .classify,
                             style: .replace(fallback: "REDACTED"), replacementMapping: mapping),
            dryRun: false)
        let outcome = try XCTUnwrap(report.outcome)
        XCTAssertEqual(outcome.regions.count, 1, "the clinical label is kept, not replaced")
        XCTAssertTrue(outcome.replacements.isEmpty)
        XCTAssertFalse(outcome.replacementFallbackNotes.isEmpty)

        // Detection oracle: the output reads as the replacement and never the original.
        let after = try await TextRegionDetector().detect(in: DICOMFile.read(from: report.data)).map { $0.text.uppercased() }
        XCTAssertFalse(after.contains { $0.contains("1962") }, "\(after)")
        XCTAssertFalse(after.contains { $0.contains("1961") }, "\(after)")
        XCTAssertTrue(after.contains { $0.contains("CM") }, "\(after)")
    }

    /// If the header policy removes dates (no --shift-dates), a burned date is blanked/
    /// labelled — pixels never retain what the header dropped. Uncertain text is never
    /// replaced.
    func testReplaceFallsBackWhenTheHeaderRemovesTheAttributeOrTheTextIsUncertain() async throws {
        let data = try twoLineImage(top: "DOB 12/03/1961", bottom: "Zebra 77")
        let file = try DICOMFile.read(from: data)
        // No --shift-dates: the Basic Profile zeroes dates.
        let header = Anonymizer().preview(file: file).dataSet
        let mapping = PixelCleaningWorkflow.ReplacementMapping.derive(original: file.dataSet, deidentified: header)
        XCTAssertNil(mapping.values[.patientBirthDate], "a zeroed date has no truthful replacement")
        XCTAssertNil(mapping.values[.patientName])

        let report = try await PixelCleaningWorkflow().run(
            fileData: data,
            options: Options(cleanPixelData: true, detectText: .classify,
                             style: .replace(fallback: "REDACTED"), replacementMapping: mapping),
            dryRun: false)
        let outcome = try XCTUnwrap(report.outcome)
        XCTAssertEqual(outcome.regions.count, 2)
        XCTAssertTrue(outcome.replacements.isEmpty, "nothing truthful to draw: \(outcome.replacements)")
        XCTAssertEqual(outcome.replacementFallbackNotes.count, 2)
        let notes = outcome.replacementFallbackNotes.values.joined(separator: " | ")
        XCTAssertTrue(notes.contains("header policy removed"), notes)
        XCTAssertTrue(notes.contains("uncertain"), notes)
        let after = try await TextRegionDetector().detect(in: DICOMFile.read(from: report.data)).map { $0.text.uppercased() }
        XCTAssertFalse(after.contains { $0.contains("1961") || $0.contains("ZEBRA") }, "\(after)")
        XCTAssertTrue(after.allSatisfy { $0.contains("REDACTED") }, "\(after)")
        for l in report.auditLines { XCTAssertFalse(l.contains("1961"), l) }
    }

    // MARK: Phase 4 — concatenations

    private func concatenationPart(text: String, uid: String, number: Int, total: Int) throws -> Data {
        let data = try bannerImage(text: text, frames: 2)
        var ds = try DICOMFile.read(from: data).dataSet
        ds.setString(uid, for: .concatenationUID, vr: .UI)
        ds.setUInt16(UInt16(number), for: .inConcatenationNumber)
        ds.setUInt16(UInt16(total), for: .inConcatenationTotalNumber)
        var meta = DataSet()
        meta.setString("1.2.840.10008.1.2.1", for: Tag(group: 0x0002, element: 0x0010), vr: .UI)
        return try DICOMFile(fileMetaInformation: meta, dataSet: ds).write()
    }

    func testSinglePartWarnsThatCoverageIsIncompleteOnlyWhenOCRRuns() async throws {
        let part = try concatenationPart(text: "SMITH JOHN", uid: "1.2.3.9", number: 1, total: 2)
        let withOCR = try await PixelCleaningWorkflow().run(
            fileData: part, options: Options(cleanPixelData: true, detectText: .classify), dryRun: false)
        XCTAssertEqual(withOCR.warnings.count, 1)
        XCTAssertTrue(withOCR.warnings[0].contains("part 1 of 2") && withOCR.warnings[0].contains("analyzed alone"), withOCR.warnings[0])
        XCTAssertTrue(withOCR.residualWarnings.isEmpty, "a coverage note must never refuse")
        XCTAssertNotNil(withOCR.outcome, "cleaning still happens")

        let noOCR = try await PixelCleaningWorkflow().run(
            fileData: part, options: Options(explicitRegions: [Region(x: 0, y: 0, width: 512, height: 60)]), dryRun: false)
        XCTAssertTrue(noOCR.warnings.isEmpty, "no OCR claim, no OCR coverage caveat")

        let swept = try await PixelCleaningWorkflow().run(
            fileData: part, options: Options(cleanPixelData: true, detectText: .classify, concatenationAnalyzedCompletely: true), dryRun: false)
        XCTAssertTrue(swept.warnings.isEmpty)
    }

    /// Text found only in part 2 must be blanked in part 1 as well (§4.4).
    func testConcatenationSweepUnionsRegionsAcrossParts() async throws {
        let uid = "1.2.3.10"
        let part1 = try concatenationPart(text: "", uid: uid, number: 1, total: 2)          // clean-looking
        let part2 = try concatenationPart(text: "DOE JANE 0012345", uid: uid, number: 2, total: 2)
        let wf = PixelCleaningWorkflow()
        var sweep = PixelCleaningWorkflow.ConcatenationSweep()
        for data in [part1, part2] {
            let (info, regions) = try await wf.sweep(fileData: data, options: Options(detectText: .classify))
            sweep.add(try XCTUnwrap(info), regions: regions)
        }
        XCTAssertTrue(sweep.isComplete(uid))
        XCTAssertFalse(sweep.regions(for: uid).isEmpty)

        // Part 1 alone would be nothingToDo; with the sweep it gets part 2's regions.
        let alone = try await wf.run(fileData: part1, options: Options(cleanPixelData: true, detectText: .classify), dryRun: false)
        XCTAssertNil(alone.outcome)
        let options = Options(cleanPixelData: true, detectText: .classify,
                              presetDetectedRegions: sweep.regions(for: uid), concatenationAnalyzedCompletely: true)
        let r1 = try await wf.run(fileData: part1, options: options, dryRun: false)
        let o1 = try XCTUnwrap(r1.outcome)
        XCTAssertEqual(o1.basis, .textDetection)
        XCTAssertEqual(Set(o1.regions), Set(sweep.regions(for: uid)))
        XCTAssertEqual(o1.frameCount, 2)
        XCTAssertTrue(r1.warnings.isEmpty)
        let r2 = try await wf.run(fileData: part2, options: options, dryRun: false)
        XCTAssertEqual(Set(try XCTUnwrap(r2.outcome).regions), Set(sweep.regions(for: uid)))
        let ocrLeftover8 = try await TextRegionDetector().detect(in: DICOMFile.read(from: r2.data), allFrames: true)
        XCTAssertTrue(ocrLeftover8.isEmpty)
    }

    func testSweepCompletenessNeedsEveryDeclaredPart() {
        var sweep = PixelCleaningWorkflow.ConcatenationSweep()
        let a = PixelCleaningWorkflow.ConcatenationInfo(uid: "u", number: 1, total: 3)
        sweep.add(a, regions: [Region(x: 0, y: 0, width: 1, height: 1)])
        XCTAssertFalse(sweep.isComplete("u"))
        sweep.add(PixelCleaningWorkflow.ConcatenationInfo(uid: "u", number: 3, total: 3), regions: [])
        XCTAssertFalse(sweep.isComplete("u"), "part 2 missing")
        sweep.add(PixelCleaningWorkflow.ConcatenationInfo(uid: "u", number: 2, total: 3), regions: [Region(x: 0, y: 0, width: 1, height: 1)])
        XCTAssertTrue(sweep.isComplete("u"))
        XCTAssertEqual(sweep.regions(for: "u").count, 1, "duplicates collapse")
        XCTAssertFalse(sweep.isComplete("other"))
    }

    /// OCR and explicit rectangles union: the rectangle never suppresses detection.
    func testExplicitAndDetectedRegionsUnion() async throws {
        let data = try bannerImage(text: "SMITH JOHN")
        let rect = Region(x: 0, y: 250, width: 512, height: 6)
        let report = try await PixelCleaningWorkflow().run(
            fileData: data, options: Options(explicitRegions: [rect], detectText: .classify), dryRun: false)
        let outcome = try XCTUnwrap(report.outcome)
        XCTAssertEqual(outcome.basis, .explicit)
        XCTAssertTrue(outcome.regions.contains(rect))
        XCTAssertGreaterThan(outcome.regions.count, 1, "detected regions must be unioned onto the explicit rectangle")
        XCTAssertTrue(report.detectedButUnredacted.isEmpty)
    }
    #else
    func testDetectTextIsAHardErrorWithoutVision() throws {
        let data = try plainImage()
        await assertThrowsErrorAsync(try await PixelCleaningWorkflow().run(
            fileData: data, options: Options(detectText: .classify), dryRun: false)) { error in
            XCTAssertEqual(error as? TextDetectionError, .unavailable)
        }
    }
    #endif
}
