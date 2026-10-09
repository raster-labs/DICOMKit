// DataExchangeViewModelTests.swift
// DICOMStudioTests

import Testing
@testable import DICOMStudio
import Foundation

@Suite("Data Exchange ViewModel Tests")
struct DataExchangeViewModelTests {

    // MARK: - Navigation

    @Test("default activeTab is jsonConversion")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDefaultActiveTab() {
        let vm = DataExchangeViewModel()
        #expect(vm.activeTab == .jsonConversion)
    }

    @Test("Secondary Capture modality defaults to OT, a PS3.3 2026a C.7.3.1.1.1 Defined Term (not SC)")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSecondaryCaptureModalityDefaultIsOT() {
        let vm = DataExchangeViewModel()
        #expect(vm.secondaryCaptureModality == "OT")
        vm.runSecondaryCapture()
        #expect(vm.secondaryCaptureResult.contains("--modality OT"))
    }

    @Test("isLoading starts false")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testIsLoadingStartsFalse() {
        let vm = DataExchangeViewModel()
        #expect(vm.isLoading == false)
    }

    @Test("errorMessage starts nil")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testErrorMessageStartsNil() {
        let vm = DataExchangeViewModel()
        #expect(vm.errorMessage == nil)
    }

    // MARK: - 12.1 JSON

    @Test("default jsonSettings outputFormat is pretty")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testDefaultJSONSettingsFormat() {
        let vm = DataExchangeViewModel()
        #expect(vm.jsonSettings.outputFormat == .pretty)
    }

    @Test("setJSONInputFilePath updates jsonInputFilePath")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetJSONInputFilePath() {
        let vm = DataExchangeViewModel()
        vm.setJSONInputFilePath("/tmp/test.dcm")
        #expect(vm.jsonInputFilePath == "/tmp/test.dcm")
    }

    @Test("updateJSONSettings updates jsonSettings")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testUpdateJSONSettings() {
        let vm = DataExchangeViewModel()
        var settings = JSONConversionSettings()
        settings.outputFormat = .compact
        vm.updateJSONSettings(settings)
        #expect(vm.jsonSettings.outputFormat == .compact)
    }

    @Test("clearJSONOutput clears jsonOutput")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testClearJSONOutput() {
        let vm = DataExchangeViewModel()
        vm.jsonOutput = "{}"
        vm.clearJSONOutput()
        #expect(vm.jsonOutput.isEmpty)
    }

    @Test("isJSONExportSheetPresented starts false")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testIsJSONExportSheetPresentedStartsFalse() {
        let vm = DataExchangeViewModel()
        #expect(vm.isJSONExportSheetPresented == false)
    }

    // MARK: - 12.2 XML

    @Test("setXMLInputFilePath updates xmlInputFilePath")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetXMLInputFilePath() {
        let vm = DataExchangeViewModel()
        vm.setXMLInputFilePath("/tmp/scan.dcm")
        #expect(vm.xmlInputFilePath == "/tmp/scan.dcm")
    }

    @Test("updateXMLSettings updates xmlSettings")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testUpdateXMLSettings() {
        let vm = DataExchangeViewModel()
        var settings = XMLConversionSettings()
        settings.outputFormat = .noKeywords
        vm.updateXMLSettings(settings)
        #expect(vm.xmlSettings.outputFormat == .noKeywords)
    }

    @Test("clearXMLOutput clears xmlOutput")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testClearXMLOutput() {
        let vm = DataExchangeViewModel()
        vm.xmlOutput = "<root/>"
        vm.clearXMLOutput()
        #expect(vm.xmlOutput.isEmpty)
    }

    // MARK: - 12.3 Image Export

    @Test("setImageInputFilePath updates imageInputFilePath")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetImageInputFilePath() {
        let vm = DataExchangeViewModel()
        vm.setImageInputFilePath("/tmp/ct.dcm")
        #expect(vm.imageInputFilePath == "/tmp/ct.dcm")
    }

    @Test("addExportedImagePath increases exportedImagePaths count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testAddExportedImagePath() {
        let vm = DataExchangeViewModel()
        vm.addExportedImagePath("/tmp/frame1.png")
        #expect(vm.exportedImagePaths.count == 1)
    }

    @Test("clearExportedImagePaths empties exportedImagePaths")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testClearExportedImagePaths() {
        let vm = DataExchangeViewModel()
        vm.addExportedImagePath("/tmp/frame1.png")
        vm.clearExportedImagePaths()
        #expect(vm.exportedImagePaths.isEmpty)
    }

    // MARK: - 12.4 Transfer Syntax

    @Test("addConversionJob increases conversionJobs count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testAddConversionJob() {
        let vm = DataExchangeViewModel()
        let job = TransferSyntaxConversionJob(sourceFilePath: "/tmp/a.dcm", targetTransferSyntaxUID: "1.2.840.10008.1.2.1")
        vm.addConversionJob(job)
        #expect(vm.conversionJobs.count == 1)
    }

    @Test("removeConversionJob decreases conversionJobs count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRemoveConversionJob() {
        let vm = DataExchangeViewModel()
        let job = TransferSyntaxConversionJob(sourceFilePath: "/tmp/a.dcm", targetTransferSyntaxUID: "1.2.840.10008.1.2.1")
        vm.addConversionJob(job)
        vm.removeConversionJob(id: job.id)
        #expect(vm.conversionJobs.isEmpty)
    }

    @Test("updateConversionJob modifies existing job")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testUpdateConversionJob() {
        let vm = DataExchangeViewModel()
        var job = TransferSyntaxConversionJob(sourceFilePath: "/tmp/a.dcm", targetTransferSyntaxUID: "1.2.840.10008.1.2.1")
        vm.addConversionJob(job)
        job.status = .completed
        vm.updateConversionJob(job)
        #expect(vm.conversionJobs.first?.status == .completed)
    }

