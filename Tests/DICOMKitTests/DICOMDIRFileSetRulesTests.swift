// DICOMDIRFileSetRulesTests.swift
// DICOM 2026a deferred row D253: the File ID / File-set ID rules of `dicom-dcmdir` and the
// DICOMStudio Workshop are DICOMDIRFileSetRules, pinned to PS3.10 2026a 8.1 (File-set ID 0-16
// characters), 8.2 (1-8 components of 1-8 characters), 8.5 (A-Z, 0-9, _), 8.6 (no File outside
// the File-set) and the PS3.3 2026a Table F.3-2 / F.3-3 / F.4-1 citations.

import XCTest
import Foundation
import DICOMCore
@testable import DICOMKit

final class DICOMDIRFileSetRulesTests: XCTestCase {

    func testConstantsArePS310() {
        XCTAssertEqual(DICOMDIRFileSetRules.maxFileSetIDLength, 16, "8.1")
        XCTAssertEqual(DICOMDIRFileSetRules.maxFileIDComponents, 8, "8.2")
        XCTAssertEqual(DICOMDIRFileSetRules.maxComponentLength, 8, "8.2")
        XCTAssertEqual(DICOMDIRFileSetRules.allowedCharacters, Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"), "8.5")
        XCTAssertFalse(DICOMDIRFileSetRules.allowedCharacters.contains(" "), "8.5: CS without SPACE")
        XCTAssertEqual(DICOMDIRFileSetRules.fileIDRule, "PS3.10 8.2, 8.5; PS3.3 Table F.3-3 Referenced File ID (0004,1500)")
        XCTAssertEqual(DICOMDIRFileSetRules.fileSetIDRule, "PS3.10 8.1, 8.5; PS3.3 Table F.3-2 File-set ID (0004,1130)")
    }

    func testFileIDRules82And85() {
        XCTAssertEqual(DICOMDIRFileSetRules.fileIDViolations(["DICOM", "PT000001", "ST000001", "SE000001", "IM000001"]), [])
        XCTAssertEqual(DICOMDIRFileSetRules.fileIDViolations(["DICOMDIR"]), [])
        XCTAssertEqual(DICOMDIRFileSetRules.fileIDViolations(["ABCDEFGHI"]),
                       ["File ID component 'ABCDEFGHI' of ABCDEFGHI has 9 characters; each component has 1 to 8 [\(DICOMDIRFileSetRules.fileIDRule)]"])
        XCTAssertEqual(DICOMDIRFileSetRules.fileIDViolations(["im1.dcm"]),
                       ["File ID component 'im1.dcm' of im1.dcm uses characters other than A-Z, 0-9 and _ [\(DICOMDIRFileSetRules.fileIDRule)]"])
        let nine = Array(repeating: "A", count: 9)
        XCTAssertEqual(DICOMDIRFileSetRules.fileIDViolations(nine),
                       ["File ID \(nine.joined(separator: "\\")) has 9 components; a File ID has 1 to 8 [\(DICOMDIRFileSetRules.fileIDRule)]"])
        XCTAssertEqual(DICOMDIRFileSetRules.fileIDViolations([]).count, 1)
    }

    func testFileSetIDRules81And85() {
        XCTAssertEqual(DICOMDIRFileSetRules.fileSetIDViolations(""), [], "Type 2: empty allowed")
        XCTAssertEqual(DICOMDIRFileSetRules.fileSetIDViolations("ABCDEFGHIJKLMNOP"), [])
        XCTAssertEqual(DICOMDIRFileSetRules.fileSetIDViolations("ABCDEFGHIJKLMNOPQ"),
                       ["File-set ID 'ABCDEFGHIJKLMNOPQ' has 17 characters; at most 16 [\(DICOMDIRFileSetRules.fileSetIDRule)]"])
        XCTAssertEqual(DICOMDIRFileSetRules.fileSetIDViolations("my set"),
                       ["File-set ID 'my set' uses characters other than A-Z, 0-9 and _ [\(DICOMDIRFileSetRules.fileSetIDRule)]"])
        XCTAssertNil(DICOMDIRFileSetRules.fileSetIDRefusal("STUDY_1"))
        XCTAssertEqual(DICOMDIRFileSetRules.fileSetIDRefusal("my set"),
                       "Refusing --file-set-id: File-set ID 'my set' uses characters other than A-Z, 0-9 and _ [\(DICOMDIRFileSetRules.fileSetIDRule)]"
                       + ". A File-set ID is 0 to 16 characters A-Z, 0-9 and _ (PS3.10 2026a 8.1, 8.5; PS3.3 2026a Table F.3-2 File-set ID (0004,1130))")
        XCTAssertEqual(DICOMDIRFileSetRules.defaultFileSetID(fromDirectoryName: "my study-2024 (final) extra"), "MY_STUDY_2024__F")
    }

    func testDeprecatedProfileSpellingsNameThePS311Table() throws {
        XCTAssertEqual(DICOMDIRFileSetRules.deprecatedProfileTables.count, 5)
        let resolved = try XCTUnwrap(DICOMDIRProfile(rawValue: "STD-GEN-DVD"))
        XCTAssertEqual(DICOMDIRFileSetRules.profileDeprecationNote(requested: "STD-GEN-DVD", resolved: resolved),
                       "dicom-dcmdir: warning: --profile STD-GEN-DVD is deprecated (not a PS3.11 Application Profile identifier); using \(resolved.rawValue) (PS3.11 2026a Table H.1-1). It will be rejected in the next major version.")
        XCTAssertNil(DICOMDIRFileSetRules.profileDeprecationNote(requested: resolved.rawValue, resolved: resolved))
    }

    func testValidationErrorsCiteTheirClause() {
        XCTAssertEqual(DICOMDIRFileSetRules.citation(for: .invalidFileSetID), DICOMDIRFileSetRules.fileSetIDRule)
        XCTAssertEqual(DICOMDIRFileSetRules.citation(for: .invalidHierarchy("x")), "PS3.3 F.4, Table F.4-1")
        XCTAssertEqual(DICOMDIRFileSetRules.citation(for: .invalidRecordTypeInHierarchy("x")), "PS3.3 F.4, Table F.4-1")
        XCTAssertEqual(DICOMDIRFileSetRules.citation(for: .missingReferencedFile("x")), "PS3.10 8.6; PS3.3 Table F.3-3 Referenced File ID (0004,1500)")
        XCTAssertEqual(DICOMDIRFileSetRules.citation(for: .invalidSOPInstanceUID("x")), "PS3.5 9.1; PS3.3 Table F.3-3 Referenced SOP Instance UID in File (0004,1511)")
        XCTAssertEqual(DICOMDIRFileSetRules.citation(for: .duplicateSOPInstanceUID("x")), "PS3.3 Table F.3-3 Referenced SOP Instance UID in File (0004,1511); PS3.5 9")
        XCTAssertTrue(DICOMDIRFileSetRules.describe(DICOMDirectory.ValidationError.missingReferencedFile("DICOM\\IM1")).hasSuffix("[PS3.10 8.6; PS3.3 Table F.3-3 Referenced File ID (0004,1500)]"))
    }
}
