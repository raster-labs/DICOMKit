import Foundation
import XCTest
import DICOMCore
import DICOMKit
@testable import DICOMStudio

private extension Data {
    mutating func appendBE32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { self.append(contentsOf: $0) }
    }
    mutating func appendBE16(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.bigEndian) { self.append(contentsOf: $0) }
    }
}

@MainActor
final class WorkshopVideoStudyDateTimeTests: XCTestCase {
    private func box(_ type: String, _ payload: Data) -> Data {
        var data = Data()
        data.appendBE32(UInt32(payload.count + 8))
        data.append(contentsOf: Array(type.utf8))
        data.append(payload)
        return data
    }

    private func ftyp(major: String = "isom",
                      compatible: [String] = ["isom", "mp41", "avc1"]) -> Data {
        var payload = Data(major.utf8)
        payload.appendBE32(512)
        for brand in compatible { payload.append(contentsOf: Array(brand.utf8)) }
        return box("ftyp", payload)
    }

    private func mdhd(timescale: UInt32, duration: UInt32) -> Data {
        var payload = Data()
        payload.appendBE32(0)
        payload.appendBE32(0)
        payload.appendBE32(0)
        payload.appendBE32(timescale)
        payload.appendBE32(duration)
        payload.appendBE16(0x55C4)
        payload.appendBE16(0)
        return box("mdhd", payload)
    }

    private func hdlr(handler: String) -> Data {
        var payload = Data()
        payload.appendBE32(0)
        payload.appendBE32(0)
        payload.append(contentsOf: Array(handler.utf8))
        payload.append(Data(repeating: 0, count: 12))
        payload.append(contentsOf: Array("Handler\0".utf8))
        return box("hdlr", payload)
    }

    /// An AVCDecoderConfigurationRecord: parameter sets stored without their NAL
    /// headers and length-prefixed (ISO/IEC 14496-15 5.3.3.1).
    private func avcC(sps: [Data], pps: [Data]) -> Data {
        var payload = Data([0x01, 0x64, 0x00, 0x29, 0xFF])
        payload.append(UInt8(0xE0 | sps.count))
        for set in sps {
            payload.appendBE16(UInt16(set.count))
            payload.append(set)
        }
        payload.append(UInt8(pps.count))
        for set in pps {
            payload.appendBE16(UInt16(set.count))
            payload.append(set)
        }
        return box("avcC", payload)
    }

    private func visualSampleEntry(
        format: String, width: UInt16, height: UInt16, extensions: Data
    ) -> Data {
        var payload = Data(repeating: 0, count: 6)
        payload.appendBE16(1)
        payload.appendBE16(0)
        payload.appendBE16(0)
        payload.append(Data(repeating: 0, count: 12))
        payload.appendBE16(width)
        payload.appendBE16(height)
        payload.appendBE32(0x0048_0000)
        payload.appendBE32(0x0048_0000)
        payload.appendBE32(0)
        payload.appendBE16(1)
        payload.append(Data(repeating: 0, count: 32))
        payload.appendBE16(24)
        payload.appendBE16(0xFFFF)
        XCTAssertEqual(payload.count, 78, "VisualSampleEntry payload is 78 bytes")
        payload.append(extensions)
        return box(format, payload)
    }

    private func stsz(sampleCount: UInt32) -> Data {
        var payload = Data()
        payload.appendBE32(0)
        payload.appendBE32(1000)
        payload.appendBE32(sampleCount)
        return box("stsz", payload)
    }

    private func stsd(_ entry: Data) -> Data {
        var payload = Data()
        payload.appendBE32(0)
        payload.appendBE32(1)
        payload.append(entry)
        return box("stsd", payload)
    }

    private func videoTrack(
        sampleEntry: Data, frameCount: UInt32, timescale: UInt32 = 30000,
        duration: UInt32, handler: String = "vide"
    ) -> Data {
        let stbl = box("stbl", stsd(sampleEntry) + stsz(sampleCount: frameCount))
        let minf = box("minf", stbl)
        let mdia = box("mdia", mdhd(timescale: timescale, duration: duration)
                       + hdlr(handler: handler) + minf)
        return box("trak", mdia)
    }

    private func mp4File(tracks: [Data], major: String = "isom",
                         compatible: [String] = ["isom", "mp41", "avc1"]) -> Data {
        var moovPayload = Data()
        for track in tracks { moovPayload.append(track) }
        return ftyp(major: major, compatible: compatible)
            + box("moov", moovPayload)
            + box("mdat", Data(repeating: 0xAB, count: 64))
    }

