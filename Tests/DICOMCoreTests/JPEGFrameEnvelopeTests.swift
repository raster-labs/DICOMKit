import Foundation
import Testing
@testable import DICOMCore

@Suite("Fixed JPEG frame envelope")
struct JPEGFrameEnvelopeTests {
    private func segment(_ marker: UInt8, _ payload: [UInt8]) -> [UInt8] {
        let length = payload.count + 2
        return [0xff, marker, UInt8(length >> 8), UInt8(length & 255)] + payload
    }

    private func frame(ids: [UInt8] = [0, 255, 17], scans: [[UInt8]], process: UInt8 = 0xc0,
                       sampling: [UInt8]? = nil,
                       entropy: [UInt8] = [0x32, 0xff, 0, 0xff, 0xd0],
                       applications: [UInt8] = []) -> Data {
        var sof: [UInt8] = [8, 1, 2, 3, 4, UInt8(ids.count)]
        for (index, id) in ids.enumerated() { sof += [id, sampling?[index] ?? UInt8(0x11 + index * 0x10), 0] }
        var bytes = [UInt8(0xff), 0xd8] + applications + segment(process, sof)
        for (index, scan) in scans.enumerated() {
            var sos = [UInt8(scan.count)]
            for id in scan { sos += [id, 0] }
            sos += [UInt8(index), UInt8(63 - index), UInt8(index * 16)]
            bytes += segment(0xda, sos) + entropy
        }
        return Data(bytes + [0xff, 0xd9])
    }

    @Test("Arbitrary identifiers, reordered selectors and every scan partition retain fields",
          arguments: [[[UInt8(17), 0, 255]], [[255], [17, 0]], [[17, 255], [0]], [[17], [0], [255]]])
    func scanPartitions(_ partitions: [[UInt8]]) throws {
        let bytes = frame(scans: partitions)
        let data = try JPEGFrameEnvelope.parse(bytes, jpegLS: false)
        let raw = try bytes.withUnsafeBytes { try JPEGFrameEnvelope.parse($0, jpegLS: false) }
        #expect(data.components == raw.components && data.scanParameters == raw.scanParameters)
        #expect(data.process == 0xc0 && data.width == 772 && data.height == 258 && data.precision == 8)
        #expect(data.components.count == 3 && data.scanParameters.count == partitions.count)
        for (index, id) in [UInt8(0), 255, 17].enumerated() {
            #expect(data.components[index].id == id)
            #expect(data.components[index].sampling == UInt8(0x11 + index * 0x10))
            #expect(data.components.index(of: id) == index)
        }
        #expect(!data.components.hasUnitSampling && !data.components.hasRGBIdentifiers)
        for index in partitions.indices {
            #expect(data.scanParameters[index] == .init(first: index, last: 63 - index, approximation: index * 16))
            #expect(!data.scanParameters.allSatisfy { $0.first != index })
        }
        #expect(data.scanParameters.allSatisfy { $0.last >= 61 })
    }

    @Test("Invalid selectors, coverage, SOF counts and lossless partitions are rejected")
    func invalidComponents() {
        let invalid = [
            frame(scans: [[0, 0, 17]]), frame(scans: [[0, 255, 18]]),
            frame(scans: [[0, 255], [255, 17]]), frame(scans: [[0, 255]]), frame(scans: [[]]),
            frame(scans: [[0], [255], [17], [0]]), frame(ids: [0, 0, 17], scans: [[0, 17]]),
            frame(ids: [], scans: []), frame(ids: [0, 1], scans: [[0, 1]]),
            frame(ids: [0, 1, 2, 3], scans: [[0, 1, 2, 3]]),
            frame(scans: [[0], [255, 17]], process: 0xc3)
        ]
        for bytes in invalid {
            #expect(throws: DICOMError.self) { try JPEGFrameEnvelope.parse(bytes, jpegLS: false) }
        }
    }

