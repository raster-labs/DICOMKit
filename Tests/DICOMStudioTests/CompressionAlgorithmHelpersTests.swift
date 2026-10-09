// CompressionAlgorithmHelpersTests.swift
// DICOMStudioTests
//
// The Data Exchange compression picker: every row's label carries the PS3.6 Table A-1
// name and the UID its dicom-compress token really produces (D9; DICOMCLI part 4 "codec").

#if canImport(SwiftUI)
import Testing
@testable import DICOMStudio
import DICOMCore
import Foundation

@Suite("CompressionAlgorithmHelpers")
struct CompressionAlgorithmHelpersTests {

    @Test("Every row is labelled by the catalog: Table A-1 name plus the UID the token produces")
    func testLabelsResolveThroughTheCatalog() throws {
        let rows = CompressionAlgorithmHelpers.algorithms
        #expect(rows.count == 12)
        #expect(Set(rows.map(\.cli)).count == rows.count, "tokens are distinct")
        for row in rows {
            let enc = try #require(TransferSyntax.parseEncoding(row.cli), "\(row.cli)")
            #expect(row.label == "\(enc.displayName) (\(enc.uid))", "\(row.cli)")
            #expect(row.label.contains(enc.transferSyntax.displayName), "Table A-1 name of \(row.cli)")
        }
    }

    @Test("The UIDs the labels claim are the ones the tokens produce (PS3.6 2026a Table A-1)")
    func testClaimedUIDs() throws {
        func uid(_ cli: String) -> String? {
            CompressionAlgorithmHelpers.algorithms.first { $0.cli == cli }
                .flatMap { TransferSyntax.parseEncoding($0.cli)?.uid }
        }
        // jpeg-lossless is JPEG Lossless, Non-Hierarchical (Process 14) — .57, not .70.
        #expect(uid("jpeg-lossless") == "1.2.840.10008.1.2.4.57")
        // j2k-lossless / htj2k-lossless are reversible codestreams in the general UIDs.
        #expect(uid("j2k-lossless") == "1.2.840.10008.1.2.4.91")
        #expect(uid("j2k") == "1.2.840.10008.1.2.4.91")
        #expect(uid("htj2k-lossless") == "1.2.840.10008.1.2.4.203")
        #expect(uid("htj2k") == "1.2.840.10008.1.2.4.203")
        #expect(uid("htj2k-rpcl") == "1.2.840.10008.1.2.4.202")
        #expect(uid("jpeg-xl-lossless-only") == "1.2.840.10008.1.2.4.110")
        #expect(uid("jpeg-xl") == "1.2.840.10008.1.2.4.112")
        #expect(uid("rle") == "1.2.840.10008.1.2.5")
        #expect(uid("jpeg-baseline") == "1.2.840.10008.1.2.4.50")
        #expect(uid("jpeg-ls-lossless") == "1.2.840.10008.1.2.4.80")
        #expect(uid("jpeg-ls") == "1.2.840.10008.1.2.4.81")
        let labelFor = { (cli: String) in CompressionAlgorithmHelpers.algorithms.first { $0.cli == cli }?.label ?? "" }
        #expect(labelFor("jpeg-lossless").hasSuffix("(1.2.840.10008.1.2.4.57)"))
        #expect(labelFor("jpeg-xl-lossless-only") == "JPEG XL Lossless (1.2.840.10008.1.2.4.110)")
    }

    @Test("isLossy agrees with the catalog's intent for every row")
    func testLossyFlagMatchesIntent() throws {
        for row in CompressionAlgorithmHelpers.algorithms {
            let enc = try #require(TransferSyntax.parseEncoding(row.cli), "\(row.cli)")
            #expect(CompressionAlgorithmHelpers.isLossy(row.cli) == !enc.isLossless, "\(row.cli)")
        }
    }
}
#endif
