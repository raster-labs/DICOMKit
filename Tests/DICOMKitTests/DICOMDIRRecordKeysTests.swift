//
// DICOMDIRRecordKeysTests.swift
// DICOMKitTests
//
// PS3.3 2026a Annex F: the Directory Record Type that references each SOP Class (F.5 "This
// Directory Record shall be used to reference ..."), its Type 1 / 2 keys (Tables F.5-1 to
// F.5-49), the File-set Consistency Flag (Table F.3-3: "The Value FFFFH shall never be
// present") and the record hierarchy of Table F.4-1 (D229-D232); PS3.11 2026a per-profile
// image attribute values (Tables A.3-3, B.3-3, B.3-4, C.3-2, E.3-3 to E.3-6, K.3-3, K.3-4,
// L.4-1, L.4-2) and the "Multi-frame Composite IODs" rows (D233).
//

import XCTest
@testable import DICOMKit
@testable import DICOMCore

final class DICOMDIRRecordKeysTests: XCTestCase {

    private var counter = 0
    private func uid() -> String {
        counter += 1
        return "1.2.826.0.1.3680043.10.1078.77.\(counter)"
    }

    private func file(_ sopClass: String, transferSyntax: String = "1.2.840.10008.1.2.1",
                      _ configure: (inout DataSet) -> Void = { _ in }) -> DICOMFile {
        var ds = DataSet()
        let instanceUID = uid()
        ds.setString(sopClass, for: .sopClassUID, vr: .UI)
        ds.setString(instanceUID, for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.3.100", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.3.100.1", for: .seriesInstanceUID, vr: .UI)
        ds.setString("P1", for: .patientID, vr: .LO)
        ds.setString("Doe^Jane", for: .patientName, vr: .PN)
        configure(&ds)
        return DICOMFile.create(dataSet: ds, sopClassUID: sopClass, sopInstanceUID: instanceUID,
                                transferSyntaxUID: transferSyntax)
    }

    private func fileID(_ n: Int) -> [String] { ["DICOM", "IM\(n)"] }

    private func onlyLeaf(_ directory: DICOMDirectory) throws -> DirectoryRecord {
        let patient = try XCTUnwrap(directory.rootRecords.first)
        return try XCTUnwrap(patient.children.first?.children.first?.children.first)
    }

    // MARK: - Record type per SOP Class (PS3.3 F.5)

