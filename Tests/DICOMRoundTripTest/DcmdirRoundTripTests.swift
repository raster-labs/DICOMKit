// DcmdirRoundTripTests.swift
// Oracle-based round-trip tests for the `dicom-dcmdir` tool.
//
// Tests call the DICOMKit library directly (DICOMDIRWorkflow / DICOMDIRWriter /
// DICOMDIRReader / DICOMDIRDumpFormatter / DICOMDirectory.Builder). They never
// spawn the CLI. Every assertion is a mathematical/semantic oracle (counts,
// hierarchy invariants, serialize→parse identity), never a comparison against a
// re-implementation of the tool.
//
// Shared helpers (makeGrayscale8, writeTempDICOM, makeTempDir, rtUID, …) live in
// RoundTripFixture.swift and are used, not redefined.

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore

final class DcmdirRoundTripTests: XCTestCase {

    // MARK: - Private helpers (class-scoped, never global)

    /// Builds a minimal conformant single-frame DICOM file with fully controllable
    /// hierarchy UIDs. `DICOMFile.create` copies the sopInstanceUID into the file
    /// meta information, which is where the DICOMDIR Builder reads the instance UID,
    /// so distinct sopInstanceUID values yield distinct IMAGE records.
    private func makeInstance(
        patientID: String, studyUID: String, seriesUID: String, sopInstanceUID: String
    ) -> DICOMFile {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString(sopInstanceUID, for: .sopInstanceUID, vr: .UI)
        ds.setString(studyUID, for: .studyInstanceUID, vr: .UI)
        ds.setString(seriesUID, for: .seriesInstanceUID, vr: .UI)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setString("RoundTrip^Patient", for: .patientName, vr: .PN)
        ds.setString(patientID, for: .patientID, vr: .LO)
        ds.setUInt16(4, for: .rows)
        ds.setUInt16(4, for: .columns)
        ds.setUInt16(8, for: .bitsAllocated)
        ds.setUInt16(8, for: .bitsStored)
        ds.setUInt16(7, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: Data(count: 16))
        return DICOMFile.create(
            dataSet: ds,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: sopInstanceUID)
    }

    /// Writes `count` synthetic DICOM files, each with its own distinct patient /
    /// study / series / SOP Instance UID, under names that are PS3.10 8.2/8.5 File IDs
    /// (`IMG0`, …): the Builder refuses any other File ID (D131). Returns (dir, [fileNames]).
    private func makeCorpusDir(count: Int) throws -> (URL, [String]) {
        let dir = try makeTempDir()
        var names: [String] = []
        for i in 0..<count {
            let file = makeInstance(
                patientID: "RT\(i)", studyUID: rtUID(),
                seriesUID: rtUID(), sopInstanceUID: rtUID())
            let name = "IMG\(i)"
            try file.write().write(to: dir.appendingPathComponent(name))
            names.append(name)
        }
        return (dir, names)
    }

    /// Builds a directory manually with `patients` PATIENT records, each holding
    /// one STUDY → one SERIES → one IMAGE. Deterministic (no Dictionary ordering).
    private func makeManualDirectory(patients: Int) -> DICOMDirectory {
        var roots: [DirectoryRecord] = []
        for p in 0..<patients {
            let image = DirectoryRecord.image(
                referencedFileID: ["PT\(p)", "ST0", "SE0", "IMG0.dcm"],
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: rtUID(),
                transferSyntaxUID: "1.2.840.10008.1.2.1",
                instanceNumber: "\(p + 1)"
            )
            let series = DirectoryRecord.series(
                seriesInstanceUID: rtUID(), modality: "CT", children: [image])
            let study = DirectoryRecord.study(
                studyInstanceUID: rtUID(), children: [series])
            let patient = DirectoryRecord.patient(
                patientID: "PID\(p)", patientName: "Patient^\(p)", children: [study])
            roots.append(patient)
        }
        return DICOMDirectory(fileSetID: "MANUAL", profile: .standardGeneralCD, rootRecords: roots)
    }

    // MARK: - create → statistics oracle

