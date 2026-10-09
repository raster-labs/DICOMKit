// DICOMDIRParserTests.swift
// DICOMStudioTests
//
// Tests for DICOMDIRParser

import Testing
@testable import DICOMStudio
import Foundation

@Suite("DICOMDIRParser Tests")
struct DICOMDIRParserTests {

    // MARK: - isDICOMDIR Tests

    @Test("Recognizes DICOMDIR file name")
    func testIsDICOMDIRFileName() {
        #expect(DICOMDIRParser.isDICOMDIR(fileName: "DICOMDIR") == true)
    }

    @Test("Recognizes case-insensitive DICOMDIR file name")
    func testIsDICOMDIRCaseInsensitive() {
        #expect(DICOMDIRParser.isDICOMDIR(fileName: "dicomdir") == true)
        #expect(DICOMDIRParser.isDICOMDIR(fileName: "Dicomdir") == true)
        #expect(DICOMDIRParser.isDICOMDIR(fileName: "DicomDir") == true)
    }

    @Test("Rejects non-DICOMDIR file names")
    func testNotDICOMDIR() {
        #expect(DICOMDIRParser.isDICOMDIR(fileName: "image.dcm") == false)
        #expect(DICOMDIRParser.isDICOMDIR(fileName: "DICOMDIR.bak") == false)
        #expect(DICOMDIRParser.isDICOMDIR(fileName: "") == false)
    }

    @Test("Recognizes DICOMDIR URL")
    func testIsDICOMDIRURL() {
        let url = URL(fileURLWithPath: "/media/cdrom/DICOMDIR")
        #expect(DICOMDIRParser.isDICOMDIR(url: url) == true)
    }

    @Test("Rejects non-DICOMDIR URL")
    func testNotDICOMDIRURL() {
        let url = URL(fileURLWithPath: "/tmp/image.dcm")
        #expect(DICOMDIRParser.isDICOMDIR(url: url) == false)
    }

    // MARK: - parseFileID Tests

    @Test("Parses backslash-separated file ID")
    func testParseFileID() {
        let components = DICOMDIRParser.parseFileID("IMAGES\\CT001\\IM00001")
        #expect(components == ["IMAGES", "CT001", "IM00001"])
    }

    @Test("Parses single component file ID")
    func testParseFileIDSingle() {
        let components = DICOMDIRParser.parseFileID("DICOMFILE")
        #expect(components == ["DICOMFILE"])
    }

    @Test("Parses empty file ID")
    func testParseFileIDEmpty() {
        let components = DICOMDIRParser.parseFileID("")
        #expect(components.isEmpty)
    }

    // MARK: - resolveFileURL Tests

    @Test("Resolves file URL relative to DICOMDIR")
    func testResolveFileURL() {
        let dicomdirURL = URL(fileURLWithPath: "/media/cdrom/DICOMDIR")
        let fileID = ["IMAGES", "CT001", "IM00001"]
        let resolved = DICOMDIRParser.resolveFileURL(fileID: fileID, relativeTo: dicomdirURL)
        #expect(resolved?.path == "/media/cdrom/IMAGES/CT001/IM00001")
    }

    @Test("Returns nil for empty file ID")
    func testResolveFileURLEmpty() {
        let dicomdirURL = URL(fileURLWithPath: "/media/cdrom/DICOMDIR")
        let resolved = DICOMDIRParser.resolveFileURL(fileID: [], relativeTo: dicomdirURL)
        #expect(resolved == nil)
    }

    // MARK: - isKnownRecordType Tests

    @Test("Recognizes known record types")
    func testKnownRecordTypes() {
        #expect(DICOMDIRParser.isKnownRecordType("PATIENT") == true)
        #expect(DICOMDIRParser.isKnownRecordType("STUDY") == true)
        #expect(DICOMDIRParser.isKnownRecordType("SERIES") == true)
        #expect(DICOMDIRParser.isKnownRecordType("IMAGE") == true)
        #expect(DICOMDIRParser.isKnownRecordType("SR DOCUMENT") == true)
        #expect(DICOMDIRParser.isKnownRecordType("RT DOSE") == true)
    }

