// J2KDICOMBoundaryTests.swift — dicom-j2k's DICOM boundary pinned to DICOM 2026a:
// frame → fragment mapping (PS3.5 A.4, A.4.4), Photometric Interpretation after a re-encode
// (PS3.5 8.2.4 / 8.2.14, Tables 8.2.4-1 / 8.2.14-1), lossy provenance and derived images
// (PS3.3 C.7.6.1.1.2, C.7.6.1.1.5, C.7.6.1.1.5.1-2), ROI geometry (C.7.6.2.1.1, C.7.6.16),
// .202 requirements (PS3.5 10.18.1), File Meta (PS3.10 Table 7.1-1).

import Testing
import Foundation
import ArgumentParser
import DICOMCore
import DICOMKit
@testable import dicom_j2k

// MARK: - Fixtures

/// A minimal main header: SOC, a COD segment with the given fields, optional TLM, then SOT.
private func codestream(progression: UInt8 = 0, mct: UInt8 = 0, levels: UInt8 = 5,
                        reversible: Bool = true, tlm: Bool = false) -> Data {
    var b: [UInt8] = [0xFF, 0x4F]
    b += [0xFF, 0x52, 0x00, 0x0C, 0x00, progression, 0x00, 0x01, mct, levels, 0x04, 0x04, 0x00,
          reversible ? 0x01 : 0x00]
    if tlm { b += [0xFF, 0x55, 0x00, 0x04, 0x00, 0x00] }
    b += [0xFF, 0x90, 0x00, 0x0A, 0, 0, 0, 0, 0, 0, 0, 1]
    return Data(b)
}

private func soc(_ tag: UInt8) -> Data { Data([0xFF, 0x4F, tag, tag]) }   // a frame's first fragment
private func body(_ tag: UInt8) -> Data { Data([tag, tag, tag, tag]) }    // a continuation fragment

private func tempURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("dicom-j2k-\(UUID().uuidString)-\(name)")
}

/// A native 8-bit image (RGB or MONOCHROME2), compressed to .90 by the shared engine.
private func j2kLosslessOnlyFile(rgb: Bool, frames: Int = 1, rows: Int = 32, columns: Int = 32) throws -> (url: URL, sop: String) {
    let sop = UIDGenerator.generateSOPInstanceUID().value
    var ds = DataSet()
    ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
    ds.setString(sop, for: .sopInstanceUID, vr: .UI)
    ds.setStrings(["ORIGINAL", "PRIMARY"], for: .imageType, vr: .CS)
    ds.setUInt16(rgb ? 3 : 1, for: .samplesPerPixel)
    ds.setString(rgb ? "RGB" : "MONOCHROME2", for: .photometricInterpretation, vr: .CS)
    if rgb { ds.setUInt16(0, for: .planarConfiguration) }
    ds.setUInt16(UInt16(rows), for: .rows)
    ds.setUInt16(UInt16(columns), for: .columns)
    ds.setUInt16(8, for: .bitsAllocated)
    ds.setUInt16(8, for: .bitsStored)
    ds.setUInt16(7, for: .highBit)
    ds.setUInt16(0, for: .pixelRepresentation)
    ds.setStrings(["10", "20", "30"], for: .imagePositionPatient, vr: .DS)
    ds.setStrings(["1", "0", "0", "0", "1", "0"], for: .imageOrientationPatient, vr: .DS)
    ds.setStrings(["0.5", "0.25"], for: .pixelSpacing, vr: .DS)
    if frames > 1 { ds.setString(String(frames), for: .numberOfFrames, vr: .IS) }
    let spp = rgb ? 3 : 1
    var pixels = [UInt8]()
    for f in 0..<frames {
        for y in 0..<rows { for x in 0..<columns { for s in 0..<spp {
            pixels.append(UInt8((x * 7 + y * 3 + s * 50 + f * 20) & 0xFF))
        } } }
    }
    ds[.pixelData] = DataElement(tag: .pixelData, vr: .OB, length: UInt32(pixels.count),
                                 valueData: Data(pixels))
    let native = try DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
                                      sopInstanceUID: sop).write()
    let j2k = try CompressionManager().compressData(native, codec: "jpeg2000-lossless-only", quality: nil)
    let url = tempURL("in.dcm")
    try j2k.write(to: url)
    return (url, sop)
}

// MARK: - Frames

@Suite("dicom-j2k: frame → fragment mapping (PS3.5 2026a A.4, A.4.4)")
struct FrameMappingTests {

