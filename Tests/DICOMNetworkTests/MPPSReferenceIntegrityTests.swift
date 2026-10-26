import Foundation
import XCTest
@testable import DICOMNetwork

#if canImport(Network)
final class MPPSReferenceIntegrityTests: XCTestCase {
    private let classes = ["1.2.840.10008.5.1.4.1.1.2", "1.2.840.10008.5.1.4.1.1.4", "1.2.840.10008.5.1.4.1.1.7"]

    private func references(_ classes: [String]) -> [MPPSReferencedInstance] {
        classes.enumerated().map { MPPSReferencedInstance(sopClassUID: $0.element, sopInstanceUID: "2.25.\($0.offset + 100)") }
    }

    // Independent TLV reader for the MPPS sequence structure. It verifies element
    // and item lengths and never searches raw byte substrings for UID/tag matches.
    private struct Element {
        let tag: UInt32
        let value: Data
        let items: [[Element]]
        var text: String { String(decoding: value, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) }
    }
    private enum ReadError: Error { case truncated, invalidLength, invalidStructure }
    private func decode(_ data: Data, explicit: Bool) throws -> [Element] {
        let bytes = [UInt8](data)
        var offset = 0
        func integer(_ count: Int) throws -> UInt32 {
            guard offset + count <= bytes.count else { throw ReadError.truncated }
            defer { offset += count }
            return (0..<count).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
        }
        func elements(until delimiter: UInt32? = nil) throws -> [Element] {
            var result: [Element] = []
            while offset < bytes.count {
                let group = try integer(2), element = try integer(2)
                let tag = group << 16 | element
                if tag == delimiter {
                    guard try integer(4) == 0 else { throw ReadError.invalidLength }
                    return result
                }
                guard group != 0xFFFE else { throw ReadError.invalidStructure }
                let length: UInt32
                let sequence: Bool
                if explicit {
                    let vr = try integer(2)
                    let text = String(bytes: [UInt8(vr & 255), UInt8(vr >> 8)], encoding: .ascii) ?? ""
                    sequence = text == "SQ"
                    if ["SQ", "OB", "OD", "OF", "OL", "OV", "OW", "UC", "UR", "UT", "UN"].contains(text) {
                        guard try integer(2) == 0 else { throw ReadError.invalidStructure }
                        length = try integer(4)
                    } else { length = try integer(2) }
                } else {
                    length = try integer(4)
                    sequence = [UInt32(0x00400340), 0x00081140, 0x00400220].contains(tag)
                }
                if sequence {
                    guard length == UInt32.max else { throw ReadError.invalidStructure }
                    var items: [[Element]] = []
                    while true {
                        let itemGroup = try integer(2), itemElement = try integer(2), itemLength = try integer(4)
                        guard itemGroup == 0xFFFE else { throw ReadError.invalidStructure }
                        if itemElement == 0xE0DD {
                            guard itemLength == 0 else { throw ReadError.invalidLength }
                            break
                        }
                        guard itemElement == 0xE000, itemLength == UInt32.max else { throw ReadError.invalidStructure }
                        items.append(try elements(until: 0xFFFEE00D))
                    }
                    result.append(Element(tag: tag, value: Data(), items: items))
                } else {
                    guard length != UInt32.max, offset + Int(length) <= bytes.count else { throw ReadError.invalidLength }
                    let value = Data(bytes[offset..<(offset + Int(length))])
                    offset += Int(length)
                    result.append(Element(tag: tag, value: value, items: []))
                }
            }
            guard delimiter == nil else { throw ReadError.truncated }
            return result
        }
        return try elements()
    }

    private func decodedReferences(_ data: Data, explicit: Bool) throws -> [MPPSReferencedInstance] {
        let root = try decode(data, explicit: explicit)
        let series = try XCTUnwrap(root.first { $0.tag == 0x00400340 })
        return try series.items.flatMap { item in
            let images = try XCTUnwrap(item.first { $0.tag == 0x00081140 })
            return try images.items.map { image in
                MPPSReferencedInstance(sopClassUID: try XCTUnwrap(image.first { $0.tag == 0x00081150 }).text,
                    sopInstanceUID: try XCTUnwrap(image.first { $0.tag == 0x00081155 }).text)
            }
        }
    }

    func testEncodedReferencesPreserveCTMRSCAndMixedPairs() throws {
        for group in classes.map({ [$0] }) + [classes] {
            let expected = references(group)
            let step = MPPSProcedureStep(sopInstanceUID: "2.25.1", status: .completed, endDateTime: Date(),
                performedSeries: [MPPSPerformedSeries(seriesInstanceUID: "2.25.2", protocolName: "M2", referencedImages: expected)])
            try DICOMMPPSService.validate(step, for: .nSet)
            for explicit in [true, false] {
                let data = DICOMMPPSService.buildNSetAttributes(procedureStep: step,
                    includeScheduledStepAttributes: false,
                    transferSyntax: explicit ? explicitVRLittleEndianTransferSyntaxUID : implicitVRLittleEndianTransferSyntaxUID)
                XCTAssertEqual(try decodedReferences(data, explicit: explicit), expected)
            }
        }
    }