    // Oracle: create over N files with distinct patients → N patients/studies/series/images.
    func testCreateStatisticsCountImages() throws {
        let (dir, names) = try makeCorpusDir(count: 3)
        let result = try DICOMDIRWorkflow.buildDirectory(
            fromFilesIn: dir, recursive: true, strict: false,
            fileSetID: "TEST", profile: .standardGeneralCD)
        let stats = result.directory.statistics()
        XCTAssertEqual(result.processed, names.count)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(stats.patientCount, names.count)
        XCTAssertEqual(stats.studyCount, names.count)
        XCTAssertEqual(stats.seriesCount, names.count)
        XCTAssertEqual(stats.imageCount, names.count)
    }

    // Oracle: create then dump — every input file name appears in the tree dump.
    func testCreateThenDumpListsAllFiles() throws {
        let (dir, names) = try makeCorpusDir(count: 3)
        let result = try DICOMDIRWorkflow.buildDirectory(
            fromFilesIn: dir, recursive: true, strict: false,
            fileSetID: "TEST", profile: .standardGeneralCD)
        let tree = DICOMDIRDumpFormatter.render(result.directory, format: .tree, verbose: false)
        for name in names {
            XCTAssertTrue(tree.contains(name), "dump tree should list \(name)")
        }
    }

    // Oracle: a freshly created directory passes validation (no throw).
    func testCreateThenValidatePasses() throws {
        let (dir, _) = try makeCorpusDir(count: 3)
        let result = try DICOMDIRWorkflow.buildDirectory(
            fromFilesIn: dir, recursive: true, strict: false,
            fileSetID: "TEST", profile: .standardGeneralCD)
        XCTAssertNoThrow(try result.directory.validate(checkFileExistence: false))
    }

    // Oracle: an empty directory yields WorkflowError.noDICOMFiles.
    func testCreateEmptyDirectoryThrowsNoDICOMFiles() throws {
        let dir = try makeTempDir()
        XCTAssertThrowsError(
            try DICOMDIRWorkflow.buildDirectory(
                fromFilesIn: dir, recursive: true, strict: false,
                fileSetID: "TEST", profile: .standardGeneralCD)
        ) { error in
            guard case DICOMDIRWorkflow.WorkflowError.noDICOMFiles = error else {
                return XCTFail("expected noDICOMFiles, got \(error)")
            }
        }
    }

    // MARK: - write → read round trip (serialize/parse identity)

    // Oracle: build → write → read preserves every statistics count.
    func testWriteReadStatisticsRoundTrip() throws {
        let original = makeManualDirectory(patients: 2)
        let data = try DICOMDIRWriter.write(original)
        let readBack = try DICOMDIRReader.read(from: data)

        let o = original.statistics()
        let r = readBack.statistics()
        XCTAssertEqual(o.patientCount, r.patientCount)
        XCTAssertEqual(o.studyCount, r.studyCount)
        XCTAssertEqual(o.seriesCount, r.seriesCount)
        XCTAssertEqual(o.imageCount, r.imageCount)
        // Manual layout: 2 patients × (1 study + 1 series + 1 image) + 2 patients = 8 records.
        XCTAssertEqual(o.patientCount, 2)
        XCTAssertEqual(o.studyCount, 2)
        XCTAssertEqual(o.seriesCount, 2)
        XCTAssertEqual(o.imageCount, 2)
    }

    // Oracle: a study with MULTIPLE series (and multiple images per series) round-trips
    // with EVERY image preserved. Regression: the reader's hierarchy reconstruction
    // mutated value-type copies of the current study/patient without writing them back,
    // so every series but the last was dropped and only the final image survived.
    func testWriteReadMultiSeriesRoundTrip() throws {
        func image(_ n: Int) -> DirectoryRecord {
            DirectoryRecord.image(
                referencedFileID: ["DICOM", "IMG\(n)"],
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: rtUID(),
                transferSyntaxUID: "1.2.840.10008.1.2.1",
                instanceNumber: "\(n)")
        }
        let seriesA = DirectoryRecord.series(
            seriesInstanceUID: rtUID(), modality: "CT", children: [image(1), image(2)])
        let seriesB = DirectoryRecord.series(
            seriesInstanceUID: rtUID(), modality: "CT", children: [image(3)])
        let study = DirectoryRecord.study(studyInstanceUID: rtUID(), children: [seriesA, seriesB])
        let patient = DirectoryRecord.patient(
            patientID: "PID", patientName: "Multi^Series", children: [study])
        let original = DICOMDirectory(fileSetID: "MULTI", rootRecords: [patient])

        let readBack = try DICOMDIRReader.read(from: try DICOMDIRWriter.write(original))
        let s = readBack.statistics()
        XCTAssertEqual(s.patientCount, 1)
        XCTAssertEqual(s.studyCount, 1)
        XCTAssertEqual(s.seriesCount, 2, "both series must survive")
        XCTAssertEqual(s.imageCount, 3, "every image across both series must survive the round-trip")
        XCTAssertEqual(readBack.allReferencedFiles().count, 3)
    }

