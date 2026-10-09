import XCTest
import DICOMCore
import DICOMKit
@testable import dicom_gateway

/// The DICOM side of the HL7 v2 / FHIR mappings, pinned to PS3.3 / PS3.5 2026a:
/// PN components and component groups (PS3.5 Table 6.2-1, 6.2.1), DA / TM forms
/// (Table 6.2-1), Patient's Sex Enumerated Values M, F, O (PS3.3 Table C.7-1), UID syntax
/// (PS3.5 9.1) and Timezone Offset From UTC "&ZZXX" (PS3.3 C.12.1.1.8).
final class DICOMValueMappingTests: XCTestCase {

    // MARK: PN

    func testHL7XPNSwapsSuffixAndPrefixIntoDICOMOrder() {
        XCTAssertEqual(DICOMValueMapping.personName(fromHL7XPN: "DOE^JOHN^A^JR^DR"), "DOE^JOHN^A^DR^JR")
    }

    func testHL7XPNWithFourComponentsPutsSuffixInTheFifthDICOMComponent() {
        // XPN.4 is the suffix; in PN the 4th component is the prefix.
        XCTAssertEqual(DICOMValueMapping.personName(fromHL7XPN: "DOE^JOHN^A^JR"), "DOE^JOHN^A^^JR")
    }

    func testHL7XPNExtraComponentsAndTrailingEmptiesAreDropped() {
        XCTAssertEqual(DICOMValueMapping.personName(fromHL7XPN: "DOE^JOHN^^^^^L"), "DOE^JOHN")
        XCTAssertEqual(DICOMValueMapping.personName(fromHL7XPN: "DOE^JOHN~ROE^JANE"), "DOE^JOHN")
        let pn = DICOMValueMapping.personName(fromHL7XPN: "A^B^C^D^E^F^G")
        XCTAssertLessThanOrEqual(pn.filter { $0 == "^" }.count, 4, "PN allows at most four component delimiters")
    }

    func testDICOMPNToXPNUsesFirstComponentGroupOnly() {
        XCTAssertEqual(DICOMValueMapping.hl7XPN(fromDICOM: "Yamada^Tarou=山田^太郎=やまだ^たろう"), "Yamada^Tarou")
        XCTAssertEqual(DICOMValueMapping.hl7XPN(fromDICOM: "DOE^JOHN^A^DR"), "DOE^JOHN^A^^DR")
        XCTAssertEqual(DICOMValueMapping.hl7XPN(fromDICOM: "DOE^JOHN^A^DR^JR"), "DOE^JOHN^A^JR^DR")
    }

    func testFHIRHumanNameMapsFurtherGivenNamesToMiddleName() {
        XCTAssertEqual(DICOMValueMapping.personName(fhirFamily: "Doe", given: ["John", "Paul"], prefix: ["Dr"], suffix: ["Jr"]),
                       "Doe^John^Paul^Dr^Jr")
        XCTAssertEqual(DICOMValueMapping.personName(fhirFamily: "Doe", given: ["John"]), "Doe^John")
    }

    // MARK: DA / TM

    func testHL7DatesGiveDAOnlyForAFullDate() {
        XCTAssertEqual(DICOMValueMapping.date(fromHL7: "19800515"), "19800515")
        XCTAssertEqual(DICOMValueMapping.date(fromHL7: "198005151230"), "19800515")
        XCTAssertNil(DICOMValueMapping.date(fromHL7: "1980"))
        XCTAssertNil(DICOMValueMapping.date(fromHL7: "198005"))
        XCTAssertNil(DICOMValueMapping.date(fromHL7: "19801315"))
    }

    func testHL7TimesGiveTMWithoutTheZone() {
        XCTAssertEqual(DICOMValueMapping.time(fromHL7: "20240115103000"), "103000")
        XCTAssertEqual(DICOMValueMapping.time(fromHL7: "202401151030"), "1030")
        XCTAssertEqual(DICOMValueMapping.time(fromHL7: "20240115103000.1234+0530"), "103000.1234")
        XCTAssertEqual(DICOMValueMapping.time(fromHL7: "20240115103000-0500"), "103000")
        XCTAssertNil(DICOMValueMapping.time(fromHL7: "20240115"))
        XCTAssertNil(DICOMValueMapping.time(fromHL7: "20240115256000"))
    }

    func testFHIRDatesAndTimes() {
        XCTAssertEqual(DICOMValueMapping.date(fromFHIR: "1980-05-15"), "19800515")
        XCTAssertNil(DICOMValueMapping.date(fromFHIR: "1980"))
        XCTAssertNil(DICOMValueMapping.date(fromFHIR: "1980-05"))
        XCTAssertEqual(DICOMValueMapping.date(fromFHIR: "2024-01-15T10:30:00+05:30"), "20240115")
        XCTAssertEqual(DICOMValueMapping.time(fromFHIR: "2024-01-15T10:30:00+05:30"), "103000")
        XCTAssertEqual(DICOMValueMapping.time(fromFHIR: "2024-01-15T10:30:00.123Z"), "103000.123")
        XCTAssertNil(DICOMValueMapping.time(fromFHIR: "2024-01-15"))
    }

