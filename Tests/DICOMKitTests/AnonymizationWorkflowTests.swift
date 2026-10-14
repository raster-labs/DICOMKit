//
// AnonymizationWorkflowTests.swift
// DICOMKitTests
//
// The shared `dicom-anon` run: the CLI and DICOMStudio's CLI Workshop both hand a
// `Request` to `AnonymizationWorkflow.run`. These tests pin the contract both
// surfaces rely on — input parsing and its messages, the output/recursive rules,
// the Burned In Annotation policy, the pixel-first refusal, and the console text —
// without either surface present.
//

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore

final class AnonymizationWorkflowTests: XCTestCase {

    private typealias Request = AnonymizationWorkflow.Request
    private typealias ValidationError = AnonymizationWorkflow.ValidationError

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnonymizationWorkflowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixtures

    /// 16×8 MONOCHROME2 8-bit image with PHI in the header. Every pixel is 200 so
    /// a blanked region is unmistakable. `burnedIn` is the literal (0028,0301) value
    /// (nil = attribute absent).
    private func phiFile(burnedIn: String? = nil, modality: String = "OT",
                         studyUID: String = "1.2.3.4.5.100", sopUID: String = "1.2.3.4.5.6.7.8.9") -> Data {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString(sopUID, for: .sopInstanceUID, vr: .UI)
        ds.setString(studyUID, for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.200", for: .seriesInstanceUID, vr: .UI)
        ds.setString(modality, for: .modality, vr: .CS)
        ds.setString("Smith^John", for: .patientName, vr: .PN)
        ds.setString("MRN-123", for: .patientID, vr: .LO)
        ds.setString("19800101", for: .patientBirthDate, vr: .DA)
        ds.setString("M", for: .patientSex, vr: .CS)
        ds.setString("20200101", for: .studyDate, vr: .DA)
        ds.setString("101500", for: .studyTime, vr: .TM)
        ds.setString("General Hospital", for: .institutionName, vr: .LO)
        if let burnedIn { ds.setString(burnedIn, for: .burnedInAnnotation, vr: .CS) }
        ds.setUInt16(8, for: .rows)
        ds.setUInt16(16, for: .columns)
        ds.setUInt16(8, for: .bitsAllocated)
        ds.setUInt16(8, for: .bitsStored)
        ds.setUInt16(7, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: Data(repeating: 200, count: 16 * 8))
        var meta = DataSet()
        meta.setString("1.2.840.10008.1.2.1", for: Tag(group: 0x0002, element: 0x0010), vr: .UI)
        return try! DICOMFile(fileMetaInformation: meta, dataSet: ds).write()
    }

    @discardableResult
    private func write(_ data: Data, _ relative: String) throws -> String {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url.path
    }

    private func path(_ relative: String) -> String { root.appendingPathComponent(relative).path }

    private func read(_ relative: String) throws -> DataSet {
        try DICOMFile.read(from: Data(contentsOf: URL(fileURLWithPath: path(relative)))).dataSet
    }

    private func run(_ r: Request, workflow: AnonymizationWorkflow = AnonymizationWorkflow()) async throws
        -> (console: String, outcome: AnonymizationWorkflow.Outcome) {
        var console = ""
        let outcome = try await workflow.run(r) { console += $0 }
        return (console, outcome)
    }

    private func assertValidationError(_ r: Request, _ expected: String,
                                       file: StaticString = #filePath, line: UInt = #line) async {
        await assertThrowsErrorAsync(try await run(r), file: file, line: line) { error in
            XCTAssertEqual((error as? ValidationError)?.message, expected, file: file, line: line)
        }
    }

    private func assertResolveError(_ r: Request, _ expected: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try AnonymizationWorkflow.resolve(r), file: file, line: line) { error in
            XCTAssertEqual((error as? ValidationError)?.message, expected, file: file, line: line)
        }
    }

    private static let identityRemoved = Tag(group: 0x0012, element: 0x0062)
    private static let method = Tag(group: 0x0012, element: 0x0063)

    // MARK: - Input parsing (messages are the CLI's)

