import XCTest
@testable import DICOMStudio
@testable import DICOMCore

/// The J2K Test Bench must not present JPEG 2000 Part 2 as a working target.
///
/// `planEncode` downgrades a Part-2 UID to a Part-1-compatible codestream (no
/// multi-component transform), which round-trips bit-exactly. Benchmarking that and
/// reporting it under a Part-2 label reads as "Part 2 works" when the feature is in
/// fact switched off — the bench must report the row as skipped instead.
final class J2KTestBenchPart2Tests: XCTestCase {

    private static let part2UIDs: Set<String> = [
        TransferSyntax.jpeg2000Part2Lossless.uid,  // .92
        TransferSyntax.jpeg2000Part2.uid           // .93
    ]

    private var part2Rows: [J2KBenchSyntax] {
        J2KBenchSyntax.all.filter { Self.part2UIDs.contains($0.uid) }
    }

    /// D9: every bench row is named by the shared catalog, so .110 reads "JPEG XL
    /// Lossless" (PS3.6 2026a Table A-1), not "JPEG XL Lossless Only"; the default
    /// selection resolves to five rows whose names are Table A-1 names.
    func test_benchSyntaxNames_followTableA1() {
        XCTAssertEqual(J2KBenchSyntax.named(TransferSyntax.jpegXLLossless.uid)?.shortName, "JPEG XL Lossless")
        XCTAssertEqual(J2KBenchSyntax.named(TransferSyntax.htj2kLossless.uid)?.shortName,
                       "High-Throughput JPEG 2000 Image Compression (Lossless Only)")
        XCTAssertEqual(J2KBenchSyntax.named(TransferSyntax.jpegLosslessSV1.uid)?.shortName,
                       TransferSyntax.jpegLosslessSV1.displayName)
        for row in J2KBenchSyntax.all {
            XCTAssertFalse(row.shortName.contains("Lossless Only Only"), row.shortName)
            XCTAssertTrue(row.shortName.hasPrefix(TransferSyntax.from(uid: row.uid)?.displayName ?? "?"),
                          "\(row.shortName) does not start with the Table A-1 name of \(row.uid)")
        }
        let defaults = J2KTestPlan().selectedSyntaxIDs
        XCTAssertEqual(defaults.count, 5)
        for id in defaults {
            XCTAssertNotNil(J2KBenchSyntax.all.first { $0.id == id }, "default selection \(id) is a bench row")
        }
    }

    /// A row built without an explicit flag asks the registry: PS3.6 2026a Table A-1's
    /// lossy-only syntaxes (JPEG Baseline .50, JPEG-LS Near-Lossless .81) and the
    /// `both` UIDs (.91, .203, .112) score by PSNR; the lossless-only ones bit-exact.
    func test_defaultIsLossless_followsRegistry() {
        XCTAssertFalse(J2KBenchSyntax(uid: TransferSyntax.jpegBaseline.uid, shortName: "", format: .jpeg).isLossless)
        XCTAssertFalse(J2KBenchSyntax(uid: TransferSyntax.jpegLSNearLossless.uid, shortName: "", format: .jpegLS).isLossless)
        XCTAssertFalse(J2KBenchSyntax(uid: TransferSyntax.jpegXL.uid, shortName: "", format: .jpegXL).isLossless)
        XCTAssertFalse(J2KBenchSyntax(uid: TransferSyntax.jpeg2000.uid, shortName: "").isLossless)
        XCTAssertTrue(J2KBenchSyntax(uid: TransferSyntax.jpeg2000Lossless.uid, shortName: "").isLossless)
        XCTAssertTrue(J2KBenchSyntax(uid: TransferSyntax.jpegLSLossless.uid, shortName: "", format: .jpegLS).isLossless)
        XCTAssertTrue(J2KBenchSyntax(uid: TransferSyntax.jpegXLLossless.uid, shortName: "", format: .jpegXL).isLossless)
    }