    @Test("One fragment per frame, no offset table")
    func oneFragmentPerFrame() throws {
        let frames = try J2KDICOMBoundary.frameCodestreams(
            fragments: [soc(1), soc(2)], basicOffsetTable: [], extendedOffsetTable: nil, numberOfFrames: 2)
        #expect(frames == [soc(1), soc(2)])
    }

    @Test("A frame spanning two fragments is found through the Basic Offset Table")
    func basicOffsetTable() throws {
        // Item offsets include the 8-byte Item header: frame 2 starts at 2 × (8 + 4).
        let frames = try J2KDICOMBoundary.frameCodestreams(
            fragments: [soc(1), body(1), soc(2), body(2)], basicOffsetTable: [0, 24],
            extendedOffsetTable: nil, numberOfFrames: 2)
        #expect(frames == [soc(1) + body(1), soc(2) + body(2)])
    }

    @Test("The Extended Offset Table (7FE0,0001) takes precedence")
    func extendedOffsetTable() throws {
        let frames = try J2KDICOMBoundary.frameCodestreams(
            fragments: [soc(1), soc(2), body(2)], basicOffsetTable: [],
            extendedOffsetTable: [0, 12], numberOfFrames: 2)
        #expect(frames == [soc(1), soc(2) + body(2)])
    }

    @Test("Without a table, frames start at the fragments that begin with SOC (FF4F)")
    func socDelimited() throws {
        let frames = try J2KDICOMBoundary.frameCodestreams(
            fragments: [soc(1), body(1), body(1), soc(2), body(2)], basicOffsetTable: [],
            extendedOffsetTable: nil, numberOfFrames: 2)
        #expect(frames == [soc(1) + body(1) + body(1), soc(2) + body(2)])
    }

    @Test("A single frame is the concatenation of every fragment")
    func singleFrame() throws {
        let frames = try J2KDICOMBoundary.frameCodestreams(
            fragments: [soc(1), body(1), body(1)], basicOffsetTable: [], extendedOffsetTable: nil,
            numberOfFrames: 1)
        #expect(frames == [soc(1) + body(1) + body(1)])
    }

    @Test("An offset that does not land on an Item fails closed")
    func inconsistentTable() {
        #expect(throws: J2KDICOMBoundary.FrameError.self) {
            try J2KDICOMBoundary.frameCodestreams(
                fragments: [soc(1), body(1), soc(2)], basicOffsetTable: [0, 10],
                extendedOffsetTable: nil, numberOfFrames: 2)
        }
    }

    @Test("A fragmented multi-frame file is transcoded frame by frame")
    func fragmentedFileEndToEnd() throws {
        let (url, _) = try j2kLosslessOnlyFile(rgb: false, frames: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        // Split each frame's codestream into two fragments and add a Basic Offset Table.
        var file = try DICOMFile.read(from: Data(contentsOf: url))
        let whole = try J2KDICOMBoundary.frameCodestreams(of: file)
        #expect(whole.count == 3)
        var fragments: [Data] = []
        var offsets: [UInt32] = []
        var cursor: UInt32 = 0
        for cs in whole {
            offsets.append(cursor)
            let half = (cs.count / 4) * 2
            let parts = [cs.prefix(half), cs.dropFirst(half)].map { Data($0) }
            fragments += parts
            cursor += UInt32(parts.reduce(0) { $0 + 8 + $1.count })
        }
        var ds = file.dataSet
        ds[.pixelData] = DataElement(tag: .pixelData, vr: .OB, length: 0xFFFFFFFF, valueData: Data(),
                                     encapsulatedFragments: fragments, encapsulatedOffsetTable: offsets)
        file = DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: ds)
        let fragmented = tempURL("frag.dcm")
        let out = tempURL("out.dcm")
        defer { try? FileManager.default.removeItem(at: fragmented); try? FileManager.default.removeItem(at: out) }
        try file.write().write(to: fragmented)

        var cmd = try DICOMJ2K.TranscodeCommand.parse(
            [fragmented.path, "--output", out.path, "--target", "htj2k-lossless"])
        try cmd.run()
        let result = try DICOMFile.read(from: Data(contentsOf: out))
        // HTJ2K: each frame encoded as a single fragment (PS3.5 A.4.4).
        #expect(result.dataSet[.pixelData]?.encapsulatedFragments?.count == 3)
        #expect(result.transferSyntaxUID == "1.2.840.10008.1.2.4.203")
    }
}

// MARK: - Photometric Interpretation