    // Oracle: the writer computes real navigation offsets (PS3.3 F.3.2.2) — root First
    // points to the first record item, and a multi-series study's sibling/child links
    // point to the correct item byte positions — so an offset-following reader (dcmtk /
    // pydicom) can navigate the file-set, not just DICOMKit's own type-order reader.
    func testWriteComputesNavigationOffsets() throws {
        func image(_ n: Int) -> DirectoryRecord {
            DirectoryRecord.image(referencedFileID: ["IMG\(n)"], sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                                  sopInstanceUID: rtUID(), transferSyntaxUID: "1.2.840.10008.1.2.1")
        }
        let seriesA = DirectoryRecord.series(seriesInstanceUID: rtUID(), modality: "CT", children: [image(1), image(2)])
        let seriesB = DirectoryRecord.series(seriesInstanceUID: rtUID(), modality: "CT", children: [image(3)])
        let study = DirectoryRecord.study(studyInstanceUID: rtUID(), children: [seriesA, seriesB])
        let patient = DirectoryRecord.patient(patientID: "P", patientName: "N", children: [study])
        let data = try DICOMDIRWriter.write(DICOMDirectory(fileSetID: "OFF", rootRecords: [patient]))

        let bytes = [UInt8](data)
        func u32(_ at: Int) -> Int {
            Int(UInt32(bytes[at]) | (UInt32(bytes[at + 1]) << 8) | (UInt32(bytes[at + 2]) << 16) | (UInt32(bytes[at + 3]) << 24))
        }
        // Locate the (0004,1220) Directory Record Sequence and walk its items.
        var header = -1
        var i = 0
        while i + 6 <= bytes.count {
            if bytes[i] == 0x04, bytes[i + 1] == 0x00, bytes[i + 2] == 0x20, bytes[i + 3] == 0x12,
               bytes[i + 4] == 0x53, bytes[i + 5] == 0x51 { header = i; break }
            i += 1
        }
        XCTAssertGreaterThanOrEqual(header, 0, "Directory Record Sequence must be present")
        let valueStart = header + 12
        let seqEnd = valueStart + u32(header + 8)
        var itemOffsets: [Int] = []
        var itemBodies: [(start: Int, length: Int)] = []
        var cursor = valueStart
        while cursor + 8 <= seqEnd, bytes[cursor] == 0xFE, bytes[cursor + 1] == 0xFF, bytes[cursor + 2] == 0x00, bytes[cursor + 3] == 0xE0 {
            let length = u32(cursor + 4)
            itemOffsets.append(cursor)
            itemBodies.append((cursor + 8, length))
            cursor += 8 + length
        }
        XCTAssertEqual(itemOffsets.count, 7, "patient+study+2 series+3 images = 7 records")

        // Read a UL element value within an item body, or nil.
        func ul(_ item: Int, tag: [UInt8]) -> Int? {
            let (start, length) = itemBodies[item]
            var p = start
            let end = start + length
            while p + 4 <= end {
                if bytes[p] == tag[0], bytes[p + 1] == tag[1], bytes[p + 2] == tag[2], bytes[p + 3] == tag[3] {
                    return u32(p + 8)   // explicit-VR UL: tag(4)+VR(2)+len(2)+value(4)
                }
                p += 1
            }
            return nil
        }
        let nextTag: [UInt8] = [0x04, 0x00, 0x00, 0x14]   // (0004,1400)
        let lowerTag: [UInt8] = [0x04, 0x00, 0x20, 0x14]  // (0004,1420)

        // Root first/last (0004,1200)/(0004,1202) live in the main data set, before the sequence.
        func rootUL(_ tag: [UInt8]) -> Int? {
            var p = 0
            while p + 4 <= header {
                if bytes[p] == tag[0], bytes[p + 1] == tag[1], bytes[p + 2] == tag[2], bytes[p + 3] == tag[3] {
                    return u32(p + 8)
                }
                p += 1
            }
            return nil
        }
        XCTAssertEqual(rootUL([0x04, 0x00, 0x00, 0x12]), itemOffsets[0], "root First → first record item")
        XCTAssertEqual(rootUL([0x04, 0x00, 0x02, 0x12]), itemOffsets[0], "root Last → last root record (single patient)")

        // Flattened order: patient(0) study(1) seriesA(2) img1(3) img2(4) seriesB(5) img3(6).
        XCTAssertEqual(ul(0, tag: lowerTag), itemOffsets[1], "patient.lower → study")
        XCTAssertEqual(ul(1, tag: lowerTag), itemOffsets[2], "study.lower → seriesA")
        XCTAssertEqual(ul(2, tag: lowerTag), itemOffsets[3], "seriesA.lower → img1")
        XCTAssertEqual(ul(2, tag: nextTag), itemOffsets[5], "seriesA.next → seriesB")
        XCTAssertEqual(ul(3, tag: nextTag), itemOffsets[4], "img1.next → img2")
        XCTAssertEqual(ul(4, tag: nextTag), 0, "img2 is last image → next 0")
        XCTAssertEqual(ul(5, tag: lowerTag), itemOffsets[6], "seriesB.lower → img3")
    }

