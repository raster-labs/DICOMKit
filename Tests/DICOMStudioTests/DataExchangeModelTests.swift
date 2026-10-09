// DataExchangeModelTests.swift
// DICOMStudioTests

import Testing
@testable import DICOMStudio
import DICOMCore
import Foundation

@Suite("Data Exchange Model Tests")
struct DataExchangeModelTests {

    // MARK: - DataExchangeTab

    @Test("DataExchangeTab has 9 cases")
    func testDataExchangeTabCaseCount() {
        #expect(DataExchangeTab.allCases.count == 9)
    }

    @Test("DataExchangeTab all cases have non-empty display names")
    func testDataExchangeTabDisplayNames() {
        for tab in DataExchangeTab.allCases {
            #expect(!tab.displayName.isEmpty)
        }
    }

    @Test("DataExchangeTab all cases have non-empty SF symbols")
    func testDataExchangeTabSFSymbols() {
        for tab in DataExchangeTab.allCases {
            #expect(!tab.sfSymbol.isEmpty)
        }
    }

    @Test("DataExchangeTab rawValues are unique")
    func testDataExchangeTabRawValuesUnique() {
        let rawValues = DataExchangeTab.allCases.map { $0.rawValue }
        #expect(Set(rawValues).count == DataExchangeTab.allCases.count)
    }

    @Test("DataExchangeTab jsonConversion rawValue is JSON_CONVERSION")
    func testDataExchangeTabJSONRawValue() {
        #expect(DataExchangeTab.jsonConversion.rawValue == "JSON_CONVERSION")
    }

    @Test("DataExchangeTab batchOperations rawValue is BATCH_OPERATIONS")
    func testDataExchangeTabBatchRawValue() {
        #expect(DataExchangeTab.batchOperations.rawValue == "BATCH_OPERATIONS")
    }

    // MARK: - JSONOutputFormat

    @Test("JSONOutputFormat all cases have non-empty displayName")
    func testJSONOutputFormatDisplayNames() {
        for fmt in JSONOutputFormat.allCases {
            #expect(!fmt.displayName.isEmpty)
        }
    }

    @Test("JSONOutputFormat all cases have non-empty description")
    func testJSONOutputFormatDescriptions() {
        for fmt in JSONOutputFormat.allCases {
            #expect(!fmt.description.isEmpty)
        }
    }

    @Test("JSONOutputFormat rawValues are unique")
    func testJSONOutputFormatRawValuesUnique() {
        let rawValues = JSONOutputFormat.allCases.map { $0.rawValue }
        #expect(Set(rawValues).count == JSONOutputFormat.allCases.count)
    }

    @Test("JSONOutputFormat standard rawValue is STANDARD")
    func testJSONOutputFormatStandardRawValue() {
        #expect(JSONOutputFormat.standard.rawValue == "STANDARD")
    }

    // MARK: - XMLOutputFormat

    @Test("XMLOutputFormat all cases have non-empty displayName")
    func testXMLOutputFormatDisplayNames() {
        for fmt in XMLOutputFormat.allCases {
            #expect(!fmt.displayName.isEmpty)
        }
    }

    @Test("XMLOutputFormat all cases have non-empty description")
    func testXMLOutputFormatDescriptions() {
        for fmt in XMLOutputFormat.allCases {
            #expect(!fmt.description.isEmpty)
        }
    }

    @Test("XMLOutputFormat rawValues are unique")
    func testXMLOutputFormatRawValuesUnique() {
        let rawValues = XMLOutputFormat.allCases.map { $0.rawValue }
        #expect(Set(rawValues).count == XMLOutputFormat.allCases.count)
    }

    @Test("XMLOutputFormat noKeywords rawValue is NO_KEYWORDS")
    func testXMLOutputFormatNoKeywordsRawValue() {
        #expect(XMLOutputFormat.noKeywords.rawValue == "NO_KEYWORDS")
    }

    // MARK: - ImageExportFormat

    @Test("ImageExportFormat all cases have non-empty displayName")
    func testImageExportFormatDisplayNames() {
        for fmt in ImageExportFormat.allCases {
            #expect(!fmt.displayName.isEmpty)
        }
    }

