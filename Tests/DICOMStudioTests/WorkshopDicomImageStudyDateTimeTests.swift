// NEMA-verified: 2026a, checked 2026-10-06 — Study Date / Time (0008,0020/0030) Type 2 "Date / Time the Study started" (PS3.3 2026a Table C.7-3), empty when unknown (PS3.5 7.4.3); DA YYYYMMDD and TM HHMMSS.FFFFFF (PS3.5 Table 6.2-1) (P-IMAGE-STUDY-DATETIME)
//
// WorkshopDicomImageStudyDateTimeTests.swift
// DICOMStudioTests
//
// The Workshop's dicom-image form offers --study-date / --study-time with dicom-image's help, and
// its executor applies the same ImageConverter.OutputRules as the CLI: the given values, one run
// moment for a new Study, empty values with --study-uid, and the DA / TM refusals (exit 1).
//

import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import DICOMStudio
@testable import DICOMKit
import DICOMCore

@MainActor
struct WorkshopDicomImageStudyDateTimeTests {

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkshopDicomImageStudyDateTime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePNG(to url: URL) throws {
        let gray: [UInt8] = [0, 64, 128, 255]
        let provider = try #require(CGDataProvider(data: Data(gray) as CFData))
        let image = try #require(CGImage(
            width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 2,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    private func run(_ values: [String: String]) async -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: "dicom-image")
        vm.updateParameterValue(parameterID: "patient-name", value: "DOE^JOHN")
        vm.updateParameterValue(parameterID: "patient-id", value: "P1")
        for (id, value) in values { vm.updateParameterValue(parameterID: id, value: value) }
        await vm.executeCommand()
        return vm
    }

    private func dataSet(_ path: String) throws -> DataSet {
        try DICOMFile.read(from: Data(contentsOf: URL(fileURLWithPath: path))).dataSet
    }

    @Test("the form offers --study-date / --study-time with dicom-image's help")
    func formFields() {
        let params = ToolCatalogHelpers.parameterDefinitions(for: "dicom-image")
        let date = params.first { $0.id == "study-date" }
        let time = params.first { $0.id == "study-time" }
        #expect(date?.flag == "--study-date")
        #expect(time?.flag == "--study-time")
        #expect(date?.helpText == ImageConverter.OutputRules.studyDateHelp)
        #expect(time?.helpText == ImageConverter.OutputRules.studyTimeHelp)
        #expect(date?.defaultValue == nil || date?.defaultValue == "", "no default: the CLI's is nil")
    }

    @Test("given values are written as given; an existing Study without them is written empty")
    func givenAndExistingStudy() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("shot.png")
        try writePNG(to: input)

        let given = root.appendingPathComponent("given.dcm").path
        var vm = await run(["input": input.path, "output": given, "study-uid": "1.2.3.4",
                            "study-date": "20260915", "study-time": "093000"])
        #expect(vm.consoleStatus == .success, "console: \(vm.consoleOutput)")
        #expect(vm.commandPreview.contains("--study-date 20260915"))
        var ds = try dataSet(given)
        #expect(ds.string(for: .studyDate) == "20260915")
        #expect(ds.string(for: .studyTime) == "093000")

        let existing = root.appendingPathComponent("existing.dcm").path
        vm = await run(["input": input.path, "output": existing, "study-uid": "1.2.3.4"])
        #expect(vm.consoleStatus == .success, "console: \(vm.consoleOutput)")
        ds = try dataSet(existing)
        #expect(ds[.studyDate] != nil && (ds.string(for: .studyDate) ?? "") == "", "Type 2: present, empty")
        #expect(ds[.studyTime] != nil && (ds.string(for: .studyTime) ?? "") == "")
    }

    @Test("a new Study's directory run writes one Study Date / Time in every instance")
    func directoryRunSharesOneMoment() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let inputDir = root.appendingPathComponent("in", isDirectory: true)
        try FileManager.default.createDirectory(at: inputDir, withIntermediateDirectories: true)
        for name in ["a", "b", "c"] { try writePNG(to: inputDir.appendingPathComponent("\(name).png")) }
        let outDir = root.appendingPathComponent("out", isDirectory: true)

        let vm = await run(["input": inputDir.path, "output": outDir.path, "recursive": "true"])
        #expect(vm.consoleStatus == .success, "console: \(vm.consoleOutput)")
        let files = try FileManager.default.contentsOfDirectory(atPath: outDir.path).filter { $0.hasSuffix(".dcm") }
        #expect(files.count == 3)
        let values = try Set(files.map { name -> String in
            let ds = try dataSet(outDir.appendingPathComponent(name).path)
            return (ds.string(for: .studyDate) ?? "") + "/" + (ds.string(for: .studyTime) ?? "")
        })
        #expect(values.count == 1, "\(values)")
        #expect(values.first.map { $0.count == 15 } == true, "YYYYMMDD/HHMMSS: \(values)")
    }

    @Test("values that are not DA / TM are refused with the CLI's lines, exit 1, nothing written")
    func refusals() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("shot.png")
        try writePNG(to: input)
        let output = root.appendingPathComponent("bad.dcm").path

        let vm = await run(["input": input.path, "output": output, "study-date": "2026-09-15", "study-time": "14:30"])
        #expect(vm.consoleStatus == .error)
        let expected = ImageConverter.OutputRules.valueViolations(
            patientName: "DOE^JOHN", patientID: "P1", studyDescription: nil, seriesDescription: nil,
            studyUID: nil, seriesUID: nil, seriesNumber: nil, instanceNumber: nil,
            studyDate: "2026-09-15", studyTime: "14:30")
        #expect(expected.count == 2)
        for line in expected { #expect(vm.consoleOutput.contains("Error: " + line)) }
        #expect(!FileManager.default.fileExists(atPath: output))
    }
}
