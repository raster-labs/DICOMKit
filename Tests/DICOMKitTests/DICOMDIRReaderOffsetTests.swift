import Testing
import Foundation
@testable import DICOMKit
import DICOMCore

/// PS3.3 2026a F.3.2.2 and Table F.3-3: the Root Directory Entity starts at Offset of the First
/// Directory Record of the Root Directory Entity (0004,1200), the records of a Directory Entity
/// are chained by Offset of the Next Directory Record (0004,1400), and a record's lower-level
/// entity starts at Offset of Referenced Lower-Level Directory Entity (0004,1420); each offset
/// is "a number of bytes starting with the first byte of the File Meta Information" and points
/// at "the first byte (of the Item Data Element)". Table F.4-1 / F.6.1: PRIVATE records may sit
/// under any record type (D240).
@Suite("DICOMDIRReader offsets")
struct DICOMDIRReaderOffsetTests {

    private func record(_ type: String, next: UInt32, lower: UInt32, _ extra: [DataElement] = []) -> SequenceItem {
        SequenceItem(elements: [
            .uint32(tag: .offsetOfTheNextDirectoryRecord, value: next),
            .uint16(tag: .recordInUseFlag, value: 0xFFFF),
            .uint32(tag: .offsetOfReferencedLowerLevelDirectoryEntity, value: lower),
            .string(tag: .directoryRecordType, vr: .CS, value: type),
        ] + extra)
    }

    private func fileMeta() -> DataSet {
        var meta = DataSet()
        meta[.fileMetaInformationVersion] = .data(tag: .fileMetaInformationVersion, vr: .OB, data: Data([0x00, 0x01]))
        meta[.mediaStorageSOPClassUID] = .string(tag: .mediaStorageSOPClassUID, vr: .UI, value: "1.2.840.10008.1.3.10")
        meta[.mediaStorageSOPInstanceUID] = .string(tag: .mediaStorageSOPInstanceUID, vr: .UI, value: "1.2.3.4.5")
        meta[.transferSyntaxUID] = .string(tag: .transferSyntaxUID, vr: .UI, value: TransferSyntax.explicitVRLittleEndian.uid)
        meta[.implementationClassUID] = .string(tag: .implementationClassUID, vr: .UI, value: DICOMFile.implementationClassUID)
        return meta
    }

    /// Encodes the records in the given sequence order; `links(offsetOf)` returns, per item,
    /// (next, lower) as item indices, plus the root's first index. Two passes, as the writer:
    /// the offsets are fixed-size UL, so the measured item positions stay valid.
    private func encode(
        _ specs: [(type: String, extra: [DataElement])],
        links: [(next: Int?, lower: Int?)],
        rootFirst: Int
    ) throws -> Data {
        func build(_ offsets: [Int]?) throws -> Data {
            func at(_ index: Int?) -> UInt32 { index.flatMap { i in offsets.map { UInt32($0[i]) } } ?? 0 }
            var dataSet = DataSet()
            dataSet.setString("OFFSETS", for: .fileSetID, vr: .CS)
            dataSet[.offsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity] =
                .uint32(tag: .offsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity, value: at(rootFirst))
            dataSet[.offsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity] =
                .uint32(tag: .offsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity, value: 0)
            dataSet[.fileSetConsistencyFlag] = .uint16(tag: .fileSetConsistencyFlag, value: 0)
            dataSet.setSequence(specs.indices.map { i in
                record(specs[i].type, next: at(links[i].next), lower: at(links[i].lower), specs[i].extra)
            }, for: .directoryRecordSequence)
            return try DICOMFile(fileMetaInformation: fileMeta(), dataSet: dataSet).write()
        }
        let probe = try build(nil)
        let offsets = try #require(DICOMDIRReader.directoryRecordItemOffsets(in: probe))
        #expect(offsets.count == specs.count)
        return try build(offsets)
    }

