// StudyBrowserViewModelTests.swift
// DICOMStudioTests
//
// Tests for StudyBrowserViewModel

import Testing
@testable import DICOMStudio
import DICOMCore
import Foundation

@Suite("StudyBrowserViewModel Tests")
@MainActor
struct StudyBrowserViewModelTests {

    @Test("Default state")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDefaultState() {
        let vm = StudyBrowserViewModel()
        #expect(vm.library.studyCount == 0)
        #expect(vm.filter == .none)
        #expect(vm.sortField == .date)
        #expect(vm.sortDirection == .descending)
        #expect(vm.displayMode == .list)
        #expect(vm.selectedStudyUID == nil)
        #expect(vm.selectedSeriesUID == nil)
        #expect(!vm.isImporting)
        #expect(vm.lastError == nil)
    }

    @Test("Display studies returns empty for empty library")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDisplayStudiesEmpty() {
        let vm = StudyBrowserViewModel()
        #expect(vm.displayStudies.isEmpty)
    }


    /// A study with one series and one instance under it — the shape a real
    /// import produces, and the shape the browser will show.
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    private func populated(
        _ library: inout LibraryModel,
        studyUID: String,
        studyID: String,
        patientName: String? = nil,
        modality: String
    ) {
        library.addStudy(StudyModel(
            studyInstanceUID: studyUID,
            studyID: studyID,
            patientName: patientName,
            modalitiesInStudy: [modality]
        ))
        library.addSeries(SeriesModel(
            seriesInstanceUID: studyUID + ".1",
            studyInstanceUID: studyUID,
            modality: modality))
        library.addInstance(InstanceModel(
            sopInstanceUID: studyUID + ".1.1",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            seriesInstanceUID: studyUID + ".1",
            instanceNumber: 1,
            filePath: "/\(studyUID).dcm"))
    }

    @Test("Display studies returns filtered studies")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDisplayStudiesWithData() {
        var library = LibraryModel()
        populated(&library, studyUID: "1.2.3", studyID: "S1",
                  patientName: "DOE^JOHN", modality: "CT")
        populated(&library, studyUID: "1.2.4", studyID: "S2",
                  patientName: "SMITH^JANE", modality: "MR")
        let vm = StudyBrowserViewModel(library: library)
        #expect(vm.displayStudies.count == 2)
    }

    @Test("A study with no images under it is not listed")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEmptyStudiesAreNotListed() {
        var library = LibraryModel()
        populated(&library, studyUID: "1.2.3", studyID: "S1", modality: "CT")
        // The row a broken import used to leave behind: a study, no instances,
        // nothing to open. It stays in storage but is not shown.
        library.addStudy(StudyModel(studyInstanceUID: "ghost", studyID: "S2"))

        let vm = StudyBrowserViewModel(library: library)
        #expect(vm.displayStudies.map(\.studyInstanceUID) == ["1.2.3"])
        #expect(vm.library.studies["ghost"] != nil, "storage is left alone")
    }

    @Test("Filter reduces displayed studies")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testFilterReducesStudies() {
        var library = LibraryModel()
        populated(&library, studyUID: "1.2.3", studyID: "S1", modality: "CT")
        populated(&library, studyUID: "1.2.4", studyID: "S2", modality: "MR")
        let vm = StudyBrowserViewModel(library: library)
        vm.filter.modalities = ["CT"]
        #expect(vm.displayStudies.count == 1)
    }

    @Test("Selected study series returns correct series")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSelectedStudySeries() {
        var library = LibraryModel()
        library.addStudy(StudyModel(
            studyInstanceUID: "1.2.3",
            studyID: "S1",
            modalitiesInStudy: ["CT"]
        ))
        library.addSeries(SeriesModel(
            seriesInstanceUID: "1.2.3.1",
            studyInstanceUID: "1.2.3",
            modality: "CT"
        ))
        let vm = StudyBrowserViewModel(library: library)
        vm.selectedStudyUID = "1.2.3"
        #expect(vm.selectedStudySeries.count == 1)
    }

    @Test("Selected study series returns empty when no selection")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSelectedStudySeriesNoSelection() {
        let vm = StudyBrowserViewModel()
        #expect(vm.selectedStudySeries.isEmpty)
    }

    @Test("Selected series instances returns correct instances")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSelectedSeriesInstances() {
        var library = LibraryModel()
        library.addStudy(StudyModel(
            studyInstanceUID: "1.2.3",
            studyID: "S1",
            modalitiesInStudy: ["CT"]
        ))
        library.addSeries(SeriesModel(
            seriesInstanceUID: "1.2.3.1",
            studyInstanceUID: "1.2.3",
            modality: "CT"
        ))
        library.addInstance(InstanceModel(
            sopInstanceUID: "1.2.3.1.1",
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            seriesInstanceUID: "1.2.3.1",
            filePath: "/tmp/test.dcm"
        ))
        let vm = StudyBrowserViewModel(library: library)
        vm.selectedSeriesUID = "1.2.3.1"
        #expect(vm.selectedSeriesInstances.count == 1)
    }

    @Test("Available modalities")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testAvailableModalities() {
        var library = LibraryModel()
        library.addStudy(StudyModel(
            studyInstanceUID: "1",
            studyID: "S1",
            modalitiesInStudy: ["CT"]
        ))
        library.addStudy(StudyModel(
            studyInstanceUID: "2",
            studyID: "S2",
            modalitiesInStudy: ["MR"]
        ))
        let vm = StudyBrowserViewModel(library: library)
        #expect(vm.availableModalities.contains("CT"))
        #expect(vm.availableModalities.contains("MR"))
    }