    @Test("setSelectedTargetSyntaxUID updates selectedTargetSyntaxUID")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetSelectedTargetSyntaxUID() {
        let vm = DataExchangeViewModel()
        vm.setSelectedTargetSyntaxUID("1.2.840.10008.1.2.4.90")
        #expect(vm.selectedTargetSyntaxUID == "1.2.840.10008.1.2.4.90")
    }

    // MARK: - 12.5 DICOMDIR

    @Test("addDICOMDIREntry increases dicomdirEntries count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testAddDICOMDIREntry() {
        let vm = DataExchangeViewModel()
        let entry = DICOMDIREntry(studyInstanceUID: "1.2.3", patientName: "Doe^John",
                                  patientID: "001", studyDate: "20240101",
                                  modalities: ["CT"], seriesCount: 1, instanceCount: 10)
        vm.addDICOMDIREntry(entry)
        #expect(vm.dicomdirEntries.count == 1)
    }

    @Test("removeDICOMDIREntry decreases dicomdirEntries count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRemoveDICOMDIREntry() {
        let vm = DataExchangeViewModel()
        let entry = DICOMDIREntry(studyInstanceUID: "1.2.3", patientName: "Doe^John",
                                  patientID: "001", studyDate: "20240101",
                                  modalities: ["CT"], seriesCount: 1, instanceCount: 10)
        vm.addDICOMDIREntry(entry)
        vm.removeDICOMDIREntry(id: entry.id)
        #expect(vm.dicomdirEntries.isEmpty)
    }

    @Test("setDICOMDIROutputPath updates dicomdirOutputPath")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetDICOMDIROutputPath() {
        let vm = DataExchangeViewModel()
        vm.setDICOMDIROutputPath("/Volumes/DICOM/DICOMDIR")
        #expect(vm.dicomdirOutputPath == "/Volumes/DICOM/DICOMDIR")
    }

    // MARK: - 12.6 PDF

    @Test("setPDFMode updates pdfMode")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetPDFMode() {
        let vm = DataExchangeViewModel()
        vm.setPDFMode(.extract)
        #expect(vm.pdfMode == .extract)
    }

    @Test("setPDFInputPath updates pdfInputPath")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetPDFInputPath() {
        let vm = DataExchangeViewModel()
        vm.setPDFInputPath("/tmp/report.pdf")
        #expect(vm.pdfInputPath == "/tmp/report.pdf")
    }

    @Test("setPDFOutputPath updates pdfOutputPath")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetPDFOutputPath() {
        let vm = DataExchangeViewModel()
        vm.setPDFOutputPath("/tmp/report.dcm")
        #expect(vm.pdfOutputPath == "/tmp/report.dcm")
    }

    @Test("setPDFPatientName updates pdfPatientName")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetPDFPatientName() {
        let vm = DataExchangeViewModel()
        vm.setPDFPatientName("Smith^Jane")
        #expect(vm.pdfPatientName == "Smith^Jane")
    }

    @Test("setPDFPatientID updates pdfPatientID")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetPDFPatientID() {
        let vm = DataExchangeViewModel()
        vm.setPDFPatientID("P002")
        #expect(vm.pdfPatientID == "P002")
    }

    // MARK: - 12.7 Batch

    @Test("addBatchJob increases batchJobs count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testAddBatchJob() {
        let vm = DataExchangeViewModel()
        let job = BatchJob(operationType: .anonymization, inputPaths: ["/tmp/a.dcm"], outputDirectory: "/tmp/out")
        vm.addBatchJob(job)
        #expect(vm.batchJobs.count == 1)
    }

    @Test("removeBatchJob decreases batchJobs count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRemoveBatchJob() {
        let vm = DataExchangeViewModel()
        let job = BatchJob(operationType: .imageExport, inputPaths: [], outputDirectory: "")
        vm.addBatchJob(job)
        vm.removeBatchJob(id: job.id)
        #expect(vm.batchJobs.isEmpty)
    }

    @Test("setSelectedBatchOperationType updates selectedBatchOperationType")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSetSelectedBatchOperationType() {
        let vm = DataExchangeViewModel()
        vm.setSelectedBatchOperationType(.transferSyntaxConversion)
        #expect(vm.selectedBatchOperationType == .transferSyntaxConversion)
    }

    @Test("addBatchTagModification increases batchTagModifications count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testAddBatchTagModification() {
        let vm = DataExchangeViewModel()
        let mod = BatchTagModification(tagKeyword: "PatientName", tagGroup: 0x0010, tagElement: 0x0010,
                                       operation: .remove, newValue: "")
        vm.addBatchTagModification(mod)
        #expect(vm.batchTagModifications.count == 1)
    }

    @Test("removeBatchTagModification decreases batchTagModifications count")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRemoveBatchTagModification() {
        let vm = DataExchangeViewModel()
        let mod = BatchTagModification(tagKeyword: "PatientName", tagGroup: 0x0010, tagElement: 0x0010,
                                       operation: .remove, newValue: "")
        vm.addBatchTagModification(mod)
        vm.removeBatchTagModification(id: mod.id)
        #expect(vm.batchTagModifications.isEmpty)
    }

    @Test("loadFromService reflects service state")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testLoadFromService() {
        let service = DataExchangeService()
        service.setJSONInputFilePath("/tmp/reload.dcm")
        let vm = DataExchangeViewModel(service: service)
        #expect(vm.jsonInputFilePath == "/tmp/reload.dcm")
    }
}
