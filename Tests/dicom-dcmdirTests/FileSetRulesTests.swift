import XCTest
import ArgumentParser
import Foundation
import DICOMCore
import DICOMKit
@testable import dicom_dcmdir

/// File ID and File-set ID rules of PS3.10 2026a 8.1, 8.2, 8.5, 8.6 and the clauses
/// `dicom-dcmdir validate` names (PS3.3 Tables F.3-2, F.3-3, F.4-1).
final class FileSetRulesTests: XCTestCase {

    func testConformantFileIDHasNoViolations() {
        // PS3.10 8.2 example: SUBDIR1\SUBDIR2\SUBDIR3\ABCDEFGH
        XCTAssertEqual(FileSetRules.fileIDViolations(["SUBDIR1", "SUBDIR2", "SUBDIR3", "ABCDEFGH"]), [])
        XCTAssertEqual(FileSetRules.fileIDViolations(["IMG_0001"]), [])
    }

    func testFileIDComponentLongerThanEightOrWithLowercaseOrDotIsAViolation() {
        let v = FileSetRules.fileIDViolations(["sub_dir", "ref_a.dcm"])
        XCTAssertEqual(v.filter { $0.contains("characters other than A-Z, 0-9 and _") }.count, 2)
        XCTAssertEqual(v.filter { $0.contains("has 9 characters") }.count, 1)
        XCTAssertTrue(v.allSatisfy { $0.contains("PS3.10 8.2, 8.5") })
    }

    func testFileIDWithNineComponentsIsAViolation() {
        let v = FileSetRules.fileIDViolations(Array(repeating: "A", count: 9))
        XCTAssertEqual(v.count, 1)
        XCTAssertTrue(v[0].contains("9 components; a File ID has 1 to 8"))
        XCTAssertEqual(FileSetRules.fileIDViolations(Array(repeating: "A", count: 8)), [])
    }

    func testFileSetIDRules() {
        XCTAssertEqual(FileSetRules.fileSetIDViolations(""), [], "File-set ID (0004,1130) is Type 2: empty is allowed")
        XCTAssertEqual(FileSetRules.fileSetIDViolations("ABCDEFGHIJKLMNOP"), [])
        XCTAssertEqual(FileSetRules.fileSetIDViolations("ABCDEFGHIJKLMNOPQ").count, 1)   // 17 characters
        XCTAssertEqual(FileSetRules.fileSetIDViolations("study folder").count, 1)
    }

    func testDefaultFileSetIDIsDerivedWithinPS310Rules() {
        XCTAssertEqual(FileSetRules.defaultFileSetID(fromDirectoryName: "study_folder"), "STUDY_FOLDER")
        XCTAssertEqual(FileSetRules.defaultFileSetID(fromDirectoryName: "my study.2026-10-01"), "MY_STUDY_2026_10")
        XCTAssertEqual(FileSetRules.fileSetIDViolations(FileSetRules.defaultFileSetID(fromDirectoryName: "Ünïcode name!")), [])
    }

    func testValidationErrorsNameTheirClause() {
        XCTAssertEqual(FileSetRules.citation(for: .invalidRecordTypeInHierarchy("x")), "PS3.3 F.4, Table F.4-1")
        XCTAssertTrue(FileSetRules.describe(DICOMDirectory.ValidationError.duplicateSOPInstanceUID("1.2.3"))
            .hasPrefix("Duplicate SOP Instance UID: 1.2.3 [PS3.3 Table F.3-3"))
        XCTAssertTrue(FileSetRules.describe(DICOMDirectory.ValidationError.missingReferencedFile("A"))
            .contains("PS3.10 8.6"))
    }

    private func directory(fileIDs: [[String]], fileSetID: String = "FS1") -> DICOMDirectory {
        var series = DirectoryRecord.series(seriesInstanceUID: "1.2.3", modality: "CT", seriesNumber: nil, seriesDescription: nil)
        for (i, id) in fileIDs.enumerated() {
            series.addChild(DirectoryRecord.image(referencedFileID: id, sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                                                  sopInstanceUID: "1.2.3.\(i + 1)", transferSyntaxUID: "1.2.840.10008.1.2.1",
                                                  instanceNumber: nil))
        }
        var study = DirectoryRecord.study(studyInstanceUID: "1.2", studyDate: nil, studyTime: nil, studyDescription: nil)
        study.addChild(series)
        var patient = DirectoryRecord.patient(patientID: "P1", patientName: "A^B")
        patient.addChild(study)
        return DICOMDirectory(fileSetID: fileSetID, profile: .standardGeneralCD, rootRecords: [patient])
    }

