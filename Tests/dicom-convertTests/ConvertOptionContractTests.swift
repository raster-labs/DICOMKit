//
// ConvertOptionContractTests.swift
// dicom-convert
//
// --transfer-syntax: every PS3.6 2026a Table A-1 keyword the tool accepts selects its Table A-1
// UID (P-CONVERT-TS-KEYWORDS: JPEG2000Lossless / HTJ2KLossless / JPEGXLLossless now .90 / .201 /
// .110; the old meaning is JPEG2000Reversible / HTJ2KReversible / JPEGXLReversible).
// --window-width follows PS3.3 2026a C.11.2.1.2.1 ("shall always be greater than or equal to
// 1"); --frame-number is 1-based per PS3.3 2026a Table 10-3 (P-CONVERT-FRAME); a directory run
// with a failed file exits 1 (P-CONVERT-EXIT).
//

import XCTest
import ArgumentParser
import DICOMCore
import DICOMKit
@testable import dicom_convert

final class ConvertOptionContractTests: XCTestCase {

    /// Every Transfer Syntax row of PS3.6 2026a Table A-1 (keyword → UID, 63 rows), dumped by
    /// Scripts/nema_docbook.py from part06_2026a.xml.
    private static let tableA1: [String: String] = [
        "ImplicitVRLittleEndian": "1.2.840.10008.1.2",
        "ExplicitVRLittleEndian": "1.2.840.10008.1.2.1",
        "EncapsulatedUncompressedExplicitVRLittleEndian": "1.2.840.10008.1.2.1.98",
        "DeflatedExplicitVRLittleEndian": "1.2.840.10008.1.2.1.99",
        "ExplicitVRBigEndian": "1.2.840.10008.1.2.2",
        "MPEG2MPML": "1.2.840.10008.1.2.4.100",
        "MPEG2MPMLF": "1.2.840.10008.1.2.4.100.1",
        "MPEG2MPHL": "1.2.840.10008.1.2.4.101",
        "MPEG2MPHLF": "1.2.840.10008.1.2.4.101.1",
        "MPEG4HP41": "1.2.840.10008.1.2.4.102",
        "MPEG4HP41F": "1.2.840.10008.1.2.4.102.1",
        "MPEG4HP41BD": "1.2.840.10008.1.2.4.103",
        "MPEG4HP41BDF": "1.2.840.10008.1.2.4.103.1",
        "MPEG4HP422D": "1.2.840.10008.1.2.4.104",
        "MPEG4HP422DF": "1.2.840.10008.1.2.4.104.1",
        "MPEG4HP423D": "1.2.840.10008.1.2.4.105",
        "MPEG4HP423DF": "1.2.840.10008.1.2.4.105.1",
        "MPEG4HP42STEREO": "1.2.840.10008.1.2.4.106",
        "MPEG4HP42STEREOF": "1.2.840.10008.1.2.4.106.1",
        "HEVCMP51": "1.2.840.10008.1.2.4.107",
        "HEVCM10P51": "1.2.840.10008.1.2.4.108",
        "JPEGXLLossless": "1.2.840.10008.1.2.4.110",
        "JPEGXLJPEGRecompression": "1.2.840.10008.1.2.4.111",
        "JPEGXL": "1.2.840.10008.1.2.4.112",
        "HTJ2KLossless": "1.2.840.10008.1.2.4.201",
        "HTJ2KLosslessRPCL": "1.2.840.10008.1.2.4.202",
        "HTJ2K": "1.2.840.10008.1.2.4.203",
        "JPIPHTJ2KReferenced": "1.2.840.10008.1.2.4.204",
        "JPIPHTJ2KReferencedDeflate": "1.2.840.10008.1.2.4.205",
        "JPEGBaseline8Bit": "1.2.840.10008.1.2.4.50",
        "JPEGExtended12Bit": "1.2.840.10008.1.2.4.51",
        "JPEGExtended35": "1.2.840.10008.1.2.4.52",
        "JPEGSpectralSelectionNonHierarchical68": "1.2.840.10008.1.2.4.53",
        "JPEGSpectralSelectionNonHierarchical79": "1.2.840.10008.1.2.4.54",
        "JPEGFullProgressionNonHierarchical1012": "1.2.840.10008.1.2.4.55",
        "JPEGFullProgressionNonHierarchical1113": "1.2.840.10008.1.2.4.56",
        "JPEGLossless": "1.2.840.10008.1.2.4.57",
        "JPEGLosslessNonHierarchical15": "1.2.840.10008.1.2.4.58",
        "JPEGExtendedHierarchical1618": "1.2.840.10008.1.2.4.59",
        "JPEGExtendedHierarchical1719": "1.2.840.10008.1.2.4.60",
        "JPEGSpectralSelectionHierarchical2022": "1.2.840.10008.1.2.4.61",
        "JPEGSpectralSelectionHierarchical2123": "1.2.840.10008.1.2.4.62",
        "JPEGFullProgressionHierarchical2426": "1.2.840.10008.1.2.4.63",
        "JPEGFullProgressionHierarchical2527": "1.2.840.10008.1.2.4.64",
        "JPEGLosslessHierarchical28": "1.2.840.10008.1.2.4.65",
        "JPEGLosslessHierarchical29": "1.2.840.10008.1.2.4.66",
        "JPEGLosslessSV1": "1.2.840.10008.1.2.4.70",
        "JPEGLSLossless": "1.2.840.10008.1.2.4.80",
        "JPEGLSNearLossless": "1.2.840.10008.1.2.4.81",
        "JPEG2000Lossless": "1.2.840.10008.1.2.4.90",
        "JPEG2000": "1.2.840.10008.1.2.4.91",
        "JPEG2000MCLossless": "1.2.840.10008.1.2.4.92",
        "JPEG2000MC": "1.2.840.10008.1.2.4.93",
        "JPIPReferenced": "1.2.840.10008.1.2.4.94",
        "JPIPReferencedDeflate": "1.2.840.10008.1.2.4.95",
        "RLELossless": "1.2.840.10008.1.2.5",
        "RFC2557MIMEEncapsulation": "1.2.840.10008.1.2.6.1",
        "XMLEncoding": "1.2.840.10008.1.2.6.2",
        "SMPTEST211020UncompressedProgressiveActiveVideo": "1.2.840.10008.1.2.7.1",
        "SMPTEST211020UncompressedInterlacedActiveVideo": "1.2.840.10008.1.2.7.2",
        "SMPTEST211030PCMDigitalAudio": "1.2.840.10008.1.2.7.3",
        "DeflatedImageFrameCompression": "1.2.840.10008.1.2.8.1",
        "Papyrus3ImplicitVRLittleEndian": "1.2.840.10008.1.20",
    ]

