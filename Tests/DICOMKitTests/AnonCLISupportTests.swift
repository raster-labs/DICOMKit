// NEMA-verified: 2026a, checked 2026-10-06 — pins the rules lifted from dicom-anon (D275): profile aliases (ps315 / basic = the PS3.15 2026a Basic Application Level Confidentiality Profile, legacy-* not Annex E), E.3.6 Full Dates / Modified Dates exclusive, E.3.2 regions required, Table E.1-1a action codes D Z X C U in the report, PS3.10 2026a Table 7.1-1 (0002,0003) = (0008,0018)
import XCTest
import DICOMCore
import DICOMDictionary
import DICOMKit

/// `AnonCLI` in DICOMKit (lifted from the dicom-anon CLI, D275). The texts are the
/// CLI's and must not drift (CLI parity; DICOMStudio's WorkshopAnonCLI mirrors them).
final class AnonCLISupportTests: XCTestCase {

    func test_profileAliases_resolve() {
        XCTAssertEqual(AnonCLI.defaultProfile, "ps315")
        XCTAssertEqual(AnonCLI.resolveProfile("ps315"), .ps315)
        XCTAssertEqual(AnonCLI.resolveProfile("BASIC"), .ps315)
        XCTAssertEqual(AnonCLI.resolveProfile("legacy-basic"), .legacyBasic)
        XCTAssertEqual(AnonCLI.resolveProfile("clinical-trial"), .legacyClinicalTrial)
        XCTAssertEqual(AnonCLI.resolveProfile("research"), .legacyResearch)
        XCTAssertNil(AnonCLI.resolveProfile("strict"))
        XCTAssertNil(AnonCLI.Profile.ps315.legacyProfile)
        guard case .basic? = AnonCLI.Profile.legacyBasic.legacyProfile else { return XCTFail("legacy-basic → .basic") }
        XCTAssertEqual(AnonCLI.legacyProfiles, ["legacy-basic", "legacy-clinical-trial", "legacy-research",
                                                "clinical-trial", "clinicaltrial", "research"])
    }

    func test_notices_nameTheStandardProfile() {
        XCTAssertNil(AnonCLI.legacyProfileNotice("ps315"))
        XCTAssertEqual(AnonCLI.legacyProfileNotice("basic"),
                       "Note: --profile basic is the PS3.15 Basic Application Level Confidentiality Profile "
                       + "(same as ps315, PS3.15 Table E.1-1). The former basic attribute list is --profile legacy-basic.")
        XCTAssertEqual(AnonCLI.legacyProfileNotice("research"),
                       "Deprecated: --profile research (now legacy-research) is a legacy attribute list, not a PS3.15 "
                       + "Annex E profile; it records no Patient Identity Removed (0012,0062). Use --profile ps315 "
                       + "(PS3.15 Basic Application Level Confidentiality Profile, Table E.1-1).")
        XCTAssertTrue(AnonCLI.retainDatesNotice(shiftDates: nil).hasSuffix("This run applies the Full Dates Option."))
        XCTAssertTrue(AnonCLI.retainDatesNotice(shiftDates: 3).hasSuffix("This run applies the Modified Dates Option."))
    }

    func test_validationError_localizedDescriptionIsTheMessage() {
        var flags = AnonCLI.PS315Flags(); flags.cleanRecognizableVisualFeatures = true
        XCTAssertThrowsError(try AnonCLI.validate(profile: "ps315", flags: flags, shiftDates: nil,
                                                  regenerateUids: false, keep: [])) { error in
            XCTAssertEqual(error.localizedDescription, AnonCLI.visualFeaturesNeedRegions)
            XCTAssertTrue(error.localizedDescription.contains("PS3.15 E.3.2"))
        }
    }