    @Test("Process selection, RGB order, application signatures and JPEG-LS stuffing are preserved")
    func processesAndApplications() throws {
        let apps = segment(0xe0, [0x4a, 0x46, 0x49, 0x46, 0]) +
            segment(0xee, [0x41, 0x64, 0x6f, 0x62, 0x65, 0, 0, 0, 0, 0, 0, 1])
        for process: UInt8 in [0xc0, 0xc1, 0xc3, 0xf7] {
            let bytes = frame(ids: [82, 71, 66], scans: [[66, 82, 71]], process: process,
                              entropy: [0xff, process == 0xf7 ? 0x7f : 0, 5], applications: apps)
            let envelope = try JPEGFrameEnvelope.parse(bytes, jpegLS: process == 0xf7)
            #expect(envelope.components.hasRGBIdentifiers && envelope.jfif && envelope.adobeTransform == 1)
            #expect(throws: DICOMError.self) { try JPEGFrameEnvelope.parse(bytes, jpegLS: process != 0xf7) }
        }
        let mono = try JPEGFrameEnvelope.parse(frame(ids: [255], scans: [[255]]), jpegLS: false)
        #expect(mono.components.count == 1 && mono.components.hasUnitSampling)
        let unit = try JPEGFrameEnvelope.parse(frame(scans: [[0, 255, 17]], sampling: [0x11, 0x11, 0x11]),
                                                jpegLS: false)
        let lastNonunit = try JPEGFrameEnvelope.parse(frame(scans: [[0, 255, 17]], sampling: [0x11, 0x11, 0x21]),
                                                       jpegLS: false)
        #expect(unit.components.hasUnitSampling && !lastNonunit.components.hasUnitSampling)
        let reordered = try JPEGFrameEnvelope.parse(frame(ids: [71, 82, 66], scans: [[82, 71, 66]]), jpegLS: false)
        #expect(!reordered.components.hasRGBIdentifiers)
        let malformedApps = segment(0xe0, [0x4a, 0x46, 0x49, 0x46, 1]) +
            segment(0xee, [0x41, 0x64, 0x6f, 0x62, 0x64, 0, 0, 0, 0, 0, 0, 1])
        let unmarked = try JPEGFrameEnvelope.parse(
            frame(scans: [[0, 255, 17]], applications: malformedApps), jpegLS: false)
        #expect(!unmarked.jfif && unmarked.adobeTransform == nil)
    }

    @Test("Marker budget, truncation, standalone markers and final fragment padding retain strict behavior")
    func markerBoundaries() throws {
        let valid = frame(ids: [0], scans: [[0]], entropy: [])
        // SOF, SOS and EOI consume three marker slots.
        let atLimit = frame(ids: [0], scans: [[0]], entropy: [],
                            applications: Array(repeating: segment(0xfe, []), count: 4093).flatMap { $0 })
        _ = try JPEGFrameEnvelope.parse(atLimit, jpegLS: false)
        let overLimit = frame(ids: [0], scans: [[0]], applications:
            Array(repeating: segment(0xfe, []), count: 4094).flatMap { $0 })
        #expect(throws: DICOMError.self) { try JPEGFrameEnvelope.parse(overLimit, jpegLS: false) }
        for end in 0..<valid.count {
            #expect(throws: DICOMError.self) { try JPEGFrameEnvelope.parse(Data(valid.prefix(end)), jpegLS: false) }
        }
        for marker: UInt8 in [0xd8, 0, 0xd0, 1, 0xdc, 0xc2] {
            let invalid = frame(scans: [[0, 255, 17]], applications: segment(marker, []))
            #expect(throws: DICOMError.self) { try JPEGFrameEnvelope.parse(invalid, jpegLS: false) }
        }
        let odd = valid.count % 2 == 1 ? valid : frame(ids: [0], scans: [[0]], entropy: [0x32])
        #expect(odd.count % 2 == 1)
        _ = try JPEGFrameEnvelope.parse(odd + Data([0]), jpegLS: false)
        for suffix in [Data([1]), Data([0, 0]), odd] {
            #expect(throws: DICOMError.self) { try JPEGFrameEnvelope.parse(odd + suffix, jpegLS: false) }
        }
    }

    @Test("Cancellation remains observable before scanning a large stuffed payload")
    func cancellation() async throws {
        let bytes = frame(scans: [[0, 255, 17]],
                          entropy: Array(repeating: [UInt8(0xff), 0], count: 65537).flatMap { $0 })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try JPEGFrameEnvelope.parse(bytes, jpegLS: false)
        }
        do { _ = try await task.value; Issue.record("Cancelled envelope inspection succeeded") }
        catch is CancellationError {}
    }
}