    @Test("ImageExportFormat all cases have non-empty fileExtension")
    func testImageExportFormatFileExtensions() {
        for fmt in ImageExportFormat.allCases {
            #expect(!fmt.fileExtension.isEmpty)
        }
    }

    @Test("ImageExportFormat PNG is lossless")
    func testImageExportFormatPNGLossless() {
        #expect(ImageExportFormat.png.isLossless == true)
    }

    @Test("ImageExportFormat TIFF is lossless")
    func testImageExportFormatTIFFLossless() {
        #expect(ImageExportFormat.tiff.isLossless == true)
    }

    @Test("ImageExportFormat JPEG is lossy")
    func testImageExportFormatJPEGLossy() {
        #expect(ImageExportFormat.jpeg.isLossless == false)
    }

    @Test("ImageExportFormat JPEG fileExtension is jpg")
    func testImageExportFormatJPEGExtension() {
        #expect(ImageExportFormat.jpeg.fileExtension == "jpg")
    }

    // MARK: - ImageExportResolution

    @Test("ImageExportResolution all cases have non-empty displayName")
    func testImageExportResolutionDisplayNames() {
        for res in ImageExportResolution.allCases {
            #expect(!res.displayName.isEmpty)
        }
    }

    @Test("ImageExportResolution all cases have non-empty description")
    func testImageExportResolutionDescriptions() {
        for res in ImageExportResolution.allCases {
            #expect(!res.description.isEmpty)
        }
    }

    @Test("ImageExportResolution has 3 cases")
    func testImageExportResolutionCaseCount() {
        #expect(ImageExportResolution.allCases.count == 3)
    }

    // MARK: - TransferSyntaxEntry

    @Test("TransferSyntaxEntry id equals uid")
    func testTransferSyntaxEntryIDEqualsUID() {
        let entry = TransferSyntaxEntry(
            uid: "1.2.840.10008.1.2.1",
            displayName: "Explicit VR Little Endian",
            shortName: "Explicit LE",
            isCompressed: false,
            isLossy: false,
            description: "Standard uncompressed"
        )
        #expect(entry.id == entry.uid)
    }

    @Test("TransferSyntaxEntry isCompressed and isLossy flags stored correctly")
    func testTransferSyntaxEntryFlags() {
        let compressed = TransferSyntaxEntry(
            uid: "1.2.840.10008.1.2.4.50",
            displayName: "JPEG Baseline",
            shortName: "JPEG",
            isCompressed: true,
            isLossy: true,
            description: "Lossy JPEG"
        )
        #expect(compressed.isCompressed == true)
        #expect(compressed.isLossy == true)
    }

    @Test("TransferSyntaxEntry uncompressed entry has isCompressed false")
    func testTransferSyntaxEntryUncompressed() {
        let entry = TransferSyntaxEntry(
            uid: "1.2.840.10008.1.2",
            displayName: "Implicit VR Little Endian",
            shortName: "Implicit LE",
            isCompressed: false,
            isLossy: false,
            description: "Default"
        )
        #expect(entry.isCompressed == false)
        #expect(entry.isLossy == false)
    }

    // MARK: - ConversionJobStatus

    @Test("ConversionJobStatus all cases have non-empty displayName")
    func testConversionJobStatusDisplayNames() {
        for status in ConversionJobStatus.allCases {
            #expect(!status.displayName.isEmpty)
        }
    }

    @Test("ConversionJobStatus has 4 cases")
    func testConversionJobStatusCaseCount() {
        #expect(ConversionJobStatus.allCases.count == 4)
    }

    // MARK: - TransferSyntaxConversionJob

    @Test("TransferSyntaxConversionJob init sets pending status")
    func testTransferSyntaxConversionJobInitStatus() {
        let job = TransferSyntaxConversionJob(
            sourceFilePath: "/tmp/test.dcm",
            targetTransferSyntaxUID: "1.2.840.10008.1.2.1"
        )
        #expect(job.status == .pending)
    }

    @Test("TransferSyntaxConversionJob init sets zero sizes")
    func testTransferSyntaxConversionJobInitSizes() {
        let job = TransferSyntaxConversionJob(
            sourceFilePath: "/tmp/test.dcm",
            targetTransferSyntaxUID: "1.2.840.10008.1.2.1"
        )
        #expect(job.originalSizeBytes == 0)
        #expect(job.convertedSizeBytes == 0)
    }

