import XCTest
import Foundation
import DICOMCore
import DICOMDictionary
import DICOMKit
@testable import dicom_split

/// `dicom-split` option surface against DICOM 2026a. Expected names and tags are the
/// PS3.6 2026a Table 6-1 / Table A-1 rows, dumped from the DocBook by script.
final class SplitOptionHelpTests: XCTestCase {

    private var help: String {
        // Whitespace-normalised: the discussion wraps names across source lines.
        DICOMSplit.helpMessage(columns: 10_000).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Every "Name (gggg,eeee)" pair in the help names the PS3.6 Table 6-1 element.
    func testAttributeNamesInHelpMatchTheirTags() throws {
        let regex = try NSRegularExpression(pattern: #"([A-Z][A-Za-z'\- ]+?(?: \(Patient\))?) \(([0-9A-F]{4}),([0-9A-F]{4})\)"#)
        let ns = help as NSString
        let matches = regex.matches(in: help, range: NSRange(location: 0, length: ns.length))
        XCTAssertGreaterThanOrEqual(matches.count, 5)
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

    /// The --split-by / --instance-number values name the PS3.3 C.7.6.16.2.2 Frame
    /// Content Macro attributes they act on.
    func testSplitByAndInstanceNumberNameFrameContentAttributes() {
        XCTAssertTrue(help.contains("stack (Stack ID (0020,9056))"))
        XCTAssertTrue(help.contains("temporal (Temporal Position Index (0020,9128))"))
        XCTAssertTrue(help.contains("instack (In-Stack Position Number (0020,9057))"))
        XCTAssertTrue(help.contains("Instance Number (0020,0013)"))
        XCTAssertEqual(SplitSeriesGrouping.allCases.map(\.rawValue), ["none", "stack", "temporal"])
        XCTAssertEqual(SplitInstanceNumbering.allCases.map(\.rawValue), ["frame", "instack", "original"])
    }

    /// PS3.3 C.7.6.16.1.2: "Frames are implicitly numbered starting from 1." --frames
    /// takes 0-based indices, so the help must say so instead of "frame numbers".
    func testFramesOptionIsDocumentedAsZeroBasedIndex() throws {
        // P-SPLIT-1: --frames is the deprecated 0-based option; --frame-numbers counts from 1.
        XCTAssertTrue(help.contains("--frames <frames> deprecated: 0-based index; use --frame-numbers"))
        XCTAssertTrue(help.contains("Frames to extract by Frame number, numbered from 1 (PS3.3 C.7.6.16.1.2)"))
        XCTAssertEqual(try SplitConsole.parseFrameSelection("0,2-3"), [0, 2, 3])
    }

    /// SOP Class names quoted in the help are PS3.6 2026a Table A-1 names.
    func testSOPClassNamesInHelpAreTableA1Names() {
        let names = [
            "CT Image Storage", "MR Image Storage", "Positron Emission Tomography Image Storage",
            "X-Ray Angiographic Image Storage", "X-Ray Radiofluoroscopic Image Storage",
            "Ultrasound Multi-frame Image Storage", "Ultrasound Image Storage",
            "Secondary Capture Image Storage", "Enhanced CT Image Storage",
        ]
        let registered = Set(UIDDictionary.allEntries.map(\.name))
        for name in names {
            XCTAssertTrue(help.contains(name), name)
            XCTAssertTrue(registered.contains(name), "\(name) is not a Table A-1 name")
        }
        XCTAssertTrue(help.contains("Explicit VR Little Endian"))
        XCTAssertEqual(UIDDictionary.lookup(uid: "1.2.840.10008.1.2.1")?.name, "Explicit VR Little Endian")
    }
}
