//
// WorkshopDirectoryRunExitTests.swift
// DICOMStudioTests
//
// The Workshop's directory runs exit as the CLIs do since 2026-10-06: dicom-pdf (D271),
// dicom-image (D273) and dicom-export bulk (D251) exit 1 after the summary when any file
// failed; dicom-pdf --extract skips a file that is not an Encapsulated Document (PS3.3
// 2026a C.24.2: no Encapsulated Document (0042,0011)) instead of failing it.
//

import Testing
import Foundation
@testable import DICOMStudio
import DICOMCore
import DICOMKit

@MainActor
struct WorkshopDirectoryRunExitTests {

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkshopDirectoryRunExit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// DICOM with Encapsulated Document (0042,0011) but no MIME Type of Encapsulated Document
    /// (0042,0012), Type 1 in PS3.3 Table C.24-2: a document that fails to extract.
    private func brokenDocument() throws -> Data {
        var ds = DataSet()
        ds.setString(EncapsulatedDocument.encapsulatedPDFStorageUID, for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5", for: .sopInstanceUID, vr: .UI)
        ds.setString("1.2.3.4", for: .studyInstanceUID, vr: .UI)
        ds.setString("1.2.3.4.1", for: .seriesInstanceUID, vr: .UI)
        ds[.encapsulatedDocument] = DataElement.data(tag: .encapsulatedDocument, vr: .OB, data: Data("%PDF-1.4\n".utf8))
        return try DICOMFile.create(dataSet: ds).write()
    }

    private func notADocument() throws -> Data {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.6", for: .sopInstanceUID, vr: .UI)
        return try DICOMFile.create(dataSet: ds).write()
    }

    private func runPdfExtract(_ input: URL, _ output: URL) async -> CLIWorkshopViewModel {
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: "dicom-pdf")
        vm.updateParameterValue(parameterID: "inputPath", value: input.path)
        vm.updateParameterValue(parameterID: "output", value: output.path)
        vm.updateParameterValue(parameterID: "extract", value: "true")
        vm.updateParameterValue(parameterID: "recursive", value: "true")
        vm.updateParameterValue(parameterID: "verbose", value: "true")
        await vm.executeCommand()
        return vm
    }

    @Test("dicom-pdf --extract over a directory skips files that are not Encapsulated Documents and exits 0 (D271)")
    func pdfExtractSkips() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("in"), output = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try Data("not DICOM".utf8).write(to: input.appendingPathComponent("notes.txt"))
        try notADocument().write(to: input.appendingPathComponent("sc.dcm"))
        let vm = await runPdfExtract(input, output)
        #expect(vm.commandHistory.last?.exitCode == 0, "console: \(vm.consoleOutput)")
        #expect(vm.consoleOutput.contains(CLIWorkshopViewModel.pdfSkippedLine(fileName: "sc.dcm")))
        #expect(vm.consoleOutput.contains("⊘ notes.txt: not an Encapsulated Document (skipped)"))
        #expect(!vm.consoleOutput.contains("Failed:"))
    }

    @Test("dicom-pdf --extract over a directory with a document that fails exits 1 after the summary (D271)")
    func pdfExtractFailureExitsOne() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("in"), output = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try brokenDocument().write(to: input.appendingPathComponent("broken.dcm"))
        let vm = await runPdfExtract(input, output)
        #expect(vm.commandHistory.last?.exitCode == 1, "console: \(vm.consoleOutput)")
        #expect(vm.consoleOutput.contains("  Failed: 1"))
        #expect(!vm.consoleOutput.contains("Error:"))      // ExitCode.failure prints no further line
    }

    @Test("dicom-image over a directory with a file that fails exits 1 after the summary (D273)")
    func imageDirectoryFailureExitsOne() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("in"), output = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try Data("not a PNG".utf8).write(to: input.appendingPathComponent("broken.png"))
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: "dicom-image")
        vm.updateParameterValue(parameterID: "input", value: input.path)
        vm.updateParameterValue(parameterID: "output", value: output.path)
        vm.updateParameterValue(parameterID: "recursive", value: "true")
        vm.updateParameterValue(parameterID: "patient-name", value: "TEST")
        vm.updateParameterValue(parameterID: "patient-id", value: "123456")
        await vm.executeCommand()
        #expect(vm.commandHistory.last?.exitCode == 1, "console: \(vm.consoleOutput)")
        #expect(vm.consoleStatus == .error)
    }

    @Test("dicom-export bulk with a file that fails exits 1 after the summary (D251)")
    func exportBulkFailureExitsOne() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("in"), output = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try Data("not DICOM".utf8).write(to: input.appendingPathComponent("broken.dcm"))
        let vm = CLIWorkshopViewModel()
        vm.selectTool(id: "dicom-export")
        vm.updateParameterValue(parameterID: "operation", value: "bulk")
        vm.updateParameterValue(parameterID: "inputPath", value: input.path)
        vm.updateParameterValue(parameterID: "output", value: output.path)
        vm.updateParameterValue(parameterID: "recursive", value: "true")
        await vm.executeCommand()
        #expect(vm.commandHistory.last?.exitCode == 1, "console: \(vm.consoleOutput)")
        #expect(vm.consoleOutput.contains("Bulk export complete: 0/1 succeeded, 1 failed"), "console: \(vm.consoleOutput)")
    }
}
