// LossyImageCompressionAttributesTests.swift
// DICOMKitTests
//
// Covers the per-UID lossy/lossless encode-intent split and the DICOM Lossy Image
// Compression provenance attributes (0028,2110/2112/2114). Reference: PS3.5 A.4.4 /
// A.4.12, PS3.3 C.7.6.1.1.5.

import XCTest
import Foundation
@testable import DICOMKit
import DICOMCore

final class LossyImageCompressionAttributesTests: XCTestCase {

    // MARK: - Method Defined Terms (0028,2114) — single source of truth

    func testLossyImageCompressionMethodDefinedTerms() {
        XCTAssertEqual(TransferSyntax.jpegBaseline.lossyImageCompressionMethod, "ISO_10918_1")   // .50
        XCTAssertEqual(TransferSyntax.jpegExtended.lossyImageCompressionMethod, "ISO_10918_1")   // .51
        XCTAssertEqual(TransferSyntax.jpegLSNearLossless.lossyImageCompressionMethod, "ISO_14495_1") // .81
        XCTAssertEqual(TransferSyntax.jpeg2000.lossyImageCompressionMethod, "ISO_15444_1")       // .91
        XCTAssertEqual(TransferSyntax.jpeg2000Part2.lossyImageCompressionMethod, "ISO_15444_1")  // .93
        XCTAssertEqual(TransferSyntax.htj2kLossy.lossyImageCompressionMethod, "ISO_15444_15")    // .203
        XCTAssertEqual(TransferSyntax.jpegXL.lossyImageCompressionMethod, "ISO_18181_1")         // .112

        // Reversible-only syntaxes never populate the lossy attributes.
        XCTAssertNil(TransferSyntax.jpeg2000Lossless.lossyImageCompressionMethod)   // .90
        XCTAssertNil(TransferSyntax.jpeg2000Part2Lossless.lossyImageCompressionMethod) // .92
        XCTAssertNil(TransferSyntax.htj2kLossless.lossyImageCompressionMethod)      // .201
        XCTAssertNil(TransferSyntax.htj2kRPCLLossless.lossyImageCompressionMethod)  // .202
        XCTAssertNil(TransferSyntax.jpegXLLossless.lossyImageCompressionMethod)     // .110
        XCTAssertNil(TransferSyntax.jpegLSLossless.lossyImageCompressionMethod)     // .80
        XCTAssertNil(TransferSyntax.rleLossless.lossyImageCompressionMethod)
        XCTAssertNil(TransferSyntax.explicitVRLittleEndian.lossyImageCompressionMethod)
    }

    // MARK: - Attribute writer: set / append / no-op

    func testWriterSetsFlagRatioAndMethod() {
        var ds = DataSet(elements: [])
        CompressionManager.applyLossyImageCompressionAttributes(
            to: &ds, targetSyntax: .jpeg2000, uncompressedByteCount: 1000, compressedByteCount: 250)
        XCTAssertEqual(ds.string(for: .lossyImageCompression), "01")
        XCTAssertEqual(ds.strings(for: .lossyImageCompressionMethod), ["ISO_15444_1"])
        let ratios = ds.strings(for: .lossyImageCompressionRatio) ?? []
        XCTAssertEqual(ratios.count, 1)
        XCTAssertEqual(Double(ratios[0]), 4.0)   // 1000 / 250
    }

    /// "Once lossy, always lossy": a second lossy step appends parallel ratio + method
    /// values rather than overwriting the earlier history (PS3.3 C.7.6.1.1.5).
    func testWriterAppendsOnRecompression() {
        var ds = DataSet(elements: [])
        CompressionManager.applyLossyImageCompressionAttributes(
            to: &ds, targetSyntax: .jpeg2000, uncompressedByteCount: 1000, compressedByteCount: 250)  // 4:1
        CompressionManager.applyLossyImageCompressionAttributes(
            to: &ds, targetSyntax: .htj2kLossy, uncompressedByteCount: 1000, compressedByteCount: 100) // 10:1
        XCTAssertEqual(ds.string(for: .lossyImageCompression), "01")
        XCTAssertEqual(ds.strings(for: .lossyImageCompressionMethod), ["ISO_15444_1", "ISO_15444_15"])
        let ratios = ds.strings(for: .lossyImageCompressionRatio) ?? []
        XCTAssertEqual(ratios.count, 2)
        XCTAssertEqual(Double(ratios[0]), 4.0)
        XCTAssertEqual(Double(ratios[1]), 10.0)
    }

