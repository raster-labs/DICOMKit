import XCTest
import Foundation
import DICOMCore
import DICOMKit

/// Independently assembled wire fixtures prevent the writer's repairs from masking
/// malformed input. These are attribute-validation fixtures, not complete clinical IODs.
final class M2AttributeIntegrityTests: XCTestCase {
    private let sop = "1.2.840.10008.5.1.4.1.1.7"
    private let instance = "2.25.1234"

    private func le(_ value: UInt32, _ width: Int) -> Data {
        Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    private func element(_ tag: Tag, _ vr: String, _ value: Data, undefined: Bool = false) -> Data {
        var result = le(UInt32(tag.group), 2) + le(UInt32(tag.element), 2) + Data(vr.utf8)
        let longVR = ["OB", "OD", "OF", "OL", "OV", "OW", "SQ", "SV", "UC", "UN", "UR", "UT", "UV"].contains(vr)
        if longVR { result += Data([0, 0]) }
        result += le(undefined ? UInt32.max : UInt32(value.count), longVR ? 4 : 2)
        return result + value
    }
    private func text(_ tag: Tag, _ vr: String, _ value: String) -> Data {
        var data = Data(value.utf8)
        if data.count % 2 != 0 { data.append(vr == "UI" ? 0 : 32) }
        return element(tag, vr, data)
    }
    private func root() -> Data { text(.sopClassUID, "UI", sop) + text(.sopInstanceUID, "UI", instance) }
    private func file(_ body: Data = Data(), overrides: [Tag: Data] = [:], groupLength: Data? = nil) -> Data {
        let defaults: [(Tag, Data)] = [
            (.fileMetaInformationVersion, element(.fileMetaInformationVersion, "OB", Data([0, 1]))),
            (.mediaStorageSOPClassUID, text(.mediaStorageSOPClassUID, "UI", sop)),
            (.mediaStorageSOPInstanceUID, text(.mediaStorageSOPInstanceUID, "UI", instance)),
            (.transferSyntaxUID, text(.transferSyntaxUID, "UI", TransferSyntax.explicitVRLittleEndian.uid)),
            (.implementationClassUID, text(.implementationClassUID, "UI", "2.25.9876"))
        ]
        let meta = defaults.reduce(into: Data()) { $0 += overrides[$1.0] ?? $1.1 }
        return Data(repeating: 0, count: 128) + Data("DICM".utf8)
            + (groupLength ?? element(.fileMetaInformationGroupLength, "UL", le(UInt32(meta.count), 4)))
            + meta + root() + body
    }
    private func validate(_ data: Data, level: Int = 2) throws -> ValidationResult {
        try DICOMValidator(level: level, iod: nil, force: false).validate(data: data, filePath: "synthetic-m2.dcm")
    }
    private func sequence(_ items: [Data], undefined: Bool) -> Data {
        var bytes = Data()
        for item in items {
            bytes += le(0xFFFE, 2) + le(0xE000, 2) + le(undefined ? UInt32.max : UInt32(item.count), 4) + item
            if undefined { bytes += le(0xFFFE, 2) + le(0xE00D, 2) + le(0, 4) }
        }
        if undefined { bytes += le(0xFFFE, 2) + le(0xE0DD, 2) + le(0, 4) }
        return element(.referencedStudySequence, "SQ", bytes, undefined: undefined)
    }

    func testCorrectMetaAndForwardCompatibleVersionPassAtBothLevels() throws {
        for level in [1, 2] {
            XCTAssertTrue(try validate(file(), level: level).isValid)
            let version = element(.fileMetaInformationVersion, "OB", Data([0x80, 0x81]))
            XCTAssertTrue(try validate(file(overrides: [.fileMetaInformationVersion: version]), level: level).isValid)
        }
    }

    func testEachRequiredMetaValueRejectsEmptyAndWrongVRAtBothLevels() throws {
        let required: [(Tag, String)] = [(.fileMetaInformationGroupLength, "UL"), (.fileMetaInformationVersion, "OB"),
            (.mediaStorageSOPClassUID, "UI"), (.mediaStorageSOPInstanceUID, "UI"), (.transferSyntaxUID, "UI"), (.implementationClassUID, "UI")]
        for (tag, vr) in required {
            for wire in [element(tag, vr, Data()), text(tag, "LO", "invalid")] {
                let data = tag == .fileMetaInformationGroupLength ? file(groupLength: wire) : file(overrides: [tag: wire])
                for level in [1, 2] {
                    let result = try validate(data, level: level)
                    XCTAssertFalse(result.isValid, "\(tag) level \(level)")
                    XCTAssertTrue(result.errors.contains { $0.tag == tag } || result.errors.contains { $0.message.contains("parse") })
                }
            }
        }
    }

    func testMalformedMetaUIDsAndVersionReject() throws {
        for tag in [Tag.mediaStorageSOPClassUID, .mediaStorageSOPInstanceUID, .transferSyntaxUID, .implementationClassUID] {
            for uid in ["1.02.3", "1..2", "1.2\\1.3", "١.٢"] {
                XCTAssertFalse(try validate(file(overrides: [tag: text(tag, "UI", uid)]), level: 1).isValid, "\(tag) \(uid)")
            }
        }
        for bytes: [UInt8] in [[0, 0], [1, 0], [0, 1, 0, 0]] {
            XCTAssertFalse(try validate(file(overrides: [.fileMetaInformationVersion: element(.fileMetaInformationVersion, "OB", Data(bytes))]), level: 1).isValid)
        }
    }

    func testEncodedGroupLengthAndIdentityMismatchesRejectAtBothLevels() throws {
        for level in [1, 2] {
            let length = try validate(file(groupLength: element(.fileMetaInformationGroupLength, "UL", le(1, 4))), level: level)
            XCTAssertTrue(length.errors.contains { $0.tag == .fileMetaInformationGroupLength && $0.message.contains("encoded group") })
            for tag in [Tag.mediaStorageSOPClassUID, .mediaStorageSOPInstanceUID] {
                let r = try validate(file(overrides: [tag: text(tag, "UI", "2.25.222222222")]), level: level)
                XCTAssertTrue(r.errors.contains { $0.tag == tag && $0.message.contains("does not match dataset") })
            }
        }
    }

    func testEveryNestedItemCheckedWithoutRootRequirements() throws {
        for undefined in [false, true] {
            let valid = sequence([text(.patientAge, "AS", "012Y"), sequence([text(.studyDate, "DA", "20240229")], undefined: undefined)], undefined: undefined)
            XCTAssertTrue(try validate(file(valid)).isValid)
            let invalid = sequence([text(.patientAge, "AS", "Y123"), sequence([
                text(.studyDate, "DA", "20260231") + text(.imageType, "CS", "ORIGINAL") + text(.rows, "LO", "512")
            ], undefined: undefined)], undefined: undefined)
            let result = try validate(file(invalid))
            XCTAssertFalse(result.isValid)
            for tag in [Tag.patientAge, .studyDate, .imageType, .rows] {
                XCTAssertTrue(result.errors.contains { $0.tag == tag && $0.message.contains("(0008,1110)[") }, "\(tag): \(result.errors.map(\.message))")
            }
            XCTAssertTrue(result.errors.contains { $0.tag == .studyDate && $0.message.contains("[2]/(0008,1110)[1]") })
            XCTAssertFalse(result.errors.contains { $0.message.contains("Missing required Type 1") })
        }
    }

    func testCalendarAndDTBoundaries() throws {
        for date in ["20240229", "20000229", "20261024"] {
            XCTAssertTrue(try validate(file(text(.studyDate, "DA", date))).isValid, date)
        }
        for date in ["20260231", "20230229", "19000229", "20260431"] {
            XCTAssertFalse(try validate(file(text(.studyDate, "DA", date))).isValid, date)
        }
        let tag = Tag(group: 0x0008, element: 0x002A)
        for dt in ["2026", "202610", "20261024", "2026102410", "202610241030", "20261024103000.123456+0530"] {
            XCTAssertTrue(try validate(file(text(tag, "DT", dt))).isValid, dt)
        }
        for dt in ["20269999112233", "20230229103000", "20261024103000.1234567", "202610241030+0530.1", "2026-10-24T10:30:00Z", "20261024103000+1460"] {
            XCTAssertFalse(try validate(file(text(tag, "DT", dt))).isValid, dt)
        }
    }

    func testWrongVRAndReportsAgreeWithoutStrict() throws {
        let result = try validate(file(text(.rows, "LO", "512")))
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.tag == .rows && $0.message.contains("VR LO") && $0.message.contains("US") })
        for strict in [false, true] {
            let report = ValidationReport(results: [result], detailed: true, strict: strict)
            XCTAssertEqual(report.exitCode(), 1)
            XCTAssertTrue(try report.render(format: .text).contains("INVALID"))
            let json = try JSONSerialization.jsonObject(with: Data(report.render(format: .json).utf8)) as! [String: Any]
            XCTAssertEqual((json["files"] as! [[String: Any]])[0]["isValid"] as? Bool, false)
        }
        XCTAssertTrue(try validate(file(element(.rows, "US", le(512, 2)))).isValid)
        for vr in ["US", "SS"] {
            XCTAssertTrue(try validate(file(element(.smallestImagePixelValue, vr, le(1, 2)))).isValid)
        }
    }

    func testUndecodableDefaultAEAndStoredGrammarReject() throws {
        let tag = Tag(group: 0x0008, element: 0x0054)
        XCTAssertFalse(try validate(file(text(tag, "AE", "Müller"))).isValid)
        XCTAssertFalse(try validate(file(text(tag, "AE", "  "))).isValid)
        XCTAssertFalse(try validate(file(text(.pixelSpacing, "DS", "1..2\\3"))).isValid)
    }

    func testWirePaddingAndEmptyValueBoundaries() throws {
        XCTAssertFalse(try validate(file(element(.studyDate, "DA", Data("20261024 ".utf8)))).isValid)
        let uid64 = "2.25." + String(repeating: "1", count: 59)
        let meta = element(.implementationClassUID, "UI", Data(uid64.utf8) + Data([0]))
        XCTAssertFalse(try validate(file(overrides: [.implementationClassUID: meta]), level: 1).isValid)
        XCTAssertTrue(try validate(file(text(.patientBirthDate, "DA", "\\"))).isValid)
        for (count, valid) in [(63, true), (64, false)] {
            XCTAssertEqual(try validate(file(text(.patientName, "PN", String(repeating: "A", count: count) + "=X"))).isValid, valid)
        }
    }

    func testMalformedNumericValueLengthFails() throws {
        let result = try validate(file(element(.rows, "US", Data([1, 0, 2]))))
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.tag == .rows })
    }
}