@Suite("dicom-j2k: Photometric Interpretation follows the codestream (PS3.5 2026a 8.2.4, 8.2.14)")
struct PhotometricTests {

    @Test("COD fields are read from the main header")
    func codestreamFacts() {
        let f = J2KDICOMBoundary.codestreamFacts(codestream(progression: 2, mct: 1, levels: 3,
                                                            reversible: false, tlm: true))
        #expect(f == .init(progressionOrder: 2, multipleComponentTransform: 1, decompositionLevels: 3,
                           reversibleWavelet: false, hasTLM: true))
    }

    @Test("Reversible MCT → YBR_RCT, irreversible MCT → YBR_ICT (Table 8.2.4-1 / 8.2.14-1)")
    func mctSetsYBR() {
        let rct = J2KDICOMBoundary.codestreamFacts(codestream(mct: 1, reversible: true))
        let ict = J2KDICOMBoundary.codestreamFacts(codestream(mct: 1, reversible: false))
        #expect(J2KDICOMBoundary.photometricInterpretation(current: "RGB", samplesPerPixel: 3, facts: rct) == "YBR_RCT")
        #expect(J2KDICOMBoundary.photometricInterpretation(current: "RGB", samplesPerPixel: 3, facts: ict) == "YBR_ICT")
        #expect(J2KDICOMBoundary.photometricInterpretation(current: "YBR_RCT", samplesPerPixel: 3, facts: ict) == "YBR_ICT")
    }

    @Test("Without MCT a YBR_RCT / YBR_ICT source (decoded to RGB) becomes RGB; others are kept")
    func noMCT() {
        let none = J2KDICOMBoundary.codestreamFacts(codestream(mct: 0))
        #expect(J2KDICOMBoundary.photometricInterpretation(current: "YBR_RCT", samplesPerPixel: 3, facts: none) == "RGB")
        #expect(J2KDICOMBoundary.photometricInterpretation(current: "YBR_FULL", samplesPerPixel: 3, facts: none) == "YBR_FULL")
        #expect(J2KDICOMBoundary.photometricInterpretation(current: "MONOCHROME2", samplesPerPixel: 1, facts: none) == "MONOCHROME2")
    }
}

// MARK: - HTJ2K Lossless RPCL

@Suite("dicom-j2k: 1.2.840.10008.1.2.4.202 (PS3.5 2026a 10.18.1)")
struct RPCLTests {

    @Test("Decomposition levels for a base resolution ≤ 64")
    func minimumLevels() {
        #expect(J2KDICOMBoundary.minimumDecompositionLevelsForRPCL(rows: 64, columns: 64) == 0)
        #expect(J2KDICOMBoundary.minimumDecompositionLevelsForRPCL(rows: 65, columns: 10) == 1)
        #expect(J2KDICOMBoundary.minimumDecompositionLevelsForRPCL(rows: 512, columns: 512) == 3)
        #expect(J2KDICOMBoundary.minimumDecompositionLevelsForRPCL(rows: 3000, columns: 4000) == 6)
    }

    @Test("RPCL progression, enough levels and a TLM segment are required")
    func violations() {
        let ok = J2KDICOMBoundary.codestreamFacts(codestream(progression: 2, levels: 3, tlm: true))
        #expect(J2KDICOMBoundary.rpclViolations(ok, rows: 512, columns: 512).isEmpty)
        let bad = J2KDICOMBoundary.codestreamFacts(codestream(progression: 0, levels: 2, tlm: false))
        #expect(J2KDICOMBoundary.rpclViolations(bad, rows: 512, columns: 512).count == 3)
    }
}

// MARK: - Lossy provenance and derived images

@Suite("dicom-j2k: lossy provenance and derived images (PS3.3 2026a C.7.6.1.1.2, C.7.6.1.1.5)")
struct ProvenanceTests {

