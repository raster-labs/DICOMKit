import XCTest
import Foundation
import DICOMCore
import DICOMDictionary
import DICOMKit
@testable import dicom_anon

/// `dicom-anon` option surface against DICOM 2026a. Option names are the PS3.15 2026a
/// E.3 Option names, codes and meanings are PS3.16 2026a CID 7050 rows, and the action
/// codes are PS3.15 2026a Table E.1-1a, all dumped from the DocBook by script.
final class AnonOptionContractTests: XCTestCase {

    private var help: String {
        DICOMAnon.helpMessage(columns: 10_000).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Help names the PS3.15 2026a Options

    func testOptionFlagsNameThePS315Options() {
        for name in [
            "Retain Longitudinal Temporal Information With Full Dates Option",
            "Retain Longitudinal Temporal Information With Modified Dates Option",
            "Retain Patient Characteristics Option",
            "Retain Device Identity Option",
            "Retain Institution Identity Option",
            "Retain UIDs Option",
            "Clean Descriptors Option",
            "Clean Pixel Data",
        ] {
            XCTAssertTrue(help.contains(name), "help lacks the PS3.15 E.3 Option name '\(name)'")
        }
    }

    /// The legacy profiles are documented as not being the PS3.15 Basic Profile
    /// (`--profile basic` matches 11 of the 647 data-set rows of Table E.1-1).
    func testLegacyProfilesAreDocumentedAsNotPS315() {
        XCTAssertTrue(help.contains("NOT the PS3.15 Basic Profile"))
        XCTAssertTrue(help.contains("ps315 (PS3.15 Basic Application Level Confidentiality Profile, Table E.1-1; the default)"))
        XCTAssertNotNil(AnonCLI.legacyProfileNotice("legacy-basic"))
        XCTAssertNotNil(AnonCLI.legacyProfileNotice("clinical-trial"))
        XCTAssertNil(AnonCLI.legacyProfileNotice("ps315"))
    }

    // MARK: - Option validation

    func testOptionFlagsAreRejectedOnLegacyProfiles() {
        var flags = AnonCLI.PS315Flags()
        flags.retainUids = true
        XCTAssertThrowsError(try AnonCLI.validate(profile: "legacy-basic", flags: flags, shiftDates: nil,
                                                  regenerateUids: false, keep: []))
        XCTAssertNoThrow(try AnonCLI.validate(profile: "ps315", flags: flags, shiftDates: nil,
                                              regenerateUids: false, keep: []))
        XCTAssertNoThrow(try AnonCLI.validate(profile: "basic", flags: flags, shiftDates: nil,
                                              regenerateUids: false, keep: []), "basic is ps315")
        XCTAssertNoThrow(try AnonCLI.validate(profile: "legacy-basic", flags: AnonCLI.PS315Flags(), shiftDates: 10,
                                              regenerateUids: true, keep: ["Modality"]))
        XCTAssertThrowsError(try AnonCLI.validate(profile: "strict", flags: AnonCLI.PS315Flags(), shiftDates: nil,
                                                  regenerateUids: false, keep: []))
    }

    /// PS3.15 E.3.6: "Two mutually exclusive Options"; dates are modified by shifting.
    func testLongitudinalTemporalOptionsAreMutuallyExclusive() {
        var full = AnonCLI.PS315Flags(); full.retainFullDates = true
        var modified = AnonCLI.PS315Flags(); modified.retainModifiedDates = true
        var both = full; both.retainModifiedDates = true
        XCTAssertThrowsError(try AnonCLI.validate(profile: "ps315", flags: both, shiftDates: 5, regenerateUids: false, keep: []))
        XCTAssertThrowsError(try AnonCLI.validate(profile: "ps315", flags: full, shiftDates: 5, regenerateUids: false, keep: []))
        XCTAssertThrowsError(try AnonCLI.validate(profile: "ps315", flags: modified, shiftDates: nil, regenerateUids: false, keep: []))
        // --shift-dates was silently ignored without a retention Option; now refused.
        XCTAssertThrowsError(try AnonCLI.validate(profile: "ps315", flags: AnonCLI.PS315Flags(), shiftDates: 5, regenerateUids: false, keep: []))
        XCTAssertNoThrow(try AnonCLI.validate(profile: "ps315", flags: modified, shiftDates: 5, regenerateUids: false, keep: []))
        XCTAssertNoThrow(try AnonCLI.validate(profile: "ps315", flags: full, shiftDates: nil, regenerateUids: false, keep: []))
    }

    func testKeepAndRetainUIDConflictsAreRefusedOnPS315() {
        var uids = AnonCLI.PS315Flags(); uids.retainUids = true
        XCTAssertThrowsError(try AnonCLI.validate(profile: "ps315", flags: uids, shiftDates: nil, regenerateUids: true, keep: []))
        XCTAssertThrowsError(try AnonCLI.validate(profile: "ps315", flags: AnonCLI.PS315Flags(), shiftDates: nil,
                                                  regenerateUids: false, keep: ["StudyDate"]))
    }

    /// Each flag selects the CID 7050 code of its Option (PS3.16 2026a CID 7050 rows).
    func testFlagsRecordTheirCID7050Codes() {
        func codes(_ f: (inout AnonCLI.PS315Flags) -> Void, shift: Int? = nil) -> [String] {
            var flags = AnonCLI.PS315Flags(); f(&flags)
            return AnonCLI.options(flags: flags, shiftDates: shift).methodCodes.map { "\($0.codeValue) \($0.meaning)" }
        }
        XCTAssertEqual(codes({ _ in }), ["113100 Basic Application Confidentiality Profile"])
        XCTAssertEqual(codes({ $0.retainFullDates = true }),
                       ["113100 Basic Application Confidentiality Profile",
                        "113106 Retain Longitudinal Temporal Information Full Dates Option"])
        XCTAssertEqual(codes({ $0.retainModifiedDates = true }, shift: -30),
                       ["113100 Basic Application Confidentiality Profile",
                        "113107 Retain Longitudinal Temporal Information Modified Dates Option"])
        XCTAssertEqual(codes({ $0.retainCharacteristics = true }).last, "113108 Retain Patient Characteristics Option")
        XCTAssertEqual(codes({ $0.retainDevice = true }).last, "113109 Retain Device Identity Option")
        XCTAssertEqual(codes({ $0.retainUids = true }).last, "113110 Retain UIDs Option")
        XCTAssertEqual(codes({ $0.retainInstitution = true }).last, "113112 Retain Institution Identity Option")
        XCTAssertEqual(codes({ $0.cleanDescriptors = true }).last, "113105 Clean Descriptors Option")
        // PS3.15 2026a E.3.10 and E.3.3 (D159).
        XCTAssertEqual(codes({ $0.retainSafePrivate = true }).last, "113111 Retain Safe Private Option")
        XCTAssertEqual(codes({ $0.cleanGraphics = true }).last, "113103 Clean Graphics Option")
        XCTAssertEqual(AnonCLI.PS315Flags(retainSafePrivate: true, cleanGraphics: true).setFlags,
                       ["--retain-safe-private", "--clean-graphics"])
    }

    // MARK: - Tag parsing

    func testRemoveAndReplaceAcceptPS6Keywords() {
        XCTAssertEqual(AnonCLI.parseTag("PatientAge"), Tag(group: 0x0010, element: 0x1010))
        XCTAssertEqual(AnonCLI.parseTag("InstitutionName"), Tag(group: 0x0008, element: 0x0080))
        XCTAssertEqual(AnonCLI.parseTag("0010,0010"), .patientName)
        XCTAssertEqual(AnonCLI.parseTag("(0008,0060)"), .modality)
        XCTAssertNil(AnonCLI.parseTag("NoSuchKeyword"))
    }

    // MARK: - Output: action labels and recorded attributes

    private func fixture() -> DataSet {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6.7.8.9", for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.100", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.5.200", for: .seriesInstanceUID, vr: .UI)
        ds.setString("OT", for: .modality, vr: .CS)
        ds.setString("Doe^John", for: .patientName, vr: .PN)
        ds.setString("MRN-1", for: .patientID, vr: .LO)
        ds.setString("20240315", for: .studyDate, vr: .DA)
        ds.setString("General Hospital", for: .institutionName, vr: .LO)
        ds.setString("NO", for: .burnedInAnnotation, vr: .CS)
        ds.setString("CREATOR", for: Tag(group: 0x0009, element: 0x0010), vr: .LO)
        ds.setString("secret", for: Tag(group: 0x0009, element: 0x1001), vr: .LO)
        return ds
    }

    /// Table E.1-1 Basic Profile: Patient's Name Z, Patient ID Z, Study Date Z,
    /// SOP Instance UID U, Institution Name X/Z/D (removed), private attributes X.
    func testActionsAreLabelledWithTableE11aCodesAndPS6Names() {
        let source = fixture()
        let file = DICOMFile.create(dataSet: source, sopClassUID: "1.2.840.10008.5.1.4.1.1.7")
        let (out, _, _) = Anonymizer(profile: .basic).deidentify(file: file, options: .basic)
        let actions = AnonCLI.attributeActions(before: source, after: out.dataSet, options: .basic)
        let byTag = Dictionary(uniqueKeysWithValues: actions.map { ($0.tag, $0) })
        XCTAssertEqual(byTag[.patientName], .init(tag: .patientName, code: "Z", name: "Patient's Name"))
        XCTAssertEqual(byTag[.patientID]?.code, "Z")
        XCTAssertEqual(byTag[.studyDate]?.code, "Z")
        XCTAssertEqual(byTag[.sopInstanceUID], .init(tag: .sopInstanceUID, code: "U", name: "SOP Instance UID"))
        XCTAssertEqual(byTag[.institutionName]?.code, "X")
        XCTAssertEqual(byTag[Tag(group: 0x0009, element: 0x1001)]?.code, "X")
        XCTAssertEqual(byTag[Tag(group: 0x0009, element: 0x1001)]?.name, "Private Data Element")
        XCTAssertEqual(byTag[Tag(group: 0x0012, element: 0x0062)],
                       .init(tag: Tag(group: 0x0012, element: 0x0062), code: "recorded", name: "Patient Identity Removed"))
        XCTAssertNil(byTag[.modality], "unchanged attributes are not listed")
        let lines = AnonCLI.actionLines(path: "f.dcm", actions: actions)
        XCTAssertTrue(lines.contains("  Z        (0010,0010) Patient's Name\n"))
        XCTAssertTrue(lines.contains("PS3.15 Table E.1-1a"))
    }

    /// Modified Dates: the Table E.1-1 column is C; a shifted date is labelled C.
    func testShiftedDateIsLabelledClean() {
        let source = fixture()
        var flags = AnonCLI.PS315Flags(); flags.retainModifiedDates = true
        let options = AnonCLI.options(flags: flags, shiftDates: 10)
        let (out, _, _) = Anonymizer(profile: .basic).deidentify(
            file: DICOMFile.create(dataSet: source, sopClassUID: "1.2.840.10008.5.1.4.1.1.7"), options: options)
        XCTAssertEqual(out.dataSet.string(for: .studyDate), "20240325")
        let actions = AnonCLI.attributeActions(before: source, after: out.dataSet, options: options)
        XCTAssertEqual(actions.first { $0.tag == .studyDate }?.code, "C")
    }

    func testAuditLogListsCodesAndNamesWithoutValues() {
        let actions = [AnonCLI.AttributeAction(tag: .patientName, code: "Z", name: "Patient's Name")]
        let text = AnonCLI.auditLogText(profileDescription: ["Basic Application Confidentiality Profile"],
                                        files: [("a.dcm", actions)], generated: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(text.contains("Method: Basic Application Confidentiality Profile\n"))
        XCTAssertTrue(text.contains("] a.dcm - Z - (0010,0010) Patient's Name\n"))
        XCTAssertFalse(text.contains("Doe"))
    }

    // MARK: - End to end

    private func run(_ args: [String]) throws {
        var command = try XCTUnwrap(DICOMAnon.parseAsRoot(args) as? DICOMAnon)
        try command.run()
    }

    /// --profile ps315 writes (0012,0062) YES and the CID 7050 codes, and now applies
    /// --remove / --replace (they were silently ignored on this path).
    func testPS315WritesMethodAttributesAndAppliesRemoveReplace() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("in.dcm"), output = dir.appendingPathComponent("out.dcm")
        let log = dir.appendingPathComponent("audit.log")
        try DICOMFile.create(dataSet: fixture(), sopClassUID: "1.2.840.10008.5.1.4.1.1.7").write().write(to: input)

        try run([input.path, "-o", output.path, "--profile", "ps315", "--retain-uids",
                 "--remove", "Modality", "--replace", "PatientID=SUBJ01", "--audit-log", log.path])
        let ds = try DICOMFile.read(from: Data(contentsOf: output)).dataSet
        XCTAssertEqual(ds.string(for: Tag(group: 0x0012, element: 0x0062)), "YES")
        let codes = (ds.sequence(for: Tag(group: 0x0012, element: 0x0064)) ?? []).compactMap {
            $0.string(for: .codeValue)?.trimmingCharacters(in: .whitespaces)
        }
        XCTAssertEqual(codes, ["113100", "113110"])
        XCTAssertNil(ds[.modality])
        XCTAssertEqual(ds.string(for: .patientID)?.trimmingCharacters(in: .whitespaces), "SUBJ01")
        XCTAssertEqual(ds.string(for: .sopInstanceUID)?.trimmingCharacters(in: CharacterSet(charactersIn: " \0")),
                       "1.2.3.4.5.6.7.8.9", "Retain UIDs Option keeps UIDs")
        let audit = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(audit.contains(" - Z - (0010,0010) Patient's Name\n"))
        XCTAssertTrue(audit.contains("Method: Basic Application Confidentiality Profile; Retain UIDs Option\n"))
    }
}

extension AnonOptionContractTests {
    /// PS3.10 7.1 / Table E.1-1 (0002,0003) U: the meta header carries the replaced UID.
    func testMediaStorageSOPInstanceUIDFollowsReplacedSOPInstanceUID() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("in.dcm"), output = dir.appendingPathComponent("out.dcm")
        var ds = DataSet()
        ds.setString("1.2.3.4.5.6.7.8.9", for: .sopInstanceUID, vr: .UI)
        ds.setString("OT", for: .modality, vr: .CS)
        try DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.7").write().write(to: input)
        var command = try XCTUnwrap(DICOMAnon.parseAsRoot([input.path, "-o", output.path, "--profile", "ps315"]) as? DICOMAnon)
        try command.run()
        let file = try DICOMFile.read(from: Data(contentsOf: output))
        let trim = CharacterSet(charactersIn: " \0")
        let sop = try XCTUnwrap(file.dataSet.string(for: .sopInstanceUID)?.trimmingCharacters(in: trim))
        XCTAssertNotEqual(sop, "1.2.3.4.5.6.7.8.9")
        XCTAssertEqual(file.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID)?.trimmingCharacters(in: trim), sop)
    }
}