    @Test("Toggle modality filter")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testToggleModalityFilter() {
        let vm = StudyBrowserViewModel()
        vm.toggleModalityFilter("CT")
        #expect(vm.filter.modalities.contains("CT"))
        vm.toggleModalityFilter("CT")
        #expect(!vm.filter.modalities.contains("CT"))
    }

    @Test("Clear filters")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testClearFilters() {
        let vm = StudyBrowserViewModel()
        vm.filter.modalities = ["CT"]
        vm.filter.searchText = "test"
        vm.clearFilters()
        #expect(!vm.filter.isActive)
    }

    @Test("Toggle sort direction")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testToggleSortDirection() {
        let vm = StudyBrowserViewModel()
        #expect(vm.sortDirection == .descending)
        vm.toggleSortDirection()
        #expect(vm.sortDirection == .ascending)
    }

    @Test("Toggle display mode")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testToggleDisplayMode() {
        let vm = StudyBrowserViewModel()
        #expect(vm.displayMode == .list)
        vm.toggleDisplayMode()
        #expect(vm.displayMode == .grid)
        vm.toggleDisplayMode()
        #expect(vm.displayMode == .list)
    }

    @Test("Remove study clears selection")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRemoveStudyClearsSelection() {
        var library = LibraryModel()
        library.addStudy(StudyModel(
            studyInstanceUID: "1.2.3",
            studyID: "S1",
            modalitiesInStudy: ["CT"]
        ))
        let vm = StudyBrowserViewModel(library: library)
        vm.selectedStudyUID = "1.2.3"
        vm.selectedSeriesUID = "1.2.3.1"
        vm.removeStudy("1.2.3")
        #expect(vm.selectedStudyUID == nil)
        #expect(vm.selectedSeriesUID == nil)
        #expect(vm.library.studyCount == 0)
    }

    @Test("Dependency injection")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDependencyInjection() {
        let importSvc = ImportService()
        let vm = StudyBrowserViewModel(importService: importSvc)
        #expect(vm.importService === importSvc)
    }

    @Test("File importer initially not presented")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testFileImporterInitialState() {
        let vm = StudyBrowserViewModel()
        #expect(vm.isFileImporterPresented == false)
    }

    @Test("Show file importer sets presented")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testShowFileImporter() {
        let vm = StudyBrowserViewModel()
        vm.showFileImporter()
        #expect(vm.isFileImporterPresented == true)
    }

    @Test("Toggle favorite on study")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testToggleFavorite() {
        var library = LibraryModel()
        library.addStudy(StudyModel(
            studyInstanceUID: "1.2.3",
            studyID: "S1",
            modalitiesInStudy: ["CT"]
        ))
        let vm = StudyBrowserViewModel(library: library)
        #expect(vm.isFavorite("1.2.3") == false)
        vm.toggleFavorite("1.2.3")
        #expect(vm.isFavorite("1.2.3") == true)
        vm.toggleFavorite("1.2.3")
        #expect(vm.isFavorite("1.2.3") == false)
    }

    @Test("Is favorite returns false for unknown study")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testIsFavoriteUnknown() {
        let vm = StudyBrowserViewModel()
        #expect(vm.isFavorite("nonexistent") == false)
    }
}

@Suite("TransferSyntaxDescriptions Tests")
struct TransferSyntaxDescriptionsTests {

    @Test("Known transfer syntax descriptions are the PS3.6 2026a Table A-1 UID Names")
    func testKnownTransferSyntax() {
        #expect(TransferSyntaxDescriptions.describe("1.2.840.10008.1.2")
                == "Implicit VR Little Endian: Default Transfer Syntax for DICOM")
        #expect(TransferSyntaxDescriptions.describe("1.2.840.10008.1.2.1") == "Explicit VR Little Endian")
        #expect(TransferSyntaxDescriptions.describe("1.2.840.10008.1.2.2") == "Explicit VR Big Endian (Retired)")
        #expect(TransferSyntaxDescriptions.describe("1.2.840.10008.1.2.4.50")
                == "JPEG Baseline (Process 1): Default Transfer Syntax for Lossy JPEG 8 Bit Image Compression")
        #expect(TransferSyntaxDescriptions.describe("1.2.840.10008.1.2.4.70")
                == "JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14 [Selection Value 1]): "
                   + "Default Transfer Syntax for Lossless JPEG Image Compression")
        #expect(TransferSyntaxDescriptions.describe("1.2.840.10008.1.2.4.90")
                == "JPEG 2000 Image Compression (Lossless Only)")
        #expect(TransferSyntaxDescriptions.describe("1.2.840.10008.1.2.4.203")
                == "High-Throughput JPEG 2000 Image Compression")
        #expect(TransferSyntaxDescriptions.describe("1.2.840.10008.1.2.5") == "RLE Lossless")
    }

    @Test("Every transfer syntax description equals DICOMCore's Table A-1 displayName")
    func testDescriptionsComeFromDICOMCore() {
        for ts in TransferSyntax.allKnown {
            #expect(TransferSyntaxDescriptions.describe(ts.uid) == ts.displayName, "\(ts.uid)")
        }
    }

    @Test("Unknown transfer syntax")
    func testUnknownTransferSyntax() {
        let result = TransferSyntaxDescriptions.describe("1.2.3.4.5")
        #expect(result.contains("Unknown"))
        #expect(result.contains("1.2.3.4.5"))
    }

    @Test("Transfer syntax with whitespace trimmed")
    func testTransferSyntaxTrimmed() {
        let result = TransferSyntaxDescriptions.describe("  1.2.840.10008.1.2  ")
        #expect(result == "Implicit VR Little Endian: Default Transfer Syntax for DICOM")
    }
}
