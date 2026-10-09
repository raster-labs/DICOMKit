// MergeFormatMatrixTests.swift
// Full-matrix oracles for dicom-merge: every MergeFormat crossed with every
// source SOP Class its gate admits, plus the SC pixel-shape variants and the
// `auto` picks — each merged, checked against MultiframeSOPClassMap (never a
// re-hardcoded UID), then split back to verify per-frame pixel identity.

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore
@testable import DICOMDictionary

final class MergeFormatMatrixTests: XCTestCase {

    private typealias U = MultiframeSOPClassMap.UID
    private let frames = 3

    // MARK: - Generic classic-slice builder

    /// Pixel shape of a synthesized classic slice.
    private enum Shape {
        case gray8, gray16, rgb, singleBit
    }

    private func makeSlice(sopClass: String, modality: String, index: Int, shape: Shape) -> DICOMFile {
        var ds = DataSet()
        ds.setString(sopClass, for: .sopClassUID, vr: .UI)
        ds.setString(rtUID(), for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.100", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.300", for: .seriesInstanceUID, vr: .UI)
        ds.setString(modality, for: .modality, vr: .CS)
        ds.setString("Matrix^Patient", for: .patientName, vr: .PN)
        ds.setString("MX001", for: .patientID, vr: .LO)
        ds.setString("\(index + 1)", for: .instanceNumber, vr: .IS)
        ds.setString("0.5\\0.5", for: .pixelSpacing, vr: .DS)
        ds.setString("1\\0\\0\\0\\1\\0", for: .imageOrientationPatient, vr: .DS)
        ds.setString("0\\0\\\(Double(index) * 2.0)", for: .imagePositionPatient, vr: .DS)
        ds.setUInt16(4, for: .rows)
        ds.setUInt16(4, for: .columns)
        let count = 16
        switch shape {
        case .gray8:
            ds.setUInt16(8, for: .bitsAllocated); ds.setUInt16(8, for: .bitsStored)
            ds.setUInt16(7, for: .highBit); ds.setUInt16(0, for: .pixelRepresentation)
            ds.setUInt16(1, for: .samplesPerPixel)
            ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
            ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB,
                                              data: Data(repeating: UInt8(10 + index), count: count))
        case .gray16:
            ds.setUInt16(16, for: .bitsAllocated); ds.setUInt16(16, for: .bitsStored)
            ds.setUInt16(15, for: .highBit); ds.setUInt16(0, for: .pixelRepresentation)
            ds.setUInt16(1, for: .samplesPerPixel)
            ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
            var px = Data(count: count * 2)
            let v = UInt16(100 + index)
            for i in 0..<count { px[i * 2] = UInt8(v & 0xFF); px[i * 2 + 1] = UInt8(v >> 8) }
            ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: px)
        case .rgb:
            ds.setUInt16(8, for: .bitsAllocated); ds.setUInt16(8, for: .bitsStored)
            ds.setUInt16(7, for: .highBit); ds.setUInt16(0, for: .pixelRepresentation)
            ds.setUInt16(3, for: .samplesPerPixel)
            ds.setUInt16(0, for: .planarConfiguration)
            ds.setString("RGB", for: .photometricInterpretation, vr: .CS)
            var px = Data(count: count * 3)
            for i in 0..<count { px[i * 3] = UInt8(200 + index); px[i * 3 + 1] = 50; px[i * 3 + 2] = UInt8(index) }
            ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: px)
        case .singleBit:
            ds.setUInt16(1, for: .bitsAllocated); ds.setUInt16(1, for: .bitsStored)
            ds.setUInt16(0, for: .highBit); ds.setUInt16(0, for: .pixelRepresentation)
            ds.setUInt16(1, for: .samplesPerPixel)
            ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
            // 16 pixels → 2 bytes; a distinct bit pattern per slice.
            ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB,
                                              data: Data([UInt8(0b10101010 >> index), UInt8(index + 1)]))
        }
        return DICOMFile.create(dataSet: ds, sopClassUID: sopClass)
    }

    private func slices(sopClass: String, modality: String, shape: Shape) -> [DICOMFile] {
        (0..<frames).map { makeSlice(sopClass: sopClass, modality: modality, index: $0, shape: shape) }
    }

    // MARK: - Drivers (same entry points as the CLI / Workshop)

    private func merge(_ files: [DICOMFile], format: MergeFormat,
                       options: MergeOptions = MergeOptions()) async throws -> DICOMFile {
        let dir = try makeTempDir()
        let paths = try files.enumerated().map { i, f -> String in
            let url = dir.appendingPathComponent(String(format: "in_%03d.dcm", i))
            try f.write().write(to: url)
            return url.path
        }
        let out = dir.appendingPathComponent("merged.dcm")
        let merger = FrameMerger(format: format, level: .file, sortBy: .instanceNumber,
                                 order: .ascending, validate: false, verbose: false, options: options)
        try await merger.mergeToSingleFile(files: paths, outputPath: out.path)
        return try DICOMFile.read(from: out)
    }

    private func splitBack(_ file: DICOMFile) async throws -> [DICOMFile] {
        let inDir = try makeTempDir()
        let inURL = inDir.appendingPathComponent("input.dcm")
        try file.write().write(to: inURL)
        let outDir = try makeTempDir()
        let splitter = FrameSplitter(outputPath: outDir.path, format: .dicom, applyWindow: false,
                                     windowCenter: nil, windowWidth: nil, namingPattern: nil,
                                     verbose: false, options: SplitOptions(), log: { _ in })
        var result = SplitResult()
        await splitter.processFile(inURL.path, frameIndices: nil, into: &result)
        return try result.writtenPaths.sorted().map { try DICOMFile.read(from: URL(fileURLWithPath: $0)) }
    }

    private func uid(_ ds: DataSet, _ tag: Tag) -> String? {
        ds.string(for: tag).map(MultiframeSOPClassMap.normalize)
    }

    // MARK: - The matrix oracle

    /// Merges classic slices with `format`, asserts the container against the
    /// SOP-class map, splits back, and asserts per-frame pixel identity.
    private func runCase(format: MergeFormat, sourceClass: String, sourceModality: String,
                         shape: Shape, expectTarget: String,
                         file: StaticString = #filePath, line: UInt = #line) async throws {
        let inputs = slices(sopClass: sourceClass, modality: sourceModality, shape: shape)
        let merged = try await merge(inputs, format: format)
        let ds = merged.dataSet

        // Container facts, all derived from MultiframeSOPClassMap.
        XCTAssertEqual(uid(ds, .sopClassUID), expectTarget, "SOP Class", file: file, line: line)
        XCTAssertEqual(uid(merged.fileMetaInformation, .mediaStorageSOPClassUID), expectTarget,
                       "file meta SOP Class", file: file, line: line)
        XCTAssertEqual(ds.numberOfFrames, frames, "NumberOfFrames", file: file, line: line)
        if let modality = MultiframeSOPClassMap.modality(forTarget: expectTarget) {
            XCTAssertEqual(ds.string(for: .modality)?.trimmingCharacters(in: .whitespaces),
                           modality.rawValue, "Modality", file: file, line: line)
        }
        let entry = MultiframeSOPClassMap.entry(for: expectTarget)
        if entry?.hasFunctionalGroups == true {
            XCTAssertNotNil(ds[.sharedFunctionalGroupsSequence], "Shared FGs", file: file, line: line)
            XCTAssertEqual(ds.sequence(for: .perFrameFunctionalGroupsSequence)?.count, frames,
                           "one Per-frame item per frame", file: file, line: line)
        } else {
            XCTAssertNil(ds[.sharedFunctionalGroupsSequence],
                         "non-FG IOD must not carry functional groups", file: file, line: line)
        }

        // Pixel bytes: the container holds the input frames concatenated in sort order.
        let mergedPixels = ds[.pixelData]?.valueData ?? Data()
        let expectedPixels = inputs.reduce(Data()) { $0 + ($1.dataSet[.pixelData]?.valueData ?? Data()) }
        // Byte-aligned frames (all shapes here) concatenate exactly — single
        // bit included (16 pixels = 2 whole bytes per frame, PS3.5 8.1.1).
        XCTAssertEqual(mergedPixels, expectedPixels, "concatenated pixels", file: file, line: line)

        // Split back: every frame returns with its own bytes.
        let back = try await splitBack(merged)
        XCTAssertEqual(back.count, frames, "split-back count", file: file, line: line)
        if case .convert(let classicUID)? = entry?.splitTarget {
            for out in back {
                XCTAssertEqual(uid(out.dataSet, .sopClassUID), classicUID,
                               "split-back SOP Class", file: file, line: line)
            }
        }
        for (i, out) in back.enumerated() {
            XCTAssertEqual(out.dataSet[.pixelData]?.valueData, inputs[i].dataSet[.pixelData]?.valueData,
                           "frame \(i) pixels", file: file, line: line)
        }
    }

    // MARK: - Explicit formats × their source modality

    func testEnhancedCTFromClassicCT() async throws {
        try await runCase(format: .enhancedCt, sourceClass: U.ctImage, sourceModality: "CT",
                          shape: .gray16, expectTarget: U.enhancedCT)
    }
    func testEnhancedMRFromClassicMR() async throws {
        try await runCase(format: .enhancedMr, sourceClass: U.mrImage, sourceModality: "MR",
                          shape: .gray16, expectTarget: U.enhancedMR)
    }
    func testEnhancedPETFromClassicPET() async throws {
        try await runCase(format: .enhancedPet, sourceClass: U.petImage, sourceModality: "PT",
                          shape: .gray16, expectTarget: U.enhancedPET)
    }
    func testEnhancedXAFromClassicXA() async throws {
        try await runCase(format: .enhancedXa, sourceClass: U.xaImage, sourceModality: "XA",
                          shape: .gray16, expectTarget: U.enhancedXA)
    }
    func testEnhancedXRFFromClassicXRF() async throws {
        try await runCase(format: .enhancedXrf, sourceClass: U.xrfImage, sourceModality: "RF",
                          shape: .gray16, expectTarget: U.enhancedXRF)
    }
    func testLegacyConvertedCTFromClassicCT() async throws {
        try await runCase(format: .legacyConvertedCt, sourceClass: U.ctImage, sourceModality: "CT",
                          shape: .gray16, expectTarget: U.legacyConvertedEnhancedCT)
    }
    func testLegacyConvertedMRFromClassicMR() async throws {
        try await runCase(format: .legacyConvertedMr, sourceClass: U.mrImage, sourceModality: "MR",
                          shape: .gray16, expectTarget: U.legacyConvertedEnhancedMR)
    }
    func testLegacyConvertedPETFromClassicPET() async throws {
        try await runCase(format: .legacyConvertedPet, sourceClass: U.petImage, sourceModality: "PT",
                          shape: .gray16, expectTarget: U.legacyConvertedEnhancedPET)
    }
    func testUSMultiframeFromClassicUS() async throws {
        try await runCase(format: .usMultiframe, sourceClass: U.usImage, sourceModality: "US",
                          shape: .gray8, expectTarget: U.usMultiframe)
    }

    // MARK: - SC multi-frame IOD completeness (PS3.3 2026a Tables A.8-2 … A.8-5)

    private func frameIncrementTarget(_ ds: DataSet) -> Tag? {
        guard let e = ds[.frameIncrementPointer], e.vr == .AT, e.valueData.count == 4 else { return nil }
        let b = [UInt8](e.valueData)
        return Tag(group: UInt16(b[0]) | UInt16(b[1]) << 8, element: UInt16(b[2]) | UInt16(b[3]) << 8)
    }

    private func assertSCMultiframeComplete(_ ds: DataSet, grayscaleWithLUT: Bool,
                                            file: StaticString = #filePath, line: UInt = #line) {
        // Type 1: SOP Common C.12-1, General Study C.7-3, General Series C.7-5a, SC
        // Equipment C.8-24, Image Pixel C.7-11a, Multi-frame C.7-14, SC Multi-frame Image C.8-25b.
        var type1: [Tag] = [.sopClassUID, .sopInstanceUID, .studyInstanceUID, .modality, .seriesInstanceUID,
                            .conversionType, .samplesPerPixel, .photometricInterpretation, .rows, .columns,
                            .bitsAllocated, .bitsStored, .highBit, .pixelRepresentation, .pixelData,
                            .numberOfFrames, .burnedInAnnotation, .frameIncrementPointer]
        if grayscaleWithLUT { type1 += [.presentationLUTShape, .rescaleIntercept, .rescaleSlope, .rescaleType] }
        for tag in type1 {
            guard let e = ds[tag] else { XCTFail("Type 1 \(tag) missing", file: file, line: line); continue }
            XCTAssertFalse(e.valueData.isEmpty, "Type 1 \(tag) empty", file: file, line: line)
        }
        // Type 2: Patient C.7-1, General Study C.7-3, General Series C.7-5a, General Image C.7-9.
        for tag in [Tag.patientName, .patientID, .patientBirthDate, .patientSex, .studyDate, .studyTime,
                    .referringPhysicianName, .studyID, .accessionNumber, .seriesNumber, .instanceNumber, .patientOrientation] {
            XCTAssertNotNil(ds[tag], "Type 2 \(tag) missing", file: file, line: line)
        }
        XCTAssertEqual(ds.string(for: .conversionType), "WSD", file: file, line: line)
        XCTAssertEqual(ds.string(for: .burnedInAnnotation), "NO", file: file, line: line)
        let target = frameIncrementTarget(ds)
        XCTAssertNotNil(target, "Frame Increment Pointer", file: file, line: line)
        if let target {
            XCTAssertNotNil(ds[target], "Frame Increment Pointer target \(target) must be present", file: file, line: line)
        }
        if grayscaleWithLUT {
            XCTAssertEqual(ds.string(for: .presentationLUTShape), "IDENTITY", file: file, line: line)
        } else {
            XCTAssertNil(ds[.presentationLUTShape], file: file, line: line)
        }
    }

    func testSCMultiframeByteIsComplete() async throws {
        let merged = try await merge(slices(sopClass: U.secondaryCapture, modality: "OT", shape: .gray8), format: .scMultiframe)
        let ds = merged.dataSet
        assertSCMultiframeComplete(ds, grayscaleWithLUT: true)
        // A.8.3.4: Rescale Intercept 0, Rescale Slope 1, Rescale Type US; no Planar Configuration.
        XCTAssertEqual(ds.string(for: .rescaleIntercept), "0")
        XCTAssertEqual(ds.string(for: .rescaleSlope), "1")
        XCTAssertEqual(ds.string(for: .rescaleType), "US")
        XCTAssertNil(ds[.planarConfiguration])
        XCTAssertEqual(frameIncrementTarget(ds), .pageNumberVector)
        XCTAssertEqual(ds.strings(for: .pageNumberVector), ["1", "2", "3"])
    }

    func testSCMultiframeWordKeepsSourceRescale() async throws {
        var inputs = slices(sopClass: U.secondaryCapture, modality: "OT", shape: .gray16)
        inputs = inputs.map { file in
            var ds = file.dataSet
            ds.setString("-10", for: .rescaleIntercept, vr: .DS)
            ds.setString("2", for: .rescaleSlope, vr: .DS)
            ds.setString("HU", for: .rescaleType, vr: .LO)
            return DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: ds)
        }
        let ds = try await merge(inputs, format: .scMultiframe).dataSet
        assertSCMultiframeComplete(ds, grayscaleWithLUT: true)
        // A.8.4.4: slope/intercept are not constrained for the Grayscale Word IOD.
        XCTAssertEqual(ds.string(for: .rescaleIntercept), "-10")
        XCTAssertEqual(ds.string(for: .rescaleSlope), "2")
        XCTAssertEqual(ds.string(for: .rescaleType), "HU")
    }

    func testSCMultiframeTrueColorIsComplete() async throws {
        let ds = try await merge(slices(sopClass: U.secondaryCapture, modality: "OT", shape: .rgb), format: .scMultiframe).dataSet
        assertSCMultiframeComplete(ds, grayscaleWithLUT: false)
        XCTAssertEqual(ds.uint16(for: .planarConfiguration), 0, "A.8.5.4")
        XCTAssertNil(ds[.rescaleIntercept])
    }

    func testSCMultiframeSingleBitIsComplete() async throws {
        let ds = try await merge(slices(sopClass: U.secondaryCapture, modality: "OT", shape: .singleBit), format: .scMultiframe).dataSet
        assertSCMultiframeComplete(ds, grayscaleWithLUT: false)
        XCTAssertNil(ds[.rescaleIntercept], "Bits Stored 1: the C.8-25b condition fails")
        XCTAssertNil(ds[.planarConfiguration])
    }

    // MARK: - SC pixel-shape refinement (byte / word / true colour / single bit)

    func testSCMultiframeByteFromGray8SC() async throws {
        try await runCase(format: .scMultiframe, sourceClass: U.secondaryCapture, sourceModality: "OT",
                          shape: .gray8, expectTarget: U.multiframeGrayscaleByteSC)
    }
    func testSCMultiframeWordFromGray16SC() async throws {
        try await runCase(format: .scMultiframe, sourceClass: U.secondaryCapture, sourceModality: "OT",
                          shape: .gray16, expectTarget: U.multiframeGrayscaleWordSC)
    }
    func testSCMultiframeTrueColorFromRGBSC() async throws {
        try await runCase(format: .scMultiframe, sourceClass: U.secondaryCapture, sourceModality: "OT",
                          shape: .rgb, expectTarget: U.multiframeTrueColorSC)
    }
    func testSCMultiframeSingleBitFromBitSC() async throws {
        try await runCase(format: .scMultiframe, sourceClass: U.secondaryCapture, sourceModality: "OT",
                          shape: .singleBit, expectTarget: U.multiframeSingleBitSC)
    }

    // MARK: - `auto` picks the map's target for every source class

    func testAutoMatrix() async throws {
        let picks: [(String, String, Shape)] = [
            (U.ctImage, "CT", .gray16),
            (U.mrImage, "MR", .gray16),
            (U.petImage, "PT", .gray16),
            (U.usImage, "US", .gray8),
            (U.secondaryCapture, "OT", .gray8),
            (U.secondaryCapture, "OT", .gray16),
            (U.secondaryCapture, "OT", .rgb),
        ]
        for (source, modality, shape) in picks {
            let bits: Int, samples: Int
            switch shape {
            case .gray8: bits = 8; samples = 1
            case .gray16: bits = 16; samples = 1
            case .rgb: bits = 8; samples = 3
            case .singleBit: bits = 1; samples = 1
            }
            guard let target = MultiframeSOPClassMap.automaticMergeTarget(
                forSource: source, bitsAllocated: bits, samplesPerPixel: samples) else {
                return XCTFail("auto has no target for \(source)")
            }
            try await runCase(format: .auto, sourceClass: source, sourceModality: modality,
                              shape: shape, expectTarget: target)
        }
    }

    // MARK: - The gate holds on every enhanced/legacy target

    func testGateRejectsForeignSourcesForEveryTarget() async throws {
        // (format, a source class its gate must refuse)
        let cases: [(MergeFormat, String, String)] = [
            (.enhancedCt, U.mrImage, "MR"),
            (.enhancedMr, U.ctImage, "CT"),
            (.enhancedPet, U.ctImage, "CT"),
            (.enhancedXa, U.xrfImage, "RF"),
            (.enhancedXrf, U.xaImage, "XA"),
            (.legacyConvertedCt, U.petImage, "PT"),
            (.legacyConvertedMr, U.usImage, "US"),
            (.legacyConvertedPet, U.mrImage, "MR"),
            (.usMultiframe, U.ctImage, "CT"),
        ]
        for (format, source, modality) in cases {
            let inputs = slices(sopClass: source, sourceModality: modality)
            do {
                _ = try await merge(inputs, format: format)
                XCTFail("\(format) accepted \(source)")
            } catch let error as MergeError {
                guard case .unsupportedSourceSOPClass = error else {
                    return XCTFail("\(format): expected the source gate, got \(error)")
                }
            }
        }
    }

    private func slices(sopClass: String, sourceModality: String) -> [DICOMFile] {
        slices(sopClass: sopClass, modality: sourceModality, shape: .gray16)
    }

    // MARK: - Re-merging the family's own multi-frame chunks

    func testEnhancedChunksRemergeIntoOneContainer() async throws {
        // Two Enhanced CT containers (frames 0-2 and 3-5) must merge back into one.
        let a = try await merge(slices(sopClass: U.ctImage, modality: "CT", shape: .gray16),
                                format: .enhancedCt)
        let more = (3..<6).map { makeSlice(sopClass: U.ctImage, modality: "CT", index: $0, shape: .gray16) }
        let b = try await merge(more, format: .enhancedCt)
        let combined = try await merge([a, b], format: .enhancedCt)
        XCTAssertEqual(uid(combined.dataSet, .sopClassUID), U.enhancedCT)
        XCTAssertEqual(combined.dataSet.numberOfFrames, 6)
        XCTAssertEqual(combined.dataSet.sequence(for: .perFrameFunctionalGroupsSequence)?.count, 6)
        let back = try await splitBack(combined)
        XCTAssertEqual(back.count, 6)
    }
}
