// MergeMonochrome1Tests.swift
// FrameMerger converts MONOCHROME1 sources to MONOCHROME2 where the target IOD allows only
// MONOCHROME2 (D37 c), pinned to PS3.3 2026a:
// - A.8.2.4 / A.8.3.4 / A.8.4.4: Multi-frame Single Bit / Grayscale Byte / Grayscale Word SC
//   "Photometric Interpretation (0028,0004) shall be MONOCHROME2"
// - A.70.3.1 / A.71.3.1: Legacy Converted Enhanced CT / MR — "If the Value of Photometric
//   Interpretation (0028,0004) in the source Single-frame Images is MONOCHROME1 ... lossless
//   conversion of the pixel data to MONOCHROME2 and updating of any related Attributes is
//   necessary"; C.8.15.2 Enhanced CT Image Enumerated Value MONOCHROME2
// - C.8.19.2: Enhanced XA/XRF allows MONOCHROME1 — no conversion
// - C.7.6.3.1.2: MONOCHROME1 minimum displayed white, MONOCHROME2 black, after VOI
// - C.11.2.1.2.1 LINEAR window, C.11.2.1.1 VOI LUT Descriptor / Data
// The appearance tests evaluate the standard's window function on both the source and the
// converted object and require the same displayed value for every stored value.

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore

final class MergeMonochrome1Tests: XCTestCase {

    private typealias U = MultiframeSOPClassMap.UID
    private let crImage = "1.2.840.10008.5.1.4.1.1.1"

    // MARK: - Fixtures

    private struct Gray {
        var bitsAllocated = 8
        var bitsStored = 8
        var signed = false
        var values: [Int]
    }

    private func slice(sopClass: String, modality: String, index: Int, gray: Gray,
                       photometric: String = "MONOCHROME1",
                       extra: (inout DataSet) -> Void = { _ in }) -> DICOMFile {
        var ds = DataSet()
        ds.setString(sopClass, for: .sopClassUID, vr: .UI)
        ds.setString(rtUID(), for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.100", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.301", for: .seriesInstanceUID, vr: .UI)
        ds.setString(modality, for: .modality, vr: .CS)
        ds.setString("Mono^One", for: .patientName, vr: .PN)
        ds.setString("M1", for: .patientID, vr: .LO)
        ds.setString("\(index + 1)", for: .instanceNumber, vr: .IS)
        ds.setString("0.5\\0.5", for: .pixelSpacing, vr: .DS)
        ds.setString("1\\0\\0\\0\\1\\0", for: .imageOrientationPatient, vr: .DS)
        ds.setString("0\\0\\\(Double(index) * 2.0)", for: .imagePositionPatient, vr: .DS)
        ds.setUInt16(1, for: .rows)
        ds.setUInt16(UInt16(gray.values.count), for: .columns)
        ds.setUInt16(UInt16(gray.bitsAllocated), for: .bitsAllocated)
        ds.setUInt16(UInt16(gray.bitsStored), for: .bitsStored)
        ds.setUInt16(UInt16(gray.bitsStored - 1), for: .highBit)
        ds.setUInt16(gray.signed ? 1 : 0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString(photometric, for: .photometricInterpretation, vr: .CS)
        var px = Data()
        let mask = (1 << gray.bitsStored) - 1
        for v in gray.values {
            let stored = v & mask   // two's complement within Bits Stored
            if gray.bitsAllocated == 8 {
                px.append(UInt8(stored))
            } else {
                px.append(UInt8(stored & 0xFF)); px.append(UInt8(stored >> 8))
            }
        }
        if px.count % 2 == 1 { px.append(0) }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: gray.bitsAllocated > 8 ? .OW : .OB, data: px)
        extra(&ds)
        return DICOMFile.create(dataSet: ds, sopClassUID: sopClass)
    }

    private func merge(_ files: [DICOMFile], format: MergeFormat) async throws -> DICOMFile {
        let dir = try makeTempDir()
        let paths = try files.enumerated().map { i, f -> String in
            let url = dir.appendingPathComponent(String(format: "in_%03d.dcm", i))
            try f.write().write(to: url)
            return url.path
        }
        let out = dir.appendingPathComponent("merged.dcm")
        let merger = FrameMerger(format: format, level: .file, sortBy: .instanceNumber,
                                 order: .ascending, validate: false, verbose: false)
        try await merger.mergeToSingleFile(files: paths, outputPath: out.path)
        return try DICOMFile.read(from: out)
    }

    /// C.11.2.1.2.1 LINEAR window, output 0...1
    private func linear(_ x: Double, c: Double, w: Double) -> Double {
        if x <= c - 0.5 - (w - 1) / 2 { return 0 }
        if x > c - 0.5 + (w - 1) / 2 { return 1 }
        return (x - (c - 0.5)) / (w - 1) + 0.5
    }

