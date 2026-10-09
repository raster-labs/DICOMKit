// ConversionDiagnosticsTests.swift
// The shared dicom-convert failure explanations (ConversionFailure) used by BOTH the
// CLI and DICOMStudio. Each test builds a source whose transfer syntax or pixel format
// does not suit the target, and checks the category and the words the user will see.

import XCTest
@testable import DICOMKit
@testable import DICOMCore

final class ConversionDiagnosticsTests: XCTestCase {

    // MARK: - Fixtures

    private func makeFile(
        transferSyntaxUID: String = TransferSyntax.explicitVRLittleEndian.uid,
        bitsAllocated: UInt16 = 8, bitsStored: UInt16 = 8, signed: Bool = false,
        samples: UInt16 = 1, photometric: String = "MONOCHROME2", frames: Int = 1,
        rows: UInt16 = 8, cols: UInt16 = 8
    ) -> DICOMFile {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6.7.8", for: .sopInstanceUID, vr: .UI)
        ds.setUInt16(rows, for: .rows)
        ds.setUInt16(cols, for: .columns)
        ds.setUInt16(bitsAllocated, for: .bitsAllocated)
        ds.setUInt16(bitsStored, for: .bitsStored)
        ds.setUInt16(bitsStored - 1, for: .highBit)
        ds.setUInt16(signed ? 1 : 0, for: .pixelRepresentation)
        ds.setUInt16(samples, for: .samplesPerPixel)
        ds.setString(photometric, for: .photometricInterpretation, vr: .CS)
        if samples > 1 { ds.setUInt16(0, for: .planarConfiguration) }
        if frames > 1 { ds.setString("\(frames)", for: .numberOfFrames, vr: .IS) }
        let bytes = Int(rows) * Int(cols) * Int(samples) * Int(bitsAllocated / 8) * frames
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: bitsAllocated > 8 ? .OW : .OB,
                                          data: Data(count: bytes))
        return DICOMFile.create(dataSet: ds, transferSyntaxUID: transferSyntaxUID)
    }

    private func failure(
        _ file: DICOMFile, _ target: TransferSyntax, intent: EncodingIntent = .notApplicable,
        file path: StaticString = #filePath, line: UInt = #line
    ) -> ConversionFailure? {
        do {
            try DICOMConverter.checkConversion(
                dicomFile: file, to: SelectableEncoding(transferSyntax: target, intent: intent))
            XCTFail("expected the check to reject \(target.uid)", file: path, line: line)
            return nil
        } catch let failure as ConversionFailure {
            return failure
        } catch {
            XCTFail("expected ConversionFailure, got \(error)", file: path, line: line)
            return nil
        }
    }

    private func assertAccepted(
        _ file: DICOMFile, _ target: TransferSyntax, intent: EncodingIntent = .notApplicable,
        file path: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertNoThrow(try DICOMConverter.checkConversion(
            dicomFile: file, to: SelectableEncoding(transferSyntax: target, intent: intent)),
            file: path, line: line)
    }

    // MARK: - JPEG XL JPEG Recompression (…4.111)

    func testRecompression_rejectsLosslessJPEGSource() throws {
        let f = try XCTUnwrap(failure(
            makeFile(transferSyntaxUID: TransferSyntax.jpegLossless.uid, samples: 3, photometric: "RGB"),
            .jpegXLRecompression))
        XCTAssertEqual(f.category, .recompressionSource)
        XCTAssertTrue(f.reason.contains("SOF3"), f.reason)
        XCTAssertTrue(f.headline?.contains("JPEG Lossless, Non-Hierarchical (Process 14) [1.2.840.10008.1.2.4.57]") == true)  // PS3.6 Table A-1 (D176)
        XCTAssertTrue(f.suggestion?.contains("jxl-lossless-only") == true)
        XCTAssertEqual(f.sourceDetails?.contains("3 samples per pixel, RGB"), true)
    }

    func testRecompression_rejectsUncompressedSource() throws {
        let f = try XCTUnwrap(failure(makeFile(), .jpegXLRecompression))
        XCTAssertEqual(f.category, .recompressionSource)
        XCTAssertTrue(f.reason.contains("uncompressed"), f.reason)
    }

    func testRecompression_rejects12BitExtendedSource() throws {
        let f = try XCTUnwrap(failure(
            makeFile(transferSyntaxUID: TransferSyntax.jpegExtended.uid, bitsAllocated: 16, bitsStored: 12),
            .jpegXLRecompression))
        XCTAssertEqual(f.category, .recompressionSource)
        XCTAssertTrue(f.reason.contains("12-bit"), f.reason)
    }

    func testRecompression_rejectsMonochrome1() throws {
        let f = try XCTUnwrap(failure(
            makeFile(transferSyntaxUID: TransferSyntax.jpegBaseline.uid, photometric: "MONOCHROME1"),
            .jpegXLRecompression))
        XCTAssertTrue(f.reason.contains("MONOCHROME1"), f.reason)
    }

    // PS3.5 2026a Table 8.2.15-1, .111 rows: MONOCHROME2 with 1 sample; YBR_FULL_422, XYB or RGB with 3.
    func testRecompression_rejectsPhotometricOutsideTable8_2_15_1() throws {
        let palette = try XCTUnwrap(failure(
            makeFile(transferSyntaxUID: TransferSyntax.jpegBaseline.uid, photometric: "PALETTE COLOR"),
            .jpegXLRecompression))
        XCTAssertTrue(palette.reason.contains("only MONOCHROME2"), palette.reason)
        let ybrFull = try XCTUnwrap(failure(
            makeFile(transferSyntaxUID: TransferSyntax.jpegBaseline.uid, samples: 3, photometric: "YBR_FULL"),
            .jpegXLRecompression))
        XCTAssertTrue(ybrFull.reason.contains("YBR_FULL_422, XYB or RGB"), ybrFull.reason)
    }

    func testRecompression_acceptsTable8_2_15_1ColourRows() {
        for pi in ["YBR_FULL_422", "RGB"] {
            assertAccepted(makeFile(transferSyntaxUID: TransferSyntax.jpegBaseline.uid, samples: 3, photometric: pi),
                           .jpegXLRecompression)
        }
    }

    func testRecompression_acceptsBaselineAndExtended8Bit() {
        assertAccepted(makeFile(transferSyntaxUID: TransferSyntax.jpegBaseline.uid), .jpegXLRecompression)
        assertAccepted(makeFile(transferSyntaxUID: TransferSyntax.jpegExtended.uid), .jpegXLRecompression)
    }

    // MARK: - Pixel format vs target encoder

    func testSigned8Bit_toJPEGBaseline_explainsSignedLimit() throws {
        let f = try XCTUnwrap(failure(makeFile(signed: true), .jpegBaseline))
        XCTAssertEqual(f.category, .pixelFormatNotSupported)
        XCTAssertTrue(f.reason.contains("signed"), f.reason)
        XCTAssertTrue(f.suggestion?.contains("JPEG-LS") == true)
    }

    func testSigned8Bit_toJPEGXL_explainsNoSigned8BitType() throws {
        let f = try XCTUnwrap(failure(makeFile(signed: true), .jpegXLLossless))
        XCTAssertEqual(f.category, .pixelFormatNotSupported)
        XCTAssertTrue(f.reason.contains("no signed 8-bit"), f.reason)
    }

    func test32Bit_toJPEG2000_explainsBitsAllocated() throws {
        let f = try XCTUnwrap(failure(makeFile(bitsAllocated: 32, bitsStored: 32), .jpeg2000Lossless))
        XCTAssertEqual(f.category, .pixelFormatNotSupported)
        XCTAssertTrue(f.reason.contains("Bits Allocated 8 or 16"), f.reason)
        XCTAssertTrue(f.reason.contains("32"), f.reason)
        XCTAssertTrue(f.suggestion?.contains("uncompressed") == true)
    }

    func test16BitTo8BitOnlyTarget_isAcceptedBecauseTheTranscoderWindowsItDown() {
        // The transcoder rescales 16-bit data to 8-bit for JPEG Baseline; the check
        // must not reject what the conversion itself supports.
        assertAccepted(makeFile(bitsAllocated: 16, bitsStored: 16), .jpegBaseline)
    }

    func testCommonFormats_areAccepted() {
        assertAccepted(makeFile(bitsAllocated: 16, bitsStored: 12, signed: true), .jpegLSLossless)
        assertAccepted(makeFile(bitsAllocated: 16, bitsStored: 16, signed: true), .jpegXLLossless)
        assertAccepted(makeFile(samples: 3, photometric: "RGB"), .htj2kLossless)
        assertAccepted(makeFile(bitsAllocated: 16, bitsStored: 12), .jpegExtended)
        assertAccepted(makeFile(bitsAllocated: 32, bitsStored: 32), .explicitVRLittleEndian)
    }

    // MARK: - Source transfer syntax

    func testUnknownSourceUID_isRejectedInsteadOfReadAsUncompressed() throws {
        let f = try XCTUnwrap(failure(makeFile(transferSyntaxUID: "1.2.3.4.999"), .jpegXLLossless))
        XCTAssertEqual(f.category, .unsupportedSource)
        XCTAssertTrue(f.reason.contains("1.2.3.4.999"), f.reason)
    }

    // MARK: - Shared formatting

    func testFailureReport_isTheSameTextForTheCLIAndTheApp() throws {
        let f = try XCTUnwrap(failure(makeFile(signed: true), .jpegBaseline))
        let report = ConvertConsole.failureReport(for: f)
        XCTAssertTrue(report.hasPrefix("❌ Conversion failed\nCannot convert "), report)
        XCTAssertTrue(report.contains("\nReason: "), report)
        XCTAssertTrue(report.contains("\nSource: Bits Allocated 8"), report)
        XCTAssertTrue(report.contains("\nSuggestion: "), report)
        XCTAssertEqual(f.errorDescription, f.message, "localizedDescription must carry the same text")
    }

    func testFailureReport_neverFallsBackToFoundationErrorN() {
        struct PlainError: Error, CustomStringConvertible { var description: String { "--flag is required" } }
        let report = ConvertConsole.failureReport(for: PlainError())
        XCTAssertEqual(report, "❌ Conversion failed\n--flag is required\n")
        XCTAssertFalse(report.contains("couldn’t be completed"))
    }

    func testFailureReport_explainsANonDICOMInput() {
        let report = ConvertConsole.failureReport(for: DICOMError.invalidDICMPrefix)
        XCTAssertTrue(report.contains("Cannot read the input as a DICOM file."), report)
        XCTAssertTrue(report.contains("--force"), report)
    }

    func testConvertToDICOM_throwsConversionFailureWithSourceAndTarget() {
        XCTAssertThrowsError(try DICOMConverter.convertToDICOM(
            dicomFile: makeFile(signed: true), to: .jpegBaseline, stripPrivate: false)) { error in
            let failure = error as? ConversionFailure
            XCTAssertNotNil(failure)
            XCTAssertTrue(failure?.headline?.contains("Explicit VR Little Endian") == true)
            XCTAssertTrue(failure?.headline?.contains("JPEG Baseline") == true)
        }
    }

    func testBatchSummary_isOneLine() throws {
        let f = try XCTUnwrap(failure(makeFile(signed: true), .jpegBaseline))
        XCTAssertFalse(ConvertConsole.failureSummary(for: f).contains("\n"))
    }
}