    @Test("An irreversible encode sets 01, appends the Ratio / Method pair, DERIVED and a new SOP Instance UID")
    func lossyAttributes() {
        var ds = DataSet()
        ds.setStrings(["ORIGINAL", "PRIMARY"], for: .imageType, vr: .CS)
        ds.setString("1.2.3.4", for: .sopInstanceUID, vr: .UI)
        ds.setString("01", for: .lossyImageCompression, vr: .CS)
        ds.setStrings(["10"], for: .lossyImageCompressionRatio, vr: .DS)
        ds.setStrings(["ISO_10918_1"], for: .lossyImageCompressionMethod, vr: .CS)
        var meta = DataSet()
        meta.setString("1.2.3.4", for: .mediaStorageSOPInstanceUID, vr: .UI)
        meta.setUInt32(123, for: .fileMetaInformationGroupLength)

        J2KDICOMBoundary.applyLossyCompression(to: &ds, meta: &meta, method: "ISO_15444_15",
                                               uncompressedBytes: 2000, compressedBytes: 100)
        #expect(ds.string(for: .lossyImageCompression) == "01")
        #expect(ds.strings(for: .lossyImageCompressionRatio)?.count == 2)
        #expect(ds.strings(for: .lossyImageCompressionRatio)?.last.flatMap { Double($0) } == 20)
        #expect(ds.strings(for: .lossyImageCompressionMethod) == ["ISO_10918_1", "ISO_15444_15"])
        #expect(ds.strings(for: .imageType)?.first == "DERIVED")
        let uid = ds.string(for: .sopInstanceUID)
        #expect(uid != "1.2.3.4")
        #expect(meta.string(for: .mediaStorageSOPInstanceUID) == uid)
        #expect(meta[.fileMetaInformationGroupLength] == nil)   // recomputed on write
        #expect(ds.string(for: .derivationDescription)?.contains("20.0:1") == true)
    }

    @Test("The Lossy Image Compression Method terms used are 2026a Defined Terms")
    func methodTerms() {
        // PS3.3 2026a C.7.6.1.1.5.1, dumped from part03: ISO_15444_1 JPEG 2000 Irreversible,
        // ISO_15444_15 High-Throughput JPEG 2000 Irreversible.
        #expect(TransferSyntax.jpeg2000.lossyImageCompressionMethod == "ISO_15444_1")
        #expect(TransferSyntax.jpeg2000Part2.lossyImageCompressionMethod == "ISO_15444_1")
        #expect(TransferSyntax.htj2kLossy.lossyImageCompressionMethod == "ISO_15444_15")
    }

    @Test("transcode to a lossy target writes YBR_ICT and the lossy provenance")
    func transcodeLossyEndToEnd() throws {
        let (url, sop) = try j2kLosslessOnlyFile(rgb: true)
        let out = tempURL("lossy.dcm")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: out) }
        var cmd = try DICOMJ2K.TranscodeCommand.parse(
            [url.path, "--output", out.path, "--target", "j2k-lossy", "--quality", "0.5"])
        try cmd.run()
        let result = try DICOMFile.read(from: Data(contentsOf: out))
        let ds = result.dataSet
        #expect(result.transferSyntaxUID == "1.2.840.10008.1.2.4.91")
        #expect(ds.string(for: .lossyImageCompression) == "01")
        #expect(ds.strings(for: .lossyImageCompressionMethod) == ["ISO_15444_1"])
        #expect(ds.strings(for: .imageType)?.first == "DERIVED")
        #expect(ds.string(for: .sopInstanceUID) != sop)
        #expect(result.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID) == ds.string(for: .sopInstanceUID))
        let cs = try #require(ds[.pixelData]?.encapsulatedFragments?.first)
        let facts = J2KDICOMBoundary.codestreamFacts(cs)
        if facts?.multipleComponentTransform == 1 {
            #expect(ds.string(for: .photometricInterpretation) == (facts!.reversibleWavelet ? "YBR_RCT" : "YBR_ICT"))
        }
        #expect(ds.uint16(for: .planarConfiguration) == 0)
    }

    @Test("--quality reaches the encoder")
    func qualityIsApplied() throws {
        let (url, _) = try j2kLosslessOnlyFile(rgb: false, rows: 64, columns: 64)
        let low = tempURL("q1.dcm"), high = tempURL("q9.dcm")
        defer { for u in [url, low, high] { try? FileManager.default.removeItem(at: u) } }
        var a = try DICOMJ2K.TranscodeCommand.parse([url.path, "-o", low.path, "-t", "j2k-lossy", "-q", "0.1"])
        try a.run()
        var b = try DICOMJ2K.TranscodeCommand.parse([url.path, "-o", high.path, "-t", "j2k-lossy", "-q", "0.95"])
        try b.run()
        func size(_ u: URL) throws -> Int {
            try DICOMFile.read(from: Data(contentsOf: u)).dataSet[.pixelData]?
                .encapsulatedFragments?.reduce(0) { $0 + $1.count } ?? 0
        }
        #expect(try size(low) < size(high))
    }

    @Test("A lossless transcode keeps the SOP Instance UID and sets no lossy attributes")
    func losslessKeepsIdentity() throws {
        let (url, sop) = try j2kLosslessOnlyFile(rgb: true)
        let out = tempURL("ll.dcm")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: out) }
        var cmd = try DICOMJ2K.TranscodeCommand.parse([url.path, "-o", out.path, "-t", "htj2k-lossless-only"])
        try cmd.run()
        let ds = try DICOMFile.read(from: Data(contentsOf: out)).dataSet
        #expect(ds.string(for: .sopInstanceUID) == sop)
        #expect(ds[.lossyImageCompression] == nil)
        #expect(ds.strings(for: .imageType)?.first == "ORIGINAL")
    }
}