    func test_validate_rejectsContradictoryOptions() {
        func message(_ body: () throws -> Void) -> String? {
            do { try body(); return nil } catch let error as AnonCLI.ValidationError { return error.message } catch { return "\(error)" }
        }
        XCTAssertEqual(message { try AnonCLI.validate(profile: "strict", flags: .init(), shiftDates: nil,
                                                       regenerateUids: false, keep: []) },
                       "Unknown --profile 'strict': use ps315 (or its alias basic), or the deprecated legacy-basic, "
                       + "legacy-clinical-trial, legacy-research")
        XCTAssertEqual(message { try AnonCLI.validate(profile: "legacy-basic", flags: .init(retainUids: true),
                                                       shiftDates: nil, regenerateUids: false, keep: []) },
                       "PS3.15 Annex E Option flags apply only to --profile ps315: --retain-uids")
        XCTAssertNotNil(message { try AnonCLI.validate(profile: "ps315", flags: .init(retainFullDates: true, retainModifiedDates: true),
                                                        shiftDates: 5, regenerateUids: false, keep: []) }, "E.3.6: mutually exclusive")
        XCTAssertNotNil(message { try AnonCLI.validate(profile: "ps315", flags: .init(retainModifiedDates: true),
                                                        shiftDates: nil, regenerateUids: false, keep: []) })
        XCTAssertNotNil(message { try AnonCLI.validate(profile: "ps315", flags: .init(), shiftDates: 5,
                                                        regenerateUids: false, keep: []) })
        XCTAssertEqual(message { try AnonCLI.validate(profile: "ps315", flags: .init(retainUids: true), shiftDates: nil,
                                                       regenerateUids: true, keep: []) },
                       "--regenerate-uids contradicts --retain-uids (Retain UIDs Option)")
        XCTAssertNotNil(message { try AnonCLI.validate(profile: "ps315", flags: .init(), shiftDates: nil,
                                                        regenerateUids: false, keep: ["PatientAge"]) })
        XCTAssertEqual(message { try AnonCLI.validate(profile: "ps315", flags: .init(cleanRecognizableVisualFeatures: true),
                                                       shiftDates: nil, regenerateUids: false, keep: []) },
                       AnonCLI.visualFeaturesNeedRegions)
        XCTAssertNil(message { try AnonCLI.validate(profile: "ps315", flags: .init(retainModifiedDates: true), shiftDates: 5,
                                                     regenerateUids: false, keep: []) })
        XCTAssertNil(message { try AnonCLI.validate(profile: "legacy-basic", flags: .init(), shiftDates: 10,
                                                     regenerateUids: true, keep: ["PatientAge"]) })
        XCTAssertEqual(AnonCLI.PS315Flags(retainSafePrivate: true, cleanGraphics: true).setFlags,
                       ["--retain-safe-private", "--clean-graphics"])
    }

    func test_options_mapFlagsOntoTheEngine() {
        let options = AnonCLI.options(flags: .init(retainModifiedDates: true, retainDevice: true, cleanDescriptors: true),
                                      shiftDates: 10)
        XCTAssertTrue(options.retainLongitudinalTemporal)
        XCTAssertEqual(options.dateOffsetDays, 10)
        XCTAssertTrue(options.retainDeviceIdentity)
        XCTAssertTrue(options.cleanDescriptors)
        XCTAssertFalse(options.retainUIDs)
        XCTAssertEqual(AnonCLI.parseTag("PatientAge"), Tag(group: 0x0010, element: 0x1010))
        XCTAssertEqual(AnonCLI.parseTag("(0008,0060)"), .modality)
    }

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
        ds.setString("CREATOR", for: Tag(group: 0x0009, element: 0x0010), vr: .LO)
        ds.setString("secret", for: Tag(group: 0x0009, element: 0x1001), vr: .LO)
        return ds
    }

    func test_actionReport_usesTableE11aCodes_andAuditLogCarriesNoValues() {
        let source = fixture()
        let file = DICOMFile.create(dataSet: source, sopClassUID: "1.2.840.10008.5.1.4.1.1.7")
        let (out, _, _) = Anonymizer(profile: .basic).deidentify(file: file, options: .basic)
        let actions = AnonCLI.attributeActions(before: source, after: out.dataSet, options: .basic)
        let byTag = Dictionary(uniqueKeysWithValues: actions.map { ($0.tag, $0) })
        XCTAssertEqual(byTag[.patientName], AnonCLI.AttributeAction(tag: .patientName, code: "Z", name: "Patient's Name"))
        XCTAssertEqual(byTag[.patientID]?.code, "Z")
        XCTAssertEqual(byTag[.sopInstanceUID]?.code, "U")
        XCTAssertEqual(byTag[.institutionName]?.code, "X")
        XCTAssertEqual(byTag[Tag(group: 0x0009, element: 0x1001)]?.name, "Private Data Element")
        XCTAssertEqual(byTag[Tag(group: 0x0012, element: 0x0062)]?.code, "recorded")
        XCTAssertNil(byTag[.modality], "unchanged attributes are not listed")
        let lines = AnonCLI.actionLines(path: "f.dcm", actions: actions)
        XCTAssertTrue(lines.hasPrefix("\nAttribute actions for f.dcm (PS3.15 Table E.1-1a: D dummy, Z zero length, "
                                      + "X removed, C cleaned, U new UID):\n"))
        XCTAssertTrue(lines.contains("  Z        (0010,0010) Patient's Name\n"))

        let text = AnonCLI.auditLogText(profileDescription: ["Basic Application Confidentiality Profile"],
                                        files: [("a.dcm", [byTag[.patientName]!])], generated: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(text.contains("[1970-01-01T00:00:00Z] a.dcm - Z - (0010,0010) Patient's Name\n"))
        XCTAssertFalse(text.contains("Doe"))
    }

    func test_fileMetaMediaStorageSOPInstanceUID_followsTheDataSet() throws {
        // PS3.10 Table 7.1-1: (0002,0003) is the SOP Instance UID of the data set.
        var ds = fixture()
        let file = DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.7")
        ds.setString("1.2.3.4.5.6.7.8.10", for: .sopInstanceUID, vr: .UI)
        let replaced = DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: ds)
        XCTAssertEqual(replaced.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID), "1.2.3.4.5.6.7.8.9")
        let synced = AnonCLI.syncingMediaStorageSOPInstanceUID(replaced)
        XCTAssertEqual(synced.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID), "1.2.3.4.5.6.7.8.10")
    }
}