// MARK: - P-ANON-PROFILE, P-ANON-RETAIN-DATES (approved 2026-10-01)

extension AnonOptionContractTests {

    /// PS3.15 2026a E.1: the Basic Application Level Confidentiality Profile is the
    /// default; `basic` names it; the old lists are `legacy-*` (deprecated).
    func testProfileNamesResolve() throws {
        XCTAssertEqual(AnonCLI.resolveProfile("ps315"), .ps315)
        XCTAssertEqual(AnonCLI.resolveProfile("basic"), .ps315)
        XCTAssertEqual(AnonCLI.resolveProfile("BASIC"), .ps315)
        XCTAssertEqual(AnonCLI.resolveProfile("legacy-basic"), .legacyBasic)
        XCTAssertEqual(AnonCLI.resolveProfile("legacy-clinical-trial"), .legacyClinicalTrial)
        XCTAssertEqual(AnonCLI.resolveProfile("clinical-trial"), .legacyClinicalTrial)
        XCTAssertEqual(AnonCLI.resolveProfile("clinicaltrial"), .legacyClinicalTrial)
        XCTAssertEqual(AnonCLI.resolveProfile("legacy-research"), .legacyResearch)
        XCTAssertEqual(AnonCLI.resolveProfile("research"), .legacyResearch)
        XCTAssertNil(AnonCLI.resolveProfile("strict"))
        guard case .basic? = AnonCLI.Profile.legacyBasic.legacyProfile else {
            return XCTFail("legacy-basic runs the old basic list")
        }
        XCTAssertNil(AnonCLI.Profile.ps315.legacyProfile)

        let parsed = try XCTUnwrap(DICOMAnon.parseAsRoot(["in.dcm", "--dry-run"]) as? DICOMAnon)
        XCTAssertEqual(parsed.profile, "ps315", "the default profile is the PS3.15 Basic Profile")
    }