// MARK: - ROI

@Suite("dicom-j2k: roi output is a consistent derived single-frame image")
struct ROITests {

    @Test("Image Position (Patient) moves to the crop origin (C.7.6.2.1.1)")
    func shiftedPosition() {
        // rowDir = +x, colDir = +y; Pixel Spacing = row spacing 0.5 \ column spacing 0.25.
        let p = J2KDICOMBoundary.shiftedPosition(ipp: [10, 20, 30], iop: [1, 0, 0, 0, 1, 0],
                                                 spacing: [0.5, 0.25], x: 8, y: 4)
        #expect(p == [12, 22, 30])
    }

    @Test("Enhanced multi-frame: one Per-frame Functional Groups item, shifted position, 1 frame")
    func enhancedCrop() {
        func posItem(_ z: String) -> SequenceItem {
            var plane = DataSet()
            plane.setStrings(["0", "0", z], for: .imagePositionPatient, vr: .DS)
            var item = DataSet()
            item.setSequence([SequenceItem(elements: plane.allElements)], for: .planePositionSequence)
            return SequenceItem(elements: item.allElements)
        }
        var orient = DataSet(); orient.setStrings(["1", "0", "0", "0", "1", "0"], for: .imageOrientationPatient, vr: .DS)
        var measures = DataSet(); measures.setStrings(["2", "1"], for: .pixelSpacing, vr: .DS)
        var shared = DataSet()
        shared.setSequence([SequenceItem(elements: orient.allElements)], for: .planeOrientationSequence)
        shared.setSequence([SequenceItem(elements: measures.allElements)], for: .pixelMeasuresSequence)
        var ds = DataSet()
        ds.setString("3", for: .numberOfFrames, vr: .IS)
        ds.setSequence([SequenceItem(elements: shared.allElements)], for: .sharedFunctionalGroupsSequence)
        ds.setSequence([posItem("0"), posItem("5"), posItem("10")], for: .perFrameFunctionalGroupsSequence)

        J2KDICOMBoundary.applyCrop(to: &ds, frame: 1, x: 3, y: 2, width: 10, height: 6)
        #expect(ds.string(for: .numberOfFrames) == "1")
        #expect(ds.uint16(for: .rows) == 6)
        #expect(ds.uint16(for: .columns) == 10)
        let items = ds.sequence(for: .perFrameFunctionalGroupsSequence)
        #expect(items?.count == 1)
        let position = items?.first?[.planePositionSequence]?.sequenceItems?.first?
            .strings(for: .imagePositionPatient)?.compactMap { Double($0) }
        #expect(position == [3, 4, 5])   // x·1·rowDir + y·2·colDir from (0, 0, 5)
    }

    @Test("roi on a multi-frame file: Number of Frames 1, DERIVED, new SOP Instance UID")
    func roiEndToEnd() throws {
        let (url, sop) = try j2kLosslessOnlyFile(rgb: false, frames: 3)
        let out = tempURL("roi.dcm")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: out) }
        var cmd = try DICOMJ2K.ROICommand.parse([url.path, "-o", out.path, "--frame", "1", "--region", "8,4,16,12"])
        try cmd.run()
        let result = try DICOMFile.read(from: Data(contentsOf: out))
        let ds = result.dataSet
        #expect(ds.string(for: .numberOfFrames) == "1")
        #expect(ds.uint16(for: .rows) == 12)
        #expect(ds.uint16(for: .columns) == 16)
        #expect(ds.strings(for: .imageType)?.first == "DERIVED")
        #expect(ds.string(for: .sopInstanceUID) != sop)
        #expect(result.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID) == ds.string(for: .sopInstanceUID))
        #expect(ds.strings(for: .imagePositionPatient)?.compactMap { Double($0) } == [12, 22, 30])
        #expect(ds[.pixelData]?.encapsulatedFragments?.count == 1)
    }

    @Test("A negative origin is refused")
    func negativeOrigin() {
        #expect(throws: (any Error).self) {
            _ = try DICOMJ2K.ROICommand.parse(["in.dcm", "-o", "o.dcm", "--region=-1,0,4,4"])
        }
    }
}