    @Test("Records out of depth-first order are placed by their offsets; PRIVATE is kept")
    func outOfOrderRecordsFollowOffsets() throws {
        // sequence order: 0 IMAGE A1, 1 SERIES A, 2 PATIENT B, 3 STUDY A, 4 PATIENT A,
        //                 5 IMAGE A2, 6 PRIVATE (under STUDY A), 7 STUDY B
        let specs: [(type: String, extra: [DataElement])] = [
            ("IMAGE", [.strings(tag: .referencedFileID, vr: .CS, values: ["A1"])]),
            ("SERIES", [.string(tag: .seriesInstanceUID, vr: .UI, value: "1.2.3.1")]),
            ("PATIENT", [.string(tag: .patientID, vr: .LO, value: "B")]),
            ("STUDY", [.string(tag: .studyInstanceUID, vr: .UI, value: "1.2.3")]),
            ("PATIENT", [.string(tag: .patientID, vr: .LO, value: "A")]),
            ("IMAGE", [.strings(tag: .referencedFileID, vr: .CS, values: ["A2"])]),
            ("PRIVATE", [.string(tag: .privateRecordUID, vr: .UI, value: "1.2.826.0.1.3680043.2.1")]),
            ("STUDY", [.string(tag: .studyInstanceUID, vr: .UI, value: "1.2.4")]),
        ]
        let links: [(next: Int?, lower: Int?)] = [
            (5, nil),   // IMAGE A1 -> IMAGE A2
            (nil, 0),   // SERIES A -> [IMAGE A1, IMAGE A2]
            (nil, 7),   // PATIENT B -> [STUDY B]
            (6, 1),     // STUDY A -> [SERIES A]; next PRIVATE
            (2, 3),     // PATIENT A (root first) -> PATIENT B; lower STUDY A
            (nil, nil), (nil, nil), (nil, nil),
        ]
        let data = try encode(specs, links: links, rootFirst: 4)
        let directory = try DICOMDIRReader.read(from: data)

        #expect(directory.rootRecords.map { $0.attribute(for: .patientID)?.stringValue } == ["A", "B"])
        let patientA = directory.rootRecords[0]
        #expect(patientA.children.map(\.recordType) == [.study, .private])
        #expect(patientA.children[1].attribute(for: .privateRecordUID)?.stringValue == "1.2.826.0.1.3680043.2.1")
        let series = try #require(patientA.children[0].children.first)
        #expect(series.recordType == .series)
        #expect(series.children.map { $0.referencedFileID ?? [] } == [["A1"], ["A2"]])
        #expect(directory.rootRecords[1].children.map { $0.attribute(for: .studyInstanceUID)?.stringValue } == ["1.2.4"])
    }

    @Test("The writer's offsets are read back: same tree, PRIVATE under SERIES kept")
    func writerRoundTrip() throws {
        var series = DirectoryRecord(recordType: .series, attributes: [
            .seriesInstanceUID: .string(tag: .seriesInstanceUID, vr: .UI, value: "1.2.3.1")])
        series.addChild(DirectoryRecord(recordType: .image, referencedFileID: ["IMG1"]))
        series.addChild(DirectoryRecord(recordType: .private, attributes: [
            .privateRecordUID: .string(tag: .privateRecordUID, vr: .UI, value: "1.2.826.0.1.3680043.2.2")]))
        var study = DirectoryRecord(recordType: .study)
        study.addChild(series)
        var patient = DirectoryRecord(recordType: .patient)
        patient.addChild(study)
        let written = DICOMDirectory(fileSetID: "RT", rootRecords: [patient, DirectoryRecord(recordType: .palette)])
        let data = try DICOMDIRWriter.write(written)

        let offsets = try #require(DICOMDIRReader.directoryRecordItemOffsets(in: data))
        #expect(offsets.count == 6)
        let file = try DICOMFile.read(from: data)
        #expect(file.dataSet.uint32(for: .offsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity).map(Int.init) == offsets[0])
        #expect(Array(data[offsets[0]..<offsets[0] + 4]) == [0xFE, 0xFF, 0x00, 0xE0], "offset is the Item tag's first byte")

        let read = try DICOMDIRReader.read(from: data)
        #expect(read.rootRecords.map(\.recordType) == [.patient, .palette])
        let readSeries = try #require(read.rootRecords.first?.children.first?.children.first)
        #expect(readSeries.children.map(\.recordType) == [.image, .private])
    }

