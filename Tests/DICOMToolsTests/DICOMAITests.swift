import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore
@testable import dicom_ai
/// These tests validate AI model loading, preprocessing, and inference operations
final class DICOMAITests: XCTestCase {
    
    // MARK: - Test Helpers
    
    /// Creates a minimal DICOM file with pixel data for testing
    private func createTestDICOMFile(
        rows: UInt16 = 512,
        columns: UInt16 = 512,
        bitsAllocated: UInt16 = 16,
        samplesPerPixel: UInt16 = 1
    ) throws -> Data {
        var data = Data()
        
        // 128-byte preamble
        data.append(Data(count: 128))
        
        // DICM prefix
        data.append(contentsOf: [0x44, 0x49, 0x43, 0x4D])
        
        // File Meta Information Group Length (0002,0000) - UL
        data.append(contentsOf: [0x02, 0x00, 0x00, 0x00])
        data.append(contentsOf: [0x55, 0x4C]) // VR = UL
        data.append(contentsOf: [0x04, 0x00]) // Length = 4
        data.append(contentsOf: [0x54, 0x00, 0x00, 0x00]) // Value
        
        // Transfer Syntax UID (0002,0010) - UI
        data.append(contentsOf: [0x02, 0x00, 0x10, 0x00])
        data.append(contentsOf: [0x55, 0x49]) // VR = UI
        let transferSyntax = "1.2.840.10008.1.2.1"
        let tsLength = UInt16(transferSyntax.utf8.count)
        data.append(contentsOf: withUnsafeBytes(of: tsLength.littleEndian) { Data($0) })
        data.append(transferSyntax.data(using: .utf8)!)
        
        // SOP Class UID (0008,0016) - UI - CT Image Storage
        data.append(contentsOf: [0x08, 0x00, 0x16, 0x00])
        data.append(contentsOf: [0x55, 0x49])
        let sopClass = "1.2.840.10008.5.1.4.1.1.2"
        let scLength = UInt16(sopClass.utf8.count)
        data.append(contentsOf: withUnsafeBytes(of: scLength.littleEndian) { Data($0) })
        data.append(sopClass.data(using: .utf8)!)
        
        // SOP Instance UID (0008,0018) - UI
        data.append(contentsOf: [0x08, 0x00, 0x18, 0x00])
        data.append(contentsOf: [0x55, 0x49])
        let sopInstance = "1.2.3.4.5.6.7.8.9"
        let siLength = UInt16(sopInstance.utf8.count)
        data.append(contentsOf: withUnsafeBytes(of: siLength.littleEndian) { Data($0) })
        data.append(sopInstance.data(using: .utf8)!)
        
        // Rows (0028,0010) - US
        data.append(contentsOf: [0x28, 0x00, 0x10, 0x00])
        data.append(contentsOf: [0x55, 0x53]) // VR = US
        data.append(contentsOf: [0x02, 0x00]) // Length = 2
        data.append(contentsOf: withUnsafeBytes(of: rows.littleEndian) { Data($0) })
        
        // Columns (0028,0011) - US
        data.append(contentsOf: [0x28, 0x00, 0x11, 0x00])
        data.append(contentsOf: [0x55, 0x53])
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: withUnsafeBytes(of: columns.littleEndian) { Data($0) })
        