    /// The keywords of the 21 UIDs the shared catalog can target.
    private static var catalogKeywords: [String: String] {
        let uids = Set(DICOMConverter.targetSyntaxes.map(\.uid))
        return tableA1.filter { uids.contains($0.value) }
    }

    func test_everyAcceptedTableA1Keyword_selectsItsTableA1UID() {
        XCTAssertEqual(Self.catalogKeywords.count, 21, "the catalog's target UIDs changed; re-dump Table A-1")
        var accepted = 0
        for (keyword, uid) in Self.tableA1 {
            guard let resolved = TransferSyntaxKeywords.resolve(keyword)?.transferSyntax.uid else {
                XCTAssertNil(Self.catalogKeywords[keyword], "\(keyword) names a catalog UID but is refused")
                continue
            }
            accepted += 1
            XCTAssertEqual(resolved, uid, keyword)
            XCTAssertEqual(TransferSyntaxKeywords.resolve(keyword.lowercased())?.transferSyntax.uid,
                           uid, "\(keyword) case-insensitive")
        }
        XCTAssertEqual(accepted, 21)
    }

    func test_reassignedKeywords_tableA1UIDs_andReversibleNames() throws {
        let rows = TransferSyntax.reassignedTableA1Keywords
        XCTAssertEqual(rows.map(\.keyword), ["JPEG2000Lossless", "HTJ2KLossless", "JPEGXLLossless"])
        for row in rows {
            XCTAssertEqual(Self.tableA1[row.keyword], row.uid, row.keyword)
            let keyword = try XCTUnwrap(TransferSyntaxKeywords.resolve(row.keyword))
            XCTAssertEqual(keyword.transferSyntax.uid, row.uid)
            XCTAssertTrue(keyword.isLossless)
            // The old meaning: reversible encode into the general UID.
            let reversible = try XCTUnwrap(TransferSyntaxKeywords.resolve(row.reversibleName), row.reversibleName)
            XCTAssertEqual(reversible.transferSyntax.uid, row.generalUID)
            XCTAssertEqual(reversible.intent, .lossless)
            XCTAssertTrue(Self.tableA1.values.contains(row.generalUID))
            // stderr note for one release.
            let note = try XCTUnwrap(TransferSyntaxKeywords.meaningChangeNote(for: row.keyword.lowercased()))
            XCTAssertTrue(note.contains(row.uid) && note.contains(row.reversibleName) && note.contains("Table A-1"), note)
        }
        XCTAssertNil(TransferSyntaxKeywords.meaningChangeNote(for: "JPEG2000LosslessOnly"))
        XCTAssertNil(TransferSyntaxKeywords.meaningChangeNote(for: "jpeg2000-lossless"))
    }