    func testResolveDefaultsAreTheStrictProfileWithPixelCleaning() throws {
        let resolved = try AnonymizationWorkflow.resolve(Request(inputPath: "x"))
        XCTAssertEqual(resolved.options, .basic)
        XCTAssertTrue(resolved.pixelOptions.cleanPixelData)
        XCTAssertEqual(resolved.pixelOptions.detectText, .classify, "OCR is part of pixel cleaning")
        XCTAssertTrue(resolved.pixelOptions.explicitRegions.isEmpty)
    }

    func testResolveDatesAreTwoDistinctStandardOptions() throws {
        var r = Request(inputPath: "x"); r.retainDates = true
        var o = try AnonymizationWorkflow.resolve(r).options
        XCTAssertTrue(o.retainLongitudinalTemporal); XCTAssertNil(o.dateOffsetDays)
        XCTAssertEqual(o.methodCodes, [.basicProfile, .retainFullDates])

        r = Request(inputPath: "x"); r.shiftDates = 10
        o = try AnonymizationWorkflow.resolve(r).options
        XCTAssertTrue(o.retainLongitudinalTemporal); XCTAssertEqual(o.dateOffsetDays, 10)
        XCTAssertEqual(o.methodCodes, [.basicProfile, .retainModifiedDates])

        r.retainDates = true
        assertResolveError(r, "--retain-dates and --shift-dates are alternatives: --retain-dates keeps the original "
                           + "dates (Retain Longitudinal Temporal Information with Full Dates); --shift-dates N "
                           + "replaces them with shifted dates (… with Modified Dates).")
    }

    func testResolveRetentionOptionsMap() throws {
        var r = Request(inputPath: "x")
        r.retainCharacteristics = true; r.retainDevice = true; r.retainInstitution = true
        r.retainUids = true; r.cleanDescriptors = true
        let o = try AnonymizationWorkflow.resolve(r).options
        XCTAssertTrue(o.retainPatientCharacteristics && o.retainDeviceIdentity && o.retainInstitutionIdentity
                      && o.retainUIDs && o.cleanDescriptors)
        XCTAssertEqual(Set(o.methodCodes), Set([.basicProfile, .retainPatientCharacteristics, .retainDeviceIdentity,
                                       .retainInstitutionIdentity, .retainUIDs, .cleanDescriptors]))
    }

    func testResolvePixelFlagMessages() {
        var r = Request(inputPath: "x"); r.redactStyle = "stripe"
        assertResolveError(r, "Invalid --redact-style 'stripe'. Use 'blank', 'label' or 'replace'.")
        r = Request(inputPath: "x"); r.ocrMode = "fuzzy"
        assertResolveError(r, "Invalid --ocr-mode 'fuzzy'. Use 'header' or 'classify' (default).")
        r = Request(inputPath: "x"); r.ocrMode = "all"
        assertResolveError(r, "Invalid --ocr-mode 'all'. Use 'header' or 'classify' (default).")
        r = Request(inputPath: "x"); r.cleanPixelData = false; r.textOnly = true
        assertResolveError(r, "--text-only needs pixel cleaning; drop --no-clean-pixel-data.")
        r = Request(inputPath: "x"); r.cleanPixelData = false; r.recompress = "rle"
        assertResolveError(r, "--recompress only applies after pixel cleaning; drop --no-clean-pixel-data or add --redact-region.")
        r = Request(inputPath: "x"); r.recompress = "webp"
        assertResolveError(r, "Invalid --recompress 'webp'. Use 'source' or a dicom-compress codec name.")
        r = Request(inputPath: "x"); r.redactStyle = "replace"; r.cleanPixelData = false
        assertResolveError(r, "--redact-style replace needs pixel cleaning; drop --no-clean-pixel-data (replacement values come from classified matches).")
        r = Request(inputPath: "x"); r.redactRegion = ["1,2,3"]
        XCTAssertThrowsError(try AnonymizationWorkflow.resolve(r))
    }

