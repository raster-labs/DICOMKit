// CompressionNativeTargetTests.swift
// DICOM 2026a deferred row D267: the native `--syntax` targets of `dicom-compress decompress` /
// `batch` and the DICOMStudio Workshop are CompressionConsole.NativeTargetSyntax — the PS3.6
// 2026a Table A-1 UIDs of PS3.5 2026a A.1, A.2, A.5 and the retired A.3; every encapsulated
// codec is refused.

import XCTest
import DICOMCore
@testable import DICOMKit

final class CompressionNativeTargetTests: XCTestCase {

    /// PS3.6 2026a Table A-1 (UID, Name) of the native targets, dumped from part06_2026a.xml.
    private static let tableA1: [(name: String, uid: String, a1Name: String)] = [
        ("explicit-le", "1.2.840.10008.1.2.1", "Explicit VR Little Endian"),
        ("implicit-le", "1.2.840.10008.1.2", "Implicit VR Little Endian: Default Transfer Syntax for DICOM"),
        ("deflate", "1.2.840.10008.1.2.1.99", "Deflated Explicit VR Little Endian"),
        ("explicit-be", "1.2.840.10008.1.2.2", "Explicit VR Big Endian (Retired)"),
    ]

    func testTheFourNativeTargetsAndTheirTableA1UIDs() throws {
        XCTAssertEqual(CompressionConsole.NativeTargetSyntax.accepted.map(\.name), Self.tableA1.map(\.name))
        for row in Self.tableA1 {
            let syntax = try CompressionConsole.NativeTargetSyntax.resolve(row.name)
            XCTAssertEqual(syntax.uid, row.uid, row.name)
            XCTAssertFalse(syntax.isEncapsulated, row.name)
            XCTAssertEqual(try CompressionConsole.NativeTargetSyntax.resolve(" " + row.name.uppercased() + " ").uid, row.uid, "case- and space-insensitive")
        }
    }

    func testEveryEncapsulatedCodecNameIsRefusedWithTheClauseText() {
        let encapsulated = CompressionManager.supportedCodecs().filter { $0.syntax.isEncapsulated }
        XCTAssertGreaterThan(encapsulated.count, 10)
        for codec in encapsulated {
            for name in [codec.name] + codec.aliases {
                XCTAssertThrowsError(try CompressionConsole.NativeTargetSyntax.resolve(name), name) { error in
                    guard let refused = error as? CompressionConsole.NativeTargetSyntax.Refused else { return XCTFail(name) }
                    XCTAssertEqual(refused.description,
                                   "--syntax \(name) names \(codec.syntax.uid), an encapsulated (compressed) Transfer Syntax "
                                   + "(PS3.6 2026a Table A-1); decompression writes native Pixel Data (PS3.5 2026a A.1, A.2, A.5). "
                                   + "Native targets: explicit-le, implicit-le, deflate, explicit-be. To compress, use `compress --codec`.")
                    XCTAssertEqual(refused.errorDescription, refused.description)
                }
            }
        }
    }

    func testUnknownValueIsRefused() {
        XCTAssertThrowsError(try CompressionConsole.NativeTargetSyntax.resolve("bogus")) { error in
            XCTAssertEqual((error as? CompressionConsole.NativeTargetSyntax.Refused)?.description,
                           "Unknown syntax 'bogus'. Native targets: explicit-le, implicit-le, deflate, explicit-be")
        }
    }
}