    func testDeprecationNotices() {
        let basic = AnonCLI.legacyProfileNotice("basic") ?? ""
        XCTAssertTrue(basic.contains("legacy-basic"), "basic says where the old list went")
        let trial = AnonCLI.legacyProfileNotice("clinical-trial") ?? ""
        XCTAssertTrue(trial.hasPrefix("Deprecated: --profile clinical-trial (now legacy-clinical-trial)"))
        XCTAssertTrue((AnonCLI.legacyProfileNotice("legacy-research") ?? "").hasPrefix("Deprecated: --profile legacy-research is"))
        XCTAssertTrue(help.contains("Deprecated: use --retain-full-dates or --retain-modified-dates"))
        XCTAssertTrue(AnonCLI.retainDatesNotice(shiftDates: nil).hasSuffix("applies the Full Dates Option."))
        XCTAssertTrue(AnonCLI.retainDatesNotice(shiftDates: 5).hasSuffix("applies the Modified Dates Option."))
    }

    private func writeFixture(in dir: URL) throws -> URL {
        let input = dir.appendingPathComponent("in.dcm")
        try DICOMFile.create(dataSet: fixture(), sopClassUID: "1.2.840.10008.5.1.4.1.1.7").write().write(to: input)
        return input
    }

    /// `--profile basic` (and no --profile) now runs the PS3.15 Basic Profile: it records
    /// Patient Identity Removed (0012,0062) YES and code 113100; `legacy-basic` does not.
    func testBasicIsThePS315ProfileAndLegacyBasicIsTheOldList() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try writeFixture(in: dir)
        func output(_ args: [String]) throws -> DataSet {
            let out = dir.appendingPathComponent("out-\(UUID().uuidString).dcm")
            try run([input.path, "-o", out.path] + args)
            return try DICOMFile.read(from: Data(contentsOf: out)).dataSet
        }
        for args in [[], ["--profile", "basic"], ["--profile", "ps315"]] {
            let ds = try output(args)
            XCTAssertEqual(ds.string(for: Tag(group: 0x0012, element: 0x0062)), "YES", "\(args)")
            XCTAssertEqual(ds.sequence(for: Tag(group: 0x0012, element: 0x0064))?.first?
                .string(for: .codeValue)?.trimmingCharacters(in: .whitespaces), "113100", "\(args)")
            XCTAssertNil(ds[Tag(group: 0x0009, element: 0x1001)], "Table E.1-1: private attributes X")
        }
        let legacy = try output(["--profile", "legacy-basic"])
        XCTAssertNil(legacy[Tag(group: 0x0012, element: 0x0062)])
        XCTAssertEqual(legacy.string(for: .patientName)?.trimmingCharacters(in: .whitespaces), "ANONYMOUS")
        // --keep is still a legacy-only option.
        XCTAssertThrowsError(try output(["--profile", "basic", "--keep", "Modality"]))
        XCTAssertNoThrow(try output(["--profile", "legacy-basic", "--keep", "Modality"]))
    }

    /// --retain-dates still works (deprecated): Full Dates without --shift-dates.
    func testRetainDatesStillSelectsFullDates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try writeFixture(in: dir), out = dir.appendingPathComponent("out.dcm")
        try run([input.path, "-o", out.path, "--retain-dates"])
        let ds = try DICOMFile.read(from: Data(contentsOf: out)).dataSet
        XCTAssertEqual(ds.string(for: .studyDate), "20240315")
        let codes = (ds.sequence(for: Tag(group: 0x0012, element: 0x0064)) ?? []).compactMap {
            $0.string(for: .codeValue)?.trimmingCharacters(in: .whitespaces)
        }
        XCTAssertEqual(codes, ["113100", "113106"])
    }

    /// D202: every `dicom-anon` command in the DICOMKit script templates parses and
    /// names the PS3.15 Basic Profile (`--profile strict` did not exist).
    func testScriptTemplatesUseExistingProfiles() throws {
        var seen = 0
        for name in ["workflow", "pipeline", "query", "archive", "anonymize"] {
            let template = try TemplateGenerator().generate(templateName: name)
            for line in template.split(separator: "\n") {
                let words = line.split(separator: " ").map(String.init)
                guard words.first == "dicom-anon" else { continue }
                seen += 1
                let command = try XCTUnwrap(DICOMAnon.parseAsRoot(Array(words.dropFirst())) as? DICOMAnon, line.description)
                XCTAssertEqual(AnonCLI.resolveProfile(command.profile), .ps315, "\(name): \(line)")
            }
        }
        XCTAssertEqual(seen, 3)
    }
}

