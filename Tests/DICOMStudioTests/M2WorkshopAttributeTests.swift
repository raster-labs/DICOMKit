import Foundation
import Testing
import DICOMCore
import DICOMKit
@testable import DICOMStudio

@Suite("M2 Workshop attribute execution", .serialized)
@MainActor
struct M2WorkshopAttributeTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dicomkit-m2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func base() -> DataSet {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("2.25.1234", for: .sopInstanceUID, vr: .UI)
        ds.setString("SYNTHETIC^M2", for: .patientName, vr: .PN)
        return ds
    }
    private func bytes(_ dataSet: DataSet) throws -> Data { try DICOMFile.create(dataSet: dataSet).write() }
    private func model(_ tool: String, _ values: [String: String]) -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
        vm.selectTool(id: tool)
        for (id, value) in values { vm.updateParameterValue(parameterID: id, value: value) }
        return vm
    }

    @Test("All nine malformed edits refuse dry run and actual write without touching input")
    func malformedEdits() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("input.dcm"), output = dir.appendingPathComponent("output.dcm")
        let original = try bytes(base())
        try original.write(to: input)
        let invalid = ["PatientAge=Y123", "PatientBirthDate=20260231", "PixelSpacing=1..2\\3", "SeriesNumber=++1",
                       "AcquisitionDateTime=20269999112233", "StudyTime=256199", "StudyInstanceUID=1..02", "Rows=1\\2",
                       "RetrieveAETitle=Müller"]
        for value in invalid {
            for dryRun in [true, false] {
                let vm = model("dicom-tags", ["inputPath": input.path, "output": output.path,
                    "set": value, "dry-run": String(dryRun)])
                await vm.executeCommand()
                #expect(vm.consoleStatus == .error, "\(value): \(vm.consoleOutput)")
                #expect(vm.commandHistory.first?.exitCode == 1)
                #expect(vm.consoleOutput.contains("Error:"))
                #expect(try Data(contentsOf: input) == original)
                #expect(!FileManager.default.fileExists(atPath: output.path))
            }
        }
    }

    @Test("Unicode, signed values and SOP identity survive Workshop writing and validation")
    func validEdits() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("input.dcm"), output = dir.appendingPathComponent("output.dcm")
        try bytes(base()).write(to: input)
        let vm = model("dicom-tags", ["inputPath": input.path, "output": output.path,
            "set": "PatientName=Müller^患者; SOPInstanceUID=2.25.222222222; PixelRepresentation=1; SmallestImagePixelValue=-1; AcquisitionDateTime=2026"])
        await vm.executeCommand()
        #expect(vm.consoleStatus == .success, "\(vm.consoleOutput)")
        let data = try Data(contentsOf: output)
        let read = try DICOMFile.read(from: data)
        #expect(read.dataSet.string(for: .patientName) == "Müller^患者")
        #expect(read.dataSet.string(for: .specificCharacterSet) == "ISO_IR 192")
        #expect(read.fileMetaInformation.string(for: .mediaStorageSOPInstanceUID) == "2.25.222222222")
        #expect(read.dataSet[.smallestImagePixelValue]?.vr == .SS)
        #expect(read.dataSet[.smallestImagePixelValue]?.valueData == Data([255, 255]))
        let check = model("dicom-validate", ["inputPath": output.path, "level": "2", "format": "json"])
        await check.executeCommand()
        #expect(check.consoleStatus == .success, "\(check.consoleOutput)")
        #expect(check.commandHistory.first?.exitCode == 0)
    }

    @Test("Numeric copy selectors use the same actual Workshop path as keyword selectors")
    func numericCopy() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("input.dcm"), source = dir.appendingPathComponent("source.dcm")
        try bytes(base()).write(to: input)
        var sourceSet = base()
        sourceSet.setString("ISO_IR 192", for: .specificCharacterSet, vr: .CS)
        sourceSet.setString("COPY^Müller", for: .patientName, vr: .PN)
        try bytes(sourceSet).write(to: source)
        for (index, selector) in ["0010,0010", "(0010,0010)", "00100010", "PatientName"].enumerated() {
            let output = dir.appendingPathComponent("copy-\(index).dcm")
            let vm = model("dicom-tags", ["inputPath": input.path, "output": output.path,
                "copy-from": source.path, "tags": selector])
            await vm.executeCommand()
            #expect(vm.consoleStatus == .success, "\(selector): \(vm.consoleOutput)")
            let file = try DICOMFile.read(from: Data(contentsOf: output))
            #expect(file.dataSet.string(for: .patientName) == "COPY^Müller")
        }
    }

    @Test("Workshop level 2 recursively reports invalid nested AS, DA and registered VR")
    func nestedValidation() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var ds = base()
        var nested = DataSet()
        nested.setString("Y123", for: .patientAge, vr: .AS)
        nested.setString("20260231", for: .studyDate, vr: .DA)
        nested.setString("512", for: .rows, vr: .LO)
        ds.setSequence([SequenceItem(elements: nested.allElements)], for: .referencedStudySequence)
        let input = dir.appendingPathComponent("nested.dcm")
        try bytes(ds).write(to: input)
        let vm = model("dicom-validate", ["inputPath": input.path, "level": "2", "format": "text"])
        await vm.executeCommand()
        #expect(vm.consoleStatus == .error)
        #expect(vm.commandHistory.first?.exitCode == 1)
        for required in ["INVALID", "(0008,1110)[1]", "(0010,1010)", "(0008,0020)", "VR LO", "US"] {
            #expect(vm.consoleOutput.contains(required), "\(vm.consoleOutput)")
        }
    }
}