    @Test("Recognizes case-insensitive record types")
    func testKnownRecordTypesCaseInsensitive() {
        #expect(DICOMDIRParser.isKnownRecordType("patient") == true)
        #expect(DICOMDIRParser.isKnownRecordType("Image") == true)
    }

    @Test("Rejects unknown record types")
    func testUnknownRecordType() {
        #expect(DICOMDIRParser.isKnownRecordType("UNKNOWN") == false)
        #expect(DICOMDIRParser.isKnownRecordType("") == false)
    }

    // MARK: - imageRecords Tests

    @Test("Filters image records from mixed records")
    func testImageRecords() {
        let records: [DICOMDIRParser.DirectoryRecord] = [
            DICOMDIRParser.DirectoryRecord(recordType: "PATIENT", patientName: "DOE^JOHN"),
            DICOMDIRParser.DirectoryRecord(recordType: "STUDY", studyInstanceUID: "1.2.3"),
            DICOMDIRParser.DirectoryRecord(recordType: "SERIES", seriesInstanceUID: "1.2.3.1"),
            DICOMDIRParser.DirectoryRecord(
                recordType: "IMAGE",
                referencedFileID: ["IMAGES", "IM001"],
                sopInstanceUID: "1.2.3.1.1"
            ),
            DICOMDIRParser.DirectoryRecord(
                recordType: "IMAGE",
                referencedFileID: ["IMAGES", "IM002"],
                sopInstanceUID: "1.2.3.1.2"
            ),
        ]
        let images = DICOMDIRParser.imageRecords(from: records)
        #expect(images.count == 2)
    }

    @Test("Image records excludes entries without file IDs")
    func testImageRecordsExcludesEmpty() {
        let records: [DICOMDIRParser.DirectoryRecord] = [
            DICOMDIRParser.DirectoryRecord(recordType: "IMAGE", sopInstanceUID: "1.2.3"),
        ]
        let images = DICOMDIRParser.imageRecords(from: records)
        #expect(images.isEmpty)
    }

    // MARK: - resolveAllFileURLs Tests

    @Test("Resolves all file URLs with deduplication")
    func testResolveAllFileURLs() {
        let dicomdirURL = URL(fileURLWithPath: "/media/DICOMDIR")
        let records: [DICOMDIRParser.DirectoryRecord] = [
            DICOMDIRParser.DirectoryRecord(
                recordType: "IMAGE",
                referencedFileID: ["IMG", "001"]
            ),
            DICOMDIRParser.DirectoryRecord(
                recordType: "IMAGE",
                referencedFileID: ["IMG", "002"]
            ),
            DICOMDIRParser.DirectoryRecord(
                recordType: "IMAGE",
                referencedFileID: ["IMG", "001"] // duplicate
            ),
            DICOMDIRParser.DirectoryRecord(
                recordType: "PATIENT" // no file ID
            ),
        ]
        let urls = DICOMDIRParser.resolveAllFileURLs(from: records, relativeTo: dicomdirURL)
        #expect(urls.count == 2)
    }

    // MARK: - DirectoryRecord Tests

    @Test("DirectoryRecord stores all fields")
    func testDirectoryRecordFields() {
        let record = DICOMDIRParser.DirectoryRecord(
            recordType: "IMAGE",
            referencedFileID: ["IMG", "001"],
            patientName: "DOE^JOHN",
            patientID: "P001",
            studyInstanceUID: "1.2.3",
            studyDate: "20240101",
            studyDescription: "CT Abdomen",
            seriesInstanceUID: "1.2.3.1",
            modality: "CT",
            sopInstanceUID: "1.2.3.1.1"
        )
        #expect(record.recordType == "IMAGE")
        #expect(record.referencedFileID == ["IMG", "001"])
        #expect(record.patientName == "DOE^JOHN")
        #expect(record.patientID == "P001")
        #expect(record.studyInstanceUID == "1.2.3")
        #expect(record.studyDate == "20240101")
        #expect(record.studyDescription == "CT Abdomen")
        #expect(record.seriesInstanceUID == "1.2.3.1")
        #expect(record.modality == "CT")
        #expect(record.sopInstanceUID == "1.2.3.1.1")
    }

