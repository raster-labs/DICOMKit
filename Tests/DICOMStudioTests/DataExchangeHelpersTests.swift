// DataExchangeHelpersTests.swift
// DICOMStudioTests

import Testing
@testable import DICOMStudio
import DICOMCore
import Foundation

@Suite("Data Exchange Helpers Tests")
struct DataExchangeHelpersTests {

    // MARK: - JSONConversionHelpers.formatOutputSize

    @Test("JSONConversionHelpers formatOutputSize bytes less than 1024 shows bytes")
    func testJSONFormatOutputSizeBytes() {
        let result = JSONConversionHelpers.formatOutputSize(bytes: 512)
        #expect(result == "512 bytes")
    }

    @Test("JSONConversionHelpers formatOutputSize 1024 shows KB")
    func testJSONFormatOutputSizeKB() {
        let result = JSONConversionHelpers.formatOutputSize(bytes: 2048)
        #expect(result.contains("KB"))
    }

    @Test("JSONConversionHelpers formatOutputSize MB range")
    func testJSONFormatOutputSizeMB() {
        let result = JSONConversionHelpers.formatOutputSize(bytes: 2 * 1024 * 1024)
        #expect(result.contains("MB"))
    }

    @Test("JSONConversionHelpers bulkDataThresholdDescription contains byte count")
    func testJSONBulkDataThresholdDescription() {
        let result = JSONConversionHelpers.bulkDataThresholdDescription(bytes: 512)
        #expect(result.contains("512"))
    }

    @Test("JSONConversionHelpers validationError nil for valid settings")
    func testJSONValidationErrorNilForValid() {
        let settings = JSONConversionSettings()
        #expect(JSONConversionHelpers.validationError(for: settings) == nil)
    }

    @Test("JSONConversionHelpers validationError non-nil for negative threshold")
    func testJSONValidationErrorNegativeThreshold() {
        var settings = JSONConversionSettings()
        settings.bulkDataThresholdBytes = -1
        #expect(JSONConversionHelpers.validationError(for: settings) != nil)
    }

    @Test("JSONConversionHelpers outputFormatDescription returns non-empty string")
    func testJSONOutputFormatDescription() {
        for fmt in JSONOutputFormat.allCases {
            let result = JSONConversionHelpers.outputFormatDescription(fmt)
            #expect(!result.isEmpty)
        }
    }

    @Test("JSONConversionHelpers estimatedOutputSize compact equals input")
    func testJSONEstimatedOutputSizeCompact() {
        let result = JSONConversionHelpers.estimatedOutputSize(inputSizeBytes: 1000, format: .compact)
        #expect(result == 1000)
    }

    @Test("JSONConversionHelpers estimatedOutputSize pretty is larger than input")
    func testJSONEstimatedOutputSizePretty() {
        let result = JSONConversionHelpers.estimatedOutputSize(inputSizeBytes: 1000, format: .pretty)
        #expect(result > 1000)
    }

    @Test("JSONConversionHelpers estimatedOutputSize standard adds 512 bytes")
    func testJSONEstimatedOutputSizeStandard() {
        let result = JSONConversionHelpers.estimatedOutputSize(inputSizeBytes: 1000, format: .standard)
        #expect(result == 1512)
    }

    // MARK: - XMLConversionHelpers

    @Test("XMLConversionHelpers formatOutputSize bytes less than 1024")
    func testXMLFormatOutputSizeBytes() {
        let result = XMLConversionHelpers.formatOutputSize(bytes: 100)
        #expect(result == "100 bytes")
    }

    @Test("XMLConversionHelpers formatOutputSize KB range")
    func testXMLFormatOutputSizeKB() {
        let result = XMLConversionHelpers.formatOutputSize(bytes: 4096)
        #expect(result.contains("KB"))
    }

    @Test("XMLConversionHelpers validationError nil for valid settings")
    func testXMLValidationErrorNilForValid() {
        let settings = XMLConversionSettings()
        #expect(XMLConversionHelpers.validationError(for: settings) == nil)
    }

