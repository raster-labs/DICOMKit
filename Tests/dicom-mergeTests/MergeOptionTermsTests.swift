import XCTest
import Foundation
import DICOMCore
import DICOMDictionary
import DICOMKit
@testable import dicom_merge

/// `dicom-merge` option vocabularies against DICOM 2026a. Expected UIDs, names and
/// tags are PS3.6 2026a Table A-1 / Table 6-1 rows, dumped from the DocBook by script.
final class MergeOptionTermsTests: XCTestCase {

    private var help: String {
        // Whitespace-normalised: the discussion wraps names across source lines.
        DICOMMerge.helpMessage(columns: 10_000).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // PS3.6 2026a Table A-1.
    func testFormatValuesMapToTableA1SOPClasses() {
        let expected: [String: (String, String)] = [
            "enhanced-ct": ("1.2.840.10008.5.1.4.1.1.2.1", "Enhanced CT Image Storage"),
            "enhanced-mr": ("1.2.840.10008.5.1.4.1.1.4.1", "Enhanced MR Image Storage"),
            "enhanced-pet": ("1.2.840.10008.5.1.4.1.1.130", "Enhanced PET Image Storage"),
            "enhanced-xa": ("1.2.840.10008.5.1.4.1.1.12.1.1", "Enhanced XA Image Storage"),
            "enhanced-xrf": ("1.2.840.10008.5.1.4.1.1.12.2.1", "Enhanced XRF Image Storage"),
            "legacy-converted-ct": ("1.2.840.10008.5.1.4.1.1.2.2", "Legacy Converted Enhanced CT Image Storage"),
            "legacy-converted-mr": ("1.2.840.10008.5.1.4.1.1.4.4", "Legacy Converted Enhanced MR Image Storage"),
            "legacy-converted-pet": ("1.2.840.10008.5.1.4.1.1.128.1", "Legacy Converted Enhanced PET Image Storage"),
            "sc-multiframe": ("1.2.840.10008.5.1.4.1.1.7.2", "Multi-frame Grayscale Byte Secondary Capture Image Storage"),
            "us-multiframe": ("1.2.840.10008.5.1.4.1.1.3.1", "Ultrasound Multi-frame Image Storage"),
        ]
        XCTAssertEqual(Set(MergeFormat.allCases.map(\.rawValue)), Set(expected.keys).union(["standard", "auto"]))
        for format in MergeFormat.allCases {
            guard let (uid, name) = expected[format.rawValue] else {
                XCTAssertNil(format.enhancedSOPClassUID, format.rawValue)
                continue
            }
            XCTAssertEqual(format.enhancedSOPClassUID, uid, format.rawValue)
            XCTAssertEqual(UIDDictionary.lookup(uid: uid)?.name, name, format.rawValue)
        }
    }

    // PS3.6 2026a Table 6-1: the --sort-by values are keywords.
    func testSortByValuesArePS36Keywords() {
        let expected: [String: Tag] = [
            "InstanceNumber": Tag(group: 0x0020, element: 0x0013),
            "ImagePositionPatient": Tag(group: 0x0020, element: 0x0032),
            "AcquisitionTime": Tag(group: 0x0008, element: 0x0032),
        ]
        for (keyword, tag) in expected {
            XCTAssertNotNil(MergeSortCriteria(rawValue: keyword), keyword)
            XCTAssertEqual(DataElementDictionary.lookup(keyword: keyword)?.tag, tag, keyword)
            XCTAssertTrue(help.contains("\(keyword) \(tag.description.dropLast())"), "help pairs \(keyword) with \(tag)")
        }
        XCTAssertNotNil(MergeSortCriteria(rawValue: "none"))
    }

    /// Every "Name (gggg,eeee)" pair in the help names the PS3.6 Table 6-1 element.
    func testAttributeNamesInHelpMatchTheirTags() throws {
        let regex = try NSRegularExpression(pattern: #"([A-Z][A-Za-z'\- ]+?(?: \(Patient\))?) \(([0-9A-F]{4}),([0-9A-F]{4})\)"#)
        let ns = help as NSString
        let matches = regex.matches(in: help, range: NSRange(location: 0, length: ns.length))
        XCTAssertGreaterThanOrEqual(matches.count, 6)
        for m in matches {
            let name = ns.substring(with: m.range(at: 1))
            let tag = Tag(group: UInt16(ns.substring(with: m.range(at: 2)), radix: 16)!,
                          element: UInt16(ns.substring(with: m.range(at: 3)), radix: 16)!)
            let entry = try XCTUnwrap(DataElementDictionary.lookup(tag: tag), "\(tag)")
            // A name or, for --sort-by values, the keyword.
            XCTAssertTrue(name.hasSuffix(entry.name) || name.hasSuffix(" " + entry.keyword) || name == entry.keyword,
                          "help says '\(name)' for \(tag); PS3.6 name is '\(entry.name)'")
        }
    }

    /// The Legacy Converted IOD is cited by its PS3.3 2026a section, not by supplement.
    func testHelpCitesLegacyConvertedIODSection() {
        XCTAssertTrue(help.contains("Legacy Converted Enhanced MR Image Storage (PS3.3 A.71)"))
        XCTAssertFalse(help.contains("Sup 157"))
    }
}
