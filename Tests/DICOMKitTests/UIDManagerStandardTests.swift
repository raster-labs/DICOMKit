// UIDManagerStandardTests.swift
// DICOM 2026a deferred rows D133, D135, D136, D138 (UIDManager / UIDConsole).
//
// D135: regenerate walks sequence items and remaps references consistently across files
//       (PS3.15 2026a Table E.1-1: (0008,1155) U, (3006,0024) U).
// D138: only the UI attributes of Table E.1-1 are replaced; Coding Scheme UID, SOP Class
//       UIDs, private UI attributes and PS3.6 Table A-1 UIDs are kept.
// D133: validateUID applies the PS3.5 2026a 9.1 rules only and cites them; --file walks
//       sequence items.
// D136: not-found / unknown --type texts name PS3.6 Table A-1 and its UID Types.

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore
import DICOMDictionary

final class UIDManagerStandardTests: XCTestCase {

    private let ctImage = "1.2.840.10008.5.1.4.1.1.2"

    private func item(_ elements: [DataElement]) -> SequenceItem { SequenceItem(elements: elements) }
    private func ui(_ tag: Tag, _ value: String) -> DataElement { DataElement.string(tag: tag, vr: .UI, value: value) }

    private func file(sop: String, study: String, series: String, frameOfReference: String,
                      configure: (inout DataSet) -> Void = { _ in }) throws -> Data {
        var ds = DataSet()
        ds.setString(ctImage, for: .sopClassUID, vr: .UI)
        ds.setString(sop, for: .sopInstanceUID, vr: .UI)
        ds.setString(study, for: .studyInstanceUID, vr: .UI)
        ds.setString(series, for: .seriesInstanceUID, vr: .UI)
        ds.setString(frameOfReference, for: .frameOfReferenceUID, vr: .UI)
        ds.setString("P1", for: .patientID, vr: .LO)
        configure(&ds)
        return try DICOMFile.create(dataSet: ds, sopClassUID: ctImage, sopInstanceUID: sop).write()
    }

    // MARK: - D138 / D135: the replaced set is the UI attributes of PS3.15 Table E.1-1

    func testRegeneratedTagsAreTheUIAttributesOfTableE11() {
        XCTAssertEqual(UIDManager.regeneratedUIDTags.count, 57, "PS3.15 2026a Table E.1-1 rows with VR UI")
        // Cross-check with the generated E.1-1 table and the PS3.6 dictionary VRs.
        let derived = Set(ConfidentialityProfile.tableE11.keys.map {
            Tag(group: UInt16($0 >> 16), element: UInt16($0 & 0xFFFF))
        }.filter { DataElementDictionary.lookup(tag: $0)?.vr.first == .UI })
        XCTAssertEqual(UIDManager.regeneratedUIDTags, derived)
        for tag in [Tag.sopInstanceUID, .studyInstanceUID, .seriesInstanceUID, .frameOfReferenceUID,
                    .referencedSOPInstanceUID, Tag(group: 0x3006, element: 0x0024), Tag(group: 0x006A, element: 0x0003)] {
            XCTAssertTrue(UIDManager.regeneratedUIDTags.contains(tag), "\(tag)")
        }
        for tag in [Tag.sopClassUID, .referencedSOPClassUID, .transferSyntaxUID,
                    Tag(group: 0x0008, element: 0x010C),   // Coding Scheme UID
                    Tag(group: 0x0008, element: 0x010D),   // Context Group Extension Creator UID
                    Tag(group: 0x0008, element: 0x0118)] { // Mapping Resource UID
            XCTAssertFalse(UIDManager.regeneratedUIDTags.contains(tag), "\(tag) is not an E.1-1 UID attribute")
        }
    }

