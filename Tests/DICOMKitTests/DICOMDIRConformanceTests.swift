// DICOMDIRConformanceTests.swift
// DICOM 2026a deferred rows D70, D128, D129, D131 (DICOMDIR builder / workflow / dump).
//
// D129: every instance gets an IMAGE record (PS3.3 2026a F.4, Table F.4-1).
// D70:  PS3.11 2026a Tables D.3-1, H.3-1, J.3-1, M.3-1, A.3-1, C.3-1 are enforced.
// D131: Referenced File IDs follow PS3.10 2026a 8.2 / 8.5; --copy-to assigns them.
// D128: dump labels are PS3.6 Attribute Names; File-set Consistency Flag per Table F.3-3.

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore
import DICOMDictionary

final class DICOMDIRConformanceTests: XCTestCase {

    private let ctImage = "1.2.840.10008.5.1.4.1.1.2"
    private let explicitLE = "1.2.840.10008.1.2.1"
    private let implicitLE = "1.2.840.10008.1.2"
    private let jpegBaseline = "1.2.840.10008.1.2.4.50"
    private let jpegLosslessSV1 = "1.2.840.10008.1.2.4.70"
    private let j2kLossless = "1.2.840.10008.1.2.4.90"

    private var counter = 0
    private func uid() -> String {
        counter += 1
        return "1.2.826.0.1.3680043.10.1078.\(UInt32.random(in: 1...UInt32.max)).\(counter)"
    }

    private func instance(patient: String = "P1", study: String, series: String, sop: String? = nil,
                          sopClass: String = "1.2.840.10008.5.1.4.1.1.2",
                          transferSyntax: String = "1.2.840.10008.1.2.1", number: Int = 1) -> DICOMFile {
        var ds = DataSet()
        let instanceUID = sop ?? uid()
        ds.setString(sopClass, for: .sopClassUID, vr: .UI)
        ds.setString(instanceUID, for: .sopInstanceUID, vr: .UI)
        ds.setString(study, for: .studyInstanceUID, vr: .UI)
        ds.setString(series, for: .seriesInstanceUID, vr: .UI)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setString("Conformance^Test", for: .patientName, vr: .PN)
        ds.setString(patient, for: .patientID, vr: .LO)
        ds.setString("\(number)", for: .instanceNumber, vr: .IS)
        // Rows / Columns: Type 1 keys of the IMAGE record under STD-GEN-DVD-* (PS3.11 2026a H.3-2, D239)
        ds.setUInt16(512, for: .rows)
        ds.setUInt16(512, for: .columns)
        return DICOMFile.create(dataSet: ds, sopClassUID: sopClass, sopInstanceUID: instanceUID,
                                transferSyntaxUID: transferSyntax)
    }

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DICOMDIRConformance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - D129: every instance indexed (PS3.3 F.4, Table F.4-1)