// MARK: - D159 Clean Structured Content, Clean Recognizable Visual Features (PS3.15 2026a E.3.4, E.3.2)

extension AnonOptionContractTests {

    func testCleanStructuredContentAndVisualFeaturesFlags() {
        XCTAssertTrue(help.contains("PS3.15 Clean Structured Content Option"))
        XCTAssertTrue(help.contains("PS3.15 Clean Recognizable Visual Features Option"))
        var flags = AnonCLI.PS315Flags(); flags.cleanStructuredContent = true
        XCTAssertEqual(AnonCLI.options(flags: flags, shiftDates: nil).methodCodes.last?.codeValue, "113104")
        XCTAssertEqual(AnonCLI.options(flags: flags, shiftDates: nil).methodCodes.last?.meaning,
                       "Clean Structured Content Option")
        flags.cleanRecognizableVisualFeatures = true
        XCTAssertEqual(flags.setFlags, ["--clean-structured-content", "--clean-recognizable-visual-features"])
        XCTAssertThrowsError(try AnonCLI.validate(profile: "legacy-basic", flags: flags, shiftDates: nil,
                                                  regenerateUids: false, keep: [], redactRegions: ["0,0,1,1"]))
    }

    /// PS3.15 E.3.2: no detector, so the Option needs the operator's regions; refused without.
    func testVisualFeaturesWithoutRegionIsRefusedCitingE32() throws {
        var flags = AnonCLI.PS315Flags(); flags.cleanRecognizableVisualFeatures = true
        XCTAssertThrowsError(try AnonCLI.validate(profile: "ps315", flags: flags, shiftDates: nil,
                                                  regenerateUids: false, keep: [])) { error in
            XCTAssertTrue(error.localizedDescription.contains("PS3.15 E.3.2"))
        }
        XCTAssertNoThrow(try AnonCLI.validate(profile: "ps315", flags: flags, shiftDates: nil,
                                              regenerateUids: false, keep: [], redactRegions: ["0,0,4,4"]))
        // Exit status 1 (a failure, not an ArgumentParser usage error).
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("in.dcm")
        try DICOMFile.create(dataSet: imageFixture(), sopClassUID: "1.2.840.10008.5.1.4.1.1.7").write().write(to: input)
        do {
            try run([input.path, "-o", dir.appendingPathComponent("out.dcm").path, "--clean-recognizable-visual-features"])
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(DICOMAnon.exitCode(for: error), .failure)
            XCTAssertEqual(DICOMAnon.exitCode(for: error).rawValue, 1)
        }
    }