    @Test("TransferSyntaxConversionJob init errorMessage is nil")
    func testTransferSyntaxConversionJobInitError() {
        let job = TransferSyntaxConversionJob(
            sourceFilePath: "/tmp/test.dcm",
            targetTransferSyntaxUID: "1.2.840.10008.1.2.1"
        )
        #expect(job.errorMessage == nil)
    }

    @Test("TransferSyntaxConversionJob defaults intent to notApplicable")
    func testTransferSyntaxConversionJobDefaultIntent() {
        let job = TransferSyntaxConversionJob(
            sourceFilePath: "/tmp/test.dcm",
            targetTransferSyntaxUID: "1.2.840.10008.1.2.4.90"
        )
        #expect(job.intent == .notApplicable)
        // A lossless-only UID reads with its canonical name, no appended suffix.
        #expect(job.targetDisplayName == "JPEG 2000 Image Compression (Lossless Only)")  // PS3.6 Table A-1 (D176)
    }

    @Test("TransferSyntaxConversionJob carries lossless/lossy intent for a both-capable UID")
    func testTransferSyntaxConversionJobIntentDisplayName() {
        // .93 is a `both`-capable UID: the same UID with a different intent must yield
        // two distinct, intent-labelled display names so the selection is unambiguous.
        let lossless = TransferSyntaxConversionJob(
            sourceFilePath: "/tmp/test.dcm",
            targetTransferSyntaxUID: "1.2.840.10008.1.2.4.93",
            intent: .lossless
        )
        let lossy = TransferSyntaxConversionJob(
            sourceFilePath: "/tmp/test.dcm",
            targetTransferSyntaxUID: "1.2.840.10008.1.2.4.93",
            intent: .lossy
        )
        #expect(lossless.intent == .lossless)
        #expect(lossless.targetDisplayName == "JPEG 2000 Part 2 Multi-component Image Compression (lossless)")
        #expect(lossy.targetDisplayName == "JPEG 2000 Part 2 Multi-component Image Compression (lossy)")
        #expect(lossless.targetTransferSyntaxUID == lossy.targetTransferSyntaxUID)
    }

    // MARK: - DICOMDIREntry

    @Test("DICOMDIREntry init stores all fields correctly")
    func testDICOMDIREntryInit() {
        let entry = DICOMDIREntry(
            studyInstanceUID: "1.2.3.4.5",
            patientName: "Doe^John",
            patientID: "P001",
            studyDate: "20240101",
            modalities: ["CT", "PT"],
            seriesCount: 3,
            instanceCount: 120
        )
        #expect(entry.studyInstanceUID == "1.2.3.4.5")
        #expect(entry.patientName == "Doe^John")
        #expect(entry.modalities.count == 2)
        #expect(entry.seriesCount == 3)
        #expect(entry.instanceCount == 120)
    }

    @Test("DICOMDIREntry each init creates unique id")
    func testDICOMDIREntryUniqueID() {
        let a = DICOMDIREntry(studyInstanceUID: "1.2.3", patientName: "A", patientID: "1",
                              studyDate: "20240101", modalities: [], seriesCount: 1, instanceCount: 5)
        let b = DICOMDIREntry(studyInstanceUID: "1.2.3", patientName: "A", patientID: "1",
                              studyDate: "20240101", modalities: [], seriesCount: 1, instanceCount: 5)
        #expect(a.id != b.id)
    }

    // MARK: - PDFEncapsulationMode

    @Test("PDFEncapsulationMode all cases have non-empty displayName")
    func testPDFEncapsulationModeDisplayNames() {
        for mode in PDFEncapsulationMode.allCases {
            #expect(!mode.displayName.isEmpty)
        }
    }

    @Test("PDFEncapsulationMode all cases have non-empty description")
    func testPDFEncapsulationModeDescriptions() {
        for mode in PDFEncapsulationMode.allCases {
            #expect(!mode.description.isEmpty)
        }
    }

    @Test("PDFEncapsulationMode has 2 cases")
    func testPDFEncapsulationModeCaseCount() {
        #expect(PDFEncapsulationMode.allCases.count == 2)
    }