    func test_addedKeywords_areCatalogKeywordsOfTheirTableA1UID() {
        // D268: the 7 keywords live in the DICOMConverter catalog, which resolves them itself.
        for (keyword, uid) in TransferSyntaxKeywords.additional {
            XCTAssertEqual(DICOMConverter.resolveTargetEncoding(keyword)?.transferSyntax.uid, uid, keyword)
            XCTAssertEqual(uid, Self.tableA1[keyword], keyword)
            XCTAssertFalse(DICOMConverter.cliTokens.contains(keyword), "\(keyword) is a cliToken; it is not additional")
        }
        XCTAssertEqual(TransferSyntaxKeywords.additional, DICOMConverter.additionalTableA1Keywords)
        XCTAssertEqual(TransferSyntaxKeywords.optionHelp, DICOMConverter.transferSyntaxOptionHelpWithKeywords)
    }

    func test_catalogNamesAndUIDs_stillResolve() {
        for target in DICOMConverter.targets {
            XCTAssertEqual(TransferSyntaxKeywords.resolve(target.cliToken)?.transferSyntax.uid, target.syntax.uid)
            XCTAssertNotNil(TransferSyntaxKeywords.resolve(target.syntax.uid))
        }
        XCTAssertNil(TransferSyntaxKeywords.resolve("bogus"))
    }

    func test_help_namesTheKeywordsAndTheReversibleNames() {
        let help = TransferSyntaxKeywords.optionHelp
        for keyword in TransferSyntaxKeywords.additional.keys { XCTAssertTrue(help.contains(keyword), keyword) }
        for row in TransferSyntax.reassignedTableA1Keywords {
            XCTAssertTrue(help.contains(row.keyword) && help.contains(row.reversibleName), row.keyword)
        }
    }

    // MARK: - Ranges

    func test_windowWidth_belowOne_isRefused_C112121() {
        XCTAssertThrowsError(try DICOMConvert.parse(["in.dcm", "-o", "o.png", "--window-width", "0.5"]))
        XCTAssertThrowsError(try DICOMConvert.parse(["in.dcm", "-o", "o.png", "--window-width", "0"]))
        XCTAssertNoThrow(try DICOMConvert.parse(["in.dcm", "-o", "o.png", "--window-width", "1"]))
    }

    func test_quality_outsideDocumentedRange_isRefused() {
        XCTAssertThrowsError(try DICOMConvert.parse(["in.dcm", "-o", "o.jpg", "--quality", "0"]))
        XCTAssertThrowsError(try DICOMConvert.parse(["in.dcm", "-o", "o.jpg", "--quality", "101"]))
        XCTAssertNoThrow(try DICOMConvert.parse(["in.dcm", "-o", "o.jpg", "--quality", "100"]))
    }