    func testFindingsCoverFileIDsDuplicatesAndMissingFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dcmdirTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("DIR1"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("DIR1/IMG1"))
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertEqual(FileSetRules.findings(for: directory(fileIDs: [["DIR1", "IMG1"]]), mediaFolder: folder, checkFiles: true), [])

        let f = FileSetRules.findings(for: directory(fileIDs: [["DIR1", "IMG1"], ["DIR1", "IMG1"], ["DIR1", "IMG2"]]),
                                      mediaFolder: folder, checkFiles: true)
        XCTAssertEqual(f.count, 2)
        XCTAssertTrue(f[0].contains("referenced by more than one Directory Record"))
        XCTAssertTrue(f[1].contains("DIR1\\IMG2 does not exist in the File-set [PS3.10 8.6"))

        // Without --check-files nothing is looked up on disk.
        XCTAssertEqual(FileSetRules.findings(for: directory(fileIDs: [["DIR1", "IMG2"]]), mediaFolder: folder, checkFiles: false), [])
        XCTAssertEqual(FileSetRules.findings(for: directory(fileIDs: [], fileSetID: "media"), mediaFolder: nil, checkFiles: false).count, 1)
    }

    // MARK: - P-DCMDIR-FSID: refuse an invalid --file-set-id (PS3.10 8.1, 8.5)

    func testInvalidFileSetIDIsRefusedWithTheClause() {
        XCTAssertNil(FileSetRules.fileSetIDRefusal(""))
        XCTAssertNil(FileSetRules.fileSetIDRefusal("MYSTUDY_2026"))
        let lower = FileSetRules.fileSetIDRefusal("my study")
        XCTAssertNotNil(lower)
        XCTAssertTrue(lower!.contains("PS3.10 2026a 8.1, 8.5"))
        XCTAssertTrue(lower!.contains("Table F.3-2"))
        XCTAssertNotNil(FileSetRules.fileSetIDRefusal("ABCDEFGHIJKLMNOPQ"))   // 17 characters
    }

    func testCreateWithInvalidFileSetIDExitsOneAndWritesNothing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dcmdir-fsid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var command = try DICOMDCMDIR.Create.parse([dir.path, "--file-set-id", "bad id"])
        XCTAssertThrowsError(try command.run()) { error in
            XCTAssertEqual((error as? ExitCode)?.rawValue, 1)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("DICOMDIR").path))
    }

    // MARK: - P-DCMDIR-PROFILE: deprecated --profile spellings (PS3.11 2026a)

    func testDeprecatedProfileSpellingsMapAndNameTheIdentifierUsed() throws {
        // identifier each spelling maps to, and the PS3.11 2026a table that defines it
        let expected: [String: (String, String)] = [
            "STD-GEN-DVD": ("STD-GEN-DVD-JPEG", "Table H.1-1"),
            "STD-GEN-USB": ("STD-GEN-USB-JPEG", "Table J.1-1"),
            "STD-GEN-SEC": ("STD-GEN-SEC-CD", "Table D.1-1"),
            "STD-CTMR-XXXX": ("STD-CTMR-CD", "Table E.1-1"),
            "STD-US-XXXX": ("STD-US-ID-SF-CDR", "Table C.1-1"),
        ]
        for (spelling, (identifier, table)) in expected {
            let profile = try XCTUnwrap(DICOMDIRProfile(rawValue: spelling))
            XCTAssertEqual(profile.rawValue, identifier)
            XCTAssertTrue(profile.isStandard)
            let note = try XCTUnwrap(FileSetRules.profileDeprecationNote(requested: spelling, resolved: profile))
            XCTAssertTrue(note.contains("--profile \(spelling) is deprecated"), note)
            XCTAssertTrue(note.contains("using \(identifier) (PS3.11 2026a \(table))"), note)
        }
        // lower case is accepted by DICOMDIRProfile too
        XCTAssertNotNil(FileSetRules.profileDeprecationNote(requested: "std-gen-dvd", resolved: .standardGeneralDVDJPEG))
    }

    func testStandardProfileIdentifiersGetNoNote() throws {
        for id in ["STD-GEN-CD", "STD-GEN-DVD-JPEG", "STD-GEN-USB-J2K", "STD-US-ID-SF-CDR"] {
            let profile = try XCTUnwrap(DICOMDIRProfile(rawValue: id))
            XCTAssertNil(FileSetRules.profileDeprecationNote(requested: id, resolved: profile))
        }
    }
}