    @Test("XMLConversionHelpers validationError non-nil for negative threshold")
    func testXMLValidationErrorNegativeThreshold() {
        var settings = XMLConversionSettings()
        settings.bulkDataThresholdBytes = -10
        #expect(XMLConversionHelpers.validationError(for: settings) != nil)
    }

    @Test("XMLConversionHelpers estimatedOutputSize standard is 1.8x input")
    func testXMLEstimatedOutputSizeStandard() {
        let result = XMLConversionHelpers.estimatedOutputSize(inputSizeBytes: 1000, format: .standard)
        #expect(result == 1800)
    }

    @Test("XMLConversionHelpers estimatedOutputSize pretty is 2.1x input")
    func testXMLEstimatedOutputSizePretty() {
        let result = XMLConversionHelpers.estimatedOutputSize(inputSizeBytes: 1000, format: .pretty)
        #expect(result == 2100)
    }

    @Test("XMLConversionHelpers estimatedOutputSize noKeywords is 1.6x input")
    func testXMLEstimatedOutputSizeNoKeywords() {
        let result = XMLConversionHelpers.estimatedOutputSize(inputSizeBytes: 1000, format: .noKeywords)
        #expect(result == 1600)
    }

    // MARK: - ImageExportHelpers

    @Test("ImageExportHelpers jpegQualityLabel high quality")
    func testImageExportHelpersJpegQualityHigh() {
        #expect(ImageExportHelpers.jpegQualityLabel(for: 0.95) == "High")
    }

    @Test("ImageExportHelpers jpegQualityLabel medium quality")
    func testImageExportHelpersJpegQualityMedium() {
        #expect(ImageExportHelpers.jpegQualityLabel(for: 0.75) == "Medium")
    }

    @Test("ImageExportHelpers jpegQualityLabel low quality")
    func testImageExportHelpersJpegQualityLow() {
        #expect(ImageExportHelpers.jpegQualityLabel(for: 0.5) == "Low")
    }

    @Test("ImageExportHelpers scaleFactor original is 1.0")
    func testImageExportHelpersScaleFactorOriginal() {
        #expect(ImageExportHelpers.scaleFactor(for: .original) == 1.0)
    }

    @Test("ImageExportHelpers scaleFactor half is 0.5")
    func testImageExportHelpersScaleFactorHalf() {
        #expect(ImageExportHelpers.scaleFactor(for: .half) == 0.5)
    }

    @Test("ImageExportHelpers scaleFactor quarter is 0.25")
    func testImageExportHelpersScaleFactorQuarter() {
        #expect(ImageExportHelpers.scaleFactor(for: .quarter) == 0.25)
    }

    @Test("ImageExportHelpers outputDimensions original unchanged")
    func testImageExportHelpersOutputDimensionsOriginal() {
        let dims = ImageExportHelpers.outputDimensions(width: 512, height: 512, resolution: .original)
        #expect(dims.width == 512)
        #expect(dims.height == 512)
    }

    @Test("ImageExportHelpers outputDimensions half halves dimensions")
    func testImageExportHelpersOutputDimensionsHalf() {
        let dims = ImageExportHelpers.outputDimensions(width: 512, height: 256, resolution: .half)
        #expect(dims.width == 256)
        #expect(dims.height == 128)
    }

    @Test("ImageExportHelpers validationError nil for valid settings")
    func testImageExportHelpersValidationErrorNil() {
        let settings = ImageExportSettings()
        #expect(ImageExportHelpers.validationError(for: settings) == nil)
    }

    @Test("ImageExportHelpers validationError non-nil for quality above 1")
    func testImageExportHelpersValidationErrorAbove1() {
        var settings = ImageExportSettings()
        settings.jpegQuality = 1.5
        #expect(ImageExportHelpers.validationError(for: settings) != nil)
    }

    @Test("ImageExportHelpers validationError non-nil for negative quality")
    func testImageExportHelpersValidationErrorNegative() {
        var settings = ImageExportSettings()
        settings.jpegQuality = -0.1
        #expect(ImageExportHelpers.validationError(for: settings) != nil)
    }

    // MARK: - TransferSyntaxHelpers