    // MARK: - BatchOperationType

    @Test("BatchOperationType all cases have non-empty displayName")
    func testBatchOperationTypeDisplayNames() {
        for type_ in BatchOperationType.allCases {
            #expect(!type_.displayName.isEmpty)
        }
    }

    @Test("BatchOperationType all cases have non-empty sfSymbol")
    func testBatchOperationTypeSFSymbols() {
        for type_ in BatchOperationType.allCases {
            #expect(!type_.sfSymbol.isEmpty)
        }
    }

    @Test("BatchOperationType has 4 cases")
    func testBatchOperationTypeCaseCount() {
        #expect(BatchOperationType.allCases.count == 4)
    }

    // MARK: - TagModificationOperation

    @Test("TagModificationOperation all cases have non-empty displayName")
    func testTagModificationOperationDisplayNames() {
        for op in TagModificationOperation.allCases {
            #expect(!op.displayName.isEmpty)
        }
    }

    @Test("TagModificationOperation has 3 cases")
    func testTagModificationOperationCaseCount() {
        #expect(TagModificationOperation.allCases.count == 3)
    }

    // MARK: - BatchTagModification

    @Test("BatchTagModification init stores fields correctly")
    func testBatchTagModificationInit() {
        let mod = BatchTagModification(
            tagKeyword: "PatientName",
            tagGroup: 0x0010,
            tagElement: 0x0010,
            operation: .update,
            newValue: "Anonymous"
        )
        #expect(mod.tagKeyword == "PatientName")
        #expect(mod.tagGroup == 0x0010)
        #expect(mod.tagElement == 0x0010)
        #expect(mod.operation == .update)
        #expect(mod.newValue == "Anonymous")
    }

    @Test("BatchTagModification each init creates unique id")
    func testBatchTagModificationUniqueID() {
        let a = BatchTagModification(tagKeyword: "PatientID", tagGroup: 0x0010, tagElement: 0x0020,
                                     operation: .remove, newValue: "")
        let b = BatchTagModification(tagKeyword: "PatientID", tagGroup: 0x0010, tagElement: 0x0020,
                                     operation: .remove, newValue: "")
        #expect(a.id != b.id)
    }

    // MARK: - BatchJobStatus

    @Test("BatchJobStatus all cases have non-empty displayName")
    func testBatchJobStatusDisplayNames() {
        for status in BatchJobStatus.allCases {
            #expect(!status.displayName.isEmpty)
        }
    }

    @Test("BatchJobStatus completed isTerminal is true")
    func testBatchJobStatusCompletedIsTerminal() {
        #expect(BatchJobStatus.completed.isTerminal == true)
    }

    @Test("BatchJobStatus completedWithErrors isTerminal is true")
    func testBatchJobStatusCompletedWithErrorsIsTerminal() {
        #expect(BatchJobStatus.completedWithErrors.isTerminal == true)
    }

    @Test("BatchJobStatus failed isTerminal is true")
    func testBatchJobStatusFailedIsTerminal() {
        #expect(BatchJobStatus.failed.isTerminal == true)
    }

    @Test("BatchJobStatus pending isTerminal is false")
    func testBatchJobStatusPendingIsTerminal() {
        #expect(BatchJobStatus.pending.isTerminal == false)
    }

    @Test("BatchJobStatus inProgress isTerminal is false")
    func testBatchJobStatusInProgressIsTerminal() {
        #expect(BatchJobStatus.inProgress.isTerminal == false)
    }

    @Test("BatchJobStatus completedWithErrors hasErrors is true")
    func testBatchJobStatusCompletedWithErrorsHasErrors() {
        #expect(BatchJobStatus.completedWithErrors.hasErrors == true)
    }

    @Test("BatchJobStatus failed hasErrors is true")
    func testBatchJobStatusFailedHasErrors() {
        #expect(BatchJobStatus.failed.hasErrors == true)
    }

    @Test("BatchJobStatus completed hasErrors is false")
    func testBatchJobStatusCompletedHasErrors() {
        #expect(BatchJobStatus.completed.hasErrors == false)
    }

    // MARK: - BatchJob

