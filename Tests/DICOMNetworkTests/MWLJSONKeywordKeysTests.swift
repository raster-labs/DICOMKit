//
// MWLJSONKeywordKeysTests.swift
// DICOMNetworkTests
//
// P-MWL-JSON-KEYS (2026-10-01): `NetworkConsole.mwlJSON` (dicom-mwl --json and
// the DICOMStudio MWL panel) writes the ten formerly abbreviated values under
// their PS3.6 2026a Table 6-1 keywords as well; the old keys keep their values.
//

import XCTest
import DICOMCore
@testable import DICOMNetwork

final class MWLJSONKeywordKeysTests: XCTestCase {

    // Implicit VR Little Endian builders.
    private func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }
    private func elem(_ g: UInt16, _ e: UInt16, _ value: String) -> Data {
        var v = Data(value.utf8)
        if v.count % 2 != 0 { v.append(0x20) }
        return le16(g) + le16(e) + le32(UInt32(v.count)) + v
    }
    private func seq(_ g: UInt16, _ e: UInt16, _ items: [Data]) -> Data {
        var body = Data()
        for item in items {
            body += Data([0xFE, 0xFF, 0x00, 0xE0]) + le32(UInt32(item.count)) + item
        }
        return le16(g) + le16(e) + le32(UInt32(body.count)) + body
    }
    private func code(_ value: String, _ scheme: String, _ meaning: String) -> Data {
        elem(0x0008, 0x0100, value) + elem(0x0008, 0x0102, scheme) + elem(0x0008, 0x0104, meaning)
    }

    private func item() -> WorklistItem {
        let spsItem = elem(0x0040, 0x0002, "20261001") + elem(0x0040, 0x0003, "0930")
            + elem(0x0040, 0x0006, "SMITH^ANN") + elem(0x0040, 0x0007, "CT HEAD")
            + seq(0x0040, 0x0008, [code("P1", "99LOCAL", "Head protocol")])
            + elem(0x0040, 0x0009, "SPS1") + elem(0x0040, 0x0011, "ROOM 1")
            + elem(0x0040, 0x0020, "SCHEDULED")
        var data = seq(0x0008, 0x1110, [
            elem(0x0008, 0x1150, "1.2.840.10008.3.1.2.3.1") + elem(0x0008, 0x1155, "1.2.3.4"),
            elem(0x0008, 0x1150, "1.2.840.10008.3.1.2.3.1") + elem(0x0008, 0x1155, "1.2.3.5"),
        ])
        data += elem(0x0010, 0x0010, "DOE^JANE")
        data += seq(0x0032, 0x1064, [code("R1", "99LOCAL", "CT Head")])
        data += seq(0x0040, 0x0100, [spsItem])
        var offset = 0
        var parsed = DICOMModalityWorklistService.MWLParsedDataSet()
        DICOMModalityWorklistService.parseMWLDataSet(data: data, offset: &offset, end: data.count,
                                                     isExplicitVR: false, into: &parsed)
        return WorklistItem(attributes: parsed.attributes, sequences: parsed.sequences)
    }

    private func json() throws -> [String: Any] {
        let text = NetworkConsole.mwlJSON(items: [item()])
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        return try XCTUnwrap(array.first)
    }

    /// The 10 keywords, as dumped from PS3.6 2026a Table 6-1 by Scripts/nema_docbook.py.
    func testKeywordKeysAreThePS36Keywords() {
        XCTAssertEqual(NetworkConsole.mwlJSONKeywordKeys.map(\.keyword), [
            "ScheduledProcedureStepStartDate", "ScheduledProcedureStepStartTime",
            "ScheduledProcedureStepStatus", "ScheduledProcedureStepID",
            "ScheduledProcedureStepDescription", "ScheduledProcedureStepLocation",
            "ScheduledPerformingPhysicianName", "RequestedProcedureCodeSequence",
            "ScheduledProtocolCodeSequence", "ReferencedStudySequence",
        ])
    }

    func testScalarValuesAreWrittenUnderBothKeys() throws {
        let object = try json()
        let expected: [(String, String, String)] = [
            ("ScheduledProcedureStepStartDate", "SPSStartDate", "20261001"),
            ("ScheduledProcedureStepStartTime", "SPSStartTime", "0930"),
            ("ScheduledProcedureStepStatus", "SPSStatus", "SCHEDULED"),
            ("ScheduledProcedureStepID", "SPSID", "SPS1"),
            ("ScheduledProcedureStepDescription", "SPSDescription", "CT HEAD"),
            ("ScheduledProcedureStepLocation", "SPSLocation", "ROOM 1"),
            ("ScheduledPerformingPhysicianName", "ScheduledPerformingPhysician", "SMITH^ANN"),
        ]
        for (keyword, legacy, value) in expected {
            XCTAssertEqual(object[keyword] as? String, value, keyword)
            XCTAssertEqual(object[legacy] as? String, value, "deprecated key \(legacy) keeps its value")
        }
    }

    func testSequencesAreArraysOfItemObjects() throws {
        let object = try json()
        let requested = try XCTUnwrap(object["RequestedProcedureCodeSequence"] as? [[String: String]])
        XCTAssertEqual(requested, [["CodeValue": "R1", "CodingSchemeDesignator": "99LOCAL", "CodeMeaning": "CT Head"]])
        XCTAssertEqual(object["RequestedProcedureCode"] as? [String: String], requested.first)

        let protocols = try XCTUnwrap(object["ScheduledProtocolCodeSequence"] as? [[String: String]])
        XCTAssertEqual(protocols.first?["CodeValue"], "P1")
        XCTAssertNotNil(object["ScheduledProtocolCodes"])

        let studies = try XCTUnwrap(object["ReferencedStudySequence"] as? [[String: String]])
        XCTAssertEqual(studies, [
            ["ReferencedSOPClassUID": "1.2.840.10008.3.1.2.3.1", "ReferencedSOPInstanceUID": "1.2.3.4"],
            ["ReferencedSOPClassUID": "1.2.840.10008.3.1.2.3.1", "ReferencedSOPInstanceUID": "1.2.3.5"],
        ])
        XCTAssertEqual(object["ReferencedStudySOPInstanceUID"] as? String, "1.2.3.4", "deprecated key: first item only")
    }

    func testAbsentValuesAddNoKeywordKey() throws {
        let text = NetworkConsole.mwlJSON(items: [WorklistItem(attributes: [:])])
        let object = try XCTUnwrap((JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])?.first)
        XCTAssertTrue(object.isEmpty, "\(object)")
    }
}
