import XCTest
import Foundation
import DICOMCore
import DICOMKit

/// D140-D143 (2026-10-01): DICOMKit DICOMValidator against the 2026a text.
/// - D140: Content Creator's Name (0070,0084) is Type 3 (PS3.3 Table 10.9.3-1, included by
///   Table 10-12) — never reported as missing.
/// - D141: IOD message prefixes are PS3.6 Table A-1 SOP Class names.
/// - D142: level 2 checks PS3.5 Table 6.2-1 lengths / repertoires, PS3.5 6.2.1 PN component
///   groups and the PS3.6 Table 6-1 VM; each DA/TM/UI problem is reported once.
/// - D143: the root Concept Name Code Sequence is Type 1C (PS3.3 Table C.17-5).
final class ValidatorStandardTests: XCTestCase {

    private func validate(_ ds: DataSet, sopClassUID: String, level: Int = 3) throws -> ValidationResult {
        let file = DICOMFile.create(dataSet: ds, sopClassUID: sopClassUID,
                                    sopInstanceUID: ds.string(for: .sopInstanceUID) ?? "1.2.3.4.5.6",
                                    transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid)
        return try DICOMValidator(level: level, iod: nil, force: false).validate(data: try file.write(), filePath: "t.dcm")
    }

    private func base(_ sop: String) -> DataSet {
        var ds = DataSet()
        ds.setString(sop, for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6", for: .sopInstanceUID, vr: .UI)
        return ds
    }

    private func messages(_ r: ValidationResult) -> [String] { r.errors.map(\.message) }

    // MARK: D140

    func testContentCreatorsNameIsNotRequiredInPresentationStates() throws {
        for sop in ["1.2.840.10008.5.1.4.1.1.11.1", "1.2.840.10008.5.1.4.1.1.11.3"] {
            let r = try validate(base(sop), sopClassUID: sop)
            XCTAssertFalse(r.errors.contains { $0.tag == .contentCreatorName }, "\(sop): \(messages(r))")
            XCTAssertTrue(r.errors.contains { $0.tag == .contentDescription && $0.message.contains("Missing Type 2") },
                          "Content Description stays Type 2 (Table 10-12)")
        }
    }

    // MARK: D141

    func testIODPrefixesArePS36TableA1Names() throws {
        let expected = [
            "1.2.840.10008.5.1.4.1.1.1": "Computed Radiography Image Storage",
            "1.2.840.10008.5.1.4.1.1.6.1": "Ultrasound Image Storage",
            "1.2.840.10008.5.1.4.1.1.11.1": "Grayscale Softcopy Presentation State Storage",
            "1.2.840.10008.5.1.4.1.1.11.3": "Pseudo-Color Softcopy Presentation State Storage",
            "1.2.840.10008.5.1.4.1.1.88.59": "Key Object Selection Document Storage",
            "1.2.840.10008.5.1.4.1.1.88.11": "Basic Text SR Storage",
            "1.2.840.10008.5.1.4.1.1.88.33": "Comprehensive SR Storage",
        ]
        for (sop, name) in expected {
            let r = try validate(base(sop), sopClassUID: sop)
            let iodMessages = messages(r).filter { $0.contains("Missing Type") }
            XCTAssertFalse(iodMessages.isEmpty, sop)
            XCTAssertTrue(iodMessages.allSatisfy { $0.hasPrefix("\(name):") }, "\(sop): \(iodMessages.prefix(2))")
        }
    }

    // MARK: D143

    func testRootConceptNameCodeSequenceIsType1C() throws {
        let sop = "1.2.840.10008.5.1.4.1.1.88.11"
        let r = try validate(base(sop), sopClassUID: sop)
        let m = try XCTUnwrap(r.errors.first { $0.tag == .conceptNameCodeSequence }?.message)
        XCTAssertTrue(m.contains("Missing Type 1C attribute Concept Name Code Sequence (required for the Root Content Item)"), m)
        XCTAssertTrue(m.contains("Table C.17-5") && m.contains("PS3.5 7.4.2"), m)
        var ds = base(sop)
        ds.setSequence([], for: .conceptNameCodeSequence)
        let empty = try validate(ds, sopClassUID: sop)
        XCTAssertTrue(empty.errors.contains { $0.tag == .conceptNameCodeSequence && $0.message.contains("Type 1C attribute Concept Name Code Sequence is empty") })
    }

    // MARK: D142

    private func level2(_ build: (inout DataSet) -> Void) throws -> ValidationResult {
        var ds = base("1.2.840.10008.5.1.4.1.1.7")
        build(&ds)
        return try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.7", level: 2)
    }

    /// PS3.5 Table 6.2-1: LO 64 chars, SH 16 chars, CS 16 bytes, DS 16 bytes, IS 12 bytes,
    /// PN 64 chars per component group.
    func testMaximumLengthsAreErrors() throws {
        let cases: [(Tag, VR, String, String)] = [
            (.studyDescription, .LO, String(repeating: "A", count: 70), "allows at most 64 chars"),
            (.stationName, .SH, String(repeating: "A", count: 20), "allows at most 16 chars"),
            (.bodyPartExamined, .CS, String(repeating: "A", count: 20), "allows at most 16 bytes"),
            (.sliceThickness, .DS, "1.00000000000000001", "allows at most 16 bytes"),
            (.seriesNumber, .IS, "1234567890123", "allows at most 12 bytes"),
            (.patientName, .PN, String(repeating: "A", count: 70), "at most 64 chars per component group"),
        ]
        for (tag, vr, value, phrase) in cases {
            let r = try level2 { $0.setString(value, for: tag, vr: vr) }
            XCTAssertTrue(r.errors.contains { $0.tag == tag && $0.message.contains(phrase) && $0.message.contains("PS3.5 Table 6.2-1") },
                          "\(vr): \(messages(r))")
            let ok = try level2 { $0.setString(String(value.prefix(vr == .IS ? 12 : 16)), for: tag, vr: vr) }
            XCTAssertFalse(ok.errors.contains { $0.tag == tag && $0.message.contains("at most") }, "\(vr): \(messages(ok))")
        }
    }

    func testRepertoireViolationsAreErrors() throws {
        let cs = try level2 { $0.setString("ax", for: .bodyPartExamined, vr: .CS) }
        XCTAssertTrue(cs.errors.contains { $0.tag == .bodyPartExamined && $0.message.contains("outside the CS character repertoire") },
                      "\(messages(cs))")
        XCTAssertFalse(cs.warnings.contains { $0.message.contains("should be uppercase") })
        let ds = try level2 { $0.setString("1,5", for: .sliceThickness, vr: .DS) }
        XCTAssertTrue(ds.errors.contains { $0.tag == .sliceThickness && $0.message.contains("DS character repertoire") }, "\(messages(ds))")
        let lo = try level2 { $0.setString("A\u{07}B", for: .studyDescription, vr: .LO) }
        XCTAssertTrue(lo.errors.contains { $0.tag == .studyDescription && $0.message.contains("0x07") }, "\(messages(lo))")
        let good = try level2 { $0.setString("HEAD_NECK 2", for: .bodyPartExamined, vr: .CS) }
        XCTAssertFalse(good.errors.contains { $0.tag == .bodyPartExamined }, "\(messages(good))")
    }

    /// PS3.6 Table 6-1 VM: Image Orientation (Patient) 6, Pixel Spacing 2, Modality 1, Image Type 2-n.
    func testVMAgainstPS36() throws {
        let r = try level2 {
            $0.setStrings(["1", "0", "0", "0", "1"], for: .imageOrientationPatient, vr: .DS)
            $0.setStrings(["0.5", "0.5", "0.5"], for: .pixelSpacing, vr: .DS)
            $0.setStrings(["CT", "MR"], for: .modality, vr: .CS)
            $0.setStrings(["ORIGINAL"], for: .imageType, vr: .CS)
        }
        for (tag, vm) in [(Tag.imageOrientationPatient, "VM 6"), (.pixelSpacing, "VM 2"), (.modality, "VM 1"), (.imageType, "VM 2-n")] {
            XCTAssertTrue(r.errors.contains { $0.tag == tag && $0.message.contains("PS3.6 Table 6-1 gives \(vm)") }, "\(tag): \(messages(r))")
        }
        let ok = try level2 {
            $0.setStrings(["1", "0", "0", "0", "1", "0"], for: .imageOrientationPatient, vr: .DS)
            $0.setStrings(["ORIGINAL", "PRIMARY", "AXIAL"], for: .imageType, vr: .CS)
            $0.setUInt16(512, for: .rows)
        }
        XCTAssertFalse(ok.errors.contains { $0.message.contains("Table 6-1 gives VM") }, "\(messages(ok))")
    }

    func testPersonNameComponentGroupsAndDuplicateDateErrors() throws {
        let pn = try level2 { $0.setString("A=B=C=D", for: .patientName, vr: .PN) }
        XCTAssertTrue(pn.errors.contains { $0.message.contains("has 4 component groups; at most 3") }, "\(messages(pn))")
        let da = try level2 { $0.setString("2024-01-01", for: .studyDate, vr: .DA) }
        XCTAssertEqual(da.errors.filter { $0.tag == .studyDate && $0.message.contains("YYYYMMDD") }.count, 1, "\(messages(da))")
        let multi = try level2 { $0.setStrings(["20240101", "20240102"], for: Tag(group: 0x0018, element: 0x1200), vr: .DA) }
        XCTAssertFalse(multi.errors.contains { $0.message.contains("Invalid date") }, "multi-valued DA judged per value: \(messages(multi))")
    }
}