    // MARK: Patient's Sex

    func testPatientSexIsAlwaysAnEnumeratedValueOrEmpty() {
        let enumerated: Set<String> = ["M", "F", "O", ""]   // PS3.3 Table C.7-1 (+ Type 2 empty)
        for code in ["M", "F", "O", "U", "A", "N", "", "m", "x"] {
            XCTAssertTrue(enumerated.contains(DICOMValueMapping.patientSex(fromHL7: code)), code)
        }
        XCTAssertEqual(DICOMValueMapping.patientSex(fromHL7: "U"), "")
        XCTAssertEqual(DICOMValueMapping.patientSex(fromHL7: "f"), "F")
        for g in ["male", "female", "other", "unknown", "x"] {
            XCTAssertTrue(enumerated.contains(DICOMValueMapping.patientSex(fromFHIR: g)), g)
        }
    }

    // MARK: Identifiers

    func testCXGivesPatientIDAndIssuer() {
        let r = DICOMValueMapping.patientID(fromHL7CX: "12345^^^HOSP&1.2.3&ISO^MR~999")
        XCTAssertEqual(r.id, "12345")
        XCTAssertEqual(r.issuer, "HOSP")
        XCTAssertNil(DICOMValueMapping.patientID(fromHL7CX: "12345").issuer)
    }

    func testEntityIdentifierAndUIDSyntax() {
        XCTAssertEqual(DICOMValueMapping.entityIdentifier(fromHL7EI: "ACC123^RIS"), "ACC123")
        XCTAssertTrue(DICOMValueMapping.isValidUID("1.2.840.10008.1.1"))
        XCTAssertFalse(DICOMValueMapping.isValidUID("1.02.3"), "leading zero (PS3.5 9.1)")
        XCTAssertFalse(DICOMValueMapping.isValidUID("1.2..3"))
        XCTAssertFalse(DICOMValueMapping.isValidUID(String(repeating: "1.", count: 40) + "1"), "over 64 characters")
        XCTAssertFalse(DICOMValueMapping.isValidUID("1.2.840.113619.DICOMKit"))
    }

    func testTimezoneOffsetKeepsMinutes() {
        XCTAssertEqual(DICOMValueMapping.timezoneOffsetFromUTC(secondsFromGMT: 19800), "+0530")
        XCTAssertEqual(DICOMValueMapping.timezoneOffsetFromUTC(secondsFromGMT: -12600), "-0330")
        XCTAssertEqual(DICOMValueMapping.timezoneOffsetFromUTC(secondsFromGMT: 0), "+0000")
    }

    // MARK: Converters end to end

    func testHL7ToDICOMWritesStandardValues() throws {
        let hl7 = "MSH|^~\\&|RIS|H|PACS|H|20240115103000||ORM^O01|1|P|2.5\r"
            + "PID|1||12345^^^HOSP^MR||DOE^JOHN^A^JR||1980|U\r"
            + "ORC|NW|ACC123^RIS\r"
            + "OBR|1||1.2.3.4^RIS|MRI^Brain|||202401151030\r"
        let message = try HL7Parser().parse(hl7)
        let file = try HL7ToDICOMConverter().convert(hl7Message: message)
        let ds = file.dataSet
        XCTAssertEqual(ds.string(for: .patientID), "12345")
        XCTAssertEqual(ds.string(for: .issuerOfPatientID), "HOSP")
        XCTAssertEqual(ds.string(for: .patientName), "DOE^JOHN^A^^JR")
        XCTAssertEqual(ds.string(for: .patientBirthDate) ?? "", "")
        XCTAssertEqual(ds.string(for: .patientSex) ?? "", "")
        XCTAssertEqual(ds.string(for: .accessionNumber), "ACC123")
        XCTAssertEqual(ds.string(for: .studyInstanceUID), "1.2.3.4")
        XCTAssertEqual(ds.string(for: .modality), "MR")
        XCTAssertEqual(ds.string(for: .studyDate), "20240115")
        XCTAssertEqual(ds.string(for: .studyTime), "1030")
        // UIDs and File Meta under DICOMKit's own root, not other arcs of 1.2.826.0.1.3680043.10
        let sop = try XCTUnwrap(ds.string(for: .sopInstanceUID))
        XCTAssertTrue(sop.hasPrefix(UIDGenerator.defaultRoot + "."), sop)
        XCTAssertEqual(file.fileMetaInformation.string(for: .implementationClassUID), DICOMFile.implementationClassUID)
    }

    func testADTTriggerEventIsNotDoublePrefixed() {
        XCTAssertEqual(DICOMToHL7Converter.adtTriggerEvent("A01"), "A01")
        XCTAssertEqual(DICOMToHL7Converter.adtTriggerEvent("01"), "A01")
    }
}