    func testReferencesInsideSequencesFollowTheReferencedInstanceAcrossFiles() throws {
        let sopA = "1.2.826.0.1.3680043.10.1078.1", sopB = "1.2.826.0.1.3680043.10.1078.2"
        let study = "1.2.826.0.1.3680043.10.1078.3", series = "1.2.826.0.1.3680043.10.1078.4"
        let frame = "1.2.826.0.1.3680043.10.1078.5"
        let a = try file(sop: sopA, study: study, series: series, frameOfReference: frame)
        let b = try file(sop: sopB, study: study, series: series, frameOfReference: frame) { ds in
            ds.setSequence([self.item([self.ui(.referencedSOPClassUID, self.ctImage),
                                       self.ui(.referencedSOPInstanceUID, sopA)])], for: .referencedImageSequence)
            // Deeper nesting: (3006,0010) > (3006,0024) Referenced Frame of Reference UID.
            ds.setSequence([self.item([self.ui(Tag(group: 0x3006, element: 0x0024), frame)])],
                           for: Tag(group: 0x3006, element: 0x0010))
        }

        let manager = UIDManager()
        var shared: [String: String] = [:]
        let (newA, _) = try manager.regenerateData(a, root: nil, maintainRelationships: true, existingMappings: &shared)
        let (newB, mapsB) = try manager.regenerateData(b, root: nil, maintainRelationships: true, existingMappings: &shared)

        let fa = try DICOMFile.read(from: newA), fb = try DICOMFile.read(from: newB)
        let newSOPA = try XCTUnwrap(fa.dataSet.string(for: .sopInstanceUID))
        XCTAssertNotEqual(newSOPA, sopA)
        XCTAssertEqual(fa.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID), newSOPA,
                       "PS3.10 Table 7.1-1 (0002,0003) follows the SOP Instance UID")
        let ref = try XCTUnwrap(fb.dataSet.sequence(for: .referencedImageSequence)?.first)
        XCTAssertEqual(ref.string(for: .referencedSOPInstanceUID), newSOPA, "the reference follows file A's new UID")
        XCTAssertEqual(ref.string(for: .referencedSOPClassUID), ctImage, "a SOP Class UID is never replaced")
        let newFrame = try XCTUnwrap(fb.dataSet.string(for: .frameOfReferenceUID))
        XCTAssertEqual(fa.dataSet.string(for: .frameOfReferenceUID), newFrame)
        let nested = try XCTUnwrap(fb.dataSet.sequence(for: Tag(group: 0x3006, element: 0x0010))?.first)
        XCTAssertEqual(nested.string(for: Tag(group: 0x3006, element: 0x0024)), newFrame)
        XCTAssertEqual(fb.dataSet.string(for: .studyInstanceUID), fa.dataSet.string(for: .studyInstanceUID))
        XCTAssertTrue(mapsB.contains { $0.tagName == "(0008,1140)>(0008,1155)" && $0.oldUID == sopA && $0.newUID == newSOPA })
    }

    func testSameUIDGetsOneNewUIDWithinAFileWithoutMaintainRelationships() throws {
        let sop = "1.2.826.0.1.3680043.10.1078.11"
        let data = try file(sop: sop, study: "1.2.826.0.1.3680043.10.1078.12",
                            series: "1.2.826.0.1.3680043.10.1078.13", frameOfReference: "1.2.826.0.1.3680043.10.1078.14") { ds in
            ds.setSequence([self.item([self.ui(.referencedSOPInstanceUID, sop)])], for: .sourceImageSequence)
        }
        var none: [String: String] = [:]
        let (out, _) = try UIDManager().regenerateData(data, root: nil, maintainRelationships: false, existingMappings: &none)
        let f = try DICOMFile.read(from: out)
        XCTAssertEqual(f.dataSet.sequence(for: .sourceImageSequence)?.first?.string(for: .referencedSOPInstanceUID),
                       f.dataSet.string(for: .sopInstanceUID))
        XCTAssertTrue(none.isEmpty, "nothing is shared without maintainRelationships")
    }

    func testNonInstanceAndRegistryUIDsAreKept() throws {
        let codingScheme = "2.16.840.1.113883.6.96"          // SNOMED CT, not in Table A-1
        let wellKnown = "1.2.840.10008.1.20"                 // Storage Commitment Push Model SOP Instance (Table A-1)
        let privateClass = "1.2.826.0.1.3680043.10.1078.99.1"
        let data = try file(sop: "1.2.826.0.1.3680043.10.1078.21", study: "1.2.826.0.1.3680043.10.1078.22",
                            series: "1.2.826.0.1.3680043.10.1078.23", frameOfReference: "1.2.826.0.1.3680043.10.1078.24") { ds in
            ds.setSequence([self.item([DataElement.string(tag: Tag(group: 0x0008, element: 0x0100), vr: .SH, value: "123"),
                                       self.ui(Tag(group: 0x0008, element: 0x010C), codingScheme),
                                       self.ui(Tag(group: 0x0008, element: 0x010D), "1.2.826.0.1.3680043.10.1078.25")])],
                           for: Tag(group: 0x0040, element: 0xA043))
            ds.setSequence([self.item([self.ui(.referencedSOPClassUID, privateClass),
                                       self.ui(.referencedSOPInstanceUID, wellKnown)])], for: .referencedImageSequence)
            ds.setString("1.2.826.0.1.3680043.10.1078.26", for: Tag(group: 0x0009, element: 0x1001), vr: .UI)
        }
        var none: [String: String] = [:]
        let (out, maps) = try UIDManager().regenerateData(data, root: nil, maintainRelationships: false, existingMappings: &none)
        let ds = try DICOMFile.read(from: out).dataSet
        let code = try XCTUnwrap(ds.sequence(for: Tag(group: 0x0040, element: 0xA043))?.first)
        XCTAssertEqual(code.string(for: Tag(group: 0x0008, element: 0x010C)), codingScheme)
        XCTAssertEqual(code.string(for: Tag(group: 0x0008, element: 0x010D)), "1.2.826.0.1.3680043.10.1078.25")
        let ref = try XCTUnwrap(ds.sequence(for: .referencedImageSequence)?.first)
        XCTAssertEqual(ref.string(for: .referencedSOPClassUID), privateClass)
        XCTAssertEqual(ref.string(for: .referencedSOPInstanceUID), wellKnown, "a Table A-1 UID is never replaced")
        XCTAssertEqual(ds.string(for: Tag(group: 0x0009, element: 0x1001)), "1.2.826.0.1.3680043.10.1078.26")
        XCTAssertEqual(Set(maps.map(\.tagHex)), ["0008,0018", "0020,000D", "0020,000E", "0020,0052"])
    }

    func testPreviewListsNestedUIDsWithTheirSequencePath() throws {
        var ds = DataSet()
        ds.setString("1.2.3.4", for: .sopInstanceUID, vr: .UI)
        ds.setString(ctImage, for: .sopClassUID, vr: .UI)
        ds.setSequence([item([ui(.referencedSOPClassUID, ctImage), ui(.referencedSOPInstanceUID, "1.2.3.5")])],
                       for: .referencedImageSequence)
        XCTAssertEqual(UIDManager.regenerationPreviewLines(for: ds), [
            "  SOPInstanceUID: 1.2.3.4 \u{2192} <new UID>",
            "  (0008,1140)>(0008,1155): 1.2.3.5 \u{2192} <new UID>",
            "  2 UID(s) would be regenerated",
        ])
    }

    // MARK: - D133: PS3.5 9.1 only

    func testValidateUIDAppliesPS35Section91Only() {
        let manager = UIDManager()
        XCTAssertTrue(manager.validateUID("1").isValid, "9.1 sets no minimum number of components")
        XCTAssertTrue(manager.validateUID("0").isValid)
        XCTAssertTrue(manager.validateUID("2.25.329800735698586629295641978511506172918").isValid)
        XCTAssertTrue(manager.validateUID("1." + String(repeating: "2", count: 62)).isValid, "64 characters")
        let tooLong = manager.validateUID("1." + String(repeating: "2", count: 63))
        XCTAssertFalse(tooLong.isValid)
        for bad in ["1.02", "1..2", ".1", "1.", "1.a", ""] {
            let r = manager.validateUID(bad)
            XCTAssertFalse(r.isValid, bad)
            XCTAssertTrue(r.errors.allSatisfy { $0.contains("(PS3.5 9.1)") }, "\(bad): \(r.errors)")
        }
        XCTAssertFalse(manager.validateUID("1").errors.contains { $0.contains("2 components") })
    }

    func testValidateFileUIDsCoversFileMetaAndSequenceItems() throws {
        let data = try file(sop: "1.2.3.6", study: "1.2.3.7", series: "1.2.3.8", frameOfReference: "1.2.3.9") { ds in
            ds.setSequence([self.item([self.ui(.referencedSOPInstanceUID, "1.02.3")])], for: .referencedImageSequence)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uid-\(UUID().uuidString).dcm")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let results = try UIDManager().validateFileUIDs(path: url.path)
        XCTAssertTrue(results.contains { $0.uid == "1.02.3" && !$0.isValid }, "nested value checked")
        XCTAssertTrue(results.contains { $0.uid == "1.2.840.10008.1.2.1" }, "File Meta Transfer Syntax UID checked")
    }

    // MARK: - D136: PS3.6 Table A-1 wording

    func testLookupTextsNameTableA1() {
        XCTAssertEqual(UIDConsole.lookupNotFoundLine(uid: "1.2.3"),
                       "UID not found in the DICOM UID registry (PS3.6 Table A-1): 1.2.3")
        let line = UIDConsole.unknownTypeFilterLine("x")
        XCTAssertTrue(line.hasPrefix("Unknown type filter 'x'. Valid types (PS3.6 Table A-1 UID Type): transfer-syntax, sop-class, meta-sop-class"))
        XCTAssertEqual(UIDConsole.lookupTypeFilters.count, 11)
        XCTAssertEqual(Set(UIDConsole.lookupTypeFilters.map(\.tableA1)).count, 11)
        XCTAssertEqual(UIDConsole.entries(forTypeFilter: "sopclass")?.count, UIDDictionary.sopClasses.count)
        XCTAssertEqual(UIDConsole.entries(forTypeFilter: "well-known-sop-instance")?.count, 19)
        XCTAssertNil(UIDConsole.entries(forTypeFilter: "nonsense"))
    }
}