    /// The bench surfaces three Part-2 rows: `.93` splits into Lossless + Lossy, and
    /// `.92` is lossless-only. This pins the set the user actually sees.
    func test_benchListsThreePart2Rows() {
        let rows = part2Rows
        XCTAssertEqual(rows.count, 3, "expected .92 plus both intents of .93, got \(rows.map(\.shortName))")
        XCTAssertEqual(rows.filter { $0.uid == TransferSyntax.jpeg2000Part2.uid }.count, 2)
        XCTAssertEqual(rows.filter { $0.uid == TransferSyntax.jpeg2000Part2Lossless.uid }.count, 1)
        // All three route to the JPEG 2000 bench family.
        XCTAssertTrue(rows.allSatisfy { $0.format == .jpeg2000 })
    }

    /// Every Part-2 row must be refused up front, flagged as unsupported (→ skipped)
    /// rather than as an error, and must never yield a codestream to time.
    func test_everyPart2Row_isSkippedNotBenchmarked() throws {
        let descriptor = PixelDataDescriptor(
            rows: 8, columns: 8, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 3,
            photometricInterpretation: .rgb
        )
        let frame = Data(repeating: 0x7F, count: descriptor.bytesPerFrame)

        for row in part2Rows {
            let result = J2KTestBenchService.encodeReference(
                frame: frame, descriptor: descriptor, syntax: row,
                mode: .cpu, warmups: 0, runs: 1
            )
            switch result {
            case .success:
                XCTFail("\(row.shortName) was benchmarked; a blocked target must not produce a codestream")
            case .failure(let error):
                XCTAssertTrue(
                    error.isUnsupported,
                    "\(row.shortName) must be flagged unsupported so the grid shows it as skipped, not a red error"
                )
                XCTAssertTrue(error.message.contains("not supported"), "reason should explain the block: \(error.message)")
            }
        }
    }

    /// Part-1 and HTJ2K rows must keep benchmarking — the guard is Part-2-only.
    func test_part1AndHTJ2KRows_stillRun() throws {
        let descriptor = PixelDataDescriptor(
            rows: 8, columns: 8, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let frame = Data(repeating: 0x40, count: descriptor.bytesPerFrame)

        let runnable = [TransferSyntax.jpeg2000Lossless.uid, TransferSyntax.htj2kLossless.uid]
        for uid in runnable {
            guard let row = J2KBenchSyntax.all.first(where: { $0.uid == uid && $0.isLossless }) else {
                return XCTFail("bench is missing a lossless row for \(uid)")
            }
            let result = J2KTestBenchService.encodeReference(
                frame: frame, descriptor: descriptor, syntax: row,
                mode: .cpu, warmups: 0, runs: 1
            )
            guard case .success(let out) = result else {
                return XCTFail("\(row.shortName) should still benchmark, got \(result)")
            }
            XCTAssertFalse(out.codestream.isEmpty)
        }
    }

    /// The DICOMCore bench entry point is the actual bypass that made Part-2 look
    /// green — it must refuse on its own, independent of the bench service.
    func test_benchEncode_refusesPart2AtCoreLevel() {
        let descriptor = PixelDataDescriptor(
            rows: 8, columns: 8, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 3,
            photometricInterpretation: .rgb
        )
        let frame = Data(repeating: 0x7F, count: descriptor.bytesPerFrame)

        let result = J2KSwiftCodec.benchEncode(
            frame, descriptor: descriptor,
            transferSyntaxUID: TransferSyntax.jpeg2000Part2.uid,
            configuration: CompressionConfiguration(quality: .maximum, preferLossless: true),
            mode: .cpu, warmups: 0, runs: 1
        )
        XCTAssertNil(result.data, "benchEncode must not produce a substitute codestream for Part-2")
        XCTAssertTrue(result.samples.isEmpty, "no timings should be reported for a blocked target")
        XCTAssertNotNil(result.error)
    }
}