// MARK: - compare, validate, help

@Suite("dicom-j2k: compare decodes samples per Bits Allocated (PS3.3 C.7.6.3)")
struct CompareTests {

    @Test("A native 16-bit file and its lossless J2K are identical sample by sample")
    func native16VersusJ2K() throws {
        let sop = UIDGenerator.generateSOPInstanceUID().value
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString(sop, for: .sopInstanceUID, vr: .UI)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds.setUInt16(16, for: .rows); ds.setUInt16(16, for: .columns)
        ds.setUInt16(16, for: .bitsAllocated); ds.setUInt16(12, for: .bitsStored)
        ds.setUInt16(11, for: .highBit); ds.setUInt16(0, for: .pixelRepresentation)
        var words = [UInt16]()
        for i in 0..<256 { words.append(UInt16((i * 37) % 4096)) }
        let bytes = words.withUnsafeBufferPointer { Data(buffer: $0) }
        ds[.pixelData] = DataElement(tag: .pixelData, vr: .OW, length: UInt32(bytes.count), valueData: bytes)
        let native = try DICOMFile.create(dataSet: ds, sopInstanceUID: sop).write()
        let j2k = try CompressionManager().compressData(native, codec: "jpeg2000-lossless-only", quality: nil)
        let a = tempURL("n.dcm"), b = tempURL("j.dcm")
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        try native.write(to: a); try j2k.write(to: b)
        var cmd = try DICOMJ2K.CompareCommand.parse([a.path, b.path, "--json"])
        try cmd.run()   // threw "Pixel count mismatch" when native samples were read as bytes
    }
}

@Suite("dicom-j2k: help text")
struct HelpTextTests {

    @Test("The UID list names each syntax as PS3.6 2026a Table A-1 does")
    func uidNames() {
        // Dumped from part06_2026a.xml Table A-1.
        let a1 = [
            "1.2.840.10008.1.2.4.90  JPEG 2000 Image Compression (Lossless Only)",
            "1.2.840.10008.1.2.4.91  JPEG 2000 Image Compression",
            "1.2.840.10008.1.2.4.92  JPEG 2000 Part 2 Multi-component Image Compression (Lossless Only)",
            "1.2.840.10008.1.2.4.93  JPEG 2000 Part 2 Multi-component Image Compression",
            "1.2.840.10008.1.2.4.201 High-Throughput JPEG 2000 Image Compression (Lossless Only)",
            "1.2.840.10008.1.2.4.202 High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only)",
            "1.2.840.10008.1.2.4.203 High-Throughput JPEG 2000 Image Compression",
        ]
        let help = DICOMJ2K.configuration.discussion
        for row in a1 { #expect(help.contains(row), "\(row)") }
    }

    @Test("Each transcode target row resolves to the UID and intent it shows")
    func targetRows() throws {
        let rows = DICOMJ2K.TranscodeCommand.configuration.discussion
            .split(separator: "\n").map(String.init)
            .filter { $0.contains("(1.2.840.10008.1.2.4.") }
        #expect(rows.count == 10)
        for row in rows {
            let alias = String(row.trimmingCharacters(in: .whitespaces).split(separator: " ")[0])
            let uid = String(row[row.range(of: "(1.2")!.upperBound...].dropLast())
            let enc = try #require(TransferSyntax.parseEncoding(alias), "\(alias)")
            #expect("1.2" + uid == enc.transferSyntax.uid, "\(alias)")
            #expect(row.contains("lossy") == !enc.isLossless, "\(alias)")
        }
    }

    @Test("Examples use only options that exist")
    func benchmarkExample() {
        #expect(!DICOMJ2K.configuration.discussion.contains("--backends"))
    }

    @Test("validate exits 2 when the file cannot be read")
    func validateReadError() throws {
        var cmd = try DICOMJ2K.ValidateCommand.parse(["/nonexistent/x.dcm"])
        #expect(throws: ExitCode(2)) { try cmd.run() }
    }
}

// MARK: - P-items (2026-10-01): P-J2K-FRAME, P-J2K-JSON, P-J2K-PART2, P-CONVERT-TS-KEYWORDS

@Suite("dicom-j2k P-items: Frame number, JSON keys, Part 2 targets, Table A-1 keywords")
struct J2KPItemTests {