    @Test("BatchJob init sets pending status")
    func testBatchJobInitStatus() {
        let job = BatchJob(
            operationType: .anonymization,
            inputPaths: ["/tmp/a.dcm"],
            outputDirectory: "/tmp/out"
        )
        #expect(job.status == .pending)
    }

    @Test("BatchJob init sets zero counts")
    func testBatchJobInitCounts() {
        let job = BatchJob(
            operationType: .imageExport,
            inputPaths: [],
            outputDirectory: "/tmp/out"
        )
        #expect(job.processedCount == 0)
        #expect(job.failedCount == 0)
        #expect(job.totalCount == 0)
    }

    @Test("BatchJob init sets empty errorSummary")
    func testBatchJobInitErrorSummary() {
        let job = BatchJob(operationType: .tagModification, inputPaths: [], outputDirectory: "")
        #expect(job.errorSummary.isEmpty)
    }

    @Test("BatchJob each init creates unique id")
    func testBatchJobUniqueID() {
        let a = BatchJob(operationType: .anonymization, inputPaths: [], outputDirectory: "")
        let b = BatchJob(operationType: .anonymization, inputPaths: [], outputDirectory: "")
        #expect(a.id != b.id)
    }

    // MARK: - JSONConversionSettings

    @Test("JSONConversionSettings init default outputFormat is pretty")
    func testJSONConversionSettingsDefaultFormat() {
        let s = JSONConversionSettings()
        #expect(s.outputFormat == .pretty)
    }

    @Test("JSONConversionSettings init default includeBulkDataURIs is false")
    func testJSONConversionSettingsDefaultBulkData() {
        let s = JSONConversionSettings()
        #expect(s.includeBulkDataURIs == false)
    }

    @Test("JSONConversionSettings init default bulkDataThresholdBytes is 1024")
    func testJSONConversionSettingsDefaultThreshold() {
        let s = JSONConversionSettings()
        #expect(s.bulkDataThresholdBytes == 1024)
    }

    @Test("JSONConversionSettings init default metadataOnly is false")
    func testJSONConversionSettingsDefaultMetadataOnly() {
        let s = JSONConversionSettings()
        #expect(s.metadataOnly == false)
    }

    // MARK: - XMLConversionSettings

    @Test("XMLConversionSettings init default outputFormat is pretty")
    func testXMLConversionSettingsDefaultFormat() {
        let s = XMLConversionSettings()
        #expect(s.outputFormat == .pretty)
    }

    @Test("XMLConversionSettings init default bulkDataThresholdBytes is 1024")
    func testXMLConversionSettingsDefaultThreshold() {
        let s = XMLConversionSettings()
        #expect(s.bulkDataThresholdBytes == 1024)
    }

    @Test("XMLConversionSettings init default metadataOnly is false")
    func testXMLConversionSettingsDefaultMetadataOnly() {
        let s = XMLConversionSettings()
        #expect(s.metadataOnly == false)
    }

    // MARK: - ImageExportSettings

    @Test("ImageExportSettings init default format is png")
    func testImageExportSettingsDefaultFormat() {
        let s = ImageExportSettings()
        #expect(s.format == .png)
    }

    @Test("ImageExportSettings init default jpegQuality is 0.85")
    func testImageExportSettingsDefaultJPEGQuality() {
        let s = ImageExportSettings()
        #expect(abs(s.jpegQuality - 0.85) < 0.001)
    }

    @Test("ImageExportSettings init default resolution is original")
    func testImageExportSettingsDefaultResolution() {
        let s = ImageExportSettings()
        #expect(s.resolution == .original)
    }

    @Test("ImageExportSettings init default burnInAnnotations is false")
    func testImageExportSettingsDefaultBurnInAnnotations() {
        let s = ImageExportSettings()
        #expect(s.burnInAnnotations == false)
    }

    @Test("ImageExportSettings init default burnInWindowLevel is true")
    func testImageExportSettingsDefaultBurnInWindowLevel() {
        let s = ImageExportSettings()
        #expect(s.burnInWindowLevel == true)
    }

    @Test("ImageExportSettings init default exportAllFrames is false")
    func testImageExportSettingsDefaultExportAllFrames() {
        let s = ImageExportSettings()
        #expect(s.exportAllFrames == false)
    }
}