    func testMissingAndMalformedClassesRefuseBeforeNetworking() async throws {
        for classUID in [nil, "", "1..2"] as [String?] {
            for description in [nil, "series"] as [String?] {
                do {
                    try await DICOMMPPSService.update(host: "host.invalid", callingAE: "M2", calledAE: "M2",
                        mppsInstanceUID: "2.25.1", status: .completed,
                        referencedSOPs: [("2.25.2", "2.25.3", "2.25.4")],
                        referencedSOPClassUID: classUID, seriesDescription: description)
                    XCTFail("Ambiguous or malformed reference was accepted")
                } catch DICOMNetworkError.invalidState(let message) {
                    XCTAssertTrue(message.contains("SOP Class") || message.contains("Class/Instance"), message)
                } catch { XCTFail("Expected preflight refusal, got \(error)") }
            }
        }
    }

    func testTypedPairsRejectMissingClassOrInstanceUID() throws {
        for reference in [MPPSReferencedInstance(sopClassUID: "", sopInstanceUID: "2.25.1"),
                          MPPSReferencedInstance(sopClassUID: classes[0], sopInstanceUID: "1..2")] {
            let step = MPPSProcedureStep(sopInstanceUID: "2.25.2", status: .completed, endDateTime: Date(),
                performedSeries: [MPPSPerformedSeries(seriesInstanceUID: "2.25.3", protocolName: "M2", referencedImages: [reference])])
            XCTAssertThrowsError(try DICOMMPPSService.validate(step, for: .nSet))
        }
    }

    func testCapturedNSetPreservesActualClassesWithBothTransferSyntaxes() async throws {
        for explicit in [true, false] {
            let scp = MockPrintSCP(behavior: MockPrintSCPBehavior(acceptOnlyImplicitVR: !explicit))
            try await scp.start()
            do {
                let port = await scp.port
                for (index, group) in (classes.map({ [$0] }) + [classes]).enumerated() {
                    let expected = references(group)
                    try await DICOMMPPSService.update(host: "127.0.0.1", port: port,
                        callingAE: "M2", calledAE: "M2", mppsInstanceUID: "2.25.820.\(explicit ? 1 : 2).\(index + 1)", status: .completed,
                        performedSeries: [MPPSPerformedSeries(seriesInstanceUID: "2.25.2", protocolName: "M2", referencedImages: expected)])
                    let captured = await scp.receivedDataSets
                    XCTAssertEqual(try decodedReferences(XCTUnwrap(captured.last), explicit: explicit), expected)
                }
            } catch {
                await scp.stop()
                throw error
            }
            await scp.stop()
        }
    }

    /// Opt-in peer for manual packaged-app qualification; deliberately skipped
    /// during ordinary automated runs. Dataset files contain synthetic test data.
    func testManualMPPSCapturePeer() async throws {
        guard let path = ProcessInfo.processInfo.environment["DICOMKIT_M2_CAPTURE_DIR"], !path.isEmpty else {
            throw XCTSkip("Set DICOMKIT_M2_CAPTURE_DIR only for the manual packaged-app capture session")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scp = MockPrintSCP()
        try await scp.start()
        do {
            let port = await scp.port
            let ready: [String: Any] = ["host": "127.0.0.1", "port": port,
                "transferSyntax": explicitVRLittleEndianTransferSyntaxUID,
                "stopFile": directory.appendingPathComponent("stop").path]
            try JSONSerialization.data(withJSONObject: ready, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("ready.json"), options: .atomic)
            let deadline = Date().addingTimeInterval(600)
            var saved = 0
            repeat {
                let dataSets = await scp.receivedDataSets
                while saved < dataSets.count {
                    let data = dataSets[saved]
                    try data.write(to: directory.appendingPathComponent(String(format: "request-%03d.dcmdata", saved + 1)), options: .atomic)
                    let references = try decodedReferences(data, explicit: true)
                    let pairs = references.map { ["sopClassUID": $0.sopClassUID, "sopInstanceUID": $0.sopInstanceUID] }
                    try JSONSerialization.data(withJSONObject: pairs, options: [.prettyPrinted, .sortedKeys])
                        .write(to: directory.appendingPathComponent(String(format: "request-%03d.json", saved + 1)), options: .atomic)
                    saved += 1
                }
                if FileManager.default.fileExists(atPath: directory.appendingPathComponent("stop").path) { break }
                try await Task.sleep(for: .milliseconds(200))
            } while Date() < deadline
            let counts = ["associations": await scp.associationCount, "capturedDataSets": saved]
            try JSONSerialization.data(withJSONObject: counts, options: [.sortedKeys])
                .write(to: directory.appendingPathComponent("finished.json"), options: .atomic)
        } catch {
            await scp.stop()
            throw error
        }
        await scp.stop()
    }
}
#endif