    // Oracle: the serialized DICOMDIR is a valid Part 10 file — preamble(128) + "DICM".
    func testSerializedDICOMDIRIsPart10() throws {
        let directory = makeManualDirectory(patients: 1)
        let data = try DICOMDIRWriter.write(directory)
        XCTAssertGreaterThan(data.count, 132)
        let magic = data.subdata(in: (data.startIndex + 128)..<(data.startIndex + 132))
        XCTAssertEqual(magic, Data("DICM".utf8))
        // First 128 bytes are the zero preamble.
        let preamble = data.subdata(in: data.startIndex..<(data.startIndex + 128))
        XCTAssertEqual(preamble, Data(count: 128))
    }

    // Oracle: serialized DICOMDIR declares the Media Storage Directory SOP Class UID.
    func testSerializedDICOMDIRSOPClassUID() throws {
        let directory = makeManualDirectory(patients: 1)
        let data = try DICOMDIRWriter.write(directory)
        let file = try DICOMFile.read(from: data)
        XCTAssertEqual(
            file.fileMetaInformation.string(for: .mediaStorageSOPClassUID),
            "1.2.840.10008.1.3.10")
    }

    // Oracle: write → read preserves the file-set ID (tag 0004,1130).
    func testWriteReadPreservesFileSetID() throws {
        let directory = DICOMDirectory(
            fileSetID: "MYSET",
            rootRecords: makeManualDirectory(patients: 1).rootRecords)
        let readBack = try DICOMDIRReader.read(from: try DICOMDIRWriter.write(directory))
        XCTAssertEqual(readBack.fileSetID, "MYSET")
    }

    // MARK: - hierarchy / record invariants

    // Oracle: rootRecords are PATIENT, children are STUDY, then SERIES, then IMAGE.
    func testHierarchyInvariant() throws {
        let directory = makeManualDirectory(patients: 1)
        let patient = try XCTUnwrap(directory.rootRecords.first)
        XCTAssertEqual(patient.recordType, .patient)
        let study = try XCTUnwrap(patient.children.first)
        XCTAssertEqual(study.recordType, .study)
        let series = try XCTUnwrap(study.children.first)
        XCTAssertEqual(series.recordType, .series)
        let image = try XCTUnwrap(series.children.first)
        XCTAssertEqual(image.recordType, .image)
    }