    @Test("DirectoryRecord equality")
    func testDirectoryRecordEquality() {
        let a = DICOMDIRParser.DirectoryRecord(recordType: "IMAGE", referencedFileID: ["A"])
        let b = DICOMDIRParser.DirectoryRecord(recordType: "IMAGE", referencedFileID: ["A"])
        #expect(a == b)
    }

    @Test("DirectoryRecord inequality")
    func testDirectoryRecordInequality() {
        let a = DICOMDIRParser.DirectoryRecord(recordType: "IMAGE", referencedFileID: ["A"])
        let b = DICOMDIRParser.DirectoryRecord(recordType: "IMAGE", referencedFileID: ["B"])
        #expect(a != b)
    }

    // MARK: - Known Record Types

    /// PS3.3 2026a Table F.4-1: the 35 Directory Record Types (first column; the Enumerated
    /// Values of Directory Record Type (0004,1430), Table F.3-3).
    static let tableF41: Set<String> = [
        "PATIENT", "STUDY", "SERIES", "IMAGE", "RT DOSE", "RT STRUCTURE SET", "RT PLAN",
        "RT TREAT RECORD", "PRESENTATION", "WAVEFORM", "SR DOCUMENT", "KEY OBJECT DOC",
        "SPECTROSCOPY", "RAW DATA", "REGISTRATION", "FIDUCIAL", "HANGING PROTOCOL", "ENCAP DOC",
        "VALUE MAP", "STEREOMETRIC", "PALETTE", "IMPLANT", "IMPLANT ASSY", "IMPLANT GROUP", "PLAN",
        "MEASUREMENT", "SURFACE", "SURFACE SCAN", "TRACT", "ASSESSMENT", "RADIOTHERAPY",
        "ANNOTATION", "INVENTORY", "WF PRESENTATION", "PRIVATE",
    ]

    @Test("Known record types are exactly PS3.3 2026a Table F.4-1 plus the retired HL7 STRUC DOC")
    func testKnownRecordTypesMatchTableF41() {
        #expect(Self.tableF41.count == 35)
        #expect(DICOMDIRParser.knownRecordTypes.isSuperset(of: Self.tableF41))
        let extras = DICOMDIRParser.knownRecordTypes.subtracting(Self.tableF41)
        #expect(extras == ["HL7 STRUC DOC"], "only the retired F.5.33 type may be carried in addition")
        // Types added on 2026-10-05 that were missing before:
        for added in ["RT TREAT RECORD", "WAVEFORM", "PLAN", "ANNOTATION", "INVENTORY", "WF PRESENTATION"] {
            #expect(DICOMDIRParser.isKnownRecordType(added), "\(added)")
        }
    }

    @Test("Known record types includes all standard types")
    func testKnownRecordTypesSet() {
        #expect(DICOMDIRParser.knownRecordTypes.contains("PATIENT"))
        #expect(DICOMDIRParser.knownRecordTypes.contains("STUDY"))
        #expect(DICOMDIRParser.knownRecordTypes.contains("SERIES"))
        #expect(DICOMDIRParser.knownRecordTypes.contains("IMAGE"))
        #expect(DICOMDIRParser.knownRecordTypes.contains("PRESENTATION"))
        #expect(DICOMDIRParser.knownRecordTypes.contains("RT DOSE"))
        #expect(DICOMDIRParser.knownRecordTypes.contains("SR DOCUMENT"))
    }
}