    func testRecordTypePerSOPClassFollowsF5() {
        let expected: [String: DirectoryRecordType] = [
            "1.2.840.10008.5.1.4.1.1.2": .image,                       // CT Image
            "1.2.840.10008.5.1.4.1.1.88.33": .srDocument,               // Comprehensive SR
            "1.2.840.10008.5.1.4.1.1.78.6": .srDocument,                // Spectacle Prescription Report (A.35.9)
            "1.2.840.10008.5.1.4.1.1.88.59": .keyObjectDoc,             // Key Object Selection Document
            "1.2.840.10008.5.1.4.1.1.11.1": .presentation,              // Grayscale Softcopy Presentation State
            "1.2.840.10008.5.1.4.1.1.131": .presentation,               // Basic Structured Display
            "1.2.840.10008.5.1.4.1.1.9.1.1": .waveform,                 // 12-lead ECG
            "1.2.840.10008.5.1.4.1.1.9.100.1": .wfPresentation,         // Waveform Presentation State
            "1.2.840.10008.5.1.4.1.1.104.1": .encapsulatedDocument,     // Encapsulated PDF
            "1.2.840.10008.5.1.4.1.1.481.2": .rtDose,
            "1.2.840.10008.5.1.4.1.1.481.3": .rtStructureSet,
            "1.2.840.10008.5.1.4.1.1.481.8": .rtPlan,                   // RT Ion Plan ("RT Plan ... or RT Ion Plan")
            "1.2.840.10008.5.1.4.1.1.481.9": .rtTreatRecord,            // RT Ion Beams Treatment Record
            "1.2.840.10008.5.1.4.34.7": .plan,                          // RT Beams Delivery Instruction (A.64)
            "1.2.840.10008.5.1.4.1.1.481.12": .radiotherapy,            // RT Radiation Set (A.86.1.4)
            "1.2.840.10008.5.1.4.1.1.4.2": .spectroscopy,
            "1.2.840.10008.5.1.4.1.1.66": .rawData,
            "1.2.840.10008.5.1.4.1.1.66.1": .registration,
            "1.2.840.10008.5.1.4.1.1.66.2": .fiducial,
            "1.2.840.10008.5.1.4.1.1.66.5": .surface,
            "1.2.840.10008.5.1.4.1.1.68.1": .surfaceScan,
            "1.2.840.10008.5.1.4.1.1.78.1": .measurement,               // Lensometry Measurements
            "1.2.840.10008.5.1.4.1.1.67": .valueMap,
            "1.2.840.10008.5.1.4.38.1": .hangingProtocol,
            "1.2.840.10008.5.1.4.39.1": .palette,
            "1.2.840.10008.5.1.4.43.1": .implant,
            "1.2.840.10008.5.1.4.1.1.201.1": .inventory,
        ]
        for (sop, type) in expected {
            XCTAssertEqual(DICOMDIRRecordKeys.recordType(forSOPClassUID: sop), type, sop)
        }
        // 2026a defines no record type for the Procedure Protocol / Protocol Approval IODs
        for sop in ["1.2.840.10008.5.1.4.1.1.200.1", "1.2.840.10008.5.1.4.1.1.200.2", "1.2.840.10008.5.1.4.1.1.200.3"] {
            XCTAssertNil(DICOMDIRRecordKeys.recordType(forSOPClassUID: sop))
            XCTAssertTrue(DICOMDIRRecordKeys.hasNoDirectoryRecordType(sopClassUID: sop))
        }
    }

    func testStudyKeysAreTableF52() throws {
        let study = try XCTUnwrap(DICOMDIRRecordKeys.keys(for: .study))
        XCTAssertEqual(study.table, "F.5-2")
        XCTAssertEqual(study.keys.map(\.name), ["Study Date", "Study Time", "Study Description",
                                                 "Study Instance UID", "Study ID", "Accession Number"])
        XCTAssertEqual(study.keys.map(\.type), ["1", "1", "2", "1", "1", "2"])
        XCTAssertEqual(DICOMDIRRecordKeys.keys(for: .series)?.keys.map(\.name), ["Modality", "Series Instance UID", "Series Number"])
    }

    // MARK: - D229 STUDY / SERIES / IMAGE keys

