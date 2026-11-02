import Foundation
import XCTest
import DICOMCore
import DICOMKit
@testable import DICOMStudio

final class M5SRTemporalPrecisionTests: XCTestCase {
    func testTimePrecisionIncludingLeapSecondAndPartialValues() {
        let cases = [("10", "10"), ("1015", "10:15"), ("101530", "10:15:30"),
                     ("101530.1", "10:15:30.1"), ("101530.100000", "10:15:30.100000"),
                     ("101530.123456", "10:15:30.123456"), ("235960.000001", "23:59:60.000001"),
                     ("101530.123456 ", "10:15:30.123456")]
        for (input, expected) in cases {
            XCTAssertEqual(DICOMValueParser.formatTime(input), expected, input)
            XCTAssertEqual(DICOMValueParser.format(value: input, vr: "TM"), expected, input)
        }
    }

    func testDateTimeRetainsEveryLegalPartialPrecisionAndExactOffset() {
        let cases = [("2026", "2026"), ("202610", "2026-10"), ("20261024", "2026-10-24"),
                     ("2026102410", "2026-10-24 10"), ("202610241015", "2026-10-24 10:15"),
                     ("20261024101530", "2026-10-24 10:15:30"),
                     ("20261024101530.1", "2026-10-24 10:15:30.1"),
                     ("20261024101530.100000", "2026-10-24 10:15:30.100000"),
                     ("20261024101530.123456+0530", "2026-10-24 10:15:30.123456 +0530"),
                     ("20261024101530.123456-0330", "2026-10-24 10:15:30.123456 -0330"),
                     ("20261024101530+0000", "2026-10-24 10:15:30 +0000"),
                     ("2026+0530", "2026 +0530"), ("202610-1200", "2026-10 -1200"),
                     ("20261024+1400", "2026-10-24 +1400"),
                     ("20240229235960.000001+0000", "2024-02-29 23:59:60.000001 +0000")]
        for (input, expected) in cases {
            XCTAssertEqual(DICOMValueParser.formatDateTime(input), expected, input)
            XCTAssertEqual(DICOMValueParser.format(value: input, vr: "dt"), expected, input)
        }
    }

    func testDetailedRepresentationsDistinguishFractionsOffsetsAndOmittedSeconds() {
        let times = ["1015", "101530", "101530.1", "101530.100000", "101530.100001"]
        XCTAssertEqual(Set(times.map(DICOMValueParser.formatTime)).count, times.count)
        let dates = ["202610241015", "20261024101530", "20261024101530.1",
                     "20261024101530.100000", "20261024101530.100001",
                     "20261024101530.100001+0530", "20261024101530.100001-0330",
                     "20261024101530.100001+0000"]
        XCTAssertEqual(Set(dates.map(DICOMValueParser.formatDateTime)).count, dates.count)
    }

    func testMalformedTimeIsNeverFilteredTrimmedOrSilentlyRepaired() {
        for input in ["", "1", "101", "10153", "240000", "106000", "101561", ".", "....",
                      "101530.", "101530.1234567", "10.1", "1015.1", "10:15:30", "101530+0530",
                      "101530junk", " 101530", "101530\n", "101530\t", "１０１５３０", "101530\\111530"] {
            XCTAssertEqual(DICOMValueParser.formatTime(input), input, input)
            if !input.isEmpty { XCTAssertEqual(DICOMValueParser.format(value: input, vr: "TM"), input, input) }
        }
    }

    func testMalformedDateTimeIsNeverNormalizedIntoAValidDate() {
        for input in ["", "202", "20261", "202613", "20260230", "2026102424", "202610241060",
                      "20261024101561", "202610241015.1", "20261024101530.", "20261024101530.1234567",
                      "2026-10-24T10:15:30Z", "20261024101530+1460", "20261024101530-1300",
                      "20261024101530-0000", "20261024101530+053", "20261024101530junk",
                      " 20261024101530", "20261024101530\n", "20261024101530\t", "２０２６１０２４"] {
            XCTAssertEqual(DICOMValueParser.formatDateTime(input), input, input)
            if !input.isEmpty { XCTAssertEqual(DICOMValueParser.format(value: input, vr: "DT"), input, input) }
        }
    }