    // PS3.3 2026a Table 10-3: "The first Frame shall be denoted as Frame number 1".
    @Test("--frame-number is 1-based on every subcommand that selects a frame")
    func frameNumber() throws {
        #expect(try DICOMJ2K.InfoCommand.parse(["a.dcm", "--frame-number", "2"]).frame == 1)
        #expect(try DICOMJ2K.ValidateCommand.parse(["a.dcm", "--frame-number", "1"]).frame == 0)
        #expect(try DICOMJ2K.BenchmarkCommand.parse(["a.dcm", "--frame-number", "3"]).frame == 2)
        #expect(try DICOMJ2K.CompareCommand.parse(["a.dcm", "b.dcm", "--frame-number", "4"]).frame == 3)
        #expect(try DICOMJ2K.ROICommand.parse(["a.dcm", "-o", "o.dcm", "--region", "0,0,1,1", "--frame-number", "2"]).frame == 1)
        // Deprecated 0-based --frame keeps its meaning; default is the first frame.
        #expect(try DICOMJ2K.InfoCommand.parse(["a.dcm", "--frame", "2"]).frame == 2)
        #expect(try DICOMJ2K.InfoCommand.parse(["a.dcm"]).frame == 0)
    }

    @Test("--frame with --frame-number exits 1; --frame-number 0 is a usage error")
    func frameConflict() {
        do {
            _ = try DICOMJ2K.InfoCommand.parse(["a.dcm", "--frame", "0", "--frame-number", "1"])
            Issue.record("expected a refusal")
        } catch {
            #expect(DICOMJ2K.InfoCommand.exitCode(for: error) == .failure)
        }
        do {
            _ = try DICOMJ2K.InfoCommand.parse(["a.dcm", "--frame-number", "0"])
            Issue.record("expected a refusal")
        } catch {
            #expect(DICOMJ2K.InfoCommand.exitCode(for: error) == .validationFailure)
        }
    }

    @Test("--help marks --frame deprecated")
    func frameHelp() {
        for help in [DICOMJ2K.InfoCommand.helpMessage(), DICOMJ2K.ValidateCommand.helpMessage(),
                     DICOMJ2K.ROICommand.helpMessage(), DICOMJ2K.BenchmarkCommand.helpMessage(),
                     DICOMJ2K.CompareCommand.helpMessage()] {
            #expect(help.contains("--frame-number"))
            #expect(help.contains("deprecated: 0-based index; use --frame-number"))
        }
    }