    func testResolvePixelOptions() throws {
        var r = Request(inputPath: "x")
        r.redactRegion = ["0,0,16,2"]; r.redactFill = "7"; r.redactStyle = "label"; r.redactLabel = "X"
        r.ocrMode = "classify"; r.ocrAllFrames = true; r.recompress = "source"
        let p = try AnonymizationWorkflow.resolve(r).pixelOptions
        XCTAssertEqual(p.explicitRegions, [PixelRedactionPlan.Region(x: 0, y: 0, width: 16, height: 2)])
        XCTAssertEqual(p.fillValue, 7)
        XCTAssertEqual(p.style, .label("X"))
        XCTAssertEqual(p.detectText, .classify)
        XCTAssertTrue(p.ocrAllFrames)
        XCTAssertFalse(p.textOnly)
        XCTAssertEqual(p.recompress, .source)
        XCTAssertTrue(p.cleaningRequested)
        r.textOnly = true
        XCTAssertTrue(try AnonymizationWorkflow.resolve(r).pixelOptions.textOnly)
        r.textOnly = false
        r.ocrMode = "header"
        XCTAssertEqual(try AnonymizationWorkflow.resolve(r).pixelOptions.detectText, .header)

        // --no-clean-pixel-data: OCR off, but explicit rectangles still blank.
        r.cleanPixelData = false
        let off = try AnonymizationWorkflow.resolve(r).pixelOptions
        XCTAssertNil(off.detectText)
        XCTAssertFalse(off.cleanPixelData)
        XCTAssertTrue(off.cleaningRequested, "rectangles imply cleaning")

        // --redact-fill black|white|<n>
        r = Request(inputPath: "x"); r.redactFill = "white"
        var p2 = try AnonymizationWorkflow.resolve(r).pixelOptions
        XCTAssertTrue(p2.fillWhite); XCTAssertNil(p2.fillValue)
        r.redactFill = "black"
        p2 = try AnonymizationWorkflow.resolve(r).pixelOptions
        XCTAssertFalse(p2.fillWhite); XCTAssertNil(p2.fillValue)
        r.redactFill = "grey"
        assertResolveError(r, "Invalid --redact-fill 'grey'. Use 'black', 'white' or a non-negative stored pixel value.")
    }

    // MARK: - Run rules

    func testMissingInputIsFileNotFound() async {
        await assertValidationError(Request(inputPath: path("nope.dcm")), "File not found")
    }

