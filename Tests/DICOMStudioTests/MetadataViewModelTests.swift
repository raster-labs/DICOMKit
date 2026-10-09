// MetadataViewModelTests.swift
// DICOMStudioTests
//
// Tests for MetadataViewModel

import Testing
@testable import DICOMStudio
import Foundation

@Suite("MetadataViewModel Tests")
struct MetadataViewModelTests {

    @Test("Default state")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDefaultState() {
        let vm = MetadataViewModel()
        #expect(vm.nodes.isEmpty)
        #expect(vm.searchText == "")
        #expect(vm.filePath == nil)
        #expect(vm.transferSyntaxUID == nil)
        #expect(vm.specificCharacterSet == nil)
        #expect(vm.totalElements == 0)
        #expect(vm.errorMessage == nil)
    }

    @Test("Filtered nodes with empty search returns all")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testFilteredNodesEmpty() {
        let vm = MetadataViewModel()
        vm.nodes = [
            MetadataTreeNode(group: 0x0010, element: 0x0010, vr: "PN", name: "PatientName", value: "Doe"),
            MetadataTreeNode(group: 0x0010, element: 0x0020, vr: "LO", name: "PatientID", value: "P001"),
        ]
        #expect(vm.filteredNodes.count == 2)
    }

    @Test("Filtered nodes with search text")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testFilteredNodesSearch() {
        let vm = MetadataViewModel()
        vm.nodes = [
            MetadataTreeNode(group: 0x0010, element: 0x0010, vr: "PN", name: "PatientName", value: "Doe"),
            MetadataTreeNode(group: 0x0010, element: 0x0020, vr: "LO", name: "PatientID", value: "P001"),
        ]
        vm.searchText = "PatientName"
        #expect(vm.filteredNodes.count == 1)
    }

    @Test("Transfer syntax description for known UID")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testTransferSyntaxDescription() {
        let vm = MetadataViewModel()
        vm.transferSyntaxUID = "1.2.840.10008.1.2"
        #expect(vm.transferSyntaxDescription == "Implicit VR Little Endian: Default Transfer Syntax for DICOM")
    }

    @Test("Transfer syntax description for nil UID")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testTransferSyntaxDescriptionNil() {
        let vm = MetadataViewModel()
        #expect(vm.transferSyntaxDescription == "Unknown")
    }

    @Test("Character set description")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCharacterSetDescription() {
        let vm = MetadataViewModel()
        vm.specificCharacterSet = "ISO_IR 192"
        #expect(vm.characterSetDescription == "Unicode (UTF-8)")
    }

    @Test("Character set description for nil")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCharacterSetDescriptionNil() {
        let vm = MetadataViewModel()
        #expect(vm.characterSetDescription == "Default (ASCII)")
    }

    @Test("Clear resets all state")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testClear() {
        let vm = MetadataViewModel()
        vm.nodes = [MetadataTreeNode(group: 0x0010, element: 0x0010, vr: "PN", name: "PatientName", value: "Doe")]
        vm.searchText = "test"
        vm.filePath = "/tmp/test.dcm"
        vm.transferSyntaxUID = "1.2.3"
        vm.specificCharacterSet = "ISO_IR 192"
        vm.totalElements = 10
        vm.errorMessage = "error"

        vm.clear()

        #expect(vm.nodes.isEmpty)
        #expect(vm.searchText == "")
        #expect(vm.filePath == nil)
        #expect(vm.transferSyntaxUID == nil)
        #expect(vm.specificCharacterSet == nil)
        #expect(vm.totalElements == 0)
        #expect(vm.errorMessage == nil)
    }

    @Test("Load non-existent file sets error")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testLoadNonExistent() {
        let vm = MetadataViewModel()
        vm.loadFile(at: URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).dcm"))
        #expect(vm.errorMessage != nil)
        #expect(vm.nodes.isEmpty)
    }

    @Test("Load invalid file sets error")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testLoadInvalidFile() throws {
        let vm = MetadataViewModel()
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid_\(UUID().uuidString).dcm")
        try Data(count: 10).write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        vm.loadFile(at: tmpURL)
        #expect(vm.errorMessage != nil)
    }

    @Test("Dependency injection")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDependencyInjection() {
        let fileService = DICOMFileService()
        let vm = MetadataViewModel(fileService: fileService)
        #expect(vm.fileService === fileService)
    }
}