    /// Displayed brightness: MONOCHROME1 shows the minimum as white (C.7.6.3.1.2)
    private func displayed(_ stored: Int, slope: Double, intercept: Double, c: Double, w: Double,
                           monochrome1: Bool) -> Double {
        let voi = linear(Double(stored) * slope + intercept, c: c, w: w)
        return monochrome1 ? 1 - voi : voi
    }

    private func storedValues(_ ds: DataSet, bitsAllocated: Int, bitsStored: Int, signed: Bool) -> [Int] {
        let data = ds[.pixelData]?.valueData ?? Data()
        let count = Int(ds.uint16(for: .columns) ?? 0) * Int(ds.uint16(for: .rows) ?? 0) * (ds.numberOfFrames ?? 1)
        return (0..<count).map { i in
            let raw = bitsAllocated == 8 ? Int(data[i]) : Int(data[2 * i]) | Int(data[2 * i + 1]) << 8
            let v = raw & ((1 << bitsStored) - 1)
            return signed && v >= 1 << (bitsStored - 1) ? v - (1 << bitsStored) : v
        }
    }

    // MARK: - Multi-frame Grayscale Byte SC (A.8.3.4)

    func testGrayscaleByteSCInvertsMonochrome1AndKeepsTheDisplayedPicture() async throws {
        let values = [0, 1, 60, 100, 127, 128, 200, 254, 255]
        let inputs = (0..<2).map { i in
            slice(sopClass: crImage, modality: "CR", index: i, gray: Gray(values: values)) { ds in
                ds.setString("100", for: .windowCenter, vr: .DS)
                ds.setString("50", for: .windowWidth, vr: .DS)
                ds.setString("INVERSE", for: .presentationLUTShape, vr: .CS)
                ds.setUInt16(3, for: .smallestImagePixelValue)
                ds.setUInt16(250, for: .largestImagePixelValue)
                ds.setUInt16(0, for: .pixelPaddingValue)
            }
        }
        let merged = try await merge(inputs, format: .scMultiframe).dataSet
        XCTAssertEqual(merged.string(for: .sopClassUID), U.multiframeGrayscaleByteSC)
        XCTAssertEqual(merged.string(for: .photometricInterpretation), "MONOCHROME2")
        XCTAssertEqual(merged.string(for: .presentationLUTShape), "IDENTITY")

        // Stored values: v -> 255 - v, lossless
        let stored = storedValues(merged, bitsAllocated: 8, bitsStored: 8, signed: false)
        XCTAssertEqual(stored, (values + values).map { 255 - $0 })

        // Window: C = 1 × 255 + 2 × 0; LINEAR centre 255 - 100 + 1 = 156, width unchanged
        XCTAssertEqual(merged.string(for: .windowCenter), "156")
        XCTAssertEqual(merged.string(for: .windowWidth), "50")
        for v in 0...255 {
            XCTAssertEqual(displayed(255 - v, slope: 1, intercept: 0, c: 156, w: 50, monochrome1: false),
                           displayed(v, slope: 1, intercept: 0, c: 100, w: 50, monochrome1: true),
                           accuracy: 1e-9, "stored \(v)")
        }

        // Stored-value attributes: padding 0 -> 255; smallest/largest swap and invert
        XCTAssertEqual(merged.uint16(for: .pixelPaddingValue), 255)
        XCTAssertEqual(merged.uint16(for: .smallestImagePixelValue), 5)
        XCTAssertEqual(merged.uint16(for: .largestImagePixelValue), 252)
    }

    // MARK: - Multi-frame Grayscale Word SC (A.8.4.4)

    func testGrayscaleWordSCInvertsTwelveBitMonochrome1() async throws {
        let values = [0, 1, 1000, 2048, 4094, 4095]
        let inputs = (0..<2).map { i in
            slice(sopClass: crImage, modality: "CR", index: i,
                  gray: Gray(bitsAllocated: 16, bitsStored: 12, values: values)) { ds in
                ds.setString("2000\\1000", for: .windowCenter, vr: .DS)
                ds.setString("4000\\500", for: .windowWidth, vr: .DS)
            }
        }
        let merged = try await merge(inputs, format: .scMultiframe).dataSet
        XCTAssertEqual(merged.string(for: .sopClassUID), U.multiframeGrayscaleWordSC)
        XCTAssertEqual(merged.string(for: .photometricInterpretation), "MONOCHROME2")
        XCTAssertEqual(storedValues(merged, bitsAllocated: 16, bitsStored: 12, signed: false),
                       (values + values).map { 4095 - $0 })
        // Each window centre moves: 4095 - c + 1
        XCTAssertEqual(merged.strings(for: .windowCenter), ["2096", "3096"])
        XCTAssertEqual(merged.strings(for: .windowWidth), ["4000", "500"])
    }

