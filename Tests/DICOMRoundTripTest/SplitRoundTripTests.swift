// SplitRoundTripTests.swift
// Oracle-based round-trip tests for the `dicom-split` tool.
//
// These tests drive the DICOMKit library engine (`FrameSplitter`) directly —
// the exact same code the `dicom-split` CLI calls — never spawning the binary.
// Every assertion is a semantic/mathematical fact true by definition, never a
// comparison against a re-implementation of the tool.
//
// Verified against source:
//   Sources/DICOMKit/Splitting/FrameSplitter.swift
//   Sources/dicom-split/DICOMSplit.swift
//   Sources/DICOMCore/PixelData.swift (frameData(at:))
//   Sources/DICOMKit/DICOMFile+PixelData.swift (numberOfFrames, pixelData, renderFrame)

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class SplitRoundTripTests: XCTestCase {

    // MARK: - Private helpers (class-scoped so they never collide across test files)

    /// Builds a FrameSplitter that writes DICOM output into `dir`.
    private func dicomSplitter(into dir: URL, pattern: String? = nil) -> FrameSplitter {
        FrameSplitter(
            outputPath: dir.path,
            format: .dicom,
            applyWindow: false,
            windowCenter: nil,
            windowWidth: nil,
            namingPattern: pattern,
            verbose: false
        )
    }

    /// Splits `file` (all frames unless `frames` given) and returns the parsed
    /// output DICOMFiles, sorted by their written path for determinism.
    private func splitDICOM(
        _ file: DICOMFile,
        frames: Set<Int>? = nil,
        pattern: String? = nil
    ) async throws -> (result: SplitResult, files: [DICOMFile]) {
        let inDir = try makeTempDir()
        let inURL = inDir.appendingPathComponent("input.dcm")
        try file.write().write(to: inURL)

        let outDir = try makeTempDir()
        let splitter = dicomSplitter(into: outDir, pattern: pattern)
        var result = SplitResult()
        await splitter.processFile(inURL.path, frameIndices: frames, into: &result)

        let parsed: [DICOMFile] = try result.writtenPaths.sorted().map {
            try DICOMFile.read(from: URL(fileURLWithPath: $0))
        }
        return (result, parsed)
    }

    // MARK: - Oracle: multi-frame splits into exactly N single-frame files

    // Oracle: N-frame input -> N output files, each with NumberOfFrames == 1.
    func testSplitProducesNSingleFrameFiles() async throws {
        let frameCount = 4
        let src = makeMultiFrame(rows: 8, cols: 8, frames: frameCount, fill: { UInt8($0 * 10) })

        let (result, files) = try await splitDICOM(src)

        XCTAssertEqual(result.extracted, frameCount, "all frames extracted")
        XCTAssertEqual(result.failed, 0, "no failures")
        XCTAssertEqual(files.count, frameCount, "one output file per frame")

        for out in files {
            // Number of Frames must be exactly 1 in every extracted file.
            let nf = out.dataSet.string(for: .numberOfFrames)
            XCTAssertEqual(nf?.trimmingCharacters(in: .whitespaces), "1",
                           "each output declares NumberOfFrames == 1")
            XCTAssertEqual(out.numberOfFrames ?? 1, 1)
        }
    }

    // MARK: - Oracle: extracted pixel bytes equal the correct source frame

    // Oracle: output frame k's pixel bytes == source frame k's pixel bytes.
    func testExtractedFramePixelsMatchSource() async throws {
        let frameCount = 3
        // Frame f is filled with a distinct constant so we can identify it.
        let src = makeMultiFrame(rows: 6, cols: 6, frames: frameCount, fill: { UInt8($0 * 40 + 5) })

        // Source frames as ground truth via the library's own pixel accessor.
        let srcPixels = try XCTUnwrap(src.pixelData())
        var expectedFrames: [Data] = []
        for f in 0..<frameCount {
            expectedFrames.append(try XCTUnwrap(srcPixels.frameData(at: f)))
        }

        let (_, files) = try await splitDICOM(src)
        XCTAssertEqual(files.count, frameCount)

        // Each output file holds exactly one frame; its bytes must equal some
        // source frame, and collectively they must cover every source frame.
        var outFrameBytes: [Data] = []
        for out in files {
            let outPixels = try XCTUnwrap(out.pixelData())
            let frame = try XCTUnwrap(outPixels.frameData(at: 0))
            outFrameBytes.append(frame)
        }

        // Every source frame's bytes appear exactly once in the outputs.
        for expected in expectedFrames {
            let matches = outFrameBytes.filter { $0 == expected }.count
            XCTAssertEqual(matches, 1, "each source frame appears exactly once in outputs")
        }
    }

    // MARK: - Oracle: distinct SOP Instance UID per extracted frame

    // Oracle: every extracted single-frame file has a unique SOP Instance UID.
    func testExtractedFramesHaveDistinctSOPInstanceUIDs() async throws {
        let src = makeMultiFrame(rows: 4, cols: 4, frames: 5)
        let (_, files) = try await splitDICOM(src)

        let uids = files.compactMap { $0.dataSet.string(for: .sopInstanceUID) }
        XCTAssertEqual(uids.count, files.count, "every file has a SOP Instance UID")
        XCTAssertEqual(Set(uids).count, uids.count, "SOP Instance UIDs are all distinct")
    }

    // MARK: - Oracle: --frames selects exactly the requested subset

    // Oracle: frameIndices subset -> only those (in-bounds) frames extracted.
    func testFrameSelectionExtractsOnlyRequestedFrames() async throws {
        let src = makeMultiFrame(rows: 5, cols: 5, frames: 8, fill: { UInt8($0 * 25) })
        // Request frames {1, 3, 6} plus one out-of-bounds index (99) that must be dropped.
        let requested: Set<Int> = [1, 3, 6, 99]

        let (result, files) = try await splitDICOM(src, frames: requested)

        // Only the 3 in-bounds indices are extracted; out-of-bounds is filtered.
        XCTAssertEqual(result.extracted, 3, "only in-bounds requested frames extracted")
        XCTAssertEqual(files.count, 3)

        // The extracted pixel content must correspond to source frames 1, 3, 6.
        let srcPixels = try XCTUnwrap(src.pixelData())
        let expected: Set<Data> = try Set([1, 3, 6].map { try XCTUnwrap(srcPixels.frameData(at: $0)) })
        var extracted: Set<Data> = []
        for out in files {
            let p = try XCTUnwrap(out.pixelData())
            extracted.insert(try XCTUnwrap(p.frameData(at: 0)))
        }
        XCTAssertEqual(extracted, expected, "extracted frames are exactly source frames 1,3,6")
    }

    // MARK: - Oracle: single-frame input is skipped, nothing extracted

    // Oracle: a single-frame file yields skippedFiles += 1 and 0 extractions.
    func testSingleFrameFileIsSkipped() async throws {
        let src = makeGrayscale8(rows: 8, cols: 8) // no NumberOfFrames -> treated as 1
        let inDir = try makeTempDir()
        let inURL = inDir.appendingPathComponent("single.dcm")
        try src.write().write(to: inURL)

        let outDir = try makeTempDir()
        var result = SplitResult()
        await dicomSplitter(into: outDir).processFile(inURL.path, frameIndices: nil, into: &result)

        XCTAssertEqual(result.extracted, 0, "no frames extracted from single-frame file")
        XCTAssertEqual(result.processedFiles, 0, "single-frame file not counted as processed")
        XCTAssertEqual(result.skippedFiles, 1, "single-frame file is skipped")
    }

    // MARK: - Oracle: metadata preserved into extracted frames

    // Oracle: non-pixel identity tags (SOPClassUID, StudyInstanceUID) copied unchanged.
    func testMetadataPreservedInExtractedFrames() async throws {
        let src = makeMultiFrame(rows: 4, cols: 4, frames: 3)
        let expectedStudy = src.dataSet.string(for: .studyInstanceUID)
        let expectedSeries = src.dataSet.string(for: .seriesInstanceUID)
        let expectedSOPClass = src.dataSet.string(for: .sopClassUID)
        let expectedModality = src.dataSet.string(for: .modality)

        let (_, files) = try await splitDICOM(src)
        XCTAssertFalse(files.isEmpty)

        for out in files {
            XCTAssertEqual(out.dataSet.string(for: .studyInstanceUID), expectedStudy,
                           "StudyInstanceUID preserved")
            XCTAssertEqual(out.dataSet.string(for: .seriesInstanceUID), expectedSeries,
                           "SeriesInstanceUID preserved")
            XCTAssertEqual(out.dataSet.string(for: .sopClassUID), expectedSOPClass,
                           "SOPClassUID preserved")
            XCTAssertEqual(out.dataSet.string(for: .modality), expectedModality,
                           "Modality preserved")
        }
    }

    // MARK: - Oracle: naming pattern template substitution

    // Oracle: {number:04d}/{modality} template resolves to real per-frame filenames.
    func testNamingPatternProducesTemplatedFilenames() async throws {
        let src = makeMultiFrame(rows: 4, cols: 4, frames: 3) // modality "CT"
        // Note: FrameSplitter substitutes the bare {number}/{modality} tokens.
        let (result, _) = try await splitDICOM(src, pattern: "seg_{number}_{modality}.dcm")

        XCTAssertEqual(result.writtenPaths.count, 3)
        let names = result.writtenPaths.map { ($0 as NSString).lastPathComponent }
        // Frame index is zero-padded to %04d; modality "CT" is substituted.
        XCTAssertTrue(names.contains("seg_0000_CT.dcm"), "frame 0 templated name")
        XCTAssertTrue(names.contains("seg_0001_CT.dcm"), "frame 1 templated name")
        XCTAssertTrue(names.contains("seg_0002_CT.dcm"), "frame 2 templated name")
        for name in names {
            XCTAssertFalse(name.contains("{"), "no unresolved template tokens remain")
        }
    }

    // MARK: - Oracle: directory processing aggregates across files

    // Oracle: processDirectory over 2 multi-frame files extracts the sum of frames.
    func testProcessDirectoryAggregatesFrameCounts() async throws {
        let a = makeMultiFrame(rows: 4, cols: 4, frames: 3)
        let b = makeMultiFrame(rows: 4, cols: 4, frames: 2)

        let inDir = try makeTempDir()
        try a.write().write(to: inDir.appendingPathComponent("a.dcm"))
        try b.write().write(to: inDir.appendingPathComponent("b.dcm"))

        let outDir = try makeTempDir()
        let result = try await dicomSplitter(into: outDir)
            .processDirectory(inDir.path, recursive: false, frameIndices: nil)

        XCTAssertEqual(result.processedFiles, 2, "both multi-frame files processed")
        XCTAssertEqual(result.extracted, 5, "3 + 2 frames extracted in total")
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(result.writtenPaths.count, 5)
    }

    // MARK: - Oracle: written DICOM files carry the standard preamble + magic

    // Oracle: each extracted DICOM has the 128-byte preamble followed by "DICM".
    func testExtractedFilesHaveDICMMagic() async throws {
        let src = makeMultiFrame(rows: 4, cols: 4, frames: 2)
        let (_, _) = try await splitDICOM(src)

        // Re-run capturing raw bytes to inspect the file preamble.
        let inDir = try makeTempDir()
        let inURL = inDir.appendingPathComponent("mf.dcm")
        try src.write().write(to: inURL)
        let outDir = try makeTempDir()
        var result = SplitResult()
        await dicomSplitter(into: outDir).processFile(inURL.path, frameIndices: nil, into: &result)

        XCTAssertFalse(result.writtenPaths.isEmpty)
        for path in result.writtenPaths {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            XCTAssertGreaterThanOrEqual(bytes.count, 132, "file has preamble + magic")
            let magic = bytes[(bytes.startIndex + 128)..<(bytes.startIndex + 132)]
            XCTAssertEqual(Data(magic), Data([0x44, 0x49, 0x43, 0x4D]), "\"DICM\" magic at byte 128")
        }
    }

    // MARK: - Oracle: corpus multi-frame realism

    // Oracle: real 12-frame Enhanced-MR corpus splits into 12 single-frame files.
    func testCorpusMultiframeSplits() async throws {
        let f = try loadCorpus(.ctMultiframe)
        try XCTSkipIf(f == nil, "corpus absent")
        let file = try XCTUnwrap(f)
        let expectedFrames = file.numberOfFrames ?? 1
        try XCTSkipIf(expectedFrames <= 1, "corpus file is not multi-frame")

        let (result, files) = try await splitDICOM(file)

        XCTAssertEqual(result.extracted, expectedFrames, "all corpus frames extracted")
        XCTAssertEqual(files.count, expectedFrames)
        for out in files {
            XCTAssertEqual(out.numberOfFrames ?? 1, 1, "each corpus output is single-frame")
        }
        // Distinct UIDs on real data too.
        let uids = files.compactMap { $0.dataSet.string(for: .sopInstanceUID) }
        XCTAssertEqual(Set(uids).count, files.count, "distinct SOP UIDs on corpus split")
    }

    // MARK: - Oracle: PNG image export writes valid PNG magic bytes

    #if canImport(CoreGraphics)
    // Oracle: --format png output begins with the PNG 8-byte signature.
    func testPNGExportHasPNGMagic() async throws {
        let src = makeMultiFrame(rows: 16, cols: 16, frames: 2, fill: { UInt8($0 * 60 + 30) })
        let inDir = try makeTempDir()
        let inURL = inDir.appendingPathComponent("mf.dcm")
        try src.write().write(to: inURL)

        let outDir = try makeTempDir()
        let splitter = FrameSplitter(
            outputPath: outDir.path,
            format: .png,
            applyWindow: false,
            windowCenter: nil,
            windowWidth: nil,
            namingPattern: nil,
            verbose: false
        )
        var result = SplitResult()
        await splitter.processFile(inURL.path, frameIndices: nil, into: &result)

        // If rendering is unavailable on this platform the tool records failures;
        // only assert the magic when frames were actually written.
        try XCTSkipIf(result.extracted == 0, "PNG rendering unavailable on this platform")
        XCTAssertEqual(result.extracted, 2)
        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        for path in result.writtenPaths {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            XCTAssertGreaterThanOrEqual(bytes.count, 8)
            XCTAssertEqual(Data(bytes.prefix(8)), pngSignature, "output is a valid PNG")
        }
    }

    // Oracle: --format jpeg / tiff write files carrying the correct image magic bytes.
    func testJPEGAndTIFFExportMagic() async throws {
        // Multi-frame source: the splitter skips single-frame files, so it needs ≥2 frames.
        let src = makeMultiFrame(rows: 16, cols: 16, frames: 2, fill: { UInt8($0 * 100 + 50) })
        let inDir = try makeTempDir()
        let inURL = inDir.appendingPathComponent("mf.dcm")
        try src.write().write(to: inURL)

        // JPEG: Start-Of-Image marker 0xFF 0xD8 0xFF.
        let jpegOut = try makeTempDir()
        var jr = SplitResult()
        await FrameSplitter(outputPath: jpegOut.path, format: .jpeg, applyWindow: false,
                            windowCenter: nil, windowWidth: nil, namingPattern: nil, verbose: false)
            .processFile(inURL.path, frameIndices: nil, into: &jr)
        try XCTSkipIf(jr.extracted == 0, "JPEG rendering unavailable on this platform")
        for p in jr.writtenPaths {
            let b = try Data(contentsOf: URL(fileURLWithPath: p))
            XCTAssertEqual(Array(b.prefix(3)), [0xFF, 0xD8, 0xFF], "output is a valid JPEG (SOI)")
        }

        // TIFF: byte-order mark "II" (little-endian) or "MM" (big-endian).
        let tiffOut = try makeTempDir()
        var tr = SplitResult()
        await FrameSplitter(outputPath: tiffOut.path, format: .tiff, applyWindow: false,
                            windowCenter: nil, windowWidth: nil, namingPattern: nil, verbose: false)
            .processFile(inURL.path, frameIndices: nil, into: &tr)
        try XCTSkipIf(tr.extracted == 0, "TIFF rendering unavailable on this platform")
        for p in tr.writtenPaths {
            let bom = Array((try Data(contentsOf: URL(fileURLWithPath: p))).prefix(2))
            XCTAssertTrue(bom == [0x49, 0x49] || bom == [0x4D, 0x4D], "output is a valid TIFF (BOM)")
        }
    }

    // Oracle: --apply-window with an explicit center/width renders a valid PNG whose
    // pixels differ from the default (no-window) render — the window is actually applied.
    func testApplyWindowChangesRenderedOutput() async throws {
        // Multi-frame source (splitter skips single-frame files); frame 0 is a uniform
        // mid-gray whose mapped level differs under a narrow window vs. the full range.
        let src = makeMultiFrame(rows: 16, cols: 16, frames: 2, fill: { UInt8($0 * 80 + 40) })
        let inDir = try makeTempDir()
        let inURL = inDir.appendingPathComponent("mf.dcm")
        try src.write().write(to: inURL)

        func renderPNG(applyWindow: Bool, wc: Double?, ww: Double?) async throws -> Data? {
            let out = try makeTempDir()
            var r = SplitResult()
            await FrameSplitter(outputPath: out.path, format: .png, applyWindow: applyWindow,
                                windowCenter: wc, windowWidth: ww, namingPattern: nil, verbose: false)
                .processFile(inURL.path, frameIndices: nil, into: &r)
            guard r.extracted > 0, let p = r.writtenPaths.first else { return nil }
            return try Data(contentsOf: URL(fileURLWithPath: p))
        }

        // Frame 0 is flat (40). The auto window is C.11.2.1.2.1's full-range window, for a
        // single value the unit-width threshold at 40.5, so it renders black (D66); 40 / 80
        // puts 40 mid-ramp, a grey that differs from it.
        let plain = try await renderPNG(applyWindow: false, wc: nil, ww: nil)
        let windowed = try await renderPNG(applyWindow: true, wc: 40, ww: 80)
        try XCTSkipIf(plain == nil || windowed == nil, "PNG rendering unavailable on this platform")
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertEqual(Array(windowed!.prefix(8)), pngSignature, "windowed output is a valid PNG")
        XCTAssertNotEqual(plain, windowed, "an explicit window must change the rendered pixels")
    }
    #endif
}