    @Test("TransferSyntaxHelpers wellKnownSyntaxes has 8 entries")
    func testTransferSyntaxHelpersWellKnownCount() {
        #expect(TransferSyntaxHelpers.wellKnownSyntaxes.count == 8)
    }

    @Test("TransferSyntaxHelpers wellKnownSyntaxes all have non-empty displayName")
    func testTransferSyntaxHelpersWellKnownDisplayNames() {
        for entry in TransferSyntaxHelpers.wellKnownSyntaxes {
            #expect(!entry.displayName.isEmpty)
        }
    }

    @Test("TransferSyntaxHelpers wellKnownSyntaxes displayName is the PS3.6 2026a Table A-1 UID Name")
    func testTransferSyntaxHelpersWellKnownDisplayNamesAreTableA1() {
        let a1: [String: String] = [
            "1.2.840.10008.1.2": "Implicit VR Little Endian: Default Transfer Syntax for DICOM",
            "1.2.840.10008.1.2.1": "Explicit VR Little Endian",
            "1.2.840.10008.1.2.2": "Explicit VR Big Endian (Retired)",
            "1.2.840.10008.1.2.4.50": "JPEG Baseline (Process 1): Default Transfer Syntax for Lossy JPEG 8 Bit Image Compression",
            "1.2.840.10008.1.2.4.70": "JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14 [Selection Value 1]): Default Transfer Syntax for Lossless JPEG Image Compression",
            "1.2.840.10008.1.2.4.80": "JPEG-LS Lossless Image Compression",
            "1.2.840.10008.1.2.4.90": "JPEG 2000 Image Compression (Lossless Only)",
            "1.2.840.10008.1.2.5": "RLE Lossless",
        ]
        for entry in TransferSyntaxHelpers.wellKnownSyntaxes {
            #expect(entry.displayName == a1[entry.uid], "\(entry.uid)")
            #expect(entry.displayName == TransferSyntax.from(uid: entry.uid)?.displayName, "\(entry.uid)")
        }
        #expect(Set(a1.keys) == Set(TransferSyntaxHelpers.wellKnownSyntaxes.map(\.uid)))
    }

    @Test("TransferSyntaxHelpers wellKnownSyntaxes ids equal uids")
    func testTransferSyntaxHelpersWellKnownIDs() {
        for entry in TransferSyntaxHelpers.wellKnownSyntaxes {
            #expect(entry.id == entry.uid)
        }
    }

    @Test("TransferSyntaxHelpers compressionRatioDescription with zero original returns N/A")
    func testTransferSyntaxHelpersCompressionRatioZeroOriginal() {
        let result = TransferSyntaxHelpers.compressionRatioDescription(originalBytes: 0, compressedBytes: 1000)
        #expect(result == "N/A")
    }

    @Test("TransferSyntaxHelpers compressionRatioDescription returns ratio string")
    func testTransferSyntaxHelpersCompressionRatioNormal() {
        let result = TransferSyntaxHelpers.compressionRatioDescription(originalBytes: 2000, compressedBytes: 1000)
        #expect(result.contains(":1"))
    }

    @Test("TransferSyntaxHelpers sizeDifferenceLabel zero converted returns N/A")
    func testTransferSyntaxHelpersSizeDifferenceLabelZeroConverted() {
        let result = TransferSyntaxHelpers.sizeDifferenceLabel(originalBytes: 1000, convertedBytes: 0)
        #expect(result == "N/A")
    }

    @Test("TransferSyntaxHelpers sizeDifferenceLabel equal sizes returns unchanged")
    func testTransferSyntaxHelpersSizeDifferenceLabelUnchanged() {
        let result = TransferSyntaxHelpers.sizeDifferenceLabel(originalBytes: 1000, convertedBytes: 1000)
        #expect(result == "unchanged")
    }

    @Test("TransferSyntaxHelpers sizeDifferenceLabel smaller converted shows minus")
    func testTransferSyntaxHelpersSizeDifferenceLabelSmaller() {
        let result = TransferSyntaxHelpers.sizeDifferenceLabel(originalBytes: 2000, convertedBytes: 1000)
        #expect(result.hasPrefix("-"))
    }

