import Foundation
import XCTest
import DICOMCore
@testable import DICOMNetwork

/// NET-04-A: a filter must affect the Identifier or prevent dispatch. Query
/// expressions deliberately use PS3.4 matching grammar, not stored DA/TM rules.
final class QueryFilterPreflightTests: XCTestCase {
    func testEveryBuilderFilterIsEitherEmittedOrRefusedAtEveryLevel() {
        let levels: [QueryLevel] = [.patient, .study, .series, .image]
        let cases: [(String, (QueryLevel) -> QueryKeys, [QueryLevel])] = [
            ("DOE*", { DICOMQueryService.buildQueryKeys(level: $0, patientName: "DOE*") }, [.patient, .study]),
            ("P1", { DICOMQueryService.buildQueryKeys(level: $0, patientID: "P1") }, [.patient, .study]),
            ("20260101-20260331", { DICOMQueryService.buildQueryKeys(level: $0, studyDate: "20260101-20260331") }, [.study]),
            ("CT", { DICOMQueryService.buildQueryKeys(level: $0, modality: "CT") }, [.study, .series]),
            ("ACC*", { DICOMQueryService.buildQueryKeys(level: $0, accession: "ACC*") }, [.study]),
            ("CHE?T*", { DICOMQueryService.buildQueryKeys(level: $0, studyDescription: "CHE?T*") }, [.study]),
            ("SMITH*", { DICOMQueryService.buildQueryKeys(level: $0, referringPhysician: "SMITH*") }, [.study]),
            ("1.2", { DICOMQueryService.buildQueryKeys(level: $0, studyUID: "1.2") }, [.study, .series, .image]),
            ("1.2.3", { DICOMQueryService.buildQueryKeys(level: $0, seriesUID: "1.2.3") }, [.series, .image]),
            ("20260101-", { DICOMQueryService.buildQueryKeys(level: $0, seriesDate: "20260101-") }, [.series]),
            ("1.2.3.4", { DICOMQueryService.buildQueryKeys(level: $0, instanceUID: "1.2.3.4") }, [.image])
        ]
        for (value, build, supported) in cases {
            for level in levels {
                let keys = build(level)
                if supported.contains(level) {
                    XCTAssertNil(keys.rejectionReason, "\(value) at \(level)")
                    XCTAssertTrue(keys.keys.contains { $0.value == value })
                    XCTAssertTrue(DICOMQueryService.appliedFilters(in: keys).contains { $0.value == value })
                } else {
                    XCTAssertNotNil(keys.rejectionReason, "\(value) at \(level)")
                    XCTAssertTrue(DICOMQueryService.appliedFilters(in: keys).isEmpty)
                }
            }
        }
    }

    func testRefusalSurvivesNonBaselineReturnKeysAndFluentCopies() {
        let keys = DICOMQueryService.buildQueryKeys(level: .image, modality: "CT",
            studyUID: "1.2", seriesUID: "1.2.3", includeParentLevelReturnKeys: true)
        XCTAssertTrue(keys.rejectionReason?.contains("Modality (--modality)") == true)
        XCTAssertEqual(keys.keys.first { $0.tag == .modality }?.value, "")
        XCTAssertEqual(keys.requestPatientID().rejectionReason, keys.rejectionReason)
        XCTAssertTrue(DICOMQueryService.appliedFilters(in: keys).isEmpty)
    }

    func testUnsupportedFilterFailsBeforeTransport() async throws {
        let keys = DICOMQueryService.buildQueryKeys(level: .image, modality: "CT",
            studyUID: "1.2", seriesUID: "1.2.3")
        let config = QueryConfiguration(callingAETitle: try AETitle("M3"), calledAETitle: try AETitle("SCP"))
        do {
            _ = try await DICOMQueryService.find(host: "host.invalid", configuration: config, queryKeys: keys)
            XCTFail("Unsupported filters must fail before opening an association")
        } catch DICOMNetworkError.invalidState(let message) {
            XCTAssertEqual(message, keys.rejectionReason)
        } catch {
            XCTFail("Expected preflight refusal, not a transport error: \(error)")
        }
    }

    func testAcceptedIdentifiersCarryCorrectModalityTagsAndUnchangedQueryExpressions() throws {
        for explicit in [false, true] {
            let syntax = explicit ? explicitVRLittleEndianTransferSyntaxUID : implicitVRLittleEndianTransferSyntaxUID
            let study = DICOMQueryService.buildQueryKeys(level: .study, patientName: "DOE*",
                studyDate: "20260101-20260331", modality: "CT", studyDescription: "CHE?T*", studyUID: "1.2\\1.3")
                .matching(.studyTime, value: "090000-170000", vr: .TM)
            let studyBytes = DICOMQueryService.buildQueryIdentifier(level: .study, queryKeys: study, transferSyntax: syntax)
            let studyValues = try decode(studyBytes, explicit: explicit)
            XCTAssertEqual(studyValues[0x00080061], "CT")
            XCTAssertNil(studyValues[0x00080060])
            XCTAssertEqual(studyValues[0x00080020], "20260101-20260331")
            XCTAssertEqual(studyValues[0x00080030], "090000-170000")
            XCTAssertEqual(studyValues[0x00100010], "DOE*")
            XCTAssertEqual(studyValues[0x00081030], "CHE?T*")
            XCTAssertEqual(studyValues[0x0020000D], "1.2\\1.3")
            XCTAssertEqual(studyValues[0x00080052], "STUDY")
            let series = DICOMQueryService.buildQueryKeys(level: .series, modality: "CT", studyUID: "1.2")
            let seriesValues = try decode(DICOMQueryService.buildQueryIdentifier(level: .series,
                queryKeys: series, transferSyntax: syntax), explicit: explicit)
            XCTAssertEqual(seriesValues[0x00080060], "CT")
            XCTAssertNil(seriesValues[0x00080061])
            XCTAssertEqual(seriesValues[0x0020000D], "1.2")
            XCTAssertEqual(seriesValues[0x00080052], "SERIES")
            XCTAssertEqual(DICOMQueryService.appliedFilters(in: series).map(\.value), ["CT", "1.2"])
        }
    }

    // Small independent reader of the short textual VRs emitted above; avoids
    // validating the encoder with the production decoder of the same module.
    private func decode(_ data: Data, explicit: Bool) throws -> [UInt32: String] {
        let bytes = [UInt8](data)
        func u16(_ offset: Int) -> UInt32 { UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 }
        var offset = 0
        var values: [UInt32: String] = [:]
        while offset < bytes.count {
            guard offset + 8 <= bytes.count else { throw NSError(domain: "Truncated element", code: 1) }
            let tag = u16(offset) << 16 | u16(offset + 2)
            let length: Int
            if explicit {
                length = Int(u16(offset + 6))
            } else {
                length = Int(u16(offset + 4) | u16(offset + 6) << 16)
            }
            offset += 8
            guard offset + length <= bytes.count else { throw NSError(domain: "Truncated value", code: 2) }
            XCTAssertNil(values[tag], "Repeated tag")
            values[tag] = String(decoding: bytes[offset..<(offset + length)], as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
            offset += length
        }
        return values
    }
}