    func testWriterNoOpForReversibleOnlySyntax() {
        var ds = DataSet(elements: [])
        CompressionManager.applyLossyImageCompressionAttributes(
            to: &ds, targetSyntax: .jpeg2000Lossless, uncompressedByteCount: 1000, compressedByteCount: 250)
        XCTAssertNil(ds.string(for: .lossyImageCompression))
        XCTAssertNil(ds.strings(for: .lossyImageCompressionRatio))
        XCTAssertNil(ds.strings(for: .lossyImageCompressionMethod))
    }

    /// A legacy source with a ratio but no method (both Type 3) must not misalign the
    /// parallel arrays: the uninterpretable orphan is dropped and the new (ratio, method)
    /// pair is positionally matched.
    func testWriterKeepsArraysAlignedWithAsymmetricPriorHistory() {
        var ds = DataSet(elements: [])
        ds.setString("01", for: .lossyImageCompression, vr: .CS)
        ds.setString("12", for: .lossyImageCompressionRatio, vr: .DS)   // orphan ratio, method absent
        CompressionManager.applyLossyImageCompressionAttributes(
            to: &ds, targetSyntax: .jpeg2000, uncompressedByteCount: 1000, compressedByteCount: 400) // 2.5:1
        let ratios = ds.strings(for: .lossyImageCompressionRatio) ?? []
        let methods = ds.strings(for: .lossyImageCompressionMethod) ?? []
        XCTAssertEqual(ratios.count, methods.count, "parallel arrays must stay equal length")
        XCTAssertEqual(ratios, ["2.5"])            // orphan "12" dropped, new aligned pair kept
        XCTAssertEqual(methods, ["ISO_15444_1"])
        XCTAssertEqual(ds.string(for: .lossyImageCompression), "01")  // flag still records lossy
    }

    func testWriterSetsImageTypeDerivedOnLossy() {
        var ds = DataSet(elements: [])
        ds.setStrings(["ORIGINAL", "PRIMARY", "AXIAL"], for: .imageType, vr: .CS)
        CompressionManager.applyLossyImageCompressionAttributes(
            to: &ds, targetSyntax: .jpeg2000, uncompressedByteCount: 1000, compressedByteCount: 250)
        XCTAssertEqual(ds.strings(for: .imageType), ["DERIVED", "PRIMARY", "AXIAL"])
    }

    func testWriterLeavesAbsentImageTypeAlone() {
        var ds = DataSet(elements: [])
        CompressionManager.applyLossyImageCompressionAttributes(
            to: &ds, targetSyntax: .jpeg2000, uncompressedByteCount: 1000, compressedByteCount: 250)
        XCTAssertNil(ds.strings(for: .imageType))
    }

    // MARK: - End-to-end through compressData

    func testCompressLossyJ2KSetsLossyAttributes() throws {
        let uncompressed = try makeUncompressed()
        let mgr = CompressionManager()
        let out = try mgr.compressData(uncompressed, codec: "jpeg2000-lossy", quality: .medium)
        let f = try DICOMFile.read(from: out)
        XCTAssertEqual(f.dataSet.string(for: .lossyImageCompression), "01")
        XCTAssertEqual(f.dataSet.strings(for: .lossyImageCompressionMethod), ["ISO_15444_1"])
        XCTAssertNotNil(f.dataSet.strings(for: .lossyImageCompressionRatio))
        XCTAssertEqual(transferSyntaxUID(of: f), "1.2.840.10008.1.2.4.91")   // general UID
    }