    @Test("TransferSyntaxHelpers validationError nil for valid job")
    func testTransferSyntaxHelpersValidationErrorNil() {
        let job = TransferSyntaxConversionJob(sourceFilePath: "/tmp/test.dcm", targetTransferSyntaxUID: "1.2.840.10008.1.2.1")
        #expect(TransferSyntaxHelpers.validationError(for: job) == nil)
    }

    @Test("TransferSyntaxHelpers validationError non-nil for empty path")
    func testTransferSyntaxHelpersValidationErrorEmptyPath() {
        let job = TransferSyntaxConversionJob(sourceFilePath: "", targetTransferSyntaxUID: "1.2.840.10008.1.2.1")
        #expect(TransferSyntaxHelpers.validationError(for: job) != nil)
    }

    // MARK: - DICOMDIRHelpers

    @Test("DICOMDIRHelpers totalInstanceCount sums all entries")
    func testDICOMDIRHelpersTotalInstanceCount() {
        let entries = [
            DICOMDIREntry(studyInstanceUID: "1", patientName: "A", patientID: "1",
                          studyDate: "20240101", modalities: ["CT"], seriesCount: 2, instanceCount: 50),
            DICOMDIREntry(studyInstanceUID: "2", patientName: "B", patientID: "2",
                          studyDate: "20240102", modalities: ["MR"], seriesCount: 3, instanceCount: 80)
        ]
        #expect(DICOMDIRHelpers.totalInstanceCount(entries: entries) == 130)
    }

    @Test("DICOMDIRHelpers totalSeriesCount sums all entries")
    func testDICOMDIRHelpersTotalSeriesCount() {
        let entries = [
            DICOMDIREntry(studyInstanceUID: "1", patientName: "A", patientID: "1",
                          studyDate: "20240101", modalities: ["CT"], seriesCount: 2, instanceCount: 10),
            DICOMDIREntry(studyInstanceUID: "2", patientName: "B", patientID: "2",
                          studyDate: "20240102", modalities: ["MR"], seriesCount: 4, instanceCount: 20)
        ]
        #expect(DICOMDIRHelpers.totalSeriesCount(entries: entries) == 6)
    }

    @Test("DICOMDIRHelpers uniqueModalities returns sorted unique modalities")
    func testDICOMDIRHelpersUniqueModalities() {
        let entries = [
            DICOMDIREntry(studyInstanceUID: "1", patientName: "A", patientID: "1",
                          studyDate: "20240101", modalities: ["CT", "PT"], seriesCount: 2, instanceCount: 10),
            DICOMDIREntry(studyInstanceUID: "2", patientName: "B", patientID: "2",
                          studyDate: "20240102", modalities: ["CT", "MR"], seriesCount: 3, instanceCount: 20)
        ]
        let result = DICOMDIRHelpers.uniqueModalities(entries: entries)
        #expect(result == ["CT", "MR", "PT"])
    }

    @Test("DICOMDIRHelpers estimatedDiskUsage returns non-empty string")
    func testDICOMDIRHelpersEstimatedDiskUsage() {
        let result = DICOMDIRHelpers.estimatedDiskUsage(instanceCount: 100)
        #expect(!result.isEmpty)
    }

    @Test("DICOMDIRHelpers validationError nil for valid entry")
    func testDICOMDIRHelpersValidationErrorNil() {
        let entry = DICOMDIREntry(studyInstanceUID: "1.2.3.4", patientName: "Test",
                                  patientID: "001", studyDate: "20240101",
                                  modalities: ["CT"], seriesCount: 1, instanceCount: 10)
        #expect(DICOMDIRHelpers.validationError(for: entry) == nil)
    }

    @Test("DICOMDIRHelpers validationError non-nil for empty studyInstanceUID")
    func testDICOMDIRHelpersValidationErrorEmptyUID() {
        let entry = DICOMDIREntry(studyInstanceUID: "", patientName: "Test",
                                  patientID: "001", studyDate: "20240101",
                                  modalities: [], seriesCount: 1, instanceCount: 10)
        #expect(DICOMDIRHelpers.validationError(for: entry) != nil)
    }

