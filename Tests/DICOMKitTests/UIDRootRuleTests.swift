// UIDRootRuleTests.swift
// DICOM 2026a deferred row D250: the `--root` checks of `dicom-uid` and the DICOMStudio Workshop
// are UIDManager.RootRule, pinned to PS3.5 2026a 9.1 (components of one or more digits, no
// leading zero unless the component is a single digit, "." separators, at most 64 characters).

import XCTest
import DICOMCore
@testable import DICOMKit

final class UIDRootRuleTests: XCTestCase {

    func testValidRootsPass() {
        XCTAssertEqual(UIDManager.RootRule.problems(root: UIDGenerator.defaultRoot, typed: true), [])
        XCTAssertEqual(UIDManager.RootRule.problems(root: "1.2.826.0.1.3680043.9.1234", typed: false), [])
        XCTAssertEqual(UIDManager.RootRule.problems(root: "2.0.10", typed: true), [], "9.1: a single-digit 0 component is allowed")
        XCTAssertEqual(UIDManager.RootRule.problems(root: "0", typed: false), [])
    }

    func testEachPS351RuleHasItsText() {
        XCTAssertEqual(UIDManager.RootRule.problems(root: "abc", typed: false),
                       ["UID root component 'abc' is not a number; only the digits 0-9 are allowed (PS3.5 9.1)"])
        XCTAssertEqual(UIDManager.RootRule.problems(root: "1.02.3", typed: false),
                       ["UID root component '02' has a leading zero; only a single-digit component may start with 0 (PS3.5 9.1)"])
        for root in ["1..2", "1.2.", ".1", ""] {
            XCTAssertEqual(UIDManager.RootRule.problems(root: root, typed: false),
                           ["UID root '\(root)' has an empty component; components are separated by single \".\" characters (PS3.5 9.1)"], root)
        }
        XCTAssertEqual(UIDManager.RootRule.problems(root: "1.2a.03", typed: false).count, 2)
    }

    func testRootMustLeaveRoomForTheUniqueSuffixWithin64Characters() {
        XCTAssertEqual(DICOMUniqueIdentifier.maximumLength, 64, "PS3.5 9.1")
        for typed in [false, true] {
            let suffix = UIDManager.RootRule.suffixLength(typed: typed)
            XCTAssertEqual(suffix, 1 + 16 + 1 + 6 + (typed ? 2 : 0), "µs timestamp has 16 digits until 2286")
            let room = 64 - suffix
            let fits = String(repeating: "1", count: room)
            let tooLong = fits + "1"
            XCTAssertEqual(UIDManager.RootRule.problems(root: fits, typed: typed), [])
            XCTAssertEqual(UIDManager.RootRule.problems(root: tooLong, typed: typed),
                           ["UID root is \(room + 1) characters; generated UIDs add up to \(suffix) more and may not exceed 64 (PS3.5 9.1), so the root may have at most \(room)"])
            let uids = UIDManager().generateUIDs(count: 20, root: fits, type: typed ? "study" : nil)
            XCTAssertTrue(uids.allSatisfy { $0.count <= 64 && $0.hasPrefix(fits + ".") })
            XCTAssertEqual(Set(uids).count, 20)
        }
    }
}