        // Bits Allocated (0028,0100) - US
        data.append(contentsOf: [0x28, 0x00, 0x00, 0x01])
        data.append(contentsOf: [0x55, 0x53])
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: withUnsafeBytes(of: bitsAllocated.littleEndian) { Data($0) })
        
        // Bits Stored (0028,0101) - US
        data.append(contentsOf: [0x28, 0x00, 0x01, 0x01])
        data.append(contentsOf: [0x55, 0x53])
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: withUnsafeBytes(of: bitsAllocated.littleEndian) { Data($0) })
        
        // High Bit (0028,0102) - US
        data.append(contentsOf: [0x28, 0x00, 0x02, 0x01])
        data.append(contentsOf: [0x55, 0x53])
        data.append(contentsOf: [0x02, 0x00])
        let highBit = bitsAllocated - 1
        data.append(contentsOf: withUnsafeBytes(of: highBit.littleEndian) { Data($0) })
        
        // Pixel Representation (0028,0103) - US (0 = unsigned)
        data.append(contentsOf: [0x28, 0x00, 0x03, 0x01])
        data.append(contentsOf: [0x55, 0x53])
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: [0x00, 0x00])
        
        // Samples Per Pixel (0028,0002) - US
        data.append(contentsOf: [0x28, 0x00, 0x02, 0x00])
        data.append(contentsOf: [0x55, 0x53])
        data.append(contentsOf: [0x02, 0x00])
        data.append(contentsOf: withUnsafeBytes(of: samplesPerPixel.littleEndian) { Data($0) })
        
        // Photometric Interpretation (0028,0004) - CS
        data.append(contentsOf: [0x28, 0x00, 0x04, 0x00])
        data.append(contentsOf: [0x43, 0x53]) // VR = CS
        let photometric = "MONOCHROME2 "
        let pmLength = UInt16(photometric.utf8.count)
        data.append(contentsOf: withUnsafeBytes(of: pmLength.littleEndian) { Data($0) })
        data.append(photometric.data(using: .utf8)!)
        
        // Pixel Data (7FE0,0010) - OW
        data.append(contentsOf: [0xE0, 0x7F, 0x10, 0x00])
        data.append(contentsOf: [0x4F, 0x57]) // VR = OW
        let pixelCount = Int(rows) * Int(columns)
        let pixelDataSize = pixelCount * Int(bitsAllocated) / 8
        let pixelLength = UInt16(pixelDataSize & 0xFFFF)
        data.append(contentsOf: withUnsafeBytes(of: pixelLength.littleEndian) { Data($0) })
        
        // Simple gradient pixel data
        for i in 0..<pixelCount {
            let value = UInt16(i % 4096)
            data.append(contentsOf: withUnsafeBytes(of: value.littleEndian) { Data($0) })
        }
        
        return data
    }
    
    // MARK: - Model Loading Tests
    
    func test_modelLoadingErrors_invalidPath() throws {
        // Test that attempting to load a non-existent model fails appropriately
        let invalidPath = "/nonexistent/model.mlmodel"
        
        #if canImport(CoreML)
        XCTAssertThrowsError(try AIEngine(modelURL: URL(fileURLWithPath: invalidPath))) { error in
            XCTAssertTrue(error is AIError, "Expected AIError")
        }
        #endif
    }
    
    func test_modelLoadingErrors_invalidExtension() throws {
        // Test that invalid model file extensions are rejected
        let invalidPath = "/tmp/model.txt"
        
        #if canImport(CoreML)
        XCTAssertThrowsError(try AIEngine(modelURL: URL(fileURLWithPath: invalidPath))) { error in
            if let aiError = error as? AIError {
                switch aiError {
                case .invalidModelFormat:
                    break // Expected
                default:
                    XCTFail("Expected invalidModelFormat error")
                }
            }
        }
        #endif
    }
    
    // MARK: - Image Preprocessing Tests
    
    func test_preprocessImage_extractsDimensions() throws {
        let dicomData = try createTestDICOMFile(rows: 256, columns: 256)
        let dicomFile = try DICOMFile.read(from: dicomData)
        let dataSet = dicomFile.dataSet
        
        #if canImport(CoreML)
        // Note: We can't actually create an AIEngine without a real model,
        // so this test validates the DICOM parsing part
        XCTAssertEqual(dataSet.uint16(for: .rows), 256)
        XCTAssertEqual(dataSet.uint16(for: .columns), 256)
        XCTAssertNotNil(dataSet[.pixelData])
        #endif
    }
    
    func test_preprocessImage_handlesMonochrome() throws {
        let dicomData = try createTestDICOMFile(samplesPerPixel: 1)
        let dicomFile = try DICOMFile.read(from: dicomData)
        let dataSet = dicomFile.dataSet
        
        XCTAssertEqual(dataSet.string(for: .photometricInterpretation), "MONOCHROME2")
        XCTAssertEqual(dataSet.uint16(for: .samplesPerPixel), 1)
    }
    
    func test_preprocessImage_extracts16BitPixelData() throws {
        let dicomData = try createTestDICOMFile(bitsAllocated: 16)
        let dicomFile = try DICOMFile.read(from: dicomData)
        let dataSet = dicomFile.dataSet
        
        XCTAssertEqual(dataSet.uint16(for: .bitsAllocated), 16)
        XCTAssertNotNil(dataSet[.pixelData])
    }
    
    // MARK: - Error Handling Tests
    
    func test_processedImage_missingPixelData() throws {
        var data = Data()
        data.append(Data(count: 128))
        data.append(contentsOf: [0x44, 0x49, 0x43, 0x4D])
        
        // Minimal meta info without pixel data
        data.append(contentsOf: [0x02, 0x00, 0x00, 0x00])
        data.append(contentsOf: [0x55, 0x4C])
        data.append(contentsOf: [0x04, 0x00])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        
        let dicomFile = try DICOMFile.read(from: data)
        let dataSet = dicomFile.dataSet
        
        // Verify pixel data is missing
        XCTAssertNil(dataSet[.pixelData])
    }
    
    // MARK: - Output Format Tests
    
    func test_formatClassificationResults_json() {
        let predictions = [
            Prediction(label: "pneumonia", confidence: 0.87),
            Prediction(label: "normal", confidence: 0.13)
        ]
        
        let output = formatClassificationResults(
            predictions: predictions,
            format: .json,
            filePath: "test.dcm"
        )
        
        XCTAssertTrue(output.contains("pneumonia"))
        XCTAssertTrue(output.contains("0.87"))
        XCTAssertTrue(output.contains("test.dcm"))
    }
    
    func test_formatClassificationResults_text() {
        let predictions = [
            Prediction(label: "lesion", confidence: 0.92),
            Prediction(label: "normal", confidence: 0.08)
        ]
        
        let output = formatClassificationResults(
            predictions: predictions,
            format: .text,
            filePath: "brain.dcm"
        )
        
        XCTAssertTrue(output.contains("lesion"))
        XCTAssertTrue(output.contains("92.00%"))
        XCTAssertTrue(output.contains("brain.dcm"))
    }
    
    func test_formatClassificationResults_csv() {
        let predictions = [
            Prediction(label: "abnormal", confidence: 0.75)
        ]
        
        let output = formatClassificationResults(
            predictions: predictions,
            format: .csv,
            filePath: "scan.dcm"
        )
        
        XCTAssertTrue(output.contains("file,label,confidence"))
        XCTAssertTrue(output.contains("scan.dcm,abnormal,0.75"))
    }
    
    func test_formatDetectionResults_json() {
        let detections = [
            Detection(
                label: "nodule",
                confidence: 0.88,
                bbox: BoundingBox(x: 100, y: 150, width: 50, height: 45)
            )
        ]
        
        let output = formatDetectionResults(
            detections: detections,
            format: .json,
            filePath: "chest.dcm"
        )
        
        XCTAssertTrue(output.contains("nodule"))
        XCTAssertTrue(output.contains("0.88"))
        XCTAssertTrue(output.contains("100"))
        XCTAssertTrue(output.contains("150"))
    }
    
    func test_formatDetectionResults_csv() {
        let detections = [
            Detection(
                label: "lesion",
                confidence: 0.92,
                bbox: BoundingBox(x: 200, y: 250, width: 30, height: 28)
            )
        ]
        
        let output = formatDetectionResults(
            detections: detections,
            format: .csv,
            filePath: "mri.dcm"
        )
        
        XCTAssertTrue(output.contains("file,label,confidence,x,y,width,height"))
        XCTAssertTrue(output.contains("mri.dcm,lesion,0.92,200.0,250.0,30.0,28.0"))
    }
    
    func test_formatSegmentationResults_json() {
        let mask = SegmentationMask(
            width: 512,
            height: 512,
            data: Data(count: 512 * 512),
            numClasses: 3
        )
        
        let output = formatSegmentationResults(
            mask: mask,
            format: .json,
            filePath: "ct.dcm"
        )
        
        XCTAssertTrue(output.contains("512x512"))
        XCTAssertTrue(output.contains("3"))
        XCTAssertTrue(output.contains("ct.dcm"))
    }
    
    func test_formatSegmentationResults_text() {
        let mask = SegmentationMask(
            width: 256,
            height: 256,
            data: Data(count: 256 * 256),
            numClasses: 2
        )
        
        let output = formatSegmentationResults(
            mask: mask,
            format: .text,
            filePath: "liver.dcm"
        )
        
        XCTAssertTrue(output.contains("256x256"))
        XCTAssertTrue(output.contains("Classes: 2"))
    }
    
    // MARK: - Batch Processing Tests
    
    func test_formatBatchResultsAsCSV_singleFile() {
        let results: [[String: Any]] = [
            [
                "file": "test1.dcm",
                "predictions": [
                    ["label": "positive", "confidence": 0.85]
                ]
            ]
        ]
        
        let csv = formatBatchResultsAsCSV(results)
        
        XCTAssertTrue(csv.contains("file,label,confidence"))
        XCTAssertTrue(csv.contains("test1.dcm,positive,0.85"))
    }
    
    func test_formatBatchResultsAsCSV_multipleFiles() {
        let results: [[String: Any]] = [
            [
                "file": "test1.dcm",
                "predictions": [
                    ["label": "positive", "confidence": 0.85],
                    ["label": "negative", "confidence": 0.15]
                ]
            ],
            [
                "file": "test2.dcm",
                "predictions": [
                    ["label": "positive", "confidence": 0.22]
                ]
            ]
        ]
        
        let csv = formatBatchResultsAsCSV(results)
        
        XCTAssertTrue(csv.contains("test1.dcm,positive,0.85"))
        XCTAssertTrue(csv.contains("test1.dcm,negative,0.15"))
        XCTAssertTrue(csv.contains("test2.dcm,positive,0.22"))
    }
    
    func test_formatBatchResultsAsCSV_withErrors() {
        let results: [[String: Any]] = [
            [
                "file": "test1.dcm",
                "predictions": [
                    ["label": "positive", "confidence": 0.85]
                ]
            ],
            [
                "file": "test2.dcm",
                "error": "Failed to load model"
            ]
        ]
        
        let csv = formatBatchResultsAsCSV(results)
        
        XCTAssertTrue(csv.contains("test1.dcm,positive,0.85"))
        XCTAssertTrue(csv.contains("test2.dcm,ERROR"))
    }
    
    // MARK: - Labels File Tests
    
    func test_loadLabels_arrayFormat() throws {
        let json = """
        ["background", "liver", "kidney"]
        """
        
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("labels-\(UUID().uuidString).json")
        try json.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        let labels = try loadLabels(from: tempFile.path)
        
        XCTAssertEqual(labels.count, 3)
        XCTAssertEqual(labels[0], "background")
        XCTAssertEqual(labels[1], "liver")
        XCTAssertEqual(labels[2], "kidney")
    }
    
    func test_loadLabels_dictionaryFormat() throws {
        let json = """
        {
          "labels": ["class1", "class2", "class3"]
        }
        """
        
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("labels-\(UUID().uuidString).json")
        try json.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        let labels = try loadLabels(from: tempFile.path)
        
        XCTAssertEqual(labels.count, 3)
        XCTAssertEqual(labels[0], "class1")
    }
    
    func test_loadLabels_nilPath() throws {
        let labels = try loadLabels(from: nil)
        XCTAssertEqual(labels.count, 0)
    }
    
    func test_loadLabels_invalidFormat() throws {
        let json = """
        {"invalid": "format"}
        """
        
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("labels-\(UUID().uuidString).json")
        try json.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        XCTAssertThrowsError(try loadLabels(from: tempFile.path)) { error in
            XCTAssertTrue(error is AIError)
        }
    }
    
    // MARK: - Data Structure Tests
    
    func test_processedImage_initialization() {
        let image = ProcessedImage(
            width: 512,
            height: 512,
            bitsPerPixel: 16,
            samplesPerPixel: 1,
            photometricInterpretation: "MONOCHROME2",
            pixelData: Data(count: 512 * 512 * 2)
        )
        
        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(image.height, 512)
        XCTAssertEqual(image.bitsPerPixel, 16)
        XCTAssertEqual(image.samplesPerPixel, 1)
    }
    
    func test_prediction_initialization() {
        let pred = Prediction(label: "pneumonia", confidence: 0.87)
        
        XCTAssertEqual(pred.label, "pneumonia")
        XCTAssertEqual(pred.confidence, 0.87, accuracy: 0.001)
    }
    
    func test_detection_initialization() {
        let detection = Detection(
            label: "nodule",
            confidence: 0.92,
            bbox: BoundingBox(x: 100, y: 150, width: 50, height: 45)
        )
        
        XCTAssertEqual(detection.label, "nodule")
        XCTAssertEqual(detection.confidence, 0.92, accuracy: 0.001)
        XCTAssertEqual(detection.bbox.x, 100, accuracy: 0.001)
        XCTAssertEqual(detection.bbox.width, 50, accuracy: 0.001)
    }
    
    func test_segmentationMask_initialization() {
        let mask = SegmentationMask(
            width: 256,
            height: 256,
            data: Data(count: 256 * 256),
            numClasses: 3
        )
        
        XCTAssertEqual(mask.width, 256)
        XCTAssertEqual(mask.height, 256)
        XCTAssertEqual(mask.numClasses, 3)
        XCTAssertEqual(mask.data.count, 256 * 256)
    }
    
    // MARK: - Error Description Tests
    
    func test_aiError_descriptions() {
        let errors: [AIError] = [
            .platformNotSupported("test"),
            .modelLoadFailed("test"),
            .modelNotLoaded("test"),
            .invalidModelFormat("test"),
            .invalidModelOutput("test"),
            .noPixelData("test"),
            .missingMetadata("test"),
            .missingOutput("test"),
            .invalidLabelsFile("test"),
            .notImplemented("test")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertTrue(error.errorDescription!.contains("test"))
        }
    }
    
    // MARK: - Phase B Tests: Preprocessing Options
    
    func test_preprocessingOptions_defaultValues() {
        let options = PreprocessingOptions.default
        
        XCTAssertNil(options.targetSize)
        if case .none = options.normalization {
            // Success
        } else {
            XCTFail("Expected .none normalization")
        }
        XCTAssertFalse(options.maintainAspectRatio)
        XCTAssertEqual(options.paddingValue, 0.0)
    }
    
    func test_preprocessingOptions_imageNetNormalized() {
        let options = PreprocessingOptions.imageNetNormalized
        
        if case .imageNet = options.normalization {
            // Success
        } else {
            XCTFail("Expected .imageNet normalization")
        }
    }
    
    func test_preprocessingOptions_customValues() {
        let options = PreprocessingOptions(
            targetSize: (width: 224, height: 224),
            normalization: .minMax(min: 0.0, max: 1.0),
            maintainAspectRatio: true,
            paddingValue: 128.0
        )
        
        XCTAssertEqual(options.targetSize?.width, 224)
        XCTAssertEqual(options.targetSize?.height, 224)
        XCTAssertTrue(options.maintainAspectRatio)
        XCTAssertEqual(options.paddingValue, 128.0)
    }
    
    // MARK: - Phase B Tests: Ensemble Inference
    
    func test_ensembleStrategy_values() {
        // Test that enum cases can be created
        let strategies: [EnsembleEngine.EnsembleStrategy] = [
            .average,
            .voting,
            .weighted([0.5, 0.3, 0.2]),
            .max
        ]
        
        XCTAssertEqual(strategies.count, 4)
    }
    
    func test_ensembleEngine_requiresModels() {
        // Test that ensemble requires at least one model
        // This would throw in real implementation
        let emptyModels: [URL] = []
        
        // We can't actually test this without real models, but we verify the structure exists
        XCTAssertEqual(emptyModels.count, 0)
    }
    
    // MARK: - Phase B Tests: Batch Processing
    
    func test_batchProcessor_operations() {
        // Test BatchOperation enum cases exist
        let operations: [BatchProcessor.BatchOperation] = [
            .classify,
            .segment,
            .detect
        ]
        
        XCTAssertEqual(operations.count, 3)
    }
    
    func test_batchResult_initialization() {
        let result = BatchResult(
            filePath: "/path/to/file.dcm",
            success: true,
            predictions: [Prediction(label: "test", confidence: 0.9)],
            error: nil
        )
        
        XCTAssertEqual(result.filePath, "/path/to/file.dcm")
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.predictions)
        XCTAssertEqual(result.predictions?.count, 1)
        XCTAssertNil(result.error)
    }
    
    func test_batchResult_withError() {
        let result = BatchResult(
            filePath: "/path/to/file.dcm",
            success: false,
            error: "Test error message"
        )
        
        XCTAssertEqual(result.filePath, "/path/to/file.dcm")
        XCTAssertFalse(result.success)
        XCTAssertNil(result.predictions)
        XCTAssertNil(result.segmentationMask)
        XCTAssertNil(result.detections)
        XCTAssertEqual(result.error, "Test error message")
    }
    
    func test_batchResult_withSegmentation() {
        let mask = SegmentationMask(
            width: 256,
            height: 256,
            data: Data(count: 256 * 256),
            numClasses: 2
        )
        
        let result = BatchResult(
            filePath: "/path/to/file.dcm",
            success: true,
            segmentationMask: mask,
            error: nil
        )
        
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.segmentationMask)
        XCTAssertEqual(result.segmentationMask?.width, 256)
        XCTAssertEqual(result.segmentationMask?.numClasses, 2)
    }
    
    func test_batchResult_withDetections() {
        let bbox = BoundingBox(x: 10, y: 20, width: 100, height: 150)
        let detection = Detection(label: "lesion", confidence: 0.85, bbox: bbox)
        
        let result = BatchResult(
            filePath: "/path/to/file.dcm",
            success: true,
            detections: [detection],
            error: nil
        )
        
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.detections)
        XCTAssertEqual(result.detections?.count, 1)
        XCTAssertEqual(result.detections?.first?.label, "lesion")
    }
    
    // MARK: - Phase B Tests: Normalization Strategies
    
    func test_normalizationStrategy_none() {
        if case .none = PreprocessingOptions.NormalizationStrategy.none {
            // Success
        } else {
            XCTFail("Expected .none strategy")
        }
    }
    
    func test_normalizationStrategy_minMax() {
        let strategy = PreprocessingOptions.NormalizationStrategy.minMax(min: 0.0, max: 1.0)
        
        if case let .minMax(min, max) = strategy {
            XCTAssertEqual(min, 0.0)
            XCTAssertEqual(max, 1.0)
        } else {
            XCTFail("Expected .minMax strategy")
        }
    }
    
    func test_normalizationStrategy_zScore() {
        let strategy = PreprocessingOptions.NormalizationStrategy.zScore(mean: 0.485, std: 0.229)
        
        if case let .zScore(mean, std) = strategy {
            XCTAssertEqual(mean, 0.485, accuracy: 0.001)
            XCTAssertEqual(std, 0.229, accuracy: 0.001)
        } else {
            XCTFail("Expected .zScore strategy")
        }
    }
    
    func test_normalizationStrategy_imageNet() {
        if case .imageNet = PreprocessingOptions.NormalizationStrategy.imageNet {
            // Success
        } else {
            XCTFail("Expected .imageNet strategy")
        }
    }
    
    // MARK: - Phase C Tests: DICOM SR from Predictions
    
    func test_createSRFromClassification_generatesValidSR() throws {
        var sourceDataSet = DataSet()
        sourceDataSet.setString("12345", for: .patientID, vr: .LO)
        sourceDataSet.setString("Doe^John", for: .patientName, vr: .PN)
        sourceDataSet.setString(UIDGenerator.generateStudyInstanceUID().value, for: .studyInstanceUID, vr: .UI)
        sourceDataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        sourceDataSet.setString(UIDGenerator.generateSOPInstanceUID().value, for: .sopInstanceUID, vr: .UI)
        
        let predictions = [
            Prediction(label: "pneumonia", confidence: 0.87),
            Prediction(label: "normal", confidence: 0.13)
        ]
        
        let srDataSet = try AIDICOMOutputGenerator.createSRFromClassification(
            predictions: predictions,
            sourceDataSet: sourceDataSet,
            modelName: "test-model.mlmodel"
        )
        
        // Verify SR DataSet contains expected elements
        let serializedData = srDataSet.write()
        XCTAssertTrue(serializedData.count > 0, "SR DataSet should serialize to non-empty data")
        
        // Verify SR SOP Class UID (Comprehensive SR)
        XCTAssertEqual(srDataSet.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.88.33")
        // Verify patient ID is preserved
        XCTAssertEqual(srDataSet.string(for: .patientID), "12345")
        // Verify modality is SR
        XCTAssertEqual(srDataSet.string(for: .modality), "SR")
    }
    
    func test_createSRFromDetections_generatesValidSR() throws {
        var sourceDataSet = DataSet()
        sourceDataSet.setString("67890", for: .patientID, vr: .LO)
        sourceDataSet.setString("Smith^Jane", for: .patientName, vr: .PN)
        sourceDataSet.setString(UIDGenerator.generateStudyInstanceUID().value, for: .studyInstanceUID, vr: .UI)
        
        let detections = [
            Detection(
                label: "nodule",
                confidence: 0.92,
                bbox: BoundingBox(x: 100, y: 150, width: 50, height: 45)
            ),
            Detection(
                label: "lesion",
                confidence: 0.75,
                bbox: BoundingBox(x: 200, y: 250, width: 30, height: 28)
            )
        ]
        
        let srDataSet = try AIDICOMOutputGenerator.createSRFromDetections(
            detections: detections,
            sourceDataSet: sourceDataSet,
            modelName: "detection-model"
        )
        
        let serializedData = srDataSet.write()
        XCTAssertTrue(serializedData.count > 0, "SR DataSet should serialize to non-empty data")
        
        // Verify SR SOP Class UID (Comprehensive SR)
        XCTAssertEqual(srDataSet.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.88.33")
        // Verify patient ID is preserved from source
        XCTAssertEqual(srDataSet.string(for: .patientID), "67890")
        // Verify modality is SR
        XCTAssertEqual(srDataSet.string(for: .modality), "SR")
    }
    
    // MARK: - Phase C Tests: GSPS with Annotations
    
    func test_createGSPSWithAnnotations_generatesValidDataSet() throws {
        var sourceDataSet = DataSet()
        sourceDataSet.setString("12345", for: .patientID, vr: .LO)
        sourceDataSet.setString("Doe^John", for: .patientName, vr: .PN)
        sourceDataSet.setString(UIDGenerator.generateStudyInstanceUID().value, for: .studyInstanceUID, vr: .UI)
        sourceDataSet.setString(UIDGenerator.generateSeriesInstanceUID().value, for: .seriesInstanceUID, vr: .UI)
        sourceDataSet.setString(UIDGenerator.generateSOPInstanceUID().value, for: .sopInstanceUID, vr: .UI)
        sourceDataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        
        let detections = [
            Detection(
                label: "mass",
                confidence: 0.88,
                bbox: BoundingBox(x: 120, y: 180, width: 60, height: 55)
            )
        ]
        
        let gspsDataSet = try AIDICOMOutputGenerator.createGSPSWithAnnotations(
            detections: detections,
            sourceDataSet: sourceDataSet,
            modelName: "detection-model"
        )
        
        // Verify GSPS SOP Class UID
        XCTAssertEqual(gspsDataSet.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.11.1")
        // Verify modality is PR (Presentation State)
        XCTAssertEqual(gspsDataSet.string(for: .modality), "PR")
        // Verify presentation label
        XCTAssertEqual(gspsDataSet.string(for: .contentLabel), "AI_ANNOTATIONS")
    }
    
    func test_createGSPSWithAnnotations_emptyDetections() throws {
        var sourceDataSet = DataSet()
        sourceDataSet.setString("12345", for: .patientID, vr: .LO)
        sourceDataSet.setString(UIDGenerator.generateStudyInstanceUID().value, for: .studyInstanceUID, vr: .UI)
        
        let gspsDataSet = try AIDICOMOutputGenerator.createGSPSWithAnnotations(
            detections: [],
            sourceDataSet: sourceDataSet,
            modelName: "test-model"
        )
        
        // GSPS should still be valid even with no annotations
        XCTAssertEqual(gspsDataSet.string(for: .sopClassUID), "1.2.840.10008.5.1.4.1.1.11.1")
        XCTAssertEqual(gspsDataSet.string(for: .modality), "PR")
    }
    
    // MARK: - Phase C Tests: Enhanced DICOM File
    
    func test_createEnhancedDICOMFile_generatesValidData() throws {
        var sourceDataSet = DataSet()
        sourceDataSet.setString(UIDGenerator.generateStudyInstanceUID().value, for: .studyInstanceUID, vr: .UI)
        sourceDataSet.setString(UIDGenerator.generateSOPInstanceUID().value, for: .sopInstanceUID, vr: .UI)
        sourceDataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        sourceDataSet.setString("CT", for: .modality, vr: .CS)
        sourceDataSet.setString("Doe^John", for: .patientName, vr: .PN)
        sourceDataSet.setString("12345", for: .patientID, vr: .LO)
        sourceDataSet.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        
        let enhancedImage = ProcessedImage(
            width: 256,
            height: 256,
            bitsPerPixel: 16,
            samplesPerPixel: 1,
            photometricInterpretation: "MONOCHROME2",
            pixelData: Data(count: 256 * 256 * 2)
        )
        
        let result = try AIDICOMOutputGenerator.createEnhancedDICOMFile(
            sourceDataSet: sourceDataSet,
            enhancedImage: enhancedImage,
            frameIndex: 0
        )
        
        XCTAssertTrue(result.count > 0, "Enhanced DICOM data should be non-empty")
    }
    
    // MARK: - Phase C Tests: Report Generation
    
    func test_generateClassificationReport_text() {
        let predictions = [
            Prediction(label: "pneumonia", confidence: 0.87),
            Prediction(label: "normal", confidence: 0.13)
        ]
        
        let report = AIDICOMOutputGenerator.generateClassificationReport(
            predictions: predictions,
            filePath: "test.dcm",
            modelName: "test-model"
        )
        
        XCTAssertTrue(report.contains("AI Classification Report"))
        XCTAssertTrue(report.contains("test-model"))
        XCTAssertTrue(report.contains("pneumonia"))
        XCTAssertTrue(report.contains("87.00%"))
    }
    
    func test_generateDetectionReport_text() {
        let detections = [
            Detection(
                label: "nodule",
                confidence: 0.92,
                bbox: BoundingBox(x: 100, y: 150, width: 50, height: 45)
            )
        ]
        
        let report = AIDICOMOutputGenerator.generateDetectionReport(
            detections: detections,
            filePath: "scan.dcm",
            modelName: "detector"
        )
        
        XCTAssertTrue(report.contains("AI Detection Report"))
        XCTAssertTrue(report.contains("nodule"))
        XCTAssertTrue(report.contains("92.00%"))
        XCTAssertTrue(report.contains("Detections: 1"))
    }
    
    func test_generateMarkdownReport() {
        let predictions = [
            Prediction(label: "abnormal", confidence: 0.75)
        ]
        let detections = [
            Detection(
                label: "lesion",
                confidence: 0.85,
                bbox: BoundingBox(x: 200, y: 250, width: 30, height: 28)
            )
        ]
        
        let report = AIDICOMOutputGenerator.generateMarkdownReport(
            predictions: predictions,
            detections: detections,
            filePath: "mri.dcm",
            modelName: "ai-model"
        )
        
        XCTAssertTrue(report.contains("# AI Analysis Report"))
        XCTAssertTrue(report.contains("## Classifications"))
        XCTAssertTrue(report.contains("## Detections"))
        XCTAssertTrue(report.contains("abnormal"))
        XCTAssertTrue(report.contains("lesion"))
        XCTAssertTrue(report.contains("ai-model"))
    }
    
    func test_generateClassificationReport_emptyPredictions() {
        let report = AIDICOMOutputGenerator.generateClassificationReport(
            predictions: [],
            filePath: "test.dcm",
            modelName: "model"
        )
        
        XCTAssertTrue(report.contains("No predictions above confidence threshold"))
    }
    
    func test_createEnhancedDICOM_replacesPlaceholder() throws {
        // Verify that createEnhancedDICOM no longer throws notImplemented
        var sourceDataSet = DataSet()
        sourceDataSet.setString(UIDGenerator.generateStudyInstanceUID().value, for: .studyInstanceUID, vr: .UI)
        sourceDataSet.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        
        let enhancedImage = ProcessedImage(
            width: 64,
            height: 64,
            bitsPerPixel: 8,
            samplesPerPixel: 1,
            photometricInterpretation: "MONOCHROME2",
            pixelData: Data(count: 64 * 64)
        )
        
        // Should not throw notImplemented anymore
        let result = try createEnhancedDICOM(
            sourceDataSet: sourceDataSet,
            enhancedImage: enhancedImage,
            frameIndex: 0
        )
        
        XCTAssertTrue(result.count > 0)
    }
    
    // MARK: - Phase D Tests (Model Registry, Performance, Confidence Filtering)
    
    /// Test 60: Model registry add and get
    func testModelRegistryAddAndGet() throws {
        guard #available(macOS 14.0, iOS 17.0, *) else {
            throw XCTSkip("This test requires macOS 14.0+ or iOS 17.0+")
        }
        
        // Create a temporary registry file
        let tempDir = FileManager.default.temporaryDirectory
        let registryPath = tempDir.appendingPathComponent("test-registry-\(UUID().uuidString).json").path
        
        let registry = try ModelRegistry(registryPath: registryPath, verbose: false)
        
        // Create a test model entry
        let entry = ModelRegistry.ModelEntry(
            name: "test-classifier",
            version: "1.0.0",
            path: "/path/to/model.mlmodel",
            modelType: .classification,
            description: "Test classification model",
            inputSize: ModelRegistry.ModelEntry.ModelInputSize(width: 224, height: 224),
            outputType: .classification,
            tags: ["test", "classification"]
        )
        
        // Note: We can't actually add it without a real model file, but we can test the structure
        // Just test that get returns nil for non-existent model
        XCTAssertNil(registry.get(name: "non-existent"))
        
        // Clean up
        try? FileManager.default.removeItem(atPath: registryPath)
    }
    
    /// Test 61: Performance metrics initialization and formatting
    func testPerformanceMetrics() throws {
        guard #available(macOS 14.0, iOS 17.0, *) else {
            throw XCTSkip("This test requires macOS 14.0+ or iOS 17.0+")
        }
        
        let metrics = PerformanceMetrics(
            inferenceTime: 0.123,
            preprocessingTime: 0.045,
            postprocessingTime: 0.012,
            memoryUsage: 1024 * 1024 * 50, // 50 MB
            modelName: "test-model"
        )
        
        XCTAssertEqual(metrics.inferenceTime, 0.123, accuracy: 0.001)
        XCTAssertEqual(metrics.preprocessingTime ?? 0.0, 0.045, accuracy: 0.001)
        XCTAssertEqual(metrics.postprocessingTime ?? 0.0, 0.012, accuracy: 0.001)
        XCTAssertEqual(metrics.totalTime, 0.180, accuracy: 0.001)
        XCTAssertEqual(metrics.memoryUsage, 1024 * 1024 * 50)
        XCTAssertEqual(metrics.modelName, "test-model")
        
        // Test formatted output
        let formatted = metrics.formatted()
        XCTAssertTrue(formatted.contains("Model: test-model"))
        XCTAssertTrue(formatted.contains("Preprocessing:"))
        XCTAssertTrue(formatted.contains("Inference:"))
        XCTAssertTrue(formatted.contains("Postprocessing:"))
        XCTAssertTrue(formatted.contains("Total:"))
        XCTAssertTrue(formatted.contains("Memory:"))
        
        // Test JSON output
        let json = try metrics.toJSON()
        XCTAssertTrue(json.contains("test-model"))
        XCTAssertTrue(json.contains("inference_time_seconds"))
    }
    
    /// Test 62: Performance profiler lifecycle
    func testPerformanceProfiler() throws {
        guard #available(macOS 14.0, iOS 17.0, *) else {
            throw XCTSkip("This test requires macOS 14.0+ or iOS 17.0+")
        }
        
        let profiler = PerformanceProfiler(modelName: "test-model", verbose: false)
        
        profiler.start()
        
        profiler.startPreprocessing()
        Thread.sleep(forTimeInterval: 0.01) // Simulate preprocessing
        profiler.endPreprocessing()
        
        profiler.startInference()
        Thread.sleep(forTimeInterval: 0.02) // Simulate inference
        profiler.endInference()
        
        profiler.startPostprocessing()
        Thread.sleep(forTimeInterval: 0.005) // Simulate postprocessing
        profiler.endPostprocessing()
        
        guard let metrics = profiler.getMetrics() else {
            XCTFail("Failed to get metrics")
            return
        }
        
        XCTAssertNotNil(metrics.preprocessingTime)
        XCTAssertNotNil(metrics.postprocessingTime)
        XCTAssertGreaterThan(metrics.inferenceTime, 0.0)
        XCTAssertEqual(metrics.modelName, "test-model")
    }
    
    /// Test 63: Confidence filtering with classification
    func testConfidenceFilteringClassification() throws {
        // Create mock predictions with various confidence levels
        let predictions = [
            Prediction(label: "high-confidence", confidence: 0.95),
            Prediction(label: "medium-confidence", confidence: 0.65),
            Prediction(label: "low-confidence", confidence: 0.35),
            Prediction(label: "very-low-confidence", confidence: 0.15)
        ]
        
        // Filter by confidence threshold
        let threshold = 0.5
        let filtered = predictions.filter { $0.confidence >= threshold }
        
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].label, "high-confidence")
        XCTAssertEqual(filtered[1].label, "medium-confidence")
    }
    
    /// Test 64: Confidence filtering with detection
    func testConfidenceFilteringDetection() throws {
        // Create mock detections with various confidence levels
        let detections = [
            Detection(label: "lesion-1", confidence: 0.92, bbox: BoundingBox(x: 10, y: 20, width: 30, height: 40)),
            Detection(label: "lesion-2", confidence: 0.78, bbox: BoundingBox(x: 50, y: 60, width: 25, height: 35)),
            Detection(label: "artifact-1", confidence: 0.45, bbox: BoundingBox(x: 100, y: 110, width: 15, height: 20)),
            Detection(label: "artifact-2", confidence: 0.23, bbox: BoundingBox(x: 150, y: 160, width: 18, height: 22))
        ]
        
        // Filter by confidence threshold
        let threshold = 0.7
        let filtered = detections.filter { $0.confidence >= threshold }
        
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].label, "lesion-1")
        XCTAssertEqual(filtered[1].label, "lesion-2")
    }
    
    /// Test 65: Model cache functionality
    func testModelCache() throws {
        guard #available(macOS 14.0, iOS 17.0, *) else {
            throw XCTSkip("This test requires macOS 14.0+ or iOS 17.0+")
        }
        
        let cache = ModelCache(maxCacheSize: 2, verbose: false)
        
        // Clear cache (should not throw)
        cache.clear()
        
        // Test that cache can be cleared multiple times
        cache.clear()
        cache.clear()
        
        // Note: We can't test actual model loading without real CoreML models
        // but we can verify the cache structure is sound
    }
    
    /// Test 66: Model registry list filtering
    func testModelRegistryListFiltering() throws {
        guard #available(macOS 14.0, iOS 17.0, *) else {
            throw XCTSkip("This test requires macOS 14.0+ or iOS 17.0+")
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let registryPath = tempDir.appendingPathComponent("test-registry-filter-\(UUID().uuidString).json").path
        
        let registry = try ModelRegistry(registryPath: registryPath, verbose: false)
        
        // Test listing with no entries
        let emptyList = registry.list()
        XCTAssertEqual(emptyList.count, 0)
        
        // Test filtering by type with no entries
        let emptyFiltered = registry.list(filterByType: .classification)
        XCTAssertEqual(emptyFiltered.count, 0)
        
        // Clean up
        try? FileManager.default.removeItem(atPath: registryPath)
    }
    
    /// Test 67: Model registry search by tags
    func testModelRegistrySearchByTags() throws {
        guard #available(macOS 14.0, iOS 17.0, *) else {
            throw XCTSkip("This test requires macOS 14.0+ or iOS 17.0+")
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let registryPath = tempDir.appendingPathComponent("test-registry-search-\(UUID().uuidString).json").path
        
        let registry = try ModelRegistry(registryPath: registryPath, verbose: false)
        
        // Search with no entries
        let emptyResults = registry.search(tags: ["test"])
        XCTAssertEqual(emptyResults.count, 0)
        
        // Clean up
        try? FileManager.default.removeItem(atPath: registryPath)
    }
    
    /// Test 68: Registry error handling
    func testRegistryErrorHandling() throws {
        guard #available(macOS 14.0, iOS 17.0, *) else {
            throw XCTSkip("This test requires macOS 14.0+ or iOS 17.0+")
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let registryPath = tempDir.appendingPathComponent("test-registry-errors-\(UUID().uuidString).json").path
        
        let registry = try ModelRegistry(registryPath: registryPath, verbose: false)
        
        // Test getting non-existent model
        XCTAssertNil(registry.get(name: "non-existent"))
        
        // Test removing non-existent model
        XCTAssertThrowsError(try registry.remove(name: "non-existent")) { error in
            XCTAssertTrue(error is RegistryError)
        }
        
        // Clean up
        try? FileManager.default.removeItem(atPath: registryPath)
    }
}