    func testCompressLosslessJ2KDoesNotSetLossyAttributes() throws {
        let uncompressed = try makeUncompressed()
        let mgr = CompressionManager()
        // Reversibly encoded INTO the general .91 UID — must carry no lossy provenance.
        let out = try mgr.compressData(uncompressed, codec: "jpeg2000-lossless", quality: nil)
        let f = try DICOMFile.read(from: out)
        XCTAssertEqual(transferSyntaxUID(of: f), "1.2.840.10008.1.2.4.91")
        XCTAssertNil(f.dataSet.string(for: .lossyImageCompression))
        XCTAssertNil(f.dataSet.strings(for: .lossyImageCompressionMethod))
    }

    // MARK: - getCompressionInfo reporting (0028,2110-aware for `both` UIDs)

    /// A reversibly encoded general (.91) file carries no lossy provenance, so
    /// `getCompressionInfo` must report it as lossless — and name it "Lossless" —
    /// even though the UID (.91) is "Lossy" at the UID level.
    func testInfoReportsReversibleGeneralUIDAsLossless() throws {
        let uncompressed = try makeUncompressed()
        let mgr = CompressionManager()
        let out = try mgr.compressData(uncompressed, codec: "jpeg2000-lossless", quality: nil)
        let info = try mgr.getCompressionInfo(data: out)
        XCTAssertEqual(info.transferSyntaxUID, "1.2.840.10008.1.2.4.91")
        XCTAssertTrue(info.isLossless, "reversible .91 must report lossless")
        XCTAssertEqual(info.transferSyntaxName, "JPEG 2000 Image Compression (lossless)")  // PS3.6 Table A-1 name + intent (D176)
    }

    /// A lossy general (.91) file sets (0028,2110)="01", so it must report lossy.
    func testInfoReportsLossyGeneralUIDAsLossy() throws {
        let uncompressed = try makeUncompressed()
        let mgr = CompressionManager()
        let out = try mgr.compressData(uncompressed, codec: "jpeg2000-lossy", quality: .medium)
        let info = try mgr.getCompressionInfo(data: out)
        XCTAssertEqual(info.transferSyntaxUID, "1.2.840.10008.1.2.4.91")
        XCTAssertFalse(info.isLossless, "lossy .91 must report lossy")
        XCTAssertEqual(info.transferSyntaxName, "JPEG 2000 Image Compression (lossy)")
    }

    /// The reversible-only UID (.90) is authoritative on its own — no 0028,2110 needed.
    func testInfoReportsLosslessOnlyUIDAsLossless() throws {
        let uncompressed = try makeUncompressed()
        let mgr = CompressionManager()
        let out = try mgr.compressData(uncompressed, codec: "jpeg2000-lossless-only", quality: nil)
        let info = try mgr.getCompressionInfo(data: out)
        XCTAssertEqual(info.transferSyntaxUID, "1.2.840.10008.1.2.4.90")
        XCTAssertTrue(info.isLossless)
    }

    // MARK: - Helpers

    private func transferSyntaxUID(of file: DICOMFile) -> String? {
        file.fileMetaInformation.string(for: .transferSyntaxUID)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
    }

    private func makeUncompressed() throws -> Data {
        var els: [DataElement] = []
        els.append(.uint16(tag: .rows, value: 8))
        els.append(.uint16(tag: .columns, value: 8))
        els.append(.uint16(tag: .bitsAllocated, value: 16))
        els.append(.uint16(tag: .bitsStored, value: 12))
        els.append(.uint16(tag: .highBit, value: 11))
        els.append(.uint16(tag: .pixelRepresentation, value: 0))
        els.append(.uint16(tag: .samplesPerPixel, value: 1))
        els.append(.string(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"))
        els.append(.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"))
        els.append(.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7.8.9"))
        var pixels = Data()
        for i in 0..<64 {
            let v = UInt16((i * 60) % 4096)
            pixels.append(UInt8(v & 0xFF)); pixels.append(UInt8((v >> 8) & 0xFF))
        }
        els.append(DataElement(tag: .pixelData, vr: .OW, length: UInt32(pixels.count), valueData: pixels))
        let ds = DataSet(elements: els)
        return try DICOMFile.create(dataSet: ds,
                                    transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
    }
}