    func testEveryInstanceOfASeriesAndEverySeriesOfAStudyGetsARecord() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "D129", profile: .standardGeneralCD)
        let study = uid(), seriesA = uid(), seriesB = uid()
        try builder.addFile(instance(study: study, series: seriesA, number: 1), relativePath: ["IMG1"])
        try builder.addFile(instance(study: study, series: seriesA, number: 2), relativePath: ["IMG2"])
        try builder.addFile(instance(study: study, series: seriesB, number: 1), relativePath: ["IMG3"])
        try builder.addFile(instance(study: uid(), series: uid(), number: 1), relativePath: ["IMG4"])
        let dir = builder.build()
        let stats = dir.statistics()
        XCTAssertEqual(stats.patientCount, 1)
        XCTAssertEqual(stats.studyCount, 2)
        XCTAssertEqual(stats.seriesCount, 3)
        XCTAssertEqual(stats.imageCount, 4, "one IMAGE record per instance (was 1 per series)")
        XCTAssertEqual(dir.rootRecords[0].children[0].children[0].children.map { $0.referencedFileID ?? [] },
                       [["IMG1"], ["IMG2"]], "records keep the order the instances were added")
        // Round-trip through the writer and reader keeps every record.
        let reread = try DICOMDIRReader.read(from: try DICOMDIRWriter.write(dir))
        XCTAssertEqual(reread.statistics().imageCount, 4)
        XCTAssertNoThrow(try reread.validate())
    }

    func testDuplicateSOPInstanceIsRefused() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "DUP", profile: .standardGeneralCD)
        let study = uid(), series = uid(), sop = uid()
        try builder.addFile(instance(study: study, series: series, sop: sop), relativePath: ["A"])
        XCTAssertThrowsError(try builder.addFile(instance(study: study, series: series, sop: sop), relativePath: ["B"])) {
            guard case DICOMDIRProfileRules.Refusal.duplicateSOPInstance(let refused, let fileID) = $0 else {
                return XCTFail("expected duplicateSOPInstance, got \($0)")
            }
            XCTAssertEqual(refused, sop)
            XCTAssertEqual(fileID, ["A"])
        }
    }

    // MARK: - D131: PS3.10 8.2 / 8.5 File IDs

    func testFileIDRules() {
        XCTAssertEqual(DICOMDIRProfileRules.fileIDProblems(["DICOM", "PT000001", "IM000001"]), [])
        XCTAssertEqual(DICOMDIRProfileRules.fileIDProblems(Array(repeating: "A", count: 8)), [])
        XCTAssertFalse(DICOMDIRProfileRules.fileIDProblems(Array(repeating: "A", count: 9)).isEmpty, "8 components at most")
        XCTAssertFalse(DICOMDIRProfileRules.fileIDProblems(["ABCDEFGHI"]).isEmpty, "8 characters at most")
        XCTAssertFalse(DICOMDIRProfileRules.fileIDProblems(["img1.dcm"]).isEmpty, "lower case and '.' are not allowed")
        XCTAssertFalse(DICOMDIRProfileRules.fileIDProblems([]).isEmpty, "at least one component")
        XCTAssertFalse(DICOMDIRProfileRules.fileIDProblems([""]).isEmpty, "a component has 1 character at least")
    }

    func testBuilderRefusesNonConformantFileID() {
        var builder = DICOMDirectory.Builder(fileSetID: "FID", profile: .standardGeneralCD)
        XCTAssertThrowsError(try builder.addFile(instance(study: uid(), series: uid()), relativePath: ["img0.dcm"])) {
            guard case DICOMDIRProfileRules.Refusal.nonConformantFileID = $0 else {
                return XCTFail("expected nonConformantFileID, got \($0)")
            }
            XCTAssertTrue(String(describing: $0).contains("PS3.10 2026a 8.2, 8.5"))
        }
    }

    func testWorkflowRefusesInPlaceNonConformantPathsAndCopyAssignsConformantIDs() throws {
        let input = try tempDir()
        let study = uid(), series = uid()
        for i in 1...3 {
            try instance(study: study, series: series, number: i).write()
                .write(to: input.appendingPathComponent("img\(i).dcm"))
        }
        try instance(study: study, series: series, number: 4).write()
            .write(to: input.appendingPathComponent("IMG4"))

        // In place: only the conformant path is indexed; the others are listed with the clause.
        let inPlace = try DICOMDIRWorkflow.buildDirectory(
            fromFilesIn: input, recursive: true, strict: false, fileSetID: "INPLACE", profile: .standardGeneralCD)
        XCTAssertEqual(inPlace.processed, 1)
        XCTAssertEqual(inPlace.failures.map(\.file), ["img1.dcm", "img2.dcm", "img3.dcm"])
        XCTAssertTrue(inPlace.failures.allSatisfy { $0.reason.contains("PS3.10 2026a 8.2, 8.5") })
        let summary = DICOMDIRWorkflow.renderCreateSummary(inPlace, outputPath: "DICOMDIR")
        XCTAssertTrue(summary.contains("    img1.dcm: File ID img1.dcm is not a conformant File ID"))

        // Copying: the File-set Creator assigns DICOM\PTnnnnnn\STnnnnnn\SEnnnnnn\IMnnnnnn.
        let media = try tempDir()
        let copied = try DICOMDIRWorkflow.buildDirectory(
            fromFilesIn: input, recursive: true, strict: false, fileSetID: "COPY",
            profile: .standardGeneralCD, copyingInto: media)
        XCTAssertEqual(copied.processed, 4)
        XCTAssertEqual(copied.failures, [])
        let ids = copied.directory.allRecords().compactMap(\.referencedFileID)
        XCTAssertEqual(ids, (1...4).map { ["DICOM", "PT000001", "ST000001", "SE000001", String(format: "IM%06d", $0)] })
        for id in ids {
            XCTAssertEqual(DICOMDIRProfileRules.fileIDProblems(id), [])
            let file = id.reduce(media) { $0.appendingPathComponent($1) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "\(id) copied")
        }
        // The copy is byte-identical to its source.
        let source = try Data(contentsOf: input.appendingPathComponent("IMG4"))
        let sourceUID = try DICOMFile.read(from: source).dataSet.string(for: .sopInstanceUID)
        let record = try XCTUnwrap(copied.directory.allRecords().first { $0.referencedSOPInstanceUID == sourceUID })
        let copy = try Data(contentsOf: try XCTUnwrap(record.referencedFileID).reduce(media) { $0.appendingPathComponent($1) })
        XCTAssertEqual(copy, source)
    }

    // MARK: - D70: PS3.11 profile tables

    func testGeneratedProfileTablesMatchTheDumpedRowCounts() {
        // PS3.11 2026a, non-Basic-Directory rows (dumped by Scripts/generate_dicomdir_profile_rules.py).
        let expected: [String: Int] = ["A.3-1": 1, "B.3-1": 5, "C.3-1": 6, "D.3-1": 1, "E.3-1": 10, "G.3-1": 1,
                                       "H.3-1": 6, "I.3-1": 1, "J.3-1": 6, "K.3-1": 4, "L.3-1": 1, "L.3-2": 2,
                                       "M.3-1": 10, "N.3-1": 3]
        XCTAssertEqual(DICOMDIRProfileRules.tables.mapValues(\.count), expected)
        XCTAssertEqual(DICOMDIRProfileRules.nonPatientStorageUIDs.count, 9, "PS3.4 Table GG.3-1")
    }

    func testEveryStandardProfileHasATable() {
        for profile in DICOMDIRProfile.allStandard {
            XCTAssertNotNil(DICOMDIRProfileRules.tableLabel(for: profile), profile.rawValue)
        }
        XCTAssertEqual(DICOMDIRProfileRules.tableLabel(for: .ultrasound(.combinedCalibration, frames: true, media: .dvd)), "C.3-1")
        XCTAssertNil(DICOMDIRProfileRules.tableLabel(for: DICOMDIRProfile(unchecked: "PRIVATE-PROFILE")))
    }

    func testAllowedTransferSyntaxesPerTable() {
        func allowed(_ p: DICOMDIRProfile, _ sop: String = "1.2.840.10008.5.1.4.1.1.2") -> Set<String>? {
            DICOMDIRProfileRules.allowedTransferSyntaxes(sopClassUID: sop, profile: p)
        }
        // D.3-1: Explicit VR Little Endian only.
        XCTAssertEqual(allowed(.standardGeneralCD), [explicitLE])
        XCTAssertEqual(allowed(.standardGeneralBD), [explicitLE])
        // H.3-1 / J.3-1 / M.3-1: -JPEG adds .70/.50/.51, -J2K adds .90/.91.
        let jpeg: Set<String> = [explicitLE, jpegLosslessSV1, jpegBaseline, "1.2.840.10008.1.2.4.51"]
        let j2k: Set<String> = [explicitLE, j2kLossless, "1.2.840.10008.1.2.4.91"]
        XCTAssertEqual(allowed(.standardGeneralDVDJPEG), jpeg)
        XCTAssertEqual(allowed(.standardGeneralDVDJPEG2000), j2k)
        XCTAssertEqual(allowed(.standardGeneralUSBJPEG), jpeg)
        XCTAssertEqual(allowed(.standardGeneralSecureSDJPEG2000), j2k)
        XCTAssertEqual(allowed(.standardGeneralBDJPEG), jpeg)
        // M.3-1 / N.3-1 MPEG profiles: the syntax the profile is named after.
        XCTAssertEqual(allowed(.standardGeneralBDMPEG2MPML), [explicitLE, "1.2.840.10008.1.2.4.100"])
        XCTAssertEqual(allowed(.standardGeneralBDMPEG4HPLV41BD), [explicitLE, "1.2.840.10008.1.2.4.103"])
        XCTAssertEqual(allowed(.standardGeneralBDMPEG4HPLV42ThreeD), ["1.2.840.10008.1.2.4.105"])
        XCTAssertEqual(allowed(.standardDVDMPEG2MPML), ["1.2.840.10008.1.2.4.100"])
        // G.3-1 / L.3-1: "Defined in Conformance Statement".
        XCTAssertNil(allowed(.standardGeneralMIME))
        XCTAssertNil(allowed(.standardGeneralZIPMail))
        // A.3-1: XA in JPEG Lossless SV1 only; CT not in the profile.
        XCTAssertEqual(allowed(.standardXABasicCardiacCD, "1.2.840.10008.5.1.4.1.1.12.1"), [jpegLosslessSV1])
        XCTAssertEqual(allowed(.standardXABasicCardiacCD), [])
        // B.3-1: JPEG Baseline/Extended "Disallowed for CD".
        XCTAssertEqual(allowed(.standardXA1024CD, "1.2.840.10008.5.1.4.1.1.12.1"), [jpegLosslessSV1])
        XCTAssertEqual(allowed(.standardXA1024DVD, "1.2.840.10008.5.1.4.1.1.12.1"),
                       [jpegLosslessSV1, jpegBaseline, "1.2.840.10008.1.2.4.51"])
        // C.3-1 / C.1-1: single-frame profiles carry the Ultrasound Image only.
        XCTAssertEqual(allowed(.ultrasound(.imageDisplay, frames: false, media: .cdr), "1.2.840.10008.5.1.4.1.1.3.1"), [])
        XCTAssertEqual(allowed(.ultrasound(.imageDisplay, frames: true, media: .cdr), "1.2.840.10008.5.1.4.1.1.3.1"),
                       [explicitLE, "1.2.840.10008.1.2.5", jpegBaseline])
        // Non-standard identifiers are not checked.
        XCTAssertNil(allowed(DICOMDIRProfile(unchecked: "PRIVATE-PROFILE")))
    }

    func testGenericProfilesAdmitMediaStorageSOPClassesOnly() {
        XCTAssertTrue(DICOMDIRProfileRules.isMediaStorageSOPClass(ctImage))
        XCTAssertTrue(DICOMDIRProfileRules.isMediaStorageSOPClass("1.2.840.10008.5.1.4.38.1"), "GG.3-1 Hanging Protocol")
        XCTAssertFalse(DICOMDIRProfileRules.isMediaStorageSOPClass("1.2.840.10008.1.3.10"), "the DICOMDIR is not a composite IOD")
        XCTAssertFalse(DICOMDIRProfileRules.isMediaStorageSOPClass("1.2.840.10008.3.1.2.3.3"), "MPPS is not a storage class")
        guard case .sopClassNotInProfile(_, "STD-GEN-CD", "D.3-1")? = DICOMDIRProfileRules.refusal(
            sopClassUID: "1.2.3.4.5", transferSyntaxUID: explicitLE, profile: .standardGeneralCD) else {
            return XCTFail("a private SOP Class is not a Media Storage SOP Class of PS3.4")
        }
    }

    func testBuilderRefusesTransferSyntaxOutsideTheProfileAndNamesTheTable() throws {
        var cd = DICOMDirectory.Builder(fileSetID: "CD", profile: .standardGeneralCD)
        XCTAssertThrowsError(try cd.addFile(instance(study: uid(), series: uid(), transferSyntax: implicitLE),
                                            relativePath: ["IMG1"])) {
            guard case DICOMDIRProfileRules.Refusal.transferSyntaxNotInProfile(let ts, _, "STD-GEN-CD", "D.3-1", let allowed) = $0 else {
                return XCTFail("expected transferSyntaxNotInProfile, got \($0)")
            }
            XCTAssertEqual(ts, implicitLE)
            XCTAssertEqual(allowed, [explicitLE])
            XCTAssertTrue(String(describing: $0).contains("[PS3.11 2026a Table D.3-1]"))
        }
        XCTAssertThrowsError(try cd.addFile(instance(study: uid(), series: uid(), transferSyntax: jpegBaseline),
                                            relativePath: ["IMG2"]))
        // The same JPEG file is fine under a -JPEG profile, refused under -J2K.
        var dvd = DICOMDirectory.Builder(fileSetID: "DVD", profile: .standardGeneralDVDJPEG)
        XCTAssertNoThrow(try dvd.addFile(instance(study: uid(), series: uid(), transferSyntax: jpegBaseline),
                                         relativePath: ["IMG1"]))
        var j2k = DICOMDirectory.Builder(fileSetID: "J2K", profile: .standardGeneralUSBJPEG2000)
        XCTAssertThrowsError(try j2k.addFile(instance(study: uid(), series: uid(), transferSyntax: jpegBaseline),
                                             relativePath: ["IMG1"]))
    }

    // MARK: - D128: dump labels

    func testVerboseDumpUsesPS36AttributeNamesAndConsistencyFlagText() throws {
        var builder = DICOMDirectory.Builder(fileSetID: "DUMP", profile: .standardGeneralCD)
        try builder.addFile(instance(study: uid(), series: uid()), relativePath: ["IMG1"])
        let dir = builder.build()
        let tree = DICOMDIRDumpFormatter.render(dir, format: .tree, verbose: true)
        let text = DICOMDIRDumpFormatter.render(dir, format: .text, verbose: true)
        for out in [tree, text] {
            XCTAssertTrue(out.contains("(0010,0020) Patient ID: P1"), out)
            XCTAssertTrue(out.contains("(0020,000D) Study Instance UID: "), out)
            XCTAssertTrue(out.contains("(0020,0013) Instance Number: 1"), out)
            XCTAssertTrue(out.contains("File-set Consistency Flag: 0000H (no known inconsistencies)"), out)
            XCTAssertFalse(out.contains("Consistent:"), out)
        }
        XCTAssertEqual(DICOMDIRDumpFormatter.attributeLabel(Tag(group: 0x0004, element: 0x1212)),
                       "(0004,1212) File-set Consistency Flag")
        XCTAssertEqual(DICOMDIRDumpFormatter.attributeLabel(Tag(group: 0x0009, element: 0x1001)), "(0009,1001)")
        let report = DICOMDIRWorkflow.renderValidationReport(dir, detailed: false)
        XCTAssertTrue(report.contains("  File-set Consistency Flag: 0000H (no known inconsistencies)\n"))
    }
}