    // Oracle: totalRecordCount == sum of level counts; active+inactive == total.
    func testStatisticsCountsAreConsistent() throws {
        let directory = makeManualDirectory(patients: 3)
        let s = directory.statistics()
        XCTAssertEqual(
            s.totalRecordCount,
            s.patientCount + s.studyCount + s.seriesCount + s.imageCount)
        XCTAssertEqual(s.activeRecordCount + s.inactiveRecordCount, s.totalRecordCount)
    }

    // Oracle: referencedFilePath() joins the referencedFileID components with '/'.
    func testReferencedFilePathJoinsComponents() throws {
        let image = DirectoryRecord.image(
            referencedFileID: ["A", "B", "C.dcm"],
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: rtUID(),
            transferSyntaxUID: "1.2.840.10008.1.2.1")
        XCTAssertEqual(image.referencedFilePath(), "A/B/C.dcm")
    }

    // Oracle: DirectoryRecord.patient factory populates PatientID/PatientName attributes.
    func testPatientFactoryAttributes() throws {
        let patient = DirectoryRecord.patient(patientID: "PID9", patientName: "Doe^John")
        XCTAssertEqual(patient.recordType, .patient)
        XCTAssertEqual(patient.attribute(for: .patientID)?.stringValue, "PID9")
        XCTAssertEqual(patient.attribute(for: .patientName)?.stringValue, "Doe^John")
    }

    // Oracle: allRecords() flattens the tree — count equals total record count.
    func testAllRecordsFlattensTree() throws {
        let directory = makeManualDirectory(patients: 2)
        XCTAssertEqual(directory.allRecords().count, directory.statistics().totalRecordCount)
    }

    // MARK: - validate: duplicate detection

    // Oracle: duplicate referenced SOP Instance UID fails validation.
    func testValidateRejectsDuplicateSOPInstanceUID() throws {
        let dupUID = rtUID()
        func image() -> DirectoryRecord {
            DirectoryRecord.image(
                referencedFileID: ["x.dcm"],
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: dupUID,
                transferSyntaxUID: "1.2.840.10008.1.2.1")
        }
        let series = DirectoryRecord.series(
            seriesInstanceUID: rtUID(), modality: "CT", children: [image(), image()])
        let study = DirectoryRecord.study(studyInstanceUID: rtUID(), children: [series])
        let patient = DirectoryRecord.patient(
            patientID: "P", patientName: "N", children: [study])
        let directory = DICOMDirectory(rootRecords: [patient])
        XCTAssertThrowsError(try directory.validate(checkFileExistence: false))
    }

    // MARK: - dump formatter

    // Oracle: dump render is deterministic (identical output across two calls).
    func testDumpIsDeterministic() throws {
        let directory = makeManualDirectory(patients: 2)
        let a = DICOMDIRDumpFormatter.render(directory, format: .tree, verbose: true)
        let b = DICOMDIRDumpFormatter.render(directory, format: .tree, verbose: true)
        XCTAssertEqual(a, b)
    }

    // Oracle: JSON dump parses as JSON and echoes the statistics counts.
    func testDumpJSONParsesWithStatistics() throws {
        let directory = makeManualDirectory(patients: 2)
        let json = DICOMDIRDumpFormatter.render(directory, format: .json, verbose: false)
        let obj = try JSONSerialization.jsonObject(
            with: Data(json.utf8)) as? [String: Any]
        let root = try XCTUnwrap(obj)
        let statistics = try XCTUnwrap(root["statistics"] as? [String: Any])
        XCTAssertEqual(statistics["patients"] as? Int, 2)
        XCTAssertEqual(statistics["images"] as? Int, 2)
        XCTAssertEqual(root["recordCount"] as? Int, directory.statistics().totalRecordCount)
    }

    // Oracle: render(format:String) returns nil for an unrecognized format.
    func testDumpUnknownFormatReturnsNil() throws {
        let directory = makeManualDirectory(patients: 1)
        XCTAssertNil(DICOMDIRDumpFormatter.render(directory, format: "bogus", verbose: false))
        XCTAssertNotNil(DICOMDIRDumpFormatter.render(directory, format: "tree", verbose: false))
    }