    #if canImport(SwiftUI)
    @MainActor
    func testPhysicalSRFileNarrativeRetainsPrecisionWithoutChangingBytes() throws {
        let cases = Self.narrativeCases
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("m5-sr-\(UUID().uuidString).dcm")
        let external = ProcessInfo.processInfo.environment["DICOMKIT_M5_SR_FIXTURE"]
        let url = external.map { URL(fileURLWithPath: $0) } ?? temporary
        defer { if external == nil { try? FileManager.default.removeItem(at: temporary) } }
        if external == nil { try Self.fileData(cases: cases).write(to: temporary) }
        let before = try Data(contentsOf: url)
        let file = try DICOMFile.read(from: before)
        let originalValues = try XCTUnwrap(file.dataSet.sequence(for: .contentSequence)).map {
            $0[.time]?.valueData ?? $0[.dateTime]?.valueData ?? Data()
        }
        guard case .report(let document) = ViewerNonImageContentReader.content(of: file.dataSet,
            sopClassUID: file.dataSet.string(for: .sopClassUID), transferSyntaxUID: file.transferSyntaxUID) else {
            return XCTFail("Synthetic SR did not reach the actual report viewer")
        }
        let rows = StructuredReportNarrativeView(document: document).rows
        XCTAssertEqual(rows.count, cases.count)
        XCTAssertEqual(rows.compactMap(\.value), cases.map(\.expected))
        // The same row.value String is displayed verbatim and exposed through
        // the existing text-selection copy path. Clipboard/UI execution is a
        // separate packaged-app gate; this test does not claim to exercise it.
        XCTAssertEqual(try Data(contentsOf: url), before)
        let afterValues = try XCTUnwrap(file.dataSet.sequence(for: .contentSequence)).map {
            $0[.time]?.valueData ?? $0[.dateTime]?.valueData ?? Data()
        }
        XCTAssertEqual(afterValues, originalValues)
        if let path = ProcessInfo.processInfo.environment["DICOMKIT_M5_SR_RESULTS"] {
            let output = zip(cases, rows).map { sample, row in
                ["label": sample.label, "vr": sample.vr, "raw": sample.raw, "display": row.value ?? ""]
            }
            try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: path))
        }
    }
    #endif

    private struct Sample: Sendable { let label: String; let vr: String; let raw: String; let expected: String }
    private static let narrativeCases: [Sample] = [
        .init(label: "TIME fraction", vr: "TM", raw: "101530.123456", expected: "10:15:30.123456"),
        .init(label: "TIME next fraction", vr: "TM", raw: "101530.123457", expected: "10:15:30.123457"),
        .init(label: "TIME trailing zeros", vr: "TM", raw: "101530.120000", expected: "10:15:30.120000"),
        .init(label: "TIME hour", vr: "TM", raw: "10", expected: "10"),
        .init(label: "TIME minute", vr: "TM", raw: "1015", expected: "10:15"),
        .init(label: "DATETIME positive offset", vr: "DT", raw: "20261024101530.123456+0530", expected: "2026-10-24 10:15:30.123456 +0530"),
        .init(label: "DATETIME negative offset", vr: "DT", raw: "20261024101530.123456-0330", expected: "2026-10-24 10:15:30.123456 -0330"),
        .init(label: "DATETIME year", vr: "DT", raw: "2026", expected: "2026"),
        .init(label: "DATETIME month", vr: "DT", raw: "202610", expected: "2026-10"),
        .init(label: "DATETIME date", vr: "DT", raw: "20261024", expected: "2026-10-24"),
        .init(label: "DATETIME hour", vr: "DT", raw: "2026102410", expected: "2026-10-24 10"),
        .init(label: "DATETIME minute", vr: "DT", raw: "202610241015", expected: "2026-10-24 10:15"),
        .init(label: "DATETIME zeros UTC", vr: "DT", raw: "20261024101530.120000+0000", expected: "2026-10-24 10:15:30.120000 +0000"),
        .init(label: "DATETIME partial offset", vr: "DT", raw: "2026+0530", expected: "2026 +0530"),
        .init(label: "Malformed TIME retained", vr: "TM", raw: "101530.1234567", expected: "101530.1234567"),
        .init(label: "Malformed DATETIME retained", vr: "DT", raw: "20260230101530+0530", expected: "20260230101530+0530")
    ]

    private static func fileData(cases: [Sample]) throws -> Data {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.88.11", for: .sopClassUID, vr: .UI)
        ds.setString("2.25.550001", for: .sopInstanceUID, vr: .UI)
        ds.setString("2.25.550002", for: .studyInstanceUID, vr: .UI)
        ds.setString("2.25.550003", for: .seriesInstanceUID, vr: .UI)
        ds.setString("M5^Temporal^Synthetic", for: .patientName, vr: .PN)
        ds.setString("M5SR001", for: .patientID, vr: .LO)
        ds.setString("SR", for: .modality, vr: .CS)
        ds.setString("CONTAINER", for: .valueType, vr: .CS)
        ds.setString("SEPARATE", for: .continuityOfContent, vr: .CS)
        ds.setSequence(cases.enumerated().map { index, sample in
            var item = DataSet(), concept = DataSet()
            item.setString("CONTAINS", for: .relationshipType, vr: .CS)
            item.setString(sample.vr == "TM" ? "TIME" : "DATETIME", for: .valueType, vr: .CS)
            item.setString(sample.raw, for: sample.vr == "TM" ? .time : .dateTime, vr: sample.vr == "TM" ? .TM : .DT)
            concept.setString("M5T\(index)", for: .codeValue, vr: .SH)
            concept.setString("99DICOMKIT", for: .codingSchemeDesignator, vr: .SH)
            concept.setString(sample.label, for: .codeMeaning, vr: .LO)
            item.setSequence([SequenceItem(elements: concept.allElements)], for: .conceptNameCodeSequence)
            return SequenceItem(elements: item.allElements)
        }, for: .contentSequence)
        return try DICOMFile.create(dataSet: ds).write()
    }
}