    @Test("roi --frame-number: Derivation Description names the Frame number")
    func roiFrameNumber() throws {
        let (url, _) = try j2kLosslessOnlyFile(rgb: false, frames: 3)
        let out = tempURL("roi-fn.dcm")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: out) }
        var cmd = try DICOMJ2K.ROICommand.parse([url.path, "-o", out.path, "--frame-number", "2", "--region", "8,4,16,12"])
        try cmd.run()
        let ds = try DICOMFile.read(from: Data(contentsOf: out)).dataSet
        #expect(ds.string(for: .derivationDescription)?.contains("of Frame number 2 of") == true)
        // Same crop as the deprecated --frame 1 (roiEndToEnd).
        #expect(ds.strings(for: .imagePositionPatient)?.compactMap { Double($0) } == [12, 22, 30])
    }

    @Test("An out-of-range frame is reported as a Frame number")
    func outOfRange() {
        let text = "\(J2KDICOMBoundary.FrameError.frameOutOfRange(3, 3))"
        #expect(text.contains("Frame number 4"))
        #expect(text.contains("Frame number 1"))
    }

    // PS3.6 2026a Table 6-1 (dumped from part06_2026a.xml): (0002,0010) TransferSyntaxUID,
    // (0028,0008) NumberOfFrames.
    @Test("JSON keyword keys are the PS3.6 Table 6-1 keywords")
    func jsonKeys() {
        let fields = J2KJSONKeys.keywordFields(transferSyntaxUID: "1.2.840.10008.1.2.4.90", numberOfFrames: 3)
        #expect(Set(fields.keys) == ["TransferSyntaxUID", "NumberOfFrames"])
        #expect(fields["TransferSyntaxUID"] as? String == "1.2.840.10008.1.2.4.90")
        #expect(fields["NumberOfFrames"] as? Int == 3)
        #expect(Set(J2KJSONKeys.keywordFields(transferSyntaxUID: "1.2", numberOfFrames: nil).keys) == ["TransferSyntaxUID"])
        #expect(DICOMJ2K.InfoCommand.configuration.discussion.contains("deprecated"))
        #expect(DICOMJ2K.ValidateCommand.configuration.discussion.contains("deprecated"))
    }

    // PS3.5 2026a A.4.4: .92 / .93 specify the Part 2 (Annex J) multiple component
    // transformation extensions; the encoder writes Part 1 only.
    @Test("The three j2k-part2-* targets are refused with exit 1 and listed as refused")
    func part2Refused() throws {
        for target in ["j2k-part2-lossy", "j2k-part2-lossless", "j2k-part2-lossless-only", "JPEG2000MC", "JPEG2000MCLossless"] {
            do {
                _ = try DICOMJ2K.TranscodeCommand.parse(["a.dcm", "-o", "o.dcm", "-t", target])
                Issue.record("\(target) accepted")
            } catch {
                #expect(DICOMJ2K.TranscodeCommand.exitCode(for: error) == .failure, "\(target)")
                #expect("\(error)".contains("PS3.5 2026a A.4.4") || DICOMJ2K.TranscodeCommand.message(for: error).contains("A.4.4"), "\(target)")
            }
        }
        for target in ["j2k-lossy", "j2k-lossless", "j2k-lossless-only", "htj2k-lossy", "htj2k-lossless",
                       "htj2k-lossless-only", "htj2k-rpcl-lossless-only"] {
            #expect(throws: Never.self) { _ = try DICOMJ2K.TranscodeCommand.parse(["a.dcm", "-o", "o.dcm", "-t", target]) }
        }
        let help = DICOMJ2K.TranscodeCommand.configuration.discussion
        let refused = try #require(help.range(of: "Refused (exit 1)"))
        for row in ["j2k-part2-lossy", "j2k-part2-lossless ", "j2k-part2-lossless-only"] {
            let at = try #require(help.range(of: "  " + row))
            #expect(at.lowerBound > refused.lowerBound, "\(row) listed as refused")
        }
        #expect(DICOMJ2K.TranscodeCommand.part2RefusalReason(.jpeg2000Part2) != nil)
        #expect(DICOMJ2K.TranscodeCommand.part2RefusalReason(.jpeg2000Part2Lossless) != nil)
        for ts: TransferSyntax in [.jpeg2000, .jpeg2000Lossless, .htj2kLossless, .htj2kRPCLLossless, .htj2kLossy] {
            #expect(DICOMJ2K.TranscodeCommand.part2RefusalReason(ts) == nil)
        }
    }

    // PS3.6 2026a Table A-1 keywords (dumped): JPEG2000Lossless .90, JPEG2000 .91,
    // HTJ2KLossless .201, HTJ2KLosslessRPCL .202, HTJ2K .203, JPEGXLLossless .110, JPEGXL .112.
    @Test("--target Table A-1 keywords select their Table A-1 UID; …Reversible keeps the old meaning")
    func tableA1Keywords() throws {
        let a1: [String: String] = [
            "JPEG2000Lossless": "1.2.840.10008.1.2.4.90", "JPEG2000": "1.2.840.10008.1.2.4.91",
            "HTJ2KLossless": "1.2.840.10008.1.2.4.201", "HTJ2KLosslessRPCL": "1.2.840.10008.1.2.4.202",
            "HTJ2K": "1.2.840.10008.1.2.4.203", "JPEGXLLossless": "1.2.840.10008.1.2.4.110",
            "JPEGXL": "1.2.840.10008.1.2.4.112",
        ]
        for (keyword, uid) in a1 {
            #expect(TransferSyntax.parseEncoding(keyword)?.transferSyntax.uid == uid, "\(keyword)")
        }
        for (name, uid) in ["JPEG2000Reversible": "1.2.840.10008.1.2.4.91", "HTJ2KReversible": "1.2.840.10008.1.2.4.203",
                            "JPEGXLReversible": "1.2.840.10008.1.2.4.112"] {
            let enc = try #require(TransferSyntax.parseEncoding(name), "\(name)")
            #expect(enc.transferSyntax.uid == uid && enc.intent == .lossless, "\(name)")
        }
        #expect(TransferSyntax.reassignedKeywordNote(for: "JPEG2000Lossless")?.contains("1.2.840.10008.1.2.4.90") == true)
        #expect(TransferSyntax.reassignedKeywordNote(for: "j2k-lossless") == nil)
    }
}