    // MARK: - Multi-frame Single Bit SC (A.8.2.4)

    func testSingleBitSCInvertsBits() async throws {
        func bitSlice(_ index: Int, _ bytes: [UInt8]) -> DICOMFile {
            var file = slice(sopClass: U.secondaryCapture, modality: "OT", index: index,
                             gray: Gray(values: [0]))
            var ds = file.dataSet
            ds.setUInt16(4, for: .rows); ds.setUInt16(4, for: .columns)
            ds.setUInt16(1, for: .bitsAllocated); ds.setUInt16(1, for: .bitsStored); ds.setUInt16(0, for: .highBit)
            ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: Data(bytes))
            file = DICOMFile.create(dataSet: ds, sopClassUID: U.secondaryCapture)
            return file
        }
        let merged = try await merge([bitSlice(0, [0b1010_0101, 0x0F]), bitSlice(1, [0xFF, 0x00])],
                                     format: .scMultiframe).dataSet
        XCTAssertEqual(merged.string(for: .sopClassUID), U.multiframeSingleBitSC)
        XCTAssertEqual(merged.string(for: .photometricInterpretation), "MONOCHROME2")
        XCTAssertEqual(merged[.pixelData]?.valueData, Data([0b0101_1010, 0xF0, 0x00, 0xFF]))
    }

    // MARK: - Legacy Converted Enhanced CT (A.70.3.1)

    func testLegacyConvertedCTInvertsSignedMonochrome1AndUpdatesFrameVOILUT() async throws {
        // Signed 12-bit stored values with a CT rescale; K = -1 so v -> -1 - v
        let values = [-2048, -1024, -1, 0, 40, 1000, 2047]
        let inputs = (0..<3).map { i in
            slice(sopClass: U.ctImage, modality: "CT", index: i,
                  gray: Gray(bitsAllocated: 16, bitsStored: 12, signed: true, values: values)) { ds in
                ds.setString("-1024", for: .rescaleIntercept, vr: .DS)
                ds.setString("1", for: .rescaleSlope, vr: .DS)
                ds.setString("HU", for: .rescaleType, vr: .LO)
                ds.setString("40", for: .windowCenter, vr: .DS)
                ds.setString("400", for: .windowWidth, vr: .DS)
            }
        }
        let merged = try await merge(inputs, format: .legacyConvertedCt).dataSet
        XCTAssertEqual(merged.string(for: .sopClassUID), U.legacyConvertedEnhancedCT)
        XCTAssertEqual(merged.string(for: .photometricInterpretation), "MONOCHROME2")
        XCTAssertEqual(storedValues(merged, bitsAllocated: 16, bitsStored: 12, signed: true),
                       Array(repeating: values.map { -1 - $0 }, count: 3).flatMap { $0 })

        // C = 1 × (-1) + 2 × (-1024) = -2049; LINEAR centre -2049 - 40 + 1 = -2088
        func frameVOI(_ item: SequenceItem?) -> SequenceItem? {
            item?[.frameVOILUTSequence]?.sequenceItems?.first
        }
        let shared = merged.sequence(for: .sharedFunctionalGroupsSequence)?.first
        let voi = try XCTUnwrap(frameVOI(shared) ?? frameVOI(merged.sequence(for: .perFrameFunctionalGroupsSequence)?.first))
        XCTAssertEqual(voi.string(for: .windowCenter), "-2088")
        XCTAssertEqual(voi.string(for: .windowWidth), "400")
        for v in -2048...2047 {
            XCTAssertEqual(displayed(-1 - v, slope: 1, intercept: -1024, c: -2088, w: 400, monochrome1: false),
                           displayed(v, slope: 1, intercept: -1024, c: 40, w: 400, monochrome1: true),
                           accuracy: 1e-9, "stored \(v)")
        }
    }

    // MARK: - Enhanced XA keeps MONOCHROME1 (C.8.19.2)

    func testEnhancedXAKeepsMonochrome1() async throws {
        let values = [0, 10, 200]
        let inputs = (0..<2).map { i in
            slice(sopClass: U.xaImage, modality: "XA", index: i, gray: Gray(values: values))
        }
        let merged = try await merge(inputs, format: .enhancedXa).dataSet
        XCTAssertEqual(merged.string(for: .photometricInterpretation), "MONOCHROME1")
        XCTAssertEqual(storedValues(merged, bitsAllocated: 8, bitsStored: 8, signed: false), values + values)
    }

    func testMonochrome2SourcesAreUntouched() async throws {
        let values = [0, 10, 200]
        let inputs = (0..<2).map { i in
            slice(sopClass: crImage, modality: "CR", index: i, gray: Gray(values: values), photometric: "MONOCHROME2") { ds in
                ds.setString("100", for: .windowCenter, vr: .DS)
                ds.setString("50", for: .windowWidth, vr: .DS)
            }
        }
        let merged = try await merge(inputs, format: .scMultiframe).dataSet
        XCTAssertEqual(merged.string(for: .photometricInterpretation), "MONOCHROME2")
        XCTAssertEqual(storedValues(merged, bitsAllocated: 8, bitsStored: 8, signed: false), values + values)
        XCTAssertEqual(merged.string(for: .windowCenter), "100")
    }

    // MARK: - What is not converted

    func testModalityLUTSequenceIsRefused() async throws {
        let inputs = (0..<2).map { i in
            slice(sopClass: crImage, modality: "CR", index: i, gray: Gray(values: [0, 1])) { ds in
                ds.setSequence([SequenceItem(elements: [
                    DataElement.uint16s(tag: .lutDescriptor, values: [2, 0, 16]),
                    DataElement.uint16s(tag: .lutData, values: [0, 1]),
                ])], for: .modalityLUTSequence)
            }
        }
        do {
            _ = try await merge(inputs, format: .scMultiframe)
            XCTFail("expected MergeError.pixelAssembly")
        } catch MergeError.pixelAssembly(let reason) {
            XCTAssertTrue(reason.contains("Modality LUT Sequence"), reason)
        }
    }

    func testEncapsulatedPayloadIsRefused() {
        let descriptor = PixelDataDescriptor(rows: 1, columns: 1, numberOfFrames: 1, bitsAllocated: 8,
                                             bitsStored: 8, highBit: 7, isSigned: false, samplesPerPixel: 1,
                                             photometricInterpretation: .monochrome1, planarConfiguration: 0)
        let payload = FramePixelPayload(storage: .encapsulated(Data([0xFF, 0xD8])),
                                        transferSyntaxUID: "1.2.840.10008.1.2.4.70", descriptor: descriptor)
        XCTAssertThrowsError(try Monochrome1Conversion.invert(payload)) { error in
            XCTAssertTrue("\(error)".contains("--pixel-handling decode"), "\(error)")
        }
    }

    func testTargetsThatRequireMonochrome2() {
        for uid in [U.enhancedCT, U.enhancedMR, U.enhancedPET, U.legacyConvertedEnhancedCT,
                    U.legacyConvertedEnhancedMR, U.legacyConvertedEnhancedPET,
                    U.multiframeSingleBitSC, U.multiframeGrayscaleByteSC, U.multiframeGrayscaleWordSC] {
            XCTAssertTrue(Monochrome1Conversion.requiresMonochrome2(targetUID: uid), uid)
        }
        for uid in [U.enhancedXA, U.enhancedXRF, U.multiframeTrueColorSC, U.usMultiframe] {
            XCTAssertFalse(Monochrome1Conversion.requiresMonochrome2(targetUID: uid), uid)
        }
    }

    // MARK: - VOI LUT Sequence (C.11.2.1.1)

    func testVOILUTSequenceIsMirrored() throws {
        // 4-entry table from input 10, 12 bits per entry
        let entries: [UInt16] = [0, 100, 2000, 4095]
        let item = SequenceItem(elements: [
            DataElement.uint16s(tag: .lutDescriptor, values: [4, 10, 12]),
            DataElement(tag: .lutData, vr: .OW, length: 8,
                        valueData: Data(entries.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })),
        ])
        // pivot C = 255 (8-bit unsigned, slope 1, intercept 0)
        let mirrored = try Monochrome1Conversion.invertVOILUT(item, pivot: 255)
        XCTAssertEqual(mirrored[.lutDescriptor]?.uint16Values, [4, 255 - 13, 12])
        let data = try XCTUnwrap(mirrored[.lutData]?.valueData)
        let out = (0..<4).map { Int(data[2 * $0]) | Int(data[2 * $0 + 1]) << 8 }
        XCTAssertEqual(out, [0, 4095 - 2000, 4095 - 100, 4095])

        // LUT'(C - x) = max - LUT(x) for every mapped input x
        func lut(_ table: [Int], first: Int, _ x: Int) -> Int { table[max(0, min(table.count - 1, x - first))] }
        for x in 10...13 {
            XCTAssertEqual(lut(out, first: 242, 255 - x), 4095 - lut(entries.map(Int.init), first: 10, x))
        }
    }
}