    func testSingleFileNeedsOutputUnlessDryRun() async throws {
        let input = try write(phiFile(), "in.dcm")
        await assertValidationError(Request(inputPath: input),
                              "Anonymization requires --output (or use --dry-run to preview without writing)")
        var dry = Request(inputPath: input); dry.dryRun = true
        let (console, outcome) = try await run(dry)
        XCTAssertEqual(outcome.exitCode, 0)
        XCTAssertTrue(console.contains("(DRY RUN - no files modified)"), console)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["in.dcm"])
    }

    func testDirectoryRules() async throws {
        try write(phiFile(), "dir/a.dcm")
        await assertValidationError(Request(inputPath: path("dir")), "Directory anonymization requires --recursive flag")
        var r = Request(inputPath: path("dir")); r.recursive = true
        await assertValidationError(r, "Directory anonymization requires --output directory")
    }

    // MARK: - The profile, applied by default

    func testDefaultRunAppliesTheBasicProfileAndAttests() async throws {
        let input = try write(phiFile(), "in.dcm")
        var r = Request(inputPath: input); r.output = path("out.dcm"); r.verbose = true
        let (console, outcome) = try await run(r)
        XCTAssertEqual(outcome.exitCode, 0)
        XCTAssertEqual(outcome.results.count, 1)
        let out = try read("out.dcm")
        XCTAssertEqual(out.string(for: .patientName), "", "Z: present but empty, not deleted")
        XCTAssertEqual(out.string(for: .patientID), "")
        XCTAssertEqual(out.string(for: .patientBirthDate), "")
        XCTAssertNil(out[.institutionName], "X: removed")
        XCTAssertEqual(out.string(for: .studyDate), "", "dates zeroed without a retention option")
        XCTAssertNotEqual(out.string(for: .studyInstanceUID), "1.2.3.4.5.100", "UIDs regenerated")
        XCTAssertEqual(out.string(for: Self.identityRemoved), "YES")
        XCTAssertTrue(ConfidentialityProfile.MethodCode.recorded(in: out).contains("113100"))
        XCTAssertFalse(ConfidentialityProfile.MethodCode.recorded(in: out).contains("113101"),
                       "nothing was blanked, so Clean Pixel Data is not claimed")
        XCTAssertEqual(Array(out[.pixelData]!.valueData.prefix(4)), [200, 200, 200, 200], "pixels untouched")
        // OCR ran (no burned-in declaration → OCR decides) and found nothing.
        XCTAssertTrue(console.hasPrefix("OCR: 0 candidate regions; 0 selected for redaction across 1 sampled frame.\n"), console)
        XCTAssertTrue(console.contains("Modified tags ("), console)
    }

    func testRetentionOptionsReachTheOutput() async throws {
        let input = try write(phiFile(), "in.dcm")
        var r = Request(inputPath: input); r.output = path("out.dcm")
        r.shiftDates = 30; r.retainCharacteristics = true; r.retainInstitution = true; r.retainUids = true
        _ = try await run(r)
        let out = try read("out.dcm")
        XCTAssertEqual(out.string(for: .studyDate), "20200131", "Modified Dates: shifted, interval preserved")
        XCTAssertEqual(out.string(for: .studyTime), "101500", "a whole-day shift leaves the time of day alone")
        XCTAssertEqual(out.string(for: .patientSex), "M")
        XCTAssertEqual(out.string(for: .institutionName), "General Hospital")
        XCTAssertEqual(out.string(for: .studyInstanceUID), "1.2.3.4.5.100")
        let method = out.string(for: Self.method) ?? ""
        XCTAssertTrue(method.contains("Modified Dates"), method)
        let codes = ConfidentialityProfile.MethodCode.recorded(in: out)
        XCTAssertTrue(codes.isSuperset(of: ["113100", "113107", "113108", "113110", "113112"]), "\(codes)")

        var full = Request(inputPath: input); full.output = path("full.dcm"); full.retainDates = true
        _ = try await run(full)
        let kept = try read("full.dcm")
        XCTAssertEqual(kept.string(for: .studyDate), "20200101", "Full Dates: kept verbatim")
        XCTAssertTrue(ConfidentialityProfile.MethodCode.recorded(in: kept).contains("113106"))
    }

    func testUIDsStayConsistentAcrossADirectory() async throws {
        try write(phiFile(sopUID: "1.2.3.4.5.6.7.8.10"), "src/a.dcm")
        try write(phiFile(sopUID: "1.2.3.4.5.6.7.8.11"), "src/nested/b.dcm")
        var r = Request(inputPath: path("src")); r.output = path("dst"); r.recursive = true
        let (_, outcome) = try await run(r)
        XCTAssertEqual(outcome.exitCode, 0)
        let a = try read("dst/a.dcm"), b = try read("dst/nested/b.dcm")
        XCTAssertEqual(a.string(for: .studyInstanceUID), b.string(for: .studyInstanceUID),
                       "one UID map per run: the study still holds together")
        XCTAssertNotEqual(a.string(for: .sopInstanceUID), b.string(for: .sopInstanceUID))
    }

    // MARK: - Burned In Annotation policy

    func testBurnedInAnnotationNoIsTrustedAndSaidSo() async throws {
        let input = try write(phiFile(burnedIn: "NO"), "in.dcm")
        var r = Request(inputPath: input); r.output = path("out.dcm"); r.verbose = true
        r.auditLog = path("audit.log")
        let (console, outcome) = try await run(r)
        XCTAssertEqual(outcome.exitCode, 0)
        XCTAssertTrue(console.hasPrefix(AnonConsole.burnedInAnnotationTrustedNote + "\n"), console)
        XCTAssertFalse(console.contains("OCR:"), "pixels were not inspected")
        let out = try read("out.dcm")
        XCTAssertEqual(out.string(for: Self.identityRemoved), "YES")
        XCTAssertEqual(out.string(for: .burnedInAnnotation), "NO")
        XCTAssertEqual(Array(out[.pixelData]!.valueData.prefix(4)), [200, 200, 200, 200])
        let audit = try String(contentsOfFile: path("audit.log"), encoding: .utf8)
        XCTAssertTrue(audit.contains("trusted; pixels were not inspected"), audit)
    }

    func testExplicitRegionOverridesTheTrustedNo() async throws {
        let input = try write(phiFile(burnedIn: "NO"), "in.dcm")
        var r = Request(inputPath: input); r.output = path("out.dcm"); r.redactRegion = ["0,0,16,2"]
        _ = try await run(r)
        let out = try read("out.dcm")
        XCTAssertEqual(Array(out[.pixelData]!.valueData.prefix(32)), Array(repeating: UInt8(0), count: 32))
        XCTAssertTrue(ConfidentialityProfile.MethodCode.recorded(in: out).contains("113101"))
    }

    func testBurnedInAnnotationYesWithNoLocatableRegionIsRefusedNotGuessed() async throws {
        let input = try write(phiFile(burnedIn: "YES"), "in.dcm")
        var r = Request(inputPath: input); r.output = path("out.dcm")
        await assertThrowsErrorAsync(try await run(r)) { error in
            guard case PixelRedactionError.unresolvedRegion = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("out.dcm")))
    }

    func testHeaderOnlyRefusesBurnedInAnnotationUnlessAccepted() async throws {
        let input = try write(phiFile(burnedIn: "YES"), "in.dcm")
        var r = Request(inputPath: input); r.output = path("out.dcm"); r.cleanPixelData = false
        await assertThrowsErrorAsync(try await run(r)) { error in
            let message = (error as? ValidationError)?.message ?? ""
            XCTAssertTrue(message.hasPrefix("Refusing to anonymize in.dcm: the pixel data may still contain PHI."), message)
            XCTAssertTrue(message.contains("--no-clean-pixel-data"), message)
            XCTAssertTrue(message.contains("--allow-burned-in-phi"), message)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("out.dcm")))

        // Dry runs report instead of refusing.
        var dry = r; dry.dryRun = true
        let (console, dryOutcome) = try await run(dry)
        XCTAssertEqual(dryOutcome.exitCode, 0)
        XCTAssertTrue(console.contains("Burned In Annotation (0028,0301) is YES"), console)

        r.allowBurnedInPHI = true
        let (_, outcome) = try await run(r)
        XCTAssertEqual(outcome.exitCode, 0)
        let out = try read("out.dcm")
        XCTAssertEqual(out.string(for: Self.identityRemoved), "NO",
                       "an accepted residual must never be attested as removed")
        XCTAssertTrue(out.string(for: Self.method)?.contains("DATASET ONLY") == true)
    }

    // MARK: - Pixel-first cleaning

    func testExplicitRegionBlanksPixelsBeforeHeaderPass() async throws {
        let input = try write(phiFile(burnedIn: "YES"), "in.dcm")
        var r = Request(inputPath: input); r.output = path("out.dcm")
        r.redactRegion = ["0,0,16,2"]; r.redactFill = "5"; r.verbose = true
        let (console, outcome) = try await run(r)
        XCTAssertEqual(outcome.exitCode, 0, "cleaning the declared burned-in text earns the attestation")
        let out = try read("out.dcm")
        let pixels = try XCTUnwrap(out[.pixelData]?.valueData)
        XCTAssertEqual(Array(pixels.prefix(32)), Array(repeating: UInt8(5), count: 32), "the 2 top rows are the fill value")
        XCTAssertEqual(pixels[32], 200, "rows outside the region are untouched")
        XCTAssertEqual(out.string(for: .burnedInAnnotation), "NO")
        XCTAssertEqual(out.string(for: Self.identityRemoved), "YES")
        XCTAssertEqual(out.string(for: .patientName), "", "header pass still ran after the pixel pass")
        let codes = ConfidentialityProfile.MethodCode.recorded(in: out)
        XCTAssertTrue(codes.isSuperset(of: ["113100", "113101"]), "both passes recorded: \(codes)")
        XCTAssertTrue(out.string(for: Self.method)?.contains("Clean Pixel Data") == true)
        XCTAssertTrue(console.contains("Cleaned pixel data (explicit): "), console)
        XCTAssertTrue(console.contains("blanked (0,0) 16x2\n"), console)
    }

    func testDryRunPrintsPlanTableAndWritesNothing() async throws {
        let input = try write(phiFile(), "in.dcm")
        var r = Request(inputPath: input); r.dryRun = true; r.redactRegion = ["0,0,4,4"]
        let (console, outcome) = try await run(r)
        XCTAssertEqual(outcome.exitCode, 0)
        XCTAssertTrue(console.contains("Pixel redaction plan:\n"), console)
        XCTAssertTrue(console.contains("1 explicit region = 1 unioned region\n"), console)
        XCTAssertTrue(console.contains("  Pixel modification: YES\n"), console)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["in.dcm"])
    }

    func testRecompressAfterExplicitRegion() async throws {
        let input = try write(phiFile(), "in.dcm")
        var r = Request(inputPath: input); r.output = path("out.dcm")
        r.redactRegion = ["0,0,16,2"]; r.recompress = "rle"
        let (console, outcome) = try await run(r)
        XCTAssertEqual(outcome.exitCode, 0)
        XCTAssertTrue(console.contains("Re-encoded to 1.2.840.10008.1.2.5 (rle, lossless); source was 1.2.840.10008.1.2.1\n"), console)
        XCTAssertTrue(console.contains("  verified: redacted regions still blank after the codec round-trip\n"), console)
        let out = try DICOMFile.read(from: Data(contentsOf: URL(fileURLWithPath: path("out.dcm"))))
        XCTAssertEqual(out.fileMetaInformation.string(for: Tag(group: 0x0002, element: 0x0010)), "1.2.840.10008.1.2.5")
    }

    // MARK: - Files and console

    func testDirectoryRunMirrorsTreeAndVerboseLines() async throws {
        try write(phiFile(), "src/a.dcm")
        try write(phiFile(), "src/nested/b.dcm")
        try write(Data("junk".utf8), "src/readme.txt")
        var r = Request(inputPath: path("src")); r.output = path("dst"); r.recursive = true; r.verbose = true
        let (console, outcome) = try await run(r)
        XCTAssertEqual(outcome.exitCode, 1, "the junk file fails, and any failure is exit 1")
        XCTAssertEqual(outcome.results.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path("dst/a.dcm")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path("dst/nested/b.dcm")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("dst/readme.txt")))
        XCTAssertTrue(console.contains(AnonConsole.fileSuccessLine(relativePath: "a.dcm") + "\n"), console)
        XCTAssertTrue(console.contains(AnonConsole.fileSuccessLine(relativePath: "nested/b.dcm") + "\n"), console)
        XCTAssertTrue(console.contains("✗ readme.txt: "), console)
        XCTAssertTrue(console.contains("  Failed: 1\n"), console)
    }

    func testDirectoryOutputForSingleFileWritesInsideItUnderInputName() async throws {
        let input = try write(phiFile(), "in.dcm")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dst"), withIntermediateDirectories: true)
        var r = Request(inputPath: input); r.output = path("dst")
        let (_, outcome) = try await run(r)
        XCTAssertEqual(outcome.exitCode, 0)
        XCTAssertTrue(outcome.results[0].warnings.isEmpty, "\(outcome.results[0].warnings)")
        XCTAssertEqual(try read("dst/in.dcm").string(for: .patientName), "")

        var r2 = Request(inputPath: input); r2.output = path("new") + "/"
        _ = try await run(r2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path("new/in.dcm")))
        var r3 = Request(inputPath: input); r3.output = path("plain.dcm")
        _ = try await run(r3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path("plain.dcm")))
    }

    func testBackupLandsNextToOutput() async throws {
        let input = try write(phiFile(), "in.dcm")
        var r = Request(inputPath: input); r.output = path("out/anon.dcm"); r.backup = true
        try FileManager.default.createDirectory(at: root.appendingPathComponent("out"), withIntermediateDirectories: true)
        _ = try await run(r)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path("out/anon.dcm.backup"))), phiFile())
    }

    func testAuditLogWrittenAndAnnouncedWhenVerboseAndCarriesNoValues() async throws {
        let input = try write(phiFile(), "in.dcm")
        var r = Request(inputPath: input); r.dryRun = true; r.auditLog = path("audit.log"); r.verbose = true
        let (console, _) = try await run(r)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path("audit.log")), "audit log is written even on a dry run")
        XCTAssertTrue(console.hasSuffix(AnonConsole.auditLogLine(path: path("audit.log")) + "\n"), console)
        let audit = try String(contentsOfFile: path("audit.log"), encoding: .utf8)
        XCTAssertTrue(audit.contains("Z zero - (0010,0010)"), audit)
        XCTAssertFalse(audit.contains("Smith"), "the audit log must not be a PHI store")
    }

    func testWriterHookNoteReachesWarnings() async throws {
        let input = try write(phiFile(), "in.dcm")
        var r = Request(inputPath: input); r.output = path("out.dcm")
        let written = WrittenURLs()
        let workflow = AnonymizationWorkflow(writeFile: { data, url in
            try data.write(to: url.appendingPathExtension("redirected"))
            written.append(url)
            return "redirected to \(url.lastPathComponent).redirected"
        })
        let (console, outcome) = try await run(r, workflow: workflow)
        XCTAssertEqual(written.paths, [path("out.dcm")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: path("out.dcm.redirected")))
        XCTAssertEqual(outcome.results[0].warnings.last, "redirected to out.dcm.redirected")
        XCTAssertTrue(console.contains("⚠️  redirected to out.dcm.redirected"), console)
    }
    // Regression coverage for integration with the newer main header engine.
    func testIntegratedWorkflowCleansDescriptorsAndSynchronizesFileMeta() async throws {
        let source = try DICOMFile.read(from: phiFile(burnedIn: "NO"))
        var ds = source.dataSet
        ds.setString("Smith^John CT chest", for: .studyDescription, vr: .LO)
        let input = try write(try DICOMFile(fileMetaInformation: source.fileMetaInformation, dataSet: ds).write(), "identified.dcm")
        var r = Request(inputPath: input)
        r.output = path("integrated.dcm")
        r.cleanDescriptors = true
        r.cleanGraphics = true
        r.cleanStructuredContent = true
        r.retainSafePrivate = true
        r.auditLog = path("audit.txt")
        _ = try await run(r)
        let out = try DICOMFile.read(from: Data(contentsOf: URL(fileURLWithPath: path("integrated.dcm"))))
        let description = out.dataSet.string(for: .studyDescription) ?? ""
        XCTAssertFalse(description.contains("Smith"))
        XCTAssertTrue(description.contains("CT chest"))
        XCTAssertEqual(out.fileMetaInformation.string(for: Tag(group: 0x0002, element: 0x0003)),
                       out.dataSet.string(for: .sopInstanceUID)) // Media Storage SOP Instance UID
        XCTAssertTrue(ConfidentialityProfile.MethodCode.recorded(in: out.dataSet).isSuperset(of: ["113100", "113103", "113104", "113105", "113111"]))
        let audit = try String(contentsOfFile: path("audit.txt"), encoding: .utf8)
        XCTAssertFalse(audit.contains("Smith"))
        XCTAssertFalse(audit.contains("MRN-123"))
    }

    func testPreviewAndFinalHeaderShareUIDReplacements() throws {
        let file = try DICOMFile.read(from: phiFile(burnedIn: "NO"))
        let anonymizer = Anonymizer(options: .basic)
        let preview = anonymizer.preview(file: file)
        let (final, _) = anonymizer.deidentify(file: file, filePath: "a.dcm")
        XCTAssertEqual(preview.dataSet.string(for: .sopInstanceUID), final.dataSet.string(for: .sopInstanceUID))
        XCTAssertEqual(preview.dataSet.string(for: .studyInstanceUID), final.dataSet.string(for: .studyInstanceUID))
        XCTAssertNotEqual(final.dataSet.string(for: .sopInstanceUID), file.dataSet.string(for: .sopInstanceUID))
    }

    func testRecognizableFeaturesNeedExplicitRegions() throws {
        var r = Request(inputPath: "unused.dcm")
        r.cleanRecognizableVisualFeatures = true
        XCTAssertThrowsError(try AnonymizationWorkflow.resolve(r))
        r.redactRegion = ["0,0,2,2"]
        let resolved = try AnonymizationWorkflow.resolve(r)
        XCTAssertTrue(resolved.pixelOptions.cleanRecognizableVisualFeatures)
    }

    func testIntegratedVisualFeatureCleaningPreservesBothMethodCodes() async throws {
        let input = try write(phiFile(burnedIn: "NO"), "features.dcm")
        var r = Request(inputPath: input)
        r.output = path("features-out.dcm")
        r.cleanPixelData = false
        r.cleanRecognizableVisualFeatures = true
        r.redactRegion = ["0,0,2,2"]
        r.recompress = "rle"
        _ = try await run(r)
        let out = try read("features-out.dcm")
        XCTAssertEqual(out.string(for: .recognizableVisualFeatures), "NO")
        XCTAssertTrue(ConfidentialityProfile.MethodCode.recorded(in: out).isSuperset(of: ["113100", "113101", "113102"]))
    }

}

/// Thread-safe collector for the `@Sendable` writer hook.
private final class WrittenURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func append(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return urls.map(\.path) }

}