    func test_negativeFrame_isRefused() {
        XCTAssertThrowsError(try DICOMConvert.parse(["in.dcm", "-o", "o.png", "--frame=-1"]))
        XCTAssertNoThrow(try DICOMConvert.parse(["in.dcm", "-o", "o.png", "--frame", "0"]))
    }

    // MARK: - Frame number (PS3.3 Table 10-3), P-CONVERT-FRAME

    func test_frameNumber_isOneBased() throws {
        XCTAssertEqual(try DICOMConvert.parse(["in.dcm", "-o", "o.png", "--frame-number", "3"]).frameIndex, 2)
        XCTAssertEqual(try DICOMConvert.parse(["in.dcm", "-o", "o.png", "--frame", "3"]).frameIndex, 3)
        XCTAssertEqual(try DICOMConvert.parse(["in.dcm", "-o", "o.png"]).frameIndex, 0)
        XCTAssertThrowsError(try DICOMConvert.parse(["in.dcm", "-o", "o.png", "--frame-number", "0"])) { error in
            XCTAssertEqual(DICOMConvert.exitCode(for: error), .validationFailure)
        }
    }

    func test_frameAndFrameNumber_together_exit1() {
        XCTAssertThrowsError(try DICOMConvert.parse(["in.dcm", "-o", "o.png", "--frame", "0", "--frame-number", "1"])) { error in
            XCTAssertEqual(DICOMConvert.exitCode(for: error), .failure)
        }
    }

    func test_help_marksFrameDeprecated() {
        let help = DICOMConvert.helpMessage()
        XCTAssertTrue(help.contains("--frame-number"))
        XCTAssertTrue(help.contains("deprecated: 0-based index; use --frame-number"))
    }

    /// D208: "The first Frame shall be denoted as Frame number 1" is PS3.3 2026a Table 10-3
    /// (Referenced Frame Number); C.7.6.6 does not say it.
    func test_frameNumberRule_citesTable10_3() {
        let help = DICOMConvert.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(help.contains("PS3.3 Table 10-3"), help)
        XCTAssertFalse(help.contains("C.7.6.6"), help)
        XCTAssertThrowsError(try DICOMConvert.parse(["in.dcm", "-o", "o.png", "--frame-number", "0"])) { error in
            XCTAssertTrue(DICOMConvert.message(for: error).contains("PS3.3 Table 10-3"))
        }
    }

    func test_invalidFrameNumberMessage_isOneBased() {
        XCTAssertEqual(ConversionError.invalidFrameNumber(5, 3).errorDescription,
                       "Frame number 5 does not exist. The file has 3 frames, numbered 1 to 3.")
    }

    // MARK: - Exit code, P-CONVERT-EXIT

    func test_directoryRun_withFailedFile_exits1() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("convert-exit-\(UUID().uuidString)")
        let input = root.appendingPathComponent("in")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a DICOM file".utf8).write(to: input.appendingPathComponent("bad.dcm"))
        var cmd = try DICOMConvert.parse([input.path, "-o", root.appendingPathComponent("out").path,
                                          "--recursive", "--transfer-syntax", "ExplicitVRLittleEndian"])
        do {
            try await cmd.run()
            XCTFail("a directory run with a failed file must exit 1")
        } catch let code as ExitCode {
            XCTAssertEqual(code, .failure)
        }
    }

    func test_directoryRun_withoutFiles_exits0() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("convert-exit0-\(UUID().uuidString)")
        let input = root.appendingPathComponent("in")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var cmd = try DICOMConvert.parse([input.path, "-o", root.appendingPathComponent("out").path,
                                          "--recursive", "--transfer-syntax", "ExplicitVRLittleEndian"])
        try await cmd.run()
    }

    func test_validateFlag_keepsItsSpelling() throws {
        let cmd = try DICOMConvert.parse(["in.dcm", "-o", "o.dcm", "--validate"])
        XCTAssertTrue(cmd.validateOutput)
    }
}
