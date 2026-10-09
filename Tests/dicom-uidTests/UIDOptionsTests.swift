import XCTest
import Foundation
import DICOMCore
import DICOMKit
import DICOMDictionary
@testable import dicom_uid

/// `dicom-uid` option checks pinned to PS3.5 2026a 9.1 (UID syntax, 64 characters),
/// 9.2.2 (registered root), B.2 (UUID derived UID) and PS3.6 2026a Table A-1 (UID Types).
final class UIDOptionsTests: XCTestCase {

    func testValidRootsPass() {
        XCTAssertEqual(UIDRootRule.problems(root: UIDGenerator.defaultRoot, typed: true), [])
        XCTAssertEqual(UIDRootRule.problems(root: "1.2.826.0.1.3680043.9.1234", typed: false), [])
        XCTAssertEqual(UIDRootRule.problems(root: "2.0.10", typed: true), [], "a single-digit 0 component is allowed")
    }

    func testMalformedRootsAreRejectedWithTheirPS35Rule() {
        // These roots used to crash the generator (force-unwrap in UIDGenerator.generate).
        XCTAssertTrue(UIDRootRule.problems(root: "abc", typed: false).contains { $0.contains("not a number") })
        XCTAssertTrue(UIDRootRule.problems(root: "1.02.3", typed: false).contains { $0.contains("leading zero") })
        XCTAssertTrue(UIDRootRule.problems(root: "1..2", typed: false).contains { $0.contains("empty component") })
        XCTAssertTrue(UIDRootRule.problems(root: "1.2.", typed: false).contains { $0.contains("empty component") })
        XCTAssertTrue(UIDRootRule.problems(root: "", typed: false).contains { $0.contains("empty component") })
    }

    func testRootMustLeaveRoomForTheUniqueSuffix() {
        let room = DICOMUniqueIdentifier.maximumLength - UIDRootRule.suffixLength(typed: true)
        let fits = String(repeating: "1", count: room)
        let tooLong = String(repeating: "1", count: room + 1)
        XCTAssertEqual(UIDRootRule.problems(root: fits, typed: true), [])
        XCTAssertEqual(UIDRootRule.problems(root: tooLong, typed: true).count, 1)
        // Every UID generated on a root that passes is within 64 characters and distinct.
        let uids = UIDManager().generateUIDs(count: 20, root: fits, type: "study")
        XCTAssertTrue(uids.allSatisfy { $0.count <= 64 && $0.hasPrefix(fits + ".1.") })
        XCTAssertEqual(Set(uids).count, 20)
    }

    func testUUIDDerivedUIDFollowsPS35B2() {
        // 128-bit all-ones UUID is 2^128 - 1 = 340282366920938463463374607431768211455 (39 digits).
        let max = UUID(uuid: (255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255))
        XCTAssertEqual(UUIDDerivedUID.make(from: max), "2.25.340282366920938463463374607431768211455")
        let one = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
        XCTAssertEqual(UUIDDerivedUID.make(from: one), "2.25.1")
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        XCTAssertEqual(UUIDDerivedUID.make(from: zero), "2.25.0")
        // RFC 4122 / ISO/IEC 9834-8 example UUID f81d4fae-7dec-11d0-a765-00a0c91e6bf6 (the 2026a text gives no example)
        let example = UUID(uuidString: "F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6")!
        XCTAssertEqual(UUIDDerivedUID.make(from: example), "2.25.329800735698586629295641978511506172918")
        for _ in 0..<50 {
            let uid = UUIDDerivedUID.make()
            XCTAssertLessThanOrEqual(uid.count, 64)
            XCTAssertTrue(UIDManager().validateUID(uid).isValid, uid)
        }
    }