    private func imageFixture() -> DataSet {
        var ds = DataSet()
        ds.setString("DOE^JOHN", for: .patientName, vr: .PN)
        ds.setString("1.2.3.4.5.6.7.8.9", for: .sopInstanceUID, vr: .UI)
        ds.setUInt16(8, for: .rows)
        ds.setUInt16(8, for: .columns)
        ds.setUInt16(8, for: .bitsAllocated)
        ds.setUInt16(8, for: .bitsStored)
        ds.setUInt16(7, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: Data(repeating: 200, count: 64))
        return ds
    }

    /// The regions are blanked, (0028,0302) NO and 113102 recorded after 113100; no Clean
    /// Pixel Data claim (113101, Burned In Annotation) is made for them.
    func testVisualFeaturesEndToEnd() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("in.dcm"), output = dir.appendingPathComponent("out.dcm")
        try DICOMFile.create(dataSet: imageFixture(), sopClassUID: "1.2.840.10008.5.1.4.1.1.7").write().write(to: input)
        try run([input.path, "-o", output.path, "--clean-recognizable-visual-features", "--redact-region", "0,0,8,2"])
        let ds = try DICOMFile.read(from: Data(contentsOf: output)).dataSet
        XCTAssertEqual(ds.string(for: .recognizableVisualFeatures)?.trimmingCharacters(in: .whitespaces), "NO")
        XCTAssertNil(ds[.burnedInAnnotation])
        let codes = (ds.sequence(for: Tag(group: 0x0012, element: 0x0064)) ?? []).compactMap {
            $0.string(for: .codeValue)?.trimmingCharacters(in: .whitespaces)
        }
        XCTAssertEqual(codes, ["113100", "113102"])
        let pixels = try XCTUnwrap(ds[.pixelData]?.valueData)
        XCTAssertEqual(pixels[0], 0)
        XCTAssertEqual(pixels[16], 200)
    }

    /// --clean-structured-content: Table E.3.4-1 Accession Number (X) goes, an unlisted
    /// concept stays; 113104 recorded.
    func testCleanStructuredContentEndToEnd() throws {
        func item(_ code: String, _ meaning: String, _ text: String) -> SequenceItem {
            var concept = DataSet()
            concept.setString(code, for: .codeValue, vr: .SH)
            concept.setString("DCM", for: .codingSchemeDesignator, vr: .SH)
            concept.setString(meaning, for: .codeMeaning, vr: .LO)
            var ds = DataSet()
            ds.setString("TEXT", for: .valueType, vr: .CS)
            ds.setSequence([SequenceItem(elements: concept.tags.compactMap { concept[$0] })], for: .conceptNameCodeSequence)
            ds.setString(text, for: .textValue, vr: .UT)
            return SequenceItem(elements: ds.tags.compactMap { ds[$0] })
        }
        var sr = DataSet()
        sr.setString("DOE^JOHN", for: .patientName, vr: .PN)
        sr.setString("1.2.3.4.5.6.7.8.9", for: .sopInstanceUID, vr: .UI)
        sr.setSequence([item("121022", "Accession Number", "ACC1"), item("121073", "Impression", "Stable")],
                       for: .contentSequence)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("in.dcm"), output = dir.appendingPathComponent("out.dcm")
        try DICOMFile.create(dataSet: sr, sopClassUID: "1.2.840.10008.5.1.4.1.1.88.11").write().write(to: input)
        try run([input.path, "-o", output.path, "--clean-structured-content"])
        let ds = try DICOMFile.read(from: Data(contentsOf: output)).dataSet
        let texts = (ds.sequence(for: .contentSequence) ?? []).compactMap {
            $0.string(for: .textValue)?.trimmingCharacters(in: .whitespaces)
        }
        XCTAssertEqual(texts, ["Stable"])
        let codes = (ds.sequence(for: Tag(group: 0x0012, element: 0x0064)) ?? []).compactMap {
            $0.string(for: .codeValue)?.trimmingCharacters(in: .whitespaces)
        }
        XCTAssertEqual(codes, ["113100", "113104"])

        // Without the Option: Table E.1-1 Basic D on Content Sequence (0040,A730) reaches all
        // of its contents (E.1.1), so both Content Items stay with their Text Value replaced (D236).
        let basicOut = dir.appendingPathComponent("basic.dcm")
        try run([input.path, "-o", basicOut.path])
        let basic = try DICOMFile.read(from: Data(contentsOf: basicOut)).dataSet
        XCTAssertEqual((basic.sequence(for: .contentSequence) ?? []).compactMap {
            $0.string(for: .textValue)?.trimmingCharacters(in: .whitespaces)
        }, ["ANONYMIZED", "ANONYMIZED"])
    }
}
