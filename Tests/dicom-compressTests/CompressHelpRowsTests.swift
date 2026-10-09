//
// CompressHelpRowsTests.swift
// dicom-compress
//
// Pins the codec / syntax rows of `compress --help` and `decompress --help` to PS3.6 2026a
// Table A-1 (D9, dfc929c, had no test): each row's first name must resolve, through the
// shared CompressionManager codec table, to the UID and lossy/lossless intent the row
// describes, and the row's label must use the Table A-1 name's words ("HTJ2K" stands for
// "High-Throughput JPEG 2000"). "Lossless Only" may appear only where Table A-1 says it
// (.4.110 is "JPEG XL Lossless").
//

import XCTest
import DICOMCore
import DICOMKit
@testable import dicom_compress

final class CompressHelpRowsTests: XCTestCase {

    /// PS3.6 2026a Table A-1 names of every UID the rows name, dumped from part06_2026a.xml.
    private static let tableA1: [String: String] = [
        "1.2.840.10008.1.2": "Implicit VR Little Endian: Default Transfer Syntax for DICOM",
        "1.2.840.10008.1.2.1": "Explicit VR Little Endian",
        "1.2.840.10008.1.2.1.99": "Deflated Explicit VR Little Endian",
        "1.2.840.10008.1.2.4.50": "JPEG Baseline (Process 1): Default Transfer Syntax for Lossy JPEG 8 Bit Image Compression",
        "1.2.840.10008.1.2.4.51": "JPEG Extended (Process 2 & 4): Default Transfer Syntax for Lossy JPEG 12 Bit Image Compression (Process 4 only)",
        "1.2.840.10008.1.2.4.57": "JPEG Lossless, Non-Hierarchical (Process 14)",
        "1.2.840.10008.1.2.4.70": "JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14 [Selection Value 1]): Default Transfer Syntax for Lossless JPEG Image Compression",
        "1.2.840.10008.1.2.4.80": "JPEG-LS Lossless Image Compression",
        "1.2.840.10008.1.2.4.81": "JPEG-LS Lossy (Near-Lossless) Image Compression",
        "1.2.840.10008.1.2.4.90": "JPEG 2000 Image Compression (Lossless Only)",
        "1.2.840.10008.1.2.4.91": "JPEG 2000 Image Compression",
        "1.2.840.10008.1.2.4.92": "JPEG 2000 Part 2 Multi-component Image Compression (Lossless Only)",
        "1.2.840.10008.1.2.4.93": "JPEG 2000 Part 2 Multi-component Image Compression",
        "1.2.840.10008.1.2.4.110": "JPEG XL Lossless",
        "1.2.840.10008.1.2.4.112": "JPEG XL",
        "1.2.840.10008.1.2.4.201": "High-Throughput JPEG 2000 Image Compression (Lossless Only)",
        "1.2.840.10008.1.2.4.202": "High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only)",
        "1.2.840.10008.1.2.4.203": "High-Throughput JPEG 2000 Image Compression",
        "1.2.840.10008.1.2.5": "RLE Lossless",
    ]

    private struct Row { let name: String; let label: String; let suffix: String? }

    /// Rows are `  <name>[, <alias>]  <label>  [(.<last UID arc>)]`.
    private static func rows(_ discussion: String) -> [Row] {
        let pattern = #"^\s{2}([a-z0-9][a-z0-9-]*)(?:, \S+)?\s{2,}(.+?)\s*(?:\(\.(\d+)\))?\s*$"#
        let regex = try! NSRegularExpression(pattern: pattern)
        return discussion.split(separator: "\n").compactMap { line in
            let s = String(line)
            guard !s.contains("dicom-compress"),
                  let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            func group(_ i: Int) -> String? {
                Range(m.range(at: i), in: s).map { String(s[$0]) }
            }
            return Row(name: group(1)!, label: group(2)!, suffix: group(3))
        }
    }

    private static func words(_ s: String) -> [String] {
        s.lowercased()
            .replacingOccurrences(of: "htj2k", with: "high throughput jpeg 2000")
            .replacingOccurrences(of: "sv1", with: "selection value 1")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func check(_ row: Row, file: StaticString = #filePath, line: UInt = #line) {
        guard let encoding = CompressionManager.resolveEncoding(for: row.name) else {
            return XCTFail("\(row.name) does not resolve", file: file, line: line)
        }
        let uid = encoding.transferSyntax.uid
        guard let a1 = Self.tableA1[uid] else {
            return XCTFail("\(row.name) → \(uid) is not a Table A-1 row here", file: file, line: line)
        }
        if let suffix = row.suffix {
            XCTAssertTrue(uid.hasSuffix("." + suffix), "\(row.name): (.\(suffix)) but resolves to \(uid)", file: file, line: line)
        }
        // Label = Table A-1 words, plus an intent gloss (", lossy" / ", lossless") or a note
        // in parentheses (bit depths per PS3.5 Table 8.2.1-1, "default").
        var label = row.label
        let lossy = label.hasSuffix(", lossy"), lossless = label.hasSuffix(", lossless")
        if lossy || lossless { label = String(label[..<label.lastIndex(of: ",")!]) }
        if let paren = label.firstIndex(of: "("), !label.contains("Process") {
            label = String(label[..<paren])
        }
        let std = Self.words(a1)
        for w in Self.words(label) where w != "near" {
            XCTAssertTrue(std.contains(w), "\(row.name): \"\(w)\" is not in \"\(a1)\"", file: file, line: line)
        }
        if row.label.lowercased().contains("lossless only") {
            XCTAssertTrue(a1.contains("(Lossless Only)"), "\(row.name): Table A-1 name is \"\(a1)\"", file: file, line: line)
        }
        if lossy { XCTAssertFalse(encoding.isLossless, "\(row.name)", file: file, line: line) }
        if lossless { XCTAssertTrue(encoding.isLossless, "\(row.name)", file: file, line: line) }
    }

    func test_compressRows_matchTableA1() {
        let rows = Self.rows(DICOMCompress.Compress.configuration.discussion)
        XCTAssertEqual(rows.count, 23)
        for row in rows { check(row) }
    }

    func test_decompressRows_matchTableA1() throws {
        let rows = Self.rows(DICOMCompress.Decompress.configuration.discussion)
        XCTAssertEqual(rows.map(\.name), ["explicit-le", "implicit-le", "deflate", "explicit-be"])
        for row in rows where row.name != "explicit-be" { check(row) }
        // explicit-be is a decompress target only (not a --codec name); Table A-1 2026a:
        // 1.2.840.10008.1.2.2 "Explicit VR Big Endian (Retired)" (dumped from part06_2026a.xml).
        let be = try XCTUnwrap(rows.first { $0.name == "explicit-be" })
        XCTAssertTrue(be.label.hasPrefix("Explicit VR Big Endian (Retired)"), be.label)
        XCTAssertEqual(try NativeTargetSyntax.resolve("explicit-be").uid, "1.2.840.10008.1.2.2")
    }

    func test_jpegXLLosslessOnly_isNamedAsTableA1_D9() {
        let row = Self.rows(DICOMCompress.Compress.configuration.discussion)
            .first { $0.name == "jpeg-xl-lossless-only" }
        XCTAssertEqual(row?.label, "JPEG XL Lossless")
        XCTAssertEqual(CompressionManager.transferSyntax(for: "jpeg-xl-lossless-only")?.uid, "1.2.840.10008.1.2.4.110")
    }
}