    // MARK: - PDFEncapsulationHelpers

    @Test("PDFEncapsulationHelpers modeDescription returns non-empty string")
    func testPDFEncapsulationHelpersModeDescription() {
        for mode in PDFEncapsulationMode.allCases {
            let result = PDFEncapsulationHelpers.modeDescription(mode)
            #expect(!result.isEmpty)
        }
    }

    @Test("PDFEncapsulationHelpers encapsulatedSOPClassUID returns correct UID")
    func testPDFEncapsulationHelpersSOPClassUID() {
        let uid = PDFEncapsulationHelpers.encapsulatedSOPClassUID()
        #expect(uid == "1.2.840.10008.5.1.4.1.1.104.1")
    }

    @Test("PDFEncapsulationHelpers validationError nil for valid paths")
    func testPDFEncapsulationHelpersValidationErrorNil() {
        let result = PDFEncapsulationHelpers.validationError(inputPath: "/tmp/in.pdf", outputPath: "/tmp/out.dcm")
        #expect(result == nil)
    }

    @Test("PDFEncapsulationHelpers validationError non-nil for empty inputPath")
    func testPDFEncapsulationHelpersValidationErrorEmptyInput() {
        let result = PDFEncapsulationHelpers.validationError(inputPath: "", outputPath: "/tmp/out.dcm")
        #expect(result != nil)
    }

    @Test("PDFEncapsulationHelpers validationError non-nil for empty outputPath")
    func testPDFEncapsulationHelpersValidationErrorEmptyOutput() {
        let result = PDFEncapsulationHelpers.validationError(inputPath: "/tmp/in.pdf", outputPath: "")
        #expect(result != nil)
    }

    // MARK: - BatchOperationHelpers

    @Test("BatchOperationHelpers progressFraction zero for empty job")
    func testBatchOperationHelpersProgressFractionEmpty() {
        let job = BatchJob(operationType: .anonymization, inputPaths: [], outputDirectory: "")
        #expect(BatchOperationHelpers.progressFraction(job: job) == 0.0)
    }

    @Test("BatchOperationHelpers progressFraction calculates correctly")
    func testBatchOperationHelpersProgressFraction() {
        var job = BatchJob(operationType: .anonymization, inputPaths: [], outputDirectory: "")
        job.totalCount = 10
        job.processedCount = 3
        job.failedCount = 2
        let fraction = BatchOperationHelpers.progressFraction(job: job)
        #expect(abs(fraction - 0.5) < 0.001)
    }

    @Test("BatchOperationHelpers statusDescription returns non-empty string")
    func testBatchOperationHelpersStatusDescription() {
        for status in BatchJobStatus.allCases {
            var job = BatchJob(operationType: .imageExport, inputPaths: [], outputDirectory: "")
            job.status = status
            job.totalCount = 10
            job.processedCount = 5
            let result = BatchOperationHelpers.statusDescription(job: job)
            #expect(!result.isEmpty)
        }
    }

    @Test("BatchOperationHelpers operationTypeDescription returns non-empty for all types")
    func testBatchOperationHelpersOperationTypeDescription() {
        for type_ in BatchOperationType.allCases {
            let result = BatchOperationHelpers.operationTypeDescription(type_)
            #expect(!result.isEmpty)
        }
    }

    @Test("BatchOperationHelpers canAddMoreItems true for pending job")
    func testBatchOperationHelpersCanAddMoreItemsPending() {
        let job = BatchJob(operationType: .tagModification, inputPaths: [], outputDirectory: "")
        #expect(BatchOperationHelpers.canAddMoreItems(job: job) == true)
    }

    @Test("BatchOperationHelpers canAddMoreItems false for completed job")
    func testBatchOperationHelpersCanAddMoreItemsCompleted() {
        var job = BatchJob(operationType: .tagModification, inputPaths: [], outputDirectory: "")
        job.status = .completed
        #expect(BatchOperationHelpers.canAddMoreItems(job: job) == false)
    }
}