    /// The 1080p High@4.1 SPS with its 0x67 NAL header, as avcC stores it:
    /// ISO/IEC 14496-15 keeps whole NAL units in the configuration record.
    private static let spsH264Unit = Data([
        0x67,
        0x64, 0x00, 0x29, 0xAC, 0xB4, 0x03, 0xC0, 0x11, 0x3F, 0x2C, 0x20,
        0x00, 0x00, 0x03, 0x00, 0x20, 0x00, 0x00, 0x07, 0x98,
    ])

    /// A conformant 1080p30 High@4.1 clip in an MP4 container.
    private func h264MP4(frameCount: UInt32 = 300) -> Data {
        let entry = visualSampleEntry(
            format: "avc1", width: 1920, height: 1080,
            extensions: avcC(sps: [Self.spsH264Unit], pps: [Data([0xEE, 0x3C, 0xB0])])
        )
        return mp4File(tracks: [videoTrack(
            sampleEntry: entry, frameCount: frameCount, duration: 300_000)])
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("video-study-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func model(input: URL, output: URL, date: String, time: String) -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: "dicom-video")
        for (id, value) in ["operation": "convert", "input": input.path, "output": output.path,
                            "type": "photographic", "studyUID": "1.2.3.4", "studyDate": date,
                            "studyTime": time, "trustInput": "false",
                            "transferSyntax": "1.2.840.10008.1.2.4.102"] {
            vm.updateParameterValue(parameterID: id, value: value)
        }
        return vm
    }

    func testWorkshopExecutionWritesStudyStartAndUnknownValues() async throws {
        let root = try directory()
        let input = root.appendingPathComponent("synthetic.mp4")
        // Construct ISO-BMFF metadata in memory, as VideoConsoleParityTests does;
        // independent real-video coverage is provided by the CLI/DCMTK check.
        try h264MP4().write(to: input)
        for (index, pair) in [("20240229", "102030.123456"), ("20240229", ""), ("", "1020"), ("", "")].enumerated() {
            for operation in ["convert", "batch-single", "batch-per-file"] {
                let output = root.appendingPathComponent("\(operation)-\(index).dcm")
                let vm = model(input: input, output: output, date: pair.0, time: pair.1)
                if operation != "convert" {
                    vm.updateParameterValue(parameterID: "operation", value: "batch")
                    vm.updateParameterValue(parameterID: "inputDirectory", value: root.path)
                    vm.updateParameterValue(parameterID: "outputDir", value: output.path)
                    vm.updateParameterValue(parameterID: "seriesMode", value: operation == "batch-single" ? "single" : "per-file")
                }
                for mode in [CLIExperienceMode.beginner, .advanced] {
                    vm.experienceMode = mode
                    let rendered = vm.visibleParameters() + vm.advancedParameters()
                    XCTAssertEqual(rendered.filter { $0.id == "studyDate" }.count, 1)
                    XCTAssertEqual(rendered.filter { $0.id == "studyTime" }.count, 1)
                }
                await vm.executeCommand()
                XCTAssertEqual(vm.commandHistory.last?.exitCode, 0, vm.consoleOutput)
                let file = operation == "convert" ? output : output.appendingPathComponent("synthetic.dcm")
                let ds = try DICOMFile.read(from: Data(contentsOf: file)).dataSet
                for (tag, vr, expected) in [(Tag(group: 0x0008, element: 0x0020), VR.DA, pair.0),
                                            (Tag(group: 0x0008, element: 0x0030), VR.TM, pair.1)] {
                    let element = try XCTUnwrap(ds[tag])
                    XCTAssertEqual(element.vr, vr)
                    XCTAssertEqual(String(decoding: element.valueData, as: UTF8.self).trimmingCharacters(in: .whitespaces), expected)
                }
            }
        }
    }

    func testWorkshopRejectsInvalidStudyValuesWithoutWriting() async throws {
        let root = try directory()
        let input = root.appendingPathComponent("unread.ts")
        try Data("must not be parsed".utf8).write(to: input)
        for operation in ["convert", "batch"] {
            for (date, time, flag) in [("20230229", "102030", "--study-date"),
                                       ("20240229", "24", "--study-time"),
                                       ("2024.02.29", "102030", "--study-date"),
                                       ("20240229", "10:20:30", "--study-time")] {
                let output = root.appendingPathComponent("must-not-exist")
                let vm = model(input: input, output: output, date: date, time: time)
                vm.updateParameterValue(parameterID: "operation", value: operation)
                vm.updateParameterValue(parameterID: "inputDirectory", value: root.path)
                vm.updateParameterValue(parameterID: "outputDir", value: output.path)
                await vm.executeCommand()
                XCTAssertEqual(vm.commandHistory.last?.exitCode, 1, vm.consoleOutput)
                XCTAssertTrue(vm.consoleOutput.contains(flag), vm.consoleOutput)
                XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            }
        }
    }
}
