import Foundation
import Testing
import DICOMCore
import DICOMKit
@testable import DICOMStudio

/// These execute real in-process Workshop routes against isolated files. A test
/// runner is not the sandboxed app: the native Browse permission check remains a
/// separate acceptance gate, while these tests pin target identity and bytes.
@Suite("M7 Workshop grants do not replace requested paths", .serialized)
@MainActor
struct M7WorkshopFileAccessTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workshop-paths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixture(at url: URL, patient: String, uid: String = "2.25.123456789") throws -> Data {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString(uid, for: .sopInstanceUID, vr: .UI)
        ds.setString("2.25.1234567", for: .studyInstanceUID, vr: .UI)
        ds.setString("2.25.12345678", for: .seriesInstanceUID, vr: .UI)
        ds.setString(patient, for: .patientName, vr: .PN)
        ds.setString("SYNTHETIC", for: .patientID, vr: .LO)
        ds.setUInt16(2, for: .rows)
        ds.setUInt16(2, for: .columns)
        ds.setUInt16(8, for: .bitsAllocated)
        ds.setUInt16(8, for: .bitsStored)
        ds.setUInt16(7, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds[.pixelData] = DataElement(tag: .pixelData, vr: .OB, length: 4, valueData: Data([0, 32, 128, 255]))
        let data = try DICOMFile.create(dataSet: ds).write()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return data
    }

