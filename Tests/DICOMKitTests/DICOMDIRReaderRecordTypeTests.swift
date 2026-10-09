import Testing
import Foundation
@testable import DICOMKit
import DICOMCore

/// PS3.3 2026a Table F.3-3 enumerates the Directory Record Types, including PRIVATE, and
/// F.6.1 says a File-set Reader that ignores privately defined Directory Records "will find a
/// conformant Directory". A DICOMDIR carrying a record type this reader does not know must
/// therefore still open, with that record skipped (D14).
@Suite("DICOMDIRReader record types")
struct DICOMDIRReaderRecordTypeTests {

    private func record(_ type: String, _ extra: [DataElement] = []) -> SequenceItem {
        var elements: [DataElement] = [
            .uint32(tag: .offsetOfTheNextDirectoryRecord, value: 0),
            .uint16(tag: .recordInUseFlag, value: 0xFFFF),
            .uint32(tag: .offsetOfReferencedLowerLevelDirectoryEntity, value: 0),
            .string(tag: .directoryRecordType, vr: .CS, value: type),
        ]
        elements.append(contentsOf: extra)
        return SequenceItem(elements: elements)
    }

    private func directory(with items: [SequenceItem]) -> DataSet {
        var dataSet = DataSet()
        dataSet.setString("TEST", for: .fileSetID, vr: .CS)
        dataSet.setSequence(items, for: .directoryRecordSequence)
        return dataSet
    }

    @Test("A record type from a later edition is skipped, not fatal; PRIVATE is kept (D240)")
    func unknownRecordTypesAreSkipped() throws {
        let items = [
            record("PATIENT", [.string(tag: .patientID, vr: .LO, value: "P1")]),
            record("STUDY"),
            record("SERIES"),
            record("IMAGE", [.string(tag: .referencedFileID, vr: .CS, value: "IMG1")]),
            record("PRIVATE", [.string(tag: .privateRecordUID, vr: .UI, value: "1.2.3.4")]),
            record("NOT A 2026A TYPE"),
        ]

        let directory = try DICOMDIRReader.parse(dataSet: directory(with: items))

        #expect(directory.rootRecords.count == 1)
        let patient = try #require(directory.rootRecords.first)
        #expect(patient.recordType == .patient)
        let study = try #require(patient.children.first)
        let series = try #require(study.children.first)
        // PS3.3 2026a Table F.4-1: PRIVATE may sit under any record type; in sequence order it
        // belongs to the open SERIES
        #expect(series.children.map(\.recordType) == [.image, .private])
    }

    @Test("A record without Directory Record Type (Type 1) is an error")
    func missingRecordTypeThrows() {
        let broken = SequenceItem(elements: [
            .uint16(tag: .recordInUseFlag, value: 0xFFFF),
        ])
        #expect(throws: DICOMError.self) {
            _ = try DICOMDIRReader.parse(dataSet: directory(with: [broken]))
        }
    }
}