    func testLookupTypeFilterCoversEveryTableA1UIDType() {
        // The 12 "UID Type" values of PS3.6 2026a Table A-1; "DICOM UIDs as a Coding Scheme"
        // is folded into coding-scheme by DICOMDictionary.UIDType.
        let tableA1Types: Set<String> = [
            "Application Context Name", "Application Hosting Model", "Coding Scheme", "LDAP OID",
            "Mapping Resource", "Meta SOP Class", "SOP Class", "Service Class",
            "Synchronization Frame of Reference", "Transfer Syntax", "Well-known SOP Instance",
        ]
        XCTAssertEqual(Set(LookupTypeFilter.all.map(\.tableA1)), tableA1Types)
        XCTAssertEqual(LookupTypeFilter.entries(for: "sopclass")?.count, UIDDictionary.sopClasses.count)
        XCTAssertEqual(LookupTypeFilter.entries(for: "transfer-syntax")?.count, UIDDictionary.transferSyntaxes.count)
        XCTAssertEqual(LookupTypeFilter.entries(for: "well-known-sop-instance")?.count, 19)
        XCTAssertEqual(LookupTypeFilter.entries(for: "application-context-name")?.map(\.uid), ["1.2.840.10008.3.1.1.1"])
        XCTAssertNil(LookupTypeFilter.entries(for: "nonsense"))
        for f in LookupTypeFilter.all { XCTAssertFalse(LookupTypeFilter.entries(for: f.value)!.isEmpty, f.value) }
    }

    // MARK: - P-UID-TYPE: PS3.6 2026a Table A-1 UID Type text

    /// Rows per UID Type in PS3.6 2026a Table A-1 (465 rows, dumped from part06 by
    /// Scripts/nema_docbook.py on 2026-10-01).
    private let tableA1TypeCounts: [String: Int] = [
        "Application Context Name": 1, "Application Hosting Model": 2, "Coding Scheme": 15,
        "DICOM UIDs as a Coding Scheme": 1, "LDAP OID": 39, "Mapping Resource": 1,
        "Meta SOP Class": 9, "SOP Class": 311, "Service Class": 3,
        "Synchronization Frame of Reference": 1, "Transfer Syntax": 63, "Well-known SOP Instance": 19,
    ]

    func testTableA1UIDTypeTextMatchesEveryRegistryRow() {
        var counts: [String: Int] = [:]
        // The two unregistered Fragmentable HEVC syntaxes (registered: false) are not Table A-1 rows.
        for entry in UIDDictionary.allEntries where entry.registered {
            counts[UIDManager.tableA1UIDType(of: entry), default: 0] += 1
        }
        XCTAssertEqual(Set(counts.keys), Set(tableA1TypeCounts.keys))
        for (type, expected) in tableA1TypeCounts {
            XCTAssertEqual(counts[type] ?? 0, expected, type)
        }
    }

    func testTheThreeFormerlyRewordedTypes() throws {
        let registry = try XCTUnwrap(UIDDictionary.lookup(uid: "1.2.840.10008.2.6.1"))
        XCTAssertEqual(UIDManager.tableA1UIDType(of: registry), "DICOM UIDs as a Coding Scheme")
        XCTAssertEqual(UIDManager.uidTypeDescription(registry.type), "Coding Scheme", "legacy wording kept for the deprecated JSON type key")
        let context = try XCTUnwrap(UIDDictionary.lookup(uid: "1.2.840.10008.3.1.1.1"))
        XCTAssertEqual(UIDManager.tableA1UIDType(of: context), "Application Context Name")
        let wellKnown = try XCTUnwrap(UIDDictionary.lookup(uid: "1.2.840.10008.1.20.1.1"))
        XCTAssertEqual(UIDManager.tableA1UIDType(of: wellKnown), "Well-known SOP Instance")
        XCTAssertEqual(UIDManager.uidTypeDescription(wellKnown.type), "Well-Known UID")
    }

    func testLookupJSONCarriesUIDTypeNextToTheDeprecatedTypeKey() throws {
        let text = try UIDConsole.lookupEntryJSON(
            uid: "1.2.840.10008.1.20.1.1", name: "Storage Commitment Push Model SOP Instance",
            type: "Well-Known UID", uidType: "Well-known SOP Instance")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String])
        XCTAssertEqual(object["uidType"], "Well-known SOP Instance")
        XCTAssertEqual(object["type"], "Well-Known UID")
        let list = try UIDConsole.listingJSON(entries: [(uid: "1.2.840.10008.3.1.1.1", name: "DICOM Application Context Name",
                                                         type: "Application Context", uidType: "Application Context Name")])
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(list.utf8)) as? [[String: String]])
        XCTAssertEqual(rows.first?["uidType"], "Application Context Name")
        XCTAssertEqual(rows.first?["type"], "Application Context")
    }
}