    // Oracle: all three dump formats produce non-empty output for a populated directory.
    func testDumpAllFormatsNonEmpty() throws {
        let directory = makeManualDirectory(patients: 1)
        for format in DICOMDIRDumpFormatter.Format.allCases {
            let out = DICOMDIRDumpFormatter.render(directory, format: format, verbose: false)
            XCTAssertFalse(out.isEmpty, "\(format.rawValue) output should not be empty")
        }
    }

    // MARK: - Builder API

    // Oracle: Builder groups distinct patients into distinct PATIENT/IMAGE records.
    func testBuilderGroupsByPatient() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "B", profile: .standardGeneralCD)
        try builder.addFile(
            makeInstance(patientID: "PA", studyUID: rtUID(), seriesUID: rtUID(), sopInstanceUID: rtUID()),
            relativePath: ["A"])
        try builder.addFile(
            makeInstance(patientID: "PB", studyUID: rtUID(), seriesUID: rtUID(), sopInstanceUID: rtUID()),
            relativePath: ["B"])
        let stats = builder.build().statistics()
        XCTAssertEqual(stats.patientCount, 2)
        XCTAssertEqual(stats.imageCount, 2)
    }

    // MARK: - corpus-backed realism

    // Oracle: a real corpus CT file round-trips through create → validate with no error.
    func testCorpusCreateValidateRoundTrip() throws {
        let f = try loadCorpus(.ct)
        try XCTSkipIf(f == nil, "corpus absent")
        let file = try XCTUnwrap(f)
        let dir = try makeTempDir()
        try file.write().write(to: dir.appendingPathComponent("CT"))
        // STD-GEN-CD admits Explicit VR Little Endian only (PS3.11 2026a Table D.3-1); pick a
        // profile whose table lists the corpus file's SOP Class and Transfer Syntax.
        let sopClass = try XCTUnwrap(file.fileMetaInformation.string(for: .mediaStorageSOPClassUID))
        let syntax = file.fileMetaInformation.string(for: .transferSyntaxUID) ?? "1.2.840.10008.1.2.1"
        let profile = [DICOMDIRProfile.standardGeneralCD, .standardGeneralDVDJPEG, .standardGeneralDVDJPEG2000,
                       .standardGeneralMIME].first {
            DICOMDIRProfileRules.refusal(sopClassUID: sopClass, transferSyntaxUID: syntax, profile: $0) == nil
        } ?? .standardGeneralMIME
        let result = try DICOMDIRWorkflow.buildDirectory(
            fromFilesIn: dir, recursive: true, strict: false,
            fileSetID: "CORPUS", profile: profile)
        XCTAssertEqual(result.processed, 1, "\(result.failures)")
        XCTAssertEqual(result.directory.statistics().imageCount, 1)
        let readBack = try DICOMDIRReader.read(from: try DICOMDIRWriter.write(result.directory))
        XCTAssertNoThrow(try readBack.validate(checkFileExistence: false))
        XCTAssertEqual(readBack.statistics().imageCount, 1)
    }

    // MARK: - profile / recursion options

    // Oracle: the requested application profile is honored — building with STD-GEN-DVD-JPEG
    // (PS3.11 2026a Table H.1-1) and STD-GEN-USB-JPEG (Table J.1-1) yields a directory carrying
    // that profile, not the default CD. (The deprecated STD-GEN-DVD / STD-GEN-USB constants are
    // not PS3.11 identifiers; P-DCMDIR-PROFILE.)
    func testBuildHonorsDVDAndUSBProfiles() throws {
        let (dir, _) = try makeCorpusDir(count: 2)
        for profile in [DICOMDIRProfile.standardGeneralDVDJPEG, .standardGeneralUSBJPEG] {
            let result = try DICOMDIRWorkflow.buildDirectory(
                fromFilesIn: dir, recursive: true, strict: false,
                fileSetID: "TEST", profile: profile)
            XCTAssertEqual(result.directory.profile, profile,
                           "built directory must carry the requested profile \(profile.rawValue)")
        }
    }

    // Oracle: --no-recursive (recursive:false) excludes files nested in subdirectories,
    // while recursive:true includes them.
    func testNoRecursiveExcludesSubdirectoryFiles() throws {
        let dir = try makeTempDir()
        try makeInstance(patientID: "TOP", studyUID: rtUID(), seriesUID: rtUID(), sopInstanceUID: rtUID())
            .write().write(to: dir.appendingPathComponent("TOP"))
        let sub = dir.appendingPathComponent("SUB")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try makeInstance(patientID: "NESTED", studyUID: rtUID(), seriesUID: rtUID(), sopInstanceUID: rtUID())
            .write().write(to: sub.appendingPathComponent("NESTED"))

        let nonRecursive = try DICOMDIRWorkflow.buildDirectory(
            fromFilesIn: dir, recursive: false, strict: false, fileSetID: "T", profile: .standardGeneralCD)
        XCTAssertEqual(nonRecursive.processed, 1, "non-recursive must only see the top-level file")

        let recursive = try DICOMDIRWorkflow.buildDirectory(
            fromFilesIn: dir, recursive: true, strict: false, fileSetID: "T", profile: .standardGeneralCD)
        XCTAssertEqual(recursive.processed, 2, "recursive must also include the nested file")
    }

    // MARK: - Oracle: update re-indexes existing entries and adds new files

    // `update` was a stub on both surfaces; it now parses the existing DICOMDIR,
    // unions its referenced files with --add, and rebuilds deterministically.
    // Oracle: after update, the re-read DICOMDIR references old + new files, the
    // file-set ID is preserved, and counts are exact.
    func testUpdateAddsNewFileToExistingDICOMDIR() throws {
        let (dir, _) = try makeCorpusDir(count: 2)
        let build = try DICOMDIRWorkflow.buildDirectory(
            fromFilesIn: dir, recursive: true, strict: false,
            fileSetID: "UPDATE_RT", profile: .standardGeneralCD)
        let dicomdirURL = dir.appendingPathComponent("DICOMDIR")
        try DICOMDIRWriter.write(build.directory, to: dicomdirURL)

        // Drop a NEW instance into the media folder after the initial build.
        let newFile = makeInstance(
            patientID: "PAT_NEW", studyUID: rtUID(), seriesUID: rtUID(), sopInstanceUID: rtUID())
        let newURL = dir.appendingPathComponent("ADDED")
        try newFile.write().write(to: newURL)

        let result = try DICOMDIRWorkflow.updateDirectory(
            dicomdirURL: dicomdirURL, addPath: newURL.path)
        try DICOMDIRWriter.write(result.directory, to: dicomdirURL)

        XCTAssertEqual(result.reindexed, 2, "both original files re-indexed")
        XCTAssertEqual(result.added, 1, "the new file added")
        XCTAssertEqual(result.missing, 0)
        XCTAssertEqual(result.failed, 0)

        let reread = try DICOMDIRReader.read(from: dicomdirURL)
        XCTAssertEqual(reread.fileSetID, "UPDATE_RT", "file-set ID preserved across update")
        let referenced = reread.allReferencedFiles()
        XCTAssertEqual(referenced.count, 3, "old + new files all referenced")
        XCTAssertTrue(referenced.contains("ADDED"), "new file's relative File ID present")
    }

    // MARK: - Oracle: update drops entries whose files vanished from disk

    func testUpdateDropsMissingFilesFromIndex() throws {
        let (dir, names) = try makeCorpusDir(count: 3)
        let build = try DICOMDIRWorkflow.buildDirectory(
            fromFilesIn: dir, recursive: true, strict: false,
            fileSetID: "PRUNE_RT", profile: .standardGeneralCD)
        let dicomdirURL = dir.appendingPathComponent("DICOMDIR")
        try DICOMDIRWriter.write(build.directory, to: dicomdirURL)

        // Remove one referenced file from disk, then update with no --add.
        try FileManager.default.removeItem(at: dir.appendingPathComponent(names[0]))
        let result = try DICOMDIRWorkflow.updateDirectory(dicomdirURL: dicomdirURL, addPath: nil)

        XCTAssertEqual(result.missing, 1, "vanished file counted as missing")
        XCTAssertEqual(result.reindexed, 2, "surviving files re-indexed")
        XCTAssertEqual(result.added, 0)
        XCTAssertFalse(result.directory.allReferencedFiles().contains(names[0]),
                       "vanished file dropped from the rebuilt index")
    }
}