    func testStudyRecordCarriesStudyIDAndAccessionNumber() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "T", profile: .standardGeneralCD)
        try builder.addFile(file("1.2.840.10008.5.1.4.1.1.2") { ds in
            ds.setString("20240115", for: .studyDate, vr: .DA)
            ds.setString("101500", for: .studyTime, vr: .TM)
            ds.setString("S77", for: .studyID, vr: .SH)
            ds.setString("ACC1", for: .accessionNumber, vr: .SH)
            ds.setString("CT", for: .modality, vr: .CS)
            ds.setString("4", for: .seriesNumber, vr: .IS)
            ds.setString("9", for: .instanceNumber, vr: .IS)
        }, relativePath: fileID(1))
        let directory = builder.build()
        let study = try XCTUnwrap(directory.rootRecords.first?.children.first)
        XCTAssertEqual(study.attribute(for: .studyID)?.stringValue, "S77")
        XCTAssertEqual(study.attribute(for: .accessionNumber)?.stringValue, "ACC1")
        XCTAssertEqual(study.attribute(for: .studyDate)?.stringValue, "20240115")
        XCTAssertNotNil(study.attribute(for: .studyDescription), "Type 2: present, zero length")
        XCTAssertEqual(study.children.first?.attribute(for: .seriesNumber)?.stringValue, "4")
        XCTAssertEqual(try onlyLeaf(directory).attribute(for: .instanceNumber)?.stringValue, "9")
    }

    func testMissingType1IdentifiersAreSuppliedByTheFileSetCreator() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "T", profile: .standardGeneralCD)
        for n in 1...2 {
            try builder.addFile(file("1.2.840.10008.5.1.4.1.1.2") { ds in
                ds.setString("CT", for: .modality, vr: .CS)
                ds.setString("20240301", for: .seriesDate, vr: .DA)
                ds.setString("", for: .studyID, vr: .SH)       // Type 2 in the IOD: empty
            }, relativePath: fileID(n))
        }
        let study = try XCTUnwrap(builder.build().rootRecords.first?.children.first)
        XCTAssertEqual(study.attribute(for: .studyID)?.stringValue, "1")
        XCTAssertEqual(study.attribute(for: .studyDate)?.stringValue, "20240301", "from Series Date")
        XCTAssertEqual(study.attribute(for: .studyTime)?.stringValue, "000000")
        XCTAssertNotNil(study.attribute(for: .accessionNumber), "Type 2: present, zero length")
        let series = try XCTUnwrap(study.children.first)
        XCTAssertEqual(series.attribute(for: .seriesNumber)?.stringValue, "1")
        XCTAssertEqual(series.children.map { $0.attribute(for: .instanceNumber)?.stringValue }, ["1", "2"])
    }

    func testStudyDateCanBeRefusedInsteadOfSupplied() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "T", profile: .standardGeneralCD)
        builder.suppliesMissingStudyDateTime = false
        XCTAssertThrowsError(try builder.addFile(file("1.2.840.10008.5.1.4.1.1.2"), relativePath: fileID(1))) { error in
            XCTAssertEqual(error as? DICOMDIRProfileRules.Refusal,
                           .missingRecordKey(recordType: "STUDY", key: "Study Date", tag: Tag.studyDate.description, table: "F.5-2"))
            XCTAssertTrue("\(error)".contains("PS3.11 2026a D.3.3.1"), "\(error)")
        }
        XCTAssertTrue(builder.build().rootRecords.isEmpty, "a refused instance adds nothing")
    }

    // MARK: - D230 record type and keys per SOP Class

    func testSRDocumentRecordKeys() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "T", profile: .standardGeneralCD)
        try builder.addFile(file("1.2.840.10008.5.1.4.1.1.88.33") { ds in
            ds.setString("SR", for: .modality, vr: .CS)
            ds.setString("20240115", for: .studyDate, vr: .DA)
            ds.setString("101500", for: .studyTime, vr: .TM)
            ds.setString("COMPLETE", for: .completionFlag, vr: .CS)
            ds.setString("VERIFIED", for: .verificationFlag, vr: .CS)
            ds.setString("20240116", for: .contentDate, vr: .DA)
            ds.setString("090000", for: .contentTime, vr: .TM)
            var observer1 = DataSet(); observer1.setString("20240116100000", for: .verificationDateTime, vr: .DT)
            var observer2 = DataSet(); observer2.setString("20240117110000", for: .verificationDateTime, vr: .DT)
            ds.setSequence([SequenceItem(elements: Array(observer1)), SequenceItem(elements: Array(observer2))],
                           for: .verifyingObserverSequence)
            var title = DataSet()
            title.setString("126000", for: .codeValue, vr: .SH)
            title.setString("DCM", for: .codingSchemeDesignator, vr: .SH)
            title.setString("Imaging Measurement Report", for: .codeMeaning, vr: .LO)
            ds.setSequence([SequenceItem(elements: Array(title))], for: .conceptNameCodeSequence)
            var mod = DataSet(); mod.setString("HAS CONCEPT MOD", for: .relationshipType, vr: .CS)
            var contains = DataSet(); contains.setString("CONTAINS", for: .relationshipType, vr: .CS)
            ds.setSequence([SequenceItem(elements: Array(mod)), SequenceItem(elements: Array(contains))], for: .contentSequence)
        }, relativePath: fileID(1))
        let record = try onlyLeaf(builder.build())
        XCTAssertEqual(record.recordType, .srDocument, "was IMAGE")
        XCTAssertEqual(record.attribute(for: .completionFlag)?.stringValue, "COMPLETE")
        XCTAssertEqual(record.attribute(for: .verificationFlag)?.stringValue, "VERIFIED")
        XCTAssertEqual(record.attribute(for: .contentDate)?.stringValue, "20240116")
        XCTAssertEqual(record.attribute(for: .verificationDateTime)?.stringValue, "20240117110000", "most recent")
        XCTAssertEqual(record.attribute(for: .conceptNameCodeSequence)?.sequenceItems?.count, 1)
        XCTAssertEqual(record.attribute(for: .contentSequence)?.sequenceItems?.count, 1, "HAS CONCEPT MOD Items only")
        XCTAssertEqual(record.attribute(for: .instanceNumber)?.stringValue, "1")
    }

    func testRecordWithoutAType1KeyIsRefused() {
        var builder = DICOMDirectory.Builder(fileSetID: "T", profile: .standardGeneralCD)
        XCTAssertThrowsError(try builder.addFile(file("1.2.840.10008.5.1.4.1.1.88.33") { ds in
            ds.setString("20240115", for: .studyDate, vr: .DA)
            ds.setString("SR", for: .modality, vr: .CS)
        }, relativePath: fileID(1))) { error in
            guard case .missingRecordKey(let type, let key, _, let table)? = error as? DICOMDIRProfileRules.Refusal else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(type, "SR DOCUMENT")
            XCTAssertEqual(key, "Completion Flag")
            XCTAssertEqual(table, "F.5-25")
        }
    }

    func testPresentationEncapsulatedDocAndRootLevelRecords() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "T", profile: .standardGeneralCD)
        try builder.addFile(file("1.2.840.10008.5.1.4.1.1.11.1") { ds in
            ds.setString("PR", for: .modality, vr: .CS)
            ds.setString("20240115", for: .presentationCreationDate, vr: .DA)
            ds.setString("101500", for: .presentationCreationTime, vr: .TM)
            ds.setString("GSPS", for: .contentLabel, vr: .CS)
        }, relativePath: fileID(1))
        try builder.addFile(file("1.2.840.10008.5.1.4.1.1.104.1") { ds in
            ds.setString("DOC", for: .modality, vr: .CS)
            ds.setString("application/pdf", for: .mimeTypeOfEncapsulatedDocument, vr: .LO)
        }, relativePath: fileID(2))
        try builder.addFile(file("1.2.840.10008.5.1.4.39.1") { ds in
            ds.setString("HOTIRON", for: .contentLabel, vr: .CS)
        }, relativePath: fileID(3))
        let directory = builder.build()
        let series = try XCTUnwrap(directory.rootRecords.first?.children.first?.children.first)
        XCTAssertEqual(series.children.map(\.recordType), [.presentation, .encapsulatedDocument])
        XCTAssertNotNil(series.children[1].attribute(for: .documentTitle), "Type 2 key of F.5-32")
        XCTAssertEqual(directory.rootRecords.map(\.recordType), [.patient, .palette], "PALETTE is a root record")
        XCTAssertNoThrow(try directory.validate())

        // D232: written and read back, every record survives where Table F.4-1 puts it
        let reread = try DICOMDIRReader.read(from: try DICOMDIRWriter.write(directory))
        XCTAssertEqual(reread.rootRecords.map(\.recordType), [.patient, .palette])
        XCTAssertEqual(reread.rootRecords.first?.children.first?.children.first?.children.map(\.recordType),
                       [.presentation, .encapsulatedDocument])
        XCTAssertEqual(reread.statistics().instanceRecordCount, 3)
    }

    func testSOPClassWithoutARecordTypeIsRefused() {
        var builder = DICOMDirectory.Builder(fileSetID: "T", profile: .standardGeneralCD)
        XCTAssertThrowsError(try builder.addFile(file("1.2.840.10008.5.1.4.1.1.200.2"), relativePath: fileID(1))) { error in
            XCTAssertEqual(error as? DICOMDIRProfileRules.Refusal,
                           .noDirectoryRecordType(sopClassUID: "1.2.840.10008.5.1.4.1.1.200.2"))
        }
    }

    // MARK: - D231

    func testConsistencyFlagIsNeverFFFFH() throws {
        let directory = DICOMDirectory(fileSetID: "T", isConsistent: false)
        let data = try DICOMDIRWriter.write(directory)
        let written = try DICOMFile.read(from: data)
        XCTAssertEqual(written.dataSet.uint16(for: .fileSetConsistencyFlag), 0x0000)
    }

    // MARK: - D232 reader

    func testReaderKeepsEverySeriesLevelAndRootLevelRecordType() throws {
        func item(_ type: String) -> SequenceItem {
            SequenceItem(elements: [
                .uint32(tag: .offsetOfTheNextDirectoryRecord, value: 0),
                .uint16(tag: .recordInUseFlag, value: 0xFFFF),
                .uint32(tag: .offsetOfReferencedLowerLevelDirectoryEntity, value: 0),
                .string(tag: .directoryRecordType, vr: .CS, value: type),
            ])
        }
        let seriesLevel = ["KEY OBJECT DOC", "ENCAP DOC", "RT TREAT RECORD", "SPECTROSCOPY", "RAW DATA",
                           "REGISTRATION", "FIDUCIAL", "VALUE MAP", "STEREOMETRIC", "PLAN", "MEASUREMENT",
                           "SURFACE", "TRACT", "ASSESSMENT", "RADIOTHERAPY", "ANNOTATION", "WF PRESENTATION"]
        var items = [item("PATIENT"), item("STUDY"), item("SERIES")] + seriesLevel.map(item)
        items += ["HANGING PROTOCOL", "PALETTE", "IMPLANT", "IMPLANT ASSY", "IMPLANT GROUP", "INVENTORY"].map(item)
        var ds = DataSet()
        ds.setSequence(items, for: .directoryRecordSequence)
        let directory = try DICOMDIRReader.parse(dataSet: ds)
        XCTAssertEqual(directory.rootRecords.map(\.recordType.rawValue),
                       ["PATIENT", "HANGING PROTOCOL", "PALETTE", "IMPLANT", "IMPLANT ASSY", "IMPLANT GROUP", "INVENTORY"])
        XCTAssertEqual(directory.rootRecords[0].children.first?.children.first?.children.map(\.recordType.rawValue), seriesLevel)
    }

    // MARK: - D233 per-profile image attribute values

    func testEveryProfileValueCellParses() {
        for (label, rows) in DICOMDIRProfileRules.imageAttributeValueTables {
            for row in rows {
                XCTAssertNotNil(DICOMDIRProfileRules.parseValueRule(row.value), "\(label) \(row.name): \(row.value)")
            }
        }
        XCTAssertEqual(DICOMDIRProfileRules.parseValueRule("8, 12 to 16"), .integers([8...8, 12...16]))
        XCTAssertEqual(DICOMDIRProfileRules.parseValueRule("up to 1024 (see below)"), .atMost(1024))
        XCTAssertEqual(DICOMDIRProfileRules.parseValueRule("0000H (unsigned)"), .integers([0...0]))
        XCTAssertEqual(DICOMDIRProfileRules.parseValueRule("Bits Stored (0028,0101) - 1"), .relative(.bitsStored, offset: -1))
    }

    private func image(_ sop: String, ts: String = "1.2.840.10008.1.2.1", rows: Int = 512, columns: Int = 512,
                       pi: String = "MONOCHROME2", allocated: Int = 8, stored: Int = 8, high: Int = 7,
                       modality: String, frames: Int? = nil, _ extra: (inout DataSet) -> Void = { _ in }) -> DICOMFile {
        file(sop, transferSyntax: ts) { ds in
            ds.setString(modality, for: .modality, vr: .CS)
            ds.setString("20240115", for: .studyDate, vr: .DA)
            ds.setString("101500", for: .studyTime, vr: .TM)
            ds.setUInt16(UInt16(rows), for: .rows)
            ds.setUInt16(UInt16(columns), for: .columns)
            ds.setUInt16(1, for: .samplesPerPixel)
            ds.setString(pi, for: .photometricInterpretation, vr: .CS)
            ds.setUInt16(UInt16(allocated), for: .bitsAllocated)
            ds.setUInt16(UInt16(stored), for: .bitsStored)
            ds.setUInt16(UInt16(high), for: .highBit)
            ds.setUInt16(0, for: .pixelRepresentation)
            if let frames { ds.setString(String(frames), for: .numberOfFrames, vr: .IS) }
            ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: Data(count: 2))
            extra(&ds)
        }
    }

    func testXA1KLimitsRowsAndBitsStored() throws {
        let xa = "1.2.840.10008.5.1.4.1.1.12.1"
        let jpegLossless = "1.2.840.10008.1.2.4.70"   // the only syntax of Table B.3-1
        var builder = DICOMDirectory.Builder(fileSetID: "T", profile: .standardXA1024CD)
        // B.3-2 / B.3.3.2 (D239): the IMAGE record needs a 128 x 128 8-bit MONOCHROME2 Icon Image
        // Sequence; this JPEG stand-in cannot be decoded, so the instance carries one
        func icon(_ ds: inout DataSet) {
            var icon = DataSet()
            for (tag, value) in [(Tag.samplesPerPixel, 1), (.rows, 128), (.columns, 128), (.bitsAllocated, 8),
                                 (.bitsStored, 8), (.highBit, 7), (.pixelRepresentation, 0)] {
                icon.setUInt16(UInt16(value), for: tag)
            }
            icon.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
            icon[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: Data(count: 128 * 128))
            ds.setSequence([SequenceItem(elements: icon.allElements)], for: .iconImageSequence)
            ds.setStrings(["ORIGINAL", "PRIMARY", "SINGLE PLANE"], for: .imageType, vr: .CS)
        }
        XCTAssertNoThrow(try builder.addFile(image(xa, ts: jpegLossless, rows: 1024, columns: 1024, stored: 10, high: 9, modality: "XA", icon), relativePath: fileID(1)))
        XCTAssertThrowsError(try builder.addFile(image(xa, ts: jpegLossless, rows: 1100, columns: 1024, stored: 14, high: 13, modality: "XA"),
                                                 relativePath: fileID(2))) { error in
            let text = "\(error)"
            XCTAssertTrue(text.contains("Rows (0028,0010) [Table B.3-3] is 1100, shall not exceed 1024"), text)
            XCTAssertTrue(text.contains("Bits Stored (0028,0101) [Table B.3-3] is 14, shall be 8, 10, and 12 bits only"), text)
        }
        // B.3-4: an SC image in this profile is 8-bit MONOCHROME2
        XCTAssertThrowsError(try builder.addFile(image("1.2.840.10008.5.1.4.1.1.7", allocated: 16, stored: 12, high: 11, modality: "OT"),
                                                 relativePath: fileID(3))) { error in
            XCTAssertTrue("\(error)".contains("[Table B.3-4]"), "\(error)")
        }
    }

    func testCTMRHighBitAndColorSC() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "T", profile: .standardCTMRCD)
        XCTAssertNoThrow(try builder.addFile(image("1.2.840.10008.5.1.4.1.1.4", allocated: 16, stored: 12, high: 11, modality: "MR"),
                                             relativePath: fileID(1)))
        XCTAssertThrowsError(try builder.addFile(image("1.2.840.10008.5.1.4.1.1.4", allocated: 16, stored: 12, high: 15, modality: "MR"),
                                                 relativePath: fileID(2))) { error in
            XCTAssertTrue("\(error)".contains("High Bit (0028,0102) [Table E.3-4] is 15, shall be Bits Stored (0028,0101) - 1 = 11"), "\(error)")
        }
        // E.3-6: a colour SC image shall be PALETTE COLOR
        XCTAssertThrowsError(try builder.addFile(image("1.2.840.10008.5.1.4.1.1.7", pi: "RGB", modality: "OT"), relativePath: fileID(3)))
    }

    func testDentalBitsAllocatedFollowsBitsStoredAndTypesAreSpecialized() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "T", profile: .standardDentalCD)
        let dx = "1.2.840.10008.5.1.4.1.1.1.3"
        func equipment(_ ds: inout DataSet) {
            for tag in [Tag.institutionName, .manufacturerModelName, Tag(group: 0x0018, element: 0x700A),
                        Tag(group: 0x0018, element: 0x702A), Tag(group: 0x0018, element: 0x702B)] {
                ds[tag] = DICOMDIRRecordKeys.emptyElement(tag)
            }
        }
        XCTAssertNoThrow(try builder.addFile(image(dx, allocated: 16, stored: 12, high: 11, modality: "IO", equipment), relativePath: fileID(1)))
        XCTAssertThrowsError(try builder.addFile(image(dx, allocated: 16, stored: 8, high: 7, modality: "IO", equipment), relativePath: fileID(2))) { error in
            XCTAssertTrue("\(error)".contains("Bits Allocated (0028,0100) [Table K.3-3] is 16, shall be 8"), "\(error)")
        }
        XCTAssertThrowsError(try builder.addFile(image(dx, allocated: 16, stored: 12, high: 11, modality: "IO"), relativePath: fileID(3))) { error in
            XCTAssertTrue("\(error)".contains("Detector ID (0018,700A) is absent; the profile makes it Type 2 [Table K.3-4]"), "\(error)")
        }
    }

    func testUltrasoundPhotometricTransferSyntaxPairs() throws {
        let us = "1.2.840.10008.5.1.4.1.1.6.1"
        var builder = DICOMDirectory.Builder(fileSetID: "T", profile: .ultrasound(.imageDisplay, frames: false, media: .cdr))
        XCTAssertNoThrow(try builder.addFile(image(us, ts: "1.2.840.10008.1.2.5", pi: "YBR_FULL", modality: "US"), relativePath: fileID(1)))
        XCTAssertThrowsError(try builder.addFile(image(us, ts: "1.2.840.10008.1.2.1", pi: "YBR_FULL", modality: "US"), relativePath: fileID(2))) { error in
            XCTAssertTrue("\(error)".contains("Table C.3-2"), "\(error)")
        }
    }

    func testMPEGRowsAdmitMultiFrameInstancesOnly() {
        let profile = DICOMDIRProfile.standardGeneralBDMPEG2MPHL
        let vl = "1.2.840.10008.5.1.4.1.1.77.1.1.1"   // Video Endoscopic Image
        XCTAssertNil(DICOMDIRProfileRules.refusal(sopClassUID: vl, transferSyntaxUID: "1.2.840.10008.1.2.4.101",
                                                  profile: profile, isMultiFrame: true))
        XCTAssertNotNil(DICOMDIRProfileRules.refusal(sopClassUID: vl, transferSyntaxUID: "1.2.840.10008.1.2.4.101",
                                                     profile: profile, isMultiFrame: false))
    }
}
