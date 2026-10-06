// ConverterTableA1KeywordTests.swift
// DICOM 2026a deferred row D268: the 7 PS3.6 2026a Table A-1 keywords `dicom-convert` added on
// top of the DICOMConverter catalog, and the composed `--transfer-syntax` help, live in the
// catalog (DICOMConverter.additionalTableA1Keywords / transferSyntaxOptionHelpWithKeywords).

import XCTest
import DICOMCore
import DICOMDictionary
@testable import DICOMKit

final class ConverterTableA1KeywordTests: XCTestCase {

    /// PS3.6 2026a Table A-1 keyword column of the 7 UIDs, dumped from part06_2026a.xml by script.
    private static let tableA1: [String: String] = [
        "DeflatedExplicitVRLittleEndian": "1.2.840.10008.1.2.1.99",
        "JPEGBaseline8Bit": "1.2.840.10008.1.2.4.50",
        "JPEGExtended12Bit": "1.2.840.10008.1.2.4.51",
        "JPEG2000MCLossless": "1.2.840.10008.1.2.4.92",
        "JPEG2000MC": "1.2.840.10008.1.2.4.93",
        "JPEGXLJPEGRecompression": "1.2.840.10008.1.2.4.111",
        "HTJ2KLosslessRPCL": "1.2.840.10008.1.2.4.202",
    ]

    func testTheSevenKeywordsAreTableA1RowsOfCatalogTargets() {
        XCTAssertEqual(DICOMConverter.additionalTableA1Keywords, Self.tableA1)
        let targetUIDs = Set(DICOMConverter.targetSyntaxes.map(\.uid))
        for (keyword, uid) in Self.tableA1 {
            XCTAssertTrue(targetUIDs.contains(uid), keyword)
            XCTAssertEqual(UIDDictionary.lookup(uid: uid)?.keyword, keyword, "DICOMDictionary Table A-1 keyword")
            XCTAssertFalse(DICOMConverter.cliTokens.contains(keyword), "\(keyword) is already a cliToken")
        }
    }

    func testKeywordsResolveToTheirUIDCaseInsensitively() {
        for (keyword, uid) in Self.tableA1 {
            for spelling in [keyword, keyword.lowercased(), keyword.uppercased(), " \(keyword)\n"] {
                XCTAssertEqual(DICOMConverter.resolveTarget(spelling)?.syntax.uid, uid, spelling)
                XCTAssertEqual(DICOMConverter.resolveTargetEncoding(spelling)?.transferSyntax.uid, uid, spelling)
            }
        }
        // A keyword of a shared (lossy + lossless) UID selects the lossy target, like a bare UID.
        XCTAssertEqual(DICOMConverter.resolveTarget("JPEG2000MC")?.cliToken, "JPEG2000Part2Lossy")
        XCTAssertEqual(DICOMConverter.resolveTarget("JPEG2000MCLossless")?.cliToken, "JPEG2000Part2LosslessOnly")
        XCTAssertEqual(DICOMConverter.resolveTarget("HTJ2KLosslessRPCL")?.cliToken, "HTJ2KRPCLLosslessOnly")
        XCTAssertNil(DICOMConverter.resolveTarget("bogus"))
    }

    func testComposedHelpListsEveryKeywordAndTheReversibleNames() {
        let help = DICOMConverter.transferSyntaxOptionHelpWithKeywords
        XCTAssertTrue(help.hasPrefix(DICOMConverter.transferSyntaxOptionHelp + ". Also a Transfer Syntax UID or a PS3.6 Table A-1 keyword ("))
        let listed = (Self.tableA1.keys + TransferSyntax.reassignedTableA1Keywords.map(\.keyword)).sorted().joined(separator: ", ")
        XCTAssertTrue(help.contains("(" + listed + "); every Table A-1 keyword selects its Table A-1 UID."), help)
        XCTAssertTrue(help.hasSuffix("Changed: JPEG2000Lossless, HTJ2KLossless and JPEGXLLossless now select .90 / .201 / .110; "
                                     + "the reversible encode into .91 / .203 / .112 is JPEG2000Reversible, HTJ2KReversible, JPEGXLReversible."))
    }
}