    @Test("Offsets that do not resolve fall back to the sequence order")
    func unresolvableOffsetsFallBack() throws {
        let specs: [(type: String, extra: [DataElement])] = [("PATIENT", []), ("STUDY", []), ("SERIES", []), ("IMAGE", [])]
        // well-formed offsets, but read with a map on which none of them lands
        let data = try encode(specs, links: [(nil, 1), (nil, 2), (nil, 3), (nil, nil)], rootFirst: 0)
        let file = try DICOMFile.read(from: data)
        let items = try #require(file.dataSet.sequence(for: .directoryRecordSequence))
        let parsed = items.map { _ in Optional(DirectoryRecord(recordType: .image)) }
        #expect(DICOMDIRReader.recordTree(items: items, parsed: parsed, itemByteOffsets: [1, 2, 3, 4], rootFirstOffset: 999) == nil)
        #expect(DICOMDIRReader.recordTree(items: items, parsed: parsed, itemByteOffsets: [1, 2, 3, 4], rootFirstOffset: 0) == nil)
        // the sequence-order fallback still yields PATIENT > STUDY > SERIES > IMAGE
        let directory = try DICOMDIRReader.parse(dataSet: file.dataSet, itemByteOffsets: [1, 2, 3, 4])
        let series = try #require(directory.rootRecords.first?.children.first?.children.first)
        #expect(series.children.map(\.recordType) == [.image])
    }

    @Test("A Record In-use Flag other than 0000H is read as FFFFH")
    func inUseFlagOtherValuesAreActive() throws {
        var dataSet = DataSet()
        dataSet.setSequence([
            SequenceItem(elements: [
                .uint16(tag: .recordInUseFlag, value: 0x0001),
                .string(tag: .directoryRecordType, vr: .CS, value: "PATIENT"),
            ]),
        ], for: .directoryRecordSequence)
        let directory = try DICOMDIRReader.parse(dataSet: dataSet)
        #expect(directory.rootRecords.first?.isActive == true)
    }

    @Test("Undefined-length items and nested sequences are walked to the item offsets")
    func undefinedLengthWalk() throws {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16 & 0xFFFF) }
        func element(_ g: Int, _ e: Int, _ vr: String, _ value: [UInt8]) -> [UInt8] {
            le16(g) + le16(e) + Array(vr.utf8) + le16(value.count) + value
        }
        let ts = Array("1.2.840.10008.1.2.1".utf8) + [0]
        let meta = element(0x0002, 0x0010, "UI", ts)
        var bytes = [UInt8](repeating: 0, count: 128) + Array("DICM".utf8)
            + element(0x0002, 0x0000, "UL", le32(meta.count)) + meta
        bytes += element(0x0004, 0x1130, "CS", Array("FS".utf8))
        // (0004,1220) SQ, undefined length
        bytes += le16(0x0004) + le16(0x1220) + Array("SQ".utf8) + [0, 0] + le32(0xFFFF_FFFF)
        let first = bytes.count
        // item 1: undefined length, holding an undefined-length nested SQ with one item
        bytes += le16(0xFFFE) + le16(0xE000) + le32(0xFFFF_FFFF)
        bytes += element(0x0004, 0x1430, "CS", Array("PATIENT ".utf8))
        bytes += le16(0x0088) + le16(0x0200) + Array("SQ".utf8) + [0, 0] + le32(0xFFFF_FFFF)
        bytes += le16(0xFFFE) + le16(0xE000) + le32(0xFFFF_FFFF)
        bytes += element(0x0028, 0x0010, "US", le16(64))
        bytes += le16(0xFFFE) + le16(0xE00D) + le32(0)
        bytes += le16(0xFFFE) + le16(0xE0DD) + le32(0)
        bytes += le16(0xFFFE) + le16(0xE00D) + le32(0)
        // item 2: defined length
        let second = bytes.count
        let body = element(0x0004, 0x1430, "CS", Array("STUDY ".utf8))
        bytes += le16(0xFFFE) + le16(0xE000) + le32(body.count) + body
        bytes += le16(0xFFFE) + le16(0xE0DD) + le32(0)

        #expect(DICOMDIRReader.directoryRecordItemOffsets(in: Data(bytes)) == [first, second])
        // no preamble / "DICM": not walked
        #expect(DICOMDIRReader.directoryRecordItemOffsets(in: Data(bytes.dropFirst(132))) == nil)
    }
}