    private func model(_ tool: String, _ values: [String: String] = [:]) -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
        vm.selectTool(id: tool)
        for (key, value) in values { vm.updateParameterValue(parameterID: key, value: value) }
        return vm
    }

    @Test("Folder grant plus typed output filename is preserved for tags and conversion", arguments: ["dicom-tags", "dicom-convert"])
    func typedFileWithinFolder(tool: String) async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("input O'Neil; snow 雪.dcm")
        let original = try fixture(at: input, patient: "ORIGINAL^Patient")
        let outDir = dir.appendingPathComponent("selected-output", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let target = outDir.appendingPathComponent("nested/exact requested.dcm")
        let vm = model(tool, ["inputPath": input.path, "format": "dicom", "force": "true"])
        vm.setSecurityScopedURL(outDir, forParameterID: "output")
        vm.updateParameterValue(parameterID: "output", value: target.path)
        if tool == "dicom-tags" {
            vm.updateParameterValue(parameterID: "set", value: "PatientID=EXACT-TARGET")
        } else {
            vm.updateParameterValue(parameterID: "transfer-syntax", value: TransferSyntax.explicitVRLittleEndian.uid)
        }
        #expect(vm.securityScopedURLs["output"] == outDir)
        #expect(vm.commandPreview.contains("exact requested.dcm"))
        await vm.executeCommand()
        #expect(vm.consoleStatus == .success, "\(vm.consoleOutput)")
        #expect(vm.commandHistory.first?.exitCode == 0)
        let actual = try DICOMFile.read(from: Data(contentsOf: target))
        #expect(actual.dataSet[.pixelData]?.valueData == Data([0, 32, 128, 255]))
        #expect(actual.dataSet.string(for: .patientName) == "ORIGINAL^Patient")
        if tool == "dicom-tags" { #expect(actual.dataSet.string(for: .patientID) == "EXACT-TARGET") }
        #expect(try Data(contentsOf: input) == original)
        #expect(!FileManager.default.fileExists(atPath: outDir.appendingPathComponent(input.lastPathComponent).path))
        #expect(!FileManager.default.fileExists(atPath: outDir.appendingPathComponent("output.dat").path))
        #expect(vm.securityScopedURLs["output"] == outDir)
    }

    @Test("Changed input file cannot execute the previously browsed file", arguments: ["dicom-info", "dicom-dump"])
    func changedInput(tool: String) async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appendingPathComponent("first.dcm"), second = dir.appendingPathComponent("second.dcm")
        let original = try fixture(at: first, patient: "STALE^Selection")
        let secondBytes = try fixture(at: second, patient: "CURRENT^Selection", uid: "2.25.987654321")
        let vm = model(tool)
        vm.setSecurityScopedURL(first, forParameterID: "inputPath")
        vm.updateParameterValue(parameterID: "inputPath", value: second.path)
        #expect(vm.securityScopedURLs["inputPath"] == nil)
        await vm.executeCommand()
        #expect(vm.consoleStatus == .success, "\(vm.consoleOutput)")
        if tool == "dicom-dump" {
            // Decode the independent hex-column representation; a PN can span
            // several 16-byte lines, so contiguous text is not the dump contract.
            var dumped = Data()
            for line in vm.consoleOutput.split(separator: "\n") {
                guard let hexEnd = line.firstIndex(of: "|") else { continue }
                let fields = line[..<hexEnd].split(whereSeparator: { $0.isWhitespace })
                guard fields.first?.count == 8 else { continue }
                for field in fields.dropFirst() {
                    let byte = try #require(UInt8(field, radix: 16))
                    dumped.append(byte)
                }
            }
            #expect(dumped == secondBytes)
            #expect(dumped != original)
        } else {
            #expect(vm.consoleOutput.contains("CURRENT^Selection"))
            #expect(!vm.consoleOutput.contains("STALE^Selection"))
        }
        #expect(try Data(contentsOf: first) == original)
    }

    @Test("Directory input and copy-source grants select typed child files, not their directories")
    func directoryToChildAndCopy() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("input.dcm"), source = dir.appendingPathComponent("source.dcm")
        let inputBytes = try fixture(at: input, patient: "INPUT^Patient")
        let sourceBytes = try fixture(at: source, patient: "COPY^Patient", uid: "2.25.222222")
        let output = dir.appendingPathComponent("copied.dcm")
        let vm = model("dicom-tags", ["output": output.path, "tags": "0010,0010"])
        for (id, file) in [("inputPath", input), ("copy-from", source)] {
            vm.setSecurityScopedURL(dir, forParameterID: id)
            vm.updateParameterValue(parameterID: id, value: file.path)
            #expect(vm.securityScopedURLs[id] == dir)
        }
        await vm.executeCommand()
        #expect(vm.consoleStatus == .success, "\(vm.consoleOutput)")
        let read = try DICOMFile.read(from: Data(contentsOf: output))
        #expect(read.dataSet.string(for: .patientName) == "COPY^Patient")
        #expect(read.dataSet.string(for: .sopInstanceUID) == "2.25.123456789")
        #expect(try Data(contentsOf: input) == inputBytes)
        #expect(try Data(contentsOf: source) == sourceBytes)
    }

    @Test("Report and exchange producers honor typed filenames after a folder grant", arguments: ["dicom-validate", "dicom-json", "dicom-xml"])
    func reportAndExchangeTargets(tool: String) async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("source.dcm")
        let original = try fixture(at: input, patient: "CURRENT^Report")
        let output = dir.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let ext = tool == "dicom-xml" ? "xml" : "json"
        let target = output.appendingPathComponent("chosen.\(ext)")
        let inputID = tool == "dicom-xml" ? "input" : "inputPath"
        let vm = model(tool, [inputID: input.path, "level": "1", "format": "json"])
        vm.setSecurityScopedURL(output, forParameterID: "output")
        vm.updateParameterValue(parameterID: "output", value: target.path)
        await vm.executeCommand()
        #expect(vm.consoleStatus == .success, "\(vm.consoleOutput)")
        let text = try String(contentsOf: target, encoding: .utf8)
        if tool == "dicom-validate" {
            let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            let files = try #require(object["files"] as? [[String: Any]])
            #expect(files.first?["filePath"] as? String == input.path)
        } else {
            #expect(text.contains("CURRENT"))
        }
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("source.\(ext)").path))
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("output.dat").path))
        #expect(try Data(contentsOf: input) == original)
    }

    @Test("Directory producers use the requested child directory rather than the selected parent")
    func archiveChildDirectory() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("new-archive", isDirectory: true)
        let vm = model("dicom-archive", ["subcommand": "init"])
        vm.setSecurityScopedURL(dir, forParameterID: "path")
        vm.updateParameterValue(parameterID: "path", value: target.path)
        await vm.executeCommand()
        #expect(vm.consoleStatus == .success, "\(vm.consoleOutput)")
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("archive_index.json").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("archive_index.json").path))
    }

    @Test("An unrelated output path drops the old capability and never changes the old file", arguments: [false, true])
    func changedOutputOutsideGrant(fileGrant: Bool) async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appendingPathComponent("selected", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        let input = dir.appendingPathComponent("input.dcm"), target = dir.appendingPathComponent("elsewhere/output.dcm")
        _ = try fixture(at: input, patient: "CURRENT^Patient")
        let sentinel = first.appendingPathComponent("output.dcm")
        let untouched = Data("preserve old selected location".utf8)
        try untouched.write(to: sentinel)
        let vm = model("dicom-tags", ["inputPath": input.path, "set": "PatientID=CURRENT"])
        vm.setSecurityScopedURL(fileGrant ? sentinel : first, forParameterID: "output")
        vm.updateParameterValue(parameterID: "output", value: target.path)
        #expect(vm.securityScopedURLs["output"] == nil)
        // Even callers restoring stale serialized state cannot turn a grant into a target.
        vm.securityScopedURLs["output"] = fileGrant ? sentinel : first
        await vm.executeCommand()
        #expect(vm.securityScopedURLs["output"] == nil)
        #expect(vm.consoleStatus == .success, "\(vm.consoleOutput)")
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(try Data(contentsOf: sentinel) == untouched)
    }

    @Test("Containment checks reject sibling prefixes, parent traversal and escaping symlinks")
    func containmentBoundaries() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let selected = dir.appendingPathComponent("selected", isDirectory: true)
        let outside = dir.appendingPathComponent("selected-other", isDirectory: true)
        for url in [selected, outside] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let link = selected.appendingPathComponent("escape", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(CLIWorkshopViewModel.grant(selected, coversPath: selected.appendingPathComponent("new/file.dcm").path))
        #expect(!CLIWorkshopViewModel.grant(selected, coversPath: outside.appendingPathComponent("file.dcm").path))
        #expect(!CLIWorkshopViewModel.grant(selected, coversPath: selected.path + "/../selected-other/file.dcm"))
        for _ in 0..<5 {
            let covered = CLIWorkshopViewModel.grant(selected, coversPath: link.appendingPathComponent("missing/sub/file.dcm").path)
            #expect(!covered, "Even the first lookup must reject a symlink escape with a nonexistent leaf")
        }
        let dangling = selected.appendingPathComponent("dangling")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: outside.appendingPathComponent("missing"))
        #expect(!CLIWorkshopViewModel.grant(selected, coversPath: dangling.appendingPathComponent("file.dcm").path))
        let inside = selected.appendingPathComponent("inside", isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        let insideLink = selected.appendingPathComponent("inside-link")
        try FileManager.default.createSymbolicLink(at: insideLink, withDestinationURL: inside)
        #expect(CLIWorkshopViewModel.grant(selected, coversPath: insideLink.appendingPathComponent("new/file.dcm").path))
        #expect(!CLIWorkshopViewModel.grant(selected, coversPath: ""))
    }

    @Test("Received files keep requested subdirectories with a parent directory grant")
    func receivedFileTargets() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = model("dicom-retrieve")
        vm.setSecurityScopedURL(dir, forParameterID: "output")
        let target = dir.appendingPathComponent("retrieved/subdirectory", isDirectory: true)
        let data = Data([1, 2, 3, 4])
        let actual = try vm.writeOutputFile(data: data, filename: "received.dcm", outputDir: target.path)
        #expect(URL(fileURLWithPath: actual).standardizedFileURL == target.appendingPathComponent("received.dcm").standardizedFileURL)
        #expect(try Data(contentsOf: URL(fileURLWithPath: actual)) == data)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("received.dcm").path))
    }

    @Test("Video conversion and extraction require force for the requested existing file even with a Browse grant", arguments: ["convert", "extract"])
    func videoForceProtectsRequestedOutput(operation: String) async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Synthetic MPEG-2 Main Profile/Main Level header, 720x576 at 25 fps,
        // followed by two picture headers. This checks path/overwrite semantics,
        // not decoded video quality or general codec conformance.
        var stream = Data([
            0x00, 0x00, 0x01, 0xB3, 0x2D, 0x02, 0x40, 0x33, 0x13, 0x88, 0x23, 0x80,
            0x80, 0x00, 0x00, 0x01, 0xB5, 0x14, 0x8A, 0x00, 0x01, 0x00, 0x00, 0x80
        ])
        for _ in 0..<2 { stream.append(contentsOf: [0, 0, 1, 0, 0, 0x0F, 0xFF, 0xF8]) }
        let input = dir.appendingPathComponent(operation == "convert" ? "input.mpg" : "input.dcm")
        if operation == "convert" {
            try stream.write(to: input)
        } else {
            let video = try VideoBuilder(videoType: .endoscopic, rows: 576, columns: 720,
                                         numberOfFrames: 2, studyInstanceUID: "2.25.100", seriesInstanceUID: "2.25.101")
                .setFrameRate(25).setPixelData(stream).build()
            let file = DICOMFile.create(dataSet: video.toDataSet(), sopClassUID: video.sopClassUID,
                                       sopInstanceUID: video.sopInstanceUID, transferSyntaxUID: TransferSyntax.mpeg2MainProfile.uid)
            try file.write().write(to: input)
        }
        let outputDirectory = dir.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let target = outputDirectory.appendingPathComponent(operation == "convert" ? "chosen.dcm" : "chosen.mpg")
        let sentinel = Data("existing output must survive without --force".utf8)
        try sentinel.write(to: target)
        let inputID = operation == "convert" ? "input" : "dicomInput"
        let outputID = operation == "convert" ? "output" : "videoOutput"
        let vm = model("dicom-video", ["operation": operation, inputID: input.path, "force": "false"])
        vm.setSecurityScopedURL(outputDirectory, forParameterID: outputID)
        vm.updateParameterValue(parameterID: outputID, value: target.path)
        #expect(vm.securityScopedURLs[outputID] == outputDirectory)
        await vm.executeCommand()
        #expect(vm.consoleStatus == .error, "\(vm.consoleOutput)")
        #expect(vm.consoleOutput.contains(VideoConsole.outputExistsLine(target.path)))
        #expect(try Data(contentsOf: target) == sentinel)
        vm.updateParameterValue(parameterID: "force", value: "true")
        await vm.executeCommand()
        #expect(vm.consoleStatus == .success, "\(vm.consoleOutput)")
        let written = try Data(contentsOf: target)
        if operation == "convert" {
            let read = try DICOMFile.read(from: written)
            #expect(try VideoExtractor.extract(from: read).bitstream == stream)
        } else {
            #expect(written == stream)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("input.dcm").path))
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("input.mpg").path))
    }

    @Test("A missing typed input refuses instead of falling back to an accessible old selection")
    func missingChangedInputRefuses() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = dir.appendingPathComponent("old.dcm")
        let original = try fixture(at: old, patient: "STALE^Patient")
        let vm = model("dicom-info")
        vm.setSecurityScopedURL(old, forParameterID: "inputPath")
        vm.updateParameterValue(parameterID: "inputPath", value: dir.appendingPathComponent("missing.dcm").path)
        await vm.executeCommand()
        #expect(vm.consoleStatus == .error)
        #expect(vm.commandHistory.first?.exitCode == 64)
        #expect(!vm.consoleOutput.contains("STALE^Patient"))
        #expect(try Data(contentsOf: old) == original)
    }
}
